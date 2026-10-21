# AGENTS.md: must read before changing anything

Rules for AI coding agents (Claude Code, Codex, Copilot, Cursor and others) and for humans working
like one. **Read this whole file before your first edit.** This project changes how Windows finds its
system fonts on other people's PCs, as administrator. A careless change can leave a PC with blank text,
squares instead of letters, or a broken uninstall. Every rule below exists because of a real failure or
a real risk; [docs/lessons-learned.md](docs/lessons-learned.md) has the stories.

Then read [README.md](README.md), [docs/how-it-works.md](docs/how-it-works.md) and
[docs/lessons-learned.md](docs/lessons-learned.md). Rules are numbered (W1, S2, ...) so reviews, commit
messages and CI can point at them. CI enforces the ones marked *(CI)*.

## What this project is

It makes Windows 11 use Apple's fonts: Segoe UI / Segoe UI Variable → SF Pro (+ SF Arabic, Hebrew,
Armenian, Georgian), Segoe UI Emoji → Apple Color Emoji, and it installs the 155 SF / New York fonts.
It works by **adding** new font files (`SFUI-*.ttf`, `SF-*.ttf/otf`, `NewYork*`) to `C:\Windows\Fonts`
and **repointing** Windows' existing registry entries at them. Every change is recorded in `state.json`
before it is made, and `uninstall.ps1` (or Settings > Apps > Installed apps) undoes exactly that.
It is for **any Windows 11 PC, any language, any folder, and any user**, including non-technical ones
who double-click `Install.cmd`.

---

## W. Windows anti-corruption rules (never break these)

**What the install may change: the complete list.** Anything not on it is off-limits. Extending it needs
the owner's approval, an `Assert-SafeState` allowlist update, a matching restore step, and a Sandbox test.

