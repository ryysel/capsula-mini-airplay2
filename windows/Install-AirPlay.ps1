# Windows PowerShell 5.1+, built-in OpenSSH. Run from an extracted release.
# Interactive by default; -HostName/-Port/-KeyFile/-Name/-Yes allow unattended use.
[CmdletBinding()]
param(
    [switch]$ValidateOnly,
    [string]$HostName,
    [int]$Port = 0,
    [string]$KeyFile,
    [string]$Name,
    [switch]$Yes,
    [switch]$DiscoverOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
$root = Split-Path $PSScriptRoot -Parent
function Invoke-Native([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed (exit $LASTEXITCODE). Nothing else will be run." }
}
function Quote-Sh([string]$Value) {
    # POSIX single-quote for the remote shell.
    return "'" + $Value.Replace("'", "'\''") + "'"
}
function Test-TcpPort([string]$Address, [int]$TcpPort) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($Address, $TcpPort)
        if ($task.Wait(350) -and $client.Connected) { return $true }
    } catch { return $false }
    finally { $client.Close() }
    return $false
}
function Get-CapsulaCandidates {
    # USB gadget address used by the Capsula images, then hosts already in the
    # ARP cache that answer on the SSH port. No subnet sweep, no port scan of
    # hosts the PC has not talked to.
    $addresses = New-Object System.Collections.Generic.List[string]
    $addresses.Add('192.168.14.14')
    try {
        foreach ($line in (& arp.exe -a 2>$null)) {
            if ($line -match '\b(\d{1,3}(?:\.\d{1,3}){3})\b') { $addresses.Add($Matches[1]) }
        }
    } catch { }
    $seen = @{}
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($address in $addresses) {
        if ($seen.ContainsKey($address)) { continue }
        $seen[$address] = $true
        if ($address -match '^(0\.|127\.|169\.254\.|22[4-9]\.|23[0-9]\.|255\.)') { continue }
        if (Test-TcpPort $address 22) { $result.Add($address) }
    }
    return $result
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
    if ($DiscoverOnly) {
        $found = Get-CapsulaCandidates
        if ($found.Count -eq 0) { Write-Host 'NOT_FOUND' } else { $found | ForEach-Object { Write-Host $_ } }
        exit 0
    }

    if (-not $HostName) {
        Write-Host 'Поиск колонки: USB-адрес и устройства из ARP с открытым SSH...'
        $found = Get-CapsulaCandidates
        if ($found.Count -gt 0) {
            Write-Host 'Найдены кандидаты:'
            for ($i = 0; $i -lt $found.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $found[$i]) }
            $answer = (Read-Host 'Номер или адрес колонки [Enter = ввести вручную]').Trim()
            if ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $found.Count) {
                $HostName = $found[([int]$answer - 1)]
            } elseif ($answer -ne '') { $HostName = $answer }
        }
        if (-not $HostName) { $HostName = (Read-Host 'IP-адрес или hostname колонки (без порта)').Trim() }
    }
    if ($HostName -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$') { throw 'Invalid address' }
    if ($Port -eq 0) {
        $portText = Read-Host 'Порт SSH [Enter = 22]'
        $Port = 22
        if ($portText -ne '') {
            if (-not [int]::TryParse($portText, [ref]$Port) -or $Port -lt 1 -or $Port -gt 65535) { throw 'Invalid port' }
        }
    }
    if ($Port -lt 1 -or $Port -gt 65535) { throw 'Invalid port' }
    if (-not $KeyFile -and -not $Yes) {
        $key = Read-Host 'Путь к вашему SSH-ключу [Enter = обычный вход по паролю/агенту]'
        if ($key -ne '') { $KeyFile = $key }
    }
    if ($KeyFile -and -not (Test-Path -LiteralPath $KeyFile -PathType Leaf)) { throw 'Key file not found' }
    if (-not $Name -and -not $Yes) {
        $nameText = Read-Host 'AirPlay-имя [Enter = взять /etc/hostname колонки]'
        if ($nameText -ne '') { $Name = $nameText.Trim() }
    }
    if ($Name) {
        if ([Text.Encoding]::UTF8.GetByteCount($Name) -gt 50) { throw 'Name must be 1..50 UTF-8 bytes' }
        if ($Name -match '[\x00-\x1f"\\]') { throw 'Name must not contain control characters, quotes or backslashes' }
    }

    # Never disable host-key verification, copy keys to the speaker or put passwords in arguments.
    $options = @('-o', 'StrictHostKeyChecking=ask', '-o', 'ConnectTimeout=10')
    if ($KeyFile) { $options += @('-i', $KeyFile, '-o', 'IdentitiesOnly=yes') }
    $sshOptions = $options + @('-p', "$Port")
    $scpOptions = $options + @('-P', "$Port")
    $target = "root@$HostName"
    Write-Host 'При первом входе сверьте fingerprint SSH-ключа с ключом вашей колонки.' -ForegroundColor Yellow
    Write-Host 'Проверка колонки без изменений:'
    $preflight = 'set -eu; test -f /etc/alpine-release; case $(cat /etc/alpine-release) in 3.24|3.24.*) ;; *) exit 1;; esac; test $(uname -m) = aarch64; test -s /etc/asound.conf; test -d /dev/snd; echo HOSTNAME; cat /etc/hostname; df -h /; echo PREFLIGHT_OK'
    Invoke-Native 'ssh.exe' ($sshOptions + @($target, $preflight))
    Write-Host 'Изменятся только AirPlay и его зависимости. Музыка прервётся. Старые файлы сохранятся в /root.'
    if (-not $Yes -and (Read-Host 'Для установки введите INSTALL, для отмены — Enter') -cne 'INSTALL') {
        Write-Host 'Отменено'; exit 0
    }
    $stage = '/root/capsula-airplay-setup-' + [Guid]::NewGuid().ToString('N')
    $archive = Join-Path ([IO.Path]::GetTempPath()) ('capsula-airplay-' + [Guid]::NewGuid().ToString('N') + '.tar.gz')
    $install = 'sh install.sh --upgrade'
    if ($Name) {
        # Pass the name as a UTF-8 file: Windows PowerShell 5.1 mangles non-ASCII
        # characters in native command-line arguments.
        [IO.File]::WriteAllText((Join-Path $root '.install-name'), $Name, [Text.UTF8Encoding]::new($false))
        $install += ' --name-file .install-name'
    }
    try {
        $items = @('.gitattributes','.gitignore','install.sh','uninstall.sh','SHA256SUMS','bin','etc','build','docs','windows','tests','README.md','NOTICE.md','LICENSE','Install-Windows.cmd')
        if ($Name) { $items += '.install-name' }
        Invoke-Native 'tar.exe' (@('-czf', $archive, '-C', $root) + $items)
        Invoke-Native 'ssh.exe' ($sshOptions + @($target, "umask 077; mkdir $stage"))
        Invoke-Native 'scp.exe' ($scpOptions + @($archive, "${target}:$stage/bundle.tar.gz"))
        Invoke-Native 'ssh.exe' ($sshOptions + @($target, "set -eu; cd $stage; tar xzf bundle.tar.gz; $install"))
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
