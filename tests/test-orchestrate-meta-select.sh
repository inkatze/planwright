#!/bin/bash
# Tests for scripts/orchestrate-meta-select.sh — the meta-tower ("tower of
# towers") multi-spec ready-unit selector with a fleet-level concurrency bound
# (orchestration-fleet Task 6, REQ-D1.1, REQ-D1.5, D-6).
#
# Contract under test:
#   orchestrate-meta-select.sh <spec-dir> [<spec-dir>...]
#   - Considers ready units across ALL supervised specs, reading each spec's
#     LIVE derivation (scripts/orchestrate-state.sh + orchestrate-select.sh),
#     never the committed tasks.md snapshot (D-3, REQ-B1.2).
#   - Enforces a FLEET concurrency bound — the config knob
#     `fleet_max_parallel_units`, overlay-resolved and DISTINCT from the per-spec
#     `max_parallel_units`: the sum of in-progress units across all supervised
#     specs may not exceed it. At or over the bound nothing is dispatched this
#     step (exit 1) even when a spec has ready work — the bound caps TOTAL
#     concurrency across specs (REQ-D1.5).
#   - Also honors each spec's own `max_parallel_units` cap: a spec already at its
#     per-spec cap is skipped even with fleet headroom, so a capped spec does not
#     starve the others.
#   - Fair across specs: among dispatchable specs the one with the fewest
#     in-flight units wins; command-line order breaks ties (FIFO).
#   - Emits "<spec-dir>\t<id>" for the chosen unit on stdout, exit 0.
#   - No dispatchable unit anywhere (nothing ready, or fleet/per-spec saturated)
#     → exit 1, empty stdout.
#   - A missing/taskless/non-git spec dir, or a hostile spec basename → exit 2
#     (fail closed), like the single-spec selector.
#
# Fixtures are real git repos with crafted evidence — the same live-truth model
# the single-spec selector test uses: a task is COMPLETED via a reachable
# `Planwright-Task: <spec>/<id>` trailer, IN-PROGRESS via a fresh runtime marker.
# Multiple specs live in ONE repo (a fleet supervises several specs in one
# checkout). The fleet/per-spec bounds are set through the machine-local overlay
# (<repo>/.claude/planwright.local.yml), so these cases also exercise the
# overlay resolution the bound is required to flow through.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
MSEL="$here/../scripts/orchestrate-meta-select.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$MSEL" ] || fail "scripts/orchestrate-meta-select.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tab=$(printf '\t')

