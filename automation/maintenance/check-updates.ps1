<#
  check-updates.ps1

  READ-ONLY scan of what is installed versus what is available. It applies
  NOTHING to what is installed: it reads versions and writes a dated report. The
  one thing it writes outside that report folder is the marketplace catalogue
  cache, refreshed through the CLI's own command so that the comparison is against
  today's catalogue; -SkipMarketplaceRefresh leaves the cache alone and the report
  says so. Applying an update stays a deliberate act, taken while looking at the
  report.

  That separation is the whole design. An updater that both detects and applies
  will, sooner or later, apply something on a day you were not paying attention -
  and the first you hear of it is a pinned dependency that stopped being pinned.

  Two surfaces:

  - Agent plugins. The agent's own CLI lists what is installed and where each
    marketplace lives; every installed plugin is then compared with its catalogue
    on disk - by version when the catalogue declares one, by pinned commit when it
    declares only that. A pin that moved behind an unchanged version string is still
    reported as an update, and the report says how to take it, because the CLI's own
    update command compares version strings only (measured 2026-09-20). The
    catalogue refresh named above happens before the comparison.
  - Global npm packages, through `npm outdated -g --json`.

  Sandboxed host. A Store-packaged application keeps its CLI inside the package,
  off PATH, one folder per CLI version. The script looks on PATH first, then in
  the package cache, and takes the highest version that has the executable. A path
  given with -ClaudeCli wins and is not guessed around: a wrong path is reported
  as could-not-check, never taken as an invitation to look elsewhere.

  Exit codes follow the house contract. 0: every surface was checked and is
  current. 1: at least one finding, printed - an update, or a plugin that its
  marketplace no longer lists. 2: at least one surface could not be checked, also
  printed; the report is still written. 2 wins over 1, because a partial run must
  never read as a clean one; the counts on stdout say what was found anyway.

  Run it from inside an agent session if your host application is sandboxed:
  a process outside that sandbox sees a different set of global packages, and
  reports "not installed" for things that are.

  ASCII-only and dependency-free for Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$ReportRoot,
    [string]$ClaudeCli,
    [string]$PluginsRoot,
    [string]$PackageRoot,
    [switch]$SkipMarketplaceRefresh,
    [switch]$SkipNpm
)

$ErrorActionPreference = 'Continue'

# Windows PowerShell 5.1: with [CmdletBinding()], $PSScriptRoot is EMPTY inside the
# param() block and populated in the body. Defaults are resolved here.
if ([string]::IsNullOrEmpty($ReportRoot))  { $ReportRoot  = Join-Path $env:USERPROFILE '.claude\maintenance' }
if ([string]::IsNullOrEmpty($PluginsRoot)) { $PluginsRoot = Join-Path $env:USERPROFILE '.claude\plugins' }
if ([string]::IsNullOrEmpty($PackageRoot)) { $PackageRoot = Join-Path $env:LOCALAPPDATA 'Packages' }

$today  = Get-Date -Format 'yyyy-MM-dd'
$report = Join-Path $ReportRoot "updates-$today.md"
$latest = Join-Path $ReportRoot 'updates-latest.md'

$script:lines    = @()
$script:updates  = 0   # a newer version or commit is available
$script:findings = 0   # something else the reader has to decide on
$script:couldNot = 0   # a surface that was not exercised
$script:fallbackParses = 0   # JSON texts the 5.1 parser refused and the .NET serializer read
$script:droppedKeys    = 0   # keys differing only by case that the rebuild kept once

function Add-Line     { param([string]$Text) $script:lines += $Text }
function Add-Update   { param([string]$Text) $script:updates++;  $script:lines += $Text }
function Add-Finding  { param([string]$Text) $script:findings++; $script:lines += $Text }
function Add-CouldNot { param([string]$Text) $script:couldNot++; $script:lines += $Text }

