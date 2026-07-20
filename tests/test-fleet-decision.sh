#!/bin/bash
# Tests for the structured worker-to-tower DECISION CHANNEL (fleet-hardening
# Task 4: D-4; REQ-A1.4, REQ-A1.5, REQ-E1.2, REQ-E1.3).
#
# The channel has two halves, both under test here:
#   - the WRITE half, `scripts/fleet-attention.sh fork` + `claim`, which extends
#     the shipped `decide` / `awaiting-input` path so a worker parked at a
#     multi-option fork records the pending decision, its full labeled option
#     set, the worker's recommendation, and a UNIQUE INSTANCE ID as a structured
#     store record — and answers it by option LABEL under the store lock, with
#     first-answer-wins claim/close semantics (REQ-A1.4);
#   - the ANSWER + DELIVERY half, `scripts/fleet-decision.sh answer`, which
#     claims the record by label and delivers the answer DOWNWARD through the
#     existing attributed buffer-paste / structured-marker path
#     (scripts/orchestrate-relay.sh), NEVER a `send-keys` menu-navigation path
#     (REQ-A1.5).
#
# What is covered:
#   - a fork writes a record carrying every option label + the recommendation +
#     a unique instance id (REQ-A1.4);
#   - answering by label selects the correct option even when the option order
#     is the REVERSE of a sibling prompt (the 2026-07-19 Skip/Apply reorder) —
#     the answer is by label, immune to menu reordering (REQ-A1.4);
#   - the answer is delivered by buffer-paste selected by label, and NO
#     `send-keys` menu-navigation path exists anywhere in the channel (REQ-A1.5);
#   - the instance id the answer must match: a stale answer for a resolved fork
#     whose labels COLLIDE with a later fork is refused, not mis-applied
#     (REQ-A1.4);
#   - double-answer: first-answer-wins claim/close (the second answer is a
#     no-op, no second delivery) (REQ-A1.4);
#   - the channel mechanically refuses to emit an answer for a record whose
#     reason is a permission-park, keeping that gate the human's (REQ-A1.5);
#   - additive-field regression (REQ-E1.2): heartbeat/decide rows stay 8 fields,
#     park stays 9, an unclaimed fork is 10, a claimed fork is 11 — the shipped
#     layout is byte-identical for every non-fork writer;
#   - no model/API call and no `capture-pane` anywhere in the channel's decision
#     path (REQ-E1.3).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FA="$here/../scripts/fleet-attention.sh"
FD="$here/../scripts/fleet-decision.sh"
FS="$here/../scripts/fleet-state.sh"
RELAY="$here/../scripts/orchestrate-relay.sh"
tab=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
ok() { echo "ok: $1"; }

[ -x "$FA" ] || fail "scripts/fleet-attention.sh missing or not executable"
[ -x "$FD" ] || fail "scripts/fleet-decision.sh missing or not executable"
[ -x "$FS" ] || fail "scripts/fleet-state.sh missing or not executable"
[ -x "$RELAY" ] || fail "scripts/orchestrate-relay.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Hermetic invocation against a given home: strip every ambient resolution knob,
# then pin the Task 9 override so the store lives under the case's home (no HOME,
# no dotfiles — marketplace-install parity). Both scripts resolve the same home
# from the same override.
aenv() {
  _home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT \
    -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS \
    -u PLANWRIGHT_ATTENTION_SURFACE_PROVIDED \
    PLANWRIGHT_FLEET_STATE_DIR="$_home" /bin/sh "$FA" "$@"
}
denv() {
  _home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT \
    -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS \
    -u PLANWRIGHT_ATTENTION_SURFACE_PROVIDED \
    PLANWRIGHT_FLEET_STATE_DIR="$_home" /bin/sh "$FD" "$@"
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
# 1. fork writes a structured record: every option label + the recommendation
#    + a unique instance id, in awaiting-input state (REQ-A1.4).
# ---------------------------------------------------------------------------
h1="$tmp/h1"
aenv "$h1" fork w1 spec-a "Apply the risky migration?" "Skip" "Apply|Skip|Modify" "fork-0001" high \
  || fail "fork exited non-zero"
[ "$(row_field "$h1" w1 3)" = "awaiting-input" ] \
  || fail "fork state: got '$(row_field "$h1" w1 3)', expected awaiting-input"
[ "$(row_field "$h1" w1 6)" = "Apply the risky migration?" ] \
  || fail "fork question (field 6): got '$(row_field "$h1" w1 6)'"
[ "$(row_field "$h1" w1 7)" = "Skip" ] \
  || fail "fork recommendation (field 7): got '$(row_field "$h1" w1 7)'"
[ "$(row_field "$h1" w1 8)" = "Apply|Skip|Modify" ] \
  || fail "fork option set (field 8): got '$(row_field "$h1" w1 8)'"
[ "$(row_field "$h1" w1 9)" = "fork" ] \
  || fail "fork marker (field 9): got '$(row_field "$h1" w1 9)', expected 'fork'"
[ "$(row_field "$h1" w1 10)" = "fork-0001" ] \
  || fail "fork instance id (field 10): got '$(row_field "$h1" w1 10)'"
ts=$(row_field "$h1" w1 4)
case $ts in "" | *[!0-9]*) fail "fork timestamp (field 4) not numeric: '$ts'" ;; esac
ok "fork writes a structured record: labels + recommendation + unique instance id (REQ-A1.4)"

