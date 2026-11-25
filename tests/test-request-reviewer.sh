#!/bin/bash
# Suite for scripts/request-reviewer.sh, the reviewer request that leaves a
# draft PR draft (human-gates REQ-C1.7, REQ-C1.8): the request, the draft-state
# check after it, the re-draft when the PR came back ready, a failed check
# treated as un-drafted, a failed re-draft parking the unit, and the wait that
# refuses an accepted request that never lands.
#
# Hermetic: tests/lib/merge-policy-fixture.sh builds a throwaway origin and a
# unit clone; the stub gh below replaces its stub and answers from files.
# Nothing reaches a real host.
# shellcheck disable=SC2119 # no case here needs mp_fixture's base parks
unset CDPATH
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=tests/lib/hermetic-env.sh
. "$REPO_ROOT/tests/lib/hermetic-env.sh"
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
# The review requests the GraphQL read answers: $GHS/events holds the
# timeline's review-request events (`<id> <login>` lines) and $GHS/pending the
# requested reviewers' logins. A request that succeeds lands an event for its
# reviewer unless no_land exists; pending_only lands it as a pending reviewer
# with no event; land_at holds the read from which a landed request shows;
# gq_fail_at.<n> fails the nth read and gq_json.<n> answers it verbatim.
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
    if [ "$rc" = 0 ] && [ ! -f "$GHS/no_land" ]; then
      who=copilot-pull-request-reviewer
      for a in "$@"; do
        case $a in 'reviewers[]='*) who=${a#reviewers\[\]=} who=${who%\[bot\]} ;; esac
      done
      if [ -f "$GHS/pending_only" ]; then
        echo "$who" >>"$GHS/landed_pending"
      else
        echo "RRE_new$$ $who" >>"$GHS/landed_events"
      fi
    fi
    exit "$rc"
    ;;
  'api graphql')
    n=0
    [ ! -f "$GHS/gq_n" ] || n=$(cat "$GHS/gq_n")
    n=$((n + 1))
    echo "$n" >"$GHS/gq_n"
    if [ -f "$GHS/gq_fail_at.$n" ]; then
      echo 'HTTP 502: Bad Gateway' >&2
      exit 1
    fi
    if [ -f "$GHS/gq_json.$n" ]; then
      cat "$GHS/gq_json.$n"
      exit 0
    fi
    show=1
    [ ! -f "$GHS/land_at" ] || [ "$n" -ge "$(cat "$GHS/land_at")" ] || show=0
    events=$(cat "$GHS/events" 2>/dev/null)
    pending=$(cat "$GHS/pending" 2>/dev/null)
    if [ "$show" = 1 ]; then
      events=$(printf '%s\n%s' "$events" "$(cat "$GHS/landed_events" 2>/dev/null)")
      pending=$(printf '%s\n%s' "$pending" "$(cat "$GHS/landed_pending" 2>/dev/null)")
    fi
    ev=$(printf '%s\n' "$events" | awk 'NF { printf "%s{\"id\":\"%s\",\"requestedReviewer\":{\"login\":\"%s\"}}", (c++ ? "," : ""), $1, $2 }')
    pe=$(printf '%s\n' "$pending" | awk 'NF { printf "%s{\"requestedReviewer\":{\"login\":\"%s\"}}", (c++ ? "," : ""), $1 }')
    printf '{"data":{"repository":{"pullRequest":{"reviewRequests":{"nodes":[%s]},"timelineItems":{"nodes":[%s]}}}}}\n' "$pe" "$ev"
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

export PLANWRIGHT_REQUEST_REVIEWER_POLL_SECONDS=0 PLANWRIGHT_REQUEST_REVIEWER_MAX_POLLS=3
run() { mp_run "$HELPER" --repo acme/widgets --pr 42 "$@"; }
gq_reads() { cat "$GHS/gq_n" 2>/dev/null || echo 0; }
undos() { mp_calls 'pr ready 42 --repo acme/widgets --undo'; }
requests() { grep -c '^CALL \(pr edit\|api -X POST\)' "$GHS/log" 2>/dev/null || true; }
is_draft() { [ ! -f "$GHS/ready" ]; }

