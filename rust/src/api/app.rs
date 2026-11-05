//! App start-up hooks.

/// Called once by Flutter when the native library loads.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    // Start the network runtime now rather than on the first connection,
    // so the first connect is not slower than the rest.
    let _ = crate::engine::runtime::AsyncRuntime::get();
}

/// Version of the native core, shown in the About screen.
#[flutter_rust_bridge::frb(sync)]
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}
