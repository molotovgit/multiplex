//! Optional test that plays a paired phone against a real computer: it
//! logs in with a phone's key, listens on the link as the app does, and
//! answers what the computer asks with the same code the app uses.
//!
//! Skipped unless these are set:
//! - `MPX_PHONE_HOST`, `MPX_PHONE_USER`, `MPX_PHONE_KEY` (the key file of
//!   a phone paired with that computer; `MPX_PHONE_PORT` is optional);
//! - `MPX_PHONE_NAME`: the name that phone is paired under;
//! - `MPX_PHONE_BIN`: the computer's `multiplex` command. The test runs it
//!   itself, so the computer has to be this machine.
//!
//! Use a throwaway key registered for the test, not a real phone's.

use std::process::{Command, Stdio};
use std::sync::Arc;
use std::time::Duration;

use multiplex_core::api::ssh_types::{ConnectError, ConnectOptions, Credentials};
use multiplex_core::engine::share;
use multiplex_core::engine::ssh::{Connection, Connector};
use multiplex_proto::share::{link_command, parse_link_event, LinkEvent};
use russh::ChannelMsg;
use tokio::sync::mpsc;

struct Setup {
    conn: Arc<Connection>,
    key: String,
    name: String,
    bin: String,
}

async fn setup() -> Option<Setup> {
    let host = std::env::var("MPX_PHONE_HOST").ok()?;
    let username = std::env::var("MPX_PHONE_USER").ok()?;
    let key = std::fs::read_to_string(std::env::var("MPX_PHONE_KEY").ok()?).expect("key file");
    let name = std::env::var("MPX_PHONE_NAME").ok()?;
    let bin = std::env::var("MPX_PHONE_BIN").ok()?;
    let port = std::env::var("MPX_PHONE_PORT").ok().and_then(|p| p.parse().ok()).unwrap_or(22);
    let mut opts = ConnectOptions {
        host,
        port,
        username,
        credentials: Credentials { private_key: Some(key.clone()), ..Default::default() },
        trusted_host_keys: vec![],
        keepalive_secs: 10,
        connect_timeout_secs: 20,
        jump: None,
        forward_agent: false,
        via_tailscale: false,
    };
    for _ in 0..3 {
        match Connector::connect(opts.clone()).await {
            Ok(conn) => return Some(Setup { conn: Arc::new(conn), key, name, bin }),
            Err(ConnectError::HostKeyUnknown { key, .. }) => opts.trusted_host_keys = vec![key.public_key],
            Err(e) => panic!("connect failed: {e:?}"),
        }
    }
    panic!("could not settle the host keys");
}

/// Listens on the link, as the app does while connected.
async fn link(conn: &Connection, name: &str) -> mpsc::UnboundedReceiver<LinkEvent> {
    let channel = conn.handle().channel_open_session().await.expect("a channel");
    channel.exec(true, link_command(name).as_bytes()).await.expect("the link starts");
    let (events, heard) = mpsc::unbounded_channel();
    tokio::spawn(async move {
        let (mut reader, _writer) = channel.split();
        let mut pending = Vec::new();
        while let Some(msg) = reader.wait().await {
            if let ChannelMsg::Data { data } = msg {
                pending.extend_from_slice(&data);
                while let Some(end) = pending.iter().position(|b| *b == b'\n') {
                    let line: Vec<u8> = pending.drain(..=end).collect();
                    if let Ok(event) = parse_link_event(&String::from_utf8_lossy(&line)) {
                        if events.send(event).is_err() {
                            return;
                        }
                    }
                }
            }
        }
    });
    // The computer counts the phone as connected once the link's loop runs.
    tokio::time::sleep(Duration::from_millis(600)).await;
    heard
}

/// The next approval the computer asks for.
async fn next_approval(heard: &mut mpsc::UnboundedReceiver<LinkEvent>) -> (String, String, String) {
    loop {
        match tokio::time::timeout(Duration::from_secs(10), heard.recv()).await.expect("the computer asks in time").expect("the link is open") {
            LinkEvent::Approve { id, reason, challenge } => return (id, reason, challenge),
            _ => continue,
        }
    }
}

