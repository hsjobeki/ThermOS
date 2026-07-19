//! Shared runtime for every ThermOS desktop component.
//!
//! A component is a thin binary over this crate: build an `App`, construct a
//! [`ShellRuntime`], register a set of [`Source`]s, and `run`.
//!

mod platform;
mod runtime;
mod shutdown;
mod signals;
mod source;
mod sources;
mod ui;

pub use runtime::ShellRuntime;
pub use shutdown::Shutdown;
pub use source::Source;
pub use ui::apply_ui;

pub use sources::dbus::{spawn_dbus, DbusShutdown, DbusSource};
pub use sources::wayland::{Toplevel, WaylandToplevelSource};

pub use platform::{Edge, LayerConfig, LayerShellApp};

// Re-export one D-Bus + async surface
// UI should use these to keep the tree in sync
pub use futures_util;
pub use zbus;
