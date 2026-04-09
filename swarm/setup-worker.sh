#!/bin/bash
set -euo pipefail

# Bootstrap a fresh Ubuntu server as a Swarm worker node.
# Installs Docker and Tailscale, then joins the swarm.
#
# Usage: ./setup-worker.sh <tailscale-auth-key> <manager-tailscale-ip> <swarm-join-token>

TS_AUTHKEY="${1:-}"
MANAGER_IP="${2:-}"
JOIN_TOKEN="${3:-}"

if [ -z "$TS_AUTHKEY" ] || [ -z "$MANAGER_IP" ] || [ -z "$JOIN_TOKEN" ]; then
  echo "Usage: ./setup-worker.sh <tailscale-auth-key> <manager-tailscale-ip> <swarm-join-token>"
  exit 1
fi

echo "==> Installing Docker..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
else
  echo "    Docker already installed."
fi

echo "==> Installing Tailscale..."
if ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
else
  echo "    Tailscale already installed."
fi

echo "==> Connecting to Tailscale..."
sudo tailscale up --authkey="$TS_AUTHKEY"

echo "==> Waiting for Tailscale IP..."
sleep 3
TAILSCALE_IP=$(tailscale ip -4)
echo "    Got Tailscale IP: $TAILSCALE_IP"

echo "==> Joining Docker Swarm..."
sudo docker swarm join --token "$JOIN_TOKEN" "$MANAGER_IP:2377"

echo ""
echo "=========================================="
echo "Worker node setup complete."
echo "Tailscale IP: $TAILSCALE_IP"
echo "Verify on manager: docker node ls"
echo "=========================================="
