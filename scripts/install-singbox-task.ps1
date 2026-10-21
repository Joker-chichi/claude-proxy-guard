[CmdletBinding()]
param(
    [string]$TaskName = 'ClaudeSingBox',
    [string]$StartScriptPath = (Join-Path $PSScriptRoot 'start-singbox.ps1'),
    [ValidateRange(1024, 65535)][int]$ProxyPort = 20808,
    [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $StartScriptPath -PathType Leaf)) { throw "Start script not found: $StartScriptPath" }
$powerShellPath = Join-Path $PSHOME 'powershell.exe'
if (-not (Test-Path -LiteralPath $powerShellPath)) { $powerShellPath = (Get-Command powershell.exe -ErrorAction Stop).Source }
$arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$StartScriptPath`" -ProxyPort $ProxyPort"
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

Write-Output "Task: $TaskName"
Write-Output "User: $currentUser"
Write-Output "Action: $powerShellPath $arguments"
Write-Output 'Trigger: at user logon; restart up to 3 times after failure'
if ($PlanOnly) { exit 0 }

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this script from an elevated PowerShell window.' }

$action = New-ScheduledTaskAction -Execute $powerShellPath -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $taskPrincipal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Write-Output "Installed and started scheduled task: $TaskName"
