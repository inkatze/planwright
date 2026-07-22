#!/bin/bash
# Tests for scripts/fleet-pane-detect.sh — the fallback pane-state detector
# (fleet-hardening Task 3; D-3, REQ-A1.3, REQ-E1.3).
#
# The detector is the reconcile BACKSTOP to the D-2 attention push: for dispatch
# backends that cannot register hooks — or where a registered hook has not
# pushed within a bounded reconcile interval (the registered-but-non-firing
# case) — it classifies a worker pane as idle / busy / indeterminate. It never
# runs where a fresh hook push exists (that is the D-2 push's job).
#
# It codifies, once, the discipline every tower otherwise re-derives (and each
# re-derivation regressed — the 2026-07-18 background-agent false-idle and the
# 2026-07-19 scrollback false-match): it reads ONLY the bounded footer region
# (not the full scrollback), requires a POSITIVE at-prompt anchor AND the
# ABSENCE of every busy marker to call idle, and DEBOUNCES across at least two
# consecutive frames before a classification flips.
#
# What is covered (the test-spec REQ-A1.3 fixtures + the REQ-E1.3 negative):
#   (a) busy words in scrollback ABOVE an idle footer classify idle — the
#       footer-only window means no scrollback false-match;
#   (b) a main-idle / background-busy pane (footer `Waiting for N background
#       agent`, no `esc to interrupt`) classifies busy, not idle;
#   (c) a single-frame flap is suppressed by the two-frame debounce;
#   (d) the detector runs only as the reconcile backstop — where the backend
#       registers no hook, OR where a registered hook has not pushed within the
#       bounded reconcile interval — and DEFERS where a fresh hook push exists;
#   (e) a pane with no positive at-prompt anchor (a blank / loading screen, no
#       busy marker either) classifies NOT idle (indeterminate) — the direct
#       test of the positive-anchor requirement, so a starting-up worker is
#       never misread as idle-at-fork;
#   plus a negative assertion that the detector's decision path invokes no
#   model / API (REQ-E1.3), and the usage-error floor.
#
# execution-backends D-11 / REQ-F1.1 additions: with a `--cwd` join key the
# detector consults the agents-json idle oracle (through the liveness helper)
# and DEFERS to an oracle answer (`defer-to-oracle <verdict>`, one probe
# instant serving the gate and the consumer) — a false-idle pane never
# reaches the pane heuristics while the oracle is available; a defer frame
# resets the two-frame debounce state so nothing confirms instantly across a
# defer era; only an unavailable oracle or an absent worker lets the pane
# heuristics run (pane-scrape demoted to fallback-only); the gate order is
# push, then oracle, then heuristics; defer-to-push resets the debounce state
# the same way; and without `--cwd` the oracle is never consulted
# (backward-compatible). An empty, relative, hostile, or over-length `--cwd`
# warns and falls back to the heuristics (oracle coverage lost, never the
# detector).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-pane-detect.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FPD="$here/../scripts/fleet-pane-detect.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FPD" ] || fail "scripts/fleet-pane-detect.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# ---------------------------------------------------------------------------
# Fixtures. The footer strings mirror Claude Code's real TUI: an idle footer
# carries a positive at-prompt anchor (`? for shortcuts`, `auto mode on`); a
# busy main agent carries `esc to interrupt`; background-agent busy carries
# `Waiting for N background agent … to manage`. Scrollback above is arbitrary.
# ---------------------------------------------------------------------------

# An idle pane: the scrollback is quiet, the footer carries the positive anchor
# and NO busy marker.
idle_pane="$tmp/idle.txt"
cat >"$idle_pane" <<'EOF'
● I have finished the task and opened the draft PR.
  The tests pass and CI is green.

╭──────────────────────────────────────────────────╮
│ >                                                  │
╰──────────────────────────────────────────────────╯
  ⏵⏵ auto mode on · ? for shortcuts
EOF

# A pane whose SCROLLBACK contains the busy phrase, but whose FOOTER is idle.
# A whole-pane matcher false-matches here (the 2026-07-19 mechanism); a
# footer-only matcher must classify idle.
scrollback_busy_pane="$tmp/scrollback-busy.txt"
cat >"$scrollback_busy_pane" <<'EOF'
● Running the suite now…
  ✳ Cogitating… (esc to interrupt)
  esc to interrupt appeared while it was working above.
  A background agent was Waiting for something to manage earlier.
● Done. All green.
  Here is the summary of what changed and why it matters for the
  reviewer, spread across a few lines of ordinary transcript text
  so the footer window cannot possibly reach back this far.

╭──────────────────────────────────────────────────╮
│ >                                                  │
╰──────────────────────────────────────────────────╯
  ⏵⏵ auto mode on · ? for shortcuts
EOF

