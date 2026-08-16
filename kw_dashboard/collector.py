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
