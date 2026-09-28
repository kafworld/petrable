#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${KEITHABLE_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
TOOLS_DIR="${KEITHABLE_TOOLS_DIR:-/private/tmp/rilable-tools}"
NODE_VERSION="${KEITHABLE_NODE_VERSION:-v24.14.0}"
NODE_DIST="node-${NODE_VERSION}-darwin-arm64"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_DIST}.tar.xz"
XCODEGEN_VERSION="${KEITHABLE_XCODEGEN_VERSION:-2.45.4}"
XCODEGEN_URL="https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"

ensure_node() {
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    NODE_BIN="$(command -v node)"
    NPM_BIN="$(command -v npm)"
    return
  fi

  mkdir -p "$TOOLS_DIR"
  if [[ ! -x "$TOOLS_DIR/$NODE_DIST/bin/node" ]]; then
    echo "Installing temporary Node.js runtime in $TOOLS_DIR..."
    curl -fsSL "$NODE_URL" -o "$TOOLS_DIR/${NODE_DIST}.tar.xz"
    tar -xf "$TOOLS_DIR/${NODE_DIST}.tar.xz" -C "$TOOLS_DIR"
  fi

  export PATH="$TOOLS_DIR/$NODE_DIST/bin:$PATH"
  NODE_BIN="$TOOLS_DIR/$NODE_DIST/bin/node"
  NPM_BIN="$TOOLS_DIR/$NODE_DIST/bin/npm"
}

ensure_xcodegen() {
  if command -v xcodegen >/dev/null 2>&1; then
    XCODEGEN_BIN="$(command -v xcodegen)"
    return
  fi

  mkdir -p "$TOOLS_DIR"
  if [[ ! -x "$TOOLS_DIR/xcodegen/xcodegen/bin/xcodegen" ]]; then
    echo "Installing temporary XcodeGen in $TOOLS_DIR..."
    curl -fsSL "$XCODEGEN_URL" -o "$TOOLS_DIR/xcodegen.zip"
    rm -rf "$TOOLS_DIR/xcodegen"
    unzip -q "$TOOLS_DIR/xcodegen.zip" -d "$TOOLS_DIR/xcodegen"
  fi

  XCODEGEN_BIN="$TOOLS_DIR/xcodegen/xcodegen/bin/xcodegen"
}

ensure_backend_deps() {
  ensure_node
  cd "$REPO_ROOT/backend"
  if [[ ! -d node_modules ]]; then
    npm_config_cache="${KEITHABLE_NPM_CACHE:-/private/tmp/rilable-npm-cache}" "$NPM_BIN" ci
  fi
}

convex() {
  ensure_backend_deps
  cd "$REPO_ROOT/backend"
  npm_config_cache="${KEITHABLE_NPM_CACHE:-/private/tmp/rilable-npm-cache}" npx convex "$@"
}

convex_url() {
  local env_file="$REPO_ROOT/backend/.env.local"
  if [[ ! -f "$env_file" ]]; then
    echo "Missing backend/.env.local. Run scripts/backend-deploy.sh first." >&2
    return 1
  fi
  awk -F= '/^CONVEX_URL=/{print $2}' "$env_file"
}
