<#
  Set-MemoryJunctions.ps1

  Keeps one physical memory folder behind per-directory silos, by making each
  silo a junction into it.

  Why this exists: with one store per working directory, the same fact gets
  written in one silo and stays invisible to every other session. The junction
  makes them one folder with many names.

  WHAT A SILO IS, EXACTLY. The host keeps one directory per working directory
  under <AGENT-HOME>/projects/<cwd>/. That directory holds the session
  transcripts (*.jsonl) AND a memory/ subfolder. The silo is the SUBFOLDER,
  <cwd>/memory, and only the subfolder is ever converted. The project directory
  itself is never touched. A version of this script before 2026-09-20 treated
  each child of -SiloRoot as the silo, which with the documented -SiloRoot is the
  project directory: -Apply would have carried every transcript into the store
  and removed the directory. A second machine caught it in dry run.

  Two guards follow from that lesson:
    * a candidate that contains *.jsonl is a project directory, not a silo, and
      is refused even if it is where the store is expected;
    * a candidate that contains a reparse point is refused too: removing a
      directory that holds a junction can remove the junction's TARGET.

  Detection is by the ReparsePoint ATTRIBUTE, never by "the folder looks empty".
  A real folder fed by an occasional copy is indistinguishable from a junction
  until you measure it, and a stale copy is exactly the failure this prevents.

  The dry run prints the FULL path of every candidate, so a human reads
  ...\projects\<cwd>\memory and recognises at once when the script is looking
  at the wrong place. That is the test the fixture cannot run for you.

  Exit codes: 0 clean or applied, 1 divergence found (dry run) or a candidate
  refused, 2 usage error. Without -Apply this script writes nothing.
#>
[CmdletBinding()]
param(
    [string]$MemoryRoot,
    [string]$SiloRoot,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($MemoryRoot) -or -not (Test-Path -LiteralPath $MemoryRoot -PathType Container)) {
    Write-Output "ERROR memory root not found: $MemoryRoot"
    exit 2
}
if ([string]::IsNullOrEmpty($SiloRoot) -or -not (Test-Path -LiteralPath $SiloRoot -PathType Container)) {
    Write-Output "ERROR silo root not found: $SiloRoot"
    exit 2
}

$store = [System.IO.Path]::GetFullPath($MemoryRoot).TrimEnd('\')
$SiloName = 'memory'

function Test-IsReparsePoint {
    param([string]$Target)
    $item = Get-Item -LiteralPath $Target -Force
    return (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-JunctionTarget {
    param([string]$Target)
    # fsutil labels its output in the system language, so parsing by label breaks on
    # any machine that is not this one. The \??\ prefix is not translated; anchor there.
    $out = (& fsutil reparsepoint query $Target 2>&1 | Out-String)
    $match = [regex]::Match($out, '\\\?\?\\([A-Za-z]:\\[^\r\n]*)')
    if (-not $match.Success) { return '' }
    return $match.Groups[1].Value.Trim().TrimEnd('\')
}

function Get-SiloState {
    param([string]$Target)
    if (-not (Test-Path -LiteralPath $Target)) { return 'missing' }
    if (Test-IsReparsePoint -Target $Target) {
        $actual = Get-JunctionTarget -Target $Target
        if ($actual -eq $store) { return 'junction-ok' }
        return 'junction-wrong'
    }
    # A real folder. Before touching it, make sure it IS a memory silo.
    if (@(Get-ChildItem -LiteralPath $Target -Filter '*.jsonl' -Recurse -File -Force -ErrorAction SilentlyContinue).Count -gt 0) {
        return 'refused-transcripts'
    }
    foreach ($child in @(Get-ChildItem -LiteralPath $Target -Force -ErrorAction SilentlyContinue)) {
        if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return 'refused-reparse' }
    }
    return 'real-folder'
}

$projects = @(Get-ChildItem -LiteralPath $SiloRoot -Directory -Force)
$divergent = 0
$refused = 0
$correct = 0

foreach ($project in $projects) {
    $silo = Join-Path $project.FullName $SiloName
    $state = Get-SiloState -Target $silo

    if ($state -eq 'junction-ok') {
        Write-Output "  ok                  $silo"
        $correct++
        continue
    }

    if ($state -like 'refused-*') {
        $why = if ($state -eq 'refused-transcripts') { 'holds *.jsonl: a project directory, not a memory silo' }
               else { 'holds a reparse point: removing it could remove the target' }
        Write-Output "  REFUSED             $silo"
        Write-Output "                      $why - resolve by hand, this script will not touch it"
        $refused++
        continue
    }

    $divergent++

    if (-not $Apply) {
        Write-Output ("  {0,-19} {1}" -f $state, $silo)
        continue
    }

    if ($state -eq 'real-folder') {
        # Copy BEFORE removing. Converting a real folder into a junction destroys
        # whatever was in it, and some of it may exist nowhere else.
        $copied = 0
        foreach ($file in @(Get-ChildItem -LiteralPath $silo -Recurse -File -Force)) {
            $relative = $file.FullName.Substring($silo.Length).TrimStart('\')
            $destination = Join-Path $store $relative
            if (Test-Path -LiteralPath $destination) { continue }   # never overwrite: the store may be newer
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $file.FullName -Destination $destination
            $copied++
        }
        Write-Output "  copied              $silo ($copied file(s) carried into the store)"
        # Get-SiloState already proved there is no reparse point inside, so a
        # recursive delete here removes only what this folder itself contains.
        [System.IO.Directory]::Delete($silo, $true)
    }
    elseif ($state -eq 'junction-wrong') {
        # Removing a junction with Remove-Item -Recurse can delete the TARGET's
        # contents. Directory.Delete with recursive:$false removes the link only.
        [System.IO.Directory]::Delete($silo, $false)
        Write-Output "  relinked            $silo"
    }
    else {
        Write-Output "  created             $silo"
    }

    New-Item -ItemType Junction -Path $silo -Target $store -Force | Out-Null
}

Write-Output ''
if ($projects.Count -eq 0) {
    Write-Output 'no project directories found under the silo root'
    exit 0
}

$summary = "$($projects.Count) project(s): $correct correct, $divergent divergent, $refused refused"
if ($Apply) {
    Write-Output ($summary -replace 'divergent', 'converted')
    if ($refused -gt 0) { exit 1 }
    exit 0
}

Write-Output $summary
if ($divergent -gt 0 -or $refused -gt 0) {
    if ($divergent -gt 0) { Write-Output 'Re-run with -Apply to convert the divergent ones. Files are carried into the store first.' }
    if ($refused -gt 0)   { Write-Output 'Refused candidates are never converted by this script; look at each one before deciding.' }
    exit 1
}
exit 0
