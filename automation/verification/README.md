# Verification

Six different jobs that people collapse into one or two, and should not.

| Concern | Tool here | Question it answers |
|---|---|---|
| Secrets | `Invoke-Gitleaks.ps1` | is there a credential in what I am about to commit? |
| Configuration drift | `Assert-Baseline.ps1` | is my setup still the one I decided on? |
| Silent corruption | `Assert-NoControlBytes.ps1` | did a programmatic write leave a control byte in any text file? |
| Memory renames | `Assert-MemoryLinks.ps1` | does every `[[wikilink]]` in the memory store still resolve, or is it a declared exception that is still true? |
| Plan staleness | `Assert-PlanFreshness.ps1` | is any active `PLAN.md` older than the threshold, or based on a commit `HEAD` no longer descends from? |
| Vault health | `Invoke-VaultLint.ps1` | orphans, stubs, real dangling links - the mechanical half of the vault's Lint operation |

None covers another, and none covers the sanitization gate in `tools/`, which looks for
identity and location rather than credentials. Seven gates, seven enumerations - and each is
worth exactly what it enumerates. The last four were promoted from a private practice after a
second machine audited this repository and pointed out that the weekly routine asked the
reader to do by hand what the practice had already automated.

Each of the four has a suite in `tools/` that runs in CI and proves the gate **fails** on a
planted defect before proving it passes on a clean fixture. A gate seen only passing is not
evidence.

## The exit-code contract

Every gate here uses the same three outcomes:

| code | meaning |
|---|---|
| `0` | passed |
| `1` | failed - there is a finding, and it is printed |
| `2` | **could not run** - a missing binary, an unreadable file, no repository |

The third one is the entire point. *A check that did not run and a check that passed are
opposite facts,* and collapsing them into `0` is how a gate becomes decorative: it keeps
reporting success from a machine where it has not worked in months.

So: never `exit 0` on an error path. If the tool is missing, that is `2`. If the config
cannot be parsed, that is `2`. Say which surface you actually exercised.

This is not hypothetical for the secret scanner. gitleaks exits `1` for **both** a finding
and a failure to run - a config that will not load, a bad flag - so a wrapper that maps `1`
to "findings" reports a scanner that never ran as a secret found, the worse half of family
2. `Invoke-Gitleaks.ps1` passes `--exit-code 3`, so a real finding is `3` and everything
that is not `0` or `3` (including that bare `1`) is `2`, could not run. A second machine
measured this against the pinned version on 2026-09-20.

## The escapes that corrupt without a warning

A class worth a gate of its own, because every part of it is silent.

In a non-raw Python string, `\a` `\b` `\f` `\v` are **valid** escapes - they produce
BEL, backspace, form feed and vertical tab. No `SyntaxWarning`, no error, just a control
byte written into your file. Windows paths are where it bites: a path ending `\tools\analysis`
becomes a TAB, then `ools`, then a BEL, then `nalysis`. The path is now unfollowable and looks almost right.

Two things make it worse than an ordinary typo. The byte is invisible in most editors and
in `git diff`, so review does not catch it - `cat -A` or a byte scan does. And the natural
scope for the rule is too narrow: a rule that says "scan after appending to the log" misses
every other file. Scan **all** tracked text, not the files you were thinking about when you
wrote the rule.

Scan for `0x00`, `0x07`, `0x08`, `0x0B`, `0x0C`. Leave TAB, LF and CR alone - they are
legitimate, and accept what that costs you: `\t` corrupts a path exactly the same way,
and a TAB is indistinguishable from an intended one. **The gate is worth what it
enumerates.** The corruption this section describes was found by hand, in the sentence
above, *after* the byte gate reported the file clean - because the survivor was a TAB. Report `file:line`, not just the filename, because the byte's position is the
only thing that makes it findable. Repair the byte alone and verify the intended value
before writing it: fixing a corrupt path to a *different* wrong path is a real outcome.

One caution learned the hard way: order the checks before any trimming. A gate that strips
trailing dots before testing for an ellipsis will eat the ellipsis and then report a finding
against a target that never existed - a well-formed finding pointing at the wrong thing,
which is the worse half of family 2.

## Snapshot-first: the bytes written are the bytes validated

When a script *generates* something and then *validates* it, there is a gap where the two
can differ - the validator reads one version, the writer writes another, and both report
success. The fix is ordering:

1. build the new content **in memory or in a temporary file**;
2. validate *that* exact content;
3. only then write it to the real destination.

Never validate the destination after writing and call it proof. If the write is partial, or
a second process touched the file, or the encoding changed in transit, you have validated
something other than what now exists on disk.

The same principle applies to repair. **A repair that runs without changing the file's hash
did not repair anything** - it is the `2` case wearing a `0` costume. Hash before, hash
after, and compare.

## `Assert-Baseline.ps1` is a starting point, not a suite

It ships three example assertions. They are deliberately generic, and you should replace
them: the assertions worth having encode *your* decisions, and a borrowed assertion passes
without telling you anything.

Good candidates, once you have made the decisions:

- a permission rule you never want silently removed;
- a hook that must stay wired - **a hook present on disk is not a hook that fires**, and
  this is the assertion that catches the gap;
- a version you pinned on purpose, with the reason nearby;
- a file that must exist because something else asserts it exists.

Keep the suite small enough that you actually read the failures. A baseline with two hundred
assertions and one recurring red line trains you to ignore the red line.

## The binary is not here, and that is deliberate

`Invoke-Gitleaks.ps1` wraps a scanner this folder does not ship. The **install** - version,
URL, checksum step - is in `stack/manifest.md`, section 6, because a version number is
inventory and ages, while the wrapper and the exit-code contract are method and do not. Put
the install command here and this folder acquires a number that will be wrong within
months, in the one place that promises not to have any.

Pin the version in whatever calls the wrapper, and **refuse a different one** rather than
scanning anyway. A scanner you did not pin is a scanner whose findings you did not define,
and "green" from an unknown version is the most expensive kind of green.

## Running them

```powershell
.\automation\verification\Invoke-Gitleaks.ps1 -RepositoryPath .
.\automation\verification\Assert-Baseline.ps1
.\automation\verification\Assert-NoControlBytes.ps1 -Root C:\Path\To\your-repo
.\automation\verification\Assert-MemoryLinks.ps1 -MemoryRoot <MEMORY-STORE> -KnownDangling not-written-yet
.\automation\verification\Assert-PlanFreshness.ps1 -Root <PROJECTS-ROOT>
.\automation\verification\Invoke-VaultLint.ps1 -VaultRoot <VAULT-ROOT>
```

The three that take a root are **required** to be told it: a gate that guessed where your
store or your projects live would report a clean sweep of the wrong folder, and an empty
sweep must never read as a clean one (all of them exit `2` on an empty result, not `0`).

`Assert-MemoryLinks` takes an exception list on purpose. The memory conventions allow a link
to a memory not yet written, so a strict gate would be born red; what the gate catches is the
*new* dangling link. Every exception you declare must stay true: an entry that resolves again,
or that nobody cites any more, fails the run - an exception list that does not maintain itself
goes back to lying quietly.

`Invoke-VaultLint` prints one number it does not judge: comparative claims with no number in
the sentence. A claim with a number can be checked mechanically; one without can only be
read. While that count fits a manual reading, reading is cheaper than building a detector for
a class nobody has observed an instance of. Watch the number; build when it grows.

Wire the secret scan into a pre-commit hook so it runs whether or not anyone remembers, and
run the baseline from your periodic maintenance routine. A gate that fires only when
remembered is not a gate - see `../triggers.md` for how to make something fire on this host.
