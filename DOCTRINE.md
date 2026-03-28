# DOCTRINE.md — Runtime Invariants (Codex Sidekick Plugin)

Effective 2026-03-28. This file defines what the plugin is allowed to do and
what it must never do.

---

## 0. Identity

- This repo is a companion integration layer.
- It prepares pairing targets for the native iPhone app.
- It does not replace the mobile app.
- It does not become a public server product.

---

## 1. Security Posture

- No public-web listener flow as the default.
- Private overlay networking such as Tailscale is the intended remote path.
- Remote pairing must be authenticated.
- If the chosen Codex runtime cannot provide websocket auth, the plugin fails
  rather than downgrading the security posture.

---

## 2. Runtime Authority

- The active Codex desktop runtime is authoritative for host-side behavior.
- Prefer `/Applications/Codex.app/Contents/Resources/codex` when available.
- The plugin should adapt to the real host runtime rather than pretending the
  Homebrew CLI is canonical.

---

## 3. Product Boundaries

- The plugin configures pairing and host setup only.
- It does not reimplement app-server protocol logic.
- It does not become a generic remote process manager.
- It does not introduce public integration surfaces or port-forwarding defaults.

---

## 4. Invariants Summary

These must stay true:

1. Private-overlay pairing is preferred.
2. Remote pairing is authenticated.
3. Insecure downgrade is forbidden.
4. Plugin docs match runtime behavior.
5. The plugin remains small, focused, and companion-oriented.
