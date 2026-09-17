# <Task name>

The live-state document for multi-step work. One file, ephemeral, tool-neutral: any agent
or human picking this up should be able to read it and know where things stand without
asking.

Replace it in place as work moves. When a decision here turns out to be durable, move it
out to an ADR or a document in the repository - this file is state, not a record.

## Done

- <what is finished, specific enough to verify without re-reading the diff>

## Next

- <the next concrete step, not a theme>

## Checkpoint

```
Status: active | paused | complete
Updated: YYYY-MM-DD
Base: <git SHA>
```

**Staleness.** A plan with `Status: active` that has not been updated in **14 days** is
stale, and so is one whose `Base` is not an ancestor of `HEAD`. Stale means *re-read
before trusting*, not *delete*: the reason it went stale is usually information.

`Base` exists so a reader can tell whether this plan describes the code they are looking
at. Recording a git checkpoint is optional, and creating one requires explicit human
approval - a plan file must never be a reason to mutate the repository on its own.

## Notes

<Anything the next reader needs and cannot reconstruct: a blocked dependency, a decision
that was made and why, an assumption still unverified. Contradictions go here too, named
as contradictions, rather than resolved silently in favour of whichever signal you saw
last.>
