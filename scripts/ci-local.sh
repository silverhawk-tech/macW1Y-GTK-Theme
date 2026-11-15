#!/usr/bin/env bash
# Static checks only. Safe to run locally or in the user's self-hosted CI farm.
# Does NOT install the theme, run shell extensions, or require sudo.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "[1/3] Enforcing the no-GitHub-Actions policy"
if [[ -d .github/workflows ]] && find .github/workflows -type f -print -quit | grep -q .; then
  echo "ERROR: .github/workflows contains files. GitHub Actions CI is prohibited in this fork." >&2
  exit 1
fi
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [[ -n "$(git ls-files -- .github/workflows)" ]]; then
    echo "ERROR: tracked GitHub Actions workflows found." >&2
    exit 1
  fi
fi

echo "[2/3] Bash syntax (no execution)"
for script in install.sh uninstall.sh apply_plymouth.sh scripts/ci-local.sh; do
  bash -n "$script"
  echo "  syntax OK: $script"
done

echo "[3/3] Extension manifests and declared GNOME 50 support"
python3 - <<'PY'
import json
from pathlib import Path

root = Path("extensions")
metadata = sorted(root.glob("*/metadata.json"))
if not metadata:
    raise SystemExit("ERROR: no GNOME extension metadata found")
for path in metadata:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data.get("shell-version"), list):
        raise SystemExit(f"ERROR: missing shell-version list: {path}")

critical = (
    "kiwi@kemma",
    "liquid-glass@thinkingcoding1231.gmail.com",
    "dash2dock-motion@unmade.space",
    "cupertino-dock-lite@rinzler69-wastaken.github.com",
    "blur-my-shell@aunetx",
)
for name in critical:
    path = root / name / "metadata.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    if "50" not in [str(v) for v in data["shell-version"]]:
        raise SystemExit(f"ERROR: GNOME 50 not declared: {name}")
print(f"  Validated {len(metadata)} extension manifests and {len(critical)} critical GNOME 50 declarations")
print("  NOTE: metadata does not prove runtime compatibility")

for name in ("config/extensions.lock.json", "config/macw1y-manifest.json"):
    json.loads(Path(name).read_text(encoding="utf-8"))
    print(f"  JSON OK: {name}")
PY

echo "Local static checks passed (NOT a live GNOME integration test)."
