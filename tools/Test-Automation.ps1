<#
  Test-Automation.ps1

  Behavioural tests for the hooks: they are fed real events on stdin and judged
  by their exit codes and output. A hook asserted only by reading its source is
  a hook nobody proved fires.
#>
[CmdletBinding()]
param(
    [string]$AutomationRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1: with [CmdletBinding()], $PSScriptRoot is EMPTY inside the
# param() block and populated in the body. Resolve defaults here, never up there.
if ([string]::IsNullOrEmpty($AutomationRoot)) {
    $AutomationRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'automation'
}

$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { $script:Pass++; Write-Output "  PASS  $Name" }
    else            { $script:Fail++; Write-Output "  FAIL  $Name" }
}

function Get-Text {
    param([string]$Relative)
    $path = Join-Path $AutomationRoot $Relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
}

function Invoke-HookWithEvent {
    param([string]$Relative, [string]$Json)

    $hook = Join-Path $AutomationRoot $Relative
    if (-not (Test-Path -LiteralPath $hook -PathType Leaf)) {
        return [pscustomobject]@{ Code = -1; Text = "hook not found: $hook" }
    }

    $eventFile = Join-Path $env:TEMP ('evt-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
    # NOT Set-Content -Encoding UTF8: on Windows PowerShell 5.1 that writes a BOM,
    # ConvertFrom-Json rejects it, and every hook then exits 2 "could not parse" -
    # which made the blocking assertions pass for entirely the wrong reason.
    [IO.File]::WriteAllText($eventFile, $Json)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & cmd /c "type `"$eventFile`" | powershell -NoProfile -ExecutionPolicy Bypass -File `"$hook`"" 2>&1
        return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($out -join "`n") }
    }
    finally {
        $ErrorActionPreference = $previous
        Remove-Item -LiteralPath $eventFile -Force -ErrorAction SilentlyContinue
    }
}

function New-Event {
    param([string]$Command, [string]$ToolName = 'Bash')
    $payload = @{
        hook_event_name = 'PreToolUse'
        tool_name       = $ToolName
        cwd             = $env:TEMP
        tool_input      = @{ command = $Command }
    }
    return ($payload | ConvertTo-Json -Depth 5 -Compress)
}

Write-Output 'Group 1 - the git guardrail blocks what it enumerates'

$blocked = @(
    'git push --force origin main',
    'git push --force-with-lease',
    'git reset --hard HEAD~1',
    'git clean -fd',
    'git branch -D feature',
    'git checkout -- .',
    'git -C some/repo reset --hard'
)
foreach ($command in $blocked) {
    $result = Invoke-HookWithEvent -Relative 'hooks\block-dangerous-git.ps1' -Json (New-Event -Command $command)
    Assert-True "blocks: $command" ($result.Code -eq 2)
}

$allowed = @(
    'git status',
    'git push origin main',
    'git commit -m "ordinary work"',
    'git log --oneline -5',
    'echo forced nothing here'
)
foreach ($command in $allowed) {
    $result = Invoke-HookWithEvent -Relative 'hooks\block-dangerous-git.ps1' -Json (New-Event -Command $command)
    Assert-True "allows: $command" ($result.Code -eq 0)
}

# A guardrail that cannot read its event must not wave the command through.
$result = Invoke-HookWithEvent -Relative 'hooks\block-dangerous-git.ps1' -Json 'this is not json'
Assert-True 'malformed event is blocked, not allowed' ($result.Code -eq 2)

# Regression: a byte order mark in front of the event used to make ConvertFrom-Json
# fail, so EVERY command came back blocked - and the blocking assertions above passed
# for the wrong reason while the allowing ones failed. The hook strips it now.
$bom = [string][char]0xFEFF
$result = Invoke-HookWithEvent -Relative 'hooks\block-dangerous-git.ps1' -Json ($bom + (New-Event -Command 'git status'))
Assert-True 'a BOM-prefixed event is still parsed, not blocked' ($result.Code -eq 0)
$result = Invoke-HookWithEvent -Relative 'hooks\block-dangerous-git.ps1' -Json ($bom + (New-Event -Command 'git reset --hard'))
Assert-True 'a BOM-prefixed event is still matched on content' ($result.Code -eq 2)

Write-Output 'Group 2 - the review reminder is advisory and never blocks'

