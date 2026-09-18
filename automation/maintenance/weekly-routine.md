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

Find every `PLAN.md` you are responsible for and check its `## Checkpoint`:

- `Status: active` with `Updated:` more than **14 days** ago → stale.
- `Base:` that is not an ancestor of the current `HEAD` → stale, and more urgent: the plan
  describes code that has moved underneath it.

Stale means *re-read before trusting*, not *delete*. Why it went stale is usually
information.

## 3. Baseline (needs `automation/verification/`)

Run `Assert-Baseline.ps1`. Every failure is either a decision you changed and did not record,
or drift you did not intend. Both are worth a line in the report; only the second is worth
fixing today.

## 4. Vault lint (needs `vault/`)

Run the **Lint** operation as defined in the vault's instruction file: orphans, stubs,
contradictions, stale claims, missing pages and cross-references, promotion and archiving
candidates. Report only.

## 5. Report

Write a dated report next to the markers: a one-line summary, the repeated corrections found
(or "none"), the stale plans, the baseline result, the lint as a prioritised list, and any
errors you hit along the way. Keep it short enough to be read.

**If a step could not run, say so in the report and continue.** A partial report is useful; a
routine that stops at the first obstacle is a routine that stops being run. A step that
could not run and a step that found nothing are different facts, and the report must not
collapse them.

## 6. Stamp the marker

Write today's date into `<MAINTENANCE-DIR>/last-run`, in `YYYY-MM-DD` form. This is what
stops the hook nagging, so do it last - and only if the routine actually ran.

---

## Adding your own steps

The five above are entailed by what the scaffold installs. Yours will have more: a check
that a sibling repository received the improvements you made this week, a licence
expiry, a backup you want to prove is restorable rather than merely present.

Two rules for anything you add. **It must be read-only by default** - a weekly routine that
changes things is a weekly routine you will start skipping when you are busy, which is when
you most need it to have run. And **it must be able to report "could not check"** as an
outcome distinct from "nothing to report", or it will eventually report success from a
machine where it stopped working months ago.