# A main-idle / background-busy pane: the main agent is at prompt, but a
# background agent is still running — the footer shows the background-agent
# busy marker and NO `esc to interrupt`. This is the 2026-07-18 false-idle:
# an absence-of-`esc to interrupt` check with no positive discipline reads it
# idle. The detector must classify busy.
background_busy_pane="$tmp/background-busy.txt"
cat >"$background_busy_pane" <<'EOF'
● Kicked off two background agents to explore the codebase.

╭──────────────────────────────────────────────────╮
│ >                                                  │
╰──────────────────────────────────────────────────╯
  ⏵ Waiting for 2 background agents… (ctrl+b to manage)
EOF

# A busy pane: the main agent is mid-turn, footer carries `esc to interrupt`.
busy_pane="$tmp/busy.txt"
cat >"$busy_pane" <<'EOF'
● Working on the implementation…

  ✳ Simmering… (12s · ↑ 1.2k tokens · esc to interrupt)
EOF

# A busy pane where the positive anchor is ALSO present — the most realistic
# main-agent-busy layout: the `auto mode on` mode line persists on screen while
# the agent runs and shows `esc to interrupt` above it. Busy must take
# precedence over the anchor (idle requires the ABSENCE of every busy marker).
busy_with_anchor_pane="$tmp/busy-with-anchor.txt"
cat >"$busy_with_anchor_pane" <<'EOF'
● Working on the implementation…
  ✳ Simmering… (12s · esc to interrupt)
╭──────────────────────────────────────────────────╮
│ >                                                  │
╰──────────────────────────────────────────────────╯
  ⏵⏵ auto mode on · ? for shortcuts
EOF

# A spinner-only busy pane: a spinner gerund in the footer but NO `esc to
# interrupt` clause (it wrapped / scrolled off) and NO anchor — the
# belt-and-suspenders spinner-word path the header documents.
spinner_only_pane="$tmp/spinner-only.txt"
cat >"$spinner_only_pane" <<'EOF'
● Kicked off the work.

  ✳ Pondering…
EOF

# A no-anchor pane: a blank / loading screen — no busy marker AND no positive
# at-prompt anchor. A starting-up worker must never be misread as idle-at-fork.
no_anchor_pane="$tmp/no-anchor.txt"
cat >"$no_anchor_pane" <<'EOF'


   Loading…


EOF

# classify_confirmed <label> <pane> <expected> [extra args…] — drive the
# detector across TWO identical frames (the debounce floor) with a private
# per-label state dir, and assert the second (confirmed) frame prints
# <expected>. Backend defaults to a hook-less one so the backstop gate always
# lets the detector run; extra args override.
classify_confirmed() {
  cc_label="$1"
  cc_pane="$2"
  cc_expected="$3"
  shift 3
  cc_state="$tmp/state-$cc_label"
  mkdir -p "$cc_state"
  local first second
  first=$("$FPD" classify --pane "$cc_pane" --backend subagent \
    --worker w-"$cc_label" --state-dir "$cc_state" "$@") \
    || fail "$cc_label: detector exited non-zero on frame 1"
  [ "$first" = pending ] \
    || fail "$cc_label: frame 1 should be 'pending' (debounce floor), got '$first'"
  second=$("$FPD" classify --pane "$cc_pane" --backend subagent \
    --worker w-"$cc_label" --state-dir "$cc_state" "$@") \
    || fail "$cc_label: detector exited non-zero on frame 2"
  [ "$second" = "$cc_expected" ] \
    || fail "$cc_label: confirmed frame should be '$cc_expected', got '$second'"
  echo "ok: $cc_label -> $cc_expected"
}

# --- (a) scrollback busy above an idle footer classifies idle -------------
classify_confirmed scrollback-idle "$scrollback_busy_pane" idle
# and the plain idle pane too (the positive-anchor happy path)
classify_confirmed plain-idle "$idle_pane" idle

# --- (b) main-idle / background-busy classifies busy ----------------------
classify_confirmed background-busy "$background_busy_pane" busy
# and the plain main-agent busy pane
classify_confirmed main-busy "$busy_pane" busy
# busy-precedence: a footer carrying BOTH a busy marker AND a positive anchor
# (the realistic persistent-mode-line layout) classifies busy, never idle
classify_confirmed busy-with-anchor "$busy_with_anchor_pane" busy
# the spinner-word-only path (no `esc to interrupt`, no anchor) classifies busy
classify_confirmed spinner-only "$spinner_only_pane" busy

# --- (e) no positive at-prompt anchor classifies NOT idle -----------------
classify_confirmed no-anchor "$no_anchor_pane" indeterminate
# an explicit, separate guard that it is not idle
na_state="$tmp/state-na2"
mkdir -p "$na_state"
"$FPD" classify --pane "$no_anchor_pane" --backend subagent --worker w-na2 \
  --state-dir "$na_state" >/dev/null
