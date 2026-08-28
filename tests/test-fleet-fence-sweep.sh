#!/bin/bash
# Tests for `scripts/fleet-fence.sh sweep` — the discovery sweep that closes
# the fence lifecycle: GC a terminal unit's fence, honor a live owner's, and
# surface everything else to the durable dedup'd operator sink
# (concurrent-orchestrator-coordination Task 4: D-7, D-13 ·
# REQ-C1.3, REQ-C1.5, REQ-C1.7).
#
# Classification is TERMINAL-FIRST, THEN LIVENESS:
#   terminal (merged PR / ledger-done)  → GC, regardless of owner liveness
#   live owner, not terminal            → honored, left alone
#   dead / unknown / ambiguous owner    → strand, SURFACED, never reclaimed
#   no owner on the presence surface    → tentative, then surfaced after a
#                                         one-pass grace re-check
#   evidence unreadable                 → hold: do not act, retry next pass
#
# Nothing is ever auto-reclaimed: reclaim is a reserved operator decision.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

# --- stub script dir: the sibling-resolved death predicate is a fixture -----
stubbin="$tmp/stub-scripts"
mkdir -p "$stubbin"
cp "$here/../scripts/"*.sh "$stubbin/"
cat >"$stubbin/fleet-death-evidence.sh" <<EOF
#!/bin/sh
verdict=\$(cat "$tmp/evidence-verdict")
printf '%s\n' "\$verdict"
case \$verdict in
  dead) exit 0 ;;
  alive) exit 1 ;;
  *) exit 3 ;;
esac
EOF
chmod +x "$stubbin/fleet-death-evidence.sh"
printf 'alive\n' >"$tmp/evidence-verdict"

# `orchestrate-state.sh` probes `gh` for PR state whenever a remote is
# configured and gh is on PATH. A local bare-repo origin plus the ambient gh
# would make EVERY pass a degraded one, so the fixture supplies its own: it
# emits the TSV the probe asks for (headRefName/state/number/mergedAt) from a
# file the tests rewrite, and a second stub dir stands in for a failing gh.
ghbin="$tmp/ghbin"
mkdir -p "$ghbin"
: >"$tmp/gh-prs"
cat >"$ghbin/gh" <<EOF
#!/bin/sh
cat "$tmp/gh-prs"
EOF
chmod +x "$ghbin/gh"
ghbroken="$tmp/ghbroken"
mkdir -p "$ghbroken"
printf '#!/bin/sh\nexit 1\n' >"$ghbroken/gh"
chmod +x "$ghbroken/gh"
GHBIN="$ghbin"

FF="$stubbin/fleet-fence.sh"
FP="$stubbin/fleet-presence.sh"
FA="$stubbin/fleet-attention.sh"

# --- fixture: bare origin, one clone, a real four-file spec bundle ----------
origin="$tmp/origin.git"
git -c init.defaultBranch=main init -q --bare "$origin"
git clone -q "$origin" "$tmp/co" 2>/dev/null
co="$tmp/co"
git -C "$co" config user.email fence@test.invalid
git -C "$co" config user.name fence-test
# Pin the local branch name: PLANWRIGHT_BASE_REF below reads the LOCAL `main`,
# and a host whose init.defaultBranch is `master` (git's built-in default)
# would otherwise leave it nonexistent and degrade every derivation.
git -C "$co" symbolic-ref HEAD refs/heads/main

mkdir -p "$co/specs/demo"
cat >"$co/specs/demo/tasks.md" <<'TASKS'
# Demo — Tasks

**Status:** Ready
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — Terminal by trailer

- **Deliverables:** a thing
- **Done when:** it is done
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** half day

### Task 2 — Live owner holds it

- **Deliverables:** a thing
- **Done when:** it is done
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** half day

### Task 3 — Dead owner, nothing downstream

- **Deliverables:** a thing
- **Done when:** it is done
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** half day

### Task 4 — Dead owner, commits but no PR

- **Deliverables:** a thing
- **Done when:** it is done
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** half day

### Task 5 — Unknown-owner orphan

- **Deliverables:** a thing
- **Done when:** it is done
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** half day

### Task 6 — Late-attributed orphan

- **Deliverables:** a thing
- **Done when:** it is done
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** half day

### Task 7 — Dead owner, open unmerged PR

