<#
  Assert-MemorySources.ps1

  Gate: a memory that mirrors a file in a repository declares the commit it was checked
  against, and fails the run once that file has changed since.

  WHY IT EXISTS. A memory that says "the published page mirrors docs/protocol.md,
  revision 1.4" was true when written. Then the document gets an erratum. The path still
  exists, every link still resolves, the index line is still verbatim - and the memory,
  together with the published page it points at, goes on asserting the old revision.
  Nothing announces it, because nothing was broken: the source moved and the claim
  stayed. A check that the path exists cannot see this; only the content can.

  THE DECLARATION. Optional, per memory, in the body, inside a code span:

      source: <absolute path, or ~/...> @ <commit, 7 to 64 hex digits>

  The path may be a file or a folder, and may contain spaces - the delimiter is the
  final ' @ ', not whitespace. The gate asks the source's own repository whether the
  path differs, IN THE WORKING TREE, from what it was at that commit
  (git diff --quiet <commit> -- <path>). An erratum typed but not yet committed counts,
  and so does a source that was deleted.

  WHAT THE COMMIT MEANS. "I checked this memory, and the surface it points at, against
  THIS version." Stamping HEAD without checking manufactures exactly the green this gate
  exists to prevent. To clear a finding: check the memory and the published surface
  against the source, then rewrite the commit in the declaration.

  NOT MEASURABLE IS NOT A FINDING. One store often serves several machines, and a source
  repository cloned on one is absent from another. So: no usable repository at the path,
  a commit this clone does not know, git missing or refusing the folder - each prints
  WARN with the reason, is counted in the summary, and does not fail the run. But a
  malformed declaration, or a commit that does not contain the declared path, are
  measured facts about the claim itself: those are findings.

  HONEST LIMITS. A NEW, untracked file inside a declared folder does not show in the
  diff. And the gate measures that the SOURCE changed - never that the memory became
  wrong. It tells you where to look, not what you will find.

  SCOPE. The .md files at the top of -MemoryRoot (no recursion: an archive of frozen
  memories makes claims that are history, not contract).

  EXIT CONTRACT (three states):
    0  at least one source was measured, and none changed since its declared commit
    1  a source changed, a declaration is malformed, or a commit lacks the declared path
    2  could NOT verify: -MemoryRoot missing, no .md to scan, no declaration found, or
       not one declared source measurable on this machine (an empty sweep is not a
       clean sweep)

  PARAMETERS
    -MemoryRoot   The memory store. Required: this gate cannot guess where yours is.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $MemoryRoot
)

$ErrorActionPreference = 'Stop'

# git writes to stderr even on success (line-ending notices), and under Windows
# PowerShell 5.1 redirected native stderr becomes a terminating error when the preference
# is 'Stop'. So the preference is relaxed around the call only, and the exit code decides.
function Invoke-Git([string] $Dir, [string[]] $GitArgs) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $global:LASTEXITCODE = $null
        $out = (& git -C $Dir @GitArgs 2>&1 | Out-String)
        return [pscustomobject]@{ Exit = $global:LASTEXITCODE; Out = ([string]$out).Trim() }
    }
    catch { return [pscustomobject]@{ Exit = -1; Out = $_.Exception.Message } }
    finally { $ErrorActionPreference = $prev }
}

