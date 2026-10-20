# fonts/

The font files are **not stored in git** (about 1 GB unpacked, a 0.7 GB download). They are attached to the
GitHub Release as three zips; `install.ps1` downloads and unpacks them here automatically.

| Release asset         | Unpacks to   | Contents |
|-----------------------|--------------|----------|
| `fonts-sf.zip`        | `fonts/SF/`    | 155 Apple originals (SF Pro, SF Compact, SF Mono, SF Arabic/Armenian/Georgian/Hebrew, New York), byte-identical to Apple's signed installers |
| `fonts-ui.zip`        | `fonts/ui/`    | 13 built replacements for Segoe UI / Segoe UI Variable (SF Pro + SF Arabic/Hebrew/Armenian/Georgian, with Segoe's names and metrics) |
| `fonts-emoji.zip`     | `fonts/emoji/` | `AppleColorEmoji-Windows.ttf`, built from macOS 27's Apple Color Emoji |

The checksum lists **are** in git and are the integrity anchor:

- `SHA256SUMS.txt` covers `SF/` and `emoji/`
- `ui/SHA256SUMS.txt` covers `ui/`

The installer refuses to run if any file does not match. To verify by hand (Git Bash):

```bash
cd fonts && sha256sum -c --quiet SHA256SUMS.txt && (cd ui && sha256sum -c --quiet SHA256SUMS.txt) && echo OK
```
