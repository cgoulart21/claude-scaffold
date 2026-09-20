<#
  check-no-personal-data.ps1

  Fails when the tree carries structural markers of personal data.
  The script knows no patterns: they are data, loaded from -PatternFile.
  That is what lets a private nominal denylist reuse this same scanner
  without the list ever entering a public repository.

  Exit codes: 0 clean, 1 hits found, 2 usage or IO error.
  A gate that could not run must never exit 0.
#>
[CmdletBinding()]
param(
    [string]$Path,
    [string]$PatternFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1: with [CmdletBinding()], $PSScriptRoot is EMPTY inside the
# param() block and populated in the body. Resolve defaults here, never up there.
if ([string]::IsNullOrEmpty($PatternFile)) { $PatternFile = Join-Path $PSScriptRoot 'patterns.txt' }
if ([string]::IsNullOrEmpty($Path))        { $Path        = Split-Path -Parent $PSScriptRoot }

# .template is on the list on purpose: to Get-ChildItem the extension of CLAUDE.md.template
# is .template, not .md, and the templates are exactly the files someone fills with real
# paths and may sync back. Until 2026-09-20 they were skipped - 59 of 63 files read.
$textExtensions = @('.md', '.ps1', '.psm1', '.psd1', '.txt', '.yml', '.yaml', '.json', '.sh', '.svg', '.toml', '.cfg', '.gitignore', '.template')

function Get-GatePattern {
    param([string]$File)

    $id = ''
    $desc = ''
    $records = @()
    foreach ($line in (Get-Content -LiteralPath $File -Encoding UTF8)) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '') { continue }
        if ($trimmed.StartsWith('# id:'))   { $id   = $trimmed.Substring(5).Trim(); continue }
        if ($trimmed.StartsWith('# desc:')) { $desc = $trimmed.Substring(7).Trim(); continue }
        if ($trimmed.StartsWith('#'))       { continue }
        $records += [pscustomobject]@{ Id = $id; Description = $desc; Regex = $trimmed }
    }
    return $records
}

if (-not (Test-Path -LiteralPath $PatternFile -PathType Leaf)) {
    Write-Output "ERROR pattern file not found: $PatternFile"
    exit 2
}
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Output "ERROR path not found: $Path"
    exit 2
}

$patterns = @(Get-GatePattern -File $PatternFile)
if ($patterns.Count -eq 0) {
    Write-Output "ERROR no patterns loaded from: $PatternFile"
    exit 2
}

$root = [System.IO.Path]::GetFullPath($Path)
$excluded = @([System.IO.Path]::GetFullPath($PatternFile))
$hits = @()

$files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force |
    Where-Object { $_.FullName -notmatch '(\\|/)\.git(\\|/)' } |
    Where-Object { $textExtensions -contains $_.Extension.ToLower() -or $_.Extension -eq '' })

foreach ($file in $files) {
    if ($excluded -contains $file.FullName) { continue }

    $relative = $file.FullName
    if ($relative.StartsWith($root)) { $relative = $relative.Substring($root.Length).TrimStart('\', '/') }

    $number = 0
    foreach ($line in (Get-Content -LiteralPath $file.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $number++
        foreach ($pattern in $patterns) {
            if ($line -match $pattern.Regex) {
                $hits += [pscustomobject]@{ Id = $pattern.Id; Location = "${relative}:${number}"; Text = $line.Trim() }
            }
        }
    }
}

foreach ($hit in $hits) {
    Write-Output "HIT $($hit.Id) $($hit.Location)"
    Write-Output "    $($hit.Text)"
}

Write-Output ''
Write-Output "scanned $($files.Count) file(s) with $($patterns.Count) pattern(s): $($hits.Count) hit(s)"
if ($hits.Count -gt 0) { exit 1 }
exit 0
