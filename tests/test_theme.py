from kw_dashboard.ui.theme import state_color, Theme, FONT_SIZES

def test_state_color_thresholds_are_distinct():
    ok, warn, crit = state_color(10), state_color(75), state_color(95)
    assert ok != warn != crit and ok != crit

def test_font_sizes_respect_26px_legibility_floor():
    # spec section 2: glanceable text floor is 26px at ~1m on a 9" panel
    for name in ("huge", "big", "body", "small"):
        assert FONT_SIZES[name] >= 26, f"{name} below legibility floor"

def test_mono_is_the_documented_exception():
    # spec section 8: log view alone relaxes the floor
    assert FONT_SIZES["mono"] == 20

def test_state_color_clamps_out_of_range():
    assert state_color(-5) == state_color(0)
    assert state_color(150) == state_color(100)


def _rel_luminance(rgb):
    def ch(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(x) for x in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def _contrast(a, b):
    la, lb = _rel_luminance(a), _rel_luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

def test_ok_and_crit_are_luminance_separated_for_cvd():
    """ok vs crit must not rely on hue alone - red/green CVD would collapse them."""
    from kw_dashboard.ui.theme import THEME
    assert _contrast(THEME.ok, THEME.crit) >= 1.8

def test_status_colors_readable_on_background():
    from kw_dashboard.ui.theme import THEME
    for c in (THEME.ok, THEME.warn, THEME.crit):
        assert _contrast(c, THEME.bg) >= 4.5