# ---------------------------------------------------------------------------
# 2. fork validates the recommendation is one of the labels, and rejects a
#    degenerate / malformed option set (REQ-A1.4 well-formedness).
# ---------------------------------------------------------------------------
h2="$tmp/h2"
rc=0
aenv "$h2" fork w1 spec-a "Q?" "Nope" "Apply|Skip" "fork-x" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "fork accepted a recommendation not in the option set (exit $rc, expected 2)"
[ -z "$(row_field "$h2" w1 3)" ] || fail "fork wrote a row despite an off-set recommendation"
rc=0
aenv "$h2" fork w1 spec-a "Q?" "Apply" "Apply" "fork-y" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "fork accepted a single-option (non-)fork (exit $rc, expected 2)"
# A duplicate label makes the "two distinct labels" set degenerate (an answer
# would be ambiguous), and must be rejected — not counted as two options.
rc=0
aenv "$h2" fork w1 spec-a "Q?" "a" "a|a" "fork-d" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "fork accepted a duplicate-label option set as a two-option decision (exit $rc, expected 2)"
rc=0
aenv "$h2" fork w1 spec-a "Q?" "a" "a|b|a" "fork-d2" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "fork accepted a set with a repeated label (exit $rc, expected 2)"
# Numeric-string aliasing: a recommendation `1` must NOT be treated as present in
# a `01|2` set (awk numeric aliasing would equate `1` and `01`), so this is an
# off-set recommendation and must be refused.
rc=0
aenv "$h2" fork w1 spec-a "Q?" "1" "01|2" "fork-n" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "fork accepted a numeric-aliased off-set recommendation (1 vs 01) (exit $rc, expected 2)"
ok "fork rejects off-set recommendation, single-option, duplicate labels, and numeric aliasing (REQ-A1.4)"

# ---------------------------------------------------------------------------
# 3. Answer by LABEL selects the correct option even when the option order is
#    the REVERSE of a sibling prompt (the 2026-07-19 Skip/Apply reorder). The
#    claim resolves the label positionally-independently (REQ-A1.4).
# ---------------------------------------------------------------------------
h3="$tmp/h3"
# Sibling prompt A: Apply|Skip. Sibling prompt B (reordered): Skip|Apply.
aenv "$h3" fork wA spec-a "Approve A?" "Apply" "Apply|Skip" "iid-A" \
  || fail "fork A exited non-zero"
aenv "$h3" fork wB spec-a "Approve B?" "Apply" "Skip|Apply" "iid-B" \
  || fail "fork B (reordered) exited non-zero"
