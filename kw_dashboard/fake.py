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
