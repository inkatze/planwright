#!/bin/bash
# Tests for scripts/quota-hold.sh, the per-vendor hold store and usage ledger
# (quota-handling REQ-B1.1, REQ-B1.3, REQ-B1.5, REQ-E1.1, REQ-E1.2), and the
# vendor view it feeds into scripts/fleet-stats.sh render.
#
# Covered:
#   - two units holding one vendor concurrently both land as holders, with a
#     ledger line each (the lock library serializes the writers);
#   - a hold pushes one attention event naming the vendor, the reason, the
#     stated reset time, and the operator's resume command, once per hold
#     whoever joins or renews it;
#   - resume releases every holder and records the resume;
#   - prune drops ledger lines older than the retention knob (90 days when
#     unset) and keeps the rest byte for byte;
#   - status renders hold state and per-event counts over the retention period,
#     and fleet-stats.sh render shows the same through its vendor view;
#   - hostile vendor, unit, step, and recognizer ids, PR numbers, heads, and
#     reset times are refused before any path or ledger use;
#   - a forged ledger or hold line (an embedded newline in a reason, or any one
#     field out of grammar) is skipped on read and dropped by prune, a reason
#     given with a newline is stored flattened, and a torn line never swallows
#     the next append;
#   - a failed ledger write leaves the hold store unchanged, and status over an
#     unreadable store fails closed (the render says unknown);
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
# A background loop a case starts is named here, so an interrupted suite stops
# it instead of leaving it spinning on a removed directory.
bg_loop=""
trap '[ -z "$bg_loop" ] || kill "$bg_loop" 2>/dev/null; rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# shellcheck source=tests/lib/fleet-home.sh
. "$here/lib/fleet-home.sh"
# shellcheck source=tests/lib/poll-until.sh
. "$here/lib/poll-until.sh"

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

