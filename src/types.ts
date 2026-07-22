export type ProviderId = "codex" | "claude";
export type SnapshotStatus = "ok" | "stale" | "loading" | "unavailable" | "signed_out";
export type Language = "zh-CN" | "en";

export interface UsageWindow {
  remainingPercent: number;
  resetsAt: string | null;
  windowSeconds: number;
}

export type LimitWindowKind = "rollingFiveHour" | "weekly" | "unknown";

export interface LimitWindow {
  id: string;
  kind: LimitWindowKind;
  durationSeconds: number;
  usedPercent: number;
  remainingPercent: number;
  resetAt: string | null;
  source: string;
  sourceLabel: string | null;
  updatedAt: string;
  isAvailable: boolean;
}

export interface ProviderSnapshot {
  provider: ProviderId;
  displayName: string;
  plan: string | null;
  currentModel?: string | null;
  /** Optional only while reading a snapshot written by Codex Lens 0.1.x. */
  limitWindows?: LimitWindow[];
  shortWindow: UsageWindow | null;
  weeklyWindow: UsageWindow | null;
  resetCredits: number | null;
  resetCreditExpiresAt?: string[];
  updatedAt: string;
  status: SnapshotStatus;
  message: string | null;
}

export interface WidgetPreferences {
  locked: boolean;
  alwaysOnTop: boolean;
  pinnedProvider: ProviderId | null;
  autoRotateSeconds: number;
  language: Language;
}
