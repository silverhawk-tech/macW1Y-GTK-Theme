# macW1Y / Ubuntu 26.04 Compatibility and Risk Inventory

**Status:** Initial static audit, 2026-11-15. Not an approval to install.

**Review target:** silverhawk-tech/macW1Y-GTK-Theme, baseline main tree 84a8bdd25c19a640acf210168d67085e9dc05941. The GitHub tree contains 55,765 entries (approximately 48,432 under icons). Examined the full root installer/uninstaller, AI instructions, package manifest, and representative scripts, system services, extensions, and metadata. This was not a line-by-line security audit of all source files, binaries, or assets; no execution or live compatibility testing occurred.

## Target environment — confirmed read-only snapshot, 2026-11-15

Captured directly on the target workstation with the read-only commands below; no writes made.

| Item | Value |
| --- | --- |
| OS | Ubuntu 26.04.1 LTS (Resolute Raccoon) |
| GNOME Shell | 50.1, session type `wayland`, `ubuntu:GNOME` |
| Mutter | 50.1-0ubuntu2.5 (via `dpkg -s mutter-common`; there is no standalone `mutter` binary on this install — `mutter --version` does not exist here) |
| GTK/icon theme | `gtk-theme`/`icon-theme` = `Yaru`, `cursor-theme` = `Yaru`, `color-scheme` = `prefer-dark` (stock; the dark look comes from `color-scheme`, not a `Yaru-dark` theme name — corrects an earlier wrong claim in this table; macOS theme not currently applied) |
| Enabled extensions | `just-perfection-desktop@just-perfection`, `codexbar@inled.es`, `blur-my-shell@aunetx`, `kiwi@kemma`, `snapd-prompting@canonical.com`, `snapd-search-provider@canonical.com`, `tiling-assistant@ubuntu.com`, `ubuntu-appindicators@ubuntu.com`, `ubuntu-dock@ubuntu.com`, `web-search-provider@ubuntu.com` |
| AnyDesk | **Not found on PATH via `command -v`** (corrects the earlier assumption — only Tailscale/SSH/GNOME Remote Desktop are confirmed present). `command -v` only shows it isn't on PATH, not that it's fully absent from the system; treat as "not confirmed present" rather than a proven negative. |
| Tailscale | `tailscaled.service` confirmed `active`/`enabled` via systemd (service-level only — reachability from another peer was not separately tested) |
| SSH | `ssh.service` confirmed `active`/`enabled` via systemd (service-level only — an actual remote login was not separately tested) |
| GNOME Remote Desktop | Active, RDP server running (Thincast-compatible) |

**Extension-name collision, new finding:** `blur-my-shell@aunetx` and `kiwi@kemma` are already enabled. This was checked with an additional `diff -rq` against this repo's `extensions/blur-my-shell@aunetx` and `extensions/kiwi@kemma` (beyond the commands listed above) and shows the installed copies are the stock, unmodified upstream versions (`SweetTooth`-generated), not this fork's "mac_"-prefixed patched variants. No fork code is currently live. Any future install of this fork's versions of these two extensions would **replace an already-enabled, independently-used extension**, not install cleanly alongside it — treat this as a Work Package 2 collision to plan for explicitly (back up the user's current config/version of each before swapping).

Ubuntu 26.04 / GNOME Shell 50 is the confirmed adaptation target. Bundled GNOME extension metadata frequently lists version 50; that alone does not verify extension safety, actual ABI/API compatibility, or compatibility with the workstation's package versions.

## Findings (repo evidence)

