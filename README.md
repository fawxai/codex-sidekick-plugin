# Codex Sidekick Plugin

`codex-sidekick-plugin` is the desktop-side companion to the native
`CodexSidekick` iPhone app. It is meant to live in its own public repository
and helps Codex set up a pairing target without forking or mirroring the full
Codex codebase.

## Current scope

- Prepare a `codex app-server` listener for the iPhone sidekick
- Prefer Tailscale host discovery for real-phone pairing
- Generate or reuse a bearer token for authenticated websocket pairing
- Print a ready-to-use pairing payload for the phone UI

## Binary compatibility

Authenticated Tailscale pairing depends on a Codex build that exposes websocket
auth flags such as `--ws-auth` and `--ws-token-file`.

The helper script prefers the bundled desktop-app binary at
`/Applications/Codex.app/Contents/Resources/codex` when it exists, then falls
back to `codex` from `PATH`.

It also checks for those auth flags before launch. If the selected binary is
older and does not support them yet, point `CODEX_BIN` at a newer or repo-built
Codex binary before running the helper.

## Why this stays separate from the app

The iPhone app is a standalone native client. This plugin is only the desktop
companion that helps the host machine expose and describe a safe pairing target.

## Local structure

- `.codex-plugin/plugin.json`: plugin manifest
- `skills/sidekick-pair/SKILL.md`: the pairing workflow Codex should follow
- `scripts/pair-over-tailscale.sh`: host-side helper that starts
  `codex app-server` for the phone
- `scripts/stop-sidekick-server.sh`: stop the helper-managed websocket server
- `examples/marketplace.json`: local marketplace entry example

## Local install shape

One reasonable local setup is:

1. Clone this repo to `~/.agents/plugins/plugins/codex-sidekick-plugin`
2. Copy `examples/marketplace.json` to `~/.agents/plugins/marketplace.json`
   and merge it with any existing local plugin entries
3. Let Codex discover the plugin from that local marketplace

The example marketplace entry uses the standard local plugin path
`./plugins/codex-sidekick-plugin` relative to `~/.agents/plugins/marketplace.json`.

## Runtime caveat

The helper is designed for a normal host shell session. Some command runners
reap detached child processes when the launching command finishes. If you hit
that behavior inside a plugin-hosted shell environment, run the helper from a
real terminal session or move the long-lived launcher into a future native
desktop integration.

## Helper output

The pairing helper emits a small JSON payload with:

- `pairingUrl`
- `listenUrl`
- `token`
- `tokenFile`
- `pid`
- `logFile`

That output is designed so a future plugin UX can surface a QR code or copy
action without changing the underlying host setup.
