# Cross-cutting lessons

**What this is:** rules that different projects learned *separately*, each one paying the
full price. An entry here means it has already cost real time in at least two projects.

**Scope:** method and verification discipline. Tool-specific gotchas belong in your memory
index, not here. Keeping them apart is what keeps either one readable.

**How to use it:** read before non-trivial work in any project. If a mistake of yours fits
none of these families, it is a candidate for a new one.

**How it grows.** A new lesson does **not** enter here the first time. It stays as a dated
line in your corrections log, and it earns a place here on the **second occurrence** - when
the *same* lesson shows up in a *different* project. Then, and only then: increment an
existing family, or open a new one naming both occurrences.

No intermediate stage, no proposals folder, no weekly review. Those stages existed once, and
the pipeline died in the second one, with 99 observations captured and 1 applied. The rule is
the whole mechanism: if it never happens again, you were right not to make it a rule.

> **These ten are borrowed, not yours.** They come from one practice - engineering,
> hardware, research - and they are here as seeds, so you start with a checklist instead of
> a blank file. The occurrences behind them have been removed: they named projects, people
> and dates. Your scars will be different ones, and the rule above is how you record them.

---

## 1. Name the level you validated, not the level you claim

The most expensive and most repeated failure of all. An artifact approved at one level gets
declared ready at a level above it, and the gate that existed never covered the claim that
was actually made.

**Apply:** when you declare something done, write the whole sentence - *"it passed X,
therefore Y"* - and check whether X really implies Y. If it does not, what is missing is a
second gate, not more confidence in the first.

**Shapes it takes:** a geometrically valid mesh is not a printable one - a clean design-rule
check is not a closed metrology envelope - a green build with unit tests is not a system
invariant - a successful package install is not a trustworthy runtime - a command that
executes is not a coherent environment - a catalogue that loaded is not a skill that ran -
a documented scope is not an inventory of the practice - text that came back is not the
document that was asked for (a portal's HTML page with a 200 where a PDF was expected; a
404 body in XML that only a file-type check exposed; a 280-byte "Redirect" stub from a
short link; hundreds of garbage characters shaped like content from an encrypted OCR
layer, twice in two projects of a second practice). The check "did text come back" passes
in all of them. The question is "did *the document* come back", and the cheap answer is a
file-type check on what arrived, or a known phrase from the original searched for in what
returned - the OCR variant is the worst, because garbage passes the file-type check too.

**Sub-pattern: a gate is worth exactly what it enumerates, not the domain it claims to
cover.** A protection list that named six components and never included a seventh, which
shipped unprotected while every gate stayed green. A silkscreen guard that swept only board
drawings and never footprint references, leaving automatic designators sitting on a
neighbour's pad. A test runner reporting PASS over two of five tests, because the three
newest ones only had ad-hoc commands in a build document. In none of them did the gate
"break": it did exactly what it enumerated. **Absence of FAIL is not absence of risk when
the risky item never entered the list.**

**It reappears wherever the consumer differs from the checker.** A schema validator passing
does not prove correct rendering: a glyph missing from the font became an empty box, and
only inspecting the rendered image revealed it. Text under a component body is invisible on
an assembled board, and a geometry checker will never say so - only the 3D render will.
Only the final consumer sees the final consumer's class of defect.

**A new path existing is not an equivalent installation.** Documents were migrated to a new
release of a numerical suite after confirming the new version's directory was there; the
migration had silently dropped an optional toolbox, and every routine that depended on it
broke. Same shape as *install succeeded is not runtime works*, on a new surface. After
changing versions of a suite, query its capabilities, not its directory.

---

## 2. A check that did not run and a check that failed are opposite facts

When the verification tool breaks for infrastructure reasons, the report comes out shaped
like the defect it was looking for. You then debug the right artifact for the wrong reason -
or worse, record "verified".

**Apply:** three states, never two - *passed* / *failed* / *could not verify*. Say which
surface was actually exercised, and never let a broken harness silently demote a required
check into a skipped one.

