// settings app

use futures_util::StreamExt;
use shell_runtime::{apply_ui, DbusShutdown, DbusSource, ShellRuntime};
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
    fn start_update(&self) -> zbus::Result<()>;
}

enum Command {
    StartUpdate,
}

async fn daemon_body(
    ui: slint::Weak<App>,
    shutdown: DbusShutdown,
    mut commands: mpsc::UnboundedReceiver<Command>,
) {
    let conn = match zbus::connection::Builder::system() {
        Ok(builder) => match builder.build().await {
            Ok(conn) => conn,
            Err(e) => {
                eprintln!("[settings] system bus connect failed: {e}");
                apply_ui(&ui, move |app| {
                    app.set_update_state(format!("error: {e}").as_str().into())
                });
                shutdown.notified().await;
                return;
            }
        },
        Err(e) => {
            eprintln!("[settings] system bus builder failed: {e}");
            shutdown.notified().await;
            return;
        }
    };

    let proxy = match DaemonProxy::new(&conn).await {
        Ok(p) => p,
        Err(e) => {
            eprintln!("[settings] daemon proxy failed: {e}");
            apply_ui(&ui, move |app| {
                app.set_update_state(format!("error: {e}").as_str().into())
            });
            shutdown.notified().await;
            return;
        }
    };

    match proxy.update_state().await {
        Ok(state) => {
            eprintln!("[settings] initial UpdateState = {state}");
            apply_ui(&ui, move |app| app.set_update_state(state.as_str().into()));
        }
        Err(e) => eprintln!("[settings] read UpdateState failed: {e}"),
    }

    let mut changes = proxy.receive_update_state_changed().await;
    loop {
        tokio::select! {
            biased;
            _ = shutdown.notified() => break,
            cmd = commands.recv() => match cmd {
                Some(Command::StartUpdate) => {
                    match proxy.start_update().await {
                        Ok(()) => {
                            eprintln!("[settings] StartUpdate authorized and invoked");
                            apply_ui(&ui, |app| app.set_last_action("update started".into()));
                        }
                        Err(e) => {
                            eprintln!("[settings] StartUpdate failed: {e}");
                            apply_ui(&ui, move |app| {
                                app.set_last_action(format!("denied: {e}").as_str().into())
                            });
                        }
                    }
                }
                None => {}
            },
            change = changes.next() => {
                if let Some(changed) = change {
                    if let Ok(state) = changed.get().await {
                        apply_ui(&ui, move |app| app.set_update_state(state.as_str().into()));
                    }
                }
            }
        }
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let app = App::new()?;
    let (tx, rx) = mpsc::unbounded_channel::<Command>();
    app.on_request_update(move || {
        let _ = tx.send(Command::StartUpdate);
    });

    let mut runtime = ShellRuntime::new(&app);
    runtime.add_source(Box::new(DbusSource::new(move |ui, shutdown| {
        daemon_body(ui, shutdown, rx)
    })));

    eprintln!("[settings] entering slint event loop");
    runtime.run(app)?;
    eprintln!("[settings] exit");
    Ok(())
}
