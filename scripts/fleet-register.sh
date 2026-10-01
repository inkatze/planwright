#!/bin/sh
# fleet-register.sh — the dispatch-time registration seam: the one place a
# dispatch seam turns "I just launched a worker" into a registry record
# (fleet-lifecycle-closure Task 3; D-12, REQ-E1.1, REQ-E1.2, REQ-E1.4,
# REQ-D1.5, REQ-K1.4).
#
# WHY A HELPER AND NOT ONE CALL SITE PER SEAM. The registry primitive
# (fleet-state.sh register) is the store; this is the seam. Every dispatch path
# owes the same three things, and owing them once per seam is how they drift:
#   1. RESOLVE THE OWNER TOKEN the same way, from the presence surface's tower
#      identity, so two towers can never be confused for one another and no
#      seam invents a second notion of who dispatched (REQ-D1.5).
#   2. WRITE THROUGH THE ONE STORE. There is no second store and no second
#      record shape; this script only assembles the call.
#   3. NEVER FAIL THE DISPATCH (REQ-E1.4). A worker that is running is a fact;
#      failing its launch because its bookkeeping did not land would trade a
#      real thing for a record of it. So a registration failure is reported
#      through THIS script's exit and a stderr warning, and every seam ignores
#      that exit.
#
# PER-FIELD DEGRADE, NOT ALL-OR-NOTHING. The store is strict: it refuses a
# malformed field rather than storing it, which is right for a store a
# destructive verb reads. But a strict store plus a pass-through seam means one
# bad optional column costs a LIVE worker its whole record — the exact leak this
# bundle exists to close. So this seam validates each optional field itself
# against the store's own grammar and drops a failing one to absent, warning as
# it goes: an inventory entry with one blank column beats no entry at all. Only
# the handle and scope are load-bearing enough to refuse outright.
#
# THE OWNER TOKEN, resolved in order, first hit wins:
#   1. --session-id <uuid> | --pid <pid>   an explicit identity, resolved
#      through fleet-presence.sh's `identity` (never re-derived here — the
#      composite shape is that surface's decision, and two derivations would
#      eventually disagree about who a tower is).
#   2. $PLANWRIGHT_TOWER_ID                the tower's ALREADY-RESOLVED token,
#      exported into a seam it invokes. This is the ordinary path: a tower
#      knows its own identity, and a seam should not have to re-derive it.
#   3. $PLANWRIGHT_TOWER_SESSION_ID | $PLANWRIGHT_TOWER_PID   the identity
#      INPUTS carried in the environment, resolved as in (1).
#   4. Nothing resolvable -> the record's owner column is the absent sentinel,
#      and a reader classifies it unknown-owner. Said once on stderr, because
#      an unattributable worker is a thing an operator should be able to see
#      coming rather than discover at reap time.
# A malformed token from any arm is refused and degrades to (4) with its own
# warning — including one that came back from the presence surface, which is
# checked here rather than trusted, so this file's stated guarantee is this
# file's to keep. Mis-attribution is worse than no attribution: a destructive
# verb reads this column.
#
# The CHECKOUT feeds the composite identity's hash, so it must be the same
# checkout the tower published under, not the worker's worktree: --checkout,
# else $PLANWRIGHT_TOWER_CHECKOUT, else the cwd's git toplevel, else the cwd.
# A seam that has cd'd into the worker's directory must pass --checkout
# explicitly; a cwd-derived hash there names a tower that exists nowhere.
#
# THE DISPATCH MARKER. Before the store write, every registration leaves one
# file, <fleet-home>/dispatch-markers/<handle>, carrying the six fields it is
# about to write (tab-separated, `-` for an absent one). The marker and the
# store write are independent: a failed store write leaves the marker, and the
# periodic sweep's reconcile (fleet-registry-reconcile.sh) rebuilds the record
# from it through --from-marker. The registry is therefore an index of what is
# on disk, and a lost write heals on the next cycle rather than costing the
# worker its place in the inventory for life. A failed marker write is warned
# and does not fail the dispatch either.
#
# THE RECONCILE'S TWO MODES go through this file so a marker meets the same
# field grammar a dispatch does, and the store is never written around it:
#   --from-marker <path>    rebuild a missing record from its marker.
#   --retire-marker <path> --expect <fields>
#                           mark closed the worker's record carrying exactly
#                           <fields> (the six the caller judged dead), then
#                           remove the marker while it still reads <fields>.
# Both refuse, rather than degrade, fields failing their grammar, a handle that
# is not the marker's filename, or a path that is not a regular file directly
# inside the marker directory: a rebuilt record feeds a destructive verb, so a
# hostile marker must never become one.
#
# Usage:
#   fleet-register.sh --handle <h> --backend <name> [--scope <s>]
#       [--state-dir <abs-dir>] [--death-handle <handle>]
#       [--checkout <dir>] [--session-id <uuid> | --pid <pid>]
#   fleet-register.sh --from-marker <path>
#   fleet-register.sh --retire-marker <path> --expect <fields>
#
# Exit codes: 0 registered (healed, retired); 1 registration failed (warned on
#   stderr — dispatch callers ignore this, by contract); 2 usage error; 3 the
#   marker modes found nothing to do (the heal: the record is already as the
#   marker says, or the marker is gone; the retirement: no live record carries
#   the expected fields); 4 the marker was refused. A retirement closes a
#   matching live record even when its marker is already gone.
#
# POSIX sh on the macOS + Linux support bar. No eval; every value is data
# (REQ-K1.5). Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=fleet-register

