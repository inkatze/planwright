#!/bin/bash
# Tests for scripts/mc-kb.sh's writers under contention: one writer per file,
# the lock wait, dead holders released and logged, concurrent appends and
# concurrent reverts (mission-control REQ-K1.5, REQ-D1.7). The rest of the
# knowledge base is tests/test-mc-kb.sh's.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-kb-locks.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-kb.sh" ] || {
  echo "FAIL: scripts/mc-kb.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
holder_pid=''
cleanup() {
  [ -z "$holder_pid" ] || kill "$holder_pid" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
mkdir -p "$repo/specs" "$core/docs"

alpha_block() { # alpha_block [extra lines on stdin]
  {
    printf '%s\n' "mission_control_programs: [alpha]" \
      "program_alpha_repositories: [$repo]" \
      "program_alpha_spec_root: $repo/specs" \
      "program_alpha_duties: [alpha-duty, beta-duty]"
    cat
  } >"$tracked"
}
alpha_block </dev/null
home="$fixhome/.config/planwright/mission-control/alpha"
kb="$home/kb"
month=$(date -u '+%Y-%m')

mc_run mc-kb.sh init --program alpha
expect_rc "init creates the layout" 0
mc_run mc-kb.sh append decisions --program alpha --subject pr-42 --act "approved the plan"
expect_rc "a first decision lands" 0

# ---------------------------------------------------------------------------
# REQ-K1.5: one writer per file; a dead holder's lock is released and logged.
# ---------------------------------------------------------------------------
printf '%s\n' "mission_control_kb_lock_wait: 1" >>"$tracked"
month=$(date -u '+%Y-%m')
seg="$kb/decisions-$month.log"
sleep 60 &
holder_pid=$!
mc_run mc-kb.sh lock --program alpha "decisions-$month.log" --holder "$holder_pid"
expect_rc "a live process claims a file's write lock" 0
token=$OUT
before=$(cat "$seg")
mc_run mc-kb.sh append decisions --program alpha --subject pr-45 --act "under a held lock"
expect_rc "an append under a held lock fails once the wait is spent" 1
expect_err "the refusal names the holder's pid" "$holder_pid"
if [ "$(cat "$seg")" = "$before" ]; then ok "the held segment is untouched"; else fail "an append landed under a held lock"; fi
mc_run mc-kb.sh unlock --program alpha "decisions-$month.log" --token "not-the-token"
expect_rc "a wrong token releases nothing" 1
mc_run mc-kb.sh unlock --program alpha "decisions-$month.log" --token "$token"
expect_rc "the holder releases its lock by token" 0
mc_run mc-kb.sh lock --program alpha "decisions-$month.log" --holder abc
expect_rc "a holder that is not a pid is refused" 2
mc_run mc-kb.sh lock --program alpha "locks-$month.log" --holder "$holder_pid"
expect_rc "the locks log cannot be locked from outside" 2
mc_run mc-kb.sh lock --program alpha "LOCKS-$month.log" --holder "$holder_pid"
expect_rc "nor under another case" 2

mc_run mc-kb.sh lock --program alpha "decisions-$month.log" --holder "$holder_pid"
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null
dead_pid=$holder_pid
holder_pid=''
mc_run mc-kb.sh append decisions --program alpha --subject pr-46 --act "after the holder died"
expect_rc "the next writer releases a dead holder's lock" 0
expect_err "the release is reported" "$dead_pid"
mc_run mc-kb.sh query locks --program alpha --subject "kb/decisions-$month.log"
expect_out "the release is logged by the locked file" "$dead_pid"

sleep 60 &
holder_pid=$!
mc_run mc-kb.sh lock --program alpha index.md --holder "$holder_pid"
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null
holder_pid=''
sleep 60 &
holder_pid=$!
mc_run mc-kb.sh lock --program alpha index.md --holder "$holder_pid"
expect_rc "a lock is claimed over a dead holder" 0
lock_token=$OUT
mc_run mc-kb.sh query locks --program alpha --subject kb/index.md
expect_out "a lock claimed for another process logs the dead holder too" "released a dead holder's lock"
mc_run mc-kb.sh unlock --program alpha index.md --token "$lock_token"
expect_rc "the token printed after a dead-holder release is the lock's own" 0
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null
holder_pid=''

alpha_block <<'EOF'
mission_control_kb_lock_wait: 20
EOF
sleep 60 &
holder_pid=$!
mc_run mc-kb.sh lock --program alpha followups.tsv --holder "$holder_pid"
(
  mc_run mc-kb.sh followup add --program alpha --owner operator --trigger date:2999-12-31 --text "after a wait"
  printf '%s\n' "$RC" >"$tmp/bg.rc"
) &
bg_pid=$!
sleep 4
if [ -L "$kb/followups.tsv.lock" ] && [ ! -e "$tmp/bg.rc" ]; then
  ok "the writer is waiting on a live holder"
else
  fail "the writer was not waiting when the holder died"
fi
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null
wait "$bg_pid" 2>/dev/null
if [ "$(cat "$tmp/bg.rc" 2>/dev/null)" = 0 ]; then ok "a writer waits out a holder that dies during the wait"; else fail "the waiting writer exited $(cat "$tmp/bg.rc" 2>/dev/null)"; fi
mc_run mc-kb.sh query locks --program alpha --subject kb/followups.tsv
expect_out "a holder dying during the wait is logged too" "pid $holder_pid"
holder_pid=''

# A locks log that cannot be written warns, and leaves no lock behind.
month=$(date -u '+%Y-%m')
lseg="$kb/locks-$month.log"
cp "$lseg" "$tmp/locks.keep"
sed 's/released/RELEASED/' "$tmp/locks.keep" >"$lseg"
sleep 60 &
holder_pid=$!
mc_run mc-kb.sh lock --program alpha sources.tsv --holder "$holder_pid"
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null
holder_pid=''
mc_run mc-kb.sh source set --program alpha after-dead --kind living --ref x
expect_rc "a write over a dead holder succeeds when the release cannot be logged" 0
expect_err "it warns that the release went unlogged" "could not be logged"
if [ -L "$lseg.lock" ]; then fail "the locks segment's lock was left behind"; else ok "no lock is left behind on the locks segment"; fi
cp "$tmp/locks.keep" "$lseg"

alpha_block <<'EOF'
mission_control_kb_lock_wait: 60
EOF
for i in 1 2 3 4 5 6 7 8; do
  (mc_run mc-kb.sh append decisions --program alpha --subject concurrent --act "writer $i") &
done
wait
mc_run mc-kb.sh query decisions --program alpha --subject concurrent
n=$(printf '%s\n' "$OUT" | grep -c "${tab}concurrent${tab}writer [1-8]${tab}-${tab}-${tab}none${tab}-\$")
ids=$(printf '%s\n' "$OUT" | cut -f 1 | sort -u | grep -c .)
if [ "$n" -eq 8 ] && [ "$ids" -eq 8 ]; then
  ok "concurrent appends land whole, one line each, never interleaved"
else
  fail "concurrent appends: $n whole lines, $ids distinct ids (want 8 and 8)"
fi
alpha_block </dev/null

# The locks log's own previous holder dead too: both releases are logged, the
# locks segment stays locked until its append is done, and nothing warns.
sleep 60 &
holder_pid=$!
month=$(date -u '+%Y-%m')
mc_run mc-kb.sh lock --program alpha "decisions-$month.log" --holder "$holder_pid"
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null
dead_a=$holder_pid
holder_pid=''
sh -c 'exit 0' &
dead_b=$!
wait "$dead_b" 2>/dev/null
ln -s "$dead_b-0-0-$dead_b-1" "$kb/locks-$month.log.lock"
mc_run mc-kb.sh append decisions --program alpha --subject nested --act "two dead holders"
expect_rc "a write over two dead holders succeeds" 0
case $ERR in
  *"could not be logged"* | *"cannot release"*) fail "a nested release misreported: $ERR" ;;
  *) ok "a release of the locks log's own lock is logged without a false warning" ;;