# Answer BOTH with the SAME label "Apply". Position differs (option 1 in A,
# option 2 in B); the by-label claim must resolve "Apply" in each regardless.
selA=$(aenv "$h3" claim wA "iid-A" "Apply") || fail "claim wA Apply exited non-zero"
selB=$(aenv "$h3" claim wB "iid-B" "Apply") || fail "claim wB Apply exited non-zero"
[ "$selA" = "Apply" ] || fail "claim wA resolved to '$selA', expected Apply"
[ "$selB" = "Apply" ] || fail "claim wB (reordered) resolved to '$selB', expected Apply"
# The claimed label is recorded on the record (field 11) — first-answer-wins.
[ "$(row_field "$h3" wA 11)" = "Apply" ] || fail "claim did not record the claimed label on wA"
[ "$(row_field "$h3" wB 11)" = "Apply" ] || fail "claim did not record the claimed label on wB"
ok "answer by label selects the correct option under a reordered option set (REQ-A1.4)"

# ---------------------------------------------------------------------------
# 4. claim refuses an invalid label (not a member of the option set) — no
#    close, no mis-apply (REQ-A1.4).
# ---------------------------------------------------------------------------
h4="$tmp/h4"
aenv "$h4" fork w1 spec-a "Q?" "Apply" "Apply|Skip" "iid-1" || fail "fork exited non-zero"
rc=0
aenv "$h4" claim w1 "iid-1" "Frobnicate" >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "claim accepted a label outside the option set"
[ -z "$(row_field "$h4" w1 11)" ] || fail "claim recorded a label despite refusing an invalid one"
# Numeric-string aliasing: answering `01` against a `1|2` set must be refused —
# `01` is not a member, and awk must not numerically alias it onto option `1`.
h4b="$tmp/h4b"
aenv "$h4b" fork w1 spec-a "Q?" "1" "1|2" "iid-n" || fail "numeric fork exited non-zero"
rc=0
aenv "$h4b" claim w1 "iid-n" "01" >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "claim numerically aliased label 01 onto option 1 (accepted a non-member)"
[ -z "$(row_field "$h4b" w1 11)" ] || fail "claim closed a fork with a numeric-aliased non-member label"
# The exact member still resolves.
sel=$(aenv "$h4b" claim w1 "iid-n" "1") || fail "claim of the exact numeric label 1 exited non-zero"
[ "$sel" = "1" ] || fail "claim of label 1 resolved to '$sel'"
ok "claim refuses an out-of-set label, including numeric-aliased ones (01 vs 1) (REQ-A1.4)"

# ---------------------------------------------------------------------------
# 5. The instance id the answer must match: a STALE answer for a resolved fork
#    whose labels collide with a LATER fork is refused, not mis-applied
#    (REQ-A1.4). Same worker reused across two forks with identical labels.
# ---------------------------------------------------------------------------
h5="$tmp/h5"
aenv "$h5" fork w1 spec-a "First fork" "Apply" "Apply|Skip" "iid-old" \
  || fail "first fork exited non-zero"
first=$(aenv "$h5" claim w1 "iid-old" "Apply") || fail "first claim exited non-zero"
[ "$first" = "Apply" ] || fail "first claim resolved to '$first'"
# The worker resumes and re-parks at a NEW fork with the SAME colliding labels
# but a fresh instance id.
aenv "$h5" fork w1 spec-a "Second fork" "Skip" "Apply|Skip" "iid-new" \
  || fail "second fork exited non-zero"
# A late answer carrying the OLD instance id must be refused (stale), never
# applied to the new fork despite the colliding labels.
rc=0
aenv "$h5" claim w1 "iid-old" "Apply" >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "a stale answer (old instance id) was accepted against the new fork"
[ "$(row_field "$h5" w1 10)" = "iid-new" ] || fail "the new fork instance id was overwritten"
[ -z "$(row_field "$h5" w1 11)" ] || fail "a stale answer mis-applied a claimed label to the new fork"
# The correct (fresh) instance id still resolves.
sel=$(aenv "$h5" claim w1 "iid-new" "Skip") || fail "claim with the fresh instance id exited non-zero"
[ "$sel" = "Skip" ] || fail "fresh claim resolved to '$sel', expected Skip"
ok "a stale answer for a resolved fork is refused; the fresh instance id still resolves (REQ-A1.4)"

