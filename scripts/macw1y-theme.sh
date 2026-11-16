#!/usr/bin/env bash
# User-scoped cosmetic asset adapter for macW1Y-GTK-Theme (Work Package 1).
# Operates strictly under $HOME; never modifies /usr, /etc, fonts/, or wallpapers/,
# and never invokes install.sh, uninstall.sh, apply_plymouth.sh, or sudo.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$HOME/.local/state/macw1y-theme"
MANIFEST_FILE="$STATE_DIR/manifest.json"
BACKUP_ROOT="$STATE_DIR/backup"
MARKER_NAME=".macw1y-managed"

say() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  macw1y-theme.sh apply --gtk-variant=<dark|dark-solid|light|light-solid> \
                        --icon-variant=<mactahoe|mactahoe-dark|mactahoe-light> \
                        [--execute]
  macw1y-theme.sh restore
  macw1y-theme.sh status

Subcommands:
  apply     Preview (default dry-run) or install (--execute) user-scoped GTK and icon themes.
  restore   Restore previous gsettings values and remove/restore backed-up assets from manifest.
  status    Show current gsettings theme keys and last applied macw1y-theme manifest.
EOF
}

resolve_gtk_dir() {
  case "$1" in
    dark)        printf '%s' "macW1Y-Dark" ;;
    dark-solid)  printf '%s' "macW1Y-Dark-solid" ;;
    light)       printf '%s' "macW1Y-Light" ;;
    light-solid) printf '%s' "macW1Y-Light-solid" ;;
    *) fail "Invalid --gtk-variant: '$1' (expected: dark, dark-solid, light, light-solid)" ;;
  esac
}

resolve_icon_dir() {
  case "$1" in
    mactahoe)       printf '%s' "MacTahoe" ;;
    mactahoe-dark)  printf '%s' "MacTahoe-dark" ;;
    mactahoe-light) printf '%s' "MacTahoe-light" ;;
    *) fail "Invalid --icon-variant: '$1' (expected: mactahoe, mactahoe-dark, mactahoe-light)" ;;
  esac
}

has_gsettings() {
  command -v gsettings >/dev/null 2>&1 && \
    gsettings get org.gnome.desktop.interface gtk-theme >/dev/null 2>&1
}

get_gsetting() {
  local key="$1"
  local raw val
  raw="$(gsettings get org.gnome.desktop.interface "$key")"
  val="${raw#\'}"
  val="${val%\'}"
  printf '%s' "$val"
}

make_timestamp() {
  date -u +%Y%m%dT%H%M%SZ
}

# Rollback state for partial-failure recovery during apply --execute
_APPLY_COMMITTED=1
_CREATED_GTK_DST=""
_CREATED_ICON_DST=""
_CREATED_BACKUP_DIR=""

cleanup_failed_apply() {
  if (( _APPLY_COMMITTED == 1 )); then
    return 0
  fi
  warn "Apply failed mid-operation; rolling back partial changes..."
  if [[ -n "$_CREATED_GTK_DST" && -e "$_CREATED_GTK_DST" ]]; then
    rm -rf -- "$_CREATED_GTK_DST" || true
  fi
  if [[ -n "$_CREATED_ICON_DST" && -e "$_CREATED_ICON_DST" ]]; then
    rm -rf -- "$_CREATED_ICON_DST" || true
  fi
  if [[ -n "$_CREATED_BACKUP_DIR" && -d "$_CREATED_BACKUP_DIR" ]]; then
    rm -rf -- "$_CREATED_BACKUP_DIR" || true
  fi
}

trap cleanup_failed_apply EXIT

