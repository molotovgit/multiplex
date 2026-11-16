# Remote desktop (gliff)

Multiplex can show and control a Hyprland desktop (for example Omarchy) on the phone. It starts `gliff-server --stdio` over the same SSH connection it already uses, so nothing new has to be exposed.

| Where you are | Route | Typical delay |
|---|---|---|
| Same network | Phone → desktop machine, directly | ~10–20 ms |
| Anywhere else | Phone → your VPS → desktop machine (reverse tunnel) | your round trip to the VPS, twice |

## 1. The desktop machine

```sh
sudo pacman -S gliff                 # Omarchy ships it already
sudo systemctl enable --now sshd
```

1. **Lock SSH down.** Copy `desktop-sshd-hardening.conf` to `/etc/ssh/sshd_config.d/10-hardening.conf`, then edit `AllowUsers`: your user, your home network, and `127.0.0.1` for the tunnel.
2. **Check and reload.** Run `sudo sshd -t`, then `sudo systemctl restart sshd`.
3. **Open the firewall to the home network only:** `sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp`.
4. **Check the video encoder.** `gliff-probe gpu` shows which encoder gliff will use. NVIDIA cards encode through Vulkan Video.

## 2. Reaching it from anywhere: a VPS relay (optional)

The desktop machine keeps an outgoing tunnel open to a VPS. The VPS only relays traffic: the phone's SSH session still runs end to end to the desktop and still needs the desktop's key, so the VPS never sees the screen.

1. **Create two accounts on the VPS**, both without a shell (`useradd -m -s /usr/sbin/nologin <name>`):
   - `gtunnel` may only hold the tunnel. Its `authorized_keys` line is `vps-gtunnel-authorized_keys.example`.
   - `gjump` may only reach the tunnel. Its `authorized_keys` line is `vps-gjump-authorized_keys.example`, with the phone's public key.
2. **Install `vps-sshd-tunnel.conf`** as `/etc/ssh/sshd_config.d/50-gliff-tunnel.conf`, then run `sshd -t && systemctl reload ssh`.
3. **Make a key for the tunnel** on the desktop machine: `ssh-keygen -t ed25519 -N "" -f ~/.ssh/desktop-tunnel`. Its public half goes to `gtunnel` on the VPS.
4. **Install the tunnel service.** Copy `gliff-tunnel.service` to `/etc/systemd/system/` and fill in your user name and VPS address. Run `ssh <vps>` once as that user so the VPS host key is known, then `sudo systemctl enable --now gliff-tunnel`.

The tunnel restarts itself within 5 s after a drop and survives reboots. The VPS frees a dead tunnel within about 45 s, so the restart never gets stuck. The forwarded port listens only on the VPS's loopback, never publicly.

## 3. In Multiplex

1. **Keychain:** add or import the phone's key. Its public half goes into the desktop machine's `~/.ssh/authorized_keys`, and into `gjump` if you use the VPS.
2. **Host "VPS jump":** the VPS address, user `gjump`, the phone's key.
3. **Host "Desk via VPS":** `localhost`, port `2222`, your desktop user, jump host *VPS jump*.
4. **Host "Desk":** the desktop's home address and user. Under **Advanced → When away, connect through**, choose *Desk via VPS*.
5. **Open the desktop:** host menu → **Remote desktop**. At home it connects directly. Elsewhere the home address fails within 4 s and it goes through the VPS on its own.

## Using it

| Gesture | Trackpad mode (default) | Direct touch |
|---|---|---|
| One finger drag | moves the pointer | drags |
| Tap | click | click where you tap |
| Two-finger tap | right-click | right-click |
| Two-finger drag | scroll | scroll |
| Hold, then drag | select or move (button held) | — (hold = right-click) |
| Three-finger tap | middle click | middle click |
| Pinch | zoom the view | zoom the view |

- **Toolbar:** phone keyboard, shortcut keys (Super, Ctrl, Alt and Shift are sticky: tap for the next key, double tap to lock), touch mode, and **More**. More has paste from phone, the launcher, terminal, close window, full screen, screen mode, text size, data saver and the speed overlay.
- **Clipboard:** text copied on the desktop lands on the phone's clipboard.
- **Typing other alphabets:** text the US layout cannot type (accents, Cyrillic, emoji) is pasted instead of typed.
- **Bluetooth or USB keyboard and mouse:** they work as they would at the desk.