# ---------------------------------------------------------------------------
# 5b. A label carrying a literal backslash (printable, so valid) matches and is
#     stored VERBATIM — awk `-v` escape processing must not mangle it into a
#     control byte (which would tear the record) or a non-matching value.
# ---------------------------------------------------------------------------
h5b="$tmp/h5b"
bs='Retry\the step'
aenv "$h5b" fork w1 spec-a "Q?" "$bs" "$bs|Skip" "iid-bs" || fail "fork with a backslash label exited non-zero"
sel=$(aenv "$h5b" claim w1 "iid-bs" "$bs") || fail "claim with a backslash label exited non-zero"
[ "$sel" = "$bs" ] || fail "backslash label mangled by claim: got '$sel', expected '$bs'"
# Stored verbatim (field 11), no embedded control byte tearing the record.
[ "$(row_field "$h5b" w1 11)" = "$bs" ] || fail "claimed backslash label not stored verbatim: '$(row_field "$h5b" w1 11)'"
[ "$(field_count "$h5b" w1)" = 11 ] || fail "backslash label tore the record ($(field_count "$h5b" w1) fields, expected 11)"
ok "a backslash-bearing label matches and stores verbatim (no awk -v escape mangling)"

# ---------------------------------------------------------------------------
# 5c. claim distinguishes an OPERATIONAL failure (exit 2) from a semantic refusal
#     (exit 3): a store that exists but cannot be READ exits 2 (matching
#     upsert_row/clear's fs convention), so a caller tells "store I/O broke" from
#     "the answer does not apply". Skipped when running as root (perms ignored).
# ---------------------------------------------------------------------------
if [ "$(id -u)" != 0 ]; then
  h5c="$tmp/h5c"
  aenv "$h5c" fork w1 spec-a "Q?" "A" "A|B" "iid-op" || fail "fork exited non-zero"
  chmod 000 "$h5c/attention/state"
  rc=0
  aenv "$h5c" claim w1 "iid-op" "A" >/dev/null 2>&1 || rc=$?
  chmod 644 "$h5c/attention/state" 2>/dev/null || true
  [ "$rc" = 2 ] || fail "claim on an unreadable store exited $rc, expected 2 (operational, not a refusal 3)"
  ok "claim exits 2 (operational) on an unreadable store, distinct from a semantic refusal (REQ-A1.4)"
else
  ok "claim operational-vs-refusal exit code (skipped: running as root, file perms ignored)"
fi

# ---------------------------------------------------------------------------
# 6. Double-answer: first-answer-wins claim/close. The second answer is a no-op
#    (refused, no second close, the first label stands) (REQ-A1.4).
# ---------------------------------------------------------------------------
h6="$tmp/h6"
aenv "$h6" fork w1 spec-a "Q?" "Apply" "Apply|Skip" "iid-1" || fail "fork exited non-zero"
first=$(aenv "$h6" claim w1 "iid-1" "Apply") || fail "first claim exited non-zero"
[ "$first" = "Apply" ] || fail "first claim resolved to '$first'"
rc=0
aenv "$h6" claim w1 "iid-1" "Skip" >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "a second answer to an already-claimed fork was accepted (first-answer-wins violated)"
[ "$(row_field "$h6" w1 11)" = "Apply" ] || fail "the second answer overwrote the first claim (got '$(row_field "$h6" w1 11)')"
ok "double-answer: first-answer-wins; the second answer is a no-op (REQ-A1.4)"

# ---------------------------------------------------------------------------
# 7. The channel mechanically refuses to emit an answer for a permission-park,
#    keeping that gate the human's (REQ-A1.5). TWO shapes are covered:
#    (a) the PRODUCTION shape — a permission record is a `decide` row with an
#        EMPTY field 9 (the permission state lives in a separate liveness marker,
#        per fleet-liveness.sh), refused by the generic not-a-fork branch;
#    (b) DEFENSE-IN-DEPTH — a record whose field 9 explicitly marks `permission:`
#        (a shape no shipped writer emits today) is refused by the permission
#        branch with its own diagnostic. Neither is an answerable fork.
# ---------------------------------------------------------------------------
# (a) production shape: a decide-written permission record — empty field 9, no
#     instance id — must be refused (never answered as a fork).
h7="$tmp/h7"
aenv "$h7" decide w1 spec-a "Worker is awaiting a permission decision in its session" \
  "answer in the worker session" "approve in the worker session|deny in the worker session" normal \
  || fail "permission-record setup (decide) exited non-zero"
