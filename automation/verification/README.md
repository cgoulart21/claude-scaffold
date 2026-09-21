# Verification

Seven different jobs that people collapse into one or two, and should not.

| Concern | Tool here | Question it answers |
|---|---|---|
| Secrets | `Invoke-Gitleaks.ps1` | is there a credential in what I am about to commit? |
| Configuration drift | `Assert-Baseline.ps1` | is my setup still the one I decided on? |
| Silent corruption | `Assert-NoControlBytes.ps1` | did a programmatic write leave a control byte in any text file? |
| Memory renames | `Assert-MemoryLinks.ps1` | does every `[[wikilink]]` in the memory store still resolve, or is it a declared exception that is still true? |
| Memory index drift | `Assert-MemoryIndex.ps1` | is every memory's index line still its `description`, verbatim, within the cap and safe to parse as YAML? |
| Plan staleness | `Assert-PlanFreshness.ps1` | is any active `PLAN.md` older than the threshold, or based on a commit `HEAD` no longer descends from? |
| Vault health | `Invoke-VaultLint.ps1` | orphans, stubs, real dangling links - the mechanical half of the vault's Lint operation |
| Errata propagation | `Assert-ErrataPropagation.ps1` | does a value marked superseded in one place still appear, unmarked, somewhere else? |

None covers another, and none covers the sanitization gate in `tools/`, which looks for
identity and location rather than credentials. Nine gates, nine enumerations - and each is
worth exactly what it enumerates. Four were promoted from a private practice after a second
machine audited this repository and pointed out that the weekly routine asked the reader to
do by hand what the practice had already automated; the memory-index gate followed when that
practice measured its own index and found the hooks had drifted from the descriptions they
were meant to repeat; the errata gate followed it, once the governance rule it enforces had
been written down here without the mechanism that makes it hold.

Each of the six has a suite in `tools/` that runs in CI and proves the gate **fails** on a
planted defect before proving it passes on a clean fixture. A gate seen only passing is not
evidence.

## The errata gate expects a convention, and will tell you when it has none

`Assert-ErrataPropagation.ps1` is the only gate here whose default answer on a fresh
repository is `2`, and that is correct rather than broken: with no errata marker carrying a
numeric value there is nothing to propagate, so there is nothing measured, and saying `0`
would be a clean bill of health issued without an examination. It becomes useful the moment
a corpus starts marking superseded values - and it needs that corpus's own convention,
because `-MarkerPattern` defaults to English words and a marker written in another language
is invisible to it.

That is not a footnote. Pointed at a corpus whose markers read *refutada* rather than
*refuted*, the gate reported eight confident findings that were entirely an artifact of the
mismatch; the same corpus, swept with its own pattern, is clean. Read the corpus's
convention before measuring it, which is the corollary in family 3 of the lessons file, and
is worth re-reading every time a scanner produces a number about someone else's text.

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

Scan for `0x00`, `0x07`, `0x08`, `0x0B`, `0x0C`, and for a `0x0D` that is not followed by
`0x0A`: CR is legitimate only as half of CRLF, and a lone one is the residue of an insertion
into a CRLF file followed by a normalisation to LF. Leave TAB and LF alone - they are
legitimate, and accept what that costs you: `\t` corrupts a path exactly the same way,
and a TAB is indistinguishable from an intended one. **The gate is worth what it
enumerates.** The corruption this section describes was found by hand, in the sentence
above, *after* the byte gate reported the file clean - because the survivor was a TAB. Report `file:line`, not just the filename, because the byte's position is the
only thing that makes it findable. Repair the byte alone and verify the intended value
before writing it: fixing a corrupt path to a *different* wrong path is a real outcome.

The lone CR earned its place the same way. A stray `0x0D` at the start of a line in a memory
index made that line invisible to every parser anchored on `^` and to `cat` itself; the byte
gate reported the file clean, because CR sat on its leave-alone list, and the gate over the
index caught it instead. Before the rule changed, both trees it runs on were measured free of
lone CRs, so the new finding was not born red - and a file that legitimately ends its lines
with a bare CR goes on the exception list, with the reason next to it.

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

### When the snapshot is a re-serialisation, capture it in canonical form

A snapshot that strips keys, or re-serialises the source for any other reason, no longer
promises byte equality with the source - it promises **semantic** equality, while the
invariant above still holds: the bytes written are the bytes validated. Re-serialising
opens a second gap. Tools rewrite their own config files with a different key order on
every machine, so a snapshot that preserves the source order flips between machines while
nothing changed. The fix is a canonical form, on the capture side only: keys of **every**
object sorted by ordinal comparison (not the machine's culture), at every level including
the top; **arrays never reordered**, because their order is meaning (permission rules,
hook sequences); scalars untouched. Same content, same bytes, whichever machine captured
it. The restore direction stays out of it: reformatting the user's live file is not the
restore's job.

Canonicalising changes what the post-write check can promise, and the check has to change
with it. Compact-JSON equality is order-sensitive and would now fail by design. The
replacement compares the **set** of keys in every object, the **length and order** of
every array, and the value of every leaf, naming the first path that differs - and it
must not reuse the canonicaliser to do so, because a comparer that shares code with the
transformation it verifies agrees with it by construction (lesson 3). Prove the check
with sabotage: mutate a copy of the installer so it drops a nested key, reorders an
array, unrolls a one-element array, or lets the canonical form leak into the path that
was promised to stay unchanged, and assert that the check dies naming the path. Two
platform traps make those mutations realistic rather than theoretical: a PowerShell
function returning an array unrolls it unless the return is wrapped in the comma
operator, so a one-element array becomes the element and an empty one becomes `$null`;
and enumerating the property names of an empty object yields `$null`, which `@()` turns
into a one-element array with no name. A check that survives its own sabotage is not
checking.

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
.\automation\verification\Assert-MemoryIndex.ps1 -MemoryRoot <MEMORY-STORE>
.\automation\verification\Assert-PlanFreshness.ps1 -Root <PROJECTS-ROOT>
.\automation\verification\Invoke-VaultLint.ps1 -VaultRoot <VAULT-ROOT>
```

The four that take a root are **required** to be told it: a gate that guessed where your
store or your projects live would report a clean sweep of the wrong folder, and an empty
sweep must never read as a clean one (all of them exit `2` on an empty result, not `0`).

`Assert-MemoryLinks` takes an exception list on purpose. The memory conventions allow a link
to a memory not yet written, so a strict gate would be born red; what the gate catches is the
*new* dangling link. Every exception you declare must stay true: an entry that resolves again,
or that nobody cites any more, fails the run - an exception list that does not maintain itself
goes back to lying quietly.

`Assert-MemoryIndex` checks the contract written in `core/memory/README.md`: one index line
per memory, the hook after the link equal to the file's `description` character for
character, the description within `-MaxLength` (200 by default) and a plain YAML scalar. It
judges neither the wording nor the grouping, and it never writes a line: the index stays
authored. What it catches is the second relevance text - the hook edited in the index while
the description stayed behind, or the memory written in a hurry with no line at all.

`Invoke-VaultLint` prints one number it does not judge: comparative claims with no number in
the sentence. A claim with a number can be checked mechanically; one without can only be
read. While that count fits a manual reading, reading is cheaper than building a detector for
a class nobody has observed an instance of. Watch the number; build when it grows.

Wire the secret scan into a pre-commit hook so it runs whether or not anyone remembers, and
run the baseline from your periodic maintenance routine. A gate that fires only when
remembered is not a gate - see `../triggers.md` for how to make something fire on this host.
