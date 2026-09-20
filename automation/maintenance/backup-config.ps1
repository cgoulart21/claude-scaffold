<#
  backup-config.ps1

  Back up your authored agent artifacts into a private repository:
  sync -> commit if anything changed -> push. Safe to run at any time; a no-op
  when nothing changed.

  Run it from inside an agent session if your host application is sandboxed, so
  that git and any credential helper resolve the way they normally do.

  The interesting part of this script is the push failure classification at the
  bottom. See the comment there before simplifying it.

  ASCII-only and dependency-free for Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$RepositoryPath,
    [string]$SyncScript,
    [string]$Remote = 'origin',
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Configuration: your private backup repository, and the script that copies your
# authored files into it. Leave the sync script empty if the repository IS the
# live location and nothing needs copying.
# ---------------------------------------------------------------------------
$DefaultRepositoryPath = ''    # e.g. C:\Path\To\your-private-config-repo
$DefaultSyncScript     = ''    # e.g. C:\Path\To\your-private-config-repo\sync.ps1
# ---------------------------------------------------------------------------

if ([string]::IsNullOrEmpty($RepositoryPath)) { $RepositoryPath = $DefaultRepositoryPath }
if ([string]::IsNullOrEmpty($SyncScript))     { $SyncScript     = $DefaultSyncScript }

if ([string]::IsNullOrEmpty($RepositoryPath) -or -not (Test-Path (Join-Path $RepositoryPath '.git'))) {
    Write-Output "Backup: no git repository at '$RepositoryPath' - skipping. Set the path at the top of this script."
    return
}

# ---------------------------------------------------------------------------
# FETCH BEFORE THE MIRROR TOUCHES ANYTHING. The old order was sync -> commit -> push,
# and a refused push was classified correctly - but by then the sync had already
# overwritten the tree with THIS machine's state and the commit existed. If the other
# machine had improved a mirrored file, the natural resolution (pull, sync again)
# reverted that improvement in the next cycle, silently. One practice lost a day to
# exactly this on 2026-08-05; the refused push was the only thing that saved it.
# So: if the remote is ahead, stop here, before any file changes, and say what to do.
# ---------------------------------------------------------------------------
$fetchOut = (git -C $RepositoryPath fetch -q $Remote $Branch 2>&1) | Out-String
if ($LASTEXITCODE -eq 0) {
    $behind = (git -C $RepositoryPath rev-list --count "HEAD..$Remote/$Branch" 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0 -and $behind.Trim() -match '^\d+$' -and [int]$behind.Trim() -gt 0) {
        Write-Output "Backup: this machine is BEHIND $Remote/$Branch by $($behind.Trim()) commit(s). Nothing was mirrored or committed."
        Write-Output "        Order is repository -> machine first (pull, then restore/bootstrap), machine -> repository after. Syncing now would overwrite what the other machine pushed."
        return
    }
}
else {
    # Could not fetch: say so and continue. Offline is not a reason to skip the local
    # backup; the push classification below will name the network if that is the cause.
    Write-Output "Backup: could not fetch $Remote/$Branch before syncing (continuing; push will tell). git said: $($fetchOut.Trim())"
}

if (-not [string]::IsNullOrEmpty($SyncScript) -and (Test-Path -LiteralPath $SyncScript)) {
    & $SyncScript | Out-Null
}

$changes = git -C $RepositoryPath status --porcelain
if ([string]::IsNullOrWhiteSpace($changes)) {
    Write-Output 'Backup: nothing changed since the last push.'
    return
}

git -C $RepositoryPath add -A
$stamp = Get-Date -Format 'yyyy-MM-dd'
git -C $RepositoryPath commit -q -m "backup: authored artifacts $stamp"

# ---------------------------------------------------------------------------
# The cause comes out of git's OUTPUT, never out of a guess.
#
# An earlier version printed "push failed - check the network" for every failure.
# Twice in one day the real cause was history divergence - another machine had
# pushed first - and both times the diagnosis sent someone to look at the network.
# A reporter that enumerates one failure mode implicitly declares the others do
# not exist. When the output cannot be classified, print it raw and say so.
#
# Windows PowerShell 5.1 wraps a native executable's stderr in an error record and
# decorates it with "At line:/+ ~~~~/CategoryInfo" blocks. Git's own text survives
# verbatim - which is why the matching below works - but the decoration is noise
# for whoever reads the report, so it is stripped before printing.
# ---------------------------------------------------------------------------
function Get-GitSaid {
    param([string]$Raw)
    $keep = $Raw -split "`r?`n" | Where-Object {
        $_ -notmatch '^(At line:|No linha:|Na linha:)' -and
        $_ -notmatch '^\s*\+' -and
        $_ -notmatch '^\s+\+?\s*(CategoryInfo|FullyQualifiedErrorId)' -and
        $_.Trim() -ne ''
    }
    return (($keep | ForEach-Object { $_ -replace '^git\s*:\s*', '' }) -join [Environment]::NewLine)
}

$pushOut = (git -C $RepositoryPath push $Remote $Branch 2>&1) | Out-String

if ($LASTEXITCODE -eq 0) {
    Write-Output "Backup: committed and pushed ($stamp)."
}
elseif ($pushOut -match 'non-fast-forward|fetch first|\[rejected\]|behind its remote') {
    $counts = ''
    git -C $RepositoryPath fetch -q $Remote $Branch 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $leftRight = (git -C $RepositoryPath rev-list --left-right --count "HEAD...$Remote/$Branch" 2>&1) | Out-String
        if ($LASTEXITCODE -eq 0 -and $leftRight -match '(\d+)\s+(\d+)') {
            $counts = " (ahead $($Matches[1]) / behind $($Matches[2]))"
        }
    }
    Write-Output "Backup: local commit OK, push REFUSED - history DIVERGENCE$counts. Another machine pushed first. This is NOT the network, and re-running a plain push will not fix it. Integrating the histories needs a deliberate decision."
}
elseif ($pushOut -match 'Could not resolve host|Connection (timed out|refused|reset)|Failed to connect|network is unreachable|Operation timed out') {
    Write-Output "Backup: local commit OK, push failed - NETWORK. Retry 'git -C $RepositoryPath push' when you have a connection."
}
elseif ($pushOut -match 'Authentication failed|could not read Username|Permission denied|403|denied to|auth status') {
    Write-Output 'Backup: local commit OK, push failed - AUTHENTICATION. If your host application is sandboxed, the session may need its context for the credential helper.'
}
else {
    Write-Output 'Backup: local commit OK, push failed for a reason that is NOT CLASSIFIED. What git actually said is below; nothing has been inferred.'
    Write-Output (Get-GitSaid $pushOut)
}
