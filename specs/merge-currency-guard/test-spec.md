# Merge Currency Guard — Test Spec

**Status:** Ready
**Last reviewed:** 2026-07-22
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: predominantly `[test]`, since both mechanisms are deterministic
shell logic (the `ready-guard` predicate and the `converge-sync-main` fetch +
merge) and straightforwardly fixture-testable, including the negative
assertions (no `git pull`, no rebase, no model/API call, deny stays deny under a
present allow entry). `[manual]` is reserved for the platform-contract
confirmations that depend on the running Claude Code version (whether a
PreToolUse `deny` on the `gh pr ready` Bash surface and the
`mcp__github__update_pull_request` MCP surface actually blocks the tool call).
`[design-level]` covers the checks whose signal is a design judgment rather than
a mechanism's output — the invariant statement (REQ-A1.1) and the
capability-vs-policy boundary (REQ-A1.4).

## REQ-A — The ready-currency invariant

### REQ-A1.1 — Invariant stated once and cited [design-level]

Review confirms the hard-invariant statement ("a PR is flipped ready only on a
`main`-current, mergeable head") exists in the bundle, is cited from the Goal,
and is referenced by the guard (REQ-C) and loop-sync (REQ-B) deliverables. Run
under Task 1 review and kickoff.

### REQ-A1.2 — Enforced by construction, not prose [test]

A fixture asserts the guard (not a skill instruction) is the thing that blocks a
non-conforming flip: with the guard wired, a `BEHIND` payload is denied even
though no skill-prose step ran; removing the guard from the wiring makes the
same payload no longer denied by this bundle's machinery. The presence of the
enforcement in `hooks/hooks.json` is asserted structurally.

### REQ-A1.3 — Flipper-agnostic enforcement [test]

Fixtures assert the same `BEHIND`/`DIRTY` payload is denied whether the
originating command shape is a worker-style `gh pr ready <n>`, a gauntlet-style
invocation (the concrete distinct shape the gauntlet emits, e.g.
`gh pr ready <n> --repo <owner>/<repo>`, not a byte-copy of the worker case —
otherwise the fixture proves nothing beyond the single form), or an MCP
`update_pull_request` transition — the guard branches on the transition and
predicate, never on the identity of the caller.

### REQ-A1.4 — Does not mandate autonomous flipping [design-level]

Review confirms the bundle adds no auto-flip to `/execute-task` and no
who-flips policy: the guard emits `deny`-or-nothing and never itself issues a
ready-flip. Cross-checked against REQ-B1.4 (draft-only PR) and D-9.

## REQ-B — Convergence-loop main-currency

### REQ-B1.1 — In-loop `origin/main` merge each convergence iteration [test]

A fixture drives `converge-sync-main.sh` against a repo whose `origin/main` has
advanced and asserts the branch head afterward includes the advanced commit
(the merge landed); an integration check asserts `/execute-task`'s convergence
loop invokes the script once per `review_sequence` iteration (the invocation
line is present at the top of the iteration and the word count check passes).

### REQ-B1.2 — Fetch + merge, never `pull`, never rebase [test]

Negative assertions over `converge-sync-main.sh`: the script contains no
`git pull` and no `git rebase`/`--rebase`; a positive assertion confirms it uses
`git fetch origin main` followed by `git merge`. A behavioral fixture run under a
repo config with `branch.autosetuprebase=always` confirms the sync does not
produce a rebase (no rewritten history on the branch).

### REQ-B1.3 — Unresolvable conflict halts to `Awaiting input` [test + manual]

`[test]`: a fixture with a conflicting `origin/main` advance asserts
`converge-sync-main.sh` exits non-zero, runs `git merge --abort` so the tree is
left clean (no `MERGE_HEAD`, no conflict markers), and that re-invoking the
script on that clean tree is idempotent (it re-attempts fetch + merge rather
than failing on a lingering merge); the conflict exit reason is distinct from
the fetch-failure reason (REQ-K1.1). **Manual/design:** review confirms
`/execute-task` maps that non-zero exit onto its existing `Awaiting input`
stop-condition protocol with the reason, adding no new halt mechanism.

### REQ-B1.6 — Distinct non-zero-exit causes surfaced [test]

Three fixtures drive `converge-sync-main.sh` into each distinct failure — an
unreachable remote (fetch failure), a conflicting `origin/main` advance
(unresolvable merge conflict), and a pre-existing dirty working tree that blocks
the merge — and assert each exits non-zero with its own reason string, never
collapsing a dirty-tree or fetch failure into a misreported "merge conflict"
(REQ-K1.1).

### REQ-B1.4 — `/execute-task` still opens only a draft PR [test]

A structural assertion over `skills/execute-task/SKILL.md` confirms the
draft-only / never-ready contract is retained and that the sync edit did not
introduce a `gh pr ready` (or MCP ready) call into the skill body.

### REQ-B1.5 — Sync offloaded to a script; instruction budget preserved [test]

`scripts/check-instructions.sh` (the instruction-headroom guard) run over
`skills/execute-task/SKILL.md` passes: the body stays under its ceiling because
the sync is a single-line script call rather than inline prose.

## REQ-C — The ready-guard

### REQ-C1.1 — Predicate: `mergeStateStatus ∈ {CLEAN, UNSTABLE}` AND `mergeable == MERGEABLE` [test]

A fixture matrix over `ready-guard.sh`, each stubbing a `gh pr view` JSON
response: `CLEAN` + `MERGEABLE` → defer (empty output, exit 0); `UNSTABLE` +
`MERGEABLE` → defer (a current, conflict-free PR with only a non-required check
pending is allowed); `BEHIND` → deny; `DIRTY` → deny; `BLOCKED` → deny;
`mergeable` `CONFLICTING` → deny; `mergeStateStatus`/`mergeable` `UNKNOWN` → deny
(after a bounded re-query) with a wait-and-retry reason, never a fetch remedy. A
negative assertion confirms the guard reads no local git ref/object and runs no
`git fetch` (grep-level and behavioral: the decision is identical when the local
checkout's refs are stale or the PR's base branch is a non-`main` branch and
when the head OID is a cross-fork commit absent locally). Each asserts the exact
decision and, for denies, a non-empty reason.

### REQ-C1.2 — Deny-emitting, deterministic, no LLM [test]

Assertions: the guard emits a `permissionDecision: deny` (or nothing), never
`allow`/`ask`; a negative assertion confirms no model/API invocation in the
decision path (REQ-D1.4); repeated runs on identical input are byte-identical
(determinism). The no-LLM stub harness is asserted **reachable** — a positive
control proves the guard's decision path actually traverses the stubbed call
site, so the "no outbound call" assertion cannot pass vacuously (per the
`test-tower-command-guard.sh` no-LLM-stub-reachability precedent).

### REQ-C1.3 — Fail closed on any doubt [test]

Fixtures: `gh` absent → deny; `gh` errors (non-zero) → deny;
`mergeStateStatus`/`mergeable` `UNKNOWN` → deny (and a fixture asserts the guard
re-queries at least once before denying, and that the reason is wait-and-retry,
not a fetch); `jq` absent → deny; empty/malformed payload → deny. Each asserts a
deny with an actionable reason (REQ-K1.1), never a silent allow/defer. A fixture
stubbing a slow/hung `gh pr view` asserts the guard's bounded timeout fires and
resolves to deny (a hang never becomes a no-output fail-open); a fixture asserts
a non-`gh pr ready` Bash command returns with no network call attempted (the
fast path precedes any query).

### REQ-C1.4 — Deny precedence over the worker allow, pinned by outcome [test]

See REQ-D1.2: with `config/worker-settings.json`'s `gh pr ready` allow entry
present, a non-conforming `gh pr ready` payload still resolves to deny. The test
asserts the OUTCOME, not Claude Code's allow-vs-deny ordering (`obs:4dda9fe1`).

### REQ-C1.5 — Intercepted payload treated as inert data [test]

An adversarial fixture whose `gh pr ready` argument embeds shell metacharacters
/ command-substitution asserts the guard never executes, evals, or re-expands
it — a sentinel side effect (a marker file the hostile payload would create if
executed) is absent after the guard runs. Because the guard runs no local git
command against server-supplied fields (the predicate is entirely
`gh pr view`-JSON comparison), there is no OID/ref interpolation sink; a fixture
asserts a `gh pr view` response carrying a metacharacter-laden field value is
compared as inert JSON data (via `jq`), never executed — the sentinel is absent.

### REQ-C1.10 — `gh api graphql` ready mutation covered; indirect forms residual [test]

`[test]`: a fixture asserts the Bash matcher denies a non-conforming
`gh api graphql -f query='mutation{markPullRequestReadyForReview(...)}'`
invocation, applying the same predicate as `gh pr ready`. A documentation-level
assertion records that compound/indirect forms (`sh -c '…'`, `env gh …`, raw
`curl`) are the accepted D-7-class residual (asserted present as a stated
residual, not silently uncovered).

### REQ-C1.6 — Both surfaces covered (Bash + MCP) [test + manual]

`[test]`: the Bash matcher denies a non-conforming `gh pr ready`; the MCP
matcher denies a non-conforming `mcp__github__update_pull_request` draft→ready
transition and defers a non-transitioning `update_pull_request` call.
**Manual:** against the running Claude Code version, confirm a PreToolUse `deny`
on each surface actually blocks the respective tool call (the version-sensitive
platform-contract confirmation).

### REQ-C1.7 — Global wiring in `hooks/hooks.json` [test]

A structural assertion confirms the PreToolUse Bash and MCP matchers for
`ready-guard.sh` are present in `hooks/hooks.json` and reference the script via
`${CLAUDE_PLUGIN_ROOT}` (marketplace-install-safe), and that the guard is not
gated behind a specific settings profile.

### REQ-C1.8 — `--undo` and non-transitions never blocked [test]

Fixtures: `gh pr ready --undo`, `gh pr ready <pr> --undo`, and a non-draft-flip
`update_pull_request` each → defer (empty output, exit 0), regardless of
currency/mergeability state.

### REQ-C1.9 — Target-PR selector resolution and injection safety [test]

Fixtures assert the guard resolves and validates the target PR from the
intercepted call's own selector and never lets a hostile selector redirect or
inject: (a) a Bash `gh pr ready 42 -R owner/other` and an MCP payload with an
explicit `owner`/`repo`/`pullNumber` are each queried against exactly that
target, not the hook's cwd PR; (b) an MCP `pullNumber` or a Bash PR argument
carrying an option/metacharacter payload (e.g. `1 --repo attacker/clean`,
`$(touch sentinel)`) is rejected by grammar validation before any `gh pr view`
runs — the guard DENIES and the sentinel side effect is absent — proving the
selector reaches `gh` as inert, separate argv, never a command string; (c) a
bare `gh pr ready` resolves to the current branch's PR. An
invalid/ambiguous selector → deny.

## REQ-D — Verification

### REQ-D1.1 — Full adversarial matrix, both surfaces [test]

The suite in Task 4 enumerates every REQ-C1.1 / REQ-C1.3 / REQ-C1.8 branch on
both the Bash and MCP surfaces; CI runs it green. Completeness is **mechanically
enforced**, not self-asserted: the suite declares an explicit expected-cell
manifest (the cartesian product of decision states × surfaces × the never-gated
cases) and a meta-check fails if any manifest cell has no corresponding fixture,
so a silently-absent cell (e.g. `UNKNOWN × MCP`) turns the suite red rather than
passing green.

### REQ-D1.2 — Deny-over-allow outcome test [test]

A test loads (or simulates) the `config/worker-settings.json` `gh pr ready`
allow entry and asserts a non-conforming payload is still denied — the outcome
pin for REQ-C1.4 / D-6. Pattern: script-level outcome plus structural
allow-entry assertion, per the `test-tower-command-guard.sh` deny-precedence
OUTCOME block (the `fleet-hardening` REQ-C1.3 precedent); the live "a hook
deny actually blocks" half of the property rides REQ-C1.6's `[manual]`
platform sweep, not this test.

### REQ-D1.3 — Sync-script tests [test]

Clean-merge success, conflict non-zero exit, fetch-failure non-zero exit with a
clear reason (unreachable remote fixture), and no-`pull`/no-rebase negative
assertions over `converge-sync-main.sh`, green in CI.

### REQ-D1.4 — No-LLM negative assertions [test]

Both `ready-guard.sh` and `converge-sync-main.sh` are asserted to contain no
model/API call in their decision paths (grep-level and behavioral).

## REQ-K — Graceful degradation and data hygiene

### REQ-K1.1 — Clear denial / halt messages [test]

Every guard deny fixture asserts a non-empty, actionable reason naming what
could not be confirmed; the sync conflict fixture asserts a message naming the
conflict and the halt. No opaque failure.

### REQ-K1.2 — Data hygiene [design-level]

Review + `mise run check` confirm no secrets, credentials, internal hostnames,
or sensitive operational detail in the scripts, fixtures, or spec prose.

### REQ-K1.3 — Echo-safety on emitted untrusted content [test]

A fixture whose PR head/base branch name (or `gh`/`git` stderr) carries an
embedded terminal escape / non-printable byte asserts the guard's denial message
emits the sanitized form (non-printables stripped via
`scripts/echo-safety.sh`), so no control sequence reaches the operator's
terminal or the audit log.
