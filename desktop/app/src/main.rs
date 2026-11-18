//! The Multiplex window for Omarchy: the paired phones, pairing a new
//! one, what each may do, sending files, finding a phone.
//!
//! The window is QML (`qml/Main.qml`); what it shows and does is Rust
//! (`backend.rs`, `logic.rs`), which in turn asks the `multiplex` command.
//! Opened with `multiplex open` or from the app launcher.

mod backend;
mod logic;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QQuickStyle, QString, QUrl};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("--version") => {
            println!("multiplex-app {}", env!("CARGO_PKG_VERSION"));
            return;
        }
        Some("--help" | "-h") => {
            print!("{}", logic::USAGE);
            return;
        }
        _ => {}
    }
    // Said before any window opens, and with the usage beside it.
    if let Err(problem) = logic::first_actions(&args, "") {
        eprintln!("multiplex-app: {problem}\n\n{}", logic::USAGE);
        std::process::exit(2);
    }
    // A picture of the window is taken without a screen, whatever the
    // desktop says programs should draw on: Omarchy sets QT_QPA_PLATFORM
    // for everything, and a picture run must never open a window on it.
    if std::env::var_os("MULTIPLEX_APP_SHOT").is_some() {
        std::env::set_var("QT_QPA_PLATFORM", "offscreen");
        std::env::set_var("QT_QUICK_BACKEND", "software");
        // No desktop theme plugin either: one of them wants a display.
        std::env::set_var("QT_QPA_PLATFORMTHEME", "");
    }

    let mut app = QGuiApplication::new();
    // The same name as the launcher entry and the icon, so the desktop
    // knows which window is whose.
    QGuiApplication::set_desktop_file_name(&QString::from("multiplex"));
    QQuickStyle::set_style(&QString::from("Material"));

    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/io/github/molotovgit/multiplex/qml/Main.qml"));
    }
    let code = app.as_mut().map_or(1, |app| app.exec());
    // The window's objects go before the program does: the backend takes
    // back a pairing code that is still waiting when it is dropped.
    drop(engine);
    drop(app);
    std::process::exit(code);
}