foreach ($command in @('git status', 'ls -la', 'git commit -m "checkpoint: wip"')) {
    $result = Invoke-HookWithEvent -Relative 'hooks\review-before-commit.ps1' -Json (New-Event -Command $command)
    Assert-True "advisory exit 0: $command" ($result.Code -eq 0)
}
$result = Invoke-HookWithEvent -Relative 'hooks\review-before-commit.ps1' -Json 'not json at all'
Assert-True 'malformed event never blocks an advisory hook' ($result.Code -eq 0)

Write-Output 'Group 3 - session-start injects, warns, and can be switched off'

$box = Join-Path $env:TEMP ('sess-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $box 'maintenance') -Force | Out-Null
$hook = Join-Path $AutomationRoot 'hooks\session-start.ps1'

function Invoke-SessionStart {
    param([hashtable]$Arguments)
    if (-not (Test-Path -LiteralPath $hook -PathType Leaf)) { return 'hook not found' }
    $list = @()
    foreach ($key in $Arguments.Keys) { $list += "-$key"; $list += $Arguments[$key] }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { return ((& powershell -NoProfile -ExecutionPolicy Bypass -File $hook @list 2>&1) -join "`n") }
    finally { $ErrorActionPreference = $previous }
}

try {
    $lessons = Join-Path $box 'LESSONS.md'
    Set-Content -LiteralPath $lessons -Encoding UTF8 -Value @(
        '# Cross-cutting lessons',
        '',
        '## 1. First family title',
        'body',
        '## 2. Second family title',
        'body',
        '## 3. Third family title'
    )

    $output = Invoke-SessionStart -Arguments @{ MaintenanceRoot = (Join-Path $box 'maintenance'); LessonsPath = $lessons }
    Assert-True 'lesson titles are printed, not pointed at' ($output -match 'First family title' -and $output -match 'Third family title')
    Assert-True 'the family count is reported'              ($output -match '3 famil')

    # Silent loss is the failure this block exists to prevent: a configured path
    # that does not resolve must shout, not quietly skip.
    $output = Invoke-SessionStart -Arguments @{ MaintenanceRoot = (Join-Path $box 'maintenance'); LessonsPath = (Join-Path $box 'nowhere.md') }
    Assert-True 'a configured-but-missing lessons path warns' ($output -match '(?i)not found')

    # An unconfigured block is simply off, and says nothing at all.
    $output = Invoke-SessionStart -Arguments @{ MaintenanceRoot = (Join-Path $box 'maintenance') }
    Assert-True 'an unconfigured lessons block stays silent' ($output -notmatch '(?i)lesson')

    # An overdue marker produces a reminder; a fresh one does not.
    Set-Content -LiteralPath (Join-Path $box 'maintenance\last-run') -Value '2000-01-01' -Encoding UTF8
    $output = Invoke-SessionStart -Arguments @{ MaintenanceRoot = (Join-Path $box 'maintenance') }
    Assert-True 'an overdue marker reminds' ($output -match '(?i)overdue|REMINDER')

    Set-Content -LiteralPath (Join-Path $box 'maintenance\last-run') -Value (Get-Date -Format 'yyyy-MM-dd') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $box 'maintenance\updates-last-check') -Value (Get-Date -Format 'yyyy-MM-dd') -Encoding UTF8
    $output = Invoke-SessionStart -Arguments @{ MaintenanceRoot = (Join-Path $box 'maintenance') }
    Assert-True 'fresh markers say nothing' ([string]::IsNullOrWhiteSpace($output))

    # A fresh install has no maintenance folder yet. Skipping quietly there means the
    # block that exists to nag says nothing to the one person who needs it most.
    $output = Invoke-SessionStart -Arguments @{ MaintenanceRoot = (Join-Path $box 'no-such-folder') }
    Assert-True 'a missing maintenance folder warns rather than skipping' ($output -match '(?i)not found')

    # Block 3, configured and present but WITHOUT the section it looks for, must say so.
    # Until 2026-09-20 it printed nothing - the silent skip the two other blocks forbid.
    $index = Join-Path $box 'MEMORY.md'
    Set-Content -LiteralPath $index -Encoding UTF8 -Value @('# Index', '', '## Something else', '- [x](x.md) - not the section')
    $output = Invoke-SessionStart -Arguments @{ MaintenanceRoot = (Join-Path $box 'maintenance'); MemoryIndexPath = $index }
    Assert-True 'a memory index without the gotcha section warns' ($output -match '(?i)no .*section')

    Set-Content -LiteralPath $index -Encoding UTF8 -Value @('# Index', '', '## Tool gotchas', '- [tool](tool.md) - the gotcha')
    $output = Invoke-SessionStart -Arguments @{ MaintenanceRoot = (Join-Path $box 'maintenance'); MemoryIndexPath = $index }
    Assert-True 'a memory index with the section prints it' ($output -match 'the gotcha' -and $output -notmatch '(?i)no .*section')

    # The corrections counter must not shrink in silence: a line that starts with a
    # date but not with "- " is a lookalike, and lookalikes are named, not dropped.
    $log = Join-Path $box 'log.md'
    Set-Content -LiteralPath $log -Encoding UTF8 -Value @('# Log', '', '- 2026-01-01 counted one', '2026-01-02 lookalike, not counted', '- 2026-01-03 counted two')
    $output = Invoke-SessionStart -Arguments @{ MaintenanceRoot = (Join-Path $box 'maintenance'); LessonsPath = $lessons; CorrectionsLogPath = $log }
    Assert-True 'the counter reports the conforming entries' ($output -match 'corrections log: 2 line')
    Assert-True 'and names the lookalike instead of hiding it' ($output -match '1 line\(s\).*start with a date but not')
}
finally { Remove-Item -LiteralPath $box -Recurse -Force -ErrorAction SilentlyContinue }

