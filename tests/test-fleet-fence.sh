#!/bin/bash
# Tests for scripts/fleet-fence.sh — the per-unit `origin` fence: the
# expect-absent CAS at dispatch, the selection guard, GC-on-terminal, and the
# discovery sweep that surfaces strands
# (concurrent-orchestrator-coordination Task 4: D-5, D-7, D-8, D-10, D-11,
# D-12, D-13 · REQ-C1.1–REQ-C1.7, REQ-D1.5).
#
# Contract under test:
#   refname --spec <spec> <unit-id>
#       Print the containment-checked fence ref name. Refuses any id that
#       would escape refs/planwright-fence/<spec>/ (REQ-D1.5).
#   check   --checkout <dir> --spec <spec> <unit-id>
#       The selection guard: `fenced` (exit 0) / `unfenced` (exit 1).
#   fence   --checkout <dir> --spec <spec> <unit-id>...
#       The atomic expect-absent CAS. One id fences one unit; several ids are
#       a cohesion bundle fenced in a single `git push --atomic`, all-or-none.
#   gc      --checkout <dir> --spec <spec> <unit-id>...
#       Idempotent fence delete (an already-absent ref is success).
#   list    --checkout <dir> [--spec <spec>]
#       Enumerate live fence refs on `origin`.
#   sweep   --checkout <dir> --spec <spec> (--session-id <uuid> | --pid <pid>)
#           [--grace <sec>] [--min-interval <sec>]
#       Terminal-first, then liveness: GC a terminal unit's fence, honor a
#       live owner's, surface everything else to the durable dedup'd sink.
#   Exit codes: 0 ok/won; 1 (check) unfenced; 2 usage / refused input;
#       3 the unit is already fenced — back off; 4 transient `origin`
#       failure — fail closed, surface, retry; 5 no `origin` — the genuine
#       no-remote single-host solo posture.
#
# Every network assertion runs against a LOCAL BARE-REPO `origin` fixture, so
# the suite is hermetic (REQ-C1.1, REQ-C1.6 `[test]` arm).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FF="$here/../scripts/fleet-fence.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FF" ] || fail "scripts/fleet-fence.sh missing or not executable"

tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

# --- fixture: a bare `origin` plus two independent clones ------------------
# Two clones of ONE bare origin is the separate-clone case the checkout-local
# per-spec lock provably cannot serialize (REQ-C1.1): everything below that
# asserts exclusion asserts it across this boundary.

origin="$tmp/origin.git"
git init -q --bare "$origin"
clone() {
  git clone -q "$origin" "$tmp/$1" 2>/dev/null
  git -C "$tmp/$1" config user.email fence@test.invalid
  git -C "$tmp/$1" config user.name fence-test
}
clone seed
(
  cd "$tmp/seed"
  echo base >file
  git add file
  git commit -qm "base"
  git push -q origin HEAD:refs/heads/main
)
clone a
clone b
A="$tmp/a"
B="$tmp/b"
tip=$(git -C "$origin" rev-parse refs/heads/main)

# The fleet home every sibling surface (presence, attention) lands under.
export PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet"
mkdir -p "$PLANWRIGHT_FLEET_STATE_DIR"
chmod 700 "$PLANWRIGHT_FLEET_STATE_DIR"

origin_refs() {
  git -C "$origin" for-each-ref --format='%(refname)' refs/planwright-fence
}

run() { # run <expected-exit> <label> <args...>
  local want=$1 label=$2
  shift 2
  local out rc=0
  out=$("$@" 2>&1) || rc=$?
  if [ "$rc" != "$want" ]; then
    echo "$out" >&2
    fail "$label: expected exit $want, got $rc"
  fi
  printf '%s' "$out"
}

# ==========================================================================
# REQ-D1.5 — ref-name grammar + containment, BEFORE any ref operation
# ==========================================================================

got=$(run 0 "refname/well-formed" "$FF" refname --spec demo 4)
[ "$got" = "refs/planwright-fence/demo/4" ] \
  || fail "refname: expected refs/planwright-fence/demo/4, got '$got'"

got=$(run 0 "refname/dotted-id" "$FF" refname --spec demo 3.5)
[ "$got" = "refs/planwright-fence/demo/3.5" ] \
  || fail "refname: dotted id, got '$got'"

got=$(run 0 "refname/bundle-range-id" "$FF" refname --spec demo 3-4)
[ "$got" = "refs/planwright-fence/demo/3-4" ] \
  || fail "refname: bundle-range id, got '$got'"

# A crafted unit or spec id must never drive a ref operation outside the
# namespace: refused at the grammar, never sanitized-and-used.
for bad in "../../heads/main" ".." "-4" "4 5" "4;rm" "refs/heads/main" "" "4/x" "4.." "@{" "4^"; do
  run 2 "refname/hostile-unit '$bad'" "$FF" refname --spec demo "$bad" >/dev/null
