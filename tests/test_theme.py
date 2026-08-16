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
