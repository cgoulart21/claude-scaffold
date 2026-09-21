# CLAUDE.md - maintaining this repository

A generic, shareable scaffold for an agent-assisted development environment, shipped as
templates with no personal data. MIT, except one skill that carries CC BY 4.0.

## Two ways you might be here

- **You cloned this to set up your own environment.** Do not hand-copy anything. Open your
  agent here and say **"Set up my environment using SCAFFOLD.md."** That file interviews
  you and instantiates the templates on your machine.
- **You are maintaining the scaffold itself.** Read the two rules below.

## Rule 1 - the routing rule

Every change lands in one of two places, and getting this wrong is what made an earlier
version of this repository freeze:

> **Method goes to `core/`. Inventory goes to `stack/`.**
> If you cannot tell which it is, it is not `core/` - inventory disguised as method is
> exactly what rots without announcing itself.

The test: would the sentence still be true if every tool named in it were replaced by a
competitor? If yes, it is method.

`stack/` carries a date stamp and a warning that it is perishable. `core/` carries neither,
because it does not need them. Keep it that way: the moment a version number lands in
`core/`, the contract is broken and nobody can tell which files have aged.

## Rule 2 - keep it generic

This is a structure to reproduce, not a configuration to copy. Everything must stay free of
personal data:

- **No secrets, no real paths, no machine-specific values, no project or knowledge content.**
  Use placeholders - `<PLACEHOLDER>`, `C:\Projects\`, `C:\Path\To\`, `$env:USERPROFILE`.
  Never a real username, token or absolute personal path.
- The vault ships **empty**. The lesson families ship as **seeds**, and say so in their own
  header.
- A private instance - somebody's actual configuration and its restore path - belongs in a
  **separate private repository**. Improvements to the reusable shape come here; personal
  state does not.

## The gate

`tools/check-no-personal-data.ps1` enforces rule 2 mechanically, and CI runs it on every
push and pull request. Read `tools/README.md` before trusting it: it is deliberate about
what it does **not** catch, and a green run means "no enumerated pattern matched", not "this
tree is clean".

Run the full sweep before pushing anything - it is the same list CI runs, in the same order:

```powershell
.\tools\Test-CheckNoPersonalData.ps1
.\tools\Test-CoreTemplates.ps1
.\tools\Test-SetMemoryJunctions.ps1
.\tools\Test-Automation.ps1
.\tools\Test-CheckUpdates.ps1
.\tools\Test-Stack.ps1
.\tools\Test-Docs.ps1
.\tools\Test-AssertNoControlBytes.ps1
.\tools\Test-AssertMemoryLinks.ps1
.\tools\Test-AssertMemoryIndex.ps1
.\tools\Test-AssertPlanFreshness.ps1
.\tools\Test-InvokeVaultLint.ps1
.\tools\Test-MergeCorrectionsLog.ps1
.\tools\Test-BackupPushClassification.ps1
.\tools\check-no-personal-data.ps1 -Path .
```

The suites run **before** the scan, on purpose: a broken scanner that exits 0 would sail
through the scan without reading a file, and only the suites prove a failure is still
reachable. Every suite that exercises a gate has at least one case where the gate must
**fail** on a planted defect; a gate seen only passing is not evidence.

When you add a suite, add it in three places or it will exist in none of them: this list,
`.github/workflows/sanitize.yml`, and - if it wraps a `.ps1` under `automation/` - the
ASCII/parse list in `tools/Test-Automation.ps1`.

## House conventions

- **Everything under `tools/` and every `.ps1` is ASCII-only.** Windows PowerShell 5.1 reads
  a UTF-8 file without a byte order mark through the legacy code page, and one typographic
  dash breaks the parse.
- **Target PowerShell 5.1.** No null-coalescing, no ternary, no `&&`/`||`, no
  `ConvertFrom-Json -AsHashtable`.
- **`$PSScriptRoot` is empty inside a `param()` block** when the script has
  `[CmdletBinding()]`, and populated in the body. Resolve default paths in the body.
- **Exit codes are `0` pass, `1` finding, `2` could not run.** Never `0` on an error path: a
  check that did not run and a check that passed are opposite facts.
- **Test behaviour, not source text.** The hooks are fed real events on stdin. A hook
  asserted only by reading its source is a hook nobody proved fires - and an early version
  of that suite passed its blocking assertions for entirely the wrong reason.

`templates/` is gone: its contents were reconciled against the live originals and moved into
`core/`, `stack/`, `vault/` and `automation/`. Nothing should point at it.
