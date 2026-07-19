// thermos-daemon (Phase 1b stub): the ThermOS-owned authority on the system bus.
//
// It owns `org.thermos.Daemon1` and exposes the full update-management interface
// clients code against: `UpdateState`, `UpdateProgress`, and the privileged,
// Polkit-gated `StartUpdate` / `ApplyUpdate`. The interface is the dependency, so
// it ships first; the method bodies are no-ops that grow real update logic later.
//
// Property change notification uses the standard properties idiom: clients
// observe `org.freedesktop.DBus.Properties.PropertiesChanged`. There is no
// separate `UpdateStateChanged` signal (DESKTOP_PLAN.md Section 4 lets us pick
// one; this is the idiomatic choice and the stub's state is constant `idle`).
//
// zbus runs on its default async-io backend (never the tokio feature); tokio here
// only drives `main` and the shutdown wait. The two reactors are independent.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use zbus::zvariant::{Type, Value};

const ACTION_START: &str = "org.thermos.daemon.start-update";
const ACTION_APPLY: &str = "org.thermos.daemon.apply-update";

// --- Polkit wire types -----------------------------------------------------

/// `PolicyKit1.Authority` Subject `(sa{sv})`. We identify the caller by its unique
/// system-bus name, which polkit resolves to a uid/pid it trusts (the kernel
/// reports it), so a client cannot spoof another's authorization.
#[derive(Serialize, Type)]
struct Subject<'a> {
    kind: String,
    details: HashMap<String, Value<'a>>,
}

/// `CheckAuthorization` result `(bba{ss})`.
#[derive(Deserialize, Type)]
struct AuthorizationResult {
    is_authorized: bool,
    is_challenge: bool,
    #[allow(dead_code)]
    details: HashMap<String, String>,
}

#[zbus::proxy(
    interface = "org.freedesktop.PolicyKit1.Authority",
    default_service = "org.freedesktop.PolicyKit1",
    default_path = "/org/freedesktop/PolicyKit1/Authority"
)]
trait PolicyKitAuthority {
    fn check_authorization(
        &self,
        subject: &Subject<'_>,
        action_id: &str,
        details: HashMap<&str, &str>,
        flags: u32,
        cancellation_id: &str,
    ) -> zbus::Result<AuthorizationResult>;
}

/// Check the caller's authorization for `action` via Polkit. Clients request; the
/// daemon acts only after Polkit says yes. `AllowUserInteraction` lets a desktop
/// session pop an auth dialog; headless callers are authorized by policy/rules or
/// rejected.
async fn authorize(conn: &zbus::Connection, caller: &str, action: &str) -> zbus::fdo::Result<()> {
    let authority = PolicyKitAuthorityProxy::new(conn)
        .await
        .map_err(|e| zbus::fdo::Error::Failed(format!("polkit unavailable: {e}")))?;
    let subject = Subject {
        kind: "system-bus-name".to_string(),
        details: HashMap::from([("name".to_string(), Value::from(caller))]),
    };
    const ALLOW_USER_INTERACTION: u32 = 1;
    let result = authority
        .check_authorization(&subject, action, HashMap::new(), ALLOW_USER_INTERACTION, "")
        .await
        .map_err(|e| zbus::fdo::Error::Failed(format!("polkit check failed: {e}")))?;
    if result.is_authorized {
        Ok(())
    } else if result.is_challenge {
        Err(zbus::fdo::Error::AccessDenied(format!(
            "authentication required for {action}"
        )))
    } else {
        Err(zbus::fdo::Error::AccessDenied(format!(
            "not authorized for {action}"
        )))
    }
}

// --- The interface ---------------------------------------------------------

struct Daemon;

#[zbus::interface(name = "org.thermos.Daemon1")]
impl Daemon {
    /// `idle | checking | downloading | applying | ready-to-reboot | failed`.
    /// Constant `idle` in the stub; real transitions emit `PropertiesChanged`.
    #[zbus(property)]
    fn update_state(&self) -> String {
        "idle".to_string()
    }

    /// 0-100; changes during `downloading` / `applying`. Constant 0 in the stub.
    #[zbus(property)]
    fn update_progress(&self) -> u32 {
        0
    }

    async fn start_update(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(connection)] conn: &zbus::Connection,
    ) -> zbus::fdo::Result<()> {
        let caller = header.sender().map(|s| s.to_string()).unwrap_or_default();
        authorize(conn, &caller, ACTION_START).await?;
        eprintln!("[thermos-daemon] StartUpdate authorized for {caller}; invoking (stub no-op)");
        Ok(())
    }

    async fn apply_update(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(connection)] conn: &zbus::Connection,
    ) -> zbus::fdo::Result<()> {
        let caller = header.sender().map(|s| s.to_string()).unwrap_or_default();
        authorize(conn, &caller, ACTION_APPLY).await?;
        eprintln!("[thermos-daemon] ApplyUpdate authorized for {caller}; invoking (stub no-op)");
        Ok(())
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let _conn = zbus::connection::Builder::system()?
        .name("org.thermos.Daemon1")?
        .serve_at("/org/thermos/Daemon1", Daemon)?
        .build()
        .await?;
    eprintln!("[thermos-daemon] owning org.thermos.Daemon1 on the system bus");

    // Run until systemd stops us (SIGTERM) or a console SIGINT.
    use tokio::signal::unix::{signal, SignalKind};
    let mut term = signal(SignalKind::terminate())?;
    let mut int = signal(SignalKind::interrupt())?;
    tokio::select! {
        _ = term.recv() => {}
        _ = int.recv() => {}
    }
    eprintln!("[thermos-daemon] shutting down");
    Ok(())
}
