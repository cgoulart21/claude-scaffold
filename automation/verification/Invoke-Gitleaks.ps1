<#
  Invoke-Gitleaks.ps1

  Thin wrapper around gitleaks for a staged-changes scan, meant to be called from
  a pre-commit hook. Secrets are its job and nothing else's: the sanitization gate
  in tools/ looks for identity and location, not credentials, and neither one
  covers the other.

  Exit codes: 0 clean, 1 findings, 2 could not run.
  The third one exists so that a missing binary never reports success.

  ASCII-only and dependency-free for Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$GitleaksPath,
    [string]$RepositoryPath,
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($GitleaksPath)) {
    $GitleaksPath = Join-Path $env:USERPROFILE '.local\bin\gitleaks.exe'
}
if ([string]::IsNullOrEmpty($RepositoryPath)) { $RepositoryPath = (Get-Location).Path }

if (-not (Test-Path -LiteralPath $GitleaksPath -PathType Leaf)) {
    Write-Output "ERROR gitleaks not found at $GitleaksPath"
    Write-Output 'Install it first: stack/manifest.md, section 6, has the version, the URL and'
    Write-Output 'the checksum step. That lives in stack/ because a version number ages and this'
    Write-Output 'folder does not.'
    exit 2
}
if (-not (Test-Path -LiteralPath (Join-Path $RepositoryPath '.git'))) {
    Write-Output "ERROR not a git repository: $RepositoryPath"
    exit 2
}

# `gitleaks git --pre-commit --staged <repo>` is the current form. `protect --staged` is
# deprecated since 8.19 (hidden from --help, still accepted) and a future bump removes it;
# with 8.30.1 pinned this wrapper would then exit 126 on every commit. The repository is a
# positional argument here, not --source. Changed 2026-09-20 after a second machine's audit.
$arguments = @('git', '--pre-commit', '--staged', '--no-banner', '--redact', $RepositoryPath)
if (-not [string]::IsNullOrEmpty($ConfigPath) -and (Test-Path -LiteralPath $ConfigPath)) {
    $arguments += @('--config', $ConfigPath)
}

$previous = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $output = & $GitleaksPath @arguments 2>&1
    $code = $LASTEXITCODE
}
finally { $ErrorActionPreference = $previous }

# --redact is not decoration. Without it a finding prints the secret into your
# terminal, your scrollback and any transcript being captured - so the tool that
# caught the leak becomes the second place it leaked.
if ($code -eq 0) {
    Write-Output 'gitleaks: no findings in the staged changes.'
    exit 0
}
if ($code -eq 1) {
    Write-Output 'gitleaks: FINDINGS in the staged changes. Values are redacted below.'
    Write-Output ($output -join [Environment]::NewLine)
    exit 1
}

Write-Output "gitleaks: could not run (exit $code). This is not a clean result."
Write-Output ($output -join [Environment]::NewLine)
exit 2
