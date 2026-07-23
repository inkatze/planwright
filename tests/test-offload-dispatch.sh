#!/bin/bash
# Tests for scripts/offload-dispatch.sh — the /offload dispatch primitive
# (execution-backends Task 6; D-1, REQ-C1.5).
#
# Contract under test (the fixture half of REQ-C1.5's verification path):
#   - `report <backend> <handle>` emits the standardized worker report: the
#     handle plus an observe/attach hint appropriate to the backend's
#     advertised set. tmux (can_observe=true, interactive=true) gets a
#     capture-pane observe hint and a window attach hint; subagent
#     (can_observe=false, interactive=false) reports the no-observe-surface
#     fact (act on the completion signal) and the not-human-attachable fact —
#     a rung with no observe surface reports that fact, never an invented hint.
#   - `dispatch tmux <prompt-file>` spawns the worker via `tmux new-window`
#     (never send-keys; the prompt travels as a file read, never spliced into
#     the command line), captures the window-id handle, and emits the same
#     report shape with `status  dispatched`.
#   - a FAILED dispatch produces a visible failure report (`status  failed` +
#     reason) and a nonzero exit — never a silent drop (REQ-C1.5).
#   - `dispatch print <prompt-file>` prepares the manual launch: it prints the
#     exact launch command, reports that no process exists until the human
#     runs it, and reports the spawn-deferred observe fact.
#   - harness-native rungs (`subagent`) and inline work (`in-session`) are
#     visibly refused by `dispatch` (the harness dispatches those; `report`
#     covers the post-dispatch subagent report), and the not-yet-drivable
#     contract rows (`stream-json-persistent`, `headless-oneshot`) are
#     visibly refused until their dispatch support lands (Tasks 3-4).
#   - hostile handles and unsafe prompt files are refused before use, never
#     interpolated (REQ-K1.5 posture, mirroring orchestrate-relay.sh).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../scripts/offload-dispatch.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/offload-dispatch-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

ok() {
  echo "ok: $1"
}

run() {
  /bin/sh "$script" "$@"
}

if [ ! -f "$script" ]; then
  echo "FAIL: scripts/offload-dispatch.sh missing at $script" >&2
  exit 1
fi

promptfile="$tmp/petition.txt"
printf 'Summarize the release notes since v0.29.0\n' >"$promptfile"

# 1. report tmux: handle + observe (capture-pane) + attach hints.
out=$(run report tmux @5) || fail "report tmux exited nonzero"
printf '%s\n' "$out" | grep -q "handle	@5" || fail "report tmux: handle line missing"
printf '%s\n' "$out" | grep -q 'capture-pane' || fail "report tmux: observe hint missing capture-pane"
printf '%s\n' "$out" | grep -qE 'attach	' || fail "report tmux: attach hint line missing"
printf '%s\n' "$out" | grep -q 'send-keys' && fail "report tmux: emitted a send-keys path (never-impersonate)"
ok "report tmux carries handle, capture-pane observe hint, attach hint"

# 2. report subagent: no observe surface reported as fact; not attachable.
out=$(run report subagent agent-abc.1) || fail "report subagent exited nonzero"
printf '%s\n' "$out" | grep -q "handle	agent-abc.1" || fail "report subagent: handle line missing"
printf '%s\n' "$out" | grep -qi 'no observe surface' || fail "report subagent: no-observe-surface fact missing"
printf '%s\n' "$out" | grep -qi 'completion' || fail "report subagent: completion-signal guidance missing"
printf '%s\n' "$out" | grep -qi 'not human-attachable' || fail "report subagent: not-attachable fact missing"
ok "report subagent states the no-observe-surface and not-attachable facts"

# 3. hostile handle refused, never interpolated.
rc=0
out=$(run report tmux '@5;rm -rf /' 2>"$tmp/err3") || rc=$?
[ "$rc" -eq 2 ] || fail "hostile handle: expected exit 2, got $rc"
[ -z "$out" ] || fail "hostile handle: emitted a report"
ok "hostile handle refused (exit 2, no report)"

