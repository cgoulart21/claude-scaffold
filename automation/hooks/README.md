# Hooks

Three hooks. Two guard, one informs. The informing one is the reason this folder exists.

| Hook | Event | Blocks? |
|---|---|---|
| `block-dangerous-git.ps1` | `PreToolUse` | yes - exit 2 stops the tool call |
| `review-before-commit.ps1` | `PreToolUse` | never - advisory only |
| `session-start.ps1` | `SessionStart` | n/a - prints context |

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

## Wiring

Add to your settings file. `PreToolUse` hooks receive the event on stdin and are matched per
tool; `SessionStart` runs once when a session opens.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$env:USERPROFILE/.claude/hooks/block-dangerous-git.ps1\"" },
          { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$env:USERPROFILE/.claude/hooks/review-before-commit.ps1\"" }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$env:USERPROFILE/.claude/hooks/session-start.ps1\"", "timeout": 15 }
        ]
      }
    ]
  }
}
```

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
