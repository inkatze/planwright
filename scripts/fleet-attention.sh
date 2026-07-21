#!/bin/sh
# fleet-attention.sh — the substrate-agnostic ATTENTION/NOTIFICATION capability,
# lifted into core paralleling the execution capability (orchestration-fleet
# Task 12; D-13, REQ-E1.3, REQ-E1.4, REQ-A1.6). It gives every persona a legible
# default surface without any dotfiles-local mechanism, so a marketplace-install
# user gets it from core.
#
# WHAT IT PROVIDES (D-13):
#   (a) HEARTBEAT/AWARENESS STATE — a per-worker current-state store keyed by
#       worker handle: scope (spec + unit), state (working / idle / hung /
#       ended / awaiting-input / pr-ready / merged / done — idle/hung/ended
#       are the hook-pushed liveness states, fleet-autonomy Task 2), a
#       commit-time heartbeat, and — for an awaiting-input worker — the
#       structured decision it is blocked on.
#   (b) a PORTABLE STATUS RENDERER (`render`) — lists each worker's scope + state.
#   (c) the DECISION QUEUE (`queue`) — one ordered, alarm-rationalized queue of
#       ACTIONABLE items across all active specs, each a structured choice
#       (scope, question, recommended default, options). Its length tracks the
#       `## Awaiting input` count (one awaiting-input record per blocked unit),
#       NOT the worker count: non-actionable signal (working / pr-ready / merged
#       / done) is suppressed. Ordering is priority-desc then oldest-waiting-first
#       (ISA-18.2 alarm rationalization: every surfaced item actionable,
#       prioritized by consequence).
#   (d) a NOTIFICATION SEAM (`notify`) — the channel (none / tmux-popup /
#       os-notify / editor-toast / statusline) is the overlay VALUE (resolve-
#       notification-channel.sh); this script is the seam that dispatches
#       through it. statusline is pull-shaped (fleet-autonomy Task 8, D-14):
#       Claude Code renders scripts/fleet-statusline.sh on its own schedule, so
#       `notify` is a no-op for that channel — there is nothing to push.
#
# BUILT ON TASK 9 (D-11, REQ-D1.1: consume, do not re-implement). The cross-spec
# home and the advisory-lock primitive are scripts/fleet-state.sh's: `root`
# resolves the D-11 home, `lock`/`unlock` are the named concurrency primitive.
# The attention store lives at <fleet-home>/attention/, so heartbeat/registry
# state lives under the same cross-spec home Task 9 owns, and every mutating
# write is serialized through the Task 9 lock (read-during-write safe: a reader
# sees an atomically-renamed complete file, never a torn one). No fleet path ever
# writes into the sibling's spec-local .orchestrate/ dir.
#
# provides_attention_surface (backend-capability-contract, D-2): when a backend
# supplies its own attention surface, planwright suppresses its OWN decision
# queue (the actionable surface) and defers; the status render stays available,
# so the operator sees one actionable surface, not two. Signalled per-call by
# --surface-provided (what an entry command passes from the selected backend's
# advertised set) or the ambient PLANWRIGHT_ATTENTION_SURFACE_PROVIDED env.
#
# REQ-A1.6 (artifact data hygiene). Worker/scope handles are validated against
# the Task 9 field grammar and decision text against a control-free text grammar
# BEFORE any write, so a traversal token, an embedded tab/newline, or a control
# byte is refused rather than tearing the store or escaping a path. Rendered
# output is stripped of C0/DEL through the canonical echo-discipline sanitizer,
# so even a hand-corrupted store line cannot drive the terminal.
#
# Usage:
#   fleet-attention.sh heartbeat <worker> <scope> <state> [--unless-awaiting]
#       Upsert the worker's current state (one row per worker, last wins).
#       <state> ∈ working | idle | hung | ended | pr-ready | merged | done
#       (idle/hung/ended are the hook-pushed liveness states, fleet-autonomy
#       Task 2). awaiting-input needs a structured decision — use `decide`.
#       --unless-awaiting: a clean no-op when the current row is
#       awaiting-input, checked atomically inside the store's critical
#       section — the escalation-preserve primitive (REQ-A1.3): a downgrade
#       push must never overwrite a queued human decision.
#   fleet-attention.sh decide <worker> <scope> <question> <default> <options> [priority]
#       Upsert the worker as awaiting-input WITH a structured decision.
#       [priority] ∈ high | normal | low (default normal).
#   fleet-attention.sh fork <worker> <scope> <question> <recommend> <options> <instance-id> [priority]
#       The answerable decision channel (fleet-hardening Task 4, D-4): upsert the
#       worker as awaiting-input with a STRUCTURED, answerable decision — the
#       question, the worker's <recommend>ation, the full labeled <options> set
#       (`|`-delimited labels), and a UNIQUE <instance-id> the answer must match.
#       Field 9 is the fixed marker `fork` (distinguishing an answerable fork
#       from a park / permission / plain decide); the instance id lands in the
#       additive 10th field. <recommend> must be one of the <options> labels, and
#       <options> must carry at least two DISTINCT non-empty labels (a duplicate
#       label is refused so an answer resolves unambiguously). [priority] ∈ high |
#       normal | low (default normal). Exits 3 (a semantic refusal) rather than
#       clobber a queued human decision (a pending permission / flailing decide);
#       it still replaces a park (upgrade) or a prior fork (re-fork).
#   fleet-attention.sh claim <worker> <instance-id> <label>
#       Answer an answerable fork BY LABEL, atomically, under the store lock —
#       the read-and-answer primitive (fleet-hardening Task 4, D-4). First-answer
#       -wins claim/close: the winning <label> is stamped into the additive 11th
#       field, so a second answer is a refused no-op. Refuses (exit 3, no close):
#       a stale <instance-id> (the answer is for a resolved fork), a <label>
#       outside the option set, an already-claimed record, and — keeping the
#       harness permission gate the human's — any record whose reason is a
#       permission-park (never an answerable `fork`). Prints the matched label on
#       success. Exit codes mirror the rest of this script so a caller can tell
#       the two failure kinds apart: 0 success; 2 a usage/malformed input OR an
#       operational error (lock / store read / mktemp / write / mv — nothing
#       consumed, a retry may help); 3 a semantic REFUSAL (stale / bad label /
#       already-claimed / permission-park / no such fork — nothing consumed, the
#       answer does not apply). It does NOT deliver; scripts/fleet-decision.sh
#       composes the claim with the attributed buffer-paste downward delivery.
#   fleet-attention.sh park <worker> <scope> <reason>
#       The fork-park attention push (fleet-hardening Task 2, D-2): upsert the
#       worker as awaiting-input carrying only the notification <reason> (the
#       additive 9th field) — no option set (that is `decide`'s answerable
#       channel). Atomic --unless-awaiting: a no-op that preserves a queued
#       decision. The classifier resolves the row to awaiting-human directly.
#   fleet-attention.sh clear <worker>
#       Remove the worker's row (idempotent) — cleanup on merged/done teardown.
#   fleet-attention.sh render [--surface-provided]
#       Status renderer: each worker's scope + state.
#   fleet-attention.sh queue [--count] [--surface-provided]
#       Decision queue: ordered actionable items as structured choices.
#       --count prints only the item count (the length that tracks the
#       `## Awaiting input` count).
#   fleet-attention.sh notify <summary>
#       Push <summary> through the resolved notification channel.
#
# Exit codes: 0 success; 2 usage error, unresolvable home, refused hostile
#   input, or a filesystem/lock error (fail closed); 3 a SEMANTIC refusal on the
#   Task 4 decision channel — `claim` refusing an answer (stale / bad label /
#   already-claimed / permission-park / no such fork) and `fork` refusing to
#   clobber a queued human decision (the unless-decide guard) — distinct from the
#   operational 2 so a caller can tell "the request does not apply" from "the
#   store I/O broke"; other non-zero from a propagated resolver hard-fail
#   (notify).
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling): uses the
# same widely-portable extensions fleet-state.sh does — `date +%s`, a fractional
# `sleep` — plus awk/sort/mktemp. No eval, no jq/fish/mise (REQ-K1.5). All input
# is data. Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# The canonical echo-discipline sanitizer (doctrine/security-posture.md), sourced
# as the sibling command scripts do; a missing helper is a broken install.
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FS="$script_dir/fleet-state.sh"
RNC="$script_dir/resolve-notification-channel.sh"
TAB=$(printf '\t')

