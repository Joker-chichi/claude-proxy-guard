[CmdletBinding()]
param(
    [ValidateRange(2, 65534)][int]$ProxyPort = 20808,
    [string]$PackageName = 'Claude',
    [switch]$PlanOnly,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$groupName = 'Claude Desktop Proxy Only (Package)'
$package = Get-AppxPackage -Name $PackageName | Sort-Object Version -Descending | Select-Object -First 1
if (-not $package) { throw "Claude Desktop package '$PackageName' was not found." }
$familyName = $package.PackageFamilyName
$rules = @(
    @{ Name = 'ClaudeProxyOnly-Package-TCP-Low'; Protocol = 'TCP'; RemotePort = "1-$($ProxyPort - 1)"; RemoteAddress = 'Any' },
    @{ Name = 'ClaudeProxyOnly-Package-TCP-High'; Protocol = 'TCP'; RemotePort = "$($ProxyPort + 1)-65535"; RemoteAddress = 'Any' },
    @{ Name = 'ClaudeProxyOnly-Package-TCP-ProxyPort-NonLoopback-v4'; Protocol = 'TCP'; RemotePort = "$ProxyPort"; RemoteAddress = @('0.0.0.0-127.0.0.0', '127.0.0.2-255.255.255.255') },
    @{ Name = 'ClaudeProxyOnly-Package-TCP-ProxyPort-IPv6'; Protocol = 'TCP'; RemotePort = "$ProxyPort"; RemoteAddress = '::/0' },
    @{ Name = 'ClaudeProxyOnly-Package-UDP-All'; Protocol = 'UDP'; RemotePort = 'Any'; RemoteAddress = 'Any' }
)

if ($PlanOnly) {
    Write-Output "Package family: $familyName"
    Write-Output "Only IPv4 127.0.0.1:$ProxyPort will remain reachable by Claude."
    $rules | ForEach-Object { Write-Output ("{0}|{1}|{2}|{3}" -f $_.Name, $_.Protocol, $_.RemotePort, ($_.RemoteAddress -join ',')) }
    exit 0
}

function Test-Rule {
    param([hashtable]$Spec)
    $rule = Get-NetFirewallRule -Name $Spec.Name -ErrorAction SilentlyContinue
    if (-not $rule) { return $false }
    $port = $rule | Get-NetFirewallPortFilter
    $app = $rule | Get-NetFirewallApplicationFilter
    $address = $rule | Get-NetFirewallAddressFilter
    $returnedFamily = if ($app.PackageFamilyName) { $app.PackageFamilyName } else { $app.Package }
    $actualAddresses = @($address.RemoteAddress | ForEach-Object { $_.ToString() } | Sort-Object)
    $expectedAddresses = @($Spec.RemoteAddress | ForEach-Object { $_.ToString() } | Sort-Object)
    return ($rule.Enabled.ToString() -eq 'True' -and
        $rule.Direction.ToString() -eq 'Outbound' -and
        $rule.Action.ToString() -eq 'Block' -and
        $port.Protocol.ToString() -eq $Spec.Protocol -and
        ($port.RemotePort -join ',') -eq $Spec.RemotePort -and
        ($actualAddresses -join ',') -eq ($expectedAddresses -join ',') -and
        (-not $returnedFamily -or $returnedFamily -eq $familyName))
}

if ($ValidateOnly) {
    $failed = @($rules | Where-Object { -not (Test-Rule -Spec $_) })
    if ($failed.Count -gt 0) { throw "Firewall validation failed for: $($failed.Name -join ', ')" }
    Write-Output "Firewall validation passed. Claude can reach only IPv4 127.0.0.1:$ProxyPort."
    exit 0
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this script from an elevated PowerShell window.' }

Get-NetFirewallRule -Group $groupName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
foreach ($spec in $rules) {
    New-NetFirewallRule -Name $spec.Name -DisplayName $spec.Name `
        -Description "Fail-closed Claude Desktop egress; only IPv4 127.0.0.1:$ProxyPort remains reachable." `
        -Group $groupName -Enabled True -Profile Any -Direction Outbound -Action Block `
        -Protocol $spec.Protocol -RemotePort $spec.RemotePort -RemoteAddress $spec.RemoteAddress `
        -PackageFamilyName $familyName | Out-Null
}
$failed = @($rules | Where-Object { -not (Test-Rule -Spec $_) })
if ($failed.Count -gt 0) { throw "Firewall rules were created but validation failed for: $($failed.Name -join ', ')" }
Write-Output "Firewall applied. Claude can reach only IPv4 127.0.0.1:$ProxyPort."
