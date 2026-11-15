# Ubuntu 26.04 / GNOME 50 compatibility plan

Target: Ubuntu 26.04.1 LTS, GNOME 50, Wayland; BOSGAME mini-PC development workstation. Remote access via Tailscale, SSH, Thincast/RDP, GNOME Remote Desktop, and AnyDesk must remain operational.

## Goal

Adapt the existing macW1Y fork rather than recreate the UI. Preserve Dock magnification, Liquid Glass, Control Center, Spotlight, Launchpad, menu bar, icons, wallpapers, GTK styling, animations, and Finder-like file-manager appearance wherever safely supportable.

## Findings from upstream source (static review, not runtime verification)

- The original `install.sh` is a broad system installer. `run_full_install()` installs extensions/settings plus GDM, Plymouth, GRUB, touchpad and game-mode components. There is no contained visual-only option.
- It modifies the system Nautilus executable and wraps launches with `LD_PRELOAD`; the GNOME Settings installer also replaces a system executable with a wrapper.
- GNOME Shell overlay installation includes `dpkg-divert` on `/usr/bin/gnome-shell`.
- GDM installation changes the login configuration and fingerprint PAM behavior.
- Core binaries in `lib/` are distributed precompiled. Source coverage, reproducibility, compatibility, and runtime effects need separate assessment.
- Several extension manifests declare GNOME 50 support (including Kiwi, Liquid Glass, Blur My Shell, Cupertino Dock Lite, and Dash2Dock Motion); manifest support alone does not prove runtime compatibility.
- Hardcoded `/home/vitaliy` paths exist in tooling and some fallback paths.
- Upstream's uninstaller resets to default values and includes broad removal operations; it is not a reliable restoration mechanism for pre-existing customized machines.

## Adaptation milestones

### 1. Safe discovery and installer design

Build read-only preflight and dry-run first. Determine actual GNOME version, session type, existing extensions, shell settings, font/theme paths, and remote-access status. Design a new, explicitly opted-in **user-level** installer profile and separate rollback journal. Keep the upstream installer for reference only; do not invoke it.

### 2. Full visual compatibility

Audit each theme/extension's GNOME 50 API use, version-specific internals, and interaction with other extensions. Keep single ownership for Dock geometry, glass shaders, and Quick Settings. Port components with tests in a disposable Wayland GNOME 50 desktop.

### 3. Optional system effects

Treat GDM, GRUB/Plymouth, Nautilus/Settings binary overlays, `LD_PRELOAD`, touchpad and performance daemons as separate high-risk features. They are not part of default installation. Evaluate technical feasibility and rollback, then request explicit approval if any becomes necessary for feature parity.

### 4. Runtime acceptance

Verify login/logout, lock/unlock, animations, multiple workspaces, Dock, Control Center, GTK3/GTK4 apps, Nautilus, Settings, CPU/GPU load, and upgrade survival. Test physical and remote sessions separately. Confirm no regression in RDP/Thincast, AnyDesk, clipboard/paste, screenshots, SSH, Tailscale, or existing development apps.

## Test/merge gates

- Local static checks pass via `bash scripts/ci-local.sh` (never GitHub Actions).
- No unsafe privileged mutations in the default installer path.
- Each enabled extension is tested against actual GNOME 50 runtime, not metadata alone.
- Backup/rollback restores the prior user-specific state, not an assumed default.
- Claude reviews security and compatibility; Codex signs off integration; Gemini is the primary code implementer.
- No production deployment until remote recovery access is confirmed.

## CI location

GitHub is a code host only. Run checks locally or through the existing self-hosted CI farm. Do not commit `.github/workflows/` or enable a hosted CI provider.
