# kw-dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native touch dashboard rendered directly to the 9" HDMI panel on `km01`, showing cluster health, live activity, alerts, and a generic namespace→pod→logs Kubernetes explorer.

**Architecture:** One Python process on the node under systemd. A collector thread polls Prometheus, Alertmanager and the k3s API on independent intervals and swaps an immutable snapshot under a lock; a pygame render thread on SDL2's KMSDRM backend draws from that snapshot and handles touch. No X11, no Wayland, no browser, no display server.

**Tech Stack:** Python 3.12, pygame 2.5.2 (apt `python3-pygame`), SDL2 2.30 KMSDRM backend, `urllib` from stdlib for HTTP, pytest for tests. All runtime deps are apt packages — no pip, no venv, no build step.

**Spec:** `docs/superpowers/specs/2026-08-16-kw-dashboard-design.md`

## Global Constraints

- **Resolution is exactly 1280x720.** Never 1920x1080. All layout constants derive from this.
- **Text legibility floor: 26 px** for glanceable views (pages 1, 2, 4). The log view is the single documented exception at ~20 px monospace.
- **Touch target minimum: 60 px row height** everywhere, including where text is small.
- **Read-only.** No mutating Kubernetes calls anywhere: no delete, scale, restart, cordon, patch. Only `GET`.
- **Runtime deps are apt-only:** `python3-pygame`, `libsdl2-2.0-0`, `fonts-dejavu-core`. Adding a pip dependency requires re-opening the spec.
- **No blocking I/O on the render thread.** Ever. All network calls live in the collector thread.
- **Service user is `piwi`** (already in groups `video`, `render`, `input`, `tty`).
- **Target node:** `km01` / `master-11` / `192.168.10.101`. It is cordoned; this does not run as a pod.
- **Endpoints:** Prometheus `10.43.125.146:9090`, Alertmanager `10.43.225.33:9093`, k3s API `127.0.0.1:6443`, Loki `10.43.88.188:3100` (optional).
- **Python version floor: 3.12** (what the node has).

---

## File Structure

```
kw_dashboard/
  __init__.py
  config.py            Config dataclass + TOML load; all tunables incl. touch calibration
  model.py             Immutable snapshot dataclasses
  sources/
    __init__.py
    http.py            Tiny urllib GET helper w/ timeout + bearer token
    prometheus.py      PromQL client + response parsing
    kube.py            k3s API client: nodes, namespaces, pods, events, logs
    alerts.py          Alertmanager client
  collector.py         Collector thread; independent intervals; staleness
  logstream.py         Log follow/pause state machine + bounded ring buffer
  nav.py               View stack + idle reset
  ui/
    __init__.py
    theme.py           Palette, fonts, size scale (derived via dataviz skill)
    widgets.py         arc gauge, sparkline, bar, list row, header, back button
    pages/
      __init__.py
      cluster.py       Page 1
      pulse.py         Page 2
      explore.py       Page 3 + namespace/pod detail views
      alerts.py        Page 4
      logs.py          Log view
      node.py          Node detail view
  app.py               pygame loop, VT setup, rotation, touch dispatch, render
  __main__.py          Entry point, arg parsing (--windowed, --screenshot)
tests/
  test_prometheus.py  test_kube.py  test_alerts.py  test_collector.py
  test_logstream.py   test_nav.py   test_config.py  test_explore_sort.py
  fixtures/           Recorded API JSON
deploy/
  rbac.yaml            ServiceAccount + view ClusterRoleBinding
  kw-dashboard.service systemd unit
  install.sh           Deploy over SSH
tools/
  probe_hardware.py    Task 1 hardware verification
```

---

## Task 1: Hardware probe — resolve the three blocking risks

Spec section 12 lists three risks that can invalidate all layout work. Resolve them before writing dashboard code. This task is a spike: its deliverable is a probe script plus recorded findings.

**Files:**
- Create: `tools/probe_hardware.py`
- Create: `docs/hardware-findings.md`

**Interfaces:**
- Consumes: nothing
- Produces: verified answers for (a) whether `piwi` can acquire DRM master unprivileged, (b) ILITEK touch axis orientation and range, (c) which VT is free. These feed `config.py` defaults in Task 2.

- [ ] **Step 1: Write the probe script**

```python
#!/usr/bin/env python3
"""Verify DRM master, touch input, and VT availability on km01. Spike tool."""
import os, sys, glob, subprocess

def check_vt():
    active = open("/sys/class/tty/console/active").read().split()
    print(f"console active on: {active}")
    used = subprocess.run(["fuser", "-v"] + glob.glob("/dev/tty[1-9]"),
                          capture_output=True, text=True)
    print(f"tty users:\n{used.stderr}")

def check_drm():
    os.environ["SDL_VIDEODRIVER"] = "kmsdrm"
    import pygame
    try:
        pygame.display.init()
        info = pygame.display.Info()
        print(f"DRM OK as uid={os.getuid()}: {info.current_w}x{info.current_h}")
        pygame.display.quit()
        return True
    except Exception as e:
        print(f"DRM FAILED as uid={os.getuid()}: {e}")
        return False

def check_touch():
    """Report raw touch events for 15s: min/max per axis to derive calibration."""
    import struct, select
    dev = "/dev/input/event5"
    EV_ABS, ABS_X, ABS_Y = 0x03, 0x00, 0x01
    fmt = "llHHi"; size = struct.calcsize(fmt)
    xs, ys = [], []
    print(f"Touch the screen corners for 15s... reading {dev}")
    with open(dev, "rb") as f:
        import time; end = time.time() + 15
        while time.time() < end:
            if select.select([f], [], [], 0.5)[0]:
                _, _, t, c, v = struct.unpack(fmt, f.read(size))
                if t == EV_ABS and c == ABS_X: xs.append(v)
                if t == EV_ABS and c == ABS_Y: ys.append(v)
    if xs and ys:
        print(f"ABS_X range: {min(xs)}..{max(xs)}")
        print(f"ABS_Y range: {min(ys)}..{max(ys)}")
    else:
        print("NO TOUCH EVENTS SEEN")

if __name__ == "__main__":
    check_vt(); check_drm(); check_touch()
```

- [ ] **Step 2: Run it on the node as `piwi`**

```bash
scp tools/probe_hardware.py piwi@192.168.10.101:/tmp/
ssh piwi@192.168.10.101 'sudo apt-get install -y python3-pygame fonts-dejavu-core && python3 /tmp/probe_hardware.py'
```

Expected: prints DRM result, touch ranges, VT usage. Note whether DRM succeeded unprivileged.

- [ ] **Step 3: If DRM failed as `piwi`, re-run under sudo to confirm the fallback**

```bash
ssh piwi@192.168.10.101 'sudo python3 /tmp/probe_hardware.py'
```

Record which of the two works. This decides `User=` in the systemd unit (Task 15).

- [ ] **Step 4: Record findings**

Write `docs/hardware-findings.md` with the actual observed values: DRM uid that works, ABS_X/ABS_Y ranges and whether axes are swapped or inverted relative to the 1280x720 display, and the chosen free VT. These become the defaults in Task 2.

- [ ] **Step 5: Commit**

```bash
git add tools/probe_hardware.py docs/hardware-findings.md
git commit -m "spike: probe DRM master, touch calibration, VT availability"
```

---

## Task 2: Config module

**Files:**
- Create: `kw_dashboard/__init__.py` (empty), `kw_dashboard/config.py`
- Test: `tests/test_config.py`

**Interfaces:**
- Consumes: Task 1's measured touch ranges and VT choice as defaults
- Produces: `Config` dataclass with fields used by every later task; `load_config(path: str | None) -> Config`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_config.py
import textwrap
from kw_dashboard.config import Config, load_config, TouchCalibration

def test_defaults_are_720p():
    c = Config()
    assert (c.width, c.height) == (1280, 720)
    assert c.rotate_seconds == 15
    assert c.touch_pause_seconds == 60
    assert c.idle_reset_seconds == 120

def test_touch_calibration_maps_raw_to_screen():
    cal = TouchCalibration(x_min=0, x_max=4095, y_min=0, y_max=4095,
                           swap_xy=False, invert_x=False, invert_y=False)
    assert cal.to_screen(0, 0, 1280, 720) == (0, 0)
    assert cal.to_screen(4095, 4095, 1280, 720) == (1279, 719)

def test_touch_calibration_inverts_and_swaps():
    cal = TouchCalibration(x_min=0, x_max=4095, y_min=0, y_max=4095,
                           swap_xy=True, invert_x=False, invert_y=True)
    # swap first, then invert y of the swapped result
    assert cal.to_screen(0, 4095, 1280, 720) == (1279, 719)

def test_load_config_overrides_from_toml(tmp_path):
    p = tmp_path / "c.toml"
    p.write_text(textwrap.dedent("""
        rotate_seconds = 30
        [touch]
        swap_xy = true
    """))
    c = load_config(str(p))
    assert c.rotate_seconds == 30
    assert c.touch.swap_xy is True
    assert c.width == 1280  # untouched default survives

def test_load_config_missing_file_returns_defaults():
    assert load_config("/nonexistent/x.toml").rotate_seconds == 15
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_config.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'kw_dashboard.config'`

- [ ] **Step 3: Write the implementation**

```python
# kw_dashboard/config.py
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_config.py -v`
Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
git add kw_dashboard/__init__.py kw_dashboard/config.py tests/test_config.py
git commit -m "feat: config module with touch calibration knobs"
```

---

## Task 3: HTTP helper

**Files:**
- Create: `kw_dashboard/sources/__init__.py` (empty), `kw_dashboard/sources/http.py`
- Test: `tests/test_http.py`

**Interfaces:**
- Consumes: `Config`
- Produces: `get_json(url, *, token=None, ca=None, timeout=8.0, params=None) -> dict` and `HttpError`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_http.py
import json, pytest
from unittest.mock import patch, MagicMock
from kw_dashboard.sources.http import get_json, build_url, HttpError

def test_build_url_encodes_params():
    u = build_url("http://x/api", {"query": 'up{job="a b"}', "limit": 3})
    assert u.startswith("http://x/api?")
    assert "query=up%7Bjob%3D%22a+b%22%7D" in u
    assert "limit=3" in u

def test_build_url_without_params():
    assert build_url("http://x/api", None) == "http://x/api"

def test_get_json_parses_body():
    resp = MagicMock()
    resp.read.return_value = json.dumps({"ok": True}).encode()
    resp.__enter__ = lambda s: s
    resp.__exit__ = lambda s, *a: None
    with patch("urllib.request.urlopen", return_value=resp):
        assert get_json("http://x") == {"ok": True}

def test_get_json_wraps_errors_as_httperror():
    with patch("urllib.request.urlopen", side_effect=OSError("refused")):
        with pytest.raises(HttpError):
            get_json("http://x")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_http.py -v`
Expected: FAIL, `No module named 'kw_dashboard.sources'`

- [ ] **Step 3: Write the implementation**

```python
# kw_dashboard/sources/http.py
"""Minimal JSON GET over stdlib urllib. Read-only by construction: no verb
other than GET is offered anywhere in this module."""
from __future__ import annotations
import json, ssl, urllib.parse, urllib.request


class HttpError(Exception):
    """Any failure reaching or decoding an endpoint."""


def build_url(url: str, params: dict | None) -> str:
    if not params:
        return url
    return f"{url}?{urllib.parse.urlencode(params)}"


def get_json(url: str, *, token: str | None = None, ca: str | None = None,
             timeout: float = 8.0, params: dict | None = None) -> dict:
    req = urllib.request.Request(build_url(url, params), method="GET")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    ctx = None
    if url.startswith("https"):
        ctx = ssl.create_default_context(cafile=ca) if ca else ssl._create_unverified_context()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            return json.loads(r.read().decode())
    except Exception as e:
        raise HttpError(f"GET {url}: {e}") from e