**The cheap corollary that catches most cases:** every comparison asserts that its operands
exist *before* comparing - a non-empty guard, an expected count greater than zero, a
non-empty hash. Empty equals empty is the most convincing PASS there is, and blocking it
costs nothing. The same goes for fixture setup: if the step that builds the scenario can
fail, it needs an explicit abort, or the negative test "passes" by testing nothing.

**Shapes it takes:** a tool that could not read the artifact found no defects - a test that
compiles is not an assertion that ran - a comparison whose two operands both came back empty
reporting IDENTICAL - a build wrapper reporting exit code 0 when the wrong working directory
meant the build never ran - a blocked renderer reported as visual verification - an
application-control policy blocking an executable reported as a broken server - killing a
long-running solver before it wrote its output and reading the interruption as "this input
cannot be solved", when the same binary, left to finish, solved it - a `--check` flag that
skips the build and validates the artifact already sitting at the destination, reporting
"all passed" over stale output.

**Zero from a broken channel has the same shape as measured zero.** An extractor fed through
standard input returned "0 nodes" with no fatal error, because each worker process died
re-importing from a path that did not exist; the same script from a real file returned two
hundred. With every chunk failing on quota, the same extractor still tried to *write* the
pruned result. Distinguish at the origin, or the distinction does not exist afterwards. A
related trap: adding a pipe filter to a command makes the exit code the filter's - read the
output, not the code.

**A single-mode reporter misinforms when the cause is something else.** A backup script
printed "push FAILED - check the network" for *any* push failure. Twice in one day the real
cause was history divergence, and twice the first diagnosis was the network. That is not
*passed* and not *could not verify*: it is **failed for the wrong reason, because the
reporter only anticipates one reason**. A reporter that enumerates one failure mode
implicitly declares the others do not exist - the same root as the sub-pattern in family 1.
Every error path should classify the cause from the real output, or say "cause not
classified" and print it.

**The exit contract of a gate.** Three states apply to what a gate *returns*, not only to
what it reports. A gate whose break path produces the same exit code as its finding has two
states, not three - and what it loses is exactly the distinction between *I found a problem*
and *I broke*. **The human reader is not the measure:** when a path test throws, the
exception is visible in the output and a person tells the difference; a caller that consumes
only the code - a chained suite, CI, a hook - tells nothing apart.

*Apply:* reserve a code for "could not verify" (`2` is a workable convention) and make sure
**no break path can reach the finding code** - malformed input becomes a formatted finding,
never an exception. And never assert only the exit code: assert some evidence that **only a
successful run produces** - the named target, the `file:line`, the word FAIL. One extra
assertion of that kind caught two cases where the exit code was "right" and the gate had not
run.

A related failure: a gate can be green because no case exercises the path. A link checker
passed seventeen assertions while two legitimate syntaxes - an aliased target and a
section-anchored one - made it throw or emit a well-formed finding against a target that
existed. None of the seventeen used either syntax. **Missing coverage does not show up as
FAIL; it shows up as green.**

**Confirmed in a second practice.** Nine occurrences in two projects of the same shape - an
empty return read as "does not exist" - seven of them on a single day, by a practice that
had not read this file. The rule of three states was rediscovered at seven a day. That is
what this family predicts: the mistake is cheap to make and expensive to notice, and whoever
has not named it repeats it until they do.

**A new gate is born wrapped.** In one repository an exception reached the finding code
three times, across two gates: a path test that threw in the link checker, then an invalid
name and an unreadable file in the index checker. Each was found and fixed on its own, which
is the signature of a rule that exists as prose and not as a habit. The habit that ends it is small: a new gate's body
goes in a try/catch that exits `2` **from the first line you write**, not after the first
time it bites. And give the regression fixture the defect more than once - a scanner that
reported every finding on line 1 passed a suite where each fixture contained exactly one
planted defect.

