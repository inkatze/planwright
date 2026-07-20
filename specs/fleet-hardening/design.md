# Fleet Hardening — Design

**Status:** Ready
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: **N** — new to this bundle. **C, `<spec> D-<n>`** — carried: this bundle reuses
an existing decision from the named sibling spec rather than inventing a parallel one.

The design leads with the principle: **prefer a deterministic, event-driven signal over a
heuristic, screen-scraped, timed, or stochastic one wherever the harness exposes one.** The
decisions below lead with the framing doctrine record (D-1), then rank the mechanisms by the
strength of the win, strongest first — the attention hooks (D-2) close the gap that already cost
seven hours and rank first among the mechanisms; D-1 is the altitude record that frames them.

## Decision log

### D-1: Deliverable altitude — mechanism-primary with one carried doctrine statement (N)

**Decision:** This bundle is primarily a set of concrete mechanisms (D-2 through D-9), plus exactly
one doctrine statement (REQ-E1.1): that fleet control-plane signals are resolved by deterministic,
event-driven means in preference to heuristic / polling / stochastic ones wherever the harness
exposes a deterministic signal. The doctrine statement is the altitude decision this bundle records
per the autopilot-reflex altitude gate, cited from the Goal.

**Alternatives considered:**
- Pure mechanism, no doctrine statement. Rejected because: the deterministic-over-heuristic
  principle recurs across every finding in this bundle and generalizes beyond this repo — the same
  shape as `fleet-autonomy`'s own D-10 ("prefer an official disable switch over a detection
  heuristic") and D-18 (no-LLM-daemon), which landed doctrine statements alongside their mechanisms.
  Leaving the principle implicit is how the next fragile-heuristic mechanism gets built without
  anyone noticing it should have been deterministic.
- Doctrine-only reframe (elevate the principle, defer the mechanisms). Rejected because: the
  seven-hour incident and the source audit demand concrete mechanisms now, not a principle awaiting
  future instantiation. The altitude here is genuinely mixed, and the honest call is
  mechanism-primary with a single carried statement, not doctrine-primary.

**Chosen because:** the altitude trigger fired (a seed framing this as a first-class control-plane
concern, and a mechanism — attention detection — that had acquired rules reading like doctrine), so
the call is recorded rather than retrofitted; and the honest weight is one doctrine line carried on
top of eight mechanisms (D-2 through D-9), scoped per proportionality to the risk this bundle actually exhibited.

### D-2: Fork-park attention via the native `Notification` hook, pushed to the store the tower already watches (N)

**Decision:** A worker pushes an `awaiting-human` attention record (reason plus timestamp) into
`fleet-autonomy`'s existing attention store the instant it parks for human input, via a native
Claude Code `Notification` hook. The tower learns of it by watching the store as an event, never by
capturing and grep-parsing the worker's pane. This closes the specific gap `fleet-autonomy` D-1
left: D-1 wired `Stop`, `PermissionRequest`, `PostToolUse`, `SessionEnd`, and `StopFailure`, but a
worker parked at an `AskUserQuestion` sign-off fork has neither stopped (it is waiting) nor raised a
tool-permission prompt — it fires `Notification` ("Claude is waiting for your input"), which nothing
was wired to, so the store row stayed `working` and aged into `hung`, and the operator fell back to
the manual pane-grep that false-negatived for seven hours.

**Alternatives considered:**
- Rely on the `Stop` hook alone. Rejected because: a fork-parked worker has not ended its turn — it
  is mid-turn awaiting input. `Stop` fires on turn-end-idle, not on an in-turn idle-wait, so it
  never fires for the exact state that cost seven hours.
- Infer `awaiting-human` from heartbeat age (the existing `hung` timing heuristic). Rejected
  because: it conflates a worker waiting on a human with a genuinely hung worker, and it carries the
  default 900-second latency — a timing heuristic, precisely the class this bundle replaces.
- Keep the operator's footer-grep pane detector as the primary signal. Rejected because: it is the
  mechanism that cost seven hours; screen-scraping over a scrollback that contains busy words
  false-matches.

