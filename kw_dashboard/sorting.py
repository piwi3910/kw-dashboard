"""Ordering rules for the explorer: problems first, then size."""
from __future__ import annotations


def sort_namespaces(items: list) -> list:
    return sorted(items, key=lambda n: (0 if n.unhealthy else 1,
                                        -n.unhealthy, -n.mem_bytes, n.name))


def sort_pods(items: list) -> list:
    return sorted(items, key=lambda p: (0 if not p.healthy else 1,
                                        -p.restarts, p.name))


def fmt_bytes(n: float) -> str:
    if n < 1024:
        return f"{int(n)} B"
    for unit in ("KB", "MB", "GB", "TB"):
        n /= 1024.0
        if n < 1024 or unit == "TB":
            return f"{n:.1f} {unit}"
    return f"{n:.1f} TB"