| Tier | Component | Evidence and implication | Decision |
| --- | --- | --- | --- |
| **CRITICAL** | Unrestricted sudo | etc/sudoers.d/99-mactheme contains: vitaliy ALL=(ALL) NOPASSWD: ALL. install.sh:1168-1175 copies its sudoers directory into /etc/sudoers.d. The username is hard-coded; broad passwordless root permission is unacceptable regardless. | Exclude entirely |
| **CRITICAL** | Arbitrary shell JavaScript evaluation over D-Bus | extensions/eval-helper@mactheme/extension.js:437-443 exports an Eval method that calls eval(code), and line 553 publishes a session D-Bus object. An arbitrary-code execution surface inside GNOME Shell is incompatible with the safety baseline. | Exclude until independently redesigned/audited |
| **CRITICAL** | GNOME Shell binary diversion | install.sh:1385-1431 uses dpkg-divert to move /usr/bin/gnome-shell and installs bin/gnome-shell, which sets G_RESOURCE_OVERLAYS. A failure risks the graphical session and remote desktop. | Exclude |
| **HIGH** | Nautilus binary wrapper and preload | install.sh:450-470 renames /usr/bin/nautilus to .orig, writes a wrapper, and uses LD_PRELOAD with bundled/native .so libraries. | Exclude |
| **HIGH** | Bootloader/initramfs | install.sh:1610-1746 changes Plymouth, /etc/initramfs-tools, /etc/default/grub, multiple /etc/grub.d files (including 10_linux), GRUB menu assets, and runs update-initramfs/update-grub. apply_plymouth.sh also touches sudoers, GRUB, and initramfs. | Exclude |
| **HIGH** | Full environment rewrite | install.sh:1767-1773 replaces the entire /etc/environment, rather than adding a scoped file. This may erase important workstation settings. | Exclude |
| **HIGH** | Login and GDM | install.sh:1437-1604 changes GDM dconf, greeter, session integration, automatic-login state, and fingerprint-related PAM behavior. | Exclude |
| **HIGH** | Broad dconf mutation | install.sh:738-778 applies dconf/gnome-all.dconf at the root dconf path; keyboard layout is handled specially, but many other existing settings may be overwritten. | Exclude; replace with reviewed per-key changes |
| **HIGH** | Extension re-enabling and validation bypass | bin/mac-ensure-extensions.sh forces disable-user-extensions=false, disables extension-version-validation, and re-enables a large extension set. This defeats rollback and compatibility checks. | Exclude |
| **HIGH** | Driver, daemon, input and privileges | install.sh:1098-1141 deploys a touchpad daemon, writes udev rules, and adds the user to the input group; install.sh:1146-1320 alters GPU/game-mode tooling, sudoers, and system services. | Exclude |
| **HIGH** | Unsafe generic removal | uninstall.sh:135-244 removes system and /usr/local paths, including /usr/local/bin/steam, and resets preferences to Yaru rather than preserving the prior baseline. Cannot be considered a safe rollback. | Exclude; build ownership-aware rollback |
| **HIGH** | Unreviewed native binaries | lib/ contains multiple .so libraries and a typelib; extensions and source code use in-process GTK/GNOME hooks. No binary provenance, reproducibility, or runtime audit has been established. | Exclude from initial rollout |
| **CRITICAL** | Persistent root execution from a user-writable home path | systemd/mac-grub-status.service runs `/home/vitaliy/MACTHEMEFILES/grub/generate_icons.py` as root at shutdown/reboot; enabled by install.sh:1738-1741. Anyone who can write to that checkout gets root code execution on every reboot. | Exclude entirely |
| **HIGH** | Second system executable replacement | install.sh:938-945 overwrites /usr/bin/gnome-control-center with a wrapper that injects libraries (bin/gnome-control-center:26-33). Not limited to gnome-shell/nautilus as previously documented. | Exclude |
| **HIGH** | Auto-login / GDM-restart helper | bin/mac-gdm-bypass:222 can enable automatic login as the hardcoded user, and :251-252 can restart GDM outright. | Exclude; treat as a privileged, approval-gated recovery tool only |
| **HIGH** | Unattended execution of dropped files | install.sh:2110-2115 enables a user service watching ~/Applications (bin/mac-sync-applications); it dispatches installers automatically — AppImages execute at line 901, archive installers at 1132, and install-named shell scripts at 1682, with no confirmation prompt. | Exclude |
| **HIGH** | Archive-name path bug enabling bulk deletion | bin/mac-sync-applications:1085-1086,1115-1117 allows an empty sanitized ID; an archive named e.g. `!!!.zip` collapses to a path that recursively deletes the entire ~/.local/share/installed-apps/ directory. Confirmed by static analysis; not executed. | Exclude; fix input sanitization before any reuse |
| **HIGH** | Uninstaller leaves root sudoers grant behind | uninstall.sh performs no sudoers cleanup, so the NOPASSWD: ALL grant (99-mactheme) survives a full uninstall. | Exclude install.sh's sudoers step entirely; do not rely on uninstall.sh to remove it |
| **MEDIUM** | Package footprint | dependencies/apt-packages.txt includes Wine/i386, NVIDIA PRIME, development libraries, GRUB, and Plymouth regardless of appearance-only objectives; install.sh:279-341 adds the i386 architecture and builds a third-party GNOME library. | Avoid new packages by default |
| **MEDIUM** | Conflicting extensions | extensions/ contains 24 extension directories plus a separate ding-patches directory (25 total entries, not 25 extensions); enabled dock, top bar, blur, and window-management features may collide with Ubuntu defaults or each other. | One-at-a-time testing only |
| **MEDIUM** | Upstream machine assumptions | AI_INSTRUCTIONS.md and AI_Instructions.md explicitly assume /home/vitaliy, direct system sync and one-turn deployment; install.sh also contains fixed source-path substitution. | Superseded by AGENTS.md and fork warning |
| **LEGAL REVIEW** | Bundled Apple materials | README references Apple SF Pro fonts, macOS sounds, wallpapers, and Apple-like marks. Upstream attribution/license claims do not by themselves prove redistribution rights. Spot-checked 2026-11-16, see "Asset spot-check" below for per-asset findings. | Keep existing history untouched; verify before distributing adapted bundles |
| **CI** | Repository workflows | Recursive GitHub tree scan found no .github/workflows entries at the audit baseline. This is **not** proof that repository Actions are disabled in GitHub settings. | No GitHub Actions now or later; local ci-farm only |

