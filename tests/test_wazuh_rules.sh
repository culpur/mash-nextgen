#!/usr/bin/env bash
# test_wazuh_rules.sh — Validates Wazuh rule and decoder XML templates
#
# Checks:
#   1. All XML templates in templates/wazuh-rules/ are well-formed XML
#   2. All XML templates in templates/wazuh-decoders/ are well-formed XML
#   3. Rule IDs don't conflict (no duplicates across all rule files)
#   4. Decoder names are unique across all decoder files
#
# Requirements: xmllint (libxml2), bash 4+
# Usage: ./tests/test_wazuh_rules.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$REPO_DIR/roles/wazuh-integration/templates"
RULES_DIR="$TEMPLATES_DIR/wazuh-rules"
DECODERS_DIR="$TEMPLATES_DIR/wazuh-decoders"

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
if ! command -v xmllint &>/dev/null; then
    echo "ERROR: xmllint is required but not found in PATH."
    echo "Install: brew install libxml2  OR  apt install libxml2-utils"
    exit 2
fi

# ---------------------------------------------------------------------------
# Helper: Strip Jinja2 templates so xmllint can parse the XML
#
# Replaces {{ var }}, {% ... %}, {# ... #} with safe placeholder text.
# This is intentionally simple — we only need well-formedness, not Jinja rendering.
# ---------------------------------------------------------------------------
strip_jinja() {
    sed \
        -e 's/{%[^%]*%}//g' \
        -e 's/{{[^}]*}}/PLACEHOLDER/g' \
        -e 's/{#[^#]*#}//g' \
        "$1"
}

# ---------------------------------------------------------------------------
# Test 1: Well-formed XML — Rule files
# ---------------------------------------------------------------------------
section "Wazuh rule XML well-formedness"

if [[ ! -d "$RULES_DIR" ]]; then
    fail "Rules directory not found: $RULES_DIR"
else
    rule_files=()
    while IFS= read -r f; do
        rule_files+=("$f")
    done < <(find "$RULES_DIR" -name '*.xml.j2' -type f | sort)

    if [[ ${#rule_files[@]} -eq 0 ]]; then
        fail "No rule XML templates found in $RULES_DIR"
    else
        printf "  Found %d rule template(s)\n" "${#rule_files[@]}"
        for rf in "${rule_files[@]}"; do
            fname="$(basename "$rf")"
            # Wrap in a root element since some files may have multiple top-level elements
            stripped="$(strip_jinja "$rf")"
            wrapped="<root>${stripped}</root>"
            if echo "$wrapped" | xmllint --noout - 2>/dev/null; then
                pass "$fname: well-formed XML"
            else
                fail "$fname: malformed XML"
                echo "$wrapped" | xmllint --noout - 2>&1 | head -5 | sed 's/^/    /'
            fi
        done
    fi
fi

# ---------------------------------------------------------------------------
# Test 2: Well-formed XML — Decoder files
# ---------------------------------------------------------------------------
section "Wazuh decoder XML well-formedness"

if [[ ! -d "$DECODERS_DIR" ]]; then
    fail "Decoders directory not found: $DECODERS_DIR"
else
    decoder_files=()
    while IFS= read -r f; do
        decoder_files+=("$f")
    done < <(find "$DECODERS_DIR" -name '*.xml.j2' -type f | sort)

    if [[ ${#decoder_files[@]} -eq 0 ]]; then
        fail "No decoder XML templates found in $DECODERS_DIR"
    else
        printf "  Found %d decoder template(s)\n" "${#decoder_files[@]}"
        for df in "${decoder_files[@]}"; do
            fname="$(basename "$df")"
            stripped="$(strip_jinja "$df")"
            wrapped="<root>${stripped}</root>"
            if echo "$wrapped" | xmllint --noout - 2>/dev/null; then
                pass "$fname: well-formed XML"
            else
                fail "$fname: malformed XML"
                echo "$wrapped" | xmllint --noout - 2>&1 | head -5 | sed 's/^/    /'
            fi
        done
    fi
fi

# ---------------------------------------------------------------------------
# Test 3: No duplicate rule IDs across all rule files
# ---------------------------------------------------------------------------
section "Rule ID uniqueness"

declare -A rule_id_source=()
dup_found=false

for rf in "${rule_files[@]}"; do
    fname="$(basename "$rf")"
    stripped="$(strip_jinja "$rf")"

    # Extract rule id= attributes using grep (works even with Jinja residue)
    while IFS= read -r rule_id; do
        [[ -z "$rule_id" ]] && continue
        if [[ -n "${rule_id_source[$rule_id]+_}" ]]; then
            fail "Duplicate rule ID $rule_id: found in $fname AND ${rule_id_source[$rule_id]}"
            dup_found=true
        else
            rule_id_source["$rule_id"]="$fname"
        fi
    done < <(echo "$stripped" | grep -oE 'rule id="[0-9]+"' | grep -oE '[0-9]+')
done

total_rules=${#rule_id_source[@]}
if ! $dup_found; then
    pass "All $total_rules rule IDs are unique across ${#rule_files[@]} file(s)"
fi

# Report rule ID ranges per file for documentation
printf "\n  Rule ID inventory:\n"
for rf in "${rule_files[@]}"; do
    fname="$(basename "$rf")"
    stripped="$(strip_jinja "$rf")"
    ids=$(echo "$stripped" | grep -oE 'rule id="[0-9]+"' | grep -oE '[0-9]+' | sort -n)
    if [[ -n "$ids" ]]; then
        first=$(echo "$ids" | head -1)
        last=$(echo "$ids" | tail -1)
        count=$(echo "$ids" | wc -l | tr -d ' ')
        printf "    %-30s IDs %s-%s (%s rules)\n" "$fname" "$first" "$last" "$count"
    fi
done

# ---------------------------------------------------------------------------
# Test 4: No duplicate decoder names across all decoder files
# ---------------------------------------------------------------------------
section "Decoder name uniqueness"

declare -A decoder_name_source=()
dup_found=false

for df in "${decoder_files[@]}"; do
    fname="$(basename "$df")"
    stripped="$(strip_jinja "$df")"

    # Extract decoder name= attributes
    while IFS= read -r dec_name; do
        [[ -z "$dec_name" ]] && continue
        if [[ -n "${decoder_name_source[$dec_name]+_}" ]]; then
            fail "Duplicate decoder name '$dec_name': found in $fname AND ${decoder_name_source[$dec_name]}"
            dup_found=true
        else
            decoder_name_source["$dec_name"]="$fname"
        fi
    done < <(echo "$stripped" | grep -oE 'decoder name="[^"]*"' | sed 's/decoder name="//;s/"//')
done

total_decoders=${#decoder_name_source[@]}
if ! $dup_found; then
    pass "All $total_decoders decoder names are unique across ${#decoder_files[@]} file(s)"
fi

# Report decoders per file
printf "\n  Decoder inventory:\n"
for df in "${decoder_files[@]}"; do
    fname="$(basename "$df")"
    stripped="$(strip_jinja "$df")"
    names=$(echo "$stripped" | grep -oE 'decoder name="[^"]*"' | sed 's/decoder name="//;s/"//' | sort)
    if [[ -n "$names" ]]; then
        count=$(echo "$names" | wc -l | tr -d ' ')
        printf "    %-30s %s decoder(s): %s\n" "$fname" "$count" "$(echo "$names" | tr '\n' ', ' | sed 's/, *$//')"
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
