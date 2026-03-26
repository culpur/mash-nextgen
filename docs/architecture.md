# mash-nextgen Architecture

## Problem Statement

Both [MASH](https://github.com/mother-of-all-self-hosting/mash-playbook) and [matrix-docker-ansible-deploy](https://github.com/spantaleev/matrix-docker-ansible-deploy) are single-host playbooks. They deploy all services to one Docker daemon on one server. This creates:

- **Resource bottlenecks** — a Matrix homeserver with 50+ containers overloads a single host
- **No failover** — if the host goes down, all services go down
- **Scaling limits** — can't distribute CPU/RAM-hungry services across nodes

## Solution

mash-nextgen adds a Docker Swarm orchestration layer on top of both upstream playbooks:

```
mash-nextgen
    |
    +-- swarm-init          (cluster bootstrap)
    +-- swarm-networking    (overlay networks)
    +-- swarm-placement     (node labels + constraints)
    +-- swarm-traefik       (global Traefik in Swarm mode)
    +-- shared-storage      (NFS for cross-node data)
    |
    +-- upstream/mash-playbook              (git subtree)
    +-- upstream/matrix-docker-ansible-deploy (git subtree)
```

## Design Principles

### 1. Don't modify upstream roles directly

Upstream roles are tracked via `git subtree`. We never edit files under `upstream/`. Instead, we:

- **Wrap** upstream roles with our Swarm-aware roles
- **Override** variables to inject placement constraints
- **Extend** docker-compose output with `deploy:` sections via Jinja2 post-processing

### 2. Stateful services stay pinned

PostgreSQL, Redis/Valkey, and other stateful services are pinned to the manager node via placement constraints. They use local volumes, not NFS, for performance.

### 3. Stateless services float

Bridges, workers, bots, and web frontends can run on any node. The Swarm scheduler places them based on resource availability.

### 4. Traefik runs globally

Traefik runs as a global service (one per node). Any node can receive traffic and route it to the correct container via the Swarm routing mesh.

### 5. Shared storage for media only

NFS is used only for data that MUST be accessible from any node (Matrix media store, file uploads). Database storage is local to the pinned node.

## Network Architecture

```
                External Traffic
                      |
            [Reverse Proxy / LB]
                      |
         +------------+------------+
         |                         |
    [Manager:80,443]          [Worker:80,443]
         |                         |
    Traefik (global)          Traefik (global)
         |                         |
    +----+----+              +----+----+
    |         |              |         |
  Synapse  Element        Bridges    Jitsi
  Postgres WordPress     Authentik  SearXNG
  Valkey   Portainer      Bots      Kuma
    |         |              |         |
    +---------+--------------+---------+
              |
        Overlay Networks
        (matrix-internal, database,
         traefik-public, monitoring)
```

## Overlay Networks

| Network | Purpose | Internal? |
|---------|---------|-----------|
| `traefik-public` | Public-facing services routed by Traefik | No |
| `matrix-internal` | Synapse ↔ workers ↔ bridges communication | No |
| `database` | PostgreSQL/Valkey connections | Yes (no external) |
| `monitoring` | Metrics and health checks | No |

## Service Placement

| Service | Node | Reason |
|---------|------|--------|
| PostgreSQL | Manager (pinned) | Stateful, local volume |
| Valkey/Redis | Manager (pinned) | Stateful, low latency |
| Synapse (main) | Manager (pinned) | Needs DB locality |
| Synapse workers | Any (spread) | Stateless, CPU-heavy |
| Element | Any | Stateless web app |
| Bridges (11) | Worker (preferred) | Stateless, memory-heavy |
| Jitsi | Worker (preferred) | CPU-heavy, independent |
| Authentik | Worker | Independent auth service |
| Traefik | Global | Must run on every node |

## Upstream Tracking

```bash
# Pull latest changes
./scripts/upstream-sync.sh both

# Check for conflicts with our roles
git diff HEAD~1 -- upstream/
```

When upstream changes conflict with our wrapper roles, we resolve manually and document the conflict in the commit message.
