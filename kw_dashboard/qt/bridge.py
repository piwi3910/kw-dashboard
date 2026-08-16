"""Qt-facing bridge: owns the Collector and Nav, exposes them to QML as
plain properties/slots. All existing logic (Collector, Nav, model dataclasses)
is reused unchanged; this file only translates it into pyqtProperty/pyqtSlot
shape and keeps network I/O off the GUI thread.
"""
from __future__ import annotations
import threading
import time

from PyQt5.QtCore import QObject, QTimer, pyqtProperty, pyqtSignal, pyqtSlot

from ..collector import is_stale
from ..logstream import LogStream
from ..model import Snapshot
from ..nav import View
from ..sources.alerts import has_critical

_STALE_SOURCES = ("prom", "nodes", "alerts", "kube")


def _node_dict(n) -> dict:
    return {
        "name": n.name, "ready": n.ready, "cordoned": n.cordoned,
        "cpuPct": n.cpu_pct, "memPct": n.mem_pct,
        "tempC": n.temp_c if n.temp_c is not None else -1,
        "pods": n.pods, "worstPct": n.worst_pct,
    }


def _ns_dict(n) -> dict:
    return {"name": n.name, "pods": n.pods, "unhealthy": n.unhealthy,
            "cpuCores": n.cpu_cores, "memBytes": n.mem_bytes}


def _pod_dict(p) -> dict:
    return {
        "name": p.name, "namespace": p.namespace, "node": p.node,
        "phase": p.phase, "ready": p.ready, "total": p.total,
        "restarts": p.restarts, "containers": list(p.containers),
        "healthy": p.healthy,
    }


def _alert_dict(a) -> dict:
    return {"name": a.name, "severity": a.severity, "summary": a.summary,
            "startsAt": a.starts_at.isoformat() if a.starts_at else None}


def _event_dict(e) -> dict:
    return {"reason": e.reason, "message": e.message, "obj": e.obj,
            "namespace": e.namespace, "warning": e.warning,
            "ts": e.ts.isoformat()}


