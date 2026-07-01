# SCAFFOLD — playbook for the agent

**You are a Claude Code (or compatible) agent.** A user has cloned this repo and asked
you to set up their environment "using this scaffold." This file is your playbook.

This scaffold is a **structure to reproduce, not a config to copy.** It contains generic
templates (a skill stack, a governance file, an LLM-wiki schema, maintenance scripts) with
**no personal data**. Your job is to install the stack and instantiate the templates **on
the user's machine, adapting paths and asking their preferences.** Never invent the user's
details — ask.

## Ground rules

1. **Adapt, don't transplant.** Replace every placeholder (`<...>`), path, and name with
   the user's actual values. Deploy targets are under `~/.claude` (use `$env:USERPROFILE`).
2. **Ask before installing** anything, and **confirm** each phase. Surface assumptions.
3. **Windows + PowerShell** is the assumed host (scripts are `.ps1`). On macOS/Linux,
   translate the shell steps; the plugin/skill installs are cross-platform.
4. Use the files under `templates/` as the source. Read `manifest.md` for exact
   install commands and `CREDITS.md` for provenance.
5. The knowledge vault starts **empty** — it's the user's knowledge, not the author's.

## Phase 0 — Interview (do this first)

Ask the user which parts they want (all optional, independent):

- **A. Skill stack** — Superpowers backbone + curated skills + the two authored skills.
- **B. Knowledge vault** — an Obsidian LLM-wiki (the "second brain"). If yes, ask for a
  **location** and **name**. Warn: if placed inside a cloud-synced folder (OneDrive/Dropbox),
  use git with a `--separate-git-dir` outside that folder to avoid sync conflicts.
- **C. Maintenance automation** — periodic update-check + backup. If yes, determine the
  **trigger model** (see Phase 5).
- **D. Front-end tooling** — Impeccable (design) + the Obsidian format skills.

Also ask: do they already have Node/npm, git, and the Claude app installed? (Prereqs.)

## Phase 1 — Skill stack (if A)

Follow `manifest.md`. In short:

1. Add marketplaces (`claude plugin marketplace add …`) and install plugins
   (`claude plugin install <name>@<mkt> --scope user`). Install **only** the Superpowers
   *core* — skip its memory plugins and Unix-first ones.
2. Install third-party skills via `npx skills add <repo> --skill <s> --global --copy -y`,
   then **prune** the duplicates that Superpowers already covers (see manifest).
3. Install CLIs (`npm i -g …`).

The `PromptScript does not support global skill installation` warning is harmless.

## Phase 2 — Authored skills (if A)

Copy `templates/skills/source-grounded` and `templates/skills/design-smells` into
`~/.claude/skills/`. They're self-contained.

## Phase 3 — Global governance (if A)

Copy `templates/global-CLAUDE.md` to `~/.claude/CLAUDE.md` (back up any existing one
first). Adapt the maintenance section to the user's chosen trigger model (Phase 5). Remove
the parts the user didn't opt into.

## Phase 4 — Knowledge vault / LLM-wiki (if B)

1. Create the vault folder at the user's chosen location.
2. Put `templates/vault-CLAUDE.md` there as the vault's `CLAUDE.md` (this is the schema).
3. Create the structure it defines: `raw/sources/`, `raw/assets/`,
   `wiki/{entities,concepts,sources,queries,notes,meta}/`, and empty
   `wiki/meta/index.md` + `wiki/meta/log.md`.
4. `git init` (with the `--separate-git-dir` tip if in a cloud folder). Optionally open in
   Obsidian.
5. Tell the user how to drive it: "ingest <file>", "lint the wiki", "synthesize <topic>",
   "challenge this", "connect A and B", "what's emerging" — the operations are in the
   vault's CLAUDE.md.

## Phase 5 — Maintenance automation (if C)

Deploy `templates/scripts/check-updates.ps1` and `backup-config.ps1` to
`~/.claude/maintenance/`, editing the placeholder paths (e.g. the backup repo path).

**Choose the trigger:**
- **Normal Claude Code install** → a Windows Task Scheduler job can run the check
  unattended.
- **MSIX/Store-packaged app or host-managed auth** → unattended `claude -p` will 401 and
  Task Scheduler won't see the app's npm globals. Use a **session-driven** trigger encoded
  in `~/.claude/CLAUDE.md` (date-marker gated), run in-session. To detect: check whether
  `AppData\Roaming\npm` is a reparse point into `…\Packages\…\LocalCache\…` (→ MSIX), or
  whether `claude -p "hi"` returns 401.

For the backup, help the user create a **private** git repo of their own authored
artifacts (their `~/.claude` skills/CLAUDE.md/scripts) and wire `backup-config.ps1` to it.

## Phase 6 — Extras (if D) & heavy/manual pieces

Impeccable and the Obsidian skills are in `manifest.md`. Domain tools (a CAD plugin, KiCad
MCP, MATLAB MCP, PlatformIO, etc.) are the user's own choice and often need per-tool setup
and their own credentials — install only what they ask for.

## Phase 7 — Finish

- Remind the user to **restart the Claude app** (plugins/skills/CLAUDE.md load at start).
- List what still needs **their** credentials (e.g. a web-search/scrape API key).
- Summarize what you installed and what you deliberately skipped.

## What this scaffold intentionally omits

No personal memory, no project data, no secrets, no machine-specific paths. The author's
own instance stays private; this is only the reusable shape.
