//! What an agent asks, read off its screen: the question and the choices
//! it offers ("❯ 1. Yes", "  2. No"), so the phone can show them as
//! buttons, in the app and in a notification.
//!
//! An answer given on the phone may arrive after the question is gone
//! (answered at the computer, or followed by another one). So what was
//! asked gets a mark, the answer carries it back, and the computer sends
//! the answer on only while the screen still asks the same thing
//! ([`may_answer`]). A yes never lands on a question nobody saw.

use serde::{Deserialize, Serialize};

use crate::agents::AgentStatus;

/// One answer on offer.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct Choice {
    /// Its number on the screen, which names it in an answer.
    pub key: String,
    /// Its words, first line only.
    pub label: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default)]
pub struct Asked {
    /// The lines above the choices: what is being decided.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub question: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub choices: Vec<Choice>,
    /// Tells this question from any other. Empty when nothing is asked
    /// by choice.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub mark: String,
    /// Which choice the screen's pointer is on, counted from 0.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub selected: u32,
}

fn is_zero(n: &u32) -> bool {
    *n == 0
}

/// How far up the screen a question is looked for.
const LOOKED_AT: usize = 60;
/// Lines that may follow the choices (hints about keys) for them to count
/// as what is being asked now.
const AFTER: usize = 6;
/// The most lines above the choices taken as the question.
const QUESTION_LINES: usize = 8;
const QUESTION_CHARS: usize = 500;
const LABEL_CHARS: usize = 120;

/// The pointer in front of the choice that Enter would take.
const POINTERS: &[char] = &['❯', '›', '>', '▶', '►', '▸', '→', '➜', '●', '◉'];
/// What some programs put in front of the other choices.
const NOT_POINTED: &[char] = &['○', '◯', '◦'];
/// The sides of a box drawn around a question.
const SIDES: &[char] = &['│', '┃', '║', '|', '▌', '▏', '▕'];

/// A line without the box around it.
fn bare(line: &str) -> &str {
    line.trim().trim_matches(SIDES).trim()
}

/// A line that only draws: the top of a box, a separator.
fn is_rule(bare: &str) -> bool {
    bare.chars().count() >= 3 && bare.chars().all(|c| matches!(c, '─' | '━' | '═' | '╭' | '╮' | '╰' | '╯' | '┌' | '┐' | '└' | '┘' | '├' | '┤' | '┬' | '┴' | '┼' | '-' | '=' | '_' | '╌' | '┄' | ' '))
}

/// "❯ 2. Yes, always" as (pointed at, 2, "Yes, always").
fn choice_line(line: &str) -> Option<(bool, u32, &str)> {
    let mut rest = bare(line);
    let mut pointed = false;
    if let Some(first) = rest.chars().next() {
        if POINTERS.contains(&first) {
            pointed = true;
            rest = rest[first.len_utf8()..].trim_start();
        } else if NOT_POINTED.contains(&first) {
            rest = rest[first.len_utf8()..].trim_start();
        }
    }
    let number = rest.chars().next()?.to_digit(10).filter(|n| *n >= 1)?;
    let label = rest[1..].strip_prefix(['.', ')'])?;
    let words = label.trim();
    (label.starts_with(' ') && !words.is_empty()).then_some((pointed, number, words))
}

