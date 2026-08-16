"""Page 1: the default glanceable view — header, four stat cards, node table.

Rebuilt to match .superpowers/sdd/2026-08-16-kw-dashboard/design/2a.{png,html}
pixel-for-pixel. Geometry below is lifted straight from the HTML spec's
absolute coordinates; the structural greys (card fill, borders, row
dividers) live only there, not in THEME, so they are named constants here.
"""
from __future__ import annotations
import socket
import time
import pygame
from ..theme import THEME, state_color
from ..widgets import TOUCH_MIN_H
from ..sorting import fmt_bytes
from ...nav import View
from ...collector import is_stale
from ...sources.alerts import has_critical

# Structural greys from 2a.html — not part of THEME (that's reserved for
# state colours + the two ink levels).
HEADER_TOP = (26, 26, 25)      # #1a1a19
HEADER_BOTTOM = (17, 17, 16)   # #111110
BORDER = (38, 38, 36)          # #262624
CARD_TOP = (25, 25, 24)        # #191918
CARD_BOTTOM = (19, 19, 18)     # #131312
ROW_DIV = (28, 28, 27)         # #1c1c1b
SUBROW_DIV = (34, 34, 32)      # #222220
WARN_TINT = (250, 178, 25)
CRIT_TINT = (255, 140, 140)

HOSTNAME = socket.gethostname().split(".")[0].upper() or "KM01"


def _vgradient_rect(surf, rect, top, bottom):
    h = max(1, rect.height)
    for i in range(h):
        t = i / h
        c = tuple(int(top[k] + (bottom[k] - top[k]) * t) for k in range(3))
        pygame.draw.line(surf, c, (rect.x, rect.y + i), (rect.right, rect.y + i))


def _card(surf, rect, radius=10):
    _vgradient_rect_rounded(surf, rect, CARD_TOP, CARD_BOTTOM, radius)
    pygame.draw.rect(surf, BORDER, rect, width=1, border_radius=radius)


def _vgradient_rect_rounded(surf, rect, top, bottom, radius):
    mask = pygame.Surface(rect.size, pygame.SRCALPHA)
    pygame.draw.rect(mask, (255, 255, 255, 255), mask.get_rect(), border_radius=radius)
    grad = pygame.Surface(rect.size)
    h = max(1, rect.height)
    for i in range(h):
        t = i / h
        c = tuple(int(top[k] + (bottom[k] - top[k]) * t) for k in range(3))
        pygame.draw.line(grad, c, (0, i), (rect.width, i))
    grad = grad.convert_alpha()
    grad.blit(mask, (0, 0), special_flags=pygame.BLEND_RGBA_MULT)
    surf.blit(grad, rect.topleft)


