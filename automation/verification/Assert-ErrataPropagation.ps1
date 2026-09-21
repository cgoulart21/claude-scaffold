<#
  Assert-ErrataPropagation.ps1

  Gate: a value marked as superseded in one place does not appear UNMARKED in another.

  WHY IT EXISTS. "Fix every published surface before the next task" is the rule with the
  longest tail, and in the practice this gate came from it failed three times in a row
  with nothing measuring it. The first failure created the rule. The second amended it
  with the pointer clause - record where you published, in the same turn - after a
  published page sat two weeks behind two errata the repository already had. The third
  showed that the pointer is only half the mechanism: the stale copies were sibling pages
  INSIDE the same repository, reachable by a plain text search since the day the
  correction was written. Nobody forgot they existed. Nobody looked.

  A pointer answers "which surfaces exist". It cannot answer "where else does the old
  value still appear". This gate is the second half: the sweep.

  WHAT IT MEASURES, AND WHY NOT THE OBVIOUS THING. Comparing values between pages is
  expensive and noisy: in the corpus this came from, a broad pass produced seventy false
  positives from a single class - supply rails, where 3.3 V, 5 V and 12 V legitimately
  coexist, so a unit alone does not identify a quantity - while a high-precision pass
  found nothing at all. What found the real defect was neither. It was looking for a
  claim already MARKED as superseded being asserted somewhere else WITHOUT the mark. When
  a corpus has errata discipline, the strongest signal is not disagreement between pages.
  It is the mark that did not propagate. Cheap, and precise.

  So: a marker ("[SUPERSEDED", "[CONTRADICTION", "errata", "refuted") annotates the
  passage next to it. A value counts as superseded when it appears in BOTH the marker
  block AND the annotated passage. That intersection is the precision filter - the
  CORRECTED value also appears in the marker, but not in the old passage, so it is never
  accused.

  THE RULE THIS GATE MUST NOT BREAK, because the manual sweep that produced it broke it:
  the marker has to CONTAIN the value, not merely sit near it. A three-line window once
  saw a marker about claim A and silenced a finding about claim B two lines below - a
  false negative that hid an entire stale surface. Scoped markers ("only the resonant
  frequencies", "only the absolute powers") exist precisely to avoid that, and the first
  detector committed the error those markers guard against.

  TWO FILTERS THAT ARE NOT OPTIONAL. Both were learned by the gate accusing nonsense.
    * A YEAR is not a measurement. Without that filter "2026" becomes a token and matches
      thousands of lines: the first run of this gate reported 1548 findings, nearly all
      dates. A plausible number, and useless.
    * A value that did NOT change appears TWICE in the marker block - once in the old
      triple, once in the new. Accusing it sprays noise over every place it legitimately
      appears. Occurrence count in the block is what separates the two.
  And a value genuinely superseded appears in few places, while a common number appears
  everywhere: the -MaxSpread cut separates them without knowing what any number means.

  APPEND-ONLY PROSE IS NOT A FINDING. A ledger (an operation log, an index) quotes the
  old value in order to record that it was corrected. Counting that is the sub-pattern
  "the scanner's scope is not the artifact's contract" from family 1. Those files are
  reported separately and never in the total.

  EXIT CONTRACT (three states):
    0  swept, and no superseded value appears unmarked
    1  a finding: file:line, the value, and who marked it
    2  could NOT sweep: root missing, no files, no marker at all (an empty sweep is not
       a clean sweep), or a break - no break path reaches 1

  PARAMETERS
    -Root            Tree to sweep. Required: this gate does not guess your corpus.
    -MarkerPattern   Regex for errata markers. The default covers the bracketed and the
                     bare forms; a corpus with another convention passes its own.
                     CASE IS DELIBERATE, and this regex is case-SENSITIVE (a [regex]
                     object is, unlike -match; the suite caught the port assuming
                     otherwise). The shouted forms stay upper-case because they are a
                     convention - SUPERSEDED, CONTRADICTION - while "contradiction" in
                     ordinary prose is not a marker and matching it would turn every
                     essay about disagreement into an errata block. The written forms
                     allow the sentence-initial capital, and nothing more: [Ee]rrata,
                     [Rr]efuted.
    -MinTokenLength  Shortest numeric token that counts as distinctive. Default 3: "7.68"
                     counts, "12" does not - a short number matches anywhere and yields
                     only noise.
    -MaxSpread       A token in more than this many files is not a distinctive value.
                     Default 6.
    -HistoricalProse Relative paths of append-only ledgers. Reported, never counted.
    -Exception       Declared exceptions, each "relative/path.md:token", several of them
                     separated by SEMICOLONS in one string (a comma is a decimal separator
                     inside the tokens, and an array does not survive `powershell -File`).
                     BY LOCATION, not by token: a short value can be ambiguous in one file
                     and be the real refuted quantity in another, so suppressing the token
                     globally would kill the true finding along with the noise.
    -Quiet           Findings and the count only.

  DECLARE EXCEPTIONS WITH A REASON, next to wherever you invoke this gate. An exception
  without a stated reason rots in silence, and this gate deliberately has no built-in
  list: the ones the originating practice needed were about its own corpus and would be
  meaningless - and silently wrong - in yours.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]   $Root,
    [string]   $MarkerPattern = '\[SUPERSEDED|\bSUPERSEDED\b|\[CONTRADICTION|\bCONTRADICTION\b|\[UPDATE|\b[Ee]rrata\b|\b[Rr]efuted\b',
    [int]      $MinTokenLength = 3,
    [int]      $MaxSpread = 6,
    [string[]] $HistoricalProse = @('meta/log.md', 'meta/index.md', 'wiki/meta/log.md', 'wiki/meta/index.md'),
    [string[]] $Exception = @(),
    [switch]   $NoHistoricalProse,
    [switch]   $Quiet
)

