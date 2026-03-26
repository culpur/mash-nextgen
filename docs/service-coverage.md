# mash-nextgen Service Coverage

This document tracks Wazuh monitoring, Authentik SSO, and fail2ban coverage across all MASH + MDAD services.

## Coverage Matrix

### Legend
- W = Wazuh dashboard + decoder + rules
- F = Fail2ban jail
- A = Active-response
- S = Authentik SSO (OIDC or proxy auth)
- `-` = Not applicable / not needed

### MDAD Services (Matrix)

| Service | W | F | A | S | Notes |
|---------|---|---|---|---|-------|
| **Synapse** | W | F | A | S | Core homeserver — full monitoring |
| **Synapse Workers** | W | - | - | - | Performance metrics via Synapse dashboard |
| **Synapse Admin** | W | - | - | S | Admin panel access tracking |
| **Element Web** | W | - | - | - | Uses Synapse auth (SSO via Synapse OIDC) |
| **Element Call** | W | - | - | - | WebRTC metrics |
| **Element Admin** | W | - | - | S | Admin access audit |
| **Cinny** | - | - | - | - | Client — uses Synapse auth |
| **Hydrogen** | - | - | - | - | Client — uses Synapse auth |
| **SchildiChat** | - | - | - | - | Client — uses Synapse auth |
| **Jitsi** | W | - | - | - | Conference metrics, no auth bypass risk |
| **LiveKit** | W | - | - | - | WebRTC metrics |
| **Coturn** | W | - | A | - | TURN abuse detection |
| **PostgreSQL** | W | - | - | - | Query performance, connection monitoring |
| **Traefik** | W | F | A | S | Access logs, path scanning, rate limiting |
| **Etherpad** | W | - | - | S | Collaborative editing audit |
| **Dimension** | W | - | - | - | Integration manager |
| **ma1sd** | W | F | - | - | Identity server auth failures |
| **maubot** | W | - | - | - | Bot activity monitoring |
| **Matrix Registration** | W | F | A | - | Registration abuse prevention |
| **Postmoogle** | W | - | - | - | Email bridge monitoring |
| **Sygnal** | W | - | - | - | Push notification delivery |
| **Bridges (all)** | W | - | - | - | Per-bridge health + message metrics |
| - mautrix-discord | W | - | - | - | |
| - mautrix-telegram | W | - | - | - | |
| - mautrix-whatsapp | W | - | - | - | |
| - mautrix-signal | W | - | - | - | |
| - mautrix-slack | W | - | - | - | |
| - mautrix-facebook | W | - | - | - | |
| - mautrix-instagram | W | - | - | - | |
| - mautrix-googlechat | W | - | - | - | |
| - mautrix-twitter | W | - | - | - | |
| - mautrix-bluesky | W | - | - | - | |
| - hookshot | W | - | - | - | Webhook bridge |
| - heisenbridge | W | - | - | - | IRC bridge |
| - appservice-irc | W | - | - | - | |
| - go-skype-bridge | W | - | - | - | |
| **Bots** | W | - | - | - | Activity monitoring |
| - draupnir | W | - | - | - | Moderation bot |
| - mjolnir | W | - | - | - | Moderation bot |
| - chatgpt | W | - | - | - | AI bot |
| - buscarron | W | - | - | - | Form bot |
| - honoroit | W | - | - | - | Support bot |
| - go-neb | W | - | - | - | Integration bot |
| **Conduit/Dendrite** | W | F | A | S | Alternative homeservers |
| **Rageshake** | W | - | - | - | Bug report collection |
| **Prometheus + Grafana** | W | - | - | S | Self-monitoring |

### MASH Services

