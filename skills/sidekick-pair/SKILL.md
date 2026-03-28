# Codex Sidekick Pairing

Use this skill when the user wants to pair the Codex Sidekick iPhone app with
their current machine, especially over Tailscale.

## Workflow

1. Confirm that `codex` and `tailscale` are installed on the host.
   Prefer `/Applications/Codex.app/Contents/Resources/codex` when available.
2. Run `scripts/pair-over-tailscale.sh`.
3. Summarize the returned pairing information for the user:
   - pairing URL
   - whether it is loopback or Tailscale
   - token file location
   - LaunchAgent label or plist path
   - log file location
4. When the user wants low-friction phone import, rerun the helper with
   `SHOW_PAIRING_CODE=1` or `--qr-file ...` and share the pairing code or QR
   image instead of asking them to type the token manually.
5. Share the bearer token only when the user truly needs to enter it into the
   phone manually. Prefer reading it from the token file or rerunning the
   helper with `SHOW_TOKEN=1`.
6. If Tailscale is unavailable, say so plainly and offer loopback pairing
   instead.
7. If the helper reports that `codex` does not support `--ws-auth`, tell the
   user to point `CODEX_BIN` at a newer or repo-built Codex binary.
8. If `launchctl bootstrap` fails, tell the user to run the helper from a
   logged-in macOS GUI session that can manage LaunchAgents.

## Notes

- This plugin does not replace the iPhone app.
- The helper binds `codex app-server` to the host's Tailscale IPv4 address by
  default, loads it as a per-user LaunchAgent, and emits a MagicDNS hostname
  for the phone when available.
- The pairing code and QR image both carry the existing websocket URL plus
  bearer token. They do not introduce a separate backend protocol.
- The iOS sidekick accepts authenticated `ws://` pairing for Tailscale hosts,
  but still requires `wss://` for general remote internet hosts.
