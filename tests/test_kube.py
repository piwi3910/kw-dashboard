from kw_dashboard.sources.kube import (parse_nodes, parse_pods, parse_events,
                                       NodeInfo, PodInfo, build_ip_map)

NODES = {"items": [{
    "metadata": {"name": "master-11"},
    "spec": {"unschedulable": True},
    "status": {
        "addresses": [{"type": "InternalIP", "address": "192.168.10.101"}],
        "conditions": [{"type": "Ready", "status": "True"}],
        "capacity": {"cpu": "8", "memory": "31000000Ki", "pods": "110"},
    }}]}

PODS = {"items": [{
    "metadata": {"name": "p1", "namespace": "novaflow"},
    "spec": {"nodeName": "worker-21",
             "containers": [{"name": "app"}, {"name": "sidecar"}]},
    "status": {"phase": "Running",
               "containerStatuses": [
                   {"name": "app", "ready": True, "restartCount": 2},
                   {"name": "sidecar", "ready": False, "restartCount": 0}]}}]}

def test_parse_nodes_extracts_ready_and_cordon():
    n = parse_nodes(NODES)[0]
    assert n.name == "master-11"
    assert n.ready is True
    assert n.cordoned is True
    assert n.internal_ip == "192.168.10.101"

def test_build_ip_map_joins_node_exporter_instances_to_names():
    # node-exporter labels series "IP:9100"; this map is how we get node names
    m = build_ip_map(parse_nodes(NODES))
    assert m["192.168.10.101:9100"] == "master-11"

def test_parse_pods_counts_ready_containers():
    p = parse_pods(PODS)[0]
    assert p.namespace == "novaflow"
    assert p.ready == 1 and p.total == 2
    assert p.restarts == 2
    assert p.healthy is False  # not all containers ready

def test_parse_pods_containers_listed_for_log_picker():
    assert parse_pods(PODS)[0].containers == ["app", "sidecar"]

def test_parse_events_sorted_newest_first():
    ev = {"items": [
        {"metadata": {"name": "a"}, "type": "Normal", "reason": "Started",
         "message": "m1", "lastTimestamp": "2026-08-16T10:00:00Z",
         "involvedObject": {"name": "p1", "namespace": "x"}},
        {"metadata": {"name": "b"}, "type": "Warning", "reason": "Failed",
         "message": "m2", "lastTimestamp": "2026-08-16T11:00:00Z",
         "involvedObject": {"name": "p2", "namespace": "x"}}]}
    e = parse_events(ev)
    assert [x.reason for x in e] == ["Failed", "Started"]
    assert e[0].warning is True
