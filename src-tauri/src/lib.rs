mod codex;
mod models;
mod status_bar;

use std::{
    fs,
    sync::{Mutex, OnceLock},
    time::Duration,
};
#[cfg(target_os = "macos")]
use std::ffi::{c_char, c_void, CString};

use models::{LimitWindow, ProviderSnapshot};
use status_bar::{
    format_status_bar, merge_status_bar_snapshot, DataStatus, StatusBarPresentation,
};
use tauri::{
    menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem},
    tray::TrayIconBuilder,
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
    fn codex_lens_status_popover_configure(
        status_item: *mut c_void,
        callback: extern "C" fn(i32),
    );
    fn codex_lens_status_popover_update(
        title: *const c_char,
        percentage: *const c_char,
        window_name: *const c_char,
        progress: f64,
        model_name: *const c_char,
        reset_time: *const c_char,
        status_text: *const c_char,
        status_code: i32,
        start_at_login: i32,
    );
    fn codex_lens_status_popover_set_start_at_login(enabled: i32);
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
#[cfg(target_os = "macos")]
static STATUS_POPOVER_APP: OnceLock<AppHandle> = OnceLock::new();

struct AppState {
    client: reqwest::Client,
    refresh_task: Mutex<Option<tauri::async_runtime::JoinHandle<()>>>,
    tray_display: Mutex<TrayDisplayState>,
    tray_menu: Mutex<Option<TrayMenuItems>>,
}

struct TrayDisplayState {
    last_good: Option<ProviderSnapshot>,
    status: DataStatus,
}

impl Default for TrayDisplayState {
    fn default() -> Self {
        Self {
            last_good: None,
            status: DataStatus::Unavailable,
        }
    }
}

