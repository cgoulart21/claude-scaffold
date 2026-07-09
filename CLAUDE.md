# CLAUDE.md — claude-scaffold

A **scaffold** (generic, shareable) for bootstrapping a Claude Code environment on Windows:
a curated skill stack, an optional Obsidian LLM-wiki, governance instructions, and maintenance
automation — shipped as **templates with no personal data**. MIT-licensed.

## Two ways you might be here

- **You cloned this to set up *your* environment** → don't hand-copy anything. Open Claude Code here
  and say **"Set up my Claude Code using SCAFFOLD.md."** `SCAFFOLD.md` is the agent playbook: it
  interviews you (which parts, vault location, automation model), then installs + instantiates the
  templates **on your machine, adapting paths and asking your preferences**.
- **You're maintaining the scaffold itself** → follow the golden rule below.

## ⚠️ Golden rule — keep it generic

This repo is a **structure to reproduce, not a config to copy.** Everything here must stay free of
personal data:

- **No secrets, no personal paths, no machine-specific values, no project/knowledge content.** Use
  placeholders (`<...>`, `$env:USERPROFILE`) — never real usernames, tokens, or absolute personal paths.
- The knowledge vault ships **empty** — it's the user's knowledge, not the author's.
- A **private instance** (the author's actual `~/.claude` artifacts + restore) lives in a **separate
  private repo** — anything personal belongs there, never here. Improvements to the *reusable shape*
  come back to this scaffold; personal state does not.
- "Adapt, don't transplant" and "ask before installing / surface assumptions" are baked into
  `SCAFFOLD.md`; keep edits consistent with that posture.

## Files

```
SCAFFOLD.md   the playbook the setup agent follows (Phase 0 interview -> 7 finish)
templates/    global governance, LLM-wiki schema (vault-CLAUDE.md), the two authored
              skills (source-grounded, design-smells), maintenance scripts, codex-AGENTS.md, PLAN.md
manifest.md   exact install commands (marketplaces, plugins, skills, CLIs) + versions
CREDITS.md    attribution to every upstream this stack reinstalls
```

- **Windows-first** (scripts are PowerShell); plugin/skill installs are cross-platform — translate the
  shell steps on macOS/Linux.
- Almost everything reinstalls **other people's work from source** (see `CREDITS.md`); the authored
  templates are the two skills + the governance/schema. Ideas were **mined, not vendored**.
