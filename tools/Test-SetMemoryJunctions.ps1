<#
  Test-SetMemoryJunctions.ps1

  Uses real junctions on a real filesystem. A mock would prove only that the
  mock agrees with itself, and the whole point of this script is telling a
  junction from a real directory.

  THE FIXTURE MODELS THE HOST, NOT THE SCRIPT. Before 2026-09-20 the fixture
  put stray.md directly under silos/project-a and expected project-a itself to
  become the junction - the same layout the script wrongly assumed, so thirteen
  assertions passed while -Apply on a real machine would have removed every
  project directory with its transcripts. Now every project in the fixture has
  the shape the host produces: <project>/session.jsonl next to
  <project>/memory/. The transcript must be exactly where it was after -Apply,
  and the project directory must never become a reparse point.
#>
[CmdletBinding()]
param(
    [string]$ScriptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1: with [CmdletBinding()], $PSScriptRoot is EMPTY inside the
# param() block and populated in the body. Resolve defaults here, never up there.
if ([string]::IsNullOrEmpty($ScriptPath)) {
    $ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\memory\Set-MemoryJunctions.ps1'
}

$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { $script:Pass++; Write-Output "  PASS  $Name" }
    else            { $script:Fail++; Write-Output "  FAIL  $Name" }
}

function New-Sandbox {
    $dir = Join-Path $env:TEMP ('mem-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $dir 'store') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dir 'projects') -Force | Out-Null
    return $dir
}

function New-Project {
    # One directory shaped like <AGENT-HOME>/projects/<cwd>: a transcript beside memory/.
    param([string]$Root, [string]$Name, [switch]$WithMemoryFolder, [string]$StrayFile)
    $project = Join-Path $Root $Name
    New-Item -ItemType Directory -Path $project -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project 'session.jsonl') -Value '{"type":"user"}' -Encoding UTF8
    if ($WithMemoryFolder) {
        $mem = Join-Path $project 'memory'
        New-Item -ItemType Directory -Path $mem -Force | Out-Null
        if ($StrayFile) { Set-Content -LiteralPath (Join-Path $mem $StrayFile) -Value 'content that predates the junction' -Encoding UTF8 }
    }
    return $project
}

function Test-IsReparsePoint {
    param([string]$Target)
    $item = Get-Item -LiteralPath $Target -Force
    return (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Invoke-Script {
    param([string]$MemoryRoot, [string]$SiloRoot, [switch]$Apply)
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) { return @{ Code = -1; Text = '' } }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($Apply) { $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -MemoryRoot $MemoryRoot -SiloRoot $SiloRoot -Apply 2>&1 }
        else        { $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -MemoryRoot $MemoryRoot -SiloRoot $SiloRoot 2>&1 }
        return @{ Code = $LASTEXITCODE; Text = ($out | Out-String) }
    }
    finally { $ErrorActionPreference = $previous }
}

Write-Output 'Group 1 - a real directory and a real junction are told apart'

$box = New-Sandbox
try {
    $store = Join-Path $box 'store'
    $plain = Join-Path $box 'projects\plain'
    $link  = Join-Path $box 'projects\linked'
    New-Item -ItemType Directory -Path $plain -Force | Out-Null
    New-Item -ItemType Junction  -Path $link -Target $store -Force | Out-Null

    Assert-True 'plain directory is not a reparse point' (-not (Test-IsReparsePoint -Target $plain))
    Assert-True 'junction is a reparse point'            (Test-IsReparsePoint -Target $link)

    # The prescribed method on the machine this came from is fsutil. Prove the two
    # agree before preferring the attribute check, which needs no external tool and
    # no elevation. If they ever disagree, the script must follow fsutil, not this.
    $fsutil = (& fsutil reparsepoint query $link 2>&1 | Out-String)
    Assert-True 'fsutil agrees with the attribute check' ($fsutil -match '0xa0000003')
}
finally { Remove-Item -LiteralPath $box -Recurse -Force }

Write-Output 'Group 2 - the silo is <project>/memory; the project directory is never touched'

$box = New-Sandbox
try {
    $store    = Join-Path $box 'store'
    $projects = Join-Path $box 'projects'
    $project  = New-Project -Root $projects -Name 'project-a' -WithMemoryFolder -StrayFile 'stray.md'
    $silo     = Join-Path $project 'memory'

    $dry = Invoke-Script -MemoryRoot $store -SiloRoot $projects
    Assert-True 'dry run reports divergence as exit 1' ($dry.Code -eq 1)
    Assert-True 'dry run wrote nothing' (Test-Path -LiteralPath (Join-Path $silo 'stray.md'))
    # The human's test: an ABSOLUTE path, with the parent, ending in \memory, is on
    # screen. Matched by shape rather than by string: $env:TEMP arrives in 8.3 form
    # (CELSOG~1) while Get-ChildItem returns the long form, so a literal comparison
    # of the two spellings of the same folder fails for reasons that are not the script's.
    Assert-True 'dry run prints the full candidate path ending in \memory' ($dry.Text -match '[A-Za-z]:\\[^\r\n]*\\projects\\project-a\\memory')
    Assert-True 'dry run names the state, not just the project' ($dry.Text -match 'real-folder')

    $apply = Invoke-Script -MemoryRoot $store -SiloRoot $projects -Apply
    Assert-True 'apply succeeds' ($apply.Code -eq 0)
    Assert-True 'memory/ is a junction after apply' (Test-IsReparsePoint -Target $silo)
    Assert-True 'the PROJECT directory is not a reparse point' (-not (Test-IsReparsePoint -Target $project))

    # The two assertions that matter most in this file.
    Assert-True 'the stray file was carried into the store, not destroyed' (Test-Path -LiteralPath (Join-Path $store 'stray.md'))
    Assert-True 'the transcript is exactly where it was' ((Get-Content -LiteralPath (Join-Path $project 'session.jsonl') -Raw) -like '*"type":"user"*')

    Assert-True 'a second dry run is clean' ((Invoke-Script -MemoryRoot $store -SiloRoot $projects).Code -eq 0)
}
finally { Remove-Item -LiteralPath $box -Recurse -Force }

