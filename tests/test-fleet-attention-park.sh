#!/bin/bash
# Tests for scripts/fleet-attention.sh `park` — the fork-park attention push
# (fleet-hardening Task 2: D-2; REQ-A1.1, REQ-E1.2, REQ-E1.3).
#
# `park <worker> <scope> <reason>` records an `awaiting-human` attention row the
# instant a worker parks at a decision fork, carrying the notification reason
# (an additive 9th store field) and a commit-time timestamp (field 4), so the
# classifier resolves `awaiting-human` DIRECTLY from the stored state — never by
# heartbeat-age inference. It EXTENDS the shipped store (REQ-E1.2): the reason is
# appended additively so an 8-field heartbeat/decide row is byte-identical to
# before, and park never clobbers a queued human decision (an existing
# awaiting-input row — a flailing escalation or a pending permission — is
# preserved atomically, the --unless-awaiting discipline).
#
# What is covered:
#   - park on a fresh / working worker writes state=awaiting-input, a numeric
#     commit-time timestamp, and the reason in field 9;
#   - park is a no-op that PRESERVES an existing awaiting-input decision (the
#     decide row's question/options survive; park never auto-resolves a queued
#     human decision, REQ-A1.3/REQ-E1.2);
#   - additive-field regression: a heartbeat row and a decide row remain exactly
#     8 tab-separated fields (7 tabs, no field 9, no trailing tab) — the shipped
#     layout is unchanged for every non-park writer (REQ-E1.2);
#   - the queue renders a park with its reason (not smashed into `options:`) and
#     renders a decide row byte-identically to before (regression);
#   - render still classifies a park as [awaiting-input] (field 9 does not tear
#     the 8-field reader);
#   - clear removes a park row;
#   - park refuses a malformed worker/scope/reason (exit 2) — no capture-pane,
#     no model call (pure shell) anywhere in the path.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FA="$here/../scripts/fleet-attention.sh"
FS="$here/../scripts/fleet-state.sh"
tab=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
ok() { echo "ok: $1"; }

[ -x "$FA" ] || fail "scripts/fleet-attention.sh missing or not executable"
[ -x "$FS" ] || fail "scripts/fleet-state.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Hermetic invocation against a given home: strip every ambient resolution knob.
aenv() {
  _home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT \
    -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS \
    PLANWRIGHT_FLEET_STATE_DIR="$_home" /bin/sh "$FA" "$@"
}

# row_field <home> <worker> <field-index> — one field of the worker's record.
row_field() {
  rf_store="$1/attention/state"
  [ -f "$rf_store" ] || return 0
  awk -F "$tab" -v w="$2" -v f="$3" \
    '($1 "") == (w "") { v = $f } END { print v }' "$rf_store"
}

# field_count <home> <worker> — number of tab-separated fields in the record.
field_count() {
  fc_store="$1/attention/state"
  [ -f "$fc_store" ] || {
    echo 0
    return 0
  }
  awk -F "$tab" -v w="$2" '($1 "") == (w "") { print NF }' "$fc_store"
}

# ---------------------------------------------------------------------------
# 1. park on a fresh worker: awaiting-input + reason (field 9) + numeric ts.
# ---------------------------------------------------------------------------
h1="$tmp/h1"
aenv "$h1" park w1 spec-a "notification:idle_prompt" || fail "park exited non-zero"
[ "$(row_field "$h1" w1 3)" = "awaiting-input" ] \
  || fail "park state: got '$(row_field "$h1" w1 3)', expected awaiting-input"
[ "$(row_field "$h1" w1 9)" = "notification:idle_prompt" ] \
  || fail "park reason (field 9): got '$(row_field "$h1" w1 9)'"
ts=$(row_field "$h1" w1 4)
case $ts in "" | *[!0-9]*) fail "park timestamp (field 4) not numeric: '$ts'" ;; esac
ok "park writes awaiting-input + reason field 9 + numeric commit-time timestamp"

# ---------------------------------------------------------------------------
# 2. park NEVER clobbers a queued human decision: an existing awaiting-input
#    decide row (with a real option set) is preserved atomically (REQ-A1.3).
# ---------------------------------------------------------------------------
h2="$tmp/h2"
aenv "$h2" decide w1 spec-a "Approve the risky migration?" "hold" "Apply|Skip" high \
  || fail "decide setup exited non-zero"
aenv "$h2" park w1 spec-a "notification:idle_prompt" || fail "park (over decide) exited non-zero"
[ "$(row_field "$h2" w1 3)" = "awaiting-input" ] || fail "decide row state changed by park"
[ "$(row_field "$h2" w1 6)" = "Approve the risky migration?" ] \
  || fail "decide question clobbered by park: '$(row_field "$h2" w1 6)'"
[ "$(row_field "$h2" w1 8)" = "Apply|Skip" ] \
  || fail "decide options clobbered by park: '$(row_field "$h2" w1 8)'"
[ -z "$(row_field "$h2" w1 9)" ] || fail "park wrote a reason over a queued decision"
ok "park no-ops over an existing awaiting-input decision, preserving it (REQ-A1.3)"

# ---------------------------------------------------------------------------
# 3. park over a WORKING row upgrades it to awaiting-input + reason.
# ---------------------------------------------------------------------------
h3="$tmp/h3"
aenv "$h3" heartbeat w1 spec-a working || fail "heartbeat setup exited non-zero"
aenv "$h3" park w1 spec-a "notification:agent_needs_input" || fail "park (over working) exited non-zero"
[ "$(row_field "$h3" w1 3)" = "awaiting-input" ] || fail "park did not upgrade a working row"
[ "$(row_field "$h3" w1 9)" = "notification:agent_needs_input" ] || fail "park reason not recorded over working"
ok "park upgrades a working row to awaiting-input + reason"