/// One pretend phone at a time: both tests listen as the same phone.
static ONE_AT_A_TIME: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

#[tokio::test(flavor = "multi_thread")]
async fn a_fingerprint_yes_reaches_the_computer_and_nothing_else_passes() {
    let _alone = ONE_AT_A_TIME.lock().await;
    let Some(Setup { conn, key, name, bin }) = setup().await else {
        eprintln!("phone test skipped: set MPX_PHONE_HOST, MPX_PHONE_USER, MPX_PHONE_KEY, MPX_PHONE_NAME and MPX_PHONE_BIN");
        return;
    };
    let mut heard = link(&conn, &name).await;
    let ask = |what: &str| Command::new(&bin).args(["approve", "--to", &name, what]).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().expect("the computer's command runs");

    // Yes: signed with the phone's key, for exactly what was asked.
    let waiting = ask("the live test");
    let (id, reason, challenge) = next_approval(&mut heard).await;
    assert_eq!(reason, "the live test");
    let signature = share::approval_signature(&key, &id, &reason, &challenge).expect("the phone signs");
    share::approved(&conn, &id, &signature).await.expect("the answer is taken");
    let out = waiting.wait_with_output().unwrap();
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), format!("Approved on {name}."));

    // No.
    let waiting = ask("something else");
    let (id, _, _) = next_approval(&mut heard).await;
    share::approved(&conn, &id, "no").await.unwrap();
    let out = waiting.wait_with_output().unwrap();
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("refused on the phone"));

    // The right key, but a yes to other words than those asked: refused.
    let waiting = ask("delete nothing");
    let (id, _, challenge) = next_approval(&mut heard).await;
    let other = share::approval_signature(&key, &id, "delete everything", &challenge).unwrap();
    share::approved(&conn, &id, &other).await.unwrap();
    let out = waiting.wait_with_output().unwrap();
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("did not come from the paired phone"));

    // An answer to a request that is over is not taken.
    assert!(share::approved(&conn, &id, &other).await.is_err());
}