na=$("$FPD" classify --pane "$no_anchor_pane" --backend subagent --worker w-na2 \
  --state-dir "$na_state")
[ "$na" != idle ] || fail "no-anchor pane must never classify idle (positive-anchor requirement)"
echo "ok: no-anchor never idle"

# --- FLEET_PANE_PROMPT_ANCHORS override, case-insensitively ----------------
# A bespoke TUI's at-prompt anchor supplied via the override env var must match
# regardless of case (the override is folded to lowercase, as the default
# anchors already are). A pane whose only anchor is a MIXED-CASE custom token
# classifies idle; without the override it is indeterminate.
custom_anchor_pane="$tmp/custom-anchor.txt"
cat >"$custom_anchor_pane" <<'EOF'
● Idle at the bespoke prompt.
   ›  Ready To Go
EOF
ov_state="$tmp/state-override"
mkdir -p "$ov_state"
FLEET_PANE_PROMPT_ANCHORS="Ready To Go" \
  "$FPD" classify --pane "$custom_anchor_pane" --backend subagent --worker w-ov \
  --state-dir "$ov_state" >/dev/null
ov=$(FLEET_PANE_PROMPT_ANCHORS="Ready To Go" \
  "$FPD" classify --pane "$custom_anchor_pane" --backend subagent --worker w-ov \
  --state-dir "$ov_state")
[ "$ov" = idle ] \
  || fail "mixed-case FLEET_PANE_PROMPT_ANCHORS override must match (case-folded), got '$ov'"
# and without the override the same pane is NOT idle (the custom token is not a
# default anchor) — proves the override, not a default, drove the match above
ov2_state="$tmp/state-override-off"
mkdir -p "$ov2_state"
"$FPD" classify --pane "$custom_anchor_pane" --backend subagent --worker w-ov2 \
  --state-dir "$ov2_state" >/dev/null
ov2=$("$FPD" classify --pane "$custom_anchor_pane" --backend subagent --worker w-ov2 \
  --state-dir "$ov2_state")
[ "$ov2" != idle ] \
  || fail "without the override the bespoke token must not classify idle, got '$ov2'"
echo "ok: FLEET_PANE_PROMPT_ANCHORS override matches case-insensitively"

# --- --footer-lines bounds the window height ------------------------------
# A pane with a busy marker 4 lines up and an idle footer in the last 2 lines:
# a narrow --footer-lines=2 window sees only the idle footer (idle); the default
# window reaches the busy marker above (busy). Same pane, different window ->
# the flag bounds the region.
footer_lines_pane="$tmp/footer-lines.txt"
cat >"$footer_lines_pane" <<'EOF'
● transcript line
  ✳ Simmering… (esc to interrupt)
  more transcript text
╭────────────────────╮
│ >                   │
  ⏵⏵ auto mode on · ? for shortcuts
EOF
classify_confirmed footer-narrow "$footer_lines_pane" idle --footer-lines 2
classify_confirmed footer-wide "$footer_lines_pane" busy

# --- --scope keys the debounce state independently ------------------------
# The same worker handle under two different scopes keeps separate two-frame
# histories (the state key folds scope + worker), so one scope's frames never
# advance the other's debounce.
sc_state="$tmp/state-scope"
mkdir -p "$sc_state"
sa1=$("$FPD" classify --pane "$idle_pane" --backend subagent --worker w-sc \
  --scope alpha --state-dir "$sc_state")
sb1=$("$FPD" classify --pane "$idle_pane" --backend subagent --worker w-sc \
  --scope beta --state-dir "$sc_state")
{ [ "$sa1" = pending ] && [ "$sb1" = pending ]; } \
  || fail "scope: the first frame under each scope must be pending (independent state), got '$sa1'/'$sb1'"
sa2=$("$FPD" classify --pane "$idle_pane" --backend subagent --worker w-sc \
  --scope alpha --state-dir "$sc_state")
[ "$sa2" = idle ] \
  || fail "scope: alpha's second frame should confirm idle independently, got '$sa2'"
sb2=$("$FPD" classify --pane "$idle_pane" --backend subagent --worker w-sc \
  --scope beta --state-dir "$sc_state")
[ "$sb2" = idle ] \
  || fail "scope: beta's second frame should confirm idle independently, got '$sb2'"
echo "ok: --scope keys the debounce state independently"

# --- (c) single-frame flap suppressed by the two-frame debounce -----------
flap_state="$tmp/state-flap"
mkdir -p "$flap_state"
# establish confirmed idle across two frames
"$FPD" classify --pane "$idle_pane" --backend subagent --worker w-flap \
  --state-dir "$flap_state" >/dev/null
