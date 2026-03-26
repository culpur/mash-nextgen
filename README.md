# mash-nextgen

Docker Swarm multi-host deployment for self-hosted services, built on top of [MASH](https://github.com/mother-of-all-self-hosting/mash-playbook) and [matrix-docker-ansible-deploy](https://github.com/spantaleev/matrix-docker-ansible-deploy).

## What This Is

Neither MASH nor MDAD support deploying services across multiple Docker hosts. This project adds that capability through Docker Swarm orchestration, while tracking upstream changes from both projects.

## Features

- **Multi-host Docker Swarm** deployment via Ansible
- **Service placement constraints** — pin stateful services (PostgreSQL, Synapse) to specific nodes
- **Overlay networking** for cross-node container communication
- **Shared storage** (NFS) for media and data that needs cross-node access
- **Traefik in Swarm mode** with global deployment and routing mesh
- **Upstream tracking** via git subtree for both MASH and MDAD

## Architecture

```
                    Docker Swarm Cluster

  +-----------------+     +-----------------+
  |   Manager Node  |     |   Worker Node   |
  |                 |     |                 |
  | Synapse (main)  |     | Bridges (11)    |
  | Synapse workers |     | Jitsi stack     |
  | PostgreSQL      |     | Authentik       |
  | Element         |     | Bots            |
  | WordPress       |     | SearXNG         |
  | Traefik (global)|     | Traefik (global)|
  +-----------------+     +-----------------+
          |                       |
          +-------Overlay---------+
                  Network
```

## Quick Start

1. Clone this repo
2. Copy `inventory/hosts.example` to `inventory/hosts`
3. Configure `inventory/host_vars/` for your nodes
4. Run:

```bash
# Initialize Swarm cluster
ansible-playbook -i inventory/hosts playbooks/swarm-init.yml

# Deploy services
ansible-playbook -i inventory/hosts playbooks/deploy.yml
```

## Upstream Tracking

This project tracks upstream via git subtree:

```bash
# Pull latest MASH changes
git subtree pull --prefix=upstream/mash-playbook https://github.com/mother-of-all-self-hosting/mash-playbook.git main --squash

# Pull latest MDAD changes
git subtree pull --prefix=upstream/matrix-docker-ansible-deploy https://github.com/spantaleev/matrix-docker-ansible-deploy.git master --squash
```

## Project Structure

```
mash-nextgen/
  upstream/
    mash-playbook/              # git subtree — upstream MASH
    matrix-docker-ansible-deploy/  # git subtree — upstream MDAD
  roles/
    swarm-init/                 # Initialize Swarm, join workers
    swarm-networking/           # Create overlay networks
    swarm-placement/            # Node labels + placement constraints
    swarm-traefik/              # Traefik in Swarm mode
    shared-storage/             # NFS for cross-node data
  inventory/
    hosts.example               # Example inventory
    host_vars/                  # Per-node configuration
  playbooks/
    swarm-init.yml              # Cluster bootstrap
    deploy.yml                  # Full service deployment
  scripts/
    upstream-sync.sh            # Pull upstream changes
  docs/
    architecture.md             # Design decisions
    migration.md                # Migrating from single-host MASH/MDAD
```

## License

AGPL-3.0 (same as upstream MASH and MDAD)
