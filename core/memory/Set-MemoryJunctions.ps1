<#
  Set-MemoryJunctions.ps1

  Keeps one physical memory folder behind per-directory silos, by making each
  silo a junction into it.

  Why this exists: with one store per working directory, the same fact gets
  written in one silo and stays invisible to every other session. The junction
  makes them one folder with many names.

  Detection is by the ReparsePoint ATTRIBUTE, never by "the folder looks empty".
  A real folder fed by an occasional copy is indistinguishable from a junction
  until you measure it, and a stale copy is exactly the failure this prevents.

  Exit codes: 0 clean or applied, 1 divergence found in dry run, 2 usage error.
  Without -Apply this script writes nothing.
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
    if (-not (Test-IsReparsePoint -Target $Target)) { return 'real-folder' }
    $actual = Get-JunctionTarget -Target $Target
    if ($actual -eq $store) { return 'junction-ok' }
    return 'junction-wrong'
}

$silos = @(Get-ChildItem -LiteralPath $SiloRoot -Directory -Force)
$divergent = 0

foreach ($silo in $silos) {
    $state = Get-SiloState -Target $silo.FullName

    if ($state -eq 'junction-ok') {
        Write-Output "  ok        $($silo.Name)"
        continue
    }

    $divergent++

    if (-not $Apply) {
        Write-Output "  $state  $($silo.Name)"
        continue
    }

    if ($state -eq 'real-folder') {
        # Copy BEFORE removing. Converting a real folder into a junction destroys
        # whatever was in it, and some of it may exist nowhere else.
        $copied = 0
        foreach ($file in @(Get-ChildItem -LiteralPath $silo.FullName -Recurse -File -Force)) {
            $relative = $file.FullName.Substring($silo.FullName.Length).TrimStart('\')
            $destination = Join-Path $store $relative
            if (Test-Path -LiteralPath $destination) { continue }   # never overwrite: the store may be newer
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $file.FullName -Destination $destination
            $copied++
        }
        Write-Output "  copied    $($silo.Name) ($copied file(s) carried into the store)"
        Remove-Item -LiteralPath $silo.FullName -Recurse -Force
    }
    else {
        # Removing a junction with Remove-Item -Recurse can delete the TARGET's
        # contents. Directory.Delete with recursive:$false removes the link only.
        [System.IO.Directory]::Delete($silo.FullName, $false)
        Write-Output "  relinked  $($silo.Name)"
    }

    New-Item -ItemType Junction -Path $silo.FullName -Target $store -Force | Out-Null
}

Write-Output ''
if ($silos.Count -eq 0) {
    Write-Output 'no silos found'
    exit 0
}

if ($Apply) {
    Write-Output "$($silos.Count) silo(s): $divergent converted, $($silos.Count - $divergent) already correct"
    exit 0
}

Write-Output "$($silos.Count) silo(s): $divergent divergent, $($silos.Count - $divergent) correct"
if ($divergent -gt 0) {
    Write-Output 'Re-run with -Apply to convert them. Files are carried into the store first.'
    exit 1
}
exit 0
