#!/bin/bash
# Every reader of the worker registry parses a three-column (pre-owner), a
# seven-column (pre-identity), and a nine-column (current) row (fleet-messaging
# Task 4; D-8, REQ-B1.1). The readers were re-derived by grep over scripts/ for
# `fleet-state.sh registry` and the registry file; the flight readers and the
# attention reconcile, whose fixtures need a git checkout, are covered in their
# own suites (tests/test-flight-sweep.sh, tests/test-flight-lifecycle.sh,
# tests/test-fleet-attention-reconcile.sh). A reader that surfaces the two
# added columns is asserted on their values by position; one that surfaces
# neither is asserted on tolerance: the row parses and its other fields read
# as they did.
#   a1  fleet-status.sh: every row renders, owners attributed, the
#       three-column row as unknown-owner
#   a2  fleet-registry-reconcile.sh: the seven- and nine-column rows are
#       judged on their death handles; the three-column one is unjudged
#   a3  fleet-stuck-detector.sh: the registry evidence reads present with the
#       recorded backend for seven and nine columns, and present for three
#   a4  fleet-state.sh: a re-register of a nine-column row's fields writes
#       nothing; retire closes a seven- and a nine-column row alike
#   a5  fleet-register.sh --retire-marker closes a nine-column row
#   a6  fleet-messaging.sh: notice-read matches the nine-column row by its
#       name column, finds no name in the shorter rows, and binds the last
#       record (send --to-worker's inbox column: tests/test-fleet-messaging.sh)
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd -P)
SC="$REPO_ROOT/scripts"

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}
ok() { echo "ok $1"; }

tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
TAB=$(printf '\t')

core_cfg="$tmp/core-defaults.yml"
cp "$REPO_ROOT/config/defaults.yml" "$core_cfg"
mkdir -p "$tmp/cfg-repo/.claude"

# A dead pid: a short-lived child, reaped.
sh -c 'exit 0' &
dead=$!
wait "$dead"

run() {
  r_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u PLANWRIGHT_ROOT \
    -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID -u PLANWRIGHT_TOWER_PID \
    -u PLANWRIGHT_TOWER_CHECKOUT -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    PLANWRIGHT_FLEET_STATE_DIR="$r_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_REPO_ROOT="$tmp/cfg-repo" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" PLANWRIGHT_LOCAL_CONFIG="" \
    PLANWRIGHT_ORACLE_CLAUDE="$tmp/oracle" \
    "$@" </dev/null
}

printf '#!/bin/sh\nprintf "[]\\n"\n' >"$tmp/oracle"
chmod +x "$tmp/oracle"

# mixed_home <case> — a fleet home holding one row of each arity.
mixed_home() {
  mh=$tmp/fleet-$1
  mkdir -p "$mh"
  chmod 700 "$mh"
  {
    printf '100\tw3\tdemo:3\n'
    printf '101\tw7\tdemo:7\tp7.t7.c7\theadless-oneshot\t%s\tprocess %s\n' "$tmp/sd7" "$dead"
    printf '102\tw9\tdemo:9\tp9.t9.c9\theadless-oneshot\t%s\tprocess %s\tn9\tb9.sock\n' "$tmp/sd9" "$dead"
  } >"$mh/registry"
  printf '%s\n' "$mh"
}

line() {
  printf '%s\n' "$1" | awk -F"$TAB" -v t="$2" -v k="$3" '$1 == t && $2 == k { print; exit }'
}

# --- a1 -----------------------------------------------------------------------
f0=$fails
h=$(mixed_home a1)
out=$(run "$h" /bin/sh "$SC/fleet-status.sh" merge 2>/dev/null) || fail "a1: fleet-status merge exited non-zero"
for w in w3 w7 w9; do
  [ -n "$(line "$out" worker "$w")" ] || fail "a1: no worker line for $w: $out"
done
[ "$(line "$out" worker w3 | awk -F"$TAB" '{ print $NF }')" = unknown-owner ] || fail "a1: the three-column row is not unknown-owner"
[ "$(line "$out" worker w7 | awk -F"$TAB" '{ print $3 "|" $NF }')" = "demo:7|p7.t7.c7" ] || fail "a1: the seven-column row read wrong: $(line "$out" worker w7)"
[ "$(line "$out" worker w9 | awk -F"$TAB" '{ print $3 "|" $NF }')" = "demo:9|p9.t9.c9" ] || fail "a1: the nine-column row read wrong: $(line "$out" worker w9)"
[ "$fails" = "$f0" ] && ok "a1 fleet-status.sh renders all three arities"

# --- a2 -----------------------------------------------------------------------
f0=$fails
h=$(mixed_home a2)
mkdir -p "$h/dispatch-markers"
printf 'w3\tdemo:3\t-\theadless-oneshot\t-\t-\n' >"$h/dispatch-markers/w3"
printf 'w7\tdemo:7\tp7.t7.c7\theadless-oneshot\t%s\tprocess %s\n' "$tmp/sd7" "$dead" >"$h/dispatch-markers/w7"
printf 'w9\tdemo:9\tp9.t9.c9\theadless-oneshot\t%s\tprocess %s\n' "$tmp/sd9" "$dead" >"$h/dispatch-markers/w9"
out=$(run "$h" /bin/sh "$SC/fleet-registry-reconcile.sh" 2>"$tmp/err") || fail "a2: the reconcile exited non-zero: $(cat "$tmp/err")"
[ -n "$(line "$out" retire w7)" ] || fail "a2: the seven-column row was not judged dead: $out"
[ -n "$(line "$out" retire w9)" ] || fail "a2: the nine-column row was not judged dead: $out"
[ -z "$(line "$out" retire w3)" ] || fail "a2: the three-column row was retired on no evidence"
[ "$(awk -F"$TAB" '$2 == "w9" && $NF == "closed"' "$h/registry" | cut -f2-7)" = \
  "$(printf 'w9\tdemo:9\tp9.t9.c9\theadless-oneshot\t%s\tprocess %s' "$tmp/sd9" "$dead")" ] \
  || fail "a2: the nine-column row's retirement does not carry its fields"
