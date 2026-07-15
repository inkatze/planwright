# Autopilot Reflex — Test Spec

**Status:** Done
**Last reviewed:** 2026-07-02
**Format-version:** 1

Coverage mix: the scripts (publish, comparator, lock logic) are automated
`[test]` — deterministic input/output, fixture git repos with a throwaway SSH
signing key (never 1Password) so CI and any contributor machine run them
identically under `mise run check`. Doctrine and catalog artifacts are
`[design-level]` (existence, required content, link-check). Live GitHub
behavior (release-please cycle, branch protection, Verified badge, the organic
release) is `[manual]`, human-gated by construction. The altitude gate is
behavioral skill prose: `[design-level + manual]`.

## REQ-A — The autopilot-reflex doctrine

### REQ-A1.1 — Six-step reflex doc exists [design-level + test]

`doctrine/autopilot-reflex.md` contains all six named steps.
`scripts/resolve-rule-doc.sh autopilot-reflex` resolves it (resolver test);
the doctrine link-check in `mise run check` covers the index link.

### REQ-A1.2 — Altitude triggers defined [design-level]

The doc defines both trigger classes (seed claims, mid-flow signals) and the
resolve-before-design rule. Verification: design-level read at task-PR
review against this REQ.

### REQ-A1.3 — Phase re-anchor defined [design-level]

The doc defines the phase-end altitude restatement + drift flag. Verification:
design-level read at task-PR review.

### REQ-A1.4 — Trigger-scoped altitude D-ID rule [design-level]

The doc states the record-when-triggered / no-record-otherwise rule and that
the D-ID is cited from the goal. Verification: design-level read at task-PR
review; REQ-I1.2 is the live demonstration.

### REQ-A1.5 — Standard resolution + index link [test]

Covered by the resolver test and link-check named under REQ-A1.1.

## REQ-B — Release-tagging policy

### REQ-B1.1 — Policy note exists with the five points [design-level]

`doctrine/release-tagging.md` cites `autopilot-reflex` and states: detection
automated, approval = human merge, publish human-gated + signed per policy,
window locked, merge/publish never autonomous. Link-check covers it.

### REQ-B1.2 — Capability/mechanism/value split explicit [design-level]

The policy note carries the altitude table assigning each shipped piece to
core / template / config. Verification: design-level read at task-PR review
against D-13.

## REQ-C — Release detection & proposal

### REQ-C1.1 — Release PR maintained automatically [manual]

On this repo: land a conventional commit on `main`, observe the release PR
created/updated with version bump + CHANGELOG, edit and close/reopen to
confirm correct/cancel semantics. (Live third-party behavior; not
fixture-testable honestly.)

### REQ-C1.2 — plugin.json is the version of truth [design-level + manual]

The release-please config targets `.claude-plugin/plugin.json` `$.version`
(config review), and the observed release PR bumps it (manual cycle above).

### REQ-C1.3 — CI never tags [manual]

After a full proposal cycle (PR created, updated, merged) and before the
publish step runs: `git ls-remote --tags origin` shows no new tag and no
GitHub Release exists. This is the PR-only mode's load-bearing property.

### REQ-C1.4 — Merge is human; no merge call sites [test + design-level]

A repo-wide grep test asserts no shipped script/workflow/skill invokes a
merge of the release PR (`gh pr merge` / merge API); the invariant prose is
confirmed by design-level read at task-PR review.

### REQ-C1.5 — Notes from PRs, spec-enriched [manual]

The generated CHANGELOG section for a real cycle groups by
conventional-commit type; a PR carrying spec/task references shows them; a PR
without them still appears.

## REQ-D — Signed publish

### REQ-D1.1 — Signer-agnostic publish script [test]

Fixture repos: one with SSH signing configured (throwaway key), one with none
— `auto` signs in the first, warns + annotates unsigned in the second; no
signer name appears in the script (grep assertion).

### REQ-D1.2 — Tags the observed merge SHA [test]

Race fixture: merge a version bump, add a further commit to `main`, run the
publish — the tag points at the bump-merge SHA, not HEAD.

### REQ-D1.3 — Safety gates refuse without side effects [test]

One failing fixture per gate: existing local tag, existing origin tag,
non-monotonic version, dirty tree, diverged main, CI-not-green (stubbed `gh`).
Each exits non-zero, names the gate, and leaves no tag/Release behind. A
first-release fixture (no existing tags) passes the monotonicity gate and
publishes — the fresh-adopter case.

### REQ-D1.4 — require_signed_tags modes [test]

`auto` / `require` / `never` each exercised: `require` refuses in the
unsigned fixture; `never` skips signing in the signed fixture; defaults
resolve `auto` when unset.

