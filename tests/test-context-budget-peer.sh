#!/bin/bash
# Tests for scripts/context-budget-peer.sh — the peer-pane `/context`
# context-budget corroboration mechanism (fleet-autonomy Task 5: D-9,
# REQ-C1.1, REQ-C1.2).
#
# The mechanism offers a corroborating DIRECT context-budget signal — a peer
# pane running `/context`, capture-paned — alongside the existing
# completed-step-count proxy (context-budget-monitor.sh). It is:
#   - capability-gated: available only where the dispatch backend supports a
#     peer observation pane (the backend-capability-contract can_observe
#     boolean, resolved through orchestrate-backends.sh caps). On a backend
#     without it, the mechanism reports itself ABSENT and the caller falls back
#     to the step-count proxy (REQ-C1.1);
#   - idle-only: it is only ATTEMPTED against an idle observed session; a busy
#     session is SKIPPED, never captured/parsed (REQ-C1.2);
#   - parse-failure-degrading: the `/context` render is UI text (an unstable
#     contract), never a stable API — a malformed/unexpected rendering degrades
#     to the step-count proxy WITH A WARNING, never an opaque halt (REQ-C1.2);
#   - echo-safe: any captured UI text that reaches a diagnostic is stripped of
#     control/escape bytes first (kickoff risk row 23, the same discipline
#     Task 1's audit trail applies).
#
# Contract under test (stdout is exactly one verdict line; exit 0 for every
# graceful verdict, mirroring context-budget-monitor.sh; exit 2 usage error):
#   corroborated <pct>     a direct signal was parsed; <pct> = context USED %
#   proxy capability-absent the backend has no peer-observation-pane capability
#   proxy session-busy      the observed session is busy; not attempted
#   proxy parse-degraded    the `/context` render was malformed; a warning was
#                           emitted; use the step-count proxy
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-context-budget-peer.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

# Hermeticity: the capability gate resolves through orchestrate-backends.sh,
# whose shipped-backend presence can be forced via these env overrides. Clear
# any ambient value so the fixtures below fully control the gate.
unset PLANWRIGHT_BACKEND_TMUX PLANWRIGHT_BACKEND_SUBAGENT

here=$(cd "$(dirname "$0")" && pwd)
CBP="$here/../scripts/context-budget-peer.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$CBP" ] || fail "scripts/context-budget-peer.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
err="$tmp/err"

# Fixture pane renders. A busy Claude Code session shows the "esc to interrupt"
# working footer; an idle one does not.
busy_pane="$tmp/busy-pane.txt"
cat >"$busy_pane" <<'EOF'
● Implementing the parser...

  Running tests (esc to interrupt)
EOF

idle_pane="$tmp/idle-pane.txt"
cat >"$idle_pane" <<'EOF'
● Done.

>
EOF

# A well-formed `/context` render (token-total form): the parenthetical percent
# next to used/total tokens is the USED fraction.
ctx_tokens="$tmp/ctx-tokens.txt"
cat >"$ctx_tokens" <<'EOF'
Context Usage
  claude-opus-4  120k/200k tokens (60%)

  System prompt: 3k
  Tools: 12k
  Messages: 105k
EOF

# A well-formed `/context` render (auto-compact form): the percent is REMAINING
# until auto-compact, so used = 100 - remaining.
ctx_autocompact="$tmp/ctx-autocompact.txt"
cat >"$ctx_autocompact" <<'EOF'
Context left until auto-compact: 25%
EOF

# A malformed/unexpected `/context` render: no recognizable context-usage
# anchor to parse a percentage from.
ctx_malformed="$tmp/ctx-malformed.txt"
cat >"$ctx_malformed" <<'EOF'
zsh: command not found: /context
some unrelated banner text with no usable signal
EOF

# ---------------------------------------------------------------------------
# 1. Capability gate — ABSENT. A backend with no peer-observation-pane
#    capability (subagent: can_observe=false) reports the mechanism absent and
#    the caller falls back to the step-count proxy. Crucially this needs NO
#    observed-pane argument: the gate short-circuits BEFORE any capture is
#    attempted (REQ-C1.1).
# ---------------------------------------------------------------------------
out=$("$CBP" --backend subagent 2>"$err") || fail "capability-absent: exited non-zero"
[ "$out" = "proxy capability-absent" ] \
  || fail "capability-absent: verdict '$out', expected 'proxy capability-absent'"
