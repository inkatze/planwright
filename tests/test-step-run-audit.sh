#!/bin/sh
# Tests for scripts/step-run.sh's `audit` verb: the configured cadence for a
# hand-on boundary compared with the step records at the current head, so a
# skipped point or step is caught whoever skipped it.
#
# Runs standalone under /bin/sh (the bash 3.2 / dash floor):
#   ./tests/test-step-run-audit.sh
# shellcheck disable=SC2319 # each verdict judges the condition just before it
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
umask 077

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
RUN="$repo_root/scripts/step-run.sh"
SR="$repo_root/scripts/step-record.sh"
SP="$repo_root/scripts/step-pool.sh"
TAB=$(printf '\t')

# shellcheck source=tests/lib/step-run-fixture.sh
. "$here/lib/step-run-fixture.sh"

SHOW="show|kind: command|target: $bin/show.sh"
# rec <run> <point> <step> <outcome> [<head>]: one step record ending on the
# head (default the worktree's).
rec() {
  _h=${5:-$(head_of)}
  sr write --run "$1" --point "$2" --step "$3" --kind command --target "$bin/show.sh" \
    --hosting isolated --backend runner --head "$_h" --end-head "$_h" \
    --start 2026-11-04T00:00:00Z --end 2026-11-04T00:01:00Z --outcome "$4" >/dev/null \
    || fail "fixture: the $3 record at $2"
}
done_at() { sr write --completion --run "$1" --point "$2" --head "${3:-$(head_of)}" >/dev/null || fail "fixture: the $2 completion"; }
audit() {
  srun audit "$@" >"$tmp/audit" 2>"$tmp/audit.err"
  RC=$?
}
commit() {
  printf '%s\n' "$1" >>"$wt/src/a.txt"
  git -C "$wt" add -A && git -C "$wt" commit -q -m "fix: $1"
}

# --- a session that ran no point at all is caught -----------------------------
fresh
catalog "$SHOW"
config 'steps_convergence: [show]' 'steps_post_pr: [show]'
audit --through post-pr
[ "$RC" -eq 1 ] && grep -qx "gap${TAB}convergence${TAB}incomplete${TAB}-" "$tmp/audit" \
  && grep -qx "gap${TAB}convergence${TAB}missing${TAB}show" "$tmp/audit" \
  && grep -qx "gap${TAB}post-pr${TAB}missing${TAB}show" "$tmp/audit" \
  && grep -qx "audit${TAB}gaps${TAB}$(head_of)" "$tmp/audit"
verdict $? "a configured cadence with no records names every missing point and step, exit 1" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
! grep -q "pre-implementation\|pre-ci\|pre-pr" "$tmp/audit"
verdict $? "a point whose configured list is empty asks for nothing" "$(cat "$tmp/audit")"

# --- the boundary bounds the points --------------------------------------------
audit --through pre-pr
[ "$RC" -eq 1 ] && ! grep -q "post-pr" "$tmp/audit"
verdict $? "--through pre-pr leaves post-pr for the later boundary" "$(cat "$tmp/audit")"

# --- a recorded cadence at the head is complete ----------------------------------
r=$(sr new-run)
rec "$r" convergence show applied
done_at "$r" convergence
rec "$r" post-pr show passed
done_at "$r" post-pr
audit --through post-pr
[ "$RC" -eq 0 ] && grep -qx "covered${TAB}convergence" "$tmp/audit" \
  && grep -qx "covered${TAB}post-pr" "$tmp/audit" && grep -qx "audit${TAB}complete${TAB}$(head_of)" "$tmp/audit"
verdict $? "every configured step recorded, every point completed at the head: complete, exit 0" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- work after the last point is unreviewed ------------------------------------
old=$(head_of)
commit after-post-pr
audit --through post-pr
[ "$RC" -eq 1 ] && grep -qx "gap${TAB}post-pr${TAB}stale${TAB}$old" "$tmp/audit" \
  && grep -qx "covered${TAB}convergence" "$tmp/audit"
verdict $? "a commit after the last point's completion is stale there; an earlier point on an ancestor stands" \
  "rc $RC: $(cat "$tmp/audit")"

# --- a merge from the base alone keeps the record fresh -------------------------
fresh
catalog "$SHOW"
config 'steps_convergence: [show]'
git -C "$wt" checkout -q -b side
printf 'b\n' >"$wt/docs/b.txt"
git -C "$wt" add -A && git -C "$wt" commit -q -m "docs: side"
git -C "$wt" checkout -q planwright/demo/task-1
r=$(sr new-run)
rec "$r" convergence show applied
done_at "$r" convergence
git -C "$wt" merge -q --no-ff -m "merge: base" side
audit --through post-pr
[ "$RC" -eq 0 ] && grep -qx "covered${TAB}convergence" "$tmp/audit"
verdict $? "a merge commit alone after the last point keeps it fresh" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- a failed step, and a later pass that supersedes it ---------------------------
fresh
catalog "$SHOW"
config 'steps_convergence: [show]'
r=$(sr new-run)
rec "$r" convergence show failed
done_at "$r" convergence
audit --through post-pr
[ "$RC" -eq 1 ] && grep -qx "gap${TAB}convergence${TAB}failed${TAB}show:failed" "$tmp/audit"
verdict $? "a step recorded only as failed is a gap naming its outcome" "rc $RC: $(cat "$tmp/audit")"
r2=$(sr new-run)
rec "$r2" convergence show passed
done_at "$r2" convergence
audit --through post-pr
[ "$RC" -eq 0 ]
verdict $? "a later run that passes the step closes the gap" "rc $RC: $(cat "$tmp/audit")"

# --- a completion on rewritten history does not count ----------------------------
fresh
catalog "$SHOW"
config 'steps_convergence: [show]'
commit before-rewrite
gone=$(head_of)
r=$(sr new-run)
rec "$r" convergence show applied "$gone"
done_at "$r" convergence "$gone"
git -C "$wt" reset -q --hard HEAD~1
commit rewritten
audit --through post-pr
[ "$RC" -eq 1 ] && grep -qx "gap${TAB}convergence${TAB}stale${TAB}$gone" "$tmp/audit"
verdict $? "a completion on a head the branch no longer contains is stale" "rc $RC: $(cat "$tmp/audit")"

# --- an empty cadence, and a step the host cannot resolve --------------------------
fresh
config 'steps_convergence: []'
audit --through post-pr
[ "$RC" -eq 0 ] && grep -qx "audit${TAB}complete${TAB}$(head_of)" "$tmp/audit" && ! grep -q '^gap' "$tmp/audit"
verdict $? "an empty configured cadence is complete" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
config 'steps_convergence: [no-such-step]'
audit --through post-pr
[ "$RC" -eq 0 ] && ! grep -q '^gap' "$tmp/audit"
verdict $? "a step the adopter layer names that does not resolve here is skipped, not required" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- usage ------------------------------------------------------------------------
audit --through merge
[ "$RC" -eq 2 ]
verdict $? "an unknown boundary point is a usage error" "rc $RC"
audit
[ "$RC" -eq 2 ]
verdict $? "--through is required" "rc $RC"
audit --through post-pr --head abc
[ "$RC" -eq 2 ]
verdict $? "a short --head is a usage error" "rc $RC"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "All step-run audit tests passed."
