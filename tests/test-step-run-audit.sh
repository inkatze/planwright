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
  _h=${5:-$(head_of)} _skip=''
  [ "$4" != skipped ] || _skip=1
  sr write --run "$1" --point "$2" --step "$3" --kind command --target "$bin/show.sh" \
    --hosting isolated --backend runner --head "$_h" --end-head "$_h" \
    --start 2026-11-04T00:00:00Z --end 2026-11-04T00:01:00Z --outcome "$4" \
    ${_skip:+--skip-code missing --skip-reason fixture} >/dev/null \
    || fail "fixture: the $3 record at $2"
}
done_at() { sr write --completion --run "$1" --point "$2" --head "${3:-$(head_of)}" >/dev/null || fail "fixture: the $2 completion"; }
audit() {
  srun audit "$@" >"$tmp/audit" 2>"$tmp/audit.err"
  RC=$?
}
# forge <record> <head>: rewrite a record's head as a hand-edited cache would.
forge() {
  awk -F '\t' -v H="$2" 'BEGIN { OFS = FS } $1 == "head" { $2 = H } { print }' "$1" >"$1.new" && mv "$1.new" "$1"
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

# --- a merge of the base alone keeps the record fresh; any other merge does not --
fresh
catalog "$SHOW"
config 'steps_convergence: [show]'
git -C "$wt" checkout -q -b base-tip
printf 'b\n' >"$wt/docs/b.txt"
git -C "$wt" add -A && git -C "$wt" commit -q -m "docs: base moved"
git -C "$wt" checkout -q -b other planwright/demo/task-1
printf 'o\n' >"$wt/docs/o.txt"
git -C "$wt" add -A && git -C "$wt" commit -q -m "docs: other feature"
git -C "$wt" checkout -q planwright/demo/task-1
r=$(sr new-run)
rec "$r" convergence show applied
done_at "$r" convergence
git -C "$wt" merge -q --no-ff -m "merge: base" base-tip
audit --through post-pr --base base-tip
[ "$RC" -eq 0 ] && grep -qx "covered${TAB}convergence" "$tmp/audit"
verdict $? "a merge of the base alone after the last point keeps it fresh" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
audit --through post-pr
[ "$RC" -eq 0 ] && grep -qx "covered${TAB}convergence" "$tmp/audit"
verdict $? "a last point followed only by a clean merge counts, with no --base too" "rc $RC: $(cat "$tmp/audit")"
printf 'x\n' >>"$wt/src/a.txt"
git -C "$wt" add -A && git -C "$wt" commit -q -m "fix: after the base merge"
audit --through post-pr --base base-tip
[ "$RC" -eq 1 ] && grep -q "^gap${TAB}convergence${TAB}stale" "$tmp/audit"
verdict $? "a plain commit after the last point is stale even with --base" "rc $RC: $(cat "$tmp/audit")"
git -C "$wt" checkout -q base-tip
printf 'c\n' >"$wt/docs/c.txt"
git -C "$wt" add -A && git -C "$wt" commit -q -m "docs: base moved again"
git -C "$wt" checkout -q -b smuggle planwright/demo/task-1~1
git -C "$wt" merge -q --no-ff --no-commit base-tip
printf 'smuggled\n' >"$wt/src/smuggled.txt"
git -C "$wt" add -A && git -C "$wt" commit -q -m "merge: base, with an edit"
audit --through post-pr --base base-tip
[ "$RC" -eq 1 ] && grep -q "^gap${TAB}convergence${TAB}stale" "$tmp/audit"
verdict $? "a base merge carrying an edit of its own is new work: stale" "rc $RC: $(cat "$tmp/audit")"
git -C "$wt" checkout -q planwright/demo/task-1~1
git -C "$wt" checkout -q -B planwright/demo/task-1
git -C "$wt" merge -q --no-ff -m "merge: other" other
audit --through post-pr --base base-tip
[ "$RC" -eq 1 ] && grep -q "^gap${TAB}convergence${TAB}stale" "$tmp/audit"
verdict $? "with --base, a merge bringing in work the base lacks makes the last point stale" "rc $RC: $(cat "$tmp/audit")"
audit --through post-pr --base no-such-ref
[ "$RC" -eq 2 ]
verdict $? "an unknown --base is a usage error" "rc $RC"

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
r3=$(sr new-run)
rec "$r3" convergence show failed
done_at "$r3" convergence
audit --through post-pr
[ "$RC" -eq 1 ] && grep -qx "gap${TAB}convergence${TAB}failed${TAB}show:failed" "$tmp/audit"
verdict $? "the newest attempt at a fresh head decides: a later failure outranks an earlier pass" \
  "rc $RC: $(cat "$tmp/audit")"
r4=$(sr new-run)
rec "$r4" convergence show skipped
done_at "$r4" convergence
audit --through post-pr
[ "$RC" -eq 0 ]
verdict $? "a skipped record (a reuse or resume) covers its step" "rc $RC: $(cat "$tmp/audit")"
r5=$(sr new-run)
done_at "$r5" convergence
audit --through post-pr
[ "$RC" -eq 1 ] && grep -qx "gap${TAB}convergence${TAB}missing${TAB}show" "$tmp/audit"
verdict $? "a completion whose run recorded no step does not borrow an earlier run's record" \
  "rc $RC: $(cat "$tmp/audit")"

# --- a re-fire record stands for its declaring point, not post-pr's own list ---------
fresh
catalog "$SHOW"
config 'steps_post_pr: [show]'
r=$(sr new-run)
sr write --run "$r" --point post-pr --step show --kind command --target "$bin/show.sh" \
  --hosting isolated --backend runner --head "$(head_of)" --end-head "$(head_of)" \
  --start 2026-11-04T00:00:00Z --end 2026-11-04T00:01:00Z --outcome passed --refire-of pre-pr \
  --fingerprint none --args-digest "$(printf '%064d' 0)" >"$tmp/refire.out" 2>&1 \
  || fail "fixture: the re-fire record: $(cat "$tmp/refire.out")"
done_at "$r" post-pr
audit --through post-pr
[ "$RC" -eq 1 ] && grep -qx "gap${TAB}post-pr${TAB}missing${TAB}show" "$tmp/audit"
verdict $? "a re-fire of the same step id does not stand in for post-pr's own run of it" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- records are untrusted ----------------------------------------------------------
fresh
catalog "$SHOW"
config 'steps_convergence: [show]'
r=$(sr new-run)
rec "$r" convergence show applied
done_at "$r" convergence
forge "$wt/.claude/steps/$r/002-done-convergence.rec" HEAD
commit after-forgery
audit --through post-pr
[ "$RC" -eq 1 ] && grep -qx "gap${TAB}convergence${TAB}incomplete${TAB}-" "$tmp/audit"
verdict $? "a completion naming a head outside commit-id form counts for nothing" "rc $RC: $(cat "$tmp/audit")"

# --- a completion on rewritten history does not count ----------------------------
fresh
catalog "$SHOW"
config 'steps_convergence: [show]' 'steps_post_pr: [show]'
commit before-rewrite
gone=$(head_of)
r=$(sr new-run)
rec "$r" convergence show applied "$gone"
done_at "$r" convergence "$gone"
git -C "$wt" reset -q --hard HEAD~1
commit rewritten
rec "$r" post-pr show passed
done_at "$r" post-pr
audit --through post-pr
[ "$RC" -eq 1 ] && grep -qx "gap${TAB}convergence${TAB}stale${TAB}$gone" "$tmp/audit" \
  && grep -qx "covered${TAB}post-pr" "$tmp/audit"
verdict $? "an earlier point completed on a head the branch no longer contains is stale" "rc $RC: $(cat "$tmp/audit")"

# --- --head names the head the audit judges ---------------------------------------
fresh
catalog "$SHOW"
config 'steps_convergence: [show]'
older=$(head_of)
commit newer
r=$(sr new-run)
rec "$r" convergence show applied
done_at "$r" convergence
audit --through post-pr --head "$older"
[ "$RC" -eq 1 ] && grep -qx "gap${TAB}convergence${TAB}stale${TAB}$(head_of)" "$tmp/audit" \
  && grep -qx "audit${TAB}gaps${TAB}$older" "$tmp/audit"
verdict $? "--head judges the named head, not the worktree's" "rc $RC: $(cat "$tmp/audit")"

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
config
mkdir -p "$wt/.claude"
printf 'steps_convergence: [no-such-step]\n' >"$wt/.claude/planwright.yml"
audit --through post-pr
[ "$RC" -eq 1 ] && grep -qx "gap${TAB}convergence${TAB}missing${TAB}no-such-step" "$tmp/audit"
verdict $? "a step that parks its point is still required" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
printf 'steps_convergence: not-a-list\n' >"$wt/.claude/planwright.yml"
audit --through post-pr
[ "$RC" -eq 4 ] && ! grep -q "^audit${TAB}complete" "$tmp/audit"
verdict $? "a steps configuration the resolver rejects exits 4 with no audit complete line" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
rm -f "$wt/.claude/planwright.yml"

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

# --- a misspelled PLANWRIGHT_STEP_* name: audit refuses, resolve warns -------------
for pair in SPEC_ID:SPEC TASK_ID:TASK_IDS TASK:TASK_IDS PR:PR_NUMBER BASE:BASE_BRANCH; do
  bad=${pair%%:*} want=${pair#*:}
  fresh
  catalog "$SHOW"
  config 'steps_convergence: [show]'
  env "PLANWRIGHT_STEP_$bad=1" "$RUN" --worktree "$wt" audit --through convergence >"$tmp/audit" 2>"$tmp/audit.err"
  RC=$?
  [ "$RC" -eq 2 ] && grep -q "PLANWRIGHT_STEP_$bad" "$tmp/audit.err" && grep -q "PLANWRIGHT_STEP_$want" "$tmp/audit.err"
  verdict $? "audit refuses PLANWRIGHT_STEP_$bad and names PLANWRIGHT_STEP_$want" "rc $RC: $(cat "$tmp/audit.err")"
done
fresh
catalog "$SHOW"
config 'steps_convergence: [show]'
r=$(sr new-run)
PLANWRIGHT_STEP_PR=7 srun resolve --run "$r" --attended convergence >"$tmp/res" 2>"$tmp/res.err"
RC=$?
[ "$RC" -eq 0 ] && [ -s "$tmp/res" ] && grep -q 'PLANWRIGHT_STEP_PR_NUMBER' "$tmp/res.err"
verdict $? "resolve only warns about PLANWRIGHT_STEP_PR and still resolves" "rc $RC: $(cat "$tmp/res.err")"
PLANWRIGHT_STEP_TASK=1 srun command --run "$r" --point convergence --step show >"$tmp/res" 2>"$tmp/res.err"
RC=$?
[ "$RC" -eq 2 ] && grep -q 'PLANWRIGHT_STEP_TASK_IDS' "$tmp/res.err" && [ -z "$(recs "$r")" ]
verdict $? "command refuses PLANWRIGHT_STEP_TASK and records nothing" "rc $RC: $(cat "$tmp/res.err")"

# A sibling resolve-steps.sh that cannot judge the context (any exit but its
# own 6) is its own breakage, never reported as a misspelled name.
broken="$tmp/broken-scripts"
mkdir "$broken"
for f in "$repo_root/scripts"/*.sh; do
  [ "$f" = "$repo_root/scripts/resolve-steps.sh" ] || ln -s "$f" "$broken/${f##*/}"
done
# shellcheck disable=SC2016 # the stub's own $1 must stay literal
printf '#!/bin/sh\ncase $1 in --check-env) echo "resolve-steps: broken install" >&2; exit 5 ;; esac\nexec "%s" "$@"\n' "$repo_root/scripts/resolve-steps.sh" >"$broken/resolve-steps.sh"
chmod +x "$broken/resolve-steps.sh"
env_run "$broken/step-run.sh" --worktree "$wt" audit --through convergence >"$tmp/audit" 2>"$tmp/audit.err"
RC=$?
[ "$RC" -eq 1 ] && ! grep -q 'broken install' "$tmp/audit.err"
verdict $? "a sibling that exits 5 on --check-env is not reported as a bad name" "rc $RC: $(cat "$tmp/audit.err")"

# --- a round that never ran: a zero-duration, no-move skill or prompt record ----------
REVIEW="review|kind: command|target: $bin/show.sh"
# krec <run> <point> <step> <kind> <outcome> <start> <end> [<head> [<end-head>]]:
# one record of any kind with explicit times and heads.
krec() {
  _hd=${8:-$(head_of)}
  sr write --run "$1" --point "$2" --step "$3" --kind "$4" --target "$bin/show.sh" \
    --hosting isolated --backend runner --head "$_hd" --end-head "${9:-$_hd}" \
    --start "$6" --end "$7" --outcome "$5" >/dev/null || fail "fixture: the $3 record at $2"
}
T0=2026-11-04T00:00:00Z
T1=2026-11-04T00:05:00Z

fresh
catalog "$REVIEW"
config 'steps_convergence: [review]'
r=$(sr new-run)
krec "$r" convergence review skill applied "$T0" "$T0"
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 1 ] && grep -qx "gap${TAB}convergence${TAB}unrun${TAB}review" "$tmp/audit" \
  && grep -qx "audit${TAB}gaps${TAB}$(head_of)" "$tmp/audit" && grep -q "skipped" "$tmp/audit.err" \
  && grep -q "missing" "$tmp/audit.err"
