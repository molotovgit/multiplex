//! The SOCKS5 handshake for dynamic forwarding (`ssh -D`).
//!
//! A browser or app set to use a SOCKS5 proxy first says which address it
//! wants. We read that request, open an SSH channel to that address, tell
//! the app whether it worked, and then just pass bytes along.
//! Only the parts real apps use are supported: no login, CONNECT only.

use tokio::io::{AsyncReadExt, AsyncWriteExt};

/// Where the app wants to go.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SocksTarget {
    pub host: String,
    pub port: u16,
}

/// Reads and answers the SOCKS5 greeting and request.
pub struct Socks5;

impl Socks5 {
    const VERSION: u8 = 5;
    const NO_AUTH: u8 = 0;
    const NO_ACCEPTABLE_METHOD: u8 = 0xFF;
    const CMD_CONNECT: u8 = 1;
    const ATYP_IPV4: u8 = 1;
    const ATYP_DOMAIN: u8 = 3;
    const ATYP_IPV6: u8 = 4;
    const REPLY_OK: u8 = 0;
    const REPLY_HOST_UNREACHABLE: u8 = 4;
    const REPLY_COMMAND_NOT_SUPPORTED: u8 = 7;

    /// Reads the greeting and the CONNECT request. On anything we do not
    /// support, answers with the matching error and returns an error.
    pub async fn accept<S>(stream: &mut S) -> anyhow::Result<SocksTarget>
    where
        S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
    {
        let mut head = [0u8; 2];
        stream.read_exact(&mut head).await?;
        anyhow::ensure!(head[0] == Self::VERSION, "not a SOCKS5 client");
        let mut methods = vec![0u8; usize::from(head[1])];
        stream.read_exact(&mut methods).await?;
        if !methods.contains(&Self::NO_AUTH) {
            stream.write_all(&[Self::VERSION, Self::NO_ACCEPTABLE_METHOD]).await?;
            anyhow::bail!("client wants a SOCKS login, which is not supported");
        }
        stream.write_all(&[Self::VERSION, Self::NO_AUTH]).await?;

        let mut request = [0u8; 4];
        stream.read_exact(&mut request).await?;
        anyhow::ensure!(request[0] == Self::VERSION, "bad SOCKS5 request");
        if request[1] != Self::CMD_CONNECT {
            Self::reply(stream, Self::REPLY_COMMAND_NOT_SUPPORTED).await?;
            anyhow::bail!("only CONNECT is supported");
        }
        let host = match request[3] {
            Self::ATYP_IPV4 => {
                let mut ip = [0u8; 4];
                stream.read_exact(&mut ip).await?;
                std::net::Ipv4Addr::from(ip).to_string()
            }
            Self::ATYP_IPV6 => {
                let mut ip = [0u8; 16];
                stream.read_exact(&mut ip).await?;
                std::net::Ipv6Addr::from(ip).to_string()
            }
            Self::ATYP_DOMAIN => {
                let len = stream.read_u8().await?;
                let mut name = vec![0u8; usize::from(len)];
                stream.read_exact(&mut name).await?;
                String::from_utf8(name)?
            }
            other => anyhow::bail!("unknown SOCKS5 address type {other}"),
        };
        let port = stream.read_u16().await?;
        Ok(SocksTarget { host, port })
    }

    /// Tells the app the connection is ready.
    pub async fn confirm<S: tokio::io::AsyncWrite + Unpin>(stream: &mut S) -> std::io::Result<()> {
        Self::reply(stream, Self::REPLY_OK).await
    }

    /// Tells the app the target could not be reached.
    pub async fn refuse<S: tokio::io::AsyncWrite + Unpin>(stream: &mut S) -> std::io::Result<()> {
        Self::reply(stream, Self::REPLY_HOST_UNREACHABLE).await
    }

    async fn reply<S: tokio::io::AsyncWrite + Unpin>(stream: &mut S, code: u8) -> std::io::Result<()> {
        // The bound address is not meaningful here, so send 0.0.0.0:0.
        stream.write_all(&[Self::VERSION, code, 0, Self::ATYP_IPV4, 0, 0, 0, 0, 0, 0]).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn run(client_bytes: Vec<u8>) -> (anyhow::Result<SocksTarget>, Vec<u8>) {
        let (mut ours, mut theirs) = tokio::io::duplex(1024);
        theirs.write_all(&client_bytes).await.unwrap();
        let result = Socks5::accept(&mut ours).await;
        drop(ours);
        let mut answer = Vec::new();
        theirs.read_to_end(&mut answer).await.unwrap();
        (result, answer)
    }

    #[tokio::test]
    async fn reads_a_domain_request() {
        let mut bytes = vec![5, 1, 0, 5, 1, 0, 3, 11];
        bytes.extend_from_slice(b"example.com");
        bytes.extend_from_slice(&443u16.to_be_bytes());
        let (target, answer) = run(bytes).await;
        assert_eq!(target.unwrap(), SocksTarget { host: "example.com".into(), port: 443 });
        assert_eq!(answer, vec![5, 0]);
    }

    #[tokio::test]
    async fn reads_an_ipv4_request() {
        let (target, _) = run(vec![5, 1, 0, 5, 1, 0, 1, 10, 0, 0, 7, 0, 22]).await;
        assert_eq!(target.unwrap(), SocksTarget { host: "10.0.0.7".into(), port: 22 });
    }

    #[tokio::test]
    async fn refuses_logins_and_other_commands() {
        let (result, answer) = run(vec![5, 1, 2]).await;
        assert!(result.is_err());
        assert_eq!(answer, vec![5, 0xFF]);

        // BIND (2) instead of CONNECT.
        let (result, answer) = run(vec![5, 1, 0, 5, 2, 0, 1, 1, 2, 3, 4, 0, 80]).await;
        assert!(result.is_err());
        assert_eq!(answer[2..4], [5, 7]);
    }
}
