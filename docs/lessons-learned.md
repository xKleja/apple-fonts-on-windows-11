# Lessons learned (read before changing the build or the scripts)

Each of these cost real debugging time. They are why the code looks the way it does.

## Font building

- **Do not remove overlaps when instancing** (`instancer.OverlapMode.REMOVE`). Skia path-ops
  mangled SF Arabic glyphs (`ع` final form lost half its ink at weight 700, visible in Bold). Use
  `KEEP_AND_SET_FLAGS`; Windows rasterisers handle overlapping contours fine.
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
- Windows Sandbox: a `.wsb` cannot use relative paths (`start-rehearsal.ps1` generates it), and its
  `LogonCommand` runs again after an in-sandbox restart (`rehearsal.ps1` uses per-phase lock files).

## Validating

- ClearType is disabled on 32-bit **alpha** bitmaps. GDI specimen sheets must use 24-bit bitmaps or a
  DIB section, or every renderer looks greyscale and smudged.
- At 100 % scale Arabic marks are 1–2 px and look missing in any font; check at the real UI size
  (the original PC runs 4K at 175 %, so UI text is about 21 px).
- A render test that never fails proves nothing. `render_all_glyphs.py --reference` exists for the
  positive control.
