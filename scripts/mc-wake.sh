#!/usr/bin/env bash
# mc-wake.sh — mission control's wake: the relay that pushes a program's
# pending events (scripts/mc-event.sh) to its sessions that run without the
# mod, the failsafe tick behind it, and the wake a session with the mod
# composes here and submits itself.
#
# `mc-wake.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-wake
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh tmux-identity-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2
# shellcheck source=scripts/tmux-identity-lib.sh
. "$script_dir/tmux-identity-lib.sh" || exit 2

LISTED_MAX=20
# The panel mod restamps its target's lease every minute; a `mod` target
# whose lease is older than this has lost its mod, and the relay and the
# tick take it back.
MOD_LEASE=300

usage() {
  mc_usage_fail "usage: mc-wake.sh target add|remove|list --program <p> [<worker>] [--mod] | relay --program <p> | tick --program <p> [--now <epoch>] | compose --program <p> <target>"
}

help_text() {
  cat <<'HELP'
mc-wake.sh — mission control's wake: the relay that pushes a program's
pending events (scripts/mc-event.sh) to its sessions that run without the
mod, the failsafe tick behind it, and the wake a session with the mod
composes here and submits itself.

A WAKE TARGET is a registered session (a fleet registry worker,
scripts/fleet-state.sh) the program's events should wake, recorded with
whether the mod loads in it. A session with the mod is woken by the mod,
which composes its wake with `compose` at its redraw and tick cadences;
the relay and the tick leave it alone while its lease, which the mod
restamps every minute (scripts/mc-panel.sh presence --target), is younger
than five minutes, and treat it as a target without the mod once the lease
is older, missing or stamped after now, so a session whose mod died is not
left with no wake at all.

THE RELAY goes through the fleet's own session relay for the backend the
registry records for the worker, and it never types into a session:
  stream-json, stream-json-persistent
            scripts/fleet-streamjson.sh steer: a user turn on the worker's
            stdin, so the wake is SUBMITTED and its events marked so
  tmux      scripts/orchestrate-relay.sh deliver tmux: a buffer paste with
            no newline, so the wake is STAGED and its events marked staged
            until the session acknowledges them (below); a recorded window
            that is no longer the one recorded (pinned to another tmux
            server or name, or, recorded without its server, gone from its
            session) is unreachable, nothing sent
  any other backend, or a retired worker: unreachable, nothing sent
A WAKE REACHES ONLY MISSION CONTROL: a reachable target whose row in the
mission-control launcher's registry (<fleet-home>/mission-control/sessions/)
names another kind, or that has no row, is refused (`misroute`), and so are
`compose` and a `target add --mod` claim run with a worker identity
(PLANWRIGHT_WORKER_HANDLE) whose row is not a mission-control session's,
since a panel mod in such a session would take another session's events.
A fleet home that cannot be resolved leaves the kind unread: the target is
unreachable, the compose or claim exits 1. Every compose or claim refusal
is named on stderr, a relay's only the first time; the first of each
verb, target, session and kind is logged in <runtime>/wake-misroutes
(<epoch><TAB><verb><TAB><target><TAB><session><TAB><kind>) and raised as a
wake-misroute event.
A ROUTINE event (one whose kind config/mc-event-classes.tsv classes
`routine`) never wakes: relay, tick and compose leave it out of the wake
and mark it submitted for the target (compose's one mark), since the
script that emitted it already acted and nothing in it is for the
operator; it stays listable. With the table unreadable every event wakes,
said on stderr.
A merge-ready event is checked against the forge before it wakes
(scripts/mc-merge-ready.sh fresh): one whose pull request merged, closed
or moved to another head is marked submitted unsent; one whose bot round is
unfinished, or whose state cannot be read, is left out of that wake and
stays pending for a later one.
One wake per target carries 20 of its pending events, oldest first and,
in the tick, never-sent ones ahead of staged ones (the rest wait for a
later wake), naming each one's kind and subject, re-checked against
their grammar, never its free text, which the session reads through the
`mc-event.sh list --program <p> <id>...` command the wake prints. A wake
carrying a usage-reset event also names the `mc-usage.sh report` command
whose lines are all the operator is told of that reset. It is
written to a file of its own under <runtime>/wake/, which a staged pointer
reads and which the tick deletes after a week. A staged wake asks the
session to acknowledge with `mc-event.sh mark ... submitted <id>...` once
read, which is what moves its events from staged to submitted.

THE TICK is the failsafe for both paths: at most once per
mission_control_tick_cadence it sends every target without the mod one
wake for its events not yet submitted, staged ones included, so an event
the push missed, or staged and nobody acknowledged, is found within one
tick. A tick with nothing pending sends nothing. Relays and ticks are
serialized by the runner's pass (scripts/mc-watch.sh); one run by hand
beside a live runner may send a target the same wake twice.

Usage:
  mc-wake.sh target add --program <p> <worker> [--mod]
  mc-wake.sh target remove --program <p> <worker>
  mc-wake.sh target list --program <p>       <worker><TAB>mod|no-mod
  mc-wake.sh relay --program <p>
      push each target's events no relay has delivered: one line per
      target,
        submitted|staged<TAB><worker><TAB><n>
        unconfirmed<TAB><worker><TAB><n>     the paste ran but was not seen;
                                             marked staged, never re-pasted
                                             by the relay
        mod<TAB><worker>                     the mod wakes it
        idle<TAB><worker>                    nothing to send
        unreachable<TAB><worker><TAB><why>
        misroute<TAB><worker><TAB><kind>     not a mission-control session;
                                             nothing sent
        refused<TAB><worker><TAB><exit>      the relay declined (a dialog
                                             open, an earlier wake staged,
                                             a message shaped like a new
                                             unit of work)
        failed<TAB><worker>                  its events could not be read
                                             or marked (named on stderr)
      or `paused` under the fleet daemon pause (`blocked<TAB><exit>` when
      the gate itself is broken).
  mc-wake.sh tick --program <p> [--now <epoch>]
      `not-due<TAB><seconds left>` before the cadence has passed; else
      `tick`, then the relay's lines over every event not yet submitted;
      or `paused` (`blocked`) as the relay.
  mc-wake.sh compose --program <p> <target>
      the wake a session with the mod submits itself: `idle`, or
      `wake<TAB><n><TAB><id> <id>...` then the wake's text, over the
      target's events not yet submitted (the tick's selection); or
      `paused` (`blocked`) as the relay. Sends nothing and marks only
      routine events: the mod marks the ids submitted once its prompt is
      in.

Exit codes: 0 done (a refused or unreachable target is reported, not a
failure); 1 a store that cannot be read or written (the fleet registry
included), a failed target, or a blocked daemon gate; 2 usage; 3 the
program is not configured; 4 a compose or claim refused because the caller
is not a mission-control session.

Portable bash 3.2 / BSD tooling.
HELP
}
case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
[ $# -ge 1 ] || usage
verb=$1
shift
sub=""
if [ "$verb" = target ]; then
  [ $# -ge 1 ] || usage
  sub=$1
  shift
fi
program=""
now=""
mod=0
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --program | --now)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --now) now=$2 ;;
      esac
      shift 2
      ;;
    --mod)
      mod=1
      shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done
