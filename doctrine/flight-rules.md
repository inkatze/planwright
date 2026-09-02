# Flight Rules

planwright routes every request onto one of two rules: **visual flight** — specless
work, where no spec bundle is authored and the audit record carries the trust — or
**instrument flight**, the spec pipeline. The names are the aviation analogy: visual
rules when conditions are clear enough to fly by what you can see, instrument rules
when you file a plan and trust the gauges (D-3).

This doc is the routing rule and the guarantees the specless side owes. It states
that rule as **law, not as demonstrated behavior** (REQ-B1.6). Throughout, *the
tower* names the standing conversational front-door session (D-2).

The rule is [proportionality](proportionality.md) operationalized one level up:
stake and reversibility already scale rigor inside a change; here they choose the
route the whole request takes (D-1).

Citations: tower-front-door REQ-A1.2, REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4,
REQ-B1.5, REQ-B1.6, REQ-C1.6, REQ-E1.1, REQ-E1.2, REQ-E1.4, REQ-E1.5, REQ-F1.3,
REQ-F1.5, REQ-F1.6, REQ-G1.1, REQ-G1.2, REQ-G1.3, REQ-G1.4, REQ-H1.4 ·
tower-front-door D-1, D-2, D-3, D-4, D-5, D-6, D-7, D-10.

## The routing rule (D-4)

The route is chosen **per request**, by the tower, and is never a user-selected
mode, flag, or persistent setting (REQ-B1.1). Two consecutive asks in one session
may route differently, and nothing carries over between them.

Three classes of signal decide it:

- **Automatic escalation.** Work centered in a hard-disqualifier zone
  ([finding-categorization](finding-categorization.md): security-sensitive code,
  migrations and destructive operations, CI configuration, lockfiles, secrets
  files), or otherwise not one revert from undone — published interfaces, data
  deletion, external side effects — files instrument flight automatically
  (REQ-B1.2). Whether work is zone work is governed by **where the fix lands**,
  not where the symptom shows; a deliverable that itself lives in a zone lands
  behind a draft PR with its pending-sign-off checklist (D-4).
- **Declared judgment.** Ambiguity escalates: when the tower cannot state a
  Done-when the user would agree with, it files. This lane is judgment and says
  so — it is not a mechanical trigger dressed as one (D-4, REQ-B1.2).
- **Advisory only.** Size proxies — diff size, file count, estimated effort —
  inform the statement and never decide it. A large but safe and reversible ask
  flies visual (D-4, REQ-B1.2).

### Grounds are stated, always (REQ-B1.3)

Routing is never silent. At routing time the tower states the route and its
grounds in one line: **the trigger that fired, and the one-line evidence for it**
(*"instrument flight: the change lands in the auth middleware — zone work"*). A
route stated without grounds is a defect, not a terse success.

The evidence behind that statement stays inside the tower-frugality bound
(REQ-A1.2, [work-placement](work-placement.md)): the tower routes on what it can
see in bounded context, never on an ingestion sweep it runs itself. When the route
cannot be decided from bounded evidence, it asks, or offloads the look — it does
not fill its own window to find out (D-1).

### The override (D-5)

One sentence forces either rule in either direction — never a config change, never
a flag. It is recognized **semantically**: D-5's "just do it" and "write this one
up" are exemplars of the two directions, not magic phrases, and an equivalent
sentence in the user's own words is the same override.

When an override crosses an automatic escalation trigger, the tower **states its
reservation and the trigger's grounds, then complies** (REQ-B1.4). The stated
reservation is the whole ceremony; there is no second confirmation.

No override crosses a hard invariant (D-5): merge stays the human's (REQ-G1.1),
the specless path invents no shadow sign-off (REQ-G1.2), commits are new commits
only (REQ-G1.3), and PRs open as drafts for the human to flip (REQ-G1.4). Those
hold on both rules, overridden or not.

### Decomposition (REQ-C1.6)

