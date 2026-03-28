#!/usr/bin/env python3

from __future__ import annotations

import argparse
from collections.abc import Callable, Iterator
import fcntl
import json
import os
import secrets
import sys
import threading
import time
from contextlib import contextmanager
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
MAX_BODY_SIZE = 4096
MIN_CODE_LENGTH = 6
MAX_CODE_LENGTH = 20
MIN_TTL_SECONDS = 30
MAX_TTL_SECONDS = 3600
FILE_MODE_OWNER_ONLY = 0o600

CODE_STATE_LOCK = threading.Lock()


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


@contextmanager
def code_state_file_lock(path: Path) -> Iterator[None]:
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_suffix(path.suffix + ".lock")
    with lock_path.open("a", encoding="utf-8") as handle:
        os.chmod(lock_path, FILE_MODE_OWNER_ONLY)
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = path.with_suffix(path.suffix + ".tmp")
    with temporary_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.chmod(temporary_path, FILE_MODE_OWNER_ONLY)
    os.replace(temporary_path, path)
    os.chmod(path, FILE_MODE_OWNER_ONLY)


def log_event(event: str, **fields: Any) -> None:
    payload = {
        "event": event,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        **fields,
    }
    sys.stderr.write(json.dumps(payload, sort_keys=True) + "\n")
    sys.stderr.flush()


def read_token(token_file: Path) -> str:
    token = token_file.read_text(encoding="utf-8").strip()
    if not token:
        raise RuntimeError(f"token file is empty: {token_file}")
    return token


def update_code_state(
    *,
    code_file: Path,
    mutator: Callable[[dict[str, Any], int], dict[str, Any] | None],
) -> dict[str, Any] | None:
    with CODE_STATE_LOCK:
        with code_state_file_lock(code_file):
            payload = load_code_state(code_file)
            now = int(time.time())
            prune_expired_codes(payload, now)
            result = mutator(payload, now)
            atomic_write_json(code_file, payload)
            return result


def issue_code(
    *,
    code_file: Path,
    ttl_seconds: int,
    code_length: int,
) -> dict[str, Any]:
    def assign_code(payload: dict[str, Any], now: int) -> dict[str, Any]:
        codes = payload.setdefault("codes", {})

        code = ""
        while not code or code in codes:
            code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(code_length))

        expires_at = now + ttl_seconds
        codes[code] = {
            "createdAt": now,
            "expiresAt": expires_at,
        }
        return {
            "code": code,
            "createdAt": now,
            "expiresAt": expires_at,
            "ttlSeconds": ttl_seconds,
            "length": code_length,
            "alphabet": CODE_ALPHABET,
        }

    payload = update_code_state(code_file=code_file, mutator=assign_code)
    if payload is None:
        raise RuntimeError("issue_code mutator must return a payload")
    return payload


def claim_code(*, code_file: Path, submitted_code: str) -> dict[str, Any] | None:
    normalized = normalize_code(submitted_code)
    return update_code_state(
        code_file=code_file,
        mutator=lambda payload, _now: payload.setdefault("codes", {}).pop(normalized, None),
    )


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


def validate_pairing_bounds(parser: argparse.ArgumentParser, ttl_seconds: int, code_length: int) -> None:
    if not MIN_CODE_LENGTH <= code_length <= MAX_CODE_LENGTH:
        parser.error(f"--code-length must be between {MIN_CODE_LENGTH} and {MAX_CODE_LENGTH}.")

    if not MIN_TTL_SECONDS <= ttl_seconds <= MAX_TTL_SECONDS:
        parser.error(f"--ttl-seconds must be between {MIN_TTL_SECONDS} and {MAX_TTL_SECONDS}.")


def main() -> int:
    parser = create_parser()
    args = parser.parse_args()
    validate_pairing_bounds(parser, args.ttl_seconds, args.code_length)
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

            if body_length < 0:
                self.send_error(HTTPStatus.BAD_REQUEST)
                return

            if body_length > MAX_BODY_SIZE:
                self.send_json(
                    {"error": f"Request body must be {MAX_BODY_SIZE} bytes or smaller."},
                    status=HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                )
                self.log_message(
                    "event=payload_too_large client_ip=%s content_length=%s limit=%s",
                    self.client_ip(),
                    body_length,
                    MAX_BODY_SIZE,
                )
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
            normalized_code = normalize_code(code)

            try:
                auth_token = read_token(token_file)
            except RuntimeError as error:
                log_event(
                    "claim_internal_error",
                    clientIP=self.client_ip(),
                    code=normalized_code,
                    reason="token_unavailable",
                )
                self.send_json(
                    {"error": str(error)},
                    status=HTTPStatus.INTERNAL_SERVER_ERROR,
                )
                return

            claim = claim_code(code_file=code_file, submitted_code=code)
            if claim is None:
                log_event(
                    "claim_failed",
                    clientIP=self.client_ip(),
                    code=normalized_code,
                    reason="invalid_or_expired",
                )
                self.send_json(
                    {"error": "That pairing code is invalid or expired."},
                    status=HTTPStatus.NOT_FOUND,
                )
                return

            log_event(
                "claim_success",
                clientIP=self.client_ip(),
                code=normalized_code,
            )

            self.send_json(
                {
                    "version": 1,
                    "hostLabel": host_label,
                    "websocketURL": args.websocket_url,
                    "authToken": auth_token,
                }
            )

        def log_message(self, format: str, *args: Any) -> None:
            log_event("http", clientIP=self.client_ip(), message=format % args)

        def client_ip(self) -> str:
            return self.client_address[0]

        def send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
            encoded = json.dumps(payload, indent=2).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

    server = ThreadingHTTPServer((args.listen_host, args.port), Handler)
    stop_reason = "shutdown"
    log_event(
        "server_start",
        listenHost=args.listen_host,
        port=args.port,
        stateDir=str(state_dir),
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        stop_reason = "keyboard_interrupt"
    except Exception:
        stop_reason = "error"
        raise
    finally:
        server.server_close()
        log_event(
            "server_stop",
            listenHost=args.listen_host,
            port=args.port,
            reason=stop_reason,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
