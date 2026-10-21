[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Edge', 'Chrome')][string]$Browser = 'Auto',
    [ValidateRange(1024, 65535)][int]$ProxyPort = 20808,
    [string]$ProfilePath = (Join-Path $env:LOCALAPPDATA 'ClaudeProxyGuard\BrowserProfile'),

    [string]$ExpectedConfigPath = 'C:\ProgramData\ClaudeProxyGuard\config.json',
    [ValidatePattern('^https?://')][string]$StartUrl = 'https://ip.net.coffee/claude/',
    [switch]$RestartProfileProcess,

    [switch]$PrintOnly
)

$ErrorActionPreference = 'Stop'
$edgeCandidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
)
$chromeCandidates = @(
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
)
$candidates = switch ($Browser) {
    'Edge' { $edgeCandidates }
    'Chrome' { $chromeCandidates }
    default { @($edgeCandidates + $chromeCandidates) }
}
$browserPath = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $browserPath) { throw "No supported browser found for selection: $Browser" }

if (-not $PrintOnly) {
    $listener = Get-NetTCPConnection -State Listen -LocalAddress '127.0.0.1' -LocalPort $ProxyPort -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $listener) { throw "Dedicated proxy is not listening on 127.0.0.1:$ProxyPort. Browser was not opened." }
    $owner = Get-Process -Id $listener.OwningProcess -ErrorAction Stop
    if ($owner.ProcessName -ne 'sing-box') { throw "Port 127.0.0.1:$ProxyPort is not owned by sing-box." }
    $ownerDetails = Get-CimInstance Win32_Process -Filter "ProcessId=$($owner.Id)" -ErrorAction Stop
    if (-not $ownerDetails.CommandLine -or $ownerDetails.CommandLine.IndexOf($ExpectedConfigPath, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "The listening sing-box process was not started with the expected config: $ExpectedConfigPath"
    }

    $existingProfileProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in @('msedge.exe', 'chrome.exe') -and
        $_.CommandLine -and
        $_.CommandLine -like '*--user-data-dir=*' -and
        $_.CommandLine.IndexOf($ProfilePath, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
    $invalidProfileProcesses = @($existingProfileProcesses | Where-Object {
        $_.CommandLine -notlike "*--proxy-server=http://127.0.0.1:$ProxyPort*" -or
        $_.CommandLine -notlike '*--disable-quic*'
    })
    if ($invalidProfileProcesses.Count -gt 0 -and -not $RestartProfileProcess) {
        throw 'The dedicated browser profile is already running without the required proxy flags. Close it or rerun with -RestartProfileProcess.'
    }
    if ($invalidProfileProcesses.Count -gt 0) {
        $invalidProfileProcesses | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 1
    }
    [IO.Directory]::CreateDirectory($ProfilePath) | Out-Null
}

$arguments = @(
    "--user-data-dir=`"$ProfilePath`"",
    '--disable-extensions',
    "--proxy-server=http://127.0.0.1:$ProxyPort",
    '--disable-quic',
    '--disable-background-mode',
    '--force-webrtc-ip-handling-policy=disable_non_proxied_udp',
    '--no-first-run',
    '--no-default-browser-check',
    "`"$StartUrl`""
)

if ($PrintOnly) {
    Write-Output "Browser: $browserPath"
    Write-Output "Profile: $ProfilePath"
    Write-Output "Proxy: http://127.0.0.1:$ProxyPort"
    Write-Output "Arguments: $($arguments -join ' ')"
    exit 0
}

Start-Process -FilePath $browserPath -ArgumentList $arguments
Start-Sleep -Seconds 1
$verified = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -in @('msedge.exe', 'chrome.exe') -and
    $_.CommandLine -and
    $_.CommandLine -like '*--user-data-dir=*' -and
    $_.CommandLine.IndexOf($ProfilePath, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
    $_.CommandLine -like "*--proxy-server=http://127.0.0.1:$ProxyPort*"
})
if ($verified.Count -eq 0) { throw 'Browser started, but the dedicated profile process could not be verified with the required proxy flag.' }
Write-Output 'Opened the dedicated extension-free browser profile.'
Write-Output 'If it is closed, rerun this launcher before visiting or signing in to Claude.'