conf=$("$FPD" classify --pane "$idle_pane" --backend subagent --worker w-flap \
  --state-dir "$flap_state")
[ "$conf" = idle ] || fail "flap: expected confirmed idle before the flap, got '$conf'"
# a SINGLE busy frame must not flip the confirmed state
flap=$("$FPD" classify --pane "$busy_pane" --backend subagent --worker w-flap \
  --state-dir "$flap_state")
[ "$flap" = idle ] \
  || fail "flap: a single busy frame must be suppressed (stay idle), got '$flap'"
# a SECOND consecutive busy frame is a real change and flips
flip=$("$FPD" classify --pane "$busy_pane" --backend subagent --worker w-flap \
  --state-dir "$flap_state")
[ "$flip" = busy ] \
  || fail "flap: two consecutive busy frames should flip to busy, got '$flip'"
echo "ok: single-frame flap suppressed, two-frame change flips"

# --- (d) backstop gating: runs only where no fresh push exists -------------
# A hook-less backend (subagent) always runs the detector — asserted implicitly
# above. Now the hook-capable (tmux) backend, gated on the attention store.
# write_row <root> <worker> <state> <heartbeat-epoch> — a store row in the real
# 8-field layout: worker · scope · state · heartbeat · priority · question ·
# default · options (matches fleet-attention.sh). Only worker (field 1) and
# heartbeat (field 4) are load-bearing for the freshness gate.
write_row() {
  wr_root="$1"
  mkdir -p "$wr_root/attention"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$2" "-" "$3" "$4" "high" "question?" "default" "a|b" \
    >"$wr_root/attention/state"
}

now=1000000

# 6b. push-capable backend + FRESH push (heartbeat == now) -> defer-to-push
root_fresh="$tmp/root-fresh"
write_row "$root_fresh" w-fresh awaiting-input "$now"
gate_state="$tmp/state-gate-fresh"
mkdir -p "$gate_state"
res=$("$FPD" classify --pane "$idle_pane" --backend tmux --worker w-fresh \
  --root "$root_fresh" --now "$now" --reconcile-ttl 300 --state-dir "$gate_state") \
  || fail "gate-fresh: detector exited non-zero"
[ "$res" = defer-to-push ] \
  || fail "gate-fresh: a fresh push must defer-to-push, got '$res'"
echo "ok: hook-capable backend defers to a fresh push"

# 6c. push-capable backend + STALE push (heartbeat old) -> detector runs
root_stale="$tmp/root-stale"
write_row "$root_stale" w-stale awaiting-input "$((now - 5000))"
gate_state2="$tmp/state-gate-stale"
mkdir -p "$gate_state2"
"$FPD" classify --pane "$idle_pane" --backend tmux --worker w-stale \
  --root "$root_stale" --now "$now" --reconcile-ttl 300 --state-dir "$gate_state2" >/dev/null
res2=$("$FPD" classify --pane "$idle_pane" --backend tmux --worker w-stale \
  --root "$root_stale" --now "$now" --reconcile-ttl 300 --state-dir "$gate_state2")
[ "$res2" = idle ] \
  || fail "gate-stale: a stale push (registered-but-non-firing) must run the detector -> idle, got '$res2'"
echo "ok: hook-capable backend with a stale push runs the backstop"

# 6d. push-capable backend + NO store row -> detector runs (no push exists)
root_empty="$tmp/root-empty"
mkdir -p "$root_empty/attention"
: >"$root_empty/attention/state"
gate_state3="$tmp/state-gate-empty"
mkdir -p "$gate_state3"
"$FPD" classify --pane "$idle_pane" --backend tmux --worker w-none \
  --root "$root_empty" --now "$now" --reconcile-ttl 300 --state-dir "$gate_state3" >/dev/null
res3=$("$FPD" classify --pane "$idle_pane" --backend tmux --worker w-none \
  --root "$root_empty" --now "$now" --reconcile-ttl 300 --state-dir "$gate_state3")
[ "$res3" = idle ] \
  || fail "gate-empty: no store row means no push -> detector runs -> idle, got '$res3'"
echo "ok: hook-capable backend with no store row runs the backstop"

# 6e. push-capable backend + CORRUPT (non-numeric) heartbeat -> no fresh push
# (the freshness guard rejects a non-numeric / leading-zero-octal timestamp) ->
# detector runs as the backstop rather than deferring to an unparseable push.
root_corrupt="$tmp/root-corrupt"
write_row "$root_corrupt" w-corrupt awaiting-input "not-a-number"
gate_state4="$tmp/state-gate-corrupt"
mkdir -p "$gate_state4"
"$FPD" classify --pane "$idle_pane" --backend tmux --worker w-corrupt \
  --root "$root_corrupt" --now "$now" --reconcile-ttl 300 --state-dir "$gate_state4" >/dev/null
