import { ArrowClockwise, CaretLeft, CaretRight, ClockCounterClockwise, CloudSlash, PushPin, PushPinSlash, SignIn, WarningCircle } from "@phosphor-icons/react";
import { memo, useEffect, useMemo, useRef, useState, type CSSProperties } from "react";
import { clampPercent, formatDateTime, formatResetDate, formatResetTime, quotaTier } from "../lib/format";
import { copy, normalizeLanguage } from "../lib/i18n";
import type { Language, LimitWindow, ProviderSnapshot, WidgetPreferences } from "../types";
import { ProviderMark } from "./ProviderMark";

interface Props {
  snapshot: ProviderSnapshot;
  preferences: WidgetPreferences;
  providerCount: number;
  onPrevious: () => void;
  onNext: () => void;
  onTogglePin: () => void;
  onLock: () => void;
  onLanguage: () => void;
  onDrag: () => void;
  onHover: (hovered: boolean) => void;
  onRefresh?: () => void;
  isConsuming?: boolean;
  notice?: string | null;
  initialShowCreditTip?: boolean;
}

function StatusIcon({ status, expired = false }: { status: ProviderSnapshot["status"]; expired?: boolean }) {
  if (status === "signed_out") return <SignIn weight="duotone" />;
  if (status === "stale" || expired) return <ClockCounterClockwise weight="duotone" />;
  if (status === "unavailable") return <CloudSlash weight="duotone" />;
  return <WarningCircle weight="duotone" />;
}

function localizedBackendMessage(message: string | null, language: Language): string | null {
  if (!message) return null;
  if (language === "en") return message;
  const normalized = message.toLowerCase();
  if (normalized.includes("sign in") || normalized.includes("login")) return "Codex 登录已失效，请重新登录。";
  if (normalized.includes("rate limited")) return "请求过于频繁，将稍后自动重试。";
  if (normalized.includes("network")) return "网络不可用，将自动重试。";
  if (normalized.includes("format")) return "额度响应格式已变化。";
  if (normalized.includes("missing the 5h")) return "额度响应缺少 5 小时窗口。";
  if (normalized.includes("refresh is already running")) return "额度正在刷新，请稍候。";
  return message;
}

