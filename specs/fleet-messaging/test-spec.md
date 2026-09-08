# Fleet Messaging — Test Spec

**Status:** Ready
**Last reviewed:** 2026-09-07
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: script-level behavior (probe parsing, grammar validation,
session-name screening, knob resolution, ordering, and post outcomes
through the
`PLANWRIGHT_MESSAGING_POST` post seam, because the CI toolchain binds no
socket) is `[test]` and runs in the repo's shell suite in CI. The post
seam serves the tower→worker sends alone; the upward worker→tower path is
the harness's one-shot idle notice, which no planwright script posts, and
the tower's own wake is the harness's too — no script posts a wake line.
The post seam's
contract is D-12's: the variable names an executable invoked with the
real post's argv and the body on stdin; it appends one record per call
(argv and body) to `$PLANWRIGHT_MESSAGING_POST_LOG`, prints the outcome
line on stdout or nothing, and exits with the write result — so a fixture
reads call counts and payloads from that log, and an empty stdout drives
the write-success fallback. The test-only seams are `--cli-version`,
`--owner-uid`, `--socket-type`, and the post seam, every one guarded by
`PLANWRIGHT_TEST_SEAM=1` (REQ-H1.5). Flows that need a live session (real
message delivery, held outcomes, idle notices, and the wire-contract
verification that is Task 2's first manual step) are `[manual]`; each
names its observable, its pass criterion, and the task PR that records
it. The harness drives one session, so nothing short of a live session
backs a two-session flow. The fleet smoke runner splits the same way: its
dry-run mode over the post seam is `[test]` and runs in the shell suite,
while the circuit it drives is `[manual]` and local-only — `mise run
smoke:fleet` is kept out of CI structurally by the standing
`check:no-ci-evals` guard, extended in Task 7 to the `smoke:` namespace and
the runner's own name, the same guard that keeps `eval:*` out. Doctrine
and contract deliverables are
`[design-level]`. The discipline ladder is prose-enforced: `effective-mode`
is an oracle the sending prose consults, never a gate a script applies, so
its verification is that oracle's arithmetic (REQ-F1.2, REQ-F1.3,
REQ-F1.4) plus the presence of the composition rule in the skill prose
(REQ-F1.2's Task 8 greps); no behavioral arm is claimed for a model
obeying it. Every frozen comparand (a pre-messaging output, a
pre-reduction interval, `fleet-attention.sh`) is
asserted against the shipping task's base commit, never against a
hand-maintained copy: the shipping task records that commit's SHA in a
one-line file under `tests/fixtures/`, one per comparand, and the fixture
reads it to resolve `<base>`, the content still coming from
`git show <base>:<file>`. `fleet-attention.sh` is frozen twice, its four
signal write
verbs against Task 2's base and the whole file against Task 6's.
`hooks/hooks.json` is not a comparand anywhere in
this bundle: no consumer of the signal transport is hook-mediated (D-20),
so the file carries no pre-messaging behavior to freeze.

## REQ-A — Availability & eligibility

### REQ-A1.1 — deterministic availability probe [test]

`fleet-messaging.sh probe` fixture tests, the CLI version supplied through
the `--cli-version` seam and the path's socket-ness through the owner
predicate's `--socket-type` seam (REQ-H1.5), so no fixture needs a real
socket or a helper interpreter to bind one: `CLAUDE_CODE_MESSAGING_SOCKET`
set and naming an existing path the seam reports as a socket, owned by the
invoking uid, with a version at or above 2.1.248 and a settings tree
resolving the session's effective `crossSessionInbound` to `accept`, reads
available. The
probe compares against 2.1.248 unconditionally — the stricter of the two
documented minimum values, with no provider detection — so 2.1.224 through
2.1.247 read absent on every host. The comparison is numeric per dotted
component: 2.1.250 reads above 2.1.248 and 2.1.1000 above 2.1.999, so a
string comparison fails the fixture. The acceptance conjunct is read from
the CLI's settings files in their precedence order (user, then project,
then local), or from the `PLANWRIGHT_MESSAGING_INBOUND=accept` layer a
fleet launch seam exports beside its `--settings` profile, a command-line
layer the files do not show (Task 4). The fixture builds the settings tree
by relocating `HOME` and the working directory so all three layers are
real files, adding no seam, and flips the layer
that wins: a local `accept` over a project `refuse` reads available, the
reverse reads absent, a tree resolving to `hold`, to `refuse`, or to
no value at all reads absent (an unmerged tower profile reads absent
rather than silently losing every notice), and that same empty tree with
`PLANWRIGHT_MESSAGING_INBOUND=accept` exported reads available, as does a
tree whose project layer carries `refuse` with that value exported: the
variable stands for the `--settings` command-line layer and outranks every
file. The parse is awk-based, no `jq` (bootstrap REQ-K1.5),
`crossSessionInbound` is read as a top-level settings key, and a parse
failure reads absent. Each
negative branch reads absent:
the variable unset, empty, or malformed; the path missing, dangling,
reported as a non-socket by `--socket-type`, or owned by another uid
(through `--owner-uid`); the version one below the minimum on each dotted
component (1.1.248, 2.0.248, 2.1.247), or unparseable (`2.1.x`, an empty
value). A fourth conjunct is the discipline knob: with every other conjunct
satisfied, a fixture overlay resolving `messaging_discipline` to `off`
reads absent — the per-fleet kill switch REQ-F1.2 places outside the
ladder, whose whole contract is that the probe lands here — while the same
overlay resolving to `script`, to `tiered`, or to `open` reads available.
With all three messaging knobs set in a fixture overlay and the
variable unset, the probe still reads absent.

### REQ-A1.6 — messaging eligibility from session-grade, fail-safe [test + design-level]

