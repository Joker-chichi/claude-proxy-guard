[CmdletBinding()]
param(
    [ValidateRange(2, 65534)][int]$ProxyPort = 20808,
    [string]$PackageName = 'Claude',
    [string]$PackageFamilyName,
    [switch]$PlanOnly,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$groupName = 'Claude Desktop Proxy Only (Package)'
$legacyGroup = 'Claude Desktop Kill Switch'
$legacyPrefix = 'Claude Desktop Proxy Only'
if ($PackageFamilyName) { $familyName = $PackageFamilyName }
else {
    $package = Get-AppxPackage -Name $PackageName | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $package) { throw "Claude Desktop package '$PackageName' was not found." }
    $familyName = $package.PackageFamilyName
}

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
    param([hashtable]$Spec, [string]$RuleName = $Spec.Name)
    $rule = Get-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue
    if (-not $rule) { return $false }
    $port = $rule | Get-NetFirewallPortFilter
    $app = $rule | Get-NetFirewallApplicationFilter
    $address = $rule | Get-NetFirewallAddressFilter
    $returnedFamily = if ($app.PackageFamilyName) { $app.PackageFamilyName } else { $app.Package }
    $actualAddresses = @($address.RemoteAddress | ForEach-Object { $_.ToString() } | Sort-Object)
    $expectedAddresses = @($Spec.RemoteAddress | ForEach-Object { $_.ToString() } | Sort-Object)
    $actualProtocol = $port.Protocol.ToString()
    $protocolMatches = $actualProtocol -eq $Spec.Protocol -or
        ($Spec.Protocol -eq 'TCP' -and $actualProtocol -eq '6') -or
        ($Spec.Protocol -eq 'UDP' -and $actualProtocol -eq '17')
    return ($rule.Enabled.ToString() -eq 'True' -and
        $rule.Direction.ToString() -eq 'Outbound' -and
        $rule.Action.ToString() -eq 'Block' -and
        $protocolMatches -and
        (@($port.RemotePort) -join ',') -eq $Spec.RemotePort -and
        ($actualAddresses -join ',') -eq ($expectedAddresses -join ',') -and
        $returnedFamily -eq $familyName)
}

function Add-Rule {
    param([hashtable]$Spec, [string]$RuleName, [string]$RuleGroup)
    New-NetFirewallRule -Name $RuleName -DisplayName $RuleName `
        -Description "Fail-closed Claude Desktop egress; only IPv4 127.0.0.1:$ProxyPort remains reachable." `
        -Group $RuleGroup -Enabled True -Profile Any -Direction Outbound -Action Block `
        -Protocol $Spec.Protocol -RemotePort $Spec.RemotePort -RemoteAddress $Spec.RemoteAddress `
        -PackageFamilyName $familyName | Out-Null
}

if ($ValidateOnly) {
    $failed = @($rules | Where-Object { -not (Test-Rule -Spec $_) })
    if ($failed.Count -gt 0) { throw "Firewall validation failed for: $($failed.Name -join ', ')" }
    Write-Output "Firewall validation passed. Claude can reach only IPv4 127.0.0.1:$ProxyPort."
    exit 0
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this script from an elevated PowerShell window.' }

$transactionId = [Guid]::NewGuid().ToString('N')
$stagingGroup = "$groupName (Staging $transactionId)"
$staged = @()
try {
    for ($index = 0; $index -lt $rules.Count; $index++) {
        $spec = $rules[$index]
        if (Test-Rule -Spec $spec) { continue }
        $stageName = "ClaudeProxyOnly-Stage-$transactionId-$index"
        Add-Rule -Spec $spec -RuleName $stageName -RuleGroup $stagingGroup
        if (-not (Test-Rule -Spec $spec -RuleName $stageName)) { throw "Staging firewall validation failed for $($spec.Name)." }
        $staged += @{ Spec = $spec; Name = $stageName }
    }

    foreach ($item in $staged) {
        Get-NetFirewallRule -Name $item.Spec.Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        Add-Rule -Spec $item.Spec -RuleName $item.Spec.Name -RuleGroup $groupName
        if (-not (Test-Rule -Spec $item.Spec)) { throw "Final firewall validation failed for $($item.Spec.Name). Staging protection remains active." }
    }

    $failed = @($rules | Where-Object { -not (Test-Rule -Spec $_) })
    if ($failed.Count -gt 0) { throw "Final firewall validation failed for: $($failed.Name -join ', ')" }

    $desiredNames = @($rules.Name)
    Get-NetFirewallRule -Group $groupName -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $desiredNames } |
        Remove-NetFirewallRule
    Get-NetFirewallRule -Group $legacyGroup -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object { $_.Group -like "$legacyPrefix*" -and $_.Group -ne $groupName } |
        Remove-NetFirewallRule
}
catch {
    Write-Warning "Firewall update did not complete. Staging block rules were intentionally left active in group '$stagingGroup'."
    throw
}

Write-Output "Firewall applied transactionally. Claude can reach only IPv4 127.0.0.1:$ProxyPort."
