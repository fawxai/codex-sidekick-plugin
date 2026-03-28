#!/bin/zsh

set -euo pipefail

STATE_DIR="${STATE_DIR:-$HOME/.codex-sidekick}"
PID_FILE="${PID_FILE:-$STATE_DIR/app-server.pid}"

if [[ ! -f "$PID_FILE" ]]; then
  echo "No sidekick app-server pid file found at $PID_FILE" >&2
  exit 1
fi

APP_SERVER_PID="$(tr -d '\r\n' < "$PID_FILE")"

if [[ -z "$APP_SERVER_PID" ]]; then
  echo "PID file is empty: $PID_FILE" >&2
  exit 1
fi

if kill -0 "$APP_SERVER_PID" 2>/dev/null; then
  kill "$APP_SERVER_PID"
  echo "Stopped sidekick app-server pid $APP_SERVER_PID"
else
  echo "Process $APP_SERVER_PID is not running"
fi

rm -f "$PID_FILE"
