#!/bin/zsh

set -euo pipefail

LAUNCH_AGENTS_DIR="${LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
SERVICE_LABEL="${SERVICE_LABEL:-com.fawxai.codex-sidekick.app-server}"
PAIRING_SERVICE_LABEL="${PAIRING_SERVICE_LABEL:-com.fawxai.codex-sidekick.pairing-broker}"
PLIST_FILE="${PLIST_FILE:-$LAUNCH_AGENTS_DIR/$SERVICE_LABEL.plist}"
PAIRING_PLIST_FILE="${PAIRING_PLIST_FILE:-$LAUNCH_AGENTS_DIR/$PAIRING_SERVICE_LABEL.plist}"

stop_service() {
  local service_label="$1"
  local plist_file="$2"

  if [[ -f "$plist_file" ]]; then
    launchctl bootout "gui/$UID" "$plist_file" >/dev/null 2>&1 || true
    rm -f "$plist_file"
    echo "Stopped service $service_label"
    return
  fi

  launchctl bootout "gui/$UID/$service_label" >/dev/null 2>&1 || true
  echo "Service $service_label was not installed via plist file"
}

stop_service "$SERVICE_LABEL" "$PLIST_FILE"
stop_service "$PAIRING_SERVICE_LABEL" "$PAIRING_PLIST_FILE"
