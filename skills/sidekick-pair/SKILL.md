# Codex Sidekick Pairing

Use this skill when the user wants to pair the Codex Sidekick iPhone app with
their current machine, especially over Tailscale.

## Workflow

1. Confirm that `codex` and `tailscale` are installed on the host.
   Prefer `/Applications/Codex.app/Contents/Resources/codex` when available.
2. Run `scripts/pair-over-tailscale.sh`.
3. Summarize the returned pairing information for the user:
   - discovery URL
   - pairing code expiry
   - pairing URL
   - that the host is Tailscale-backed
   - token file location
   - both LaunchAgent labels or plist paths
   - both log file locations
4. When the user wants low-friction phone import, rerun the helper with
   `--qr-file ...` and share the QR image instead of asking them to type the
   discovery URL and code manually.
5. Share the bearer token only when the user truly needs to enter it into the
   phone manually. Prefer reading it from the token file or rerunning the
   helper with `SHOW_TOKEN=1`.
6. If Tailscale is unavailable, say so plainly and offer loopback pairing
   instead.
7. If the helper reports that `codex` does not support `--ws-auth`, tell the
   user to point `CODEX_BIN` at a newer or repo-built Codex binary.
8. If `launchctl bootstrap` fails, tell the user to run the helper from a
   logged-in macOS GUI session that can manage LaunchAgents.
9. If the helper reports a MagicDNS or discovery URL verification failure, do
   not hand out the pairing code. Help the user fix Tailscale DNS integration
   on the host first.
10. If the helper specifically points out a Homebrew-only `tailscale` install
    on macOS, tell the user to install or run `Tailscale.app` before retrying.

## Notes

- This plugin does not replace the iPhone app.
- The helper binds `codex app-server` to the host's Tailscale IPv4 address by
  default, loads it as a per-user LaunchAgent, and emits a MagicDNS hostname
  for the phone when available.
- The helper also loads a pairing broker LaunchAgent that serves discovery and
  code redemption on the tailnet.
- The helper validates the advertised `.ts.net` hostname and then verifies the
  actual discovery URL from the host before it issues a claim code.
- The pairing code and QR image carry discovery information plus a short-lived
  claim code. They do not embed the bearer token.
- The iOS sidekick accepts authenticated `ws://` pairing for Tailscale hosts,
  but still requires `wss://` for general remote internet hosts.
