# shellcheck shell=bash
# inception-fixture.sh — the golden compliant inception bundle the inception
# suites mutate (sourced, never executed).
#
# One writer, two shapes: an untracked venture (the default) and a tracked one
# (`tracked` as the second argument), because the track rules in
# doctrine/inception-format.md are conditional on the venture declaring tracks
# and cannot be exercised from a single bundle. Everything else is shared, so a
# seeded-violation fixture is one `sed`/append away from the compliant baseline
# and the diff between "passes" and "fails" is exactly the rule under test.
#
# The bundle is deliberately unremarkable content: an internal ops tool, no
# real people, no hostnames, no credentials (the artifact data-hygiene rule in
# doctrine/security-posture.md applies to fixtures too — they are committed).
#
# Usage:
#   . tests/lib/inception-fixture.sh
#   inception_fixture_write <dir> [tracked]

# inception_fixture_write <dir> [tracked] — write the five authored files.
# Creates <dir> if needed. Prints nothing; returns non-zero on a write failure.
inception_fixture_write() {
  _if_dir=$1
  _if_shape=${2:-untracked}

  mkdir -p "$_if_dir" || return 1

  if [ "$_if_shape" = tracked ]; then
    _if_tracks_section='## Tracks

- **capture** — the single capture surface and its fan-out
- **measure** — the handover-time measurement pipeline

'
    _if_track_a1='
- **Track:** capture'
    _if_track_a2='
- **Track:** capture'
    _if_track_a4='
- **Track:** measure'
    _if_track_d1='
- **Track:** capture'
    _if_track_d2='
- **Track:** capture'
    _if_track_t1='
- **Track:** capture'
    _if_track_t2='
- **Track:** measure'
    _if_track_t3='
- **Track:** capture'
    _if_gate_tracks='Tracks: capture=Recycle, measure=Recycle
'
  else
    _if_tracks_section=
    _if_track_a1=
    _if_track_a2=
    _if_track_a4=
    _if_track_d1=
    _if_track_d2=
    _if_track_t1=
    _if_track_t2=
    _if_track_t3=
    _if_gate_tracks=
  fi

  cat >"$_if_dir/brief.md" <<EOF || return 1
# Northwind Signals — Brief

**Status:** Exploring
**Last reviewed:** 2026-08-20
**Format-version:** 1.0

## Opportunity

- **Framing:** Ops leads re-key the same incident summary into three tools; the duplication shows
  up as dead time in the 2026-07 workflow audit.
- **Who hurts:** An ops lead closing an incident at end of shift with the handover report due.
- **No-gos & sketch:** No agent-authored customer messaging. Sketch: one capture surface that
  fans out to the three existing sinks.
- **Chain:** The ops lead files once → the three sinks stay in sync → handover time drops.

## Success metric

Median incident-handover time drops below ten minutes within one quarter of adoption.

## Appetite

_Skipped: appetite is set at the portfolio level and re-derived at the first gate._

## Kill criteria

**Gate decider:** Dana Reyes

- **KC-1:** three ops leads have run a full week on the capture surface — by 2026-10-01
- **KC-2:** the handover-time measurement pipeline reports weekly — by 2026-09-15

${_if_tracks_section}## Existing alternatives

Runbook macros and a shared spreadsheet cover part of the fan-out; neither closes the loop.

## Business viability

_Skipped: internal tool with no external market, pricing, or channel question this cycle._

## Strategy fit

Rides the incident-tooling consolidation already funded for the year.

## Sources

- **workflow audit** — the 2026-07 ops workflow timing audit — \`sources/workflow-audit.md\`
- **handover interviews** — five ops-lead interviews — held out: the notes name individuals

## Gate log

### Gate 1 — 2026-08-18

Outcome: Recycle
Date: 2026-08-18
Decider: Dana Reyes
Evidence: A-1 (stated-intent)
Thresholds: A-1 open, A-2 open
Kill-criteria: KC-1 clear, KC-2 clear
${_if_gate_tracks}Rationale: The capture-surface spike has not run yet; re-scope the plan and return.

## Changelog

- 2026-08-01 — venture opened at Exploring.
- 2026-08-10 — A-3 superseded by A-4.
- 2026-08-18 — Gate 1 recorded (Recycle).
EOF

  cat >"$_if_dir/disciplines.md" <<EOF || return 1
# Northwind Signals — Disciplines

**Status:** Exploring
**Last reviewed:** 2026-08-20
**Format-version:** 1.0

## Discipline map

| Discipline | Touches | Undecided decisions |
| --- | --- | --- |
| product-strategy | which handover moment the surface owns | DEC-1 |
| software-engineering | the fan-out integration seam | DEC-2 |
| org-design | who owns the surface after launch | none |

## Staffing table

| Discipline | Staffing | Card / person |
| --- | --- | --- |
| product-strategy | agent-persona | product-strategy |
| software-engineering | named-human | Kim Alvarez |
| org-design | unstaffed | none |

## Stakeholder map

| Decision area | Decides | Aligned | Informed |
| --- | --- | --- | --- |
| venture direction | Dana Reyes | Kim Alvarez | ops leads |
| integration seam | Kim Alvarez | none | Dana Reyes |
| post-launch ownership | Dana Reyes | none | none |
EOF

  cat >"$_if_dir/assumptions.md" <<EOF || return 1
# Northwind Signals — Assumptions

**Status:** Exploring
**Last reviewed:** 2026-08-20
**Format-version:** 1.0

### A-1 — ops leads will file once instead of three times

- **Statement:** believe ops leads will file once instead of three times; verify with a two-week
  shadow run; measure the share of incidents filed through the surface; right if at least seven
  of ten incidents arrive through it.
- **Risk-if-wrong:** the fan-out saves no time and the venture has no value story
- **Risk-tag:** value
- **Threshold:** at least 7 of 10 incidents filed through the surface over two weeks
- **Evidence:** stated-intent — handover interviews
- **Blocking:** yes
- **Tasks:** T-1
- **Status:** testing${_if_track_a1}

### A-2 — the three sinks accept writes from one surface

- **Statement:** believe all three sinks accept programmatic writes; verify by writing a canned
  incident into each; measure the write success rate; right if all three accept without a manual
  step.
- **Risk-if-wrong:** the fan-out needs a human relay and the time saving disappears
- **Risk-tag:** feasibility
- **Threshold:** none
- **Evidence:** none
- **Blocking:** yes
- **Tasks:** T-2
- **Status:** open${_if_track_a2}

### A-3 — ops leads want a chat-first capture surface

- **Statement:** believe ops leads want capture in chat; verify by asking; measure stated
  preference; right if most name chat first.
- **Risk-if-wrong:** the surface lands in the wrong place
- **Risk-tag:** usability
- **Threshold:** none
- **Evidence:** none
- **Blocking:** no
- **Tasks:** none
- **Status:** open
- **Superseded-by:** A-4 (2026-08-10)

### A-4 — the handover report is the moment worth instrumenting

- **Statement:** believe the handover report is the moment worth instrumenting; verify with the
  timing audit; measure minutes spent per handover; right if handover dominates the re-keying
  time.
- **Risk-if-wrong:** the venture instruments a moment nobody feels
- **Risk-tag:** viability
- **Threshold:** none
- **Evidence:** none
- **Blocking:** no
- **Tasks:** none
- **Status:** waived — internal tool; the portfolio already funds the handover moment${_if_track_a4}
EOF

  cat >"$_if_dir/decisions.md" <<EOF || return 1
# Northwind Signals — Decisions

**Status:** Exploring
**Last reviewed:** 2026-08-20
**Format-version:** 1.0

### DEC-1 — which handover moment the capture surface owns

- **Status:** open
- **Door:** two-way
- **Discipline:** product-strategy
- **Deciders:** Dana Reyes
- **Options:**
  - end-of-shift handover only — narrowest surface, clearest metric
  - every incident close — broader reach, weaker metric
- **Outcome:** open — waiting on the A-1 shadow run
- **Consequences:** sets what the success metric measures
- **Feed-forward:** the capture-surface spec's scope section${_if_track_d1}

### DEC-2 — fan-out seam: write directly or through the existing relay

- **Status:** decided
- **Door:** one-way
- **Discipline:** software-engineering
- **Deciders:** Kim Alvarez
- **Options:**
  - direct writes to each sink — fewer hops, three integrations to own
  - reuse the existing relay — one integration, inherits the relay's latency
- **Outcome:** reuse the existing relay (2026-08-12)
- **Consequences:** the venture owns one integration and inherits relay latency as a known cost
- **Feed-forward:** the integration section of the capture-surface spec${_if_track_d2}
EOF

  cat >"$_if_dir/plan.md" <<EOF || return 1
# Northwind Signals — Plan

**Status:** Exploring
**Last reviewed:** 2026-08-20
**Format-version:** 1.0

**Limiting constraint:** A-1

### T-1 — two-week shadow run of the capture surface

- **Kind:** spike
- **Tests:** A-1
- **Done when:** ten incidents have been offered to the surface and the filed share is recorded
- **Cap:** two weeks of elapsed time, no more than three engineer-days
- **Status:** running${_if_track_t1}

### T-2 — write a canned incident into each sink

- **Kind:** research
- **Tests:** A-2
- **Done when:** each sink has accepted or rejected a canned write and the result is written up
- **Cap:** one engineer-day
- **Status:** planned${_if_track_t2}

### T-3 — align on which handover moment the surface owns

- **Kind:** alignment
- **Tests:** DEC-1
- **Target:** venture direction
- **Done when:** the decision area's decider has recorded a position
- **Cap:** one 30-minute conversation
- **Status:** planned${_if_track_t3}
EOF

  return 0
}
