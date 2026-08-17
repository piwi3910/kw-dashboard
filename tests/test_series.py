import math
from kw_dashboard.series import SeriesStats, stats, downsample, normalise, nice_axis


def test_stats_computes_min_max_mean_last():
    s = stats(((0, 1.0), (1, 3.0), (2, 5.0)))
    assert s == SeriesStats(min=1.0, max=5.0, mean=3.0, last=5.0)


def test_stats_empty_series_returns_zeros_not_nan():
    s = stats(())
    assert s == SeriesStats(min=0.0, max=0.0, mean=0.0, last=0.0)
    assert not any(math.isnan(v) for v in (s.min, s.max, s.mean, s.last))


def test_downsample_preserves_first_and_last():
    pts = tuple((i, float(i)) for i in range(500))
    out = downsample(pts, 50)
    assert out[0] == pts[0]
    assert out[-1] == pts[-1]
    assert len(out) <= 50


def test_downsample_never_exceeds_max_points():
    pts = tuple((i, float(i)) for i in range(10))
    assert len(downsample(pts, 3)) <= 3


def test_downsample_short_series_returned_unchanged():
    pts = ((0, 1.0), (1, 2.0))
    assert downsample(pts, 120) == pts


def test_normalise_all_equal_returns_half_for_every_point():
    pts = ((0, 5.0), (1, 5.0), (2, 5.0))
    out = normalise(pts)
    assert out == (0.5, 0.5, 0.5)


def test_normalise_maps_to_0_1_range():
    pts = ((0, 0.0), (1, 5.0), (2, 10.0))
    out = normalise(pts)
    assert out == (0.0, 0.5, 1.0)


def test_normalise_empty_series_returns_empty():
    assert normalise(()) == ()


def test_nice_axis_covers_0_100():
    ticks = nice_axis(0, 100, ticks=5)
    assert ticks[0] <= 0
    assert ticks[-1] >= 100
    assert len(ticks) >= 2


def test_nice_axis_handles_narrow_range():
    ticks = nice_axis(49.8, 50.2, ticks=5)
    assert ticks[0] <= 49.8
    assert ticks[-1] >= 50.2
    assert len(set(ticks)) == len(ticks)  # no duplicate ticks
