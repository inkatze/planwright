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

# 2b. Fewest-in-flight-first is the PRIMARY key, ahead of command-line order — a
#     dedicated fixture that discriminates it from a pure FIFO. specA (listed
#     FIRST) has a ready unit but 1 in-flight; specB (listed second) has a ready
#     unit and 0 in-flight. The lower-in-flight specB must win despite being
#     later on the command line; a CLI-order-only pick would wrongly take specA.
repoD=$(new_fleet "$tmp/D")
dA=$(add_spec "$repoD" speca)
dB=$(add_spec "$repoD" specb)
{
  printf '# tasks\n\n## Forward plan\n\n'
  printf '### Task 1 — root\n\n- **Dependencies:** none\n- **Estimated effort:** half day\n\n'
  printf '### Task 2 — dep on 1\n\n- **Dependencies:** 1\n- **Estimated effort:** half day\n\n'
  printf '### Task 3 — dep on 1\n\n- **Dependencies:** 1\n- **Estimated effort:** half day\n'
} >"$dA/tasks.md"
two_task_body >"$dB/tasks.md"
seal_base "$repoD"
done_trailer "$repoD" speca 1
done_trailer "$repoD" specb 1
inflight_marker "$dA" 2 # specA now at 1 in-flight, still ready via task 3
set_bounds "$repoD" 5 3
got=$("$MSEL" "$dA" "$dB") || fail "case 2b: non-zero exit ($?)"
[ "$got" = "$dB${tab}2" ] \
  || fail "case 2b: fewest-in-flight specB must win over earlier-listed specA (got '$got', expected '$dB${tab}2')"
echo "ok: fewest-in-flight is the primary key, ahead of command-line order"

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
# 5. Per-spec cap respected — and the case is built to DISCRIMINATE it. The
#    fewest-in-flight fair-pick already prefers a lower-in-flight spec, so a
#    capped spec only changes the outcome when it is the spec that would
#    otherwise be picked. So the capped spec here is the SOLE ready spec: alpha
#    holds 1 in-flight (task 2) but still has a ready task 3, while beta has no
#    ready unit at all (only its completed task 1). With per-spec cap 1 and a
#    generous fleet bound (10), alpha is skipped by its cap and nothing else is
#    ready → exit 1. Deleting the per-spec-cap check would make alpha a candidate
#    and flip this to `alpha\t3`, so the assertion genuinely exercises the cap.
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
# beta carries only a (completed) task 1: no forward-ready unit, so alpha is the
# sole ready spec and the per-spec cap is the only thing that can hold it.
printf '# tasks\n\n## Forward plan\n\n### Task 1 — lone root\n\n- **Dependencies:** none\n- **Estimated effort:** half day\n' >"$bbeta/tasks.md"
seal_base "$repoB"
done_trailer "$repoB" alpha 1
done_trailer "$repoB" beta 1
inflight_marker "$balpha" 2
set_bounds "$repoB" 10 1
rc=0
got=$("$MSEL" "$balpha" "$bbeta" 2>/dev/null) || rc=$?
{ [ "$rc" = 1 ] && [ -z "$got" ]; } \
  || fail "case 5a: per-spec cap 1 must skip the sole ready spec alpha → exit 1 (got '$got', rc $rc)"
echo "ok: a spec at its per-spec cap is skipped even as the sole ready spec (cap discriminated)"
# 5b. Same fixture, per-spec cap raised to 2 (via the overlay): alpha is now below
#     its cap (1 < 2) and IS selected — proving the cap is the overlay-resolved
#     gate, distinct from the fleet bound, and that raising it admits the spec.
set_bounds "$repoB" 10 2
got=$("$MSEL" "$balpha" "$bbeta") || fail "case 5b: non-zero exit ($?)"
[ "$got" = "$balpha${tab}3" ] \
  || fail "case 5b: raising the per-spec cap to 2 must admit alpha's ready task 3 (got '$got')"
echo "ok: raising the per-spec cap (overlay) admits the previously-capped spec"

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
#    emitting "<spec-dir>\t<id>" for the sole spec's ready unit. alpha holds 1
#    in-flight (task 2) and a ready task 3; with per-spec cap 3 it is below its
#    cap, so the sole ready unit (task 3) is emitted.
# ---------------------------------------------------------------------------
set_bounds "$repoB" 10 3
got=$("$MSEL" "$balpha") || fail "case 8: non-zero exit ($?)"
[ "$got" = "$balpha${tab}3" ] \
  || fail "case 8: single-spec fleet must emit the sole ready unit (got '$got')"
