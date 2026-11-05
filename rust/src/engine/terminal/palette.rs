//! Turns terminal colour codes into real colours.
//!
//! Programs ask for colours in three ways: "the default", a number from
//! 0 to 255, or an exact red/green/blue value. This file maps all of them
//! to 0xAARRGGBB so Flutter can paint them directly.

use crate::api::terminal_types::TerminalPalette;

/// The palette plus the 256-colour table built from it.
pub struct ColorResolver {
    palette: TerminalPalette,
    table: [u32; 256],
}

impl ColorResolver {
    pub fn new(palette: TerminalPalette) -> Self {
        let table = Self::build_table(&palette);
        Self { palette, table }
    }

    pub fn palette(&self) -> &TerminalPalette {
        &self.palette
    }

    /// Colour for text. `bold` matters only when bold-is-bright is on.
    pub fn foreground(&self, color: vt100::Color, bold: bool) -> u32 {
        match color {
            vt100::Color::Default => self.palette.foreground,
            vt100::Color::Idx(i) if bold && self.palette.bold_is_bright && i < 8 => {
                self.table[usize::from(i) + 8]
            }
            vt100::Color::Idx(i) => self.table[usize::from(i)],
            vt100::Color::Rgb(r, g, b) => Self::rgb(r, g, b),
        }
    }

    /// Colour for the cell background, or `None` for the default background.
    pub fn background(&self, color: vt100::Color) -> Option<u32> {
        match color {
            vt100::Color::Default => None,
            vt100::Color::Idx(i) => Some(self.table[usize::from(i)]),
            vt100::Color::Rgb(r, g, b) => Some(Self::rgb(r, g, b)),
        }
    }

    /// Mixes a colour halfway towards the background, used for "dim" text.
    pub fn dim(&self, color: u32) -> u32 {
        let bg = self.palette.background;
        let mix = |shift: u32| {
            let a = (color >> shift) & 0xFF;
            let b = (bg >> shift) & 0xFF;
            ((a + b) / 2) << shift
        };
        0xFF00_0000 | mix(16) | mix(8) | mix(0)
    }

    fn rgb(r: u8, g: u8, b: u8) -> u32 {
        0xFF00_0000 | (u32::from(r) << 16) | (u32::from(g) << 8) | u32::from(b)
    }

    /// Standard xterm table: 16 theme colours, a 6x6x6 colour cube, then
    /// 24 shades of grey.
    fn build_table(palette: &TerminalPalette) -> [u32; 256] {
        let mut table = [0u32; 256];
        for (i, slot) in table.iter_mut().enumerate().take(16) {
            *slot = palette.ansi.get(i).copied().unwrap_or(palette.foreground);
        }
        const LEVELS: [u8; 6] = [0, 95, 135, 175, 215, 255];
        for i in 0..216 {
            let r = LEVELS[i / 36];
            let g = LEVELS[(i / 6) % 6];
            let b = LEVELS[i % 6];
            table[16 + i] = Self::rgb(r, g, b);
        }
        for i in 0..24 {
            let level = (8 + i * 10) as u8;
            table[232 + i] = Self::rgb(level, level, level);
        }
        table
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_the_three_kinds_of_colour() {
        let resolver = ColorResolver::new(TerminalPalette::default());
        let palette = TerminalPalette::default();
        assert_eq!(resolver.foreground(vt100::Color::Default, false), palette.foreground);
        assert_eq!(resolver.foreground(vt100::Color::Idx(1), false), palette.ansi[1]);
        assert_eq!(resolver.foreground(vt100::Color::Rgb(1, 2, 3), false), 0xFF010203);
        // 196 is pure red in the xterm cube.
        assert_eq!(resolver.foreground(vt100::Color::Idx(196), false), 0xFFFF0000);
        // 232 is the darkest grey.
        assert_eq!(resolver.foreground(vt100::Color::Idx(232), false), 0xFF080808);
        assert_eq!(resolver.background(vt100::Color::Default), None);
    }

    #[test]
    fn bold_uses_bright_colour_only_when_asked() {
        let mut palette = TerminalPalette::default();
        let normal = ColorResolver::new(palette.clone());
        assert_eq!(normal.foreground(vt100::Color::Idx(2), true), palette.ansi[2]);
        palette.bold_is_bright = true;
        let bright = ColorResolver::new(palette.clone());
        assert_eq!(bright.foreground(vt100::Color::Idx(2), true), palette.ansi[10]);
    }
}
