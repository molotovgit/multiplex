//! Wake-on-LAN: switching a paired computer on from the phone.
//!
//! A "magic packet" (six bytes of 0xFF, then the network card's address
//! sixteen times) is broadcast on the home network; the card listens for
//! it while the computer sleeps or is off. It only reaches the computer
//! from the same network, and only if the card and the firmware have
//! Wake-on-LAN turned on (`multiplex setup` does the card's part).

use std::net::{Ipv4Addr, SocketAddrV4};
use std::time::Duration;

use tokio::net::UdpSocket;

/// The "discard" port, the usual one for magic packets (7 is also seen).
const PORTS: [u16; 2] = [9, 7];

/// A network card address from "aa:bb:cc:dd:ee:ff" (or with dashes).
pub fn parse_mac(mac: &str) -> anyhow::Result<[u8; 6]> {
    let parts: Vec<&str> = mac.trim().split([':', '-']).collect();
    let mut out = [0u8; 6];
    if parts.len() != 6 {
        anyhow::bail!("This is not a network card address.");
    }
    for (byte, part) in out.iter_mut().zip(&parts) {
        if part.len() != 2 {
            anyhow::bail!("This is not a network card address.");
        }
        *byte = u8::from_str_radix(part, 16).map_err(|_| anyhow::anyhow!("This is not a network card address."))?;
    }
    Ok(out)
}

pub fn magic_packet(mac: [u8; 6]) -> [u8; 102] {
    let mut packet = [0xFFu8; 102];
    for chunk in packet[6..].chunks_exact_mut(6) {
        chunk.copy_from_slice(&mac);
    }
    packet
}

/// Where the packet goes: everyone on the network the phone is on, and
/// the broadcast address of the computer's home network (taking the
/// usual /24), for phones that route broadcasts oddly.
pub fn targets(home_address: Option<&str>) -> Vec<SocketAddrV4> {
    let mut hosts = vec![Ipv4Addr::BROADCAST];
    if let Some(ip) = home_address.and_then(|a| a.parse::<Ipv4Addr>().ok()) {
        let [a, b, c, _] = ip.octets();
        hosts.push(Ipv4Addr::new(a, b, c, 255));
    }
    hosts.into_iter().flat_map(|host| PORTS.map(|port| SocketAddrV4::new(host, port))).collect()
}

/// Sends the packet to each target, three times a little apart (it is
/// UDP: one may get lost). Returns how many were sent.
pub async fn send(mac: [u8; 6], targets: &[SocketAddrV4]) -> anyhow::Result<usize> {
    let socket = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0)).await?;
    socket.set_broadcast(true)?;
    let packet = magic_packet(mac);
    let mut sent = 0;
    for round in 0..3 {
        if round > 0 {
            tokio::time::sleep(Duration::from_millis(120)).await;
        }
        for target in targets {
            if socket.send_to(&packet, target).await.is_ok() {
                sent += 1;
            }
        }
    }
    if sent == 0 {
        anyhow::bail!("The wake signal could not be sent. Is the phone on a network?");
    }
    Ok(sent)
}

pub async fn wake(mac: &str, home_address: Option<&str>) -> anyhow::Result<usize> {
    send(parse_mac(mac)?, &targets(home_address)).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn addresses_are_read_strictly() {
        assert_eq!(parse_mac("00:e0:4c:AA:0b:ff").unwrap(), [0x00, 0xe0, 0x4c, 0xaa, 0x0b, 0xff]);
        assert_eq!(parse_mac(" 00-11-22-33-44-55 ").unwrap(), [0x00, 0x11, 0x22, 0x33, 0x44, 0x55]);
        for bad in ["", "00:11:22:33:44", "00:11:22:33:44:55:66", "0:11:22:33:44:55", "zz:11:22:33:44:55", "001122334455"] {
            assert!(parse_mac(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn the_packet_is_six_ff_then_the_address_sixteen_times() {
        let mac = [1, 2, 3, 4, 5, 6];
        let packet = magic_packet(mac);
        assert_eq!(packet.len(), 102);
        assert_eq!(&packet[..6], &[0xFF; 6]);
        assert!(packet[6..].chunks(6).all(|c| c == mac));
        assert_eq!(packet[6..].chunks(6).count(), 16);
    }

    #[test]
    fn it_goes_to_everyone_and_to_the_home_network() {
        let all = targets(Some("192.168.0.10"));
        let hosts: Vec<String> = all.iter().map(|t| t.to_string()).collect();
        assert_eq!(hosts, ["255.255.255.255:9", "255.255.255.255:7", "192.168.0.255:9", "192.168.0.255:7"]);
        assert_eq!(targets(None).len(), 2);
        assert_eq!(targets(Some("desk.example")).len(), 2);
    }

    #[tokio::test]
    async fn the_packet_arrives_as_sent() {
        let listener = UdpSocket::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
        let std::net::SocketAddr::V4(at) = listener.local_addr().unwrap() else { unreachable!() };
        let mac = [0xde, 0xad, 0xbe, 0xef, 0x00, 0x01];
        assert_eq!(send(mac, &[at]).await.unwrap(), 3);
        let mut buf = [0u8; 200];
        let (n, _) = listener.recv_from(&mut buf).await.unwrap();
        assert_eq!(&buf[..n], &magic_packet(mac));
    }
}
