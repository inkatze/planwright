#!/usr/bin/env bash
# mc-usage.sh — the usage-window duty: hold a program's launches while an
# account usage window is near its limit, queue the next units, and at the
# window's reset drain the queue and resume the sessions a limit stopped.
# Every step is a script; none calls a model.
#
# `mc-usage.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-usage
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh lock-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh" || exit 2

# A launch the launcher refuses for a reason that may pass (a held name, the
# admission gate) is tried at this many drains before it is reported failed.
MAX_ATTEMPTS=3

usage() {
  mc_usage_fail "usage: mc-usage.sh [watch] [--program <p>] [--now <epoch>] | held --program <p> [--now <epoch>] | list|report --program <p> | drain --program <p> [--now <epoch>] | enqueue --program <p> (--kind <k> --scope <s> --brief <file> [--backend <b>] [--cwd <dir>] [--repo <dir>] [--rules <scope>]... | --resume <session> [--brief <file>]) | drop --program <p> <id> (mc-usage.sh --help)"
}

help_text() {
  cat <<'HELP'
mc-usage.sh — the usage-window duty: hold a program's launches while an
account usage window is near its limit, queue the next units, and at the
window's reset drain the queue and resume the sessions a limit stopped.
Every step is a script; none calls a model.

THE WINDOWS are the session (five-hour) and weekly windows with the epoch
each resets at: the status-line mirror (scripts/fleet-usage-gate.sh
windows), and for a window the mirror lacks, the reading the stream-json
workers' frames give (scripts/claude-frames.sh read), so a host running
only headless sessions still reads them; while a hold lasts, only a frame
received after it began counts. A held claude quota (scripts/quota-hold.sh,
a session that died on a limit) is a window too, named `quota`, resetting at
the time its refusal stated.

THE HOLD starts when a window reaches mission_control_usage_hold percent
(`off` holds on the quota alone) and lasts until every held window's reset
epoch has passed, or a fresh reading of it is under the threshold, so a
mirror gone stale while the account is held does not hold it past the
reset. A quota with no stated reset ends with fresh readings of both windows
under the threshold. A quota that has ended is released, and its reset
acted on, even when no watch saw it held. While the hold lasts the
launcher refuses new sessions (scripts/mission-control-launch.sh, but for
a mission-control launch and one with --operator-asked), the budget reads
hold-dispatch (scripts/mc-budget.sh), and the next units go to the queue
instead. It is kept in <runtime>/usage/hold.

THE QUEUE is <runtime>/usage/queue/<id>/, one directory per entry holding
its `entry` record and a copy of its brief, so it survives every session.
An entry's trigger is the usage-reset event: it drains at the next reset,
or at the next watch once no hold is left. A launch entry replays the
launcher from the directory it was queued in, after scripts/mc-budget.sh
admit admits a session; one the launcher refuses with exit 3 or 4 is kept
for the next drain, up to three attempts. A resume entry, and every
stream-json session the launcher lists for the program whose run ended on
a limit (scripts/fleet-streamjson.sh status: limited), is resumed with a
handover: steered a user turn carrying the entry's brief, or the default
handover, and when its channel is dead, recovered first
(fleet-streamjson.sh recover --cwd <its launch directory>).

Usage:
  mc-usage.sh [watch] [--program <p>] [--now <epoch>]
      the duty's watcher (what a run with no verb does under the runner,
      the program from PLANWRIGHT_MC_PROGRAM): read the windows, update the
      hold, and at the reset release the claude quota, drain the queue and
      write the reset record; one line per act:
        held<TAB><window><TAB><percent|-><TAB><reset epoch|->
        released-quota<TAB>claude
        launched<TAB><id><TAB><session>
        resumed<TAB><session>
        kept<TAB><id><TAB><why>
        failed<TAB><id|session><TAB><why>
        event<TAB>usage-held<TAB><window><TAB><text>      entering a hold
        event<TAB>usage-reset<TAB><window>[.<window>]<TAB><text>
        event<TAB>usage-drained<TAB><program><TAB><text>  a later drain
                                                          that acted
      or `busy` while another watch or drain holds the duty's lock, and
      `paused` under the fleet daemon pause (`blocked<TAB><exit>` for a
      broken gate)
  mc-usage.sh held --program <p> [--now <epoch>]
      exit 0 printing the hold's `held` lines, a window whose reset has
      passed left out; exit 1 printing `clear` when none is left
  mc-usage.sh enqueue --program <p> --kind <k> --scope <s> --brief <file>
                      [--backend <b>] [--cwd <dir>] [--repo <dir>] [--rules <scope>]...
  mc-usage.sh enqueue --program <p> --resume <session> [--brief <file>]
      queue a launch (the launcher's own arguments) or a resume (of a
      stream-json session the program launched, its brief at most 64 KiB);
      prints queued<TAB><id>
  mc-usage.sh list --program <p>
      entry<TAB><id><TAB>launch|resume<TAB><trigger><TAB><scope|session>
  mc-usage.sh drop --program <p> <id>
      prints dropped<TAB><id>
  mc-usage.sh drain --program <p> [--now <epoch>]
      launch the queue and resume the sessions a limit stopped now, printing
      the watch's launched, resumed, kept and failed lines; it releases no
      quota and writes no reset record (refused while a hold lasts, a window
      whose reset has passed aside)
  mc-usage.sh report --program <p>
      what the first wake after the latest reset tells the operator, and
      nothing else: since the hold began, each landing (session-landed),
      each decision (an operator item of a kind an armed duty declares) and
      each failure (stall-dead, stream-json-worker-dead, watcher-stopped,
      and the drain's own failures):
        landed|decision|failed<TAB><subject><TAB><text>

Exit codes: 0 done (held: held); 1 clear (held), a store that cannot be
read or written, an invalid threshold, a drain refused under a hold, or a
blocked daemon gate (watch, drain); 2 usage, or a broken install; 3 the
program is not configured, or no such entry (drop). Exit 1 is both clear
and a failure, so a caller reads clear only from the printed `clear`.

Portable bash 3.2 / BSD tooling.
HELP
}
case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac

