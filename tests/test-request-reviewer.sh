#!/bin/bash
# Suite for scripts/request-reviewer.sh, the reviewer request that leaves a
# draft PR draft (human-gates REQ-C1.7, REQ-C1.8): the request, the draft-state
# check after it, the re-draft when the PR came back ready, a failed check
# treated as un-drafted, and a failed re-draft parking the unit.
#
# Hermetic: tests/lib/merge-policy-fixture.sh builds a throwaway origin and a
# unit clone; the stub gh below replaces its stub and answers from files.
# Nothing reaches a real host.
# shellcheck disable=SC2119 # no case here needs mp_fixture's base parks
unset CDPATH PLANWRIGHT_ROOT CLAUDE_PLUGIN_ROOT
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PLANWRIGHT_CONFIG_DEFAULTS="$REPO_ROOT/config/defaults.yml"
HELPER="$REPO_ROOT/scripts/request-reviewer.sh"

failures=0
passes=0
pass() {
  echo "ok: $1"
  passes=$((passes + 1))
}
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
check() { # <label> <command...>
  local label=$1
  shift
  if "$@"; then pass "$label"; else fail "$label"; fi
}
not() { ! "$@"; }

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/request-reviewer.XXXXXX") || exit 1
trap 'rm -rf "$SANDBOX"' EXIT
# shellcheck source=tests/lib/merge-policy-fixture.sh
. "$REPO_ROOT/tests/lib/merge-policy-fixture.sh"

if [ ! -f "$HELPER" ]; then
  fail "the helper exists at scripts/request-reviewer.sh"
  echo "request-reviewer: $passes passed, $failures failed" >&2
  exit 1
fi

# The stub: $GHS/ready marks the PR ready; undraft_on_request flips it ready
# when a review is requested; view_fail_at.<n> fails the nth view and
# view_json.<n> answers it verbatim; request_rc
# and undo_rc are the exits of the request and the re-draft.
cat >"$MP_STUBBIN/gh" <<'GHSTUB'
#!/bin/sh
{
  printf 'CALL'
  for a in "$@"; do printf ' %s' "$a"; done
  printf '\n'
} >>"$GHS/log"
case "$1 $2" in
  'pr view')
    n=0
    [ ! -f "$GHS/view_n" ] || n=$(cat "$GHS/view_n")
    n=$((n + 1))
    echo "$n" >"$GHS/view_n"
    if [ -f "$GHS/view_fail_at.$n" ]; then
      echo 'HTTP 502: Bad Gateway' >&2
      exit 1
    fi
    if [ -f "$GHS/view_json.$n" ]; then
      cat "$GHS/view_json.$n"
      exit 0
    fi
    draft=true
    [ ! -f "$GHS/ready" ] || draft=false
    head=planwright/demo/task-1
    [ ! -f "$GHS/head" ] || head=$(cat "$GHS/head")
    printf '{"isDraft":%s,"state":"OPEN","baseRefName":"main","headRefName":"%s"}\n' "$draft" "$head"
    ;;
  'pr edit' | 'api -X')
    rc=0
    [ ! -f "$GHS/request_rc" ] || rc=$(cat "$GHS/request_rc")
    [ ! -f "$GHS/undraft_on_request" ] || : >"$GHS/ready"
    exit "$rc"
    ;;
  'pr ready')
    case " $* " in
      *' --undo '*) ;;
      *) exit 3 ;;
    esac
    rc=0
    [ ! -f "$GHS/undo_rc" ] || rc=$(cat "$GHS/undo_rc")
    [ "$rc" != 0 ] || rm -f "$GHS/ready"
    exit "$rc"
    ;;
  *) exit 3 ;;
esac
GHSTUB
chmod +x "$MP_STUBBIN/gh"

run() { mp_run "$HELPER" --repo acme/widgets --pr 42 "$@"; }
undos() { mp_calls 'pr ready 42 --repo acme/widgets --undo'; }
requests() { grep -c '^CALL \(pr edit\|api -X POST\)' "$GHS/log" 2>/dev/null || true; }
is_draft() { [ ! -f "$GHS/ready" ]; }

mp_fixture
MP_TEMPLATE=$F

echo "# a draft PR the request leaves draft: no corrective"
mp_fixture
run --copilot
check "a request that leaves the PR draft exits 0" [ "$CODE" = 0 ]
check "the Copilot request goes through gh pr edit --add-reviewer @copilot" \
  [ "$(mp_calls 'pr edit 42 --repo acme/widgets --add-reviewer @copilot')" = 1 ]
check "the draft state is read before and after the request" [ "$(mp_calls 'pr view')" = 2 ]
check "no re-draft runs when the PR stayed draft" [ "$(undos)" = 0 ]

echo "# a request that un-drafts the PR is followed by a re-draft"
mp_fixture
: >"$GHS/undraft_on_request"
run --reviewer octocat
check "the re-drafted request exits 0" [ "$CODE" = 0 ]
check "a named reviewer is requested over REST" \
  [ "$(mp_calls 'api -X POST repos/acme/widgets/pulls/42/requested_reviewers -f reviewers\[\]=octocat')" = 1 ]
