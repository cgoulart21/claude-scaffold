<#
  Test-AssertPlanFreshness.ps1

  Suite for automation/verification/Assert-PlanFreshness.ps1.

  Hermetic: a projects root is built under $env:TEMP with one PLAN.md per case. The
  Base-ancestry group builds a real git repository with two branches, because a
  fixture that merely wrote a SHA into a file would prove the regex and nothing about
  ancestry - the same fixture-models-the-script trap that let a destructive junction
  script pass thirteen assertions. If git is not on PATH that group is SKIPPED and
  says so; skipped and passed are different facts.
#>
[CmdletBinding()]
param([string]$GatePath)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($GatePath)) {
    $GatePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'automation\verification\Assert-PlanFreshness.ps1'
}
$script:Pass = 0
$script:Fail = 0
$script:Skip = 0
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

function New-Root {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('plans-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $null = $script:Temps.Add($dir)
    return $dir
}

function Add-Plan {
    param([string] $Root, [string] $Project, [string] $Checkpoint)
    $dir = Join-Path $Root $Project
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $text = "# $Project`n`n## Done`n- x`n`n## Next`n- y`n`n## Checkpoint`n`n" + $Checkpoint + "`n"
    [IO.File]::WriteAllText((Join-Path $dir 'PLAN.md'), $text, $Utf8NoBom)
    return $dir
}

$fresh = (Get-Date).AddDays(-3).ToString('yyyy-MM-dd')
$old   = (Get-Date).AddDays(-20).ToString('yyyy-MM-dd')

try {
    Assert-True 'the gate exists' (Test-Path -LiteralPath $GatePath -PathType Leaf) $GatePath
    if (-not (Test-Path -LiteralPath $GatePath -PathType Leaf)) { throw 'gate missing' }

    Write-Output 'Group 1 - state 0: conformant and fresh, in all three formats'
    $root = New-Root
    Add-Plan $root 'own-line'  "Status: active`nUpdated: $fresh`nBase: abc1234" | Out-Null
    Add-Plan $root 'list-item' "- Status: paused`n- Updated: $old`n- Base: abc1234" | Out-Null
    Add-Plan $root 'one-line'  ("Status: complete " + [char]0x00B7 + " Updated: $old " + [char]0x00B7 + " Base: abc1234") | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'no-plan-here') -Force | Out-Null
    $r = Invoke-Gate @('-Root', $root)
    Assert-True 'three formats, all conformant: exit 0' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'prints OK' ($r.Out -match 'OK\s+every plan') $r.Out
    Assert-True 'counts 3 plans and ignores the directory without one' ($r.Out -match 'plans: 3 \|') $r.Out
    Assert-True 'an OLD paused plan is not stale' ($r.Out -notmatch 'list-item') $r.Out

    Write-Output 'Group 2 - state 1: an active plan past the age threshold'
    $root = New-Root
    Add-Plan $root 'went-quiet' "Status: active`nUpdated: $old`nBase: abc1234" | Out-Null
    $r = Invoke-Gate @('-Root', $root)
    Assert-True 'stale by age exits 1' ($r.Exit -eq 1) "exit [$($r.Exit)]"
    Assert-True 'the finding names the project and the age' ($r.Out -match 'FAIL\s+went-quiet\s+Updated ' + [regex]::Escape($old) + ', \d+ day\(s\) ago') $r.Out
    Assert-True 'the finding states the FACT about mtime vs Updated, not a cause' ($r.Out -match 'check whether the plan moved or only the field did') $r.Out
    $r = Invoke-Gate @('-Root', $root, '-MaxAgeDays', '60')
    Assert-True 'a wider threshold makes the same plan fresh (exit 0)' ($r.Exit -eq 0) $r.Out

    Write-Output 'Group 3 - state 1: missing Checkpoint fields'
    $root = New-Root
    Add-Plan $root 'no-fields'  "just prose, no checkpoint" | Out-Null
    Add-Plan $root 'no-updated' "Status: active`nBase: abc1234" | Out-Null
    $r = Invoke-Gate @('-Root', $root)
    Assert-True 'non-conformant plans exit 1' ($r.Exit -eq 1) $r.Out
    Assert-True 'the finding lists which fields are missing' ($r.Out -match 'no-fields\s+missing: Status\+Updated\+Base') $r.Out
    Assert-True 'a plan missing only Updated says so' ($r.Out -match 'no-updated\s+missing: Updated\s') $r.Out
    Assert-True 'the template line about a human act is printed' ($r.Out -match 'human act') $r.Out

    Write-Output 'Group 4 - state 2: could not verify, never 1'
    $nowhere = Join-Path ([IO.Path]::GetTempPath()) ('nope-' + [guid]::NewGuid().ToString('N'))
    $r = Invoke-Gate @('-Root', $nowhere)
    Assert-True 'a missing root exits 2' ($r.Exit -eq 2) "exit [$($r.Exit)]"
    $r = Invoke-Gate @()
    Assert-True 'no -Root exits 2 and says it is required' ($r.Exit -eq 2 -and $r.Out -match 'required') $r.Out
    $root = New-Root
    New-Item -ItemType Directory -Path (Join-Path $root 'empty-project') -Force | Out-Null
    $r = Invoke-Gate @('-Root', $root)
    Assert-True 'a root with no PLAN.md at all exits 2, not 0' ($r.Exit -eq 2 -and $r.Out -match 'no PLAN\.md') $r.Out

    Write-Output 'Group 5 - Base ancestry, against a real repository'
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) {
        $script:Skip++
        Write-Output '  SKIP  git not on PATH: ancestry cases not exercised (skipped is not passed)'
    } else {
        $root = New-Root
        $repo = Join-Path $root 'repo-plan'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $git.Source -C $repo init -q -b main 2>&1 | Out-Null
            & $git.Source -C $repo config user.email 'suite@example.com' 2>&1 | Out-Null
            & $git.Source -C $repo config user.name 'suite' 2>&1 | Out-Null
            [IO.File]::WriteAllText((Join-Path $repo 'a.txt'), "a`n", $Utf8NoBom)
            & $git.Source -C $repo add -A 2>&1 | Out-Null
            & $git.Source -C $repo commit -q -m 'first' 2>&1 | Out-Null
            $first = (& $git.Source -C $repo rev-parse HEAD 2>&1 | Out-String).Trim()
            [IO.File]::WriteAllText((Join-Path $repo 'b.txt'), "b`n", $Utf8NoBom)
            & $git.Source -C $repo add -A 2>&1 | Out-Null
            & $git.Source -C $repo commit -q -m 'second' 2>&1 | Out-Null
            $second = (& $git.Source -C $repo rev-parse HEAD 2>&1 | Out-String).Trim()
            # An orphan branch: its commit is real in this repo but NOT an ancestor of main.
            & $git.Source -C $repo checkout -q --orphan elsewhere 2>&1 | Out-Null
            [IO.File]::WriteAllText((Join-Path $repo 'c.txt'), "c`n", $Utf8NoBom)
            & $git.Source -C $repo add -A 2>&1 | Out-Null
            & $git.Source -C $repo commit -q -m 'elsewhere' 2>&1 | Out-Null
            $orphan = (& $git.Source -C $repo rev-parse HEAD 2>&1 | Out-String).Trim()
            & $git.Source -C $repo checkout -q main 2>&1 | Out-Null
        } finally { $ErrorActionPreference = $prev }

        $plan = Join-Path $repo 'PLAN.md'
        function Set-Checkpoint([string] $Base) {
            [IO.File]::WriteAllText($plan, "# repo-plan`n`n## Checkpoint`n`nStatus: active`nUpdated: $fresh`nBase: $Base`n", $Utf8NoBom)
        }
        Set-Checkpoint $first
        $r = Invoke-Gate @('-Root', $root)
        Assert-True 'Base = an ancestor of HEAD: fresh (exit 0)' ($r.Exit -eq 0) $r.Out
        Set-Checkpoint $second
        $r = Invoke-Gate @('-Root', $root)
        Assert-True 'Base = HEAD itself: fresh (exit 0)' ($r.Exit -eq 0) $r.Out
        Set-Checkpoint $orphan
        $r = Invoke-Gate @('-Root', $root)
        Assert-True 'Base on a branch HEAD does not descend from: STALE (exit 1)' ($r.Exit -eq 1) $r.Out
        Assert-True 'the finding says it is not an ancestor' ($r.Out -match 'NOT an ancestor of HEAD') $r.Out
        Set-Checkpoint 'deadbeefcafe0000'
        $r = Invoke-Gate @('-Root', $root)
        Assert-True 'a Base this clone does not have is reported, not counted as stale (exit 0)' ($r.Exit -eq 0 -and $r.Out -match 'not found in this clone') $r.Out
        # A paused plan on the orphan base is not checked for ancestry at all.
        [IO.File]::WriteAllText($plan, "# repo-plan`n`n## Checkpoint`n`nStatus: paused`nUpdated: $old`nBase: $orphan`n", $Utf8NoBom)
        $r = Invoke-Gate @('-Root', $root)
        Assert-True 'a paused plan is not judged on ancestry (exit 0)' ($r.Exit -eq 0) $r.Out
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
