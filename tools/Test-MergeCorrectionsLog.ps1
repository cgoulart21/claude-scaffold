<#
  Test-MergeCorrectionsLog.ps1

  Fixes the contracts of core/corrections/Merge-CorrectionsLog.ps1.

  This is the test that was missing when a line-based union replaced copy-over in the
  practice this came from: the change fixed line loss between machines and introduced
  a duplication mode of its own (`- X` and `X` are different strings), which surfaced
  only at a weekly routine with 3 duplicates already in the log. The block lived
  inline in a sync script and rewrote BOTH files - live and repository - with no test.
#>
[CmdletBinding()]
param([string]$MergerPath)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($MergerPath)) {
    $MergerPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\corrections\Merge-CorrectionsLog.ps1'
}
$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([string] $Name, [bool] $Condition, [string] $Detail = '')
    if ($Condition) { $script:Pass++; Write-Output "  PASS  $Name" }
    else { $script:Fail++; Write-Output "  FAIL  $Name"; if ($Detail) { Write-Output "          -> $Detail" } }
}

if (-not (Test-Path -LiteralPath $MergerPath -PathType Leaf)) {
    Write-Output "FAIL  Merge-CorrectionsLog.ps1 not found at $MergerPath"
    Write-Output 'PASS 0  FAIL 1'
    exit 1
}

function Invoke-Merge([string[]] $Repo, [string[]] $Live) { return & $MergerPath -RepoLines $Repo -LiveLines $Live -NewLine "`n" }
function Get-Entries($result) {
    # The leading ',' is mandatory: PS 5.1 UNROLLS a one-element array on return, and the
    # caller ends up indexing a string.
    return , @($result.MergedText -split "`n" | Where-Object { $_ -match '^- 20\d\d-\d\d-\d\d' })
}

$HEADER = @('# Corrections log', '', 'One line per correction.', '', '---', '')

Write-Output 'Group 1 - nothing disappears, and the repository order is preserved'
$repo = $HEADER + @('- 2026-01-01 A', '- 2026-01-02 B')
$live = $HEADER + @('- 2026-01-01 A', '- 2026-01-02 B', '- 2026-01-03 C')
$r = Invoke-Merge $repo $live
$e = Get-Entries $r
Assert-True 'all 3 entries are in the result' ($e.Count -eq 3) "$($e.Count)"
Assert-True 'the repository order comes first' ($e[0] -match ' A$' -and $e[1] -match ' B$')
Assert-True 'the new live entry goes last' ($e[2] -match ' C$')
Assert-True 'Added counts only the new entry' ($r.Added -eq 1) "$($r.Added)"
Assert-True 'Collapsed is empty when there is no variant' ($r.Collapsed.Count -eq 0) "$($r.Collapsed.Count)"

Write-Output 'Group 2 - an entry the REPOSITORY has and the live copy lacks survives'
$repo = $HEADER + @('- 2026-01-01 A', '- 2026-02-02 repo-only')
$live = $HEADER + @('- 2026-01-01 A')
$r = Invoke-Merge $repo $live
Assert-True 'the other machine''s entry was not erased' ((Get-Entries $r) -join "`n" -match 'repo-only')
Assert-True 'no new entry counted' ($r.Added -eq 0)

Write-Output 'Group 3 - a missing bullet is the SAME entry'
$r = Invoke-Merge ($HEADER + @('- 2026-03-01 entry with bullet in repo')) ($HEADER + @('2026-03-01 entry with bullet in repo'))
$e = Get-Entries $r
Assert-True 'not duplicated' ($e.Count -eq 1) ($e -join ' | ')
Assert-True 'the bullet was restored on write' ($e[0].StartsWith('- 2026-03-01'))
Assert-True 'not counted as new' ($r.Added -eq 0) "$($r.Added)"
$r2 = Invoke-Merge ($HEADER + @('2026-03-01 same entry')) ($HEADER + @('- 2026-03-01 same entry'))
Assert-True 'the inverse (repo without bullet, live with) does not duplicate either' ((Get-Entries $r2).Count -eq 1)
$r3 = Invoke-Merge ($HEADER + @('- 2026-03-02 text  with   spaces')) ($HEADER + @('- 2026-03-02 text with spaces'))
Assert-True 'collapsed whitespace does not create a new entry' ((Get-Entries $r3).Count -eq 1)

Write-Output 'Group 4 - an in-place edit collapses onto the longer wording (promotion marker)'
$base = '- 2026-04-01 ran the wrong command and read exit 0 as success, when the target did not even exist'
$prom = $base + ' **PROMOTED 2026-04-02 -> family 9**'
$r = Invoke-Merge ($HEADER + @($base)) ($HEADER + @($prom))
$e = Get-Entries $r
Assert-True 'one entry only' ($e.Count -eq 1) ($e -join ' | ')
Assert-True 'the wording WITH the marker stays' ($e[0] -match 'PROMOTED') $e[0]
Assert-True 'counted as a collapse, not as a new entry' ($r.Collapsed.Count -eq 1 -and $r.Added -eq 0) "Collapsed=$($r.Collapsed.Count) Added=$($r.Added)"
$r = Invoke-Merge ($HEADER + @($prom)) ($HEADER + @($base))
$e = Get-Entries $r
Assert-True 'inverse: a marker added on the repository side survives too' ($e.Count -eq 1 -and $e[0] -match 'PROMOTED') ($e -join ' | ')

