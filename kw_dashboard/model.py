"""Immutable snapshot handed from collector to renderer."""
from __future__ import annotations
from dataclasses import dataclass, field
from .sources.prometheus import Sample
from .sources.kube import NodeInfo, build_ip_map


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
    pods: list = field(default_factory=list)
    alerts: list = field(default_factory=list)
    events: list = field(default_factory=list)
    cpu_history: tuple = ()
    mem_history: tuple = ()
    updated: dict = field(default_factory=dict)
    errors: dict = field(default_factory=dict)


def merge_node_stats(nodes: list[NodeInfo], cpu: list[Sample], mem: list[Sample],
                     temp: list[Sample], pod_counts: dict[str, int]) -> list[NodeStat]:
    """Join node-exporter series (labelled by IP:9100) to k8s node names."""
    ip_map = build_ip_map(nodes)                     # {"IP:9100": node_name}

    def by_name(samples):
        out = {}
        for s in samples:
            name = ip_map.get(s.labels.get("instance", ""))
            if name is not None:
                out[name] = s.value
        return out

    c, m, t = by_name(cpu), by_name(mem), by_name(temp)
    return [
        NodeStat(
            name=n.name, ready=n.ready, cordoned=n.cordoned,
            cpu_pct=c.get(n.name, 0.0), mem_pct=m.get(n.name, 0.0),
            temp_c=t.get(n.name),      # None when absent: absent != 0 degrees
            pods=pod_counts.get(n.name, 0))
        for n in nodes
    ]
