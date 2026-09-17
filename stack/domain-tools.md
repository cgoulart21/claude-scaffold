# Domain tooling - named, not recommended

> Snapshot as of 2026-09-17.

These are the domain-specific tools in the practice this scaffold came from. **They are
listed, not endorsed, and deliberately without setup instructions.** Yours will be different
ones, and a scaffold that ships someone else's toolchain instructions is shipping their
problems along with them.

| Area | Tools in play |
|---|---|
| Electronics design | A PCB suite, an autorouter, an MCP server for design inspection |
| Mechanical CAD | Parametric CAD from code, plus a solid-modelling kernel underneath it |
| Embedded firmware | An embedded build system with pinned platform versions |
| Numerical work | A numerical computing suite driven through an MCP server |
| Documents | Offline document-to-markdown conversion; scraping with anti-bot handling |
| Literature | Bibliographic APIs queried by script rather than by fetching publisher pages |
| Code knowledge | A repository-to-knowledge-graph tool |

## Why there are no instructions here

Every one of these needs its own setup, and that setup is where the time goes: a pinned
runtime version, a specific JDK, a path that must not contain a space, a virtual environment
that has to be re-synced after an unrelated update. Those details are real and they are
expensive to rediscover - but they are also **specific to one machine, one operating system
and one version**, and they go stale faster than anything else in this repository.

So they live in the author's own memory index, not here. What transfers is the shape:

- **Each domain tool gets a memory entry** recording the gotcha you paid for, in one or two
  lines, so the next session does not pay again. `core/memory/` has the schema.
- **Pin the ones with coupled versions**, and record the reason next to the pin.
- **Check capability, not presence.** After changing versions of a suite, ask it what it
  can do rather than confirming a directory exists - an installation that arrived without an
  optional component looks identical from the outside until something breaks.
- **Install only what you use.** A domain tool you set up for one project and never opened
  again is a maintenance obligation with no return.

If you want the hardware or research side of this stack specifically, the honest answer is
that you will spend an afternoon per tool regardless of what any scaffold tells you. Budget
it, and write down what you learn.
