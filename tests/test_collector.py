import time
from kw_dashboard.model import Snapshot, NodeStat, NsStat, merge_node_stats
from kw_dashboard.collector import is_stale
from kw_dashboard.sources.prometheus import Sample
from kw_dashboard.sources.kube import NodeInfo

def test_merge_node_stats_joins_prom_instances_to_node_names():
    nodes = [NodeInfo("master-11", "192.168.10.101", True, True, 8, 3e10, 110),
             NodeInfo("worker-21", "192.168.10.104", True, False, 8, 3e10, 110)]
    cpu = [Sample({"instance": "192.168.10.101:9100"}, 47.0),
           Sample({"instance": "192.168.10.104:9100"}, 12.0)]
    mem = [Sample({"instance": "192.168.10.101:9100"}, 31.0)]
    temp = [Sample({"instance": "192.168.10.104:9100"}, 61.5)]
    out = {n.name: n for n in merge_node_stats(nodes, cpu, mem, temp, {})}
    assert out["master-11"].cpu_pct == 47.0
    assert out["master-11"].mem_pct == 31.0
    assert out["master-11"].temp_c is None      # missing series -> None, not 0
    assert out["worker-21"].temp_c == 61.5
    assert out["master-11"].cordoned is True

def test_node_stat_worst_uses_highest_pressure():
    n = NodeStat("n", True, False, 20.0, 90.0, 45.0, 5)
    assert n.worst_pct == 90.0

def test_node_stat_not_ready_is_always_worst():
    n = NodeStat("n", False, False, 1.0, 1.0, 20.0, 0)
    assert n.worst_pct == 100.0

def test_is_stale_uses_per_source_timestamps():
    s = Snapshot(updated={"prom": time.time() - 10, "kube": time.time() - 300})
    assert is_stale(s, "prom", limit=45) is False
    assert is_stale(s, "kube", limit=45) is True

def test_is_stale_for_never_updated_source():
    assert is_stale(Snapshot(), "prom", limit=45) is True