| Service | W | F | A | S | Notes |
|---------|---|---|---|---|-------|
| **Authentik** | W | F | A | - | IS the SSO provider |
| **Authelia** | W | F | A | - | Alternative auth provider |
| **Keycloak** | W | F | A | - | Alternative auth provider |
| **LLDAP** | W | F | - | - | LDAP auth failures |
| **OAuth2-Proxy** | W | F | - | - | Proxy auth failures |
| **WordPress** | W | F | A | S | Full web app monitoring |
| **Nextcloud** | W | F | A | S | Cloud platform — full monitoring |
| **Forgejo/Gitea** | W | F | A | S | Git hosting — auth + push/pull audit |
| **GoToSocial** | W | F | - | S | Fediverse — auth + federation |
| **PeerTube** | W | F | - | S | Video hosting — auth + upload monitoring |
| **Immich** | W | - | - | S | Photo management — upload monitoring |
| **Jellyfin** | W | F | - | S | Media server — auth + streaming |
| **Navidrome** | W | F | - | S | Music server — auth |
| **Grafana** | W | - | - | S | Dashboards |
| **Prometheus** | W | - | - | - | Metrics (no user auth) |
| **AdGuard Home** | W | - | - | S | DNS query monitoring |
| **Headscale** | W | - | - | S | VPN control plane |
| **SearXNG** | W | - | - | S | Search — proxy auth |
| **Uptime Kuma** | W | - | - | S | Monitoring — proxy auth |
| **Miniflux/FreshRSS** | W | - | - | S | Feed readers |
| **Paperless-ngx** | W | - | - | S | Document management |
| **Outline** | W | - | - | S | Knowledge base |
| **CryptPad** | W | - | - | - | E2EE — no SSO possible |
| **Vaultwarden** | W | F | A | - | Password manager — critical |
| **NetBox** | W | - | - | S | DCIM/IPAM |
| **Docker Registry** | W | F | - | S | Push/pull audit |
| **PrivateBin** | W | - | - | - | Zero-knowledge paste |
| **Plausible** | W | - | - | S | Web analytics |
| **Matomo** | W | - | - | S | Web analytics |
| **Listmonk** | W | - | - | S | Email marketing |
| **FreeScout** | W | - | - | S | Help desk |
| **LimeSurvey** | W | - | - | S | Surveys |
| **Focalboard** | W | - | - | S | Project management |
| **Actual** | W | - | - | S | Finance |
| **BorgBackup** | W | - | - | - | Backup monitoring |
| **ntfy** | W | - | - | - | Notification delivery |
| **Mosquitto** | W | - | - | - | MQTT broker |
| **All others** | W | - | - | - | Basic container health monitoring |

### Dashboard Categories (14 total)

| Dashboard | Covers | Type |
|-----------|--------|------|
| `security-overview` | All auth failures, bans, threats across all services | Security |
| `infrastructure-health` | Host CPU/RAM/disk, ZFS, NFS, backup status | Admin |
| `docker-swarm` | Container health, restarts, placement, resource usage | Admin |
| `matrix-synapse` | Federation, rooms, users, workers, media, bridges | Application |
| `matrix-bridges` | Per-bridge status, message throughput, errors | Application |
| `authentik` | SSO flows, provider health, user provisioning | Application |
| `wordpress` | Login attempts, REST API, plugin activity, comments | Application |
| `jitsi` | Conferences, participants, quality metrics | Application |
| `opencti` | IOC ingestion, connectors, enrichment pipeline | Application |
| `docker-registry` | Push/pull activity, image sizes, auth failures | Application |
| `traefik-access` | HTTP status distribution, top URLs, response times | Web/SEO |
| `postgresql` | Query performance, connections, replication | Database |
| `seo-marketing` | Bot identification, geographic distribution, referrers | Marketing |
| `compliance` | Audit completeness, FIM, password policy, retention | Compliance |

### Future Dashboards (when services added)

| Dashboard | Trigger |
|-----------|---------|
| `nextcloud` | `nextcloud_enabled: true` |
| `forgejo` | `forgejo_enabled: true` |
| `jellyfin` | `jellyfin_enabled: true` |
| `peertube` | `peertube_enabled: true` |
| `immich` | `immich_enabled: true` |
| `gotosocial` | `gotosocial_enabled: true` |
| `headscale` | `headscale_enabled: true` |
| `vaultwarden` | `vaultwarden_enabled: true` |
| `paperless` | `paperless_enabled: true` |
| `plausible` | `plausible_enabled: true` |
