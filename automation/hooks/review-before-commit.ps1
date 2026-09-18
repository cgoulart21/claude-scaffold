<#
  PreToolUse hook: a non-blocking review reminder before commits.

  Reads the hook event from stdin and emits additionalContext only when the
  target repository actually has something staged. Advisory by design: it never
  exits non-zero, because a reminder that can block unrelated work is a reminder
  people disable.

  ASCII-only and dependency-free for Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$LessonsPath,
    [string]$CorrectionsLogPath
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuration. Point these at your own files, or leave them empty to drop the
# second-occurrence question from the reminder.
# ---------------------------------------------------------------------------
$DefaultLessonsPath        = ''
$DefaultCorrectionsLogPath = ''
# ---------------------------------------------------------------------------

if ([string]::IsNullOrEmpty($LessonsPath))        { $LessonsPath        = $DefaultLessonsPath }
if ([string]::IsNullOrEmpty($CorrectionsLogPath)) { $CorrectionsLogPath = $DefaultCorrectionsLogPath }

try {
    $raw = [Console]::In.ReadToEnd()
    # Discard anything before the opening brace: ConvertFrom-Json rejects a leading byte
    # order mark, and a reminder that silently stops working is worse than no reminder.
    # Trimming U+FEFF is not enough - stdin is decoded in the console code page, so the
    # BOM arrives as characters you were not looking for.
    $start = $raw.IndexOf('{')
    if ($start -gt 0) { $raw = $raw.Substring($start) }
    $hookEvent = $raw | ConvertFrom-Json -ErrorAction Stop
    $command = [string] $hookEvent.tool_input.command
} catch {
    # Advisory: a malformed event must not block unrelated work.
    exit 0
}

if ([string]::IsNullOrWhiteSpace($command)) { exit 0 }

$gitPrefix = "(?i)(^|[\s&|;(<>)])(?:(?:[`"'][^`"']*[\\/])|(?:[^\s;&|<>]*[\\/])|[`"'])?git(?:\.exe)?[`"']?\s+"
if (-not [regex]::IsMatch($command, $gitPrefix + '[^;&|]*?\bcommit\b')) { exit 0 }
if ($command -match '(?i)checkpoint:|\bwip\b') { exit 0 }

$repoPath = [string] $hookEvent.cwd
if ([string]::IsNullOrWhiteSpace($repoPath)) { exit 0 }
try { $repoPath = [IO.Path]::GetFullPath($repoPath) } catch { exit 0 }
if ($repoPath.StartsWith('\\') -or -not (Test-Path -LiteralPath $repoPath -PathType Container)) { exit 0 }

# Follow a conservative "git -C <path>" prefix so the reminder describes the
# repository actually being committed to, not the one the shell happens to be in.
$gitC = $gitPrefix + "-C\s+(?:`"([^`"]+)`"|'([^']+)'|([^\s;&|]+))[^;&|]*?\bcommit\b"
$gitCMatch = [regex]::Match($command, $gitC)
if ($gitCMatch.Success) {
    $candidate = @(
        $gitCMatch.Groups[1].Value
        $gitCMatch.Groups[2].Value
        $gitCMatch.Groups[3].Value
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    if ($candidate) {
        if (-not [IO.Path]::IsPathRooted($candidate)) { $candidate = Join-Path $repoPath $candidate }
        try {
            $candidate = [IO.Path]::GetFullPath($candidate)
            if (-not $candidate.StartsWith('\\') -and (Test-Path -LiteralPath $candidate -PathType Container)) {
                $repoPath = $candidate
            }
        } catch {
            # Advisory: an invalid -C target simply produces no reminder.
        }
    }
}

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { exit 0 }

$inside = @(& $git.Source -c core.fsmonitor=false -C $repoPath rev-parse --is-inside-work-tree 2>$null)
if ($LASTEXITCODE -ne 0 -or $inside -notcontains 'true') { exit 0 }

$env:GIT_OPTIONAL_LOCKS = '0'
$gitSafeArgs = @('-c', 'core.fsmonitor=false', '-c', 'diff.external=', '-C', $repoPath)
$files = @(& $git.Source @gitSafeArgs diff --no-ext-diff --cached --name-only --diff-filter=ACMR 2>$null)

$commitAll = (
    $command -match '(?i)(^|\s)--all(?:[=\s]|$)' -or
    $command -match '(?i)(^|\s)-[a-z]*a[a-z]*(?:\s|$)'
)
if ($commitAll) {
    $files += @(& $git.Source @gitSafeArgs diff --no-ext-diff --name-only --diff-filter=ACMR 2>$null)
}

$codePattern = '\.(c|cc|cpp|cxx|h|hh|hpp|hxx|ino|py|pyi|js|mjs|cjs|jsx|ts|tsx|vue|svelte|html|htm|css|sh|bash|zsh|ps1|psm1|m|mm|rs|go|java|kt|kts|swift|cs|rb|php|pl|lua|sql|r|jl|scala|dart|groovy)$'

# Documents count for the second-occurrence question, not for code review. Without
# this the hook exited early on every commit without code - and in at least one
# practice the projects that generated the MOST lessons were document projects, so
# the anchor sat inert exactly where there was most to promote. Family 1: a hook
# that is installed is not a hook that fires in your case.
$docPattern = '\.(md|markdown|rst|org|txt|csv|tsv|tex|bib|docx|xlsx|pptx)$'

$code = @($files | Where-Object { $_ -match $codePattern } | Sort-Object -Unique)
$docs = @($files | Where-Object { $_ -match $docPattern } | Sort-Object -Unique)
if ($code.Count -eq 0 -and $docs.Count -eq 0) { exit 0 }

# The second-occurrence question applies to both cases; code review only makes
# sense when there is code. Telling someone to review a spreadsheet is the kind of
# noise that trains people to ignore the whole reminder.
$promotion = ''
if (-not [string]::IsNullOrEmpty($LessonsPath) -or -not [string]::IsNullOrEmpty($CorrectionsLogPath)) {
    $where = @()
    if (-not [string]::IsNullOrEmpty($LessonsPath))        { $where += $LessonsPath }
    if (-not [string]::IsNullOrEmpty($CorrectionsLogPath)) { $where += $CorrectionsLogPath }
    $promotion = (
        'And before you close: is anything you learned here a SECOND occurrence of a ' +
        'family in {0}? If so, promote it now - the end of a unit of work is the only ' +
        'moment you can still tell.'
    ) -f ($where -join ' or ')
}

if ($code.Count -gt 0) {
    $message = (
        '[review-before-commit] This commit touches {0} code file(s). Before committing: ' +
        'review the staged diff with effort proportional to risk, fix confirmed findings, ' +
        're-review once, and validate build and tests. Skip only for WIP or checkpoint ' +
        'commits, or when explicitly asked. {1}'
    ) -f $code.Count, $promotion
}
else {
    $message = (
        '[review-before-commit] This commit touches {0} document(s) and no code, so there ' +
        'is no code review to run. {1}'
    ) -f $docs.Count, $promotion
}

$output = @{
    hookSpecificOutput = @{
        hookEventName     = 'PreToolUse'
        additionalContext = $message.Trim()
    }
}
$output | ConvertTo-Json -Depth 4 -Compress
exit 0
