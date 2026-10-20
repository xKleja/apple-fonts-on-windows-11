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

Double-click to install, uninstall from Settings like any app, and no Windows font file is modified.

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

- **Windows 11** (Home, Pro, Education or Enterprise; any language). Tested on 25H2 (build 26200).
  The installer refuses to run on Windows 10 or Windows Server, before downloading anything.
- An administrator account, or an administrator's password (you will click **Yes** on one UAC prompt).
  When a standard user types an administrator's password, the per-user font settings handled are still
  the signed-in user's.
- Scripts must be allowed to run: PCs in **S mode**, or with **Smart App Control** or an organization's
  App Control policy turned on, block them (the installer says so and changes nothing).
- An internet connection for the first run. The fonts download from this project's release page over
  HTTPS; no GitHub account or other tools are needed.
- Free space: about 2 GB on the drive holding this folder (a 0.7 GB download, deleted after unpacking,
  plus 1 GB of unpacked fonts) and about 1 GB on the Windows drive.

It changes Windows for every account on the PC, and works from any folder on the PC's own drives.

## Install

1. Open the [latest release](../../releases/latest) and download **Source code (zip)**.
   (The green **Code > Download ZIP** button on this page gives the newest, not yet released, version.)
2. Right-click the downloaded ZIP, choose **Extract All…**, then **Extract**.
3. In the extracted folder, double-click **`Install.cmd`**.
   If Windows asks whether to run it ("Open File – Security Warning"), click **Run**.
4. Click **Yes** on the administrator (UAC) prompt.
5. When it finishes, answer **y** to restart. Running apps only pick up a new system font after a restart.

That's it. Keep the folder if you want to run `Status.cmd` later (for example after Windows updates);
uninstalling does not need it, because it also works from Settings.

If an install is interrupted (window closed, power cut), double-click `Install.cmd` again: it offers to
finish what was started.

The window shows seven numbered steps, `[1/7]` to `[7/7]`, with a progress bar for every long step
(fonts checked, megabytes downloaded with speed and time left, fonts installed), a seconds counter
while Windows creates the restore point, and a summary at the end. Steps 1-3 run in the first window;
after **Yes** on the administrator prompt, steps 4-7 continue in a second window.

What happens, in order:

1. **Checks first.** It confirms this is Windows 11 and that the folder is usable: extracted from the
   ZIP, not on a network drive, and not in a very deeply nested folder. It warns if the folder is
   inside OneDrive, because 1 GB of fonts would then be uploaded too.
2. **Download.** The three font zips for this version (named in `fonts\release.txt`) are downloaded,
   verified with SHA-256, and unpacked into `fonts\`. Failed downloads are retried; fonts that are
   missing or damaged are downloaded again.
3. **Install, as administrator.** Every font is checked again against the checksums in this folder.
   Every possible conflict is checked before anything changes. A restore point and registry backups are
   made. Then the fonts are installed, and Windows' Segoe UI / Segoe UI Variable / Segoe UI Emoji
   entries are pointed at the Apple builds.
4. **Settings entry.** It appears in **Settings > Apps > Installed apps** as
   "Apple fonts on Windows 11 (community project)", so you can uninstall it like any app.

Prefer a terminal, or Git? This does the same:

```powershell
git clone https://github.com/xKleja/apple-fonts-on-windows-11.git
cd apple-fonts-on-windows-11
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

### Options

Add options after `Install.cmd` in a Command Prompt, or after `.\install.ps1` in PowerShell:

| Option | Effect |
|---|---|
| `-SkipEmoji` | UI fonts + SF fonts, keep Windows emoji |
| `-SkipUI` | SF fonts + emoji, keep Segoe UI as the system font |
| `-Resume` | Finish an install that was interrupted (power loss, closed window…) |
| `-DownloadOnly` | Only download, verify and unpack the fonts. Windows is not touched. |
| `-NoRestartPrompt` | Do not ask about restarting |
| `-NoRestorePoint` | Skip the System Restore point |
| `-BackupDir <path>` | Keep state, logs and registry backups somewhere else. Pass the same `-BackupDir` to `status.ps1` and `uninstall.ps1`. The folder must be new (it is created for administrators only) or already administrators-only. |
| `-Tag v1.0.0` | Download the fonts from a different release. The default is the release that matches this copy. |

`-Resume` remembers `-SkipUI` / `-SkipEmoji` from the interrupted run, and `status.ps1` only checks the
parts that were installed.

