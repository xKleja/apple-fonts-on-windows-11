# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.3.0] - 2026-10-21

Install by pasting one line into PowerShell. The fonts are unchanged.

### Added

- **Paste-in install:** `irm https://github.com/xKleja/apple-fonts-on-windows-11/releases/latest/download/get.ps1 | iex`
  in PowerShell (or the same through `powershell -Command "..."` from Command Prompt).
  `get.ps1`, attached to every release, downloads that release's source ZIP from this repository,
  unpacks it to `%LOCALAPPDATA%\AppleFontsOnWindows` and starts `Install.cmd` there. Pasting it again
  reuses the copy. CI checks that `get.ps1` names the version in `VERSION`, and every week that the
  latest release carries a `get.ps1` for itself.
- `AGENTS.md` rewritten as the must-read rule list for coding agents and contributors: the complete list
  of what the install may change on Windows, Windows anti-corruption rules, security, PowerShell, user
  experience, testing (definition of done), font and release rules. `CLAUDE.md` points Claude Code to it.
- CI safety guards (`.github/scripts/safety-guards.sh`) fail the build when a product script writes to
  other font settings, deletes registry keys, uses takeown / icacls, adds anything that runs later, uses
  boot or servicing tools, runs downloaded code, contacts another address, or starts Windows tools
  without a full path.

### Changed

- `reg.exe` and `shutdown.exe` are started by full path.

### Fixed

- `state.json` saved the project version as an object (`{ "value": "1.2.0", "PSPath": ... }`) instead
  of `"1.2.0"`, and Status.cmd printed all of it. Status.cmd reads both forms.

## [1.2.0] - 2026-10-21

From a review of the project as a Windows team lead. The fonts are unchanged.

### Fixed

- **`Install.cmd` started from a PowerShell 7 window failed** ("Get-FileHash is not recognized"):
  Windows PowerShell inherited PowerShell 7's module path. The launchers clear it and the scripts reset
  it to Windows PowerShell's own folders.
- **Status.cmd said "Not installed" and uninstalling from Settings failed for anyone not running as
  administrator**: the backup folder was readable by administrators only. Everyone can now read it; only
  administrators can change it.
- **A standard user could prepare `%ProgramData%\AppleFontsOnWindows` before the install** and so control
  the uninstaller that Settings runs as administrator. A folder that a non-administrator could have
  changed (owner, permissions, links) is now set aside and recreated; an existing custom `-BackupDir`
  must be administrators-only.
- `state.json` is checked against allowlists: only the 13 Segoe UI files, `seguiemj.ttf` and Apple-named
  font files may appear in it (a modified one could previously make the elevated uninstall remove other fonts).
- Per-user font overrides are handled for the signed-in user, even when an administrator's password was
  typed at the UAC prompt (previously the administrator account's settings were changed instead).
- The launchers keep their window open on every failure, say what to do when the ZIP was not extracted,
  and start PowerShell by its full path.
- Paths containing `[` or `]` work (every file operation uses literal paths).
- A relative `-BackupDir` is resolved against the current folder, and `-BackupDir C:\` is passed correctly.
- The Settings entry showed the fonts release (1.0.0) as its version; it now shows the project version
  (new `VERSION` file).
- Release zips are unpacked into a scratch folder and only the listed fonts are copied out, so a zip cannot
  replace the checksum files.
- Restore reports a failed delete-at-restart or registry removal instead of claiming success.

### Changed

- **Install and uninstall windows show numbered steps** (`[1/7]`...`[7/7]`, `[1/3]`...`[3/3]`) with a
  progress bar for every long step: fonts checked, download size / speed / time left, fonts installed or
  removed; a seconds counter while the restore point is created and the font cache stops; green ticks;
  and a summary with the time taken, how to check and how to undo.
- Installing again over a finished install says "Already installed"; over an unfinished one,
  `Install.cmd` offers to finish it. Uninstalling with nothing installed says "Nothing to uninstall".
- `status.ps1` shows the project version, the Windows build and the backup folder, flags a per-user copy
  that hides the system font, and exits 0 / 1 / 2 (in place / differs / not installed).
- Install and restore logs include the error and its location; a failed install prints the log path.
- Downloads show progress (Background Intelligent Transfer), keep zips that already arrived, and report
  free-space and download problems separately.
- Clear messages for S mode / Smart App Control, and for restarting with Restart rather than Shut down.
- The SF fonts are recorded in `state.json` in one step before they are copied (faster with antivirus).
- `-BackupDir` folders must be new or administrators-only, and always get the Settings entry.

### Added

- `tests/state-and-folder.tests.ps1` (state validation, folder trust), run by CI on 5.1 and 7.
- CI: the launcher's missing-files message; a *Release assets* workflow that downloads the fonts through
  `Install.cmd -DownloadOnly` on font changes and weekly.
- Sandbox script test: runs as a standard user too (Status.cmd, reading the uninstaller, not writing the
  backups), a prepared backup folder, a per-user override, and a folder name with `[ ]`.

Installs made with 1.1.0 or earlier: their Settings entry cannot start its uninstaller without
administrator rights. Uninstall with `Uninstall.cmd` from this version instead.

## [1.1.0] - 2026-10-21

The fonts are unchanged (same release assets as v1.0.0); these changes affect the scripts, tools and docs.

### Added

- Double-click launchers `Install.cmd`, `Uninstall.cmd` and `Status.cmd`; the README install guide is
  written for anyone with Windows 11 (Download ZIP, Extract All, double-click).
- A **Settings > Apps > Installed apps** entry, with its uninstaller kept in the admin-only backup folder,
  so uninstalling works after the downloaded folder is deleted.
- Checks before anything is downloaded or changed: Windows 11 desktop edition, folder extracted from the
  ZIP, not on a network drive, path not too long; a warning for OneDrive folders and for an existing
  FontSubstitutes entry for Segoe UI.
- `fonts/release.txt`: the installer downloads the release that matches the checksums in the checkout
  (instead of the latest release), retries failed downloads, and downloads missing or damaged fonts again.
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
- `-Resume` remembers `-SkipUI` / `-SkipEmoji`, finishes partly recorded steps, and refuses to run on a
  complete install.
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

[Unreleased]: https://github.com/xKleja/apple-fonts-on-windows-11/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/xKleja/apple-fonts-on-windows-11/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/xKleja/apple-fonts-on-windows-11/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/xKleja/apple-fonts-on-windows-11/releases/tag/v1.0.0
