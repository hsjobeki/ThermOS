use std::future::Future;
use std::marker::PhantomData;
use std::sync::Arc;
use std::thread::JoinHandle;

use slint::ComponentHandle;
use tokio::sync::Notify;

use crate::shutdown::Shutdown;
use crate::source::{guarded, Source};

#[derive(Clone)]
pub struct DbusShutdown {
    notify: Arc<Notify>,
}

impl DbusShutdown {
    /// Resolves on shutdown.
    pub async fn notified(&self) {
        self.notify.notified().await;
    }
}

pub fn spawn_dbus<T, F, Fut>(ui: slint::Weak<T>, shutdown: Arc<Shutdown>, body: F) -> JoinHandle<()>
where
    T: ComponentHandle + 'static,
    F: FnOnce(slint::Weak<T>, DbusShutdown) -> Fut + Send + 'static,
    Fut: Future<Output = ()>,
{
    let notify = Arc::new(Notify::new());
    let waker_notify = notify.clone();
    shutdown.register(Box::new(move || waker_notify.notify_one()));
    let token = DbusShutdown { notify };

    std::thread::Builder::new()
        .name("dbus".into())
        .spawn(move || {
            guarded(shutdown, || {
                let rt = match tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                {
                    Ok(rt) => rt,
                    Err(e) => {
                        eprintln!("[dbus] runtime build failed: {e}");
                        return;
                    }
                };
                rt.block_on(body(ui, token));
                eprintln!("[dbus] loop exited");
            });
        })
        .expect("spawn dbus source")
}

pub struct DbusSource<T, F> {
    body: F,
    _marker: PhantomData<fn() -> T>,
}

impl<T, F, Fut> DbusSource<T, F>
where
    T: ComponentHandle + 'static,
    F: FnOnce(slint::Weak<T>, DbusShutdown) -> Fut + Send + 'static,
    Fut: Future<Output = ()>,
{
    pub fn new(body: F) -> Self {
        DbusSource {
            body,
            _marker: PhantomData,
        }
    }
}

impl<T, F, Fut> Source<T> for DbusSource<T, F>
where
    T: ComponentHandle + 'static,
    F: FnOnce(slint::Weak<T>, DbusShutdown) -> Fut + Send + 'static,
    Fut: Future<Output = ()>,
{
    fn spawn(self: Box<Self>, ui: slint::Weak<T>, shutdown: Arc<Shutdown>) -> JoinHandle<()> {
        spawn_dbus(ui, shutdown, self.body)
    }
}