def get_text(url: str, *, token: str | None = None, ca: str | None = None,
             timeout: float = 8.0, params: dict | None = None) -> str:
    """Plain-text GET, used for the pod log endpoint."""
    req = urllib.request.Request(build_url(url, params), method="GET")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    ctx = None
    if url.startswith("https"):
        ctx = ssl.create_default_context(cafile=ca) if ca else ssl._create_unverified_context()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            return r.read().decode(errors="replace")
    except Exception as e:
        raise HttpError(f"GET {url}: {e}") from e
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_http.py -v`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add kw_dashboard/sources/ tests/test_http.py
git commit -m "feat: stdlib HTTP GET helper"
```

---

## Task 4: Prometheus client

All PromQL below was verified against the live cluster on 2026-08-16 and returns data. Do not "improve" the temperature query: `node_hwmon_temp_celsius` returns 136 series including NVMe drive temperatures, so it reports disk temperature as CPU temperature. `node_thermal_zone_temp` with `max by(instance)` is correct.

**Files:**
- Create: `kw_dashboard/sources/prometheus.py`
- Test: `tests/test_prometheus.py`, `tests/fixtures/prom_vector.json`

**Interfaces:**
- Consumes: `get_json` from Task 3
- Produces: `PrometheusClient` with `query(promql) -> list[Sample]`, `query_all(dict[str,str]) -> dict[str, list[Sample]]`; `Sample(labels: dict, value: float)`; module constant `QUERIES: dict[str, str]`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_prometheus.py
import pytest
from kw_dashboard.sources.prometheus import parse_vector, Sample, QUERIES

VECTOR = {
    "status": "success",
    "data": {"resultType": "vector", "result": [
        {"metric": {"instance": "192.168.10.101:9100"}, "value": [1786889057.7, "7.17"]},
        {"metric": {"instance": "192.168.10.102:9100"}, "value": [1786889057.7, "10.05"]},
    ]},
}

def test_parse_vector_returns_samples():
    s = parse_vector(VECTOR)
    assert len(s) == 2
    assert s[0] == Sample(labels={"instance": "192.168.10.101:9100"}, value=7.17)

def test_parse_vector_rejects_error_status():
    with pytest.raises(ValueError):
        parse_vector({"status": "error", "error": "boom"})

def test_parse_vector_handles_empty_result():
    assert parse_vector({"status": "success", "data": {"result": []}}) == []

def test_parse_vector_skips_nan_values():
    bad = {"status": "success", "data": {"result": [
        {"metric": {}, "value": [1.0, "NaN"]}]}}
    assert parse_vector(bad) == []

