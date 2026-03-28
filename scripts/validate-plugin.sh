#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"

python3 - <<'PY' "$REPO_ROOT"
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def plugin_path(root: Path, relative_path: str) -> Path:
    assert relative_path.startswith("./")
    return root / relative_path.removeprefix("./")


def load_json(path: Path) -> object:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def parse_frontmatter(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    match = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not match:
        raise ValueError("missing YAML frontmatter")

    fields: dict[str, str] = {}
    for raw_line in match.group(1).splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        fields[key.strip()] = value.strip()
    return fields


root = Path(sys.argv[1]).resolve()
errors: list[str] = []

manifest_path = root / ".codex-plugin" / "plugin.json"
marketplace_path = root / "examples" / "marketplace.json"

try:
    manifest = load_json(manifest_path)
except Exception as exc:  # pragma: no cover - script entrypoint
    errors.append(f"{manifest_path}: invalid JSON ({exc})")
    manifest = None

if manifest is not None:
    if not isinstance(manifest, dict):
        errors.append(f"{manifest_path}: manifest must be a JSON object")
    else:
        for key in ("name", "version", "description"):
            if not isinstance(manifest.get(key), str) or not manifest[key].strip():
                errors.append(f"{manifest_path}: missing required string field '{key}'")

        for key in ("skills", "mcpServers", "apps"):
            if key not in manifest:
                continue
            value = manifest[key]
            if not isinstance(value, str) or not value.startswith("./"):
                errors.append(f"{manifest_path}: '{key}' must be a './'-prefixed relative path")
                continue

            target = plugin_path(root, value)
            if not target.exists():
                errors.append(f"{manifest_path}: '{key}' points to a missing path: {value}")

try:
    marketplace = load_json(marketplace_path)
except Exception as exc:  # pragma: no cover - script entrypoint
    errors.append(f"{marketplace_path}: invalid JSON ({exc})")
    marketplace = None

if marketplace is not None and not isinstance(marketplace, dict):
    errors.append(f"{marketplace_path}: marketplace example must be a JSON object")
elif isinstance(marketplace, dict):
    plugins = marketplace.get("plugins")
    if not isinstance(plugins, list) or not plugins:
        errors.append(f"{marketplace_path}: marketplace example must include a non-empty 'plugins' array")
    else:
        for index, plugin in enumerate(plugins):
            if not isinstance(plugin, dict):
                errors.append(f"{marketplace_path}: plugins[{index}] must be an object")
                continue

            source = plugin.get("source")
            if not isinstance(source, dict):
                errors.append(f"{marketplace_path}: plugins[{index}].source must be an object")
            else:
                source_path = source.get("path")
                if not isinstance(source_path, str) or not source_path.startswith("./"):
                    errors.append(
                        f"{marketplace_path}: plugins[{index}].source.path must be a './'-prefixed relative path"
                    )
                elif ".." in Path(source_path).parts:
                    errors.append(
                        f"{marketplace_path}: plugins[{index}].source.path must stay inside the marketplace root"
                    )

            policy = plugin.get("policy")
            if not isinstance(policy, dict):
                errors.append(f"{marketplace_path}: plugins[{index}].policy must be an object")
            else:
                for field in ("installation", "authentication"):
                    value = policy.get(field)
                    if not isinstance(value, str) or not value.strip():
                        errors.append(
                            f"{marketplace_path}: plugins[{index}].policy.{field} must be a non-empty string"
                        )

            category = plugin.get("category")
            if not isinstance(category, str) or not category.strip():
                errors.append(f"{marketplace_path}: plugins[{index}].category must be a non-empty string")

skill_files = sorted((root / "skills").glob("*/SKILL.md"))
if not skill_files:
    errors.append(f"{root / 'skills'}: expected at least one bundled skill")

for skill_path in skill_files:
    try:
        frontmatter = parse_frontmatter(skill_path)
    except ValueError as exc:
        errors.append(f"{skill_path}: {exc}")
        continue

    for field in ("name", "description"):
        value = frontmatter.get(field, "")
        if not value:
            errors.append(f"{skill_path}: missing required frontmatter field '{field}'")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)

print("Plugin validation passed.")
PY