script_dir=$(cd "$(dirname "$0")" && pwd) || {
  echo "fleet-register: cannot resolve the script's own directory" >&2
  exit 2
}
FS="$script_dir/fleet-state.sh"
FP="$script_dir/fleet-presence.sh"

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

# printf, never echo: under dash (/bin/sh on the Linux support bar) `echo`
# re-expands backslash escapes, so a value carrying the four printable
# characters `\`, `0`, `3`, `3` would become a real ESC on the operator's
# terminal — passing straight through sanitize_printable, which strips control
# BYTES and has no such sequence to find. Every diagnostic here takes untrusted
# input, so every one of them uses printf (doctrine/security-posture.md).
warn() {
  printf '%s\n' "$me: $1" >&2
}

usage() {
  printf '%s\n' "usage: $me --handle <h> --backend <name> [--scope <s>] [--state-dir <abs-dir>] [--death-handle <handle>] [--checkout <dir>] [--session-id <uuid> | --pid <pid>]" >&2
  printf '%s\n' "       $me --from-marker <path> | --retire-marker <path> --expect <fields>" >&2
  exit 2
}

handle=""
scope=""
backend=""
state_dir=""
death_handle=""
checkout=""
session_id=""
pid=""
marker_mode=""
marker_path=""
expect=""

while [ "$#" -gt 0 ]; do
  case $1 in
    --from-marker | --retire-marker)
      [ "$#" -ge 2 ] && [ -z "$marker_mode" ] || usage
      marker_mode=$1
      marker_path=$2
      shift 2
      ;;
    --expect)
      [ "$#" -ge 2 ] || usage
      expect=$2
      shift 2
      ;;
    --handle | --scope | --backend | --state-dir | --death-handle | --checkout | --session-id | --pid)
      [ "$#" -ge 2 ] || usage
      case $1 in
        --handle) handle=$2 ;;
        --scope) scope=$2 ;;
        --backend) backend=$2 ;;
        --state-dir) state_dir=$2 ;;
        --death-handle) death_handle=$2 ;;
        --checkout) checkout=$2 ;;
        --session-id) session_id=$2 ;;
        --pid) pid=$2 ;;
      esac
      shift 2
      ;;
    *)
      warn "unexpected argument '$(sanitize_printable "$1" "(unprintable argument)")'"
      usage
      ;;
  esac
done

