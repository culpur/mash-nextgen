# Scaling Guide — Multi-Node Deployment Patterns

mash-nextgen supports 2, 3, 4, or more Swarm nodes. This guide explains how services distribute at each scale, and how to configure your inventory for optimal placement.

## Node Roles

Every node has one or more roles assigned via labels:

| Label | Purpose | Constraints |
|-------|---------|-------------|
| `role=manager` | Swarm manager, stateful services | PostgreSQL, Redis, primary data |
| `role=worker` | General compute | Bridges, bots, media processing |
| `role=matrix` | Matrix-specific services | Synapse workers, bridges |
| `role=media` | Media processing | Jitsi, LiveKit, Coturn, streaming |
| `role=web` | Web applications | WordPress, Nextcloud, CMS |
| `role=auth` | Authentication services | Authentik, Keycloak, LDAP |
| `role=monitoring` | Observability stack | Prometheus, Grafana, Wazuh |
| `role=storage` | Storage-heavy services | Registry, Immich, Paperless |

Nodes can have multiple roles. For example, a 2-node setup has `manager` and `worker`. A 4-node setup might have `manager`, `matrix`, `media+web`, and `monitoring+auth`.

---

## 2-Node Deployment (Minimum)

The simplest multi-host setup. One manager, one worker.

```
inventory/hosts:
  [swarm_managers]
  node1 ansible_host=10.0.70.6

  [swarm_workers]
  node2 ansible_host=10.0.70.7
```

### Service Distribution

```
+---------------------------+     +---------------------------+
|  Node 1 (Manager)         |     |  Node 2 (Worker)          |
|  Labels: role=manager     |     |  Labels: role=worker      |
|                           |     |                           |
|  PINNED (stateful):       |     |  DISTRIBUTED:             |
|    PostgreSQL             |     |    mautrix-discord         |
|    Valkey/Redis           |     |    mautrix-telegram        |
|    Synapse (main)         |     |    mautrix-whatsapp        |
|                           |     |    mautrix-signal          |
|  PREFERRED:               |     |    mautrix-slack           |
|    Synapse workers (7)    |     |    mautrix-facebook        |
|    Element + Element Call |     |    + 16 more bridges       |
|    WordPress + MariaDB    |     |                           |
|    Portainer              |     |    Jitsi (4 containers)   |
|                           |     |    LiveKit + Coturn        |
|  GLOBAL:                  |     |    Authentik + KeyDB       |
|    Traefik                |     |    SearXNG, Uptime Kuma    |
|    Wazuh Agent            |     |    maubot, ChatGPT bot    |
|                           |     |    Open WebUI             |
|                           |     |                           |
|                           |     |  GLOBAL:                  |
|                           |     |    Traefik                |
|                           |     |    Wazuh Agent            |
+---------------------------+     +---------------------------+
```

**Approximate load**: Node1 ~25 containers, Node2 ~35 containers

### Node vars

```yaml
# node1/vars.yml
swarm_node_labels:
  role: manager
  storage: ssd

# node2/vars.yml
swarm_node_labels:
  role: worker
  storage: ssd
```

---

## 3-Node Deployment (Recommended)

Separates Matrix services from web/auth services. Better fault isolation.

```
inventory/hosts:
  [swarm_managers]
  node1 ansible_host=10.0.70.6

  [swarm_workers]
  node2 ansible_host=10.0.70.7
  node3 ansible_host=10.0.70.8
```

### Service Distribution

