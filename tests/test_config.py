import textwrap
from kw_dashboard.config import Config, load_config, TouchCalibration

def test_defaults_are_720p():
    c = Config()
    assert (c.width, c.height) == (1280, 720)
    assert c.rotate_seconds == 15
    assert c.touch_pause_seconds == 60
    assert c.idle_reset_seconds == 120

def test_touch_calibration_maps_raw_to_screen():
    cal = TouchCalibration(x_min=0, x_max=4095, y_min=0, y_max=4095,
                           swap_xy=False, invert_x=False, invert_y=False)
    assert cal.to_screen(0, 0, 1280, 720) == (0, 0)
    assert cal.to_screen(4095, 4095, 1280, 720) == (1279, 719)

def test_touch_calibration_inverts_and_swaps():
    cal = TouchCalibration(x_min=0, x_max=4095, y_min=0, y_max=4095,
                           swap_xy=True, invert_x=False, invert_y=True)
    # swap first, then invert y of the swapped result
    assert cal.to_screen(0, 4095, 1280, 720) == (1279, 719)

def test_load_config_overrides_from_toml(tmp_path):
    p = tmp_path / "c.toml"
    p.write_text(textwrap.dedent("""
        rotate_seconds = 30
        [touch]
        swap_xy = true
    """))
    c = load_config(str(p))
    assert c.rotate_seconds == 30
    assert c.touch.swap_xy is True
    assert c.width == 1280  # untouched default survives

def test_load_config_missing_file_returns_defaults():
    assert load_config("/nonexistent/x.toml").rotate_seconds == 15
