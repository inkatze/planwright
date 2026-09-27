# Review effectiveness — Design

**Status:** Ready
**Last reviewed:** 2026-09-24
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` is a decision new in this bundle; `C, <bundle> D-<n>` is
one carried from another bundle and applied here.

## Decision log

### D-1: The deliverable spans the altitude ladder, and each piece is placed  (N)

**Decision:** The bundle is placed on every rung of the altitude ladder at
once. Doctrine (rules about how a review must think): the reviewer-basics
gate, claim-versus-code executed from both sides, the sibling sweep,
reproduction first, the declared adversarial pass, evidence naming its
process, and the blind review definition; these amend the rigor, lens, and
gate doctrine and add a new rule doc (Tasks 3 to 5). Capability (seams core
offers): the blind step in the steps catalog, the handoff bundle, the
miss-ledger grammar, the external step output contract, the backtest
corpus and harness. Mechanism: the skill instantiations, the scripts
filling those seams, and the guard rules. Local value: this repository's
own convergence chain and backend choices, which stay in its overlays;
the one overlay value this bundle changes is this repository's
convergence setting, moved from `/self-review` to `/polish` so the blind
pass runs here and the closeout window measures it (Task 10). The
observation reword (Task 15) is data hygiene under D-16, off the ladder.

**Alternatives considered:**
- Mechanism only: revamp the two skills' prose and leave the doctrine
  untouched. Rejected because: the measured misses come from rules the
  doctrine lacks (a gate, a sweep, a blind pass), and a rule buried in a
  skill is invisible to every other reader of the doctrine.
- Doctrine only: amend the rigor docs and let the skills follow through
  the drift ritual. Rejected because: the cost half of the goal is
  mechanism (handoff, delta, cadence), and the skills sit at their budget
  ceiling, so doctrine growth without the diet cannot land.

**Chosen because:** both altitude triggers fired (the seed claims were about
the review passes as a class, and elicitation kept producing doctrine-shaped
rules), so the placement is recorded here, cited from the goal, for the
kickoff lens pass to verify against the task decomposition.

### D-2: Reviewer basics run as a gate before the fan-out  (N)

**Decision:** The seven reviewer basics (acceptance coverage, description
versus diff, tests exercise the change, copies of a changed claim, callers
and consumers, scope fence, previous-iteration regressions) run as one gate
before the lens fan-out, and a gate finding halts the pass until it is
dispositioned. The gate is a coordinator step reading the handoff bundle
and the task contract; its mechanical parts (the scope fence, the
regression re-run) are scripts, its judgment parts are the coordinator's.

**Alternatives considered:**
- An extra lens inside the fan-out. Rejected because: a lens finding never
  blocks the pass, and the research shows round-2 findings come from
  incomplete or half-done rounds that the lenses then reviewed as if
  complete.
- A check at PR-body time, after the fan-out. Rejected because: cheapest,
  but the lenses would review a possibly incomplete change and the body
  would be checked after the pass that could have fixed it.

**Chosen because:** the basics are the checks a human reviewer runs first,
their misses were the largest prose class (a claim disagreeing with the
code) and the acceptance gap the operator named, and a gate makes the
fan-out's input a complete change.

### D-3: One handoff bundle, assembled once, shared by every lens  (N)

**Decision:** The coordinator assembles the handoff bundle once per pass
into a worktree-local directory under the repository's `.claude/`
(gitignored, beside the polish audit file): the diff, every changed file
whole, the callers of every changed symbol (found by symbol search over the
repository, a grep-based heuristic over the tracked tree with no new
dependency, its per-language limits recorded in the bundle), the unit's
task contract slice, the would-be PR title and body, and the tooling
output. Every
lens agent, the self-critique agent, and the blind pass receive the bundle
path and nothing else; no agent fetches its own diff slice. Doctrine and
the brief are resolved once per loop and their resolved paths recorded in
the bundle. The nearest seams, considered and reused: the machine-local
state home holds cross-unit state, not per-pass files; the polish audit
file already establishes a worktree-local `.claude/` artifact, so the
bundle sits beside it. The bundle is rebuilt per pass, in delta mode after
an iteration's fixes, before the post-fix sweep or blind pass reads it. A
lens agent that fails is retried once, then run
inline from the bundle and recorded as not context-independent; its
timeout is the execution backend's own agent timeout.

**Alternatives considered:**
- Each lens agent fetches the diff itself, as today. Rejected because:
  measured duplicate reads (50 of 70 file reads in one run, research seed §1), and no agent
  reads callers or whole files, which is the outside-the-diff miss class.
- The bundle embedded in every lens prompt. Rejected because: the prompt
  grows with the branch, and one copy of the same content per lens
  multiply cache-creation cost; a path is read once per agent.

**Chosen because:** it removes the re-fetch cost, gives every lens the
whole-file and caller context the misses needed, and is the same artifact
the blind pass consumes, so context independence and cost share one
mechanism.

### D-4: The sibling sweep is both a lens and a post-fix step  (N)

**Decision:** The sibling sweep runs twice: as a lens over the diff (for
every property the change introduces, where else does it hold?) and as a
step after every applied fix (for the property the fix corrected, where
else is it broken?). Both write findings into the same pass; the post-fix
sweep's findings enter the next iteration.

**Alternatives considered:**
- Post-fix step only. Rejected because: it catches the half-fix pattern but
  not twins the original diff introduced, which was the round-1 shape.
- Lens only. Rejected because: a fix's twins are caught only if the next
  pass lenses them, and delta-scoped re-discovery would not.

**Chosen because:** the research measured both shapes (round-1 sibling
misses, round-2 half-fixes), and the operator's own words on one PR were
that the previous round fixed the sites pointed at rather than the sites
that were wrong.

### D-5: Blind review on two axes; the blind pass is the confirming pass  (N)

**Decision:** A blind review is defined on a context axis (the reviewer
sees the repository at the branch head, the diff, the would-be PR body, and
the task contract, never the implementation transcript or the decline
ledger) and a generator axis (a different model
family only; a same-family session at another tier is context-independent
only). The blind pass
is `/polish`'s confirming pass and replaces the whole-branch scope of the
confirming iteration the loop runs today (that iteration is now
delta-directed, D-14): when an iteration produces nothing new, polish invokes the
blind skill, which reviews from a clean context; its findings enter
disposition unfiltered, so a wrongly declined finding can be resurrected.
An applied blind finding returns polish to iterating, and the next blind
pass is directed at the delta since the previous one over the whole-branch
handoff; each blind pass counts against polish's cap. A backend from a
different model family attached through custom-steps counts as the
generator-independent angle when present. The convergence criterion is
doctrine, not a preference: an adopter removes the blind pass only by
shadowing `gate-wiring`'s convergence criterion through the doctrine
overlay.

**Alternatives considered:**
- A blind pass in addition to the confirming pass. Rejected because: one
  more full fan-out per unit, on top of a confirming pass the research
  already found to be pure cost.
- A separate step after polish at the end of the convergence list.
  Rejected at kickoff because: an applied blind finding needs a loop back
  into polish, and custom-steps rules out re-running earlier steps.
- An opt-in knob, off by default. Rejected because: the capability-vs-style
  rule keeps preferences in overlays, but a rigor rule is not a preference;
  the same-context miss shape is measured, and an off-by-default rigor rule
  is the silent uneven rigor proportionality forbids.
- Per-step dispatch isolation as the blind reviewer. Rejected because: the
  fresh session is seeded with the author's brief and ledger, is the same
  model, and 52 of 57 measured nested runs ran inline anyway (research seed §1).

**Chosen because:** it makes the last pass of every unit independent at no
extra pass, and the two axes let the PR body say honestly which
independence the unit had.

### D-6: The blind reviewer is a handoff bundle plus a fresh foreground agent on every backend, as a thin nestable skill  (N)

**Decision:** The blind pass is a new thin skill, `blind-review`, declaring
`--nested`, invoked by `/polish` as its confirming pass and entered in
the steps catalog for standalone use, with its own allocation step keys. It reads the handoff bundle,
runs the discovery doctrine's lens fan-out and the reviewer-basics gate
from that bundle alone, and returns findings; it never reads the loop
ledger or the session transcript. On every backend it runs as a fresh
sub-agent given only the handoff bundle path, on each backend the
capability contract defines, in the foreground under stream-json since a
background agent's report is lost at turn end there.

**Alternatives considered:**
- A `--blind` mode of `/self-review`. Rejected because: that skill sits
  near its budget error line, and a mode that
  must suppress the ledger read and the brief detection would grow it.
- Backend-specific realization (fresh session where possible, sub-agent
  otherwise). Rejected because: two code paths for one contract, and the
  fresh-session path is what per-step isolation already tried.

**Chosen because:** one shape everywhere, the cheapest to reason about, and
the skill's own budget is fresh (where no agent can be spawned it runs
inline and the record says the blind angle did not run): it runs in its own
agent, so its closure is
charged alone and never adds to the polish and self-review chain; the lens fan-out is doctrine, so the thin
skill carries only the blind contract.

### D-7: The backtest corpus is a committed snapshot with a refresh script  (N)

**Decision:** The fixed external findings the research mined (PR, pre-fix
commit hash, file, line, category, miss reason, a paraphrased gist, a
replayable flag) are committed as a versioned corpus under the test
fixtures. A refresh script, run operator-local with the operator's existing
GitHub authentication and never in CI, rebuilds it into a new corpus
version from the repository's PR history and the miss ledger; it validates
each PR number as an integer, fetches the PR's head ref, and marks a row
unreplayable when its pre-fix commit is not in that ref's history. Every
recall comparison is made within one corpus version, so a refresh never
moves a baseline, and lens briefs cite the ledger's recurring classes,
never its rows, so no corpus row is copied into a lens brief; a declined
row's dismissal enters the replay only as its paraphrased corpus field,
never raw PR text. A corpus version is a `v<N>` directory; a baseline
records the version and the resolved model id. A class is a row's miss
reason, and a row counts as caught when any finding cites its file within
10 lines of its line: mechanical, fixed before the baseline run, and
chosen by the operator over category matching (the labels were about one
in five wrong) and a model judge (a second model step with no eval set). A replay harness
checks out a sample's pre-fix commits into isolated copies (REQ-C1.1), runs
one review pass (the pass under test's pre-fan-out steps plus one lens
fan-out, no fixes and no loop), and reports recall per class; a
`declined`-class row is replayed with its recorded dismissal seeded into
the coordinator's ledger, never the blind pass's input, so the harness
measures whether the blind pass re-raises it. The replayed session keeps
its own home and credentials; only the commands it executes see the
isolated copy. The corpus holds only public repository data and never a
line from the private reviewer.

**Alternatives considered:**
- Generated on demand from GitHub each run. Rejected because: never
  reproducible, needs authentication in CI, and the eval set must be
  held-out and versioned.
- A frozen snapshot with no refresh. Rejected because: new misses would
  never enter it, and the miss ledger would have no reader.

**Chosen because:** the LLM-quality decision domain requires a versioned,
held-out eval set for a load-bearing model step, and the operator asked to
use merged PRs as the record of what worked.

### D-8: The miss ledger is observation fragments with a fixed grammar  (N)

**Decision:** A miss is recorded through the existing observation-recording
helper with the slug `review-miss` and a text beginning
`review-miss(<lens>, <reason>): #<pr> <path>:` where `<lens>` is a
canonical lens name
and `<reason>` one of the tokens `outside-diff`, `runtime-tracing`,
`claim-vs-code`, `pruned`, `spec-conflict`, `lintable` (the research seed's
reasons, a twin-site miss carrying `pruned`), `declined`, or `other`; the PR number and path are the key the
refresh matches a fixed finding against. The backtest refresh and the
metric script are its readers; consumption follows the accumulator's drain ritual.