```
+------------------------+   +------------------------+   +------------------------+
|  Node 1 (Manager)      |   |  Node 2 (Matrix)       |   |  Node 3 (Services)     |
|  role=manager           |   |  role=matrix            |   |  role=web,auth         |
|                        |   |                        |   |                        |
|  PINNED:               |   |  Matrix Stack:         |   |  Web Applications:     |
|    PostgreSQL          |   |    Synapse workers (14)|   |    WordPress + MariaDB |
|    Valkey/Redis        |   |    All bridges (22)    |   |    Nextcloud           |
|    Synapse (main)      |   |    All bots (10)       |   |    Forgejo/Gitea       |
|    Portainer           |   |    maubot              |   |    GoToSocial          |
|                        |   |    Dimension           |   |    PeerTube            |
|  Element + Call        |   |    ma1sd               |   |    Jellyfin            |
|  Etherpad              |   |    Registration        |   |    Immich              |
|  Synapse Admin         |   |    Sygnal              |   |                        |
|  Element Admin         |   |                        |   |  Auth + Monitoring:    |
|                        |   |  Media:                |   |    Authentik           |
|  GLOBAL:               |   |    Jitsi (4)           |   |    SearXNG             |
|    Traefik             |   |    LiveKit (2)         |   |    Uptime Kuma         |
|    Wazuh Agent         |   |    Coturn              |   |    Grafana             |
|                        |   |                        |   |    Prometheus          |
|                        |   |  GLOBAL:               |   |                        |
|                        |   |    Traefik             |   |  GLOBAL:               |
|                        |   |    Wazuh Agent         |   |    Traefik             |
|                        |   |                        |   |    Wazuh Agent         |
+------------------------+   +------------------------+   +------------------------+
```

**Approximate load**: Node1 ~15, Node2 ~50, Node3 ~20

### Node vars

```yaml
# node1/vars.yml
swarm_node_labels:
  role: manager
  storage: ssd

# node2/vars.yml
swarm_node_labels:
  role: matrix
  storage: ssd

# node3/vars.yml
swarm_node_labels:
  role: web
  secondary_role: auth
  storage: ssd
```

---

## 4-Node Deployment (Production)

Full separation of concerns. Each node has a dedicated purpose.

```
inventory/hosts:
  [swarm_managers]
  node1 ansible_host=10.0.70.6

  [swarm_workers]
  node2 ansible_host=10.0.70.7
  node3 ansible_host=10.0.70.8
  node4 ansible_host=10.0.70.9
```

### Service Distribution

```
+---------------------+  +---------------------+  +---------------------+  +---------------------+
| Node 1 (Core)       |  | Node 2 (Matrix)     |  | Node 3 (Web+Media)  |  | Node 4 (Ops)        |
| role=manager        |  | role=matrix         |  | role=web,media      |  | role=auth,monitoring |
|                     |  |                     |  |                     |  |                     |
| PINNED:             |  | Synapse workers:    |  | Web Apps:           |  | Authentication:     |
|   PostgreSQL        |  |   generic (2)       |  |   WordPress         |  |   Authentik         |
|   Valkey/Redis      |  |   media-repo        |  |   Nextcloud         |  |   Keycloak/LLDAP    |
|   Synapse (main)    |  |   federation-sender |  |   Forgejo           |  |   OAuth2-Proxy      |
|   Portainer         |  |   background        |  |   GoToSocial        |  |                     |
|                     |  |   user-dir          |  |   PeerTube          |  | Monitoring:         |
| Element + Call      |  |   appservice        |  |   Outline           |  |   Prometheus        |
| Synapse Admin       |  |   pusher            |  |   MediaWiki         |  |   Grafana           |
| Element Admin       |  |   stream-writers (6)|  |   Paperless         |  |   Uptime Kuma       |
| Etherpad            |  |                     |  |                     |  |   Healthchecks      |
|                     |  | Bridges (22):       |  | Media:              |  |   Loki + Promtail   |
|                     |  |   discord, telegram |  |   Jitsi (4)         |  |                     |
|                     |  |   whatsapp, signal  |  |   LiveKit (2)       |  | Search:             |
|                     |  |   slack, facebook   |  |   Coturn            |  |   SearXNG           |
|                     |  |   instagram, twitter|  |   Jellyfin          |  |   Meilisearch       |
|                     |  |   googlechat, skype |  |   Immich            |  |                     |
|                     |  |   bluesky, hookshot |  |   Navidrome         |  | Utilities:          |
|                     |  |   + more            |  |   Audiobookshelf    |  |   ntfy              |
|                     |  |                     |  |   Owncast           |  |   PrivateBin        |
|                     |  | Bots (10):          |  |                     |  |   Docker Registry   |
|                     |  |   draupnir, maubot  |  | File Management:    |  |   Registry Browser  |
|                     |  |   chatgpt, honoroit |  |   File Browser      |  |   Linkding          |
|                     |  |   buscarron, go-neb |  |                     |  |                     |
|                     |  |   + more            |  |                     |  |                     |
|                     |  |                     |  |                     |  |                     |
| GLOBAL: Traefik     |  | GLOBAL: Traefik     |  | GLOBAL: Traefik     |  | GLOBAL: Traefik     |
|         Wazuh Agent |  |         Wazuh Agent |  |         Wazuh Agent |  |         Wazuh Agent |
+---------------------+  +---------------------+  +---------------------+  +---------------------+
```

