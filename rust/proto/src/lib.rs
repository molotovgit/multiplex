//! What the phone app and the Omarchy side agree on.
//!
//! Pairing works like this:
//! 1. `multiplex pair` on the computer makes a one-time SSH key that may
//!    run exactly one command (register a phone), for five minutes, and
//!    shows a [`PairingCode`] as a QR code: where the computer is, its SSH
//!    host key, and the seed of that one-time key.
//! 2. The phone scans it, logs in with the one-time key (checking the host
//!    key from the code, so nobody can sit in between), and sends a
//!    [`RegisterRequest`] with its own public key.
//! 3. The computer adds that key to `authorized_keys`, removes the
//!    one-time key, and answers with a [`RegisterReply`].
//!
//! Nothing here does I/O or cryptography; both sides share only the shapes
//! and the checks.

pub mod desk;
pub mod input;
pub mod share;

use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine;
use serde::{Deserialize, Serialize};

/// Every pairing code starts with this, so the app can tell at once.
pub const CODE_PREFIX: &str = "MPX1.";
/// How long a pairing code works.
pub const PAIRING_SECONDS: u64 = 300;

#[derive(Debug, thiserror::Error, PartialEq)]
pub enum ProtoError {
    #[error("this is not a Multiplex pairing code")]
    NotACode,
    #[error("the pairing code is damaged")]
    Damaged,
    #[error("the pairing code is from a newer Multiplex; update the app")]
    TooNew,
    #[error("the pairing code has expired; show a new one on the computer")]
    Expired,
    #[error("{0}")]
    Invalid(&'static str),
}

/// What the QR code carries. Field names are short to keep the code small.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PairingCode {
    /// Format version.
    pub v: u8,
    /// Which pairing this is (also in the one-time key's comment).
    pub id: String,
    /// The computer's name, as shown in the app.
    pub n: String,
    /// The user to log in as.
    pub u: String,
    /// The SSH port.
    pub p: u16,
    /// Home-network addresses, best first.
    #[serde(default)]
    pub a: Vec<String>,
    /// The computer's name on the tailnet, when it is on one.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub t: Option<String>,
    /// The computer's SSH host key (the 32 bytes of an ed25519 key, base64).
    pub h: String,
    /// The seed of the one-time key (32 bytes, base64).
    pub k: String,
    /// When the code stops working (Unix seconds).
    pub x: u64,
    /// The network card's address, for Wake-on-LAN.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub m: Option<String>,
}

impl PairingCode {
    /// The text for the QR code (and for pasting by hand).
    pub fn encode(&self) -> String {
        let json = serde_json::to_vec(self).expect("a pairing code is always valid JSON");
        format!("{CODE_PREFIX}{}", URL_SAFE_NO_PAD.encode(json))
    }

    /// Reads a scanned or pasted code and checks every field.
    pub fn decode(text: &str, now_unix: u64) -> Result<Self, ProtoError> {
        let text = text.trim();
        let body = text.strip_prefix(CODE_PREFIX).ok_or_else(|| {
            if text.starts_with("MPX") { ProtoError::TooNew } else { ProtoError::NotACode }
        })?;
        if body.len() > 2048 {
            return Err(ProtoError::Damaged);
        }
        let json = URL_SAFE_NO_PAD.decode(body).map_err(|_| ProtoError::Damaged)?;
        let code: PairingCode = serde_json::from_slice(&json).map_err(|_| ProtoError::Damaged)?;
        if code.v != 1 {
            return Err(ProtoError::TooNew);
        }
        code.check()?;
        if now_unix > code.x {
            return Err(ProtoError::Expired);
        }
        Ok(code)
    }

    fn check(&self) -> Result<(), ProtoError> {
        if !valid_id(&self.id) {
            return Err(ProtoError::Invalid("the pairing code has a bad id"));
        }
        if !valid_host_name(&self.n) || !valid_user(&self.u) || self.p == 0 {
            return Err(ProtoError::Invalid("the pairing code names the computer badly"));
        }
        if self.a.len() > 8 || self.a.iter().any(|a| !valid_host_name(a)) || self.t.as_deref().is_some_and(|t| !valid_host_name(t)) {
            return Err(ProtoError::Invalid("the pairing code has a bad address"));
        }
        if self.a.is_empty() && self.t.is_none() {
            return Err(ProtoError::Invalid("the pairing code has no address"));
        }
        if decode32(&self.h).is_none() || decode32(&self.k).is_none() {
            return Err(ProtoError::Invalid("the pairing code has a bad key"));
        }
        Ok(())
    }

    /// The seed of the one-time key.
    pub fn seed(&self) -> [u8; 32] {
        decode32(&self.k).expect("checked when decoded")
    }

