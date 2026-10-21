[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)][int]$ProxyPort = 20808,
    [string]$ConfigPath = 'C:\ProgramData\ClaudeSingBox\config.json',
    [switch]$CheckExit
)

$ErrorActionPreference = 'Stop'
$package = Get-AppxPackage -Name 'Claude' | Sort-Object Version -Descending | Select-Object -First 1
if ($package) {
    Write-Output "Claude package: $($package.PackageFullName)"
    Write-Output "Package family: $($package.PackageFamilyName)"
} else { Write-Warning 'Claude Desktop MSIX package was not found.' }

foreach ($port in @($ProxyPort, 7890) | Select-Object -Unique) {
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
    if ($listeners.Count -eq 0) { Write-Output "Listener ${port}: none" }
    else {
        foreach ($listener in $listeners) {
            $processName = try { (Get-Process -Id $listener.OwningProcess -ErrorAction Stop).ProcessName } catch { 'unknown' }
            Write-Output "Listener ${port}: $($listener.LocalAddress) PID=$($listener.OwningProcess) Process=$processName"
        }
    }
}

foreach ($process in @(Get-Process -Name 'Claude' -ErrorAction SilentlyContinue)) {
    foreach ($connection in @(Get-NetTCPConnection -OwningProcess $process.Id -State Established -ErrorAction SilentlyContinue)) {
        Write-Output "Claude connection: PID=$($process.Id) $($connection.LocalAddress):$($connection.LocalPort) -> $($connection.RemoteAddress):$($connection.RemotePort)"
    }
}

if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        if (@($config.inbounds | Where-Object { $_.type -eq 'tun' }).Count -gt 0) { Write-Warning "TUN inbound detected in $ConfigPath; this is not desktop-only isolation." }
        else { Write-Output 'TUN inbound: none' }
        foreach ($outbound in @($config.outbounds)) {
            if ($outbound.server) {
                $userState = if ($outbound.username) { '<configured>' } else { '<none>' }
                Write-Output "Upstream: type=$($outbound.type) server=$($outbound.server) port=$($outbound.server_port) username=$userState password=<hidden>"
            }
        }
    } catch { Write-Warning "Could not parse sing-box config: $($_.Exception.Message)" }
} else { Write-Warning "sing-box config not found: $ConfigPath" }

$firewallRules = @(Get-NetFirewallRule -Group 'Claude Desktop Proxy Only (Package)' -ErrorAction SilentlyContinue)
Write-Output "Claude package firewall rules: $($firewallRules.Count)"
foreach ($rule in $firewallRules) {
    $portFilter = $rule | Get-NetFirewallPortFilter
    Write-Output "Firewall: $($rule.Name) Enabled=$($rule.Enabled) Action=$($rule.Action) Protocol=$($portFilter.Protocol) RemotePort=$($portFilter.RemotePort)"
}

if ($CheckExit) {
    $listener = Get-NetTCPConnection -State Listen -LocalAddress '127.0.0.1' -LocalPort $ProxyPort -ErrorAction SilentlyContinue
    if (-not $listener) { throw "Cannot check exit: no listener on 127.0.0.1:$ProxyPort" }
    $exit = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -Proxy "http://127.0.0.1:$ProxyPort" -TimeoutSec 20
    Write-Output "Exit: ip=$($exit.ip) country=$($exit.country) region=$($exit.region) city=$($exit.city) org=$($exit.org)"
}