- **Deliverables:** a thing
- **Done when:** it is done
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** half day

### Task 8 — Dead owner, merged PR

- **Deliverables:** a thing
- **Done when:** it is done
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
TASKS

(
  cd "$co"
  git add specs
  git commit -qm "spec fixture"
  # Task 1 is TERMINAL by the durable completion trailer, reachable from base.
  git commit -q --allow-empty -m "close task 1

Planwright-Task: demo/1"
  git push -q origin HEAD:refs/heads/main
  # Task 4 carries task-branch commits but no PR: NOT terminal.
  git branch -q planwright/demo/task-4
  git push -q origin planwright/demo/task-4:refs/heads/planwright/demo/task-4
  git branch -q planwright/demo/task-7
  git push -q origin planwright/demo/task-7:refs/heads/planwright/demo/task-7
  git branch -q planwright/demo/task-8
  git push -q origin planwright/demo/task-8:refs/heads/planwright/demo/task-8
)
# Task 7's PR is OPEN and unmerged — explicitly NOT terminal (REQ-C1.5), so
# its fence persists across the whole open-PR window. Task 8's is MERGED, so
# task 8 IS terminal and its fence is swept.
printf 'planwright/demo/task-7\tOPEN\t7\t\n' >"$tmp/gh-prs"
printf 'planwright/demo/task-8\tMERGED\t8\t2026-08-01T00:00:00Z\n' >>"$tmp/gh-prs"
git -C "$co" fetch -q origin
export PLANWRIGHT_BASE_REF=main

home="$tmp/fleet"
mkdir -p "$home"
chmod 700 "$home"

uuid_self="11111111-1111-1111-1111-111111111111"
uuid_peer="22222222-2222-2222-2222-222222222222"

pw() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    PLANWRIGHT_FLEET_STATE_DIR="$home" PLANWRIGHT_BASE_REF=main \
    PATH="$GHBIN:$PATH" \
    /bin/sh "$@"
}

run() { # run <expected-exit> <label> <args...>
  local want=$1 label=$2
  shift 2
  local out rc=0
  out=$(pw "$@" 2>&1) || rc=$?
  if [ "$rc" != "$want" ]; then
    echo "$out" >&2
    fail "$label: expected exit $want, got $rc"
  fi
  printf '%s' "$out"
}

sweep() { # sweep <expected-exit> <label> [extra args...]
  run "$1" "$2" "$FF" sweep --checkout "$co" --spec demo \
    --session-id "$uuid_self" "${@:3}"
}

origin_refs() {
  git -C "$origin" for-each-ref --format='%(refname)' refs/planwright-fence
}

sink() {
  pw "$FA" render 2>/dev/null || true
}

sink_count() {
  sink | grep -c 'pwfence' || true
}

# The peer publishes a presence record listing the units it fences, which is
# what makes a fence attributable (REQ-A1.2 currently-fenced-unit field).
publish_peer() { # publish_peer <fenced-csv>
  pw "$FP" publish --checkout "$co" --session-id "$uuid_peer" \
    --specs demo --fenced "$1" --pid 4242 >/dev/null \
    || fail "peer presence publish failed"
}

# ==========================================================================
# Fence the units under test
# ==========================================================================
for u in 1 2 3 4 5; do
  run 0 "fence/$u" "$FF" fence --checkout "$co" --spec demo "$u" >/dev/null
done
[ "$(origin_refs | wc -l | tr -d ' ')" = 5 ] || fail "fixture: expected 5 fences"

publish_peer "demo/1,demo/2,demo/3,demo/4"

# ==========================================================================
# REQ-C1.5 / REQ-C1.3 — terminal first: a merged/ledger-done unit's fence is
# GC'd regardless of who owns it or whether they are alive
# ==========================================================================
printf 'alive\n' >"$tmp/evidence-verdict"
out=$(sweep 0 "sweep/live-owner")

printf '%s\n' "$out" | grep -q "^gc	refs/planwright-fence/demo/1$" \
  || fail "terminal unit's fence was not GC'd: $out"
origin_refs | grep -q 'demo/1$' && fail "the terminal fence is still on origin"

# A live owner's non-terminal fence is honored: not GC'd, not surfaced.
printf '%s\n' "$out" | grep -q "^honored	refs/planwright-fence/demo/2	$uuid_peer$" \
  || fail "live owner's fence not honored: $out"
