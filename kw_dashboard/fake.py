"""Synthetic snapshots so pages can be rendered and reviewed off-device."""
from __future__ import annotations
import os, random, time
import pygame
from .model import Snapshot, NodeStat, NsStat
from .sources.alerts import Alert
from .sources.kube import EventInfo, PodInfo
from datetime import datetime, timezone


def _walk(n, start, lo, hi, step, seed):
    rnd = random.Random(seed)
    v, out = start, []
    for _ in range(n):
        v = min(hi, max(lo, v + rnd.uniform(-step, step)))
        out.append(v)
    return tuple(out)


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
    pods = [
        PodInfo("web-7c9d-abc12", "novaflow", "worker-21", "Running", 1, 1, 0),
        PodInfo("worker-5f8b-xyz34", "novaflow", "worker-21", "Running", 0, 1, 5),
        PodInfo("api-6b7c-def56", "novaflow", "worker-22", "Running", 1, 1, 0),
        PodInfo("cache-redis-0", "fastllm", "worker-22", "Running", 1, 1, 0),
        PodInfo("etl-job-99a1", "fastllm", "worker-21", "Pending", 0, 1, 0),
        PodInfo("collector-ds-2k9m", "monitoring", "worker-22", "Running", 1, 1, 1),
    ]
    alerts = [Alert("NodeNotReady", "critical", "worker-24 is not ready",
                    datetime.now(timezone.utc))] if with_alerts else []
    events = [
        EventInfo("Started", "Started container app", "p1", "novaflow",
                  False, datetime.now(timezone.utc)),
        EventInfo("BackOff", "Back-off restarting failed container", "worker-5f8b-xyz34",
                  "novaflow", True, datetime.now(timezone.utc)),
        EventInfo("Pulled", "Successfully pulled image", "api-6b7c-def56",
                  "novaflow", False, datetime.now(timezone.utc)),
        EventInfo("FailedScheduling", "0/8 nodes available", "etl-job-99a1",
                  "fastllm", True, datetime.now(timezone.utc)),
        EventInfo("Created", "Created container collector", "collector-ds-2k9m",
                  "monitoring", False, datetime.now(timezone.utc)),
        EventInfo("Unhealthy", "Readiness probe failed", "cache-redis-0",
                  "fastllm", True, datetime.now(timezone.utc)),
    ]
    return Snapshot(cluster_cpu=37.0, cluster_mem=41.0, pods_running=176,
                    net_rx=1.2e7, net_tx=8.4e6, nodes=nodes, namespaces=ns,
                    pods=pods, alerts=alerts, events=events,
                    cpu_history=_walk(60, 37, 15, 75, 4, seed=1),
                    mem_history=_walk(60, 41, 25, 65, 3, seed=2),
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
