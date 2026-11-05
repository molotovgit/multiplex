//! Remote port forwarding (`ssh -R`): the server listens on a port and
//! hands every incoming connection to us; we connect it to a service on
//! this device's network.
//!
//! The server only tells us "a connection arrived for address:port". This
//! router keeps the list of active forwards so we know where each one goes.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use russh::client::{ChannelOpenHandle, Msg};
use russh::{Channel, ChannelOpenFailure};
use tokio::net::TcpStream;

use super::pipe::{Pipe, TunnelCounters};
use crate::engine::runtime::AsyncRuntime;

/// Where connections for one remote port should go.
struct Route {
    local_host: String,
    local_port: u16,
    counters: Arc<TunnelCounters>,
}

/// All remote forwards of one SSH connection.
#[derive(Default)]
pub struct RemoteForwardRouter {
    routes: Mutex<HashMap<u32, Vec<(String, Route)>>>,
}

impl RemoteForwardRouter {
    /// Starts sending connections for `bind_addr:bind_port` on the server to
    /// `local_host:local_port`.
    pub fn add(&self, bind_addr: &str, bind_port: u32, local_host: &str, local_port: u16, counters: Arc<TunnelCounters>) {
        let route = Route {
            local_host: local_host.to_owned(),
            local_port,
            counters,
        };
        self.routes
            .lock()
            .expect("router lock")
            .entry(bind_port)
            .or_default()
            .push((bind_addr.to_owned(), route));
    }

    pub fn remove(&self, bind_addr: &str, bind_port: u32) {
        let mut routes = self.routes.lock().expect("router lock");
        if let Some(list) = routes.get_mut(&bind_port) {
            list.retain(|(addr, _)| addr != bind_addr);
            if list.is_empty() {
                routes.remove(&bind_port);
            }
        }
    }

    /// Called when the server opens a channel for a forwarded connection.
    /// Unknown ports are refused.
    pub async fn accept(&self, channel: Channel<Msg>, address: &str, port: u32, reply: ChannelOpenHandle) {
        let target = {
            let routes = self.routes.lock().expect("router lock");
            routes.get(&port).and_then(|list| {
                // Prefer the exact address; servers sometimes report a
                // different spelling (0.0.0.0, localhost), so fall back to
                // the only forward on that port.
                list.iter()
                    .find(|(addr, _)| addr == address)
                    .or_else(|| (list.len() == 1).then(|| &list[0]))
                    .map(|(_, r)| (r.local_host.clone(), r.local_port, r.counters.clone()))
            })
        };
        let Some((host, local_port, counters)) = target else {
            reply.reject(ChannelOpenFailure::AdministrativelyProhibited).await;
            return;
        };
        match TcpStream::connect((host.as_str(), local_port)).await {
            Ok(socket) => {
                reply.accept().await;
                AsyncRuntime::spawn(async move {
                    let _ = socket.set_nodelay(true);
                    Pipe::run(socket, channel.into_stream(), &counters).await;
                });
            }
            Err(_) => reply.reject(ChannelOpenFailure::ConnectFailed).await,
        }
    }
}