if [ -n "$marker_mode" ]; then
  # A marker carries the whole record; a field flag beside it would be a second
  # source for the same column.
  [ -z "$handle$scope$backend$state_dir$death_handle$checkout$session_id$pid" ] || usage
else
  [ -n "$handle" ] && [ -n "$backend" ] && [ -z "$expect" ] || usage
  # An absent scope is the store's `-` sentinel, not an invented word: a reader
  # must be able to tell "no scope was recorded" from a worker whose scope
  # really is `unknown`.
  [ -n "$scope" ] || scope="-"

  # Containment at this ingress (REQ-K1.4): a handle or scope beginning with a
  # dash is an option-injection token the moment any later consumer passes it
  # as an argv element, so it is refused here rather than stored and re-read.
  # The rest of the field grammar is the store's, checked there — this is the
  # one check the store's older, shared grammar does not make. The bare `-`
  # sentinel is exempt: it is the store's own absent marker, not a caller's
  # token.
  for arg in "$handle" "$scope"; do
    [ "$arg" = "-" ] && continue
    case $arg in
      -*)
        warn "refusing '$(sanitize_printable "$arg" "(unprintable value)")': a handle or scope may not begin with a dash"
        exit 2
        ;;
    esac
  done
fi

# Readable, not executable: every caller invokes this script as `/bin/sh <path>`,
# so the exec bit is not what the call depends on. Gating a seam on `-x` means a
# checkout with `core.fileMode=false`, an unzip, or an `rsync` without `-p`
# silently turns registration off fleet-wide with nothing on stderr.
if [ ! -r "$FS" ]; then
  if [ -n "$marker_mode" ]; then
    warn "cannot reconcile a dispatch marker: the registry store $FS is missing or unreadable (broken install)"
  else
    warn "cannot register $(sanitize_printable "$handle" "(unprintable handle)"): the registry store $FS is missing or unreadable (broken install); the dispatch continues unregistered"
  fi
  exit 1
fi

# The field grammars, kept identical to the store's (fleet-state.sh), so this
# seam never offers the store a value it will refuse — and so a malformed value
# is caught HERE, where dropping one column can still keep the record.
valid_owner() {
  vo_v=$1
  case $vo_v in
    "" | . | .. | unknown-owner | *[!A-Za-z0-9._-]*) return 1 ;;
    -*) return 1 ;;
  esac
  [ "${#vo_v}" -le 128 ]
}

valid_backend() {
  vb_v=$1
  case $vb_v in
    "" | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#vb_v}" -le 64 ]
}

