<#
  Test-Stack.ps1

  Assertions over stack/ and the repository root - including the one that guards
  the destructive step of retiring templates/: no file may still point at it.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1: with [CmdletBinding()], $PSScriptRoot is EMPTY inside the
# param() block and populated in the body. Resolve defaults here, never up there.
if ([string]::IsNullOrEmpty($RepoRoot)) { $RepoRoot = Split-Path -Parent $PSScriptRoot }

$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { $script:Pass++; Write-Output "  PASS  $Name" }
    else            { $script:Fail++; Write-Output "  FAIL  $Name" }
}

function Get-Text {
    param([string]$Relative)
    $path = Join-Path $RepoRoot $Relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
}

Write-Output 'Group 1 - stack declares its own perishability'

$stackReadme = Get-Text 'stack\README.md'
Assert-True 'stack README exists' ($stackReadme.Length -gt 0)
Assert-True 'it carries a date stamp'   ($stackReadme -match '\b20\d\d-\d\d-\d\d\b')
Assert-True 'it says it is perishable'  ($stackReadme -match '(?i)perishable|snapshot|out of date')

# The one timeless thing inside stack/: how to derive your own, which outlives any
# list of tools. Without it, stack/ is only a list that rots.
Assert-True 'it explains how to derive your own stack' ($stackReadme -match '(?i)derive your own')
Assert-True 'telemetry pruning is described'           ($stackReadme -match '(?i)telemetry|usage data')
Assert-True 'a loaded catalogue is distinguished from a used skill' ($stackReadme -match '(?i)loaded')

$manifest = Get-Text 'stack\manifest.md'
Assert-True 'manifest exists' ($manifest.Length -gt 0)
Assert-True 'manifest carries install commands' ($manifest -match '(?i)install')

$domain = Get-Text 'stack\domain-tools.md'
Assert-True 'domain tools doc exists' ($domain.Length -gt 0)
Assert-True 'domain tools are declared as the author own choice' ($domain -match '(?i)yours will|your own')

Write-Output 'Group 2 - the four shippable skills, with attribution'

foreach ($skill in @('design-smells', 'source-grounded', 'diagnose', 'scientific-project-report')) {
    $text = Get-Text "stack\skills\$skill\SKILL.md"
    Assert-True "skill present: $skill" ($text.Length -gt 0)
}

# Two are derivative and one is third-party-customised. Shipping them without saying
# so is the kind of omission that is invisible until it is a complaint.
Assert-True 'source-grounded credits its upstream' ((Get-Text 'stack\skills\source-grounded\SKILL.md') -match '(?i)addyosmani')
Assert-True 'design-smells credits its upstream'   ((Get-Text 'stack\skills\design-smells\SKILL.md') -match '(?i)addyosmani')
Assert-True 'diagnose credits its upstream'        ((Get-Text 'stack\skills\diagnose\SKILL.md') -match '(?i)mattpocock|upstream')

$licensePath = Join-Path $RepoRoot 'stack\skills\scientific-project-report\LICENSE.txt'
Assert-True 'the CC BY skill keeps its own licence file' (Test-Path -LiteralPath $licensePath -PathType Leaf)

$credits = Get-Text 'CREDITS.md'
Assert-True 'CREDITS exists' ($credits.Length -gt 0)
foreach ($upstream in @('addyosmani', 'mattpocock')) {
    Assert-True "CREDITS names upstream: $upstream" ($credits -match [regex]::Escape($upstream))
}

Write-Output 'Group 3 - the root describes what the repository now is'

$readme = Get-Text 'README.md'
Assert-True 'root README exists' ($readme.Length -gt 0)
Assert-True 'the durability contract is on the front page' ($readme -match '(?i)core/' -and $readme -match '(?i)stack/')

$scaffold = Get-Text 'SCAFFOLD.md'
Assert-True 'SCAFFOLD exists' ($scaffold.Length -gt 0)
foreach ($layer in @('core/', 'stack/', 'vault/', 'automation/')) {
    Assert-True "SCAFFOLD walks the layer: $layer" ($scaffold -match [regex]::Escape($layer))
}
Assert-True 'SCAFFOLD keeps the adapt-do-not-transplant posture' ($scaffold -match '(?i)adapt')

$claude = Get-Text 'CLAUDE.md'
Assert-True 'maintainer CLAUDE.md exists' ($claude.Length -gt 0)
Assert-True 'the routing rule is stated'  ($claude -match '(?i)method goes to|routing')
Assert-True 'the golden rule survives'    ($claude -match '(?i)generic')

Write-Output 'Group 4 - templates/ is retired, with nothing left pointing at it'

$templatesPath = Join-Path $RepoRoot 'templates'
Assert-True 'the templates folder is gone' (-not (Test-Path -LiteralPath $templatesPath))

# The destructive step's actual gate. A folder removed while documents still name it
# leaves a repository that contradicts itself on its own front page.
$dangling = @()
foreach ($doc in @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Filter '*.md' |
        Where-Object { $_.FullName -notmatch '(\\|/)\.git(\\|/)' })) {
    # Strip markdown code ticks first: a document legitimately writes `templates/` in
    # backticks, and matching the raw text makes the allowance below never fire.
    $text = (Get-Content -LiteralPath $doc.FullName -Raw -Encoding UTF8) -replace '`', ''
    # Allow a historical mention that explicitly says the folder is gone.
    if ($text -match 'templates/' -and $text -notmatch '(?i)templates/ (is |was )?(now )?(gone|retired|removed)') {
        $dangling += $doc.Name
    }
}
Assert-True "no document still points at templates/ [$($dangling -join '; ')]" ($dangling.Count -eq 0)

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
