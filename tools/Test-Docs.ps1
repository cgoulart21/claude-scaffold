<#
  Test-Docs.ps1

  Structural assertions over docs/. A guide cannot be tested for being good, but it
  can be tested for covering what it promised and for not pointing at files that do
  not exist - which is what actually rots.
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

function Get-Doc {
    param([string]$Name)
    $path = Join-Path $RepoRoot "docs\$Name"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
}

Write-Output 'Group 1 - every chapter is present'

$chapters = @(
    '00-why.md',
    '10-machine-setup.md',
    '20-the-four-memories.md',
    '30-governance.md',
    '40-skills-and-plugins.md',
    '50-verification.md',
    '60-maintenance.md',
    '99-faq.md'
)
foreach ($chapter in $chapters) {
    Assert-True "chapter present: $chapter" ((Get-Doc $chapter).Length -gt 0)
}

Write-Output 'Group 2 - the machine setup chapter answers what was asked of it'

$machine = Get-Doc '10-machine-setup.md'
foreach ($topic in @('prerequisite', 'agent home', 'vault', 'backup', 'long path')) {
    Assert-True "machine setup covers: $topic" ($machine -match "(?i)$([regex]::Escape($topic))")
}
# The trap that makes absolute paths lie, and the one that eats a vault.
Assert-True 'the sandboxed-host trap is explained' ($machine -match '(?i)sandbox')
Assert-True 'cloud-synced storage is warned about'  ($machine -match '(?i)sync')

Write-Output 'Group 3 - the four layers are distinguished, with a decision table'

$memories = Get-Doc '20-the-four-memories.md'
foreach ($layer in @('session', 'memory', 'lesson', 'vault')) {
    Assert-True "layer named: $layer" ($memories -match "(?i)\b$layer")
}
Assert-True 'a decision table exists' ($memories -match '(?m)^\|.*\|')
Assert-True 'it says where a thing goes, not just what each layer is' ($memories -match '(?i)where does')

Write-Output 'Group 4 - the diagram ships and is a real SVG'

$svgPath = Join-Path $RepoRoot 'docs\assets\layout.svg'
Assert-True 'the layout diagram exists' (Test-Path -LiteralPath $svgPath -PathType Leaf)
if (Test-Path -LiteralPath $svgPath -PathType Leaf) {
    $svg = Get-Content -LiteralPath $svgPath -Raw -Encoding UTF8
    Assert-True 'it opens and closes as SVG' ($svg -match '<svg' -and $svg -match '</svg>')
    Assert-True 'it declares a viewBox so it scales' ($svg -match 'viewBox=')
    # A diagram that is invisible in half the readers' themes is half a diagram.
    Assert-True 'it does not hardcode a light-only fill for text' ($svg -match 'currentColor|prefers-color-scheme')
}

Write-Output 'Group 5 - nothing points at a file that does not exist'

$dangling = @()
$docsRoot = Join-Path $RepoRoot 'docs'
if (Test-Path -LiteralPath $docsRoot -PathType Container) {
    foreach ($doc in @(Get-ChildItem -LiteralPath $docsRoot -File -Filter '*.md')) {
        $text = Get-Content -LiteralPath $doc.FullName -Raw -Encoding UTF8
        foreach ($hit in [regex]::Matches($text, '`((?:core|stack|vault|automation|tools|docs)/[A-Za-z0-9_./-]*)`')) {
            $relative = $hit.Groups[1].Value.TrimEnd('/') -replace '/', '\'
            if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $relative))) {
                $dangling += "$($doc.Name) -> $($hit.Groups[1].Value)"
            }
        }
    }
}
Assert-True "no dangling repository reference [$($dangling -join '; ')]" ($dangling.Count -eq 0)

# The rows removed while docs/ did not exist have to come back now that it does.
$rootReadme = Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md') -Raw -Encoding UTF8
Assert-True 'the root README lists docs/ again' ($rootReadme -match 'docs/')

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
