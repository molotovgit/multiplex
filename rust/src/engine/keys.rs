//! SSH key pairs: create new ones, read existing ones, show fingerprints.
//!
//! Keys are always stored in the OpenSSH text format, the same format
//! `ssh-keygen` writes, so they can be copied to and from other tools.

use std::sync::Arc;

use russh::keys::ssh_key::private::{KeypairData, RsaKeypair};
use russh::keys::ssh_key::LineEnding;
use russh::keys::{Algorithm, EcdsaCurve, HashAlg, PrivateKey, PublicKey};
use thiserror::Error;

use crate::api::keys::{KeyKind, KeyPairInfo};

#[derive(Debug, Error, PartialEq, Eq)]
pub enum KeyError {
    #[error("this key is protected with a passphrase")]
    PassphraseNeeded,
    #[error("the passphrase is wrong")]
    WrongPassphrase,
    #[error("this is not a private key Multiplex can read: {0}")]
    Unreadable(String),
    #[error("could not create the key: {0}")]
    Generate(String),
}

/// Creates and reads SSH keys.
pub struct KeyFactory;

impl KeyFactory {
    /// Makes a brand new key pair. With a passphrase the private key is
    /// stored encrypted, exactly like `ssh-keygen -N`.
    pub fn generate(kind: KeyKind, comment: &str, passphrase: Option<&str>) -> Result<KeyPairInfo, KeyError> {
        let mut rng = rand::rng();
        let mut key = match kind {
            KeyKind::Ed25519 => PrivateKey::random(&mut rng, Algorithm::Ed25519),
            KeyKind::EcdsaP256 => PrivateKey::random(
                &mut rng,
                Algorithm::Ecdsa { curve: EcdsaCurve::NistP256 },
            ),
            KeyKind::Rsa3072 => Self::rsa(&mut rng, 3072),
            KeyKind::Rsa4096 => Self::rsa(&mut rng, 4096),
        }
        .map_err(|e| KeyError::Generate(e.to_string()))?;
        key.set_comment(comment);

        let public = Self::public_line(key.public_key())?;
        let fingerprint = key.fingerprint(HashAlg::Sha256).to_string();
        let stored = match passphrase.filter(|p| !p.is_empty()) {
            Some(pass) => key
                .encrypt(&mut rng, pass)
                .map_err(|e| KeyError::Generate(e.to_string()))?,
            None => key.clone(),
        };
        let private_pem = stored
            .to_openssh(LineEnding::LF)
            .map_err(|e| KeyError::Generate(e.to_string()))?
            .to_string();

        Ok(KeyPairInfo {
            private_pem,
            public_openssh: public,
            fingerprint,
            algorithm: key.algorithm().as_str().to_owned(),
            comment: comment.to_owned(),
            encrypted: stored.is_encrypted(),
        })
    }

    /// Reads a private key someone pasted or picked from a file. Accepts
    /// OpenSSH, PEM (PKCS#1/PKCS#8) and PuTTY formats. The key text is kept
    /// as given, so an encrypted key stays encrypted.
    pub fn inspect(pem: &str, passphrase: Option<&str>) -> Result<KeyPairInfo, KeyError> {
        let key = Self::decode(pem, passphrase)?;
        Ok(KeyPairInfo {
            private_pem: pem.trim().to_owned() + "\n",
            public_openssh: Self::public_line(key.public_key())?,
            fingerprint: key.fingerprint(HashAlg::Sha256).to_string(),
            algorithm: key.algorithm().as_str().to_owned(),
            comment: key.comment().to_string(),
            encrypted: Self::is_encrypted(pem),
        })
    }

    /// True when the key text needs a passphrase before it can be used.
    pub fn is_encrypted(pem: &str) -> bool {
        match Self::decode(pem, None) {
            Err(KeyError::PassphraseNeeded) => true,
            _ => pem.contains("ENCRYPTED"),
        }
    }

    /// Decodes a private key so it can be used to log in.
    pub fn decode(pem: &str, passphrase: Option<&str>) -> Result<PrivateKey, KeyError> {
        let passphrase = passphrase.filter(|p| !p.is_empty());
        match russh::keys::decode_secret_key(pem.trim(), passphrase) {
            Ok(key) => Ok(key),
            Err(err) => Err(Self::classify(err, passphrase.is_some())),
        }
    }

