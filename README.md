# claude-scaffold

A scaffold for setting up an agent-assisted development environment: the governance file,
the memory system, the error-lesson discipline, the hooks, the maintenance triggers and an
optional knowledge vault.

It is **not** a copy of somebody's configuration. It ships shapes with the values left as
placeholders, plus a playbook an agent follows to instantiate them on your machine.

## The durability contract

This is the first thing to understand, because the layout encodes it:

| Folder | Rots | What it holds |
|---|---|---|
| `core/` | **never** | Method, discipline, schemas. Governance, lessons, memory, corrections, handoff, review |
| `stack/` | **fast** | A dated inventory of tools. Carries a date stamp and a warning |
| `automation/` | slowly | Hooks, maintenance scripts, trigger selection, verification patterns |
| `vault/` | slowly | An optional knowledge wiki - schema only, ships empty |

An earlier version of this repository had no such split. Every file looked equally current,
so nothing could say *this one does not need updating* - and it spent months confidently
teaching a governance file its author had already rewritten. The split is the fix, and the
rule that keeps it working is in `CLAUDE.md`.

**Read `core/` first.** It is the part that is still true after every tool named in `stack/`
has been replaced.

## Quick start

1. Install the prerequisites: your agent CLI, Node, git. PowerShell ships with Windows.
2. Clone this repository and open your agent inside it.
3. Say: **"Set up my environment using SCAFFOLD.md."**
4. Answer the questions - which parts you want, where the vault goes, which maintenance
   trigger fits your machine.
5. Restart the application so hooks and instructions load, then add your own credentials
   where the agent tells you they are needed.

Take the pieces you will actually maintain. A rule you do not follow is worse than no rule,
because it teaches you the file is decorative. Two subsystems used properly beat five
installed and ignored.

## What you get

- **A governance file** of eight rules, short enough to be read at the start of every
  session. It came out of an audit that cut thirty-eight rules to eight and made them *more*
  effective.
- **Ten cross-cutting lesson families** - the errors that different projects learn
  separately, each paying full price - plus the rule that grows your own.
- **A memory system** that is one physical folder behind per-directory junctions, so a fact
  learned in one project is visible from every other.
- **A corrections log** that promotes a lesson into a rule on its second occurrence, and
  has no stage in between, because that is where the previous design died.
- **Three hooks**, of which the interesting one prints your lessons and gotchas into every
  session instead of pointing at a file nobody opens.
- **Maintenance that notifies and never applies**, with three trigger mechanisms and a test
  for telling which one your host can actually run.

## What this is not

- Not a turnkey clone of anyone's setup. The agent adapts it; you decide what to keep.
- No personal data, no secrets, no real paths. A CI gate enforces that on every push, and
  `tools/README.md` is honest about what that gate does and does not catch.
- Windows-first: the scripts are PowerShell. The concepts are not, and the plugin and skill
  installs are cross-platform - you will translate the shell steps on macOS and Linux.

## Credits and licence

Most of the value here is other people's work, reinstalled from source rather than copied -
see `CREDITS.md`. The authored parts are MIT (`LICENSE`), except
`stack/skills/scientific-project-report/`, which is CC BY 4.0 and carries its own licence.
