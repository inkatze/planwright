#!/bin/bash
# Tests for the registry's LIVE WRITER and the dispatch owner token
# (fleet-lifecycle-closure Task 3; D-12, REQ-E1.1, REQ-E1.2, REQ-E1.4,
# REQ-D1.5, REQ-K1.4).
#
# The registry had a primitive and no writer: `fleet-state.sh register` existed,
# no dispatch path called it, and the record it wrote (ts/worker/scope) carried
# nothing a close verb could act on. Task 3 gives the primitive the fields
# REQ-E1.2 names, gives every record an owner token so two towers are never
# confused for one another (REQ-D1.5), and wires registration into every
# dispatch seam through one helper (scripts/fleet-register.sh) so there is no
# second store and no second resolution path.
#
# Coverage (mapped to the task Done-when):
#   a1 (REQ-E1.2): the extended record round-trips all five fields plus the
#      owner token, in the declared column order.
#   a2 (REQ-D1.5 compat): an unsupplied optional field writes the `-` sentinel,
#      and the legacy two-argument form still writes a well-formed record — an
#      absent owner reads unknown-owner rather than tearing the record.
#   a3 (REQ-D1.5, REQ-K1.4): a malformed owner token is REFUSED at write and
#      nothing is appended.
#   a4 (REQ-K1.4): a malformed backend, state directory, or death handle is
#      refused before any write; a relative or traversing state dir never
#      reaches the record.
#   a5 (REQ-D1.8): `none` is an admissible death handle — the print rung spawns
#      no process, and that fact is recorded rather than left blank.
#   b1 (REQ-D1.5): two dispatches under distinct tower identities produce
#      records distinguishable by owner token.
#   b2 (REQ-D1.5): the helper resolves the owner token from the presence
#      surface, and honors the pre-resolved env-carried token when a seam has
#      no identity flags.
#   b3 (REQ-D1.5 compat): with no identity resolvable the record is still
#      written, with the absent-token sentinel and a visible note.
#   b4 (REQ-E1.4): a failing registry write warns visibly and reports failure
#      through its own exit — the seams ignore that exit, so a dispatch never
#      fails on it.
#   b5 (REQ-K1.4): the helper refuses a hostile handle before it reaches the
#      store.
#   c1 (REQ-E1.1): the seam-coverage manifest — every dispatch seam registers,
#      and discovery over scripts/ finds no seam missing from the manifest, so
#      the requirement does not silently decay as seams are added.
#   c2 (REQ-E1.1, REQ-E1.2): the headless rung registers a complete record.
#   c3 (REQ-E1.1, REQ-E1.2): the stream-json rung registers a complete record.
#   c4 (REQ-E1.1, REQ-D1.8): the offload print rung registers its deferred
#      launch, and a registry-write failure leaves the dispatch successful.
#   c5 (REQ-E1.1): the worktree seam registers at dispatch; its create-only
#      arm does not (the caller owns that launch and its record).
#   d1 (REQ-E1.1, REQ-D1.5): fleet-status.sh renders the extended registry as
#      PRESENT, attributes each record's owner, and classifies a legacy
#      ownerless record unknown-owner.
#
# Hermetic: every case pins PLANWRIGHT_FLEET_STATE_DIR at a temp home, so no
# case touches the developer's real fleet state. Runs standalone under
# /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-registration.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
FS="$REPO_ROOT/scripts/fleet-state.sh"
FR="$REPO_ROOT/scripts/fleet-register.sh"
FDH="$REPO_ROOT/scripts/fleet-dispatch-headless.sh"
FSJ="$REPO_ROOT/scripts/fleet-streamjson.sh"
FOD="$REPO_ROOT/scripts/offload-dispatch.sh"
FDW="$REPO_ROOT/scripts/fleet-dispatch-worktree.sh"
FST="$REPO_ROOT/scripts/fleet-status.sh"

rc=0
case_rc=0
skips=0
cases=0
fail() {
  # Both streams, deliberately: the per-case ledger goes to stdout, so a
  # failure that only reached stderr would leave a reader of that ledger unable
  # to tell a failed case from one that never ran.
  echo "not ok: $1"
  echo "FAIL: $1" >&2
  rc=$((rc + 1))
}

# ok <id> <text> — announce a case only when it added no failure of its own,
# so a green line never sits under a red one. Called exactly once per case.
ok() {
  cases=$((cases + 1))
  [ "$rc" = "$case_rc" ] && echo "ok $1: $2"
  case_rc=$rc
}

# skip <id> <reason> — a skip is NOT a pass and does not print like one. Skips
# are counted so the floor below can refuse a run that quietly exercised
# nothing; an environment that cannot run a case is a legitimate outcome, an
# environment that silently ran none is not.
skip() {
  cases=$((cases + 1))
  skips=$((skips + 1))
  echo "skip $1: $2"
  case_rc=$rc
}

for s in "$FS" "$FR"; do
  [ -x "$s" ] || {
    echo "FAIL: $s missing or not executable" >&2
    exit 1
  }
done

tmp=$(cd "$(mktemp -d)" && pwd -P)
cleanup() {
  for pf in "$tmp"/state*/*/pid "$tmp"/sj-*/*/supervisor.pid; do
    [ -f "$pf" ] || continue
    p=$(cat "$pf" 2>/dev/null) || continue
    case $p in '' | *[!0-9]*) continue ;; esac
    kill -9 "$p" 2>/dev/null
  done
  rm -rf "$tmp"
}
trap cleanup EXIT
tab=$(printf '\t')

# A fleet home per case, so one case's records never leak into another's.
home() {
  h="$tmp/fleet-$1"
  mkdir -p "$h"
  printf '%s\n' "$h"
}

