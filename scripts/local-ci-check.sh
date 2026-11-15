#!/usr/bin/env bash
# Standalone, read-only policy check for the user's independent local CI farm.
# Never invokes install.sh, uninstall.sh, any updater, or privileged command.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
failed=0

say() { printf '%s\n' "$*"; }
fail() { say "FAIL: $*"; failed=1; }

say "macW1Y static policy check (local/ci-farm only)"
say "WARNING: Upstream installers and auto-repair scripts are NOT approved for execution."

for required in AGENTS.md COMPATIBILITY.md IMPLEMENTATION_PLAN.md; do
  [[ -s "$required" ]] || fail "Missing required policy document: $required"
done

if [[ -d .github/workflows ]] && [[ -n "$(find .github/workflows -type f -print -quit)" ]]; then
  fail "GitHub Actions workflow files exist. Remove them: GitHub CI is prohibited."
else
  say "PASS: No GitHub Actions workflows in .github/workflows"
fi

for script in install.sh uninstall.sh apply_plymouth.sh; do
  if [[ -f "$script" ]]; then
    if bash -n "$script"; then
      say "PASS: Static Bash syntax: $script (NOT executed)"
    else
      fail "Bash syntax error: $script"
    fi
  fi
done

if command -v python3 >/dev/null 2>&1; then
  if python3 - <<'PY'
import json
from pathlib import Path

files = sorted(Path("extensions").glob("*/metadata.json"))
for file in files:
    with file.open(encoding="utf-8") as stream:
        data = json.load(stream)
    if not isinstance(data, dict) or not data.get("uuid"):
        raise ValueError(f"{file}: metadata object or uuid missing")
print(f"PASS: Parsed {len(files)} GNOME extension metadata files (not runtime-tested)")
PY
  then
    :
  else
    fail "GNOME extension metadata validation failed"
  fi
else
  say "SKIP: python3 unavailable (no metadata validation)"
fi

if (( failed )); then
  say "FAIL: Static policy checks failed. Do not deploy."
  exit 1
fi

say "PASS: Preliminary static checks only; not an installer, security audit or deployment approval."
