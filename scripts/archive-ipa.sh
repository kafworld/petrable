#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/keithable-env.sh"

TEAM_ID="${KEITHABLE_TEAM_ID:-}"
BUNDLE_ID="${KEITHABLE_BUNDLE_ID:-com.example.rilable}"
EXPORT_METHOD="${KEITHABLE_EXPORT_METHOD:-development}"
USER_NAME="${KEITHABLE_USER_NAME:-Keith}"
URL="$(convex_url)"

if [[ -z "$TEAM_ID" ]]; then
  cat >&2 <<'EOF'
Missing KEITHABLE_TEAM_ID.

Run with your Apple Developer Team ID, for example:

  KEITHABLE_TEAM_ID=ABCDE12345 scripts/archive-ipa.sh

Optional overrides:

  KEITHABLE_BUNDLE_ID=com.yourcompany.keithable
  KEITHABLE_EXPORT_METHOD=development | ad-hoc
EOF
  exit 1
fi

SIGNING_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if ! printf '%s\n' "$SIGNING_IDENTITIES" | grep -Eq 'Apple (Development|Distribution)'; then
  cat >&2 <<'EOF'
No Apple code-signing certificate is available in this Mac keychain.

Install or select your Apple Development/Distribution certificate in Xcode first:

  Xcode > Settings > Accounts > Apple ID > Manage Certificates

Then rerun this script with KEITHABLE_TEAM_ID and KEITHABLE_BUNDLE_ID.
EOF
  exit 1
fi

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

ARCHIVE_PATH="$REPO_ROOT/ios/build/Archives/Petrable.xcarchive"
EXPORT_PATH="$REPO_ROOT/ios/build/ipa"
EXPORT_OPTIONS="$REPO_ROOT/ios/build/ExportOptions.plist"

mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH"

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>$EXPORT_METHOD</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>compileBitcode</key>
  <false/>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
</dict>
</plist>
PLIST

echo "Archiving Petrable for device..."
xcodebuild \
  -project Forge.xcodeproj \
  -scheme Forge \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_STYLE=Automatic \
  archive

echo "Exporting IPA..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

echo "IPA output:"
find "$EXPORT_PATH" -maxdepth 1 -name '*.ipa' -print
