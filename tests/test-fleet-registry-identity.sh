#!/bin/bash
# The registry's two identity columns, `name` and `inbox` (fleet-messaging
# Task 4; D-8, REQ-B1.1, REQ-B1.2): `fleet-state.sh register` writes the `-`
# sentinel in both, `fleet-state.sh amend` fills them on the worker's last
# record and changes nothing else, and `fleet-register.sh --amend` degrades per
# field so one refused value never costs the other.
#   i1  register writes nine columns, the two added ones `-`
#   i2  amend replaces exactly the two added columns of the last record: every
#       other field, the epoch included, is unchanged by a before/after diff
#   i3  amend of one field keeps the other's current value
#   i4  amend of a seven-column (pre-identity) and a three-column (pre-owner)
#       last record writes a nine-column row carrying the old fields
#   i5  amend finds nothing to write for an unknown or a retired worker (3)
#   i6  hostile name and inbox values are refused at the registry write and
#       nothing is appended, the sentinel included
#   i7  fleet-register.sh --amend degrades per field: a name the session-name
#       screen admits but the registry charset refuses is not written, the
#       inbox still is, and the exit is non-zero naming the dropped field
#   i8  amend binds the worker's last record: an older record of the same
#       worker is never the one copied
#   i9  an amend that would change nothing writes nothing, and a torn last
#       record is refused (2) rather than read as absent
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
FS="$REPO_ROOT/scripts/fleet-state.sh"
FR="$REPO_ROOT/scripts/fleet-register.sh"

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}
ok() { echo "ok $1"; }

tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
TAB=$(printf '\t')

home() {
  mkdir -p "$tmp/fleet-$1"
  printf '%s\n' "$tmp/fleet-$1"
}

fs_at() {
  fa_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u PLANWRIGHT_ROOT \
    PLANWRIGHT_FLEET_STATE_DIR="$fa_home" /bin/sh "$FS" "$@"
}

fr_at() {
  fr_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u PLANWRIGHT_ROOT \
    -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID \
    -u PLANWRIGHT_TOWER_PID -u PLANWRIGHT_TOWER_CHECKOUT \
    PLANWRIGHT_FLEET_STATE_DIR="$fr_home" /bin/sh "$FR" "$@"
}

last_row() {
  awk -F"$TAB" -v w="$2" '($2 "") == (w "") { l = $0 } END { print l }' "$1/registry"
}

field() {
  printf '%s\n' "$1" | cut -f"$2"
}

# --- i1 -----------------------------------------------------------------------
h=$(home i1)
fs_at "$h" register w1 demo:4 --owner p1.t2.c3 --backend tmux \
  --state-dir "$tmp/wt" --death-handle "tmux-window s1 @1" || fail "i1: register exited non-zero"
row=$(last_row "$h" w1)
[ "$(printf '%s\n' "$row" | awk -F"$TAB" '{ print NF }')" = 9 ] || fail "i1: the record is not nine columns: $row"
[ "$(field "$row" 8)" = - ] || fail "i1: the name column is not the sentinel"
[ "$(field "$row" 9)" = - ] || fail "i1: the inbox column is not the sentinel"
[ "$fails" = 0 ] && ok "i1 register writes the two added columns as the sentinel"

# --- i2 -----------------------------------------------------------------------
f0=$fails
h=$(home i2)
fs_at "$h" register w1 demo:4 --owner p1.t2.c3 --backend tmux \
  --state-dir "$tmp/wt" --death-handle "tmux-window s1 @1" >/dev/null || fail "i2: register failed"
before=$(last_row "$h" w1)
fs_at "$h" amend w1 --name tmux-demo-task-4 --inbox 4242.sock || fail "i2: amend exited non-zero"
after=$(last_row "$h" w1)
[ "$(grep -c . "$h/registry")" = 2 ] || fail "i2: amend did not append exactly one record"
[ "$(field "$before" 1-7)" = "$(field "$after" 1-7)" ] \
  || fail "i2: amend changed a field outside the two added ones: '$before' -> '$after'"
[ "$(field "$after" 8)" = tmux-demo-task-4 ] || fail "i2: the name column is '$(field "$after" 8)'"
[ "$(field "$after" 9)" = 4242.sock ] || fail "i2: the inbox column is '$(field "$after" 9)'"
[ "$(printf '%s\n' "$after" | awk -F"$TAB" '{ print NF }')" = 9 ] || fail "i2: the amended record is not nine columns"
[ "$fails" = "$f0" ] && ok "i2 amend replaces exactly the name and inbox columns"

