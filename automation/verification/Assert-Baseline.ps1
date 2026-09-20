<#
  Assert-Baseline.ps1

  A starting point for a baseline gate: a script that asserts the invariants you
  decided on, and fails loudly when your configuration drifts away from them.

  This ships with three example assertions. They are examples, not a suite - the
  assertions worth having are the ones that encode YOUR decisions, and nobody can
  write those for you. Replace them.

  Exit codes: 0 all assertions passed, 1 at least one failed, 2 could not run.

  ASCII-only and dependency-free for Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$SettingsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($SettingsPath)) {
    $SettingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
}

$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { $script:Pass++; Write-Output "  PASS  $Name" }
    else            { $script:Fail++; Write-Output "  FAIL  $Name" }
}

if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
    Write-Output "ERROR settings file not found: $SettingsPath"
    exit 2
}

try {
    # utf8-sig on purpose: a byte order mark makes a JSON parse fail, and the failure
    # arrives shaped like "your settings are invalid" rather than "I could not read
    # this file". Read with the API that consumes the mark.
    $raw = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8
    $settings = $raw.Substring($raw.IndexOf('{')) | ConvertFrom-Json
}
catch {
    Write-Output "ERROR could not parse $SettingsPath"
    exit 2
}

Write-Output "Baseline assertions against $SettingsPath"

# --- Example 1: a deny rule you never want to lose -------------------------
$deny = @()
if ($settings.PSObject.Properties.Name -contains 'permissions' -and
    $settings.permissions.PSObject.Properties.Name -contains 'deny') {
    $deny = @($settings.permissions.deny)
}
Assert-True 'environment files are denied' (@($deny | Where-Object { $_ -match '\.env' }).Count -gt 0)
Assert-True 'private keys are denied'      (@($deny | Where-Object { $_ -match 'ssh' }).Count -gt 0)

# --- Example 2: the hooks you rely on are wired AND present ----------------
# A hook present on disk is not a hook that fires - and a hook wired in settings is
# not a hook that exists. Both halves fail silently, so both are asserted: an earlier
# version of this file only grepped for the string "PreToolUse", which passes on any
# settings file where somebody typed the word once, including one whose hook scripts
# were deleted months ago.
$wired = ''
if ($settings.PSObject.Properties.Name -contains 'hooks') {
    $wired = ($settings.hooks | ConvertTo-Json -Depth 10 -Compress)
}
Assert-True 'a PreToolUse hook is wired' ($wired -match 'PreToolUse')

$missing = @()
foreach ($hit in [regex]::Matches($wired, '-File\s+\\?["'']?([^"''\\]+(?:\\\\[^"''\\]+)*\.ps1)')) {
    $candidate = $hit.Groups[1].Value -replace '\\\\', '\'
    # Both spellings appear in real settings files and both are expanded by the host:
    # "$env:USERPROFILE" and a bare "$USERPROFILE". Handling only the first produces a
    # false positive on a hook that works perfectly well.
    $expanded = [Environment]::ExpandEnvironmentVariables(($candidate -replace '\$(?:env:)?([A-Za-z_][A-Za-z0-9_]*)', '%$1%'))
    if (-not (Test-Path -LiteralPath $expanded -PathType Leaf)) { $missing += $expanded }
}
Assert-True "every wired hook script exists on disk [$($missing -join '; ')]" ($missing.Count -eq 0)

# A hook that invokes -File "<var>/..." must pair the profile variable with the shell it
# runs under, or the path does not resolve, the hook does not start, and a guard that does
# not start does not block. Each spelling works under exactly one shell:
#   $env:USERPROFILE -> PowerShell only (bash makes it ":USERPROFILE")
#   $USERPROFILE     -> bash only       (PowerShell makes it empty)
# The host runs a hook in bash when Git Bash is installed, powershell otherwise, unless
# "shell" says which. So $env: requires shell "powershell"; a bare $USERPROFILE requires
# NOT shell "powershell". Measured on two machines on 2026-09-20 - the second found the
# powershell routing itself failing, which is why the recommended pairing is the bash one.
# The two spellings are disjoint in text: "$env:USERPROFILE" has no "$USERPROFILE" in it.
$mispaired = @()
if ($settings.PSObject.Properties.Name -contains 'hooks') {
    foreach ($eventName in $settings.hooks.PSObject.Properties.Name) {
        foreach ($group in @($settings.hooks.$eventName)) {
            foreach ($entry in @($group.hooks)) {
                $cmd = [string]$entry.command
                $isPwsh   = ($entry.PSObject.Properties.Name -contains 'shell') -and ([string]$entry.shell -eq 'powershell')
                $usesEnv  = $cmd -match '\$env:USERPROFILE'
                $usesBare = $cmd -match '\$USERPROFILE'
                if ($usesEnv -and -not $isPwsh) { $mispaired += "$eventName (`$env:USERPROFILE needs shell powershell)" }
                if ($usesBare -and $isPwsh)     { $mispaired += "$eventName (`$USERPROFILE breaks under shell powershell)" }
            }
        }
    }
}
Assert-True "every hook pairs its USERPROFILE spelling with its shell [$($mispaired -join '; ')]" ($mispaired.Count -eq 0)

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
