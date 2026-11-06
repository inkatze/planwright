#!/bin/sh
# mission-control-launch.sh — the one launcher for every session kind mission
# control starts, and the verb that retires them. A launch delivers the brief
# (to a repository-changing kind, with the verification cadence), the rules
# in scope, the kind's settings profile, its model tier and its name
# (and to a mission-control session its registry row's token, as
# PLANWRIGHT_MC_TOKEN), then registers owner, kind and scope. `--help` prints
# the usage, the output shapes and the exit codes.
#
# Emits: markdown
#
# POSIX sh; no eval; every input is data. Pathname expansion is disabled.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=mission-control-launch
FORMAT=1

script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
if [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "$me: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"
[ -r "$script_dir/lock-lib.sh" ] || {
  printf '%s\n' "$me: lock-lib.sh is missing or unreadable (broken install)" >&2
  exit 2
}
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh"
NL='
'

die() {
  printf '%s\n' "$me: $1" >&2
  exit "${2:-2}"
}

help_text() {
  cat <<'EOF'
usage:
  mission-control-launch.sh launch --program <p> --kind <kind> --scope <s>
      --brief <file> [--rules <rule-scope>]... [--backend stream-json|tmux]
      [--cwd <abs-dir>] [--repo <abs-dir>]
  mission-control-launch.sh name --program <p> --kind <kind> --scope <s>
  mission-control-launch.sh retire <name>|<worker>
  mission-control-launch.sh list
  mission-control-launch.sh kinds

<kind> is one of `kinds`; <scope> holds letters, digits and . _ = @ : - only,
at most 128. --rules adds a rule-store scope (duty:<id> or repo:<name>);
program rules ride every launch. The rung is --backend, else the
mission_control_launch_backend knob.

A kind that changes a repository (worker, reviewer, ad-hoc) starts in its
own worktree, never a primary checkout. With no --cwd, the dispatch
machinery creates one in the repository holding --repo (default: the
current directory), on the unit's branch when it exists, off the default
branch otherwise. A scope with one colon, <spec>:task-<id>, names a task
unit (branch planwright/<spec>/task-<id>; a one-colon scope of that shape
outside the task grammar is refused); any other scope gets a flight branch
derived from the name. A
worktree already holding that branch is reused only when no live session
runs there: another registered launch, or a process working in it other
than the launcher, its callers and tmux. --cwd names a worktree instead,
accepted only when it is not a primary checkout and no live session uses
it; it takes neither --repo nor a task scope. Such a launch's brief, unless
its first line is a skill command (`/<name>`, alone or before a space),
also carries the verification cadence: the in-run points and the
`step-run.sh audit` that readiness repeats. Every other kind starts in
--cwd, else the current directory, and takes no --repo.

The name is derived from program, kind and scope alone, so the same inputs
always name the same session, and a name with a registry row is held until
it is retired. No output names a pane, window or attach hint.

Output, tab separated:
  launch   launch <field> <value> for name, kind, program, owner, scope,
           backend, profile, tier, brief, cwd
  name     the name alone
  retire   retire <name> released|partial released=<classes> held=<classes>,
           over the classes process, pane, registry, attention and row
  list     <name> <program> <kind> <scope> <backend> <launched epoch>
  kinds    <kind> <profile> <allocation key>

A launch reserves the name with a complete row (backend, launcher pid and a
token) before it starts anything, and a session that started but could not
be recorded is stopped. A mission-control session starts holding that token
as PLANWRIGHT_MC_TOKEN, which no other kind is handed. A retire refuses a launch still in flight, closes the
process or window first, and releases the fleet record, the attention row
and the row only once it is gone; a window counts as closed only when tmux
lists the windows and that one is not among them. A session with no row
(one an older planwright or /orchestrate launched, named by its worker
handle) is retired through its stream-json runtime directory: the rung's
final close, then its fleet record and attention row, over the classes
process, registry and attention, refused while the rung's own launch,
recover or relaunch of it is in flight; with no such directory either, the
refusal names the headless and tmux stops.

Exit codes: 0 done; 1 the rung failed to start the session (or it started,
could not be recorded, and was stopped), or it started or may have and could
not be closed, so its row stays for a retire, or a retire released only part
of it; 2 usage, an invalid value, or a registry row or launch directory the
launcher cannot read or write; 3 the name is held, a launch or retire of it
is in flight, a live session uses its worktree, another launch is placing
its branch, or a dispatch holds it or cannot say (launch), or there is
neither a row nor a stream-json worker of that name, a launch, recover,
relaunch or another retire of it is in flight, or the caller runs inside
its window (retire); 4 a launch refused before it started: no readable
profile, an unresolvable rung knob, no resolvable tier (an unreachable
allocation store or a malformed tier knob), the admission gate withholding
it, a broken allocation install, a program that is not configured, rules
that would not render, a worktree that could not be created, a named
directory that is not a worktree other than a primary checkout, a worktree
path holding a control character, or any other refusal by the rung.
EOF
}

usage() {
  help_text >&2
  exit 2
}

# kind_row <kind> — set K_PROFILE and K_KEY, or return 1 for an unknown kind.
kind_row() {
  case $1 in
    tower) K_PROFILE=tower K_KEY=orchestrate_dispatch ;;
    orchestrator) K_PROFILE=tower K_KEY=bookkeeping ;;
    worker) K_PROFILE=worker K_KEY=execution ;;
    reviewer) K_PROFILE=worker K_KEY=execute_step ;;
    ad-hoc) K_PROFILE=worker K_KEY=offload ;;
    mission-control) K_PROFILE=mission-control K_KEY=orchestrate_dispatch ;;
    *) return 1 ;;
  esac
}
KINDS="tower orchestrator worker reviewer ad-hoc mission-control"

# changes_repo <kind> — 0 for a kind that starts in its own worktree.
changes_repo() {
  case $1 in
    worker | reviewer | ad-hoc) return 0 ;;
  esac
  return 1
}

valid_program() {
  case $1 in
    [a-z]*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!a-z0-9-]* | *--* | *-) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

valid_scope() {
  case $1 in
    '' | -* | *[!A-Za-z0-9._=@:-]* | . | ..) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

valid_name() {
  case $1 in
    mc-*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# valid_window <id> — a tmux window id: @ and digits only.
valid_window() {
  case $1 in
    @[0-9]*) ;;
    *) return 1 ;;
  esac
  case ${1#@} in
    *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 12 ]
}

sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    return 1
  fi
}