**Green because of the language your machine speaks.** A test proving "no raw exception
leaked" asserted on the word `Exception`. That word appears in the English runtime wrapper;
on the author's machine the wrapper is translated, so the assertion matched nothing and the
test went green for the wrong reason - then failed in CI, in English, where the wrapper
matched and the "impossible" case was real. This is family 8 living inside a test rather
than inside data. Test evidence has to be what is identical in every locale: the method name
in the wrapper, a stable error identifier, the named file - never a runtime's prose. The
gate itself was changed to print the **inner** exception, without the translated wrapper.

---

## 3. Internal consistency does not prove a correct binding

If the target and the reference were built from the same assumption, both are wrong together
and every check passes.

**Apply:** at least one check has to touch an independent source - a real export, a
datasheet, a measurement, a materialised datum. And when a format stores the same content
twice (a live representation plus a pre-rendered fallback), establish *which of the two* the
verifier read before accepting the render as proof.

**Shapes it takes:** a 3D case mirrored on one axis passed 47 of 47 checks because the
reference envelopes inherited the same wrong frame - a photograph converted into an offset
with no physical datum on either side - geometry and polarity compared as one aggregate
label - a design constraint treated as external when it was a sentence the agent itself had
written in an earlier session, blocking a whole round of optimisation until someone asked
where the limit came from. A document you authored is not an external source.

**Two clocks that agree and answer the wrong question.** In a session resumed two weeks
later, the date in the prompt and the shell's own clock agreed, and were used to "correct"
dates the agent itself had written earlier. The old dates were right: the proof was the
build timestamp compiled into the binary. Both signals agreed with each other and neither
answered the question asked - the resumed session's date is the date of the *resume*, and
the clock gives *today*, not *when this was written*. Before correcting a date you wrote
yourself, find a timestamp belonging to the artifact.

**A vendor's own benchmark is internal consistency.** A package README scored its latest
release best, which made the upgrade look obvious; that release had an open regression that
rejected a whole class of input. It surfaced only by running both versions over a real
corpus and checking against an independent extractor, which reversed the ranking. A number
published by whoever wrote the code is the same assumption measuring itself.

**The worst case is one source, and nothing independent at all.** Every shape above has two
sources sharing an assumption. This one has a single source - your own extractor - and it is
more dangerous, because *repetition cannot catch it*: repeating the measurement calls the
same extractor and returns the same number.

A routine audit measured the body length of two hundred pages to find which were thin. The
extractor isolated the body with one regular expression spanning the whole document; because
the dot matched newlines, the non-greedy match closed at the first horizontal rule **in the
body** rather than at the end of the frontmatter. Every page silently lost its most
substantial section before being counted. The report that came out was not noise - it was
coherent: a ranking, a correlation ("the most-cited pages are the thinnest"), and a
recommended remedy. The real numbers were the exact inverse, the recommended remedy was to
rewrite seven pages that did not need it, and nothing in the output looked wrong.

What broke the spell was opening the first page slated for rewriting. It had tables and four
sections where the report promised ninety-seven words.

**The counter-move is one item.** Before acting on an extracted metric, open **one** item of
the corpus and check the number against it by hand. One item is enough, it costs seconds,
and it is the only step in the chain that does not go through the thing that might be
broken. Two design decisions follow, and both are cheap: cut structured headers **line by
line** rather than with a pattern that can span the document, and never let a single
expression be the only thing standing between raw text and a number you will act on.

A corollary with the same root: **before running an integrity check over someone else's
corpus, read that corpus's own convention for the relation you are about to measure.** A
link checker counted only inline wiki-links and reported a thousand-word source page, cited
by twelve others, as an orphan - that corpus declares source-to-concept links in a
frontmatter field, with a bare name. The scanner's definition of the relation was not the
corpus's definition, and the finding it produced was confident and wrong.

---

## 4. Durability has to be periodic and unconditional

When the cost is already paid before the single save point, any interruption zeroes the paid
work. And an instruction conditioned on the executor noticing its own budget does not
protect it: the executor cannot see the shared ceiling, and dies without warning with the
whole bill paid.

