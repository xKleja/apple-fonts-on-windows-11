# Where install/restore keep their state, registry exports, logs and the original emoji font.
# Dot-sourced by install-macos-fonts.ps1, restore-macos-fonts.ps1 and status.ps1.

$script:DefaultBackupDir = Join-Path $env:ProgramData 'AppleFontsOnWindows'
$script:LegacyBackupDir  = 'E:\FontBackup'   # used by the very first install (2026-10-20)

function Get-DefaultBackupDir {
    # An existing install keeps using the folder it was recorded in.
    foreach ($dir in $script:DefaultBackupDir, $script:LegacyBackupDir) {
        if (Test-Path (Join-Path $dir 'state.json')) { return $dir }
    }
    return $script:DefaultBackupDir
}
