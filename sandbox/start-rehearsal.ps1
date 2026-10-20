<#
.SYNOPSIS
    Rehearse install -> restart -> restore in Windows Sandbox (a disposable copy of this exact Windows).
    Nothing on the real PC changes. Needs the "Windows Sandbox" feature and the fonts in ..\fonts
    (run ..\install.ps1 -DownloadOnly first).

.DESCRIPTION
    Generates rehearsal.wsb with this repo's real paths (Sandbox config files cannot be relative),
    maps the repo read-only as C:\src and ..\sandbox-results writable as C:\results, and starts it.
    rehearsal.ps1 then runs inside the sandbox through three phases, restarting in between:
      0-before    screenshots + font report with stock Windows      -> install, restart
      1-installed screenshots + font report with the Apple fonts    -> restore, restart
      2-restored  screenshots + font report after undo              -> done
    Follow progress in sandbox-results\rehearsal.log. Closing the Sandbox window discards it.
#>
$ErrorActionPreference = 'Stop'
if (-not (Test-Path "$env:WINDIR\System32\WindowsSandbox.exe")) {
    throw 'Windows Sandbox is not enabled. Elevated: Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All, then restart.'
}
$repo    = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$results = Join-Path $repo 'sandbox-results'
if ((Get-ChildItem (Join-Path $repo 'fonts\ui') -Filter *.ttf -ErrorAction SilentlyContinue).Count -lt 13) {
    throw 'Fonts are missing. Run ..\install.ps1 -DownloadOnly first.'
}
New-Item -ItemType Directory -Force $results | Out-Null
Get-ChildItem $results | Remove-Item -Recurse -Force

$wsb = @"
<Configuration>
  <Networking>Disable</Networking>
  <MemoryInMB>8192</MemoryInMB>
  <MappedFolders>
    <MappedFolder><HostFolder>$repo</HostFolder><SandboxFolder>C:\src</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$results</HostFolder><SandboxFolder>C:\results</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand><Command>powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\src\sandbox\rehearsal.ps1</Command></LogonCommand>
</Configuration>
"@
$wsbPath = Join-Path $env:TEMP 'apple-fonts-rehearsal.wsb'
Set-Content $wsbPath $wsb -Encoding UTF8
Start-Process $wsbPath
"Sandbox starting. Progress: $results\rehearsal.log (UTF-16). Screenshots land in $results\<phase>\."