def test_temperature_query_uses_thermal_zone_not_hwmon():
    # hwmon includes NVMe drive temps and would misreport disk as CPU
    assert "node_thermal_zone_temp" in QUERIES["node_temp"]
    assert "hwmon" not in QUERIES["node_temp"]
    assert "max by" in QUERIES["node_temp"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_prometheus.py -v`
Expected: FAIL, `No module named 'kw_dashboard.sources.prometheus'`

- [ ] **Step 3: Write the implementation**

```python
# kw_dashboard/sources/prometheus.py
"""PromQL client. All queries verified against the live cluster 2026-08-16."""
from __future__ import annotations
import math
from dataclasses import dataclass
from .http import get_json


@dataclass(frozen=True)
class Sample:
    labels: dict
    value: float


# Verified working. node-exporter labels by `instance` (IP:9100), NOT node name;
# callers join to node names via the IP map from kube.py.
QUERIES = {
    "node_cpu": '100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[2m]))*100)',
    "node_mem": '100*(1 - node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes)',
    # thermal_zone, not hwmon: hwmon includes NVMe drive sensors.
    "node_temp": 'max by(instance)(node_thermal_zone_temp)',
    "pods_running": 'sum(kube_pod_status_phase{phase="Running"})',
    "ns_mem": 'sum by(namespace)(container_memory_working_set_bytes{container!=""})',
    "ns_cpu": 'sum by(namespace)(rate(container_cpu_usage_seconds_total{container!=""}[2m]))',
    "cluster_cpu": '100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[2m]))*100)',
    "cluster_mem": '100*(1 - sum(node_memory_MemAvailable_bytes)/sum(node_memory_MemTotal_bytes))',
    "pod_restarts": 'sum by(namespace,pod)(kube_pod_container_status_restarts_total)',
    "net_rx": 'sum(rate(container_network_receive_bytes_total[2m]))',
    "net_tx": 'sum(rate(container_network_transmit_bytes_total[2m]))',
}


def parse_vector(payload: dict) -> list[Sample]:
    """Turn an instant-query response into Samples, dropping non-finite values."""
    if payload.get("status") != "success":
        raise ValueError(f"prometheus error: {payload.get('error')}")
    out = []
    for item in payload.get("data", {}).get("result", []):
        try:
            v = float(item["value"][1])
        except (KeyError, IndexError, ValueError):
            continue
        if not math.isfinite(v):
            continue
        out.append(Sample(labels=dict(item.get("metric", {})), value=v))
    return out


class PrometheusClient:
    def __init__(self, base_url: str, timeout: float = 8.0):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def query(self, promql: str) -> list[Sample]:
        payload = get_json(f"{self.base_url}/api/v1/query",
                           params={"query": promql}, timeout=self.timeout)
        return parse_vector(payload)

    def query_named(self, name: str) -> list[Sample]:
        return self.query(QUERIES[name])

    def scalar(self, name: str, default: float = 0.0) -> float:
        s = self.query_named(name)
        return s[0].value if s else default
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_prometheus.py -v`
Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
git add kw_dashboard/sources/prometheus.py tests/test_prometheus.py
git commit -m "feat: prometheus client with verified queries"
```

---

## Task 5: Kubernetes API client

**Files:**
- Create: `kw_dashboard/sources/kube.py`
- Test: `tests/test_kube.py`

**Interfaces:**
- Consumes: `get_json`, `get_text` from Task 3
- Produces: `KubeClient` with `list_nodes() -> list[NodeInfo]`, `node_ip_map() -> dict[str,str]`, `list_namespaces() -> list[str]`, `list_pods(ns=None) -> list[PodInfo]`, `recent_events(ns=None, limit=30) -> list[EventInfo]`, `pod_log(ns, pod, container=None, tail=200) -> list[str]`. Dataclasses `NodeInfo`, `PodInfo`, `EventInfo`.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_kube.py
from kw_dashboard.sources.kube import (parse_nodes, parse_pods, parse_events,
                                       NodeInfo, PodInfo, build_ip_map)

NODES = {"items": [{
    "metadata": {"name": "master-11"},
    "spec": {"unschedulable": True},
    "status": {
        "addresses": [{"type": "InternalIP", "address": "192.168.10.101"}],
        "conditions": [{"type": "Ready", "status": "True"}],
        "capacity": {"cpu": "8", "memory": "31000000Ki", "pods": "110"},
    }}]}

PODS = {"items": [{
    "metadata": {"name": "p1", "namespace": "novaflow"},
    "spec": {"nodeName": "worker-21",
             "containers": [{"name": "app"}, {"name": "sidecar"}]},
    "status": {"phase": "Running",
               "containerStatuses": [
                   {"name": "app", "ready": True, "restartCount": 2},
                   {"name": "sidecar", "ready": False, "restartCount": 0}]}}]}

def test_parse_nodes_extracts_ready_and_cordon():
    n = parse_nodes(NODES)[0]
    assert n.name == "master-11"
    assert n.ready is True
    assert n.cordoned is True
    assert n.internal_ip == "192.168.10.101"

def test_build_ip_map_joins_node_exporter_instances_to_names():
    # node-exporter labels series "IP:9100"; this map is how we get node names
    m = build_ip_map(parse_nodes(NODES))
    assert m["192.168.10.101:9100"] == "master-11"

def test_parse_pods_counts_ready_containers():
    p = parse_pods(PODS)[0]
    assert p.namespace == "novaflow"
    assert p.ready == 1 and p.total == 2
    assert p.restarts == 2
    assert p.healthy is False  # not all containers ready

def test_parse_pods_containers_listed_for_log_picker():
    assert parse_pods(PODS)[0].containers == ["app", "sidecar"]

def test_parse_events_sorted_newest_first():
    ev = {"items": [
        {"metadata": {"name": "a"}, "type": "Normal", "reason": "Started",
         "message": "m1", "lastTimestamp": "2026-08-16T10:00:00Z",
         "involvedObject": {"name": "p1", "namespace": "x"}},
        {"metadata": {"name": "b"}, "type": "Warning", "reason": "Failed",
         "message": "m2", "lastTimestamp": "2026-08-16T11:00:00Z",
         "involvedObject": {"name": "p2", "namespace": "x"}}]}
    e = parse_events(ev)
    assert [x.reason for x in e] == ["Failed", "Started"]
    assert e[0].warning is True
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_kube.py -v`
Expected: FAIL, `No module named 'kw_dashboard.sources.kube'`

- [ ] **Step 3: Write the implementation**

```python
# kw_dashboard/sources/kube.py
"""Read-only k3s API client. GET only — no mutating verb appears in this file."""
from __future__ import annotations
from dataclasses import dataclass, field
from datetime import datetime, timezone
from .http import get_json, get_text


@dataclass(frozen=True)
class NodeInfo:
    name: str
    internal_ip: str
    ready: bool
    cordoned: bool
    cpu_capacity: float
    mem_capacity_bytes: float
    pod_capacity: int


@dataclass(frozen=True)
class PodInfo:
    name: str
    namespace: str
    node: str
    phase: str
    ready: int
    total: int
    restarts: int
    containers: list = field(default_factory=list)

    @property
    def healthy(self) -> bool:
        return self.phase == "Running" and self.ready == self.total and self.total > 0


@dataclass(frozen=True)
class EventInfo:
    reason: str
    message: str
    obj: str
    namespace: str
    warning: bool
    ts: datetime


def _ki_to_bytes(v: str) -> float:
    v = v.strip()
    units = {"Ki": 1024, "Mi": 1024**2, "Gi": 1024**3, "Ti": 1024**4}
    for suf, mult in units.items():
        if v.endswith(suf):
            return float(v[: -len(suf)]) * mult
    try:
        return float(v)
    except ValueError:
        return 0.0


def parse_nodes(payload: dict) -> list[NodeInfo]:
    out = []
    for it in payload.get("items", []):
        st, spec, meta = it.get("status", {}), it.get("spec", {}), it.get("metadata", {})
        ip = next((a["address"] for a in st.get("addresses", [])
                   if a.get("type") == "InternalIP"), "")
        ready = any(c.get("type") == "Ready" and c.get("status") == "True"
                    for c in st.get("conditions", []))
        cap = st.get("capacity", {})
        out.append(NodeInfo(
            name=meta.get("name", ""), internal_ip=ip, ready=ready,
            cordoned=bool(spec.get("unschedulable", False)),
            cpu_capacity=float(cap.get("cpu", 0) or 0),
            mem_capacity_bytes=_ki_to_bytes(cap.get("memory", "0")),
            pod_capacity=int(cap.get("pods", 0) or 0)))
    return out


def build_ip_map(nodes: list[NodeInfo], port: int = 9100) -> dict[str, str]:
    """node-exporter labels series `IP:9100`, not by node name. This joins them."""
    return {f"{n.internal_ip}:{port}": n.name for n in nodes if n.internal_ip}


def parse_pods(payload: dict) -> list[PodInfo]:
    out = []
    for it in payload.get("items", []):
        meta, spec, st = it.get("metadata", {}), it.get("spec", {}), it.get("status", {})
        cs = st.get("containerStatuses", []) or []
        containers = [c.get("name", "") for c in spec.get("containers", [])]
        out.append(PodInfo(
            name=meta.get("name", ""), namespace=meta.get("namespace", ""),
            node=spec.get("nodeName", ""), phase=st.get("phase", "Unknown"),
            ready=sum(1 for c in cs if c.get("ready")),
            total=len(containers) or len(cs),
            restarts=sum(int(c.get("restartCount", 0)) for c in cs),
            containers=containers))
    return out


def _parse_ts(s: str | None) -> datetime:
    if not s:
        return datetime.fromtimestamp(0, tz=timezone.utc)
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return datetime.fromtimestamp(0, tz=timezone.utc)


def parse_events(payload: dict) -> list[EventInfo]:
    out = []
    for it in payload.get("items", []):
        io = it.get("involvedObject", {})
        out.append(EventInfo(
            reason=it.get("reason", ""), message=it.get("message", ""),
            obj=io.get("name", ""), namespace=io.get("namespace", ""),
            warning=it.get("type") == "Warning",
            ts=_parse_ts(it.get("lastTimestamp") or it.get("eventTime"))))
    out.sort(key=lambda e: e.ts, reverse=True)
    return out


class KubeClient:
    def __init__(self, base_url: str, token: str, ca: str | None, timeout: float = 8.0):
        self.base = base_url.rstrip("/")
        self.token, self.ca, self.timeout = token, ca, timeout

    def _get(self, path: str, params: dict | None = None) -> dict:
        return get_json(f"{self.base}{path}", token=self.token, ca=self.ca,
                        timeout=self.timeout, params=params)

    def list_nodes(self) -> list[NodeInfo]:
        return parse_nodes(self._get("/api/v1/nodes"))

    def list_namespaces(self) -> list[str]:
        p = self._get("/api/v1/namespaces")
        return sorted(i["metadata"]["name"] for i in p.get("items", []))

    def list_pods(self, namespace: str | None = None) -> list[PodInfo]:
        path = f"/api/v1/namespaces/{namespace}/pods" if namespace else "/api/v1/pods"
        return parse_pods(self._get(path))

    def recent_events(self, namespace: str | None = None, limit: int = 30) -> list[EventInfo]:
        path = f"/api/v1/namespaces/{namespace}/events" if namespace else "/api/v1/events"
        return parse_events(self._get(path, {"limit": limit}))[:limit]

    def pod_log(self, namespace: str, pod: str, container: str | None = None,
                tail: int = 200) -> list[str]:
        params = {"tailLines": tail, "timestamps": "true"}
        if container:
            params["container"] = container
        text = get_text(f"{self.base}/api/v1/namespaces/{namespace}/pods/{pod}/log",
                        token=self.token, ca=self.ca, timeout=self.timeout, params=params)
        return [ln for ln in text.splitlines() if ln]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_kube.py -v`
Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
git add kw_dashboard/sources/kube.py tests/test_kube.py
git commit -m "feat: read-only kubernetes API client"
```

---

## Task 6: Alertmanager client

**Files:**
- Create: `kw_dashboard/sources/alerts.py`
- Test: `tests/test_alerts.py`

**Interfaces:**
- Consumes: `get_json`
- Produces: `AlertsClient.active() -> list[Alert]`; `Alert(name, severity, summary, starts_at)`; `SEVERITY_ORDER`; `rank_alerts(list[Alert]) -> list[Alert]`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_alerts.py
from kw_dashboard.sources.alerts import parse_alerts, rank_alerts, Alert

PAYLOAD = [
    {"labels": {"alertname": "DiskLow", "severity": "warning"},
     "annotations": {"summary": "disk low"}, "status": {"state": "active"},
     "startsAt": "2026-08-16T10:00:00Z"},
    {"labels": {"alertname": "NodeDown", "severity": "critical"},
     "annotations": {"summary": "node down"}, "status": {"state": "active"},
     "startsAt": "2026-08-16T11:00:00Z"},
    {"labels": {"alertname": "Silenced", "severity": "critical"},
     "annotations": {"summary": "x"}, "status": {"state": "suppressed"},
     "startsAt": "2026-08-16T09:00:00Z"},
]

def test_parse_alerts_skips_suppressed():
    a = parse_alerts(PAYLOAD)
    assert {x.name for x in a} == {"DiskLow", "NodeDown"}

def test_rank_alerts_critical_first():
    assert rank_alerts(parse_alerts(PAYLOAD))[0].name == "NodeDown"

def test_rank_alerts_unknown_severity_sorts_last():
    a = [Alert("X", "bogus", "s", None), Alert("Y", "critical", "s", None)]
    assert [x.name for x in rank_alerts(a)] == ["Y", "X"]

def test_has_critical_detects_preemption_condition():
    from kw_dashboard.sources.alerts import has_critical
    assert has_critical(parse_alerts(PAYLOAD)) is True
    assert has_critical([]) is False
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_alerts.py -v`
Expected: FAIL, module not found

- [ ] **Step 3: Write the implementation**

```python
# kw_dashboard/sources/alerts.py
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
        out.append(Alert(
            name=labels.get("alertname", "unknown"),
            severity=labels.get("severity", "info"),
            summary=a.get("annotations", {}).get("summary", ""),
            starts_at=parsed))
    return out


def rank_alerts(alerts: list[Alert]) -> list[Alert]:
    epoch = datetime.fromtimestamp(0, tz=timezone.utc)
    return sorted(alerts, key=lambda a: (SEVERITY_ORDER.get(a.severity, 99),
                                         -(a.starts_at or epoch).timestamp()))


def has_critical(alerts: list[Alert]) -> bool:
    return any(a.severity == "critical" for a in alerts)


class AlertsClient:
    def __init__(self, base_url: str, timeout: float = 8.0):
        self.base = base_url.rstrip("/")
        self.timeout = timeout

    def active(self) -> list[Alert]:
        payload = get_json(f"{self.base}/api/v2/alerts", timeout=self.timeout)
        return rank_alerts(parse_alerts(payload))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_alerts.py -v`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add kw_dashboard/sources/alerts.py tests/test_alerts.py
git commit -m "feat: alertmanager client with severity ranking"
```

---

## Task 7: Snapshot model and collector thread

**Files:**
- Create: `kw_dashboard/model.py`, `kw_dashboard/collector.py`
- Test: `tests/test_collector.py`

**Interfaces:**
- Consumes: `PrometheusClient`, `KubeClient`, `AlertsClient`, `Config`
- Produces: `Snapshot` dataclass (fields: `cluster_cpu`, `cluster_mem`, `pods_running`, `nodes: list[NodeStat]`, `namespaces: list[NsStat]`, `alerts`, `events`, `updated: dict[str,float]`); `SourceState`; `Collector` with `.start()`, `.stop()`, `.snapshot() -> Snapshot`; `is_stale(snapshot, source, now, limit) -> bool`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_collector.py
import time
from kw_dashboard.model import Snapshot, NodeStat, NsStat, merge_node_stats
from kw_dashboard.collector import is_stale
from kw_dashboard.sources.prometheus import Sample
from kw_dashboard.sources.kube import NodeInfo

def test_merge_node_stats_joins_prom_instances_to_node_names():
    nodes = [NodeInfo("master-11", "192.168.10.101", True, True, 8, 3e10, 110),
             NodeInfo("worker-21", "192.168.10.104", True, False, 8, 3e10, 110)]
    cpu = [Sample({"instance": "192.168.10.101:9100"}, 47.0),
           Sample({"instance": "192.168.10.104:9100"}, 12.0)]
    mem = [Sample({"instance": "192.168.10.101:9100"}, 31.0)]
    temp = [Sample({"instance": "192.168.10.104:9100"}, 61.5)]
    out = {n.name: n for n in merge_node_stats(nodes, cpu, mem, temp, {})}
    assert out["master-11"].cpu_pct == 47.0
    assert out["master-11"].mem_pct == 31.0
    assert out["master-11"].temp_c is None      # missing series -> None, not 0
    assert out["worker-21"].temp_c == 61.5
    assert out["master-11"].cordoned is True

def test_node_stat_worst_uses_highest_pressure():
    n = NodeStat("n", True, False, 20.0, 90.0, 45.0, 5)
    assert n.worst_pct == 90.0

def test_node_stat_not_ready_is_always_worst():
    n = NodeStat("n", False, False, 1.0, 1.0, 20.0, 0)
    assert n.worst_pct == 100.0

def test_is_stale_uses_per_source_timestamps():
    s = Snapshot(updated={"prom": time.time() - 10, "kube": time.time() - 300})
    assert is_stale(s, "prom", limit=45) is False
    assert is_stale(s, "kube", limit=45) is True

def test_is_stale_for_never_updated_source():
    assert is_stale(Snapshot(), "prom", limit=45) is True
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_collector.py -v`
Expected: FAIL, module not found

- [ ] **Step 3: Write the model**

```python
# kw_dashboard/model.py
"""Immutable snapshot handed from collector to renderer."""
from __future__ import annotations
from dataclasses import dataclass, field
from .sources.prometheus import Sample
from .sources.kube import NodeInfo


@dataclass(frozen=True)
class NodeStat:
    name: str
    ready: bool
    cordoned: bool
    cpu_pct: float
    mem_pct: float
    temp_c: float | None
    pods: int

    @property
    def worst_pct(self) -> float:
        """Single number driving the node's colour. Not-ready dominates."""
        if not self.ready:
            return 100.0
        vals = [self.cpu_pct, self.mem_pct]
        if self.temp_c is not None:
            vals.append(min(100.0, self.temp_c))  # ~80C reads as high pressure
        return max(vals)


@dataclass(frozen=True)
class NsStat:
    name: str
    pods: int
    unhealthy: int
    cpu_cores: float
    mem_bytes: float


@dataclass(frozen=True)
class Snapshot:
    cluster_cpu: float = 0.0
    cluster_mem: float = 0.0
    pods_running: int = 0
    net_rx: float = 0.0
    net_tx: float = 0.0
    nodes: list = field(default_factory=list)
    namespaces: list = field(default_factory=list)
    alerts: list = field(default_factory=list)
    events: list = field(default_factory=list)
    cpu_history: tuple = ()
    mem_history: tuple = ()
    updated: dict = field(default_factory=dict)
    errors: dict = field(default_factory=dict)


def _by_instance(samples: list[Sample]) -> dict[str, float]:
    return {s.labels.get("instance", ""): s.value for s in samples}


def merge_node_stats(nodes: list[NodeInfo], cpu: list[Sample], mem: list[Sample],
                     temp: list[Sample], pod_counts: dict[str, int]) -> list[NodeStat]:
    """Join node-exporter series (labelled by IP:9100) to k8s node names."""
    c, m, t = _by_instance(cpu), _by_instance(mem), _by_instance(temp)
    out = []
    for n in nodes:
        key = f"{n.internal_ip}:9100"
        out.append(NodeStat(
            name=n.name, ready=n.ready, cordoned=n.cordoned,
            cpu_pct=c.get(key, 0.0), mem_pct=m.get(key, 0.0),
            temp_c=t.get(key),  # None when absent: absent != 0 degrees
            pods=pod_counts.get(n.name, 0)))
    return out
```

- [ ] **Step 4: Write the collector**

```python
# kw_dashboard/collector.py
"""Background polling thread. Never blocks the renderer; each source fails
independently so one dead endpoint dims only its own panels."""
from __future__ import annotations
import threading, time
from collections import Counter, deque
from dataclasses import replace
from .model import Snapshot, NsStat, merge_node_stats


def is_stale(snap: Snapshot, source: str, limit: float, now: float | None = None) -> bool:
    ts = snap.updated.get(source)
    if ts is None:
        return True
    return ((now or time.time()) - ts) > limit


class Collector:
    def __init__(self, cfg, prom, kube, alerts):
        self.cfg, self.prom, self.kube, self.alerts = cfg, prom, kube, alerts
        self._snap = Snapshot()
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._cpu_hist: deque = deque(maxlen=60)
        self._mem_hist: deque = deque(maxlen=60)

    def snapshot(self) -> Snapshot:
        with self._lock:
            return self._snap

    def _update(self, **kw):
        with self._lock:
            self._snap = replace(self._snap, **kw)

    def _mark(self, source: str, error: str | None = None):
        with self._lock:
            upd = dict(self._snap.updated)
            errs = dict(self._snap.errors)
            if error:
                errs[source] = error
            else:
                upd[source] = time.time()
                errs.pop(source, None)
            self._snap = replace(self._snap, updated=upd, errors=errs)

    def _poll_prom(self):
        try:
            cpu = self.prom.scalar("cluster_cpu")
            mem = self.prom.scalar("cluster_mem")
            self._cpu_hist.append(cpu)
            self._mem_hist.append(mem)
            self._update(
                cluster_cpu=cpu, cluster_mem=mem,
                pods_running=int(self.prom.scalar("pods_running")),
                net_rx=self.prom.scalar("net_rx"), net_tx=self.prom.scalar("net_tx"),
                cpu_history=tuple(self._cpu_hist), mem_history=tuple(self._mem_hist))
            self._node_and_ns()
            self._mark("prom")
        except Exception as e:
            self._mark("prom", str(e))

    def _node_and_ns(self):
        nodes = self.kube.list_nodes()
        pods = self.kube.list_pods()
        counts = Counter(p.node for p in pods)
        stats = merge_node_stats(
            nodes, self.prom.query_named("node_cpu"),
            self.prom.query_named("node_mem"),
            self.prom.query_named("node_temp"), counts)

        ns_cpu = {s.labels.get("namespace"): s.value for s in self.prom.query_named("ns_cpu")}
        ns_mem = {s.labels.get("namespace"): s.value for s in self.prom.query_named("ns_mem")}
        by_ns: dict[str, list] = {}
        for p in pods:
            by_ns.setdefault(p.namespace, []).append(p)
        namespaces = [
            NsStat(name=ns, pods=len(ps),
                   unhealthy=sum(1 for p in ps if not p.healthy),
                   cpu_cores=ns_cpu.get(ns, 0.0), mem_bytes=ns_mem.get(ns, 0.0))
            for ns, ps in by_ns.items()]
        self._update(nodes=stats, namespaces=namespaces)

    def _poll_slow(self):
        try:
            self._update(alerts=self.alerts.active())
            self._mark("alerts")
        except Exception as e:
            self._mark("alerts", str(e))
        try:
            self._update(events=self.kube.recent_events(limit=30))
            self._mark("kube")
        except Exception as e:
            self._mark("kube", str(e))

    def _run(self):
        last_slow = 0.0
        while not self._stop.is_set():
            self._poll_prom()
            if time.time() - last_slow > self.cfg.poll_slow_seconds:
                self._poll_slow()
                last_slow = time.time()
            self._stop.wait(self.cfg.poll_fast_seconds)

    def start(self):
        self._thread = threading.Thread(target=self._run, daemon=True, name="collector")
        self._thread.start()

    def stop(self):
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=3)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `pytest tests/test_collector.py -v`
Expected: 5 passed

