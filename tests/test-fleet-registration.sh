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
fail() {
  echo "FAIL: $1" >&2
  rc=$((rc + 1))
}

# ok <id> <text> — announce a case only when it added no failure of its own,
# so a green line never sits under a red one. Called exactly once per case.
ok() {
  [ "$rc" = "$case_rc" ] && echo "ok $1: $2"
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
if [ -f "$h/registry" ]; then
  [ "$(col "$h" 4)" = "-" ] \
    || fail "b2: a malformed env token was recorded as an owner"
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

# Discovery: worker-spawning sites, found by the launch forms the fleet uses.
# Comment lines are stripped first — a guard that quotes a launch shape in its
# prose is documenting one, not spawning one.
discovered=$(for f in "$REPO_ROOT"/scripts/*.sh; do
  grep -v '^[[:space:]]*#' "$f" \
    | grep -qE -- '--print --output-format|--tmux=classic|tmux new-window|-p --input-format stream-json' \
    && basename "$f"
done | sort -u)
[ -n "$discovered" ] || fail "c1: seam discovery found nothing (the scan has drifted)"
# prompt-eval.sh is the documented non-dispatch harness exemption, matching the
# launch-pin guard's own exemption; fleet-dispatch-env.sh only wraps a launch.
for d in $discovered; do
  case $d in
    prompt-eval.sh | fleet-dispatch-env.sh) continue ;;
  esac
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
ok c4 "the print rung registers, and a registry-write failure never fails the dispatch"

# ---------------------------------------------------------------------------
# c5 — the worktree seam registers at dispatch; the create-only arm does not.
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
  h=$(home c5)
  out=$(env PLANWRIGHT_TOWER_ID=p3.t3.c3 PLANWRIGHT_FLEET_STATE_DIR="$h" \
    PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX=1 \
    /bin/sh "$FDW" dispatch spec-c5 1 --repo-root "$repo" --attach-dry-run 2>&1)
  st=$?
  if [ "$st" = 0 ]; then
    if [ -f "$h/registry" ]; then
      [ "$(col "$h" 3)" = "spec-c5:1" ] || fail "c5: the registered scope is wrong"
      [ "$(col "$h" 4)" = p3.t3.c3 ] || fail "c5: the owner token was not recorded"
      [ "$(col "$h" 5)" = tmux ] || fail "c5: the backend is not tmux"
      [ "$(col "$h" 6)" = "-" ] && fail "c5: the worktree path was not recorded"
    else
      fail "c5: the worktree seam wrote no registry record"
    fi
    # The create-only arm hands the launch to another rung, which owns its own
    # record; registering here too would double-count one unit.
    h2=$(home c5b)
    env PLANWRIGHT_TOWER_ID=p3.t3.c3 PLANWRIGHT_FLEET_STATE_DIR="$h2" \
      PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX=1 \
      /bin/sh "$FDW" dispatch spec-c5 2 --repo-root "$repo" --no-attach >/dev/null 2>&1
    [ -f "$h2/registry" ] && fail "c5: the create-only arm registered a worker it does not launch"
    ok c5 "the worktree seam registers at dispatch; the create-only arm does not"
  else
    ok c5 "skipped (worktree dispatch unavailable here: $out)"
  fi
else
  ok c5 "skipped (git absent)"
fi

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
  printf '%s\n' "$out" | grep -qiE 'registry[^a-z]+absent' \
    && fail "d1: the registry renders as absent with records present"
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
echo "all fleet-registration tests passed"