fn one_line(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn cut(text: &str, chars: usize) -> String {
    if text.chars().count() <= chars {
        text.to_owned()
    } else {
        let mut cut: String = text.chars().take(chars - 1).collect();
        cut.push('…');
        cut
    }
}

/// FNV-1a: not for secrets, only for telling questions apart.
fn mark_of(parts: &[String]) -> String {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in parts.join("\n").bytes() {
        hash ^= u64::from(byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    format!("{hash:016x}")
}

/// A mark as an answer carries it: this exact shape, or nothing.
pub fn clean_mark(mark: &str) -> Result<String, crate::ProtoError> {
    if mark.is_empty() || (mark.len() == 16 && mark.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())) {
        Ok(mark.to_owned())
    } else {
        Err(crate::ProtoError::Invalid("this is not the mark of a question"))
    }
}

/// A choice as found on the screen.
struct Found {
    number: u32,
    /// Its first line.
    label: String,
    /// All its words, the lines under it too: what the mark is made of.
    all: String,
}

/// A run of choices on the screen.
struct Block {
    /// Its first line, and the line after its last.
    start: usize,
    end: usize,
    /// Which choice the pointer is on.
    selected: u32,
    choices: Vec<Found>,
}

/// A numbered list from 1 with the pointer on one of its lines: the last
/// such on the screen.
fn numbered(lines: &[&str]) -> Option<Block> {
    let mut found: Option<Block> = None;
    let mut at = 0;
    while at < lines.len() {
        let Some((pointed, 1, label)) = choice_line(lines[at]) else {
            at += 1;
            continue;
        };
        let start = at;
        let mut selected = pointed.then_some(0u32);
        let mut choices = vec![Found { number: 1, label: label.to_owned(), all: label.to_owned() }];
        let mut more = 0;
        at += 1;
        while at < lines.len() {
            if let Some((pointed, number, label)) = choice_line(lines[at]) {
                if number as usize != choices.len() + 1 {
                    break;
                }
                if pointed && selected.is_none() {
                    selected = Some(choices.len() as u32);
                }
                choices.push(Found { number, label: label.to_owned(), all: label.to_owned() });
                more = 0;
            } else {
                // A choice's words running on, or a line about it.
                let text = bare(lines[at]);
                if text.is_empty() || is_rule(text) || more == 2 {
                    break;
                }
                let all = &mut choices.last_mut().expect("there is a first choice").all;
                all.push(' ');
                all.push_str(text);
                more += 1;
            }
            at += 1;
        }
        if let (true, Some(selected)) = (choices.len() >= 2, selected) {
            found = Some(Block { start, end: at, selected, choices });
        }
    }
    found
}

/// Where a line's words begin, counted in characters, with the box's
/// side and a pointer taken for blanks. None for a line without words.
fn words_at(line: &str) -> Option<(usize, bool, &str)> {
    let mut pointed = false;
    for (column, (at, c)) in line.char_indices().enumerate() {
        if c.is_whitespace() || SIDES.contains(&c) {
            continue;
        }
        if POINTERS.contains(&c) && !pointed && line[at + c.len_utf8()..].starts_with(' ') {
            pointed = true;
            continue;
        }
        let words = line[at..].trim_end().trim_end_matches(SIDES).trim_end();
        return (!words.is_empty() && !is_rule(words)).then_some((column, pointed, words));
    }
    None
}

/// A list without numbers: the line the pointer is on, and the lines
/// right above and below it whose words begin in the same column
/// ("❯ No, exit" over "  Yes, I trust this folder"). The last such on
/// the screen. Boxes to tick are not a choice of one.
fn pointed(lines: &[&str]) -> Option<Block> {
    let (at, column) = lines.iter().enumerate().rev().find_map(|(at, line)| words_at(line).filter(|(_, pointed, _)| *pointed).map(|(column, _, _)| (at, column)))?;
    let beside = |at: usize| words_at(lines[at]).filter(|(col, pointed, _)| *col == column && !*pointed).map(|(_, _, words)| words);
    let mut start = at;
    while start > 0 && beside(start - 1).is_some() {
        start -= 1;
    }
    let mut end = at + 1;
    while end < lines.len() && beside(end).is_some() {
        end += 1;
    }
    let labels: Vec<&str> = (start..end).map(|line| words_at(lines[line]).map_or("", |(_, _, words)| words)).collect();
    let ticks = |label: &&str| label.starts_with(['[', '☐', '☑', '☒', '◻', '◼', '✓', '✔']);
    if !(2..=9).contains(&labels.len()) || labels.iter().any(ticks) {
        return None;
    }
    let choices = labels.iter().enumerate().map(|(n, label)| Found { number: n as u32 + 1, label: (*label).to_owned(), all: (*label).to_owned() }).collect();
    Some(Block { start, end, selected: (at - start) as u32, choices })
}

/// What the end of a screen asks by choice. Nothing (the default) unless
/// there is a list of two or more with the pointer on one of them, and at
/// most a few lines after it: a list an agent merely wrote in an answer
/// has no pointer and is not at the bottom. The list is numbered from 1,
/// or has no numbers at all; a choice is then named by its place.
pub fn asked(screen: &str) -> Asked {
    let lines: Vec<&str> = screen.lines().collect();
    let lines = &lines[lines.len().saturating_sub(LOOKED_AT)..];
    let Some(Block { start, end, selected, choices }) = numbered(lines).or_else(|| pointed(lines)) else { return Asked::default() };
    if lines[end..].iter().filter(|line| !bare(line).is_empty() && !is_rule(bare(line))).count() > AFTER {
        return Asked::default();
    }

    // The question: what stands above, up to the box's edge, an earlier
    // question, a wide gap, or a few lines.
    let mut above: Vec<&str> = Vec::new();
    let (mut gaps, mut gap) = (0, 0);
    for line in lines[..start].iter().rev() {
        let text = bare(line);
        // The box's edge, or the choices of an earlier question.
        if is_rule(text) || choice_line(line).is_some() {
            break;
        }
        if text.is_empty() {
            gap += 1;
            if gap == 3 {
                break;
            }
            continue;
        }
        if gap > 0 && !above.is_empty() {
            gaps += 1;
            if gaps == 3 {
                break;
            }
            above.push("");
        }
        gap = 0;
        above.push(text);
        if above.iter().filter(|line| !line.is_empty()).count() == QUESTION_LINES {
            break;
        }
    }
    above.reverse();
    let question = above.join("\n");
    // Too long: its end is the nearest to the choices.
    let question = if question.chars().count() > QUESTION_CHARS {
        let from = question.char_indices().rev().nth(QUESTION_CHARS - 2).map_or(0, |(from, _)| from);
        format!("…{}", &question[from..])
    } else {
        question
    };

    let mut parts = vec![one_line(&question)];
    parts.extend(choices.iter().map(|choice| format!("{} {}", choice.number, one_line(&choice.all))));
    Asked {
        question,
        choices: choices.iter().map(|choice| Choice { key: choice.number.to_string(), label: cut(&one_line(&choice.label), LABEL_CHARS) }).collect(),
        mark: mark_of(&parts),
        selected,
    }
}

/// An answer from the phone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Reply {
    /// One of the choices, by its number.
    Choice(String),
    /// Words of the owner's own, sent as one piece with Enter.
    Text(String),
}

/// Whether an answer to what was asked earlier (`mark`; empty when it
/// was not a choice) may still be sent, given the agent's state now and
/// what its screen asks now. The words of a refusal are for the owner.
pub fn may_answer(status: Option<AgentStatus>, now: &Asked, mark: &str, with: &Reply) -> Result<(), &'static str> {
    match status {
        None => return Err("No agent is in that pane any more. Nothing was sent."),
        Some(AgentStatus::Working) => return Err("It is working again. Nothing was sent."),
        Some(_) => {}
    }
    if now.mark != mark {
        return Err("That is no longer what it asks. Nothing was sent.");
    }
    match with {
        Reply::Choice(key) if !now.choices.iter().any(|choice| &choice.key == key) => Err("That is not one of its choices. Nothing was sent."),
        Reply::Text(_) if !now.choices.is_empty() => Err("It asks for one of its choices. Nothing was sent."),
        _ => Ok(()),
    }
}

