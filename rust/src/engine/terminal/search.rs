//! Finds text on the screen and in the scrollback.
//!
//! Lines are numbered from the oldest line of history (0) down to the last
//! row of the live screen, so a match keeps its place while the view
//! scrolls. The screen above the view is read page by page through vt100's
//! own scroll position, which is put back afterwards.

use crate::api::terminal_types::SearchMatch;

use super::emulator::TerminalEmulator;

/// Searches one terminal's text.
pub struct TextSearch {
    /// The text to find, lower-cased unless the search is case-sensitive.
    needle: Vec<char>,
    case_sensitive: bool,
    limit: usize,
}

/// One row of text with the column each character starts at.
struct RowText {
    chars: Vec<char>,
    cols: Vec<u16>,
    /// The column just after the last character.
    end: u16,
}

impl TextSearch {
    /// More matches than this are not reported: a search for "e" in a full
    /// scrollback would otherwise build a huge list nobody can step through.
    pub const MAX_MATCHES: usize = 5000;

    pub fn new(query: &str, case_sensitive: bool) -> Self {
        let needle = query.chars().map(|c| Self::fold(c, case_sensitive)).collect();
        Self { needle, case_sensitive, limit: Self::MAX_MATCHES }
    }

    /// Every match, oldest first. Empty for an empty query.
    pub fn find_all(&self, term: &mut TerminalEmulator) -> Vec<SearchMatch> {
        let mut found = Vec::new();
        if self.needle.is_empty() {
            return found;
        }
        let (rows, cols) = term.size();
        let history = term.history_len();
        let saved = term.screen().scrollback();
        let total = history + usize::from(rows);
        let mut line = 0;
        while line < total && found.len() < self.limit {
            // Show the page that has `line` at the top (or the live screen
            // for the last page) and read its rows.
            let top = line.min(history);
            term.screen_mut().set_scrollback(history - top);
            let screen = term.screen();
            for row in (line - top)..usize::from(rows) {
                let text = Self::row_text(screen, row as u16, cols);
                self.find_in_row(&text, (top + row) as u32, &mut found);
                if found.len() >= self.limit {
                    break;
                }
            }
            line = top + usize::from(rows);
        }
        term.screen_mut().set_scrollback(saved);
        found.truncate(self.limit);
        found
    }

    fn find_in_row(&self, row: &RowText, line: u32, found: &mut Vec<SearchMatch>) {
        let n = self.needle.len();
        if row.chars.len() < n {
            return;
        }
        let mut i = 0;
        while i + n <= row.chars.len() {
            let hit = (0..n).all(|k| Self::fold(row.chars[i + k], self.case_sensitive) == self.needle[k]);
            if hit {
                let col = row.cols[i];
                let end = row.cols.get(i + n).copied().unwrap_or(row.end);
                found.push(SearchMatch { line, col, width: end - col });
                // Matches never overlap, like in an editor.
                i += n;
            } else {
                i += 1;
            }
        }
    }

    /// The text of a visible row. Empty cells count as spaces so columns
    /// stay right; the second half of a wide character is skipped.
    fn row_text(screen: &vt100::Screen, row: u16, cols: u16) -> RowText {
        let mut chars = Vec::with_capacity(usize::from(cols));
        let mut starts = Vec::with_capacity(usize::from(cols));
        let mut end = 0;
        for col in 0..cols {
            let Some(cell) = screen.cell(row, col) else { break };
            if cell.is_wide_continuation() {
                continue;
            }
            let width = if cell.is_wide() { 2 } else { 1 };
            if cell.has_contents() {
                // A cell may hold a letter plus combining marks: only the
                // first character is matched, the rest ride along.
                let mut it = cell.contents().chars();
                if let Some(first) = it.next() {
                    chars.push(first);
                    starts.push(col);
                }
            } else {
                chars.push(' ');
                starts.push(col);
            }
            end = col + width;
        }
        RowText { chars, cols: starts, end }
    }

    fn fold(c: char, case_sensitive: bool) -> char {
        if case_sensitive {
            c
        } else {
            c.to_lowercase().next().unwrap_or(c)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn term_with(lines: usize, rows: u16) -> TerminalEmulator {
        let mut term = TerminalEmulator::new(rows, 30, 100);
        for i in 0..lines {
            term.process(format!("line {i} {}\r\n", if i % 3 == 0 { "Error here" } else { "ok" }).as_bytes());
        }
        term
    }

    #[test]
    fn finds_matches_in_history_and_on_screen() {
        let mut term = term_with(10, 4);
        let found = TextSearch::new("error", false).find_all(&mut term);
        // Lines 0, 3, 6 and 9 say "Error"; line 9 is on the live screen.
        assert_eq!(found.iter().map(|m| m.line).collect::<Vec<_>>(), vec![0, 3, 6, 9]);
        assert_eq!((found[0].col, found[0].width), (7, 5));
    }

    #[test]
    fn case_sensitive_search_skips_other_cases() {
        let mut term = term_with(10, 4);
        assert!(TextSearch::new("error", true).find_all(&mut term).is_empty());
        assert_eq!(TextSearch::new("Error", true).find_all(&mut term).len(), 4);
    }

    #[test]
    fn puts_the_scroll_position_back() {
        let mut term = term_with(20, 4);
        term.scroll_by(5);
        TextSearch::new("line", false).find_all(&mut term);
        assert_eq!(term.screen().scrollback(), 5);
    }

    #[test]
    fn counts_wide_characters_as_two_columns() {
        let mut term = TerminalEmulator::new(3, 20, 10);
        term.process("漢字 abc".as_bytes());
        let found = TextSearch::new("字 a", false).find_all(&mut term);
        assert_eq!(found.len(), 1);
        assert_eq!((found[0].line, found[0].col, found[0].width), (0, 2, 4));
    }

    #[test]
    fn empty_query_finds_nothing_and_matches_do_not_overlap() {
        let mut term = TerminalEmulator::new(3, 20, 10);
        term.process(b"aaaa");
        assert!(TextSearch::new("", false).find_all(&mut term).is_empty());
        assert_eq!(TextSearch::new("aa", false).find_all(&mut term).len(), 2);
    }

    #[test]
    fn stops_at_the_limit() {
        let mut term = TerminalEmulator::new(3, 20, 10);
        term.process(b"xxxxxxxxxx");
        let mut search = TextSearch::new("x", false);
        search.limit = 4;
        assert_eq!(search.find_all(&mut term).len(), 4);
    }
}