Write-Output 'Group 4 - hooks ship ASCII-only and parse on 5.1'

foreach ($name in @('block-dangerous-git.ps1', 'review-before-commit.ps1', 'session-start.ps1')) {
    $path = Join-Path $AutomationRoot "hooks\$name"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $nonAscii = @([IO.File]::ReadAllBytes($path) | Where-Object { $_ -gt 127 }).Count
        Assert-True "ascii-only: $name" ($nonAscii -eq 0)

        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$parseErrors) | Out-Null
        Assert-True "parses: $name" ($null -eq $parseErrors -or $parseErrors.Count -eq 0)
    }
    else {
        Assert-True "ascii-only: $name (file missing)" $false
        Assert-True "parses: $name (file missing)"     $false
    }
}

$readme = Get-Text 'hooks\README.md'
Assert-True 'hooks README exists' ($readme.Length -gt 0)
Assert-True 'the README shows the settings wiring' ($readme -match '(?i)PreToolUse' -and $readme -match '(?i)SessionStart')

Write-Output 'Group 5 - maintenance, triggers and verification'

$backup = Get-Text 'maintenance\backup-config.ps1'
Assert-True 'backup script exists' ($backup.Length -gt 0)
# The whole point of this script is that it does not guess the failure mode.
foreach ($mode in @('DIVERGENCE', 'NETWORK', 'AUTHENTICATION', 'NOT CLASSIFIED')) {
    Assert-True "push failure mode classified: $mode" ($backup -match [regex]::Escape($mode))
}
# The fetch must come BEFORE the sync script is invoked, not after the push fails: by
# then the mirror has already overwritten the tree. Order is asserted on the source
# because this group reads source; a behavioural fixture with two clones belongs in
# a suite of its own (the private practice has one with 19 cases).
$fetchAt = $backup.IndexOf('fetch -q $Remote')
$syncAt  = $backup.IndexOf('& $SyncScript')
Assert-True 'the backup fetches before it mirrors'    ($fetchAt -ge 0 -and $syncAt -ge 0 -and $fetchAt -lt $syncAt)
Assert-True 'and stops when the remote is ahead'      ($backup -match 'BEHIND')

$routine = Get-Text 'maintenance\weekly-routine.md'
Assert-True 'the weekly routine is defined, not merely nagged about' ($routine.Length -gt 0)
# Its reason for existing, which is stronger than "documentation was missing".
Assert-True 'it states why it exists at all' ($routine -match '(?i)write-only|never fires')
# Each step must say which subsystem entails it, so the reader can delete the rest.
Assert-True 'steps are tied to the subsystems that entail them' (@([regex]::Matches($routine, '(?i)\(needs ')).Count -ge 4)
Assert-True 'the marker is stamped last'   ($routine -match '(?i)stamp the marker')
Assert-True 'could-not-run stays distinct from nothing-to-report' ($routine -match '(?i)could not (run|check)')

