<#
  Test-InvokeVaultLint.ps1

  Suite for automation/verification/Invoke-VaultLint.ps1.

  Hermetic: no case touches a real vault. The case that justifies the suite is the
  first one: a page with a `---` frontmatter AND `---` horizontal rules in the body.
  That is exactly where the improvised extractor failed - a regex over the whole
  document closing on the first rule in the body - producing a report of "11 stubs"
  against 0 real ones, and pages of 506 words counted as 53. If this case leaves the
  suite the class comes back, and missing coverage shows up as green.
#>
[CmdletBinding()]
param([string]$GatePath)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($GatePath)) {
    $GatePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'automation\verification\Invoke-VaultLint.ps1'
}
$script:Pass = 0
$script:Fail = 0
$script:Temps = New-Object 'System.Collections.ArrayList'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

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

function New-Vault {
    param([hashtable] $Pages)
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('vaultlint-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
    foreach ($name in $Pages.Keys) {
        $full = Join-Path $dir $name
        $parent = Split-Path -Parent $full
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [IO.File]::WriteAllText($full, [string] $Pages[$name], $Utf8NoBom)
    }
    $null = $script:Temps.Add($dir)
    return $dir
}

# A page with frontmatter and, in the body, horizontal rules - the exact shape that broke
# the improvised extractor. The body has 90+ words AFTER the rules.
function New-PageWithRules {
    param([string] $Title, [string[]] $Links = @())
    $ls = @('---', "title: `"$Title`"", 'type: concept', '---', '', "# $Title", '', 'A short opening line.', '', '---', '', '## Substantive section')
    for ($i = 1; $i -le 9; $i++) { $ls += ("Sentence number $i with exactly ten words to count correctly right here now.") }
    $ls += ''; $ls += '---'; $ls += ''
    foreach ($l in $Links) { $ls += "- see [[$l]]" }
    return ($ls -join "`n")
}

try {
    Assert-True 'the gate exists' (Test-Path -LiteralPath $GatePath -PathType Leaf) $GatePath
    if (-not (Test-Path -LiteralPath $GatePath -PathType Leaf)) { throw 'gate missing' }

    Write-Output 'Group 1 - REGRESSION: frontmatter plus rules in the body do not make a stub'
    $v = New-Vault @{
        'wiki/concepts/Full.md'  = (New-PageWithRules -Title 'Full')
        'wiki/concepts/Other.md' = (New-PageWithRules -Title 'Other' -Links @('Full'))
    }
    $r = Invoke-Gate @('-VaultRoot', $v, '-NoHistoricalProse')
    Assert-True 'a page with rules in the body is NOT a stub' ($r.Out -notmatch 'stub: Full') $r.Out
    Assert-True 'the stub total is zero' ($r.Out -match 'under 60 words: 0') $r.Out
    Assert-True 'the distribution shows a full body (min > 60)' ($r.Out -match 'min=(\d+)' -and [int]$Matches[1] -gt 60) $r.Out

    Write-Output 'Group 2 - a real stub fails, and is named'
    $v2 = New-Vault @{
        'wiki/concepts/Short.md' = "---`ntitle: `"Short`"`n---`n`n# Short`n`nJust this.`n"
        'wiki/concepts/Cites.md' = (New-PageWithRules -Title 'Cites' -Links @('Short'))
    }
    $r2 = Invoke-Gate @('-VaultRoot', $v2, '-NoHistoricalProse')
    Assert-True 'a real stub fails with exit 1' ($r2.Exit -eq 1) $r2.Out
    Assert-True 'the finding names the page and the count' ($r2.Out -match 'FAIL  stub: Short \(\d+ words') $r2.Out

    Write-Output 'Group 3 - orphan: a page nobody cites'
    $v3 = New-Vault @{
        'wiki/concepts/Alone.md' = (New-PageWithRules -Title 'Alone')
        'wiki/concepts/Cited.md' = (New-PageWithRules -Title 'Cited')
        'wiki/concepts/Cites.md' = (New-PageWithRules -Title 'Cites' -Links @('Cited'))
    }
    $r3 = Invoke-Gate @('-VaultRoot', $v3, '-NoHistoricalProse')
    Assert-True 'an orphan fails with exit 1' ($r3.Exit -eq 1) $r3.Out
    Assert-True 'the finding names the orphan' ($r3.Out -match 'orphan: Alone') $r3.Out
    Assert-True 'the cited page is NOT accused' ($r3.Out -notmatch 'orphan: Cited') $r3.Out

    Write-Output 'Group 4 - REGRESSION: a page referenced only through sources: is not an orphan'
    $vs = New-Vault @{
        'wiki/sources/2026-01-02-a-source.md' = (New-PageWithRules -Title 'A source')
        'wiki/concepts/Uses.md'  = "---`ntitle: Uses`nsources: [2026-01-02-a-source]`n---`n`n# Uses`n`n" + ('word ' * 80) + "`n"
        'wiki/concepts/CitesUses.md' = (New-PageWithRules -Title 'CitesUses' -Links @('Uses'))
        'wiki/concepts/Uses2.md' = "---`ntitle: Uses2`nsources: [2026-01-02-a-source]`n---`n`n# Uses2`n`n" + ('word ' * 80) + "`n- [[CitesUses]]`n"
    }
    $rs = Invoke-Gate @('-VaultRoot', $vs, '-NoHistoricalProse')
    Assert-True 'a source referenced by sources: is NOT an orphan' ($rs.Out -notmatch 'orphan: 2026-01-02-a-source') $rs.Out
    $vs2 = New-Vault @{
        'wiki/concepts/A.md' = "---`ntitle: A`nsources: [raw-file-that-is-not-a-page]`n---`n`n# A`n`n" + ('word ' * 80) + "`n- [[B]]`n"
        'wiki/concepts/B.md' = (New-PageWithRules -Title 'B' -Links @('A'))
    }
    $rs2 = Invoke-Gate @('-VaultRoot', $vs2, '-NoHistoricalProse')
    Assert-True 'a raw source in sources: does not become a dangling link' ($rs2.Out -match 'REAL DANGLING LINKS: 0' -and $rs2.Exit -eq 0) $rs2.Out

    Write-Output 'Group 5 - HISTORICAL PROSE: a target cited only by the log is not a finding'
    $v4 = New-Vault @{
        'wiki/concepts/Live.md'  = (New-PageWithRules -Title 'Live' -Links @('Cites'))
        'wiki/concepts/Cites.md' = (New-PageWithRules -Title 'Cites' -Links @('Live'))
        'wiki/meta/log.md'       = "# Log`n`n- normalised [[OldForm]] to [[Live]] on 4 pages`n"
    }
    $r4 = Invoke-Gate @('-VaultRoot', $v4)
    Assert-True 'a target cited only by the log is NOT a real dangling link' ($r4.Out -match 'REAL DANGLING LINKS: 0') $r4.Out
    Assert-True 'and it appears in the labelled historical section' ($r4.Out -match 'OldForm') $r4.Out
    Assert-True 'a log alone does not fail the run' ($r4.Exit -eq 0) $r4.Out
    Assert-True 'historical prose is not counted as a stub' ($r4.Out -notmatch 'stub: log') $r4.Out
    $r4b = Invoke-Gate @('-VaultRoot', $v4, '-NoHistoricalProse')
    Assert-True 'NoHistoricalProse makes the log target fail again' ($r4b.Exit -eq 1 -and $r4b.Out -match 'missing target: \[\[OldForm\]\]') $r4b.Out

    Write-Output 'Group 6 - a REAL dangling link from a normal page'
    $v5 = New-Vault @{
        'wiki/concepts/A.md' = (New-PageWithRules -Title 'A' -Links @('DoesNotExist'))
        'wiki/concepts/B.md' = (New-PageWithRules -Title 'B' -Links @('A'))
    }
    $r5 = Invoke-Gate @('-VaultRoot', $v5, '-NoHistoricalProse')
    Assert-True 'a real dangling link fails with exit 1' ($r5.Exit -eq 1) $r5.Out
    Assert-True 'the finding names target and citer' ($r5.Out -match 'missing target: \[\[DoesNotExist\]\]' -and $r5.Out -match 'wiki/concepts/A\.md') $r5.Out
    $v5b = New-Vault @{
        'wiki/concepts/A.md' = "---`ntitle: A`n---`n`n" + ('word ' * 80) + "`n`n- [[B|alias]] and [[B#section]]`n"
        'wiki/concepts/B.md' = (New-PageWithRules -Title 'B' -Links @('A'))
    }
    $r5c = Invoke-Gate @('-VaultRoot', $v5b, '-NoHistoricalProse')
    Assert-True 'alias [[B|x]] and anchor [[B#y]] resolve to B' ($r5c.Out -match 'REAL DANGLING LINKS: 0') $r5c.Out

    Write-Output 'Group 7 - promotion is a QUEUE, not a defect: it does not change the exit'
    $many = @{}
    $many['wiki/concepts/Thin.md'] = "---`ntitle: Thin`n---`n`n# Thin`n`n" + ('word ' * 70) + "`n"
    for ($i = 1; $i -le 9; $i++) { $many["wiki/concepts/Cite$i.md"] = (New-PageWithRules -Title "Cite$i" -Links @('Thin')) }
    $many['wiki/concepts/Hub.md'] = (New-PageWithRules -Title 'Hub' -Links @(1..9 | ForEach-Object { "Cite$_" }))
    $many['wiki/concepts/Cite1.md'] = (New-PageWithRules -Title 'Cite1' -Links @('Thin', 'Hub'))
    $r6 = Invoke-Gate @('-VaultRoot', (New-Vault $many), '-NoHistoricalProse')
    Assert-True 'a promotion candidate appears with citations and words' ($r6.Out -match 'Thin\s+\d+ citations,\s+\d+ words') $r6.Out
    Assert-True 'the section says it is a queue, not a defect' ($r6.Out -match 'work queue, not a defect') $r6.Out

    Write-Output 'Group 8 - watch metric: comparative claims WITHOUT a number'
    $vm = New-Vault @{
        'wiki/concepts/A.md' = "---`ntitle: A`n---`n`n# A`n`n" + ('word ' * 70) + "`n`nThe option on the left is better than the one on the right for this use case.`n`nThe top arrangement has 3.5 times more output than the bottom one.`n"
        'wiki/concepts/B.md' = (New-PageWithRules -Title 'B' -Links @('A')) + "`n`nThis approach is worse than the previous one, with no measurement at all.`n"
    }
    $rv = Invoke-Gate @('-VaultRoot', $vm, '-NoHistoricalProse')
    Assert-True 'the metric appears in the output' ($rv.Out -match 'COMPARATIVE CLAIMS WITHOUT A NUMBER') $rv.Out
    # two comparative sentences without a number (A and B); the third carries 3.5 and does not count
    Assert-True 'it counts EXACTLY the comparatives without a number (2), not zero' ($rv.Out -match 'COMPARATIVE CLAIMS WITHOUT A NUMBER: 2\b') $rv.Out
    Assert-True 'and the metric does NOT change the exit code' ($rv.Exit -in @(0, 1)) $rv.Out

    Write-Output 'Group 9 - state 2: could not verify, never 1'
    $nowhere = Join-Path ([IO.Path]::GetTempPath()) ('nope-' + [guid]::NewGuid().ToString('N'))
    $r7 = Invoke-Gate @('-VaultRoot', $nowhere)
    Assert-True 'a missing vault exits 2, not 1' ($r7.Exit -eq 2) "exit [$($r7.Exit)]"
    Assert-True 'and says COULD NOT VERIFY' ($r7.Out -match 'COULD NOT VERIFY') $r7.Out
    $r7b = Invoke-Gate @()
    Assert-True 'no -VaultRoot exits 2 and says it is required' ($r7b.Exit -eq 2 -and $r7b.Out -match 'required') $r7b.Out
    $noWiki = New-Vault @{ 'readme.md' = "no wiki folder`n" }
    $r8 = Invoke-Gate @('-VaultRoot', $noWiki)
    Assert-True 'a root without wiki/ exits 2, not 0' ($r8.Exit -eq 2) $r8.Out
    $emptyWiki = New-Vault @{ 'wiki/.keep' = "x`n" }
    $r9 = Invoke-Gate @('-VaultRoot', $emptyWiki)
    Assert-True 'wiki/ with no .md page exits 2, not 0' ($r9.Exit -eq 2) $r9.Out
}
finally {
    foreach ($d in $script:Temps) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
