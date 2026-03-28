# AGENTS.md — Codex Sidekick Plugin

This repository is the desktop-side companion plugin for the native iPhone
sidekick. It prepares host-side pairing, especially over Tailscale. It is not
the mobile app and not a fork of Codex.

Read these files in order before making changes:

1. `ENGINEERING.md`
2. `DOCTRINE.md`
3. `TASTE.md`

## Scope

- Codex plugin manifest and packaging
- Skills that help desktop Codex pair with the phone
- Host-side helper scripts
- Local marketplace examples

## Translation from Fawx doctrine

The Fawx ideas that transfer cleanly here are:

- root-cause fixes
- small focused tools
- fail-fast behavior
- zero-trust networking
- shell/peripheral thinking

The Rust-kernel-specific parts do not transfer directly. This repo is a plugin
and script surface, so the translation should preserve intent rather than copy
engine mechanics.

## Working rules

- Prefer the bundled Codex desktop runtime when it provides the needed surface.
- Never silently weaken pairing security.
- Keep plugin output machine-readable and human-readable.
- Document shell-environment caveats honestly when they affect long-lived
  processes.
