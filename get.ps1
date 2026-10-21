# Paste-in install. Open PowerShell (Start menu, type PowerShell, press Enter) and paste this line:
#
#   irm https://github.com/xKleja/apple-fonts-on-windows-11/releases/latest/download/get.ps1 | iex
#
# From Command Prompt, paste this instead:
#
#   powershell -NoProfile -Command "irm https://github.com/xKleja/apple-fonts-on-windows-11/releases/latest/download/get.ps1 | iex"
#
# This file is attached to every release and installs exactly that release. It downloads the release's
# source ZIP from this GitHub repository, unpacks it to %LOCALAPPDATA%\AppleFontsOnWindows, and starts
# Install.cmd there, the same as double-clicking it: Install.cmd checks the PC, downloads and verifies
# the fonts, asks for administrator rights, and changes nothing on Windows before its step 5.
# Nothing else is downloaded or run. To read it first, open the address above in a browser.
# Everything runs inside "& { }" so nothing is left behind in the PowerShell window it is pasted into.
& {
    $ErrorActionPreference = 'Stop'
    $Tag  = 'v1.3.0'   # the release this file belongs to; CI checks it against VERSION
    $Repo = 'xKleja/apple-fonts-on-windows-11'
    $Version = $Tag.Substring(1)
    $Name = "apple-fonts-on-windows-11-$Version"   # the folder inside GitHub's source ZIP

    function Write-Fail([string]$Message) {
        Write-Host "`nCANNOT INSTALL: $Message" -ForegroundColor Red
    }

    Write-Host "`nApple fonts on Windows 11  $Version" -ForegroundColor Cyan
    Write-Host 'Getting the installer. Nothing on Windows changes until the installer says so.'
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        return Write-Fail 'Windows is blocking scripts on this PC (Smart App Control, S mode or an App Control policy). Nothing was changed.'
    }
    if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or -not $env:LOCALAPPDATA) {
        return Write-Fail 'This is for Windows 11 PCs. Nothing was changed.'
    }

    $base = Join-Path $env:LOCALAPPDATA 'AppleFontsOnWindows'
    $dir  = Join-Path $base $Name
    $installCmd  = Join-Path $dir 'Install.cmd'
    $versionFile = Join-Path $dir 'VERSION'
    $ready = (Test-Path -LiteralPath $installCmd) -and (Test-Path -LiteralPath $versionFile) -and
             ((Get-Content -LiteralPath $versionFile -TotalCount 1).Trim() -eq $Version)
    if ($ready) {
        Write-Host "  Using the copy downloaded before: $dir"
    } else {
        $work = Join-Path $base ('download-' + [guid]::NewGuid().ToString('N'))
        try {
            [void][IO.Directory]::CreateDirectory($work)
            $zip = Join-Path $work 'source.zip'
            Write-Host "  Downloading release $Tag from github.com/$Repo ..."
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $ProgressPreference = 'SilentlyContinue'   # the progress bar makes Invoke-WebRequest very slow on 5.1
            Invoke-WebRequest -Uri "https://github.com/$Repo/archive/refs/tags/$Tag.zip" -OutFile $zip -UseBasicParsing -TimeoutSec 300
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::ExtractToDirectory($zip, (Join-Path $work 'unpacked'))
            $unpacked = Join-Path $work "unpacked\$Name"
            if (-not (Test-Path -LiteralPath (Join-Path $unpacked 'Install.cmd'))) { throw 'the download does not contain Install.cmd.' }
            # A copy that is incomplete or from elsewhere is set aside, not deleted.
            if (Test-Path -LiteralPath $dir) {
                Rename-Item -LiteralPath $dir -NewName "$Name.old-$(Get-Date -Format yyyyMMdd-HHmmss)"
            }
            Move-Item -LiteralPath $unpacked -Destination $dir
        } catch {
            return Write-Fail "could not download the installer ($($_.Exception.Message)). Check the internet connection and paste the line again. Nothing was changed."
        } finally {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "  Unpacked to $dir"
    }

    Write-Host "  Starting Install.cmd`n"
    # cmd /c ""path"": the outer quotes are removed by cmd, so any folder name works (spaces, parentheses, &).
    $p = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList "/d /c `"`"$installCmd`"`"" -NoNewWindow -Wait -PassThru
    Write-Host "`nThe installer's files are in: $dir"
    if ($p.ExitCode -eq 0) {
        Write-Host 'Check it any time with Status.cmd there. Undo it in Settings > Apps > Installed apps, or with Uninstall.cmd there.'
    }
}
