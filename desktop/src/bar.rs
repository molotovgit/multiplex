//! `multiplex bar`: Multiplex in the Omarchy bar.
//!
//! The widget is a plugin of the Omarchy shell, so it is QML, the one
//! thing that shell runs; everything it shows it gets from `multiplex
//! devices --json`. Its files travel inside this command, so that however
//! Multiplex was installed, `multiplex bar on` can put the widget in place
//! and point it at this very command.

use std::path::{Path, PathBuf};

use anyhow::{bail, Context};

/// The plugin's name for the shell, and its directory under the shell's
/// plugins.
pub const ID: &str = "multiplex.phones";

/// The plugin, file by file, as it is in `dist/omarchy/multiplex.phones`.
const FILES: &[(&str, &str)] = &[
    ("manifest.json", include_str!("../../dist/omarchy/multiplex.phones/manifest.json")),
    ("Panel.qml", include_str!("../../dist/omarchy/multiplex.phones/Panel.qml")),
    ("Model.js", include_str!("../../dist/omarchy/multiplex.phones/Model.js")),
    ("i18n/en.json", include_str!("../../dist/omarchy/multiplex.phones/i18n/en.json")),
];

/// The one file that is written rather than copied: where the command is.
const WHERE: &str = "Where.js";

/// `Where.js` for a widget that is to run `command`. The path is written
/// as a JSON string, which is also a JavaScript one, whatever is in it.
pub fn where_js(command: &Path) -> String {
    let path = serde_json::to_string(&command.to_string_lossy()).unwrap_or_else(|_| "\"multiplex\"".to_owned());
    format!("// Written by `multiplex bar on`: the command this widget runs.\nvar multiplex = {path}\n")
}

/// Where the shell looks for the plugin: under the user's configuration.
pub fn plugin_dir() -> anyhow::Result<PathBuf> {
    let config = match std::env::var_os("XDG_CONFIG_HOME").filter(|dir| !dir.is_empty()) {
        Some(dir) => PathBuf::from(dir),
        None => PathBuf::from(std::env::var_os("HOME").context("HOME is not set")?).join(".config"),
    };
    Ok(config.join("omarchy/plugins").join(ID))
}

/// How the widget in `dir` compares with the one this command carries.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Installed {
    No,
    /// Written by this version of the command, for `command`.
    Current,
    /// There, but not what this command would write.
    Older,
}

pub fn installed(dir: &Path, command: &Path) -> Installed {
    if !dir.join("manifest.json").is_file() {
        return Installed::No;
    }
    let same = |name: &str, text: &str| std::fs::read_to_string(dir.join(name)).is_ok_and(|there| there == text);
    if FILES.iter().all(|(name, text)| same(name, text)) && same(WHERE, &where_js(command)) {
        Installed::Current
    } else {
        Installed::Older
    }
}

/// The plugin a directory holds, by its manifest: only a directory that
/// holds this widget is ever written over or removed.
fn plugin_in(dir: &Path) -> Option<String> {
    let manifest: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(dir.join("manifest.json")).ok()?).ok()?;
    Some(manifest.get("id")?.as_str()?.to_owned())
}

fn not_ours(dir: &Path) -> anyhow::Result<()> {
    if dir.exists() && plugin_in(dir).as_deref() != Some(ID) {
        bail!("{} is there already and is not the Multiplex widget; it was left alone", dir.display());
    }
    Ok(())
}

/// Writes the widget into `dir`, and says whether anything there changed.
/// Each file is written beside its place and then moved there, so the
/// shell never reads half a file.
pub fn write(dir: &Path, command: &Path) -> anyhow::Result<bool> {
    not_ours(dir)?;
    let place = |name: &str, text: &str| -> anyhow::Result<bool> {
        let target = dir.join(name);
        let parent = target.parent().context("a file without a directory")?;
        std::fs::create_dir_all(parent).with_context(|| format!("could not make {}", parent.display()))?;
        if std::fs::read_to_string(&target).is_ok_and(|there| there == text) {
            return Ok(false);
        }
        let beside = parent.join(format!(".{}.new", target.file_name().and_then(|n| n.to_str()).unwrap_or("file")));
        std::fs::write(&beside, text).with_context(|| format!("could not write {}", beside.display()))?;
        std::fs::rename(&beside, &target).with_context(|| format!("could not write {}", target.display()))?;
        Ok(true)
    };
    // The manifest last: with it the directory becomes a plugin.
    let mut changed = place(WHERE, &where_js(command))?;
    for (name, text) in FILES.iter().rev() {
        changed |= place(name, text)?;
    }
    Ok(changed)
}

