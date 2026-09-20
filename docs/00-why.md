# Why any of this exists

An agent that writes code for you has three failure modes that no amount of prompting fixes,
because none of them is a reasoning failure. They are memory failures.

## It forgets

Every session starts from nothing. The tool gotcha you paid an hour for on Tuesday is gone
by Thursday, and you pay again. Not because the agent is careless - because nothing carried
the fact from one session to the next.

The obvious fix is "write it down", and the obvious fix fails. Written-down is not read: a
file the agent could open is only useful in the sessions where something reminds it to open
that file, which are exactly the sessions where you already remembered the gotcha yourself.
One practice audited its own history and found **eighteen separate rediscoveries, across
eight projects, of a rule that was written down the whole time.**

So the fix is not a file. It is a file plus a mechanism that puts it in front of every
session whether or not anyone remembers. That is `core/memory/` and the session-start hook.

## It repeats the same class of mistake in a new costume

Worse than forgetting a fact is relearning a *shape*. A project discovers that a clean
design-rule check does not mean a manufacturable board. Six months later, a different
project discovers that a green build does not mean a satisfied contract. Same lesson, no
transfer, full price paid twice - because nothing connected them.

`core/lessons/` is that connection: eleven families of error, each one collected from at least
two projects that learned it separately. And `core/corrections/` is how the eleventh gets
found - a log that counts, and a rule that promotes a lesson on its **second** occurrence.

The counting matters more than it sounds. The instinct is to build a pipeline: capture
observations, review them weekly, promote the good ones. That design has been built and it
fails in one specific place - **it dies at the review stage**, because nobody schedules
"read the backlog". One instance captured ninety-nine observations and applied one. A
counter with no stages survives where the pipeline does not.

## It claims more than it checked

This is the expensive one. An agent runs a test, the test passes, and the agent reports that
the feature works. But the test covered one path and the feature has four. Or the harness
died before the first assertion and reported success. Or the check ran against a file that a
scheduled job had already rewritten.

None of that is dishonesty. It is the gap between **the level you validated** and **the level
you claimed**, and it is the first and most repeated family in `core/lessons/`.

The structural answer is not "be more careful". It is gates that run whether or not anyone
remembers, an exit code that distinguishes *failed* from *could not run*, and the habit of
writing the whole sentence - *"it passed X, therefore Y"* - and checking whether X actually
implies Y.

## What this repository is, then

Not a prompt collection. Four mechanisms that address those three failures:

| Mechanism | Answers |
|---|---|
| `core/memory/` + the session-start hook | It forgets |
| `core/lessons/` + `core/corrections/` | It repeats the shape |
| `automation/verification/` + the exit-code contract | It claims more than it checked |
| `core/governance/` | All three, by stating the rules where they get read |

And one meta-mechanism, `stack/` versus `core/`, which exists because this repository itself
failed: it sat frozen for months, looking current, teaching a configuration its author had
already abandoned. Nothing in its layout could say *this part ages and that part does not*.
Read `core/README.md` for what that fixed.

## What it will not do

It will not make an agent good at your domain. It will not replace review. It will not stop
you from shipping something wrong - it will only make it harder to ship something wrong
while believing you checked.

That is a smaller promise than most tooling makes, and it is the one that survives contact
with a real week of work.

---

Next: [how to lay out a machine](10-machine-setup.md).
