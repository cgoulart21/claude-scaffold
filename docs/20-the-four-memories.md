# The four memories

The single most useful idea in this repository, and the one most setups get wrong by
collapsing two of these into one.

An agent has four distinct places a fact can live. They differ in **how long the fact
lasts**, **who reads it**, and **what happens when the pile gets big**. Put a fact in the
wrong one and it is either never read or it drowns the things that are.

## The four

| | Session context | Memory | Lessons | Vault |
|---|---|---|---|---|
| **Holds** | what is happening now | tool gotchas, project context | families of error | research, sources, synthesis |
| **Lasts** | one conversation | until the tool changes | permanently | permanently |
| **Read** | continuously, for free | start of every session | start of every session | when a question needs it |
| **Size** | bounded by the window | one line per entry | ten-ish families | unbounded |
| **If it doubles** | you lose the start | it stops being read | it stops being read | it gets more useful |
| **Lives in** | nowhere, it evaporates | `core/memory/` | `core/lessons/` | `vault/` |

**Session context** is not yours to manage, beyond keeping it clean. It evaporates. Anything
you want next week has to leave it before the conversation ends - which is why the
corrections log is written *when the thing happens*, not at the end.

**Memory** is operational and must stay small. It is injected into every session, so every
line you add is a line someone reads a hundred times. One line per entry, scannable, and the
test is: *would I get this wrong again without the note?* If not, it does not go in.

**Lessons** are method, not tools. A gotcha says "this tool needs that flag"; a lesson says
"a check that did not run is not a check that passed". Lessons are also injected every
session, which is why there are eleven families and not a hundred.

**The vault** is research and is *supposed* to grow without bound. Nothing injects it; it is
read on demand. That is what lets it be big.

## Where does this go?

The decision table, in the order you will actually need it:

| What you just learned | Goes to | Why |
|---|---|---|
| "This CLI needs `--flag` on Windows or it silently does nothing" | **Memory** | Tool-specific, you would repeat it, one line |
| "I said the suite was green and it never ran" | **Corrections log** | First occurrence. It is not a lesson yet |
| The same thing, in a different project, two months later | **Lessons** | Second occurrence, different project: promote it |
| "This project uses a 12 V rail, not 5 V" | **Memory**, project context | Facts about a project that its code does not state |
| "This paper argues X, and contradicts that other one" | **Vault** | Research. It will grow, and that is fine |
| "We decided to use approach B because of C" | **The project's own repository** | An ADR belongs with the code it constrains |
| "The user prefers short answers" | **Memory**, user type | Durable preference, one line |
| "We are mid-refactor, three files left" | **`PLAN.md`** | Live state, ephemeral by design |

Two boundaries are worth stating because they are the ones that get crossed:

**Never put research in memory.** It is the fastest way to make the index unreadable, and an
unread index is worse than no index because you will keep adding to it.

**Never put tool gotchas in the vault.** They will be correctly filed, beautifully
cross-linked, and never read at the moment they would have helped - which is the start of a
session, where only memory reaches.

## Why "written down" is not enough

All four are useless if nothing reads them at the right moment. The design that fails is a
folder of excellent notes that the agent *could* open. The design that works puts the small
ones - memory and lessons - **into every session automatically**, and leaves the big one -
the vault - to be asked.

That is the whole job of `automation/hooks/session-start.ps1`: it prints the lesson titles
and the gotcha lines into the session, unasked. It costs a handful of lines per session. It
buys the rule being in context before it bites, instead of in the postmortem afterwards.

## The promotion path

The four are not independent - there is a flow between them:

```
something goes wrong
   -> a line in the corrections log            (first occurrence)
   -> it happens again, in another project
   -> a family in LESSONS.md                   (second occurrence)
   -> and, if it is tool-specific rather than method,
      a line in MEMORY.md instead
```

The **second occurrence** is the entire mechanism. Promoting on the first gives you a
hundred rules nobody follows; waiting for the third means paying three times. And the log
has to be *read periodically* or no second occurrence is ever noticed - which is what
`automation/maintenance/weekly-routine.md` is for.

A rule that lives in `LESSONS.md` without two occurrences behind it is a rule you borrowed.
That is fine as a starting checklist - the ten shipped here are exactly that, and say so -
but your own families are the ones you will actually apply, because you remember what they
cost.

---

Previous: [laying out a machine](10-machine-setup.md) · Next: [governance](30-governance.md).