**Alternatives considered:**
- A dedicated TSV under the machine-local state home. Rejected because:
  machine-local never reaches the repository or another machine, and the
  existing-seam-reuse domain makes a parallel store the exception.
- Rows appended straight to the backtest corpus. Rejected because: the
  corpus would stop being a held-out set the moment a live miss entered it.

**Chosen because:** the accumulator already has a writer, a reader model,
hygiene screening, and a drain ritual; a grammar on the text is the whole
addition.

### D-9: Replay per task on the classes it targets, under a declared sample cap  (N)

**Decision:** Every task that changes a lens, a gate, or the handoff
replays the corpus rows in the miss classes it targets before it lands, and
records the recall it achieved against the baseline replay in its `Done
when:`; the landed-pass backtest (Task 13) replays the full sample (the default cap
applied to every class) once. The harness samples at random with a
recorded seed, one run per row, capped per class by a command-line value
with a documented default of five rows, not a config knob. A task lands
only when no targeted class catches fewer sampled rows than the baseline
did; improvement is recorded, not required, and the rule is fixed before
the first run, as the LLM-quality domain requires of a gate. A failed gate
is not re-rolled with a new seed without the operator. The corpus is not
held out from this bundle's own lens design, which studied the same
findings, so the replay is a regression guard only; the closeout window
over PRs merged after landing is the held-out measure. A baseline
records the model it ran on: a comparison across models is refused and the
baseline re-run, since a model change moves recall in every class.