valid_state_dir() {
  vsd_v=$1
  case $vsd_v in
    / | */../* | */.. | ../*) return 1 ;;
    /*) ;;
    *) return 1 ;;
  esac
  [ "${#vsd_v}" -le 4096 ] || return 1
  [ "$(printf '%s' "$vsd_v" | tr -d '\000-\037\177')" = "$vsd_v" ]
}

valid_tmux_token() {
  vtt_v=$1
  case $vtt_v in
    "" | -* | *[!A-Za-z0-9._@%-]*) return 1 ;;
  esac
  [ "${#vtt_v}" -le 128 ]
}

valid_death_handle() {
  vdh_v=$1
  case $vdh_v in
    none) return 0 ;;
    "process "*)
      vdh_pid=${vdh_v#process }
      case $vdh_pid in
        "" | 0* | *[!0-9]*) return 1 ;;
      esac
      [ "${#vdh_pid}" -le 10 ]
      ;;
    "tmux-window "*)
      vdh_rest=${vdh_v#tmux-window }
      case $vdh_rest in
        *" "*) ;;
        *) return 1 ;;
      esac
      valid_tmux_token "${vdh_rest%% *}" && valid_tmux_token "${vdh_rest#* }"
      ;;
    *) return 1 ;;
  esac
}

# keep_or_drop <kind> <value> — print the value when it passes its grammar,
# print nothing and warn when it does not. The per-field degrade: one bad
# optional column costs that column, never the record. The predicate is chosen
# by an explicit case rather than called through a variable, so every one of
# them has a visible call site.
keep_or_drop() {
  kod_kind=$1
  kod_value=$2
  [ -n "$kod_value" ] || return 0
  case $kod_kind in
    backend) valid_backend "$kod_value" && kod_ok=1 || kod_ok=0 ;;
    state-dir) valid_state_dir "$kod_value" && kod_ok=1 || kod_ok=0 ;;
    death-handle) valid_death_handle "$kod_value" && kod_ok=1 || kod_ok=0 ;;
    *) kod_ok=0 ;;
  esac
  if [ "$kod_ok" = 1 ]; then
    printf '%s\n' "$kod_value"
    return 0
  fi
  warn "dropping malformed $kod_kind '$(sanitize_printable "$kod_value" "(unprintable value)")' from the record for $(sanitize_printable "$handle" "(unprintable handle)"); the rest of the record still lands"
  return 0
}

# The worker and scope grammar (fleet-state.sh valid_field) plus this seam's
# leading-dash refusal: a marker's handle is also its filename and an argv word.
valid_handle() {
  vh_v=$1
  case $vh_v in
    "" | . | .. | -* | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#vh_v}" -le 128 ]
}

# markers_dir — print the marker directory under the resolved fleet home.
markers_dir() {
  md_root=$(/bin/sh "$FS" root 2>/dev/null) || return 1
  [ -n "$md_root" ] || return 1
  printf '%s/dispatch-markers\n' "$md_root"
}

# write_marker <line> — leave this dispatch's marker, atomically, so a reader
# never sees half a line. The directory is created owner-only and refused when
# it is not a plain directory: a marker written through a link lands wherever
# the link points.
wm_tmp=""
mm_aside=""
mm_restore=""
trap '[ -z "$wm_tmp" ] || rm -f "$wm_tmp" 2>/dev/null
  if [ -n "$mm_aside" ]; then ln "$mm_aside" "$mm_restore" 2>/dev/null; rm -f "$mm_aside" 2>/dev/null; fi' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
trap 'exit 141' PIPE
write_marker() {
  wm_dir=$(markers_dir) || return 1
  if [ -L "$wm_dir" ]; then
    return 1
  fi
  wm_umask=$(umask)
  umask 0077
  mkdir -p "$wm_dir" 2>/dev/null
  wm_tmp=$(mktemp "$wm_dir/.marker.XXXXXX" 2>/dev/null) || wm_tmp=""
  umask "$wm_umask"
  [ -n "$wm_tmp" ] || return 1
  # A directory or link at the marker's name would take the rename into it.
  if [ ! -L "$wm_dir/$handle" ] && [ ! -d "$wm_dir/$handle" ] \
    && printf '%s\n' "$1" >"$wm_tmp" 2>/dev/null && mv -f "$wm_tmp" "$wm_dir/$handle" 2>/dev/null; then
    wm_tmp=""
    return 0
  fi
  rm -f "$wm_tmp" 2>/dev/null
  wm_tmp=""
  return 1
}

# marker_path_ok <path> — the marker's place, not its content: a regular file,
# not a link, directly inside the marker directory, named as a worker handle.
# Sets mp_name. Returns 0 ok, 3 absent, 4 refused (reason on stderr), 1 when
# the fleet home cannot be resolved, which says nothing about the marker.
marker_path_ok() {
  mp_path=$1
  mp_name=${mp_path##*/}
  mp_dir=$(markers_dir) || {
    warn "cannot resolve the fleet home to check the marker against"
    return 1
  }
  if [ "${mp_path%/*}" != "$mp_dir" ]; then
    warn "refusing a marker outside $mp_dir"
    return 4
  fi
  if [ -L "$mp_dir" ] || [ ! -d "$mp_dir" ]; then
    [ -e "$mp_dir" ] || [ -L "$mp_dir" ] || return 3
    warn "refusing the marker directory $mp_dir: it is not a plain directory"
    return 4
  fi
  if [ -L "$mp_path" ]; then
    warn "refusing marker '$(sanitize_printable "$mp_name" "(unprintable name)")': it is a symbolic link"
    return 4
  fi
  [ -e "$mp_path" ] || return 3
  if [ ! -f "$mp_path" ]; then
    warn "refusing marker '$(sanitize_printable "$mp_name" "(unprintable name)")': it is not a regular file"
    return 4
  fi
  if ! valid_handle "$mp_name"; then
    warn "refusing marker '$(sanitize_printable "$mp_name" "(unprintable name)")': its name is not a worker handle"
    return 4
  fi
  return 0
}

