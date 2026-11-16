# macW1Y Compatibility Fork — Implementation Plan

**Stage:** Plan only. No deployment approved.  
**Primary target:** Existing Ubuntu 26.04.1 LTS / GNOME Wayland workstation.  
**Manager:** Claude. **Reviewer:** Codex. **Implementer:** Gemini.  
**CI:** Independent local ci-farm only; never GitHub Actions.

## Delivery philosophy

Preserve a working development machine and its remote connectivity. Aim for the macOS visual experience without adopting upstream's entire operating-system modification layer. Prefer user-scoped GTK/icon changes and isolated GNOME extensions; avoid a bespoke installer framework, unnecessary packages, and system-wide changes. A component may be skipped if its risk outweighs its visual value.

### Work package 0 — Safety and environment baseline (current)

- [x] Establish safe agent rules and local-only CI requirement.
- [x] Identify critical static risks in upstream installer, uninstaller, and representative runtime components.
- [x] Run scripts/ci-local.sh on a local clone or independent ci-farm; record output (no GitHub Actions). Ran `bash scripts/ci-local.sh` on commit 19d2410a: exit 0, all 10 checks printed PASS, no FAIL; re-verified by Codex QA (gpt-6-luna, 2026-11-16) including simulated-failure cases. Reproduce with `bash scripts/ci-local.sh`.
- [x] Verify current exact GNOME Shell, Mutter, Ubuntu, Wayland, existing extensions, theme settings, and remote access with read-only commands listed in COMPATIBILITY.md. Captured in COMPATIBILITY.md's "confirmed read-only snapshot" table.
- [ ] Establish a restore point, access method independent of the modified graphical session, and a proven rollback process before any GUI mutation. Access confirmed (SSH/Tailscale services active, independent of the GNOME session) and a dconf/file-backup rollback procedure is designed — see COMPATIBILITY.md "Restore point and recovery" — but a live backup/restore round-trip has not been rehearsed yet; leaving open until Work Package 1's dry-run exercises it for real.
- [x] Manually inspect upstream assets that will be reused for licenses, unexpected executables/symlinks, and malware indicators. See COMPATIBILITY.md "Asset spot-check": icon theme (`icons/MacTahoe*`) is attributed/licensed GPLv3; GTK `.rc`/`themerc` files and symlinks carry no risk; `fonts/` (except `Open_Runde`) and the two Apple-pattern-matching wallpaper assets are excluded pending real license verification, not cleared for reuse.

**Gate 0:** Manager approves a specific, auditable cosmetic-only scope. No runtime changes.

### Work package 1 — Safe cosmetic asset adapter (Gemini) — DONE, live-tested 2026-11-16

- [x] Create a minimal user-scoped preview or install plan that does not call install.sh, uninstall.sh, any updater, or privileged helper. `scripts/macw1y-theme.sh` — confirmed by code review, never invokes those.
- [x] Select theme CSS, icons and optional backgrounds explicitly; list every installed/overwritten path in a generated manifest. GTK theme + icon theme only; backgrounds omitted entirely since none are license-cleared (COMPATIBILITY.md asset spot-check). `manifest.json` records exact paths written and backed up.
- [x] Do not overwrite existing user GTK4 configuration without backup; account for libadwaita's stylesheet limitations. Backup confirmed live (original `Yaru`/`Yaru`/`Yaru` captured in the manifest and a `dconf dump`). The libadwaita limitation was directly observed on the real desktop, not just anticipated — see "Live test findings" below.
- [x] Include dry-run as the default, backup of each overwritten user file, exact restore command, and collision detection. Dry-run-by-default and collision detection verified both in sandbox and live (real `$HOME`, before any write). `restore` is implemented and passed its sandbox round-trip test; **not yet exercised against this live apply** — intentionally left applied so the owner can keep evaluating it; restore it with `bash scripts/macw1y-theme.sh restore` whenever ready.
- [x] Keep GTK/theme application separate from GNOME Shell extension enablement. Confirmed by code review — the script never touches `gnome-extensions`/extension state.
- [x] Include test fixtures for paths with spaces, repeated application (idempotency), pre-existing themes, and partial failure recovery. `scripts/macw1y-theme-test.sh`, all 6 cases pass.
- [x] No Apple fonts, proprietary wallpapers, or other unclear-redistribution assets in a new packaged release until license verification. Script never references `fonts/` or `wallpapers/` at all.

**Gate 1 — PASSED 2026-11-16:** Diff reviewed (Codex, 2 rounds, 9 real bugs found and fixed), reproducible manifest confirmed live, dry-run/restore tested in sandbox. Owner authorized and ran the first live cosmetic test on the real target (`--gtk-variant=dark --icon-variant=mactahoe-dark --execute`); SSH/Tailscale/GNOME Remote Desktop confirmed unaffected, including a live RDP session actively in use during the test.

