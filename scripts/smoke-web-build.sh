#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/keithable-env.sh"
ensure_node

PROMPT="${1:-a tiny hello world page with one big blue button}"
MODEL="${KEITHABLE_MODEL:-free-balanced}"
PROJECT_JSON="{\"prompt\":\"$PROMPT\",\"platform\":\"web\",\"model\":\"$MODEL\"}"

echo "Creating web build smoke test..."
PROJECT_ID="$(convex run projects:create "$PROJECT_JSON" | tr -d '"')"
echo "Project: $PROJECT_ID"

for attempt in $(seq 1 60); do
  STATUS_JSON="$(convex run projects:get "{\"id\":\"$PROJECT_ID\"}")"
  STATUS="$(printf '%s' "$STATUS_JSON" | "$NODE_BIN" -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{const p=JSON.parse(s); console.log(p.status || "")})')"
  DETAIL="$(printf '%s' "$STATUS_JSON" | "$NODE_BIN" -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{const p=JSON.parse(s); console.log(p.statusDetail || p.error || "")})')"
  echo "[$attempt/60] $STATUS - $DETAIL"

  if [[ "$STATUS" == "live" ]]; then
    printf '%s' "$STATUS_JSON" | "$NODE_BIN" -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{const p=JSON.parse(s); console.log(`Preview: ${p.previewUrl || "(missing)"}`)})'
    exit 0
  fi

  if [[ "$STATUS" == "error" ]]; then
    printf '%s\n' "$STATUS_JSON"
    exit 1
  fi

  sleep 10
done

echo "Timed out waiting for project $PROJECT_ID."
exit 1
