# The weekly routine

Hand this file to your agent when the session-start hook says the weekly marker is
overdue. It is a prompt, not a script: every step needs judgement, which is exactly why it
is not automated.

> **Why this file exists at all.** The scaffold ships a corrections log and a rule that
> promotes a lesson on its second occurrence - and, without something that periodically
> *reads* the log, nothing ever notices a second occurrence. The log becomes write-only and
> the promotion rule never fires. This routine is the missing half of a mechanism that is
> already installed, not an extra.
>
> Each step below is the periodic half of one subsystem. **Delete the steps whose subsystem
> you did not install.**

---

## 1. Second occurrences (needs `core/corrections/` and `core/lessons/`)

Read the corrections log. Look for any lesson that appears **twice**, and check whether the
second occurrence was in a *different* project from the first.

- Same correction, twice → it becomes a rule in the global instruction file.
- Same correction, twice but only in one project → a rule in that project's instructions.
- Same technical gotcha, in a **different** project → a new family in `LESSONS.md`, naming
  both occurrences.

Only report what you find. Applying a promotion is a decision, and the person whose practice
this is makes it.

## 2. Plan freshness (needs `core/handoff/`)

Run `automation/verification/Assert-PlanFreshness.ps1 -Root <your projects root>`. It reads
every `## Checkpoint` and reports:

- `Status: active` with `Updated:` more than **14 days** ago → stale.
- `Base:` that is not an ancestor of the current `HEAD` → stale, and more urgent: the plan
  describes code that has moved underneath it. (Checked with git when the project is a
  repository; the report says when that surface was *not* exercised.)
- Missing fields → non-conformant, which is worse than stale: a plan that cannot be told
  alive misinforms whoever reads it.

Stale means *re-read before trusting*, not *delete*. Why it went stale is usually
information. The script never edits a plan; filling the fields is a human act.

## 3. Baseline and corruption (needs `automation/verification/`)

Run `Assert-Baseline.ps1`. Every failure is either a decision you changed and did not record,
or drift you did not intend. Both are worth a line in the report; only the second is worth
fixing today.

Then run `Assert-NoControlBytes.ps1 -Root <repo>` over **every** repository you version -
not only the corrections log. The rule "sweep after appending to the log" is too narrow: the
two latent bytes one practice found on the day the gate was written were in a memory note and
a script, files no log-scoped rule would ever have reached.

If you keep the memory store, run `Assert-MemoryLinks.ps1 -MemoryRoot <store>` as well. A
rename's blast radius is its incoming links, and nothing else tells you one went dangling.
Then `Assert-MemoryIndex.ps1 -MemoryRoot <store>`: a memory written in a hurry gets no index
line, or a line whose hook is not its `description`, and the index is the one surface that
decides relevance before a file is opened.

## 4. Memory silos (needs `core/memory/`)

Run `core/memory/Set-MemoryJunctions.ps1 -MemoryRoot <store> -SiloRoot <agent-home>/projects`
**without `-Apply`**. A new project creates a new silo, and nothing else detects it - one
practice found four in three weeks, while its own check kept passing because it enumerated
only silos that already had a `memory/`. Read the paths before the verdicts: every line must
end in `\memory`.

## 5. Vault lint (needs `vault/`)

Run `automation/verification/Invoke-VaultLint.ps1 -VaultRoot <vault>` for the mechanical
half: orphans, stubs, real dangling links, the promotion queue. Then do the judgement half
yourself, as the vault's instruction file defines it: contradictions, stale claims, missing
pages and cross-references, archiving candidates. Report only.

## 6. Report

Write a dated report next to the markers: a one-line summary, the repeated corrections found
(or "none"), the stale plans, the baseline result, the lint as a prioritised list, and any
errors you hit along the way. Keep it short enough to be read.

**If a step could not run, say so in the report and continue.** A partial report is useful; a
routine that stops at the first obstacle is a routine that stops being run. A step that
could not run and a step that found nothing are different facts, and the report must not
collapse them.

## 7. Stamp the marker

Write today's date into `<MAINTENANCE-DIR>/last-run`, in `YYYY-MM-DD` form. This is what
stops the hook nagging, so do it last - and only if the routine actually ran.

---

## Adding your own steps

The six above are entailed by what the scaffold installs. Yours will have more: a check
that a sibling repository received the improvements you made this week, a licence
expiry, a backup you want to prove is restorable rather than merely present.

Two rules for anything you add. **It must be read-only by default** - a weekly routine that
changes things is a weekly routine you will start skipping when you are busy, which is when
you most need it to have run. And **it must be able to report "could not check"** as an
outcome distinct from "nothing to report", or it will eventually report success from a
machine where it stopped working months ago.
