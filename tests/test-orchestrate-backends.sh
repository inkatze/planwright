#!/bin/bash
# Tests for scripts/orchestrate-backends.sh — the host-backend AUTODETECTION
# and unattended SELECTION path for /orchestrate (orchestration-fleet Task 2;
# D-3, REQ-B1.4). It is the scripts-level realization of the Task 1 backend
# capability contract's advertisement mechanism
# (doctrine/backend-capability-contract.md, D-2).
#
# Contract under test:
#   - `detect [pluggable-name...]` reports exactly the backends PRESENT on the
#     host, each with its advertised capability set as a TSV row
#     (backend, interactive, can_observe, can_steer_inflight,
#      provides_attention_surface, supports_parallel, session_grade, overhead,
#      hook_registration), richest rung first. `in-session` and `print` are
#     always present; `subagent` is present by default (the harness-native
#     runtime) and `tmux` is present iff it resolves on PATH — both overridable
#     via PLANWRIGHT_BACKEND_{SUBAGENT,TMUX} so a host/test can force presence.
#     The contract-defined `stream-json-persistent` and `headless-oneshot` rows
#     (execution-backends REQ-A1.2, REQ-A1.3) default ABSENT until their
#     dispatch support lands (execution-backends Tasks 3–4), overridable via
#     PLANWRIGHT_BACKEND_{STREAM_JSON_PERSISTENT,HEADLESS_ONESHOT}. A pluggable
#     name is present iff a `planwright-backend-<name>` adapter on PATH answers
#     `advertise` with a well-formed capability set; a malformed/absent adapter
#     is reported absent.
#   - The adapter `advertise` grammar is 6→8 back-compatible (execution-backends
#     D-13, REQ-A1.7): an eight-field line parses fully; a legacy six-field line
#     is accepted with fail-safe defaults (hook_registration=false, overhead
#     treated as the most conservative class, full-session+supervisor); a
#     seven-field or nine-plus-field line is malformed and fails closed with a
#     VISIBLE diagnostic, never a silent absence. Advertise lines are
#     length-bounded and stripped of non-printable bytes before any use or echo
#     (REQ-A1.9).
#   - The contract doc's backend table (doctrine/backend-capability-contract.md)
#     and this script agree for every row and field under the drift guard below
#     (execution-backends REQ-A1.6), and the doc records the pinned
#     degradation-ladder ordering and pinned overhead enum (REQ-A1.8).
#   - `select-unattended [--tmux-candidate] <configured>` makes the
#     dispatch-time pick (execution-backends Task 5; D-8, REQ-B1.1, REQ-B1.4,
#     REQ-B1.5). The semantic value `full-session` walks the pinned ladder over
#     the PRESENT rungs — tmux only under --tmux-candidate (the operator's
#     tmux-context answer), then stream-json-persistent > headless-oneshot >
#     subagent > in-session — never silently interactive, never the manual
#     `print` rung; degrading past the session-grade rungs prints a NOTE to
#     stderr and still exits 0. An explicit LITERAL is honored when present
#     (interactive and manual included: explicit config is the operator's
#     standing answer) and FAILS CLOSED when not advertised on the host —
#     exit 6, the missing backend named on stderr, no substitute on stdout
#     (dispatch-time ladders apply to semantic values only, REQ-B1.5).
#   - Every task/backend token is treated as DATA: a hostile pluggable name
#     (traversal, glob, bad charset) is refused before it is used to build the
#     `planwright-backend-<name>` command, never interpolated.
#   - Fail-closed usage: no subcommand, an unknown subcommand, or
#     select-unattended with no configured backend exit 2.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH
# Hermeticity: the suite controls backend presence only via per-invocation env
# prefixes (and the real `command -v` probe for the unforced cases). A backend
# override inherited from the developer's/CI's ambient shell would flip those
# cases, so clear them up front — including the two new-row overrides, whose
# ambient presence would flip the default-absent assertions in test 31.
unset PLANWRIGHT_BACKEND_TMUX PLANWRIGHT_BACKEND_SUBAGENT \
  PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT PLANWRIGHT_BACKEND_HEADLESS_ONESHOT

here=$(cd "$(dirname "$0")" && pwd)
BACKENDS="$here/../scripts/orchestrate-backends.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$BACKENDS" ] || fail "scripts/orchestrate-backends.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A scrubbed bin dir seeded with symlinks to exactly the tools the script uses,
# so a test can control tmux/adapter presence on PATH without a real tmux and
# without the ambient PATH leaking one in. Detection of tmux is forced via the
# env override in most cases; the fake-tmux-on-PATH case exercises the real
# `command -v` probe.
BIN="$tmp/bin"
mkdir -p "$BIN"
for t in sh env cat awk sed tr grep printf command dirname basename; do
  p=$(command -v "$t" 2>/dev/null) || true
  [ -n "$p" ] && ln -sf "$p" "$BIN/$t" 2>/dev/null || true
done

# Field extractor: prints field N (1-based) of the detect row for <backend>.
field_of() {
  printf '%s\n' "$1" | awk -F"$TAB" -v b="$2" -v n="$3" '$1==b {print $n; found=1} END{if(!found) exit 3}'
}
row_present() {
  printf '%s\n' "$1" | awk -F"$TAB" -v b="$2" '$1==b {f=1} END{exit f?0:1}'
}

# A fake pluggable adapter that advertises the given capability set. Takes the
# name plus the advertise-line fields verbatim (6 for a legacy line, 8 for the
# full grammar, any other arity to exercise the malformed paths).
# usage: make_adapter <name> <field>...
make_adapter() {
  name="$1"
  shift
  cat >"$BIN/planwright-backend-$name" <<EOF
#!/bin/sh
[ "\$1" = advertise ] || exit 2
printf '%s\n' "$*"
EOF
  chmod +x "$BIN/planwright-backend-$name"
}