# git with a deterministic, signing-free identity (mirrors the sibling tests).
gitc() {
  gc_repo="$1"
  shift
  git -C "$gc_repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# new_fleet <repo> — init one git repo to hold several specs; echo the repo path.
new_fleet() {
  mkdir -p "$1"
  git -C "$1" -c init.defaultBranch=main init -q
  printf '%s' "$1"
}

# add_spec <repo> <spec-id> — create specs/<spec-id>/ and echo the spec dir. The
# caller writes tasks.md; seal_base commits the working tree once all are added.
add_spec() {
  mkdir -p "$1/specs/$2"
  printf '%s/specs/%s' "$1" "$2"
}

# seal_base <repo> — commit the working tree as the base commit on main.
seal_base() {
  gitc "$1" add -A
  gitc "$1" commit -q -m "base: fleet bundle"
}

# done_trailer <repo> <spec-id> <id> — mark task <id> of <spec-id> COMPLETED via
# a reachable completion trailer on main (the durable anchor, D-2 / REQ-C1.4).
done_trailer() {
  gitc "$1" commit -q --allow-empty -m "task $3 done" -m "Planwright-Task: $2/$3"
}

# inflight_marker <spec-dir> <id> — mark task <id> IN-PROGRESS via a fresh
# runtime dispatch marker (D-3), the branch-create → first-commit window.
inflight_marker() {
  im_dir="$1/.orchestrate/markers"
  mkdir -p "$im_dir"
  date +%s >"$im_dir/$2"
}

# set_bounds <repo> <fleet> <per-spec> — write the machine-local overlay so the
# meta-selector resolves the fleet and per-spec bounds through the config chain.
set_bounds() {
  mkdir -p "$1/.claude"
  printf 'fleet_max_parallel_units: %s\nmax_parallel_units: %s\n' "$2" "$3" \
    >"$1/.claude/planwright.local.yml"
}

# A ready task with dep 1: task 1 is a depless root completed via a trailer; the
# forward task(s) depend on it and become ready once 1 is derived completed.
two_task_body() {
  printf '# tasks\n\n## Forward plan\n\n'
  printf '### Task 1 — root\n\n- **Dependencies:** none\n- **Estimated effort:** half day\n\n'
  printf '### Task 2 — dep on 1\n\n- **Dependencies:** 1\n- **Estimated effort:** half day\n'
}

# ---------------------------------------------------------------------------
# Repo A holds specs alpha, beta, gamma — cases 1-4 build state incrementally.
# ---------------------------------------------------------------------------
repoA=$(new_fleet "$tmp/A")
alpha=$(add_spec "$repoA" alpha)
beta=$(add_spec "$repoA" beta)
two_task_body >"$alpha/tasks.md"
two_task_body >"$beta/tasks.md"
seal_base "$repoA"
done_trailer "$repoA" alpha 1
done_trailer "$repoA" beta 1

# 1. Multi-spec reach + fair tie-break. Both alpha and beta have a ready task 2
#    and zero in-flight; the fleet bound (5) leaves ample headroom. The tie
#    (equal in-flight) is broken by command-line order → alpha.
set_bounds "$repoA" 5 3
got=$("$MSEL" "$alpha" "$beta") || fail "case 1: non-zero exit ($?)"
[ "$got" = "$alpha${tab}2" ] \
  || fail "case 1: selected '$got', expected '$alpha${tab}2' (multi-spec reach, CLI-order tie-break)"
echo "ok: considers ready units across specs; ties break by command-line order"

# 2. Fair round-robin. With alpha's task 2 now in flight (alpha at 1 in-flight,
#    no other ready alpha unit), the less-loaded beta is selected.
inflight_marker "$alpha" 2
got=$("$MSEL" "$alpha" "$beta") || fail "case 2: non-zero exit ($?)"
[ "$got" = "$beta${tab}2" ] \
  || fail "case 2: selected '$got', expected '$beta${tab}2' (fewest-in-flight-first fairness)"
echo "ok: fair selection prefers the spec with the fewest in-flight units"

# 3. The fleet bound caps TOTAL concurrency across specs. With the bound at 1 and
#    alpha already holding 1 in-flight unit, beta's ready task 2 is HELD — the
#    cap is fleet-wide, not per-spec.
set_bounds "$repoA" 1 3
rc=0
got=$("$MSEL" "$alpha" "$beta" 2>/dev/null) || rc=$?
{ [ "$rc" = 1 ] && [ -z "$got" ]; } \
  || fail "case 3: fleet bound 1 with 1 in-flight must hold beta (got '$got', rc $rc)"
echo "ok: the fleet bound caps total concurrency across specs (a ready sibling is held)"

# 4. The fleet bound is DISTINCT from the per-spec max_parallel_units and is
#    overlay-resolved. gamma adds a third ready unit; alpha and beta each hold 1
#    in-flight (fleet-wide 2). With fleet bound 2 but per-spec cap 5, gamma is
#    HELD by the FLEET bound even though every per-spec cap has headroom.
gamma=$(add_spec "$repoA" gamma)
two_task_body >"$gamma/tasks.md"
done_trailer "$repoA" gamma 1
inflight_marker "$beta" 2
set_bounds "$repoA" 2 5
rc=0
got=$("$MSEL" "$alpha" "$beta" "$gamma" 2>/dev/null) || rc=$?
{ [ "$rc" = 1 ] && [ -z "$got" ]; } \
  || fail "case 4a: fleet bound 2 (per-spec 5) must hold gamma at fleet-wide 2 in-flight (got '$got', rc $rc)"
#    Raising ONLY the fleet bound to 5 (per-spec unchanged at 5) now admits
#    gamma — proving the FLEET bound, not the per-spec cap, was the gate.
set_bounds "$repoA" 5 5
got=$("$MSEL" "$alpha" "$beta" "$gamma") || fail "case 4b: non-zero exit ($?)"
[ "$got" = "$gamma${tab}2" ] \
  || fail "case 4b: raising the fleet bound must admit gamma (got '$got', expected '$gamma${tab}2')"
echo "ok: the fleet bound is distinct from per-spec max_parallel_units and overlay-resolved"

# ---------------------------------------------------------------------------
# 5. Per-spec cap respected: a spec at its own max_parallel_units is skipped even
#    with fleet headroom, so it does not starve the others. alpha holds 1
#    in-flight (task 2) but still has a ready task 3; with per-spec cap 1 alpha is
#    skipped and beta (0 in-flight) is selected, despite a fleet bound of 10.
# ---------------------------------------------------------------------------
repoB=$(new_fleet "$tmp/B")
balpha=$(add_spec "$repoB" alpha)
bbeta=$(add_spec "$repoB" beta)
{
  printf '# tasks\n\n## Forward plan\n\n'
  printf '### Task 1 — root\n\n- **Dependencies:** none\n- **Estimated effort:** half day\n\n'
  printf '### Task 2 — dep on 1\n\n- **Dependencies:** 1\n- **Estimated effort:** half day\n\n'
  printf '### Task 3 — dep on 1\n\n- **Dependencies:** 1\n- **Estimated effort:** half day\n'
} >"$balpha/tasks.md"
two_task_body >"$bbeta/tasks.md"
seal_base "$repoB"
done_trailer "$repoB" alpha 1
done_trailer "$repoB" beta 1
inflight_marker "$balpha" 2
set_bounds "$repoB" 10 1
got=$("$MSEL" "$balpha" "$bbeta") || fail "case 5: non-zero exit ($?)"
[ "$got" = "$bbeta${tab}2" ] \
  || fail "case 5: per-spec cap 1 must skip alpha (ready task 3) and pick beta (got '$got')"
echo "ok: a spec at its per-spec cap is skipped even with fleet headroom"

# ---------------------------------------------------------------------------
# 6. Nothing dispatchable anywhere → exit 1, empty stdout. Every forward task
#    depends on a non-existent task (blocked); no in-flight units.
# ---------------------------------------------------------------------------
repoC=$(new_fleet "$tmp/C")
calpha=$(add_spec "$repoC" alpha)
cbeta=$(add_spec "$repoC" beta)
for d in "$calpha" "$cbeta"; do
  printf '# tasks\n\n## Forward plan\n\n### Task 2 — blocked on a phantom dep\n\n- **Dependencies:** 99\n- **Estimated effort:** 1 day\n' >"$d/tasks.md"
done
seal_base "$repoC"
set_bounds "$repoC" 5 3
rc=0
got=$("$MSEL" "$calpha" "$cbeta" 2>/dev/null) || rc=$?
{ [ "$rc" = 1 ] && [ -z "$got" ]; } \
  || fail "case 6: nothing ready must exit 1 with empty stdout (got '$got', rc $rc)"
echo "ok: nothing dispatchable across the fleet exits 1 with empty stdout"

# ---------------------------------------------------------------------------
# 7. Fail closed (exit 2) on a bad spec dir, a bad spec among good ones, and a
#    hostile (non-grammar) spec basename — mirroring the single-spec selector.
# ---------------------------------------------------------------------------
rc=0
"$MSEL" "$tmp/does-not-exist" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "case 7a: missing spec dir must fail closed (exit $rc, expected 2)"
rc=0
"$MSEL" "$balpha" "$tmp/does-not-exist" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "case 7b: one bad spec among good ones must fail closed (exit $rc, expected 2)"
# Hostile basename: an uppercase / non-grammar spec id is rejected before any
# path or id use, even when a tasks.md is present.
mkdir -p "$repoB/specs/Bad"
two_task_body >"$repoB/specs/Bad/tasks.md"
rc=0
"$MSEL" "$repoB/specs/Bad" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "case 7c: hostile spec basename must fail closed (exit $rc, expected 2)"
echo "ok: missing / mixed-bad / hostile-identifier spec dirs fail closed with exit 2"

# ---------------------------------------------------------------------------
# 8. Degenerate single-spec fleet: the meta-selector reduces to a one-spec pass,
#    emitting "<spec-dir>\t<id>" for the sole spec's ready unit.
# ---------------------------------------------------------------------------
set_bounds "$repoB" 10 3
got=$("$MSEL" "$bbeta") || fail "case 8: non-zero exit ($?)"
[ "$got" = "$bbeta${tab}2" ] \
  || fail "case 8: single-spec fleet must emit the sole ready unit (got '$got')"
echo "ok: a single-spec fleet reduces to a one-spec selection"

echo "PASS: orchestrate-meta-select"
