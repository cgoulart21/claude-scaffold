# Governance: the file that is read every time

The global instruction file is the only text guaranteed to reach every session. That makes
it the most valuable real estate you have, and the easiest to waste.

## Why eight and not thirty-eight

The practice this came from ran an audit on its own instruction file and cut **thirty-eight
rules to eight**. The rules that survived became *more* effective, not less.

That is not a paradox once you see the mechanism. Instructions do not fail by being absent;
they fail by being **skimmed**. A file long enough to skim is a file where every rule is
optional, because the reader has already learned that most of it does not apply right now.
Cutting the thirty that were situational made the eight that were universal visible.

The rules that were cut were not wrong. They were *specific* - things that belong in a
project's own instruction file, where they are read by the sessions they apply to and
nowhere else.

**The test for whether a rule belongs in the global file:** would you want it applied to
every task you do, in every project, forever? If not, it belongs in the project.

## What the eight cover

Read `core/governance/CLAUDE.md.template` for the text. The shape:

| Section | The rule underneath it |
|---|---|
| **Verification** | At least one check touches an independent source; say which surface you tested |
| **Cross-project knowledge** | Where memory and lessons live, and that they are read before non-trivial work |
| **Handoff** | `PLAN.md`, its checkpoint fields, and when a plan is stale |
| **Commits and review** | Depth scaled to risk; named approval for commits, pushes and disclosure |
| **Maintenance** | On a dated reminder, run the routine and stamp the marker |
| **Workflows and subagents** | Your own default, stated - because an unstated default gets applied inconsistently |
| **Corrections** | The log, the second-occurrence rule, and the control-byte sweep |

Plus the rule at the top: a project's own instructions override this file. That is the eighth,
and it is what makes the other seven safe to keep short.

## The three that carry the most weight

**"Say which surface you tested."** Most wrong claims from an agent are not fabrications;
they are correct statements about the wrong thing. A passing suite is a fact about the
suite. This rule forces the sentence *"it passed X, therefore Y"* into the open, where the
gap between X and Y is visible.

**"Name the contradiction."** When two signals disagree, the tempting move is to pick the
one that fits and continue. The disagreement is usually the finding. An agent that silently
picks a side has destroyed the most informative thing it had.

**"Fix every published surface before the next task."** The moment a check overturns
something you already wrote, every uncorrected copy keeps misinforming on its own. This is
the rule with the longest tail: it only reaches surfaces someone remembers exist, which is
why publishing anything means recording where you put it, in the same turn.

## Writing your own

Three things make the difference between an instruction file that shapes behaviour and one
that gets skimmed:

**State the reason, briefly.** A rule with its reason attached survives contact with an
edge case, because the reader can tell whether the edge case is inside the reason. A bare
imperative gets either over-applied or ignored.

**Prefer a rule that changes a default to one that adds a step.** "Say which surface you
tested" changes how every claim is phrased. "Run the linter before committing" adds a step
that gets skipped when busy.

**Delete on a schedule.** Instruction files only grow. Put "is anything here now
unnecessary?" in your periodic routine, and mean it. The audit that produced these eight
found that most of what it cut had been added for a reason that had since stopped existing.

---

Previous: [the four memories](20-the-four-memories.md) · Next: [skills, plugins and hooks](40-skills-and-plugins.md).
