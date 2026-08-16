"""Page 4: calm when clear, ranked list when firing."""
from __future__ import annotations
import time
import pygame
from ..theme import THEME
from ..widgets import draw_header, TOUCH_MIN_H

SEV_COLOR = {"critical": THEME.crit, "warning": THEME.warn, "info": THEME.accent}


def render(surf, snap, nav, fonts, app):
    draw_header(surf, "ALERTS", fonts, right_text=time.strftime("%H:%M"))
    hits = []
    if not snap.alerts:
        t = fonts["big"].render("all quiet", True, THEME.ok)
        surf.blit(t, t.get_rect(center=(surf.get_width() // 2, 320)))
        s = fonts["small"].render("no alerts firing", True, THEME.dim)
        surf.blit(s, s.get_rect(center=(surf.get_width() // 2, 390)))
        return hits

    y = 90
    for a in snap.alerts[:6]:
        rect = pygame.Rect(30, y, surf.get_width() - 60, TOUCH_MIN_H + 18)
        pygame.draw.rect(surf, THEME.panel, rect, border_radius=6)
        pygame.draw.rect(surf, SEV_COLOR.get(a.severity, THEME.dim),
                         pygame.Rect(rect.x, rect.y, 8, rect.height), border_radius=4)
        surf.blit(fonts["body"].render(a.name, True, THEME.fg), (rect.x + 26, rect.y + 8))
        surf.blit(fonts["small"].render(a.summary[:64], True, THEME.dim),
                  (rect.x + 26, rect.y + 44))
        y += TOUCH_MIN_H + 26

    # Dismissing clears local screen pre-emption so rotation can resume.
    # This does NOT silence the alert upstream in Alertmanager.
    ack = pygame.Rect(surf.get_width() - 220, 640, 190, TOUCH_MIN_H)
    pygame.draw.rect(surf, THEME.panel, ack, border_radius=6)
    surf.blit(fonts["small"].render("DISMISS", True, THEME.accent),
              (ack.x + 18, ack.y + 16))
    hits.append((ack, lambda: nav.clear_preempt(time.time())))
    return hits
