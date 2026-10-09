#!/bin/sh
# test-fleet-lock-token-release.sh — every consumer of fleet-state.sh's lock
# releases by the owner token `lock` prints, so a release issued after its own
# hold was cleared leaves the successor's lock standing (D-11, REQ-E1.5).
#
# Each consumer runs from a scratch copy of scripts/ whose fleet-state.sh is a
# stand-in for the real one. On the first `unlock` it sees, the stand-in clears
# the caller's hold the way the operator's escape hatch does, takes the lock
# for a successor, forwards the caller's own `unlock` unchanged, and records
# whether the successor's lock survived it. A token-less release removes it;
# a release by token leaves it.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-lock-token-release.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
src="$here/../scripts"
real_fs="$src/fleet-state.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$real_fs" ] || fail "scripts/fleet-state.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

sd="$tmp/scripts"
mkdir -p "$sd"
for f in "$src"/*; do
  ln -s "$f" "$sd/${f##*/}"
done
rm -f "$sd/fleet-state.sh"
cat >"$sd/fleet-state.sh" <<EOF
#!/bin/sh
real='$real_fs'
ev=\${LOCKTEST_EVIDENCE:-}
if [ "\${1:-}" = unlock ] && [ -n "\$ev" ] && [ ! -e "\$ev" ]; then
  root=\$("\$real" root) || exit 2
  lk="\$root/.fleet.lock"
  "\$real" unlock >/dev/null 2>&1 || exit 2
  succ=\$("\$real" lock) || exit 2
  before=\$(readlink "\$lk")
  rc=0
  "\$real" "\$@" || rc=\$?
  if [ "\$(readlink "\$lk" 2>/dev/null)" = "\$before" ]; then
    echo intact >"\$ev"
  else
    echo removed >"\$ev"
  fi
  "\$real" unlock "\$succ" >/dev/null 2>&1 || :
  exit "\$rc"
fi
exec "\$real" "\$@"
EOF
chmod 0755 "$sd/fleet-state.sh"

core_cfg="$tmp/core-defaults.yml"
repo="$tmp/repo"
adopter_root="$tmp/adopter"
mkdir -p "$repo/.claude" "$adopter_root" "$tmp/checkout"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$repo"
cat >"$core_cfg" <<'EOF'
fleet_daemon_pause: false
fleet_throttle_default_hold: 120
fleet_usage_read_cadence_seconds: 60
fleet_usage_signal_ttl_seconds: 300
fleet_usage_sustained_loss_count: 3
fleet_usage_session_downshift: 50
fleet_usage_session_reduce_concurrency: 70
fleet_usage_session_defer_heavy: 85
fleet_usage_weekly_downshift: 60
fleet_usage_weekly_reduce_concurrency: 75
fleet_usage_weekly_defer_heavy: 85
fleet_usage_weekly_defer_all: 95
fleet_flailing_threshold: 3
fleet_hung_heartbeat_seconds: 900
fleet_crash_backoff_base_seconds: 30
fleet_crash_disable_threshold: 3
stale_marker_threshold: 15m
EOF

# run <home> <evidence> <script> <args...> — one consumer, from the scratch
# copy, with pinned config layers and no ambient plugin or dotfile env.
run() {
  r_home=$1
  r_ev=$2
  r_script=$3
  shift 3
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    PLANWRIGHT_FLEET_STATE_DIR="$r_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    LOCKTEST_EVIDENCE="$r_ev" \
    /bin/sh "$sd/$r_script" "$@"
}

# expect_intact <label> <home> <evidence> — the clobber was staged, and the
# consumer's release left the successor's lock where it was.
expect_intact() {
  [ -f "$3" ] || fail "$1: no release reached fleet-state.sh, so nothing was staged"
  [ "$(cat "$3")" = intact ] || fail "$1: a release after the hold was cleared removed the successor's lock"
  [ ! -e "$2/.fleet.lock" ] && [ ! -L "$2/.fleet.lock" ] \
    || fail "$1: the fleet lock was left standing after the run"
  echo "ok: $1 leaves a successor's lock standing when its own hold was cleared"
}

now=$(date +%s)

h="$tmp/h-attention"
run "$h" "$tmp/ev-attention" fleet-attention.sh heartbeat "worker=alpha" "orchestration-fleet:12" working \
  || fail "fleet-attention: heartbeat exited non-zero"
expect_intact fleet-attention "$h" "$tmp/ev-attention"

h="$tmp/h-throttle"
run "$h" "$tmp/ev-throttle" fleet-throttle.sh engage --until $((now + 600)) >/dev/null \
  || fail "fleet-throttle: engage exited non-zero"
expect_intact fleet-throttle "$h" "$tmp/ev-throttle"

h="$tmp/h-audit"
run "$h" "$tmp/ev-audit" fleet-audit.sh record lock-test probe staged "a staged clobber" \
  || fail "fleet-audit: record exited non-zero"
expect_intact fleet-audit "$h" "$tmp/ev-audit"

h="$tmp/h-usage"
printf 'Usage\n\nCurrent session\n10%% used\nResets 3:00pm\n\nCurrent week (all models)\n65%% used\nResets Monday\n' \
  | run "$h" "" fleet-usage-gate.sh capture >/dev/null || fail "fleet-usage-gate: capture exited non-zero"
run "$h" "$tmp/ev-usage" fleet-usage-gate.sh evaluate >/dev/null \
  || fail "fleet-usage-gate: evaluate exited non-zero"
expect_intact fleet-usage-gate "$h" "$tmp/ev-usage"

h="$tmp/h-marker"
run "$h" "$tmp/ev-marker" fleet-tower-marker.sh record lock-test --mode unattended --pid $$ --checkout "$tmp/checkout" \
  || fail "fleet-tower-marker: record exited non-zero"
expect_intact fleet-tower-marker "$h" "$tmp/ev-marker"

h="$tmp/h-liveness"
run "$h" "$tmp/ev-liveness" fleet-liveness.sh crash-record "worker=t2" "fleet-autonomy:2" --now 1000 </dev/null >/dev/null \
  || fail "fleet-liveness: crash-record exited non-zero"
expect_intact fleet-liveness "$h" "$tmp/ev-liveness"

h="$tmp/h-worktree"
run "$h" "$tmp/ev-worktree" fleet-worktree-track.sh record-create /work/lock-test >/dev/null \
  || fail "fleet-worktree-track: record-create exited non-zero"
expect_intact fleet-worktree-track "$h" "$tmp/ev-worktree"

# The token-less form stays the operator's escape hatch: it clears a detached
# hold nobody else can name.
h="$tmp/h-hatch"
PLANWRIGHT_FLEET_STATE_DIR="$h" /bin/sh "$real_fs" lock >/dev/null || fail "escape hatch: could not take a detached hold"
[ -L "$h/.fleet.lock" ] || fail "escape hatch: the detached hold left no lock"
PLANWRIGHT_FLEET_STATE_DIR="$h" /bin/sh "$real_fs" unlock || fail "escape hatch: the token-less unlock exited non-zero"
[ ! -e "$h/.fleet.lock" ] && [ ! -L "$h/.fleet.lock" ] || fail "escape hatch: the token-less unlock left the lock standing"
echo "ok: the token-less unlock still clears a detached hold"