# parse_fields <line> <name> — set handle, scope, owner, backend, state_dir and
# death_handle from one marker line. Returns 0, or 4 (reason on stderr) for
# anything but six non-empty tab-separated fields that pass their grammars
# and name the handle <name>. An empty field is refused before `read`, which
# treats a tab as whitespace and would slide the next field into its place.
parse_fields() {
  pf_shape=$(printf '%s\n' "$1" | awk -F'\t' '{ for (i = 1; i <= NF; i++) if ($i == "") e++ } END { print NR, NF, e + 0, length($0) }')
  case $pf_shape in
    "1 6 0 "*) ;;
    *)
      warn "refusing marker '$2': it is not one line of six fields"
      return 4
      ;;
  esac
  [ "${pf_shape##* }" -le 8192 ] || {
    warn "refusing marker '$2': over-length"
    return 4
  }
  IFS=$(printf '\t') read -r handle scope owner backend state_dir death_handle <<PF
$1
PF
  if [ "$handle" != "$2" ]; then
    warn "refusing marker '$2': it names another handle"
    return 4
  fi
  if ! valid_handle "$scope" && [ "$scope" != - ]; then
    warn "refusing marker '$2': malformed scope"
    return 4
  fi
  if [ "$owner" != - ] && ! valid_owner "$owner"; then
    warn "refusing marker '$2': malformed owner token"
    return 4
  fi
  if ! valid_backend "$backend"; then
    warn "refusing marker '$2': malformed backend"
    return 4
  fi
  if [ "$state_dir" != - ] && ! valid_state_dir "$state_dir"; then
    warn "refusing marker '$2': malformed state directory"
    return 4
  fi
  if [ "$death_handle" != - ] && ! valid_death_handle "$death_handle"; then
    warn "refusing marker '$2': malformed death handle"
    return 4
  fi
  return 0
}

# read_marker <path> — marker_path_ok, then parse_fields over its one line.
read_marker() {
  marker_path_ok "$1" || return $?
  rm_size=$(wc -c <"$1" 2>/dev/null | tr -d ' ') || rm_size=""
  case $rm_size in
    "" | *[!0-9]*) rm_size=99999 ;;
  esac
  if [ "$rm_size" -gt 8193 ]; then
    warn "refusing marker '$mp_name': over-length"
    return 4
  fi
  parse_fields "$(cat "$1" 2>/dev/null)" "$mp_name"
}

# drop_marker <path> <line> — remove the marker only while it still reads
# <line>. It is renamed aside first, so a re-dispatch writing a new marker
# between the comparison and the removal is never the one removed: a moved-aside
# marker that reads otherwise is linked back, unless a newer one already took
# the name. A signal mid-way links it back from the exit trap.
drop_marker() {
  mm_aside="${1%/*}/.retiring.$$"
  mm_restore=$1
  if ! mv -f "$1" "$mm_aside" 2>/dev/null; then
    mm_aside=""
    [ -e "$1" ] || [ -L "$1" ] || return 0
    return 1
  fi
  if [ "$(cat "$mm_aside" 2>/dev/null)" != "$2" ]; then
    # A newer marker already at the name supersedes this one; any other
    # failure to link back leaves it aside rather than losing it.
    if ! ln "$mm_aside" "$1" 2>/dev/null && [ ! -e "$1" ]; then
      warn "could not put back the marker at $1; it is kept as $mm_aside"
      mm_aside=""
      return 1
    fi
  fi
  rm -f "$mm_aside" 2>/dev/null
  mm_aside=""
  return 0
}

