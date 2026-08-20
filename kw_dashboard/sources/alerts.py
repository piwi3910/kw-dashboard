"""Alertmanager client. Severity ranking drives screen pre-emption (spec 7)."""

from __future__ import annotations
from dataclasses import dataclass
from datetime import datetime, timezone
from .http import get_json

SEVERITY_ORDER = {"critical": 0, "warning": 1, "info": 2}


@dataclass(frozen=True)
class Alert:
    name: str
    severity: str
    summary: str
    starts_at: datetime | None


def parse_alerts(payload: list) -> list[Alert]:
    out = []
    for a in payload or []:
        if a.get("status", {}).get("state") != "active":
            continue  # suppressed/silenced must not seize the screen
        labels = a.get("labels", {})
        ts = a.get("startsAt")
        try:
            parsed = datetime.fromisoformat(ts.replace("Z", "+00:00")) if ts else None
        except (ValueError, AttributeError):
            parsed = None
        out.append(
            Alert(
                name=labels.get("alertname", "unknown"),
                severity=labels.get("severity", "info"),
                summary=a.get("annotations", {}).get("summary", ""),
                starts_at=parsed,
            )
        )
    return out


def rank_alerts(alerts: list[Alert]) -> list[Alert]:
    epoch = datetime.fromtimestamp(0, tz=timezone.utc)
    return sorted(
        alerts,
        key=lambda a: (
            SEVERITY_ORDER.get(a.severity, 99),
            -(a.starts_at or epoch).timestamp(),
        ),
    )


def has_critical(alerts: list[Alert]) -> bool:
    return any(a.severity == "critical" for a in alerts)


class AlertsClient:
    def __init__(self, base_url: str, timeout: float = 8.0):
        self.base = base_url.rstrip("/")
        self.timeout = timeout

    def active(self) -> list[Alert]:
        payload = get_json(f"{self.base}/api/v2/alerts", timeout=self.timeout)
        return rank_alerts(parse_alerts(payload))