# A reminder that points at something undefined trains the reader to dismiss it.
$sessionStart = Get-Text 'hooks\session-start.ps1'
Assert-True 'the hook names the routine file' ($sessionStart -match 'weekly-routine\.md')

$updates = Get-Text 'maintenance\check-updates.ps1'
Assert-True 'update check exists' ($updates.Length -gt 0)
Assert-True 'the update check applies nothing' ($updates -match '(?i)nothing (was |is )?applied|read-only')

$triggers = Get-Text 'triggers.md'
Assert-True 'triggers doc exists' ($triggers.Length -gt 0)
foreach ($path in @('Task Scheduler', 'session-driven', 'scheduled-task')) {
    Assert-True "trigger path documented: $path" ($triggers -match [regex]::Escape($path))
}
# A path without a way to tell whether it applies to you is a path you cannot choose.
Assert-True 'each trigger path carries a detection test' (@([regex]::Matches($triggers, '(?i)how to tell')).Count -ge 3)

$verification = Get-Text 'verification\README.md'
Assert-True 'verification README exists' ($verification.Length -gt 0)
Assert-True 'the exit-code contract is stated'   ($verification -match '(?i)exit')
Assert-True 'snapshot-first is explained'        ($verification -match '(?i)snapshot')

foreach ($name in @('Invoke-Gitleaks.ps1', 'Assert-Baseline.ps1', 'Assert-NoControlBytes.ps1', 'Assert-MemoryLinks.ps1', 'Assert-PlanFreshness.ps1', 'Invoke-VaultLint.ps1')) {
    $path = Join-Path $AutomationRoot "verification\$name"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $nonAscii = @([IO.File]::ReadAllBytes($path) | Where-Object { $_ -gt 127 }).Count
        Assert-True "ascii-only: $name" ($nonAscii -eq 0)
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$parseErrors) | Out-Null
        Assert-True "parses: $name" ($null -eq $parseErrors -or $parseErrors.Count -eq 0)
    }
    else {
        Assert-True "ascii-only: $name (file missing)" $false
        Assert-True "parses: $name (file missing)"     $false
    }
}

# The gitleaks binary is not in CI, so the exit-code mapping is asserted on the source:
# gitleaks exits 1 for both a finding and a config failure, so the wrapper must split them
# with --exit-code 3 and never read a bare 1 as a finding. Measured on 2026-09-20.
$gitleaks = ((Get-Text 'verification\Invoke-Gitleaks.ps1') -replace '\s', '')
Assert-True 'gitleaks wrapper passes --exit-code 3' ($gitleaks -match "'--exit-code','3'")
Assert-True 'gitleaks wrapper treats exit 3 as the finding' ($gitleaks -match '\$code-eq3')
Assert-True 'gitleaks wrapper never treats a bare exit 1 as a finding' (-not ($gitleaks -match '\$code-eq1'))

Write-Output 'Group 6 - the vault schema ships empty'

$vaultRoot = Join-Path (Split-Path -Parent $AutomationRoot) 'vault'
function Get-VaultText {
    param([string]$Relative)
    $path = Join-Path $vaultRoot $Relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
}

$agents = Get-VaultText 'AGENTS.md.template'
Assert-True 'vault template exists' ($agents.Length -gt 0)
foreach ($section in @('Project Map', 'Wiki Page Format', 'Core Wiki Operations', 'Definition Of Done')) {
    Assert-True "vault section present: $section" ($agents -match [regex]::Escape($section))
}
foreach ($operation in @('ingest', 'Query', 'Lint', 'Synthesize', 'Challenge', 'Connect', 'Emerge')) {
    Assert-True "wiki operation documented: $operation" ($agents -match [regex]::Escape($operation))
}

$structure = Get-VaultText 'structure.md'
Assert-True 'vault structure doc exists' ($structure.Length -gt 0)
Assert-True 'the cloud-folder warning is present' ($structure -match '(?i)separate-git-dir')

$vaultReadme = Get-VaultText 'README.md'
Assert-True 'vault README exists' ($vaultReadme.Length -gt 0)
Assert-True 'the vault is distinguished from memory' ($vaultReadme -match '(?i)memory')

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
