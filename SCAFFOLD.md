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

## Phase 0 - interview

Ask which parts they want. They are independent; none requires another:

- **A. `core/`** - governance, lessons, memory, corrections, handoff, review map. This is
  the part worth having even alone.
- **B. `stack/`** - the skill and plugin inventory. Dated; treat it as a starting list to
  prune, not a shopping list to complete.
- **C. `automation/`** - hooks, maintenance, verification.
- **D. `vault/`** - the knowledge wiki. If yes, ask where it should live and warn about
  cloud-synced folders (`vault/structure.md` has the git setup that survives one).

Also ask what they already have: agent CLI, Node, git. And ask whether they keep a private
backup repository for their own configuration - several pieces below want its path.

## Phase 1 - `core/` (if A)

Deploy in this order, because each one is referenced by the next:

1. `core/governance/CLAUDE.md.template` to their agent home as the global instruction file.
   **Replace the three placeholders** with the paths chosen in the following steps, and
   delete the sections they did not opt into.
2. `core/lessons/LESSONS.md` into a location they control and back up - ideally a private
   git repository, not a scratch folder. Tell them plainly that the ten families are
   **seeds from someone else's practice**, and that the second-occurrence rule is how they
   grow their own.
3. `core/memory/` - create the memory store, copy `MEMORY.md.template` and
   `memory-file.template.md` in, and run `Set-MemoryJunctions.ps1` **without `-Apply`
   first** so they can see what it would change before it changes anything.
4. `core/corrections/log.md.template` as their corrections log.
5. `core/handoff/PLAN.md` into a project when substantive work starts, and
   `core/handoff/codex-AGENTS.md` if they use a second agent.
6. `core/review/README.md` is reading material, not a deployable. Point them at it.

## Phase 2 - `automation/` (if C)

1. Copy the three hooks from `automation/hooks/` and wire them into the settings file. The
   wiring JSON is in `automation/hooks/README.md`. **Wire the PreToolUse hooks for every
   tool that can run a shell command**, not just one - a guard covering one of two shells
   is a door left open.
2. Edit the configuration block at the top of `session-start.ps1` to point at the lessons
   file, memory index and corrections log from Phase 1. Leave a path empty to switch that
   block off.
3. Choose a maintenance trigger using `automation/triggers.md`. **Run the detection test
   for their host** rather than assuming - two of the three paths fail silently on the
   wrong machine, and a silent failure here means maintenance that never runs and never
   says so.
4. `automation/verification/` - set up the secret scanner in a pre-commit hook, and copy
   `Assert-Baseline.ps1` with its example assertions replaced by their decisions.

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
