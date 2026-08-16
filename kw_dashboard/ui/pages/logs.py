"""Log view. Deliberately uses 20px monospace, below the 26px glanceable
floor: logs are a lean-in activity and 26px fits only ~78 columns (spec 8)."""
from __future__ import annotations
import pygame
from ..theme import THEME
from ..widgets import draw_back_button, TOUCH_MIN_H
from ...logstream import wrap_line


def render(surf, snap, nav, fonts, app):
    p = nav.current.params
    ns, pod, container = p.get("ns", ""), p.get("pod", ""), p.get("container")
    hits = [(draw_back_button(surf, fonts), nav.pop)]
    surf.blit(fonts["small"].render(f"{pod}/{container}"[:48], True, THEME.fg), (110, 24))

    app._ensure_cache()
    stream = app.view_cache.get(("logs", ns, pod, container))
    if stream is None:
        stream = app.fetch_logs(ns, pod, container)
        surf.blit(fonts["small"].render("loading...", True, THEME.dim), (30, 90))
        return hits

    mono = fonts["mono"]
    char_w = mono.size("M")[0] or 11
    cols = max(20, (surf.get_width() - 60) // char_w)
    line_h = mono.get_linesize()
    rows = (surf.get_height() - 130) // line_h

    wrapped: list[str] = []
    for ln in stream.visible(rows=rows):
        wrapped.extend(wrap_line(ln, cols))
    wrapped = wrapped[-rows:]

    y = 80
    for ln in wrapped:
        surf.blit(mono.render(ln, True, THEME.fg), (30, y))
        y += line_h

    up = pygame.Rect(surf.get_width() - 200, surf.get_height() - 70, 90, TOUCH_MIN_H)
    live = pygame.Rect(surf.get_width() - 100, surf.get_height() - 70, 90, TOUCH_MIN_H)
    for rect, label, color in ((up, "^", THEME.accent),
                               (live, "LIVE",
                                THEME.ok if stream.follow else THEME.dim)):
        pygame.draw.rect(surf, THEME.panel, rect, border_radius=6)
        surf.blit(fonts["small"].render(label, True, color), (rect.x + 14, rect.y + 16))
    hits.append((up, lambda: stream.scroll_up(rows // 2)))
    hits.append((live, stream.jump_to_live))
    return hits
