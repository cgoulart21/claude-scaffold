---
name: design-smells
description: >
  Fast structural design-smell pass for reviewing a diff/PR or deciding whether a refactor
  is worth it — catches conditionals bolted onto unrelated flows, repeated same-shape
  branches, refactors that relocate rather than reduce complexity, feature logic leaking
  into shared modules, and gratuitous type escapes. TRIGGER — reviewing changes; code
  "works but feels tangled"; before accepting a refactor. SKIP — full correctness/spec
  review (this is a smell lens, not a full review); greenfield code with no refactor
  decision pending; pure style nits.
---

# Design Smells

A quick structural lens for code review and refactors. Mined from
`addyosmani/agent-skills` (code-review-and-quality) + the "SWE at Google" playbook.
These are **design smells, not nits** — treat them as signals, not blockers.

## The smells

- **Bolted-on conditional.** A new `if` grafted onto an unrelated flow is a design
  smell, not a nit. Push the logic into its own helper, state, or policy instead of
  tangling an existing path.
- **Repeated same-shape branches.** The same conditional on the same shape appearing
  in several places signals a **missing model or dispatcher**. A "temporary" branch is
  usually permanent debt.
- **Relocate vs reduce.** Ask of any refactor: does it *reduce* complexity or just
  *move* it? Count the concepts a reader must hold to follow the change. If a "cleaner"
  version leaves that count unchanged, it isn't cleaner. Prefer restructurings that make
  whole branches/modes/layers **disappear** over ones that re-centralize the same logic.
- **Delete over polish.** Prefer deleting an abstraction to polishing it. Don't
  generalize until the third real use case.
- **Leaky feature logic.** Feature-specific logic in a shared/general-purpose module is
  drift — keep logic in its owning layer; reuse the canonical helper, don't add a
  near-duplicate.
- **Papered-over boundaries.** Gratuitous `any`/`unknown`/optional/casts and silent
  fallbacks hide an unclear invariant. Make the boundary explicit — it usually makes the
  surrounding control flow simpler too. (For C/embedded: implicit narrowing casts,
  `void*` round-trips, and magic sentinel returns are the same smell.)
- **Dead artifacts.** No-op variables, `// removed` comments, unused back-compat shims.

## Approval calibration

Approve a change when it **definitely improves overall code health**, even if it isn't
perfect — perfect code doesn't exist. Don't block because it isn't how you'd have
written it; if it improves the codebase and follows the project's conventions, approve.
Flag smells with severity (blocker vs. worth-doing vs. nit) so the important ones aren't
lost in style noise.