echo "ok: a backend without peer-pane capability reports the mechanism absent (proxy fallback)"

# ---------------------------------------------------------------------------
# 2. Capability gate — an unknown backend with no adapter is treated as ABSENT
#    (fail-safe: an unknown backend never claims a capability it cannot prove).
# ---------------------------------------------------------------------------
out=$("$CBP" --backend nope-no-adapter 2>"$err") || fail "unknown backend: exited non-zero"
[ "$out" = "proxy capability-absent" ] \
  || fail "unknown backend: verdict '$out', expected 'proxy capability-absent'"
echo "ok: an unknown backend fails safe to capability-absent"

# ---------------------------------------------------------------------------
# 3. Idle gate — a BUSY observed session is SKIPPED, not attempted. Even with a
#    perfectly parseable `/context` render supplied, a busy pane must NOT be
#    parsed: the verdict is session-busy, never corroborated (REQ-C1.2).
# ---------------------------------------------------------------------------
out=$(PLANWRIGHT_BACKEND_TMUX=1 "$CBP" --backend tmux \
  --observed-pane "$busy_pane" --context-render "$ctx_tokens" 2>"$err") \
  || fail "session-busy: exited non-zero"
[ "$out" = "proxy session-busy" ] \
  || fail "session-busy: verdict '$out', expected 'proxy session-busy'"
echo "ok: a busy observed session is skipped (not attempted), even with a parseable render"

# ---------------------------------------------------------------------------
# 3b. Idle gate — busy detection is scoped to the FOOTER, not the whole capture.
#     An idle pane whose SCROLLBACK merely quotes "esc to interrupt" (routine
#     when a worker's task is about this codebase) but whose footer is the idle
#     prompt must corroborate, not be misread as busy.
# ---------------------------------------------------------------------------
scroll_pane="$tmp/scroll-pane.txt"
cat >"$scroll_pane" <<'EOF'
● We discussed the footer: it shows "esc to interrupt" while working.
● All checks pass now.
● Done.

>
EOF
out=$(PLANWRIGHT_BACKEND_TMUX=1 "$CBP" --backend tmux \
  --observed-pane "$scroll_pane" --context-render "$ctx_tokens" 2>"$err") \
  || fail "scrollback-idle: exited non-zero"
[ "$out" = "corroborated 60" ] \
  || fail "scrollback-idle: verdict '$out', expected 'corroborated 60' (scrollback mention must not read as busy)"
echo "ok: a scrollback mention of the busy phrase does not misclassify an idle session"

# ---------------------------------------------------------------------------
# 4. Idle + well-formed token-total render → corroborated USED percent (60).
# ---------------------------------------------------------------------------
out=$(PLANWRIGHT_BACKEND_TMUX=1 "$CBP" --backend tmux \
  --observed-pane "$idle_pane" --context-render "$ctx_tokens" 2>"$err") \
  || fail "token-form: exited non-zero"
[ "$out" = "corroborated 60" ] \
  || fail "token-form: verdict '$out', expected 'corroborated 60'"
echo "ok: an idle session with a token-total /context render corroborates the used percent"

# ---------------------------------------------------------------------------
# 5. Idle + well-formed auto-compact render → corroborated USED percent
#    (100 - 25 = 75).
# ---------------------------------------------------------------------------
out=$(PLANWRIGHT_BACKEND_TMUX=1 "$CBP" --backend tmux \
  --observed-pane "$idle_pane" --context-render "$ctx_autocompact" 2>"$err") \
  || fail "auto-compact-form: exited non-zero"
[ "$out" = "corroborated 75" ] \
  || fail "auto-compact-form: verdict '$out', expected 'corroborated 75'"
echo "ok: an auto-compact /context render is normalized to used percent"

# ---------------------------------------------------------------------------
# 5b. Parser disambiguation & robustness (self-review correctness findings).
#     corroborate_expect writes a render, runs the idle+capable path, and
#     asserts the exact verdict.
# ---------------------------------------------------------------------------
corroborate_expect() {
  ce_render="$tmp/ce.txt"
  printf '%s\n' "$1" >"$ce_render"
  ce_out=$(PLANWRIGHT_BACKEND_TMUX=1 "$CBP" --backend tmux \
    --observed-pane "$idle_pane" --context-render "$ce_render" 2>/dev/null) \
    || fail "parser: exited non-zero on render <$1>"
  [ "$ce_out" = "$2" ] || fail "parser: render <$1> gave '$ce_out', expected '$2'"
}