# ---------------------------------------------------------------------------
# 4. Additive-field regression (REQ-E1.2): a heartbeat row and a decide row are
#    EXACTLY 8 fields — no field 9, no trailing tab — byte-identical layout.
# ---------------------------------------------------------------------------
h4="$tmp/h4"
aenv "$h4" heartbeat wA spec-a working || fail "heartbeat exited non-zero"
[ "$(field_count "$h4" wA)" = 8 ] || fail "heartbeat row is $(field_count "$h4" wA) fields, expected 8 (additive regression)"
aenv "$h4" decide wB spec-a "Q?" "d" "X|Y" || fail "decide exited non-zero"
[ "$(field_count "$h4" wB)" = 8 ] || fail "decide row is $(field_count "$h4" wB) fields, expected 8 (additive regression)"
# A park row carries exactly the 9th field.
aenv "$h4" park wC spec-a "notification:idle_prompt" || fail "park exited non-zero"
[ "$(field_count "$h4" wC)" = 9 ] || fail "park row is $(field_count "$h4" wC) fields, expected 9"
ok "additive regression: heartbeat/decide rows stay 8 fields, park adds field 9 (REQ-E1.2)"

# ---------------------------------------------------------------------------
# 5. queue renders a park with its reason (not as options), and renders a
#    decide row's option set unchanged (regression).
# ---------------------------------------------------------------------------
h5="$tmp/h5"
aenv "$h5" park w1 spec-a "notification:idle_prompt" || fail "park exited non-zero"
q_park=$(aenv "$h5" queue) || fail "queue (park) exited non-zero"
printf '%s' "$q_park" | grep -q "notification:idle_prompt" \
  || fail "queue does not surface the park reason: [$q_park]"
printf '%s' "$q_park" | grep -q "options: notification:idle_prompt" \
  && fail "queue mis-renders the park reason as options"
: # decide-row regression
h5b="$tmp/h5b"
aenv "$h5b" decide w1 spec-a "Approve?" "hold" "Apply|Skip" || fail "decide exited non-zero"
q_dec=$(aenv "$h5b" queue) || fail "queue (decide) exited non-zero"
printf '%s' "$q_dec" | grep -q "Q: Approve?" || fail "queue decide question changed: [$q_dec]"
printf '%s' "$q_dec" | grep -q "options: Apply|Skip" || fail "queue decide options changed: [$q_dec]"
ok "queue surfaces a park's reason and renders a decide row unchanged"

# ---------------------------------------------------------------------------
# 6. render classifies a park as [awaiting-input] (field 9 does not tear the
#    8-field render reader).
# ---------------------------------------------------------------------------
h6="$tmp/h6"
aenv "$h6" park w1 spec-a "notification:idle_prompt" || fail "park exited non-zero"
r=$(aenv "$h6" render) || fail "render exited non-zero"
printf '%s' "$r" | grep -q "\[awaiting-input\]" || fail "render did not show [awaiting-input]: [$r]"
printf '%s' "$r" | grep -q "w1" || fail "render did not show the worker: [$r]"
ok "render shows a park as [awaiting-input] (field 9 does not break the reader)"

# ---------------------------------------------------------------------------
# 7. clear removes a park row.
# ---------------------------------------------------------------------------
h7="$tmp/h7"
aenv "$h7" park w1 spec-a "notification:idle_prompt" || fail "park exited non-zero"
aenv "$h7" clear w1 || fail "clear exited non-zero"
[ -z "$(row_field "$h7" w1 3)" ] || fail "clear did not remove the park row"
ok "clear removes a park row"

# ---------------------------------------------------------------------------
# 8. park refuses malformed input (exit 2) — worker, scope, and reason.
# ---------------------------------------------------------------------------
h8="$tmp/h8"
rc=0
aenv "$h8" park "bad/worker" spec-a "r" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "park accepted a malformed worker (exit $rc, expected 2)"
rc=0
aenv "$h8" park w1 "bad scope" "r" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "park accepted a malformed scope (exit $rc, expected 2)"
rc=0
aenv "$h8" park w1 spec-a "" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "park accepted an empty reason (exit $rc, expected 2)"
# A control byte in the reason (record-tearing / terminal injection) is refused.
rc=0
aenv "$h8" park w1 spec-a "$(printf 'bad\treason')" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "park accepted a reason with an embedded tab (exit $rc, expected 2)"
[ -z "$(row_field "$h8" w1 3)" ] || fail "park wrote a row despite refusing the input"
ok "park refuses a malformed worker/scope/reason with no write (exit 2)"

# ---------------------------------------------------------------------------
# 9. No model / API call and no capture-pane anywhere in the park path
#    (REQ-E1.3 / REQ-A1.1 no-pane): a static assertion over the store script.
# ---------------------------------------------------------------------------
grep -nE 'capture-pane' "$FA" && fail "fleet-attention.sh references capture-pane"
grep -nE '(^|[^A-Za-z_])(claude|anthropic|curl|wget)([^A-Za-z_]|$)' "$FA" \
  && fail "fleet-attention.sh references a model/network call in the store path"
ok "no capture-pane and no model/network call in the store path (REQ-E1.3)"

echo "PASS: fleet-attention park"
