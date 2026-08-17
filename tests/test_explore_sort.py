from kw_dashboard.sorting import sort_namespaces, sort_pods, fmt_bytes
from kw_dashboard.model import NsStat
from kw_dashboard.sources.kube import PodInfo

def test_unhealthy_namespaces_sort_first():
    a = NsStat("big", 30, 0, 5.0, 9e9)
    b = NsStat("broken", 2, 1, 0.1, 1e6)
    assert [n.name for n in sort_namespaces([a, b])] == ["broken", "big"]

def test_healthy_namespaces_sort_by_memory():
    a = NsStat("small", 3, 0, 0.1, 1e6)
    b = NsStat("large", 3, 0, 0.1, 9e9)
    assert [n.name for n in sort_namespaces([a, b])] == ["large", "small"]

def test_unhealthy_pods_sort_first_then_by_restarts():
    p1 = PodInfo("ok", "n", "w", "Running", 1, 1, 0, ["c"])
    p2 = PodInfo("bad", "n", "w", "CrashLoopBackOff", 0, 1, 9, ["c"])
    p3 = PodInfo("flaky", "n", "w", "Running", 1, 1, 5, ["c"])
    assert [p.name for p in sort_pods([p1, p2, p3])] == ["bad", "flaky", "ok"]

def test_succeeded_pod_does_not_sort_above_broken_running_pod():
    # A completed Job pod is not a problem -- it must not be sorted to the
    # top ahead of a pod that's genuinely broken.
    done = PodInfo("done", "n", "w", "Succeeded", 0, 1, 0, ["c"])
    broken = PodInfo("broken", "n", "w", "Running", 0, 1, 3, ["c"])
    assert [p.name for p in sort_pods([done, broken])] == ["broken", "done"]

def test_fmt_bytes_scales_units():
    assert fmt_bytes(0) == "0 B"
    assert fmt_bytes(1536) == "1.5 KB"
    assert fmt_bytes(9e9) == "8.4 GB"
