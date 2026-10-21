[CmdletBinding()]
param(
    [string]$SingBoxPath,
    [string]$ConfigPath = 'C:\ProgramData\ClaudeProxyGuard\config.json',
    [string]$LogPath = 'C:\ProgramData\ClaudeProxyGuard\sing-box.log',
    [ValidateRange(1024, 65535)][int]$ProxyPort = 20808,
    [ValidateRange(1, 1024)][int]$MaxLogSizeMB = 20,
    [switch]$AllowTun,
    [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-SingBoxPath {
    param([string]$RequestedPath)
    if ($RequestedPath) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) { throw "sing-box executable not found: $RequestedPath" }
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }
    $command = Get-Command 'sing-box.exe' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $packageRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $candidate = Get-ChildItem -LiteralPath $packageRoot -Filter 'sing-box.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*SagerNet.sing-box*' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $candidate) { throw 'sing-box.exe was not found. Install it with WinGet or pass -SingBoxPath.' }
    return $candidate.FullName
}

$resolvedSingBox = Resolve-SingBoxPath -RequestedPath $SingBoxPath
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "sing-box config not found: $ConfigPath" }
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$tunInbounds = @($config.inbounds | Where-Object { $_.type -eq 'tun' })
if ($tunInbounds.Count -gt 0 -and -not $AllowTun) { throw 'TUN inbound detected. Desktop-only mode refuses to start it.' }
$loopbackInbound = @($config.inbounds | Where-Object {
    $_.type -eq 'mixed' -and $_.listen -eq '127.0.0.1' -and [int]$_.listen_port -eq $ProxyPort
})
if ($loopbackInbound.Count -ne 1) { throw "Expected exactly one mixed inbound on 127.0.0.1:$ProxyPort." }

& $resolvedSingBox check -c $ConfigPath
if ($LASTEXITCODE -ne 0) { throw "sing-box config check failed with exit code $LASTEXITCODE." }

$existing = @(Get-NetTCPConnection -State Listen -LocalAddress '127.0.0.1' -LocalPort $ProxyPort -ErrorAction SilentlyContinue)
if ($existing.Count -gt 0) {
    $owners = @($existing | ForEach-Object { Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue })
    if (@($owners | Where-Object { $_.ProcessName -ne 'sing-box' }).Count -gt 0) {
        throw "Port 127.0.0.1:$ProxyPort is owned by a process other than sing-box."
    }
    foreach ($owner in $owners) {
        $details = Get-CimInstance Win32_Process -Filter "ProcessId=$($owner.Id)" -ErrorAction Stop
        if (-not $details.CommandLine -or $details.CommandLine.IndexOf($ConfigPath, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            throw "The existing sing-box listener is using a different config than expected: $ConfigPath"
        }
    }
    Write-Output "sing-box is already listening on 127.0.0.1:$ProxyPort."
    exit 0
}

Write-Output "sing-box: $resolvedSingBox"
Write-Output "config: $ConfigPath"
Write-Output "listener: 127.0.0.1:$ProxyPort"
if ($PlanOnly) { exit 0 }

if (Test-Path -LiteralPath $LogPath) {
    $log = Get-Item -LiteralPath $LogPath
    if ($log.Length -gt ($MaxLogSizeMB * 1MB)) {
        $previousLog = "$LogPath.previous"
        Remove-Item -LiteralPath $previousLog -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath $LogPath -Destination $previousLog
    }
}

& $resolvedSingBox run -c $ConfigPath
exit $LASTEXITCODE
