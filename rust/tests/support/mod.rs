//! A tiny SSH server that runs inside the test process.
//!
//! It is just enough server to test the client for real: password and key
//! login, an echo "shell", a few fake commands, and TCP forwarding in both
//! directions. Each test starts its own server on a free port.

#![allow(dead_code)]

use std::sync::Arc;

use russh::keys::{Algorithm, PrivateKey, PublicKey};
use russh::server::{self, Auth, ChannelOpenHandle, Msg, Server as _, Session, VerifiedPublicKey};
use russh::{Channel, ChannelId};
use tokio::net::{TcpListener, TcpStream};

use vaultterm_core::api::ssh_types::{ConnectOptions, Credentials};

pub const USER: &str = "alice";
pub const PASSWORD: &str = "secret";

/// Who may log in to a [`TestServer`].
#[derive(Clone, Default)]
pub struct Logins {
    pub password: Option<String>,
    pub authorized_key: Option<PublicKey>,
    /// Accept the password only through keyboard-interactive.
    pub keyboard_interactive_only: bool,
}

/// A running in-process SSH server.
pub struct TestServer {
    pub port: u16,
    pub host_key: PrivateKey,
}

impl TestServer {
    pub async fn start(logins: Logins) -> Self {
        let host_key = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
        let config = Arc::new(server::Config {
            keys: vec![host_key.clone()],
            auth_rejection_time: std::time::Duration::from_millis(1),
            auth_rejection_time_initial: Some(std::time::Duration::ZERO),
            ..Default::default()
        });
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let mut factory = ServerFactory { logins };
        tokio::spawn(async move {
            let _ = factory.run_on_socket(config, &listener).await;
        });
        Self { port, host_key }
    }

    /// The server's key as an OpenSSH line, as the app would store it.
    pub fn host_key_line(&self) -> String {
        self.host_key.public_key().to_openssh().unwrap()
    }

    /// Options that trust this server and log in with the password.
    pub fn options(&self) -> ConnectOptions {
        ConnectOptions {
            host: "127.0.0.1".into(),
            port: self.port,
            username: USER.into(),
            credentials: Credentials { password: Some(PASSWORD.into()), ..Default::default() },
            trusted_host_keys: vec![self.host_key_line()],
            keepalive_secs: 0,
            connect_timeout_secs: 10,
            jump: None,
        }
    }
}

struct ServerFactory {
    logins: Logins,
}

impl server::Server for ServerFactory {
    type Handler = ClientConn;

    fn new_client(&mut self, _: Option<std::net::SocketAddr>) -> ClientConn {
        ClientConn { logins: self.logins.clone(), shells: Default::default() }
    }
}

/// One client connection on the server side.
pub struct ClientConn {
    logins: Logins,
    /// Channels running the echo shell. Data on other channels (tunnels)
    /// belongs to the pipe tasks and must not be echoed.
    shells: std::collections::HashSet<ChannelId>,
}

impl server::Handler for ClientConn {
    type Error = russh::Error;

    async fn auth_password(&mut self, user: &str, password: &str) -> Result<Auth, Self::Error> {
        let ok = !self.logins.keyboard_interactive_only
            && user == USER
            && self.logins.password.as_deref() == Some(password);
        Ok(if ok { Auth::Accept } else { Auth::reject() })
    }

    async fn auth_publickey(&mut self, user: &str, key: VerifiedPublicKey<'_>) -> Result<Auth, Self::Error> {
        let ok = user == USER
            && self.logins.authorized_key.as_ref().is_some_and(|k| k.key_data() == key.public_key.key_data());
        Ok(if ok { Auth::Accept } else { Auth::reject() })
    }

