# ENGINEERING.md — Immutable Doctrine (Codex Sidekick Plugin)

Effective 2026-03-28. These are the implementation rules for this repository.

For evolving judgment and UX preference, see `TASTE.md`.

---

## 0. Core Principles

### YAGNI
This plugin exists to make pairing and host setup easier. It should not become
a sprawling Codex automation toolbox.

### DRY
Pairing logic, runtime selection, and JSON output shape must each have one
obvious home.

### Fail Fast and Loudly
If Tailscale is missing, the Codex runtime is too old, auth flags are absent,
or the listener never binds, exit with a clear error.

### Fix Root Causes, Not Symptoms
If host launch is unreliable, fix process ownership or lifecycle. Do not mask it
with retry spam or vague “started” messages.

### Every Dependency Is a Liability
Prefer shell, system tools, and tiny local scripts. New dependencies need real
justification.

---

## 1. Repository Structure

```text
.codex-plugin/   ← plugin manifest
skills/          ← plugin-facing workflows
scripts/         ← host-side helpers
examples/        ← local marketplace examples
```

Rules:

- No generic `utils` bucket.
- Scripts must have a single job and obvious inputs/outputs.
- Example files must be truthful and runnable, not aspirational.

---

## 2. Script Quality

- Use safe shell settings.
- Check required binaries explicitly.
- Prefer structured source data such as `tailscale status --json` over brittle
  text scraping.
- Emit deterministic JSON for outputs other tools may consume.
- Keep state paths explicit.
- Surface log file locations whenever long-lived background behavior is involved.

---

## 3. Plugin Truthfulness

- The manifest, skill text, and README must match runtime reality.
- Do not advertise secure remote pairing unless the launched path is actually
  authenticated.
- Do not claim install flows that are not tested.
- Caveats about shell environments or background process lifetime must be
  documented plainly.

---

## 4. Security Rules

- Never silently fall back from authenticated remote pairing to insecure remote
  pairing.
- Never emit secrets into logs unless the user explicitly asked for them.
- Prefer the Codex desktop app runtime when it is the authoritative environment.
- Remote pairing is private-overlay-first, not public-internet-first.

---

## 5. Verification

- Validate plugin and example JSON before completion.
- Run the helper script when touching launch logic.
- When process lifetime is involved, verify both startup and shutdown behavior as
  far as the host environment allows.
