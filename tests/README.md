# mash-nextgen Integration Tests

Validation tests for the mash-nextgen Ansible roles. These scripts run locally
and do not require a live Docker Swarm cluster or Wazuh instance.

## Prerequisites

| Tool      | Used by              | Install                             |
|-----------|----------------------|-------------------------------------|
| `yq` v4+  | `test_convert.sh`    | `brew install yq`                   |
| `jq`      | `test_dashboards.sh` | `brew install jq`                   |
| `xmllint` | `test_wazuh_rules.sh`| `brew install libxml2` (usually pre-installed on macOS) |
| `bash` 4+ | all scripts          | `brew install bash` (macOS ships 3.x) |

## Running Tests

From the repository root:

```bash
# Run all tests
./tests/test_convert.sh && ./tests/test_dashboards.sh && ./tests/test_wazuh_rules.sh

# Run individually
./tests/test_convert.sh        # Compose-to-stack conversion
./tests/test_dashboards.sh     # NDJSON dashboard validation
./tests/test_wazuh_rules.sh    # Wazuh XML rule/decoder validation
```

All scripts exit 0 on success, 1 on test failure, 2 on missing dependencies.

## What Each Test Covers

### test_convert.sh — Compose-to-Stack Conversion

Simulates the `swarm-service-wrapper` Ansible role logic using `yq` to convert
the fixture compose files and then validates the output:

- `container_name` fields are removed from all services
- `deploy:` sections are injected on every service
- `restart:` directives are converted to `deploy.restart_policy`
- PostgreSQL services have `node.labels.role == manager` constraint
- Bridge services (mautrix-*) have `node.labels.role == worker` constraint
- Traefik services have `mode: global` with no `replicas`
- Cache services (valkey, keydb) are pinned to manager
- Worker services get `replicas: 2` and `spread: node.id` preference

Fixture files in `tests/fixtures/`:
- `matrix-compose.yml` — Realistic MDAD output (Synapse, workers, bridges, Element, Traefik, Valkey)
- `mash-compose.yml` — Realistic MASH output (Authentik, SearXNG, Uptime Kuma, Traefik, KeyDB)

### test_dashboards.sh — NDJSON Dashboard Validation

Validates the 14 OpenSearch dashboard files in
`roles/wazuh-integration/files/dashboards/`:

- Every line in each file is valid JSON (NDJSON format)
- Each file contains at least 1 `index-pattern`, 1+ `visualization`, and 1 `dashboard`
- Visualization `visState.type` values are valid OpenSearch types
- Dashboard `panelsJSON` references point to visualization IDs that exist in the same file

### test_wazuh_rules.sh — Wazuh XML Rule/Decoder Validation

Validates XML templates in `roles/wazuh-integration/templates/`:

- All `.xml.j2` files in `wazuh-rules/` are well-formed XML (after stripping Jinja2 syntax)
- All `.xml.j2` files in `wazuh-decoders/` are well-formed XML
- Rule IDs are unique across all rule files (no conflicts)
- Decoder names are unique across all decoder files
- Prints an inventory of rule ID ranges and decoder names per file

## Adding New Tests

Follow the same pattern: executable shell script, exit 0/1/2, color-coded output.
Place fixture data in `tests/fixtures/`.
