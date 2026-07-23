#!/bin/bash
# Tests for scripts/offload-dispatch.sh — the /offload dispatch primitive
# (execution-backends Task 6; D-1, REQ-C1.5).
#
# Contract under test (the fixture half of REQ-C1.5's verification path):
#   - `report <backend> <handle>` emits the standardized worker report: the
#     handle plus an observe/attach hint appropriate to the backend's
#     advertised set, under `status reported` (grammar validated, dispatch and
#     liveness NOT verified). tmux (can_observe=true, interactive=true) gets a
#     single-quoted capture-pane observe hint and a window attach hint;
#     subagent (can_observe=false, interactive=false) reports the
#     no-observe-surface fact (act on the completion signal) and the
#     not-human-attachable fact — a rung with no observe surface reports that
#     fact, never an invented hint.
#   - `dispatch tmux <prompt-file>` spawns the worker via `tmux new-window`
#     (never send-keys; the petition travels as a FILE READ of an absolutized
#     path, never spliced into the command line, and `--` pins it as the
#     prompt so leading-dash content can never become a `claude` option),
#     captures the window-id handle from STDOUT ONLY (stderr chatter on a
#     successful spawn must not corrupt the handle), and emits the report
#     with `status  dispatched`.
#   - a FAILED dispatch produces a visible failure report (`status  failed` +
#     reason, `(no output)` when tmux was silent) and exit 1 — never a silent
#     drop (REQ-C1.5).
#   - `dispatch print <prompt-file>` prepares the manual launch: it prints the
#     exact `claude -- "$(cat -- '<abs-path>')"` launch command, reports that
#     no process exists until the human runs it, and reports the
#     spawn-deferred observe fact.
#   - harness-native rungs (`subagent`) and inline work (`in-session`) are
#     visibly refused by `dispatch` (the harness dispatches those; `report`
#     covers the post-dispatch subagent report), and the not-yet-drivable
#     contract rows (`stream-json-persistent`, `headless-oneshot`) are
#     visibly refused until their dispatch support lands (Tasks 3-4).
#   - hostile handles (charset, leading dash, over-length, empty), unsafe
#     prompt-file paths (single quote, control bytes, unreadable), unknown
#     backends, and usage errors are refused before use, never interpolated,
#     with sanitized diagnostics (REQ-K1.5 posture, mirroring
#     orchestrate-relay.sh).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../scripts/offload-dispatch.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/offload-dispatch-test.XXXXXX")" || {
  echo "FAIL: mktemp could not create a work dir" >&2
  exit 1
}
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

# PATH-stub invocation confined to a function-local command prefix (never a
# bare `PATH=... fn` prefix on a function call, whose persistence is
# shell-dependent).
stubbin="$tmp/bin"
run_stub() {
  PATH="$stubbin:$PATH" /bin/sh "$script" "$@"
}

if [ ! -x "$script" ]; then
  echo "FAIL: scripts/offload-dispatch.sh missing or not executable at $script" >&2
  exit 1
fi

promptfile="$tmp/petition.txt"
printf 'Summarize the release notes since v0.29.0\n' >"$promptfile" || {
  echo "FAIL: cannot write the petition fixture" >&2
  exit 1
}

# 1. report tmux: status reported, handle, quoted observe/attach hints.
out=$(run report tmux @5) || fail "report tmux exited nonzero"
printf '%s\n' "$out" | grep -q "status	reported" || fail "report tmux: status must be 'reported', not an unverified 'dispatched'"
printf '%s\n' "$out" | grep -q "handle	@5" || fail "report tmux: handle line missing"
printf '%s\n' "$out" | grep -q "capture-pane -p -t '@5'" || fail "report tmux: observe hint missing or -t target unquoted"
printf '%s\n' "$out" | grep -q "select-window -t '@5'" || fail "report tmux: attach hint missing or -t target unquoted"
printf '%s\n' "$out" | grep -q 'send-keys' && fail "report tmux: emitted a send-keys path (never-impersonate)"
ok "report tmux carries status reported, handle, quoted observe/attach hints"

