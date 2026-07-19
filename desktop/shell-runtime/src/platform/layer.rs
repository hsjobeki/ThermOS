use std::error::Error;
use std::rc::Rc;
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use slint::platform::software_renderer::{
    MinimalSoftwareWindow, RepaintBufferType, SoftwareRenderer,
};
use slint::platform::{PointerEventButton, WindowAdapter, WindowEvent};
use slint::{ComponentHandle, LogicalPosition, LogicalSize, PhysicalSize};

use smithay_client_toolkit::{
    compositor::{CompositorHandler, CompositorState},
    delegate_compositor, delegate_foreign_toplevel_list, delegate_layer, delegate_output,
    delegate_pointer, delegate_registry, delegate_seat, delegate_shm,
    foreign_toplevel_list::{ForeignToplevelList, ForeignToplevelListHandler},
    output::{OutputHandler, OutputState},
    reexports::{
        calloop::{EventLoop, LoopSignal},
        calloop_wayland_source::WaylandSource,
        client::{
            globals::registry_queue_init,
            protocol::{wl_output, wl_pointer, wl_seat, wl_shm, wl_surface},
            Connection, Proxy, QueueHandle,
        },
        protocols::ext::foreign_toplevel_list::v1::client::{
            ext_foreign_toplevel_handle_v1::ExtForeignToplevelHandleV1,
            ext_foreign_toplevel_list_v1::ExtForeignToplevelListV1,
        },
    },
    registry::{ProvidesRegistryState, RegistryState},
    registry_handlers,
    seat::{
        pointer::{PointerEvent, PointerEventKind, PointerHandler},
        Capability, SeatHandler, SeatState,
    },
    shell::{
        wlr_layer::{
            Anchor, KeyboardInteractivity, Layer, LayerShell, LayerShellHandler, LayerSurface,
            LayerSurfaceConfigure,
        },
        WaylandSurface,
    },
    shm::{slot::SlotPool, Shm, ShmHandler},
};

use crate::platform::proxy::{make_proxy, CalloopProxy, UiQueue};
use crate::platform::shm::ShmPixel;
use crate::shutdown::Shutdown;
use crate::signals;
use crate::source::Source;
use crate::sources::wayland::Toplevel;

/// Which screen edge a bar anchors to. Width always spans the full output.
#[derive(Clone, Copy, Debug)]
pub enum Edge {
    Top,
    Bottom,
}

/// A layer-shell bar surface: anchored to one edge, full output width, reserving
/// `height` pixels of exclusive zone.
pub struct LayerConfig {
    pub namespace: String,
    pub edge: Edge,
    pub height: u32,
}

// === Custom Platform =================================================================

struct LayerShellPlatform {
    window: Rc<MinimalSoftwareWindow>,
    start: Instant,
    proxy: CalloopProxy,
}

impl slint::platform::Platform for LayerShellPlatform {
    fn create_window_adapter(
        &self,
    ) -> Result<Rc<dyn slint::platform::WindowAdapter>, slint::PlatformError> {
        Ok(self.window.clone())
    }
    fn duration_since_start(&self) -> Duration {
        self.start.elapsed()
    }
    // Load-bearing: routes invoke_from_event_loop / quit_event_loop onto our
    // calloop loop. set_platform reads this once and installs it as the global
    // proxy, so the Platform MUST be installed before App::new().
    fn new_event_loop_proxy(&self) -> Option<Box<dyn slint::platform::EventLoopProxy>> {
        Some(Box::new(self.proxy.clone()))
    }
}

// === Wayland client state ============================================================
// App-agnostic: the only UI coupling is `push_toplevels`, a loop-thread closure the
// component supplies (it upgrades its own Weak<App> and calls a generated setter).
// Everything else paints through the MinimalSoftwareWindow, which renders whatever
// component App::new() registered on the installed Platform.