**Alternatives considered:**
- Only at the landed-pass backtest. Rejected because: a regression in one
  task is found only at the end, after every dependent task built on it.
- The full sample on every task. Rejected because: strongest signal,
  highest token cost, on a bundle whose goal includes cost.

**Chosen because:** the LLM-quality domain says a changed prompt under a
gate needs its eval before landing, and the targeted subset keeps that
honest at a bounded price.

### D-10: This bundle's doctrine tasks wait for prose-disposition's shared-file edits  (N)

**Decision:** A task editing a file another Ready bundle's unmerged task
also edits names that task as a `Done when:` precondition. The first doctrine task
names the prose-disposition tasks that edit the Documentation lens and the
review skills' prose; the validation doctrine task names prose-disposition's
doctrine task; the diet task names instruction-headroom's review-skill
reclassification and prose-disposition's `/polish` instantiation; the
validation doctrine task also names human-gates' doctrine rewrite; the
execute-task wiring names prose-disposition's `/execute-task`
instantiation; the blind step and convergence wiring name
custom-steps' catalog, knob, and execute-task wiring tasks. This bundle's
scripts, guards, corpus, and handoff builder start immediately.

**Alternatives considered:**
- This bundle first, prose-disposition rebased onto it. Rejected because:
  it reopens a signed-off bundle's delta for a smaller change.
