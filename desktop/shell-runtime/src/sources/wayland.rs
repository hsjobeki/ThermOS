use std::error::Error;
use std::sync::Arc;
use std::thread::JoinHandle;

use slint::ComponentHandle;
use smithay_client_toolkit::{
    delegate_foreign_toplevel_list, delegate_registry,
    foreign_toplevel_list::{ForeignToplevelList, ForeignToplevelListHandler},
    reexports::{
        calloop::{self, EventLoop},
        calloop_wayland_source::WaylandSource,
        client::{globals::registry_queue_init, Connection, Proxy, QueueHandle},
        protocols::ext::foreign_toplevel_list::v1::client::{
            ext_foreign_toplevel_handle_v1::ExtForeignToplevelHandleV1,
            ext_foreign_toplevel_list_v1::ExtForeignToplevelListV1,
        },
    },
    registry::{ProvidesRegistryState, RegistryState},
    registry_handlers,
};

use crate::shutdown::Shutdown;
use crate::source::{guarded, Source};
use crate::ui::apply_ui;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Toplevel {
    pub title: String,
    pub app_id: String,
    pub identifier: String,
}

impl Toplevel {
    /// Return a label for the toplevel in the following order:
    /// - title
    /// - app_id
    /// - identifier
    pub fn label(&self) -> &str {
        if !self.title.is_empty() {
            &self.title
        } else if !self.app_id.is_empty() {
            &self.app_id
        } else {
            &self.identifier
        }
    }
}

pub struct WaylandToplevelSource<T: ComponentHandle + 'static> {
    apply: Arc<dyn Fn(T, Vec<Toplevel>) + Send + Sync>,
}

impl<T: ComponentHandle + 'static> WaylandToplevelSource<T> {
    pub fn new(apply: impl Fn(T, Vec<Toplevel>) + Send + Sync + 'static) -> Self {
        WaylandToplevelSource {
            apply: Arc::new(apply),
        }
    }
}

impl<T: ComponentHandle + 'static> Source<T> for WaylandToplevelSource<T> {
    fn spawn(self: Box<Self>, ui: slint::Weak<T>, shutdown: Arc<Shutdown>) -> JoinHandle<()> {
        let apply = self.apply.clone();
        let push: Push = Arc::new(move |list: Vec<Toplevel>| {
            let apply = apply.clone();
            apply_ui(&ui, move |app| apply(app, list));
        });

        let (ping, ping_source) = calloop::ping::make_ping().expect("make wayland ping");
        shutdown.register(Box::new(move || ping.ping()));

        std::thread::Builder::new()
            .name("wayland".into())
            .spawn(move || {
                guarded(shutdown, || {
                    if let Err(e) = run(push, ping_source) {
                        eprintln!("[wayland] error: {e}");
                    }
                    eprintln!("[wayland] loop exited");
                });
            })
            .expect("spawn wayland source")
    }
}

type Push = Arc<dyn Fn(Vec<Toplevel>) + Send + Sync>;

struct State {
    registry_state: RegistryState,
    toplevel_list: ForeignToplevelList,
    push: Push,
}

impl State {
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
        (self.push)(list);
    }
}

impl ProvidesRegistryState for State {
    fn registry(&mut self) -> &mut RegistryState {
        &mut self.registry_state
    }
    registry_handlers! {}
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
        handle: ExtForeignToplevelHandleV1,
    ) {
        self.push_summary(Some(&handle));
    }
}

delegate_foreign_toplevel_list!(State);
delegate_registry!(State);

fn run(push: Push, ping_source: calloop::ping::PingSource) -> Result<(), Box<dyn Error>> {
    let conn = Connection::connect_to_env()?;
    let (globals, mut event_queue) = registry_queue_init::<State>(&conn)?;
    let qh = event_queue.handle();

    // Startup guard: only wlroots/cosmic-comp advertise this; GNOME/Mutter do not.
    let wanted = ExtForeignToplevelListV1::interface().name;
    let present = globals
        .contents()
        .with_list(|gs| gs.iter().any(|g| g.interface.as_str() == wanted));

    let registry_state = RegistryState::new(&globals);
    let toplevel_list = ForeignToplevelList::new(&globals, &qh);
    let mut state = State {
        registry_state,
        toplevel_list,
        push,
    };

    if present {
        event_queue.roundtrip(&mut state)?;
    } else {
        eprintln!(
            "[wayland] ext-foreign-toplevel-list-v1 not advertised (run under wlroots/cosmic-comp)"
        );
    }
    // Make sure UI is initialized with the current state.
    state.push_summary(None);

    let mut event_loop: EventLoop<State> = EventLoop::try_new()?;
    let handle = event_loop.handle();
    let loop_signal = event_loop.get_signal();

    handle
        .insert_source(ping_source, move |_, _, _state| {
            loop_signal.stop();
        })
        .map_err(|e| format!("insert ping source: {e:?}"))?;

    WaylandSource::new(conn, event_queue)
        .insert(handle)
        .map_err(|e| format!("insert wayland source: {e:?}"))?;

    event_loop.run(None, &mut state, |_state| {})?;
    Ok(())
}
