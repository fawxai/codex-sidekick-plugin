# TASTE.md — Evolving Preferences (Codex Sidekick Plugin)

This file captures the product and UX taste for the companion plugin.

---

## Philosophy

### Quiet, Useful, Scriptable
The best plugin experience here is not flashy. It is a clean host-side helper
that produces trustworthy output and gets out of the way.

### Prefer Real Host Truth
If the desktop app runtime is the thing actually in use, design around that
reality. Do not optimize around a stale CLI just because it is in `PATH`.

### Make Trust Boundaries Obvious
The difference between local, tailnet, and generic remote should be explicit in
docs and output. The user should understand what is being exposed and why.

---

## Output Style

- Prefer structured JSON plus a small amount of plain-language guidance.
- Prefer MagicDNS hostnames over raw IPs when available.
- Prefer explicit paths to token and log files.
- Prefer copy-pasteable commands and examples.

---

## What to Avoid

- clever shell tricks that obscure process ownership
- verbose plugin prose that says less than the JSON already does
- hidden fallback behavior
- “one command does everything forever” claims when host shell semantics make
  that unreliable
