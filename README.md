> [!WARNING]
> **Educational and experimental project — use at your own risk.**
> This project is provided for educational, research, and demonstration purposes only, **as is**, without any warranties or guarantees. Installing fonts or changing Windows font settings may cause compatibility issues, instability, or data loss; you assume all risks and responsibility for your actions.
>
> Apple, San Francisco (SF), New York, and Apple Color Emoji are trademarks or proprietary materials of their respective owners; Segoe UI and Windows belong to Microsoft. This project is **not affiliated with, endorsed by, or sponsored by Apple Inc. or Microsoft Corporation**. No intellectual-property rights or permission to download, copy, modify, distribute, or use proprietary fonts are granted here.
>
> **You are responsible for complying with all applicable laws and font license agreements.** In particular, Apple's font licenses may restrict modification, redistribution, and use on non-Apple platforms, even for personal or educational purposes. Calling a project “educational” or using it privately does **not** override those restrictions. Do not use or distribute any font unless you have the necessary rights.

---

# Apple fonts on Windows 11

Make Windows 11 look like a Mac. Your Start menu, taskbar, Settings, File Explorer and apps switch to
Apple's **San Francisco** font. Emoji turn into **Apple's emoji** everywhere. You also get Apple's full
font collection to use in Word, Figma and other apps. Arabic text looks right too.

- **One line to install.** No account or extra tools needed.
- **Undo any time** from Settings, like any other app.
- **Your Windows fonts stay untouched.** Nothing of Windows' own is changed or deleted, so undo is exact.

## Install

1. Open **PowerShell**: click Start, type `PowerShell`, and press Enter.
2. Copy this line, paste it into the PowerShell window, and press Enter:

   ```powershell
   irm https://github.com/xKleja/apple-fonts-on-windows-11/releases/latest/download/get.ps1 | iex
   ```

3. Click **Yes** when Windows asks for permission.
4. Wait a few minutes. When it asks to restart, type **y** and press Enter.

After the restart, Windows uses the Apple fonts. You need **Windows 11**, an internet connection and
about 3 GB of free space.

<details>
<summary><b>Rather not paste a command?</b> Download it instead</summary>

1. Open the [latest release](../../releases/latest) and download **Source code (zip)**.
2. Right-click the downloaded ZIP, choose **Extract All…**, then **Extract**.
3. In the extracted folder, double-click **`Install.cmd`**.
   If Windows asks whether to run it ("Open File – Security Warning"), click **Run**.
4. Click **Yes** on the permission prompt, and type **y** to restart when it finishes.

Keep that folder if you want to run `Status.cmd` later (uninstalling does not need it).

</details>

<details>
<summary><b>Is the paste-in line safe?</b> What it does</summary>

Pasting a command from a web page runs it as you, so it is fair to check first. Open the address in a
browser to read [`get.ps1`](get.ps1). It only downloads this project's release from GitHub to
`%LOCALAPPDATA%\AppleFontsOnWindows` and starts `Install.cmd` from there. That is the same installer
the download gives you. It checks your PC first and changes nothing until you click **Yes**.

Using **Command Prompt** instead of PowerShell? Paste this:

```bat
powershell -NoProfile -Command "irm https://github.com/xKleja/apple-fonts-on-windows-11/releases/latest/download/get.ps1 | iex"
```

</details>

## Undo it

Open **Settings > Apps > Installed apps**, find **Apple fonts on Windows 11 (community project)**, and
choose **⋯ > Uninstall**. Click **Yes**, then restart with **Start > Power > Restart**.

Windows is then back to its own fonts and emoji, exactly as before.

<details>
<summary>More about uninstalling</summary>

- You can also double-click **`Uninstall.cmd`** in the project folder. With the paste-in line, that
  folder is in `%LOCALAPPDATA%\AppleFontsOnWindows` (paste that into the File Explorer address bar).
- Choose **Restart**, not Shut down: shutting down and starting again does not finish the uninstall.
- The Settings entry works even if you deleted the project folder.
- It removes the SF / New York fonts and reverses exactly what the install recorded, nothing more.

