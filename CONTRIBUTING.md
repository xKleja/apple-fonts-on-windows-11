# Contributing

Thanks for helping out. Please read the disclaimer at the top of the [README](README.md) first.

## Ground rules

- **PowerShell must parse on Windows PowerShell 5.1 and PowerShell 7.** Check both `powershell.exe`
  and `pwsh.exe` (see the parser one-liner in [AGENTS.md](AGENTS.md)).
- **`.ps1` files use CRLF line endings and are ASCII only** (or UTF-8 with a BOM if non-ASCII text is
  unavoidable). `.gitattributes` enforces the line endings.
- **Never commit font binaries.** Fonts are published only as GitHub release assets. The tracked
  `fonts/**/SHA256SUMS.txt` files are the integrity anchor; update them together with a release.
- **New or rebuilt fonts must pass the validation tools** listed in [AGENTS.md](AGENTS.md):
  `validation/validate_ui_fonts.py` (`ALL HARD CHECKS PASSED`), `validation/render_all_glyphs.py`
  (0 blank), and `validation/winload.ps1` (all load), plus a look at the specimen sheets (Arabic in
  particular). Do not weaken a check to make it pass.
- **Test install changes in Windows Sandbox** with `sandbox/start-rehearsal.ps1` before proposing them.
  Do not run the real install or uninstall on a machine you care about without a backup.
- Do not add startup items, scheduled tasks or services.

## Pull requests

- Keep commits small and descriptive, one concern each.
- Update the README and docs when behaviour changes.
- Describe how you tested the change (parsers, Sandbox rehearsal, validation output).
