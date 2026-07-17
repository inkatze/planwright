#!/bin/sh
# fleet-throttle.sh — reactive fleet-wide dispatch throttling off Claude
# Code's native rate-limit signal (fleet-autonomy Task 7; D-12, REQ-E1.3;
# kickoff risk rows 9, 23, 24, 30).
#
# No supported, machine-readable way exists to query Claude Code's own
# account-level usage or rate-limit state (D-12: confirmed against Claude
# Code issues #38380/#40793/#33820), so throttling is REACTIVE — the amux
# precedent: when any fleet session renders the shared rate-limit
# prompt/retry text, the tower feeds the captured text to `observe`, which
# parses the signaled reset time and pauses FLEET-WIDE dispatch until it.
# Every tower consults `check` before dispatching; dispatch resumes at the
# signaled reset time by the check comparing against the wall clock — no
# daemon has to fire at the boundary.
#
# STATE. One flag file under the cross-spec fleet home (fleet-state.sh
# root): <fleet-home>/throttle/until, holding the reset epoch. Writes
# serialize through fleet-state.sh's existing cross-spec advisory lock (the
# same primitive fleet-audit.sh holds for the same store area — risk row 8's
# floor: no second lock primitive) and land via write-temp-RENAME, so a
# lockless `check` reader always sees a complete value. CONFLICT RULE (risk
# row 9): concurrent observations with differing parsed reset times resolve
# to the MAX under the lock — the conservative direction — never
# last-write-wins, which could resume dispatch before the account-level
# limit actually clears.
#
# PARSE DISCIPLINE (risk rows 23, 24). Captured pane text is untrusted
# terminal output: every line is stripped of non-printable bytes BEFORE
# parsing, and only sanitized excerpts reach a diagnostic or the audit trail
# (the echo discipline; doctrine/security-posture.md). The recognized reset
# forms are the relative "in <N> seconds/minutes/hours" and the wall-clock
# "resets [at] <H>[:MM]<am|pm>" / 24-hour "<HH>:MM" (next local
# occurrence). A rate-limit signal whose reset time cannot be parsed — the
# text is version-sensitive UI, so this WILL happen — degrades to a bounded
# default hold (the fleet_throttle_default_hold knob) with a warning: never
# an indefinite pause, never an immediate resume, never an opaque halt
# (mirroring REQ-C1.2's /context-parse degrade posture). An engagement
# beyond the 8-day sanity ceiling is refused outright — a garbage reset
# time must never park the fleet indefinitely.
#
# DAEMON CONTRACT (risk row 30). Engagement is an autonomous daemon action:
# it checks the operator kill-switch (fleet-daemon-gate.sh, D-15) before
# acting — a set switch short-circuits, exit 1 — and every state change
# (engage, extend, clear) logs through the shared audit trail
# (fleet-audit.sh, D-16/REQ-F1.4) AFTER the lock is released (fleet-audit
# takes the same lock; holding it across the record call would deadlock).
# An audit-write failure is surfaced (exit 2), never swallowed — an
# unrecorded daemon action is what the trail exists to prevent. `check` is a
# pure read (no gate, no audit); `clear` is the operator's manual-resume
# path (audit-logged, but not gate-checked: the kill-switch pauses
# autonomous actions, not the operator's own lever).
#
# Usage:
#   fleet-throttle.sh check
#       Exit 0: dispatch allowed (no engagement, or the reset time has
#       passed). Exit 1: throttled — prints `until<TAB><epoch>` on stdout so
#       a tower can render the reset time. Exit 2: unreadable/corrupt state
#       (fail loud, let the tower decide).
#   fleet-throttle.sh observe
#       Read captured session text on stdin. No rate-limit signal: exit 3
#       (clean no-op). Signal found: engage (or extend, max rule) until the
#       parsed — or degraded-default — reset time; exit 0, printing
#       `until<TAB><epoch>`. Kill-switch set: exit 1.
#   fleet-throttle.sh engage --until <epoch> [--trigger <text>]
#       Structured engagement for a caller that already holds a parsed
#       reset time (and for fixtures). Same gate/lock/max-rule/audit path
#       as observe. A past or beyond-ceiling epoch is a caller bug: exit 2.
#   fleet-throttle.sh clear [--trigger <text>]
#       Remove the engagement (manual resume) and log it. No-op exit 0 when
#       nothing is engaged.
#
# Exit codes: 0 success (including observe-engaged and no-op clear);
# 1 kill-switch short-circuit (engage/observe) or throttled (check);
# 2 usage error, refused epoch, corrupt state, lock or audit failure;
# 3 no rate-limit signal in the observed text (observe only);
# 4/5 propagated from the kill-switch gate (malformed shared config /
# broken install — fail closed).
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling): awk
# without interval expressions, `date +%s`, a fractional sleep for the lock
# retry. No eval, no jq (REQ-K1.5). All input is data. Pathname expansion
# is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FS="$script_dir/fleet-state.sh"
GATE="$script_dir/fleet-daemon-gate.sh"
AUDIT="$script_dir/fleet-audit.sh"
RESOLVER="$script_dir/resolve-config-knob.sh"

