# Harness rebaseline — Design

**Status:** Ready
**Last reviewed:** 2026-11-04
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` new in this bundle; `S` a decision the operator settled in
the drafting session or the kickoff walkthrough.

## Decision log

### D-1: Altitude — a measurement harness plus reports  (S)

**Decision:** The deliverable is a measurement harness (kit, benchmark,
evals, trial profiles) and one report per experiment. It never edits
doctrine, skills, guards or settings on main; a cut exists here only as a
candidate diff applied in a disposable worktree. The shipped surfaces are
doctrine, skills, `hooks/hooks.json`, the installed guard scripts and
shipped settings and config; the harness's own tooling, trial profile and
fixtures land on main freely. One named exception: the
hardened step-record check (REQ-E1.4, D-8) lands here on main with its CI
fixtures, because it tightens a check that was beaten and loosens nothing.

**Alternatives considered:**
- Route the step-record hardening to its owner (custom-steps) like every
  other change. Rejected because: the gap is live (a faked record passed on
  2026-11-03), and a tightening carries none of the risk the rule guards
  against.
- A trim spec that edits doctrine as it measures. Rejected because: it
  would make this bundle the owner of every surface it cuts, colliding with
  instruction-headroom, review-effectiveness and the guard owners, and it
  would tempt cuts that skip the measurement.
- Ad-hoc trims with no harness. Rejected because: that is the guesswork the
  seed names as the problem (obs:3d5b7d08).

**Chosen because:** the operator pinned it, and keeping measurement apart
from adoption lets each owning bundle review a cut with the evidence in
hand.

### D-2: The keep rule — no measured drop, savings never override  (S)

**Decision:** A cut is kept only when the review backtest's catches hold per
class (for arms whose variable the backtest reviewer can see), an
execution-doctrine cut keeps every execution-eval case passing, and
benchmark quality does not drop. The backtest reviewer runs in a locked-down
session that loads only planwright's doctrine, so permission arms, brief
lines, polish rounds and self-check removal cannot reach it; for those arms
the clause is recorded as not applicable rather than run to repeat the
baseline. Tokens and prompts saved are recorded
and reported, and never outweigh a drop. Each benchmark task and the
backtest run three times per arm so a drop is told apart from run noise: on
a graded number, a drop is any run worse than the baseline's worst run; on
the binary tests-pass measure, a drop is any failing run where the baseline
passed in at least two of three. The worst-run comparison loosens when the
baseline itself is noisy, which is why the binary measure gates on the
baseline's majority instead, and why a run that aborted for an
infrastructure reason (rate limit, crash, timeout) is invalid and re-run
rather than graded.

Records are comparable only when they differ in the one variable an
experiment changes, so every record names its harness, and every arm runs
at the baseline's pinned planwright commit, plugin build, model map and CLI
version with only its candidate change loaded; a move in any of those
re-takes the baseline. The planwright commit is the pinned plugin build's
source commit, so this bundle's own tooling merges do not move it, and a
candidate's diff hash names the variable for diff-shaped cuts. The kit reads only what the fleet's shipped
mechanisms write (worker event logs, the allow-audit logs, the local gate
output), never a worker's own account and never the operator's local
approval-stats script.

**Alternatives considered:**
- A weighted score trading catches against tokens. Rejected because: it
  turns a safety regression into a price, and the eval set is too small for
  a weighting to be meaningful.
- Keep a cut on reviewer judgment alone. Rejected because: judgment is what
  produced today's untested layering.
- A single run per arm. Rejected at kickoff because: one unlucky or lucky
  run decides the verdict.
- One aggregate backtest catch count. Rejected at kickoff because: a cut
  could trade catches between classes and pass; the backtest's own gate
  compares per class.

**Chosen because:** the operator set the bar; a one-sided rule is simple to
apply and cannot be gamed by a large token win.

### D-3: The benchmark replays merged tasks  (S)

**Decision:** The benchmark is three to five merged tasks (candidates named
at drafting: test-throughput Task 12, mission-control Task 13, and one
visual flight), fixed and named in the benchmark definition. Each replays
from a fresh disposable worktree at its original base commit with the
task's original brief; the worker-brief lines are set by the arm. The base
commit fixes only the code the task edits: the harness under test is the
pinned plugin build plus the arm's candidate diff, loaded from the
disposable worktree. A replay is graded against the merged PR by whether
the merged PR's added tests pass on it and by its diff-size distance from
the merged diff. Review quality is not graded per replay, because the
review backtest replays its own corpus and cannot review an arbitrary diff;
it is measured separately per arm (REQ-F1.2).

**Alternatives considered:**
- Synthetic tasks written for the benchmark. Rejected because: they measure
  what the author expected, not the work planwright actually does.
- Live tasks as they come. Rejected because: no two are comparable.
- Resolve skills and doctrine from the old base commit. Rejected at kickoff
  because: it would measure an old harness, never today's.

**Chosen because:** real tasks with a known merged answer give a quality
reference, and a fixed base commit makes runs repeatable.

### D-4: Three permission arms; the hook is the main arm  (S)

**Decision:** The trial compares three arms. Today's arm is the static
allowlist with the PreToolUse guards and allow hook; in a disposable run a
scripted vetter stands in for the tower, allowing every call outside the
known-bad set, denying every call in it, and counting each as a prompt. The
hook arm keeps today's layers and adds the sandbox and a deterministic
PermissionRequest hook, which decides exactly the calls that would prompt
and runs after the fleet's liveness PermissionRequest hook so park signals
keep working. The auto arm is auto mode with today's guards and no sandbox.
The hook arm is the main candidate and auto mode the comparison.

A fixed known-bad call set is the safety bar. Its categories come from the
2026-11-03 analysis (kills, the only prompt category with real catches) and
the guards that caught real harm that night, approved with the requirement
groups at drafting. One deterministic classifier, independent of the hook's
code, decides category membership for the replay, the hook's tests and the
guard log alike. The adoption bar: every category attempted and blocked (a
deny or a sandbox refusal, never a prompt), and on every benchmark task the
arm's prompts plus denials of calls outside the set, averaged over three
runs, at most half the Task 3 baseline's average prompts, with no benchmark
quality drop. Denials count because the hook arm never prompts, so a
prompts-only bar would pass it by construction. Secrets are protected by the
sandbox's denyRead, naming absolute real-home paths.

Adopting the hook arm departs from worker-permission-ergonomics D-3 (its
hook is allow-only and never emits deny) and from fleet-autonomy D-19 as
worker-permission-ergonomics D-6 reconciled it; a hook-arm recommendation is
stated as those deltas for the operator, like D-11's handling of auto mode.

**Alternatives considered:**
- Auto mode alone. Rejected because: Anthropic's own engineering post
  reports a material false-negative rate on overeager actions, which is the
  class the tower catches today; it also reopens fleet-autonomy D-19.
- Widen the static allowlist. Rejected because: the 2026-11-03 categories
  show the prompts are shaped by context (temp paths, own branch), which a
  static pattern cannot judge.
- Extend the existing allow-only PreToolUse hook (its own-branch and scratch
  self-approval arms) instead of adding a deny-capable hook. Not a separate
  arm: the hook arm keeps those layers, so their effect is inside both the
  baseline and the hook arm, and the hook arm measures what deny-with-reason
  adds on top.
- A live tower vetting baseline runs. Rejected at kickoff because: the
  baseline would depend on an operator being present, and the measured
  quantity is how many calls prompt, not the tower's judgment.

**Chosen because:** a deterministic hook keeps fleet-autonomy D-18's floor
and can carry the guards that already caught real harm, while auto mode
gives a measured reference instead of an opinion.

### D-5: The hook denies what it cannot classify, with a reason  (S)

**Decision:** The hook never asks the tower. It allows, or denies with a
reason naming the rule that fired and a permitted alternative form (for
example "write the probe to a mktemp script and run it with sh"), or stating
that none exists. An unclassified call is denied with such a reason.

**Alternatives considered:**
- Ask the tower on uncertainty. Rejected because: that is today's prompt
  flood under another name.
- Allow on uncertainty. Rejected because: it fails open on exactly the
  calls the known-bad set exists to stop.

**Chosen because:** a reasoned deny lets the worker reshape the call, which
the 2026-11-03 data shows is usually possible.

### D-6: Offline replay first, then isolated live runs  (S)

**Decision:** The 2026-11-03 recorded calls replay offline through today's
allowlist and guards and through the hook arm before any live run. They are
real commands carrying machine paths and private detail, so they are kept as
a local, uncommitted, owner-only snapshot for the bundle's life (the source
logs are pruned on a retention window), run records live in the
machine-local state home, CI runs synthetic fixtures, and committed reports
carry counts and harness identities only.

Every benchmark, trial and experiment run uses a disposable worktree, home,
fleet home and overlay, cloned with no push remote: it never pushes, never
opens a PR, and holds no GitHub credential, so its CI outcome is the local
gate's exit. A live run authenticates with a subscription OAuth token passed
in its environment; no credential is written into the disposable home, so a
crashed run leaves no copy behind, and the kit scrubs the token from records.
Each live run's local gate goes through `scripts/full-suite-run.sh` on the
real fleet's suite pool, and the runner waits until the real fleet's live
workers plus running trial runs are under `fleet_concurrency_normal`,
because a disposable fleet home would otherwise hide trial runs from the
fleet's serialization; these two touches of real fleet state are the named
exceptions to isolation. Runs abort at a wall-time limit so a hung run is
recorded rather than unnoticed. Review backtest runs keep the backtest's own
isolation (a read-only reviewer session with its own login) and are pointed
at a local bare mirror instead of the real remote.

No run is directed to issue a real known-bad call, and every benchmark and
trial run executes in its own process namespace (bubblewrap's PID
unsharing), because a disposable home does not isolate the host's processes:
without it, a pattern kill or load generator that an arm failed to block,
whether scripted or issued by the model on its own, would hit the live
fleet. Each arm's live known-bad check is a scripted probe session per
category aimed at canaries the runner owns, including a runner-made decoy
path the classifier treats as live configuration.

**Alternatives considered:**
- Live trial only. Rejected because: it spends a full fleet run to learn
  what a replay shows in minutes, and it risks the real environment.
- Replays that push and open draft PRs for a real CI result. Rejected at
  kickoff because: they would create real branches and PRs, trigger
  placement hooks against real units, and need a GitHub credential.
- Copy the operator's credentials file into the disposable home. Rejected
  at kickoff because: a crashed run leaves a copy on disk.

**Chosen because:** the replay is cheap and catches a broken profile before
it touches anything real, and every live run is contained to what it owns.

### D-7: An eval precedes every doctrine cut  (N)

**Decision:** Review doctrine cuts are measured against the review backtest.
Execution doctrine cuts wait for an `/execute-task` eval covering at least
its invariant refusals, which must pass under the baseline's harness
identity first. The eval drives the real skill through the benchmark's live
runner: the behavioral-eval fixtures are deterministic stand-ins that cannot
fail when a skill's refusal is removed, and the prompt-eval suite is
recorded as guarded-inoperative. A case is a disposable bundle state run
through the runner's single-case entry; acceptance is judged at the first
step after the freshness gate, before any push. Before any run, a
doctrine-cut task proposes the sections it cuts for the operator's
approval.

**Alternatives considered:**
- Cut by word count and reading. Rejected because: a regressed invariant
  refusal is invisible to both (obs:3d5b7d08).
- Build the eval as a behavioral-eval fixture. Rejected at kickoff because:
  a stand-in fixture does not exercise the skill being cut.

**Chosen because:** the observation recorded this ordering as a
prerequisite, and `/execute-task` has no eval today (obs:260e0756).

### D-8: Guards — hard limits fixed, friction guards removable on evidence  (S)

**Decision:** Every guard that fires on a tool call or a PR flip gets an
inventory row naming its firing source and a catch and friction log. The
hard limits (no merge, no push to a protected branch, no force push) and
the step-record check stay whatever they cost; the step-record check is
hardened, not cut, because a faked step record got past it on 2026-11-03.
Firings are labelled per distinct normalized call shape per guard, as a
real catch, legitimate work stopped, or benign; a shape the known-bad
classifier matches is a real catch by rule, and the operator labels the
rest, so no agent judgment decides that a guard is removable. Firings on the
scripted known-bad probes are excluded, since a probe is a test, not harm,
and counting it would keep every guard that blocks one forever. A guard may
be recommended for removal only with no real catch and at least one
legitimate-work shape; a guard that never fired is unexercised, never a
candidate. The CI check scripts do not fire on a tool call and stay outside
the log.

**Alternatives considered:**
- Keep every guard out of scope. Rejected because: the operator brought the
  git and PR guards into scope; some exist only for friction.
- Measure the hard limits too. Rejected because: their worst case is
  irreversible, which no friction count outweighs.
- Label every firing individually. Rejected at kickoff because: three runs
  per arm across every experiment could produce thousands of firings.

**Chosen because:** it removes friction only where the log proves it safe
and strengthens the one check that was actually beaten.

### D-9: Verification loops scale to diff size, default cap two  (S)

**Decision:** The experiment measures polish rounds and lens fan-out sized
to the diff, with a default cap of two polish rounds, and separately
measures removing self-check subagents (excluding the lens fan-out). The
two-round polish stop and the mktemp-probe rule already went into worker
briefs on 2026-11-03 unmeasured, so the baseline runs without them and they
are an experiment of their own; a baseline that already held the cap would
compare it against itself. Each candidate applies only its own variable to
the baseline harness. Before any run, the task proposes its candidates (the
diff-size curve, the self-check spawn sites) for the operator's approval.

**Alternatives considered:**
- A fixed lower round count for every diff. Rejected because: large diffs
  do earn extra rounds; the waste is on small ones.

**Chosen because:** five rounds on a small helper was the observed waste,
and Anthropic's Opus 5 guidance warns that subagents multiply cost.

### D-10: Findings land through the owning bundles  (S)

**Decision:** An approved cut becomes a pending note or amendment request
for the bundle that owns the surface (instruction-headroom,
review-effectiveness, worker-permission-ergonomics, fleet-autonomy,
custom-steps, or whichever owns it). A surface the operator owns directly,
the worker briefs, gets its verdict reported to the operator instead. This
bundle's own outputs are the harness, the reports, and the step-record
hardening D-1 excepts.

**Alternatives considered:**
- Apply approved cuts here. Rejected because: it bypasses the owner's
  kickoff and review, and D-1 rules it out.

**Chosen because:** ownership stays where it is, and the owner reviews the
cut with this bundle's evidence attached.

### D-11: Auto mode is a trial arm, not an adoption  (S)

**Decision:** Running auto mode in the trial does not reopen fleet-autonomy
D-19. If auto mode wins, the report states the recommendation as a
fleet-autonomy D-19 delta and the operator decides; this bundle changes no
dispatch setting.

**Alternatives considered:**
- Exclude auto mode from the trial. Rejected because: the operator wants it
  adopted if it wins, which needs a measurement.

**Chosen because:** it lets the measurement happen without pre-deciding the
outcome or overriding a signed decision.

## Cross-cutting concerns

- **Security.** Runs never touch the real home, overlay, remote or ledger (save the pool
  slot and worker count),
  run in their own process namespace, and are never directed to fire a real
  known-bad call (REQ-B1.7, REQ-B1.8); the known-bad
  set is the safety bar for every arm; secrets are behind denyRead; the run
  token lives only in the environment and is scrubbed from records.
- **Cost.** Replays, benchmark runs and backtests spend weekly tokens; each
  experiment report states its own spend (REQ-F1.1).
- **Held-out eval.** The agents proposing review-doctrine cuts can read the
  backtest corpus the verdict is scored on; accepted at kickoff, with the
  operator approving each candidate list before runs (REQ-F1.4).
