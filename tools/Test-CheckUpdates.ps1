<#
  Test-CheckUpdates.ps1

  Suite for automation/maintenance/check-updates.ps1.

  Hermetic: the agent CLI is a .cmd stub that answers the three commands the script
  issues from fixture files, with a configurable exit for each; catalogues, the
  installed record and the report live under $env:TEMP; npm is a stub put first on
  PATH, or removed from it. Nothing here reaches the network or the real agent home.
  Every exit state, and every report branch the stub can reach, is produced at least
  once, including the ones that must fail. The exception is the two "could not run"
  branches that need an executable dying between two commands; they are named here
  rather than faked. Five of the cases are exit-class defects a reviewer found on
  2026-09-20, in two rounds, with the same kind of stub; they are kept as regressions.
#>
[CmdletBinding()]
param([string]$ScriptPath)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($ScriptPath)) {
    $ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'automation\maintenance\check-updates.ps1'
}
$script:Pass = 0
$script:Fail = 0
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
    # A CLI that answers the three commands the script issues, from files, each with
    # its own exit code when a case needs the command to fail.
    param([string] $Box, [int] $RefreshExit, [int] $MarketplaceListExit, [int] $PluginListExit, [switch] $EmptyMarketplaceList, [switch] $EmptyPluginList)
    $path = Join-Path $Box 'agent-stub.cmd'
    $marketplaceList = Join-Path $Box 'marketplace-list.json'
    $pluginList = Join-Path $Box 'plugin-list.json'
    $refresh = 'exit 0'
    if ($RefreshExit -ne 0) { $refresh = "(echo stub: refresh failed, no network 1>&2 & exit $RefreshExit)" }
    $marketplaces = '(type "' + $marketplaceList + '" & exit 0)'
    if ($MarketplaceListExit -ne 0) { $marketplaces = "(echo stub: cannot list marketplaces 1>&2 & exit $MarketplaceListExit)" }
    if ($EmptyMarketplaceList) { $marketplaces = 'exit 0' }
    $plugins = '(type "' + $pluginList + '" & exit 0)'
    if ($PluginListExit -ne 0) { $plugins = "(echo stub: cannot list plugins 1>&2 & exit $PluginListExit)" }
    if ($EmptyPluginList) { $plugins = 'exit 0' }
    $lines = @(
        '@echo off',
        'set "A=%~1 %~2 %~3 %~4"',
        ('if "%A%"=="plugin marketplace update " ' + $refresh),
        ('if "%A%"=="plugin marketplace list --json" ' + $marketplaces),
        ('if "%A%"=="plugin list --json " ' + $plugins),
        'echo stub: unexpected arguments %* 1>&2',
        'exit 9'
    )
    Write-Text $path (($lines -join "`r`n") + "`r`n")
    return $path
}