verdict $? "a zero-duration, no-move skill record is an unrun gap, with the remedy" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

fresh
catalog "$REVIEW"
config 'steps_convergence: [review]'
r=$(sr new-run)
krec "$r" convergence review prompt passed "$T0" "$T0"
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 1 ] && grep -qx "gap${TAB}convergence${TAB}unrun${TAB}review" "$tmp/audit"
verdict $? "the same holds for a prompt record outcome passed" "rc $RC: $(cat "$tmp/audit")"

fresh
catalog "$REVIEW"
config 'steps_convergence: [review]'
r=$(sr new-run)
krec "$r" convergence review command applied "$T0" "$T0"
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ] && ! grep -q unrun "$tmp/audit"
verdict $? "a zero-duration command record is exempt" "rc $RC: $(cat "$tmp/audit")"

fresh
catalog "$REVIEW"
config 'steps_convergence: [review]'
r=$(sr new-run)
krec "$r" convergence review skill applied "$T0" "$T1"
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ] && ! grep -q unrun "$tmp/audit"
verdict $? "an end later than the start is evidence" "rc $RC: $(cat "$tmp/audit")"

fresh
catalog "$REVIEW"
config 'steps_convergence: [review]'
r=$(sr new-run)
h0=$(head_of)
commit moved
krec "$r" convergence review skill applied "$T0" "$T0" "$h0" "$(head_of)"
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ] && ! grep -q unrun "$tmp/audit"
verdict $? "a record whose head moved is evidence" "rc $RC: $(cat "$tmp/audit")"

