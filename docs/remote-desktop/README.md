# Remote desktop (gliff)

Multiplex can show and control a Hyprland desktop (for example Omarchy) on the phone. It starts `gliff-server --stdio` over the same SSH connection it already uses, so nothing new has to be exposed.

Away from home it connects through **Tailscale, built into Multiplex**: the phone joins your tailnet from inside the app, so no Tailscale VPN app is needed. Tailscale picks the most direct path by itself: peer to peer when the networks allow it (fastest), otherwise a Tailscale relay.

## 1. On the computer (Omarchy)

Install the package and prepare the computer once:

```sh
git clone https://github.com/molotovgit/multiplex.git
cd multiplex/dist/arch
makepkg -si          # installs the `multiplex` command
multiplex setup      # asks for sudo; `multiplex setup --dry-run` shows the steps first
multiplex doctor     # checks that everything is ready
```

`multiplex setup` turns the SSH server on with key-only logins, opens the firewall for SSH from the home network and Tailscale only, and makes sure gliff is installed. For access away from home, also join your tailnet: `sudo tailscale up`.

## 2. Pair the phone

1. On the computer, run `multiplex pair`. It shows a QR code for five minutes.
2. In the app: **Hosts → Pair a computer → Scan the code**. No camera? Paste the line of text shown under the code.
3. The app shows **Paired with <computer>**. Tap **Open the desktop**.

The phone has to reach the computer while pairing: be on the same Wi-Fi, or sign in to Tailscale in the app first (**Settings → Tailscale**) with the account the computer uses. Later the app picks the route by itself: Tailscale when the phone is signed in, the home-network address otherwise.

What the code does, and why it is safe to show on a screen for a few minutes:

- It carries a one-time SSH key that can do one thing, register a phone, once. `authorized_keys` holds it with `restrict`, an `expiry-time` and a forced command; it is removed the moment a phone pairs, and refused after five minutes either way.
- It carries the computer's SSH host key, so the phone's first connection already knows who it is talking to. There is no "trust this server?" question to wave through.
- The phone registers its own key. Only a well-formed ed25519 key and a plain-character name are accepted; nothing else reaches `authorized_keys`, and lines that are not Multiplex's stay untouched.
- The computer shows a notification naming the phone that paired.

`multiplex devices` lists the paired phones; `multiplex unpair "<name>"` removes one.

Building Tailscale into the app needs Go and the Android NDK. Run `native/tailscale/build-android.sh` before `flutter build apk`; builds without it work, minus Tailscale.

## The panel: the desktop without its picture

A paired computer has a **Panel** (on its card on Home, on its page, and on the bar inside the remote desktop, where it sits under the picture in portrait and beside it in landscape):

- **Workspaces** of the monitor in focus, 1 to 10. Tap one to show it; hold one to send the window in focus there. With several monitors, their names are above: tap one to give it the focus.
- **Window**: arrows move the focus to the neighbouring window (or, after a tap on the button between them, move the window itself), and Close, Full, Float, Split.
- **Open**: pinned shortcuts, at first Omarchy's menu, a terminal, the browser and the file manager. **All shortcuts** lists every key binding of the computer that has a description: search it, tap one to run it, pin the ones you want on the panel.
- **Sound**: what is playing, previous / play or pause / next, and the volume.

The panel does what the computer's own keys do. The phone runs `multiplex desk …` on the computer over the SSH connection it already has (nothing new listens on the network); that command asks Hyprland through `hyprctl`, takes the list of bindings from Omarchy's own key-binding menu, reads players over the session bus and the volume from `wpctl`. The state follows the computer by itself: switch a workspace at the desk and the phone shows it.

## The touchpad: pointer and keys, no picture

When the computer's screen is in sight (a TV across the room, the desk you are standing next to), the **Touchpad** tile turns the phone into its touchpad and keyboard. No picture is sent or decoded, so it costs a few bytes per movement and is as quick as the network.

- One finger moves the pointer (slow is exact, quick crosses the screen); a tap clicks.
- Hold still, then move, to drag. Or hold **Left click** under your thumb and move with the other hand.
- Two fingers scroll; a two-finger tap is the right button, a three-finger tap the middle one.
- The key bar has Super, Ctrl, Alt and Shift (tap: for the next key or click; double tap: locked), and the keyboard button opens Multiplex's keyboard. Text the US keyboard cannot type goes through the computer's clipboard (needs `wl-clipboard` there).