    /// The computer's host key as an OpenSSH public key line.
    pub fn host_key_line(&self) -> String {
        ed25519_line(&decode32(&self.h).expect("checked when decoded"))
    }
}

/// What the phone sends through the one-time key: `register <base64 of this>`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RegisterRequest {
    /// The phone's own public key, as an OpenSSH line (ed25519).
    pub key: String,
    /// What to call the phone on the computer.
    pub name: String,
}

impl RegisterRequest {
    pub const COMMAND: &'static str = "register";

    /// The command line the phone runs with the one-time key.
    pub fn command_line(&self) -> String {
        let json = serde_json::to_vec(self).expect("always valid JSON");
        format!("{} {}", Self::COMMAND, URL_SAFE_NO_PAD.encode(json))
    }

    /// Reads what arrived as the SSH command, trusting nothing: the key
    /// must be one well-formed ed25519 public key and the name plain text,
    /// because both end up in `authorized_keys`.
    pub fn parse(command_line: &str) -> Result<Self, ProtoError> {
        let mut parts = command_line.trim().split(' ');
        if parts.next() != Some(Self::COMMAND) {
            return Err(ProtoError::Invalid("not a register request"));
        }
        let body = parts.next().ok_or(ProtoError::Damaged)?;
        if parts.next().is_some() || body.len() > 1024 {
            return Err(ProtoError::Damaged);
        }
        let json = URL_SAFE_NO_PAD.decode(body).map_err(|_| ProtoError::Damaged)?;
        let req: RegisterRequest = serde_json::from_slice(&json).map_err(|_| ProtoError::Damaged)?;
        let key = normalize_ed25519_line(&req.key).ok_or(ProtoError::Invalid("the phone's key is not an ed25519 public key"))?;
        let name = clean_device_name(&req.name).ok_or(ProtoError::Invalid("the phone's name is empty or has odd characters"))?;
        Ok(Self { key, name })
    }
}

/// The computer's answer, as one line of JSON.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RegisterReply {
    pub ok: bool,
    /// The computer's name.
    #[serde(default)]
    pub computer: String,
    /// Why not, when `ok` is false.
    #[serde(default)]
    pub error: String,
    /// What the computer has: "gliff", "tailscale", "hyprland", "fcitx5"...
    #[serde(default)]
    pub features: Vec<String>,
}

/// `ssh-ed25519 <base64>` for 32 key bytes.
pub fn ed25519_line(key: &[u8; 32]) -> String {
    let mut blob = Vec::with_capacity(51);
    blob.extend_from_slice(&11u32.to_be_bytes());
    blob.extend_from_slice(b"ssh-ed25519");
    blob.extend_from_slice(&32u32.to_be_bytes());
    blob.extend_from_slice(key);
    format!("ssh-ed25519 {}", STANDARD.encode(blob))
}

/// The 32 key bytes of an `ssh-ed25519 <base64> [comment]` line, when it is
/// exactly that.
pub fn ed25519_key_bytes(line: &str) -> Option<[u8; 32]> {
    let mut parts = line.split_whitespace();
    if parts.next()? != "ssh-ed25519" {
        return None;
    }
    let blob = STANDARD.decode(parts.next()?).ok()?;
    if blob.len() != 51 || blob[..4] != 11u32.to_be_bytes() || &blob[4..15] != b"ssh-ed25519" || blob[15..19] != 32u32.to_be_bytes() {
        return None;
    }
    blob[19..].try_into().ok()
}

/// The line without its comment, re-encoded from the key bytes, so nothing
/// but the key itself can reach `authorized_keys`.
pub fn normalize_ed25519_line(line: &str) -> Option<String> {
    if line.contains(['\n', '\r']) {
        return None;
    }
    ed25519_key_bytes(line).map(|k| ed25519_line(&k))
}

/// A device name safe to store and show: letters, digits, spaces and
/// `-_.'()`, at most 40 characters. Returns it trimmed.
pub fn clean_device_name(name: &str) -> Option<String> {
    let name = name.trim();
    let ok = !name.is_empty()
        && name.chars().count() <= 40
        && name.chars().all(|c| c.is_alphanumeric() || matches!(c, ' ' | '-' | '_' | '.' | '\'' | '(' | ')'));
    ok.then(|| name.to_owned())
}

/// The nearest name [`clean_device_name`] accepts: other characters are
/// dropped, the rest is cut to 40, and an empty result becomes "Phone".
/// Phones are named by their owners ("Sam's phone 📱"), and pairing should
/// not fail over that.
pub fn tidy_device_name(name: &str) -> String {
    let kept: String = name.chars().filter(|c| c.is_alphanumeric() || matches!(c, ' ' | '-' | '_' | '.' | '\'' | '(' | ')')).take(40).collect();
    clean_device_name(&kept).unwrap_or_else(|| "Phone".to_owned())
}

