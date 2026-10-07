#!/bin/bash
# Tests for scripts/fleet-dispatch-env.sh — the dispatch-time environment-
# hardening wrapper (fleet-autonomy Task 6; D-10, REQ-D1.1).
#
# Every fleet-launched Claude Code session another session reads via pane
# capture (a dispatched worker) is launched THROUGH this wrapper so it inherits
# CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false, disabling input-line ghost-text
# (prompt suggestions) at the source (D-10). Prevention at the launch
# environment, never a runtime detection heuristic (REQ-D1.1; the backspace
# probe of REQ-D1.2 stays a documented, undispatched fallback).
#
# What is covered:
#   - a launched worker's process environment carries the var set to `false`
#     (the REQ-D1.1 test-spec "inspect the launched process's environment");
#   - a launched, meta-tower-observed tower's process environment carries it
#     too (the second REQ-D1.1 fixture — the two launch paths share the one
#     wrapper chokepoint);
#   - the wrapper OVERRIDES a hostile/pre-set `...=true` in the parent env down
#     to `false` (prevention must not be defeatable by an inherited value);
#   - `--print` emits exactly the `KEY=VALUE` assignment line (the mode a
#     launcher that cannot wrap the exec — a tmux relay — prepends);
#   - exec is a clean passthrough: the wrapped command's exit status and its
#     arguments (spaces included) reach it unmangled;
#   - a no-command invocation is a usage error (exit 2), never a silent no-op.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-dispatch-env.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FDE="$here/../scripts/fleet-dispatch-env.sh"

VAR=CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FDE" ] || fail "scripts/fleet-dispatch-env.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A stand-in launch target: prints the value the *launched process* actually
# sees for VAR (REQ-D1.1's "inspect the launched process's environment"), and
# echoes its first argument back so argument passthrough is observable. Stands
# in for the `claude ...` a backend spawns — a worker or an observed tower.
fake_session="$tmp/fake-session.sh"
cat >"$fake_session" <<EOF
#!/bin/sh
printf 'seen=%s\n' "\${$VAR-<unset>}"
printf 'arg1=%s\n' "\${1-<none>}"
exit 0
EOF
chmod +x "$fake_session"

# assert_launch_sets_var <label>: launch the stand-in session THROUGH the
# wrapper (the shared dispatch chokepoint both launch paths use) and assert its
# process environment carries the var pinned to `false`.
assert_launch_sets_var() {
  _label=$1
  _out=$("$FDE" "$fake_session") || fail "$_label launch through the wrapper failed (exit $?)"
  printf '%s\n' "$_out" | grep -qx "seen=false" \
    || fail "$_label launch: expected $VAR=false in the launched process env, got: $_out"
}

# REQ-D1.1 fixture 1: a dispatched worker.
assert_launch_sets_var "worker"

# REQ-D1.1 fixture 2: a tower under meta-tower observation.
assert_launch_sets_var "meta-tower-observed tower"

# The launched process must also see the planwright root, or a worker's
# auto-approve hook — wired through $CLAUDE_PLUGIN_ROOT in the worker-settings
# fragment — resolves against an empty value and never runs.
root_session="$tmp/root-session.sh"
cat >"$root_session" <<'EOF'
#!/bin/sh
printf 'plugin_root=%s\n' "${CLAUDE_PLUGIN_ROOT-<unset>}"
printf 'planwright_root=%s\n' "${PLANWRIGHT_ROOT-<unset>}"
exit 0
EOF
chmod +x "$root_session"

root_out=$(env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT "$FDE" "$root_session") || fail "root-session launch through the wrapper failed (exit $?)"
for rootvar in plugin_root planwright_root; do
  line=$(printf '%s\n' "$root_out" | grep "^$rootvar=") \
    || fail "the launched process must see $rootvar, got: $root_out"
  [ -f "${line#*=}/scripts/fleet-dispatch-env.sh" ] \
    || fail "$rootvar in the launched env does not point at a planwright root: '$line'"
done

# An operator-chosen root is not overridden: unlike the ghost-text pin, these
# are documented overrides (tests, adopters pointing at a checkout).
ovr_launch=$(PLANWRIGHT_ROOT=/tmp/chosen-root "$FDE" "$root_session") \
  || fail "root-session launch with an override failed (exit $?)"