function New-NpmStub {
    # An npm that prints a fixed answer on stdout and exits as told.
    param([string] $Dir, [string] $Answer, [int] $Exit)
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    Write-Text (Join-Path $Dir 'answer.json') $Answer
    Write-Text (Join-Path $Dir 'npm.cmd') ("@echo off`r`ntype """ + (Join-Path $Dir 'answer.json') + """`r`nexit $Exit`r`n")
}

function New-NpmStubBody {
    # An npm with an arbitrary body, for the cases about what it does NOT print.
    param([string] $Dir, [string] $Body)
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    Write-Text (Join-Path $Dir 'npm.cmd') $Body
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
        [int] $MarketplaceListExit = 0,
        [int] $PluginListExit = 0,
        [string] $MarketplaceListText,
        [switch] $NoMarketplace,
        [switch] $NoInstallLocation,
        [switch] $EmptyMarketplaceList,
        [switch] $EmptyPluginList
    )
    $box = New-Box
    $marketplaceDir = Join-Path $box 'marketplaces\mp'
    New-Item -ItemType Directory -Path (Join-Path $marketplaceDir '.claude-plugin') -Force | Out-Null
    $manifest = Join-Path $marketplaceDir '.claude-plugin\marketplace.json'
    if (-not [string]::IsNullOrEmpty($CatalogueText)) { Write-Text $manifest $CatalogueText }
    elseif ($null -ne $Catalogue) { Write-Json $manifest $Catalogue }
    if (-not [string]::IsNullOrEmpty($MarketplaceListText)) {
        Write-Text (Join-Path $box 'marketplace-list.json') $MarketplaceListText
    }
    else {
        $marketplaces = @()
        if (-not $NoMarketplace) {
            $entry = @{ name = 'mp'; source = 'github'; repo = 'example/mp' }
            if (-not $NoInstallLocation) { $entry['installLocation'] = $marketplaceDir }
            $marketplaces = @($entry)
        }
        Write-Json (Join-Path $box 'marketplace-list.json') $marketplaces
    }
    Write-Json (Join-Path $box 'plugin-list.json') @($Installed)
    New-Item -ItemType Directory -Path (Join-Path $box 'plugins') -Force | Out-Null
    if ($null -ne $Record) { Write-Json (Join-Path $box 'plugins\installed_plugins.json') $Record }
    return [pscustomobject]@{
        Box     = $box
        Stub    = (New-AgentStub -Box $box -RefreshExit $RefreshExit -MarketplaceListExit $MarketplaceListExit -PluginListExit $PluginListExit -EmptyMarketplaceList:$EmptyMarketplaceList -EmptyPluginList:$EmptyPluginList)
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

    # The refresh is the one write outside the report folder; the switch must keep the
    # command from being issued at all, so the stub's refresh is made to fail here.
    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0'))) -RefreshExit 1
    $r = Invoke-Check ((Get-StandardArgs $f) + '-SkipMarketplaceRefresh')
    $report = Get-Report $f
    Assert-True '-SkipMarketplaceRefresh: exit 0 although the stub refresh would fail' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'the report says the catalogues were not refreshed, on request' ($report -match 'not refreshed, on request \(-SkipMarketplaceRefresh\)') $report
    Assert-True 'and the refresh command was never issued' ($report -cnotmatch 'COULD NOT REFRESH' -and $report -notmatch 'catalogues: refreshed') $report

    Write-Output 'Group 2 - state 1: findings, each printed with what to decide'
    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0' $false), (New-Installed 'beta@mp' '2.0.0'), (New-Installed 'gamma@mp' '3.0.0'), (New-Installed 'delta@other' '4.0.0'), (New-Installed 'orphan' '5.0.0')) `
                     -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.1.0'), (New-PinnedEntry 'beta' $CommitB))) `
                     -Record (New-Record @{ 'beta@mp' = $CommitA })
    $r = Invoke-Check (Get-StandardArgs $f)
    $report = Get-Report $f
    Assert-True 'exit 1' ($r.Exit -eq 1) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'a newer catalogue version is an UPDATE naming both versions' ($report -match '- alpha@mp : 1\.0\.0 \(disabled\) -> \*\*1\.1\.0\*\*  \[UPDATE\]') $report
    Assert-True 'a moved pinned commit is an UPDATE naming both commits' ($report -match '- beta@mp : 2\.0\.0  commit a1a1a1a -> \*\*b2b2b2b\*\*  \[UPDATE\]') $report
    # Measured 2026-09-20: the CLI's update command compares version strings only, so a pin
    # that moved behind an unchanged version is "already at the latest version" to it.
    Assert-True 'and says how to take it, since plugin update compares version strings only' ($report -match 'uninstall, then install') $report
    Assert-True 'a plugin the catalogue dropped is a finding, not silence' ($report -match '- gamma@mp : 3\.0\.0  NOT IN CATALOGUE') $report
    Assert-True 'a plugin whose marketplace is gone is a finding, not silence' ($report -match "- delta@other : 4\.0\.0  MARKETPLACE 'other' IS NOT CONFIGURED") $report
    Assert-True 'an id that names no marketplace is a finding, not silence' ($report -match '- orphan : 5\.0\.0  NOT ATTRIBUTABLE') $report
    Assert-True 'the counts separate updates from other findings' ($r.Out -match 'Updates available: 2' -and $r.Out -match 'Other findings: 3' -and $r.Out -match 'Could not check: 0') $r.Out

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

    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0'))) -MarketplaceListExit 1
    $r = Invoke-Check (Get-StandardArgs $f)
    $report = Get-Report $f
    Assert-True 'a marketplace list that fails exits 2, naming the complaint' ($r.Exit -eq 2 -and $report -match 'COULD NOT LIST the marketplaces \(exit 1\): stub: cannot list marketplaces') "exit [$($r.Exit)]; $report"
    Assert-True 'and every plugin is could-not-compare, not dropped' ($report -match '- alpha@mp : 1\.0\.0  COULD NOT COMPARE - the marketplace list was not available') $report

    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0'))) -MarketplaceListText 'not json at all'
    $r = Invoke-Check (Get-StandardArgs $f)
    Assert-True 'an unreadable marketplace list exits 2 and says so' ($r.Exit -eq 2 -and (Get-Report $f) -match 'COULD NOT READ the marketplace list') $r.Out

    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0'))) -PluginListExit 1
    $r = Invoke-Check (Get-StandardArgs $f)
    Assert-True 'an installed list that fails exits 2, naming the complaint' ($r.Exit -eq 2 -and (Get-Report $f) -match 'COULD NOT LIST the installed plugins \(exit 1\): stub: cannot list plugins') $r.Out

    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0')))
    Write-Text (Join-Path $f.Box 'plugin-list.json') 'this is not json'
    $r = Invoke-Check (Get-StandardArgs $f)
    Assert-True 'an unreadable installed list exits 2 and says so' ($r.Exit -eq 2 -and (Get-Report $f) -match 'COULD NOT READ the installed list') $r.Out

    # Reviewer's cases, round two (2026-09-20): on 5.1, '' | ConvertFrom-Json is $null
    # without an error, and @($null) has one element - an empty listing fabricated
    # class-1 findings with the wrong advice.
    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0'))) -EmptyMarketplaceList
    $r = Invoke-Check (Get-StandardArgs $f)
    $report = Get-Report $f
    Assert-True 'a marketplace list with nothing on stdout is could-not-read (exit 2)' ($r.Exit -eq 2 -and $report -match 'COULD NOT READ the marketplace list: nothing on stdout \(exit 0\)') "exit [$($r.Exit)]; $report"
    Assert-True 'and no plugin is told its marketplace is gone' ($report -cnotmatch 'IS NOT CONFIGURED' -and $report -match 'COULD NOT COMPARE - the marketplace list was not available') $report

    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0'))) -EmptyPluginList
    $r = Invoke-Check (Get-StandardArgs $f)
    $report = Get-Report $f
    Assert-True 'an installed list with nothing on stdout is could-not-read (exit 2)' ($r.Exit -eq 2 -and $report -match 'COULD NOT READ the installed list: nothing on stdout \(exit 0\)') "exit [$($r.Exit)]; $report"
    Assert-True 'and no phantom plugin is reported' ($report -cnotmatch 'NOT ATTRIBUTABLE') $report

    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0'))) -NoInstallLocation
    $r = Invoke-Check (Get-StandardArgs $f)
    Assert-True 'a marketplace without an install location is could-not-compare (exit 2)' ($r.Exit -eq 2 -and (Get-Report $f) -match "COULD NOT COMPARE - the catalogue of 'mp' is unreadable: the marketplace list gives no install location") $r.Out

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

    # Reviewer's case, 2026-09-20: a catalogue with no plugins section used to be walked
    # once with a null candidate and reported as "the marketplace dropped the plugin".
    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -CatalogueText '{"name":"mp","owner":{"name":"x"}}'
    $r = Invoke-Check (Get-StandardArgs $f)
    $report = Get-Report $f
    Assert-True 'a catalogue with no plugins section is could-not-compare (exit 2)' ($r.Exit -eq 2 -and $report -match "COULD NOT COMPARE - the catalogue of 'mp' has no plugins section") "exit [$($r.Exit)]; $report"
    Assert-True 'and never a dropped plugin' ($report -cnotmatch 'NOT IN CATALOGUE') $report

    # Three facts, three sentences: a null section, an empty section, an empty file. The
    # first version said "has no plugins section" for all of them, because Get-Field
    # handed an empty list back bare and it unrolled to nothing.
    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -CatalogueText '{"name":"mp","plugins":null}'
    $r = Invoke-Check (Get-StandardArgs $f)
    Assert-True 'a null plugins section is could-not-compare, and says null' ($r.Exit -eq 2 -and (Get-Report $f) -match "the plugins section of the catalogue of 'mp' is null") $r.Out

    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -CatalogueText '{"name":"mp","plugins":[]}'
    $r = Invoke-Check (Get-StandardArgs $f)
    Assert-True 'an empty plugins section lists nothing, so the plugin is not in it (exit 1)' ($r.Exit -eq 1 -and (Get-Report $f) -match '- alpha@mp : 1\.0\.0  NOT IN CATALOGUE') $r.Out

    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -CatalogueText ' '
    $r = Invoke-Check (Get-StandardArgs $f)
    Assert-True 'an empty marketplace.json is could-not-compare, and says empty' ($r.Exit -eq 2 -and (Get-Report $f) -match 'is unreadable: marketplace\.json at .* is empty or parsed to nothing') $r.Out

    $f = New-Fixture -Installed @((New-Installed 'beta@mp' '2.0.0')) -Catalogue (New-Catalogue @((New-PinnedEntry 'beta' $CommitB)))
    Write-Text (Join-Path $f.Plugins 'installed_plugins.json') ' '
    $r = Invoke-Check (Get-StandardArgs $f)
    Assert-True 'an empty installed record is named as empty, not as missing' ($r.Exit -eq 2 -and (Get-Report $f) -match 'installed commit is unknown: .*installed_plugins\.json is empty or parsed to nothing') $r.Out

    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0'), (New-Installed 'beta@mp' '2.0.0')) `
                     -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.1.0'), (New-PinnedEntry 'beta' $CommitB)))
    $r = Invoke-Check (Get-StandardArgs $f)
    $report = Get-Report $f
    Assert-True 'an update next to a could-not-check exits 2, not 1' ($r.Exit -eq 2) "exit [$($r.Exit)]"
    Assert-True 'and the update is still printed and counted' ($report -match '- alpha@mp : 1\.0\.0 -> \*\*1\.1\.0\*\*  \[UPDATE\]' -and $r.Out -match 'Updates available: 1' -and $r.Out -match 'Could not check: 1') $r.Out

    # The report itself cannot be written: a file sits where the folder would go.
    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0')))
    $blocked = Join-Path $f.Box 'blocked'
    Write-Text $blocked 'a file where a folder is needed'
    $r = Invoke-Check @('-ClaudeCli', $f.Stub, '-PluginsRoot', $f.Plugins, '-ReportRoot', (Join-Path $blocked 'reports'), '-SkipNpm')
    Assert-True 'an unwritable report root exits 2' ($r.Exit -eq 2) "exit [$($r.Exit)]; $($r.Out)"
    Assert-True 'and the report text goes to stdout with the reason' ($r.Out -match 'COULD NOT WRITE the report under' -and $r.Out -match '- alpha@mp : 1\.0\.0  \(current\)') $r.Out

    Write-Output 'Group 4 - a catalogue the 5.1 parser rejects is read, and garbage is still refused'
    $duplicateKeys = '{"name":"mp","plugins":[{"name":"alpha","version":"1.0.0","source":{"source":"url","url":"https://example.com/alpha.git"},"lspServers":{"languages":{".c":"c",".C":"cpp"}}}]}'
    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -CatalogueText $duplicateKeys
    $r = Invoke-Check (Get-StandardArgs $f)
    $report = Get-Report $f
    Assert-True 'keys differing only by case: exit 0' ($r.Exit -eq 0) "exit [$($r.Exit)]; $($r.Out)"
    # -cnotmatch: the report's own footer says "Could not check: 0", and -notmatch ignores case.
    Assert-True 'the plugin in that catalogue is compared, not "not comparable"' ($report -match '- alpha@mp : 1\.0\.0  \(current\)' -and $report -cnotmatch 'COULD NOT') $report
    Assert-True 'the loss is named: which catalogue, how many keys' ($report -match "- note: the catalogue of 'mp' needed the fallback parser; 1 key\(s\) differing only by case dropped") $report
    Assert-True 'and the note sits under the CLI lines, before the plugins' ($report.IndexOf('- note: the catalogue') -gt 0 -and $report.IndexOf('- note: the catalogue') -lt $report.IndexOf('- alpha@mp')) $report

    # The same note for a listing: every JSON the script reads goes through the same parser.
    $f = New-Fixture -Installed @((New-Installed 'alpha@mp' '1.0.0')) -Catalogue (New-Catalogue @((New-VersionedEntry 'alpha' '1.0.0')))
    $listText = '[{"name":"mp","source":"github","repo":"example/mp","installLocation":"' + ((Join-Path $f.Box 'marketplaces\mp') -replace '\\', '\\') + '","map":{".c":1,".C":2}}]'
    Write-Text (Join-Path $f.Box 'marketplace-list.json') $listText
    $r = Invoke-Check (Get-StandardArgs $f)
    Assert-True 'a marketplace list that needs the fallback gets the same note, and the run is still clean' ($r.Exit -eq 0 -and (Get-Report $f) -match '- note: the marketplace list needed the fallback parser; 1 key\(s\)') "exit [$($r.Exit)]; $($r.Out)"
    # Control, run in the same engine the script runs under: if that parser accepted the
    # planted text, the case above would have proved nothing about the fallback.
    $controlFile = Join-Path $f.Box 'duplicate-keys.json'
    Write-Text $controlFile $duplicateKeys
    $control = (& powershell -NoProfile -ExecutionPolicy Bypass -Command "try { `$null = [IO.File]::ReadAllText('$controlFile') | ConvertFrom-Json -ErrorAction Stop; 'accepted' } catch { 'rejected' }" 2>&1 | Out-String)
    Assert-True 'control: the 5.1 engine that runs the script rejects the planted text' ($control -match 'rejected') $control

    Write-Output 'Group 5 - resolving the CLI on a sandboxed host'
    $f = New-Fixture -Installed @() -Catalogue (New-Catalogue @())
    $packages = Join-Path $f.Box 'Packages'
    foreach ($version in @('1.2.3', '1.10.0', 'not-a-version')) {
        $folder = Join-Path $packages ('Claude_abc\LocalCache\Roaming\Claude\claude-code\' + $version)
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $folder 'claude.exe'), [byte[]]@())
    }
    # A decoy: another package with the same inner layout and a higher version must lose.
    $decoy = Join-Path $packages 'Other_xyz\LocalCache\Roaming\Claude\claude-code\9.9.9'
    New-Item -ItemType Directory -Path $decoy -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $decoy 'claude.exe'), [byte[]]@())
    $r = Invoke-Check @('-PackageRoot', $packages, '-PluginsRoot', $f.Plugins, '-ReportRoot', $f.Reports, '-SkipNpm') $BarePath
    $report = Get-Report $f
    Assert-True 'the highest version is chosen numerically, not lexically' ($report -match '- CLI: .*\\Claude_abc\\.*\\1\.10\.0\\claude\.exe \(found in the package cache') $report
    Assert-True 'only the vendor package folders are searched' ($report -notmatch 'Other_xyz') $report
    Assert-True 'an executable that cannot start is could-not-check (exit 2), not an empty plugin list' ($r.Exit -eq 2 -and $report -match 'COULD NOT RUN the CLI' -and $report -notmatch 'no plugins are installed') $r.Out

    $r = Invoke-Check @('-PackageRoot', $packages, '-PluginsRoot', $f.Plugins, '-ReportRoot', $f.Reports, '-SkipNpm', '-SkipMarketplaceRefresh') $BarePath
    Assert-True 'with the refresh skipped, the listing is the first command and its failure to start is still exit 2' ($r.Exit -eq 2 -and (Get-Report $f) -match 'COULD NOT RUN the CLI') $r.Out

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

    $npmDir = Join-Path $current.Box 'npm-silent-ok'
    New-NpmStubBody $npmDir "@echo off`r`nexit 0`r`n"
    $r = Invoke-Check (Get-StandardArgs $current -WithNpm) ($npmDir + ';' + $BarePath)
    Assert-True 'nothing on stdout with exit 0 is current (exit 0)' ($r.Exit -eq 0 -and (Get-Report $current) -match 'everything current') $r.Out

    # Reviewer's case, 2026-09-20: npm that says nothing on stdout and fails used to read
    # as "everything current" with exit 0 - the 0 on an error path the contract forbids.
    $npmDir = Join-Path $current.Box 'npm-stderr-only'
    New-NpmStubBody $npmDir "@echo off`r`necho npm ERR! node failed before json mode 1>&2`r`nexit 1`r`n"
    $r = Invoke-Check (Get-StandardArgs $current -WithNpm) ($npmDir + ';' + $BarePath)
    $report = Get-Report $current
    Assert-True 'nothing on stdout with a non-zero exit is could-not-check (exit 2)' ($r.Exit -eq 2) "exit [$($r.Exit)]; $report"
    Assert-True 'naming the exit and the first stderr line' ($report -match 'COULD NOT CHECK: npm exited 1 with nothing on stdout: npm ERR! node failed before json mode') $report

    # Reviewer's case, round two: {} on stdout with the error on stderr and a non-zero exit
    # used to read as "everything current" with exit 0, the sibling of the case above.
    $npmDir = Join-Path $current.Box 'npm-empty-object-failed'
    New-NpmStubBody $npmDir "@echo off`r`necho npm ERR! registry timeout 1>&2`r`necho {}`r`nexit 3`r`n"
    $r = Invoke-Check (Get-StandardArgs $current -WithNpm) ($npmDir + ';' + $BarePath)
    $report = Get-Report $current
    Assert-True 'an empty object with a non-zero exit is could-not-check (exit 2)' ($r.Exit -eq 2 -and $report -match 'COULD NOT CHECK: npm exited 3 with an empty object on stdout: npm ERR! registry timeout') "exit [$($r.Exit)]; $report"

    # Reviewer's case, 2026-09-20: a global package literally named "error" used to be read
    # as a registry failure, retried, and its update swallowed.
    $npmDir = Join-Path $current.Box 'npm-error-package'
    New-NpmStub $npmDir '{"error":{"current":"1.0.0","wanted":"1.1.0","latest":"1.1.0","dependent":"global","location":"global"}}' 1
    $r = Invoke-Check (Get-StandardArgs $current -WithNpm) ($npmDir + ';' + $BarePath)
    $report = Get-Report $current
    Assert-True 'a package named error is an UPDATE like any other (exit 1)' ($r.Exit -eq 1 -and $report -match '- error : 1\.0\.0 -> \*\*1\.1\.0\*\*  \[UPDATE\]') "exit [$($r.Exit)]; $report"
    Assert-True 'and is not mistaken for a registry failure' ($report -cnotmatch 'answered an error') $report

    $npmDir = Join-Path $current.Box 'npm-error'
    New-NpmStub $npmDir '{"error":{"code":"E503","summary":"registry unavailable"}}' 1
    $r = Invoke-Check (Get-StandardArgs $current -WithNpm) ($npmDir + ';' + $BarePath)
    Assert-True 'a registry error twice is could-not-check (exit 2), naming the summary' ($r.Exit -eq 2 -and (Get-Report $current) -match 'COULD NOT CHECK: npm answered an error twice: registry unavailable') $r.Out

    $npmDir = Join-Path $current.Box 'npm-garbage'
    New-NpmStub $npmDir 'not json at all' 0
    $r = Invoke-Check (Get-StandardArgs $current -WithNpm) ($npmDir + ';' + $BarePath)
    Assert-True 'an unreadable npm answer is could-not-check (exit 2)' ($r.Exit -eq 2 -and (Get-Report $current) -match 'COULD NOT READ the answer of npm outdated') $r.Out

    $r = Invoke-Check (Get-StandardArgs $current -WithNpm) $BarePath
    Assert-True 'npm off the PATH is could-not-check (exit 2), not everything current' ($r.Exit -eq 2 -and (Get-Report $current) -match 'COULD NOT CHECK: npm is not on this PATH') $r.Out
}
finally {
    foreach ($d in $script:Temps) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
