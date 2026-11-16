//! Plain data about the app's Tailscale node.

/// The node and the devices on the tailnet.
#[derive(Debug, Clone, Default, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TailscaleStatus {
    /// NoState, NeedsLogin, NeedsMachineAuth, Stopped, Starting or Running.
    pub state: String,
    /// The page to open to sign in, while signing in.
    #[serde(default)]
    pub auth_url: String,
    #[serde(default)]
    pub tailnet: String,
    /// Who signed in (an e-mail or login name).
    #[serde(default)]
    pub user: String,
    /// This phone.
    #[serde(default, rename = "self")]
    pub this_device: Option<TailscaleDevice>,
    #[serde(default, rename = "peers", deserialize_with = "null_as_empty")]
    pub devices: Vec<TailscaleDevice>,
    #[serde(default)]
    pub error: String,
}

/// One device on the tailnet.
#[derive(Debug, Clone, Default, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TailscaleDevice {
    pub name: String,
    /// Full MagicDNS name, for example `omarchy.tail1234.ts.net`.
    #[serde(default)]
    pub dns_name: String,
    #[serde(default, deserialize_with = "null_as_empty")]
    pub ips: Vec<String>,
    #[serde(default)]
    pub os: String,
    #[serde(default)]
    pub online: bool,
    /// Reached peer to peer (fastest), not through a Tailscale relay.
    #[serde(default)]
    pub direct: bool,
    /// The relay region in use when not direct (for example `fra`).
    #[serde(default)]
    pub relay: String,
}

fn null_as_empty<'de, D, T>(d: D) -> Result<Vec<T>, D::Error>
where
    D: serde::Deserializer<'de>,
    T: serde::Deserialize<'de>,
{
    use serde::Deserialize;
    Ok(Option::<Vec<T>>::deserialize(d)?.unwrap_or_default())
}