**Chosen because:** the `Notification` event is Claude Code's own authoritative "needs attention"
signal; pushing it to the store `fleet-autonomy` already renders and queues from is zero-latency,
involves no pane text, and reuses the existing classifier surface (REQ-E1.2). Research trigger
(platform-contract, version-sensitive): confirm against the running Claude Code `hooks` documentation
that a `Notification` hook fires for the fork-park / idle-wait state, and pin the confirmed event in
the kickoff. Where a given fork type is found not to raise `Notification`, D-3's fallback detector is
the reconcile backstop — the push-first / reconcile pattern `fleet-autonomy` D-1 already establishes.

Three execution-time robustness properties ride Task 2 (recorded in its Done-when and the risk
register): the hook **gates on the `Notification` payload reason** so permission-park / idle-nudge
notifications do not push false `awaiting-human` records; the tower's event-watch carries a
**liveness check plus a periodic full-store reconcile sweep** so a dead watch degrades to
poll-latency rather than the silent blindness this decision exists to end (and so a push written
before the watch is established is not missed); and the `awaiting-human` row gets an **exit edge**
(cleared or superseded on resume) so an answered fork does not leave a stuck row that, because the
push overrides heartbeat, no fresh heartbeat could clear.

### D-3: One codified fallback pane-state detector — footer-only, positive-anchor, debounced (N)

**Decision:** For backends that cannot register hooks — or where a registered hook has not produced
a push within a bounded reconcile interval (a registered-but-non-firing fork type) — the fleet ships
a single fallback pane-state detector: it reads only the bounded footer region (not the full
scrollback), requires a positive at-prompt anchor AND the absence of every busy marker
(`esc to interrupt`, background-agent `Waiting for` / `to manage`, spinner words), and debounces
across at least two consecutive frames. It is the reconcile backstop to D-2's push, never the primary
path where a fresh hook push exists. This gating closure matters: without it, a hook-capable backend
whose specific fork type does not raise `Notification` would be covered by neither the push nor the
detector — re-opening the exact invisible-fork-park this bundle exists to kill.

**Alternatives considered:**
- Let each tower re-derive its own pane heuristic (the status quo). Rejected because: it is
  uncodified tower judgment, so every tower re-invents it and each re-invention can regress — the
  2026-07-18 background-agent false-positive (a main-idle worker with a busy background subagent read
  as idle) came from an absence-of-busy check with no positive anchor.
- Scan the whole captured pane. Rejected because: scrollback text ("Waiting for N background agent",
  spinner words) false-matches a busy detector over the full buffer — the exact 2026-07-19 mechanism.

**Chosen because:** a footer-only, positive-anchor, debounced detector, codified once as a
planwright script, removes the two failure modes that actually fired (scrollback false-match and
background-agent false-idle) and stops towers re-deriving a fragile heuristic. It stays strictly a
backstop, so the deterministic push (D-2) remains the signal wherever a hook can register.

### D-4: Structured worker-to-tower decision channel, answered by label (N)

**Decision:** A worker parked at a multi-option fork writes the pending decision and its full option
set — each option's label and the worker's recommendation — to a structured record on
`fleet-autonomy`'s attention store (extending its existing `decide` / `awaiting-input` path). The
tower or human reads that record and answers by option *label*; the answer is delivered to the
worker through the existing attributed buffer-paste / structured-marker path. No one selects an
option by counting `send-keys` down-arrows against a captured menu.

**Alternatives considered:**
- Keep verify-before-submit menu-scraping (send down-arrows, capture-pane, verify the highlighted
  line, then Enter). Rejected because: option order is not stable — on 2026-07-19 a worker put
  `Skip` as option 1 and `Apply` as option 2, the reverse of its sibling prompts, so a blind
  Down-Down or default-Enter would have selected the wrong disposition; and the verify round-trips
  suffer partial-frame captures and do not scale to unattended operation.
- Invent a new IPC socket / channel for decisions. Rejected because: the attention store already has
  a `decide` / `awaiting-input` path for exactly this shape; reuse it rather than add a parallel
  transport.

