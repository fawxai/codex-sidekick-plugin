#!/bin/zsh

set -euo pipefail

PORT="${PORT:-4222}"
STATE_DIR="${STATE_DIR:-$HOME/.codex-sidekick}"
TOKEN_FILE="${TOKEN_FILE:-$STATE_DIR/tailscale-token.txt}"
PID_FILE="${PID_FILE:-$STATE_DIR/app-server.pid}"
LOG_DIR="${LOG_DIR:-$STATE_DIR/logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/app-server.log}"
APP_BUNDLED_CODEX="/Applications/Codex.app/Contents/Resources/codex"
if [[ -z "${CODEX_BIN:-}" ]]; then
  if [[ -x "$APP_BUNDLED_CODEX" ]]; then
    CODEX_BIN="$APP_BUNDLED_CODEX"
  else
    CODEX_BIN="$(command -v codex || true)"
  fi
fi
TAILSCALE_BIN="${TAILSCALE_BIN:-$(command -v tailscale || true)}"

mkdir -p "$STATE_DIR" "$LOG_DIR"

if [[ -z "$CODEX_BIN" ]]; then
  echo "codex binary not found in PATH" >&2
  exit 1
fi

if [[ -z "$TAILSCALE_BIN" ]]; then
  echo "tailscale binary not found in PATH" >&2
  exit 1
fi

APP_SERVER_HELP="$("$CODEX_BIN" app-server --help 2>&1 || true)"
if [[ "$APP_SERVER_HELP" != *"--ws-auth"* ]]; then
  echo "The selected codex binary does not expose --ws-auth: $CODEX_BIN" >&2
  echo "Point CODEX_BIN at a newer or repo-built Codex binary with websocket auth support." >&2
  exit 1
fi

TAILSCALE_STATUS="$("$TAILSCALE_BIN" status --json)"
TAILSCALE_DNS_NAME="$(
  python3 -c 'import json,sys; status=json.load(sys.stdin); self=status.get("Self") or {}; print((self.get("DNSName") or "").rstrip("."))' \
    <<<"$TAILSCALE_STATUS"
)"
TAILSCALE_IPV4="$("$TAILSCALE_BIN" ip -4 | head -n 1 | tr -d '\n')"

if [[ -z "$TAILSCALE_IPV4" ]]; then
  echo "tailscale is installed but no IPv4 tailnet address is available" >&2
  exit 1
fi

LISTEN_HOST="${LISTEN_HOST:-$TAILSCALE_IPV4}"
PAIR_HOST="${PAIR_HOST:-${TAILSCALE_DNS_NAME:-$TAILSCALE_IPV4}}"
LISTEN_URL="ws://$LISTEN_HOST:$PORT"
PAIRING_URL="ws://$PAIR_HOST:$PORT"

if [[ ! -s "$TOKEN_FILE" ]]; then
  python3 - <<'PY' > "$TOKEN_FILE"
import secrets
print(secrets.token_urlsafe(32))
PY
  chmod 600 "$TOKEN_FILE"
fi

TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE")"

if [[ -f "$PID_FILE" ]]; then
  EXISTING_PID="$(tr -d '\r\n' < "$PID_FILE" || true)"
  if [[ -n "$EXISTING_PID" ]] && kill -0 "$EXISTING_PID" 2>/dev/null; then
    python3 - <<'PY' "$PAIRING_URL" "$LISTEN_URL" "$TOKEN" "$TOKEN_FILE" "$EXISTING_PID" "$LOG_FILE"
import json
import sys

pairing_url, listen_url, token, token_file, pid, log_file = sys.argv[1:]
print(json.dumps({
    "status": "already-running",
    "pairingUrl": pairing_url,
    "listenUrl": listen_url,
    "token": token,
    "tokenFile": token_file,
    "pid": int(pid),
    "logFile": log_file,
}, indent=2))
PY
    exit 0
  fi
fi

nohup sh -c 'tail -f /dev/null | "$1" app-server --listen "$2" --ws-auth capability-token --ws-token-file "$3"' \
  sh "$CODEX_BIN" "$LISTEN_URL" "$TOKEN_FILE" \
  >"$LOG_FILE" 2>&1 &

APP_SERVER_PID="$!"
disown %+ 2>/dev/null || true
LISTEN_READY=0

for _ in 1 2 3 4 5; do
  sleep 1

  if ! kill -0 "$APP_SERVER_PID" 2>/dev/null; then
    echo "codex app-server exited during startup. Inspect: $LOG_FILE" >&2
    tail -n 20 "$LOG_FILE" >&2 || true
    exit 1
  fi

  if command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
      LISTEN_READY=1
      break
    fi
  else
    LISTEN_READY=1
    break
  fi
done

if [[ "$LISTEN_READY" -ne 1 ]]; then
  echo "codex app-server did not begin listening on port $PORT. Inspect: $LOG_FILE" >&2
  tail -n 20 "$LOG_FILE" >&2 || true
  exit 1
fi

echo "$APP_SERVER_PID" > "$PID_FILE"

python3 - <<'PY' "$PAIRING_URL" "$LISTEN_URL" "$TOKEN" "$TOKEN_FILE" "$APP_SERVER_PID" "$LOG_FILE"
import json
import sys

pairing_url, listen_url, token, token_file, pid, log_file = sys.argv[1:]
print(json.dumps({
    "status": "started",
    "pairingUrl": pairing_url,
    "listenUrl": listen_url,
    "token": token,
    "tokenFile": token_file,
    "pid": int(pid),
    "logFile": log_file,
}, indent=2))
PY