origin_refs | grep -q 'demo/2$' || fail "a live owner's fence was deleted"
sink | grep -q 'demo:2' && fail "a live owner's fence raised an operator item: $(sink)"

# ==========================================================================
# REQ-C1.3 / REQ-C1.7 — a dead owner's non-terminal unit is SURFACED, never
# reclaimed. A non-merged downstream artifact does not suppress the strand.
# ==========================================================================
# Units 7 and 8 join now, so their terminal-vs-strand classification is made
# against an owner that is POSITIVELY DEAD: that is what makes it an assertion
# about terminal-first ordering rather than about liveness.
run 0 "fence/7" "$FF" fence --checkout "$co" --spec demo 7 >/dev/null
run 0 "fence/8" "$FF" fence --checkout "$co" --spec demo 8 >/dev/null
publish_peer "demo/2,demo/3,demo/4,demo/7,demo/8"
printf 'dead\n' >"$tmp/evidence-verdict"
out=$(sweep 0 "sweep/dead-owner" --min-interval 0)

# Task 3: dead owner, no downstream artifact at all.
printf '%s\n' "$out" | grep -q "^strand	refs/planwright-fence/demo/3	$uuid_peer	dead$" \
  || fail "dead owner + no artifact was not surfaced as a strand: $out"
# Task 4: dead owner whose unit carries task-branch commits but no PR. No live
# tower will carry that work to merge, so it is a strand, not completion.
printf '%s\n' "$out" | grep -q "^strand	refs/planwright-fence/demo/4	$uuid_peer	dead$" \
  || fail "dead owner + commits-no-PR was not surfaced as a strand: $out"

# Task 7: dead owner whose unit has an OPEN, unmerged PR. Still not terminal —
# a dead tower cannot carry its own PR to merge — so it is surfaced too.
printf '%s\n' "$out" | grep -q "^strand	refs/planwright-fence/demo/7	$uuid_peer	dead$" \
  || fail "dead owner + open unmerged PR was not surfaced as a strand: $out"
origin_refs | grep -q 'demo/7$' || fail "an open PR's fence was GC'd (it is not terminal)"

# Task 8: dead owner but a MERGED PR. That is terminal, so it is GC'd, not
# surfaced — terminal-first outranks liveness.
printf '%s\n' "$out" | grep -q "^gc	refs/planwright-fence/demo/8$" \
  || fail "a merged PR's fence was not GC'd: $out"
origin_refs | grep -q 'demo/8$' && fail "a terminal (merged-PR) fence survived the sweep"
printf '%s\n' "$out" | grep -q "^strand	refs/planwright-fence/demo/8" \
  && fail "a terminal unit was surfaced as a strand"

# Never auto-reclaimed: the refs stay, and no re-dispatch happens.
origin_refs | grep -q 'demo/3$' || fail "a strand's fence was auto-reclaimed (deleted)"
origin_refs | grep -q 'demo/4$' || fail "a strand's fence was auto-reclaimed (deleted)"

# Each entry names the unit and a defined operator action.
s=$(sink)
printf '%s\n' "$s" | grep -q 'demo:3' || fail "sink entry does not name the unit: $s"
q=$(pw "$FA" queue 2>/dev/null || true)
printf '%s\n' "$q" | grep -q 'reclaim' || fail "sink entry offers no reclaim action: $q"
printf '%s\n' "$q" | grep -q 'investigate' || fail "sink entry offers no investigate action: $q"
printf '%s\n' "$q" | grep -q 'dismiss' || fail "sink entry offers no dismiss action: $q"
# Data hygiene (REQ-D1.4): neither the peer's checkout path nor its raw
# death handle reaches the operator surface.
printf '%s\n' "$q$s" | grep -q "$co" && fail "a checkout path leaked into the sink"
printf '%s\n' "$q$s" | grep -qE 'process 4242|tmux-window' && fail "a death handle leaked into the sink"

# ==========================================================================
# REQ-C1.7 — the sink is DEDUPLICATED: the same unresolved strand observed on
# successive passes is raised once, not re-raised every pass
# ==========================================================================
before=$(sink_count)
out=$(sweep 0 "sweep/dedup" --min-interval 0)
[ "$(sink_count)" = "$before" ] \
  || fail "a second pass over the same strand added sink entries ($before -> $(sink_count))"
