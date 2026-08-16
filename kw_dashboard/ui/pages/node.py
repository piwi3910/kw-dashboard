"""Node detail, reached by tapping a node bar on page 1."""
from __future__ import annotations
import time
import pygame
from ..theme import THEME, state_color
from ..widgets import draw_bar, draw_back_button, draw_list_row, TOUCH_MIN_H
from ..sorting import sort_pods
from ...nav import View


def render(surf, snap, nav, fonts, app):
    name = nav.current.params.get("node", "")
    node = next((n for n in snap.nodes if n.name == name), None)
    hits = [(draw_back_button(surf, fonts), nav.pop)]

    title = fonts["body"].render(name, True, THEME.fg)
    surf.blit(title, (110, 18))
    if node is None:
        surf.blit(fonts["body"].render("node not found", True, THEME.dim), (110, 100))
        return hits

    state = "NOT READY" if not node.ready else ("CORDONED" if node.cordoned else "READY")
    col = THEME.crit if not node.ready else (THEME.warn if node.cordoned else THEME.ok)
    surf.blit(fonts["body"].render(state, True, col), (surf.get_width() - 280, 18))

    rows = [("CPU", node.cpu_pct, f"{node.cpu_pct:.0f}%"),
            ("MEMORY", node.mem_pct, f"{node.mem_pct:.0f}%"),
            ("TEMP", (node.temp_c or 0.0),
             f"{node.temp_c:.0f} C" if node.temp_c is not None else "n/a")]
    y = 90
    for label, pct, text in rows:
        surf.blit(fonts["small"].render(label, True, THEME.dim), (40, y))
        draw_bar(surf, pygame.Rect(200, y + 6, 700, 22), pct)
        surf.blit(fonts["small"].render(text, True, THEME.fg), (930, y))
        y += 56

    surf.blit(fonts["small"].render(f"{node.pods} pods", True, THEME.dim), (40, y + 6))

    pods = sort_pods([p for p in getattr(snap, "pods", []) if p.node == name])[:5]
    y += 50
    for p in pods:
        rect = pygame.Rect(40, y, surf.get_width() - 80, TOUCH_MIN_H)
        draw_list_row(surf, rect, f"{p.namespace}/{p.name}",
                      f"{p.ready}/{p.total}", fonts, warn=not p.healthy)
        hits.append((rect, lambda ns=p.namespace, pn=p.name: nav.push(
            View("pod", {"ns": ns, "pod": pn}), now=time.time())))
        y += TOUCH_MIN_H + 8
    return hits
