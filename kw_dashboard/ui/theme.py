"""Palette and type scale. Values derived via the dataviz skill.

Palette derivation (dataviz skill, references/palette.md — dark mode, always-on
panel viewed in a room):
  bg     = dark "page plane"     #0d0d0d
  panel  = dark "chart surface"  #1a1a19
  fg     = dark "primary ink"    #ffffff
  dim    = dark "secondary ink"  #c3c2b7
  accent = categorical slot 1 (blue), dark step  #3987e5
  ok/warn/crit = status colours, deliberately re-derived (fix round 1) from
    the skill's fixed status palette to add LUMINANCE separation on top of
    hue: ok #288c28 (deep green), warn #fab219, crit #ff8c8c (bright/light
    red). ok-vs-crit hue alone is a classic red-green CVD failure — a
    deuteranope/protanope sees two similarly-bright blobs. Making crit
    noticeably brighter than ok means "bright = alarming" reads correctly
    even with zero hue perception, and both still clear >=4.5:1 against bg.
    DO NOT "tidy" ok/crit back to matched luminance — the separation is the
    point, pinned by test_ok_and_crit_are_luminance_separated_for_cvd.

Validated with the skill's `scripts/validate_palette.js` against the dark
surface #1a1a19: chroma floor, adjacent/CVD separation, and contrast vs
surface all PASS for accent+status together (worst CVD ΔE 11.3, worst
normal-vision ΔE 27.6, all >= 3:1 contrast). The lightness-band check flags
a matched-luminance warning step — that check is scoped to categorical
palettes; the status palette is fixed/reserved, not categorical, so it is
exempt and hand-tuned per role. Colour is reserved for state: accent is the
only "normal" hue, ok/warn/crit are used only to signal state, never
decoratively.

FONT_SIZES honours the spec's 26px legibility floor for every glanceable
size. `mono` at 20px is the single documented exception (spec section 8):
logs are a lean-in activity and 26px monospace fits only ~78 columns.
"""
from __future__ import annotations
from dataclasses import dataclass

FONT_SIZES = {"huge": 120, "big": 64, "body": 30, "small": 26, "mono": 20}

WARN_AT, CRIT_AT = 70.0, 88.0


@dataclass(frozen=True)
class Theme:
    bg: tuple
    fg: tuple
    dim: tuple
    panel: tuple
    accent: tuple
    ok: tuple
    warn: tuple
    crit: tuple


THEME = Theme(
    bg=(13, 13, 13), fg=(255, 255, 255), dim=(195, 194, 183),
    panel=(26, 26, 25), accent=(57, 135, 229),
    ok=(40, 140, 40), warn=(250, 178, 25), crit=(255, 140, 140))


def state_color(pct: float, theme: Theme = THEME) -> tuple:
    """Colour is reserved for state, so it always carries meaning."""
    pct = min(100.0, max(0.0, pct))
    if pct >= CRIT_AT:
        return theme.crit
    if pct >= WARN_AT:
        return theme.warn
    return theme.ok
