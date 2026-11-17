use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    // The window (QML) and the Rust object it talks to are one QML module,
    // compiled into the program.
    CxxQtBuilder::new_qml_module(QmlModule::new("io.github.molotovgit.multiplex").qml_file("qml/Main.qml")).files(["src/backend.rs"]).build();
}
