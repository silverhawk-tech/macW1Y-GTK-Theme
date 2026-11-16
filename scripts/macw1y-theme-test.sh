#!/usr/bin/env bash
# Sandbox test harness for scripts/macw1y-theme.sh.
# Every test runs in a fresh throwaway HOME under /tmp and never touches real $HOME or real dconf.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/macw1y-theme.sh"
failed=0

say()  { printf '%s\n' "$*"; }
pass() { say "PASS: $*"; }
skip() { say "SKIP: $*"; }
fail() { say "FAIL: $*"; failed=1; }

[[ -f "$SCRIPT" ]] || { say "FAIL: Missing $SCRIPT"; exit 1; }

declare -a _TMP_DIRS=()

cleanup_all() {
  local d
  if (( ${#_TMP_DIRS[@]} > 0 )); then
    for d in "${_TMP_DIRS[@]}"; do
      if [[ -d "$d" ]]; then
        chmod -R u+rwx -- "$d" 2>/dev/null || true
        rm -rf -- "$d" || true
      fi
    done
  fi
}

trap cleanup_all EXIT

MACW1Y_LAST_TMP_HOME=""

make_temp_home() {
  local prefix="${1:-macw1y-test}"
  MACW1Y_LAST_TMP_HOME="$(mktemp -d "/tmp/${prefix}.XXXXXX")"
  _TMP_DIRS+=("$MACW1Y_LAST_TMP_HOME")
}

# Run macw1y-theme.sh isolated from the real HOME and real D-Bus session.
run_isolated() {
  local fake_home="$1"
  shift
  env -u DBUS_SESSION_BUS_ADDRESS \
    HOME="$fake_home" \
    XDG_CONFIG_HOME="$fake_home/.config" \
    XDG_DATA_HOME="$fake_home/.local/share" \
    XDG_STATE_HOME="$fake_home/.local/state" \
    bash "$SCRIPT" "$@"
}

# Probe whether isolated dbus-run-session + gsettings works in this environment.
HAS_ISOLATED_DBUS=0
if command -v dbus-run-session >/dev/null 2>&1 && command -v gsettings >/dev/null 2>&1; then
  make_temp_home "macw1y-dbus-probe"
  probe_home="$MACW1Y_LAST_TMP_HOME"
  if env -u DBUS_SESSION_BUS_ADDRESS \
    HOME="$probe_home" \
    XDG_CONFIG_HOME="$probe_home/.config" \
    XDG_DATA_HOME="$probe_home/.local/share" \
    dbus-run-session -- gsettings get org.gnome.desktop.interface gtk-theme >/dev/null 2>&1; then
    HAS_ISOLATED_DBUS=1
  fi
fi

say "macW1Y-theme sandbox test suite (isolated HOME, never touches real \$HOME)"

# ---------------------------------------------------------------------------
# Static syntax check first
# ---------------------------------------------------------------------------
if bash -n "$SCRIPT"; then
  pass "Bash syntax check: $SCRIPT"
else
  fail "Bash syntax check failed: $SCRIPT"
fi

# ---------------------------------------------------------------------------
# Test 1: Dry run writes nothing
# ---------------------------------------------------------------------------
make_temp_home "macw1y-t1"
t1_home="$MACW1Y_LAST_TMP_HOME"
if run_isolated "$t1_home" apply --gtk-variant=dark --icon-variant=mactahoe >/dev/null 2>&1; then
  if [[ ! -e "$t1_home/.themes" && ! -e "$t1_home/.icons" && ! -e "$t1_home/.local/state/macw1y-theme" ]]; then
    pass "Test 1: Dry run writes nothing"
  else
    fail "Test 1: Dry run created unexpected files under $t1_home"
  fi
else
  fail "Test 1: Dry run exited non-zero"
fi

# ---------------------------------------------------------------------------
# Test 2: apply --execute then restore round-trips cleanly
# ---------------------------------------------------------------------------
make_temp_home "macw1y-t2"
t2_home="$MACW1Y_LAST_TMP_HOME"
if run_isolated "$t2_home" apply --gtk-variant=dark --icon-variant=mactahoe --execute >/dev/null 2>&1; then
  if [[ -f "$t2_home/.themes/macW1Y-Dark/.macw1y-managed" && \
        -f "$t2_home/.icons/MacTahoe/.macw1y-managed" && \
        -f "$t2_home/.local/state/macw1y-theme/manifest.json" ]]; then
    if run_isolated "$t2_home" status >/dev/null 2>&1 && \
       run_isolated "$t2_home" restore >/dev/null 2>&1; then
      if [[ ! -e "$t2_home/.themes/macW1Y-Dark" && \
            ! -e "$t2_home/.icons/MacTahoe" && \
            ! -e "$t2_home/.local/state/macw1y-theme/manifest.json" ]]; then
        if run_isolated "$t2_home" restore >/dev/null 2>&1; then
          pass "Test 2: apply --execute then restore round-trips cleanly"
        else
          fail "Test 2: Second restore (no manifest) exited non-zero"
        fi
      else
        fail "Test 2: restore left managed files or manifest behind"
      fi
    else
      fail "Test 2: status or restore failed"
    fi
  else
    fail "Test 2: apply --execute did not create expected theme/icon/manifest files"
  fi
else
  fail "Test 2: apply --execute failed"
fi

# Optional gsettings round-trip inside isolated dbus-run-session
if (( HAS_ISOLATED_DBUS == 1 )); then
  make_temp_home "macw1y-t2-dbus"
  t2_dbus_home="$MACW1Y_LAST_TMP_HOME"
  if env -u DBUS_SESSION_BUS_ADDRESS \
    HOME="$t2_dbus_home" \
    XDG_CONFIG_HOME="$t2_dbus_home/.config" \
    XDG_DATA_HOME="$t2_dbus_home/.local/share" \
    XDG_STATE_HOME="$t2_dbus_home/.local/state" \
    dbus-run-session -- bash -c '
      set -euo pipefail
      script="$1"
      gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"
      gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
      bash "$script" apply --gtk-variant=dark --icon-variant=mactahoe --execute >/dev/null
      [[ "$(gsettings get org.gnome.desktop.interface gtk-theme)" == "'"'macW1Y-Dark'"'" ]]
      [[ "$(gsettings get org.gnome.desktop.interface icon-theme)" == "'"'MacTahoe'"'" ]]
      bash "$script" restore >/dev/null
      [[ "$(gsettings get org.gnome.desktop.interface gtk-theme)" == "'"'Adwaita'"'" ]]
      [[ "$(gsettings get org.gnome.desktop.interface icon-theme)" == "'"'Adwaita'"'" ]]
    ' _ "$SCRIPT"; then
    pass "Test 2b: gsettings apply/restore round-trip (isolated dbus-run-session)"
  else
    fail "Test 2b: gsettings apply/restore round-trip failed"
  fi
else
  skip "Test 2b: isolated dbus-run-session/gsettings unavailable; skipping gsettings assertions"
fi

# ---------------------------------------------------------------------------
# Test 3: Idempotency (second apply --execute is a no-op for copy & backup)
# ---------------------------------------------------------------------------
make_temp_home "macw1y-t3"
t3_home="$MACW1Y_LAST_TMP_HOME"
if run_isolated "$t3_home" apply --gtk-variant=dark --icon-variant=mactahoe --execute >/dev/null 2>&1; then
  backup_count_1="$(find "$t3_home/.local/state/macw1y-theme/backup" -mindepth 1 -maxdepth 1 -type d | wc -l)"
  if run_isolated "$t3_home" apply --gtk-variant=dark --icon-variant=mactahoe --execute >/dev/null 2>&1; then
    backup_count_2="$(find "$t3_home/.local/state/macw1y-theme/backup" -mindepth 1 -maxdepth 1 -type d | wc -l)"
    if [[ "$backup_count_1" -eq 1 && "$backup_count_2" -eq 1 ]]; then
      pass "Test 3: Idempotent re-apply created no duplicate backup"
    else
      fail "Test 3: Expected 1 backup dir before and after re-apply (got $backup_count_1 -> $backup_count_2)"
    fi
  else
    fail "Test 3: Second apply --execute exited non-zero"
  fi
else
  fail "Test 3: First apply --execute failed"
fi

# ---------------------------------------------------------------------------
# Test 4: HOME path containing spaces
# ---------------------------------------------------------------------------
make_temp_home "macw1y test 4"
t4_home="$MACW1Y_LAST_TMP_HOME"
if run_isolated "$t4_home" apply --gtk-variant=light-solid --icon-variant=mactahoe-light --execute >/dev/null 2>&1; then
  if [[ -f "$t4_home/.themes/macW1Y-Light-solid/.macw1y-managed" && \
        -f "$t4_home/.icons/MacTahoe-light/.macw1y-managed" && \
        -f "$t4_home/.local/state/macw1y-theme/manifest.json" ]] && \
     run_isolated "$t4_home" status >/dev/null 2>&1 && \
     run_isolated "$t4_home" restore >/dev/null 2>&1 && \
     [[ ! -e "$t4_home/.themes/macW1Y-Light-solid" && \
        ! -e "$t4_home/.icons/MacTahoe-light" && \
        ! -e "$t4_home/.local/state/macw1y-theme/manifest.json" ]]; then
    pass "Test 4: HOME path with spaces apply/status/restore succeeded"
  else
    fail "Test 4: Failed with spaces in HOME path"
  fi
else
  fail "Test 4: apply --execute failed with spaces in HOME path"
fi

# ---------------------------------------------------------------------------
# Test 5: Pre-existing unrelated theme collision
# ---------------------------------------------------------------------------
make_temp_home "macw1y-t5"
t5_home="$MACW1Y_LAST_TMP_HOME"
mkdir -p -- "$t5_home/.themes/macW1Y-Dark"
printf 'keep-me\n' > "$t5_home/.themes/macW1Y-Dark/sentinel.txt"
if run_isolated "$t5_home" apply --gtk-variant=dark --icon-variant=mactahoe --execute >/dev/null 2>&1; then
  fail "Test 5: Expected collision refusal, but apply --execute exited 0"
else
  if [[ -f "$t5_home/.themes/macW1Y-Dark/sentinel.txt" ]] && \
     [[ "$(cat "$t5_home/.themes/macW1Y-Dark/sentinel.txt")" == "keep-me" ]] && \
     [[ ! -e "$t5_home/.icons/MacTahoe" ]] && \
     [[ ! -e "$t5_home/.local/state/macw1y-theme/manifest.json" ]]; then
    pass "Test 5: Collision refused cleanly without overwriting or partial writes"
  else
    fail "Test 5: Collision check altered existing theme or left partial writes"
  fi
fi

# ---------------------------------------------------------------------------
# Test 6: Partial-failure recovery (read-only ~/.icons during apply)
# ---------------------------------------------------------------------------
make_temp_home "macw1y-t6"
t6_home="$MACW1Y_LAST_TMP_HOME"
mkdir -p -- "$t6_home/.icons"
chmod 555 -- "$t6_home/.icons"

if run_isolated "$t6_home" apply --gtk-variant=dark --icon-variant=mactahoe --execute >/dev/null 2>&1; then
  chmod 755 -- "$t6_home/.icons"
  fail "Test 6: Expected apply --execute to fail when ~/.icons is read-only"
else
  chmod 755 -- "$t6_home/.icons"
  leftover_backups="$(find "$t6_home/.local/state/macw1y-theme/backup" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l || true)"
  if [[ ! -e "$t6_home/.themes/macW1Y-Dark" && \
        ! -e "$t6_home/.local/state/macw1y-theme/manifest.json" && \
        "$leftover_backups" -eq 0 ]]; then
    if run_isolated "$t6_home" restore >/dev/null 2>&1 && \
       run_isolated "$t6_home" apply --gtk-variant=dark --icon-variant=mactahoe --execute >/dev/null 2>&1 && \
       [[ -f "$t6_home/.themes/macW1Y-Dark/.macw1y-managed" && \
          -f "$t6_home/.icons/MacTahoe/.macw1y-managed" && \
          -f "$t6_home/.local/state/macw1y-theme/manifest.json" ]] && \
       run_isolated "$t6_home" restore >/dev/null 2>&1; then
      pass "Test 6: Partial-failure rolled back cleanly and recovered on retry"
    else
      fail "Test 6: Recovery restore or retried apply --execute failed"
    fi
  else
    fail "Test 6: Partial failure left orphaned theme, manifest, or backup dir"
  fi
fi

if (( failed )); then
  say "FAIL: One or more macw1y-theme tests failed."
  exit 1
fi

say "PASS: All macw1y-theme sandbox tests passed."
