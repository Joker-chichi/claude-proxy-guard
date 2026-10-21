[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Edge', 'Chrome')][string]$Browser = 'Auto',
    [ValidateRange(1024, 65535)][int]$ProxyPort = 20808,
    [string]$ProfilePath = (Join-Path $env:LOCALAPPDATA 'ClaudeProxyGuard\BrowserProfile'),
    [ValidatePattern('^https?://')][string]$StartUrl = 'https://ip.net.coffee/claude/',
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
    $listener = Get-NetTCPConnection -State Listen -LocalAddress '127.0.0.1' -LocalPort $ProxyPort -ErrorAction SilentlyContinue
    if (-not $listener) { throw "Dedicated proxy is not listening on 127.0.0.1:$ProxyPort. Browser was not opened." }
    [IO.Directory]::CreateDirectory($ProfilePath) | Out-Null
}

$arguments = @(
    "--user-data-dir=`"$ProfilePath`"",
    '--disable-extensions',
    "--proxy-server=http://127.0.0.1:$ProxyPort",
    '--disable-quic',
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
Write-Output 'Opened the dedicated extension-free browser profile.'
Write-Output 'If it is closed, rerun this launcher before visiting or signing in to Claude.'
