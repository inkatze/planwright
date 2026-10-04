# Fleet Hardening — Design

**Status:** Ready
**Last reviewed:** 2026-10-04
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

**Superseded-by: D-10** (2026-10-04, attach step only) — step 2's attach through
`claude --worktree <suffix> --tmux=classic` never returns inside tmux, moves the operator's
client, and leaves its worker on the tmux server's environment; D-10 replaces the attach step and
its carried caveats with a detached launch the dispatch creates itself. Step 1, the
collision/orphan handling, the exception scope, and the tower-guard interaction carry into D-10;
D-14 extends the collision handling with a name pre-check and its failure arms, and the "attached
tmux session" liveness signal above now means a live tmux session for the worker.

### D-8: Tower command-guard — a distinct tower safe set fronting the stochastic classifier (N)

**Decision:** A tower runs under a tower-settings profile that wires a deterministic PreToolUse
command-guard over the tower's own orchestration command set (tmux relay/observe, `claude --worktree`
worker launches *(amended at extension kickoff 2026-10-04: an operator's hand-launch; the tmux
rung's worker launch is D-10's detached session)*, planwright scripts by resolved literal path),
reusing the
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

### D-10: The tmux rung launches its worker in a detached session it creates itself (N, extension 2026-10-04; supersedes D-7's attach step)

**Decision:** D-7's create step carries unchanged: a single
`git worktree add -b planwright/<spec>/task-<id> .claude/worktrees/<suffix> <base>` on the
freshly-fetched `origin/main`, tokens validated before interpolation, the create's exit status
gating everything after it, the atomic-exit collision detection and live-versus-stale orphan
reconcile, the scoped never-shell-`git worktree` exception, and the tower-guard interaction. D-14
adds a name pre-check and the failure arms around it. The attach step is replaced. After the
create succeeds, the dispatch primitive creates the worker's session itself, in one tmux
invocation that also turns `remain-on-exit` off for the new window (so a worker that exits takes
its session with it, whatever the operator's global tmux options say):

`tmux new-session -d -s <session> -c <physical worktree> -P -F '#{session_name}<TAB>#{window_id}' -- <fleet-dispatch-env.sh> <wrapper options> <absolute claude> <launch args> [-- <prompt>]`

with stdin from `/dev/null`, no `--worktree`, and no `--tmux`. `<wrapper options>` are D-11's;
`<launch args>` are the forwarded flags the primitive already admits, plus any launch flags a
sibling spec adds to this rung (`fleet-messaging`'s `--name` and `--settings <profile>`, its
REQ-B1.1 and Task 4, when they land). The command after `--` is always several argv words, never
one shell string. The session is never attached and no client is switched. The name and window id
that `-P -F` prints are the registry death handle (REQ-G1.6): the registry record is written once,
after `new-session` succeeds, carrying that handle; output that does not parse to one name and one
window id inside the registry's token grammar registers no death handle and warns, without failing
the launch. The observe hint targets `'=<session>:'`, because tmux 3.6 refuses a bare `=<session>`
as a pane target. The flight dispatch takes the session name for its report and hints from the
launch's report line, never by searching session names.

The primitive's live launch has two steps. **Launch** returns once the session exists, printing
its report. **Confirm** then waits for the worker's startup confirmation (D-15). The flight caller
runs the launch under the checkout's flight lock, releases the lock, and only then runs the
confirm step, because the lock guards counting free slots and placing the worktree as one act,
and both are finished once the session exists. A caller with no lock (the `/orchestrate` tmux
dispatch) runs the two back to back. The session name is D-14's, the env carriage D-11's, the path
checks D-12's and D-13's.

**Alternatives considered:**
- Keep `claude --worktree <suffix> --tmux=classic` and background it. Rejected because: the
  launcher still switches the operator's client and still never exits, leaving one orphan per
  dispatch. Its worker still takes the tmux server's environment, and its `--worktree` still
  resolves against the main checkout, so a placed worktree checked out elsewhere gets a second one
  (obs:62f3016e).
- Run the native launcher with `TMUX` unset so it does not take the inside-tmux path. Rejected
  because: what it does outside tmux is undocumented and version-sensitive, and the `--worktree`
  resolution and environment problems remain.
- Open the worker as a window in an existing (tower) session. Rejected because: it ties the
  worker's lifetime and naming to the tower's session (closing the tower's session closes its
  workers), and it breaks the one-session-per-worker liveness probes.
- Keep the blocking launcher and kill it after a timeout, then restore the client. Rejected
  because: it is timing-based. It reports a live worker as killed, which is the false "did not
  start" this extension removes, and the environment defect stays.
- One launch step that waits for confirmation inside the flight lock, with its cap held well below
  the lock wait. Rejected because: the lock then guards nothing for the length of the wait, and
  concurrent flights from one checkout queue behind each other's startup check, a smaller form of
  obs:fa759dcb (operator decision, 2026-10-04).

**Chosen because:** this is the session the native launcher already creates (the worktree as cwd,
the worker in a classic tmux pane), minus the client switch, the wait, and the `--worktree`
resolution. It is the only shape that meets REQ-F1.1 through REQ-F1.4 together. The pane stays a
classic tmux pane, so D-7's reason for `--tmux=classic` (a `capture-pane` / `load-buffer`
relay-targetable worker) still holds without the flag. Writing the registry only after the session
exists means no failure arm ever has a record to retract. Cross-spec: `fleet-messaging`'s open
question about `--name` beside `--worktree --tmux=classic` no longer bears on this rung once no
tmux-rung worker launches with that shape.

