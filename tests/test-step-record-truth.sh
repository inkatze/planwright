#!/bin/sh
# Tests for the step-record truth check in scripts/step-record.sh: write refuses
# a skill or prompt record that overstates what happened (a window under the
# floor, an in-session step with a backend, a start made up from the clock or
# round minutes, an outcome that disagrees with the heads), stores an honest
# record unchanged, and the untrue verb names the stored records it would refuse.
#
# Runs standalone under /bin/sh:
#   ./tests/test-step-record-truth.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
SR="$repo_root/scripts/step-record.sh"
TAB=$(printf '\t')
PLANWRIGHT_SECRET_SCREEN_TOOL=none
export PLANWRIGHT_SECRET_SCREEN_TOOL

failures=0
fail() {
  printf '%s\n' "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { printf '%s\n' "ok: $1"; }
# verdict <ok message> <fail message>: judged on the status of the command before it.
verdict() {
  if [ $? -eq 0 ]; then ok "$1"; else fail "$2"; fi
}

tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-step-record-truth.XXXXXX")" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

wt="$tmp/wt"
mkdir -p "$wt"
git -C "$wt" init -q -b main
git -C "$wt" config user.name Fixture
git -C "$wt" config user.email fixture@example.invalid
git -C "$wt" config commit.gpgsign false
printf 'base\n' >"$wt/file.txt"
git -C "$wt" add file.txt
git -C "$wt" commit -q -m "chore: base"
H1=$(git -C "$wt" rev-parse HEAD)
printf 'two\n' >>"$wt/file.txt"
git -C "$wt" commit -q -a -m "chore: two"
H2=$(git -C "$wt" rev-parse HEAD)
CT=$(git -C "$wt" log -1 --format=%ct "$H2")

sr() { "$SR" --worktree "$wt" "$@"; }
run=$(sr new-run)
records() { find "$wt/.claude/steps/$run" -name '*-step-*.rec' | wc -l | tr -d ' '; }

# A record no rule objects to: a real window, a start off the round minute.
START=2026-11-01T10:03:17Z
END=2026-11-01T10:09:41Z

# wr <flags>: a polish skill record write, every other flag given by the caller.
wr() {
  sr write --run "$run" --point convergence --step polish --kind skill --target polish "$@"
}
# refuses_full <label> <rule id> <flag> <write flags...>: exit 2 naming the flag and
# the rule, and no record stored.
refuses_full() {
  label=$1 rule=$2 flag=$3
  shift 3
  before=$(records)
  err=$(wr "$@" 2>&1 >/dev/null)
  rc=$?
  after=$(records)
  if [ "$rc" -eq 2 ] && printf '%s' "$err" | grep -q -- "$flag" \
    && printf '%s' "$err" | grep -q "step-record truth check, rule $rule" && [ "$before" = "$after" ]; then
    ok "the truth check refuses $label"
  else
    fail "$label: rc=$rc before=$before after=$after err=$err"
  fi
}

# Shapes the hub denied by hand.
refuses_full "an in-session skill recorded with an adopter backend" hosting-backend --backend \
  --hosting in-session --backend adopter --head "$H1" --end-head "$H1" --start "$START" --end "$END" --outcome passed
refuses_full "a window of seconds on a skill that passed" window-floor --start \
  --hosting in-session --backend in-session --head "$H1" --end-head "$H1" \
  --start 2026-11-01T10:03:17Z --end 2026-11-01T10:03:21Z --outcome passed
refuses_full "a start that is the clock at writing" start-from-clock --start \
  --kind prompt --hosting in-session --backend in-session --head "$H1" --end-head "$H1" --start "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --outcome passed
refuses_full "a window of whole minutes" window-round-minutes --start \
  --hosting in-session --backend in-session --head "$H1" --end-head "$H1" \
  --start 2026-11-01T10:03:17Z --end 2026-11-01T10:08:17Z --outcome passed
refuses_full "a start on seconds :00" start-round-minute --start \
  --hosting in-session --backend in-session --head "$H1" --end-head "$H1" \
  --start 2026-11-01T10:03:00Z --end 2026-11-01T10:09:41Z --outcome passed
refuses_full "passed over a moved head" outcome-heads --outcome \
  --hosting in-session --backend in-session --head "$H1" --end-head "$H2" --start "$START" --end "$END" --outcome passed
refuses_full "applied over an unmoved head" outcome-heads --outcome \
  --hosting in-session --backend in-session --head "$H1" --end-head "$H1" --start "$START" --end "$END" --outcome applied
refuses_full "a prompt step on seconds :00 as well" start-round-minute --start \
  --kind prompt --hosting in-session --backend in-session --head "$H1" --end-head "$H1" \
  --start 2026-11-01T10:03:00Z --end 2026-11-01T10:09:41Z --outcome passed

# An honest record is stored, its values unchanged.
path=$(wr --hosting in-session --backend in-session --head "$H1" --end-head "$H1" \
  --start "$START" --end "$END" --outcome passed) && [ -f "$path" ] \
  && grep -qx "start${TAB}$START" "$path" && grep -qx "end${TAB}$END" "$path" \
  && grep -qx "backend${TAB}in-session" "$path" && grep -qx "outcome${TAB}passed" "$path"
verdict "an honest record is stored with its values unchanged" "the honest record was refused or altered"

# Applied over a moved head passes; the point differs so the first stays done.
path=$(sr write --run "$run" --point pre-pr --step polish --kind skill --target polish \
  --hosting in-session --backend in-session --head "$H1" --end-head "$H2" \
  --start "$START" --end "$END" --outcome applied) && [ -f "$path" ]
verdict "applied over a moved head is stored" "applied over a moved head was refused"

# A start source lifts the made-up-start signs; a commit source is verified.
SRC_END=$(date -u -d "@$((CT + 400))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$((CT + 400))" +%Y-%m-%dT%H:%M:%SZ)
CT_TS=$(date -u -d "@$CT" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$CT" +%Y-%m-%dT%H:%M:%SZ)
path=$(sr write --run "$run" --point post-pr --step polish --kind skill --target polish \
  --hosting in-session --backend in-session --head "$H1" --end-head "$H1" \
  --start "$CT_TS" --end "$SRC_END" --start-source "commit:$H2" --outcome passed) \
  && grep -qx "start-source${TAB}commit:$H2" "$path"
verdict "a verified commit source is stored and lifts the start rules" "the commit source was refused or not stored"
err=$(sr write --run "$run" --point pre-ci --step polish --kind skill --target polish \
  --hosting in-session --backend in-session --head "$H1" --end-head "$H1" \
  --start 2026-11-01T10:03:17Z --end "$END" --start-source "commit:$H2" --outcome passed 2>&1 >/dev/null)
if [ $? -eq 2 ] && printf '%s' "$err" | grep -q -- '--start-source'; then ok "a commit source whose time is not --start is refused"; else fail "a mismatched commit source passed: $err"; fi

# A start a whole number of minutes before the clock (inside the hour) is
# refused; the clock is read by write itself, so a second ticking between this
# test's read and the write's is retried.
seen=0
for i in 1 2 3 4 5; do
  nowe=$(date -u +%s)
  recent=$(date -u -d "@$((nowe - 600))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$((nowe - 600))" +%Y-%m-%dT%H:%M:%SZ)
  case $recent in *:00Z) continue ;; esac
  err=$(sr write --run "$run" --point "pre-pr" --step "clockmin$i" --kind prompt --target x \
    --hosting in-session --backend in-session --head "$H1" --end-head "$H1" --start "$recent" --outcome passed 2>&1 >/dev/null)
  if printf '%s' "$err" | grep -q "rule start-round-minutes"; then
    seen=1
    break
  fi
done
[ "$seen" -eq 1 ]
verdict "a start a whole number of minutes before the clock is refused" "no start-round-minutes refusal in five tries: $err"

# A start source lifts the made-up-start rules: a whole-minute window and a :00
# start pass with a forge source, and are refused without one.
refuses_full "a round start and window with no source" window-round-minutes --start \
  --hosting in-session --backend in-session --head "$H1" --end-head "$H1" \
  --start 2026-11-01T10:03:00Z --end 2026-11-01T10:08:00Z --outcome passed
path=$(wr --hosting in-session --backend in-session --head "$H1" --end-head "$H1" \
  --start 2026-11-01T10:03:00Z --end 2026-11-01T10:08:00Z --start-source comment:4242 --outcome passed) \
  && grep -qx "start-source${TAB}comment:4242" "$path"
verdict "a forge source lifts the made-up-start rules and is stored" "the forge source was refused or not stored"
for bad in comment:12x commit:abc review: stamp; do
  err=$(wr --hosting in-session --backend in-session --head "$H1" --end-head "$H1" \
    --start "$START" --end "$END" --start-source "$bad" --outcome passed 2>&1 >/dev/null)
  [ $? -eq 2 ] && printf '%s' "$err" | grep -q -- '--start-source'
  verdict "a start source outside the grammar ($bad) is refused" "start source $bad: $err"
done

# The window floor: 29 seconds is refused, 30 passes; an applied skill is held to it.
refuses_full "an applied skill under the floor" window-floor --start \
  --hosting in-session --backend in-session --head "$H1" --end-head "$H2" \
  --start 2026-11-01T10:03:17Z --end 2026-11-01T10:03:46Z --outcome applied
wr --hosting in-session --backend in-session --head "$H1" --end-head "$H1" \
  --start 2026-11-01T10:03:17Z --end 2026-11-01T10:03:47Z --outcome passed >/dev/null
verdict "a window of exactly the floor passes" "a 30 second window was refused"

# A step that failed or halted claims no work: the start and floor rules leave
# it, so a fast honest failure can be recorded.
sr write --run "$run" --point pre-ci --step fastfail --kind skill --target x \
  --hosting in-session --backend in-session --head "$H1" --end-head "$H1" \
  --start 2026-11-01T10:03:00Z --end 2026-11-01T10:03:00Z --outcome failed >/dev/null
verdict "a failed skill over a zero window is stored" "a failed record was refused"
err=$(sr write --run "$run" --point pre-ci --step fastfail2 --kind skill --target x \
  --hosting in-session --backend adopter --head "$H1" --end-head "$H1" \
  --start 2026-11-01T10:03:17Z --end 2026-11-01T10:04:29Z --outcome failed 2>&1 >/dev/null)
[ $? -eq 2 ] && printf '%s' "$err" | grep -q "rule hosting-backend"
verdict "a failed in-session record with a backend is still refused" "hosting-backend skipped a failed record: $err"

# Command records and skipped records are outside the check.
sr write --run "$run" --point pre-ci --step lint --kind command --target lint \
  --hosting in-session --backend runner --head "$H1" --end-head "$H2" \
  --start 2026-11-01T10:03:00Z --end 2026-11-01T10:04:00Z --outcome passed >/dev/null
verdict "a command record is never judged" "a command record was refused"
sr write --run "$run" --point pre-ci --step polish --kind skill --target polish \
  --hosting in-session --backend adopter --head "$H1" --end-head "$H1" \
  --start 2026-11-01T10:03:00Z --end 2026-11-01T10:04:00Z --outcome skipped --skip-code missing >/dev/null
verdict "a skipped record is never judged" "a skipped record was refused"

# untrue names a stored record the check would refuse, and only that one.
run2=$(sr new-run)
sr write --run "$run2" --point convergence --step honest --kind skill --target honest \
  --hosting in-session --backend in-session --head "$H1" --end-head "$H1" \
  --start "$START" --end "$END" --outcome passed >/dev/null
bad=$(sr write --run "$run2" --point convergence --step fabricated --kind command --target x \
  --hosting isolated --backend runner --head "$H1" --end-head "$H1" \
  --start "$START" --end "$END" --outcome passed)
# Rewrite the stored record into a skill one the way a pre-check cache holds it.
sed -e "s/^kind${TAB}command/kind${TAB}skill/" -e "s/^end${TAB}.*/end${TAB}2026-11-01T10:03:21Z/" "$bad" >"$bad.new" && mv "$bad.new" "$bad"
out=$(sr untrue)
if printf '%s\n' "$out" | grep -q "^$run2:convergence:002${TAB}fabricated${TAB}--start${TAB}window-floor$" \
  && ! printf '%s\n' "$out" | grep -q "honest"; then
  ok "untrue names the fabricated stored record and not the honest one"
else
  fail "untrue printed: $out"
fi

# A stored record is judged on a :00 start with a whole-minute window together,
# not on either alone, so an honest one-in-sixty record stays audited.
run3=$(sr new-run)
r1=$(sr write --run "$run3" --point convergence --step lone --kind skill --target x \
  --hosting in-session --backend in-session --head "$H1" --end-head "$H1" \
  --start 2026-11-01T10:03:00Z --end 2026-11-01T10:03:41Z --outcome passed --start-source comment:7)
sed -e "/^start-source${TAB}/d" "$r1" >"$r1.new" && mv "$r1.new" "$r1"
out=$(sr untrue)
! printf '%s\n' "$out" | grep -q "$run3"
verdict "untrue leaves a stored record with only a :00 start" "untrue flagged: $out"
r2=$(sr write --run "$run3" --point pre-ci --step both --kind skill --target x \
  --hosting in-session --backend in-session --head "$H1" --end-head "$H1" \
  --start 2026-11-01T10:03:00Z --end 2026-11-01T10:08:00Z --outcome passed --start-source comment:7)
sed -e "/^start-source${TAB}/d" "$r2" >"$r2.new" && mv "$r2.new" "$r2"
out=$(sr untrue)
printf '%s\n' "$out" | grep -q "^$run3:pre-ci:002${TAB}both${TAB}--start${TAB}window-round-minutes$"
verdict "untrue names a stored record with a :00 start and a whole-minute window" "untrue printed: $out"
sed -e "s/^start${TAB}.*/start${TAB}garbage/" "$r2" >"$r2.new" && mv "$r2.new" "$r2"
out=$(sr untrue)
printf '%s\n' "$out" | grep -q "^$run3:pre-ci:002${TAB}both${TAB}--start${TAB}malformed-times$"
verdict "untrue names a stored record whose times are not timestamps" "untrue printed: $out"

if [ "$failures" -gt 0 ]; then
  printf '%s\n' "$failures failure(s)" >&2
  exit 1
fi
echo "all step-record truth-check tests passed"
