#!/usr/bin/env bash
# test_dashboards.sh — Validates all NDJSON dashboard files
#
# Checks:
#   1. Each line is valid JSON
#   2. Each file has at least 1 index-pattern, 1+ visualizations, 1 dashboard
#   3. Visualization types are valid OpenSearch types
#   4. Dashboard panelsJSON references match existing visualization IDs in the file
#
# Requirements: jq, bash 4+
# Usage: ./tests/test_dashboards.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARDS_DIR="$REPO_DIR/roles/wazuh-integration/files/dashboards"

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
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not found in PATH."
    echo "Install: brew install jq  OR  apt install jq"
    exit 2
fi

# ---------------------------------------------------------------------------
# Valid OpenSearch/Kibana visualization types
# ---------------------------------------------------------------------------
VALID_VIS_TYPES=(
    "area" "line" "histogram" "horizontal_bar" "vertical_bar"
    "pie" "table" "metric" "gauge" "goal"
    "markdown" "tagcloud" "heatmap" "region_map" "coordinate_map"
    "input_control_vis" "vega" "vega-lite" "timelion" "tsvb"
    "maps" "gantt_chart" "timeline"
)

is_valid_vis_type() {
    local t="$1"
    for valid in "${VALID_VIS_TYPES[@]}"; do
        [[ "$t" == "$valid" ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Discover NDJSON files
# ---------------------------------------------------------------------------
ndjson_files=()
while IFS= read -r f; do
    ndjson_files+=("$f")
done < <(find "$DASHBOARDS_DIR" -name '*.ndjson' -type f | sort)

if [[ ${#ndjson_files[@]} -eq 0 ]]; then
    echo "ERROR: No .ndjson files found in $DASHBOARDS_DIR"
    exit 2
fi

section "Discovered ${#ndjson_files[@]} NDJSON files"
printf "  Expected: 14  Found: %d\n" "${#ndjson_files[@]}"
if [[ ${#ndjson_files[@]} -eq 14 ]]; then
    pass "NDJSON file count = 14"
else
    fail "NDJSON file count = ${#ndjson_files[@]} (expected 14)"
fi

# ---------------------------------------------------------------------------
# Per-file validation
# ---------------------------------------------------------------------------
for ndjson_file in "${ndjson_files[@]}"; do
    fname="$(basename "$ndjson_file")"
    section "$fname"

    # --- Check 1: Every line is valid JSON ---
    line_num=0
    json_valid=true
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        if [[ -z "$line" ]]; then
            continue
        fi
        if ! echo "$line" | jq empty 2>/dev/null; then
            fail "$fname: line $line_num is not valid JSON"
            json_valid=false
        fi
    done < "$ndjson_file"

    if $json_valid; then
        pass "$fname: all lines are valid JSON ($line_num lines)"
    fi

    # --- Check 2: Required object types ---
    index_count=0
    vis_count=0
    dashboard_count=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        obj_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
        case "$obj_type" in
            index-pattern) index_count=$((index_count + 1)) ;;
            visualization) vis_count=$((vis_count + 1)) ;;
            dashboard)     dashboard_count=$((dashboard_count + 1)) ;;
        esac
    done < "$ndjson_file"

    if [[ $index_count -ge 1 ]]; then
        pass "$fname: has $index_count index-pattern(s)"
    else
        fail "$fname: missing index-pattern (found $index_count)"
    fi

    if [[ $vis_count -ge 1 ]]; then
        pass "$fname: has $vis_count visualization(s)"
    else
        fail "$fname: missing visualizations (found $vis_count)"
    fi

    if [[ $dashboard_count -ge 1 ]]; then
        pass "$fname: has $dashboard_count dashboard(s)"
    else
        fail "$fname: missing dashboard (found $dashboard_count)"
    fi

    # --- Check 3: Visualization types are valid ---
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        obj_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
        [[ "$obj_type" != "visualization" ]] && continue

        vis_id=$(echo "$line" | jq -r '.id // "unknown"' 2>/dev/null)
        vis_title=$(echo "$line" | jq -r '.attributes.title // "untitled"' 2>/dev/null)

        # The visState is a JSON string inside the attributes
        vis_state_type=$(echo "$line" | jq -r '.attributes.visState' 2>/dev/null | jq -r '.type // empty' 2>/dev/null)

        if [[ -n "$vis_state_type" && "$vis_state_type" != "null" ]]; then
            if is_valid_vis_type "$vis_state_type"; then
                pass "$fname: vis \"$vis_title\" type=$vis_state_type"
            else
                fail "$fname: vis \"$vis_title\" has invalid type: $vis_state_type"
            fi
        else
            fail "$fname: vis \"$vis_title\" ($vis_id) has no parseable visState type"
        fi
    done < "$ndjson_file"

    # --- Check 4: Dashboard panelsJSON references match visualization IDs ---
    # Collect all visualization IDs in this file
    declare -A vis_ids_in_file=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        obj_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
        [[ "$obj_type" != "visualization" ]] && continue
        vid=$(echo "$line" | jq -r '.id // empty' 2>/dev/null)
        [[ -n "$vid" ]] && vis_ids_in_file["$vid"]=1
    done < "$ndjson_file"

    # Check dashboard references
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        obj_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
        [[ "$obj_type" != "dashboard" ]] && continue

        dash_title=$(echo "$line" | jq -r '.attributes.title // "untitled"' 2>/dev/null)

        # Extract referenced visualization IDs from the references array
        ref_count=0
        ref_ok=0
        while IFS= read -r ref_id; do
            [[ -z "$ref_id" ]] && continue
            ref_count=$((ref_count + 1))
            if [[ -n "${vis_ids_in_file[$ref_id]+_}" ]]; then
                ref_ok=$((ref_ok + 1))
            else
                fail "$fname: dashboard \"$dash_title\" references unknown vis ID: $ref_id"
            fi
        done < <(echo "$line" | jq -r '.references[] | select(.type == "visualization") | .id' 2>/dev/null)

        if [[ $ref_count -gt 0 && $ref_ok -eq $ref_count ]]; then
            pass "$fname: dashboard \"$dash_title\" — all $ref_count panel refs valid"
        elif [[ $ref_count -eq 0 ]]; then
            fail "$fname: dashboard \"$dash_title\" has no visualization references"
        fi
    done < "$ndjson_file"

    unset vis_ids_in_file
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
