# bismarck

Multi-site Docker Swarm over Tailscale. Run containers across servers in different locations with full overlay networking - no port forwarding required.

## Architecture

```
Manager Node (Site A)              Worker Node (Site B)
  Tailscale (100.x.x.1)  <------->  Tailscale (100.x.x.2)
  Docker Swarm Manager               Docker Swarm Worker
  ├── service-a ◄── overlay net ──► service-b
  └── service-c                      └── service-d
```

Tailscale creates an encrypted mesh VPN between all nodes using NAT traversal (DERP relay servers). Docker Swarm runs on top, advertising on Tailscale IPs so all swarm and overlay traffic flows through the tunnel.

**Key constraint solved:** the remote node only needs outbound internet access. No ports need to be opened or forwarded.

## Prerequisites

- Docker installed on all nodes
- A [Tailscale](https://tailscale.com) account (free for personal use)
- SSH access to all nodes

## Setup

### 1. Install Tailscale on every node

Tailscale must be installed **natively** (not in a container) so the `tailscale0` TUN interface is available to Docker.

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey=tskey-auth-XXXXXXXXXXXX
```

Verify:
```bash
tailscale status        # shows all your nodes
tailscale ip -4         # shows this node's Tailscale IP
ip addr show tailscale0 # confirms the TUN interface exists
```

For TrueNAS SCALE: use the built-in Tailscale app from the Apps catalog.

### 2. Tailscale ACLs

Ensure your Tailscale ACL policy allows all traffic between your nodes. In the [Tailscale admin console](https://login.tailscale.com/admin/acls):

```json
{
  "acls": [
    { "action": "accept", "src": ["*"], "dst": ["*:*"] }
  ]
}
```

If TrueNAS is using Tailscale's built-in netfilter, you may need to disable it:
```bash
tailscale set --netfilter-mode=off
```

### 3. Initialize the Swarm (manager node)

On the node you want as the manager:

```bash
./swarm/init-manager.sh
```

This auto-detects the Tailscale IP and initializes the swarm. It outputs a join command.

### 4. Join worker nodes

On each worker node, run the join command from step 3, or use the helper:

```bash
./swarm/join-worker.sh <manager-tailscale-ip> <join-token>
```

For fresh Ubuntu servers, the bootstrap script handles everything:

```bash
./swarm/setup-worker.sh <tailscale-auth-key> <manager-tailscale-ip> <swarm-join-token>
```

### 5. Verify

From the manager:
```bash
docker node ls
```

Both nodes should show `Ready` / `Active`.

## Deploying Stacks

Deploy from the manager node:

```bash
docker stack deploy -c stacks/example-stack.yml myapp
```

Services on the overlay network can reach each other by service name regardless of which physical node they run on.

### Remote deploy from your workstation

With Tailscale on your workstation, you can deploy directly:

```bash
docker -H ssh://user@<manager-tailscale-ip> stack deploy -c stacks/example-stack.yml myapp
```

## Project Structure

```
bismarck/
├── README.md
├── swarm/
│   ├── init-manager.sh      # Initialize swarm on manager node
│   ├── join-worker.sh       # Join an existing swarm as worker
│   └── setup-worker.sh      # Bootstrap a fresh Ubuntu server
└── stacks/
    └── example-stack.yml    # Example multi-host stack
```

## Adding a New Stack

Create a compose file in `stacks/` using the overlay network driver:

```yaml
version: "3.8"

services:
  my-service:
    image: my-image:latest
    networks:
      - app-net
    deploy:
      replicas: 2

networks:
  app-net:
    driver: overlay
```

Use `deploy.placement.constraints` to pin services to specific nodes:

```yaml
deploy:
  placement:
    constraints:
      - node.role == manager     # run on manager only
      - node.role == worker      # run on workers only
      - node.hostname == octavia # run on a specific node
```

## Troubleshooting

| Problem | Fix |
|---|---|
| `tailscale0` doesn't exist | Install Tailscale natively, not in a container |
| Swarm join times out | Check `iptables-legacy -L ts-input -n` for DROP rules. Disable netfilter: `tailscale set --netfilter-mode=off` |
| Overlay network unreachable | Ensure ports 2377, 7946, 4789 are reachable between Tailscale IPs. Check `tailscale ping <other-ip>` works first |
| Node shows `Down` | Check Tailscale is running: `tailscale status`. Restart if needed: `sudo systemctl restart tailscaled` |
