<#
  Assert-PlanFreshness.ps1

  Gate: every PLAN.md under a projects root carries the Checkpoint fields, and no
  active plan has gone stale - by age, or by a Base that HEAD no longer descends from.

  WHY IT EXISTS. core/handoff/PLAN.md defines the schema (Status: active|paused|
  complete, Updated: YYYY-MM-DD, Base: <git SHA>) and the staleness rule (active and
  untouched for 14 days; or Base not an ancestor of HEAD). One practice measured its
  own directory: of 15 plans, 7 lacked the fields and 1 had been "active" for 18 days.
  A documented rule with no detector is the same shape as a backup that was broken
  for two weeks in silence.

  WHAT IT DOES NOT DO. It does not edit a PLAN.md - declaring the status of someone
  else's plan is asserting what the script does not know; it reports and a person
  decides. It does not read the file's mtime as if it were the update date: Updated:
  is a declaration, mtime is a side effect of any tool that touched the file. Both are
  shown so their divergence is visible; the note states the FACT (the dates differ),
  never a cause, because a reporter that names one cause declares the others absent.

  THREE FORMATS COEXIST in real plans, and the first regex written here matched only
  one of them - reporting 11 non-conformant plans that were conformant:
    - "- Status: complete"                          (list item)
    - "Status: active <dot> Updated: X <dot> Base: Y"  (one line, separated by U+00B7)
    - "Status: active"                              (its own line, as in the template)
  So the accepted prefix is: start of line with an optional list marker, OR an inline
  separator. Without that the checker would accuse the format, not the content - family
  1 applied to the checker itself.

  BASE ANCESTRY. For an active plan, if Base: names a commit and the plan's directory
  is a git work tree, `git merge-base --is-ancestor <base> HEAD` decides. Exit 1 there
  is a definite "not an ancestor" and counts as stale. A Base this clone does not have
  (exit 128) is reported as "not found here" and counted under could-not-check, not as
  stale: it may be the other machine's commit. Plans outside a git work tree are
  counted in one summary line, not listed one by one. Without git on PATH the age
  check still runs and the report says the ancestry surface was NOT exercised.

  NATIVE COMMANDS UNDER 'Stop'. Windows PowerShell 5.1 wraps a native executable's
  stderr in an error record, and with $ErrorActionPreference = 'Stop' that record
  TERMINATES the script - even with 2>$null. The first version of this gate died on
  the first directory that was not a repository, mid-report, with a non-zero exit that
  looked like a finding. Every git call goes through Invoke-Git, which lowers the
  preference only around the call and returns exit code and text.

  EXIT CONTRACT (three states):
    0  every plan conformant and fresh
    1  at least one stale or non-conformant plan
    2  could NOT verify (root missing, or no PLAN.md found at all)

  PARAMETERS
    -Root        Required. The directory whose immediate children are your projects.
    -MaxAgeDays  Staleness threshold for active plans. Default 14.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $Root,
    [int]    $MaxAgeDays = 14
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($Root)) {
    Write-Output 'COULD NOT VERIFY: -Root is required (the directory whose children are your projects).'
    exit 2
}
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Output "COULD NOT VERIFY: root does not exist: $Root"
    exit 2
}

$git = Get-Command git -ErrorAction SilentlyContinue

function Invoke-Git {
    # Runs git with the error preference lowered so stderr does not terminate the
    # script, and returns what the caller actually needs: the exit code and the text.
    param([string] $Dir, [string[]] $GitArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $global:LASTEXITCODE = $null
        $out = (& $git.Source -C $Dir @GitArgs 2>&1 | Out-String)
        $code = $global:LASTEXITCODE
    } finally { $ErrorActionPreference = $prev }
    return [pscustomobject]@{ Exit = $code; Out = $out }
}

$today = Get-Date
$stale = @(); $nonConformant = @(); $unchecked = @(); $notRepo = 0; $ok = 0; $seen = 0

