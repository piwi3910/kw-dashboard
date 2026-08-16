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
                    elif ev.type in (pygame.MOUSEBUTTONDOWN, pygame.FINGERDOWN):
                        if ev.type == pygame.FINGERDOWN:
                            cal = self.cfg.touch
                            # SDL normalises finger coords to 0..1; project back onto the
                            # configured raw range so swap/invert knobs actually apply.
                            raw_x = cal.x_min + ev.x * (cal.x_max - cal.x_min)
                            raw_y = cal.y_min + ev.y * (cal.y_max - cal.y_min)
                            pos = cal.to_screen(int(raw_x), int(raw_y),
                                                self.cfg.width, self.cfg.height)
                        else:
                            pos = ev.pos          # mouse in --windowed mode needs no calibration
                        self._dispatch_touch(pos, now)
                snap = self.collector.snapshot()
                self._check_preemption(snap, now)
                self.nav.tick(now)
                self.render_once(snap)
                pygame.display.flip()
                clock.tick(self.cfg.fps)
        finally:
            pygame.quit()
