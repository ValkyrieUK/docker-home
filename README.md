# bismarck

Multi-site Docker Swarm over Tailscale. Run containers across servers in different locations with full overlay networking - no port forwarding required.

## Architecture

```
iMac (100.104.90.34)
  └── deploy via: docker -H ssh://root@100.75.214.41

TrueNAS (100.75.214.41)             Ubuntu @ Dad's (100.99.166.30)
  Swarm Manager                       Swarm Worker
  ├── postgres                        ├── correlator-worker
  ├── redis            ◄── overlay ──►├── anomaly-worker
  └── app (port 3000)                 └── ...
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

## Deploying WorldView

### 1. Build and push the images

In the WorldView repo, build and push to GitHub Container Registry:

```bash
# Login to GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u ValkyrieUK --password-stdin

# Build and push the app image
docker build -f docker/Dockerfile.app -t ghcr.io/valkyrie-uk/worldview-app:latest .
docker push ghcr.io/valkyrie-uk/worldview-app:latest

# Build and push the postgres image
docker build -f docker/Dockerfile.postgres -t ghcr.io/valkyrie-uk/worldview-postgres:latest .
docker push ghcr.io/valkyrie-uk/worldview-postgres:latest
```

### 2. Create the secret

On the swarm manager (TrueNAS):

```bash
echo "your-db-password" | docker secret create pg_password -
```

### 3. Deploy the stack

From TrueNAS:
```bash
docker stack deploy -c stacks/worldview.yml worldview
```

Or remotely from your iMac via Tailscale:
```bash
docker -H ssh://root@100.75.214.41 stack deploy -c stacks/worldview.yml worldview
```

### 4. Check status

```bash
docker stack ps worldview
docker service ls
```

### 5. Scale workers

```bash
docker service scale worldview_correlator-worker=4
docker service scale worldview_anomaly-worker=2
```

### Service placement

| Service | Node | Why |
|---------|------|-----|
| postgres | TrueNAS (manager) | Needs fast local storage for persistent volumes |
| redis | TrueNAS (manager) | Co-located with postgres for low-latency pub/sub |
| app | TrueNAS (manager) | Close to database, serves the WebSocket API |
| correlator-worker | Any node | CPU-bound, stateless - spread across nodes |
| anomaly-worker | Any node | CPU-bound, stateless - spread across nodes |

Workers are the ideal candidates for running on the Ubuntu server at dad's since they're stateless and only need network access to postgres and redis over the overlay.

## Deploying Other Stacks

Services on the overlay network can reach each other by service name regardless of which physical node they run on.

### Remote deploy from your workstation

With Tailscale on your iMac, deploy directly:

```bash
docker -H ssh://root@100.75.214.41 stack deploy -c stacks/my-stack.yml myapp
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
    └── worldview.yml        # WorldView multi-site stack
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