Test: `fleet-messaging.sh eligible <rung> --launch <bare|normal>` reads the
backend capability contract (`orchestrate-backends.sh caps <rung>`), not the
worker registry, and maps a `Session-grade` `yes` under `--launch normal`
to eligible for `tmux`, `stream-json-persistent`, and `headless-oneshot`;
`no` (`subagent`, `in-session`), `deferred` (`print`), an unknown value,
and a malformed value map to ineligible, as does a fixture rung reading
`yes` under `--launch bare`; an unknown rung, a missing `--launch`, and a
`--launch` value outside the pair are refused with a diagnostic and never
read eligible. The send precondition needs both the sender's probe reading
available and a recorded target inbox socket basename (the addressed
worker's registry `inbox` column, a bare value rather than a `key=value`
token), and each negative alone
refuses the send with a non-zero exit and an empty post log: the probe
absent with a basename recorded, the probe available with none recorded,
and the probe available with a recorded basename resolving to a path that
fails the owner predicate. Design-level: contract-doc review that the
derivation names the
`Session-grade` column as its source and adds no column, and that the doc
states messaging eligibility as distinct from dispatch eligibility.

### REQ-A1.5 — absence changes nothing on the signal paths [test]

With the probe forced absent — `--cli-version` below the minimum, the
variable unset, or a fixture overlay resolving `messaging_discipline` to
`off` — every consumer of the signal transport — downward
delivery, the idle notices, and the demoted sweeps — takes today's code
path. The one-shot forms are byte-identical to their pre-messaging
outputs frozen at Task 2's base commit (the comparand, gated in that
task's Done-when): the page `fleet-dashboard.sh write --out` renders, the
stdout and the signature file of `fleet-attention-watch.sh watch --once`,
and the commands `orchestrate-relay.sh` and `fleet-decision.sh` emit, all
over a fixture store carrying no answered-undelivered case, so Task 7's
surfacing does not move a comparand frozen here;
`hooks/hooks.json` is outside the frozen set, no consumer of the signal
transport being hook-mediated (D-20). The idle-notice path has no
pre-messaging output, so absence there is "not invoked", asserted at
source level: the idle-notice subscribe step in `/orchestrate`'s prose
names the probe as its condition, matched as a literal token (live once
Task 6 ships the step). The naming comparand is the post-Task-4 launch
argv: with the probe absent it is asserted equal to the argv with the
probe present, since `--name` and `--settings` are unconditional on
eligible rungs and inert without messaging. The `off` arm asserts against
these same frozen comparands rather than freezing a set of its own:
absence is absence however it was forced, and the kill switch earns its
name by proving exactly today's paths (REQ-F1.2).

### REQ-A1.4 — platform-contract drift guard [test + manual]

Two arms, stated honestly. The CI arm is self-referential by construction:
the drift-guard fixtures freeze the env var names
(`CLAUDE_CODE_MESSAGING_SOCKET`, `CLAUDE_CODE_MESSAGING_TOKEN`), the post's
line framing and the response Task 2 observed, the observed field shape of
the CLI's per-session record `~/.claude/sessions/<pid>.json`
`self-register` consumes, the documented minimum (2.1.224;
2.1.248, the value the probe compares against), the last-verified pin
(initially 2.1.259), and the six behaviors Task 2's wire step observes,
each frozen with the outcome it recorded — whether `crossSessionInbound:
hold` and whether `refuse` gate an idle notice, and what a second
`notify_when_idle` on a live subscription does (observable: the transcript
line); whether `--name` applies beside `--worktree --tmux=classic`
(observable: the launched session's observed name); whether `CLAUDE_PID`
reaches a SessionStart hook's environment (observable: the hook's captured
environment); whether a held message is released when the receiver relaxes
to `accept` (observable: the receiving session's transcript; either
outcome recorded, both passing); and in which
session types the harness's scheduled wakeup is
available (observable: a turn started at the requested instant, tried in
interactive tmux, in `-p`, and in a watchdog-launched tower, interactive
with an initial prompt), that last one observed from the session's own
model rather than from the script step — and prove
planwright's own parsers and probe match
them, failing with a diagnostic naming the assumption when a repo-side
change breaks one. The notice's rendered line shape (requirements,
Sources) is not among them: no shipped script parses that line, so it is
carried as a `[manual]` drift observation Tasks 2 and 6 re-read against
the running CLI — the two whose environment holds a watched worker — and
the smoke runner re-reads once Task 7 has landed, not as a parser fixture.
CI has the CLI (2.1.179, below the messaging minimum)
but no messaging-capable session, so it cannot see the platform move. The
live arm is the re-verification each platform-touching task performs
against the running CLI — once Task 7 has landed, by running the fleet
smoke
runner (REQ-A1.7) in place of an ad-hoc manual pass; pass criterion: the
observed version is recorded
in that task's PR and is at or above the pin, and the pin is raised to it,
never lowered; the notice's line shape is confirmed or its drift
recorded on the tasks that carry that observation (Tasks 2 and 6, then the
runner); a running CLI below the pin halts the task.

### REQ-A1.7 — the fleet smoke runner [test + manual]

Test: `scripts/fleet-smoke.sh` in its dry-run mode, which walks the whole
step sequence over the `PLANWRIGHT_MESSAGING_POST` post seam and a fixture
registry with no live session — the CI toolchain binds no socket, so what
this arm covers is the runner's own sequencing and exit behavior, never the
circuit. The fixture asserts the order of the five steps (dispatch, park,
notice, answer, resume), read from the post log and the runner's own step
lines, each against its named observable: the park is the worker's
`awaiting-input` attention row, the notice and answer are the tower's
answer post in the post log within 120 s of that park row (the runner's own
threshold), and the resume is the worker's next heartbeat row after the
answer. A fixture withholding one step's observable exits non-zero with
a diagnostic naming the missed step, one arm per step; and a complete
dry run exits 0 having printed a latency line per step and one before/after
duty-cycle line, the duty cycle being store reads per worker-minute over
that pass. Plus the CI-exclusion arm: `mise run check:no-ci-evals`
passes with its guard extended to the `smoke:` namespace and the
`fleet-smoke.sh` runner name (Task 7), and a fixture workflow wiring either
form — the mise task or the runner script directly — fails it, so
local-only is structural and not the task's mere absence from the `check`
aggregate.
Manual: the capstone run, one `mise run smoke:fleet` on a host with a
messaging-capable CLI; the environment is a `--watch` tower in a tmux
window and one worker dispatched on the same machine, both accepting; the
observable is the runner's exit status and its printed step, latency, and
duty-cycle lines; pass criterion: it exits 0 having observed every step of
the circuit — the dispatch, the park, the tower acting on the park, the
answer, and the worker's resume — and its printed latencies are recorded in
Task 7's PR. Before the Deferred entry's gate resolves the circuit passes
when a metronome tower acts on the park on its next iteration; the
notice-wake arm and the before/after duty-cycle figure are gated with Task
6's loop change and evaluated when that gate resolves. From that run on,
this
is what re-verifying against the running CLI means: every later
platform-touching change reruns the runner rather than inventing a manual
arm of its own (REQ-A1.4).

