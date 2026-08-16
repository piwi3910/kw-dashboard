"""Page 4: calm when clear, ranked list when firing."""
from __future__ import annotations
import time
import pygame
from ..theme import THEME
from ..widgets import draw_header, TOUCH_MIN_H

SEV_COLOR = {"critical": THEME.crit, "warning": THEME.warn, "info": THEME.accent}

MAX_ROWS = 6
ROWS_TOP = 70
DISMISS_TOP = 640
MAX_ROW_H = 400  # a lone critical alert should dominate the screen


def render(surf, snap, nav, fonts, app):
    draw_header(surf, "ALERTS", fonts, right_text=time.strftime("%H:%M"))
    hits = []
    if not snap.alerts:
        t = fonts["big"].render("all quiet", True, THEME.ok)
        surf.blit(t, t.get_rect(center=(surf.get_width() // 2, 320)))
        s = fonts["small"].render("no alerts firing", True, THEME.dim)
        surf.blit(s, s.get_rect(center=(surf.get_width() // 2, 390)))
        return hits

    shown = snap.alerts[:MAX_ROWS]
    extra = len(snap.alerts) - len(shown)
    gap = 14
    footer_h = 34 if extra else 0  # room for the "+N more" line

    # Row pitch is computed from the space actually available (header to
    # DISMISS button) rather than a fixed stack, so a lone alert becomes a
    # large, prominent card instead of a small one marooned at the top.
    available = DISMISS_TOP - ROWS_TOP - footer_h - 10
    pitch = available / len(shown)
    row_h = max(TOUCH_MIN_H, min(pitch - gap, MAX_ROW_H))

    name_h = fonts["body"].get_height()
    small_h = fonts["small"].get_height()
    block_h = name_h + 6 + small_h

    y = ROWS_TOP
    for a in shown:
        rect = pygame.Rect(30, int(y), surf.get_width() - 60, int(row_h))
        pygame.draw.rect(surf, THEME.panel, rect, border_radius=6)
        pygame.draw.rect(surf, SEV_COLOR.get(a.severity, THEME.dim),
                         pygame.Rect(rect.x, rect.y, 8, rect.height), border_radius=4)

        text_y = rect.y + max(8, (rect.height - block_h) // 2)
        surf.blit(fonts["body"].render(a.name, True, THEME.fg), (rect.x + 26, text_y))
        # Severity is also rendered as text (not colour alone): colour-vision
        # deficiency can make the stripe alone unreadable as a signal.
        sev_color = SEV_COLOR.get(a.severity, THEME.dim)
        sev_text = fonts["small"].render(a.severity.upper(), True, sev_color)
        surf.blit(sev_text, (rect.right - sev_text.get_width() - 20, text_y))
        surf.blit(fonts["small"].render(a.summary[:64], True, THEME.dim),
                  (rect.x + 26, text_y + name_h + 6))
        y += row_h + gap

    if extra:
        surf.blit(fonts["small"].render(f"+{extra} more", True, THEME.dim), (36, int(y)))

    # Dismissing clears local screen pre-emption so rotation can resume.
    # This does NOT silence the alert upstream in Alertmanager.
    ack = pygame.Rect(surf.get_width() - 220, DISMISS_TOP, 190, TOUCH_MIN_H)
    pygame.draw.rect(surf, THEME.panel, ack, border_radius=6)
    surf.blit(fonts["small"].render("DISMISS", True, THEME.accent),
              (ack.x + 18, ack.y + 16))
    hits.append((ack, lambda: nav.clear_preempt(time.time())))
    return hits
