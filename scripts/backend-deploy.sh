#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/keithable-env.sh"

echo "Deploying Convex functions..."
convex dev --once
echo "Convex functions are ready."
