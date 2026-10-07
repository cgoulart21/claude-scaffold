<#
  Assert-MirrorFreshness.ps1

  Gate: no MIRROR in your backup repository is ahead of the LIVE file it mirrors.

  WHY IT EXISTS. A sync runs one way: live configuration -> backup repository. That
  direction is safe exactly as long as the live side is never older than the mirror. Two
  ordinary events break it, and neither errors:
    - someone edits the mirror instead of the live file; the next sync reverts the edit;
    - a machine that was away pulls the repository - getting another machine's newer
      mirror - and syncs before restoring that mirror to its own live side. The sync
      copies the stale live file over the fresh mirror, the commit is clean, the push is
      clean, and the other machine's improvement is gone.
  The second case is the one docs/60-maintenance.md used to call "the case no script
  catches". It bit a practice whose restore step covered the files under its main config
  folder and missed one that lived elsewhere: the procedure was right, the coverage of the
  procedure was not. This gate measures the coverage instead of trusting it.

  THE PAIRS FILE is the one source of truth for what is mirrored. One pair per line:

      <live path> => <mirror path>

  Blank lines and lines starting with # are ignored. A leading ~ expands to -HomeRoot (by
  default the user profile). A relative mirror path resolves against the folder of the
  pairs file - put the file at the root of your backup repository. Either side may be a
  file or a directory; directories are compared file by file, by relative name. Have your
  sync script read the same file, so the list of what is copied and the list of what is
  checked cannot drift apart.

  CLASSIFICATION, per file:
    same content                        -> fine, whatever the mtimes (checkout moves them)
    live only, or live newer            -> PENDING: a sync is due; not a finding
    live missing                        -> counted; the sync has nothing to copy either
    different, mirror newer OR equal    -> FINDING. Running the sync now destroys the
                                           difference. Equal mtimes are ambiguous, and
                                           ambiguous is not permission to overwrite.

  EXIT CONTRACT - three states, never two:
    0  checked, and no mirror is ahead
    1  checked, and at least one mirror is ahead (each one printed)
    2  could NOT verify: no pairs file, no pair in it, a malformed line, or the gate broke.
       A malformed line is a 2 and not a warning: a pair skipped in silence is exactly
       the hole this gate exists to close. No breaking path reaches 1.

  ASCII-only and dependency-free for Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string] $PairsFile,
    [string] $HomeRoot
)

$ErrorActionPreference = 'Stop'

function Write-CouldNot([string] $Why) { Write-Output "COULD NOT VERIFY: $Why"; exit 2 }

try {
    if ([string]::IsNullOrEmpty($HomeRoot)) { $HomeRoot = $env:USERPROFILE }
    if ([string]::IsNullOrEmpty($PairsFile)) { Write-CouldNot 'no -PairsFile given' }
    if (-not (Test-Path -LiteralPath $PairsFile -PathType Leaf)) { Write-CouldNot "pairs file not found: $PairsFile" }
    $pairsDir = Split-Path -Parent (Resolve-Path -LiteralPath $PairsFile).ProviderPath

    function Resolve-Side([string] $Raw, [bool] $IsMirror) {
        $p = $Raw.Trim()
        if ($p -eq '~' -or $p.StartsWith('~\') -or $p.StartsWith('~/')) {
            $p = Join-Path $HomeRoot ($p.Substring(1).TrimStart('\', '/'))
        }
        elseif ($IsMirror -and -not [IO.Path]::IsPathRooted($p)) {
            $p = Join-Path $pairsDir $p
        }
        return [IO.Path]::GetFullPath($p)
    }

    # --- 1. the pairs, from the one source ---------------------------------------
    $pairs = @()
    $malformed = @()
    $lineNo = 0
    foreach ($line in [IO.File]::ReadAllLines($PairsFile)) {
        $lineNo++
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $m = [regex]::Match($t, '^(.+?)\s+=>\s+(.+)$')
        if (-not $m.Success) { $malformed += "line $lineNo"; continue }
        $pairs += [pscustomobject]@{
            Live   = (Resolve-Side $m.Groups[1].Value $false)
            Mirror = (Resolve-Side $m.Groups[2].Value $true)
        }
    }
    if ($malformed.Count -gt 0) { Write-CouldNot ("malformed pair(s) in {0}: {1} - expected '<live> => <mirror>'" -f $PairsFile, ($malformed -join ', ')) }
    if ($pairs.Count -eq 0) { Write-CouldNot "no pair in $PairsFile" }

    function Get-Sha([string] $Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

    # --- 2. compare file by file ---------------------------------------------------
    $files = 0; $pending = 0; $ahead = 0; $liveMissing = 0
    foreach ($pair in $pairs) {
        if (-not (Test-Path -LiteralPath $pair.Live)) { $liveMissing++; continue }
        $item = Get-Item -LiteralPath $pair.Live -Force
        if ($item.PSIsContainer) {
            $list = @(Get-ChildItem -LiteralPath $pair.Live -Recurse -File -Force | ForEach-Object {
                $rel = $_.FullName.Substring($item.FullName.Length).TrimStart('\')
                [pscustomobject]@{ Live = $_.FullName; Mirror = (Join-Path $pair.Mirror $rel); Name = $rel }
            })
        }
        else {
            $list = @([pscustomobject]@{ Live = $item.FullName; Mirror = $pair.Mirror; Name = $item.Name })
        }
        foreach ($f in $list) {
            $files++
            if (-not (Test-Path -LiteralPath $f.Mirror -PathType Leaf)) {
                Write-Output "pending  $($f.Name)  (live only; a sync is due)"
                $pending++
                continue
            }
            if ((Get-Sha $f.Live) -eq (Get-Sha $f.Mirror)) { continue }
            $tLive   = (Get-Item -LiteralPath $f.Live -Force).LastWriteTimeUtc
            $tMirror = (Get-Item -LiteralPath $f.Mirror -Force).LastWriteTimeUtc
            if ($tLive -gt $tMirror) {
                Write-Output "pending  $($f.Name)  (live newer; a sync is due)"
                $pending++
                continue
            }
            Write-Output ("FINDING  {0}: mirror AHEAD of live (mirror {1:yyyy-MM-dd HH:mm:ss}Z, live {2:yyyy-MM-dd HH:mm:ss}Z)" -f $f.Name, $tMirror, $tLive)
            Write-Output "         mirror: $($f.Mirror)"
            Write-Output "         live:   $($f.Live)"
            Write-Output '         Do not run the sync now: it would overwrite this difference. Either the mirror was edited (edit the LIVE file instead and discard the copy), or the repository was pulled and not yet restored to this machine (restore first, then sync).'
            $ahead++
        }
    }

    Write-Output ''
    Write-Output ("checked {0} pair(s), {1} file(s): {2} pending, {3} ahead, {4} live missing" -f $pairs.Count, $files, $pending, $ahead, $liveMissing)
    if ($ahead -gt 0) { exit 1 }
    Write-Output 'OK  no mirror is ahead of its live file.'
    exit 0
}
catch {
    # The gate breaking is "could not verify" - never "found", never "clean".
    Write-Output "COULD NOT VERIFY: $($_.Exception.GetType().Name): $($_.Exception.Message)"
    exit 2
}