res4=$("$FPD" classify --pane "$idle_pane" --backend tmux --worker w-corrupt \
  --root "$root_corrupt" --now "$now" --reconcile-ttl 300 --state-dir "$gate_state4")
[ "$res4" = idle ] \
  || fail "gate-corrupt: a non-numeric heartbeat is not a fresh push -> detector runs -> idle, got '$res4'"
echo "ok: hook-capable backend with a corrupt heartbeat runs the backstop"

# 6f. push-capable backend + FUTURE heartbeat (negative age) -> NOT fresh ->
# detector runs. A heartbeat later than --now (clock skew or a corrupt future
# timestamp) must not be read as a fresh push: treating a negative age as fresh
# would defer indefinitely until real time catches up (silent blindness). It
# must fail toward running the backstop.
root_future="$tmp/root-future"
write_row "$root_future" w-future awaiting-input "$((now + 100000))"
gate_state5="$tmp/state-gate-future"
mkdir -p "$gate_state5"
"$FPD" classify --pane "$idle_pane" --backend tmux --worker w-future \
  --root "$root_future" --now "$now" --reconcile-ttl 300 --state-dir "$gate_state5" >/dev/null
res5=$("$FPD" classify --pane "$idle_pane" --backend tmux --worker w-future \
  --root "$root_future" --now "$now" --reconcile-ttl 300 --state-dir "$gate_state5")
[ "$res5" = idle ] \
  || fail "gate-future: a future (negative-age) heartbeat must not defer; detector runs -> idle, got '$res5'"
echo "ok: hook-capable backend with a future heartbeat runs the backstop (no indefinite defer)"

# --- state-file shape guard: a tampered state file never leaks a verdict ------
# A corrupted state file (arbitrary strings on the two lines) must never reach
# stdout as a classification; the reader coerces unknown values to empty, so the
# frame degrades to `pending` (no prior state), never emits the garbage.
tamper_state="$tmp/state-tamper"
mkdir -p "$tamper_state"
"$FPD" classify --pane "$idle_pane" --backend subagent --worker w-tamper \
  --state-dir "$tamper_state" >/dev/null
tamper_file=$(find "$tamper_state" -type f ! -name '.tmp.*' | head -n1)
[ -n "$tamper_file" ] || fail "tamper: could not locate the debounce state file"
printf '%s\n%s\n' 'rm -rf /' 'arbitrary garbage' >"$tamper_file"
tampered=$("$FPD" classify --pane "$idle_pane" --backend subagent --worker w-tamper \
  --state-dir "$tamper_state")
case $tampered in
  idle | busy | indeterminate | pending) ;;
  *) fail "tamper: a corrupt state file leaked a non-verdict token '$tampered'" ;;
esac
echo "ok: corrupt state file never leaks an arbitrary verdict ($tampered)"

# --- REQ-E1.3: no model / API in the detector's decision path -------------
# Whole-word match via a pure-POSIX ERE that spells out the word boundaries with
# `[^[:alnum:]_]` — NOT `\b…\b` (a GNU extension, a literal backspace under some
# ERE engines) and NOT `grep -w` (the -w flag is not in POSIX grep), either of
# which could let the assertion pass vacuously on a non-conforming engine. Prove
# the pattern is LIVE with a positive control before trusting a no-match on the
# script: a planted forbidden token must be caught, or the assertion is
# meaningless.
model_pattern='(^|[^[:alnum:]_])(curl|wget|claude|anthropic|openai)([^[:alnum:]_]|$)'
printf 'x claude x\n' | grep -Eq "$model_pattern" \
  || fail "REQ-E1.3 assertion is vacuous: the grep pattern fails to match a planted forbidden token"
if grep -Eq "$model_pattern" "$FPD"; then
  fail "detector references a network/model call in its decision path (REQ-E1.3)"
fi
echo "ok: no model/API call in the detector's decision path (REQ-E1.3)"

# --- usage-error floor ----------------------------------------------------
uc=0
"$FPD" classify --backend subagent --worker w >/dev/null 2>&1 || uc=$?
[ "$uc" -eq 2 ] || fail "missing --pane must be a usage error (exit 2), got '$uc'"
uc=0
"$FPD" classify --pane "$idle_pane" --worker w >/dev/null 2>&1 || uc=$?
[ "$uc" -eq 2 ] || fail "missing --backend must be a usage error (exit 2), got '$uc'"
uc=0
"$FPD" bogus >/dev/null 2>&1 || uc=$?
[ "$uc" -eq 2 ] || fail "unknown subcommand must be a usage error (exit 2), got '$uc'"
echo "ok: usage-error floor"

