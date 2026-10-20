# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

The fonts are unchanged (same release assets as v1.0.0); these changes affect the scripts, tools and docs.

### Added

- Project scaffolding: license, notice, contributing guide, security policy, CI, issue/PR templates, editorconfig.
- `sandbox/script-test.ps1` and `start-rehearsal.ps1 -Mode Scripts`: a no-restart functional test of the
  install and restore scripts (fresh install, guards, simulated crash + `-Resume`, restore) in Windows Sandbox.
- `status.ps1 -BackupDir`, and an exit code (0 = everything in place).
- CI: ruff, dependency install and API smoke test, known-bad build settings, variable-casing check,
  checksum-manifest format, executable bits, line endings, `status.ps1` smoke run; Dependabot for pip.

### Changed

- `install.ps1` downloads the release over HTTPS; GitHub CLI and sign-in are no longer needed.
- Installer records every change in `state.json` **before** making it, finds all conflicts in a pre-flight
  before the first change, writes `state.json` atomically, verifies every copied file, refuses to run
  while a previous uninstall still waits for a restart, and time-limits the restore point and registry exports.
- `-Resume` remembers `-SkipUI` / `-SkipEmoji` and finishes partly recorded steps.
- A byte-identical SF font that is already installed is left alone (only a missing registry entry is added and later removed).
- Backup folder is restricted to administrators; restore validates `state.json` before acting, continues past
  individual failures and reports them.
- The restart prompt uses a 30-second, cancellable restart instead of an immediate forced one.
- Build scripts: `build_emoji.sh` keeps a relative output path, requires a full commit SHA and checks
  for macOS; `fetch_apple_fonts.sh` detaches images on failure, retries downloads and enforces the 155-font count;
  `build_ui_fonts.py` has proper argument parsing, reads the SF version label from the font and closes files (Windows).
- Validation: `validate_ui_fonts.py` no longer counts the fonts under test as their own fallback; tools print
  usage and fail with a non-zero exit code; `winload.ps1` exits 1 on a failed font.

### Removed

- The automatic fallback to a personal `E:\FontBackup` folder; use `-BackupDir` for a non-default location.

## [1.0.0] - 2026-10-20

### Added

- One-step `install.ps1`, `uninstall.ps1` and read-only `status.ps1`.
- 13 SF Pro / SF Arabic-based replacements for Segoe UI (12 faces) and Segoe UI Variable, applied by
  registry repointing; Apple Color Emoji as "Segoe UI Emoji"; 155 SF / New York fonts.
- Build (macOS), validation and Windows Sandbox rehearsal tooling; documentation.

[Unreleased]: https://github.com/xKleja/apple-fonts-on-windows-11/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/xKleja/apple-fonts-on-windows-11/releases/tag/v1.0.0