check "the re-draft ran once" [ "$(undos)" = 1 ]
req=$(grep -n '^CALL api -X POST' "$GHS/log" | head -1 | cut -d: -f1)
chk=$(grep -n '^CALL pr view' "$GHS/log" | sed -n 2p | cut -d: -f1)
und=$(grep -n '^CALL pr ready' "$GHS/log" | head -1 | cut -d: -f1)
check "the state check follows the request" [ "${req:-9999}" -lt "${chk:-0}" ]
check "the re-draft follows the state check" [ "${chk:-9999}" -lt "${und:-0}" ]
check "the PR is draft again" is_draft
check "the handoff says the PR was re-drafted" grep -q 're-drafted PR #42' <<<"$OUT"

echo "# a failing state check is treated as un-drafted"
mp_fixture
: >"$GHS/view_fail_at.2"
run --copilot
check "a failed state check still exits 0 once the corrective ran" [ "$CODE" = 0 ]
check "a failed state check runs the re-draft" [ "$(undos)" = 1 ]
check "the handoff names the unreadable state" grep -q 'could not be read' <<<"$OUT"

echo "# a failing re-draft parks the unit, naming the PR"
mp_fixture
: >"$GHS/undraft_on_request"
echo 1 >"$GHS/undo_rc"
run --copilot --spec specs/demo --task 1
check "a failed re-draft with a unit parks (exit 4)" [ "$CODE" = 4 ]
check "the park is pushed under Awaiting input, naming the PR" \
  grep -q '^- \*\*Task 1\*\* — pending ready-flip: redraft-pr-42 failed on ' <<<"$(mp_origin_tasks)"
check "the handoff names the un-drafted PR" grep -q 'PR #42 is no longer a draft' <<<"$OUT"

echo "# a failing re-draft after an unreadable check claims no un-draft it never saw"
mp_fixture
: >"$GHS/view_fail_at.2"
echo 1 >"$GHS/undo_rc"
run --copilot
check "a failed re-draft after an unreadable check with no unit exits 5" [ "$CODE" = 5 ]
check "the handoff says the PR may no longer be a draft" grep -q 'PR #42 may no longer be a draft' <<<"$OUT"
check "the handoff does not state an un-draft as fact" not grep -q 'PR #42 is no longer a draft' <<<"$OUT"

echo "# a park that cannot be written says why, never silent"
mp_fixture
: >"$GHS/undraft_on_request"
echo 1 >"$GHS/undo_rc"
printf '\n' >>"$F/wt/specs/demo/tasks.md"
run --copilot --spec specs/demo --task 1
check "a failed park with a unit exits 5" [ "$CODE" = 5 ]
check "the handoff relays the park's own reason" grep -q 'uncommitted changes' <<<"$OUT"
check "the handoff never claims the unit is parked" not grep -q 'the unit is parked' <<<"$OUT"

echo "# a failing re-draft parks only on the PR's own branch"
mp_fixture
: >"$GHS/undraft_on_request"
echo 1 >"$GHS/undo_rc"
echo planwright/other/task-2 >"$GHS/head"
before=$(mp_origin_head)
run --copilot --spec specs/demo --task 1
check "a checkout on another branch than the PR's parks nothing (exit 5)" [ "$CODE" = 5 ]
check "no park is pushed to a branch that is not the PR's" [ "$(mp_origin_head)" = "$before" ]
check "the handoff says why nothing was parked" grep -q "not on PR #42's branch" <<<"$OUT"

echo "# a failing re-draft with no unit is named, never silent"
mp_fixture
: >"$GHS/undraft_on_request"
echo 1 >"$GHS/undo_rc"
run --copilot
check "a failed re-draft with no unit to park exits 5" [ "$CODE" = 5 ]
check "the handoff names the un-drafted PR" grep -q 'PR #42 is no longer a draft' <<<"$OUT"

echo "# a PR that was ready before the request is left alone"
mp_fixture
: >"$GHS/ready"
run --copilot
check "a request on a ready PR exits 0" [ "$CODE" = 0 ]
check "a ready PR is never re-drafted" [ "$(undos)" = 0 ]
check "a ready PR needs no state check after the request" [ "$(mp_calls 'pr view')" = 1 ]

echo "# an unreadable state before the request makes no request"
mp_fixture
: >"$GHS/view_fail_at.1"
run --copilot
check "an unreadable starting state skips (exit 3)" [ "$CODE" = 3 ]
check "no request is made over an unreadable starting state" [ "$(requests)" = 0 ]
check "no re-draft runs over an unreadable starting state" [ "$(undos)" = 0 ]

