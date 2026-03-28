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
   - log file location
4. Share the bearer token only when the user needs to enter it into the phone.
5. If Tailscale is unavailable, say so plainly and offer loopback pairing
   instead.
6. If the helper reports that `codex` does not support `--ws-auth`, tell the
   user to point `CODEX_BIN` at a newer or repo-built Codex binary.
7. If the host shell reaps detached children after the command completes, tell
   the user to run the helper from a real terminal session instead of a
   short-lived shell tool.

## Notes

- This plugin does not replace the iPhone app.
- The helper binds `codex app-server` to the host's Tailscale IPv4 address by
  default and emits a MagicDNS hostname for the phone when available.
- The iOS sidekick accepts authenticated `ws://` pairing for Tailscale hosts,
  but still requires `wss://` for general remote internet hosts.
