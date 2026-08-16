"""Entry point. --windowed and --screenshot exist so layout work never
requires the physical panel."""
from __future__ import annotations
import argparse, os, sys
from .config import load_config
from .collector import Collector
from .sources.prometheus import PrometheusClient
from .sources.kube import KubeClient
from .sources.alerts import AlertsClient


def read_token(path: str) -> str:
    try:
        return open(path).read().strip()
    except OSError:
        return ""


def main():
    ap = argparse.ArgumentParser(prog="kw-dashboard")
    ap.add_argument("--config", default="/etc/kw-dashboard/config.toml")
    ap.add_argument("--windowed", action="store_true",
                    help="run in a desktop window instead of KMSDRM")
    ap.add_argument("--screenshot", metavar="DIR",
                    help="render each page from fake data to PNGs and exit")
    args = ap.parse_args()

    cfg = load_config(args.config)

    if args.screenshot:
        from .fake import render_all_pages
        os.makedirs(args.screenshot, exist_ok=True)
        render_all_pages(cfg, args.screenshot)
        print(f"wrote screenshots to {args.screenshot}")
        return 0

    token = read_token(cfg.token_path)
    ca = cfg.ca_path if os.path.exists(cfg.ca_path) else None
    collector = Collector(
        cfg,
        PrometheusClient(cfg.prometheus_url, cfg.http_timeout_seconds),
        KubeClient(cfg.kube_url, token, ca, cfg.http_timeout_seconds),
        AlertsClient(cfg.alertmanager_url, cfg.http_timeout_seconds))
    collector.start()
    try:
        from .app import App
        App(cfg, collector, windowed=args.windowed).run()
    finally:
        collector.stop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
