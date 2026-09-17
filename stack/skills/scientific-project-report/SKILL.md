---
name: scientific-project-report
description: Reconstruct and write self-contained scientific reports from long, iterative technical or research projects with superseded claims, conflicting artifacts, multiple configurations, heterogeneous evidence, or open validation gates. Use when the evidence state must be reconciled before writing; do not use for simple summaries, literature reviews, copy or style editing that needs no evidence reconciliation, or projects governed by one stable source.
---

# Scientific Project Report

**Created by Celso Goulart / [GitHub](https://github.com/cgoulart21)**

This open-source methodology turns an iterative project history into a report whose
claims, objects, evidence, and remaining uncertainty can be audited by an external
reader.

**Licence:** This skill is released under CC BY 4.0. Share and adapt it for any
purpose with credit. See `LICENSE.txt` for the full terms.

**Feedback & Support:** Send methodology feedback to the creator through the contact
link above. If a problem comes from the agent not following this skill, acknowledge
and correct the execution instead of attributing it to the methodology.

## Outcome and boundaries

Produce a scientifically coherent report, not a chronological transcript. Preserve
the causal history needed to understand the current result while preventing obsolete
assumptions, mismatched configurations, or incomplete validation from leaking into
the conclusions.

Respect the requested audience, language, disciplinary conventions, document format,
and temporal cutoff. Invoking this skill does not itself authorize publication,
external research, file mutation, or transmission of project material; act only within
the user's actual request. Before sending any source material to an external service,
disclose the destination, content categories, exact item count, approximate volume,
exclusions, credential persistence, and external-processing risk, then obtain explicit
consent for that payload. Do not request consent again when those exact disclosures and
that payload are already covered; label any unavailable disclosure field as unknown.

## Evidence invariants

Keep these distinctions explicit throughout the work:

- chronology is not validity: a newer statement is not automatically stronger, and an
  older result is not automatically obsolete;
- object identity matters: physical specimens, model configurations, CAD revisions,
  protocols, and intended products are not interchangeable;
- theory, literature support, implementation checks, reproduced simulations, digital
  validation, physical observations, calibrated measurements, and independent
  replication are different evidence classes;
- a model can be verified within its assumptions without being validated physically;
- a prediction is not a measurement, and a manufactured object is not an approved
  experiment;
- unresolved and not-yet-tested claims are not negative results;
- precision in prose must not exceed the precision, identifiability, or traceability of
  the underlying evidence.

## Workflow

### 1. Establish the reconstruction contract

Identify the intended reader, scientific question, reporting standard, source scope,
cutoff date, requested deliverables, and authorization boundary. Read local project
instructions and current handoff/source-of-truth documents before interpreting older
material. State reasonable assumptions; ask only when a missing choice would change the
scientific meaning or the allowed action.

### 2. Inventory sources and stabilize the vocabulary

Inventory project history, reports, notebooks, code and configuration, raw data,
derived results, figures, protocols, digital artifacts, and physical-test records.
Record provenance and currentness rather than treating every file as equally
authoritative. Keep the investigation proportional to the material claims and the
requested scope; do not perform unlimited archaeology.

Name every materially distinct object or revision. Create stable identifiers for
physical specimens, numerical configurations, digital designs, protocols, and target
systems. Do not merge two objects merely because they share a nickname or nominal
geometry.

### 3. Build the four control views before drafting

Read [references/artifact-schemas.md](references/artifact-schemas.md) and create four
logical views:

1. a timeline with explicit supersessions;
2. a claim–evidence–status matrix;
3. a configuration map linking physical, numerical, digital, and procedural objects;
4. an open-gates register tying missing evidence to the claims it would unlock.

They may share one working document and need not be user-facing unless requested. Do
not begin the report body until the views expose the central contradictions and
configuration mismatches or explicitly record that none material were found. Use
`unknown`, `unresolved`, or `not recorded` instead of inventing a bridge. Do not assign
automatic truth scores; status and equivalence require scientific judgment.

### 4. Resolve contradictions by evidence, not by recency

For each conflict, identify the exact claim, object, assumptions, evidence, and later
decision that allegedly supersedes it. Prefer reproducible primary project evidence
over narrative summaries, but retain an explicit unresolved state when the evidence
does not close the conflict. Different conditions can explain different outcomes and
should not be mislabeled as contradictions. A correction propagates only to the claims
that depend on the corrected premise.

### 5. Select the external narrative

Apply the attempt-inclusion test in
[references/narrative-and-preflight.md](references/narrative-and-preflight.md). Retain
history only when it changes a current decision or interpretation, establishes a
meaningful limit or negative result, supports reproducibility, or prevents a likely
misunderstanding. Otherwise preserve it in traceability notes or omit it. Work spent is
not itself a scientific inclusion criterion.

### 6. Derive the report from the evidence controls

Read [references/narrative-and-preflight.md](references/narrative-and-preflight.md)
before drafting. Use IMRaD when appropriate, but adapt to the target discipline or
reporting standard. Explain the system and terminology for an external reader before
using project shorthand.

Build the theoretical foundation around the claims, methods, parameters, and
limitations actually needed by the report. Distinguish external literature from
project-generated evidence. Methods should describe the defensible scientific
sequence, not reproduce every internal attempt. Results should follow evidence classes;
discussion should interpret rather than silently add new results; conclusions should
contain only claims permitted by the matrix. Write the abstract last.

### 7. Verify proportionally to the claims

Re-run supplied validations and regenerate key results when feasible and authorized.
Record exact commands, versions, configurations, outputs, and blocked checks. A blocked
execution is not a passing test. Keep computational, digital, fabrication, assembly,
measurement, and operational gates separate.

## Pre-flight before delivery

Re-read this skill, both control references, and the final artifacts. Do not deliver
until all applicable checks pass:

- every material claim in the body, abstract, tables, figures, captions, discussion,
  recommendations, and conclusions maps to a current or explicitly conditional matrix
  row;
- every material quantitative result has an object, configuration, conditions,
  provenance, evidence class, and units or an explicit `dimensionless`, `count`, `date`,
  or `not applicable` designation;
- abstract, tables, discussion, and conclusions use the same configuration identities
  and claim status;
- superseded or refuted premises do not survive in captions, figures, appendices, or
  recommendations;
- measured, observed, simulated, digitally checked, manufactured, and validated are
  used according to their actual evidence class;
- limitations and open gates appear near the claims they bound, not only in a final
  disclaimer;
- each narrated attempt passes the inclusion test;
- figures, tables, equations, references, and reproducibility instructions are complete
  and internally consistent;
- a reader who did not participate in the project can identify what was done, what was
  found, what remains conditional, and what should happen next;
- the report respects the requested temporal cutoff, and later evidence is either
  excluded or clearly separated as post-cutoff context;
- if the output will be public or externally shared, project identifiers and sensitive
  details have been checked against the user's authorization for that audience;
- any output document has passed the format-specific structural and visual checks
  required by its medium.

If a check fails, narrow the claim or restore the missing traceability. Mark a claim
`pending` when defined evidence is still absent, `unresolved` when available evidence
cannot choose among live interpretations, or `refuted` when contrary evidence closes
the stated scope. Do not smooth over the inconsistency for narrative fluency.