def _mini_bar(surf, x, y, w, h, pct, color):
    pygame.draw.rect(surf, BORDER, (x, y, w, h), border_radius=h // 2)
    fw = int(w * min(100.0, max(0.0, pct)) / 100.0)
    if fw:
        pygame.draw.rect(surf, color, (x, y, fw, h), border_radius=h // 2)


def _area_sparkline(surf, rect, values, color):
    if len(values) < 2:
        return
    lo, hi = min(values), max(values)
    span = (hi - lo) or 1.0
    step = rect.width / (len(values) - 1)
    pts = [(rect.x + i * step, rect.bottom - (v - lo) / span * rect.height)
           for i, v in enumerate(values)]

    fill = pygame.Surface(rect.size, pygame.SRCALPHA)
    poly = [(px - rect.x, py - rect.y) for px, py in pts]
    poly += [(rect.width, rect.height), (0, rect.height)]
    pygame.draw.polygon(fill, (*color, 255), poly)
    grad = pygame.Surface(rect.size, pygame.SRCALPHA)
    top_a = int(0.34 * 255)
    for i in range(rect.height):
        a = int(top_a * (1 - i / rect.height))
        pygame.draw.line(grad, (255, 255, 255, a), (0, i), (rect.width, i))
    fill.blit(grad, (0, 0), special_flags=pygame.BLEND_RGBA_MULT)
    surf.blit(fill, rect.topleft)
    pygame.draw.lines(surf, color, False, pts, 3)


def render(surf, snap, nav, fonts, app):
    W = surf.get_width()
    stale = is_stale(snap, "prom", limit=45)

    # ---- header --------------------------------------------------------
    header = pygame.Rect(0, 0, W, 64)
    _vgradient_rect(surf, header, HEADER_TOP, HEADER_BOTTOM)
    pygame.draw.line(surf, BORDER, (0, 64), (W, 64))

    title_color = THEME.dim if stale else THEME.fg
    title_t = fonts["body"].render(HOSTNAME, True, title_color)
    surf.blit(title_t, (24, 18))
    sub = f"k3s · {len(snap.nodes)} nodes · {snap.pods_running} pods"
    surf.blit(fonts["small"].render(sub, True, THEME.dim), (24 + title_t.get_width() + 16, 20))

    clock = fonts["body"].render(time.strftime("%H:%M"), True, THEME.fg)
    clock_x = W - 24 - clock.get_width()
    surf.blit(clock, (clock_x, 18))

    if stale:
        status_color, status_text = THEME.dim, "STALE"
    elif has_critical(snap.alerts):
        status_color, status_text = THEME.crit, "ALERT"
    elif snap.alerts:
        status_color, status_text = THEME.warn, "ALERT"
    else:
        status_color, status_text = THEME.ok, "OK"
    status_txt = fonts["small"].render(status_text, True, status_color)
    status_block_w = 12 + 10 + status_txt.get_width()
    status_right = clock_x - 24
    dot_x = status_right - status_block_w
    pygame.draw.circle(surf, status_color, (dot_x + 6, 24 + 4), 6)
    surf.blit(status_txt, (dot_x + 22, 18))

    # ---- left column: CPU / MEMORY / PODS / NETWORK cards --------------
    cpu_rect = pygame.Rect(16, 80, 274, 298)
    mem_rect = pygame.Rect(302, 80, 274, 298)
    pods_rect = pygame.Rect(16, 390, 274, 314)
    net_rect = pygame.Rect(302, 390, 274, 314)

    for rect, label, pct, hist in (
            (cpu_rect, "CPU", snap.cluster_cpu, snap.cpu_history),
            (mem_rect, "MEMORY", snap.cluster_mem, snap.mem_history)):
        _card(surf, rect)
        surf.blit(fonts["small"].render(label, True, THEME.dim), (rect.x + 20, rect.y + 18))
        val = fonts["big"].render(f"{pct:.0f}%", True, THEME.fg)
        surf.blit(val, (rect.x + 20, rect.y + 44))
        peak = max(hist) if hist else pct
        peak_t = fonts["small"].render(f"peak {peak:.0f}% · 5 min", True, THEME.dim)
        surf.blit(peak_t, (rect.x + 20, rect.y + 150))
        if hist:
            spark_rect = pygame.Rect(rect.x + 2, rect.bottom - 92, rect.width - 4, 88)
            _area_sparkline(surf, spark_rect, list(hist), THEME.accent)

    # PODS card
    _card(surf, pods_rect)
    surf.blit(fonts["small"].render("PODS", True, THEME.dim), (pods_rect.x + 20, pods_rect.y + 18))
    val = fonts["big"].render(str(snap.pods_running), True, THEME.fg)
    surf.blit(val, (pods_rect.x + 20, pods_rect.y + 40))

    pending = sum(1 for p in snap.pods if p.phase == "Pending")
    unhealthy = sum(1 for p in snap.pods if not p.healthy)
    restarts = sum(p.restarts for p in snap.pods)
    stat_y = pods_rect.y + 158
    for i, (lab, val_txt, color) in enumerate((
            ("pending", str(pending), THEME.fg),
            ("unhealthy", str(unhealthy), THEME.warn if unhealthy else THEME.fg),
            ("restarts 1h", str(restarts), THEME.fg))):
        row_y = stat_y + i * 52
        pygame.draw.line(surf, SUBROW_DIV, (pods_rect.x, row_y), (pods_rect.right, row_y))
        surf.blit(fonts["small"].render(lab, True, THEME.dim), (pods_rect.x + 20, row_y + 13))
        vt = fonts["small"].render(val_txt, True, color)
        surf.blit(vt, (pods_rect.right - 20 - vt.get_width(), row_y + 13))

    # NETWORK card
    _card(surf, net_rect)
    surf.blit(fonts["small"].render("NETWORK", True, THEME.dim), (net_rect.x + 20, net_rect.y + 18))
    for i, (lab, val) in enumerate((("RX", snap.net_rx), ("TX", snap.net_tx))):
        y0 = net_rect.y + 66 + i * 124
        surf.blit(fonts["small"].render(lab, True, THEME.dim), (net_rect.x + 20, y0))
        rate = fonts["body"].render(f"{fmt_bytes(val)}/s", True, THEME.fg)
        surf.blit(rate, (net_rect.x + 20, y0 + 32))
        bar_w = net_rect.width - 40
        max_rate = 15 * 1024 * 1024  # scale reference; matches mockup proportions
        pct = min(100.0, val / max_rate * 100.0)
        _mini_bar(surf, net_rect.x + 20, y0 + 86, bar_w, 8, pct, THEME.accent)

    # ---- right panel: NODES table --------------------------------------
    table = pygame.Rect(588, 80, 676, 624)
    _card(surf, table)
    surf.blit(fonts["small"].render("NODES", True, THEME.fg), (table.x + 20, table.y + 14))
    ready_n = sum(1 for n in snap.nodes if n.ready)
    ready_t = fonts["small"].render(f"{ready_n} / {len(snap.nodes)} ready", True, THEME.dim)
    surf.blit(ready_t, (table.right - 20 - ready_t.get_width(), table.y + 14))
    pygame.draw.line(surf, BORDER, (table.x, table.y + 52), (table.right, table.y + 52))

    # column geometry: order (NODE, CPU, MEM, °C, PODS, STATE) mirrors
    # 2a.html, but positions are derived from *measured* label/value widths
    # rather than the HTML's raw pixel column widths — our rendered DejaVu
    # Sans runs wider than the mockup's browser metrics, so copying those
    # widths verbatim collided header text (particularly "PODS"/"STATE").
    small = fonts["small"]
    col_gap = 16
    col_node_x = table.x + 20
    node_col_w = max((small.size(nd.name)[0] for nd in snap.nodes), default=140)
    metric_w = 64 + 10 + small.size("99")[0]         # bar + gap + typical 2-digit number
    deg_w = max(small.size("°C")[0], small.size("99")[0])
    pods_w = max(small.size("PODS")[0], small.size("99")[0])
    state_w = max(small.size("STATE")[0], small.size("CORD")[0], small.size("DOWN")[0])

    col_cpu_x = col_node_x + node_col_w + col_gap
    col_mem_x = col_cpu_x + metric_w + col_gap
    col_deg_r = col_mem_x + metric_w + col_gap + deg_w
    col_pods_r = col_deg_r + col_gap + pods_w
    col_state_r = col_pods_r + col_gap + state_w

    head_y = table.y + 52
    surf.blit(fonts["small"].render("NODE", True, THEME.dim), (col_node_x, head_y + 6))
    surf.blit(fonts["small"].render("CPU", True, THEME.dim), (col_cpu_x, head_y + 6))
    surf.blit(fonts["small"].render("MEM", True, THEME.dim), (col_mem_x, head_y + 6))
    for text, right in (("°C", col_deg_r), ("PODS", col_pods_r),
                        ("STATE", col_state_r)):
        t = fonts["small"].render(text, True, THEME.dim)
        surf.blit(t, (right - t.get_width(), head_y + 6))
    pygame.draw.line(surf, SUBROW_DIV, (table.x, head_y + 40), (table.right, head_y + 40))

    hits = []
    n = len(snap.nodes) or 1
    body_top = head_y + 40
    row_h = (table.bottom - body_top) // n
    row_h = max(TOUCH_MIN_H, row_h)

    for i, node in enumerate(snap.nodes):
        ry = body_top + i * row_h
        row = pygame.Rect(table.x, ry, table.width, row_h)

        down = not node.ready
        # Cordoned alone gets the amber STATE text but not the row tint/
        # stripe — those are reserved for an actual hot/pressured node
        # (mirrors 2a.html: master-11 is cordoned with a plain row, only
        # worker-21's high CPU gets the amber stripe).
        warn = node.ready and not node.cordoned and node.worst_pct >= 70.0
        if down:
            tint, stripe = CRIT_TINT, CRIT_TINT
        elif warn:
            tint, stripe = WARN_TINT, WARN_TINT
        else:
            tint, stripe = None, None

        if tint:
            a = 0.07 if down else 0.05
            overlay = pygame.Surface((row.width, row.height), pygame.SRCALPHA)
            overlay.fill((*tint, int(255 * a)))
            surf.blit(overlay, row.topleft)
        if stripe:
            pygame.draw.rect(surf, stripe, (row.x, row.y, 4, row.height))
        if i < n - 1:
            pygame.draw.line(surf, ROW_DIV, (row.x, row.bottom), (row.right, row.bottom))

        cy = row.centery
        name_color = CRIT_TINT if down else THEME.fg
        name_t = fonts["small"].render(node.name, True, name_color)
        surf.blit(name_t, (col_node_x, cy - name_t.get_height() // 2))

        def _metric(x, pct, color, txt):
            _mini_bar(surf, x, cy - 4, 64, 8, pct, color)
            t = fonts["small"].render(txt, True, THEME.dim if color != CRIT_TINT else CRIT_TINT)
            surf.blit(t, (x + 64 + 10, cy - t.get_height() // 2))

        if down:
            for x in (col_cpu_x, col_mem_x):
                t = fonts["small"].render("—", True, THEME.dim)
                surf.blit(t, (x, cy - t.get_height() // 2))
            for right, txt in ((col_deg_r, "—"), (col_pods_r, "0")):
                t = fonts["small"].render(txt, True, THEME.dim)
                surf.blit(t, (right - t.get_width(), cy - t.get_height() // 2))
        else:
            cpu_color = state_color(node.cpu_pct)
            _metric(col_cpu_x, node.cpu_pct, cpu_color, f"{node.cpu_pct:.0f}")
            mem_color = state_color(node.mem_pct)
            _metric(col_mem_x, node.mem_pct, mem_color, f"{node.mem_pct:.0f}")
            deg_txt = "—" if node.temp_c is None else f"{node.temp_c:.0f}"
            t = fonts["small"].render(deg_txt, True, THEME.dim)
            surf.blit(t, (col_deg_r - t.get_width(), cy - t.get_height() // 2))
            t = fonts["small"].render(str(node.pods), True, THEME.fg)
            surf.blit(t, (col_pods_r - t.get_width(), cy - t.get_height() // 2))

        if down:
            state_text, state_color_v = "DOWN", CRIT_TINT
        elif node.cordoned:
            state_text, state_color_v = "CORD", WARN_TINT
        else:
            state_text, state_color_v = "ready", THEME.dim
        t = fonts["small"].render(state_text, True, state_color_v)
        surf.blit(t, (col_state_r - t.get_width(), cy - t.get_height() // 2))

        hits.append((row, lambda nm=node.name: nav.push(
            View("node", {"node": nm}), now=time.time())))

    return hits