struct State {
    registry_state: RegistryState,
    seat_state: SeatState,
    output_state: OutputState,
    shm: Shm,
    pool: SlotPool,
    layer: LayerSurface,
    toplevel_list: ForeignToplevelList,
    window: Rc<MinimalSoftwareWindow>,
    push_toplevels: Box<dyn Fn(Vec<Toplevel>)>,
    signal: LoopSignal,
    pointer: Option<wl_pointer::WlPointer>,
    width: u32,
    height: u32,
    first_configure: bool,
    frame_count: u64,
    // Observability for tests (set from SHELL_RUNTIME_TRACE): logs the configured
    // size and a per-frame counter so a harness can assert frame liveness without
    // a display. Off (silent) in production.
    trace: bool,
}

impl State {
    fn draw(&mut self, qh: &QueueHandle<Self>) {
        let (w, h) = (self.width, self.height);
        if w == 0 || h == 0 {
            return;
        }
        let stride = w as i32 * 4;

        // Drive Slint's clock: fires timers and advances animations.
        slint::platform::update_timers_and_animations();

        let (buffer, canvas) = self
            .pool
            .create_buffer(w as i32, h as i32, stride, wl_shm::Format::Xrgb8888)
            .expect("create buffer");
        // shm slots are page-aligned and the length is a multiple of 4, so
        // head/tail are empty.
        let (head, pixels, tail) = unsafe { canvas.align_to_mut::<ShmPixel>() };
        debug_assert!(head.is_empty() && tail.is_empty());

        let drew = self.window.draw_if_needed(|renderer: &SoftwareRenderer| {
            renderer.render(pixels, w as usize);
        });

        // Re-arm the frame callback every draw so the compositor keeps pacing us.
        let surface = self.layer.wl_surface();
        surface.frame(qh, surface.clone());
        if drew {
            buffer.attach_to(surface).expect("attach buffer");
            surface.damage_buffer(0, 0, w as i32, h as i32);
            self.frame_count += 1;
            if self.trace {
                eprintln!("[layer] frame {}", self.frame_count);
            }
        }
        surface.commit();
    }

    // Recompute the toplevel list and push it to the UI. `excluding` drops the
    // handle mid-close (SCTK calls toplevel_closed before removing it). Runs on the
    // loop thread, so it pushes directly (no proxy).
    fn push_summary(&self, excluding: Option<&ExtForeignToplevelHandleV1>) {
        let mut list = Vec::new();
        for handle in self.toplevel_list.toplevels() {
            if excluding == Some(handle) {
                continue;
            }
            if let Some(info) = self.toplevel_list.info(handle) {
                list.push(Toplevel {
                    title: info.title,
                    app_id: info.app_id,
                    identifier: info.identifier,
                });
            }
        }
        (self.push_toplevels)(list);
    }
}

impl CompositorHandler for State {
    fn scale_factor_changed(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        _: i32,
    ) {
    }
    fn transform_changed(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        _: wl_output::Transform,
    ) {
    }
    fn frame(&mut self, _: &Connection, qh: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: u32) {
        self.draw(qh);
    }
    fn surface_enter(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        _: &wl_output::WlOutput,
    ) {
    }
    fn surface_leave(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        _: &wl_output::WlOutput,
    ) {
    }
}

impl OutputHandler for State {
    fn output_state(&mut self) -> &mut OutputState {
        &mut self.output_state
    }
    fn new_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}
    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}
    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}
}

