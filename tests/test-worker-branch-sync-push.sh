#!/bin/bash
# Tests for scripts/worker-branch-sync.sh push, the leased push a worker
# mission control launched publishes a rewrite of its own draft branch through
# (human-gates REQ-F1.8, REQ-F1.10, REQ-G1.14): what it pushes, prints and
# audits, and every refusal, each pushing nothing. The shared record and
# branch checks every verb makes are tests/test-worker-branch-sync.sh's.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-worker-branch-sync-push.sh
unset CDPATH
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/worker-branch-sync-fixture.sh
. "$here/lib/worker-branch-sync-fixture.sh"

ALLOW='launcher=mission-control draft_rewrite=allow'
# shellcheck disable=SC2086 # the two record lines, split on purpose
record "$wt" "$B" $ALLOW
DRAFT="[{\"number\":7,\"isDraft\":true,\"headRefName\":\"$B\",\"isCrossRepository\":false}]"
STUB_HEADS=$DRAFT
STUB_BASES='[]'
export STUB_HEADS STUB_BASES

# rewrite [<git commit options>...] — push a new commit plainly, then amend
# it with a content change; sets LEASE (the pushed tip) and NEW (the rewrite).
n=0
rewrite() {
  n=$((n + 1))
  g -C "$wt" commit -q --allow-empty "$@" -m "work $n"
  g -C "$wt" push -q origin "$B"
  LEASE=$(g -C "$wt" rev-parse HEAD)
  printf '%s\n' "$n" >"$wt/f$n"
  g -C "$wt" add "f$n"
  g -C "$wt" commit -q --amend --no-edit
  NEW=$(g -C "$wt" rev-parse HEAD)
}
push_args() { printf '%s\n' "--force-with-lease=$B:$1"; }
# untouched <label> — the remote branch still sits at the lease.
untouched() { [ "$(remote_tip "$B")" = "$LEASE" ] || fail "$1: a refused push moved origin's branch"; }
try() { # <label> <args...> — a push that must be refused, pushing nothing
  local label=$1
  shift
  run "$wt" push "$@"
  refused "$label"
  untouched "$label"
}

# --- the push ------------------------------------------------------------------

rewrite
: >"$GHLOG"
run "$wt" push "$(push_args "$LEASE")" --force-if-includes
[ "$RC" = 0 ] || fail "the leased push of a draft branch did not succeed: $OUT"
[ "$(remote_tip "$B")" = "$NEW" ] || fail "origin's branch is not the rewrite after the push"
has "^pushed	$B	$LEASE	$NEW" "the push names the branch, the lease and the new head"
has "^replaced	$LEASE	work $n" "the push names the commit it replaced"
grep -q -- '--repo github.com/acme/demo' "$GHLOG" || fail "the PR read did not pass the push remote's repository: $(cat "$GHLOG")"
# The line lands in the session's own log, the one its record_key names.
audit="$tmp/fleet/allow-audit/session-$(basename "$(rec_path "$wt")" .record).log"
grep -q "	draft-rewrite-push	$B	$LEASE	$NEW\$" "$audit" 2>/dev/null || fail "no audit line for the push in $audit"
[ ! -e "$tmp/fleet/allow-audit/$(basename "$(rec_path "$wt")" .record).log" ] || fail "the push wrote a log named after the worktree's copy, not the session's"
pass "F1.8: a draft branch's rewrite is pushed on the lease, naming what it replaced, with an audit line in the session's own log"

# --- the record's authority ------------------------------------------------------