class Bridge(QObject):
    snapshotChanged = pyqtSignal()
    navChanged = pyqtSignal()
    podsFetched = pyqtSignal(str, 'QVariant')
    logsFetched = pyqtSignal(str, str, str)

    def __init__(self, cfg, collector, nav, parent=None):
        super().__init__(parent)
        self.cfg = cfg
        self.collector = collector
        self.nav = nav
        self._last_snap: Snapshot = collector.snapshot()
        self._last_nav_state = None
        self._preempt_active = False
        self._pods_cache: dict[str, list] = {}
        self._log_stream = LogStream(cfg.log_ring_size)

        self._timer = QTimer(self)
        self._timer.setInterval(500)
        self._timer.timeout.connect(self._tick)
        self._timer.start()

    # ---- polling ----------------------------------------------------
    def _tick(self):
        now = time.time()
        self.nav.tick(now)
        snap = self.collector.snapshot()

        # Edge-triggered alert pre-emption: fire once per episode, re-arm
        # once no critical alert is active.
        critical = has_critical(snap.alerts)
        if critical and not self._preempt_active:
            self.nav.preempt_for_alert(now)
            self._preempt_active = True
        elif not critical:
            self._preempt_active = False

        nav_state = (self.nav.page_index, self.nav.current.kind,
                     tuple(sorted(self.nav.current.params.items())),
                     self.nav.depth)
        if nav_state != self._last_nav_state:
            self._last_nav_state = nav_state
            self.navChanged.emit()

        if snap != self._last_snap:
            self._last_snap = snap
            self.snapshotChanged.emit()

    # ---- data properties ---------------------------------------------
    def _snap(self) -> Snapshot:
        return self._last_snap

    clusterCpu = pyqtProperty(float, lambda self: self._snap().cluster_cpu,
                               notify=snapshotChanged)
    clusterMem = pyqtProperty(float, lambda self: self._snap().cluster_mem,
                               notify=snapshotChanged)
    podsRunning = pyqtProperty(int, lambda self: self._snap().pods_running,
                                notify=snapshotChanged)
    netRx = pyqtProperty(float, lambda self: self._snap().net_rx,
                          notify=snapshotChanged)
    netTx = pyqtProperty(float, lambda self: self._snap().net_tx,
                          notify=snapshotChanged)
    cpuHistory = pyqtProperty('QVariant',
                               lambda self: list(self._snap().cpu_history),
                               notify=snapshotChanged)
    memHistory = pyqtProperty('QVariant',
                               lambda self: list(self._snap().mem_history),
                               notify=snapshotChanged)
    nodes = pyqtProperty('QVariant',
                          lambda self: [_node_dict(n) for n in self._snap().nodes],
                          notify=snapshotChanged)
    namespaces = pyqtProperty('QVariant',
                               lambda self: [_ns_dict(n) for n in self._snap().namespaces],
                               notify=snapshotChanged)
    pods = pyqtProperty('QVariant',
                         lambda self: [_pod_dict(p) for p in self._snap().pods],
                         notify=snapshotChanged)
    alerts = pyqtProperty('QVariant',
                           lambda self: [_alert_dict(a) for a in self._snap().alerts],
                           notify=snapshotChanged)
    events = pyqtProperty('QVariant',
                           lambda self: [_event_dict(e) for e in self._snap().events],
                           notify=snapshotChanged)
    errors = pyqtProperty('QVariant', lambda self: dict(self._snap().errors),
                           notify=snapshotChanged)

    def _stale(self) -> bool:
        snap, now = self._snap(), time.time()
        return any(is_stale(snap, src, self.cfg.stale_after_seconds, now)
                   for src in _STALE_SOURCES)

    stale = pyqtProperty(bool, _stale, notify=snapshotChanged)

    def _pending_pods(self) -> int:
        return sum(1 for p in self._snap().pods if p.phase == "Pending")

    def _unhealthy_pods(self) -> int:
        return sum(1 for p in self._snap().pods if not p.healthy)

    def _total_restarts(self) -> int:
        return sum(p.restarts for p in self._snap().pods)

    def _cpu_peak(self) -> float:
        h = self._snap().cpu_history
        return max(h) if h else 0.0

    def _mem_peak(self) -> float:
        h = self._snap().mem_history
        return max(h) if h else 0.0

    pendingPods = pyqtProperty(int, _pending_pods, notify=snapshotChanged)
    unhealthyPods = pyqtProperty(int, _unhealthy_pods, notify=snapshotChanged)
    totalRestarts = pyqtProperty(int, _total_restarts, notify=snapshotChanged)
    cpuPeak = pyqtProperty(float, _cpu_peak, notify=snapshotChanged)
    memPeak = pyqtProperty(float, _mem_peak, notify=snapshotChanged)

    # ---- nav properties -------------------------------------------
    pageIndex = pyqtProperty(int, lambda self: self.nav.page_index,
                              notify=navChanged)
    viewKind = pyqtProperty(str, lambda self: self.nav.current.kind,
                             notify=navChanged)
    viewParams = pyqtProperty('QVariant',
                               lambda self: dict(self.nav.current.params),
                               notify=navChanged)
    depth = pyqtProperty(int, lambda self: self.nav.depth, notify=navChanged)

    # ---- slots ----------------------------------------------------
    @pyqtSlot()
    def touch(self):
        self.nav.touch(time.time())

    @pyqtSlot(str, 'QVariant')
    def pushView(self, kind, params):
        p = dict(params) if params else {}
        self.nav.push(View(kind, p), time.time())
        self.navChanged.emit()

    @pyqtSlot()
    def popView(self):
        self.nav.pop()
        self.navChanged.emit()

    @pyqtSlot(int)
    def jumpToPage(self, index):
        self.nav.jump_to_page(index, time.time())
        self.navChanged.emit()

    @pyqtSlot()
    def clearPreempt(self):
        self.nav.clear_preempt(time.time())
        self._preempt_active = False
        self.navChanged.emit()

    # ---- off-thread network fetches --------------------------------
    @pyqtSlot(str)
    def fetchPods(self, ns):
        threading.Thread(target=self._fetch_pods_thread, args=(ns,),
                         daemon=True).start()

    def _fetch_pods_thread(self, ns):
        try:
            pods = self.collector.kube.list_pods(ns or None)
            result = [_pod_dict(p) for p in pods]
        except Exception:
            result = []
        self._pods_cache[ns] = result
        self.podsFetched.emit(ns, result)

    @pyqtSlot(str, str, str)
    def fetchLogs(self, ns, pod, container):
        threading.Thread(target=self._fetch_logs_thread,
                         args=(ns, pod, container), daemon=True).start()

    def _fetch_logs_thread(self, ns, pod, container):
        try:
            lines = self.collector.kube.pod_log(
                ns, pod, container or None, tail=self.cfg.log_tail_lines)
            self._log_stream.append_lines(lines)
        except Exception:
            pass
        self.logsFetched.emit(ns, pod, container)

    @pyqtSlot(result='QVariant')
    def logLines(self):
        return list(self._log_stream.lines)
