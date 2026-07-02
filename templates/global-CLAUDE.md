# Global Operating Instructions (template)

Deploy to `~/.claude/CLAUDE.md`. These apply to **every** project; a project's own
`CLAUDE.md` governs that project's domain and **takes precedence**. Keep this file
lean — it costs tokens on every session. Adapt names/paths to your machine.

## Core operating behaviors

Non-negotiable, across every task (adapted from Addy Osmani's `agent-skills`):

- **Surface assumptions.** Before any non-trivial work, state them explicitly —
  "**Assumptions I'm making:** 1… 2… → correct me now or I proceed with these."
- **Manage confusion actively.** On an inconsistency or conflicting signal, **stop**,
  name the confusion, present the trade-off or ask, and wait — don't guess.

## Cross-agent handoff — `PLAN.md`

If you tag-team a project with **Codex** (e.g. the user switches to Codex when Claude hits
its usage limit, then back), use a shared `PLAN.md` at the repo root so the handoff is
seamless. Codex's mirror lives in `~/.codex/AGENTS.md` (deploy `templates/codex-AGENTS.md`).

- For substantive multi-step work, **read `PLAN.md` first** if present and resume from it;
  else create one: **Goal · Done · Next · Decisions/gotchas · Checkpoint**.
- Keep **Done / Next** current — it's the context bridge for whoever picks up.
- **Checkpoint with git** at milestones and before a handoff (small labeled commit; record
  its hash on the `## Checkpoint` line so the next agent can `git diff <hash>`). Don't push
  or open PRs without the user's ok.

## Skill posture — the autonomous skillchain

- **Superpowers is the methodology backbone.** Its `using-superpowers` skill is injected
  at session start (plugin SessionStart hook). Before non-trivial work, check for a
  relevant skill and prefer the disciplined workflows (TDD, systematic-debugging,
  writing-plans, verification-before-completion, worktrees) over ad-hoc approaches.
- **Capability gaps → `find-skills`.** When a task might be served by a skill you don't
  have, search the ecosystem before hand-rolling.
- **Hard bugs → `diagnose`** (feedback-loop discipline); `systematic-debugging` for the rest.
- **Framework/hardware code → `source-grounded`**; **reviewing/refactoring → `design-smells`**.

## Skill self-maintenance — `task-observer`

Invoke `task-observer` when either: (1) starting a substantive multi-step build/debug/
authoring session; or (2) the user corrects you or you hit a gap no skill covers. Not for
trivial Q&A (its SKILL.md is large). When loading any skill, check
`~/.claude/skill-observations/observation-log.md` for OPEN observations tagged to it.

- Observations → `~/.claude/skill-observations/observation-log.md`
- Proposed skill updates (await approval) → `~/.claude/skill-updates/`

## Maintenance & updates (choose your automation model)

A periodic routine reviews OPEN observations, lints your knowledge vault (if you use one),
and checks for tool updates — writing proposals/reports under `~/.claude/maintenance/`.
Proposals are never auto-applied.

**Pick the trigger that fits your environment:**

- **Normal Claude Code install** (npm-based, standard auth): a real **cron / Task
  Scheduler** job can run the checks unattended.
- **MSIX/Store-packaged app OR host-managed auth** (unattended `claude -p` gets a 401,
  and external schedulers don't share the app's virtualized npm globals): use a
  **session-driven** trigger instead — near the start of a session, if the date in a
  marker file (e.g. `~/.claude/maintenance/updates-last-check`) is ≥N days old, run the
  checks in-session, then update the marker. This is the safer default if unsure.

Applying updates stays deliberate: coupled runtimes (e.g. a plugin whose Python venv must
be re-synced) and pinned versions use their own per-tool scripts and often need an app
restart.