echo "# a starting state missing a field is unreadable, not ready"
for json in '{"state":"OPEN","baseRefName":"main","headRefName":"planwright/demo/task-1"}' '{"isDraft":null,"state":"OPEN","baseRefName":"main","headRefName":"planwright/demo/task-1"}' \
  '{"isDraft":true,"state":"OPEN","baseRefName":"","headRefName":"planwright/demo/task-1"}' '{"isDraft":true,"baseRefName":"main","headRefName":"planwright/demo/task-1"}' \
  '{"isDraft":true,"state":"OPEN","baseRefName":"main","headRefName":""}' '{"isDraft":true,'; do
  mp_fixture
  printf '%s\n' "$json" >"$GHS/view_json.1"
  run --copilot
  check "an incomplete starting state skips (exit 3): $json" [ "$CODE" = 3 ]
  check "no request is made over an incomplete starting state: $json" [ "$(requests)" = 0 ]
done

echo "# an incomplete state after the request is treated as un-drafted"
mp_fixture
printf '%s\n' '{"state":"OPEN","baseRefName":"main","headRefName":"planwright/demo/task-1"}' >"$GHS/view_json.2"
run --copilot
check "an incomplete state after the request runs the re-draft" [ "$(undos)" = 1 ]

echo "# a failed request still checks the draft state"
mp_fixture
echo 1 >"$GHS/request_rc"
: >"$GHS/undraft_on_request"
run --copilot
check "a failed request exits 1" [ "$CODE" = 1 ]
check "a failed request is still followed by the re-draft it needs" [ "$(undos)" = 1 ]
check "the PR is draft after a failed request" is_draft

echo "# an App reviewer is requested by its [bot] login"
mp_fixture
run --reviewer 'copilot-pull-request-reviewer[bot]'
check "an App login is accepted (exit 0)" [ "$CODE" = 0 ]
check "the REST body carries the [bot] login" \
  [ "$(mp_calls 'api -X POST repos/acme/widgets/pulls/42/requested_reviewers -f reviewers\[\]=copilot-pull-request-reviewer\[bot\]')" = 1 ]

echo "# a PR that is not open makes no request"
mp_fixture
printf '%s\n' '{"isDraft":false,"state":"MERGED","baseRefName":"main","headRefName":"planwright/demo/task-1"}' >"$GHS/view_json.1"
run --copilot
check "a merged PR skips (exit 3)" [ "$CODE" = 3 ]
check "no request is made on a merged PR" [ "$(requests)" = 0 ]
check "no re-draft runs on a merged PR" [ "$(undos)" = 0 ]
check "the handoff names the PR's state" grep -q 'PR #42 is MERGED, not open' <<<"$OUT"

echo "# a missing gh or jq makes no request"
NOGH="$SANDBOX/bin-nogh"
NOJQ="$SANDBOX/bin-nojq"
mkdir -p "$NOGH" "$NOJQ"
ln -s "$(command -v dirname)" "$NOGH/dirname"
ln -s "$(command -v jq)" "$NOGH/jq"
ln -s "$(command -v dirname)" "$NOJQ/dirname"
ln -s "$MP_STUBBIN/gh" "$NOJQ/gh"
for bin in "$NOGH" "$NOJQ"; do
  mp_fixture
  OUT=$(cd "$F/wt" && env PATH="$bin" GHS="$GHS" /bin/bash "$HELPER" --repo acme/widgets --pr 42 --copilot 2>&1)
  CODE=$?
  check "a missing tool skips (exit 3): ${bin##*/}" [ "$CODE" = 3 ]
  check "no gh call with a missing tool: ${bin##*/}" [ "$(mp_calls '')" = 0 ]
done
check "a missing gh is named" grep -q 'gh is not installed' <<<"$(cd "$F/wt" && env PATH="$NOGH" /bin/bash "$HELPER" --repo acme/widgets --pr 42 --copilot 2>&1)"

echo "# usage refusals make no host call"
for args in '--copilot --pr 4x2' '--reviewer' '--reviewer "a b"' '--reviewer octocat --copilot' '' \
  '--copilot --repo bad' '--copilot --task 1' '--copilot --spec specs/demo' \
  '--copilot --spec specs/demo --task 1x' '--copilot --spec ../x --task 1' '--copilot --spec a/./b --task 1' \
  '--copilot --spec a/../b --task 1' '--copilot --spec /tmp/demo --task 1' '--reviewer -octocat'; do
  mp_fixture
  # shellcheck disable=SC2086 # the cases are word lists on purpose
  eval "mp_run \"\$HELPER\" --repo acme/widgets --pr 42 $args"
  check "usage refuses (exit 2): $args" [ "$CODE" = 2 ]
  check "no gh call on a usage refusal: $args" [ "$(mp_calls '')" = 0 ]
done
for args in '--pr 42 --copilot' '--repo acme/widgets --copilot'; do
  mp_fixture
  # shellcheck disable=SC2086 # the cases are word lists on purpose
  mp_run "$HELPER" $args
  check "a missing --repo or --pr is refused (exit 2): $args" [ "$CODE" = 2 ]
  check "no gh call without --repo or --pr: $args" [ "$(mp_calls '')" = 0 ]
done

echo "# echo discipline"
# shellcheck disable=SC2016 # a literal pattern, not an expansion
check "the helper sources scripts/echo-safety.sh" grep -q '\. "\$SCRIPTS/echo-safety.sh"' "$HELPER"

echo "request-reviewer: $passes passed, $failures failed"
[ "$failures" = 0 ]
