# How it works

## What Windows 11 uses for its interface

| Family | File(s) | Used by |
|---|---|---|
| **Segoe UI** | 12 static files: `segoeuil` Light, `segoeuisl` Semilight, `segoeui` Regular, `seguisb` Semibold, `segoeuib` Bold, `seguibl` Black, plus the 6 italics | Classic Win32: title bars, menus, dialogs, Control Panel, most desktop apps, browser UI. Also what Windows falls back to for Arabic and Hebrew. |
| **Segoe UI Variable** | `SegUIVar.ttf` (variable: `wght` 300–700, `opsz` 5–36, 15 named instances Small/Text/Display) | WinUI / XAML: Start, Taskbar, **Search panel**, Settings, new File Explorer, Notepad. The Search panel's web UI asks for `"Segoe UI Variable Text"`, `"Segoe UI Variable Small"` and `"Segoe UI"`. |
| **Segoe UI Emoji** | `seguiemj.ttf` | Every emoji, in every app |
| Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol | icon fonts | **Left untouched.** Replacing them turns icons into squares. |

## The approach: repoint, don't overwrite

Windows only knows a font is installed through the registry
(`HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`). Each entry maps a face name to a file.
The installer:

1. copies each replacement in as a **new file** (`SFUI-segoeui.ttf`, `SFUI-SegUIVar.ttf`, `SFUI-seguiemj.ttf`, …)
2. points the **existing** entry (for example `"Segoe UI (TrueType)"`) at the new file
3. records the old value in `state.json`

The original Segoe files stay on disk, unmodified. That means:

- `sfc /scannow` and Windows Update see nothing damaged
- undo is just putting the registry values back
- nothing has to be swapped while Windows has the file open

A per-user copy of a family (`HKCU\...\Fonts`) wins over the system one, so a per-user
"Segoe UI Variable" registration is unregistered too (the file is kept, and the entry is recorded and restored on undo).

## Why the replacement fonts are *built* and not just SF Pro

The common community trick (`FontSubstitutes "Segoe UI"="SF Pro Text"`) is known to give broken
bold and leaves Start/Settings/Search on Segoe ([Microsoft Q&A report](https://learn.microsoft.com/en-us/answers/questions/3919601/bold-font-rendering-issue-after-replacing-segoe-ui)).
The cause: Windows asks for *"Segoe UI, weight 700"* and the substituted font's own names and
style bits do not match, so Windows guesses or synthesizes bold.

Each built file instead carries **Segoe's exact identity** around Apple's glyphs:

| Copied from the Segoe file it replaces | Kept from Apple |
|---|---|
| Entire `name` table (family, style, full and PostScript names, every language) | All glyph outlines (verified point-identical) |
| `OS/2` weight class, `fsSelection`, `fsType`, PANOSE | Glyph widths and kerning |
| Line metrics: `usWinAscent/Descent`, `sTypo*`, `hhea` ascent/descent/lineGap | OpenType layout (GSUB/GPOS): ligatures, Arabic joining, marks |
| `head.macStyle`; for Segoe UI Variable the `fvar` axes, 15 named instances and `STAT` | Variation data (Segoe UI Variable build) |

So Windows always finds the exact face it asked for, and line heights match Segoe, so nothing is clipped or misaligned.

### Segoe UI (12 static faces)

- **SF Pro** pinned at optical size 17 (*SF Pro Text*, what macOS uses for UI-size text), width 100,
  at each Segoe weight (300/350/400/600/700/900). Italics come from **SF Pro Italic**.
- Merged in, for scripts Segoe UI covers and SF Pro does not: **SF Arabic**, **SF Hebrew**,
  **SF Armenian**, **SF Georgian** (same weight, opsz 17). Arabic is Apple-styled everywhere.
- **Gap-fill:** 14–20 everyday characters SF Pro lacks but Segoe has (for example soft hyphen, `ŉ`,
  `―`, `‗`, `‛`, `‟`, a few currency signs, Arabic `؝`) are copied from Segoe's own glyph,
  so they never fall back to another font or become squares.
- **Hinting:** `ttfautohint` (with `hint_composites` off: on, it corrupts GPOS anchors), so text stays crisp in classic GDI apps.
- Overlapping contours are **kept** (removing them damaged some SF Arabic glyphs, for example `ع`).

### Segoe UI Variable

SF Pro variable, `wdth` pinned to 100, `wght` limited to 300–700, `opsz` limited to 17–28 with the
default moved to 17. The axes are then presented in Segoe's user space (`opsz` 5 → 10.5 → 36,
`wght` 300 → 400 → 700) with Segoe's 15 named instances and `STAT`, so XAML's requests for
*Small*, *Text* and *Display* map to SF Text through SF Display, the way macOS switches optical sizes.

### Segoe UI Emoji

Apple Color Emoji built by [samuelngs/apple-emoji-ttf](https://github.com/samuelngs/apple-emoji-ttf)
(Windows recipe: Segoe UI Emoji names and metrics, CBDT color bitmaps) from macOS 27's own font,
installed the same way as the UI fonts: as `SFUI-seguiemj.ttf`, with the "Segoe UI Emoji"
registry entry pointed at it.

## What install and restore do, step by step

`scripts/install-macos-fonts.ps1` (started by `install.ps1`):

1. Verify every font against `fonts/SHA256SUMS.txt` and `fonts/ui/SHA256SUMS.txt`. Any mismatch stops it before anything changes.
2. **Pre-flight**: find every conflict before the first change: a different font file with the same
   name already in `C:\Windows\Fonts`, a font name already registered to another file, a missing
   Segoe registry entry, or a previous uninstall whose file deletions are still waiting for a restart.
3. Safety nets: System Restore point (when System Protection is on; Windows allows one per 24 h),
   exports of the HKLM and HKCU font keys, `state.json`.
4. Install the 155 SF / New York fonts as new fonts. A byte-identical SF font that is already
   installed is left alone (if it was only unregistered, just its registry entry is added and later removed).
5. Repoint the 13 Segoe UI / Segoe UI Variable entries and unregister per-user overrides.
6. Repoint Segoe UI Emoji.
7. Clear the font cache (FontCache service data and `FNTCACHE.DAT`), then ask for a restart.

Every change is **recorded in `state.json` before it is made**, and every copied file is checked
against its checksum. `state.json` is written atomically, so a power cut cannot leave it half-written.
An interrupted run can therefore be finished (`install.ps1 -Resume`, which also remembers
`-SkipUI` / `-SkipEmoji`) or fully undone (`uninstall.ps1`).

`scripts/restore-macos-fonts.ps1` (started by `uninstall.ps1`) reverses exactly what `state.json`
records. It refuses a `state.json` with unexpected entries, carries on past individual failures and
reports them (re-running retries them), and schedules files that are still in use for deletion at the
next restart.

Backups and logs: `%ProgramData%\AppleFontsOnWindows\`, readable and writable by administrators only
(the elevated scripts trust `state.json`). Use `-BackupDir` on install, status and uninstall to use
another folder.