function Get-Field {
    # Property access that answers $null when the object is not an object or the
    # property is not there, instead of throwing or guessing.
    param($Object, [string]$Name)
    if ($null -eq $Object -or $Object -is [string]) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertTo-PSObjectTree {
    # Dictionaries and lists from the .NET serializer, rebuilt as the objects
    # ConvertFrom-Json would have produced, so the rest of the script walks one shape.
    param($Node)
    if ($Node -is [System.Collections.IDictionary]) {
        $object = New-Object PSObject
        foreach ($key in $Node.Keys) {
            # PSObject property names are case-insensitive: the first spelling enumerated
            # wins (a Dictionary's order is not contractual), and the loss is counted so
            # that the report can name it instead of dropping keys in silence.
            if ($null -ne $object.PSObject.Properties[$key]) { $script:droppedKeys++; continue }
            $object | Add-Member -MemberType NoteProperty -Name $key -Value (ConvertTo-PSObjectTree $Node[$key])
        }
        return $object
    }
    if (($Node -is [System.Collections.IList]) -and ($Node -isnot [string])) {
        $list = @()
        foreach ($item in $Node) { $list += ,(ConvertTo-PSObjectTree $item) }
        return ,$list
    }
    return $Node
}

function ConvertFrom-JsonTolerant {
    param([string]$Text)
    try { return ,($Text | ConvertFrom-Json -ErrorAction Stop) }
    catch {
        # Windows PowerShell 5.1 rejects an object whose keys differ only by case. One
        # public catalogue carries exactly that - '.c' and '.C' in a language map,
        # measured 2026-09-20 - and an earlier version of this script swallowed the
        # error and reported that marketplace's plugins as "not comparable", when the
        # fact was "could not read". The .NET serializer is case-sensitive and reads
        # the file; the result is rebuilt first-spelling-wins so it walks like the rest.
        $first = $_.Exception.Message
        try {
            Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
            $script:fallbackParses++
            $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
            $serializer.MaxJsonLength = [int]::MaxValue
            return ,(ConvertTo-PSObjectTree ($serializer.DeserializeObject($Text)))
        }
        catch { throw "not valid JSON for either parser ($first)" }
    }
}

function Read-JsonFile {
    param([string]$Path)
    # ReadAllText honours a byte order mark and defaults to UTF-8; Get-Content on 5.1
    # reads a BOM-less file through the ANSI code page.
    return ,(ConvertFrom-JsonTolerant ([IO.File]::ReadAllText($Path)))
}

function Invoke-Cli {
    # Runs the agent CLI keeping stdout apart from stderr. Ran is $false when the
    # executable could not be started at all, which is a different fact from a
    # non-zero exit.
    param([string]$Path, [string[]]$Arguments)
    $global:LASTEXITCODE = $null
    $stdout = @()
    $stderr = @()
    try {
        foreach ($item in @(& $Path @Arguments 2>&1)) {
            if ($item -is [System.Management.Automation.ErrorRecord]) { $stderr += $item.ToString() }
            else { $stdout += [string]$item }
        }
    }
    catch {
        return [pscustomobject]@{ Ran = $false; Code = -1; Out = ''; Err = $_.Exception.Message }
    }
    $code = $global:LASTEXITCODE
    if ($null -eq $code) { $code = -1 }
    return [pscustomobject]@{ Ran = $true; Code = $code; Out = ($stdout -join "`n"); Err = ($stderr -join ' | ') }
}

function Get-Complaint {
    # The first line the CLI said, for a report line; stderr before stdout.
    param($Result)
    $text = $Result.Err
    if ([string]::IsNullOrWhiteSpace($text)) { $text = $Result.Out }
    if ([string]::IsNullOrWhiteSpace($text)) { return 'no output' }
    $line = (($text.Trim()) -split "`r?`n")[0]
    if ($line.Length -gt 200) { $line = $line.Substring(0, 200) + '...' }
    return $line
}

function Get-ShortCommit {
    param([string]$Commit)
    if ($Commit.Length -gt 7) { return $Commit.Substring(0, 7) }
    return $Commit
}

function Get-SourceDescription {
    param($Source)
    if ($null -eq $Source) { return 'no source' }
    if ($Source -is [string]) { return "relative path $Source" }
    $kind = [string](Get-Field $Source 'source')
    if ([string]::IsNullOrEmpty($kind)) { return 'source of unknown kind' }
    return "source of kind $kind"
}

function Resolve-Cli {
    if (-not [string]::IsNullOrEmpty($ClaudeCli)) {
        if (Test-Path -LiteralPath $ClaudeCli -PathType Leaf) {
            return [pscustomobject]@{ Path = $ClaudeCli; How = 'given with -ClaudeCli' }
        }
        return [pscustomobject]@{ Path = $null; How = "nothing at the path given with -ClaudeCli: $ClaudeCli" }
    }
    $command = Get-Command claude -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $source = $command.Source
        if ([string]::IsNullOrEmpty($source)) { $source = $command.Name }
        return [pscustomobject]@{ Path = $source; How = 'found on PATH' }
    }
    # Sandboxed host: the package keeps one folder per CLI version under its private,
    # redirected roaming folder. Layout as measured on a Store-packaged install in
    # 2026-09; if the vendor moves it, pass -ClaudeCli. Only the vendor's package
    # folders are searched - their name starts with the product name, and the publisher
    # hash after the underscore is not hard-coded - because every package on the machine
    # can write under this root, and the highest version anywhere is not the CLI.
    $best = $null
    $bestVersion = $null
    if (Test-Path -LiteralPath $PackageRoot -PathType Container) {
        foreach ($package in @(Get-ChildItem -LiteralPath $PackageRoot -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue)) {
            $cliRoot = Join-Path $package.FullName 'LocalCache\Roaming\Claude\claude-code'
            if (-not (Test-Path -LiteralPath $cliRoot -PathType Container)) { continue }
            foreach ($folder in @(Get-ChildItem -LiteralPath $cliRoot -Directory -ErrorAction SilentlyContinue)) {
                $candidate = Join-Path $folder.FullName 'claude.exe'
                if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
                # Numeric, not lexical: as text, '1.10.0' sorts before '1.9.0'.
                $version = $null
                if (-not [version]::TryParse($folder.Name, [ref]$version)) { continue }
                if ($null -eq $bestVersion -or $version -gt $bestVersion) {
                    $bestVersion = $version
                    $best = $candidate
                }
            }
        }
    }
    if ($null -ne $best) {
        return [pscustomobject]@{ Path = $best; How = 'found in the package cache, highest version present' }
    }
    return [pscustomobject]@{ Path = $null; How = "not on PATH, and no package cache with it under $PackageRoot" }
}

