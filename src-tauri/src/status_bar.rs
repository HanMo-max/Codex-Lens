use chrono::{DateTime, Local};

use crate::models::{LimitWindow, ProviderSnapshot};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum DataStatus {
    Synced,
    Stale,
    Unavailable,
    Refreshing,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct StatusBarPresentation {
    pub title: String,
    pub tooltip: String,
    pub quota_text: String,
    pub window_text: String,
    pub model_text: String,
    pub reset_text: String,
    pub status_text: String,
    pub refresh_text: String,
    pub popover_percentage_text: String,
    pub popover_window_text: String,
    pub popover_progress: f64,
    pub popover_model_text: String,
    pub popover_reset_text: String,
    pub popover_status_text: String,
    pub popover_status_code: i32,
}

impl DataStatus {
    pub(crate) fn bridge_code(self) -> i32 {
        match self {
            Self::Synced => 0,
            Self::Stale => 1,
            Self::Unavailable => 2,
            Self::Refreshing => 3,
        }
    }
}

pub(crate) fn select_status_window(windows: &[LimitWindow]) -> Option<&LimitWindow> {
    fn usable(window: &&LimitWindow) -> bool {
        window.is_available && window.remaining_percent.is_finite()
    }

    windows
        .iter()
        .filter(usable)
        .find(|window| window.kind == "rollingFiveHour")

}

pub(crate) fn merge_status_bar_snapshot(
    previous: Option<ProviderSnapshot>,
    next: &ProviderSnapshot,
) -> (Option<ProviderSnapshot>, DataStatus) {
    if next.status == "ok" && select_status_window(&next.limit_windows).is_some() {
        return (Some(next.clone()), DataStatus::Synced);
    }

    if previous.is_some() {
        (previous, DataStatus::Stale)
    } else {
        (None, DataStatus::Unavailable)
    }
}

fn percent_text(window: &LimitWindow) -> String {
    format!("{:.0}%", window.remaining_percent.clamp(0.0, 100.0))
}

fn window_name(window: &LimitWindow) -> &'static str {
    match window.kind.as_str() {
        "rollingFiveHour" => "5-hour quota",
        "weekly" => "Weekly quota",
        _ => "Unknown quota",
    }
}

fn compact_single_line(value: &str) -> Option<String> {
    let compact = value.split_whitespace().collect::<Vec<_>>().join(" ");
    (!compact.is_empty()).then_some(compact)
}

fn reset_countdown(value: &str, now: DateTime<chrono::Utc>) -> Option<String> {
    let reset = DateTime::parse_from_rfc3339(value).ok()?;
    let seconds = reset.signed_duration_since(now).num_seconds();
    if seconds <= 0 {
        return Some("等待重置".into());
    }
    if seconds < 60 {
        return Some("即将重置".into());
    }
    let minutes = (seconds + 59) / 60;
    let hours = minutes / 60;
    let remainder = minutes % 60;
    Some(match (hours, remainder) {
        (0, minutes) => format!("{minutes}分钟后重置"),
        (hours, 0) => format!("{hours}小时后重置"),
        (hours, minutes) => format!("{hours}小时{minutes}分钟后重置"),
    })
}

fn reset_time_text(value: &str) -> Option<String> {
    DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|date| {
            date.with_timezone(&Local)
                .format("%Y-%m-%d %H:%M %Z")
                .to_string()
        })
        .or_else(|| compact_single_line(value))
}

