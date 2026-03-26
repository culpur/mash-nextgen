# Contributing to mash-nextgen

This project extends [MASH](https://github.com/mother-of-all-self-hosting/mash-playbook) and [MDAD](https://github.com/spantaleev/matrix-docker-ansible-deploy) with Docker Swarm multi-host deployment, Wazuh monitoring, Authentik SSO, and fail2ban integration. Contributions that add service coverage, fix bugs, or improve the Swarm orchestration layer are welcome.

## Project Layout

```
mash-nextgen/
  upstream/                          # git subtree — DO NOT EDIT
    mash-playbook/
    matrix-docker-ansible-deploy/
  roles/
    wazuh-integration/               # Wazuh decoders, rules, dashboards, fail2ban
      defaults/main.yml              # Service detection variables
      templates/wazuh-decoders/      # Decoder XML templates (Jinja2)
      templates/wazuh-rules/         # Rule XML templates (Jinja2)
      templates/fail2ban/            # Fail2ban jail templates
      files/dashboards/              # OpenSearch/Wazuh dashboard NDJSON
    authentik-sso/                   # Authentik OIDC/proxy provider automation
      defaults/main.yml              # SSO config per service
      tasks/main.yml                 # Authentik API calls
    swarm-init/                      # Docker Swarm cluster bootstrap
    swarm-networking/                # Overlay network creation
    swarm-placement/                 # Node labels + constraints
    swarm-traefik/                   # Traefik in global Swarm mode
    swarm-service-wrapper/           # Wraps upstream roles with deploy: sections
    shared-storage/                  # NFS for cross-node data
  playbooks/
  inventory/
  scripts/
  docs/
```

## How to Add a New Service

Adding monitoring and SSO for a new service involves up to six steps. Not every service needs all of them. See `docs/adding-a-service.md` for the full walkthrough.

Summary:

1. **Service detection** -- Add a `wazuh_service_<name>` variable to `roles/wazuh-integration/defaults/main.yml`
2. **Wazuh decoder** -- Create `roles/wazuh-integration/templates/wazuh-decoders/<name>.xml.j2`
3. **Wazuh rules** -- Create `roles/wazuh-integration/templates/wazuh-rules/<name>.xml.j2`
4. **Dashboard** -- Export or create `roles/wazuh-integration/files/dashboards/<name>.ndjson`
5. **Fail2ban jail** -- Create `roles/wazuh-integration/templates/fail2ban/jail-<name>.conf.j2` (if the service has login endpoints)
6. **Authentik SSO** -- Add an `authentik_sso_<name>` block to `roles/authentik-sso/defaults/main.yml` (if the service supports OIDC or proxy auth)
7. **Update coverage** -- Add the service to `docs/service-coverage.md`

## How to Sync Upstream Changes

Both MASH and MDAD are tracked as git subtrees under `upstream/`. Never edit files there directly.

```bash
# Sync both upstreams
./scripts/upstream-sync.sh both

# Sync one at a time
./scripts/upstream-sync.sh mash
./scripts/upstream-sync.sh mdad

# After syncing, check for conflicts with our wrapper roles
git diff HEAD~1 -- upstream/
```

The `upstream-check.yml` GitHub Actions workflow runs weekly and creates an issue when new upstream commits are available.

When a sync introduces conflicts:
- Resolve them in the wrapper roles (under `roles/`), not in `upstream/`
- Document the conflict and resolution in the commit message
- If upstream changed a variable name we depend on, update the corresponding detection variable in `wazuh-integration/defaults/main.yml` or `authentik-sso/defaults/main.yml`

## Code Style

### Ansible

- Use FQCNs for all modules (e.g., `ansible.builtin.template`, not `template`)
- Name every task descriptively (the `name:` field is mandatory)
- Use `ansible.builtin.debug` for informational messages, not `command: echo`
- Prefer `ansible.builtin.uri` over `command: curl`
- Use `| default(false)` for all boolean service detection variables
- Keep `defaults/main.yml` as the single source of truth for service flags -- do not hardcode service checks in tasks

### YAML

- Two-space indentation
- Start files with `---`
- No trailing whitespace
- Strings: use quotes only when YAML requires them (colons, special chars, Jinja2 expressions)
- Line length: 200 max (we have complex Jinja2 expressions)

### Jinja2 Templates

- Include a `<!-- Managed by mash-nextgen -->` comment at the top of XML templates
- Use meaningful variable names, not single letters
- Keep one decoder/rule concern per file -- do not combine unrelated services

### Wazuh XML

- Decoder rule IDs: use the 100xxx range (see existing rules for allocated blocks)
- Always set `<mitre><id>` tags on detection rules where a MITRE ATT&CK technique applies
- Use `<same_source_ip/>` for correlation rules (brute force detection)
- Group names: `service_name,category` (e.g., `synapse,authentication_failed`)

### Fail2ban

- Jail names: `<service>-auth` for login failures, `<service>-abuse` for other abuse
- Use the `fail2ban_<service>_*` variables from defaults, never hardcode thresholds
- Filter regex must match the decoder's `<regex>` pattern to stay consistent

## Testing Procedures

### Local Validation

Before opening a PR, run these checks locally:

```bash
# YAML syntax check
yamllint roles/*/defaults/*.yml roles/*/tasks/*.yml playbooks/*.yml

# Ansible syntax check (does not require inventory)
ansible-playbook --syntax-check playbooks/swarm-init.yml

# Ansible lint (excludes upstream/)
pip install ansible-lint
ansible-lint roles/ playbooks/

# Jinja2 template syntax
python3 -c "
from jinja2 import Environment, FileSystemLoader
import glob, sys, os
errors = 0
for f in sorted(glob.glob('roles/**/templates/**/*.j2', recursive=True)):
    try:
        env = Environment(loader=FileSystemLoader(os.path.dirname(f)))
        env.get_template(os.path.basename(f))
    except Exception as e:
        print(f'ERROR: {f}: {e}')
        errors += 1
print(f'{errors} error(s)') if errors else print('All templates OK')
sys.exit(1 if errors else 0)
"

# Wazuh XML well-formedness (requires lxml)
pip install lxml jinja2
python3 -c "
from jinja2 import Environment, FileSystemLoader, Undefined
from lxml import etree
import glob, sys, os
errors = 0
for f in sorted(glob.glob('roles/wazuh-integration/templates/wazuh-*/*.xml.j2')):
    env = Environment(loader=FileSystemLoader(os.path.dirname(f)), undefined=Undefined)
    try:
        rendered = env.get_template(os.path.basename(f)).render()
        etree.fromstring(rendered.encode())
    except Exception as e:
        print(f'ERROR: {f}: {e}')
        errors += 1
print(f'{errors} error(s)') if errors else print('All XML templates OK')
sys.exit(1 if errors else 0)
"
```

### CI Validation

The `lint.yml` workflow runs automatically on push and PR. It checks:

1. `ansible-lint` on all roles and playbooks (excluding `upstream/`)
2. Jinja2 template syntax for all `.j2` files
3. Wazuh XML well-formedness for all decoder and rule templates

### Integration Testing

For testing against a real Wazuh/Authentik stack:

1. Deploy to a staging environment with the target service enabled
2. Verify the decoder parses real log lines (`/var/ossec/bin/wazuh-logtest`)
3. Verify rules fire at the correct levels (`/var/ossec/bin/wazuh-logtest` with sample events)
4. Verify the dashboard loads and shows data in Wazuh Dashboard
5. Verify the fail2ban jail bans after the configured threshold
6. Verify the Authentik SSO flow completes (login, callback, session)

## PR Requirements

All pull requests must:

1. **Pass CI** -- The `lint.yml` workflow must pass (ansible-lint, Jinja2 validation, XML validation)
2. **Include a description** -- What service is being added or changed, and why
3. **Update `docs/service-coverage.md`** -- If adding or changing service coverage
4. **Not modify `upstream/`** -- Changes to upstream are done exclusively via `git subtree pull`
5. **Follow the naming conventions** -- File names, variable names, rule IDs must follow existing patterns
6. **Allocate rule IDs correctly** -- Check existing rules to avoid ID collisions in the 100xxx range
7. **Test decoder regex** -- Include sample log lines that the decoder should match (in the PR description or as comments in the template)

### Rule ID Allocation

| Range | Service |
|-------|---------|
| 100100-100109 | Synapse |
| 100110-100119 | Synapse workers |
| 100120-100129 | Matrix bridges |
| 100130-100139 | Matrix bots |
| 100200-100209 | WordPress |
| 100210-100219 | Nextcloud |
| 100220-100229 | Forgejo/Gitea |
| 100300-100309 | Docker Swarm |
| 100310-100319 | Docker Registry |
| 100400-100409 | Traefik |
| 100500-100509 | Vaultwarden |
| 100510-100519 | Authentik |
| 100520-100529 | Keycloak/Authelia |
| 100600-100609 | PostgreSQL |
| 100700-100709 | Jellyfin |
| 100710-100719 | PeerTube |
| 100720-100729 | Immich |
| 100800-100809 | GoToSocial |
| 100810-100819 | Headscale |
| 100900-100999 | Reserved (future) |

When adding a new service, pick the next available block and document it here.

## Questions

Open an issue with the `question` label, or check the existing docs:

- `docs/architecture.md` -- Design decisions and Swarm topology
- `docs/migration.md` -- Migrating from single-host MASH/MDAD
- `docs/service-coverage.md` -- Current monitoring and SSO coverage
- `docs/adding-a-service.md` -- Step-by-step guide for new service integration