[ -n "$program" ] || usage
mc_now_arg "$now"
mc_require_program "$program"
runtime=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory for '$program'"
targets="$runtime/wake-targets"
misroutes="$runtime/wake-misroutes"

# session_kind <name>: SK_KIND, the kind the mission-control launcher's
# registry row records for a session, `unknown` with no row it can trust,
# or `unreadable` when the fleet home cannot be resolved: only a session the
# launcher started as mission control is one. Set, not printed, so the
# fleet home is resolved once per run.
session_kind() {
  SK_KIND=unknown
  mc_valid_handle "$1" || return 0
  if [ -z "${SK_ROOT+x}" ]; then
    SK_ROOT=$(/bin/sh "$script_dir/fleet-state.sh" root 2>/dev/null </dev/null) || SK_ROOT=""
  fi
  if [ -z "$SK_ROOT" ]; then
    SK_KIND=unreadable
    return 0
  fi
  sk_row=$SK_ROOT/mission-control/sessions/$1
  [ -f "$sk_row" ] && [ ! -L "$sk_row" ] && [ -r "$sk_row" ] || return 0
  while IFS='	' read -r sk_key sk_val || [ -n "$sk_key" ]; do
    [ "$sk_key" = kind ] || continue
    case $sk_val in
      "" | -* | *[!a-z0-9-]*) ;;
      *) SK_KIND=$sk_val ;;
    esac
    break
  done <"$sk_row"
}

