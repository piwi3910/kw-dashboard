"""Bounded log buffer with follow/pause. A long-running tail on an always-on
panel must not grow without limit."""
from __future__ import annotations
from collections import deque


def wrap_line(line: str, cols: int) -> list[str]:
    """Hard-wrap; the log view wraps rather than scrolling horizontally."""
    if not line:
        return [""]
    return [line[i:i + cols] for i in range(0, len(line), cols)]


class LogStream:
    def __init__(self, ring_size: int = 2000):
        self._buf: deque = deque(maxlen=ring_size)
        self.follow = True
        # Absolute index (not relative to the tail) of one-past-last visible
        # line when paused, so appends don't shift a paused view.
        self._end = 0

    @property
    def lines(self) -> list[str]:
        return list(self._buf)

    def append_lines(self, lines: list[str]):
        self._buf.extend(lines)

    def scroll_up(self, n: int):
        if self.follow:
            self._end = len(self._buf)
            self.follow = False
        self._end = max(1, self._end - n)

    def scroll_down(self, n: int):
        self._end = min(len(self._buf), self._end + n)
        if self._end >= len(self._buf):
            self.follow = True

    def jump_to_live(self):
        self.follow = True
        self._end = len(self._buf)

    def visible(self, rows: int) -> list[str]:
        buf = list(self._buf)
        if not buf:
            return []
        end = len(buf) if self.follow else min(self._end, len(buf))
        start = max(0, end - rows)
        if end - start < rows:               # keep the window full when scrolled to the top
            end = min(len(buf), start + rows)
        return buf[start:end]