$ErrorActionPreference = 'Stop'

function Say([string] $m) { if (-not $Quiet) { Write-Output $m } }
function Fail([string] $m) { Write-Output ('FAIL  ' + $m) }

# Thin and non-breaking spaces are built HERE, from their code points, so this file stays
# ASCII. Writing them as literal characters, or as \u escapes in the source, has been lost
# twice to a transport layer that rewrites one or the other - and when the characters
# vanished from these classes the suite stayed green, because no fixture used a thousands
# separator. Broken behaviour, green suite.
$script:ThinSpaces = -join @([char]0x00A0, [char]0x202F, [char]0x2009)
$script:ThinClass = '[' + $script:ThinSpaces + ' ]'

try {
    if ([string]::IsNullOrEmpty($Root)) {
        Write-Output 'COULD NOT VERIFY: -Root is required (this gate does not know which tree is yours).'
        exit 2
    }
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        Write-Output "COULD NOT VERIFY: root does not exist: $Root"
        exit 2
    }
    $Root = (Get-Item -LiteralPath $Root).FullName

    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|_archive|node_modules|raw)[\\/]' })
    if ($files.Count -eq 0) {
        Write-Output "COULD NOT VERIFY: no .md file under $Root - an empty sweep is not a clean sweep"
        exit 2
    }

    # SPLIT ON SEMICOLON, and not only on the array boundary. An array does not survive
    # the `powershell -File` binder: every element after the first arrives as a positional
    # argument, and under PositionalBinding=$false the script dies before measuring
    # anything. CI invokes gates exactly that way, so the array form would have worked in
    # a suite that passes one exception and failed the first time a practice declared two.
    # Semicolon, not comma: a comma is a decimal separator inside these very tokens.
    $exceptions = @{}
    foreach ($e in $Exception) {
        if (-not $e) { continue }
        foreach ($one in ($e -split ';')) {
            $t = $one.Trim()
            if ($t) { $exceptions[$t] = $true }
        }
    }

    $markerRe = [regex] $MarkerPattern
    # A distinctive numeric token: digits with a separator, tolerating a thin thousands
    # space. Built by concatenation for the same reason the class above is.
    $tokenRe = [regex] ('\d[\d' + $script:ThinSpaces + ' ]*[.,]\d+|\d[\d' + $script:ThinSpaces + ']{2,}\d')

    $content = @{}
    foreach ($f in $files) {
        $rel = ($f.FullName.Substring($Root.Length).TrimStart('\', '/')) -replace '\\', '/'
        try {
            # ForEach-Object guarantees an array of STRING with no null element: an empty
            # file, or a null line, made .TrimStart() throw and the sweep exit 2 halfway
            # through. The contract held - it never exited 1 - but the findings were lost.
            $content[$rel] = @(Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction Stop |
                ForEach-Object { if ($null -eq $_) { '' } else { [string]$_ } })
        } catch {
            Say "WARN  $rel could not be read: $($_.Exception.Message)"
        }
    }

    function Get-Token([string] $Text) {
        $out = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($m in $tokenRe.Matches($Text)) {
            $t = ($m.Value -replace $script:ThinClass, '')
            if ($t.Length -lt $MinTokenLength) { continue }
            if ($t -match '^(19|20)\d{2}$') { continue }
            [void]$out.Add($t)
        }
        # THE COMMA IS NOT DECORATION. A PowerShell function that does "return $collection"
        # UNROLLS it into the pipeline: a HashSet with items comes back as an array (and
        # .Contains on an array happens to work), while an EMPTY HashSet comes back as
        # $null - so .Contains() throws only on the lines with no token, which are most of
        # them. The return TYPE changed with the CONTENT, silently.
        return , $out
    }

    function Test-Marked([string[]] $Lines, [int] $Idx, [string] $Token) {
        # A line is covered if it IS a marker, or if an adjacent block - above OR below -
        # carries a marker that CITES this token. Below matters: a common convention puts
        # the entry first and the scoped marker after it. And the requirement that the
        # marker cite the token is what prevents the false negative described in the
        # header: a marker about claim A does not cover claim B beside it.
        $n = @($Lines).Count
        if ($Idx -lt 0 -or $Idx -ge $n) { return $false }
        if ($markerRe.IsMatch([string]$Lines[$Idx])) { return $true }

        # MODEL: a scoped marker annotates the ADJACENT paragraph. So, from the line of the
        # finding: (1) leave the current paragraph, (2) skip blank lines, (3) accumulate
        # the marker block that follows - and ask the question of the BLOCK. Three earlier
        # versions each failed here differently: checking marker and token on the SAME line
        # (the marker is on the first line of the quote, the value on the second); walking
        # only through ">" (a marker can sit in a bullet with an indented continuation);
        # stopping inside the annotated paragraph, without skipping the blank line that
        # separates it from the marker. Each produced a false positive against marked text.
        function Get-NeighbourBlock([string[]] $L, [int] $From, [int] $Dir) {
            $acc = New-Object 'System.Collections.Generic.List[string]'
            $j = $From
            while ($j -ge 0 -and $j -lt $L.Count -and ([string]$L[$j]).Trim() -ne '') {
                $cur = [string] $L[$j]
                if ($cur.TrimStart() -match '^>') { $acc.Add($cur) }
                $j += $Dir
            }
            while ($j -ge 0 -and $j -lt $L.Count -and ([string]$L[$j]).Trim() -eq '') { $j += $Dir }
            $limit = 0
            while ($j -ge 0 -and $j -lt $L.Count -and $limit -lt 12) {
                $cur = [string] $L[$j]
                $isBlock = $cur.TrimStart() -match '^>' -or $cur -match '^\s{2,}\S' -or $cur -match '^\s*[-*]\s'
                if (-not $isBlock) { break }
                $acc.Add($cur)
                $j += $Dir
                $limit++
            }
            return , $acc
        }

        foreach ($dir in @(-1, 1)) {
            $block = Get-NeighbourBlock -L $Lines -From $Idx -Dir $dir
            if ($block.Count -eq 0) { continue }
            $text = ($block -join ' ')
            if ($markerRe.IsMatch($text) -and (Get-Token $text).Contains($Token)) { return $true }
        }
        return $false
    }

    # ---------- 1. find marker blocks and the values they annotate ----------
    # ONE definition of "marker block", used by both passes. Keeping two - an accumulator
    # here and a neighbour-walk in the coverage check - is what produced every defect in
    # this area: first the identification pass missed bullet markers that the coverage
    # pass understood, and then, once that was fixed, the marker's OWN continuation line
    # was accused of repeating the value it declares superseded. The line numbers that
    # belong to a marker block are recorded here and consulted there.
    $markerLines = @{}
    $superseded = @{}
    $blocks = 0
    foreach ($rel in ($content.Keys | Sort-Object)) {
        $script:current = $rel
        $ls = @($content[$rel] | Where-Object { $null -ne $_ })
        for ($i = 0; $i -lt $ls.Count; $i++) {
            if (-not $markerRe.IsMatch($ls[$i])) { continue }
            # The marker block runs to the end of the quote OR of the bullet. Following
            # only ">" was an ASYMMETRY that hid findings without ever failing: the
            # coverage check below already walked indented continuations, and this, the
            # identification path, did not. A marker written as a bullet whose value sits
            # on the continuation line therefore identified NOTHING - empty intersection,
            # zero superseded values, exit 0. The gate reported a clean sweep because it
            # had not looked. Found by a fixture, never by a corpus.
            $end = $i
            $bullet = $ls[$i].TrimStart() -match '^[-*]\s'
            while ($end + 1 -lt $ls.Count) {
                $next = [string] $ls[$end + 1]
                $continues = $next.TrimStart() -match '^>' -or ($bullet -and $next -match '^\s{2,}\S')
                if (-not $continues) { break }
                $end++
            }
            if (-not $markerLines.ContainsKey($rel)) {
                $markerLines[$rel] = New-Object 'System.Collections.Generic.HashSet[int]'
            }
            foreach ($k in $i..$end) { [void]$markerLines[$rel].Add($k) }
            $blockText = ($ls[$i..$end] -join ' ')

            # SKIP the blank lines between the marker and the paragraph before accumulating.
            # Without skipping, the layout "marker, blank line, paragraph" - the commonest
            # when the marker is its own blockquote - yielded an EMPTY passage, an empty
            # intersection, and no superseded value identified: the gate exited 0 for not
            # having measured. An asymmetry, since the coverage check already skipped blanks.
            $pStart = $end + 1
            while ($pStart -lt $ls.Count -and $ls[$pStart].Trim() -eq '') { $pStart++ }
            $pEnd = $pStart
            while ($pEnd -lt $ls.Count -and $pEnd -lt $pStart + 8 -and
                   $ls[$pEnd].Trim() -ne '' -and -not $markerRe.IsMatch($ls[$pEnd])) { $pEnd++ }
            $passage = if ($pEnd -gt $pStart) { ($ls[$pStart..($pEnd - 1)] -join ' ') } else { '' }

            # The marker may also annotate the passage ABOVE it.
            $aEnd = $i - 1
            while ($aEnd -ge 0 -and $ls[$aEnd].Trim() -eq '') { $aEnd-- }
            $aStart = $aEnd
            while ($aStart -ge 0 -and $ls[$aStart].Trim() -ne '' -and -not $markerRe.IsMatch($ls[$aStart])) { $aStart-- }
            $aStart++
            $above = if ($aEnd -ge 0 -and $aStart -le $aEnd) { ($ls[$aStart..$aEnd] -join ' ') } else { '' }

            $blockTokens = Get-Token $blockText
            if ($blockTokens.Count -eq 0) { continue }
            $blocks++
            foreach ($cand in (Get-Token ($passage + ' ' + $above))) {
                # INTERSECTION: the value has to be in the MARKER and in the annotated passage.
                if (-not $blockTokens.Contains($cand)) { continue }
                # AND IT HAS TO HAVE CHANGED: a value quoted twice in the block is the one
                # that stayed the same.
                $hits = ([regex]::Matches(($blockText -replace $script:ThinClass, ''),
                    [regex]::Escape($cand))).Count
                if ($hits -ge 2) { continue }
                if (-not $superseded.ContainsKey($cand)) {
                    $superseded[$cand] = New-Object 'System.Collections.Generic.HashSet[string]'
                }
                [void]$superseded[$cand].Add(("{0}:{1}" -f $rel, ($i + 1)))
            }
        }
    }

    if ($blocks -eq 0) {
        Write-Output "COULD NOT VERIFY: no errata marker found under $Root - nothing to propagate, and nothing measured"
        exit 2
    }

    # ---------- 1b. drop NON-DISTINCTIVE tokens by spread ----------
    $spread = @{}
    foreach ($tok in @($superseded.Keys)) {
        $n = 0
        foreach ($rel in $content.Keys) {
            if ((($content[$rel] -join ' ') -replace $script:ThinClass, '') -match [regex]::Escape($tok)) { $n++ }
        }
        $spread[$tok] = $n
    }
    $dropped = @($superseded.Keys | Where-Object { $spread[$_] -gt $MaxSpread })
    foreach ($tok in $dropped) { $superseded.Remove($tok) }

    # ---------- 2. does each superseded value appear unmarked elsewhere? ----------
    $ledgers = if ($NoHistoricalProse) { @() } else { @($HistoricalProse | Where-Object { $_ }) }
    $findings = 0
    $inLedger = 0
    foreach ($tok in ($superseded.Keys | Sort-Object)) {
        foreach ($rel in ($content.Keys | Sort-Object)) {
            if ($exceptions.ContainsKey("${rel}:${tok}")) { continue }
            $script:current = $rel
            $ls = @($content[$rel] | Where-Object { $null -ne $_ })
            for ($i = 0; $i -lt $ls.Count; $i++) {
                $norm = ($ls[$i] -replace $script:ThinClass, '')
                if ($norm -notmatch [regex]::Escape($tok)) { continue }
                # A line that IS part of a marker block declares the supersession; it does
                # not repeat it unmarked.
                if ($markerLines.ContainsKey($rel) -and $markerLines[$rel].Contains($i)) { continue }
                if (Test-Marked -Lines $ls -Idx $i -Token $tok) { continue }
                if ($ledgers -contains $rel) { $inLedger++; continue }
                Fail ("{0}:{1} repeats the superseded value {2} with no mark (marked in: {3})" -f
                    $rel, ($i + 1), $tok, (($superseded[$tok] | Sort-Object) -join ', '))
                $findings++
            }
        }
    }

    $summary = "{0} .md file(s) | {1} marker block(s) | {2} superseded value(s) identified" -f
        $content.Count, $blocks, $superseded.Count
    if ($dropped.Count -gt 0) { $summary += " | {0} dropped by spread (>{1} files)" -f $dropped.Count, $MaxSpread }
    if ($inLedger -gt 0) { $summary += " | $inLedger in append-only prose (not counted)" }
    Say $summary
    if ($findings -gt 0) {
        Write-Output "$findings occurrence(s) of a superseded value with no mark. Propagate the marker, do not rewrite the body."
        exit 1
    }
    Say 'OK  no superseded value appears unmarked.'
    exit 0
}
catch {
    # A break must never exit 1: 1 means "finding", and a caller reading only the code
    # cannot tell the two apart. "Could not verify" that does not say WHERE is nearly
    # useless to whoever fixes it, so the script line and the last file being read go in
    # the output. The message is the INNER exception's: PowerShell's method-call wrapper
    # is localised and hides the cause.
    $reason = $_.Exception.Message
    if ($null -ne $_.Exception.InnerException) { $reason = $_.Exception.InnerException.Message }
    $where = if ($script:current) { " (last file: $script:current)" } else { '' }
    $line = if ($_.InvocationInfo) { " [line $($_.InvocationInfo.ScriptLineNumber)]" } else { '' }
    Write-Output "COULD NOT VERIFY:$line $reason$where"
    exit 2
}
