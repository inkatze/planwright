# Worker Permission Ergonomics — Tasks

**Status:** Draft
**Last reviewed:** 2026-10-10
**Format-version:** 2
**Execution:** derived — see the status render

Tasks 1 to 3 delivered the hook, its wiring, and literal-path invocation.
Tasks 4 onward are the 2026-10-05 extension. Task 4 closes a live false-allow
and sits on the critical path; the real-prompt corpus (Task 5) lands before
the guard tasks it verifies, so each of them turns its own corpus rows from
pending to enforced. The tasks that edit the worker guard (6, 7, 9, 10, 11)
form one deliberate chain so no two of them change that script at once; do
not parallelize them. The dependency graph is the `Dependencies:` fields
below; `scripts/spec-graph.sh` renders it on demand.

## Tasks

### Task 1 — Implement and test the auto-approve hook

- **Deliverables:** `scripts/worker-command-guard.sh` — a portable POSIX/bash
  `PreToolUse` hook that reads the hook payload from stdin, extracts
  `tool_name` and `tool_input.command` via `jq` (deferring all when `jq` is
  absent), and returns `permissionDecision: allow` only for known-safe Bash
  command shapes, deferring everything else. Ports the validated prototype's
  analysis (quote-aware segment splitter, every-segment-safe rule, verb
  classifier, `fish -c` recursion with bounded depth, redirect handling) into
  pure shell, and implements the kickoff-hardened analysis: per-invocation
  safe-flag/arg guards with unknown-flag-defers (REQ-A1.8), grammar-conservative
  deferral of env-assignment prefixes / path-prefixed verbs / fish bare-paren /
  subshell-grouping / multi-char redirect tokenization (REQ-A1.9), script/test/
  bats path canonicalization + containment (REQ-A1.10), and the fail-closed
  emission contract (REQ-B1.7). Plus `tests/test-worker-command-guard.sh`, the
  adversarial suite.
- **Done when:** the hook returns allow/defer per the REQ-A1.5 known-safe set
  and REQ-A1.6 defer set, honoring the REQ-A1.8 safe-invocation rule,
  REQ-A1.9 grammar-conservative deferral, REQ-A1.10 path containment, and the
  REQ-B1.7 fail-closed emission contract (defer path emits empty stdout + exit 0,
  never exit 2, never a partial allow, never hangs); `jq`-absent, non-Bash,
  malformed-stdin, empty/non-string-command, and deep-`fish -c`-nesting inputs
  all defer; the adversarial suite (≥30 cases including the kickoff-surfaced
  vectors and the deny-collision case, test-first) is green with ZERO
  false-allows and asserts a deny-listed command is never auto-approved;
  `shellcheck` and `shfmt -d` are clean; the suite runs under `mise run test`.
- **Dependencies:** none
- **Citations:** D-2, D-3, D-4 · REQ-A1.1, REQ-A1.2, REQ-A1.4, REQ-A1.5,
  REQ-A1.6, REQ-A1.7, REQ-A1.8, REQ-A1.9, REQ-A1.10, REQ-B1.1, REQ-B1.2,
  REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-B1.7
- **Estimated effort:** 3–4 days (grew from 2 at kickoff: the hardened analysis
  in REQ-A1.8/A1.9/A1.10/B1.7)

### Task 2 — Wire the hook into the worker-settings profile

- **Deliverables:** `config/worker-settings.json` updated with a `PreToolUse`
  (Bash) hook entry referencing `scripts/worker-command-guard.sh` via
  `${CLAUDE_PLUGIN_ROOT}`, keeping `defaultMode: default` and the `deny` block
  byte-for-byte unchanged; the `_about` field updated to document the hook (its
  no-LLM, allow-only, deny-precedence properties), the human-sign-off posture,
  and the optional adopter-specific literal-path allow entry. The `_about` text
  SHALL also warn adopters not to merge the auto-approve hook stanza into a
  general (tower/human) `settings.json`, since worker-scoping is enforced only by
  where the hook is wired (REQ-C1.2; brief §7 R7). Task 2 is the sole editor of
  `config/worker-settings.json` `_about` (Task 3 does not touch it).
