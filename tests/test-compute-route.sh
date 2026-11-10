#!/bin/bash
# Tests for scripts/compute-route.sh: the knob-driven choice between running a
# gate command here and on a compute host. The channel is a fake script named
# through PLANWRIGHT_FLEET_REMOTE; config layers are fixtures.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../scripts/compute-route.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/compute-route-test.XXXXXX")" || exit 1
tmp=$(cd -P "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}
has() { case $3 in *"$2"*) ok "$1" ;; *) fail "$1 (missing '$2' in '$3')" ;; esac }

chan="$tmp/channel.sh"
cat >"$chan" <<'CH'
#!/bin/sh
# fake fleet-remote.sh
verb=$3
printf '%s %s\n' "$verb" "$*" >>"$FAKE_CHANNEL_LOG"
case $verb in
  load)
    [ -z "${FAKE_LOAD_DOWN:-}" ] || exit 255
    echo "${FAKE_LOAD:-0.5} ${FAKE_CORES:-16}"
    ;;
  compute)
    if [ -n "${FAKE_NOSTART:-}" ]; then
      echo "fleet-remote: could not ship HEAD" >&2
      exit "$FAKE_NOSTART"
    fi
    echo "fleet-remote: running fake at abc, timeout 1s" >&2
    echo "remote ran"
    exit "${FAKE_RC:-0}"
    ;;
esac
CH
chmod +x "$chan"
export PLANWRIGHT_FLEET_REMOTE="$chan"
export FAKE_CHANNEL_LOG="$tmp/channel.log"

defaults="$tmp/defaults.yml"
local_cfg="$tmp/local.yml"
printf 'fleet_compute_host: local\nfleet_compute_load_cap: 0.4\nfleet_compute_timeout:\n' >"$defaults"
export PLANWRIGHT_CONFIG_DEFAULTS="$defaults" PLANWRIGHT_LOCAL_CONFIG="$local_cfg" PLANWRIGHT_REPO_ROOT="$tmp"

mkdir -p "$tmp/wt"
cd "$tmp/wt" || exit 1
# shellcheck disable=SC2016 # expanded by the fixture at run time
printf '#!/bin/sh\necho "local ran $*"\nexit "${LOCAL_RC:-0}"\n' >"$tmp/lcmd"
chmod +x "$tmp/lcmd"

run() {
  : >"$FAKE_CHANNEL_LOG"
  OUT=$(/bin/sh "$script" "$@" 2>"$tmp/err")
  CODE=$?
  ERR=$(cat "$tmp/err")
  LOG=$(cat "$FAKE_CHANNEL_LOG")
}

: >"$local_cfg"
run --check -- "$tmp/lcmd" a
assert_eq "host local runs the command here" "local ran a" "$OUT"
assert_eq "host local never touches the channel" "" "$LOG"

printf 'fleet_compute_host: mac\n' >"$local_cfg"
run --check -- "$tmp/lcmd" a
assert_eq "a host runs the kind remotely" "remote ran" "$OUT"
has "the channel is asked for the host" "--host mac compute --worktree $tmp/wt --check" "$LOG"
run -- "$tmp/lcmd" a
assert_eq "a command that maps to no kind runs here" "local ran a" "$OUT"
assert_eq "an unmapped command never touches the channel" "" "$LOG"
run --task lint:md -- "$tmp/lcmd"
has "--task is passed through" "compute --worktree $tmp/wt --task lint:md" "$LOG"
run --test tests/test-x.sh -- "$tmp/lcmd"
has "--test is passed through" "--test tests/test-x.sh" "$LOG"

printf '#!/bin/sh\necho "local ran $*"\n' >"$tmp/mise"
chmod +x "$tmp/mise"
PATH="$tmp:$PATH" run -- mise run check
has "mise run check maps to --check" "--check" "$LOG"
PATH="$tmp:$PATH" run -- mise run lint:md
has "mise run <task> maps to --task" "--task lint:md" "$LOG"
PATH="$tmp:$PATH" run -- mise run check extra
assert_eq "extra arguments keep a command local" "" "$LOG"

printf 'mise run check\n' >"$tmp/gate1"
printf 'mise run lint:md\n' >"$tmp/gate2"
printf 'mise run check\nrm -rf x\n' >"$tmp/gate3"
run -- bash "$tmp/gate1"
has "a gate file holding mise run check maps to --check" "--check" "$LOG"
run -- bash "$tmp/gate2"
has "a gate file holding mise run <task> maps to --task" "--task lint:md" "$LOG"
run -- bash "$tmp/gate3"
assert_eq "a multi-line gate file stays local" "" "$LOG"

printf 'fleet_compute_host: mac\nfleet_compute_timeout: 3000\n' >"$local_cfg"
run --check -- "$tmp/lcmd"
has "the timeout knob reaches the channel" "--timeout 3000" "$LOG"

printf 'fleet_compute_host: mac\n' >"$local_cfg"
FAKE_RC=7 run --check -- "$tmp/lcmd"
assert_eq "the remote exit status is the result" 7 "$CODE"
assert_eq "a started run is never repeated locally" "remote ran" "$OUT"

FAKE_LOAD_DOWN=1 run --check -- "$tmp/lcmd" a
assert_eq "an unreachable host falls back to local" "local ran a" "$OUT"
has "the fallback is announced" "compute-route: warning: compute host unreachable" "$ERR"
assert_eq "one warning line" 1 "$(printf '%s\n' "$ERR" | grep -c 'warning')"
assert_eq "an unreachable host is probed, not run on" 1 "$(printf '%s\n' "$LOG" | grep -c .)"

FAKE_LOAD=8 FAKE_CORES=16 run --check -- "$tmp/lcmd" a
assert_eq "a host over the load cap falls back to local" "local ran a" "$OUT"
has "the busy fallback names the load" "busy (load 8 on 16 cores" "$ERR"
FAKE_LOAD=6 FAKE_CORES=16 run --check -- "$tmp/lcmd" a
assert_eq "a host under the load cap takes the run" "remote ran" "$OUT"

FAKE_NOSTART=4 run --check -- "$tmp/lcmd" a
assert_eq "a ship failure before the command started reruns locally" "local ran a" "$OUT"
has "the rerun is announced" "failed before its command started" "$ERR"
FAKE_NOSTART=255 run --check -- "$tmp/lcmd" a
assert_eq "an SSH failure before the command started reruns locally" "local ran a" "$OUT"
FAKE_NOSTART=1 run --check -- "$tmp/lcmd" a
assert_eq "another early exit is the result, not a rerun" 1 "$CODE"

printf 'fleet_compute_host: "a b"\n' >"$local_cfg"
run --check -- "$tmp/lcmd" a
assert_eq "a host that is no alias runs here" "local ran a" "$OUT"
has "and says so" "is not a host alias" "$ERR"

run --check
assert_eq "no command is a usage error" 2 "$CODE"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all compute-route tests passed"