# fs_at <home> <args...> — the register primitive against a pinned fleet home,
# with every other resolution knob stripped so the case is reproducible.
fs_at() {
  fa_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u PLANWRIGHT_ROOT \
    PLANWRIGHT_FLEET_STATE_DIR="$fa_home" /bin/sh "$FS" "$@"
}

# fr_at <home> <args...> — the seam helper against a pinned fleet home.
fr_at() {
  fr_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u PLANWRIGHT_ROOT \
    -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID \
    -u PLANWRIGHT_TOWER_PID -u PLANWRIGHT_TOWER_CHECKOUT \
    PLANWRIGHT_FLEET_STATE_DIR="$fr_home" /bin/sh "$FR" "$@"
}

# col <home> <n> — the nth column of the sole registry record.
col() {
  cut -f"$2" "$1/registry"
}

# ---------------------------------------------------------------------------
# a1 — the extended record round-trips all five fields plus the owner token.
# ---------------------------------------------------------------------------
h=$(home a1)
fs_at "$h" register worker-alpha spec-a:1 \
  --owner p4242.t99.c17 \
  --backend headless-oneshot \
  --state-dir "$tmp/unit-a1" \
  --death-handle "process 4242" >/dev/null 2>&1 \
  || fail "a1: extended register exited non-zero"
if [ -f "$h/registry" ]; then
  n=$(awk -F"$tab" 'END { print NR }' "$h/registry")
  [ "$n" = 1 ] || fail "a1: expected one record, got $n"
  nf=$(awk -F"$tab" '{ print NF }' "$h/registry")
  [ "$nf" = 7 ] || fail "a1: expected 7 columns, got $nf"
  [ "$(col "$h" 2)" = worker-alpha ] || fail "a1: column 2 is not the handle"
  [ "$(col "$h" 3)" = "spec-a:1" ] || fail "a1: column 3 is not the scope"
  [ "$(col "$h" 4)" = p4242.t99.c17 ] || fail "a1: column 4 is not the owner token"
  [ "$(col "$h" 5)" = headless-oneshot ] || fail "a1: column 5 is not the backend"
  [ "$(col "$h" 6)" = "$tmp/unit-a1" ] || fail "a1: column 6 is not the state dir"
  [ "$(col "$h" 7)" = "process 4242" ] || fail "a1: column 7 is not the death handle"
else
  fail "a1: no registry written"
fi
ok a1 "the record carries handle, scope, owner, backend, state dir, death handle"

# ---------------------------------------------------------------------------
# a2 — absent optional fields write the sentinel; the legacy form still works.
# ---------------------------------------------------------------------------
h=$(home a2)
fs_at "$h" register worker-legacy spec-b >/dev/null 2>&1 \
  || fail "a2: the legacy two-argument form exited non-zero"
if [ -f "$h/registry" ]; then
  nf=$(awk -F"$tab" '{ print NF }' "$h/registry")
  [ "$nf" = 7 ] || fail "a2: legacy record is not padded to 7 columns (got $nf)"
  for c in 4 5 6 7; do
    [ "$(col "$h" "$c")" = "-" ] \
      || fail "a2: column $c is not the absent sentinel, got '$(col "$h" "$c")'"
  done
else
  fail "a2: no registry written for the legacy form"
fi
ok a2 "an unsupplied field writes the absent sentinel; the legacy form still writes"

# ---------------------------------------------------------------------------
# a3 — a malformed owner token is refused at write, and nothing is appended.
# ---------------------------------------------------------------------------
h=$(home a3)
for bad in "../../etc/passwd" "tower one" "-leading-dash" \
  "$(printf 'ow\tner')" "$(printf 'ow\nner')"; do
  out=$(fs_at "$h" register worker-x spec-x --owner "$bad" 2>&1)
  st=$?
  [ "$st" = 2 ] || fail "a3: owner '$bad' was not refused (exit $st)"
  printf '%s' "$out" | grep -qi 'owner' \
    || fail "a3: the refusal for '$bad' does not name the owner field"
done
if [ -f "$h/registry" ]; then
  grep -q passwd "$h/registry" && fail "a3: a refused owner token reached the registry"
fi
ok a3 "a malformed owner token is refused at write"

# ---------------------------------------------------------------------------
# a4 — a malformed backend, state dir, or death handle is refused before write.
# ---------------------------------------------------------------------------
h=$(home a4)
for bad in "Headless" "-tmux" "tmux;rm" "$(printf 'tm\tux')"; do
  st=0
  fs_at "$h" register worker-y spec-y --backend "$bad" >/dev/null 2>&1 || st=$?
  [ "$st" = 2 ] || fail "a4: backend '$bad' was not refused"
done
for bad in "relative/dir" "/etc/../etc/passwd" "/a/../../b" "$(printf '/a\tb')"; do
  st=0
  fs_at "$h" register worker-y spec-y --state-dir "$bad" >/dev/null 2>&1 || st=$?
  [ "$st" = 2 ] || fail "a4: state dir '$bad' was not refused"
done
# `timeout` is not an evidence class at all (REQ-A1.7): the record must not be
# able to carry a pseudo-evidence handle a later reaper would then honor.
for bad in "timeout 30" "process abc" "process " "tmux-window one" \
  "tmux-window a:b c" "silence"; do
  st=0
  fs_at "$h" register worker-y spec-y --death-handle "$bad" >/dev/null 2>&1 || st=$?
  [ "$st" = 2 ] || fail "a4: death handle '$bad' was not refused"
done
[ -f "$h/registry" ] && fail "a4: a refused register wrote a record anyway"
ok a4 "malformed backend, state dir, and death handle are refused before any write"