rewrite
record "$wt" "$B" launcher=mission-control
try "a record with no draft_rewrite" "$(push_args "$LEASE")" --force-if-includes
has 'draft_rewrite is not allow' "the knob refusal names it"
record "$wt" "$B" launcher=mission-control draft_rewrite=deny
try "draft_rewrite=deny" "$(push_args "$LEASE")" --force-if-includes
has 'draft_rewrite is not allow' "the deny refusal names the knob"
record "$wt" "$B" launcher=mission-control draft_rewrite=sometimes
try "draft_rewrite with a value outside allow and deny" "$(push_args "$LEASE")" --force-if-includes
has 'draft_rewrite is not allow' "the invalid-value refusal names the knob"
record "$wt" "$B" launcher=tower draft_rewrite=allow
try "a record naming another launcher" "$(push_args "$LEASE")" --force-if-includes
has 'mission control' "the launcher refusal names mission control"
record "$wt" "$B" draft_rewrite=allow
try "a record naming no launcher" "$(push_args "$LEASE")" --force-if-includes
has 'mission control' "the no-launcher refusal names mission control"
rm -f "$(rec_path "$wt")"
try "no record at the worktree's own path" "$(push_args "$LEASE")" --force-if-includes
has 'no session record' "the missing-record refusal says why"
# shellcheck disable=SC2086
record "$wt" "$B" $ALLOW
chmod 000 "$(rec_path "$wt")"
if [ -r "$(rec_path "$wt")" ]; then
  chmod 600 "$(rec_path "$wt")"
  printf '%s\n' "skip: an unreadable record (this user reads every file, as root does)"
else
  try "an unreadable record" "$(push_args "$LEASE")" --force-if-includes
  chmod 600 "$(rec_path "$wt")"
fi
grep -v '^record_key=' "$(rec_path "$wt")" >"$tmp/r" && mv "$tmp/r" "$(rec_path "$wt")" && chmod 600 "$(rec_path "$wt")"
try "a record naming no record_key" "$(push_args "$LEASE")" --force-if-includes
has 'record_key' "the no-record-key refusal says why"
# shellcheck disable=SC2086
record "$wt" "$B" $ALLOW
grep -v '^audit_log_home=' "$(rec_path "$wt")" >"$tmp/r" && printf 'audit_log_home=%s\n' "$tmp/no-such-home" >>"$tmp/r" \
  && mv "$tmp/r" "$(rec_path "$wt")" && chmod 600 "$(rec_path "$wt")"
try "an audit-log home that does not exist" "$(push_args "$LEASE")" --force-if-includes
has 'audit' "the missing audit-home refusal says why"
# A forged record the environment names never stands in for the worktree's.
# shellcheck disable=SC2086
record "$wt" "$B" $ALLOW
cp "$(rec_path "$wt")" "$tmp/forged.record"
record "$wt" "$B" launcher=mission-control draft_rewrite=deny
RC=0
OUT=$(cd "$wt" && PLANWRIGHT_WORKER_SESSION_RECORD="$tmp/forged.record" "$SCRIPT" push "$(push_args "$LEASE")" --force-if-includes 2>&1) || RC=$?
refused "an allowing record the environment names"
untouched "an allowing record the environment names"
record "$wt" "$B" $ALLOW 'pr_base=origin/main'
try "a malformed record (a key given twice)" "$(push_args "$LEASE")" --force-if-includes
has 'malformed' "the malformed-record refusal says why"
# shellcheck disable=SC2086
record "$wt" "$B" $ALLOW
pass "F1.8/G1.14: under deny, with another launcher or none, an environment-named record, or a malformed one, nothing is pushed"

# --- the environment ----------------------------------------------------------------

for v in GH_REPO=acme/other GH_HOST=ghe.example PLANWRIGHT_LOCAL_CONFIG="$tmp/x.yml" \
  PLANWRIGHT_CONFIG_DEFAULTS="$tmp/x.yml" PLANWRIGHT_REPO_ROOT="$tmp" PLANWRIGHT_CONFIG_STRICT_OVERLAYS=1; do
  RC=0
  OUT=$(cd "$wt" && env "$v" "$SCRIPT" push "$(push_args "$LEASE")" --force-if-includes 2>&1) || RC=$?
  refused "$v in the environment"
  untouched "$v in the environment"
  has "${v%%=*} is set" "the override refusal names ${v%%=*}"
done
pass "F1.8: a GH_REPO, GH_HOST or planwright config override in the environment is refused"

# --- the grammar and the lease ------------------------------------------------------

