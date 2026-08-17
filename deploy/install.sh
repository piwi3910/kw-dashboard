#!/usr/bin/env bash
# deploy/install.sh — deploy kw-dashboard to km01.
#
# Idempotent: safe to re-run. Assumes SSH access to the node already works
# and that a kubeconfig with cluster-admin-ish rights is available locally
# for `kubectl apply`/`get secret` (RBAC applied here is read-only: the
# built-in `view` ClusterRole plus a minimal extra ClusterRole for
# cluster-scoped nodes/namespaces reads — see deploy/rbac.yaml; that scope
# is only for the dashboard's own token).
set -euo pipefail

NODE="${NODE:-192.168.10.101}"
SSH_USER="${SSH_USER:-piwi}"

echo "==> installing apt dependencies"
ssh "$SSH_USER@$NODE" 'sudo apt-get update -qq && sudo apt-get install -y python3-pyqt5 python3-pyqt5.qtquick qml-module-qtquick2 qml-module-qtquick-controls2 qml-module-qtquick-layouts qml-module-qtquick-shapes qml-module-qtgraphicaleffects qml-module-qtquick-window2 fonts-ibm-plex libegl1 libgles2 libgbm1 libgl1-mesa-dri'

echo "==> applying RBAC"
kubectl apply -f deploy/rbac.yaml

echo "==> extracting service account token and CA"
TOKEN=$(kubectl -n monitoring get secret kw-dashboard-token -o jsonpath='{.data.token}' | base64 -d)
CA=$(kubectl -n monitoring get secret kw-dashboard-token -o jsonpath='{.data.ca\.crt}' | base64 -d)

echo "==> copying application"
ssh "$SSH_USER@$NODE" 'sudo mkdir -p /opt/kw-dashboard /etc/kw-dashboard && sudo chown -R '"$SSH_USER"' /opt/kw-dashboard'
rsync -a --delete kw_dashboard "$SSH_USER@$NODE:/opt/kw-dashboard/"

# Token is secret: piped via stdin so it never lands in ps output, argv, or a
# heredoc embedded in the remote command line. 0400, owned by piwi.
echo "==> installing token (0400, owned by $SSH_USER)"
printf '%s' "$TOKEN" | ssh "$SSH_USER@$NODE" "sudo tee /etc/kw-dashboard/token >/dev/null && sudo chown $SSH_USER /etc/kw-dashboard/token && sudo chmod 400 /etc/kw-dashboard/token"

# CA is public (it only lets the client verify the server, it authenticates
# nothing on its own) so 0444 is fine. This is NOT the node's k3s server CA
# (/var/lib/rancher/k3s/server/tls/server-ca.crt, root-only) and NOT
# /etc/rancher/k3s/cluster-ca.crt (world-readable but fails verification
# against https://127.0.0.1:6443) — it is the ServiceAccount's own CA, the
# one verified to work. See docs/hardware-findings.md and config.py ca_path.
echo "==> installing CA certificate (0444, owned by $SSH_USER)"
printf '%s' "$CA" | ssh "$SSH_USER@$NODE" "sudo tee /etc/kw-dashboard/ca.crt >/dev/null && sudo chown $SSH_USER /etc/kw-dashboard/ca.crt && sudo chmod 444 /etc/kw-dashboard/ca.crt"

echo "==> installing config"
ssh "$SSH_USER@$NODE" 'sudo tee /etc/kw-dashboard/config.toml >/dev/null <<EOF
# Touch scaling is handled by libinput under Qt eglfs — no config needed here.
EOF'

echo "==> installing systemd unit"
scp deploy/kw-dashboard.service "$SSH_USER@$NODE:/tmp/"
ssh "$SSH_USER@$NODE" 'sudo mv /tmp/kw-dashboard.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now kw-dashboard'

echo "==> restarting to pick up any config/unit changes on re-run"
ssh "$SSH_USER@$NODE" 'sudo systemctl restart kw-dashboard'

echo "==> status"
ssh "$SSH_USER@$NODE" 'sudo systemctl --no-pager status kw-dashboard | head -20'
