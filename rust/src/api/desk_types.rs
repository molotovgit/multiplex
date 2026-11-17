//! The computer's desktop as the phone shows it: monitors with their
//! workspaces, the window in focus, what is playing, and what the phone
//! can ask for. The wire format and its checks are in `multiplex-proto`,
//! shared with the computer's side.

use multiplex_proto::desk as proto;

#[derive(Debug, Clone, Default)]
pub struct DeskState {
    pub monitors: Vec<DeskMonitor>,
    /// The window in focus, when there is one.
    pub window: Option<DeskWindow>,
    /// What is playing or paused, when a player is open.
    pub media: Option<DeskMedia>,
    pub volume: Option<DeskVolume>,
    /// Whether notifications are silenced (Do Not Disturb), when the
    /// computer can tell.
    pub dnd: Option<bool>,
}

#[derive(Debug, Clone, Default)]
pub struct DeskMonitor {
    pub name: String,
    pub focused: bool,
    /// This monitor's ten workspaces, in order.
    pub slots: Vec<DeskSlot>,
}

#[derive(Debug, Clone, Default)]
pub struct DeskSlot {
    /// 1 to 10: the number on the keyboard.
    pub slot: u8,
    pub windows: u32,
    /// The one this monitor shows now.
    pub active: bool,
}

#[derive(Debug, Clone, Default)]
pub struct DeskWindow {
    pub title: String,
    pub class: String,
    pub floating: bool,
    pub fullscreen: bool,
}

#[derive(Debug, Clone, Default)]
pub struct DeskMedia {
    pub player: String,
    pub playing: bool,
    pub title: String,
    pub artist: String,
}

#[derive(Debug, Clone, Default)]
pub struct DeskVolume {
    pub percent: u8,
    pub muted: bool,
}

/// One key binding from the computer's Hyprland configuration.
#[derive(Debug, Clone, Default)]
pub struct DeskBinding {
    /// "SUPER + W", or two chords for the same thing: "SUPER + W / SUPER + Q".
    pub keys: String,
    pub title: String,
    /// The phone can run it.
    pub run: bool,
}

#[derive(Debug, Clone, Copy)]
pub enum DeskDirection {
    Left,
    Right,
    Up,
    Down,
}

/// Something the phone asks the desktop to do.
#[derive(Debug, Clone)]
pub enum DeskAction {
    /// Show workspace `slot` (1 to 10) on a monitor; the one in focus when
    /// `monitor` is not given.
    Workspace { slot: u8, monitor: Option<String> },
    /// Move the window in focus to workspace `slot` of its monitor.
    MoveWindow { slot: u8 },
    FocusMonitor { name: String },
    Focus { direction: DeskDirection },
    Swap { direction: DeskDirection },
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
    Dnd { enabled: bool },
    /// Run the binding with these keys, as the computer lists it.
    Bind { keys: String },
}

impl From<DeskDirection> for proto::Dir {
    fn from(direction: DeskDirection) -> Self {
        match direction {
            DeskDirection::Left => proto::Dir::Left,
            DeskDirection::Right => proto::Dir::Right,
            DeskDirection::Up => proto::Dir::Up,
            DeskDirection::Down => proto::Dir::Down,
        }
    }
}

impl From<DeskAction> for proto::DeskAction {
    fn from(action: DeskAction) -> Self {
        match action {
            DeskAction::Workspace { slot, monitor } => proto::DeskAction::Workspace { slot, monitor },
            DeskAction::MoveWindow { slot } => proto::DeskAction::MoveWindow { slot },
            DeskAction::FocusMonitor { name } => proto::DeskAction::FocusMonitor { name },
            DeskAction::Focus { direction } => proto::DeskAction::Focus(direction.into()),
            DeskAction::Swap { direction } => proto::DeskAction::Swap(direction.into()),
            DeskAction::Close => proto::DeskAction::Close,
            DeskAction::Fullscreen => proto::DeskAction::Fullscreen,
            DeskAction::Float => proto::DeskAction::Float,
            DeskAction::Split => proto::DeskAction::Split,
            DeskAction::PlayPause => proto::DeskAction::PlayPause,
            DeskAction::Next => proto::DeskAction::Next,
            DeskAction::Previous => proto::DeskAction::Previous,
            DeskAction::VolumeUp => proto::DeskAction::VolumeUp,
            DeskAction::VolumeDown => proto::DeskAction::VolumeDown,
            DeskAction::Mute => proto::DeskAction::Mute,
            DeskAction::Dnd { enabled } => proto::DeskAction::Dnd { on: enabled },
            DeskAction::Bind { keys } => proto::DeskAction::Bind { keys },
        }
    }
}

impl From<proto::DeskState> for DeskState {
    fn from(state: proto::DeskState) -> Self {
        Self {
            monitors: state
                .monitors
                .into_iter()
                .map(|m| DeskMonitor {
                    name: m.name,
                    focused: m.focused,
                    slots: m.slots.into_iter().map(|s| DeskSlot { slot: s.slot, windows: s.windows, active: s.active }).collect(),
                })
                .collect(),
            window: state.window.map(|w| DeskWindow { title: w.title, class: w.class, floating: w.floating, fullscreen: w.fullscreen }),
            media: state.media.map(|m| DeskMedia { player: m.player, playing: m.playing, title: m.title, artist: m.artist }),
            volume: state.volume.map(|v| DeskVolume { percent: v.percent, muted: v.muted }),
            dnd: state.dnd,
        }
    }
}

impl From<proto::DeskBinding> for DeskBinding {
    fn from(binding: proto::DeskBinding) -> Self {
        Self { keys: binding.keys, title: binding.title, run: binding.run }
    }
}
