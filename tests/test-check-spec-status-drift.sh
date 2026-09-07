#!/bin/bash
# Tests for scripts/check-spec-status-drift.sh — the stored-vs-derived spec
# status drift guard.
#
# The drift this guard exists to catch: on a Format-version 2 bundle the
# lifecycle state is DERIVED from live task evidence and is never written back
# to the header, so `**Status:** Ready` can stand unchanged long after every
# task has completed. `tasks-pr-sync.sh reconcile` will not close the gap — on
# a v2 bundle it short-circuits with "derived state is never stored" and writes
# nothing — so nothing in the repo notices. A reader who trusts the stored
# header reads a finished bundle as outstanding backlog.
#
# The contract under test:
#   - a bundle whose canonical status render derives Done while the header
#     stores something else is reported, naming the bundle and both values,
#     exit 1;
#   - a correctly stored bundle passes, and the clean report names how many
#     bundles were scanned — a guard that reports clean over an empty scan is
#     the failure mode this whole guard exists to prevent, so the count is part
#     of the contract, not decoration;
#   - derived Active against stored Ready is NOT drift (on v2 Active is never
#     stored, by design), so it must not be reported;
#   - Retired and Superseded are human-set terminal states with no skill-driven
#     transition out, so an all-tasks-complete bundle in either state is never
#     reported; Draft likewise makes no execution claim;
#   - a stored v1 Done bundle makes no derived claim and is never reported;
#   - the fail-closed arm: anything that would make the scan cover less than it
#     claims — a missing specs/, an unreadable bundle, a render that fails, a
#     transient evidence failure, an empty enumeration — is exit 2, never a
#     clean report.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
CHECKER="$REPO_ROOT/scripts/check-spec-status-drift.sh"

failures=0

assert() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

assert_contains() {
  case "$2" in
    *"$3"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (output did not mention '$3'): $2" >&2
      failures=$((failures + 1))
      ;;
  esac
}

assert_not_contains() {
  case "$2" in
    *"$3"*)
      echo "FAIL: $1 (output unexpectedly mentioned '$3'): $2" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker script missing at $CHECKER" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# git with a deterministic, signing-free identity (the house fixture pattern,