/// Takes the widget's files away again. Anything else in the directory
/// (there should be nothing) stays, and then so does the directory.
pub fn remove(dir: &Path) -> anyhow::Result<bool> {
    if !dir.exists() {
        return Ok(false);
    }
    not_ours(dir)?;
    for name in FILES.iter().map(|(name, _)| *name).chain([WHERE]) {
        match std::fs::remove_file(dir.join(name)) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(e).with_context(|| format!("could not remove {}", dir.join(name).display())),
        }
    }
    // Only empty directories go; `remove_dir` refuses any other.
    let _ = std::fs::remove_dir(dir.join("i18n"));
    let _ = std::fs::remove_dir(dir);
    Ok(true)
}

/// What the shell is asked, as a command and its arguments, and what it
/// answered. Apart, so the steps can be tested without a shell.
pub trait Shell {
    fn there(&self) -> bool;
    fn ask(&mut self, command: &[&str]) -> anyhow::Result<String>;
    /// A short wait before asking again.
    fn pause(&mut self);
}

struct Omarchy;

impl Shell for Omarchy {
    fn there(&self) -> bool {
        crate::system::on_path("omarchy-shell") && crate::system::on_path("omarchy")
    }

    fn ask(&mut self, command: &[&str]) -> anyhow::Result<String> {
        let done = std::process::Command::new(command[0]).args(&command[1..]).output().with_context(|| format!("could not run {}", command[0]))?;
        let said = |bytes: &[u8]| String::from_utf8_lossy(bytes).trim().to_owned();
        if !done.status.success() {
            bail!("`{}` failed: {}", command.join(" "), said(if done.stderr.is_empty() { &done.stdout } else { &done.stderr }));
        }
        Ok(said(&done.stdout))
    }

    fn pause(&mut self) {
        std::thread::sleep(std::time::Duration::from_millis(200));
    }
}

const NO_SHELL: &str = "the bar widget is for the Omarchy shell, which was not found on this computer";

/// Whether the shell has the widget in its bar, from `omarchy plugin list
/// --json`. None: the shell does not know the plugin (yet).
fn enabled_in(list: &str) -> Option<bool> {
    let plugins: Vec<serde_json::Value> = serde_json::from_str(list).ok()?;
    plugins.iter().find(|plugin| plugin.get("id").and_then(|id| id.as_str()) == Some(ID))?.get("enabled")?.as_bool()
}

/// Waits until the shell answers. It reloads its plugins when their files
/// change and is deaf while it does: seen on a real bar, where it took in
/// a new widget and could not say so in time.
fn answering(shell: &mut dyn Shell) -> bool {
    for _ in 0..50 {
        if shell.ask(&["omarchy-shell", "shell", "ping"]).is_ok_and(|answer| answer == "ok") {
            return true;
        }
        shell.pause();
    }
    false
}

fn in_the_bar(shell: &mut dyn Shell) -> bool {
    shell.ask(&["omarchy", "plugin", "list", "--json"]).is_ok_and(|list| enabled_in(&list) == Some(true))
}

const ON: &str = "Multiplex is in the bar. Drag it to where you want it; `multiplex bar off` takes it out again.";
const THERE: &str = "Multiplex is in the bar already, and its widget is this version's.";
/// Seen on Omarchy 4.5: the shell loads a widget's files once and keeps
/// them until it starts again, whatever changes on disk.
const RENEWED: &str = "Multiplex's widget in the bar is renewed. The bar keeps showing the one it loaded until the Omarchy shell starts again: `omarchy restart shell`, or the next login.";