**Offline install:** download `fonts-sf.zip`, `fonts-ui.zip` and `fonts-emoji.zip` from the
release page, and unzip all three into `fonts\` (giving `fonts\SF\`, `fonts\ui\`, `fonts\emoji\`).
Then run `Install.cmd`. It sees that the fonts are present and verified, and skips the download.

## Check that it worked

Double-click **`Status.cmd`**. It is read-only, needs no administrator rights, and changes nothing.

```
[OK]   Segoe UI                    -> SFUI-SEGOEUI.TTF     Version 5.72; SF Pro 22.0d5e4 (Apple)
[OK]   Segoe UI Variable Text      -> SFUI-SEGUIVAR.TTF    Version 2.03; SF Pro 22.0d5e4 (Apple)
[OK]   Segoe UI Emoji              -> SFUI-SEGUIEMJ.TTF    Version 1.60
...
  13/13 UI font files match
...
Everything is in place.
```

It ends with one of: **Everything is in place** (exit code 0), **Something differs** (1, with what to
do), or **Not installed** (2). Paste its whole output into a bug report.

By eye: open Start and type in Search, open Settings, and type `😀 👍🏽 🇪🇬` in Notepad.

## Uninstall

Either:

- **Settings > Apps > Installed apps**, find **Apple fonts on Windows 11 (community project)**,
  then **⋯ > Uninstall**. This works even if you deleted the downloaded folder.
- Or double-click **`Uninstall.cmd`** in the folder.

Click **Yes** on UAC, then restart (**Start > Power > Restart**; "Shut down" and starting again does not
finish it). Windows is back to Segoe UI / Segoe UI Variable / Segoe UI Emoji, and the SF / New York fonts
are removed. It reverses exactly what the install recorded, nothing more.

## After Windows updates

Windows updates (monthly ones too, not only big feature updates) can re-register Windows' own fonts
and undo part of this. After an update, double-click `Status.cmd`. If anything shows `[DIFF]`:
uninstall (Settings > Apps > Installed apps), restart, then double-click `Install.cmd` and restart.

## Troubleshooting

| Symptom | Fix |
|---|---|
| UI still looks like Segoe right after installing | Restart Windows (not just sign out). Then run `Status.cmd`. |
| Emoji are still Windows emoji | Same: restart. `Status.cmd` should show `Segoe UI Emoji -> SFUI-SEGUIEMJ.TTF`. |
| Double-clicking `Install.cmd` shows "Windows protected your PC" | Click **More info**, then **Run anyway**. It is a plain text script; open it in Notepad to see what it runs. |
| `This needs Windows 11` / `This is for Windows 11 PCs` | Only Windows 11 desktop editions are supported. Nothing was changed. |
| `Files are missing next to install.ps1` | The ZIP was opened but not extracted. Right-click the ZIP, choose **Extract All**, and run `Install.cmd` from the extracted folder. |
| `This folder is on a network drive` | Copy the folder to this PC (for example to Downloads) and run it from there. |
| `The folder path is too long` | Move the folder somewhere shorter, for example `C:\AppleFonts`. |
| `COULD NOT GET THE FONTS` | For a download error: check the internet connection (and any proxy or firewall), then run it again; zips that already arrived are kept. Or use the offline install above. Nothing on Windows was changed. |
| `Checksum mismatch` / `Missing font` | A font file was changed after the download check. Run the install again; it downloads damaged fonts again. |
| `Already installed` | It is installed; `Status.cmd` checks it. To install again: uninstall, restart, install. |
| `A previous install did not finish` | Double-click `Install.cmd` and answer **y** to finish it, or uninstall to undo it. |
| `Nothing to resume: the install is complete` | The last install finished, so there is nothing for `-Resume` to do. Check it with `Status.cmd`. |
| `Nothing to uninstall` | No install is recorded (or it used `-BackupDir`: pass the same `-BackupDir`). |
| `Windows is blocking scripts on this PC` | S mode, Smart App Control or an App Control policy is on. This project cannot run there. |
| `... can be changed by non-administrators, so it cannot hold the install's backups` | Leave out `-BackupDir`, or give a new folder. |
| `Note: ... already existed with permissions a standard user could change; moved it to ...` | Something had created the backup folder before the install, so it was set aside unused (it can be deleted). |
| `Note: ... SF / New York fonts are also installed for this user only` | You had installed some SF fonts yourself. Apps may list them twice; remove your copies in Settings > Personalization > Fonts if you like. |
| `C:\Windows\Fonts already has a different SF-Pro.ttf` (or another SF font), or `The font name ... is already registered` | Another copy of that SF font is installed. Uninstall it (Settings > Personalization > Fonts), then install again. Nothing was changed. |
| `Windows' registration for segoeui.ttf is missing or was changed` | Another font tool changed the system font. Undo that tool's change first. Nothing was changed. |
| `Note: FontSubstitutes redirects Segoe UI ...` | Another tool substitutes a different font for Segoe UI. Some apps will show that font until you remove the substitution. |
| `A previous uninstall is still waiting ...` | Restart Windows (Start > Power > Restart, not Shut down), then install. |
| Install stopped half-way | Double-click `Install.cmd` again and answer **y**, or uninstall to undo whatever was done. Every change is recorded before it is made. |
| `Administrator rights were declined` | Run it again and click **Yes** on the UAC prompt. |
| A message about execution policy | Your organization blocks PowerShell scripts with Group Policy. Ask your IT administrator. |
| Some text slightly truncated ("…") in a tight spot | SF Pro is about 6–15 % wider than Segoe (measured). This is cosmetic; there is no fix short of using Segoe there. |
| An old app shows blank space instead of an emoji | Apple's emoji are color-only, so very old GDI-only apps that cannot draw color fonts show nothing. Modern apps are fine. |
| Windows will not start properly (not observed in testing) | Boot to Recovery, then System Restore and pick **"Before macOS fonts"**. Or use your system image backup. |