echo "ok: a single-spec fleet reduces to a one-spec selection"

# ---------------------------------------------------------------------------
# 9. Malformed bound value → warn on stderr and fall back to the default (3), so
#    a typo in the overlay never wedges the fleet. speca has a ready task 2 and
#    zero in-flight; with a non-numeric fleet bound the selector must still
#    dispatch (default 3 leaves headroom) AND emit the malformed-value warning.
# ---------------------------------------------------------------------------
repoE=$(new_fleet "$tmp/E")
ealpha=$(add_spec "$repoE" speca)
two_task_body >"$ealpha/tasks.md"
seal_base "$repoE"
done_trailer "$repoE" speca 1
set_bounds "$repoE" foo 3
got=$("$MSEL" "$ealpha" 2>"$tmp/e9.err") || fail "case 9: malformed bound must still dispatch via fallback (rc $?)"
[ "$got" = "$ealpha${tab}2" ] \
  || fail "case 9: malformed fleet bound must fall back to the default and dispatch (got '$got')"
grep -q "ignoring malformed fleet_max_parallel_units" "$tmp/e9.err" \
  || fail "case 9: malformed fleet bound must warn on stderr"
echo "ok: a malformed bound warns and falls back to the safe default"

# ---------------------------------------------------------------------------
# 10. Missing required helper → fail closed (exit 2) at pre-flight, before any
#     selection. A copy of the selector placed in a directory WITHOUT its sibling
#     primitives (orchestrate-state.sh / orchestrate-select.sh / config-get.sh)
#     must exit 2 rather than proceed with absent live truth.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/nohelpers"
cp "$MSEL" "$tmp/nohelpers/orchestrate-meta-select.sh"
chmod +x "$tmp/nohelpers/orchestrate-meta-select.sh"
rc=0
"$tmp/nohelpers/orchestrate-meta-select.sh" "$ealpha" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "case 10: a missing required helper must fail closed (exit $rc, expected 2)"
echo "ok: a missing / non-executable required helper fails closed with exit 2"

# ---------------------------------------------------------------------------
# 11. A bound of 0 pauses (documented as "a paused fleet/spec"). 11a: fleet bound
#     0 holds every step even with a ready unit and zero in-flight. 11b: per-spec
#     cap 0 skips the spec (0 < 0 is false) so nothing is dispatchable. Both
#     assert exit 1 with empty stdout; if 0 were not honored the ready task 2
#     would dispatch and each assertion would flip.
# ---------------------------------------------------------------------------
repoF=$(new_fleet "$tmp/F")
falpha=$(add_spec "$repoF" speca)
two_task_body >"$falpha/tasks.md"
seal_base "$repoF"
done_trailer "$repoF" speca 1
set_bounds "$repoF" 0 3
rc=0
got=$("$MSEL" "$falpha" 2>/dev/null) || rc=$?
{ [ "$rc" = 1 ] && [ -z "$got" ]; } \
  || fail "case 11a: fleet bound 0 must pause the fleet (got '$got', rc $rc)"
set_bounds "$repoF" 5 0
rc=0
got=$("$MSEL" "$falpha" 2>/dev/null) || rc=$?
{ [ "$rc" = 1 ] && [ -z "$got" ]; } \
  || fail "case 11b: per-spec cap 0 must skip the spec (got '$got', rc $rc)"
echo "ok: a bound of 0 pauses the fleet (fleet-wide) or the spec (per-spec)"

# ---------------------------------------------------------------------------
# 12. Multi-checkout fail-closed. A fleet supervises specs in ONE checkout: the
#     config overlay is read once from the shared repo root and the bounds are
#     only meaningful against a single derivation base. A spec passed from a
#     DIFFERENT git work tree must fail closed (exit 2) rather than silently
#     resolving bounds from the first repo's overlay while deriving state against
#     another. Two separate repos, each with a ready spec; without the check the
#     selector would happily emit the first spec's unit (rc 0), so the assertion
#     genuinely exercises the same-checkout guard.
# ---------------------------------------------------------------------------
repoG=$(new_fleet "$tmp/G")
galpha=$(add_spec "$repoG" speca)
two_task_body >"$galpha/tasks.md"
seal_base "$repoG"
done_trailer "$repoG" speca 1
repoH=$(new_fleet "$tmp/H")
hbeta=$(add_spec "$repoH" specb)
two_task_body >"$hbeta/tasks.md"
seal_base "$repoH"
done_trailer "$repoH" specb 1
set_bounds "$repoG" 5 3
rc=0
"$MSEL" "$galpha" "$hbeta" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] \
  || fail "case 12: specs from different checkouts must fail closed (exit $rc, expected 2)"
