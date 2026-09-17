# Sanitization gate

This repository is a scaffold: it ships shapes, not anyone's data. The gate below is what
makes that claim checkable instead of aspirational.

Everything under `tools/` is deliberately **ASCII-only**, including this file: Windows
PowerShell 5.1 reads a UTF-8 file without BOM through the legacy ANSI code page, and a
single typographic dash there can break a script's parse.

## What it is

One scanner that knows no patterns. The patterns are data, passed in with `-PatternFile`:

```powershell
.\tools\check-no-personal-data.ps1 -Path . -PatternFile .\tools\patterns.txt
```

`patterns.txt` in this repository holds **structural** markers only - no proper nouns. That
is the point: a nominal denylist (real names, handles, project names) can reuse this same
scanner from a *private* repository, without the list itself ever becoming public. A
denylist published next to the thing it protects leaks exactly what it was written to hide.

## The six patterns

| id | what it catches |
|---|---|
| `win-user-path` | a Windows user-profile path carrying a real account name: `C:\Users\<username>` passes, the same path with the placeholder replaced does not. The accepted placeholders are `<username>`, `<user>`, `$env:USERNAME` and `%USERNAME%` |
| `bash-user-path` | the Git Bash spelling of the same thing: `/c/Users/<username>` passes, a real account name there does not |
| `abs-drive-path` | any absolute drive-letter path outside the documentation placeholders `C:\Projects\` and `C:\Path\To\` |
| `email` | any e-mail address outside the reserved domains `example.com` and `example.org` |
| `artifact-url` | links to a published artifact or document |
| `session-silo` | paths naming a per-working-directory session silo - the `projects` folder inside `.claude` - because those names are the machine's directory layout |

The placeholder allowlist is short and closed on purpose. Forcing every example onto the
same fictional root is better teaching *and* it is what makes the rule mechanical. A rule
that reads "unless it is obviously an example" is a judgement call wearing a gate's uniform.

## What it does NOT cover

**A green run means no enumerated pattern matched - not that the tree is free of personal
data.** Specifically, it will not catch:

- **proper nouns nobody enumerated** - a collaborator's name, a grant number, an internal
  codename. Those need a human reading the diff;
- **anything inside a binary file** - only the text extensions listed in the script are
  read;
- **secrets** - use a dedicated scanner such as Gitleaks. This gate is about identity and
  location, not credentials;
- **meaning** - a sentence that identifies someone without matching a pattern passes.

Name the level you validated. This gate validates "no enumerated pattern matched".

## Exit codes

| code | meaning |
|---|---|
| `0` | clean: every scanned file was free of the enumerated patterns |
| `1` | hits found: each one printed as `HIT <id> <path>:<line>` followed by the line |
| `2` | usage or IO error: the pattern file is missing, unreadable, or contains no patterns |

`2` exists so that a gate which could not run never reports success. A check that did not
run and a check that passed are opposite facts, and collapsing them into `0` is how a gate
becomes decorative.

## Path exclusions

Exactly one: `patterns.txt` is skipped when the scanner runs against its own repository,
because the file necessarily contains the patterns it defines. `.git/` is skipped as well,
being version-control internals rather than published content.

There is no exclusion for the test suite, and there should never be one. Two mechanisms make
that possible:

1. the suite writes its fixtures into `$env:TEMP` and deletes them, so no planted **file**
   is ever created inside the repository;
2. the planted **strings** are assembled at runtime from fragments that match nothing on
   their own, so no complete offending literal sits in the suite's source either.

The second one is easy to forget, and forgetting it is what pushes people toward an
exclusion: the fixtures were in a temp directory, but the strings were plain literals in
the test file, and the gate flagged them - correctly, since it cannot tell a synthetic
account name from a real one and should not have to. Every exclusion is a hole, and a gate
full of holes stops enumerating the thing it claims to cover.

## Running it

```powershell
.\tools\Test-CheckNoPersonalData.ps1   # 25 assertions: the gate itself
.\tools\check-no-personal-data.ps1 -Path .
```

CI runs both on every push and pull request (`.github/workflows/sanitize.yml`), in that
order. The suite comes first: a broken scanner that exits `0` would sail through the scan
without reading a single file, and only the suite proves that `1` is still reachable.
