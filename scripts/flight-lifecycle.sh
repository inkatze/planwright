#!/bin/sh
# flight-lifecycle.sh — a visual flight's lifecycle pushes into the attention
# store, and the crash policy that covers its worker (tower-front-door D-8,
# D-10; REQ-F1.1, REQ-F1.2, REQ-F1.5, REQ-F1.6).
#
# PUSHES. Each lifecycle event is one invocation by the process that caused it
# (dispatch by scripts/flight-dispatch.sh, the other two by the worker as its
# brief directs), so an event reaches the store whether or not a tower session
# is running, and nothing polls for it. Every write goes through
# scripts/fleet-attention.sh, the existing store and its lock; no second store
# exists. The row is the flight worker's, keyed by its registered handle
# (`tmux-flight-<id>` or `print-flight-<id>`) with scope `flight:<id>`:
#   dispatch            working (tmux) or idle (print: no process exists until
#                       the operator runs the launch); never over a queued
#                       decision, and with --since never over a row the
#                       worker itself wrote at or after that epoch
#   awaiting-decision   awaiting-input carrying the reason, through the
#                       fork-park channel: the one actionable event, so the
#                       one the decision queue shows
#   completion          pr-ready (a PR landing) or done (a record landing),
#                       never over a queued decision; the landing reference is
#                       kept beside the flight's brief as `landing` and sent
#                       through the notification seam (a record landing with
#                       its branch)
# The queue suppresses the two status events, so the operator is pushed only
# what needs them: the decision, and the landing on whatever channel the
# operator chose (`notification_channel`).
#
# CRASH POLICY. `supervise` is one pass of the fleet crash-loop policy over a
# checkout's flights; the fleet sweep runs it every cycle. It reads the shared
# flight sweep, so a worker is a crash only on positive evidence of death with
# no landing: an unknown liveness, a print-rung flight, and a landed or queued
# one are never crashes. For each dead flight it counts the death once, keyed
# by the registry's death handle and claimed atomically beside the brief,
# through scripts/fleet-liveness.sh crash-record under the fleet knobs
# (fleet_crash_backoff_base_seconds, fleet_crash_disable_threshold); then
# crash-check decides: inside the backoff it waits, at the disable threshold
# the disable is already a decision-queue entry and nothing relaunches, and
# otherwise the worker relaunches into the flight's own worktree and branch
# with its own brief (fleet-dispatch-worktree.sh dispatch --relaunch, the
# guarded launch, creating nothing), which registers the new worker; that relaunch is claimed once per death too, so two sweeps
# racing on one death start one worker. crash-check consults the operator
# kill-switch and crash-record does not, but the fleet sweep skips its whole
# cycle while the switch is set, so under the sweep a paused death is counted
# once the switch is cleared. The death is claimed BEFORE
# crash-record runs, because crash-record is not idempotent, and no pass
# relaunches a death until its count is recorded beside the claim. A
# crash-record that counted nothing releases its claim for the next pass; a
# relaunch that did not start releases both, so the next pass counts it as
# another crash under the same backoff and disable threshold. A pass that dies
# between claiming and recording, or a relaunched worker the registry never
# learned, leaves that death `waiting`, which the fleet sweep warns of every
# cycle rather than relaunching it.
#
# What this guarantees is bounded or surfaced, never absolute: a dead worker is
# relaunched at most up to the disable threshold and then surfaced as a
# decision; a worker whose death cannot be proven (no handle, an unreachable
# tmux server) is not relaunched and reads `unknown` in the sweep's render; a
# relaunch whose worker cannot be matched to a tmux window leaves a registry
# record without a death handle, so later deaths of that worker read unknown
# rather than dead.
#
# Usage:
#   flight-lifecycle.sh push dispatch <flight-id> --handle <handle> [--since <epoch>]
#   flight-lifecycle.sh push awaiting-decision <flight-id> --handle <handle> --reason <text>
#   flight-lifecycle.sh push completion <flight-id> --handle <handle> --landing <pr:<url>|record:<path>>
#   flight-lifecycle.sh supervise [--repo-root <dir>] [--now <epoch>]
#
# supervise prints one TAB-separated line per dead flight:
#   backoff<TAB><id><TAB><count>      counted; waiting out the backoff
#   relaunched<TAB><id><TAB><count>   relaunched into its own worktree
#   waiting<TAB><id><TAB><count>      another pass holds this death's count
#                                     or relaunch, or the relaunched worker
#                                     has not registered a death handle of
#                                     its own yet
#   held<TAB><id><TAB><count>         counted; the daemon layer is paused
#   disabled<TAB><id><TAB><count>     at the disable threshold; queued
#   failed<TAB><id><TAB><reason>      a step failed; left for the next pass
#
# Exit codes: 0 pushed / supervised (a failed flight is a line, not an exit);
#   2 usage or a refused input; 4 the fleet home, the sweep, or the store could
#   not be read or written.
#
# Portable POSIX sh (the bash 3.2 floor); no eval; pathname expansion off.
set -uf
LC_ALL=C
export LC_ALL
unset CDPATH

