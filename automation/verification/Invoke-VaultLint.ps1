<#
  Invoke-VaultLint.ps1

  Gate: the mechanical half of the vault's Lint operation - orphans, stubs, dangling
  links, and the promotion queue. The judgement half (contradictions, stale claims)
  stays with the agent; this script measures what can be measured and says so.

  WHY IT EXISTS. The Lint operation is defined in the vault's instruction file and was
  being improvised at every weekly routine - a new extractor each week, none under
  test. One such improvisation produced a FALSE report: it isolated page bodies with a
  regex over the whole document (`^---.*?^---` with the dot matching newlines), and
  the non-greedy match closed on the first HORIZONTAL RULE in the body, not the end of
  the frontmatter. Every page lost its most substantive section before being counted.
  The report said "11 stubs" and "the most-cited pages are the thinnest", with a
  ranking; the truth was 0 stubs and the exact inverse. The recommended action was to
  rewrite seven pages that needed nothing.

  The measurement RAN and produced plausible numbers - which is why repetition did not
  catch it: repeating called the same extractor. Internal consistency does not prove a
  correct binding (lesson family 3).

  TWO DESIGN DECISIONS, each from a measured error:

  1. Frontmatter is cut BY LINE (first line `---`, next line `---`, body is the rest).
     No regex crosses a line boundary.
  2. An append-only file of HISTORICAL PROSE (the vault's operations log) is not a
     source of dangling links: it CITES old link forms to record that they were already
     fixed. Counting that as a defect is the "a gate is worth what it enumerates"
     sub-pattern of family 1. Targets cited only by such files go in a separate,
     labelled section, never in the finding total.
  3. `sources:` in the frontmatter counts as an incoming citation. The first version
     counted only [[...]] in bodies and declared ORPHAN a source page that twelve pages
     referenced through frontmatter. Checked against the corpus before fixing.

  EXIT CONTRACT (three states):
    0  measured, nothing above threshold
    1  measured and FOUND (orphan, stub, or real dangling link)
    2  could NOT measure (vault missing, no wiki/, no page)
  Promotion candidates do NOT fail: they are a work queue, not a defect.
  No break path reaches 1.

  PARAMETERS
    -VaultRoot          Required. The vault root (the folder holding wiki/).
    -StubWords          Stub threshold in body words. Default 60.
    -PromoteCitations   Minimum incoming citations for a promotion candidate. Default 8.
    -PromoteWords       Maximum body for a promotion candidate. Default 200.
    -HistoricalProse    Relative paths (forward slashes) treated as append-only history:
                        not a dangling-link source, not a citing page, not a stub.
                        Default: wiki/meta/log.md and wiki/meta/index.md.
    -NoHistoricalProse  Ignore that list; for hermetic fixtures.
#>
[CmdletBinding()]
param(
    [string]   $VaultRoot,
    [int]      $StubWords = 60,
    [int]      $PromoteCitations = 8,
    [int]      $PromoteWords = 200,
    [string[]] $HistoricalProse = @('wiki/meta/log.md', 'wiki/meta/index.md'),
    [switch]   $NoHistoricalProse
)

$ErrorActionPreference = 'Stop'

function Get-Body {
    # Frontmatter cut BY LINE. The failure this gate replaces did it with a regex over
    # the whole document; here no expression crosses a line.
    param([string[]] $Lines)
    if ($Lines.Count -gt 0 -and $Lines[0].Trim() -eq '---') {
        for ($i = 1; $i -lt $Lines.Count; $i++) {
            if ($Lines[$i].Trim() -eq '---') {
                if ($i + 1 -ge $Lines.Count) { return @() }
                return $Lines[($i + 1)..($Lines.Count - 1)]
            }
        }
    }
    return $Lines
}

function Measure-Words {
    param([string[]] $Lines)
    if (-not $Lines -or $Lines.Count -eq 0) { return 0 }
    return @(($Lines -join ' ') -split '\s+' | Where-Object { $_ -ne '' }).Count
}

function Get-FrontmatterSources {
    param([string[]] $Lines)
    if (-not $Lines -or $Lines.Count -eq 0 -or $Lines[0].Trim() -ne '---') { return @() }
    $out = @()
    for ($i = 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -eq '---') { break }
        $m = [regex]::Match($Lines[$i], '^\s*sources:\s*\[(.*)\]\s*$')
        if ($m.Success) {
            foreach ($item in ($m.Groups[1].Value -split ',')) {
                $t = $item.Trim().Trim('"', "'")
                if ($t) { $out += $t }
            }
        }
    }
    return $out
}