MECHANISM=throttle
# The engagement sanity ceiling: 8 days, comfortably past the longest native
# limit window (weekly) while bounding any garbage epoch (risk row 24).
MAX_HOLD=691200

usage() {
  echo "usage: fleet-throttle.sh check | observe | engage --until <epoch> [--trigger <text>] | clear [--trigger <text>]" >&2
}

now_epoch() {
  ne_v=$(date +%s)
  case $ne_v in
    "" | *[!0-9]*) return 1 ;;
  esac
  printf '%s' "$ne_v"
}

resolve_home() {
  rh_root=$("$FS" root) || return 2
  printf '%s' "$rh_root"
}

HOLD_LOCK=0
# Release on ANY exit, signals included (the fleet-attention.sh trap
# discipline); INT/TERM route through EXIT with the conventional codes.
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
        echo "fleet-throttle: cannot acquire the fleet lock (fleet-state exit $al_rc)" >&2
        return 2
        ;;
    esac
    al_tries=$((al_tries + 1))
    sleep 0.02
  done
  echo "fleet-throttle: gave up acquiring the fleet lock after contention" >&2
  return 2
}
release_lock() {
  if [ "$HOLD_LOCK" = 1 ]; then
    "$FS" unlock >/dev/null 2>&1 || true
    HOLD_LOCK=0
  fi
}

# read_until <file>: print the stored reset epoch, empty when absent.
# Returns 2 on a present-but-corrupt value (fail loud, never guess).
read_until() {
  [ -f "$1" ] || {
    printf ''
    return 0
  }
  ru_v=$(head -n 1 "$1" 2>/dev/null | tr -d '[:space:]')
  case $ru_v in
    "" | *[!0-9]*)
      echo "fleet-throttle: throttle state file '$1' is corrupt ('$(sanitize_printable "$ru_v" "(unprintable)")')" >&2
      return 2
      ;;
  esac
  printf '%s' "$ru_v"
}

