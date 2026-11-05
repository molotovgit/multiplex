//! SSH key management for Flutter: create, import and inspect keys.

use crate::engine::keys::KeyFactory;

/// Which kind of key to create.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyKind {
    /// Modern default: small, fast and secure.
    Ed25519,
    EcdsaP256,
    /// For old servers that only accept RSA.
    Rsa3072,
    Rsa4096,
}

/// Everything the app stores and shows about a key pair.
#[derive(Debug, Clone, PartialEq)]
pub struct KeyPairInfo {
    /// The private key in OpenSSH text format (encrypted if it has a
    /// passphrase).
    pub private_pem: String,
    /// The public key line for `~/.ssh/authorized_keys`.
    pub public_openssh: String,
    /// SHA256 fingerprint, as `ssh-keygen -l` prints it.
    pub fingerprint: String,
    /// Key type, for example `ssh-ed25519`.
    pub algorithm: String,
    pub comment: String,
    /// True when the private key needs a passphrase.
    pub encrypted: bool,
}

/// Creates a new key pair. Runs off the UI thread because RSA keys take a
/// moment to generate.
pub async fn generate_key(kind: KeyKind, comment: String, passphrase: Option<String>) -> anyhow::Result<KeyPairInfo> {
    let pair = tokio::task::spawn_blocking(move || KeyFactory::generate(kind, &comment, passphrase.as_deref()))
        .await
        .map_err(|e| anyhow::anyhow!("key generation stopped: {e}"))??;
    Ok(pair)
}

/// Checks a pasted or imported private key and describes it.
pub fn inspect_private_key(pem: String, passphrase: Option<String>) -> anyhow::Result<KeyPairInfo> {
    Ok(KeyFactory::inspect(&pem, passphrase.as_deref())?)
}

/// True when the key text needs a passphrase.
#[flutter_rust_bridge::frb(sync)]
pub fn private_key_is_encrypted(pem: String) -> bool {
    KeyFactory::is_encrypted(&pem)
}

/// SHA256 fingerprint of a public key line.
#[flutter_rust_bridge::frb(sync)]
pub fn public_key_fingerprint(public_openssh: String) -> anyhow::Result<String> {
    Ok(KeyFactory::fingerprint_of_public(&public_openssh)?)
}
