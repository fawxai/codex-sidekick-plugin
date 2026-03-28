#!/bin/zsh

set -euo pipefail

SHOW_TOKEN="${SHOW_TOKEN:-0}"
QR_FILE="${QR_FILE:-}"
SCRIPT_DIR="${0:A:h}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --show-token)
      SHOW_TOKEN=1
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
PAIR_PORT="${PAIR_PORT:-4231}"
STATE_DIR="${STATE_DIR:-$HOME/.codex-sidekick}"
TOKEN_FILE="${TOKEN_FILE:-$STATE_DIR/tailscale-token.txt}"
CODE_FILE="${CODE_FILE:-$STATE_DIR/pairing-codes.json}"
LOG_DIR="${LOG_DIR:-$STATE_DIR/logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/app-server.log}"
PAIRING_LOG_FILE="${PAIRING_LOG_FILE:-$LOG_DIR/pairing-broker.log}"
LAUNCH_AGENTS_DIR="${LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
SERVICE_LABEL="${SERVICE_LABEL:-com.fawxai.codex-sidekick.app-server}"
PAIRING_SERVICE_LABEL="${PAIRING_SERVICE_LABEL:-com.fawxai.codex-sidekick.pairing-broker}"
PLIST_FILE="${PLIST_FILE:-$LAUNCH_AGENTS_DIR/$SERVICE_LABEL.plist}"
PAIRING_PLIST_FILE="${PAIRING_PLIST_FILE:-$LAUNCH_AGENTS_DIR/$PAIRING_SERVICE_LABEL.plist}"
CODE_TTL_SECONDS="${CODE_TTL_SECONDS:-300}"
CODE_LENGTH="${CODE_LENGTH:-8}"
APP_BUNDLED_CODEX="/Applications/Codex.app/Contents/Resources/codex"
if [[ -z "${CODEX_BIN:-}" ]]; then
  if [[ -x "$APP_BUNDLED_CODEX" ]]; then
    CODEX_BIN="$APP_BUNDLED_CODEX"
  else
    CODEX_BIN="$(command -v codex || true)"
  fi
fi
TAILSCALE_BIN="${TAILSCALE_BIN:-$(command -v tailscale || true)}"
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || true)}"

mkdir -p "$STATE_DIR" "$LOG_DIR" "$LAUNCH_AGENTS_DIR"

if [[ -z "$CODEX_BIN" ]]; then
  echo "codex binary not found in PATH" >&2
  exit 1
fi

if [[ -z "$TAILSCALE_BIN" ]]; then
  echo "tailscale binary not found in PATH" >&2
  exit 1
fi

if [[ -z "$PYTHON_BIN" ]]; then
  echo "python3 is required for the pairing broker" >&2
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
BROKER_LISTEN_HOST="${BROKER_LISTEN_HOST:-$TAILSCALE_IPV4}"
if [[ -z "${PAIR_HOST:-}" ]]; then
  if [[ -z "$TAILSCALE_DNS_NAME" ]]; then
    echo "tailscale MagicDNS name not available; discovery-first pairing requires a .ts.net host name" >&2
    exit 1
  fi
  PAIR_HOST="$TAILSCALE_DNS_NAME"
fi
HOST_LABEL="${HOST_LABEL:-${TAILSCALE_DNS_NAME:-$PAIR_HOST}}"

