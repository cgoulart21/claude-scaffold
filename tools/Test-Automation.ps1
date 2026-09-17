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

Write-Output ''
Write-Output "PASS $script:Pass  FAIL $script:Fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