/// What sudo's PAM file would run (`multiplex approve --pam`), tried
/// without root: the keys file root would keep is a test file here.
/// Needs `MPX_PHONE_KEY`'s public half next to it (`<key file>.pub`).
#[tokio::test(flavor = "multi_thread")]
async fn sudo_takes_only_a_yes_signed_by_the_enrolled_phone() {
    let _alone = ONE_AT_A_TIME.lock().await;
    let Some(Setup { conn, key, name, bin }) = setup().await else {
        return;
    };
    let user = std::env::var("MPX_PHONE_USER").unwrap();
    let Ok(public) = std::fs::read_to_string(format!("{}.pub", std::env::var("MPX_PHONE_KEY").unwrap())) else {
        eprintln!("sudo test skipped: no public key file next to MPX_PHONE_KEY");
        return;
    };
    let public: Vec<&str> = public.split_whitespace().take(2).collect();
    let dir = std::env::temp_dir().join(format!("mpx-sudo-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let keys = dir.join("sudo-keys");
    let enrol = |key_line: &str| std::fs::write(&keys, format!("# test\n{user} {key_line} multiplex:{name}\n")).unwrap();
    enrol(&public.join(" "));
    let mut heard = link(&conn, &name).await;
    let sudo = || {
        Command::new(&bin)
            .args(["approve", "--pam", "--test-keys", keys.to_str().unwrap()])
            .env("PAM_TYPE", "auth")
            .env("PAM_USER", &user)
            .env("PAM_TTY", "/dev/pts/9")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("the computer's command runs")
    };

    // Yes, signed by the enrolled phone for exactly what was asked.
    let waiting = sudo();
    let (id, reason, challenge) = next_approval(&mut heard).await;
    assert!(reason.starts_with("Use sudo on ") && reason.ends_with("(pts/9)"), "{reason}");
    share::approved(&conn, &id, &share::approval_signature(&key, &id, &reason, &challenge).unwrap()).await.unwrap();
    let out = waiting.wait_with_output().unwrap();
    assert!(out.status.success(), "approved: {}", String::from_utf8_lossy(&out.stderr));
    assert!(String::from_utf8_lossy(&out.stdout).contains(&format!("Waiting for {name} to approve")));

    // No.
    let waiting = sudo();
    let (id, _, _) = next_approval(&mut heard).await;
    share::approved(&conn, &id, "no").await.unwrap();
    assert_eq!(waiting.wait_with_output().unwrap().status.code(), Some(1));

    // A yes to other words than those asked.
    let waiting = sudo();
    let (id, _, challenge) = next_approval(&mut heard).await;
    share::approved(&conn, &id, &share::approval_signature(&key, &id, "Use sudo on another computer", &challenge).unwrap()).await.unwrap();
    assert_eq!(waiting.wait_with_output().unwrap().status.code(), Some(1));

    // The phone is paired and signs correctly, but root's file names
    // another key for it: its yes does not count.
    enrol(&multiplex_proto::ed25519_line(&[9u8; 32]));
    let waiting = sudo();
    let (id, reason, challenge) = next_approval(&mut heard).await;
    share::approved(&conn, &id, &share::approval_signature(&key, &id, &reason, &challenge).unwrap()).await.unwrap();
    assert_eq!(waiting.wait_with_output().unwrap().status.code(), Some(1));

    // Nobody enrolled for this user: no at once, without asking anyone.
    std::fs::write(&keys, format!("someone-else {} multiplex:{name}\n", public.join(" "))).unwrap();
    let started = std::time::Instant::now();
    assert_eq!(sudo().wait_with_output().unwrap().status.code(), Some(1));
    assert!(started.elapsed() < Duration::from_secs(2));
    assert!(tokio::time::timeout(Duration::from_millis(500), heard.recv()).await.is_err(), "the phone was not asked");

    // Not asked by PAM to check who it is: no.
    let out = Command::new(&bin).args(["approve", "--pam", "--test-keys", keys.to_str().unwrap()]).env_remove("PAM_TYPE").output().unwrap();
    assert_eq!(out.status.code(), Some(1));
    let _ = std::fs::remove_dir_all(&dir);
}

/// The phone's key used from the computer through `multiplex agent`: ssh
/// lists it, logs in with it and signs with it, and each use is a
/// request the phone reads, shows and signs itself.
#[tokio::test(flavor = "multi_thread")]
async fn the_phones_key_logs_in_and_signs_through_the_agent() {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Mutex;

    let _alone = ONE_AT_A_TIME.lock().await;
    let Some(Setup { conn, key, name, bin }) = setup().await else {
        eprintln!("agent test skipped: set MPX_PHONE_HOST, MPX_PHONE_USER, MPX_PHONE_KEY, MPX_PHONE_NAME and MPX_PHONE_BIN");
        return;
    };
    let public_file = format!("{}.pub", std::env::var("MPX_PHONE_KEY").unwrap());
    let host = format!("{}@{}", std::env::var("MPX_PHONE_USER").unwrap(), std::env::var("MPX_PHONE_HOST").unwrap());
    let work = std::env::temp_dir().join(format!("mpx-agent-test-{}", std::process::id()));
    std::fs::create_dir_all(&work).unwrap();

    // The computer's agent.
    let socket = String::from_utf8(Command::new(&bin).args(["agent", "--socket"]).output().unwrap().stdout).unwrap().trim().to_owned();
    // Stopped when the test ends, however it ends; and it holds none of
    // the test's own pipes.
    struct Agent(std::process::Child, String);
    impl Drop for Agent {
        fn drop(&mut self) {
            let _ = self.0.kill();
            let _ = self.0.wait();
            let _ = std::fs::remove_file(&self.1);
        }
    }
    let log = std::fs::File::create(work.join("agent.log")).unwrap();
    let _agent = Agent(Command::new(&bin).arg("agent").stdin(Stdio::null()).stdout(Stdio::null()).stderr(log).spawn().expect("the agent starts"), socket.clone());
    tokio::time::sleep(Duration::from_millis(300)).await;

    // The phone: it reads each request itself, "shows" it, and signs or refuses.
    let mut heard = link(&conn, &name).await;
    let says_yes = Arc::new(AtomicBool::new(true));
    let shown = Arc::new(Mutex::new(Vec::<String>::new()));
    let (yes, prompts, phone, phone_key) = (says_yes.clone(), shown.clone(), conn.clone(), key.clone());
    tokio::spawn(async move {
        while let Some(event) = heard.recv().await {
            let LinkEvent::Sign { id, data } = event else { continue };
            let answer = match share::signing_request(&phone_key, &data) {
                Some(what) => {
                    prompts.lock().unwrap().push(what);
                    if yes.load(Ordering::SeqCst) { share::signing_signature(&phone_key, &data).unwrap() } else { "no".to_owned() }
                }
                None => "no".to_owned(),
            };
            let _ = share::approved(&phone, &id, &answer).await;
        }
    });

    let ssh_env = |command: &mut Command| {
        command.env("SSH_AUTH_SOCK", &socket).stdin(Stdio::null());
    };
    let run = |mut command: Command| tokio::task::spawn_blocking(move || command.output().expect("the tool runs"));

    // 1. ssh sees the phone's key in the agent.
    let mut list = Command::new("ssh-add");
    list.arg("-L");
    ssh_env(&mut list);
    let listed = String::from_utf8_lossy(&run(list).await.unwrap().stdout).into_owned();
    let public = std::fs::read_to_string(&public_file).unwrap();
    let blob = public.split_whitespace().nth(1).unwrap();
    assert!(listed.contains(blob), "the phone's key is listed: {listed}");

    // 2. A real login with it, to the same computer.
    let login = |socket: &str| {
        let mut ssh = Command::new("ssh");
        ssh.args(["-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes", "-o", "PreferredAuthentications=publickey", "-o", "StrictHostKeyChecking=accept-new", "-o", "LogLevel=ERROR"])
            .args(["-o", &format!("UserKnownHostsFile={}", work.join("known_hosts").display())])
            .args(["-o", &format!("IdentityAgent={socket}"), "-i", &public_file, &host, "echo logged-in-with-the-phone"])
            .stdin(Stdio::null());
        ssh
    };
    let out = run(login(&socket)).await.unwrap();
    let agent_said = || std::fs::read_to_string(work.join("agent.log")).unwrap_or_default();
    assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), "logged-in-with-the-phone", "ssh: {} | agent: {}", String::from_utf8_lossy(&out.stderr), agent_said());
    let user = std::env::var("MPX_PHONE_USER").unwrap();
    assert_eq!(shown.lock().unwrap().last().unwrap(), &format!("Log in as {user} with this phone's key"));

    // 3. A Git-style signature, checked by ssh-keygen itself.
    let file = work.join("commit.txt");
    std::fs::write(&file, b"a commit to sign\n").unwrap();
    let mut sign = Command::new("ssh-keygen");
    sign.args(["-Y", "sign", "-n", "git", "-f", &public_file]).arg(&file);
    ssh_env(&mut sign);
    let out = run(sign).await.unwrap();
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    assert_eq!(shown.lock().unwrap().last().unwrap(), "Sign a Git commit or tag with this phone's key");
    let signers = work.join("allowed_signers");
    std::fs::write(&signers, format!("phone {public}")).unwrap();
    let mut verify = Command::new("ssh-keygen");
    verify.args(["-Y", "verify", "-n", "git", "-I", "phone", "-f"]).arg(&signers).arg("-s").arg(work.join("commit.txt.sig")).stdin(std::fs::File::open(&file).unwrap());
    let out = tokio::task::spawn_blocking(move || verify.output().unwrap()).await.unwrap();
    assert!(out.status.success(), "ssh-keygen accepts the signature: {}", String::from_utf8_lossy(&out.stderr));

    // 4. Refused on the phone: no login.
    says_yes.store(false, Ordering::SeqCst);
    let out = run(login(&socket)).await.unwrap();
    assert!(!out.status.success(), "a refusal on the phone means no login");

    let _ = std::fs::remove_dir_all(&work);
}
