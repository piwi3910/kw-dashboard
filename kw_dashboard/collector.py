"""Background polling thread. Never blocks the renderer; each source fails
independently so one dead endpoint dims only its own panels."""
from __future__ import annotations
import threading, time
from collections import Counter, deque
from dataclasses import replace
from .model import Snapshot, NsStat, merge_node_stats
from .series import stats, downsample
from .sources.kube import build_ip_map
from .sources.prometheus import RANGE_QUERIES

RANGE_WINDOW_SECONDS = 3600
RANGE_STEP_SECONDS = 60
RANGE_MAX_POINTS = 120


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
            self._mark("prom")
        except Exception as e:
            self._mark("prom", str(e))

        # Independently marked: this path needs BOTH prometheus and the k8s API,
        # so a failure here must not be attributed to prometheus alone.
        try:
            self._node_and_ns()
            self._mark("nodes")
        except Exception as e:
            self._mark("nodes", str(e))

    def _node_and_ns(self):
        nodes = self.kube.list_nodes()
        pods = self.kube.list_pods()
        counts = Counter(p.node for p in pods)
        stats = merge_node_stats(
            nodes, self.prom.query_named("node_cpu"),
            self.prom.query_named("node_mem"),
            self.prom.query_named("node_temp"), counts,
            uptime=self.prom.query_named("node_uptime_days"))

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
        self._update(nodes=stats, namespaces=namespaces, pods=pods)

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
        # Range queries are heavy; keep them on the slow loop and isolate their
        # failure so a dead range endpoint doesn't stale out instant metrics.
        try:
            self._poll_series()
            self._mark("series")
        except Exception as e:
            self._mark("series", str(e))

    def _series_dicts(self, series_list, name_map=None) -> tuple:
        """Turn Series into the {name, points, min, max, mean, last} dicts the
        UI expects, downsampled for display."""
        out = []
        for s in series_list:
            if name_map is not None:
                name = name_map.get(s.labels.get("instance", ""))
                if name is None:
                    continue
            else:
                name = s.labels.get("namespace") or s.labels.get("instance") or ""
            pts = downsample(s.points, RANGE_MAX_POINTS)
            st = stats(pts)
            out.append({"name": name, "points": pts,
                        "min": st.min, "max": st.max, "mean": st.mean, "last": st.last})
        return tuple(out)

    def _poll_series(self):
        end = time.time()
        start = end - RANGE_WINDOW_SECONDS
        nodes = self.kube.list_nodes()
        ip_map = build_ip_map(nodes)

        node_cpu = self.prom.query_range(self._range_query("node_cpu"), start, end, RANGE_STEP_SECONDS)
        node_mem = self.prom.query_range(self._range_query("node_mem"), start, end, RANGE_STEP_SECONDS)
        ns_mem = self.prom.query_range(self._range_query("ns_mem"), start, end, RANGE_STEP_SECONDS)
        net_rx = self.prom.query_range(self._range_query("net_rx"), start, end, RANGE_STEP_SECONDS)
        net_tx = self.prom.query_range(self._range_query("net_tx"), start, end, RANGE_STEP_SECONDS)

        self._update(
            node_cpu_series=self._series_dicts(node_cpu, name_map=ip_map),
            node_mem_series=self._series_dicts(node_mem, name_map=ip_map),
            ns_mem_series=self._series_dicts(ns_mem),
            net_rx_series=self._series_dicts(net_rx),
            net_tx_series=self._series_dicts(net_tx))

    @staticmethod
    def _range_query(name: str) -> str:
        return RANGE_QUERIES[name]

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
