//! `multiplex agent`: an SSH agent whose keys live on the paired phones.
//!
//! `ssh` and `git` talk to it like to any agent (point `SSH_AUTH_SOCK` at
//! its socket). It lists the paired phones' public keys; when asked to
//! sign, it passes the request to that phone over the link, the phone's
//! owner confirms with a fingerprint, and the signature comes back. The
//! private key never leaves the phone.
//!
//! Only real SSH requests are passed on (a login, or an SSH signature
//! such as Git makes): see `multiplex_proto::sign`. The phone checks that
//! again itself.

use std::io::{Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;

use anyhow::{anyhow, bail, Context, Result};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use multiplex_proto::ed25519_key_bytes;
use multiplex_proto::share::LinkEvent;
use multiplex_proto::sign::{ed25519_blob, read_request, MAX_SIGN};

use crate::share::{ask_and_wait, linked, runtime_dir};
use crate::store::Store;

// The agent protocol's message numbers.
const FAILURE: u8 = 5;
const REQUEST_IDENTITIES: u8 = 11;
const IDENTITIES_ANSWER: u8 = 12;
const SIGN_REQUEST: u8 = 13;
const SIGN_RESPONSE: u8 = 14;

fn socket_path() -> PathBuf {
    runtime_dir().join("agent.sock")
}

/// The paired phones with their keys.
fn phones() -> Vec<(String, [u8; 32])> {
    let devices = Store::open().and_then(|s| s.devices()).unwrap_or_default();
    devices.into_iter().filter_map(|d| Some((d.name, ed25519_key_bytes(&d.key)?))).collect()
}

fn put(out: &mut Vec<u8>, bytes: &[u8]) {
    out.extend_from_slice(&(bytes.len() as u32).to_be_bytes());
    out.extend_from_slice(bytes);
}

/// Takes one length-prefixed field off the front.
fn take<'a>(rest: &mut &'a [u8]) -> Option<&'a [u8]> {
    let len = u32::from_be_bytes(rest.get(..4)?.try_into().ok()?) as usize;
    let field = rest.get(4..4 + len)?;
    *rest = &rest[4 + len..];
    Some(field)
}

/// The answer to "which keys do you have".
fn identities(phones: &[(String, [u8; 32])]) -> Vec<u8> {
    let mut out = vec![IDENTITIES_ANSWER];
    out.extend_from_slice(&(phones.len() as u32).to_be_bytes());
    for (name, key) in phones {
        put(&mut out, &ed25519_blob(key));
        put(&mut out, format!("multiplex:{name}").as_bytes());
    }
    out
}

/// A signature as the agent protocol carries it.
fn sign_response(signature: &[u8; 64]) -> Vec<u8> {
    let mut blob = Vec::new();
    put(&mut blob, b"ssh-ed25519");
    put(&mut blob, signature);
    let mut out = vec![SIGN_RESPONSE];
    put(&mut out, &blob);
    out
}

/// A signing request, taken apart: whose key, and what to sign.
fn parse_sign(payload: &[u8]) -> Option<(&[u8], &[u8])> {
    let mut rest = payload;
    let key = take(&mut rest)?;
    let data = take(&mut rest)?;
    // Four bytes of flags follow; none of them changes an ed25519 signature.
    (rest.len() == 4 && data.len() <= MAX_SIGN).then_some((key, data))
}

/// Has the phone sign, if it is one of ours, connected, and the request
/// is one an SSH key is for. The phone's answer is checked before it is
/// handed on.
fn sign(payload: &[u8], ask: &dyn Fn(&str, &[u8]) -> Option<String>) -> Option<Vec<u8>> {
    let (key_blob, data) = parse_sign(payload)?;
    let (phone, key) = phones().into_iter().find(|(_, key)| ed25519_blob(key) == key_blob)?;
    let Some(request) = read_request(data, &key) else {
        eprintln!("multiplex: refused to pass on a signing request that is neither a login nor an SSH signature");
        return None;
    };
    eprintln!("multiplex: asking {phone}: {}", request.describe());
    let answer = ask(&phone, data)?;
    let signature: [u8; 64] = STANDARD.decode(answer.trim()).ok()?.try_into().ok()?;
    let verified = ed25519_dalek::VerifyingKey::from_bytes(&key).ok()?.verify_strict(data, &ed25519_dalek::Signature::from_bytes(&signature)).is_ok();
    if !verified {
        eprintln!("multiplex: {phone}'s answer was not a signature by its key");
        return None;
    }
    Some(sign_response(&signature))
}

/// Asks over the link and waits for the phone.
fn ask_phone(phone: &str, data: &[u8]) -> Option<String> {
    if !linked(phone) {
        eprintln!("multiplex: {phone} is not connected, so its key cannot be used right now");
        return None;
    }
    match ask_and_wait(phone, |id| LinkEvent::Sign { id: id.to_owned(), data: STANDARD.encode(data) }) {
        Ok((_, Some(answer))) if answer.trim() != "no" => Some(answer),
        Ok((_, Some(_))) => {
            eprintln!("multiplex: refused on {phone}");
            None
        }
        Ok((_, None)) => {
            eprintln!("multiplex: {phone} did not answer in time");
            None
        }
        Err(err) => {
            eprintln!("multiplex: {err:#}");
            None
        }
    }
}

fn respond(message: &[u8], ask: &dyn Fn(&str, &[u8]) -> Option<String>) -> Vec<u8> {
    match message.split_first() {
        Some((&REQUEST_IDENTITIES, [])) => identities(&phones()),
        Some((&SIGN_REQUEST, payload)) => sign(payload, ask).unwrap_or_else(|| vec![FAILURE]),
        _ => vec![FAILURE],
    }
}

