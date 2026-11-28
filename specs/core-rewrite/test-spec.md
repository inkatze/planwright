# Core rewrite — Test Spec

**Status:** Draft
**Last reviewed:** 2026-11-27
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: the core's verbs, engine, parser tier, state machine and
readiness computation are verified by `[test]` fixtures in the repository's CI
suite (the Go tests plus the existing shell suites the shims must keep
passing), each refusal fixture shown to fail once against a deliberately
broken build. The doctrine line is `[design-level]`. Sandbox behaviour,
service-mode latency and the slice measurements need a real host and are
`[test + manual]` or `[manual]`, with the measured reports as their artifacts.

## REQ-A — Mechanical enforcement

### REQ-A1.1 — Every rule has a code home [design-level]

The mechanical-enforcement rule doc (Task 4) states the rule and the open-gap
record form; each REQ in this bundle names its code home in its task's
deliverables, and the kickoff lens confirms no REQ here relies on an
instruction alone.

### REQ-A1.2 — Prose retires only against a refusing fixture [test]

Task 16's retirement list pairs each retired prose rule with a fixture; a
check fails when a retired rule names no fixture or the fixture passes against
a build with the code home removed.

### REQ-A1.3 — Asymmetric failure [test]

Fixtures feed unreadable, unknown-format and ambiguous inputs to the engine,
the record verbs and the readiness computation (each refuses or asks) and to
event dedupe (it delivers).

### REQ-A1.4 — Gates stay human [test]

The must-never-allow set includes merge outside a policy class, spec sign-off,
a ready flip outside the ready-flip policy, release publishing and a message
to a person; the replay and the engine suite fail when any is allowed, with
the policy data set to allow it.

### REQ-A1.5 — The rule doc and its lens [test]

The rule doc resolves through the rule-doc resolver and the doctrine index
check passes; a fixture bundle with an instruction-only requirement draws the
lens flag, and a clean fixture does not.

## REQ-B — The core program and store

### REQ-B1.1 — No toolchain to install or run [test]

A CI job per supported platform installs planwright on an image with no Go,
compiler or package manager and runs `planwright --version` and one verb.

### REQ-B1.2 — Embedded store, no server [test]

The build's dependency list is checked for no database, queue or message
client; the store opens in WAL mode in a fixture with no service running.

### REQ-B1.3 — Same decisions in both modes [test]

The engine and verb fixture suites run in direct mode and in service mode and
must produce identical decisions.

### REQ-B1.4 — Service mode only on a recorded yes [test]

Enabling service mode without a capability record is refused; the doctor
fixture prints each capability and each lack.

### REQ-B1.5 — Shims keep the entry points [test]

The shim check fails a fixture shim that does not exec the stable command
name; the existing suites pass through the shims.

### REQ-B1.6 — Work products exported [test]

A change to a rule, follow-up, decision or ledger row writes its text export;
a fixture rebuilds operational state from git, the forge fixture and the logs.

### REQ-B1.7 — Verified delivery [test]

A tampered asset and a wrong checksum are each refused at first use, with no
fallback to an unverified copy.

### REQ-B1.8 — Bare mode refused, hook self-check [test]

A launch requesting bare mode is refused; a session whose hook is disabled
stops at its first tool call with a message naming the hook.

## REQ-C — The pipeline state machine

### REQ-C1.1 — One machine, undefined transitions refused [test]

A table-driven fixture walks every defined transition and attempts every
undefined one; each undefined one is refused.

### REQ-C1.2 — Times and heads stamped by the core [test]

The record verbs take no time or head argument; a fixture that passes one is
refused, and recorded times fall between the verb's own begin and end.

### REQ-C1.3 — Prompt steps only after delivery [test]

A prompt-kind record attempted before its point's resolve, or with a start
before the delivery, is refused.

### REQ-C1.4 — Completion needs every record; convergence needs a clean pass [test]

A completion with a resolved step missing its record is refused; a convergence
completion after a pass that applied a change is refused.

### REQ-C1.5 — Records only through the verbs [test + manual]

