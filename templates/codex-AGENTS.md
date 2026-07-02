# Codex — global instructions (template → deploy to ~/.codex/AGENTS.md)

## Cross-agent handoff (PLAN.md)

You (Codex) may tag-team a project with **Claude Code** — typically the user switches to
you when Claude hits its usage limit, then back to Claude later. Make the handoff seamless
via a shared `PLAN.md` at the repo root (the same file Claude uses).

- When starting substantive multi-step work in a project, **read `PLAN.md` first** if it
  exists and resume from it. Also skim `git log` / `git diff` since the commit it records
  under `## Checkpoint`. If none exists and the work is non-trivial, create one:
  **Goal · Done · Next · Decisions/gotchas · Checkpoint**.
- Keep **Done / Next** current as you work — it is the context bridge for whoever picks up
  next (you or Claude).
- **Checkpoint with git** at logical milestones and before handing back: a small labeled
  commit (`checkpoint: <what>`), and record its hash + date on the `## Checkpoint` line so
  the next agent can `git diff <hash>` for the exact delta.
- Keep commits small; do **not** push or open PRs without the user's ok.
- Keep `PLAN.md` tool-neutral — Claude Code reads the same file.