# misroute <verb> <target> <session> <kind>: a wake that would have reached
# a session that is not mission control, refused. Raised as one
# wake-misroute event and logged in <runtime>/wake-misroutes the first time
# each verb, target, session and kind are seen together, so a relay that
# meets it at every pass neither grows the log nor floods the store. Named
# on stderr then, and at every compose or claim refusal, whose caller shows
# it. The line is written only once the event is in, so a failed emit is
# tried again at the next refusal; a log that cannot be read or written
# raises nothing, since it could not stop the next pass raising it again.
misroute() {
  mr_s=$3
  mc_valid_handle "$mr_s" || mr_s=-
  mr_for=""
  [ "$2" = "$mr_s" ] || mr_for=" for $2"
  mr_seen=0
  if [ -f "$misroutes" ] && awk -F '\t' -v v="$1" -v t="$2" -v s="$mr_s" -v k="$4" \
    '$2 == v && $3 == t && $4 == s && $5 == k { f = 1; exit } END { exit !f }' "$misroutes"; then
    mr_seen=1
  fi
  if [ "$mr_seen" -eq 0 ] || [ "$1" != relay ]; then
    printf '%s: refusing to wake %s (kind %s)%s: not a mission-control session\n' \
      "$prog" "$mr_s" "$4" "$mr_for" >&2
  fi
  [ "$mr_seen" -eq 0 ] || return 0
  [ ! -L "$misroutes" ] || return 0
  { : >>"$misroutes"; } 2>/dev/null && [ -r "$misroutes" ] || return 0
  # A session name outside the handle grammar cannot be an event's subject.
  mr_subject=$mr_s
  [ "$mr_subject" != - ] || mr_subject=$2
  mc_event emit --program "$program" -- wake-misroute "$mr_subject" \
    "a $1 wake for $2 would have reached $mr_s, a $4 session; refused" >/dev/null 2>&1 </dev/null || return 0
  printf '%s\t%s\t%s\t%s\t%s\n' "$NOW" "$1" "$2" "$mr_s" "$4" >>"$misroutes" || :
}

# require_mission_control_caller <verb> <target>: exits 4 when the caller
# carries a worker identity whose session is not mission control: a panel
# mod that activated in a worker must neither take the target nor its wake.
require_mission_control_caller() {
  rc_h=${PLANWRIGHT_WORKER_HANDLE:-}
  [ -n "$rc_h" ] || return 0
  session_kind "$rc_h"
  [ "$SK_KIND" != mission-control ] || return 0
  [ "$SK_KIND" != unreadable ] || mc_fail "cannot resolve the fleet home to read the session kind of '$rc_h'"
  misroute "$1" "$2" "$rc_h" "$SK_KIND"
  exit 4
}

