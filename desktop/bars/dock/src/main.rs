// dock (Tier 1): an always-on bottom layer-shell bar listing running apps. Its one
// authority is the compositor's foreign-toplevel list, folded onto the bar's own
// calloop. It caches nothing: a restart re-subscribes and rebuilds the list from
// the compositor, so correctness after restart is by construction.

use shell_runtime::{Edge, LayerConfig, LayerShellApp, Source, Toplevel};

slint::include_modules!();

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let bar = LayerShellApp::new(LayerConfig {
        namespace: "thermos-dock".into(),
        edge: Edge::Bottom,
        height: 40,
    })?;
    if !bar.toplevels_available() {
        eprintln!("[dock] compositor does not advertise ext-foreign-toplevel-list-v1");
    }

    let app = App::new()?;
    // No D-Bus sources: the dock observes only the compositor.
    let sources: Vec<Box<dyn Source<App>>> = Vec::new();

    eprintln!("[dock] entering layer-shell loop");
    bar.run(
        app,
        |app: App, list: Vec<Toplevel>| {
            eprintln!("[dock] apps update: {} running", list.len());
            let text = if list.is_empty() {
                "(no running apps)".to_string()
            } else {
                let labels: Vec<String> =
                    list.iter().take(8).map(|t| t.label().to_string()).collect();
                format!("{}: {}", list.len(), labels.join("  |  "))
            };
            app.set_apps_text(text.as_str().into());
        },
        sources,
    )?;
    eprintln!("[dock] clean exit");
    Ok(())
}
