//! Optional end-to-end test of QR pairing against a real computer.
//!
//! Skipped unless MPX_PAIR_CODE holds a fresh code from
//! `multiplex pair --code-only` on a computer this machine can reach on
//! its home-network address. It pairs a throwaway key as "pairing-test";
//! remove it afterwards with `multiplex unpair pairing-test`.

use multiplex_core::api::keys::KeyKind;
use multiplex_core::api::ssh_types::{ConnectError, ConnectOptions, Credentials};
use multiplex_core::engine::keys::KeyFactory;
use multiplex_core::engine::pairing::{self, PairError};
use multiplex_core::engine::ssh::Connector;
use multiplex_proto::PairingCode;

#[tokio::test(flavor = "multi_thread")]
async fn pairs_logs_in_and_the_code_works_once() {
    let Ok(text) = std::env::var("MPX_PAIR_CODE") else {
        eprintln!("pairing test skipped: set MPX_PAIR_CODE");
        return;
    };
    let code = PairingCode::decode(&text, pairing::now_unix()).expect("a fresh code");
    let phone = KeyFactory::generate(KeyKind::Ed25519, "pairing-test", None).unwrap();

    // 1. Pair.
    let paired = pairing::register(&code, &phone.public_openssh, "pairing-test", false).await.expect("pairing should work");
    eprintln!("paired with {} at {} (features {:?})", paired.computer, paired.address, paired.features);
    assert_eq!(paired.computer, code.n);

    // 2. The phone's own key now logs in, with the host key from the code.
    let options = ConnectOptions {
        host: paired.address.clone(),
        port: code.p,
        username: code.u.clone(),
        credentials: Credentials { private_key: Some(phone.private_pem.clone()), ..Default::default() },
        trusted_host_keys: vec![code.host_key_line()],
        keepalive_secs: 0,
        connect_timeout_secs: 10,
        jump: None,
        forward_agent: false,
        via_tailscale: false,
    };
    let conn = Connector::connect(options.clone()).await.expect("the new key should log in");
    let out = conn.exec("echo paired-login-ok", 256).await.unwrap();
    assert_eq!(out.stdout.trim(), "paired-login-ok");
    conn.disconnect().await;

    // 3. The code is used up: the one-time key no longer logs in.
    let other = KeyFactory::generate(KeyKind::Ed25519, "intruder", None).unwrap();
    let again = pairing::register(&code, &other.public_openssh, "intruder", false).await;
    assert!(matches!(again, Err(PairError::CodeRefused)), "a used code must be refused, got {again:?}");

    // 4. A wrong host key in the code is noticed before anything is sent.
    let mut forged = code.clone();
    forged.h = base64_of([1u8; 32]);
    let wrong = pairing::register(&forged, &other.public_openssh, "intruder", false).await;
    assert!(matches!(wrong, Err(PairError::WrongComputer)), "got {wrong:?}");

    // 5. The intruder's key cannot log in.
    let mut intruder = options;
    intruder.credentials.private_key = Some(other.private_pem);
    assert!(matches!(Connector::connect(intruder).await, Err(ConnectError::AuthFailed { .. })));
}

fn base64_of(bytes: [u8; 32]) -> String {
    use base64::Engine;
    base64::engine::general_purpose::STANDARD.encode(bytes)
}