# ---------------------------------------------------------------------------
# a5 — `none` is an admissible death handle (the print rung, REQ-D1.8).
# ---------------------------------------------------------------------------
h=$(home a5)
fs_at "$h" register print-1 offload --backend print --death-handle none >/dev/null 2>&1 \
  || fail "a5: the print rung's none death handle was refused"
[ "$(col "$h" 7)" = none ] || fail "a5: the none death handle did not round-trip"
ok a5 "a rung that spawns no process records that fact rather than a blank"

# ---------------------------------------------------------------------------
# b1 — two distinct tower identities produce distinguishable owner tokens.
# ---------------------------------------------------------------------------
h=$(home b1)
# Two live pids standing in for two towers; the composite identity pins each
# one's start time, so the derived tokens differ.
sleep 30 &
t1=$!
sleep 30 &
t2=$!
fr_at "$h" --handle w-b1-one --scope spec-b1:1 --backend tmux \
  --pid "$t1" --checkout "$REPO_ROOT" >/dev/null 2>&1 \
  || fail "b1: the first registration exited non-zero"
fr_at "$h" --handle w-b1-two --scope spec-b1:2 --backend tmux \
  --pid "$t2" --checkout "$REPO_ROOT" >/dev/null 2>&1 \
  || fail "b1: the second registration exited non-zero"
kill "$t1" "$t2" 2>/dev/null
wait "$t1" 2>/dev/null
wait "$t2" 2>/dev/null
if [ -f "$h/registry" ]; then
  owners=$(cut -f4 "$h/registry" | sort -u | wc -l | tr -d ' ')
  [ "$owners" = 2 ] || fail "b1: expected 2 distinct owner tokens, got $owners"
  cut -f4 "$h/registry" | grep -q '^-$' \
    && fail "b1: an identity that resolved was recorded as absent"
else
  fail "b1: no registry written"
fi
ok b1 "two tower identities produce records distinguishable by owner token"

# ---------------------------------------------------------------------------
# b2 — the pre-resolved env-carried token is honored when a seam has no flags.
# ---------------------------------------------------------------------------
h=$(home b2)
env PLANWRIGHT_TOWER_ID=p777.t1.c2 PLANWRIGHT_FLEET_STATE_DIR="$h" \
  /bin/sh "$FR" --handle w-b2 --scope spec-b2:1 --backend print >/dev/null 2>&1 \
  || fail "b2: registration with an env-carried token exited non-zero"
[ "$(col "$h" 4)" = p777.t1.c2 ] \
  || fail "b2: the env-carried tower token was not used as the owner"
# A malformed env token must not silently become the owner.
h=$(home b2b)
out=$(env PLANWRIGHT_TOWER_ID="../evil" PLANWRIGHT_FLEET_STATE_DIR="$h" \
  /bin/sh "$FR" --handle w-b2b --scope spec-b2:2 --backend print 2>&1)
# The claim is that a malformed token degrades to unknown-owner WHILE KEEPING
# the record; guarding the assertion on the record existing would let a
# regression that drops the record entirely pass on the stderr grep alone.
if [ -f "$h/registry" ]; then
  [ "$(col "$h" 4)" = "-" ] \
    || fail "b2: a malformed env token was recorded as an owner"
else
  fail "b2: a malformed env token cost the record instead of degrading"
fi
printf '%s' "$out" | grep -qi 'tower' \
  || fail "b2: a malformed env token was dropped without a visible note"
ok b2 "the env-carried tower token is honored, and a malformed one is not"

# ---------------------------------------------------------------------------
# b3 — no resolvable identity still writes the record, with a visible note.
# ---------------------------------------------------------------------------
h=$(home b3)
out=$(fr_at "$h" --handle w-b3 --scope spec-b3:1 --backend print 2>&1)
st=$?
[ "$st" = 0 ] || fail "b3: registration without an identity exited $st"
[ -f "$h/registry" ] || fail "b3: no record written without an identity"
[ "$(col "$h" 4)" = "-" ] || fail "b3: an unresolved owner is not the absent sentinel"
printf '%s' "$out" | grep -qi 'owner' \
  || fail "b3: an unresolved owner token was not noted"
ok b3 "an unresolvable identity still registers, visibly, as unknown-owner"

# ---------------------------------------------------------------------------
# b4 — a failing registry write warns visibly and reports through its own exit.
# ---------------------------------------------------------------------------
h="$tmp/fleet-b4"
: >"$h" # a FILE where the fleet home must be a directory: every write fails
out=$(fr_at "$h" --handle w-b4 --scope spec-b4:1 --backend print 2>&1)
st=$?
[ "$st" != 0 ] || fail "b4: a failed registry write reported success"
[ -n "$out" ] || fail "b4: a failed registry write emitted no warning"
printf '%s' "$out" | grep -qi 'regist' \
  || fail "b4: the warning does not name the registration, got: $out"
ok b4 "a failed registry write warns visibly and reports failure"

# ---------------------------------------------------------------------------
# b5 — a hostile handle is refused before it reaches the store.
# ---------------------------------------------------------------------------
h=$(home b5)
for bad in "../../etc/passwd" "$(printf 'w\tx')" "-dash"; do
  fr_at "$h" --handle "$bad" --scope spec-b5:1 --backend print >/dev/null 2>&1 \
    && fail "b5: hostile handle '$bad' was accepted"
done
if [ -f "$h/registry" ]; then
  grep -q passwd "$h/registry" && fail "b5: a hostile handle reached the registry"
fi
ok b5 "a hostile handle is refused before the store"

