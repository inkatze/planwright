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

## 9. Amendment log

### Amendment 1 — 2026-07-18 (panel-review delta re-walkthrough)

**Trigger:** `/panel-review --nested` (gemini backend) over the Ready spec
PR #234 surfaced spec-wording defects; the human dispositioned them. Ready
bundle, pre-merge → **delta re-walkthrough** (REQ-D1.4), not the amendment
ritual (reserved for Active bundles). No status flip, no PR reopen.

**Delta scope + lens pass:** 4 REQ edits + 2 test-spec entries. Delta-scoped
Discovery-Rigor lens pass walked **inline** (declared per `discovery-rigor`
proportionality — the delta is narrow and every edit tightens or clarifies). No
new contradictions; test-spec updated to match REQ-A1.9/B1.7; cross-file
consistency re-checked; validator 0/0, `lint:md` 0.

**Findings dispositioned:**

- **M1 (applied).** Heredocs/here-strings (`<<`/`<<-`/`<<<`) were pinned nowhere;
  REQ-A1.4's defer list and REQ-A1.9's tokenizer list now name them explicitly
  (REQ-A1.9's catch-all already covered them, but the redirect enumeration was
  asymmetric — output forms listed, input/heredoc omitted). test-spec REQ-A1.9
  fixture added.
- **M3 (applied).** REQ-B1.7's "parse error on the bash floor" clause read as the
  hook inspecting a *target* script's contents, contradicting REQ-B1.1's
  inert-data rule (a defect in the original sign-off-pass wording). Reworded: the
  hook decides from the command string + path metadata only, never reads target
  contents; a hook-script start failure fails safe structurally (no output →
  Claude Code's normal prompt). test-spec REQ-B1.7 updated (now `[test +
  design-level]`). Dissolves M5 (Task 1 no longer owes a target-startability
  check).
- **M4 (applied).** `awk` was absent from REQ-A1.5's allowlist yet referenced in
  A1.6's write-escape callout. Human call: **defer awk entirely** (too capable to
  allowlist — `system()`/command-`getline`). REQ-A1.6 clarifies awk defers
  wholesale and the callout is belt-and-suspenders.
- **M2 (declined).** gemini's TOCTOU symlink-swap concern on REQ-A1.10 —
  non-applicable to the single-agent trusted-checkout threat model (no concurrent
  adversary racing its own approval; R1 already accepts worker-run code).
  Recorded, no spec change.

Class: meaning
Lens-pass: §9 Amendment 1 (delta-scoped, inline walk; M1/M3/M4 applied, M2 declined, all dispositioned)
Anchor: `5bb10abed10109f92f50491d4d935ff8e61a5898` — computed as
`scripts/spec-anchor.sh specs/worker-permission-ergonomics`

### Re-anchor — anchor-scope exclusion sweep (2026-08-24)

Machine-written entry per the meta-spec's expression-only lane
(`doctrine/spec-format.md`, *Writers*), recorded by the coordinated sweep
that lands with the hash-scope change (anchor-integrity D-3, REQ-A1.4).

**Why the anchor moved:** the hash scope changed, not this bundle's
content. The per-file digests for `requirements.md`, `design.md`, and
`test-spec.md` now drop the header-block `**Status:**` line, so every
bundle carrying one recomputes to a new value. Verified by isolation:
recomputing under the amended semantics over this bundle as it stood at the
prior entry's commit (`82f4ffb`) yields the same hash recorded below, so no
anchored byte has changed since that entry was written.

**Cites the changelog line:** the 2026-07-26 `## Changelog` entry in
`doctrine/spec-format.md` ("Anchor-scope exclusion"), the doctrine half of
the change this entry re-anchors against.

Class: expression-only
Anchor: `e0f619c7444445ad8023c3756f9c80bcb869a866` — computed as
`scripts/spec-anchor.sh specs/worker-permission-ergonomics`

### Amendment 2 — 2026-10-05 (reopen: unattended self-approval extension, delta kickoff)

#### 2.1 Header

- **Mode:** reopened-bundle delta kickoff (Status Draft with a complete signed
  brief, the reopen cycle). The sign-off flips Draft→Ready again.
- **Delta:** the 2026-10-05 `/spec-draft --extend` commit (REQ groups E–H,
  superseded REQs, the new D-IDs with D-2 and D-8 superseded, Tasks 4 onward);
  the bundle's `## Changelog` 2026-10-05 entry is the authoritative list.
