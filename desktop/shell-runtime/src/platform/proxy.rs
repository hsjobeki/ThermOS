use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use smithay_client_toolkit::reexports::calloop::{self, ping::Ping, LoopSignal};

/// Closures queued by `invoke_from_event_loop`, drained on the loop thread.
pub(crate) type UiQueue = Arc<Mutex<VecDeque<Box<dyn FnOnce() + Send>>>>;

/// Routes `slint::invoke_from_event_loop` and `slint::quit_event_loop` onto the
/// layer-shell `calloop` loop. This is the load-bearing piece of the custom
/// `Platform`: without it both calls return `NoEventLoopProvider` under a
/// non-winit backend, so neither a worker nor shutdown could reach the UI.
///
/// `slint::platform::EventLoopProxy` requires `Send + Sync`. calloop's channel
/// `Sender` wraps `std::mpsc::Sender`, which is `!Sync`, so a channel cannot back
/// it. Instead a `calloop::ping::Ping` (Send+Sync) wakes the loop and an
/// `Arc<Mutex<VecDeque>>` (Send+Sync) carries the closures; a `PingSource` drains
/// and runs them on the loop thread.
#[derive(Clone)]
pub(crate) struct CalloopProxy {
    pub(crate) queue: UiQueue,
    pub(crate) ping: Ping,
    pub(crate) signal: LoopSignal,
}

impl slint::platform::EventLoopProxy for CalloopProxy {
    fn invoke_from_event_loop(
        &self,
        event: Box<dyn FnOnce() + Send>,
    ) -> Result<(), slint::EventLoopError> {
        self.queue.lock().unwrap().push_back(event);
        self.ping.ping();
        Ok(())
    }
    fn quit_event_loop(&self) -> Result<(), slint::EventLoopError> {
        self.signal.stop();
        Ok(())
    }
}

/// Build the proxy plumbing. Returns the proxy (installed into the `Platform`)
/// and the `PingSource` to register in the loop (its handler drains `queue`).
pub(crate) fn make_proxy(
    signal: LoopSignal,
) -> Result<(CalloopProxy, calloop::ping::PingSource, UiQueue), calloop::error::Error> {
    let (ping, ping_source) = calloop::ping::make_ping()?;
    let queue: UiQueue = Arc::new(Mutex::new(VecDeque::new()));
    let proxy = CalloopProxy {
        queue: queue.clone(),
        ping,
        signal,
    };
    Ok((proxy, ping_source, queue))
}
