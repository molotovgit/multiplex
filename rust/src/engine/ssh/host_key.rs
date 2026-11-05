//! Checking that the server is the one the user trusts.
//!
//! Every SSH server has an identity key. The first time we connect, the
//! user is shown its fingerprint and decides whether to trust it ("trust on
//! first use", as OpenSSH does). Later connections must present the same
//! key; a different key is reported loudly, because it can mean someone
//! sits between the phone and the server.

use std::sync::Mutex;

use russh::keys::{HashAlg, PublicKey, PublicKeyOrCertificate};

use crate::api::ssh_types::HostKeyInfo;

/// What went wrong with the server's key, if anything.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HostKeyProblem {
    Unknown(HostKeyInfo),
    Changed(HostKeyInfo),
}

/// Holds the trusted keys for one server and remembers the outcome of the
/// check, because russh only lets us answer yes or no.
pub struct HostKeyGuard {
    trusted: Vec<PublicKey>,
    problem: Mutex<Option<HostKeyProblem>>,
    seen: Mutex<Option<HostKeyInfo>>,
}

impl HostKeyGuard {
    /// `trusted` are OpenSSH public key lines. Lines that cannot be read
    /// are ignored (they can never match anyway).
    pub fn new(trusted: &[String]) -> Self {
        let trusted = trusted
            .iter()
            .filter_map(|line| PublicKey::from_openssh(line.trim()).ok())
            .collect();
        Self {
            trusted,
            problem: Mutex::new(None),
            seen: Mutex::new(None),
        }
    }

    /// Decides whether to continue with this server key.
    pub fn check(&self, offered: &PublicKeyOrCertificate) -> bool {
        let key = match offered {
            PublicKeyOrCertificate::PublicKey { key, .. } => key.clone(),
            // A certificate's own key is what identifies the server.
            PublicKeyOrCertificate::Certificate(cert) => PublicKey::from(cert.public_key().clone()),
        };
        let info = Self::describe(&key);
        *self.seen.lock().expect("host key lock") = Some(info.clone());

        if self.trusted.iter().any(|t| t.key_data() == key.key_data()) {
            return true;
        }
        let problem = if self.trusted.is_empty() {
            HostKeyProblem::Unknown(info)
        } else {
            HostKeyProblem::Changed(info)
        };
        *self.problem.lock().expect("host key lock") = Some(problem);
        false
    }

    /// The problem found during the last check, if any.
    pub fn problem(&self) -> Option<HostKeyProblem> {
        self.problem.lock().expect("host key lock").clone()
    }

    /// The key the server presented (after a successful check).
    pub fn seen(&self) -> Option<HostKeyInfo> {
        self.seen.lock().expect("host key lock").clone()
    }

    /// Type, fingerprint and OpenSSH line of a key.
    pub fn describe(key: &PublicKey) -> HostKeyInfo {
        let mut bare = key.clone();
        bare.set_comment("");
        HostKeyInfo {
            algorithm: key.algorithm().as_str().to_owned(),
            fingerprint: key.fingerprint(HashAlg::Sha256).to_string(),
            public_key: bare.to_openssh().unwrap_or_default(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use russh::keys::{Algorithm, PrivateKey};

    fn offered(key: &PrivateKey) -> PublicKeyOrCertificate {
        PublicKeyOrCertificate::PublicKey { key: key.public_key().clone(), hash_alg: None }
    }

    fn new_key() -> PrivateKey {
        PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap()
    }

    #[test]
    fn unknown_server_is_reported_with_its_fingerprint() {
        let server = new_key();
        let guard = HostKeyGuard::new(&[]);
        assert!(!guard.check(&offered(&server)));
        let Some(HostKeyProblem::Unknown(info)) = guard.problem() else { panic!("expected unknown") };
        assert_eq!(info.fingerprint, server.fingerprint(HashAlg::Sha256).to_string());
        assert!(info.public_key.starts_with("ssh-ed25519 "));
    }

    #[test]
    fn trusted_key_passes_and_a_different_one_is_flagged() {
        let server = new_key();
        let line = server.public_key().to_openssh().unwrap();
        let guard = HostKeyGuard::new(std::slice::from_ref(&line));
        assert!(guard.check(&offered(&server)));
        assert_eq!(guard.problem(), None);

        let impostor = new_key();
        let guard = HostKeyGuard::new(&[line]);
        assert!(!guard.check(&offered(&impostor)));
        assert!(matches!(guard.problem(), Some(HostKeyProblem::Changed(_))));
    }
}
