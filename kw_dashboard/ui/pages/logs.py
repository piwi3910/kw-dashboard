"""Log view. Deliberately uses 20px monospace, below the 26px glanceable
floor: logs are a lean-in activity and 26px fits only ~78 columns (spec 8)."""
from __future__ import annotations
import pygame
from ..theme import THEME
from ..widgets import draw_back_button, TOUCH_MIN_H
from ...logstream import wrap_line

_LEVELS = {"INFO", "WARN", "WARNING", "ERROR", "ERR", "DEBUG", "TRACE", "FATAL"}
_WARN_LEVELS = {"WARN", "WARNING"}
_CRIT_LEVELS = {"ERROR", "ERR", "FATAL"}

# Column layout: timestamp | level | message, all fixed-width so the eye can
# scan straight down each column. 24 chars covers a full RFC3339-with-millis
# stamp ("2026-08-16T15:02:11.884Z"); 5 covers the longest common level
# token ("ERROR"). Real logs vary — a longer level just pushes the message
# column right on that one row rather than truncating anything.
TS_COL = 24
LEVEL_COL = 5
PREFIX = TS_COL + 1 + LEVEL_COL + 1


def split_log_line(line: str) -> tuple[str, str, str]:
    """Split a log line into (timestamp, level, message).

    Returns "" for any part that is absent — the level in particular is
    the container's own convention, not something Kubernetes guarantees,
    so most lines legitimately have none. Never drops text: whatever isn't
    recognised as timestamp/level stays in the message verbatim.
    """
    if not line:
        return "", "", ""

    head, _, rest = line.partition(" ")
    if not (len(head) >= 5 and head[:4].isdigit() and head[4] == "-" and "T" in head):
        return "", "", line

    ts = head
    tok, _, rest2 = rest.partition(" ")
    if tok.upper() in _LEVELS:
        return ts, tok.upper(), rest2
    return ts, "", rest


def _level_color(level: str) -> tuple:
    if level in _CRIT_LEVELS:
        return THEME.crit
    if level in _WARN_LEVELS:
        return THEME.warn
    return THEME.dim


def _display_ts(ts: str, budget: int) -> str:
    """Truncate to time-of-day if the full timestamp won't fit its column."""
    if len(ts) <= budget:
        return ts
    return ts.split("T", 1)[1] if "T" in ts else ts[:budget]


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
    msg_cols = max(10, cols - PREFIX)

    # Each raw line becomes one or more display rows: (ts, level, text, is_first)
    display_rows: list[tuple[str, str, str, bool]] = []
    for ln in stream.visible(rows=rows):
        ts, level, msg = split_log_line(ln)
        ts = _display_ts(ts, TS_COL)
        segments = wrap_line(msg, msg_cols)
        for i, seg in enumerate(segments):
            display_rows.append((ts, level, seg, i == 0))
    display_rows = display_rows[-rows:]

    y = 80
    x0 = 30
    msg_x = x0 + PREFIX * char_w
    for ts, level, seg, is_first in display_rows:
        if is_first:
            surf.blit(mono.render(ts.ljust(TS_COL), True, THEME.dim), (x0, y))
            surf.blit(mono.render(level.ljust(LEVEL_COL), True, _level_color(level)),
                       (x0 + (TS_COL + 1) * char_w, y))
        surf.blit(mono.render(seg, True, THEME.fg), (msg_x, y))
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