# session_name <program> <kind> <scope> — the brief is left out on purpose:
# a relaunch with a reworded brief must find the name its predecessor holds.
# A program name too long for the readable form falls back to a longer hash.
session_name() {
  sn_h=$(printf '%s\t%s\t%s' "$1" "$2" "$3" | sha256_hex) || die "no SHA-256 tool (sha256sum or shasum) to derive the session name"
  sn_name="mc-$1-$2-$(printf '%s' "$sn_h" | cut -c1-10)"
  [ "${#sn_name}" -le 64 ] || sn_name="mc-$2-$(printf '%s' "$sn_h" | cut -c1-16)"
  printf '%s\n' "$sn_name"
}

# The registry and the composed briefs are runtime state, so they live under
# the fleet home beside the fleet registry, never in the program home.
fleet_home() {
  FH=$(/bin/sh "$script_dir/fleet-state.sh" root 2>/dev/null </dev/null) || die "cannot resolve the fleet home for the launcher's registry"
  case $FH in
    /*) ;;
    *) die "the fleet home is not an absolute path" ;;
  esac
  REG="$FH/mission-control/sessions"
  LAUNCHES="$FH/mission-control/launch"
}

# private_dir <dir> — create it owner-only; refuse a symbolic link.
private_dir() {
  [ ! -L "$1" ] || die "refusing $(sanitize_printable "$1"): a symbolic link"
  (umask 077 && mkdir -p -- "$1") 2>/dev/null || die "cannot create $(sanitize_printable "$1")"
  chmod -- 700 "$1" 2>/dev/null || :
}

# row_get <file> <key> — print the value of <key> in a registry row.
row_get() {
  awk -F '\t' -v k="$2" '$1 == k { print substr($0, length(k) + 2); exit }' "$1"
}

# row_format_ok <file> — 0 when the row's format field is this launcher's.
row_format_ok() {
  [ "$(row_get "$1" format)" = "$FORMAT" ]
}

# row_check <file> — refuse a row whose format this launcher does not know.
row_check() {
  row_format_ok "$1" \
    || die "refusing the registry row $(sanitize_printable "$1"): its format field is $(sanitize_printable "$(row_get "$1" format)" missing), not $FORMAT" 2
}

resolve_backend() {
  if [ -n "$backend" ]; then
    return 0
  fi
  backend=$(/bin/sh "$script_dir/resolve-config-knob.sh" --key mission_control_launch_backend \
    --type enum --values 'stream-json tmux' --fallback stream-json </dev/null) \
    || die "cannot resolve mission_control_launch_backend" 4
}

# name_lock <name> — hold the per-name lock a launch's reservation and a whole
# retire take, so neither acts on a row the other is changing.
name_lock() {
  private_dir "$FH/mission-control/locks"
  pw_lock_trap_install
  pw_lock_try "$FH/mission-control/locks/$1"
  case $? in
    0) ;;
    1) die "another launch or retire of $1 is in flight" 3 ;;
    *) die "cannot take the lock for $1" 2 ;;
  esac
  NAME_LOCK="$FH/mission-control/locks/$1"
}

name_unlock() {
  [ -z "${NAME_LOCK:-}" ] || pw_lock_release "$NAME_LOCK" || :
  NAME_LOCK=''
}

new_token() {
  nt=$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n') || nt=''
  [ -n "$nt" ] || nt=$(date +%s)
  printf '%s-%s\n' "$$" "$nt"
}

# row_write <row> <token> <state> — write the row from the launch variables,
# into a temporary file renamed over the row only while the row on disk is
# still this launch's (it carries <token>).
row_write() {
  rw_tmp="$1.tmp.$$"
  if ! (umask 077 && {
    printf 'format\t%s\n' "$FORMAT"
    printf 'name\t%s\n' "$name"
    printf 'state\t%s\n' "$3"
    printf 'token\t%s\n' "$2"
    printf 'pid\t%s\n' "$$"
    printf 'program\t%s\n' "$program"
    printf 'owner\t%s\n' "$owner"
    printf 'kind\t%s\n' "$kind"
    printf 'scope\t%s\n' "$scope"
    printf 'backend\t%s\n' "$backend"
    printf 'handle\t%s\n' "$handle"
    printf 'profile\t%s\n' "$profile"
    printf 'tier\t%s\n' "$tier"
    printf 'brief\t%s\n' "$composed"
    printf 'cwd\t%s\n' "${cwd:--}"
    printf 'task\t%s\n' "${task:--}"
    printf 'primary\t%s\n' "${placed_primary:--}"
    printf 'marker\t%s\n' "${PLACED_MARKER:--}"
    printf 'launched\t%s\n' "$launched"
  } >"$rw_tmp"); then
    rm -f "$rw_tmp"
    return 1
  fi
  # A non-empty row is rewritten only while it is still this launch's; a
  # launched row is never created where a retire removed the reservation.
  if [ -s "$1" ] && [ "$(row_get "$1" token)" != "$2" ]; then
    rm -f "$rw_tmp"
    return 1
  fi
  if [ "$3" = launched ] && [ ! -s "$1" ]; then
    rm -f "$rw_tmp"
    return 1
  fi
  mv -f -- "$rw_tmp" "$1" || {
    rm -f "$rw_tmp"
    return 1
  }
}

# stop_session <backend> <handle> — close a session this launch started; 0
# only on proof it is gone.
stop_session() {
  case $1 in
    stream-json)
      ss_out=$(/bin/sh "$script_dir/fleet-streamjson.sh" stop "$2" --final </dev/null 2>/dev/null)
      ss_rc=$?
      case $ss_out in
        "stop $2 stopped "* | "stop $2 already-closed") return 0 ;;
      esac
      # An unknown worker never got a state directory: nothing ran.
      [ "$ss_rc" = 2 ] && [ ! -d "$FH/streamjson/$2" ] && return 0
      return 1
      ;;
    tmux)
      release_pane "$name" "$2"
      return
      ;;
  esac
  return 1
}

# release_fleet_entry <name> <handle> — retire the fleet registry marker the
# rung wrote under <handle> and clear the session's attention row; 0 only
# when both are gone.
release_fleet_entry() {
  rf_marker="$FH/dispatch-markers/$2"
  if [ "$2" != - ] && { [ -e "$rf_marker" ] || [ -L "$rf_marker" ]; }; then
    rf_fields=$(cat "$rf_marker" 2>/dev/null) || rf_fields=''
    /bin/sh "$script_dir/fleet-register.sh" --retire-marker "$rf_marker" --expect "$rf_fields" >/dev/null 2>&1 </dev/null || :
    if [ -e "$rf_marker" ] || [ -L "$rf_marker" ]; then return 1; fi
  fi
  /bin/sh "$script_dir/fleet-attention.sh" clear "$1" >/dev/null 2>&1 </dev/null
}

# primary_checkout <dir> — print the physical primary checkout of the
# repository holding <dir>; 1 when there is none (no repository, or a bare one).
primary_checkout() {
  pc_common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null </dev/null) || return 1
  case $pc_common in
    */.git) ;;
    *) return 1 ;;
  esac
  (cd "${pc_common%/.git}" 2>/dev/null && pwd -P)
}