esac
mc_run mc-kb.sh query locks --program alpha --subject "kb/locks-$month.log"
expect_out "the locks log's own dead holder is logged" "pid $dead_b"
if [ -L "$kb/locks-$month.log.lock" ]; then fail "the locks segment stayed locked"; else ok "the locks segment is released once"; fi
mc_run mc-kb.sh query locks --program alpha --subject "kb/decisions-$month.log"
expect_out "and the file's own dead holder too" "pid $dead_a"

# The lock wait is at least the knob's seconds.
alpha_block <<'EOF'
mission_control_kb_lock_wait: 2
EOF
sleep 60 &
holder_pid=$!
mc_run mc-kb.sh lock --program alpha index.md --holder "$holder_pid"
lock_token=$OUT
mkdir -p "$kb/alpha"
printf 'x\n' >"$kb/alpha/waited.md"
start=$(date -u '+%s')
mc_run mc-kb.sh index-add --program alpha alpha/waited.md "waited"
end=$(date -u '+%s')
expect_rc "an index write under a held lock gives up" 1
if [ $((end - start)) -ge 2 ]; then ok "the writer waited at least the lock wait"; else fail "the writer gave up after $((end - start))s"; fi
mc_run mc-kb.sh unlock --program alpha index.md --token "$lock_token"
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null
holder_pid=''
alpha_block </dev/null

# Concurrent reverts of one entry run its reversal once.
mc_run mc-kb.sh append undo --program alpha --subject pr-50 --act "counted" -- sh -c "printf x >>$tmp/runs"
race_id=$OUT
for i in 1 2 3; do
  (mc_run mc-kb.sh revert --program alpha "$race_id") &
done
wait
if [ "$(cat "$tmp/runs" 2>/dev/null)" = x ]; then ok "concurrent reverts run the reversal once"; else fail "the reversal ran '$(cat "$tmp/runs" 2>/dev/null)' times"; fi

if [ "$failures" -ne 0 ]; then
  echo "test-mc-kb-locks: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-kb-locks: all passed"
