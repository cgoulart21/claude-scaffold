---
name: source-grounded
description: Ground framework/library/hardware code decisions in version-specific official docs and datasheets instead of memory. Detect the exact versions from the project manifest, fetch the matching doc/datasheet page, follow it, and cite. TRIGGER — writing or reviewing framework/library/chip-specific code where version-correctness matters (APIs, peripheral/register config, build flags, pinouts, timing) and getting it from memory risks stale or deprecated patterns. SKIP — pure logic, renames, formatting, version-agnostic code, or when the user explicitly asks for speed over verification.
---

# Source-Grounded

Adapted from `addyosmani/agent-skills` (source-driven-development), tuned for mixed
embedded + general software work (adapt the examples to your stack). Training data goes
stale, APIs and silicon errata change — verify, cite, and let the user check the source.

Process: **DETECT → FETCH → IMPLEMENT → CITE**

## 1. DETECT stack + exact versions

Read the manifest; never assume the latest. State what you found explicitly.

| Manifest | Stack |
|---|---|
| `platformio.ini` / `library.json` / `library.properties` | PlatformIO platform + Arduino/ESP libs (pin the `platform =` version — e.g. pioarduino 55.03.39) |
| the board/chip in use | MCU datasheet + peripheral TRM (ESP32-C3/S3, MPU6050, MH-Z19, TP4056, TPS63020…) |
| `package.json` / `requirements.txt` · `pyproject.toml` / `Cargo.toml` / `go.mod` | Node/React · Python · Rust · Go |

Say it back: e.g. `STACK: pioarduino 55.03.39 · ESP32-S3 · LovyanGFX 1.x → fetching the version-matched pages.` If a version is ambiguous, **ask** — the version decides which pattern (or register/pin) is correct.

## 2. FETCH the specific page (not the homepage)

Get the exact page for the feature/peripheral. Authority order:

1. Official docs / datasheet / TRM (docs.espressif.com, the part's datasheet PDF, react.dev…)
2. Official blog / changelog / errata
3. Official examples / reference designs
4. High-signal community (maintainer issues) — only to locate the official answer

Tools here: **firecrawl** (JS-heavy/structured), **defuddle** (clean article/doc extraction, fewer tokens), `WebFetch` for `.md`, and the **kicad `datasheets`/distributor skills** for component PDFs. Prefer the datasheet's own tables over prose.

## 3. IMPLEMENT to the documented pattern

Follow the doc's current idiom for that version — not a remembered one. If the doc contradicts your prior, the doc wins (or flag the conflict).

## 4. CITE

Show the sources inline so they're checkable: page/table/section + URL (or datasheet §/figure). For hardware, cite the exact register/pin/timing spec used. In the vault, this doubles as the traceability every claim needs (Quality Rules).

**When NOT to use:** pure logic (loops, data structures), renames/moves, version-independent code, or when the user explicitly wants speed over verification.