printf '%s\n' "$out" | grep -q "^strand	refs/planwright-fence/demo/3" \
  || fail "a re-observed strand stopped being reported at all: $out"

# What "raised once" has to protect is the OPERATOR'S ANSWER. The attention
# surface upserts by worker handle, so a sweep that re-raises an entry every
# pass replaces the row — silently discarding an answer the operator already
# gave and resetting the first-seen timestamp the cadence window is measured
# from. Answer the strand, sweep again, and require the answer to survive.
skey3=$(sink | awk '/demo:3/ {print $3}')
[ -n "$skey3" ] || fail "no sink entry to answer for demo:3"
pw "$FA" claim "$skey3" "$skey3" reclaim >/dev/null \
  || fail "could not answer the strand's operator item"
pw "$FA" queue 2>/dev/null | grep -q '^    answered: reclaim$' \
  || fail "the answered strand did not record the operator's choice"
out=$(sweep 0 "sweep/answer-survives" --min-interval 0)
pw "$FA" queue 2>/dev/null | grep -q '^    answered: reclaim$' \
  || fail "a later sweep clobbered the operator's answer to an already-raised strand"

# REQ-C1.3 — an already-surfaced strand is skipped while its sink entry is
# younger than the cadence window. The window runs from FIRST observation and
# never renews, so what the skip suppresses is the per-ref attribution
# subprocess, not the sweep's `origin` reads: the namespace read and the state
# derivation are hoisted above the per-ref loop and cost one `ls-remote` and one
# derivation per pass however many strands are queued.
out=$(sweep 0 "sweep/cadence-suppressed" --min-interval 9999)
printf '%s\n' "$out" | grep -q "^suppressed	refs/planwright-fence/demo/3$" \
  || fail "an already-surfaced strand was re-probed inside its cadence window: $out"

# ==========================================================================
# REQ-C1.3 — unclassifiable liveness is surfaced, never silently honored
# ==========================================================================
printf 'unknown\n' >"$tmp/evidence-verdict"
pw "$FA" clear "$(sink | awk '/demo:3/ {print $3}')" >/dev/null 2>&1 || true
out=$(sweep 0 "sweep/unknown-liveness" --min-interval 0)
printf '%s\n' "$out" | grep -q "^strand	refs/planwright-fence/demo/3	$uuid_peer	unknown$" \
  || fail "an unknown-liveness owner was not surfaced: $out"

# ==========================================================================
# REQ-C1.3 — an unknown-owner orphan surfaces only after a one-pass grace
# re-check, because a live tower's fenced-unit list is only as fresh as its
# last heartbeat: surfacing on sight would raise a FALSE strand on a unit that
# is legitimately in flight.
# ==========================================================================
# demo/5 is fenced but listed by no presence record at all.
out=$(sweep 0 "sweep/orphan-grace" --min-interval 0 --grace 9999)
printf '%s\n' "$out" | grep -q "^tentative	refs/planwright-fence/demo/5$" \
  || fail "an unknown-owner orphan was not held tentative on first sight: $out"
q=$(pw "$FA" queue 2>/dev/null || true)
printf '%s\n' "$q" | grep -q 'reclaim' || true

# Still inside the grace window on the next pass: still tentative.
out=$(sweep 0 "sweep/orphan-still-in-grace" --min-interval 0 --grace 9999)
printf '%s\n' "$out" | grep -q "^tentative	refs/planwright-fence/demo/5$" \
  || fail "the grace window did not hold across passes: $out"

# Once the grace window has elapsed, the still-unattributed orphan is promoted
# to a surfaced strand. The grace memory lives in the durable sink, not in the
# tower, so it holds cross-tower and a stateless tower keeps no local store.
out=$(sweep 0 "sweep/orphan-promoted" --min-interval 0 --grace 0)
printf '%s\n' "$out" | grep -q "^strand	refs/planwright-fence/demo/5	unknown-owner	orphan$" \
  || fail "an orphan past its grace window was not promoted to a strand: $out"
origin_refs | grep -q 'demo/5$' || fail "an orphan strand's fence was auto-reclaimed"

