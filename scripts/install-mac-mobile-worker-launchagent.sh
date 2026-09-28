#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
label="com.keithable.mac-mobile-worker"
plist="$HOME/Library/LaunchAgents/${label}.plist"
logs_dir="$repo_root/ios/build/mac-mobile-worker"
launch_logs_dir="$HOME/Library/Logs/Keithable"
worker_out_root="$HOME/Library/Application Support/Keithable/mac-mobile-worker-builds"
runner="$HOME/Library/Application Support/Keithable/mac-mobile-worker-runner.sh"
worker_copy="$HOME/Library/Application Support/Keithable/mac-mobile-worker.py"
env_copy="$HOME/Library/Application Support/Keithable/keithable-env.sh"

mkdir -p "$HOME/Library/LaunchAgents" "$logs_dir" "$launch_logs_dir" "$worker_out_root" "$(dirname "$runner")"

if [[ -f "$plist" ]]; then
  backup="$logs_dir/${label}.$(date +%Y%m%d_%H%M%S).plist.backup"
  cp "$plist" "$backup"
  echo "Backed up existing LaunchAgent to $backup"
fi

cat > "$runner" <<RUNNER
#!/bin/zsh
set -e
cd "$repo_root"
export KEITHABLE_REPO_ROOT="$repo_root"
export KEITHABLE_ENV_SCRIPT="$env_copy"
export KEITHABLE_WORKER_OUT_ROOT="$worker_out_root"
exec /usr/bin/python3 "$worker_copy" --loop
RUNNER
chmod +x "$runner"
cp "$repo_root/scripts/mac-mobile-worker.py" "$worker_copy"
cp "$repo_root/scripts/keithable-env.sh" "$env_copy"
chmod +x "$worker_copy"
chmod +x "$env_copy"

cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>${runner}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${HOME}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>KEITHABLE_WORKER_ID</key>
    <string>keith-local-mac</string>
    <key>KEITHABLE_WORKER_INTERVAL</key>
    <string>30</string>
    <key>PATH</key>
    <string>${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${launch_logs_dir}/worker.out.log</string>
  <key>StandardErrorPath</key>
  <string>${launch_logs_dir}/worker.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$plist"
launchctl kickstart -k "gui/$(id -u)/${label}"

echo "$label installed and started"
echo "$plist"
