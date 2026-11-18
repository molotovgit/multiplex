//! Using the phone's SSH key from the computer: the key stays on the
//! phone, the computer's SSH agent (`multiplex agent`) passes each
//! signing request to it, and the phone signs after a fingerprint.
//!
//! The phone does not sign whatever it is handed. It reads the request
//! itself and signs only the two things an SSH key is for:
//!
//! - logging in (the data an SSH client signs to authenticate, RFC 4252);
//! - an SSH signature over a file or a Git commit (the `SSHSIG` format).
//!
//! What it shows the owner comes from that reading, not from anything the
//! computer says about the request. Everything else is refused, which
//! also keeps this path from being used to get any other signature (an
//! approval, say) out of the key.

use base64::engine::general_purpose::STANDARD;
use base64::Engine;

/// The largest request taken (a login request is a few hundred bytes).
pub const MAX_SIGN: usize = 16 * 1024;

const SSH_MSG_USERAUTH_REQUEST: u8 = 50;
const SSHSIG_MAGIC: &[u8] = b"SSHSIG";

/// What a signing request is for.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SignRequest {
    /// Logging in to an SSH server as this user.
    Login { user: String },
    /// Signing something in this namespace ("git", "file").
    Signature { namespace: String },
}

impl SignRequest {
    /// What the owner is asked, in a fingerprint prompt.
    pub fn describe(&self) -> String {
        match self {
            SignRequest::Login { user } => format!("Log in as {user} with this phone's key"),
            SignRequest::Signature { namespace } if namespace == "git" => "Sign a Git commit or tag with this phone's key".to_owned(),
            SignRequest::Signature { namespace } => format!("Sign with this phone's key (for: {namespace})"),
        }
    }
}

/// Reads SSH's length-prefixed fields.
struct Reader<'a>(&'a [u8]);

impl<'a> Reader<'a> {
    fn bytes(&mut self, n: usize) -> Option<&'a [u8]> {
        if self.0.len() < n {
            return None;
        }
        let (head, rest) = self.0.split_at(n);
        self.0 = rest;
        Some(head)
    }

    fn byte(&mut self) -> Option<u8> {
        self.bytes(1).map(|b| b[0])
    }

    fn string(&mut self) -> Option<&'a [u8]> {
        let len = u32::from_be_bytes(self.bytes(4)?.try_into().ok()?) as usize;
        self.bytes(len)
    }

    fn text(&mut self) -> Option<String> {
        let text = std::str::from_utf8(self.string()?).ok()?;
        // Shown to the owner: nothing that could hide or fake a line.
        (!text.is_empty() && text.len() <= 64 && text.chars().all(|c| !c.is_control())).then(|| text.to_owned())
    }

    fn done(&self) -> bool {
        self.0.is_empty()
    }
}

/// The blob of an ed25519 public key as SSH writes it.
pub fn ed25519_blob(key: &[u8; 32]) -> Vec<u8> {
    let mut blob = Vec::with_capacity(51);
    blob.extend_from_slice(&11u32.to_be_bytes());
    blob.extend_from_slice(b"ssh-ed25519");
    blob.extend_from_slice(&32u32.to_be_bytes());
    blob.extend_from_slice(key);
    blob
}

/// Reads a signing request. `key` is the phone's own public key: a login
/// request names the key it is for, and must name this one. `None` for
/// anything that is not, exactly and completely, one of the two kinds.
pub fn read_request(data: &[u8], key: &[u8; 32]) -> Option<SignRequest> {
    if data.len() > MAX_SIGN {
        return None;
    }
    if let Some(rest) = data.strip_prefix(SSHSIG_MAGIC) {
        // SSHSIG || namespace || reserved || hash algorithm || H(message)
        let mut r = Reader(rest);
        let namespace = r.text()?;
        let _reserved = r.string()?;
        let hash = r.string()?;
        let digest = r.string()?;
        let sized = matches!((hash, digest.len()), (b"sha256", 32) | (b"sha512", 64));
        return (sized && r.done()).then_some(SignRequest::Signature { namespace });
    }
    // session id || 50 || user || service || method || TRUE || algorithm || key
    // and, with the method newer OpenSSH uses, the server's host key last
    // (so that a signature made for one server is of no use at another).
    let mut r = Reader(data);
    let session = r.string()?;
    if session.is_empty() || r.byte()? != SSH_MSG_USERAUTH_REQUEST {
        return None;
    }
    let user = r.text()?;
    let service = r.string()?;
    let method = r.string()?;
    let has_signature = r.byte()?;
    let algorithm = r.string()?;
    let named_key = r.string()?;
    match method {
        b"publickey" => {}
        b"publickey-hostbound-v00@openssh.com" => {
            let server_key = r.string()?;
            if server_key.is_empty() {
                return None;
            }
        }
        _ => return None,
    }
    let exact = service == b"ssh-connection" && has_signature == 1 && algorithm == b"ssh-ed25519" && named_key == ed25519_blob(key) && r.done();
    exact.then_some(SignRequest::Login { user })
}

