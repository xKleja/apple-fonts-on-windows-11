# AGENTS.md

Guidance for AI coding agents (Claude Code and others) working in this repository.
Read [README.md](README.md) first, then [docs/how-it-works.md](docs/how-it-works.md) and
[docs/lessons-learned.md](docs/lessons-learned.md) before changing any build or install code.

## What this repo is

An educational project that makes Windows 11 use Apple's fonts for its UI (Segoe UI / Segoe UI
Variable → SF Pro + SF Arabic) and emoji (Segoe UI Emoji → Apple Color Emoji), and installs the SF /
New York families, with full English and Arabic support.

## Hard rules

1. **Never modify, overwrite, rename or delete a Windows font file** (`C:\Windows\Fonts\segoe*`,
   `seg*`, `SegUIVar.ttf`, `seguiemj.ttf`). The design is *repoint the registry entry at a new
   `SFUI-*.ttf` file*. Overwriting `seguiemj.ttf` already failed once (in use, TrustedInstaller ACL).
2. **Never touch icon fonts** (Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol).
3. **Do not run `install.ps1` / `uninstall.ps1` (or anything elevated) without the user's explicit
   go-ahead.** They change the live system and need a restart. Prefer `status.ps1` (read-only),
   `install.ps1 -DownloadOnly`, or `sandbox\start-rehearsal.ps1` to test.
4. **Font binaries never go into git.** They are release assets. `fonts/**/SHA256SUMS.txt` *is* tracked
   and is the integrity anchor; update it together with any new release.
5. **Any new or rebuilt font must pass, before release:** `validation/validate_ui_fonts.py`
   (`ALL HARD CHECKS PASSED`), `validation/render_all_glyphs.py` (0 blank), `validation/winload.ps1`
   (all load), and a look at the specimen sheets, Arabic in particular. Do not weaken a check to make it pass.
6. Keep every install step **recorded in `state.json` before or right after it happens**, and
   restorable by `restore-macos-fonts.ps1`. Every external tool call needs a timeout (`Invoke-Tool`).
7. Do not add startup items, scheduled tasks or services.
8. Never redistribute font files. Respect the licensing disclaimer in [README.md](README.md).

## Conventions

- PowerShell must run on **Windows PowerShell 5.1 and PowerShell 7**. Check both parsers:
  ```powershell
  foreach ($exe in 'powershell.exe','pwsh.exe') { & $exe -NoProfile -Command "Get-ChildItem -Recurse -Filter *.ps1 | % { `$e=`$null; [void][System.Management.Automation.Language.Parser]::ParseFile(`$_.FullName,[ref]`$null,[ref]`$e); if (`$e) { `$_.Name } }" }
  ```
  No output means every file parses.
- **Run the tools after any "lint fix"** and check their verdicts did not change (see
  [docs/lessons-learned.md](docs/lessons-learned.md): a suggested refactor once made every font "fail").
- `.ps1` files: CRLF (enforced by `.gitattributes`); ASCII only, or a UTF-8 BOM if non-ASCII text is needed.
- PowerShell variables are case-insensitive: never use two names that differ only by case (`$State` vs `$state`).
- Python tools: fontTools-based, Python 3.12+, deps in `build/requirements.txt`.
- macOS build scripts are bash, run on a Mac.
- Commits: small and descriptive, one concern each.

## Common tasks

| Task | How |
|---|---|
| Is everything still applied? | `.\status.ps1` |
| New macOS with new emoji or SF fonts | [docs/rebuild.md](docs/rebuild.md), then a new release `vX.Y.Z` |
| Windows update broke it | `status.ps1`; if `[DIFF]`, uninstall + install (ask the user first) |
| Change install behavior | Edit `install.ps1`, `uninstall.ps1` or `scripts/*.ps1`; parse-check both PowerShells; run `sandbox\start-rehearsal.ps1 -Mode Scripts` until `SCRIPT TEST PASSED`; update README, docs and CHANGELOG |
