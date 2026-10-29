# Windows PowerShell 5.1+, built-in OpenSSH. Run from an extracted release.
[CmdletBinding()]
param([switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
$root = Split-Path $PSScriptRoot -Parent
function Invoke-Native([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed (exit $LASTEXITCODE). Nothing else will be run." }
}
try {
    Write-Host 'Установка AirPlay 2 — Капсула Мини / Alpine 3.24 / aarch64' -ForegroundColor Cyan
    Write-Host 'Это НЕ прошивальщик. На колонке уже должны работать Alpine, root SSH и ALSA.'
    foreach ($tool in @('ssh.exe', 'scp.exe', 'tar.exe')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "$tool not found. Install OpenSSH Client in Windows Optional Features."
        }
    }
    # Verify the extracted bundle before any SSH connection, including the binaries.
    foreach ($line in Get-Content -LiteralPath (Join-Path $root 'SHA256SUMS') -Encoding UTF8) {
        if ($line -notmatch '^([0-9a-f]{64})  \./(.+)$') { throw 'Invalid SHA256SUMS line' }
        $expected = $Matches[1]; $relative = $Matches[2]
        if ($relative -match '(^/|\\|:|(^|/)\.\.(/|$))') { throw 'Unsafe checksum path' }
        $file = Join-Path $root $relative
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
            throw "Checksum mismatch: $relative. Extract the release again."
        }
    }
    Write-Host 'Контрольные суммы комплекта совпали.' -ForegroundColor Green
    if ($ValidateOnly) { Write-Host 'VALIDATION_PASS (no network or installation)'; exit 0 }
    $hostName = (Read-Host 'IP-адрес или hostname колонки в локальной сети (без порта)').Trim()
    if ($hostName -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$') { throw 'Invalid address' }
    $portText = Read-Host 'Порт SSH [Enter = 22]'
    $port = 22
    if ($portText -ne '') {
        if (-not [int]::TryParse($portText, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'Invalid port' }
    }
    $key = Read-Host 'Путь к вашему SSH-ключу [Enter = обычный вход по паролю/агенту]'
    if ($key -ne '' -and -not (Test-Path -LiteralPath $key -PathType Leaf)) { throw 'Key file not found' }
    # Never disable host-key verification, copy keys to the speaker or put passwords in arguments.
    $options = @('-o', 'StrictHostKeyChecking=ask', '-o', 'ConnectTimeout=10')
    if ($key -ne '') { $options += @('-i', $key, '-o', 'IdentitiesOnly=yes') }
    $sshOptions = $options + @('-p', "$port")
    $scpOptions = $options + @('-P', "$port")
    $target = "root@$hostName"
    Write-Host 'При первом входе сверьте fingerprint SSH-ключа с ключом вашей колонки.' -ForegroundColor Yellow
    Write-Host 'Проверка колонки без изменений:'
    $preflight = 'set -eu; test -f /etc/alpine-release; case $(cat /etc/alpine-release) in 3.24|3.24.*) ;; *) exit 1;; esac; test $(uname -m) = aarch64; test -s /etc/asound.conf; test -d /dev/snd; echo HOSTNAME; cat /etc/hostname; df -h /; echo PREFLIGHT_OK'
    Invoke-Native 'ssh.exe' ($sshOptions + @($target, $preflight))
    Write-Host 'При первой установке имя берётся из /etc/hostname колонки. При обновлении своё имя сохраняется.'
    Write-Host 'Изменятся только AirPlay и его зависимости. Музыка прервётся. Старые файлы сохранятся в /root.'
    if ((Read-Host 'Для установки введите INSTALL, для отмены — Enter') -cne 'INSTALL') { Write-Host 'Отменено'; exit 0 }
    $stage = '/root/capsula-airplay-setup-' + [Guid]::NewGuid().ToString('N')
    $archive = Join-Path ([IO.Path]::GetTempPath()) ('capsula-airplay-' + [Guid]::NewGuid().ToString('N') + '.tar.gz')
    try {
        $items = @('.gitattributes','install.sh','uninstall.sh','SHA256SUMS','bin','etc','build','docs','windows','tests','README.md','NOTICE.md','LICENSE','Install-Windows.cmd')
        Invoke-Native 'tar.exe' (@('-czf', $archive, '-C', $root) + $items)
        Invoke-Native 'ssh.exe' ($sshOptions + @($target, "umask 077; mkdir $stage"))
        Invoke-Native 'scp.exe' ($scpOptions + @($archive, "${target}:$stage/bundle.tar.gz"))
        Invoke-Native 'ssh.exe' ($sshOptions + @($target, "set -eu; cd $stage; tar xzf bundle.tar.gz; sh install.sh --upgrade"))
    } finally {
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive }
    }
    Write-Host 'Готово. Выберите колонку в AirPlay на iPhone. Проверьте звук, громкость и переподключение.' -ForegroundColor Green
    Write-Host "Комплект на колонке: $stage. Инструкция отката: docs/WINDOWS.md."
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Не отключайте проверку SSH-ключа! Для настройки Alpine/ALSA обратитесь к вики устройства.'
    exit 1
}