File-tool writes to the store and record files are denied in the shipped
profiles (test); on a sandbox host a shell write to them is refused by the OS,
and a copied recorder records nothing (manual, recorded in Task 7's report).

### REQ-C1.6 — One readiness computation [test]

A flight, a spec task and a mission-control launch with the same records get
the same readiness verdict; readiness reads the forge fixture's current state,
not a stored claim.

### REQ-C1.7 — Generated handover, guarded take [test]

A generated brief lists every open unit, request, commitment and duty in the
fixture store; its diff against the previous brief is printed; take is refused
while one request is unacknowledged.

### REQ-C1.8 — Config from the session row [test]

A session with a wrong or missing overlay variable still resolves its own
program's config.

## REQ-D — The guard model

### REQ-D1.1 — One engine at every hook [test]

The hook is registered in the worker, tower and mission-control profiles and
for subagents (a profile check); each logged decision carries an input digest.

### REQ-D1.2 — Tier order [test]

Fixtures where two tiers would disagree resolve by the stated order; a floor
act is denied even when the policy data and a verb would allow it.

### REQ-D1.3 — Floor in settings too [test]

A profile check fails any shipped profile missing a floor deny or ask rule.

### REQ-D1.4 — Only irreversible or outward acts blocked [test]

Reversible local fixtures (in-worktree writes, builds, tests, commits on the
unit branch) are allowed and logged; outward fixtures go to a verb or ask.

### REQ-D1.5 — Sandbox profile [test + manual]

The profile check confirms the write list, the credential mask, unsandboxed
retry off and the required flag (test); on a sandbox host a write outside the
worktree and a mission-control repository write are refused by the OS
(manual, Task 7's report).

### REQ-D1.6 — Outward acts only through verbs [test + manual]

Each verb refuses arguments that do not match the session's row, and the
kickoff publish verb re-runs from a signed anchor (test); on a sandbox host a
shell push finds no credential (manual, Task 7's report).

### REQ-D1.7 — Push judges resolved refs [test]

Every push fixture targeting a protected or foreign branch (the 2026-11-27
option-swallow and brace or glob forms, and every push spelling in the
guard-coverage corpus) is refused; the unit's own branch pushes.

### REQ-D1.8 — Parser tier fails closed [test]

Fixtures with each non-literal word class in a command position and in a
judged argument all ask; literal allow-list commands are allowed.

### REQ-D1.9 — Shell guards removed only after shadow [manual]

Task 16's record shows the shadow window, zero floor disagreements and the
operator's recorded go before the removal commit.

## REQ-E — The approval flow

### REQ-E1.1 — Routine classes as policy data [test]

Each routine class has allow fixtures and near-miss fixtures that ask;
changing the policy data changes the decision with no code change.

### REQ-E1.2 — The engine answers [test]

A decidable call is answered by the engine with a logged decision and no
prompt reaches an owner.

### REQ-E1.3 — Whole prompts, inbox states, redelivery [test + manual]

A prompt larger than any display cap is stored and delivered whole; delivery
repeats until acknowledged (test); in service mode the timed fixture meets the
configured bound on a real host (manual).

### REQ-E1.4 — Escalation and per-program visibility [test]

An unanswered prompt escalates at its timer to the notification seam; a
program's listing excludes another program's prompts.

### REQ-E1.5 — Approvals as records [test]

A relayed go with a matching record performs its act; a mismatched hash, a
reused single-use record and a missing record are each refused.

### REQ-E1.6 — Request ledger carried [test]

control-plane REQ-J's verification entries are carried as fixtures over the
store.

### REQ-E1.7 — Event dedupe carried [test]

control-plane REQ-D's verification entries are carried as fixtures over the
store.

## REQ-F — Process lifecycle

### REQ-F1.1 — One row, atomic lifecycle [test]

Recover and relaunch keep the owner; a completed row is never removed while
its fixture process lives; a crash mid-transaction leaves the prior state.

### REQ-F1.2 — Supervisor owns pipes and groups [test]

A large frame write does not interleave; stop ends every process of the
worker's group in a fixture with a grandchild.

### REQ-F1.3 — Liveness from the recorded process [test]

Liveness of a fixture worker is answered with no process-table scan.

### REQ-F1.4 — Moving onto a new install [test + manual]

After a simulated update the daemon re-execs and new sessions carry the new
root (test); on this host a real update leaves no stale-root session unraised
(manual).

## REQ-G — Cost and throughput

### REQ-G1.1 — Diff-sized lenses, stop on an empty pass [test]

A fixture loop stops on its first non-applying pass; a later pass's lens set
covers only the previous pass's changed files.

### REQ-G1.2 — Round cap and wall-clock budget [test]

Reaching the cap or the budget records the outcome and runs no further pass.

### REQ-G1.3 — Hosted review once per final head [test]

A readiness fixture with a hosted-review run on a non-final head, with no code
fix round between, reports the defect.

### REQ-G1.4 — Test-time budget on touched files [test]

An untouched file over budget is retried once and reported; a touched file
over budget fails.

### REQ-G1.5 — Usage ladder fails closed [test]

An unreadable or refused usage or load read holds launches and raises an
event.

### REQ-G1.6 — Tiers resolved per point and step [test]

Resolver fixtures cover each launch point and step kind; a default change
without a cited measurement fails the defaults check.

### REQ-G1.7 — Idle end and measured handover threshold [test]

A worker whose wait passes the cache lifetime ends and is relaunched from a
generated brief; the threshold default cites its measurement.

### REQ-G1.8 — Slices measured against one baseline [manual]

Task 1's baseline and Task 16's report exist with each measure before and
after; a measure that did not move is raised to the operator before the next
slice, as the report records.

## REQ-H — Migration and safety

### REQ-H1.1 — Offline replay first [test]

The replay prints its per-tier report over a recorded window and exits
non-zero when a must-never-allow fixture is allowed.

### REQ-H1.2 — Shadow before live [manual]

Each live task's record cites its shadow window and its zero floor
disagreements.

### REQ-H1.3 — Kill switch [test]

The switch returns a fixture session to the shell path; the floor still
denies afterwards.

### REQ-H1.4 — Fixtures first, positive control [test]

Each policy and guard task's first commit adds failing fixtures; the positive
control fails the harness when the engine is replaced by an allow-all stub.

## REQ-I — Supersession

### REQ-I1.1 — control-plane superseded [test]

The validator passes control-plane with Status Superseded and its
`Superseded-by:` pointer.

### REQ-I1.2 — universal-binary Tasks 9 to 14 retired [test]

The validator passes universal-binary with each of Tasks 9 to 14 carrying an
Out-of-scope reference bullet citing this bundle.

### REQ-I1.3 — Guard mechanism replaced, approval rule amended [design-level]

The amended worker-permission-ergonomics REQ-F1.2 and execution-backends D-5
cite this bundle's D-7; the amendment entries exist in each bundle's
changelog.
