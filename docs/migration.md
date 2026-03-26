# Migrating from Single-Host MASH/MDAD

This guide covers migrating an existing single-host MASH or MDAD deployment to mash-nextgen's multi-host Docker Swarm setup.

## Prerequisites

- Two or more Linux hosts with Docker installed
- SSH access between all hosts
- Ansible installed on your control machine
- Existing MASH and/or MDAD deployment (data will be preserved)

## Migration Steps

### 1. Snapshot Your Current Setup

Before anything else, snapshot your VMs/containers:

```bash
# Proxmox example
qm snapshot <vmid> pre-swarm-migration
pct snapshot <ctid> pre-swarm-migration
```

### 2. Set Up Inventory

```bash
cp inventory/hosts.example inventory/hosts
# Edit inventory/hosts with your node IPs
# Edit inventory/host_vars/ for each node
```

### 3. Initialize Swarm (Non-Destructive)

```bash
ansible-playbook -i inventory/hosts playbooks/swarm-init.yml
```

This:
- Initializes Docker Swarm on the manager node
- Joins worker nodes
- Creates overlay networks
- Sets up NFS shared storage
- Deploys Traefik in Swarm mode

**Your existing containers are NOT affected.** Docker Swarm coexists with standalone containers.

### 4. Migrate Services Gradually

Move one service at a time from standalone docker-compose to Swarm stacks:

```bash
# On the old host, stop the bridge
docker stop matrix-mautrix-discord

# Deploy as Swarm service (runs on worker node)
docker service create \
  --name mautrix-discord \
  --network matrix-internal \
  --constraint 'node.labels.role == worker' \
  dock.mau.dev/mautrix/discord:latest
```

### 5. Update Reverse Proxy

After moving services, update your reverse proxy (Traefik labels or external proxy) to route to the Swarm service instead of the standalone container.

### 6. Validate

```bash
ansible-playbook -i inventory/hosts playbooks/swarm-status.yml
```

## Rollback

If anything goes wrong:

1. Stop Swarm services: `docker service rm <service>`
2. Restart standalone containers: `docker start <container>`
3. Leave Swarm (on worker): `docker swarm leave`
4. Restore from snapshot if needed

## Data Considerations

- **PostgreSQL data**: Stays on the manager node's local volume. Not migrated.
- **Matrix media**: Copied to NFS share, accessible from both nodes.
- **Bridge databases**: SQLite files need to be on the node running the bridge, or on NFS.
- **Configuration files**: Remain in their original locations; Swarm services mount them via bind mounts or configs.