# Once the pending push is relayed (the marker consumed), a unit joining the
# same hold or renewing it pushes nothing; a hold after a resume pushes anew.
rm -f "$push_dir"/*
run hold --vendor sample-reviewer --unit spec-z:task-1 --step bot-review \
  --reason "review quota used up" --now $((NOW + 30)) >/dev/null 2>&1 || fail "a joining hold exited non-zero"
run hold --vendor sample-reviewer --unit spec-a:task-1 --step bot-review \
  --reason "review quota used up" --now $((NOW + 31)) >/dev/null 2>&1 || fail "a renewing hold exited non-zero"
[ -z "$(ls -A "$push_dir")" ] || fail "push: a unit joining a relayed hold pushed it again: $(cat "$push_dir"/*)"
run resume --vendor sample-reviewer --now $((NOW + 40)) >/dev/null || fail "resume before a re-hold failed"
run hold --vendor sample-reviewer --unit spec-a:task-1 --step bot-review \
  --reason "refused again" --now $((NOW + 50)) >/dev/null 2>&1 || fail "a hold after a resume exited non-zero"
case $(cat "$push_dir"/* 2>/dev/null) in
  *"refused again"*) ;;
  *) fail "push: a hold after a resume pushed nothing" ;;
esac
pass "a joined or renewed hold is never pushed twice, and a new hold after a resume is"

# A push record naming an older hold never silences a new one.
new_home stale-record
mkdir -p "$home/fleet/quota/sample-cli"
printf '%s\n' $((NOW - 999)) >"$home/fleet/quota/sample-cli/pushed"
run hold --vendor sample-cli --unit spec-a:task-1 --step panel --reason "quota" --now "$NOW" >/dev/null 2>&1 || fail "stale-record: hold failed"
[ -n "$(ls -A "$home/fleet/attention/push" 2>/dev/null)" ] || fail "stale-record: a push record for an older hold silenced a new one"

# A push that finishes after a resume and a new hold never records the old
# hold over the new one: a stub notify parks the first push until released.
new_home late-push
stub="$tmp/stub-scripts"
rm -rf "$stub"
cp -R "$repo_root/scripts" "$stub"
cat >"$stub/fleet-attention.sh" <<'STUB'
#!/bin/sh
n=0
while [ ! -e "$QH_GO" ] && [ "$n" -lt 90 ]; do
  sleep 1
  n=$((n + 1))
done
printf '%s\n' "$4" >>"$QH_PUSHES"
STUB
chmod 755 "$stub/fleet-attention.sh"
srun() {
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    QH_PUSHES="$tmp/late-pushes" /bin/sh "$stub/quota-hold.sh" "$@"
}
: >"$tmp/late-pushes"
QH_GO="$tmp/go-first" srun hold --vendor sample-cli --unit spec-a:task-1 --step panel --reason "quota" --now "$NOW" >/dev/null 2>&1 &
first=$!
poll_until --what 'the first hold landing' -- test -s "$home/fleet/quota/sample-cli/hold.tsv" \
  || fail "late-push: the first hold never landed"
: >"$tmp/go-now"
QH_GO="$tmp/go-now" srun resume --vendor sample-cli --now $((NOW + 50)) >/dev/null || fail "late-push: resume failed"
QH_GO="$tmp/go-now" srun hold --vendor sample-cli --unit spec-b:task-1 --step panel --reason "quota" --now $((NOW + 100)) >/dev/null 2>&1 || fail "late-push: the second hold failed"
: >"$tmp/go-first"
wait "$first" || fail "late-push: the parked first hold failed"
QH_GO="$tmp/go-now" srun hold --vendor sample-cli --unit spec-c:task-1 --step panel --reason "quota" --now $((NOW + 200)) >/dev/null 2>&1 || fail "late-push: the joining hold failed"
[ "$(grep -c "quota-hold-sample-cli-$((NOW + 100))" "$tmp/late-pushes")" = 1 ] \
  || fail "late-push: the live hold was pushed again after a late push recorded the old one: $(cat "$tmp/late-pushes")"
pass "a push record follows the live hold, never an older one"

# A failed push whose reservation cannot be released says so rather than
# leaving joiners silently unpushed.
if [ "$(id -u)" != 0 ]; then
  new_home unreleased
  cat >"$stub/fleet-attention.sh" <<'STUB'
#!/bin/sh
chmod 500 "$QH_VENDORDIR"
exit 1
STUB
  rc=0
  QH_VENDORDIR="$home/fleet/quota/sample-cli" srun hold --vendor sample-cli --unit spec-a:task-1 --step panel \
    --reason "quota" --now "$NOW" >/dev/null 2>"$tmp/unreleased-err" || rc=$?
  chmod 700 "$home/fleet/quota/sample-cli"
  [ "$rc" = 3 ] || fail "unreleased: a hold whose push failed exited $rc, not 3"
  grep -q "the push stays reserved" "$tmp/unreleased-err" \
    || fail "unreleased: no warning that the push stayed reserved: $(cat "$tmp/unreleased-err")"
  pass "a failed push whose reservation cannot be released says so"
fi

# A holder killed mid-push releases its reservation, so the next joiner pushes;
# and a failing holder never releases a later hold's reservation that began in
# the same second.
cat >"$stub/fleet-attention.sh" <<'STUB'
#!/bin/sh
case ${QH_STUB_MODE:-ok} in
  slow) sleep 30 ;;
  slowfail)
    n=0
    while [ ! -e "$QH_GO" ] && [ "$n" -lt 60 ]; do
      sleep 1
      n=$((n + 1))
    done
    exit 1
    ;;
esac
printf '%s\n' "$4" >>"$QH_PUSHES"
STUB
chmod 755 "$stub/fleet-attention.sh"
new_home killed-push
: >"$tmp/late-pushes"
QH_STUB_MODE=slow srun hold --vendor sample-cli --unit spec-a:task-1 --step panel --reason quota --now "$NOW" >/dev/null 2>&1 &
victim=$!
poll_until --what 'the push reservation' -- test -s "$home/fleet/quota/sample-cli/pushed" \
  || fail "killed-push: the push was never reserved"
# TERM the whole tree, as a timeout wrapper's process-group signal would.
term_tree() {
  for tt_c in $(pgrep -P "$1" 2>/dev/null); do
    term_tree "$tt_c"
  done
  kill -TERM "$1" 2>/dev/null || :
}
term_tree "$victim"
wait "$victim" 2>/dev/null || :
poll_until --what 'the killed holder releasing its reservation' -- test ! -s "$home/fleet/quota/sample-cli/pushed" \
  || fail "killed-push: the killed holder never released its reservation"
srun hold --vendor sample-cli --unit spec-b:task-2 --step panel --reason quota --now "$NOW" >/dev/null 2>&1 || fail "killed-push: the next joiner failed"
[ "$(grep -c "quota-hold-sample-cli-$NOW" "$tmp/late-pushes")" = 1 ] \
  || fail "killed-push: the next joiner did not push the hold a killed holder had reserved"
pass "a holder killed mid-push releases its reservation"

new_home same-second
: >"$tmp/late-pushes"
rm -f "$tmp/go-a"
QH_STUB_MODE=slowfail QH_GO="$tmp/go-a" srun hold --vendor sample-cli --unit spec-a:task-1 --step panel --reason quota --now "$NOW" >/dev/null 2>&1 &
holder_a=$!
poll_until --what 'the first push reservation' -- test -s "$home/fleet/quota/sample-cli/pushed" \
  || fail "same-second: the first push was never reserved"
srun resume --vendor sample-cli --now "$NOW" >/dev/null || fail "same-second: resume failed"
srun hold --vendor sample-cli --unit spec-b:task-2 --step panel --reason quota --now "$NOW" >/dev/null 2>&1 || fail "same-second: the new hold failed"
: >"$tmp/go-a"
rc=0
wait "$holder_a" || rc=$?
[ "$rc" = 3 ] || fail "same-second: the failing holder exited $rc, not 3"
srun hold --vendor sample-cli --unit spec-c:task-3 --step panel --reason quota --now "$NOW" >/dev/null 2>&1 || fail "same-second: the joiner failed"
[ "$(grep -c "quota-hold-sample-cli-$NOW" "$tmp/late-pushes")" = 1 ] \
  || fail "same-second: a failing holder released the new hold's reservation, so it was pushed $(grep -c "quota-hold-sample-cli-$NOW" "$tmp/late-pushes") times"
pass "a failing holder releases only its own reservation"

new_home noreset
run hold --vendor sample-cli --unit spec-a:task-1 --step panel \
  --reason "monthly allowance exhausted" --now "$NOW" >/dev/null 2>&1 || fail "hold without a reset exited non-zero"
marker=$(cat "$home/fleet/attention/push"/* 2>/dev/null) || fail "push: a hold with no stated reset pushed nothing"
case $marker in
  *"no stated reset"*) ;;
  *) fail "push: a hold with no stated reset does not say so: $marker" ;;
esac
pass "a hold with no stated reset time says so in its event"

# A hold whose push fails is still recorded, exits 3, and is pushed by the
# next unit that joins it.
new_home push-fails
mkdir -p "$home/fleet/attention"
: >"$home/fleet/attention/push"
rc=0
out=$(run hold --vendor sample-cli --unit spec-a:task-1 --step panel --reason "quota" --now "$NOW" 2>/dev/null) || rc=$?
rm -f "$home/fleet/attention/push"
[ "$rc" = 3 ] || fail "push-fails: a hold whose push failed exited $rc, not 3"
[ "$out" = "held${TAB}sample-cli${TAB}${NOW}" ] || fail "push-fails: the hold did not print its held line: $out"
grep -q "${TAB}spec-a:task-1${TAB}" "$(holdfile sample-cli)" || fail "push-fails: the hold was not recorded"
run hold --vendor sample-cli --unit spec-b:task-1 --step panel --reason "quota" --now "$NOW" >/dev/null 2>&1 || fail "push-fails: the joining hold failed"
[ -n "$(ls -A "$home/fleet/attention/push")" ] || fail "push-fails: the joining unit did not push the unpushed hold"
pass "a failed push exits 3 with the hold recorded, and the next joiner pushes it"

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

# The other store files are held to the same rule, and no verb blocks on a
# FIFO where a store file belongs.
# bg_run <fifo> <args>: run the script in the background; one still running
# at the poll deadline is released by opening <fifo> for writing, and bg_rc
# reads hung.
bg_gone() { ! kill -0 "$bg_pid" 2>/dev/null; }
bg_run() {
  bg_fifo=$1
  shift
  run "$@" >/dev/null 2>&1 &
  bg_pid=$!
  if ! poll_until --what "quota-hold $1 finishing" -- bg_gone; then
    (: >"$bg_fifo") >/dev/null 2>&1 &
    bg_w=$!
    wait "$bg_pid" 2>/dev/null || :
    kill "$bg_w" 2>/dev/null || :
    wait "$bg_w" 2>/dev/null || :
    bg_rc=hung
  else
    bg_rc=0
    wait "$bg_pid" || bg_rc=$?
  fi
}
for f in hold.tsv ledger.tsv; do
  new_home "fifo-$f"
  vdir="$home/fleet/quota/sample-reviewer"
  mkdir -p "$vdir"
  mkfifo "$vdir/$f"
  bg_run "$vdir/$f" status --vendor sample-reviewer --now "$NOW"
  [ "$bg_rc" = 6 ] || fail "non-regular: status over a FIFO $f exited $bg_rc, not 6"
done
new_home resume-not-file
vdir="$home/fleet/quota/sample-reviewer"
mkdir -p "$vdir"
mkfifo "$vdir/hold.tsv"
bg_run "$vdir/hold.tsv" resume --vendor sample-reviewer --now "$NOW"
[ "$bg_rc" = 6 ] || fail "non-regular: a resume over a FIFO hold store exited $bg_rc, not 6"
rm -f "$vdir/hold.tsv"
mkdir "$vdir/hold.tsv"
rc=0
run resume --vendor sample-reviewer --now "$NOW" >/dev/null 2>&1 || rc=$?
[ "$rc" = 6 ] || fail "non-regular: a resume over a hold store that is a directory exited $rc, not 6"
new_home pushed-stuck
run hold --vendor sample-reviewer --unit spec-a:task-1 --step bot-review --reason "quota" --now "$NOW" >/dev/null 2>&1 || fail "pushed-stuck fixture: hold failed"
vdir="$home/fleet/quota/sample-reviewer"
rm -f "$vdir/pushed"
mkdir -p "$vdir/pushed/kept"
rc=0
run resume --vendor sample-reviewer --now "$NOW" >/dev/null 2>&1 || rc=$?
[ "$rc" = 6 ] || fail "non-regular: a resume that could not clear the push record exited $rc, not 6"
grep -q "${TAB}spec-a:task-1${TAB}" "$vdir/hold.tsv" || fail "non-regular: a resume that could not clear the push record released the holds"
new_home pushed-not-file
vdir="$home/fleet/quota/sample-reviewer"
mkdir -p "$vdir/pushed"
rc=0
run hold --vendor sample-reviewer --unit spec-a:task-1 --step bot-review --reason "quota" --now "$NOW" >/dev/null 2>&1 || rc=$?
[ "$rc" = 6 ] || fail "non-regular: a hold over a push record that is a directory exited $rc, not 6"
[ ! -e "$vdir/hold.tsv" ] || fail "non-regular: a hold refused over its push record still held"
pass "status, resume, and hold refuse store files that are not regular files"

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

# Each line carries the PR, head, unit, and recognizer it was given, and `-`
# where it was given none.
lf=$(ledger sample-reviewer)
grep -q "${TAB}request${TAB}spec-a:task-1${TAB}42${TAB}${HEAD40}${TAB}-${TAB}-${TAB}end$" "$lf" \
  || fail "ledger: a request line lost its unit, PR, or head: $(cat "$lf")"
grep -q "${TAB}answer${TAB}-${TAB}42${TAB}${HEAD40}${TAB}-${TAB}-${TAB}end$" "$lf" \
  || fail "ledger: an answer given no unit, recognizer, or reason did not record dashes: $(cat "$lf")"
grep -q "${TAB}hold${TAB}spec-a:task-1${TAB}42${TAB}${HEAD40}${TAB}sample-reviewer.quota${TAB}quota used up${TAB}end$" "$lf" \
  || fail "ledger: a hold line lost its PR, head, or recognizer: $(cat "$lf")"

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

new_home ledger-fields
HEAD64=$HEAD40$(printf '%s' "$HEAD40" | cut -c 1-24)
run hold --vendor sample-reviewer --unit spec-a:task-1 --step bot-review --reason "quota" \
  --recognizer sample-reviewer.quota --pr 42 --head "$HEAD64" --now "$NOW" >/dev/null 2>&1 || fail "hold with a 64-hex head failed"
grep -q "^${NOW}${TAB}hold${TAB}spec-a:task-1${TAB}42${TAB}${HEAD64}${TAB}sample-reviewer.quota${TAB}quota${TAB}end$" "$(ledger sample-reviewer)" \
  || fail "ledger: a hold line lost its PR, 64-hex head, or recognizer: $(cat "$(ledger sample-reviewer)")"
long=$(printf '%0600d' 0 | tr 0 x)
run record --vendor sample-reviewer --event refusal --reason "$long" --now "$NOW" || fail "record with a long reason failed"
got=$(tail -n 1 "$(ledger sample-reviewer)" | cut -f 7)
[ "${#got}" = 512 ] || fail "ledger: a long reason was stored at ${#got} bytes, not cut to 512"
pass "ledger lines carry the PR, head, and recognizer given, and a reason is cut to 512 bytes"

# A renewal takes the new step and reason; the vendor line reads the earliest
# holder's since and reason and the latest stated reset.
new_home renewal
run hold --vendor sample-reviewer --unit spec-a:task-1 --step bot-review --reason "first" --reset $((NOW + 100)) --now "$NOW" >/dev/null 2>&1 || fail "renewal fixture: hold a failed"
run hold --vendor sample-reviewer --unit spec-b:task-1 --step panel --reason "second" --reset $((NOW + 900)) --now $((NOW + 10)) >/dev/null 2>&1 || fail "renewal fixture: hold b failed"
run hold --vendor sample-reviewer --unit spec-c:task-1 --step panel --reason "third" --reset $((NOW + 500)) --now $((NOW + 20)) >/dev/null 2>&1 || fail "renewal fixture: hold c failed"
run hold --vendor sample-reviewer --unit spec-d:task-1 --step panel --reason "fourth" --reset $((NOW + 200)) --now $((NOW + 25)) >/dev/null 2>&1 || fail "renewal fixture: hold d failed"
run hold --vendor sample-reviewer --unit spec-b:task-1 --step bot-review --reason "renewed" --now $((NOW + 30)) >/dev/null 2>&1 || fail "renewal fixture: renew b failed"
[ "$(grep -c "${TAB}spec-b:task-1${TAB}" "$(holdfile sample-reviewer)")" = 1 ] || fail "renewal: the unit was written twice"
grep -q "^$((NOW + 10))${TAB}spec-b:task-1${TAB}bot-review${TAB}-${TAB}-${TAB}renewed${TAB}end$" "$(holdfile sample-reviewer)" \
  || fail "renewal: the renewed line did not take the new step and reason: $(cat "$(holdfile sample-reviewer)")"
st=$(run status --vendor sample-reviewer --now $((NOW + 30))) || fail "status exited non-zero (--vendor sample-reviewer)"
printf '%s\n' "$st" | grep -q "^vendor${TAB}sample-reviewer${TAB}held${TAB}${NOW}${TAB}$((NOW + 500))${TAB}4${TAB}first$" \
  || fail "status: the vendor line is not the earliest since and reason with the latest reset"
pass "a renewal takes the new step and reason, and the vendor line aggregates its holders"

# Retention edges: a line exactly at the cutoff counts and survives prune, a
# value above 36500 reads as 36500, prune --vendor touches only that vendor,
# and a resume reason reaches the ledger.
new_home retention
run record --vendor sample-reviewer --event request --now $((NOW - 90 * DAY)) || fail "retention fixture: record at the cutoff failed"
run record --vendor sample-reviewer --event request --now $((NOW - 90 * DAY - 1)) || fail "retention fixture: record past the cutoff failed"
run record --vendor sample-cli --event request --now $((NOW - 200 * DAY)) || fail "retention fixture: other vendor record failed"
st=$(run status --vendor sample-reviewer --now "$NOW") || fail "status exited non-zero (--vendor sample-reviewer)"
printf '%s\n' "$st" | grep -q "^count${TAB}sample-reviewer${TAB}request${TAB}1$" \
  || fail "retention: a line exactly at the cutoff was not counted (or one past it was)"
run prune --vendor sample-reviewer --now "$NOW" || fail "prune --vendor failed"
[ "$(wc -l <"$(ledger sample-reviewer)" | tr -d ' ')" = 1 ] || fail "retention: prune did not keep exactly the line at the cutoff"
[ "$(wc -l <"$(ledger sample-cli)" | tr -d ' ')" = 1 ] || fail "retention: prune --vendor touched another vendor"
printf 'quota_ledger_retention_days: 99999\n' >"$local_cfg"
st=$(run status --vendor sample-reviewer --now "$NOW") || fail "status exited non-zero (--vendor sample-reviewer)"
printf '%s\n' "$st" | grep -q "^retention${TAB}36500$" || fail "retention: a value above 36500 did not read as 36500"
: >"$local_cfg"
mkdir -p "$home/fleet/quota/Not-A-Vendor"
st=$(run status --now "$NOW") || fail "status exited non-zero (all vendors)"
! printf '%s\n' "$st" | grep -q "Not-A-Vendor" || fail "status listed a store directory outside the vendor grammar"
run hold --vendor sample-cli --unit spec-a:task-1 --step panel --reason "quota" --now "$NOW" >/dev/null 2>&1 || fail "retention fixture: hold failed"
run resume --vendor sample-cli --reason "window reset seen" --now "$NOW" >/dev/null || fail "resume with a reason failed"
grep -q "${TAB}resume${TAB}-${TAB}-${TAB}-${TAB}-${TAB}window reset seen${TAB}end$" "$(ledger sample-cli)" || fail "retention: the resume reason did not reach the ledger"
pass "retention edges: the cutoff, the clamp, a scoped prune, and the resume reason"

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
  if [ -e "$tmp/escape" ] || [ -e "$home/escape" ]; then
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
refuse "reason empty" hold --vendor v --unit u1 --step s --reason "" --now "$NOW"
refuse "now non-epoch" record --vendor v --event request --now "1e9"
refuse "recognizer of another vendor" record --vendor v --event refusal --recognizer other.quota --now "$NOW"
refuse "flag the verb does not take" resume --vendor v --unit u1 --now "$NOW"
refuse "vendor too long" record --vendor "v$(printf '%064d' 0 | tr 0 a)" --event request --now "$NOW"
refuse "unit too long" hold --vendor v --unit "u$(printf '%0128d' 0)" --step s --reason r --now "$NOW"
refuse "pr too long" record --vendor v --event request --pr 12345678901 --now "$NOW"
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

# Each read rule on its own: a full eight-field line ending in `end` that
# breaks exactly one field is never counted, and prune drops it.
new_home forged-fields
lf=$(ledger sample-cli)
run record --vendor sample-cli --event answer --now "$NOW" || fail "forged-fields fixture: record failed"
esc=$(printf '\033')
{
  printf '%s\trequest\t-\t-\t-\tother.quota\tr\tend\n' "$NOW"
  printf '%s\trequest\t-\t042\t-\t-\tr\tend\n' "$NOW"
  printf '%s\trequest\t-\t-\t%s\t-\tr\tend\n' "$NOW" "$(printf '%s' "$HEAD40" | tr a-f A-F)"
  printf 'soon\trequest\t-\t-\t-\t-\tr\tend\n'
  printf '%s\tspend\t-\t-\t-\t-\tr\tend\n' "$NOW"
  printf '%s\trequest\t-\t-\t-\t-\tbad%sbyte\tend\n' "$NOW" "$esc"
  printf '%s\trequest\t-\t-\t-\t-\tr\tnot-end\n' "$NOW"
  printf '%s\trequest\t-\t-\t-\t-\t%s\tend\n' "$NOW" "$(printf '%0513d' 0)"
  printf '%s\trequest\t-\t-\t-\t-\t\tend\n' "$NOW"
  printf '%s\trequest\t-\t-\t%sa\t-\tr\tend\n' "$NOW" "$HEAD40"
  printf '1%015d\trequest\t-\t-\t-\t-\tr\tend\n' 0
  printf '%s\trequest\t..\t-\t-\t-\tr\tend\n' "$NOW"
  printf '%s\trequest\tu%0128d\t-\t-\t-\tr\tend\n' "$NOW" 0
  printf '%s\trequest\t-\t-\t-\t-\tr\tend\textra\n' "$NOW"
} >>"$lf"
status=$(run status --vendor sample-cli --now "$NOW")
printf '%s\n' "$status" | grep -q "^count${TAB}sample-cli${TAB}request${TAB}0$" || fail "forged-fields: a line breaking one field was counted: $status"
printf '%s\n' "$status" | grep -q "^count${TAB}sample-cli${TAB}answer${TAB}1$" || fail "forged-fields: the valid line was not counted: $status"
run prune --now "$NOW" || fail "forged-fields: prune failed"
[ "$(wc -l <"$lf" | tr -d ' ')" = 1 ] || fail "forged-fields: prune kept a line failing the grammar: $(cat "$lf")"
pass "every read rule skips its own forged line, and prune drops them"

# The hold store's read rules, one forged line each: none is a holder, and a
# resume releases none of them.
new_home forged-holds
mkdir -p "$home/fleet/quota/sample-cli"
{
  printf 'soon\tspec-a:task-1\tpanel\t-\t-\tr\tend\n'
  printf '%s\tspec-a:task-1\tBad Step\t-\t-\tr\tend\n' "$NOW"
  printf '%s\tspec-a:task-1\tpanel\tlater\t-\tr\tend\n' "$NOW"
  printf '%s\tspec-a:task-1\tpanel\t-\tother.quota\tr\tend\n' "$NOW"
  printf '%s\tspec-a:task-1\tpanel\t-\t-\tbad%sbyte\tend\n' "$NOW" "$esc"
  printf '%s\tspec-a:task-1\tpanel\t-\t-\tr\tnot-end\n' "$NOW"
  printf '%s\tspec-a:task-1\tpanel\t-\t-\tr\tend\textra\n' "$NOW"
  printf '1%015d\tspec-a:task-1\tpanel\t-\t-\tr\tend\n' 0
  printf '%s\tspec-ok:task-1\tpanel\t-\t-\tr\tend\n' "$NOW"
} >"$(holdfile sample-cli)"
st=$(run status --vendor sample-cli --now "$NOW") || fail "forged-holds: status exited non-zero"
printf '%s\n' "$st" | grep -q "^vendor${TAB}sample-cli${TAB}held${TAB}${NOW}${TAB}-${TAB}1${TAB}r$" || fail "forged-holds: a forged hold line was read as a holder: $st"
out=$(run resume --vendor sample-cli --now "$NOW") || fail "forged-holds: resume failed"
[ "$out" = "released${TAB}spec-ok:task-1${TAB}panel" ] || fail "forged-holds: resume released other than the one valid line: $out"
pass "every hold-store read rule skips its own forged line"

# An append that was cut short (a full disk) never swallows the next line.
new_home torn
run record --vendor sample-cli --event request --now "$NOW" || fail "torn fixture: record failed"
printf '%s\trequest\t-\t-' "$NOW" >>"$(ledger sample-cli)"
run record --vendor sample-cli --event refusal --now "$NOW" || fail "torn: the record after a torn line failed"
st=$(run status --vendor sample-cli --now "$NOW") || fail "status exited non-zero (--vendor sample-cli)"
printf '%s\n' "$st" | grep -q "^count${TAB}sample-cli${TAB}refusal${TAB}1$" \
  || fail "torn: the line appended after a torn one was lost"
# A crash can leave the tail as NUL bytes rather than a cut line.
printf '%s\trequest\t-\t-\t-\t-\t-\te\000\000' "$NOW" >>"$(ledger sample-cli)"
run record --vendor sample-cli --event answer --now "$NOW" || fail "torn: the record after a NUL tail failed"
st=$(run status --vendor sample-cli --now "$NOW") || fail "status exited non-zero (--vendor sample-cli)"
printf '%s\n' "$st" | grep -q "^count${TAB}sample-cli${TAB}answer${TAB}1$" \
  || fail "torn: the line appended after a NUL tail was lost"
pass "a torn ledger line never swallows the next append"

# A planted symlink in the store is never written through.
new_home symlink
mkdir -p "$home/fleet/quota/sample-cli"
: >"$tmp/link-target"
ln -s "$tmp/link-target" "$home/fleet/quota/sample-cli/ledger.tsv"
rc=0
run record --vendor sample-cli --event request --now "$NOW" 2>/dev/null || rc=$?
[ "$rc" = 6 ] || fail "symlink: a record through a planted ledger link exited $rc, not 6"
[ ! -s "$tmp/link-target" ] || fail "symlink: the record wrote through the planted link"
for pos in vendor hold store; do
  new_home "symlink-$pos"
  mkdir -p "$tmp/link-dir-$pos"
  case $pos in
    vendor)
      mkdir -p "$home/fleet/quota"
      ln -s "$tmp/link-dir-$pos" "$home/fleet/quota/sample-cli"
      ;;
    hold)
      mkdir -p "$home/fleet/quota/sample-cli"
      ln -s "$tmp/link-dir-$pos/hold.tsv" "$home/fleet/quota/sample-cli/hold.tsv"
      ;;
    store)
      mkdir -p "$home/fleet"
      ln -s "$tmp/link-dir-$pos" "$home/fleet/quota"
      ;;
  esac
  rc=0
  run hold --vendor sample-cli --unit spec-a:task-1 --step panel --reason r --now "$NOW" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 6 ] || fail "symlink: a hold through a planted $pos link exited $rc, not 6"
  [ -z "$(ls -A "$tmp/link-dir-$pos")" ] || fail "symlink: a hold wrote through a planted $pos link"
done
new_home symlink-prune
mkdir -p "$home/fleet/quota/sample-cli"
printf '%s\trequest\t-\t-\t-\t-\t-\tend\n' 1 >"$tmp/prune-target"
ln -s "$tmp/prune-target" "$home/fleet/quota/sample-cli/ledger.tsv"
rc=0
run prune --now "$NOW" 2>/dev/null || rc=$?
[ "$rc" = 6 ] || fail "symlink: a prune through a planted ledger link exited $rc, not 6"
[ -s "$tmp/prune-target" ] || fail "symlink: the prune rewrote the planted link's target"
pass "a planted symlink in the store is refused"

# status refuses the same links the writers do, named or enumerated.
for pos in store vendor hold ledger; do
  for form in named all; do
    new_home "symlink-status-$pos-$form"
    mkdir -p "$tmp/status-link-$pos-$form"
    printf '%s\t%s\tpanel\t-\t-\tplanted\tend\n' "$NOW" spec-a:task-1 >"$tmp/status-link-$pos-$form/hold.tsv"
    case $pos in
      store)
        mkdir -p "$home/fleet"
        mkdir -p "$tmp/status-link-$pos-$form/sample-cli"
        ln -s "$tmp/status-link-$pos-$form" "$home/fleet/quota"
        ;;
      vendor)
        mkdir -p "$home/fleet/quota"
        ln -s "$tmp/status-link-$pos-$form" "$home/fleet/quota/sample-cli"
        ;;
      hold)
        mkdir -p "$home/fleet/quota/sample-cli"
        ln -s "$tmp/status-link-$pos-$form/hold.tsv" "$home/fleet/quota/sample-cli/hold.tsv"
        ;;
      ledger)
        mkdir -p "$home/fleet/quota/sample-cli"
        ln -s "$tmp/status-link-$pos-$form/hold.tsv" "$home/fleet/quota/sample-cli/ledger.tsv"
        ;;
    esac
    rc=0
    if [ "$form" = named ]; then
      run status --vendor sample-cli --now "$NOW" >/dev/null 2>&1 || rc=$?
    else
      run status --now "$NOW" >/dev/null 2>&1 || rc=$?
    fi
    [ "$rc" = 6 ] || fail "symlink: status ($form) through a planted $pos link exited $rc, not 6"
  done
done
pass "status refuses a symlink in the store, as the writers do"

# prune and resume refuse a link even where they would have nothing to do.
new_home symlink-prune-store
mkdir -p "$home/fleet" "$tmp/prune-store-link/sample-cli"
ln -s "$tmp/prune-store-link" "$home/fleet/quota"
rc=0
run prune --now "$NOW" >/dev/null 2>&1 || rc=$?
[ "$rc" = 6 ] || fail "symlink: prune over a linked store exited $rc, not 6"
new_home prune-unsearchable
mkdir -p "$home/fleet/quota/sample-cli"
chmod 000 "$home/fleet/quota"
rc=0
run prune --now "$NOW" >/dev/null 2>&1 || rc=$?
chmod 700 "$home/fleet/quota"
[ "$rc" = 6 ] || fail "prune over an unsearchable store exited $rc, not 6"
for pos in vendor hold; do
  new_home "symlink-resume-$pos"
  mkdir -p "$home/fleet/quota" "$tmp/resume-link-$pos"
  case $pos in
    vendor) ln -s "$tmp/resume-link-$pos" "$home/fleet/quota/sample-cli" ;;
    hold)
      mkdir -p "$home/fleet/quota/sample-cli"
      ln -s "$tmp/resume-link-$pos/absent" "$home/fleet/quota/sample-cli/hold.tsv"
      ;;
  esac
  rc=0
  run resume --vendor sample-cli --now "$NOW" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 6 ] || fail "symlink: resume through a planted $pos link exited $rc, not 6"
done
pass "prune and resume refuse a symlink in the store"

# A linked push record could carry the hold's own time and silence its push.
new_home symlink-pushed
mkdir -p "$home/fleet/quota/sample-cli"
printf '%s\n' "$NOW" >"$tmp/pushed-target"
ln -s "$tmp/pushed-target" "$home/fleet/quota/sample-cli/pushed"
rc=0
run hold --vendor sample-cli --unit spec-a:task-1 --step panel --reason r --now "$NOW" >/dev/null 2>&1 || rc=$?
[ "$rc" = 6 ] || fail "symlink: a hold beside a linked push record exited $rc, not 6"
pass "a hold refuses a linked push record"

# A file where the store or a vendor's directory belongs hides every hold.
for pos in store vendor; do
  for verb in status resume; do
    new_home "nondir-$pos-$verb"
    case $pos in
      store)
        mkdir -p "$home/fleet"
        : >"$home/fleet/quota"
        ;;
      vendor)
        mkdir -p "$home/fleet/quota"
        : >"$home/fleet/quota/sample-cli"
        ;;
    esac
    rc=0
    run "$verb" --vendor sample-cli --now "$NOW" >/dev/null 2>&1 || rc=$?
    [ "$rc" = 6 ] || fail "non-directory: $verb over a file at the $pos path exited $rc, not 6"
  done
done
for pos in store vendor; do
  for verb in status prune; do
    new_home "nondir-all-$pos-$verb"
    case $pos in
      store)
        mkdir -p "$home/fleet"
        : >"$home/fleet/quota"
        ;;
      vendor)
        mkdir -p "$home/fleet/quota"
        : >"$home/fleet/quota/sample-cli"
        ;;
    esac
    rc=0
    run "$verb" --now "$NOW" >/dev/null 2>&1 || rc=$?
    [ "$rc" = 6 ] || fail "non-directory: $verb (every vendor) over a file at the $pos path exited $rc, not 6"
  done
done
pass "a file at the store or vendor path is refused"

# A ledger that is not a regular file is never skipped as though absent.
new_home prune-ledger-dir
mkdir -p "$home/fleet/quota/sample-cli/ledger.tsv"
rc=0
run prune --now "$NOW" >/dev/null 2>&1 || rc=$?
[ "$rc" = 6 ] || fail "prune over a directory at ledger.tsv exited $rc, not 6"
new_home prune-ledger-fifo
mkdir -p "$home/fleet/quota/sample-cli"
mkfifo "$home/fleet/quota/sample-cli/ledger.tsv"
rc=0
run prune --vendor sample-cli --now "$NOW" >/dev/null 2>&1 || rc=$?
[ "$rc" = 6 ] || fail "prune over a FIFO at ledger.tsv exited $rc, not 6"
pass "prune refuses a ledger that is not a regular file"

# The push is reserved under the vendor's lock, so joiners racing a relay that
# drains the first marker still push one hold once.
new_home push-race
relayed="$tmp/push-race-relayed"
: >"$relayed"
(
  while [ -d "$tmp" ] && [ ! -e "$tmp/push-race-done" ]; do
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
      PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
      /bin/sh "$repo_root/scripts/fleet-attention.sh" relay >>"$relayed" 2>/dev/null || :
  done
) &
relay_pid=$!
bg_loop=$relay_pid
pids=""
for u in $units; do
  run hold --vendor sample-reviewer --unit "$u" --step bot-review --reason quota --now "$NOW" >/dev/null 2>&1 &
  pids="$pids $!"
done
for p in $pids; do
  wait "$p" || :
done
: >"$tmp/push-race-done"
wait "$relay_pid" || :
bg_loop=""
PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
  /bin/sh "$repo_root/scripts/fleet-attention.sh" relay >>"$relayed" 2>/dev/null || :
n=$(grep -c "quota-hold-sample-reviewer-$NOW" "$relayed" || :)
[ "$n" = 1 ] || fail "push race: one hold was pushed $n times"
pass "joiners racing a relay push one hold once"

# A push that fails releases its reservation, so the next joiner pushes.
new_home push-fail
good_cfg=$core_cfg
core_cfg="$tmp/push-fail-core.yml"
printf 'notification_channel: not-a-channel\nquota_ledger_retention_days: 90\n' >"$core_cfg"
rc=0
run hold --vendor sample-cli --unit spec-a:task-1 --step panel --reason r --now "$NOW" >/dev/null 2>&1 || rc=$?
core_cfg=$good_cfg
[ "$rc" = 3 ] || fail "push fail: a hold whose push failed exited $rc, not 3"
[ ! -e "$home/fleet/quota/sample-cli/pushed" ] || fail "push fail: the failed push left its reservation"
run hold --vendor sample-cli --unit spec-b:task-2 --step panel --reason r --now "$NOW" >/dev/null 2>&1 || fail "push fail: the next hold failed"
[ -n "$(ls -A "$home/fleet/attention/push" 2>/dev/null)" ] || fail "push fail: the next joiner did not push"
pass "a failed push releases its reservation"

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
printf '%s\n' "$render" | grep -q "^    sample-reviewer: held since .* (1 unit), reset $real_reset_iso; reason: quota used up$" \
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

new_home stats-noreset
real=$(date +%s)
run hold --vendor sample-cli --unit spec-a:task-1 --step panel --reason "quota" --now $((real - 10)) >/dev/null 2>&1 || fail "stats-noreset fixture: hold failed"
run hold --vendor sample-cli --unit spec-b:task-1 --step panel --reason "quota" --now $((real - 5)) >/dev/null 2>&1 || fail "stats-noreset fixture: hold failed"
printf 'quota_ledger_retention_days: 30\n' >"$local_cfg"
render=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
  /bin/sh "$FSTATS" render 2>/dev/null) || fail "fleet-stats render (no reset) exited non-zero"
: >"$local_cfg"
printf '%s\n' "$render" | grep -q "^    sample-cli: held since .* (2 units), no stated reset; reason: quota$" \
  || fail "render: a held vendor with no stated reset does not say so: $render"
printf '%s\n' "$render" | grep -q "over 30d: 0 requests, 0 answers, 0 refusals, 2 holds, 0 resumes" \
  || fail "render: the counts do not name the configured retention: $render"
pass "the render names a missing reset, plural units, and the configured retention"

# A store status cannot read fails closed: never a held vendor rendered clear
# or missing.
if [ "$(id -u)" = 0 ]; then
  echo "skip: unreadable-store checks (root reads through mode 000)"
else
  new_home stats-unreadable
  run hold --vendor sample-reviewer --unit spec-a:task-1 --step bot-review --reason "quota" --now "$NOW" >/dev/null 2>&1 || fail "unreadable fixture: hold failed"
  qs="$home/fleet/quota"
  for f in "$qs/sample-reviewer/hold.tsv" "$qs/sample-reviewer/ledger.tsv" "$qs/sample-reviewer" "$qs"; do
    mode=600
    [ -f "$f" ] || mode=700
    chmod 000 "$f"
    rc=0
    run status --now "$NOW" >/dev/null 2>&1 || rc=$?
    render=$(PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
      PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
      /bin/sh "$FSTATS" render 2>/dev/null) || render="(render exited non-zero)"
    chmod "$mode" "$f"
    [ "$rc" = 6 ] || fail "status over an unreadable ${f#"$qs"/} exited $rc, not 6"
    printf '%s\n' "$render" | grep -q '^  vendors:        unknown$' || fail "render over an unreadable ${f#"$qs"/} is not unknown: $render"
  done
  for f in "$qs/sample-reviewer" "$qs"; do
    chmod 000 "$f"
    rc=0
    run status --vendor sample-reviewer --now "$NOW" >/dev/null 2>&1 || rc=$?
    rrc=0
    run resume --vendor sample-reviewer --now "$NOW" >/dev/null 2>&1 || rrc=$?
    chmod 700 "$f"
    [ "$rc" = 6 ] || fail "status --vendor under an unsearchable ${f#"$qs"} exited $rc, not 6"
    [ "$rrc" = 6 ] || fail "resume under an unsearchable ${f#"$qs"} exited $rrc, not 6"
  done
  grep -q "${TAB}spec-a:task-1${TAB}" "$qs/sample-reviewer/hold.tsv" || fail "a refused resume released the vendor"
  pass "status and resume fail closed over an unreadable or unsearchable store"
fi

# A stated reset of 0 is still a stated reset in the status view.
new_home reset-zero
run hold --vendor sample-cli --unit spec-a:task-1 --step panel --reason "quota" --reset 0 --now "$NOW" >/dev/null 2>&1 || fail "reset-zero fixture: hold failed"
st=$(run status --vendor sample-cli --now "$NOW") || fail "status exited non-zero (--vendor sample-cli)"
printf '%s\n' "$st" | grep -q "^vendor${TAB}sample-cli${TAB}held${TAB}${NOW}${TAB}0${TAB}1${TAB}" \
  || fail "status dropped a stated reset of 0"
pass "a stated reset of 0 reads the same in status as in the push"

# --- 8. The fleet home is outside the repository's tracked tree -------------
# The default resolution, with every override unset: a write lands under the
# user's Claude directory, never under the repository.
user_home="$tmp/default-user"
mkdir -p "$user_home/.claude/planwright"
printf '{"name": "planwright"}\n' >"$user_home/.claude/planwright/plugin.json"
default_run() {
  env -u PLANWRIGHT_FLEET_STATE_DIR -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR HOME="$user_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="$local_cfg" "$@"
}
default_home=$(default_run /bin/sh "$repo_root/scripts/fleet-state.sh" root) || fail "cannot resolve the default fleet home"
case $default_home/ in
  "$repo_root"/*) fail "the default fleet home sits inside the repository: $default_home" ;;
  "$user_home"/*) ;;
  *) fail "the default fleet home is not under the user's home: $default_home" ;;
esac
default_run /bin/sh "$QH" record --vendor sample-cli --event request --now "$NOW" || fail "a record under the default home failed"
[ -f "$default_home/quota/sample-cli/ledger.tsv" ] || fail "the default-home record did not land under $default_home"
inherited_home=$(fleet_home_inherited)
for h in "$default_home" "$inherited_home"; do
  [ -n "$h" ] || continue
  case $h/ in
    "$repo_root"/*) fail "the fleet home sits inside the repository: $h" ;;
  esac
done
tracked=$(git -C "$repo_root" ls-files -- "*quota*/ledger.tsv" "*quota*/hold.tsv")
[ -z "$tracked" ] || fail "a ledger or hold file is tracked: $tracked"
pass "the ledger lives outside the repository's tracked tree"

echo "all quota-hold tests passed"
