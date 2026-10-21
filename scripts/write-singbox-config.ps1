[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Server,
    [Parameter(Mandatory = $true)][ValidateRange(1, 65535)][int]$ServerPort,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Username,
    [ValidateSet('http', 'socks')][string]$Protocol = 'http',
    [ValidateRange(1024, 65535)][int]$ListenPort = 20808,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutputPath,
    [Security.SecureString]$Password,
    [string]$SingBoxPath,
    [ValidateRange(1, 20)][int]$BackupRetention = 3,
    [switch]$SkipValidation,
    [switch]$SkipAcl
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

function Set-RestrictedConfigAcl {
    param([string]$Path)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $acl = New-Object Security.AccessControl.FileSecurity
    $acl.SetOwner($identity.User)
    $inheritance = [Security.AccessControl.InheritanceFlags]::None
    $propagation = [Security.AccessControl.PropagationFlags]::None
    $allow = [Security.AccessControl.AccessControlType]::Allow
    $full = [Security.AccessControl.FileSystemRights]::FullControl
    foreach ($sidText in @($identity.User.Value, 'S-1-5-18', 'S-1-5-32-544')) {
        $sid = New-Object Security.Principal.SecurityIdentifier($sidText)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, $full, $inheritance, $propagation, $allow)
        [void]$acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

if (-not $Password) { $Password = Read-Host 'Proxy password (input is hidden)' -AsSecureString }
$parent = Split-Path -Parent $OutputPath
if (-not $parent) { throw 'OutputPath must include a parent directory.' }
$leaf = Split-Path -Leaf $OutputPath
$tempPath = Join-Path $parent (".$leaf.{0}.tmp" -f [Guid]::NewGuid().ToString('N'))
$passwordPtr = [IntPtr]::Zero

try {
    $passwordPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPtr)
    if ([string]::IsNullOrEmpty($plainPassword)) { throw 'Proxy password cannot be empty.' }

    $config = [ordered]@{
        log = [ordered]@{ level = 'warn'; timestamp = $true; output = (Join-Path $parent 'sing-box.log').Replace('\', '/') }
        inbounds = @([ordered]@{ type = 'mixed'; tag = 'claude-proxy-in'; listen = '127.0.0.1'; listen_port = $ListenPort })
        outbounds = @([ordered]@{ type = $Protocol; tag = 'proxy-out'; server = $Server; server_port = $ServerPort; username = $Username; password = $plainPassword })
        route = [ordered]@{
            rules = @([ordered]@{ inbound = @('claude-proxy-in'); outbound = 'proxy-out' })
            final = 'proxy-out'
        }
    }
    $json = $config | ConvertTo-Json -Depth 10

    if (-not $PSCmdlet.ShouldProcess($OutputPath, 'Validate, back up, and atomically replace sing-box configuration')) {
        Write-Output "Would write loopback-only sing-box config: $OutputPath"
        exit 0
    }

    [IO.Directory]::CreateDirectory($parent) | Out-Null
    [IO.File]::WriteAllText($tempPath, $json, (New-Object Text.UTF8Encoding($false)))
    if (-not $SkipAcl) { Set-RestrictedConfigAcl -Path $tempPath }

    if (-not $SkipValidation) {
        $resolvedSingBox = Resolve-SingBoxPath -RequestedPath $SingBoxPath
        & $resolvedSingBox check -c $tempPath
        if ($LASTEXITCODE -ne 0) { throw "sing-box config check failed with exit code $LASTEXITCODE." }
    }

    if (Test-Path -LiteralPath $OutputPath) {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $backupPath = Join-Path $parent ("$leaf.backup-$timestamp")
        [IO.File]::Replace($tempPath, $OutputPath, $backupPath, $true)
        if (-not $SkipAcl) { Set-RestrictedConfigAcl -Path $backupPath }
        Get-ChildItem -LiteralPath $parent -Filter "$leaf.backup-*" -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip $BackupRetention |
            Remove-Item -Force
        Write-Output "Backup: $backupPath"
    } else {
        [IO.File]::Move($tempPath, $OutputPath)
    }
    if (-not $SkipAcl) { Set-RestrictedConfigAcl -Path $OutputPath }
}
finally {
    $plainPassword = $null
    if ($passwordPtr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtr) }
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
}

Write-Output "Wrote loopback-only sing-box config: $OutputPath"
Write-Output "Local listener: http://127.0.0.1:$ListenPort"
Write-Output "Upstream: ${Protocol}://$Server`:$ServerPort (credentials hidden)"