- **Done when:** the fragment carries the hook and validates as Claude Code
  settings JSON (`lint:json` / schema check clean); the `deny` block is
  unchanged from the pre-edit version; `_about` documents the hook and posture;
  a hook-JSON-shape assertion in the test suite confirms the hook is present in
  `worker-settings.json` and absent from the plugin-global `hooks/hooks.json`.
- **Dependencies:** 1
- **Citations:** D-5, D-6 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-A1.3
- **Estimated effort:** half day

### Task 3 — Resolve plugin scripts by literal path in the dispatching skills

- **Deliverables:** `/execute-task`, `/orchestrate`, and `/spec-kickoff` updated
  to resolve the plugin/planwright root once per invocation and invoke plugin
  scripts by resolved literal absolute path rather than through an unexpanded
  shell variable; the optional install-location-specific literal-path allow
  entry documented for adopters in the options/overlay docs. (The
  `worker-settings.json` `_about` mention of the allow entry is owned by Task 2,
  which owns the `_about` rewrite; Task 3 does not edit `worker-settings.json`.)
- **Done when:** the three skills' plugin-script invocations use a resolved
  literal path (no `"$VAR/scripts/x.sh"` invocation shape remains in the
  changed call sites); the change is documented; existing skill behavior is
  otherwise unchanged and the repo's `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-7 · REQ-D1.1
- **Estimated effort:** 1 day

### Task 4 — Close the unexpanded-operand and `-v` false-allows in both guards