**Apply:** in fan-out, long work or numerical search, save per phase and without condition.
Estimate cost from the **size distribution** of the items, not their count. Price the cheap
route *before* spending on the expensive one - the execution route is the first decision,
not plan B.

**The enforcement trap.** A rule anchored to one specific tool goes inert precisely in the
sessions that work in a different style - which are the ones that generate new observations.
A self-observation mechanism failed for exactly this reason: its mandatory checkpoint
depended on a tool the session might never call, so the sessions worth observing were the
ones it never saw.

---

## 5. One operational source; an example gets read as a definition

Warning that a number is stale does not neutralise it, as long as it is still presented as
an executable step. And an example that covers one case is read as the definition of the
convention - every uncovered case becomes an independent invention, and inventions made in
parallel do not converge.

**Apply:** a physical or executable deliverable has one source, not a source plus an
addendum. An example must cover the boundary cases, or say explicitly that it does not.

**The example read as the rule.** A calibration window was nearly hard-coded from a literal
in a protocol document. The document was quoting one *instance* of a ratiometric rule, under
one specific supply voltage and temperature - not the rule itself. The absolute constant
would have failed, for free, a later test that varies those conditions on purpose.

**The note that was not enough.** A bootstrap script pinned a sparse-checkout path matching
an upstream layout. When upstream moved its content, every update began downloading an empty
cache. The first attempt diagnosed it as *suspected* and wrote the suspicion into a memory
note without touching the script; months later the same failure repeated, was confirmed
against the upstream tree, and only then was the script fixed. The warning in memory did not
help, because the wrong executable step was still the script.

---

## 6. Verification must not damage the user's live state

A QA step that drives a shared user application - a word processor, a spreadsheet, a browser
profile - is side-effectful, not read-only.

**Apply:** use a headless engine or an isolated profile; never mutate global state; never
kill a process that might be holding the user's unsaved work. A persistent permission
authorises **one immutable executable**, not a general-purpose interpreter.

**Shapes it takes:** office automation hijacking the user's live session - a suite labelled
"unit" writing into the user's real paths - a rasteriser running unisolated.

**The destructive-conversion case.** Converting a real directory into a link destroys its
contents. Any tool that does that has to copy first, never overwrite what is already at the
destination, and abort that item if the copy fails. And removing a link with a recursive
delete can delete the *target*: remove the link itself, not the tree behind it.

---

## 7. A handoff carries provenance and authority, not just content

A document written at the end of a long collaboration inherits the conversation's
compression, and whoever reads it did not watch the reasoning being earned. Options without
consequence produce a vote; options with consequence produce a decision.

**Apply:** mark each artifact as authoritative or superseded; label the provenance of each
claim (user-supplied / retrieved / inferred); and declare the authority boundary - what the
document decides, what it merely proposes, and for whom. An architectural change is done
only when the narrative, the design, the resources and the handoff all express the same
version.

**The earlier decision is usually in the commit message, not in the code.** A proposal to
reclassify a setting as unsafe was approved. Running the file's history first would have
surfaced an earlier commit that had classified it *safe*, with an approval of its own, for a
reason the proposer did not have - the dangerous case was already neutralised elsewhere. The
reversal would have undone an informed decision, with the decider's own approval, because
nobody read the provenance. **A user's approval does not supply provenance:** they approve
the proposal you presented, and if you did not know they had already decided the opposite,
they were not reminded either. Before changing a file's classification or policy, read its
history - the messages, not just the dates.

**A point-in-time reading of a file that an automation rewrites is not state.** A claim that
a baseline "lost two keys in yesterday's merge" turned out to describe a value that
alternates every run of a scheduled job, which had already restored them. To describe a
trend, the file's history is the source; today's contents are not.

---

## 8. Two read paths over the same file disagree about encoding

When two APIs read the same file under different encoding assumptions, the stricter one
reports as **invalid** what is valid - and the error comes out shaped like the defect you
were hunting, not shaped like "I could not read this".