- [ ] **Step 6: Commit**

```bash
git add kw_dashboard/model.py kw_dashboard/collector.py tests/test_collector.py
git commit -m "feat: snapshot model and collector thread with per-source staleness"
```

---

## Task 8: Navigation stack

**Files:**
- Create: `kw_dashboard/nav.py`
- Test: `tests/test_nav.py`

**Interfaces:**
- Consumes: `Config`
- Produces: `View(kind: str, params: dict)`, `Nav` with `.push(view)`, `.pop()`, `.current`, `.depth`, `.touch()`, `.tick(now)`, `.rotating`, `.page_index`; kinds are `"cluster"`, `"pulse"`, `"explore"`, `"alerts"`, `"namespace"`, `"pod"`, `"logs"`, `"node"`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_nav.py
from kw_dashboard.nav import Nav, View, PAGES

def test_starts_on_cluster_page_rotating():
    n = Nav(rotate_seconds=15, pause_seconds=60, idle_reset_seconds=120)
    assert n.current.kind == "cluster"
    assert n.rotating is True

def test_tick_rotates_pages_in_order():
    n = Nav(15, 60, 120)
    n.tick(now=16.0)
    assert n.current.kind == PAGES[1]
    n.tick(now=32.0)
    assert n.current.kind == PAGES[2]

def test_touch_pauses_rotation_then_resumes():
    n = Nav(15, 60, 120)
    n.touch(now=1.0)
    n.tick(now=30.0)
    assert n.current.kind == "cluster"   # still paused
    n.tick(now=100.0)
    assert n.current.kind != "cluster"   # pause expired, rotation resumed

def test_push_and_pop_restores_previous_view():
    n = Nav(15, 60, 120)
    n.push(View("namespace", {"ns": "novaflow"}), now=1.0)
    assert n.current.kind == "namespace"
    assert n.depth == 1
    n.pop()
    assert n.current.kind == "cluster"
    assert n.depth == 0

def test_deep_view_does_not_rotate():
    n = Nav(15, 60, 120)
    n.push(View("pod", {"ns": "a", "pod": "b"}), now=1.0)
    n.tick(now=100.0)
    assert n.current.kind == "pod"

def test_idle_reset_returns_to_cluster_and_resumes_rotation():
    n = Nav(15, 60, 120)
    n.push(View("logs", {"ns": "a", "pod": "b"}), now=1.0)
    n.tick(now=200.0)      # >120s since last touch
    assert n.current.kind == "cluster"
    assert n.depth == 0
    assert n.rotating is True

def test_jump_to_page_sets_index_and_pauses():
    n = Nav(15, 60, 120)
    n.jump_to_page(3, now=5.0)
    assert n.current.kind == PAGES[3]
    assert n.rotating is False
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_nav.py -v`
Expected: FAIL, module not found

- [ ] **Step 3: Write the implementation**

```python
# kw_dashboard/nav.py
"""View stack and rotation state. Pure logic, no pygame — so it is testable
without a display."""
from __future__ import annotations
from dataclasses import dataclass, field

PAGES = ["cluster", "pulse", "explore", "alerts"]


@dataclass(frozen=True)
class View:
    kind: str
    params: dict = field(default_factory=dict)


class Nav:
    def __init__(self, rotate_seconds: float, pause_seconds: float,
                 idle_reset_seconds: float):
        self.rotate_seconds = rotate_seconds
        self.pause_seconds = pause_seconds
        self.idle_reset_seconds = idle_reset_seconds
        self.page_index = 0
        self._stack: list[View] = []
        # Far in the past: a fresh Nav must start rotating, not paused.
        self._last_touch = -1e9
        self._last_rotate = 0.0
        self._preempted = False

    @property
    def depth(self) -> int:
        return len(self._stack)

    @property
    def current(self) -> View:
        return self._stack[-1] if self._stack else View(PAGES[self.page_index])

    @property
    def rotating(self) -> bool:
        return self.depth == 0 and not self._paused_at(self._now) and not self._preempted

    _now = 0.0

    def _paused_at(self, now: float) -> bool:
        return (now - self._last_touch) < self.pause_seconds

    def touch(self, now: float):
        self._now = now
        self._last_touch = now

    def push(self, view: View, now: float):
        self.touch(now)
        self._stack.append(view)

    def pop(self):
        if self._stack:
            self._stack.pop()

    def jump_to_page(self, index: int, now: float):
        self.touch(now)
        self._stack.clear()
        self.page_index = index % len(PAGES)
        self._last_rotate = now

    def preempt_for_alert(self, now: float):
        """A firing critical alert seizes the screen (spec section 7)."""
        self._stack.clear()
        self.page_index = PAGES.index("alerts")
        self._preempted = True
        self._last_rotate = now

    def clear_preempt(self, now: float):
        self._preempted = False
        self.touch(now)

    def tick(self, now: float):
        self._now = now
        # Idle reset from a deep view or a pre-empted page back to page 1.
        # Only short-circuits when there is actually something to reset —
        # otherwise an untouched panel would never rotate at all.
        if ((now - self._last_touch) > self.idle_reset_seconds
                and (self._stack or self._preempted)):
            self._stack.clear()
            self.page_index = 0
            self._preempted = False
            self._last_rotate = now
            return
        if not self.rotating:
            return
        if (now - self._last_rotate) >= self.rotate_seconds:
            self.page_index = (self.page_index + 1) % len(PAGES)
            self._last_rotate = now
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_nav.py -v`
Expected: 7 passed

- [ ] **Step 5: Commit**

```bash
git add kw_dashboard/nav.py tests/test_nav.py
git commit -m "feat: navigation stack with rotation, pause and idle reset"
```

---

## Task 9: Log stream with bounded ring buffer

**Files:**
- Create: `kw_dashboard/logstream.py`
- Test: `tests/test_logstream.py`

**Interfaces:**
- Consumes: `KubeClient.pod_log`, `Config.log_ring_size`
- Produces: `LogStream` with `.append_lines(list[str])`, `.lines`, `.follow`, `.scroll_up(n)`, `.jump_to_live()`, `.visible(rows)`; must never grow unbounded

- [ ] **Step 1: Write the failing test**

```python
# tests/test_logstream.py
from kw_dashboard.logstream import LogStream

def test_ring_buffer_bounds_memory():
    s = LogStream(ring_size=100)
    s.append_lines([f"line {i}" for i in range(500)])
    assert len(s.lines) == 100
    assert s.lines[-1] == "line 499"

def test_follows_live_by_default():
    s = LogStream(ring_size=100)
    s.append_lines(["a", "b", "c"])
    assert s.follow is True
    assert s.visible(rows=2) == ["b", "c"]

def test_scroll_up_pauses_follow():
    s = LogStream(ring_size=100)
    s.append_lines([f"l{i}" for i in range(10)])
    s.scroll_up(3)
    assert s.follow is False
    assert s.visible(rows=2) == ["l5", "l6"]

def test_new_lines_do_not_move_view_while_paused():
    s = LogStream(ring_size=100)
    s.append_lines([f"l{i}" for i in range(10)])
    s.scroll_up(3)
    before = s.visible(rows=2)
    s.append_lines(["new"])
    assert s.visible(rows=2) == before

def test_jump_to_live_resumes_follow():
    s = LogStream(ring_size=100)
    s.append_lines([f"l{i}" for i in range(10)])
    s.scroll_up(5)
    s.jump_to_live()
    assert s.follow is True
    assert s.visible(rows=1) == ["l9"]

def test_scroll_up_clamps_at_oldest_line():
    s = LogStream(ring_size=100)
    s.append_lines(["a", "b"])
    s.scroll_up(999)
    assert s.visible(rows=2) == ["a", "b"]

def test_wrap_long_line_for_narrow_panel():
    from kw_dashboard.logstream import wrap_line
    assert wrap_line("abcdefghij", 4) == ["abcd", "efgh", "ij"]
    assert wrap_line("", 4) == [""]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_logstream.py -v`
Expected: FAIL, module not found

- [ ] **Step 3: Write the implementation**

```python
# kw_dashboard/logstream.py
"""Bounded log buffer with follow/pause. A long-running tail on an always-on
panel must not grow without limit."""
from __future__ import annotations
from collections import deque


def wrap_line(line: str, cols: int) -> list[str]:
    """Hard-wrap; the log view wraps rather than scrolling horizontally."""
    if not line:
        return [""]
    return [line[i:i + cols] for i in range(0, len(line), cols)]


