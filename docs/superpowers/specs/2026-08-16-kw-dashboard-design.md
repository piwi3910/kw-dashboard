# kw-dashboard — Design

**Date:** 2026-08-16
**Status:** Approved for planning

A native, always-on dashboard rendered directly to the HDMI touch panel attached
to `km01` (Kubernetes node `master-11`) in the kw k3s cluster. No browser, no
Grafana UI, no X11, no Wayland.

## 1. Goal

A glanceable panel that answers, without anyone touching it: is the cluster
healthy, is it alive, what is running, is anything on fire.

Touch turns it into a **generic Kubernetes explorer** — drill from namespace to
pod to container, see metrics and logs for anything in the cluster. Nothing
about it is app-specific: workloads are discovered from the API, never
configured.

It is **not** a Grafana replacement. Grafana already exists at
`grafana.kw.local` for investigation and ad-hoc querying. This is the
always-visible summary.

## 2. Target hardware

Verified on the node, 2026-08-16.

| Property     | Value                                                                                                                                   |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| Host         | `km01`, Kubernetes node `master-11`, `192.168.10.101`                                                                                   |
| SoC          | Rockchip RK3588, 8 cores, aarch64                                                                                                       |
| RAM          | 30 GiB                                                                                                                                  |
| OS           | Armbian 26.2.1 (Ubuntu 24.04 noble), kernel 6.12.58-current-rockchip64                                                                  |
| Display      | HDMI-A-1 connected, `/dev/fb0`, **1280x720** — confirmed correct for this 9" panel; 1920x1080 is offered but explicitly not used        |
| Panel        | Realtek scaler, EDID model `RTK 9Cun` — a ~9 inch panel. EDID's 597x336 mm physical size is generic-scaler garbage and must be ignored. |
| GPU          | Mali-G610, `panthor` driver, `/dev/dri/card1` + `renderD128`. No GL/Vulkan userspace installed; Mesa 25.2.8 available in apt.           |
| Touch        | `ILITEK-TOUCH`, USB `222a:0001` behind a Genesys hub, `/dev/input/event5` + `mouse0`                                                    |
| Other input  | `gpio_ir_recv` (IR), `adc-keys-0/1` (board buttons) — **not used**, noted only so they are not mistaken for the touch device            |
| Node state   | Cordoned (`SchedulingDisabled`)                                                                                                         |
| Service user | `piwi`, already in groups `video`, `render`, `input`, `tty`                                                                             |

**Effective pixel density:** the panel is roughly 200 mm wide at 1280 px, so
about **6.4 px/mm**. At a ~1 m viewing distance this sets a hard floor of
~26 px for body text and ~96-140 px for headline figures. This constraint,
not aesthetics, is what forces low information density per page.

## 3. Rendering approach

**Python 3.12 + pygame 2.5.2 on SDL2's KMSDRM backend** (`SDL_VIDEODRIVER=kmsdrm`).

Draws straight to DRM with no display server. Chosen over the two alternatives:

- _TUI on the framebuffer console_ — less code and very robust, but cannot
  reach the visual quality asked for.
- _Direct DRM + cairo_ — same visual ceiling as pygame, but requires
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

| Source       | Address              | Latency | Used for                                                                  |
| ------------ | -------------------- | ------- | ------------------------------------------------------------------------- |
| Prometheus   | `10.43.125.146:9090` | 7 ms    | node and per-container CPU/RAM/temp, pod counts, rates, sparkline history |
| Alertmanager | `10.43.225.33:9093`  | —       | firing alerts                                                             |
| k3s API      | `127.0.0.1:6443`     | —       | namespace/workload/pod listing, conditions, events, **and pod logs**      |
| Loki         | `10.43.88.188:3100`  | 2 ms    | _optional_ historical logs from before the current pod instance           |

Prometheus is `kube-prometheus-stack` with node-exporter on all 8 nodes and
kube-state-metrics. 2739 metric names available.

**Per-container metrics are generic.** cAdvisor metrics
(`container_cpu_usage_seconds_total`, `container_memory_working_set_bytes`,
`container_network_*`, `container_fs_*`) are labelled with `namespace`, `pod`,
`container` and `node`. This means CPU, memory, network and disk are available
for **every** pod in the cluster with no per-app configuration whatsoever.

### Logs: k8s API is primary, Loki is optional

The Kubernetes API pod-log endpoint
(`/api/v1/namespaces/{ns}/pods/{pod}/log?tailLines=N&timestamps=true`, with
`follow=true` for streaming) is the **primary** log source.

Loki is deliberately **not** primary, despite being available and fast. It
currently indexes only **19 of the cluster's 27 namespaces** — `novachess`,
`observability`, `headlamp`, `novaflow-sandbox`, `cilium-secrets`, `default`,
`kube-public` and `kube-node-lease` have nothing in it. A generic explorer that
silently shows no logs for a third of the cluster is broken. The API endpoint
works for any pod, always, and needs no extra dependency.

Loki's advantage is history across pod restarts. It is therefore a secondary,
optional source behind a config flag, added after the API path works.

**Cluster shape:** 8 nodes — `master-11/12/13` (control-plane, `master-11`
cordoned) and `worker-21..25`, all at `192.168.10.101-108`.

### Authentication

A dedicated read-only ServiceAccount bound to a `view`-scoped ClusterRole. Its
token is written to `/etc/kw-dashboard/token`, mode `0400`, owned by `piwi`.

