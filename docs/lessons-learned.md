# Lessons learned (read before changing the build or the scripts)

Each of these cost real debugging time. They are why the code looks the way it does.

## Font building

- **Do not remove overlaps when instancing** (`instancer.OverlapMode.REMOVE`). Skia path-ops
  mangled SF Arabic glyphs (`ع` final form lost half its ink at weight 700, visible in Bold). Use
  `KEEP_AND_SET_FLAGS`; Windows rasterizers handle overlapping contours fine.
- **ttfautohint `hint_composites=True` corrupts GPOS** (it appends a glyph, which shifts anchor offsets;
  OTS: "Bad Anchor table format"). Keep it off. The build now refuses to continue if hinting changes
  the glyph order or any layout table.
- **Apple's `head.fontRevision` is meaningless** (often 1.0 or 0.0). Compare versions with the
  `name` ID 5 string (`Version 22.0d5e4`).
- **macOS system fonts are not usable on Windows**: `/System/Library/Fonts/SFNS.ttf`, `SFHebrew.ttf`
  and the rest are hidden (`.SF NS`, `.New York`), and the script ones are small helper subsets that rely
  on SFNS for Latin (SF Hebrew has 168 glyphs vs 455). Use Apple's developer downloads.
- **fontTools `Merger` leaves script/feature records unsorted.** The spec needs them sorted by tag
  (engines binary-search them). `sort_layout()` re-sorts and remaps feature indices.
- Stylistic-set names (`FeatureParams` `UINameID`) point into Apple's `name` table, which is replaced
  by Segoe's, so they are stripped.
- Gap-filled Segoe glyphs need an empty `gvar` entry in the variable font, and `HVAR` is dropped
  (its glyph-indexed width map does not cover new glyphs; it is optional).

## Installing on Windows

- **Do not overwrite `seguiemj.ttf`** (or any Segoe file). It is always in use and owned by
  TrustedInstaller. A `MoveFileEx(DELAY_UNTIL_REBOOT)` swap is silently dropped at boot when the
  file's original ACL is restored first (SYSTEM only has read access). Repointing the registry entry
  avoids all of it.
- **PowerShell variable names are case-insensitive**: `$State` (a path) and `$state` (the data) were
  the same variable and corrupted the state file. The path is now `$StatePath`.
- `Start-Process -PassThru` + `WaitForExit(ms)`: read `$p.Handle` first, or `ExitCode` comes back empty.
- PowerShell 5.1 turns a native tool's stderr into a terminating error under
  `$ErrorActionPreference = 'Stop'`. `reg export` of a missing key aborted the install, so it runs through `cmd /c`.
- `Checkpoint-Computer` only allows one restore point per 24 h and only *warns* otherwise.
- Never leave a step that can hang without a timeout (`Invoke-Tool`).
- Scripts with non-ASCII text need a UTF-8 BOM for Windows PowerShell 5.1.
- **Record before you change.** Writing `state.json` *after* a registry change leaves a window where a
  crash makes the change unrecoverable. Every step now records first, then acts, and `-Resume` re-applies
  recorded steps. A pre-flight finds all conflicts before the first change.
- **`$null` is not null for .NET string arguments.** `[IO.File]::Replace($a, $b, $null)` and
  `MoveFileEx($p, $null, ...)` receive `""` and fail. Pass `[NullString]::Value`.
- **A function's output is unrolled.** `$x = Get-Items $list` gives `$null` for 0 items and a single
  object for 1, not a list. Windows PowerShell 5.1 then writes the empty list to JSON as `{}` (restore
  rejected the state) and `+=` on the single object fails. Wrap it: `@(Get-Items $list)`. PowerShell 7
  hides the first half of this, so test on 5.1 too. The Sandbox script test caught it.
- Write `state.json` to a temp file and swap it in (`[IO.File]::Replace`): a power cut mid-write must not
  corrupt the only record of what to undo. The backup folder is admin-only, because the elevated
  restore trusts its contents (and validates them anyway: `Assert-SafeState`).
- Windows Sandbox: a `.wsb` cannot use relative paths (`start-rehearsal.ps1` generates it).
  An in-sandbox restart did not reliably resume the logon script, so script correctness is tested by
  `start-rehearsal.ps1 -Mode Scripts` (no restarts); the full mode is for screenshots.
- **The sandbox shares the host's Windows files but not its registry.** If the host has SF fonts
  installed, the sandbox sees the files in `C:\Windows\Fonts` without registry entries, which is
  exactly the "file present but not registered" case the installer must handle (it registers them,
  records `KeepFile`, and uninstall removes only the registry entry).
- **Test as a standard user, not only as administrator.** Everything in the Sandbox test once ran
  elevated, so it missed that an administrators-only backup folder made `Status.cmd` report "Not
  installed" and broke the Settings uninstall (Settings starts it unelevated). The test now also runs
  steps with `runas /trustlevel:0x20000`.
- **`%ProgramData%` is writable by standard users** (they can create folders). Any folder there that
  elevated code trusts must be checked recursively (owner, permissions, links) or created fresh.
- `Get-Acl` owners: files created elevated are owned by Administrators (unless the "object creator"
  policy is set); a standard user's own folder keeps them as owner, and the owner can always change
  the permissions.
- **Windows Sandbox file-system quirk:** in a folder re-created right where one was moved aside, a name
  that was just renamed away (`state.json.tmp` -> `state.json`, `state.json` -> `state.restored-*.json`)
  could not be created again ("Could not find file" / "file already exists"). Real NTFS does not do this;
  `Save-State` uses a new temp name every time anyway.

## Validating

- ClearType is disabled on 32-bit **alpha** bitmaps. GDI specimen sheets must use 24-bit bitmaps or a
  DIB section, or every renderer looks greyscale and smudged.
- At 100 % scale Arabic marks are 1–2 px and look missing in any font; check at the real UI size
  (a 4K display at 175 % scaling gives UI text of about 21 px).
- A render test that never fails proves nothing. `render_all_glyphs.py --reference` exists for the
  positive control.
- **Run the tools after "lint fixes".** Ruff's SIM118 suggests `for tag in font` instead of
  `font.keys()`, but a fontTools `TTFont` is not iterable over its tags: every font then "failed" with
  `KeyError('0')`.
- `validate_ui_fonts.py` must not count the fonts under test as their own fallback: with the install
  active, the registry points at the `SFUI-*` files, which are skipped explicitly.

## Build scripts

- Resolve output paths to absolute **before** any `cd` (`build_emoji.sh` once wrote its result into a
  temp folder that the exit trap then deleted, and still printed success).
