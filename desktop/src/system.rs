//! What the computer is and has: its name and addresses for the pairing
//! code, the checks of `multiplex doctor`, and the steps of
//! `multiplex setup`.

use std::path::Path;
use std::process::Command;

use anyhow::Context;
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use multiplex_proto::ed25519_key_bytes;

/// Runs a command and returns its output when it succeeded.
fn run(program: &str, args: &[&str]) -> Option<String> {
    let out = Command::new(program).args(args).output().ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).trim().to_owned())
}

pub(crate) fn on_path(program: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|p| std::env::split_paths(&p).any(|d| d.join(program).is_file()))
}

/// Where the computer is and who to log in as.
pub struct Computer {
    pub name: String,
    pub user: String,
    pub port: u16,
    /// Home-network addresses, best first.
    pub addresses: Vec<String>,
    pub tailscale: Option<String>,
    /// The ed25519 host key (32 bytes, base64).
    pub host_key: String,
    pub mac: Option<String>,
}

impl Computer {
    pub fn detect() -> anyhow::Result<Self> {
        let name = std::fs::read_to_string("/proc/sys/kernel/hostname").map(|s| s.trim().to_owned()).unwrap_or_else(|_| "computer".into());
        let user = std::env::var("USER").ok().filter(|u| !u.is_empty()).or_else(|| run("id", &["-un"])).context("could not tell the user name")?;
        let host_line = std::fs::read_to_string("/etc/ssh/ssh_host_ed25519_key.pub")
            .context("the SSH server has no ed25519 host key (/etc/ssh/ssh_host_ed25519_key.pub); run `multiplex setup`")?;
        let host_key = STANDARD.encode(ed25519_key_bytes(&host_line).context("the SSH host key file is not an ed25519 key")?);
        let (address, device) = default_route();
        let mac = device.and_then(|d| std::fs::read_to_string(format!("/sys/class/net/{d}/address")).ok()).map(|m| m.trim().to_owned()).filter(|m| m.len() == 17);
        Ok(Self { name, user, port: ssh_port(), addresses: address.into_iter().collect(), tailscale: tailscale_name(), host_key, mac })
    }
}

/// The address and network card the default route uses.
fn default_route() -> (Option<String>, Option<String>) {
    let Some(json) = run("ip", &["-j", "-4", "route", "get", "1.1.1.1"]) else { return (None, None) };
    let Ok(routes) = serde_json::from_str::<serde_json::Value>(&json) else { return (None, None) };
    let route = &routes[0];
    let text = |key: &str| route[key].as_str().map(str::to_owned);
    // A Tailscale exit node would answer here; that is not the home network.
    match text("dev") {
        Some(dev) if dev.starts_with("tailscale") => (None, None),
        dev => (text("prefsrc"), dev),
    }
}

/// The first label of the computer's MagicDNS name, when Tailscale runs.
fn tailscale_name() -> Option<String> {
    let status: serde_json::Value = serde_json::from_str(&run("tailscale", &["status", "--json"])?).ok()?;
    if status["BackendState"].as_str()? != "Running" {
        return None;
    }
    let dns = status["Self"]["DNSName"].as_str()?;
    dns.split('.').next().filter(|l| !l.is_empty()).map(str::to_owned)
}

/// The SSH port from the server's configuration (22 when it says nothing).
fn ssh_port() -> u16 {
    sshd_setting("port").and_then(|p| p.parse().ok()).unwrap_or(22)
}

/// The first value of a setting in sshd's configuration files (sshd uses
/// the first one it reads; the drop-in directory is included at the top).
fn sshd_setting(key: &str) -> Option<String> {
    let mut files: Vec<_> = std::fs::read_dir("/etc/ssh/sshd_config.d").into_iter().flatten().flatten().map(|e| e.path()).filter(|p| p.extension().is_some_and(|e| e == "conf")).collect();
    files.sort();
    files.push("/etc/ssh/sshd_config".into());
    files.iter().filter_map(|f| std::fs::read_to_string(f).ok()).flat_map(|t| t.lines().map(str::to_owned).collect::<Vec<_>>()).find_map(|line| {
        let mut words = line.split_whitespace();
        (words.next()?.eq_ignore_ascii_case(key)).then(|| words.next().map(str::to_owned)).flatten()
    })
}

