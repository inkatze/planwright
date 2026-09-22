# Human gates — Design

**Status:** Draft
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` new in this bundle; `C, <source>` carried from a recorded
decision elsewhere.

## Decision log

### D-1: Altitude — doctrine first, then policy knobs, then guard mechanics  (N)

**Decision:** The pinned seed claim ("the invariants were set when agents ran
without harnesses; re-evaluate what stays strict") is an altitude trigger, so
the altitude is fixed before any mechanism. The deliverable is, in order: a
**doctrine** rule (the gate test and the list it yields, owned by the
framework), a set of **capabilities** (policy knobs with core defaults an
overlay may set), and the **mechanisms** that enforce whatever the knobs
resolve to (profiles, guards, helpers). The task graph mirrors that order, and
a task that ships a mechanism before the doctrine it enforces is
mis-sequenced.

**Alternatives considered:**
- Ship the flip knob alone (issue planwright#379 as written). Rejected
  because: the sign-off coupling the issue itself names makes the knob unsafe
  until the approval act moves, and the same era artifact recurs in the merge
  and rewrite rules; fixing one spelling of it leaves the list inconsistent.
- Rewrite the skills' invariant sections directly. Rejected because: nine
  surfaces already diverge; without one doctrine source the tenth copy
  diverges too.

**Chosen because:** the seed claim and every source describe a policy
re-decision, not a missing feature; the autopilot reflex's altitude ladder
puts a rule about which acts stay human at the doctrine rung.

### D-2: The gate test and the list it yields  (N)

**Decision:** An act is a human gate exactly when it is irreversible for
other people (it changes shared history or ships something) or when it is the
approval act that ends the framework's review contract. Applying the test:
**human gates** are authorizing a merge, signing off a finding, and the
release publish (release-hardening keeps it); **policies** are the draft→ready
flip, a base merge into an owned branch, and reshaping never-pushed commits;
**composition contracts** are the never-push rules the review skills carry
(ownership between skills, never trust). Unchanged rules carry forward:
never act on a non-Ready spec, never auto-chain `/orchestrate` into
`/spec-kickoff`, never rewrite main, a protected branch, or a spec branch.
bootstrap D-26 gains a `Superseded-by: human-gates D-2` pointer; its body is
untouched.

**Alternatives considered:**
- Keep the list as bootstrap wrote it and only add knobs beside it. Rejected
  because: a list with no stated test cannot be extended honestly; the next
  act will be argued from era again.
- Make every reserved act a knob, merge included, with no floor. Rejected
  because: the merge is the approval act under `human` and no research source
  lets an agent decide ad hoc to merge; the test is what keeps the floor
  from being a taste.

**Chosen because:** the test reproduces every decision the repo already
made (kickoff-lifecycle D-6, merge-currency-guard D-9, the 2026-09-02
sign-off decision) and explains each one, which a list by fiat did not.

### D-3: Sign-off is the approval act; the marker is a trailer  (C, obs:77e452b4; issue planwright#384)

**Decision:** The human signs off a Needs-sign-off finding by the approval
act that lets the PR merge — the merge under `merge_policy: human`, enabling
auto-merge (or an approving review with it enabled) under `on-approval` —
never by the flip. The commit carries `Planwright-Sign-Off: PS-<n>` as a git
trailer stamped through the trailer helper, with `PS-<n>` written once and
never recomputed; the checklist regenerates from
`git log --format='%(trailers:key=Planwright-Sign-Off,valueonly)'` over
`base..head`, which excludes a revert by construction. `--marker subject` is
retired; `--marker title` is kept one release, broadened, and its removal is
a gated deferral. Handoffs print trailered SHAs and the trailer-aware log
command. Migration is one doctrine line.

**Alternatives considered:**
- `approved-if-merged` as the marker text. Rejected because: still a status
  claim, and an admin or bot merge would make mainline assert an approval
  nobody performed.
- Keep the subject suffix and add warnings. Rejected because: the leak onto
  mainline under merge-commit repos and the revert double-count are defects
  of the carrier, not of its wording.
- Trailer plus a subject suffix for `--oneline` legibility. Rejected
  because: it reintroduces the mainline leak; the SHA printout at handoff
  is the mitigation.

**Chosen because:** carried operator decisions; the trailer has in-repo
precedent (`Planwright-Task`), a parser instead of a grep, and immutable
ids.

### D-4: `ready_flip_policy` — two values, `agent` by default, worker-only  (N, `customization-boundary`)

**Decision:** `ready_flip_policy` resolves through `config-get.sh` and the
shared knob resolver with values `human` and `agent`; the shipped default is
`agent`. Under `agent` the skill that owns the unit's branch (the
`/execute-task` convergence run, or the review skill it delegates the
terminal step to) flips its own PR once D-5 holds; the orchestrator and tower
profiles keep their flip deny. `mark_spec_pr_ready_on_kickoff` stays a
separate knob for the spec PR and keeps its default. **Declared departure:**
customization-boundary asks a core knob to preserve today's behaviour by
default; this knob does not, because the prior default was an era artifact
the repo had already ruled a preference (merge-currency-guard D-9) and the
operator asked for the change (issue planwright#379). The departure is
recorded here, named in the release notes as a behaviour change, and is the
first fork the kickoff must reconfirm.

**Alternatives considered:**
- Default `human`, opt in to `agent`. Rejected because: the operator's
  stated intent and the #379 verdict; every adopter running a fleet hits the
  same bottleneck, and one line in an overlay restores the old posture.
- A `when-no-pending-sign-off` middle value. Rejected because: once the
  flip approves nothing (D-3) the carve-out has no content.
- Let the tower or orchestrator flip too. Rejected because: neither owns a
  task branch, and the preconditions are computed where the work happened; a
  worker that dies after converging is re-dispatched, and the re-run flips.

**Chosen because:** the operator chose it; the flip is reversible
(`--undo` exists) and approves nothing, so it fails the gate test on both
arms.

### D-5: Flip preconditions compose existing gates and leave a PR record  (N, `decision-domains` existing-seam reuse)

**Decision:** An agent flip fires only when, on the current head: the
ready-guard defers (currency and mergeability, the fail-closed floor as
shipped); the head SHA's check rollup is a positive green within a bounded
wait, reusing the `kickoff_ready_ci_wait` mechanics under a sibling knob
`ready_flip_ci_wait` with the same default; the review loop's handoff record
names that head (the record gains a head-SHA line if it lacks one); and the
spec's `## Awaiting input` holds
no bullet for the unit. One helper (`scripts/ready-flip.sh`) evaluates the
predicates deterministically, writes a PR comment naming the policy value,
the head SHA, and each predicate's evidence, and only then issues the flip
through the surface the ready-guard intercepts. Any failure leaves the PR
draft and parks the pending flip under `## Awaiting input` naming the failed
predicate, the same re-entry `/spec-kickoff` uses.

