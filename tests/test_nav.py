from kw_dashboard.nav import Nav, View, PAGES


def test_starts_on_cluster_page_rotating():
    n = Nav(rotate_seconds=15, pause_seconds=60, idle_reset_seconds=120)
    assert n.current.kind == "cluster"
    assert n.rotating is True


def test_tick_rotates_pages_in_order():
    n = Nav(15, 60, 120)
    n.tick(now=16.0)
    assert n.current.kind == PAGES[1]
    n.tick(now=32.0)
    assert n.current.kind == PAGES[2]


def test_touch_pauses_rotation_then_resumes():
    n = Nav(15, 60, 120)
    n.touch(now=1.0)
    n.tick(now=30.0)
    assert n.current.kind == "cluster"  # still paused
    n.tick(now=100.0)
    assert n.current.kind != "cluster"  # pause expired, rotation resumed


def test_push_and_pop_restores_previous_view():
    n = Nav(15, 60, 120)
    n.push(View("namespace", {"ns": "novaflow"}), now=1.0)
    assert n.current.kind == "namespace"
    assert n.depth == 1
    n.pop()
    assert n.current.kind == "cluster"
    assert n.depth == 0


def test_deep_view_does_not_rotate():
    n = Nav(15, 60, 120)
    n.push(View("pod", {"ns": "a", "pod": "b"}), now=1.0)
    n.tick(now=100.0)
    assert n.current.kind == "pod"


def test_idle_reset_returns_to_cluster_and_resumes_rotation():
    n = Nav(15, 60, 120)
    n.push(View("logs", {"ns": "a", "pod": "b"}), now=1.0)
    n.tick(now=200.0)  # >120s since last touch
    assert n.current.kind == "cluster"
    assert n.depth == 0
    assert n.rotating is True


def test_jump_to_page_sets_index_and_pauses():
    n = Nav(15, 60, 120)
    n.jump_to_page(3, now=5.0)
    assert n.current.kind == PAGES[3]
    assert n.rotating is False
