# kw-dashboard — Design

**Date:** 2026-08-16
**Status:** Approved for planning

A native, always-on dashboard rendered directly to the HDMI touch panel attached
to `km01` (Kubernetes node `master-11`) in the kw k3s cluster. No browser, no
Grafana UI, no X11, no Wayland.

## 1. Goal

A glanceable panel that answers, without anyone touching it: is the cluster
healthy, is it alive, are my apps working, is anything on fire. Touch adds
override and drill-down for when someone is standing in front of it.

It is **not** a Grafana replacement. Grafana already exists at
`grafana.kw.local` for investigation and ad-hoc querying. This is the
always-visible summary.

## 2. Target hardware

Verified on the node, 2026-08-16.

| Property | Value |
|---|---|
| Host | `km01`, Kubernetes node `master-11`, `192.168.10.101` |
| SoC | Rockchip RK3588, 8 cores, aarch64 |
| RAM | 30 GiB |
| OS | Armbian 26.2.1 (Ubuntu 24.04 noble), kernel 6.12.58-current-rockchip64 |
| Display | HDMI-A-1 connected, `/dev/fb0`, **1280x720** preferred (1920x1080 also offered) |
| Panel | Realtek scaler, EDID model `RTK 9Cun` — a ~9 inch panel. EDID's 597x336 mm physical size is generic-scaler garbage and must be ignored. |
| GPU | Mali-G610, `panthor` driver, `/dev/dri/card1` + `renderD128`. No GL/Vulkan userspace installed; Mesa 25.2.8 available in apt. |
| Touch | `ILITEK-TOUCH`, USB `222a:0001` behind a Genesys hub, `/dev/input/event5` + `mouse0` |
| Other input | `gpio_ir_recv` (IR), `adc-keys-0/1` (board buttons) — **not used**, noted only so they are not mistaken for the touch device |
| Node state | Cordoned (`SchedulingDisabled`) |
| Service user | `piwi`, already in groups `video`, `render`, `input`, `tty` |

**Effective pixel density:** the panel is roughly 200 mm wide at 1280 px, so
about **6.4 px/mm**. At a ~1 m viewing distance this sets a hard floor of
~26 px for body text and ~96-140 px for headline figures. This constraint,
not aesthetics, is what forces low information density per page.

## 3. Rendering approach

**Python 3.12 + pygame 2.5.2 on SDL2's KMSDRM backend** (`SDL_VIDEODRIVER=kmsdrm`).

Draws straight to DRM with no display server. Chosen over the two alternatives:

- *TUI on the framebuffer console* — less code and very robust, but cannot
  reach the visual quality asked for.
- *Direct DRM + cairo* — same visual ceiling as pygame, but requires
  hand-rolled modesetting, dumb-buffer allocation, page flipping, vblank
  handling and damage tracking before the first dashboard pixel is drawn.

All dependencies are apt packages (`python3-pygame`, `libsdl2-2.0-0`,
`fonts-dejavu-core`). No pip, no venv, no build step.

Mali GL is **not** required: at 720p the software path is sufficient. Mesa may
be added later if effects warrant it.

## 4. Deployment

**A systemd unit on the node, not a Kubernetes pod.**

The decisive reason: a dashboard whose purpose is reporting cluster health must
survive the cluster being broken. A pod-based dashboard goes black precisely
when it is most needed. Secondary reasons: `master-11` is cordoned, so a pod
would need tolerations plus `nodeName` pinning, plus privileged hostPath mounts
for `/dev/dri` and `/dev/input`.

Accepted cost: deployment is a script over SSH rather than GitOps.

- Unit runs as `piwi` (already in `video`, `render`, `input`, `tty`).
- Bound to a **dedicated VT**, not `tty1`, so it never contends with the
  console. Console blanking disabled on that VT.
- `Restart=always` with backoff. Logs to journald.

## 5. Process architecture

One Python process, two threads, sharing an immutable snapshot.

```
┌─────────────────┐   writes    ┌──────────────┐   reads   ┌────────────────┐
│ Collector thread│ ──────────► │  Snapshot    │ ────────► │ Render thread  │
│ Prom/Alerts/API │  (lock)     │  (dataclass) │  (lock)   │ pygame + touch │
└─────────────────┘             └──────────────┘           └────────────────┘
```

- **Collector thread** — polls each source on its own independent interval,
  builds a new immutable snapshot, swaps it under a lock. Slow or hung sources
  never block rendering.
- **Render thread** — pygame main loop at a fixed modest FPS. Reads the current
  snapshot, draws, handles touch events.

A hung Prometheus must degrade to stale-but-drawn numbers, never a frozen or
blank screen.

## 6. Data sources

All verified reachable from the node.

| Source | Address | Latency | Used for |
|---|---|---|---|
| Prometheus | `10.43.125.146:9090` | 7 ms | node CPU/RAM/temp, pod counts, rates, sparkline history |
| Alertmanager | `10.43.225.33:9093` | — | firing alerts |
| k3s API | `127.0.0.1:6443` | — | node conditions, pod and event drill-down |

Prometheus is `kube-prometheus-stack` with node-exporter on all 8 nodes and
kube-state-metrics. 2739 metric names available.

**Cluster shape:** 8 nodes — `master-11/12/13` (control-plane, `master-11`
cordoned) and `worker-21..25`, all at `192.168.10.101-108`.

### Authentication

A dedicated read-only ServiceAccount bound to a `view`-scoped ClusterRole. Its
token is written to `/etc/kw-dashboard/token`, mode `0400`, owned by `piwi`.