print_macos_tailscale_dns_hint() {
  if [[ "$TAILSCALE_BIN" == /opt/homebrew/* || "$TAILSCALE_BIN" == /usr/local/* ]]; then
    if [[ ! -d "/Applications/Tailscale.app" ]]; then
      echo "This Mac appears to have the Homebrew tailscale CLI but not /Applications/Tailscale.app." >&2
      echo "On macOS, install or run the Tailscale app so the system resolver can answer .ts.net names." >&2
    fi
  fi
}

if [[ "$PAIR_HOST" == *.ts.net ]]; then
  if ! "$PYTHON_BIN" - <<'PY' "$PAIR_HOST" >/dev/null
import socket
import sys

host = sys.argv[1]
try:
    addresses = sorted({info[4][0] for info in socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)})
except socket.gaierror:
    raise SystemExit(1)
if not addresses:
    raise SystemExit(1)
PY
  then
    echo "tailscale MagicDNS appears enabled, but this machine cannot resolve $PAIR_HOST" >&2
    echo "Fix MagicDNS/system DNS integration before using discovery-first Tailscale pairing." >&2
    echo "On macOS, verify that the Tailscale client with DNS integration is installed and that Tailscale DNS is enabled." >&2
    print_macos_tailscale_dns_hint
    echo "The helper will not emit a broken discovery URL." >&2
    exit 1
  fi
fi

LISTEN_URL="ws://$LISTEN_HOST:$PORT"
PAIRING_URL="ws://$PAIR_HOST:$PORT"
DISCOVERY_URL="http://$PAIR_HOST:$PAIR_PORT/v1/discover"
CLAIM_URL="http://$PAIR_HOST:$PAIR_PORT/v1/claim"

if [[ ! -s "$TOKEN_FILE" ]]; then
  python3 - <<'PY' > "$TOKEN_FILE"
import secrets
print(secrets.token_urlsafe(32))
PY
  chmod 600 "$TOKEN_FILE"
fi

TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE")"

write_app_server_plist() {
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

write_pairing_plist() {
  python3 - <<'PY' "$PAIRING_PLIST_FILE" "$PAIRING_SERVICE_LABEL" "$PYTHON_BIN" "$SCRIPT_DIR/sidekick-pairing-broker.py" "$BROKER_LISTEN_HOST" "$PAIR_PORT" "$STATE_DIR" "$TOKEN_FILE" "$DISCOVERY_URL" "$CLAIM_URL" "$PAIRING_URL" "$CODE_TTL_SECONDS" "$CODE_LENGTH" "$HOST_LABEL" "$PAIRING_LOG_FILE"
import plistlib
import sys

(
    plist_file,
    service_label,
    python_bin,
    script_path,
    listen_host,
    port,
    state_dir,
    token_file,
    discovery_url,
    claim_url,
    websocket_url,
    ttl_seconds,
    code_length,
    host_label,
    log_file,
) = sys.argv[1:]
payload = {
    "Label": service_label,
    "ProgramArguments": [
        python_bin,
        script_path,
        "serve",
        "--listen-host",
        listen_host,
        "--port",
        port,
        "--state-dir",
        state_dir,
        "--token-file",
        token_file,
        "--discovery-url",
        discovery_url,
        "--claim-url",
        claim_url,
        "--websocket-url",
        websocket_url,
        "--ttl-seconds",
        ttl_seconds,
        "--code-length",
        code_length,
        "--host-label",
        host_label,
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
pairing_service_target="gui/$UID/$PAIRING_SERVICE_LABEL"

write_app_server_plist
write_pairing_plist

launchctl bootout "gui/$UID" "$PLIST_FILE" >/dev/null 2>&1 || true
launchctl bootout "gui/$UID" "$PAIRING_PLIST_FILE" >/dev/null 2>&1 || true

if ! launchctl bootstrap "gui/$UID" "$PLIST_FILE"; then
  echo "launchctl bootstrap failed for $PLIST_FILE" >&2
  echo "Run this helper from a logged-in macOS GUI session that can manage LaunchAgents." >&2
  exit 1
fi

if ! launchctl bootstrap "gui/$UID" "$PAIRING_PLIST_FILE"; then
  echo "launchctl bootstrap failed for $PAIRING_PLIST_FILE" >&2
  echo "Run this helper from a logged-in macOS GUI session that can manage LaunchAgents." >&2
  exit 1
fi

launchctl kickstart -k "$service_target" >/dev/null 2>&1 || true
launchctl kickstart -k "$pairing_service_target" >/dev/null 2>&1 || true

wait_for_ready() {
  local url="$1"
  local description="$2"
  local log_file="$3"

  for _ in 1 2 3 4 5 6 7 8; do
    sleep 1
    if command -v curl >/dev/null 2>&1; then
      if curl --silent --fail "$url" >/dev/null 2>&1; then
        return 0
      fi
    fi
  done

  echo "$description did not become ready. Inspect: $log_file" >&2
  tail -n 20 "$log_file" >&2 || true
  exit 1
}

wait_for_ready "http://$LISTEN_HOST:$PORT/readyz" "codex app-server" "$LOG_FILE"
wait_for_ready "http://$BROKER_LISTEN_HOST:$PAIR_PORT/readyz" "pairing broker" "$PAIRING_LOG_FILE"

verify_advertised_discovery_url() {
  local url="$1"

  for _ in 1 2 3; do
    if curl --silent --show-error --fail --max-time 3 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "The advertised discovery URL is not reachable from this Mac: $url" >&2
  echo "Fix Tailscale DNS/routing before handing this pairing target to your phone." >&2
  print_macos_tailscale_dns_hint
  exit 1
}

verify_advertised_discovery_url "$DISCOVERY_URL"

CODE_PAYLOAD="$("$PYTHON_BIN" "$SCRIPT_DIR/sidekick-pairing-broker.py" issue-code --state-dir "$STATE_DIR" --ttl-seconds "$CODE_TTL_SECONDS" --code-length "$CODE_LENGTH")"
PAIRING_CODE="$(
  python3 -c 'import json,sys; payload=json.load(sys.stdin); print(payload["code"])' <<<"$CODE_PAYLOAD"
)"
PAIRING_CODE_EXPIRES_AT="$(
  python3 -c 'import json,sys; payload=json.load(sys.stdin); print(payload["expiresAt"])' <<<"$CODE_PAYLOAD"
)"
PAIRING_LINK="$(
  python3 - <<'PY' "$DISCOVERY_URL" "$PAIRING_CODE"
import sys
import urllib.parse

discovery_url, pairing_code = sys.argv[1:]
query = urllib.parse.urlencode({"discovery": discovery_url, "code": pairing_code})
print(f"codexsidekick://pair?{query}")
PY
)"

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

SERVICE_PID="$(
  launchctl print "$service_target" 2>/dev/null | awk '/\bpid = / { print $3; exit }'
)"
PAIRING_PID="$(
  launchctl print "$pairing_service_target" 2>/dev/null | awk '/\bpid = / { print $3; exit }'
)"

python3 - <<'PY' "$PAIRING_URL" "$LISTEN_URL" "$DISCOVERY_URL" "$CLAIM_URL" "$PAIRING_CODE" "$PAIRING_CODE_EXPIRES_AT" "$CODE_FILE" "$TOKEN" "$TOKEN_FILE" "$SERVICE_PID" "$PAIRING_PID" "$LOG_FILE" "$PAIRING_LOG_FILE" "$SERVICE_LABEL" "$PAIRING_SERVICE_LABEL" "$PLIST_FILE" "$PAIRING_PLIST_FILE" "$SHOW_TOKEN" "$PAIRING_LINK" "$QR_FILE"
import json
import sys

(
    pairing_url,
    listen_url,
    discovery_url,
    claim_url,
    pairing_code,
    pairing_code_expires_at,
    code_file,
    token,
    token_file,
    service_pid,
    pairing_pid,
    log_file,
    pairing_log_file,
    service_label,
    pairing_service_label,
    plist_file,
    pairing_plist_file,
    show_token,
    pairing_link,
    qr_file,
) = sys.argv[1:]

payload = {
    "status": "started",
    "pairingUrl": pairing_url,
    "listenUrl": listen_url,
    "discoveryUrl": discovery_url,
    "claimUrl": claim_url,
    "pairingCode": pairing_code,
    "pairingCodeExpiresAt": int(pairing_code_expires_at),
    "pairingCodeFile": code_file,
    "tokenFile": token_file,
    "serviceLabel": service_label,
    "pairingServiceLabel": pairing_service_label,
    "plistFile": plist_file,
    "pairingPlistFile": pairing_plist_file,
    "logFile": log_file,
    "pairingLogFile": pairing_log_file,
}

if service_pid:
    payload["pid"] = int(service_pid)

if pairing_pid:
    payload["pairingPid"] = int(pairing_pid)

if show_token == "1":
    payload["token"] = token
else:
    payload["tokenPreview"] = f"{token[:4]}...{token[-4:]}" if len(token) >= 8 else "<redacted>"
    payload["tokenRedacted"] = True

payload["pairingLink"] = pairing_link

if qr_file:
    payload["pairingQRCodeFile"] = qr_file

print(json.dumps(payload, indent=2))
PY
