# `core/` - the part that does not expire

Everything in this folder is **method**: discipline, schemas, conventions. None of it has a
shelf life. You can adopt it today and it will still be right when every version number in
`stack/` has moved on.

That is the whole point of the split, and it exists because of a specific failure.

## Why the split exists

This repository froze once. It was written, it was accurate, and then the practice it came
from kept moving while the files did not. Months later it was still confidently teaching a
governance file whose author had already deleted half of it.

The cause was not neglect. The cause was that **every file looked equally current.**
Nothing in the layout could express "this one does not need updating", so nothing
distinguished the parts that had aged from the parts that never would. A reader had no way
to tell, and neither did the author.

So durability is now structural. A file's folder tells you how fast it rots:

| Folder | Rots | Contract |
|---|---|---|
| `core/` | never | Method and schemas. Timeless by construction |
| `stack/` | fast | A dated inventory of tools. Carries a date stamp and a warning |
| `vault/`, `automation/` | slowly | Shapes and patterns, with concrete values as placeholders |
| `docs/` | slowly | The explanation. Cites `stack/` as a dated example, never as truth |

## The routing rule

When you change something here, decide where it goes:

> **Method goes to `core/`. Inventory goes to `stack/`.**
> If you cannot tell which one it is, it is not `core/` - inventory disguised as method is
> exactly what rots without announcing itself.

A version number, a package name, a tool that happens to be good this year: `stack/`. A way
of deciding, a schema, a rule about what counts as verified: `core/`.

The test is simple. Ask whether the sentence would still be true if every tool named in it
were replaced by a competitor. If yes, it is method.

## What is in here

| Subsystem | What it gives you |
|---|---|
| `governance/` | The global instruction file: eight rules in seven sections, short enough to actually be read |
| `lessons/` | Ten cross-cutting error families, with the rule that grows them |
| `memory/` | One physical memory folder behind per-directory junctions, plus the file schema |
| `corrections/` | The append-only counter, and the second-occurrence promotion rule |
| `handoff/` | `PLAN.md` and its checkpoint convention, shared across agents |
| `review/` | One review surface per purpose, and why CI is the authoritative one |

`lessons/` and `corrections/` are two ends of one mechanism: the log counts, and a lesson
that repeats in a second project graduates into a family. The eleven families shipped here are
**seeds from someone else's practice** - a checklist to start from, not a record of your own
mistakes. The file says so in its own header, because a borrowed scar presented as your own
is how a discipline turns decorative.

## Using it

Nothing here is meant to be copied wholesale. Take the pieces you will actually maintain:
a rule you will not follow is worse than no rule, because it teaches you that the file is
decorative. Two subsystems used properly beat five installed and ignored.