**Apply:** when reading a file another tool also reads, use the API that consumes the byte
order mark, or strip it explicitly. Never let your reader be stricter than the downstream
consumer, and when a parser calls a file invalid, check the **first byte** before believing
it.

**Shapes it takes:** a validator failing on one platform through an implicit-encoding read -
a byte order mark preserved by a string conversion, breaking a JSON parse in a settings file
that the same repository's own gate approved - a registry file with a byte order mark
breaking the JSON parser of the very CLI that maintains it, so the CLI reported "nothing
installed" for five entries the file listed correctly, while another tool read the same file
without complaint.

**Write-side variant.** The same disagreement runs in reverse. A script that prints text
read from a UTF-8 file dies on the first character outside the console's narrower default
encoding, and the error arrives *before* the gate the script was supposed to run - the gate
did not fail, it did not run, which is family 2. Any script that might print file text
should reconfigure its output encoding first; better still, write the text to a file and
print only counts and plain-ASCII paths.

**Line-ending variant, and here the permissive reader is the one that lies.** A text-mode
search tool discards carriage returns, so searching for a literal CR answers "LF" for a file
that is entirely CRLF. Twice this turned a scripted edit into a partial one - in the first
case fourteen of twenty-seven replacements failed, all the ones containing a newline. Before
editing a file by script, census the terminators by counting bytes, and adapt per file: a
real repository mixes both. And a line-ending check must read in binary or with newline
translation disabled, or universal mode makes a uniformly CRLF file look mixed.

---

## 9. A string that crosses a layer is silently rewritten

A literal passes through an interpreter before it reaches its destination, and the
interpreter rewrites it. The destination receives something you never wrote, and complains
in terms of **its own world** - "the repository does not exist", "the anchor did not match" -
never in terms of "what arrived here is not what you sent".

Worse: the warning, when there is one, points the wrong way. In a non-raw literal, the
*invalid* escape sequences warn and stay harmless, while the *valid* ones - `\a`, `\b`,
`\f`, `\n`, `\r`, `\t`, `\v`, `\0`, `\x` - do not warn, and corrupt. A warning present is a
sign that other escapes in the same string went through silently.

**Apply:** the default is a file, not inline. Scripts, commit messages, and any text
carrying apostrophes, escapes or Windows paths get written to a file and executed by
reference. Inline quoting, heredocs and command substitution are not the normal path with a
fallback - they are the wrong transport.

**The three that keep recurring:**

| transport | trap | fix |
|---|---|---|
| Unix-style shell to git | an argument with both a slash and a colon gets rewritten as a path | disable the shell's path conversion for that command |
| shell tool to an interpreter | valid escape sequences in a non-raw literal are **valid**, do not warn, and corrupt | raw literals, or text in a file that the script only reads |
| passing an array to a script by file reference | a comma-separated list arrives as one element, and the script exits 0 having done nothing | invoke through the call operator with a real array, or split inside the script |

**Doubling the escape is what the transport undoes.** A corrupted control byte in a shared
log was repaired by a byte replacement written with doubled backslashes. It ran three times
without changing a single byte - identical hash - because the doubling also collapsed in
transport, and the control byte was replaced by itself. **A repair that runs without
changing the hash did not repair** (family 2). What worked was building the byte from its
numeric value, with no backslash in the source at all. Measure your transport before
trusting an escape convention: the same doubling can survive one tool and collapse in
another.

**Related to family 8, and distinct from it:** there, two *readers* disagree about the same
bytes, and the fix is choosing the API that consumes the byte order mark. Here, a *writer*
has its bytes rewritten in transit, and the fix is escaping at the source or changing
transport.

**When the corruption reaches a shared artifact.** A form feed, written by one session into
an append-only log through a valid-but-unwanted escape, was found three days later by
another. Two things the earlier occurrences did not have: the damage did not stay in the
execution, it **persisted in the counter this discipline itself uses** to decide promotions;
and the session that wrote it was not the session that found it, so nobody had the case in
mind. After any programmatic write to an append-only file, sweep for the control bytes
before finishing - and repair only the byte, never rewrite another session's entry.

