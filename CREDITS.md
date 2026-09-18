# Credits

Most of the value in this repository is other people's work. Almost nothing is vendored:
`stack/manifest.md` reinstalls things from their own sources, so upstream fixes reach you
and nobody maintains a fork.

## Vendored here, with permission of their licences

| What | Origin | Licence |
|---|---|---|
| `stack/skills/source-grounded` | Adapted from `addyosmani/agent-skills` (source-driven-development) | see upstream |
| `stack/skills/design-smells` | Authored, mined from `addyosmani/agent-skills` (code-review-and-quality) and a published software-engineering playbook | MIT with this repository |
| `stack/skills/diagnose` | A customisation of an upstream skill from `mattpocock/skills` | see upstream |
| `stack/skills/scientific-project-report` | Authored | **CC BY 4.0**, own `LICENSE.txt` |

The first three carry their attribution in their own `SKILL.md` as well as here. If you
redistribute them, keep it: two of them are derivative works and the third is somebody
else's skill with local changes.

## Installed from source, never copied

| Project | What it provides |
|---|---|
| `obra/superpowers-marketplace` | The methodology plugin that acts as the backbone of the skill stack |
| `mattpocock/skills` | A large general-purpose skill collection |
| `vercel-labs/skills` | `find-skills`, for discovering what else is out there |
| `kepano/obsidian-skills` | `obsidian-markdown` and `defuddle` |
| Gitleaks | The secret scanner behind `automation/verification/` |

Their licences are their own; this repository only tells you how to install them.

## Ideas taken, not code

Some of what is here is a shape learned from reading other people's work rather than
anything copied from it:

- The **second-occurrence rule** and the failure of staged observation pipelines came out of
  auditing one such pipeline that had captured ninety-nine observations and applied one.
- The **lesson families** in `core/lessons/` are a distillation of errors paid for across
  many projects. The occurrences behind them have been removed - they named projects, people
  and dates - and what remains is the shape.
- The **durability contract** came from this repository's own failure: it froze for months
  while looking current, and the folder split is the fix.

## Licence

The authored parts are MIT - see `LICENSE`. The exception is
`stack/skills/scientific-project-report/`, which is CC BY 4.0 and ships with its own licence
file; keep that file with the folder if you redistribute it.