class LogStream:
    def __init__(self, ring_size: int = 2000):
        self._buf: deque = deque(maxlen=ring_size)
        self.follow = True
        self._offset = 0  # lines above the live tail

    @property
    def lines(self) -> list[str]:
        return list(self._buf)

    def append_lines(self, lines: list[str]):
        self._buf.extend(lines)

    def scroll_up(self, n: int):
        self.follow = False
        self._offset = min(self._offset + n, max(0, len(self._buf) - 1))

    def scroll_down(self, n: int):
        self._offset = max(0, self._offset - n)
        if self._offset == 0:
            self.follow = True

    def jump_to_live(self):
        self.follow = True
        self._offset = 0

    def visible(self, rows: int) -> list[str]:
        buf = list(self._buf)
        if not buf:
            return []
        end = len(buf) if self.follow else max(1, len(buf) - self._offset)
        start = max(0, end - rows)
        return buf[start:end]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_logstream.py -v`
Expected: 7 passed

- [ ] **Step 5: Commit**

```bash
git add kw_dashboard/logstream.py tests/test_logstream.py
git commit -m "feat: bounded log ring buffer with follow/pause"
```

---

## Task 10: Explorer sorting logic

Sorting is pure logic and belongs in tests, separate from rendering.

**Files:**
- Create: `kw_dashboard/ui/__init__.py` (empty), `kw_dashboard/ui/sorting.py`
- Test: `tests/test_explore_sort.py`

**Interfaces:**
- Consumes: `NsStat`, `PodInfo`
- Produces: `sort_namespaces(list[NsStat]) -> list[NsStat]`, `sort_pods(list[PodInfo]) -> list[PodInfo]`, `fmt_bytes(float) -> str`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_explore_sort.py
from kw_dashboard.ui.sorting import sort_namespaces, sort_pods, fmt_bytes
from kw_dashboard.model import NsStat
from kw_dashboard.sources.kube import PodInfo

def test_unhealthy_namespaces_sort_first():
    a = NsStat("big", 30, 0, 5.0, 9e9)
    b = NsStat("broken", 2, 1, 0.1, 1e6)
    assert [n.name for n in sort_namespaces([a, b])] == ["broken", "big"]

def test_healthy_namespaces_sort_by_memory():
    a = NsStat("small", 3, 0, 0.1, 1e6)
    b = NsStat("large", 3, 0, 0.1, 9e9)
    assert [n.name for n in sort_namespaces([a, b])] == ["large", "small"]

def test_unhealthy_pods_sort_first_then_by_restarts():
    p1 = PodInfo("ok", "n", "w", "Running", 1, 1, 0, ["c"])
    p2 = PodInfo("bad", "n", "w", "CrashLoopBackOff", 0, 1, 9, ["c"])
    p3 = PodInfo("flaky", "n", "w", "Running", 1, 1, 5, ["c"])
    assert [p.name for p in sort_pods([p1, p2, p3])] == ["bad", "flaky", "ok"]

def test_fmt_bytes_scales_units():
    assert fmt_bytes(0) == "0 B"
    assert fmt_bytes(1536) == "1.5 KB"
    assert fmt_bytes(9e9) == "8.4 GB"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_explore_sort.py -v`
Expected: FAIL, module not found

- [ ] **Step 3: Write the implementation**

```python
# kw_dashboard/ui/sorting.py
"""Ordering rules for the explorer: problems first, then size."""
from __future__ import annotations


def sort_namespaces(items: list) -> list:
    return sorted(items, key=lambda n: (0 if n.unhealthy else 1,
                                        -n.unhealthy, -n.mem_bytes, n.name))


def sort_pods(items: list) -> list:
    return sorted(items, key=lambda p: (0 if not p.healthy else 1,
                                        -p.restarts, p.name))


def fmt_bytes(n: float) -> str:
    if n < 1024:
        return f"{int(n)} B"
    for unit in ("KB", "MB", "GB", "TB"):
        n /= 1024.0
        if n < 1024 or unit == "TB":
            return f"{n:.1f} {unit}"
    return f"{n:.1f} TB"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_explore_sort.py -v`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add kw_dashboard/ui/ tests/test_explore_sort.py
git commit -m "feat: explorer sorting and byte formatting"
```

---

## Task 11: Theme and widgets

**REQUIRED:** Load the `dataviz` skill before writing `theme.py`. It governs palette construction, the colour formula and its validator, and accessibility checks. Do not invent hex values ad hoc.

**Files:**
- Create: `kw_dashboard/ui/theme.py`, `kw_dashboard/ui/widgets.py`
- Test: `tests/test_theme.py`

**Interfaces:**
- Consumes: `Config`
- Produces: `Theme` (colours `bg`, `fg`, `dim`, `accent`, `ok`, `warn`, `crit`, `panel`; fonts `huge`, `big`, `body`, `small`, `mono`), `state_color(pct) -> tuple`, and widget functions `draw_arc_gauge`, `draw_sparkline`, `draw_bar`, `draw_list_row`, `draw_header`, `draw_back_button`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_theme.py
from kw_dashboard.ui.theme import state_color, Theme, FONT_SIZES

def test_state_color_thresholds_are_distinct():
    ok, warn, crit = state_color(10), state_color(75), state_color(95)
    assert ok != warn != crit and ok != crit

def test_font_sizes_respect_26px_legibility_floor():
    # spec section 2: glanceable text floor is 26px at ~1m on a 9" panel
    for name in ("huge", "big", "body", "small"):
        assert FONT_SIZES[name] >= 26, f"{name} below legibility floor"

def test_mono_is_the_documented_exception():
    # spec section 8: log view alone relaxes the floor
    assert FONT_SIZES["mono"] == 20

def test_state_color_clamps_out_of_range():
    assert state_color(-5) == state_color(0)
    assert state_color(150) == state_color(100)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_theme.py -v`
Expected: FAIL, module not found

- [ ] **Step 3: Write theme and widgets**

Load the `dataviz` skill, derive the palette per its formula and run its validator, then write `theme.py` using the derived values. The structure below is fixed; the specific colour values come from the skill.

```python
# kw_dashboard/ui/theme.py
"""Palette and type scale. Values derived via the dataviz skill.

FONT_SIZES honours the spec's 26px legibility floor for every glanceable
size. `mono` at 20px is the single documented exception (spec section 8):
logs are a lean-in activity and 26px monospace fits only ~78 columns.
"""
from __future__ import annotations
from dataclasses import dataclass

FONT_SIZES = {"huge": 120, "big": 64, "body": 30, "small": 26, "mono": 20}

WARN_AT, CRIT_AT = 70.0, 88.0


@dataclass(frozen=True)
class Theme:
    bg: tuple
    fg: tuple
    dim: tuple
    panel: tuple
    accent: tuple
    ok: tuple
    warn: tuple
    crit: tuple


# Replace with dataviz-derived values; keep the field names.
THEME = Theme(
    bg=(13, 17, 23), fg=(230, 237, 243), dim=(110, 122, 138),
    panel=(22, 27, 34), accent=(88, 166, 255),
    ok=(63, 185, 80), warn=(210, 153, 34), crit=(248, 81, 73))


def state_color(pct: float, theme: Theme = THEME) -> tuple:
    """Colour is reserved for state, so it always carries meaning."""
    pct = min(100.0, max(0.0, pct))
    if pct >= CRIT_AT:
        return theme.crit
    if pct >= WARN_AT:
        return theme.warn
    return theme.ok
```

```python
# kw_dashboard/ui/widgets.py
"""Reusable drawing primitives. Pure pygame; no data access."""
from __future__ import annotations
import math
import pygame
from .theme import THEME, state_color

TOUCH_MIN_H = 60  # spec global constraint


def draw_arc_gauge(surf, center, radius, pct, label, fonts, width=18):
    pct = min(100.0, max(0.0, pct))
    cx, cy = center
    rect = pygame.Rect(cx - radius, cy - radius, radius * 2, radius * 2)
    pygame.draw.arc(surf, THEME.panel, rect, math.radians(-215), math.radians(35), width)
    end = math.radians(-215) + (math.radians(250) * pct / 100.0)
    if pct > 0:
        pygame.draw.arc(surf, state_color(pct), rect, math.radians(-215), end, width)
    val = fonts["big"].render(f"{pct:.0f}%", True, THEME.fg)
    surf.blit(val, val.get_rect(center=(cx, cy - 6)))
    lab = fonts["small"].render(label, True, THEME.dim)
    surf.blit(lab, lab.get_rect(center=(cx, cy + radius - 10)))


def draw_sparkline(surf, rect, values, color=None):
    if len(values) < 2:
        return
    lo, hi = min(values), max(values)
    span = (hi - lo) or 1.0
    step = rect.width / (len(values) - 1)
    pts = [(rect.x + i * step, rect.bottom - ((v - lo) / span) * rect.height)
           for i, v in enumerate(values)]
    pygame.draw.lines(surf, color or THEME.accent, False, pts, 3)


def draw_bar(surf, rect, pct, color=None):
    pygame.draw.rect(surf, THEME.panel, rect, border_radius=4)
    w = int(rect.width * min(100.0, max(0.0, pct)) / 100.0)
    if w > 0:
        pygame.draw.rect(surf, color or state_color(pct),
                         pygame.Rect(rect.x, rect.y, w, rect.height), border_radius=4)


def draw_header(surf, title, fonts, right_text=None, stale=False):
    color = THEME.dim if stale else THEME.fg
    surf.blit(fonts["body"].render(title, True, color), (24, 18))
    if right_text:
        t = fonts["body"].render(right_text, True, THEME.dim)
        surf.blit(t, (surf.get_width() - t.get_width() - 24, 18))


def draw_back_button(surf, fonts) -> pygame.Rect:
    rect = pygame.Rect(8, 8, 90, TOUCH_MIN_H)
    surf.blit(fonts["body"].render("<", True, THEME.accent), (28, 18))
    return rect


def draw_list_row(surf, rect, left, right, fonts, pct=None, warn=False):
    """One touch-sized list row. Returns its rect for hit-testing."""
    pygame.draw.rect(surf, THEME.panel, rect, border_radius=6)
    color = THEME.crit if warn else THEME.fg
    surf.blit(fonts["small"].render(left, True, color), (rect.x + 16, rect.y + 14))
    if right:
        t = fonts["small"].render(right, True, THEME.dim)
        surf.blit(t, (rect.right - t.get_width() - 16, rect.y + 14))
    if pct is not None:
        draw_bar(surf, pygame.Rect(rect.x + 16, rect.bottom - 12,
                                   rect.width - 32, 6), pct)
    return rect
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_theme.py -v`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add kw_dashboard/ui/theme.py kw_dashboard/ui/widgets.py tests/test_theme.py
git commit -m "feat: theme and drawing widgets"
```

---

## Task 12: App shell — pygame loop, touch, windowed and screenshot modes

Getting `--windowed` and `--screenshot` working here is what makes every later page task testable without the physical panel. Do not defer them.

**Files:**
- Create: `kw_dashboard/app.py`, `kw_dashboard/__main__.py`
- Create: `kw_dashboard/ui/pages/__init__.py` (empty)

**Interfaces:**
- Consumes: `Config`, `Collector`, `Nav`, `Theme`
- Produces: `App` with `.run()`, `.render_once(snapshot) -> pygame.Surface`; `load_fonts() -> dict`; page render functions registered as `render(surface, snapshot, nav, fonts) -> list[tuple[pygame.Rect, callable]]` returning hit regions

- [ ] **Step 1: Write the app shell**

```python
# kw_dashboard/app.py
"""pygame main loop on SDL2's KMSDRM backend. Renders from the collector's
snapshot; never performs I/O on this thread."""
from __future__ import annotations
import os, time
import pygame
from .config import Config
from .nav import Nav, View, PAGES
from .ui.theme import THEME, FONT_SIZES
from .sources.alerts import has_critical

FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
MONO_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"


def load_fonts() -> dict:
    pygame.font.init()
    f = {n: pygame.font.Font(FONT_PATH, s)
         for n, s in FONT_SIZES.items() if n != "mono"}
    f["mono"] = pygame.font.Font(MONO_PATH, FONT_SIZES["mono"])
    return f


