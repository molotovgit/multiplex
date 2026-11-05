//! Theme import for Flutter.

use crate::api::theme_types::ImportedTheme;
use crate::engine::theme_import::ThemeImporter;

/// Reads an Alacritty (.toml), Kitty (.conf) or Ghostty theme file.
#[flutter_rust_bridge::frb(sync)]
pub fn parse_theme_file(text: String) -> anyhow::Result<ImportedTheme> {
    Ok(ThemeImporter::parse(&text)?)
}
