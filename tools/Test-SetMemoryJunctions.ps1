<#
  Test-SetMemoryJunctions.ps1

  Uses real junctions on a real filesystem. A mock would prove only that the
  mock agrees with itself, and the whole point of this script is telling a
  junction from a real directory.
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
    New-Item -ItemType Directory -Path (Join-Path $dir 'silos') -Force | Out-Null
    return $dir
}

function Test-IsReparsePoint {
    param([string]$Target)
    $item = Get-Item -LiteralPath $Target -Force
    return (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Invoke-Script {
    param([string]$MemoryRoot, [string]$SiloRoot, [switch]$Apply)
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) { return -1 }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($Apply) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -MemoryRoot $MemoryRoot -SiloRoot $SiloRoot -Apply 2>&1 | Out-Null
        }
        else {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -MemoryRoot $MemoryRoot -SiloRoot $SiloRoot 2>&1 | Out-Null
        }
        return $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
}

Write-Output 'Group 1 - a real directory and a real junction are told apart'

$box = New-Sandbox
try {
    $store = Join-Path $box 'store'
    $plain = Join-Path $box 'silos\plain'
    $link  = Join-Path $box 'silos\linked'
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

Write-Output 'Group 2 - dry run reports without writing; -Apply writes'

$box = New-Sandbox
try {
    $store = Join-Path $box 'store'
    $silos = Join-Path $box 'silos'
    $silo  = Join-Path $silos 'project-a'
    New-Item -ItemType Directory -Path $silo -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $silo 'stray.md') -Value 'content that predates the junction' -Encoding UTF8

    Assert-True 'dry run reports divergence as exit 1' ((Invoke-Script -MemoryRoot $store -SiloRoot $silos) -eq 1)
    Assert-True 'dry run wrote nothing' (Test-Path -LiteralPath (Join-Path $silo 'stray.md'))

    Assert-True 'apply succeeds' ((Invoke-Script -MemoryRoot $store -SiloRoot $silos -Apply) -eq 0)
    Assert-True 'silo is a junction after apply' (Test-IsReparsePoint -Target $silo)

    # The assertion that matters most in this file. Converting a real folder into a
    # junction destroys its contents unless something moves them first.
    Assert-True 'the stray file was preserved, not destroyed' (Test-Path -LiteralPath (Join-Path $store 'stray.md'))

    Assert-True 'a second dry run is clean' ((Invoke-Script -MemoryRoot $store -SiloRoot $silos) -eq 0)
}
finally { Remove-Item -LiteralPath $box -Recurse -Force }

Write-Output 'Group 3 - usage errors exit 2, never 0'

$box = New-Sandbox
try {
    $nowhere = Join-Path $env:TEMP ('nope-' + [guid]::NewGuid().ToString('N'))
    Assert-True 'missing memory root exits 2' ((Invoke-Script -MemoryRoot $nowhere -SiloRoot (Join-Path $box 'silos')) -eq 2)
    Assert-True 'missing silo root exits 2'   ((Invoke-Script -MemoryRoot (Join-Path $box 'store') -SiloRoot $nowhere) -eq 2)
}
finally { Remove-Item -LiteralPath $box -Recurse -Force }

Write-Output 'Group 4 - the script ships ASCII-only and parses on 5.1'

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
