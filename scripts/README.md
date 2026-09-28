# Petrable Automation

These scripts automate the local setup path used for this workspace.

```bash
scripts/backend-deploy.sh
scripts/ios-run-simulator.sh
scripts/smoke-web-build.sh "a tiny hello world page with one big blue button"
scripts/package-unsigned-ipa.sh
```

`backend-deploy.sh` installs backend dependencies if needed and pushes Convex functions.

`ios-run-simulator.sh` writes the ignored `ios/Sources/AppConfig.swift` from `backend/.env.local`, regenerates the Xcode project, builds, installs, and launches the app in the iPhone simulator. Pass a simulator name as the first argument if needed.

`smoke-web-build.sh` creates a small web build through Convex and polls until it is live or fails.

`archive-ipa.sh` creates a signed device archive and exports an `.ipa` when you provide your Apple signing team:

```bash
KEITHABLE_TEAM_ID=ABCDE12345 \
KEITHABLE_BUNDLE_ID=com.yourcompany.keithable \
KEITHABLE_EXPORT_METHOD=development \
scripts/archive-ipa.sh
```

Environment overrides:

```bash
KEITHABLE_USER_NAME=Keith scripts/ios-run-simulator.sh "iPhone 17"
KEITHABLE_MODEL=free-balanced scripts/smoke-web-build.sh "build a notes app"
```

`package-unsigned-ipa.sh` builds a device `.ipa` without local signing, intended for third-party signing services that accept custom IPA uploads:

```bash
KEITHABLE_BUNDLE_ID=com.keithfleishman.keithable scripts/package-unsigned-ipa.sh
```
