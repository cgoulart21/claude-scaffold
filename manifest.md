# Manifest — the stack, and how to reinstall it

Everything is reinstalled **from its own source** (nothing is vendored here). Pin versions
if you want reproducibility; otherwise these install latest. Run installs from **inside a
Claude session's terminal** if your app is MSIX-packaged (see SCAFFOLD Phase 5).

## 1. Marketplaces  (`claude plugin marketplace add <src>`)

| Marketplace | Source | Note |
|---|---|---|
| superpowers-marketplace | `obra/superpowers-marketplace` | |
| text-to-cad | `earthtojake/text-to-cad` | *(optional; CAD)* add with `--sparse .claude-plugin plugins` |
| kicad-happy | `aklofas/kicad-happy` | *(optional; KiCad)* |
| openai-codex | `https://github.com/openai/codex-plugin-cc.git` | *(optional)* git URL |
| claude-plugins-official | `anthropics/claude-plugins-official` | usually preinstalled (has firecrawl) |

## 2. Plugins  (`claude plugin install <name>@<mkt> --scope user`)

| Plugin | Note |
|---|---|
| `superpowers@superpowers-marketplace` | **core only** — skip its memory plugins (`episodic-memory`, `private-journal-mcp`) and Unix-first ones (`claude-session-driver`) |
| `firecrawl@claude-plugins-official` | web search/scrape *(needs your own API key)* |
| `cad@text-to-cad` · `kicad-happy@kicad-happy` · `codex@openai-codex` | optional, domain-specific |

## 3. Third-party skills  (`npx skills add <repo> --skill <s> --global --copy -y`)

| Repo | Skills |
|---|---|
| `mattpocock/skills` | `*` (all), then **prune** the ones Superpowers covers |
| `vercel-labs/skills` | `find-skills` |
| `rebelytics/one-skill-to-rule-them-all` | `task-observer` |
| `kepano/obsidian-skills` | `obsidian-markdown`, `defuddle` *(optional; needs `npm i -g defuddle`)* |

**Prune (Superpowers is the backbone):** remove the mattpocock duplicates
`tdd`, `diagnosing-bugs`, `writing-great-skills`, `grill-me` —
`npx skills remove --skill <name> -g -y`. Keeping `diagnose` + `grilling` is a good default.

**Customized skills override upstream:** `diagnose` (upstream: mattpocock/skills) is
customized in this scaffold — after installing the third-party skills, deploy
`templates/skills/diagnose/SKILL.md` OVER the upstream copy. `design-smells` and
`source-grounded` are authored here and deploy from `templates/skills/` as usual.
All three carry the description gating convention: explicit `TRIGGER —` / `SKIP —`
clauses (see the cross-cutting principle in `~/.claude/skill-observations/`); never
use colon-space inside an unquoted YAML scalar.

The `PromptScript does not support global skill installation` warning is harmless — the
`SKILL.md` still copies.

## 4. CLIs  (`npm install -g <pkg>`)

| Package | Feeds |
|---|---|
| `@openai/codex` | codex *(optional)* |
| `firecrawl-cli` | firecrawl skills *(needs auth)* |
| `defuddle` | the `defuddle` skill |

The `skills` CLI and `impeccable` are used via `npx` (not installed globally).

## 5. Authored skills (from `templates/skills/`)

Copy `source-grounded` and `design-smells` into `~/.claude/skills/`.

## 6. Impeccable — front-end design (optional)

`npx impeccable install` defaults to **project** scope. For a global skill without a global
hook, install then move the skill folder to `~/.claude/skills/impeccable`, and add its
PostToolUse hook + `/impeccable init` **per front-end project** only.

## 7. Heavy / domain-specific (install only what you use)

CAD venvs (build123d/OCP), KiCad/MATLAB MCP servers, PlatformIO, etc. are the user's own
choice — each has its own setup and often pinned/coupled versions and its own credentials.
When a plugin ships a Python runtime, remember its venv may need re-syncing after a plugin
update (that's a per-tool script, not part of this scaffold).