- **Deliverables:** `scripts/worker-command-guard.sh` and
  `scripts/tower-command-guard.sh` defer any word carrying an unresolved or
  opaque `$` expansion wherever the verb's approval depends on that word
  (screened operands, verb positions, containment-checked paths), model a
  `for` variable by re-verifying the loop body once per plain-literal head
  word up to a stated bound (the whole loop defers past it), and defer
  `test -v`, `[ -v`, and `printf -v` in every form; adversarial fixtures in
  both guards' suites for the recorded bypasses (`for d in "<flags>"; do
  find . $d; done`, the `$_` form, a non-literal loop head reaching
  `cat`/`sed`/`awk` operands such as `for d in $X; do cat $d; done`, a glob in
  a verb path such as `bash scripts/s*.sh`, a symlinked cache root,
  `test -v 'a[$(…)]'`, `[ -v 'a[$(…)]' ]`, `printf -v 'a[$(…)]' x`, and
  `printf -v PATH …`), plus regression-only fixtures for the shapes the
  guards already defer (a loop variable reaching `bash` or a containment
  check).
- **Done when:** every listed bypass defers in both guards, each bypass
  fixture first shown allowing against the pre-change guard (the
  regression-only fixtures are exempt, since they already defer); a
  plain-literal loop head behaves as its substituted literal form
  (`for f in a b; do grep -n x $f; done` still approves); both suites and
  `shellcheck`/`shfmt -d` are clean under `mise run test`.
- **Dependencies:** none
- **Citations:** D-11 · REQ-E1.1, REQ-A1.13, REQ-A1.14
- **Estimated effort:** 1–2 days

### Task 5 — Real-prompt regression corpus and harness

- **Deliverables:** a sanitized corpus file drawn from real worker prompts
  (command shapes only: no hostnames, user paths, tokens, or repository
  names), each row tagged with its class and its expected verdict under each
  policy value (the empty list, `own-branch`, `scratch`, and
  `own-branch scratch`); the existing `tests/fixtures/worker-guard-corpus.tsv`
  rows migrated into it (or retired with the reason recorded) so one corpus
  remains and runs in CI; a harness in the guard's test suite that runs every
  row through the hook with the policy and a session record injected,
  treating rows of a class whose task has not landed as pending and
  enforcing a class once it is marked shipped, so a shipped row that misses
  its expected verdict fails; floor rows and uncovered rows enforced from the
  start.
- **Done when:** the corpus holds at least one row for every shape REQ-E
  and REQ-F name, every floor act REQ-F1.5 names, and every uncovered class
  REQ-A1.13 names; floor rows (merge, ready flip, force-push, amend, rebase,
  any push, writes outside worktree and scratch, writes to REQ-F1.6 paths,
  `gh` writes) defer under every policy value, uncovered rows (interpreters,
  self-written script execution) defer, a secret-scan and the
  purged-identifier guard pass over the corpus file, and the harness runs
  under `mise run test`.
- **Dependencies:** 4
- **Citations:** D-20 · REQ-H1.3, REQ-A1.11
- **Estimated effort:** 1–2 days

### Task 6 — Run-order analysis: cd, plain assignments, transparent prefixes, timing verbs

- **Deliverables:** the worker guard walks segments in run order carrying the
  working directory and plain-literal variable values across `&&` only, from
  segments that run unconditionally in the current shell; approves a
  `cd <literal>` (never through `CDPATH`) that canonicalizes to an existing
  directory inside the session's own worktree and analyses later segments
  against it; resolves `NAME=<plain literal>` for any literal, under the
  existing `assign_name_ok` screen and placement rule, with unquoted word
  splitting reproduced; makes a variable opaque after any other
  variable-writing form; treats `time` (bare or `-p`) and flagless
  `timeout <duration>` as transparent prefixes; adds the wait and inspection
  verbs of REQ-E1.5 under the safe-invocation rule; fixtures for each,
  including `cd` out of the worktree, `cd` with a non-literal operand,
  `cd missing; rm -r ../x`, `cd sub | …`, `x=a | grep $x`, `IFS=-; …`,
  `read f` and `printf -v f` before a use of `$f`, an assignment whose value
  carries a glob or quote, `timeout -k 5 30 …`, and
  `git ls-remote --upload-pack=… origin`, all deferring.
- **Done when:** the corpus rows of these classes are enforced and pass;
  REQ-A1.12's run-order and `&&` clauses and REQ-A1.13's prefix clause are
  exercised by fixtures; the fleet guide and the worker launch text state
  that a worker issues `git` without a `cd`; the suite and lints pass.
- **Dependencies:** 5
- **Citations:** D-19 · REQ-A1.12, REQ-A1.13, REQ-E1.2, REQ-E1.4, REQ-E1.5
- **Estimated effort:** 2 days

### Task 7 — Admit argument-independent command substitution

- **Deliverables:** the worker guard admits `$(…)` under REQ-E1.3: inner text a
  single simple command or pipeline passing the read-only analysis; no
  nesting, backtick, or parenthesis inside a quote; output (directly or via a
  variable assigned from it, tracked as opaque) reaching only operands of the
  enumerated argument-independent verbs (no `-v` forms, no `printf` format)
  or such an assignment; an adversarial fixture set for unquoted word
  splitting, glob expansion of the output, a tainted variable reaching a
  screened verb, nesting, quoting tricks, a substitution reaching a `-v`
  operand or a `printf` format, and a substitution in a verb position.
- **Done when:** the corpus's substitution rows that meet the rule approve
  and every other substitution row defers; each adversarial fixture that
  depends on the argument-independence check is first shown allowing against
  an over-broad variant (admitting `$(…)` wherever its inner text passes the
  read-only analysis) and deferring against the real one, while the nesting
  and backtick fixtures, which defer by separate code, are regression-only;
  the suite and lints pass.
- **Dependencies:** 6
- **Citations:** D-11 · REQ-A1.12, REQ-E1.3
- **Estimated effort:** 2–3 days

### Task 8 — Plugin scripts resolve the values workers fetched by substitution

- **Deliverables:** `scripts/step-record.sh` defaults `--head` to the current
  `HEAD` when it is omitted; a sweep of the plugin scripts a worker or
  orchestrator calls with an argument fed by substitution in the replay, each
  given the same self-resolving default; their tests.
- **Done when:** `step-record.sh write` without `--head` records the current
  `HEAD`, the existing explicit form is unchanged, each swept script has a
  test for its default, and `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-11 · REQ-H1.1
- **Estimated effort:** half day

### Task 9 — The session record, the policy, the floor, and the own-branch arm

- **Deliverables:** the `worker_self_approval` knob in `config/defaults.yml`
  (default empty: read-only only) documented in the options reference and
  resolved through the overlay layers last-value-wins; the worker launchers
  writing the session record (policy, unit branch, worktree root, PR base,
  `worker_base_merge` value) outside the worktree; the worker guard reading
  its inputs only from that record, the declared command steps, and the
  profile's `Bash(…)` deny rules, with per-arm fallback when a field is
  missing; a floor check evaluated before any arm, refusing deny-matched
  commands in every category (declared steps included); the `own-branch` arm
  per REQ-F1.3 (flag, `mv`-source, hard-link, link-creation, and `sed` script
  rules; REQ-F1.6 exclusions), composed with `worker_base_merge` and leaving
  `policy-guard.sh` in place; fixtures for each arm member, the floor under
  every value, a missing record field, `git switch` to another branch,
  `cp -l`, `mv <outside> <inside>`, `sed -i '1e …'`, writes to each REQ-F1.6
  path, and the deny-outcome assertion.
