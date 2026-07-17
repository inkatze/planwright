#!/bin/bash
# Tests for scripts/fleet-dispatch-guard.sh — the dispatch-time guard proving
# a fleet worker session is never launched under Claude Code's `auto`
# permission mode (fleet-autonomy Task 7; D-19, REQ-E1.4; kickoff risk rows
# 19, 20).
#
# `auto` mode's approval classifier is LLM-based and judgment-driven —
# directly against the D-18 no-LLM-daemon-mechanics floor for the single
# most security-sensitive decision a dispatched session makes. The
# human-reviewed, human-installed `config/worker-settings.json` allowlist
# (which pins `defaultMode` to a non-auto value) stays the sole
# permission-approval mechanism for dispatched workers (D-19). The guard
# covers both dispatch shapes: a LAUNCHED process (check-launch, over the
# argv) and an IN-PROCESS subagent that inherits the hosting session's
# effective mode (check-inherited — risk 19); and it demands an EXPLICIT
# non-auto mode source rather than trusting absence of the auto flag, so an
# operator's ambient `defaultMode: "auto"` in their own user settings can
# never leak into a worker (risk 20).
#
# What is covered (the REQ-E1.4 fixtures plus the risk-row mitigations):
#   - a launch with `--permission-mode auto` (both spellings) is refused;
#   - a launch with the standard worker-settings-profile allowlist (the
#     shipped config/worker-settings.json via --settings) succeeds;
#   - a bare launch with NO explicit mode source is refused (risk 20);
#   - a settings fragment that itself pins `defaultMode` to auto is refused,
#     as is a --settings path that does not exist (fail closed);
#   - an explicit non-auto `--permission-mode` passes;
#   - check-inherited refuses in-process dispatch under a user-settings
#     ambient `defaultMode: "auto"` and passes otherwise (risk 19);
#   - diagnostics are sanitized (hostile argv cannot drive the terminal);
#   - usage errors are refused (exit 2).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-dispatch-guard.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FDG="$here/../scripts/fleet-dispatch-guard.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FDG" ] || fail "scripts/fleet-dispatch-guard.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

run() {
  /bin/bash "$FDG" "$@"
}

# 1. Usage errors: no subcommand, unknown subcommand, check-launch with no
#    argv, check-inherited with extra args.
for args in "" "bogus" "check-launch" "check-inherited extra"; do
  rc=0
  # shellcheck disable=SC2086
  run $args >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage error for '$args': exit $rc, expected 2"
done
echo "ok: usage errors exit 2"

# 2. The REQ-E1.4 refusal fixture: a worker launch attempting
#    `--permission-mode auto` is refused, in both flag spellings, wherever
#    the flag sits in the argv.
rc=0
run check-launch claude --permission-mode auto -p "/execute-task 3" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "--permission-mode auto: exit $rc, expected 1 (refused)"
rc=0
run check-launch claude -p "/execute-task 3" --permission-mode=auto >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "--permission-mode=auto: exit $rc, expected 1 (refused)"
echo "ok: an auto-mode launch is refused (both spellings)"

# 3. The REQ-E1.4 success fixture: a launch carrying the standard
#    worker-settings-profile allowlist succeeds — asserted against the REAL
#    shipped fragment, so a future defaultMode drift in
#    config/worker-settings.json fails here.
real_profile="$here/../config/worker-settings.json"
[ -f "$real_profile" ] || fail "shipped config/worker-settings.json not found"
run check-launch claude --settings "$real_profile" -p "/execute-task 3" >/dev/null 2>&1 \
  || fail "the standard worker-settings-profile launch must pass the guard"
echo "ok: the standard worker-settings-profile launch passes"

# 4. Risk 20: a bare launch with NO explicit non-auto mode source is refused
#    — absence of the auto flag is not proof of a non-auto mode (the
#    operator's ambient user-settings default could be auto).
rc=0
run check-launch claude -p "/execute-task 3" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "bare launch: exit $rc, expected 1 (no explicit mode source)"
echo "ok: a launch with no explicit mode source is refused (risk 20)"

# 5. A settings fragment that itself pins defaultMode to auto is refused; a
#    fragment pinning a non-auto mode passes; a missing fragment path fails
#    closed; a fragment with no defaultMode at all is not a mode source.
auto_profile="$tmp/auto-settings.json"
printf '{"permissions": {"defaultMode": "auto", "allow": []}}\n' >"$auto_profile"
rc=0
run check-launch claude --settings "$auto_profile" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "auto-pinning settings fragment: exit $rc, expected 1"
ok_profile="$tmp/ok-settings.json"
printf '{"permissions": {"defaultMode": "acceptEdits", "allow": []}}\n' >"$ok_profile"
run check-launch claude --settings="$ok_profile" >/dev/null 2>&1 \
  || fail "a non-auto-pinning settings fragment (--settings= spelling) must pass"
