<#
  SessionStart hook: puts three things in front of every session.

    1. Maintenance reminders, from dated marker files.
    2. Your cross-cutting lesson families - PRINTED, not pointed at.
    3. Your tool gotchas - PRINTED, not pointed at.

  Blocks 2 and 3 are the reason this file is worth having. An audit of one practice
  found eighteen separate rediscoveries, across eight projects, of a rule that was
  already written down in a file that was available and never read. Available is not
  read - which is family 1 applied to this very hook. So the titles are printed into
  the session, at a cost of a handful of lines, in exchange for the rule being in
  context before it bites instead of after.

  Deterministic and cheap: it only reads files. Nothing here executes a routine -
  the model does that, in session, when it sees the reminder.

  ASCII-only and dependency-free for Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
    [string]$MaintenanceRoot,
    [string]$LessonsPath,
    [string]$MemoryIndexPath,
    [string]$CorrectionsLogPath
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuration. Each block is independent: switch one off, or leave its path
# empty, and the others keep working.
# ---------------------------------------------------------------------------
$EnableMaintenanceReminders = $true
$EnableLessonInjection      = $true
$EnableMemoryInjection      = $true

$DefaultMaintenanceRoot    = (Join-Path $env:USERPROFILE '.claude\maintenance')
$DefaultLessonsPath        = ''    # e.g. C:\Path\To\knowledge\LESSONS.md
$DefaultMemoryIndexPath    = ''    # e.g. C:\Path\To\knowledge\memory\MEMORY.md
$DefaultCorrectionsLogPath = ''    # e.g. C:\Path\To\knowledge\corrections\log.md
# The corrections log default is empty like the other two knowledge files, and for the
# same reason: SCAFFOLD.md puts the three knowledge files in a repository of your own,
# never under the agent home. A default there would point at the place the guide says
# not to use, and until 2026-09-20 it did.

# Heading of the section in your memory index that holds tool gotchas. Only that
# section is printed: the rest of the index is actionable INSIDE a given project,
# not in any session, and printing it would be noise that trains people to skip the
# whole block.
$GotchaSectionHeading = 'Tool gotchas'

# Days after which each marker is considered overdue.
$WeeklyOverdueDays  = 7
$UpdatesOverdueDays = 14
# ---------------------------------------------------------------------------

if ([string]::IsNullOrEmpty($MaintenanceRoot))    { $MaintenanceRoot    = $DefaultMaintenanceRoot }
if ([string]::IsNullOrEmpty($LessonsPath))        { $LessonsPath        = $DefaultLessonsPath }
if ([string]::IsNullOrEmpty($MemoryIndexPath))    { $MemoryIndexPath    = $DefaultMemoryIndexPath }
if ([string]::IsNullOrEmpty($CorrectionsLogPath)) { $CorrectionsLogPath = $DefaultCorrectionsLogPath }

$messages = @()

function Get-MarkerAgeDays {
    param([string]$File)
    if (-not (Test-Path -LiteralPath $File)) { return $null }
    $raw = Get-Content -LiteralPath $File -Raw -ErrorAction SilentlyContinue
    if (-not $raw) { return $null }
    # Markers get written by assorted tools, so tolerate a BOM and stray whitespace.
    $text = $raw.Trim([char]0xFEFF, ' ', "`r", "`n", "`t")
    try { return (New-TimeSpan -Start ([datetime]$text) -End (Get-Date)).Days } catch { return $null }
}

# --- Block 1: maintenance reminders ---------------------------------------
# Same rule as the other two blocks: an unconfigured block is silent, a configured one
# that cannot find its target is loud. An earlier version simply skipped when the folder
# was absent, which is what a fresh install looks like - so the block that exists to nag
# said nothing, forever, to exactly the person who had not set it up yet.
if ($EnableMaintenanceReminders -and -not [string]::IsNullOrEmpty($MaintenanceRoot) -and
    -not (Test-Path -LiteralPath $MaintenanceRoot -PathType Container)) {
    $messages += "WARNING: maintenance folder not found at $MaintenanceRoot. Create it and drop a date into last-run, or set EnableMaintenanceReminders to false in this hook."
}

if ($EnableMaintenanceReminders -and -not [string]::IsNullOrEmpty($MaintenanceRoot) -and
    (Test-Path -LiteralPath $MaintenanceRoot -PathType Container)) {

    # Name the routine's file rather than "your weekly routine": a reminder that points at
    # something undefined trains the reader to dismiss it.
    $routine = Join-Path $MaintenanceRoot 'weekly-routine.md'
    $weekly = Get-MarkerAgeDays (Join-Path $MaintenanceRoot 'last-run')
    if ($null -eq $weekly) {
        $messages += "REMINDER: weekly maintenance has no readable marker (maintenance/last-run). Run $routine when convenient and write today's date into the marker."
    }
    elseif ($weekly -ge $WeeklyOverdueDays) {
        $messages += "REMINDER: weekly maintenance is overdue (last run $weekly days ago). Run $routine, then write today's date into maintenance/last-run. Skip if the user is mid-task."
    }

    $updates = Get-MarkerAgeDays (Join-Path $MaintenanceRoot 'updates-last-check')
    if ($null -eq $updates) {
        $messages += "REMINDER: the update check has no readable marker (maintenance/updates-last-check). Run check-updates and backup-config when convenient and write the date."
    }
    elseif ($updates -ge $UpdatesOverdueDays) {
        $messages += "REMINDER: the update and backup check is overdue (last run $updates days ago). Run check-updates and backup-config, then write the date into maintenance/updates-last-check. Skip if the user is mid-task."
    }
}

