#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import secrets
import sys
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"


def normalize_code(raw_value: str) -> str:
    return "".join(character for character in raw_value.upper() if character in CODE_ALPHABET)


def load_code_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"version": 1, "codes": {}}

    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)

    if not isinstance(payload, dict):
        return {"version": 1, "codes": {}}

    codes = payload.get("codes")
    if not isinstance(codes, dict):
        payload["codes"] = {}

    payload.setdefault("version", 1)
    return payload


def prune_expired_codes(payload: dict[str, Any], now: int) -> None:
    codes = payload.setdefault("codes", {})
    stale = [
        code
        for code, details in codes.items()
        if not isinstance(details, dict) or int(details.get("expiresAt", 0)) <= now
    ]
    for code in stale:
        codes.pop(code, None)


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = path.with_suffix(path.suffix + ".tmp")
    with temporary_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(temporary_path, path)


def read_token(token_file: Path) -> str:
    token = token_file.read_text(encoding="utf-8").strip()
    if not token:
        raise RuntimeError(f"token file is empty: {token_file}")
    return token


def issue_code(
    *,
    code_file: Path,
    ttl_seconds: int,
    code_length: int,
) -> dict[str, Any]:
    payload = load_code_state(code_file)
    now = int(time.time())
    prune_expired_codes(payload, now)
    codes = payload.setdefault("codes", {})

    code = ""
    while not code or code in codes:
        code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(code_length))

    expires_at = now + ttl_seconds
    codes[code] = {
        "createdAt": now,
        "expiresAt": expires_at,
    }
    atomic_write_json(code_file, payload)
    return {
        "code": code,
        "createdAt": now,
        "expiresAt": expires_at,
        "ttlSeconds": ttl_seconds,
        "length": code_length,
        "alphabet": CODE_ALPHABET,
    }


def claim_code(*, code_file: Path, submitted_code: str) -> dict[str, Any] | None:
    payload = load_code_state(code_file)
    now = int(time.time())
    prune_expired_codes(payload, now)
    codes = payload.setdefault("codes", {})
    normalized = normalize_code(submitted_code)
    entry = codes.pop(normalized, None)
    atomic_write_json(code_file, payload)
    if entry is None:
        return None
    return entry


def formatted_host_label(discovery_url: str, websocket_url: str, explicit_label: str | None) -> str:
    if explicit_label:
        return explicit_label

    for candidate in (discovery_url, websocket_url):
        parsed = urlparse(candidate)
        if parsed.hostname:
            return parsed.hostname

    return "Codex Host"


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Codex Sidekick pairing broker")
    subparsers = parser.add_subparsers(dest="command", required=True)

    issue_parser = subparsers.add_parser("issue-code", help="Issue a short-lived pairing code")
    issue_parser.add_argument("--state-dir", required=True)
    issue_parser.add_argument("--ttl-seconds", type=int, default=300)
    issue_parser.add_argument("--code-length", type=int, default=8)

    serve_parser = subparsers.add_parser("serve", help="Serve discovery and claim endpoints")
    serve_parser.add_argument("--listen-host", required=True)
    serve_parser.add_argument("--port", type=int, default=4231)
    serve_parser.add_argument("--state-dir", required=True)
    serve_parser.add_argument("--token-file", required=True)
    serve_parser.add_argument("--discovery-url", required=True)
    serve_parser.add_argument("--claim-url", required=True)
    serve_parser.add_argument("--websocket-url", required=True)
    serve_parser.add_argument("--ttl-seconds", type=int, default=300)
    serve_parser.add_argument("--code-length", type=int, default=8)
    serve_parser.add_argument("--host-label")
    return parser


def main() -> int:
    parser = create_parser()
    args = parser.parse_args()
    state_dir = Path(args.state_dir).expanduser()
    code_file = state_dir / "pairing-codes.json"

    if args.command == "issue-code":
        payload = issue_code(
            code_file=code_file,
            ttl_seconds=args.ttl_seconds,
            code_length=args.code_length,
        )
        print(json.dumps(payload, indent=2))
        return 0

    token_file = Path(args.token_file).expanduser()
    host_label = formatted_host_label(args.discovery_url, args.websocket_url, args.host_label)

    class Handler(BaseHTTPRequestHandler):
        server_version = "CodexSidekickPairingBroker/1.0"

        def do_GET(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            if parsed.path == "/readyz":
                self.send_json({"status": "ok"})
                return

            if parsed.path == "/v1/discover":
                self.send_json(
                    {
                        "version": 1,
                        "hostLabel": host_label,
                        "discoveryURL": args.discovery_url,
                        "claimURL": args.claim_url,
                        "websocketURL": args.websocket_url,
                        "connectionKind": "tailnet",
                        "pairingCode": {
                            "format": "alphanumeric",
                            "length": args.code_length,
                            "alphabet": CODE_ALPHABET,
                            "ttlSeconds": args.ttl_seconds,
                        },
                    }
                )
                return

            self.send_error(HTTPStatus.NOT_FOUND)

        def do_POST(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            if parsed.path != "/v1/claim":
                self.send_error(HTTPStatus.NOT_FOUND)
                return

            try:
                body_length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                self.send_error(HTTPStatus.BAD_REQUEST)
                return

            raw_body = self.rfile.read(body_length)
            try:
                payload = json.loads(raw_body or b"{}")
            except json.JSONDecodeError:
                self.send_json(
                    {"error": "Request body must be valid JSON."},
                    status=HTTPStatus.BAD_REQUEST,
                )
                return

            code = str(payload.get("code", ""))
            claim = claim_code(code_file=code_file, submitted_code=code)
            if claim is None:
                self.send_json(
                    {"error": "That pairing code is invalid or expired."},
                    status=HTTPStatus.NOT_FOUND,
                )
                return

            try:
                auth_token = read_token(token_file)
            except RuntimeError as error:
                self.send_json(
                    {"error": str(error)},
                    status=HTTPStatus.INTERNAL_SERVER_ERROR,
                )
                return

            self.send_json(
                {
                    "version": 1,
                    "hostLabel": host_label,
                    "websocketURL": args.websocket_url,
                    "authToken": auth_token,
                }
            )

        def log_message(self, format: str, *args: Any) -> None:
            return

        def send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
            encoded = json.dumps(payload, indent=2).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

    server = ThreadingHTTPServer((args.listen_host, args.port), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        return 0
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