The built-in `view` ClusterRole already grants `get` on `pods/log`, which the
explorer's log view requires, so no custom role is needed. It grants no write
verbs, matching the read-only scope in section 13.

Root's `/etc/rancher/k3s/k3s.yaml` is **not** used — it is cluster-admin
credentials and inappropriate for a display process.

### Staleness

Every panel tracks the age of the data behind it. Past a threshold the panel
visibly greys out and displays that age. A dashboard confidently showing
five-minute-old numbers is worse than one admitting it lost contact.

## 7. Pages

Four pages. The three glanceable pages (1, 2, 4) each get **one idea and a
handful of large figures** — the pixel density budget in section 2 permits
nothing denser. Page 3 is the interactive explorer and follows list ergonomics
instead (see section 8).

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

### Page 3 — EXPLORE

A **generic Kubernetes explorer**. No app-specific code, no hardcoded workload
list, no per-app PromQL. Everything is driven by what the API and cAdvisor
report, so a newly deployed namespace appears with no changes to this project.

Entry point is the namespace list (27 namespaces, scrollable):

```
┌──────────────────────────────────────────────┐
│ ← NAMESPACES                          27     │
│                                              │
│  kube-system            31 pods  ██▁  1.2 GB │
│  monitoring             12 pods  █▁▁  3.4 GB │
│  novaflow                8 pods  █▁▁  892 MB │
│  longhorn-system        14 pods  ██▁  1.1 GB │
│  fastllm                 4 pods  ███  6.2 GB │
│  novamail                6 pods  █▁▁  412 MB │
│                              ▼ scroll        │
└──────────────────────────────────────────────┘
```

Namespaces with anything unhealthy sort to the top; the rest sort by resource
use. Aggregates come from summing cAdvisor series by `namespace`.

This page replaces the app-specific design considered earlier. That approach
was rejected because it only worked for the four instrumented workloads
(`novaflow`, `novamail`, `zot`, `openfga`) and degraded to a bare replica count
for `fastllm`, `novachess` and `novamem`. Generic per-container metrics plus
API logs cover every workload uniformly instead.

Custom app metrics are explicitly **out of scope** — Grafana already handles
those, and encoding them here would reintroduce exactly the app-coupling this
page exists to avoid.

### Page 4 — ALERTS

Near-empty and calm when clear: "all quiet" plus the last-incident timestamp.
When alerts fire, a list ranked by severity.

**Alerts pre-empt rotation.** A firing critical alert seizes the screen
regardless of the current page and halts the carousel until acknowledged by
touch. An alert you must wait 45 seconds for the carousel to reach is not an
alert.

## 8. Navigation and drill-down

The explorer needs real depth, so there is a proper navigation stack with a
persistent back affordance in the top-left.

```
NAMESPACES ─► NAMESPACE ─► POD ─┬─► LOGS
                                └─► CONTAINER
   (page 3)     pods in ns    detail

CLUSTER ─► NODE ─► (pods on that node) ─► POD ...
 (page 1)   detail
```

**Views:**

- **Namespace** — pods in it, each with status, restart count, age, and a CPU
  and memory bar. Unhealthy first.
- **Pod** — phase, ready state, restarts, node, age, owner workload, per-container
  CPU/memory sparklines from cAdvisor, recent events for that pod from the API,
  and a prominent **LOGS** action.
- **Logs** — tailed from the k8s API, newest at the bottom, auto-scrolling until
  the user scrolls up (which pauses follow, with a "jump to live" affordance).
  Container picker when the pod has more than one. Lines wrap rather than
  scrolling horizontally.
- **Node** — reached from page 1; conditions, capacity vs allocated, temperature,
  and the pods scheduled on it, which lead back into the pod view.

**Idle reset:** any view deeper than a top-level page returns to page 1 and
resumes rotation after ~2 minutes without touch, so the panel is never stranded
after someone walks away.

**Log legibility, honestly.** Section 2 sets a ~26 px floor for glanceable text
at ~1 m. Logs cannot honour that — at 26 px monospace you get roughly 78
columns, and most log lines are longer. The log view therefore deliberately
uses a smaller monospace size (~20 px, ~100 columns) than the rest of the
dashboard. This is a justified exception rather than an oversight: reading logs
is a lean-in activity, and anyone tapping through three levels of navigation is
already standing at arm's length from the panel. Glanceable views keep the
large type; only the log view relaxes it.

**Touch targets** stay at a ~60 px minimum row height throughout, so lists
remain finger-usable even where text is small. Lists scroll with inertia.

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

- **Data layer** — PromQL response parsing, unit conversion, staleness logic,
  alert severity ranking, and namespace/pod aggregation and sorting are pure
  functions, tested off-device against recorded API fixtures. No cluster
  required.
- **Log streaming** — the follow/pause/resume state machine and the ring buffer
  that bounds memory are tested against a synthetic line source. A long-running
  log tail must not grow without limit.
- **Navigation** — the view stack (push, pop, idle-reset to page 1) is tested
  independently of rendering.
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
- Ad-hoc querying / PromQL entry
- Log search or filtering beyond namespace/pod/container selection
- App-specific metric panels (`novaflow`, `novamail`, `zot`, `openfga` custom
  metrics) — Grafana's job, and reintroduces app coupling
- Any write or mutating action: no delete pod, no scale, no restart, no cordon.
  The ServiceAccount is read-only and the UI offers nothing that would need more.
- Configuration UI
- Multi-cluster support
- Authentication or any user accounts on the panel itself