</details>

## Did it work?

After the restart, open Start and type something in Search, or type `😀 👍🏽 🇪🇬` in Notepad.

To check properly, double-click **`Status.cmd`** in the project folder. It only looks and changes
nothing. It ends with **Everything is in place**, **Something differs** (and what to do), or
**Not installed**.

## After Windows updates

Windows updates, even the monthly ones, can switch some fonts back. If something looks like Windows
again, double-click `Status.cmd`. If it shows `[DIFF]`, uninstall, restart, install again, and restart.

## Something went wrong?

Most problems are fixed by **restarting Windows** (Restart, not Shut down). The installer always says
whether it changed anything, and **if it stops before changing anything, it says "Nothing was
changed."** If an install was interrupted (window closed, power cut), run it again: it offers to finish
what was started.

<details>
<summary><b>Messages and fixes</b></summary>

| Symptom | Fix |
|---|---|
| UI still looks like Segoe right after installing | Restart Windows (not just sign out). Then run `Status.cmd`. |
| Emoji are still Windows emoji | Same: restart. `Status.cmd` should show `Segoe UI Emoji -> SFUI-SEGUIEMJ.TTF`. |
| Double-clicking `Install.cmd` shows "Windows protected your PC" | Click **More info**, then **Run anyway**. It is a plain text script; open it in Notepad to see what it runs. |
| `irm` is not recognized, or `'irm' is not recognized as an internal or external command` | It was pasted into Command Prompt. Use the Command Prompt line under "Is the paste-in line safe?", or open PowerShell instead. |
| `CANNOT INSTALL: could not download the installer` | Check the internet connection (and any proxy or firewall), then paste the line again. Or download the ZIP instead. Nothing was changed. |
| `This needs Windows 11` / `This is for Windows 11 PCs` | Only Windows 11 desktop editions are supported. Nothing was changed. |
| `Files are missing next to install.ps1` | The ZIP was opened but not extracted. Right-click the ZIP, choose **Extract All**, and run `Install.cmd` from the extracted folder. |
| `This folder is on a network drive` | Copy the folder to this PC (for example to Downloads) and run it from there. |
| `The folder path is too long` | Move the folder somewhere shorter, for example `C:\AppleFonts`. |
| `COULD NOT GET THE FONTS` | For a download error: check the internet connection (and any proxy or firewall), then run it again; zips that already arrived are kept. Or use the offline install (under "For advanced users"). Nothing on Windows was changed. |
| `Checksum mismatch` / `Missing font` | A font file was changed after the download check. Run the install again; it downloads damaged fonts again. |
| `Already installed` | It is installed; `Status.cmd` checks it. To install again: uninstall, restart, install. |
| `A previous install did not finish` | Double-click `Install.cmd` (or paste the line again) and answer **y** to finish it, or uninstall to undo it. |
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
| Install stopped half-way | Run the install again and answer **y**, or uninstall to undo whatever was done. Every change is recorded before it is made. |
| `Administrator rights were declined` | Run it again and click **Yes** on the permission (UAC) prompt. |
| A message about execution policy | Your organization blocks PowerShell scripts with Group Policy. Ask your IT administrator. |
| Some text slightly truncated ("…") in a tight spot | SF Pro is about 6–15 % wider than Segoe (measured). This is cosmetic; there is no fix short of using Segoe there. |
| An old app shows blank space instead of an emoji | Apple's emoji are color-only, so very old GDI-only apps that cannot draw color fonts show nothing. Modern apps are fine. |
| Windows will not start properly (not observed in testing) | Boot to Recovery, then System Restore and pick **"Before macOS fonts"**. Or use your system image backup. |

Logs of every run: `%ProgramData%\AppleFontsOnWindows\install-*.log` / `restore-*.log` (readable without
administrator rights). A failed install prints the path of its log. When you [report a
problem](../../issues/new/choose), attach the log and paste the whole output of `Status.cmd`.

</details>

---

## More details

<details>
<summary><b>What changes on screen</b></summary>