- No ordering rule. Rejected because: bundles editing the same doctrine
  lines concurrently produce merge conflicts on every PR, which
  the research measured as its own miss source.

**Chosen because:** the shared-file bundles are all Ready and smaller, and
the cross-bundle precondition is the only dependency form the task graph
admits.

### D-11: Validation order and the suite cadence  (N)

**Decision:** On an executable surface the first validation pass is
reproduction through the real surface, in an isolated copy (a fixture tree
or a fresh clone with the home and state home redirected, no push remote)
because a worktree shares refs, remotes, and credentials with the live
checkout; the bi-directional adversarial pass
is declared in each act-on-findings skill with the full pass as the
default; a positive result names its producing process; a tool-cited
mechanical finding is validated by its rule plus the diff-scoped check. The full
suite runs once per iteration after its fixes; each fix gets a diff-scoped
check (tests touching the changed files, plus the linters); the
Agent-resolvable predicate in `finding-categorization` is reworded
word-neutrally to read the diff-scoped check per fix and the full suite per
iteration.

**Alternatives considered:**
- Keep the full suite per fix. Rejected because: measured 400 to 800
  seconds per run, concurrent across workers, with about one in four runs
  falsely red under load in one sample (research seed §3).
- Keep three passes for every finding. Rejected because: a linter rule
  already grounds the finding; three passes there are ceremony.

**Chosen because:** the serious misses were runtime behaviour a targeted
test did not reach, and the suite cadence is the wall-clock and false-verdict
driver of the loop.

### D-12: The diet lands first, growth lands word-neutral, the chain is charged whole  (N)

**Decision:** The review skills' run-start set is reduced to what the
pre-flight needs, with every other doc point-of-use where the safety-floor
test allows, before any doctrine or skill prose this bundle adds to what
those skills load (a doc only the blind skill or `/execute-task` loads is
not in that closure); every
task adding prose names what it replaces and the start-load may not grow;
the budget guard charges the nested chain as one closure with its own error
line. The loop's audit record is written as deltas per iteration and
regenerated once at loop end, the angles record added to custom-steps'
post-pr regeneration; the polish audit file stops being overwritten per run and is resumed
when present, amending operator-dialogue D-16's cache-not-source framing
for the ledger part only; a ledger without the new header is treated as
absent (a fresh loop), never parsed, so a rollout never misreads an old file; the loop ledger persists so a killed loop
resumes.

**Alternatives considered:**
- Land the rules and ask for a budget raise. Rejected because: a raise is
  the last rung of instruction-headroom's ladder, and the measured cost has
  the instruction load as one of its terms.
- Regenerate the tables every pass as today. Rejected because: the
  research counted the per-pass tables among the ceremony that does not
  change the outcome.

**Chosen because:** zero slack was measured (research seed §2), and a bundle whose goal is cost
cannot start by adding words.

### D-13: The guards are lint rules plus small checks in the guard catalog  (N)

