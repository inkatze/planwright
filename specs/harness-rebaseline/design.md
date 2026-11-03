# Harness rebaseline — Design

**Status:** Draft
**Last reviewed:** 2026-11-03
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` new in this bundle; `S` a decision the operator settled in
the drafting session.

## Decision log

### D-1: Altitude — a measurement harness plus reports  (S)

**Decision:** The deliverable is a measurement harness (kit, benchmark,
evals, trial profiles) and one report per experiment. It never edits
doctrine, skills, guards or settings on main; a cut exists here only as a
candidate diff applied in a disposable worktree.

**Alternatives considered:**
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

**Decision:** A cut is kept only when the review eval set's catches stay at
the baseline or better and benchmark quality does not drop. Tokens and
prompts saved are recorded and reported, and never outweigh a drop. Records
are comparable only when they differ in the one variable an experiment
changes, so every record names its harness.

**Alternatives considered:**
- A weighted score trading catches against tokens. Rejected because: it
  turns a safety regression into a price, and the eval set is too small for
  a weighting to be meaningful.
- Keep a cut on reviewer judgment alone. Rejected because: judgment is what
  produced today's untested layering.

**Chosen because:** the operator set the bar; a one-sided rule is simple to
apply and cannot be gamed by a large token win.

### D-3: The benchmark replays recent merged tasks  (S)

**Decision:** The benchmark is three to five recent merged tasks (candidates
named at drafting: test-throughput Task 12, mission-control Task 13, and one
visual flight), each replayed from a fresh worktree at its original base
commit with the original brief, and graded against the merged PR.

**Alternatives considered:**
- Synthetic tasks written for the benchmark. Rejected because: they measure
  what the author expected, not the work planwright actually does.
- Live tasks as they come. Rejected because: no two are comparable.

**Chosen because:** real tasks with a known merged answer give a quality
reference, and a fixed base commit makes runs repeatable.

### D-4: Three permission arms; the hook is the main arm  (S)

**Decision:** The trial compares today's allowlist with tower vetting, a
sandbox plus a deterministic PermissionRequest hook, and auto mode. The hook
arm is the main candidate and auto mode the comparison. A fixed known-bad
call set, built from the 2026-11-03 categories that held real catches, is the
safety bar; the adoption bar is blocking all of it while at least halving
prompts. Secrets are protected by the sandbox's denyRead.

**Alternatives considered:**
- Auto mode alone. Rejected because: Anthropic's own engineering post
  reports a material false-negative rate on overeager actions, which is the
  class the tower catches today; it also reopens fleet-autonomy D-19.
- Widen the static allowlist. Rejected because: the 2026-11-03 categories
  show the prompts are shaped by context (temp paths, own branch), which a
  static pattern cannot judge.

**Chosen because:** a deterministic hook keeps D-18's floor and can carry
the guards that already caught real harm, while auto mode gives a measured
reference instead of an opinion.

### D-5: The hook denies what it cannot classify, with a reason  (S)

**Decision:** The hook never asks the tower. It allows, or denies with a
reason the worker can act on (for example "write the probe to a mktemp
script and run it with sh"). An unclassified call is denied with a reason.

**Alternatives considered:**
- Ask the tower on uncertainty. Rejected because: that is today's prompt
  flood under another name.
- Allow on uncertainty. Rejected because: it fails open on exactly the
  calls the known-bad set exists to stop.

**Chosen because:** a reasoned deny lets the worker reshape the call, which
the 2026-11-03 data shows is usually possible.

### D-6: Offline replay first, then live runs in disposable environments  (S)

**Decision:** The 505 recorded calls replay offline through every arm that
decides deterministically before any live run. Live runs use a disposable
worktree, home and overlay.

**Alternatives considered:**
- Live trial only. Rejected because: it spends a full fleet run to learn
  what a replay shows in minutes, and it risks the real environment.

**Chosen because:** the replay is cheap and catches a broken profile before
it touches anything real.

### D-7: An eval precedes every doctrine cut  (N)

**Decision:** Review doctrine cuts are measured against the existing review
eval set. Execution doctrine cuts wait for an `/execute-task` eval covering
its invariant refusals, which must pass on the baseline first.

**Alternatives considered:**
- Cut by word count and reading. Rejected because: a regressed invariant
  refusal is invisible to both (obs:3d5b7d08).

**Chosen because:** the observation recorded this ordering as a
prerequisite, and `/execute-task` has no eval today (obs:260e0756).

### D-8: Guards — hard limits fixed, friction guards removable on evidence  (S)

**Decision:** Every guard gets a catch and friction log. The hard limits (no
merge, no push to a protected branch, no force push) stay whatever they
cost. Any other guard may be recommended for removal only when it shows no
real catch over the trial window and measurable friction. The
evidence-integrity checks are hardened, not cut, because a faked step record
got past them on 2026-11-03.

**Alternatives considered:**
- Keep every guard out of scope. Rejected because: the operator brought the
  git and PR guards into scope; some exist only for friction.
- Measure the hard limits too. Rejected because: their worst case is
  irreversible, which no friction count outweighs.

**Chosen because:** it removes friction only where the log proves it safe
and strengthens the one class of check that was actually beaten.

### D-9: Verification loops scale to diff size, default cap two  (S)

**Decision:** The experiment measures polish rounds and lens fan-out sized
to the diff, with a default cap of two polish rounds, and separately
measures removing self-check subagents.

**Alternatives considered:**
- A fixed lower round count for every diff. Rejected because: large diffs
  do earn extra rounds; the waste is on small ones.

**Chosen because:** five rounds on a small helper was the observed waste,
and Anthropic's Opus 5 guidance warns that subagents multiply cost.

### D-10: Findings land through the owning bundles  (S)

**Decision:** An approved cut becomes a pending note or amendment request
for the bundle that owns the surface (instruction-headroom,
review-effectiveness, worker-permission-ergonomics, fleet-autonomy, or
whichever owns it). This bundle's own outputs are the harness and the
reports.

**Alternatives considered:**
- Apply approved cuts here. Rejected because: it bypasses the owner's
  kickoff and review, and D-1 rules it out.

**Chosen because:** ownership stays where it is, and the owner reviews the
cut with this bundle's evidence attached.

### D-11: Auto mode is a trial arm, not an adoption  (S)

**Decision:** Running auto mode in the trial does not reopen fleet-autonomy
D-19. If auto mode wins, the report states the recommendation as a D-19
delta and the operator decides; this bundle changes no dispatch setting.

**Alternatives considered:**
- Exclude auto mode from the trial. Rejected because: the operator wants it
  adopted if it wins, which needs a measurement.

**Chosen because:** it lets the measurement happen without pre-deciding the
outcome or overriding a signed decision.

## Cross-cutting concerns

- **Security.** Trial runs never touch the real home, overlay or ledger
  (REQ-B1.7); the known-bad set is the safety bar for every arm; secrets are
  behind denyRead.
- **Cost.** Replays and benchmark runs spend weekly tokens; each experiment
  reports its own spend.