| Where | Before | After |
|---|---|---|
| Start, Taskbar, **Search panel**, Settings, new File Explorer, Notepad (modern UI) | Segoe UI Variable | **SF Pro** (Text and Display optical sizes, like macOS) |
| Title bars, menus, dialogs, Control Panel, browser UI, most desktop apps (classic UI) | Segoe UI | **SF Pro Text**, every weight Light → Black plus italics |
| Arabic (and Hebrew, Armenian, Georgian) in the UI | Segoe UI | **SF Arabic** / SF Hebrew / SF Armenian / SF Georgian |
| Emoji in every app | Segoe UI Emoji | **Apple Color Emoji** (macOS 27), about 700 more emoji than Windows has |
| Fonts you can pick in Word, Figma, VS Code, … | — | SF Pro, SF Pro Rounded, SF Compact, SF Mono, New York, SF Arabic/Hebrew/Armenian/Georgian (155 files) |

Not changed: icon fonts (Segoe Fluent Icons, MDL2 Assets, UI Symbol), document fonts (Calibri,
Aptos, Times…), and the console / code fonts. English and Arabic are first-class.

</details>

<details>
<summary><b>Requirements in full</b></summary>

- **Windows 11** (Home, Pro, Education or Enterprise; any language). Tested on 25H2 (build 26200).
  The installer refuses to run on Windows 10 or Windows Server, before downloading anything.
- An administrator account, or an administrator's password (you will click **Yes** on one UAC prompt).
  When a standard user types an administrator's password, the per-user font settings handled are still
  the signed-in user's.
- Scripts must be allowed to run: PCs in **S mode**, or with **Smart App Control** or an organization's
  App Control policy turned on, block them (the installer says so and changes nothing).
- An internet connection for the first run. The fonts download from this project's release page over
  HTTPS; no GitHub account or other tools are needed.
- Free space: about 2 GB on the drive holding the project folder (a 0.7 GB download, deleted after
  unpacking, plus 1 GB of unpacked fonts) and about 1 GB on the Windows drive. With the paste-in line,
  both are the Windows drive.

It changes Windows for every account on the PC, and works from any folder on the PC's own drives.

</details>

<details>
<summary><b>What the installer does, step by step</b></summary>

The window shows seven numbered steps, `[1/7]` to `[7/7]`, with a progress bar for every long step
(fonts checked, megabytes downloaded with speed and time left, fonts installed), a seconds counter
while Windows creates the restore point, and a summary at the end. Steps 1-3 run in the first window;
after **Yes** on the administrator prompt, steps 4-7 continue in a second window.

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

Running apps only pick up a new system font after a restart.

</details>

<details>
<summary><b>Safety and backups</b>: what is changed, and how it is undone</summary>

- **No Windows font file is modified or deleted.** Replacements are added as new `SFUI-*.ttf` files
  and only the registry entries are repointed. `sfc /scannow` stays clean.
- Every font is checked against SHA-256 checksums tracked in git before anything changes, and every
  copied file is checked again after copying.
- All conflicts are found before the first change (see the messages above); if one is found, nothing is
  changed.
- Before changing anything: a System Restore point (`Before macOS fonts`; only when System Protection
  is on, at most one per 24 h) and exports of the font registry keys, in `%ProgramData%\AppleFontsOnWindows\`
  (only administrators can change it; everyone can read it). A folder of that name that someone else
  created first is never used: it is set aside and a new one is made.
- `state.json` records every change **before** it is made. Uninstall uses it to undo exactly that, and
  refuses a `state.json` that names anything the install would not have changed.
- Nothing runs at startup, and no scheduled task or service is added.

**What the install changes:**

- Adds up to 155 SF / New York font files and 14 `SFUI-*.ttf` files to `C:\Windows\Fonts`.
- Adds registry entries for the SF / New York fonts and repoints the 13 Segoe UI / Segoe UI Variable
  entries and the Segoe UI Emoji entry under `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`.
- Removes the signed-in user's per-user registrations of the same Segoe families (`HKCU\...\Fonts`),
  which would override the system ones. They are recorded and put back on uninstall.
- Clears the Windows font cache (it is rebuilt at the next restart).
- Writes `state.json`, logs and registry exports to `%ProgramData%\AppleFontsOnWindows\`, plus a copy of
  the uninstaller there for the Settings entry.
- Adds the **Installed apps** entry (`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\AppleFontsOnWindows`);
  uninstall removes it.
- Before the first real install, the release passed 311 automated checks, a render of every glyph with
  Windows' own engines, and a rehearsal in Windows Sandbox. See [docs/validation.md](docs/validation.md).

</details>

<details>
<summary><b>For advanced users</b>: options, Git, offline install</summary>

**Options.** Add them after `Install.cmd` in a Command Prompt, or after `.\install.ps1` in PowerShell:

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

**With Git:**

```powershell
git clone https://github.com/xKleja/apple-fonts-on-windows-11.git
cd apple-fonts-on-windows-11
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