## REQ-B — Addressable identity

### REQ-B1.1 — deterministic launch names [test + manual + design-level]

Test: grammar tests for `--name` derivation at the three shipped worker
dispatch seams (`tmux`, `stream-json-persistent`, `headless-oneshot`) and
at the watchdog's `tmux` relaunch (`fleet-tower-watchdog.sh`, a script, so
its emitted launch argv is a fixture), every derived name passing
`orchestrate-relay.sh validate-handle` for its backend. Plus one
identity-environment fixture per session-grade worker seam: the emitted
launch environment carries `PLANWRIGHT_WORKER_HANDLE` and
`PLANWRIGHT_WORKER_SCOPE` with that worker's handle and scope, where today
only the `headless-oneshot` seam exports them (obs:fbb701bc), and a seam
that cannot derive either exits non-zero naming the missing one — the
precondition for the hooks that write attention rows, so a tower can be
woken about every worker. Plus the argv fixture for
`scripts/fleet-tower-launch.sh`, the thin launcher the meta-tower's
subordinate and the continue-as-new handover reach (Task 4).
Design-level: those two launches are prose steps invoking that
launcher, so review that each derives `--name`
for a launch on a session-grade rung, that a subordinate hosted on
`subagent` or `in-session` gets none, and that the tower command-guard's
verdict on the launcher is wholesale approval; a custom
`PLANWRIGHT_TOWER_LAUNCHER`
is out of scope and carries no arm here (REQ-B1.1). Manual: in a live
fleet on
one machine (a tower and one dispatched worker per rung), each dispatch
shows the worker under its derived name in
the tower's listing, and a watchdog-relaunched tower (a tower killed
mid-run plus a watchdog tick) appears under its
derived name; pass criterion: each listed name equals the derived one;
recorded in Task 4's PR.

### REQ-B1.2 — self-registration and recorded address [test + manual]