/// The keys that take a choice in any list: from where the pointer is to
/// the choice, then Enter. (A number key does it in some programs and
/// types a digit in others.)
pub fn keys_for(now: &Asked, key: &str) -> Option<Vec<String>> {
    let target = now.choices.iter().position(|choice| choice.key == key)? as i64;
    let steps = target - i64::from(now.selected);
    let mut keys = vec![if steps < 0 { "up" } else { "down" }.to_owned(); steps.unsigned_abs() as usize];
    keys.push("enter".to_owned());
    Some(keys)
}

#[cfg(test)]
mod tests {
    use super::*;

    const BOXED: &str = "\
● I'll run the tests now.

╭──────────────────────────────────────────────────────╮
│ Bash command                                         │
│                                                      │
│   make test                                          │
│   Run the test suite                                 │
│                                                      │
│ Do you want to proceed?                              │
│ ❯ 1. Yes                                             │
│   2. Yes, and don't ask again for make commands in   │
│      /home/sam/code/api                              │
│   3. No, and tell Claude what to do differently      │
│      (esc)                                           │
╰──────────────────────────────────────────────────────╯
";

    #[test]
    fn a_boxed_question_is_read_with_its_choices() {
        let asked = asked(BOXED);
        assert_eq!(asked.question, "Bash command\n\nmake test\nRun the test suite\n\nDo you want to proceed?");
        assert_eq!(
            asked.choices.iter().map(|c| (c.key.as_str(), c.label.as_str())).collect::<Vec<_>>(),
            [("1", "Yes"), ("2", "Yes, and don't ask again for make commands in"), ("3", "No, and tell Claude what to do differently")]
        );
        assert_eq!(asked.selected, 0);
        assert_eq!(asked.mark.len(), 16);
        assert_eq!(clean_mark(&asked.mark).as_deref(), Ok(asked.mark.as_str()));
    }