# 2. report subagent: no observe surface reported as fact; not attachable.
out=$(run report subagent agent-abc.1) || fail "report subagent exited nonzero"
printf '%s\n' "$out" | grep -q "status	reported" || fail "report subagent: status line missing"
printf '%s\n' "$out" | grep -q "handle	agent-abc.1" || fail "report subagent: handle line missing"
printf '%s\n' "$out" | grep -qi 'no observe surface' || fail "report subagent: no-observe-surface fact missing"
printf '%s\n' "$out" | grep -qi 'completion' || fail "report subagent: completion-signal guidance missing"
printf '%s\n' "$out" | grep -qi 'not human-attachable' || fail "report subagent: not-attachable fact missing"
ok "report subagent states the no-observe-surface and not-attachable facts"

# 3. hostile handles refused with a diagnostic, never interpolated.
check_refused_report() {
  rc=0
  out=$(run report "$1" "$2" 2>"$tmp/err") || rc=$?
  [ "$rc" -eq 2 ] || fail "$3: expected exit 2, got $rc"
  [ -z "$out" ] || fail "$3: emitted a report"
  [ -s "$tmp/err" ] || fail "$3: refusal carried no diagnostic"
}
check_refused_report tmux '@5;rm -rf /' "hostile tmux handle (metacharacters)"
check_refused_report tmux '-x' "leading-dash handle (option injection)"
check_refused_report tmux '' "empty handle"
check_refused_report subagent '@5' "tmux-charset handle against the stricter subagent grammar"
long_handle=$(printf 'a%.0s' $(seq 1 129))
check_refused_report tmux "$long_handle" "over-length (129-char) handle"
for b in print in-session nosuch; do
  check_refused_report "$b" whatever "report for unsupported backend '$b'"
done
ok "hostile handles and unsupported report backends refused (exit 2, diagnostic, no report)"

# 4. dispatch tmux via a PATH stub: report carries the stub's window id; the
#    petition travels as an absolutized file-read argv, pinned behind `--`.
mkdir -p "$stubbin" || {
  echo "FAIL: cannot create the stub bin dir" >&2
  exit 1
}
cat >"$stubbin/tmux" <<EOF || exit 1
#!/bin/sh
printf '%s\n' "\$@" >>"$tmp/tmux-argv"
echo '@7'
EOF
chmod +x "$stubbin/tmux" || exit 1
resolved=$(PATH="$stubbin:$PATH" command -v tmux)
[ "$resolved" = "$stubbin/tmux" ] || {
  echo "FAIL: tmux stub did not shadow the real tmux (resolved: $resolved)" >&2
  exit 1
}

out=$(run_stub dispatch tmux "$promptfile") || fail "dispatch tmux exited nonzero"
printf '%s\n' "$out" | grep -q "status	dispatched" || fail "dispatch tmux: status line missing"
printf '%s\n' "$out" | grep -q "handle	@7" || fail "dispatch tmux: handle from tmux not reported"
printf '%s\n' "$out" | grep -q "capture-pane -p -t '@7'" || fail "dispatch tmux: quoted observe hint missing"
printf '%s\n' "$out" | grep -q "select-window -t '@7'" || fail "dispatch tmux: quoted attach hint missing"
grep -q 'new-window' "$tmp/tmux-argv" || fail "dispatch tmux: did not use new-window"
grep -q 'offload-' "$tmp/tmux-argv" || fail "dispatch tmux: window not named with the offload- prefix"
grep -q 'send-keys' "$tmp/tmux-argv" && fail "dispatch tmux: used send-keys (never-impersonate)"
# The petition text must travel as a file read, never inline in the argv...
grep -q 'Summarize the release notes' "$tmp/tmux-argv" && fail "dispatch tmux: prompt content spliced into argv"
# ...and the (absolute) prompt-file path must actually be passed to the worker.
grep -qF "$promptfile" "$tmp/tmux-argv" || fail "dispatch tmux: prompt-file path absent from the worker argv"
# `--` pins the prompt as a positional: leading-dash petition content can
# never be parsed as a claude option.
grep -q 'claude -- ' "$tmp/tmux-argv" || fail "dispatch tmux: claude launch not pinned with -- end-of-options"
ok "dispatch tmux reports the spawned window handle; petition rides an absolutized file read behind --"