/// The same, from the base64 the request travels in.
pub fn read_request_base64(data: &str, key: &[u8; 32]) -> Option<(Vec<u8>, SignRequest)> {
    let bytes = STANDARD.decode(data.trim()).ok()?;
    let request = read_request(&bytes, key)?;
    Some((bytes, request))
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    fn field(out: &mut Vec<u8>, bytes: &[u8]) {
        out.extend_from_slice(&(bytes.len() as u32).to_be_bytes());
        out.extend_from_slice(bytes);
    }

    /// What an SSH client signs to log in.
    pub fn login(user: &str, key: &[u8; 32]) -> Vec<u8> {
        let mut data = Vec::new();
        field(&mut data, &[7u8; 32]);
        data.push(50);
        field(&mut data, user.as_bytes());
        field(&mut data, b"ssh-connection");
        field(&mut data, b"publickey");
        data.push(1);
        field(&mut data, b"ssh-ed25519");
        field(&mut data, &ed25519_blob(key));
        data
    }

    /// The same with the server's host key bound in, as newer OpenSSH does.
    pub fn hostbound_login(user: &str, key: &[u8; 32]) -> Vec<u8> {
        let mut data = Vec::new();
        field(&mut data, &[7u8; 32]);
        data.push(50);
        field(&mut data, user.as_bytes());
        field(&mut data, b"ssh-connection");
        field(&mut data, b"publickey-hostbound-v00@openssh.com");
        data.push(1);
        field(&mut data, b"ssh-ed25519");
        field(&mut data, &ed25519_blob(key));
        field(&mut data, &ed25519_blob(&[5u8; 32]));
        data
    }

    /// What `ssh-keygen -Y sign` (and so Git) signs.
    pub fn sshsig(namespace: &str) -> Vec<u8> {
        let mut data = b"SSHSIG".to_vec();
        field(&mut data, namespace.as_bytes());
        field(&mut data, b"");
        field(&mut data, b"sha512");
        field(&mut data, &[3u8; 64]);
        data
    }

    #[test]
    fn a_login_and_a_signature_are_read_and_described() {
        let key = [9u8; 32];
        assert_eq!(read_request(&login("sam", &key), &key), Some(SignRequest::Login { user: "sam".into() }));
        assert_eq!(read_request(&hostbound_login("sam", &key), &key), Some(SignRequest::Login { user: "sam".into() }));
        assert_eq!(SignRequest::Login { user: "sam".into() }.describe(), "Log in as sam with this phone's key");
        assert_eq!(read_request(&sshsig("git"), &key).unwrap().describe(), "Sign a Git commit or tag with this phone's key");
        assert_eq!(read_request(&sshsig("file"), &key), Some(SignRequest::Signature { namespace: "file".into() }));
        let (bytes, request) = read_request_base64(&STANDARD.encode(sshsig("git")), &key).unwrap();
        assert_eq!((bytes, request), (sshsig("git"), SignRequest::Signature { namespace: "git".into() }));
    }

    #[test]
    fn nothing_else_is_ever_signed() {
        let key = [9u8; 32];
        let good = login("sam", &key);
        // A login for another key, a longer or shorter request, another message.
        assert_eq!(read_request(&login("sam", &[8u8; 32]), &key), None);
        assert_eq!(read_request(&[good.clone(), vec![0]].concat(), &key), None);
        assert_eq!(read_request(&good[..good.len() - 1], &key), None);
        let mut other_message = good.clone();
        other_message[36] = 51;
        assert_eq!(read_request(&other_message, &key), None);
        // The host-bound form without a host key, or with something after it;
        // the plain form with a host key tacked on; another method.
        let bound = hostbound_login("sam", &key);
        assert_eq!(read_request(&bound[..bound.len() - 51 - 4], &key), None);
        assert_eq!(read_request(&[bound.clone(), vec![0, 0, 0, 0]].concat(), &key), None);
        assert_eq!(read_request(&[good.clone(), ed25519_blob(&[5u8; 32])].concat(), &key), None);
        assert_eq!(read_request(&bound.iter().map(|b| if *b == b'v' { b'w' } else { *b }).collect::<Vec<u8>>(), &key), None);
        // A user name that could fake a line in the prompt.
        assert_eq!(read_request(&login("sam\nApprove everything", &key), &key), None);
        // An approval, plain text, an empty request, a huge one.
        assert_eq!(read_request(b"multiplex-approve-v1\n00112233aabbccdd\nYw==\nsudo", &key), None);
        assert_eq!(read_request(b"hello", &key), None);
        assert_eq!(read_request(b"", &key), None);
        assert_eq!(read_request(&vec![0u8; MAX_SIGN + 1], &key), None);
        // SSHSIG with a digest of the wrong size, or trailing bytes.
        let mut short = b"SSHSIG".to_vec();
        for part in [&b"git"[..], b"", b"sha512", &[1u8; 20]] {
            field(&mut short, part);
        }
        assert_eq!(read_request(&short, &key), None);
        assert_eq!(read_request(&[sshsig("git"), vec![1]].concat(), &key), None);
        assert!(read_request_base64("not base64!", &key).is_none());
    }
}