printf '%s\n' "$ovr_launch" | grep -qx "planwright_root=/tmp/chosen-root" \
  || fail "an operator-set PLANWRIGHT_ROOT must reach the launched process unchanged, got: $ovr_launch"

# Prevention is not defeatable by an inherited value: a parent env that already
# exports the var to `true` is overridden to `false` at launch.
override_out=$(CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=true "$FDE" "$fake_session") \
  || fail "launch with a pre-set true failed (exit $?)"
printf '%s\n' "$override_out" | grep -qx "seen=false" \
  || fail "the wrapper must override a pre-set '$VAR=true' down to false, got: $override_out"

# --print emits the assignment lines a launcher that cannot wrap the exec must
# prepend: the ghost-text pin, plus the resolved planwright root under both
# names the guard's resolution chain reads. A launcher using --print is exactly
# the case that gets no exec-time export, so omitting the root here would leave
# its workers without the auto-approve hook.
print_out=$(env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT "$FDE" --print) || fail "--print exited nonzero"
printf '%s\n' "$print_out" | grep -qx "$VAR=false" \
  || fail "--print must emit '$VAR=false', got '$print_out'"
for rootvar in PLANWRIGHT_ROOT CLAUDE_PLUGIN_ROOT; do
  line=$(printf '%s\n' "$print_out" | grep "^$rootvar=") \
    || fail "--print must emit a $rootvar assignment, got '$print_out'"
  case ${line#*=} in
    /*) ;;
    *) fail "$rootvar must be absolute, got '$line'" ;;
  esac
  [ -f "${line#*=}/scripts/fleet-dispatch-env.sh" ] \
    || fail "$rootvar does not point at a planwright root: '$line'"
done

# The root is self-located, never a captured version-bearing path: an operator
# override wins, and the derived value survives a plugin update.
ovr_out=$(PLANWRIGHT_ROOT=/tmp/chosen-root "$FDE" --print) || fail "--print with an override exited nonzero"
printf '%s\n' "$ovr_out" | grep -qx "PLANWRIGHT_ROOT=/tmp/chosen-root" \
  || fail "an operator-set PLANWRIGHT_ROOT must win, got '$ovr_out'"

# --print takes no extra args: a trailing argument is a usage error, never a
# silent print (guards the `[ "$#" -eq 1 ] || usage` branch).
pc=0
"$FDE" --print extra >/dev/null 2>&1 || pc=$?
[ "$pc" -eq 2 ] || fail "'--print <extra>' should exit 2 (usage), got $pc"

# exec passthrough: the wrapped command's exit status propagates unchanged.
ec=0
"$FDE" sh -c 'exit 7' || ec=$?
[ "$ec" -eq 7 ] || fail "exec exit-code passthrough expected 7, got $ec"

# exec passthrough: an argument with spaces reaches the command unmangled
# (exec "$@", no shell re-parse).
arg_out=$("$FDE" "$fake_session" "hello world") || fail "argument-passthrough launch failed"
printf '%s\n' "$arg_out" | grep -qx "arg1=hello world" \
  || fail "argument passthrough mangled a spaced argument, got: $arg_out"

# A no-command invocation is a usage error, never a silent no-op.
uc=0
"$FDE" >/dev/null 2>&1 || uc=$?
[ "$uc" -eq 2 ] || fail "a no-command invocation should exit 2 (usage), got $uc"

# The launch options: a detached tmux session runs the wrapper as its command,
# so the worker's identity and the dispatcher's roots have to come from the
# options, not from whatever the tmux server's environment inherited.
id_session="$tmp/id-session.sh"
cat >"$id_session" <<'EOF'
#!/bin/sh
for v in PLANWRIGHT_WORKER_HANDLE PLANWRIGHT_WORKER_SCOPE PLANWRIGHT_WORKER_LAUNCH_TOKEN \
  PLANWRIGHT_ROOT CLAUDE_PLUGIN_ROOT PLANWRIGHT_FLEET_STATE_DIR CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION \
  PLANWRIGHT_TOWER_ID PLANWRIGHT_TOWER_SESSION_ID PLANWRIGHT_TOWER_PID PLANWRIGHT_TOWER_CHECKOUT \
  PLANWRIGHT_REPO_ROOT PLANWRIGHT_ORCH_STATE_DIR; do
  printf '%s=%s\n' "$v" "$(printenv "$v" || echo '<unset>')"
done
printf 'args=%s\n' "$*"
EOF
chmod +x "$id_session"
mkdir -p "$tmp/root" "$tmp/fleet"
tok=0123456789abcdef0123456789abcdef
id_out=$(PLANWRIGHT_ROOT=/decoy CLAUDE_PLUGIN_ROOT=/decoy PLANWRIGHT_FLEET_STATE_DIR=/decoy \
  PLANWRIGHT_TOWER_ID=p9.t9.c9 PLANWRIGHT_TOWER_SESSION_ID=decoy PLANWRIGHT_TOWER_PID=1 \
  PLANWRIGHT_TOWER_CHECKOUT=/decoy PLANWRIGHT_REPO_ROOT=/decoy PLANWRIGHT_ORCH_STATE_DIR=/decoy \
  PLANWRIGHT_WORKER_HANDLE=stale "$FDE" --identity tmux-demo-task-3 demo:3 --launch-token "$tok" \
  --root "$tmp/root" --fleet-home "$tmp/fleet" "$id_session" a b) \
  || fail "a launch with every option failed (exit $?)"
for want in "PLANWRIGHT_WORKER_HANDLE=tmux-demo-task-3" "PLANWRIGHT_WORKER_SCOPE=demo:3" \
  "PLANWRIGHT_WORKER_LAUNCH_TOKEN=$tok" "PLANWRIGHT_ROOT=$tmp/root" "CLAUDE_PLUGIN_ROOT=$tmp/root" \
  "PLANWRIGHT_FLEET_STATE_DIR=$tmp/fleet" "$VAR=false" "args=a b" \
  "PLANWRIGHT_TOWER_ID=<unset>" "PLANWRIGHT_TOWER_SESSION_ID=<unset>" "PLANWRIGHT_TOWER_PID=<unset>" \
  "PLANWRIGHT_TOWER_CHECKOUT=<unset>" "PLANWRIGHT_REPO_ROOT=<unset>" "PLANWRIGHT_ORCH_STATE_DIR=<unset>"; do
  printf '%s\n' "$id_out" | grep -qxF "$want" \
    || fail "the launch options must reach the launched process as '$want', got: $id_out"
done

# --check validates every option and launches nothing.
ck_out=$("$FDE" --check --identity tmux-demo-task-3 demo:3 --launch-token "$tok" \
  --root "$tmp/root" --fleet-home "$tmp/fleet" "$id_session") \
  || fail "--check over well-formed options must exit 0 (exit $?)"
[ -z "$ck_out" ] || fail "--check must launch nothing, got: $ck_out"

# A malformed or half-supplied option is a usage refusal under --check and
# under a launch alike, and the command never runs.
expect_refused() {
  _label=$1
  shift
  for _mode in --check launch; do
    _rc=0
    if [ "$_mode" = --check ]; then
      _o=$("$FDE" --check "$@" "$id_session" 2>&1) || _rc=$?
    else
      _o=$("$FDE" "$@" "$id_session" 2>&1) || _rc=$?
    fi
    [ "$_rc" -eq 2 ] || fail "$_label ($_mode): expected exit 2, got $_rc ($_o)"
    case $_o in *args=*) fail "$_label ($_mode): the command ran ($_o)" ;; esac
  done
}
expect_refused "identity missing its scope" --identity tmux-demo-task-3
expect_refused "identity whose scope is the next option" --identity tmux-demo-task-3 --launch-token "$tok"
expect_refused "identity outside the identity-gate grammar" --identity 'tmux demo' demo:3
expect_refused "identity holding a slash" --identity tmux-demo demo/3
expect_refused "identity given twice" --identity a b --identity c d
expect_refused "launch token missing" --launch-token
expect_refused "launch token not lowercase hex" --launch-token 0123456789ABCDEF
expect_refused "launch token too short" --launch-token 0123abcd
expect_refused "root missing" --root
expect_refused "relative root" --root relative/root
expect_refused "root that is not a directory" --root "$tmp/missing"
expect_refused "relative fleet home" --fleet-home fleet
uc=0
"$FDE" --check --identity a b >/dev/null 2>&1 || uc=$?
[ "$uc" -eq 2 ] || fail "--check with no command should exit 2 (usage), got $uc"

echo "ok: test-fleet-dispatch-env"