try {
    if ([string]::IsNullOrEmpty($MemoryRoot)) {
        Write-Output 'COULD NOT VERIFY: -MemoryRoot is required (this gate does not know where your store is).'
        exit 2
    }
    if (-not (Test-Path -LiteralPath $MemoryRoot -PathType Container)) {
        Write-Output "COULD NOT VERIFY: memory root does not exist: $MemoryRoot"
        exit 2
    }
    $files = @(Get-ChildItem -LiteralPath $MemoryRoot -File -Filter '*.md' | Sort-Object Name)
    if ($files.Count -eq 0) {
        Write-Output "COULD NOT VERIFY: no .md under $MemoryRoot (an empty sweep is not a clean sweep)."
        exit 2
    }

    $tick = [string][char]96
    $spanRe = [regex]($tick + '\s*(source:[^' + $tick + [string][char]10 + ']{3,400})' + $tick)
    $declRe = [regex]'^source:\s*(?<p>.+?)\s+@\s*(?<c>[0-9a-fA-F]{7,64})$'
    $hasGit = $null -ne (Get-Command git -ErrorAction SilentlyContinue)

    $declared = 0
    $current = 0
    $unmeasurable = 0
    $findings = 0

    foreach ($f in $files) {
        try { $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction Stop } catch { continue }
        if ([string]::IsNullOrEmpty($text)) { continue }
        foreach ($m in $spanRe.Matches($text)) {
            $raw = $m.Groups[1].Value.Trim()
            # A declaration is 'source:' followed by an absolute or ~/ path. Any other use
            # of the word inside a code span is not this gate's business.
            if ($raw -notmatch '^source:\s*([A-Za-z]:\\|~[\\/])') { continue }
            $declared++
            $d = $declRe.Match($raw)
            if (-not $d.Success) {
                Write-Output ("FAIL  {0}: malformed source declaration (expected 'source: <path> @ <commit, 7 to 64 hex>'): {1}" -f $f.Name, $raw)
                $findings++
                continue
            }
            $target = $d.Groups['p'].Value.Trim()
            $sha = $d.Groups['c'].Value.ToLowerInvariant()
            $real = if ($target -match '^~') { Join-Path $env:USERPROFILE ($target.Substring(1).TrimStart('\', '/')) } else { $target }
            $real = $real.TrimEnd('\', '/')

            # Anchor on the nearest ancestor that EXISTS: a deleted source still has to be
            # measured (it is a change), and only the repository's git can say whether the
            # path existed at the commit.
            $dir = $real
            $rest = @()
            if (Test-Path -LiteralPath $real -PathType Leaf) {
                $dir = Split-Path -Parent $real
                $rest = @(Split-Path -Leaf $real)
            }
            else {
                while (-not [string]::IsNullOrEmpty($dir) -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
                    $rest = @(Split-Path -Leaf $dir) + $rest
                    $dir = Split-Path -Parent $dir
                }
            }
            $rel = if ($rest.Count -gt 0) { $rest -join '/' } else { '.' }

            $why = $null
            if (-not $hasGit) { $why = 'git is not on PATH' }
            elseif ([string]::IsNullOrEmpty($dir)) { $why = 'no ancestor of the path exists on this machine' }
            else {
                $g = Invoke-Git $dir @('rev-parse', '--is-inside-work-tree')
                if ($g.Exit -ne 0 -or $g.Out -notmatch 'true') {
                    $first = (($g.Out -split "`n")[0]).Trim()
                    $why = "no usable git repository at $dir ($first)"
                }
                else {
                    $g = Invoke-Git $dir @('cat-file', '-e', ($sha + '^{commit}'))
                    if ($g.Exit -ne 0) { $why = "commit $sha is unknown to this clone (not fetched, or it belongs to another repository)" }
                }
            }
            if ($why) {
                Write-Output ("WARN  {0}: source NOT MEASURABLE on this machine, not a finding: {1} -- {2}" -f $f.Name, $target, $why)
                $unmeasurable++
                continue
            }

            $obj = if ($rel -eq '.') { $sha + ':./' } else { $sha + ':./' + $rel }
            $g = Invoke-Git $dir @('cat-file', '-e', $obj)
            if ($g.Exit -ne 0) {
                Write-Output ("FAIL  {0}: declares a source that commit {1} does not contain: {2}" -f $f.Name, $sha, $target)
                $findings++
                continue
            }
            $g = Invoke-Git $dir @('diff', '--quiet', $sha, '--', $rel)
            if ($g.Exit -eq 0) { $current++; continue }
            if ($g.Exit -ne 1) {
                Write-Output ("WARN  {0}: source NOT MEASURABLE on this machine, not a finding: {1} -- git diff exited {2}" -f $f.Name, $target, $g.Exit)
                $unmeasurable++
                continue
            }
            $howFar = 'a change not yet committed, or on another branch'
            $n = Invoke-Git $dir @('rev-list', '--count', ($sha + '..HEAD'), '--', $rel)
            if ($n.Exit -eq 0 -and $n.Out -match '^\d+$' -and [int]$n.Out -gt 0) {
                $last = Invoke-Git $dir @('log', '-1', '--format=%h %ad', '--date=short', '--', $rel)
                $howFar = "{0} commit(s) later; the latest is {1}" -f $n.Out, $last.Out
            }
            Write-Output ("FAIL  {0}: checked against {1} at commit {2}, and the source has changed since ({3}). Check the memory and the published surface against the source, then rewrite the commit." -f $f.Name, $target, $sha, $howFar)
            $findings++
        }
    }

    Write-Output ("{0} memory file(s) | {1} source declaration(s): {2} current, {3} not measurable, {4} finding(s)" -f $files.Count, $declared, $current, $unmeasurable, $findings)
    if ($findings -gt 0) { exit 1 }
    if ($declared -eq 0) {
        Write-Output 'COULD NOT VERIFY: no source declaration in the store - nothing was measured (an empty sweep is not a clean sweep).'
        exit 2
    }
    if ($current -eq 0) {
        Write-Output 'COULD NOT VERIFY: not one declared source is measurable on this machine - nothing was measured.'
        exit 2
    }
    Write-Output 'OK  no measured source has changed since the commit its memory was checked against.'
    exit 0
}
catch {
    Write-Output "COULD NOT VERIFY: $($_.Exception.Message)"
    exit 2
}
