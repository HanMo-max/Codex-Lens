mod codex;
mod models;

use std::{
    ffi::{c_char, CString},
    fs,
    sync::{Mutex, OnceLock},
    time::Duration,
};

use models::{LimitWindow, ProviderSnapshot};
use tauri::{
    menu::{CheckMenuItem, Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager,
};
use tauri_plugin_autostart::{MacosLauncher, ManagerExt};

const BACKGROUND_REFRESH_INTERVAL: Duration = Duration::from_secs(60);

#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn codex_lens_reload_widget_timelines();
    fn codex_lens_write_widget_snapshot(bytes: *const u8, length: usize) -> i32;
    fn codex_lens_start_power_observer(callback: extern "C" fn());
    fn codex_lens_log_refresh_event(message: *const c_char);
}

#[cfg(target_os = "macos")]
fn reload_widget_timelines() {
    // The symbol is implemented by the small Swift bridge compiled in build.rs.
    unsafe { codex_lens_reload_widget_timelines() };
}

#[cfg(not(target_os = "macos"))]
fn reload_widget_timelines() {}

#[cfg(target_os = "macos")]
static POWER_OBSERVER_APP: OnceLock<AppHandle> = OnceLock::new();

struct AppState {
    client: reqwest::Client,
    refresh_task: Mutex<Option<tauri::async_runtime::JoinHandle<()>>>,
}

#[cfg(target_os = "macos")]
fn log_refresh_event(message: &str) {
    if let Ok(message) = CString::new(message) {
        unsafe { codex_lens_log_refresh_event(message.as_ptr()) };
    }
}

#[cfg(not(target_os = "macos"))]
fn log_refresh_event(message: &str) {
    eprintln!("{message}");
}

#[cfg(target_os = "macos")]
extern "C" fn handle_system_wake() {
    if let Some(app) = POWER_OBSERVER_APP.get() {
        request_refresh(app, "system-wake");
    }
}

#[cfg(target_os = "macos")]
fn start_power_observer(app: &AppHandle) {
    let _ = POWER_OBSERVER_APP.set(app.clone());
    unsafe { codex_lens_start_power_observer(handle_system_wake) };
}

#[cfg(not(target_os = "macos"))]
fn start_power_observer(_app: &AppHandle) {}

const WIDGET_SNAPSHOT_SCHEMA_VERSION: u32 = 1;

/// Display-only document exchanged through the App Group. It intentionally
/// omits credentials, account IDs, raw API data, and reset-credit metadata.
#[derive(serde::Serialize, serde::Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
struct WidgetSnapshot {
    schema_version: u32,
    active_model: Option<String>,
    limit_windows: Vec<LimitWindow>,
    updated_at: String,
    source: String,
    is_stale: bool,
    display_name: String,
    plan: Option<String>,
    status: String,
    message: Option<String>,
}

impl WidgetSnapshot {
    fn from_provider(snapshot: &ProviderSnapshot) -> Self {
        Self {
            schema_version: WIDGET_SNAPSHOT_SCHEMA_VERSION,
            active_model: snapshot.current_model.clone(),
            limit_windows: snapshot.limit_windows.clone(),
            updated_at: snapshot.updated_at.clone(),
            source: "codexDesktopUsage".into(),
            is_stale: snapshot.status == "stale",
            display_name: snapshot.display_name.clone(),
            plan: snapshot.plan.clone(),
            status: snapshot.status.clone(),
            message: snapshot.message.clone(),
        }
    }
}

#[cfg(test)]
fn snapshot_for_publishing(next: &WidgetSnapshot, previous: Option<WidgetSnapshot>) -> WidgetSnapshot {
    if next.status == "ok" {
        return next.clone();
    }

    previous
        // LimitWindow is the authoritative snapshot shape. Keep legacy fields
        // only for installed 0.1.x widgets; do not let their later removal
        // discard a valid normalized cache during a transient refresh failure.
        .filter(|snapshot| {
            !snapshot.limit_windows.is_empty()
        })
        .map(|mut snapshot| {
            snapshot.status = "stale".into();
            snapshot.is_stale = true;
            snapshot.message = next.message.clone();
            snapshot
        })
        .unwrap_or_else(|| next.clone())
}