[ "$fails" = "$f0" ] && ok "a2 fleet-registry-reconcile.sh judges all three arities"

# --- a3 -----------------------------------------------------------------------
f0=$fails
h=$(mixed_home a3)
for w in w3 w7 w9; do
  out=$(run "$h" /bin/sh "$SC/fleet-stuck-detector.sh" classify "$w" 2>/dev/null)
  [ "$(printf '%s\n' "$out" | awk -F"$TAB" '$1 == "evidence" && $3 == "registry" { print $4 }')" = present ] \
    || fail "a3: the registry evidence for $w is not present: $out"
  printf '%s\n' "$out" | grep -q "registry-malformed" && fail "a3: the $w row read as malformed"
done
out=$(run "$h" /bin/sh "$SC/fleet-stuck-detector.sh" classify w9 2>/dev/null)
[ "$(printf '%s\n' "$out" | awk -F"$TAB" '$1 == "evidence" && $3 == "backend" { print $4 }')" = headless-oneshot ] \
  || fail "a3: the nine-column backend did not read: $out"
[ "$fails" = "$f0" ] && ok "a3 fleet-stuck-detector.sh reads all three arities"

# --- a4 -----------------------------------------------------------------------
f0=$fails
h=$(mixed_home a4)
n=$(grep -c . "$h/registry")
rc=0
run "$h" /bin/sh "$SC/fleet-state.sh" register w9 demo:9 --if-changed --owner p9.t9.c9 \
  --backend headless-oneshot --state-dir "$tmp/sd9" --death-handle "process $dead" >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "a4: re-registering a nine-column row's fields exited $rc, not 3"
[ "$(grep -c . "$h/registry")" = "$n" ] || fail "a4: a no-change re-register wrote a record"
run "$h" /bin/sh "$SC/fleet-state.sh" retire w7 demo:7 --owner p7.t7.c7 --backend headless-oneshot \
  --state-dir "$tmp/sd7" --death-handle "process $dead" || fail "a4: retire of the seven-column row failed"
run "$h" /bin/sh "$SC/fleet-state.sh" retire w9 demo:9 --owner p9.t9.c9 --backend headless-oneshot \
  --state-dir "$tmp/sd9" --death-handle "process $dead" || fail "a4: retire of the nine-column row failed"
rc=0
run "$h" /bin/sh "$SC/fleet-state.sh" retire w3 demo:3 >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "a4: retire of the three-column row exited $rc, not 3"
[ "$(awk -F"$TAB" '$NF == "closed" { print $2 }' "$h/registry" | tr '\n' ' ')" = "w7 w9 " ] \
  || fail "a4: the closed rows are not w7 and w9"
[ "$fails" = "$f0" ] && ok "a4 fleet-state.sh compares and retires all three arities"

# --- a5 -----------------------------------------------------------------------
f0=$fails
h=$(mixed_home a5)
mkdir -p "$h/dispatch-markers"
want=$(printf 'w9\tdemo:9\tp9.t9.c9\theadless-oneshot\t%s\tprocess %s' "$tmp/sd9" "$dead")
printf '%s\n' "$want" >"$h/dispatch-markers/w9"
run "$h" /bin/sh "$SC/fleet-register.sh" --retire-marker "$h/dispatch-markers/w9" --expect "$want" \
  || fail "a5: --retire-marker of a nine-column row exited non-zero"
[ "$(awk -F"$TAB" '$2 == "w9" { l = $0 } END { print l }' "$h/registry" | cut -f2-8)" = "$want${TAB}closed" ] \
  || fail "a5: the nine-column row was not closed"
[ ! -e "$h/dispatch-markers/w9" ] || fail "a5: the marker was not removed"
[ "$fails" = "$f0" ] && ok "a5 fleet-register.sh --retire-marker closes a nine-column row"

# --- a6 -----------------------------------------------------------------------
f0=$fails
h=$(mixed_home a6)
rc=0
run "$h" /bin/sh "$SC/fleet-messaging.sh" notice-read n9 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 0 ] || fail "a6: notice-read did not match the nine-column row by its name (exit $rc: $(cat "$tmp/err"))"
for nm in demo:7 "process $dead" p7.t7.c7; do
  rc=0
  run "$h" /bin/sh "$SC/fleet-messaging.sh" notice-read "$nm" >/dev/null 2>"$tmp/err" || rc=$?
  [ "$rc" = 2 ] && grep -q "no registry row carries" "$tmp/err" \
    || fail "a6: notice-read matched '$nm' in a row with no name column (exit $rc)"
done
printf '103\tw9\tdemo:9\tp9.t9.c9\theadless-oneshot\t%s\tprocess %s\t-\t-\n' "$tmp/sd9" "$dead" >>"$h/registry"
rc=0
run "$h" /bin/sh "$SC/fleet-messaging.sh" notice-read n9 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a6: notice-read matched a name only an older record carries (exit $rc)"
[ "$fails" = "$f0" ] && ok "a6 fleet-messaging.sh reads the name column by position"

if [ "$fails" -ne 0 ]; then
  echo "FAIL: test-fleet-registry-arity.sh ($fails)" >&2
  exit 1
fi
echo "PASS: test-fleet-registry-arity.sh"
