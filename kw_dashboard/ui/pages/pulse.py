"""Page 2: the cluster-is-alive view. Throughput plus a rolling event feed."""
from __future__ import annotations
import time
import pygame
from ..theme import THEME
from ..widgets import draw_header, draw_sparkline
from ..sorting import fmt_bytes

MAX_EVENT_ROWS = 6


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

    # The sparkline is the "cluster is alive" signal, so it gets the bulk of
    # the vertical room instead of a thin strip clustered near the top.
    if snap.cpu_history:
        draw_sparkline(surf, pygame.Rect(80, 220, surf.get_width() - 160, 180),
                       list(snap.cpu_history), THEME.accent)

    surf.blit(fonts["small"].render("RECENT EVENTS", True, THEME.dim), (80, 430))
    if len(snap.events) > MAX_EVENT_ROWS:
        shown, extra = snap.events[:MAX_EVENT_ROWS - 1], len(snap.events) - (MAX_EVENT_ROWS - 1)
    else:
        shown, extra = snap.events, 0

    y = 470
    line_h = 40
    for e in shown:
        color = THEME.warn if e.warning else THEME.dim
        line = f"{e.reason}  {e.namespace}/{e.obj}"
        surf.blit(fonts["small"].render(line[:58], True, color), (80, y))
        y += line_h
    if extra:
        surf.blit(fonts["small"].render(f"+{extra} more", True, THEME.dim), (80, y))
    return []