# A parenthesized used percent wins even when the SAME line also carries a
# remaining ("until auto-compact") clause — the used reading is 77, not 100-77.
corroborate_expect 'claude 154k/200k tokens (77%) · 46k until auto-compact' 'corroborated 77'
# A bogus leading >100 percent on a line is skipped for a later valid one,
# rather than abandoning the line to a false degrade.
corroborate_expect 'tokens 200% cap, actually 60% used' 'corroborated 60'
# 0% / 100% boundaries, both forms (the arithmetic endpoints).
corroborate_expect 'claude 0/200k tokens (0%)' 'corroborated 0'
corroborate_expect 'claude 200k/200k tokens (100%)' 'corroborated 100'
corroborate_expect 'Context left until auto-compact: 0%' 'corroborated 100'
corroborate_expect 'Context left until auto-compact: 100%' 'corroborated 0'
# Leading-zero percent normalizes decimal (never octal): 08% -> 8.
corroborate_expect 'claude tokens (08%)' 'corroborated 8'
echo "ok: parser disambiguates used vs remaining and normalizes edge percents"

# A >100 percent with no other valid signal, and a token line phrased as
# remaining, both DEGRADE rather than emit a wrong number.
bad_render="$tmp/bad.txt"
for bad in 'claude tokens (150%)' 'tokens remaining: 40%'; do
  printf '%s\n' "$bad" >"$bad_render"
  out=$(PLANWRIGHT_BACKEND_TMUX=1 "$CBP" --backend tmux \
    --observed-pane "$idle_pane" --context-render "$bad_render" 2>/dev/null) \
    || fail "parser: exited non-zero on render <$bad>"
  [ "$out" = "proxy parse-degraded" ] \
    || fail "parser: render <$bad> should degrade, got '$out'"
done
echo "ok: an out-of-range or remaining-phrased token percent degrades, never a wrong number"

# ---------------------------------------------------------------------------
# 6. Idle + malformed render → degrade to the step-count proxy WITH A WARNING,
#    never an opaque halt (exit 0). (REQ-C1.2)
# ---------------------------------------------------------------------------
rc=0
out=$(PLANWRIGHT_BACKEND_TMUX=1 "$CBP" --backend tmux \
  --observed-pane "$idle_pane" --context-render "$ctx_malformed" 2>"$err") || rc=$?
[ "$rc" = 0 ] || fail "parse-degrade: exit $rc, expected 0 (never an opaque halt)"
[ "$out" = "proxy parse-degraded" ] \
  || fail "parse-degrade: verdict '$out', expected 'proxy parse-degraded'"
[ -s "$err" ] || fail "parse-degrade: a warning must be emitted on stderr"
grep -qi 'warn' "$err" \
  || fail "parse-degrade: the stderr note should read as a warning"
echo "ok: a malformed /context render degrades to the proxy with a warning (no opaque halt)"

# ---------------------------------------------------------------------------
# 7. Echo discipline — a malformed render carrying control/escape bytes must be
#    sanitized before any of it reaches the warning: no raw ESC on stderr
#    (kickoff risk row 23).
# ---------------------------------------------------------------------------
ctx_hostile="$tmp/ctx-hostile.txt"
printf 'garbage \033]0;PWNED\007 no signal here\n' >"$ctx_hostile"
rc=0
out=$(PLANWRIGHT_BACKEND_TMUX=1 "$CBP" --backend tmux \
  --observed-pane "$idle_pane" --context-render "$ctx_hostile" 2>"$err") || rc=$?
[ "$rc" = 0 ] || fail "hostile-render: exit $rc, expected 0"
[ "$out" = "proxy parse-degraded" ] \
  || fail "hostile-render: verdict '$out', expected 'proxy parse-degraded'"
if LC_ALL=C grep -q "$(printf '\033')" "$err"; then
  fail "hostile-render: captured control bytes must be stripped before the warning is echoed"
fi
echo "ok: captured UI text is sanitized before it reaches the warning"

