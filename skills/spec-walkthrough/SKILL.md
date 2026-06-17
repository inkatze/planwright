---
name: spec-walkthrough
description: >
  Render a spec bundle (or a chosen slice) into a plain-language, didactic
  comprehension artifact a human reads and judges for themselves: an unaided
  cold read before kickoff, re-orientation mid-execution, or onboarding to a
  finished or abandoned spec. Standalone and strictly read-only: it renders any
  status, never edits, signs off, mutates the pipeline, or delivers a verdict of
  its own. The independent complement to /spec-kickoff's guided dialogue.
argument-hint: "[--scope <selector>] [--reveal] <spec-path>"
---

# /spec-walkthrough

A standalone, read-only command that renders an existing spec bundle, or a
selected part of it, into a visual, plain-English artifact a human reads and
**judges for themselves** (REQ-A1.1, D-1). It lowers the cost of absorbing a
dense bundle so a reader can independently evaluate it at any lifecycle stage,
and it stands apart from `/spec-kickoff` precisely so that read stays
independent: the moment the authoring agent performs the comprehension,
independent review collapses into "the agent reviewed its own spec."

This skill is being built task by task. **Today it is the command scaffold**
(Task 1): the surface, the safety gate, the read-only load, and graceful
degradation. The rendering pipeline (the bundle model, the plain-language
translation, the one-pager, teach-back, the drawn graph and decision-map views,
the self-contained HTML artifact) lands in the following tasks and extends this
same entry point. Until then the command loads a bundle and reports its shape;
it produces no artifact yet.

## Doctrine

Resolve and read these rule docs at run start via the rule-doc resolution
convention (`scripts/resolve-rule-doc.sh <doc-name>`, or the documented
`PLANWRIGHT_ROOT`/`CLAUDE_PLUGIN_ROOT` chain): `spec-format` (the bundle this
command reads conforms to the meta-spec — its file set, headers, and identifier
discipline govern what the scaffold loads and validates) and `security-posture`
(the identifier-charset and path-containment rules the scaffold enforces before
any read, and the data-hygiene rule for anything it later writes). Their
definitions govern wherever this skill names a concept. If one does not resolve,
halt with a clear message naming the missing doc and the chain consulted
(REQ-K1.7: a clear message is the graceful arm; proceeding without doctrine is
the opaque failure).

## Invocation

Run from the repository root (the scaffold resolves `specs/` relative to the
working directory, the same contract as the validator):

```sh
scripts/spec-walkthrough.sh [--scope <selector>] [--reveal] <spec-path>
```

- **`<spec-path>`** — `specs/<spec>` or the bare `<spec>` (the two sanctioned
  forms). The `<spec>` segment is charset-validated against
  `^[a-z0-9][a-z0-9-]*$` (max 64) and the resolved path is containment-checked
  **before any read** (REQ-A1.6). A hostile or malformed identifier or a path
  that escapes `specs/` is a clean refusal that never becomes a path and never
  echoes the candidate back.
- **`--scope <selector>`** — which part to render (REQ-A1.2, REQ-B1.2). Default
  is the whole bundle. Selectors: `whole`; `file:<name>` (one of
  `requirements`, `design`, `tasks`, `test-spec`); `reqs:<GROUP>` (one
  requirement group, e.g. `reqs:A`); `decisions` (the decision set); `tasks`
  (the task graph); `decision:<id>` (a single decision plus its blast radius,
  e.g. `decision:1` or `decision:D-1`).
- **`--reveal`** — expose the underlying identifiers. Off by default (REQ-D1.3):
  the default view is plain and audience-neutral.

**Exit codes.** `0` the bundle loaded (full or partial); `1` graceful
degradation with nothing to load (the bundle directory is absent, holds none of
the four files, or the requested scope resolves to no part of it) — a clear
message names what is absent or the available scopes, never an opaque halt
(REQ-A1.5); `2` a clean refusal (a malformed invocation, or a hostile/malformed
identifier or escaping path).

## Invariants

These hold at every stage as the rendering pipeline is built on top:

- **Strictly read-only** (REQ-A1.3). The command never edits a bundle file,
  commits, pushes, changes a status, or writes the kickoff brief. Its only
  sanctioned write is the generated artifact to the gitignored location (a later
  task); the scaffold writes nothing at all.
- **Status-agnostic** (REQ-A1.4, REQ-B1.4). Every status renders — Draft,
  Active, Done, Retired, Superseded — in deliberate contrast with the execution
  skills' non-Active refusal. Rendering is read-only, so that refusal's safety
  rationale does not apply, and terminal bundles stay valuable for archaeology.
  There is no Active gate.
- **Presents and structures; the human judges** (REQ-D1.1, the independence
  firewall). The command never delivers a verdict, score, or quality assessment
  of its own. It renders the bundle and records the reader's own responses; it
  never supplies the "right" answer.
- **Degrades, never halts opaquely** (REQ-A1.5). A missing, malformed, or
  partial bundle, or an unresolvable scope, yields a clear message that names
  what is present and what is absent.

## Maintenance

After a run, compare these instructions against the resolved doctrine docs
(`spec-format`, `security-posture`). If a concept this skill names has changed
meaning, gained or lost a step, or moved between docs, append a drift
observation to `specs/_observations/opportunities.md`
(`- <YYYY-MM-DD> [<repo>] skill-drift(spec-walkthrough): <observation>`) and
tell the user what drifted. Do not edit this skill or the doctrine docs to
resolve the drift; the observation log's reader owns folding drift into spec
amendments.