- **Spec commit at walkthrough start:** `63cf7e7`
- **Walkthrough date:** 2026-10-05
- **Validator outcome (pre-flight):** clean, 0 errors, 0 warnings
  (`scripts/spec-validate.sh`)
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true`,
  `kickoff_ready_ci_wait: 10m` (defaults; no local override)
- **Working location:** spec worktree on `planwright/worker-permission-ergonomics/spec`,
  clean tree, one commit ahead of `origin/main`.
- **Decision/transcript log:** no harness-provided log in this session; the
  mirror is skipped.

#### 2.2 Goal & glossary (delta)

**Restatement.** The shipped hook left an unattended fleet asking the operator
about nearly every routine step: it never modelled a leading `cd`, command
substitution, or temp writes, and by design never approved work on the
worker's own branch. The extension makes in-scope work self-approving, worker
side and deterministically, through one configurable policy whose arms are
read-only, own-branch, and scratch. Core ships read-only only; an overlay
turns on the rest. Out-of-policy prompts still reach the operator, parked, and
no tower answers them. It also closes a live false-allow (an unexpanded
operand reaching a screened verb), corrects the false premise that the hook
sees an expanded command, and removes the meta-tower's subordinate session.

**Rules out:** tower-side answering of prompts, executing self-written
scripts, an arbitrary per-verb allowlist knob, Claude Code's own safety gates
(`cd`-before-`git`, sensitive paths), and skill-prose changes (another flight).

**Assumes:** the hook receives the raw command (verified, D-10); `deny` rules
hold against a hook `allow` (asserted as an outcome, REQ-A1.11); permissions
load only at session start (D-16).

**Implicit terms resolved:**

- **Policy / arm:** the one set-valued knob and its members (`read-only`,
  `own-branch`, `scratch`).
- **Floor:** what the *guard* never approves at any policy value. It does not
  bound the profile's static allow rules, which already admit the PR-create
  and ready-flip commands; those and the ready-guard hook govern the ready
  flip as before (operator decision 2026-10-05; spec edit E1).
- **Unit identity:** the session's worktree root and unit branch.
- **Argument-independent position:** an operand of a verb whose approval does
  not depend on operand values (REQ-E1.3's enumerated set).
- **Corpus pending/shipped:** a corpus row's class is pending until the task
  delivering it lands, then enforced.

**Spec edits (consolidated list, this section):**

- **E1.** Requirements intro and REQ-F1.5: the floor is scoped to the guard's
  approvals; the profile's static rules and deny block govern independently.
  Expression-level clarification.

Signed off: 2026-10-05

#### 2.3 Requirements walkthrough (delta)

Per-group outcomes (the group intents are the bundle's own REQ-E to REQ-H
headings and the four superseding REQs; restated here only where the walk
changed or pinned something):

- **REQ-A (superseded four).** A1.11 asserts the deny outcome rather than the
  platform's order; A1.12 adds run-order analysis and the narrow substitution
  rule; A1.13 makes `time`/`timeout` transparent; B1.8 widens the hook's
  inputs. Gap found: B1.8's sole-input clause named only the policy and the
  unit identity, while REQ-F1.3 and REQ-F1.4 need the scratch root, the PR
  base, and the `worker_base_merge` value. Resolved by gap-fill (edit E2).
- **REQ-E (expansion and compound shapes).** Confirmed. The substitution rule
  is sound by construction: output reaching only argument-independent
  positions is equivalent to a literal the guard already approves; a resolved
  plain literal (`X=-exec; find . $X`) still meets the verb's screen.
- **REQ-F (the policy).** Confirmed with the floor scoped to the guard (E1).
  The own-branch arm's push comes from the profile's existing static
  `git push origin` rule, not the guard; the floor's "push to any other ref"
  is the guard's refusal, the deny block is the static side's.
- **REQ-G (profiles and delivery).** Operator decision: the static allow set
  drops `sed -n`, `sort`, and `uniq`, because a static rule skips the guard's
  argument screens and each has a write or execution form (edit E3). The rule
  is stated generally: no new static rule names a verb or subcommand with such
  a form.
- **REQ-H (source fixes and premises).** Confirmed; corpus pending/shipped
  wording clarified (E4).

**Spec edits (consolidated list, this section):**

- **E2.** REQ-B1.8 input list adds the scratch root and, for the base merge,
  the PR base and `worker_base_merge` value; paired test-spec REQ-B1.8 entry
  adds the matching unresolvable-input fixtures. Expression-level gap-fill.
- **E3.** REQ-G1.1, D-15, Task 12, test-spec REQ-G1.1, and the stopgap Sources
  line: `sed -n`, `sort`, `uniq` out of the static set, with the general
  no-write-or-exec-form rule. Meaning-class (operator decision).
- **E4.** Task 5 and test-spec REQ-H1.3: a pending class becomes enforced once
  marked shipped. Expression-level.

**Observation recorded:** the pre-existing static `git diff`/`log`/`show`
(`--output=FILE`) and `git branch` (`-D`/`-f`) rules have the same bypass;
outside this delta (`worker-profile-static-git-write-forms`).

Signed off: 2026-10-05

#### 2.4 Design walkthrough (delta)

Ledger for the delta (the earlier D-IDs stand as §4 and Amendment 1 recorded
them):

- **D-2** superseded by **D-10** (premise corrected: the hook sees the raw
  command; the hook choice stands). **D-8** superseded by **D-12** (the
  drain evidence arrived; the configurable policy is the graduated knob).
- **D-9 to D-14, D-16 to D-21:** confirmed, rationale intact.
- **D-15:** amended at this kickoff (E3): the static set drops `sed -n`,
  `sort`, and `uniq` and states the no-write-or-exec-form rule.
- **D-20/D-21:** block order swapped so the D-IDs read in order (E5,
  presentation only).

No design decision contradicts a walked requirement.

Signed off: 2026-10-05

#### 2.5 Verification approach (delta)

- **Coverage mix:** the delta keeps `[test]` as primary evidence, adds the
  sanitized real-prompt corpus (REQ-H1.3) with floor rows enforced from its
  first landing, `[design-level]` for the doctrine and documentation REQs, and
  `[manual]` end-to-end confirmations for the relaunch (REQ-G1.3) and the
  meta-tower dispatch (REQ-G1.5). Tag tallies: derive from `test-spec.md`.
- **Ownership:** CI runs every `[test]` entry through `mise run test` /
  `mise run check`; the `[manual]` entries are swept by the operator on the
  first live `--fleet --unattended` run after Tasks 13 and 15 land (the
  `/drain` inventory surfaces them).
- **Dead paths:** none found. Each new or superseding REQ has an entry that
  names a runnable check; the two kickoff extensions (B1.8, G1.1) carry their
  paired test-spec edits.

Signed off: 2026-10-05

#### 2.6 Task graph (delta)

Reconstructed from the `Dependencies:` lines (authoritative; render with
`scripts/spec-graph.sh specs/worker-permission-ergonomics`).

- **Shape after this kickoff:** Task 4 (the live false-allow) → Task 5 (the
  corpus) → one serialized guard chain 6 → 7 → 9 → 10 → 11, with Task 12
  after 9 and 10, Task 14 after 9, and Task 13 after 10 (the sign-off lens
  pass gave relaunch the session record and scratch root to carry). Tasks 8
  and 15 have no dependencies and run alongside the chain.
- **Operator decision (E6):** the tasks that edit the worker guard script are
  serialized so no two change it at once; shell-shape analysis (6, 7) runs
  before the policy (9). Order grounded in the spec: the run-order and
  substitution classes help every adopter at the default policy,
  while the own-branch and scratch arms help only where an overlay enables
  them. Edges added: Task 9 depends on 7; Task 11 depends on 10.
- **Critical path:** the guard chain; the renderer's `GRAPHCRIT` line is the
  authoritative statement.
- **Deliberate non-edges (do not "fix"):** Task 8 (scripts self-resolve
  `--head`) has no edge to Task 7, though Task 7's fixture uses
  `step-record.sh --head $(…)`: the fixture exercises the guard on that shape
  whatever the script does. Task 12 (profile) has no edge to Task 11: it edits
  the profile, not the guard. Tasks 13 and 15 touch neither the guard nor the
  profile, so neither joins the guard chain. Task 14 waits only on Task 9,
  whose policy it describes.

Signed off: 2026-10-05

#### 2.7 Risk register (delta)

**Decision-domains gap check:** the merged catalog
(`scripts/resolve-catalog.sh decision-domains`, no overlay additions) walked
against the delta. Touched and decided: data-storage and observability (the
hashed audit log, D-21), auth (the policy arms and floor, D-12, D-13),
secrets-config (hashed log, sanitized corpus, overlay-held policy value),
concurrency (per-spec lock in D-17; guard-task serialization E6),
deploy-migration (relaunch, D-16; behaviour-preserving default, D-12),
queues-async (out-of-policy prompts park, REQ-G1.4), existing-seam-reuse
(overlay layers, `worker_base_merge`), human-comprehension (the doctrine
statement, D-9). No touched domain is undecided. *(The sign-off lens pass
found this check incomplete; its decision-domain row in §2.8 records the
gaps it closed: knob syntax and merge rule, where the policy is read,
the audit-log home and retention, and relaunch versus `recover`.)*

Rows appended to §7 (R1 to R7 stand; R5 is now addressed by D-21 and Task 11):

| # | Risk | Mitigation / early signal |
|---|---|---|
| R8 | **Write approvals are new.** A canonicalization or containment bug in the own-branch or scratch arm is a false-allow that writes. | Floor evaluated before any arm; floor rows defer under every policy value in the corpus; adversarial fixtures (symlink escape, `..`, outside-root targets); core default stays `read-only`; the audit log names the approving arm. |
| R9 | **Edited repo scripts still run.** A worker can edit a tracked `scripts/`/`tests/` file (by Bash under own-branch or the `Write` tool) and run it without a prompt. | Extends R1's accepted trusted-checkout residual. The execution-bearing config paths (git hooks, `.git`, `.claude/`, tool config) are closed in both the guard and the profile (D-22); human-gated PRs bound the rest. Accepted (operator decision 2026-10-05). |
| R10 | **Parser surface growth.** Run-order state and the substitution rule enlarge an allow-only parser, the shape that produced the awk lexer's false-allows. | D-11's argued-sound rule; each adversarial fixture first shown allowing against a deliberately over-broad variant; the real-prompt corpus. |
| R11 | **Serialized guard chain lengthens delivery.** The guard-editing tasks run one at a time (§2.6 names them). | Accepted for conflict-free merges (E6); the independent tasks fill the other worker slots. Early signal: a guard task stalled in review blocks the rest of the chain. |
| R12 | **Claude Code's own gates remain.** The `cd`-before-`git` gate and the sensitive-path prompt still prompt whatever the hook says. | Fleet guide and launch text tell workers to issue `git` without a `cd`; the corpus replay after landing measures the residual. |
| R13 | **Pre-existing static git rules bypass the guard.** `git diff`/`log`/`show --output=FILE` and `git branch -D`/`-f` are statically allowed today. | Outside this delta; recorded as an observation for `/spec-draft`. |
| R14 | **Relaunch rests on documented CLI behaviour.** `--resume` not restoring `--settings` is from the sessions documentation, not measured here. | The existing `recover` already passes `--settings` explicitly; REQ-G1.3's `[manual]` live relaunch confirms the rest; the test pins the argv. |
| R15 | **Path deny rules may overlap Claude Code's own protections or fail to match.** The `Write`/`Edit` deny rules D-22 and D-23 add depend on the matcher's path semantics under a `--settings` fragment. | Task 12 checks which paths Claude Code already protects and pins each rule with a permission-matcher fixture row. |

**Open questions:** none outstanding.

**Data hygiene:** no secrets, credentials, internal hostnames, or raw worker
commands recorded; the replay table stays machine-local.

Signed off: 2026-10-05

#### 2.8 Sign-off lens review and record

**Scope and path.** Delta-scoped Discovery-Rigor review of the extension (the
2026-10-05 extension commit plus this kickoff's walk edits), spec lens set per
`artifact-lenses`, fanned out to one read-only reviewer per lens. Two scopings,
declared: dead verification paths and testability ran as one reviewer (they
probe the same surface), and a code-class **security** lens was added
explicitly, since the spec defines an allow-only permission mechanism and a
rule that permits a false-allow is a spec bug. Rendered-content safety: `n/a`
(the bundle is not rendered into an executing or markup context).

**Validation.** Findings were deduplicated across lenses (the same defect from
several reviewers counts once). Findings resting on runtime behaviour were
reproduced: the `test -v` / `[ -v` / `printf -v` subscript execution in bash,
and both shipped guards' `allow` on those shapes, by direct probe; the guard
`read`/`printf -v` opacity claim was probed and found already deferred for
`read` (kept for `printf -v`, which allows). Findings citing code or config
were checked against it (`recover`'s `--settings`, the profile's
amend-under-`git commit` text, the absence of an `xargs` guard, the existing
corpus fixture). Contract findings were checked by reading each pair of
clauses; findings several independent lenses reached (the `$TMPDIR` fixture,
the `xargs` clause, the D-6 reversal) needed no further pass.

**Lens-coverage table (spec set, plus the declared security lens):**

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness and internal consistency | 10 | Default "reproduces pre-extension" falsified by REQ-E; floor caught `/dev/null` and git's own writes; floor named the policy guard the guard cannot evaluate; deny-outcome vs guard inputs; `$TMPDIR` fixture vs REQ-E1.1; state carried across any operator; plugin roots vs REQ-A1.10; `xargs` "safe forms"; git static set self-contradiction; `cd` with unresolved identity. |
| Security (declared, code-class) | 8 | **Live false-allow** in both shipped guards (`test -v`/`[ -v`/`printf -v` subscript execution); assignment names; `cd` after failure or non-`&&`; hard links, `cp -l/-s`, `mv` sources; execution-bearing in-worktree paths; `sed -i` `e`; `git fetch`/`ls-remote` `--upload-pack` and URL operands; unpinned static git set and trust-input sources. |
| Ambiguity and interpretation forks | 14 | Variable-writing forms, name rule, `printf` in the argument-independent set, `$TMPDIR` source, per-arm fallback, unit/PR-base identity, arm-set semantics, push ownership, deny fixture generation, loop bound and `timeout` flags, fetch refspec, leading vs mid-chain `cd`, self-written-script scope, log unit and enforcer. |
| Citation and coverage integrity | 5 | D-17 cites orchestration-fleet D-6 as support while reversing it; dangling `tasks.md` Deferred pointer; cross-cutting cites superseded REQ-A1.3; untraceable "drafting-session decision" tokens; Sources entries now cited for their opposite. Validator clean. |
| Dead verification paths and testability | 9 | Bypass fixtures that already defer cannot be "shown failing first"; the recorded `cat` bypass becomes an allow under the mandated mechanism; `$TMPDIR` fixture; kept REQ-A1.4 fixtures under an arm; MCP deny rules have no Bash fixture; meta-tower `[test]` unrunnable (prose step); undefined over-broad variant; allow-rule coverage not enforced; a second corpus beside the existing one. |
| Decision-domain gaps | 5 | Knob syntax and layer-merge rule (api-surface); where the guard reads the policy (secrets-config/auth); audit-log home when the state home is unresolved (observability); retention value and enforcer (concurrency); relaunch vs existing `recover` and the scratch root across it (deploy-migration). |
| Cross-file consistency | 9 | D-13's amend claim vs the profile's static `git commit`; deny-outcome vs declared-step exception; B1.8 omits the declared steps; `$TMPDIR` fixture; E1.2 drops the name screen; relaunch duplicates `recover`; `xargs`; G1.4 vs the doctrine's standing-decision clause; kept fixtures under an arm. |
| Documentation and glossary drift | 14 | "Already-expanded" premise in A1.10, its test entry, and Sources (stale prose); goal's precedence claim (stale); D-3 and D-1 unmarked (stale); cross-cutting A1.3 (stale); "read-only" meaning three things (fork); "policy guard" unnamed (fork); `xargs` (stale); orchestration-fleet reversal (missing); doctrine index row for Task 15 (missing); stale knob deferral text and changelog omission (stale); copied tallies in the brief and D-8 (spec-format rule); "task" vs "unit" branch (fork). |
| Rendered-content safety | n/a | Not rendered into an executing or markup context. |

**Kickoff-specific checks.**

- **Altitude (triggered bundle).** The pinned altitude seed claims are in
  `requirements.md` Sources; D-9 exists and the goal cites it; the
  decomposition matches (a doctrine task, the policy-knob capability, and
  mechanism tasks). No finding.
- **Ship-gate.** The "skills emit one plain command per Bash call" flight the
  bundle names as out-of-band had no tracked record: one finding, dispositioned
  by an observation fragment (`skills-emit-plain-bash-commands`). The
  standing-decision deferral is gated in `tasks.md` Deferred; the
  pre-existing static git rules have their observation
  (`worker-profile-static-git-write-forms`).

**Dispositions (every finding dispositioned with the operator):**

- **Live false-allow** (`-v` forms in both shipped guards) — *applied*:
  folded into Task 4 with fixtures in both guards; the argument-independent
  set excludes the `-v` forms and a `printf` format (operator decision).
- **Execution-bearing paths** — *applied*: closed in both the guard and the
  profile (REQ-F1.6, D-22); edited repo scripts stay runnable, accepted as R9
  (operator decision).
- **Trust-input source** — *applied*: launcher-written session record with
  profile deny rules (REQ-G1.8, D-23) (operator decision).
- **Meta-tower verification** — *applied*: the meta step becomes a tested
  script, with the orchestration-fleet reversal recorded in D-17 (operator
  decision).
- **All remaining findings** — *applied* as one grounded batch (operator
  decision): the shell-edge tightenings (REQ-A1.12, A1.13, E1.1–E1.5,
  F1.3, F1.4), the contradictions (REQ-A1.11, B1.8, F1.1, F1.5, G1.1, D-13,
  `xargs`, `$TMPDIR`), the knob and log details (REQ-F1.1, H1.4, D-12, D-21),
  relaunch over `recover` (REQ-G1.3, D-16), the stale text and citations
  (goal, Sources, Changelog, D-1, D-3, D-8, cross-cutting, REQ-A1.14
  superseding A1.10, "unit branch"), and the test plumbing (Tasks 4, 5, 7, 9,
  12, 15 and their test-spec entries, the REQ-C1.1 baseline note). Each
  requirement change carries its paired test-spec edit.
- **Declined:** none.

**Post-lens stale-reference sweep.** Swept the bundle and this entry for the
minted (REQ-A1.14, F1.6, G1.8, D-22, D-23) and re-scoped IDs and for the
default-policy and "byte-identical" wording: fixed the brief's §2.6 shape
(Task 13 now follows Task 10), §2.7 gap-check sentence, R9 and R14, two
copied tallies, and the REQ-C1.1 baseline note. Remaining references to
REQ-A1.10 sit in completed Tasks 1–3, superseded entries, and dated
changelog lines, which record history.

Draft→Ready flipped on all four files at this sign-off (reopen cycle); validator clean at Ready.

Class: meaning
Lens-pass: §9 Amendment 2, 2.8 (delta-scoped fan-out, one reviewer per lens plus the declared security lens; canonical lens-coverage table above; all findings dispositioned — applied)
Anchor: `fe407f11a05100bbfee2657922428ae9f673e5db` — computed as
`scripts/spec-anchor.sh specs/worker-permission-ergonomics`

### Amendment 3 — 2026-10-10 (reopen: align with the merged guard, delta kickoff)

#### 3.1 Header

- **Mode:** reopened-bundle delta kickoff (Status Draft with a complete signed
  brief, the reopen cycle). The sign-off flips Draft→Ready again. The bundle
  derives Active on main (Task 8 in flight); the reopen exists only on this
  branch, per the 2026-10-10 Changelog entry.
- **Delta:** the 2026-10-10 `/spec-draft --extend` commit plus this
  kickoff's edits; the bundle's two `## Changelog` 2026-10-10 entries (the
  extension and the delta kickoff) are the authoritative list.
- **Spec commit at walkthrough start:** `b7e159a`
- **Walkthrough date:** 2026-10-10
- **Validator outcome (pre-flight):** clean, 0 errors, 0 warnings
  (`scripts/spec-validate.sh`)
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true`,
  `kickoff_ready_ci_wait: 10m` (defaults; no local override)
- **Working location:** spec worktree on `planwright/worker-permission-ergonomics/spec`,
  clean tree; the prior kickoff PR (#582) is merged, so this delta gets a new
  spec PR.
- **Decision/transcript log:** no harness-provided log in this session; the
  mirror is skipped.

#### 3.2 Goal & glossary (delta)

**Restatement.** The guard merged in PR #637 implements three operator
decisions of 2026-10-09 that depart from the signed text; this delta writes
them back so the signed spec matches the shipped guard before the remaining
guard tasks build on it. Wider: a plain assignment carries its value across
`;`, a newline, and `||` as well as `&&` (D-24); `cd` and every other
state-setting segment stay `&&`-only. Narrower: a whitespace-bearing value
resolves only inside double quotes, the one form bash and zsh agree on
(D-25). Narrower: every `ps` form carrying `-e` defers, with `ps -A` the
approved spelling (D-26). *(The newline came from §3.3's E1; §3.8's lens
pass widened the delta with REQ-E1.6, D-27, and Task 6.1.)*

**Rules out:** the shared-tokenizer zsh root fix (obs:8d46a461 stays
unconsumed). *(As walked this also ruled out task-block changes; §3.5 and
§3.8 reopened that: Task 6.1 added, Tasks 6, 7, and 12 edited.)*

**Assumes:** the merged guard implements all three; D-24's "cannot fail"
rests on the name screen covering both shells' readonly and self-set names.
*(As walked this read "which `assign_name_ok` does"; §3.8's lens pass found
zsh `zsh/parameter` read-only names it misses, now Task 6.1.)*

**Implicit terms resolved:**

- **Runs unconditionally** (REQ-A1.12, D-24): the segment is opened by
  nothing, by `;` or a newline, or by `&&` directly after another
  state-setting segment that itself carried state; an assignment after
  `||`, or after a real command's `&&`, is conditional and carries nothing.
  §3.8 wrote this definition into REQ-A1.12.

**Spec edits (consolidated list, this section):** none.

Signed off: 2026-10-10

#### 3.3 Requirements walkthrough (delta)

Each claim was probed against the merged guard (`scripts/worker-command-guard.sh`
fed hook payloads):

- **REQ-A1.12 (assignment carry).** Confirmed: assignment carry across `;` and
  `||` allows; a carried `-delete` still meets `find`'s screen; `cd` across
  `||` or `;`, and an assignment after `||`, defer. Gap found: the guard also
  carries an assignment across a newline (pinned by the suite's
  "tracked: newline-separated" fixture) while the text named only `;` and `||`,
  so read literally a newline-joined successor had to defer. Resolved by
  naming the newline, which ends a command as `;` does (edit E1; operator
  decision).
- **REQ-E1.2 (whitespace values).** Confirmed: a double-quoted use resolves as
  one word; an unquoted use stays unresolved and defers only where the verb
  screens the word (`grep`, which has no operand screen, still allows, as
  REQ-E1.1 provides); an empty value removes an unquoted word.
- **REQ-E1.5 (`ps`).** Confirmed: `ps -A`, `ps -o …`, and `ps aux` allow;
  every form carrying `-e` (`-ef`, `-e`, `-eo`, `-Ae`, `-A -e`) and the BSD
  `e` forms defer. The REQ text, whose membership the implementation carries,
  needs no change.

**Spec edits (consolidated list, this section):**

- **E1.** REQ-A1.12, its amendment note, D-24 (title and decision), the D-19
  amendment note, and the REQ-A1.12 test-spec entry: a plain assignment
  carries across `;`, a newline, and `||`. The test-spec entry adds the
  newline pair, `cd` then a newline, and an assignment after `||`.
  Meaning-class (widens REQ-A1.12's text to the shipped behaviour).

**Mid-walk lens on E1 (inline; the delta is one clause).** Checked the
clauses that read REQ-A1.12's carry rule: REQ-E1.4 keeps `cd` on the `&&`
rule (unchanged, correct); REQ-E1.2's placement rule needs no edit; the
§3.2 "runs unconditionally" definition omitted the newline opener, fixed in
place. No other finding.

Signed off: 2026-10-10

#### 3.4 Design walkthrough (delta)

Ledger for the delta (earlier D-IDs stand as §4, Amendment 1, and
Amendment 2 recorded them):

- **D-24:** confirmed, rationale intact; amended at this kickoff (E1) to name
  the newline.
- **D-25:** confirmed; both rejected alternatives (reproduce bash splitting,
  model per host shell) hold as recorded.
- **D-26:** confirmed; its claim that macOS's `-E` is already outside the
  accepted flags was probed (`ps -E`, `ps -AE` defer), as were the long
  `--everyone` form and the BSD `e` modifier (both defer).
- **D-19:** amendment note carries the newline (E1).

No design decision contradicts a walked requirement.

Signed off: 2026-10-10

#### 3.5 Verification approach (delta)

- **Coverage mix:** unchanged; every delta REQ is `[test]`. Tag tallies:
  derive from `test-spec.md`.
- **Ownership:** CI runs the guard suite (`tests/test-worker-command-guard.sh`)
  through `mise run test` / `mise run check`; no `[manual]` entry changes.
- **Dead paths:** checked each fixture the delta's test-spec entries name
  against the merged suite. Every REQ-E1.2 and REQ-E1.5 fixture is pinned.
  Three REQ-A1.12 fixtures were not: an assignment carried across `||`
  allowing (in the extension's own text), and `cd` then a newline and an
  assignment after `||` deferring (added by E1). The guard already decides
  all three correctly (probed); only the pins are missing. Resolved by
  folding them into Task 7, the next unit to edit the suite and already
  citing REQ-A1.12 (edit E2; operator decision).

**Spec edits (consolidated list, this section):**

- **E2.** Task 7 Deliverables and Done-when: pin the three REQ-A1.12 carry
  fixtures, regression-only. Meaning-class (a task-definition change).

**Mid-walk lens on E2 (inline).** Task 7 already cites REQ-A1.12; no new
dependency or edge; the fixtures are regression-only, so the Done-when's
over-broad-variant rule does not apply to them. No finding.

*(Superseded at §3.8: the sign-off lens pass found the three fixtures did
not discriminate and other pins missing; E2 is reverted from Task 7 and the
sharpened pins move to Task 6.1.)*

Signed off: 2026-10-10

#### 3.6 Task graph (delta)

Reconstructed from the `Dependencies:` lines (render with
`scripts/spec-graph.sh specs/worker-permission-ergonomics`). As walked, no
edge changed. §3.8 then added Task 6.1 on edge 6 → 6.1, and moved Task 7's
dependency from 6 to 6.1, so the serialized guard chain runs through 6.1
before 7. Every other edge, and §2.6's deliberate non-edges, stand. The
renderer's `GRAPHCRIT` line is the authoritative critical path.

Signed off: 2026-10-10

#### 3.7 Risk register (delta)

**Decision-domains gap check:** the merged catalog
(`scripts/resolve-catalog.sh decision-domains`, no overlay additions) walked
against the delta. Touched and decided: auth (the carry widening and the two
narrowings, D-24 to D-26), secrets-config (`ps -e` environment exposure,
D-26), existing-seam-reuse (the shipped name screen D-24 rests on). No touched
domain is undecided. *(The §3.8 lens pass found secrets-config incomplete:
other-process environments via `/proc`, now decided by D-27 and REQ-E1.6.)*

Rows appended (R1 to R15 stand):

| # | Risk | Mitigation / early signal |
|---|---|---|
| R16 | **The spec trailed the code.** Three operator decisions shipped in a task PR before the signed text caught up, so a later task could build on text the guard no longer matches. | This delta kickoff re-aligns text and guard before the next guard task starts. Early signal: an "open spec forks" list in a task PR description. |
| R17 | **Other bash/zsh model gaps remain.** D-25 settles quoting, and Task 6.1 closes the name-screen and `=` gaps the lens pass found; the shared tokenizer still models bash while the Bash tool runs zsh on macOS. The zsh claims could not be run on the review host (no zsh). | Accepted for this delta; obs:8d46a461 stays unconsumed and carries the root fix to `/spec-draft`. Early signal: Task 6.1 fixtures are bash-run; a zsh-host run of the suite is the confirmation. |
| R18 | **Static routes to other-process environments outside the new rule.** The existing static `git diff` rule's `--no-index` reads arbitrary paths, and the `Read` deny depends on Claude Code matching `/proc` paths. | The `git diff` route joins R13's pre-existing static git rules (observation `worker-profile-static-git-write-forms`); Task 12's matcher row pins the `Read` deny. |
| R19 | **Seven read verbs lose their no-hook fallback.** With `cat`, `grep`, `head`, `tail`, `cut`, `diff`, and `jq` out of the static set, a worker whose hook cannot run (no `jq`) prompts on them. | Accepted (operator decision 2026-10-10, D-27). Early signal: prompts on these verbs in an unattended run mean the hook is not running. |

**Open questions:** none outstanding.

**Data hygiene:** no secrets, credentials, internal hostnames, or raw worker
commands recorded.

Signed off: 2026-10-10

#### 3.8 Sign-off lens review and record

**Class:** meaning (operator-confirmed walk; the delta mints D-24 to D-27,
REQ-E1.6, and Task 6.1, and edits REQ text, so the doctrine's
additions-are-meaning rule decides it).

**Scope and path.** Delta-scoped Discovery-Rigor review of the extension
commit plus this kickoff's walk edits (E1, E2), spec lens set per
`artifact-lenses`, fanned out to one read-only reviewer per lens. Declared
scopings, as at Amendment 2: dead verification paths and testability ran as
one reviewer, and a code-class **security** lens was added because the
bundle specifies an allow-only permission mechanism. Rendered-content
safety: `n/a`.

**Validation.** Findings were deduplicated across lenses. Every behavioural
claim was reproduced by feeding hook payloads to the merged guard (the
carry, quoting, empty-word, `ps`, zsh-name, `=`, and `/proc` shapes);
fixture claims were checked by grepping the suite; contract and drift
claims by reading both clauses; source claims against the local `ps(1)`
page and the PR the Sources entry names. The zsh behaviour claims could not
be run (no zsh on the review host): they rest on the zsh manual and on the
guard's own refusal of sibling names from the same `zsh/parameter` table,
and are recorded at that confidence (R17). Adversarial pass: no kept finding
was refuted; one decline stands (the PR description's own slip is not a
spec defect).

**Lens-coverage table (spec set, plus the declared security lens):**

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness and internal consistency | 4 | "Cannot fail" false under zsh (unscreened `zsh/parameter` read-only names); Task 6 text contradicts amended REQ-A1.12/E1.2; "no task-block change" vs E2; REQ-E1.1's "unresolved" does not cover REQ-E1.2's unquoted use. |
| Security (declared, code-class) | 2 | D-26 text left the BSD `e` modifier open (guard already defers); zsh expands a leading `=` in an assignment value, so the modelled literal differs (guard allows). |
| Ambiguity and interpretation forks | 6 | Whitespace scope (tab/newline); partly quoted words; empty-word removal with joined text; "runs unconditionally"; `cd` in force across a later `;`; what "carrying `-e`" covers. |
| Citation and coverage integrity | 6 | Changelog stale (newline, Task 7); D-24 provenance for the newline; amendment notes credit the wrong event; brief §3.2 rules-out and restatement stale; D-26 "other BSDs" uncited. |
| Dead verification paths and testability | 4 | `;`/newline plain-literal carry unpinned; carry fixtures cannot tell carried from dropped; `cd`-newline fixture defers either way; `ps -e` cluster and later-flag forms unpinned. |
| Decision-domain gaps | 2 | secrets-config: `/proc/<pid>/environ` readable though D-26 refuses the same exposure; D-26 covers only the `-e` spelling. |
| Cross-file consistency | 5 | Changelog vs E1/E2; §3.2 vs E2; §3.2 vs E1; Task 6 vs amended REQs; "cannot fail" vs substitution-valued assignments. |
| Documentation and glossary drift | 10 | Stale Changelog, §3.1, §3.2, Task 6 (stale prose); event attribution and missing amendment notes (annotation format); "unresolved" and "state-carrying" (term drift); name screen's readonly coverage undocumented (missing contract). |
| Rendered-content safety | n/a | Not rendered into an executing or markup context. |

**Kickoff-specific checks.**

- **Altitude (triggered bundle).** The altitude record (D-9) is untouched;
  the delta adds mechanism under existing capability. No finding.
- **Ship-gate.** Every out-of-band fix named carries a record: the guard
  gaps are Task 6.1, the static-set and `Read` deny changes are Task 12, the
  zsh tokenizer root fix is obs:8d46a461, the static `git diff` route rides
  R13's observation. No finding.

**Dispositions (every finding dispositioned with the operator):**

- **zsh model gaps** (unscreened read-only names; zsh-expanded `=`) —
  *applied*: new Task 6.1 (depends on 6; Task 7 now depends on 6.1), REQ-E1.2
  and D-24/D-25 text (operator decision).
- **Other-process environments** — *applied*: REQ-E1.6 and D-27 minted; the
  guard deferral rides Task 6.1; the profile denies `Read` on
  `/proc/*/environ` and REQ-G1.1, D-15, and Task 12 drop `cat`, `grep`,
  `head`, `tail`, `cut`, `diff`, `jq` from the static set (operator
  decisions, including widening from four verbs to seven once the
  content-printing rule was written).
- **All remaining findings** — *applied* as one batch (operator decision):
  the stale and attribution text, amendment notes, the pinned readings in
  REQ-A1.12, REQ-E1.1, REQ-E1.2, REQ-E1.5, and D-24 to D-26, Task 6 aligned
  with what shipped, E2 reverted from Task 7 with the sharpened fixtures in
  Task 6.1, and the D-26 source narrowed. Each requirement change carries its
  paired test-spec edit.
- **Declined:** none.

**Post-lens stale-reference sweep.** Swept the bundle and this amendment for
the minted IDs (REQ-E1.6, D-27, Task 6.1), the re-scoped static set, and the
moved Task 7 edge: fixed the stopgap Sources entry, brief §3.1, §3.2, §3.5,
§3.6, and the §3.7 gap-check note; added R18 and R19. The validator's
changed-REQ heuristic then flagged REQ-E1.1's unchanged test entry, paired
by a fixture line. No copied tallies.

**Pre-flip checks.** Lint (`mise run lint:md`) clean over the brief and the
four spec files; validator clean (0 errors, 0 warnings); enumerations in the
delta are decided rules or cite their source (`ps(1)`, `proc(5)`, the PR
named in Sources); the brief cites rather than copies its figures.

Draft→Ready flipped on all four files at this sign-off (reopen cycle);
validator clean at Ready.

Class: meaning
Lens-pass: §9 Amendment 3, 3.8 (delta-scoped fan-out, one reviewer per lens plus the declared security lens; canonical lens-coverage table above; all findings dispositioned — applied)
Anchor: `88f9ec559aff449b9a2809b2e3874a2b509e8eba` — computed as
`scripts/spec-anchor.sh specs/worker-permission-ergonomics`
