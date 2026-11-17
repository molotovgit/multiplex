//! Sharing with a paired computer: text to and from its clipboard, a link
//! opened in its browser, where files for it go, and what it has waiting
//! for the phone. All through `multiplex …` on the computer, over the SSH
//! connection that is already open; files themselves travel by SFTP.

use multiplex_proto::share::{self as proto, Clipboard, MAX_CLIP};

use super::ssh::Connection;
use crate::api::ssh_types::ExecOutput;

/// Why a share command failed, in words for the user.
fn problem(out: &ExecOutput) -> anyhow::Error {
    if out.exit_code == Some(127) {
        return anyhow::anyhow!("This computer does not have the Multiplex package (or it is an old one). Install it there, then try again.");
    }
    let said = out.stderr.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or_default().trim();
    let said = said.strip_prefix("multiplex: ").unwrap_or(said);
    if said.is_empty() {
        return anyhow::anyhow!("The computer did not answer.");
    }
    let mut text = said.to_owned();
    if let Some(first) = text.get_mut(..1) {
        first.make_ascii_uppercase();
    }
    anyhow::anyhow!("{text}")
}

async fn run(conn: &Connection, command: &str) -> anyhow::Result<String> {
    let out = conn.exec(command, MAX_CLIP * 2).await?;
    if out.exit_code == Some(0) {
        Ok(out.stdout)
    } else {
        Err(problem(&out))
    }
}

/// The folder on the computer that files from the phone go to.
pub async fn inbox(conn: &Connection) -> anyhow::Result<String> {
    let folder = run(conn, &proto::inbox_command()).await?.trim().to_owned();
    if folder.starts_with('/') {
        Ok(folder)
    } else {
        Err(anyhow::anyhow!("The computer's answer was not understood."))
    }
}

/// Tells the computer what arrived, so it can say so on its screen.
pub async fn received(conn: &Connection, phone: &str, names: &[String]) -> anyhow::Result<()> {
    if names.is_empty() {
        return Ok(());
    }
    let names: Vec<String> = names.iter().map(|n| proto::clean_file_name(n)).collect();
    run(conn, &proto::received_command(phone, &names)).await.map(|_| ())
}

/// Puts text on the computer's clipboard.
pub async fn copy(conn: &Connection, text: &str) -> anyhow::Result<()> {
    if text.len() > MAX_CLIP {
        anyhow::bail!("That is too much text for a clipboard.");
    }
    let out = conn.exec_with_input(&proto::copy_command(), text.as_bytes(), 4096).await?;
    if out.exit_code == Some(0) {
        Ok(())
    } else {
        Err(problem(&out))
    }
}

/// The text on the computer's clipboard, if it holds text.
pub async fn paste(conn: &Connection) -> anyhow::Result<Option<String>> {
    let reply = run(conn, &proto::paste_command()).await?;
    let clipboard: Clipboard = serde_json::from_str(reply.trim()).map_err(|_| anyhow::anyhow!("The computer's answer was not understood."))?;
    Ok(clipboard.text)
}

/// Opens a web link in the computer's browser.
pub async fn open(conn: &Connection, url: &str) -> anyhow::Result<()> {
    let command = proto::open_command(url).map_err(|_| anyhow::anyhow!("Only web links (http or https) can be opened on the computer."))?;
    run(conn, &command).await.map(|_| ())
}

async fn tell(conn: &Connection, command: &str, json: String) -> anyhow::Result<()> {
    let out = conn.exec_with_input(command, json.as_bytes(), 4096).await?;
    if out.exit_code == Some(0) {
        Ok(())
    } else {
        Err(problem(&out))
    }
}

/// Tells the computer how the phone is doing (for `multiplex devices`).
pub async fn status(conn: &Connection, phone: &str, status: &proto::PhoneStatus) -> anyhow::Result<()> {
    tell(conn, &proto::status_command(phone), serde_json::to_string(&status.cleaned())?).await
}

/// Shows one of the phone's notifications on the computer's screen.
pub async fn notice(conn: &Connection, phone: &str, notice: &proto::PhoneNotice) -> anyhow::Result<()> {
    tell(conn, &proto::notice_command(phone), serde_json::to_string(&notice.cleaned())?).await
}