### D-11: The dispatch env wrapper carries the worker identity and the dispatcher's roots, inside the session (N, extension 2026-10-04)

**Decision:** `fleet-dispatch-env.sh` is the session's command, so the environment it builds is
the worker's own, whatever the tmux server's environment holds. The wrapper gains leading options:

- `--identity <handle> <scope>`: validated against the identity-gate grammar the liveness hooks
  enforce, then exported as `PLANWRIGHT_WORKER_HANDLE` and `PLANWRIGHT_WORKER_SCOPE`.
- `--launch-token <token>`: a per-launch random token the dispatch mints (lowercase hex), exported
  as `PLANWRIGHT_WORKER_LAUNCH_TOKEN` for D-15's confirmation.
- `--root <dir>` and `--fleet-home <dir>`: the dispatcher's resolved planwright root and fleet
  home, which the wrapper exports in place of any inherited value, so the worker's command guard
  and its hook writes resolve to the same root and store the dispatcher uses.

A malformed or half-supplied option is a usage refusal (exit 2). The dispatch runs the wrapper in
a check-only mode (`--check`, which validates every option and exits without `exec`) before
`new-session`, so a refusal is reported by the dispatch and launches nothing; the in-session
validation stays as defense in depth. The tmux rung passes the handle and scope of the registry
record it writes (`tmux-<spec>-task-<id>` and `<spec>:<id>` for a task, `tmux-flight-<flight-id>`
and `flight:<flight-id>` for a flight), so the two agree by construction. This bundle owns the tmux
rung's identity export; `fleet-messaging` REQ-B1.1 and its Task 4 require the same export across
every session-grade rung, and its tmux part is satisfied here (operator decision, 2026-10-04).

**Alternatives considered:**
- `tmux new-session -e KEY=VALUE`. Rejected because: it needs tmux 3.2 or later where planwright
  declares no tmux floor, and it puts the identity in the session's tmux environment, where later
  windows in that session inherit it.
- An `env KEY=VALUE` prefix in the session's argv. Rejected because: it adds a second
  env-setting path beside the wrapper, which REQ-B1.1 names as the mechanism of record, with
  nowhere to validate the identity grammar.
- `tmux set-environment -g`. Rejected because: it writes the server's global environment and leaks
  into every session the server starts.
- Leave the identity export to `fleet-messaging`. Rejected because: D-15's confirmation needs the
  identity now, and that bundle has not started executing.

**Chosen because:** one seam applies every dispatch-time variable and validates it where it is set
(the `existing-seam-reuse` decision domain), with no tmux version floor. Running the wrapper inside
the session is what closes obs:da5e6757: the defect was a correct wrapper running in the wrong
process. Under the detached launch "inherited" means the tmux server's environment, so the
wrapper's keep-an-inherited-root rule would let a stale server value win; passing the dispatcher's
values explicitly closes that.

### D-12: Declared charsets for every tmux-format-expanded value; a physical start directory that must exist (N, extension 2026-10-04)

**Decision:** tmux 3.6 format-expands `new-session`'s `-s` and `-c` and every `-t` target, and does
not expand the command words after `--` (the probes in Sources). Before any tmux call, including the
liveness probes' `has-session` targets, the launch checks the two expanded value classes against
declared charsets:

- the physical (`pwd -P`) worktree path against the brief path charset `[A-Za-z0-9._/@+-]`;
- the session name against `[A-Za-z0-9_@-]`, first byte alphanumeric, at most 128 bytes. That is
  the registry's tmux-token grammar narrowed to drop `.` (which tmux rewrites to `_`, as it does
  `:`), so every name the launch creates is also a valid death handle.