rc=0
aenv "$h7" claim w1 "iid-perm" "approve in the worker session" >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "claim answered a production-shape permission record (empty field 9)"
[ -z "$(row_field "$h7" w1 11)" ] || fail "claim closed a production-shape permission record"
# (b) defense-in-depth: an explicit permission-reason record (field 9), with an
#     instance id so the permission branch — not a missing id — is what refuses.
h7b="$tmp/h7b"
mkdir -p "$h7b/attention"
printf 'w1\tspec-a\tawaiting-input\t1700000000\tnormal\tPermission?\tanswer in session\tapprove|deny\tpermission:tool-x\tiid-perm\n' \
  >"$h7b/attention/state"
rc=0
aenv "$h7b" claim w1 "iid-perm" "approve" >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "claim answered an explicit permission-reason record (the human's gate was bypassed)"
[ -z "$(row_field "$h7b" w1 11)" ] || fail "claim closed an explicit permission-reason record"
ok "claim refuses a permission-park — production (empty field 9) and explicit (permission: reason) shapes (REQ-A1.5)"

# ---------------------------------------------------------------------------
# 8. ANSWER + DELIVERY (REQ-A1.5): fleet-decision.sh answer claims by label and
#    emits the DOWNWARD delivery through the attributed buffer-paste path — the
#    label lands in a structured-marker answer artifact, and the emitted command
#    is a load-buffer/paste-buffer relay, NEVER send-keys.
# ---------------------------------------------------------------------------
h8="$tmp/h8"
aenv "$h8" fork w1 spec-a "Approve?" "Apply" "Apply|Skip" "iid-1" || fail "fork exited non-zero"
out=$(denv "$h8" answer tmux "dev:1.0" w1 "iid-1" "Apply") || fail "answer exited non-zero"
# The emitted delivery is a buffer-paste relay (load-buffer + paste-buffer) at
# the target handle — the same attributed path orchestrate-relay.sh emits. Assert
# the buffer-paste verbs and the target handle SEPARATELY (not orchestrate-relay's
# exact flag layout), so a benign relay-format change does not break this channel
# test while the channel behavior is unchanged.
printf '%s\n' "$out" | grep -q "load-buffer" \
  || fail "answer did not emit a buffer-paste (load-buffer) delivery: [$out]"
printf '%s\n' "$out" | grep -q "paste-buffer" \
  || fail "answer did not emit a paste-buffer delivery: [$out]"
printf '%s\n' "$out" | grep -q "dev:1.0" \
  || fail "answer did not target the requested handle: [$out]"
# NEVER a send-keys menu-navigation path.
printf '%s\n' "$out" | grep -q "send-keys" \
  && fail "answer emitted a send-keys path (impersonation / menu navigation)"
# The answer artifact is a structured marker carrying the chosen label (by
# label, not a menu position). It persists so the tower can run the emitted
# paste command against it.
ans="$h8/attention/answers/w1"
[ -f "$ans" ] || fail "answer did not persist a structured-marker answer artifact at $ans"
grep -q "iid-1" "$ans" || fail "the answer artifact does not carry the instance id: [$(cat "$ans")]"
grep -q "Apply" "$ans" || fail "the answer artifact does not carry the chosen label: [$(cat "$ans")]"
# The record is closed (first-answer-wins), so a second delivery is a no-op.
[ "$(row_field "$h8" w1 11)" = "Apply" ] || fail "answer did not close the fork record"
ok "answer delivers the chosen label by buffer-paste, never send-keys (REQ-A1.5)"

# ---------------------------------------------------------------------------
# 9. answer refuses to deliver a permission-park record — the mechanical refusal
#    reaches through the whole channel, not just the store primitive (REQ-A1.5).
# ---------------------------------------------------------------------------
h9="$tmp/h9"
mkdir -p "$h9/attention"
printf 'w1\tspec-a\tawaiting-input\t1700000000\tnormal\tPermission?\tanswer in session\tapprove|deny\tpermission:tool-x\tiid-perm\n' \
  >"$h9/attention/state"