- **Done when:** the corpus's own-branch rows approve only under a policy
  containing `own-branch`; floor rows defer under every value; a malformed,
  unknown-member, or unreadable knob behaves as the empty list; for every
  `Bash(…)` deny rule a generated matching command, plus a curated collision
  wherever the rule's verb is otherwise approvable, never receives `allow`;
  the suite and lints pass.
- **Dependencies:** 5, 7
- **Citations:** D-12, D-13, D-22, D-23 · REQ-F1.1, REQ-F1.2, REQ-F1.3,
  REQ-F1.5, REQ-F1.6, REQ-G1.8, REQ-B1.8, REQ-A1.11
- **Estimated effort:** 3–4 days

### Task 10 — The per-worker scratch root and the scratch arm

- **Deliverables:** the worker launchers create a per-worker scratch root
  owned by the worker, export it as `TMPDIR`, and add it to the session
  record; the root survives `recover` and is removed only by the final stop
  or reap; the guard's `scratch` arm approves writes whose every target
  canonicalizes inside that root (a literal `$TMPDIR` resolving to it) and
  never approves executing or sourcing from it; launcher and guard tests.
- **Done when:** a launched worker's `TMPDIR` is its own scratch root and a
  recovered worker keeps it; the corpus's scratch-write rows approve only
  under a policy containing `scratch`; writes to `/tmp` outside the root, a
  symlink escaping it, and `bash <root>/x.sh` defer; the suite and lints
  pass.
- **Dependencies:** 9
- **Citations:** D-14 · REQ-F1.4, REQ-G1.2
- **Estimated effort:** 1–2 days

### Task 11 — The audit log of allow decisions

- **Deliverables:** the launcher records the audit-log home in the session
  record; the worker guard appends one line per emitted `allow`, with a
  single append write, to a per-session append-only log there (time,
  session, approving arm or category, command hash, never the command text);
  the launcher or final stop prunes past the retention bound, which the
  options reference states; the write arms are off when the record names no
  usable log home; the options and fleet docs describe it.
- **Done when:** an approved fixture produces exactly one log line carrying no
  command text; an unwritable log leaves the `allow` intact and well-formed;
  a record with no log home yields no `own-branch` or `scratch` approval; the
  pruning step enforces the bound in a test; the suite and lints pass.
- **Dependencies:** 9, 10
- **Citations:** D-21 · REQ-H1.4, REQ-B1.8
- **Estimated effort:** 1 day

### Task 12 — Profile: static allow set, `-u` push, path denies, `_about`, matcher model

- **Deliverables:** `config/worker-settings.json` gains the REQ-G1.1 static
  allow rules, with the read-only `git` subcommands enumerated here and each
  checked against the no-write-or-exec-form rule, and `git push -u origin`;
  its `deny` block gains only the `Write`/`Edit` path rules for the REQ-F1.6
  paths, the session record location, and the overlay config files
  (REQ-G1.8), after checking which of those paths Claude Code already
  protects itself; `_about` rewritten to describe every approval category,
  each policy arm, and the floor; the permission-matcher model doc, its
  re-implementation, and the fixture table updated to the documented
  nested-command behaviour, with a row per nesting form; the matcher test
  gains an allow-rule coverage pass mirroring its deny-rule pass.
- **Done when:** the permission-matcher test passes and fails on an allow
  rule with no fixture row; every nesting form has a row; `awk`, `find`,
  `xargs`, `sed`, `sort`, `uniq`, and the diff-family, `grep`, and
  `cat-file` `git` subcommands have no new allow rule; the `deny` block
  differs from its pre-change content only by the added path rules; the
  settings-fragment and hook-contract checks pass.
- **Dependencies:** 9, 10
- **Citations:** D-10, D-15, D-22, D-23 · REQ-G1.1, REQ-G1.6, REQ-G1.7,
  REQ-H1.2, REQ-F1.6, REQ-G1.8
