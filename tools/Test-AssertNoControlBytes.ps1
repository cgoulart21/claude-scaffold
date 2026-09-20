<#
  Test-AssertNoControlBytes.ps1

  Suite for automation/verification/Assert-NoControlBytes.ps1.

  The three exit states are asserted SEPARATELY, and no case trusts the exit code
  alone: each also demands evidence that only a successful run produces (the named
  target, the file:line, the word the gate prints). One extra assertion of that kind
  caught, in the practice this came from, a wrong relative path when the root arrived
  in 8.3 form - the exit was right and the finding named the wrong file.

  Hermetic: fixtures live under $env:TEMP and are removed. The last group runs the
  gate over THIS repository, which must be clean - the scaffold ships text, and text
  with a control byte in it is corruption shipped as a template.
#>
[CmdletBinding()]
param([string]$GatePath)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($GatePath)) {
    $GatePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'automation\verification\Assert-NoControlBytes.ps1'
}
$RepoRoot = Split-Path -Parent $PSScriptRoot
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

function New-Fixture {
    param([hashtable] $Files)
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('ctlbytes-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $null = $script:Temps.Add($dir)
    foreach ($name in $Files.Keys) {
        $full = Join-Path $dir $name
        $parent = Split-Path -Parent $full
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [IO.File]::WriteAllText($full, [string] $Files[$name], $Utf8NoBom)
    }
    return $dir
}

try {
    Assert-True 'the gate exists' (Test-Path -LiteralPath $GatePath -PathType Leaf) $GatePath
    if (-not (Test-Path -LiteralPath $GatePath -PathType Leaf)) { throw 'gate missing' }

    Write-Output 'Group 1 - state 0: a clean tree'
    $clean = New-Fixture @{ 'a.md' = "line one`nline two`n"; 'sub\b.ps1' = "# comment`n" }
    $r = Invoke-Gate @('-Root', $clean, '-NoKnownException')
    Assert-True 'clean tree exits 0' ($r.Exit -eq 0) "exit [$($r.Exit)]"
    Assert-True 'clean tree prints OK (evidence, not just exit)' ($r.Out -match 'OK\s+no control byte') $r.Out
    Assert-True 'clean tree says how many files it scanned' ($r.Out -match 'scanned 2 text file') $r.Out

    Write-Output 'Group 2 - state 1: each of the five bytes fails, and the finding names the target'
    foreach ($case in @(@{ Name = 'NUL'; Code = 0 }, @{ Name = 'BEL'; Code = 7 }, @{ Name = 'BS'; Code = 8 }, @{ Name = 'VT'; Code = 11 }, @{ Name = 'FF'; Code = 12 })) {
        $content = "first line`nsecond with " + [string][char]$case.Code + " here`n"
        $dirty = New-Fixture @{ 'dirty.md' = $content; 'ok.md' = "nothing`n" }
        $r = Invoke-Gate @('-Root', $dirty, '-NoKnownException')
        Assert-True ("byte {0} fails with exit 1" -f $case.Name) ($r.Exit -eq 1) "exit [$($r.Exit)]; $($r.Out)"
        Assert-True ("finding for {0} names dirty.md line 2" -f $case.Name) ($r.Out -match 'FAIL\s+dirty\.md:2') $r.Out
        Assert-True ("finding for {0} names the byte" -f $case.Name) ($r.Out -match [regex]::Escape($case.Name)) $r.Out
        Assert-True ("the clean neighbour is NOT accused ({0})" -f $case.Name) ($r.Out -notmatch 'FAIL\s+ok\.md') $r.Out
    }

    Write-Output 'Group 3 - TAB, LF and CR are legitimate'
    $tabs = New-Fixture @{ 'tab.md' = "col1`tcol2`r`nline`n" }
    $r = Invoke-Gate @('-Root', $tabs, '-NoKnownException')
    Assert-True 'TAB/CR/LF do not fail' ($r.Exit -eq 0) $r.Out

    Write-Output 'Group 4 - a declared exception'
    $exc = New-Fixture @{ 'dirty.md' = "x " + [string][char]7 + " y`n" }
    $r1 = Invoke-Gate @('-Root', $exc, '-KnownException', 'dirty.md')
    Assert-True 'a declared exception is exempt and exits 0' ($r1.Exit -eq 0) $r1.Out
    Assert-True 'the exemption shows in the summary' ($r1.Out -match '1 declared exception') $r1.Out
    $r2 = Invoke-Gate @('-Root', $exc, '-NoKnownException')
    Assert-True 'NoKnownException ignores the list and fails again' ($r2.Exit -eq 1) $r2.Out

    Write-Output 'Group 5 - excluded directories are not descended into'
    $ex = New-Fixture @{ 'ok.md' = "fine`n"; 'node_modules\x.md' = "bad " + [string][char]8 + "`n"; 'build\y.md' = "bad " + [string][char]7 + "`n" }
    $r = Invoke-Gate @('-Root', $ex, '-NoKnownException')
    Assert-True 'node_modules and build are skipped' ($r.Exit -eq 0 -and $r.Out -match 'scanned 1 text file') $r.Out

    Write-Output 'Group 6 - .template files are text and are scanned'
    $tpl = New-Fixture @{ 'CLAUDE.md.template' = "a " + [string][char]12 + " b`n" }
    $r = Invoke-Gate @('-Root', $tpl, '-NoKnownException')
    Assert-True 'a byte inside a .template is found' ($r.Exit -eq 1 -and $r.Out -match 'FAIL\s+CLAUDE\.md\.template:1') $r.Out

    Write-Output 'Group 7 - state 2: could not verify, never 1'
    $nowhere = Join-Path ([IO.Path]::GetTempPath()) ('nope-' + [guid]::NewGuid().ToString('N'))
    $r = Invoke-Gate @('-Root', $nowhere)
    Assert-True 'a missing root exits 2, not 1' ($r.Exit -eq 2) "exit [$($r.Exit)]"
    Assert-True 'a missing root says COULD NOT VERIFY' ($r.Out -match 'COULD NOT VERIFY') $r.Out
    $empty = New-Fixture @{ }
    $r = Invoke-Gate @('-Root', $empty)
    Assert-True 'a tree with no eligible file exits 2, not 0' ($r.Exit -eq 2) $r.Out

    Write-Output 'Group 8 - this repository is clean'
    $rr = Invoke-Gate @('-Root', $RepoRoot)
    Assert-True 'the scaffold tree exits 0' ($rr.Exit -eq 0) $rr.Out
    Assert-True 'and it scanned a plausible number of files (more than 40)' ($rr.Out -match 'scanned (\d+) text file' -and [int]$Matches[1] -gt 40) $rr.Out
}
finally {
    foreach ($d in $script:Temps) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
