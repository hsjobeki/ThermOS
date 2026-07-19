use std::sync::Arc;
use std::thread::JoinHandle;

use slint::ComponentHandle;

use crate::shutdown::Shutdown;
use crate::signals;
use crate::source::Source;

pub struct ShellRuntime<T>
where
    T: ComponentHandle + 'static,
{
    ui: slint::Weak<T>,
    shutdown: Arc<Shutdown>,
    workers: Vec<JoinHandle<()>>,
}

impl<T> ShellRuntime<T>
where
    T: ComponentHandle + 'static,
{
    pub fn new(app: &T) -> Self {
        ShellRuntime {
            ui: app.as_weak(),
            shutdown: Arc::new(Shutdown::new()),
            workers: Vec::new(),
        }
    }

    pub fn shutdown(&self) -> Arc<Shutdown> {
        self.shutdown.clone()
    }

    /// A weak UI handle for sources built outside `add_source`.
    pub fn ui(&self) -> slint::Weak<T> {
        self.ui.clone()
    }

    pub fn add_source(&mut self, source: Box<dyn Source<T>>) {
        let handle = source.spawn(self.ui.clone(), self.shutdown.clone());
        self.workers.push(handle);
    }

    pub fn run(self, app: T) -> Result<(), slint::PlatformError> {
        let supervisor = signals::spawn_sigint(self.shutdown.clone());
        app.run()?;
        self.shutdown.trigger();
        signals::stop(supervisor);
        for worker in self.workers {
            let _ = worker.join();
        }
        Ok(())
    }
}
