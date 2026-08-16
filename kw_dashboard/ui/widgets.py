"""Reusable drawing primitives. Pure pygame; no data access."""
from __future__ import annotations
import math
import pygame
from .theme import THEME, state_color

TOUCH_MIN_H = 60  # spec global constraint


def _arc_ring(surf, center, radius, width, start_rad, end_rad, color, steps=64):
    cx, cy = center
    r_out, r_in = radius, radius - width
    pts_out, pts_in = [], []
    for i in range(steps + 1):
        a = start_rad + (end_rad - start_rad) * i / steps
        # pygame y grows downward, so negate the sine
        pts_out.append((cx + r_out * math.cos(a), cy - r_out * math.sin(a)))
        pts_in.append((cx + r_in * math.cos(a), cy - r_in * math.sin(a)))
    pygame.draw.polygon(surf, color, pts_out + list(reversed(pts_in)))


def draw_arc_gauge(surf, center, radius, pct, label, fonts, width=18):
    pct = min(100.0, max(0.0, pct))
    cx, cy = center
    start, sweep_end = math.radians(-215), math.radians(35)
    _arc_ring(surf, center, radius, width, start, sweep_end, THEME.panel)
    end = start + (math.radians(250) * pct / 100.0)
    if pct > 0:
        _arc_ring(surf, center, radius, width, start, end, state_color(pct))
    val = fonts["big"].render(f"{pct:.0f}%", True, THEME.fg)
    surf.blit(val, val.get_rect(center=(cx, cy - 6)))
    lab = fonts["small"].render(label, True, THEME.dim)
    surf.blit(lab, lab.get_rect(center=(cx, cy + radius - 10)))


def draw_sparkline(surf, rect, values, color=None):
    if len(values) < 2:
        return
    lo, hi = min(values), max(values)
    span = (hi - lo) or 1.0
    step = rect.width / (len(values) - 1)
    pts = [(rect.x + i * step, rect.bottom - ((v - lo) / span) * rect.height)
           for i, v in enumerate(values)]
    pygame.draw.lines(surf, color or THEME.accent, False, pts, 3)


def draw_bar(surf, rect, pct, color=None):
    pygame.draw.rect(surf, THEME.panel, rect, border_radius=4)
    w = int(rect.width * min(100.0, max(0.0, pct)) / 100.0)
    if w > 0:
        pygame.draw.rect(surf, color or state_color(pct),
                         pygame.Rect(rect.x, rect.y, w, rect.height), border_radius=4)


def draw_header(surf, title, fonts, right_text=None, stale=False):
    color = THEME.dim if stale else THEME.fg
    surf.blit(fonts["body"].render(title, True, color), (24, 18))
    if right_text:
        t = fonts["body"].render(right_text, True, THEME.dim)
        surf.blit(t, (surf.get_width() - t.get_width() - 24, 18))


def draw_back_button(surf, fonts) -> pygame.Rect:
    rect = pygame.Rect(8, 8, 90, TOUCH_MIN_H)
    surf.blit(fonts["body"].render("<", True, THEME.accent), (28, 18))
    return rect


def draw_list_row(surf, rect, left, right, fonts, pct=None, warn=False):
    """One touch-sized list row. Returns its rect for hit-testing."""
    pygame.draw.rect(surf, THEME.panel, rect, border_radius=6)
    color = THEME.crit if warn else THEME.fg
    surf.blit(fonts["small"].render(left, True, color), (rect.x + 16, rect.y + 14))
    if right:
        t = fonts["small"].render(right, True, THEME.dim)
        surf.blit(t, (rect.right - t.get_width() - 16, rect.y + 14))
    if pct is not None:
        draw_bar(surf, pygame.Rect(rect.x + 16, rect.bottom - 12,
                                   rect.width - 32, 6), pct)
    return rect