- **Estimated effort:** 1–2 days

### Task 13 — Relaunch under the current profile

- **Deliverables:** a stream-json supervisor `relaunch` verb for a live
  worker: a graceful `stop` then the existing `recover`, refused while the
  worker holds a lock the stop would release, re-resolving the session record
  from current config and keeping the scratch root; the fleet guide's
  statement that permissions and the session record load at session start and
  reach a running worker only by relaunch.
- **Done when:** a test shows the relaunch passes the installed profile's
  path and the persisted session id, refuses a worker with no persisted
  session or a held lock, rewrites the session record, and keeps the scratch
  root; the guide text is present; `mise run check` passes.
- **Dependencies:** 10
- **Citations:** D-16 · REQ-G1.3, REQ-G1.2
- **Estimated effort:** 1 day

### Task 14 — State what unattended means in doctrine

- **Deliverables:** the inter-orchestrator-coordination doctrine's
  permission-prompt section states that unattended mode parks every prompt
  outside the configured self-approval policy and outside any
  operator-written standing decision for the operator, that no tower or
  supervisor answers one on its judgment, and that the policy is the only
  self-approval surface; the doctrine index row updated.
- **Done when:** the doctrine text is present and agrees with the section's
  standing-decision clause, the instruction-budget and doctrine-index checks
  pass, and `mise run check` passes.
- **Dependencies:** 9
- **Citations:** D-9, D-12 · REQ-G1.4, REQ-F1.2
- **Estimated effort:** half day

### Task 15 — Meta-tower direct dispatch

- **Deliverables:** a plugin script carrying the meta step's mechanical part
  (per-spec lock, freshness gate, dispatch record, worker launch) that
  `/orchestrate --meta`/`--fleet` calls in the meta-tower's own session; the
  orchestration-modes doctrine's meta step amended to call it, with its
  `doctrine/README.md` index row updated; tests over the script.
- **Done when:** a test shows the script launches a worker and no
  subordinate tower session, takes and releases the per-spec lock around the
  step, and is excluded by a concurrent single-spec tower's lock; the
  instruction-budget and doctrine-index checks pass; `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-17 · REQ-G1.5
- **Estimated effort:** 2–3 days

## Awaiting input

(none yet)

## Deferred

- **Standing-decision matching over split segments.** tower-comms' standing
  decisions match a literal prefix of the whole command; matching them per
  split segment is deferred, since a standing-decision settle today closes the
  queue item without answering the worker's live prompt. Confidence: high.
  **Gate:** the tower-comms settle route delivers the recorded answer to the
  worker's live permission prompt (obs:fd1824a4 resolved). (Free-text: the
  condition is another bundle's fix landing, which no `GATE(when:)` atom
  names.) Citations: D-18; tower-comms REQ-E1.5.

## Out of scope

- **`auto` / `bypassPermissions` permission modes.** Rejected by fleet-autonomy
  D-19; this hook is the LLM-free path to the same no-flood goal. Citations:
  D-2; fleet-autonomy REQ-E1.4/D-19.
- **`fleet-state-home-unresolved`.** fleet-throttle / tower-marker failing to
  resolve a cross-spec fleet home under a marketplace install — a
  fleet-governance robustness gap orthogonal to worker permissions. Left to
  fleet-autonomy or its own bundle; the observation is left unconsumed.
  Citations: obs:b085ac53 (unconsumed).
- **Non-Bash tool coverage.** The hook considers only the Bash tool; every
  other tool defers to the normal flow. Citations: REQ-A1.7.
- **Tower-side answering of worker prompts.** No tower, supervisor, or relay
  answers a worker's permission prompt on the strength of the policy or its
  own judgment. Citations: D-12; REQ-F1.2.
- **Executing self-written scripts.** A script the worker wrote outside the
  repository's tracked `scripts/` and `tests/` (scratch included) is never
  approved: it is arbitrary execution. Running an edited repo script or test
  stays under the trusted-checkout residual. Citations: D-14, D-22; REQ-F1.4,
  REQ-F1.6.
- **Claude Code's own safety gates.** The `cd`-before-`git` gate and the
  sensitive-path prompt are outside any hook's reach. Citations: D-19.
