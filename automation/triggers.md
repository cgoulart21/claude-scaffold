# Choosing a trigger

Maintenance only works if something fires it. There are three ways to do that, they are
not interchangeable, and **two of them fail silently on the wrong host** - which is the
worst possible outcome, because a maintenance routine that never runs looks exactly like a
maintenance routine with nothing to report.

Pick by measuring your host, not by preference.

---

## Path 1 - the operating system's scheduler

A Task Scheduler job (or `cron`, or a systemd timer) runs your scripts unattended.

**When it works:** an ordinary installation, where your agent CLI and your global packages
live in real directories that any process on the machine can see, and authentication does
not depend on a running application.

**How to tell:** run your agent CLI non-interactively from a plain terminal - not from
inside the agent - and see whether it authenticates and returns. If it returns a `401`, or
cannot find globally installed packages, this path is not available to you, whatever the
documentation says.

**The trap:** it looks like it is working. The job runs, the script starts, a command
inside it fails for an environment reason, and the report is written anyway - empty. Guard
every step, and make "could not check" a distinct outcome from "nothing to report".

---

## Path 2 - session-driven, gated by a dated marker

Nothing runs unattended. A `SessionStart` hook reads a date marker and, when it is old
enough, prints a reminder. The routine runs **in session**, executed by the agent, with
whatever authentication and environment a session already has.

**When it works:** always. This is the fallback that has no host requirements, and it is
the right default when you are unsure.

**How to tell:** you do not need to tell - it works wherever the hook runs. Prefer it if
your host application is sandboxed or packaged, because in that case the first path is
unavailable *and* usually appears to work.

**The trap:** it only fires when you open a session, so a two-week gap in your work is a
two-week gap in maintenance. That is usually fine: nothing needs maintaining while nothing
is happening.

`automation/hooks/session-start.ps1` implements this path. The markers are plain files
holding a date:

```
<maintenance-root>/last-run              the weekly routine
<maintenance-root>/updates-last-check    the update and backup check
```

The routine writes today's date into the marker when it finishes. Nothing else touches
them, and a marker that cannot be parsed is reported as missing rather than treated as
fresh - again, "could not check" is not "nothing to report".

---

## Path 3 - a scheduled-task facility offered by the host

Some host applications expose their own scheduling, running the task inside the application
context - so it inherits the same authentication and the same view of the filesystem that a
normal session has.

**When it works:** when your host offers it. This is the only unattended path that survives
a sandboxed host, because it runs *inside* the sandbox rather than beside it.

**How to tell:** look for a scheduling capability in the host itself, and then **verify one
real firing end to end** before relying on it. A scheduler that accepted your task is not a
scheduler that ran it - the acceptance and the firing are different facts, and only the
second one matters.

**The trap:** the task is stored somewhere the rest of your configuration is not, so it
does not travel with your dotfiles and it will not exist on a new machine. Keep a copy of
the definition in your backup repository.

---

## The sandbox question, which decides most of this

If your host application is packaged or sandboxed, paths that look absolute are not. A
process started outside the sandbox sees the real directory; the application sees a
redirected one. The two disagree, silently, and the symptom is a tool that "is not
installed" despite being installed.

**How to tell:** check whether the relevant directory is a reparse point redirecting into
an application-private location:

```powershell
$probe = Join-Path $env:APPDATA 'npm'
if (Test-Path -LiteralPath $probe) {
    $item = Get-Item -LiteralPath $probe -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        'redirected - path 1 will not see what the application sees'
    } else {
        'a real directory'
    }
}
```

If it is redirected, use path 2 or path 3 and stop trying to make path 1 work.

---

## What not to do

Do not run an unattended job that *applies* updates. Detection and application are
separate on purpose (see `maintenance/check-updates.ps1`): an updater that applies on a
schedule will eventually unpin something you pinned for a reason, on a day nobody was
reading the output.