# The Task 9 field grammar for worker/scope handles (REQ-A1.6), byte-identical to
# fleet-state.sh valid_field: excludes path separators, whitespace, tabs,
# newlines, and any control or shell-metacharacter, and rejects the bare
# `.`/`..` dot-runs outright (inert without a slash — the grammar bars `/` so a
# dot-run can never chain into a traversal — but a `.`/`..` handle would still
# misdirect a per-worker path, so refuse it), so a hostile field can neither
# escape a path nor tear the tab-delimited record. Bounded to 128 chars.
valid_field() {
  vf_v=$1
  case $vf_v in
    "" | . | .. | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#vf_v}" -le 128 ]
}

# The decision-text grammar for the free-text choice fields (question, default,
# options): non-empty, at most 512 bytes, and free of C0/DEL control bytes —
# which the sanitizer strips, so a value that changes under sanitize_printable
# carries a control byte (a tab, a newline, or an escape sequence) and is
# refused. This blocks record-tearing (tab/newline) and terminal injection while
# still admitting ordinary punctuation and UTF-8 text.
valid_text() {
  vt_v=$1
  [ -n "$vt_v" ] || return 1
  [ "${#vt_v}" -le 512 ] || return 1
  [ "$(sanitize_printable "$vt_v")" = "$vt_v" ]
}

# The states a heartbeat may set. awaiting-input is deliberately excluded: it is
# the ONE state that carries a structured decision, so it is set only by `decide`.
# idle / hung / ended are the hook-pushed liveness states (fleet-autonomy Task 2,
# D-1/REQ-A1.1, written by fleet-liveness.sh): status like the progress states,
# never queued.
valid_heartbeat_state() {
  case $1 in
    working | idle | hung | ended | pr-ready | merged | done) return 0 ;;
    *) return 1 ;;
  esac
}

valid_priority() {
  case $1 in
    high | normal | low) return 0 ;;
    *) return 1 ;;
  esac
}

# now_epoch — a validated numeric wall-clock second, or empty on a bad clock read
# (the caller decides whether that is fatal). `date +%s` is the same BSD/GNU
# extension fleet-state.sh relies on.
now_epoch() {
  ne_v=$(date +%s)
  case $ne_v in
    "" | *[!0-9]*) printf '' ;;
    *) printf '%s' "$ne_v" ;;
  esac
}

# --- the Task 9 advisory lock, consumed through fleet-state.sh's exposed
#     one-shot `lock`/`unlock` primitive (D-11). We spin the one-shot acquire so
#     an attention write is never dropped under contention, matching fleet-state
#     spin_acquire's bounded 20ms backoff. HOLD_LOCK gates release so we never
#     rmdir a lock we do not hold. On a fatal signal the trap releases AND exits
#     (below) rather than resuming the critical section unlocked.
HOLD_LOCK=0

release_lock() {
  if [ "$HOLD_LOCK" = 1 ]; then
    "$FS" unlock >/dev/null 2>&1 || true
    HOLD_LOCK=0
  fi
}
# The EXIT trap is the cleanup; the fatal-signal traps re-`exit` so the
# interrupted critical section does NOT resume with the lock released (a bare
# `trap release_lock INT TERM` would run the handler and then RETURN into the
# unfinished copy-filter-append-rename, unlocked — letting a concurrent writer
# acquire and clobber `state`, the exact lost update the lock prevents). The
# explicit `exit` re-enters the EXIT trap so release still runs, mirroring the
# sibling lock-holder scripts/tasks-pr-sync.sh. SIGKILL stays unrecoverable and
# falls to the stale-lock break.
trap 'release_lock' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

acquire_lock() {
  al_tries=0
  while [ "$al_tries" -lt 1000 ]; do
    "$FS" lock >/dev/null 2>&1
    al_rc=$?
    case $al_rc in
      0)
        HOLD_LOCK=1
        return 0
        ;;
      1) ;; # a live holder has it — retry
      *)
        echo "fleet-attention: cannot acquire the fleet lock (fleet-state exit $al_rc)" >&2
        return 2
        ;;
    esac
    al_tries=$((al_tries + 1))
    sleep 0.02
  done
  echo "fleet-attention: gave up acquiring the fleet lock after contention" >&2
  return 2
}

# resolve_home — the D-11 cross-spec home, via Task 9 (never re-derived here).
resolve_home() {
  rh_root=$("$FS" root) || return 2
  printf '%s' "$rh_root"
}