/// `multiplex bar on`: the files, then the shell is told. A widget that is
/// already in the bar stays where the user put it; its files are renewed
/// and the shell reloads them by itself.
pub fn turn_on(dir: &Path, command: &Path, shell: &mut dyn Shell) -> anyhow::Result<&'static str> {
    if !shell.there() {
        bail!(NO_SHELL);
    }
    let changed = write(dir, command)?;
    // The shell notices new files by itself, a moment later; it is told
    // too, for one that did not, and then given the time its reload takes.
    shell.pause();
    answering(shell);
    let _ = shell.ask(&["omarchy-shell", "shell", "rescanPlugins"]);
    shell.pause();
    if !answering(shell) {
        bail!("the widget's files are in place, but the Omarchy shell is not answering; when it runs again, `multiplex bar on` finishes this");
    }
    if in_the_bar(shell) {
        return Ok(if changed { RENEWED } else { THERE });
    }
    if let Err(problem) = shell.ask(&["omarchy", "plugin", "enable", ID]) {
        // The shell may have done it and been too busy to say so.
        shell.pause();
        answering(shell);
        if !in_the_bar(shell) {
            return Err(problem);
        }
    }
    Ok(ON)
}

/// `multiplex bar off`: out of the bar first, then the files.
pub fn turn_off(dir: &Path, shell: &mut dyn Shell) -> anyhow::Result<&'static str> {
    not_ours(dir)?;
    if shell.there() && enabled_in(&shell.ask(&["omarchy", "plugin", "list", "--json"]).unwrap_or_default()) == Some(true) {
        shell.ask(&["omarchy", "plugin", "disable", ID])?;
    }
    let was_there = remove(dir)?;
    if shell.there() {
        // So the shell forgets a plugin whose files are gone. Its answer
        // changes nothing here.
        let _ = shell.ask(&["omarchy-shell", "shell", "rescanPlugins"]);
    }
    Ok(if was_there { "Multiplex is out of the bar." } else { "Multiplex was not in the bar." })
}

/// One line on how things stand, for `multiplex bar` and `multiplex doctor`.
pub fn status(dir: &Path, command: &Path, shell_there: bool) -> (Option<bool>, String) {
    if !shell_there {
        return (None, "for the Omarchy shell, which is not on this computer".to_owned());
    }
    match installed(dir, command) {
        Installed::Current => (Some(true), "installed; `multiplex bar off` takes it out".to_owned()),
        Installed::Older => (Some(false), "installed by another version of this command: run `multiplex bar on` to renew it".to_owned()),
        Installed::No => (Some(false), "not installed: `multiplex bar on` puts Multiplex in the bar".to_owned()),
    }
}