**Decision:** The recurring shell classes become a rule set (shell-lint
configuration where the linter has the rule, small grep-based checks under
the repository's check task where it does not), entered in the guard
catalog so the builder recommends them and their findings are
tool-grounded (Auto-applicable where the categorization's conditions and
disqualifiers allow: the echo and path rules are security-sensitive and
route to sign-off); emitter output linting, the count-versus-list guard, and
the test-vacuity guard are checks of the same shape.

**Alternatives considered:**
- Leave them to the lenses. Rejected because: the same portability and
  fail-open findings recurred almost verbatim across more than eight PRs (research seed §3),
  and a mechanical check cannot be pencil-whipped.
- One monolithic check script. Rejected because: the guard catalog is
  per-guard, and a rule that fires wrongly must be disableable alone.

**Chosen because:** the engineering doctrine defers to tooling wherever a
tool can enforce the choice, and the research counted the lintable share.

### D-14: Delta attention over whole-branch context, with regression re-verification  (N)

**Decision:** After the first pass of a loop, the lenses are directed at the
delta since the previous pass's head plus the files a fix touched, while
the handoff bundle still carries the whole branch for context; the
reviewer-basics gate re-verifies every earlier finding's fix by re-running
its recorded reproduction, so the un-lensed part of the branch is covered
by re-verification rather than re-discovery.

**Alternatives considered:**
- Re-lens the whole branch every pass, as today. Rejected because: every
  productive run pays the full fan-out again to find a few new items, and
  the ledger suppresses most of what it finds.
- Delta only, no re-verification. Rejected because: a fix that regresses an
  earlier finding outside the delta would be invisible.

**Chosen because:** attention and context are separable, and the
combination keeps coverage while cutting the repeated fan-out.

### D-15: Capability in core, values in overlays  (C, customization-overlay D-10)

**Decision:** The mechanisms land in core: the blind step entry, the
handoff builder, the miss-ledger grammar, the backtest harness, the guard
rules, and the metric script. The values stay in overlays: which external
backend supplies generator independence, this repository's convergence
chain, and any per-repository guard exclusion. No behaviour
value of one operator is baked into core; the blind pass's place as
polish's confirming pass is a rigor rule, not a preference (D-5).

**Alternatives considered:**
- Ship the operator's full chain (blind, then the external review
  commands) as the core default. Rejected because: those steps name
  commands that live outside planwright; that is style.

**Chosen because:** the boundary runs through the feature, as the
customization-boundary doctrine's worked example of convergence steps
already shows.

### D-16: Data hygiene of the corpus and the bundle  (N)

**Decision:** The corpus, the miss ledger, and every artifact this bundle
commits carry only this public repository's data: PR numbers, commit
hashes, paths, categories, gists. The private reviewer is never named,
quoted, or characterized beyond the generic Source entry, and its lessons
enter only as a Deferred entry gated on a permitted read. No committed
artifact (spec file, brief, research notes, corpus, ledger, results file,
PR body) this bundle writes names the bot reviewer product or the
external model backend (custom-steps' step tables, which carry the
operator's own step ids, are governed by that bundle);
they are "the bot reviewer" and "the external backend", and a committed
record names an attached step by its role, never by step or product name.
An operator exception is recorded in that artifact's PR body. The refresh
writes paraphrased gists and drops reviewer logins, and a hygiene screen
refuses a row naming a product from a name list kept in the machine-local
state home, never a committed one; the refresh refuses to run without the
list, and CI, which has none, runs the rest of the screen. PR bodies and results files carry repo-relative paths only.
The rule also reaches the observation fragments already merged, which are
reworded. The handoff bundle is gitignored and holds only
repository content.

**Alternatives considered:**
- Cite the private reviewer's design as prior art. Rejected
  because: private, and the operator asked for generic reference only.

**Chosen because:** the security-posture doctrine's artifact hygiene rule
and the operator's instruction coincide.

## Cross-cutting concerns

- **Security.** The blind agent and every lens agent read a bundle of
  repository content and run with the session's permissions; no credential
  or host detail enters the bundle, and no committed artifact names the
  bot reviewer or backend product (D-16). The guard rules for raw echo and
  leading-dash arguments are the security-posture doctrine's echo and path
  disciplines made mechanical.
- **Instruction budget.** Every doctrine amendment is word-neutral or lands
  after the diet; the new rule doc is point-of-use for the blind skill and
  the convergence phase only.
- **Overlay protection.** A doc that moves to point-of-use keeps its
  basename so overlay shadowing continues to resolve it.
