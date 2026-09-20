# SCAFFOLD - the playbook for the setup agent

**You are an agent.** Someone cloned this repository and asked you to set up their
environment "using this scaffold". This file is your playbook.

This is a **structure to reproduce, not a configuration to copy.** Everything here is
generic, with placeholders where real values belong. Your job is to install what they want
and instantiate the templates **on their machine, adapting paths and asking their
preferences.** Never invent their details - ask.

## Ground rules

1. **Adapt, do not transplant.** Replace every `<PLACEHOLDER>` with their actual value.
   Deploy targets live under the agent home; derive it from the environment rather than
   writing an absolute path.
2. **Ask before installing anything**, and confirm each phase. Surface your assumptions out
   loud rather than acting on them quietly.
3. **Back up before you overwrite.** If a governance file, a hook or a settings file already
   exists, copy it aside first and say where you put it. Someone else's configuration is
   not yours to replace silently.
4. **Windows and PowerShell** is the assumed host. On macOS or Linux, translate the shell
   steps and say clearly which ones you translated - a script that was not run is not a
   script that passed.
5. **The vault ships empty.** It is their knowledge, not the author's.

## The paths this playbook uses

Every `<PLACEHOLDER>` below is a real location you must establish before Phase 1. **Confirm
them with the user rather than assuming** - a host that stores its configuration elsewhere
is exactly the case where a silent wrong guess costs the most, because nothing errors: the
files land where nothing reads them.

| Placeholder | What it is | Usual value on this stack |
|---|---|---|
| `<AGENT-HOME>` | The agent's configuration directory | `$env:USERPROFILE/.claude` |
| `<SETTINGS-FILE>` | The user-scope settings file that holds `hooks` and `permissions` | `<AGENT-HOME>/settings.json` |
| `<HOOKS-DIR>` | Where hook scripts live | `<AGENT-HOME>/hooks` |
| `<SKILLS-DIR>` | The global skills directory | `<AGENT-HOME>/skills` |
| `<MAINTENANCE-DIR>` | Maintenance scripts and their date markers | `<AGENT-HOME>/maintenance` |

Three more are **the user's choice** and are collected in Phase 0, not derived:

| Placeholder | What it is | Constraint |
|---|---|---|
| `<MEMORY-STORE>` | The single physical memory folder | Inside a git repository they control |
| `<LESSONS-FILE>` | Their `LESSONS.md` | Backed up; not a scratch folder |
| `<CORRECTIONS-LOG>` | Their corrections log | Next to the lessons file, and backed up with it |

The last three are deliberately **not** under `<AGENT-HOME>`. That directory is application
state - it gets rewritten by updates and is not version-controlled - and these three files
are the ones you least want to lose. Deploy targets that are *configuration* go under the
agent home; targets that are *accumulated knowledge* go in a repository.

**Deployed files get their `.template` suffix removed**, and their contents keep the name
their consumer expects: `CLAUDE.md.template` becomes the global instruction file,
`MEMORY.md.template` becomes `MEMORY.md`, `log.md.template` becomes `log.md`.
`memory-file.template.md` keeps its name - it is a form to copy per memory, not a file to
deploy once.

## Phase 0 - interview

Ask which parts they want. They are independent, except that `automation/`'s session-start
hook has nothing to inject unless `core/` gave it a lessons file and a memory index - say so
if they want C without A, rather than delivering a hook with two of its three blocks dark.

- **A. `core/`** - governance, lessons, memory, corrections, handoff, review map. This is
  the part worth having even alone.
- **B. `stack/`** - the skill and plugin inventory. Dated; treat it as a starting list to
  prune, not a shopping list to complete.
- **C. `automation/`** - hooks, maintenance, verification.
- **D. `vault/`** - the knowledge wiki. If yes, ask where it should live and warn about
  cloud-synced folders (`vault/structure.md` has the git setup that survives one).

Also ask what they already have: agent CLI, Node, git. Then collect the four locations the
playbook cannot derive:

- **The private backup repository** for their configuration - several pieces below want its
  path. If they do not have one, offer to create it; the alternative is that the three
  knowledge files below live only in application state.
- **`<MEMORY-STORE>`**, **`<LESSONS-FILE>`** and **`<CORRECTIONS-LOG>`** - defaulting to
  that repository is a good suggestion, not an assumption to make silently.

Finally, confirm `<AGENT-HOME>` and the four paths derived from it, from the table above.
One question, and it removes the single largest class of silent failure in this playbook.

## Phase 1 - `core/` (if A)

Deploy in this order, because each one is referenced by the next:

1. `core/lessons/LESSONS.md` to `<LESSONS-FILE>`. Tell them plainly that the ten families
   are **seeds from someone else's practice**, and that the second-occurrence rule is how
   they grow their own.
2. `core/corrections/log.md.template` to `<CORRECTIONS-LOG>`, suffix removed. **Keep the
   leading `- ` in its line format**: the session-start hook counts entries by it.