# drop_stale_merge_ready <target>: SEL_ROWS without the merge-ready events
# that must not be pushed now, each checked against the forge once more
# (scripts/mc-merge-ready.sh fresh). One whose pull request merged, closed
# or moved on is marked submitted unsent, so it never wakes; one whose bot
# round is unfinished, or whose state cannot be read, is left out of this
# wake and unmarked, so a later wake can still carry it, the unreadable one
# named on stderr. An event whose text names no pull request and head is
# left as it is.
drop_stale_merge_ready() {
  ds_keep="" ds_gone=""
  while IFS= read -r ds_row; do
    [ -n "$ds_row" ] || continue
    ds_kind=$(printf '%s\n' "$ds_row" | cut -f3)
    if [ "$ds_kind" = merge-ready ]; then
      ds_text=$(printf '%s\n' "$ds_row" | cut -f5)
      ds_pr=${ds_text%% *}
      ds_head=$(printf '%s\n' "$ds_text" | sed -n 's/.*--match-head-commit \([0-9a-f]\{40\}\).*/\1/p')
      case $ds_pr in
        */*#[0-9]*) ;;
        *) ds_head="" ;;
      esac
      if [ -n "$ds_head" ]; then
        ds_why=$(/bin/bash "$script_dir/mc-merge-ready.sh" fresh --program "$program" \
          --repo "${ds_pr%#*}" --pr "${ds_pr##*#}" --head "$ds_head" 2>/dev/null </dev/null)
        ds_rc=$?
        case $ds_rc in
          0) ;;
          4)
            ds_gone="$ds_gone $(printf '%s\n' "$ds_row" | cut -f1)"
            continue
            ;;
          5) continue ;;
          *)
            printf '%s: %s: held: %s\n' "$prog" "$(sanitize_printable "$ds_pr" -)" \
              "$(sanitize_printable "${ds_why#*	}" "fresh exited $ds_rc")" >&2
            continue
            ;;
        esac
      fi
    fi
    ds_keep="$ds_keep$ds_row
"
  done <<EOF
$SEL_ROWS
EOF
  SEL_ROWS=$(printf '%s' "$ds_keep")
  if [ -n "$ds_gone" ]; then
    # shellcheck disable=SC2086 # one event id per word
    mc_event mark --program "$program" --target "$1" submitted $ds_gone
    case $? in 0 | 3) ;; *) return 1 ;; esac
  fi
}

# select_events <target> unmarked|unsubmitted: the target's events for one
# wake, in SEL_ROWS (at most LISTED_MAX), SEL_TOTAL (all but the routine
# ones), SEL_N and SEL_IDS (space separated).
select_events() {
  SEL_ROWS=$(mc_event list --program "$program" --target "$1" --pending --limit 100000) || return 1
  # A routine event is marked submitted unsent, so it leaves the pending
  # set (the panel's count, the next listing) instead of piling up there.
  # Marked in batches, so a large routine backlog never outgrows the
  # argument list and holds back the events that do wake.
  sel_routine=$(printf '%s\n' "$SEL_ROWS" | mc_event_wakes --routine | awk -F '\t' '
    { printf "%s%s", (n % 200 ? " " : (n ? "\n" : "")), $1; n++ } END { if (n) print "" }')
  if [ -n "$sel_routine" ]; then
    printf '%s\n' "$sel_routine" | while IFS= read -r sel_batch; do
      # shellcheck disable=SC2086 # one event id per word
      mc_event mark --program "$program" --target "$1" submitted $sel_batch
      case $? in 0 | 3) ;; *) exit 1 ;; esac
    done || return 1
  fi
  SEL_ROWS=$(printf '%s\n' "$SEL_ROWS" | mc_event_wakes)
  drop_stale_merge_ready "$1" || return 1
  if [ "$2" = unsubmitted ]; then
    # Never-sent events first, so a backlog of staged ones nobody has
    # acknowledged cannot keep a newer event out of every wake.
    SEL_ROWS=$(printf '%s\n' "$SEL_ROWS" | awk -F '\t' 'NF && $NF == "-"; NF && $NF != "-" { s[++n] = $0 } END { for (i = 1; i <= n; i++) print s[i] }')
  else
    SEL_ROWS=$(printf '%s\n' "$SEL_ROWS" | awk -F '\t' '$NF == "-"')
  fi
  SEL_TOTAL=$(printf '%s' "$SEL_ROWS" | awk 'NF { n++ } END { print n + 0 }')
  # One wake carries the first LISTED_MAX; the rest wait for a later wake.
  SEL_ROWS=$(printf '%s\n' "$SEL_ROWS" | M=$LISTED_MAX awk 'NF && ++n <= ENVIRON["M"] + 0')
  SEL_N=$(printf '%s\n' "$SEL_ROWS" | awk 'NF { n++ } END { print n + 0 }')
  SEL_IDS=$(printf '%s\n' "$SEL_ROWS" | awk -F '\t' 'NF { printf "%s%s", sep, $1; sep = " " }')
}

# wake_text <rows> <total> <ids> submitted|staged <target>: the wake, naming
# each event's kind and subject and never its free text.
wake_text() {
  wt_cmd=$(mc_quote "$script_dir/mc-event.sh") || return 1
  wt_n=$(printf '%s\n' "$1" | awk 'NF { n++ } END { print n + 0 }')
  printf 'mission control (%s): %s event(s) pending' "$program" "$2"
  [ "$wt_n" -eq "$2" ] || printf ', %s of them here' "$wt_n"
  printf '.\n'
  printf '%s\n' "$1" | awk -F '\t' 'NF { print "- " $3 " " $4 }'
  printf 'Read them with: %s list --program %s %s\n' "$wt_cmd" "$program" "$3"
  if printf '%s\n' "$1" | awk -F '\t' '$3 == "usage-reset" { f = 1 } END { exit !f }'; then
    wt_usage=$(mc_quote "$script_dir/mc-usage.sh") || return 1
    printf 'A usage window reset: tell the operator only what %s report --program %s prints (landings, decisions, failures).\n' \
      "$wt_usage" "$program"
  fi
  if [ "$4" = staged ]; then
    printf 'Then acknowledge them with: %s mark --program %s --target %s submitted %s\n' \
      "$wt_cmd" "$program" "$5" "$3"
  fi
}

# send <worker> unmarked|unsubmitted: one wake for the worker's events that
# carry no mark, or that are not yet submitted.
send() {
  sd_w=$1
  sd_row=$(printf '%s\n' "$REGISTRY" | W=$sd_w awk -F '\t' '$2 == ENVIRON["W"] { r = $0 } END { print r }')
  if [ -z "$sd_row" ]; then
    printf 'unreachable\t%s\tnot in the fleet registry\n' "$sd_w"
    return 0
  fi
  if [ "$(printf '%s\n' "$sd_row" | awk -F '\t' '{ print (NF == 8 && $8 == "closed") ? "closed" : "live" }')" = closed ]; then
    printf 'unreachable\t%s\tretired\n' "$sd_w"
    return 0
  fi
  sd_backend=$(printf '%s' "$sd_row" | cut -f5)
  sd_handle=""
  case $sd_backend in
    stream-json | stream-json-persistent) sd_mark=submitted ;;
    tmux)
      sd_mark=staged
      sd_handle=$(printf '%s' "$sd_row" | cut -f7)
      case $sd_handle in
        "tmux-window "*" "*)
          if tmux_handle_parse "${sd_handle#tmux-window }"; then
            sd_handle="$TH_SESSION:$TH_WINDOW"
          else
            sd_handle=""
          fi
          ;;
        *) sd_handle="" ;;
      esac
      if [ -z "$sd_handle" ] || ! /bin/sh "$script_dir/orchestrate-relay.sh" validate-handle tmux "$sd_handle" 2>/dev/null; then
        printf 'unreachable\t%s\tno valid tmux window recorded\n' "$sd_w"
        return 0
      fi
      # Typed into only while the window is still the recorded one: a
      # restarted server reissues ids, and the window under one now may be
      # another session's, mission control's own included. A pinned window
      # must still come from its server under its name; one recorded before
      # the pin must still sit in its recorded session.
      if [ -n "$TH_SERVER" ]; then
        sd_ev=$(/bin/sh "$script_dir/bounded-run.sh" 10 /bin/sh "$script_dir/fleet-death-evidence.sh" tmux-window "$TH_SESSION" "$TH_WINDOW" "$TH_SERVER" "$TH_NAME" 2>/dev/null </dev/null)
      else
        sd_ev=$(/bin/sh "$script_dir/bounded-run.sh" 10 /bin/sh "$script_dir/fleet-death-evidence.sh" tmux-window --in-session "$TH_SESSION" "$TH_WINDOW" 2>/dev/null </dev/null)
      fi
      case $sd_ev in
        alive) ;;
        dead)
          printf 'unreachable\t%s\tthe recorded tmux window is gone, or is no longer the one recorded\n' "$sd_w"
          return 0
          ;;
        *)
          printf 'unreachable\t%s\ttmux could not say whether the recorded window is still the one recorded\n' "$sd_w"
          return 0
          ;;
      esac
      ;;
    *)
      printf 'unreachable\t%s\tbackend %s has no session relay\n' "$sd_w" "$(sanitize_printable "$sd_backend" -)"
      return 0
      ;;
  esac
  session_kind "$sd_w"
  if [ "$SK_KIND" = unreadable ]; then
    printf 'unreachable\t%s\tthe fleet home could not be resolved to read its session kind\n' "$sd_w"
    return 0
  fi
  if [ "$SK_KIND" != mission-control ]; then
    misroute relay "$sd_w" "$sd_w" "$SK_KIND"
    printf 'misroute\t%s\t%s\n' "$sd_w" "$SK_KIND"
    return 0
  fi
  select_events "$sd_w" "$2" || return 1
  sd_rows=$SEL_ROWS
  sd_total=$SEL_TOTAL
  sd_n=$SEL_N
  sd_ids=$SEL_IDS
  if [ "$sd_total" -eq 0 ]; then
    printf 'idle\t%s\n' "$sd_w"
    return 0
  fi
  mkdir -p "$runtime/wake" || return 1
  sd_msg=$(mktemp "$runtime/wake/$sd_w.XXXXXX") || return 1
  wake_text "$sd_rows" "$sd_total" "$sd_ids" "$sd_mark" "$sd_w" >"$sd_msg" || {
    rm -f "$sd_msg"
    return 1
  }
  if [ "$sd_mark" = submitted ]; then
    /bin/sh "$script_dir/fleet-streamjson.sh" steer "$sd_w" --message-file "$sd_msg" >/dev/null 2>&1
  else
    /bin/sh "$script_dir/orchestrate-relay.sh" deliver tmux "$sd_handle" "$sd_msg" >/dev/null 2>&1
  fi
  sd_rc=$?
  sd_said=$sd_mark
  case $sd_rc in
    0) ;;
    4)
      # The paste ran, or may have, but its tag never showed: pasting again
      # would stage a duplicate, so it is marked staged and left to the tick.
      [ "$sd_mark" = staged ] || {
        rm -f "$sd_msg"
        printf 'refused\t%s\t%s\n' "$sd_w" "$sd_rc"
        return 0
      }
      sd_said=unconfirmed
      ;;
    *)
      rm -f "$sd_msg"
      printf 'refused\t%s\t%s\n' "$sd_w" "$sd_rc"
      return 0
      ;;
  esac
  # shellcheck disable=SC2086 # one event id per word
  mc_event mark --program "$program" --target "$sd_w" "$sd_mark" $sd_ids
  # Exit 3: an event was pruned since it was listed; the rest are marked.
  case $? in 0 | 3) ;; *) return 1 ;; esac
  printf '%s\t%s\t%s\n' "$sd_said" "$sd_w" "$sd_n"
}

# mod_live <target>: the target's lease, which only its mod writes, is
# younger than MOD_LEASE; one stamped after now proves nothing.
mod_live() {
  ml_lease=$runtime/leases/$1
  [ ! -L "$runtime/leases" ] && [ -f "$ml_lease" ] && [ ! -L "$ml_lease" ] || return 1
  ml_at=$(head -n 1 "$ml_lease")
  mc_valid_uint "$ml_at" || return 1
  [ "$ml_at" -le "$NOW" ] && [ $((NOW - ml_at)) -lt "$MOD_LEASE" ]
}

# each unmarked|unsubmitted: send to every target without the mod. One
# target's failure is named and the rest still sent to; the status is 1 then.
each() {
  [ -f "$targets" ] || return 0
  REGISTRY=$(/bin/sh "$script_dir/fleet-state.sh" registry 2>/dev/null) || mc_fail "cannot read the fleet registry"
  ea_list=$(cat "$targets") || mc_fail "cannot read the wake targets"
  ea_rc=0
  while IFS='	' read -r ea_w ea_mod; do
    mc_valid_handle "$ea_w" || continue
    if [ "$ea_mod" = mod ] && mod_live "$ea_w"; then
      printf 'mod\t%s\n' "$ea_w"
      continue
    fi
    if ! send "$ea_w" "$1"; then
      printf '%s\n' "$prog: cannot read or mark the events for '$ea_w'" >&2
      printf 'failed\t%s\n' "$ea_w"
      ea_rc=1
    fi
  done <<EOF
$ea_list
EOF
  return "$ea_rc"
}

case $verb in
  target)
    case $sub in
      add | remove)
        [ "${#args[@]}" -eq 1 ] || usage
        w=${args[0]}
        mc_valid_handle "$w" || mc_usage_fail "invalid worker '$(sanitize_printable "$w")'"
        [ "$sub" = add ] || [ "$mod" -eq 0 ] || usage
        [ "$mod" -eq 0 ] || require_mission_control_caller claim "$w"
        line=""
        if [ "$sub" = add ]; then
          if [ "$mod" -eq 1 ]; then line="$w	mod"; else line="$w	no-mod"; fi
        fi
        mc_lock || mc_fail "cannot take the fleet lock"
        trap 'mc_unlock' EXIT
        mc_upsert "$targets" "$w" "$line" || mc_fail "cannot read or write the wake targets"
        ;;
      list)
        [ "${#args[@]}" -eq 0 ] || usage
        [ ! -f "$targets" ] || mc_clean <"$targets"
        ;;
      *) usage ;;
    esac
    ;;
  relay)
    [ "${#args[@]}" -eq 0 ] || usage
    mc_gate_or_exit mc-wake
    each unmarked || exit 1
    ;;
  tick)
    [ "${#args[@]}" -eq 0 ] || usage
    mc_gate_or_exit mc-wake
    cadence=$(mc_knob mission_control_tick_cadence mc_parse_cadence) || exit 1
    secs=$(mc_seconds "$cadence")
    last=0
    if [ -f "$runtime/last-tick" ]; then
      last=$(head -n 1 "$runtime/last-tick")
      # A stamp from the future (a clock step, an edited file) never holds
      # the failsafe off.
      mc_valid_uint "$last" && [ "$last" -le "$NOW" ] || last=0
    fi
    if [ $((NOW - last)) -lt "$secs" ]; then
      printf 'not-due\t%s\n' $((secs - (NOW - last)))
      exit 0
    fi
    printf 'tick\n'
    tick_rc=0
    each unsubmitted || tick_rc=1
    # Stamped whatever one target did, so a failing target is retried at the
    # tick's cadence rather than at every pass.
    printf '%s\n' "$NOW" | mc_write "$runtime/last-tick" || mc_fail "cannot record the tick"
    if [ -d "$runtime/wake" ]; then
      # Wake files a week old have long been read or superseded.
      find "$runtime/wake" -type f -mtime +7 -exec rm -f {} + 2>/dev/null || :
    fi
    exit "$tick_rc"
    ;;
  compose)
    [ "${#args[@]}" -eq 1 ] || usage
    w=${args[0]}
    mc_valid_handle "$w" || mc_usage_fail "invalid target '$(sanitize_printable "$w")'"
    mc_gate_or_exit mc-wake
    require_mission_control_caller compose "$w"
    select_events "$w" unsubmitted || mc_fail "cannot read the events for '$w'"
    if [ "$SEL_TOTAL" -eq 0 ]; then
      printf 'idle\n'
      exit 0
    fi
    printf 'wake\t%s\t%s\n' "$SEL_N" "$SEL_IDS"
    wake_text "$SEL_ROWS" "$SEL_TOTAL" "$SEL_IDS" submitted "$w" || mc_fail "cannot quote the event command"
    ;;
  *) usage ;;
esac
