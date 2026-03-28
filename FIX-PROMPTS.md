# Security Fix Prompts — codex-sidekick-plugin

Reference: https://github.com/fawxai/codex-sidekick-plugin/issues/1

---

## Prompt: Critical Security Fixes

```
Read ENGINEERING.md and DOCTRINE.md first and follow all rules.

Fix the two critical security issues and high-priority findings in codex-sidekick-plugin.

### Fix 1: TOCTOU Race Condition in Claim Code Redemption (CRITICAL)
File: scripts/sidekick-pairing-broker.py

The broker uses ThreadingHTTPServer but claim_code() performs a non-atomic read-modify-write on pairing-codes.json. Two concurrent /v1/claim requests with the same valid code can both succeed.

Fix: Add a module-level threading.Lock. Acquire it around the entire claim_code() call path (load state → pop code → write state → return token). This must protect the full read-modify-write cycle.

### Fix 2: No Request Body Size Limit (CRITICAL)
File: scripts/sidekick-pairing-broker.py, do_POST method

Content-Length is read directly and used in rfile.read() with no cap. A malicious client can OOM the server.

Fix: Add a MAX_BODY_SIZE = 4096 constant. In do_POST, check body_length > MAX_BODY_SIZE before reading. If exceeded, respond with 413 Payload Too Large and return.

### Fix 3: Enable Request Logging (HIGH)
File: scripts/sidekick-pairing-broker.py

The log_message override suppresses ALL HTTP logging. For a security-sensitive pairing service, this makes incident investigation impossible.

Fix: Replace the no-op log_message with one that logs to stderr. At minimum, log: successful claims (code redeemed, source IP), failed claims (invalid/expired code, source IP), and server start/stop events. Keep it to one line per event. Do NOT log tokens or full request bodies.

### Fix 4: Validate --code-length and --ttl-seconds Bounds (HIGH)
File: scripts/sidekick-pairing-broker.py

Both accept arbitrary integers. --code-length 1 makes codes trivially guessable. --ttl-seconds 999999 creates near-permanent codes.

Fix: After argparse, validate: code_length must be >= 6 and <= 20. ttl_seconds must be >= 30 and <= 3600. Exit with a clear error message if out of bounds.

### Fix 5: Token File Permissions (MEDIUM)
File: scripts/pair-over-tailscale.sh

chmod 600 only runs on new token files. Pre-existing files with bad permissions are not corrected.

Fix: Move `chmod 600 "$TOKEN_FILE"` AFTER the if block so it runs unconditionally.

### Fix 6: Code State File Permissions (MEDIUM)
File: scripts/sidekick-pairing-broker.py, atomic_write_json()

pairing-codes.json inherits process umask (often world-readable).

Fix: After creating the temp file in atomic_write_json, call os.chmod(tmp_path, 0o600) before os.replace(). Also chmod 600 the final path after replace for safety.

### Fix 7: State Directory Permissions (MEDIUM)
File: scripts/pair-over-tailscale.sh

STATE_DIR created with default umask.

Fix: After mkdir -p, add: chmod 700 "$STATE_DIR"

### Validation
After all fixes:
- shellcheck scripts/pair-over-tailscale.sh scripts/stop-sidekick-server.sh (if available)
- python3 -m py_compile scripts/sidekick-pairing-broker.py
- Verify the threading.Lock is actually acquired/released correctly (use `with lock:` context manager)
- Read through the diff to confirm no regressions

Commit with message: "security: fix TOCTOU race, add body size limit, enable logging, tighten permissions"
Push to a branch: fix/plugin-security-review
Open a PR against main on fawxai/codex-sidekick-plugin.
```
