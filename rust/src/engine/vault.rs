//! Encryption for everything VaultTerm saves.
//!
//! - [`VaultCipher`] locks the app's data file with a random 32-byte key.
//!   The app keeps that key in the phone's secure key store (Android
//!   Keystore / iOS Keychain), so the file alone is useless.
//! - [`BackupCipher`] locks an exported backup with a password the user
//!   picks. Argon2id makes guessing that password slow.
//! - [`SecureFile`] writes files so a crash never leaves half a file.
//!
//! Both ciphers use XChaCha20-Poly1305: it encrypts and also detects any
//! change to the file, so a damaged or tampered file is refused.

use std::path::Path;

use argon2::{Algorithm, Argon2, Params, Version};
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{Key, XChaCha20Poly1305, XNonce};
use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum VaultError {
    #[error("the key must be 32 bytes")]
    BadKey,
    #[error("this is not a VaultTerm file")]
    NotAVaultFile,
    #[error("wrong key or password, or the file was changed")]
    CannotDecrypt,
    #[error("could not derive the key from the password: {0}")]
    Kdf(String),
    #[error("file error: {0}")]
    Io(String),
}

const NONCE_LEN: usize = 24;
const KEY_LEN: usize = 32;

/// Encrypts the app's own data file with a random key.
pub struct VaultCipher;

impl VaultCipher {
    /// Marks the file format, version 1.
    const MAGIC: &'static [u8; 4] = b"VTV1";

    /// A fresh random key for a new install.
    pub fn new_key() -> Vec<u8> {
        Random::bytes(KEY_LEN)
    }

    /// Layout: MAGIC | nonce (24 bytes) | ciphertext with tag.
    pub fn seal(key: &[u8], plaintext: &[u8]) -> Result<Vec<u8>, VaultError> {
        let cipher = Self::cipher(key)?;
        let nonce = Random::bytes(NONCE_LEN);
        let sealed = cipher
            .encrypt(XNonce::from_slice(&nonce), Payload { msg: plaintext, aad: Self::MAGIC })
            .map_err(|_| VaultError::CannotDecrypt)?;
        let mut out = Vec::with_capacity(4 + NONCE_LEN + sealed.len());
        out.extend_from_slice(Self::MAGIC);
        out.extend_from_slice(&nonce);
        out.extend_from_slice(&sealed);
        Ok(out)
    }

    pub fn open(key: &[u8], data: &[u8]) -> Result<Vec<u8>, VaultError> {
        let cipher = Self::cipher(key)?;
        if data.len() < 4 + NONCE_LEN || &data[..4] != Self::MAGIC {
            return Err(VaultError::NotAVaultFile);
        }
        let (nonce, body) = data[4..].split_at(NONCE_LEN);
        cipher
            .decrypt(XNonce::from_slice(nonce), Payload { msg: body, aad: Self::MAGIC })
            .map_err(|_| VaultError::CannotDecrypt)
    }

    fn cipher(key: &[u8]) -> Result<XChaCha20Poly1305, VaultError> {
        if key.len() != KEY_LEN {
            return Err(VaultError::BadKey);
        }
        Ok(XChaCha20Poly1305::new(Key::from_slice(key)))
    }
}

/// Settings for turning a password into a key. Stored in the backup so
/// old backups still open if the defaults change later.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KdfSettings {
    /// Memory in KiB.
    pub memory_kib: u32,
    pub passes: u32,
    pub lanes: u32,
}

impl KdfSettings {
    /// 64 MiB, 3 passes: about a second on a phone, very slow to brute force.
    pub const DEFAULT: Self = Self { memory_kib: 64 * 1024, passes: 3, lanes: 1 };
    /// Cheap settings for tests only.
    #[cfg(test)]
    pub const FAST: Self = Self { memory_kib: 64, passes: 1, lanes: 1 };
}

/// Encrypts a backup with a password.
pub struct BackupCipher;

impl BackupCipher {
    const MAGIC: &'static [u8; 4] = b"VTB1";
    const SALT_LEN: usize = 16;
    /// MAGIC + three u32 settings + salt.
    const HEADER_LEN: usize = 4 + 12 + Self::SALT_LEN;

    /// Layout: MAGIC | memory | passes | lanes | salt | nonce | ciphertext.
    /// The header is authenticated too, so its settings cannot be altered.
    pub fn seal(password: &str, plaintext: &[u8], settings: KdfSettings) -> Result<Vec<u8>, VaultError> {
        let salt = Random::bytes(Self::SALT_LEN);
        let mut header = Vec::with_capacity(Self::HEADER_LEN);
        header.extend_from_slice(Self::MAGIC);
        header.extend_from_slice(&settings.memory_kib.to_le_bytes());
        header.extend_from_slice(&settings.passes.to_le_bytes());
        header.extend_from_slice(&settings.lanes.to_le_bytes());
        header.extend_from_slice(&salt);

        let key = Self::derive(password, &salt, settings)?;
        let cipher = XChaCha20Poly1305::new(Key::from_slice(&key));
        let nonce = Random::bytes(NONCE_LEN);
        let sealed = cipher
            .encrypt(XNonce::from_slice(&nonce), Payload { msg: plaintext, aad: &header })
            .map_err(|_| VaultError::CannotDecrypt)?;

        let mut out = header;
        out.extend_from_slice(&nonce);
        out.extend_from_slice(&sealed);
        Ok(out)
    }

