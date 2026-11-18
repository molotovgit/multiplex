//! What the phone and the computer say to each other about the desktop:
//! its state (monitors with their workspaces, the window in focus, what
//! is playing) and the actions the phone may ask for.
//!
//! The phone runs `multiplex desk …` on the computer over its SSH
//! connection. Both sides build and read these messages with this code.

use serde::{Deserialize, Serialize};

use crate::ProtoError;

/// Workspaces a monitor has, numbered 1 to 10 as on the keyboard.
pub const SLOTS: u8 = 10;

/// How the phone starts the computer's side. The package installs the
/// command in `/usr/bin`; a hand-installed one lives in `~/.local/bin`,
/// which an SSH command does not search by itself.
pub const DESK_COMMAND: &str = r#"PATH="$PATH:$HOME/.local/bin" multiplex desk"#;

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct DeskState {
    #[serde(default)]
    pub monitors: Vec<DeskMonitor>,
    /// The window in focus, when there is one.
    #[serde(default)]
    pub window: Option<DeskWindow>,
    /// What is playing or paused, when a player is open.
    #[serde(default)]
    pub media: Option<DeskMedia>,
    #[serde(default)]
    pub volume: Option<DeskVolume>,
    /// Whether notifications are silenced (Do Not Disturb), when the
    /// computer can tell.
    #[serde(default)]
    pub dnd: Option<bool>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct DeskMonitor {
    pub name: String,
    pub focused: bool,
    /// This monitor's ten workspaces, in order.
    pub slots: Vec<DeskSlot>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct DeskSlot {
    /// 1 to 10: the number on the keyboard.
    pub slot: u8,
    /// Hyprland's own id for it.
    pub id: i64,
    pub windows: u32,
    /// The one this monitor shows now.
    pub active: bool,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct DeskWindow {
    pub title: String,
    pub class: String,
    pub floating: bool,
    pub fullscreen: bool,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct DeskMedia {
    /// The player's name, as it gives it ("Spotify", "Firefox").
    pub player: String,
    pub playing: bool,
    pub title: String,
    pub artist: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct DeskVolume {
    pub percent: u8,
    pub muted: bool,
}

/// One key binding from the computer's Hyprland configuration.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct DeskBinding {
    /// As Omarchy shows it: "SUPER + W". With a second chord for the same
    /// thing: "SUPER + W / SUPER + Q".
    pub keys: String,
    pub title: String,
    /// The phone can run it (some bindings only mean something to the
    /// program that has the keyboard, and are listed for reference).
    pub run: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Dir {
    Left,
    Right,
    Up,
    Down,
}

impl Dir {
    /// Hyprland's letter for it.
    pub fn letter(self) -> &'static str {
        match self {
            Dir::Left => "l",
            Dir::Right => "r",
            Dir::Up => "u",
            Dir::Down => "d",
        }
    }

    fn parse(text: &str) -> Result<Self, ProtoError> {
        Ok(match text {
            "l" => Dir::Left,
            "r" => Dir::Right,
            "u" => Dir::Up,
            "d" => Dir::Down,
            _ => return Err(ProtoError::Invalid("a direction is l, r, u or d")),
        })
    }
}

/// Something the phone asks the desktop to do.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DeskAction {
    /// Show workspace `slot` on a monitor (the one in focus when not named).
    Workspace { slot: u8, monitor: Option<String> },
    /// Move the window in focus to workspace `slot` of its monitor.
    MoveWindow { slot: u8 },
    FocusMonitor { name: String },
    /// Focus the window in a direction.
    Focus(Dir),
    /// Swap the window in focus with the one in a direction.
    Swap(Dir),
    Close,
    Fullscreen,
    Float,
    Split,
    PlayPause,
    Next,
    Previous,
    VolumeUp,
    VolumeDown,
    Mute,
    /// Silence notifications (Do Not Disturb), or stop silencing them.
    Dnd { on: bool },
    /// Run the binding with these keys, as the computer lists it.
    Bind { keys: String },
}

fn slot(text: &str) -> Result<u8, ProtoError> {
    match text.parse::<u8>() {
        Ok(n) if (1..=SLOTS).contains(&n) => Ok(n),
        _ => Err(ProtoError::Invalid("a workspace is a number from 1 to 10")),
    }
}

/// A monitor's connector name ("DP-1", "HDMI-A-1", "eDP-1").
pub fn clean_monitor_name(name: &str) -> Result<String, ProtoError> {
    let ok = !name.is_empty() && name.len() <= 32 && name.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | ':'));
    if ok {
        Ok(name.to_owned())
    } else {
        Err(ProtoError::Invalid("this is not a monitor's name"))
    }
}

/// A binding's keys: one line of ordinary characters, spaces single.
pub fn clean_keys(keys: &str) -> Result<String, ProtoError> {
    // Checked before tidying: a line break must not pass as a space.
    if keys.chars().any(char::is_control) {
        return Err(ProtoError::Invalid("these are not a binding's keys"));
    }
    let tidy = keys.split_whitespace().collect::<Vec<_>>().join(" ");
    if tidy.is_empty() || tidy.chars().count() > 80 {
        return Err(ProtoError::Invalid("these are not a binding's keys"));
    }
    Ok(tidy)
}

/// One argument for a POSIX shell.
fn quoted(arg: &str) -> String {
    format!("'{}'", arg.replace('\'', r"'\''"))
}

impl DeskAction {
    /// The words after `multiplex desk do`.
    pub fn to_args(&self) -> Vec<String> {
        let one = |word: &str| vec![word.to_owned()];
        match self {
            DeskAction::Workspace { slot, monitor } => {
                let mut args = vec!["workspace".to_owned(), slot.to_string()];
                args.extend(monitor.clone());
                args
            }
            DeskAction::MoveWindow { slot } => vec!["move".to_owned(), slot.to_string()],
            DeskAction::FocusMonitor { name } => vec!["monitor".to_owned(), name.clone()],
            DeskAction::Focus(dir) => vec!["focus".to_owned(), dir.letter().to_owned()],
            DeskAction::Swap(dir) => vec!["swap".to_owned(), dir.letter().to_owned()],
            DeskAction::Close => one("close"),
            DeskAction::Fullscreen => one("fullscreen"),
            DeskAction::Float => one("float"),
            DeskAction::Split => one("split"),
            DeskAction::PlayPause => one("play"),
            DeskAction::Next => one("next"),
            DeskAction::Previous => one("previous"),
            DeskAction::VolumeUp => one("volume-up"),
            DeskAction::VolumeDown => one("volume-down"),
            DeskAction::Mute => one("mute"),
            DeskAction::Dnd { on } => vec!["dnd".to_owned(), if *on { "on" } else { "off" }.to_owned()],
            DeskAction::Bind { keys } => vec!["bind".to_owned(), keys.clone()],
        }
    }

    /// Reads the words after `multiplex desk do`. Everything is checked:
    /// numbers in range, names and keys made of ordinary characters.
    pub fn parse(args: &[&str]) -> Result<Self, ProtoError> {
        Ok(match args {
            ["workspace", n] => DeskAction::Workspace { slot: slot(n)?, monitor: None },
            ["workspace", n, monitor] => DeskAction::Workspace { slot: slot(n)?, monitor: Some(clean_monitor_name(monitor)?) },
            ["move", n] => DeskAction::MoveWindow { slot: slot(n)? },
            ["monitor", name] => DeskAction::FocusMonitor { name: clean_monitor_name(name)? },
            ["focus", dir] => DeskAction::Focus(Dir::parse(dir)?),
            ["swap", dir] => DeskAction::Swap(Dir::parse(dir)?),
            ["close"] => DeskAction::Close,
            ["fullscreen"] => DeskAction::Fullscreen,
            ["float"] => DeskAction::Float,
            ["split"] => DeskAction::Split,
            ["play"] => DeskAction::PlayPause,
            ["next"] => DeskAction::Next,
            ["previous"] => DeskAction::Previous,
            ["volume-up"] => DeskAction::VolumeUp,
            ["volume-down"] => DeskAction::VolumeDown,
            ["mute"] => DeskAction::Mute,
            ["dnd", "on"] => DeskAction::Dnd { on: true },
            ["dnd", "off"] => DeskAction::Dnd { on: false },
            ["bind", keys] => DeskAction::Bind { keys: clean_keys(keys)? },
            _ => return Err(ProtoError::Invalid("this is not something the desktop can be asked to do")),
        })
    }

    /// The command the phone runs on the computer. The action is checked
    /// first, so nothing unexpected reaches the shell.
    pub fn command_line(&self) -> Result<String, ProtoError> {
        let args = self.to_args();
        let refs: Vec<&str> = args.iter().map(String::as_str).collect();
        let checked = Self::parse(&refs)?.to_args();
        Ok(format!("{DESK_COMMAND} do {}", checked.iter().map(|a| quoted(a)).collect::<Vec<_>>().join(" ")))
    }
}

/// The command that prints the state once, as one line of JSON.
pub fn state_command() -> String {
    format!("{DESK_COMMAND} state")
}

/// The command that prints the state now and again whenever it changes.
pub fn watch_command() -> String {
    format!("{DESK_COMMAND} watch")
}

/// The command that prints every binding, as one line of JSON.
pub fn bindings_command() -> String {
    format!("{DESK_COMMAND} binds")
}

/// Reads a line the state or watch command printed.
pub fn parse_state(line: &str) -> Result<DeskState, ProtoError> {
    serde_json::from_str(line.trim()).map_err(|_| ProtoError::Damaged)
}

/// Reads what the bindings command printed.
pub fn parse_bindings(text: &str) -> Result<Vec<DeskBinding>, ProtoError> {
    serde_json::from_str(text.trim()).map_err(|_| ProtoError::Damaged)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_action_survives_the_trip_as_words() {
        let all = [
            DeskAction::Workspace { slot: 3, monitor: None },
            DeskAction::Workspace { slot: 10, monitor: Some("HDMI-A-1".into()) },
            DeskAction::MoveWindow { slot: 1 },
            DeskAction::FocusMonitor { name: "DP-2".into() },
            DeskAction::Focus(Dir::Left),
            DeskAction::Swap(Dir::Down),
            DeskAction::Close,
            DeskAction::Fullscreen,
            DeskAction::Float,
            DeskAction::Split,
            DeskAction::PlayPause,
            DeskAction::Next,
            DeskAction::Previous,
            DeskAction::VolumeUp,
            DeskAction::VolumeDown,
            DeskAction::Mute,
            DeskAction::Dnd { on: true },
            DeskAction::Dnd { on: false },
            DeskAction::Bind { keys: "SUPER SHIFT + RETURN".into() },
        ];
        for action in all {
            let args = action.to_args();
            let refs: Vec<&str> = args.iter().map(String::as_str).collect();
            assert_eq!(DeskAction::parse(&refs).unwrap(), action);
        }
    }

    #[test]
    fn odd_requests_are_refused() {
        for bad in [
            vec!["workspace", "0"],
            vec!["workspace", "11"],
            vec!["workspace", "3", "DP-1\"}) os.execute(\"x"],
            vec!["workspace", "3", ""],
            vec!["move", "-1"],
            vec!["monitor", "a b"],
            vec!["focus", "x"],
            vec!["bind", ""],
            vec!["dnd", "maybe"],
            vec!["bind", "SUPER + W\nrm"],
            vec!["shutdown"],
            vec![],
        ] {
            assert!(DeskAction::parse(&bad).is_err(), "{bad:?}");
        }
        assert!(DeskAction::Workspace { slot: 99, monitor: None }.command_line().is_err());
    }

    #[test]
    fn the_command_line_is_quoted_for_the_shell() {
        let line = DeskAction::Bind { keys: "SUPER + '".into() }.command_line().unwrap();
        assert!(line.ends_with(r#"multiplex desk do 'bind' 'SUPER + '\'''"#), "{line}");
        let line = DeskAction::Workspace { slot: 4, monitor: Some("DP-1".into()) }.command_line().unwrap();
        assert!(line.ends_with("do 'workspace' '4' 'DP-1'"), "{line}");
    }

    #[test]
    fn state_reads_back_and_tolerates_missing_parts() {
        let state = DeskState {
            monitors: vec![DeskMonitor { name: "DP-1".into(), focused: true, slots: vec![DeskSlot { slot: 1, id: 11, windows: 2, active: true }] }],
            window: Some(DeskWindow { title: "notes".into(), class: "foot".into(), floating: false, fullscreen: true }),
            media: None,
            volume: Some(DeskVolume { percent: 40, muted: false }),
            dnd: Some(true),
        };
        assert_eq!(parse_state(&serde_json::to_string(&state).unwrap()).unwrap(), state);
        assert_eq!(parse_state("{}").unwrap(), DeskState::default());
        assert!(parse_state("not json").is_err());
    }
}