pub fn run(args: &[&str]) -> anyhow::Result<()> {
    let dir = plugin_dir()?;
    let command = std::env::current_exe().context("could not find the multiplex command's own path")?;
    let mut shell = Omarchy;
    match args {
        ["on"] => println!("{}", turn_on(&dir, &command, &mut shell)?),
        ["off"] => println!("{}", turn_off(&dir, &mut shell)?),
        [] => println!("The bar widget: {}.", status(&dir, &command, shell.there()).1),
        _ => bail!("usage: multiplex bar [on|off]"),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A shell that writes down what it is asked and says the widget is
    /// (or is not) in the bar.
    struct Pretend {
        there: bool,
        enabled: Option<bool>,
        /// Everything asked, apart from "are you there?".
        asked: Vec<String>,
        /// How often it does not answer "are you there?" before it does.
        deaf_for: u32,
        /// Enabling: done but not answered, or not done at all.
        enable: Enable,
        pauses: u32,
    }

    #[derive(PartialEq)]
    enum Enable {
        Works,
        WorksWithoutSayingSo,
        Fails,
    }

    impl Pretend {
        fn new(enabled: Option<bool>) -> Self {
            Self { there: true, enabled, asked: Vec::new(), deaf_for: 0, enable: Enable::Works, pauses: 0 }
        }
    }

    impl Shell for Pretend {
        fn there(&self) -> bool {
            self.there
        }

        fn pause(&mut self) {
            self.pauses += 1;
        }

        fn ask(&mut self, command: &[&str]) -> anyhow::Result<String> {
            if command == ["omarchy-shell", "shell", "ping"] {
                if self.deaf_for > 0 {
                    self.deaf_for -= 1;
                    bail!("omarchy-shell is not responding");
                }
                return Ok("ok".to_owned());
            }
            self.asked.push(command.join(" "));
            if command == ["omarchy", "plugin", "enable", ID] {
                if self.enable != Enable::Fails {
                    self.enabled = Some(true);
                }
                if self.enable != Enable::Works {
                    bail!("omarchy-shell is not responding");
                }
            }
            Ok(match (command, self.enabled) {
                (["omarchy", "plugin", "list", "--json"], Some(enabled)) => format!(r#"[{{"id":"omarchy.power","enabled":true}},{{"id":"{ID}","enabled":{enabled}}}]"#),
                (["omarchy", "plugin", "list", "--json"], None) => r#"[{"id":"omarchy.power","enabled":true}]"#.to_owned(),
                _ => "ok".to_owned(),
            })
        }
    }

    fn read(dir: &Path, name: &str) -> String {
        std::fs::read_to_string(dir.join(name)).unwrap()
    }

    #[test]
    fn the_widget_this_command_carries_is_whole() {
        let manifest: serde_json::Value = serde_json::from_str(FILES[0].1).unwrap();
        assert_eq!(manifest["id"], ID);
        assert_eq!(manifest["kinds"][0], "bar-widget");
        // The file the manifest names as the widget is among those carried.
        let entry = manifest["entryPoints"]["barWidget"].as_str().unwrap();
        let panel = FILES.iter().find(|(name, _)| *name == entry).expect("the entry point is carried").1;
        assert!(panel.contains(&format!("moduleName: \"{ID}\"")));
        // Everything the panel imports from beside itself is carried or written.
        for import in panel.lines().filter_map(|line| line.strip_prefix("import \"")).filter_map(|rest| rest.split('"').next()) {
            assert!(import == WHERE || FILES.iter().any(|(name, _)| *name == import), "{import} is imported but not installed");
        }
        assert!(panel.contains("import \"Where.js\" as Where"));
        let strings: serde_json::Value = serde_json::from_str(FILES.iter().find(|(name, _)| *name == "i18n/en.json").unwrap().1).unwrap();
        assert!(strings["title"].is_string());
    }

    #[test]
    fn where_the_command_is_survives_any_path() {
        assert_eq!(where_js(Path::new("/usr/bin/multiplex")), "// Written by `multiplex bar on`: the command this widget runs.\nvar multiplex = \"/usr/bin/multiplex\"\n");
        // Quotes, a backslash and a line break stay inside the one string.
        let odd = where_js(Path::new("/home/sam/my \"apps\"/a\\b\n/multiplex"));
        let line = odd.lines().nth(1).unwrap();
        assert_eq!(odd.lines().count(), 2, "{odd}");
        let literal = line.strip_prefix("var multiplex = ").unwrap();
        assert_eq!(serde_json::from_str::<String>(literal).unwrap(), "/home/sam/my \"apps\"/a\\b\n/multiplex");
    }

    #[test]
    fn turning_it_on_writes_the_files_and_tells_the_shell() {
        let home = tempfile::tempdir().unwrap();
        let dir = home.path().join("omarchy/plugins").join(ID);
        let command = Path::new("/home/sam/.local/bin/multiplex");
        assert_eq!(installed(&dir, command), Installed::No);
        let mut shell = Pretend::new(None);
        let said = turn_on(&dir, command, &mut shell).unwrap();
        assert!(said.contains("in the bar"));
        assert_eq!(shell.asked, ["omarchy-shell shell rescanPlugins", "omarchy plugin list --json", format!("omarchy plugin enable {ID}").as_str()]);
        for (name, text) in FILES {
            assert_eq!(&read(&dir, name), text, "{name}");
        }
        assert_eq!(read(&dir, WHERE), where_js(command));
        assert_eq!(installed(&dir, command), Installed::Current);
        // Nothing half-written is left beside the files.
        let left: Vec<String> = std::fs::read_dir(&dir).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).filter(|n| n.starts_with('.')).collect();
        assert!(left.is_empty(), "{left:?}");
    }

    #[test]
    fn a_widget_already_in_the_bar_is_renewed_where_it_is() {
        let home = tempfile::tempdir().unwrap();
        let dir = home.path().join(ID);
        let command = Path::new("/usr/bin/multiplex");
        write(&dir, command).unwrap();
        // An older version's file, and the command somewhere else now.
        std::fs::write(dir.join("Model.js"), "// older\n").unwrap();
        assert_eq!(installed(&dir, command), Installed::Older);
        let moved = Path::new("/home/sam/.local/bin/multiplex");
        assert_eq!(installed(&dir, moved), Installed::Older);
        let mut shell = Pretend::new(Some(true));
        // The bar still shows what it loaded before: said, with what to do.
        assert_eq!(turn_on(&dir, moved, &mut shell).unwrap(), RENEWED);
        assert!(RENEWED.contains("omarchy restart shell"));
        // Not enabled a second time: that would move it from where the
        // user put it.
        assert_eq!(shell.asked, ["omarchy-shell shell rescanPlugins", "omarchy plugin list --json"]);
        assert_eq!(installed(&dir, moved), Installed::Current);
        // Once more, with nothing to renew: nothing is written, and no restart asked for.
        let before = std::fs::metadata(dir.join("Panel.qml")).unwrap().modified().unwrap();
        assert_eq!(turn_on(&dir, moved, &mut Pretend::new(Some(true))).unwrap(), THERE);
        assert_eq!(std::fs::metadata(dir.join("Panel.qml")).unwrap().modified().unwrap(), before);
        // Known to the shell but switched off: switched on again.
        let mut shell = Pretend::new(Some(false));
        turn_on(&dir, moved, &mut shell).unwrap();
        assert_eq!(shell.asked.last().unwrap(), &format!("omarchy plugin enable {ID}"));
    }

    #[test]
    fn a_shell_busy_reloading_is_waited_for() {
        let home = tempfile::tempdir().unwrap();
        let command = Path::new("/usr/bin/multiplex");
        // Deaf for a while after the files changed, then fine.
        let mut shell = Pretend::new(None);
        shell.deaf_for = 7;
        assert_eq!(turn_on(&home.path().join("a"), command, &mut shell).unwrap(), ON);
        assert!(shell.pauses >= 7, "{}", shell.pauses);
        // It took the widget in but could not say so: that is not a failure.
        let mut shell = Pretend::new(None);
        shell.enable = Enable::WorksWithoutSayingSo;
        assert_eq!(turn_on(&home.path().join("b"), command, &mut shell).unwrap(), ON);
        assert_eq!(shell.asked.last().unwrap(), "omarchy plugin list --json");
        // It really did not take it in: said, with the shell's own words.
        let mut shell = Pretend::new(None);
        shell.enable = Enable::Fails;
        assert!(turn_on(&home.path().join("c"), command, &mut shell).unwrap_err().to_string().contains("not responding"));
        // It never answers at all: the files stay, and the message says what to do.
        let mut shell = Pretend::new(None);
        shell.deaf_for = u32::MAX;
        let problem = turn_on(&home.path().join("d"), command, &mut shell).unwrap_err().to_string();
        assert!(problem.contains("not answering") && problem.contains("multiplex bar on"), "{problem}");
        assert_eq!(installed(&home.path().join("d"), command), Installed::Current);
    }

    #[test]
    fn turning_it_off_takes_it_out_of_the_bar_and_removes_only_its_own_files() {
        let home = tempfile::tempdir().unwrap();
        let dir = home.path().join(ID);
        write(&dir, Path::new("/usr/bin/multiplex")).unwrap();
        let mut shell = Pretend::new(Some(true));
        assert_eq!(turn_off(&dir, &mut shell).unwrap(), "Multiplex is out of the bar.");
        assert_eq!(shell.asked, ["omarchy plugin list --json", format!("omarchy plugin disable {ID}").as_str(), "omarchy-shell shell rescanPlugins"]);
        assert!(!dir.exists());
        // Again: nothing to do, and said so.
        let mut shell = Pretend::new(None);
        assert_eq!(turn_off(&dir, &mut shell).unwrap(), "Multiplex was not in the bar.");
        assert_eq!(shell.asked, ["omarchy plugin list --json", "omarchy-shell shell rescanPlugins"]);
        // A file of the user's own in the directory stays, and so does the directory.
        write(&dir, Path::new("/usr/bin/multiplex")).unwrap();
        std::fs::write(dir.join("notes.txt"), "mine").unwrap();
        turn_off(&dir, &mut Pretend::new(Some(false))).unwrap();
        assert_eq!(read(&dir, "notes.txt"), "mine");
        assert!(!dir.join("manifest.json").exists() && !dir.join("i18n").exists());
    }

    #[test]
    fn another_plugins_directory_is_never_touched() {
        let home = tempfile::tempdir().unwrap();
        let dir = home.path().join(ID);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("manifest.json"), r#"{"id":"someone.else"}"#).unwrap();
        std::fs::write(dir.join("Panel.qml"), "theirs").unwrap();
        let command = Path::new("/usr/bin/multiplex");
        let mut shell = Pretend::new(None);
        assert!(turn_on(&dir, command, &mut shell).unwrap_err().to_string().contains("left alone"));
        assert!(turn_off(&dir, &mut shell).unwrap_err().to_string().contains("left alone"));
        assert!(shell.asked.is_empty(), "{:?}", shell.asked);
        assert_eq!(read(&dir, "Panel.qml"), "theirs");
        // The same for a directory with something in it that is no plugin at all.
        let dir = home.path().join("other");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("Panel.qml"), "theirs").unwrap();
        assert!(write(&dir, command).is_err());
        assert!(remove(&dir).is_err());
        assert_eq!(read(&dir, "Panel.qml"), "theirs");
    }

    #[test]
    fn without_the_omarchy_shell_nothing_is_written() {
        let home = tempfile::tempdir().unwrap();
        let dir = home.path().join(ID);
        let mut shell = Pretend::new(None);
        shell.there = false;
        assert_eq!(turn_on(&dir, Path::new("/usr/bin/multiplex"), &mut shell).unwrap_err().to_string(), NO_SHELL);
        assert!(!dir.exists());
        assert!(shell.asked.is_empty());
        assert_eq!(status(&dir, Path::new("/usr/bin/multiplex"), false).0, None);
    }

    #[test]
    fn the_status_says_what_to_run() {
        let home = tempfile::tempdir().unwrap();
        let dir = home.path().join(ID);
        let command = Path::new("/usr/bin/multiplex");
        let (ok, text) = status(&dir, command, true);
        assert_eq!(ok, Some(false));
        assert!(text.contains("multiplex bar on"));
        write(&dir, command).unwrap();
        assert_eq!(status(&dir, command, true).0, Some(true));
        std::fs::write(dir.join("Panel.qml"), "older").unwrap();
        let (ok, text) = status(&dir, command, true);
        assert_eq!(ok, Some(false));
        assert!(text.contains("renew"));
    }

    #[test]
    fn the_shells_list_says_whether_the_widget_is_in_the_bar() {
        assert_eq!(enabled_in(&format!(r#"[{{"id":"{ID}","enabled":true}}]"#)), Some(true));
        assert_eq!(enabled_in(&format!(r#"[{{"id":"{ID}","enabled":false}}]"#)), Some(false));
        assert_eq!(enabled_in(r#"[{"id":"omarchy.power","enabled":true}]"#), None);
        assert_eq!(enabled_in("not json"), None);
        assert_eq!(enabled_in(""), None);
    }
}