fresh
catalog "$REVIEW"
config 'steps_convergence: [review]'
r=$(sr new-run)
krec "$r" convergence review skill applied "$T0" "$T0"
done_at "$r" convergence
r2=$(sr new-run)
sr write --run "$r2" --point convergence --step review --kind skill --target "$bin/show.sh" \
  --hosting isolated --backend runner --head "$(head_of)" --end-head "$(head_of)" \
  --start "$T0" --end "$T0" --outcome skipped --skip-code missing --skip-reason "round did not run" >/dev/null \
  || fail "fixture: the skipped record"
done_at "$r2" convergence
audit --through convergence
[ "$RC" -eq 0 ] && ! grep -q unrun "$tmp/audit"
verdict $? "a fresh run recording the step skipped with reason missing clears the gap" "rc $RC: $(cat "$tmp/audit")"

fresh
catalog "$REVIEW"
config 'steps_convergence: [review]'
r=$(sr new-run)
krec "$r" convergence review skill applied "$T0" "$T0"
done_at "$r" convergence
f=$(ls "$wt/.claude/steps/$r"/*-step-convergence.rec)
awk -F '\t' '$1 != "end-head"' "$f" >"$f.new" && mv "$f.new" "$f"
audit --through convergence
[ "$RC" -eq 1 ] && grep -qx "gap${TAB}convergence${TAB}unrun${TAB}review" "$tmp/audit"
verdict $? "a record without an end head is judged by its times: equal is unrun" "rc $RC: $(cat "$tmp/audit")"
r2=$(sr new-run)
krec "$r2" convergence review skill applied "$T0" "$T1"
done_at "$r2" convergence
f=$(ls "$wt/.claude/steps/$r2"/*-step-convergence.rec)
awk -F '\t' '$1 != "end-head"' "$f" >"$f.new" && mv "$f.new" "$f"
audit --through convergence
! grep -q unrun "$tmp/audit"
verdict $? "a record without an end head and a later end is not unrun" "$(cat "$tmp/audit")"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "All step-run audit tests passed."