export const QuotaCard = memo(function QuotaCard({
  snapshot,
  preferences,
  providerCount,
  onPrevious,
  onNext,
  onTogglePin: _onTogglePin,
  onLock,
  onLanguage,
  onDrag,
  onHover,
  onRefresh,
  isConsuming = false,
  notice = null,
  initialShowCreditTip = false,
}: Props) {
  const [showCreditTip, setShowCreditTip] = useState(initialShowCreditTip);
  const language = normalizeLanguage(preferences.language);
  const t = copy[language];
  const windows = snapshot.limitWindows?.filter((window) => window.isAvailable) ?? [];
  const fiveHour = windows.find((window) => window.kind === "rollingFiveHour") ?? (snapshot.shortWindow ? legacyWindow(snapshot.shortWindow, "rollingFiveHour") : null);
  const weeklyWindow = windows.find((window) => window.kind === "weekly") ?? (snapshot.weeklyWindow ? legacyWindow(snapshot.weeklyWindow, "weekly") : null);
  const primaryWindow = fiveHour ?? weeklyWindow;
  const primary = primaryWindow ? clampPercent(primaryWindow.remainingPercent) : null;
  const weekly = weeklyWindow ? clampPercent(weeklyWindow.remainingPercent) : null;
  const primaryLabel = fiveHour ? "5-hour remaining" : "Weekly remaining";
  const dualLimits = Boolean(fiveHour && weeklyWindow);
  const staleAge = Date.now() - new Date(snapshot.updatedAt).getTime();
  const staleExpired = snapshot.status === "stale" && staleAge > 30 * 60_000;
  const available = snapshot.status === "ok" || (snapshot.status === "stale" && !staleExpired);
  const tier = quotaTier(primary);
  const indicatorState = isConsuming ? "active" : snapshot.status === "ok" ? "ok" : snapshot.status === "stale" ? "stale" : "error";
  const indicatorLabel = isConsuming
    ? t.active
    : snapshot.status === "ok"
      ? t.dataSynced
      : snapshot.status === "stale"
        ? t.dataStale
        : snapshot.status === "signed_out"
          ? t.notSignedIn
          : t.unavailableStatus;
  const message = localizedBackendMessage(snapshot.message, language);
  const dialStyle = { "--quota-angle": `${(primary ?? 0) * 3.6}deg` } as CSSProperties;
  const creditExpirations = useMemo(() => (snapshot.resetCreditExpiresAt ?? []).map((value, index) => {
    return t.creditItem(index, formatDateTime(value, language));
  }), [language, snapshot.resetCreditExpiresAt, t]);

  return (
    <main
      className={`quota-card quota-card--${snapshot.status} quota-card--${tier}`}
      onMouseEnter={() => onHover(true)}
      onMouseLeave={() => onHover(false)}
      onMouseDown={(event) => { if (event.button === 0) void onDrag(); }}
    >
      <div className="glass-refraction" aria-hidden="true" />
      <span className="sr-only" aria-live="polite">{available && primary !== null ? t.availableLabel(primary) : message}</span>
      {notice ? <p className="operation-notice" role="status">{notice}</p> : null}
      <header className="card-header">
        <div className="brand-lockup">
          <ProviderMark />
          <div>
            <p className="eyebrow">{snapshot.displayName}</p>
            <p className="updated">{snapshot.plan ?? t.accountFallback}</p>
          </div>
        </div>
        {!preferences.locked ? (
          <nav className="card-actions" aria-label={t.controls} onMouseDown={(event) => event.stopPropagation()}>
            {providerCount > 1 ? <button onClick={onPrevious} aria-label={t.servicePrevious}><CaretLeft /></button> : null}
            <span className={`usage-indicator usage-indicator--${indicatorState}`} role="status" aria-label={indicatorLabel} title={indicatorLabel}><i /></span>
            <button className="language-button" onClick={onLanguage} aria-label={t.switchLanguage} title={t.switchLanguage}>{language === "en" ? "中" : "EN"}</button>
            <button onClick={onLock} aria-label={preferences.alwaysOnTop ? t.pinOff : t.pinOn} title={preferences.alwaysOnTop ? t.pinOff : t.pinOn}>
              {preferences.alwaysOnTop ? <PushPin /> : <PushPinSlash />}
            </button>
            {providerCount > 1 ? <button onClick={onNext} aria-label={t.serviceNext}><CaretRight /></button> : null}
          </nav>
        ) : null}
      </header>

      {available && primary !== null ? (
        <>
          <section className="primary-panel" aria-label={t.availableLabel(primary)}>
            <div className="quota-dial" style={dialStyle}>
              <div className="quota-dial__face">
                <div className="primary-metric"><span>{primary}</span><small>%</small></div>
                <p>{primaryLabel}</p>
              </div>
            </div>
            <div className="primary-detail">
              <p className="detail-label">{t.nextReset}</p>
              <strong>{formatResetTime(primaryWindow?.resetAt ?? null, new Date(), language)}</strong>
              <span>{indicatorLabel}</span>
            </div>
          </section>
          <div className="sr-only" role="progressbar" aria-label={t.availableLabel(primary)} aria-valuemin={0} aria-valuemax={100} aria-valuenow={primary} />
          <footer className="card-footer">
            <div className="weekly-metric metric-cell">
              <p>{dualLimits ? t.weeklyRemaining : t.nextReset}</p>
              <strong>{dualLimits ? weekly ?? "--" : formatResetTime(primaryWindow?.resetAt ?? null, new Date(), language)}<small>{dualLimits && weekly !== null ? "%" : ""}</small></strong>
              <span>{dualLimits ? formatResetDate(weeklyWindow?.resetAt ?? null, language) : snapshot.currentModel ?? "模型待识别"}</span>
            </div>
            <div className="metric-divider" aria-hidden="true" />
            <div className="credit-metric metric-cell">
              <p>{snapshot.resetCredits === null ? t.resetCreditUnknown : t.resetCredits(snapshot.resetCredits)}</p>
              <div className="reset-credit-row" onMouseDown={(event) => event.stopPropagation()}>
                <strong>{snapshot.resetCredits ?? "--"}</strong>
                {snapshot.resetCredits !== null && snapshot.resetCredits > 0 ? (
                  <button type="button" className="reset-credit-button" onClick={() => setShowCreditTip((value) => !value)} aria-expanded={showCreditTip} aria-label={t.view}>{t.view}</button>
                ) : null}
              </div>
              {showCreditTip ? (
                <div className="reset-credit-tip" role="status" onMouseDown={(event) => event.stopPropagation()}>
                  {creditExpirations.length > 0 ? creditExpirations.map((item) => <p key={item}>{item}</p>) : <p>{t.noCreditExpiration}</p>}
                </div>
              ) : null}
            </div>
          </footer>
        </>
      ) : (
        <section className="error-state" aria-live="polite">
          <div className="status-icon" aria-hidden="true"><StatusIcon status={snapshot.status} expired={staleExpired} /></div>
          <strong>{snapshot.status === "signed_out" ? t.signedInRequired : staleExpired ? t.staleExpired : t.temporarilyUnavailable}</strong>
          <p>{message ?? t.errorUnavailable}</p>
          {snapshot.status === "stale" ? (
            <button type="button" className="error-refresh-button" onMouseDown={(event) => event.stopPropagation()} onClick={onRefresh} disabled={!onRefresh} aria-label={t.refreshQuota}>
              <ArrowClockwise />
              <span>{t.refresh}</span>
            </button>
          ) : null}
        </section>
      )}
    </main>
  );
});

