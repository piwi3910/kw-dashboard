import json, pytest
from unittest.mock import patch, MagicMock
from kw_dashboard.sources.http import get_json, build_url, HttpError


def test_build_url_encodes_params():
    u = build_url("http://x/api", {"query": 'up{job="a b"}', "limit": 3})
    assert u.startswith("http://x/api?")
    assert "query=up%7Bjob%3D%22a+b%22%7D" in u
    assert "limit=3" in u


def test_build_url_without_params():
    assert build_url("http://x/api", None) == "http://x/api"


def test_get_json_parses_body():
    resp = MagicMock()
    resp.read.return_value = json.dumps({"ok": True}).encode()
    resp.__enter__ = lambda s: s
    resp.__exit__ = lambda s, *a: None
    with patch("urllib.request.urlopen", return_value=resp):
        assert get_json("http://x") == {"ok": True}


def test_get_json_wraps_errors_as_httperror():
    with patch("urllib.request.urlopen", side_effect=OSError("refused")):
        with pytest.raises(HttpError):
            get_json("http://x")


def test_httperror_message_includes_query_params():
    with patch("urllib.request.urlopen", side_effect=OSError("refused")):
        with pytest.raises(HttpError) as exc:
            get_json("http://x/api", params={"query": "up"})
    assert "query=up" in str(exc.value)
