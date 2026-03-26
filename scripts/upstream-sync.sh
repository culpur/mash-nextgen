#!/bin/bash
# Sync upstream MASH and MDAD changes into mash-nextgen
#
# Usage: ./scripts/upstream-sync.sh [mash|mdad|both]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

sync_mash() {
    echo "=== Syncing MASH playbook ==="
    git subtree pull \
        --prefix=upstream/mash-playbook \
        https://github.com/mother-of-all-self-hosting/mash-playbook.git \
        main --squash \
        -m "chore: sync upstream mash-playbook $(date +%Y-%m-%d)"
    echo "[+] MASH synced"
}

sync_mdad() {
    echo "=== Syncing matrix-docker-ansible-deploy ==="
    git subtree pull \
        --prefix=upstream/matrix-docker-ansible-deploy \
        https://github.com/spantaleev/matrix-docker-ansible-deploy.git \
        master --squash \
        -m "chore: sync upstream matrix-docker-ansible-deploy $(date +%Y-%m-%d)"
    echo "[+] MDAD synced"
}

case "${1:-both}" in
    mash)
        sync_mash
        ;;
    mdad)
        sync_mdad
        ;;
    both)
        sync_mash
        echo ""
        sync_mdad
        ;;
    *)
        echo "Usage: $0 [mash|mdad|both]"
        exit 1
        ;;
esac

echo ""
echo "=== Done ==="
git log --oneline -5