pub(crate) fn format_status_bar(
    snapshot: Option<&ProviderSnapshot>,
    requested_status: DataStatus,
) -> StatusBarPresentation {
    let window = snapshot.and_then(|snapshot| select_status_window(&snapshot.limit_windows));
    let status = match (requested_status, window.is_some()) {
        (DataStatus::Refreshing, _) => DataStatus::Refreshing,
        (_, false) => DataStatus::Unavailable,
        (status, true) => status,
    };
    let percent = window.map(percent_text);
    let reset_short = window
        .and_then(|window| window.reset_at.as_deref())
        .and_then(|value| reset_countdown(value, chrono::Utc::now()));
    let mut title = match (percent.as_deref(), reset_short) {
        (Some(value), Some(reset)) => format!("{value}  ·  {reset}"),
        (Some(value), None) => value.to_owned(),
        (None, _) => "5 小时 —".into(),
    };
    if status == DataStatus::Stale {
        title.push_str(" !");
    }
    let status_label = match status {
        DataStatus::Synced => "Synced",
        DataStatus::Stale => "Data stale",
        DataStatus::Unavailable => "Unavailable",
        DataStatus::Refreshing => "Refreshing",
    };
    let quota = percent.unwrap_or_else(|| "—".into());
    let window_label = window.map(window_name).unwrap_or("Not available");
    let model = snapshot
        .and_then(|snapshot| snapshot.current_model.as_deref())
        .and_then(|model| compact_single_line(model))
        .unwrap_or_else(|| "Not available".into());
    let reset = window
        .and_then(|window| window.reset_at.as_deref())
        .and_then(reset_time_text)
        .unwrap_or_else(|| "Not available".into());
    let progress = window
        .map(|window| (window.remaining_percent / 100.0).clamp(0.0, 1.0))
        .unwrap_or(0.0);
    let tooltip = if window.is_some() {
        format!("Codex Lens — 剩余 {quota} · 已用 {:.0}% ({window_label}) — {status_label}", (1.0 - progress) * 100.0)
    } else {
        format!("Codex Lens — {status_label}")
    };

    StatusBarPresentation {
        title,
        tooltip,
        quota_text: format!("Quota remaining: {quota}"),
        window_text: format!("Window: {window_label}"),
        model_text: format!("Model: {model}"),
        reset_text: format!("Next reset: {reset}"),
        status_text: format!("Status: {status_label}"),
        refresh_text: if status == DataStatus::Refreshing {
            "Refreshing".into()
        } else {
            "Refresh now".into()
        },
        popover_percentage_text: quota,
        popover_window_text: window_label.into(),
        popover_progress: progress,
        popover_model_text: model,
        popover_reset_text: reset,
        popover_status_text: status_label.into(),
        popover_status_code: status.bridge_code(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn window(kind: &str, remaining_percent: f64, is_available: bool) -> LimitWindow {
        LimitWindow {
            id: kind.into(),
            kind: kind.into(),
            duration_seconds: 0,
            used_percent: 100.0 - remaining_percent,
            remaining_percent,
            reset_at: Some("2026-08-01T02:00:00Z".into()),
            source: "test".into(),
            source_label: None,
            updated_at: "2026-07-31T02:00:00Z".into(),
            is_available,
        }
    }

    fn snapshot(windows: Vec<LimitWindow>) -> ProviderSnapshot {
        ProviderSnapshot {
            provider: "codex".into(),
            display_name: "CODEX".into(),
            plan: Some("PLUS".into()),
            current_model: Some("gpt-test".into()),
            limit_windows: windows,
            short_window: None,
            weekly_window: None,
            reset_credits: None,
            reset_credit_expires_at: Vec::new(),
            updated_at: "2026-07-31T02:00:00Z".into(),
            status: "ok".into(),
            message: None,
        }
    }

    #[test]
    fn five_hour_window_is_preferred_over_weekly() {
        let snapshot = snapshot(vec![
            window("weekly", 41.0, true),
            window("rollingFiveHour", 92.0, true),
        ]);

        let selected = select_status_window(&snapshot.limit_windows).unwrap();
        let presentation = format_status_bar(Some(&snapshot), DataStatus::Synced);

        assert_eq!(selected.kind, "rollingFiveHour");
        assert!(presentation.title.starts_with("92%  ·  "));
        assert!(presentation.title.ends_with("重置"));
        assert_eq!(presentation.window_text, "Window: 5-hour quota");
        assert_eq!(presentation.popover_percentage_text, "92%");
        assert_eq!(presentation.popover_window_text, "5-hour quota");
        assert_eq!(presentation.popover_progress, 0.92);
    }

    #[test]
    fn weekly_window_is_not_shown_when_five_hour_is_missing() {
        let snapshot = snapshot(vec![window("weekly", 41.0, true)]);

        let presentation = format_status_bar(Some(&snapshot), DataStatus::Synced);
        assert!(select_status_window(&snapshot.limit_windows).is_none());
        assert_eq!(presentation.title, "5 小时 —");
        assert_eq!(presentation.status_text, "Status: Unavailable");
    }

    #[test]
    fn unavailable_five_hour_window_does_not_fall_back_to_weekly() {
        let snapshot = snapshot(vec![
            window("rollingFiveHour", 92.0, false),
            window("weekly", 41.0, true),
        ]);

        assert!(select_status_window(&snapshot.limit_windows).is_none());
    }

    #[test]
    fn no_quota_data_formats_as_unavailable() {
        let presentation = format_status_bar(None, DataStatus::Unavailable);

        assert_eq!(presentation.title, "5 小时 —");
        assert_eq!(presentation.quota_text, "Quota remaining: —");
        assert_eq!(presentation.status_text, "Status: Unavailable");
        assert_eq!(presentation.popover_percentage_text, "—");
        assert_eq!(presentation.popover_progress, 0.0);
        assert_eq!(presentation.popover_status_code, 2);
    }

    #[test]
    fn stale_data_keeps_the_percentage_and_marks_it_clearly() {
        let snapshot = snapshot(vec![window("rollingFiveHour", 92.0, true)]);

        let presentation = format_status_bar(Some(&snapshot), DataStatus::Stale);

        assert!(presentation.title.starts_with("92%  ·  "));
        assert!(presentation.title.ends_with("重置 !"));
        assert_eq!(presentation.quota_text, "Quota remaining: 92%");
        assert_eq!(presentation.status_text, "Status: Data stale");
        assert!(presentation.tooltip.contains("Data stale"));
        assert_eq!(presentation.popover_percentage_text, "92%");
        assert_eq!(presentation.popover_status_code, 1);
    }

    #[test]
    fn failed_refresh_retains_the_last_good_status_bar_snapshot() {
        let previous = snapshot(vec![window("rollingFiveHour", 64.0, true)]);
        let failure = ProviderSnapshot::failure("unavailable", "network unavailable");

        let (retained, status) = merge_status_bar_snapshot(Some(previous), &failure);
        let presentation = format_status_bar(retained.as_ref(), status);

        assert_eq!(status, DataStatus::Stale);
        assert!(presentation.title.starts_with("64%  ·  "));
        assert!(presentation.title.ends_with("重置 !"));
        assert_eq!(presentation.status_text, "Status: Data stale");
    }

    #[test]
    fn unknown_windows_are_not_presented_as_supported_quota() {
        let snapshot = snapshot(vec![window("unknown", 77.0, true)]);

        let presentation = format_status_bar(Some(&snapshot), DataStatus::Synced);

        assert!(select_status_window(&snapshot.limit_windows).is_none());
        assert_eq!(presentation.title, "5 小时 —");
        assert_eq!(presentation.status_text, "Status: Unavailable");
    }

    #[test]
    fn refreshing_keeps_existing_value_and_exposes_loading_state() {
        let snapshot = snapshot(vec![window("rollingFiveHour", 64.0, true)]);

        let presentation = format_status_bar(Some(&snapshot), DataStatus::Refreshing);

        assert!(presentation.title.starts_with("64%  ·  "));
        assert!(!presentation.title.contains('…'));
        assert!(presentation.title.ends_with("重置"));
        assert_eq!(presentation.popover_percentage_text, "64%");
        assert_eq!(presentation.popover_progress, 0.64);
        assert_eq!(presentation.popover_status_text, "Refreshing");
        assert_eq!(presentation.popover_status_code, 3);
    }

    #[test]
    fn countdown_handles_whole_hours_minutes_and_reset_boundary() {
        let now = DateTime::parse_from_rfc3339("2026-10-04T12:00:00Z").unwrap().with_timezone(&chrono::Utc);
        for (seconds, expected) in [
            (4 * 3600, "4小时后重置"),
            (3 * 3600 + 25 * 60, "3小时25分钟后重置"),
            (25 * 60, "25分钟后重置"),
            (60, "1分钟后重置"),
            (59, "即将重置"),
            (0, "等待重置"),
            (-60, "等待重置"),
        ] {
            let reset = (now + chrono::Duration::seconds(seconds)).to_rfc3339();
            assert_eq!(reset_countdown(&reset, now).as_deref(), Some(expected));
        }
        assert!(reset_countdown("not a timestamp", now).is_none());
        assert_eq!(reset_countdown("2026-10-04T23:25:00+08:00", now).as_deref(), Some("3小时25分钟后重置"));
    }

    #[test]
    fn popover_status_codes_are_stable_for_the_swift_bridge() {
        assert_eq!(DataStatus::Synced.bridge_code(), 0);
        assert_eq!(DataStatus::Stale.bridge_code(), 1);
        assert_eq!(DataStatus::Unavailable.bridge_code(), 2);
        assert_eq!(DataStatus::Refreshing.bridge_code(), 3);
    }
}