The green **Code > Download ZIP** button on this page gives the newest, not yet released, version.

**Offline install:** download `fonts-sf.zip`, `fonts-ui.zip` and `fonts-emoji.zip` from the
release page, and unzip all three into `fonts\` (giving `fonts\SF\`, `fonts\ui\`, `fonts\emoji\`).
Then run `Install.cmd`. It sees that the fonts are present and verified, and skips the download.

`Status.cmd` exit codes: 0 everything is in place, 1 something differs, 2 not installed.

</details>

<details>
<summary><b>Font versions in this release</b></summary>

| Component | Version | Source |
|---|---|---|
| SF Pro, SF Compact | 22.0d5e4 | Apple developer downloads (signature-checked) |
| SF Mono | 18.0d1e1 | same |
| SF Arabic | 20.0d1e2 | same |
| SF Hebrew, SF Armenian, SF Georgian | 20.0d1e1 | same |
| New York | 17.0d5e1 (static OTFs 16.0d2e2) | same |
| Apple Color Emoji | macOS 27.0 (build 26A5425a) | macOS's `/System/Library/Fonts`, converted with [apple-emoji-ttf](https://github.com/samuelngs/apple-emoji-ttf) @ `484daf4` |
| UI replacements | built for Segoe UI 5.72 / Segoe UI Variable 2.03 | `build/build_ui_fonts.py` |

Release assets: `get.ps1` (the paste-in loader), `fonts-sf.zip` (155 Apple fonts), `fonts-ui.zip`
(13 UI replacements), `fonts-emoji.zip`, `fonts-zips.sha256`.

</details>

<details>
<summary><b>For developers</b>: how it works, repository layout, rebuilding</summary>

**How it works.** Windows decides which file *is* "Segoe UI" through the registry. This repo builds
replacement fonts from Apple's glyphs that carry Segoe's exact names, weights and line metrics, so
Windows finds the exact face it asks for (no faux bold, no clipped text). Arabic, Hebrew, Armenian and
Georgian come from Apple's script fonts merged in, and the few everyday characters SF lacks are filled
from Segoe so nothing turns into a square. The installer adds these as new files and points the
existing registry entries at them. Full detail: [docs/how-it-works.md](docs/how-it-works.md).
Pitfalls: [docs/lessons-learned.md](docs/lessons-learned.md).

**Rebuilding for a new macOS** (new emoji or SF versions): [docs/rebuild.md](docs/rebuild.md)
(Mac: fetch + build, Windows: validate, then publish a new release).

**Contributing:** read [AGENTS.md](AGENTS.md) (the rules, for people and AI agents alike) and
[CONTRIBUTING.md](CONTRIBUTING.md).

```
get.ps1                  paste-in loader (attached to each release): downloads it, runs Install.cmd
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
sandbox/                 Windows Sandbox tests: script test, paste-in test, full rehearsal
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

</details>

## License

The code and documentation in this repository are released under the [MIT License](LICENSE).

The MIT license does **not** cover any Apple or Microsoft fonts. Those remain under their owners'
licenses, as described in the disclaimer at the top of this page and in [NOTICE](NOTICE).