One ask may fan into several flights, one per coherent unit, each routed on its
own and each with its own stated grounds. A mixed-stake ask is decomposed, not
routed by its riskiest clause: filing the whole thing because one part touches a
zone re-imposes the entry fee the routing rule exists to remove.

## The flight boundary (REQ-C1.6)

**A flight is a unit of repo-mutating specless work.** "Instrument flight" names a
route, never a flight unit; nothing on the spec path is a flight.

- **Read-only asks carry no flight identity.** A read-only ask exceeding the
  inline bound is offloaded through the work-placement axioms and its result
  returns to the conversation — no flight branch, no worktree, no draft PR, no
  flight record.
- **Mid-offload re-route.** A mutation need surfaced during a read-only offload
  comes back as a **new routed request**. A read-only worker never converts in
  place: converting would mint flight identity behind the router's back, unrouted
  and unrecorded.
- **Mid-flight re-route.** A flight whose scope outgrows the route it was given
  parks behind its hard pause and returns for re-routing rather than flying on.
  Routing is preventive, not enforcement (D-4, REQ-B1.5): the
  [gate-wiring](gate-wiring.md) hard pauses stay in force inside every worker
  whatever the route, and a pause is exactly where an outgrown route surfaces.

## The audit record (D-6)

On the specless path the record, not a spec, is what carries trust. The flight
worker authors and lands it, and it carries (REQ-E1.1):

- the **quoted ask**, sanitized per [security-posture](security-posture.md)
  data-hygiene and markup-neutralized before it reaches any committed or remote
  surface;
- the **routing decision and its grounds**, as stated in the conversation;
- the **convergence audit tables** the review skills produce: lens coverage, the
  four buckets, the declined log, and the pending-sign-off checklist;
- **any rigor scoping actually applied** inside the configured `review_sequence`.
  Visual flight runs the same sequence instrument flight runs; proportionality may
  scope rigor inside a pass, but a scoping that is not declared did not happen
  (D-7);
- the **worker handle**; and
- the **revert path**.

The record's home is adaptive and **declared at routing time** (D-6, REQ-E1.2):
the draft PR body where a remote and `gh` are available, a committed per-flight
record file riding the flight's own branch otherwise. Both homes render
human-first (REQ-E1.5) — a lead a human PR author would write (what changed, why,
how it was verified; no restated prompt, no filler) with the full contract
collapsed below it.

The record is an audit artifact, not an accumulator (D-6): it collects no deferred
decisions, so it owes no named reader and no drain ritual
([accumulator-taxonomy](accumulator-taxonomy.md)). The pending-sign-off checklist
it renders keeps its own PR-review drain.

## Specless traceability (REQ-E1.4)

Specless is not traceless. **Specless traceability is the ask, the route and its
grounds, the evidence, and the revert path, cited in the record.** That is the
whole definition, and every visual flight owes all four.

REQ-level traceability — requirements, design decisions, task citations, a test
spec pinning each REQ to a verification path — is precisely what escalation to
instrument flight buys. The two are not competitors: the routing rule decides
which of them a given request deserves.

## Survival guarantees (D-10)

Every guarantee about work surviving the tower is stated in the
**bounded-or-surfaced** form, never absolutely (REQ-F1.6):

> Best-effort while the substrate is reachable; every residue is bounded and
> swept, or durably surfaced to the operator. Never silent.

Concretely: flights run on rungs that outlive the session that dispatched them,
and their worktrees, branches, and records are durable (REQ-F1.3). What that buys
is itself stated in the bounded form rather than as an absolute: a killed tower
leaves every residue bounded and swept, or durably surfaced — never silently
lost. It is not a promise that nothing is ever left behind. Dead flight workers
inherit the fleet crash-loop policy (D-10, REQ-F1.5): bounded backoff relaunch
against the flight's own worktree and branch, then escalation to the human at the
disable threshold.

An absolute survival or cleanup claim on any surface this doctrine governs is a
defect. The bounded-or-surfaced form is what makes the guarantee checkable.
