#!/bin/bash
# scripts/fleet-tower-launch.sh — the fleet tower launch the continue-as-new
# handover runs (fleet-messaging Task 4; D-8, D-17, D-19, REQ-B1.1, REQ-F1.1).
#   t1  a launch starts a detached headless tower whose argv names the session
#       on the headless-oneshot grammar, passes the tower profile with
#       --settings, and carries the fixed wake prompt; its environment carries
#       PLANWRIGHT_MESSAGING_INBOUND=accept and the ghost-text pin, the caller's
#       umask, and no tower or worker identity; the report names the pid, the
#       name, and the owner-only log
#   t2  --unattended and --meta shape the wake prompt; --dry-run prints the
#       same argv and starts nothing
#   t3  an unreadable tower profile under the planwright root refuses the
#       launch, naming the profile, and starts nothing
#   t4  a hostile spec, a relative checkout, an unknown flag, and the CLI seam
#       without PLANWRIGHT_TEST_SEAM=1 are refused
#   t5  a tower that exits at once is reported as a failed launch
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd -P)
FTL="$REPO_ROOT/scripts/fleet-tower-launch.sh"

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}
ok() { echo "ok $1"; }

tmp=$(cd "$(mktemp -d)" && pwd -P)
cleanup() {
  for pf in "$tmp"/rec*/pid; do
    [ -f "$pf" ] || continue
    p=$(cat "$pf" 2>/dev/null) || continue
    case $p in '' | *[!0-9]*) continue ;; esac
    kill "$p" 2>/dev/null
  done
  rm -rf "$tmp"
}
trap cleanup EXIT
TAB=$(printf '\t')
mkdir -p "$tmp/checkout" "$tmp/fleet"
chmod 700 "$tmp/fleet"

# The CLI shim records its argv (one word per line) and environment, then
# holds until released, the way a live tower runs on.
cat >"$tmp/claude" <<'SHIM'
#!/bin/sh
rec=$SHIM_REC
mkdir -p "$rec"
printf '%s\n' "$$" >"$rec/pid"
: >"$rec/argv.tmp"
for a in "$@"; do printf '%s\n' "$a" >>"$rec/argv.tmp"; done
mv "$rec/argv.tmp" "$rec/argv"
printf 'inbound=%s\n' "${PLANWRIGHT_MESSAGING_INBOUND-<unset>}" >"$rec/env"
printf 'ghost=%s\n' "${CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION-<unset>}" >>"$rec/env"
printf 'cwd=%s\n' "$(pwd -P)" >>"$rec/env"
printf 'tower=%s\n' "${PLANWRIGHT_TOWER_ID-<unset>}" >>"$rec/env"
printf 'worker=%s\n' "${PLANWRIGHT_WORKER_HANDLE-<unset>}" >>"$rec/env"
printf 'umask=%s\n' "$(umask)" >>"$rec/env"
[ -n "${SHIM_EXIT:-}" ] && exit "$SHIM_EXIT"
while [ ! -e "$rec/release" ]; do sleep 0.1; done
SHIM
chmod +x "$tmp/claude"

launch() {
  env -u PLANWRIGHT_ROOT -u PLANWRIGHT_MESSAGING_INBOUND -u CLAUDE_PLUGIN_ROOT \
    PLANWRIGHT_TOWER_ID=p9.t9.c9 PLANWRIGHT_WORKER_HANDLE=stale-worker PLANWRIGHT_TEST_SEAM=1 \
    PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" PLANWRIGHT_TOWER_LAUNCH_CLAUDE="$tmp/claude" "$@"
}

wait_file() {
  local n=0
  while [ ! -e "$1" ] && [ "$n" -lt 100 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  [ -e "$1" ]
}

field() { printf '%s\n' "$1" | awk -F"$TAB" -v k="$2" '$1 == "tower-launch" && $2 == k { print $3; exit }'; }

# --- t1 -----------------------------------------------------------------------
f0=$fails
out=$(launch SHIM_REC="$tmp/rec1" /bin/sh "$FTL" demo --checkout "$tmp/checkout" 2>"$tmp/err") \
  || fail "t1: the launch exited non-zero: $(cat "$tmp/err")"
wait_file "$tmp/rec1/argv" || fail "t1: the tower never started"
name=$(field "$out" name)
case $name in
  planwright-tower-demo-[0-9]*-[0-9]*) ;;
  *) fail "t1: the reported name is '$name'" ;;
esac
"$REPO_ROOT/scripts/orchestrate-relay.sh" validate-handle headless-oneshot "$name" \
  || fail "t1: the derived name fails the headless-oneshot grammar"
want=$(printf '%s\n' -p --name "$name" --settings "$REPO_ROOT/config/tower-settings.json" \
  --output-format json "/orchestrate --watch demo")
[ "$(cat "$tmp/rec1/argv")" = "$want" ] || fail "t1: the tower argv is '$(tr '\n' '|' <"$tmp/rec1/argv")'"
grep -qx 'inbound=accept' "$tmp/rec1/env" || fail "t1: the tower's inbound layer is not accept: $(cat "$tmp/rec1/env")"
grep -qx 'ghost=false' "$tmp/rec1/env" || fail "t1: the tower lacks the ghost-text pin"
grep -qx "cwd=$tmp/checkout" "$tmp/rec1/env" || fail "t1: the tower did not start in its checkout"
grep -qx 'tower=<unset>' "$tmp/rec1/env" || fail "t1: the fresh tower inherited the retiring tower's identity"
grep -qx 'worker=<unset>' "$tmp/rec1/env" || fail "t1: the fresh tower inherited a worker identity"
grep -qx "umask=$(umask)" "$tmp/rec1/env" || fail "t1: the fresh tower did not keep the caller's umask: $(grep umask "$tmp/rec1/env")"
[ "$(field "$out" pid)" = "$(cat "$tmp/rec1/pid")" ] || fail "t1: the reported pid is not the tower's"
log=$(field "$out" log)
case $log in
  "$tmp/fleet/tower-launch/$name.log") ;;
  *) fail "t1: the reported log is '$log'" ;;
