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
#      provides_attention_surface, supports_parallel, session_grade), richest
#     rung first. `in-session` and `print` are always present; `subagent` is
#     present by default (the harness-native runtime) and `tmux` is present iff
#     it resolves on PATH — both overridable via PLANWRIGHT_BACKEND_{SUBAGENT,
#     TMUX} so a host/test can force presence. A pluggable name is present iff a
#     `planwright-backend-<name>` adapter on PATH answers `advertise` with a
#     well-formed capability set; a malformed/absent adapter is reported absent.
#   - `select-unattended <configured>` makes the autonomous
#     (no-human-to-ask) pick: the configured backend when it is present AND
#     unattended-eligible (interactive=false AND session_grade!=deferred); else
#     it DEGRADES down the shipped autonomous chain (subagent → in-session, the
#     always-present terminal rung), NEVER selecting an interactive backend and
#     NEVER the manual `print` rung. A degrade prints a NOTE to stderr and still
#     exits 0 with the selection on stdout.
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
# cases, so clear them up front.
unset PLANWRIGHT_BACKEND_TMUX PLANWRIGHT_BACKEND_SUBAGENT

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

# A fake pluggable adapter that advertises the given capability set.
# usage: make_adapter <name> <interactive> <can_observe> <can_steer> <attn> <parallel> <session_grade>
make_adapter() {
  name="$1"
  cat >"$BIN/planwright-backend-$name" <<EOF
#!/bin/sh
[ "\$1" = advertise ] || exit 2
printf '%s %s %s %s %s %s\n' "$2" "$3" "$4" "$5" "$6" "$7"
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
# 7. select-unattended: configured is INTERACTIVE (tmux) → degrades to the
#    richest eligible autonomous rung (subagent), never tmux, with a NOTE.
# ---------------------------------------------------------------------------
sel=$(PLANWRIGHT_BACKEND_TMUX=1 "$BACKENDS" select-unattended tmux 2>"$err") \
  || fail "select-unattended tmux non-zero"
[ "$sel" = subagent ] || fail "select-unattended: interactive tmux should degrade to subagent, got '$sel'"
[ "$sel" != tmux ] || fail "select-unattended: MUST NOT silently pick the interactive backend"
grep -q NOTE "$err" || fail "select-unattended: a degrade must emit a NOTE on stderr"
echo "ok: select-unattended never silently picks an interactive backend (degrades with a note)"

# ---------------------------------------------------------------------------
# 8. select-unattended: a missing/rich configured backend degrades down the
#    ladder; with subagent also unavailable it reaches the in-session terminal
#    rung (always present), still never interactive.
# ---------------------------------------------------------------------------
sel=$(PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" select-unattended tmux 2>"$err") \
  || fail "select-unattended(missing tmux) non-zero"
[ "$sel" = subagent ] || fail "select-unattended: missing rich backend should degrade to subagent, got '$sel'"
sel=$(PLANWRIGHT_BACKEND_TMUX=0 PLANWRIGHT_BACKEND_SUBAGENT=0 \
  "$BACKENDS" select-unattended tmux 2>"$err") \
  || fail "select-unattended(no rich, no subagent) non-zero"
[ "$sel" = in-session ] \
  || fail "select-unattended: with no rich rung and no subagent it must reach in-session, got '$sel'"
echo "ok: select-unattended degrades down the ladder to the in-session terminal rung"

# ---------------------------------------------------------------------------
# 9. select-unattended: a configured PLUGGABLE that is present & eligible is
#    picked; an interactive pluggable is refused (degrades), never picked.
# ---------------------------------------------------------------------------
sel=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" select-unattended foo 2>"$err") \
  || fail "select-unattended(pluggable foo) non-zero"
[ "$sel" = foo ] || fail "select-unattended: eligible configured pluggable foo should be picked, got '$sel'"
make_adapter bar true true true false true yes
sel=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" select-unattended bar 2>"$err") \
  || fail "select-unattended(interactive pluggable) non-zero"
[ "$sel" = subagent ] || fail "select-unattended: interactive pluggable bar must degrade to subagent, got '$sel'"
[ "$sel" != bar ] || fail "select-unattended: MUST NOT pick an interactive pluggable"
echo "ok: select-unattended honors pluggable eligibility (picks eligible, degrades interactive)"

# ---------------------------------------------------------------------------
# 10. select-unattended: print (manual, session_grade=deferred) is never the
#     autonomous pick even when configured.
# ---------------------------------------------------------------------------
sel=$(PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" select-unattended print 2>"$err") \
  || fail "select-unattended print non-zero"
[ "$sel" != print ] || fail "select-unattended: the manual print rung must not be auto-picked"
[ "$sel" = subagent ] || fail "select-unattended: configured print should degrade to subagent, got '$sel'"
echo "ok: select-unattended never auto-picks the manual print rung"

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
# 12. never-interactive invariant across the whole matrix: for every configured
#     value, select-unattended's stdout is never an interactive backend.
# ---------------------------------------------------------------------------
for cfg in tmux subagent print in-session bogus; do
  for tm in 0 1; do
    sel=$(PLANWRIGHT_BACKEND_TMUX=$tm "$BACKENDS" select-unattended "$cfg" 2>/dev/null) \
      || fail "select-unattended($cfg,tmux=$tm) non-zero"
    [ "$sel" != tmux ] || fail "select-unattended($cfg,tmux=$tm): picked interactive tmux"
    [ "$sel" != print ] || fail "select-unattended($cfg,tmux=$tm): picked manual print"
    [ -n "$sel" ] || fail "select-unattended($cfg,tmux=$tm): empty selection"
  done
done
echo "ok: select-unattended never yields an interactive or manual backend for any input"

# ---------------------------------------------------------------------------
# 13. usage / fail-closed.
# ---------------------------------------------------------------------------
rc=0
"$BACKENDS" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "usage: no subcommand returned $rc, expected 2"
rc=0
"$BACKENDS" frobnicate >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "usage: unknown subcommand returned $rc, expected 2"
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
#     malformed) degrades down the ladder to subagent with a NOTE, the same
#     fail-safe path a missing shipped backend takes (case 8) — the pluggable
#     branch of that path was only covered indirectly before.
# ---------------------------------------------------------------------------
sel=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" select-unattended ghost 2>"$err") \
  || fail "select-unattended(absent pluggable) non-zero"
[ "$sel" = subagent ] \
  || fail "select-unattended: an absent configured pluggable should degrade to subagent, got '$sel'"
grep -q NOTE "$err" || fail "select-unattended: an absent-pluggable degrade must emit a NOTE"
echo "ok: select-unattended degrades an absent configured pluggable down the ladder"

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
#     (f_rest nonempty) is malformed → reported absent. The prior malformed test
#     only exercised bad token VALUES, never the too-many-tokens guard.
# ---------------------------------------------------------------------------
cat >"$BIN/planwright-backend-extra" <<'EOF'
#!/bin/sh
[ "$1" = advertise ] || exit 2
printf '%s\n' "false false false false true no EXTRA"
EOF
chmod +x "$BIN/planwright-backend-extra"
out=$(PATH="$BIN" PLANWRIGHT_BACKEND_TMUX=0 "$BACKENDS" detect extra 2>/dev/null) \
  || fail "detect(extra-token adapter) non-zero"
row_present "$out" extra \
  && fail "detect: an adapter set with a trailing extra token must be reported absent"
echo "ok: detect rejects an adapter set with too many tokens"

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

echo "PASS: test-orchestrate-backends.sh"
