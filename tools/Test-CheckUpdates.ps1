<#
  Test-CheckUpdates.ps1

  Suite for automation/maintenance/check-updates.ps1.

  Hermetic: the agent CLI is a .cmd stub that answers the three commands the script
  issues from fixture files; catalogues, the installed record and the report live
  under $env:TEMP; npm is a stub put first on PATH, or removed from it. Nothing here
  reaches the network or the real agent home. Every state of the exit contract is
  produced at least once, and the two defects the rewrite exists to name are
  planted: a catalogue whose keys differ only by case, which the 5.1 JSON parser
  rejects, and a comparison that used to be reported as "not comparable" when the
  fact was "could not read".
#>
[CmdletBinding()]
param([string]$ScriptPath)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($ScriptPath)) {
    $ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'automation\maintenance\check-updates.ps1'
}
$script:Pass = 0
$script:Fail = 0
$script:Skip = 0
$script:Temps = New-Object 'System.Collections.ArrayList'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Today = Get-Date -Format 'yyyy-MM-dd'
# A PATH with the shell and nothing else: no real agent CLI, no real npm.
$BarePath = (Join-Path $env:SystemRoot 'System32') + ';' + (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0')
$CommitA = 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1'
$CommitB = 'b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2'

function Assert-True {
    param([string] $Name, [bool] $Condition, [string] $Detail)
    if ($Condition) { $script:Pass++; Write-Output "  PASS  $Name" }
    else { $script:Fail++; Write-Output "  FAIL  $Name"; if ($Detail) { Write-Output "          -> $Detail" } }
}

function New-Box {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('upd-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $null = $script:Temps.Add($dir)
    return $dir
}

function Write-Text {
    param([string] $Path, [string] $Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Write-Json {
    param([string] $Path, $Object)
    # -InputObject, never the pipeline: a one-element array piped in serialises as the
    # element alone, and the script expects a list.
    Write-Text $Path (ConvertTo-Json -InputObject $Object -Depth 8)
}

function New-AgentStub {
    # A CLI that answers the three commands the script issues, from files.
    param([string] $Box, [int] $RefreshExit)
    $path = Join-Path $Box 'agent-stub.cmd'
    $marketplaceList = Join-Path $Box 'marketplace-list.json'
    $pluginList = Join-Path $Box 'plugin-list.json'
    $refresh = 'exit 0'
    if ($RefreshExit -ne 0) { $refresh = "(echo stub: refresh failed, no network 1>&2 & exit $RefreshExit)" }
    $lines = @(
        '@echo off',
        'set "A=%~1 %~2 %~3 %~4"',
        ('if "%A%"=="plugin marketplace update " ' + $refresh),
        ('if "%A%"=="plugin marketplace list --json" (type "' + $marketplaceList + '" & exit 0)'),
        ('if "%A%"=="plugin list --json " (type "' + $pluginList + '" & exit 0)'),
        'echo stub: unexpected arguments %* 1>&2',
        'exit 9'
    )
    Write-Text $path (($lines -join "`r`n") + "`r`n")
    return $path
}

function New-NpmStub {
    param([string] $Dir, [string] $Answer, [int] $Exit)
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    Write-Text (Join-Path $Dir 'answer.json') $Answer
    Write-Text (Join-Path $Dir 'npm.cmd') ("@echo off`r`ntype """ + (Join-Path $Dir 'answer.json') + """`r`nexit $Exit`r`n")
}

function New-Installed {
    param([string] $Id, [string] $Version, [bool] $Enabled = $true, [string] $Scope = 'user')
    return @{ id = $Id; version = $Version; scope = $Scope; enabled = $Enabled; installPath = 'not-used'; installedAt = '2026-01-01T00:00:00.000Z'; lastUpdated = '2026-01-01T00:00:00.000Z' }
}

function New-Catalogue {
    param([hashtable[]] $Plugins)
    return @{ name = 'mp'; owner = @{ name = 'suite' }; plugins = @($Plugins) }
}

function New-VersionedEntry {
    param([string] $Name, [string] $Version)
    return @{ name = $Name; version = $Version; source = @{ source = 'url'; url = 'https://example.com/' + $Name + '.git' } }
}

function New-PinnedEntry {
    param([string] $Name, [string] $Commit)
    return @{ name = $Name; source = @{ source = 'url'; url = 'https://example.com/' + $Name + '.git'; sha = $Commit } }
}

function New-BareEntry {
    param([string] $Name)
    return @{ name = $Name; source = './plugins/' + $Name }
}

function New-Record {
    # installed_plugins.json: id -> one entry per scope, with the commit recorded at install.
    param([hashtable] $Commits)
    $plugins = @{}
    foreach ($id in $Commits.Keys) { $plugins[$id] = @(@{ scope = 'user'; version = '0'; gitCommitSha = $Commits[$id] }) }
    return @{ version = 2; plugins = $plugins }
}

function New-Fixture {
    param(
        [object[]] $Installed,
        [hashtable] $Catalogue,
        [string] $CatalogueText,
        [hashtable] $Record,
        [int] $RefreshExit = 0,
        [switch] $NoMarketplace
    )
    $box = New-Box
    $marketplaceDir = Join-Path $box 'marketplaces\mp'
    New-Item -ItemType Directory -Path (Join-Path $marketplaceDir '.claude-plugin') -Force | Out-Null
    $manifest = Join-Path $marketplaceDir '.claude-plugin\marketplace.json'
    if (-not [string]::IsNullOrEmpty($CatalogueText)) { Write-Text $manifest $CatalogueText }
    elseif ($null -ne $Catalogue) { Write-Json $manifest $Catalogue }
    $marketplaces = @()
    if (-not $NoMarketplace) {
        $marketplaces = @(@{ name = 'mp'; source = 'github'; repo = 'example/mp'; installLocation = $marketplaceDir })
    }
    Write-Json (Join-Path $box 'marketplace-list.json') $marketplaces
    Write-Json (Join-Path $box 'plugin-list.json') @($Installed)
    New-Item -ItemType Directory -Path (Join-Path $box 'plugins') -Force | Out-Null
    if ($null -ne $Record) { Write-Json (Join-Path $box 'plugins\installed_plugins.json') $Record }
    return [pscustomobject]@{
        Box     = $box
        Stub    = (New-AgentStub -Box $box -RefreshExit $RefreshExit)
        Plugins = (Join-Path $box 'plugins')
        Reports = (Join-Path $box 'reports')
    }
}

function Invoke-Check {
    param([string[]] $ScriptArgs, [string] $PathOverride)
    $previousPreference = $ErrorActionPreference
    $previousPath = $env:Path
    $ErrorActionPreference = 'Continue'
    try {
        if (-not [string]::IsNullOrEmpty($PathOverride)) { $env:Path = $PathOverride }
        $global:LASTEXITCODE = $null
        $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @ScriptArgs 2>&1 | Out-String)
        $code = $global:LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
        $env:Path = $previousPath
    }
    return [pscustomobject]@{ Exit = $code; Out = $out }
}

function Get-Report {
    param($Fixture)
    $path = Join-Path $Fixture.Reports "updates-$Today.md"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    return [IO.File]::ReadAllText($path)
}

function Get-StandardArgs {
    param($Fixture, [switch] $WithNpm)
    $list = @('-ClaudeCli', $Fixture.Stub, '-PluginsRoot', $Fixture.Plugins, '-ReportRoot', $Fixture.Reports)
    if (-not $WithNpm) { $list += '-SkipNpm' }
    return ,$list
}

try {
    Assert-True 'the script exists' (Test-Path -LiteralPath $ScriptPath -PathType Leaf) $ScriptPath
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) { throw 'script missing' }

    Write-Output 'Group 1 - state 0: everything checked, everything current'
    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0'), (New-Installed 'beta@mp' '2.0.0')) `
                     -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0'), (New-PinnedEntry 'beta' $CommitB))) `
                     -Record (New-Record @{ 'beta@mp' = $CommitB })
    $r = Invoke-Check (Get-StandardArgs $f)
    $report = Get-Report $f
    Assert-True 'exit 0' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'the report is written under -ReportRoot' ($report.Length -gt 0) $f.Reports
    $latestPath = Join-Path $f.Reports 'updates-latest.md'
    Assert-True 'and copied to updates-latest.md, byte for byte' ((Test-Path -LiteralPath $latestPath) -and ([IO.File]::ReadAllText($latestPath) -eq $report))
    Assert-True 'the CLI line says how the CLI was found' ($report -match '- CLI: .* \(given with -ClaudeCli\)') $report
    Assert-True 'the catalogues were refreshed through the CLI' ($report -match 'catalogues: refreshed') $report
    Assert-True 'a version match is current' ($report -match '- alpha@mp : 1\.0\.0  \(current\)') $report
    Assert-True 'a pinned-commit match is current, and says it was compared that way' ($report -match '- beta@mp : 2\.0\.0  \(current; .*pinned commit b2b2b2b') $report
    Assert-True 'npm is reported as skipped on request, not as checked' ($report -match 'skipped on request \(-SkipNpm\)') $report
    Assert-True 'stdout carries the three counts, all zero' ($r.Out -match 'Updates available: 0' -and $r.Out -match 'Other findings: 0' -and $r.Out -match 'Could not check: 0') $r.Out
    Assert-True 'stdout says nothing was applied' ($r.Out -match 'Nothing was applied') $r.Out

    $f = New-Fixture -Installed @() -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0')))
    $r = Invoke-Check (Get-StandardArgs $f)
    Assert-True 'no plugins installed: exit 0, and said so' ($r.Exit -eq 0 -and (Get-Report $f) -match 'no plugins are installed') $r.Out

    Write-Output 'Group 2 - state 1: findings, each printed with what to decide'
    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0' $false), (New-Installed 'beta@mp' '2.0.0'), (New-Installed 'gamma@mp' '3.0.0'), (New-Installed 'delta@other' '4.0.0')) `
                     -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.1.0'), (New-PinnedEntry 'beta' $CommitB))) `
                     -Record (New-Record @{ 'beta@mp' = $CommitA })
    $r = Invoke-Check (Get-StandardArgs $f)
    $report = Get-Report $f
    Assert-True 'exit 1' ($r.Exit -eq 1) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'a newer catalogue version is an UPDATE naming both versions' ($report -match '- alpha@mp : 1\.0\.0 \(disabled\) -> \*\*1\.1\.0\*\*  \[UPDATE\]') $report
    Assert-True 'a moved pinned commit is an UPDATE naming both commits' ($report -match '- beta@mp : 2\.0\.0  commit a1a1a1a -> \*\*b2b2b2b\*\*  \[UPDATE\]') $report
    Assert-True 'a plugin the catalogue dropped is a finding, not silence' ($report -match '- gamma@mp : 3\.0\.0  NOT IN CATALOGUE') $report
    Assert-True 'a plugin whose marketplace is gone is a finding, not silence' ($report -match "- delta@other : 4\.0\.0  MARKETPLACE 'other' IS NOT CONFIGURED") $report
    Assert-True 'the counts separate updates from other findings' ($r.Out -match 'Updates available: 2' -and $r.Out -match 'Other findings: 2' -and $r.Out -match 'Could not check: 0') $r.Out

    Write-Output 'Group 3 - state 2: could not check, never 0 and never 1'
    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0')))
    $missing = Join-Path $f.Box 'no-such-cli.cmd'
    $r = Invoke-Check @('-ClaudeCli', $missing, '-PluginsRoot', $f.Plugins, '-ReportRoot', $f.Reports, '-SkipNpm')
    $report = Get-Report $f
    Assert-True 'a wrong -ClaudeCli exits 2' ($r.Exit -eq 2) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'and is named as the reason, not guessed around' ($report -match 'COULD NOT CHECK: the agent CLI was nothing at the path given with -ClaudeCli') $report
    Assert-True 'the report is still written on exit 2' ($report.Length -gt 0)

    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0'))) -RefreshExit 1
    $r = Invoke-Check (Get-StandardArgs $f)
    $report = Get-Report $f
    Assert-True 'a failed catalogue refresh exits 2' ($r.Exit -eq 2) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'names the failure with the CLI complaint' ($report -match 'COULD NOT REFRESH the catalogues \(exit 1\): stub: refresh failed') $report
    Assert-True 'and still compares against the cached copies' ($report -match '- alpha@mp : 1\.0\.0  \(current\)') $report

    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0')))
    Write-Text (Join-Path $f.Box 'plugin-list.json') 'this is not json'
    $r = Invoke-Check (Get-StandardArgs $f)
    Assert-True 'an unreadable installed list exits 2 and says so' ($r.Exit -eq 2 -and (Get-Report $f) -match 'COULD NOT READ the installed list') $r.Out

    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0'), (New-Installed 'beta@mp' '2.0.0')) `
                     -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0'), (New-PinnedEntry 'beta' $CommitB)))
    $r = Invoke-Check (Get-StandardArgs $f)
    $report = Get-Report $f
    Assert-True 'a pinned commit with no installed record exits 2' ($r.Exit -eq 2) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'names the plugin and the missing record' ($report -match '- beta@mp : 2\.0\.0  COULD NOT COMPARE - .*installed commit is unknown: no installed_plugins\.json') $report
    Assert-True 'while the plugin that could be compared still is' ($report -match '- alpha@mp : 1\.0\.0  \(current\)') $report

    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -Catalogue (New-Catalogue @((New-BareEntry 'alpha')))
    $r = Invoke-Check (Get-StandardArgs $f)
    Assert-True 'a catalogue entry with neither version nor commit exits 2, naming the limit' ($r.Exit -eq 2 -and (Get-Report $f) -match 'COULD NOT COMPARE - the catalogue declares neither a version nor a pinned commit') $r.Out

    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -CatalogueText '{"name":"mp","plugins":[{"name":"alpha","version":"1.0.0"'
    $r = Invoke-Check (Get-StandardArgs $f)
    Assert-True 'a truncated catalogue exits 2 as unreadable, for either parser' ($r.Exit -eq 2 -and (Get-Report $f) -match "COULD NOT COMPARE - the catalogue of 'mp' is unreadable: not valid JSON for either parser") $r.Out

    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0'), (New-Installed 'beta@mp' '2.0.0')) `
                     -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.1.0'), (New-PinnedEntry 'beta' $CommitB)))
    $r = Invoke-Check (Get-StandardArgs $f)
    $report = Get-Report $f
    Assert-True 'an update next to a could-not-check exits 2, not 1' ($r.Exit -eq 2) "exit [$($r.Exit)]"
    Assert-True 'and the update is still printed and counted' ($report -match '- alpha@mp : 1\.0\.0 -> \*\*1\.1\.0\*\*  \[UPDATE\]' -and $r.Out -match 'Updates available: 1' -and $r.Out -match 'Could not check: 1') $r.Out

    Write-Output 'Group 4 - a catalogue the 5.1 parser rejects is read, and garbage is still refused'
    $duplicateKeys = '{"name":"mp","plugins":[{"name":"alpha","version":"1.0.0","source":{"source":"url","url":"https://example.com/alpha.git"},"lspServers":{"languages":{".c":"c",".C":"cpp"}}}]}'
    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -CatalogueText $duplicateKeys
    $r = Invoke-Check (Get-StandardArgs $f)
    $report = Get-Report $f
    Assert-True 'keys differing only by case: exit 0' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"
    # -cnotmatch: the report's own footer says "Could not check: 0", and -notmatch ignores case.
    Assert-True 'the plugin in that catalogue is compared, not "not comparable"' ($report -match '- alpha@mp : 1\.0\.0  \(current\)' -and $report -cnotmatch 'COULD NOT') $report
    # Control: the host's own parser must reject that text, or the case above proved
    # nothing about the fallback. Windows PowerShell 5.1 does; a newer engine may not.
    $rejected = $false
    try { $null = $duplicateKeys | ConvertFrom-Json -ErrorAction Stop } catch { $rejected = $true }
    if ($rejected) { Assert-True 'control: this host rejects the planted text, so the fallback was exercised' $true }
    else { $script:Skip++; Write-Output '  SKIP  this host accepts case-variant keys natively; the fallback was not exercised (skipped is not passed)' }

    Write-Output 'Group 5 - resolving the CLI on a sandboxed host'
    $f = New-Fixture -Installed @() -Catalogue (New-Catalogue @())
    $packages = Join-Path $f.Box 'Packages'
    foreach ($version in @('1.2.3', '1.10.0', 'not-a-version')) {
        $folder = Join-Path $packages ('Vendor_abc\LocalCache\Roaming\Claude\claude-code\' + $version)
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $folder 'claude.exe'), [byte[]]@())
    }
    New-Item -ItemType Directory -Path (Join-Path $packages 'Other_xyz\LocalCache') -Force | Out-Null
    $r = Invoke-Check @('-PackageRoot', $packages, '-PluginsRoot', $f.Plugins, '-ReportRoot', $f.Reports, '-SkipNpm') $BarePath
    $report = Get-Report $f
    Assert-True 'the highest version is chosen numerically, not lexically' ($report -match '- CLI: .*\\1\.10\.0\\claude\.exe \(found in the package cache') $report
    Assert-True 'an executable that cannot start is could-not-check (exit 2), not an empty plugin list' ($r.Exit -eq 2 -and $report -match 'COULD NOT RUN the CLI' -and $report -notmatch 'no plugins are installed') $r.Out

    $r = Invoke-Check @('-PackageRoot', (Join-Path $f.Box 'nowhere'), '-PluginsRoot', $f.Plugins, '-ReportRoot', $f.Reports, '-SkipNpm') $BarePath
    Assert-True 'no CLI anywhere exits 2 and says where it looked' ($r.Exit -eq 2 -and (Get-Report $f) -match 'COULD NOT CHECK: the agent CLI was not on PATH, and no package cache') $r.Out

    Write-Output 'Group 6 - the npm surface, through a stub on PATH'
    $current = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0')))

    $npmDir = Join-Path $current.Box 'npm-outdated'
    New-NpmStub $npmDir '{"pkg":{"current":"1.0.0","wanted":"1.1.0","latest":"1.1.0","dependent":"global","location":"global"}}' 1
    $r = Invoke-Check (Get-StandardArgs $current -WithNpm) ($npmDir + ';' + $BarePath)
    $report = Get-Report $current
    Assert-True 'an outdated global package is an UPDATE naming both versions (exit 1)' ($r.Exit -eq 1 -and $report -match '- pkg : 1\.0\.0 -> \*\*1\.1\.0\*\*  \[UPDATE\]') "exit [$($r.Exit)]; $report"

    $npmDir = Join-Path $current.Box 'npm-current'
    New-NpmStub $npmDir '{}' 0
    $r = Invoke-Check (Get-StandardArgs $current -WithNpm) ($npmDir + ';' + $BarePath)
    Assert-True 'nothing outdated is current (exit 0)' ($r.Exit -eq 0 -and (Get-Report $current) -match 'everything current') $r.Out

    $npmDir = Join-Path $current.Box 'npm-error'
    New-NpmStub $npmDir '{"error":{"code":"E503","summary":"registry unavailable"}}' 1
    $r = Invoke-Check (Get-StandardArgs $current -WithNpm) ($npmDir + ';' + $BarePath)
    Assert-True 'a registry error twice is could-not-check (exit 2), naming the summary' ($r.Exit -eq 2 -and (Get-Report $current) -match 'COULD NOT CHECK: npm answered an error twice: registry unavailable') $r.Out

    $r = Invoke-Check (Get-StandardArgs $current -WithNpm) $BarePath
    Assert-True 'npm off the PATH is could-not-check (exit 2), not everything current' ($r.Exit -eq 2 -and (Get-Report $current) -match 'COULD NOT CHECK: npm is not on this PATH') $r.Out
}
finally {
    foreach ($d in $script:Temps) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Output ''
if ($script:Skip -gt 0) { Write-Output "($script:Skip check(s) skipped)" }
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