3. `core/memory/` - create `<MEMORY-STORE>`, copy `MEMORY.md.template` in as `MEMORY.md`
   and `memory-file.template.md` alongside it, then run `Set-MemoryJunctions.ps1
   -MemoryRoot <MEMORY-STORE> -SiloRoot <AGENT-HOME>/projects` **without `-Apply` first**,
   so they see what it would change before it changes anything. **Every path the dry run
   prints must end in `\memory`** - it converts `<cwd>\memory`, never `<cwd>`. If it lists
   project directories, stop and do not apply; `core/memory/README.md` shows the expected
   output.
4. `core/governance/CLAUDE.md.template` to `<AGENT-HOME>` as the global instruction file.
   Replace `<MEMORY-PATH>`, `<LESSONS-PATH>` and `<CORRECTIONS-PATH>` with the three paths
   just established - which is why this step comes after them, not before.

   Delete whole `##` sections only for parts they declined: `## Maintenance` belongs to C,
   `## Cross-project knowledge` to A. Leave the rest; a rule they did not ask about is
   cheaper to read than a gap they have to notice.
5. `core/handoff/PLAN.md` into a project when substantive work starts, and
   `core/handoff/codex-AGENTS.md` if they use a second agent.
6. `core/review/README.md` is reading material, not a deployable. Point them at it.

## Phase 2 - `automation/` (if C)

1. Copy the three hooks into `<AGENT-HOME>/hooks/` and wire them into the settings file.
   The wiring JSON is in `automation/hooks/README.md`. **Wire the PreToolUse pair for both
   shell-capable tools** - the ones named `Bash` and `PowerShell` - because a guard covering
   one of two shells is a door left open.

   If this host has a *third* tool that can run shell commands, wiring the guard to it is
   not enough: `block-dangerous-git.ps1` answers any event whose tool name is outside its
   own allowlist with exit 2, so a third name turns the guard into a wall that blocks
   everything. Add the name to the allowlist in the script **and** to the wiring, or leave
   both alone.

2. Edit the configuration block at the top of **`session-start.ps1` and
   `review-before-commit.ps1`** - both have one - to point at the lessons file, memory index
   and corrections log from Phase 1. Leave a path empty to switch that block off; a path
   that is set but does not resolve produces a warning, which is deliberate.
3. Deploy `automation/maintenance/` into `<MAINTENANCE-DIR>` - both scripts **and**
   `weekly-routine.md`, which is what the session-start hook names when the weekly marker
   goes overdue. Delete the routine's steps whose subsystem they declined. Fill in
   `backup-config.ps1`'s two configuration values with the private backup repository from
   Phase 0. Create the folder itself: the hook warns when it is missing, and on a fresh
   install it always is.

   Do not skip the routine because it looks like documentation. The corrections log has no
   periodic reader without it, and a log nobody reads never produces a second occurrence -
   which disables the promotion rule that `core/` is built around.
4. Choose a maintenance trigger using `automation/triggers.md`. **Run the detection test
   for their host** rather than assuming - two of the three paths fail silently on the
   wrong machine, and a silent failure here means maintenance that never runs and never
   says so.
5. `automation/verification/` - copy `Assert-Baseline.ps1` with its example assertions
   replaced by their decisions, and set up the secret scanner.

   **The scanner needs a binary this repository does not ship.** `stack/manifest.md`
   section 6 has the version, the URL and the checksum step - follow it, then put the
   binary where `Invoke-Gitleaks.ps1` expects it or pass `-GitleaksPath`. Call the wrapper
   from a `pre-commit` hook in each repository they want scanned, and **pin the version in
   that hook so it refuses a different one**; there is no hook template here because it is
   a few lines and writing it for their layout beats shipping one that assumes it.

   If you cannot complete this step, **say so in the Phase 5 summary** rather than leaving
   a wrapper that exits 2 forever and a person who believes they have a secret scanner.

## Phase 3 - `stack/` (if B)

Work from `stack/manifest.md`, and read `stack/README.md` **to them** first, or at least
the warning: it is a dated snapshot, not a recommendation. Install by name, never "all
minus a list". Skip anything they cannot say they will use.

The four skills in `stack/skills/` copy into their global skills directory.
`scientific-project-report` keeps its own licence file alongside it.

## Phase 4 - `vault/` (if D)

1. Create the folder tree from `vault/structure.md`.
2. Copy `vault/AGENTS.md.template` in as the vault's instruction file, adapting paths.
3. `git init` - with `--separate-git-dir` if it sits in synced storage - and set up LFS
   **before** the first binary is committed.
4. Tell them how to drive it, and mention **harvest** specifically: it is the operation that
   collects learning out of their code repositories, and the one people leave out.

## Phase 5 - finish

- Remind them to **restart the application** so hooks and instructions load.
- List what still needs **their** credentials. You never had them and never should.
- Summarise what you installed, and say explicitly **what you skipped and why**. A setup
  report that only lists successes is the one that gets believed and should not be.
- Tell them where their backup repository is and what it now contains.

## What this scaffold deliberately omits

No personal memory, no project data, no secrets, no real paths, and no domain toolchain
instructions. The author's own instance stays private; this is only the reusable shape.
