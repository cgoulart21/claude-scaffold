<#
  Assert-MemoryLinks.ps1

  Gate: every [[wikilink]] in the memory store resolves, or is a declared and still
  live exception.

  WHY IT EXISTS. A session renamed one memory file and the [[old-name]] inside another
  memory was left dangling. Nothing said so - not the baseline, not a hook, not the
  sync. The blast radius of a rename is its INCOMING links, and whoever wrote them is
  not told the target changed. It surfaced only because another session mentioned the
  rename in passing.

  WHAT IT DOES NOT DO, AND WHY. It does not demand that every [[target]] exist. The
  memory conventions deliberately allow a link to a memory not yet written - "it marks
  something worth writing later, not an error". A strict gate would contradict the
  convention and be born red.

  So the contract is by DECLARED EXCEPTION: a dangling target passes only if it is in
  -KnownDangling, with the reason written next to it in the caller. What the gate
  catches is the NEW dangling link - the one nobody decided would appear.

  AND THE EXCEPTION LIST CANNOT ROT. An entry that resolves again, or that nobody cites
  any more, FAILS. An exception list that does not maintain itself goes back to lying
  quietly - a gate is worth what it enumerates, including its own exclusions.

  SCOPE. The .md files at the top of -MemoryRoot (no recursion: an archive folder of
  frozen memories holds links that are history, not contract) plus any -ExtraSource
  files - because not every incoming link lives in the store; a global instruction
  file may cite a [[slug]] too.

  SYNTAX. [[target]], [[target|alias]] and [[target#section]] all point at `target`;
  alias and anchor are dropped before resolving. This is not cosmetic: `|` is invalid
  in a Windows path, and the first version of this gate let Test-Path throw on it and
  exit 1 - the SAME exit as "found a dangling link". Whoever reads the output could
  tell; whoever consumes only the exit code (a CI step, a chained suite) could not.
  A malformed target is now a formatted finding, never an exception.

  EXIT CONTRACT (three states):
    0  every link resolves, or is a declared and live exception
    1  an undeclared dangling link, or an exception that is stale or dead
    2  could NOT verify: -MemoryRoot missing, or no .md to scan (an empty sweep is
       not a clean sweep)

  PARAMETERS
    -MemoryRoot      The memory store. Required: this gate cannot guess where yours is.
    -ExtraSource     Files outside the store that cite memory slugs. Absolute, or relative
                     to the current directory. A missing extra is ignored, not an error.
    -KnownDangling   Slugs allowed to dangle. Each needs a reason next to it in the caller.
    -NoKnownDangling / -NoExtraSource   Ignore those lists; for hermetic fixtures.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]   $MemoryRoot,
    [string[]] $ExtraSource = @(),
    [string[]] $KnownDangling = @(),
    [switch]   $NoKnownDangling,
    [switch]   $NoExtraSource,
    [switch]   $Quiet
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($MemoryRoot)) {
    Write-Output 'COULD NOT VERIFY: -MemoryRoot is required (this gate does not know where your store is).'
    exit 2
}
if (-not (Test-Path -LiteralPath $MemoryRoot -PathType Container)) {
    Write-Output "COULD NOT VERIFY: memory root does not exist: $MemoryRoot"
    exit 2
}

if ($NoExtraSource)   { $ExtraSource   = @() }
if ($NoKnownDangling) { $KnownDangling = @() }
$ExtraSource   = @($ExtraSource   | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
$KnownDangling = @($KnownDangling | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })

$files = @(Get-ChildItem -LiteralPath $MemoryRoot -Filter '*.md' -File)
if ($files.Count -eq 0) {
    Write-Output "COULD NOT VERIFY: no .md in $MemoryRoot - an empty sweep is not a clean sweep"
    exit 2
}

$sources = New-Object System.Collections.ArrayList
foreach ($f in $files) { $null = $sources.Add([pscustomobject]@{ Path = $f.FullName; Label = $f.Name }) }
foreach ($rel in $ExtraSource) {
    $full = if ([IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path (Get-Location).Path $rel }
    if (Test-Path -LiteralPath $full -PathType Leaf) {
        $null = $sources.Add([pscustomobject]@{ Path = $full; Label = $rel })
    }
}

$links = New-Object System.Collections.ArrayList
foreach ($s in $sources) {
    $n = 0
    foreach ($line in [IO.File]::ReadAllLines($s.Path)) {
        $n++
        foreach ($m in [regex]::Matches($line, '\[\[([^\]\r\n]+)\]\]')) {
            $raw = $m.Groups[1].Value
            # The target is always the first segment in both [[t|alias]] and [[t#sec]],
            # so the first split segment is right for [[t#sec|alias]] and [[t|alias#sec]].
            $target = (($raw -split '[|#]')[0]).Trim()
            if (-not $target) { continue }   # [[#section]] is an internal anchor
            $null = $links.Add([pscustomobject]@{ Target = $target; Raw = $raw; Source = $s.Label; Line = $n })
        }
    }
}

$targets  = @($links | Select-Object -ExpandProperty Target -Unique | Sort-Object)
$resolved = @()
$dangling = @()
$invalidChars = [IO.Path]::GetInvalidFileNameChars()
foreach ($t in $targets) {
    # A malformed target is a FINDING, never an exception. As `/` and `\` count as
    # invalid, this also enforces the declared scope: [[sub/target]] does not resolve
    # into a subdirectory; it is reported.
    if ($t.IndexOfAny($invalidChars) -ge 0) { $dangling += $t; continue }
    if (Test-Path -LiteralPath (Join-Path $MemoryRoot ($t + '.md')) -PathType Leaf) { $resolved += $t }
    else { $dangling += $t }
}

$undeclared = @($dangling      | Where-Object { $KnownDangling -notcontains $_ })
$stale      = @($KnownDangling | Where-Object { $resolved -contains $_ })
$dead       = @($KnownDangling | Where-Object { $targets   -notcontains $_ })

if (-not $Quiet) {
    Write-Output ("memory: {0}" -f $MemoryRoot)
    Write-Output ("  {0} file(s) ({1} in the store, {2} extra) | {3} link(s) | {4} distinct target(s) | {5} resolve | {6} dangling, {7} declared" -f `
        $sources.Count, $files.Count, ($sources.Count - $files.Count), $links.Count, $targets.Count, `
        $resolved.Count, $dangling.Count, @($dangling | Where-Object { $KnownDangling -contains $_ }).Count)
}

$problems = 0
foreach ($t in $undeclared) {
    $problems++
    # Show the link AS WRITTEN when it differs from the target: that is what you search
    # for to find the line.
    $cites = @($links | Where-Object { $_.Target -eq $t } | ForEach-Object {
        if ($_.Raw -ne $t) { "{0}:{1} (written [[{2}]])" -f $_.Source, $_.Line, $_.Raw } else { "{0}:{1}" -f $_.Source, $_.Line }
    })
    Write-Output ("FAIL  [[{0}]] does not resolve and is not declared - cited at: {1}" -f $t, ($cites -join ', '))
}
foreach ($t in $stale) { $problems++; Write-Output ("FAIL  stale exception: [[{0}]] resolves again - remove it from KnownDangling" -f $t) }
foreach ($t in $dead)  { $problems++; Write-Output ("FAIL  dead exception: [[{0}]] is cited by nobody - remove it from KnownDangling" -f $t) }

if ($problems -gt 0) {
    Write-Output ("{0} wikilink problem(s)." -f $problems)
    exit 1
}
if (-not $Quiet) { Write-Output 'OK  every wikilink resolves, or is a declared and live exception.' }
exit 0