done
for bad in "../evil" ".." "-demo" "de mo" "Demo" "demo/x" ""; do
  run 2 "refname/hostile-spec '$bad'" "$FF" refname --spec "$bad" 4 >/dev/null
done

# ==========================================================================
# REQ-C1.6(a) — no `origin` configured is the genuine solo posture
# ==========================================================================

solo="$tmp/solo"
git init -q "$solo"
git -C "$solo" config user.email fence@test.invalid
git -C "$solo" config user.name fence-test
(
  cd "$solo"
  echo x >f
  git add f
  git commit -qm solo
)
out=$(run 5 "fence/no-origin" "$FF" fence --checkout "$solo" --spec demo 4)
case "$out" in
  *solo*) ;;
  *) fail "fence/no-origin: expected a solo-posture line, got '$out'" ;;
esac
out=$(run 5 "check/no-origin" "$FF" check --checkout "$solo" --spec demo 4)
case "$out" in
  *solo*) ;;
  *) fail "check/no-origin: expected a solo-posture line, got '$out'" ;;
esac
[ -z "$(origin_refs)" ] || fail "fence/no-origin: pushed a ref despite no origin"

# ==========================================================================
# REQ-C1.1 / REQ-C1.2 — the expect-absent CAS, and it adds no history to main
# ==========================================================================

main_before=$(git -C "$origin" rev-parse refs/heads/main)
log_before=$(git -C "$origin" rev-list --count refs/heads/main)

run 1 "check/before-fence" "$FF" check --checkout "$A" --spec demo 4 >/dev/null
run 0 "fence/tower-a-wins" "$FF" fence --checkout "$A" --spec demo 4 >/dev/null

[ "$(origin_refs)" = "refs/planwright-fence/demo/4" ] \
  || fail "fence: expected exactly the demo/4 fence ref, got '$(origin_refs)'"
[ "$(git -C "$origin" rev-parse refs/planwright-fence/demo/4)" = "$tip" ] \
  || fail "fence: the fence ref must point at the origin/main tip"
[ "$(git -C "$origin" rev-parse refs/heads/main)" = "$main_before" ] \
  || fail "fence: main moved — the fence must add no history to main"
[ "$(git -C "$origin" rev-list --count refs/heads/main)" = "$log_before" ] \
  || fail "fence: main gained a commit — the fence must add no history to main"

# The loser is REJECTED even though it targets the very same commit. This is
# the case a bare exit-code read gets wrong: git short-circuits a same-value
# update to `[up to date]` (exit 0) BEFORE evaluating the lease, so the
# discriminator is the per-ref porcelain status, not the exit code (REQ-C1.6).
run 3 "fence/tower-b-backs-off" "$FF" fence --checkout "$B" --spec demo 4 >/dev/null
[ "$(origin_refs)" = "refs/planwright-fence/demo/4" ] \
  || fail "fence: the losing tower must leave the ref set unchanged"

# The selection guard sees the fence from the OTHER clone (cross-clone).
run 0 "check/after-fence-cross-clone" "$FF" check --checkout "$B" --spec demo 4 >/dev/null

# ...and a peer is free to take a DIFFERENT unit.
run 0 "fence/tower-b-other-unit" "$FF" fence --checkout "$B" --spec demo 5 >/dev/null

# ==========================================================================
# REQ-C1.1 — correctness is independent of the presence surface
# ==========================================================================

(
  PLANWRIGHT_FLEET_STATE_DIR="$tmp/no-such-surface"
  export PLANWRIGHT_FLEET_STATE_DIR
  run 0 "fence/no-presence-surface-winner" "$FF" fence --checkout "$A" --spec demo 6 >/dev/null
  run 3 "fence/no-presence-surface-loser" "$FF" fence --checkout "$B" --spec demo 6 >/dev/null
) || fail "fence: exclusion must not depend on the presence surface"

# ==========================================================================
# REQ-C1.2 — cohesion bundles are fenced all-or-none
# ==========================================================================

# Clean slate for the bundle assertions.
run 0 "gc/bundle-slate" "$FF" gc --checkout "$A" --spec demo 4 5 6 >/dev/null
[ -z "$(origin_refs)" ] || fail "gc: expected an empty fence namespace, got '$(origin_refs)'"

run 0 "fence/bundle-wins" "$FF" fence --checkout "$A" --spec demo 7 8 >/dev/null
got=$(origin_refs | sort | tr '\n' ' ')
[ "$got" = "refs/planwright-fence/demo/7 refs/planwright-fence/demo/8 " ] \
  || fail "fence/bundle: expected both member refs, got '$got'"