class App:
    def __init__(self, cfg: Config, collector, windowed: bool = False):
        self.cfg, self.collector, self.windowed = cfg, collector, windowed
        self.nav = Nav(cfg.rotate_seconds, cfg.touch_pause_seconds,
                       cfg.idle_reset_seconds)
        self.hits: list = []
        self.log_stream = None
        self._alert_seen = False

    def _init_display(self):
        if not self.windowed:
            os.environ.setdefault("SDL_VIDEODRIVER", "kmsdrm")
        pygame.display.init()
        flags = 0 if self.windowed else pygame.FULLSCREEN
        self.screen = pygame.display.set_mode((self.cfg.width, self.cfg.height), flags)
        pygame.mouse.set_visible(False)
        self.fonts = load_fonts()

    def _dispatch_touch(self, pos, now: float):
        self.nav.touch(now)
        for rect, action in self.hits:
            if rect.collidepoint(pos):
                action()
                return

    def _check_preemption(self, snap, now: float):
        """A firing critical alert seizes the screen (spec section 7)."""
        crit = has_critical(snap.alerts)
        if crit and not self._alert_seen:
            self.nav.preempt_for_alert(now)
            self._alert_seen = True
        elif not crit:
            self._alert_seen = False

    def render_once(self, snap) -> pygame.Surface:
        from .ui.pages import registry
        self.screen.fill(THEME.bg)
        view = self.nav.current
        renderer = registry.get(view.kind, registry["cluster"])
        self.hits = renderer(self.screen, snap, self.nav, self.fonts, self) or []
        return self.screen

    def run(self):
        self._init_display()
        clock = pygame.time.Clock()
        running = True
        while running:
            now = time.time()
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT:
                    running = False
                elif ev.type == pygame.KEYDOWN and ev.key == pygame.K_ESCAPE:
                    running = False
                elif ev.type in (pygame.MOUSEBUTTONDOWN, pygame.FINGERDOWN):
                    if ev.type == pygame.FINGERDOWN:
                        pos = (int(ev.x * self.cfg.width), int(ev.y * self.cfg.height))
                    else:
                        pos = ev.pos
                    self._dispatch_touch(pos, now)
            snap = self.collector.snapshot()
            self._check_preemption(snap, now)
            self.nav.tick(now)
            self.render_once(snap)
            pygame.display.flip()
            clock.tick(self.cfg.fps)
        pygame.quit()
```

```python
# kw_dashboard/__main__.py
"""Entry point. --windowed and --screenshot exist so layout work never
requires the physical panel."""
from __future__ import annotations
import argparse, os, sys
from .config import load_config
from .collector import Collector
from .sources.prometheus import PrometheusClient
from .sources.kube import KubeClient
from .sources.alerts import AlertsClient


def read_token(path: str) -> str:
    try:
        return open(path).read().strip()
    except OSError:
        return ""


def main():
    ap = argparse.ArgumentParser(prog="kw-dashboard")
    ap.add_argument("--config", default="/etc/kw-dashboard/config.toml")
    ap.add_argument("--windowed", action="store_true",
                    help="run in a desktop window instead of KMSDRM")
    ap.add_argument("--screenshot", metavar="DIR",
                    help="render each page from fake data to PNGs and exit")
    args = ap.parse_args()

    cfg = load_config(args.config)

    if args.screenshot:
        from .fake import render_all_pages
        os.makedirs(args.screenshot, exist_ok=True)
        render_all_pages(cfg, args.screenshot)
        print(f"wrote screenshots to {args.screenshot}")
        return 0

    token = read_token(cfg.token_path)
    ca = cfg.ca_path if os.path.exists(cfg.ca_path) else None
    collector = Collector(
        cfg,
        PrometheusClient(cfg.prometheus_url, cfg.http_timeout_seconds),
        KubeClient(cfg.kube_url, token, ca, cfg.http_timeout_seconds),
        AlertsClient(cfg.alertmanager_url, cfg.http_timeout_seconds))
    collector.start()
    try:
        from .app import App
        App(cfg, collector, windowed=args.windowed).run()
    finally:
        collector.stop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Write the fake-data screenshot harness**

```python
# kw_dashboard/fake.py
"""Synthetic snapshots so pages can be rendered and reviewed off-device."""
from __future__ import annotations
import os, time
import pygame
from .model import Snapshot, NodeStat, NsStat
from .sources.alerts import Alert
from .sources.kube import EventInfo, PodInfo
from datetime import datetime, timezone


def fake_snapshot(with_alerts: bool = False) -> Snapshot:
    nodes = [
        NodeStat("master-11", True, True, 47.0, 31.0, 52.0, 18),
        NodeStat("master-12", True, False, 22.0, 40.0, 48.0, 14),
        NodeStat("master-13", True, False, 18.0, 35.0, 47.0, 12),
        NodeStat("worker-21", True, False, 71.0, 55.0, 61.0, 31),
        NodeStat("worker-22", True, False, 40.0, 44.0, 55.0, 27),
        NodeStat("worker-23", True, False, 33.0, 39.0, 53.0, 22),
        NodeStat("worker-24", False, False, 0.0, 0.0, None, 0),
        NodeStat("worker-25", True, False, 29.0, 48.0, 57.0, 25),
    ]
    ns = [NsStat("kube-system", 31, 0, 1.2, 4.9e9),
          NsStat("longhorn-system", 14, 0, 0.8, 6.3e9),
          NsStat("monitoring", 12, 0, 0.9, 3.4e9),
          NsStat("novaflow", 8, 1, 0.3, 8.9e8),
          NsStat("fastllm", 4, 0, 2.1, 6.2e9)]
    alerts = [Alert("NodeNotReady", "critical", "worker-24 is not ready",
                    datetime.now(timezone.utc))] if with_alerts else []
    events = [EventInfo("Started", "Started container app", "p1", "novaflow",
                        False, datetime.now(timezone.utc))]
    return Snapshot(cluster_cpu=37.0, cluster_mem=41.0, pods_running=176,
                    net_rx=1.2e7, net_tx=8.4e6, nodes=nodes, namespaces=ns,
                    alerts=alerts, events=events,
                    cpu_history=tuple(30 + 15 * (i % 7) / 7 for i in range(60)),
                    mem_history=tuple(40 + 5 * (i % 5) / 5 for i in range(60)),
                    updated={"prom": time.time(), "kube": time.time(),
                             "alerts": time.time()})


def render_all_pages(cfg, outdir: str):
    os.environ["SDL_VIDEODRIVER"] = "dummy"
    from .app import App
    from .nav import PAGES, View

    class _Stub:
        def __init__(self, s): self._s = s
        def snapshot(self): return self._s

    for name in PAGES:
        snap = fake_snapshot(with_alerts=(name == "alerts"))
        app = App(cfg, _Stub(snap), windowed=True)
        app._init_display()
        app.nav.jump_to_page(PAGES.index(name), now=time.time())
        surf = app.render_once(snap)
        pygame.image.save(surf, os.path.join(outdir, f"{name}.png"))
        pygame.display.quit()
```

- [ ] **Step 3: Verify the shell starts in windowed mode**

Run: `python3 -m kw_dashboard --windowed --config /dev/null`
Expected: a 1280x720 window opens showing the cluster page skeleton; Escape exits. (Pages land in Tasks 13-16; a mostly-empty screen here is correct.)

- [ ] **Step 4: Commit**

```bash
git add kw_dashboard/app.py kw_dashboard/__main__.py kw_dashboard/fake.py kw_dashboard/ui/pages/__init__.py
git commit -m "feat: app shell with KMSDRM, windowed and screenshot modes"
```

---

## Task 13: Page 1 (CLUSTER) and node detail

**Files:**
- Create: `kw_dashboard/ui/pages/cluster.py`, `kw_dashboard/ui/pages/node.py`
- Modify: `kw_dashboard/ui/pages/__init__.py` (add `registry`)

**Interfaces:**
- Consumes: `Snapshot`, `Nav`, widgets, `state_color`
- Produces: `render(surface, snap, nav, fonts, app) -> list[tuple[Rect, callable]]` for kinds `"cluster"` and `"node"`; `registry: dict[str, callable]`

- [ ] **Step 1: Write the cluster page**

```python
# kw_dashboard/ui/pages/cluster.py
"""Page 1: the default glanceable view. Two gauges, pod count, node strip."""
from __future__ import annotations
import time
import pygame
from ..theme import THEME, state_color
from ..widgets import draw_arc_gauge, draw_sparkline, draw_header
from ...nav import View, PAGES
from ...collector import is_stale


def render(surf, snap, nav, fonts, app):
    stale = is_stale(snap, "prom", limit=45)
    status = "STALE" if stale else ("ALERT" if snap.alerts else "OK")
    draw_header(surf, "KW CLUSTER", fonts,
                right_text=f"{time.strftime('%H:%M')}   {status}", stale=stale)

    draw_arc_gauge(surf, (250, 250), 110, snap.cluster_cpu, "CPU", fonts)
    draw_arc_gauge(surf, (560, 250), 110, snap.cluster_mem, "MEM", fonts)

    pods = fonts["huge"].render(str(snap.pods_running), True, THEME.fg)
    surf.blit(pods, pods.get_rect(center=(960, 220)))
    lab = fonts["small"].render("PODS RUNNING", True, THEME.dim)
    surf.blit(lab, lab.get_rect(center=(960, 300)))

    if snap.cpu_history:
        draw_sparkline(surf, pygame.Rect(140, 380, 220, 50),
                       list(snap.cpu_history), THEME.accent)
    if snap.mem_history:
        draw_sparkline(surf, pygame.Rect(450, 380, 220, 50),
                       list(snap.mem_history), THEME.accent)

    hits = []
    n = len(snap.nodes) or 1
    bw, gap = 128, 12
    total = n * bw + (n - 1) * gap
    x0 = (surf.get_width() - total) // 2
    for i, node in enumerate(snap.nodes):
        x = x0 + i * (bw + gap)
        rect = pygame.Rect(x, 470, bw, 90)   # >=60px touch target
        color = THEME.crit if not node.ready else state_color(node.worst_pct)
        pygame.draw.rect(surf, THEME.panel, rect, border_radius=6)
        fill_h = int(rect.height * min(100.0, node.worst_pct) / 100.0)
        if fill_h:
            pygame.draw.rect(surf, color, pygame.Rect(
                rect.x, rect.bottom - fill_h, rect.width, fill_h), border_radius=6)
        short = node.name.split("-")[-1]
        t = fonts["small"].render(short, True, THEME.fg)
        surf.blit(t, t.get_rect(center=(rect.centerx, rect.bottom + 24)))
        hits.append((rect, lambda nm=node.name: nav.push(
            View("node", {"node": nm}), now=time.time())))

    ready = sum(1 for x in snap.nodes if x.ready)
    summary = fonts["body"].render(f"{ready}/{len(snap.nodes)} nodes up", True, THEME.dim)
    surf.blit(summary, (surf.get_width() - summary.get_width() - 24, 620))

    for i, _ in enumerate(PAGES):
        c = THEME.accent if i == nav.page_index else THEME.panel
        pygame.draw.circle(surf, c, (560 + i * 30, 690), 7)
    return hits
```

- [ ] **Step 2: Write the node detail view**

