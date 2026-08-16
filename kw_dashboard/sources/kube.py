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