On the computer this is `multiplex input`: an ordinary Wayland program that makes a virtual pointer and a virtual keyboard (with a US keymap from `xkbcli`) and reads one short line per event from the SSH connection. A key or button cannot stay down: everything is released when the phone leaves, and when it goes quiet for a few seconds while something is held.

## Sharing: files, the clipboard, links

**From the phone.** Share anything to Multiplex from another app. A paired computer is offered first:

- files: **Send to <computer>** puts them in its Downloads folder, and the computer says on its screen what arrived;
- text: **Copy to <computer>** puts it on its clipboard; a web link can also **Open on <computer>**, in its browser.

If the computer cannot be reached just then, **Send when it is next connected** keeps the files on the phone; they go by themselves the next time the phone connects to it.

Plain SSH servers are one tap further, as before (pick the server and a folder).

**From the computer.**

```sh
multiplex send report.pdf "Holiday photos/"     # a folder goes as one .tar.gz
multiplex send --to "Sam's phone" notes.txt     # with several phones paired
multiplex send                                  # what is still waiting
```

The file waits in an outbox until the phone is connected to the computer (Multiplex open, or kept in the background by an open session); then the phone fetches it into its Multiplex downloads and shows a notification, and the computer says it was delivered. What is sent while the phone is away simply waits: the outbox is the queue.

**The clipboard.** While the phone is connected to a paired computer, text copied at the computer lands on the phone's clipboard, and text copied on the phone goes to the computer when Multiplex comes back to the front (Android only lets the app in front read the clipboard). What a password manager marks as secret is not passed on. The panel has **Phone to computer** and **Computer to phone** for doing it by hand.

Nothing new listens on the network for any of this: the phone runs `multiplex share …` and `multiplex link` on the computer over its SSH connection, and files travel by SFTP. The computer needs `wl-clipboard` for the clipboard and `libnotify` for its notices.

## The phone, from the computer

While the phone is connected to a paired computer:

- `multiplex ring` makes the phone ring out loud, also when it is on silent, for up to 30 seconds or until its notification is tapped. For finding it.
- `multiplex devices` shows each paired phone, whether it is connected, and its battery.
- When the phone rings or is in a call (also an internet call; Android 12 or later), what is playing on the computer pauses, and carries on afterwards unless you touched it meanwhile. On by default; the switch is in **Sharing and notifications**.
- **Do Not Disturb together** (off by default) silences the computer's notifications while the phone is on Do Not Disturb. The panel also has a **Do Not Disturb** chip for the computer alone.
- The phone's notifications can show on the computer's screen. This is off until you switch it on for that computer (its page, **⋮ → Sharing and notifications**) and give Multiplex notification access in Android's settings, which the app opens for you. Apps appear in that screen as they post; switch one off to keep it on the phone only. Nothing is stored on either side: a notification is passed on only while the computer is connected.

## Waking the computer

A paired computer's page has a **Wake** tile: it broadcasts a Wake-on-LAN signal for the computer's network card, whose address the pairing code carried. Three things have to hold:

- the phone is on the computer's home network (the signal is a broadcast; it does not travel over Tailscale or mobile data);
- the network card listens for it: `multiplex setup` turns that on for a wired card managed by NetworkManager, and `multiplex doctor` shows whether it is on;
- the firmware (BIOS) allows waking from the network.

## Optional: up to 120 frames a second

gliff caps its stream at 60 frames a second (`MAX_FPS` in `crates/gliff-server/src/session.rs`). On a monitor faster than 60 Hz, a build with 120 cuts the wait for the next frame from about 8 ms to about 4 ms on average, for roughly 40% more data. Gliff's own rate control still lowers it on slow links.

```sh
git clone https://github.com/omacom/gliff && cd gliff
sed -i 's/^const MAX_FPS: u32 = 60;/const MAX_FPS: u32 = 120;/' crates/gliff-server/src/session.rs
cargo build --release -p gliff-server
install -m 755 target/release/gliff-server ~/.local/bin/gliff-server-fast
```

Multiplex uses `~/.local/bin/gliff-server-fast` when it exists and falls back to `gliff-server` otherwise. Delete the file to go back.

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