# --- field-grammar validation of --worker / --scope -----------------------
# A handle carrying a tab, newline, or control char would silently break the
# tab-delimited store lookup and the state-file key; it must be refused (exit 2),
# matching fleet-liveness.sh's valid_field discipline. A long-but-legal handle
# over the 128-char bound is refused too.
vg_state="$tmp/state-vg"
mkdir -p "$vg_state"
uc=0
"$FPD" classify --pane "$idle_pane" --backend subagent --worker "$(printf 'bad\tworker')" \
  --state-dir "$vg_state" >/dev/null 2>&1 || uc=$?
[ "$uc" -eq 2 ] || fail "a worker handle with a tab must be refused (exit 2), got '$uc'"
uc=0
"$FPD" classify --pane "$idle_pane" --backend subagent --worker w-ok \
  --scope "$(printf 'bad\nscope')" --state-dir "$vg_state" >/dev/null 2>&1 || uc=$?
[ "$uc" -eq 2 ] || fail "a scope with a newline must be refused (exit 2), got '$uc'"
uc=0
long_handle=$(printf 'a%.0s' $(seq 1 200))
"$FPD" classify --pane "$idle_pane" --backend subagent --worker "$long_handle" \
  --state-dir "$vg_state" >/dev/null 2>&1 || uc=$?
[ "$uc" -eq 2 ] || fail "an over-128-char worker handle must be refused (exit 2), got '$uc'"
echo "ok: malformed --worker / --scope refused (field-grammar validation)"

# --- execution-backends D-11 / REQ-F1.1: the oracle demotes pane-scrape ------
# The agents-json idle oracle, shimmed. The detector reaches it through the
# liveness helper, which reads the binary from PLANWRIGHT_ORACLE_CLAUDE.
o_dir="$tmp/oracle"
mkdir -p "$o_dir"
o_fix="$o_dir/fixture.json"
o_shim="$o_dir/agents-shim"
{
  echo '#!/bin/sh'
  echo "touch \"$o_dir/invoked\""
  # shellcheck disable=SC2016 # $1/$2 are literal shim-script source, expanded at shim runtime, not here
  echo '[ "$1" = agents ] && [ "$2" = --json ] || exit 9'
  echo "cat \"$o_fix\""
} >"$o_shim"
chmod +x "$o_shim"
printf '[]\n' >"$o_fix"
"$o_shim" agents --json >/dev/null 2>&1 || true # pre-warm (first-exec latency)
rm -f "$o_dir/invoked"

# The false-idle case the oracle corrects: the pane's footer carries the
# at-prompt anchor (pane heuristics would confirm idle) while the worker's
# session is actually mid-turn — the oracle answers busy, and the detector
# must defer-to-oracle on EVERY frame, never emitting the false idle.
cat >"$o_fix" <<'JSON'
[ {"pid": 300, "cwd": "/wt/fi", "kind": "interactive", "sessionId": "gg-6", "name": "fi", "status": "busy"} ]
JSON
od_state="$tmp/state-oracle-defer"
mkdir -p "$od_state"
res=$(PLANWRIGHT_ORACLE_CLAUDE="$o_shim" "$FPD" classify --pane "$idle_pane" \
  --backend subagent --worker w-od --state-dir "$od_state" --cwd /wt/fi) \
  || fail "oracle-defer: detector exited non-zero on frame 1"
[ "$res" = "defer-to-oracle busy" ] \
  || fail "oracle-defer: frame 1 should defer carrying the verdict (false idle corrected), got '$res'"
res=$(PLANWRIGHT_ORACLE_CLAUDE="$o_shim" "$FPD" classify --pane "$idle_pane" \
  --backend subagent --worker w-od --state-dir "$od_state" --cwd /wt/fi) \
  || fail "oracle-defer: detector exited non-zero on frame 2"
[ "$res" = "defer-to-oracle busy" ] \
  || fail "oracle-defer: frame 2 should still defer with the verdict (gate precedes debounce), got '$res'"
echo "ok: an available oracle defers the detector with its verdict — the pane false-idle never surfaces"

# Deferring resets the debounce state: heuristic frames recorded BEFORE a
# defer era must not instantly confirm once the oracle drops away — the first
# post-defer fallback frame restarts the two-frame floor (pending).
o_fail_early="$o_dir/fail-early"
printf '#!/bin/sh\nexit 1\n' >"$o_fail_early"
chmod +x "$o_fail_early"
"$o_fail_early" agents --json >/dev/null 2>&1 || true # pre-warm
rs_state="$tmp/state-oracle-reset"
mkdir -p "$rs_state"
r0=$(PLANWRIGHT_ORACLE_CLAUDE="$o_fail_early" "$FPD" classify --pane "$idle_pane" \
  --backend subagent --worker w-rs --state-dir "$rs_state" --cwd /wt/fi) \
  || fail "oracle-reset: frame 1 (fallback) exited non-zero"