# --- Block 2: the lesson families -----------------------------------------
if ($EnableLessonInjection -and -not [string]::IsNullOrEmpty($LessonsPath)) {

    if (-not (Test-Path -LiteralPath $LessonsPath)) {
        # Silent loss is the one unacceptable failure mode here. The purpose of this
        # block is to turn "available" into "read", and a wrong path - a repository
        # restored elsewhere, a renamed folder - would make every session run believing
        # there are no cross-cutting lessons at all. That is precisely the state this
        # hook exists to remove, so it shouts instead of skipping.
        $messages += "WARNING: lessons file not found at $LessonsPath. If it moved, fix the path in this hook - without it the families reach no session's context."
    }
    else {
        try {
            # Titles are read from the file and never duplicated here: family 5, one
            # operational source. A title hardcoded in this hook would drift in silence.
            $titles = @(Get-Content -LiteralPath $LessonsPath -Encoding UTF8 -ErrorAction Stop |
                Where-Object { $_ -match '^##\s+\d+\.\s+\S' } |
                ForEach-Object { $_ -replace '^##\s+', '' })
        } catch { $titles = @() }

        if ($titles.Count -gt 0) {
            $block = @("Cross-cutting lessons -- $($titles.Count) families, read before non-trivial work ($LessonsPath):")
            $block += ($titles | ForEach-Object { "  $_" })

            if (-not [string]::IsNullOrEmpty($CorrectionsLogPath) -and (Test-Path -LiteralPath $CorrectionsLogPath)) {
                $logLines = @(Get-Content -LiteralPath $CorrectionsLogPath -Encoding UTF8 -ErrorAction SilentlyContinue)
                $entries  = @($logLines | Where-Object { $_ -match '^- \d{4}-\d{2}-\d{2} ' })
                # A line that starts with a date but not with "- " looks like an entry and is
                # not counted. Counting only the exact format, a log that had drifted between
                # two formats reported 46 of 105 entries - shrinking in silence, which is the
                # one thing this block must never do. Name the drift instead of hiding it.
                $lookalike = @($logLines | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}' })
                if ($entries.Count -gt 0) {
                    $last = ($entries[-1] -split ' ')[1]
                    $block += "  (corrections log: $($entries.Count) line(s), last on $last; promote on the SECOND occurrence)"
                }
                if ($lookalike.Count -gt 0) {
                    $block += "  WARNING: $($lookalike.Count) line(s) in the corrections log start with a date but not with '- ' and are not counted. Fix the format or the count is wrong."
                }
            }
            $messages += ($block -join "`n")
        }
    }
}

# --- Block 3: the tool gotchas --------------------------------------------
if ($EnableMemoryInjection -and -not [string]::IsNullOrEmpty($MemoryIndexPath)) {

    if (-not (Test-Path -LiteralPath $MemoryIndexPath)) {
        $messages += "WARNING: memory index not found at $MemoryIndexPath. Fix the path in this hook, or empty it to switch this block off."
    }
    else {
        try { $indexLines = @(Get-Content -LiteralPath $MemoryIndexPath -Encoding UTF8 -ErrorAction Stop) }
        catch { $indexLines = @() }

        $inSection = $false
        $gotchas = @()
        foreach ($line in $indexLines) {
            if ($line -match '^##\s') { $inSection = ($line -match [regex]::Escape($GotchaSectionHeading)); continue }
            if ($inSection -and $line -match '^- \[') { $gotchas += ($line -replace '^- ', '  ') }
        }

        if ($gotchas.Count -gt 0) {
            $messages += (@("Memory -- $($gotchas.Count) tool gotcha(s) ($MemoryIndexPath):") + $gotchas) -join "`n"
        }
        else {
            # Configured, present, and yet nothing to print means the index does not have
            # the section this hook looks for - a heading renamed, or an index organised by
            # another criterion. Same rule as blocks 1 and 2: configured but absent is loud.
            $messages += "WARNING: memory index at $MemoryIndexPath has no '## $GotchaSectionHeading' section with '- [' entries. Rename the heading in this hook, or empty MemoryIndexPath to switch this block off."
        }
    }
}

if ($messages.Count -gt 0) { Write-Output ($messages -join "`n") }
exit 0
