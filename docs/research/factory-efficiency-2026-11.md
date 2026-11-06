# Factory efficiency, efficacy and cost: what we have trails for (2026-11)

A research snapshot taken on 2026-11-06 at the operator's ask, before any
spec is drafted. planwright now runs as a factory: one mission-control hub,
many workers, reviewers and walkers a day, mostly unattended. Waste in that
mode is noticed only once its effects are large. This report inventories
every trail the repository and GitHub hold on cost, efficiency and efficacy,
says what was acted on and what is still open, measures what could be
measured cheaply, and names the gaps.

Sources are this repository (specs, observations, doctrine, docs, scripts,
config, git history, gitignored step records in worktrees) and GitHub (PRs,
CI runs). Nothing outside the repository and GitHub was read. Paths are
repository-relative; `E/` is `specs/_observations/entries/`, `A/` is
`specs/_observations/archive/`. The asks are recorded as obs:d7b6b586 (this
report and the cost-awareness asks), obs:e97aa5bb (`/handoff`) and
obs:bc9ff4f3 (offload windows).

## Top findings

1. **Efficiency is not a core, always-on property anywhere.** Rules that
   touch it are scoped: proportionality (`doctrine/proportionality.md`), the
   work-placement axioms (`doctrine/work-placement.md`), instruction budgets
   (`doctrine/instruction-hygiene.md`), and mission control's "cost is
   declared" for its own duties (`doctrine/mission-control.md`). No doctrine
   makes token, dollar or wall-time waste a standing concern of every skill
   and run. The one spec built to measure cost against quality,
   `specs/harness-rebaseline/` (Ready), has no task landed.
2. **CI wall time went from about 2 minutes (July) to about 60 minutes
   (November), mostly from the platform matrix, not tests.** macOS and Alpine
   began running on every PR on 2026-10-30 (`d59e99f6`); macOS shards run 8
   to 27 minutes and can first wait up to about 80 minutes for a runner
   (runs since 11-01). Linux shards run 2 to 5 minutes.
3. **The test suite grew about tenfold in four months, and its budgets
   followed the growth instead of limiting it.** 41 test files at v0.2.0,
   447 at v0.67.0. The suite total budget was raised three times in a month,
   then replaced by a per-file mean whose own comment says adding files is
   free (`config/test-time-budget.yml`). No rule prunes or consolidates tests.
4. **Nothing runs only the tests a change affects.** Every PR runs the whole
   suite on three platforms (`.github/workflows/ci.yml` has no `paths:`
   filter), and `/execute-task` runs the full local suite before convergence
   even on an existing PR. The designed fix (`full_suite_evidence` and
   `local-then-ci`; `specs/test-throughput/` Tasks 10, 16 and 17) is unbuilt.
5. **Task build time rose about sevenfold from July to October, and about
   as much at equal PR size, then fell back in November.** Not a within-spec effect (task 1
   versus task N shows no trend). The drivers with the strongest evidence are
   the slower, broader gate and more review steps per unit (polish, gemini
   panel and cubic stacked on most October units). Polish is the largest
   recorded wall-time sink.
6. **The cost machinery mostly ships dark.** Model allocation adapts nothing
   by default (`allocation_adaptation: "off"`, `config/defaults.yml`),
   per-step tiers have no caller, the allocation feedback loop is wired but
   never fires (with adaptation off nothing escalates), the stale-worker
   reaper only observes (`fleet_sweep_reap: observe`), and the heavy-run
   admission check (`mc-budget.sh admit heavy`) has no caller.
7. **Spend is invisible.** No token or dollar figure is tracked against a
   budget anywhere; the only token readers are two review-effectiveness eval
   tools (`scripts/review-cost.sh`, `scripts/review-backtest-reviewer.sh`).
   A dollar ceiling was "parked as a pending seed" by `specs/fleet-autonomy/`
   and the seed was never written.
8. **Idle sessions are retired automatically only when their tracked PR
   merges or closes.** A reviewer, panel
   or offload session with no tracked PR is never retired, and the offload
   tmux rung names every window `offload-<pid>`.