```python
# kw_dashboard/ui/pages/node.py
"""Node detail, reached by tapping a node bar on page 1."""
from __future__ import annotations
import time
import pygame
from ..theme import THEME, state_color
from ..widgets import draw_bar, draw_back_button, draw_list_row, TOUCH_MIN_H
from ..sorting import sort_pods
from ...nav import View


def render(surf, snap, nav, fonts, app):
    name = nav.current.params.get("node", "")
    node = next((n for n in snap.nodes if n.name == name), None)
    hits = [(draw_back_button(surf, fonts), nav.pop)]

    title = fonts["body"].render(name, True, THEME.fg)
    surf.blit(title, (110, 18))
    if node is None:
        surf.blit(fonts["body"].render("node not found", True, THEME.dim), (110, 100))
        return hits

    state = "NOT READY" if not node.ready else ("CORDONED" if node.cordoned else "READY")
    col = THEME.crit if not node.ready else (THEME.warn if node.cordoned else THEME.ok)
    surf.blit(fonts["body"].render(state, True, col), (surf.get_width() - 280, 18))

    rows = [("CPU", node.cpu_pct, f"{node.cpu_pct:.0f}%"),
            ("MEMORY", node.mem_pct, f"{node.mem_pct:.0f}%"),
            ("TEMP", (node.temp_c or 0.0),
             f"{node.temp_c:.0f} C" if node.temp_c is not None else "n/a")]
    y = 90
    for label, pct, text in rows:
        surf.blit(fonts["small"].render(label, True, THEME.dim), (40, y))
        draw_bar(surf, pygame.Rect(200, y + 6, 700, 22), pct)
        surf.blit(fonts["small"].render(text, True, THEME.fg), (930, y))
        y += 56

    surf.blit(fonts["small"].render(f"{node.pods} pods", True, THEME.dim), (40, y + 6))

    pods = sort_pods([p for p in getattr(snap, "pods", []) if p.node == name])[:5]
    y += 50
    for p in pods:
        rect = pygame.Rect(40, y, surf.get_width() - 80, TOUCH_MIN_H)
        draw_list_row(surf, rect, f"{p.namespace}/{p.name}",
                      f"{p.ready}/{p.total}", fonts, warn=not p.healthy)
        hits.append((rect, lambda ns=p.namespace, pn=p.name: nav.push(
            View("pod", {"ns": ns, "pod": pn}), now=time.time())))
        y += TOUCH_MIN_H + 8
    return hits
```

- [ ] **Step 3: Register both in the page registry**

```python
# kw_dashboard/ui/pages/__init__.py
from . import cluster, node

registry = {
    "cluster": cluster.render,
    "node": node.render,
}
```

- [ ] **Step 4: Render a screenshot and inspect it**

Run: `python3 -m kw_dashboard --screenshot /tmp/shots --config /dev/null && ls /tmp/shots`
Expected: `cluster.png` exists at 1280x720. Open it and confirm the gauges, pod count and eight node bars render, and that `worker-24` (not ready in fake data) is red.

- [ ] **Step 5: Commit**

```bash
git add kw_dashboard/ui/pages/
git commit -m "feat: cluster page and node detail view"
```

---

## Task 14: Page 4 (ALERTS) and page 2 (PULSE)

**Files:**
- Create: `kw_dashboard/ui/pages/alerts.py`, `kw_dashboard/ui/pages/pulse.py`
- Modify: `kw_dashboard/ui/pages/__init__.py`

**Interfaces:**
- Consumes: `Snapshot.alerts`, `Snapshot.events`, `Snapshot.net_rx/net_tx`
- Produces: `render(...)` for kinds `"alerts"` and `"pulse"`

- [ ] **Step 1: Write the alerts page**

```python
# kw_dashboard/ui/pages/alerts.py
"""Page 4: calm when clear, ranked list when firing."""
from __future__ import annotations
import time
import pygame
from ..theme import THEME
from ..widgets import draw_header, TOUCH_MIN_H

SEV_COLOR = {"critical": THEME.crit, "warning": THEME.warn, "info": THEME.accent}


def render(surf, snap, nav, fonts, app):
    draw_header(surf, "ALERTS", fonts, right_text=time.strftime("%H:%M"))
    hits = []
    if not snap.alerts:
        t = fonts["big"].render("all quiet", True, THEME.ok)
        surf.blit(t, t.get_rect(center=(surf.get_width() // 2, 320)))
        s = fonts["small"].render("no alerts firing", True, THEME.dim)
        surf.blit(s, s.get_rect(center=(surf.get_width() // 2, 390)))
        return hits

    y = 90
    for a in snap.alerts[:6]:
        rect = pygame.Rect(30, y, surf.get_width() - 60, TOUCH_MIN_H + 18)
        pygame.draw.rect(surf, THEME.panel, rect, border_radius=6)
        pygame.draw.rect(surf, SEV_COLOR.get(a.severity, THEME.dim),
                         pygame.Rect(rect.x, rect.y, 8, rect.height), border_radius=4)
        surf.blit(fonts["body"].render(a.name, True, THEME.fg), (rect.x + 26, rect.y + 8))
        surf.blit(fonts["small"].render(a.summary[:64], True, THEME.dim),
                  (rect.x + 26, rect.y + 44))
        y += TOUCH_MIN_H + 26

    # Acknowledging clears pre-emption so rotation can resume.
    ack = pygame.Rect(surf.get_width() - 220, 640, 190, TOUCH_MIN_H)
    pygame.draw.rect(surf, THEME.panel, ack, border_radius=6)
    surf.blit(fonts["small"].render("ACKNOWLEDGE", True, THEME.accent),
              (ack.x + 18, ack.y + 16))
    hits.append((ack, lambda: nav.clear_preempt(time.time())))
    return hits
```

- [ ] **Step 2: Write the pulse page**

```python
# kw_dashboard/ui/pages/pulse.py
"""Page 2: the cluster-is-alive view. Throughput plus a rolling event feed."""
from __future__ import annotations
import time
import pygame
from ..theme import THEME
from ..widgets import draw_header, draw_sparkline
from ..sorting import fmt_bytes


def render(surf, snap, nav, fonts, app):
    draw_header(surf, "PULSE", fonts, right_text=time.strftime("%H:%M"))

    for i, (label, val) in enumerate((("NET RX", snap.net_rx), ("NET TX", snap.net_tx))):
        x = 80 + i * 340
        t = fonts["big"].render(f"{fmt_bytes(val)}/s", True, THEME.fg)
        surf.blit(t, (x, 90))
        surf.blit(fonts["small"].render(label, True, THEME.dim), (x, 160))

    restarts = sum(1 for e in snap.events if e.warning)
    t = fonts["big"].render(str(restarts), True,
                            THEME.warn if restarts else THEME.ok)
    surf.blit(t, (760, 90))
    surf.blit(fonts["small"].render("WARN EVENTS", True, THEME.dim), (760, 160))

    if snap.cpu_history:
        draw_sparkline(surf, pygame.Rect(80, 210, surf.get_width() - 160, 60),
                       list(snap.cpu_history), THEME.accent)

    surf.blit(fonts["small"].render("RECENT EVENTS", True, THEME.dim), (80, 300))
    y = 340
    for e in snap.events[:6]:
        color = THEME.warn if e.warning else THEME.dim
        line = f"{e.reason}  {e.namespace}/{e.obj}"
        surf.blit(fonts["small"].render(line[:58], True, color), (80, y))
        y += 40
    return []
```

- [ ] **Step 3: Register both**

```python
# kw_dashboard/ui/pages/__init__.py
from . import cluster, node, alerts, pulse

registry = {
    "cluster": cluster.render,
    "node": node.render,
    "alerts": alerts.render,
    "pulse": pulse.render,
}
```

- [ ] **Step 4: Screenshot and inspect**

Run: `python3 -m kw_dashboard --screenshot /tmp/shots --config /dev/null`
Expected: `alerts.png` shows the critical `NodeNotReady` alert from fake data with a red severity stripe; `pulse.png` shows throughput and the event feed.

- [ ] **Step 5: Commit**

```bash
git add kw_dashboard/ui/pages/
git commit -m "feat: alerts and pulse pages"
```

---

## Task 15: Page 3 (EXPLORE) — namespace, pod and log views

**Files:**
- Create: `kw_dashboard/ui/pages/explore.py`, `kw_dashboard/ui/pages/logs.py`
- Modify: `kw_dashboard/ui/pages/__init__.py`, `kw_dashboard/app.py` (add on-demand pod/log fetch hook)

**Interfaces:**
- Consumes: `sort_namespaces`, `sort_pods`, `fmt_bytes`, `LogStream`, `KubeClient.list_pods`, `KubeClient.pod_log`
- Produces: `render(...)` for kinds `"explore"`, `"namespace"`, `"pod"`, `"logs"`; `App.fetch_pods(ns)` and `App.fetch_logs(ns, pod, container)` which run off-thread and cache into `App.view_cache`

- [ ] **Step 1: Add the on-demand fetch hook to App**

Drill-down data is fetched only when a view is opened, and never on the render thread. Add to `kw_dashboard/app.py`:

```python
    # --- add inside class App ---
    def _ensure_cache(self):
        if not hasattr(self, "view_cache"):
            self.view_cache = {}
            self._inflight = set()

    def fetch_pods(self, ns: str):
        """Fetch pods for a namespace in a worker thread; cache the result."""
        import threading
        self._ensure_cache()
        key = ("pods", ns)
        if key in self.view_cache or key in self._inflight:
            return self.view_cache.get(key)
        self._inflight.add(key)

        def work():
            try:
                self.view_cache[key] = self.collector.kube.list_pods(ns)
            except Exception as e:
                self.view_cache[key] = []
                self.view_cache[("err", ns)] = str(e)
            finally:
                self._inflight.discard(key)

        threading.Thread(target=work, daemon=True).start()
        return None

    def fetch_logs(self, ns: str, pod: str, container: str | None):
        import threading
        from .logstream import LogStream
        self._ensure_cache()
        key = ("logs", ns, pod, container)
        if key in self._inflight:
            return self.view_cache.get(key)
        if key not in self.view_cache:
            self.view_cache[key] = LogStream(ring_size=self.cfg.log_ring_size)
        stream = self.view_cache[key]
        self._inflight.add(key)

        def work():
            try:
                lines = self.collector.kube.pod_log(
                    ns, pod, container, tail=self.cfg.log_tail_lines)
                stream.append_lines(lines[-self.cfg.log_tail_lines:])
            except Exception as e:
                stream.append_lines([f"[log unavailable: {e}]"])
            finally:
                self._inflight.discard(key)

        threading.Thread(target=work, daemon=True).start()
        return stream
```

Also add `self.kube = kube` to `Collector.__init__` — it is already stored as `self.kube`, so no change is needed; verify it is accessible as `collector.kube`.

- [ ] **Step 2: Write the explorer views**

