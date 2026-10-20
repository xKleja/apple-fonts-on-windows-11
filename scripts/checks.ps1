# Checks that this PC and this copy of the repo can run the install. Dot-sourced by install.ps1
# (before anything is downloaded) and by install-macos-fonts.ps1 (again, elevated, before any change).

# Windows 11 desktop editions only: the UI fonts replace Segoe UI Variable, which Windows 10 does not
# have, and Windows Server is untested.
function Assert-SupportedWindows {
    $cv    = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$cv.CurrentBuild
    $name  = "$($cv.ProductName) $($cv.DisplayVersion) (build $build)".Trim()
    if ($cv.InstallationType -ne 'Client') { throw "This is for Windows 11 PCs; this is $name. Nothing was changed." }
    if ($build -lt 22000) { throw "This needs Windows 11; this PC runs Windows 10 ($name). Nothing was changed." }
}

# Problems with where this folder is, found before the download or the UAC prompt.
# Returns warnings (strings); throws for locations that cannot work.
function Test-RepoLocation([string]$Root) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'scripts\install-macos-fonts.ps1'))) {
        throw 'Files are missing next to install.ps1. If you opened the ZIP without extracting it: right-click the ZIP, choose "Extract All", and run Install.cmd from the extracted folder.'
    }
    $isNetwork = $Root.StartsWith('\\')
    if (-not $isNetwork) {
        try { $isNetwork = ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($Root))).DriveType -eq 'Network' } catch { }
    }
    if ($isNetwork) {
        throw "This folder is on a network drive ($Root), which the administrator window cannot see. Copy the folder to this PC (for example to Downloads) and run it from there. Nothing was changed."
    }
    # The longest font path inside fonts\ is 65 characters; stay clear of the 260-character limit.
    if ($Root.Length -gt 180) {
        throw "The folder path is too long ($($Root.Length) characters): $Root. Move the folder somewhere shorter, for example C:\AppleFonts, and run it again. Nothing was changed."
    }
    $warnings = @()
    foreach ($od in $env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial | Where-Object { $_ } | Select-Object -Unique) {
        if ($Root.StartsWith($od.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $warnings += 'This folder is inside OneDrive, so the fonts (about 1 GB) will also be uploaded there. To avoid that, move the folder outside OneDrive (for example C:\AppleFonts) and run it from there.'
            break
        }
    }
    $warnings
}
