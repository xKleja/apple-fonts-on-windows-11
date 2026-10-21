#!/usr/bin/env bash
# Enforces the rules marked (CI) in AGENTS.md on the product scripts: everything that runs on a user's
# PC. A hit fails the build. Comment lines are ignored. To allow something new, change AGENTS.md first
# (with the owner's approval), then this file.
set -u
cd "$(dirname "$0")/../.."
files=(install.ps1 uninstall.ps1 status.ps1 scripts/*.ps1 Install.cmd Uninstall.cmd Status.cmd)
fail=0

# check RULE "what it forbids" REGEX [ALLOWED-LINES-REGEX]
check() {
    local rule="$1" what="$2" re="$3" allow="${4:-}" hits
    hits=$(grep -nEi -- "$re" "${files[@]}" | grep -viE '^[^:]+:[0-9]+:[[:space:]]*(#|rem )' || true)
    if [ -n "$allow" ] && [ -n "$hits" ]; then hits=$(printf '%s\n' "$hits" | grep -vE -- "$allow" || true); fi
    if [ -n "$hits" ]; then
        echo "::error::AGENTS.md $rule: $what"
        printf '%s\n' "$hits"
        fail=1
    else
        echo "ok   $rule  $what"
    fi
}

check W3 'no writes to other font settings (FontSubstitutes, FontLink, console fonts, ...)' \
    '(Set-ItemProperty|New-ItemProperty|Remove-ItemProperty|New-Item|Remove-Item|Rename-ItemProperty|reg(\.exe)?"? +(add|delete|import|copy))[^#]*(FontSubstitutes|FontLink|SystemLink|FontMapper|GRE_Initialize|Font Management|FontDPI|\\Console)'
check W4 'no deleting registry keys (only the project'"'"'s own Uninstall key)' \
    'Remove-Item[[:space:]][^#]*(HK(LM|CU|U|EY_)|Registry::|\$Reg)'
check W5 'no takeown / icacls' '\b(takeown|icacls)\b'
check W5 'Set-Acl only for the backup folder (scripts/backup-location.ps1)' 'Set-Acl' '^scripts/backup-location\.ps1:'
check W6 'nothing that runs later (services, scheduled tasks, Run keys, Startup folder)' \
    '(New-Service|\bsc(\.exe)? +(create|config)|schtasks|Register-ScheduledTask|New-ScheduledTask|CurrentVersion\\Run(Once)?\b|\\Start Menu\\Programs\\Startup)'
check W7 'no boot, recovery or servicing tools' '\b(bcdedit|reagentc|vssadmin|dism(\.exe)?|wuauclt|usoclient)\b|sfc(\.exe)? +/scannow'
check S3 'no Invoke-Expression, encoded commands or downloaded code' '\b(Invoke-Expression|iex|DownloadString|DownloadFile)\b|EncodedCommand|FromBase64String'
check P9 'no aliases in pipelines' '\|[[:space:]]*(%|\?|foreach|where|select|sort|gci|ls|cat|gc)[[:space:]]'

# S4: the only web addresses are this repository on GitHub
urls=$(grep -noE "https?://[^\"' )\`]+" "${files[@]}" | grep -vE ':https://github\.com/(xKleja/apple-fonts-on-windows-11|\$Repo)(/|$)' || true)
if [ -n "$urls" ]; then echo '::error::AGENTS.md S4: only this repository'"'"'s GitHub address may appear'; printf '%s\n' "$urls"; fail=1
else echo 'ok   S4  only this repository'"'"'s GitHub address'; fi

# S5: Windows tools by full path
bare=$(grep -nE '(^|[[:space:]&(])(reg|shutdown|cmd|powershell)\.exe\b' "${files[@]}" | grep -viE '^[^:]+:[0-9]+:[[:space:]]*(#|rem )' | grep -vE 'System32\\(WindowsPowerShell\\v1\.0\\)?(reg|shutdown|cmd|powershell)\.exe' || true)
if [ -n "$bare" ]; then echo '::error::AGENTS.md S5: start Windows tools by full path'; printf '%s\n' "$bare"; fail=1
else echo 'ok   S5  Windows tools by full path'; fi

# P6: the module-path reset stays in the entry scripts
for f in install.ps1 uninstall.ps1 status.ps1; do
    if ! grep -q "GetEnvironmentVariable('PSModulePath', 'Machine')" "$f"; then echo "::error::AGENTS.md P6: $f lost the PSModulePath reset"; fail=1; fi
done
[ $fail -eq 0 ] && echo 'ok   P6  PSModulePath reset in the entry scripts'

exit $fail
