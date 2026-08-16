"""Page 3: generic namespace -> pod explorer. Nothing app-specific; every
workload is discovered from the API."""
from __future__ import annotations
import time
import pygame
from ..theme import THEME, state_color
from ..widgets import (draw_header, draw_list_row, draw_back_button,
                       draw_bar, TOUCH_MIN_H)
from ..sorting import sort_namespaces, sort_pods, fmt_bytes
from ...nav import View

ROW_H = TOUCH_MIN_H + 8
LIST_TOP = 80


def _rows_visible(surf) -> int:
    return (surf.get_height() - LIST_TOP - 20) // ROW_H


def _page_and_indicator(surf, app, nav, items):
    """Clamp the scroll offset for the current view and slice out the visible
    page. Returns (page, hidden_below) so callers can draw a "+N more"."""
    rows = _rows_visible(surf)
    key = app.scroll_key(nav.current)
    off = app.scroll.get(key, 0)
    off = max(0, min(off, max(0, len(items) - rows)))
    app.scroll[key] = off
    page = items[off: off + rows]
    hidden = max(0, len(items) - off - len(page))
    return page, hidden


def _draw_more(surf, fonts, hidden, y):
    if hidden:
        t = fonts["small"].render(f"+{hidden} more", True, THEME.dim)
        surf.blit(t, (surf.get_width() - t.get_width() - 30, y))


def render_namespaces(surf, snap, nav, fonts, app):
    draw_header(surf, "NAMESPACES", fonts, right_text=str(len(snap.namespaces)))
    hits = []
    items = sort_namespaces(snap.namespaces)
    page, hidden = _page_and_indicator(surf, app, nav, items)
    y = LIST_TOP
    for ns in page:
        rect = pygame.Rect(30, y, surf.get_width() - 60, TOUCH_MIN_H)
        right = f"{ns.pods} pods   {fmt_bytes(ns.mem_bytes)}"
        draw_list_row(surf, rect, ns.name, right, fonts, warn=bool(ns.unhealthy))
        hits.append((rect, lambda n=ns.name: (
            app.fetch_pods(n), nav.push(View("namespace", {"ns": n}), now=time.time()))))
        y += ROW_H
    _draw_more(surf, fonts, hidden, y)
    return hits


def render_namespace(surf, snap, nav, fonts, app):
    ns = nav.current.params.get("ns", "")
    hits = [(draw_back_button(surf, fonts), nav.pop)]
    surf.blit(fonts["body"].render(ns, True, THEME.fg), (110, 18))

    app._ensure_cache()
    pods = app.view_cache.get(("pods", ns))
    if pods is None:
        err = app.view_cache.get(("err", ns))
        if err:
            surf.blit(fonts["small"].render(f"error: {err}"[:70], True, THEME.crit),
                      (30, LIST_TOP))
        else:
            app.fetch_pods(ns)
            surf.blit(fonts["small"].render("loading...", True, THEME.dim), (30, LIST_TOP))
        return hits

    items = sort_pods(pods)
    page, hidden = _page_and_indicator(surf, app, nav, items)
    y = LIST_TOP
    for p in page:
        rect = pygame.Rect(30, y, surf.get_width() - 60, TOUCH_MIN_H)
        right = f"{p.ready}/{p.total}  {p.restarts}R  {p.phase}"
        draw_list_row(surf, rect, p.name[:40], right, fonts, warn=not p.healthy)
        hits.append((rect, lambda pn=p.name: nav.push(
            View("pod", {"ns": ns, "pod": pn}), now=time.time())))
        y += ROW_H
    _draw_more(surf, fonts, hidden, y)
    return hits


def render_pod(surf, snap, nav, fonts, app):
    ns = nav.current.params.get("ns", "")
    name = nav.current.params.get("pod", "")
    hits = [(draw_back_button(surf, fonts), nav.pop)]
    surf.blit(fonts["body"].render(f"{ns}/{name}"[:44], True, THEME.fg), (110, 18))

    app._ensure_cache()
    pods = app.view_cache.get(("pods", ns)) or []
    pod = next((p for p in pods if p.name == name), None)
    if pod is None:
        surf.blit(fonts["small"].render("pod not found", True, THEME.dim), (30, LIST_TOP))
        return hits

    facts = [("PHASE", pod.phase), ("READY", f"{pod.ready}/{pod.total}"),
             ("RESTARTS", str(pod.restarts)), ("NODE", pod.node)]
    y = LIST_TOP
    for label, value in facts:
        surf.blit(fonts["small"].render(label, True, THEME.dim), (40, y))
        color = THEME.crit if label == "RESTARTS" and pod.restarts > 0 else THEME.fg
        surf.blit(fonts["small"].render(value, True, color), (280, y))
        y += 46

    y += 10
    rows = max(1, (surf.get_height() - y - 20) // ROW_H)
    key = app.scroll_key(nav.current)
    off = app.scroll.get(key, 0)
    off = max(0, min(off, max(0, len(pod.containers) - rows)))
    app.scroll[key] = off
    page = pod.containers[off: off + rows]
    for c in page:
        rect = pygame.Rect(30, y, surf.get_width() - 60, TOUCH_MIN_H)
        draw_list_row(surf, rect, f"logs: {c}", ">", fonts)
        hits.append((rect, lambda cn=c: (
            app.fetch_logs(ns, name, cn),
            nav.push(View("logs", {"ns": ns, "pod": name, "container": cn}),
                     now=time.time()))))
        y += ROW_H
    hidden = max(0, len(pod.containers) - off - len(page))
    _draw_more(surf, fonts, hidden, y)
    return hits


def render(surf, snap, nav, fonts, app):
    return render_namespaces(surf, snap, nav, fonts, app)
