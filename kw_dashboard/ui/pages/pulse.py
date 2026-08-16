"""Page 2: the cluster-is-alive view. Throughput plus a rolling event feed."""
from __future__ import annotations
import time
import pygame
from ..theme import THEME
from ..widgets import draw_header, draw_sparkline
from ..sorting import fmt_bytes


def render(surf, snap, nav, fonts, app):
    draw_header(surf, "PULSE", fonts, right_text=time.strftime("%H:%M"))

    # 380px columns (not the brief's 340px): "999.9 MB/s" at the big font
    # measures ~358px, which would run into a 340px-wide column.
    for i, (label, val) in enumerate((("NET RX", snap.net_rx), ("NET TX", snap.net_tx))):
        x = 80 + i * 380
        t = fonts["big"].render(f"{fmt_bytes(val)}/s", True, THEME.fg)
        surf.blit(t, (x, 90))
        surf.blit(fonts["small"].render(label, True, THEME.dim), (x, 160))

    restarts = sum(1 for e in snap.events if e.warning)
    t = fonts["big"].render(str(restarts), True,
                            THEME.warn if restarts else THEME.ok)
    surf.blit(t, (840, 90))
    surf.blit(fonts["small"].render("WARN EVENTS", True, THEME.dim), (840, 160))

    if snap.cpu_history:
        draw_sparkline(surf, pygame.Rect(80, 210, surf.get_width() - 160, 60),
                       list(snap.cpu_history), THEME.accent)

    surf.blit(fonts["small"].render("RECENT EVENTS", True, THEME.dim), (80, 300))
    y = 340
    for e in snap.events[:6]:
        color = THEME.warn if e.warning else THEME.dim
        line = f"{e.reason}  {e.namespace}/{e.obj}"
        surf.blit(fonts["small"].render(line[:58], True, color), (80, y))
        y += 40
    return []