[ "$r0" = pending ] || fail "oracle-reset: frame 1 should be pending, got '$r0'"
r1=$(PLANWRIGHT_ORACLE_CLAUDE="$o_shim" "$FPD" classify --pane "$idle_pane" \
  --backend subagent --worker w-rs --state-dir "$rs_state" --cwd /wt/fi) \
  || fail "oracle-reset: defer frame exited non-zero"
[ "$r1" = "defer-to-oracle busy" ] || fail "oracle-reset: expected a defer frame, got '$r1'"
r2=$(PLANWRIGHT_ORACLE_CLAUDE="$o_fail_early" "$FPD" classify --pane "$idle_pane" \
  --backend subagent --worker w-rs --state-dir "$rs_state" --cwd /wt/fi) \
  || fail "oracle-reset: post-defer fallback frame exited non-zero"
[ "$r2" = pending ] \
  || fail "oracle-reset: the first post-defer fallback frame must restart the floor (pending), got '$r2'"
# defer-to-push resets the state the same way: two confirmed frames, then a
# fresh-push defer era, then a stale push — the first fallback frame must be
# pending, never an instant re-confirmation of the pre-defer pair
pr_root="$tmp/root-push-reset"
mkdir -p "$pr_root/attention"
: >"$pr_root/attention/state"
pr_state="$tmp/state-push-reset"
mkdir -p "$pr_state"
"$FPD" classify --pane "$idle_pane" --backend tmux --worker w-pr \
  --root "$pr_root" --now "$now" --reconcile-ttl 300 --state-dir "$pr_state" >/dev/null \
  || fail "push-reset: frame 1 exited non-zero"
pc=$("$FPD" classify --pane "$idle_pane" --backend tmux --worker w-pr \
  --root "$pr_root" --now "$now" --reconcile-ttl 300 --state-dir "$pr_state") \
  || fail "push-reset: frame 2 exited non-zero"
[ "$pc" = idle ] || fail "push-reset: expected confirmed idle before the defer era, got '$pc'"
write_row "$pr_root" w-pr awaiting-input "$now"
pd=$("$FPD" classify --pane "$idle_pane" --backend tmux --worker w-pr \
  --root "$pr_root" --now "$now" --reconcile-ttl 300 --state-dir "$pr_state") \
  || fail "push-reset: defer frame exited non-zero"
[ "$pd" = defer-to-push ] || fail "push-reset: expected defer-to-push, got '$pd'"
write_row "$pr_root" w-pr awaiting-input "$((now - 5000))"
pf=$("$FPD" classify --pane "$idle_pane" --backend tmux --worker w-pr \
  --root "$pr_root" --now "$now" --reconcile-ttl 300 --state-dir "$pr_state") \
  || fail "push-reset: post-defer fallback frame exited non-zero"
[ "$pf" = pending ] \
  || fail "push-reset: the first post-defer fallback frame must restart the floor (pending), got '$pf'"
echo "ok: a defer frame (oracle or push) resets the debounce state — no instant confirmation across a defer era"

# A fresh hook push still wins the gate order (defer-to-push precedes the
# oracle gate: the deterministic push is the primary, the oracle backs it up).
op_root="$tmp/root-oracle-push"
write_row "$op_root" w-op awaiting-input "$now"
op_state="$tmp/state-oracle-push"
mkdir -p "$op_state"
res=$(PLANWRIGHT_ORACLE_CLAUDE="$o_shim" "$FPD" classify --pane "$idle_pane" \
  --backend tmux --worker w-op --root "$op_root" --now "$now" --reconcile-ttl 300 \
  --state-dir "$op_state" --cwd /wt/fi) \
  || fail "oracle-push-order: detector exited non-zero"
[ "$res" = defer-to-push ] \
  || fail "oracle-push-order: a fresh push should defer-to-push ahead of the oracle, got '$res'"
# and a STALE push falls through the push gate INTO the oracle gate (the full
# ordering: push, then oracle, then heuristics)
sp_root="$tmp/root-oracle-stale"
write_row "$sp_root" w-sp awaiting-input "$((now - 5000))"
sp_state="$tmp/state-oracle-stale"
mkdir -p "$sp_state"
res=$(PLANWRIGHT_ORACLE_CLAUDE="$o_shim" "$FPD" classify --pane "$idle_pane" \
  --backend tmux --worker w-sp --root "$sp_root" --now "$now" --reconcile-ttl 300 \
  --state-dir "$sp_state" --cwd /wt/fi) \
  || fail "oracle-stale-push: detector exited non-zero"
[ "$res" = "defer-to-oracle busy" ] \
  || fail "oracle-stale-push: a stale push should fall through to the oracle gate, got '$res'"