**Chosen because:** answering by label over a structured record is immune to menu reordering and
partial frames, and it is the same event-driven direction as D-2. It preserves the relay's
no-`send-keys` / no-impersonation contract (`orchestration-fleet`): the channel is upward-structured,
the answer downward-attributed, and the worker's own harness permission prompts stay out of scope
(those remain the human's gate).

Two robustness properties ride Task 4 (Done-when + risk register): each decision record carries a
**unique instance id** the answer must match, with **first-answer-wins claim/close** semantics, so a
late answer for a resolved fork cannot mis-apply to a later fork whose labels collide (the recurring
`Skip`/`Apply` case) and two answerers cannot double-deliver; and the channel **mechanically refuses
to emit an answer for a record whose reason is a permission-park**, so the harness-permission gate
stays the human's by mechanism, not by a prose scope claim alone.

### D-5: Ghost-text pin in the launch primitive, through an auto-approved launch shape (N)

**Decision:** The dispatch primitive applies `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` in its own
launch construction (a code path), through a launch shape the worker's permission layer auto-approves
— the `worker-command-guard` literal-path resolution shipped by `worker-permission-ergonomics`
(#236/#237) — so applying the pin never triggers the permission flood that forced a bare-launch
fallback.

**Alternatives considered:**
- Keep the skill-prose instruction ("launch every fleet session through `fleet-dispatch-env.sh`").
  Rejected because: it is model-obeyed, and on 2026-07-19 it was dropped — the wrapper invocation hit
  the classifier (which blocks `--permission-mode auto`), the fallback was a bare launch, and the
  bare launch dropped the pin, surfacing dangerous input-line suggestions ("mark PR ready", "clean up
  worktree and window") one stray Enter from firing.
- Apply the pin only via the watchdog's tower re-launch (the one code path that already wraps).
  Rejected because: it leaves every dispatched *worker* — the sessions actually read via pane capture
  — unprotected.

**Chosen because:** wiring the pin into the launch construction makes it a property of dispatch, not
of the model remembering prose; and now that `worker-permission-ergonomics` auto-approves the
literal-path script invocation, the wrapped launch no longer floods, so the deterministic and the
ergonomic paths finally coincide. Carries `fleet-autonomy` D-10 (the pin itself; prevention over
detection).

### D-6: Correct-glob allow-rule discipline, documented and guard-checked (N)

**Decision:** Path-scoped Bash allow rules use the `Bash(<dir>/*)` form; the word-boundary
`Bash(<dir>/:*)` form is forbidden for directory/path scoping (it never matches `<dir>/<file>`
because `:*` requires a following space or end-of-string). The rule is both documented and enforced
by a mechanical check that flags any `Bash(<path>/:*)` directory-scoped rule.

**Alternatives considered:**
- Document the rule only. Rejected because: operators re-derive the `:*` footgun by analogy to the
  correct *command* globs (`Bash(git status:*)`), which is exactly how a machine-local
  `Bash(<scripts-dir>/:*)` rule silently never matched the wrapper path on 2026-07-19 and forced the
  bare launch.
- Ship the check only, no doctrine. Rejected because: a flagged rule needs a stated correct form to
  fix toward; the check and the documented shape are complements.

**Chosen because:** the `:*` word-boundary semantics are a genuine, already-bitten footgun; making
the correct shape both the documented rule and a mechanical check closes it at authoring time rather
than at incident time. Grounded in the Claude Code Bash-glob word-boundary behavior (`:*` == a
following space-or-end-of-string).

### D-7: Deterministic D-36 branch naming in the tmux dispatch primitive (N, amended at kickoff 2026-07-20)

**Decision:** The tmux-backend dispatch primitive produces a worktree on the canonical D-36 branch
`planwright/<spec>/task-<id>` deterministically at launch, with no manual post-launch `git branch -m`
rename. Mechanism, in two steps:

1. **Create** the worktree with a single
   `git worktree add -b planwright/<spec>/task-<id> .claude/worktrees/<suffix> <base>` call, where
   `<base>` is the **freshly-fetched `origin/main`** (never stale local `main` or the tower's current
   HEAD — the fetch-before-act discipline of D-9); `<suffix>` is a **deterministic** function of
   `(spec, task-id)` so the same task always maps to the same worktree path; and `<spec>` / `<id>` /
   `<suffix>` are **validated against the D-36 grammar before interpolation** (or passed as argv, not
   a shell string) so no shell metacharacter or `..` path-traversal can reach the command. The
   shell-out is a narrow, documented exception to the never-shell-`git worktree` rule (scope below).
2. **Attach** with `claude --worktree <suffix> --tmux=classic`, which discovers the already-placed
   worktree (`docs/conventions.md`: "any worktree placed there is attachable … regardless of which
   backend created it") and folds the classic tmux session + launch. The attach runs **only if step 1
   exited zero**; a non-zero create aborts the dispatch and never attaches to a missing or wrong
   worktree.

Splitting create-then-attach makes the exact D-36 branch name a guaranteed output rather than a rename
an operator must remember.

**Alternatives considered:**
- The pure-native `claude --worktree <bare-suffix> --tmux=classic` fold (this decision's own prior
  mechanism, superseded here). Rejected because: `claude --worktree <name>` couples the worktree
  directory and the new branch to a single token and always names the branch `worktree-<name>`, never
  the slashed D-36 `planwright/<spec>/task-<id>` — there is no flag to set a slashed branch name
  (confirmed against `claude --worktree` behaviour, the running CLI, and the recurring
  tmux-dispatch-branch-rename operational evidence). Of the three constraints {deterministic D-36
  name, no post-launch rename, honour D-37's no-shell-`git worktree`}, only two are simultaneously
  satisfiable, so the fold cannot yield the D-36 name without a forbidden `git branch -m` rename.
- Keep the manual `git branch -m planwright/<spec>/task-<id>` post-launch rename (prior operator
  practice). Rejected because: it is a per-dispatch manual step; when forgotten, the worktree sits on
  the mangled `worktree-<suffix>` name, which the tasks-PR-sync hook cannot map back to a task (the
  non-convention-headref miss), so a merged task can read as unmerged.
- Use plain `--tmux` (non-classic) for the attach. Rejected because: it opens iTerm2 native panes that
  are not `load-buffer` / `capture-pane` relay-targetable; `--tmux=classic` is required for the relay
  to function.

**Chosen because:** of the three constraints above only two hold at once, and spending the no-shell
constraint — as a narrowly-scoped, documented exception — is the only way to keep **both** the
deterministic D-36 name and the zero-rename property; the mangled `worktree-<suffix>` name is exactly
what the tasks-PR-sync hook cannot map back to a task, so a merged task reads as unmerged. Two caveats
carry into the task: `--tmux=classic` is mandatory (not plain `--tmux`), and the attach command still
switches the attached tmux client to the new session, which must be mitigated so it does not disrupt a
tower watching another session — Task 10 **designs** that mitigation (launch detached, or
capture-and-restore the prior client attachment), not a manual confirmation.

**Collision / orphan handling.** `<suffix>` and the branch name are deterministic per task, so a
concurrent or repeat dispatch collides. Detection **relies on `git worktree add -b`'s own atomic
non-zero exit** (git locks the worktrees admin dir; `-b` refuses an existing branch) — never a
check-then-create pre-check, which would race (TOCTOU). On that failure the primitive **reconciles
rather than blindly aborting**, distinguishing in-flight from stale via this bundle's existing
liveness signals (the dispatch marker, the attached tmux session, the Task-2 attention/heartbeat
store — not a new source of truth):
- **Live** dispatch in flight → abort as **already-in-flight** (the intended collision guard).
- **Stale / orphaned** existing branch or worktree with no live session — a prior create that died
  before attach (step 1 succeeded, step 2 never ran), or a finished task whose branch outlived its
  worktree — is an orphan, not in-flight: the primitive **GC-adopts** it (remove the leftover
  worktree; delete the branch only when safe — not a live PR head, not unmerged-and-wanted) before
  recreating, so a crash can never wedge a task as permanently "already-in-flight". A leftover
  **empty** `.claude/worktrees/<suffix>` dir (which `git worktree add` would otherwise silently
  create into) is treated as such an orphan and cleaned, not silently reused.
- A **partial create** (branch made, worktree add failed) is **rolled back** (delete the just-made
  branch) so it cannot masquerade as an in-flight collision next time.

This replaces the earlier bare "detect an existing branch/worktree and abort" with a reconcile that
does not trade the rename footgun for a permanent-collision footgun.

**Exception scope.** The `git worktree add` shell-out is **confined to the dispatch primitive within
this bundle's shipped code**: a guard over the bundle's dispatch/tower sources (a grep / call-site
allowlist) asserts no other worktree-creation path in the bundle shells out to `git worktree`. It does
**not** claim planwright never shells out elsewhere — the same slashed-branch impossibility applies to
planwright's own spec-worktree creation (the `/spec-kickoff` path already uses `git worktree add` to
place `<spec>-spec` on `planwright/<spec>/spec`), so `docs/conventions.md`'s "planwright never shells
out to `git worktree`" and bootstrap-D-37 are already aspirational there. Reconciling that repo-wide
invariant (relax the never-shell rule to sanction `git worktree add` for the slashed-branch placement
contract, or add a native path that yields a slashed branch) is **delegated to planwright core**
(bootstrap-D-37 + `docs/conventions.md`), not resolved in this fleet bundle; an observation ties this
scoped exception to the existing 2026-06-16 D-37 opportunity so core reconciles it.

**Tower-guard interaction (D-8).** The `git worktree add` call lives **inside** the dispatch
primitive, which the tower runs as a planwright script by resolved literal path — allowed by the tower
guard's literal-path script allowance (REQ-C1.1), so the inner git call is never a separate PreToolUse
Bash string exposed to the stochastic `auto`-mode classifier. For defense-in-depth the tower deny
floor (REQ-C1.2) still names the dangerous `git worktree` forms (a `git worktree add` targeting or
detaching the default branch, `--force`) so no loose allow can pass them.

### D-8: Tower command-guard — a distinct tower safe set fronting the stochastic classifier (N)

**Decision:** A tower runs under a tower-settings profile that wires a deterministic PreToolUse
command-guard over the tower's own orchestration command set (tmux relay/observe, `claude --worktree`
worker launches, planwright scripts by resolved literal path), reusing the
`worker-permission-ergonomics` guard *pattern* but with a **distinct, tower-oriented safe set** — not
a verbatim reuse of the worker set. The guard is allow-only; because it has no default-deny,
deny-block *completeness* is the security floor (anything unmatched falls to the stochastic
classifier). The deny block therefore covers not only the shell ops (merge, force-push in every
spelling — `--force`, `-f`, `--force-with-lease`, `+`-refspec — amend, squash, rebase, `gh pr merge`)
but also **default-branch writes and local-`main` mutation** (`git push …:main`, `reset --hard`,
`branch -f`, `update-ref`), the **equivalent GitHub MCP tool surface** (`merge_pull_request`,
`update_pull_request` draft→ready, `push_files` / `create_or_update_file` on the default branch — a
Bash-string guard cannot see MCP calls), and every never-merge / never-ready guardrail, effective
regardless of guard output. The **allow-set is pinned** so `claude --worktree` never matches
`--dangerously-skip-permissions` / `--permission-mode` (a fleet-wide escalation) and `tmux` is scoped
to `load-buffer` / `paste-buffer` / `capture-pane` (never `send-keys` / `kill-session`); the guard
**fails closed**; and the sanctioned kickoff spec-PR ready-flip is reconciled against the never-ready
deny (denied for task PRs / by the tower, permitted only via the kickoff skill path).

**Alternatives considered:**
- Reuse `worker-command-guard.sh`'s safe set verbatim for the tower. Rejected because: the tower's
  safe set genuinely differs (the tower needs tmux relay/observe and `claude --worktree` launches;
  the worker needs git/mise/gh), and `worker-permission-ergonomics` scoped its guard worker-only for
  a security reason (blast radius) this bundle must consciously re-open rather than silently widen.
- Hand-edit `settings.local.json` allow rules (the 2026-07-18 stopgap). Rejected because: static
  rules are deterministic but brittle — they enumerate commands, cannot match dynamic `$VAR`-expansion
  shapes, and are pinned to a plugin version; and the tower cannot self-grant a fix (editing its own
  allowlist is correctly classifier-blocked as self-escalation).
- Rely on the `auto`-mode classifier for the tower. Rejected because: it is a non-deterministic LLM
  feature that cannot be made deterministic or tested, and it stochastically blocked the tower's own
  orchestration commands — determinism only comes from fronting it with a tested allow layer.

**Chosen because:** a tested allow layer evaluated before the stochastic classifier is the only path
to deterministic tower self-permission (obs:8eacaa65, Diego's determinism requirement). The
allow-only, deny-precedence, no-LLM properties carry from `worker-permission-ergonomics`; the tests
assert the *outcome* (the guard never emits `allow` for a deny-listed command) rather than relying on
documented Claude Code allow-vs-deny precedence, which is not confirmed for the running version
(obs:4dda9fe1). **Routing note:** obs:8eacaa65 originally directed this to land as a
`worker-permission-ergonomics` amendment; the 2026-07-19 hardening seed places it here — the
`/spec-kickoff` walkthrough confirms the placement (see requirements Sources).

### D-9: Fetch-before-gate freshness and merge detection, without advancing local `main` (N)

**Decision:** `/orchestrate` and `/execute-task` fetch `origin` and evaluate the execution freshness
gate (currency, and `anchor-integrity`'s existing content-anchor check re-pointed at the fetched ref
— this bundle re-points, it does not implement anchor-hash comparison) and merge detection against
the fetched `origin/main` and remote-tracking refs before dispatch. The fetch does **not** advance
local `main`. A tower-recorded
observation reaches the accumulator on `main` through a sanctioned path (the `--bookkeeping` / drain
pass, or the tower, auto-opening a chore PR), rather than being stranded on a never-pushed tower
branch.

**Alternatives considered:**
- Fast-forward local `main` before dispatch. Rejected because: multiple towers and workers share one
  checkout; advancing local `main` clobbers a peer's unpushed commits — the shared-checkout model
  (`orchestration-concurrency`, inter-orchestrator coordination) keeps local `main` read-only and
  reconciles via quick PRs, never by resetting or advancing shared `main`.
- Keep the offline gate reading local `main` (the status quo). Rejected because: it is a stale-read
  surface — a stale local `main` bases a dispatch on outdated spec content, misses an upstream
  re-anchor, and (for merge detection) re-dispatches an already-merged task whose merge trailer has
  not reached local `main`. This bundle hit it live during its own drafting.
- Write tower observations to a shared location outside the tower branch. Rejected for the
  observation-propagation half because: it re-opens the concurrent-shared-write conflict class
  `observation-recording` already solved for the accumulator log.

**Chosen because:** fetching and gating against `origin/main` makes the dispatch base and merge
signal current without touching the shared local `main`, honoring the read-only-local-`main`
invariant; and a sanctioned chore-PR path stops autonomy learnings being lost on disposable tower
branches (obs:a877745e). **Scope boundary:** this is git-ref currency for the dispatch/merge path
only. Content-anchor *hash* freshness (whether the executed bundle equals the signed one) is
`anchor-integrity`'s (Ready); the `release-publish` stale-`main` version-derivation variant is
`release-hardening`'s (obs:04b578da). The observation-propagation half (REQ-D1.3) stays here
(kickoff, 2026-07-19): `observation-recording` (Done) does not own a tower→`main` carry path and is
out of scope for one, and `observation-routing` is cross-repo (a different axis) — REQ-D1.3's
intra-repo tower→`main` carry is fleet-domain and net-new here. `no-remote` / `no-gh` degrades
gracefully, as the existing reconcile fetch already does.

Three execution-time robustness properties ride Tasks 8 and 9 (Done-when + risk register): a
**transient fetch failure against a *present* remote** is handled distinctly from structural
`no-remote` (retry, then block or proceed with an explicit stale flag — never a silent stale gate);
the per-gate fetch is **bounded** (a short TTL / coalesced with the reconcile sweep) so an
`/orchestrate --watch` idle loop does not fetch every cycle; and the observation carry is
**idempotent** (reuse / update one open chore PR, dedupe already-carried observations) and safe under
concurrent bookkeeping runs.
