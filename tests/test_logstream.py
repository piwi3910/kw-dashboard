from kw_dashboard.logstream import LogStream


def test_ring_buffer_bounds_memory():
    s = LogStream(ring_size=100)
    s.append_lines([f"line {i}" for i in range(500)])
    assert len(s.lines) == 100
    assert s.lines[-1] == "line 499"


def test_follows_live_by_default():
    s = LogStream(ring_size=100)
    s.append_lines(["a", "b", "c"])
    assert s.follow is True
    assert s.visible(rows=2) == ["b", "c"]


def test_scroll_up_pauses_follow():
    s = LogStream(ring_size=100)
    s.append_lines([f"l{i}" for i in range(10)])
    s.scroll_up(3)
    assert s.follow is False
    assert s.visible(rows=2) == ["l5", "l6"]


def test_new_lines_do_not_move_view_while_paused():
    s = LogStream(ring_size=100)
    s.append_lines([f"l{i}" for i in range(10)])
    s.scroll_up(3)
    before = s.visible(rows=2)
    s.append_lines(["new"])
    assert s.visible(rows=2) == before


def test_jump_to_live_resumes_follow():
    s = LogStream(ring_size=100)
    s.append_lines([f"l{i}" for i in range(10)])
    s.scroll_up(5)
    s.jump_to_live()
    assert s.follow is True
    assert s.visible(rows=1) == ["l9"]


def test_scroll_up_clamps_at_oldest_line():
    s = LogStream(ring_size=100)
    s.append_lines(["a", "b"])
    s.scroll_up(999)
    assert s.visible(rows=2) == ["a", "b"]


def test_wrap_long_line_for_narrow_panel():
    from kw_dashboard.logstream import wrap_line

    assert wrap_line("abcdefghij", 4) == ["abcd", "efgh", "ij"]
    assert wrap_line("", 4) == [""]
