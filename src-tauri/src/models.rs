use serde::{Deserialize, Serialize};

pub fn current_timestamp() -> String {
    // WidgetKit's default ISO8601DateFormatter accepts whole-second RFC 3339
    // timestamps, but rejects Chrono's default fractional-second output.
    chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageWindow {
    pub remaining_percent: f64,
    pub resets_at: Option<String>,
    pub window_seconds: u64,
}

/// A normalized quota window. The UI only consumes this model, never raw API data.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LimitWindow {
    pub id: String,
    pub kind: String,
    pub duration_seconds: u64,
    pub used_percent: f64,
    pub remaining_percent: f64,
    pub reset_at: Option<String>,
    pub source: String,
    pub source_label: Option<String>,
    pub updated_at: String,
    pub is_available: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderSnapshot {
    pub provider: String,
    pub display_name: String,
    pub plan: Option<String>,
    /// The model configured for the local Codex client, when it can be read safely.
    pub current_model: Option<String>,
    #[serde(default)]
    pub limit_windows: Vec<LimitWindow>,
    // Kept for one release of snapshot compatibility with older installed widgets.
    pub short_window: Option<UsageWindow>,
    pub weekly_window: Option<UsageWindow>,
    pub reset_credits: Option<u64>,
    pub reset_credit_expires_at: Vec<String>,
    pub updated_at: String,
    pub status: String,
    pub message: Option<String>,
}

impl ProviderSnapshot {
    pub fn failure(status: &str, message: &str) -> Self {
        Self {
            provider: "codex".into(),
            display_name: "CODEX".into(),
            plan: None,
            current_model: None,
            limit_windows: Vec::new(),
            short_window: None,
            weekly_window: None,
            reset_credits: None,
            reset_credit_expires_at: Vec::new(),
            updated_at: current_timestamp(),
            status: status.into(),
            message: Some(message.into()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn widget_timestamp_uses_whole_seconds() {
        let timestamp = current_timestamp();
        assert!(!timestamp.contains('.'));
        assert!(chrono::DateTime::parse_from_rfc3339(&timestamp).is_ok());
    }
}