**Alternatives considered:**
- Let the skill judge readiness from its own transcript. Rejected because:
  an instruction an LLM follows can be pencil-whipped; a comparator cannot.
- Skip the PR record. Rejected because: the flip is now performed by a party
  other than the human who will merge, and the record is what lets the human
  see why the PR is in front of them.
- A new currency check. Rejected because: the ready-guard already is one and
  is flipper-agnostic by design.

**Chosen because:** every predicate already exists as a shipped, tested
mechanism; the helper only sequences them.

### D-6: `merge_policy` — a tiered knob whose default keeps today's posture  (N, research)

**Decision:** `merge_policy` takes `human`, `on-approval`, and `policy-class`,
default `human`, malformed or unresolvable → `human`. Under `human` a person
authorizes and executes. Under `on-approval` the person's act is enabling
GitHub auto-merge (or, with a detected identity split per D-14, an approving
review with auto-merge enabled); GitHub executes when required checks pass;
planwright builds no execution path and agent sessions stay denied every
merge spelling. Under `policy-class` a deterministic evaluator
(`scripts/merge-class.sh`) admits a PR only when every predicate holds: no
`Planwright-Sign-Off` trailer in `base..head`, no changed path in a
hard-disqualifier zone, no live Awaiting-input bullet, the D-5 preconditions
on the head, and the adopter's bounds (`merge_class_max_lines`,
`merge_class_exclude_paths`); an admitted PR gets a PR comment naming each
predicate's evidence and is merged through one helper with the repository's
sanctioned strategy; anything else falls to `on-approval`.

**Alternatives considered:**
- Merge stays permanent with no knob. Rejected because: the operator asked
  for the three shapes, and each is an established practice (merge queues,
  dependency bots, risk-tiered agent policies).
- `on-approval` executed by a planwright helper watching for a review.
  Rejected because: under a shared identity the helper cannot tell a human
  approval from one the agent could post, and GitHub already executes
  auto-merge.
- Let the agent classify risk with a model. Rejected because: the one
  production report found (Ona) bars engineers from self-classifying and
  uses mechanical criteria; a model in the path is the same self-classification.