try "no --force-if-includes" "$(push_args "$LEASE")"
has 'exactly' "the missing-flag refusal names the grammar"
try "--force-if-includes first" --force-if-includes "$(push_args "$LEASE")"
has 'first' "the flag-order refusal says the lease comes first"
try "a remote" "$(push_args "$LEASE")" --force-if-includes origin
has 'exactly' "the extra-remote refusal names the grammar"
try "a refspec" "$(push_args "$LEASE")" --force-if-includes "$B:$B"
has 'exactly' "the extra-refspec refusal names the grammar"
try "a + form" "$(push_args "$LEASE")" --force-if-includes "+$B"
has 'exactly' "the + form refusal names the grammar"
try "--force" --force --force-if-includes
has 'first' "the --force refusal asks for the lease"
try "a bare lease" --force-with-lease --force-if-includes
has 'first' "the bare-lease refusal asks for the branch and the id"
try "a short lease" "$(push_args "${LEASE%????????????????????????????}")" --force-if-includes
has 'full commit id' "the short-lease refusal says why"
try "a lease that is HEAD" "$(push_args "$NEW")" --force-if-includes
has 'nothing to rewrite' "the lease-is-HEAD refusal says why"
try "a lease HEAD descends from" "$(push_args "$(g -C "$wt" rev-parse "$LEASE^")")" --force-if-includes
has 'fast-forward' "the fast-forward-lease refusal says a plain push suffices"
try "a lease on another branch" "--force-with-lease=planwright/flight/other:$LEASE" --force-if-includes
has 'checked out' "the other-branch lease refusal says why"
stranger=$(g -C "$wt" commit-tree -p "$LEASE^" -m "never a tip here" "HEAD^{tree}")
try "a lease the reflog never recorded" "$(push_args "$stranger")" --force-if-includes
has 'never held' "the unrecorded-lease refusal says why"
logs=$(g -C "$wt" rev-parse --git-common-dir)/logs/refs/heads/$B
mv "$logs" "$tmp/reflog"
try "a missing reflog" "$(push_args "$LEASE")" --force-if-includes
has 'no reflog' "the missing-reflog refusal says why"
mv "$tmp/reflog" "$logs"
pass "F1.8: any other grammar, a short, foreign or unrecorded lease, or a missing reflog is refused"

# --- the tree, the branch and its authors ----------------------------------------------

printf 'dirty\n' >"$wt/untracked.txt"
try "a dirty tree" "$(push_args "$LEASE")" --force-if-includes
has 'not clean' "the dirty-tree refusal says why"
rm -f "$wt/untracked.txt"
twin="$tmp/wt-twin"
g -C "$primary" worktree add -q --force "$twin" "$B"
try "a branch another worktree holds" "$(push_args "$LEASE")" --force-if-includes
has 'another worktree' "the shared-branch refusal names the other worktree"
g -C "$primary" worktree remove --force "$twin"
g -C "$wt" switch -q -c planwright/flight/unrecorded
try "an unrecorded branch" "--force-with-lease=planwright/flight/unrecorded:$LEASE" --force-if-includes
has 'names the unit branch' "the unrecorded-branch refusal names the recorded branch"
g -C "$wt" switch -q "$B"
pd="$tmp/wt-prot"
worktree "$pd" planwright/flight/prot
# shellcheck disable=SC2086
record "$pd" planwright/flight/prot $ALLOW
prot_tip=$(remote_tip planwright/flight/prot)
run "$pd" push "--force-with-lease=planwright/flight/prot:$prot_tip" --force-if-includes
refused "a protected branch"
has 'protected set' "the protected-branch refusal says why"
pass "F1.8: a dirty tree, a branch another worktree holds, an unrecorded or a protected branch is refused"