esac
[ "$(stat -c %a "$log" 2>/dev/null || stat -f %Lp "$log")" = 600 ] || fail "t1: the tower log is not owner-only"
touch "$tmp/rec1/release"
[ "$fails" = "$f0" ] && ok "t1 the launch names the tower, passes the tower profile, and sets the inbound layer"

# --- t2 -----------------------------------------------------------------------
f0=$fails
out=$(launch SHIM_REC="$tmp/rec2" /bin/sh "$FTL" demo --unattended --checkout "$tmp/checkout" --dry-run 2>"$tmp/err") \
  || fail "t2: the dry run exited non-zero: $(cat "$tmp/err")"
[ ! -e "$tmp/rec2/argv" ] || fail "t2: the dry run started a tower"
plan=$(printf '%s\n' "$out" | awk -F"$TAB" '$1 == "tower-launch" && $2 == "argv" { for (i = 3; i <= NF; i++) print $i }')
case $plan in
  *"--inbound"*"accept"*"--name"*"--settings"*"/orchestrate --watch --unattended demo") ;;
  *) fail "t2: the dry-run plan is '$plan'" ;;
esac
out=$(launch SHIM_REC="$tmp/rec2m" /bin/sh "$FTL" --meta --checkout "$tmp/checkout" --dry-run 2>/dev/null) \
  || fail "t2: the meta dry run exited non-zero"
[ "$(printf '%s\n' "$out" | awk -F"$TAB" '$2 == "argv" { print $NF }')" = "/orchestrate --meta --watch" ] \
  || fail "t2: the meta wake prompt is wrong: $out"
case $(field "$out" name) in
  planwright-tower-meta-[0-9]*-[0-9]*) ;;
  *) fail "t2: the meta tower's name is wrong: $out" ;;
esac
[ "$fails" = "$f0" ] && ok "t2 --unattended, --meta, and --dry-run shape the launch"

# --- t3 -----------------------------------------------------------------------
f0=$fails
bad="$tmp/badroot"
mkdir -p "$bad/config"
cp "$REPO_ROOT/config/tower-settings.json" "$bad/config/"
chmod 000 "$bad/config/tower-settings.json"
rc=0
env PLANWRIGHT_ROOT="$bad" PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" PLANWRIGHT_TOWER_LAUNCH_CLAUDE="$tmp/claude" PLANWRIGHT_TEST_SEAM=1 \
  SHIM_REC="$tmp/rec3" /bin/sh "$FTL" demo --checkout "$tmp/checkout" >/dev/null 2>"$tmp/err" || rc=$?
chmod 644 "$bad/config/tower-settings.json"
[ "$rc" = 2 ] || fail "t3: an unreadable tower profile exited $rc, not 2"
grep -qF "$bad/config/tower-settings.json" "$tmp/err" || fail "t3: the refusal does not name the profile: $(cat "$tmp/err")"
[ ! -e "$tmp/rec3/argv" ] || fail "t3: the refused launch started a tower"
[ "$fails" = "$f0" ] && ok "t3 an unreadable tower profile refuses the launch, naming it"

# --- t4 -----------------------------------------------------------------------
f0=$fails
# shellcheck disable=SC2016 # literal hostile values
for args in "../x" "Demo" "flight" 'a$(id)' "-x" "demo --checkout relative/dir" "demo --bogus" "demo extra"; do
  rc=0
  # shellcheck disable=SC2086 # each case is split into its words on purpose
  launch SHIM_REC="$tmp/rec4" /bin/sh "$FTL" $args >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "t4: '$args' exited $rc, not 2"
done
[ ! -e "$tmp/rec4/argv" ] || fail "t4: a refused launch started a tower"
rc=0
env -u PLANWRIGHT_TEST_SEAM -u PLANWRIGHT_ROOT PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" PLANWRIGHT_TOWER_LAUNCH_CLAUDE="$tmp/claude" \
  SHIM_REC="$tmp/rec4" /bin/sh "$FTL" demo --checkout "$tmp/checkout" >/dev/null 2>"$tmp/err" || rc=$?
if [ "$rc" != 2 ] || ! grep -q "test-only seam" "$tmp/err"; then
  fail "t4: the CLI seam was honoured without PLANWRIGHT_TEST_SEAM=1 (exit $rc: $(cat "$tmp/err"))"
fi
[ ! -e "$tmp/rec4/argv" ] || fail "t4: the ungated seam started a tower"
[ "$fails" = "$f0" ] && ok "t4 hostile or malformed arguments are refused"

# --- t5 -----------------------------------------------------------------------
f0=$fails
rc=0
launch SHIM_REC="$tmp/rec5" SHIM_EXIT=1 /bin/sh "$FTL" demo --checkout "$tmp/checkout" >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 4 ] || fail "t5: a tower that exits at once was reported with exit $rc, not 4"
grep -q "log" "$tmp/err" || fail "t5: the failure does not point at the log: $(cat "$tmp/err")"
[ "$fails" = "$f0" ] && ok "t5 a tower that exits at once is a failed launch"

if [ "$fails" -ne 0 ]; then
  echo "FAIL: test-fleet-tower-launch.sh ($fails)" >&2
  exit 1
fi
echo "PASS: test-fleet-tower-launch.sh"