### REQ-D1.5 — Signature verified before push [test]

Signed fixture: assert `git tag -v` runs (and gates the push) before any push
occurs; a corrupted-signature fixture aborts unpushed.

### REQ-D1.6 — version_file knob [test]

A fixture repo versioning `package.json` publishes correctly with
`version_file` overridden; the default resolves plugin.json.

### REQ-D1.7 — Release from CHANGELOG section, --verify-tag [test + manual]

Stubbed-`gh` test asserts the invocation shape (notes = the version's
CHANGELOG section, `--verify-tag`, no tag creation by `gh`); the live path is
covered by REQ-I1.1. A partial-publish fixture (tag pushed, Release absent)
resumes by creating the Release, per REQ-D1.3's idempotency exception.

### REQ-D1.8 — Comparator [test]

`release-pending.sh`: ahead-of-tag → pending with version; equal → none; no
tags yet → pending (first release); malformed version → error.

### REQ-D1.9 — Portability conventions + CI wiring [test]

shellcheck/shfmt over both scripts in `mise run check`; tests registered in
the aggregate check; `CDPATH=.` regression case per the house convention.

## REQ-E — Untagged-window lock

### REQ-E1.1 — Check fails in the window, names the command [test + manual]

Unit tests on the check's logic (comparator-driven): in-window run exits
non-zero with the publish command in output. Manual: the required check
observed red on this repo during the REQ-I1.1 window.

### REQ-E1.2 — Passes outside the window [test]

Out-of-window fixture exits zero; a non-bump PR fixture is unaffected.

### REQ-E1.3 — Merge serialization on this repo [manual]

Repo settings show the check required and merge queue (or
require-up-to-date) enabled; adopter guidance shipped. Settings are not
CI-assertable; verified at T6 (merge-serialization settings land), observed
live at T11.

### REQ-E1.4 — Correctness independent of the lock [test]

The REQ-D1.2 race fixture runs with no lock present — the tag still lands on
the merge SHA.

## REQ-F — Surfacing

### REQ-F1.1 — Release-PR body instructions [design-level + manual]

The release-please config's PR body template carries merge-then-publish
instructions; observed on a live release PR.

### REQ-F1.2 — Bookkeeping reports pending [test + manual]

The bookkeeping path invokes the comparator (fixture test of the report
branch); a live `--bookkeeping` run in the T11 window shows the report.

### REQ-F1.3 — mise wrapper [test]

`mise tasks` lists `release`; the task invokes `scripts/release-publish.sh`
(definition assertion).

## REQ-G — Adopter path

### REQ-G1.1 — Guard-catalog entry with both facets [design-level]

The entry exists with detection + scaffold facets and the advisory/consent
framing. Design-level read at task-PR review; link-check.

### REQ-G1.2 — Decision-domains versioning entry [design-level]

The domain exists with the scheme alternatives, artifact-type heuristics, and
the D-9 worked example; `/spec-draft`'s catalog walk needs no wiring change
(resolve-catalog output includes it — resolver test).

### REQ-G1.3 — Templates opt-in only [design-level + test]

Templates live in the opt-in location; a grep/inventory test asserts no
workflow template is inside any path the installer lands by default.

## REQ-H — Authoring altitude gate

### REQ-H1.1 — Seed-claim pinning + trigger firing [design-level + manual]

`/spec-draft` prose carries the pinning step and the fire rule citing the
doctrine. Manual: a drafting exercise seeded with a trigger phrase produces
the altitude resolution before the design phase.

### REQ-H1.2 — Phase re-anchor in summaries [design-level + manual]

The running-summary convention includes the altitude line; the same manual
exercise shows it at each phase end.

### REQ-H1.3 — Kickoff lens check [design-level + manual]

`/spec-kickoff`'s lens-pass instructions name the altitude check (D-ID
present, goal citation, task match) as a kickoff-specific check item; the
canonical `discovery-rigor` lens list is untouched. Manual: a kickoff over a
triggered fixture bundle missing its D-ID surfaces the finding, and a
triggered bundle carrying its D-ID passes the check.

## REQ-I — Organic proof

### REQ-I1.1 — First automated signed release [manual]

Human-gated by construction. Evidence recorded on completion: `git tag -v`
output on the published tag, the GitHub Release URL, the tagged SHA equal to
the release-merge SHA, the lock observed red→green across the window.

### REQ-I1.2 — This bundle carries the altitude D-ID [design-level]

D-1 exists, is the altitude record, and the Goal cites it. Verified at
kickoff walkthrough (and by REQ-H1.3's check once Task 8 lands).
