---
name: <short-kebab-case-slug>
description: <one line of 200 characters at most - the text the host reads to decide relevance, repeated verbatim as this memory's line in MEMORY.md>
metadata:
  type: user | feedback | project | reference
---

<The fact itself, in as few lines as it takes.>

<Link related memories with [[their-name]], using the other file's `name:` slug. A link to
a memory that does not exist yet is fine - it marks something worth writing later.>
---

## The four types

| `type` | What belongs in it |
|---|---|
| `user` | Who the person is: role, expertise, standing preferences |
| `feedback` | Guidance they have given about how you should work - corrections *and* confirmed approaches. Always include the reason |
| `project` | Ongoing work, goals or constraints that are **not** derivable from the code or the git history |
| `reference` | Pointers to things outside the repository: URLs, dashboards, tickets, published pages |

For `feedback` and `project`, follow the fact with a **Why:** line and a **How to apply:**
line. A rule without its reason gets applied where it does not belong, and dropped where it
does.

## Rules that keep this useful

**One fact per file.** A file with three facts gets recalled for one of them and the other
two go unread.

**Convert relative dates to absolute ones.** "Last week" is false by the time it is read.

**Do not record what the repository already records.** Code structure, past fixes, git
history and the project's own instruction file are all better sources than a memory that
drifts from them. If you are asked to remember one of those, ask what was *non-obvious*
about it and record that instead.

**Do not record what only matters to the current conversation.**

**Before writing, look for a file that already covers it.** Update that one. Two memories
about the same gotcha will eventually disagree, and you will not know which is current.

**Delete memories that turn out to be wrong.** A wrong memory is worse than no memory: it
is confidently retrieved.

**A memory is what was true when it was written.** If one names a file, a function or a
flag, verify it still exists before acting on it.

**The description is the index line.** One line, 200 characters at most, a plain YAML
scalar (no wrapping quotes, no `: `, no ` #`), copied verbatim after the link in
`MEMORY.md`. `automation/verification/Assert-MemoryIndex.ps1` fails when the two differ;
`README.md` in this folder says why there is only one text.

## Published surfaces

If the memory records a page, document or export you published - an artifact, a shared
doc, a rendered report - it belongs under `reference`, and it must carry **the URL and the
update convention**: same URL with an erratum at the top, or body rewritten.

Write it in the same turn you publish. A published page nobody has a pointer to keeps
serving the old numbers long after the repository was corrected, and nobody notices,
because nobody remembers it exists.