Write-Output 'Group 3 - already-correct and missing silos'

$box = New-Sandbox
try {
    $store    = Join-Path $box 'store'
    $projects = Join-Path $box 'projects'
    $okProj   = New-Project -Root $projects -Name 'project-ok'
    New-Item -ItemType Junction -Path (Join-Path $okProj 'memory') -Target $store -Force | Out-Null
    $newProj  = New-Project -Root $projects -Name 'project-new'     # no memory/ yet

    $dry = Invoke-Script -MemoryRoot $store -SiloRoot $projects
    Assert-True 'correct junction is reported ok'          ($dry.Text -match 'ok\s+.*project-ok\\memory')
    Assert-True 'a project without memory/ is reported missing' ($dry.Text -match 'missing\s+.*project-new\\memory')
    Assert-True 'dry run with one missing exits 1'          ($dry.Code -eq 1)

    $apply = Invoke-Script -MemoryRoot $store -SiloRoot $projects -Apply
    Assert-True 'apply creates the missing junction'        ((Test-Path -LiteralPath (Join-Path $newProj 'memory')) -and (Test-IsReparsePoint -Target (Join-Path $newProj 'memory')))
    Assert-True 'apply leaves the correct one alone'        (Test-IsReparsePoint -Target (Join-Path $okProj 'memory'))
    Assert-True 'all correct afterwards: dry run exits 0'   ((Invoke-Script -MemoryRoot $store -SiloRoot $projects).Code -eq 0)
}
finally { Remove-Item -LiteralPath $box -Recurse -Force }

Write-Output 'Group 4 - a candidate that is not a memory silo is refused, never converted'

$box = New-Sandbox
try {
    $store    = Join-Path $box 'store'
    $projects = Join-Path $box 'projects'
    # memory/ that holds a transcript: whatever it is, it is not a memory silo.
    $bad = New-Project -Root $projects -Name 'project-bad' -WithMemoryFolder
    Set-Content -LiteralPath (Join-Path $bad 'memory\leftover.jsonl') -Value '{}' -Encoding UTF8
    # memory/ that holds a junction inside: removing it could remove the target.
    $nested = New-Project -Root $projects -Name 'project-nested' -WithMemoryFolder
    New-Item -ItemType Junction -Path (Join-Path $nested 'memory\inner') -Target $store -Force | Out-Null

    $dry = Invoke-Script -MemoryRoot $store -SiloRoot $projects
    Assert-True 'refused candidates exit 1 in dry run' ($dry.Code -eq 1)
    Assert-True 'transcript inside is named as the reason' ($dry.Text -match 'REFUSED.*project-bad' -and $dry.Text -match 'jsonl')
    Assert-True 'reparse point inside is named as the reason' ($dry.Text -match 'REFUSED.*project-nested' -and $dry.Text -match 'reparse')

    $apply = Invoke-Script -MemoryRoot $store -SiloRoot $projects -Apply
    Assert-True 'apply with refused candidates exits 1'     ($apply.Code -eq 1)
    Assert-True 'refused: transcript-holder untouched'      (-not (Test-IsReparsePoint -Target (Join-Path $bad 'memory')))
    Assert-True 'refused: the leftover transcript survives' (Test-Path -LiteralPath (Join-Path $bad 'memory\leftover.jsonl'))
    Assert-True 'refused: nested-junction holder untouched' (-not (Test-IsReparsePoint -Target (Join-Path $nested 'memory')))
    Assert-True 'refused: the store itself is intact'       (Test-Path -LiteralPath $store -PathType Container)
}
finally {
    # The nested junction must be unlinked, not recursed into, or the sandbox
    # cleanup would empty the store first and then fail on it.
    $inner = Join-Path $box 'projects\project-nested\memory\inner'
    if (Test-Path -LiteralPath $inner) { [System.IO.Directory]::Delete($inner, $false) }
    Remove-Item -LiteralPath $box -Recurse -Force
}

Write-Output 'Group 5 - usage errors exit 2, never 0'

$box = New-Sandbox
try {
    $nowhere = Join-Path $env:TEMP ('nope-' + [guid]::NewGuid().ToString('N'))
    Assert-True 'missing memory root exits 2' ((Invoke-Script -MemoryRoot $nowhere -SiloRoot (Join-Path $box 'projects')).Code -eq 2)
    Assert-True 'missing silo root exits 2'   ((Invoke-Script -MemoryRoot (Join-Path $box 'store') -SiloRoot $nowhere).Code -eq 2)
}
finally { Remove-Item -LiteralPath $box -Recurse -Force }

Write-Output 'Group 6 - the script ships ASCII-only and parses on 5.1'

foreach ($file in @($ScriptPath, $PSCommandPath)) {
    if (Test-Path -LiteralPath $file -PathType Leaf) {
        $nonAscii = @([IO.File]::ReadAllBytes($file) | Where-Object { $_ -gt 127 }).Count
        Assert-True "ascii-only: $(Split-Path -Leaf $file)" ($nonAscii -eq 0)
    }
    else {
        Assert-True "ascii-only: $(Split-Path -Leaf $file) (file missing)" $false
    }
}

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
