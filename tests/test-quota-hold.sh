#!/bin/bash
# Tests for scripts/quota-hold.sh, the per-vendor hold store and usage ledger
# (quota-handling REQ-B1.1, REQ-B1.3, REQ-B1.5, REQ-E1.1, REQ-E1.2), and the
# vendor view it feeds into scripts/fleet-stats.sh render.
#
# Covered:
#   - two units holding one vendor concurrently both land as holders, with a
#     ledger line each (the lock library serializes the writers);
#   - a hold pushes one attention event naming the vendor, the reason, the
#     stated reset time, and the operator's resume command;
#   - resume releases every holder and records the resume;
#   - prune drops ledger lines older than the retention knob (90 days when
#     unset) and keeps the rest byte for byte;
#   - status renders hold state and per-event counts over the retention period,
#     and fleet-stats.sh render shows the same through its vendor view;
#   - hostile vendor, unit, step, and recognizer ids, PR numbers, heads, and
#     reset times are refused before any path or ledger use;
#   - a forged ledger or hold line (an embedded newline in a reason) is skipped
#     on read, and a reason given with a newline is stored flattened;
#   - the default fleet home resolves outside the repository's tracked tree.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-quota-hold.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH
# Every reason goes through the secret screen; the real scanner costs seconds a
# call and is covered by the screen's own tests.
PLANWRIGHT_SECRET_SCREEN_TOOL=none
export PLANWRIGHT_SECRET_SCREEN_TOOL

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
QH="$repo_root/scripts/quota-hold.sh"
FSTATS="$repo_root/scripts/fleet-stats.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
pass() {
  echo "ok: $1"
}

[ -x "$QH" ] || fail "scripts/quota-hold.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/fleet-home.sh
. "$here/lib/fleet-home.sh"

core_cfg="$tmp/core-defaults.yml"
repo="$tmp/repo"
adopter_root="$tmp/adopter"
mkdir -p "$repo/.claude" "$adopter_root"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$repo"
printf 'notification_channel: push\nquota_ledger_retention_days: 90\n' >"$core_cfg"
local_cfg="$tmp/local.yml"
: >"$local_cfg"

home=""
new_home() {
  home="$tmp/home-$1"
  fleet_home_pin "$home" || fail "cannot pin the fleet home for $1"
}

run() {
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$QH" "$@"
}

# The clock every fixture pins, and a reset time an hour after it.
NOW=1800000000
RESET=$((NOW + 3600))
DAY=86400
HEAD40=0123456789abcdef0123456789abcdef01234567

ledger() { printf '%s' "$home/fleet/quota/$1/ledger.tsv"; }
holdfile() { printf '%s' "$home/fleet/quota/$1/hold.tsv"; }

# --- 1. Concurrent holds on one vendor from two units -----------------------
new_home concurrent
pids=""
units="spec-a:task-1 spec-b:task-2 spec-c:task-3 spec-d:task-4 spec-e:task-5 spec-f:task-6
spec-g:task-7 spec-h:task-8 spec-i:task-9 spec-j:task-10 spec-k:task-11 spec-l:task-12"
for u in $units; do
  run hold --vendor sample-reviewer --unit "$u" --step bot-review \
    --reason "review quota used up" --reset "$RESET" --now "$NOW" \
    >"$tmp/out-$u" 2>"$tmp/err-$u" &
  pids="$pids $!"
done
for p in $pids; do
  wait "$p" || fail "a concurrent hold exited non-zero ($(cat "$tmp"/err-* | head -n 3))"
done
status=$(run status --vendor sample-reviewer --now "$NOW")
holders=$(printf '%s\n' "$status" | grep -c "^holder${TAB}sample-reviewer${TAB}" || :)
[ "$holders" = 12 ] || fail "concurrent holds: expected 12 holders, got $holders: $status"
holds=$(grep -c "${TAB}hold${TAB}" "$(ledger sample-reviewer)" || :)
[ "$holds" = 12 ] || fail "concurrent holds: expected 12 hold ledger lines, got $holds"
printf '%s\n' "$status" | grep -q "^vendor${TAB}sample-reviewer${TAB}held${TAB}${NOW}${TAB}${RESET}${TAB}12${TAB}review quota used up$" \
  || fail "status: the vendor line does not read held since $NOW, reset $RESET, 12 units: $status"