**Chosen because:** the default changes nothing; each value maps to a shape
mature systems converged on; the class can never contain a sign-off item, so
the approval gate survives every value.

### D-7: A worker merges its base into its own branch; conflicts are a knob  (N)

**Decision:** The allowance is the act "merge the PR base into the branch
this session owns", enforced across `git merge`, `git pull`, and the helper.
`converge-sync-main.sh` remains the sanctioned path and gains a `resolve`
mode; the worker profile drops its blanket `git merge` deny in favour of a
deny-emitting check that refuses any merge whose current branch is not the
session's unit branch or whose source is not the PR base. `worker_merge_conflicts`
defaults to `halt` (abort, clean tree, park under `## Awaiting input` with
the paths); `resolve` lets the worker commit the resolution and flag the
commit in the PR body. Orchestrator and tower profiles keep their deny; the
local-main fast-forward stays the only sanctioned local-main mutation.

**Alternatives considered:**
- Keep the deny and route every sync through the tower. Rejected because:
  two observations show it failing under load, and `git pull` already
  bypasses the deny.
- Allow any `git merge` to workers. Rejected because: the act is scoped to
  the owned branch; a merge into main or a sibling branch is exactly what
  the floor exists to stop.

**Chosen because:** plain merge creates commits and rewrites nothing, so it
never met the gate test; the scoping keeps the floor.

### D-8: Rewrite allowances — never-pushed local commits; force-push only on request  (N)

**Decision:** Amend, squash, fixup, and rebase are allowed to a worker by
default for commits no remote-tracking ref contains, on its own unit branch;
the guard evaluates `git branch -r --contains <sha>` before allowing and
refuses otherwise (a local-state read, unlike the ready-guard's server-only
predicate: whether a commit was pushed is a fact about this clone, and a
stale remote-tracking ref errs toward refusing). A force-push is performed only by the tower, only on an
explicit operator request in the same turn, after a confirmation that names
the remote commits the push drops (conforming to `check-confirmation.sh`),
never to main, a protected branch, or a spec branch, and never from a
standing decision. The commit-range lint failure is the named reason for
that path, and the skill whose gate reports it names the path in its
handoff. The secret purge stays human-run; the tower may prepare the command
and rotation checklist.

**Alternatives considered:**
- Keep the full prohibition. Rejected because: a never-pushed commit is
  irreversible for nobody, and a pushed bad subject currently fails CI with
  no sanctioned repair.
- Let workers force-push their own branch. Rejected because: a pushed commit
  may already be reviewed, cited, or checked out elsewhere; the operator's
  stance is tower-on-request only.

**Chosen because:** the gate test draws the line at "irreversible for other
people", which is the push, not the commit.

### D-9: Enforcement derives from the resolved policy; one spelling list  (N)

**Decision:** Acts no value can permit stay in the deny profiles as the
floor (merge or rewrite of main, a protected or spec branch; an agent merge
outside `policy-class`; a rewrite of a pushed commit outside D-8's tower
path). Acts a policy can permit leave the profile deny lists for the tiers
the policy can grant them to, and a deny-emitting **policy guard**
(`scripts/policy-guard.sh`, the ready-guard's sibling in modality) enforces
the resolved value at PreToolUse: it reads the knob through the shared
resolver, deterministically and within a wall-clock bound, and denies on any
read failure. One fixture file (`tests/fixtures/reserved-control-spellings`)
lists every refused spelling, and one test drives it through the tower
queue's reserved-control check, the ready-guard, both command guards, both
profiles, and the policy guard.

**Alternatives considered:**
- Generate the profiles from the policy at dispatch. Rejected because: a
  profile is read once at launch and cannot follow a knob that changes
  mid-session; the guard can.
- Merge the guard implementations into one script. Rejected because: they
  differ in modality (allow-only versus deny-emitting) and each has its own
  adversarial suite; one fixture list is what the observation asked for.

**Chosen because:** deny precedence means a profile can never be the
policy-following layer, and worker-permission-ergonomics D-1 already makes
the profile the floor and the hook the refinement.

### D-10: One doctrine source, three rule kinds, retired phrasings purged  (N)

**Decision:** `doctrine/human-gates.md` states the gate test, the list, and
each rule's kind (human gate / policy with knob and default / composition
contract with owner). Every skill invariant section is rewritten to cite it,
split by kind, word-neutral or net-negative under `check-instructions.sh`.
Every doc surface restates by citation. The retired phrasings of the old
rule enter the purged-identifier list so the CI screen refuses their return.

**Alternatives considered:**
- Keep per-skill lists and sync them by review. Rejected because: that is
  the state that produced nine divergent copies.
