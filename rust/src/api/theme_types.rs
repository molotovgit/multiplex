//! A colour theme read from another terminal's theme file.

/// Colours as 0xAARRGGBB.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImportedTheme {
    /// Name found in the file, if it had one.
    pub name: Option<String>,
    pub foreground: u32,
    pub background: u32,
    pub cursor: Option<u32>,
    pub selection: Option<u32>,
    /// Always 16 entries: 8 normal and 8 bright colours.
    pub ansi: Vec<u32>,
    /// "alacritty", "kitty" or "ghostty".
    pub format: String,
}