prog=flight-lifecycle
TAB=$(printf '\t')

script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"
# shellcheck source=scripts/flight-common.sh
. "$script_dir/flight-common.sh"

STATE="$script_dir/fleet-state.sh"
ATTN="$script_dir/fleet-attention.sh"
LIVENESS="$script_dir/fleet-liveness.sh"
SWEEP="$script_dir/flight-sweep.sh"
FLIGHT_ID="$script_dir/flight-id.sh"
WORKTREE="$script_dir/fleet-dispatch-worktree.sh"

die() {
  printf '%s: %s\n' "$prog" "$2" >&2
  exit "$1"
}

usage() {
  cat >&2 <<'EOF'
usage: flight-lifecycle.sh push dispatch <flight-id> --handle <handle> [--since <epoch>]
       flight-lifecycle.sh push awaiting-decision <flight-id> --handle <handle> --reason <text>
       flight-lifecycle.sh push completion <flight-id> --handle <handle> --landing <pr:<url>|record:<path>>
       flight-lifecycle.sh supervise [--repo-root <dir>] [--now <epoch>]
EOF
  exit 2
}

valid_id() {
  /bin/sh "$FLIGHT_ID" check "$1" >/dev/null 2>&1 </dev/null
}

# flight_dir <id> — set FDIR to the flight's private directory under the fleet
# home, or fail: a flight this home never dispatched has nowhere to keep its
# landing or its crash mark. The home itself must be private too, as for the
# brief: anyone who can write it can swap `flights` for a directory of theirs.
flight_dir() {
  _home=$(/bin/sh "$STATE" root 2>/dev/null </dev/null) || return 1
  [ -n "$_home" ] && _home=$(cd "$_home" 2>/dev/null && pwd -P) || return 1
  FDIR="$_home/flights/$1"
  private_dir "$_home" && private_dir "$_home/flights" && private_dir "$FDIR"
}

