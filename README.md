# kw-dashboard <!-- usp: Native touch-panel dashboard for Kubernetes, no browser -->

A native, always-on dashboard rendered directly to an HDMI touch panel — no
browser, no Grafana UI, no X11, no Wayland. A glanceable view of a Kubernetes
cluster's health, alive with real-time metrics and logs, pre-empted by alerts.

<!-- badges -->

[![tests](https://github.com/piwi3910/kw-dashboard/actions/workflows/ci.yml/badge.svg)](https://github.com/piwi3910/kw-dashboard/actions/workflows/ci.yml)
[![lint](https://github.com/piwi3910/kw-dashboard/actions/workflows/ci.yml/badge.svg?label=lint)](https://github.com/piwi3910/kw-dashboard/actions/workflows/ci.yml)
[![CI](https://github.com/piwi3910/kw-dashboard/actions/workflows/ci.yml/badge.svg)](https://github.com/piwi3910/kw-dashboard/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

<!-- quick start -->

## Quick start

### On the panel node

```bash
# 1. Install dependencies
sudo apt-get install python3-pygame fonts-dejavu-core python3-pyqt5.qml

# 2. Apply RBAC
kubectl apply -f deploy/rbac.yaml

# 3. Install and start
./deploy/install.sh
```

The dashboard starts on its own VT and auto-rotates between pages every 15 seconds.
Touch pauses rotation and drills into workload details.

### Desktop debugging

```bash
python3 -m kw_dashboard.qt.main --windowed --config /dev/null
```

Runs in a window with synthetic data so layout work never requires the physical panel.

## What it does

- **Cluster overview** — CPU, memory gauges; pod count; node health bars.
- **Pulse** — network throughput, event feed, sparkline history.
- **Explore** — namespace list, pod detail, container logs.
- **Alerts** — automatic screen takeover on critical alerts.

All data from Prometheus, Alertmanager, and the k3s API. Everything is generic,
discoverable at runtime — no per-app configuration.

## Key design decisions

- **Systemd unit, not a pod** — the dashboard must survive a broken cluster.
- **PyQt/QML over pygame** — better touch handling, no antialiasing limits.
- **k8s API for logs, not Loki** — works for every namespace, always.
- **Read-only** — service account has `view` ClusterRole only.
