<#
  Test-AssertErrataPropagation.ps1

  Suite for automation/verification/Assert-ErrataPropagation.ps1.

  Group 1 is the one that matters: prove the detector FIRES when a value marked as
  superseded on one page is still asserted, unmarked, on a sibling. A gate that never
  accuses stays green forever.

  Every other group is a defect the gate committed during its construction, turned into a
  regression case. There were seven, all of one family - "the detector measures what it
  knows how to extract and calls that coverage" - and without these cases the class comes
  back in silence, because missing coverage shows up as green, never as FAIL.

  Hermetic: no case reads a real corpus. The gate runs as a child process, the way a CI
  step invokes it, so the exit code is the real one.
#>
[CmdletBinding()]
param([string]$GatePath)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($GatePath)) {
    $GatePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'automation\verification\Assert-ErrataPropagation.ps1'
}
$script:Pass = 0
$script:Fail = 0
$script:Temps = New-Object 'System.Collections.ArrayList'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
# Built from the code point, never written literally or as an escape: see the header of
# the gate for why this file would otherwise stop testing what it claims to test.
$Nbsp = [string][char]0x00A0

function Invoke-Gate {
    param([string[]] $ScriptArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $global:LASTEXITCODE = $null
        $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $GatePath @ScriptArgs 2>&1 | Out-String)
        $code = $global:LASTEXITCODE
    } finally { $ErrorActionPreference = $prev }
    return [pscustomobject]@{ Exit = $code; Out = $out }
}

function Assert-True {
    param([string] $Name, [bool] $Condition, [string] $Detail)
    if ($Condition) { $script:Pass++; Write-Output "  PASS  $Name" }
    else { $script:Fail++; Write-Output "  FAIL  $Name"; if ($Detail) { Write-Output "          -> $Detail" } }
}