impl LayerShellHandler for State {
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &LayerSurface) {
        // Compositor dropped our surface: converge on a clean stop.
        self.signal.stop();
    }
    fn configure(
        &mut self,
        _: &Connection,
        qh: &QueueHandle<Self>,
        _: &LayerSurface,
        configure: LayerSurfaceConfigure,
        _: u32,
    ) {
        let (w, h) = configure.new_size;
        if w != 0 {
            self.width = w;
        }
        if h != 0 {
            self.height = h;
        }
        self.window
            .set_size(PhysicalSize::new(self.width, self.height));
        // Propagate the new surface size to the slint view so root.width/height
        // (and right-anchored layout) reflect the real output width. set_size alone
        // does not update the view; the WindowAdapter contract wants a Resized
        // dispatch. Without it a .slint Window with no fixed width renders with none.
        if let Err(e) = self
            .window
            .window()
            .try_dispatch_event(WindowEvent::Resized {
                size: LogicalSize::new(self.width as f32, self.height as f32),
            })
        {
            eprintln!("[layer] resize dispatch error: {e}");
        }
        if self.trace {
            eprintln!("[layer] configured {}x{}", self.width, self.height);
        }
        if self.first_configure {
            self.first_configure = false;
            self.draw(qh);
        }
    }
}

impl SeatHandler for State {
    fn seat_state(&mut self) -> &mut SeatState {
        &mut self.seat_state
    }
    fn new_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat) {}
    fn new_capability(
        &mut self,
        _: &Connection,
        qh: &QueueHandle<Self>,
        seat: wl_seat::WlSeat,
        capability: Capability,
    ) {
        if capability == Capability::Pointer && self.pointer.is_none() {
            self.pointer = Some(self.seat_state.get_pointer(qh, &seat).expect("get pointer"));
        }
    }
    fn remove_capability(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: wl_seat::WlSeat,
        capability: Capability,
    ) {
        if capability == Capability::Pointer {
            if let Some(p) = self.pointer.take() {
                p.release();
            }
        }
    }
    fn remove_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat) {}
}

impl PointerHandler for State {
    fn pointer_frame(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_pointer::WlPointer,
        events: &[PointerEvent],
    ) {
        for event in events {
            if &event.surface != self.layer.wl_surface() {
                continue;
            }
            let position = LogicalPosition::new(event.position.0 as f32, event.position.1 as f32);
            let win_event = match event.kind {
                PointerEventKind::Enter { .. } | PointerEventKind::Motion { .. } => {
                    WindowEvent::PointerMoved { position }
                }
                PointerEventKind::Leave { .. } => WindowEvent::PointerExited,
                PointerEventKind::Press { button, .. } => WindowEvent::PointerPressed {
                    position,
                    button: map_button(button),
                },
                PointerEventKind::Release { button, .. } => WindowEvent::PointerReleased {
                    position,
                    button: map_button(button),
                },
                PointerEventKind::Axis { .. } => continue,
            };
            if let Err(e) = self.window.window().try_dispatch_event(win_event) {
                eprintln!("[layer] pointer dispatch error: {e}");
            }
            self.window.window().request_redraw();
        }
    }
}

// Linux evdev button codes (linux/input-event-codes.h).
fn map_button(code: u32) -> PointerEventButton {
    match code {
        0x110 => PointerEventButton::Left,
        0x111 => PointerEventButton::Right,
        0x112 => PointerEventButton::Middle,
        _ => PointerEventButton::Other,
    }
}

impl ShmHandler for State {
    fn shm_state(&mut self) -> &mut Shm {
        &mut self.shm
    }
}

impl ProvidesRegistryState for State {
    fn registry(&mut self) -> &mut RegistryState {
        &mut self.registry_state
    }
    registry_handlers![OutputState, SeatState];
}

impl ForeignToplevelListHandler for State {
    fn foreign_toplevel_list_state(&mut self) -> &mut ForeignToplevelList {
        &mut self.toplevel_list
    }
    fn new_toplevel(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: ExtForeignToplevelHandleV1,
    ) {
        self.push_summary(None);
    }
    fn update_toplevel(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: ExtForeignToplevelHandleV1,
    ) {
        self.push_summary(None);
    }
    fn toplevel_closed(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        h: ExtForeignToplevelHandleV1,
    ) {
        self.push_summary(Some(&h));
    }
}

