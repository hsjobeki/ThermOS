use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

type Waker = Box<dyn Fn() + Send + Sync>;

type Quit = Box<dyn Fn() + Send + Sync>;

pub struct Shutdown {
    fired: AtomicBool,
    wakers: Mutex<Vec<Waker>>,
    quit: Quit,
}

impl Shutdown {
    pub fn new() -> Self {
        Shutdown {
            fired: AtomicBool::new(false),
            wakers: Mutex::new(Vec::new()),
            // After the loop has already quit this returns Err, which is fine: the
            // registered wakers are what tear the sources down.
            quit: Box::new(|| {
                let _ = slint::invoke_from_event_loop(|| {
                    let _ = slint::quit_event_loop();
                });
            }),
        }
    }

    /// Test-only constructor that injects the quit action
    #[cfg(test)]
    fn with_quit(quit: Quit) -> Self {
        Shutdown {
            fired: AtomicBool::new(false),
            wakers: Mutex::new(Vec::new()),
            quit,
        }
    }

    /// Register a waker to be invoked on shutdown.
    /// If shutdown has already fired, the waker is invoked immediately.
    pub fn register(&self, waker: Waker) {
        let mut wakers = self.wakers.lock().unwrap();
        if self.fired.load(Ordering::SeqCst) {
            drop(wakers);
            waker();
        } else {
            wakers.push(waker);
        }
    }

    pub fn is_fired(&self) -> bool {
        self.fired.load(Ordering::SeqCst)
    }

    /// Fire shutdown. Idempotent: a second call returns immediately, so a worker
    /// failure and a SIGINT racing cannot double-wake or double-quit.
    pub fn trigger(&self) {
        if self.fired.swap(true, Ordering::SeqCst) {
            return;
        }
        {
            let wakers = self.wakers.lock().unwrap();
            for waker in wakers.iter() {
                waker();
            }
        }
        (self.quit)();
    }
}

impl Default for Shutdown {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;
    use std::sync::Arc;
    use std::thread;

    fn counter() -> (Arc<AtomicUsize>, Waker) {
        let n = Arc::new(AtomicUsize::new(0));
        let c = n.clone();
        (
            n,
            Box::new(move || {
                c.fetch_add(1, Ordering::SeqCst);
            }),
        )
    }

    #[test]
    fn trigger_wakes_each_source_and_quits_exactly_once() {
        let quit_runs = Arc::new(AtomicUsize::new(0));
        let q = quit_runs.clone();
        let sd = Shutdown::with_quit(Box::new(move || {
            q.fetch_add(1, Ordering::SeqCst);
        }));

        let (runs, waker) = counter();
        sd.register(waker);
        assert!(!sd.is_fired());

        sd.trigger();
        assert!(sd.is_fired());
        // Idempotent: further triggers neither re-wake nor re-quit.
        sd.trigger();
        sd.trigger();

        assert_eq!(runs.load(Ordering::SeqCst), 1, "waker fired exactly once");
        assert_eq!(
            quit_runs.load(Ordering::SeqCst),
            1,
            "quit invoked exactly once"
        );
    }

    #[test]
    fn all_registered_wakers_fire_on_trigger() {
        let sd = Shutdown::with_quit(Box::new(|| {}));
        let total = Arc::new(AtomicUsize::new(0));
        for _ in 0..5 {
            let t = total.clone();
            sd.register(Box::new(move || {
                t.fetch_add(1, Ordering::SeqCst);
            }));
        }
        sd.trigger();
        assert_eq!(total.load(Ordering::SeqCst), 5);
    }

    #[test]
    fn register_before_trigger_runs_on_trigger_not_before() {
        let sd = Shutdown::with_quit(Box::new(|| {}));
        let (runs, waker) = counter();
        sd.register(waker);
        assert_eq!(
            runs.load(Ordering::SeqCst),
            0,
            "must not run before trigger"
        );
        sd.trigger();
        assert_eq!(runs.load(Ordering::SeqCst), 1, "runs once on trigger");
    }

    #[test]
    fn register_after_trigger_runs_immediately() {
        let sd = Shutdown::with_quit(Box::new(|| {}));
        sd.trigger();
        let (runs, waker) = counter();
        sd.register(waker);
        assert_eq!(
            runs.load(Ordering::SeqCst),
            1,
            "waker registered during teardown still unparks"
        );
    }

    // Race invariant:
    // trigger swaps the flag before taking the wakers lock
    #[test]
    fn concurrent_register_and_trigger_runs_each_waker_exactly_once() {
        for _ in 0..200 {
            let sd = Arc::new(Shutdown::with_quit(Box::new(|| {})));
            let runs = Arc::new(AtomicUsize::new(0));
            let n = 16usize;

            let mut handles = Vec::with_capacity(n + 1);
            for _ in 0..n {
                let sd = sd.clone();
                let runs = runs.clone();
                handles.push(thread::spawn(move || {
                    sd.register(Box::new(move || {
                        runs.fetch_add(1, Ordering::SeqCst);
                    }));
                }));
            }
            let sd_t = sd.clone();
            handles.push(thread::spawn(move || sd_t.trigger()));

            for h in handles {
                h.join().unwrap();
            }
            // All registrations have returned and trigger has fired, so by the
            // invariant every waker has run, once.
            assert_eq!(
                runs.load(Ordering::SeqCst),
                n,
                "every registered waker must run exactly once"
            );
        }
    }
}
