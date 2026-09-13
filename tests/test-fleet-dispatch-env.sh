#!/bin/bash
# Tests for scripts/fleet-dispatch-env.sh — the dispatch-time environment-
# hardening wrapper (fleet-autonomy Task 6; D-10, REQ-D1.1).
#
# Every fleet-launched Claude Code session another session reads via pane
# capture — a dispatched worker, and any subordinate tower a meta-tower
# observes — is launched THROUGH this wrapper so it inherits
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

root_out=$("$FDE" "$root_session") || fail "root-session launch through the wrapper failed (exit $?)"
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
print_out=$("$FDE" --print) || fail "--print exited nonzero"
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

echo "ok: test-fleet-dispatch-env"
