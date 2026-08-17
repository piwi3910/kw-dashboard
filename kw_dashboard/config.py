"""Configuration. Every tunable lives here; nothing is hardcoded at a call site.

Touch scaling is not configured here: under Qt eglfs, libinput reads the
digitiser's real axis range from the kernel and scales it itself, so no
calibration knob is needed (do not re-add one).
"""
from __future__ import annotations
import tomllib
from dataclasses import dataclass, replace


@dataclass(frozen=True)
class Config:
    width: int = 1280
    height: int = 720
    fps: int = 30
    vt: int = 2

    rotate_seconds: int = 15
    touch_pause_seconds: int = 60
    idle_reset_seconds: int = 120

    prometheus_url: str = "http://10.43.125.146:9090"
    alertmanager_url: str = "http://10.43.225.33:9093"
    kube_url: str = "https://127.0.0.1:6443"
    loki_url: str = "http://10.43.88.188:3100"
    loki_enabled: bool = False

    token_path: str = "/etc/kw-dashboard/token"
    ca_path: str = "/etc/kw-dashboard/ca.crt"

    poll_fast_seconds: float = 5.0
    poll_slow_seconds: float = 20.0
    http_timeout_seconds: float = 8.0
    stale_after_seconds: float = 45.0

    log_tail_lines: int = 200
    log_ring_size: int = 2000


def load_config(path: str | None) -> Config:
    """Load config, falling back to defaults for anything unspecified."""
    cfg = Config()
    if not path:
        return cfg
    try:
        with open(path, "rb") as f:
            data = tomllib.load(f)
    except (FileNotFoundError, PermissionError):
        return cfg

    known = set(Config.__dataclass_fields__)
    cfg = replace(cfg, **{k: v for k, v in data.items() if k in known})
    return cfg
