use std::sync::Arc;
use std::thread::JoinHandle;

use slint::ComponentHandle;

use crate::shutdown::Shutdown;

pub trait Source<T>: Send + 'static
where
    T: ComponentHandle + 'static,
{
    fn spawn(self: Box<Self>, ui: slint::Weak<T>, shutdown: Arc<Shutdown>) -> JoinHandle<()>;
}

pub(crate) fn guarded<F: FnOnce()>(shutdown: Arc<Shutdown>, body: F) {
    struct Guard(Arc<Shutdown>);
    impl Drop for Guard {
        fn drop(&mut self) {
            self.0.trigger();
        }
    }
    let guard = Guard(shutdown);
    body();
    drop(guard);
}
