# Remote desktop (gliff)

Multiplex can show and control a Hyprland desktop (for example Omarchy) on the phone. It starts `gliff-server --stdio` over the same SSH connection it already uses, so nothing new has to be exposed.

Away from home it connects through **Tailscale, built into Multiplex**: the phone joins your tailnet from inside the app, so no Tailscale VPN app is needed. Tailscale picks the most direct path by itself: peer to peer when the networks allow it (fastest), otherwise a Tailscale relay.

## 1. The desktop machine

```sh
sudo pacman -S gliff                 # Omarchy ships it already
sudo systemctl enable --now sshd
```

1. **Lock SSH down.** Copy `desktop-sshd-hardening.conf` to `/etc/ssh/sshd_config.d/10-hardening.conf` and put your user name in `AllowUsers`. It allows your home network and your tailnet (`100.64.0.0/10`).
2. **Check and reload.** Run `sudo sshd -t`, then `sudo systemctl restart sshd`.
3. **Open the firewall** to the home network and Tailscale only:
   - `sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp`
   - `sudo ufw allow in on tailscale0 to any port 22 proto tcp`
4. **Join your tailnet:** `sudo tailscale up --hostname=<name>`, then sign in.
5. **Check the video encoder.** `gliff-probe gpu` shows which encoder gliff will use. NVIDIA cards encode through Vulkan Video.

## 2. In Multiplex

1. **Settings → Tailscale → Sign in to Tailscale**, with the same account as the desktop. You do this once per phone. The screen lists your devices and whether each is reached directly or through a relay.
2. **Keychain:** add or import the phone's key, and put its public half in the desktop's `~/.ssh/authorized_keys`.
3. **Add the desktop:** in the Tailscale screen, open the device's menu → **Add as host**. Or create a host with the device name as the address (for example `omarchy`) and turn on **Advanced → Connect through Tailscale**.
4. **Open the desktop:** host menu → **Remote desktop**. It works the same at home and away.

Building Tailscale into the app needs Go and the Android NDK. Run `native/tailscale/build-android.sh` before `flutter build apk`; builds without it work, minus Tailscale.

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
