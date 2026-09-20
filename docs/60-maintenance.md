# Maintenance

A setup is not a thing you build. It is a thing you keep, and the keeping has a shape.

## Two cadences

| Cadence | What it does | Why separate |
|---|---|---|
| **Weekly** | Reads what accumulated: the corrections log, stale plans, baseline drift | Cheap, judgement-heavy, no network |
| **Every two weeks** | Checks for updates and backs up your authored artifacts | Slower, touches the network, produces a report to act on later |

They are separate because they fail differently. The weekly one needs you present and
thinking. The biweekly one mostly needs to have happened.

## Detection and application are separate, always

The update check **applies nothing**. It reads versions and writes a dated report; you apply
things deliberately, looking at that report.

This is worth defending, because the combined version is more convenient and strictly worse.
An updater that both detects and applies will eventually, on a day nobody was reading the
output, unpin something you pinned for a reason. The reason is usually in a file somebody
wrote once and nobody has read since - which is why a pin without its reason next to it gets
"helpfully" upgraded within two maintenance runs.

The check answers with the same three exit codes as the gates in `automation/verification/`:
`0` when every surface was checked and is current, `1` when there is something to act on -
an update, or a plugin its marketplace no longer lists - and `2` when a surface could not be
checked: the CLI not found, a catalogue unreadable, npm off the PATH. A partial run is
reported as `2` even when it also found an update, so that "could not check" never hides
behind "nothing to do". On a sandboxed host the agent CLI is not on PATH; the script looks in
the application's package cache before giving up, and the report says which of the two it
used.

## The weekly routine reads the log, and that is the point

`automation/maintenance/weekly-routine.md` has the steps. The one that justifies the whole
routine is the first: **read the corrections log and look for second occurrences.**

Without a periodic reader, the log is write-only. Entries go in, nothing ever notices that
one of them has now happened twice, and the promotion rule - the mechanism `core/` is built
around - never fires. The counter exists; nobody counts.

Every other step is the periodic half of a subsystem you installed: plan staleness for
`core/handoff/`, baseline drift for `automation/verification/`, a lint pass for `vault/`.
Delete the ones whose subsystem you skipped.

## Making it actually fire

Three mechanisms, and **two of them fail silently on the wrong host** - which is worse than
failing loudly, because a maintenance routine that never runs looks exactly like one with
nothing to report.

| Path | Works when | Test |
|---|---|---|
| OS scheduler | Ordinary install, real directories, no application-managed auth | Run your CLI non-interactively from a plain terminal |
| Session-driven marker | Always | None needed - it is the fallback |
| Host-provided scheduler | The host offers one | Verify **one real firing**, end to end |

`automation/triggers.md` has the detection tests in full. Two notes that matter more than the
table:

**Accepted is not fired.** A scheduler that took your task is not a scheduler that ran it.
Those are different facts, and only the second one is maintenance.

**The session-driven path has a real limitation, and it is fine.** It fires when you open a
session, so two weeks away from the keyboard is two weeks without maintenance. That is
usually correct: nothing needs maintaining while nothing is happening.

## Direction of sync

If you keep a private backup repository - and you should - fix the direction and write it
down.

```
live configuration  ->  backup repository        sync
backup repository   ->  a new machine            restore
```

**Never edit the backup copy.** It is a mirror; the next sync overwrites it, and you lose the
edit with no error and no clue. Edit the live file, then sync.

The exception is the files the repository *authors* rather than mirrors - your lessons file,
your memory index. Those are edited in place, because the repository is where they live.
Know which of your files are which, and say so at the top of that repository's own
instruction file.

### The second machine, and the order that is not optional

With two machines the direction above has a second half, and it is the half that fails
silently. Machine B pushes an improvement to a mirrored file. Machine A, behind, runs its
backup: the sync overwrites the repository copy with A's older live file, commits, and the
push is refused. Good - the refusal is loud. The backup script now fetches first and stops
before touching anything when the remote is ahead, so this case ends there.

The case no script catches is the stale machine that does the *right* thing first: it pulls,
gets B's improvement into the repository, and then syncs - and the sync mirrors A's old live
file over the freshly pulled one. Clean commit, clean push, improvement gone. Nothing errors,
because every step did what it was told.

The rule that closes it is procedural: **repository to machine first, machine to repository
after, never the reverse.** On a machine that has been away, restore or bootstrap from the
pulled repository *before* you sync from it. Measure `ahead/behind` for every repository you
share before you start, not after something looks wrong. This is lesson family 10 in
operational form: the handoff described the machine it came from, and the machine you are
on is not that one.

## What maintenance does not cover

Nothing above synchronises one setup with another. If you improve a *shape* - a rule, a
hook, a schema - and you also keep a generic copy of that shape somewhere, nothing carries
the improvement across. That is a human step, and it needs to be in the routine or it does
not happen.

This is not hypothetical. This repository froze for two months, looking current, teaching a
governance file its author had already rewritten, for exactly that reason: the improvement
went to the private instance and nothing brought it here.

---

Previous: [verification](50-verification.md) · Next: [questions](99-faq.md).