run 0 "gc/bundle-reset" "$FF" gc --checkout "$A" --spec demo 7 8 >/dev/null

# A peer holds the NON-LEAD member only: the whole bundle must back off, and
# no member may be left fenced behind (git does not roll `[up to date]` back,
# so the tower has to compensate for what its own push created).
run 0 "fence/peer-holds-non-lead" "$FF" fence --checkout "$B" --spec demo 8 >/dev/null
run 3 "fence/bundle-collides-on-non-lead" "$FF" fence --checkout "$A" --spec demo 7 8 >/dev/null
got=$(origin_refs | sort | tr '\n' ' ')
[ "$got" = "refs/planwright-fence/demo/8 " ] \
  || fail "fence/bundle: a backed-off bundle must leave no member fenced; got '$got'"

# ...and symmetrically when the peer holds the LEAD member.
run 0 "gc/bundle-reset-2" "$FF" gc --checkout "$B" --spec demo 8 >/dev/null
run 0 "fence/peer-holds-lead" "$FF" fence --checkout "$B" --spec demo 7 >/dev/null
run 3 "fence/bundle-collides-on-lead" "$FF" fence --checkout "$A" --spec demo 7 8 >/dev/null
got=$(origin_refs | sort | tr '\n' ' ')
[ "$got" = "refs/planwright-fence/demo/7 " ] \
  || fail "fence/bundle: a lead-collision must leave no extra member fenced; got '$got'"
run 0 "gc/bundle-reset-3" "$FF" gc --checkout "$B" --spec demo 7 >/dev/null

# A repeated unit id in one bundle is refused, never silently deduped into a
# push whose refspecs collide.
run 2 "fence/bundle-duplicate-id" "$FF" fence --checkout "$A" --spec demo 9 9 >/dev/null

# ==========================================================================
# REQ-C1.1 / REQ-C1.6 — the CAS itself, with the pre-flight read taken out
# ==========================================================================
# The live pre-flight read catches an already-fenced unit before the push, so
# on its own it hides whether the CAS is sound. These cases stage the real
# race — a peer landing its fence AFTER our read and BEFORE our push — by
# hooking `receive-pack` on the pushing clone, so the server's advertisement
# already carries the peer's fence when the push computes its per-ref status.
# This is the case a bare exit-code read gets WRONG: both towers target the
# same `origin/main` tip, so git resolves the loser's update to `[up to date]`
# and exits 0 without ever consulting the lease.

racer="$tmp/racing-receive-pack"
cat >"$racer" <<RACER
#!/bin/sh
# Land the "peer" fences named in \$PW_RACE_REFS, once, then hand off to the
# real receive-pack — so they are present in the advertisement this push reads.
if [ -n "\${PW_RACE_REFS:-}" ] && [ ! -f "$tmp/race-fired" ]; then
  : >"$tmp/race-fired"
  for _r in \$PW_RACE_REFS; do
    git --git-dir="$origin" update-ref "\$_r" "$tip"
  done
fi
exec git-receive-pack "\$@"
RACER
chmod +x "$racer"
git -C "$B" config remote.origin.receivepack "$racer"

race() { # race <space-separated refs the peer wins> <expected exit> <label> <args...>
  local peer=$1 want=$2 label=$3
  shift 3
  rm -f "$tmp/race-fired"
  PW_RACE_REFS="$peer" run "$want" "$label" "$@"
}

# Single unit: the peer wins the race, so we must back off despite git
# reporting the push a success.
race "refs/planwright-fence/demo/20" 3 "fence/cas-loses-race" \
  "$FF" fence --checkout "$B" --spec demo 20 >/dev/null
[ "$(origin_refs | sort | tr '\n' ' ')" = "refs/planwright-fence/demo/20 " ] \
  || fail "fence/cas: the loser must not add a ref; got '$(origin_refs | tr '\n' ' ')'"
run 0 "gc/cas-cleanup" "$FF" gc --checkout "$A" --spec demo 20 >/dev/null

# Bundle: the peer wins ONE member in the race. `--atomic` does not roll an
# `[up to date]` member back, so the tower has to delete the member its own
# push created before backing off the whole bundle.
race "refs/planwright-fence/demo/21" 3 "fence/cas-bundle-loses-race" \
  "$FF" fence --checkout "$B" --spec demo 21 22 >/dev/null
[ "$(origin_refs | sort | tr '\n' ' ')" = "refs/planwright-fence/demo/21 " ] \
  || fail "fence/cas-bundle: member 22 must not stay fenced by a bundle that backed off; got '$(origin_refs | sort | tr '\n' ' ')'"
