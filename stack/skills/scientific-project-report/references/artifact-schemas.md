# Control artifact schemas

Create these views before drafting a long-project report. Adapt fields to the
discipline, but preserve the distinctions they enforce. Use stable object identifiers
and explicit missing-value labels such as `unknown`, `unresolved`, and `not recorded`.

## 1. Timeline with supersessions

| Sequence/date | Object/configuration | Event, claim, or decision | Primary evidence | Supersedes / is superseded by | Current effect | Report disposition |
|---|---|---|---|---|---|---|
| T1 | specimen-A / model-A1 | Initial parameter estimate adopted | notebook page, raw file, commit, or protocol | Superseded by T4 for this parameter only | Historical input | Omit or describe as initial assumption |

Do not use a generic “later work superseded earlier work” note. Name the dependent
claim and the scope of supersession. A revised input does not automatically invalidate
unrelated geometry, methods, or observations.

## 2. Claim–evidence–status matrix

| Claim ID | Proposed claim | Object/configuration | Assumptions and domain | Evidence and provenance | Evidence class | Independence / countercheck | Status | Publishable wording |
|---|---|---|---|---|---|---|---|---|
| C-01 | Configuration R yields 12 units at 30 Hz | model-R2 | stated load, damping, and input | reproducible run at revision X | reproduced computation | no physical countercheck | current-conditional | “The model predicts 12 units under…” |

Recommended claim statuses:

- `current-supported`: evidence supports the claim at the stated scope;
- `current-conditional`: valid only under named assumptions or within a model;
- `unresolved`: available evidence cannot choose among live interpretations;
- `pending`: the claim awaits a defined gate and should not yet be asserted;
- `superseded`: replaced for a named scope by stronger or corrected evidence;
- `refuted`: evidence contradicts the claim in the stated scope.

Recommended evidence classes include theory/derivation, external literature,
implementation check, reproduced computation, digital-design validation, physical
observation, calibrated measurement, and independent replication. Add domain-specific
classes when needed, but do not collapse them into one “validated” label.

The `Publishable wording` column is the bridge to prose. It should encode the correct
verb, scope, conditions, and uncertainty before the report is written.

## 3. Configuration map

| Config ID | Physical specimen | Numerical model/config | Digital design revision | Protocol/data source | Critical parameters | Mapping quality | Known mismatches / unknowns |
|---|---|---|---|---|---|---|---|
| R2 | prototype-P1 | config-R2 | CAD-D3 | protocol-V2, dataset-S7 | geometry, material, input, boundary condition | partial | material batch unrecorded; model uses nominal input |

Use `exact`, `partial`, `nominal only`, `incompatible`, or `unknown` for mapping quality.
If a reported result combines artifacts from different rows, name that composition and
justify it. Never let a shared label imply equivalence.

## 4. Open-gates register

| Gate ID | Claim or decision unlocked | Required evidence | Acceptance criterion and provenance | Current evidence | State | Next action |
|---|---|---|---|---|---|---|
| G-03 | Claim physical output at operating condition | calibrated input and output series on identified specimen | protocol-defined range and repeatability | simulation only | HOLD | execute protocol on specimen-P1 |

Use `GO`, `HOLD`, and `NO-GO` only when their criteria and scope are explicit. A digital
pass can release fabrication while the physical-performance gate remains on HOLD.
Separate gates for fabrication, fit, operation, measurement, scientific interpretation,
and product claims when they require different evidence.

## Optional source register

When the corpus is large, add a compact source register:

| Source ID | Type | Date/revision | Object/configuration | Authority/currentness | Extracted facts | Contradictions or caveats |
|---|---|---|---|---|---|---|

The register reduces repeated reading, but it does not replace inspecting primary
evidence for high-impact claims.

## Artifact quality checks

- Every material claim intended for the report appears as a matrix row.
- Every matrix row refers to a configuration-map identity.
- Every superseded or refuted row links to the evidence that changed its status.
- Every pending material claim refers to an open gate.
- Unknown mappings remain visible instead of being inferred from nominal similarity.
- Precision and certainty are no stronger than the weakest necessary evidence link.
