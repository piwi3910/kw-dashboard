"""Qt/QML entry point. --windowed skips eglfs so layout work never requires
the physical panel; --config picks the same config file the pygame path used.
"""
from __future__ import annotations
import argparse
import os
import sys

from PyQt5.QtCore import QUrl
from PyQt5.QtGui import QGuiApplication
from PyQt5.QtQml import QQmlApplicationEngine

from ..config import load_config
from ..collector import Collector
from ..nav import Nav
from ..sources.prometheus import PrometheusClient
from ..sources.kube import KubeClient
from ..sources.alerts import AlertsClient
from .bridge import Bridge

QML_MAIN = os.path.join(os.path.dirname(__file__), "..", "qml", "Main.qml")


def read_token(path: str) -> str:
    try:
        return open(path).read().strip()
    except OSError:
        return ""


def _set_eglfs_env():
    os.environ.setdefault("QT_QPA_PLATFORM", "eglfs")
    os.environ.setdefault("QT_QPA_EGLFS_INTEGRATION", "eglfs_kms")
    os.environ.setdefault("QT_QPA_EGLFS_HIDECURSOR", "1")


def main():
    ap = argparse.ArgumentParser(prog="kw-dashboard-qt")
    ap.add_argument("--config", default="/etc/kw-dashboard/config.toml")
    ap.add_argument("--windowed", action="store_true",
                    help="run in a desktop window instead of KMSDRM/eglfs")
    args = ap.parse_args()

    cfg = load_config(args.config)

    if not args.windowed:
        _set_eglfs_env()

    token = read_token(cfg.token_path)
    ca = cfg.ca_path if os.path.exists(cfg.ca_path) else None
    collector = Collector(
        cfg,
        PrometheusClient(cfg.prometheus_url, cfg.http_timeout_seconds),
        KubeClient(cfg.kube_url, token, ca, cfg.http_timeout_seconds),
        AlertsClient(cfg.alertmanager_url, cfg.http_timeout_seconds))
    nav = Nav(cfg.rotate_seconds, cfg.touch_pause_seconds, cfg.idle_reset_seconds)

    collector.start()
    try:
        app = QGuiApplication(sys.argv)
        engine = QQmlApplicationEngine()
        bridge = Bridge(cfg, collector, nav)
        engine.rootContext().setContextProperty("bridge", bridge)
        engine.load(QUrl.fromLocalFile(os.path.abspath(QML_MAIN)))
        if not engine.rootObjects():
            print("failed to load QML", file=sys.stderr)
            return 1
        return app.exec_()
    finally:
        collector.stop()


if __name__ == "__main__":
    sys.exit(main())
