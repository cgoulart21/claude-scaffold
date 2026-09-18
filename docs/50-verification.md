# Verification

The discipline that separates *this works* from *I have not yet seen it fail*.

## Three states, never two

The most expensive habit in agent-assisted work is treating verification as a boolean.

```
passed          the check ran and found nothing
failed          the check ran and found something
could not run   the check did not happen
```

The third state is the one that gets collapsed into the first, and the collapse is almost
always silent. A test harness dies before its first assertion and the runner reports zero
failures. A build wrapper starts in the wrong directory, the build never runs, and the exit
code is zero. A comparison whose two inputs both came back empty reports that they match.

**Empty equals empty is the most convincing pass there is.** Every comparison should assert
its operands exist before comparing them, and every fixture step that can fail needs an
explicit abort - otherwise the negative test passes by testing nothing.

Every gate in this repository uses `0` / `1` / `2` for exactly this reason, and `2` never
means success.

## Name the level you validated

Write the whole sentence: *"it passed X, therefore Y."* Then check whether X actually
implies Y.

- A clean design-rule check is not a manufacturable board.
- A green build with unit tests is not a satisfied system invariant.
- A successful install is not a working runtime.
- A command that executed is not a coherent environment.
- A loaded catalogue is not a skill that ran.

When X does not imply Y, what is missing is a second gate - not more confidence in the
first.

And the sub-pattern that catches people who have already learned the main one: **a gate is
worth exactly what it enumerates, not the domain it claims to cover.** A protection list that
names six components and omits a seventh does not "break" when the seventh ships
unprotected. It does exactly what it enumerates. Absence of FAIL is not absence of risk when
the risky item never entered the list.

## Touch something independent

If your artifact and your reference were built from the same assumption, they are wrong
together and every check passes.

At least one check has to touch a source that does not share the assumption: a real export,
a datasheet, a measurement, a timestamp belonging to the artifact itself. Two signals that
agree with each other prove agreement, not correctness - and a vendor's own benchmark is the
same assumption measuring itself.

## Do not damage the live state

A verification step that drives an application the person is using is not read-only, whatever
the intent. Use a headless engine or an isolated profile; never mutate global state; never
kill a process that might hold unsaved work.

The sharp edge in this area: converting a real directory into a link **destroys its
contents**, and removing a link with a recursive delete can destroy the **target**. Anything
that does either must copy first and remove the link itself rather than the tree behind it.

## Where the gates live

| Gate | Catches | Runs |
|---|---|---|
| Your test suite | Behaviour | Locally and in CI |
| A secret scanner | Credentials | Pre-commit hook |
| A baseline assertion script | Configuration drift | Periodic routine |
| CI | All of the above, unconditionally | Every push |

**CI is the authoritative one**, and not because it is smarter. Local review is often
better. It is *conditional*: it runs when someone remembers, on the machine they happen to
be using, against the state they happen to have checked out. A gate that fires only when
remembered is not a gate.

So anything you rely on goes into CI. Local review is for the judgement a pipeline cannot
have - is this the right shape, is this worth doing at all.

One corollary people get wrong: **a green local run and a green CI run are different facts.**
When they disagree, CI is right about what the repository contains and your machine is right
about nothing except your machine.

## Testing a detector

If the thing you are testing is itself a check, the test needs both directions.

A suite that only asserts *the detector fires on bad input* will pass when the detector is
broken in the specific way that makes it fire on **everything**. That is not hypothetical:
an early version of this repository's own hook suite passed all its blocking assertions
because a byte order mark in the fixtures made every event unparseable, so every command
came back blocked. The blocking assertions were green. The detector was useless.

Assert the positive and the negative. And when a repair does not change the file's hash,
**the repair did not happen** - that is the `could not run` state wearing a `passed` costume.

---

Previous: [skills and plugins](40-skills-and-plugins.md) · Next: [maintenance](60-maintenance.md).