echo "ok: specs spanning different checkouts fail closed with exit 2"

# ---------------------------------------------------------------------------
# 13. A malformed repo-tracked (team-shared) overlay must SURFACE config-get's
#     hard-fail diagnostic (exit 4) on stderr rather than being silently degraded
#     to the fallback bound: read_bound does not suppress config-get's stderr
#     (matching scripts/orchestrate-lock.sh / scripts/fleet-state.sh), so an
#     operator sees the broken shared config; the selector still dispatches via
#     the safe fallback default (degrade-but-surface, like the sibling threshold
#     reads). speca has a ready task 2 and zero in-flight. PLANWRIGHT_REPO_ROOT
#     pins the repo so config-get resolves the repo-tracked layer to the fixture.
#     A suppressed (2>/dev/null) read_bound would swallow the diagnostic and this
#     grep would fail, so the assertion discriminates the fix.
# ---------------------------------------------------------------------------
repoI=$(new_fleet "$tmp/I")
ialpha=$(add_spec "$repoI" speca)
two_task_body >"$ialpha/tasks.md"
seal_base "$repoI"
done_trailer "$repoI" speca 1
mkdir -p "$repoI/.claude"
# An indented (nested) line is malformed for the flat `key: value` reader → the
# repo-tracked layer hard-fails with config-get exit 4.
printf 'fleet_max_parallel_units:\n  nested: bad\n' >"$repoI/.claude/planwright.yml"
rc=0
got=$(PLANWRIGHT_REPO_ROOT="$repoI" "$MSEL" "$ialpha" 2>"$tmp/i13.err") || rc=$?
[ "$rc" = 0 ] \
  || fail "case 13: malformed repo-tracked overlay must still dispatch via fallback (rc $rc)"
[ "$got" = "$ialpha${tab}2" ] \
  || fail "case 13: malformed repo-tracked overlay must dispatch the ready unit via fallback (got '$got')"
grep -q "repo-tracked overlay.*malformed" "$tmp/i13.err" \
  || fail "case 13: malformed repo-tracked overlay must surface config-get's diagnostic on stderr"
echo "ok: a malformed repo-tracked overlay surfaces the hard-fail diagnostic (not silently degraded)"

# ---------------------------------------------------------------------------
# 14. Config resolution is pinned to the validated fleet root, NOT the caller's
#     CWD. config-get resolves the repo-tracked/adopter overlay layers from
#     PLANWRIGHT_REPO_ROOT when set, else the CWD's git toplevel; read_bound pins
#     it to repo_root so the bound is read from the fleet the specs live in even
#     when the selector is invoked from a different checkout. Fixture: repoJ holds
#     a ready spec AND a repo-tracked overlay pausing the fleet (bound 0, no
#     machine-local overlay so repo-tracked is the deciding layer over core's
#     default 3). Invoked from inside a DIFFERENT git repo (repoK, no overlay).
#     With the pin, repoJ's overlay is read → fleet paused → exit 1 empty. Without
#     it, config-get would resolve repo-tracked from repoK (absent) → core default
#     3 → the ready unit would dispatch (rc 0), so the assertion discriminates the
#     CWD-independence fix. PLANWRIGHT_REPO_ROOT is unset in the environment so the
#     ONLY thing pinning it is read_bound.
# ---------------------------------------------------------------------------
repoJ=$(new_fleet "$tmp/J")
jalpha=$(add_spec "$repoJ" speca)
two_task_body >"$jalpha/tasks.md"
seal_base "$repoJ"
done_trailer "$repoJ" speca 1
mkdir -p "$repoJ/.claude"
# Repo-tracked (team-shared) overlay, NOT machine-local: pauses the fleet.
printf 'fleet_max_parallel_units: 0\n' >"$repoJ/.claude/planwright.yml"
# A different checkout to run FROM (carries no overlay). `git rev-parse
# --show-toplevel` resolves on a freshly-init'd repo, so it needs no commit.
repoK=$(new_fleet "$tmp/K")
rc=0
got=$(
  unset PLANWRIGHT_REPO_ROOT
  cd "$repoK" && "$MSEL" "$jalpha" 2>/dev/null
) || rc=$?
{ [ "$rc" = 1 ] && [ -z "$got" ]; } \
  || fail "case 14: repo-tracked bound must resolve from the fleet root, not CWD (got '$got', rc $rc)"
echo "ok: config resolution is pinned to the fleet root, independent of the caller's CWD"

echo "PASS: orchestrate-meta-select"
