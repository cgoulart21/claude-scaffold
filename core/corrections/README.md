# Corrections - the counter, and nothing more

One append-only file. One line per correction. A rule is born only when the same thing
happens twice.

## Why a counter instead of a process

The obvious design is a pipeline: capture observations, review them weekly, promote the
good ones into rules. That design has been built and it fails in a specific, repeatable
way - **it dies at the second stage**. One instance of it captured 99 observations and
applied exactly 1, because "review the backlog" is work nobody schedules, and a backlog
nobody reads is indistinguishable from a backlog that does not exist.

What survives is a counter with no stages: you write the line when it happens, and the
*second* occurrence is the promotion trigger. There is no queue to groom, no folder of
proposals, no weekly ritual. If it never happens again, the line costs one sentence and
you were right not to make it a rule.

## The line

```
- YYYY-MM-DD - what I did - what they wanted
- YYYY-MM-DD - what I assumed - what was actually true
```

**Keep the leading `- `.** The session-start hook counts entries with
`^- \d{4}-\d{2}-\d{2} `, and a log written without it matches nothing - the counter goes
quiet and never says why. A format taught in prose and matched by a regex is two sources
for one contract, which is family 5; `tools/Test-CoreTemplates.ps1` now asserts that the
example here actually matches the pattern there.

The first form is a correction from the person you work with. The second is a technical
gotcha you found on your own. Both belong here: a gotcha that bites twice in two different
projects is exactly as worth a rule as a correction repeated twice.

Write the line the moment it happens, not at the end of the session. At the end of the
session the specifics are gone and what you write is a platitude.

## Promotion, on the **second occurrence**

| What repeated | Where it goes |
|---|---|
| The same correction, again | A rule in your global instructions |
| The same correction, but only in one project | A rule in that project's instruction file |
| The same gotcha, in a **different** project | A new family in `LESSONS.md`, naming both occurrences |

One occurrence stays here and only here. There is no stage between noticing and applying -
that gap is where the previous pipeline died.

Keep the promoted rule short and keep the log line too. The line is the evidence that the
rule was earned, and a rule whose reason nobody remembers is a rule that gets deleted in
the next cleanup.

## Two machines append to the same log

The moment a second machine exists, the log has two live copies and one repository copy,
and the obvious way to reconcile them - copy the live file into the repository - **erases the
other machine's lines** with no error. Union is the right operation, and it is subtler than it
looks: a union that compared literal lines treated `- entry` and `entry` as different and kept
both, so the fix for copy-over had a duplication mode of its own.

`Merge-CorrectionsLog.ps1` in this folder is that union, with the contracts its suite fixes:
nothing from either side disappears; an entry that differs only by bullet or whitespace is one
entry; an entry edited in place (a promotion marker appended) collapses onto the longer
wording, but only when one wording is a strict prefix of the other above a minimum length -
two distinct observations about the same tool on the same day share a long prefix easily, and
a first version that compared the first sixty characters deleted one of them from both logs;
header prose only the live copy has is never erased; and the result is idempotent, so a
periodic sync does not become a churn commit.

Call it from your sync script with the two files' lines, and write `MergedText` back to both
only when `WriteLive` is true. It returns the discarded texts, not a count: whoever removes a
line from a user's log must be able to show which one.

## After a programmatic append: sweep for control bytes

Any time a **script** appends to this file - or to any append-only file, a plan, a
changelog - sweep for `0x00`, `0x07`, `0x08`, `0x0B` and `0x0C` before you finish.

The reason is that `\a`, `\b`, `\f` and `\v` are *valid* escape sequences in a non-raw
string literal in most languages. Writing `\find` or `\backup` inside one produces a
control byte, raises no warning, and corrupts the file silently. One such byte sat inside
a real corrections log for three days before anyone noticed.

```powershell
$bytes = [IO.File]::ReadAllBytes($logPath)
$bad = @(0x00, 0x07, 0x08, 0x0B, 0x0C)
$hits = @(0..($bytes.Length - 1) | Where-Object { $bad -contains $bytes[$_] })
if ($hits.Count -gt 0) { "control bytes at: $($hits -join ', ')" } else { 'clean' }
```

**Repair only the offending byte.** Never rewrite an entry written by another session:
this file is shared, append-only state, and a well-meaning reformat destroys other
people's lines.