- A new checker that diffs prose against doctrine. Rejected because: the
  purged-identifier screen already refuses retired phrasings and the
  doctrine-index check already pins the doc's presence.

**Chosen because:** one source plus a mechanical screen against regression
is cheaper than a prose checker and is what the repo already does for other
retired vocabulary.

### D-11: The reviewer-request side effect is verified, then corrected narrowly  (N)

**Decision:** Before any fix, the mechanism (requesting a reviewer on a
draft PR un-drafting it) is verified against gh and GitHub documentation
and a live probe on a scratch PR. Whichever holds, planwright's own
review-request surfaces verify the draft state after the request and, if
un-drafted, re-draft through a helper that is the only sanctioned
`gh pr ready --undo` spelling for an agent; the guards allow that helper
and refuse every other undo spelling.

**Alternatives considered:**
- Switch to the REST transport on the assumption it lacks the side effect.
  Rejected because: unverified; the observation itself says so.
- Allow `--undo` generally. Rejected because: an un-flip is a status change
  on a surface a human may be watching; the narrow helper keeps it an
  auditable corrective.

**Chosen because:** research before mechanism; the corrective is the
smallest allowance that closes the silent bypass.

### D-12: One commit per finding yields to green commits  (N)

**Decision:** Where Needs-sign-off findings are not file-isolable or share a
regression test, one commit carrying every affected finding's trailer is
conforming; the checklist discloses the shared commit and gives a per-item
revert recipe. Where findings are isolable, one commit each remains the
rule.

**Alternatives considered:**
- Split anyway and accept red intermediate commits. Rejected because: it
  trades a reviewer convenience for a broken bisect.

**Chosen because:** the observation resolved it this way live and disclosed
rather than hid it; the rule only names what happened.

### D-13: Approval semantics stated at the point of use; attended runs apply then review  (N)

**Decision:** The generated pending-sign-off section states which act
approves its items and that rejection is a revert before that act; the
checkbox is dropped or relabelled so it does not read as the control. The
attended path of each gate-wired skill states the apply-then-review default
in the same words as the unattended path.

**Alternatives considered:**
- Leave the semantics in gate-wiring only. Rejected because: the repo author
  could not tell whether to approve their own items; doctrine nobody has
  open is not a point of use.

**Chosen because:** both observations name the fix; it is prose only and
lands inside surfaces the bundle already rewrites.

### D-14: Agent identity — detected and recommended, never required  (N, research)

**Decision:** Every policy value works under a shared GitHub identity
through client-side enforcement. planwright detects, at the point a policy
acts, whether the agent session's login differs from the PR author's; when
it does, the docs' recommended setup (a GitHub App on an organisation repo,
a machine user on a personal one) is in effect and an approving review by
the human counts as the `on-approval` act, self-approval being impossible
server-side. The docs recommend the split and say why; no value refuses to
run without it.

**Alternatives considered:**
- Require a distinct identity for the agentic values. Rejected because: on a
  personal repo a GitHub App cannot open PRs and a machine user costs a
  second credential; the operator's own repo runs agents under their login.
- Ignore identity. Rejected because: a detected split gives a
  server-verified approval path at no cost, and the docs would otherwise
  leave adopters to rediscover the self-approval rule.

**Chosen because:** capability in core, value in overlay; the split is the
better posture and the shared identity is the common one.

## Cross-cutting concerns

- **Security posture.** Every guard this bundle adds is deny-emitting, so
  it inherits the ready-guard's risk model: a missed deny defeats it, a
  false deny blocks work. Each gets the adversarial fixture treatment the
  ready-guard has, no model in the decision path, bounded runtime, and
  fail-closed on any doubt. Policy reads are data, never evaluated.
- **Decision-domains walk.** Touched and decided: auth (D-9, D-14),
  api-surface and secrets-configuration (the knobs, D-4, D-6, D-7),
  observability (the PR records, D-5, D-6), versioning (the one-release
  `--marker title` deprecation, D-3), LLM output gates (no model in any
  guard), human comprehension (D-13), existing-seam reuse (D-5, D-9).
  Touched, not decided here: concurrency between a policy change and a guard
  read mid-session is accepted as last-write-wins at PreToolUse time.
- **Instruction budget.** Every skill prose change is measured by
  `check-instructions.sh`; a change that grows a saturated surface is
  reworked as a citation, never landed over budget.
- **Release note.** The `ready_flip_policy` default is a behaviour change
  for adopters and is called out as such; the other knobs preserve today's
  behaviour.
