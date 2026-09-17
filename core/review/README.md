# One surface per purpose

Review tools multiply fast, and the failure mode is not having too few - it is having four
that overlap, so each one gets run sometimes, none gets run reliably, and nobody can say
which check actually covered a given change.

Pick one surface per purpose, write down which is which, and leave the rest uninstalled.

| Purpose | When it runs | What it is for |
|---|---|---|
| **Plan review** | before any code exists | Argue with the approach while changing it is still free. Ideally a *different model* than the one that wrote the plan - two instances of the same model agree with each other far too easily |
| **Branch / PR review** | on a finished diff | Does this follow the repository's documented standards, and does it do what the issue asked? Two separate questions; answer them separately |
| **Independent heavyweight review** | before merge, on risky changes | A reviewer with no memory of writing the code. Expensive on purpose - reserve it for auth, money, schema, concurrency and migrations |
| **Security review** | when the change touches auth, crypto, input handling or secrets | A different question from correctness, and one that correctness review reliably misses |

## Scale depth to risk

- Mechanical change - skip review, commit.
- One module - medium depth.
- Multi-file, or anything touching auth, money, schema, concurrency or security - full
  depth.

Fix what comes back, re-review **once**, then commit. A third round usually means the
disagreement is about design, not about the diff, and that conversation belongs upstream
of the review.

## CI is the authoritative gate

Local review complements CI; it never replaces it. The reason is not that local review is
worse - often it is better - but that it is **conditional**: it runs when someone
remembers, on the machine they happen to be using, against the state they happen to have
checked out. A gate that only fires when remembered is not a gate.

So: anything you actually rely on goes into CI. Local review is for the judgement that
cannot be automated - is this the right shape, is this the right abstraction, is this
worth doing at all - and those are exactly the questions a pipeline cannot ask.

A corollary worth stating, because it is the one people get wrong: **a green local run and
a green CI run are different facts.** When they disagree, CI is right about what the
repository contains, and your machine is right about nothing except your machine.
