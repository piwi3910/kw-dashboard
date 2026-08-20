import textwrap
from kw_dashboard.config import Config, load_config


def test_defaults_are_720p():
    c = Config()
    assert (c.width, c.height) == (1280, 720)
    assert c.rotate_seconds == 15
    assert c.touch_pause_seconds == 60
    assert c.idle_reset_seconds == 120


def test_load_config_overrides_from_toml(tmp_path):
    p = tmp_path / "c.toml"
    p.write_text(
        textwrap.dedent("""
        rotate_seconds = 30
    """)
    )
    c = load_config(str(p))
    assert c.rotate_seconds == 30
    assert c.width == 1280  # untouched default survives


def test_load_config_missing_file_returns_defaults():
    assert load_config("/nonexistent/x.toml").rotate_seconds == 15