    #[test]
    fn a_question_without_a_box_and_with_hints_under_it_is_read_too() {
        let screen = "\
earlier output
────────────────────────────────────
 Allow this command?

   cargo publish

 › 1. Yes, proceed (y)
   2. Yes, and don't ask again for this command (a)
   3. No, and tell Codex what to do differently (esc)

 Press enter to confirm or esc to cancel
";
        let asked = asked(screen);
        assert_eq!(asked.question, "Allow this command?\n\ncargo publish");
        assert_eq!(asked.choices.len(), 3);
        assert_eq!(asked.choices[0].label, "Yes, proceed (y)");
        // The pointer further down, and the other choices marked as such.
        let moved = super::asked("Pick one\n ○ 1. Red\n ● 2. Green\n ○ 3. Blue\n");
        assert_eq!((moved.selected, moved.choices.len(), moved.question.as_str()), (1, 3, "Pick one"));
    }

    /// As Claude Code asked it on 2026-11-18 (the folder is made up).
    const TRUST: &str = "\
…/code/new-thing ❯ claude
──────────────────────────────────────────────────────────────────────────────────
 Accessing workspace:

 /home/sam/code/new-thing

 Quick safety check: Is this a project you created or one you trust? (Like your
 own code, a well-known open source project, or work from your team). If not, take
 a moment to review what's in this folder first.

 Claude Code'll be able to read, edit, and execute files here.

 Security guide

 ❯ No, exit
   Yes, I trust this folder

 Enter to confirm · Esc to cancel
";

    #[test]
    fn a_list_without_numbers_is_read_by_its_pointer() {
        let asked = asked(TRUST);
        assert_eq!(asked.choices.iter().map(|c| (c.key.as_str(), c.label.as_str())).collect::<Vec<_>>(), [("1", "No, exit"), ("2", "Yes, I trust this folder")]);
        assert_eq!(asked.selected, 0);
        assert!(asked.question.ends_with("Claude Code'll be able to read, edit, and execute files here.\n\nSecurity guide"), "{}", asked.question);
        assert!(!asked.question.contains("❯ claude"), "the shell's line above the rule is not part of it");
        assert_eq!(keys_for(&asked, "2").unwrap(), ["down", "enter"]);
        // The pointer on the second, in a box, with a third.
        let boxed = asked_in_box();
        assert_eq!((boxed.selected, boxed.choices.iter().map(|c| c.label.as_str()).collect::<Vec<_>>()), (1, vec!["Apply", "Skip", "Stop"]));
        assert_eq!(boxed.question, "Apply this change?");
        assert_eq!(keys_for(&boxed, "1").unwrap(), ["up", "enter"]);
        // Not a choice of one: boxes to tick, a pointer alone (a prompt
        // someone types at), lines that do not stand under each other.
        assert_eq!(super::asked("Which ones?\n❯ [ ] Tests\n  [x] Docs\n"), Asked::default());
        assert_eq!(super::asked("some output\n❯ make test\n"), Asked::default());
        assert_eq!(super::asked("some output\n❯ make test\nthe next line of output\n"), Asked::default());
        assert_eq!(super::asked("❯ \n"), Asked::default());
    }

    fn asked_in_box() -> Asked {
        asked("╭────────────────────╮\n│ Apply this change? │\n│   Apply            │\n│ › Skip             │\n│   Stop             │\n╰────────────────────╯\n")
    }