# ---------------------------------------------------------------------------
# c1 — the seam-coverage manifest (REQ-E1.1).
#
# The manifest is the expected set of dispatch seams. Discovery is independent
# of it: a dispatch seam is a script under scripts/ that spawns a worker
# (a `claude` launch argv, a tmux worker window, or a printed deferred launch).
# A seam discovered but absent from the manifest, or named by the manifest but
# not calling the registration helper, fails here — so adding a seam without
# registration cannot pass silently.
# ---------------------------------------------------------------------------
manifest="fleet-dispatch-worktree.sh
fleet-dispatch-headless.sh
fleet-streamjson.sh
offload-dispatch.sh"

for seam in $manifest; do
  s="$REPO_ROOT/scripts/$seam"
  [ -f "$s" ] || {
    fail "c1: manifest names $seam, which does not exist"
    continue
  }
  grep -q 'fleet-register\.sh' "$s" \
    || fail "c1: seam $seam does not call the registration helper"
done
# The print rung's deferred-launch record lives in offload-dispatch.sh; assert
# the arm itself registers, not merely that the file mentions the helper.
grep -qE 'register_dispatch .* print' "$REPO_ROOT/scripts/offload-dispatch.sh" \
  || fail "c1: the print rung's deferred launch is not registered as backend print"