fn persist_widget_snapshot(snapshot: &ProviderSnapshot) {
    let next = WidgetSnapshot::from_provider(snapshot);
    if next.status != "ok" {
        // Do not overwrite the shared document on a transient failure. The
        // Widget's last-known-good copy remains readable and becomes stale
        // from its original timestamp instead of masquerading as live data.
        log_refresh_event("widget-snapshot retained last-known-good after refresh failure");
        return;
    }
    // The Swift bridge retains the most recent valid shared document. Rust
    // deliberately never falls back to a private Extension path: that would
    // falsely claim WidgetKit synchronization when App Group is unavailable.
    let Ok(serialized) = serde_json::to_vec(&next) else {
        log_refresh_event("widget-snapshot serialization failed");
        return;
    };
    #[cfg(target_os = "macos")]
    let result = unsafe { codex_lens_write_widget_snapshot(serialized.as_ptr(), serialized.len()) };
    #[cfg(not(target_os = "macos"))]
    let result = 1;
    if result == 0 {
        reload_widget_timelines();
    } else {
        log_refresh_event(&format!("widget-snapshot publish unavailable code={result}"));
    }
}

fn build_http_client() -> reqwest::Client {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(12))
        .connect_timeout(Duration::from_secs(8))
        // Never retain a socket across refreshes. This avoids stale pre-sleep
        // keep-alive connections without rebuilding the client in the refresh
        // task, where macOS proxy discovery itself could block recovery.
        .pool_max_idle_per_host(0)
        .redirect(reqwest::redirect::Policy::none())
        .user_agent("CodexLens/0.1")
        .build()
        .expect("static HTTP client configuration must be valid")
}

async fn fetch_and_publish(app: &AppHandle, reason: &'static str) {
    let should_log_success = reason != "periodic";
    if should_log_success {
        log_refresh_event(&format!("refresh-start reason={reason}"));
    }

    let Some(state) = app.try_state::<AppState>() else {
        log_refresh_event(&format!("refresh-rejected reason={reason} missing=state"));
        return;
    };
    let client = state.client.clone();
    // The client keeps no idle sockets, so this request cannot inherit a
    // pre-sleep connection. The outer deadline also covers response parsing.
    let snapshot = match tokio::time::timeout(
        Duration::from_secs(20),
        codex::fetch_snapshot(&client),
    )
    .await
    {
        Ok(snapshot) => snapshot,
        Err(_) => ProviderSnapshot::failure(
            "unavailable",
            "Refresh timed out. It will retry automatically.",
        ),
    };
    let status = snapshot.status.clone();
    persist_widget_snapshot(&snapshot);
    if should_log_success || status != "ok" {
        log_refresh_event(&format!("refresh-finish reason={reason} status={status}"));
    }
}

fn should_skip_refresh(reason: &str, current_task_is_running: bool) -> bool {
    reason == "periodic" && current_task_is_running
}

fn request_refresh(app: &AppHandle, reason: &'static str) {
    let Some(state) = app.try_state::<AppState>() else {
        return;
    };
    let Ok(mut current_task) = state.refresh_task.lock() else {
        log_refresh_event("refresh-rejected reason=poisoned-task-state");
        return;
    };

    let current_task_is_running = current_task
        .as_ref()
        .is_some_and(|task| !task.inner().is_finished());
    if should_skip_refresh(reason, current_task_is_running) {
        // Periodic work is best-effort. It must never interrupt a startup,
        // manual, reopen, or wake recovery that is already in progress.
        return;
    }

    // Wake and manual refreshes must never queue behind a request that was
    // suspended with the machine. Cancel the old task; dropping it also drops
    // its sockets and response-body future.
    if let Some(previous) = current_task.take() {
        if !previous.inner().is_finished() {
            previous.abort();
            log_refresh_event(&format!("refresh-cancelled-previous reason={reason}"));
        }
    }

    let app = app.clone();
    *current_task = Some(tauri::async_runtime::spawn(async move {
        fetch_and_publish(&app, reason).await;
    }));
}

fn start_background_sync(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        request_refresh(&app, "startup");
        let first_tick = tokio::time::Instant::now() + BACKGROUND_REFRESH_INTERVAL;
        let mut interval = tokio::time::interval_at(first_tick, BACKGROUND_REFRESH_INTERVAL);
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            interval.tick().await;
            request_refresh(&app, "periodic");
        }
    });
}