    async fn auth_keyboard_interactive<'a>(
        &'a mut self,
        user: &str,
        _submethods: &str,
        response: Option<server::Response<'a>>,
    ) -> Result<Auth, Self::Error> {
        let Some(expected) = self.logins.password.clone() else { return Ok(Auth::reject()) };
        match response {
            None => Ok(Auth::Partial {
                name: "".into(),
                instructions: "".into(),
                prompts: vec![("Password: ".into(), false)].into(),
            }),
            Some(mut answers) => {
                let given = answers.next().map(|a| String::from_utf8_lossy(&a).into_owned());
                let ok = user == USER && given.as_deref() == Some(expected.as_str());
                Ok(if ok { Auth::Accept } else { Auth::reject() })
            }
        }
    }

    async fn channel_open_session(&mut self, _channel: Channel<Msg>, reply: ChannelOpenHandle, _session: &mut Session) -> Result<(), Self::Error> {
        reply.accept().await;
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    async fn pty_request(
        &mut self,
        channel: ChannelId,
        _term: &str,
        _cols: u32,
        _rows: u32,
        _pw: u32,
        _ph: u32,
        _modes: &[(russh::Pty, u32)],
        session: &mut Session,
    ) -> Result<(), Self::Error> {
        session.channel_success(channel)?;
        Ok(())
    }

    async fn shell_request(&mut self, channel: ChannelId, session: &mut Session) -> Result<(), Self::Error> {
        session.channel_success(channel)?;
        self.shells.insert(channel);
        session.data(channel, b"welcome\r\n$ ".to_vec())?;
        Ok(())
    }

    /// The "shell" echoes what it gets. Ctrl+D (byte 4) ends it with exit 0.
    async fn data(&mut self, channel: ChannelId, data: &[u8], session: &mut Session) -> Result<(), Self::Error> {
        if !self.shells.contains(&channel) {
            return Ok(());
        }
        if data == [4] {
            session.exit_status_request(channel, 0)?;
            session.eof(channel)?;
            session.close(channel)?;
            return Ok(());
        }
        session.data(channel, data.to_vec())?;
        Ok(())
    }

    async fn window_change_request(
        &mut self,
        channel: ChannelId,
        cols: u32,
        rows: u32,
        _pw: u32,
        _ph: u32,
        session: &mut Session,
    ) -> Result<(), Self::Error> {
        session.data(channel, format!("[resized {cols}x{rows}]").into_bytes())?;
        Ok(())
    }

    /// Fake commands: `echo <text>`, `fail` (stderr + exit 3), anything
    /// else exits 127.
    async fn exec_request(&mut self, channel: ChannelId, command: &[u8], session: &mut Session) -> Result<(), Self::Error> {
        let command = String::from_utf8_lossy(command).into_owned();
        session.channel_success(channel)?;
        let code = if let Some(text) = command.strip_prefix("echo ") {
            session.data(channel, format!("{text}\n").into_bytes())?;
            0
        } else if command == "fail" {
            session.extended_data(channel, 1, b"it broke\n".to_vec())?;
            3
        } else {
            127
        };
        session.exit_status_request(channel, code)?;
        session.eof(channel)?;
        session.close(channel)?;
        Ok(())
    }

    /// `ssh -L` and jump hosts: connect to the requested address and pipe.
    #[allow(clippy::too_many_arguments)]
    async fn channel_open_direct_tcpip(
        &mut self,
        channel: Channel<Msg>,
        host: &str,
        port: u32,
        _originator_address: &str,
        _originator_port: u32,
        reply: ChannelOpenHandle,
        _session: &mut Session,
    ) -> Result<(), Self::Error> {
        match TcpStream::connect((host, port as u16)).await {
            Ok(mut socket) => {
                reply.accept().await;
                tokio::spawn(async move {
                    let mut stream = channel.into_stream();
                    let _ = tokio::io::copy_bidirectional(&mut socket, &mut stream).await;
                });
            }
            Err(_) => reply.reject(russh::ChannelOpenFailure::ConnectFailed).await,
        }
        Ok(())
    }

    /// `ssh -R`: listen on the server side and send connections back.
    async fn tcpip_forward(&mut self, address: &str, port: &mut u32, session: &mut Session) -> Result<bool, Self::Error> {
        let Ok(listener) = TcpListener::bind(("127.0.0.1", *port as u16)).await else { return Ok(false) };
        *port = u32::from(listener.local_addr().unwrap().port());
        let (address, bound) = (address.to_owned(), *port);
        let handle = session.handle();
        tokio::spawn(async move {
            while let Ok((mut socket, peer)) = listener.accept().await {
                let Ok(channel) = handle
                    .channel_open_forwarded_tcpip(address.clone(), bound, peer.ip().to_string(), u32::from(peer.port()))
                    .await
                else {
                    continue;
                };
                tokio::spawn(async move {
                    let mut stream = channel.into_stream();
                    let _ = tokio::io::copy_bidirectional(&mut socket, &mut stream).await;
                });
            }
        });
        Ok(true)
    }
}

/// A plain TCP echo service, the "app" that tunnels lead to.
pub async fn echo_service() -> u16 {
    let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
    let port = listener.local_addr().unwrap().port();
    tokio::spawn(async move {
        while let Ok((mut socket, _)) = listener.accept().await {
            tokio::spawn(async move {
                let (mut read, mut write) = socket.split();
                let _ = tokio::io::copy(&mut read, &mut write).await;
            });
        }
    });
    port
}