#[derive(Clone)]
struct TrayMenuItems {
    quota: MenuItem<tauri::Wry>,
    window: MenuItem<tauri::Wry>,
    model: MenuItem<tauri::Wry>,
    reset: MenuItem<tauri::Wry>,
    status: MenuItem<tauri::Wry>,
    refresh: MenuItem<tauri::Wry>,
    autostart: CheckMenuItem<tauri::Wry>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StatusPopoverAction {
    Refresh,
    ToggleStartAtLogin,
    Quit,
}

fn status_popover_action_from_code(code: i32) -> Option<StatusPopoverAction> {
    match code {
        0 => Some(StatusPopoverAction::Refresh),
        1 => Some(StatusPopoverAction::ToggleStartAtLogin),
        2 => Some(StatusPopoverAction::Quit),
        _ => None,
    }
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

fn update_start_at_login_controls(app: &AppHandle, enabled: bool) {
    if let Some(state) = app.try_state::<AppState>() {
        if let Some(menu) = state
            .tray_menu
            .lock()
            .ok()
            .and_then(|items| items.clone())
        {
            let _ = menu.autostart.set_checked(enabled);
        }
    }

    #[cfg(target_os = "macos")]
    unsafe {
        codex_lens_status_popover_set_start_at_login(i32::from(enabled));
    }
}

fn toggle_start_at_login(app: &AppHandle) {
    let manager = app.autolaunch();
    let enabled = manager.is_enabled().unwrap_or(false);
    let result = if enabled {
        manager.disable()
    } else {
        manager.enable()
    };
    match result {
        Ok(()) => update_start_at_login_controls(app, !enabled),
        Err(_) => {
            update_start_at_login_controls(
                app,
                app.autolaunch().is_enabled().unwrap_or(enabled),
            );
            eprintln!("autostart update failed");
        }
    }
}

#[cfg(target_os = "macos")]
extern "C" fn handle_status_popover_action(code: i32) {
    let Some(app) = STATUS_POPOVER_APP.get() else {
        return;
    };
    match status_popover_action_from_code(code) {
        Some(StatusPopoverAction::Refresh) => request_refresh(app, "manual-popover"),
        Some(StatusPopoverAction::ToggleStartAtLogin) => toggle_start_at_login(app),
        Some(StatusPopoverAction::Quit) => app.exit(0),
        None => {}
    }
}

#[cfg(target_os = "macos")]
fn configure_status_popover(
    tray: &tauri::tray::TrayIcon<tauri::Wry>,
    app: &AppHandle,
) -> tauri::Result<()> {
    let _ = STATUS_POPOVER_APP.set(app.clone());
    let status_item = tray.with_inner_tray_icon(|inner| {
        inner
            .ns_status_item()
            .map(|status_item| (&**status_item as *const _) as usize)
    })?;
    if let Some(status_item) = status_item {
        unsafe {
            codex_lens_status_popover_configure(
                status_item as *mut c_void,
                handle_status_popover_action,
            );
        }
    }
    Ok(())
}

#[cfg(target_os = "macos")]
fn update_status_popover(
    presentation: &StatusBarPresentation,
    start_at_login: bool,
) {
    fn bridge_string(value: &str) -> CString {
        CString::new(value.replace('\0', " ")).expect("sanitized status text must be C-compatible")
    }

    let title = bridge_string(&presentation.title);
    let percentage = bridge_string(&presentation.popover_percentage_text);
    let window_name = bridge_string(&presentation.popover_window_text);
    let model_name = bridge_string(&presentation.popover_model_text);
    let reset_time = bridge_string(&presentation.popover_reset_text);
    let status_text = bridge_string(&presentation.popover_status_text);

    unsafe {
        codex_lens_status_popover_update(
            title.as_ptr(),
            percentage.as_ptr(),
            window_name.as_ptr(),
            presentation.popover_progress,
            model_name.as_ptr(),
            reset_time.as_ptr(),
            status_text.as_ptr(),
            presentation.popover_status_code,
            i32::from(start_at_login),
        );
    }
}

#[cfg(not(target_os = "macos"))]
fn update_status_popover(
    _presentation: &StatusBarPresentation,
    _start_at_login: bool,
) {
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

fn update_tray_ui(app: &AppHandle, presentation: &StatusBarPresentation) {
    if let Some(tray) = app.tray_by_id("main") {
        let _ = tray.set_title(Some(presentation.title.as_str()));
        let _ = tray.set_tooltip(Some(presentation.tooltip.as_str()));
    }
    let start_at_login = app.autolaunch().is_enabled().unwrap_or(false);
    update_status_popover(presentation, start_at_login);

    let Some(state) = app.try_state::<AppState>() else {
        return;
    };
    // Clone the handles before dispatching their updates to the main thread.
    // Holding this mutex while a menu callback runs could otherwise deadlock.
    let menu = state
        .tray_menu
        .lock()
        .ok()
        .and_then(|items| items.clone());
    let Some(menu) = menu else {
        return;
    };
    let _ = menu.quota.set_text(&presentation.quota_text);
    let _ = menu.window.set_text(&presentation.window_text);
    let _ = menu.model.set_text(&presentation.model_text);
    let _ = menu.reset.set_text(&presentation.reset_text);
    let _ = menu.status.set_text(&presentation.status_text);
    let _ = menu.refresh.set_text(&presentation.refresh_text);
}

fn mark_tray_refreshing(app: &AppHandle) {
    let Some(state) = app.try_state::<AppState>() else {
        return;
    };
    let presentation = {
        let Ok(mut display) = state.tray_display.lock() else {
            return;
        };
        display.status = DataStatus::Refreshing;
        format_status_bar(display.last_good.as_ref(), display.status)
    };
    update_tray_ui(app, &presentation);
}

fn apply_tray_snapshot(app: &AppHandle, snapshot: &ProviderSnapshot) {
    let Some(state) = app.try_state::<AppState>() else {
        return;
    };
    let presentation = {
        let Ok(mut display) = state.tray_display.lock() else {
            return;
        };
        let (last_good, status) =
            merge_status_bar_snapshot(display.last_good.take(), snapshot);
        display.last_good = last_good;
        display.status = status;
        format_status_bar(display.last_good.as_ref(), display.status)
    };
    update_tray_ui(app, &presentation);
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
    apply_tray_snapshot(app, &snapshot);
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
    if reason != "periodic" {
        // Update the native UI before taking the task lock. Menu callbacks run
        // on the main thread, so no UI dispatch should wait while holding it.
        mark_tray_refreshing(app);
    }
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

fn refresh_reason_for_tray_interaction(menu_item_id: Option<&str>) -> Option<&'static str> {
    match menu_item_id {
        Some("refresh") => Some("manual-menu"),
        None | Some(_) => None,
    }
}

fn setup_tray(app: &tauri::App) -> tauri::Result<()> {
    let initial = format_status_bar(None, DataStatus::Unavailable);
    let quota = MenuItem::with_id(app, "quota-status", &initial.quota_text, false, None::<&str>)?;
    let window =
        MenuItem::with_id(app, "window-status", &initial.window_text, false, None::<&str>)?;
    let model = MenuItem::with_id(app, "model-status", &initial.model_text, false, None::<&str>)?;
    let reset = MenuItem::with_id(app, "reset-status", &initial.reset_text, false, None::<&str>)?;
    let status =
        MenuItem::with_id(app, "sync-status", &initial.status_text, false, None::<&str>)?;
    let status_separator = PredefinedMenuItem::separator(app)?;
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
    let action_separator = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(
        app,
        &[
            &quota,
            &window,
            &model,
            &reset,
            &status,
            &status_separator,
            &refresh,
            &autostart,
            &action_separator,
            &quit,
        ],
    )?;
    let mut builder = TrayIconBuilder::with_id("main")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .title(&initial.title)
        .tooltip(&initial.tooltip);
    if let Some(icon) = app.default_window_icon() {
        builder = builder.icon(icon.clone());
    }

    let tray = builder
        .on_menu_event(move |app, event| {
            let menu_id = event.id.as_ref();
            if let Some(reason) = refresh_reason_for_tray_interaction(Some(menu_id)) {
                request_refresh(app, reason);
                return;
            }

            match menu_id {
                "autostart" => toggle_start_at_login(app),
                "quit" => app.exit(0),
                _ => {}
            }
        })
        .build(app)?;
    if let Some(state) = app.try_state::<AppState>() {
        if let Ok(mut items) = state.tray_menu.lock() {
            *items = Some(TrayMenuItems {
                quota,
                window,
                model,
                reset,
                status,
                refresh,
                autostart,
            });
        }
    }
    #[cfg(target_os = "macos")]
    configure_status_popover(&tray, app.handle())?;
    update_tray_ui(app.handle(), &initial);
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
                tray_display: Mutex::new(TrayDisplayState::default()),
                tray_menu: Mutex::new(None),
            });

            start_power_observer(app.handle());
            if setup_tray(app).is_err() {
                eprintln!("tray setup failed");
            }
            start_background_sync(app.handle().clone());
            Ok(())
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

    #[test]
    fn opening_tray_menu_does_not_refresh_but_refresh_item_does() {
        assert_eq!(refresh_reason_for_tray_interaction(None), None);
        assert_eq!(
            refresh_reason_for_tray_interaction(Some("quota-status")),
            None
        );
        assert_eq!(
            refresh_reason_for_tray_interaction(Some("refresh")),
            Some("manual-menu")
        );
    }

    #[test]
    fn native_popover_action_codes_map_without_touching_quota_logic() {
        assert_eq!(
            status_popover_action_from_code(0),
            Some(StatusPopoverAction::Refresh)
        );
        assert_eq!(
            status_popover_action_from_code(1),
            Some(StatusPopoverAction::ToggleStartAtLogin)
        );
        assert_eq!(
            status_popover_action_from_code(2),
            Some(StatusPopoverAction::Quit)
        );
        assert_eq!(status_popover_action_from_code(99), None);
    }
}