try {
    if ([string]::IsNullOrEmpty($VaultRoot)) {
        Write-Output 'COULD NOT VERIFY: -VaultRoot is required (this gate does not know where your vault is).'
        exit 2
    }
    if (-not (Test-Path -LiteralPath $VaultRoot -PathType Container)) {
        Write-Output "COULD NOT VERIFY: vault does not exist: $VaultRoot"
        exit 2
    }
    $VaultRoot = (Get-Item -LiteralPath $VaultRoot).FullName
    $wiki = Join-Path $VaultRoot 'wiki'
    if (-not (Test-Path -LiteralPath $wiki -PathType Container)) {
        Write-Output "COULD NOT VERIFY: no wiki/ folder under $VaultRoot"
        exit 2
    }

    $files = @(Get-ChildItem -LiteralPath $wiki -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|\.obsidian|node_modules)[\\/]' })
    if ($files.Count -eq 0) {
        Write-Output "COULD NOT VERIFY: no .md page under $wiki"
        exit 2
    }

    $historical = if ($NoHistoricalProse) { @() } else { @($HistoricalProse | Where-Object { $_ }) }

    $rel = @{}; $words = @{}; $linesOf = @{}
    foreach ($f in $files) {
        $name = [IO.Path]::GetFileNameWithoutExtension($f.Name)
        $r = ($f.FullName.Substring($VaultRoot.Length).TrimStart('\', '/')) -replace '\\', '/'
        try { $l = @(Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction Stop) } catch {
            Write-Output "WARNING  $r could not be read: $($_.Exception.Message)"
            continue
        }
        $rel[$name] = $r; $linesOf[$name] = $l; $words[$name] = Measure-Words (Get-Body $l)
    }

    $incoming = @{}; $onlyHistorical = @{}; $dangling = @{}
    $linkRe = [regex]'\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]'
    foreach ($name in $rel.Keys) {
        $isHistorical = $historical -contains $rel[$name]
        if (-not $isHistorical) {
            foreach ($src in (Get-FrontmatterSources $linesOf[$name])) {
                if ($src -eq $name) { continue }
                if ($rel.ContainsKey($src)) {
                    if (-not $incoming.ContainsKey($src)) { $incoming[$src] = New-Object 'System.Collections.Generic.HashSet[string]' }
                    [void]$incoming[$src].Add($name)
                }
                # A declared source that is not a page is NOT a dangling link: `sources:` also
                # names raw material that never became a page.
            }
        }
        foreach ($m in $linkRe.Matches(($linesOf[$name] -join "`n"))) {
            $target = $m.Groups[1].Value.Trim()
            if ($target -eq $name) { continue }
            if ($rel.ContainsKey($target)) {
                if (-not $isHistorical) {
                    if (-not $incoming.ContainsKey($target)) { $incoming[$target] = New-Object 'System.Collections.Generic.HashSet[string]' }
                    [void]$incoming[$target].Add($name)
                }
            } elseif ($isHistorical) {
                if (-not $onlyHistorical.ContainsKey($target)) { $onlyHistorical[$target] = New-Object 'System.Collections.Generic.HashSet[string]' }
                [void]$onlyHistorical[$target].Add($rel[$name])
            } else {
                if (-not $dangling.ContainsKey($target)) { $dangling[$target] = New-Object 'System.Collections.Generic.HashSet[string]' }
                [void]$dangling[$target].Add($rel[$name])
            }
        }
    }

    Write-Output ("VAULT LINT  {0}  --  {1} page(s)" -f $VaultRoot, $rel.Count)
    Write-Output ''

    # Distribution first: "thin" only means something against the corpus.
    $vals = @($words.Values | Sort-Object)
    function Pct([int] $p) { return $vals[[Math]::Min($vals.Count - 1, [int][Math]::Floor($vals.Count * $p / 100))] }
    Write-Output ("BODY DISTRIBUTION (words): min={0}  p25={1}  median={2}  p75={3}  max={4}" -f $vals[0], (Pct 25), (Pct 50), (Pct 75), $vals[-1])

    $findings = 0

    $orphans = @($rel.Keys | Where-Object {
            -not ($incoming.ContainsKey($_) -and $incoming[$_].Count -gt 0) -and -not ($historical -contains $rel[$_])
        } | Sort-Object)
    Write-Output ''
    Write-Output ("ORPHANS -- no non-historical page cites them: {0}" -f $orphans.Count)
    foreach ($n in $orphans) { Write-Output ("  FAIL  orphan: {0} ({1}, {2} words)" -f $n, $rel[$n], $words[$n]); $findings++ }

    # Historical prose leaves this check too, for the same reason it leaves the others:
    # it is a ledger, not a page. Exclude it from all three checks or the gate is worth
    # what it enumerates inside itself.
    $stubs = @($rel.Keys | Where-Object { $words[$_] -lt $StubWords -and -not ($historical -contains $rel[$_]) } | Sort-Object { $words[$_] })
    Write-Output ''
    Write-Output ("STUBS -- body under {0} words: {1}" -f $StubWords, $stubs.Count)
    foreach ($n in $stubs) { Write-Output ("  FAIL  stub: {0} ({1} words, {2})" -f $n, $words[$n], $rel[$n]); $findings++ }

    Write-Output ''
    Write-Output ("REAL DANGLING LINKS: {0} target(s)" -f $dangling.Count)
    foreach ($t in ($dangling.Keys | Sort-Object)) {
        Write-Output ("  FAIL  missing target: [[{0}]]  cited by: {1}" -f $t, (($dangling[$t] | Sort-Object) -join ', '))
        $findings++
    }

    if ($onlyHistorical.Count -gt 0) {
        Write-Output ''
        Write-Output ("CITED ONLY BY HISTORICAL PROSE -- not a finding: {0} target(s)" -f $onlyHistorical.Count)
        Write-Output '  (an append-only file cites the OLD form of a link to record that it was fixed;'
        Write-Output '   counting that as a defect is the "gate is worth what it enumerates" sub-pattern)'
        foreach ($t in ($onlyHistorical.Keys | Sort-Object)) {
            Write-Output ("    [[{0}]]  in: {1}" -f $t, (($onlyHistorical[$t] | Sort-Object) -join ', '))
        }
    }

    # Watch metric, not a gate: comparative claims with no number in the sentence. A
    # claim WITH a number can be checked by an erratum-propagation gate; one without can
    # only be read. While this count fits a manual reading (a few dozen), reading is
    # cheaper than building a semantic detector for a class with no observed instance.
    # Variable names are contract: the first version of this block iterated a variable
    # that did not exist, and foreach over $null does not iterate - the metric reported
    # 0 in silence, forever. A watch metric stuck at zero never trips the threshold that
    # justifies it, which is worse than not having one.
    $compRe = [regex] '(?i)\b(better|worse|superior|inferior|outperform|beats|dominates|prefer|preferred|optimal|ideal|recommended|discarded|chosen|more \w+ than|less \w+ than|melhor|pior|supera|domina|otim[oa]|recomendad|descartad|escolhid|mais \w+ que|menos \w+ que)\b'
    $numRe  = [regex] '\d[\d.,]*'
    $noNumber = 0
    foreach ($name in $rel.Keys) {
        if ($historical -contains $rel[$name]) { continue }
        foreach ($sentence in (($linesOf[$name] -join "`n") -split '(?<=[.!?])\s+|\n(?=[-*#|>])')) {
            $s = $sentence.Trim()
            if ($s.Length -lt 25) { continue }
            if ($compRe.IsMatch($s) -and -not $numRe.IsMatch($s)) { $noNumber++ }
        }
    }
    Write-Output ''
    Write-Output ("COMPARATIVE CLAIMS WITHOUT A NUMBER: {0}  (watch metric, not a finding -- above a few dozen, manual reading stops being cheap)" -f $noNumber)

    $promo = @($incoming.Keys | Where-Object { $incoming[$_].Count -ge $PromoteCitations -and $words[$_] -lt $PromoteWords } | Sort-Object { - $incoming[$_].Count })
    Write-Output ''
    Write-Output ("PROMOTION CANDIDATES -- {0}+ citations and body under {1} words: {2}" -f $PromoteCitations, $PromoteWords, $promo.Count)
    Write-Output '  (work queue, not a defect: they do not change the exit code)'
    foreach ($n in $promo) { Write-Output ("    {0,-40} {1,3} citations, {2,4} words  {3}" -f $n, $incoming[$n].Count, $words[$n], $rel[$n]) }

    Write-Output ''
    if ($findings -gt 0) {
        Write-Output ("{0} finding(s): orphan, stub or real dangling link." -f $findings)
        exit 1
    }
    Write-Output 'OK  no orphan, no stub, no real dangling link.'
    exit 0
}
catch {
    Write-Output "COULD NOT VERIFY: $($_.Exception.Message)"
    exit 2
}
