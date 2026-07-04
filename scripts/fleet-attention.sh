#!/bin/sh
# fleet-attention.sh — the substrate-agnostic ATTENTION/NOTIFICATION capability,
# lifted into core paralleling the execution capability (orchestration-fleet
# Task 12; D-13, REQ-E1.3, REQ-E1.4, REQ-A1.6). It gives every persona a legible
# default surface without any dotfiles-local mechanism, so a marketplace-install
# user gets it from core.
#
# WHAT IT PROVIDES (D-13):
#   (a) HEARTBEAT/AWARENESS STATE — a per-worker current-state store keyed by
#       worker handle: scope (spec + unit), state (working / awaiting-input /
#       pr-ready / merged / done), a commit-time heartbeat, and — for an
#       awaiting-input worker — the structured decision it is blocked on.
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
#       os-notify / editor-toast) is the overlay VALUE (resolve-notification-
#       channel.sh); this script is the seam that dispatches through it.
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
#   fleet-attention.sh heartbeat <worker> <scope> <state>
#       Upsert the worker's current state (one row per worker, last wins).
#       <state> ∈ working | pr-ready | merged | done. awaiting-input needs a
#       structured decision — use `decide`.
#   fleet-attention.sh decide <worker> <scope> <question> <default> <options> [priority]
#       Upsert the worker as awaiting-input WITH a structured decision.
#       [priority] ∈ high | normal | low (default normal).
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
#   input, or a filesystem/lock error (fail closed); other non-zero from a
#   propagated resolver hard-fail (notify).
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
# fleet-state.sh valid_field: excludes path separators (a `.`/`..` dot-run is
# inert without a slash), whitespace, tabs, newlines, and any control or
# shell-metacharacter, so a hostile field can neither escape a path nor tear the
# tab-delimited record. Bounded to 128 chars.
valid_field() {
  vf_v=$1
  case $vf_v in
    "" | *[!A-Za-z0-9._=@:-]*) return 1 ;;
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
valid_heartbeat_state() {
  case $1 in
    working | pr-ready | merged | done) return 0 ;;
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
# — replace <worker>'s row in the state store (or insert it), atomically, under
# the Task 9 lock. Copy-filter-append-rename so a concurrent reader sees only a
# complete store and the worker never appears twice (a state store, not a log).
# The record is assembled HERE, with the heartbeat timestamp stamped UNDER the
# lock (below), so this is the single authority for the 8-field record layout.
upsert_row() {
  ur_worker=$1
  ur_scope=$2
  ur_state=$3
  ur_prio=$4
  ur_q=$5
  ur_def=$6
  ur_opts=$7
  acquire_lock || return 2
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
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$ur_worker" "$ur_scope" "$ur_state" "$ur_ts" "$ur_prio" "$ur_q" "$ur_def" "$ur_opts" \
      >>"$ur_tmp" || ur_rc=2
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
  echo "usage: fleet-attention.sh heartbeat|decide|clear|render|queue|notify [args]" >&2
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
    if [ -z "$worker" ] || [ -z "$scope" ] || [ -z "$state" ]; then
      echo "usage: fleet-attention.sh heartbeat <worker> <scope> <state>" >&2
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
    if ! valid_heartbeat_state "$state"; then
      echo "fleet-attention: refusing state '$(sanitize_printable "$state" "(unprintable state)")' (heartbeat states: working|pr-ready|merged|done; awaiting-input needs 'decide')" >&2
      exit 2
    fi
    root=$(resolve_home) || exit 2
    attn_dir="$root/attention"
    store="$attn_dir/state"
    # A heartbeat carries no decision, so priority/question/default/options are
    # empty; upsert_row stamps the commit-time timestamp under the lock.
    upsert_row "$worker" "$scope" "$state" "" "" "" "" || exit 2
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
    # Sorted lines carry the two sort-key fields ahead of the 8 stored fields.
    printf '%s\n' "$sortable" | while IFS="$TAB" read -r _w _tskey worker scope _state ts prio q def opts; do
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
      s_q=$(sanitize_printable "$q" "?")
      s_def=$(sanitize_printable "$def" "?")
      s_opts=$(sanitize_printable "$opts" "?")
      printf -- '- [%s] %s  (%s, waiting %ss)\n' "$s_prio" "$s_scope" "$s_worker" "$age"
      printf '    Q: %s\n' "$s_q"
      printf '    default: %s\n' "$s_def"
      printf '    options: %s\n' "$s_opts"
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
    echo "fleet-attention: unknown command '$(sanitize_printable "$cmd" "(unprintable command)")' (heartbeat|decide|clear|render|queue|notify)" >&2
    exit 2
    ;;
esac