9. **Observations pile up unconsumed in exactly these themes.** 859 open
   fragments; whole families recur (spawn cost, gate locks and pool waits,
   secret scan crossing worktrees, allocation never wired) without a
   consuming spec.

## The operator's asks: where each one stands

| Ask | Covered today | Smallest change | Home |
| --- | --- | --- | --- |
| 1. Change-only watcher instead of sweep ticks | Mostly. The runner and tick are already change-gated; the 1M-token tick was a hub's own timer (obs:1f599c9d) | A change watcher over the forge snapshot and due follow-ups; quiet hours; skill forbids self-scheduled wakes | mission-control amendment plus one task |
| 2. Retire idle sessions by default; idle count and cost on the panel | Only sessions with a tracked PR, once it merges or closes | An idle-retire knob and a digest `idle` record | mission-control amendment (REQ-D1.5, REQ-F1.1) plus a task |
| 3. Doctor proposing the minimal permission set | Close: Task 20 posture check, draft PR #844 | A `propose` verb diffing duty verbs against loaded allow rules | Amend Task 20 while in flight |
| 4. Spend in the loop, top spenders, cheaper tiers, launch estimates | Account usage percentages only | A `spend` budget dimension, a daily by-kind report, cheaper shipped tiers for mechanical kinds, an estimate clause before fan-outs | mission-control amendment plus a task; tier defaults under model-allocation |
| 5. Context size: hubs self-succeed at breaks | Recorded already: obs:32bde2c6, obs:3b1fad05, obs:1f599c9d (PR #857) | As those observations state | mission-control amendment |
| 6. Offload windows named and closed | Naming is possible (`--name`) but unused by default; no close path a finished session can reach | Default name from the unit; a retire verb on the dispatch seam | offload or fleet-lifecycle-closure amendment |
| /handoff duty inventory | Partly: the handover file carries items and sessions, not duties | A `duty` record plus an inventory verb sorting each duty | mission-control amendment plus a task |
| Test cost and growth | Sharding, per-file budgets, the gate pool | Ship `full_suite_evidence`; gate macOS per PR on what changed; a growth and pruning rule | test-throughput open tasks plus a new rule |
| Task build time | Step timings in step records since 2026-10-11; no per-unit record of wall time, tokens and rounds | Record per-unit wall time, tokens and rounds | harness-rebaseline REQ-A1.1 |

<details>
<summary>Detail per ask</summary>

**1. Polling.** `scripts/mc-watch.sh` runs every
`mission_control_runner_interval` (1m) without a model; watchers emit
edge-triggered events through `mc_announce` (`scripts/mc-lib.sh`), once per
key until the item clears, and
`scripts/mc-wake.sh tick` sends nothing when nothing is pending; the mod's
tick submits only on a wake to an idle session
(`hooks/mission-control/register.tsx`). A full sweep happens only at
bring-up (`skills/mission-control/SKILL.md`). Gaps: no watcher emits PR
transitions (CI red or green, a new thread, approval, mergeability, a head
move outside the readiness case; the snapshot in REQ-M1.1 and D-12 holds
these fields but emits nothing), due follow-ups (`mc-kb.sh followup due`) are
never evented, there is no quiet-hours hold on hub wakes, and the skill does
not forbid model-side scheduled wakes. Smallest change: one bash 3.2 watcher
that keys `<pr>=<head|ci|threads|mergeable|approval>` and due follow-ups,
reuses `mc_announce`, and is armed through `config/duties.yaml`; a
quiet-hours knob honoured by `mc-wake.sh relay` and `tick`; the skill fix
from obs:1f599c9d. Touches REQ-E1.2, REQ-M1.1, REQ-M1.3, D-12 and a new knob
clause. Retiring "sweep everything" ticks is already the spec's position;
what remains is coverage, so the hub never needs one.

**2. Idle sessions.** REQ-D1.5 and D-10 say a finished session is retired by
mission control. The only automatic retirer of finished worker sessions is
`mc-keeper.sh sweep`, and only for sessions tracked with `--pr` once that PR
is merged or closed.
`mc-stall.sh` classifies `idle` but raises no event for it. The panel digest
(`scripts/mc-panel.sh`) shows flights, waiting count, budget rung and
headroom; no idle count, no cost. Smallest change: define finished as `idle`
held past a new `mission_control_idle_retire` knob for a session with no
tracked open PR or whose deliverable is reported; retire it through the
launcher with the act logged; add an `idle` digest record from the samples
`mc-stall` already keeps. Related: obs:083b73d4 (panel counted dead rows as
in flight; open PR #848), draft PR #842 (closes the permission requests a
finished stream-json worker left waiting).

**3. Permission denials.** No `doctor` or prompt counter exists. The
auto-approve hook logs allows only (worker-permission-ergonomics REQ-H1.4).
`scripts/mc-proposals.sh` with `config/denial-knobs.tsv` turns repeated guard
denials into knob proposals. mission-control Task 20 (D-32, REQ-G1.5; draft
PR #844) derives a pre-approval list from the scripts the skill and
`config/duties.yaml` invoke. Smallest change: a `propose` verb on that
posture script that diffs the enabled duties' verbs against the loaded allow
rules and prints the missing rules as an operator-applied change; counting
deferrals needs a REQ-H1.4 amendment.

**4. Cost signals.** `scripts/fleet-usage-gate.sh` maps account session and
weekly percentages to a restriction ladder; mission-control Task 28 (dynamic
admission from account headroom, REQ-L1.7, D-41) is not landed.
`scripts/mc-budget.sh` dimensions are sessions, polls per hour, context
steps, host load and a watcher spend class, with no tokens or money
(REQ-L1.2, D-17; obs:af17332a). Launch tiers resolve per kind in
`scripts/mission-control-launch.sh` (reviewer to `execute_step`, ad-hoc to
`offload`, tower and mission-control to `orchestrate_dispatch`, all three
`inherit` by default; worker and orchestrator to `execution` and
`bookkeeping`, unset by default); no key exists for research or walks.
Smallest change: lift `review-cost.sh`'s token reader into a `spend`
dimension with an optional budget in either unit (tokens or dollars; the
program's usage rule needs dollars for enterprise accounts, obs:af17332a),
shown on the panel line and
status; a daily by-kind verb keyed on launcher kind; cheaper shipped defaults
for reviewer, research and walk kinds; a skill clause stating a rough
estimate before fan-outs and panels.

**5. Context size.** REQ-L1.5 and D-29 define the trigger
(`mission_control_handover_context: 70`, wakes, compactions); REQ-L1.8 and
D-42 make an attended session compact instead, and Task 30 would hard-code
that. The three PR #857 observations already state the smallest changes;
Task 30 should be reconsidered before dispatch.

**6. Offload windows.** `scripts/offload-dispatch.sh` names a tmux window
`offload-$$` unless the caller passes `--name` (tmux rung only), and opens it
with `tmux new-window -d`. `scripts/mission-control-launch.sh retire` kills
only windows for launches it registered; `scripts/fleet-cleanup.sh window`
reclaims only windows whose panes are all dead and refuses the caller's own,
so a finished interactive worker whose process is still alive is never
reclaimed. In the relayed report, the owner's raw `tmux kill-window` was
refused by the classifier. Smallest change: default the window name from
the unit (`offload-<unit>`, or the caller's `review-<pr>-<lens>`); the
dispatch seam already registers the window id as its handle, so add a
`retire <handle>` verb that closes exactly that window; the owner then
closes it through a planwright script its permission profile already
allows, never a raw tmux call. Touches the offload skill's dispatch contract and the tmux row of
`doctrine/fleet-coordination-floor.md`.

**/handoff.** `scripts/mc-handover.sh write` records program, predecessor,
rules digest, open item ids and live session handles; `verify` checks the
successor against the file, and `take`, `release` and `resume` move the
holder (Task 16). `scripts/mc-duties.sh` lists duties and
armed watchers; `mc-kb.sh inventory-refresh` builds `kb/mechanisms.tsv`;
`mc-proposals.sh` maps a repeat onto the smallest mechanism;
`doctrine/autopilot-reflex.md` is the doctrine (name the gates, automate up
to them, verify the burden is gone). Gap: nothing inventories what a
predecessor was doing by hand, and nothing sorts it into covered,
mechanizable or judgment; a tower or ad-hoc hub has no path in (tower
takeover is Task 22, which waits on Tasks 21 and 32). Smallest change: a `duty`
record kind in the handover file and an `inventory` verb that classifies each
duty against the duty catalog, the mechanism inventory and the shipped
scripts (`covered <mechanism>`, `mechanizable <smallest row>` through
`mc-proposals.sh` selection, or `judgment`), run by a `/handoff` entry so the
successor arms the covered ones and proposes the rest.

</details>

## Measurements

### Test suite and CI growth

| Tag | Date | Test files | Test lines | Assertion lines | CI median (PR runs) |
| --- | --- | --- | --- | --- | --- |
| v0.2.0 | 06-30 | 41 | 16.8k | 472 | 1.9 min (July) |
| v0.24.0 | 07-19 | 98 | 44.8k | 1,592 | 2.1 min (late July) |
| v0.35.0 | 08-31 | 166 | 81.5k | 3,235 | 2.9 min (late Aug) |
| v0.45.0 | 09-24 | 218 | 112.0k | 4,578 | 7.2 min (late Sep) |
| v0.51.0 | 10-04 | 258 | 135.4k | 5,582 | 10.9 min (early Oct) |
| v0.62.0 | 10-20 | 359 | 180.3k | 9,744 | 5 to 6 min (Linux sharded) |
| v0.67.0 | 11-06 | 447 | 214.3k | 13,276 | 63.5 min (Nov; p90 95.9) |

The recorded per-file seconds in `config/test-durations.tsv` rose from 2,823 s
(358 rows, `cd9fe5fe`, 10-20) to 4,057 s (419 rows, `345b4487`, 11-01), up
44 percent in 12 days. The table is refreshed by hand
(`mise run test:refresh-durations`), last on 11-01, and 28 test files have no
row, so shard plans run on stale data.

<details>
<summary>Commands, gate structure, budget history and top offenders</summary>

- File counts: `git ls-tree --name-only <tag> tests/ | grep -cE '^tests/(test-|smoke-|rehearsal-)[^/]*\.sh$'`.
- Test lines (`test-*` files only): `git grep -h -c '' <tag> -- 'tests/test-*.sh'`, summed.
- Assertion lines (the suite has no single test-declaration pattern):
  `git grep -h -c -E '^\s*(assert[a-z_]*|expect[a-z_]*)\b' <tag> -- 'tests/test-*.sh'`, summed.
- CI: `gh run list --workflow ci.yml --limit 4000 --json databaseId,createdAt,updatedAt,startedAt,conclusion,event,headBranch`,
  median of `updatedAt - startedAt` over successful `pull_request` runs (job
  queue time included); per-job timings from `gh api repos/{owner}/{repo}/actions/runs/<id>/jobs`.
- Duration sums: `git show <rev>:config/test-durations.tsv | awk -F'\t' '!/^#/ && NF>=2{n++;s+=$2}'`.

**Gate structure.** `mise run check` runs `test`, `check:test-time` and
`check:non-test` (nearly 60 lint and check tasks) through mise `depends`;
`scripts/run-tests.sh` runs files in parallel under a host-wide ticket pool
with a per-file deadline; `.claude/planwright.yml` allows one full local suite
per host (`full_suite_pool: gate`, capacity 1). CI (`.github/workflows/ci.yml`)
triggers on every PR and push to main with no path filter and runs lint, a
shard-planning job, planned Linux shards, Alpine shards, four macOS shards, a
macOS install smoke and a joining `check`.
History: `a3ac1fc3` (10-08) macOS runs awk-sensitive suites; `cd9fe5fe`
(10-20) Linux split into shards; `d59e99f6` (10-30) macOS and Alpine on every
PR; `3997515e` (11-01) shard count planned from predicted time; `b51cc372`
(11-04) macOS and Alpine sharded. Job timings on 11-05 and 11-06 runs
(42261296820, 42164719580): macOS shards queued up to 29 minutes (one
started at once) then ran 8 to 24;
Linux shards 3 to 4; Alpine 3 to 6. Before sharding, `macos-suite` ran 69 to
80 minutes serially (11-01, 11-04).

**Budget history** (`config/test-time-budget.yml`):

| Commit | Date | Change |
| --- | --- | --- |
| `c75f006d` | 09-08 | introduced: 120 s per file, 600 s suite total |
| `dee2dea6` | 10-02 | suite total to 780 s |
| `dc84d00e` | 10-16 | to 1000 s (runner variance) |
| `329eebe0` | 10-21 | added a 400 s shard wall |
| `b4302a25` | 10-31 | to 1400 s (main runs measured 675 to 1075 s; two failed on green code) |
| `3997515e` | 11-01 | total replaced by a 13.5 s per-file mean; shard target 200 s, at most 10 shards |

No budget covers the macOS or Alpine shards, where the wall time now is; the
shard wall budget judges Linux reports only. The deferral "apply the
test-time budgets to the macOS CI job" in `specs/test-throughput/` is gated on
universal-binary Task 4.1, which has merged, and was not picked up.

**Slowest files** (current tsv): `tests/test-flight-lifecycle.sh` 77.5 s,
`tests/test-fleet-streamjson.sh` 74.7, `tests/test-ready-flip.sh` 66.5,
`tests/test-flight-record.sh` 60.2, `tests/test-resolve-steps.sh` 52.3,
`tests/test-tower-queue-picklist.sh` 49.8,
`tests/test-check-echo-discipline.sh` 45.2,
`tests/test-check-purged-identifiers.sh` 44.6,
`tests/test-inception-gate.sh` 44.6, `tests/test-flight-dispatch.sh` 43.9. The
37 files at 30 s or more are 37 percent of the total. Two of the slowest
scan the whole tree (echo discipline, purged identifiers), so their cost
grows with the repository, not with the code under test.

**Grew most since 10-21:** `test-check-steps.sh` 12.9 to 31.3 s,
`test-check-lock-primitive.sh` 21.5 to 37.0, `test-tasks-pr-sync.sh` 17.0 to
27.5, `test-inception-venture.sh` 23.9 to 34.4,
`test-orchestrate-meta-step.sh` 23.4 to 33.3.

**Consolidation candidates** (counted from `grep -oE 'scripts/[a-z0-9-]+\.sh'
tests/test-*.sh`; each needs a reading before acting): 28 test files
reference `tower-queue.sh` (the `test-tower-queue-*` family is 18 files,
348 s across the 17 with a recorded time); 48 files touch `fleet-state.sh`
or `fleet-attention.sh` (608 s); 10 `test-worker-command-guard*` files
(175 s across the 9 with a recorded time); 10 `test-flight-*` files
(296 s); 8 `test-check-instructions*` files (63 s).

**Targeted runs.** `run-tests.sh` takes only `--shard`, `--plan-shards` and a
suite directory; it cannot select files. `skills/execute-task/SKILL.md` runs
the full suite through `scripts/full-suite-run.sh` before convergence; polish
and self-review run the wider suite after fixes. The only targeted policy is
the `fix-round-cadence` prompt step (`.claude/catalogs/steps.yaml`), which its
own config comment calls "a reminder, not an enforcement".

</details>

### Task build time and where it goes

| Month | Task PRs | Build median (p75) | Open to merge | Lines changed |
| --- | --- | --- | --- | --- |
| 06 | 54 | 0.45 h (1.26) | 3.0 h | 708 |
| 07 | 126 | 0.57 h (1.16) | 3.1 h | 642 |
| 09 | 65 | 1.89 h (3.33) | 7.9 h | 1,294 |
| 10 | 133 | 3.96 h (12.16) | 11.0 h | 1,258 |
| 11 | 26 | 0.82 h (3.96) | 10.8 h | 691 |

"Build" is PR creation minus the first commit's author date, over 424 merged
task PRs (`gh pr list --state merged`; branches `planwright/<spec>/task-N`);
August's 20 are in that total but not in the table. This is the one method
used: monthly medians of that span, with a single size band as the control.
Its caveats: it leaves out the worker's time before its first commit, it
counts parks and waits as build time, and a spec bootstrapped from older
commits inflates its first tasks. At equal size October is still slower: 1,000 to 3,000 changed lines took 1.10 h
in July and 7.18 h in October. Within a spec there is no trend (median
Spearman correlation of task order against build time 0.01 over 40 specs), so
the slowdown is shared infrastructure and process, not harder tasks.

Where recorded wall time goes (352 step records across worktrees, all from
2026-10-11 on): polish 99 runs, median 66 minutes, 220 hours in total, and
its weekly median rose from 49 to 77 minutes over ISO weeks 43 to 45 even as
rounds fell to 2; 16 of 99 polish runs ended halted or failed. On
2026-10-25 seven full-suite pool waits expired at the 3600 s cap, about 9.7
worker-hours of waiting in one afternoon.

<details>
<summary>Review steps, rounds, CI reruns and caveats</summary>

- Share of task PRs naming each review step: gemini panel 21 to 30 percent in
  June and July, 53 in October, 0 in November; cubic 0 before October, 63 in
  October, 100 in November; polish about 85 percent early, 96 to 100 from
  October.
- Polish rounds from PR bodies: median 2 (June to July), 3 (September and
  October), 2 (November). The highest pending sign-off number per body
  averaged about 1.2 early and 8.5 in October.
- Failed CI runs per task PR: about 0.2 in June and July, 1.11 in October,
  0.12 in November; reruns 0.26 in October, about zero elsewhere.
- The 12 slowest October task PRs (33 to 106 hours, for example #640, #539,
  #675, #662, #673) all mention a park, stall, resume, relaunch, quota halt,
  429 or host load.
- Local gate data points: #105 ran `mise run check` in 328 s; #689 hit its
  3600 s limit at host load about 70 with 115 of 314 files run; #594 killed
  gate hangs at a 7200 s outer timeout.
- The November recovery coincides with the local gate being skipped (stated
  in every November task body), the gemini panel dropping out, cubic halting
  on quota, and smaller units; this data cannot separate those causes.
- Caveats: step records start 2026-10-11, so there is no earlier baseline;
  the step-record counts take the records last written before this report's
  commit, and they move as running units finish;
  some in-session records carry hand-entered timestamps and include stall
  time, so polish totals are an upper bound; pool waits cover one day; the
  November sample is small.

</details>

## Trails by theme

Each theme lists what was acted on, what is open, and the gap.

### Polling and wakes

Acted on: supervisors subscribe instead of polling, edge-triggered attention,
cached dashboard reads, merge-edge wakes (`A/2026-10-07-supervisors-subscribe-not-poll-b9f53634.md`
and six more consumed by mission-control and fleet-hardening);
`doctrine/fleet-coordination-floor.md` rules out LLM daemon mechanics, partly
on cost and rate-limit grounds. Open: obs:1f599c9d (the costly tick);
bot-review polling cadence inside its wait window
(`E/2026-09-17-bot-review-latency-overstated-67aafd6a.md`); fixed 1 s
supervisor tick (`E/2026-10-02-streamjson-fixed-poll-tick-953df56d.md`);
tower-queue idle-pass costs (d394ee29, 980f2be4, 2b1327e0);
`specs/fleet-messaging/` Task 6's event-driven `--watch` loop and Task 7's
notice-wake step, deferred until bootstrap signs off an amendment retiring
D-38's metronome; the pending note routing that amendment
(`specs/_pending/bootstrap-amendment.md`) is Task 6's own deliverable, and
Task 6 has not started. Gap: PR-state
change events (ask 1).

### Idle sessions and retirement

Acted on: lingering flight workers, stream-json teardown and liveness cleanup
(consumed by mission-control and fleet-lifecycle-closure). Open: the reaper
only observes (`fleet_sweep_reap: observe`, terminate refused pending
pid-binding); registry and fleet state never pruned
(`E/2026-09-02-registry-retention-and-write-cost-75369b47.md`,
`E/2026-09-07-streamjson-state-has-no-retention-4dd41794.md`); the test
supervisor leak recorded five times and recurring after its fix
(`E/2026-10-05-streamjson-test-leak-recurs-on-main-44b2795b.md`); a live
worktree removable after 900 s (`E/2026-11-05-launcher-worktree-liveness-093b1e8d.md`).
Gap: no rule anywhere retires an idle, finished session on a timeout (asks 2
and 6).

### Permission denials

Acted on: the prompt-flood class (`specs/worker-permission-ergonomics/`,
Tasks 1 to 15 merged); step resolution too slow for the 2 s guard deadline
(`E/2026-10-02-guard-multipoint-resolve-089f3a5d.md`, fixed by one
multi-point resolver run in #561, the fragment never archived and the
deadline never re-measured). Open: polish audit writes
denied twice (82b9bba0, 34e406e0); every main merge needs an operator act
because `--no-verify` is blocked (82612b46); the kickoff push refused
(04bcb01a); a successor stalled on its own prompts (32bde2c6);
`specs/harness-rebaseline/` REQ-B1 (a three-arm permission trial) not
started. Gap: no count of prompts or denials, so their cost is never seen
(ask 3).

### Model tiers and spend visibility

Acted on: `specs/model-allocation/` (Done) and `specs/fleet-autonomy/` usage
ladder and per-kind models (`fleet_model_execution: opus`, bookkeeping
`sonnet`). Open: everything that would make it bite. Adaptation off;
per-step tiers unwired (`E/2026-10-05-step-tiers-cannot-raise-or-apply-e9ae3805.md`);
no launch point passes `--step-type` (f17e821b); the feedback loop never
invoked (7c8e69ca, 639cea17); a fleet entirely at the top tier records
nothing (270651d6); `docs/allocation.md` says the mechanism is dark;
`specs/quota-handling/` Tasks 2 and 8 wait on custom-steps tasks that have
all merged. Gaps: no dollar or token accounting (obs:af17332a; the
fleet-autonomy dollar seed never written); no estimate before a launch; no
rule setting the model for lens and verification subagents.

### Test cost and test growth

Acted on: the host ticket pool, per-file deadlines, sharding, the gate pool,
step-record reuse on the same head (`specs/test-throughput/`,
`specs/guard-coverage/`, `specs/custom-steps/`). Open:
`specs/test-throughput/` Tasks 10, 11, 13, 16, 17 (CI as full-suite
evidence); the heavy-run admission verb has no caller
(`E/2026-11-05-no-host-load-scheduling-01033adb.md`); gate lock order
inversion with 60-minute stalls (ac484ef0); pool waits expiring (4d47cc6b);
about one false red in four under load (66ae088f); the spawn-cost family of
nine fragments (for example `E/2026-10-02-guard-hook-spawn-cost-ee336bb5.md`,
about 78 thousand forks in one guard test file); `docs/recurring-failure-classes.md` load
policy never picked up. Gaps: affected-tests selection exists only as the
per-fix diff-scoped check (`scripts/check-diff-scoped.sh`,
review-effectiveness REQ-D1.3), which no skill calls yet, and nothing
selects tests for CI; per-PR platform gating is forbidden by the current
rule (universal-binary REQ-B1.6 and `scripts/check-workflow-posture.sh`
require every platform job on every PR); no growth or pruning rule (see
Measurements).

### Review rounds and convergence

Acted on: comment volume, handoff before bot review lands (consumed).
Open: `specs/review-effectiveness/` (Active) carries every cost cut and has
them unlanded: delta-directed lenses (REQ-B1.5), a fresh bounded context per
pass (REQ-D1.1), doctrine resolved once per loop (REQ-D1.2), a blind pass
replacing the whole-branch confirm (REQ-D1.5); Task 3's only dependency
(Task 2) has merged, it has no PR, and Tasks 3.1, 7, 8 and 9 wait on it.
Its research measured a median 17.0M tokens per convergence run (`specs/_pending/review-effectiveness-research.md`).
Polish's iteration cap is ten (`skills/polish/SKILL.md`), where
harness-rebaseline D-9 proposes two scaled to diff size. Observations: a
59-file unit took five panel passes (a0add2f0), a shell-lexer guard seven
polish passes to converge (47e8a423), a 53-minute panel that timed out after converging
(5f46acd5), isolated review steps degrading to in-session (7f7e0c9f).

### Context size and succession

Acted on: tower handover by step count (`doctrine/context-budget-autoheal.md`),
mission-control succession (Task 16), instruction budgets
(`specs/instruction-headroom/`). Open: the three PR #857 observations;
about 940 always-resident skill description words with no budget class
(`E/2026-07-27-ctxeng-skill-description-surface-34cae1db.md`); real closure
load above the error threshold while the guard reports green
(4fbf9ceb); the context-engineering spec model-allocation scoped out, whose
`ctxeng-*` seed fragments sit unconsumed, never drafted. Gap: no context or succession rule for workers.

### Task build time

No trail measures it. Tasks carry an authored effort estimate
(`doctrine/spec-format.md`) and nothing compares it to actuals;
`specs/harness-rebaseline/` REQ-A1.1 would record wall time, tokens, rounds
and prompts per run and is not started. Stall observations (scratch root emptied c7ff1358, fixed
by #841; a 28-minute sweep hang 581c7096; run-tests pool hangs 6ed98940 and
69089148, now bounded by the per-file deadline) feed the long tail.

### Handoff duties

The handover file covers items and sessions, not duties (see the ask table).
Observations show work done by hand that a mechanism already covers or could:
a hand-built heavy-run lock and a "targeted tests locally" rule copied into
every brief (01033adb); hand-wrapped gate locks (ac484ef0); review steps
applied only when a session remembered them (a724c17f); a corpus refresh run
by hand (9b382af6).

### Other

- Cross-worker interference: one worker's secret-scan fixture fails every
  worker's gate because the scan walks all refs (five open fragments, for
  example `E/2026-10-25-gate-secret-scan-all-refs-3b81d2da.md`).
- Operator attention as a cost: kickoff density raised five or more times
  (`E/2026-11-04-drafting-kickoff-too-heavy-c52287be.md`).
- A filesystem-root search at 430 percent CPU for 7 minutes
  (`E/2026-11-05-no-filesystem-root-search-guard-3548c59c.md`).

## Gaps

**No trail at all:**

1. Efficiency and efficacy as an always-on doctrine for every skill and run.
2. Selecting the tests a change affects for the full gate and CI (the only
   selector is the per-fix diff-scoped check, which no skill calls yet), and
   a path to gating platform jobs per change (today's rule, universal-binary
   REQ-B1.6, requires every platform on every PR).
3. A rule bounding suite growth: pruning, consolidation, or a budget that
   does not grow with the file count.
4. Measuring task build time against its estimate.
5. Retiring an idle, finished session on a timeout outside mission
   control's PR-tracked sessions.
6. The model tier for lens and verification subagents.
7. A cost estimate before any launch.
8. Context and succession limits for workers.

**Recorded but never consumed:**

- The dollar-spend ceiling seed (`specs/fleet-autonomy/requirements.md` out of
  scope) and the context-engineering spec (`specs/model-allocation/`
  requirements out of scope): promised, never written.
- The bootstrap D-38 amendment that gates fleet-messaging's event-driven
  `--watch`: its routing note is a fleet-messaging Task 6 deliverable, not
  yet written.
- Waits whose condition is met but which nobody picked up: the macOS
  test-time budgets (a test-throughput deferral) and quota-handling Tasks 2
  and 8 (awaiting input until custom-steps tasks merged, which they have).
- Observation families still open: spawn cost (nine or more), secret scan
  crossing worktrees (five), allocation never wired (four), throttle-elapse
  flake (ten or more), fleet-stop timing under load (seven or more), the test
  supervisor leak (five).

## Does this deserve its own spec?

Yes, one cross-cutting spec, drafted only after the operator reads this, with
mission-control-specific asks kept as mission-control amendments. Proposed
scope: an always-on efficiency doctrine (waste is a finding in every skill,
with a cost line in each run's handoff); per-run measurement of wall time,
tokens, rounds and prompts (absorbing harness-rebaseline REQ-A1.1 rather than
duplicating it); test economy (affected-tests selection, per-PR platform
gating, a growth and pruning rule, and building and turning on
`full_suite_evidence`);
spend accounting in tokens or dollars with cheaper shipped tiers for
mechanical work; idle-session retirement across every launch rung, offload
included. The alternative is to finish what is already signed off first
(harness-rebaseline, review-effectiveness Task 3 onward, test-throughput
Tasks 10, 16 and 17), which covers measurement and review cost but leaves the
doctrine, test growth and spend gaps open.