# An orphan that becomes attributable before its grace elapses is SWEPT, not
# promoted: the owner's heartbeat simply caught up.
run 0 "fence/6" "$FF" fence --checkout "$co" --spec demo 6 >/dev/null
printf 'alive\n' >"$tmp/evidence-verdict"
out=$(sweep 0 "sweep/orphan-new" --min-interval 0 --grace 9999)
printf '%s\n' "$out" | grep -q "^tentative	refs/planwright-fence/demo/6$" \
  || fail "the new orphan was not held tentative: $out"
publish_peer "demo/2,demo/3,demo/4,demo/6"
out=$(sweep 0 "sweep/orphan-attributed" --min-interval 0 --grace 0)
printf '%s\n' "$out" | grep -q "^honored	refs/planwright-fence/demo/6	$uuid_peer$" \
  || fail "an orphan whose owner reappeared was not honored: $out"
sink | grep -q 'demo:6' && fail "a swept tentative entry survived attribution: $(sink)"

# The same reappearance, but AFTER the grace window already promoted the orphan
# to a surfaced strand (demo/5, above). The strand entry is keyed by ref plus
# OWNER (REQ-C1.7), so re-attribution moves the key and the old `unknown-owner`
# row is orphaned in the sink. Clearing the tentative key alone would leave a
# queued operator item saying no live tower will carry a unit that a live tower
# is demonstrably carrying — and offering `reclaim` on it, which is the double
# dispatch this whole mechanism exists to prevent.
sink | grep -q 'demo:5' \
  || fail "fixture: demo/5 should still hold its surfaced orphan strand: $(sink)"
publish_peer "demo/2,demo/3,demo/4,demo/5,demo/6"
out=$(sweep 0 "sweep/strand-reattributed" --min-interval 0 --grace 0)
printf '%s\n' "$out" | grep -q "^honored	refs/planwright-fence/demo/5	$uuid_peer$" \
  || fail "an orphan strand whose owner reappeared was not honored: $out"
sink | grep -q 'demo:5' \
  && fail "a stale unknown-owner strand survived re-attribution to a live owner: $(sink)"

# ==========================================================================
# REQ-C1.5 — the terminal transition sweeps the unit's sink entry too, so the
# sink is bounded rather than growing one entry per historical strand
# ==========================================================================
(
  cd "$co"
  git commit -q --allow-empty -m "close task 3

Planwright-Task: demo/3"
  git push -q origin HEAD:refs/heads/main
)
git -C "$co" fetch -q origin
git -C "$co" merge -q --ff-only origin/main 2>/dev/null || git -C "$co" reset -q --hard origin/main
out=$(sweep 0 "sweep/terminal-sweeps-sink" --min-interval 0)
printf '%s\n' "$out" | grep -q "^gc	refs/planwright-fence/demo/3$" \
  || fail "a now-terminal strand's fence was not GC'd: $out"
sink | grep -q 'demo:3' && fail "a terminal unit's sink entry was not swept: $(sink)"

# ==========================================================================
# REQ-C1.3 — a transient evidence failure fails closed: do not act, retry
# ==========================================================================
refs_before=$(origin_refs | sort | tr '\n' ' ')
GHBIN="$ghbroken"
out=$(sweep 0 "sweep/degraded-evidence" --min-interval 0)
GHBIN="$ghbin"
printf '%s\n' "$out" | grep -q '^hold	' \
  || fail "a degraded evidence probe did not hold: $out"
printf '%s\n' "$out" | grep -q '^strand	' \
  && fail "a degraded evidence probe surfaced a strand it could not rule terminal"
[ "$(origin_refs | sort | tr '\n' ' ')" = "$refs_before" ] \
  || fail "a degraded evidence probe still mutated the fence namespace"

# ==========================================================================
# REQ-D1.5 — a fence ref outside the unit-id grammar is surfaced as an
# anomaly, never parsed into a ref operation
# ==========================================================================
git -C "$origin" update-ref "refs/planwright-fence/demo/not-an-id" \
  "$(git -C "$origin" rev-parse refs/heads/main)"
out=$(sweep 0 "sweep/anomalous-ref" --min-interval 0)
printf '%s\n' "$out" | grep -q "^anomaly	refs/planwright-fence/demo/not-an-id	" \
  || fail "an off-grammar fence ref was not surfaced as an anomaly: $out"
git -C "$origin" show-ref -q "refs/planwright-fence/demo/not-an-id" \
  || fail "an off-grammar fence ref was acted on rather than surfaced"

