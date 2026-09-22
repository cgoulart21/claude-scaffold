# Hooks

Three hooks. Two guard, one informs. The informing one is the reason this folder exists.

| Hook | Event | Blocks? |
|---|---|---|
| `block-dangerous-git.ps1` | `PreToolUse` | yes - exit 2 stops the tool call |
| `review-before-commit.ps1` | `PreToolUse` | never - advisory only |
| `session-start.ps1` | `SessionStart` | n/a - prints context |

**Compaction is a session boundary, and the host treats it as one.** When a long session
compacts, the block this hook printed is summarised away with everything else - and that
block was the only path by which the lesson families and the tool gotchas reached the
context at all. You do not need a second registration to put it back: `SessionStart` fires
again after compaction (its `matcher` is `compact` on that start), so the same hook reprints
the same block into the fresh context. Measured on one practice: 36 post-compaction starts,
every one with the block.

Until 2026-09-20 this table advertised a `-IndexOnly` switch on `PreCompact`. The switch did
not exist in the published script, and the idea behind it was wrong: a `PreCompact` hook
runs *before* the summary, so what it prints goes into the region about to be discarded.
A second machine found the phantom switch; the measurement above found the wrong idea.

If you want the post-compaction start to say something different from the first start -
"the plan file may now be stale; refill `Done`/`Next`" is the useful thing - read the event's
`source` field from stdin and branch on `compact`. This script does not do that yet; it
prints the same block on every start, which is correct and merely repetitive.

## Why `session-start.ps1` matters more than the other two

Guardrails are easy to imagine and easy to find elsewhere. The session-start hook solves a
quieter problem: **a rule written down is not a rule that gets read.**

One practice audited its own history and found eighteen separate rediscoveries, across eight
projects, of a lesson that was already written in a file that was available the whole time.
Available is not read. Pointing at a file only works if the session already knows it needs
to open it - which is precisely the condition you cannot guarantee.

So this hook **prints** the lesson titles and the tool gotchas into the session, costing a
handful of lines per session, in exchange for the rule being in context *before* it bites
rather than in the postmortem afterwards.

Two design choices follow from that, and both matter:

- **Titles are read from the source file, never duplicated into the hook.** A hardcoded
  title drifts silently the day someone edits the real file.
- **A configured path that does not resolve produces a loud warning, not a quiet skip.**
  Silent loss is the only unacceptable failure here: a moved repository would otherwise put
  every session back in the state this hook exists to remove, with nothing to show for it.

An unconfigured block, on the other hand, says nothing at all. Off is off; broken is loud.

**Block 3 may be redundant on your host.** Claude Code injects the memory index of the
current project into every session on its own (the auto-memory feature). If your index is
that file, block 3 prints the same gotchas a second time - noise that trains the reader to
skip the whole block, which is the failure this hook exists to prevent. On such a host
leave `MemoryIndexPath` empty. The block earns its place when the index lives somewhere the
host does not read, or on a host without auto-memory. One practice measured its own
duplicate at about a thousand tokens per session start.

## Wiring

Add to your settings file. `PreToolUse` hooks receive the event on stdin and are matched per
tool; `SessionStart` runs when a session opens, resumes, or restarts after compaction.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$USERPROFILE/.claude/hooks/block-dangerous-git.ps1\"" },
          { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$USERPROFILE/.claude/hooks/review-before-commit.ps1\"" }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$USERPROFILE/.claude/hooks/session-start.ps1\"", "timeout": 15 }
        ]
      }
    ]
  }
}
```

**The variable must match the shell, and the shell is bash.** On Windows the host runs a
hook command in `bash` when Git Bash is installed and in `powershell` only when it is not.
The two spellings of the profile path each resolve under exactly one shell: in bash
`$USERPROFILE` resolves (Git Bash imports the Windows environment) while `$env:USERPROFILE`
becomes the literal `:USERPROFILE`; in PowerShell it is the reverse. So the pairing is what
matters, never either half alone - and a `PreToolUse` guard whose path does not resolve does
not start, and a guard that does not start does not block, with no warning.

Use `$USERPROFILE` with the **default** shell, as above: wherever there is a Bash tool to
guard, Git Bash exists to run the hook, so this pairing works on every machine that has
something to protect. **Do not use `"shell": "powershell"` for a guard, even correctly
paired with `$env:USERPROFILE`.** An earlier version of this page said that form "also
works". It runs, but it cannot block: with `"shell": "powershell"` the host executes the
hook command through `powershell -Command`, and the `-Command` of Windows PowerShell 5.1
flattens every non-zero exit to 1. Measured on 2026-09-22 by feeding the real guard a
valid force-push event: through `bash -c` the caller receives exit 2 (block); through
`powershell -Command` it receives exit 1, with `BLOCKED` printed. The host reads 2 as
"block" and 1 as "non-blocking error, continue", so the dangerous command runs under a
BLOCKED banner. A second machine that had carried that form for six weeks confirmed it by
behaviour: a force push and a hard reset both ran in a fixture, guard logic intact when fed
directly. The `review-before-commit` reminder kept working the whole time - it needs only
stdout and exit 0 - which is what hid the hole. `pwsh` 7.6.6, measured on that second
machine the same day, flattens the same way: no PowerShell path delivers the 2, and the bash
pairing never depended on which shell the host picked. Two earlier versions of
this example were each half-right: one used `$env:USERPROFILE` under no shell (works under
neither), the next added `"shell": "powershell"` (starts, but cannot block).
`Assert-Baseline.ps1` in `../verification/` fails on the powershell form for this reason.

Repeat the `PreToolUse` block for every tool name that can run a shell command - on this
stack that means `Bash` and `PowerShell`. A guard wired to one of them and not the other is
a guard with a door left open, which is family 1: it is worth exactly what it enumerates.

## Configuration

`session-start.ps1` and `review-before-commit.ps1` both carry a short configuration block at
the top. Set the paths to your own lessons file, memory index and corrections log; leave a
path empty to switch that block off. Nothing is hardcoded to the author's layout.

## A byte order mark will silently disable a hook

Both `PreToolUse` hooks parse their event from stdin as JSON, and a leading byte order mark
makes that parse fail. The failure does not look like a failure: the guardrail reports
`BLOCKED: could not parse the event` and **every** command comes back blocked, including
ordinary ones.

Both hooks now discard anything before the opening brace. **Trimming `U+FEFF` is not
enough**, and that is the part worth remembering: stdin is decoded in the console code page,
so the BOM's three bytes usually arrive as three unrelated characters and never match the
character you were looking for. A fix that searches for the brace works regardless of how
the bytes were decoded; a fix that searches for the BOM works only where you tested it.

The same trap catches the tests. Writing a fixture with `Set-Content -Encoding UTF8` on
Windows PowerShell 5.1 produces a BOM, which made an early version of this suite pass its
blocking assertions for entirely the wrong reason - exit 2 because the parse died, not
because the pattern matched, while every allowing assertion failed and pointed at the hook
instead of at the fixture. `tools/Test-Automation.ps1` writes fixtures with
`[IO.File]::WriteAllText` and keeps two regression cases: a BOM-prefixed event must still be
allowed when harmless and still blocked when dangerous. One case alone would not have caught
it, because "blocked" was the wrong-reason answer.

## Testing them

```powershell
.\tools\Test-Automation.ps1
```

The hooks are fed real events on stdin and judged by exit code and output. A hook asserted
only by reading its source is a hook nobody proved fires.
