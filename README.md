> [!WARNING]
> **Educational and experimental project — use at your own risk.**
> This project is provided for educational, research, and demonstration purposes only, **as is**, without any warranties or guarantees. Installing fonts or changing Windows font settings may cause compatibility issues, instability, or data loss; you assume all risks and responsibility for your actions.
>
> Apple, San Francisco (SF), New York, and Apple Color Emoji are trademarks or proprietary materials of their respective owners; Segoe UI and Windows belong to Microsoft. This project is **not affiliated with, endorsed by, or sponsored by Apple Inc. or Microsoft Corporation**. No intellectual-property rights or permission to download, copy, modify, distribute, or use proprietary fonts are granted here.
>
> **You are responsible for complying with all applicable laws and font license agreements.** In particular, Apple's font licenses may restrict modification, redistribution, and use on non-Apple platforms, even for personal or educational purposes. Calling a project “educational” or using it privately does **not** override those restrictions. Do not use or distribute any font unless you have the necessary rights.

---

# Apple fonts on Windows 11

Make Windows 11 look and read like macOS: **SF Pro** as the system UI font (Start, Taskbar, Search,
Settings, File Explorer, dialogs, every app's menus), **SF Arabic** for Arabic UI text,
**Apple Color Emoji** everywhere, and the full **SF / New York** families installed for apps.
English and Arabic are first-class.

One command installs it, one command undoes it, and no Windows font file is modified.

## Contents

- [What you get](#what-you-get)
- [Requirements](#requirements)
- [Install](#install)
- [Check that it worked](#check-that-it-worked)
- [Uninstall](#uninstall)
- [After Windows updates](#after-windows-updates)
- [Troubleshooting](#troubleshooting)
- [Safety and backups](#safety-and-backups)
- [What is in this release](#what-is-in-this-release)
- [Repository layout](#repository-layout)
- [How it works (short version)](#how-it-works-short-version)
- [Rebuilding for a new macOS](#rebuilding-for-a-new-macos)
- [License](#license)

---

## What you get

| Where | Before | After |
|---|---|---|
| Start, Taskbar, **Search panel**, Settings, new File Explorer, Notepad (modern UI) | Segoe UI Variable | **SF Pro** (Text and Display optical sizes, like macOS) |
| Title bars, menus, dialogs, Control Panel, browser UI, most desktop apps (classic UI) | Segoe UI | **SF Pro Text**, every weight Light → Black plus italics |
| Arabic (and Hebrew, Armenian, Georgian) in the UI | Segoe UI | **SF Arabic** / SF Hebrew / SF Armenian / SF Georgian |
| Emoji in every app | Segoe UI Emoji | **Apple Color Emoji** (macOS 27), about 700 more emoji than Windows has |
| Fonts you can pick in Word, Figma, VS Code, … | — | SF Pro, SF Pro Rounded, SF Compact, SF Mono, New York, SF Arabic/Hebrew/Armenian/Georgian (155 files) |

Not changed: icon fonts (Segoe Fluent Icons, MDL2 Assets, UI Symbol), document fonts (Calibri,
Aptos, Times…), and the console / code fonts.

## Requirements

- Windows 11, tested on 25H2 (build 26200). Other Windows 11 builds, Windows 10, ARM64 PCs and
  non-English Windows editions are untested.
- An administrator account (you will click **Yes** on one UAC prompt)
- An internet connection for the first run (the fonts are downloaded from the release over HTTPS;
  no GitHub account or tools needed)
- Free space: about 2 GB on the drive holding this folder (0.7 GB download, deleted after unpacking,
  plus 1 GB of unpacked fonts) and about 1 GB on the Windows drive for the installed fonts

## Install

```powershell
git clone https://github.com/xKleja/apple-fonts-on-windows-11.git
cd apple-fonts-on-windows-11
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

No Git? Download the repository as a ZIP from the green **Code** button, unpack it, and run the last
line from inside the unpacked folder.

What happens:

1. The three font zips are downloaded from the [latest release](../../releases/latest), verified (SHA-256), and unpacked into `fonts\`.
2. A **UAC prompt** appears. Click **Yes**.
3. In the elevated window, every font is checked again against the checksums in git, every possible
   conflict is checked before anything changes, a restore point and backups are made, then the fonts are installed and Windows' Segoe UI / Segoe UI Variable /
   Segoe UI Emoji entries are pointed at the Apple builds.
4. It asks to **restart**. Say yes, because running apps only pick up a system font change after a restart.

Options:

| Command | Effect |
|---|---|
| `.\install.ps1 -SkipEmoji` | UI fonts + SF fonts, keep Windows emoji |
| `.\install.ps1 -SkipUI` | SF fonts + emoji, keep Segoe UI as the system font |
| `.\install.ps1 -Resume` | Finish an install that was interrupted (power loss, closed window…) |
| `.\install.ps1 -DownloadOnly` | Only download, verify and unpack the fonts. Windows is not touched. |
| `.\install.ps1 -Tag v1.0.0` | Install a specific release instead of the latest |
| `.\install.ps1 -NoRestartPrompt` | Do not ask about restarting |
| `.\install.ps1 -NoRestorePoint` | Skip the System Restore point |
| `.\install.ps1 -BackupDir <path>` | Keep state, logs and registry backups somewhere else (pass the same `-BackupDir` to `status.ps1` and `uninstall.ps1`) |

`-Resume` remembers `-SkipUI` / `-SkipEmoji` from the interrupted run, and `status.ps1` only checks the
parts that were installed.

Offline install: download `fonts-sf.zip`, `fonts-ui.zip`, `fonts-emoji.zip` from the
release page, unzip all three into `fonts\` (giving `fonts\SF\`, `fonts\ui\`, `fonts\emoji\`), then run `.\install.ps1`.
It sees the fonts are present and skips the download.

## Check that it worked

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1
```

```
[OK]   Segoe UI                    -> SFUI-SEGOEUI.TTF     Version 5.72; SF Pro 22.0d5e4 (Apple)
[OK]   Segoe UI Variable Text      -> SFUI-SEGUIVAR.TTF    Version 2.03; SF Pro 22.0d5e4 (Apple)
[OK]   Segoe UI Emoji              -> SFUI-SEGUIEMJ.TTF    Version 1.60
...
  13/13 UI font files match
Everything is in place.
```

By eye: open Start and type in Search, open Settings, and type `😀 👍🏽 🇪🇬` in Notepad.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Click **Yes** on UAC, then restart. Windows is back to Segoe UI / Segoe UI Variable / Segoe UI Emoji
and the SF / New York fonts are removed. It reverses exactly what the install recorded, nothing more.

## After Windows updates

A big Windows feature update can re-register its own fonts and undo part of this. Run `.\status.ps1`
after updates. If anything shows `[DIFF]`:

```powershell
.\uninstall.ps1      # restart
.\install.ps1        # restart
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| UI still looks like Segoe right after installing | Restart Windows (not just sign out). Then run `.\status.ps1`. |
| Emoji are still Windows emoji | Same: restart. `status.ps1` should show `Segoe UI Emoji -> SFUI-SEGUIEMJ.TTF`. |
| `Download of ... failed` | Check the internet connection (and any proxy), then run `install.ps1` again. Or use the offline install above. |
| `Checksum mismatch` / `Missing font` | A font file changed or a download got corrupted. Delete `fonts\SF`, `fonts\emoji` and the `*.ttf` in `fonts\ui`, then run `install.ps1` again. |
| `Already installed (found ...state.json)` | It is installed. Use `uninstall.ps1` first, or `install.ps1 -Resume` if the last run was interrupted. |
| `Nothing to resume: the install ... is complete` | The last install finished; there is nothing for `-Resume` to do. Check it with `status.ps1`. |
| `C:\Windows\Fonts already has a different SF-Pro.ttf` (or another SF font), or `The font name ... is already registered` | Another copy of that SF font is installed. Uninstall it (Settings > Personalization > Fonts), then run `install.ps1` again. Nothing was changed. |
| `A previous uninstall is still waiting ...` | Restart Windows first, then install. |
| Install stopped half-way | `.\install.ps1 -Resume` finishes it, or `.\uninstall.ps1` undoes whatever was done. Every change is recorded before it is made. |
| `Administrator rights were declined` | Run it again and click **Yes** on the UAC prompt. |
| Some text slightly truncated ("…") in a tight spot | SF Pro is about 6–15 % wider than Segoe (measured). This is cosmetic; there is no fix short of using Segoe there. |
| An old app shows blank space instead of an emoji | Apple's emoji are color-only, so very old GDI-only apps that cannot draw color fonts show nothing. Modern apps are fine. |
| Windows will not start properly (not observed in testing) | Boot to Recovery, then System Restore and pick **"Before macOS fonts"**. Or use your system image backup. |

Logs of every run: `%ProgramData%\AppleFontsOnWindows\install-*.log` / `restore-*.log`.

## Safety and backups

- **No Windows font file is modified or deleted.** Replacements are added as new `SFUI-*.ttf` files
  and only the registry entries are repointed. `sfc /scannow` stays clean.
- Every font is checked against SHA-256 checksums tracked in git before anything changes, and every
  copied file is checked again after copying.
- All conflicts are found before the first change (see Troubleshooting); if one is found, nothing is changed.
- Before changing anything: a System Restore point (`Before macOS fonts`; only when System Protection
  is on, at most one per 24 h) and exports of the font registry keys, in `%ProgramData%\AppleFontsOnWindows\`
  (administrators only).
- `state.json` records every change **before** it is made. Uninstall uses it to undo exactly that.
- Nothing runs at startup, and no scheduled task or service is added.

### What the install changes

- Adds up to 155 SF / New York font files and 14 `SFUI-*.ttf` files to `C:\Windows\Fonts`.
- Adds registry entries for the SF / New York fonts and repoints the 13 Segoe UI / Segoe UI Variable
  entries and the Segoe UI Emoji entry under `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`.
- Removes per-user registrations of the same Segoe families (`HKCU\...\Fonts`), which would override
  the system ones. They are recorded and put back on uninstall.
- Clears the Windows font cache (it is rebuilt at the next restart).
- Writes `state.json`, logs and registry exports to `%ProgramData%\AppleFontsOnWindows\`.
- Before the first real install, the release passed 311 automated checks, a render of every glyph with
  Windows' own engines, and a rehearsal in Windows Sandbox. See [docs/validation.md](docs/validation.md).

## What is in this release

| Component | Version | Source |
|---|---|---|
| SF Pro, SF Compact | 22.0d5e4 | Apple developer downloads (signature-checked) |
| SF Mono | 18.0d1e1 | same |
| SF Arabic | 20.0d1e2 | same |
| SF Hebrew, SF Armenian, SF Georgian | 20.0d1e1 | same |
| New York | 17.0d5e1 (static OTFs 16.0d2e2) | same |
| Apple Color Emoji | macOS 27.0 (build 26A5425a) | macOS's `/System/Library/Fonts`, converted with [apple-emoji-ttf](https://github.com/samuelngs/apple-emoji-ttf) @ `484daf4` |
| UI replacements | built for Segoe UI 5.72 / Segoe UI Variable 2.03 | `build/build_ui_fonts.py` |

Release assets: `fonts-sf.zip` (155 Apple fonts), `fonts-ui.zip` (13 UI replacements),
`fonts-emoji.zip`, `fonts-zips.sha256`.

## Repository layout

```
install.ps1              one-step install (download -> verify -> elevate -> install -> restart)
uninstall.ps1            one-step undo
status.ps1               read-only health check
scripts/
  install-macos-fonts.ps1   the actual installer (state-tracked, resumable)
  restore-macos-fonts.ps1   the actual restore
  backup-location.ps1       where state, logs and backups live
fonts/                   filled from the release; SHA256SUMS.txt files are tracked in git
build/                   macOS pipeline: fetch Apple fonts, build UI fonts, build emoji
validation/              checks, render-every-glyph, specimen sheets, Arabic diagnostics
sandbox/                 Windows Sandbox tests: script test (no restarts) and full rehearsal
docs/                    how it works, validation evidence, rebuild guide, lessons learned
.github/                 CI, Dependabot, issue forms, PR template
AGENTS.md                rules for AI agents working in this repo
CONTRIBUTING.md          how to contribute
SECURITY.md              how to report a security issue
CHANGELOG.md             release history
LICENSE, NOTICE          MIT license for the code; what it does not cover
```

## How it works (short version)

Windows decides which file *is* "Segoe UI" through the registry. This repo builds replacement fonts
from Apple's glyphs that carry Segoe's exact names, weights and line metrics, so Windows finds the
exact face it asks for (no faux bold, no clipped text). Arabic, Hebrew, Armenian and Georgian come
from Apple's script fonts merged in, and the few everyday characters SF lacks are filled from Segoe so
nothing turns into a square. The installer adds these as new files and points the existing registry
entries at them.

Full detail: [docs/how-it-works.md](docs/how-it-works.md). Pitfalls: [docs/lessons-learned.md](docs/lessons-learned.md).

## Rebuilding for a new macOS

When a new macOS brings new emoji or SF versions: [docs/rebuild.md](docs/rebuild.md)
(Mac: fetch + build, Windows: validate, then publish a new release).

## License

The code and documentation in this repository are released under the [MIT License](LICENSE).

The MIT license does **not** cover any Apple or Microsoft fonts. Those remain under their owners'
licenses, as described in the disclaimer at the top of this page and in [NOTICE](NOTICE).