```python
# kw_dashboard/ui/pages/explore.py
"""Page 3: generic namespace -> pod explorer. Nothing app-specific; every
workload is discovered from the API."""
from __future__ import annotations
import time
import pygame
from ..theme import THEME, state_color
from ..widgets import (draw_header, draw_list_row, draw_back_button,
                       draw_bar, TOUCH_MIN_H)
from ..sorting import sort_namespaces, sort_pods, fmt_bytes
from ...nav import View

ROW_H = TOUCH_MIN_H + 8
LIST_TOP = 80


def _rows_visible(surf) -> int:
    return (surf.get_height() - LIST_TOP - 20) // ROW_H


def render_namespaces(surf, snap, nav, fonts, app):
    draw_header(surf, "NAMESPACES", fonts, right_text=str(len(snap.namespaces)))
    hits = []
    items = sort_namespaces(snap.namespaces)[: _rows_visible(surf)]
    y = LIST_TOP
    for ns in items:
        rect = pygame.Rect(30, y, surf.get_width() - 60, TOUCH_MIN_H)
        right = f"{ns.pods} pods   {fmt_bytes(ns.mem_bytes)}"
        draw_list_row(surf, rect, ns.name, right, fonts, warn=bool(ns.unhealthy))
        hits.append((rect, lambda n=ns.name: (
            app.fetch_pods(n), nav.push(View("namespace", {"ns": n}), now=time.time()))))
        y += ROW_H
    return hits


def render_namespace(surf, snap, nav, fonts, app):
    ns = nav.current.params.get("ns", "")
    hits = [(draw_back_button(surf, fonts), nav.pop)]
    surf.blit(fonts["body"].render(ns, True, THEME.fg), (110, 18))

    app._ensure_cache()
    pods = app.view_cache.get(("pods", ns))
    if pods is None:
        app.fetch_pods(ns)
        surf.blit(fonts["small"].render("loading...", True, THEME.dim), (30, LIST_TOP))
        return hits

    y = LIST_TOP
    for p in sort_pods(pods)[: _rows_visible(surf)]:
        rect = pygame.Rect(30, y, surf.get_width() - 60, TOUCH_MIN_H)
        right = f"{p.ready}/{p.total}  {p.restarts}R  {p.phase}"
        draw_list_row(surf, rect, p.name[:40], right, fonts, warn=not p.healthy)
        hits.append((rect, lambda pn=p.name: nav.push(
            View("pod", {"ns": ns, "pod": pn}), now=time.time())))
        y += ROW_H
    return hits


def render_pod(surf, snap, nav, fonts, app):
    ns = nav.current.params.get("ns", "")
    name = nav.current.params.get("pod", "")
    hits = [(draw_back_button(surf, fonts), nav.pop)]
    surf.blit(fonts["body"].render(f"{ns}/{name}"[:44], True, THEME.fg), (110, 18))

    app._ensure_cache()
    pods = app.view_cache.get(("pods", ns)) or []
    pod = next((p for p in pods if p.name == name), None)
    if pod is None:
        surf.blit(fonts["small"].render("pod not found", True, THEME.dim), (30, LIST_TOP))
        return hits

    facts = [("PHASE", pod.phase), ("READY", f"{pod.ready}/{pod.total}"),
             ("RESTARTS", str(pod.restarts)), ("NODE", pod.node)]
    y = LIST_TOP
    for label, value in facts:
        surf.blit(fonts["small"].render(label, True, THEME.dim), (40, y))
        color = THEME.crit if label == "RESTARTS" and pod.restarts > 0 else THEME.fg
        surf.blit(fonts["small"].render(value, True, color), (280, y))
        y += 46

    y += 10
    for c in pod.containers[:3]:
        rect = pygame.Rect(30, y, surf.get_width() - 60, TOUCH_MIN_H)
        draw_list_row(surf, rect, f"logs: {c}", ">", fonts)
        hits.append((rect, lambda cn=c: (
            app.fetch_logs(ns, name, cn),
            nav.push(View("logs", {"ns": ns, "pod": name, "container": cn}),
                     now=time.time()))))
        y += ROW_H
    return hits


def render(surf, snap, nav, fonts, app):
    return render_namespaces(surf, snap, nav, fonts, app)
```

```python
# kw_dashboard/ui/pages/logs.py
"""Log view. Deliberately uses 20px monospace, below the 26px glanceable
floor: logs are a lean-in activity and 26px fits only ~78 columns (spec 8)."""
from __future__ import annotations
import pygame
from ..theme import THEME
from ..widgets import draw_back_button, TOUCH_MIN_H
from ...logstream import wrap_line


def render(surf, snap, nav, fonts, app):
    p = nav.current.params
    ns, pod, container = p.get("ns", ""), p.get("pod", ""), p.get("container")
    hits = [(draw_back_button(surf, fonts), nav.pop)]
    surf.blit(fonts["small"].render(f"{pod}/{container}"[:48], True, THEME.fg), (110, 24))

    app._ensure_cache()
    stream = app.view_cache.get(("logs", ns, pod, container))
    if stream is None:
        stream = app.fetch_logs(ns, pod, container)
        surf.blit(fonts["small"].render("loading...", True, THEME.dim), (30, 90))
        return hits

    mono = fonts["mono"]
    char_w = mono.size("M")[0] or 11
    cols = max(20, (surf.get_width() - 60) // char_w)
    line_h = mono.get_linesize()
    rows = (surf.get_height() - 130) // line_h

    wrapped: list[str] = []
    for ln in stream.visible(rows=rows):
        wrapped.extend(wrap_line(ln, cols))
    wrapped = wrapped[-rows:]

    y = 80
    for ln in wrapped:
        surf.blit(mono.render(ln, True, THEME.fg), (30, y))
        y += line_h

    up = pygame.Rect(surf.get_width() - 200, surf.get_height() - 70, 90, TOUCH_MIN_H)
    live = pygame.Rect(surf.get_width() - 100, surf.get_height() - 70, 90, TOUCH_MIN_H)
    for rect, label, color in ((up, "^", THEME.accent),
                               (live, "LIVE",
                                THEME.ok if stream.follow else THEME.dim)):
        pygame.draw.rect(surf, THEME.panel, rect, border_radius=6)
        surf.blit(fonts["small"].render(label, True, color), (rect.x + 14, rect.y + 16))
    hits.append((up, lambda: stream.scroll_up(rows // 2)))
    hits.append((live, stream.jump_to_live))
    return hits
```

- [ ] **Step 3: Register the new kinds**

```python
# kw_dashboard/ui/pages/__init__.py
from . import cluster, node, alerts, pulse, explore, logs

registry = {
    "cluster": cluster.render,
    "node": node.render,
    "alerts": alerts.render,
    "pulse": pulse.render,
    "explore": explore.render,
    "namespace": explore.render_namespace,
    "pod": explore.render_pod,
    "logs": logs.render,
}
```

- [ ] **Step 4: Verify the whole suite still passes and screenshot the explorer**

Run: `pytest -v && python3 -m kw_dashboard --screenshot /tmp/shots --config /dev/null`
Expected: all tests pass; `explore.png` shows the namespace list with `novaflow` (1 unhealthy pod in fake data) sorted to the top.

- [ ] **Step 5: Commit**

```bash
git add kw_dashboard/ui/pages/ kw_dashboard/app.py
git commit -m "feat: generic namespace/pod explorer with log view"
```

---

## Task 16: RBAC, systemd unit, and install script

Use the DRM result recorded in Task 1 to decide `User=`. If `piwi` acquired DRM master, keep `User=piwi`; if not, drop the `User=`/`Group=` lines so it runs as root and note the reason in the unit file.

**Files:**
- Create: `deploy/rbac.yaml`, `deploy/kw-dashboard.service`, `deploy/install.sh`

**Interfaces:**
- Consumes: everything above
- Produces: a deployed, running unit on km01

- [ ] **Step 1: Write the RBAC manifest**

```yaml
# deploy/rbac.yaml
# Read-only access. The built-in `view` ClusterRole already grants get on
# pods/log, which the explorer needs, and grants no write verbs.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kw-dashboard
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kw-dashboard-view
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
  - kind: ServiceAccount
    name: kw-dashboard
    namespace: monitoring
---
apiVersion: v1
kind: Secret
metadata:
  name: kw-dashboard-token
  namespace: monitoring
  annotations:
    kubernetes.io/service-account.name: kw-dashboard
type: kubernetes.io/service-account-token
```

- [ ] **Step 2: Write the systemd unit**

```ini
# deploy/kw-dashboard.service
[Unit]
Description=kw-dashboard on the HDMI panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=piwi
Group=piwi
SupplementaryGroups=video render input tty
Environment=SDL_VIDEODRIVER=kmsdrm
Environment=PYTHONUNBUFFERED=1
WorkingDirectory=/opt/kw-dashboard
ExecStart=/usr/bin/python3 -m kw_dashboard --config /etc/kw-dashboard/config.toml
Restart=always
RestartSec=5
# Bound to a dedicated VT so it never contends with the console on tty1.
TTYPath=/dev/tty2
StandardInput=tty
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 3: Write the install script**

```bash
#!/usr/bin/env bash
# deploy/install.sh — deploy kw-dashboard to km01.
set -euo pipefail

NODE="${NODE:-192.168.10.101}"
USER="${USER_NAME:-piwi}"

echo "==> installing apt dependencies"
ssh "$USER@$NODE" 'sudo apt-get update -qq && sudo apt-get install -y python3-pygame fonts-dejavu-core'

echo "==> applying RBAC"
kubectl apply -f deploy/rbac.yaml

echo "==> extracting service account token"
TOKEN=$(kubectl -n monitoring get secret kw-dashboard-token -o jsonpath='{.data.token}' | base64 -d)

echo "==> copying application"
ssh "$USER@$NODE" 'sudo mkdir -p /opt/kw-dashboard /etc/kw-dashboard && sudo chown -R '"$USER"' /opt/kw-dashboard'
rsync -a --delete kw_dashboard "$USER@$NODE:/opt/kw-dashboard/"

echo "==> installing token (0400, owned by $USER)"
ssh "$USER@$NODE" "sudo tee /etc/kw-dashboard/token >/dev/null <<<'$TOKEN' && sudo chown $USER /etc/kw-dashboard/token && sudo chmod 400 /etc/kw-dashboard/token"

echo "==> installing config"
ssh "$USER@$NODE" 'sudo tee /etc/kw-dashboard/config.toml >/dev/null <<EOF
# Touch calibration: set from tools/probe_hardware.py output.
[touch]
swap_xy = false
invert_x = false
invert_y = false
EOF'

echo "==> installing systemd unit"
scp deploy/kw-dashboard.service "$USER@$NODE:/tmp/"
ssh "$USER@$NODE" 'sudo mv /tmp/kw-dashboard.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now kw-dashboard'

echo "==> status"
ssh "$USER@$NODE" 'sudo systemctl --no-pager status kw-dashboard | head -20'
```

- [ ] **Step 4: Deploy and verify on the panel**

```bash
chmod +x deploy/install.sh
./deploy/install.sh
ssh piwi@192.168.10.101 'journalctl -u kw-dashboard -n 40 --no-pager'
```

Expected: unit is `active (running)`, no traceback in the journal, and **the dashboard is visible on the physical panel**. Confirm pages rotate every 15 s.

- [ ] **Step 5: Verify touch and calibrate**

Tap a node bar on page 1. If the wrong node opens, or nothing responds, set `swap_xy` / `invert_x` / `invert_y` in `/etc/kw-dashboard/config.toml` using the ranges from Task 1 and restart the unit. Iterate until taps land where expected. Record the working values in `docs/hardware-findings.md`.

- [ ] **Step 6: Commit**

```bash
git add deploy/ docs/hardware-findings.md
git commit -m "feat: RBAC, systemd unit and install script"
```

---

## Self-Review Notes

**Spec coverage check:**

| Spec section | Covered by |
|---|---|
| 2 Target hardware | Task 1 (probe), Task 2 (720p defaults) |
| 3 Rendering (pygame/KMSDRM) | Task 12 |
| 4 Deployment (systemd, not pod) | Task 16 |
| 5 Process architecture (2 threads) | Task 7 |
| 6 Data sources + auth + staleness | Tasks 3-7, 16 (RBAC) |
| 6 Logs via k8s API, Loki optional | Task 5 (`pod_log`), Task 9, Task 15. Loki left unimplemented behind `loki_enabled=False` — it is spec'd as optional and follows the API path. |
| 7 Pages 1-4 + alert pre-emption | Tasks 13, 14, 15; pre-emption in Task 12 `_check_preemption` + Task 8 `preempt_for_alert` |
| 8 Navigation, drill-down, log legibility | Tasks 8, 11 (`FONT_SIZES`), 15 |
| 9 Visual direction | Task 11 (dataviz skill required) |
| 10 Error handling | Task 7 (per-source `_mark`), Task 16 (`Restart=always`) |
| 11 Testing | Tasks 2-11 unit tests; Task 12 screenshot mode; Task 16 on-device smoke |
| 12 Risks | Task 1 (all three), Task 16 step 5 (calibration) |
| 13 Out of scope | No mutating call exists anywhere; `kube.py` exposes GET only |

**Deferred deliberately:** live log `follow=true` streaming (Task 15 fetches a
bounded tail on view open and on refresh; the `LogStream` follow machinery from
Task 9 already supports continuous append when streaming is added). Loki
history. Both are spec'd as optional or secondary.
