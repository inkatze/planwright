#!/bin/bash
# Tests for scripts/pr-agent-reviewed.sh, the PR-Agent workflow's once-per-head
# check: a head the workflow's own run marker already records as reviewed
# successfully is not reviewed again, so the flip after a draft's review fires
# no second paid run. A stub gh answers from a comments file; nothing here
# reaches a real host.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$here/../scripts/pr-agent-reviewed.sh"
failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to run the script's jq program" >&2
  exit 1
}
[ -f "$SCRIPT" ] || {
  echo "FAIL: scripts/pr-agent-reviewed.sh is missing" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-pr-agent-reviewed.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
# The gh stub runs the --jq program over $GHS_COMMENTS, as gh would over the
# API's answer; $GHS_FAIL makes the read fail the way an API error does.
cat >"$tmp/bin/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$GHS_LOG"
[ -z "${GHS_FAIL:-}" ] || { echo '{"message":"Bad credentials"}'; exit 1; }
filter=''
while [ "$#" -gt 0 ]; do
  [ "$1" != --jq ] || filter=$2
  shift
done
jq -r "$filter" "$GHS_COMMENTS"
STUB
chmod +x "$tmp/bin/gh"

H=1111111111111111111111111111111111111111
OTHER=2222222222222222222222222222222222222222
marker() { # marker <login> <head> <status>
  printf '{"user":{"login":"%s"},"body":"<!-- pr-agent-run: id=4475.1 head=%s status=%s -->\\nPR-Agent run 4475 reviewed: %s."}' "$1" "$2" "$3" "$3"
}
human() { printf '{"user":{"login":"alice"},"body":"looks fine"}'; }

run() { # run <comments json> [args...]
  printf '%s\n' "$1" >"$tmp/comments.json"
  shift
  : >"$tmp/out"
  : >"$tmp/log"
  OUT=$(env PATH="$tmp/bin:$PATH" GHS_COMMENTS="$tmp/comments.json" GHS_LOG="$tmp/log" \
    GITHUB_REPOSITORY=acme/widgets GITHUB_OUTPUT="$tmp/out" GHS_FAIL="${GHS_FAIL:-}" \
    /bin/bash "$SCRIPT" "$@" 2>&1)
  CODE=$?
}
want() { # want <label> <reviewed value>
  if [ "$CODE" = 0 ] && [ "$(cat "$tmp/out")" = "reviewed=$2" ]; then
    ok "$1"
  else
    fail "$1 (exit $CODE, output '$(cat "$tmp/out")'): $OUT"
  fi
}

run "[]" --pr 42 --head "$H"
want "a pull request with no run marker is reviewed" false
run "[$(human)]" --pr 42 --head "$H"
want "a comment that is no marker counts for nothing" false
run "[$(marker 'github-actions[bot]' "$H" success)]" --pr 42 --head "$H"
want "a head the workflow already reviewed successfully is not reviewed again" true
case $OUT in *'::notice title=PR-Agent already reviewed this head::'*) ok "the skip is announced" ;; *) fail "the skip is not announced: $OUT" ;; esac
if grep -q 'repos/acme/widgets/issues/42/comments' "$tmp/log"; then ok "the pull request's own comments are read"; else fail "the comment read: $(cat "$tmp/log")"; fi
run "[$(marker 'github-actions[bot]' "$OTHER" success)]" --pr 42 --head "$H"
want "a marker for an older head leaves the new head to review" false
run "[$(marker 'github-actions[bot]' "$H" failure)]" --pr 42 --head "$H"
want "a failed run at the head is reviewed again" false
run "[$(marker 'github-actions[bot]' "$H" cancelled)]" --pr 42 --head "$H"
want "a cancelled run at the head is reviewed again" false
run "[$(marker alice "$H" success)]" --pr 42 --head "$H"
want "a marker a person wrote never stands in for the workflow's" false
run "[$(marker 'github-actions[bot]' "$H" success), $(marker 'github-actions[bot]' "$OTHER" success)]" --pr 42 --head "$H"
want "the newest of the workflow's markers decides" false
run "[$(marker 'github-actions[bot]' "$OTHER" success), $(marker 'github-actions[bot]' "$H" success)]" --pr 42 --head "$H"
want "and decides the other way round too" true
GHS_FAIL=1 run "[$(marker 'github-actions[bot]' "$H" success)]" --pr 42 --head "$H"
want "a failed read reviews the head rather than skip it" false
case $OUT in *'::warning'*) ok "the failed read is named" ;; *) fail "the failed read is silent: $OUT" ;; esac

run "[]" --pr 42 --head abc
if [ "$CODE" = 2 ]; then ok "a head that is no full commit is a usage error"; else fail "a short head exits $CODE"; fi
run "[]" --pr x --head "$H"
if [ "$CODE" = 2 ]; then ok "a pull request that is no number is a usage error"; else fail "a bad --pr exits $CODE"; fi

if [ "$failures" -ne 0 ]; then
  echo "test-pr-agent-reviewed: $failures failure(s)" >&2
  exit 1
fi
echo "test-pr-agent-reviewed: all passed"
