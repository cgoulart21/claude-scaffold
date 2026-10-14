<#
  Test-AssertMirrorFreshness.ps1

  Suite for automation/verification/Assert-MirrorFreshness.ps1, and for the guard that
  automation/maintenance/backup-config.ps1 builds on it.

  Hermetic: every case builds a live folder, a mirror folder and a pairs file under
  $env:TEMP. Timestamps are SET, never waited for, so the cases do not depend on how fast
  the machine is.

  The backup group drives the real backup script against a throwaway git repository with
  no remote, and a sync stub that does what every sync does - copy live over mirror. That
  is the failure being guarded: a machine pulls a newer mirror, nobody restores it to the
  live side, and the next backup copies the old live file over it and commits the
  reversion. A source-reading test would pass over a guard that no longer runs; this one
  watches the mirror survive. If git is not on PATH that group is SKIPPED and says so.
#>
[CmdletBinding()]
param([string]$GatePath, [string]$BackupPath)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrEmpty($GatePath))   { $GatePath   = Join-Path $repoRoot 'automation\verification\Assert-MirrorFreshness.ps1' }
if ([string]::IsNullOrEmpty($BackupPath)) { $BackupPath = Join-Path $repoRoot 'automation\maintenance\backup-config.ps1' }
$script:Pass = 0
$script:Fail = 0
$script:Skip = 0
$script:Temps = New-Object 'System.Collections.ArrayList'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Invoke-Ps {
    param([string] $Script, [string[]] $ScriptArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $global:LASTEXITCODE = $null
        $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $Script @ScriptArgs 2>&1 | Out-String)
        $code = $global:LASTEXITCODE
    } finally { $ErrorActionPreference = $prev }
    return [pscustomobject]@{ Exit = $code; Out = $out }
}

function Assert-True {
    param([string] $Name, [bool] $Condition, [string] $Detail)
    if ($Condition) { $script:Pass++; Write-Output "  PASS  $Name" }
    else { $script:Fail++; Write-Output "  FAIL  $Name"; if ($Detail) { Write-Output "          -> $Detail" } }
}

