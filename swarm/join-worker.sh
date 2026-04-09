#!/bin/bash
set -euo pipefail

# Join this node to an existing Docker Swarm as a worker.
# Uses the manager's Tailscale IP so traffic routes over the tunnel.

usage() {
  echo "Usage: ./join-worker.sh <manager-tailscale-ip> <join-token>"
  echo ""
  echo "Get these values by running on the manager node:"
  echo "  docker swarm join-token worker"
  exit 1
}

MANAGER_IP="${1:-}"
JOIN_TOKEN="${2:-}"

[ -z "$MANAGER_IP" ] && usage
[ -z "$JOIN_TOKEN" ] && usage

echo "Joining swarm via manager Tailscale IP: $MANAGER_IP"
docker swarm join --token "$JOIN_TOKEN" "$MANAGER_IP:2377"