---

## 10. A handoff describes the machine it came from, not the one it runs on

A handoff written on machine A carries, without saying so, A's shell, the tools on A's PATH,
A's user profile and the state of A's tree. Whoever runs it on B reads literal instructions,
and B is not A. The error takes three forms, all of them already paid for: the **noisy** one
(a shell that does not exist; a pull refused because the tree is not clean), the **silent**
one (a sync that copies A's state over B's, erasing configuration only B had), and the
**invisible** one (B had five days of uncommitted work A never saw, and the handoff said
"update" as if B were empty).

Family 7 covers *who* wrote it and *with what authority*; this one covers *where* the text
will run. A handoff can be impeccable in provenance and still describe the wrong machine.

**Apply:** before executing any cross-machine handoff, measure the destination - repository
status and ahead/behind for **every** repository named, presence of every named tool, the
profile path - and only then run. Whoever writes the handoff declares the origin machine and
lists what it assumes of the destination (shell, clean tree, tools) instead of embedding
those assumptions in the commands.

**A number written in a handoff without saying how it was measured is a hypothesis, not a
fact.** One claimed an ignore-file would prune 31 nodes from a graph and that the run
therefore needed a force flag; measured first, those paths had always produced zero nodes.
Another said six files lacked coverage; the measurement found seven, and the seventh was the
handoff itself, which *should* be included - writing the rule from the handoff's pattern
would have excluded the wrong file. A third said no backup of a set of computed results
existed and asked for hours of regeneration; the destination machine had them all, ignored
by version control, and regenerating would have overwritten the stochastic optimum behind
already-published numbers. Measuring cost a twenty-line script each time, and each time the
written number was wrong.

**Union-merge of content also loses per-machine state.** Swapping copy-over for union solves
*erasing*, not *integrating*. A merge brought one machine's settings into a shared baseline
and dropped two keys that only the other machine had. The rule that closes it: a shared
baseline is a union, per-machine difference goes to a sidecar named after the profile, and
the exporter sorts its keys before writing - without a stable order, every periodic run
becomes a churn commit that hides the real change among reordered lines.

---

## 11. The summarising layer is not the source

Between you and a document there is, more and more often, a layer that **rewrites**: the
summary of a search, the fetcher that returns "what the page says", the extractor that
condenses, the compaction summary that stands in for a conversation, the report you
generated yourself over a corpus. It returns coherent prose in the right register with the
original's structure - and what it returns is a **claim about** the source, not the source.
When the claim is wrong it looks exactly like when it is right.

This is not family 3 (there, target and reference share an assumption; here there is one
source and a layer in between) and not family 9 (there the rewrite is mechanical - escaping,
encoding, path conversion; here it is a rewrite of **meaning**, and the string can be intact
while the fact has changed). What makes it expensive is what makes it useful: the layer
exists so that you do not open the original, and the saving is real until the day the
number is wrong.

**Apply:** a number, a name, a title or an attribution that came through a summarising layer
does not enter an artifact until **one** of them has been checked against the original. If
the original is on disk, opening it costs less than the summary did. When the layer is your
own - a report, a lint, an extractor - family 3's rule applies: open one item of the corpus
and check the number against it before acting. And when you cite, say **which layer** the
fact came through ("according to the search summary", "the PDF says") - family 7's
provenance, applied to derived text.

**Shapes it takes:** a search summary that swapped +1.2 °C for +2.1 °C and attached the
probability to the wrong event - a page fetcher that invented the title, journal and subject
of an article whose PDF sat correct on disk - a lint report over a knowledge base that said
the most-cited pages were the thinnest when the truth was the reverse, because the extractor
behind it was wrong and every number in the report came from it. Four occurrences across
four projects in two practices. The family has a name of its own, rather than being folded
into family 3, because it arrived in three different shapes - external search summary,
external page extractor, self-authored report - and a third shape is what opens a family
here.