delegate_compositor!(State);
delegate_output!(State);
delegate_shm!(State);
delegate_seat!(State);
delegate_pointer!(State);
delegate_layer!(State);
delegate_registry!(State);
delegate_foreign_toplevel_list!(State);

// === Public setup + run ==============================================================

/// A Tier 1 layer-shell surface hosting a Slint UI on the software renderer over a
/// single `calloop` loop and a single Wayland connection. Construct it (which
/// installs the custom `Platform`), then build the `App`, then `run`. The Wayland
/// introspection (foreign-toplevel list) folds onto this same connection and loop;
/// D-Bus `Source`s stay on their own threads and reach the UI through the proxy.
pub struct LayerShellApp {
    event_loop: EventLoop<'static, State>,
    ping_source: Option<smithay_client_toolkit::reexports::calloop::ping::PingSource>,
    queue: UiQueue,
    window: Rc<MinimalSoftwareWindow>,
    conn: Connection,
    event_queue: smithay_client_toolkit::reexports::client::EventQueue<State>,
    layer: LayerSurface,
    shm: Shm,
    pool: SlotPool,
    toplevel_list: ForeignToplevelList,
    registry_state: RegistryState,
    seat_state: SeatState,
    output_state: OutputState,
    signal: LoopSignal,
    height: u32,
    toplevels_present: bool,
    shutdown: Arc<Shutdown>,
}

impl LayerShellApp {
    /// Set up the loop, install the custom `Platform`, connect to Wayland, and
    /// create the anchored layer surface. MUST be called before `App::new()`.
    pub fn new(config: LayerConfig) -> Result<Self, Box<dyn Error>> {
        let event_loop: EventLoop<'static, State> = EventLoop::try_new()?;
        let signal = event_loop.get_signal();

        // Proxy plumbing must exist before set_platform (it reads
        // new_event_loop_proxy once).
        let (proxy, ping_source, queue) = make_proxy(signal.clone())?;

        let window = MinimalSoftwareWindow::new(RepaintBufferType::NewBuffer);
        slint::platform::set_platform(Box::new(LayerShellPlatform {
            window: window.clone(),
            start: Instant::now(),
            proxy,
        }))
        .map_err(|e| format!("set_platform: {e:?}"))?;

        // One Wayland connection for the surface and the introspection.
        let conn = Connection::connect_to_env()?;
        let (globals, event_queue) = registry_queue_init::<State>(&conn)?;
        let qh = event_queue.handle();

        let compositor = CompositorState::bind(&globals, &qh).expect("wl_compositor");
        let layer_shell = LayerShell::bind(&globals, &qh).expect("zwlr_layer_shell_v1");
        let shm = Shm::bind(&globals, &qh).expect("wl_shm");

        let surface = compositor.create_surface(&qh);
        let layer = layer_shell.create_layer_surface(
            &qh,
            surface,
            Layer::Top,
            Some(config.namespace.clone()),
            None,
        );
        let edge_anchor = match config.edge {
            Edge::Top => Anchor::TOP,
            Edge::Bottom => Anchor::BOTTOM,
        };
        // Anchor to one edge plus both sides: width 0 spans the full output.
        layer.set_anchor(edge_anchor | Anchor::LEFT | Anchor::RIGHT);
        layer.set_size(0, config.height);
        layer.set_exclusive_zone(config.height as i32);
        layer.set_keyboard_interactivity(KeyboardInteractivity::None);
        layer.commit();

        let pool = SlotPool::new((1920 * config.height * 4) as usize, &shm).expect("slot pool");

        let wanted = ExtForeignToplevelListV1::interface().name;
        let toplevels_present = globals
            .contents()
            .with_list(|gs| gs.iter().any(|g| g.interface.as_str() == wanted));
        let toplevel_list = ForeignToplevelList::new(&globals, &qh);

        Ok(LayerShellApp {
            event_loop,
            ping_source: Some(ping_source),
            queue,
            window,
            conn,
            event_queue,
            layer,
            shm,
            pool,
            toplevel_list,
            registry_state: RegistryState::new(&globals),
            seat_state: SeatState::new(&globals, &qh),
            output_state: OutputState::new(&globals, &qh),
            signal,
            height: config.height,
            toplevels_present,
            shutdown: Arc::new(Shutdown::new()),
        })
    }