### Compatibility candidates

- **Candidate A — cosmetic user-space assets:** selectively copy CSS/GTK themes, icon theme, and wallpaper assets to a test profile or temporary directory, after file and license review. Avoid the root installer and global symlinks. Per the asset spot-check below: `fonts/` (except `Open_Runde`) and the Apple-pattern-matching wallpapers are excluded from this candidate's scope pending license verification.
- **Candidate B — isolated GNOME user extensions:** validate a single extension against the target GNOME version, initially with all competing dock/menu extensions disabled. Examples advertising Shell 50 include Cupertino Dock Lite, Kiwi, Blur My Shell, and Liquid Glass. Metadata compatibility is an initial filter, **not a GO decision**.
- **Candidate C — advanced overlays, Finder/Settings integrations, native .so, GNOME Shell/GDM replacement, boot visuals, device controls:** out of scope for first rollout. Must not be pulled in transitively by an installer.

## Asset spot-check (WP0, 2026-11-16) — manual review, not an installer or exhaustive audit

Scope: the specific CSS/icon/wallpaper assets Candidate A (cosmetic user-space assets) would reuse: `macW1Y-Dark`/`macW1Y-Light`(`-solid`) GTK themes, `icons/`, `wallpapers/`, `fonts/`, `gtk-3.0/`, `gtk-4.0/`.