# upsert_row <worker> <scope> <state> <priority> <question> <default> <options>
# [<guard>] [<reason>] [<instance-id>]
# — replace <worker>'s row in the state store (or insert it), atomically, under
# the Task 9 lock. Copy-filter-append-rename so a concurrent reader sees only a
# complete store and the worker never appears twice (a state store, not a log).
# The record is assembled HERE, with the heartbeat timestamp stamped UNDER the
# lock (below), so this is the single authority for the record layout (the 8
# shipped fields plus the optional additive park reason at field 9).
# The optional <guard> `unless-awaiting` makes the upsert a clean no-op when
# the worker's CURRENT row is awaiting-input, with the check made inside this
# same critical section — the atomic escalation-preserve primitive the
# hook-push downgrade path needs (fleet-autonomy Task 2, REQ-A1.3): a lockless
# read-then-write guard would race a concurrent `decide` and silently
# auto-resolve a queued human decision.
upsert_row() {
  ur_worker=$1
  ur_scope=$2
  ur_state=$3
  ur_prio=$4
  ur_q=$5
  ur_def=$6
  ur_opts=$7
  ur_guard=${8:-}
  # ur_reason (field 9) is the fleet-hardening Task 2 additive extension (D-2):
  # the fork-park notification reason. It is APPENDED only when non-empty, so a
  # heartbeat / decide row stays byte-identical to the shipped 8-field layout —
  # an older 8-field reader ignores the trailing field, a newer reader reads it
  # (REQ-E1.2, additive-with-older-reader-ignores).
  ur_reason=${9:-}
  # ur_iid (field 10) is the fleet-hardening Task 4 additive extension (D-4): the
  # unique instance id an answerable fork record carries, so a late answer for a
  # resolved fork cannot mis-apply to a later fork whose labels collide. It is
  # APPENDED only when non-empty AND field 9 is set (a fork always stamps field 9
  # = `fork`), so the additive ladder stays monotonic — 8 shipped fields, +9 for
  # a park reason, +10 for a fork instance id. An older 8/9-field reader ignores
  # the trailing field (REQ-E1.2, additive-with-older-reader-ignores).
  ur_iid=${10:-}
  # Enforce the additive ladder as an invariant, not just a caller convention:
  # field 10 (the instance id) may only be written when field 9 (the reason) is
  # also set, so a malformed field-10-without-field-9 row can never be committed
  # (such a row would carry an empty field 9 and be misread as a decide/permission
  # row by the unless-decide guard). The only iid writer, `fork`, always stamps
  # field 9 = `fork`, so this never fires for real callers; it fails closed on a
  # future misuse of the primitive rather than tearing the ladder. No lock needed
  # (a pure argument check).
  if [ -n "$ur_iid" ] && [ -z "$ur_reason" ]; then
    echo "fleet-attention: internal error — an instance id (field 10) requires a reason (field 9); refusing to write a ladder-skipping row" >&2
    return 2
  fi
  acquire_lock || return 2
  if [ "$ur_guard" = unless-awaiting ] && [ -f "$store" ]; then
    # Fail SAFE if ANY matching row is awaiting-input, not just when the sole
    # row equals it: one row per worker is the store invariant, but external
    # corruption could leave several, and a naive single-string compare would
    # see a multi-line value, miss the awaiting-input row, and let this
    # downgrade clobber a queued human decision — the exact REQ-A1.3 violation
    # the guard exists to prevent. (Detecting the corruption itself is a
    # separate concern; see the store-corruption-detector observation.)
    ur_awk_rc=0
    ur_awaiting=$(awk -F "$TAB" -v w="$ur_worker" \
      '($1 "") == (w "") && $3 == "awaiting-input" { f = 1 } END { print (f ? "y" : "") }' "$store") \
      || ur_awk_rc=$?
    if [ "$ur_awk_rc" != 0 ]; then
      # The guard could not READ the store to check for a queued decision.
      # Fail closed, never open: proceeding would risk overwriting an
      # awaiting-input escalation on an unverifiable read — the exact clobber
      # this guard prevents. Surface it (the caller warns and the REQ-A1.8
      # reconcile re-derives), the same fail-closed posture classify takes on
      # an unreadable store (REQ-A1.3, REQ-A1.7).
      release_lock
      echo "fleet-attention: could not read the store to evaluate --unless-awaiting; refusing to risk clobbering a queued decision" >&2
      return 2
    fi
    if [ -n "$ur_awaiting" ]; then
      release_lock
      return 0
    fi
  fi
  if [ "$ur_guard" = unless-decide ] && [ -f "$store" ]; then
    # The fork-write guard (fleet-hardening Task 4): a `fork` must never clobber a
    # QUEUED HUMAN DECISION — a `decide`-family row (awaiting-input with an EMPTY
    # field 9: a pending permission or a flailing escalation). It CAN replace a
    # park (field 9 = `notification:*`, the coarse fork-park signal a structured
    # fork legitimately upgrades) and a prior fork (field 9 = `fork`, a re-fork),
    # both of which carry a NON-EMPTY field 9. Same multi-row-safe, fail-closed
    # read as the unless-awaiting guard; unlike park's downgrade no-op this REFUSES
    # (a fork over a queued decision is anomalous — the two states are mutually
    # exclusive by construction — so surface it rather than silently drop the
    # fork), keeping the harness permission gate the human's even if the store is
    # reached out of band. Returns 3 (a refusal, distinct from a 2 write/lock
    # error) so the caller can name it.
    ur_dec_rc=0
    ur_decide=$(awk -F "$TAB" -v w="$ur_worker" \
      '($1 "") == (w "") && $3 == "awaiting-input" && ($9 "") == "" { f = 1 } END { print (f ? "y" : "") }' "$store") \
      || ur_dec_rc=$?
    if [ "$ur_dec_rc" != 0 ]; then
      release_lock
      echo "fleet-attention: could not read the store to evaluate --unless-decide; refusing to risk clobbering a queued decision" >&2
      return 2
    fi
    if [ -n "$ur_decide" ]; then
      release_lock
      echo "fleet-attention: refusing to overwrite a queued human decision (a pending permission / flailing escalation) with a fork" >&2
      return 3
    fi
  fi
  # Stamp the heartbeat UNDER the lock, so the recorded time is COMMIT time, not
  # invocation time — byte-for-byte the discipline fleet-state.sh register uses
  # (scripts/fleet-state.sh, "stamp the record's time UNDER the lock"). Without
  # it, a writer that captured its timestamp early and then blocked on the lock
  # could commit an OLDER timestamp after a newer one under contention, which
  # both regresses the heartbeat (non-monotonic age / queue oldest-first order)
  # and, for the same worker, lets an earlier-captured write overwrite a
  # later-committed one (a lost update). On a bad clock read, release and fail.
  ur_ts=$(now_epoch)
  if [ -z "$ur_ts" ]; then
    release_lock
    echo "fleet-attention: could not read a numeric timestamp" >&2
    return 2
  fi
  ur_rc=0
  if ! mkdir -p "$attn_dir" 2>/dev/null; then
    echo "fleet-attention: cannot create the attention dir $attn_dir" >&2
    release_lock
    return 2
  fi
  ur_tmp=$(mktemp "$attn_dir/.state.XXXXXX") || {
    release_lock
    return 2
  }
  if [ -f "$store" ]; then
    # Force a STRING comparison: awk compares two numeric-looking operands
    # NUMERICALLY (strnum), and valid_field admits all-numeric handles, so a
    # bare `$1 != w` would treat `100` == `1e2` and `1` == `01` == `1.0` as
    # equal and drop the wrong worker's row (data loss). Concatenating "" pins
    # both operands to string type so only an exact-text match is filtered.
    awk -F "$TAB" -v w="$ur_worker" '($1 "") != (w "")' "$store" >"$ur_tmp" || ur_rc=2
  fi
  if [ "$ur_rc" = 0 ]; then
    if [ -n "$ur_iid" ]; then
      # A fork row carries the additive 10th field (the instance id), on top of
      # the 9th (reason = `fork`). fork is the only writer that sets field 10, and
      # it always sets field 9, so the ladder never skips a field.
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$ur_worker" "$ur_scope" "$ur_state" "$ur_ts" "$ur_prio" "$ur_q" "$ur_def" "$ur_opts" "$ur_reason" "$ur_iid" \
        >>"$ur_tmp" || ur_rc=2
    elif [ -n "$ur_reason" ]; then
      # A park row carries the additive 9th field (the notification reason).
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$ur_worker" "$ur_scope" "$ur_state" "$ur_ts" "$ur_prio" "$ur_q" "$ur_def" "$ur_opts" "$ur_reason" \
        >>"$ur_tmp" || ur_rc=2
    else
      # Every shipped writer (heartbeat, decide) — byte-identical 8-field layout.
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$ur_worker" "$ur_scope" "$ur_state" "$ur_ts" "$ur_prio" "$ur_q" "$ur_def" "$ur_opts" \
        >>"$ur_tmp" || ur_rc=2
    fi
  fi
  if [ "$ur_rc" = 0 ]; then
    mv -f "$ur_tmp" "$store" || ur_rc=2
  fi
  [ "$ur_rc" = 0 ] || rm -f "$ur_tmp" 2>/dev/null
  release_lock
  if [ "$ur_rc" != 0 ]; then
    echo "fleet-attention: failed to write the state store" >&2
  fi
  return "$ur_rc"
}