verb=watch
case ${1:-} in
  "" | --*) ;;
  *)
    verb=$1
    shift
    ;;
esac
program=${PLANWRIGHT_MC_PROGRAM:-}
now="" kind="" scope="" brief="" backend="" cwd="" repo="" rules="" resume=""
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --program | --now | --kind | --scope | --brief | --backend | --cwd | --repo | --rules | --resume)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --now) now=$2 ;;
        --kind) kind=$2 ;;
        --scope) scope=$2 ;;
        --brief) brief=$2 ;;
        --backend) backend=$2 ;;
        --cwd) cwd=$2 ;;
        --repo) repo=$2 ;;
        --rules) rules="$rules $2" ;;
        --resume) resume=$2 ;;
      esac
      shift 2
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
udir="$runtime/usage"
queue="$udir/queue"
holdf="$udir/hold"
lastf="$udir/last-reset"
mkdir -p "$queue" || mc_fail "cannot create the usage queue"
TAB=$(printf '\t')

parse_hold() {
  case $1 in
    off) printf 'off\n' ;;
    *)
      mc_valid_uint "$1" && [ "$1" -ge 1 ] && [ "$1" -le 100 ] || return 1
      printf '%s\n' "$1"
      ;;
  esac
}

valid_scope() {
  [ "${#1}" -le 128 ] || return 1
  case $1 in
    "" | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
}
valid_id() {
  case $1 in
    q[0-9]*.*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!a-z0-9.]* | *.*.*) return 1 ;;
  esac
  [ "${#1}" -le 40 ]
}
abs_dir() { # abs_dir <flag> <dir>
  case $2 in
    /*) ;;
    *) mc_usage_fail "$1 takes an absolute directory" ;;
  esac
  case $2 in
    *[[:cntrl:]]*) mc_usage_fail "$1 holds a control character" ;;
  esac
  [ -d "$2" ] || mc_usage_fail "$1 names no directory"
  (cd -- "$2" && pwd -P)
}

# queue_ids: the ids of the queued entries, sorted.
queue_ids() {
  (cd "$queue" && set +f && for d in q*; do [ -f "$d/entry" ] && printf '%s\n' "$d"; done) | sort
}

# field <file> <key>: one entry or record field.
field() { mc_kv "$1" "$2"; }

# windows [since]: WIN, `<window> <percent> <reset>` lines, a window no source
# reads left out. With a hold since <since>, a frame received no later is no
# fresh reading: frames carry no age limit, so an older, lower one would end
# the hold while the account is still near the limit.
windows() {
  wi_mirror=$(/bin/sh "$script_dir/fleet-usage-gate.sh" windows --now "$NOW" 2>/dev/null) || wi_mirror=""
  wi_frames=$(/bin/sh "$script_dir/claude-frames.sh" read --now "$NOW" 2>/dev/null) || wi_frames=""
  WIN=$(printf '%s\n%s\n' "$wi_mirror" "$wi_frames" | S=${1:-} awk -F '\t' '
    function ok(p, r) { return p ~ /^[0-9]+([.][0-9]+)?$/ && p + 0 <= 100 && r ~ /^[0-9]+$/ }
    function fresh(t) { return ENVIRON["S"] == "" || (t ~ /^[0-9]+$/ && t + 0 > ENVIRON["S"] + 0) }
    ($1 == "session" || $1 == "weekly") && ok($2, $3) && !($1 in w) { w[$1] = int($2) " " $3 }
    $1 == "window" && ($2 == "session" || $2 == "weekly") && ok($3, $4) && fresh($5) && !($2 in w) { w[$2] = int($3) " " $4 }
    END { if ("session" in w) print "session " w["session"]; if ("weekly" in w) print "weekly " w["weekly"] }')
}

# quota: QUOTA held|clear, QUOTA_RESET (an epoch or -) and QUOTA_SINCE (an
# epoch or empty) for claude.
quota() {
  QUOTA=clear
  QUOTA_RESET=-
  QUOTA_SINCE=""
  qu_out=$(/bin/sh "$script_dir/quota-hold.sh" status --vendor claude --now "$NOW" 2>/dev/null) || return 1
  qu_line=$(printf '%s\n' "$qu_out" | awk -F '\t' '$1 == "vendor" && $2 == "claude" { print $3 "\t" $5 "\t" $4 }')
  case $qu_line in
    held"$TAB"*)
      QUOTA=held
      qu_rest=${qu_line#held"$TAB"}
      QUOTA_RESET=${qu_rest%%"$TAB"*}
      QUOTA_SINCE=${qu_rest#*"$TAB"}
      mc_valid_uint "$QUOTA_RESET" || QUOTA_RESET=-
      mc_valid_uint "$QUOTA_SINCE" || QUOTA_SINCE=""
      ;;
  esac
}

# held_rows: the hold's window lines, `<window> <percent|-> <reset|->`.
held_rows() {
  [ -e "$holdf" ] || return 0
  [ -f "$holdf" ] && [ -r "$holdf" ] || return 1
  awk -F '\t' '$1 == "window" && NF == 4 { print $2 " " $3 " " $4 }' "$holdf"
}

# live_rows: the hold's rows still held at NOW, not only at the last watch:
# a watcher that stopped (a disarmed duty, a paused fleet) must not hold
# launches past a reset.
live_rows() {
  lr_rows=$(held_rows) || return 1
  printf '%s\n' "$lr_rows" | N=$NOW awk 'NF == 3 && ($3 == "-" || ENVIRON["N"] + 0 < $3 + 0)'
}

# hold_now <threshold>: CUR, the windows held at NOW, from the readings, the
# hold so far and the quota.
hold_now() {
  CUR=$(printf '%s\n--\n%s\n--\n%s %s %s\n' "$WIN" "$PREV" "$QUOTA" "$QUOTA_RESET" "$1" | N=$NOW awk '
    BEGIN { part = 1; now = ENVIRON["N"] + 0 }
    $0 == "--" { part++; next }
    NF == 0 { next }
    part == 1 { pct[$1] = $2; rst[$1] = $3; seen[$1] = 1; next }
    part == 2 { prev[$1] = 1; ppct[$1] = $2; prst[$1] = $3; order[++n] = $1; next }
    part == 3 { qstate = $1; qreset = $2; thr = $3 }
    END {
      for (w in seen) if (thr != "off" && pct[w] >= thr + 0) cur[w] = pct[w] " " rst[w]
      for (i = 1; i <= n; i++) {
        w = order[i]
        if (w == "quota" || (w in cur)) continue
        if (prst[w] != "-" && now >= prst[w] + 0) continue
        if ((w in seen) && (thr == "off" || pct[w] < thr + 0)) continue
        cur[w] = ppct[w] " " prst[w]
      }
      if (qstate == "held") {
        clear = 0
        if (qreset != "-") clear = now >= qreset + 0
        else clear = ("session" in seen) && ("weekly" in seen) && thr != "off" && pct["session"] < thr + 0 && pct["weekly"] < thr + 0
        if (!clear) cur["quota"] = "- " qreset
      }
      for (w in cur) print w " " cur[w]
    }' | sort)
}

write_hold() { # write_hold <since>
  {
    printf 'format\t1\nsince\t%s\n' "$1"
    printf '%s\n' "$CUR" | awk 'NF == 3 { print "window\t" $1 "\t" $2 "\t" $3 }'
  } | mc_write "$holdf"
}

# outcome <kind> <fields...>: one drain outcome, printed and kept for the
# reset record.
outcome() {
  oc_line=$(printf '%s\t' "$@")
  oc_line=${oc_line%"$TAB"}
  printf '%s\n' "$oc_line"
  OUTCOMES="$OUTCOMES$oc_line
"
}

# handover_text <windows>: the turn a stopped session is resumed with; with
# no windows (a drain outside a reset), it claims no reset.
handover_text() {
  if [ -n "$1" ]; then
    ht_what="The $1 usage window reset at $(mc_iso "$NOW")."
  else
    ht_what="Mission control resumed held work at $(mc_iso "$NOW")."
  fi
  printf '%s\n' "[mission control: usage reset] $ht_what Your run stopped on a usage limit; pick your unit up where it stopped. Re-read its state first (git status and log, the open pull request, your step records), then continue."
}

last_line() { sanitize_printable "$(printf '%s\n' "$1" | tail -n 1)" - | cut -c1-200; }

# detached <command...>: run it in a session of its own where setsid exists.
# The runner's watcher loop leads a process group it stops whole
# (scripts/mc-watch.sh), and a session the drain starts or recovers must
# outlive the loop.
detached() {
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@"
  else
    "$@"
  fi
}

# resume_session <name> <handover file>: steer the handover in, recovering
# a dead channel first.
resume_session() {
  rs_out=$(/bin/sh "$script_dir/fleet-streamjson.sh" steer "$1" --message-file "$2" 2>&1)
  rs_rc=$?
  if [ "$rs_rc" -eq 3 ]; then
    rs_dir="$FH/streamjson/$1"
    rs_cwd=""
    [ -f "$rs_dir/cwd" ] && [ ! -L "$rs_dir/cwd" ] && rs_cwd=$(head -n 1 "$rs_dir/cwd")
    case $rs_cwd in
      /*) ;;
      *)
        outcome failed "$1" "no recorded launch directory to recover it in"
        return 0
        ;;
    esac
    rs_out=$( (cd "$rs_cwd" && detached /bin/sh "$script_dir/fleet-streamjson.sh" recover "$1" --cwd "$rs_cwd") 2>&1 </dev/null)
    rs_rc=$?
    if [ "$rs_rc" -ne 0 ]; then
      outcome failed "$1" "recover exit $rs_rc: $(last_line "$rs_out")"
      return 0
    fi
    # The resumed session takes no prompt of its own; the steer is its turn.
    rs_i=0
    while :; do
      rs_out=$(/bin/sh "$script_dir/fleet-streamjson.sh" steer "$1" --message-file "$2" 2>&1)
      rs_rc=$?
      [ "$rs_rc" -eq 3 ] && [ "$rs_i" -lt 20 ] || break
      rs_i=$((rs_i + 1))
      sleep 1
    done
  fi
  if [ "$rs_rc" -eq 0 ]; then
    outcome resumed "$1"
  else
    outcome failed "$1" "steer exit $rs_rc: $(last_line "$rs_out")"
  fi
}

# drain <windows>: launch the queue's entries and resume the sessions a
# limit stopped. Sets OUTCOMES.
drain() {
  dr_windows=$1
  OUTCOMES=""
  FH=$(mc_fleet_home) || mc_fail "cannot resolve the fleet home"
  dr_resumed=" "
  dr_ids=$(queue_ids)
  for id in $dr_ids; do
    valid_id "$id" || continue
    e="$queue/$id"
    case $(field "$e/entry" action) in
      resume)
        w=$(field "$e/entry" worker)
        mc_valid_handle "$w" || {
          outcome failed "$id" "the entry names no valid session"
          rm -rf "$e"
          continue
        }
        if [ -s "$e/brief" ]; then
          resume_session "$w" "$e/brief"
        elif handover_text "$dr_windows" >"$e/handover"; then
          resume_session "$w" "$e/handover"
        else
          outcome failed "$id" "cannot write the handover for $w"
        fi
        dr_resumed="$dr_resumed$w "
        rm -rf "$e"
        ;;
      launch)
        if ! dr_adm=$(/bin/bash "$script_dir/mc-budget.sh" admit --program "$program" session --now "$NOW" 2>&1); then
          printf 'kept\t%s\t%s\n' "$id" "$(sanitize_printable "$(printf '%s' "$dr_adm" | awk -F '\t' 'NR == 1 { print ($2 != "" ? $2 : $0) }' | cut -c1-200)" -)"
          continue
        fi
        set -- --program "$program" --kind "$(field "$e/entry" kind)" --scope "$(field "$e/entry" scope)" --brief "$e/brief"
        for k in backend cwd repo; do
          v=$(field "$e/entry" "$k")
          [ "$v" = - ] || [ -z "$v" ] || set -- "$@" "--$k" "$v"
        done
        for r in $(field "$e/entry" rules); do
          [ "$r" = - ] || set -- "$@" --rules "$r"
        done
        origin=$(field "$e/entry" origin)
        dr_errf=$(mktemp "$udir/.launch.err.XXXXXX") || {
          printf 'kept\t%s\tcannot stage the launch\n' "$id"
          continue
        }
        dr_out=$( (cd "$origin" && detached /bin/bash "$script_dir/mission-control-launch.sh" launch "$@") 2>"$dr_errf" </dev/null)
        dr_rc=$?
        dr_err=$(tail -n 1 "$dr_errf" 2>/dev/null | cut -c1-200)
        rm -f "$dr_errf"
        case $dr_rc in
          0)
            name=$(printf '%s\n' "$dr_out" | awk -F '\t' '$1 == "launch" && $2 == "name" { print $3 }')
            outcome launched "$id" "${name:--}"
            rm -rf "$e"
            ;;
          3 | 4)
            n=$(field "$e/entry" attempts)
            mc_valid_uint "$n" || n=0
            n=$((n + 1))
            if [ "$n" -ge "$MAX_ATTEMPTS" ]; then
              outcome failed "$id" "launch refused $n times (exit $dr_rc): $(sanitize_printable "$dr_err" -)"
              rm -rf "$e"
            elif [ -d "$e" ]; then
              # Kept even when the attempt cannot be counted: the next drain
              # tries it again, and the rest of this drain goes on.
              awk -F '\t' -v n="$n" 'BEGIN { OFS = "\t" } $1 == "attempts" { $2 = n } { print }' "$e/entry" | mc_write "$e/entry" \
                || printf '%s\n' "$prog: cannot record the attempt on $id" >&2
              printf 'kept\t%s\tlaunch exit %s: %s\n' "$id" "$dr_rc" "$(sanitize_printable "$dr_err" -)"
            fi
            ;;
          *)
            outcome failed "$id" "launch exit $dr_rc: $(sanitize_printable "$dr_err" -)"
            rm -rf "$e"
            ;;
        esac
        ;;
      *) printf '%s\n' "$prog: skipping queue entry $id: no action it knows" >&2 ;;
    esac
  done
  dr_list=$(/bin/bash "$script_dir/mission-control-launch.sh" list 2>/dev/null) || {
    outcome failed sessions "cannot list the sessions a limit stopped"
    dr_list=""
  }
  for w in $(printf '%s\n' "$dr_list" | P=$program awk -F '\t' '$2 == ENVIRON["P"] && $5 == "stream-json" { print $1 }'); do
    mc_valid_handle "$w" || continue
    case $dr_resumed in *" $w "*) continue ;; esac
    case $(/bin/sh "$script_dir/fleet-streamjson.sh" status "$w" 2>/dev/null) in
      "status $w limited "*) ;;
      *) continue ;;
    esac
    dr_msg=$(mktemp "$udir/.handover.XXXXXX") || {
      outcome failed "$w" "cannot write the handover"
      continue
    }
    if ! handover_text "$dr_windows" >"$dr_msg"; then
      outcome failed "$w" "cannot write the handover"
      rm -f "$dr_msg"
      continue
    fi
    resume_session "$w" "$dr_msg"
    rm -f "$dr_msg"
  done
}

summary() { # summary <lead>
  printf '%s' "$OUTCOMES" | L=$1 awk -F '\t' '
    $1 == "launched" { l++ } $1 == "resumed" { r++ } $1 == "failed" { f++ }
    END { printf "%s: %d queued unit(s) launched, %d session(s) resumed, %d failed", ENVIRON["L"], l, r, f }'
}

take_lock() {
  pw_lock_try "$udir/lock"
  case $? in
    0) trap 'pw_lock_release_all' EXIT ;;
    1)
      printf 'busy\n'
      exit 0
      ;;
    *) mc_fail "cannot take the usage lock" ;;
  esac
}

watch() {
  mc_gate_or_exit mc-usage
  take_lock
  thr=$(mc_knob mission_control_usage_hold parse_hold) || exit 1
  PREV=$(held_rows) || mc_fail "cannot read the usage hold"
  since=""
  [ -z "$PREV" ] || since=$(field "$holdf" since)
  quota || mc_fail "cannot read the claude quota hold"
  # A held quota with no usage hold recorded began at its own since.
  windows "${since:-$QUOTA_SINCE}"
  hold_now "$thr"
  printf '%s\n' "$CUR" | awk 'NF == 3 { print "held\t" $1 "\t" $2 "\t" $3 }'
  # A held quota that reads clear is a reset even with no hold recorded: its
  # stated reset can pass before any watch sees it (a paused fleet, the
  # doubled cadence), and nothing else releases it.
  if [ -z "$CUR" ] && { [ -n "$PREV" ] || [ "$QUOTA" = held ]; }; then
    gone=$(printf '%s\n' "$PREV" | awk 'NF { printf "%s%s", s, $1; s = "." }')
    [ -n "$gone" ] || gone=quota
    [ -n "$since" ] || since=$QUOTA_SINCE
    rm -f "$holdf" || mc_fail "cannot clear the usage hold"
    if [ "$QUOTA" = held ]; then
      /bin/sh "$script_dir/quota-hold.sh" resume --vendor claude --reason "the usage window reset" --now "$NOW" >/dev/null \
        || mc_fail "cannot release the claude quota hold"
      printf 'released-quota\tclaude\n'
    fi
    drain "$(printf '%s' "$gone" | tr . ' ')"
    {
      printf 'format\t1\nsince\t%s\nreset\t%s\nwindows\t%s\n' "${since:-$NOW}" "$NOW" "$gone"
      printf '%s' "$OUTCOMES" | awk 'NF { print "outcome\t" $0 }'
    } | mc_write "$lastf" || mc_fail "cannot write the reset record"
    printf 'event\tusage-reset\t%s\t%s; tell the operator what mc-usage.sh report prints\n' "$gone" \
      "$(summary "the $(printf '%s' "$gone" | tr . ' ') usage window reset")"
    return 0
  fi
  if [ -n "$CUR" ]; then
    if [ -z "$PREV" ]; then
      write_hold "$NOW" || mc_fail "cannot write the usage hold"
      first=$(printf '%s\n' "$CUR" | head -n 1)
      # shellcheck disable=SC2086 # the window, its percent and its reset
      set -- $first
      if [ "$1" = quota ]; then
        text="launches held: a session stopped on the claude usage limit"
      else
        text="launches held: the $1 usage window is at $2%"
      fi
      [ "$3" = - ] || text="$text until $(mc_iso "$3")"
      printf 'event\tusage-held\t%s\t%s; queue the next units with mc-usage.sh enqueue\n' "$1" "$text"
    else
      write_hold "$since" || mc_fail "cannot write the usage hold"
    fi
    return 0
  fi
  # No hold: an entry still queued (a launch the budget did not admit at the
  # reset, one queued since) drains now.
  if [ -n "$(queue_ids)" ]; then
    drain ""
    if [ -n "$OUTCOMES" ]; then
      if [ -f "$lastf" ]; then
        printf '%s' "$OUTCOMES" | awk 'NF { print "outcome\t" $0 }' >>"$lastf" || mc_fail "cannot extend the reset record"
      fi
      printf 'event\tusage-drained\t%s\t%s\n' "$program" "$(summary "the usage queue drained")"
    fi
  fi
}

report() {
  [ -f "$lastf" ] || return 0
  rp_since=$(field "$lastf" since)
  mc_valid_uint "$rp_since" || mc_fail "the reset record is unreadable"
  rp_kinds=""
  rp_duties=$(/bin/bash "$script_dir/mc-duties.sh" files --program "$program" 2>/dev/null) || rp_duties=""
  for d in $(printf '%s\n' "$rp_duties" | cut -f1); do
    rp_kinds="$rp_kinds $(/bin/bash "$script_dir/mc-duties.sh" get "$d" kinds 2>/dev/null | tr -d '[],')"
  done
  rp_events=$(mc_event list --program "$program" --limit 100000 2>/dev/null) || mc_fail "cannot read the events"
  printf '%s\n' "$rp_events" | S=$rp_since K="$rp_kinds" awk -F '\t' '
    BEGIN { n = split(ENVIRON["K"], k, " "); for (i = 1; i <= n; i++) dk[k[i]] = 1 }
    NF >= 4 && $2 + 0 >= ENVIRON["S"] + 0 {
      c = ""
      if ($3 == "session-landed") c = "landed"
      else if ($3 == "stall-dead" || $3 == "stream-json-worker-dead" || $3 == "watcher-stopped") c = "failed"
      else if ($3 in dk) c = "decision"
      if (c != "") { t = $5; gsub(/[^[:print:]]/, "", t); print c "\t" $4 "\t" t }
    }'
  awk -F '\t' '$1 == "outcome" && $2 == "failed" { t = $4; gsub(/[^[:print:]]/, "", t); print "failed\t" $3 "\t" t }' "$lastf"
}

case $verb in
  watch)
    [ "${#args[@]}" -eq 0 ] || usage
    watch
    ;;
  held)
    [ "${#args[@]}" -eq 0 ] || usage
    rows=$(live_rows) || mc_fail "cannot read the usage hold"
    if [ -z "$rows" ]; then
      printf 'clear\n'
      exit 1
    fi
    printf '%s\n' "$rows" | awk 'NF == 3 { print "held\t" $1 "\t" $2 "\t" $3 }'
    ;;
  enqueue)
    [ "${#args[@]}" -eq 0 ] || usage
    if [ -n "$resume" ]; then
      [ -z "$kind$scope$backend$cwd$repo$rules" ] || usage
      mc_valid_handle "$resume" || mc_usage_fail "invalid session '$(sanitize_printable "$resume")'"
      # The drain steers the session, so it must be a stream-json one this
      # program launched, and the brief one steer takes (scripts/fleet-streamjson.sh).
      sessions=$(/bin/bash "$script_dir/mission-control-launch.sh" list 2>/dev/null) || mc_fail "cannot list the sessions"
      printf '%s\n' "$sessions" | P=$program W=$resume awk -F '\t' '$1 == ENVIRON["W"] && $2 == ENVIRON["P"] && $5 == "stream-json" { f = 1 } END { exit !f }' \
        || mc_usage_fail "$resume is no stream-json session program $program launched"
      if [ -n "$brief" ] && [ -f "$brief" ] && [ -r "$brief" ]; then
        [ "$(head -c 65537 <"$brief" | wc -c | tr -d ' ')" -le 65536 ] || mc_usage_fail "--brief exceeds the 64 KiB a steered turn takes"
        [ "$(tr -d '[:space:]' <"$brief" | wc -c | tr -d ' ')" != 0 ] || mc_usage_fail "--brief holds only blanks"
      fi
      action=resume
    else
      action=launch
      kinds=$(/bin/bash "$script_dir/mission-control-launch.sh" kinds 2>/dev/null) || mc_fail "cannot list the session kinds"
      kinds=$(printf '%s\n' "$kinds" | cut -f1)
      case " $(printf '%s' "$kinds" | tr '\n' ' ') " in
        *" $kind "*) [ -n "$kind" ] || mc_usage_fail "--kind is required" ;;
        *) mc_usage_fail "unknown session kind '$(sanitize_printable "$kind")'" ;;
      esac
      valid_scope "$scope" || mc_usage_fail "refusing the scope '$(sanitize_printable "$scope")'"
      [ -n "$brief" ] || mc_usage_fail "--brief is required"
      case $backend in '' | stream-json | tmux) ;; *) mc_usage_fail "--backend is stream-json or tmux" ;; esac
      [ -z "$cwd" ] || cwd=$(abs_dir --cwd "$cwd") || exit 2
      [ -z "$repo" ] || repo=$(abs_dir --repo "$repo") || exit 2
      for r in $rules; do
        case $r in duty:* | repo:*) valid_scope "$r" && continue ;; esac
        mc_usage_fail "--rules takes a duty:<id> or repo:<name> rule scope"
      done
    fi
    if [ -n "$brief" ]; then
      [ -f "$brief" ] && [ -r "$brief" ] && [ -s "$brief" ] || mc_usage_fail "--brief must name a readable, non-empty regular file"
    fi
    origin=$(pwd -P) || mc_fail "cannot resolve the current directory"
    case $origin in *[[:cntrl:]]*) mc_usage_fail "the current directory holds a control character" ;; esac
    hex=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    case $hex in "" | *[!0-9a-f]*) mc_fail "cannot draw an entry id" ;; esac
    id="q$NOW.$hex"
    stage=$(mktemp -d "$queue/.new.XXXXXX") || mc_fail "cannot stage the entry"
    if {
      [ -z "$brief" ] || cp -- "$brief" "$stage/brief"
    } && {
      printf 'format\t1\nid\t%s\ntrigger\tusage-reset\naction\t%s\nqueued\t%s\norigin\t%s\n' "$id" "$action" "$NOW" "$origin"
      printf 'kind\t%s\nscope\t%s\nbackend\t%s\ncwd\t%s\nrepo\t%s\n' "${kind:--}" "${scope:--}" "${backend:--}" "${cwd:--}" "${repo:--}"
      rules=${rules# }
      printf 'rules\t%s\nworker\t%s\nattempts\t0\n' "${rules:--}" "${resume:--}"
    } >"$stage/entry" && mv "$stage" "$queue/$id"; then
      printf 'queued\t%s\n' "$id"
    else
      rm -rf "$stage"
      mc_fail "cannot write the entry"
    fi
    ;;
  list)
    [ "${#args[@]}" -eq 0 ] || usage
    queue_ids | while IFS= read -r id; do
      valid_id "$id" || continue
      e="$queue/$id/entry"
      a=$(field "$e" action)
      s=$(field "$e" scope)
      [ "$a" != resume ] || s=$(field "$e" worker)
      printf 'entry\t%s\t%s\t%s\t%s\n' "$id" "$(sanitize_printable "$a" -)" "$(sanitize_printable "$(field "$e" trigger)" -)" "$(sanitize_printable "$s" -)"
    done
    ;;
  drop)
    [ "${#args[@]}" -eq 1 ] || usage
    valid_id "${args[0]}" || mc_usage_fail "invalid entry id"
    [ -d "$queue/${args[0]}" ] || {
      printf '%s\n' "$prog: no queue entry ${args[0]}" >&2
      exit 3
    }
    rm -rf "${queue:?}/${args[0]}" || mc_fail "cannot drop the entry"
    printf 'dropped\t%s\n' "${args[0]}"
    ;;
  drain)
    [ "${#args[@]}" -eq 0 ] || usage
    mc_gate_or_exit mc-usage
    take_lock
    rows=$(live_rows) || mc_fail "cannot read the usage hold"
    [ -z "$rows" ] || mc_fail "launches are held until the usage window resets; the watch drains the queue then"
    drain ""
    ;;
  report)
    [ "${#args[@]}" -eq 0 ] || usage
    report
    ;;
  *) usage ;;
esac
