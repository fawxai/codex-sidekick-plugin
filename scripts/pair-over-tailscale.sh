#!/bin/zsh

set -euo pipefail

SHOW_TOKEN="${SHOW_TOKEN:-0}"
SHOW_PAIRING_CODE="${SHOW_PAIRING_CODE:-0}"
QR_FILE="${QR_FILE:-}"
SCRIPT_DIR="${0:A:h}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --show-token)
      SHOW_TOKEN=1
      ;;
    --show-pairing-code)
      SHOW_PAIRING_CODE=1
      ;;
    --qr-file)
      if [[ $# -lt 2 ]]; then
        echo "--qr-file requires an output path" >&2
        exit 1
      fi
      QR_FILE="$2"
      shift
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

PORT="${PORT:-4222}"
STATE_DIR="${STATE_DIR:-$HOME/.codex-sidekick}"
TOKEN_FILE="${TOKEN_FILE:-$STATE_DIR/tailscale-token.txt}"
LOG_DIR="${LOG_DIR:-$STATE_DIR/logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/app-server.log}"
LAUNCH_AGENTS_DIR="${LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
SERVICE_LABEL="${SERVICE_LABEL:-com.fawxai.codex-sidekick.app-server}"
PLIST_FILE="${PLIST_FILE:-$LAUNCH_AGENTS_DIR/$SERVICE_LABEL.plist}"
APP_BUNDLED_CODEX="/Applications/Codex.app/Contents/Resources/codex"
if [[ -z "${CODEX_BIN:-}" ]]; then
  if [[ -x "$APP_BUNDLED_CODEX" ]]; then
    CODEX_BIN="$APP_BUNDLED_CODEX"
  else
    CODEX_BIN="$(command -v codex || true)"
  fi
fi
TAILSCALE_BIN="${TAILSCALE_BIN:-$(command -v tailscale || true)}"

mkdir -p "$STATE_DIR" "$LOG_DIR" "$LAUNCH_AGENTS_DIR"

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
PAIRING_ARTIFACT="$(
  python3 - <<'PY' "$PAIRING_URL" "$TOKEN"
import base64
import json
import sys
import urllib.parse

pairing_url, token = sys.argv[1:]
payload = {
    "version": 1,
    "websocketURL": pairing_url,
    "authToken": token,
}
encoded = base64.urlsafe_b64encode(
    json.dumps(payload, separators=(",", ":")).encode()
).decode().rstrip("=")
pairing_code = f"codex-sidekick:v1:{encoded}"
pairing_link = "codexsidekick://pair?code=" + urllib.parse.quote(pairing_code, safe="")
print(pairing_code)
print(pairing_link)
PY
)"
PAIRING_CODE="$(printf '%s\n' "$PAIRING_ARTIFACT" | sed -n '1p')"
PAIRING_LINK="$(printf '%s\n' "$PAIRING_ARTIFACT" | sed -n '2p')"

if [[ -n "$QR_FILE" ]]; then
  if command -v xcrun >/dev/null 2>&1; then
    xcrun swift "$SCRIPT_DIR/render-pairing-qr.swift" "$PAIRING_LINK" "$QR_FILE"
  elif command -v swift >/dev/null 2>&1; then
    swift "$SCRIPT_DIR/render-pairing-qr.swift" "$PAIRING_LINK" "$QR_FILE"
  else
    echo "swift is required to render a pairing QR image" >&2
    exit 1
  fi
fi

write_plist() {
  python3 - <<'PY' "$PLIST_FILE" "$SERVICE_LABEL" "$CODEX_BIN" "$LISTEN_URL" "$TOKEN_FILE" "$STATE_DIR" "$LOG_FILE"
import plistlib
import sys

plist_file, service_label, codex_bin, listen_url, token_file, state_dir, log_file = sys.argv[1:]
payload = {
    "Label": service_label,
    "ProgramArguments": [
        codex_bin,
        "app-server",
        "--listen",
        listen_url,
        "--ws-auth",
        "capability-token",
        "--ws-token-file",
        token_file,
    ],
    "RunAtLoad": True,
    "KeepAlive": True,
    "WorkingDirectory": state_dir,
    "StandardOutPath": log_file,
    "StandardErrorPath": log_file,
    "ProcessType": "Background",
}

with open(plist_file, "wb") as handle:
    plistlib.dump(payload, handle, sort_keys=False)
PY
}

service_target="gui/$UID/$SERVICE_LABEL"

write_plist
launchctl bootout "gui/$UID" "$PLIST_FILE" >/dev/null 2>&1 || true
if ! launchctl bootstrap "gui/$UID" "$PLIST_FILE"; then
  echo "launchctl bootstrap failed for $PLIST_FILE" >&2
  echo "Run this helper from a logged-in macOS GUI session that can manage LaunchAgents." >&2
  exit 1
fi
launchctl kickstart -k "$service_target" >/dev/null 2>&1 || true

LISTEN_READY=0

for _ in 1 2 3 4 5 6 7 8; do
  sleep 1

  if command -v curl >/dev/null 2>&1; then
    if curl --silent --fail "http://$LISTEN_HOST:$PORT/readyz" >/dev/null 2>&1; then
      LISTEN_READY=1
      break
    fi
  elif command -v lsof >/dev/null 2>&1; then
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

SERVICE_PID="$(
  launchctl print "$service_target" 2>/dev/null | awk '/\bpid = / { print $3; exit }'
)"

python3 - <<'PY' "$PAIRING_URL" "$LISTEN_URL" "$TOKEN" "$TOKEN_FILE" "$SERVICE_PID" "$LOG_FILE" "$SERVICE_LABEL" "$PLIST_FILE" "$SHOW_TOKEN" "$SHOW_PAIRING_CODE" "$PAIRING_CODE" "$PAIRING_LINK" "$QR_FILE"
import json
import sys

(
    pairing_url,
    listen_url,
    token,
    token_file,
    pid,
    log_file,
    service_label,
    plist_file,
    show_token,
    show_pairing_code,
    pairing_code,
    pairing_link,
    qr_file,
) = sys.argv[1:]
payload = {
    "status": "started",
    "pairingUrl": pairing_url,
    "listenUrl": listen_url,
    "tokenFile": token_file,
    "serviceLabel": service_label,
    "plistFile": plist_file,
    "logFile": log_file,
}

if pid:
    payload["pid"] = int(pid)

if show_token == "1":
    payload["token"] = token
else:
    payload["tokenPreview"] = f"{token[:4]}...{token[-4:]}" if len(token) >= 8 else "<redacted>"
    payload["tokenRedacted"] = True

if show_pairing_code == "1":
    payload["pairingCode"] = pairing_code
    payload["pairingLink"] = pairing_link

if qr_file:
    payload["pairingQRCodeFile"] = qr_file

print(json.dumps(payload, indent=2))
PY
