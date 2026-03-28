---
name: sidekick-pair
description: Prepare or inspect Codex Sidekick iPhone pairing targets on the current Mac over Tailscale. Use for private-overlay pairing, claim-code generation, and QR export; do not use it for generic remote hosting or public-internet exposure.
---

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
6. If Tailscale is unavailable, say so plainly and explain that this plugin
   does not provide a public-internet or loopback iPhone pairing fallback.
7. If the helper reports that `codex` does not support `--ws-auth`, tell the
   user to point `CODEX_BIN` at a newer or repo-built Codex binary.
8. If `launchctl bootstrap` fails, tell the user to run the helper from a
   logged-in macOS GUI session that can manage LaunchAgents.
9. If the helper reports that MagicDNS is unavailable locally but falls back to
   a Tailscale IP, reassure the user that this is still the preferred Tailscale
   path and share the IP-based discovery target it emits.
10. If the helper specifically points out a Homebrew-only `tailscale` install
    on macOS, tell the user to install or run `Tailscale.app` before retrying.

## Notes

- This plugin does not replace the iPhone app.
- The helper binds `codex app-server` to the host's Tailscale IPv4 address by
  default, loads it as a per-user LaunchAgent, and emits a MagicDNS hostname
  for the phone when available.
- The helper also loads a pairing broker LaunchAgent that serves discovery and
  code redemption on the tailnet.
- The helper prefers a `.ts.net` hostname when the Mac can resolve it, falls
  back to the Tailscale IP when local MagicDNS is unavailable, and then
  verifies the actual discovery URL from the host before it issues a claim
  code.
- The pairing code and QR image carry discovery information plus a short-lived
  claim code. They do not embed the bearer token.
- The iOS sidekick accepts authenticated `ws://` pairing for Tailscale hosts,
  but still requires `wss://` for general remote internet hosts. This plugin
  does not configure that general remote path.