export const QuotaOrb = memo(function QuotaOrb({ snapshot, onDrag, onHover, language = "zh-CN" }: Pick<Props, "snapshot" | "onDrag" | "onHover"> & { language?: Language }) {
  const [idle, setIdle] = useState(false);
  const idleTimer = useRef<number | null>(null);
  const activeLanguage = normalizeLanguage(language);
  const t = copy[activeLanguage];
  const fiveHour = snapshot.limitWindows?.find((window) => window.kind === "rollingFiveHour") ?? null;
  const weekly = snapshot.limitWindows?.find((window) => window.kind === "weekly") ?? null;
  const primary = clampPercent((fiveHour ?? weekly)?.remainingPercent ?? snapshot.shortWindow?.remainingPercent ?? snapshot.weeklyWindow?.remainingPercent ?? 0);
  const tier = quotaTier(primary);
  const available = snapshot.status === "ok" && (fiveHour ?? weekly ?? snapshot.shortWindow ?? snapshot.weeklyWindow) !== null;
  const dialStyle = { "--quota-angle": `${(primary ?? 0) * 3.6}deg` } as CSSProperties;

  useEffect(() => {
    idleTimer.current = window.setTimeout(() => setIdle(true), 2000);
    return () => {
      if (idleTimer.current !== null) window.clearTimeout(idleTimer.current);
    };
  }, []);

  const handleMouseEnter = () => {
    if (idleTimer.current !== null) window.clearTimeout(idleTimer.current);
    setIdle(false);
    onHover(true);
  };

  return (
    <main
      className={`quota-orb quota-card--${snapshot.status} quota-card--${tier}${idle ? " quota-orb--idle" : ""}`}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={() => onHover(false)}
      onMouseDown={(event) => { if (event.button === 0) void onDrag(); }}
      aria-label={available ? t.availableLabel(primary) : localizedBackendMessage(snapshot.message, activeLanguage) ?? t.unavailableStatus}
    >
      <div className="glass-refraction" aria-hidden="true" />
      {available ? (
        <section className="orb-dial" style={dialStyle}>
          <div className="orb-dial__face">
            <div className="orb-metric"><span>{primary}</span><small>%</small></div>
            <span className="orb-label">{fiveHour ? "5H" : "W"}</span>
          </div>
          <i className="orb-status" aria-hidden="true" />
        </section>
      ) : (
        <section className="orb-unavailable">
          <StatusIcon status={snapshot.status} />
        </section>
      )}
    </main>
  );
});

function legacyWindow(window: { remainingPercent: number; resetsAt: string | null; windowSeconds: number }, kind: LimitWindow["kind"]): LimitWindow {
  return { id: `legacy-${kind}`, kind, durationSeconds: window.windowSeconds, usedPercent: 100 - window.remainingPercent, remainingPercent: window.remainingPercent, resetAt: window.resetsAt, source: "legacy-snapshot", sourceLabel: null, updatedAt: "", isAvailable: true };
}