| May change | Exactly what |
|---|---|
| `C:\Windows\Fonts` | **add** files named `SFUI-<one of the 13 Segoe UI files or seguiemj.ttf>`, `SF-*.ttf/otf`, `NewYork*.ttf/otf`; delete only those files, on uninstall |
| `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts` | add values for the SF / New York fonts; **set** the values of the 13 Segoe UI / Segoe UI Variable entries and the Segoe UI Emoji entry to their `SFUI-` files; put the recorded originals back on uninstall |
| `HKEY_USERS\<signed-in user>\...\Windows NT\CurrentVersion\Fonts` | remove (recorded) per-user registrations of the same Segoe UI families; put them back on uninstall |
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\AppleFontsOnWindows` | the Installed apps entry |
| `%ProgramData%\AppleFontsOnWindows` (or `-BackupDir`) | state, logs, registry exports, the uninstaller copy |
| Font cache | stop the FontCache service and delete its cache files (Windows rebuilds them) |
| System Restore | one restore point, "Before macOS fonts" |
| `%LOCALAPPDATA%\AppleFontsOnWindows` | `get.ps1` only, as the signed-in user: the downloaded copy of the project, one folder per version |
| `PendingFileRenameOperations` | delete-at-restart of the install's own font files only (`MoveFileEx`) |

- **W1. Never modify, overwrite, rename, move or delete a Windows font file** (`segoe*`, `segui*`,
  `SegUIVar.ttf`, `seguiemj.ttf`, or any font the install did not add). Repoint the registry entry at a
  new file instead. Overwriting `seguiemj.ttf` already failed once: it is always in use and owned by
  TrustedInstaller.
- **W2. Never touch icon or symbol fonts:** Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol,
  Marlett, Wingdings, or any font used for glyph icons. Changing them turns buttons into wrong
  characters.
- **W3. Never write to other font settings:** `FontSubstitutes`, `FontLink\SystemLink`, `FontMapper`,
  `GRE_Initialize`, `Font Management`, `FontDPI`, the console font keys (`HKCU\Console`,
  `...\Console\TrueTypeFont`). Read them if needed, for example to warn (the installer warns about a
  Segoe UI `FontSubstitutes` entry). *(CI)*
- **W4. Never delete or recreate a whole registry key** that Windows owns. Change single values that
  the install recorded. *(CI: no `Remove-Item` on registry paths except the project's own Uninstall key)*
- **W5. Never take ownership of, or change the permissions on, anything Windows owns:** no `takeown`,
  no `icacls`, and no `Set-Acl` outside the project's backup folder. *(CI)*
- **W6. Never install drivers, services, scheduled tasks, startup items, Run keys, shell extensions,
  or anything that runs later.** Nothing from this project may run at startup. *(CI)*
- **W7. Never touch boot, recovery or servicing:** `bcdedit`, `reagentc`, `sfc /scannow`
  repairs, `DISM /RestoreHealth`, `vssadmin delete`, component store, Windows Update settings.
  *(CI)*
- **W8. Find Windows' entries by file name, never by display name or position.** Display names differ
  between Windows builds; the file name (`segoeui.ttf`) does not. Refuse (with "Nothing was changed")
  when an expected entry is missing, duplicated or unexpected. Never guess.
- **W9. Never hard-code `C:\`, `C:\Windows`, a user name, a drive letter or a locale.** Use
  `$env:WINDIR`, `$env:SystemRoot`, `$env:ProgramData`, `$PSScriptRoot`, and SIDs for users.
- **W10. Find every conflict in the pre-flight, before the first change.** If anything stops the install
  after a change, it must be because Windows failed, never because a check came too late.
- **W11. Record before you change.** Every change is written to `state.json` before it is made
  (`Save-State`: atomic, with a new temp name each time). Uninstall undoes exactly what is recorded.
  An interrupted install must be both resumable (`-Resume`) and fully undoable. Restore continues past
  individual failures and keeps `state.json` until everything is undone.
- **W12. `state.json` stays minimal and is validated.** Anything new written to it must also be
  allowed, and nothing more, by `Assert-SafeState` in `scripts/backup-location.ps1`, with a test in
  `tests/state-and-folder.tests.ps1`. A tampered `state.json` must not be able to make the elevated
  uninstall touch anything outside the table above.
- **W13. Verify every font before it touches Windows:** SHA-256 against the checksums tracked in git
  (`fonts/**/SHA256SUMS.txt`), again after copying (`Copy-Verified`). Checksum files come from git,
  never from a download.
- **W14. Leave Windows usable at every point.** No step may leave a Segoe entry pointing at a missing
  file. Copy the new file first, verify it, then change the registry value.
- **W15. Every external tool call has a timeout** (`Invoke-Tool`, or a job with `Wait-WithTimer`). A
  hang must become a clear error, not a frozen window.
- **W16. Undo must always be possible:** the Installed apps entry, `Uninstall.cmd`, a restore point
  (when System Protection is on) and registry exports. Never remove one of these safety nets.

## S. Security rules (the scripts run as administrator)

- **S1. Elevated code must not trust anything a standard user can change.** That includes the project
  folder, a custom `-BackupDir`, `%TEMP%`, and `%ProgramData%` (standard users can create folders
  there). The backup folder goes through `Protect-BackupDir`: administrators only for writing,
  everyone for reading, and a folder someone else created first is set aside.
- **S2. File paths always use `-LiteralPath`** (`[` `]` are wildcards in `-Path`). No temp files with
  predictable names in shared folders.
- **S3. No `Invoke-Expression`, no `Add-Type` with downloaded or user-provided source, no
  `-EncodedCommand`, no `iex (irm ...)` one-liners** in the product scripts. *(CI)* The one approved
  exception is the README's paste-in line, `irm .../releases/latest/download/get.ps1 | iex`, which runs
  `get.ps1`; `get.ps1` itself follows every rule here.
- **S4. Download only from this repository's GitHub Releases over HTTPS**, only the files named in the
  code, and only for the release in `fonts/release.txt`. Unpack into a scratch folder and copy out only
  the files listed in the tracked checksums. `get.ps1` downloads only the source ZIP of its own release
  tag. No other network endpoints, telemetry, or update checks.
  *(CI: no other URLs in the product scripts)*
- **S5. Launch Windows tools by full path** (`$env:SystemRoot\System32\...`). The `.cmd` launchers
  start `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`.
- **S6. Per-user changes go to the signed-in user's hive** (`HKEY_USERS\<SID>`, passed from the
  unelevated stage as `-UserSid`), not to `HKCU` of the account typed at the UAC prompt.
- **S7. No secrets or personal data in the repo:** no IP addresses, host names, SSH or API keys, e-mail
  addresses, user names, or personal paths. Check before every push:
  `git grep -nE "([0-9]{1,3}\.){3}[0-9]{1,3}|BEGIN (OPENSSH|RSA)|C:\\Users\\[A-Za-z]" $(git rev-list origin/main..HEAD) -- .`

## P. PowerShell engineering rules

- **P1. Everything runs on Windows PowerShell 5.1 and PowerShell 7.** Users get 5.1 (the launchers);
  test both. *(CI parses with both)*
- **P2. No two variable names that differ only by case.** `$State` and `$state` are the same variable;
  this once corrupted `state.json`. *(CI)*
- **P3. A function's output is unrolled.** Zero items give `$null` and one item gives a scalar, not a
  list. Wrap it, `@(Get-Items $x)`, before `+=` or saving to JSON. PowerShell 5.1 then writes an empty
  list as `{}`.
- **P4. `$null` passed to a .NET string parameter becomes `""`.** Use `[NullString]::Value`.
- **P5. `.ps1` files: CRLF line endings, ASCII only** (or UTF-8 with a BOM). Write non-ASCII characters
  as `[char]0x....`. *(CI)*
- **P6. Entry scripts reset `PSModulePath`** for Windows PowerShell (keep the block at the top of
  `install.ps1`, `uninstall.ps1`, `status.ps1`). Started from a PowerShell 7 window, 5.1 otherwise
  cannot load `Get-FileHash`, `Expand-Archive` or `Get-Acl`.
- **P7. `$ErrorActionPreference = 'Stop'`, errors as `throw` with a message a user can act on, and
  `exit` codes only in entry scripts.** Inner scripts throw; entry scripts catch, explain, pause when
  the window would close, and `exit 1`.
- **P8. Transcripts:** start them before the first real work, log the error and stack trace in `catch`,
  stop them in `finally`.
- **P9. No aliases (`%`, `?`, `gci`, `iwr`) in product scripts.** Install and uninstall text goes
  through `scripts/ui.ps1` (`Write-Step`, `Write-Ok`, `Write-Info`, `Write-Warn`, `Write-Detail`,
  `Show-Progress`, `Wait-WithTimer`) so both windows look the same; `status.ps1` prints its report
  lines directly. *(CI: aliases)*
- **P10. Progress bars:** update every few items, not every item (it is slow on 5.1). Silence
  cmdlets' own bars where ours is shown, and always `Hide-Progress` before printing an error.
- **P11. Store plain values.** A string from `Get-Content` carries extra properties that Windows
  PowerShell's `ConvertTo-Json` writes out as an object. Use `"$(Get-Content ...)".Trim()` for anything
  that goes into `state.json` or the registry.

## U. User experience rules

- **U1. Write for someone who double-clicked `Install.cmd`:** say what happened, whether anything was
  changed, and what to do next, in plain words. No stack traces or PowerShell jargon on screen; those
  go to the log.
- **U2. Every new message a user can see gets a README troubleshooting row.**
- **U3. Never let a window close on an error unread:** the launchers pause on any non-zero exit, and
  the elevated window pauses before closing.
- **U4. Long steps show progress:** a numbered step, a bar or a seconds counter, and a tick when done.
- **U5. Keep `Status.cmd` read-only and runnable without administrator rights.** Exit codes: 0 in
  place, 1 differs, 2 not installed.

## T. Testing: definition of done

Nothing is done until all of these pass, and you say which ones you ran:

1. **Parse** with both `powershell.exe` and `pwsh.exe` (one-liner below), and the variable-casing check.
2. **Unit tests:** `tests\state-and-folder.tests.ps1` on both PowerShells, with `ALL PASSED`.
3. **Windows Sandbox functional test:** `.\install.ps1 -DownloadOnly` once, then
   `sandbox\start-rehearsal.ps1 -Mode Scripts`, which must end with `SCRIPT TEST PASSED`. Add checks for
   your change to `sandbox/script-test.ps1`, including the standard-user path
   (`Run-AsStandardUser`) when it matters.
4. **Visual check** for anything shown on screen: run it in a real window (`-DownloadOnly`, or a demo
   that changes nothing) and look at it.
5. **CI green** on GitHub, including *Release assets* when fonts or the download changed.
6. **For font changes:** the full validation suite in [docs/validation.md](docs/validation.md)
   (`validate_ui_fonts.py` with `ALL HARD CHECKS PASSED`, `render_all_glyphs.py` with 0 blank,
   `winload.ps1` with all fonts loaded, and the specimen sheets, Arabic in particular). **Never weaken a
   check to make it pass.** After a "lint fix", run the tools again and compare their verdicts.
7. **Never test on a real PC** unless its owner says so explicitly. Test in Windows Sandbox.

```powershell
foreach ($exe in 'powershell.exe','pwsh.exe') { & $exe -NoProfile -Command "Get-ChildItem -Recurse -Filter *.ps1 | % { `$e=`$null; [void][System.Management.Automation.Language.Parser]::ParseFile(`$_.FullName,[ref]`$null,[ref]`$e); if (`$e) { `$_.Name } }" }
```
No output means every file parses.

## F. Font rules

- **F1. Font binaries never go into git.** They are GitHub Release assets. `fonts/**/SHA256SUMS.txt`
  and `fonts/release.txt` are tracked and are the integrity anchor. *(CI)*
- **F2. Build rules:** no overlap removal (`OverlapMode.REMOVE` damaged SF Arabic), and no
  `hint_composites=True` (it corrupted GPOS). Keep Segoe's names, metrics and axes. Fill missing
  characters from Segoe so nothing becomes a square. *(CI)*
- **F3. Respect the licenses:** never redistribute fonts outside this project's release assets, and keep
  the disclaimer at the top of the README.

## R. Release and git rules

- **R1. `VERSION`** is the scripts' version (shown in Installed apps and Status). Bump it and move the
  CHANGELOG `[Unreleased]` section for every release.
- **R2. `fonts/release.txt` names the release the fonts are downloaded from.** Publish a new font
  release with its assets **before** pushing the commit that points at it
  ([docs/rebuild.md](docs/rebuild.md)).
- **R3. Small commits, one concern each, with a message saying what and why.** Update README, docs and
  CHANGELOG in the same change as the behavior.
- **R4. Push, tag, release, force-push or rewrite history only when the owner asks.** Never force-push
  `main` on your own initiative.
- **R5. Never delete or replace published release assets.** Existing installs and old checkouts
  download from them.
- **R6. Every release attaches `get.ps1` from its tagged commit** (`gh release upload vX.Y.Z get.ps1`),
  with `$Tag` set to `v` + `VERSION` *(CI)*. The paste-in line always runs the latest release's
  `get.ps1`, so a release without it breaks the README's first install method *(CI, weekly)*.
  Test a changed `get.ps1` with `sandbox\start-rehearsal.ps1 -Mode PasteIn` before the release, and
  with `-Mode PasteIn -Release` after it.

## When in doubt

Stop and ask the owner. In particular, ask before:
- adding anything to the "may change" table;
- touching anything elevated that you cannot test in Windows Sandbox;
- changing `Assert-SafeState`, `Protect-BackupDir` or the restore;
- running anything elevated on a real PC.

A missing feature is fine. A PC with broken fonts is not.

## Where things live

| Path | What |
|---|---|
| `Install.cmd`, `Uninstall.cmd`, `Status.cmd` | double-click launchers (users start here) |
| `get.ps1` | the paste-in loader, attached to every release: downloads that release and runs `Install.cmd` |
| `install.ps1`, `uninstall.ps1`, `status.ps1` | entry scripts: checks, download, elevation, summary |
| `scripts/install-macos-fonts.ps1` | the elevated installer (steps 4-7) |
| `scripts/restore-macos-fonts.ps1` | the elevated restore |
| `scripts/backup-location.ps1` | backup folder, its protection, `Assert-SafeState` allowlists |
| `scripts/checks.ps1` | Windows 11 and folder-location checks |
| `scripts/ui.ps1` | everything the windows show |
| `tests/` | unit tests (CI) |
| `sandbox/` | Windows Sandbox functional test and visual rehearsal |
| `build/`, `validation/` | font build (Mac) and validation tools |
| `docs/lessons-learned.md` | every past mistake, read before repeating one |
