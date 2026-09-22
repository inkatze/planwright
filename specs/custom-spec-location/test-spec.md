# Custom spec location — Test Spec

**Status:** Draft
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` wherever a script or fixture can prove it (the
resolver, the golden compatibility fixture, the literal-path guard, the
posture fixtures, the observation routing), all run by `mise run check` and
the repository CI; `[Gherkin]` for the authoring and dispatch scenarios that
exercise a skill end to end on a fixture; `[manual]` where a skill's handoff
prose is the artifact; `[design-level]` where a doctrine or documentation
artifact's existence and coverage is the verification.

## REQ-A — The spec root

### REQ-A1.1 — Default is today's root [test]

The golden fixture (Task 4) records each migrated script's output with every
option unset and replays it after each migration task; any path or message
difference fails.

### REQ-A1.2 — Four-layer resolution and value forms [test]

Resolver tests set `spec_root` in each layer in turn and assert
last-layer-wins; absolute, `~/`-prefixed, and relative values each resolve to
the expected canonical path.

### REQ-A1.3 — Canonicalization and refusal [test]

Fixtures for an empty value, a value with a control byte, a value naming a
file, and a relative value escaping the checkout each yield a non-zero exit
and no root; the by-layer policy is asserted per layer (warn-and-degrade
versus hard-fail).

### REQ-A1.4 — Marker required off the default [test]

A configured directory without `planwright-root.yml` is refused; the same
directory after `--init` resolves; the default root resolves with no marker
present.

### REQ-A1.5 — Reserved children follow [test]

With the root relocated, `obs-record` and the pending-note reader operate
under `<root>/_observations` and `<root>/_pending`; the reserved-name
screening still rejects a hostile underscore name.

### REQ-A1.6 — Every locator uses the resolver [test]

The literal-path guard (Task 4) passes over `scripts/` and `hooks/`; the
posture suite (Task 5) passes with the root relocated, which no hardcoded
caller can.

### REQ-A1.7 — No parent-directory inference [test]

The orchestrate lock, the tower watchdog, and anchor freshness each run
against a root whose parent is not named `specs` and succeed.

### REQ-A1.8 — Explain mode [test]

`--explain` names the supplying layer (or `default`), the canonical path, and
the posture for each fixture.

### REQ-A1.9 — Two views [test]

From a task worktree of a fixture repository, the default view prints the
worktree's root and `--canonical` prints the primary checkout's; config set
only in the primary's machine-local layer is honoured from the worktree.

## REQ-B — The primary checkout root

### REQ-B1.1 — One primary-root helper [test]

`repo --primary` from a worktree prints the primary checkout;
`PLANWRIGHT_REPO_ROOT` overrides it; a grep test asserts no script other than
the resolver calls `git rev-parse --show-toplevel` to find the repository.

### REQ-B1.2 — Overlay layers read the primary checkout [test]

The reproduction of the config-overlay observations: a machine-local value
set only in the primary checkout is read from a worktree.

### REQ-B1.3 — Worktree placement [test]

A dispatch started from inside a worktree places the new worktree under the
primary checkout's `.claude/worktrees/`, never nested.

### REQ-B1.4 — Outside a repository [test]

`repo --primary` in a plain directory exits non-zero with a message; the
overlay resolver treats the repo-side layers as absent.

## REQ-C — The install root

### REQ-C1.1 — One chain, every consumer [test]

The guard drift test asserts both command guards trust the same arm set; a
grep test asserts the chain is implemented only in the resolver.

### REQ-C1.2 — Self-hosting pin [test]

From a worktree of the planwright checkout, `install` prints that checkout;
with `PLANWRIGHT_ROOT` set elsewhere it prints the override.

### REQ-C1.3 — Content-less arm skipped [test]

An arm pointed at an empty directory is skipped with a warning and the next
arm is returned.

## REQ-D — Spec identity

### REQ-D1.1 — Bare id canonical, alias accepted [test]

Each seam is invoked with `<id>`, `specs/<id>`, and a third form; the first
two succeed identically and the third is rejected.

### REQ-D1.2 — Keyed forms unchanged [test]

The golden fixture asserts branch, worktree, lock, trailer, and
`Consumed-by:` strings are byte-identical before and after.

### REQ-D1.3 — Scope grammar agrees [test]

The dispatch scope grammar accepts the identifier and the seams that name a
unit scope produce the same token.

## REQ-E — The git posture ladder

### REQ-E1.1 — Posture classification [test]

Fixtures for an in-repo root, a root in a second repository, and a plain
directory classify as `same-repo`, `separate-repo`, and `plain`.

### REQ-E1.2 — Authoring targets the holder [Gherkin]

Given a work repository whose root is a fixture holder, when `/spec-draft`
completes a bundle, then the bundle is committed on `planwright/<id>/spec` in
the holder, the holder worktree is at `<holder>/.claude/worktrees/<id>-spec`,
and the work repository has no new commit or branch.

### REQ-E1.3 — Plain store skips git steps [Gherkin + manual]

Given a plain directory as the root, when `/spec-draft` completes, then four
files exist, no git command ran in the store, and the handoff lists each
skipped step. Manual: the handoff prose is read for the skipped-step list.

### REQ-E1.4 — Execution derives from the work repository [test]

The derivation engine on a fixture work repository yields the same task
states whether the bundle lives in-repo, in a holder, or in a plain
directory.

### REQ-E1.5 — Gate read surface [test]

The gate halts on an anchored-content mismatch and passes on a match in each
posture; in `plain` the comparison runs against the directory's files.

### REQ-E1.6 — Hook and dispatchers use the resolver [test]

The sync hook fixture and the dispatcher fixtures locate the bundle in a
relocated root.

### REQ-E1.7 — Worker write zone [test]

A worker write inside an external root is allowed; a write to the root's
sibling directory is denied.

### REQ-E1.8 — Holder guards [manual + design-level]

`/builder` run in a fixture holder wires the spec guards; the plain-store
handoff names the absence of guards.

## REQ-F — Observations across roots

### REQ-F1.1 — Store follows the root [test]

Each observation script, run with the root relocated and no `--obs-dir`,
operates under `<root>/_observations`.

### REQ-F1.2 — Named targets [test]

`obs-record --target <alias>` lands a UID-named fragment in the target root's
`entries/`; an unknown alias and a marker-less target are refused.

### REQ-F1.3 — Hygiene at the boundary [test]

A fragment carrying a source path, a hostname, or a private-repository
identifier is refused with a message naming the screen; nothing is written.

### REQ-F1.4 — No public send [design-level]

No script or skill step in this spec's deliverables opens an issue, PR, or
remote write for a fragment; asserted by reading the deliverables at kickoff
and by the absence of any such command in the routing tests.

### REQ-F1.5 — Per-accumulator identity and carry [test]

The duplicate-UID refusal fires within one accumulator and not across two;
the carry fixture runs in a holder.

## REQ-G — Guards and documentation

### REQ-G1.1 — Literal-path guard [test]

The guard flags a planted `specs/` literal in a fixture script and passes on
the resolver and on comment lines.

### REQ-G1.2 — Checks read the resolved root [test]

`mise run check` spec checks pass with the root relocated in a fixture
checkout.

### REQ-G1.3 — Documentation [design-level]

The options rows, the overlays guide section, the conventions and
getting-started updates, the spec-location guide, and the `spec-format`
versioning entry exist and pass the link and doctrine-index checks.

### REQ-G1.4 — Storage-classes amendment [design-level]

The doctrine states the class-3 home as a location the human owns, records
the three postures, and classifies the marker as class-1.

## REQ-H — Compatibility

### REQ-H1.1 — Golden fixture [test]

Recorded before migration, replayed after every migration task; any
difference fails.

### REQ-H1.2 — Existing artifacts untouched [test]

Every in-repo bundle validates and anchors identically before and after; the
archived fragments' `Consumed-by:` lines are unchanged.

### REQ-H1.3 — Options ship dark [test]

`config/defaults.yml` carries `spec_root` unset and `observation_targets`
empty; the options-reference check passes.
