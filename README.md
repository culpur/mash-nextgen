# mash-nextgen

**Docker Swarm multi-host deployment for 250+ self-hosted services with integrated security monitoring, SSO, and automated threat response.**

Built on top of [MASH](https://github.com/mother-of-all-self-hosting/mash-playbook) (150+ services) and [matrix-docker-ansible-deploy](https://github.com/spantaleev/matrix-docker-ansible-deploy) (100+ Matrix services).

## The Problem

Both MASH and MDAD are single-host playbooks. They deploy all services to one Docker daemon on one server. This creates resource bottlenecks, no failover, and no way to distribute CPU/RAM-hungry services like Matrix bridges or Jitsi across multiple nodes.

## The Solution

mash-nextgen adds three layers on top of both upstream playbooks:

1. **Docker Swarm orchestration** — distribute services across multiple hosts with automatic placement
2. **Wazuh security monitoring** — dashboards, fail2ban, active-response, and log collection for every enabled service
3. **Authentik SSO** — single sign-on for 30+ services via OIDC or proxy authentication

All three layers are **service-aware** — they auto-configure based on which services you enable in your `vars.yml`. Enable a service, get monitoring + SSO + placement for free. Disable it, everything cleans up.

## Architecture

```
                        Docker Swarm Cluster
                              |
              +---------------+---------------+
              |                               |
    +---------+---------+           +---------+---------+
    |   Manager Node    |           |   Worker Node     |
    |                   |           |                   |
    | Synapse (main)    |           | Bridges (22)      |
    | PostgreSQL        |           | Jitsi (4)         |
    | Valkey/Redis      |           | LiveKit + Coturn   |
    | Element + Call    |           | Bots (10)         |
    | WordPress         |           | Authentik         |
    | Traefik (global)  |           | SearXNG           |
    | Wazuh Agent       |           | Uptime Kuma       |
    |                   |           | Traefik (global)  |
    +---+-------+---+---+           | Wazuh Agent       |
        |       |   |               +---+-------+---+---+
        |       |   |                   |       |   |
        +---+---+---+-------------------+---+---+---+
            |           |           |           |
     traefik-public  matrix-internal  database  monitoring
                  (Overlay Networks)
```

## Features

### Docker Swarm (5 roles)
- **swarm-init** — Cluster bootstrap, worker join, token management
- **swarm-networking** — 4 overlay networks (traefik-public, matrix-internal, database, monitoring)
- **swarm-placement** — Node labels + 11 service categories with placement constraints
- **swarm-traefik** — Traefik v3.6 in global Swarm mode with routing mesh
- **shared-storage** — NFS server/client for cross-node media and data access

### Swarm Service Wrapper
- **swarm-service-wrapper** — Converts docker-compose files from MDAD/MASH into Swarm-compatible stack files
  - Injects `deploy:` sections with placement constraints per service category
  - Removes `container_name:` (incompatible with Swarm)
  - Converts `restart:` policies to `deploy.restart_policy:`
  - 11 placement categories: core, workers, bridges, bots, media, web, auth, monitoring, database, cache, global
  - Per-service overrides for fine-grained control

### Wazuh Security Monitoring
- **60+ service detections** across the full MASH + MDAD catalog
- **14 production dashboards** with 74 visualizations:

  | Dashboard | Panels |
  |-----------|--------|
  | Security Overview | Alert severity, top IPs, auth failures, MITRE ATT&CK, active response |
  | Infrastructure Health | Disk/memory/CPU, service availability, backups, ZFS |
  | Docker Swarm | Container lifecycle, crash loops, health, node status |
  | Matrix Synapse | Login/federation/registration/media/workers/bridges |
  | Matrix Bridges | Per-bridge messages, errors, reconnections, status |
  | Authentik | SSO logins, failures, OIDC providers, token events |
  | WordPress | Login/xmlrpc/admin/REST API, attacking IPs, WPScan |
  | Jitsi | Conferences, participants, errors, JVB health |
  | OpenCTI | IOC ingestion, connectors, enrichment, sightings |
  | Docker Registry | Push/pull, auth failures, repositories, image sizes |
  | Traefik Access | HTTP status, RPS, URLs, response time, client IPs |
  | PostgreSQL | Connections, slow queries, replication, locks |
  | SEO/Marketing | Bot/human traffic, crawlers, referrers, geo, paths |
  | Compliance | Audit completeness, FIM, privilege escalation, CVEs |

- **5 fail2ban jails** — SSH, Synapse, Authentik, WordPress, Traefik (+ Nextcloud, Forgejo, Vaultwarden, Jellyfin when enabled)
- **Custom Wazuh decoders** for Synapse, Authentik, WordPress, Traefik, Docker Swarm
- **Custom Wazuh rules** with MITRE ATT&CK mapping
- **Active-response automation** — auto-block brute force IPs, auto-restart crash-looping containers

### Authentik SSO
- **30+ service configurations** via OIDC or Traefik proxy authentication
- **OIDC**: Synapse, Nextcloud, Forgejo, GoToSocial, PeerTube, Outline, Immich, Jellyfin, Portainer, OpenCTI, NetBox, Headscale, WordPress, Miniflux, Focalboard, pgAdmin
- **Proxy auth**: SearXNG, Uptime Kuma, Plausible, Paperless, FreshRSS, Matomo, Listmonk, FreeScout, LimeSurvey, AdGuard, Actual, Docker Registry
- **Group-to-role mappings**: admins, users, soc, devops, marketing
- Auto-creates providers + applications in Authentik via API

### Upstream Tracking
- Both MASH and MDAD tracked via **git subtree** — never modified directly
- `scripts/upstream-sync.sh` pulls latest changes from both upstreams
- GitHub Actions weekly check for upstream updates
- Wrapper roles extend upstream without modifying it

## Quick Start

```bash
# Clone
git clone https://github.com/culpur/mash-nextgen.git
cd mash-nextgen

# Configure
cp inventory/hosts.example inventory/hosts
# Edit inventory/hosts with your node IPs
# Edit inventory/host_vars/node1/vars.yml and node2/vars.yml

# Initialize Swarm cluster
ansible-playbook -i inventory/hosts playbooks/swarm-init.yml

# Check cluster status
ansible-playbook -i inventory/hosts playbooks/swarm-status.yml
```

## Project Structure

```
mash-nextgen/
  upstream/
    mash-playbook/                    # git subtree — 150+ services
    matrix-docker-ansible-deploy/     # git subtree — 100+ Matrix services
  roles/
    swarm-init/                       # Cluster bootstrap
    swarm-networking/                 # Overlay networks
    swarm-placement/                  # Node labels + constraints
    swarm-traefik/                    # Global Traefik
    shared-storage/                   # NFS server/client
    swarm-service-wrapper/            # Compose → Swarm stack converter
    wazuh-integration/                # Full security monitoring
      files/dashboards/               # 14 NDJSON dashboard definitions
      templates/fail2ban/             # Service-specific jails
      templates/wazuh-rules/          # Custom detection rules
      templates/wazuh-decoders/       # Log format decoders
      templates/active-response/      # Automated threat response
    authentik-sso/                    # SSO for all services
  playbooks/
    swarm-init.yml                    # Full cluster bootstrap
    swarm-status.yml                  # Health check
  inventory/
    hosts.example                     # 2-node example
    host_vars/                        # Per-node configuration
  scripts/
    upstream-sync.sh                  # Pull upstream changes
  docs/
    architecture.md                   # Design decisions + diagrams
    migration.md                      # Single-host to multi-host guide
    service-coverage.md               # Full Wazuh/SSO/fail2ban coverage matrix
    adding-a-service.md               # Guide for adding new service support
  .github/workflows/
    upstream-check.yml                # Weekly upstream diff detection
    lint.yml                          # Ansible lint + template validation
```

## Service Coverage

See [docs/service-coverage.md](docs/service-coverage.md) for the full matrix of Wazuh monitoring, fail2ban, active-response, and Authentik SSO coverage across all 250+ supported services.

## Sync Upstream

```bash
# Pull latest from both upstreams
./scripts/upstream-sync.sh both

# Or individually
./scripts/upstream-sync.sh mash
./scripts/upstream-sync.sh mdad
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add support for new services, write dashboards, and submit pull requests.

## Design Principles

1. **Never modify upstream** — wrapper roles extend, not patch
2. **Service-aware** — everything auto-configures from `vars.yml`
3. **Stateful services stay pinned** — PostgreSQL, Redis on manager node
4. **Stateless services float** — bridges, workers on any node
5. **Security by default** — monitoring + fail2ban for every enabled service
6. **Clean up after yourself** — disable a service, its dashboards/jails/SSO configs are removed

## License

[AGPL-3.0](LICENSE) (same as upstream MASH and MDAD)

## Credits

- [MASH Playbook](https://github.com/mother-of-all-self-hosting/mash-playbook) by the mother-of-all-self-hosting community
- [matrix-docker-ansible-deploy](https://github.com/spantaleev/matrix-docker-ansible-deploy) by Slavi Pantaleev
- [Wazuh](https://wazuh.com/) — open source security monitoring
- [Authentik](https://goauthentik.io/) — identity provider
- [Culpur Defense](https://culpur.net) — project maintainer