# is_linked_worktree <dir> — 0 when the physical <dir> is the top of a git
# worktree other than its repository's primary checkout.
is_linked_worktree() {
  lw_top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null </dev/null) || return 1
  lw_top=$(cd "$lw_top" 2>/dev/null && pwd -P) || return 1
  [ "$lw_top" = "$1" ] || return 1
  lw_git=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null </dev/null) || return 1
  lw_common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null </dev/null) || return 1
  [ "$lw_git" != "$lw_common" ]
}

# branch_holder <primary> <branch> — print the physical worktree that has
# <branch> checked out, empty when none does or its directory is gone (git
# still lists a worktree deleted by hand); 1 when the list cannot be read.
branch_holder() {
  bh_list=$(git -C "$1" worktree list --porcelain 2>/dev/null </dev/null) || return 1
  bh_path=$(printf '%s\n' "$bh_list" | WANT="branch refs/heads/$2" awk '
    index($0, "worktree ") == 1 { p = substr($0, 10) }
    $0 == ENVIRON["WANT"] { print p; exit }')
  [ -n "$bh_path" ] || return 0
  (cd "$bh_path" 2>/dev/null && pwd -P) || :
}

# own_pids — print this process and its ancestors, which run wherever the
# caller does and are not a session using the directory.
own_pids() {
  op_pid=$$
  op_n=0
  while [ -n "$op_pid" ] && [ "$op_pid" -gt 1 ] 2>/dev/null && [ "$op_n" -lt 64 ]; do
    printf '%s\n' "$op_pid"
    # busybox ps has no -p; procfs gives the parent wherever it exists. The
    # command name may hold spaces and parentheses, so fields count from the
    # last one.
    if [ -r "/proc/$op_pid/stat" ]; then
      op_pid=$(sed 's/.*) //' "/proc/$op_pid/stat" 2>/dev/null | cut -d' ' -f2)
    else
      op_pid=$(ps -o ppid= -p "$op_pid" 2>/dev/null | tr -d ' ')
    fi
    op_n=$((op_n + 1))
  done
}

# dir_users <dir> — print the pid of every visible process whose working
# directory is <dir> or below it; 1 when the process table will not show this
# process its own, so nothing it lists can be trusted as complete.
dir_users() {
  # Its own helpers would otherwise inherit the caller's directory.
  cd / || return 1
  if [ -L /proc/self/cwd ]; then
    # A procfs that will not show this process its own working directory
    # shows none of the operator's either.
    readlink "/proc/$$/cwd" >/dev/null 2>&1 || return 1
    # One find over procfs: a readlink per process costs seconds on a busy
    # host. The path is escaped so -lname matches it literally.
    if [ -n "$(find "/proc/$$/cwd" -prune -lname '*' 2>/dev/null)" ]; then
      du_glob=$(printf '%s' "$1" | sed 's/[][*?\\]/\\&/g')
      find /proc -mindepth 2 -maxdepth 2 -name cwd \( -lname "$du_glob" -o -lname "$du_glob/*" \) 2>/dev/null \
        | awk -F / '$3 ~ /^[0-9]+$/ { print $3 }'
      return 0
    fi
    # busybox find has no -lname, and a failed find reads as no live user.
    du_d=$1
    set +f
    set -- /proc/[0-9]*/cwd
    set -f
    for du_c in "$@"; do
      du_t=$(readlink "$du_c" 2>/dev/null) || continue
      case $du_t in
        "$du_d" | "$du_d"/*)
          du_p=${du_c#/proc/}
          printf '%s\n' "${du_p%/cwd}"
          ;;
      esac
    done
    return 0
  fi
  command -v lsof >/dev/null 2>&1 || return 1
  du_out=$(lsof -a -d cwd -F pn 2>/dev/null </dev/null)
  [ -n "$du_out" ] || return 1
  printf '%s\n' "$du_out" | D="$1/" awk '
    /^p/ { pid = substr($0, 2) }
    /^n/ { c = substr($0, 2) "/"; if (index(c, ENVIRON["D"]) == 1) print pid }'
}

# live_in <dir> — 0 when a live session may run in <dir>, naming it in
# LIVE_BY: another registered launch there, or a process working in it other
# than this launch's own and a tmux server or client (which keep the
# directory they were started from). A process table that cannot be read
# cannot tell, which counts as live.
live_in() {
  LIVE_BY=''
  set +f
  set -- "$1" "$REG"/mc-*
  set -f
  li_d=$1
  shift
  for li_f in "$@"; do
    [ -f "$li_f" ] && [ ! -L "$li_f" ] || continue
    case ${li_f##*/} in "$name" | *.tmp.*) continue ;; esac
    if ! li_c=$(row_get "$li_f" cwd 2>/dev/null); then
      [ -e "$li_f" ] || continue
      LIVE_BY="the session of the unreadable row ${li_f##*/}"
      return 0
    fi
    case $li_c in
      "$li_d" | "$li_d"/*)
        LIVE_BY="session ${li_f##*/}"
        return 0
        ;;
    esac
  done
  if ! li_users=$(dir_users "$li_d"); then
    LIVE_BY="an unknown session (this host's process directories cannot be read)"
    return 0
  fi
  [ -n "$li_users" ] || return 1
  li_own=$(own_pids)
  for li_p in $li_users; do
    case "$NL$li_own$NL" in *"$NL$li_p$NL"*) continue ;; esac
    # Skipped only on proof it is gone since the scan; a ps that cannot
    # answer leaves it live.
    if [ -d /proc/self ]; then
      [ -e "/proc/$li_p" ] || continue
    fi
    if li_comm=$(ps -o comm= -p "$li_p" 2>/dev/null); then
      case ${li_comm##*/} in tmux*) continue ;; esac
    elif [ ! -d /proc/self ] && ps -o comm= -p "$$" >/dev/null 2>&1; then
      continue
    fi
    LIVE_BY="process $li_p"
    return 0
  done
  return 1
}

