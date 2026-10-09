#!/bin/sh
# test-fleet-lock-token-release.sh — every consumer of fleet-state.sh's lock
# releases by the owner token `lock` prints, so a release issued after its own
# hold was cleared leaves the successor's lock standing (D-11, REQ-E1.5).
#
# Each consumer runs from a scratch copy of scripts/ whose fleet-state.sh is a
# stand-in for the real one, in one of three modes (LOCKTEST_MODE):
#   clobber  on the first `unlock` it sees, clear the caller's hold the way the
#            operator's escape hatch does, take the lock for a successor,
#            forward the caller's own `unlock` unchanged, and record whether
#            the successor's lock survived it. A token-less release removes
#            it; a release by token leaves it.
#   fail     forward every token release, then report exit 2 (the lock still
#            on disk), logging each call, so the consumer's handling of a
#            failed release shows: it says so, and its exit handler retries.
#   (unset)  pass everything through, so the consumer's own release is the
#            only thing that can clear its hold.
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
  printf '%s\n' "FAIL: $1" >&2
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
if [ "\${LOCKTEST_MODE:-}" = fail ] && [ "\${1:-}" = unlock ] && [ "\$#" -eq 2 ]; then
  "\$real" "\$@" >/dev/null 2>&1 || :
  echo unlock >>"\$ev"
  exit 2
fi
if [ "\${LOCKTEST_MODE:-}" = clobber ] && [ "\${1:-}" = unlock ] && [ ! -e "\$ev" ]; then
  root=\$("\$real" root) || exit 2
  lk="\$root/.fleet.lock"
  "\$real" unlock >/dev/null 2>&1 || exit 2
  succ=\$("\$real" lock) || exit 2
  before=\$(readlink "\$lk")
  [ -n "\$before" ] || exit 2
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

# run <home> <mode> <evidence> <script> <args...> — one consumer, from the
# scratch copy, with pinned config layers and no ambient plugin or dotfile env.
run() {
  r_home=$1
  r_mode=$2
  r_ev=$3
  r_script=$4
  shift 4
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    PLANWRIGHT_FLEET_STATE_DIR="$r_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    LOCKTEST_MODE="$r_mode" \
    LOCKTEST_EVIDENCE="$r_ev" \
    /bin/sh "$sd/$r_script" "$@"
}

# drive <consumer> <home> <mode> <evidence> — one lock-taking verb of the
# named consumer. Its stderr goes to <evidence>.err.
drive() {
  d_home=$2
  d_mode=$3
  d_ev=$4
  case $1 in
    fleet-attention)
      run "$d_home" "$d_mode" "$d_ev" fleet-attention.sh heartbeat "worker=alpha" "orchestration-fleet:12" working
      ;;
    fleet-throttle)
      run "$d_home" "$d_mode" "$d_ev" fleet-throttle.sh engage --until $((now + 600)) >/dev/null
      ;;
    fleet-audit)
      run "$d_home" "$d_mode" "$d_ev" fleet-audit.sh record lock-test probe staged "a staged clobber"
      ;;
    fleet-usage-gate)
      printf 'Usage\n\nCurrent session\n10%% used\nResets 3:00pm\n\nCurrent week (all models)\n65%% used\nResets Monday\n' \
        | run "$d_home" "" "" fleet-usage-gate.sh capture >/dev/null || return 1
      run "$d_home" "$d_mode" "$d_ev" fleet-usage-gate.sh evaluate >/dev/null
      ;;
    fleet-tower-marker)
      run "$d_home" "$d_mode" "$d_ev" fleet-tower-marker.sh record lock-test --mode unattended --pid $$ --checkout "$tmp/checkout"
      ;;
    fleet-liveness)
      run "$d_home" "$d_mode" "$d_ev" fleet-liveness.sh crash-record "worker=t2" "fleet-autonomy:2" --now 1000 </dev/null >/dev/null
      ;;
    fleet-worktree-track)
      run "$d_home" "$d_mode" "$d_ev" fleet-worktree-track.sh record-create /work/lock-test >/dev/null
      ;;
  esac 2>"$d_ev.err"
}

lock_gone() {
  [ ! -e "$1/.fleet.lock" ] && [ ! -L "$1/.fleet.lock" ]
}

consumers="fleet-attention fleet-throttle fleet-audit fleet-usage-gate fleet-tower-marker fleet-liveness fleet-worktree-track"
now=$(date +%s)

# The harness itself: a token-less release through the clobber stand-in is
# recorded as removing the successor's lock, so "intact" below is a result,
# not the only answer the stand-in can give.
h="$tmp/h-control"
ev="$tmp/ev-control"
own=$(PLANWRIGHT_FLEET_STATE_DIR="$h" /bin/sh "$real_fs" lock) || fail "control: could not take a hold"
[ -n "$own" ] || fail "control: lock printed no token"
PLANWRIGHT_FLEET_STATE_DIR="$h" LOCKTEST_MODE=clobber LOCKTEST_EVIDENCE="$ev" /bin/sh "$sd/fleet-state.sh" unlock \
  || fail "control: the token-less release exited non-zero"
[ "$(cat "$ev")" = removed ] || fail "control: the stand-in did not record a token-less release as removing the successor's lock"
echo "ok: the stand-in records a token-less release as removing the successor's lock"

for c in $consumers; do
  h="$tmp/h-$c"
  ev="$tmp/ev-$c"
  drive "$c" "$h" clobber "$ev" || fail "$c: the clobber run exited non-zero"
  [ -f "$ev" ] || fail "$c: no release reached fleet-state.sh, so nothing was staged"
  [ "$(cat "$ev")" = intact ] || fail "$c: a release after the hold was cleared removed the successor's lock"
  lock_gone "$h" || fail "$c: the fleet lock was left standing after the run"
  printf '%s\n' "ok: $c leaves a successor's lock standing when its own hold was cleared"

  h="$tmp/h-plain-$c"
  drive "$c" "$h" "" "$tmp/ev-plain-$c" || fail "$c: the plain run exited non-zero"
  lock_gone "$h" || fail "$c: its own release did not clear its own hold"
  printf '%s\n' "ok: $c releases its own hold"

  h="$tmp/h-fail-$c"
  ev="$tmp/ev-fail-$c"
  drive "$c" "$h" fail "$ev" || :
  [ -f "$ev" ] && [ "$(wc -l <"$ev")" -ge 2 ] \
    || fail "$c: a failed release was not retried by the exit handler"
  grep -q "could not release the fleet lock" "$ev.err" \
    || fail "$c: a failed release was not reported"
  printf '%s\n' "ok: $c reports a failed release and retries it on exit"
done

# The token-less form stays the operator's escape hatch: it clears a detached
# hold nobody else can name.
h="$tmp/h-hatch"
PLANWRIGHT_FLEET_STATE_DIR="$h" /bin/sh "$real_fs" lock >/dev/null || fail "escape hatch: could not take a detached hold"
[ -L "$h/.fleet.lock" ] || fail "escape hatch: the detached hold left no lock"
PLANWRIGHT_FLEET_STATE_DIR="$h" /bin/sh "$real_fs" unlock || fail "escape hatch: the token-less unlock exited non-zero"
[ ! -e "$h/.fleet.lock" ] && [ ! -L "$h/.fleet.lock" ] || fail "escape hatch: the token-less unlock left the lock standing"
echo "ok: the token-less unlock still clears a detached hold"