A value outside its charset is refused with a message naming the charset and the value class
(worktree path or session name), and nothing is launched. The start directory must exist, be a
directory, and equal `<physical worktree root>/<suffix>`, rechecked immediately before
`new-session`; tmux would otherwise start the pane in its fallback directory without a word. A
checkout whose physical path falls outside the charset (one holding a space, for example) therefore
cannot use the tmux rung. The refusal says so, and the other rungs are unaffected. A liveness probe
whose name fails the charset is not sent and reads as live (the probes' fail-safe direction, D-7).

**Alternatives considered:**
- Refuse only `#`. Rejected because: a denylist is only as complete as one's knowledge of what
  tmux expands, and that varies by version; an allowlist does not depend on it (operator decision,
  2026-10-04).
- Escape `#` as `##`. Rejected because: it relies on per-argument tmux escape semantics that
  differ across versions, and the unescaped path still reaches other surfaces verbatim.
- Omit `-c` and have the wrapper change into the worktree. Rejected because: the session name
  still needs screening, so it adds a mechanism without removing the check.
- Apply a charset to the command words too. Rejected because: the probe shows tmux passes them
  through unexpanded, and the prompt and forwarded flags would lose bytes for no protection.

**Chosen because:** the path charset is the one the dispatch arm already holds the brief path to,
so one rule covers every path the launch hands tmux, and the session-name charset is the narrowest
one the registry and death evidence already accept. Both were verified against the live expansion
behavior (the tmux 3.6 probes in Sources). The cost, no tmux rung for a checkout path outside the
charset, is recorded here and in Out of scope.

### D-13: `attach` keeps its plan and refuses a live launch (N, extension 2026-10-04)

**Decision:** `fleet-dispatch-worktree.sh attach <suffix>` keeps its argument validation and its
`--dry-run` plan output, which now prints the detached launch plan (D-10). A live standalone attach
is refused with a usage error pointing at `dispatch`. The only live launch is the dispatch arm,
after its path-escape guard (no symlinked `.claude`, `.claude/worktrees`, or leaf, and physical
containment under the primary checkout's worktree root), which satisfies REQ-G1.3 by construction.
The `--no-attach` flag keeps its name; its prose says it creates the worktree without launching a
worker.

**Alternatives considered:**
- Keep the live standalone attach and share the guard with it. Rejected because: no shipped caller
  uses the live arm, so keeping it keeps a second launch path to secure and test for no current
  user.
- Remove the `attach` subcommand. Rejected because: its argument-validation fixtures would move to
  `dispatch --attach-dry-run`, a larger test rewrite for no extra safety.
- Rename `--no-attach`. Rejected because: shipped callers and docs use it, and the rename buys
  only vocabulary.

**Chosen because:** removing the unguarded live arm is the smallest change that makes every live
launch pass one guard, and the plan output keeps its fixtures (operator decision, 2026-10-04).

### D-14: Session names carry the checkout; collisions are found before side effects; a lost race touches nothing (N, extension 2026-10-04)

**Decision:** The session name is `<base>-<hash6>_<suffix'>`:

- `<base>` is the primary checkout's physical basename with every byte outside `[A-Za-z0-9@-]`
  mapped to `-`, leading non-alphanumeric bytes dropped (`repo` if nothing remains), truncated to
  32 bytes.
- `<hash6>` is the first six of the eight zero-padded lowercase hex digits `printf '%08x'` renders
  for the `cksum` CRC of the primary checkout's physical path. This is disambiguation, not
  security: two checkouts that collide on it fail closed as a live-name refusal and never
  cross-wire.
- `<suffix'>` is the worktree suffix with `.` written `_`, the rewrite tmux itself applies, so the
  name the dispatch computes is the name tmux stores and `=<name>` targets match exactly.

A name over 128 bytes is refused under D-12 before any side effect.

Before any durable side effect (worktree, branch, dispatch marker, registry record), the dispatch
checks whether a session already holds that exact name. A live one is an in-flight dispatch and
aborts as already-in-flight under the live-versus-stale rule carried from D-7. This is a fast path
for the common case; the create's atomic exit (D-7) and the lost-race arm below remain the race
guard.

- **Lost race** (`new-session` refuses a duplicate name): everything the task's dispatch owns (the
  worktree path, branch, marker, and registry handle) is the winner's too, so the dispatch aborts
  as already-in-flight and removes, clears, and writes nothing.
- **Any other failure after the create** (`new-session` failing for another reason, a start
  directory refused under D-12, tmux gone): the dispatch undoes only what this run created. It
  removes the worktree and deletes the branch only if this run created them with `-b` and no live
  session runs in the worktree (an adopted branch is never deleted), and it clears the marker it
  set. A failed undo step is reported by name with the residual path or branch, and the dispatch
  still exits with the original failure's status.

Neither arm writes a registry record: D-10 writes it only after `new-session` succeeds, and closing
a record stays the reconcile's, on positive death evidence (`fleet-lifecycle-closure` REQ-E1.5).

Liveness probes check this name and, while workers from before the upgrade may still be running,
the prior launcher's `<repo-basename'>_worktree-<suffix'>` spelling, where `<repo-basename'>` is
the primary checkout's basename with `.` and `:` written `_` (tmux's rewrite), for the dispatch
suffix and for the alternate name of a worktree that already holds the branch alike. The bare
`<suffix>` and `worktree-<suffix>` probes (and their alternate-name forms), which match nothing any
launch creates, are removed. Retiring the prior-launcher probe is a gated deferral in `tasks.md`.

**Alternatives considered:**
- Hash only (`pw-<hash8>_<suffix'>`). Rejected because: the repo cannot be recognized in
  `tmux ls` or in the dispatch report's hints (operator decision, 2026-10-04).
- Basename only (`<base>_<suffix'>`). Rejected because: two clones with the same directory name
  would share session names, which fails REQ-G1.4.
- Rely on `new-session`'s own duplicate refusal, with no pre-check. Rejected because: that refusal
  comes after the worktree and marker exist, which is the orphan the parked flight's review found.
- Roll back the worktree, branch, and marker on a lost race and write a terminal registry record.
  Rejected because: they belong to the winner, so the loser would remove a running worker's
  checkout and close its record, and only the reconcile closes records (operator decision,
  2026-10-04).

**Chosen because:** it is unique per checkout and still readable, and every byte is inside D-12's
session-name charset by construction. The pre-check catches the common collision before any write,
D-7's atomic create stays the race guard, and the failure arms never touch what a winner owns.

### D-15: A launch counts as started when this launch's worker confirms it from its SessionStart hook (N, extension 2026-10-04)

**Decision:** Before any durable side effect, the launch resolves the worker CLI (`command -v
claude`) and `tmux`, requiring an absolute path to an executable regular file for `claude` and a
resolvable `tmux`, and refuses otherwise with documented statuses. The confirmation is a new
identity-gated `SessionStart` arm in `fleet-liveness.sh`, wired under the `startup` and `resume`
matchers (task dispatches may forward `--continue` / `--resume`), that pushes `working` for the
worker's handle and records the launch token from the worker's environment (D-11), extending the
hook set the way D-2's `Notification` arm did and redefining nothing (REQ-E1.2).

The confirm step (D-10) records the dispatch start immediately before `new-session`; an unknown
start time never confirms. It then polls, at a fixed interval and up to a fixed cap both defined in
the launch script (a test seam shortens both), and on each poll:

1. reads the attention store first: a row for its handle carrying this launch's token and stamped
   no earlier than the dispatch start is the confirmation;
2. otherwise probes the session: a definite "no such session" from a reachable server ends the
   wait as failed-at-startup; an unreachable server or an unreadable store keeps waiting.

The signal is the worker's own event; only its read is polled, and the poll is bounded.

The outcomes, each with its own exit status:

- **started:** confirmed, report printed, exit 0.
- **failed-at-startup:** the session is gone. The report says the worker died at startup. The
  dispatch clears the marker it set, so a retry is not read as in-flight; for a flight, whose
  registered worktree the reconcile never force-removes, the report names the hand removal step.
- **started-unconfirmed:** the cap expired with the session still present, or the server or store
  stayed unreadable. The report carries the handles and says confirmation never arrived. Every
  shipped caller of the primitive (the flight dispatch and the `/orchestrate` tmux dispatch alike)
  treats it as placed, never as a failure that invites a re-dispatch.

Every exit status the launch returns (the outcomes and each refusal) is distinct and documented in
the primitive's usage header. The launch never sees the worker's own exit status.

**Alternatives considered:**
- Set `remain-on-exit` and check `#{pane_dead}` after a fixed settle. Rejected because: it is
  timing-based, misses a worker that dies after the settle, and confirms only that a process
  exists, not that Claude Code reached a working session.
- Both, with a dead pane ending the marker wait early. Rejected because: the session-gone check
  already ends the wait for a worker that dies, so a second mechanism doubles the test surface for
  little extra precision (operator decision, 2026-10-04).
- Accept any `working` row for the handle, with no token. Rejected because: any process that sets
  the handle could mark a dead launch started (operator decision, 2026-10-04).

**Chosen because:** it is the worker's own deterministic event, in the store the tower already
watches, which is the bundle's principle (D-1). It exists only because REQ-F1.5 now gives tmux
workers an identity. The three outcomes keep the one failure #546 made costly, reporting a running
worker as failed, from returning: a missing confirmation with a live session, or an unreadable
server, is never read as death.