    #[test]
    fn a_list_an_agent_merely_wrote_is_not_a_question() {
        // No pointer on any of them.
        assert_eq!(asked("Here is the plan:\n 1. Read the code\n 2. Fix the bug\n 3. Run the tests\n"), Asked::default());
        // Pointed, but far from the end: it was asked long ago. (Two of
        // the lines after it pass for the last choice's own words.)
        let old = format!("❯ 1. Yes\n  2. No\n{}", "a line of later work\n".repeat(AFTER + 3));
        assert_eq!(asked(&format!("❯ 1. Yes\n  2. No\n\n{}", "a hint about keys\n".repeat(AFTER))).choices.len(), 2);
        assert_eq!(asked(&old), Asked::default());
        // One choice is no choice.
        assert_eq!(asked("❯ 1. Yes\n"), Asked::default());
        assert_eq!(asked(""), Asked::default());
        // Numbers that do not run from 1 (the list's beginning scrolled
        // away): still a list under a pointer, its lines taken as they
        // stand and named by their place.
        let odd = asked("❯ 2. Yes\n  3. No\n");
        assert_eq!(odd.choices.iter().map(|c| (c.key.as_str(), c.label.as_str())).collect::<Vec<_>>(), [("1", "2. Yes"), ("2", "3. No")]);
        // A later question wins over an earlier one still on the screen.
        let two = asked("Old?\n❯ 1. A\n  2. B\n\nNew?\n❯ 1. C\n  2. D\n");
        assert_eq!((two.question.as_str(), two.choices[0].label.as_str()), ("New?", "C"));
    }

    #[test]
    fn the_mark_tells_questions_apart_and_survives_a_redraw() {
        let first = asked(BOXED);
        // Drawn again in a wider pane: the same words on other lines.
        let wider = BOXED.replace("in   │\n│      /home/sam/code/api                              │", "in /home/sam/code/api │");
        assert_ne!(wider, BOXED);
        assert_eq!(asked(&wider).mark, first.mark);
        // Another command under the same words is another question.
        let other = BOXED.replace("make test ", "make clean");
        assert_ne!(asked(&other).mark, first.mark);
        assert!(clean_mark("").is_ok() && clean_mark("xyz").is_err() && clean_mark("0123456789ABCDEF").is_err() && clean_mark("0123456789abcdef; rm").is_err());
    }

    #[test]
    fn an_answer_goes_only_to_the_question_it_was_given_to() {
        let now = asked(BOXED);
        let blocked = Some(AgentStatus::Blocked);
        let yes = Reply::Choice("1".to_owned());
        assert_eq!(may_answer(blocked, &now, &now.mark, &yes), Ok(()));
        // Another question is on the screen now, or none.
        let other = asked(&BOXED.replace("make test ", "rm -rf ../ "));
        assert!(may_answer(blocked, &other, &now.mark, &yes).unwrap_err().contains("no longer what it asks"));
        assert!(may_answer(Some(AgentStatus::Idle), &Asked::default(), &now.mark, &yes).unwrap_err().contains("no longer what it asks"));
        // It went back to work, or is gone.
        assert!(may_answer(Some(AgentStatus::Working), &now, &now.mark, &yes).unwrap_err().contains("working again"));
        assert!(may_answer(None, &now, &now.mark, &yes).unwrap_err().contains("No agent"));
        // A choice it does not offer; words where a choice is wanted.
        assert!(may_answer(blocked, &now, &now.mark, &Reply::Choice("4".to_owned())).is_err());
        assert!(may_answer(blocked, &now, &now.mark, &Reply::Text("yes please".to_owned())).is_err());
        // Words for an agent that finished or asks in its own words: fine,
        // unless a choice has come up meanwhile.
        let words = Reply::Text("now run the tests".to_owned());
        assert_eq!(may_answer(Some(AgentStatus::Done), &Asked::default(), "", &words), Ok(()));
        assert_eq!(may_answer(blocked, &Asked::default(), "", &words), Ok(()));
        assert!(may_answer(blocked, &now, "", &words).is_err());
    }

    #[test]
    fn a_choice_is_taken_by_moving_the_pointer_to_it() {
        let now = asked(BOXED);
        assert_eq!(keys_for(&now, "1").unwrap(), ["enter"]);
        assert_eq!(keys_for(&now, "3").unwrap(), ["down", "down", "enter"]);
        let moved = asked("Pick one\n ○ 1. Red\n ○ 2. Green\n ● 3. Blue\n");
        assert_eq!(keys_for(&moved, "1").unwrap(), ["up", "up", "enter"]);
        assert_eq!(keys_for(&moved, "4"), None);
    }
}