Root's `/etc/rancher/k3s/k3s.yaml` is **not** used — it is cluster-admin
credentials and inappropriate for a display process.

### Staleness

Every panel tracks the age of the data behind it. Past a threshold the panel
visibly greys out and displays that age. A dashboard confidently showing
five-minute-old numbers is worse than one admitting it lost contact.

## 7. Pages

Four pages. Each gets **one idea and a handful of large figures** — the pixel
density budget in section 2 permits nothing denser.

Idle behaviour: pages auto-rotate on a timer (default 15 s per page, and all
timing values in this section are configurable). Touch overrides and pauses
rotation for ~60 s, after which rotation resumes.

### Page 1 — CLUSTER (default; the page idle rotation returns to)

```
┌──────────────────────────────────────────────┐
│ KW CLUSTER                    14:32    ● OK  │
│                                              │
│   ╭─────╮        ╭─────╮        142          │
│   │ 47% │        │ 31% │        PODS         │
│   ╰─────╯        ╰─────╯        running      │
│    CPU            MEM                        │
│   ▁▂▃▅▇▅▃▂▁▂▃▅    ▁▁▂▂▃▃▂▂▁▁▂▂                │
│                                              │
│  ██ ██ ██ ██ ██ ██ ██ ██     8/8 nodes up    │
│  11 12 13 21 22 23 24 25                     │
│                    ● ○ ○ ○                   │
└──────────────────────────────────────────────┘
```

Eight node bars along the bottom, each coloured by worst-of(CPU, memory,
temperature, node condition). Tapping one opens the node drill-down.

### Page 2 — PULSE

The "cluster is alive" page: pod churn (starts, restarts, terminations per
minute), aggregate network throughput, and a short rolling feed of recent
Kubernetes events. Motion is the point — this is the page that makes an
always-on screen worth glancing at.

### Page 3 — APPS

Two-tier by necessity, because instrumentation is uneven.

**Tier 1 — apps exporting real metrics:**

| App | Metrics | Surface on the panel |
|---|---|---|
| `novaflow` | 22 (PodMonitor) | LLM requests + tokens, turns, tool calls, dreamloop runs, lessons recalled, turn duration |
| `novamail` | 11 (ServiceMonitor) | ingress accepted/rejected, delivery relayed/deferred/failed, DSN bounced/suppressed |
| `zot` | 21 | HTTP request rate, repo storage bytes, uploads/downloads |
| `openfga` | 19 | check cache hit rate, evaluation duration |

**Tier 2 — apps exporting nothing:** `fastllm`, `novachess`, `novamem` have no
Prometheus metrics. They are shown via kube-state-metrics only: replica
health, ready/desired, restart counts, age.

Tier 2 is displayed as a distinct, visibly less-detailed row so the difference
reads as "not instrumented", not as "healthy and quiet".

Tapping an app opens the app drill-down.

### Page 4 — ALERTS

Near-empty and calm when clear: "all quiet" plus the last-incident timestamp.
When alerts fire, a list ranked by severity.

**Alerts pre-empt rotation.** A firing critical alert seizes the screen
regardless of the current page and halts the carousel until acknowledged by
touch. An alert you must wait 45 seconds for the carousel to reach is not an
alert.

## 8. Drill-down

Tapping a node (page 1) or an app (page 3) opens a detail view with a back
affordance.

A detail view returns to normal rotation after ~2 minutes without touch, so the
panel is never stranded on a drill-down after someone walks away.

Depth is one level only. No nested navigation stack.

## 9. Visual direction

- Dark background — it is an always-on panel in a room.
- One accent hue for the normal state. Warning and critical hues are reserved
  **exclusively** for state, so colour always carries meaning.
- Generous whitespace; density is capped by the legibility floor, not by taste.
- A single sans family at three or four sizes.

Exact palette values, contrast ratios and chart specifications are deliberately
**not** fixed here. They will be derived at implementation time using the
`dataviz` skill, including colour-blind safety checks.

## 10. Error handling

- Each data source fails independently. One dead source dims only its own
  panels; the others keep updating.
- `Restart=always` with backoff.
- Unhandled exceptions log to journald and restart the unit rather than leaving
  a half-drawn screen.
- Network calls have explicit timeouts. The collector never retries in a tight
  loop.

## 11. Testing

- **Data layer** — PromQL response parsing, unit conversion, staleness logic and
  alert severity ranking are pure functions, tested off-device against recorded
  API fixtures. No cluster required.
- **Rendering** — a `--windowed` mode for development on a workstation, plus an
  offline screenshot mode that renders PNGs from synthetic snapshots. Layout
  work must not require the physical panel.
- **On-device** — a smoke check that the unit starts, acquires DRM, and draws.

## 12. Risks to resolve first, in order

1. **DRM master as non-root.** Whether `piwi` can acquire DRM master under
   logind on a dedicated VT. Fallback: a root-owned unit, or granting the
   needed capability.
2. **Touch orientation and calibration.** The ILITEK panel's axis order and
   polarity are unverified. Cheap panels routinely report flipped, swapped or
   offset axes.
   **A calibration and rotation config knob ships regardless of what the first
   test shows.** No amount of clean code detects a miscalibrated digitiser;
   physical hardware needs a tuning path that a minimal model cannot infer.
3. **VT contention.** Confirm the chosen VT does not fight `fbcon` or getty.

## 13. Explicitly out of scope

- Historical time-range picker
- Ad-hoc querying
- Configuration UI
- Multi-cluster support
- Nested navigation beyond one drill-down level
- Authentication or any user accounts on the panel itself
