# Codex Sidekick Plugin

`codex-sidekick-plugin` is the desktop-side companion to the native
`CodexSidekick` iPhone app. It is meant to live in its own public repository
and helps Codex set up a pairing target without forking or mirroring the full
Codex codebase.

## Current scope

- Prepare a launchd-managed `codex app-server` listener for the iPhone sidekick
- Serve a discovery document for real-phone pairing over Tailscale
- Generate or reuse a bearer token for authenticated websocket pairing
- Issue short-lived 8-character claim codes
- Optionally export a QR image that carries the discovery URL plus claim code
- Validate the plugin manifest and required skill metadata before release

## Binary compatibility

Authenticated Tailscale pairing depends on a Codex build that exposes websocket
auth flags such as `--ws-auth` and `--ws-token-file`.

The helper script prefers the bundled desktop-app binary at
`/Applications/Codex.app/Contents/Resources/codex` when it exists, then falls
back to `codex` from `PATH`.

It also checks for those auth flags before launch. If the selected binary is
older and does not support them yet, point `CODEX_BIN` at a newer or repo-built
Codex binary before running the helper.

The helper prefers the node's `.ts.net` hostname for discovery when the Mac can
actually resolve it. If local MagicDNS resolution is unavailable, the helper
falls back to the machine's Tailscale IP so discovery-first pairing still works
over the tailnet. It then verifies that the exact discovery URL is reachable
from the host before it issues a claim code.

On macOS, the helper also points out the common case where the machine appears
to have only the Homebrew `tailscale` CLI and not `Tailscale.app`, since that
often means the system resolver is not handling `.ts.net` hostnames.

## Why this stays separate from the app

The iPhone app is a standalone native client. This plugin is only the desktop
companion that helps the host machine expose and describe a safe pairing target.
It intentionally does not configure public-internet pairing or a loopback-only
iPhone fallback.

## Local structure

- `.codex-plugin/plugin.json`: plugin manifest
- `skills/sidekick-pair/SKILL.md`: the pairing workflow Codex should follow
- `scripts/pair-over-tailscale.sh`: host-side helper that writes and loads a
  LaunchAgent for `codex app-server`
- `scripts/stop-sidekick-server.sh`: unload and remove the helper-managed
  LaunchAgent
- `scripts/validate-plugin.sh`: validate manifest JSON and required skill
  metadata
- `examples/marketplace.json`: local marketplace entry example

## Local install shape

One reasonable personal setup is:

1. Copy or clone this repo to `~/.codex/plugins/codex-sidekick-plugin`
2. Copy `examples/marketplace.json` to `~/.agents/plugins/marketplace.json`
   and merge it with any existing local plugin entries
3. Restart Codex and let it discover the plugin from that local marketplace

The example marketplace entry uses the personal plugin path
`./.codex/plugins/codex-sidekick-plugin`.

That `source.path` is resolved from the personal marketplace root `~`, not from
the `~/.agents/plugins/` folder that stores `marketplace.json`.

If you maintain a separate repo-scoped marketplace, keep the plugin under that
repo root, often at `./plugins/codex-sidekick-plugin`, and point the repo
marketplace entry there.

This path format follows the current Codex plugin contract as of March 2026. If
your installed Codex version changes marketplace path resolution behavior,
verify the expected structure against that version's plugin docs.

## Using it from Codex

After Codex has discovered the plugin and the Sidekick iPhone app is installed
and open, tell Codex to prepare pairing for this Mac.

Example prompts:

- `Prepare Codex Sidekick pairing over Tailscale and give me a pairing code.`
- `Start a Codex app-server for my iPhone sidekick and show me the discovery URL.`
- `Prepare Codex Sidekick pairing over Tailscale and export a QR code for my phone.`

That flow should cause Codex to run the helper, start the LaunchAgents, and
return the current discovery target plus a short-lived pairing code.

## Runtime caveat

The helper uses per-user macOS LaunchAgents. Run it from a logged-in desktop
session that has access to `launchctl bootstrap gui/$UID`. Headless shells and
some CI-style sessions may not have permission to install LaunchAgents.

The launch helper scripts use `zsh` and assume a macOS shell environment. Run
`scripts/pair-over-tailscale.sh` and `scripts/stop-sidekick-server.sh` with the
system `zsh` rather than `bash`. The validator script is shell-portable and can
run under `bash`.

## Helper output

The pairing helper emits a small JSON payload with:

- `pairingUrl`
- `listenUrl`
- `discoveryUrl`
- `claimUrl`
- `pairingCode`
- `pairingCodeExpiresAt`
- `tokenFile`
- `serviceLabel`
- `pairingServiceLabel`
- `plistFile`
- `pairingPlistFile`
- `pid` when available from `launchctl`
- `pairingPid` when available from `launchctl`
- `logFile`
- `pairingLogFile`
- `tokenPreview` by default

That output is designed so a future plugin UX can surface the correct discovery
URL and claim step without changing the underlying host setup.

Use `SHOW_TOKEN=1 scripts/pair-over-tailscale.sh` or
`scripts/pair-over-tailscale.sh --show-token` only when you explicitly need the
full bearer token in stdout.

Use `QR_FILE=~/.codex-sidekick/pairing-qr.png scripts/pair-over-tailscale.sh`
or `scripts/pair-over-tailscale.sh --qr-file ~/.codex-sidekick/pairing-qr.png`
to render a QR PNG that the iPhone app can open directly.

The helper's QR/deep link contains only the discovery URL plus the short-lived
claim code. It does not embed the bearer token.

## Validation

Run `scripts/validate-plugin.sh` after changing the manifest, marketplace
example, or skill metadata. It checks that the JSON files parse and that every
bundled `SKILL.md` includes the required `name` and `description` frontmatter.
