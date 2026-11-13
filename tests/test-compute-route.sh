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
  inuse)
    [ -z "${FAKE_INUSE_DOWN:-}" ] || exit 255
    echo "${FAKE_HID_NS:--} ${FAKE_CONSOLE:-fleet} ${FAKE_LOGIN:-fleet}"
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
printf 'fleet_compute_host: local\nfleet_compute_load_cap: 0.4\nfleet_compute_idle_threshold: 600\nfleet_compute_account:\nfleet_compute_timeout:\n' >"$defaults"
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
FAKE_NOSTART=2 run --check -- "$tmp/lcmd" a
assert_eq "a refusal before the command started reruns locally" "local ran a" "$OUT"

# A Mac a person is using yields to the local host.
printf 'fleet_compute_host: mac\n' >"$local_cfg"
FAKE_HID_NS=3600000000000 FAKE_CONSOLE=fleet run --check -- "$tmp/lcmd" a
assert_eq "an idle host with only the fleet console user takes the run" "remote ran" "$OUT"
FAKE_HID_NS=- FAKE_CONSOLE=- run --check -- "$tmp/lcmd" a
assert_eq "a host with no HID or console reading takes the run" "remote ran" "$OUT"
FAKE_HID_NS=5000000000 run --check -- "$tmp/lcmd" a
assert_eq "recent HID input runs locally" "local ran a" "$OUT"
has "the in-use fallback is announced" "compute-route: warning: compute host is in use" "$ERR"
assert_eq "one in-use warning line" 1 "$(printf '%s\n' "$ERR" | grep -c 'warning')"
FAKE_HID_NS=3600000000000 FAKE_CONSOLE=alice run --check -- "$tmp/lcmd" a
assert_eq "another console user runs locally" "local ran a" "$OUT"
has "the console user is named" "console user alice" "$ERR"
FAKE_HID_NS=3600000000000 FAKE_CONSOLE=root run --check -- "$tmp/lcmd" a
assert_eq "the login window (root) is not a person" "remote ran" "$OUT"
FAKE_INUSE_DOWN=1 run --check -- "$tmp/lcmd" a
assert_eq "a failed in-use probe falls back like an unreachable host" "local ran a" "$OUT"
has "and is announced as unreachable" "compute host unreachable" "$ERR"
printf 'fleet_compute_host: mac\nfleet_compute_idle_threshold: 60\n' >"$local_cfg"
FAKE_HID_NS=120000000000 run --check -- "$tmp/lcmd" a
assert_eq "a lowered threshold admits input older than it" "remote ran" "$OUT"
printf 'fleet_compute_host: mac\nfleet_compute_idle_threshold: 3600\n' >"$local_cfg"
FAKE_HID_NS=1800000000000 run --check -- "$tmp/lcmd" a
assert_eq "a raised threshold turns away input younger than it" "local ran a" "$OUT"
printf 'fleet_compute_host: mac\nfleet_compute_idle_threshold: 0\n' >"$local_cfg"
FAKE_HID_NS=1000000000 FAKE_CONSOLE=alice run --check -- "$tmp/lcmd" a
assert_eq "threshold 0 turns the in-use probe off" "remote ran" "$OUT"
printf 'fleet_compute_host: mac\nfleet_compute_idle_threshold: 0600\n' >"$local_cfg"
FAKE_HID_NS=700000000000 run --check -- "$tmp/lcmd" a
assert_eq "a zero-padded threshold reads as the default, never octal" "remote ran" "$OUT"
FAKE_HID_NS=300000000000 run --check -- "$tmp/lcmd" a
assert_eq "and the default 600 still turns away input younger than it" "local ran a" "$OUT"
printf 'fleet_compute_host: mac\nfleet_compute_account: alice\n' >"$local_cfg"
FAKE_HID_NS=3600000000000 FAKE_CONSOLE=alice FAKE_LOGIN=fleet run --check -- "$tmp/lcmd" a
assert_eq "the account knob names the fleet console user" "remote ran" "$OUT"
printf 'fleet_compute_host: mac\n' >"$local_cfg"