# utc_iso <epoch>: best-effort UTC rendering for audit reasoning text; falls
# back to the bare epoch when the platform date cannot format it.
utc_iso() {
  ui_v=$(TZ=UTC date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
    || ui_v=$(TZ=UTC date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
    || ui_v="epoch $1"
  printf '%s' "$ui_v"
}

# engage_until <until-epoch> <trigger-text>
# The shared engagement path: kill-switch gate, lock, max rule, atomic
# write, then audit. Prints `until<TAB><winning-epoch>` on stdout.
engage_until() {
  eu_until=$1
  eu_trigger=$2

  # The daemon gate (D-15): only exit 0 authorizes proceeding; 1 is the set
  # switch (short-circuit), 4/5 are resolver hard-fails — all propagate.
  "$GATE" "$MECHANISM"
  eu_rc=$?
  if [ "$eu_rc" -ne 0 ]; then
    exit "$eu_rc"
  fi

  eu_root=$(resolve_home) || exit 2
  eu_dir="$eu_root/throttle"
  eu_file="$eu_dir/until"

  acquire_lock || exit 2
  eu_existing=$(read_until "$eu_file") || {
    release_lock
    exit 2
  }
  eu_action=""
  if [ -z "$eu_existing" ]; then
    eu_action=engage
  elif [ "$eu_until" -gt "$eu_existing" ]; then
    # The max rule (risk row 9): a later reset extends; an earlier or equal
    # one changes nothing (the conservative direction).
    eu_action=extend
  else
    eu_until=$eu_existing
  fi
  if [ -n "$eu_action" ]; then
    mkdir -p "$eu_dir" || {
      echo "fleet-throttle: cannot create '$eu_dir'" >&2
      release_lock
      exit 2
    }
    printf '%s\n' "$eu_until" >"$eu_file.tmp.$$" || {
      echo "fleet-throttle: cannot write throttle state" >&2
      rm -f "$eu_file.tmp.$$"
      release_lock
      exit 2
    }
    mv "$eu_file.tmp.$$" "$eu_file" || {
      echo "fleet-throttle: cannot commit throttle state" >&2
      rm -f "$eu_file.tmp.$$"
      release_lock
      exit 2
    }
  fi
  release_lock

  if [ -n "$eu_action" ]; then
    # Audit AFTER release: fleet-audit takes the same fleet lock. A failed
    # record is surfaced (exit 2), never swallowed (the trail's contract).
    "$AUDIT" record "$MECHANISM" "$eu_action" "$eu_trigger" \
      "fleet-wide dispatch paused until $(utc_iso "$eu_until") (epoch $eu_until); resumes when check passes that time" || {
      echo "fleet-throttle: the audit trail refused the $eu_action record — surfacing, not swallowing" >&2
      exit 2
    }
  fi
  printf 'until\t%s\n' "$eu_until"
}

[ "$#" -ge 1 ] || {
  usage
  exit 2
}
cmd=$1
shift

case "$cmd" in
  check)
    [ "$#" -eq 0 ] || {
      usage
      exit 2
    }
    root=$(resolve_home) || exit 2
    until_file="$root/throttle/until"
    stored=$(read_until "$until_file") || exit 2
    [ -n "$stored" ] || exit 0
    now=$(now_epoch) || {
      echo "fleet-throttle: cannot read the clock" >&2
      exit 2
    }
    if [ "$now" -lt "$stored" ]; then
      printf 'until\t%s\n' "$stored"
      exit 1
    fi
    exit 0
    ;;

  engage)
    until_arg=""
    trigger="manual engage"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --until)
          [ "$#" -ge 2 ] || {
            usage
            exit 2
          }
          until_arg=$2
          shift 2
          ;;
        --trigger)
          [ "$#" -ge 2 ] || {
            usage
            exit 2
          }
          trigger=$2
          shift 2
          ;;
        *)
          usage
          exit 2
          ;;
      esac
    done
    case $until_arg in
      "" | *[!0-9]*)
        echo "fleet-throttle: --until requires an epoch-seconds value" >&2
        exit 2
        ;;
    esac
    now=$(now_epoch) || {
      echo "fleet-throttle: cannot read the clock" >&2
      exit 2
    }
    if [ "$until_arg" -le "$now" ]; then
      echo "fleet-throttle: refusing a reset time in the past (until $until_arg, now $now) — caller bug" >&2
      exit 2
    fi
    if [ "$until_arg" -gt $((now + MAX_HOLD)) ]; then
      echo "fleet-throttle: refusing a reset time more than 8 days out (until $until_arg, now $now) — a garbage reset must never park the fleet (risk 24)" >&2
      exit 2
    fi
    engage_until "$until_arg" "$trigger"
    ;;

  observe)
    [ "$#" -eq 0 ] || {
      usage
      exit 2
    }
    # Parse the captured text: strip non-printable bytes per line (the awk
    # [[:print:]] form of the echo discipline — risk 23), join, detect the
    # native rate-limit signal, then extract the first recognized reset
    # form. Output protocol: line 1 = `none` | `rel <seconds>` |
    # `wall <h> <m>` | `unparsed`; line 2 (when not `none`) = a <=200-char
    # sanitized excerpt for the audit trigger.
    parse=$(awk '
      { gsub(/[^[:print:]]/, ""); text = text " " $0 }
      END {
        lt = tolower(text)
        if (lt !~ /rate.?limit|usage limit|limit reached|too many requests/) { print "none"; exit }
        excerpt = substr(text, 2, 200)
        if (match(lt, /in [0-9]+ (second|minute|hour)/)) {
          s = substr(lt, RSTART, RLENGTH)
          split(s, a, " ")
          n = a[2] + 0
          if (a[3] == "second") secs = n
          else if (a[3] == "minute") secs = n * 60
          else secs = n * 3600
          if (secs > 0 && secs <= 691200) { print "rel " secs; print excerpt; exit }
          print "unparsed"; print excerpt; exit
        }
        if (match(lt, /(resets?|try again|available)( at)? [0-9][0-9]?(:[0-5][0-9])? ?(am|pm)/)) {
          s = substr(lt, RSTART, RLENGTH)
          match(s, /[0-9][0-9]?(:[0-5][0-9])?/)
          t = substr(s, RSTART, RLENGTH)
          split(t, hm, ":")
          h = hm[1] + 0
          m = (2 in hm) ? hm[2] + 0 : 0
          pm = (s ~ /pm/) ? 1 : 0
          if (h == 12) h = 0
          if (pm) h = h + 12
          if (h <= 23 && m <= 59) { print "wall " h " " m; print excerpt; exit }
          print "unparsed"; print excerpt; exit
        }
        if (match(lt, /(resets?|try again|available)( at)? [0-9][0-9]?:[0-5][0-9]/)) {
          s = substr(lt, RSTART, RLENGTH)
          match(s, /[0-9][0-9]?:[0-5][0-9]/)
          t = substr(s, RSTART, RLENGTH)
          split(t, hm, ":")
          h = hm[1] + 0
          m = hm[2] + 0
          if (h <= 23 && m <= 59) { print "wall " h " " m; print excerpt; exit }
          print "unparsed"; print excerpt; exit
        }
        print "unparsed"; print excerpt
      }') || {
      echo "fleet-throttle: parse failed" >&2
      exit 2
    }
    kind=$(printf '%s\n' "$parse" | head -n 1)
    excerpt=$(printf '%s\n' "$parse" | sed -n '2p')
    [ -n "$excerpt" ] || excerpt="rate-limit signal (no excerpt)"
    case "$kind" in
      none)
        exit 3
        ;;
      rel\ *)
        secs=${kind#rel }
        now=$(now_epoch) || {
          echo "fleet-throttle: cannot read the clock" >&2
          exit 2
        }
        engage_until $((now + secs)) "$excerpt"
        ;;
      wall\ *)
        wh=${kind#wall }
        wm=${wh#* }
        wh=${wh%% *}
        now=$(now_epoch) || {
          echo "fleet-throttle: cannot read the clock" >&2
          exit 2
        }
        cur=$(date +%H:%M:%S)
        ch=${cur%%:*}
        cs=${cur##*:}
        cm=${cur#*:}
        cm=${cm%%:*}
        # Strip a leading zero so 08/09 are not read as bad octal by $(( )).
        ch=${ch#0}
        cm=${cm#0}
        cs=${cs#0}
        cur_secs=$((${ch:-0} * 3600 + ${cm:-0} * 60 + ${cs:-0}))
        target=$((wh * 3600 + wm * 60))
        delta=$((target - cur_secs))
        [ "$delta" -gt 0 ] || delta=$((delta + 86400))
        engage_until $((now + delta)) "$excerpt"
        ;;
      unparsed)
        # Risk 24: signal present, reset time unreadable (version-sensitive
        # UI text). Degrade to the bounded default hold with a warning —
        # never indefinite, never immediate resume, never an opaque halt.
        hold=$("$RESOLVER" --key fleet_throttle_default_hold --type posint --fallback 300) || exit $?
        now=$(now_epoch) || {
          echo "fleet-throttle: cannot read the clock" >&2
          exit 2
        }
        echo "fleet-throttle: warning: rate-limit signal detected but the reset time could not be parsed; degrading to the ${hold}s default hold" >&2
        engage_until $((now + hold)) "$excerpt"
        ;;
      *)
        echo "fleet-throttle: internal parse protocol error" >&2
        exit 2
        ;;
    esac
    ;;

  clear)
    trigger="operator clear"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --trigger)
          [ "$#" -ge 2 ] || {
            usage
            exit 2
          }
          trigger=$2
          shift 2
          ;;
        *)
          usage
          exit 2
          ;;
      esac
    done
    root=$(resolve_home) || exit 2
    until_file="$root/throttle/until"
    [ -f "$until_file" ] || exit 0
    acquire_lock || exit 2
    rm -f "$until_file" || {
      echo "fleet-throttle: cannot remove '$until_file'" >&2
      release_lock
      exit 2
    }
    release_lock
    "$AUDIT" record "$MECHANISM" clear "$trigger" \
      "throttle engagement cleared; fleet-wide dispatch resumes immediately" || {
      echo "fleet-throttle: the audit trail refused the clear record — surfacing, not swallowing" >&2
      exit 2
    }
    exit 0
    ;;

  *)
    usage
    exit 2
    ;;
esac