/// What the phone can count on, sent in the pairing reply.
pub fn features() -> Vec<String> {
    let mut f = Vec::new();
    if on_path("gliff-server") {
        f.push("gliff");
    }
    if hyprland_running() {
        f.push("hyprland");
    }
    if run("pgrep", &["-x", "fcitx5"]).is_some() {
        f.push("fcitx5");
    }
    if tailscale_name().is_some() {
        f.push("tailscale");
    }
    f.into_iter().map(str::to_owned).collect()
}

fn hyprland_running() -> bool {
    let dir = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| format!("/run/user/{}", run("id", &["-u"]).unwrap_or_default()));
    std::fs::read_dir(Path::new(&dir).join("hypr")).is_ok_and(|mut d| d.next().is_some())
}

/// One line of `multiplex doctor`.
#[derive(serde::Serialize)]
pub struct Check {
    pub name: &'static str,
    /// None: could not tell without sudo.
    pub ok: Option<bool>,
    /// Needed for pairing and the desktop; the rest is optional.
    pub required: bool,
    pub detail: String,
}

pub fn doctor() -> Vec<Check> {
    let check = |name, ok: Option<bool>, required, detail: &str| Check { name, ok, required, detail: detail.to_owned() };
    let sshd = run("systemctl", &["is-active", "sshd"]).is_some();
    let host_key = std::fs::read_to_string("/etc/ssh/ssh_host_ed25519_key.pub").is_ok_and(|l| ed25519_key_bytes(&l).is_some());
    let passwords = sshd_setting("passwordauthentication").map(|v| v.eq_ignore_ascii_case("no"));
    let ufw = run("systemctl", &["is-active", "ufw"]).is_some();
    let ts = tailscale_name();
    let mut checks = vec![
        check("SSH server", Some(sshd), true, if sshd { "running" } else { "not running: run `multiplex setup`" }),
        check("SSH host key", Some(host_key), true, if host_key { "ed25519 key present" } else { "no ed25519 host key: run `multiplex setup`" }),
        check("Key-only logins", passwords, true, match passwords {
            Some(true) => "password logins are off",
            Some(false) => "password logins are on: run `multiplex setup`",
            None => "not set in sshd's configuration (passwords are allowed by default): run `multiplex setup`",
        }),
        check("Firewall", if ufw { None } else { Some(false) }, false, if ufw { "ufw is on; `sudo ufw status` shows whether SSH is open to the home network and Tailscale" } else { "ufw is not running" }),
        check("gliff", Some(on_path("gliff-server")), true, if on_path("gliff-server") { "gliff-server found" } else { "gliff is not installed: sudo pacman -S gliff" }),
        check("Hyprland", Some(hyprland_running()), true, if hyprland_running() { "a session is running" } else { "no session found (log in to the desktop)" }),
        check("Tailscale", Some(ts.is_some()), false, &ts.map(|n| format!("connected as {n}")).unwrap_or_else(|| "not connected: the phone reaches this computer on the home network only".into())),
        check("Automatic keyboard", Some(run("pgrep", &["-x", "fcitx5"]).is_some()), false, "needs fcitx5 running (it tells the phone when a text field has the focus)"),
        match wake_on_lan() {
            Some((_, true)) => check("Wake-on-LAN", Some(true), false, "on: the phone can switch this computer on from the home network (the firmware has to allow it too)"),
            Some((_, false)) => check("Wake-on-LAN", Some(false), false, "off: run `multiplex setup`, and allow it in the firmware's settings"),
            None => check("Wake-on-LAN", None, false, "needs a wired network card managed by NetworkManager"),
        },
        check("Touchpad and keys", Some(crate::input::available()), false, "the phone's touchpad needs Hyprland running and xkbcli (from libxkbcommon)"),
        check("Phone screen", Some(on_path("mpv")), false, "showing the phone's screen in a window needs mpv: sudo pacman -S mpv"),
        match crate::camera::Way::find().filter(|_| on_path("ffmpeg")) {
            Some(way) => check("Phone camera", Some(true), false, &way.words()),
            None => check("Phone camera", Some(false), false, crate::camera::NEEDS),
        },
        check("Phone microphone", Some(crate::mic::available()), false, crate::mic::NEEDS),
        check("Phone speaker", Some(crate::speaker::available()), false, crate::speaker::NEEDS),
        match crate::read::languages() {
            languages if languages.is_empty() => check("Reading text", Some(false), false, crate::read::NEEDS),
            languages => check("Reading text", Some(true), false, &format!("in pictures from the phone, in: {} (more: sudo pacman -S tesseract-data-<language>)", languages.join(", "))),
        },
        check("120 fps", Some(Path::new(&std::env::var("HOME").unwrap_or_default()).join(".local/bin/gliff-server-fast").is_file()), false, "optional: a gliff build without the 60 fps cap at ~/.local/bin/gliff-server-fast"),
    ];
    if let Some((on, detail)) = crate::sudo::standing_here() {
        checks.push(check("sudo by phone", Some(on), false, &detail));
    }
    // Only where there is an Omarchy bar to be in.
    if let Some((ok, detail)) = bar_widget() {
        checks.push(check("Bar widget", ok, false, &detail));
    }
    checks
}