/// A call on the phone began or ended: the computer pauses what is
/// playing, and carries on with it afterwards.
pub async fn call(conn: &Connection, phone: &str, active: bool) -> anyhow::Result<()> {
    run(conn, &proto::call_command(phone, active)).await.map(|_| ())
}

/// Signs an approval request with the phone's own key (an OpenSSH
/// ed25519 private key, as the app stores it). The answer is the
/// signature in base64, which only this key can make and which is good
/// for this one request.
pub fn approval_signature(private_key: &str, id: &str, reason: &str, challenge: &str) -> anyhow::Result<String> {
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    use ed25519_dalek::Signer;
    use russh::keys::ssh_key::private::KeypairData;

    let key = russh::keys::decode_secret_key(private_key.trim(), None).map_err(|_| anyhow::anyhow!("This phone's key could not be read."))?;
    let KeypairData::Ed25519(pair) = key.key_data() else { anyhow::bail!("This phone's key is not of the kind approvals use.") };
    let signer = ed25519_dalek::SigningKey::from_bytes(&pair.private.to_bytes());
    let id = proto::clean_id(id).map_err(|err| anyhow::anyhow!("{err}"))?;
    Ok(STANDARD.encode(signer.sign(&proto::approval_message(&id, reason, challenge)).to_bytes()))
}

/// Gives the computer the phone's answer to an approval: a signature, or
/// "no".
pub async fn approved(conn: &Connection, id: &str, answer: &str) -> anyhow::Result<()> {
    let command = proto::approved_command(id).map_err(|err| anyhow::anyhow!("{err}"))?;
    tell(conn, &command, answer.to_owned()).await
}

/// The phone has fetched a waiting file: the computer forgets it.
pub async fn done(conn: &Connection, id: &str) -> anyhow::Result<()> {
    let command = proto::done_command(id).map_err(|err| anyhow::anyhow!("{err}"))?;
    run(conn, &command).await.map(|_| ())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_approval_signed_here_is_one_the_computer_accepts() {
        use base64::engine::general_purpose::STANDARD;
        use base64::Engine;
        use russh::keys::ssh_key::private::{Ed25519Keypair, KeypairData};
        use russh::keys::ssh_key::LineEnding;
        use russh::keys::PrivateKey;

        // A phone key as the app keeps it.
        let pair = Ed25519Keypair::from_seed(&[9u8; 32]);
        let public = pair.public.0;
        let pem = PrivateKey::new(KeypairData::Ed25519(pair), "multiplex-phone").unwrap().to_openssh(LineEnding::LF).unwrap().to_string();
        let (id, reason, challenge) = ("00112233aabbccdd", "sudo pacman -Syu", "Y2hhbGxlbmdl");
        let signature: [u8; 64] = STANDARD.decode(approval_signature(&pem, id, reason, challenge).unwrap()).unwrap().try_into().unwrap();
        // The computer's check: the phone's public key over the same message.
        let key = ed25519_dalek::VerifyingKey::from_bytes(&public).unwrap();
        let signature = ed25519_dalek::Signature::from_bytes(&signature);
        assert!(key.verify_strict(&proto::approval_message(id, reason, challenge), &signature).is_ok());
        assert!(key.verify_strict(&proto::approval_message(id, "sudo rm -rf /", challenge), &signature).is_err());
        assert!(approval_signature("not a key", id, reason, challenge).is_err());
        assert!(approval_signature(&pem, "not an id", reason, challenge).is_err());
    }

    #[test]
    fn failures_are_put_in_words() {
        let out = |code, stderr: &str| ExecOutput { stdout: String::new(), stderr: stderr.to_owned(), exit_code: code, truncated: false };
        assert!(problem(&out(Some(127), "sh: multiplex: not found")).to_string().contains("Multiplex package"));
        assert_eq!(problem(&out(Some(1), "multiplex: wl-copy (from wl-clipboard) is needed for the clipboard\n")).to_string(), "Wl-copy (from wl-clipboard) is needed for the clipboard");
        assert_eq!(problem(&out(None, "")).to_string(), "The computer did not answer.");
    }
}
