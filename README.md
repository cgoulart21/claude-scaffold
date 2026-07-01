# claude-scaffold

A **scaffold** for bootstrapping a Claude Code environment on Windows: a curated skill
stack (Superpowers backbone + complementary skills), an optional Obsidian **LLM-wiki**
("second brain"), governance instructions, and maintenance automation.

It's **agent-driven**: instead of a brittle install script, you hand the scaffold to your
own Claude Code and it sets everything up *on your machine*, adapting paths and asking your
preferences. The repo ships generic **templates** — no personal data.

## Quick start

1. Install prerequisites: the **Claude app**, **Node.js/npm**, **git** (PowerShell ships
   with Windows).
2. Clone this repo and open Claude Code inside it.
3. Say: **"Set up my Claude Code using SCAFFOLD.md."**
4. Answer the agent's questions (which parts you want, where to put the vault, your
   automation preference). It installs the stack, deploys the skills + governance, and
   scaffolds an empty LLM-wiki.
5. **Restart the Claude app**, then add your own API keys where prompted.

## What you get

- **Skill stack** — Superpowers (methodology backbone) + `find-skills`, `task-observer`,
  and the two authored skills **`source-grounded`** (ground code in version-specific docs)
  and **`design-smells`** (structural review lens). See `manifest.md`.
- **LLM-wiki** (optional) — an Obsidian vault whose `CLAUDE.md` (`templates/vault-CLAUDE.md`)
  defines a self-maintaining knowledge base: Ingest / Query / Lint / Synthesize / Note plus
  the "thinking" ops **Challenge / Connect / Emerge**. Starts empty — it's *your* knowledge.
- **Governance** — `templates/global-CLAUDE.md` (operating behaviors, skill posture,
  self-maintenance, update/backup triggers).
- **Maintenance** (optional) — read-only update-check + a git backup of your authored
  artifacts, on the cadence that fits your environment.

## What this is NOT

- Not a turnkey clone of anyone's setup — the agent adapts it to you.
- No personal notes, no secrets, no hardcoded personal paths. The vault is empty.
- Windows-first (scripts are PowerShell); the plugin/skill installs are cross-platform, but
  you'll translate the shell steps on macOS/Linux.

## Files

- `SCAFFOLD.md` — the playbook the agent follows.
- `templates/` — global governance, the LLM-wiki schema, the two skills, maintenance scripts.
- `manifest.md` — exact install commands (marketplaces, plugins, skills, CLIs).
- `CREDITS.md` — attribution to every upstream project this stack reinstalls.

## Credits & license

Almost everything here reinstalls other people's work from source — see `CREDITS.md`.
The authored templates are MIT-licensed (`LICENSE`).