cmd_apply() {
  local gtk_variant=""
  local icon_variant=""
  local execute=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --gtk-variant=*)
        gtk_variant="${1#*=}"
        shift
        ;;
      --gtk-variant)
        [[ $# -ge 2 ]] || fail "--gtk-variant requires a value"
        gtk_variant="$2"
        shift 2
        ;;
      --icon-variant=*)
        icon_variant="${1#*=}"
        shift
        ;;
      --icon-variant)
        [[ $# -ge 2 ]] || fail "--icon-variant requires a value"
        icon_variant="$2"
        shift 2
        ;;
      --execute)
        execute=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown option for apply: $1"
        ;;
    esac
  done

  [[ -n "$gtk_variant" ]] || fail "Missing required option: --gtk-variant"
  [[ -n "$icon_variant" ]] || fail "Missing required option: --icon-variant"

  local gtk_dir icon_dir
  gtk_dir="$(resolve_gtk_dir "$gtk_variant")"
  icon_dir="$(resolve_icon_dir "$icon_variant")"

  local gtk_src="$ROOT/$gtk_dir"
  local icon_src="$ROOT/icons/$icon_dir"
  [[ -d "$gtk_src" ]] || fail "Source GTK theme directory not found: $gtk_src"
  [[ -d "$icon_src" ]] || fail "Source icon theme directory not found: $icon_src"

  local gtk_dst="$HOME/.themes/$gtk_dir"
  local icon_dst="$HOME/.icons/$icon_dir"

  local need_gtk_copy=1
  local need_icon_copy=1

  # Collision detection before any writes
  if [[ -e "$gtk_dst" || -L "$gtk_dst" ]]; then
    if [[ -f "$gtk_dst/$MARKER_NAME" ]]; then
      need_gtk_copy=0
    else
      fail "Collision: '$gtk_dst' already exists without '$MARKER_NAME' marker. Refusing to overwrite unrelated user theme."
    fi
  fi

  if [[ -e "$icon_dst" || -L "$icon_dst" ]]; then
    if [[ -f "$icon_dst/$MARKER_NAME" ]]; then
      need_icon_copy=0
    else
      fail "Collision: '$icon_dst' already exists without '$MARKER_NAME' marker. Refusing to overwrite unrelated user icon theme."
    fi
  fi

  if (( need_gtk_copy == 0 || need_icon_copy == 0 )) && [[ ! -f "$MANIFEST_FILE" ]]; then
    local -a orphaned=()
    if (( need_gtk_copy == 0 )); then
      orphaned+=("$gtk_dst")
    fi
    if (( need_icon_copy == 0 )); then
      orphaned+=("$icon_dst")
    fi
    fail "Inconsistent state: managed-looking directory (${orphaned[*]}) exists with '$MARKER_NAME' marker, but tracking manifest '$MANIFEST_FILE' is missing. Resolve manually (remove the stale marker/directory or restore from a known-good manifest) before running apply."
  fi

  local ts
  ts="$(make_timestamp)"
  local backup_dir="$BACKUP_ROOT/$ts"

  if (( execute == 0 )); then
    say "DRY RUN (no changes written; pass --execute to apply)"
    if (( need_gtk_copy == 1 )); then
      say "  Would copy GTK theme:  $gtk_src -> $gtk_dst"
    else
      say "  GTK theme already managed (idempotent skip): $gtk_dst"
    fi
    if (( need_icon_copy == 1 )); then
      say "  Would copy icon theme: $icon_src -> $icon_dst"
    else
      say "  Icon theme already managed (idempotent skip): $icon_dst"
    fi
    if (( need_gtk_copy == 1 || need_icon_copy == 1 )) || [[ ! -f "$MANIFEST_FILE" ]]; then
      say "  Would back up dconf /org/gnome/desktop/interface/ (if available) to: $backup_dir"
      say "  Would write manifest:  $MANIFEST_FILE"
    else
      say "  Would reuse existing manifest and skip redundant backup."
    fi
    say "  Would set gsettings org.gnome.desktop.interface gtk-theme='$gtk_dir' icon-theme='$icon_dir'"
    return 0
  fi

  command -v python3 >/dev/null 2>&1 || fail "python3 is required to write manifest.json"

  # Idempotent re-run when both assets are already managed and manifest exists
  if (( need_gtk_copy == 0 && need_icon_copy == 0 )) && [[ -f "$MANIFEST_FILE" ]]; then
    say "Assets already managed (no-op for copy and backup)."
    if has_gsettings; then
      if gsettings set org.gnome.desktop.interface gtk-theme "$gtk_dir" && \
         gsettings set org.gnome.desktop.interface icon-theme "$icon_dir"; then
        say "Re-applied gsettings: gtk-theme='$gtk_dir', icon-theme='$icon_dir'."
      else
        warn "Failed to re-apply gsettings (gtk-theme='$gtk_dir', icon-theme='$icon_dir')."
      fi
    else
      warn "gsettings/D-Bus unavailable; skipped gsettings re-apply."
    fi
    return 0
  fi

  # Capture previous gsettings before making changes
  local gsettings_ok=0
  local prev_gtk="" prev_icon="" prev_cursor=""
  if has_gsettings; then
    gsettings_ok=1
    prev_gtk="$(get_gsetting gtk-theme)"
    prev_icon="$(get_gsetting icon-theme)"
    prev_cursor="$(get_gsetting cursor-theme)"
  fi

  # Begin transactional filesystem changes
  _APPLY_COMMITTED=0

  # Ensure unique backup dir
  if [[ -e "$backup_dir" ]]; then
    backup_dir="${backup_dir}-$$"
  fi
  mkdir -p -- "$backup_dir"
  _CREATED_BACKUP_DIR="$backup_dir"

  local dconf_backup_file=""
  if (( gsettings_ok == 1 )) && command -v dconf >/dev/null 2>&1; then
    dconf_backup_file="$backup_dir/dconf-interface.ini"
    dconf dump /org/gnome/desktop/interface/ > "$dconf_backup_file"
  fi

  if (( need_gtk_copy == 1 )); then
    mkdir -p -- "$HOME/.themes"
    _CREATED_GTK_DST="$gtk_dst"
    if ! cp -a -- "$gtk_src" "$gtk_dst"; then
      fail "Failed to copy GTK theme to '$gtk_dst'"
    fi
    printf 'macw1y-managed\ntimestamp=%s\nvariant=%s\n' "$ts" "$gtk_variant" > "$gtk_dst/$MARKER_NAME"
    say "Installed GTK theme: $gtk_dst"
  else
    say "GTK theme already managed (skipped copy): $gtk_dst"
  fi

  if (( need_icon_copy == 1 )); then
    mkdir -p -- "$HOME/.icons"
    _CREATED_ICON_DST="$icon_dst"
    if ! cp -a -- "$icon_src" "$icon_dst"; then
      fail "Failed to copy icon theme to '$icon_dst'"
    fi
    printf 'macw1y-managed\ntimestamp=%s\nvariant=%s\n' "$ts" "$icon_variant" > "$icon_dst/$MARKER_NAME"
    say "Installed icon theme: $icon_dst"
  else
    say "Icon theme already managed (skipped copy): $icon_dst"
  fi

  mkdir -p -- "$STATE_DIR"
  local manifest_tmp="$MANIFEST_FILE.tmp.$$"

  MACW1Y_TS="$ts" \
  MACW1Y_GTK_VARIANT="$gtk_variant" \
  MACW1Y_ICON_VARIANT="$icon_variant" \
  MACW1Y_GTK_DST="$gtk_dst" \
  MACW1Y_ICON_DST="$icon_dst" \
  MACW1Y_BACKUP_DIR="$backup_dir" \
  MACW1Y_DCONF_BACKUP="$dconf_backup_file" \
  MACW1Y_GSETTINGS_APPLIED="$gsettings_ok" \
  MACW1Y_PREV_GTK="$prev_gtk" \
  MACW1Y_PREV_ICON="$prev_icon" \
  MACW1Y_PREV_CURSOR="$prev_cursor" \
  MACW1Y_MANIFEST="$MANIFEST_FILE" \
  MACW1Y_MANIFEST_TMP="$manifest_tmp" \
  python3 - <<'PY'
import json
import os
from pathlib import Path

manifest_path = Path(os.environ["MACW1Y_MANIFEST"])
tmp_path = Path(os.environ["MACW1Y_MANIFEST_TMP"])

existing = {}
if manifest_path.is_file():
    existing = json.loads(manifest_path.read_text(encoding="utf-8"))

paths_written = list(existing.get("paths_written", []))
for p in (os.environ["MACW1Y_GTK_DST"], os.environ["MACW1Y_ICON_DST"]):
    if p and p not in paths_written:
        paths_written.append(p)

backup_paths = list(existing.get("backup_paths", []))
dconf_backup = os.environ["MACW1Y_DCONF_BACKUP"]
if dconf_backup and dconf_backup not in backup_paths:
    backup_paths.append(dconf_backup)

this_run_gsettings_ok = os.environ["MACW1Y_GSETTINGS_APPLIED"] == "1"
existing_gsettings_applied = bool(existing.get("gsettings_applied", False))
gsettings_applied = existing_gsettings_applied or this_run_gsettings_ok

prev_gsettings = existing.get("previous_gsettings")
if prev_gsettings is None:
    if this_run_gsettings_ok:
        prev_gsettings = {
            "gtk-theme": os.environ["MACW1Y_PREV_GTK"],
            "icon-theme": os.environ["MACW1Y_PREV_ICON"],
            "cursor-theme": os.environ["MACW1Y_PREV_CURSOR"],
        }
    else:
        prev_gsettings = None

data = {
    "timestamp": os.environ["MACW1Y_TS"],
    "gtk_variant": os.environ["MACW1Y_GTK_VARIANT"],
    "icon_variant": os.environ["MACW1Y_ICON_VARIANT"],
    "paths_written": paths_written,
    "backup_dir": os.environ["MACW1Y_BACKUP_DIR"],
    "backup_paths": backup_paths,
    "gsettings_applied": gsettings_applied,
    "previous_gsettings": prev_gsettings,
}

tmp_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
os.replace(tmp_path, manifest_path)
PY

  _APPLY_COMMITTED=1
  _CREATED_GTK_DST=""
  _CREATED_ICON_DST=""
  _CREATED_BACKUP_DIR=""

  say "Wrote manifest: $MANIFEST_FILE"

  if (( gsettings_ok == 1 )); then
    if gsettings set org.gnome.desktop.interface gtk-theme "$gtk_dir" && \
       gsettings set org.gnome.desktop.interface icon-theme "$icon_dir"; then
      say "Updated gsettings: gtk-theme='$gtk_dir', icon-theme='$icon_dir'"
    else
      warn "Failed to update gsettings (gtk-theme='$gtk_dir', icon-theme='$icon_dir'); filesystem assets and manifest are committed. Re-run apply or run gsettings set manually."
    fi
  else
    warn "gsettings/D-Bus unavailable; filesystem assets installed without gsettings update."
  fi
}