    /// Whether the compositor advertises `ext-foreign-toplevel-list-v1`. A bar can
    /// degrade gracefully (e.g. show nothing) when it does not.
    pub fn toplevels_available(&self) -> bool {
        self.toplevels_present
    }

    /// The shared shutdown token, for converging other causes onto it.
    pub fn shutdown(&self) -> Arc<Shutdown> {
        self.shutdown.clone()
    }

    /// Run the bar. Spawns each D-Bus `Source` (own thread, reaching the UI through
    /// the proxy), folds the foreign-toplevel introspection onto this loop pushing
    /// via `on_toplevels`, installs the SIGINT supervisor, runs the loop, then
    /// converges shutdown and joins the workers.
    pub fn run<A>(
        mut self,
        app: A,
        on_toplevels: impl Fn(A, Vec<Toplevel>) + 'static,
        sources: Vec<Box<dyn Source<A>>>,
    ) -> Result<(), Box<dyn Error>>
    where
        A: ComponentHandle + 'static,
    {
        let loop_handle = self.event_loop.handle();

        // Spawn D-Bus sources before running; each reaches the UI via the proxy.
        let mut workers: Vec<JoinHandle<()>> = Vec::new();
        for source in sources {
            workers.push(source.spawn(app.as_weak(), self.shutdown.clone()));
        }

        // The folded introspection push: upgrade the component on the loop thread
        // and call its setter.
        let weak = app.as_weak();
        let push_toplevels: Box<dyn Fn(Vec<Toplevel>)> = Box::new(move |list| {
            if let Some(a) = weak.upgrade() {
                on_toplevels(a, list);
            }
        });

        let mut state = State {
            registry_state: self.registry_state,
            seat_state: self.seat_state,
            output_state: self.output_state,
            shm: self.shm,
            pool: self.pool,
            layer: self.layer,
            toplevel_list: self.toplevel_list,
            window: self.window.clone(),
            push_toplevels,
            signal: self.signal.clone(),
            pointer: None,
            width: 0,
            height: self.height,
            first_configure: true,
            frame_count: 0,
            trace: std::env::var_os("SHELL_RUNTIME_TRACE").is_some(),
        };

        // Drain the proxy queue when pinged: run worker-posted closures on the loop.
        let ping_source = self.ping_source.take().expect("ping source consumed once");
        loop_handle
            .insert_source(ping_source, {
                let queue = self.queue.clone();
                move |_, _, _state: &mut State| loop {
                    let job = queue.lock().unwrap().pop_front();
                    match job {
                        Some(f) => f(),
                        None => break,
                    }
                }
            })
            .map_err(|e| format!("insert ping source: {e:?}"))?;

        if self.toplevels_present {
            // Drain the initial burst so the first push reflects reality.
            self.event_queue.roundtrip(&mut state)?;
        }
        state.push_summary(None);

        WaylandSource::new(self.conn, self.event_queue)
            .insert(loop_handle)
            .map_err(|e| format!("insert wayland source: {e:?}"))?;

        let supervisor = signals::spawn_sigint(self.shutdown.clone());
        self.event_loop
            .run(None, &mut state, |_state| {})
            .map_err(|e| format!("run loop: {e}"))?;

        // Window-close path already triggered this; idempotent.
        self.shutdown.trigger();
        signals::stop(supervisor);
        for worker in workers {
            let _ = worker.join();
        }
        // Keep the app alive across the whole loop; drop it here.
        drop(app);
        Ok(())
    }
}