**Approximate load**: Node1 ~12, Node2 ~45, Node3 ~25, Node4 ~18

### Node vars

```yaml
# node1/vars.yml
swarm_node_labels:
  role: manager
  storage: ssd
  tier: core

# node2/vars.yml
swarm_node_labels:
  role: matrix
  storage: ssd
  tier: communication

# node3/vars.yml
swarm_node_labels:
  role: web
  secondary_role: media
  storage: ssd
  tier: content

# node4/vars.yml
swarm_node_labels:
  role: auth
  secondary_role: monitoring
  storage: ssd
  tier: operations
```

---

## 5+ Node Deployment (Enterprise)

At 5+ nodes, you can further split:

| Node | Role | Services |
|------|------|----------|
| Node 1 | `manager` | PostgreSQL, Valkey, Synapse main, Portainer |
| Node 2 | `matrix-workers` | Synapse workers (14), Dimension, ma1sd |
| Node 3 | `matrix-bridges` | All bridges (22), all bots (10), maubot |
| Node 4 | `media` | Jitsi, LiveKit, Coturn, Jellyfin, Immich, PeerTube |
| Node 5 | `web` | WordPress, Nextcloud, Forgejo, Outline, GoToSocial |
| Node 6 | `operations` | Authentik, Prometheus, Grafana, SearXNG, Registry |

At this scale, consider:
- **Multiple managers** (3 or 5) for Swarm quorum
- **Dedicated NFS/storage node** instead of manager hosting NFS
- **Dedicated database node** — PostgreSQL on its own host with local SSD
- **Separate Wazuh manager** — not on a Swarm node

---

## Placement Decision Tree

When deciding where a service goes:

```
Is it stateful (writes to disk)?
  ├─ YES: Does it need low-latency storage?
  │   ├─ YES → Pin to manager (PostgreSQL, Redis)
  │   └─ NO → Pin to storage node or use NFS
  └─ NO: Is it CPU/RAM heavy?
      ├─ YES: Is it Matrix-related?
      │   ├─ YES → matrix node (workers, bridges)
      │   └─ NO → media or web node (Jitsi, Jellyfin)
      └─ NO: Is it user-facing?
          ├─ YES → web node (Element, WordPress)
          └─ NO → operations node (monitoring, auth)
```

## Resource Recommendations

| Nodes | Min RAM/node | Min CPU/node | Min Disk/node | Use Case |
|-------|-------------|-------------|---------------|----------|
| 2 | 8 GB | 4 cores | 50 GB SSD | Personal/small team |
| 3 | 16 GB | 8 cores | 100 GB SSD | Small organization |
| 4 | 16 GB | 8 cores | 100 GB SSD | Medium organization |
| 5+ | 32 GB | 16 cores | 200 GB SSD | Enterprise |

Manager node should always have the most RAM (PostgreSQL, Synapse main).

## Custom Placement

Override any service's placement in your `vars.yml`:

```yaml
# Move a specific bridge to the manager node
swarm_service_overrides:
  matrix-mautrix-discord:
    constraints:
      - "node.labels.role == manager"
    replicas: 2

  # Run Jellyfin on a specific node with GPU
  jellyfin:
    constraints:
      - "node.hostname == gpu-node"
    resources:
      limits:
        memory: "4G"
```