# --- i3 -----------------------------------------------------------------------
f0=$fails
fs_at "$h" amend w1 --inbox 5151.sock || fail "i3: an inbox-only amend exited non-zero"
row=$(last_row "$h" w1)
[ "$(field "$row" 8)" = tmux-demo-task-4 ] || fail "i3: an inbox-only amend lost the name"
[ "$(field "$row" 9)" = 5151.sock ] || fail "i3: an inbox-only amend did not write the inbox"
fs_at "$h" amend w1 --name renamed-1 || fail "i3: a name-only amend exited non-zero"
row=$(last_row "$h" w1)
[ "$(field "$row" 8)" = renamed-1 ] && [ "$(field "$row" 9)" = 5151.sock ] \
  || fail "i3: a name-only amend did not keep the inbox: $row"
rc=0
fs_at "$h" amend w1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "i3: an amend naming no field exited $rc, not 2"
[ "$fails" = "$f0" ] && ok "i3 amend of one field keeps the other"

# --- i4 -----------------------------------------------------------------------
f0=$fails
h=$(home i4)
printf '100\tw7\tdemo:1\tp1.t2.c3\ttmux\t/tmp/x\tnone\n' >"$h/registry"
printf '101\tw3\tdemo:2\n' >>"$h/registry"
fs_at "$h" amend w7 --name n7 --inbox b7.sock || fail "i4: amend of a seven-column record failed"
fs_at "$h" amend w3 --name n3 --inbox b3.sock || fail "i4: amend of a three-column record failed"
[ "$(last_row "$h" w7)" = "$(printf '100\tw7\tdemo:1\tp1.t2.c3\ttmux\t/tmp/x\tnone\tn7\tb7.sock')" ] \
  || fail "i4: the seven-column amend wrote '$(last_row "$h" w7)'"
[ "$(last_row "$h" w3)" = "$(printf '101\tw3\tdemo:2\t-\t-\t-\t-\tn3\tb3.sock')" ] \
  || fail "i4: the three-column amend wrote '$(last_row "$h" w3)'"
[ "$fails" = "$f0" ] && ok "i4 amend lifts a seven- or three-column record to nine columns"

# --- i5 -----------------------------------------------------------------------
f0=$fails
h=$(home i5)
rc=0
fs_at "$h" amend ghost --name n --inbox b.sock >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "i5: amend of an unknown worker exited $rc, not 3"
[ ! -s "$h/registry" ] || fail "i5: amend of an unknown worker wrote a record"
fs_at "$h" register w1 demo:4 --backend tmux >/dev/null
fs_at "$h" retire w1 demo:4 --backend tmux >/dev/null || fail "i5: retire failed"
n=$(grep -c . "$h/registry")
rc=0
fs_at "$h" amend w1 --name n --inbox b.sock >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "i5: amend of a retired worker exited $rc, not 3"
[ "$(grep -c . "$h/registry")" = "$n" ] || fail "i5: amend of a retired worker wrote a record"
[ "$fails" = "$f0" ] && ok "i5 amend finds nothing to write for an unknown or retired worker"

# --- i6 -----------------------------------------------------------------------
f0=$fails
h=$(home i6)
fs_at "$h" register w1 demo:4 --backend tmux >/dev/null
n=$(grep -c . "$h/registry")
# shellcheck disable=SC2016 # literal hostile values
for v in "-" "" "a b" "a/b" ".." 'a$(id)' 'a`id`' "a;b" "$(printf 'a\tb')" \
  "$(printf 'a\nb')" "$(printf 'a\033[2Jb')" "$(printf '%0129d' 0)" "--name"; do
  rc=0
  fs_at "$h" amend w1 --name "$v" >/dev/null 2>"$tmp/err" || rc=$?
  [ "$rc" = 2 ] || fail "i6: amend accepted the name [$v] (exit $rc)"
  rc=0
  fs_at "$h" amend w1 --inbox "$v" >/dev/null 2>>"$tmp/err" || rc=$?
  [ "$rc" = 2 ] || fail "i6: amend accepted the inbox [$v] (exit $rc)"
done
for v in "a:b" "a=b" "a@b"; do
  rc=0
  fs_at "$h" amend w1 --inbox "$v" >/dev/null 2>>"$tmp/err" || rc=$?
  [ "$rc" = 2 ] || fail "i6: amend accepted the inbox [$v], outside the inbox charset (exit $rc)"
done
[ "$(grep -c . "$h/registry")" = "$n" ] || fail "i6: a refused amend appended a record"
grep -q "$(printf '\033')" "$tmp/err" && fail "i6: a refusal echoed a raw escape byte"
[ "$fails" = "$f0" ] && ok "i6 hostile name and inbox values are refused at the registry write"

