"""pygame main loop on SDL2's KMSDRM backend. Renders from the collector's
snapshot; never performs I/O on this thread."""
from __future__ import annotations
import logging, os, time
import pygame
from .config import Config
from .nav import Nav, View, PAGES
from .ui.theme import THEME, FONT_SIZES
from .sources.alerts import has_critical

FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
MONO_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"


def load_fonts() -> dict:
    pygame.font.init()
    f = {n: pygame.font.Font(FONT_PATH, s)
         for n, s in FONT_SIZES.items() if n != "mono"}
    f["mono"] = pygame.font.Font(MONO_PATH, FONT_SIZES["mono"])
    return f


class App:
    def __init__(self, cfg: Config, collector, windowed: bool = False):
        self.cfg, self.collector, self.windowed = cfg, collector, windowed
        self.nav = Nav(cfg.rotate_seconds, cfg.touch_pause_seconds,
                       cfg.idle_reset_seconds)
        self.hits: list = []
        self._alert_seen = False
        self.scroll = {}          # view-key -> int offset (rows)
        self._drag_start = None   # (x, y) where the current press began
        self._drag_moved = False

    def _init_display(self):
        if not self.windowed:
            os.environ.setdefault("SDL_VIDEODRIVER", "kmsdrm")
        pygame.display.init()
        flags = 0 if self.windowed else pygame.FULLSCREEN
        self.screen = pygame.display.set_mode((self.cfg.width, self.cfg.height), flags)
        pygame.mouse.set_visible(False)
        self.fonts = load_fonts()

    def _dispatch_touch(self, pos, now: float):
        self.nav.touch(now)
        for rect, action in self.hits:
            if rect.collidepoint(pos):
                action()
                return

    def _check_preemption(self, snap, now: float):
        """A firing critical alert seizes the screen (spec section 7)."""
        crit = has_critical(snap.alerts)
        if crit and not self._alert_seen:
            self.nav.preempt_for_alert(now)
            self._alert_seen = True
        elif not crit:
            self._alert_seen = False

    def _ensure_cache(self):
        if not hasattr(self, "view_cache"):
            self.view_cache = {}
            self._inflight = set()

    def scroll_key(self, view):
        return (view.kind, tuple(sorted(view.params.items())))

    # ponytail: view_cache/scroll are unbounded insertion-order dicts capped
    # by _cache_evict below; upgrade to a real LRU/TTL if browsing patterns
    # ever outgrow ~24 live namespaces/pods/log-streams.
    _CACHE_MAX = 24

    def _cache_evict(self):
        while len(self.view_cache) > self._CACHE_MAX:
            self.view_cache.pop(next(iter(self.view_cache)))

    def fetch_pods(self, ns: str):
        """Fetch pods for a namespace in a worker thread; cache the result."""
        import threading
        self._ensure_cache()
        key = ("pods", ns)
        if key in self.view_cache or key in self._inflight:
            return self.view_cache.get(key)
        self._inflight.add(key)

        def work():
            try:
                self.view_cache[key] = self.collector.kube.list_pods(ns)
                self.view_cache.pop(("err", ns), None)
            except Exception as e:
                self.view_cache.pop(key, None)   # keep the miss so it renders as an error, not empty
                self.view_cache[("err", ns)] = str(e)
            finally:
                self._inflight.discard(key)
                self._cache_evict()

        threading.Thread(target=work, daemon=True).start()
        return None

    def fetch_logs(self, ns: str, pod: str, container: str | None):
        import threading
        from .logstream import LogStream
        self._ensure_cache()
        key = ("logs", ns, pod, container)
        if key in self._inflight:
            return self.view_cache.get(key)
        if key not in self.view_cache:
            self.view_cache[key] = LogStream(ring_size=self.cfg.log_ring_size)
        stream = self.view_cache[key]
        self._inflight.add(key)

        def work():
            try:
                lines = self.collector.kube.pod_log(
                    ns, pod, container, tail=self.cfg.log_tail_lines)
                stream.append_lines(lines[-self.cfg.log_tail_lines:])
            except Exception as e:
                stream.append_lines([f"[log unavailable: {e}]"])
            finally:
                self._inflight.discard(key)
                self._cache_evict()

        threading.Thread(target=work, daemon=True).start()
        return stream

    def render_once(self, snap) -> pygame.Surface:
        from .ui.pages import registry
        self.screen.fill(THEME.bg)
        view = self.nav.current
        renderer = registry.get(view.kind)
        if renderer is None:
            return self.screen          # no pages registered yet (Tasks 13-15)
        try:
            self.hits = renderer(self.screen, snap, self.nav, self.fonts, self) or []
        except Exception:
            # A broken page must not take down an unattended panel.
            self.hits = []
            logging.exception("page renderer failed: %s", view.kind)
        return self.screen

    def run(self):
        self._init_display()
        clock = pygame.time.Clock()
        try:
            running = True
            while running:
                now = time.time()
                for ev in pygame.event.get():
                    if ev.type == pygame.QUIT:
                        running = False
                    elif ev.type == pygame.KEYDOWN and ev.key == pygame.K_ESCAPE:
                        running = False
                    elif ev.type in (pygame.MOUSEBUTTONDOWN, pygame.FINGERDOWN,
                                     pygame.MOUSEMOTION, pygame.FINGERMOTION,
                                     pygame.MOUSEBUTTONUP, pygame.FINGERUP):
                        if ev.type in (pygame.FINGERDOWN, pygame.FINGERMOTION, pygame.FINGERUP):
                            cal = self.cfg.touch
                            # SDL normalises finger coords to 0..1; project back onto the
                            # configured raw range so swap/invert knobs actually apply.
                            raw_x = cal.x_min + ev.x * (cal.x_max - cal.x_min)
                            raw_y = cal.y_min + ev.y * (cal.y_max - cal.y_min)
                            pos = cal.to_screen(int(raw_x), int(raw_y),
                                                self.cfg.width, self.cfg.height)
                        else:
                            pos = ev.pos          # mouse in --windowed mode needs no calibration

                        if ev.type in (pygame.MOUSEBUTTONDOWN, pygame.FINGERDOWN):
                            self._drag_start = pos
                            self._drag_moved = False
                            self.nav.touch(now)
                        elif ev.type in (pygame.MOUSEMOTION, pygame.FINGERMOTION):
                            if self._drag_start is not None:
                                dy = pos[1] - self._drag_start[1]
                                if abs(dy) > 8:
                                    self._drag_moved = True
                                    key = self.scroll_key(self.nav.current)
                                    self.scroll[key] = max(
                                        0, self.scroll.get(key, 0) + (1 if dy < 0 else -1))
                                    self._drag_start = pos  # re-anchor so drag is continuous
                        elif ev.type in (pygame.MOUSEBUTTONUP, pygame.FINGERUP):
                            if self._drag_start is not None and not self._drag_moved:
                                self._dispatch_touch(self._drag_start, now)
                            self._drag_start = None
                            self._drag_moved = False
                snap = self.collector.snapshot()
                self._check_preemption(snap, now)
                self.nav.tick(now)
                self.render_once(snap)
                pygame.display.flip()
                clock.tick(self.cfg.fps)
        finally:
            pygame.quit()
