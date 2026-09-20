<#
  Test-AssertMemoryLinks.ps1

  Suite for automation/verification/Assert-MemoryLinks.ps1.

  The case that matters most is Group 1: prove the detector FIRES on a broken link. A
  gate that never accuses stays green forever. Groups 4 and 5 cover the other half: the
  exception list has to die when it stops being true. Group 9 exists because the first
  version of the private suite did not cover alias and anchor syntax, and passed 17
  assertions over a gate that threw on [[target|alias]]. Missing coverage does not
  show up as FAIL; it shows up as green.

  Hermetic: no case reads a real memory store. The gate runs as a child process, the
  way a CI step invokes it, so the exit code is the real one.
#>
[CmdletBinding()]
param([string]$GatePath)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($GatePath)) {
    $GatePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'automation\verification\Assert-MemoryLinks.ps1'
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

function New-Fixture {
    param([hashtable] $Files)
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('memlinks-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
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

    Write-Output 'Group 1 - the detector FIRES on a broken link'
    $d = New-Fixture @{ 'a.md' = "line one`nsee [[ghost]] here`n"; 'b.md' = 'content' }
    $r = Invoke-Gate @('-MemoryRoot', $d, '-NoKnownDangling', '-NoExtraSource')
    Assert-True 'a broken link fails (exit 1)' ($r.Exit -eq 1) "exit [$($r.Exit)]"
    Assert-True 'the output names the dangling target' ($r.Out -match 'ghost') $r.Out
    Assert-True 'the output says WHERE (file:line)' ($r.Out -match 'a\.md:2') $r.Out

    Write-Output 'Group 2 - a clean set passes'
    $d = New-Fixture @{ 'a.md' = 'see [[b]] here'; 'b.md' = 'content' }
    $r = Invoke-Gate @('-MemoryRoot', $d, '-NoKnownDangling', '-NoExtraSource')
    Assert-True 'all links resolving passes (exit 0)' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'and prints OK' ($r.Out -match 'OK\s+every wikilink') $r.Out

    Write-Output 'Group 3 - a DECLARED dangling link passes'
    $d = New-Fixture @{ 'a.md' = 'see [[ghost]] here'; 'b.md' = 'content' }
    $r = Invoke-Gate @('-MemoryRoot', $d, '-KnownDangling', 'ghost', '-NoExtraSource')
    Assert-True 'a dangling link on the exception list passes (exit 0)' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"

    Write-Output 'Group 4 - a STALE exception fails (the target exists again)'
    $d = New-Fixture @{ 'a.md' = 'see [[b]] here'; 'b.md' = 'content' }
    $r = Invoke-Gate @('-MemoryRoot', $d, '-KnownDangling', 'b', '-NoExtraSource')
    Assert-True 'an exception that resolves again fails (exit 1)' ($r.Exit -eq 1) "exit [$($r.Exit)]"
    Assert-True 'the output says the exception is stale' ($r.Out -match 'stale') $r.Out

    Write-Output 'Group 5 - a DEAD exception fails (nobody cites it)'
    $d = New-Fixture @{ 'a.md' = 'see [[b]] here'; 'b.md' = 'content' }
    $r = Invoke-Gate @('-MemoryRoot', $d, '-KnownDangling', 'nobody-cites-this', '-NoExtraSource')
    Assert-True 'an uncited exception fails (exit 1)' ($r.Exit -eq 1) "exit [$($r.Exit)]"
    Assert-True 'the output says the exception is dead' ($r.Out -match 'dead') $r.Out

    Write-Output 'Group 6 - an empty sweep is NOT a clean sweep'
    $d = New-Fixture @{ 'readme.txt' = 'no markdown here' }
    $r = Invoke-Gate @('-MemoryRoot', $d, '-NoKnownDangling', '-NoExtraSource')
    Assert-True 'a root with no .md exits 2, not 0' ($r.Exit -eq 2) "exit [$($r.Exit)]; $($r.Out)"

    Write-Output 'Group 7 - state 2 for a missing or unset root'
    $missing = Join-Path ([IO.Path]::GetTempPath()) ('memlinks-missing-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $r = Invoke-Gate @('-MemoryRoot', $missing, '-NoKnownDangling', '-NoExtraSource')
    Assert-True 'a missing root exits 2' ($r.Exit -eq 2) "exit [$($r.Exit)]; $($r.Out)"
    $r = Invoke-Gate @('-NoKnownDangling', '-NoExtraSource')
    Assert-True 'no -MemoryRoot at all exits 2 and says it is required' ($r.Exit -eq 2 -and $r.Out -match 'required') $r.Out

    Write-Output 'Group 8 - scope: a subdirectory is NOT swept'
    $d = New-Fixture @{ 'a.md' = 'see [[b]] here'; 'b.md' = 'content'; 'archive\old.md' = 'see [[target-that-vanished]]' }
    $r = Invoke-Gate @('-MemoryRoot', $d, '-NoKnownDangling', '-NoExtraSource')
    Assert-True 'a broken link in a subdirectory is ignored (exit 0)' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'the subdirectory target is absent from the output' ($r.Out -notmatch 'target-that-vanished') $r.Out

    Write-Output 'Group 9 - Obsidian syntax: alias and anchor resolve to the target'
    foreach ($form in @(
        @{ Name = 'alias [[b|alias]]';         Text = 'see [[b|alias]] here' },
        @{ Name = 'anchor [[b#section]]';      Text = 'see [[b#section]] here' },
        @{ Name = 'anchor+alias [[b#s|al]]';   Text = 'see [[b#s|al]] here' },
        @{ Name = 'alias+anchor [[b|al#s]]';   Text = 'see [[b|al#s]] here' },
        @{ Name = 'spaces [[ b | al ]]';       Text = 'see [[ b | al ]] here' },
        @{ Name = 'embed ![[b]]';              Text = 'see ![[b]] here' }
    )) {
        $d = New-Fixture @{ 'a.md' = $form.Text; 'b.md' = 'content' }
        $r = Invoke-Gate @('-MemoryRoot', $d, '-NoKnownDangling', '-NoExtraSource')
        Assert-True ("{0} resolves to b (exit 0)" -f $form.Name) ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"
    }
    # A malformed target must become a FINDING, never an exception: an exception exits 1
    # and disguises itself as a finding to anyone reading only the exit code.
    $d = New-Fixture @{ 'a.md' = 'see [[sub/target]] here'; 'b.md' = 'content' }
    $r = Invoke-Gate @('-MemoryRoot', $d, '-NoKnownDangling', '-NoExtraSource')
    Assert-True 'a target with an invalid character fails (exit 1)' ($r.Exit -eq 1) "exit [$($r.Exit)]"
    Assert-True 'and fails as a readable FAIL, not a .NET exception' ($r.Out -match 'FAIL') $r.Out
    Assert-True 'the output carries no Test-Path exception' ($r.Out -notmatch 'Test-Path') $r.Out
    $d = New-Fixture @{ 'a.md' = 'see [[ghost|pretty alias]] here'; 'b.md' = 'content' }
    $r = Invoke-Gate @('-MemoryRoot', $d, '-NoKnownDangling', '-NoExtraSource')
    Assert-True 'a dangling link with an alias shows the link AS WRITTEN' ($r.Out -match 'pretty alias') $r.Out

    Write-Output 'Group 10 - extra sources: an incoming link from outside the store'
    $d       = New-Fixture @{ 'b.md' = 'content' }
    $outside = New-Fixture @{ 'OUTSIDE.md' = 'the doc cites [[ghost]]' }
    $r = Invoke-Gate @('-MemoryRoot', $d, '-NoKnownDangling', '-NoExtraSource')
    Assert-True 'without -ExtraSource the outside file is ignored (exit 0)' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"
    $r = Invoke-Gate @('-MemoryRoot', $d, '-NoKnownDangling', '-ExtraSource', (Join-Path $outside 'OUTSIDE.md'))
    Assert-True 'with -ExtraSource the outside dangling link fails (exit 1)' ($r.Exit -eq 1) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'the output names the outside file' ($r.Out -match 'OUTSIDE\.md') $r.Out
    $r = Invoke-Gate @('-MemoryRoot', $d, '-NoKnownDangling', '-ExtraSource', (Join-Path $outside 'DOES-NOT-EXIST.md'))
    Assert-True 'a missing extra is ignored, not an error (exit 0)' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"
}
finally {
    foreach ($d in $script:Temps) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
