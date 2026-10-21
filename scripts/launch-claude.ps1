[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)][int]$ProxyPort = 20808,
    [string]$TaskName = 'ClaudeSingBox',
    [string]$StartSingBoxScript = (Join-Path $PSScriptRoot 'start-singbox.ps1'),
    [string]$ConfigPath = 'C:\ProgramData\ClaudeSingBox\config.json',
    [string]$SingBoxPath,
    [string]$UserDataDir = (Join-Path $env:LOCALAPPDATA 'ClaudeProxyGuard\ClaudeProfile'),
    [string]$PackageName = 'Claude',
    [ValidateRange(5, 120)][int]$StartupTimeoutSeconds = 45,
    [switch]$RepairPackage,
    [switch]$SkipFirewallValidation,
    [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'
$proxyHost = '127.0.0.1'
$proxyUrl = "http://${proxyHost}:$ProxyPort"

function Get-HealthyClaudePackage {
    $package = Get-AppxPackage -Name $PackageName | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $package) { throw "Claude Desktop package '$PackageName' was not found." }
    if ($package.Status.ToString() -ne 'Ok') {
        if (-not $RepairPackage) { throw "Claude package status is $($package.Status). Rerun with -RepairPackage only after reviewing the diagnosis." }
        Stop-Service -Name 'CoworkVMService' -Force -ErrorAction SilentlyContinue
        $manifest = Join-Path $package.InstallLocation 'AppxManifest.xml'
        Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ForceApplicationShutdown
        $package = Get-AppxPackage -Name $PackageName | Sort-Object Version -Descending | Select-Object -First 1
        if (-not $package -or $package.Status.ToString() -ne 'Ok') { throw 'Claude Desktop package repair failed.' }
    }
    return $package
}

if (-not (Test-Path -LiteralPath $StartSingBoxScript)) { throw "sing-box validation script not found: $StartSingBoxScript" }
$startValidation = @{
    ConfigPath = $ConfigPath
    ProxyPort = $ProxyPort
    PlanOnly = $true
}
if ($SingBoxPath) { $startValidation.SingBoxPath = $SingBoxPath }
& $StartSingBoxScript @startValidation