Test: the recorded values are the observed ones, and the session records
them itself. For a worker, the registry's two added columns, `name` and
`inbox`, are written as the store's `-` sentinel at registration and
filled afterwards by the session's own SessionStart hook running
`fleet-messaging.sh self-register`, which reads
`~/.claude/sessions/$CLAUDE_PID.json` (an undocumented surface, D-8,
D-11) and amends the row through `fleet-state.sh amend <worker> --name
--inbox`, reached by `fleet-register.sh`'s per-field degrade. The fixture
supplies a captured copy of that record and asserts the row's `name` column
equals its
`name` field and its `inbox` column the basename of its
`messagingSocketPath`, both held as bare values rather than `key=value`
tokens,
that neither value carries a path separator, and that every other field
of the row is unchanged by a before/after diff; a second fixture drives
the degrade, an amend that cannot write one field still writing the other
and exiting non-zero naming it; a third drives the narrowest screen, a name
the session-name screen admits but the registry's own field charset
refuses leaving the sentinel in place. `amend` and `send --to-worker` bind
the worker's last registry record, the append log's last-record-wins
convention. No seam reads anything back, so no
fixture supplies a checkout path, a `cwd` match, or a retry window: none
exists. A worker whose hook never runs keeps both sentinels — the row is
unchanged, `send --to-worker` refuses that worker with an empty post log,
and the start-of-tower subscribe pass skips it (fixture). The scripts that
parse the registry file, re-derived by grep at Task 4 (today
`fleet-status.sh`), plus the readers this bundle adds, each parse a three-,
a seven-, and a nine-column row, one
fixture per reader, asserting the two added values by field position for
the readers that surface them and tolerance alone for the readers that
surface no added field.
For a tower, the marker's one added field, the
observed name read by `fleet-messaging.sh self-name` (a fixture over a
relocated session record: the name printed; a missing record or a record
without a name exits non-zero and the marker keeps its sentinel), carried
on `fleet-tower-marker.sh record --name` with its
own validator (`record` accepts a valid name and refuses a hostile one,
`read` returns it), with no socket path recorded for a tower; the marker
is written at `--watch` loop start and removed on graceful exit, and a
single-step tower writes none and is addressed by a listing round-trip
(fixtures).
Both readers (`fleet-tower-signpost.sh`, the watchdog's marker reader)
parse seven- and eight-field rows on a mixed-arity fixture, asserted by
field position (the name surfaces at its declared position in each
reader's output, so a silently skipped row fails the fixture: the
signpost's failure mode is a silent skip, not a refusal). A nine-field row
splits per reader: the signpost skips it silently and continues with the
remaining rows, the watchdog's marker reader escalates it as ambiguous.
Manual: the
collision check (the environment: two same-named launches on one machine)
records whichever outcome the
CLI produces — a renamed variant, a refusal, or a duplicate — into D-8's
amendment note and Task 4's PR; the recorded name is the observed one, a
refusal surfaces as the CLI's own non-zero exit at the dispatch seam, and a
duplicate is read off the sender-side listing rather than detected, no seam
reading a name back.

### REQ-B1.3 — names validated as data [test]

Hostile-name fixtures (control bytes, a path separator, traversal,
over-length, shell metacharacters, an empty name) are refused with a
sanitized diagnostic before addressing, path use, or echo; the registry's
`name` and `inbox` columns and the marker's added name field refuse the
same set at write (`fleet-tower-marker.sh record --name` for the marker)
and on read.

## REQ-C — Downward delivery

### REQ-C1.1 — messaging-first with fallback ladder [test + manual]

Test: through the post seam, a refused outcome and a failed post each walk
the ladder one step — messaging → the rung's existing attributed steer
delivery → operator handoff, in that order — with exactly one post attempt
per step by the post log's record count, for `tmux`; the steer-less rung
(`headless-oneshot`)
receives no delivery attempt (an empty post log). The
`stream-json-persistent` carve-out is its own arm: `fleet-decision.sh
answer` refuses that rung with a non-zero exit and a diagnostic naming
`fleet-streamjson.sh answer`, the supervisor's control-response verb, and
never reaches the post seam (empty post log), since a
message cannot resolve the pending control request the worker is blocked
on; the tower obtains the full request id from `fleet-streamjson.sh status
<worker>`, the `decide` row carrying no id field of its own, and the fork
is claimed and its answer artifact written before the control response, so
REQ-C1.2's ordering holds on that rung too (fixtures);
a free-text steer on that rung posts once and, on a refusal, goes
straight to operator handoff, skipping the attributed steer delivery step
that rung does not have. Manual: a live `tmux`
check (the environment: a tower and one dispatched `tmux` worker on the
same machine) delivers a steer via messaging end to end; pass criterion:
the post
reports accepted and the worker's transcript shows the steer text
attributed to the tower session; recorded in Task 5's PR.

### REQ-C1.2 — claim, persist, then deliver; never re-claim [test]

Ordering tests against the decision-channel store: the answer artifact
exists before any delivery attempt (the post seam's stub checks for the
artifact at post time and records the result in its log); an induced
delivery failure (a refused outcome or a failed post from the seam) leaves
the fork closed, the claim field unchanged by a before/after diff, and the
artifact recoverable. A source audit that the claim verb appears at
exactly one call site in `fleet-decision.sh`, so no second path can
re-claim.

### REQ-C1.5 — synchronous outcomes consumed; held surfaced only [test + manual]

Test: the post seam stub returns each outcome in turn — the `accepted`,
`held`, and `refused` lines on stdout with exit 0, then a failed post (no
line, non-zero exit) — and the send path reacts to each: accepted is
reported as accepted, never as delivered, and exits 0; held produces one
stderr notice,
no store row, no second post (one record in the post log), and its own
exit code 5; the five codes are asserted together and distinct — 0 for an
accepted post or an emitted fallback delivery command, 5 held, 4 keeping
today's meaning (delivery not completed after a successful claim) now
reached as the ladder's terminal operator handoff with both of its existing
sub-case messages standing, and today's 2 and 3 unchanged — so an
unattended caller can tell queued from done, and the relay's messaging arm
reports held with that same 5; refused and
a failed post take the next step of the fallback ladder. The write-success
fallback is fixture-driven: with the stub printing nothing, exit 0 is
treated as accepted and a non-zero exit as a failed post, under the same
rules. `send` mints the message id itself, writes it into the posted
frame beside the reply address with no auth line (the post-seam log
carries both fields and no `auth` frame), prints it for every post it
writes, accepted or
held, and
`fleet-decision.sh` records that id in the answer artifact's metadata
sibling (`<fleet-home>/attention/answers/<worker>.meta`, one line per fork
instance id, the attention store's fork discriminator), so a later
status frame names a fork; the artifact itself stays byte-identical to the
shape it has today, its whole content being what the attributed steer
delivery carries, and
a second fork for the same worker adds a second keyed record and leaves the
first in place (fixtures:
the id read off stdout is the id that record carries). The outcomes the
connection cannot show (dropped,
expired) come back
as status frames to the reply address: the seam's recorded frame carries
the invoking session's own socket path as its reply address (fixture), and
`fleet-decision.sh redeliver --message-id <id>` — the tower's one action
on a drop, expiry,
or refused frame — resolves the fork from the record carrying that id,
emits the attributed steer delivery command for its
persisted answer and does nothing else (post log empty, claim field
unchanged by a before/after diff, no attributed steer delivery performed:
the script cannot
see one land), writes exactly one `redelivered` mark on that line,
refuses an id no record carries, refuses an id whose fork is not the
artifact's current fork, and
refuses a second call for the same fork (fixtures; Task 5). A held status
frame, and a frame the tower never receives, drive no `redeliver` at all:
that turn runs the step's own first action and the recovery is the
surfacing below (fixture: a held frame leaves the post
log empty, the record without a `redelivered` mark, and the parked
worker rendered answered-undelivered). A status frame read mid-turn is
handled after the step's own work, never interleaved; that rule is skill
prose, so its arm is the `/orchestrate` grep set in REQ-D1.8, not a
script test. Where the
frames do not exist, the worker is surfaced instead: a fixture with a
parked worker whose fork carries a persisted answer artifact renders as
answered-undelivered in the attention view, and the sweep pass that renders
it leaves the post log empty (Task 7). Manual: the wire-contract
verification against the running CLI is Task 2's first step, run from an
interactive session on the kickoff host with the inbox socket bound,
posting one line to a second session's socket with a reply address; the
admissible outcomes are a response line, whose framing is recorded, or no
response, where write success or failure is the only signal, and, for a
message the receiver refuses or drops, a status frame at the reply address
or none; each passes when the request-line framing, the observed response
(or its absence), and the status frame's shape (or its absence) are
recorded in Task 2's PR and frozen in the drift guard. Plus a live
held-message check against a receiver whose profile carries
`crossSessionInbound: hold`, surfaced as unconfirmed, never presumed
delivered; pass criterion: one stderr notice and no store row while the
receiver holds, then either outcome recorded when the receiver relaxes to
`accept` — the text delivered exactly once, or the queued message
discarded — since the answered-undelivered surfacing carries the case
either way; recorded in Task 5's PR.

### REQ-C1.4 — no impersonation, no permission answering [test + design-level]

Tests that message text is handled as data (the post reads the message
file, never splicing its content into a command string: a body carrying
shell metacharacters and a `$(...)` substitution arrives in the post log
verbatim; a permission-park record is refused by the claim before any
delivery attempt) and the source audit that the messaging arm contains no
`send-keys`, so attributed steer delivery is never faked through the
worker's input. That a delivered message cannot approve a permission
prompt is a platform guarantee (Sources), reviewed design-level, not a
repo behavior under test.

## REQ-D — Upward signals

### REQ-D1.4 — missed notices healed by the sweep [test]

With no notice delivered (standing in for a missed one, an expired one,
and a turn-boundary-delayed one alike — a notice enqueued at a busy tower
whose model has not reached the turn boundary that would show it, D-21)
and an
attention row written while the worker is still running, one
`fleet-attention-watch.sh watch --once` pass surfaces both rows from the
store: the sweep derives from the store, so the pass reads no clock and
the cadence knob is not an input to the assertion (the fixture shared with
REQ-E1.2). `fleet-dashboard.sh` renders a projection and heals nothing, so
it carries no arm here, and its refresh keeps today's interval as an
operator-facing cadence (REQ-E1.1).

### REQ-D1.6 — upward push is the idle notice [test + manual]

Test: a source audit against Task 6's base commit, which already carries
Task 2's `render --worker` arity and doctrine header — `fleet-attention.sh`
is byte-identical to that base-commit copy, so no write verb gained a
post; no file matching `scripts/*.sh` other than `fleet-messaging.sh`
contains the `CLAUDE_CODE_MESSAGING_SOCKET` name, so no shipped
worker-side script reads a socket path (the inference the grep supports
and no more: the CLI's per-session record is world-readable, so a socket
path is discoverable by other means; what is asserted is that no shipped
script goes looking); and `SendMessage` and `ListAgents` appear in no file
matching `scripts/*.sh`, so no worker-side model turn carries a signal.
Only a stop that ends the worker's turn fires a notice: a mid-turn
suspension (a permission or elicitation dialog, obs:4c25e743) ends no turn
and is the sweep's case, asserted through REQ-D1.4's healing fixture with
no notice delivered rather than by a second notice fixture. The identity
environment (`PLANWRIGHT_WORKER_HANDLE`, `PLANWRIGHT_WORKER_SCOPE`)
exported at the worker's dispatch seam is this path's precondition — the
hooks that write the attention rows the sweep carries read it — and is
covered by REQ-B1.1's per-seam fixture, not restated here.
Manual: in a live two-session environment (a tower and one dispatched
worker on the same machine), a worker that parks on a fork produces a
notice at the tower
carrying the worker's closing line; pass criterion: the notice is
enqueued at the tower within 10 s of the worker's turn ending, observed
from the receiving session's transcript timestamp with the tower idle, so
enqueue and model delivery coincide (the kickoff experiment E3
observed 1 s; on a busy tower the notice reaches the model at its next
turn boundary, which is unbounded and not this criterion, D-21), and its
status line carries that closing line; recorded in
Task 6's PR.

### REQ-D1.7 — notices subscribed and read as data [test + manual]

Test: `fleet-messaging.sh notice-read <session name>` screens the name as
data (printable ASCII, no path separator, at most 128 bytes — a different,
path-safe screen from `orchestrate-relay.sh validate-handle`), matches it
against the
worker registry's `name` column, and delegates to
`fleet-attention.sh render --worker <handle>` for that row, returning that
output only: for a notice whose status line contradicts the store, it
returns the store row for the named worker and no notice content. Hostile
names are refused with a sanitized diagnostic and drive nothing: control
bytes, an over-length name (over 128 bytes), a name carrying a path
separator, and a well-formed name matching no row's `name` column; an
ambiguous match — two registry rows carrying the same `name` value — is
refused the same way and reads no store row. Distinct from all of those,
a name matching exactly one row whose store holds no attention row
returns empty output and is a no-op: the turn derives nothing from it and
takes no further action.
Prose fixtures (literal-token greps over `/orchestrate`, live once Task 6
ships the steps): the subscribe step after dispatch conditioned on the
tower's own probe; the re-subscribe step after each downward delivery,
unconditional on any prior subscription while the subscribe step's probe
condition still applies; the start-of-tower subscribe pass over the
reconcile sweep's in-flight worker set, derived from disk, which a fresh
tower after a watchdog relaunch or a continue-as-new handover needs
because it holds no
subscriptions, addressing every subscription by the registry's recorded
`name` column and skipping a worker carrying none (a fixture registry with
one
named and one unnamed in-flight worker yields one subscription); the
carve-out that a single-step tower whose session ends with the step takes
no subscription; and the sanction, stated once as a standing
instruction, that `notice-read` is the only sanctioned action on a notice
and that the re-read precedes any other fleet read in every notice-driven
turn, `--watch` iterations included.
Manual: a live two-session check (the environment: a tower and one
dispatched worker on the same machine, the tower running `--watch`) where
both sessions
accept (the worker's rung is eligible, its shipped profile carries
`crossSessionInbound: accept`, and the tower's settings carry the same
key: the tower profile at a fleet tower launch, the operator's own
settings otherwise) — a notice is enqueued at the tower within 10 s of
the worker's first stop, read from the receiving session's transcript
timestamp with the tower idle, so enqueue and model delivery coincide
(first pass criterion; on a busy tower, model visibility waits for the
next turn boundary and is unbounded, D-21); the tower then delivers a
steer, re-subscribes, and a second notice is enqueued within 10 s of the
worker's next stop (second pass criterion); and
the `--watch` iteration that consumes a notice shows no fleet read before
the `notice-read` invocation and no action derived from the notice other
than it (third pass criterion, observed on that iteration's tool calls),
this last criterion gated with Task 6's loop change, since a metronome
tower runs no iteration that consumes a notice — the ungated arms stop at
a notice enqueued at the tower.
That the absence of a notice moves no liveness classification is
Task 6's `[test]` baseline (the existing liveness tests pass unmodified),
not this arm's. Recorded in Task 6's PR.

### REQ-D1.8 — the tower's watch loop is event-driven [test + manual]

Test: two source audits over the `/orchestrate` skill prose, and no script
fixture: the wake is the harness's and the loop is prose, so nothing
script-level carries this path. The first audit shows a step in `--watch`
ends the tower's turn and the loop emits no unconditional in-turn sleep:
the metronome sentence's unconditional form is absent from
`skills/orchestrate/SKILL.md` at Task 6's head while present at that
task's base commit (`git show <base>:skills/orchestrate/SKILL.md`, `<base>`
read from that comparand's base-SHA file). The
second is a literal-token grep set over the sentences that replace it —
the three wake paths (a worker's idle notice, a peer message, and the
timer, which is the harness's scheduled wakeup requested at step end,
whose availability per session type Task 2's wire step records); the
conditions under which the metronome is kept instead (the probe reads
absent, the wakeup is unavailable for the session type, the tower is a
`-p` session, the continue-as-new handover's own `claude -p` launch
included, or the step ends with neither a live subscription nor an
available wakeup), the subagent backend's existing event-driven arm left
standing; the ordering rule, a notice-driven turn running `notice-read`
first, a drop, expiry, or refused status frame's turn `redeliver` first, a
held frame's turn the step's own first action, a timer-driven turn the
reconcile sweep first, and an advisory turn the step's own first action,
with none of them dispatching, claiming, or writing outside the step's own
rules and a status frame read mid-turn handled after the step's work; the
wake-source order for a turn with more than one pending, `notice-read`,
then `redeliver`, then the reconcile sweep, then the step's own first
action, with the subscribe pass preceding all of them on a tower's first
turn; and
the selector-exit-1 rule, the turn ending awaiting a wake while a
subscription is live and the watch ending otherwise. Plus a grep over the
skill's handover step for the sentence instructing the continue-as-new
seed to carry the sanction, and for the absence of any in-flight worker
list carried beside it: the subscribe pass derives that set from disk.
Manual, both recorded in Task 6's PR. First, the three wakes: an idle
`--watch` tower is woken into a step by a worker's idle notice, by a peer
message, and by the timer, one arm each; the environment is a `--watch`
tower in a tmux window and one dispatched worker on the same machine, both
accepting; pass criterion: each wake starts a new tower turn whose first
fleet action is the step's own, read from the tower's transcript (the
kickoff's E4 observed the notice and the message wakes on this host; the
timer is the arm E4 did not cover), the timer arm taking either outcome —
where Task 2's wire step recorded no scheduled wakeup for this session
type, the arm records that and the metronome-retention clause is what is
verified instead. Second, the relaunch subscribe pass: a
fresh tower after a watchdog relaunch subscribes over its in-flight set;
the environment is a tower killed mid-run with in-flight workers plus a
watchdog tick that relaunches it; pass criterion: the relaunched tower's
first turn takes one subscription per in-flight worker carrying a `name`
value
and none for a worker without one, read from that turn's tool calls.
The three-wake manual arm and both source audits are gated: Task 6 holds
its loop change behind the Deferred entry in `tasks.md`, whose gate is
bootstrap's D-38 amendment being signed off, so that part of this entry's
coverage is evaluated when the gate resolves. The relaunch subscribe-pass
arm and Task 6's ungated half (REQ-D1.7's subscribe steps, the sanction,
the start-of-tower pass) carry no such wait.

## REQ-E — Store-load reduction

### REQ-E1.1 — cadence demotion where push is live [test]

The demoted set is two consumers: the `--watch` loop's own store reads,
which the event-driven loop makes wake-driven rather than cadenced
(REQ-D1.8; Task 6's turn-end audit is that half's verification and this
entry adds no arm for it, and that half is gated with Task 6's loop
change), and `fleet-attention-watch.sh watch` run
without an `--on-change` callback, the tower-facing pass. With the trigger
true (the tower's probe reads available and at least one in-flight worker
in the fixture registry carries a recorded `inbox`
value, the dispatch-time proxy for the tower's subscription), the watcher
demotes its poll interval to `messaging_heal_cadence_seconds`; with the
trigger false (the probe absent, or no in-flight worker carrying that
value), it keeps its pre-reduction default interval,
frozen as a fixture from Task 7's base commit. Both conjuncts are recorded
facts, so no fixture flag stands in for anything prose-side. The demoted
pass recomputes `reconcile_every = max(1, round(300 / cadence))`, so the
deep reconcile period is at least the pre-demotion period and within one
demoted interval of it (fixture: asserted at a cadence that divides the
base period and at one that does not). The
operator-facing cadences are excluded and their exclusion is asserted, not
assumed: a frozen-interval fixture against that same base commit shows the
watcher run with an `--on-change` callback and `fleet-dashboard.sh
watch`'s refresh unchanged under both trigger states, nothing pushing to
the human. The knob is bounded: a `messaging_heal_cadence_seconds` above
the attention watcher's default liveness max-age (900) is refused with a
diagnostic naming the knob and the bound, and 900 itself is accepted. The
trigger is re-evaluated each
pass:
a fixture that flips the worker's recorded field between two passes flips
the interval. An explicit `--interval` wins in both states. The demotion
targets a poll-interval variable split from the event branches' timeout,
asserted as a source diff rather than a runtime probe: against
`git show <base>:scripts/fleet-attention-watch.sh` with `<base>` read from
that comparand's base-SHA file, the fswatch branch's
and the inotifywait branch's timeout sites are byte-identical to the base
commit (the form Task 7 uses; neither tool is present on the kickoff
host). `docs/fleet.md` carries a bring-up line for each watcher form, the
demoting tower-facing pass and the `--on-change` form that keeps its
interval, the script having no shipped caller today (grep).

### REQ-E1.2 — healing sweep never removed [test]

The healing fixture shared with REQ-D1.4 (one `fleet-attention-watch.sh
watch --once` pass recovers the rows with no notice delivered; the
attention watcher is the healing consumer, the dashboard only projects),
plus a source audit that neither touched consumer reads
`messaging_discipline` (the knob name absent from `fleet-dashboard.sh` and
`fleet-attention-watch.sh`), so the sweep runs at every discipline value
by construction.

### REQ-E1.3 — record semantics untouched [test + design-level]

Diff-review of the reduction changes (design-level: only reads and cadences
touched, no write path changed) plus the existing store-schema fixtures
passing unmodified (test: record shape unchanged).

## REQ-F — Settings & discipline

### REQ-F1.1 — worker inbound acceptance wired at dispatch [test + manual]

Test: the profile content is Task 3's, the seam wiring Task 4's. Content:
a `jq -e` fixture over the two shipped profiles, the worker profile
carrying `crossSessionInbound: accept` and both carrying
`isolatePeerMachines: true`, with `mise run lint:json` and
`mise run check:hook-contracts` passing. Wiring, per D-19: each shipped
session-grade worker seam's emitted argv carries `--settings <profile>`
naming `config/worker-settings.json` and its environment carries
`PLANWRIGHT_MESSAGING_INBOUND=accept` beside it (one fixture per rung),
and a seam whose profile is unreadable
exits non-zero with a diagnostic naming the profile (the injector: the
seam resolves the profile under a planwright-root override, and the
fixture points it at a temporary root whose profile is unreadable). Tower
side: the fleet tower-launch argv fixtures (the watchdog's relaunch and
`scripts/fleet-tower-launch.sh`)
carry `--settings` naming `config/tower-settings.json` with
`PLANWRIGHT_MESSAGING_INBOUND=accept` exported beside it, and an
operator-launched tower's bring-up passes no `--settings` (the operator's
own settings carry the profile). No guard fixture appears here, because no
guard is re-scoped: in D-19's words, each seam builds its own launch line
after validating any caller-supplied extras, so
`fleet-dispatch-worktree.sh`'s launch-argument pin never sees the profile
flag, and the tower command-guard auto-approves planwright's own scripts
wholesale, so it never sees the launch either. Manual: a
live per-rung check on `tmux` and `stream-json-persistent` (the
environment: a tower and one dispatched worker on the same machine, the
operator away) that an
unattended worker accepts an inbound message; pass criterion: the send
reports accepted and the worker's transcript shows the text with no
prompt, the `tmux` arm's unattended acceptance being itself the observable
for D-19's unverified interactive `--settings` case, no surface printing a
session's effective inbound state; recorded in Task 4's PR.

### REQ-F1.2 — the discipline knob [test]

`messaging_discipline` resolution tests through the overlay layers: all
four values validated — the ladder's `script`, `tiered`, and `open`, plus
the switch value `off` — default `tiered`, an unknown value refused with a
visible diagnostic naming the knob at the resolver and read as absent by
the probe, the fail-safe posture every other unknown value takes
(REQ-A1.1). `off` is accepted by the knob and
outside the ladder: it resolves like any other value, the probe reads
absent for it (REQ-A1.1's fourth-conjunct fixture) so every consumer takes
today's path (REQ-A1.5), and `effective-mode` refuses it with a diagnostic
naming it the switch value rather than applying a direction or pressure
offset to it — those offsets are asserted over the three ladder values
alone (REQ-F1.3, REQ-F1.4).

### REQ-F1.3 — three directions [test]

`effective-mode --direction <worker-to-tower | tower-to-worker |
tower-to-tower>` tests: `worker-to-tower` resolves at the knob value,
`tower-to-worker` one value stricter saturating at `script` (`script`
resolves `script` in every direction), and `tower-to-tower` advisory at
the knob value, for each of the three knob values; a missing or unknown
`--direction` is refused with a diagnostic.

### REQ-F1.4 — send-time pressure demotion [test]

Usage-gate rung fixtures over `fleet-usage-gate.sh rung`: a rung at or
above `reduce-concurrency` demotes
one value in every direction, saturating at `script`, and writes one
stderr notice per send that runs demoted by pressure (none for a send
whose effective value differs from the knob only by the direction offset);
a rung below it, or an unavailable gate, applies no demotion; the
context-budget monitor's output (each of `near-limit`, `ok`, `disabled`)
is ignored; the fleet state directory listing outside `usage/`, which
`fleet-usage-gate.sh` legitimately writes into, is identical before and
after an `effective-mode` sequence covering every direction and pressure
state (no discipline state written); a fixture that changes only the usage
gate's rung flips the result, so the decision reads that rung and nothing
else.

### REQ-F1.6 — cross-machine gated by the harness prompt [test + manual + design-level]

Design-level: both shipped settings profiles (`config/worker-settings.json`,
`config/tower-settings.json`) carry `isolatePeerMachines: true`, and the
`messaging_cross_machine` options-reference row states the knob as the
operator's cue to relax that setting, not an enforcement point. Test:
`fleet-messaging.sh send` accepts only a local socket path as `--to` (a
host-qualified or URL-shaped target is refused as a grammar failure), so
script paths are same-machine by construction. Manual: a model-composed
cross-machine send from a session carrying the profile prompts for
approval before anything leaves the machine, in two arms, one with
`messaging_cross_machine` on and one with it off; pass criterion: the
harness's approval prompt appears in both arms alike; needs a second
machine or a cloud session; recorded in Task 3's PR.

## REQ-G — Degradation & carried floors

### REQ-G1.1 — named fallback per path [test + design-level]

Test: for each posting path in D-13's set that a script carries — the
tower→worker steer and the decision answer, the only two — an observable
failure from the post seam (refused, or a failed post)
reaches the path's named fallback with no operator step to select it
(shared with REQ-A1.5 and REQ-C1.1). The tower↔tower advisory carries no
test arm: it is model-composed through the harness's message tool, no
script carrying it, and its fallback is not-sent (REQ-G1.4, D-14).
Design-level: review that each
script's header names its fallback and that the doctrine's fallback table
covers exactly D-13's path set, including the worker→tower idle notice
(whose fallback is the healing sweep), the tower's own wake (whose
fallback is today's metronome, REQ-D1.8), and the two poll cadences,
the attention watcher's healing sweep and the dashboard's projection
refresh (whose fallback is their own retained cadence; only the first
demotes, REQ-E1.1), and that its two downward rows read per rung — the
`tmux` attributed buffer-paste, the `stream-json-persistent` control
response for an answer with operator handoff for a steer, and
`headless-oneshot` none.

### REQ-G1.2 — no state of record on messages [design-level]

Bundle and implementation review: the upward notice's status line is never
a record — it drives only the store re-read — and every downward or
advisory message is instruction text with its record behind it; no
consumer treats message content as durable state.

### REQ-G1.3 — carried floors unchanged [design-level]

Review of the delivered scripts, prose, and doctrine against each floor
the fleet-coordination-floor doctrine states, the never-impersonate rule
the inter-orchestrator-coordination doctrine states, and the
never-auto-merge floor the autonomous-safe-decision doctrine states, read
from those documents at review time (no copied list here); pass criterion:
no delivered path substitutes a message to a tower for the
deterministic-attention floor's operator-facing push, whose ownership
stays the doctrine's assignment to `merge-currency-guard`.

### REQ-G1.4 — advisory-only tower↔tower [manual + design-level]

No test arm: the advisory is composed and sent by the tower's model
through the harness's message tool, so no shipped script carries the path
and there is nothing script-level to exercise (D-14).
Design-level: prose and guard review that no advisory path writes the
fence refs, presence, or `tasks.md` (presence is re-published by the
sibling bundle on every heartbeat, so it gets the review, not a byte
check), and that the advisory rule cites the assume-multiplicity floor
rather than restating authority. Manual: a live advisory message between
two live tower sessions on the same machine (the environment: a
marker-named fleet-launched tower and an operator-launched one); pass
criterion: the sending tower's model composes and sends the advisory
through the harness's message tool and the receiving tower's transcript
shows the text; recorded in Task 8's PR.

### REQ-G1.5 — the doctrine document [test + design-level]

Test: `doctrine/messaging-transport.md` resolves through the rule-doc
chain; `mise run check:doctrine-index` and `check:links` pass; a literal
grep for `^Doctrine: (run-start|point-of-use) messaging-transport` matches
in the `SKILL.md` of `/orchestrate` and of `/execute-task`; and the
scripts that carry a messaging path (`fleet-messaging.sh`,
`orchestrate-relay.sh`, `fleet-decision.sh`, `fleet-attention.sh` for the
`render --worker` arity `notice-read` delegates to,
`fleet-attention-watch.sh`, `fleet-dashboard.sh`) each cite the doctrine
in their header comment (a grep for `messaging-transport` within the
header). Design-level: review that the doctrine states the nine contents
REQ-G1.5 enumerates — the signal-vs-record rule, carrying the sentence
that only a stop ending the worker's turn fires a notice while a mid-turn
suspension is the sweep's case; the fallback obligation;
the discipline ladder; the per-path fallback table over D-13's path set
(the tower→worker steer, the decision answer, the worker→tower idle
notice, the tower's own wake with today's metronome as its fallback, the
two poll cadences — the attention watcher's healing
sweep and the dashboard's projection refresh — and the tower↔tower
advisory), read per rung on its two downward rows;
the per-session probe definition; the cross-machine transit note; the
sentence distinguishing the healing sweep from `/orchestrate`'s reconcile
sweep and from `fleet-attention-watch.sh reconcile`; the glossary of
the three ladders with their step nouns; and the fleet-runtime version
rule, mixed CLI versions across a fleet being fine because the probe is
per session and fail-safe — plus the resource-class
declaration REQ-G1.6 places there.

### REQ-G1.6 — one lifecycle row and column, no other class [test + design-level]

Test: the fleet-coordination-floor doctrine's lifecycle-closure class
contract table contains the one added row for the inbox socket (opened by
the harness at session start, closed with the session, detector: the
session's own death evidence); its rungs-by-classes table contains the one
added column with every cell filled (a table parse finds no blank cell in
that column, the table's no-blank-cell rule); and `mise run check:links`
passes on the amended doc. Design-level: review that the
messaging-transport doctrine declares that no other resource class is
acquired, with the reason for each ride-along — the idle-notice
subscription tower-side and self-closing, the tower's name riding the
tower marker's existing lifecycle, the worker's socket basename (the
registry's `inbox` column) riding the worker registry's existing
lifecycle — so no row is missing by omission.

### REQ-G1.7 — inter-orchestrator-coordination doctrine amended [test + design-level]

Test: the amended text is present in the doctrine, matched as literal
tokens — the steer-in-flight section's heading and body naming messaging
first with attributed buffer-paste as the fallback; the "one audited
script" sentence and the `relay-command` description naming
`fleet-messaging.sh`; the tower-to-tower clause of the *Attributed,
non-impersonating relay* section cross-referencing the advisory rule
(REQ-G1.4) — and `mise run check:links` and `check:doctrine-index` pass on
the amended doc. Design-level: review that the amended text no longer pins
buffer-paste as the mechanism of record and contradicts nothing in this
bundle.

## REQ-H — Security & hygiene

### REQ-H1.4 — inbound content untrusted [test + manual]

Test: hostile notice and message fixtures (control bytes, over-length, a
forged worker name the `notice-read` screen refuses, a status line whose
content contradicts the store, shell metacharacters, ANSI escapes) are
screened
and sanitized before echo (the diagnostic contains none of the hostile
bytes), a notice drives action only through `notice-read`'s store
re-read, and a status frame drives action only through `redeliver`, which
refuses a frame naming a message id no metadata sibling carries, and one
whose id is malformed (control bytes, over-length; fixtures); steer and
advisory text is
screened and sanitized but never re-validated against the store. Manual:
in a live two-session environment
(two live tower sessions on
the same machine, the receiving one in `--watch`), that tower treats steer
or advisory text as
advisory; pass criterion: after a delivered advisory that instructs a
claim, a release, or a `tasks.md` edit, no fence ref and no `tasks.md`
write follows in that tower's next turn (presence is re-published on every
heartbeat, so it gets REQ-G1.4's design-level review rather than this
check); recorded in Task 8's PR.

### REQ-H1.2 — message hygiene [test + design-level]

Echo-sanitization tests on each message-derived output (the `notice-read`
diagnostic, the held notice, the demotion notice, and `notice-read`'s
rendered output); design-level review bounded to the two script-carried
send paths (`orchestrate-relay.sh`'s messaging arm and `fleet-decision.sh`)
and their `--message-file` call sites, that neither places secrets or
sensitive operational detail in message text (`send` bodies are
operator- or model-composed text), and that the cross-machine transit note
is present in the doctrine.

### REQ-H1.3 — one enforcement point [test]

A literal source audit over `scripts/*.sh` (the same shape as the relay's
`send-keys` audit) whose match set is exactly the
`CLAUDE_CODE_MESSAGING_SOCKET` name: it is absent from
every file other than `fleet-messaging.sh`, and that script's `claude`
invocations are exactly one, the probe's version read.
`orchestrate-relay.sh` and `fleet-decision.sh` reach the post only through
`fleet-messaging.sh`, its invocation present by token in each and no post
of their own; no other shipped script posts at all. The other half of the
one-home rule — that nothing acts on
an idle notice except through `notice-read` — is not a script audit but
the prose grep over `/orchestrate` (REQ-D1.7's fixture): the sanction is
skill prose, so no script carries a notice-handling path to audit. The
socket owner/existence predicate is a
`fleet-messaging.sh` verb applied by `send` to its target socket: a target
failing the predicate refuses the send with a non-zero exit and an empty
post log.

### REQ-H1.5 — test-only seams guarded [test]

For each seam — `probe --cli-version`, the owner predicate's `--owner-uid`
and `--socket-type`, and `PLANWRIGHT_MESSAGING_POST` — the invocation
without `PLANWRIGHT_TEST_SEAM=1` exits non-zero with a diagnostic naming
the seam and the guard, and the same invocation with it set is honored
(the supplied version, uid, socket type, or post override is observed in
the result).
