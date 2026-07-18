# Worker Permission Ergonomics — Kickoff Brief

## 1. Header

- **Spec path:** `specs/worker-permission-ergonomics`
- **Spec commit at walkthrough start:** `df69b9e`
- **Walkthrough date:** 2026-07-18
- **Mode:** First activation (Status Draft, no prior brief)
- **Validator outcome (pre-flight):** clean — 0 errors, 0 warnings
  (`scripts/spec-validate.sh`)
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true`
  (both defaults; no local override)
- **Working location:** spec worktree on branch
  `planwright/worker-permission-ergonomics/spec`, clean tree; `origin` remote
  configured.

## 2. Goal & glossary

**Goal (restated).** Dispatched planwright workers flood on permission prompts
because Claude Code's static allowlist matches the *literal* command token, never
its expansion, and offers no persistent-allow for shapes it flags "cannot be
statically analyzed" (`$VAR`-path script calls, `for`/`while` loops, other
expansions) — the exact shapes `/execute-task` issues. The spec closes the flood
two ways: (1) a deterministic `PreToolUse` hook that inspects the *fully-expanded*
command and returns `allow` for an enumerated known-safe set, deferring
everything else; (2) a root-cause cleanup having the dispatching skills invoke
plugin scripts by resolved literal absolute path so the commonest shape is
statically approvable even on the hook's degraded path. Every existing guardrail
holds: no LLM in the approval path (fleet-autonomy D-18), allow-only (cannot
override `deny`/`ask`), worker-scoped, human-reviewed artifact.

**Rules out:** `auto`/`bypassPermissions` modes (LLM classifier, fleet-autonomy
D-19); non-Bash tool coverage; an operator-configurable allowlist knob (deferred,
D-8); `fleet-state-home-unresolved` (orthogonal, left unconsumed).

**Assumes:** deny→ask→allow precedence holds so a hook `allow` can never unblock a
denied command; `${CLAUDE_PLUGIN_ROOT}` expands inside a `--settings`-referenced
worker fragment (flagged for end-to-end confirmation, Section 7); a `PreToolUse`
`allow` decision actually skips the prompt.

**The trust boundary (made explicit).** The known-safe set auto-approves
`mise run`/`tasks`, `bats`, and direct execution of repo `scripts/*.sh` and
`tests/*.sh`. Each runs *arbitrary repo-defined code*. So "known-safe" is not
purely per-verb safety: it encodes an explicit trust decision — **repo-resident
scripts, tests, mise tasks, and bats files are trusted as code, including code the
worker authored earlier in the same session** (a worker legitimately runs a script
or test it just wrote). This is defensible because the worker operates inside a
trusted checkout under human-gated PRs, but it is named here so the residual risk
(a worker auto-runs unreviewed self-authored code) is auditable — carried as a
risk-register row in Section 7.

**Glossary.**

- **Defer** — the hook emits *no decision* (clean exit, no `allow` on stdout), so
  Claude Code's normal permission flow handles the command (a prompt, or a
  matching static allow). Defer == "never worse than today."
- **Segment** — one command in a compound, after a quote-aware split on `;`,
  `&&`, `||`, `|`, `&`, and newlines. **Every-segment-safe:** a compound is
  approved only if *every* segment is independently known-safe.
- **Known-safe shape** — a command whose verb (and flags) fall in the enumerated
  REQ-A1.5 set, subject to the trust boundary above.
- **Dispatched worker** vs **tower** vs **human interactive session** — the hook
  loads only for dispatched workers (via `worker-settings.json`), never the tower
  or a human's session. Blast radius is set by *where it is wired*, not by the
  hook detecting a session type.

Signed off: 2026-07-18

## 3. Requirements walkthrough

**REQ-A — the hook.** Intent confirmed: deterministic, Bash-only
(REQ-A1.7), allow-only-or-defer (REQ-A1.2), every-segment-safe (REQ-A1.4),
allow cannot override `deny`/`ask` (REQ-A1.3). One load-bearing correctness
issue surfaced and was fixed (decision below): the known-safe set was described
by *category* for coreutils and git, which hides command-runner and writer
false-allow vectors.

- **Decision (REQ-A1.5 tightened — enumeration, not category).** `gh` was
  enumerated precisely but coreutils/git were categories. Categories false-allow
  command-runners (`env`/`xargs`/`timeout`/`nohup`/`nice`/`setsid` wrap an
  arbitrary sub-command), writer coreutils (`tee`/`dd`/`cp`/`mv`/...), text-tool
  write-escapes (`sed` `w`/`s///w`, `awk` `print >`), and mutating git flag forms
  (`branch -m`, `config k v`). Resolved: REQ-A1.5 reworded to an explicit
  enumerated allowlist with sed/git flag guards; REQ-A1.6 extended with the
  command-runner, writer-coreutil, and write-escape defer set; test-spec and
  REQ-B1.6 gained the mandatory adversarial cases. `mise run`/`bats`/repo
  scripts stay allowed under the §2 trust boundary (repo-defined code), which is
  the line that separates them from the general command-runners now deferred.
  *(brief §3, 2026-07-18)*
- **Clarification (REQ-A1.4 — fd-dup vs file write).** File-descriptor
  duplication/closing (`2>&1`, `>&2`, `2>&-`) is not a file write and does not
  defer; only a file-target write-redirect other than `/dev/null` defers.
  Prevents the `>/dev/null 2>&1` idiom from over-deferring. Resolved-and-applied.

**REQ-B — implementation, robustness, security.** Confirmed: `jq` extraction
with degrade-to-defer (REQ-B1.2, the `tasks-pr-sync.sh` precedent); fail-safe on
malformed input and deep `fish -c` nesting (REQ-B1.3); fixed
`permissionDecisionReason`, no untrusted echo (REQ-B1.4, security-posture echo
discipline); framework-script security bar + quality guards (REQ-B1.5);
adversarial suite ≥30 cases, zero false-allows, deny-never-approved (REQ-B1.6).
Runs on the bash 3.2 floor via `run-tests.sh`.

- **Clarification (REQ-B1.1 — inert-data analysis).** Added the explicit
  security property that the analyzer treats the extracted command as inert data
  (never `eval`-ed, re-expanded, glob-expanded, or used as a
  pattern/format/unquoted arg), so analyzing a hostile command can never execute
  it. Was only implied by "pure shell" + security-posture; now pinned in the
  requirement. Resolved-and-applied.

**REQ-C — wiring and delivery.** Confirmed: wired into `worker-settings.json`
via `${CLAUDE_PLUGIN_ROOT}` (REQ-C1.1), worker-scoped, not in plugin-global
`hooks/hooks.json` (REQ-C1.2), human-reviewed artifact with `_about` updated
(REQ-C1.3). `${CLAUDE_PLUGIN_ROOT}` expansion in a `--settings` fragment is
carried to §7 as a risk row (end-to-end confirm at execution).

**REQ-D — root-cause literal-path invocation.** Confirmed: `/execute-task`,
`/orchestrate`, `/spec-kickoff` resolve root once and invoke plugin scripts by
literal absolute path (REQ-D1.1); the per-install literal-path allow entry stays
adopter-documented, not shipped (D-7). Defense-in-depth for the `jq`-absent
degradation path.

**Consolidated spec-edit list (applied in place, Draft):**

1. `requirements.md` REQ-A1.5 — enumerated allowlist framing; `sed`
   `w`/`W`/`s///w` and git per-subcommand flag guards; `mise run` trust-boundary
   note.
2. `requirements.md` REQ-A1.6 — defer command-runner verbs, writer coreutils,
   text-tool write-escapes.
3. `requirements.md` REQ-A1.4 — fd-duplication is not a file write.
4. `requirements.md` REQ-B1.1 — inert-data analysis security clause.
5. `test-spec.md` REQ-A1.5 / REQ-A1.6 / REQ-B1.6 — matching adversarial fixtures.
6. `test-spec.md` REQ-C1.1 — `[manual]` no-flood must re-run against the shipped
   shell port (see §5).

(This is the walkthrough's first-wave edit list. The sign-off lens pass (§8)
applied a substantial second wave — REQ-A1.8/A1.9/A1.10/B1.7 and matching
fixtures — enumerated in §8. A single `## Changelog` entry recording all kickoff
edits is written at sign-off.)

Signed off: 2026-07-18

## 4. Design walkthrough

All 8 D-IDs accounted for. Ledger:

- **D-1** (altitude — mechanism under fleet-autonomy D-18): confirmed. Honest
  altitude; the capability-vs-style sub-call is isolated in D-8.
- **D-2** (deterministic PreToolUse hook, not fatter allowlist / `auto` mode):
  confirmed. The hook sees the expanded command; the static allowlist can't.
- **D-3** (allow-only, defer-else, every-segment-safe): confirmed. The §3
  REQ-A1.5 enumeration-not-category tightening operationalizes D-3's
  "conservative allowlist, not a denylist" — consistent, no design edit.
- **D-4** (`jq` + degrade-to-defer; pure-shell analysis): confirmed. The §3
  REQ-B1.1 inert-data clause reinforces D-4's antipattern rejection.
- **D-5** (worker-scoped wiring, not plugin-global hooks): confirmed.
- **D-6** (reconcile fleet-autonomy REQ-E1.4/D-19 by citation-in-place):
  confirmed with a recorded residual. The intent reading is sound and reopening
  a Ready sibling is disproportionate. **Decision:** accept D-6 as-is; log an
  observation so REQ-E1.4/D-19 gains a forward-citation to this bundle's D-6 the
  next time fleet-autonomy is touched. Observation recorded:
  `specs/_observations/entries/2026-07-18-fa-sole-mechanism-fwd-citation-bddb4918.md`.
- **D-7** (literal-path invocation, defense-in-depth; per-install allow entry
  adopter-documented): confirmed.
- **D-8** (fixed conservative core allowlist; operator knob deferred with a
  drain-evidence gate): confirmed.

No design decision contradicts a walked requirement; the §3 requirement edits
are all consistent with the accepted decisions (clarifications, not
contradictions).

Signed off: 2026-07-18

## 5. Verification approach

**Coverage mix** (cite: `test-spec.md`; all 17 REQs pinned, validator-confirmed):
predominantly `[test]` — the adversarial suite `tests/test-worker-command-guard.sh`
plus JSON-shape assertions, run under `mise run test` in CI; `[design-level]` for
the tool-grounded guards (shellcheck/shfmt/secret scan) and review-confirmed
properties; `[manual]` for two end-to-end confirmations.

**Ownership.**
- `[test]` and guard-based `[design-level]`: CI (`mise run test` / `mise run
  lint` / secret scan).
- `[manual]` × 2: operator-owned, exercised during execution —
  - REQ-C1.1: a dispatched worker under the wired profile runs a full task with
    no prompt-flood;
  - REQ-D1.1: plugin-script invocations are statically analyzable (persistent-
    allow offered / literal-path allow entry matched) with the hook disabled.

**Dead-path check:** none. Every REQ's named verification can run.

**Verification-integrity note (applied).** The PR #232 no-flood evidence covered
the *python prototype*; Task 1 ships a *pure-shell port* (new code). REQ-C1.1's
`[manual]` entry now states the end-to-end no-flood confirmation MUST be re-run
against the shipped shell hook — the prototype evidence does not transfer.
(test-spec edit #6.)

Signed off: 2026-07-18

## 6. Task graph

Reconstructed from the `Dependencies:` lines (cite: `tasks.md`; rendered by
`scripts/spec-graph.sh`):

- **Edges:** Task 1 → Task 2 (the hook must exist before it is wired). Task 3 has
  no dependencies.
- **Critical path:** Task 1 (2d) → Task 2 (½d) = **2.5 days** (confirmed by
  `spec-graph.sh` GRAPHCRIT `1 2`).
- **Parallelism:** Tasks 1 and 3 start together; Task 2 waits on Task 1. Two
  workers → wall-clock ≈ 2.5 days.
- **Deliberate non-edge (recorded):** Task 3 does not depend on Task 1/2 — the
  literal-path cleanup is an orthogonal defense-in-depth layer, not a serial step
  behind the hook. Left as a non-edge on purpose.

**Shared-file collision resolved (decision).** Reconstruction surfaced that
Task 2 and Task 3 both listed "document the adopter literal-path allow entry in
`worker-settings.json` `_about`" — a concurrent-edit collision the dependency
graph didn't show (no edge between them). **Resolved:** Task 2 is the **sole
editor** of `config/worker-settings.json` `_about` (hook + literal-path allow
entry); Task 3 narrows to the skill-side literal-path invocation change plus
documenting the allow entry in the options/overlay docs, and does not touch
`worker-settings.json`. Both task deliverables edited (`tasks.md`). Keeps
Tasks 1/3 parallel-safe with no artificial dependency edge.

Signed off: 2026-07-18

## 7. Risk register

**Decision-domains gap check:** all 11 catalogued domains walked (merged path via
`scripts/resolve-catalog.sh decision-domains`; no overlay additions). One
undecided touched domain — **observability** — resolved by deferral with a gate
(R5 below; `tasks.md` Deferred entry added). All other domains are
touched-and-decided or not touched (see §7 gap table in the walkthrough).

| # | Risk | Mitigation / early signal |
|---|---|---|
| R1 | **Trust boundary residual.** The known-safe set auto-approves `mise run`/`bats`/repo `scripts/*.sh`/`tests/*.sh`, i.e. arbitrary repo-defined code including code the worker authored this session; a worker can auto-run unreviewed self-authored code. | Bounded by the trusted-checkout model under human-gated PRs; the `deny` block still fires regardless; named explicitly in §2 so the acceptance is auditable. Accepted risk. |
| R2 | **`${CLAUDE_PLUGIN_ROOT}` may not expand in a `--settings`-referenced worker fragment.** If it doesn't, the hook silently doesn't load → flood continues (fails safe, but the feature is defeated). | The plugin's own `hooks/hooks.json` relies on the same expansion (working precedent); confirm end-to-end during Task 2 execution (design cross-cutting note). |
| R3 | **Claude Code platform-contract version sensitivity.** The hook-payload shape, `permissionDecision: allow` semantics, and `deny`→`ask`→`allow` precedence are pinned to CC docs v2.1.x; a future CC change could break the hook or (worse) alter precedence such that an `allow` gains reach. | Grounded facts recorded in Sources; the `[manual]` no-flood run (REQ-C1.1) re-confirms behavior against the running CC version; every degradation defers, so a broken contract fails safe unless precedence itself changes. |
| R4 | **Allow-glob portability for the per-install literal-path allow entry.** Whether CC allow-globs portably match a per-install plugin-script path is version-sensitive. | Why D-7 keeps the literal-path allow entry adopter-documented rather than shipped; the hook is the primary path, literal-path is defense-in-depth. |
| R5 | **Observability — silent auto-approve has no runtime audit trail.** A novel field false-allow is invisible in production (fixed reason string, REQ-B1.4). Decision-domains observability gap. | **Deferred with a gate** (`tasks.md`): audit-logging gated on first field false-allow evidence OR drain-loop demand. Shipped controls: adversarial suite (pre-ship), defer-safety, deny-precedence (a false-allow can't un-block a denied command). |
| R6 | **Usefulness regression — over-conservative coverage.** If the enumerated set is too tight, workers still flood and the feature underdelivers (the failure mode opposite to a false-allow). | The `[manual]` end-to-end no-flood run against the shipped shell hook (REQ-C1.1) is the acceptance signal; the prototype demonstrated adequate coverage on PR #232. |
| R7 | **Worker-scoping mis-merge.** Scoping is enforced only by *where* the hook is wired (`worker-settings.json`), with no runtime session-type check. An adopter who merges the hook stanza into a general `~/.claude/settings.json` silently auto-approves in their tower/human sessions — the blast radius D-5 rejects. | Delivery is human-reviewed manual merge/reference (REQ-C1.3); Task 2's `_about` warns explicitly against mis-merging into a non-worker settings file; surfaced by the sign-off lens pass (§8). Accepted residual. |

**Open questions:** none outstanding — all resolved to decisions (R1 accepted, R5
deferred-with-gate) or carried as accepted/early-signal risks (R2–R4, R6).

**Data hygiene:** no secrets, credentials, internal hostnames, or sensitive
operational detail recorded (security-posture artifact hygiene).

Signed off: 2026-07-18

## 8. Sign-off

**Altitude check (REQ-H1.3).** The bundle is **triggered** — D-1 records a fired
mid-flow signal (the recurring capability-vs-style call on allowlist
configurability). Verified bundle-locally from `requirements.md` `## Sources`:
the altitude D-ID **D-1 exists**, is **cited from the goal** ("The deliverable is
a **mechanism** … not a new doctrine gap (D-1)"), and the **task decomposition
matches** the claimed mechanism altitude — Tasks 1–3 are all concrete mechanism
work (implement the hook, wire it, literal-path cleanup), no doctrine-first /
mechanism-only mismatch. Altitude check **passes**.

**Lens review pass.** Scope: **full bundle** (first activation). Path:
**fan-out** — five read-only sub-agents (Correctness, Security,
Error-handling/failure-modes, Tests/verification, Cross-file-consistency), with
the remaining four canonical lenses (Performance, Concurrency, Naming/structure,
Documentation) walked **inline** (declared scoping per `discovery-rigor`
proportionality; a prose spec of a stateless synchronous hook yields little
there). Findings validated per `validation-rigor` — the load-bearing shell-behavior
claims reproduced directly (`>&file` file write; `sort -o`/`uniq OUT` writes;
`git -c alias.x='!cmd'` executes with no tty; `BASH_ENV=<abs> bash <script>`
sources injected code; `fish -c "echo (cmd)"` executes via bare-paren
substitution); three-pass converged (reproduction + known shell/git/fish
semantics + `security-posture` doctrine).

Canonical lens-coverage table:

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | ~15 | False-allow vectors past the §3 enumeration + parser under-specification (Clusters A, B) |
| Security | ~5 | Path containment, git-config/env-prefix code-exec, worker-scoping mis-merge (Clusters A, C, G) |
| Error handling and failure modes | 6 | Fail-closed emission contract unpinned: crash-then-allow, split-before-match ordering, empty/non-string cmd, exit-code/stdout discipline (exit 2 = CC block), bounded runtime, invoke-failure (Cluster D) |
| Performance | none | Stateless synchronous per-invocation hook; the one runtime concern (hang/DoS) is captured under error-handling (bounded-runtime, REQ-B1.7) |
| Concurrency / state | n/a | Hook holds no shared mutable state; each invocation independent |
| Naming, readability, structure | none | Prose spec; the walkthrough did not worsen structure |
| Documentation | 2 | Brief edit-ledger nit (fixed, §3); `_about` mis-merge warning (added to Task 2) |
| Tests / verification | ~9 | Inert-data probe, deny collision fixture, fallthrough-is-defer assertion, fd-dup positive fixture, fish buried-unsafe, git/find/sed fixtures, reason-string marker, awk `system()`/`stdbuf`/`chroot` (Cluster F) |
| Cross-file consistency | 3 | REQ-A1.6 `stdbuf`/`chroot` fixture drift, REQ-A1.4 fd-dup fixture gap, brief ledger (all fixed) |

**Headline finding:** the drafted bundle (even after the §3 enumeration fix) did
**not** meet its own zero-false-allow bar. The lens pass is the last line of
defense (D-45); it earned its keep here.

**Dispositions** (human choice: *Apply all as spec edits, review the diff at the
spec PR*). All seven clusters applied in place:

- **A — safe-invocation / unknown-flag-defers** → new **REQ-A1.8**. Kills
  `sort -o`, `uniq OUT`, `markdownlint --fix`, `date -s`, `file -C`,
  `find -okdir/-fls`, and git pre-subcommand globals (`-c`/`-C`/`--git-dir`/…) at
  once.
- **B — grammar-conservative deferral** → new **REQ-A1.9**: env-assignment
  prefixes, path-prefixed verbs, fish bare-paren substitution, subshell/brace
  groups, bundled/long `-c`, multi-char redirect tokenization. Plus **REQ-A1.4**
  file-write vs fd-dup redirect precision.
- **C — path containment** → new **REQ-A1.10**: canonicalize + contain
  script/test/bats paths.
- **D — fail-closed emission contract** → new **REQ-B1.7**: emit-decision-last,
  empty-stdout + exit 0 on defer/error, never exit 2, bounded runtime,
  invoke-failure / empty / non-string → defer.
- **E — deny-precedence verified** → **REQ-B1.6** + test-spec **REQ-A1.3**
  collision case derived from the actual `deny` block; fallthrough-is-defer
  assertion.
- **F — matching adversarial fixtures** → test-spec REQ-A1.3/A1.4/A1.5/A1.6/B1.1/
  B1.4/B1.6 + new REQ-A1.8/A1.9/A1.10/B1.7 entries; inert-data side-effect probe.
- **G — worker-scoping mis-merge** → risk row **R7** + Task 2 `_about` warning.

Task 1 effort re-estimated 2d → 3–4d (the hardened analysis). Every finding is
dispositioned (all applied); none deferred, none declined. `## Changelog` entry
recorded. Validator re-run on the Ready bundle: **0 errors, 0 warnings**.

Class: meaning
Lens-pass: §8 (full-bundle fan-out; canonical lens-coverage table above; all findings dispositioned — applied)
Anchor: `d37ea69fdffc63837cff9331985210b9a3551ee2` — computed as
`scripts/spec-anchor.sh specs/worker-permission-ergonomics`

*(Anchor recomputed after an expression-only pre-merge fix for `lint:md`:
test-spec REQ entries grouped under `## REQ-<group>` headings (MD001
heading-increment) mirroring `requirements.md`; brief trailing blank lines
removed (MD012). No REQ meaning or coverage changed.)*
