#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/keithable-env.sh"

BUNDLE_ID="${KEITHABLE_BUNDLE_ID:-com.keithfleishman.keithable}"
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

BUILD_DIR="$REPO_ROOT/ios/build"
PRODUCTS_DIR="$BUILD_DIR/Build/Products/Release-iphoneos"
APP_PATH="$PRODUCTS_DIR/Forge.app"
PAYLOAD_DIR="$BUILD_DIR/unsigned-ipa/Payload"
IPA_PATH="$BUILD_DIR/unsigned-ipa/Petrable-unsigned.ipa"

echo "Building unsigned Petrable app for device..."
xcodebuild \
  -project Forge.xcodeproj \
  -scheme Forge \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$BUILD_DIR" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle not found at $APP_PATH" >&2
  exit 1
fi

rm -rf "$BUILD_DIR/unsigned-ipa"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/Petrable.app"

echo "Packaging unsigned IPA..."
(
  cd "$BUILD_DIR/unsigned-ipa"
  /usr/bin/zip -qry "$IPA_PATH" Payload
)

echo "Unsigned IPA output:"
echo "$IPA_PATH"
