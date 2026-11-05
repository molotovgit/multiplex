//! Builds a [`TerminalFrame`] from the emulator's screen.
//!
//! Flutter draws text in pieces. To keep the number of pieces small, cells
//! next to each other that look the same are joined into one run. Plain
//! ASCII is joined freely. Any other character gets its own run placed at
//! its exact column, so a font with odd widths can never push later text
//! out of line.

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

use crate::api::terminal_types::{
    CursorShape, RunStyle, TerminalCursor, TerminalFrame, TerminalLine, TextRun,
};

use super::emulator::TerminalEmulator;
use super::palette::ColorResolver;

/// Converts screen state into drawable frames.
pub struct FrameBuilder<'a> {
    colors: &'a ColorResolver,
}

/// The look of a single cell, used to decide which cells can be joined.
#[derive(Clone, Copy, PartialEq, Eq)]
struct CellLook {
    fg: u32,
    bg: u32,
    style: u8,
}

impl<'a> FrameBuilder<'a> {
    pub fn new(colors: &'a ColorResolver) -> Self {
        Self { colors }
    }

    /// Takes a full picture of the visible screen.
    pub fn build(&self, term: &mut TerminalEmulator) -> TerminalFrame {
        let scrollback_len = term.history_len() as u32;
        let screen = term.screen();
        let (rows, cols) = term.size();
        let offset = screen.scrollback() as u32;
        let lines = (0..rows).map(|row| self.line(screen, row, cols)).collect();

        TerminalFrame {
            rows,
            cols,
            lines,
            cursor: self.cursor(screen, rows, offset),
            scroll_offset: offset,
            scrollback_len,
            alternate_screen: screen.alternate_screen(),
            mouse_reporting: screen.mouse_protocol_mode() != vt100::MouseProtocolMode::None,
            title: term.title().to_owned(),
            background: self.colors.palette().background,
            foreground: self.colors.palette().foreground,
        }
    }

    fn line(&self, screen: &vt100::Screen, row: u16, cols: u16) -> TerminalLine {
        let mut runs: Vec<TextRun> = Vec::new();
        let mut joinable = false;

        for col in 0..cols {
            let Some(cell) = screen.cell(row, col) else { continue };
            if cell.is_wide_continuation() {
                continue;
            }
            let look = self.look(cell);
            let text = if cell.has_contents() { cell.contents() } else { " " };
            let is_ascii = text.len() == 1 && text.is_ascii() && !cell.is_wide();

            match runs.last_mut() {
                Some(last)
                    if joinable
                        && is_ascii
                        && last.fg == look.fg
                        && last.bg == look.bg
                        && last.style == look.style
                        && last.col + last.width == col =>
                {
                    last.text.push_str(text);
                    last.width += 1;
                }
                _ => {
                    let wide = cell.is_wide();
                    runs.push(TextRun {
                        col,
                        width: if wide { 2 } else { 1 },
                        text: text.to_owned(),
                        fg: look.fg,
                        bg: look.bg,
                        style: look.style | if wide { RunStyle::WIDE } else { 0 },
                    });
                }
            }
            joinable = is_ascii;
        }

        let runs = Self::drop_invisible(runs);
        TerminalLine {
            key: Self::key_of(&runs),
            runs,
        }
    }

    /// Resolves colours and style flags of one cell. Inverse swaps text and
    /// background colour; dim mixes the text towards the background.
    fn look(&self, cell: &vt100::Cell) -> CellLook {
        let mut fg = self.colors.foreground(cell.fgcolor(), cell.bold());
        let mut bg = self.colors.background(cell.bgcolor());
        if cell.inverse() {
            let old_fg = fg;
            fg = bg.unwrap_or(self.colors.palette().background);
            bg = Some(old_fg);
        }
        if cell.dim() {
            fg = self.colors.dim(fg);
        }
        let mut style = 0;
        if cell.bold() {
            style |= RunStyle::BOLD;
        }
        if cell.italic() {
            style |= RunStyle::ITALIC;
        }
        if cell.underline() {
            style |= RunStyle::UNDERLINE;
        }
        CellLook {
            fg,
            bg: bg.unwrap_or(0),
            style,
        }
    }

