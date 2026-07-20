#!/bin/sh
# fleet-attention-watch.sh — the tower-side attention-store EVENT WATCH
# (fleet-hardening Task 2: D-2; REQ-A1.2, REQ-E1.3).
#
# The tower learns a worker parked for a human by WATCHING fleet-autonomy's
# attention store as an event — NEVER by capturing and grep-parsing the worker's
# pane (the mechanism that false-negatived for seven hours). This script is the
# event reaction plus its two safety rails:
#
#   * CHANGE DETECTION (`pass`). One pass reads the store, and for each
#     awaiting-human row (a stored awaiting-input state — a fork-park, a pending
#     permission, or a flailing escalation) that is NEW or CHANGED since the last
#     pass, emits it and fires the on-change callback. This is the low-latency
#     event reaction: driven by a filesystem watcher (fswatch / inotifywait) in
#     the `watch` loop, it fires the instant the store is written, not on a poll.
#
#   * RECONCILE SWEEP (`reconcile`). A full-store pass that fires for EVERY
#     current awaiting-human row regardless of the change signature — the
#     backstop for a push written before the watch was established, or a dead
#     watcher. It bounds the worst case to poll-latency, never the silent
#     blindness this mechanism exists to end (the push-first / reconcile pattern
#     fleet-autonomy D-1 establishes).
#
#   * LIVENESS (`liveness`). Each pass / reconcile stamps a liveness marker; a
#     supervisor (or the tower watchdog) checks it, so a dead watch is itself
#     detectable — a store row aging toward `hung` is the watcher-down tell.
#
# The callback receives `<worker> <scope> <reason>` per row (the reason is the
# fork-park notification reason, empty for a permission / flailing decide) so the
# tower can distinguish a fork-park from the other awaiting-human causes. The
# callback is an operator-supplied command invoked with positional args (never
# eval'd); store fields were grammar-validated on write and are re-sanitized for
# stdout (the echo discipline).
#
# No LLM (REQ-E1.3), no jq (REQ-K1.5), no capture-pane (REQ-A1.2): pure awk / sh
# reading the store file under the cross-spec fleet home (fleet-state.sh). POSIX
# sh on the bash-3.2 / BSD bar; pathname expansion disabled (set -f).
#
# Usage:
#   fleet-attention-watch.sh pass [--on-change <cmd>]
#       One change-detection pass: emit + fire the callback for each NEW/CHANGED
#       awaiting-human row; update the change signature; stamp liveness.
#   fleet-attention-watch.sh reconcile [--on-change <cmd>]
#       Full sweep: emit + fire for EVERY current awaiting-human row regardless
#       of the signature (the backstop); reset the signature; stamp liveness.
#   fleet-attention-watch.sh watch [--on-change <cmd>] [--interval <secs>]
#       [--reconcile-every <n>] [--once]
#       The loop: block on fswatch / inotifywait when available (event), else
#       poll every <secs> (degrade to poll-latency); each wake runs a pass, every
#       <n> wakes a reconcile. --once runs a single pass and returns (cron/test).
#   fleet-attention-watch.sh liveness [--max-age <secs>]
#       Exit 0 if a pass stamped liveness within <secs> (default 900), else 1 —
#       the dead-watch / never-started tell.
#
# Exit codes: 0 success; 2 usage / a filesystem error (fail closed).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FS="$script_dir/fleet-state.sh"
TAB=$(printf '\t')

now_epoch() {
  ne_v=$(date +%s)
  case $ne_v in
    "" | *[!0-9]*) printf '' ;;
    *) printf '%s' "$ne_v" ;;
  esac
}

# valid_posint <value> — a positive integer CLI option value: digits only, no
# leading zero (shell arithmetic would read it as octal), 1..15 digits (the
# overflow guard the sibling resolvers use), and not bare 0 (a 0 interval /
# max-age / reconcile-every is meaningless). An invalid option value is a usage
# error (exit 2 at the call site), never a silent fall-back to the default — the
# same discipline fleet-liveness.sh classify applies to --now / --heartbeat, so a
# misconfigured watch fails loudly instead of running an unintended cadence.
valid_posint() {
  case $1 in
    "" | *[!0-9]* | 0 | 0?*) return 1 ;;
  esac
  [ "${#1}" -le 15 ]
}