- **Icon theme (`icons/MacTahoe*`) — attributed and licensed, not independently re-audited asset-by-asset.** Ships its own `COPYING` (GPLv3) and `AUTHORS`, crediting Vince Liuice's existing open-source `WhiteSur-icon-theme`/`MacTahoe-icon-theme` projects on GitHub, consistent with the repo's own top-level `LICENSE` (GPLv3). This establishes license and provenance for the icon set as a whole; it is not independent proof that every individual icon file was authored by that project (e.g. any upstream SF Symbols-derived icon would not be covered by MacTahoe's own GPLv3 grant). Preserve `COPYING`/`AUTHORS` if reused.
- **GTK theme `.rc`/`themerc` files (gtk-2.0, xfwm4, labwc) — no concern.** Plain key-value theme config, not executable code; no code-execution surface.
- **Symlinks — no concern.** 25,247 under `icons/` (confirmed via `find`/git index) plus 5 more elsewhere in this spot-check's scope (macW1Y-Dark/Light metacity theme XML, one gtk-4.0 CSS alias) — 25,252 total. All relative, none resolve outside their own theme/icon tree, none broken. Standard freedesktop icon-theme aliasing (same pattern Yaru/Adwaita use), not a traversal or packaging risk.
- **Loose `+x` permission bits on static PNG/SVG files — cosmetic only.** Many bitmap/vector assets carry an executable permission bit; they are not scripts and GTK/GNOME never executes them, so this is not a security finding, just an artifact of how the tree was packaged.
- **`wallpapers/GoldenGate_Day.jpg` and the "Golden Gate Live" video wallpapers — DO NOT REUSE without further verification.** The "Day" image (7396x3900) plus matching `GoldenGate_Live_loop.mov`/`.mp4` and `Golden Gate.mov` follow Apple's own macOS Sonoma Dynamic Desktop wallpaper naming convention (a real Sonoma wallpaper is named "Golden Gate" with Day/Live variants). No independent authorship or license evidence was found for these. The video files are **Git LFS pointer stubs** in this checkout (`.gitattributes` tracks `*.mov`/`*.MOV`/`*.mp4` via LFS; `git-lfs` is not installed here) — the actual ~158MB of video content has never been downloaded or inspected by anyone on this audit. Treat as likely unlicensed Apple material until someone with git-lfs pulls and independently verifies otherwise; exclude from Work Package 1 until then.
- **`wallpapers/mendhak-Bluebells_Suspended_In_Time.jpg` — needs a license lookup before reuse.** `strings` found an embedded Flickr share URL, confirming the file is a real photo hosted on Flickr (not proof of authorship by itself); the "mendhak" attribution comes from the filename, not the URL, and is unverified against the original post. "mendhak" is a Flickr handle known for Creative-Commons-licensed photos, but the specific CC variant (BY vs BY-SA, commercial-use terms) has not been confirmed — look up the original Flickr post before bundling.
- **`fonts/` — DO NOT REUSE, exclude from Work Package 1.** Contains full, unmodified copies of Apple's own proprietary system font families: `SF_Pro`, `SF_Pro_Display`, `SF_Pro_Text`, `SF_Pro_Rounded`, `SF_Compact_Display`, `SF_Compact_Text`, `SF_Compact_Rounded`, `SF_Mono`, and `New_York` (178 `.otf` files across those nine directories). No `LICENSE`/`COPYING`/`README` file exists anywhere under `fonts/` for any of them. These are Apple-owned fonts bundled by the upstream project without any redistribution license on display; this confirms (with concrete evidence) the existing generic "Bundled Apple materials" legal-review finding above. The remaining 8 files are `fonts/Open_Runde`, a font whose upstream project (lauridskern/open-runde on GitHub) is published under SIL OFL 1.1 — a real open license, but this repo's own copy carries no license file either, so confirm the OFL terms against the upstream project before reuse rather than assuming this copy is self-documenting.
- Could not run `exiftool` in this environment (not installed) — metadata-level provenance (camera EXIF, embedded copyright fields) was not checked beyond `strings`/`file`. A fuller check would re-run this with `exiftool` available.

**Net effect on Candidate A:** the icon theme and theme-engine files are attributed/licensed as a set (GPLv3 notices to be preserved if reused) but not re-audited file-by-file. The two Apple-pattern-matching wallpaper assets are excluded from Work Package 1 pending real license verification; `mendhak-...jpg` needs its exact CC terms confirmed first via the original Flickr post.

## Restore point and recovery (WP0, confirmed 2026-11-16, read-only) — access confirmed, rollback designed but not yet rehearsed

Confirmed on the target workstation, read-only, no writes made:

- **Independent recovery access (confirmed at service level, not end-to-end):** `ssh.service` and `tailscaled.service` are both separate systemd services, confirmed `active`/`enabled` via `systemctl is-active`/`is-enabled`, independent of the GNOME graphical session in principle — a crashed/hung GNOME Shell extension would not stop either service from running. This is service status, not a tested connection: an actual remote login over SSH or Tailscale from another machine was **not** performed as part of this check. No OS-level snapshot tool (Timeshift, Snapper, btrfs) is installed; the root filesystem is plain `ext4` on a single partition, so there is **no filesystem-snapshot safety net** — recovery depends entirely on explicit backups of the specific files/settings each change touches, exactly as IMPLEMENTATION_PLAN.md Work Package 1 already requires (backup of each overwritten user file, exact restore command, dry-run default).
- **Current baseline to restore to, if needed:** `gtk-theme` = `Yaru`, `icon-theme` = `Yaru`, `cursor-theme` = `Yaru`, `color-scheme` = `prefer-dark`; current `dconf dump /` is 568 lines. Any WP1 prototype should diff against this baseline, not assume a blank slate.
- **Rollback procedure for a GTK/icon/dconf-only change (the only kind WP1 will make) — designed, not yet rehearsed:** (1) back up the touched dconf keys (`dconf dump <path> > backup.ini` before writing, `dconf load <path> < backup.ini` to restore — confirm this restores cleanly rather than merging, since `dconf load` semantics should be re-verified against the actual dconf version here before relying on it) and any overwritten user config files; (2) if the GUI becomes unresponsive, SSH or Tailscale in and run the restore commands from the CLI — no reboot or GDM restart should be required for a user-scoped theme/dconf change, but this has not been exercised end-to-end; (3) this does not cover a true GNOME Shell crash loop, which is out of scope since WP1/WP2 explicitly exclude GNOME Shell binary/extension changes capable of causing one until WP2's one-at-a-time extension gate.
- **Still open:** a live rehearsal of (1)-(2) above — an actual dconf backup/restore round-trip and a real remote-login check — has not been performed and requires the owner's go-ahead since it touches the live session, even reversibly. Plan to rehearse this as the first exercise of Work Package 1's own dry-run requirement, not as a separate live test now.

## Required workstation snapshot (read-only; run only after manager review)

    cat /etc/os-release
    gnome-shell --version
    dpkg -s mutter-common 2>/dev/null | grep Version
    echo "$XDG_SESSION_TYPE"
    echo "$XDG_CURRENT_DESKTOP"
    gnome-extensions list --enabled
    gsettings get org.gnome.desktop.interface gtk-theme
    gsettings get org.gnome.desktop.interface icon-theme
    gsettings get org.gnome.shell favorite-apps
    command -v anydesk
    command -v tailscale
    command -v ssh
    systemctl --user --no-pager status gnome-remote-desktop.service

Additional backups and network/remote checks require a deliberately reviewed command set. Read-only collection is not a license to change settings. Do not store sensitive system details or logs in public Git history.

## Definition of a compatibility pass

1. All planned changes are user-scoped, listed in a manifest, and can be reversed without relying on the upstream uninstaller.
2. GUI boots normally; existing session, keyboard, and desktop settings remain intact.
3. GNOME Remote Desktop/RDP, Tailscale, SSH, terminal keyboard/clipboard, and local login remain functional before and after each tested component. AnyDesk is not confirmed present on this workstation (see snapshot above); if it is installed by other means, verify it too — do not assume it must be present to pass this gate.
4. Local ci-farm checks pass; no GitHub-hosted CI is configured or run.
5. Real GNOME/Wayland testing completed for each enabled extension; no forced version-validation bypass.
6. A proven recovery procedure is available independent of the session being modified.

**Current verdict:** No-Go for upstream full install; safe to plan and implement a narrowly scoped cosmetic-only adaptation in the repository.
