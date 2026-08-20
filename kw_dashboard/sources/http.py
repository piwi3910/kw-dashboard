"""Minimal JSON GET over stdlib urllib. Read-only by construction: no verb
other than GET is offered anywhere in this module."""

from __future__ import annotations
import json, ssl, urllib.parse, urllib.request


class HttpError(Exception):
    """Any failure reaching or decoding an endpoint."""


def build_url(url: str, params: dict | None) -> str:
    if not params:
        return url
    return f"{url}?{urllib.parse.urlencode(params)}"


def get_json(
    url: str,
    *,
    token: str | None = None,
    ca: str | None = None,
    timeout: float = 8.0,
    params: dict | None = None,
) -> dict:
    full_url = build_url(url, params)
    req = urllib.request.Request(full_url, method="GET")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    ctx = None
    if url.startswith("https"):
        ctx = (
            ssl.create_default_context(cafile=ca)
            if ca
            else ssl._create_unverified_context()
        )
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            return json.loads(r.read().decode())
    except Exception as e:
        raise HttpError(f"GET {full_url}: {e}") from e


def get_text(
    url: str,
    *,
    token: str | None = None,
    ca: str | None = None,
    timeout: float = 8.0,
    params: dict | None = None,
) -> str:
    """Plain-text GET, used for the pod log endpoint."""
    full_url = build_url(url, params)
    req = urllib.request.Request(full_url, method="GET")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    ctx = None
    if url.startswith("https"):
        ctx = (
            ssl.create_default_context(cafile=ca)
            if ca
            else ssl._create_unverified_context()
        )
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            return r.read().decode(errors="replace")
    except Exception as e:
        raise HttpError(f"GET {full_url}: {e}") from e