# atomic_write_file <file> <content> — same-dir temp + rename (never a truncating
# `>` redirect, which would follow a planted symlink).
atomic_write_file() {
  awf_file=$1
  awf_val=$2
  awf_dir=$(dirname "$awf_file")
  awf_tmp=$(mktemp "$awf_dir/.tmp.XXXXXX") || return 1
  if ! printf '%s' "$awf_val" >"$awf_tmp"; then
    rm -f "$awf_tmp"
    return 1
  fi
  if ! mv -f "$awf_tmp" "$awf_file"; then
    rm -f "$awf_tmp"
    return 1
  fi
  return 0
}

# resolve the store paths under the cross-spec fleet home.
resolve_paths() {
  rp_root=$("$FS" root) || return 2
  attn_dir="$rp_root/attention"
  store="$attn_dir/state"
  sigfile="$attn_dir/watch.sig"
  alivefile="$attn_dir/watch.alive"
  return 0
}

stamp_liveness() {
  mkdir -p "$attn_dir" 2>/dev/null || return 1
  sl_now=$(now_epoch)
  [ -n "$sl_now" ] || return 1
  atomic_write_file "$alivefile" "$sl_now"
}

# emit_and_fire <worker> <scope> <reason> — one awaiting-human row's reaction:
# emit a sanitized line to stdout and (if set) invoke the callback with the
# positional fields (never eval'd).
emit_and_fire() {
  eaf_w=$(sanitize_printable "$1" "?")
  eaf_s=$(sanitize_printable "$2" "?")
  eaf_r=$(sanitize_printable "$3" "")
  printf '%s\t%s\t%s\n' "$eaf_w" "$eaf_s" "$eaf_r"
  if [ -n "$on_change" ]; then
    "$on_change" "$1" "$2" "$3" || true
  fi
}

# read_store_guard — fail CLOSED if the store exists but is unreadable (a blind
# watch reporting nothing looks identical to a quiet fleet — never report health
# from lost observability, the classifier's REQ-A1.7 posture).
read_store_guard() {
  if [ -f "$store" ] && [ ! -r "$store" ]; then
    echo "fleet-attention-watch: attention store exists but is unreadable — refusing to watch blind" >&2
    return 2
  fi
  return 0
}

# do_pass <all> — emit awaiting-human rows. <all>=1 (reconcile) fires every row;
# <all>=0 (pass) fires only rows whose signature is new since the last pass.
# Rewrites the signature file to the current awaiting-human set either way, and
# stamps liveness.
do_pass() {
  dp_all=$1
  resolve_paths || return 2
  read_store_guard || return 2
  mkdir -p "$attn_dir" 2>/dev/null || true
  if [ ! -f "$store" ]; then
    # No store yet: nothing awaiting. Reset the signature (through
    # atomic_write_file, never a truncating `>` redirect that would follow a
    # planted symlink) so a later push is seen as new. Stamp liveness (a
    # completed pass over an empty fleet) and return.
    atomic_write_file "$sigfile" "" 2>/dev/null || true
    stamp_liveness || {
      echo "fleet-attention-watch: could not stamp liveness" >&2
      return 2
    }
    return 0
  fi
  # Snapshot the store ONCE and compute BOTH the fire set and the new signature
  # set from that single snapshot. The store is written temp+rename, so one `cp`
  # captures a consistent, untorn view; reading it twice (as this used to) opened
  # a window where a row written between the two reads landed in the signature
  # file without ever being fired — silently dropped by the low-latency event
  # path until the next reconcile. One snapshot closes that TOCTOU.
  dp_snap=$(mktemp "$attn_dir/.watch-snap.XXXXXX") || {
    echo "fleet-attention-watch: could not create a store snapshot" >&2
    return 2
  }
  if ! cp "$store" "$dp_snap" 2>/dev/null; then
    rm -f "$dp_snap" 2>/dev/null
    echo "fleet-attention-watch: could not snapshot the attention store" >&2
    return 2
  fi
  # A row's change-identity signature is worker|heartbeat|reason (a re-park
  # re-stamps the commit-time heartbeat, so a genuine change re-fires). The seen
  # set is the previous pass's signatures.
  dp_new=$(awk -F "$TAB" -v sigfile="$sigfile" -v all="$dp_all" '
    BEGIN {
      if (all == 0) {
        while ((getline s < sigfile) > 0) { if (s != "") seen[s] = 1 }
        close(sigfile)
      }
    }
    $3 == "awaiting-input" {
      sig = $1 "|" $4 "|" $9
      if (all == 1 || !(sig in seen)) {
        # \x1f-delimited so a reason with a space survives the read below.
        printf "%s\037%s\037%s\n", $1, $2, $9
      }
    }
  ' "$dp_snap") || {
    rm -f "$dp_snap" 2>/dev/null
    echo "fleet-attention-watch: could not read the attention store" >&2
    return 2
  }
  # Fire each selected row.
  if [ -n "$dp_new" ]; then
    printf '%s\n' "$dp_new" | while IFS=$(printf '\037') read -r fw fs fr; do
      [ -n "$fw" ] || continue
      emit_and_fire "$fw" "$fs" "$fr"
    done
  fi
  # Rewrite the signature file to the CURRENT awaiting-human set from the SAME
  # snapshot (so the next pass fires only post-snapshot changes; a reconcile also
  # resets it here). Every awaiting row in the snapshot was just considered for
  # firing, so none can be recorded here without having been fired.
  dp_sigs=$(awk -F "$TAB" '$3 == "awaiting-input" { print $1 "|" $4 "|" $9 }' "$dp_snap") || dp_sigs=""
  rm -f "$dp_snap" 2>/dev/null
  atomic_write_file "$sigfile" "$dp_sigs
" 2>/dev/null || true
  # Stamp liveness only after the pass has actually COMPLETED — never before the
  # snapshot / read, which can still fail and exit the watch loop while
  # watch.alive reads fresh for --max-age, masking a dead watch (the whole point
  # of the liveness tell is that a watcher that dies stops stamping).
  stamp_liveness || {
    echo "fleet-attention-watch: could not stamp liveness" >&2
    return 2
  }
  return 0
}