    /// Decodes a key for login, shared behind an `Arc` as russh wants it.
    pub fn decode_shared(pem: &str, passphrase: Option<&str>) -> Result<Arc<PrivateKey>, KeyError> {
        Self::decode(pem, passphrase).map(Arc::new)
    }

    /// SHA256 fingerprint of a public key line such as
    /// `ssh-ed25519 AAAA... comment`.
    pub fn fingerprint_of_public(line: &str) -> Result<String, KeyError> {
        let key = PublicKey::from_openssh(line.trim()).map_err(|e| KeyError::Unreadable(e.to_string()))?;
        Ok(key.fingerprint(HashAlg::Sha256).to_string())
    }

    /// The `type base64 comment` line that goes into `authorized_keys`.
    pub fn public_line(key: &PublicKey) -> Result<String, KeyError> {
        key.to_openssh().map_err(|e| KeyError::Unreadable(e.to_string()))
    }

    fn rsa(rng: &mut rand::rngs::ThreadRng, bits: usize) -> russh::keys::ssh_key::Result<PrivateKey> {
        let pair = RsaKeypair::random(rng, bits)?;
        PrivateKey::new(KeypairData::from(pair), "")
    }

    /// Sorts russh's many error kinds into the few the app shows.
    fn classify(err: russh::keys::Error, had_passphrase: bool) -> KeyError {
        let text = err.to_string();
        let lower = text.to_lowercase();
        if matches!(err, russh::keys::Error::KeyIsEncrypted) {
            return KeyError::PassphraseNeeded;
        }
        if lower.contains("decrypt") || lower.contains("crypto") || lower.contains("padding") || lower.contains("checkint") {
            return if had_passphrase { KeyError::WrongPassphrase } else { KeyError::PassphraseNeeded };
        }
        KeyError::Unreadable(text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_key_can_be_read_back() {
        let pair = KeyFactory::generate(KeyKind::Ed25519, "me@phone", None).unwrap();
        assert!(pair.public_openssh.starts_with("ssh-ed25519 "));
        assert!(pair.public_openssh.ends_with(" me@phone"));
        assert!(pair.fingerprint.starts_with("SHA256:"));
        assert!(!pair.encrypted);
        let again = KeyFactory::inspect(&pair.private_pem, None).unwrap();
        assert_eq!(again.fingerprint, pair.fingerprint);
        assert_eq!(again.comment, "me@phone");
        assert_eq!(KeyFactory::fingerprint_of_public(&pair.public_openssh).unwrap(), pair.fingerprint);
    }

    #[test]
    fn passphrase_protected_key_needs_the_right_passphrase() {
        let pair = KeyFactory::generate(KeyKind::Ed25519, "locked", Some("correct horse")).unwrap();
        assert!(pair.encrypted);
        assert!(KeyFactory::is_encrypted(&pair.private_pem));
        assert_eq!(KeyFactory::decode(&pair.private_pem, None).unwrap_err(), KeyError::PassphraseNeeded);
        assert_eq!(
            KeyFactory::decode(&pair.private_pem, Some("wrong")).unwrap_err(),
            KeyError::WrongPassphrase
        );
        let key = KeyFactory::decode(&pair.private_pem, Some("correct horse")).unwrap();
        assert_eq!(key.fingerprint(HashAlg::Sha256).to_string(), pair.fingerprint);
    }

    #[test]
    fn makes_ecdsa_keys() {
        let pair = KeyFactory::generate(KeyKind::EcdsaP256, "", None).unwrap();
        assert!(pair.public_openssh.starts_with("ecdsa-sha2-nistp256 "));
    }

    #[test]
    fn makes_rsa_keys() {
        let pair = KeyFactory::generate(KeyKind::Rsa3072, "rsa", None).unwrap();
        assert!(pair.public_openssh.starts_with("ssh-rsa "));
        KeyFactory::inspect(&pair.private_pem, None).unwrap();
    }

    #[test]
    fn rejects_text_that_is_not_a_key() {
        assert!(matches!(KeyFactory::inspect("hello", None), Err(KeyError::Unreadable(_))));
    }
}
