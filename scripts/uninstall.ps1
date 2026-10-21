[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\ProgramData\ClaudeProxyGuard',
    [string]$TaskName = 'ClaudeSingBox',
    [switch]$RestoreLatestConfig,
    [switch]$ArchiveRuntime,
    [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'
$configPath = Join-Path $RuntimeRoot 'config.json'
$groupName = 'Claude Desktop Proxy Only (Package)'
$legacyGroup = 'Claude Desktop Kill Switch'
$legacyPrefix = 'Claude Desktop Proxy Only'
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcuts = @(
    (Join-Path $desktop 'Claude (Proxy Guard).lnk'),
    (Join-Path $desktop 'Claude Clean Browser.lnk')
)

Write-Output "Would remove task: $TaskName"
Write-Output "Would remove Claude Proxy Guard firewall groups and shortcuts."
Write-Output "Runtime files are preserved unless -ArchiveRuntime is supplied: $RuntimeRoot"
if ($PlanOnly) { exit 0 }

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this uninstaller from an elevated PowerShell window.' }

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Get-CimInstance Win32_Process -Filter "Name='sing-box.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($configPath, [StringComparison]::OrdinalIgnoreCase) -ge 0 } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Get-NetFirewallRule -Group $groupName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
Get-NetFirewallRule -Group $legacyGroup -ErrorAction SilentlyContinue | Remove-NetFirewallRule
Get-NetFirewallRule -ErrorAction SilentlyContinue |
    Where-Object { $_.Group -like "$legacyPrefix*" } |
    Remove-NetFirewallRule

foreach ($shortcut in $shortcuts) { Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue }

if ($RestoreLatestConfig -and (Test-Path -LiteralPath $RuntimeRoot)) {
    $latestBackup = Get-ChildItem -LiteralPath $RuntimeRoot -Filter 'config.json.backup-*' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latestBackup) { throw 'No configuration backup is available to restore.' }
    Copy-Item -LiteralPath $latestBackup.FullName -Destination $configPath -Force
    Write-Output "Restored configuration backup: $($latestBackup.FullName)"
}

if ($ArchiveRuntime -and (Test-Path -LiteralPath $RuntimeRoot)) {
    $archivePath = "$RuntimeRoot.removed-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Set-Location -LiteralPath (Split-Path -Parent $RuntimeRoot)
    Move-Item -LiteralPath $RuntimeRoot -Destination $archivePath
    Write-Output "Archived runtime for recovery: $archivePath"
}

Write-Output 'Claude Proxy Guard task, firewall rules, and shortcuts were removed. Browser and Claude profile data were preserved.'