$script:catalogues = @{}
function Get-Catalogue {
    # The catalogue of one marketplace, read once. Data is $null whenever Error is set.
    param([string]$Name, [string]$Location)
    if ($script:catalogues.ContainsKey($Name)) { return $script:catalogues[$Name] }
    $result = [pscustomobject]@{ Data = $null; Error = $null }
    if ([string]::IsNullOrEmpty($Location)) {
        $result.Error = 'the marketplace list gives no install location for it'
    }
    else {
        $manifest = Join-Path $Location '.claude-plugin\marketplace.json'
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
            $result.Error = "no marketplace.json at $manifest"
        }
        else {
            $fallbackBefore = $script:fallbackParses
            $droppedBefore = $script:droppedKeys
            try { $result.Data = Read-JsonFile $manifest }
            catch { $result.Error = $_.Exception.Message }
            if ($null -eq $result.Error -and $script:fallbackParses -gt $fallbackBefore) {
                $dropped = $script:droppedKeys - $droppedBefore
                Add-Line "- note: the catalogue of '$Name' needed the fallback parser; $dropped key(s) differing only by case dropped, first spelling kept."
            }
        }
    }
    $script:catalogues[$Name] = $result
    return $result
}

function Get-InstalledCommit {
    # The commit the CLI recorded at install, from its own record: the list command
    # does not carry it. Prefers the entry of the same scope.
    param($Records, [string]$Id, [string]$Scope)
    $entries = Get-Field $Records $Id
    if ($null -eq $entries) { return $null }
    $fallback = $null
    foreach ($entry in @($entries)) {
        $commit = [string](Get-Field $entry 'gitCommitSha')
        if ([string]::IsNullOrEmpty($commit)) { continue }
        if ([string](Get-Field $entry 'scope') -eq $Scope) { return $commit }
        if ($null -eq $fallback) { $fallback = $commit }
    }
    return $fallback
}

function Test-NpmErrorShape {
    # npm reports a failure as {"error":{"code":...,"summary":...}}; a package entry has
    # current/wanted/latest. Read by shape, not by the key's name: a global package may be
    # literally named "error" (reviewer's case, 2026-09-20).
    param($Answer)
    $failure = Get-Field $Answer 'error'
    if ($null -eq $failure -or $failure -is [string]) { return $false }
    if ($null -ne (Get-Field $failure 'current') -or $null -ne (Get-Field $failure 'latest')) { return $false }
    return (($null -ne (Get-Field $failure 'code')) -or ($null -ne (Get-Field $failure 'summary')))
}

Add-Line "# Update report - $today"
Add-Line ''
Add-Line 'Read-only scan. **Nothing was applied.** Apply deliberately, from the list below.'
Add-Line ''