# parse [--on-change <cmd>] from a subcommand's args into on_change.
on_change=""
parse_on_change() {
  poc_rest=""
  while [ "$#" -gt 0 ]; do
    case $1 in
      --on-change)
        [ "$#" -ge 2 ] || {
          echo "fleet-attention-watch: --on-change needs a command" >&2
          exit 2
        }
        on_change=$2
        shift 2
        ;;
      *)
        poc_rest="$poc_rest $1"
        shift
        ;;
    esac
  done
  REST=$poc_rest
}

if [ "$#" -lt 1 ]; then
  echo "usage: fleet-attention-watch.sh pass|reconcile|watch|liveness [args]" >&2
  exit 2
fi
cmd=$1
shift

[ -x "$FS" ] || {
  echo "fleet-attention-watch: fleet-state.sh '$FS' is missing or not executable" >&2
  exit 2
}

case $cmd in
  pass)
    parse_on_change "$@"
    # No positional args expected beyond --on-change. Intentional re-split of the
    # leftover args (set -f keeps it word-split only, never globbed).
    # shellcheck disable=SC2086
    set -- $REST
    [ "$#" -eq 0 ] || {
      echo "fleet-attention-watch: pass takes no positional args" >&2
      exit 2
    }
    do_pass 0 || exit 2
    exit 0
    ;;

  reconcile)
    parse_on_change "$@"
    # shellcheck disable=SC2086
    set -- $REST
    [ "$#" -eq 0 ] || {
      echo "fleet-attention-watch: reconcile takes no positional args" >&2
      exit 2
    }
    do_pass 1 || exit 2
    exit 0
    ;;

  liveness)
    max_age=900
    while [ "$#" -gt 0 ]; do
      case $1 in
        --max-age)
          [ "$#" -ge 2 ] || {
            echo "fleet-attention-watch: --max-age needs seconds" >&2
            exit 2
          }
          # An invalid value is a usage error (exit 2), never a silent fall-back
          # to the default: a mistyped --max-age must fail loudly, not read health
          # from an unintended window.
          valid_posint "$2" || {
            echo "fleet-attention-watch: --max-age needs a positive integer of seconds (1..15 digits, no leading zero)" >&2
            exit 2
          }
          max_age=$2
          shift 2
          ;;
        *)
          echo "fleet-attention-watch: unknown liveness option '$(sanitize_printable "$1" "(unprintable)")'" >&2
          exit 2
          ;;
      esac
    done
    resolve_paths || exit 2
    [ -f "$alivefile" ] || exit 1
    la_stamp=$(cat "$alivefile" 2>/dev/null) || la_stamp=""
    case $la_stamp in "" | *[!0-9]* | 0?*) exit 1 ;; esac
    la_now=$(now_epoch)
    [ -n "$la_now" ] || exit 2
    if [ $((la_now - la_stamp)) -le "$max_age" ]; then
      exit 0
    fi
    exit 1
    ;;

  watch)
    interval=15
    reconcile_every=20
    once=0
    parse_on_change "$@"
    # shellcheck disable=SC2086
    set -- $REST
    while [ "$#" -gt 0 ]; do
      case $1 in
        --interval)
          [ "$#" -ge 2 ] || {
            echo "fleet-attention-watch: --interval needs seconds" >&2
            exit 2
          }
          # A usage error, not a silent default: a bad --interval (a busy-loop 0,
          # a typo) must fail loudly rather than silently watching at 15s.
          valid_posint "$2" || {
            echo "fleet-attention-watch: --interval needs a positive integer of seconds (1..15 digits, no leading zero)" >&2
            exit 2
          }
          interval=$2
          shift 2
          ;;
        --reconcile-every)
          [ "$#" -ge 2 ] || {
            echo "fleet-attention-watch: --reconcile-every needs a count" >&2
            exit 2
          }
          valid_posint "$2" || {
            echo "fleet-attention-watch: --reconcile-every needs a positive integer count (1..15 digits, no leading zero)" >&2
            exit 2
          }
          reconcile_every=$2
          shift 2
          ;;
        --once)
          once=1
          shift
          ;;
        *)
          echo "fleet-attention-watch: unknown watch option '$(sanitize_printable "$1" "(unprintable)")'" >&2
          exit 2
          ;;
      esac
    done
    resolve_paths || exit 2
    # Pick the event mechanism: a filesystem watcher (event, low latency) if one
    # is installed, else a bounded poll (degrade to poll-latency, never silent).
    watcher=""
    if command -v fswatch >/dev/null 2>&1; then
      watcher=fswatch
    elif command -v inotifywait >/dev/null 2>&1; then
      watcher=inotifywait
    fi
    loops=0
    while :; do
      do_pass 0 || exit 2
      loops=$((loops + 1))
      if [ "$reconcile_every" -gt 0 ] && [ $((loops % reconcile_every)) -eq 0 ]; then
        do_pass 1 || exit 2
      fi
      [ "$once" = 1 ] && break
      mkdir -p "$attn_dir" 2>/dev/null || true
      w_t0=$(now_epoch)
      case $watcher in
        fswatch)
          # Block until the store dir changes or the interval elapses (the
          # timeout keeps the reconcile cadence and re-checks a dead watcher).
          fswatch -1 --latency 0.2 --timeout "$((interval * 1000))" "$attn_dir" >/dev/null 2>&1 || true
          ;;
        inotifywait)
          inotifywait -qq -t "$interval" -e close_write -e moved_to -e create "$attn_dir" >/dev/null 2>&1 || true
          ;;
        *)
          sleep "$interval"
          ;;
      esac
      # Busy-spin floor. A filesystem watcher is supposed to BLOCK until the store
      # changes or the interval elapses, but an unsupported flag (an old fswatch /
      # inotifywait) or an unwatchable dir can make it exit instantly, and the
      # `|| true` above swallows that — leaving the loop to re-enter do_pass with
      # no delay at 100% CPU. When a watcher returned in under a second, sleep out
      # a one-second floor so a broken watcher degrades to a 1s poll, never a spin.
      # The poll branch already slept `interval`, so this only bites the watcher
      # branches; a genuine sub-second event costs at most one added second.
      if [ -n "$watcher" ]; then
        w_t1=$(now_epoch)
        if [ -n "$w_t0" ] && [ -n "$w_t1" ] && [ "$((w_t1 - w_t0))" -lt 1 ]; then
          sleep 1
        fi
      fi
    done
    exit 0
    ;;

  *)
    echo "fleet-attention-watch: unknown command '$(sanitize_printable "$cmd" "(unprintable command)")' (pass|reconcile|watch|liveness)" >&2
    exit 2
    ;;
esac
