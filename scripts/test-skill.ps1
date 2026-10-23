[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = New-Object Collections.Generic.List[string]

Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File | ForEach-Object {
    $scriptFile = $_
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$errors)
    foreach ($parseError in @($errors)) { $failures.Add("PowerShell parse error in $($scriptFile.Name): $($parseError.Message)") }
}

$skillPath = Join-Path $repoRoot 'SKILL.md'
$skillText = Get-Content -LiteralPath $skillPath -Raw
if ($skillText -notmatch '(?s)^---\s+name:\s+claude-desktop-proxy-guard\s+description:.+?\s+---') {
    $failures.Add('SKILL.md frontmatter is missing or malformed.')
}

$readmeText = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw
$consistencyPath = Join-Path $repoRoot 'references\account-environment-consistency.md'
if (-not (Test-Path -LiteralPath $consistencyPath -PathType Leaf)) {
    $failures.Add('Account-environment consistency reference is missing.')
}
else {
    $consistencyText = Get-Content -LiteralPath $consistencyPath -Raw
    foreach ($requiredPhrase in @('language and time zone', 'dedicated, low-churn endpoint', 'disposable SMS', 'no published Anthropic evidence', 'Chinese passport', 'mobile device clock', 'observation period')) {
        if ($consistencyText -notmatch [Regex]::Escape($requiredPhrase)) {
            $failures.Add("Account-environment consistency reference is missing required guidance: $requiredPhrase")
        }
    }
}
if ($skillText -notmatch 'references/account-environment-consistency\.md') {
    $failures.Add('SKILL.md does not link the account-environment consistency reference.')
}
if ($readmeText -notmatch 'references/account-environment-consistency\.md') {
    $failures.Add('README.md does not link the account-environment consistency reference.')
}

$tempBase = [IO.Path]::GetTempPath()
$testRoot = Join-Path $tempBase ("claude-proxy-guard-test-{0}" -f [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
if (-not $testRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe temporary test path.' }

try {
    $configPath = Join-Path $testRoot 'config.json'
    $password = ConvertTo-SecureString 'dummy-ci-password' -AsPlainText -Force
    & (Join-Path $PSScriptRoot 'write-singbox-config.ps1') `
        -Server '203.0.113.10' -ServerPort 12323 -Username 'test-user' `
        -Password $password -OutputPath $configPath -SkipValidation -SkipAcl | Out-Null
    & (Join-Path $PSScriptRoot 'write-singbox-config.ps1') `
        -Server '203.0.113.11' -ServerPort 12323 -Username 'test-user' `
        -Password $password -OutputPath $configPath -SkipValidation -SkipAcl | Out-Null

    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if (@($config.inbounds).Count -ne 1 -or $config.inbounds[0].type -ne 'mixed') { $failures.Add('Generated config does not have exactly one mixed inbound.') }
    if ($config.inbounds[0].listen -ne '127.0.0.1' -or [int]$config.inbounds[0].listen_port -ne 20808) { $failures.Add('Generated config is not loopback-only on port 20808.') }
    if (@($config.inbounds | Where-Object { $_.type -eq 'tun' }).Count -ne 0) { $failures.Add('Generated config unexpectedly contains a TUN inbound.') }
    if (@(Get-ChildItem -LiteralPath $testRoot -Filter 'config.json.backup-*' -File).Count -ne 1) { $failures.Add('Atomic config update did not create exactly one backup.') }
    if (@(Get-ChildItem -LiteralPath $testRoot -Filter '*.tmp' -File -Force).Count -ne 0) { $failures.Add('Temporary config files were left behind.') }

    & (Join-Path $PSScriptRoot 'set-claude-package-firewall.ps1') -PackageFamilyName 'Claude_TestFamily' -PlanOnly | Out-Null
    & (Join-Path $PSScriptRoot 'uninstall.ps1') -RuntimeRoot (Join-Path $testRoot 'runtime') -PlanOnly | Out-Null
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Get-ChildItem -LiteralPath $testRoot -Recurse -File -Force | Remove-Item -Force
        Get-ChildItem -LiteralPath $testRoot -Recurse -Directory -Force | Sort-Object FullName -Descending | Remove-Item -Force
        Remove-Item -LiteralPath $testRoot -Force
    }
}

if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }
Write-Output 'All Claude Proxy Guard tests passed.'
