"""Log line parsing. Pure logic, no rendering dependency."""
from __future__ import annotations

_LEVELS = {"INFO", "WARN", "WARNING", "ERROR", "ERR", "DEBUG", "TRACE", "FATAL"}


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
