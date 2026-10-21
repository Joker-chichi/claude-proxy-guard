[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Server,
    [Parameter(Mandatory = $true)][ValidateRange(1, 65535)][int]$ServerPort,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Username,
    [ValidateSet('http', 'socks')][string]$Protocol = 'http',
    [ValidateRange(1024, 65535)][int]$ListenPort = 20808,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutputPath,
    [Security.SecureString]$Password,
    [switch]$SkipAcl
)

$ErrorActionPreference = 'Stop'
if (-not $Password) { $Password = Read-Host 'Proxy password (input is hidden)' -AsSecureString }

$passwordPtr = [IntPtr]::Zero
try {
    $passwordPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPtr)
    if ([string]::IsNullOrEmpty($plainPassword)) { throw 'Proxy password cannot be empty.' }

    $config = [ordered]@{
        log = [ordered]@{ level = 'info'; timestamp = $true }
        inbounds = @([ordered]@{ type = 'mixed'; tag = 'claude-proxy-in'; listen = '127.0.0.1'; listen_port = $ListenPort })
        outbounds = @([ordered]@{ type = $Protocol; tag = 'proxy-out'; server = $Server; server_port = $ServerPort; username = $Username; password = $plainPassword })
        route = [ordered]@{
            rules = @([ordered]@{ inbound = @('claude-proxy-in'); outbound = 'proxy-out' })
            final = 'proxy-out'
        }
    }

    $json = $config | ConvertTo-Json -Depth 10
    $parent = Split-Path -Parent $OutputPath
    if (-not $parent) { throw 'OutputPath must include a parent directory.' }
    if ($PSCmdlet.ShouldProcess($OutputPath, 'Write loopback-only sing-box configuration')) {
        [IO.Directory]::CreateDirectory($parent) | Out-Null
        [IO.File]::WriteAllText($OutputPath, $json, (New-Object Text.UTF8Encoding($false)))
        if (-not $SkipAcl) {
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
                $acl.AddAccessRule($rule)
            }
            Set-Acl -LiteralPath $OutputPath -AclObject $acl
        }
    }
}
finally {
    $plainPassword = $null
    if ($passwordPtr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtr) }
}

Write-Output "Wrote loopback-only sing-box config: $OutputPath"
Write-Output "Local listener: http://127.0.0.1:$ListenPort"
Write-Output "Upstream: ${Protocol}://$Server`:$ServerPort (credentials hidden)"