# 4. dispatch tmux via a PATH stub: report carries the stub's window id.
stubbin="$tmp/bin"
mkdir -p "$stubbin"
cat >"$stubbin/tmux" <<EOF
#!/bin/sh
printf '%s\n' "\$@" >>"$tmp/tmux-argv"
echo '@7'
EOF
chmod +x "$stubbin/tmux"

out=$(PATH="$stubbin:$PATH" run dispatch tmux "$promptfile") || fail "dispatch tmux exited nonzero"
printf '%s\n' "$out" | grep -q "status	dispatched" || fail "dispatch tmux: status line missing"
printf '%s\n' "$out" | grep -q "handle	@7" || fail "dispatch tmux: handle from tmux not reported"
printf '%s\n' "$out" | grep -q 'capture-pane' || fail "dispatch tmux: observe hint missing"
printf '%s\n' "$out" | grep -qE 'attach	' || fail "dispatch tmux: attach hint missing"
grep -q 'new-window' "$tmp/tmux-argv" || fail "dispatch tmux: did not use new-window"
grep -q 'send-keys' "$tmp/tmux-argv" && fail "dispatch tmux: used send-keys (never-impersonate)"
# The petition text must travel as a file read, never inline in the argv.
grep -q 'Summarize the release notes' "$tmp/tmux-argv" && fail "dispatch tmux: prompt content spliced into argv"
ok "dispatch tmux reports the spawned window handle with observe/attach hints"

# 5. failed dispatch: visible failure report + nonzero exit, never silent.
cat >"$stubbin/tmux" <<'EOF'
#!/bin/sh
echo 'tmux: server exited unexpectedly' >&2
exit 1
EOF
rc=0
out=$(PATH="$stubbin:$PATH" run dispatch tmux "$promptfile" 2>"$tmp/err5") || rc=$?
[ "$rc" -ne 0 ] || fail "failed dispatch: expected nonzero exit"
printf '%s\n' "$out" | grep -q "status	failed" || fail "failed dispatch: no failure report on stdout"
printf '%s\n' "$out" | grep -qE "reason	" || fail "failed dispatch: no reason line"
ok "failed dispatch produces a visible failure report and nonzero exit"

# 6. dispatch print: launch command printed, spawn-deferred facts reported.
out=$(run dispatch print "$promptfile") || fail "dispatch print exited nonzero"
printf '%s\n' "$out" | grep -q "status	prepared" || fail "dispatch print: status line missing"
printf '%s\n' "$out" | grep -qE "launch	claude " || fail "dispatch print: launch command missing"
printf '%s\n' "$out" | grep -qi 'no process' || fail "dispatch print: no-process-until-run fact missing"
ok "dispatch print prints the launch command and the spawn-deferred facts"

# 7. harness-native / inline / not-yet-drivable rungs visibly refused.
for b in subagent in-session stream-json-persistent headless-oneshot; do
  rc=0
  run dispatch "$b" "$promptfile" >/dev/null 2>"$tmp/err7" || rc=$?
  [ "$rc" -eq 2 ] || fail "dispatch $b: expected visible refusal (exit 2), got $rc"
  [ -s "$tmp/err7" ] || fail "dispatch $b: refusal carried no diagnostic"
done
ok "non-shell-drivable rungs are refused visibly, never silently"

# 8. unknown backend and unsafe prompt file refused.
rc=0
run dispatch nosuch "$promptfile" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "unknown backend: expected exit 2, got $rc"
rc=0
run dispatch tmux "$tmp/absent.txt" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "missing prompt file: expected exit 2, got $rc"
: >"$tmp/empty.txt"
rc=0
run dispatch tmux "$tmp/empty.txt" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "empty prompt file: expected exit 2, got $rc"
ok "unknown backend and missing/empty prompt files refused"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all offload-dispatch tests passed"