valid_landing() {
  # grep -x anchors each line, not the whole value, so a multi-line landing
  # would pass on any one matching line.
  has_ctl "$1" && return 1
  case $1 in
    pr:*)
      printf '%s\n' "${1#pr:}" \
        | grep -Eqx 'https://[A-Za-z0-9.-]+/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+'
      ;;
    record:*)
      _lp=${1#record:}
      case $_lp in
        /* | *..* | *//*) return 1 ;;
      esac
      printf '%s\n' "$_lp" | grep -Eqx "([A-Za-z0-9._-]+/)*_flights/$2\\.md"
      ;;
    *) return 1 ;;
  esac
}

cmd_push() {
  [ $# -ge 2 ] || usage
  event=$1
  id=$2
  shift 2
  case $event in
    dispatch | awaiting-decision | completion) ;;
    *) die 2 "unknown lifecycle event '$(sanitize_printable "$event" "(unprintable)")' (dispatch, awaiting-decision, completion)" ;;
  esac
  handle=''
  reason=''
  reason_set=0
  landing=''
  since=''
  while [ $# -gt 0 ]; do
    case $1 in
      --handle)
        [ $# -ge 2 ] || usage
        handle=$2
        shift 2
        ;;
      --since)
        [ $# -ge 2 ] || usage
        case $2 in
          '' | 0?* | *[!0-9]* | ????????????????*) die 2 "--since needs epoch seconds (digits, no leading zero, at most 15)" ;;
        esac
        since=$2
        shift 2
        ;;
      --reason)
        [ $# -ge 2 ] || usage
        reason=$2
        reason_set=1
        shift 2
        ;;
      --landing)
        [ $# -ge 2 ] || usage
        landing=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  valid_id "$id" || die 2 "refusing an off-grammar flight id"
  case $handle in
    "tmux-flight-$id" | "print-flight-$id") ;;
    *) die 2 "the handle must be the flight's own (tmux-flight-<id> or print-flight-<id>)" ;;
  esac
  scope="flight:$id"
  [ -z "$since" ] || [ "$event" = dispatch ] || usage
  case $event in
    dispatch)
      [ $reason_set -eq 0 ] && [ -z "$landing" ] || usage
      state=working
      [ "${handle%%-*}" != print ] || state=idle
      set -- --unless-awaiting
      # The worker's own row, stamped since its launch, outranks this push.
      [ -z "$since" ] || set -- "$@" --unless-since "$since"
      /bin/sh "$ATTN" heartbeat "$handle" "$scope" "$state" "$@" </dev/null \
        || die 4 "the dispatch push did not reach the attention store"
      ;;
    awaiting-decision)
      [ -z "$landing" ] || usage
      [ -n "$reason" ] || die 2 "the awaiting-decision push needs a non-empty --reason"
      has_ctl "$reason" && die 2 "refusing a reason carrying a control byte"
      # The store refuses the C1 byte range too, which UTF-8 punctuation such
      # as a dash falls in; refusing it here keeps a refused reason exit 2.
      [ "$(sanitize_printable "$reason")" = "$reason" ] \
        || die 2 "refusing a reason the attention store would refuse; keep it to plain ASCII"
      [ "${#reason}" -le 480 ] || die 2 "refusing a reason over 480 bytes"
      /bin/sh "$ATTN" park "$handle" "$scope" "flight-parked: $reason" </dev/null \
        || die 4 "the awaiting-decision push did not reach the attention store"
      ;;
    completion)
      [ $reason_set -eq 0 ] || usage
      valid_landing "$landing" "$id" || die 2 "refusing a landing that is neither pr:<https PR URL> nor record:<path to _flights/<id>.md>"
      case $landing in
        pr:*) state=pr-ready ;;
        *) state="done" ;;
      esac
      # The landing and its notification do not depend on the row, so a store
      # that refuses the row still gets them before this exits.
      _stored=1
      /bin/sh "$ATTN" heartbeat "$handle" "$scope" "$state" --unless-awaiting </dev/null || _stored=0
      if flight_dir "$id"; then
        (umask 077 && printf '%s\n' "$landing" >"$FDIR/landing.tmp" && mv -f "$FDIR/landing.tmp" "$FDIR/landing") \
          || printf '%s: could not keep the landing reference beside the brief; the sweep still derives it\n' "$prog" >&2
      else
        printf '%s: no private flight directory under the fleet home; the landing reference is kept by the sweep only\n' "$prog" >&2
      fi
      # A record landing has no link to follow, so its reference is the record
      # path and the branch that carries it.
      _ref=${landing#*:}
      case $landing in
        record:*) _ref="$_ref on planwright/flight/$id" ;;
      esac
      /bin/sh "$ATTN" notify "flight $id landed: $_ref" --key "flight-landed-$id" </dev/null \
        || printf '%s: the landing notification was not sent; the store row and the sweep carry it\n' "$prog" >&2
      [ "$_stored" -eq 1 ] || die 4 "the completion push did not reach the attention store"
      ;;
  esac
}

# registry_death <handle> — the death handle of the handle's latest registry
# record, empty when it has none (the registry writes `-` for an absent one).
registry_death() {
  /bin/sh "$STATE" registry 2>/dev/null </dev/null | awk -F "$TAB" -v h="$1" '
    $2 == h { last = $7 } END { if (last != "-") print last }'
}

# claim <kind> <death> — take the one-time claim of <kind> for this death,
# atomically: mkdir succeeds for exactly one caller, so two sweeps racing on
# one death cannot both count it or both relaunch it. Sets CLAIM to its path;
# returns 1 when another pass holds it, 2 when it could not be taken at all.
claim() {
  _ck=$(printf '%s' "$2" | cksum | awk '{ print $1 "." $2 }')
  CLAIM="$FDIR/$1.$_ck"
  (umask 077 && mkdir "$CLAIM") 2>/dev/null && return 0
  [ -d "$CLAIM" ] && [ ! -L "$CLAIM" ] && return 1
  return 2
}

crash_count() {
  _cc=$(/bin/sh "$LIVENESS" crash-count "$1" 2>/dev/null </dev/null) || _cc=''
  case $_cc in
    '' | *[!0-9]*) printf '?\n' ;;
    *) printf '%s\n' "$_cc" ;;
  esac
}

# relaunch <id> <handle> — start a fresh worker in the flight's own worktree
# with its own brief, through the dispatch primitive's relaunch arm, the one
# guarded launch, which also registers the new worker. Startup is not waited
# for: a sweep pass must not hold on one flight. On failure RELAUNCH_WHY holds
# the primitive's last diagnostic, one printable line, so the operator sees why.
relaunch() {
  RELAUNCH_WHY=''
  _rl_err=$( (cd "$repo_root" && /bin/sh "$WORKTREE" dispatch --flight "$1" --brief "$FDIR/brief.md" \
    --relaunch --launch-only --repo-root "$repo_root" </dev/null 2>&1 >/dev/null)) \
    && return 0
  _rl_err=$(printf '%s\n' "$_rl_err" | awk 'NF { l = $0 } END { print l }')
  RELAUNCH_WHY=$(sanitize_printable "$_rl_err" | cut -c1-200)
  return 1
}

supervise_one() {
  id=$1
  handle=$2
  case $handle in
    "tmux-flight-$id") ;;
    *) return 0 ;;
  esac
  if ! flight_dir "$id"; then
    printf 'failed\t%s\t%s\n' "$id" "no private flight directory under the fleet home"
    return 0
  fi
  death=$(registry_death "$handle")
  if [ -z "$death" ] || has_ctl "$death"; then
    printf 'failed\t%s\t%s\n' "$id" "the registry holds no death handle to count the crash by"
    return 0
  fi
  claim counted "$death"
  _cl=$?
  counted=$CLAIM
  case $_cl in
    0)
      set -- "$handle" "flight:$id"
      [ -z "$now" ] || set -- "$@" --now "$now"
      # crash-record's counter is durable once it prints its line, so the line,
      # not the exit, says whether this death was counted.
      if [ -z "$(cd "$repo_root" && /bin/sh "$LIVENESS" crash-record "$@" 2>/dev/null </dev/null)" ]; then
        rmdir "$CLAIM" 2>/dev/null
        printf 'failed\t%s\t%s\n' "$id" "the crash could not be counted; a later pass counts it"
        return 0
      fi
      if ! (umask 077 && : >"$CLAIM/recorded") 2>/dev/null; then
        printf 'failed\t%s\t%s\n' "$id" "the crash was counted but its record mark could not be written; later passes wait on it"
        return 0
      fi
      ;;
    1)
      # Until the pass holding the count has recorded it, crash-check would
      # read the previous streak and authorize a relaunch early.
      if [ ! -e "$CLAIM/recorded" ]; then
        printf 'waiting\t%s\t%s\n' "$id" "$(crash_count "$handle")"
        return 0
      fi
      ;;
    *)
      printf 'failed\t%s\t%s\n' "$id" "the crash claim could not be taken under the flight directory"
      return 0
      ;;
  esac
  set -- "$handle"
  [ -z "$now" ] || set -- "$@" --now "$now"
  # The knobs and the kill-switch resolve from the flight's checkout, as the
  # gate re-check below does, not from wherever the pass was started.
  (cd "$repo_root" && /bin/sh "$LIVENESS" crash-check "$@" >/dev/null 2>&1 </dev/null)
  _cr=$?
  count=$(crash_count "$handle")
  case $_cr in
    0)
      claim relaunched "$death"
      case $? in
        0)
          if relaunch "$id" "$handle"; then
            printf 'relaunched\t%s\t%s\n' "$id" "$count"
          else
            # A relaunch that did not start is another failure of this worker:
            # releasing the count too makes the next pass count it, so a
            # relaunch that keeps failing backs off and reaches the disable.
            rmdir "$CLAIM" 2>/dev/null
            rm -f "$counted/recorded" && rmdir "$counted" 2>/dev/null
            printf 'failed\t%s\t%s\n' "$id" "the relaunch did not start${RELAUNCH_WHY:+ ($RELAUNCH_WHY)}; it counts as another crash"
          fi
          ;;
        1) printf 'waiting\t%s\t%s\n' "$id" "$count" ;;
        *) printf 'failed\t%s\t%s\n' "$id" "the relaunch claim could not be taken under the flight directory" ;;
      esac
      ;;
    1)
      # crash-check answers 1 for the backoff window and for a paused daemon
      # layer alike; the gate tells them apart.
      if (cd "$repo_root" && /bin/sh "$script_dir/fleet-daemon-gate.sh" liveness-backoff >/dev/null 2>&1 </dev/null); then
        printf 'backoff\t%s\t%s\n' "$id" "$count"
      else
        printf 'held\t%s\t%s\n' "$id" "$count"
      fi
      ;;
    3) printf 'disabled\t%s\t%s\n' "$id" "$count" ;;
    *) printf 'failed\t%s\t%s\n' "$id" "crash-check exited $_cr" ;;
  esac
}

cmd_supervise() {
  repo_root=''
  now=''
  while [ $# -gt 0 ]; do
    case $1 in
      --repo-root)
        [ $# -ge 2 ] || usage
        repo_root=$2
        shift 2
        ;;
      --now)
        [ $# -ge 2 ] || usage
        case $2 in
          '' | *[!0-9]* | 0?* | ????????????????*) die 2 "--now needs a non-negative epoch of at most 15 digits" ;;
        esac
        now=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  if [ -z "$repo_root" ]; then
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || die 2 "not inside a git checkout; pass --repo-root"
  fi
  repo_root=$(cd "$repo_root" 2>/dev/null && pwd -P) || die 2 "--repo-root is not a directory"
  # The local read first: only a worker with positive death evidence can be a
  # crash, so the forge's PR reads, which a landing needs, are paid only when
  # one exists. Without the forge an unlanded flight with an origin reads
  # unknown, so unknown stays a candidate; one already waiting on the operator
  # never is.
  render=$(/bin/sh "$SWEEP" sweep --repo-root "$repo_root" --no-forge --no-write 2>/dev/null </dev/null) \
    || die 4 "the flight sweep could not be read; nothing was supervised"
  printf '%s\n' "$render" | awk -F "$TAB" '$1 == "flight" && $5 == "dead" && ($3 == "dead" || $3 == "unknown") { f = 1 } END { exit !f }' \
    || return 0
  render=$(/bin/sh "$SWEEP" sweep --repo-root "$repo_root" --no-write 2>/dev/null </dev/null) \
    || die 4 "the flight sweep could not be read; nothing was supervised"
  dead=$(printf '%s\n' "$render" | awk -F "$TAB" '$1 == "flight" && $3 == "dead" && $5 == "dead" { print $2 "\t" $6 }')
  [ -n "$dead" ] || return 0
  printf '%s\n' "$dead" | while IFS="$TAB" read -r _id _handle; do
    valid_id "$_id" || continue
    supervise_one "$_id" "$_handle"
  done
}

[ $# -ge 1 ] || usage
sub=$1
shift
case $sub in
  push) cmd_push "$@" ;;
  supervise) cmd_supervise "$@" ;;
  *) usage ;;
esac
