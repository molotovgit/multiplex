//! Connecting and logging in, against the in-process test server.

mod support;

use support::{Logins, TestServer, PASSWORD};
use tokio::net::TcpListener;
use multiplex_core::api::keys::KeyKind;
use multiplex_core::api::ssh_types::{ConnectError, Credentials, JumpHost};
use multiplex_core::engine::keys::KeyFactory;
use multiplex_core::engine::ssh::Connector;

fn password_logins() -> Logins {
    Logins { password: Some(PASSWORD.into()), ..Default::default() }
}

#[tokio::test]
async fn first_visit_reports_the_server_key_then_connects_once_trusted() {
    let server = TestServer::start(password_logins()).await;
    let mut options = server.options();
    options.trusted_host_keys.clear();

    let Err(ConnectError::HostKeyUnknown { key, port, .. }) = Connector::connect(options.clone()).await else {
        panic!("expected an unknown host key");
    };
    assert_eq!(port, server.port);
    assert_eq!(key.fingerprint, server.host_key.public_key().fingerprint(Default::default()).to_string());

    // The user accepts the key; the next attempt goes through.
    options.trusted_host_keys = vec![key.public_key];
    let conn = Connector::connect(options).await.expect("connects after trusting");
    assert_eq!(conn.info().host_key.fingerprint, key.fingerprint);
    assert!(!conn.is_closed());
}

#[tokio::test]
async fn a_different_server_key_is_refused() {
    let server = TestServer::start(password_logins()).await;
    let other = TestServer::start(password_logins()).await;
    let mut options = server.options();
    options.trusted_host_keys = vec![other.host_key_line()];
    assert!(matches!(Connector::connect(options).await, Err(ConnectError::HostKeyChanged { .. })));
}

#[tokio::test]
async fn logs_in_with_password_and_refuses_a_wrong_one() {
    let server = TestServer::start(password_logins()).await;
    Connector::connect(server.options()).await.expect("right password works");

    let mut options = server.options();
    options.credentials.password = Some("wrong".into());
    let Err(ConnectError::AuthFailed { tried, .. }) = Connector::connect(options).await else {
        panic!("expected a refused login");
    };
    assert!(tried.contains(&"password".to_string()));
}

#[tokio::test]
async fn falls_back_to_keyboard_interactive() {
    let logins = Logins { keyboard_interactive_only: true, ..password_logins() };
    let server = TestServer::start(logins).await;
    Connector::connect(server.options()).await.expect("password through keyboard-interactive");
}

#[tokio::test]
async fn logs_in_with_a_private_key() {
    let pair = KeyFactory::generate(KeyKind::Ed25519, "test", Some("pass")).unwrap();
    let public = russh::keys::PublicKey::from_openssh(&pair.public_openssh).unwrap();
    let server = TestServer::start(Logins { authorized_key: Some(public), ..Default::default() }).await;

    let mut options = server.options();
    options.credentials = Credentials { private_key: Some(pair.private_pem.clone()), key_passphrase: Some("pass".into()), password: None };
    Connector::connect(options.clone()).await.expect("key login works");

    options.credentials.key_passphrase = None;
    assert!(matches!(Connector::connect(options).await, Err(ConnectError::KeyNeedsPassphrase)));
}

#[tokio::test]
async fn runs_a_command_and_collects_its_output() {
    let server = TestServer::start(password_logins()).await;
    let conn = Connector::connect(server.options()).await.unwrap();

    let out = conn.exec("echo hello", 1024).await.unwrap();
    assert_eq!((out.stdout.as_str(), out.exit_code), ("hello\n", Some(0)));

    let out = conn.exec("fail", 1024).await.unwrap();
    assert_eq!((out.stderr.as_str(), out.exit_code), ("it broke\n", Some(3)));

    let out = conn.exec("echo 0123456789", 4).await.unwrap();
    assert!(out.truncated);
    assert_eq!(out.stdout, "0123");
    conn.disconnect().await;
}

#[tokio::test]
async fn connects_through_a_jump_host() {
    let jump = TestServer::start(password_logins()).await;
    let target = TestServer::start(password_logins()).await;
    let mut options = target.options();
    let jump_options = jump.options();
    options.jump = Some(JumpHost {
        host: jump_options.host,
        port: jump_options.port,
        username: jump_options.username,
        credentials: jump_options.credentials,
        trusted_host_keys: jump_options.trusted_host_keys,
    });
    let conn = Connector::connect(options).await.expect("connects through the jump host");
    assert_eq!(conn.info().via.as_deref(), Some("127.0.0.1"));
    let out = conn.exec("echo via jump", 1024).await.unwrap();
    assert_eq!(out.stdout, "via jump\n");
}

#[tokio::test]
async fn reports_network_errors_and_timeouts() {
    // Nothing listens on this port any more.
    let closed_port = {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        listener.local_addr().unwrap().port()
    };
    let server = TestServer::start(password_logins()).await;
    let mut options = server.options();
    options.port = closed_port;
    assert!(matches!(Connector::connect(options.clone()).await, Err(ConnectError::Network { .. })));

    // A port that accepts the connection but never speaks SSH.
    let silent = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
    options.port = silent.local_addr().unwrap().port();
    options.connect_timeout_secs = 1;
    assert_eq!(Connector::connect(options).await.err(), Some(ConnectError::Timeout));
    drop(silent);
}