function New-Corpus {
    $d = Join-Path ([IO.Path]::GetTempPath()) ("errata-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    [void](New-Item -ItemType Directory -Path $d -Force)
    [void]$script:Temps.Add($d)
    return $d
}

function Set-Page {
    param([string] $Root, [string] $Rel, [string[]] $Lines, [switch] $Crlf)
    $p = Join-Path $Root $Rel
    $dir = Split-Path -Parent $p
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    $nl = if ($Crlf) { "`r`n" } else { "`n" }
    [IO.File]::WriteAllText($p, (($Lines -join $nl) + $nl), $Utf8NoBom)
}

# Filler so pages are not degenerate one-line cases.
$Filler = @('', 'Some surrounding prose that carries no measurement at all.', '')

try {
    Assert-True -Name 'the gate exists' -Condition (Test-Path -LiteralPath $GatePath -PathType Leaf)

    # ---------------- Group 1: it FIRES ----------------
    Write-Output ''
    Write-Output 'Group 1  the detector accuses an unmarked sibling'
    $c = New-Corpus
    Set-Page -Root $c -Rel 'notes/source.md' -Lines (@(
        '# Source', '',
        'The measured step was 7.68 units under the first method.', '',
        '> **[SUPERSEDED 2026-09-02]** the step is 7.55 units, not 7.68: the first method',
        '> used the wrong reference.', ''
    ) + $Filler)
    Set-Page -Root $c -Rel 'notes/sibling.md' -Lines (@(
        '# Sibling', '',
        'Downstream sizing assumes a step of 7.68 units.', ''
    ) + $Filler)
    $r = Invoke-Gate @('-Root', $c)
    Assert-True -Name 'an unmarked superseded value fails with exit 1' -Condition ($r.Exit -eq 1) -Detail $r.Out
    Assert-True -Name 'the finding names file:line of the SIBLING' `
        -Condition ($r.Out -match 'notes/sibling\.md:3') -Detail $r.Out
    Assert-True -Name 'the finding names the value' -Condition ($r.Out -match '7\.68') -Detail $r.Out
    Assert-True -Name 'the finding says WHERE the value is marked' `
        -Condition ($r.Out -match 'notes/source\.md:') -Detail $r.Out
    Assert-True -Name 'the passage the marker annotates is not accused' `
        -Condition ($r.Out -notmatch 'notes/source\.md:3 repeats') -Detail $r.Out
    Assert-True -Name 'the corrected value is never accused' `
        -Condition ($r.Out -notmatch '7\.55') -Detail $r.Out

    # ---------------- Group 2: it clears ----------------
    Write-Output ''
    Write-Output 'Group 2  a marked sibling is clean, and says so'
    Set-Page -Root $c -Rel 'notes/sibling.md' -Lines (@(
        '# Sibling', '',
        'Downstream sizing assumes a step of 7.68 units.', '',
        '> **[SUPERSEDED]** 7.68 was refuted; use 7.55.', ''
    ) + $Filler)
    $r2 = Invoke-Gate @('-Root', $c)
    Assert-True -Name 'a marked sibling exits 0' -Condition ($r2.Exit -eq 0) -Detail $r2.Out
    Assert-True -Name 'and prints OK (evidence, not just the exit code)' `
        -Condition ($r2.Out -match 'OK\s+no superseded value') -Detail $r2.Out

    # ---------------- Group 3: marker shapes ----------------
    Write-Output ''
    Write-Output 'Group 3  the shapes a marker actually takes'
    $c3 = New-Corpus
    Set-Page -Root $c3 -Rel 'a.md' -Lines (@(
        '# A', '',
        'The plateau sits at 11.80 units.', '',
        '> **[SUPERSEDED]** the plateau figure is wrong;',
        '> it is 11.22, not 11.80.', ''
    ) + $Filler)
    Set-Page -Root $c3 -Rel 'b.md' -Lines (@('# B', '', 'We size for a plateau of 11.80 units.', '') + $Filler)
    $r3 = Invoke-Gate @('-Root', $c3)
    Assert-True -Name 'a multi-line marker covers a value on its second line' `
        -Condition ($r3.Exit -eq 1 -and $r3.Out -match 'b\.md:3') -Detail $r3.Out

    $c4 = New-Corpus
    Set-Page -Root $c4 -Rel 'a.md' -Lines (@(
        '# A', '',
        'Recorded loss of 3.41 percent.', '',
        '- **Errata**: the loss is 3.02 percent,',
        '  superseding the 3.41 first written here.', ''
    ) + $Filler)
    Set-Page -Root $c4 -Rel 'b.md' -Lines (@('# B', '', 'Budget assumes 3.41 percent loss.', '') + $Filler)
    $r4 = Invoke-Gate @('-Root', $c4)
    Assert-True -Name 'a marker in a bullet with an indented continuation is recognised' `
        -Condition ($r4.Exit -eq 1 -and $r4.Out -match 'b\.md:3') -Detail $r4.Out
    # And the marker's OWN continuation line is not accused of repeating the value it
    # declares superseded. Making the identification pass follow the bullet introduced
    # exactly that false positive, and the assertion above - which only checks that the
    # sibling IS accused - was blind to it.
    Assert-True -Name 'and the continuation line of the marker itself is not accused' `
        -Condition ($r4.Out -notmatch 'a\.md:\d+ repeats') -Detail $r4.Out

    # ---------------- Group 4: the false negative that motivated the gate ----------------
    Write-Output ''
    Write-Output 'Group 4  a marker about claim A does not cover claim B beside it'
    $c5 = New-Corpus
    Set-Page -Root $c5 -Rel 'a.md' -Lines (@(
        '# A', '',
        'First quantity 4.41 units. Second quantity 9.03 units.', '',
        '> **[SUPERSEDED]** only the first quantity: 4.41 is now 4.62.', ''
    ) + $Filler)
    Set-Page -Root $c5 -Rel 'b.md' -Lines (@(
        '# B', '', 'Sizing uses 9.03 units for the second quantity.', ''
    ) + $Filler)
    $r5 = Invoke-Gate @('-Root', $c5)
    Assert-True -Name 'a scoped marker does NOT supersede the neighbouring value' `
        -Condition ($r5.Out -notmatch '9\.03') -Detail $r5.Out

    # ---------------- Group 5: the filters ----------------
    Write-Output ''
    Write-Output 'Group 5  the filters that stop plausible nonsense'
    # The marker quotes BOTH triples, which is what a real one does - and that is exactly
    # what makes 4.41 appear twice in the block and identifies it as the value that did
    # NOT move. A fixture quoting only the new triple does not exercise this rule at all;
    # the first version of this case did that and accused the gate of the defect it was
    # written to prevent.
    $c6 = New-Corpus
    Set-Page -Root $c6 -Rel 'a.md' -Lines (@(
        '# A', '',
        'Triple 4.41 / 7.68 / 11.80 measured in the first run.', '',
        '> **[SUPERSEDED]** the triple 4.41 / 7.68 / 11.80 is wrong;',
        '> it is 4.41 / 7.55 / 11.22 - only the last two moved.', ''
    ) + $Filler)
    Set-Page -Root $c6 -Rel 'b.md' -Lines (@('# B', '', 'Elsewhere 4.41 appears legitimately.', '') + $Filler)
    $r6 = Invoke-Gate @('-Root', $c6)
    Assert-True -Name 'a value quoted twice in the marker (unchanged) is not accused' `
        -Condition ($r6.Out -notmatch 'b\.md.*4\.41') -Detail $r6.Out

    $c7 = New-Corpus
    Set-Page -Root $c7 -Rel 'a.md' -Lines (@(
        '# A', '',
        'Written in 2026 during the 2026 review.', '',
        '> **[SUPERSEDED]** dated 2026; the figure 5.10 is now 5.40.', ''
    ) + $Filler)
    Set-Page -Root $c7 -Rel 'b.md' -Lines (@('# B', '', 'Also written in 2026.', '') + $Filler)
    $r7 = Invoke-Gate @('-Root', $c7)
    Assert-True -Name 'a year is not a measurement and raises no finding' `
        -Condition ($r7.Out -notmatch 'FAIL') -Detail $r7.Out

    $c8 = New-Corpus
    Set-Page -Root $c8 -Rel 'a.md' -Lines (@(
        '# A', '', 'Common reading 0.70 volts.', '',
        '> **[SUPERSEDED]** 0.70 is now 0.65.', ''
    ) + $Filler)
    foreach ($n in 1..8) {
        Set-Page -Root $c8 -Rel "spread$n.md" -Lines (@("# S$n", '', 'A drop of 0.70 volts here too.', '') + $Filler)
    }
    $r8 = Invoke-Gate @('-Root', $c8, '-MaxSpread', '6')
    Assert-True -Name 'a token in more files than MaxSpread is dropped, not accused' `
        -Condition ($r8.Exit -eq 0) -Detail $r8.Out
    Assert-True -Name 'and the drop is visible in the summary' `
        -Condition ($r8.Out -match 'dropped by spread') -Detail $r8.Out

    # ---------------- Group 6: append-only prose ----------------
    Write-Output ''
    Write-Output 'Group 6  a ledger quotes the old value on purpose'
    $c9 = New-Corpus
    Set-Page -Root $c9 -Rel 'a.md' -Lines (@(
        '# A', '', 'The figure is 8.31 units.', '',
        '> **[SUPERSEDED]** 8.31 is now 8.05.', ''
    ) + $Filler)
    Set-Page -Root $c9 -Rel 'meta/log.md' -Lines (@(
        '# Log', '', '- normalised the old 8.31 to the corrected figure.', ''
    ) + $Filler)
    $r9 = Invoke-Gate @('-Root', $c9)
    Assert-True -Name 'an occurrence in append-only prose does not fail' -Condition ($r9.Exit -eq 0) -Detail $r9.Out
    Assert-True -Name 'and is counted separately in the summary' `
        -Condition ($r9.Out -match 'append-only prose') -Detail $r9.Out
    $r9b = Invoke-Gate @('-Root', $c9, '-NoHistoricalProse')
    Assert-True -Name 'NoHistoricalProse makes the ledger fail again' -Condition ($r9b.Exit -eq 1) -Detail $r9b.Out

    # ---------------- Group 7: declared exceptions ----------------
    Write-Output ''
    Write-Output 'Group 7  an exception is by location, not by token'
    $c10 = New-Corpus
    Set-Page -Root $c10 -Rel 'a.md' -Lines (@(
        '# A', '', 'The figure is 6.22 units.', '',
        '> **[SUPERSEDED]** 6.22 is now 6.90.', ''
    ) + $Filler)
    Set-Page -Root $c10 -Rel 'excused.md' -Lines (@('# E', '', 'Unrelated quantity 6.22 amperes.', '') + $Filler)
    Set-Page -Root $c10 -Rel 'guilty.md' -Lines (@('# G', '', 'Sizing uses 6.22 units.', '') + $Filler)
    $r10 = Invoke-Gate @('-Root', $c10, '-Exception', 'excused.md:6.22')
    Assert-True -Name 'the excused location is silent' -Condition ($r10.Out -notmatch 'excused\.md') -Detail $r10.Out
    Assert-True -Name 'and the same token elsewhere is still accused' `
        -Condition ($r10.Exit -eq 1 -and $r10.Out -match 'guilty\.md') -Detail $r10.Out

    # TWO exceptions, the case that a one-exception suite never reaches. An array does not
    # survive the `powershell -File` binder - the second element arrives positional and the
    # gate dies before measuring - which is how the real corpus, with three declared
    # exceptions, broke while this suite stayed green.
    Set-Page -Root $c10 -Rel 'guilty.md' -Lines (@('# G', '', 'Sizing uses 6.22 units.', '') + $Filler)
    $r10b = Invoke-Gate @('-Root', $c10, '-Exception', 'excused.md:6.22;guilty.md:6.22')
    Assert-True -Name 'two exceptions in one semicolon-separated string both apply' `
        -Condition ($r10b.Exit -eq 0) -Detail $r10b.Out
    Assert-True -Name 'and the run measured rather than breaking' `
        -Condition ($r10b.Out -match 'superseded value\(s\) identified') -Detail $r10b.Out

    # ---------------- Group 8: the thin thousands separator ----------------
    Write-Output ''
    Write-Output 'Group 8  a thin thousands space does not hide a value'
    $c11 = New-Corpus
    Set-Page -Root $c11 -Rel 'a.md' -Lines (@(
        '# A', '', "Total of 2${Nbsp}958 units.", '',
        "> **[SUPERSEDED]** 2${Nbsp}958 is now 3${Nbsp}104.", ''
    ) + $Filler)
    Set-Page -Root $c11 -Rel 'b.md' -Lines (@('# B', '', 'Carried forward as 2958 units.', '') + $Filler)
    $r11 = Invoke-Gate @('-Root', $c11)
    Assert-True -Name 'a value with a thin thousands space is matched against its plain form' `
        -Condition ($r11.Exit -eq 1 -and $r11.Out -match 'b\.md:3') -Detail $r11.Out

    # ---------------- Group 9: CRLF ----------------
    Write-Output ''
    Write-Output 'Group 9  a corpus written with CRLF'
    $c12 = New-Corpus
    Set-Page -Crlf -Root $c12 -Rel 'a.md' -Lines (@(
        '# A', '', 'The figure is 5.55 units.', '',
        '> **[SUPERSEDED]** 5.55 is now 5.95.', ''
    ) + $Filler)
    Set-Page -Crlf -Root $c12 -Rel 'b.md' -Lines (@('# B', '', 'Sizing uses 5.55 units.', '') + $Filler)
    $r12 = Invoke-Gate @('-Root', $c12)
    Assert-True -Name 'CRLF line endings do not hide the finding' `
        -Condition ($r12.Exit -eq 1 -and $r12.Out -match 'b\.md:3') -Detail $r12.Out

    # ---------------- Group 10: the exit contract ----------------
    Write-Output ''
    Write-Output 'Group 10  could-not-verify is never 0 and never 1'
    $r13 = Invoke-Gate @()
    Assert-True -Name 'no -Root exits 2, not 0' -Condition ($r13.Exit -eq 2) -Detail $r13.Out
    $r14 = Invoke-Gate @('-Root', (Join-Path ([IO.Path]::GetTempPath()) 'no-such-tree-here'))
    Assert-True -Name 'a missing root exits 2, not 1' -Condition ($r14.Exit -eq 2) -Detail "exit [$($r14.Exit)]"
    $empty = New-Corpus
    $r15 = Invoke-Gate @('-Root', $empty)
    Assert-True -Name 'no .md exits 2, not 0 (an empty sweep is not a clean sweep)' `
        -Condition ($r15.Exit -eq 2) -Detail $r15.Out
    $c16 = New-Corpus
    Set-Page -Root $c16 -Rel 'a.md' -Lines (@('# A', '', 'A page with 1.23 and no marker at all.', '') + $Filler)
    $r16 = Invoke-Gate @('-Root', $c16)
    Assert-True -Name 'a corpus with no errata marker exits 2, not 0' -Condition ($r16.Exit -eq 2) -Detail $r16.Out
    Assert-True -Name 'and says COULD NOT VERIFY' -Condition ($r16.Out -match 'COULD NOT VERIFY') -Detail $r16.Out

    # The defect that made the gate exit 2 in the MIDDLE of a run, after printing findings:
    # a function returning an unrolled empty collection came back as $null, so .Contains()
    # threw on exactly the lines with no token - which are most lines.
    Write-Output ''
    Write-Output 'Group 11  many token-free lines: a finding, not a break'
    $c17 = New-Corpus
    $many = @('# A', '')
    foreach ($n in 1..60) { $many += "Line $n of prose with no numeric token whatsoever." }
    $many += @('', 'The figure is 9.44 units.', '', '> **[SUPERSEDED]** 9.44 is now 9.80.', '')
    Set-Page -Root $c17 -Rel 'a.md' -Lines $many
    $bLines = @('# B', '')
    foreach ($n in 1..60) { $bLines += "Another line $n with nothing numeric in it." }
    $bLines += @('', 'Sizing uses 9.44 units.', '')
    Set-Page -Root $c17 -Rel 'b.md' -Lines $bLines
    $r17 = Invoke-Gate @('-Root', $c17)
    Assert-True -Name 'exits 1 (finding), not 2 (break)' -Condition ($r17.Exit -eq 1) -Detail $r17.Out
    Assert-True -Name 'and does NOT print COULD NOT VERIFY alongside a finding' `
        -Condition ($r17.Out -notmatch 'COULD NOT VERIFY') -Detail $r17.Out

    # A break has to be a break, and has to say where. The message must not carry the
    # localised method-call wrapper: a test asserting on an English runtime word is green
    # for the wrong reason on a translated host, and red in CI. That happened once here.
    Write-Output ''
    Write-Output 'Group 12  an unreadable file breaks to 2, and names itself'
    $c18 = New-Corpus
    Set-Page -Root $c18 -Rel 'a.md' -Lines (@(
        '# A', '', 'The figure is 4.04 units.', '', '> **[SUPERSEDED]** 4.04 is now 4.40.', ''
    ) + $Filler)
    Set-Page -Root $c18 -Rel 'locked.md' -Lines @('# Locked', '', 'Sizing uses 4.04 units.', '')
    $stream = [IO.File]::Open((Join-Path $c18 'locked.md'), 'Open', 'Read', 'None')
    try {
        $r18 = Invoke-Gate @('-Root', $c18)
        Assert-True -Name 'an unreadable file is a warning, and the sweep still reports' `
            -Condition ($r18.Exit -ne 2 -or $r18.Out -match 'COULD NOT VERIFY') -Detail $r18.Out
        Assert-True -Name 'and no raw error record or localised wrapper leaks into the output' `
            -Condition ($r18.Out -notmatch 'FullyQualifiedErrorId') -Detail $r18.Out
    } finally { $stream.Dispose() }
}
finally {
    foreach ($d in $script:Temps) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
