# Laying out a machine

Where everything goes, and the three traps that make a layout look right and behave wrong.

## Prerequisites

| Need | Why |
|---|---|
| Your agent CLI or desktop application | Everything else hangs off it |
| **git** | The memory store, the lessons file and the backup repository are all repositories |
| **Node and npm** | Most skills and plugins install through it |
| PowerShell | Ships with Windows. On macOS and Linux you will translate the `.ps1` steps |

Nothing here needs administrator rights. If something asks for them, stop and find out why
before agreeing.

## The layout

```
C:\Projects\                       one root for work, whatever you call it
  my-project-a\
  my-project-b\
  my-config\                       PRIVATE repo: your knowledge lives here
    memory\                        the single physical memory store
      MEMORY.md
      some-tool-gotcha.md
    LESSONS.md
    corrections\log.md
  my-vault\                        OPTIONAL knowledge wiki, its own repo

<AGENT-HOME>\                      application state, NOT version-controlled
  CLAUDE.md                        the global instruction file
  settings.json                    permissions and hook wiring
  hooks\                           the three hooks
  skills\                          installed skills
  maintenance\                     scripts, the weekly routine, date markers
  projects\<per-directory>\memory  junctions into the store above
```

The one decision that matters: **your knowledge does not live under the agent home.**

That directory is application state. It gets rewritten by updates, it is not under version
control, and its layout is the vendor's to change. The memory store, the lessons file and
the corrections log are the three things you least want to lose and most want a history of,
so they live in a repository you control. Configuration - instructions, hooks, settings -
stays under the agent home, where the application expects it.

The junctions are what let both be true at once. The agent writes memory to the path it
expects, under its own home; that path is a link into your repository; and a fact written
from any project lands in one place and is visible from all of them. `core/memory/` has the
mechanism and the script.

## Trap 1 - the sandboxed host

If your agent application is packaged - MSIX on Windows, or any sandboxed distribution -
then paths that look absolute are not. A process started **outside** the sandbox sees the
real directory. The application sees a redirected one. They disagree, and nothing errors.

The symptom is a tool that "is not installed" while being installed, or a scheduled job that
runs, reports success, and did nothing.

How to tell:

```powershell
$probe = Join-Path $env:APPDATA 'npm'
if (Test-Path -LiteralPath $probe) {
    $item = Get-Item -LiteralPath $probe -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        'redirected - an outside process sees something else'
    } else {
        'a real directory'
    }
}
```

If it is redirected, your maintenance cannot run from the operating system's scheduler. Use
a session-driven trigger instead - `automation/triggers.md` covers all three options and the
test for each.

## Trap 2 - cloud-synced storage

A repository inside a folder that a sync client watches means two systems managing the same
`.git` directory. The result is conflicted objects, phantom modifications, and occasionally a
repository that will not open.

Keep repositories out of synced storage. If you cannot, put the git directory somewhere the
client does not watch:

```bash
git init --separate-git-dir "C:\Path\To\vault-git" "C:\Path\To\synced\vault"
```

Verify it took: the working folder should contain a `.git` **file** holding a path, not a
`.git` directory.

And the corollary that costs the most: **if a second copy of anything ever existed, decide
which one is live and write the decision down.** A dead copy that still opens is
indistinguishable from the live one, and edits made in the wrong one vanish without an
error.

## Trap 3 - long paths

Windows still defaults to a 260-character path limit, and a deep node_modules or a nested
worktree passes it easily. Enable long paths once, for your user, rather than per command:

```powershell
git config --global core.longpaths true
```

`--global` writes to your own `.gitconfig` and needs no elevation. The `--system` form
writes into Git's own installation folder under Program Files and asks for administrator
rights - which would contradict the promise at the top of this chapter. Both fix the same
problem.

Setting it for a single command does **not** persist, which produces the worst version of
this bug - it worked when you tested it and fails in the run you were not watching.

## Order of operations

1. Create the project root and the private configuration repository. `git init` it now, not
   later: the whole point is that the knowledge has a history.
2. Install the prerequisites.
3. Clone this scaffold and hand it to your agent with `SCAFFOLD.md`.
4. Answer the interview, especially the four locations it asks for.
5. Restart the application - hooks and instructions load at startup.
6. Check that it took: open a new session and see whether the lesson titles appear. If they
   do not, the hook is not wired or a path is wrong, and now is when you want to know.

That last step is the one people skip. A hook installed is not a hook that fires, and the
only cheap moment to find that out is the minute after you installed it.

---

Previous: [why any of this exists](00-why.md) · Next: [the four memories](20-the-four-memories.md).