# ---------------------------------------------------------------------------
# 7b. Echo discipline under an XSI `echo` shell (Linux /bin/sh = dash). A render
#     whose first line carries LITERAL backslash-escape TEXT (`\033`, `\007` as
#     real backslash/digit bytes, NOT control bytes) survives sanitize_printable
#     (which strips control bytes, not backslashes); an XSI `echo` would then
#     re-interpret it into a live terminal escape. The warning must use
#     `printf '%s\n'`, so no ESC is produced on any host (kickoff risk row 23).
#     Run under dash when present (else /bin/sh) so the guard bites where the bug
#     would fire.
xsi_sh=$(command -v dash || echo /bin/sh)
ctx_backslash="$tmp/ctx-backslash.txt"
printf 'garbage \\033]0;PWNED\\007 no signal here\n' >"$ctx_backslash"
rc=0
out=$(PLANWRIGHT_BACKEND_TMUX=1 "$xsi_sh" "$CBP" --backend tmux \
  --observed-pane "$idle_pane" --context-render "$ctx_backslash" 2>"$err") || rc=$?
[ "$rc" = 0 ] || fail "backslash-escape render ($xsi_sh): exit $rc, expected 0"
[ "$out" = "proxy parse-degraded" ] \
  || fail "backslash-escape render: verdict '$out', expected 'proxy parse-degraded'"
if LC_ALL=C grep -q "$(printf '\033')" "$err"; then
  fail "backslash-escape render ($xsi_sh): an XSI echo re-interpreted a literal \\033 into ESC; use printf"
fi
echo "ok: a literal backslash-escape render cannot become a terminal escape (printf, not echo)"

# ---------------------------------------------------------------------------
# 8. Usage errors (exit 2, fail closed).
# ---------------------------------------------------------------------------
rc=0
"$CBP" >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "no --backend: exit $rc, expected 2"

rc=0
"$CBP" --backend '../evil' >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "invalid backend name: exit $rc, expected 2"

# capability present but the required observed-pane is missing → usage error.
rc=0
PLANWRIGHT_BACKEND_TMUX=1 "$CBP" --backend tmux >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "missing --observed-pane on a capable backend: exit $rc, expected 2"

# an unreadable observed-pane file → usage error.
rc=0
PLANWRIGHT_BACKEND_TMUX=1 "$CBP" --backend tmux \
  --observed-pane "$tmp/does-not-exist" >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "unreadable --observed-pane: exit $rc, expected 2"

# idle, capability present, but the required context-render is missing → usage.
rc=0
PLANWRIGHT_BACKEND_TMUX=1 "$CBP" --backend tmux \
  --observed-pane "$idle_pane" >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "missing --context-render on an idle capable session: exit $rc, expected 2"

# a flag given as the trailing token with no value → usage error (the
# [ "$#" -ge 2 ] arms).
rc=0
"$CBP" --backend >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "--backend with no value: exit $rc, expected 2"
rc=0
PLANWRIGHT_BACKEND_TMUX=1 "$CBP" --backend tmux --observed-pane >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "--observed-pane with no value: exit $rc, expected 2"

# an unreadable --context-render (nonexistent path) on an idle session → usage.
rc=0
PLANWRIGHT_BACKEND_TMUX=1 "$CBP" --backend tmux \
  --observed-pane "$idle_pane" --context-render "$tmp/no-such-render" >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "unreadable --context-render: exit $rc, expected 2"

echo "ok: malformed invocations fail closed (exit 2)"

# ---------------------------------------------------------------------------
# 9. The `na` capability (in-session backend) degrades to absent through the
#    peer script itself (the gate uses `!= true`, so `na` is not `true`), and
#    the happy corroborated path leaves stderr empty (no spurious warning).
# ---------------------------------------------------------------------------
out=$("$CBP" --backend in-session 2>"$err") || fail "in-session: exited non-zero"
[ "$out" = "proxy capability-absent" ] \
  || fail "in-session (can_observe=na): verdict '$out', expected 'proxy capability-absent'"

out=$(PLANWRIGHT_BACKEND_TMUX=1 "$CBP" --backend tmux \
  --observed-pane "$idle_pane" --context-render "$ctx_tokens" 2>"$err")
[ "$out" = "corroborated 60" ] || fail "happy-path: verdict '$out', expected 'corroborated 60'"
[ -s "$err" ] && fail "happy-path: the corroborated path must not emit a warning on stderr"
echo "ok: na-capability degrades to absent, and the corroborated path is warning-free"

echo "PASS: test-context-budget-peer.sh"