Write-Output 'Group 5 - DISTINCT entries with a long common prefix BOTH stay'
# The regression the first version had: it compared the first 60 characters and kept the
# longer, deleting a distinct entry from BOTH logs. These two share 74 characters.
$f1 = '- 2026-08-22 tool gotcha, some router 2.2.4 on project X: with more than one thread it is not reproducible'
$f2 = '- 2026-08-22 tool gotcha, some router 2.2.4 on project X: it only terminates on a pad, never mid-trace'
$r = Invoke-Merge ($HEADER + @($f1)) ($HEADER + @($f2))
$e = Get-Entries $r
Assert-True 'BOTH distinct entries survived' ($e.Count -eq 2) ("got {0}: {1}" -f $e.Count, ($e -join ' || '))
Assert-True 'neither was reported as collapsed' ($r.Collapsed.Count -eq 0) ("discarded: " + ($r.Collapsed -join ' || '))
$r = Invoke-Merge ($HEADER + @('- 2026-08-23 ran gate P4 and read the inclusive limit as exclusive, wrong')) ($HEADER + @('- 2026-08-23 ran gate P3 and hardcoded the protocol literal, wrong'))
Assert-True 'divergence right after the date also keeps both' ((Get-Entries $r).Count -eq 2)

Write-Output 'Group 6 - the discarded text is returned, not just counted'
$r = Invoke-Merge ($HEADER + @($base)) ($HEADER + @($prom))
Assert-True 'Collapsed returns the TEXT of the discarded wording' ($r.Collapsed.Count -eq 1 -and $r.Collapsed[0] -is [string] -and $r.Collapsed[0].Length -gt 40)
Assert-True 'and the discarded one is the SHORT wording, without the marker' ($r.Collapsed[0] -notmatch 'PROMOTED') $r.Collapsed[0]

Write-Output 'Group 7 - a prefix below the floor does not authorise a discard'
$r = Invoke-Merge ($HEADER + @('- 2026-08-24 short note')) ($HEADER + @('- 2026-08-24 short note that was later extended with much more text'))
Assert-True 'a prefix below the floor keeps both entries' ((Get-Entries $r).Count -eq 2)

Write-Output 'Group 8 - prose only the live copy has is NOT erased'
$repo = $HEADER + @('- 2026-05-01 A')
$live = $HEADER + @('A new paragraph only the live copy has.', '- 2026-05-01 A')
$r = Invoke-Merge $repo $live
Assert-True 'the live-only prose was detected' ($r.LiveOnlyProse.Count -eq 1) "$($r.LiveOnlyProse.Count)"
Assert-True 'the LIVE file will not be rewritten in that case' (-not $r.WriteLive)
$r = Invoke-Merge $repo ($HEADER + @('- 2026-05-01 A'))
Assert-True 'with no prose divergence, the live file is rewritten normally' $r.WriteLive

Write-Output 'Group 9 - the repository header dictates the form and survives'
$r = Invoke-Merge ($HEADER + @('- 2026-06-01 A')) ($HEADER + @('- 2026-06-01 A'))
Assert-True 'the log title is still the first line' ($r.MergedText.StartsWith('# Corrections log'))
Assert-True 'the --- separator survived' ($r.MergedText -match '(?m)^---$')

Write-Output 'Group 10 - idempotent: running twice changes nothing and duplicates nothing'
$repo = $HEADER + @('- 2026-07-01 A', '- 2026-07-02 B')
$live = $HEADER + @('- 2026-07-02 B', '- 2026-07-03 C')
$r1 = Invoke-Merge $repo $live
$lines1 = @($r1.MergedText -split "`n")
$r2 = Invoke-Merge $lines1 $lines1
Assert-True 'the second pass is byte-identical to the first' ($r2.MergedText -eq $r1.MergedText)
Assert-True 'no entry added on the second pass' ($r2.Added -eq 0)
Assert-True 'the 3 distinct entries are there (a real union of both sides)' ((Get-Entries $r1).Count -eq 3)

Write-Output 'Group 11 - no entry from either side is lost (sweep)'
$repo = $HEADER + @('- 2026-08-01 R1', '- 2026-08-02 R2', '2026-08-03 R3-no-bullet')
$live = $HEADER + @('- 2026-08-02 R2', '- 2026-08-04 L1', '2026-08-05 L2-no-bullet')
$r = Invoke-Merge $repo $live
$missing = @()
foreach ($tag in @('R1', 'R2', 'R3-no-bullet', 'L1', 'L2-no-bullet')) { if ($r.MergedText -notmatch [regex]::Escape($tag)) { $missing += $tag } }
Assert-True 'all 5 entries from both sides are present' ($missing.Count -eq 0) ("missing: " + ($missing -join ', '))
Assert-True 'every written entry has a bullet' (@($r.MergedText -split "`n" | Where-Object { $_ -match '^20\d\d-\d\d-\d\d' }).Count -eq 0)

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
