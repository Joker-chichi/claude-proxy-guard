[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Server,
    [Parameter(Mandatory = $true)][ValidateRange(1, 65535)][int]$ServerPort,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Username,
    [ValidateSet('http', 'socks')][string]$Protocol = 'http',
    [ValidateRange(1024, 65535)][int]$ProxyPort = 20808,
    [Security.SecureString]$Password,
    [string]$SingBoxPath,
    [string]$RuntimeRoot = 'C:\ProgramData\ClaudeProxyGuard',
    [string]$TaskName = 'ClaudeSingBox',
    [switch]$CheckExit,
    [switch]$SkipShortcuts,
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

function New-GuardShortcut {
    param([string]$Path, [string]$PowerShellPath, [string]$Arguments, [string]$WorkingDirectory)
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $PowerShellPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Save()
}

$runtimeScripts = Join-Path $RuntimeRoot 'scripts'
$configPath = Join-Path $RuntimeRoot 'config.json'
$sourceScripts = $PSScriptRoot
$filesToInstall = @(
    'inspect-claude-proxy.ps1', 'install-singbox-task.ps1', 'launch-clean-browser.ps1',
    'launch-claude.ps1', 'set-claude-package-firewall.ps1', 'start-singbox.ps1',
    'uninstall.ps1', 'write-singbox-config.ps1'
)
foreach ($file in $filesToInstall) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceScripts $file))) { throw "Required runtime script is missing: $file" }
}

Write-Output "Runtime: $RuntimeRoot"
Write-Output "Config: $configPath"
Write-Output "Listener: 127.0.0.1:$ProxyPort"
Write-Output "Upstream: ${Protocol}://$Server`:$ServerPort (credentials hidden)"
Write-Output "Task: $TaskName"
if ($PlanOnly) {
    & (Join-Path $sourceScripts 'set-claude-package-firewall.ps1') -ProxyPort $ProxyPort -PlanOnly
    & (Join-Path $sourceScripts 'install-singbox-task.ps1') -TaskName $TaskName -StartScriptPath (Join-Path $runtimeScripts 'start-singbox.ps1') -ConfigPath $configPath -ProxyPort $ProxyPort -PlanOnly
    exit 0
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this installer from an elevated PowerShell window.' }
$resolvedSingBox = Resolve-SingBoxPath -RequestedPath $SingBoxPath

[IO.Directory]::CreateDirectory($runtimeScripts) | Out-Null
foreach ($file in $filesToInstall) {
    Copy-Item -LiteralPath (Join-Path $sourceScripts $file) -Destination (Join-Path $runtimeScripts $file) -Force
}

$writeConfigArgs = @{
    Server = $Server; ServerPort = $ServerPort; Username = $Username; Protocol = $Protocol
    ListenPort = $ProxyPort; OutputPath = $configPath; SingBoxPath = $resolvedSingBox
}
if ($Password) { $writeConfigArgs.Password = $Password }
& (Join-Path $runtimeScripts 'write-singbox-config.ps1') @writeConfigArgs

& (Join-Path $runtimeScripts 'set-claude-package-firewall.ps1') -ProxyPort $ProxyPort

$listener = Get-NetTCPConnection -State Listen -LocalAddress '127.0.0.1' -LocalPort $ProxyPort -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    $owner = Get-Process -Id $listener.OwningProcess -ErrorAction Stop
    if ($owner.ProcessName -ne 'sing-box') { throw "Port 127.0.0.1:$ProxyPort is owned by $($owner.ProcessName)." }
    $details = Get-CimInstance Win32_Process -Filter "ProcessId=$($owner.Id)" -ErrorAction Stop
    if (-not $details.CommandLine -or $details.CommandLine.IndexOf($configPath, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        Stop-Process -Id $owner.Id -Force
        Start-Sleep -Seconds 1
    }
}

& (Join-Path $runtimeScripts 'install-singbox-task.ps1') `
    -TaskName $TaskName -StartScriptPath (Join-Path $runtimeScripts 'start-singbox.ps1') `
    -ConfigPath $configPath -SingBoxPath $resolvedSingBox -ProxyPort $ProxyPort

$deadline = (Get-Date).AddSeconds(45)
do {
    Start-Sleep -Milliseconds 500
    $listener = Get-NetTCPConnection -State Listen -LocalAddress '127.0.0.1' -LocalPort $ProxyPort -ErrorAction SilentlyContinue | Select-Object -First 1
} until ($listener -or (Get-Date) -gt $deadline)
if (-not $listener) { throw 'Installation completed, but the dedicated proxy listener did not start.' }
$owner = Get-Process -Id $listener.OwningProcess -ErrorAction Stop
if ($owner.ProcessName -ne 'sing-box') { throw "Listener validation failed: port 127.0.0.1:$ProxyPort is owned by $($owner.ProcessName)." }
$details = Get-CimInstance Win32_Process -Filter "ProcessId=$($owner.Id)" -ErrorAction Stop
if (-not $details.CommandLine -or $details.CommandLine.IndexOf($configPath, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
    throw "Listener validation failed: sing-box is not using the installed config $configPath. Firewall protection remains fail-closed."
}

if (-not $SkipShortcuts) {
    $powerShellPath = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $powerShellPath)) { $powerShellPath = (Get-Command powershell.exe -ErrorAction Stop).Source }
    $desktop = [Environment]::GetFolderPath('Desktop')
    $claudeArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $runtimeScripts 'launch-claude.ps1')`" -ConfigPath `"$configPath`" -SingBoxPath `"$resolvedSingBox`" -ProxyPort $ProxyPort"
    $browserArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $runtimeScripts 'launch-clean-browser.ps1')`" -ExpectedConfigPath `"$configPath`" -ProxyPort $ProxyPort"
    New-GuardShortcut -Path (Join-Path $desktop 'Claude (Proxy Guard).lnk') -PowerShellPath $powerShellPath -Arguments $claudeArgs -WorkingDirectory $RuntimeRoot
    New-GuardShortcut -Path (Join-Path $desktop 'Claude Clean Browser.lnk') -PowerShellPath $powerShellPath -Arguments $browserArgs -WorkingDirectory $RuntimeRoot
}

& (Join-Path $runtimeScripts 'set-claude-package-firewall.ps1') -ProxyPort $ProxyPort -ValidateOnly
$inspectArgs = @{ ProxyPort = $ProxyPort; ConfigPath = $configPath }
if ($CheckExit) { $inspectArgs.CheckExit = $true }
& (Join-Path $runtimeScripts 'inspect-claude-proxy.ps1') @inspectArgs
Write-Output 'Claude Proxy Guard installation passed local validation.'