rc=0
run check-launch claude --settings "$tmp/no-such.json" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "missing settings fragment: exit $rc, expected 1 (fail closed)"
nomode_profile="$tmp/nomode-settings.json"
printf '{"permissions": {"allow": []}}\n' >"$nomode_profile"
rc=0
run check-launch claude --settings "$nomode_profile" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "settings fragment without defaultMode: exit $rc, expected 1 (not a mode source)"
echo "ok: settings-fragment mode pins are honored and fail closed"

# 6. An explicit non-auto --permission-mode is a valid mode source; auto
#    still wins the refusal even when a non-auto settings pin is also
#    present (any auto source refuses).
run check-launch claude --permission-mode default -p "/execute-task 3" >/dev/null 2>&1 \
  || fail "an explicit non-auto --permission-mode must pass"
rc=0
run check-launch claude --settings "$ok_profile" --permission-mode auto >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "auto flag alongside a non-auto settings pin: exit $rc, expected 1"
echo "ok: explicit non-auto mode passes; any auto source refuses"

# 7. Risk 19: check-inherited covers the in-process (subagent) dispatch
#    shape — the worker inherits the hosting session's effective mode, whose
#    ambient source is the operator's own user settings (the one place
#    Claude Code honors defaultMode auto, per D-19).
claude_dir="$tmp/claude-home"
mkdir -p "$claude_dir"
printf '{"permissions": {"defaultMode": "auto"}}\n' >"$claude_dir/settings.json"
rc=0
CLAUDE_DIR="$claude_dir" run check-inherited >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "inherited ambient auto: exit $rc, expected 1 (refused)"
printf '{"permissions": {"defaultMode": "default"}}\n' >"$claude_dir/settings.json"
CLAUDE_DIR="$claude_dir" run check-inherited >/dev/null 2>&1 \
  || fail "inherited non-auto default must pass"
rm -f "$claude_dir/settings.json"
CLAUDE_DIR="$claude_dir" run check-inherited >/dev/null 2>&1 \
  || fail "no user settings file must pass (Claude Code's own default mode is 'default')"
echo "ok: check-inherited covers the in-process dispatch shape (risk 19)"

# 8. Echo discipline: a hostile argv value cannot drive the terminal — the
#    refusal diagnostic is stripped of control bytes.
esc=$(printf '\033')
rc=0
err=$(run check-launch "evil${esc}[2Jclaude" --permission-mode auto 2>&1 >/dev/null) || rc=$?
[ "$rc" = 1 ] || fail "hostile argv: exit $rc, expected 1"
case $err in
  *"$esc"*) fail "hostile argv: a raw escape byte reached the diagnostic" ;;
esac
echo "ok: refusal diagnostics are sanitized"

# 9. Duplicate defaultMode keys: JSON duplicate-key resolution is
#    parser-dependent, so the guard must refuse when ANY occurrence pins
#    auto — a fragment with auto first and default last must not slip
#    through on a first-match (or last-match) read.
dup_profile="$tmp/dup-settings.json"
printf '{"defaultMode": "auto", "nested": {"defaultMode": "default"}}\n' >"$dup_profile"
rc=0
run check-launch claude --settings "$dup_profile" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "duplicate defaultMode with any auto occurrence: exit $rc, expected 1"
echo "ok: any auto occurrence among duplicate defaultMode keys refuses"

# 10. A --permission-mode value that is itself a flag is not a mode: the
#    guard must not swallow a following option as the mode value and then
#    green-light a launch whose real --settings source was never read.
rc=0
run check-launch claude --permission-mode --settings "$tmp/no-such.json" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "flag-valued --permission-mode: exit $rc, expected 1"
echo "ok: a flag swallowed as the mode value is refused"

# 11. check-inherited with NEITHER CLAUDE_DIR nor HOME set: the inherited
#    mode is unverifiable, and unverifiable fails closed (exit 1) — never a
#    silent pass against /.claude.
rc=0
env -u CLAUDE_DIR -u HOME /bin/bash "$FDG" check-inherited >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "check-inherited with no CLAUDE_DIR/HOME: exit $rc, expected 1 (fail closed)"
echo "ok: an unverifiable inherited-mode environment fails closed"

echo "ALL PASS: fleet-dispatch-guard"