function New-Box {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('mirror-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
    New-Item -ItemType Directory -Path (Join-Path $dir 'live'), (Join-Path $dir 'repo') -Force | Out-Null
    $null = $script:Temps.Add($dir)
    return $dir
}

function Set-File {
    param([string] $Path, [string] $Text, [int] $AgeMinutes)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
    (Get-Item -LiteralPath $Path).LastWriteTime = (Get-Date).AddMinutes(-$AgeMinutes)
}

function Set-Pairs {
    param([string] $Box, [string[]] $Lines)
    $p = Join-Path $Box 'repo\mirror-pairs.txt'
    [IO.File]::WriteAllText($p, (($Lines -join "`n") + "`n"), $Utf8NoBom)
    return $p
}

try {
    Assert-True 'the gate exists' (Test-Path -LiteralPath $GatePath -PathType Leaf) $GatePath
    if (-not (Test-Path -LiteralPath $GatePath -PathType Leaf)) { throw 'gate missing' }

    Write-Output 'Group 1 - state 0: nothing ahead'
    $box = New-Box
    Set-File (Join-Path $box 'live\a.md') "same`n" 60
    Set-File (Join-Path $box 'repo\a.md') "same`n" 1
    Set-File (Join-Path $box 'live\b.md') "edited live`n" 1
    Set-File (Join-Path $box 'repo\b.md') "old mirror`n" 60
    Set-File (Join-Path $box 'live\c.md') "new file`n" 1
    $pairs = Set-Pairs $box @(
        '# comment lines and blank lines are ignored', '',
        "$box\live\a.md => a.md",
        "$box\live\b.md => b.md",
        "$box\live\c.md => c.md",
        "$box\live\gone.md => gone.md")
    $r = Invoke-Ps $GatePath @('-PairsFile', $pairs)
    Assert-True 'equal content, live newer, live-only and live-missing: exit 0' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'equal content with a NEWER mirror is not a finding (checkout moves mtimes)' ($r.Out -notmatch 'a\.md.*AHEAD') $r.Out
    Assert-True 'live newer is reported as pending' ($r.Out -match 'pending\s+.*b\.md') $r.Out
    Assert-True 'a file only on the live side is pending' ($r.Out -match 'pending\s+.*c\.md') $r.Out
    Assert-True 'the summary counts 4 pairs, 2 pending, 0 ahead, 1 live missing' ($r.Out -match '4 pair\(s\).*2 pending.*0 ahead.*1 live missing') $r.Out
    Assert-True 'prints OK' ($r.Out -match 'OK\s+no mirror is ahead') $r.Out

    Write-Output 'Group 1b - line endings alone are not a difference'
    # A checkout under core.autocrlf=true (a fresh clone, an agent worktree) writes CRLF
    # where the live file is LF, and its mtime is the newest: byte hashes reported every
    # text pair as ahead. Text compares modulo CRLF/LF; a file with a NUL byte is binary
    # and compares raw.
    $box = New-Box
    Set-File (Join-Path $box 'live\a.md') "line a`nline b`n" 600
    Set-File (Join-Path $box 'repo\a.md') "line a`r`nline b`r`n" 5
    Set-File (Join-Path $box 'live\t.md') "line a`nline b`n" 600
    Set-File (Join-Path $box 'repo\t.md') "line a`r`nline c`r`n" 5
    Set-File (Join-Path $box 'live\z.bin') "a`0`nb`n" 600
    Set-File (Join-Path $box 'repo\z.bin') "a`0`r`nb`r`n" 5
    $pairs = Set-Pairs $box @("$box\live\a.md => a.md", "$box\live\t.md => t.md", "$box\live\z.bin => z.bin")
    $r = Invoke-Ps $GatePath @('-PairsFile', $pairs)
    Assert-True 'CRLF vs LF with the same text is not ahead' ($r.Out -notmatch 'a\.md.*AHEAD') $r.Out
    Assert-True 'CRLF plus a text change is still ahead' ($r.Out -match 'FINDING\s+.*t\.md.*AHEAD') $r.Out
    Assert-True 'a file with a NUL byte compares raw' ($r.Out -match 'FINDING\s+.*z\.bin.*AHEAD') $r.Out
    Assert-True 'line endings: exactly 2 ahead' ($r.Out -match '2 ahead') $r.Out

    Write-Output 'Group 2 - state 1: a mirror ahead of its live file'
    $box = New-Box
    Set-File (Join-Path $box 'live\a.md') "old live`n" 600
    Set-File (Join-Path $box 'repo\a.md') "pulled, newer`n" 5
    $pairs = Set-Pairs $box @("$box\live\a.md => a.md")
    $r = Invoke-Ps $GatePath @('-PairsFile', $pairs)
    Assert-True 'mirror newer and different: exit 1' ($r.Exit -eq 1) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'the finding names the file and says AHEAD' ($r.Out -match 'FINDING\s+.*a\.md.*AHEAD') $r.Out
    Assert-True 'the finding says not to sync' ($r.Out -match '(?i)do not (run the )?sync') $r.Out
    Assert-True 'the mirror is untouched by the gate' ([IO.File]::ReadAllText((Join-Path $box 'repo\a.md')) -eq "pulled, newer`n")
    # Equal mtimes and different content is ambiguous; ambiguous is not permission to copy.
    (Get-Item -LiteralPath (Join-Path $box 'live\a.md')).LastWriteTime = (Get-Item -LiteralPath (Join-Path $box 'repo\a.md')).LastWriteTime
    $r = Invoke-Ps $GatePath @('-PairsFile', $pairs)
    Assert-True 'equal mtimes with different content is a finding too (exit 1)' ($r.Exit -eq 1) "exit [$($r.Exit)]"

    Write-Output 'Group 3 - directory pairs are compared file by file'
    $box = New-Box
    Set-File (Join-Path $box 'live\skill\SKILL.md') "same`n" 60
    Set-File (Join-Path $box 'repo\skill\SKILL.md') "same`n" 60
    Set-File (Join-Path $box 'live\skill\ref\deep.md') "old`n" 600
    Set-File (Join-Path $box 'repo\skill\ref\deep.md') "newer`n" 5
    $pairs = Set-Pairs $box @("$box\live\skill => skill")
    $r = Invoke-Ps $GatePath @('-PairsFile', $pairs)
    Assert-True 'a nested file ahead inside a directory pair: exit 1' ($r.Exit -eq 1) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'the finding names the nested file' ($r.Out -match 'deep\.md') $r.Out
    Assert-True 'and counts 2 files' ($r.Out -match '2 file\(s\)') $r.Out

    Write-Output 'Group 4 - home expansion and relative mirrors'
    $box = New-Box
    Set-File (Join-Path $box 'live\h.md') "old`n" 600
    Set-File (Join-Path $box 'repo\sub\h.md') "newer`n" 5
    $pairs = Set-Pairs $box @('~\h.md => sub\h.md')
    $r = Invoke-Ps $GatePath @('-PairsFile', $pairs, '-HomeRoot', (Join-Path $box 'live'))
    Assert-True '~ expands to -HomeRoot and the mirror resolves next to the pairs file (exit 1)' ($r.Exit -eq 1 -and $r.Out -match 'h\.md') "exit [$($r.Exit)]; $($r.Out)"

    Write-Output 'Group 5 - state 2: could not verify, and never a 1'
    $r = Invoke-Ps $GatePath @('-PairsFile', (Join-Path ([IO.Path]::GetTempPath()) ('no-such-' + [guid]::NewGuid().ToString('N') + '\mirror-pairs.txt')))
    Assert-True 'missing pairs file: exit 2' ($r.Exit -eq 2) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'and says COULD NOT VERIFY' ($r.Out -match 'COULD NOT VERIFY') $r.Out
    $r = Invoke-Ps $GatePath @()
    Assert-True 'no pairs file given: exit 2' ($r.Exit -eq 2) "exit [$($r.Exit)]; $($r.Out)"
    $box = New-Box
    $pairs = Set-Pairs $box @('# only a comment', '')
    $r = Invoke-Ps $GatePath @('-PairsFile', $pairs)
    Assert-True 'a pairs file with no pair: exit 2, not a clean 0' ($r.Exit -eq 2) "exit [$($r.Exit)]; $($r.Out)"
    Set-File (Join-Path $box 'live\a.md') "x`n" 5
    Set-File (Join-Path $box 'repo\a.md') "x`n" 5
    $pairs = Set-Pairs $box @("$box\live\a.md => a.md", 'this line has no arrow')
    $r = Invoke-Ps $GatePath @('-PairsFile', $pairs)
    Assert-True 'one malformed line among good ones: exit 2 (a skipped pair is a hole)' ($r.Exit -eq 2) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'and the malformed line is named' ($r.Out -match 'line 2') $r.Out
    # A mirror path that is not a valid path at all must break INTO 2, never into 1.
    $pairs = Set-Pairs $box @("$box\live\a.md => bad|name.md")
    $r = Invoke-Ps $GatePath @('-PairsFile', $pairs)
    Assert-True 'an invalid path character ends in 2, not 1' ($r.Exit -eq 2) "exit [$($r.Exit)]; $($r.Out)"

    Write-Output 'Group 6 - the backup consults the gate before it syncs'
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        $script:Skip++
        Write-Output '  SKIP  git not on PATH - the backup guard was NOT exercised'
    }
    elseif (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
        Assert-True 'backup-config.ps1 exists' $false $BackupPath
    }
    else {
        $box = New-Box
        $repo = Join-Path $box 'repo'
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & git -C $repo init -q 2>&1 | Out-Null
        & git -C $repo config user.email 'fixture' 2>&1 | Out-Null
        & git -C $repo config user.name 'test' 2>&1 | Out-Null
        & git -C $repo config commit.gpgsign false 2>&1 | Out-Null
        $ErrorActionPreference = $prev
        Set-File (Join-Path $box 'live\a.md') "old live`n" 600
        Set-File (Join-Path $repo 'a.md') "pulled, newer`n" 5
        $pairs = Set-Pairs $box @("$box\live\a.md => a.md")
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & git -C $repo add -A 2>&1 | Out-Null
        & git -C $repo commit -q -m 'pulled state' 2>&1 | Out-Null
        $ErrorActionPreference = $prev
        # The stub is what every sync is: copy live over mirror. It also leaves a marker,
        # so the test can tell "the guard stopped it" from "it ran and changed nothing".
        $stub = Join-Path $box 'sync-stub.ps1'
        $stubText = "Copy-Item -LiteralPath '" + (Join-Path $box 'live\a.md') + "' -Destination '" + (Join-Path $repo 'a.md') + "' -Force`r`n" +
            "Set-Content -LiteralPath '" + (Join-Path $box 'sync-ran.txt') + "' -Value 'ran'`r`nexit 0`r`n"
        [IO.File]::WriteAllText($stub, $stubText, $Utf8NoBom)
        $commitsBefore = (& git -C $repo rev-list --count HEAD 2>$null)

        $r = Invoke-Ps $BackupPath @('-RepositoryPath', $repo, '-SyncScript', $stub, '-MirrorPairs', $pairs, '-MirrorGate', $GatePath)
        Assert-True 'mirror ahead: the backup says it stopped' ($r.Out -match '(?i)mirror .*AHEAD|STOPPED') $r.Out
        Assert-True 'mirror ahead: the sync did NOT run' (-not (Test-Path -LiteralPath (Join-Path $box 'sync-ran.txt'))) $r.Out
        Assert-True 'mirror ahead: the pulled mirror survives' ([IO.File]::ReadAllText((Join-Path $repo 'a.md')) -eq "pulled, newer`n")
        Assert-True 'mirror ahead: nothing was committed' ((& git -C $repo rev-list --count HEAD 2>$null) -eq $commitsBefore)

        # Gate configured but unable to run: stop too. A guard that cannot run is not a pass.
        $r = Invoke-Ps $BackupPath @('-RepositoryPath', $repo, '-SyncScript', $stub, '-MirrorPairs', (Join-Path $box 'nope.txt'), '-MirrorGate', $GatePath)
        Assert-True 'gate could not verify: the sync did NOT run' (-not (Test-Path -LiteralPath (Join-Path $box 'sync-ran.txt'))) $r.Out

        # Half-configured (gate without pairs): stop, and say why, instead of a binder error.
        $r = Invoke-Ps $BackupPath @('-RepositoryPath', $repo, '-SyncScript', $stub, '-MirrorGate', $GatePath)
        Assert-True 'gate without a pairs file: the sync did NOT run' (-not (Test-Path -LiteralPath (Join-Path $box 'sync-ran.txt'))) $r.Out
        Assert-True 'and the reason is named' ($r.Out -match 'without a pairs file') $r.Out

        # A sync that fails must not be followed by a commit of whatever is in the tree.
        $failStub = Join-Path $box 'sync-fails.ps1'
        [IO.File]::WriteAllText($failStub, "Set-Content -LiteralPath '" + (Join-Path $repo 'half.md') + "' -Value 'half'`r`nexit 1`r`n", $Utf8NoBom)
        $r = Invoke-Ps $BackupPath @('-RepositoryPath', $repo, '-SyncScript', $failStub)
        Assert-True 'a failing sync stops the backup' ($r.Out -match '(?i)sync .*fail') $r.Out
        Assert-True 'a failing sync leads to no commit' ((& git -C $repo rev-list --count HEAD 2>$null) -eq $commitsBefore)
        Remove-Item -LiteralPath (Join-Path $repo 'half.md') -Force -ErrorAction SilentlyContinue

        # Restored (live now newer): the guard lets the sync through and the backup commits.
        Set-File (Join-Path $box 'live\a.md') "restored and edited`n" 1
        $r = Invoke-Ps $BackupPath @('-RepositoryPath', $repo, '-SyncScript', $stub, '-MirrorPairs', $pairs, '-MirrorGate', $GatePath)
        Assert-True 'live newer: the sync ran' (Test-Path -LiteralPath (Join-Path $box 'sync-ran.txt')) $r.Out
        Assert-True 'live newer: the backup committed' ([int](& git -C $repo rev-list --count HEAD 2>$null) -eq ([int]$commitsBefore + 1)) $r.Out

        # Not configured: the backup says so, rather than skipping in silence.
        Remove-Item -LiteralPath (Join-Path $box 'sync-ran.txt') -Force
        $r = Invoke-Ps $BackupPath @('-RepositoryPath', $repo, '-SyncScript', $stub)
        Assert-True 'unconfigured guard is announced, not silent' ($r.Out -match '(?i)mirror check.*not configured') $r.Out
    }
}
finally {
    foreach ($d in $script:Temps) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Output ''
if ($script:Skip -gt 0) { Write-Output "($script:Skip group(s) skipped)" }
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
