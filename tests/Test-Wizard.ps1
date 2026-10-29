# Mock integration: no real SSH/SCP or speaker modifications.
param([switch]$FailScp)
$ErrorActionPreference = 'Stop'
$global:CapsulaTestAnswers = [Collections.Generic.Queue[string]]::new()
foreach ($answer in @('192.0.2.10', '', '', 'INSTALL')) { $global:CapsulaTestAnswers.Enqueue($answer) }
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
& (Join-Path (Split-Path $PSScriptRoot -Parent) 'windows/Install-AirPlay.ps1')
if ($FailScp) {
    if ($LASTEXITCODE -ne 1 -or $global:CapsulaTestCalls.Count -ne 3) { throw 'Failed upload was not stopped safely' }
    Write-Host 'WINDOWS_WIZARD_UPLOAD_FAILURE_PASS'
    exit 0
}
if ($global:CapsulaTestAnswers.Count -ne 0 -or $global:CapsulaTestCalls.Count -ne 4) { throw 'Wizard did not complete expected steps' }
$joined = $global:CapsulaTestCalls -join "`n"
if ($joined -match 'StrictHostKeyChecking=no|UserKnownHostsFile=NUL|192\.168\.') { throw 'Unsafe/private SSH option' }
if ($joined -notmatch 'StrictHostKeyChecking=ask' -or $joined -notmatch 'sh install.sh --upgrade') { throw 'Wrong SSH/installation flow' }
Write-Host 'WINDOWS_WIZARD_MOCK_PASS'
