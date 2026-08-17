"""View stack and rotation state. Pure logic, no pygame — so it is testable
without a display."""
from __future__ import annotations
from dataclasses import dataclass, field

PAGES = ["cluster", "pulse", "explore", "alerts"]


@dataclass(frozen=True)
class View:
    kind: str
    params: dict = field(default_factory=dict)


class Nav:
    def __init__(self, rotate_seconds: float, pause_seconds: float,
                 idle_reset_seconds: float):
        self.rotate_seconds = rotate_seconds
        self.pause_seconds = pause_seconds
        self.idle_reset_seconds = idle_reset_seconds
        self.page_index = 0
        self._stack: list[View] = []
        # Far in the past: a fresh Nav must start rotating, not paused.
        self._last_touch = -1e9
        self._last_rotate = 0.0
        self._preempted = False

    @property
    def depth(self) -> int:
        return len(self._stack)

    @property
    def current(self) -> View:
        return self._stack[-1] if self._stack else View(PAGES[self.page_index])

    @property
    def rotating(self) -> bool:
        return self.depth == 0 and not self._paused_at(self._now) and not self._preempted

    _now = 0.0

    def _paused_at(self, now: float) -> bool:
        return (now - self._last_touch) < self.pause_seconds

    def touch(self, now: float):
        self._now = now
        self._last_touch = now

    def push(self, view: View, now: float):
        self.touch(now)
        self._stack.append(view)

    def pop(self):
        if self._stack:
            self._stack.pop()

    def jump_to_page(self, index: int, now: float):
        self.touch(now)
        self._stack.clear()
        self.page_index = index % len(PAGES)
        self._last_rotate = now

    def preempt_for_alert(self, now: float):
        """A firing critical alert seizes the screen (spec section 7)."""
        self._stack.clear()
        self.page_index = PAGES.index("alerts")
        self._preempted = True
        self._last_rotate = now

    def clear_preempt(self, now: float):
        self._preempted = False
        self.touch(now)

    def tick(self, now: float):
        self._now = now
        # Idle reset from a deep view or a pre-empted page back to page 1.
        # Only short-circuits when there is actually something to reset —
        # otherwise an untouched panel would never rotate at all.
        if ((now - self._last_touch) > self.idle_reset_seconds
                and (self._stack or self._preempted)):
            self._stack.clear()
            self.page_index = 0
            self._preempted = False
            self._last_rotate = now
            return
        if not self.rotating:
            return
        if (now - self._last_rotate) >= self.rotate_seconds:
            self.page_index = (self.page_index + 1) % len(PAGES)
            self._last_rotate = now