cmd_restore() {
  if [[ $# -gt 0 ]]; then
    case "$1" in
      -h|--help) usage; exit 0 ;;
      *) fail "Unexpected argument for restore: $1" ;;
    esac
  fi

  if [[ ! -f "$MANIFEST_FILE" ]]; then
    say "Nothing was applied (no manifest at $MANIFEST_FILE)."
    return 0
  fi

  command -v python3 >/dev/null 2>&1 || fail "python3 is required to read manifest.json"

  # Read paths_written and gsettings info safely via NUL-delimited python output
  local -a paths_written=()
  while IFS= read -r -d '' p; do
    paths_written+=("$p")
  done < <(
    MACW1Y_MANIFEST="$MANIFEST_FILE" python3 - <<'PY'
import json, os, sys
data = json.loads(open(os.environ["MACW1Y_MANIFEST"], encoding="utf-8").read())
for p in data.get("paths_written", []):
    sys.stdout.buffer.write(p.encode("utf-8") + b"\0")
PY
  )

  local gsettings_applied prev_gtk prev_icon prev_cursor
  {
    IFS= read -r -d '' gsettings_applied
    IFS= read -r -d '' prev_gtk
    IFS= read -r -d '' prev_icon
    IFS= read -r -d '' prev_cursor
  } < <(
    MACW1Y_MANIFEST="$MANIFEST_FILE" python3 - <<'PY'
import json, os, sys
data = json.loads(open(os.environ["MACW1Y_MANIFEST"], encoding="utf-8").read())
applied = "1" if data.get("gsettings_applied") else "0"
prev = data.get("previous_gsettings") or {}
fields = [
    applied,
    prev.get("gtk-theme", ""),
    prev.get("icon-theme", ""),
    prev.get("cursor-theme", ""),
]
for f in fields:
    sys.stdout.buffer.write(f.encode("utf-8") + b"\0")
PY
  )

  local -a pending=()

  if [[ "$gsettings_applied" == "1" ]]; then
    if has_gsettings; then
      local gs_ok=1
      if ! gsettings set org.gnome.desktop.interface gtk-theme "$prev_gtk"; then
        gs_ok=0
      fi
      if ! gsettings set org.gnome.desktop.interface icon-theme "$prev_icon"; then
        gs_ok=0
      fi
      if ! gsettings set org.gnome.desktop.interface cursor-theme "$prev_cursor"; then
        gs_ok=0
      fi
      if (( gs_ok == 1 )); then
        say "Restored gsettings: gtk-theme='$prev_gtk', icon-theme='$prev_icon', cursor-theme='$prev_cursor'"
      else
        warn "Failed to restore one or more gsettings keys."
        pending+=("gsettings (gtk-theme='$prev_gtk', icon-theme='$prev_icon', cursor-theme='$prev_cursor')")
      fi
    else
      warn "gsettings/D-Bus unavailable; could not restore gsettings keys."
      pending+=("gsettings (gtk-theme='$prev_gtk', icon-theme='$prev_icon', cursor-theme='$prev_cursor')")
    fi
  fi

  local p
  if (( ${#paths_written[@]} > 0 )); then
    for p in "${paths_written[@]}"; do
      if [[ -e "$p" || -L "$p" ]]; then
        if [[ -f "$p/$MARKER_NAME" ]]; then
          if rm -rf -- "$p"; then
            say "Removed managed asset: $p"
          else
            warn "Failed to remove managed asset: $p"
            pending+=("remove managed asset: $p")
          fi
        else
          warn "Skipping '$p': missing '$MARKER_NAME' marker (will not delete unmanaged path)."
          pending+=("unmarked path (missing '$MARKER_NAME'): $p")
        fi
      fi
    done
  fi

  if (( ${#pending[@]} > 0 )); then
    local item
    warn "Restore incomplete; leaving manifest intact at '$MANIFEST_FILE'. Pending items:"
    for item in "${pending[@]}"; do
      warn "  - $item"
    done
    fail "Restore did not complete all steps; resolve pending items and re-run restore."
  fi

  rm -f -- "$MANIFEST_FILE"
  say "Removed manifest: $MANIFEST_FILE"
}

cmd_status() {
  if [[ $# -gt 0 ]]; then
    case "$1" in
      -h|--help) usage; exit 0 ;;
      *) fail "Unexpected argument for status: $1" ;;
    esac
  fi

  say "Current gsettings (org.gnome.desktop.interface):"
  if has_gsettings; then
    say "  gtk-theme:    $(get_gsetting gtk-theme)"
    say "  icon-theme:   $(get_gsetting icon-theme)"
    say "  cursor-theme: $(get_gsetting cursor-theme)"
  else
    say "  (gsettings/D-Bus unavailable in this session)"
  fi

  if [[ ! -f "$MANIFEST_FILE" ]]; then
    say "Manifest: none (no macw1y-theme currently applied)."
    return 0
  fi

  command -v python3 >/dev/null 2>&1 || fail "python3 is required to read manifest.json"
  MACW1Y_MANIFEST="$MANIFEST_FILE" python3 - <<'PY'
import json, os
data = json.loads(open(os.environ["MACW1Y_MANIFEST"], encoding="utf-8").read())
print("Manifest:")
print(f"  timestamp:    {data.get('timestamp')}")
print(f"  gtk_variant:  {data.get('gtk_variant')}")
print(f"  icon_variant: {data.get('icon_variant')}")
print(f"  backup_dir:   {data.get('backup_dir')}")
print("  paths_written:")
for p in data.get("paths_written", []):
    print(f"    - {p}")
PY
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi

  local subcmd="$1"
  shift

  case "$subcmd" in
    apply)   cmd_apply "$@" ;;
    restore) cmd_restore "$@" ;;
    status)  cmd_status "$@" ;;
    -h|--help|help) usage; exit 0 ;;
    *) fail "Unknown subcommand: $subcmd (expected: apply, restore, status)" ;;
  esac
}

main "$@"
