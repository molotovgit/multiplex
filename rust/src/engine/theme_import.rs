//! Reads terminal colour themes written for other terminals, so users can
//! bring any theme they like: Alacritty (`.toml`), Kitty (`.conf`) and
//! Ghostty (config lines). Themes from desktop setups such as Omarchy ship
//! in exactly these formats.

use thiserror::Error;

use crate::api::theme_types::ImportedTheme;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ThemeImportError {
    #[error("this does not look like an Alacritty, Kitty or Ghostty theme")]
    UnknownFormat,
    #[error("the theme has no {0} colour")]
    Missing(&'static str),
    #[error("the TOML could not be read: {0}")]
    Toml(String),
}

/// Colours collected while reading a file. Index 0-15 are the ANSI colours.
#[derive(Default)]
struct Collected {
    name: Option<String>,
    foreground: Option<u32>,
    background: Option<u32>,
    cursor: Option<u32>,
    selection: Option<u32>,
    ansi: [Option<u32>; 16],
}

impl Collected {
    fn finish(self, format: &str) -> Result<ImportedTheme, ThemeImportError> {
        let foreground = self.foreground.ok_or(ThemeImportError::Missing("foreground"))?;
        let background = self.background.ok_or(ThemeImportError::Missing("background"))?;
        if self.ansi[..8].iter().any(Option::is_none) {
            return Err(ThemeImportError::Missing("normal (0-7)"));
        }
        // Many themes leave out the bright set; reuse the normal colours.
        let ansi = (0..16)
            .map(|i| self.ansi[i].or(self.ansi[i % 8]).unwrap_or(foreground))
            .collect();
        Ok(ImportedTheme {
            name: self.name,
            foreground,
            background,
            cursor: self.cursor,
            selection: self.selection,
            ansi,
            format: format.to_owned(),
        })
    }
}

/// Detects the format and reads the colours.
pub struct ThemeImporter;

impl ThemeImporter {
    const COLOR_NAMES: [&'static str; 8] = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"];

    pub fn parse(text: &str) -> Result<ImportedTheme, ThemeImportError> {
        if text.contains("[colors") {
            return Self::alacritty(text);
        }
        let lines = Self::lines(text);
        if lines.iter().any(|(k, _)| k.starts_with("color") && k[5..].parse::<u8>().is_ok()) {
            return Self::kitty(&lines);
        }
        if lines.iter().any(|(k, _)| *k == "palette") || text.contains('=') {
            return Self::ghostty(&lines);
        }
        Err(ThemeImportError::UnknownFormat)
    }

    /// Reads `#rrggbb`, `0xrrggbb` or `rrggbb` into 0xFFRRGGBB.
    pub fn color(value: &str) -> Option<u32> {
        let v = value.trim().trim_matches(|c| c == '\'' || c == '"');
        let hex = v.strip_prefix('#').or_else(|| v.strip_prefix("0x")).or_else(|| v.strip_prefix("0X")).unwrap_or(v);
        if hex.len() != 6 || !hex.chars().all(|c| c.is_ascii_hexdigit()) {
            return None;
        }
        u32::from_str_radix(hex, 16).ok().map(|rgb| 0xFF00_0000 | rgb)
    }

    fn alacritty(text: &str) -> Result<ImportedTheme, ThemeImportError> {
        let table: toml::Table = toml::from_str(text).map_err(|e| ThemeImportError::Toml(e.to_string()))?;
        let colors = table.get("colors").and_then(|v| v.as_table()).ok_or(ThemeImportError::UnknownFormat)?;
        let get = |section: &str, key: &str| {
            colors
                .get(section)
                .and_then(|s| s.get(key))
                .and_then(|v| v.as_str())
                .and_then(Self::color)
        };
        let mut c = Collected {
            foreground: get("primary", "foreground"),
            background: get("primary", "background"),
            cursor: get("cursor", "cursor"),
            selection: get("selection", "background"),
            ..Default::default()
        };
        for (i, name) in Self::COLOR_NAMES.iter().enumerate() {
            c.ansi[i] = get("normal", name);
            c.ansi[i + 8] = get("bright", name);
        }
        c.name = Self::name_from_comment(text);
        c.finish("alacritty")
    }

    fn kitty(lines: &[(&str, &str)]) -> Result<ImportedTheme, ThemeImportError> {
        let mut c = Collected::default();
        for (key, value) in lines {
            let color = Self::color(value);
            match *key {
                "foreground" => c.foreground = color,
                "background" => c.background = color,
                "cursor" => c.cursor = color,
                "selection_background" => c.selection = color,
                k if k.starts_with("color") => {
                    if let Ok(i) = k[5..].parse::<usize>() {
                        if i < 16 {
                            c.ansi[i] = color;
                        }
                    }
                }
                _ => {}
            }
        }
        c.finish("kitty")
    }

    fn ghostty(lines: &[(&str, &str)]) -> Result<ImportedTheme, ThemeImportError> {
        let mut c = Collected::default();
        for (key, value) in lines {
            match *key {
                "foreground" => c.foreground = Self::color(value),
                "background" => c.background = Self::color(value),
                "cursor-color" => c.cursor = Self::color(value),
                "selection-background" => c.selection = Self::color(value),
                // palette = 4=#7aa2f7
                "palette" => {
                    if let Some((index, color)) = value.split_once('=') {
                        if let Ok(i) = index.trim().parse::<usize>() {
                            if i < 16 {
                                c.ansi[i] = Self::color(color);
                            }
                        }
                    }
                }
                _ => {}
            }
        }
        if c.foreground.is_none() && c.background.is_none() && c.ansi.iter().all(Option::is_none) {
            return Err(ThemeImportError::UnknownFormat);
        }
        c.finish("ghostty")
    }

    /// Splits `key value` or `key = value` lines, skipping comments.
    fn lines(text: &str) -> Vec<(&str, &str)> {
        text.lines()
            .map(str::trim)
            .filter(|l| !l.is_empty() && !l.starts_with('#'))
            .filter_map(|l| {
                if let Some((k, v)) = l.split_once('=') {
                    // Ghostty: "palette = 0=#000000" splits at the first '='.
                    return Some((k.trim(), v.trim()));
                }
                l.split_once(char::is_whitespace).map(|(k, v)| (k.trim(), v.trim()))
            })
            .collect()
    }

    /// Alacritty theme files often start with "# Colors (Theme Name)".
    fn name_from_comment(text: &str) -> Option<String> {
        let line = text.lines().find(|l| l.trim_start().starts_with("# Colors ("))?;
        let start = line.find('(')? + 1;
        let end = line.rfind(')')?;
        (end > start).then(|| line[start..end].trim().to_owned())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_colour_notations() {
        assert_eq!(ThemeImporter::color("#1a1b26"), Some(0xFF1A1B26));
        assert_eq!(ThemeImporter::color("'0x1A1B26'"), Some(0xFF1A1B26));
        assert_eq!(ThemeImporter::color("c0caf5"), Some(0xFFC0CAF5));
        assert_eq!(ThemeImporter::color("#fff"), None);
    }

    #[test]
    fn reads_an_alacritty_theme() {
        let text = r##"
# Colors (Night Owl Test)
[colors.primary]
background = '#101010'
foreground = '#e0e0e0'
[colors.cursor]
cursor = '#ffcc00'
[colors.normal]
black = '#000000'
red = '#ff0000'
green = '#00ff00'
yellow = '#ffff00'
blue = '#0000ff'
magenta = '#ff00ff'
cyan = '#00ffff'
white = '#ffffff'
"##;
        let theme = ThemeImporter::parse(text).unwrap();
        assert_eq!(theme.format, "alacritty");
        assert_eq!(theme.name.as_deref(), Some("Night Owl Test"));
        assert_eq!((theme.background, theme.foreground, theme.cursor), (0xFF101010, 0xFFE0E0E0, Some(0xFFFFCC00)));
        assert_eq!(theme.ansi.len(), 16);
        assert_eq!(theme.ansi[1], 0xFFFF0000);
        // No bright set: bright red falls back to red.
        assert_eq!(theme.ansi[9], 0xFFFF0000);
    }

    #[test]
    fn reads_a_kitty_theme() {
        let mut text = String::from("# kitty\nforeground #c0caf5\nbackground #1a1b26\nselection_background #33467c\n");
        for i in 0..16 {
            text.push_str(&format!("color{i} #0000{i:02x}\n"));
        }
        let theme = ThemeImporter::parse(&text).unwrap();
        assert_eq!(theme.format, "kitty");
        assert_eq!(theme.ansi[15], 0xFF00000F);
        assert_eq!(theme.selection, Some(0xFF33467C));
    }

    #[test]
    fn reads_a_ghostty_theme() {
        let mut text = String::from("background = 1a1b26\nforeground = c0caf5\ncursor-color = c0caf5\n");
        for i in 0..8 {
            text.push_str(&format!("palette = {i}=#1111{i:02x}\n"));
        }
        let theme = ThemeImporter::parse(&text).unwrap();
        assert_eq!(theme.format, "ghostty");
        assert_eq!(theme.ansi[3], 0xFF111103);
        assert_eq!(theme.ansi[11], 0xFF111103);
    }

    #[test]
    fn explains_what_is_missing() {
        assert_eq!(ThemeImporter::parse("hello"), Err(ThemeImportError::UnknownFormat));
        let no_background = "[colors.primary]\nforeground = '#ffffff'\n";
        assert_eq!(ThemeImporter::parse(no_background), Err(ThemeImportError::Missing("background")));
    }
}