# --- Agent plugins -----------------------------------------------------------
Add-Line '## Agent plugins'
$cli = Resolve-Cli
if ($null -eq $cli.Path) {
    Add-CouldNot "- COULD NOT CHECK: the agent CLI was $($cli.How)."
}
else {
    Add-Line "- CLI: $($cli.Path) ($($cli.How))"
    $cliRuns = $true

    if ($SkipMarketplaceRefresh) {
        Add-Line '- catalogues: not refreshed, on request (-SkipMarketplaceRefresh); compared against the cached copies.'
    }
    else {
        $refresh = Invoke-Cli -Path $cli.Path -Arguments @('plugin', 'marketplace', 'update')
        if (-not $refresh.Ran) {
            Add-CouldNot "- COULD NOT RUN the CLI: $($refresh.Err)"
            $cliRuns = $false
        }
        elseif ($refresh.Code -eq 0) {
            Add-Line '- catalogues: refreshed.'
        }
        else {
            Add-CouldNot "- COULD NOT REFRESH the catalogues (exit $($refresh.Code)): $(Get-Complaint $refresh). Compared against the cached copies."
        }
    }

    $marketplaces = $null
    if ($cliRuns) {
        $listing = Invoke-Cli -Path $cli.Path -Arguments @('plugin', 'marketplace', 'list', '--json')
        if (-not $listing.Ran) {
            Add-CouldNot "- COULD NOT RUN the CLI: $($listing.Err)"
            $cliRuns = $false
        }
        elseif ($listing.Code -ne 0) {
            Add-CouldNot "- COULD NOT LIST the marketplaces (exit $($listing.Code)): $(Get-Complaint $listing)"
        }
        else {
            # Assign, then wrap: @(f) around a function that protects its array with the
            # comma operator collects that array as ONE element, and a two-plugin list
            # walked as one nameless plugin (found by the suite on 2026-09-20).
            try { $parsed = ConvertFrom-JsonTolerant $listing.Out; $marketplaces = @($parsed) }
            catch { Add-CouldNot "- COULD NOT READ the marketplace list: $($_.Exception.Message)" }
        }
    }

    $installed = $null
    if ($cliRuns) {
        $listing = Invoke-Cli -Path $cli.Path -Arguments @('plugin', 'list', '--json')
        if (-not $listing.Ran) {
            Add-CouldNot "- COULD NOT RUN the CLI: $($listing.Err)"
        }
        elseif ($listing.Code -ne 0) {
            Add-CouldNot "- COULD NOT LIST the installed plugins (exit $($listing.Code)): $(Get-Complaint $listing)"
        }
        else {
            try { $parsed = ConvertFrom-JsonTolerant $listing.Out; $installed = @($parsed) }
            catch { Add-CouldNot "- COULD NOT READ the installed list: $($_.Exception.Message)" }
        }
    }

    if ($null -ne $installed) {
        if ($installed.Count -eq 0) { Add-Line '- no plugins are installed.' }

        # The pinned commit of each installed plugin lives in the CLI's own record, not
        # in its list output. It is needed only for a catalogue that pins a commit and
        # declares no version, so a missing record is reported per plugin, where it bites.
        $records = $null
        $recordsComplaint = ''
        $recordPath = Join-Path $PluginsRoot 'installed_plugins.json'
        if (Test-Path -LiteralPath $recordPath -PathType Leaf) {
            try { $records = Get-Field (Read-JsonFile $recordPath) 'plugins' }
            catch { $recordsComplaint = "$recordPath could not be read: $($_.Exception.Message)" }
            if ($null -eq $records -and [string]::IsNullOrEmpty($recordsComplaint)) {
                $recordsComplaint = "$recordPath has no plugins section"
            }
        }
        else {
            $recordsComplaint = "no installed_plugins.json under $PluginsRoot"
        }

        foreach ($plugin in $installed) {
            $id = [string](Get-Field $plugin 'id')
            $installedVersion = [string](Get-Field $plugin 'version')
            $scope = [string](Get-Field $plugin 'scope')
            $label = "- $id : $installedVersion"
            if (-not [string]::IsNullOrEmpty($scope) -and $scope -ne 'user') { $label += " [$scope]" }
            if ((Get-Field $plugin 'enabled') -eq $false) { $label += ' (disabled)' }

            $at = $id.LastIndexOf('@')
            if ($at -lt 1 -or $at -eq ($id.Length - 1)) {
                Add-Finding "$label  NOT ATTRIBUTABLE - the id names no marketplace."
                continue
            }
            $name = $id.Substring(0, $at)
            $marketplaceName = $id.Substring($at + 1)

            if ($null -eq $marketplaces) {
                Add-CouldNot "$label  COULD NOT COMPARE - the marketplace list was not available (see above)."
                continue
            }
            $marketplace = $null
            foreach ($candidate in $marketplaces) {
                if ([string](Get-Field $candidate 'name') -eq $marketplaceName) { $marketplace = $candidate; break }
            }
            if ($null -eq $marketplace) {
                Add-Finding "$label  MARKETPLACE '$marketplaceName' IS NOT CONFIGURED - it cannot be updated from here; add the marketplace back, or uninstall."
                continue
            }

            $catalogue = Get-Catalogue -Name $marketplaceName -Location ([string](Get-Field $marketplace 'installLocation'))
            if ($null -ne $catalogue.Error) {
                Add-CouldNot "$label  COULD NOT COMPARE - the catalogue of '$marketplaceName' is unreadable: $($catalogue.Error)"
                continue
            }
            # Test the field before wrapping it: @($null) has one element, so a catalogue
            # with no plugins section would walk once with a null candidate and report the
            # plugin as dropped (class 1) where the fact is could-not-compare (class 2).
            $pluginList = Get-Field $catalogue.Data 'plugins'
            if ($null -eq $pluginList) {
                Add-CouldNot "$label  COULD NOT COMPARE - the catalogue of '$marketplaceName' has no plugins section."
                continue
            }
            $entry = $null
            foreach ($candidate in @($pluginList)) {
                if ([string](Get-Field $candidate 'name') -eq $name) { $entry = $candidate; break }
            }
            if ($null -eq $entry) {
                Add-Finding "$label  NOT IN CATALOGUE - '$marketplaceName' no longer lists it; decide whether the installed copy stays."
                continue
            }

            $catalogueVersion = [string](Get-Field $entry 'version')
            if (-not [string]::IsNullOrEmpty($catalogueVersion)) {
                if ($catalogueVersion -eq $installedVersion) { Add-Line "$label  (current)" }
                else { Add-Update "$label -> **$catalogueVersion**  [UPDATE]" }
                continue
            }

            $source = Get-Field $entry 'source'
            $pinned = [string](Get-Field $source 'sha')
            if (-not [string]::IsNullOrEmpty($pinned)) {
                $installedCommit = Get-InstalledCommit -Records $records -Id $id -Scope $scope
                if ([string]::IsNullOrEmpty($installedCommit)) {
                    if ([string]::IsNullOrEmpty($recordsComplaint)) { $recordsComplaint = "$recordPath records no commit for $id" }
                    Add-CouldNot "$label  COULD NOT COMPARE - the catalogue pins a commit and the installed commit is unknown: $recordsComplaint"
                    continue
                }
                if ($installedCommit -eq $pinned) {
                    Add-Line "$label  (current; no version in the catalogue, compared by pinned commit $(Get-ShortCommit $pinned))"
                }
                else {
                    Add-Update "$label  commit $(Get-ShortCommit $installedCommit) -> **$(Get-ShortCommit $pinned)**  [UPDATE] - no version in the catalogue, compared by pinned commit; 'plugin update' answers up to date while the version string is unchanged, so take it with uninstall, then install (measured 2026-09-20)"
                }
                continue
            }

            Add-CouldNot "$label  COULD NOT COMPARE - the catalogue declares neither a version nor a pinned commit for it ($(Get-SourceDescription $source))."
        }
    }
}
Add-Line ''

