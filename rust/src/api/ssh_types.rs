//! Plain data for opening SSH connections and the errors that can happen.

/// How to reach and log in to a server.
#[derive(Debug, Clone, PartialEq)]
pub struct ConnectOptions {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub credentials: Credentials,
    /// Host keys the user already accepted for this server, as OpenSSH
    /// public key lines. Empty on the first connection.
    pub trusted_host_keys: Vec<String>,
    /// Send a keep-alive after this many quiet seconds (0 = never).
    pub keepalive_secs: u32,
    /// Give up if the server does not answer within this many seconds.
    pub connect_timeout_secs: u32,
    /// Optional server to hop through first (like `ssh -J`).
    pub jump: Option<JumpHost>,
}

/// What VaultTerm may try when logging in. Everything that is set is
/// tried in order: key, password, then keyboard-interactive (answered with
/// the password).
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Credentials {
    pub password: Option<String>,
    /// Private key in OpenSSH or PEM text format.
    pub private_key: Option<String>,
    pub key_passphrase: Option<String>,
}

/// The server to hop through on the way to the real target.
#[derive(Debug, Clone, PartialEq)]
pub struct JumpHost {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub credentials: Credentials,
    pub trusted_host_keys: Vec<String>,
}

/// A server's identity key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostKeyInfo {
    /// Key type, for example `ssh-ed25519`.
    pub algorithm: String,
    /// SHA256 fingerprint, as OpenSSH shows it.
    pub fingerprint: String,
    /// The full public key line, to store once the user trusts it.
    pub public_key: String,
}

/// Why a connection failed, in terms the app can act on.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum ConnectError {
    /// First visit: the user must check and accept the server's key.
    #[error("{host}:{port} is not known yet")]
    HostKeyUnknown { host: String, port: u16, key: HostKeyInfo },
    /// The server's key is different from the one accepted before. This can
    /// mean someone is intercepting the connection.
    #[error("the identity of {host}:{port} changed")]
    HostKeyChanged { host: String, port: u16, key: HostKeyInfo },
    #[error("login to {host} was refused")]
    AuthFailed {
        host: String,
        /// Methods VaultTerm tried, such as "publickey" or "password".
        tried: Vec<String>,
        /// Methods the server said it accepts.
        server_accepts: Vec<String>,
    },
    #[error("the private key needs its passphrase")]
    KeyNeedsPassphrase,
    #[error("the passphrase of the private key is wrong")]
    KeyWrongPassphrase,
    #[error("the private key could not be read: {reason}")]
    KeyUnreadable { reason: String },
    #[error("could not reach {host}:{port}: {message}")]
    Network { host: String, port: u16, message: String },
    #[error("the server did not answer in time")]
    Timeout,
    #[error("SSH error: {message}")]
    Protocol { message: String },
}

/// Facts about an open session, for display.
#[derive(Debug, Clone, PartialEq)]
pub struct SessionInfo {
    pub host: String,
    pub port: u16,
    pub username: String,
    /// The jump host's name when the session goes through one.
    pub via: Option<String>,
    /// Text the server showed before login (often a legal notice).
    pub banner: Option<String>,
    pub host_key: HostKeyInfo,
}

/// Result of running one command without a terminal.
#[derive(Debug, Clone, PartialEq)]
pub struct ExecOutput {
    pub stdout: String,
    pub stderr: String,
    /// The command's exit code, if the server reported one.
    pub exit_code: Option<u32>,
    /// True when the output was cut at the size limit.
    pub truncated: bool,
}
