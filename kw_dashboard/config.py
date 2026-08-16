"""Configuration. Every tunable lives here; nothing is hardcoded at a call site.

The touch calibration knobs exist unconditionally, even though the panel may
appear correct on first test. Cheap HDMI panels routinely report swapped,
inverted or offset axes, and firmware revisions differ between units. No
amount of clean code detects a miscalibrated digitiser.
"""
from __future__ import annotations
import tomllib
from dataclasses import dataclass, field, replace


@dataclass(frozen=True)
class TouchCalibration:
    x_min: int = 0
    x_max: int = 4095
    y_min: int = 0
    y_max: int = 4095
    swap_xy: bool = False
    invert_x: bool = False
    invert_y: bool = False

    def to_screen(self, raw_x: int, raw_y: int, w: int, h: int) -> tuple[int, int]:
        """Map a raw digitiser sample to a screen pixel."""
        def norm(v, lo, hi):
            if hi == lo:
                return 0.0
            return min(1.0, max(0.0, (v - lo) / (hi - lo)))

        nx = norm(raw_x, self.x_min, self.x_max)
        ny = norm(raw_y, self.y_min, self.y_max)
        if self.swap_xy:
            nx, ny = ny, nx
        if self.invert_x:
            nx = 1.0 - nx
        if self.invert_y:
            ny = 1.0 - ny
        return (min(w - 1, int(nx * w)), min(h - 1, int(ny * h)))


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
    ca_path: str = "/var/lib/rancher/k3s/server/tls/server-ca.crt"

    poll_fast_seconds: float = 5.0
    poll_slow_seconds: float = 20.0
    http_timeout_seconds: float = 8.0
    stale_after_seconds: float = 45.0

    log_tail_lines: int = 200
    log_ring_size: int = 2000

    touch: TouchCalibration = field(default_factory=TouchCalibration)


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

    touch_data = data.pop("touch", {})
    known = {f for f in Config.__dataclass_fields__ if f != "touch"}
    cfg = replace(cfg, **{k: v for k, v in data.items() if k in known})
    if touch_data:
        known_t = set(TouchCalibration.__dataclass_fields__)
        cfg = replace(cfg, touch=replace(
            cfg.touch, **{k: v for k, v in touch_data.items() if k in known_t}))
    return cfg
