use slint::ComponentHandle;

/// Takes a weak handle to a Slint component and a closure
/// Invokes the closure on the component if it is still alive.
pub fn apply_ui<T>(ui: &slint::Weak<T>, f: impl FnOnce(T) + Send + 'static)
where
    T: ComponentHandle + 'static,
{
    let weak = ui.clone();
    let _ = slint::invoke_from_event_loop(move || {
        if let Some(app) = weak.upgrade() {
            f(app);
        }
    });
}