fn serve_client(mut stream: UnixStream) {
    loop {
        let mut len = [0u8; 4];
        if stream.read_exact(&mut len).is_err() {
            return;
        }
        let len = u32::from_be_bytes(len) as usize;
        // A request is small; anything else is not an SSH client.
        if len == 0 || len > MAX_SIGN + 4096 {
            return;
        }
        let mut message = vec![0u8; len];
        if stream.read_exact(&mut message).is_err() {
            return;
        }
        let reply = respond(&message, &ask_phone);
        if stream.write_all(&(reply.len() as u32).to_be_bytes()).and_then(|()| stream.write_all(&reply)).is_err() {
            return;
        }
    }
}

/// `multiplex agent [--socket]`.
pub fn run(args: &[&str]) -> Result<()> {
    let path = socket_path();
    match args {
        ["--socket"] => {
            println!("{}", path.display());
            return Ok(());
        }
        [] => {}
        _ => bail!("use: multiplex agent [--socket]"),
    }
    if UnixStream::connect(&path).is_ok() {
        bail!("the agent is already running at {}", path.display());
    }
    // A socket nobody answers at is left over from a run that ended.
    let _ = std::fs::remove_file(&path);
    let listener = UnixListener::bind(&path).with_context(|| format!("could not listen at {}", path.display()))?;
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))?;
    eprintln!("The agent is listening. To use the phone's key in a shell:");
    eprintln!("  export SSH_AUTH_SOCK={}", path.display());
    for stream in listener.incoming() {
        let stream = stream.map_err(|err| anyhow!("the agent's socket failed: {err}"))?;
        std::thread::spawn(move || serve_client(stream));
    }
    Ok(())
}

/// `multiplex key [<phone>]`: the phones' public keys, to give to servers
/// (`authorized_keys`) or to Git as a signing key.
pub fn key(args: &[&str]) -> Result<()> {
    let all = Store::open()?.devices()?;
    let wanted: Vec<_> = match args {
        [] => all,
        [name] => all.into_iter().filter(|d| d.name.eq_ignore_ascii_case(name)).collect(),
        _ => bail!("use: multiplex key [<phone>]"),
    };
    if wanted.is_empty() {
        bail!("no such phone is paired (see `multiplex devices`)");
    }
    for device in wanted {
        println!("{} {}", device.key, device.name.replace(' ', "-"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use ed25519_dalek::Signer;

    use super::*;

    #[test]
    fn the_list_of_keys_is_what_an_ssh_client_expects() {
        let answer = identities(&[("Sam's phone".to_owned(), [1u8; 32])]);
        assert_eq!(answer[0], IDENTITIES_ANSWER);
        assert_eq!(&answer[1..5], &1u32.to_be_bytes());
        let mut rest = &answer[5..];
        assert_eq!(take(&mut rest).unwrap(), ed25519_blob(&[1u8; 32]));
        assert_eq!(take(&mut rest).unwrap(), b"multiplex:Sam's phone");
        assert!(rest.is_empty());
        assert_eq!(identities(&[]), [IDENTITIES_ANSWER, 0, 0, 0, 0]);
    }

    #[test]
    fn a_sign_request_is_taken_apart_strictly() {
        let mut payload = Vec::new();
        put(&mut payload, b"key");
        put(&mut payload, b"data");
        payload.extend_from_slice(&[0, 0, 0, 0]);
        assert_eq!(parse_sign(&payload), Some((&b"key"[..], &b"data"[..])));
        assert_eq!(parse_sign(&payload[..payload.len() - 1]), None);
        assert_eq!(parse_sign(&[payload.clone(), vec![0]].concat()), None);
        assert_eq!(parse_sign(b""), None);
        let mut huge = Vec::new();
        put(&mut huge, b"key");
        put(&mut huge, &vec![0u8; MAX_SIGN + 1]);
        huge.extend_from_slice(&[0; 4]);
        assert_eq!(parse_sign(&huge), None);
    }

    #[test]
    fn a_signature_goes_back_in_the_agents_wrapping() {
        let signer = ed25519_dalek::SigningKey::from_bytes(&[4u8; 32]);
        let signature = signer.sign(b"data").to_bytes();
        let response = sign_response(&signature);
        assert_eq!(response[0], SIGN_RESPONSE);
        let mut rest = &response[1..];
        let mut blob = take(&mut rest).unwrap();
        assert!(rest.is_empty());
        assert_eq!(take(&mut blob).unwrap(), b"ssh-ed25519");
        assert_eq!(take(&mut blob).unwrap(), signature);
        assert!(blob.is_empty());
    }

    #[test]
    fn anything_but_the_two_questions_fails() {
        let never = |_: &str, _: &[u8]| -> Option<String> { panic!("no phone should be asked") };
        assert_eq!(respond(&[], &never), [FAILURE]);
        assert_eq!(respond(&[27, 0, 0], &never), [FAILURE], "extensions");
        assert_eq!(respond(&[17], &never), [FAILURE], "adding a key");
        assert_eq!(respond(&[REQUEST_IDENTITIES, 1], &never), [FAILURE], "a list request with something after it");
        // A sign request for a key that is no paired phone's.
        let mut payload = vec![SIGN_REQUEST];
        put(&mut payload, &ed25519_blob(&[0xEE; 32]));
        put(&mut payload, b"data");
        payload.extend_from_slice(&[0; 4]);
        assert_eq!(respond(&payload, &never), [FAILURE]);
    }
}
