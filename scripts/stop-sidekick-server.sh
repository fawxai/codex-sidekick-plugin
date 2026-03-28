#!/bin/zsh

set -euo pipefail

LAUNCH_AGENTS_DIR="${LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
SERVICE_LABEL="${SERVICE_LABEL:-com.fawxai.codex-sidekick.app-server}"
PLIST_FILE="${PLIST_FILE:-$LAUNCH_AGENTS_DIR/$SERVICE_LABEL.plist}"

if [[ -f "$PLIST_FILE" ]]; then
  launchctl bootout "gui/$UID" "$PLIST_FILE" >/dev/null 2>&1 || true
  rm -f "$PLIST_FILE"
  echo "Stopped sidekick app-server service $SERVICE_LABEL"
else
  launchctl bootout "gui/$UID/$SERVICE_LABEL" >/dev/null 2>&1 || true
  echo "Service $SERVICE_LABEL was not installed via plist file"
fi