Logs of every run: `%ProgramData%\AppleFontsOnWindows\install-*.log` / `restore-*.log` (readable without
administrator rights). A failed install prints the path of its log; attach it to a bug report.

## Safety and backups

- **No Windows font file is modified or deleted.** Replacements are added as new `SFUI-*.ttf` files
  and only the registry entries are repointed. `sfc /scannow` stays clean.
- Every font is checked against SHA-256 checksums tracked in git before anything changes, and every
  copied file is checked again after copying.
- All conflicts are found before the first change (see Troubleshooting); if one is found, nothing is changed.
- Before changing anything: a System Restore point (`Before macOS fonts`; only when System Protection
  is on, at most one per 24 h) and exports of the font registry keys, in `%ProgramData%\AppleFontsOnWindows\`
  (only administrators can change it; everyone can read it). A folder of that name that someone else
  created first is never used: it is set aside and a new one is made.
- `state.json` records every change **before** it is made. Uninstall uses it to undo exactly that, and
  refuses a `state.json` that names anything the install would not have changed.
- Nothing runs at startup, and no scheduled task or service is added.

### What the install changes

- Adds up to 155 SF / New York font files and 14 `SFUI-*.ttf` files to `C:\Windows\Fonts`.
- Adds registry entries for the SF / New York fonts and repoints the 13 Segoe UI / Segoe UI Variable
  entries and the Segoe UI Emoji entry under `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`.
- Removes the signed-in user's per-user registrations of the same Segoe families (`HKCU\...\Fonts`), which would override
  the system ones. They are recorded and put back on uninstall.
- Clears the Windows font cache (it is rebuilt at the next restart).
- Writes `state.json`, logs and registry exports to `%ProgramData%\AppleFontsOnWindows\`, plus a copy of
  the uninstaller there for the Settings entry.
- Adds the **Installed apps** entry (`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\AppleFontsOnWindows`);
  uninstall removes it.
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
Install.cmd              double-click: install (runs install.ps1)
Uninstall.cmd            double-click: undo (runs uninstall.ps1)
Status.cmd               double-click: read-only health check (runs status.ps1)
install.ps1              one-step install (checks -> download -> verify -> elevate -> install -> restart)
uninstall.ps1            one-step undo
status.ps1               read-only health check
scripts/
  checks.ps1                Windows 11 and folder-location checks
  ui.ps1                    what the windows show: numbered steps, progress bars, timers
  install-macos-fonts.ps1   the actual installer (state-tracked, resumable)
  restore-macos-fonts.ps1   the actual restore
  backup-location.ps1       where state, logs and backups live
fonts/                   filled from the release; release.txt and the SHA256SUMS.txt files are tracked in git
build/                   macOS pipeline: fetch Apple fonts, build UI fonts, build emoji
validation/              checks, render-every-glyph, specimen sheets, Arabic diagnostics
sandbox/                 Windows Sandbox tests: script test (no restarts) and full rehearsal
tests/                   unit tests run by CI (state.json validation, backup-folder permissions)
VERSION                  version of the scripts (shown by Status.cmd and in Installed apps)
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