# 4b. a RELATIVE prompt-file path is absolutized before dispatch. The
#     expected form is pwd-normalized (a TMPDIR with a trailing slash makes
#     $tmp itself carry a double slash pwd would not).
: >"$tmp/tmux-argv"
printf 'relative petition\n' >"$tmp/rel-petition.txt"
tmp_norm=$(cd "$tmp" && pwd)
(cd "$tmp" && PATH="$stubbin:$PATH" /bin/sh "$script" dispatch tmux rel-petition.txt >/dev/null) || fail "relative-path dispatch exited nonzero"
grep -qF "$tmp_norm/rel-petition.txt" "$tmp/tmux-argv" || fail "relative prompt path was not absolutized in the worker argv"
ok "a relative prompt-file path is absolutized before dispatch"

# 4b2. REGRESSION: a dash-leading RELATIVE prompt path must absolutize against
#      the cwd, not be swallowed as a `cd` option (cd -- discipline): without
#      `--`, `cd "-P"` resolves against $HOME and the dispatch misresolves.
: >"$tmp/tmux-argv"
mkdir -p "$tmp/-P" || exit 1
printf 'dash-dir petition\n' >"$tmp/-P/pet.txt"
(cd "$tmp" && PATH="$stubbin:$PATH" /bin/sh "$script" dispatch tmux "-P/pet.txt" >/dev/null 2>&1) || fail "dash-leading relative prompt path: dispatch exited nonzero"
grep -qF "$tmp_norm/-P/pet.txt" "$tmp/tmux-argv" || fail "dash-leading relative prompt path was not absolutized against the cwd"
ok "a dash-leading relative prompt path absolutizes against the cwd (cd -- discipline)"

# 4c. REGRESSION: stderr chatter on a SUCCESSFUL spawn must not corrupt the
#     handle into a false failure (streams captured separately).
: >"$tmp/tmux-argv"
cat >"$stubbin/tmux" <<EOF || exit 1
#!/bin/sh
printf '%s\n' "\$@" >>"$tmp/tmux-argv"
echo 'warning: deprecated option in ~/.tmux.conf' >&2
echo '@7'
EOF
chmod +x "$stubbin/tmux" || exit 1
rc=0
out=$(run_stub dispatch tmux "$promptfile") || rc=$?
[ "$rc" -eq 0 ] || fail "stderr chatter on success: expected exit 0, got $rc"
printf '%s\n' "$out" | grep -q "status	dispatched" || fail "stderr chatter on success: reported failure over a live worker"
printf '%s\n' "$out" | grep -q "handle	@7" || fail "stderr chatter on success: handle corrupted by stderr"
ok "stderr chatter on a successful spawn does not corrupt the handle (no false failure)"

# 4d. tmux exits 0 but prints an unusable window id: failure report + exit 1.
cat >"$stubbin/tmux" <<'EOF'
#!/bin/sh
echo 'not a window id !!'
EOF
chmod +x "$stubbin/tmux" || exit 1
rc=0
out=$(run_stub dispatch tmux "$promptfile" 2>"$tmp/err4d") || rc=$?
[ "$rc" -eq 1 ] || fail "unusable window id: expected exit 1, got $rc"
printf '%s\n' "$out" | grep -q "status	failed" || fail "unusable window id: no failure report"
printf '%s\n' "$out" | grep -qi 'unusable window id' || fail "unusable window id: reason missing"
ok "an unusable window id from tmux produces a failure report and exit 1"

# 5. failed dispatch: visible failure report + exit 1 exactly, never silent;
#    tmux's stderr reaches the reason line.
cat >"$stubbin/tmux" <<'EOF'
#!/bin/sh
echo 'tmux: server exited unexpectedly' >&2
exit 1
EOF
chmod +x "$stubbin/tmux" || exit 1
rc=0
out=$(run_stub dispatch tmux "$promptfile" 2>"$tmp/err5") || rc=$?
[ "$rc" -eq 1 ] || fail "failed dispatch: expected exit 1 (the pinned failure code), got $rc"
printf '%s\n' "$out" | grep -q "status	failed" || fail "failed dispatch: no failure report on stdout"
printf '%s\n' "$out" | grep -q "reason	" || fail "failed dispatch: no reason line"
printf '%s\n' "$out" | grep -q 'server exited unexpectedly' || fail "failed dispatch: tmux stderr absent from the reason"
[ -s "$tmp/err5" ] || fail "failed dispatch: no stderr diagnostic"
ok "failed dispatch produces a visible failure report (with tmux stderr) and exit 1"