# ---------------------------------------------------------------------------
# 1. detect: the always-present backends and their advertised sets.
# ---------------------------------------------------------------------------
out=$(PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" detect) || fail "detect exited non-zero"
for b in subagent in-session print; do
  row_present "$out" "$b" || fail "detect: expected $b to be present"
done
[ "$(field_of "$out" print 7)" = deferred ] \
  || fail "detect: print session_grade should be 'deferred'"
[ "$(field_of "$out" subagent 6)" = true ] \
  || fail "detect: subagent supports_parallel should be 'true'"
[ "$(field_of "$out" in-session 6)" = false ] \
  || fail "detect: in-session supports_parallel should be 'false'"
[ "$(field_of "$out" subagent 2)" = false ] \
  || fail "detect: subagent interactive should be 'false'"
# The two appended fields (execution-backends REQ-A1.1, REQ-A1.8): overhead
# (col 8) and hook_registration (col 9), pinned per row.
[ "$(field_of "$out" subagent 8)" = light ] \
  || fail "detect: subagent overhead should be 'light'"
[ "$(field_of "$out" subagent 9)" = false ] \
  || fail "detect: subagent hook_registration should be 'false'"
[ "$(field_of "$out" print 8)" = none ] \
  || fail "detect: print overhead should be 'none'"
[ "$(field_of "$out" in-session 8)" = none ] \
  || fail "detect: in-session overhead should be 'none'"
echo "ok: detect reports the always-present backends with their advertised sets"

# ---------------------------------------------------------------------------
# 2. detect: tmux absent (forced) → not reported; present (forced) → reported
#    with the contract's rich advertised set.
# ---------------------------------------------------------------------------
out=$(PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" detect)
row_present "$out" tmux && fail "detect: tmux forced absent should not be reported"
out=$(PLANWRIGHT_BACKEND_TMUX=1 "$BACKENDS" detect) || fail "detect(tmux=1) non-zero"
row_present "$out" tmux || fail "detect: tmux forced present should be reported"
[ "$(field_of "$out" tmux 2)" = true ] || fail "detect: tmux interactive should be 'true'"
[ "$(field_of "$out" tmux 3)" = true ] || fail "detect: tmux can_observe should be 'true'"
[ "$(field_of "$out" tmux 4)" = true ] || fail "detect: tmux can_steer_inflight should be 'true'"
[ "$(field_of "$out" tmux 7)" = yes ] || fail "detect: tmux session_grade should be 'yes'"
[ "$(field_of "$out" tmux 8)" = full-session ] \
  || fail "detect: tmux overhead should be 'full-session'"
[ "$(field_of "$out" tmux 9)" = true ] \
  || fail "detect: tmux hook_registration should be 'true'"
echo "ok: detect includes/excludes tmux by advertised presence"

# ---------------------------------------------------------------------------
# 3. detect: real `command -v` probe — a fake tmux on PATH is detected when the
#    override is unset (the genuine autodetection path, not the env shortcut).
# ---------------------------------------------------------------------------
ln -sf "$BIN/cat" "$BIN/tmux" # any executable named tmux satisfies command -v
out=$(PATH="$BIN" "$BACKENDS" detect) || fail "detect(real probe) non-zero"
row_present "$out" tmux || fail "detect: a fake tmux on PATH should autodetect present"
rm -f "$BIN/tmux"
out=$(PATH="$BIN" "$BACKENDS" detect) || fail "detect(real probe, no tmux) non-zero"
row_present "$out" tmux && fail "detect: no tmux on scrubbed PATH should autodetect absent"
echo "ok: detect autodetects tmux via the real command -v probe when unforced"

# ---------------------------------------------------------------------------
# 4. detect: a pluggable backend advertised via its adapter is reported.
# ---------------------------------------------------------------------------
make_adapter foo false true true false true yes
out=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" detect foo) \
  || fail "detect(pluggable) non-zero"
row_present "$out" foo || fail "detect: pluggable foo with an adapter should be present"
[ "$(field_of "$out" foo 4)" = true ] || fail "detect: foo can_steer_inflight should be 'true'"
[ "$(field_of "$out" foo 7)" = yes ] || fail "detect: foo session_grade should be 'yes'"
# A legacy six-field adapter line gets the fail-safe defaults (D-13):
# hook_registration=false, overhead = the most conservative class.
[ "$(field_of "$out" foo 8)" = full-session+supervisor ] \
  || fail "detect: a six-field adapter must default overhead to full-session+supervisor"
[ "$(field_of "$out" foo 9)" = false ] \
  || fail "detect: a six-field adapter must default hook_registration to false"
# A pluggable name equal to a known backend is not double-reported.
n=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" detect subagent \
  | awk -F"$TAB" '$1=="subagent"{c++} END{print c+0}')
[ "$n" = 1 ] || fail "detect: a pluggable arg naming a known backend must not duplicate it"
echo "ok: detect reports an advertised pluggable backend and dedupes known names"

# ---------------------------------------------------------------------------
# 5. detect: an absent or malformed adapter is reported absent (fail-safe: a
#    backend with unknown capabilities is never advertised).
# ---------------------------------------------------------------------------
out=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" detect nope 2>/dev/null) \
  || fail "detect(absent adapter) non-zero"
row_present "$out" nope && fail "detect: a pluggable with no adapter should be absent"
cat >"$BIN/planwright-backend-bad" <<'EOF'
#!/bin/sh
echo "garbage output not a capability set"
EOF
chmod +x "$BIN/planwright-backend-bad"
out=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" detect bad 2>/dev/null) \
  || fail "detect(malformed adapter) non-zero"
row_present "$out" bad && fail "detect: a malformed adapter should be reported absent"
echo "ok: detect treats an absent or malformed adapter as absent"

# ---------------------------------------------------------------------------
# 6. select-unattended: configured backend present & eligible → picked, no
#    degrade (nothing on stderr).
# ---------------------------------------------------------------------------
err="$tmp/err"
sel=$(PLANWRIGHT_BACKEND_TMUX=1 "$BACKENDS" select-unattended subagent 2>"$err") \
  || fail "select-unattended subagent non-zero"
[ "$sel" = subagent ] || fail "select-unattended: configured subagent should be picked, got '$sel'"
[ ! -s "$err" ] || fail "select-unattended: an un-degraded pick must not warn"
echo "ok: select-unattended picks an eligible configured backend without degrading"

# ---------------------------------------------------------------------------
# 7. select-unattended: an explicitly configured LITERAL present on the host is
#    honored — the interactive tmux and manual print rungs included (explicit
#    config is the operator's standing answer, never a silent pick; REQ-B1.5's
#    honored-or-halted rule for literals).
# ---------------------------------------------------------------------------
sel=$(PLANWRIGHT_BACKEND_TMUX=1 "$BACKENDS" select-unattended tmux 2>"$err") \
  || fail "select-unattended tmux non-zero"
[ "$sel" = tmux ] || fail "select-unattended: an explicit present tmux literal must be honored, got '$sel'"
[ ! -s "$err" ] || fail "select-unattended: honoring an explicit literal must not warn"
sel=$(PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" select-unattended print 2>"$err") \
  || fail "select-unattended print non-zero"
[ "$sel" = print ] || fail "select-unattended: an explicit print literal must be honored, got '$sel'"
echo "ok: select-unattended honors an explicit present literal (interactive/manual included)"

# ---------------------------------------------------------------------------
# 8. select-unattended: an explicitly configured backend NOT advertised on the
#    host fails closed (REQ-B1.5): exit 6, the missing backend named on
#    stderr, and NO substitute selection on stdout — never a silent degrade.
# ---------------------------------------------------------------------------
rc=0
sel=$(PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" select-unattended tmux 2>"$err") || rc=$?
[ "$rc" = 6 ] || fail "select-unattended: an absent explicit literal should exit 6, got $rc"
[ -z "$sel" ] || fail "select-unattended: a fail-closed halt must not print a substitute, got '$sel'"
grep -q "tmux" "$err" || fail "select-unattended: the halt diagnostic must name the missing backend"
rc=0
sel=$(PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" select-unattended headless-oneshot 2>"$err") || rc=$?
[ "$rc" = 6 ] || fail "select-unattended: absent headless-oneshot should exit 6, got $rc"
[ -z "$sel" ] || fail "select-unattended: the headless-oneshot halt must not print a substitute, got '$sel'"
grep -q "headless-oneshot" "$err" \
  || fail "select-unattended: the halt diagnostic must name headless-oneshot"
echo "ok: select-unattended fails closed on an explicit unadvertised literal (exit 6)"

# ---------------------------------------------------------------------------
# 9. select-unattended: a configured PLUGGABLE present via its adapter is
#    honored — the interactive pluggable included (same standing-answer rule).
# ---------------------------------------------------------------------------
sel=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" select-unattended foo 2>"$err") \
  || fail "select-unattended(pluggable foo) non-zero"
[ "$sel" = foo ] || fail "select-unattended: eligible configured pluggable foo should be picked, got '$sel'"
make_adapter bar true true true false true yes
sel=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" select-unattended bar 2>"$err") \
  || fail "select-unattended(interactive pluggable) non-zero"
[ "$sel" = bar ] || fail "select-unattended: an explicit present interactive pluggable must be honored, got '$sel'"
echo "ok: select-unattended honors an explicit present pluggable literal"

# ---------------------------------------------------------------------------
# 10. select-unattended: the `full-session` SEMANTIC value walks the pinned
#     ladder over the present non-interactive rungs (REQ-B1.1, REQ-A1.8):
#     stream-json-persistent > headless-oneshot > subagent > in-session; never
#     tmux without --tmux-candidate, never print; degrading past the
#     session-grade rungs emits a NOTE and still exits 0.
# ---------------------------------------------------------------------------
sel=$(PLANWRIGHT_BACKEND_TMUX=1 PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=1 \
  PLANWRIGHT_BACKEND_HEADLESS_ONESHOT=1 "$BACKENDS" select-unattended full-session 2>"$err") \
  || fail "select-unattended(full-session) non-zero"
[ "$sel" = stream-json-persistent ] \
  || fail "full-session should pick the richest non-interactive session-grade rung, got '$sel'"
[ ! -s "$err" ] || fail "full-session resolving to a session-grade rung must not warn"
sel=$(PLANWRIGHT_BACKEND_TMUX=1 PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=0 \
  PLANWRIGHT_BACKEND_HEADLESS_ONESHOT=1 "$BACKENDS" select-unattended full-session 2>"$err") \
  || fail "select-unattended(full-session, ho) non-zero"
[ "$sel" = headless-oneshot ] \
  || fail "full-session should walk the ladder to headless-oneshot, got '$sel'"
sel=$(PLANWRIGHT_BACKEND_TMUX=1 PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=0 \
  "$BACKENDS" select-unattended full-session 2>"$err") \
  || fail "select-unattended(full-session, no session rung) non-zero"
[ "$sel" = subagent ] \
  || fail "full-session with no non-interactive session-grade rung should degrade to subagent, got '$sel'"
grep -q NOTE "$err" || fail "full-session degrading past the session-grade rungs must NOTE on stderr"
# The NOTE must not claim the host advertises NO session-grade backend: tmux is
# session-grade and IS advertised in this very case (PLANWRIGHT_BACKEND_TMUX=1
# above) — it is merely not a candidate without the tmux-context ask. An
# unqualified "no session-grade backend" reads as a host-capability claim and
# misleads the operator into thinking tmux is unavailable.
grep -q "non-interactive session-grade" "$err" \
  || fail "full-session degrade NOTE must scope the absence to NON-interactive session-grade rungs (tmux may be advertised)"
sel=$(PLANWRIGHT_BACKEND_TMUX=0 PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=0 \
  PLANWRIGHT_BACKEND_SUBAGENT=0 "$BACKENDS" select-unattended full-session 2>"$err") \
  || fail "select-unattended(full-session, no subagent) non-zero"
[ "$sel" = in-session ] \
  || fail "full-session must reach the in-session terminal rung, got '$sel'"
# --tmux-candidate: the operator's tmux-context answer adds tmux to the top of
# the candidate set; with tmux absent the flag falls through, never a halt
# (the flag joins a candidate — it is not an explicit literal).
sel=$(PLANWRIGHT_BACKEND_TMUX=1 PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=1 \
  "$BACKENDS" select-unattended --tmux-candidate full-session 2>"$err") \
  || fail "select-unattended(--tmux-candidate) non-zero"
[ "$sel" = tmux ] \
  || fail "--tmux-candidate with tmux present must pick tmux for full-session, got '$sel'"
sel=$(PLANWRIGHT_BACKEND_TMUX=0 PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=1 \
  "$BACKENDS" select-unattended --tmux-candidate full-session 2>"$err") \
  || fail "select-unattended(--tmux-candidate, tmux absent) non-zero"
[ "$sel" = stream-json-persistent ] \
  || fail "--tmux-candidate with tmux absent must fall through the ladder, got '$sel'"
# The flag only widens the full-session candidate set; an explicit literal is
# unaffected by it (still honored-or-halted).
rc=0
sel=$(PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" select-unattended --tmux-candidate tmux 2>"$err") || rc=$?
[ "$rc" = 6 ] || fail "--tmux-candidate must not rescue an absent explicit literal, got exit $rc"
echo "ok: full-session walks the pinned ladder; --tmux-candidate admits tmux as a candidate"

# ---------------------------------------------------------------------------
# 11. input-as-data: a hostile pluggable name is refused, never interpolated
#     into the adapter command; a hostile configured name is a usage error.
# ---------------------------------------------------------------------------
canary="$tmp/canary"
out=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" detect "../../etc; touch $canary" 2>/dev/null) || true
[ ! -e "$canary" ] || fail "detect: a hostile pluggable name must not be executed"
printf '%s\n' "$out" | awk -F"$TAB" '$1 ~ /etc|touch|\.\./ {exit 1}' \
  || fail "detect: a hostile pluggable name must not appear as a backend row"
rc=0
PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" select-unattended "foo/../bar" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "select-unattended: a hostile configured name should be a usage error (2), got $rc"
echo "ok: hostile backend names are treated as data (refused, never executed)"

# ---------------------------------------------------------------------------
# 12. the semantic-resolution matrix (REQ-B1.4): without --tmux-candidate,
#     full-session NEVER yields an interactive or manual backend across every
#     presence combination — only explicit config can select one. A valid-name
#     but unadvertised literal (bogus) halts fail-closed rather than degrading.
# ---------------------------------------------------------------------------
for tm in 0 1; do
  for sjp in 0 1; do
    for ho in 0 1; do
      sel=$(PLANWRIGHT_BACKEND_TMUX=$tm PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=$sjp \
        PLANWRIGHT_BACKEND_HEADLESS_ONESHOT=$ho "$BACKENDS" select-unattended full-session 2>/dev/null) \
        || fail "select-unattended(full-session,tmux=$tm,sjp=$sjp,ho=$ho) non-zero"
      [ "$sel" != tmux ] || fail "full-session matrix picked interactive tmux (tmux=$tm)"
      [ "$sel" != print ] || fail "full-session matrix picked manual print"
      [ -n "$sel" ] || fail "full-session matrix: empty selection"
    done
  done
done
rc=0
PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" select-unattended bogus >/dev/null 2>&1 || rc=$?
[ "$rc" = 6 ] || fail "an unadvertised valid-name literal must halt (exit 6), got $rc"
echo "ok: full-session never yields an interactive or manual backend without explicit config"

# ---------------------------------------------------------------------------
# 13. usage / fail-closed.
# ---------------------------------------------------------------------------
rc=0
"$BACKENDS" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "usage: no subcommand returned $rc, expected 2"
rc=0
"$BACKENDS" frobnicate >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "usage: unknown subcommand returned $rc, expected 2"
# Echo discipline: an unknown subcommand carrying an ESC/OSC sequence fails closed
# AND never leaks its raw control bytes to stderr (mirrors the sanitized invalid-
# name diagnostics this script already emits for detect/select-unattended).
escsub=$(printf 'frob\033]0;INJECT\007nicate')
rc=0
subErr=$("$BACKENDS" "$escsub" 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "usage: escape-laden subcommand returned $rc, expected 2"
subStripped=$(printf '%s' "$subErr" | tr -d '\000-\037\177')
[ "$subStripped" = "$subErr" ] \
  || fail "usage: raw control/escape bytes leaked to stderr from an unknown subcommand"
rc=0
"$BACKENDS" select-unattended >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "usage: select-unattended with no arg returned $rc, expected 2"
# select-unattended takes exactly one <configured> arg: an extra positional is a
# caller mistake and must fail closed (exit 2), never be silently ignored.
rc=0
PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" select-unattended foo bar >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "usage: select-unattended with extra args returned $rc, expected 2"
echo "ok: usage errors and an unknown subcommand fail closed (exit 2)"

# ---------------------------------------------------------------------------
# 14. detect: rows are emitted richest rung first — the documented ordering
#     contract (tmux → advertised pluggables → subagent → in-session → print).
#     Presence tests above never pin the relative order, so a reordering of the
#     emit_row sequence would pass unnoticed; this asserts it directly.
# ---------------------------------------------------------------------------
make_adapter ordp false true true false true yes
order=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=1 "$BACKENDS" detect ordp \
  | awk -F"$TAB" '{printf "%s ", $1}')
[ "$order" = "tmux ordp subagent in-session print " ] \
  || fail "detect: rows must be emitted richest rung first, got '$order'"
echo "ok: detect emits rows richest rung first"

# ---------------------------------------------------------------------------
# 15. select-unattended: a configured PLUGGABLE with no adapter (absent, not
#     malformed) is an explicit-but-unavailable literal — it halts fail-closed
#     (exit 6) naming the backend, the same REQ-B1.5 path a missing shipped
#     backend takes (case 8), never a silent degrade.
# ---------------------------------------------------------------------------
rc=0
sel=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" select-unattended ghost 2>"$err") || rc=$?
[ "$rc" = 6 ] || fail "select-unattended: an absent configured pluggable should exit 6, got $rc"
[ -z "$sel" ] || fail "select-unattended: an absent-pluggable halt must not print a substitute"
grep -q "ghost" "$err" || fail "select-unattended: the halt diagnostic must name the pluggable"
echo "ok: select-unattended halts fail-closed on an absent configured pluggable"

# ---------------------------------------------------------------------------
# 16. echo discipline (doctrine/security-posture.md): an invalid backend name
#     carrying control/escape bytes is SANITIZED before it reaches stderr, and
#     detect still continues to emit the always-present rows after refusing it.
#     Guards the fix for the terminal-escape/log-injection finding — a raw ESC
#     in a rejected name must never survive into the diagnostic.
# ---------------------------------------------------------------------------
esc=$(printf 'ev\033]0;PWNED\007il')
out=$(PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" detect "$esc" 2>"$err") \
  || fail "detect(control-byte name) non-zero"
if LC_ALL=C grep -q "$(printf '\033')" "$err"; then
  fail "detect: an invalid name's control bytes must be stripped before echo"
fi
grep -q "ignoring invalid backend name" "$err" \
  || fail "detect: a refused invalid name should still be reported (sanitized) on stderr"
row_present "$out" subagent \
  || fail "detect: must continue emitting always-present rows after refusing an invalid name"
row_present "$out" in-session \
  || fail "detect: must continue emitting in-session after refusing an invalid name"
echo "ok: detect sanitizes a refused invalid name's control bytes and continues"

# ---------------------------------------------------------------------------
# 17. detect: a well-formed first six tokens followed by an extra trailing token
#     is a SEVEN-field line — malformed under the 6-or-8 grammar (REQ-A1.7) →
#     reported absent, with the visible malformed-line diagnostic (never a
#     silent absence).
# ---------------------------------------------------------------------------
cat >"$BIN/planwright-backend-extra" <<'EOF'
#!/bin/sh
[ "$1" = advertise ] || exit 2
printf '%s\n' "false false false false true no EXTRA"
EOF
chmod +x "$BIN/planwright-backend-extra"
out=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" detect extra 2>"$err") \
  || fail "detect(extra-token adapter) non-zero"
row_present "$out" extra \
  && fail "detect: an adapter set with a trailing extra token must be reported absent"
grep -q "malformed advertise line" "$err" \
  || fail "detect: a seven-field advertise line must get the visible malformed diagnostic"
echo "ok: detect rejects a seven-field adapter set with a visible diagnostic"

# ---------------------------------------------------------------------------
# 18. detect: five valid booleans plus an INVALID session_grade sixth token
#     exercises the session_grade validation branch (yes|no|deferred) that the
#     bad-boolean malformed test short-circuits before reaching → reported absent.
# ---------------------------------------------------------------------------
make_adapter badsg false false false false true maybe
out=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" detect badsg 2>/dev/null) \
  || fail "detect(bad session_grade) non-zero"
row_present "$out" badsg \
  && fail "detect: an adapter with an invalid session_grade token must be reported absent"
echo "ok: detect rejects an adapter with an invalid session_grade token"

# ---------------------------------------------------------------------------
# 19. present: renders detect's TSV rows as the two-seam presentation the
#     entry command shows an attended operator (orchestration-fleet Task 10;
#     D-9, D-12, REQ-E1.2, REQ-E1.5). The header frames the seams (the decision
#     queue is the default attention surface regardless of the execution pick),
#     each backend keeps detect's richest-first order, and an INTERACTIVE
#     multiplexer row carries the detached-background-plumbing note so the
#     approachable path is the default presentation, not a fallback behind tmux.
# ---------------------------------------------------------------------------
# stream-json-persistent pinned absent: its default is now the installed-CLI
# probe (Task 4), and this fixture's expected block set must not vary by host.
out=$(PLANWRIGHT_BACKEND_TMUX=1 PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=0 \
  "$BACKENDS" detect \
  | "$BACKENDS" present) || fail "present exited non-zero on detect output"
printf '%s\n' "$out" | grep -qi "decision queue" \
  || fail "present: header must name the decision queue as the attention surface"
printf '%s\n' "$out" | grep -qi "default" \
  || fail "present: header must present the decision queue as the DEFAULT surface"
# Header-only phrases: every block also says "decision queue (default)", so the
# two greps above alone would survive deleting the header wholesale. These two
# appear only in the header's two-seam framing.
printf '%s\n' "$out" | grep -q "execution seam" \
  || fail "present: the header must frame the pick as the execution seam"
printf '%s\n' "$out" | grep -q "richest rung first" \
  || fail "present: the header must state the richest-first ordering"
# Block extractor: prints the lines of the block for backend $2 (from its
# "* <name>:" line up to the next "* " line).
block_of() {
  printf '%s\n' "$1" | awk -v b="$2" '
    $0 ~ "^\\* " b ":" {inb=1}
    inb && $0 ~ "^\\* " && $0 !~ "^\\* " b ":" {inb=0}
    inb {print}'
}
tb=$(block_of "$out" tmux)
[ -n "$tb" ] || fail "present: tmux row missing from the presentation"
printf '%s\n' "$tb" | grep -q "detached background server" \
  || fail "present: interactive tmux block must carry the detached-plumbing note"
printf '%s\n' "$tb" | grep -q "never required" \
  || fail "present: the detached-plumbing note must say attaching is never required"
# The summary is derived one token per advertised capability; asserting the
# full five-token line means dropping (or mislabeling) any single pb_add
# branch in emit_block fails here instead of passing silently.
printf '%s\n' "$tb" \
  | grep -q "interactive, observe in-flight, steer in-flight, parallel workers, session-grade workers" \
  || fail "present: tmux's summary must carry all five advertised feature tokens"
# The advertised overhead class (REQ-A1.1) renders on every block, so the
# operator's smallest-sufficient-rung choice can see the per-dispatch cost.
printf '%s\n' "$tb" | grep -q "overhead: full-session" \
  || fail "present: tmux's block must render its advertised overhead class"
sb=$(block_of "$out" subagent)
printf '%s\n' "$sb" | grep -q "overhead: light" \
  || fail "present: subagent's block must render its advertised overhead class"
printf '%s\n' "$sb" | grep -q "decision queue (default)" \
  || fail "present: a backend with no own surface must default to the decision queue"
printf '%s\n' "$sb" | grep -q "detached" \
  && fail "present: a non-interactive backend must not carry the plumbing note"
order=$(printf '%s\n' "$out" | awk '/^\* / {sub(/^\* /,""); sub(/:.*/,""); printf "%s ", $0}')
[ "$order" = "tmux subagent in-session print " ] \
  || fail "present: blocks must keep detect's richest-first order, got '$order'"
# The advertised-set-derived summary branches: in-session (nothing true, na
# observe/steer) must hit the empty-feature fallback — which also proves na
# fields are skipped, not treated as capabilities — and print
# (session_grade=deferred) must carry the manual-dispatch phrasing.
ib=$(block_of "$out" in-session)
printf '%s\n' "$ib" | grep -q "synchronous, in the tower's own session" \
  || fail "present: in-session must render the empty-feature fallback summary"
printf '%s\n' "$ib" | grep -Eq "observe in-flight|steer in-flight" \
  && fail "present: in-session's na observe/steer fields must not surface as features"
prb=$(block_of "$out" print)
printf '%s\n' "$prb" | grep -q "manual dispatch" \
  || fail "present: print (session_grade=deferred) must carry the manual-dispatch phrasing"
echo "ok: present renders the two-seam presentation with the detached-plumbing note"

# ---------------------------------------------------------------------------
# 20. present: a backend advertising provides_attention_surface=true is marked
#     as owning the operator's surface, and the presentation says planwright
#     DEFERS its own queue (the --surface-provided deferral, D-13) — the
#     attention-seam half of adapt-to-advertised.
# ---------------------------------------------------------------------------
row=$(printf 'cmuxish\ttrue\ttrue\ttrue\ttrue\ttrue\tyes\tfull-session\ttrue\n')
out=$(printf '%s\n' "$row" | "$BACKENDS" present) \
  || fail "present exited non-zero on a provides-surface row"
cb=$(block_of "$out" cmuxish)
printf '%s\n' "$cb" | grep -q "provides its own" \
  || fail "present: a provides_attention_surface backend must be marked as owning the surface"
printf '%s\n' "$cb" | grep -q -- "--surface-provided" \
  || fail "present: the defer note must name the --surface-provided signal"
echo "ok: present defers to a backend that provides its own attention surface"

# ---------------------------------------------------------------------------
# 21. present: fail-closed input handling. present's stdin is detect's own
#     output, so a malformed row is a framework bug, never silently skipped:
#     wrong field count, a bad boolean, empty input, and a stray positional
#     argument all exit 2.
# ---------------------------------------------------------------------------
rc=0
printf 'tmux\ttrue\ttrue\n' | "$BACKENDS" present >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "present: a short row returned $rc, expected 2"
grep -q "malformed detect row" "$err" \
  || fail "present: a short row must get the malformed-detect-row diagnostic"
rc=0
printf 'tmux\ttrue\ttrue\ttrue\tfalse\ttrue\tmaybe\tfull-session\ttrue\n' \
  | "$BACKENDS" present >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "present: an invalid session_grade returned $rc, expected 2"
grep -q "malformed session_grade" "$err" \
  || fail "present: an invalid session_grade must get its own diagnostic, not a generic one"
rc=0
printf 'tmux\tmaybe\ttrue\ttrue\tfalse\ttrue\tyes\tfull-session\ttrue\n' \
  | "$BACKENDS" present >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "present: an invalid capability boolean returned $rc, expected 2"
grep -q "malformed capability field" "$err" \
  || fail "present: an invalid capability boolean must get the capability-field diagnostic"
# The two appended columns validate too: a bad overhead class and a bad
# hook_registration token each fail closed with their own diagnostic.
rc=0
printf 'tmux\ttrue\ttrue\ttrue\tfalse\ttrue\tyes\tenormous\ttrue\n' \
  | "$BACKENDS" present >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "present: an invalid overhead class returned $rc, expected 2"
grep -q "malformed overhead" "$err" \
  || fail "present: an invalid overhead class must get its own diagnostic"
rc=0
printf 'tmux\ttrue\ttrue\ttrue\tfalse\ttrue\tyes\tfull-session\tmaybe\n' \
  | "$BACKENDS" present >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "present: an invalid hook_registration returned $rc, expected 2"
grep -q "malformed hook_registration" "$err" \
  || fail "present: an invalid hook_registration must get its own diagnostic"
# A legacy seven-column row (the pre-extension detect shape) is no longer a
# well-formed detect row: present's input is detect's OWN output, so a
# column-count mismatch means a broken producer and fails closed.
rc=0
printf 'tmux\ttrue\ttrue\ttrue\tfalse\ttrue\tyes\n' \
  | "$BACKENDS" present >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "present: a seven-column legacy row returned $rc, expected 2"
grep -q "malformed detect row" "$err" \
  || fail "present: a seven-column legacy row must get the malformed-detect-row diagnostic"
rc=0
printf '' | "$BACKENDS" present >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "present: empty input returned $rc, expected 2 (detect always emits rows)"
rc=0
printf 'subagent\tfalse\tfalse\tfalse\tfalse\ttrue\tno\tlight\tfalse\n' \
  | "$BACKENDS" present extra >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "present: a stray positional arg returned $rc, expected 2"
echo "ok: present fails closed on malformed rows, empty input, and stray args"

# ---------------------------------------------------------------------------
# 22. present: echo discipline — a hand-corrupted row whose backend name
#     carries control/escape bytes is refused with a SANITIZED diagnostic (no
#     raw ESC reaches stderr), the same terminal-escape guard detect applies.
# ---------------------------------------------------------------------------
rc=0
printf '%s\ttrue\ttrue\ttrue\tfalse\ttrue\tyes\tfull-session\ttrue\n' "$(printf 'ev\033]0;PWNED\007il')" \
  | "$BACKENDS" present >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "present: a control-byte backend name returned $rc, expected 2"
if LC_ALL=C grep -q "$(printf '\033')" "$err"; then
  fail "present: a refused name's control bytes must be stripped before echo"
fi
grep -q "malformed detect row" "$err" \
  || fail "present: the refused hostile row must still be reported (sanitized), not fail silently"
echo "ok: present sanitizes a refused hostile row's control bytes"

# ---------------------------------------------------------------------------
# 23. present: the no-partial-output guarantee — a valid first row followed by
#     a malformed second row must emit NOTHING on stdout (all rows validate
#     before any rendering), so an operator can never act on a truncated
#     backend list. Guards the two-loop validate-then-render structure.
# ---------------------------------------------------------------------------
rc=0
outp=$(printf 'tmux\ttrue\ttrue\ttrue\tfalse\ttrue\tyes\tfull-session\ttrue\nBAD ROW\n' \
  | "$BACKENDS" present 2>/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "present: valid-then-malformed input returned $rc, expected 2"
[ -z "$outp" ] \
  || fail "present: a malformed later row must suppress ALL output, got '$outp'"
echo "ok: present emits no partial surface when a later row is malformed"

# ---------------------------------------------------------------------------
# 24. present: strict field count — TAB is IFS whitespace, so a hand-corrupted
#     row with an empty field (consecutive tabs) would collapse and could
#     re-align into nine valid-looking tokens; the eight-tab count guard must
#     refuse it. Here: empty eighth field plus a stray trailing token, which
#     token-collapse alone would mis-read as a well-formed row.
# ---------------------------------------------------------------------------
rc=0
printf 'tmux\ttrue\ttrue\ttrue\tfalse\ttrue\tyes\t\tfull-session\ttrue\n' \
  | "$BACKENDS" present >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "present: a double-tab (empty-field) row returned $rc, expected 2"
# The malformed-row diagnostic is capped: a zero-tab line has no field boundary
# to strip at, so without a cap the whole corrupted line would be echoed.
rc=0
printf '%0300d\n' 0 | tr '0' 'x' | "$BACKENDS" present >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "present: a long zero-tab row returned $rc, expected 2"
[ "$(wc -c <"$err")" -lt 160 ] \
  || fail "present: the malformed-row diagnostic must cap the echoed line"
echo "ok: present refuses a row whose tab count betrays an empty field"
# The complementary shape: exactly eight tabs with an empty MIDDLE field passes
# the tab-count guard, so only the field-validation loop can catch it — after
# token collapse the trailing vars land empty/shifted (p_p lands 'yes').
# Pins the loop interplay so a reorder of the validate loops cannot silently
# accept a collapsed row. No stdout: the fail-closed guarantee holds here too.
rc=0
outp=$(printf 'tmux\ttrue\t\ttrue\tfalse\ttrue\tyes\tfull-session\ttrue\n' \
  | "$BACKENDS" present 2>/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "present: an eight-tab empty-middle-field row returned $rc, expected 2"
[ -z "$outp" ] \
  || fail "present: an eight-tab empty-middle-field row must emit no output, got '$outp'"
echo "ok: present refuses an eight-tab row whose empty middle field collapses"

# ---------------------------------------------------------------------------
# 25. echo discipline on the dispatcher: an unknown subcommand carrying
#     control/escape bytes is reported SANITIZED (no raw ESC reaches stderr),
#     matching the treatment every refused backend name gets.
# ---------------------------------------------------------------------------
rc=0
"$BACKENDS" "$(printf 'fr\033]0;PWNED\007ob')" >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "unknown subcommand with control bytes returned $rc, expected 2"
if LC_ALL=C grep -q "$(printf '\033')" "$err"; then
  fail "dispatcher: an unknown subcommand's control bytes must be stripped before echo"
fi
grep -q "unknown subcommand" "$err" \
  || fail "dispatcher: the unknown-subcommand diagnostic should still be reported (sanitized)"
echo "ok: the dispatcher sanitizes an unknown subcommand's control bytes"

# ---------------------------------------------------------------------------
# 26. present: na-typed fields on a RENDERED row are skipped, not treated as
#     capabilities — a pluggable adapter may advertise na for ANY of the five
#     booleans (adapter_caps admits it), so a row with interactive=na,
#     surface=na, parallel=na must render only its true features, carry no
#     plumbing note, and fall to the default attention line.
# ---------------------------------------------------------------------------
row=$(printf 'plugna\tna\ttrue\ttrue\tna\tna\tyes\tfull-session\tfalse\n')
out=$(printf '%s\n' "$row" | "$BACKENDS" present) \
  || fail "present exited non-zero on an na-heavy row"
nb=$(block_of "$out" plugna)
[ -n "$nb" ] || fail "present: plugna row missing from the presentation"
printf '%s\n' "$nb" | grep -q "observe in-flight, steer in-flight, session-grade workers" \
  || fail "present: an na-heavy row must render exactly its true features"
printf '%s\n' "$nb" | grep -q "interactive" \
  && fail "present: interactive=na must not surface as a feature"
printf '%s\n' "$nb" | grep -q "parallel workers" \
  && fail "present: supports_parallel=na must not surface as a feature"
printf '%s\n' "$nb" | grep -q "detached" \
  && fail "present: interactive=na must not carry the plumbing note"
printf '%s\n' "$nb" | grep -q "decision queue (default)" \
  || fail "present: provides_attention_surface=na must fall to the default attention line"
echo "ok: present skips na-typed fields on a rendered row"

# ---------------------------------------------------------------------------
# 27. caps <backend>: the read accessor prints one backend's eight-field
#     advertised capability set, PRESENCE-AGNOSTIC for a shipped backend
#     (advertisement is a static property of the backend type). tmux advertises
#     can_observe=true (field 2); subagent and in-session do not — the exact
#     gate Task 5's peer-pane /context corroboration reads.
# ---------------------------------------------------------------------------
out=$("$BACKENDS" caps tmux) || fail "caps tmux exited non-zero"
[ "$out" = "true true true false true yes full-session true" ] \
  || fail "caps tmux: got '$out', expected the contract-table row"
# Field 2 (can_observe) is what the capability gate reads.
obs=$(printf '%s\n' "$out" | cut -d' ' -f2)
[ "$obs" = true ] || fail "caps tmux: can_observe field '$obs', expected true"

out=$("$BACKENDS" caps subagent) || fail "caps subagent exited non-zero"
[ "$(printf '%s\n' "$out" | cut -d' ' -f2)" = false ] \
  || fail "caps subagent: can_observe should be false (no peer observation pane)"

out=$("$BACKENDS" caps in-session) || fail "caps in-session exited non-zero"
[ "$(printf '%s\n' "$out" | cut -d' ' -f2)" = na ] \
  || fail "caps in-session: can_observe should be na (no peer observation pane)"

# caps is presence-agnostic: a shipped backend forced ABSENT still advertises
# its static capability set (the gate asks about the backend type, not the host).
out=$(PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" caps tmux) \
  || fail "caps tmux (forced absent) exited non-zero"
[ "$out" = "true true true false true yes full-session true" ] \
  || fail "caps must be presence-agnostic for a shipped backend"
echo "ok: caps prints a shipped backend's advertised set, presence-agnostic"

# ---------------------------------------------------------------------------
# 28. caps fail-safe and fail-closed paths: an unknown/adapterless pluggable
#     is ABSENT (exit 1), a hostile name is refused SANITIZED (exit 2), and a
#     wrong argument count is a usage error (exit 2).
# ---------------------------------------------------------------------------
rc=0
"$BACKENDS" caps no-such-adapter >/dev/null 2>"$err" || rc=$?
[ "$rc" = 1 ] || fail "caps of an adapterless pluggable: exit $rc, expected 1 (absent)"

rc=0
"$BACKENDS" caps "$(printf 'ev\033]0;X\007il')" >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "caps of a hostile name: exit $rc, expected 2"
if LC_ALL=C grep -q "$(printf '\033')" "$err"; then
  fail "caps: a hostile backend name's control bytes must be stripped before echo"
fi

rc=0
"$BACKENDS" caps >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "caps with no argument: exit $rc, expected 2"
rc=0
"$BACKENDS" caps tmux extra >/dev/null 2>"$err" || rc=$?
[ "$rc" = 2 ] || fail "caps with an extra argument: exit $rc, expected 2"
echo "ok: caps fails safe (absent) and fails closed (usage) as specified"

# ---------------------------------------------------------------------------
# 29. caps resolves a PRESENT pluggable backend through its adapter: the
#     adapter's advertised set is printed verbatim at exit 0 (the cmd_caps
#     adapter_caps SUCCESS branch — the path a pluggable-dispatched worker's
#     capability gate takes). A present-but-MALFORMED adapter fails safe to
#     absent (exit 1), never emitting a half-parsed set. Only detect exercised
#     these adapter branches before; caps is what Task 5's peer-pane gate calls.
# ---------------------------------------------------------------------------
make_adapter plug false true true false true yes
out=$(PATH="$BIN" "$BACKENDS" caps plug) || fail "caps of a present pluggable: exited non-zero"
[ "$out" = "false true true false true yes full-session+supervisor false" ] \
  || fail "caps plug: got '$out', expected the adapter's set with the fail-safe defaults"
[ "$(printf '%s\n' "$out" | cut -d' ' -f2)" = true ] \
  || fail "caps plug: can_observe (field 2) should be true"

cat >"$BIN/planwright-backend-plugbad" <<'EOF'
#!/bin/sh
echo "garbage output not a capability set"
EOF
chmod +x "$BIN/planwright-backend-plugbad"
rc=0
PATH="$BIN" "$BACKENDS" caps plugbad >/dev/null 2>"$err" || rc=$?
[ "$rc" = 1 ] || fail "caps of a malformed present adapter: exit $rc, expected 1 (fail-safe absent)"
echo "ok: caps resolves a present pluggable adapter and fails safe on a malformed one"

# ---------------------------------------------------------------------------
# 30. The two new contract rows answer their PINNED advertised sets
#     (execution-backends REQ-A1.2, REQ-A1.3 — asserted against the pinned
#     values, not merely doc↔script parity).
# ---------------------------------------------------------------------------
out=$("$BACKENDS" caps headless-oneshot) || fail "caps headless-oneshot exited non-zero"
[ "$out" = "false false false false true yes full-session true" ] \
  || fail "caps headless-oneshot: got '$out', expected the REQ-A1.2 pinned set"
out=$("$BACKENDS" caps stream-json-persistent) \
  || fail "caps stream-json-persistent exited non-zero"
[ "$out" = "false true true false true yes full-session+supervisor true" ] \
  || fail "caps stream-json-persistent: got '$out', expected the REQ-A1.3 pinned set"
echo "ok: caps answers the REQ-A1.2/REQ-A1.3 pinned sets for the new rows"

# ---------------------------------------------------------------------------
# 31. New-row presence: stream-json-persistent gained dispatch support
#     (fleet-streamjson.sh, execution-backends Task 4), so its default is the
#     installed-CLI probe — present exactly when `claude` is on PATH, both
#     arms pinned below so the fixture is machine-independent.
#     headless-oneshot still ships ahead of its dispatch support (Task 3) and
#     defaults ABSENT — never a selectable rung the tower cannot drive — while
#     the env overrides force presence for tests and the richest-first order
#     slots them between tmux and the pluggables.
# ---------------------------------------------------------------------------
# Installed-CLI probe, absent arm: no `claude` on the pinned PATH.
out=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" detect) \
  || fail "detect exited non-zero"
row_present "$out" stream-json-persistent \
  && fail "detect: stream-json-persistent must be absent when no claude CLI is installed"
row_present "$out" headless-oneshot \
  && fail "detect: headless-oneshot must default absent until dispatch support lands"
# Installed-CLI probe, present arm: a claude stub on the pinned PATH.
printf '#!/bin/sh\nexit 0\n' >"$BIN/claude"
chmod +x "$BIN/claude"
out=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" detect) \
  || fail "detect exited non-zero (claude stub present)"
row_present "$out" stream-json-persistent \
  || fail "detect: stream-json-persistent must probe present when the claude CLI is installed"
row_present "$out" headless-oneshot \
  && fail "detect: an installed CLI must not flip headless-oneshot (Task 3 pending)"
rm -f "$BIN/claude"
out=$(PLANWRIGHT_BACKEND_TMUX=1 PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=1 \
  PLANWRIGHT_BACKEND_HEADLESS_ONESHOT=1 "$BACKENDS" detect) \
  || fail "detect(new rows forced) non-zero"
row_present "$out" stream-json-persistent \
  || fail "detect: stream-json-persistent forced present should be reported"
[ "$(field_of "$out" stream-json-persistent 3)" = true ] \
  || fail "detect: stream-json-persistent can_observe should be 'true'"
[ "$(field_of "$out" stream-json-persistent 8)" = full-session+supervisor ] \
  || fail "detect: stream-json-persistent overhead should be 'full-session+supervisor'"
[ "$(field_of "$out" headless-oneshot 4)" = false ] \
  || fail "detect: headless-oneshot can_steer_inflight should be 'false'"
[ "$(field_of "$out" headless-oneshot 9)" = true ] \
  || fail "detect: headless-oneshot hook_registration should be 'true'"
make_adapter ordq false true true false true yes
order=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=1 PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=1 \
  PLANWRIGHT_BACKEND_HEADLESS_ONESHOT=1 "$BACKENDS" detect ordq \
  | awk -F"$TAB" '{printf "%s ", $1}')
[ "$order" = "tmux stream-json-persistent headless-oneshot ordq subagent in-session print " ] \
  || fail "detect: forced-present new rows must slot per the pinned ladder, got '$order'"
# Unattended selection: an absent rung (forced absent — the default is now
# the installed-CLI probe) is an explicit-but-unavailable literal and halts
# fail-closed (REQ-B1.5); forced-present is honored.
rc=0
sel=$(PLANWRIGHT_BACKEND_TMUX=0 PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=0 \
  "$BACKENDS" select-unattended stream-json-persistent 2>"$err") || rc=$?
[ "$rc" = 6 ] \
  || fail "select-unattended: a default-absent new row should halt (exit 6), got $rc"
grep -q "stream-json-persistent" "$err" \
  || fail "select-unattended: the default-absent halt must name the backend"
sel=$(PLANWRIGHT_BACKEND_TMUX=0 PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=1 \
  "$BACKENDS" select-unattended stream-json-persistent 2>"$err") \
  || fail "select-unattended(stream-json-persistent, forced) non-zero"
[ "$sel" = stream-json-persistent ] \
  || fail "select-unattended: a forced-present new row should be picked, got '$sel'"
[ ! -s "$err" ] || fail "select-unattended: a forced-present pick must not warn"
sel=$(PLANWRIGHT_BACKEND_TMUX=0 PLANWRIGHT_BACKEND_HEADLESS_ONESHOT=1 \
  "$BACKENDS" select-unattended headless-oneshot 2>"$err") \
  || fail "select-unattended(headless-oneshot, forced) non-zero"
[ "$sel" = headless-oneshot ] \
  || fail "select-unattended: forced-present headless-oneshot should be picked, got '$sel'"
# The Task 5 ladder wiring: the new rows ARE full-session ladder targets now —
# a forced-present stream-json-persistent is the semantic value's first
# non-interactive pick, while an absent explicit literal still halts (never a
# cross-literal substitution).
sel=$(PLANWRIGHT_BACKEND_TMUX=0 PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=1 \
  "$BACKENDS" select-unattended full-session 2>"$err") \
  || fail "select-unattended(full-session, sjp forced) non-zero"
[ "$sel" = stream-json-persistent ] \
  || fail "select-unattended: full-session must ladder onto the forced-present new rung, got '$sel'"
echo "ok: the new contract rows default absent and honor the env presence overrides"

# ---------------------------------------------------------------------------
# 32. Adapter grammar, 6→8 back-compatible (D-13, REQ-A1.7): an eight-field
#     line parses fully (echoed verbatim by caps); a nine-field line is
#     malformed; both malformed arities carry the visible diagnostic, and the
#     malformed backend is never in the candidate set (fail closed, asserted by
#     exit code, absence, and diagnostic).
# ---------------------------------------------------------------------------
make_adapter full8 false true true false true yes light true
out=$(PATH="$BIN" "$BACKENDS" caps full8) || fail "caps of an eight-field adapter: non-zero"
[ "$out" = "false true true false true yes light true" ] \
  || fail "caps full8: got '$out', expected the eight-field set verbatim"
out=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" detect full8 2>/dev/null) \
  || fail "detect(eight-field adapter) non-zero"
[ "$(field_of "$out" full8 8)" = light ] \
  || fail "detect: an eight-field adapter's overhead must be carried through"
[ "$(field_of "$out" full8 9)" = true ] \
  || fail "detect: an eight-field adapter's hook_registration must be carried through"
make_adapter nine9 false true true false true yes light true EXTRA
rc=0
PATH="$BIN" "$BACKENDS" caps nine9 >/dev/null 2>"$err" || rc=$?
[ "$rc" = 1 ] || fail "caps of a nine-field adapter: exit $rc, expected 1 (fail-safe absent)"
grep -q "malformed advertise line" "$err" \
  || fail "caps: a nine-field advertise line must get the visible malformed diagnostic"
out=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" detect nine9 2>"$err") \
  || fail "detect(nine-field adapter) non-zero"
row_present "$out" nine9 \
  && fail "detect: a nine-field adapter must be absent from the candidate set"
grep -q "malformed advertise line" "$err" \
  || fail "detect: a nine-field advertise line must get the visible malformed diagnostic"
# Bad token values in the two appended fields are malformed too.
make_adapter badov false true true false true yes enormous true
rc=0
PATH="$BIN" "$BACKENDS" caps badov >/dev/null 2>"$err" || rc=$?
[ "$rc" = 1 ] || fail "caps of a bad-overhead adapter: exit $rc, expected 1"
grep -q "malformed advertise line" "$err" \
  || fail "caps: an invalid overhead class must get the visible malformed diagnostic"
make_adapter badhr false true true false true yes light maybe
rc=0
PATH="$BIN" "$BACKENDS" caps badhr >/dev/null 2>"$err" || rc=$?
[ "$rc" = 1 ] || fail "caps of a bad-hook_registration adapter: exit $rc, expected 1"
grep -q "malformed advertise line" "$err" \
  || fail "caps: an invalid hook_registration token must get the visible malformed diagnostic"
# The pre-extension token paths carry the diagnostic too (never a silent
# absence, REQ-A1.7): an invalid session_grade and an EMPTY advertise line.
make_adapter badsg2 false false false false true maybe
rc=0
PATH="$BIN" "$BACKENDS" caps badsg2 >/dev/null 2>"$err" || rc=$?
[ "$rc" = 1 ] || fail "caps of a bad-session_grade adapter: exit $rc, expected 1"
grep -q "malformed advertise line" "$err" \
  || fail "caps: an invalid session_grade token must get the visible malformed diagnostic"
cat >"$BIN/planwright-backend-emptyline" <<'EOF'
#!/bin/sh
[ "$1" = advertise ] || exit 2
printf '\n'
EOF
chmod +x "$BIN/planwright-backend-emptyline"
rc=0
PATH="$BIN" "$BACKENDS" caps emptyline >/dev/null 2>"$err" || rc=$?
[ "$rc" = 1 ] || fail "caps of an empty advertise line: exit $rc, expected 1"
grep -q "empty advertise line" "$err" \
  || fail "caps: an empty advertise line must get its own empty-line diagnostic"
echo "ok: the adapter grammar is 6-or-8 with fail-closed, diagnosed malformed arities"

# ---------------------------------------------------------------------------
# 33. Advertise-line input hygiene (REQ-A1.9): the line is length-bounded and
#     stripped of non-printable bytes BEFORE any use or echo — an overlong line
#     is malformed (diagnosed, never parsed), control bytes never reach stderr,
#     and stripping happens before grammar validation (strip-then-use).
# ---------------------------------------------------------------------------
cat >"$BIN/planwright-backend-longline" <<'EOF'
#!/bin/sh
[ "$1" = advertise ] || exit 2
awk 'BEGIN { s="false true true false true yes"; while (length(s) < 600) s = s " "; print s }'
EOF
chmod +x "$BIN/planwright-backend-longline"
rc=0
PATH="$BIN" "$BACKENDS" caps longline >/dev/null 2>"$err" || rc=$?
[ "$rc" = 1 ] || fail "caps of an overlong advertise line: exit $rc, expected 1"
grep -q "malformed advertise line" "$err" \
  || fail "caps: an overlong advertise line must get the visible malformed diagnostic"
# Pin the exact boundary (the bound is `-gt 512`): an exactly-512-byte line is
# accepted, a 513-byte line refused — so the bound cannot silently drift.
cat >"$BIN/planwright-backend-b512" <<'EOF'
#!/bin/sh
[ "$1" = advertise ] || exit 2
awk 'BEGIN { s="false true true false true yes"; while (length(s) < 512) s = s " "; print s }'
EOF
cat >"$BIN/planwright-backend-b513" <<'EOF'
#!/bin/sh
[ "$1" = advertise ] || exit 2
awk 'BEGIN { s="false true true false true yes"; while (length(s) < 513) s = s " "; print s }'
EOF
chmod +x "$BIN/planwright-backend-b512" "$BIN/planwright-backend-b513"
out=$(PATH="$BIN" "$BACKENDS" caps b512) \
  || fail "caps of an exactly-512-byte advertise line: expected acceptance"
[ "$out" = "false true true false true yes full-session+supervisor false" ] \
  || fail "caps b512: got '$out', expected the padded legacy line to parse"
rc=0
PATH="$BIN" "$BACKENDS" caps b513 >/dev/null 2>"$err" || rc=$?
[ "$rc" = 1 ] || fail "caps of a 513-byte advertise line: exit $rc, expected 1 (refused)"
grep -q "exceeds 512 bytes" "$err" \
  || fail "caps: the 513-byte refusal must carry the length-bound diagnostic"
# Strip-before-use: control bytes embedded in an otherwise-valid token are
# stripped BEFORE grammar validation, so the line parses (here as a legacy
# six-field line taking the fail-safe defaults).
cat >"$BIN/planwright-backend-escline" <<'EOF'
#!/bin/sh
[ "$1" = advertise ] || exit 2
printf 'fa\033\007lse true true false true yes\n'
EOF
chmod +x "$BIN/planwright-backend-escline"
out=$(PATH="$BIN" "$BACKENDS" caps escline 2>"$err") \
  || fail "caps of an esc-laden advertise line: expected acceptance after stripping"
[ "$out" = "false true true false true yes full-session+supervisor false" ] \
  || fail "caps escline: got '$out', expected the stripped line to parse as legacy six-field"
# Strip-before-echo: a malformed line whose tokens carry control + printable
# escape payloads is refused with a diagnostic that never reproduces the line's
# content — no raw ESC can reach the operator's terminal.
cat >"$BIN/planwright-backend-escbad" <<'EOF'
#!/bin/sh
[ "$1" = advertise ] || exit 2
printf 'ev\033]0;PWNED\007il true true false true yes\n'
EOF
chmod +x "$BIN/planwright-backend-escbad"
rc=0
PATH="$BIN" "$BACKENDS" caps escbad >/dev/null 2>"$err" || rc=$?
[ "$rc" = 1 ] || fail "caps of an escape-payload advertise line: exit $rc, expected 1"
grep -q "malformed advertise line" "$err" \
  || fail "caps: an escape-payload advertise line must get the visible malformed diagnostic"
if LC_ALL=C grep -q "$(printf '\033')" "$err"; then
  fail "caps: advertise-line control bytes must never reach stderr"
fi
echo "ok: advertise lines are length-bounded and stripped before use or echo"

# ---------------------------------------------------------------------------
# 34. The contract drift guard (REQ-A1.6, REQ-A1.8): the doc's backend table
#     and this script agree for every row and field — a new doc-table parser,
#     asserted three ways: the real doc passes; a seeded divergence fails; an
#     unparseable table fails rather than passing on an empty row set. The doc
#     must also record the pinned ladder ordering and the pinned overhead enum.
# ---------------------------------------------------------------------------
CONTRACT_DOC="$here/../doctrine/backend-capability-contract.md"
[ -f "$CONTRACT_DOC" ] || fail "doctrine/backend-capability-contract.md missing"

# Parse the doc's backend table into "name f1..f8" lines: a data row is a
# 9-column markdown row whose first cell is a backticked backend name. Cells
# are trimmed, backticks dropped, and the doc's n/a display form normalized to
# the script's `na` token.
parse_contract_rows() {
  # NF must be EXACTLY 11 (leading empty + 9 cells + trailing empty): a doc
  # table that grows a column the script lacks changes NF, drops the row here,
  # and fails the per-name coverage check below — the one-directional drift a
  # >= guard would silently pass.
  awk -F'|' '
    NF == 11 && $2 ~ /^[[:space:]]*`[a-z0-9-]+`[[:space:]]*$/ {
      out = ""
      for (i = 2; i <= 10; i++) {
        v = $i
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        gsub(/`/, "", v)
        if (v == "n/a") v = "na"
        out = (out == "" ? v : out " " v)
      }
      print out
    }' "$1"
}

# The guard: every doc row must have a caps answer equal to its eight fields,
# the row set must cover all six shipped backends, and the doc must pin the
# ladder ordering and overhead enum. Returns non-zero on any divergence.
check_drift() {
  cd_rows=$(parse_contract_rows "$1")
  cd_n=$(printf '%s\n' "$cd_rows" | grep -c . || true)
  [ "$cd_n" -ge 6 ] || return 1
  while IFS= read -r cd_row; do
    [ -n "$cd_row" ] || continue
    cd_name=${cd_row%% *}
    cd_fields=${cd_row#* }
    cd_caps=$("$BACKENDS" caps "$cd_name" 2>/dev/null) || return 1
    [ "$cd_caps" = "$cd_fields" ] || return 1
  done <<EOF
$cd_rows
EOF
  for b in tmux stream-json-persistent headless-oneshot subagent print in-session; do
    printf '%s\n' "$cd_rows" | grep -q "^$b " || return 1
  done
  # shellcheck disable=SC2016 # the backticks are literal markdown, not expansion
  grep -qF '`tmux` > `stream-json-persistent` > `headless-oneshot` > `subagent` > `print`/`in-session`' "$1" \
    || return 1
  # shellcheck disable=SC2016 # the backticks are literal markdown, not expansion
  grep -qF '`none` | `light` | `full-session` | `full-session+supervisor`' "$1" \
    || return 1
  return 0
}

check_drift "$CONTRACT_DOC" \
  || fail "drift guard: doctrine/backend-capability-contract.md and orchestrate-backends.sh disagree"
# Seeded divergence: flip one field in a copy — the guard must fail. The seed
# is anchored to the FULL subagent table row (not a bare `light` token, which
# also appears in the enum-pin lines: mangling those would make check_drift
# fail via the grep pins and vacate the row-comparison assertion this case
# exists to prove). Assert the seed actually changed the copy first, so a doc
# rewording can never turn this into a vacuous same-file comparison.
# shellcheck disable=SC2016 # the backticks are literal markdown, not expansion
sed 's/^| `subagent` | false | false | false | false | true | no | `light` | false |$/| `subagent` | false | false | false | false | true | no | `light` | true |/' \
  "$CONTRACT_DOC" >"$tmp/contract-diverged.md"
cmp -s "$CONTRACT_DOC" "$tmp/contract-diverged.md" \
  && fail "drift guard: the divergence seed no longer matches the doc (fixture rot)"
check_drift "$tmp/contract-diverged.md" \
  && fail "drift guard: a seeded doc/script divergence must fail the guard"
# Unparseable table: the guard must fail, never pass on an empty row set.
printf 'no table here\n' >"$tmp/contract-empty.md"
check_drift "$tmp/contract-empty.md" \
  && fail "drift guard: an unparseable contract table must fail, not pass on zero rows"

# The THIRD copy of the table — orchestrate-degrade.sh's caps_for — is not
# reachable through a caps accessor, so guard it textually: both scripts'
# caps_for case arms must be byte-identical (the lockstep-comment promise).
# rung classification alone would never catch a divergence in the two appended
# fields, which the classifier deliberately ignores.
extract_caps_table() {
  awk '/^caps_for\(\) \{/,/^\}/' "$1" | grep ') echo "'
}
bk_table=$(extract_caps_table "$here/../scripts/orchestrate-backends.sh")
dg_table=$(extract_caps_table "$here/../scripts/orchestrate-degrade.sh")
[ -n "$bk_table" ] || fail "drift guard: could not extract orchestrate-backends.sh caps_for"
[ "$(printf '%s\n' "$bk_table" | grep -c .)" -eq 6 ] \
  || fail "drift guard: orchestrate-backends.sh caps_for should have six rows"
[ "$bk_table" = "$dg_table" ] \
  || fail "drift guard: orchestrate-degrade.sh caps_for diverged from orchestrate-backends.sh"
echo "ok: the contract doc and the script agree under the drift guard"

echo "PASS: test-orchestrate-backends.sh"
