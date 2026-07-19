use std::sync::Arc;
use std::thread::JoinHandle;

use signal_hook::consts::SIGINT;
use signal_hook::iterator::{Handle, Signals};

use crate::shutdown::Shutdown;

pub(crate) struct Supervisor {
    handle: Handle,
    thread: JoinHandle<()>,
}

pub(crate) fn spawn_sigint(shutdown: Arc<Shutdown>) -> Supervisor {
    let mut signals = Signals::new([SIGINT]).expect("register SIGINT handler");
    let handle = signals.handle();
    let thread = std::thread::Builder::new()
        .name("sigint".into())
        .spawn(move || {
            for sig in signals.forever() {
                if sig == SIGINT {
                    shutdown.trigger();
                    break;
                }
            }
        })
        .expect("spawn SIGINT supervisor");
    Supervisor { handle, thread }
}

pub(crate) fn stop(supervisor: Supervisor) {
    supervisor.handle.close();
    let _ = supervisor.thread.join();
}