# --- Global npm packages -----------------------------------------------------
Add-Line '## Global npm packages'
if ($SkipNpm) {
    Add-Line '- skipped on request (-SkipNpm).'
}
elseif ($null -eq (Get-Command npm -ErrorAction SilentlyContinue)) {
    # Family 2: a check that could not run is not a check that passed.
    Add-CouldNot '- COULD NOT CHECK: npm is not on this PATH.'
}
else {
    # --json, not --parseable: the parseable form is colon-delimited and a Windows path
    # carries a colon after the drive letter, so splitting on ':' put the path where
    # the version should be (measured 2026-09-20). npm exits 1 when something IS
    # outdated, so the exit code alone decides nothing: stdout and stderr are kept
    # apart, an empty stdout is "everything current" only when npm also exited 0, and
    # otherwise it is could-not-check naming the first stderr line (a shim, or node
    # failing before JSON mode, says nothing on stdout). One retry when npm answers its
    # own error object, recognised by shape and never by the substring "error".
    $attempts = 2
    $answer = $null
    $outdated = $null
    $readError = ''
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $answer = Invoke-Cli -Path 'npm' -Arguments @('outdated', '-g', '--json')
        $outdated = $null
        $readError = ''
        if ($answer.Ran -and -not [string]::IsNullOrWhiteSpace($answer.Out) -and $answer.Out.Trim() -ne '{}') {
            try { $outdated = ConvertFrom-JsonTolerant $answer.Out.Trim() }
            catch { $readError = $_.Exception.Message }
        }
        $registryError = ($null -ne $outdated) -and (Test-NpmErrorShape $outdated)
        if (-not $registryError) { break }
        if ($attempt -lt $attempts) { Start-Sleep -Seconds 3 }
    }
    if (-not $answer.Ran) {
        Add-CouldNot "- COULD NOT CHECK: npm could not be started: $($answer.Err)"
    }
    elseif ([string]::IsNullOrWhiteSpace($answer.Out)) {
        if ($answer.Code -eq 0) { Add-Line '- everything current.' }
        else { Add-CouldNot "- COULD NOT CHECK: npm exited $($answer.Code) with nothing on stdout: $(Get-Complaint $answer)" }
    }
    elseif ($answer.Out.Trim() -eq '{}') {
        Add-Line '- everything current.'
    }
    elseif ($null -eq $outdated) {
        Add-CouldNot "- COULD NOT READ the answer of npm outdated: $readError"
    }
    elseif (Test-NpmErrorShape $outdated) {
        $failure = Get-Field $outdated 'error'
        $summary = [string](Get-Field $failure 'summary')
        if ([string]::IsNullOrEmpty($summary)) { $summary = [string](Get-Field $failure 'code') }
        Add-CouldNot "- COULD NOT CHECK: npm answered an error twice: $summary"
    }
    else {
        $any = $false
        foreach ($property in @($outdated.PSObject.Properties)) {
            $current = [string](Get-Field $property.Value 'current')
            $newest  = [string](Get-Field $property.Value 'latest')
            if ([string]::IsNullOrEmpty($newest)) { continue }
            Add-Update "- $($property.Name) : $current -> **$newest**  [UPDATE]"
            $any = $true
        }
        if (-not $any) { Add-Line '- everything current.' }
    }
}
Add-Line ''

