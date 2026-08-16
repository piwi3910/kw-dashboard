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
