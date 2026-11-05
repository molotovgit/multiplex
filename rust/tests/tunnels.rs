//! Local, remote and dynamic (SOCKS5) forwarding through the test server,
//! each reaching a small TCP echo service.

mod support;

use std::sync::Arc;
use std::time::Duration;

use support::{echo_service, Logins, TestServer, PASSWORD};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use multiplex_core::api::tunnel_types::{TunnelKind, TunnelSpec};
use multiplex_core::engine::ssh::{Connection, Connector};
use multiplex_core::engine::tunnel::Tunnel;

async fn connect() -> Arc<Connection> {
    let server = TestServer::start(Logins { password: Some(PASSWORD.into()), ..Default::default() }).await;
    Arc::new(Connector::connect(server.options()).await.unwrap())
}

fn spec(kind: TunnelKind, target_port: u16) -> TunnelSpec {
    TunnelSpec { kind, bind_host: "127.0.0.1".into(), bind_port: 0, target_host: "127.0.0.1".into(), target_port }
}

/// Sends `ping` and expects it back.
async fn ping(stream: &mut TcpStream) {
    stream.write_all(b"ping").await.unwrap();
    let mut answer = [0u8; 4];
    tokio::time::timeout(Duration::from_secs(5), stream.read_exact(&mut answer)).await.expect("no answer").unwrap();
    assert_eq!(&answer, b"ping");
}

#[tokio::test]
async fn local_forward_reaches_a_service_behind_the_server() {
    let echo = echo_service().await;
    let tunnel = Tunnel::start(connect().await, spec(TunnelKind::Local, echo)).await.unwrap();
    assert_ne!(tunnel.bound_port(), 0);

    let mut client = TcpStream::connect(("127.0.0.1", tunnel.bound_port())).await.unwrap();
    ping(&mut client).await;
    drop(client);

    tokio::time::sleep(Duration::from_millis(200)).await;
    let stats = tunnel.stats();
    assert_eq!(stats.connections_total, 1);
    assert_eq!(stats.connections_active, 0);
    assert_eq!((stats.bytes_sent, stats.bytes_received), (4, 4));

    tunnel.stop().await;
    assert!(!tunnel.is_running());
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert!(TcpStream::connect(("127.0.0.1", tunnel.bound_port())).await.is_err(), "stopped tunnel still accepts");
}

#[tokio::test]
async fn dynamic_forward_works_as_a_socks5_proxy() {
    let echo = echo_service().await;
    let tunnel = Tunnel::start(connect().await, spec(TunnelKind::Dynamic, 0)).await.unwrap();

    let mut client = TcpStream::connect(("127.0.0.1", tunnel.bound_port())).await.unwrap();
    client.write_all(&[5, 1, 0]).await.unwrap();
    let mut greeting = [0u8; 2];
    client.read_exact(&mut greeting).await.unwrap();
    assert_eq!(greeting, [5, 0]);

    let mut request = vec![5, 1, 0, 3, 9];
    request.extend_from_slice(b"127.0.0.1");
    request.extend_from_slice(&echo.to_be_bytes());
    client.write_all(&request).await.unwrap();
    let mut reply = [0u8; 10];
    client.read_exact(&mut reply).await.unwrap();
    assert_eq!(reply[1], 0, "SOCKS reply was not success");

    ping(&mut client).await;
}

#[tokio::test]
async fn remote_forward_brings_server_side_connections_here() {
    let echo = echo_service().await;
    let tunnel = Tunnel::start(connect().await, spec(TunnelKind::Remote, echo)).await.unwrap();
    // The test server listens on the same machine, so we can play the
    // part of someone connecting to the server's forwarded port.
    let mut visitor = TcpStream::connect(("127.0.0.1", tunnel.bound_port())).await.unwrap();
    ping(&mut visitor).await;
    tunnel.stop().await;
}