/// How the bar widget stands, where the Omarchy shell is installed.
fn bar_widget() -> Option<(Option<bool>, String)> {
    if !(on_path("omarchy-shell") && on_path("omarchy")) {
        return None;
    }
    let dir = crate::bar::plugin_dir().ok()?;
    let command = std::env::current_exe().ok()?;
    Some(crate::bar::status(&dir, &command, true))
}

/// The commands of `multiplex setup`, in order, each with what it is for.
pub fn setup_steps() -> Vec<(&'static str, Vec<String>)> {
    let sh = |s: &str| vec!["sudo".to_owned(), "sh".to_owned(), "-c".to_owned(), s.to_owned()];
    let mut steps = vec![
        ("Create the SSH host keys if they are missing", sh("ssh-keygen -A")),
        ("Key-only logins, no root login", sh(
            "printf '%s\\n' '# Written by multiplex setup: only keys may log in.' 'PasswordAuthentication no' 'KbdInteractiveAuthentication no' 'PermitRootLogin no' 'PubkeyAuthentication yes' > /etc/ssh/sshd_config.d/10-multiplex.conf && sshd -t || { rm -f /etc/ssh/sshd_config.d/10-multiplex.conf; echo 'sshd refused the settings; nothing changed'; exit 1; }",
        )),
        ("Start the SSH server now and at every boot", sh("systemctl enable --now sshd && systemctl reload sshd")),
    ];
    if on_path("ufw") {
        if let Some(net) = home_network() {
            steps.push(("Firewall: SSH from the home network", sh(&format!("ufw allow from {net} to any port 22 proto tcp comment 'Multiplex: SSH from the home network'"))));
        }
        steps.push(("Firewall: SSH over Tailscale", sh("ufw allow in on tailscale0 to any port 22 proto tcp comment 'Multiplex: SSH over Tailscale'")));
    }
    if !on_path("gliff-server") {
        steps.push(("Install gliff (the remote desktop)", sh("pacman -S --needed --noconfirm gliff")));
    }
    if let Some((connection, false)) = wake_on_lan() {
        // Applies the next time the network connects, so nothing drops now.
        steps.push((
            "Wake-on-LAN: let the phone switch this computer on (from the next network connection; the firmware has to allow it too)",
            sh(&format!("nmcli connection modify '{}' 802-3-ethernet.wake-on-lan magic", connection.replace('\'', r"'\''"))),
        ));
    }
    steps
}

/// The home network as `address/prefix`, for the firewall rule.
fn home_network() -> Option<String> {
    let (_, device) = default_route();
    let json = run("ip", &["-j", "-4", "route", "show", "dev", &device?])?;
    let routes: serde_json::Value = serde_json::from_str(&json).ok()?;
    routes.as_array()?.iter().filter_map(|r| r["dst"].as_str()).find(|d| d.contains('/')).map(str::to_owned)
}

/// The wired NetworkManager connection the default route uses, and whether
/// it wakes the computer on a magic packet. None without such a connection.
fn wake_on_lan() -> Option<(String, bool)> {
    let (_, device) = default_route();
    let device = device?;
    let active = run("nmcli", &["-t", "-f", "NAME,DEVICE,TYPE", "connection", "show", "--active"])?;
    let name = active.lines().find_map(|line| {
        // NAME may hold escaped colons; DEVICE and TYPE never do.
        let (rest, kind) = line.rsplit_once(':')?;
        let (name, dev) = rest.rsplit_once(':')?;
        (dev == device && kind == "802-3-ethernet").then(|| name.replace("\\:", ":"))
    })?;
    let setting = run("nmcli", &["-g", "802-3-ethernet.wake-on-lan", "connection", "show", &name])?;
    Some((name, setting.split(',').any(|s| s.trim() == "magic")))
}