g -C "$wt" reset -q --hard "$LEASE"
g -C "$wt" commit -q --allow-empty --author='Someone Else <else@example.invalid>' -m "their commit"
g -C "$wt" push -q origin "$B"
LEASE=$(g -C "$wt" rev-parse HEAD)
g -C "$wt" commit -q --allow-empty --amend --no-edit --reset-author
try "a replaced commit by another author" "$(push_args "$LEASE")" --force-if-includes
has 'else@example.invalid' "the author refusal names the commit's author"
# The identity is the launch's, not the repository config the worker can write.
g -C "$primary" config user.name 'Someone Else'
g -C "$primary" config user.email else@example.invalid
try "another author's commit, under a config rewritten to that author" "$(push_args "$LEASE")" --force-if-includes
has 'else@example.invalid' "the rewritten-config refusal names the commit's author"
g -C "$primary" config user.name t
g -C "$primary" config user.email t@example.invalid
# The replaced set is what the push drops, bounded by no local ref a worker can move.
base_before=$(g -C "$wt" rev-parse refs/remotes/origin/main)
g -C "$wt" update-ref refs/remotes/origin/main "$LEASE"
try "another author's commit, under a PR base moved onto the lease" "$(push_args "$LEASE")" --force-if-includes
has 'else@example.invalid' "the moved-base refusal names the commit's author"
g -C "$wt" update-ref refs/remotes/origin/main "$base_before"
fixed=$(rec_path "$wt")
grep -v '^author=' "$fixed" >"$tmp/r" && mv "$tmp/r" "$fixed" && chmod 600 "$fixed"
try "a record naming no author" "$(push_args "$LEASE")" --force-if-includes
has 'no author' "the no-author refusal says why"
# shellcheck disable=SC2086
record "$wt" "$B" $ALLOW
pass "F1.8: a rewrite replacing another author's commit is refused, whatever the repository config or the local PR base"

# --- the pull request -------------------------------------------------------------------

