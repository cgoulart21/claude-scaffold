# Questions

## Do I need all of this?

No, and installing all of it is the failure mode.

A rule you do not follow teaches you the file is decorative, and that lesson generalises to
the rules you *were* going to follow. Two subsystems used properly beat five installed and
ignored.

**The minimum viable subset**, in the order that pays back fastest:

1. **`core/corrections/`** - one file, one line per correction, promote on the second
   occurrence. Costs a sentence a day. It is the only one that gets *more* valuable with no
   further work.
2. **The session-start hook** - because a file that is written and not read is the failure
   this whole repository is about.
3. **`core/memory/`** - once you have written the same gotcha down twice.

Everything else is worth adding when you feel its absence. If you cannot name the moment
`core/lessons/` would have helped you last month, you are not ready to maintain it yet.

## I am on macOS or Linux. How much of this works?

The concepts: all of them. The scripts: not directly.

| Piece | Portability |
|---|---|
| Governance, lessons, corrections, handoff | Plain Markdown - fully portable |
| Vault schema | Fully portable |
| `triggers.md`, the exit-code contract | Concepts port; use `cron` or a systemd timer for path 1 |
| The three hooks | PowerShell. Logic ports, syntax does not |
| `Set-MemoryJunctions.ps1` | **Windows-specific by design** - it uses NTFS reparse points |

For the memory store on Unix, the equivalent is a symlink per silo. The safety argument is
identical and non-negotiable: **copy before you remove**, never overwrite what is already in
the store, and remove a link rather than the tree behind it. `rm -rf` through a symlink
deletes the target.

Two things to be honest about. This repository has not been tested on macOS or Linux - the
translation above is derived, not verified. And "translate the shell steps" is easy to write
and real work to do; if you do it, a pull request would help the next person more than
anything else here.

## What does this cost in tokens?

The session-start hook prints the lesson titles and the gotcha index into every session -
call it a few dozen lines.

Whether that is expensive depends on what it prevents. The audit that motivated it found
eighteen rediscoveries of one rule across eight projects. Each rediscovery cost far more than
the injection does, and cost it in the expensive currency: your attention, on a day when you
were doing something else.

If it does get too big, the fix is not to stop printing. It is that **memory has grown past
what memory is for** - a line that does not change behaviour is a line that belongs in the
vault or nowhere.

## Can I use this with a different agent?

The Markdown, yes - governance, lessons, corrections, handoff, the vault schema are all
plain text about method.

The hooks and the settings wiring assume a harness that runs scripts at `PreToolUse` and
`SessionStart` and hands them a JSON event on stdin. If yours has equivalent events, the
logic transfers directly. If it has none, the session-start injection has no equivalent, and
that is the piece you would miss most.

`core/handoff/codex-AGENTS.md` exists precisely because two agents sharing one `PLAN.md` is
the common case.

## Why is the lessons file someone else's lessons?

Because a checklist to start from beats a blank file, and because the alternative - shipping
an empty one - teaches nothing about the shape a lesson should have.

They are labelled as borrowed in their own header, and the rule for growing your own is
right there. Your families will be different, and the ones you paid for are the ones you
will actually apply.

## Something here is wrong or out of date. Which part?

Check the folder first:

- **`stack/`** carries a date and a warning. If it is stale, that is expected, and the
  section on deriving your own stack is the part that still holds.
- **`core/`** is method and should not go stale. If it has, that is a real defect - the
  durability contract failed, and this repository has failed that way before.

## Can I contribute?

The most useful contributions, in order: a verified macOS or Linux translation of the
hooks; a lesson family with **two occurrences from different projects** behind it; a
sharper `SKIP` clause for any skill description here.

The least useful: another skill. The stack is already bigger than most people will prune.

---

Previous: [maintenance](60-maintenance.md) · Back to [the start](00-why.md).