# ==========================================================================
# REQ-C1.1 / REQ-C1.3 — presence is never on the correctness path: with the
# surface gone, the sweep still classifies (as unknown-owner orphans) rather
# than freeing anything
# ==========================================================================
refs_before=$(origin_refs | sort | tr '\n' ' ')
out=$(PLANWRIGHT_FLEET_STATE_DIR="$tmp/no-surface" pw "$FF" sweep \
  --checkout "$co" --spec demo --session-id "$uuid_self" --min-interval 0 --grace 9999 2>&1) \
  || fail "sweep failed with no presence surface"
[ "$(origin_refs | sort | tr '\n' ' ')" = "$refs_before" ] \
  || fail "a missing presence surface changed the fence namespace"
printf '%s\n' "$out" | grep -q '^tentative	' \
  || fail "with no presence surface, fences should read as unattributed: $out"

# ==========================================================================
# REQ-C1.4 — composing with meta-tower selection
# ==========================================================================
# The peer fence is the mechanism for the INDEPENDENTLY-STARTED, no-meta-tower
# case. Where a meta-tower is present it owns cross-spec selection, and the
# fence must compose with that assignment rather than contradict it: it never
# blocks a slice the meta-tower assigned, and it still refuses a second tower
# the same unit.

metahome="$tmp/fleet-meta"
mkdir -p "$metahome"
chmod 700 "$metahome"
mpw() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    PLANWRIGHT_FLEET_STATE_DIR="$metahome" PLANWRIGHT_BASE_REF=main \
    PATH="$GHBIN:$PATH" /bin/sh "$@"
}
uuid_meta="33333333-3333-3333-3333-333333333333"
uuid_sub="44444444-4444-4444-4444-444444444444"

# Clean slate: the earlier cases left live fences behind on purpose.
for r in $(origin_refs); do
  git -C "$origin" update-ref -d "$r"
done

printf 'alive\n' >"$tmp/evidence-verdict"
mpw "$FP" publish --checkout "$co" --session-id "$uuid_meta" --pid 4242 \
  --specs demo --meta >/dev/null || fail "meta-tower publish failed"
mpw "$FP" publish --checkout "$co" --session-id "$uuid_sub" --pid 4243 \
  --specs demo >/dev/null || fail "subordinate tower publish failed"

# The meta-tower is distinguished by the presence record's OWN validated meta
# marker — not by fleet-tower-marker.sh, whose field is the orthogonal
# unattended/interactive recovery mode.
peers=$(mpw "$FP" discover --checkout "$co" --session-id "$uuid_sub" --min-interval 0)
printf '%s\n' "$peers" | grep -q "^peer	$uuid_meta	live	.*	true$" \
  || fail "the meta-tower is not distinguishable by its own meta marker: $peers"
printf '%s\n' "$peers" | grep -q "^peer	$uuid_meta	live	.*	false$" \
  && fail "the meta marker is not being read from the record's own field"
grep -q 'fleet-tower-marker' "$stubbin/fleet-fence.sh" \
  && fail "the fence path reads the orthogonal recovery-mode marker"

# Cross-spec selection stays the meta-tower's: the fence is applied to the unit
# meta-selection produced, never used to pick one.
assigned=$(mpw "$stubbin/orchestrate-meta-select.sh" "$co/specs/demo" 2>/dev/null) \
  || fail "meta-tower selection produced nothing to assign"
aspec=$(printf '%s' "$assigned" | awk -F'\t' '{print $1}')
aunit=$(printf '%s' "$assigned" | awk -F'\t' '{print $2}')
[ "$aspec" = "$co/specs/demo" ] || fail "meta-select named an unexpected spec: $assigned"

# The assignment is honored: fencing the assigned unit succeeds, so the fence
# never contradicts the meta-tower.
rc=0
mpw "$FF" fence --checkout "$co" --spec demo "$aunit" >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "the fence blocked a unit the meta-tower assigned (exit $rc)"

# ...and it still does not double-assign: a second tower under the same
# meta-tower that reaches for the same unit collides and backs off.
rc=0
mpw "$FF" fence --checkout "$co" --spec demo "$aunit" >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "a meta-tower-present fence double-assigned the unit (exit $rc)"
run 0 "gc/meta-cleanup" "$FF" gc --checkout "$co" --spec demo "$aunit" >/dev/null

echo "PASS: $(basename "$0")"