rc=0
denv "$h9" answer tmux "dev:1.0" w1 "iid-perm" "approve" >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "answer delivered a permission-park record (the human's gate was bypassed)"
[ ! -f "$h9/attention/answers/w1" ] || fail "answer wrote a delivery artifact for a permission-park record"
ok "answer refuses a permission-park record end-to-end (REQ-A1.5)"

# ---------------------------------------------------------------------------
# 9b. fork must NOT clobber a queued human decision (a pending permission /
#     flailing `decide` row — awaiting-input with an empty field 9), keeping that
#     gate the human's; but it MUST replace a park (upgrade) and a prior fork
#     (re-fork), both of which carry a non-empty field 9.
# ---------------------------------------------------------------------------
# (a) refuse over a queued decide/permission row (empty field 9).
h9b="$tmp/h9b"
aenv "$h9b" decide w1 spec-a "Approve the risky migration?" "hold" "Apply|Skip" high \
  || fail "decide setup exited non-zero"
rc=0
aenv "$h9b" fork w1 spec-a "Different fork?" "X" "X|Y" "iid-clobber" >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "fork clobbered a queued human decision (permission/flailing)"
[ "$(row_field "$h9b" w1 6)" = "Approve the risky migration?" ] \
  || fail "fork overwrote the queued decide question: '$(row_field "$h9b" w1 6)'"
[ -z "$(row_field "$h9b" w1 10)" ] || fail "fork wrote an instance id over a queued decide"
# (b) upgrade a park (field 9 = notification:*) to an answerable fork.
h9c="$tmp/h9c"
aenv "$h9c" park w1 spec-a "notification:idle_prompt" || fail "park setup exited non-zero"
aenv "$h9c" fork w1 spec-a "Now a structured fork?" "X" "X|Y" "iid-up" \
  || fail "fork failed to upgrade a park"
[ "$(row_field "$h9c" w1 9)" = "fork" ] || fail "fork did not upgrade the park to a fork marker"
[ "$(row_field "$h9c" w1 10)" = "iid-up" ] || fail "fork did not stamp the instance id over the park"
# (c) re-fork replaces a prior fork (field 9 = fork).
h9d="$tmp/h9d"
aenv "$h9d" fork w1 spec-a "First" "X" "X|Y" "iid-1" || fail "first fork exited non-zero"
aenv "$h9d" fork w1 spec-a "Second" "Y" "X|Y" "iid-2" || fail "re-fork exited non-zero"
[ "$(row_field "$h9d" w1 10)" = "iid-2" ] || fail "re-fork did not replace the prior fork instance id"
ok "fork refuses to clobber a queued decision, upgrades a park, and allows a re-fork (REQ-A1.5)"

# ---------------------------------------------------------------------------
# 10. Additive-field regression (REQ-E1.2): the shipped writers are unchanged.
#     heartbeat/decide = 8 fields, park = 9, an unclaimed fork = 10, a claimed
#     fork = 11 — a monotonic additive ladder, older readers ignore the tail.
# ---------------------------------------------------------------------------
h10="$tmp/h10"
aenv "$h10" heartbeat wA spec-a working || fail "heartbeat exited non-zero"
[ "$(field_count "$h10" wA)" = 8 ] || fail "heartbeat row is $(field_count "$h10" wA) fields, expected 8"
aenv "$h10" decide wB spec-a "Q?" "d" "X|Y" || fail "decide exited non-zero"
[ "$(field_count "$h10" wB)" = 8 ] || fail "decide row is $(field_count "$h10" wB) fields, expected 8"
aenv "$h10" park wC spec-a "notification:idle_prompt" || fail "park exited non-zero"
[ "$(field_count "$h10" wC)" = 9 ] || fail "park row is $(field_count "$h10" wC) fields, expected 9"
aenv "$h10" fork wD spec-a "Q?" "X" "X|Y" "iid-d" || fail "fork exited non-zero"
[ "$(field_count "$h10" wD)" = 10 ] || fail "unclaimed fork row is $(field_count "$h10" wD) fields, expected 10"
aenv "$h10" claim wD "iid-d" "X" >/dev/null || fail "claim exited non-zero"
[ "$(field_count "$h10" wD)" = 11 ] || fail "claimed fork row is $(field_count "$h10" wD) fields, expected 11"
ok "additive regression: heartbeat/decide=8, park=9, fork=10, claimed fork=11 (REQ-E1.2)"

