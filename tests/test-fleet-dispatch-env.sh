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

# Prevention is not defeatable by an inherited value: a parent env that already
# exports the var to `true` is overridden to `false` at launch.
override_out=$(CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=true "$FDE" "$fake_session") \
  || fail "launch with a pre-set true failed (exit $?)"
printf '%s\n' "$override_out" | grep -qx "seen=false" \
  || fail "the wrapper must override a pre-set '$VAR=true' down to false, got: $override_out"

# --print emits exactly the assignment line (for a launcher that prepends it).
print_out=$("$FDE" --print) || fail "--print exited nonzero"
[ "$print_out" = "$VAR=false" ] \
  || fail "--print expected '$VAR=false', got '$print_out'"

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
