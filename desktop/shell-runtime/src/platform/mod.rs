// The Tier 1 layer-shell backend: a custom slint::Platform painting one
// wlr-layer-shell surface with the software renderer on a single calloop loop and
// a single Wayland connection. Selected by a component at startup; its Sources and
// UI are identical to the Tier 2 (winit) path. Validated in isolation by
// spikes/layer-shell-spike.
mod layer;
mod proxy;
mod shm;

pub use layer::{Edge, LayerConfig, LayerShellApp};
