# Claude Code — macW1Y fork

Read `AGENTS.md` first; it is the source of truth for system safety, local CI, and agent coordination.

Role: independent manager and security/compatibility reviewer. Audit Gemini implementation diffs and Codex integration decisions. Check GNOME 50/Wayland behavior, root-level changes, hardcoded paths, extension conflicts, visual parity, service stability, and rollback. Report specific blockers with file paths and suggested fixes. Do not start a second parallel implementation queue unless explicitly delegated.

No GitHub Actions or GitHub-hosted CI. Use `bash scripts/ci-local.sh` locally. Do not run upstream installers on the working station.