# --- Tools you pinned on purpose ---------------------------------------------
Add-Line '## Pinned on purpose - do not bump without deciding'
Add-Line ''
Add-Line 'List your pinned tools here, with the reason and the issue link. A pin whose'
Add-Line 'reason nobody remembers gets "helpfully" upgraded within two maintenance runs.'
Add-Line ''

# --- What to do next ----------------------------------------------------------
Add-Line '## Applying'
Add-Line ''
Add-Line 'Nothing above has been applied. Update one thing at a time, run your test suite'
Add-Line 'after each, and write down anything that had to be pinned and why.'
Add-Line ''
Add-Line 'Plugins update one at a time, and the application has to be restarted afterwards:'
Add-Line ''
Add-Line '    <cli> plugin update <name>@<marketplace>'
Add-Line ''
Add-Line 'A moved pinned commit behind the same version string is not taken by that command:'
Add-Line 'uninstall, then install, then disable again if the plugin was disabled - the install'
Add-Line 'enables it and rewrites settings.json with the keys reordered.'
Add-Line ''
Add-Line 'On a sandboxed host the CLI is not on PATH: <cli> is the path printed under CLI above.'
Add-Line ''
Add-Line '---'
Add-Line "Updates available: $script:updates | Other findings: $script:findings | Could not check: $script:couldNot"

try {
    New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($report, (($script:lines -join [Environment]::NewLine) + [Environment]::NewLine), $utf8)
    [IO.File]::Copy($report, $latest, $true)
}
catch {
    Write-Output "COULD NOT WRITE the report under ${ReportRoot}: $($_.Exception.Message)"
    Write-Output ($script:lines -join [Environment]::NewLine)
    exit 2
}

Write-Output "Update report written: $report"
Write-Output "Updates available: $script:updates"
Write-Output "Other findings: $script:findings"
Write-Output "Could not check: $script:couldNot"
Write-Output 'Nothing was applied.'

if ($script:couldNot -gt 0) { exit 2 }
if (($script:updates + $script:findings) -gt 0) { exit 1 }
exit 0
