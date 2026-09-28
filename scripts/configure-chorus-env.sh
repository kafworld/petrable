#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/keithable-env.sh"

TODIST_PROJECT_ID="${KEITHABLE_TODIST_PROJECT_ID:-jd7fbe5j1j2s3ertzc3scev20589en0s}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
Usage:
  CHORUS_API_KEY=chorus_... CHORUS_USER_ID=... scripts/configure-chorus-env.sh [--retry-todist]

Sets Petrable's Chorus/Vibecode mobile-build credentials on the Convex deployment.
Secrets are sent to Convex and are not written into this repository.
USAGE
  exit 0
fi

if [[ -z "${CHORUS_API_KEY:-}" ]]; then
  echo "Missing CHORUS_API_KEY. It should start with chorus_." >&2
  exit 1
fi

if [[ -z "${CHORUS_USER_ID:-}" ]]; then
  echo "Missing CHORUS_USER_ID. The Chorus/Vibecode CLI stores it as userId." >&2
  exit 1
fi

convex env set CHORUS_API_KEY "$CHORUS_API_KEY"
convex env set CHORUS_USER_ID "$CHORUS_USER_ID"

echo "Chorus environment variables are set on Convex."

if [[ "${1:-}" == "--retry-todist" ]]; then
  convex run projects:retry "{\"id\":\"$TODIST_PROJECT_ID\"}"
  echo "Todist mobile build retry queued."
fi
