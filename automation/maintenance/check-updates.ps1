<#
  check-updates.ps1

  READ-ONLY scan of what is installed versus what is available. It applies
  NOTHING: it reads versions and writes a dated report. Applying an update stays
  a deliberate act, taken while looking at the report.

  That separation is the whole design. An updater that both detects and applies
  will, sooner or later, apply something on a day you were not paying attention -
  and the first you hear of it is a pinned dependency that stopped being pinned.

  Run it from inside an agent session if your host application is sandboxed:
  a process outside that sandbox sees a different set of global packages, and
  reports "not installed" for things that are.

  ASCII-only and dependency-free for Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$ReportRoot
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrEmpty($ReportRoot)) {
    $ReportRoot = Join-Path $env:USERPROFILE '.claude\maintenance'
}
New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null

$today  = Get-Date -Format 'yyyy-MM-dd'
$report = Join-Path $ReportRoot "updates-$today.md"
$latest = Join-Path $ReportRoot 'updates-latest.md'

$script:lines = @()
function Add-Line { param([string]$Text) $script:lines += $Text }

Add-Line "# Update report - $today"
Add-Line ''
Add-Line 'Read-only scan. **Nothing was applied.** Apply deliberately, from the list below.'
Add-Line ''

# --- Global npm packages ---------------------------------------------------
Add-Line '## Global npm packages'
if (Get-Command npm -ErrorAction SilentlyContinue) {
    $outdated = (npm outdated -g --parseable 2>&1) | Out-String
    if ([string]::IsNullOrWhiteSpace($outdated)) {
        Add-Line '- everything current.'
    }
    else {
        foreach ($line in ($outdated -split "`r?`n" | Where-Object { $_.Trim() -ne '' })) {
            $parts = $line -split ':'
            if ($parts.Count -ge 3) { Add-Line "- $($parts[2]) -> $($parts[1])" }
            else                    { Add-Line "- $line" }
        }
    }
}
else {
    # Family 2: a check that could not run is not a check that passed.
    Add-Line '- COULD NOT CHECK: npm is not on this PATH.'
}
Add-Line ''

# --- Tools you pinned on purpose -------------------------------------------
Add-Line '## Pinned on purpose - do not bump without deciding'
Add-Line ''
Add-Line 'List your pinned tools here, with the reason and the issue link. A pin whose'
Add-Line 'reason nobody remembers gets "helpfully" upgraded within two maintenance runs.'
Add-Line ''

# --- What to do next --------------------------------------------------------
Add-Line '## Applying'
Add-Line ''
Add-Line 'Nothing above has been applied. Update one thing at a time, run your test suite'
Add-Line 'after each, and write down anything that had to be pinned and why.'

Set-Content -LiteralPath $report -Value ($script:lines -join [Environment]::NewLine) -Encoding UTF8
Copy-Item -LiteralPath $report -Destination $latest -Force

Write-Output "Update report written: $report"
Write-Output 'Nothing was applied.'
