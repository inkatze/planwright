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

# A direct run inherits the operator's plugin-data home, whose adopter overlay
# can set fleet_compute_host; the gate runner pins it per file, a bare run does
# not. The decoy stands in for that inherited overlay.
mkdir -p "$tmp/decoy/overlay"
printf 'fleet_compute_host: mac\n' >"$tmp/decoy/overlay/planwright.yml"
export CLAUDE_PLUGIN_DATA="$tmp/decoy"
# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"
hermetic_env_sentinel "$tmp/home" || exit 1

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
  capacity)
    [ -z "${FAKE_CAP_DOWN:-}" ] || exit 255
    if [ -n "${FAKE_CAP_RAW+x}" ]; then
      printf '%s\n' "$FAKE_CAP_RAW"
      exit 0
    fi
    echo "load=${FAKE_LOAD:-0.5} cores=${FAKE_CORES:-16} mem_free_mb=8000 idle_secs=${FAKE_IDLE:-unavailable}"
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
# Pinned independently of the plugin-data home, which the sentinel redirects
# only when it is set; the adopter overlay otherwise falls back to the real home.
mkdir -p "$tmp/adopter"
export PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter"

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

# A registry host marked shared takes the run only while its owner is away:
# input idle for the host's own registry idle time, and no hold switch.
reg="$tmp/reg/hosts"
mkdir -p "$tmp/reg"
host_line() { printf 'host mac account=fleet ceiling=2 %s\n' "$1" >"$reg"; }
printf 'fleet_compute_host: mac\nremote_hosts_file: %s\n' "$reg" >"$local_cfg"
host_line 'shared=no'
FAKE_IDLE=5 run --check -- "$tmp/lcmd" a
assert_eq "a host the registry does not mark shared is never held" "remote ran" "$OUT"
case $LOG in *capacity*) fail "and its idle time is never asked" ;; *) ok "and its idle time is never asked" ;; esac
host_line 'shared=yes idle=5'
FAKE_IDLE=600 run --check -- "$tmp/lcmd" a
assert_eq "a shared host idle past its own registry time takes the run" "remote ran" "$OUT"
FAKE_IDLE=300 run --check -- "$tmp/lcmd" a
assert_eq "input exactly that long ago counts as away" "remote ran" "$OUT"
FAKE_IDLE=299 run --check -- "$tmp/lcmd" a
assert_eq "a shared host used within its registry time runs locally" "local ran a" "$OUT"
has "the owner's use is announced" "compute-route: warning: compute host is shared and its owner is using it" "$ERR"
assert_eq "one warning line" 1 "$(printf '%s\n' "$ERR" | grep -c 'warning')"
host_line 'shared=yes idle=08'
FAKE_IDLE=480 run --check -- "$tmp/lcmd" a
assert_eq "a zero-padded registry idle 08 reads as 8 minutes, never an octal error" "remote ran" "$OUT"
host_line 'shared=yes idle=010'
FAKE_IDLE=599 run --check -- "$tmp/lcmd" a
assert_eq "a zero-padded registry idle 010 is 10 minutes, never octal 8" "local ran a" "$OUT"
host_line 'shared=yes idle=0'
FAKE_IDLE=0 run --check -- "$tmp/lcmd" a
assert_eq "a registry idle of 0 never holds a shared host" "remote ran" "$OUT"
host_line 'shared=yes'
default_idle=$("$here/../scripts/host-registry.sh" get mac idle)
FAKE_IDLE=$((default_idle * 60 - 1)) run --check -- "$tmp/lcmd" a
assert_eq "a shared host with no idle field takes the registry default" "local ran a" "$OUT"
FAKE_IDLE=$((default_idle * 60)) run --check -- "$tmp/lcmd" a
assert_eq "and admits input that old" "remote ran" "$OUT"
run --check -- "$tmp/lcmd" a
assert_eq "a shared host whose idle time is unavailable runs locally" "local ran a" "$OUT"
has "and says the owner's absence cannot be read" "idle time is unavailable" "$ERR"
FAKE_LOAD=8 FAKE_CORES=8 FAKE_IDLE=99999 run --check -- "$tmp/lcmd" a
has "a busy shared host is passed over as busy" "compute host is busy (load 8 on 8 cores" "$ERR"
case $LOG in *"load --host"*) fail "a shared host is probed once, by capacity" ;; *) ok "a shared host is probed once, by capacity" ;; esac
host_line 'shared=yes hold=yes'
FAKE_IDLE=99999 run --check -- "$tmp/lcmd" a
assert_eq "a shared host on hold runs locally" "local ran a" "$OUT"
has "and names the hold" "compute host is on hold" "$ERR"
assert_eq "and the held host is never probed" "" "$LOG"
host_line 'shared=no hold=yes'
run --check -- "$tmp/lcmd" a
assert_eq "the hold switch holds an unshared host too" "local ran a" "$OUT"
assert_eq "and never probes it" "" "$LOG"
host_line 'shared=yes idle=5'
FAKE_CAP_DOWN=1 run --check -- "$tmp/lcmd" a
assert_eq "a failed capacity probe on a shared host runs locally" "local ran a" "$OUT"
has "and is announced as unreachable" "compute host unreachable" "$ERR"
for raw in '' 'load=unavailable cores=16 idle_secs=700' 'load=0.5 idle_secs=700'; do
  FAKE_CAP_RAW=$raw run --check -- "$tmp/lcmd" a
  assert_eq "a capacity line with no usable load ('$raw') runs locally" "local ran a" "$OUT"
  has "and says the host did not report its load ('$raw')" "did not report its load" "$ERR"
