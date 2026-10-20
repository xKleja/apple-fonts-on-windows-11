# Rebuilding for a newer macOS / new Apple fonts

Rebuild when Apple ships new SF fonts or a new Apple Color Emoji (each macOS release), or when a
Windows update changes Segoe UI (new characters to gap-fill or match).

You need a **Mac** for the Apple sources and a **Windows PC** for the original Segoe files and validation.

## 1. Apple fonts (Mac)

```bash
build/fetch_apple_fonts.sh build/work/SF
```

It downloads the 8 installers from developer.apple.com, rejects anything not signed by Apple, and
extracts the 155 fonts into `build/work/SF/` in the layout the installer expects. It stops with an
error if the count is not 155 or the output folder already contains fonts.

## 2. Emoji (Mac)

```bash
brew install uv           # once
build/build_emoji.sh build/work/emoji
```

This uses the Mac's `/System/Library/Fonts/Apple Color Emoji.ttc`, so the emoji are whatever that
macOS ships. It clones and runs [apple-emoji-ttf](https://github.com/samuelngs/apple-emoji-ttf) at a
pinned commit (the optional second argument, a full 40-character SHA; default: the commit used for
v1.0.0). Check coverage against Windows' emoji font (copy `C:\Windows\Fonts\seguiemj.ttf` from the PC):

```bash
python build/emoji_coverage.py build/work/emoji/emoji-test.txt \
    segoe=seguiemj.ttf apple="/System/Library/Fonts/Apple Color Emoji.ttc" built=build/work/emoji/AppleColorEmoji-Windows.ttf
```

It must end with `In segoe but missing from built: 0` (exit code 0).

## 3. UI fonts (Mac; Windows works too)

Copy the **original** Segoe files from `C:\Windows\Fonts` on a Windows PC into `build/work/segoe/`.
The install never modifies them (its registry entries just point elsewhere), so this works on a PC
with the install active too:

```
segoeui.ttf segoeuib.ttf segoeuii.ttf segoeuiz.ttf segoeuil.ttf seguili.ttf
segoeuisl.ttf seguisli.ttf seguisb.ttf seguisbi.ttf seguibl.ttf seguibli.ttf SegUIVar.ttf
```

macOS:

```bash
python3 -m venv .venv && .venv/bin/pip install -r build/requirements.txt
.venv/bin/python build/build_ui_fonts.py build/work/SF build/work/segoe build/work/ui
```

Windows (PowerShell):

```powershell
py -3.12 -m venv .venv; .venv\Scripts\pip install -r build\requirements.txt
.venv\Scripts\python build\build_ui_fonts.py build\work\SF build\work\segoe build\work\ui
```

About 6 minutes on an M-series Mac (hinting 12 × 37k glyphs). Add `--no-hint` for a quick trial build,
or list output names to build only those (for example `segoeui.ttf SegUIVar.ttf`).

## 4. Validate (Windows)

```powershell
py -3.12 -m venv .venv; .venv\Scripts\pip install -r build\requirements.txt
.venv\Scripts\python validation\validate_ui_fonts.py build\work\ui build\work\segoe build\work\SF
.venv\Scripts\python validation\render_all_glyphs.py build\work\ui build\work\render
pwsh validation\winload.ps1 -Root build\work\ui
pwsh validation\specimen.ps1 -RenderWork build\work\render -OutDir build\work\specimens
```

All must be clean: `ALL HARD CHECKS PASSED`, `TOTAL blank glyphs ...: 0`, all fonts loaded (each tool
exits non-zero otherwise). Then look at the specimen PNGs (Arabic marks especially). Test the install
scripts in Windows Sandbox with `sandbox\start-rehearsal.ps1 -Mode Scripts`, and optionally take
screenshots with the full `sandbox\start-rehearsal.ps1`.

## 5. Publish

Run this in Git Bash or WSL (it needs GNU `sha256sum` and `xargs -d`; macOS has `shasum -a 256`
instead) with `zip` installed:

```bash
# checksums (tracked in git)
(cd build/work && find SF emoji -type f \( -name '*.ttf' -o -name '*.otf' \) | sort | sed 's|^|./|' | xargs -d '\n' sha256sum) > fonts/SHA256SUMS.txt
(cd build/work/ui && sha256sum *.ttf) > fonts/ui/SHA256SUMS.txt

# zips (release assets): each unpacks into fonts/
(cd build/work && zip -r -9 ../../fonts-sf.zip SF && zip -r -9 ../../fonts-ui.zip ui -x '*.txt' && zip -r -9 ../../fonts-emoji.zip emoji -x '*.txt')
sha256sum fonts-sf.zip fonts-ui.zip fonts-emoji.zip > fonts-zips.sha256
```

Then write the new tag into `fonts/release.txt` (the installer downloads the fonts from the release
named there, so it must match the checksums above), update `CHANGELOG.md` and the version table in
the README, and:

```bash
git commit -am "Fonts vX.Y.Z: <what changed>"
git tag -a vX.Y.Z -m "vX.Y.Z" && git push --follow-tags
gh release create vX.Y.Z fonts-*.zip fonts-zips.sha256 --title "vX.Y.Z" --notes "<what changed>"
```

On a PC with an older version installed: `.\uninstall.ps1`, restart, pull, `.\install.ps1`, restart.