# tests/test-spec-status.sh).
gitc() {
  gc_repo="$1"
  shift
  git -C "$gc_repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# write_bundle <spec-dir> <status> <format-version> <n-tasks> [extra-header]
# A minimal bundle: requirements.md (the authoritative Status home) plus a
# tasks.md carrying <n-tasks> dependency-free task blocks. Both files mirror
# the header, as the format requires.
write_bundle() {
  wb_dir="$1"
  wb_status="$2"
  wb_fv="$3"
  wb_n="$4"
  wb_extra="${5:-}"
  mkdir -p "$wb_dir" || exit 1
  wb_header="**Status:** $wb_status
**Last reviewed:** 2026-09-07
**Format-version:** $wb_fv"
  if [ "$wb_fv" = 2 ]; then
    wb_header="$wb_header
**Execution:** derived — see the status render"
  fi
  if [ -n "$wb_extra" ]; then
    wb_header="$wb_header
$wb_extra"
  fi
  {
    printf '%s\n\n' "# Demo — Requirements"
    printf '%s\n\n' "$wb_header"
    printf '%s\n\n%s\n' "## Goal" "Fixture."
  } >"$wb_dir/requirements.md"
  {
    printf '%s\n\n' "# Demo — Tasks"
    printf '%s\n\n' "$wb_header"
    printf '%s\n\n' "## Tasks"
    wb_i=1
    while [ "$wb_i" -le "$wb_n" ]; do
      printf '### Task %s — fixture\n- **Dependencies:** none\n\n' "$wb_i"
      wb_i=$((wb_i + 1))
    done
    printf '%s\n\n%s\n\n' "## Awaiting input" "(none yet)"
    printf '%s\n\n%s\n\n' "## Deferred" "(none yet)"
    printf '%s\n\n%s\n' "## Out of scope" "(none yet)"
  } >"$wb_dir/tasks.md"
}

# complete_tasks <repo> <spec-id> <first> <last> — land a `Planwright-Task`
# trailer commit on main for each id in the range. The trailer is the engine's
# durable completion anchor, so these tasks derive completed with no branch, no
# PR, and no remote in play.
complete_tasks() {
  ct_repo="$1"
  ct_spec="$2"
  ct_i="$3"
  while [ "$ct_i" -le "$4" ]; do
    gitc "$ct_repo" commit -q --allow-empty \
      -m "work on $ct_spec task $ct_i" -m "Planwright-Task: $ct_spec/$ct_i" || exit 1
    ct_i=$((ct_i + 1))
  done
}

new_repo() {
  mkdir -p "$1" || exit 1
  git -C "$1" -c init.defaultBranch=main init -q || exit 1
}

seal() {
  gitc "$1" add -A || exit 1
  gitc "$1" commit -q -m "base: spec bundles" || exit 1
}

# ---------------------------------------------------------------------------
# 1. The drift case. A v2 bundle stored Ready whose every task derives
#    completed is the exact shape that misled a reader into treating a finished
#    bundle as backlog. It must be reported, by name, with both values.
#
#    The same root holds a bundle with work genuinely outstanding, so this case
#    also pins that the guard reports the drifted bundle SPECIFICALLY rather
#    than failing the whole root indiscriminately.
# ---------------------------------------------------------------------------
repo="$tmp/drift"
new_repo "$repo"
write_bundle "$repo/specs/drifted" Ready 2 2
write_bundle "$repo/specs/healthy" Ready 2 2
seal "$repo"
complete_tasks "$repo" drifted 1 2
complete_tasks "$repo" healthy 1 1

out=$("$CHECKER" "$repo" 2>&1)
rc=$?
assert "drift: a stored-Ready v2 bundle deriving Done exits 1" 1 "$rc"
assert_contains "drift: the report names the drifted bundle" "$out" "specs/drifted"
assert_contains "drift: the report names the stored value" "$out" "Ready"
assert_contains "drift: the report names the derived value" "$out" "Done"
assert_not_contains "drift: the bundle with work outstanding is not reported" \
  "$out" "specs/healthy"
# A failing run is the one an operator actually reads, so it carries the same
# coverage numbers the clean run does.
assert_contains "drift: the failing run reports its coverage" \
  "$out" "2 bundles scanned, 2 judged, 1 drifted"

# The guard resolves its own directory through a cd command substitution, so it
# owes the house regression test for that pattern (scripts/check-cdpath.sh):
# run it under a CDPATH holding a decoy `scripts` directory and assert the
# resolved path is still right. Invoking it by a BARE RELATIVE path is what
# makes cd consult CDPATH at all — an absolute or ./-prefixed path bypasses it,
# so the ambient environment proves nothing. Asserting the named bundle rather
# than a bare exit code is the point: a corrupted self_dir loses the render and
# fails for a different-looking reason.
decoy="$tmp/decoy"
mkdir -p "$decoy/scripts"
out=$(cd "$REPO_ROOT" && CDPATH="$decoy" /bin/bash scripts/check-spec-status-drift.sh "$repo" 2>&1)
rc=$?
assert "CDPATH: a decoy CDPATH does not derail the scan" 1 "$rc"
assert_contains "CDPATH: the drifted bundle is still identified" "$out" "specs/drifted"

# ---------------------------------------------------------------------------
# 2. THE NEGATIVE CONTROL. Every bundle here is stored correctly, and between
#    them they cover every shape that could be mistaken for drift:
#
#      healthy      v2 Ready, work outstanding      → derives Active
#      fresh        v2 Ready, no evidence at all    → derives Ready
#      drafted      v2 Draft                        → no execution claim
#      retired      v2 Retired, ALL tasks complete  → terminal, human-set
#      superseded   v2 Superseded, ALL complete     → terminal, human-set
#      legacy       v1 Done, all tasks complete     → v1 stores its own status
#
#    The retired/superseded pair is the one that matters most: their evidence
#    is identical to the drifted bundle in case 1, and flagging them would push
#    a reader toward a transition out of a terminal state that no skill accepts.
#
#    A guard that cannot fail is worthless, so this case also pins that the
#    clean report names a non-zero scanned count: green over an empty scan is
#    not the same fact as green over six bundles, and only the count tells them
#    apart.
# ---------------------------------------------------------------------------
repo="$tmp/clean"
new_repo "$repo"
write_bundle "$repo/specs/healthy" Ready 2 2
write_bundle "$repo/specs/fresh" Ready 2 2
write_bundle "$repo/specs/drafted" Draft 2 2
write_bundle "$repo/specs/retired" Retired 2 2
write_bundle "$repo/specs/superseded" Superseded 2 2 '**Superseded-by:** specs/healthy/'
write_bundle "$repo/specs/legacy" Done 1 2
# The accumulator directories are not bundles and must not break the scan.
mkdir -p "$repo/specs/_observations" "$repo/specs/_pending"
seal "$repo"
complete_tasks "$repo" healthy 1 1
complete_tasks "$repo" retired 1 2
complete_tasks "$repo" superseded 1 2
complete_tasks "$repo" legacy 1 2

out=$("$CHECKER" "$repo" 2>&1)
rc=$?
assert "negative control: a correctly stored tree passes" 0 "$rc"
assert_contains "negative control: the clean report names the scanned count" \
  "$out" "6 bundles"
# Scanned and judged are different facts. Four of these six make no derived
# claim at all, and counting them as coverage would overstate what the run
# proved — the clean line has to say which number is which.
assert_contains "negative control: the clean report separates judged from scanned" \
  "$out" "6 bundles scanned, 2 judged"
assert_not_contains "negative control: derived Active is not drift" "$out" "specs/healthy"
assert_not_contains "negative control: a Draft bundle is not drift" "$out" "specs/drafted"
assert_not_contains "negative control: a Retired bundle is never flagged" \
  "$out" "specs/retired"
assert_not_contains "negative control: a Superseded bundle is never flagged" \
  "$out" "specs/superseded"
assert_not_contains "negative control: a stored v1 Done bundle is not flagged" \
  "$out" "specs/legacy"

# ---------------------------------------------------------------------------
# 3. Fail-closed: a v2 bundle storing Active or Done violates the restricted v2
#    stored vocabulary. The render refuses it, and the guard must carry that
#    refusal out as exit 2 rather than swallowing it into a clean report.
# ---------------------------------------------------------------------------
repo="$tmp/v2active"
new_repo "$repo"
write_bundle "$repo/specs/wrongvocab" Active 2 1
seal "$repo"

out=$("$CHECKER" "$repo" 2>&1)
rc=$?
assert "fail-closed: a v2 bundle storing Active exits 2" 2 "$rc"
assert_contains "fail-closed: the refusal names the bundle" "$out" "specs/wrongvocab"

# ---------------------------------------------------------------------------
# 4. Fail-closed: an unreadable bundle. The guard cannot know whether an
#    unreadable header has drifted, and reporting the tree clean would claim
#    coverage it does not have.
# ---------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
  echo "ok: fail-closed: unreadable bundle (skipped, running as root)"
else
  repo="$tmp/unreadable"
  new_repo "$repo"
  write_bundle "$repo/specs/locked" Ready 2 1
  seal "$repo"
  chmod 000 "$repo/specs/locked/requirements.md"

  out=$("$CHECKER" "$repo" 2>&1)
  rc=$?
  chmod 644 "$repo/specs/locked/requirements.md"
  assert "fail-closed: an unreadable bundle file exits 2" 2 "$rc"
  assert_contains "fail-closed: the refusal names the unreadable bundle" "$out" "locked"
fi

# ---------------------------------------------------------------------------
# 5. Fail-closed: a transient evidence failure. A configured remote whose gh
#    query fails is the render's documented exit 3, and partial evidence must
#    never be presented as a clean status. This is the arm that keeps a network
#    outage from turning the guard vacuously green.
# ---------------------------------------------------------------------------
repo="$tmp/degraded"
new_repo "$repo"
write_bundle "$repo/specs/probed" Ready 2 1
seal "$repo"
gitc "$repo" remote add origin https://example.invalid/demo.git
stub="$tmp/binfail"
mkdir -p "$stub"
printf '#!/bin/sh\necho "gh: simulated outage" >&2\nexit 1\n' >"$stub/gh"
chmod +x "$stub/gh"

out=$(PATH="$stub:$PATH" "$CHECKER" "$repo" 2>&1)
rc=$?
assert "fail-closed: a transient evidence failure exits 2" 2 "$rc"
assert_not_contains "fail-closed: a degraded run never reports clean" "$out" "clean ("

# ---------------------------------------------------------------------------
# 6. Fail-closed: an empty enumeration. A root with no specs/ at all, and a
#    root whose specs/ holds only accumulators, both reach zero bundles. Zero
#    scanned bundles is a broken enumeration, not a clean tree — the whole
#    point of the scanned count in case 2.
# ---------------------------------------------------------------------------
repo="$tmp/nospecs"
new_repo "$repo"
gitc "$repo" commit -q --allow-empty -m base

out=$("$CHECKER" "$repo" 2>&1)
assert "fail-closed: a root with no specs/ exits 2" 2 $?
assert_contains "fail-closed: the missing scope directory is named" "$out" "specs"

repo="$tmp/onlyacc"
new_repo "$repo"
mkdir -p "$repo/specs/_pending"
: >"$repo/specs/_pending/notes.md"
seal "$repo"

out=$("$CHECKER" "$repo" 2>&1)
assert "fail-closed: a specs/ holding only accumulators exits 2" 2 $?
assert_not_contains "fail-closed: an empty enumeration never reports clean" "$out" "clean ("

# ---------------------------------------------------------------------------
# 7. A directory under specs/ with no requirements.md is not a bundle. The spec
#    validator owns bundle structure (check-memory-links.sh takes the same
#    line), so this guard reports the skip on stderr and keeps scanning rather
#    than either failing or silently absorbing it into the scanned count.
# ---------------------------------------------------------------------------
repo="$tmp/partial"
new_repo "$repo"
write_bundle "$repo/specs/real" Ready 2 1
mkdir -p "$repo/specs/notabundle"
: >"$repo/specs/notabundle/README.md"
seal "$repo"

out=$("$CHECKER" "$repo" 2>&1)
rc=$?
assert "structure: a directory with no requirements.md does not fail the scan" 0 "$rc"
assert_contains "structure: the skip is surfaced, not silent" "$out" "notabundle"
assert_contains "structure: the skipped directory is outside the scanned count" \
  "$out" "1 bundle"

# ---------------------------------------------------------------------------
# 8. Usage surface, mirroring check-cdpath.sh: --help alone exits 0, an unknown
#    option and a surplus argument are usage errors.
# ---------------------------------------------------------------------------
out=$("$CHECKER" --help 2>&1)
assert "usage: --help exits 0" 0 $?
assert_contains "usage: --help describes the guard" "$out" "Usage:"

out=$("$CHECKER" --help "$tmp" 2>&1)
assert "usage: --help with another argument exits 2" 2 $?

out=$("$CHECKER" --bogus 2>&1)
assert "usage: an unknown option exits 2" 2 $?

out=$("$CHECKER" "$tmp" "$tmp" 2>&1)
assert "usage: a surplus argument exits 2" 2 $?

out=$("$CHECKER" "$tmp/definitely-not-here" 2>&1)
assert "usage: a nonexistent root exits 2" 2 $?

# ---------------------------------------------------------------------------
# 9. The guard reports drift; it never repairs it. Editing a signed bundle
#    would move the anchor, so the scan must leave the tree byte-identical.
# ---------------------------------------------------------------------------
repo="$tmp/readonly"
new_repo "$repo"
write_bundle "$repo/specs/drifted" Ready 2 2
seal "$repo"
complete_tasks "$repo" drifted 1 2

before=$(find "$repo/specs" -type f -exec cksum {} \; | LC_ALL=C sort)
"$CHECKER" "$repo" >/dev/null 2>&1
after=$(find "$repo/specs" -type f -exec cksum {} \; | LC_ALL=C sort)
if [ "$before" = "$after" ]; then
  echo "ok: read-only: the scan writes nothing under specs/"
else
  echo "FAIL: read-only: the scan modified the spec tree" >&2
  failures=$((failures + 1))
fi

# ---------------------------------------------------------------------------
# 10. Fail-closed: a symlinked bundle directory. Following it would read a
#     bundle from outside the root while reporting it under a path inside the
#     root; skipping it would cover less than the scan claims. Neither is
#     honest, so it is refused.
# ---------------------------------------------------------------------------
repo="$tmp/symlinked"
new_repo "$repo"
write_bundle "$repo/specs/real" Ready 2 1
write_bundle "$tmp/outside/elsewhere" Ready 2 1
ln -s "$tmp/outside/elsewhere" "$repo/specs/elsewhere"
seal "$repo"

out=$("$CHECKER" "$repo" 2>&1)
rc=$?
assert "fail-closed: a symlinked bundle directory exits 2" 2 "$rc"
assert_contains "fail-closed: the refused symlink is named" "$out" "elsewhere"

# ---------------------------------------------------------------------------
# 11. Fail-closed: a bundle whose requirements.md is present but whose tasks.md
#     is absent. Absent and unreadable are different facts, and an incomplete
#     bundle must not be described as a permissions failure.
# ---------------------------------------------------------------------------
repo="$tmp/notasks"
new_repo "$repo"
write_bundle "$repo/specs/half" Ready 2 1
rm "$repo/specs/half/tasks.md"
seal "$repo"

out=$("$CHECKER" "$repo" 2>&1)
rc=$?
assert "fail-closed: a bundle with no tasks.md exits 2" 2 "$rc"
assert_contains "fail-closed: the missing file is named as missing" "$out" "no tasks.md"

# ---------------------------------------------------------------------------
# 12. Fail-closed: a directory name that is not a spec id. The render would
#     refuse it downstream anyway; refusing it here is what makes the
#     diagnostic name the real problem instead of a generic render failure.
# ---------------------------------------------------------------------------
repo="$tmp/badname"
new_repo "$repo"
write_bundle "$repo/specs/Bad_Name" Ready 2 1
seal "$repo"

out=$("$CHECKER" "$repo" 2>&1)
rc=$?
assert "fail-closed: a non-spec-id bundle directory exits 2" 2 "$rc"
assert_contains "fail-closed: the offending name is reported as not a spec id" \
  "$out" "not a spec id"

# ---------------------------------------------------------------------------
# 13. An explicitly empty root is a usage error, not an instruction to scan the
#     default tree. `${1:-default}` substitutes on empty as well as unset, so
#     without this the guard would silently report on a tree the caller never
#     named.
# ---------------------------------------------------------------------------
out=$("$CHECKER" "" 2>&1)
assert "usage: an empty root argument exits 2" 2 $?

# ---------------------------------------------------------------------------
# 14. The guard is wired as a mise task. An unwired guard is one nobody runs.
# ---------------------------------------------------------------------------
if grep -q '^\[tasks."check:spec-status-drift"\]' "$REPO_ROOT/mise.toml"; then
  echo "ok: wiring: the guard has a mise task"
else
  echo 'FAIL: wiring: no [tasks."check:spec-status-drift"] in mise.toml' >&2
  failures=$((failures + 1))
fi
if grep -q 'check-spec-status-drift.sh' "$REPO_ROOT/mise.toml"; then
  echo "ok: wiring: the mise task invokes the guard"
else
  echo "FAIL: wiring: the mise task does not invoke check-spec-status-drift.sh" >&2
  failures=$((failures + 1))
fi
# The exclusion from the `check` aggregate is a decision, not an omission: the
# guard runs the derivation engine once per bundle, and the bundles it reports
# today are real drift whose repair is a human lifecycle act. Pinning the
# absence is what stops it being "fixed" into the gate by someone reading the
# omission as an oversight.
if grep -q '"check:spec-status-drift",' "$REPO_ROOT/mise.toml"; then
  echo "FAIL: wiring: the guard is in the check aggregate, but it derives per bundle and is deliberately on-demand" >&2
  failures=$((failures + 1))
else
  echo "ok: wiring: the guard is deliberately outside the check aggregate"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "all check-spec-status-drift tests passed"
