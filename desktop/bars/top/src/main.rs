// top (Tier 1): an always-on top layer-shell bar. It shows a clock (a local
// timer), the ThermOS update status (from the daemon), and a shutdown action
// (logind). Each fact has its own authority and its own Source; the bar caches
// nothing and shares nothing with the dock. Killing the dock cannot touch this
// process; a restart re-subscribes and rebuilds from the authorities.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use futures_util::StreamExt;
use shell_runtime::{apply_ui, DbusShutdown, DbusSource, Edge, LayerConfig, LayerShellApp, Source};
use tokio::sync::mpsc;

slint::include_modules!();

#[zbus::proxy(
    interface = "org.thermos.Daemon1",
    default_service = "org.thermos.Daemon1",
    default_path = "/org/thermos/Daemon1"
)]
trait Daemon {
    #[zbus(property)]
    fn update_state(&self) -> zbus::Result<String>;
}

#[zbus::proxy(
    interface = "org.freedesktop.login1.Manager",
    default_service = "org.freedesktop.login1",
    default_path = "/org/freedesktop/login1"
)]
trait Logind {
    fn power_off(&self, interactive: bool) -> zbus::Result<()>;
    fn reboot(&self, interactive: bool) -> zbus::Result<()>;
}

enum Command {
    Shutdown,
}

fn now_hms() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let (h, m, s) = ((secs / 3600) % 24, (secs / 60) % 60, secs % 60);
    format!("{h:02}:{m:02}:{s:02} UTC")
}

/// Subscribe to the daemon's UpdateState. Degrades gracefully (shows
/// "unavailable") if the daemon is absent: a missing authority disables only its
/// own label, never the rest of the bar.
async fn daemon_body(ui: slint::Weak<App>, shutdown: DbusShutdown) {
    let conn = match zbus::connection::Builder::system() {
        Ok(b) => match b.build().await {
            Ok(c) => c,
            Err(e) => {
                eprintln!("[top] system bus connect failed: {e}");
                apply_ui(&ui, |app| {
                    app.set_update_text("update: no system bus".into())
                });
                shutdown.notified().await;
                return;
            }
        },
        Err(e) => {
            eprintln!("[top] system bus builder failed: {e}");
            shutdown.notified().await;
            return;
        }
    };
    let proxy = match DaemonProxy::new(&conn).await {
        Ok(p) => p,
        Err(e) => {
            eprintln!("[top] daemon proxy failed: {e}");
            apply_ui(&ui, |app| app.set_update_text("update: unavailable".into()));
            shutdown.notified().await;
            return;
        }
    };
    match proxy.update_state().await {
        Ok(state) => {
            eprintln!("[top] update state: {state}");
            apply_ui(&ui, move |app| {
                app.set_update_text(format!("update: {state}").as_str().into())
            });
        }
        Err(e) => {
            eprintln!("[top] read UpdateState failed: {e}");
            apply_ui(&ui, |app| app.set_update_text("update: unavailable".into()));
        }
    }
    let mut changes = proxy.receive_update_state_changed().await;
    loop {
        tokio::select! {
            biased;
            _ = shutdown.notified() => break,
            change = changes.next() => {
                if let Some(c) = change {
                    if let Ok(state) = c.get().await {
                        apply_ui(&ui, move |app| {
                            app.set_update_text(format!("update: {state}").as_str().into())
                        });
                    }
                }
            }
        }
    }
}

/// Owns the logind connection and performs power actions on request. The button
/// handler (UI thread) only sends a Command; the privileged call runs here.
async fn logind_body(
    ui: slint::Weak<App>,
    shutdown: DbusShutdown,
    mut commands: mpsc::UnboundedReceiver<Command>,
) {
    let conn = match zbus::connection::Builder::system() {
        Ok(b) => match b.build().await {
            Ok(c) => c,
            Err(e) => {
                eprintln!("[top] logind: system bus connect failed: {e}");
                shutdown.notified().await;
                return;
            }
        },
        Err(e) => {
            eprintln!("[top] logind: system bus builder failed: {e}");
            shutdown.notified().await;
            return;
        }
    };
    let proxy = match LogindProxy::new(&conn).await {
        Ok(p) => {
            eprintln!("[top] logind ready");
            p
        }
        Err(e) => {
            eprintln!("[top] logind proxy failed: {e}");
            shutdown.notified().await;
            return;
        }
    };
    let _ = &ui;
    loop {
        tokio::select! {
            biased;
            _ = shutdown.notified() => break,
            cmd = commands.recv() => match cmd {
                Some(Command::Shutdown) => {
                    eprintln!("[top] shutdown requested -> logind PowerOff");
                    if let Err(e) = proxy.power_off(false).await {
                        eprintln!("[top] PowerOff failed: {e}");
                    }
                }
                None => {}
            }
        }
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let bar = LayerShellApp::new(LayerConfig {
        namespace: "thermos-top".into(),
        edge: Edge::Top,
        height: 32,
    })?;

    let app = App::new()?;

    // Local clock: a UI-thread timer ticking every second. It fires from the
    // backend's per-frame update_timers_and_animations, so it keeps updating as
    // long as this process's loop runs (the fault-isolation liveness signal).
    let clock = slint::Timer::default();
    clock.start(slint::TimerMode::Repeated, Duration::from_secs(1), {
        let weak = app.as_weak();
        move || {
            if let Some(a) = weak.upgrade() {
                let t = now_hms();
                eprintln!("[top] clock {t}");
                a.set_clock_text(t.as_str().into());
            }
        }
    });

    let (tx, rx) = mpsc::unbounded_channel::<Command>();
    app.on_request_shutdown(move || {
        let _ = tx.send(Command::Shutdown);
    });

    let sources: Vec<Box<dyn Source<App>>> = vec![
        Box::new(DbusSource::new(daemon_body)),
        Box::new(DbusSource::new(move |ui, sd| logind_body(ui, sd, rx))),
    ];

    eprintln!("[top] entering layer-shell loop");
    // The top bar shows no app list; the folded toplevel source is a no-op here.
    bar.run(app, |_app, _list| {}, sources)?;
    eprintln!("[top] clean exit");
    Ok(())
}
