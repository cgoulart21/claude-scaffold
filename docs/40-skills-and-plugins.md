# Skills, plugins, hooks, agents and MCP

Five things with overlapping names that do genuinely different jobs. Knowing which one you
need saves more time than any of them.

| Thing | What it is | Who triggers it | Fails by |
|---|---|---|---|
| **Skill** | A folder with instructions the agent loads when a task matches | The agent, by matching your request against its description | Never being triggered |
| **Plugin** | A bundle that installs skills, agents, commands or an MCP server | You, once, at install time | Bringing more than you wanted |
| **Hook** | A script the harness runs at a fixed event | The harness, deterministically | Not being wired |
| **Subagent** | A separate agent with its own context and tool set | The agent, or you | Losing the context that made the task make sense |
| **MCP server** | A process exposing tools the agent can call | The agent, when it needs that tool | Failing to connect, quietly |

## The distinction that matters most

**Skills are probabilistic. Hooks are deterministic.**

A skill fires when the agent decides its description matches. Write a vague description and
it fires when you did not want it, or - far more common - never fires at all, and you never
notice, because nothing reports a skill that did not trigger.

A hook fires because the harness ran it. No judgement involved.

So: anything that must happen *every time* is a hook, not a skill. The lesson injection in
this repository is a hook for exactly that reason. Had it been a skill called "remember the
lessons", it would have fired in the sessions where you already remembered.

Conversely, anything requiring judgement about *whether* it applies should be a skill. A
hook that runs a heavy check on every tool call is a hook you will disable within a week.

## Writing a skill description that actually triggers

The description is the whole triggering mechanism. Two clauses fix most of it:

```
TRIGGER - the concrete situations where this applies.
SKIP - the situations where it looks applicable and is not.
```

The `SKIP` clause does more work than the `TRIGGER` one. Without it, a skill about
"reviewing code" competes with every other review skill and fires in a coin flip.

Name the artifacts, not the intention. "When the user asks about performance" is untestable;
"when a profiler output, flame graph or benchmark result is in the conversation" is not.

## How to know what you actually use

You will install more than you use. That is not a failure of discipline; a skill's value is
unknowable until you have worked with it.

The recoverable version is to **prune against usage data rather than against your
impression**. Your agent records which skills and plugins were invoked, and your session
history shows what you reached for. Compare the installed set against the used set on a
schedule.

One trap, and it is the reason to write this down: **a loaded catalogue is not a used
skill.** Skills appear in a session's catalogue because they were *offered*. Counting
catalogue entries measures what you installed. Only invocation data measures what you use.
One audit that made this distinction removed thirteen skills in a single pass, none of which
had ever run.

## Installing without drifting

Prefer naming what you want to excluding what you do not.

An install of the form "everything from that repository, minus a list" means every skill
upstream adds arrives silently, and the installed set depends on *when* you last ran the
installer. Two machines drift apart with nobody touching anything - and upstream renames
leave the old name orphaned on disk, where nothing recreates it and no allowlist removes it.

But know the cost of the switch: **an allowlist installs and does not remove.** Moving to
one does not prune what is already there. Pruning becomes a deliberate, manual act, and a
machine set up before the switch keeps whatever it had. Both properties are correct; only
the second one surprises people.

## Subagents

Useful for two things: work that would flood your context with output you do not need, and
work where **not** having your context is the point.

The second is the interesting one. An agent that wrote something cannot review it freshly -
it knows what it meant. A subagent with no history reads what is actually there. The fresh
reader that audited this repository's own playbook found nine gaps its author could not see,
because the author knew the answers and never noticed they were unwritten.

The cost is that a subagent knows nothing you do not tell it, and a task that needed the
conversation will come back confidently wrong. Send work that is self-contained, or work
where isolation *is* the method.

---

Previous: [governance](30-governance.md) · Next: [verification](50-verification.md).