foreach ($dir in (Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name)) {
    $plan = Join-Path $dir.FullName 'PLAN.md'
    if (-not (Test-Path -LiteralPath $plan -PathType Leaf)) { continue }
    $seen++
    try { $text = Get-Content -LiteralPath $plan -Raw -Encoding UTF8 } catch {
        $unchecked += [pscustomobject]@{ Project = $dir.Name; Why = "unreadable: $($_.Exception.Message)" }
        continue
    }

    $pre = '(?im)(?:^[ \t]*(?:[-*+][ \t]*)?|[' + [char]0x00B7 + '|;][ \t]*)'
    $mStatus  = [regex]::Match($text, $pre + 'Status:\s*(active|paused|complete)\b')
    $mUpdated = [regex]::Match($text, $pre + 'Updated:\s*(\d{4}-\d{2}-\d{2})')
    $mBase    = [regex]::Match($text, $pre + 'Base:\s*([0-9a-fA-F]{7,40})\b')
    $hasBase  = [regex]::IsMatch($text, $pre + 'Base:\s*\S')
    $mtime    = (Get-Item -LiteralPath $plan).LastWriteTime

    if (-not $mStatus.Success -or -not $mUpdated.Success) {
        $missing = @()
        if (-not $mStatus.Success)  { $missing += 'Status' }
        if (-not $mUpdated.Success) { $missing += 'Updated' }
        if (-not $hasBase)          { $missing += 'Base' }
        $nonConformant += [pscustomobject]@{ Project = $dir.Name; Missing = ($missing -join '+'); Mtime = $mtime.ToString('yyyy-MM-dd') }
        continue
    }

    $status  = $mStatus.Groups[1].Value
    $updated = [datetime] $mUpdated.Groups[1].Value
    $age     = [int] ($today - $updated).TotalDays
    $reasons = @()

    if ($status -eq 'active' -and $age -gt $MaxAgeDays) { $reasons += "Updated $($updated.ToString('yyyy-MM-dd')), $age day(s) ago" }

    if ($status -eq 'active' -and $mBase.Success -and $null -ne $git) {
        $inside = Invoke-Git -Dir $dir.FullName -GitArgs @('rev-parse', '--is-inside-work-tree')
        if ($inside.Exit -eq 0 -and $inside.Out.Trim() -eq 'true') {
            $anc = Invoke-Git -Dir $dir.FullName -GitArgs @('merge-base', '--is-ancestor', $mBase.Groups[1].Value, 'HEAD')
            switch ($anc.Exit) {
                0 { }
                1 { $reasons += "Base $($mBase.Groups[1].Value) is NOT an ancestor of HEAD - the plan describes code that moved underneath it" }
                default { $unchecked += [pscustomobject]@{ Project = $dir.Name; Why = "Base $($mBase.Groups[1].Value) not found in this clone (git exit $($anc.Exit))" } }
            }
        } else {
            $notRepo++
        }
    }

    if ($reasons.Count -gt 0) {
        $stale += [pscustomobject]@{ Project = $dir.Name; Reasons = $reasons; Updated = $updated.ToString('yyyy-MM-dd'); Mtime = $mtime.ToString('yyyy-MM-dd') }
    } else { $ok++ }
}

if ($seen -eq 0) {
    Write-Output "COULD NOT VERIFY: no PLAN.md under any child of $Root"
    exit 2
}

Write-Output "PLAN.md under $Root  (threshold: active for more than $MaxAgeDays days; Base must be an ancestor of HEAD)"
Write-Output ''

if ($stale.Count -gt 0) {
    Write-Output 'STALE -- active plans that failed a freshness rule:'
    foreach ($p in $stale) {
        foreach ($r in $p.Reasons) { Write-Output ("  FAIL  {0,-26} {1}" -f $p.Project, $r) }
        if ($p.Mtime -ne $p.Updated) {
            # The fact, not the cause: the file was touched after its declared date. Whether the
            # plan moved on or only the field was back-dated is for a person to check.
            Write-Output ("        (file last written {0}, after Updated {1} - check whether the plan moved or only the field did)" -f $p.Mtime, $p.Updated)
        }
    }
    Write-Output ''
}
if ($nonConformant.Count -gt 0) {
    Write-Output 'NON-CONFORMANT -- missing the Checkpoint fields core/handoff/PLAN.md defines:'
    foreach ($p in $nonConformant) { Write-Output ("  FAIL  {0,-26} missing: {1,-22} (mtime {2})" -f $p.Project, $p.Missing, $p.Mtime) }
    Write-Output ''
    Write-Output '  Without Status and Updated there is no way to tell whether the plan is alive, and a plan'
    Write-Output '  that cannot be told alive misinforms whoever reads it. Filling the fields is a human act.'
    Write-Output ''
}
if ($unchecked.Count -gt 0) {
    Write-Output 'COULD NOT CHECK -- reported, not counted as stale:'
    foreach ($p in $unchecked) { Write-Output ("        {0,-26} {1}" -f $p.Project, $p.Why) }
    Write-Output ''
}

Write-Output ("plans: {0} | conformant and fresh: {1} | stale: {2} | non-conformant: {3} | could not check: {4}" -f $seen, $ok, $stale.Count, $nonConformant.Count, $unchecked.Count)
if ($null -eq $git) { Write-Output 'surface NOT exercised: Base ancestry (git not on PATH)' }
elseif ($notRepo -gt 0) { Write-Output "surface NOT exercised for $notRepo active plan(s): Base ancestry (directory is not a git work tree)" }
if ($stale.Count -gt 0 -or $nonConformant.Count -gt 0) { exit 1 }
Write-Output 'OK  every plan is conformant and fresh.'
exit 0