# --- i7 -----------------------------------------------------------------------
f0=$fails
h=$(home i7)
fs_at "$h" register w1 demo:4 --backend tmux >/dev/null
rc=0
fr_at "$h" --amend w1 --name "fleet-w1 task" --inbox 4242.sock >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" != 0 ] || fail "i7: a dropped name still exited 0"
grep -q "name" "$tmp/err" || fail "i7: the diagnostic does not name the dropped field: $(cat "$tmp/err")"
row=$(last_row "$h" w1)
[ "$(field "$row" 8)" = - ] || fail "i7: the name column left its sentinel: $row"
[ "$(field "$row" 9)" = 4242.sock ] || fail "i7: the inbox was not written beside a dropped name: $row"
rc=0
fr_at "$h" --amend w1 --name good-name --inbox "a/b" >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" != 0 ] || fail "i7: a dropped inbox still exited 0"
grep -q "inbox" "$tmp/err" || fail "i7: the diagnostic does not name the dropped inbox"
row=$(last_row "$h" w1)
[ "$(field "$row" 8)" = good-name ] && [ "$(field "$row" 9)" = 4242.sock ] \
  || fail "i7: the name beside a dropped inbox was not written, or the inbox changed: $row"
fr_at "$h" --amend w1 --name both-ok --inbox 9.sock >/dev/null 2>&1 || fail "i7: a clean amend exited non-zero"
rc=0
fr_at "$h" --amend w1 --name "a b" --inbox "a/b" >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "i7: an amend with both fields dropped exited 0"
row=$(last_row "$h" w1)
[ "$(field "$row" 8)" = both-ok ] && [ "$(field "$row" 9)" = 9.sock ] \
  || fail "i7: an amend with both fields dropped changed the row: $row"
rc=0
fr_at "$h" --amend -w1 --name x >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "i7: a dash-led worker handle was not refused (exit $rc)"
for flag in --name --inbox; do
  rc=0
  fr_at "$h" --handle w9 --backend tmux "$flag" x >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "i7: $flag beside a dispatch registration was not refused (exit $rc)"
done
[ "$fails" = "$f0" ] && ok "i7 fleet-register.sh --amend degrades per field and names the dropped one"

# --- i8 -----------------------------------------------------------------------
f0=$fails
h=$(home i8)
fs_at "$h" register w1 demo:4 --backend tmux --state-dir "$tmp/old" >/dev/null
fs_at "$h" register w1 demo:4 --backend tmux --state-dir "$tmp/new" >/dev/null
fs_at "$h" amend w1 --name n --inbox b.sock || fail "i8: amend failed"
[ "$(field "$(last_row "$h" w1)" 6)" = "$tmp/new" ] || fail "i8: amend copied an older record"
[ "$fails" = "$f0" ] && ok "i8 amend binds the worker's last record"

# --- i9 -----------------------------------------------------------------------
f0=$fails
h=$(home i9)
fs_at "$h" register w1 demo:4 --backend tmux >/dev/null
fs_at "$h" amend w1 --name n --inbox b.sock || fail "i9: amend failed"
n=$(grep -c . "$h/registry")
fs_at "$h" amend w1 --name n --inbox b.sock || fail "i9: a no-change amend exited non-zero"
[ "$(grep -c . "$h/registry")" = "$n" ] || fail "i9: a no-change amend appended a record"
printf '200\tw2\tdemo:5\t-\ttmux\n' >>"$h/registry"
n=$(grep -c . "$h/registry")
rc=0
fs_at "$h" amend w2 --name n2 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 2 ] || fail "i9: amend of a torn record exited $rc, not 2"
grep -q malformed "$tmp/err" || fail "i9: the torn-record refusal does not say so: $(cat "$tmp/err")"
[ "$(grep -c . "$h/registry")" = "$n" ] || fail "i9: amend of a torn record wrote a record"
fs_at "$h" amend w1 --clear-inbox || fail "i9: --clear-inbox exited non-zero"
[ "$(field "$(last_row "$h" w1)" 8-9)" = "n${TAB}-" ] || fail "i9: --clear-inbox did not write the sentinel back: $(last_row "$h" w1)"
rc=0
fs_at "$h" amend w1 --inbox - >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "i9: the sentinel as an --inbox value was accepted (exit $rc)"
[ "$fails" = "$f0" ] && ok "i9 a no-change amend writes nothing; a torn record is refused; --clear-inbox restores the sentinel"

if [ "$fails" -ne 0 ]; then
  echo "FAIL: test-fleet-registry-identity.sh ($fails)" >&2
  exit 1
fi
echo "PASS: test-fleet-registry-identity.sh"