# Discovery: worker-spawning sites, found by RULE rather than by the literal
# spelling each seam happens to use today. A pattern set that enumerates the
# current four is a tautology — it re-derives the manifest and can never catch
# the new seam the manifest exists to catch. So: a line that launches the
# worker CLI in a non-interactive mode (`-p`/`--print` with an `--output-format`,
# in either order and with flags in between), or opens a tmux window, or attaches
# a classic tmux session. Same shape as the sibling guard in
# tests/test-dispatch-launch-pin.sh. Comment lines are stripped first: a guard
# that quotes a launch shape in its prose is documenting one, not spawning one.
discovered=$(for f in "$REPO_ROOT"/scripts/*.sh; do
  body=$(grep -v '^[[:space:]]*#' "$f")
  if printf '%s\n' "$body" | grep -qE -- '(^|[[:space:]])(-p|--print)([[:space:]].*)?[[:space:]]--output-format' \
    || printf '%s\n' "$body" | grep -qE -- '--output-format([[:space:]].*)?[[:space:]](-p|--print)([[:space:]]|$)' \
    || printf '%s\n' "$body" | grep -qE -- '--tmux=classic|tmux new-window'; then
    basename "$f"
  fi
done | sort -u)
[ -n "$discovered" ] || fail "c1: seam discovery found nothing (the scan has drifted)"
# Non-vacuity floor, the sibling guard's p1: the scan must still find every
# seam the manifest names. A scan that has drifted into finding nothing (or
# only some) would pass the loop below trivially, which is the failure mode
# that lets an unregistered seam through.
for seam in $manifest; do
  printf '%s\n' "$discovered" | grep -qx "$seam" \
    || fail "c1: discovery no longer finds $seam — the scan has drifted and can pass vacuously"
done
# No exemption arm: nothing this scan discovers today is a non-dispatch site.
# One is added when the scan first finds one, so an exemption can never sit
# here unreached, reading as coverage it does not provide.
for d in $discovered; do
  printf '%s\n' "$manifest" | grep -qx "$d" \
    || fail "c1: $d spawns a worker but is not in the seam-coverage manifest"
done
ok c1 "every dispatch seam registers, and discovery finds none missing"

# ---------------------------------------------------------------------------
# c2 — the headless rung registers a complete record.
# ---------------------------------------------------------------------------
h=$(home c2)
rec="$tmp/rec-c2"
mkdir -p "$rec"
fake="$rec/fake-claude"
cat >"$fake" <<'EOF'
#!/bin/sh
cat >/dev/null
exit 0
EOF
chmod +x "$fake"
wt="$tmp/wt-c2"
mkdir -p "$wt"
out=$(printf 'do the thing' | env -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
  -u PLANWRIGHT_TOWER_SESSION_ID -u PLANWRIGHT_TOWER_PID \
  PLANWRIGHT_TOWER_ID=p1.t2.c3 \
  PLANWRIGHT_FLEET_STATE_DIR="$h" \
  PLANWRIGHT_HEADLESS_CLAUDE="$fake" \
  PLANWRIGHT_HEADLESS_STATE_DIR="$tmp/state-c2" \
  /bin/sh "$FDH" launch spec-c2 3 --worktree "$wt" 2>&1)
st=$?
[ "$st" = 0 ] || fail "c2: headless launch exited $st: $out"
if [ -f "$h/registry" ]; then
  [ "$(col "$h" 2)" = "headless-spec-c2-task-3" ] \
    || fail "c2: the registered handle is not the headless worker handle"
  [ "$(col "$h" 3)" = "spec-c2:3" ] || fail "c2: the registered scope is wrong"
  [ "$(col "$h" 4)" = p1.t2.c3 ] || fail "c2: the owner token was not recorded"
  [ "$(col "$h" 5)" = headless-oneshot ] || fail "c2: the backend is not headless-oneshot"
  [ "$(col "$h" 6)" = "-" ] && fail "c2: no state directory recorded"
  col "$h" 7 | grep -q '^process [0-9][0-9]*$' \
    || fail "c2: the death handle is not a process handle, got '$(col "$h" 7)'"
else
  fail "c2: the headless rung wrote no registry record"
fi
ok c2 "the headless rung registers a complete record"

# ---------------------------------------------------------------------------
# c3 — the stream-json rung registers a complete record.
# ---------------------------------------------------------------------------
if [ -x "$FSJ" ]; then
  h=$(home c3)
  sjrec="$tmp/rec-c3"
  mkdir -p "$sjrec"
  sjfake="$sjrec/fake-claude"
  cat >"$sjfake" <<'EOF'
#!/bin/sh
cat >/dev/null
exit 0
EOF
  chmod +x "$sjfake"
  pf="$tmp/prompt-c3"
  printf 'do the thing\n' >"$pf"
  out=$(env -u PLANWRIGHT_TOWER_SESSION_ID -u PLANWRIGHT_TOWER_PID \
    PLANWRIGHT_TOWER_ID=p9.t8.c7 \
    PLANWRIGHT_FLEET_STATE_DIR="$h" \
    PLANWRIGHT_STREAMJSON_CLI="$sjfake" \
    /bin/sh "$FSJ" launch w-c3 spec-c3:1 --prompt-file "$pf" 2>&1)
  st=$?
  if [ "$st" = 0 ]; then
    if [ -f "$h/registry" ]; then
      [ "$(col "$h" 2)" = w-c3 ] || fail "c3: the registered handle is not the worker"
      [ "$(col "$h" 4)" = p9.t8.c7 ] || fail "c3: the owner token was not recorded"
      [ "$(col "$h" 5)" = stream-json-persistent ] \
        || fail "c3: the backend is not stream-json-persistent"
      [ "$(col "$h" 6)" = "-" ] && fail "c3: no state directory recorded"
    else
      fail "c3: the stream-json rung wrote no registry record"
    fi
    ok c3 "the stream-json rung registers a complete record"
  else
    ok c3 "skipped (stream-json launch unavailable in this environment)"
  fi
else
  ok c3 "skipped (fleet-streamjson.sh absent)"
fi

# ---------------------------------------------------------------------------
# c4 — the print rung registers its deferred launch, and a registry-write
#      failure leaves the dispatch successful (REQ-E1.4, REQ-D1.8).
# ---------------------------------------------------------------------------
h=$(home c4)
pf="$tmp/prompt-c4"
printf 'a petition\n' >"$pf"
out=$(env PLANWRIGHT_TOWER_ID=p5.t5.c5 PLANWRIGHT_FLEET_STATE_DIR="$h" \
  /bin/sh "$FOD" dispatch print "$pf" 2>/dev/null)
st=$?
[ "$st" = 0 ] || fail "c4: the print dispatch exited $st"
printf '%s\n' "$out" | grep -q "^status${tab}prepared$" \
  || fail "c4: the print dispatch did not report prepared"
if [ -f "$h/registry" ]; then
  [ "$(col "$h" 5)" = print ] || fail "c4: the print record's backend is wrong"
  [ "$(col "$h" 7)" = none ] \
    || fail "c4: the print record does not state that no process exists"
  [ "$(col "$h" 4)" = p5.t5.c5 ] || fail "c4: the print record carries no owner token"
else
  fail "c4: the print rung wrote no registry record"
fi
# The degradation half: an unwritable fleet home must not fail the dispatch,
# and the warning must reach the operator rather than a discarded stream.
broken="$tmp/fleet-c4-broken"
: >"$broken"
outfile="$tmp/c4-out"
errfile="$tmp/c4-err"
env PLANWRIGHT_TOWER_ID=p5.t5.c5 PLANWRIGHT_FLEET_STATE_DIR="$broken" \
  /bin/sh "$FOD" dispatch print "$pf" >"$outfile" 2>"$errfile"
st=$?
[ "$st" = 0 ] || fail "c4: a registry-write failure failed the dispatch (exit $st)"
grep -q "^status${tab}prepared$" "$outfile" \
  || fail "c4: the degraded dispatch did not report prepared"
[ -s "$errfile" ] || fail "c4: a failed registry write emitted no visible warning"
grep -qi 'regist' "$errfile" \
  || fail "c4: the warning does not attribute itself to the registration"
ok c4 "the print rung registers, and a registry-write failure never fails the dispatch"

# ---------------------------------------------------------------------------
# c5 — the worktree seam: the real attach path registers and then supersedes
#      its own record with the death handle; the create-only and dry-run arms
#      register nothing.
#
# The attach is driven with a PATH-stubbed `claude` and a PATH-stubbed `tmux`,
# so the two-phase write and the death-handle discovery are exercised without a
# live session — the path that ships, not just the one a fixture can reach.
# ---------------------------------------------------------------------------
if command -v git >/dev/null 2>&1; then
  mkrepo() {
    mr_d=$1
    mkdir -p "$mr_d"
    git -C "$mr_d" init -q -b main >/dev/null 2>&1
    git -C "$mr_d" config user.email t@example.com
    git -C "$mr_d" config user.name t
    mkdir -p "$mr_d/specs/spec-c5"
    printf 'x\n' >"$mr_d/specs/spec-c5/requirements.md"
    git -C "$mr_d" add -A >/dev/null 2>&1
    git -C "$mr_d" commit -qm init >/dev/null 2>&1
  }
  repo="$tmp/repo-c5"
  mkrepo "$repo"

  # The stub bin dir: a no-op `claude`, and a `tmux` that answers list-panes
  # with a fixture. The fixture's FIRST row is a decoy whose path carries a
  # literal tab and would, under naive positional parsing, present an
  # attacker-chosen session and window as the match. The second row is a
  # pre-existing session (created long before this dispatch) sitting in the
  # very worktree the dispatch targets — the operator's own shell. Only the
  # third, created during this dispatch, may be selected.
  stub="$tmp/bin-c5"
  mkdir -p "$stub"
  printf '#!/bin/sh\nexit 0\n' >"$stub/claude"
  chmod +x "$stub/claude"
  wt5="$repo/.claude/worktrees/task-1"
  cat >"$stub/tmux" <<EOF
#!/bin/sh
case "\$1" in
  list-panes)
    printf '1\tevil-session\t@99\t%s\tdecoy-session\t@98\n' "$wt5"
    printf '1\tstale-session\t@7\t%s\n' "$wt5"
    printf '%s\tworker-session\t@42\t%s\n' "\$(date +%s)" "$wt5"
    ;;
  *) : ;;
esac
exit 0
EOF
  chmod +x "$stub/tmux"

  h=$(home c5)
  out=$(PATH="$stub:$PATH" env PLANWRIGHT_TOWER_ID=p3.t3.c3 \
    PLANWRIGHT_FLEET_STATE_DIR="$h" \
    PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX=1 \
    /bin/sh "$FDW" dispatch spec-c5 1 --repo-root "$repo" 2>&1)
  st=$?
  if [ "$st" = 0 ] && [ -f "$h/registry" ]; then
    [ "$(col "$h" 2 | tail -n 1)" = "tmux-spec-c5-task-1" ] \
      || fail "c5: the registered handle is not the D-36 task identity"
    [ "$(col "$h" 3 | tail -n 1)" = "spec-c5:1" ] || fail "c5: the registered scope is wrong"
    [ "$(col "$h" 4 | tail -n 1)" = p3.t3.c3 ] || fail "c5: the owner token was not recorded"
    [ "$(col "$h" 5 | tail -n 1)" = tmux ] || fail "c5: the backend is not tmux"
    [ "$(col "$h" 6 | tail -n 1)" = "$wt5" ] || fail "c5: the worktree was not recorded as the state dir"
    # Two records: the pre-attach one, then the superseding complete one.
    n5=$(wc -l <"$h/registry" | tr -d ' ')
    [ "$n5" = 2 ] || fail "c5: expected a dispatch record superseded by a complete one, got $n5"
    [ "$(col "$h" 7 | head -n 1)" = "-" ] \
      || fail "c5: the pre-attach record claims a death handle it cannot know yet"
    [ "$(col "$h" 7 | tail -n 1)" = "tmux-window worker-session @42" ] \
      || fail "c5: the death handle is not the session created by this dispatch, got '$(col "$h" 7 | tail -n 1)'"
    grep -q 'evil-session\|decoy-session' "$h/registry" \
      && fail "c5: a tab in the pane path shifted the fields an attacker controls into the record"
    grep -q 'stale-session' "$h/registry" \
      && fail "c5: a session predating the dispatch was adopted as the worker's"
    ok c5 "the worktree seam registers, then supersedes with a positively-matched death handle"
  else
    skip c5 "worktree dispatch unavailable here: $out"
  fi

  # The arms that launch nothing must record nothing: an append-only store has
  # no retraction, so a phantom row is permanent.
  for arm in --no-attach --attach-dry-run; do
    h2=$(home "c5$arm")
    PATH="$stub:$PATH" env PLANWRIGHT_TOWER_ID=p3.t3.c3 \
      PLANWRIGHT_FLEET_STATE_DIR="$h2" \
      PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX=1 \
      /bin/sh "$FDW" dispatch spec-c5 2 --repo-root "$repo" "$arm" >/dev/null 2>&1
    [ -f "$h2/registry" ] \
      && fail "c5: $arm registered a worker it never launched"
    git -C "$repo" worktree remove --force "$repo/.claude/worktrees/task-2" >/dev/null 2>&1
    git -C "$repo" branch -D planwright/spec-c5/task-2 >/dev/null 2>&1
  done
  ok c5b "the create-only and dry-run arms register nothing"
else
  skip c5 "git absent"
  skip c5b "git absent"
fi

# ---------------------------------------------------------------------------
# c6 — the offload tmux rung registers with a death handle built from BOTH
#      halves of the window reference (REQ-E1.1).
# ---------------------------------------------------------------------------
h=$(home c6)
stub6="$tmp/bin-c6"
mkdir -p "$stub6"
cat >"$stub6/tmux" <<'EOF'
#!/bin/sh
case "$1" in
  new-window) printf '@31
' ;;
  display-message) printf 'offload-sess
' ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "$stub6/tmux"
pf6="$tmp/prompt-c6"
printf 'a petition
' >"$pf6"
out=$(PATH="$stub6:$PATH" env PLANWRIGHT_TOWER_ID=p6.t6.c6 \
  PLANWRIGHT_FLEET_STATE_DIR="$h" /bin/sh "$FOD" dispatch tmux "$pf6" 2>/dev/null)
st=$?
if [ "$st" = 0 ] && [ -f "$h/registry" ]; then
  [ "$(col "$h" 2)" = "@31" ] || fail "c6: the tmux window id is not the handle"
  [ "$(col "$h" 5)" = tmux ] || fail "c6: the backend is not tmux"
  [ "$(col "$h" 7)" = "tmux-window offload-sess @31" ] \
    || fail "c6: the death handle is not the session/window pair, got '$(col "$h" 7)'"
  ok c6 "the offload tmux rung registers with a session/window death handle"
else
  skip c6 "offload tmux dispatch unavailable here"
fi

# ---------------------------------------------------------------------------
# c7 — the subagent rung registers through its only seam (REQ-E1.1). Its spawn
#      is harness-native, so `report` is the single point at which such a
#      worker can enter the inventory; a re-report of a tmux handle is not a
#      new dispatch and registers nothing.
# ---------------------------------------------------------------------------
h=$(home c7)
env PLANWRIGHT_TOWER_ID=p7.t7.c7 PLANWRIGHT_FLEET_STATE_DIR="$h" \
  /bin/sh "$FOD" report subagent agent-7 >/dev/null 2>&1 \
  || fail "c7: the subagent report exited non-zero"
if [ -f "$h/registry" ]; then
  [ "$(col "$h" 2)" = agent-7 ] || fail "c7: the subagent handle was not recorded"
  [ "$(col "$h" 5)" = subagent ] || fail "c7: the backend is not subagent"
  [ "$(col "$h" 7)" = none ] \
    || fail "c7: the subagent record does not state that it has no separate process"
else
  fail "c7: the subagent rung wrote no registry record"
fi
h=$(home c7b)
env PLANWRIGHT_TOWER_ID=p7.t7.c7 PLANWRIGHT_FLEET_STATE_DIR="$h" \
  /bin/sh "$FOD" report tmux "@5" >/dev/null 2>&1 \
  || fail "c7: the tmux re-report exited non-zero"
[ -f "$h2/registry" ] 2>/dev/null
[ -f "$h/registry" ] && fail "c7: a re-report registered a second record for one worker"
ok c7 "the subagent rung registers; a re-report does not"

# ---------------------------------------------------------------------------
# e1 — the per-field degrade: one malformed OPTIONAL field costs that column,
#      never the live worker's whole record (REQ-E1.4).
# ---------------------------------------------------------------------------
h=$(home e1)
out=$(fr_at "$h" --handle w-e1 --scope spec-e1:1 --backend tmux \
  --state-dir "relative/not/absolute" --death-handle "timeout 30" 2>&1)
st=$?
[ "$st" = 0 ] || fail "e1: a malformed optional field failed the whole registration (exit $st)"
if [ -f "$h/registry" ]; then
  [ "$(col "$h" 2)" = w-e1 ] || fail "e1: the record did not land"
  [ "$(col "$h" 6)" = "-" ] || fail "e1: the malformed state dir reached the record"
  [ "$(col "$h" 7)" = "-" ] || fail "e1: the malformed death handle reached the record"
else
  fail "e1: one bad optional column cost the whole record"
fi
printf '%s' "$out" | grep -qi 'state-dir' || fail "e1: the dropped state dir was not named"
printf '%s' "$out" | grep -qi 'death-handle' || fail "e1: the dropped death handle was not named"
ok e1 "a malformed optional field is dropped to a blank column, never taking the record"

# ---------------------------------------------------------------------------
# e2 — the reader's sentinel is not a writable value (REQ-D1.5).
# ---------------------------------------------------------------------------
h=$(home e2)
fs_at "$h" register w-e2 spec-e2:1 --owner unknown-owner >/dev/null 2>&1 \
  && fail "e2: the literal reader sentinel was accepted as an owner token"
[ -f "$h/registry" ] && fail "e2: the forged sentinel reached the registry"
ok e2 "unknown-owner cannot be forged as a stored owner token"

# ---------------------------------------------------------------------------
# e3 — over-length tokens are refused at every bounded field (REQ-K1.4).
# ---------------------------------------------------------------------------
h=$(home e3)
long129=$(awk 'BEGIN { s = ""; while (length(s) < 129) s = s "a"; print s }')
long65=$(awk 'BEGIN { s = ""; while (length(s) < 65) s = s "a"; print s }')
long4097=$(awk 'BEGIN { s = ""; while (length(s) < 4097) s = s "a"; print "/" s }')
fs_at "$h" register w-e3 spec-e3:1 --owner "$long129" >/dev/null 2>&1 \
  && fail "e3: an over-length owner token was accepted"
fs_at "$h" register w-e3 spec-e3:1 --backend "$long65" >/dev/null 2>&1 \
  && fail "e3: an over-length backend was accepted"
fs_at "$h" register w-e3 spec-e3:1 --state-dir "$long4097" >/dev/null 2>&1 \
  && fail "e3: an over-length state dir was accepted"
fs_at "$h" register w-e3 spec-e3:1 --death-handle "tmux-window $long129 @1" >/dev/null 2>&1 \
  && fail "e3: an over-length tmux session token was accepted"
[ -f "$h/registry" ] && fail "e3: an over-length token reached the registry"
ok e3 "every bounded field refuses an over-length token"

# ---------------------------------------------------------------------------
# e4 — the bare root is refused as a state directory: a close verb matching
#      processes against `/` would match the operator's whole session.
# ---------------------------------------------------------------------------
h=$(home e4)
fs_at "$h" register w-e4 spec-e4:1 --state-dir / >/dev/null 2>&1 \
  && fail "e4: the filesystem root was accepted as a worker state directory"
ok e4 "the filesystem root is refused as a state directory"

# ---------------------------------------------------------------------------
# e5 — positionals bind by COUNT: an empty argument is a refusal, never a slot
#      the next token slides into.
# ---------------------------------------------------------------------------
h=$(home e5)
fs_at "$h" register w-e5 "" spec-e5:2 >/dev/null 2>&1 \
  && fail "e5: an empty scope let the next argument take its slot"
[ -f "$h/registry" ] && fail "e5: a mis-bound record was written"
ok e5 "an empty positional is refused rather than silently skipped"

# ---------------------------------------------------------------------------
# e6 — a hostile SCOPE is refused at the seam, not only a hostile handle.
# ---------------------------------------------------------------------------
h=$(home e6)
for bad in "../../etc/passwd" "$(printf 's\tx')" "-dash"; do
  fr_at "$h" --handle w-e6 --scope "$bad" --backend print >/dev/null 2>&1 \
    && fail "e6: hostile scope '$bad' was accepted"
done
if [ -f "$h/registry" ]; then
  grep -q passwd "$h/registry" && fail "e6: a hostile scope reached the registry"
fi
ok e6 "a hostile scope is refused before the store"

# ---------------------------------------------------------------------------
# e7 — a diagnostic carrying an escape SEQUENCE cannot drive the terminal.
#      sanitize_printable strips control BYTES; the four printable characters
#      `\`,`0`,`3`,`3` survive it, and `echo` under dash would expand them.
# ---------------------------------------------------------------------------
h=$(home e7)
out=$(env PLANWRIGHT_TOWER_ID='\033[31mRED' PLANWRIGHT_FLEET_STATE_DIR="$h" \
  /bin/sh "$FR" --handle w-e7 --scope spec-e7:1 --backend print 2>&1)
esc=$(printf '\033')
case $out in
  *"$esc"*) fail "e7: a diagnostic expanded an escape sequence onto the terminal" ;;
esac
printf '%s' "$out" | grep -q '033\[31mRED' \
  || fail "e7: the refused token was not reported literally"
ok e7 "diagnostics report untrusted text literally, never as terminal escapes"

# ---------------------------------------------------------------------------
# e8 — an interrupted registration releases the shared fleet lock, rather than
#      wedging every other fleet writer until the stale-break threshold.
# ---------------------------------------------------------------------------
h=$(home e8)
mkdir -p "$h"
# shellcheck disable=SC2016 # the $1/$p expansions are the INNER shell's, by design
env PLANWRIGHT_FLEET_STATE_DIR="$h" /bin/sh -c '
  "$1" register w-e8 spec-e8:1 &
  p=$!
  sleep 0.05
  kill -TERM "$p" 2>/dev/null
  wait "$p" 2>/dev/null
  exit 0
' _ "$FS" >/dev/null 2>&1
# Whether the TERM landed inside the critical section or before it, the lock
# must not be standing afterwards.
[ -L "$h/.fleet.lock" ] && fail "e8: a signalled register left the shared fleet lock held"
env PLANWRIGHT_FLEET_STATE_DIR="$h" /bin/sh "$FS" register w-e8b spec-e8:2 >/dev/null 2>&1 \
  || fail "e8: a later registration could not acquire the lock"
ok e8 "an interrupted registration releases the shared lock"

# ---------------------------------------------------------------------------
# e9 — the --session-id resolution arms (flag and env) reach the presence
#      surface; b1 covers the pid arms.
# ---------------------------------------------------------------------------
h=$(home e9)
uuid=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
fr_at "$h" --handle w-e9 --scope spec-e9:1 --backend print \
  --session-id "$uuid" --checkout "$REPO_ROOT" >/dev/null 2>&1 \
  || fail "e9: the --session-id arm exited non-zero"
[ "$(col "$h" 4)" = "$uuid" ] \
  || fail "e9: the --session-id arm did not resolve to the session identity"
h=$(home e9b)
env -u PLANWRIGHT_TOWER_ID PLANWRIGHT_TOWER_SESSION_ID="$uuid" \
  PLANWRIGHT_TOWER_CHECKOUT="$REPO_ROOT" PLANWRIGHT_FLEET_STATE_DIR="$h" \
  /bin/sh "$FR" --handle w-e9b --scope spec-e9:2 --backend print >/dev/null 2>&1 \
  || fail "e9: the env session-id arm exited non-zero"
[ "$(col "$h" 4)" = "$uuid" ] \
  || fail "e9: the env session-id arm did not resolve to the session identity"
ok e9 "both session-id resolution arms reach the presence surface"

# ---------------------------------------------------------------------------
# d1 — fleet-status.sh renders the extended registry as PRESENT, attributes
#      owners, and classifies a legacy ownerless record unknown-owner.
# ---------------------------------------------------------------------------
if [ -x "$FST" ]; then
  h=$(home d1)
  fs_at "$h" register w-d1-owned spec-d1:1 --owner p11.t2.c3 --backend tmux \
    >/dev/null 2>&1 || fail "d1: could not seed an owned record"
  # A legacy record, written before the record carried an owner column.
  printf '%s\tw-d1-legacy\tspec-d1:2\n' "$(date +%s)" >>"$h/registry"
  out=$(env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR \
    PLANWRIGHT_FLEET_STATE_DIR="$h" /bin/sh "$FST" render 2>&1)
  printf '%s\n' "$out" | grep -qi 'registry' \
    || fail "d1: the status render does not mention the registry source"
  printf '%s\n' "$out" | grep -q "registry=ok" \
    || fail "d1: the registry source does not render as ok with records present"
  printf '%s\n' "$out" | grep -q 'w-d1-owned' \
    || fail "d1: the owned registry worker is not rendered"
  printf '%s\n' "$out" | grep -q 'w-d1-legacy' \
    || fail "d1: the legacy registry worker is not rendered"
  printf '%s\n' "$out" | grep -q 'p11.t2.c3' \
    || fail "d1: the owner token is not surfaced for an owned record"
  printf '%s\n' "$out" | grep -q 'unknown-owner' \
    || fail "d1: a legacy ownerless record is not classified unknown-owner"
  ok d1 "the registry renders present, with owner attribution and unknown-owner"
else
  ok d1 "skipped (fleet-status.sh absent)"
fi

[ "$rc" = 0 ] || {
  echo "$rc assertion(s) failed" >&2
  exit 1
}
# A coverage floor, so a box that can run almost nothing cannot report a green
# run. Skips are legitimate (no git, no usable dispatch path); a run that
# skipped most of its cases is not evidence of anything and says so.
if [ "$skips" -gt 0 ]; then
  echo "note: $skips of $cases case(s) skipped"
fi
[ "$((cases - skips))" -ge 20 ] || {
  echo "only $((cases - skips)) of $cases case(s) actually ran; this run proves too little to pass" >&2
  exit 1
}
echo "all fleet-registration tests passed ($((cases - skips)) of $cases cases ran)"