mp_fixture
MP_TEMPLATE=$F
# fixture [<origin url>] — a unit clone whose origin names acme/widgets on
# GitHub (or <origin url>), still pushing to the throwaway origin.
fixture() {
  local url=${1:-https://github.com/acme/widgets.git}
  mp_fixture
  gitf remote set-url origin "$url"
  gitf config "url.$F/origin.git.insteadOf" "$url"
}

echo "# a draft PR the request leaves draft: no corrective"
fixture
run --copilot
check "a request that leaves the PR draft exits 0" [ "$CODE" = 0 ]
check "the Copilot request goes through gh pr edit --add-reviewer @copilot" \
  [ "$(mp_calls 'pr edit 42 --repo acme/widgets --add-reviewer @copilot')" = 1 ]
check "the draft state is read before and after the request" [ "$(mp_calls 'pr view')" = 2 ]
check "no re-draft runs when the PR stayed draft" [ "$(undos)" = 0 ]

echo "# a request that un-drafts the PR is followed by a re-draft"
fixture
: >"$GHS/undraft_on_request"
run --reviewer 'cubic-dev-ai[bot]'
check "the re-drafted request exits 0" [ "$CODE" = 0 ]
check "a named reviewer is requested over REST" \
  [ "$(mp_calls 'api -X POST repos/acme/widgets/pulls/42/requested_reviewers -f reviewers\[\]=cubic-dev-ai\[bot\]')" = 1 ]
check "the re-draft ran once" [ "$(undos)" = 1 ]
req=$(grep -n '^CALL api -X POST' "$GHS/log" | head -1 | cut -d: -f1)
chk=$(grep -n '^CALL pr view' "$GHS/log" | sed -n 2p | cut -d: -f1)
und=$(grep -n '^CALL pr ready' "$GHS/log" | head -1 | cut -d: -f1)
check "the state check follows the request" [ "${req:-9999}" -lt "${chk:-0}" ]
check "the re-draft follows the state check" [ "${chk:-9999}" -lt "${und:-0}" ]
check "the PR is draft again" is_draft
check "the handoff says the PR was re-drafted" grep -q 're-drafted PR #42' <<<"$OUT"

echo "# a failing state check is treated as un-drafted"
fixture
: >"$GHS/view_fail_at.2"
run --copilot
check "a failed state check still exits 0 once the corrective ran" [ "$CODE" = 0 ]
check "a failed state check runs the re-draft" [ "$(undos)" = 1 ]
check "the handoff names the unreadable state" grep -q 'could not be read' <<<"$OUT"

echo "# a failing re-draft parks the unit, naming the PR"
fixture
: >"$GHS/undraft_on_request"
echo 1 >"$GHS/undo_rc"
run --copilot --spec specs/demo --task 1
check "a failed re-draft with a unit parks (exit 4)" [ "$CODE" = 4 ]
check "the park is pushed under Awaiting input, naming the PR" \
  grep -q '^- \*\*Task 1\*\* — pending ready-flip: redraft-pr-42 failed on ' <<<"$(mp_origin_tasks)"
check "the handoff names the un-drafted PR" grep -q 'PR #42 is no longer a draft' <<<"$OUT"

echo "# a failing re-draft after an unreadable check claims no un-draft it never saw"
fixture
: >"$GHS/view_fail_at.2"
echo 1 >"$GHS/undo_rc"
run --copilot
check "a failed re-draft after an unreadable check with no unit exits 5" [ "$CODE" = 5 ]
check "the handoff says the PR may no longer be a draft" grep -q 'PR #42 may no longer be a draft' <<<"$OUT"
check "the handoff does not state an un-draft as fact" not grep -q 'PR #42 is no longer a draft' <<<"$OUT"

echo "# a park that cannot be written says why, never silent"
fixture
: >"$GHS/undraft_on_request"
echo 1 >"$GHS/undo_rc"
printf '\n' >>"$F/wt/specs/demo/tasks.md"
run --copilot --spec specs/demo --task 1
check "a failed park with a unit exits 5" [ "$CODE" = 5 ]
check "the handoff relays the park's own reason" grep -q 'uncommitted changes' <<<"$OUT"
check "the handoff never claims the unit is parked" not grep -q 'the unit is parked' <<<"$OUT"

echo "# a failing re-draft parks only on the PR's own branch"
fixture
: >"$GHS/undraft_on_request"
echo 1 >"$GHS/undo_rc"
echo planwright/other/task-2 >"$GHS/head"
before=$(mp_origin_head)
run --copilot --spec specs/demo --task 1
check "a checkout on another branch than the PR's parks nothing (exit 5)" [ "$CODE" = 5 ]
check "no park is pushed to a branch that is not the PR's" [ "$(mp_origin_head)" = "$before" ]
check "the handoff says why nothing was parked" grep -q "not on PR #42's branch" <<<"$OUT"

echo "# a failing re-draft with no unit is named, never silent"
fixture
: >"$GHS/undraft_on_request"
echo 1 >"$GHS/undo_rc"
run --copilot
check "a failed re-draft with no unit to park exits 5" [ "$CODE" = 5 ]
check "the handoff names the un-drafted PR" grep -q 'PR #42 is no longer a draft' <<<"$OUT"

echo "# a PR that was ready before the request is left alone"
fixture
: >"$GHS/ready"
run --copilot
check "a request on a ready PR exits 0" [ "$CODE" = 0 ]
check "a ready PR is never re-drafted" [ "$(undos)" = 0 ]
check "a ready PR needs no state check after the request" [ "$(mp_calls 'pr view')" = 1 ]

echo "# an unreadable state before the request makes no request"
fixture
: >"$GHS/view_fail_at.1"
run --copilot
check "an unreadable starting state skips (exit 3)" [ "$CODE" = 3 ]
check "no request is made over an unreadable starting state" [ "$(requests)" = 0 ]
check "no re-draft runs over an unreadable starting state" [ "$(undos)" = 0 ]

echo "# a starting state missing a field is unreadable, not ready"
for json in '{"state":"OPEN","baseRefName":"main","headRefName":"planwright/demo/task-1"}' '{"isDraft":null,"state":"OPEN","baseRefName":"main","headRefName":"planwright/demo/task-1"}' \
  '{"isDraft":true,"state":"OPEN","baseRefName":"","headRefName":"planwright/demo/task-1"}' '{"isDraft":true,"baseRefName":"main","headRefName":"planwright/demo/task-1"}' \
  '{"isDraft":true,"state":"OPEN","baseRefName":"main","headRefName":""}' '{"isDraft":true,'; do
  fixture
  printf '%s\n' "$json" >"$GHS/view_json.1"
  run --copilot
  check "an incomplete starting state skips (exit 3): $json" [ "$CODE" = 3 ]
  check "no request is made over an incomplete starting state: $json" [ "$(requests)" = 0 ]
done

echo "# an incomplete state after the request is treated as un-drafted"
fixture
printf '%s\n' '{"state":"OPEN","baseRefName":"main","headRefName":"planwright/demo/task-1"}' >"$GHS/view_json.2"
run --copilot
check "an incomplete state after the request runs the re-draft" [ "$(undos)" = 1 ]

echo "# a failed request still checks the draft state"
fixture
echo 1 >"$GHS/request_rc"
: >"$GHS/undraft_on_request"
run --copilot
check "a failed request exits 1" [ "$CODE" = 1 ]
check "a failed request is still followed by the re-draft it needs" [ "$(undos)" = 1 ]
check "the PR is draft after a failed request" is_draft

echo "# an App reviewer is requested by its [bot] login"
fixture
run --reviewer 'copilot-pull-request-reviewer[bot]'
check "an App login is accepted (exit 0)" [ "$CODE" = 0 ]
check "the REST body carries the [bot] login" \
  [ "$(mp_calls 'api -X POST repos/acme/widgets/pulls/42/requested_reviewers -f reviewers\[\]=copilot-pull-request-reviewer\[bot\]')" = 1 ]

echo "# an accepted request that never lands is refused, naming the fallback"
fixture
: >"$GHS/ready"
: >"$GHS/no_land"
run --copilot
check "an accepted request with no review request landing exits 6" [ "$CODE" = 6 ]
check "the landing wait is bounded: one read before the request, the poll cap after" [ "$(gq_reads)" = 4 ]
check "the refusal is the whole output, one line" [ "$(grep -c . <<<"$OUT")" = 1 ]
check "the refusal names what did not land" \
  grep -q 'the review request to Copilot on PR #42 did not land: no review_requested event and no pending request' <<<"$OUT"
check "the refusal names the draft-and-ready fallback that fires PR-Agent" \
  grep -q 'convert PR #42 to draft and mark it ready again' <<<"$OUT"
check "the refusal never claims the review was requested" not grep -q 'requested a review from' <<<"$OUT"
check "a ready PR is not re-drafted over a request that did not land" [ "$(undos)" = 0 ]

echo "# a request that lands a few reads later passes, and the wait stops there"
fixture
: >"$GHS/ready"
echo 3 >"$GHS/land_at"
run --copilot
check "a request whose review_requested event lands exits 0" [ "$CODE" = 0 ]
check "the wait stops at the read that saw it land" [ "$(gq_reads)" = 3 ]
check "the handoff says the request landed" grep -q 'requested a review from Copilot on PR #42' <<<"$OUT"

echo "# an earlier request's event is not this request landing"
fixture
: >"$GHS/ready"
: >"$GHS/no_land"
echo 'RRE_old copilot-pull-request-reviewer' >"$GHS/events"
run --copilot
check "an event from before the request does not count as landing (exit 6)" [ "$CODE" = 6 ]

echo "# a reviewer newly among the requested reviewers has landed"
fixture
: >"$GHS/ready"
: >"$GHS/pending_only"
run --reviewer 'cubic-dev-ai[bot]'
check "a request that shows only as a pending reviewer exits 0" [ "$CODE" = 0 ]
fixture
: >"$GHS/ready"
: >"$GHS/no_land"
echo cubic-dev-ai >"$GHS/pending"
run --reviewer 'cubic-dev-ai[bot]'
check "a reviewer already pending before the request is not a landing (exit 6)" [ "$CODE" = 6 ]

echo "# another reviewer's request landing is not this one"
fixture
: >"$GHS/ready"
: >"$GHS/no_land"
printf '%s\n' 'RRE_x cubic-dev-ai' >"$GHS/landed_events"
echo 2 >"$GHS/land_at"
run --copilot
check "only the requested reviewer's event counts (exit 6)" [ "$CODE" = 6 ]

echo "# on a draft, a request that does not land points at the ready flip"
fixture
: >"$GHS/no_land"
run --copilot
check "a draft whose request does not land exits 6" [ "$CODE" = 6 ]
check "the draft state is still checked after the request" [ "$(mp_calls 'pr view')" = 2 ]
check "the draft refusal names the ready flip as what fires PR-Agent" \
  grep -q 'marking PR #42 ready fires PR-Agent' <<<"$OUT"

echo "# a request that does not land on a draft that came back ready is still re-drafted"
fixture
: >"$GHS/no_land"
: >"$GHS/undraft_on_request"
echo 1 >"$GHS/undo_rc"
run --copilot
check "a failed re-draft outranks a request that did not land (exit 5)" [ "$CODE" = 5 ]
check "the handoff still names the request that did not land" grep -q 'did not land' <<<"$OUT"

echo "# unreadable review requests before the request make no request"
fixture
: >"$GHS/gq_fail_at.1"
run --copilot
check "unreadable review requests before the request skip (exit 3)" [ "$CODE" = 3 ]
check "no request is made when its landing could not be told" [ "$(requests)" = 0 ]

echo "# a read that fails while waiting is waited past"
fixture
: >"$GHS/ready"
: >"$GHS/gq_fail_at.2"
run --copilot
check "a failed read during the wait does not end it (exit 0)" [ "$CODE" = 0 ]
check "the wait read again after the failed read" [ "$(gq_reads)" = 3 ]

echo "# a failed request is not waited on"
fixture
: >"$GHS/ready"
echo 1 >"$GHS/request_rc"
run --copilot
check "a failed request reads the review requests only before it" [ "$(gq_reads)" = 1 ]

echo "# the review-request read names this PR, with owner and name as strings"
fixture
: >"$GHS/ready"
run --copilot
check "the read passes owner and name raw and the number typed" \
  [ "$(mp_calls 'api graphql -f query=.* -f owner=acme -f name=widgets -F number=42$')" -ge 2 ]

echo "# a newer event over an earlier one is a landing"
fixture
: >"$GHS/ready"
printf '%s\n' 'RRE_older copilot-pull-request-reviewer' 'RRE_old copilot-pull-request-reviewer' >"$GHS/events"
run --copilot
check "a new event after earlier ones for the reviewer exits 0" [ "$CODE" = 0 ]

echo "# Copilot's request lands under either of its logins"
fixture
: >"$GHS/ready"
: >"$GHS/no_land"
echo 'RRE_x Copilot' >"$GHS/landed_events"
echo 2 >"$GHS/land_at"
run --copilot
check "an event for the Copilot login counts as Copilot's (exit 0)" [ "$CODE" = 0 ]

echo "# a named bot lands by its event, whatever the login's case"
fixture
: >"$GHS/ready"
run --reviewer 'cubic-dev-ai[bot]'
check "a named bot whose event lands exits 0" [ "$CODE" = 0 ]
fixture
: >"$GHS/ready"
: >"$GHS/no_land"
echo 'RRE_x Cubic-Dev-AI' >"$GHS/landed_events"
echo 2 >"$GHS/land_at"
run --reviewer 'cubic-dev-ai[bot]'
check "a login in another case still matches (exit 0)" [ "$CODE" = 0 ]

echo "# a malformed or empty answer during the wait is polled past"
fixture
: >"$GHS/ready"
: >"$GHS/no_land"
printf '%s\n' '{"errors":[{"message":"boom"}],"data":null}' >"$GHS/gq_json.2"
printf '%s\n' '{"data":{"repository":{"pullRequest":{"reviewRequests":{"nodes":[{"requestedReviewer":{}}]},"timelineItems":{"nodes":[{"id":"RRE_t","requestedReviewer":null},{"id":"!!!","requestedReviewer":{"login":"copilot-pull-request-reviewer"}}]}}}}}' >"$GHS/gq_json.3"
run --copilot
check "a GraphQL error body, a reviewer with no login and an unusable id are not a landing (exit 6)" [ "$CODE" = 6 ]
check "every read in the bound was made" [ "$(gq_reads)" = 4 ]
fixture
printf '%s\n' '{"data":{"repository":{"pullRequest":null}}}' >"$GHS/gq_json.1"
run --copilot
check "a PR missing from the answer before the request skips (exit 3)" [ "$CODE" = 3 ]
check "the skip names the unreadable review requests" \
  grep -q 'the review requests on PR #42 could not be read, so no review was requested' <<<"$OUT"

echo "# no successful read during the wait says the landing is unconfirmed"
fixture
: >"$GHS/ready"
for i in 2 3 4; do : >"$GHS/gq_fail_at.$i"; done
run --copilot
check "an unconfirmed landing exits 6" [ "$CODE" = 6 ]
check "the handoff says the landing is unconfirmed, never that nothing landed" \
  grep -q 'is unconfirmed: every read of its review requests failed' <<<"$OUT"
check "the unconfirmed handoff asks for a PR-Agent check before the fallback" \
  grep -q 'check for a new PR-Agent run before falling back' <<<"$OUT"

echo "# a reviewer already requested before"
fixture
: >"$GHS/ready"
: >"$GHS/no_land"
echo copilot-pull-request-reviewer >"$GHS/pending"
run --copilot
check "an already-pending reviewer with no new event exits 6" [ "$CODE" = 6 ]
check "the handoff says the reviewer was already requested" \
  grep -q 'Copilot was already a requested reviewer and no new review_requested event followed' <<<"$OUT"
fixture
: >"$GHS/ready"
echo copilot-pull-request-reviewer >"$GHS/pending"
run --copilot
check "an already-pending reviewer with a new event exits 0" [ "$CODE" = 0 ]

echo "# exit precedence over a request that did not land"
fixture
: >"$GHS/no_land"
: >"$GHS/undraft_on_request"
run --copilot
check "a restored draft keeps the not-landed exit (6)" [ "$CODE" = 6 ]
check "the handoff names the re-draft" grep -q 're-drafted PR #42' <<<"$OUT"
und=$(grep -n '^CALL pr ready' "$GHS/log" | head -1 | cut -d: -f1)
last_gq=$(grep -n '^CALL api graphql' "$GHS/log" | tail -1 | cut -d: -f1)
check "the re-draft runs before the landing wait" [ "${und:-9999}" -lt "${last_gq:-0}" ]
fixture
: >"$GHS/no_land"
: >"$GHS/undraft_on_request"
echo 1 >"$GHS/undo_rc"
run --copilot --spec specs/demo --task 1
check "a parked unit outranks a request that did not land (exit 4)" [ "$CODE" = 4 ]

echo "# the wait sleeps between reads only, and its knobs fall back when malformed"
fixture
: >"$GHS/ready"
: >"$GHS/no_land"
cat >"$MP_STUBBIN/sleep" <<'SLEEPSTUB'
#!/bin/sh
echo "SLEEP $*" >>"$GHS/log"
SLEEPSTUB
chmod +x "$MP_STUBBIN/sleep"
PLANWRIGHT_REQUEST_REVIEWER_POLL_SECONDS=2 run --copilot
check "three reads sleep twice, never after the last" [ "$(grep -c '^SLEEP 2$' "$GHS/log")" = 2 ]
for case in '08 8' 'abc 3' '12345 3'; do
  read -r knob want <<<"$case"
  fixture
  : >"$GHS/ready"
  : >"$GHS/no_land"
  PLANWRIGHT_REQUEST_REVIEWER_POLL_SECONDS=$knob run --copilot
  check "POLL_SECONDS=$knob sleeps $want between reads" [ "$(grep -c "^SLEEP $want\$" "$GHS/log")" = 2 ]
done
rm -f "$MP_STUBBIN/sleep"
for case in '0 11' 'abc 11' '08 9'; do
  read -r knob want <<<"$case"
  fixture
  : >"$GHS/ready"
  : >"$GHS/no_land"
  PLANWRIGHT_REQUEST_REVIEWER_MAX_POLLS=$knob run --copilot
  check "MAX_POLLS=$knob makes $want reads in all" [ "$(gq_reads)" = "$want" ]
done

echo "# a PR that is not open makes no request"
fixture
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
for tool in dirname git sed tr; do
  ln -s "$(command -v "$tool")" "$NOGH/$tool"
  ln -s "$(command -v "$tool")" "$NOJQ/$tool"
done
ln -s "$(command -v jq)" "$NOGH/jq"
ln -s "$MP_STUBBIN/gh" "$NOJQ/gh"
for bin in "$NOGH" "$NOJQ"; do
  fixture
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
  fixture
  # shellcheck disable=SC2086 # the cases are word lists on purpose
  eval "mp_run \"\$HELPER\" --repo acme/widgets --pr 42 $args"
  check "usage refuses (exit 2): $args" [ "$CODE" = 2 ]
  check "no gh call on a usage refusal: $args" [ "$(mp_calls '')" = 0 ]
done
for args in '--pr 42 --copilot' '--repo acme/widgets --copilot'; do
  fixture
  # shellcheck disable=SC2086 # the cases are word lists on purpose
  mp_run "$HELPER" $args
  check "a missing --repo or --pr is refused (exit 2): $args" [ "$CODE" = 2 ]
  check "no gh call without --repo or --pr: $args" [ "$(mp_calls '')" = 0 ]
done

echo "# the request reaches only this checkout's own repository, and only bots"
for args in '--reviewer octocat' '--reviewer Octo-Cat'; do
  fixture
  # shellcheck disable=SC2086 # the cases are word lists on purpose
  mp_run "$HELPER" --repo acme/widgets --pr 42 $args
  check "a person as reviewer is refused (exit 2): $args" [ "$CODE" = 2 ]
  check "no gh call for a person as reviewer: $args" [ "$(mp_calls '')" = 0 ]
done
check "the refusal says only bots are requested" grep -q 'bot' <<<"$OUT"
for repo in acme/other evil/widgets acme/widgets-fork; do
  fixture
  mp_run "$HELPER" --repo "$repo" --pr 42 --copilot
  check "a repository other than the checkout's origin is refused (exit 2): $repo" [ "$CODE" = 2 ]
  check "no gh call on another repository: $repo" [ "$(mp_calls '')" = 0 ]
done
check "the refusal names the checkout's origin" grep -q "origin" <<<"$OUT"
fixture
gitf remote remove origin
mp_run "$HELPER" --repo acme/widgets --pr 42 --copilot
check "a checkout with no origin is refused (exit 2)" [ "$CODE" = 2 ]
check "no gh call with no origin" [ "$(mp_calls '')" = 0 ]
for url in git@github.com:acme/widgets.git ssh://git@github.com/acme/widgets https://github.com/Acme/Widgets/; do
  fixture "$url"
  run --copilot
  check "the checkout's own origin is accepted (exit 0): $url" [ "$CODE" = 0 ]
done
fixture
mp_run "$HELPER" --repo ACME/Widgets --pr 42 --copilot
check "the origin comparison ignores case, as GitHub does" [ "$CODE" = 0 ]

echo "# echo discipline"
# shellcheck disable=SC2016 # a literal pattern, not an expansion
check "the helper sources scripts/echo-safety.sh" grep -q '\. "\$SCRIPTS/echo-safety.sh"' "$HELPER"

echo "request-reviewer: $passes passed, $failures failed"
[ "$failures" = 0 ]
