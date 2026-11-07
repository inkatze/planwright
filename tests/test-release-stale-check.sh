#!/bin/bash
# Tests for scripts/release-stale-check.sh, the escalation for a merged release
# PR still labelled `autorelease: pending` past the bound.
#
# Contract under test:
#   - no merged pending PR -> exit 0, silent;
#   - a merged pending PR younger than the bound -> exit 0, silent;
#   - one older than the bound -> exit 1, naming the PR and the publish command;
#   - --max-age-minutes moves the bound;
#   - the query asks for merged PRs carrying the pending label;
#   - gh failing, or unparseable gh output -> exit 2 (never 0);
#   - a malformed flag value -> exit 2.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
CHECK="$here/../scripts/release-stale-check.sh"
failures=0

[ -x "$CHECK" ] || {
  echo "FAIL: scripts/release-stale-check.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
mkdir -p "$stub"
# The stub prints $GH_OUT as the PR list (or fails when GH_FAIL=1) and logs its
# argv, one argument per line, to $GH_LOG.
cat >"$stub/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$GH_LOG"
[ "${GH_FAIL:-0}" = 1 ] && exit 1
printf '%s' "$GH_OUT"
EOF
chmod +x "$stub/gh"

# 2026-11-07T18:50:56Z
MERGED=1794077456
MERGED_ISO="2026-11-07T18:50:56Z"
ONE_PR="[{\"number\":872,\"title\":\"chore: release 0.69.0\",\"mergedAt\":\"$MERGED_ISO\"}]"
LOG="$tmp/gh.log"

# run <gh-out> <gh-fail> <args...>: sets OUT and RC.
run() {
  out="$1"
  fail="$2"
  shift 2
  RC=0
  OUT=$(env PATH="$stub:$PATH" GH_OUT="$out" GH_FAIL="$fail" GH_LOG="$LOG" \
    "$CHECK" "$@" 2>&1) || RC=$?
}

expect() {
  name="$1"
  want_rc="$2"
  want_text="$3"
  if [ "$RC" != "$want_rc" ]; then
    echo "FAIL: $name: exit $RC, want $want_rc; output: $OUT" >&2
    failures=$((failures + 1))
    return
  fi
  if [ -n "$want_text" ]; then
    case "$OUT" in
      *"$want_text"*) ;;
      *)
        echo "FAIL: $name: output lacks '$want_text': $OUT" >&2
        failures=$((failures + 1))
        return
        ;;
    esac
  elif [ -n "$OUT" ]; then
    echo "FAIL: $name: expected silence, got: $OUT" >&2
    failures=$((failures + 1))
    return
  fi
  echo "ok: $name"
}

run '[]' 0 --now $((MERGED + 86400))
expect "no merged pending PR is silent" 0 ""

run "$ONE_PR" 0 --now $((MERGED + 3600))
expect "a PR inside the default bound is silent" 0 ""

run "$ONE_PR" 0 --now $((MERGED + 3 * 3600))
expect "a PR past the default bound escalates" 1 "#872 chore: release 0.69.0 merged $MERGED_ISO, 180 minutes ago"
expect "the escalation names the publish command" 1 "scripts/release-publish.sh"

run "$ONE_PR" 0 --max-age-minutes 360 --now $((MERGED + 3 * 3600))
expect "--max-age-minutes widens the bound" 0 ""

run "$ONE_PR" 0 --max-age-minutes 0 --now $((MERGED + 60))
expect "--max-age-minutes 0 escalates at once" 1 "#872"

ESC=$(printf '\033')
run "[{\"number\":9,\"title\":\"evil\\u001b[2Jtitle\",\"mergedAt\":\"$MERGED_ISO\"}]" 0 --now $((MERGED + 3 * 3600))
case "$OUT" in
  *"$ESC"*)
    echo "FAIL: a control byte in a PR title reached the output" >&2
    failures=$((failures + 1))
    ;;
  *) expect "a PR title's control bytes are stripped" 1 "#9 evil[2Jtitle" ;;
esac

CSI8=$(printf '\302\233')
run "[{\"number\":9,\"title\":\"evil\\u009b[2Jtitle\",\"mergedAt\":\"$MERGED_ISO\"}]" 0 --now $((MERGED + 3 * 3600))
case "$OUT" in
  *"$CSI8"*)
    echo "FAIL: a C1 control (U+009B) in a PR title reached the output" >&2
    failures=$((failures + 1))
    ;;
  *) expect "a PR title's C1 controls are stripped" 1 "#9 evil[2Jtitle" ;;
esac

run '' 0 --now $((MERGED + 3 * 3600))
expect "an empty gh body is could-not-determine" 2 "release state unknown"

run '{}' 0 --now $((MERGED + 3 * 3600))
expect "a non-array gh body is could-not-determine" 2 "release state unknown"

run '[{"number":5,"title":"t","mergedAt":null}]' 0 --now $((MERGED + 3 * 3600))
expect "a merged PR without a merge time is could-not-determine" 2 "release state unknown"

if grep -qx -- '--state' "$LOG" && grep -qx merged "$LOG" \
  && grep -qx -- '--label' "$LOG" && grep -qx 'autorelease: pending' "$LOG"; then
  echo "ok: the query asks for merged PRs labelled autorelease: pending"
else
  echo "FAIL: gh was not asked for merged pending PRs: $(tr '\n' ' ' <"$LOG")" >&2
  failures=$((failures + 1))
fi

run "$ONE_PR" 1 --now $((MERGED + 3 * 3600))
expect "gh failing is could-not-determine" 2 "release state unknown"

run 'not json' 0 --now $((MERGED + 3 * 3600))
expect "unparseable gh output is could-not-determine" 2 "release state unknown"

run "$ONE_PR" 0 --max-age-minutes two
expect "a malformed bound is a usage error" 2 "usage"

# jq rejects a leading zero as JSON, which would misreport as unreadable state.
run "$ONE_PR" 0 --max-age-minutes 090
expect "a zero-padded bound is a usage error" 2 "usage"

run "$ONE_PR" 0 --now
expect "a flag without its value is a usage error" 2 "usage"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all release-stale-check tests passed"