# suppressed — 0 when this call must defer to a backend's own attention surface.
suppressed() {
  [ "$surface_flag" = 1 ] && return 0
  case "${PLANWRIGHT_ATTENTION_SURFACE_PROVIDED:-}" in
    1 | true | yes) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# Command dispatch
# ---------------------------------------------------------------------------
cmd="${1:-}"
if [ -z "$cmd" ]; then
  echo "usage: fleet-attention.sh heartbeat|decide|fork|claim|park|clear|render|queue|notify [args]" >&2
  exit 2
fi
shift || true

[ -x "$FS" ] || {
  echo "fleet-attention: Task 9 dependency '$FS' is missing or not executable" >&2
  exit 2
}

case $cmd in
  heartbeat)
    worker="${1:-}"
    scope="${2:-}"
    state="${3:-}"
    guard="${4:-}"
    if [ -z "$worker" ] || [ -z "$scope" ] || [ -z "$state" ]; then
      echo "usage: fleet-attention.sh heartbeat <worker> <scope> <state> [--unless-awaiting]" >&2
      exit 2
    fi
    case $guard in
      "" | --unless-awaiting) ;;
      *)
        echo "usage: fleet-attention.sh heartbeat <worker> <scope> <state> [--unless-awaiting]" >&2
        exit 2
        ;;
    esac
    if ! valid_field "$worker"; then
      echo "fleet-attention: refusing malformed worker handle '$(sanitize_printable "$worker" "(unprintable worker)")'" >&2
      exit 2
    fi
    if ! valid_field "$scope"; then
      echo "fleet-attention: refusing malformed scope '$(sanitize_printable "$scope" "(unprintable scope)")'" >&2
      exit 2
    fi
    if ! valid_heartbeat_state "$state"; then
      echo "fleet-attention: refusing state '$(sanitize_printable "$state" "(unprintable state)")' (heartbeat states: working|idle|hung|ended|pr-ready|merged|done; awaiting-input needs 'decide')" >&2
      exit 2
    fi
    root=$(resolve_home) || exit 2
    attn_dir="$root/attention"
    store="$attn_dir/state"
    # A heartbeat carries no decision, so priority/question/default/options are
    # empty; upsert_row stamps the commit-time timestamp under the lock. The
    # optional --unless-awaiting guard is evaluated inside the lock (see
    # upsert_row): a no-op success when the current row is awaiting-input.
    if [ "$guard" = --unless-awaiting ]; then
      upsert_row "$worker" "$scope" "$state" "" "" "" "" unless-awaiting || exit 2
    else
      upsert_row "$worker" "$scope" "$state" "" "" "" "" || exit 2
    fi
    exit 0
    ;;

  decide)
    worker="${1:-}"
    scope="${2:-}"
    question="${3:-}"
    default="${4:-}"
    options="${5:-}"
    priority="${6:-normal}"
    if [ -z "$worker" ] || [ -z "$scope" ] || [ -z "$question" ] || [ -z "$default" ] || [ -z "$options" ]; then
      echo "usage: fleet-attention.sh decide <worker> <scope> <question> <default> <options> [priority]" >&2
      exit 2
    fi
    if ! valid_field "$worker"; then
      echo "fleet-attention: refusing malformed worker handle '$(sanitize_printable "$worker" "(unprintable worker)")'" >&2
      exit 2
    fi
    if ! valid_field "$scope"; then
      echo "fleet-attention: refusing malformed scope '$(sanitize_printable "$scope" "(unprintable scope)")'" >&2
      exit 2
    fi
    if ! valid_priority "$priority"; then
      echo "fleet-attention: refusing priority '$(sanitize_printable "$priority" "(unprintable priority)")' (high|normal|low)" >&2
      exit 2
    fi
    for _f in "$question" "$default" "$options"; do
      if ! valid_text "$_f"; then
        echo "fleet-attention: refusing a decision field with a control byte, an embedded tab/newline, or over-length text (would tear the record or drive the terminal)" >&2
        exit 2
      fi
    done
    root=$(resolve_home) || exit 2
    attn_dir="$root/attention"
    store="$attn_dir/state"
    # awaiting-input is the one decision-bearing state; upsert_row stamps the
    # commit-time timestamp under the lock.
    upsert_row "$worker" "$scope" "awaiting-input" "$priority" "$question" "$default" "$options" \
      || exit 2
    exit 0
    ;;

  park)
    # The fork-park attention push (fleet-hardening Task 2, D-2/REQ-A1.1): a
    # worker parks at a decision fork and pushes an `awaiting-human` record
    # carrying the notification reason and a commit-time timestamp, with NO pane
    # capture. The classifier resolves this row to `awaiting-human` DIRECTLY off
    # the stored awaiting-input state (never by heartbeat-age inference). Unlike
    # `decide`, park carries only the reason — never an option set: the
    # answerable, labeled option-set is the Task 4 decision channel. park never
    # auto-resolves a queued human decision: the --unless-awaiting guard makes it
    # an atomic no-op when the worker is ALREADY awaiting-input (a pending
    # permission or a flailing escalation), so a fork-park coincident with such a
    # decision preserves that decision instead of clobbering it (REQ-A1.3,
    # REQ-E1.2). The reason lands in the additive 9th field. Priority defaults to
    # `normal` (matching `decide`), so the decision queue renders a concrete
    # `[normal]` label rather than the `?` placeholder and sorts a fork-park level
    # with a routine decide (the empty-priority sort weight was already `normal`).
    worker="${1:-}"
    scope="${2:-}"
    reason="${3:-}"
    if [ -z "$worker" ] || [ -z "$scope" ] || [ -z "$reason" ]; then
      echo "usage: fleet-attention.sh park <worker> <scope> <reason>" >&2
      exit 2
    fi
    if ! valid_field "$worker"; then
      echo "fleet-attention: refusing malformed worker handle '$(sanitize_printable "$worker" "(unprintable worker)")'" >&2
      exit 2
    fi
    if ! valid_field "$scope"; then
      echo "fleet-attention: refusing malformed scope '$(sanitize_printable "$scope" "(unprintable scope)")'" >&2
      exit 2
    fi
    if ! valid_text "$reason"; then
      echo "fleet-attention: refusing a park reason with a control byte, an embedded tab/newline, or over-length text (would tear the record or drive the terminal)" >&2
      exit 2
    fi
    root=$(resolve_home) || exit 2
    attn_dir="$root/attention"
    store="$attn_dir/state"
    upsert_row "$worker" "$scope" "awaiting-input" "normal" "" "" "" unless-awaiting "$reason" \
      || exit 2
    exit 0
    ;;

  fork)
    # The answerable decision channel (fleet-hardening Task 4, D-4/REQ-A1.4): a
    # worker parked at a MULTI-OPTION fork records the pending decision, its full
    # labeled option set, its recommendation, and a UNIQUE instance id as a
    # structured store record — so the tower/human answers BY LABEL (immune to
    # menu reordering) and a late answer for a resolved fork cannot mis-apply to
    # a later fork whose labels collide (the instance id is the discriminator).
    # Field 9 is the fixed marker `fork`; the instance id is the additive 10th
    # field. Unlike `park` (Task 2, reason-only) this is deliberately NOT
    # --unless-awaiting: a fork is the worker's authoritative current decision,
    # written the same way `decide` writes (a plain upsert), so it establishes
    # the answerable record rather than deferring to a prior row.
    worker="${1:-}"
    scope="${2:-}"
    question="${3:-}"
    recommend="${4:-}"
    options="${5:-}"
    instance="${6:-}"
    priority="${7:-normal}"
    if [ -z "$worker" ] || [ -z "$scope" ] || [ -z "$question" ] \
      || [ -z "$recommend" ] || [ -z "$options" ] || [ -z "$instance" ]; then
      echo "usage: fleet-attention.sh fork <worker> <scope> <question> <recommend> <options> <instance-id> [priority]" >&2
      exit 2
    fi
    if ! valid_field "$worker"; then
      echo "fleet-attention: refusing malformed worker handle '$(sanitize_printable "$worker" "(unprintable worker)")'" >&2
      exit 2
    fi
    if ! valid_field "$scope"; then
      echo "fleet-attention: refusing malformed scope '$(sanitize_printable "$scope" "(unprintable scope)")'" >&2
      exit 2
    fi
    # The instance id shares the worker/scope handle grammar (no path separator,
    # whitespace, control byte, or tab/newline) so it can neither tear the record
    # nor be mistaken for a multi-field value on read-back.
    if ! valid_field "$instance"; then
      echo "fleet-attention: refusing malformed instance id '$(sanitize_printable "$instance" "(unprintable instance)")'" >&2
      exit 2
    fi
    if ! valid_priority "$priority"; then
      echo "fleet-attention: refusing priority '$(sanitize_printable "$priority" "(unprintable priority)")' (high|normal|low)" >&2
      exit 2
    fi
    for _f in "$question" "$recommend" "$options"; do
      if ! valid_text "$_f"; then
        echo "fleet-attention: refusing a decision field with a control byte, an embedded tab/newline, or over-length text (would tear the record or drive the terminal)" >&2
        exit 2
      fi
    done
    # The option set must carry at least two non-empty `|`-delimited labels (a
    # single-option "fork" is not a decision), and the recommendation must be one
    # of them — so answering by label always resolves to a real option and the
    # recommendation is never off-set. Pure awk, no eval, all input is data.
    # The free-text values pass through ENVIRON, NOT `-v`: awk processes backslash
    # escapes in a `-v` value (a label `x\ty` would become `x<TAB>y`), which would
    # both misjudge membership and, on the claim write below, tear the record.
    # ENVIRON is not escape-processed, so the values compare and store verbatim.
    # Comparisons are STRING-forced (`(x "") == (y "")`): awk compares two
    # numeric-looking operands NUMERICALLY (strnum), and both the split labels and
    # the ENVIRON recommendation carry that attribute, so a bare `==` would treat
    # labels `1` and `01` (or `1.0`, `1e0`) as equal — accepting an off-set
    # recommendation and, at claim time, resolving the wrong option. `seen`
    # (a real string-keyed array) counts DISTINCT non-empty labels and rejects an
    # exact-duplicate label, so `a|a` is not miscounted as a two-option decision.
    opt_check=$(FA_OPTS="$options" FA_REC="$recommend" awk '
      BEGIN {
        n = split(ENVIRON["FA_OPTS"], a, "|")
        rec = ENVIRON["FA_REC"]
        cnt = 0; recfound = 0; empty = 0; dup = 0
        for (i = 1; i <= n; i++) {
          if (a[i] == "") { empty = 1; continue }
          if (a[i] in seen) { dup = 1 } else { seen[a[i]] = 1; cnt++ }
          if ((a[i] "") == (rec "")) recfound = 1
        }
        if (empty) { print "empty"; exit }
        if (dup) { print "dup"; exit }
        if (cnt < 2) { print "toofew"; exit }
        if (!recfound) { print "norec"; exit }
        print "ok"
      }')
    case $opt_check in
      ok) ;;
      empty)
        echo "fleet-attention: refusing a fork option set with an empty label ('|'-delimited, each label non-empty)" >&2
        exit 2
        ;;
      dup)
        echo "fleet-attention: refusing a fork option set with a duplicate label (each label must be distinct so an answer resolves unambiguously)" >&2
        exit 2
        ;;
      toofew)
        echo "fleet-attention: refusing a fork with fewer than two distinct labels (a single-option fork is not a decision)" >&2
        exit 2
        ;;
      norec)
        echo "fleet-attention: refusing a fork whose recommendation '$(sanitize_printable "$recommend" "(unprintable)")' is not one of the option labels" >&2
        exit 2
        ;;
      *)
        echo "fleet-attention: could not validate the fork option set" >&2
        exit 2
        ;;
    esac
    root=$(resolve_home) || exit 2
    attn_dir="$root/attention"
    store="$attn_dir/state"
    # awaiting-input with the fork marker (field 9) and the instance id (field
    # 10); the recommendation rides the `default` slot (field 7) and the labeled
    # option set the `options` slot (field 8). upsert_row stamps the commit-time
    # timestamp under the lock. The `unless-decide` guard makes the write refuse
    # (return 3) rather than clobber a queued human decision (a pending permission
    # / flailing escalation); it still replaces a park (upgrade) or a prior fork
    # (re-fork).
    fork_rc=0
    upsert_row "$worker" "$scope" "awaiting-input" "$priority" "$question" "$recommend" "$options" unless-decide "fork" "$instance" \
      || fork_rc=$?
    [ "$fork_rc" = 0 ] || exit "$fork_rc"
    exit 0
    ;;

  claim)
    # Answer an answerable fork BY LABEL, atomically (fleet-hardening Task 4,
    # D-4/REQ-A1.4). All validation AND the first-answer-wins close happen inside
    # ONE critical section so two answerers can never both close a fork: the
    # winning label is stamped into the additive 11th field, and a second claim
    # (already-claimed) is a refused no-op. The refusals are mechanical (pure
    # awk, no model call): a stale instance id, a label outside the option set,
    # an already-claimed record, and — keeping the harness permission gate the
    # human's — any record whose reason is a permission-park (never a `fork`).
    worker="${1:-}"
    instance="${2:-}"
    label="${3:-}"
    if [ -z "$worker" ] || [ -z "$instance" ] || [ -z "$label" ]; then
      echo "usage: fleet-attention.sh claim <worker> <instance-id> <label>" >&2
      exit 2
    fi
    if ! valid_field "$worker"; then
      echo "fleet-attention: refusing malformed worker handle '$(sanitize_printable "$worker" "(unprintable worker)")'" >&2
      exit 2
    fi
    if ! valid_field "$instance"; then
      echo "fleet-attention: refusing malformed instance id '$(sanitize_printable "$instance" "(unprintable instance)")'" >&2
      exit 2
    fi
    if ! valid_text "$label"; then
      echo "fleet-attention: refusing a label with a control byte, an embedded tab/newline, or over-length text" >&2
      exit 2
    fi
    root=$(resolve_home) || exit 2
    attn_dir="$root/attention"
    store="$attn_dir/state"
    acquire_lock || exit 2
    if [ ! -f "$store" ]; then
      release_lock
      echo "fleet-attention: no answerable fork for worker '$(sanitize_printable "$worker" "(unprintable worker)")'" >&2
      exit 3
    fi
    # Validation pass: locate the worker's row and decide the outcome. `matched`
    # is the exact option label the answer resolves to (by label, not position),
    # empty on any refusal; the code names the refusal for the diagnostic. The
    # claimed-label field (11) is captured in the matched block because $11 is not
    # addressable in END. String-forced comparisons (see upsert_row) so numeric
    # -looking handles/ids never numerically alias.
    # w and iid ride `-v` (their valid_field grammar excludes backslash, so no
    # escape processing can alter them); the free-text label rides ENVIRON so a
    # backslash in a label neither misjudges membership nor is escape-mangled.
    cl_verdict=$(FA_LBL="$label" awk -F "$TAB" -v w="$worker" -v iid="$instance" '
      ($1 "") == (w "") {
        found = 1; st = $3; f9 = ($9 ""); f10 = ($10 ""); opts = $8
        cl = (NF >= 11 ? ($11 "") : "")
      }
      END {
        lbl = ENVIRON["FA_LBL"]
        if (!found || st != "awaiting-input") { print "REFUSE\tno-fork\t"; exit }
        if (f9 ~ /^permission/) { print "REFUSE\tpermission\t"; exit }
        if (f9 != "fork") { print "REFUSE\tno-fork\t"; exit }
        if (f10 != (iid "")) { print "REFUSE\tstale\t"; exit }
        if (cl != "") { print "REFUSE\tclaimed\t"; exit }
        n = split(opts, a, "|"); matched = ""
        # String-force (see fork opt_check): a bare `a[i] == lbl` compares numeric
        # -looking labels numerically, so `01` would match option `1` (a label
        # outside the set answered as if inside it, or the wrong option resolved).
        for (i = 1; i <= n; i++) if ((a[i] "") == (lbl "")) matched = a[i]
        if (matched == "") { print "REFUSE\tbad-label\t"; exit }
        print "OK\t\t" matched
      }' "$store") || {
      # An OPERATIONAL failure (the store exists but could not be read), not a
      # semantic refusal: exit 2, matching upsert_row/clear's fs/lock/read/write
      # convention, so a caller (fleet-decision.sh) distinguishes "store I/O
      # broke, nothing consumed, retry may help" (2) from "the answer does not
      # apply" (3). A genuinely ABSENT store is the separate exit-3 no-fork case
      # above (no rows means no answerable fork, a real refusal).
      release_lock
      echo "fleet-attention: could not read the store to evaluate the claim" >&2
      exit 2
    }
    # Split the three tab-delimited verdict fields with pure PARAMETER EXPANSION,
    # not `printf | awk` — the parse needs no store access, so keeping subprocesses
    # (three awk + three printf) out of the held critical section shrinks lock hold
    # time under high-frequency answering. An IFS=TAB `read` is unusable here: TAB
    # is IFS-whitespace, so it would collapse the empty middle field of the OK
    # verdict (`OK<TAB><TAB>label`); `%%`/`#` expansion preserves empty fields.
    cl_status=${cl_verdict%%"$TAB"*}
    cl_rest=${cl_verdict#*"$TAB"}
    cl_code=${cl_rest%%"$TAB"*}
    cl_matched=${cl_rest#*"$TAB"}
    if [ "$cl_status" != OK ]; then
      release_lock
      case $cl_code in
        permission)
          echo "fleet-attention: refusing to answer a permission-park record — the harness permission gate stays the human's" >&2
          ;;
        stale)
          echo "fleet-attention: refusing a stale answer (instance id does not match the current fork)" >&2
          ;;
        claimed)
          echo "fleet-attention: fork already answered (first-answer-wins); this answer is a no-op" >&2
          ;;
        bad-label)
          echo "fleet-attention: refusing an answer whose label is not in the fork's option set" >&2
          ;;
        *)
          echo "fleet-attention: no answerable fork with that instance id for the worker" >&2
          ;;
      esac
      exit 3
    fi
    # Close pass: stamp the winning label into field 11 for the worker's row
    # only, every other row byte-identical. Copy-filter-rename so a reader never
    # sees a torn store (the clear/upsert discipline). These are all OPERATIONAL
    # failures AFTER a successful validation (mktemp / awk write / mv) — exit 2,
    # the script's fs/lock/write convention, never the semantic-refusal 3.
    cl_tmp=$(mktemp "$attn_dir/.state.XXXXXX") || {
      release_lock
      exit 2
    }
    cl_rc=0
    # The winning label rides ENVIRON (not `-v`): it is written verbatim into
    # field 11, so escape processing must not alter it (an unescaped `-v` value
    # could inject a tab and tear the record).
    FA_LBL="$cl_matched" awk -F "$TAB" -v OFS="$TAB" -v w="$worker" '
      ($1 "") == (w "") { $11 = ENVIRON["FA_LBL"]; NF = 11; print; next }
      { print }
    ' "$store" >"$cl_tmp" || cl_rc=2
    if [ "$cl_rc" = 0 ]; then
      mv -f "$cl_tmp" "$store" || cl_rc=2
    fi
    [ "$cl_rc" = 0 ] || rm -f "$cl_tmp" 2>/dev/null
    release_lock
    if [ "$cl_rc" != 0 ]; then
      echo "fleet-attention: failed to record the claim (store write failed)" >&2
      exit "$cl_rc"
    fi
    # Print the canonical matched label (the exact option), so the caller relays
    # the label the record actually carries, not the raw argument spelling.
    printf '%s\n' "$cl_matched"
    exit 0
    ;;

  clear)
    worker="${1:-}"
    if [ -z "$worker" ]; then
      echo "usage: fleet-attention.sh clear <worker>" >&2
      exit 2
    fi
    if ! valid_field "$worker"; then
      echo "fleet-attention: refusing malformed worker handle '$(sanitize_printable "$worker" "(unprintable worker)")'" >&2
      exit 2
    fi
    root=$(resolve_home) || exit 2
    attn_dir="$root/attention"
    store="$attn_dir/state"
    # Absent store → nothing to clear (idempotent), no lock, no home creation.
    [ -f "$store" ] || exit 0
    acquire_lock || exit 2
    clr_rc=0
    clr_tmp=$(mktemp "$attn_dir/.state.XXXXXX") || {
      release_lock
      exit 2
    }
    # String comparison (see upsert_row): a bare `$1 != w` would numerically
    # equate all-numeric handles (`1` == `01` == `1.0`) and clear the wrong row.
    awk -F "$TAB" -v w="$worker" '($1 "") != (w "")' "$store" >"$clr_tmp" || clr_rc=2
    if [ "$clr_rc" = 0 ]; then
      mv -f "$clr_tmp" "$store" || clr_rc=2
    fi
    [ "$clr_rc" = 0 ] || rm -f "$clr_tmp" 2>/dev/null
    release_lock
    exit "$clr_rc"
    ;;

  render)
    # `--surface-provided` is accepted as a recognized no-op so a caller can pass
    # the advertised set uniformly to both render and queue. It does NOT suppress
    # render: the backend-capability contract scopes provides_attention_surface
    # deferral to the DECISION QUEUE only (the actionable surface), never the
    # status view — planwright's per-worker status is always available. Only
    # `queue` honors the signal.
    for _a in "$@"; do
      case $_a in
        --surface-provided) ;;
        *)
          echo "fleet-attention: render: unknown flag '$(sanitize_printable "$_a" "(unprintable flag)")'" >&2
          exit 2
          ;;
      esac
    done
    root=$(resolve_home) || exit 2
    store="$root/attention/state"
    [ -f "$store" ] || exit 0
    now=$(now_epoch)
    # A trailing record without a newline is still emitted (|| [ -n "$w" ]).
    while IFS="$TAB" read -r w scope state ts _prio _q _def _opts || [ -n "$w" ]; do
      [ -n "$w" ] || continue
      age="?"
      case $ts in
        "" | *[!0-9]* | 0?*) ;; # 0?* excludes a leading-zero ts: `$(( ))` would
        # read it as OCTAL — `010` miscounts (age = now-8) and `08`/`09` are an
        # invalid-octal error, FATAL under dash. Mirrors fleet-state.sh
        # read_counter / orchestrate-meta-select.sh read_bound; a corrupt ts
        # degrades to the "?" age below, never a wrong number or an abort.
        *) [ -n "$now" ] && age=$((now - ts)) ;;
      esac
      # Sanitize every field before it reaches the terminal (echo discipline):
      # a hand-corrupted store line cannot drive the terminal or corrupt a log.
      s_state=$(sanitize_printable "$state" "?")
      s_scope=$(sanitize_printable "$scope" "?")
      s_worker=$(sanitize_printable "$w" "?")
      printf '[%s] %s  %s  (%ss)\n' "$s_state" "$s_scope" "$s_worker" "$age"
    done <"$store"
    exit 0
    ;;

  queue)
    surface_flag=0
    count_only=0
    for _a in "$@"; do
      case $_a in
        --surface-provided) surface_flag=1 ;;
        --count) count_only=1 ;;
        *)
          echo "fleet-attention: queue: unknown flag '$(sanitize_printable "$_a" "(unprintable flag)")'" >&2
          exit 2
          ;;
      esac
    done
    if suppressed; then
      echo "fleet-attention: a backend advertises provides_attention_surface; deferring the decision queue to it (planwright renders nothing)" >&2
      exit 0
    fi
    root=$(resolve_home) || exit 2
    store="$root/attention/state"
    # Actionable items only (awaiting-input); non-actionable signal suppressed.
    # Prefix each with a sort key: a priority weight (high<normal<low) and the
    # heartbeat timestamp, so the sort is priority-desc then oldest-waiting-first
    # (alarm rationalization). The worker handle (field 3 of the prefixed line,
    # the first field of $0) is a tertiary key so two decisions committed within
    # the same wall-clock second still order deterministically rather than by
    # sort's unspecified tie behavior. No store → no actionable items.
    sortable=""
    if [ -f "$store" ]; then
      sortable=$(awk -F "$TAB" '
        $3 == "awaiting-input" {
          w = ($5 == "high") ? 0 : ($5 == "low") ? 2 : 1
          print w "\t" $4 "\t" $0
        }
      ' "$store" | sort -t "$TAB" -k1,1n -k2,2n -k3,3)
    fi
    # Item count = the queue length that tracks the `## Awaiting input` count.
    if [ -z "$sortable" ]; then
      n=0
    else
      n=$(printf '%s\n' "$sortable" | grep -c .)
    fi
    if [ "$count_only" = 1 ]; then
      printf '%s\n' "$n"
      exit 0
    fi
    [ "$n" = 0 ] && exit 0
    now=$(now_epoch)
    # Sorted lines carry the two sort-key fields ahead of the stored fields. The
    # trailing vars read the additive fields: `reason` the 9th (fleet-hardening
    # Task 2 park / Task 4 fork marker), `iid` the 10th and `claimed` the 11th
    # (Task 4 fork). They are empty for a shipped decide row (8 fields → the vars
    # read nothing, so the decide branch below is byte-identical to before),
    # carry the reason for a park row (9 fields), and carry the instance id and
    # (once answered) the claimed label for a fork row (10/11 fields).
    # US-delimit the read. TAB is IFS-whitespace, so `read` collapses a run of
    # consecutive empty fields (a park row carries empty prio/q/def/opts with
    # only field 9 set) and would slide the reason into the priority slot,
    # dropping the fork-park `reason:` branch entirely. Translating the sort's
    # TAB delimiters to the US control byte (never a valid field byte) makes each
    # empty field survive the split — the fleet-attention-watch.sh do_pass idiom.
    us=$(printf '\037')
    printf '%s\n' "$sortable" | tr "$TAB" "$us" | while IFS="$us" read -r _w _tskey worker scope _state ts prio q def opts reason iid claimed; do
      [ -n "$worker" ] || continue
      age="?"
      case $ts in
        "" | *[!0-9]* | 0?*) ;; # 0?* excludes a leading-zero ts: `$(( ))` would
        # read it as OCTAL — `010` miscounts (age = now-8) and `08`/`09` are an
        # invalid-octal error, FATAL under dash. Mirrors fleet-state.sh
        # read_counter / orchestrate-meta-select.sh read_bound; a corrupt ts
        # degrades to the "?" age below, never a wrong number or an abort.
        *) [ -n "$now" ] && age=$((now - ts)) ;;
      esac
      s_prio=$(sanitize_printable "$prio" "?")
      s_scope=$(sanitize_printable "$scope" "?")
      s_worker=$(sanitize_printable "$worker" "?")
      printf -- '- [%s] %s  (%s, waiting %ss)\n' "$s_prio" "$s_scope" "$s_worker" "$age"
      if [ "$reason" = fork ] && [ -n "$iid" ]; then
        # An answerable fork (Task 4, D-4): a structured decision the tower/human
        # answers BY LABEL. The `[ -n "$iid" ]` guard disambiguates from a park
        # whose free-text reason happens to be the literal `fork` (field 10 empty),
        # so only a genuine fork record (a non-empty instance id) renders here.
        # Surface the question, the recommendation (the `default` slot), the full
        # labeled option set, and the instance id the answer must match; once
        # answered, the claimed label (first-answer-wins).
        s_q=$(sanitize_printable "$q" "?")
        s_def=$(sanitize_printable "$def" "?")
        s_opts=$(sanitize_printable "$opts" "?")
        s_iid=$(sanitize_printable "$iid" "?")
        printf '    Q: %s\n' "$s_q"
        printf '    recommend: %s\n' "$s_def"
        printf '    options: %s\n' "$s_opts"
        printf '    instance: %s\n' "$s_iid"
        if [ -n "$claimed" ]; then
          s_claimed=$(sanitize_printable "$claimed" "?")
          printf '    answered: %s\n' "$s_claimed"
        fi
      elif [ -n "$reason" ]; then
        # A fork-park (Task 2): it carries the notification reason, not a labeled
        # option set. Surface the reason so the tower distinguishes a fork-park
        # from a permission / flailing decide.
        s_reason=$(sanitize_printable "$reason" "?")
        printf '    reason: %s\n' "$s_reason"
      else
        s_q=$(sanitize_printable "$q" "?")
        s_def=$(sanitize_printable "$def" "?")
        s_opts=$(sanitize_printable "$opts" "?")
        printf '    Q: %s\n' "$s_q"
        printf '    default: %s\n' "$s_def"
        printf '    options: %s\n' "$s_opts"
      fi
    done
    exit 0
    ;;

  notify)
    summary="${1:-}"
    if [ -z "$summary" ]; then
      echo "usage: fleet-attention.sh notify <summary>" >&2
      exit 2
    fi
    [ -x "$RNC" ] || {
      echo "fleet-attention: notify: channel resolver '$RNC' is missing or not executable" >&2
      exit 2
    }
    channel=$("$RNC")
    nrc=$?
    if [ "$nrc" -ne 0 ]; then
      # A broken/hard-failed channel config: fail closed rather than guess a
      # channel. The resolver already diagnosed on stderr.
      echo "fleet-attention: notify: could not resolve the notification channel (resolver exit $nrc)" >&2
      exit "$nrc"
    fi
    # Sanitize the summary to a single control-free line before it reaches any
    # channel adapter (echo discipline + no record tearing).
    summary=$(sanitize_printable "$summary" "(empty)")
    case $channel in
      none)
        # Pull-only: nothing is pushed. The operator reads `queue` on demand.
        exit 0
        ;;
      statusline)
        # The native Claude Code statusLine surface (fleet-autonomy Task 8,
        # D-14) is PULL-shaped: Claude Code invokes scripts/fleet-statusline.sh
        # on its own schedule and that command renders the current derived stats
        # (scripts/fleet-stats.sh line). There is nothing to PUSH on an event, so
        # `notify` is a clean no-op for this channel — the operator sees the
        # stats via the status line, not a pushed message. (A no-op, not the
        # unreachable `*)` fail-closed below, because this IS a recognized
        # channel.)
        exit 0
        ;;
      editor-toast)
        # Drop a timestamped line to a file the editor tails. Serialize the
        # append through the Task 9 lock so concurrent notifies never interleave.
        root=$(resolve_home) || exit 2
        attn_dir="$root/attention"
        toasts="$attn_dir/toasts"
        acquire_lock || exit 2
        nt_rc=0
        if ! mkdir -p "$attn_dir" 2>/dev/null; then
          nt_rc=2
        fi
        if [ "$nt_rc" = 0 ]; then
          ts=$(now_epoch)
          [ -n "$ts" ] || ts=0
          printf '%s\t%s\n' "$ts" "$summary" >>"$toasts" || nt_rc=2
        fi
        release_lock
        [ "$nt_rc" = 0 ] || echo "fleet-attention: notify: failed to write the editor-toast file" >&2
        exit "$nt_rc"
        ;;
      tmux-popup)
        # tmux display-message interprets `#{...}`/`#(...)` FORMAT specifiers,
        # and `#(cmd)` runs a shell command — so untrusted text must never reach
        # it as a format. Neutralize by stripping `#` before the push. Best
        # effort: with no attached server the item still lives in the queue.
        if command -v tmux >/dev/null 2>&1 && [ -n "${TMUX:-}" ]; then
          tmux_msg=$(printf '%s' "$summary" | tr -d '#')
          tmux display-message -- "$tmux_msg" 2>/dev/null || true
        else
          echo "fleet-attention: notify: tmux-popup channel selected but no attached tmux server; the item remains in the decision queue" >&2
        fi
        exit 0
        ;;
      os-notify)
        # Pass the summary as ARGV data, never interpolated into a script string
        # (no AppleScript-string / shell injection). Best effort per platform.
        if command -v notify-send >/dev/null 2>&1; then
          notify-send -- "$summary" 2>/dev/null || true
        elif command -v osascript >/dev/null 2>&1; then
          osascript -e 'on run argv' -e 'display notification (item 1 of argv)' \
            -e 'end run' -- "$summary" >/dev/null 2>&1 || true
        else
          echo "fleet-attention: notify: os-notify channel selected but neither notify-send nor osascript is present; the item remains in the decision queue" >&2
        fi
        exit 0
        ;;
      *)
        # resolve-notification-channel.sh only ever prints a validated enum, so
        # this is unreachable in practice; fail closed rather than silently drop.
        echo "fleet-attention: notify: resolver returned an unrecognized channel '$(sanitize_printable "$channel" "(unprintable channel)")'" >&2
        exit 2
        ;;
    esac
    ;;

  *)
    echo "fleet-attention: unknown command '$(sanitize_printable "$cmd" "(unprintable command)")' (heartbeat|decide|fork|claim|park|clear|render|queue|notify)" >&2
    exit 2
    ;;
esac