# 5b. a silent tmux failure labels the empty output honestly.
cat >"$stubbin/tmux" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$stubbin/tmux" || exit 1
rc=0
out=$(run_stub dispatch tmux "$promptfile" 2>/dev/null) || rc=$?
[ "$rc" -eq 1 ] || fail "silent tmux failure: expected exit 1, got $rc"
printf '%s\n' "$out" | grep -q 'no output' || fail "silent tmux failure: empty stderr not labeled '(no output)'"
ok "a silent tmux failure reports '(no output)', not a mislabel"

# 6. dispatch print: exact launch command, spawn-deferred facts, full report.
out=$(run dispatch print "$promptfile") || fail "dispatch print exited nonzero"
printf '%s\n' "$out" | grep -q "status	prepared" || fail "dispatch print: status line missing"
printf '%s\n' "$out" | grep -q "backend	print" || fail "dispatch print: backend line missing"
printf '%s\n' "$out" | grep -qF "launch	claude -- \"\$(cat -- '$promptfile')\"" || fail "dispatch print: exact launch form (claude -- + quoted cat of the abs path) not emitted"
printf '%s\n' "$out" | grep -qi 'no process' || fail "dispatch print: no-process-until-run fact missing"
printf '%s\n' "$out" | grep -qi 'spawn deferred' || fail "dispatch print: spawn-deferred observe fact missing"
printf '%s\n' "$out" | grep -q "attach	" || fail "dispatch print: attach line missing"
ok "dispatch print emits the exact -- pinned launch command and the spawn-deferred facts"

# 7. harness-native / inline / not-yet-drivable rungs visibly refused.
for b in subagent in-session stream-json-persistent headless-oneshot; do
  rc=0
  run dispatch "$b" "$promptfile" >/dev/null 2>"$tmp/err7" || rc=$?
  [ "$rc" -eq 2 ] || fail "dispatch $b: expected visible refusal (exit 2), got $rc"
  [ -s "$tmp/err7" ] || fail "dispatch $b: refusal carried no diagnostic"
done
ok "non-shell-drivable rungs are refused visibly, never silently"

# 8. unknown backend and missing/empty/unsafe prompt files refused.
check_refused_dispatch() {
  rc=0
  run dispatch "$1" "$2" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "$3: expected exit 2, got $rc"
}
check_refused_dispatch nosuch "$promptfile" "unknown backend"
check_refused_dispatch tmux "$tmp/absent.txt" "missing prompt file"
: >"$tmp/empty.txt"
check_refused_dispatch tmux "$tmp/empty.txt" "empty prompt file"
printf 'x\n' >"$tmp/it's.txt"
check_refused_dispatch tmux "$tmp/it's.txt" "prompt path containing a single quote"
ctl_path="$tmp/$(printf 'bad\033name.txt')"
printf 'x\n' >"$ctl_path"
check_refused_dispatch tmux "$ctl_path" "prompt path containing a control byte"
printf 'x\n' >"$tmp/unreadable.txt"
chmod 000 "$tmp/unreadable.txt"
if [ ! -r "$tmp/unreadable.txt" ]; then # skip under root, where -r passes
  check_refused_dispatch tmux "$tmp/unreadable.txt" "unreadable prompt file"
fi
chmod 600 "$tmp/unreadable.txt"
ok "unknown backend and missing/empty/unsafe prompt files refused"

# 9. usage errors fail closed.
for args in '' 'nosuchsub' 'dispatch' 'dispatch tmux' 'report' 'report tmux'; do
  rc=0
  # shellcheck disable=SC2086 # word-splitting the arg string is the point
  run $args >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "usage '$args': expected exit 2, got $rc"
done
ok "usage errors (no/unknown subcommand, wrong arity) exit 2"

# 10. a control-byte-laden backend name cannot drive the terminal: the
#     diagnostic is sanitized.
rc=0
run dispatch "$(printf 'bad\033[31mname')" "$promptfile" >/dev/null 2>"$tmp/err10" || rc=$?
[ "$rc" -eq 2 ] || fail "control-byte backend name: expected exit 2, got $rc"
if grep -q "$(printf '\033')" "$tmp/err10"; then
  fail "control-byte backend name: raw ESC byte reached the diagnostic (echo discipline)"
fi
ok "hostile backend-name diagnostics are sanitized (no raw control bytes)"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all offload-dispatch tests passed"