if [ -n "$marker_mode" ]; then
  if [ "$marker_mode" = --from-marker ]; then
    [ -z "$expect" ] || usage
    mm_rc=0
    read_marker "$marker_path" || mm_rc=$?
    [ "$mm_rc" = 0 ] || exit "$mm_rc"
  else
    # A retirement closes the fields the caller judged dead, never whatever the
    # marker says by now: a re-dispatch may have rewritten it in between.
    [ -n "$expect" ] || usage
    mm_rc=0
    marker_path_ok "$marker_path" || mm_rc=$?
    case $mm_rc in
      0 | 3) ;;
      *) exit "$mm_rc" ;;
    esac
    parse_fields "$expect" "$mp_name" || exit 4
  fi
  set -- "$handle" "$scope"
  [ "$owner" = - ] || set -- "$@" --owner "$owner"
  set -- "$@" --backend "$backend"
  [ "$state_dir" = - ] || set -- "$@" --state-dir "$state_dir"
  [ "$death_handle" = - ] || set -- "$@" --death-handle "$death_handle"
  if [ "$marker_mode" = --from-marker ]; then
    st_rc=0
    /bin/sh "$FS" register --heal "$@" >/dev/null || st_rc=$?
    case $st_rc in
      0 | 3) exit "$st_rc" ;;
    esac
    warn "could not rebuild the record for $handle from its marker; the next sweep retries"
    exit 1
  fi
  st_rc=0
  /bin/sh "$FS" retire "$@" >/dev/null || st_rc=$?
  case $st_rc in
    0) ;;
    3)
      # Nothing to close: only an earlier retirement of these very fields
      # leaves the marker to finish removing.
      mm_last=$(/bin/sh "$FS" registry 2>/dev/null | awk -F'\t' -v w="$handle" '($2 "") == (w "") { l = $0 } END { print l }')
      [ "$(printf '%s\n' "$mm_last" | cut -f2-8)" = "$expect$(printf '\t')closed" ] || exit 3
      ;;
    *)
      warn "could not retire the record for $handle; the next sweep retries"
      exit 1
      ;;
  esac
  # The record is closed either way; a marker left behind is finished on the
  # next pass, so this exit still reports the retirement.
  drop_marker "$marker_path" "$expect" \
    || warn "retired $handle but could not remove its marker; the next sweep finishes it"
  exit "$st_rc"
fi

resolve_checkout() {
  if [ -n "$checkout" ]; then
    printf '%s\n' "$checkout"
    return 0
  fi
  if [ -n "${PLANWRIGHT_TOWER_CHECKOUT:-}" ]; then
    printf '%s\n' "$PLANWRIGHT_TOWER_CHECKOUT"
    return 0
  fi
  rc_top=$(git rev-parse --show-toplevel 2>/dev/null) || rc_top=""
  if [ -n "$rc_top" ]; then
    printf '%s\n' "$rc_top"
    return 0
  fi
  pwd
}

# via_presence <flag> <value> — the tower identity for an explicit identity
# input, through the presence surface and nowhere else. Its answer is still
# checked against the owner grammar here: the guarantee this file's header
# states is this file's to keep, and an unchecked value would reach the store,
# be refused there, and take the whole record with it.
via_presence() {
  [ -r "$FP" ] || return 1
  vp_out=$(/bin/sh "$FP" identity --checkout "$(resolve_checkout)" "$1" "$2" 2>/dev/null) || return 1
  valid_owner "$vp_out" || return 1
  printf '%s\n' "$vp_out"
}

