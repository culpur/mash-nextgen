#!/usr/bin/env bash
# test_convert.sh — Integration test for swarm-service-wrapper compose-to-stack conversion
#
# Simulates the Ansible conversion logic using yq (https://github.com/mikefarah/yq)
# and validates the output matches Swarm requirements.
#
# Requirements: yq v4+, bash 4+
# Usage: ./tests/test_convert.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
WORK_DIR="$(mktemp -d)"

trap 'rm -rf "$WORK_DIR"' EXIT

PASS=0
FAIL=0
TOTAL=0

pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    printf "  \033[32mPASS\033[0m %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    printf "  \033[31mFAIL\033[0m %s\n" "$1"
}

section() {
    printf "\n\033[1m--- %s ---\033[0m\n" "$1"
}

# ---------------------------------------------------------------------------
# Check dependencies
# ---------------------------------------------------------------------------
if ! command -v yq &>/dev/null; then
    echo "ERROR: yq (mikefarah/yq) is required but not found in PATH."
    echo "Install: brew install yq  OR  https://github.com/mikefarah/yq/releases"
    exit 2
fi

# ---------------------------------------------------------------------------
# Conversion function — mirrors swarm-service-wrapper/tasks/convert-compose.yml
#
# For each service in the compose file:
#   1. Remove container_name
#   2. Convert restart: to deploy.restart_policy
#   3. Inject deploy: with placement constraints based on service category
# ---------------------------------------------------------------------------

# Category-to-constraint mapping (from roles/swarm-service-wrapper/defaults/main.yml)
declare -A CATEGORY_CONSTRAINTS
CATEGORY_CONSTRAINTS[core]='node.labels.role == manager'
CATEGORY_CONSTRAINTS[workers]=''
CATEGORY_CONSTRAINTS[bridges]='node.labels.role == worker'
CATEGORY_CONSTRAINTS[bots]='node.labels.role == worker'
CATEGORY_CONSTRAINTS[media]='node.labels.role == worker'
CATEGORY_CONSTRAINTS[web]=''
CATEGORY_CONSTRAINTS[auth]=''
CATEGORY_CONSTRAINTS[monitoring]=''
CATEGORY_CONSTRAINTS[database]='node.labels.role == manager'
CATEGORY_CONSTRAINTS[cache]='node.labels.role == manager'
CATEGORY_CONSTRAINTS[global]=''

declare -A CATEGORY_MODE
CATEGORY_MODE[core]='replicated'
CATEGORY_MODE[workers]='replicated'
CATEGORY_MODE[bridges]='replicated'
CATEGORY_MODE[bots]='replicated'
CATEGORY_MODE[media]='replicated'
CATEGORY_MODE[web]='replicated'
CATEGORY_MODE[auth]='replicated'
CATEGORY_MODE[monitoring]='replicated'
CATEGORY_MODE[database]='replicated'
CATEGORY_MODE[cache]='replicated'
CATEGORY_MODE[global]='global'

# Service-to-category map (subset relevant to our fixtures)
declare -A SERVICE_CATEGORY
# Matrix fixture
SERVICE_CATEGORY[matrix-synapse]='core'
SERVICE_CATEGORY[matrix-postgres]='core'
SERVICE_CATEGORY[matrix-synapse-worker-generic-0]='workers'
SERVICE_CATEGORY[matrix-synapse-worker-federation-sender-0]='workers'
SERVICE_CATEGORY[matrix-mautrix-discord]='bridges'
SERVICE_CATEGORY[matrix-mautrix-telegram]='bridges'
SERVICE_CATEGORY[matrix-mautrix-whatsapp]='bridges'
SERVICE_CATEGORY[matrix-traefik]='global'
SERVICE_CATEGORY[matrix-element]='web'
SERVICE_CATEGORY[matrix-valkey]='cache'
# MASH fixture
SERVICE_CATEGORY[mash-authentik-server]='auth'
SERVICE_CATEGORY[mash-authentik-worker]='auth'
SERVICE_CATEGORY[mash-postgres]='core'
SERVICE_CATEGORY[mash-keydb]='cache'
SERVICE_CATEGORY[mash-traefik]='global'
SERVICE_CATEGORY[mash-searxng]='web'
SERVICE_CATEGORY[mash-uptime-kuma]='monitoring'
SERVICE_CATEGORY[mash-valkey]='cache'

# Map compose restart: values to Swarm restart_policy condition:
declare -A RESTART_MAP
RESTART_MAP[always]='any'
RESTART_MAP[unless-stopped]='any'
RESTART_MAP[on-failure]='on-failure'
RESTART_MAP[no]='none'

convert_compose() {
    local input="$1"
    local output="$2"
    local base
    base="$(basename "$input")"

    # Start with a copy
    cp "$input" "$output"

    # Get list of services
    local services
    services=$(yq '.services | keys | .[]' "$input")

    for svc in $services; do
        local category="${SERVICE_CATEGORY[$svc]:-_default}"
        local mode="${CATEGORY_MODE[$category]:-replicated}"
        local constraint="${CATEGORY_CONSTRAINTS[$category]:-}"

        # 1. Remove container_name
        yq -i "del(.services.\"$svc\".container_name)" "$output"

        # 2. Convert restart: to deploy.restart_policy
        local restart_val
        restart_val=$(yq ".services.\"$svc\".restart // \"\"" "$output" | tr -d '"')
        if [[ -n "$restart_val" && "$restart_val" != "null" ]]; then
            local condition="${RESTART_MAP[$restart_val]:-any}"
            yq -i "del(.services.\"$svc\".restart)" "$output"
            yq -i ".services.\"$svc\".deploy.restart_policy.condition = \"$condition\"" "$output"
            yq -i ".services.\"$svc\".deploy.restart_policy.delay = \"5s\"" "$output"
            yq -i ".services.\"$svc\".deploy.restart_policy.max_attempts = 0" "$output"
            yq -i ".services.\"$svc\".deploy.restart_policy.window = \"120s\"" "$output"
        fi

        # 3. Inject deploy mode
        yq -i ".services.\"$svc\".deploy.mode = \"$mode\"" "$output"

        # 4. Inject replicas (only for replicated)
        if [[ "$mode" == "replicated" ]]; then
            local replicas=1
            if [[ "$category" == "workers" ]]; then
                replicas=2
            fi
            yq -i ".services.\"$svc\".deploy.replicas = $replicas" "$output"
        fi

        # 5. Inject placement constraints
        if [[ -n "$constraint" ]]; then
            yq -i ".services.\"$svc\".deploy.placement.constraints = [\"$constraint\"]" "$output"
        fi

        # 6. Workers get spread preference
        if [[ "$category" == "workers" ]]; then
            yq -i ".services.\"$svc\".deploy.placement.preferences = [{\"spread\": \"node.id\"}]" "$output"
        fi
    done
}

# ---------------------------------------------------------------------------
# Convert both fixtures
# ---------------------------------------------------------------------------
section "Converting fixture compose files"

convert_compose "$FIXTURES_DIR/matrix-compose.yml" "$WORK_DIR/matrix-stack.yml"
echo "  Converted matrix-compose.yml -> matrix-stack.yml"

convert_compose "$FIXTURES_DIR/mash-compose.yml" "$WORK_DIR/mash-stack.yml"
echo "  Converted mash-compose.yml -> mash-stack.yml"

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------
svc_field() {
    # svc_field <file> <service> <yq-path>
    yq ".services.\"$2\"$3" "$1" 2>/dev/null
}

has_no_field() {
    local val
    val=$(svc_field "$1" "$2" ".$3")
    [[ "$val" == "null" || -z "$val" ]]
}

# ---------------------------------------------------------------------------
# Test: container_name removed from all services
# ---------------------------------------------------------------------------
section "container_name removal"

for file in "$WORK_DIR/matrix-stack.yml" "$WORK_DIR/mash-stack.yml"; do
    fname="$(basename "$file")"
    services=$(yq '.services | keys | .[]' "$file")
    for svc in $services; do
        if has_no_field "$file" "$svc" "container_name"; then
            pass "$fname/$svc: no container_name"
        else
            fail "$fname/$svc: container_name still present"
        fi
    done
done

# ---------------------------------------------------------------------------
# Test: deploy sections present on all services
# ---------------------------------------------------------------------------
section "deploy section presence"

for file in "$WORK_DIR/matrix-stack.yml" "$WORK_DIR/mash-stack.yml"; do
    fname="$(basename "$file")"
    services=$(yq '.services | keys | .[]' "$file")
    for svc in $services; do
        local_deploy=$(svc_field "$file" "$svc" ".deploy")
        if [[ "$local_deploy" != "null" && -n "$local_deploy" ]]; then
            pass "$fname/$svc: deploy section exists"
        else
            fail "$fname/$svc: deploy section missing"
        fi
    done
done

# ---------------------------------------------------------------------------
# Test: restart fields converted to deploy.restart_policy
# ---------------------------------------------------------------------------
section "restart -> deploy.restart_policy conversion"

for file in "$WORK_DIR/matrix-stack.yml" "$WORK_DIR/mash-stack.yml"; do
    fname="$(basename "$file")"
    services=$(yq '.services | keys | .[]' "$file")
    for svc in $services; do
        # No bare restart: should remain
        if has_no_field "$file" "$svc" "restart"; then
            pass "$fname/$svc: restart field removed"
        else
            fail "$fname/$svc: restart field still present"
        fi
        # restart_policy should exist
        rp_condition=$(svc_field "$file" "$svc" ".deploy.restart_policy.condition")
        if [[ "$rp_condition" != "null" && -n "$rp_condition" ]]; then
            pass "$fname/$svc: restart_policy.condition = $rp_condition"
        else
            fail "$fname/$svc: restart_policy.condition missing"
        fi
    done
done

# ---------------------------------------------------------------------------
# Test: PostgreSQL pinned to manager
# ---------------------------------------------------------------------------
section "PostgreSQL placement constraints"

for pg_svc in matrix-postgres mash-postgres; do
    local_file="$WORK_DIR/matrix-stack.yml"
    [[ "$pg_svc" == mash-* ]] && local_file="$WORK_DIR/mash-stack.yml"

    constraint=$(svc_field "$local_file" "$pg_svc" ".deploy.placement.constraints[0]")
    if [[ "$constraint" == *"node.labels.role == manager"* ]]; then
        pass "$pg_svc: constraint = node.labels.role == manager"
    else
        fail "$pg_svc: expected manager constraint, got: $constraint"
    fi
done

# ---------------------------------------------------------------------------
# Test: Bridge services constrained to worker nodes
# ---------------------------------------------------------------------------
section "Bridge placement constraints"

for bridge_svc in matrix-mautrix-discord matrix-mautrix-telegram matrix-mautrix-whatsapp; do
    constraint=$(svc_field "$WORK_DIR/matrix-stack.yml" "$bridge_svc" ".deploy.placement.constraints[0]")
    if [[ "$constraint" == *"node.labels.role == worker"* ]]; then
        pass "$bridge_svc: constraint = node.labels.role == worker"
    else
        fail "$bridge_svc: expected worker constraint, got: $constraint"
    fi
done

# ---------------------------------------------------------------------------
# Test: Traefik has mode: global
# ---------------------------------------------------------------------------
section "Traefik global mode"

for traefik_svc in matrix-traefik mash-traefik; do
    local_file="$WORK_DIR/matrix-stack.yml"
    [[ "$traefik_svc" == mash-* ]] && local_file="$WORK_DIR/mash-stack.yml"

    mode=$(svc_field "$local_file" "$traefik_svc" ".deploy.mode")
    if [[ "$mode" == "global" ]]; then
        pass "$traefik_svc: mode = global"
    else
        fail "$traefik_svc: expected global mode, got: $mode"
    fi

    # Global services should NOT have a replicas field
    replicas=$(svc_field "$local_file" "$traefik_svc" ".deploy.replicas")
    if [[ "$replicas" == "null" ]]; then
        pass "$traefik_svc: no replicas (correct for global)"
    else
        fail "$traefik_svc: replicas present on global service: $replicas"
    fi
done

# ---------------------------------------------------------------------------
# Test: Cache services (valkey, keydb) pinned to manager
# ---------------------------------------------------------------------------
section "Cache service placement"

for cache_svc in matrix-valkey mash-valkey mash-keydb; do
    local_file="$WORK_DIR/matrix-stack.yml"
    [[ "$cache_svc" == mash-* ]] && local_file="$WORK_DIR/mash-stack.yml"

    constraint=$(svc_field "$local_file" "$cache_svc" ".deploy.placement.constraints[0]")
    if [[ "$constraint" == *"node.labels.role == manager"* ]]; then
        pass "$cache_svc: constraint = node.labels.role == manager"
    else
        fail "$cache_svc: expected manager constraint, got: $constraint"
    fi
done

# ---------------------------------------------------------------------------
# Test: Worker services have spread preference and replicas=2
# ---------------------------------------------------------------------------
section "Worker service configuration"

for worker_svc in matrix-synapse-worker-generic-0 matrix-synapse-worker-federation-sender-0; do
    replicas=$(svc_field "$WORK_DIR/matrix-stack.yml" "$worker_svc" ".deploy.replicas")
    if [[ "$replicas" == "2" ]]; then
        pass "$worker_svc: replicas = 2"
    else
        fail "$worker_svc: expected 2 replicas, got: $replicas"
    fi

    spread=$(svc_field "$WORK_DIR/matrix-stack.yml" "$worker_svc" ".deploy.placement.preferences[0].spread")
    if [[ "$spread" == "node.id" ]]; then
        pass "$worker_svc: spread preference = node.id"
    else
        fail "$worker_svc: expected spread node.id, got: $spread"
    fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
section "Results"
printf "  Total: %d  Passed: %d  Failed: %d\n" "$TOTAL" "$PASS" "$FAIL"

if [[ "$FAIL" -gt 0 ]]; then
    printf "\n  \033[31mFAILED\033[0m — %d test(s) failed\n" "$FAIL"
    exit 1
else
    printf "\n  \033[32mALL TESTS PASSED\033[0m\n"
    exit 0
fi