pass "concurrent holds from several units all land under the vendor lock"

# A unit holding again is renewed in place, never listed twice, and keeps the
# time it first held.
run hold --vendor sample-reviewer --unit spec-a:task-1 --step bot-review \
  --reason "still refused" --now $((NOW + 60)) >/dev/null 2>&1 || fail "a renewed hold exited non-zero"
status=$(run status --vendor sample-reviewer --now $((NOW + 60)))
n=$(printf '%s\n' "$status" | grep -c "^holder${TAB}sample-reviewer${TAB}spec-a:task-1${TAB}" || :)
[ "$n" = 1 ] || fail "renewal: the unit is listed $n times"
printf '%s\n' "$status" | grep -q "^holder${TAB}sample-reviewer${TAB}spec-a:task-1${TAB}bot-review${TAB}${NOW}$" \
  || fail "renewal: the unit lost the time it first held: $status"
pass "a renewed hold updates the unit in place"

# --- 2. A hold pushes its event --------------------------------------------
push_dir="$home/fleet/attention/push"
markers=$(find "$push_dir" -type f 2>/dev/null | wc -l | tr -d ' ')
[ "$markers" = 1 ] || fail "push: expected one deduplicated marker for one vendor hold, got $markers"
marker=$(cat "$push_dir"/*)
case $marker in
  *sample-reviewer*) ;;
  *) fail "push: the event does not name the vendor: $marker" ;;
esac
case $marker in
  *"review quota used up"*) ;;
  *) fail "push: the event does not carry the reason: $marker" ;;
esac
case $marker in
  *"2027-01-15T09:00:00Z"*) ;;
  *) fail "push: the event does not state the reset time: $marker" ;;
esac
case $marker in
  *"scripts/quota-hold.sh resume --vendor sample-reviewer"*) ;;
  *) fail "push: the event does not name the resume command: $marker" ;;
esac
pass "a hold pushes one event naming the vendor, reason, reset time, and resume command"

new_home noreset
run hold --vendor sample-cli --unit spec-a:task-1 --step panel \
  --reason "monthly allowance exhausted" --now "$NOW" >/dev/null 2>&1 || fail "hold without a reset exited non-zero"
marker=$(cat "$home/fleet/attention/push"/* 2>/dev/null) || fail "push: a hold with no stated reset pushed nothing"
case $marker in
  *"no stated reset"*) ;;
  *) fail "push: a hold with no stated reset does not say so: $marker" ;;
esac
pass "a hold with no stated reset time says so in its event"

# A writer waits on the vendor's lock: with a live process holding it, the
# hold lands nothing until that process is gone.
new_home locked
vdir="$home/fleet/quota/sample-reviewer"
mkdir -p "$vdir"
sleep 120 &
holder_pid=$!
ln -s "$holder_pid-0-1" "$vdir/lock"
run hold --vendor sample-reviewer --unit spec-a:task-1 --step bot-review \
  --reason "quota" --now "$NOW" >/dev/null 2>"$tmp/locked-err" &
writer_pid=$!
sleep 2
if [ -e "$vdir/hold.tsv" ] || [ -e "$vdir/ledger.tsv" ]; then
  kill "$holder_pid" 2>/dev/null || :
  fail "lock: a hold wrote while another process held the vendor's lock"
fi
kill "$holder_pid"
wait "$holder_pid" 2>/dev/null || :
wait "$writer_pid" || fail "lock: the waiting hold failed once the holder was gone ($(cat "$tmp/locked-err"))"
grep -q "${TAB}spec-a:task-1${TAB}" "$vdir/hold.tsv" || fail "lock: the waiting hold never landed"
pass "a hold waits on the vendor's lock"

# --- 3. Resume releases every holder ---------------------------------------
new_home resume
for u in spec-a:task-1 spec-b:task-2; do
  run hold --vendor sample-reviewer --unit "$u" --step bot-review \
    --reason "quota" --now "$NOW" >/dev/null 2>&1 || fail "hold for $u failed"
done
released=$(run resume --vendor sample-reviewer --now $((NOW + 10))) || fail "resume exited non-zero"
printf '%s\n' "$released" | grep -q "^released${TAB}spec-a:task-1${TAB}bot-review$" || fail "resume: spec-a not released: $released"
printf '%s\n' "$released" | grep -q "^released${TAB}spec-b:task-2${TAB}bot-review$" || fail "resume: spec-b not released: $released"
status=$(run status --vendor sample-reviewer --now $((NOW + 10)))
printf '%s\n' "$status" | grep -q "^vendor${TAB}sample-reviewer${TAB}clear${TAB}" || fail "resume: vendor still held: $status"
! printf '%s\n' "$status" | grep -q "^holder${TAB}" || fail "resume: a holder survived the release: $status"
grep -q "^$((NOW + 10))${TAB}resume${TAB}" "$(ledger sample-reviewer)" || fail "resume: no resume line in the ledger"
again=$(run resume --vendor sample-reviewer --now $((NOW + 20))) || fail "resume of a clear vendor exited non-zero"
[ -z "$again" ] || fail "resume of a clear vendor released something: $again"
[ "$(grep -c "${TAB}resume${TAB}" "$(ledger sample-reviewer)")" = 1 ] || fail "resume of a clear vendor wrote a ledger line"
pass "resume releases every holder once and records it"

# A ledger write that fails leaves the hold store as it was: a hold that exits
# 6 held nothing, and a resume that exits 6 released nothing.
new_home ledger-fails
vdir="$home/fleet/quota/sample-reviewer"
mkdir -p "$vdir/ledger.tsv"
rc=0
run hold --vendor sample-reviewer --unit spec-a:task-1 --step bot-review --reason "quota" --now "$NOW" >/dev/null 2>&1 || rc=$?
[ "$rc" = 6 ] || fail "ledger-fails: a hold whose ledger append failed exited $rc, not 6"
[ ! -s "$vdir/hold.tsv" ] || fail "ledger-fails: a hold that exited 6 left a holder: $(cat "$vdir/hold.tsv")"
rmdir "$vdir/ledger.tsv"
run hold --vendor sample-reviewer --unit spec-a:task-1 --step bot-review --reason "quota" --now "$NOW" >/dev/null 2>&1 || fail "ledger-fails: the hold failed once the ledger was writable"
rm -f "$vdir/ledger.tsv"
mkdir "$vdir/ledger.tsv"
rc=0
run resume --vendor sample-reviewer --now "$NOW" >/dev/null 2>&1 || rc=$?
[ "$rc" = 6 ] || fail "ledger-fails: a resume whose ledger append failed exited $rc, not 6"
grep -q "${TAB}spec-a:task-1${TAB}" "$vdir/hold.tsv" || fail "ledger-fails: a resume that exited 6 released its holders"
pass "a failed ledger write leaves the hold store unchanged"

new_home hold-not-file
vdir="$home/fleet/quota/sample-reviewer"
mkdir -p "$vdir/hold.tsv"
rc=0
out=$(run hold --vendor sample-reviewer --unit spec-a:task-1 --step bot-review --reason "quota" --now "$NOW" 2>/dev/null) || rc=$?
[ "$rc" = 6 ] || fail "hold-not-file: a hold over a hold store that is a directory exited $rc, not 6 ($out)"
[ -z "$out" ] || fail "hold-not-file: a refused hold printed $out"
[ -z "$(ls -A "$vdir/hold.tsv")" ] || fail "hold-not-file: the hold wrote inside the directory"
pass "a hold store that is not a regular file is refused"

# --- 4. The ledger, its counts, and retention pruning -----------------------
new_home ledger
run record --vendor sample-reviewer --event request --unit spec-a:task-1 --pr 42 --head "$HEAD40" --now $((NOW - 100 * DAY)) || fail "record request (old) failed"
run record --vendor sample-reviewer --event request --unit spec-a:task-1 --pr 42 --head "$HEAD40" --now $((NOW - 10)) || fail "record request failed"
run record --vendor sample-reviewer --event answer --pr 42 --head "$HEAD40" --now $((NOW - 5)) || fail "record answer failed"
run record --vendor sample-reviewer --event refusal --pr 42 --head "$HEAD40" --recognizer sample-reviewer.quota --reason "quota used up" --now $((NOW - 4)) || fail "record refusal failed"
run hold --vendor sample-reviewer --unit spec-a:task-1 --step bot-review --reason "quota used up" --recognizer sample-reviewer.quota --pr 42 --head "$HEAD40" --now $((NOW - 3)) >/dev/null 2>&1 || fail "hold failed"
run resume --vendor sample-reviewer --now $((NOW - 2)) >/dev/null || fail "resume failed"
status=$(run status --vendor sample-reviewer --now "$NOW")
for pair in request:1 answer:1 refusal:1 hold:1 resume:1; do
  ev=${pair%%:*}
  want=${pair#*:}
  printf '%s\n' "$status" | grep -q "^count${TAB}sample-reviewer${TAB}${ev}${TAB}${want}$" \
    || fail "status counts: expected $ev $want over the retention period: $status"
done
printf '%s\n' "$status" | grep -q "^retention${TAB}90$" || fail "status: the default retention is not 90 days: $status"
pass "status counts each event over the retention period (90 days by default)"

lf=$(ledger sample-reviewer)
tail -n +2 "$lf" >"$tmp/kept"
run prune --now "$NOW" || fail "prune exited non-zero"
cmp -s "$lf" "$tmp/kept" || fail "prune: the lines inside retention were not kept byte for byte"
pass "prune drops lines past retention and keeps the rest byte for byte"

printf 'quota_ledger_retention_days: 1\n' >"$local_cfg"
run prune --now "$NOW" || fail "prune with a 1-day retention exited non-zero"
[ "$(wc -l <"$lf" | tr -d ' ')" = 5 ] || fail "prune: a 1-day retention dropped lines from the last minute"
run prune --now $((NOW + 2 * DAY)) || fail "prune past the window exited non-zero"
[ ! -s "$lf" ] || fail "prune: lines older than a 1-day retention survived: $(cat "$lf")"
: >"$local_cfg"
pass "the retention knob governs pruning"

# --- 5. Hostile input is refused before any path or ledger use --------------
new_home hostile
refuse() {
  label=$1
  shift
  rc=0
  run "$@" >/dev/null 2>"$tmp/hostile-err" || rc=$?
  [ "$rc" = 2 ] || fail "hostile $label: expected exit 2, got $rc"
  if [ -d "$home/fleet/quota" ] && [ -n "$(ls -A "$home/fleet/quota")" ]; then
    fail "hostile $label: something was written under the store: $(ls -AR "$home/fleet/quota")"
  fi
  if [ -e "$tmp/escape" ]; then
    fail "hostile $label: a path escaped the store"
  fi
}
nl='
'
refuse "vendor traversal" hold --vendor ../../escape --unit u1 --step s --reason r --now "$NOW"
refuse "vendor uppercase" hold --vendor Sample --unit u1 --step s --reason r --now "$NOW"
refuse "vendor empty" status --vendor ""
refuse "unit slash" hold --vendor v --unit "a/b" --step s --reason r --now "$NOW"
refuse "unit dot-dot" hold --vendor v --unit .. --step s --reason r --now "$NOW"
refuse "unit newline" hold --vendor v --unit "u${nl}x" --step s --reason r --now "$NOW"
refuse "step grammar" hold --vendor v --unit u1 --step "Bad Step" --reason r --now "$NOW"
refuse "recognizer grammar" hold --vendor v --unit u1 --step s --reason r --recognizer "v;rm" --now "$NOW"
refuse "recognizer no name" record --vendor v --event refusal --recognizer v --now "$NOW"
refuse "pr non-decimal" record --vendor v --event request --pr 4x2 --now "$NOW"
refuse "pr leading zero" record --vendor v --event request --pr 042 --now "$NOW"
refuse "head short" record --vendor v --event request --head abc123 --now "$NOW"
refuse "head uppercase" record --vendor v --event request --head "$(printf '%s' "$HEAD40" | tr a-f A-F)" --now "$NOW"
refuse "reset non-epoch" hold --vendor v --unit u1 --step s --reason r --reset tomorrow --now "$NOW"
refuse "event unknown" record --vendor v --event spend --now "$NOW"
refuse "hold event via record" record --vendor v --event hold --now "$NOW"
refuse "reason missing" hold --vendor v --unit u1 --step s --now "$NOW"
pass "hostile ids, PR numbers, heads, and reset times are refused before any write"

# --- 6. Forged lines are skipped on read; written reasons stay one line -----
new_home forged
run record --vendor sample-cli --event refusal --reason "line one${nl}line${TAB}two" --now "$NOW" || fail "record with a multi-line reason failed"
lf=$(ledger sample-cli)
[ "$(wc -l <"$lf" | tr -d ' ')" = 1 ] || fail "a multi-line reason was not flattened to one ledger line"
grep -q 'line one line two' "$lf" || fail "the flattened reason lost its text: $(cat "$lf")"
# A hand-forged line whose reason carries a newline: neither half is read.
{
  printf '%s\trefusal\t-\t-\t-\t-\tforged%s\tend\n' "$NOW" "${nl}${NOW}${TAB}hold"
  printf '%s\trequest\t../x\t-\t-\t-\t-\tend\n' "$NOW"
  printf 'garbage\n'
} >>"$lf"
status=$(run status --vendor sample-cli --now "$NOW")
printf '%s\n' "$status" | grep -q "^count${TAB}sample-cli${TAB}refusal${TAB}1$" || fail "forged: a forged refusal was counted: $status"
printf '%s\n' "$status" | grep -q "^count${TAB}sample-cli${TAB}hold${TAB}0$" || fail "forged: a forged hold fragment was counted: $status"
printf '%s\n' "$status" | grep -q "^count${TAB}sample-cli${TAB}request${TAB}0$" || fail "forged: a request with a hostile unit was counted: $status"
mkdir -p "$home/fleet/quota/sample-cli"
printf '%s\t../escape\tpanel\t-\t-\tforged\tend\n' "$NOW" >"$(holdfile sample-cli)"
status=$(run status --vendor sample-cli --now "$NOW")
printf '%s\n' "$status" | grep -q "^vendor${TAB}sample-cli${TAB}clear${TAB}" || fail "forged: a hostile hold line was trusted: $status"
pass "forged ledger and hold lines are skipped on read"

# A planted symlink in the store is never written through.
new_home symlink
mkdir -p "$home/fleet/quota/sample-cli"
: >"$tmp/link-target"
ln -s "$tmp/link-target" "$home/fleet/quota/sample-cli/ledger.tsv"
rc=0
run record --vendor sample-cli --event request --now "$NOW" 2>/dev/null || rc=$?
[ "$rc" = 6 ] || fail "symlink: a record through a planted ledger link exited $rc, not 6"
[ ! -s "$tmp/link-target" ] || fail "symlink: the record wrote through the planted link"
pass "a planted symlink in the store is refused"

# --- 7. The vendor view in fleet-stats.sh render ---------------------------
# The render reads the real clock, so this fixture is stamped relative to it.
new_home stats
real=$(date +%s)
real_reset=$((real + 3600))
real_reset_iso=$(TZ=UTC date -u -r "$real_reset" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
  || real_reset_iso=$(TZ=UTC date -u -d "@$real_reset" +%Y-%m-%dT%H:%M:%SZ)
run record --vendor sample-reviewer --event request --pr 7 --now $((real - 50)) || fail "stats fixture: record failed"
run hold --vendor sample-reviewer --unit spec-a:task-1 --step bot-review --reason "quota used up" --reset "$real_reset" --now $((real - 40)) >/dev/null 2>&1 || fail "stats fixture: hold failed"
run record --vendor sample-cli --event request --now $((real - 30)) || fail "stats fixture: record failed"
render=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
  /bin/sh "$FSTATS" render 2>/dev/null) || fail "fleet-stats render exited non-zero"
printf '%s\n' "$render" | grep -q '^  vendors:' || fail "render: no vendor view: $render"
printf '%s\n' "$render" | grep -q "^    sample-reviewer: held since .*1 unit.*reset $real_reset_iso.*quota used up" \
  || fail "render: the held vendor's line is missing its state, reset, or reason: $render"
printf '%s\n' "$render" | grep -q '^    sample-cli: clear' || fail "render: the clear vendor's line is missing: $render"
printf '%s\n' "$render" | grep -q 'over 90d: 1 request, 0 answers, 0 refusals, 1 hold, 0 resumes' \
  || fail "render: the held vendor's counts are missing: $render"
pass "fleet-stats.sh render shows each vendor's hold state, reason, and counts"

new_home stats-empty
render=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
  /bin/sh "$FSTATS" render 2>/dev/null) || fail "fleet-stats render (empty) exited non-zero"
printf '%s\n' "$render" | grep -q '^  vendors:        none recorded$' || fail "render: an empty store does not say none recorded: $render"
pass "an empty store renders as none recorded"

# A store status cannot read fails closed: never a held vendor rendered clear
# or missing.
new_home stats-unreadable
run hold --vendor sample-reviewer --unit spec-a:task-1 --step bot-review --reason "quota" --now "$NOW" >/dev/null 2>&1 || fail "unreadable fixture: hold failed"
for f in hold.tsv ledger.tsv; do
  chmod 000 "$home/fleet/quota/sample-reviewer/$f"
  rc=0
  run status --now "$NOW" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 6 ] || fail "status over an unreadable $f exited $rc, not 6"
  render=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$FSTATS" render 2>/dev/null) || fail "fleet-stats render (unreadable) exited non-zero"
  printf '%s\n' "$render" | grep -q '^  vendors:        unknown$' || fail "render over an unreadable $f is not unknown: $render"
  chmod 600 "$home/fleet/quota/sample-reviewer/$f"
done
pass "status fails closed over an unreadable store, and the render says unknown"

# A stated reset of 0 is still a stated reset in the status view.
new_home reset-zero
run hold --vendor sample-cli --unit spec-a:task-1 --step panel --reason "quota" --reset 0 --now "$NOW" >/dev/null 2>&1 || fail "reset-zero fixture: hold failed"
run status --vendor sample-cli --now "$NOW" | grep -q "^vendor${TAB}sample-cli${TAB}held${TAB}${NOW}${TAB}0${TAB}1${TAB}" \
  || fail "status dropped a stated reset of 0"
pass "a stated reset of 0 reads the same in status as in the push"

# --- 8. The fleet home is outside the repository's tracked tree -------------
inherited_home=$(fleet_home_inherited)
if [ -n "$inherited_home" ]; then
  case $inherited_home/ in
    "$repo_root"/*) fail "the fleet home sits inside the repository: $inherited_home" ;;
  esac
fi
tracked=$(git -C "$repo_root" ls-files -- "*quota*/ledger.tsv" "*quota*/hold.tsv")
[ -z "$tracked" ] || fail "a ledger or hold file is tracked: $tracked"
pass "the ledger lives outside the repository's tracked tree"

echo "all quota-hold tests passed"
