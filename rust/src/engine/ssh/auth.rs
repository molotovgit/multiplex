//! Logging in once the encrypted connection is up.
//!
//! We try what the user gave us, strongest first: the private key, then
//! the password, then "keyboard-interactive" (many servers that turn off
//! plain password login still ask for the password this way).

use russh::client::{Handle, KeyboardInteractiveAuthResponse};
use russh::keys::PrivateKeyWithHashAlg;
use russh::MethodSet;

use super::handler::ClientHandler;
use crate::api::ssh_types::{ConnectError, Credentials};
use crate::engine::keys::{KeyError, KeyFactory};

/// Runs the login steps for one user on one connection.
pub struct Authenticator<'a> {
    handle: &'a mut Handle<ClientHandler>,
    host: &'a str,
    username: &'a str,
    tried: Vec<String>,
    server_accepts: Vec<String>,
}

impl<'a> Authenticator<'a> {
    /// Keyboard-interactive can ask several rounds of questions; stop after
    /// this many so a confused server cannot keep us looping.
    const MAX_PROMPT_ROUNDS: usize = 5;

    pub fn new(handle: &'a mut Handle<ClientHandler>, host: &'a str, username: &'a str) -> Self {
        Self {
            handle,
            host,
            username,
            tried: Vec::new(),
            server_accepts: Vec::new(),
        }
    }

    pub async fn login(mut self, credentials: &Credentials) -> Result<(), ConnectError> {
        let password = credentials.password.as_deref().filter(|p| !p.is_empty());
        let key_text = credentials.private_key.as_deref().filter(|k| !k.trim().is_empty());

        if key_text.is_none() && password.is_none() {
            // Some servers (and test setups) let anyone in.
            let result = self.handle.authenticate_none(self.username).await.map_err(Self::protocol)?;
            if self.done("none", result.success(), Self::remaining(&result)) {
                return Ok(());
            }
        }

        if let Some(text) = key_text {
            let key = KeyFactory::decode_shared(text, credentials.key_passphrase.as_deref()).map_err(|e| match e {
                KeyError::PassphraseNeeded => ConnectError::KeyNeedsPassphrase,
                KeyError::WrongPassphrase => ConnectError::KeyWrongPassphrase,
                other => ConnectError::KeyUnreadable { reason: other.to_string() },
            })?;
            // RSA keys must be signed with the hash the server prefers.
            let hash = self
                .handle
                .best_supported_rsa_hash()
                .await
                .map_err(Self::protocol)?
                .flatten();
            let result = self
                .handle
                .authenticate_publickey(self.username, PrivateKeyWithHashAlg::new(key, hash))
                .await
                .map_err(Self::protocol)?;
            if self.done("publickey", result.success(), Self::remaining(&result)) {
                return Ok(());
            }
        }

        if let Some(password) = password {
            if self.server_allows("password") {
                let result = self
                    .handle
                    .authenticate_password(self.username, password)
                    .await
                    .map_err(Self::protocol)?;
                if self.done("password", result.success(), Self::remaining(&result)) {
                    return Ok(());
                }
            }
            if self.server_allows("keyboard-interactive") && self.keyboard_interactive(password).await? {
                return Ok(());
            }
        }

        Err(ConnectError::AuthFailed {
            host: self.host.to_owned(),
            tried: self.tried,
            server_accepts: self.server_accepts,
        })
    }

    /// Answers every question the server asks with the password.
    async fn keyboard_interactive(&mut self, password: &str) -> Result<bool, ConnectError> {
        let mut response = self
            .handle
            .authenticate_keyboard_interactive_start(self.username, None::<String>)
            .await
            .map_err(Self::protocol)?;
        for _ in 0..Self::MAX_PROMPT_ROUNDS {
            match response {
                KeyboardInteractiveAuthResponse::Success => {
                    self.tried.push("keyboard-interactive".into());
                    return Ok(true);
                }
                KeyboardInteractiveAuthResponse::Failure { remaining_methods, .. } => {
                    self.done("keyboard-interactive", false, Self::method_names(&remaining_methods));
                    return Ok(false);
                }
                KeyboardInteractiveAuthResponse::InfoRequest { ref prompts, .. } => {
                    let answers = prompts.iter().map(|_| password.to_owned()).collect();
                    response = self
                        .handle
                        .authenticate_keyboard_interactive_respond(answers)
                        .await
                        .map_err(Self::protocol)?;
                }
            }
        }
        self.tried.push("keyboard-interactive".into());
        Ok(false)
    }

    /// Records an attempt. Returns true when we are logged in.
    fn done(&mut self, method: &str, success: bool, remaining: Vec<String>) -> bool {
        self.tried.push(method.to_owned());
        if !remaining.is_empty() {
            self.server_accepts = remaining;
        }
        success
    }

    /// Until the server has told us its methods, try everything.
    fn server_allows(&self, method: &str) -> bool {
        self.server_accepts.is_empty() || self.server_accepts.iter().any(|m| m == method)
    }

    fn remaining(result: &russh::client::AuthResult) -> Vec<String> {
        match result {
            russh::client::AuthResult::Success => Vec::new(),
            russh::client::AuthResult::Failure { remaining_methods, .. } => Self::method_names(remaining_methods),
        }
    }

    fn method_names(methods: &MethodSet) -> Vec<String> {
        methods.iter().map(|m| <&str>::from(m).to_owned()).collect()
    }

    fn protocol(err: russh::Error) -> ConnectError {
        ConnectError::Protocol { message: err.to_string() }
    }
}
