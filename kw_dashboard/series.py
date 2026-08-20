"""Pure functions over (timestamp, value) point series. No I/O."""

from __future__ import annotations
from dataclasses import dataclass

Point = tuple[float, float]


@dataclass(frozen=True)
class SeriesStats:
    min: float
    max: float
    mean: float
    last: float


def stats(points) -> SeriesStats:
    """Empty series returns zeros, never NaN (a NaN reaching the UI draws a broken chart)."""
    if not points:
        return SeriesStats(min=0.0, max=0.0, mean=0.0, last=0.0)
    vals = [v for _, v in points]
    return SeriesStats(
        min=min(vals), max=max(vals), mean=sum(vals) / len(vals), last=vals[-1]
    )


def downsample(points, max_points: int) -> tuple:
    """Evenly reduce a series for display, always keeping the first and last point.
    Never returns more than max_points."""
    points = tuple(points)
    if len(points) <= max_points:
        return points
    if max_points <= 1:
        return (points[-1],)
    step = (len(points) - 1) / (max_points - 1)
    idxs = sorted({round(i * step) for i in range(max_points)})
    return tuple(points[i] for i in idxs)


def normalise(points, lo=None, hi=None) -> tuple[float, ...]:
    """Map values to 0..1 for plotting. Flat series (max == min) plots as 0.5,
    not 0.0 — pinning a level line to the bottom edge is a real bug we shipped once."""
    if not points:
        return ()
    vals = [v for _, v in points]
    lo = min(vals) if lo is None else lo
    hi = max(vals) if hi is None else hi
    if hi == lo:
        return tuple(0.5 for _ in vals)
    return tuple((v - lo) / (hi - lo) for v in vals)


def nice_axis(lo: float, hi: float, ticks: int = 5) -> tuple[float, ...]:
    """Human-friendly axis tick values covering [lo, hi]."""
    if hi < lo:
        lo, hi = hi, lo
    span = hi - lo
    if span <= 0:
        span = abs(lo) if lo else 1.0
    raw_step = span / max(ticks - 1, 1)
    magnitude = (
        10 ** (len(str(int(raw_step))) - 1)
        if raw_step >= 1
        else _small_magnitude(raw_step)
    )
    for m in (1, 2, 2.5, 5, 10):
        step = m * magnitude
        if step >= raw_step:
            break
    start = step * (lo // step)
    out = []
    v = start
    while v < hi + step:
        out.append(round(v, 10))
        v += step
    return tuple(out)


def _small_magnitude(raw_step: float) -> float:
    magnitude = 1.0
    while magnitude > raw_step:
        magnitude /= 10
    return magnitude
