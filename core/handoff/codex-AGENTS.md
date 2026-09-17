# Agent instructions

Deploy this to the other agent's instruction file - the one it reads at startup - so that
both agents share a single handoff convention and you can switch between them without
re-explaining the state of the work.

## Handoff - `PLAN.md`

- In multi-step work, read `PLAN.md` at the repository root **first**.
- Keep `Done` and `Next` current, and maintain the `## Checkpoint` block:
  `Status: active|paused|complete`, `Updated: YYYY-MM-DD`, `Base: <git SHA>`.
- One file, ephemeral, tool-neutral. Replace it in place. Durable decisions move out to an
  ADR or a repository document; `PLAN.md` holds state, not history.
- A plan with `Status: active` untouched for **14 days**, or whose `Base` is not an
  ancestor of `HEAD`, is stale - re-read before trusting it.
- A git checkpoint is optional and needs explicit human approval.

## Working agreements

- **Say which surface you tested.** A passing suite is not a satisfied contract; a command
  that runs is not a coherent environment. Name the level you actually validated.
- **Name contradictions** instead of picking a side quietly. If `PLAN.md` and the code
  disagree, the disagreement itself is the finding.
- **Commit, push, opening a PR, and sending private code or diffs to an external service
  each need named approval**, whatever the surrounding task authorised.
- When you correct something that was already written down somewhere, fix **every** copy
  before moving on, and say which copies you fixed.