g -C "$wt" reset -q --hard "origin/$B"
rewrite
# Each case is <gh answer>|<label>|<the reason the refusal must give>.
for c in "[]|no PR|heads no open pull request" \
  "[{\"number\":7,\"isDraft\":false,\"headRefName\":\"$B\",\"isCrossRepository\":false}]|a ready PR|ready for review" \
  "[{\"number\":7,\"isDraft\":true,\"headRefName\":\"$B\",\"isCrossRepository\":false},{\"number\":8,\"isDraft\":true,\"headRefName\":\"$B\",\"isCrossRepository\":false}]|two PRs|more than one" \
  "[{\"number\":7,\"isDraft\":true,\"headRefName\":\"$B\",\"isCrossRepository\":true}]|a cross-repository PR|another repository" \
  "[{\"number\":7,\"headRefName\":\"$B\",\"isCrossRepository\":false}]|a PR with no draft state|could not be read" \
  "not json|an unreadable answer|could not be read"; do
  label=${c#*|}
  label=${label%|*}
  STUB_HEADS=${c%%|*} try "$label" "$(push_args "$LEASE")" --force-if-includes
  has "${c##*|}" "the refusal for $label says why"
done
STUB_BASES='[{"number":9}]' try "a PR based on the branch" "$(push_args "$LEASE")" --force-if-includes
has 'as its base' "the stacked-PR refusal says why"
STUB_BASES='{' try "an unreadable base answer" "$(push_args "$LEASE")" --force-if-includes
has 'could not be read' "the unreadable-base refusal says why"
STUB_GH_FAIL=1 try "a failed host read" "$(push_args "$LEASE")" --force-if-includes
has 'could not list' "the failed-read refusal says why"
g -C "$primary" remote set-url origin "$origin"
try "a push remote naming no GitHub repository" "$(push_args "$LEASE")" --force-if-includes
has 'names no repository' "the non-GitHub-remote refusal says why"
g -C "$primary" remote set-url origin "$URL"
pass "F1.8: no PR, a ready, cross-repository or doubled PR, a stacked PR, or an unreadable host answer is refused"

# The PR is read in the repository the push reaches: a URL rewrite that
# sends the push elsewhere than the URL gh reads is refused.
g -C "$primary" remote set-url origin git@github.com:acme/decoy.git
g -C "$primary" config url.git@github.com:acme/demo.git.insteadOf git@github.com:acme/decoy.git
try "an insteadOf rewrite of the push URL" "$(push_args "$LEASE")" --force-if-includes
has 'sends the push to github.com/acme/demo, not github.com/acme/decoy' "the rewrite refusal names both repositories"
g -C "$primary" config --unset url.git@github.com:acme/demo.git.insteadOf
g -C "$primary" remote set-url origin "$URL"
g -C "$primary" config url.git@github.com:acme/elsewhere.git.pushInsteadOf "$URL"
try "a pushInsteadOf rewrite of the push URL" "$(push_args "$LEASE")" --force-if-includes
has 'rewrite' "the pushInsteadOf refusal says why"
g -C "$primary" config --unset url.git@github.com:acme/elsewhere.git.pushInsteadOf
g -C "$primary" config --add remote.origin.pushurl "$URL"
g -C "$primary" config --add remote.origin.pushurl git@github.com:acme/other.git
try "two push URLs" "$(push_args "$LEASE")" --force-if-includes
has 'single push URL' "the two-URL refusal says why"
g -C "$primary" config --unset-all remote.origin.pushurl
# Look-alikes: the same name under another owner, and on another host.
for alt in git@github.com:evil/demo.git:github.com/evil/demo git@gitlab.example:acme/demo.git:gitlab.example/acme/demo \
  ssh://git@github.com/acme/demo-fork.git:github.com/acme/demo-fork; do
  to=${alt%:*}
  g -C "$primary" config "url.$to.insteadOf" "$URL"
  try "a rewrite to $to" "$(push_args "$LEASE")" --force-if-includes
  has "sends the push to ${alt##*:}, not github.com/acme/demo" "the look-alike refusal names $to's repository"
  g -C "$primary" config --unset "url.$to.insteadOf"
done
pass "F1.8: the PR is read in the one repository the push reaches"
# A rewrite that keeps the repository (an https remote pushed over ssh) is fine.
g -C "$primary" remote set-url origin https://github.com/acme/demo.git
g -C "$primary" config url.git@github.com:.insteadOf https://github.com/
run "$wt" push "$(push_args "$LEASE")" --force-if-includes
g -C "$primary" config --unset url.git@github.com:.insteadOf
g -C "$primary" remote set-url origin "$URL"
[ "$RC" = 0 ] || fail "a same-repository https-to-ssh rewrite refused the push: $OUT"
[ "$(remote_tip "$B")" = "$NEW" ] || fail "the same-repository rewrite did not land the push"
grep -q -- '--repo github.com/acme/demo' "$GHLOG" || fail "the same-repository push read another repository: $(cat "$GHLOG")"
pass "F1.8: an https-to-ssh rewrite of the same repository still pushes"

# --- a moved remote ---------------------------------------------------------------------

other_clone="$tmp/other-clone"
g clone -q "$origin" "$other_clone"
g -C "$other_clone" switch -q "$B"
g -C "$other_clone" commit -q --allow-empty -m "someone else's push"
g -C "$other_clone" push -q origin "$B"
theirs=$(remote_tip "$B")
run "$wt" push "$(push_args "$LEASE")" --force-if-includes
refused "a remote moved past the lease"
has 'shared' "the moved-remote refusal reports the branch shared"
has 'never retry' "the moved-remote refusal forbids a retry"
[ "$(remote_tip "$B")" = "$theirs" ] || fail "the moved remote was overwritten"
pass "F1.8: a remote moved past the lease is reported shared, and left as it is"

# --- a legacy checklist item the rewrite re-identifies (REQ-F1.10) -----------------------

g -C "$wt" fetch -q origin "$B"
g -C "$wt" reset -q --hard "origin/$B"
g -C "$wt" commit -q --allow-empty -m "a finding [pending-sign-off]"
g -C "$wt" push -q origin "$B"
LEASE=$(g -C "$wt" rev-parse HEAD)
printf 'legacy\n' >"$wt/legacy"
g -C "$wt" add legacy
g -C "$wt" commit -q --amend --no-edit
NEW=$(g -C "$wt" rev-parse HEAD)
run "$wt" push "$(push_args "$LEASE")" --force-if-includes
[ "$RC" = 0 ] || fail "the push of a rewritten legacy item did not succeed: $OUT"
has "^legacy	PS-legacy-$(printf '%s' "$LEASE" | cut -c1-7)	PS-legacy-$(printf '%s' "$NEW" | cut -c1-7)\$" "the push names the legacy id the rewrite changed"
has 're-stamp' "the push tells the worker to re-stamp a rejection naming the old id"
pass "F1.10: a rewrite that re-identifies a legacy checklist item names the old and the new id"

printf '\npasses: %s\n' "$passes"
