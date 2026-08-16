"""Page 1: the default glanceable view. Two gauges, pod count, node strip."""
from __future__ import annotations
import time
import pygame
from ..theme import THEME, state_color
from ..widgets import draw_arc_gauge, draw_sparkline, draw_header
from ...nav import View, PAGES
from ...collector import is_stale


def render(surf, snap, nav, fonts, app):
    stale = is_stale(snap, "prom", limit=45)
    status = "STALE" if stale else ("ALERT" if snap.alerts else "OK")
    draw_header(surf, "KW CLUSTER", fonts,
                right_text=f"{time.strftime('%H:%M')}   {status}", stale=stale)

    draw_arc_gauge(surf, (250, 250), 110, snap.cluster_cpu, "CPU", fonts)
    draw_arc_gauge(surf, (560, 250), 110, snap.cluster_mem, "MEM", fonts)

    pods = fonts["huge"].render(str(snap.pods_running), True, THEME.fg)
    surf.blit(pods, pods.get_rect(center=(960, 220)))
    lab = fonts["small"].render("PODS RUNNING", True, THEME.dim)
    surf.blit(lab, lab.get_rect(center=(960, 300)))

    if snap.cpu_history:
        draw_sparkline(surf, pygame.Rect(140, 380, 220, 50),
                       list(snap.cpu_history), THEME.accent)
    if snap.mem_history:
        draw_sparkline(surf, pygame.Rect(450, 380, 220, 50),
                       list(snap.mem_history), THEME.accent)

    hits = []
    n = len(snap.nodes) or 1
    bw, gap = 128, 12
    total = n * bw + (n - 1) * gap
    x0 = (surf.get_width() - total) // 2
    for i, node in enumerate(snap.nodes):
        x = x0 + i * (bw + gap)
        rect = pygame.Rect(x, 470, bw, 90)   # >=60px touch target
        color = THEME.crit if not node.ready else state_color(node.worst_pct)
        pygame.draw.rect(surf, THEME.panel, rect, border_radius=6)
        fill_h = int(rect.height * min(100.0, node.worst_pct) / 100.0)
        if fill_h:
            pygame.draw.rect(surf, color, pygame.Rect(
                rect.x, rect.bottom - fill_h, rect.width, fill_h), border_radius=6)
        short = node.name.split("-")[-1]
        t = fonts["small"].render(short, True, THEME.fg)
        surf.blit(t, t.get_rect(center=(rect.centerx, rect.bottom + 24)))
        hits.append((rect, lambda nm=node.name: nav.push(
            View("node", {"node": nm}), now=time.time())))

    ready = sum(1 for x in snap.nodes if x.ready)
    summary = fonts["body"].render(f"{ready}/{len(snap.nodes)} nodes up", True, THEME.dim)
    surf.blit(summary, (surf.get_width() - summary.get_width() - 24, 620))

    for i, _ in enumerate(PAGES):
        c = THEME.accent if i == nav.page_index else THEME.panel
        pygame.draw.circle(surf, c, (560 + i * 30, 690), 7)
    return hits
