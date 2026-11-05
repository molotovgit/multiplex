//! One shared async runtime for all network work.
//!
//! The SSH library (russh) needs a tokio runtime to run its background
//! tasks. Flutter calls into Rust from its own threads, so we keep one
//! long-lived runtime here and send every async job to it.

use std::future::Future;
use std::sync::LazyLock;

use tokio::runtime::{Builder, Runtime};

/// Owns the process-wide tokio runtime.
pub struct AsyncRuntime;

static RUNTIME: LazyLock<Runtime> = LazyLock::new(|| {
    Builder::new_multi_thread()
        .worker_threads(4)
        .thread_name("vaultterm-net")
        .enable_all()
        .build()
        .expect("could not start the network runtime")
});

impl AsyncRuntime {
    /// The shared runtime. Created the first time it is used.
    pub fn get() -> &'static Runtime {
        &RUNTIME
    }

    /// Starts a background job that runs on its own.
    pub fn spawn<F>(future: F) -> tokio::task::JoinHandle<F::Output>
    where
        F: Future + Send + 'static,
        F::Output: Send + 'static,
    {
        RUNTIME.spawn(future)
    }

    /// Runs a job on the shared runtime and waits for its result.
    ///
    /// Use this for every async call that comes from Flutter: it makes sure
    /// the job runs inside tokio, whatever thread the call came from.
    pub async fn run<F>(future: F) -> anyhow::Result<F::Output>
    where
        F: Future + Send + 'static,
        F::Output: Send + 'static,
    {
        RUNTIME
            .spawn(future)
            .await
            .map_err(|err| anyhow::anyhow!("background task failed: {err}"))
    }
}