# ---------------------------------------------------------------------------
# 11. REQ-E1.2 positive regression: the queue still renders a shipped decide row
#     byte-identically, AND surfaces a fork as an answerable decision (with its
#     labeled option set + recommendation), not a corrupted line.
# ---------------------------------------------------------------------------
h11="$tmp/h11"
aenv "$h11" decide wDec spec-a "Approve?" "hold" "Apply|Skip" || fail "decide exited non-zero"
q_dec=$(aenv "$h11" queue) || fail "queue (decide) exited non-zero"
printf '%s' "$q_dec" | grep -q "Q: Approve?" || fail "queue decide question changed: [$q_dec]"
printf '%s' "$q_dec" | grep -q "options: Apply|Skip" || fail "queue decide options changed: [$q_dec]"
h11b="$tmp/h11b"
aenv "$h11b" fork wFork spec-a "Approve the fork?" "Skip" "Apply|Skip|Modify" "iid-q" \
  || fail "fork exited non-zero"
q_fork=$(aenv "$h11b" queue) || fail "queue (fork) exited non-zero"
printf '%s' "$q_fork" | grep -q "Approve the fork?" \
  || fail "queue did not surface the fork question: [$q_fork]"
printf '%s' "$q_fork" | grep -q "Apply|Skip|Modify" \
  || fail "queue did not surface the fork option set: [$q_fork]"
# The fork marker literal 'fork' must NOT leak into the priority bracket (a field
# collapse would slide field 9 into the wrong slot, the Task 2 park gotcha).
printf '%s' "$q_fork" | grep -q "^- \[fork\]" \
  && fail "queue rendered the fork marker in the priority bracket (field collapse): [$q_fork]"
ok "queue renders a decide row unchanged and surfaces a fork as an answerable decision (REQ-E1.2)"

# ---------------------------------------------------------------------------
# 12. Source audit (REQ-E1.3, REQ-A1.5): the EXECUTABLE code of the channel's
#     OWN scripts (fleet-attention.sh, fleet-decision.sh) contains no
#     model/network call, no capture-pane, and no send-keys path. Comment lines
#     are stripped first so the doc blocks (which name the prohibitions) are not
#     themselves read as violations — the audit targets code, not documentation,
#     exactly as test-orchestrate-relay.sh does. The delegated DELIVERY path
#     (orchestrate-relay.sh) is asserted send-keys-free behaviorally in Test 8
#     (the emitted command) and by orchestrate-relay's own source-audit suite, so
#     it is not re-grepped wholesale here (its observe path legitimately uses
#     capture-pane, which is not part of this channel's delivery).
# ---------------------------------------------------------------------------
for f in "$FA" "$FD"; do
  code="$tmp/$(basename "$f").code"
  grep -v '^[[:space:]]*#' "$f" >"$code" || true
  grep -q 'capture-pane' "$code" && fail "$(basename "$f") code references capture-pane"
  grep -Eq '(^|[^A-Za-z_])(claude|anthropic|curl|wget|openai)([^A-Za-z_]|$)' "$code" \
    && fail "$(basename "$f") code references a model/network call"
  grep -q 'send-keys' "$code" && fail "$(basename "$f") code references a send-keys path"
  grep -Eq '(^|[^A-Za-z_])eval([^A-Za-z_]|$)' "$code" \
    && fail "$(basename "$f") code references an eval path"
done
ok "source audit: no model/network call, no capture-pane, no send-keys, no eval in the channel code (REQ-E1.3, REQ-A1.5)"

echo "PASS: fleet-decision (Task 4 structured decision channel)"
