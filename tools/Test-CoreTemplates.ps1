<#
  Test-CoreTemplates.ps1

  Structural assertions over core/. These check that the templates say what the
  scaffold claims they say - not that the prose is good, which no test can do.

  Group 2 (the ten lesson families) is deliberately absent: core/lessons/ is
  authored in a session of its own. The numbering keeps its slot so the group
  lands where it belongs rather than at the end.
#>
[CmdletBinding()]
param(
    [string]$CoreRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1: with [CmdletBinding()], $PSScriptRoot is EMPTY inside the
# param() block and populated in the body. Resolve defaults here, never up there.
if ([string]::IsNullOrEmpty($CoreRoot)) { $CoreRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'core' }

$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { $script:Pass++; Write-Output "  PASS  $Name" }
    else            { $script:Fail++; Write-Output "  FAIL  $Name" }
}

function Get-Text {
    param([string]$Relative)
    $path = Join-Path $CoreRoot $Relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
}

Write-Output 'Group 1 - governance template carries the post-audit shape'

$gov = Get-Text 'governance\CLAUDE.md.template'
Assert-True 'governance template exists' ($gov.Length -gt 0)

# The defect that started this work: the July scaffold shipped the PRE-audit file,
# built around a mechanism that was retired. If this assertion ever goes red, the
# scaffold is teaching something its author deleted.
#
# The length check is not decoration. A bare -notmatch against an empty string is
# TRUE, so a missing file would make this assertion pass vacuously - and this is the
# one assertion that exists to catch the original defect.
Assert-True 'no retired task-observer section' ($gov.Length -gt 0 -and $gov -notmatch '(?i)task-observer')

foreach ($heading in @('Verification', 'Cross-project knowledge', 'Handoff', 'Commits and review', 'Maintenance', 'Workflows and subagents', 'Corrections')) {
    Assert-True "section present: $heading" ($gov -match [regex]::Escape($heading))
}

foreach ($rule in @('independent', 'Assumptions:', 'contradiction', 'published surface', 'second occurrence')) {
    Assert-True "rule survives translation: $rule" ($gov -match [regex]::Escape($rule))
}

Write-Output 'Group 2 - the ten families and the growth rule'

$lessons = Get-Text 'lessons\LESSONS.md'
Assert-True 'lessons file exists' ($lessons.Length -gt 0)

$families = @([regex]::Matches($lessons, '(?m)^##\s+\d+\.\s'))
Assert-True 'exactly ten families' ($families.Count -eq 10)

$applies = @([regex]::Matches($lessons, '(?m)^\*\*Apply:\*\*'))
Assert-True 'every family carries an Apply line' ($applies.Count -eq 10)

Assert-True 'second-occurrence rule is stated' ($lessons -match '(?i)second occurrence')
Assert-True 'seeds are labelled as borrowed'   ($lessons -match '(?i)borrowed|seeds|not your scars')

Write-Output 'Group 3 - memory subsystem'

$memReadme = Get-Text 'memory\README.md'
Assert-True 'memory README exists' ($memReadme.Length -gt 0)
Assert-True 'detection is by reparse point, not by looking empty' ($memReadme -match '(?i)reparse point')
Assert-True 'the index is described as authored, not mirrored'    ($memReadme -match '(?i)authored')

$memTemplate = Get-Text 'memory\memory-file.template.md'
foreach ($field in @('name:', 'description:', 'metadata:', 'type:')) {
    Assert-True "frontmatter field present: $field" ($memTemplate -match [regex]::Escape($field))
}
foreach ($kind in @('user', 'feedback', 'project', 'reference')) {
    Assert-True "memory type documented: $kind" ($memTemplate -match "\b$kind\b")
}

Write-Output 'Group 4 - corrections, handoff and the review map'

$corrections = Get-Text 'corrections\README.md'
Assert-True 'corrections README exists' ($corrections.Length -gt 0)
Assert-True 'second-occurrence promotion is stated' ($corrections -match '(?i)second occurrence')
Assert-True 'the control-byte sweep is documented'  ($corrections -match '0x0B|0x0C')

$plan = Get-Text 'handoff\PLAN.md'
foreach ($field in @('Status:', 'Updated:', 'Base:')) {
    Assert-True "checkpoint field present: $field" ($plan -match [regex]::Escape($field))
}
Assert-True 'staleness rule is stated' ($plan -match '14 days')

$review = Get-Text 'review\README.md'
Assert-True 'review map exists' ($review.Length -gt 0)
Assert-True 'CI is named as the authoritative gate' ($review -match '(?i)authoritative')

Write-Output 'Group 5 - the durability contract is written down'

$coreReadme = Get-Text 'README.md'
Assert-True 'core README exists' ($coreReadme.Length -gt 0)
Assert-True 'core is declared timeless'          ($coreReadme -match '(?i)timeless|does not expire')
Assert-True 'the routing rule is stated'         ($coreReadme -match '(?i)routing|where does a change go')
Assert-True 'inventory is routed away from core' ($coreReadme -match '(?i)inventory')

# A repo-relative path that resolves to nothing is the classic thing that ships. This
# catches it while the branch is still local, which is the only cheap moment.
$dangling = @()
foreach ($doc in @(Get-ChildItem -LiteralPath $CoreRoot -Recurse -File -Filter '*.md')) {
    $text = Get-Content -LiteralPath $doc.FullName -Raw -Encoding UTF8
    foreach ($hit in [regex]::Matches($text, 'core/([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*)')) {
        $relative = $hit.Groups[1].Value -replace '/', '\'
        if (-not (Test-Path -LiteralPath (Join-Path $CoreRoot $relative))) {
            $dangling += "$($doc.Name) -> $($hit.Value)"
        }
    }
}
Assert-True "no dangling core/ references [$($dangling -join '; ')]" ($dangling.Count -eq 0)

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