run 0 "gc/cas-bundle-cleanup" "$FF" gc --checkout "$A" --spec demo 21 22 >/dev/null

git -C "$B" config --unset remote.origin.receivepack
[ -z "$(origin_refs)" ] || fail "fence/cas: expected a clean namespace after the race cases"

# ==========================================================================
# REQ-C1.6(c) — a transient `origin` failure fails closed, never dispatches
# ==========================================================================

broken="$tmp/broken"
git clone -q "$origin" "$broken" 2>/dev/null
git -C "$broken" remote set-url origin "$tmp/does-not-exist.git"
run 4 "fence/transient-origin" "$FF" fence --checkout "$broken" --spec demo 4 >/dev/null
run 4 "check/transient-origin" "$FF" check --checkout "$broken" --spec demo 4 >/dev/null
run 4 "gc/transient-origin" "$FF" gc --checkout "$broken" --spec demo 4 >/dev/null
[ -z "$(origin_refs)" ] || fail "fence: a transient failure must create no ref"

# ==========================================================================
# REQ-C1.5 — GC is idempotent and bounded; an open PR is not terminal
# ==========================================================================

run 0 "fence/gc-subject" "$FF" fence --checkout "$A" --spec demo 4 >/dev/null
run 0 "gc/first" "$FF" gc --checkout "$A" --spec demo 4 >/dev/null
[ -z "$(origin_refs)" ] || fail "gc: the fence ref must be gone"
# Two towers GC'ing the same terminal fence, and a delete of an already-absent
# ref, are both success — no error, no destructive race.
run 0 "gc/idempotent-same-tower" "$FF" gc --checkout "$A" --spec demo 4 >/dev/null
run 0 "gc/idempotent-peer-tower" "$FF" gc --checkout "$B" --spec demo 4 >/dev/null
run 0 "gc/idempotent-never-fenced" "$FF" gc --checkout "$A" --spec demo 99 >/dev/null

# ==========================================================================
# list
# ==========================================================================

run 0 "fence/list-1" "$FF" fence --checkout "$A" --spec demo 4 >/dev/null
run 0 "fence/list-2" "$FF" fence --checkout "$A" --spec other 1 >/dev/null
got=$(run 0 "list/scoped" "$FF" list --checkout "$A" --spec demo | tr '\n' ' ')
[ "$got" = "refs/planwright-fence/demo/4" ] \
  || fail "list --spec: expected only the demo fences, got '$got'"
got=$(run 0 "list/all" "$FF" list --checkout "$A" | sort | tr '\n' ' ')
[ "$got" = "refs/planwright-fence/demo/4 refs/planwright-fence/other/1 " ] \
  || fail "list: expected both namespaces, got '$got'"
run 0 "gc/list-cleanup" "$FF" gc --checkout "$A" --spec demo 4 >/dev/null
run 0 "gc/list-cleanup-2" "$FF" gc --checkout "$A" --spec other 1 >/dev/null

# ==========================================================================
# REQ-C1.1 / REQ-C1.3 / REQ-C1.5 — Architecture A is ABSENT by construction
# ==========================================================================

# The MECHANISMS Architecture A needed, not the vocabulary: `reclaim` is a
# legitimate word here because it names the OPERATOR's action on a surfaced
# strand. What must be absent is machinery that performs it — a claim
# sub-surface, a per-unit reclaim lock and its under-lock re-read, the
# four-residue GC, and the record quarantine. (That nothing is auto-reclaimed
# is asserted behaviourally in the sweep suite; this is the structural half.)
for banned in "claims/" "reclaim[-_]lock" "quarantine" "dead-letter" "rename-aside" \
  "under-lock" "orchestrate-lock" "fleet-state.sh['\"]* lock" "\.lock"; do
  if grep -nE "^[^#]*($banned)" "$FF" >/dev/null 2>&1; then
    fail "Architecture A residue: '$banned' appears on a code line of fleet-fence.sh"
  fi
done
# No dispatch backend and no branch rename anywhere in the fencing path
# (REQ-C1.2): the tower pushes the canonical fence ref directly.
for banned in "fleet-dispatch-worktree" "claude --worktree" "branch -m" "--force[^-]" "push --force "; do
  if grep -nE "^[^#]*$banned" "$FF" >/dev/null 2>&1; then
    fail "fencing path must not reference '$banned'"
  fi
done
grep -q -- '--force-with-lease' "$FF" \
  || fail "the fence push must use the expect-absent --force-with-lease"
# The all-zeros OID, never the bare-empty nothing-after-the-colon form.
grep -qE '040d|064d|0{40}' "$FF" \
  || fail "the lease must name the object format's all-zeros OID explicitly"

echo "PASS: $(basename "$0")"