**Live test findings (real desktop, not sandbox):**
- Icon-theme changes propagate everywhere, including through `kiwi@kemma`'s dock (its `tahoeApps.js:108` calls `Gtk.IconTheme.get_for_display()`, so dock icons reflect whatever icon theme is active) — confirmed by reading the extension's source, not assumed.
- `blur-my-shell` has zero references to `icon-theme` in its source — its blur/transparency effects are completely independent of anything WP1 touches.
- GTK-theme CSS only visibly restyles legacy GTK3 apps (`update-manager`, confirmed GTK3/PyGObject). Modern libadwaita apps (Nautilus/Files, Ptyxis/Terminal, GNOME Settings, Text Editor — all confirmed GTK4+libadwaita via `ldd`) ignore custom GTK themes by design; only their icons change, not their window chrome. This is a real, permanent limitation of the GTK-theme-CSS approach, not a bug — any future macOS-chrome goal for these apps needs a different mechanism (WP2's shell theme, or accepting libadwaita's native look).

### Work package 2 — Desktop shell appearance, one extension at a time

Suggested evaluation order: existing Ubuntu dock baseline -> user theme -> one supported dock enhancement -> one blur/glass extension -> one menu/control-center feature. Never enable competing implementations simultaneously.

- [ ] Inventory and preserve the currently installed Ubuntu dock and extensions.
- [ ] Inspect GNOME 50 API compatibility and security-sensitive behavior of each candidate, not just metadata.json.
- [ ] Explicitly exclude eval-helper@mactheme, any D-Bus Eval endpoint, and forced extension-version-validation bypass.
- [ ] Prefer native user-scoped GNOME extension mechanisms; no /usr/bin/gnome-shell replacement or G_RESOURCE_OVERLAYS injection.
- [ ] Verify on a test session first; never mass-enable bundled extensions.
- [ ] Record login behavior, extension errors, window management, performance, and the remote desktop session after each change.
- [ ] Keep an immediate disable/restore path available in case the GUI stops responding.

**Gate 2:** Each extension individually passes functional and remote-access smoke tests; compatibility review signed off by manager.

### Work package 3 — User experience refinement

- [ ] Tune light/dark behavior, titlebar buttons, window shadows, dock placement, and GNOME accessibility without replacing system binaries.
- [ ] Preserve keyboard layout, input methods, terminal keybindings, copy/paste, screenshots, AnyDesk, RDP, Tailscale, and SSH.
- [ ] Consider optional changes to the user file manager appearance only through supported themes or extensions; do not hook Nautilus through LD_PRELOAD.
- [ ] If GNOME 50 cannot support a particular macOS feature safely, document the trade-off and skip it.

**Gate 3:** Accept visually with a live before/after review and a clean rollback test; no degradation in the development workflow.

## Excluded from this program unless separately requested and approved

GDM/login customization; GRUB/Plymouth; initramfs, kernel, dracut; systemd daemons (including the root-privileged mac-grub-status.service that executes a script from the user's home directory); power/GPU tweaks; udev/input group changes; sudoers changes; environment rewrites; GNOME binary diversion; Nautilus or GNOME Control Center binary wrappers; arbitrary D-Bus JavaScript Eval; auto-repair watchdogs; the ~/Applications auto-execute watcher (mac-sync-applications); mac-gdm-bypass auto-login/GDM-restart behavior; global dconf import/reset; installing Wine/Steam/NVIDIA drivers solely for appearance.

## Local CI contract

The ci-farm may run shell syntax checking, metadata validation, static security checks, file manifest consistency checks, and tests that operate only inside a disposable temporary directory. It **must not** run the upstream install/uninstall/upgrade scripts or apply GTK/dconf/system changes to the ci-farm node.

Minimum initial job, invoked **from a local clone or the independent ci-farm**:

    bash scripts/ci-local.sh

This check intentionally proves only the documented static policy assertions and is not a security certification. Future tests can be added under scripts/ and called directly by the farm; never create .github/workflows.

## Deployment checklist (future, not authorization)

1. Capture exactly which files/settings would change; review a dry-run before any writes.
2. Store backups and a rollback manifest outside the theme source tree.
3. Confirm alternate SSH/physical recovery route, and verify it works.
4. Apply one user-scoped component (not full installer).
5. Confirm desktop, login, AnyDesk (if present), GNOME RDP, Tailscale, SSH, terminal autocomplete, clipboard text, and screenshot clipboard behavior are no worse than baseline.
6. If any function breaks, execute the specific component rollback and stop; do not use upstream uninstall.sh.
7. After a successful validation window, document the exact tested versions and any unresolved limitations.

## Current handoff to Gemini

**First engineering task, only after manager review:** Build and test a user-scoped cosmetic asset manifest/dry-run prototype, with no sudo, no system paths, no dconf changes, no extension enablement, no network downloads, and no workstation installation. Keep implementation narrowly scoped and dependency-free where practical. Report a compact file-by-file change summary, local test output, and known risks.

## Acceptance and reporting

Each merge candidate should state: changed files, tests run (where: local/ci-farm), version assumptions, privilege and network usage, planned workstation impact, exact rollback strategy, and any gaps. No automatic merge or deploy.