$package = Get-HealthyClaudePackage
$manifestPath = Join-Path $package.InstallLocation 'AppxManifest.xml'
[xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
$applicationNodes = @($manifest.SelectNodes("//*[local-name()='Application']"))
$application = $applicationNodes | Where-Object {
    $_.GetAttribute('Executable') -match '(^|[\\/])Claude\.exe$'
} | Select-Object -First 1
if (-not $application) { $application = $applicationNodes | Select-Object -First 1 }
if (-not $application) { throw "No Application entry found in $manifestPath" }
$applicationId = $application.GetAttribute('Id')
if ([string]::IsNullOrWhiteSpace($applicationId)) { throw "Application Id is missing in $manifestPath" }
$appUserModelId = "$($package.PackageFamilyName)!$applicationId"

Write-Output "Package: $($package.PackageFullName)"
Write-Output "AppUserModelId: $appUserModelId"
Write-Output "Proxy: $proxyUrl"
Write-Output "Profile: $UserDataDir"
if ($PlanOnly) { exit 0 }

if (-not $SkipFirewallValidation) {
    $firewallScript = Join-Path $PSScriptRoot 'set-claude-package-firewall.ps1'
    if (-not (Test-Path -LiteralPath $firewallScript)) { throw 'Firewall validation script is missing.' }
    & $firewallScript -ProxyPort $ProxyPort -PackageName $PackageName -ValidateOnly
}

$listener = Get-NetTCPConnection -State Listen -LocalAddress $proxyHost -LocalPort $ProxyPort -ErrorAction SilentlyContinue
if (-not $listener) {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) { Start-ScheduledTask -TaskName $TaskName }
    else {
        $powerShellPath = Join-Path $PSHOME 'powershell.exe'
        if (-not (Test-Path -LiteralPath $powerShellPath)) { $powerShellPath = (Get-Command powershell.exe -ErrorAction Stop).Source }
        $startArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $StartSingBoxScript, '-ConfigPath', $ConfigPath, '-ProxyPort', $ProxyPort)
        if ($SingBoxPath) { $startArguments += @('-SingBoxPath', $SingBoxPath) }
        Start-Process -FilePath $powerShellPath -ArgumentList $startArguments -WindowStyle Hidden
    }
    $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 500
        $listener = Get-NetTCPConnection -State Listen -LocalAddress $proxyHost -LocalPort $ProxyPort -ErrorAction SilentlyContinue
    } until ($listener -or (Get-Date) -gt $deadline)
    if (-not $listener) { throw "Dedicated proxy did not start within $StartupTimeoutSeconds seconds." }
}
$owner = Get-Process -Id $listener.OwningProcess -ErrorAction Stop
if ($owner.ProcessName -ne 'sing-box') { throw "Port $proxyHost`:$ProxyPort is not owned by sing-box." }
$ownerDetails = Get-CimInstance Win32_Process -Filter "ProcessId=$($owner.Id)" -ErrorAction Stop
if (-not $ownerDetails.CommandLine -or $ownerDetails.CommandLine.IndexOf($ConfigPath, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
    throw "The listening sing-box process was not started with the expected config: $ConfigPath"
}

[IO.Directory]::CreateDirectory($UserDataDir) | Out-Null
$claudePath = Join-Path $package.InstallLocation 'app\Claude.exe'
$existing = Get-CimInstance Win32_Process -Filter "Name='Claude.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $claudePath }
foreach ($process in $existing) { Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue }
if ($existing) { Start-Sleep -Seconds 2 }

$env:HTTP_PROXY = $proxyUrl
$env:HTTPS_PROXY = $proxyUrl
$env:ALL_PROXY = $proxyUrl
$env:NO_PROXY = 'localhost,127.0.0.1'

$activationSource = @'
using System;
using System.Runtime.InteropServices;
[Flags] public enum ClaudeProxyGuardActivateOptions { None = 0, DesignMode = 1, NoErrorUI = 2, NoSplashScreen = 4 }
[ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IClaudeProxyGuardActivationManager {
    [PreserveSig] int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId, [MarshalAs(UnmanagedType.LPWStr)] string arguments, ClaudeProxyGuardActivateOptions options, out uint processId);
    [PreserveSig] int ActivateForFile([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId, IntPtr itemArray, [MarshalAs(UnmanagedType.LPWStr)] string verb, out uint processId);
    [PreserveSig] int ActivateForProtocol([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId, IntPtr itemArray, out uint processId);
}
[ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
class ClaudeProxyGuardActivationManager {}
public static class ClaudeProxyGuardLauncher {
    public static uint Activate(string appUserModelId, string arguments) {
        var manager = (IClaudeProxyGuardActivationManager)new ClaudeProxyGuardActivationManager();
        uint processId;
        int result = manager.ActivateApplication(appUserModelId, arguments, ClaudeProxyGuardActivateOptions.None, out processId);
        if (result < 0) Marshal.ThrowExceptionForHR(result);
        return processId;
    }
}
'@
if (-not ('ClaudeProxyGuardLauncher' -as [type])) { Add-Type -TypeDefinition $activationSource -Language CSharp }
$claudeArguments = "--proxy-server=$proxyUrl --user-data-dir=`"$UserDataDir`" --disable-quic"
$startedProcessId = [ClaudeProxyGuardLauncher]::Activate($appUserModelId, $claudeArguments)
Start-Sleep -Milliseconds 750
if (-not (Get-Process -Id $startedProcessId -ErrorAction SilentlyContinue)) { throw 'Windows reported activation, but Claude did not remain running.' }
Write-Output "Claude started through the dedicated proxy. PID=$startedProcessId"
