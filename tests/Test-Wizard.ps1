# Mock integration: no real SSH/SCP or speaker modifications.
param([switch]$FailScp, [switch]$Unattended)
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'windows/Install-AirPlay.ps1'
$global:CapsulaTestAnswers = [Collections.Generic.Queue[string]]::new()
foreach ($answer in @('192.0.2.10', '', '', 'Test Room', 'INSTALL')) { $global:CapsulaTestAnswers.Enqueue($answer) }
$global:CapsulaTestCalls = [Collections.Generic.List[string]]::new()
$global:CapsulaTestFailScp = $FailScp
function global:Read-Host { param($Prompt); return $global:CapsulaTestAnswers.Dequeue() }
function global:ssh.exe {
    $global:CapsulaTestCalls.Add('ssh ' + ($args -join ' '))
    $global:LASTEXITCODE = 0
}
function global:scp.exe {
    $global:CapsulaTestCalls.Add('scp ' + ($args -join ' '))
    if ($global:CapsulaTestFailScp) { $global:LASTEXITCODE = 17 } else { $global:LASTEXITCODE = 0 }
}
if ($Unattended) {
    & $scriptPath -HostName 192.0.2.10 -Port 22 -Name 'Test Room' -Yes
} else {
    & $scriptPath
}
if ($FailScp) {
    if ($LASTEXITCODE -ne 1 -or $global:CapsulaTestCalls.Count -ne 3) { throw 'Failed upload was not stopped safely' }
    Write-Host 'WINDOWS_WIZARD_UPLOAD_FAILURE_PASS'
    exit 0
}
if (-not $Unattended -and $global:CapsulaTestAnswers.Count -ne 0) { throw 'Wizard did not consume all prompts' }
if ($global:CapsulaTestCalls.Count -ne 4) { throw 'Wizard did not complete expected steps' }
$joined = $global:CapsulaTestCalls -join "`n"
if ($joined -match 'StrictHostKeyChecking=no|UserKnownHostsFile=NUL|192\.168\.') { throw 'Unsafe/private SSH option' }
if ($joined -notmatch 'StrictHostKeyChecking=ask' -or $joined -notmatch 'sh install.sh --upgrade') { throw 'Wrong SSH/installation flow' }
if ($joined -notmatch "--name 'Test Room'") { throw 'Name was not passed to the installer' }
Write-Host 'WINDOWS_WIZARD_MOCK_PASS'