# resolve_owner — print the owner token, or nothing when none is resolvable.
resolve_owner() {
  if [ -n "$session_id" ]; then
    via_presence --session-id "$session_id" && return 0
    warn "could not resolve a tower identity from --session-id; recording this dispatch as unknown-owner"
    return 1
  fi
  if [ -n "$pid" ]; then
    via_presence --pid "$pid" && return 0
    warn "could not resolve a tower identity from --pid; recording this dispatch as unknown-owner"
    return 1
  fi
  if [ -n "${PLANWRIGHT_TOWER_ID:-}" ]; then
    if valid_owner "$PLANWRIGHT_TOWER_ID"; then
      printf '%s\n' "$PLANWRIGHT_TOWER_ID"
      return 0
    fi
    warn "refusing malformed \$PLANWRIGHT_TOWER_ID '$(sanitize_printable "$PLANWRIGHT_TOWER_ID" "(unprintable token)")'; recording this dispatch as unknown-owner rather than mis-attributing it"
    return 1
  fi
  if [ -n "${PLANWRIGHT_TOWER_SESSION_ID:-}" ]; then
    via_presence --session-id "$PLANWRIGHT_TOWER_SESSION_ID" && return 0
    warn "could not resolve a tower identity from \$PLANWRIGHT_TOWER_SESSION_ID; recording this dispatch as unknown-owner"
    return 1
  fi
  if [ -n "${PLANWRIGHT_TOWER_PID:-}" ]; then
    via_presence --pid "$PLANWRIGHT_TOWER_PID" && return 0
    warn "could not resolve a tower identity from \$PLANWRIGHT_TOWER_PID; recording this dispatch as unknown-owner"
    return 1
  fi
  warn "no tower identity available (set \$PLANWRIGHT_TOWER_ID, or pass --session-id/--pid); recording this dispatch as unknown-owner"
  return 1
}

owner=$(resolve_owner) || owner=""
backend=$(keep_or_drop backend "$backend")
state_dir=$(keep_or_drop state-dir "$state_dir")
death_handle=$(keep_or_drop death-handle "$death_handle")

# A backend that failed its grammar leaves the record without the one field that
# says which rung to close it on, which is not a record worth writing.
if [ -z "$backend" ]; then
  warn "cannot register $(sanitize_printable "$handle" "(unprintable handle)"): no usable backend name"
  exit 1
fi

set -- register "$handle" "$scope" --if-changed
[ -n "$owner" ] && set -- "$@" --owner "$owner"
set -- "$@" --backend "$backend"
[ -n "$state_dir" ] && set -- "$@" --state-dir "$state_dir"
[ -n "$death_handle" ] && set -- "$@" --death-handle "$death_handle"

# The marker comes first, so a store write that fails, or a dispatch killed
# between the two, still leaves what the next sweep heals from. A handle or
# scope the store would refuse gets no marker: the handle is its filename, and
# nothing the store refuses is worth rebuilding.
marked=0
if valid_handle "$handle" && { [ "$scope" = - ] || valid_handle "$scope"; }; then
  if write_marker "$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$handle" "$scope" "${owner:--}" \
    "$backend" "${state_dir:--}" "${death_handle:--}")"; then
    marked=1
  else
    # An earlier dispatch's marker left at this name would later be read as
    # this worker's and rebuild a long-dead record, so it goes.
    wf_dir=$(markers_dir) || wf_dir=""
    if [ -n "$wf_dir" ] && [ -f "$wf_dir/$handle" ] && [ ! -L "$wf_dir/$handle" ]; then
      rm -f "$wf_dir/$handle" 2>/dev/null
    fi
    warn "could not write the dispatch marker for $(sanitize_printable "$handle" "(unprintable handle)"); no sweep can retire its record, and if the registry write below fails too, none can rebuild it"
  fi
fi

st_rc=0
/bin/sh "$FS" "$@" >/dev/null || st_rc=$?
case $st_rc in
  0 | 3) exit 0 ;;
esac
if [ "$marked" = 1 ]; then
  warn "failed to register $(sanitize_printable "$handle" "(unprintable handle)") in the fleet registry; the dispatch stands, and the next sweep rebuilds the record from its dispatch marker"
else
  warn "failed to register $(sanitize_printable "$handle" "(unprintable handle)") in the fleet registry; the dispatch stands, but with no dispatch marker either, this worker will not appear in the fleet inventory"
fi
exit 1
