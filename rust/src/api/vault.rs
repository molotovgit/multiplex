//! Encrypted storage for Flutter: the app's data file and password
//! protected backups.

use std::path::PathBuf;

use crate::engine::vault::{BackupCipher, KdfSettings, SecureFile, VaultCipher};

/// A fresh random 32-byte key for the data file. The app stores it in the
/// platform's secure key store.
#[flutter_rust_bridge::frb(sync)]
pub fn vault_new_key() -> Vec<u8> {
    VaultCipher::new_key()
}

/// Encrypts `contents` with `key` and writes it to `path` crash-safely.
pub async fn vault_save(path: String, key: Vec<u8>, contents: String) -> anyhow::Result<()> {
    tokio::task::spawn_blocking(move || {
        let sealed = VaultCipher::seal(&key, contents.as_bytes())?;
        SecureFile::write_atomic(&PathBuf::from(path), &sealed)?;
        anyhow::Ok(())
    })
    .await??;
    Ok(())
}

/// Reads and decrypts the data file. Returns `None` when it does not exist
/// yet (first start).
pub async fn vault_load(path: String, key: Vec<u8>) -> anyhow::Result<Option<String>> {
    tokio::task::spawn_blocking(move || {
        let Some(bytes) = SecureFile::read(&PathBuf::from(path))? else {
            return anyhow::Ok(None);
        };
        let plain = VaultCipher::open(&key, &bytes)?;
        anyhow::Ok(Some(String::from_utf8(plain)?))
    })
    .await?
}

/// Encrypts a backup with the user's password.
pub async fn backup_seal(password: String, contents: String) -> anyhow::Result<Vec<u8>> {
    tokio::task::spawn_blocking(move || {
        anyhow::Ok(BackupCipher::seal(&password, contents.as_bytes(), KdfSettings::DEFAULT)?)
    })
    .await?
}

/// Opens a backup made with [`backup_seal`].
pub async fn backup_open(password: String, data: Vec<u8>) -> anyhow::Result<String> {
    tokio::task::spawn_blocking(move || {
        let plain = BackupCipher::open(&password, &data)?;
        anyhow::Ok(String::from_utf8(plain)?)
    })
    .await?
}
