# Custom spec location — Test Spec

**Status:** Ready
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` wherever a script or fixture can prove it (the
resolver, the golden compatibility fixture, the literal-path guard, the
posture fixtures, the observation routing), all run by `mise run check` and
the repository CI; `[Gherkin]` for the authoring and dispatch scenarios that
exercise a skill end to end on a fixture, run on demand through the
behavioral-eval harness (never in CI) and inventoried by the manual sweep;
`[manual]` where a skill's handoff prose is the artifact; `[design-level]`
where a doctrine or documentation artifact's existence and coverage is the
verification.

## REQ-A — The spec root

### REQ-A1.1 — Default is today's root [test]

The golden fixture (Task 4) records each migrated script's output with every
option unset, from the primary checkout and from a worktree, and replays it
after each migration task; a difference outside that task's declared
expected-change set fails, and a named correction absent from every set
fails.

### REQ-A1.2 — Four-layer resolution and value forms [test]

Resolver tests set `spec_root` in each layer in turn and assert
last-layer-wins; absolute, `~/`-prefixed, and relative values each resolve to
the expected path; `~` alone resolves to `HOME`; a `~user` form and a
padded value are handled as the requirement states.

### REQ-A1.3 — Bad values [test]

Fixtures for an empty value in a higher layer over a set lower one (falls
through), an empty value everywhere (the default), a value with a control
byte in each layer (warn-and-fall-through for adopter and machine-local,
hard-fail for repo-tracked), and a missing path, a file, and an escaping
relative value in each layer (non-zero, no root, the layer named, no
fallback to the default).

### REQ-A1.4 — Marker required off the default [test]

A configured directory without `planwright-spec-root.yml` is refused from
every layer; the same directory after `--init` resolves; the default root
resolves with no marker present, both with the option unset and with it set
to a value whose primary view is `<primary checkout>/specs`, and `--explain`
names the supplying layer in the second case.

### REQ-A1.5 — Reserved children follow [test + manual]

With the root relocated, `obs-record` operates under `<root>/_observations`
of the checkout-local view; `--init` in a git repository writes the ignore
rules for `_pending/notes.md` and the per-spec runtime files, asserted by
`git check-ignore`; the reserved-name screening still rejects a hostile
underscore name. Manual: `/spec-draft` reads pending notes from
`<root>/_pending` on a relocated fixture.

### REQ-A1.6 — Every locator uses the resolver [test]

The literal-path guard (Task 4) passes over its scanned locations; the
relocated-root subset (Task 5) passes with the root relocated, which no
hardcoded caller can; a grep of `skills/` finds no command line composing
`specs/_observations`.

### REQ-A1.7 — No parent-directory inference [test]

Every script the parent-assertion sweep touches runs against a root whose
parent is not named `specs` and succeeds, deriving the checkout from the
primary-root helper.

### REQ-A1.8 — Explain mode [test]

`--explain` on each kind names the supplying arm or layer (or `default`),
the canonicalized path, and, for the spec kind, the posture and the view,
for each fixture.

### REQ-A1.9 — Two views [test]

From a task worktree of a fixture repository, the default view prints the
worktree's root and `--primary` prints the primary checkout's, for a
relative value and for an absolute value inside the primary checkout;
config set only in the primary's machine-local layer is honoured from the
worktree.

## REQ-B — The primary checkout root

### REQ-B1.1 — One primary-root helper [test]

`repo --primary` from a worktree prints the primary checkout;
`PLANWRIGHT_REPO_ROOT` naming a git toplevel overrides it, one naming a
non-repository is refused, and `--checkout` ignores it; a grep test asserts
no script other than the resolver calls `git rev-parse --show-toplevel` to
find the repository.

### REQ-B1.2 — Overlay layers read the primary checkout [test]

The reproduction of the config-overlay observations: a machine-local value
set only in the primary checkout is read from a worktree.

### REQ-B1.3 — Worktree placement [test]

A dispatch started from inside a worktree places the new worktree under the
work repository's primary `.claude/worktrees/`, never nested; the spec
worktree for a holder root is placed under the holder's.

### REQ-B1.4 — Outside a repository [test]

`repo --primary` in a plain directory and in a bare repository each exit
non-zero with a message naming the case; the overlay resolver treats the
repo-side layers as absent.

## REQ-C — The install root

### REQ-C1.1 — One chain, every consumer [test]

The guard drift test asserts both command guards derive the chain from the
helper and that each guard's own policy set (the worker's installed-roots
arm, the tower's tighter set) is unchanged; a grep test asserts the chain is
implemented only in the resolver.

### REQ-C1.2 — Self-hosting pin [test]

From a worktree of the planwright checkout, with a decoy
`CLAUDE_PLUGIN_ROOT` pointing at a content-bearing decoy tree and the pin
explicitly set as the tracked configuration sets it, `install` prints that
worktree; with the pin cleared it prints the decoy; with `PLANWRIGHT_ROOT`
set elsewhere it prints the override.

### REQ-C1.3 — Content-less arm skipped [test]

An arm pointed at an empty directory is skipped with a warning and the next
arm is returned.

## REQ-D — Spec identity

### REQ-D1.1 — Bare id canonical, alias accepted [test]

Each identity seam is invoked with `<id>`, `<id>/`, `specs/<id>`,
`specs/<id>/`, and a bundle-file path; the first four succeed identically
and the path is rejected. A directory-taking script still accepts a
directory.

### REQ-D1.2 — Keyed forms unchanged [test]

The golden fixture asserts branch, worktree, lock, trailer, and
`Consumed-by:` strings are byte-identical before and after.

### REQ-D1.3 — Scope grammar agrees [test]

The dispatch scope field grammar is unchanged; every caller that names a
unit scope passes the bare identifier; the usage and error text names the
expected shape (the scope-grammar observation's reproduction).

## REQ-E — The git posture ladder

### REQ-E1.1 — Posture classification [test]

Fixtures for an in-repo root, a root in a second worktree of the same
repository, a gitignored in-repo root, a root in a second repository, and a
plain directory classify as `same-repo`, `same-repo`, `same-repo`,
`separate-repo`, and `plain`; `--posture` and `--explain` carry the posture
and the default output is the bare path.

### REQ-E1.2 — Authoring targets the holder [Gherkin + manual]

Given a work repository whose root is a fixture holder, when `/spec-draft`
completes a bundle, then the bundle is committed on `planwright/<id>/spec` in
the holder, the holder worktree is at `<holder>/.claude/worktrees/<id>-spec`,
and the work repository has no new commit or branch. Run on demand through
the behavioral-eval harness; manual: the sweep confirms the run.

### REQ-E1.3 — Plain store skips git steps [Gherkin + manual]

Given a plain directory as the root, when `/spec-draft` completes, then four
files exist, no spec branch or worktree exists in any repository, no git
command ran in the store, and the handoff lists each skipped step and the
absence of guards. Manual: the handoff prose is read for the list.

### REQ-E1.4 — Execution derives from the work repository [test]

The derivation engine, the status render, and meta-select on a fixture work
repository yield the same task states whether the bundle lives in-repo, in
a holder, or in a plain directory, and none refuses because the spec
directory's repository differs from the work repository's.

### REQ-E1.5 — Gate read surface [test]

The gate halts on an anchored-content mismatch and passes on a match in each
posture; in the git postures it reads the default branch's committed view,
including against a holder whose default branch is not named `main`, and
an uncommitted holder edit is outside the read surface; in `plain` the
comparison runs against the directory's files.

### REQ-E1.6 — Hook and dispatchers use the resolver [test]

The sync hook fixture and the dispatcher fixtures locate the bundle in a
relocated root.

### REQ-E1.7 — Worker write zone [test]

With the resolved root handed in through the worker settings, a write inside
an external root is allowed and a write to the root's sibling directory is
denied; the guard performs no config resolution per call.

### REQ-E1.8 — Holder guards [manual + design-level]

The spec-location guide carries the holder guard recipe (design-level);
following it in a fixture holder wires the spec guards (manual); the
plain-store handoff names the absence of guards (manual, with REQ-E1.3).

### REQ-E1.9 — Halt writes in a holder [Gherkin + manual]

Given a fixture holder, when an execution skill halts to Awaiting input,
then the bullet is an uncommitted change in the holder's primary checkout
working tree with no new commit, branch, or push in the holder; the same
scenario in `plain` leaves the file. Run on demand through the
behavioral-eval harness; manual: the handoff prose names the uncommitted
file.

## REQ-F — Observations across roots

### REQ-F1.1 — Store follows the root [test]

Each observation script, run with the root relocated and no `--obs-dir`,
operates under `<root>/_observations`; carry in `plain` exits zero with a
message naming the no-op.

### REQ-F1.2 — Named targets [test]

`obs-record --target <alias>` lands a UID-named fragment in the target root's
`entries/`; an unknown alias and a marker-less non-default target are
refused; a target that is the default root of a git checkout is accepted by
shape.

### REQ-F1.3 — Hygiene at the boundary [test]

A fragment carrying an absolute path, one carrying a `~` path, and one
carrying a hostname with a public suffix, `.local`, or `.internal` are each
refused with a message naming the screen and nothing written; a fragment
naming a repo-relative file is written.

### REQ-F1.4 — No public send [test + design-level]

The routing tests assert no observation script invokes `gh`, `git push`, or
a network write; the deliverables were read at kickoff for any such step
(none).

### REQ-F1.5 — Per-accumulator identity and carry [test]

The duplicate-UID refusal fires within one accumulator and not across two;
the carry fixture runs in a holder.

## REQ-G — Guards and documentation

### REQ-G1.1 — Literal-path guard [test]

The guard flags a planted `specs/` path literal in each scanned location
(`scripts/`, `githooks/`, a `mise.toml` task body, `lefthook.yml`,
`.gitignore`, a workflow) and passes on the resolver, on comment lines, and
on each allowlisted class.

### REQ-G1.2 — Checks read the resolved root [test]

The `mise.toml` spec-check task bodies obtain the root from the resolver;
the validator and the bundle lint run against a fixture checkout with the
root relocated, the lint relaxation found under the relocated root.

### REQ-G1.3 — Documentation [design-level]

The options rows, the spec-location guide, the README index entry, and the
updated docs exist and pass the link check; a grep of `docs/` and
`README.md` for `specs/` returns only sites that state the default or the
namespace.

### REQ-G1.4 — Doctrine amendments [design-level]

`storage-classes` states the class-3 home as a location the human owns with
the committed attribute scoped to the git postures, records the three
postures, classifies the marker as class-1, and re-anchors its class-2
note; `spec-format`'s versioning entry names every changed passage;
`accumulator-taxonomy`, `orchestration-modes`, and the
`plugin-script-invocation` example agree; the doctrine-index check passes.

## REQ-H — Compatibility

### REQ-H1.1 — Golden fixture [test]

Recorded once the resolver exists, from the primary checkout and a
worktree; replayed after every migration task; a difference outside the
task's expected-change set fails; every named correction appears in exactly
one set.

### REQ-H1.2 — Existing artifacts untouched [test]

Every in-repo bundle's content anchor is recorded in the fixture baseline
and recomputes equal after every migration task; the archived fragments'
`Consumed-by:` lines are unchanged.

### REQ-H1.3 — Options ship dark [test]

`config/defaults.yml` carries no `spec_root` key and an empty
`observation_targets`; the options-reference check passes with the
`spec_root` row present and the key absent.