done
for idle_part in '' 'idle_secs=' 'idle_secs=abc' 'idle_secs=-5' 'idle_secs=1.5' 'idle_secs=1234567890123' 'xidle_secs=700'; do
  FAKE_CAP_RAW="load=0.5 cores=16 $idle_part" run --check -- "$tmp/lcmd" a
  assert_eq "a shared host reporting '$idle_part' runs locally" "local ran a" "$OUT"
  has "and says it did not report its idle time ('$idle_part')" "did not report its input idle time" "$ERR"
done
FAKE_CAP_RAW='load=0.5 cores=16 idle_secs=999999999999' run --check -- "$tmp/lcmd" a
assert_eq "a twelve-digit idle reading is read" "remote ran" "$OUT"
FAKE_CAP_RAW='load=0.5 cores=16 idle_secs=700 idle_secs=5' run --check -- "$tmp/lcmd" a
assert_eq "the first idle_secs field is the reading" "remote ran" "$OUT"
printf 'host other account=fleet ceiling=2 shared=yes\n' >"$reg"
FAKE_IDLE=5 run --check -- "$tmp/lcmd" a
assert_eq "a host missing from the registry is not shared" "remote ran" "$OUT"
printf 'fleet_compute_host: _box\nremote_hosts_file: %s\n' "$reg" >"$local_cfg"
FAKE_IDLE=5 run --check -- "$tmp/lcmd" a
assert_eq "an alias the registry's grammar cannot list is not shared" "remote ran" "$OUT"
printf 'fleet_compute_host: mac\nremote_hosts_file: %s\n' "$reg" >"$local_cfg"
printf 'host mac account=fleet\n' >"$reg"
run --check -- "$tmp/lcmd" a
assert_eq "a registry the helper refuses runs locally" "local ran a" "$OUT"
has "and gives the helper's reason" "host mac: ceiling: required" "$ERR"
assert_eq "and never probes the host" "" "$LOG"
host_line 'shared=yes hold=yes'
chmod 000 "$reg"
if hermetic_access_denied r "$reg"; then
  FAKE_IDLE=99999 run --check -- "$tmp/lcmd" a
  assert_eq "a configured registry that cannot be read runs locally" "local ran a" "$OUT"
  has "and says the registry cannot be read" "host registry cannot be read" "$ERR"
else
  ok "a configured registry that cannot be read runs locally (skipped: this user reads a mode-000 file)"
fi
chmod 600 "$reg"
mkdir -p "$tmp/reg/dir"
printf 'fleet_compute_host: mac\nremote_hosts_file: %s\n' "$tmp/reg/dir" >"$local_cfg"
FAKE_IDLE=99999 run --check -- "$tmp/lcmd" a
assert_eq "a registry path naming a directory runs locally" "local ran a" "$OUT"
has "and says the registry cannot be read" "host registry cannot be read" "$ERR"
printf 'fleet_compute_host: mac\n' >"$local_cfg"
FAKE_IDLE=5 run --check -- "$tmp/lcmd" a
assert_eq "with no registry configured no host is shared" "remote ran" "$OUT"

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

# The explicit local-config file wins over the repo-root one, which resolves
# here because the scratch repo is a git toplevel.
git init -q "$tmp/repo" || exit 1
mkdir -p "$tmp/repo/.claude"
printf 'fleet_compute_host: mac\n' >"$tmp/repo/.claude/planwright.local.yml"
PLANWRIGHT_REPO_ROOT="$tmp/repo" run --check -- "$tmp/lcmd" a
assert_eq "an explicit local config outranks the repo-root file" "local ran a" "$OUT"
assert_eq "and never touches the channel" "" "$LOG"
env -u PLANWRIGHT_LOCAL_CONFIG PLANWRIGHT_REPO_ROOT="$tmp/repo" /bin/sh "$script" --check -- "$tmp/lcmd" a >"$tmp/derived.out" 2>&1
has "without it the repo-root file does move the knob" "remote ran" "$(cat "$tmp/derived.out")"

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