    pub fn open(password: &str, data: &[u8]) -> Result<Vec<u8>, VaultError> {
        if data.len() < Self::HEADER_LEN + NONCE_LEN || &data[..4] != Self::MAGIC {
            return Err(VaultError::NotAVaultFile);
        }
        let read_u32 = |at: usize| u32::from_le_bytes([data[at], data[at + 1], data[at + 2], data[at + 3]]);
        let settings = KdfSettings { memory_kib: read_u32(4), passes: read_u32(8), lanes: read_u32(12) };
        // Refuse absurd settings from a crafted file instead of trying to
        // allocate gigabytes.
        if settings.memory_kib > 1024 * 1024 || settings.passes > 64 || settings.lanes > 16 {
            return Err(VaultError::NotAVaultFile);
        }
        let (header, rest) = data.split_at(Self::HEADER_LEN);
        let salt = &header[16..];
        let (nonce, body) = rest.split_at(NONCE_LEN);

        let key = Self::derive(password, salt, settings)?;
        let cipher = XChaCha20Poly1305::new(Key::from_slice(&key));
        cipher
            .decrypt(XNonce::from_slice(nonce), Payload { msg: body, aad: header })
            .map_err(|_| VaultError::CannotDecrypt)
    }

    fn derive(password: &str, salt: &[u8], settings: KdfSettings) -> Result<Vec<u8>, VaultError> {
        let params = Params::new(settings.memory_kib, settings.passes, settings.lanes, Some(KEY_LEN))
            .map_err(|e| VaultError::Kdf(e.to_string()))?;
        let argon = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
        let mut key = vec![0u8; KEY_LEN];
        argon
            .hash_password_into(password.as_bytes(), salt, &mut key)
            .map_err(|e| VaultError::Kdf(e.to_string()))?;
        Ok(key)
    }
}

/// Crash-safe file writes.
pub struct SecureFile;

impl SecureFile {
    /// Writes to a temporary file next to the target, flushes it to disk,
    /// then renames it over the target. Readers see the old file or the new
    /// one, never a half-written one.
    pub fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), VaultError> {
        use std::io::Write;
        let io = |e: std::io::Error| VaultError::Io(e.to_string());
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).map_err(io)?;
        }
        let tmp = path.with_extension("tmp");
        {
            let mut file = std::fs::File::create(&tmp).map_err(io)?;
            file.write_all(bytes).map_err(io)?;
            file.sync_all().map_err(io)?;
        }
        std::fs::rename(&tmp, path).map_err(io)
    }

    /// Reads a file, or `None` if it does not exist yet.
    pub fn read(path: &Path) -> Result<Option<Vec<u8>>, VaultError> {
        match std::fs::read(path) {
            Ok(bytes) => Ok(Some(bytes)),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(VaultError::Io(e.to_string())),
        }
    }
}

/// Cryptographically secure random bytes.
struct Random;

impl Random {
    fn bytes(len: usize) -> Vec<u8> {
        let mut buf = vec![0u8; len];
        rand::fill(&mut buf[..]);
        buf
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vault_round_trip_and_tamper_detection() {
        let key = VaultCipher::new_key();
        let sealed = VaultCipher::seal(&key, b"secret hosts").unwrap();
        assert_eq!(VaultCipher::open(&key, &sealed).unwrap(), b"secret hosts");

        let other = VaultCipher::new_key();
        assert_eq!(VaultCipher::open(&other, &sealed), Err(VaultError::CannotDecrypt));

        let mut broken = sealed.clone();
        *broken.last_mut().unwrap() ^= 1;
        assert_eq!(VaultCipher::open(&key, &broken), Err(VaultError::CannotDecrypt));
        assert_eq!(VaultCipher::open(&key, b"nope"), Err(VaultError::NotAVaultFile));
        assert_eq!(VaultCipher::seal(&[1, 2, 3], b"x"), Err(VaultError::BadKey));
    }

    #[test]
    fn same_data_encrypts_differently_each_time() {
        let key = VaultCipher::new_key();
        assert_ne!(VaultCipher::seal(&key, b"a").unwrap(), VaultCipher::seal(&key, b"a").unwrap());
    }

    #[test]
    fn backup_opens_only_with_the_password() {
        let sealed = BackupCipher::seal("hunter2", b"{\"hosts\":[]}", KdfSettings::FAST).unwrap();
        assert_eq!(BackupCipher::open("hunter2", &sealed).unwrap(), b"{\"hosts\":[]}");
        assert_eq!(BackupCipher::open("hunter3", &sealed), Err(VaultError::CannotDecrypt));

        // Changing the stored settings breaks the authentication check.
        let mut altered = sealed.clone();
        altered[8] ^= 1;
        assert!(BackupCipher::open("hunter2", &altered).is_err());
    }

    #[test]
    fn atomic_write_replaces_the_file() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("data").join("vault.bin");
        assert_eq!(SecureFile::read(&path).unwrap(), None);
        SecureFile::write_atomic(&path, b"one").unwrap();
        SecureFile::write_atomic(&path, b"two").unwrap();
        assert_eq!(SecureFile::read(&path).unwrap().unwrap(), b"two");
        assert!(!path.with_extension("tmp").exists());
    }
}