# marker_cmd write|clear <primary> <spec>/<id> — write or clear the unit's
# dispatch marker in the spec root of the repository at <primary>.
marker_cmd() {
  mk_root=$(cd -- "$2" && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$script_dir/resolve-root.sh" spec 2>/dev/null </dev/null) \
    || return 1
  /bin/sh "$script_dir/orchestrate-marker.sh" "$1" "$mk_root/${3%/*}" "${3#*/}" >/dev/null 2>&1 </dev/null
}

# branch_lock <primary> <branch> — hold the lock placement takes for one
# branch: two names can share a branch, so the name lock alone would let both
# start in one worktree. Released once the row records cwd.
branch_lock() {
  bl_hash=$(printf '%s\t%s' "$1" "$2" | sha256_hex) && [ -n "$bl_hash" ] \
    || refuse "refusing to launch $name: no SHA-256 tool to key the branch lock" 2
  placed_primary=$1
  BRANCH_LOCK="$FH/mission-control/locks/branch-$(printf '%s' "$bl_hash" | cut -c1-16)"
  pw_lock_try "$BRANCH_LOCK"
  case $? in
    0) ;;
    1) refuse "refusing to launch $name: another launch is placing $2" 3 ;;
    *) refuse "refusing to launch $name: cannot take the lock for $2" 2 ;;
  esac
}

# place_worktree — set cwd to the worktree a repository-changing launch runs
# in, or refuse the launch. Runs under the reservation, so refuse releases
# it; on success it holds the branch lock until the caller has recorded cwd.
place_worktree() {
  if [ -n "$cwd" ]; then
    is_linked_worktree "$cwd" \
      || refuse "refusing to launch $name in $(sanitize_printable "$cwd"): a $kind starts in a worktree other than a primary checkout" 4
    pw_primary=$(primary_checkout "$cwd") || refuse "refusing to launch $name: cannot find the repository of $(sanitize_printable "$cwd")" 4
    pw_branch=$(git -C "$cwd" symbolic-ref -q HEAD 2>/dev/null </dev/null) || pw_branch="detached:$cwd"
    branch_lock "$pw_primary" "${pw_branch#refs/heads/}"
    ! live_in "$cwd" || refuse "refusing to launch $name: $LIVE_BY runs in $(sanitize_printable "$cwd")" 3
    return 0
  fi
  pw_from=${repo:-$(pwd -P)}
  pw_primary=$(primary_checkout "$pw_from") \
    || refuse "refusing to launch $name: $(sanitize_printable "$pw_from") is in no repository with a primary checkout to create its worktree from" 4
  # Both branch shapes are fleet-dispatch-worktree.sh's; keep them in step.
  if [ -n "$task" ]; then
    pw_branch="planwright/${task%/*}/task-${task#*/}"
    set -- dispatch "${task%/*}" "${task#*/}"
  else
    # Derived from the name, so a relaunch finds the branch its predecessor
    # started; eight hex digits are the flight-id grammar's uid.
    pw_flight="${name%-*}-$(printf '%s' "${name##*-}" | cut -c1-8)"
    pw_branch="planwright/flight/$pw_flight"
    set -- dispatch --flight "$pw_flight"
  fi
  branch_lock "$pw_primary" "$pw_branch"
  pw_held=$(branch_holder "$pw_primary" "$pw_branch") \
    || refuse "refusing to launch $name: cannot read the worktree list of $(sanitize_printable "$pw_primary")" 4
  if [ -n "$pw_held" ]; then
    [ "$pw_held" != "$pw_primary" ] \
      || refuse "refusing to launch $name: $pw_branch is checked out in the primary checkout" 4
    is_linked_worktree "$pw_held" \
      || refuse "refusing to launch $name: $(sanitize_printable "$pw_held"), which holds $pw_branch, is not a worktree of its own" 4
    ! live_in "$pw_held" \
      || refuse "refusing to launch $name: $LIVE_BY runs in $(sanitize_printable "$pw_held"), which holds $pw_branch" 3
    cwd=$pw_held
    # A reused task worktree is marked in flight as a placed one is.
    if [ -n "$task" ]; then
      if marker_cmd write "$pw_primary" "$task"; then
        PLACED_MARKER=1
      else
        printf '%s\n' "$me: the dispatch marker for $task was not written; the unit may read as not in flight" >&2
      fi
    fi
    return 0
  fi
  pw_out=$(cd "$pw_primary" && /bin/sh "$script_dir/fleet-dispatch-worktree.sh" "$@" \
    --repo-root "$pw_primary" --no-attach </dev/null)
  pw_rc=$?
  # A task placement has written the unit's dispatch marker by now.
  [ "$pw_rc" != 0 ] || [ -z "$task" ] || PLACED_MARKER=1
  case $pw_rc in
    0) ;;
    3) refuse "refusing to launch $name: a dispatch holds $pw_branch, or cannot say whether one does (fleet-dispatch-worktree exit 3)" 3 ;;
    *) refuse "refusing to launch $name: its worktree could not be created (fleet-dispatch-worktree exit $pw_rc)" 4 ;;
  esac
  pw_wt=$(printf '%s\n' "$pw_out" | awk -F '\t' '$1 == "dispatch" && $2 == "worktree" { print $3; exit }')
  if [ -z "$pw_wt" ] || ! cwd=$(cd "$pw_wt" 2>/dev/null && pwd -P); then
    refuse "refusing to launch $name: the dispatch machinery reported no worktree" 4
  fi
}

