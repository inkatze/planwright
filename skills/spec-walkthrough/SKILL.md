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

On a successful load the command assembles the bundle into a single
self-contained HTML file and writes it to the gitignored
`.claude/walkthroughs/<spec>/` location (REQ-E1.1), naming the path in the load
report. The artifact carries the one-pager, the decision map, the drawn
dependency graph, and the teach-back; a partial `--scope` selector renders only
the sections in its scope (a single file, a requirement group, the decision set,
the task graph, or one decision plus its blast radius), and the framing adapts
to the bundle's auto-detected status (REQ-B1.2, REQ-B1.3).

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

**Artifact.** On a successful load the command assembles the bundle into a
single self-contained HTML file (via `scripts/spec-assemble.sh`) and writes it
to the gitignored `.claude/walkthroughs/<spec>/<spec>.html` (REQ-E1.1); the load
report names the path. The file opens offline in any browser with nothing
installed (REQ-E1.2): the read (the one-pager) first, the teach-back prompt
after it, all bundle content HTML/SVG-escaped so markup in the spec displays as
literal text and never executes (REQ-E1.7), identifiers behind an off-by-default
reveal toggle (REQ-D1.3), original styling inlined that draws on MIT-licensed
design primitives (REQ-E1.6), and a
bundle + commit provenance stamp so a reader can tell whether it is stale
(REQ-E1.5). Open it directly: `open .claude/walkthroughs/<spec>/<spec>.html`.

**Optional Graphviz enhancement.** The dependency graph is always drawn as
inline SVG (never ASCII), self-contained and offline. When the Graphviz `dot`
binary is present it is used for a richer node layout (read-only, for
coordinates only); when it is absent, exits non-zero, times out, or emits an
unparseable layout, the view degrades identically to a built-in layout and
records a one-line in-artifact note saying which path was taken (REQ-E1.3, D-5).
`dot` is never on a path that can fail the render, so the artifact is fully
self-contained and offline either way; only the layout differs. No installation
is required: Graphviz is an enhancement, not a dependency. Two environment
variables tune the probe: `SPEC_WALKTHROUGH_DOT` overrides the binary name
(default `dot`; point it at a name that does not exist to force the built-in
layout), and `SPEC_WALKTHROUGH_DOT_TIMEOUT` sets the watchdog in whole seconds
(default 5; any value that is not a plain non-negative integer, such as `0.5`,
is coerced back to 5) before a slow `dot` run is killed and the layout degrades.

## Teach-back

The teach-back is the comprehension check: the reader restates the spec's own
assertions, section by section, and judges each for themselves (D-3, D-9;
REQ-C1.5). The claim set is extracted once by `scripts/spec-teachback.sh` over
the plain-language translation stream — every live requirement and every
decision becomes one claim, grouped into sections (one per requirement group,
then the decisions) — and **both** delivery paths render from that single
source, so they always cover the same claims:

- **In-artifact** (assembled by the HTML task): a self-paced
  agree / disagree / unsure checklist, one neutral choice per claim. It records
  the reader's marks; it has no comparison engine and supplies no answer.
- **In-session walk** (optional, this skill): present each claim section by
  section, ask the reader to restate it in their own words, and record the
  response. Where a restatement diverges from the source, **surface the
  divergence** — show the verbatim source for the reader to compare — and let
  the reader adjudicate (REQ-D1.4). Never say who is right, never score, never
  supply the "right" answer: the independence firewall (REQ-D1.1) means the
  tool presents and structures, the human judges.

Run the full read first; only then offer the teach-back. The agent voices no
verdict, score, or assessment of the spec at any point.

## Invariants

These hold at every stage of the rendering pipeline:

- **Strictly read-only** (REQ-A1.3). The command never edits a bundle file,
  commits, pushes, changes a status, or writes the kickoff brief. Its only
  sanctioned write is the generated artifact to the gitignored
  `.claude/walkthroughs/<spec>/` location; it modifies no tracked content (the
  optional Graphviz probe's only writes are ephemeral, auto-cleaned `$TMPDIR`
  temp files).
- **Status-agnostic** (REQ-A1.4, REQ-B1.4). Every status renders — Draft, Ready,
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

After each run, compare these instructions against the doctrine and spec they
implement: the `spec-format` and `security-posture` doctrine docs (the bundle
file set and identifier discipline this command reads, and the data-hygiene rule
for the artifact it writes) and REQ-F1.4 (the completion-time drift-observation
contract). If a concept this skill names (the bundle file set, the identifier
charset, the path-containment gate, or the artifact data-hygiene rule) has
changed meaning, gained or lost a step, or moved between docs, append a one-line
drift observation to `specs/_observations/opportunities.md` in the standard
format (`- <YYYY-MM-DD> [<repo>] skill-drift(spec-walkthrough): <what>`) and
commit the append as its own chore commit, per REQ-B3.2 / D-42. In repositories
without `specs/`, surface the drift to the user instead of writing the log. Do
not edit this skill or the doctrine docs to resolve the drift; the observation
log's reader owns folding drift into spec amendments.