    /// Removes runs that would draw nothing (only spaces, no background,
    /// no underline) and trims trailing spaces from the rest.
    fn drop_invisible(runs: Vec<TextRun>) -> Vec<TextRun> {
        runs.into_iter()
            .filter_map(|mut run| {
                if run.bg != 0 || run.style & RunStyle::UNDERLINE != 0 {
                    return Some(run);
                }
                let trimmed = run.text.trim_end_matches(' ');
                if trimmed.is_empty() {
                    return None;
                }
                let removed = (run.text.len() - trimmed.len()) as u16;
                run.text.truncate(trimmed.len());
                run.width -= removed;
                Some(run)
            })
            .collect()
    }

    fn key_of(runs: &[TextRun]) -> u64 {
        let mut hasher = DefaultHasher::new();
        for run in runs {
            (run.col, run.width, &run.text, run.fg, run.bg, run.style).hash(&mut hasher);
        }
        hasher.finish()
    }

    /// The cursor, shifted down when the view is scrolled back, and hidden
    /// once that pushes it off the screen.
    fn cursor(&self, screen: &vt100::Screen, rows: u16, offset: u32) -> TerminalCursor {
        let (row, col) = screen.cursor_position();
        let shown_row = u32::from(row) + offset;
        let shape = match screen.cursor_style() {
            vt100::CursorStyle::BlinkUnderline | vt100::CursorStyle::SteadyUnderline => {
                CursorShape::Underline
            }
            vt100::CursorStyle::BlinkVerticalBar | vt100::CursorStyle::SteadyVerticalBar => CursorShape::Bar,
            _ => CursorShape::Block,
        };
        TerminalCursor {
            row: shown_row.min(u32::from(u16::MAX)) as u16,
            col,
            visible: !screen.hide_cursor() && shown_row < u32::from(rows),
            shape,
            color: self.colors.palette().cursor,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::terminal_types::TerminalPalette;

    fn frame_of(bytes: &[u8]) -> TerminalFrame {
        let colors = ColorResolver::new(TerminalPalette::default());
        let mut term = TerminalEmulator::new(4, 20, 50);
        term.process(bytes);
        FrameBuilder::new(&colors).build(&mut term)
    }

    #[test]
    fn joins_plain_text_into_one_run() {
        let frame = frame_of(b"hello world");
        let runs = &frame.lines[0].runs;
        assert_eq!(runs.len(), 1);
        assert_eq!(runs[0].text, "hello world");
        assert_eq!((runs[0].col, runs[0].width), (0, 11));
        assert!(frame.lines[1].runs.is_empty());
    }

    #[test]
    fn splits_runs_where_the_colour_changes() {
        // "ok" in red, then " done" in the default colour.
        let frame = frame_of(b"\x1b[31mok\x1b[0m done");
        let runs = &frame.lines[0].runs;
        assert_eq!(runs.len(), 2);
        assert_eq!(runs[0].text, "ok");
        assert_eq!(runs[0].fg, TerminalPalette::default().ansi[1]);
        assert_eq!(runs[1].text, " done");
        assert_eq!(runs[1].col, 2);
    }

    #[test]
    fn gives_wide_characters_their_own_two_cell_run() {
        let frame = frame_of("a漢b".as_bytes());
        let runs = &frame.lines[0].runs;
        assert_eq!(runs.len(), 3);
        assert_eq!((runs[1].text.as_str(), runs[1].col, runs[1].width), ("漢", 1, 2));
        assert_ne!(runs[1].style & RunStyle::WIDE, 0);
        assert_eq!(runs[2].col, 3);
    }

    #[test]
    fn inverse_swaps_colours_and_keeps_background() {
        let frame = frame_of(b"\x1b[7m  \x1b[0m");
        let run = &frame.lines[0].runs[0];
        let palette = TerminalPalette::default();
        assert_eq!(run.bg, palette.foreground);
        assert_eq!(run.fg, palette.background);
        assert_eq!(run.width, 2);
    }

    #[test]
    fn line_key_changes_with_content() {
        let a = frame_of(b"same");
        let b = frame_of(b"same");
        let c = frame_of(b"other");
        assert_eq!(a.lines[0].key, b.lines[0].key);
        assert_ne!(a.lines[0].key, c.lines[0].key);
    }

    #[test]
    fn reports_cursor_and_hides_it_when_asked() {
        let frame = frame_of(b"ab");
        assert_eq!((frame.cursor.row, frame.cursor.col, frame.cursor.visible), (0, 2, true));
        let frame = frame_of(b"\x1b[?25l");
        assert!(!frame.cursor.visible);
    }
}