echo "ok: a fresh hook push outranks the oracle gate; a stale push falls through to it"

# An UNAVAILABLE oracle (probe fails) lets the pane heuristics run — the
# fallback engages, never a dead stop.
o_fail="$o_dir/fail-shim"
printf '#!/bin/sh\nexit 1\n' >"$o_fail"
chmod +x "$o_fail"
"$o_fail" agents --json >/dev/null 2>&1 || true # pre-warm
ou_state="$tmp/state-oracle-unavail"
mkdir -p "$ou_state"
r1=$(PLANWRIGHT_ORACLE_CLAUDE="$o_fail" "$FPD" classify --pane "$idle_pane" \
  --backend subagent --worker w-ou --state-dir "$ou_state" --cwd /wt/fi) \
  || fail "oracle-unavailable: detector exited non-zero on frame 1"
[ "$r1" = pending ] \
  || fail "oracle-unavailable: frame 1 should run the heuristics (pending), got '$r1'"
r2=$(PLANWRIGHT_ORACLE_CLAUDE="$o_fail" "$FPD" classify --pane "$idle_pane" \
  --backend subagent --worker w-ou --state-dir "$ou_state" --cwd /wt/fi) \
  || fail "oracle-unavailable: detector exited non-zero on frame 2"
[ "$r2" = idle ] \
  || fail "oracle-unavailable: frame 2 should confirm via the heuristics (idle), got '$r2'"
echo "ok: an unavailable oracle falls back to the pane heuristics"

# An ABSENT worker (valid oracle output, no matching row) is no evidence — the
# heuristics run.
printf '[]\n' >"$o_fix"
oa_state="$tmp/state-oracle-absent"
mkdir -p "$oa_state"
PLANWRIGHT_ORACLE_CLAUDE="$o_shim" "$FPD" classify --pane "$idle_pane" \
  --backend subagent --worker w-oa --state-dir "$oa_state" --cwd /wt/fi >/dev/null \
  || fail "oracle-absent: detector exited non-zero on frame 1"
ra=$(PLANWRIGHT_ORACLE_CLAUDE="$o_shim" "$FPD" classify --pane "$idle_pane" \
  --backend subagent --worker w-oa --state-dir "$oa_state" --cwd /wt/fi) \
  || fail "oracle-absent: detector exited non-zero on frame 2"
[ "$ra" = idle ] \
  || fail "oracle-absent: an absent worker should fall through to the heuristics (idle), got '$ra'"
echo "ok: an absent worker is no evidence — the heuristics run"

# Without --cwd the oracle is never consulted (backward-compatible: the shim's
# invocation marker must stay absent).
rm -f "$o_dir/invoked"
nc_state="$tmp/state-no-cwd"
mkdir -p "$nc_state"
PLANWRIGHT_ORACLE_CLAUDE="$o_shim" "$FPD" classify --pane "$idle_pane" \
  --backend subagent --worker w-nc --state-dir "$nc_state" >/dev/null \
  || fail "no-cwd: detector exited non-zero"
[ ! -e "$o_dir/invoked" ] \
  || fail "no-cwd: the oracle was consulted without a --cwd join key"
echo "ok: without --cwd the oracle is never consulted"

# An unusable --cwd (relative, control-bearing, empty, over-length) costs
# ORACLE COVERAGE only: a loud stderr warning, then the pane heuristics run —
# never a hard exit (which would turn a merely-unjoinable path into total
# classification loss), and never a silent skip (the warning is asserted).
# mc_fallback <label> <cwd-value>
mc_fallback() {
  mcf_label="$1"
  mcf_cwd="$2"
  mcf_state="$tmp/state-$mcf_label"
  mkdir -p "$mcf_state"
  mcf_out=$("$FPD" classify --pane "$idle_pane" --backend subagent \
    --worker "w-$mcf_label" --state-dir "$mcf_state" --cwd "$mcf_cwd" \
    2>"$tmp/err-$mcf_label") \
    || fail "$mcf_label: an unusable --cwd must not fail the detector"
  [ "$mcf_out" = pending ] \
    || fail "$mcf_label: heuristics should run (pending), got '$mcf_out'"
  grep -q "not a usable oracle join key" "$tmp/err-$mcf_label" \
    || fail "$mcf_label: the skipped oracle must be warned about, not silent"
  echo "ok: unusable --cwd ($mcf_label) warns and falls back to the heuristics"
}
mc_fallback cwd-relative relative/path
mc_fallback cwd-tab "$(printf '/wt/bad\tpath')"
mc_fallback cwd-empty ""
long_cwd="/$(printf 'a%.0s' $(seq 1 520))"
mc_fallback cwd-overlength "$long_cwd"

echo "ok: test-fleet-pane-detect"
