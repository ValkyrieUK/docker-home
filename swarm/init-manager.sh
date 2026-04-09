#!/bin/bash
set -euo pipefail

# Initialize this node as a Docker Swarm manager.
# Advertises on the Tailscale IP so all swarm traffic
# routes over the encrypted Tailscale tunnel.

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null) || {
  echo "ERROR: Could not get Tailscale IP. Is Tailscale running?"
  exit 1
}

echo "Initializing Docker Swarm on Tailscale IP: $TAILSCALE_IP"
docker swarm init --advertise-addr "$TAILSCALE_IP"

echo ""
echo "=========================================="
echo "Swarm initialized. To add worker nodes:"
echo "  docker swarm join-token worker"
echo "Copy the output and run it on each worker."
echo "=========================================="