fn setup_tray(app: &tauri::App) -> tauri::Result<()> {
    let refresh = MenuItem::with_id(app, "refresh", "Refresh now", true, None::<&str>)?;
    let autostart_enabled = app.autolaunch().is_enabled().unwrap_or(false);
    let autostart = CheckMenuItem::with_id(
        app,
        "autostart",
        "Start at login",
        true,
        autostart_enabled,
        None::<&str>,
    )?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&refresh, &autostart, &quit])?;
    let mut builder = TrayIconBuilder::with_id("main")
        .menu(&menu)
        .tooltip("Codex Lens");
    if let Some(icon) = app.default_window_icon() {
        builder = builder.icon(icon.clone());
    }

    let autostart_menu = autostart.clone();
    builder
        .on_menu_event(move |app, event| match event.id.as_ref() {
            "refresh" => request_refresh(app, "manual-menu"),
            "autostart" => {
                let manager = app.autolaunch();
                let enabled = manager.is_enabled().unwrap_or(false);
                let result = if enabled {
                    manager.disable()
                } else {
                    manager.enable()
                };
                match result {
                    Ok(()) => {
                        let _ = autostart_menu.set_checked(!enabled);
                    }
                    Err(_) => eprintln!("autostart update failed"),
                }
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;
    Ok(())
}

pub fn run() {
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            // Reopening the app or activating its URL refreshes data without
            // constructing the retired floating WebView.
            request_refresh(app, "single-instance");
        }))
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            None,
        ))
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            let data_dir = app.path().app_config_dir()?;
            let background_sync_marker = data_dir.join("background-sync-at-login-v2");
            if !background_sync_marker.exists() {
                let autolaunch = app.autolaunch();
                if autolaunch.is_enabled().unwrap_or(false) || autolaunch.enable().is_ok() {
                    let _ = fs::create_dir_all(&data_dir);
                    let _ = fs::write(&background_sync_marker, b"enabled");
                }
            }

            app.manage(AppState {
                client: build_http_client(),
                refresh_task: Mutex::new(None),
            });

            start_power_observer(app.handle());
            start_background_sync(app.handle().clone());
            if setup_tray(app).is_err() {
                eprintln!("tray setup failed");
            }
            Ok(())
        })
        .on_tray_icon_event(|app, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                request_refresh(app, "tray-click");
            }
        })
        .build(tauri::generate_context!())
        .expect("failed to build Codex Lens");

    app.run(|app_handle, event| match event {
        tauri::RunEvent::Resumed => request_refresh(app_handle, "runtime-resumed"),
        #[cfg(target_os = "macos")]
        tauri::RunEvent::Opened { .. } | tauri::RunEvent::Reopen { .. } => {
            request_refresh(app_handle, "app-reopen")
        }
        _ => {}
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::UsageWindow;

    #[test]
    fn failed_refresh_keeps_last_values_and_marks_them_stale() {
        let mut previous = WidgetSnapshot::from_provider(&ProviderSnapshot {
            provider: "codex".into(),
            display_name: "CODEX".into(),
            plan: Some("PLUS".into()),
            current_model: Some("gpt-test".into()),
            limit_windows: Vec::new(),
            short_window: Some(UsageWindow {
                remaining_percent: 64.0,
                resets_at: None,
                window_seconds: 18_000,
            }),
            weekly_window: None,
            reset_credits: None,
            reset_credit_expires_at: Vec::new(),
            updated_at: "2026-07-15T08:00:00Z".into(),
            status: "ok".into(),
            message: None,
        });
        previous.limit_windows.push(LimitWindow {
            id: "weekly".into(), kind: "weekly".into(), duration_seconds: 604_800,
            used_percent: 36.0, remaining_percent: 64.0, reset_at: None,
            source: "test".into(), source_label: None, updated_at: previous.updated_at.clone(), is_available: true,
        });
        let failure = WidgetSnapshot::from_provider(&ProviderSnapshot::failure("unavailable", "network unavailable"));

        let published = snapshot_for_publishing(&failure, Some(previous));

        assert_eq!(published.status, "stale");
        assert_eq!(published.limit_windows[0].remaining_percent, 64.0);
        assert_eq!(published.updated_at, "2026-07-15T08:00:00Z");
        assert_eq!(published.message.as_deref(), Some("network unavailable"));
    }

    #[test]
    fn widget_document_has_required_safe_fields() {
        let snapshot = WidgetSnapshot::from_provider(&ProviderSnapshot::failure("unavailable", "safe"));
        let raw = serde_json::to_value(snapshot).unwrap();
        for key in ["schemaVersion", "activeModel", "limitWindows", "updatedAt", "source", "isStale"] {
            assert!(raw.get(key).is_some(), "missing {key}");
        }
        assert!(raw.get("accessToken").is_none());
        assert!(raw.get("accountId").is_none());
    }

    #[test]
    fn periodic_refresh_never_preempts_a_user_or_wake_refresh() {
        assert!(should_skip_refresh("periodic", true));
        assert!(!should_skip_refresh("periodic", false));
        assert!(!should_skip_refresh("manual-menu", true));
        assert!(!should_skip_refresh("system-wake", true));
        assert!(!should_skip_refresh("app-reopen", true));
    }
}