fn decode32(b64: &str) -> Option<[u8; 32]> {
    STANDARD.decode(b64).ok()?.try_into().ok()
}

fn valid_id(id: &str) -> bool {
    (8..=32).contains(&id.len()) && id.chars().all(|c| c.is_ascii_hexdigit())
}

fn valid_user(user: &str) -> bool {
    (1..=32).contains(&user.len()) && user.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
}

/// A host name or address: no spaces, nothing a shell or a URL would trip on.
fn valid_host_name(host: &str) -> bool {
    (1..=253).contains(&host.len()) && host.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | ':'))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn code() -> PairingCode {
        PairingCode {
            v: 1,
            id: "0123456789abcdef".into(),
            n: "desk".into(),
            u: "me".into(),
            p: 22,
            a: vec!["192.168.0.10".into()],
            t: Some("desk".into()),
            h: STANDARD.encode([7u8; 32]),
            k: STANDARD.encode([9u8; 32]),
            x: 1000,
            m: Some("aa:bb:cc:dd:ee:ff".into()),
        }
    }

    #[test]
    fn a_code_survives_the_qr() {
        let text = code().encode();
        assert!(text.starts_with(CODE_PREFIX));
        assert!(text.len() < 420, "small enough to scan off a screen: {}", text.len());
        let back = PairingCode::decode(&format!("  {text}\n"), 999).unwrap();
        assert_eq!(back, code());
        assert_eq!(back.seed(), [9u8; 32]);
        assert_eq!(ed25519_key_bytes(&back.host_key_line()), Some([7u8; 32]));
    }

    #[test]
    fn expired_foreign_and_damaged_codes_are_refused() {
        let text = code().encode();
        assert_eq!(PairingCode::decode(&text, 1001), Err(ProtoError::Expired));
        assert_eq!(PairingCode::decode("https://example.com", 0), Err(ProtoError::NotACode));
        assert_eq!(PairingCode::decode("MPX2.abc", 0), Err(ProtoError::TooNew));
        assert_eq!(PairingCode::decode(&text[..text.len() - 9], 0), Err(ProtoError::Damaged));
        let mut bad = code();
        bad.u = "me; rm -rf ~".into();
        assert!(matches!(PairingCode::decode(&bad.encode(), 0), Err(ProtoError::Invalid(_))));
        let mut bad = code();
        bad.k = "short".into();
        assert!(matches!(PairingCode::decode(&bad.encode(), 0), Err(ProtoError::Invalid(_))));
    }

    #[test]
    fn a_register_request_round_trips_and_drops_the_comment() {
        let req = RegisterRequest { key: format!("{} sneaky comment", ed25519_line(&[3u8; 32])), name: " Galaxy S21 FE ".into() };
        let parsed = RegisterRequest::parse(&req.command_line()).unwrap();
        assert_eq!(parsed.key, ed25519_line(&[3u8; 32]));
        assert_eq!(parsed.name, "Galaxy S21 FE");
    }

    #[test]
    fn odd_phone_names_are_tidied_not_refused() {
        assert_eq!(tidy_device_name("  Sam's phone 📱 "), "Sam's phone");
        assert_eq!(tidy_device_name("📱📱"), "Phone");
        assert_eq!(tidy_device_name(&"x".repeat(80)).chars().count(), 40);
        assert_eq!(clean_device_name(&tidy_device_name("a\nb;rm -rf")), Some("abrm -rf".to_owned()));
    }

    #[test]
    fn malformed_register_requests_are_refused() {
        let cmd = |key: &str, name: &str| RegisterRequest { key: key.into(), name: name.into() }.command_line();
        let good = ed25519_line(&[3u8; 32]);
        // Not a key, another key type, a second line smuggled in, options in front.
        for key in ["", "ssh-ed25519 AAAA", "ssh-rsa AAAAB3NzaC1yc2E=", &format!("{good}\nssh-ed25519 AAAA evil"), &format!("command=\"sh\" {good}")] {
            assert!(RegisterRequest::parse(&cmd(key, "phone")).is_err(), "accepted key {key:?}");
        }
        for name in ["", "a\nb", "x\" y", "$(reboot)", &"n".repeat(41)] {
            assert!(RegisterRequest::parse(&cmd(&good, name)).is_err(), "accepted name {name:?}");
        }
        for line in ["", "register", "register !!!", "shell", "register a b", "ls -la"] {
            assert!(RegisterRequest::parse(line).is_err(), "accepted {line:?}");
        }
    }
}
