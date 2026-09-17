# The knowledge vault

An agent-maintained wiki: you supply sources, questions and decisions; the agent keeps the
structure, the links and the index honest. It ships **empty**. What is here is a schema.

## Why this is not the same thing as memory

This is the distinction people collapse, and collapsing it ruins both halves.

| | `core/memory/` | `vault/` |
|---|---|---|
| Holds | tool gotchas, project context | research, sources, synthesis |
| Read | at the start of every session | when a question needs it |
| Size | one line per entry, scannable | pages, with history |
| Grows by | getting bitten | reading and thinking |
| If it doubles | it stops being read | it gets more useful |

Memory is operational and must stay small enough to be injected into every session. The
vault is research and is *supposed* to grow without bound. Put research notes in memory and
the index becomes unreadable; put tool gotchas in the vault and they never reach the session
that needed them.

The same line runs through the lessons file: **method and verification discipline go to
`core/lessons/`, not here.** The vault is what you know; lessons are how you work.

## Files

| File | What it is |
|---|---|
| `AGENTS.md.template` | The schema: page format, operations, conventions, definition of done |
| `structure.md` | The folders to create, and the two traps that come with them |

## Driving it

Once the vault exists, you drive it in plain language: *ingest this paper*, *lint the wiki*,
*synthesize what we know about X*, *challenge this claim*, *connect these two areas*,
*what's emerging*. The operations are defined in the template - the agent reads them there
rather than from you.

The one worth knowing about is **harvest**, which collects durable learning out of your code
repositories and into the wiki. Every other operation starts from material you deliberately
filed, which means a vault can sit untouched for weeks while the actual work happens
elsewhere. Harvest is the operation that closes that loop, and it is the one people leave
out.

## Two decisions to make before you start

**Where it lives.** Not inside a cloud-synced folder, unless you follow the git setup in
`structure.md`. Two sync engines on one directory produce conflicts that look like data
corruption.

**What goes in it.** A vault with everything in it is a search engine you built by hand and
lose to. Sources you will cite, concepts you will reuse, decisions you will be asked to
justify. Not clippings you might read one day.