# Targets the channel would refuse, and out-of-range knobs, never reach it as is.
run --task 'a.b' -- "$tmp/lcmd" a
assert_eq "a task name outside the grammar runs here" "local ran a" "$OUT"
run --test tests/sub/test-x.sh -- "$tmp/lcmd" a
assert_eq "a test path outside the grammar runs here" "local ran a" "$OUT"
printf 'fleet_compute_host: mac\nfleet_compute_timeout: 0\n' >"$local_cfg"
run --check -- "$tmp/lcmd"
case $LOG in *--timeout*) fail "a zero timeout reached the channel" ;; *) ok "a zero timeout reads as the channel default" ;; esac
printf 'fleet_compute_host: mac\nfleet_compute_timeout: 100000\n' >"$local_cfg"
run --check -- "$tmp/lcmd"
case $LOG in *--timeout*) fail "an over-range timeout reached the channel" ;; *) ok "an over-range timeout reads as the channel default" ;; esac
printf 'fleet_compute_host: mac\nfleet_compute_load_cap: 2\n' >"$local_cfg"
FAKE_LOAD=20 FAKE_CORES=16 run --check -- "$tmp/lcmd" a
assert_eq "a raised load cap admits a busier host" "remote ran" "$OUT"
printf 'fleet_compute_host: mac\nfleet_compute_load_cap: 0.01\n' >"$local_cfg"
FAKE_LOAD=1 FAKE_CORES=16 run --check -- "$tmp/lcmd" a
assert_eq "a lowered load cap turns a lightly loaded host away" "local ran a" "$OUT"
printf 'fleet_compute_host: mac\n' >"$local_cfg"

# A worktree with uncommitted changes would be tested as something it is not.
mkdir -p "$tmp/gitwt"
git -C "$tmp/gitwt" init -q
printf 'x\n' >"$tmp/gitwt/dirty"
: >"$FAKE_CHANNEL_LOG"
(cd "$tmp/gitwt" && /bin/sh "$script" --check -- "$tmp/lcmd" a 2>"$tmp/err" >"$tmp/out")
assert_eq "a dirty worktree runs here" "local ran a" "$(cat "$tmp/out")"
has "and says why" "uncommitted changes" "$(cat "$tmp/err")"
assert_eq "a dirty worktree never touches the channel" "" "$(cat "$FAKE_CHANNEL_LOG")"

# A two-line gate file without a final newline is not one command.
printf 'mise run check\nextra' >"$tmp/gate4"
run -- bash "$tmp/gate4"
assert_eq "a gate file with a second line stays local" "" "$LOG"

# The full-suite owner runs a gate file through the router.
: >"$FAKE_CHANNEL_LOG"
FSR=$(cd "$here/../scripts" && pwd)/full-suite-run.sh
OUT=$(/bin/sh "$FSR" -- bash "$tmp/gate1" 2>/dev/null)
assert_eq "full-suite-run routes the saved gate command" "remote ran" "$OUT"

printf 'fleet_compute_host: "a b"\n' >"$local_cfg"
run --check -- "$tmp/lcmd" a
assert_eq "a host that is no alias runs here" "local ran a" "$OUT"
has "and says so" "is not a host alias" "$ERR"

run --check
assert_eq "no command is a usage error" 2 "$CODE"

# The shape a worker starts a test run in: the bare form, no kind flag.
printf 'fleet_compute_host: mac\n' >"$local_cfg"
run -- bash tests/test-x.sh
assert_eq "a worker's plain test run goes to the host" "remote ran" "$OUT"
has "as the named test file" "--host mac compute --worktree $tmp/wt --test tests/test-x.sh" "$LOG"
: >"$local_cfg"
run -- bash tests/test-x.sh
assert_eq "knob local keeps the plain test run off the channel" "" "$LOG"

# Workers learn the form from the instructions they load.
root="$here/.."
for doc in doctrine/plugin-script-invocation.md skills/polish/SKILL.md skills/self-review/SKILL.md; do
  if grep -q 'compute-route.sh' "$root/$doc"; then ok "$doc names the router"; else fail "$doc does not name the router"; fi
done

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all compute-route tests passed"