# cadence_section <name> [<spec>/<id>] — the configured cadence a
# repository-changing session runs, by reference to the one procedure that
# fires it, with the mappings its unit needs, and the audit readiness repeats.
cadence_section() {
  cs_root=$(cd "$script_dir/.." && pwd -P) || return 1
  if [ -n "${2:-}" ]; then
    cs_unit="task ${2#*/} of spec ${2%/*}"
    cs_ctx="\`PLANWRIGHT_STEP_UNIT_KIND=task\`, spec id \`${2%/*}\`, task id \`${2#*/}\`"
  else
    cs_unit="a specless session"
    cs_ctx="\`PLANWRIGHT_STEP_UNIT_KIND=flight\`, empty spec and task ids"
  fi
  cat <<EOF

## Verification cadence

This session changes a repository, so it runs the configured cadence. Fire
every in-run point (\`pre-implementation\`, \`pre-ci\`, \`convergence\`,
\`pre-pr\`, \`post-pr\`) at its moment by \`/execute-task\`'s *Points*
procedure, read from \`$cs_root/skills/execute-task/SKILL.md\`, with these
mappings for $cs_unit:

- Resolve every point \`--unattended\`, under \`$cs_root/scripts/\`.
- Export the step context with $cs_ctx, this branch,
  its base branch and this worktree; an isolated step's launch tier takes the
  unit \`mission-control:$1\`.
- Wherever the procedure parks or stops the unit, stop and report the point,
  the step and what it printed to mission control instead; write nothing to
  any \`tasks.md\` or other spec state.

Before the push, run \`$cs_root/scripts/step-run.sh audit --through pre-pr\`;
before reporting the PR done, \`$cs_root/scripts/step-run.sh audit --through post-pr --base origin/<base branch>\`.
Close every gap it names first. Mission control's readiness check runs the
same audit and refuses a PR with a gap. The PR body carries the rendered
records (\`$cs_root/scripts/step-record.sh render\`) in a \`<details>\` block.
EOF
}

# valid_task <spec>/<id> — the unit grammar fleet-dispatch-worktree.sh
# enforces, checked here so a bad value is a usage error.
valid_task() {
  case $1 in
    */*/* | *[!a-z0-9./-]*) return 1 ;;
    */*) ;;
    *) return 1 ;;
  esac
  vt_spec=${1%/*} vt_id=${1#*/}
  case $vt_spec in
    '' | [!a-z0-9]* | *[!a-z0-9-]* | flight) return 1 ;;
  esac
  [ "${#vt_spec}" -le 64 ] || return 1
  case $vt_id in
    '' | *[!0-9.]* | .* | *. | *.*.*) return 1 ;;
  esac
}

# abs_dir <flag> <path> — print the physical directory, or die naming the
# flag. A control character would forge a line of the registry row.
abs_dir() {
  case $2 in
    /*) ;;
    *) die "$1 must be an absolute path" ;;
  esac
  ad_dir=$(cd -- "$2" 2>/dev/null && pwd -P) || die "$1 is not an existing directory"
  case $ad_dir in
    *[[:cntrl:]]*) die "refusing $1: its path holds a control character" ;;
  esac
  printf '%s\n' "$ad_dir"
}

# --------------------------------------------------------------------------

cmd_launch() {
  program='' kind='' scope='' brief='' backend='' cwd='' rules='' repo='' task=''
  PLACED_MARKER='' BRANCH_LOCK='' placed_primary=''
  while [ "$#" -gt 0 ]; do
    case $1 in
      --program | --kind | --scope | --brief | --backend | --cwd | --rules | --repo)
        [ "$#" -ge 2 ] || usage
        case $1 in
          --program) program=$2 ;;
          --kind) kind=$2 ;;
          --scope) scope=$2 ;;
          --brief) brief=$2 ;;
          --backend) backend=$2 ;;
          --cwd) cwd=$2 ;;
          --repo) repo=$2 ;;
          --rules)
            case $2 in
              duty:* | repo:*) ;;
              *) die "--rules takes a duty:<id> or repo:<name> rule scope" ;;
            esac
            valid_scope "$2" || die "refusing the rule scope '$(sanitize_printable "$2")'"
            rules="$rules $2"
            ;;
        esac
        shift 2
        ;;
      *) usage ;;
    esac
  done
  valid_program "$program" || die "refusing the program name '$(sanitize_printable "$program")'"
  kind_row "$kind" || die "unknown session kind '$(sanitize_printable "$kind")' (one of: $KINDS)"
  valid_scope "$scope" || die "refusing the scope '$(sanitize_printable "$scope")': letters, digits and . _ = @ : - only, at most 128"
  [ -n "$brief" ] && [ -f "$brief" ] && [ -r "$brief" ] && [ -s "$brief" ] \
    || die "--brief must name a readable, non-empty regular file"
  case $backend in
    '' | stream-json | tmux) ;;
    *) die "--backend is stream-json or tmux" ;;
  esac
  if changes_repo "$kind"; then
    # A scope the way the keeper offers a unit (<spec>:task-<id>) runs on
    # that unit's branch.
    case $scope in
      *:*:*) ;;
      *:task-*)
        task="${scope%:task-*}/${scope##*:task-}"
        valid_task "$task" \
          || die "refusing the scope $scope: a task scope is <spec>:task-<id>, the spec lowercase letters, digits and - (at most 64), the id <n> or <n>.<m>"
        ;;
    esac
    [ -z "$cwd" ] || { [ -z "$repo" ] && [ -z "$task" ]; } \
      || die "--cwd names the worktree itself, so it takes neither --repo nor a task scope"
    [ -z "$repo" ] || repo=$(abs_dir --repo "$repo") || exit 2
  else
    [ -z "$repo" ] || die "a $kind starts where it is launched and takes no --repo"
    [ -n "$cwd" ] || cwd=$(pwd -P) || die "cannot resolve the current directory"
  fi
  [ -z "$cwd" ] || cwd=$(abs_dir --cwd "$cwd") || exit 2

  name=$(session_name "$program" "$kind" "$scope") || exit 2
  valid_name "$name" || die "the derived session name is outside the launcher's grammar"
  /bin/sh "$script_dir/orchestrate-relay.sh" validate-handle stream-json-persistent "$name" 2>/dev/null \
    || die "the derived session name is outside the relay's session-name grammar"

  profile=$(/bin/sh "$script_dir/fleet-launch-profile.sh" "$K_PROFILE" </dev/null) \
    || die "refusing to launch $name without its $K_PROFILE settings profile" 4

  set --
  for r in $rules; do set -- "$@" --scope "$r"; done
  [ "$#" -gt 0 ] || set -- --scope program
  rendered=$(/bin/bash "$script_dir/mc-rules.sh" render "$program" "$@" </dev/null)
  rr=$?
  case $rr in
    0) ;;
    3) die "refusing to launch $name: the program $(sanitize_printable "$program") is not configured" 4 ;;
    *) die "refusing to launch $name: the rules in scope did not render (mc-rules.sh exit $rr)" 4 ;;
  esac

  resolve_backend
  fleet_home
  private_dir "$FH/mission-control"
  private_dir "$REG"
  private_dir "$LAUNCHES"
  row="$REG/$name"
  ldir="$LAUNCHES/$name"
  owner="mission-control:$program"
  composed="$ldir/brief.md"
  launched=$(date +%s)
  tier=-
  # A stream-json session is found by its name; a tmux one by the window id
  # the rung reports.
  handle=-
  [ "$backend" != stream-json ] || handle=$name
  token=$(new_token)

  # The reservation: a complete row linked into place only where none
  # exists, so a held name is reported and never replaced, and a row on disk
  # always names its backend and token. The name lock is held for the whole
  # launch: a retire meeting it knows the launch is still in flight, and one
  # finding it free knows a `launching` row is a launch that died.
  name_lock "$name"
  if [ -e "$row" ] || [ -L "$row" ]; then
    die "the session name $name is held by a registered session; retire it before launching again" 3
  fi
  rtmp=$(mktemp "$REG/.reserve.XXXXXX") || die "cannot write the reservation for $name"
  if ! row_write "$rtmp" "$token" launching; then
    rm -f "$rtmp"
    die "cannot write the reservation for $name"
  fi
  if ! ln "$rtmp" "$row" 2>/dev/null; then
    rm -f "$rtmp"
    [ ! -e "$row" ] || die "the session name $name is held by a registered session; retire it before launching again" 3
    die "cannot reserve the session name $name"
  fi
  rm -f "$rtmp"
  # A launch directory with no row is a leftover of a launch that died; the
  # reservation now owns the name, so it is cleared.
  rm -rf "$ldir"

  release_reservation() {
    rm -rf "$ldir"
    if [ -e "$ldir" ]; then
      printf '%s\n' "$me: the launch directory $(sanitize_printable "$ldir") could not be removed" >&2
      return 1
    fi
    [ "$(row_get "$row" token 2>/dev/null)" = "$token" ] || return 0
    rm -f "$row"
    if [ -e "$row" ]; then
      printf '%s\n' "$me: the reservation $(sanitize_printable "$row") could not be removed" >&2
      return 1
    fi
  }
  refuse() { # <message> <exit>
    # The dispatch marker a task placement wrote would hold the unit as in
    # flight with no session in it.
    [ -z "$PLACED_MARKER" ] || marker_cmd clear "$placed_primary" "$task" \
      || printf '%s\n' "$me: the dispatch marker for $task was not cleared; the unit may read as in flight" >&2
    release_reservation || :
    die "$1" "$2"
  }

  if changes_repo "$kind"; then
    place_worktree
    case $cwd in
      *[[:cntrl:]]*) refuse "refusing to launch $name: its worktree path holds a control character" 4 ;;
    esac
    # The row names its worktree before the branch lock goes, so a
    # concurrent launch for the same branch finds it in use.
    row_write "$row" "$token" launching || refuse "cannot record the worktree of $name" 2
    [ -z "${BRANCH_LOCK:-}" ] || pw_lock_release "$BRANCH_LOCK" || :
  fi

  # not-a-lock: the reservation is the row above; this only creates the directory it owns
  (umask 077 && mkdir "$ldir") 2>/dev/null || refuse "cannot create the launch directory for $name" 2
  if ! (umask 077 && cat "$brief" >"$composed"); then
    refuse "cannot read the brief into the launch for $name" 2
  fi
  # A kind that changes a repository runs the configured cadence whatever its
  # brief says; a brief whose first line is a skill command leaves it to that
  # skill.
  if changes_repo "$kind" && ! head -n 1 "$composed" | grep -Eq '^/[A-Za-z0-9:_-]+( |$)' \
    && ! cadence_section "$name" "$task" >>"$composed"; then
    refuse "cannot write the cadence into the brief for $name" 2
  fi
  # The provenance line follows the brief, so a brief that is a slash command
  # still opens with it.
  if ! {
    printf '\n%s\n\n' "$rendered"
    printf '<!-- mission-control launch: %s (kind %s, scope %s, program %s) -->\n' "$name" "$kind" "$scope" "$program"
  } >>"$composed"; then
    refuse "cannot write the composed brief for $name" 2
  fi

  # Each rung is an existing primitive. The stream-json supervisor resolves
  # no tier itself, so the plan is resolved here, in the directory the session
  # runs in, where a relaunch re-resolves it; offload-dispatch resolves
  # its own at the kind's key, and --strict-tier stops it from launching at
  # the ambient tier when the allocation store is unreachable.
  unit="mission-control:$name"
  # The row's token goes into the session, so a decided-by-mission-control
  # item it adds is bound to this row rather than to a name any caller can
  # type (tower-comms REQ-A1.14). It is handed to the rung as an explicit
  # argument, which passes it to a mission-control session only.
  mc_tok_flag=''
  [ "$K_PROFILE" != mission-control ] || mc_tok_flag=1
  # Each rung registers the session under the owner fleet-register.sh reads
  # from PLANWRIGHT_TOWER_ID, and keeps it out of the session's environment.
  case $backend in
    stream-json)
      plan=$(cd "$cwd" && /bin/sh "$script_dir/allocation-apply.sh" plan --key "$K_KEY" --backend stream-json-persistent --unit "$unit" </dev/null)
      pr=$?
      case $pr in
        0) ;;
        3) refuse "refusing to launch $name: the admission gate withholds it (allocation-apply exit 3)" 4 ;;
        5) refuse "refusing to launch $name: the allocation seam is a broken install (allocation-apply exit 5)" 4 ;;
        *) refuse "refusing to launch $name: no launch tier resolves at the $K_KEY key (allocation-apply exit $pr)" 4 ;;
      esac
      model=$(printf '%s\n' "$plan" | awk -F '\t' '$1 == "model" { print $2 }')
      effort=$(printf '%s\n' "$plan" | awk -F '\t' '$1 == "effort" { print $2 }')
      if [ -z "$model" ] || [ -z "$effort" ]; then
        refuse "refusing to launch $name: the tier plan carries no model or effort row (broken install)" 4
      fi
      set -- launch "$name" "$scope" --prompt-file "$composed" --profile "$K_PROFILE" --cwd "$cwd" \
        --tier-key "$K_KEY" --tier-unit "$unit"
      [ "$K_PROFILE" != mission-control ] || set -- "$@" --mc-token "$token"
      set -- "$@" --
      [ "$model" = inherit ] || set -- "$@" --model "$model"
      [ "$effort" = inherit ] || set -- "$@" --effort "$effort"
      tier="$model/$effort"
      sr=0
      PLANWRIGHT_TOWER_ID=$owner /bin/sh "$script_dir/fleet-streamjson.sh" "$@" </dev/null >/dev/null || sr=$?
      case $sr in
        0) ;;
        3)
          # A launch or a live session the rung already holds under this
          # name is not this launch's to stop.
          refuse "the stream-json rung already holds a session named $name; it was left running" 1
          ;;
        *)
          # A supervisor that came up after the rung stopped waiting would run
          # with no row, so it is closed before the name is released, and the
          # row stays where the close is not proven.
          if stop_session stream-json "$name"; then
            release_fleet_entry "$name" "$name" || :
            refuse "the stream-json rung did not start $name" 1
          fi
          die "the stream-json rung did not start $name, and what it may have started could not be closed; retire it by name" 1
          ;;
      esac
      ;;
    tmux)
      out=$(cd "$cwd" && PLANWRIGHT_TOWER_ID=$owner /bin/sh "$script_dir/offload-dispatch.sh" dispatch tmux "$composed" --unit "$unit" \
        --key "$K_KEY" --strict-tier --profile "$K_PROFILE" ${mc_tok_flag:+--mc-token "$token"} --name "$name" --scope "$scope" </dev/null)
      dr=$?
      case $dr in
        0) ;;
        1)
          # The rung exits 1 also after a window it created reported an
          # unusable id; that window carries the session's name.
          if stop_session tmux -; then
            refuse "the tmux rung did not start $name" 1
          fi
          die "the tmux rung did not start $name, and a window it may have created could not be closed; retire it by name" 1
          ;;
        3) refuse "refusing to launch $name: the admission gate withholds it (offload-dispatch exit 3)" 4 ;;
        5) refuse "refusing to launch $name: the allocation seam is a broken install (offload-dispatch exit 5)" 4 ;;
        4 | 6) refuse "refusing to launch $name: no launch tier resolves at the $K_KEY key (offload-dispatch exit $dr)" 4 ;;
        *) refuse "the tmux rung refused $name (offload-dispatch exit $dr)" 4 ;;
      esac
      handle=$(printf '%s\n' "$out" | awk -F '\t' '$1 == "handle" { print $2; exit }')
      valid_window "$handle" || refuse "the tmux rung reported no usable window for $name" 1
      tier=rung
      ;;
  esac

  if ! row_write "$row" "$token" launched; then
    # The session runs, but no row records it: stop it rather than leave it
    # where retire cannot find it.
    if stop_session "$backend" "$handle"; then
      release_fleet_entry "$name" "$handle" || :
      refuse "$name started but its registry row could not be completed, so it was stopped" 1
    fi
    die "$name started but its registry row could not be completed and it could not be stopped; retire it by name" 1
  fi
  report() { printf 'launch\t%s\t%s\n' "$1" "$(sanitize_printable "$2")"; }
  report name "$name"
  report kind "$kind"
  report program "$program"
  report owner "$owner"
  report scope "$scope"
  report backend "$backend"
  report profile "$profile"
  report tier "$tier"
  report brief "$composed"
  report cwd "$cwd"
}

cmd_name() {
  program='' kind='' scope=''
  while [ "$#" -gt 0 ]; do
    case $1 in
      --program | --kind | --scope)
        [ "$#" -ge 2 ] || usage
        case $1 in
          --program) program=$2 ;;
          --kind) kind=$2 ;;
          --scope) scope=$2 ;;
        esac
        shift 2
        ;;
      *) usage ;;
    esac
  done
  valid_program "$program" || die "refusing the program name '$(sanitize_printable "$program")'"
  kind_row "$kind" || die "unknown session kind '$(sanitize_printable "$kind")' (one of: $KINDS)"
  valid_scope "$scope" || die "refusing the scope '$(sanitize_printable "$scope")'"
  session_name "$program" "$kind" "$scope"
}

# windows_named <name> — print the ids of the tmux windows named <name>, or
# return 1 when tmux cannot list them.
windows_named() {
  if ! wn_list=$(tmux list-windows -a -F '#{window_id} #{window_name}' 2>&1); then
    # No server means no window: positive evidence, unlike other errors.
    case $wn_list in
      *'no server running'* | *'error connecting to'*'No such file or directory'*) return 0 ;;
    esac
    return 1
  fi
  printf '%s\n' "$wn_list" | awk -v n="$1" '$2 == n && $1 ~ /^@[0-9]+$/ { print $1 }'
}

# window_ids — print every live window id, or return 1 when tmux cannot list
# them (no server: none).
window_ids() {
  if ! wi_list=$(tmux list-windows -a -F '#{window_id}' 2>&1); then
    case $wi_list in
      *'no server running'* | *'error connecting to'*'No such file or directory'*) return 0 ;;
    esac
    return 1
  fi
  printf '%s\n' "$wi_list"
}

# release_pane <name> <window-id or -> — close the session's window, setting
# RP_IDS to the ids it closed. Released only on positive evidence that it is
# gone: a listing that succeeds (or no server at all) and carries no window
# of that id and name. A recorded id live under another name is held.
release_pane() {
  rp_ids=$(windows_named "$1") || return 1
  if [ "$2" != - ]; then
    case "$NL$rp_ids$NL" in
      *"$NL$2$NL"*) rp_ids=$2 ;;
      *)
        # Live under another name: renamed, or reused by another server.
        # Either way it is not proven gone, and it is not killed.
        rp_all=$(window_ids) || return 1
        case "$NL$rp_all$NL" in *"$NL$2$NL"*) return 1 ;; esac
        rp_ids=''
        ;;
    esac
  fi
  RP_IDS=$rp_ids
  for rp_id in $rp_ids; do
    tmux kill-window -t "$rp_id" >/dev/null 2>&1 || :
  done
  rp_left=$(windows_named "$1") || return 1
  for rp_id in $rp_ids; do
    case "$NL$rp_left$NL" in *"$NL$rp_id$NL"*) return 1 ;; esac
  done
  return 0
}

# retire_unregistered <name> — retire a session this launcher holds no row
# for: one an older planwright, /orchestrate or a hand launch started straight
# on the stream-json rung. Its runtime directory is all there is to go on, so
# the rung's own final close takes it, then the fleet registry marker under
# the same handle and the attention row, as for a launched one. Without that
# directory the refusal names the stop that applies.
retire_unregistered() {
  if [ -L "$FH/streamjson/$1" ] || [ ! -d "$FH/streamjson/$1" ]; then
    die "no registered session and no stream-json worker is named $1; a headless worker closes with scripts/fleet-dispatch-headless.sh stop $1, a tmux window with tmux kill-window -t <window id>" 3
  fi
  name_lock "$1"
  # A launch reserves its row under this same lock, so a row that appeared
  # since the caller looked is a launch to leave alone.
  if [ -e "$REG/$1" ] || [ -L "$REG/$1" ]; then
    die "a launch of $1 is in flight" 3
  fi
  # The name lock covers only this launcher's launches: one by /orchestrate
  # or by hand holds the rung's own elections, which a close would break.
  for ru_l in launch.lock recover.lock relaunch.lock; do
    ru_t=$(pw_lock_owner "$FH/streamjson/$1/$ru_l") || ru_t=''
    if [ -n "$ru_t" ] && pw_lock_owner_alive "$ru_t"; then
      die "a launch, recover or relaunch of $1 is in flight ($ru_l is held)" 3
    fi
  done
  released='' held=''
  st=$(/bin/sh "$script_dir/fleet-streamjson.sh" stop "$1" --final </dev/null 2>/dev/null)
  case $st in
    "stop $1 stopped "* | "stop $1 already-closed")
      released=process
      if release_fleet_entry "$1" "$1"; then
        released="$released,registry,attention"
      else
        held=registry,attention
      fi
      ;;
    *) held=process,registry,attention ;;
  esac
  name_unlock
  if [ -z "$held" ]; then
    printf 'retire\t%s\treleased\treleased=%s\theld=-\n' "$1" "$released"
    return 0
  fi
  printf 'retire\t%s\tpartial\treleased=%s\theld=%s\n' "$1" "${released:--}" "$held"
  return 1
}

cmd_retire() {
  [ "$#" -eq 1 ] || usage
  name=$1
  if ! valid_name "$name"; then
    valid_scope "$name" || die "refusing the session name '$(sanitize_printable "$name")'"
    fleet_home
    retire_unregistered "$name"
    return
  fi
  fleet_home
  row="$REG/$name"
  [ ! -L "$row" ] || die "refusing the registry row for $name: a symbolic link"
  [ -f "$row" ] || {
    retire_unregistered "$name"
    return
  }
  name_lock "$name"
  [ -f "$row" ] || die "no registered session is named $name" 3
  row_check "$row"
  state=$(row_get "$row" state)
  backend=$(row_get "$row" backend)
  handle=$(row_get "$row" handle)
  released='' held=''
  add_released() { released="$released,$1"; }
  add_held() { held="$held,$1"; }

  case $backend in
    stream-json)
      st=$(/bin/sh "$script_dir/fleet-streamjson.sh" stop "$name" --final </dev/null 2>/dev/null)
      case $st in
        "stop $name stopped "* | "stop $name already-closed") add_released process ;;
        *)
          # A launch that died before its supervisor came up left no state.
          if [ "$state" = launching ] && [ ! -d "$FH/streamjson/$name" ]; then
            add_released process
          else
            add_held process
          fi
          ;;
      esac
      ;;
    tmux)
      [ "$handle" = - ] || valid_window "$handle" || die "the registry row for $name names no usable window" 2
      if [ -n "${TMUX_PANE:-}" ] && [ "$handle" != - ]; then
        self=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null) || self=''
        [ "$self" != "$handle" ] || die "refusing to retire $name from inside its own window" 3
      fi
      if release_pane "$name" "$handle"; then add_released pane; else add_held pane; fi
      ;;
    *) die "the registry row for $name names an unknown backend" 2 ;;
  esac

  # A session still running keeps its fleet record and attention row, so
  # the fleet goes on seeing it.
  if [ -n "$held" ]; then
    add_held registry
    add_held attention
  else
    # The rung registered the session in the fleet registry under its own
    # handle: the session name on stream-json, the window id on tmux.
    # A tmux row the launch never completed names no window; the windows
    # closed by name carry the markers then.
    ids=$handle
    [ "$backend" != tmux ] || [ "$handle" != - ] || ids=${RP_IDS:-}
    reg_ok=1
    for id in $ids; do
      marker="$FH/dispatch-markers/$id"
      if [ "$id" != - ] && { [ -e "$marker" ] || [ -L "$marker" ]; }; then
        fields=$(cat "$marker" 2>/dev/null) || fields=''
        /bin/sh "$script_dir/fleet-register.sh" --retire-marker "$marker" --expect "$fields" >/dev/null 2>&1 </dev/null || :
        if [ -e "$marker" ] || [ -L "$marker" ]; then reg_ok=0; fi
      fi
    done
    if [ "$reg_ok" = 1 ]; then add_released registry; else add_held registry; fi
    if /bin/sh "$script_dir/fleet-attention.sh" clear "$name" >/dev/null 2>&1 </dev/null; then
      add_released attention
    else
      add_held attention
    fi
  fi

  if [ -z "$held" ]; then
    # The dispatch marker this launch wrote would hold the unit as in flight.
    r_task=$(row_get "$row" task)
    r_primary=$(row_get "$row" primary)
    if [ "$(row_get "$row" marker)" = 1 ] && valid_task "$r_task" && [ -d "$r_primary" ]; then
      marker_cmd clear "$r_primary" "$r_task" \
        || printf '%s\n' "$me: the dispatch marker for $r_task was not cleared; the unit may read as in flight" >&2
    fi
    rm -rf "${LAUNCHES:?}/$name"
    if [ -e "$LAUNCHES/$name" ]; then
      add_held row
    else
      rm -f "$row"
      if [ -e "$row" ]; then add_held row; else add_released row; fi
    fi
  else
    add_held row
  fi
  name_unlock
  released=${released#,}
  held=${held#,}
  if [ -z "$held" ]; then
    printf 'retire\t%s\treleased\treleased=%s\theld=-\n' "$name" "$released"
    return 0
  fi
  printf 'retire\t%s\tpartial\treleased=%s\theld=%s\n' "$name" "${released:--}" "$held"
  return 1
}

cmd_list() {
  [ "$#" -eq 0 ] || usage
  fleet_home
  [ -d "$REG" ] || return 0
  [ -r "$REG" ] && [ -x "$REG" ] || die "cannot read the registry $(sanitize_printable "$REG")" 2
  set +f
  set -- "$REG"/mc-*
  set -f
  for f in "$@"; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    case ${f##*/} in *.tmp.*) continue ;; esac
    [ -r "$f" ] || die "cannot read the registry row $(sanitize_printable "${f##*/}")" 2
    if ! row_format_ok "$f"; then
      printf '%s\n' "$me: skipping the registry row $(sanitize_printable "${f##*/}"): its format field is not $FORMAT" >&2
      continue
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${f##*/}" "$(row_get "$f" program)" "$(row_get "$f" kind)" \
      "$(row_get "$f" scope)" "$(row_get "$f" backend)" "$(row_get "$f" launched)"
  done
}

cmd_kinds() {
  [ "$#" -eq 0 ] || usage
  for k in $KINDS; do
    kind_row "$k"
    printf '%s\t%s\t%s\n' "$k" "$K_PROFILE" "$K_KEY"
  done
}

[ "$#" -ge 1 ] || usage
verb=$1
shift
case $verb in
  -h | --help) help_text ;;
  launch) cmd_launch "$@" ;;
  name) cmd_name "$@" ;;
  retire) cmd_retire "$@" ;;
  list) cmd_list "$@" ;;
  kinds) cmd_kinds "$@" ;;
  *) usage ;;
esac
