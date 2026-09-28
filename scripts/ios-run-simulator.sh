#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/keithable-env.sh"

SIMULATOR_NAME="${1:-iPhone 17}"
USER_NAME="${KEITHABLE_USER_NAME:-Keith}"
URL="$(convex_url)"

ensure_xcodegen

cat > "$REPO_ROOT/ios/Sources/AppConfig.swift" <<SWIFT
import Foundation

enum AppConfig {
    static let convexDeploymentURL = "$URL"
    static let userName = "$USER_NAME"
}
SWIFT

cd "$REPO_ROOT/ios"

echo "Generating Xcode project..."
"$XCODEGEN_BIN" generate

echo "Building Petrable for $SIMULATOR_NAME..."
xcodebuild \
  -project Forge.xcodeproj \
  -scheme Forge \
  -destination "platform=iOS Simulator,name=$SIMULATOR_NAME" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "Booting simulator..."
xcrun simctl boot "$SIMULATOR_NAME" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_NAME" -b

echo "Installing and launching Petrable..."
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Forge.app
xcrun simctl launch booted com.example.rilable
open -a Simulator
