# `stack/` - a dated snapshot, and how to stop needing it

> **Snapshot as of 2026-09-17. Verify before trusting any of it.**
>
> Everything in this folder is **perishable**: version numbers move, plugins get renamed,
> marketplaces restructure, and a tool that was the obvious choice this year is replaced by
> something better next year. If you are reading this long after that date, treat the lists
> as archaeology and the method below as the part that still holds.

That warning is the whole reason this folder is separate from `core/`. An earlier version of
this repository had no such split, every file looked equally current, and it spent months
confidently teaching a configuration its author had already abandoned. Nothing in the layout
could say *this one ages and that one does not* - so nobody could tell which was which,
including the author.

## How to derive your own stack

This section is the timeless part, and it is worth more than the lists.

**Start from what you actually use, not from what looks good.** The reliable method is
telemetry plus transcripts: your agent records which skills and plugins were invoked, and
your session history shows what you actually reached for. Prune against that, on a schedule,
and the stack stays the size of your practice instead of the size of your curiosity.

**A loaded catalogue is not a used skill.** This is the trap, and it is worth stating
plainly: a skill appearing in the session's catalogue means it was *offered*, not that it
ran. Counting catalogue entries tells you what you installed; only usage data tells you what
you use. One audit that made this distinction removed thirteen skills in a single pass, none
of which had ever fired.

**Prefer an allowlist to a denylist when the upstream moves.** If you install "everything
from that repository, minus a list", then every new skill upstream adds arrives silently,
and the installed set depends on *when* you last ran the installer. Two machines drift apart
with nobody touching anything. Name what you want instead.

**But know that an allowlist installs and does not remove.** Switching to one does not prune
what is already there - that capability is gone by design, and pruning becomes a deliberate
manual act. A machine that was set up before the switch keeps whatever it had.

**Pin what you pinned for a reason, and write the reason next to it.** A pin whose
justification nobody remembers gets helpfully upgraded within two maintenance runs.

**Re-derive rather than copy.** The lists below describe one practice on one operating
system with one set of problems. Yours differ. The method above transfers; the inventory
does not.

## What is in here

| File | What it is |
|---|---|
| `manifest.md` | Marketplaces, plugins, skills and CLIs, with the exact commands |
| `domain-tools.md` | Domain-specific tooling, named only - these are the author's, not a recommendation |
| `skills/` | The four skills this repository can actually ship, with attribution |

## About `skills/`

Four skills ship here because four is what the licences and the authorship allow:

| Skill | Provenance |
|---|---|
| `design-smells` | Authored, mined from `addyosmani/agent-skills` plus a published playbook |
| `source-grounded` | Authored, adapted from `addyosmani/agent-skills` |
| `diagnose` | A customisation of an upstream skill from `mattpocock/skills` |
| `scientific-project-report` | Authored, CC BY 4.0, ships with its own licence file |

Everything else in the practice this came from is installed from its own source and listed
in `manifest.md` rather than vendored here. Vendoring somebody else's skill creates a fork
you then have to maintain, and a stale fork is worse than a link.
