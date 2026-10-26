#!/bin/sh
# fleet-task-brief.sh — the task worker's launch-time brief (fleet-messaging
# D-25, REQ-C1.6, REQ-H1.6).
#
# A tmux task worker starts its opening turn from a file, never a message or a
# keystroke: the tower's dispatch step renders the unit's task brief here, then
# passes it to `fleet-dispatch-worktree.sh dispatch <spec> <id> --brief <path>`,
# which hands the worker the one fixed prompt naming it. The brief is the
# shipped template (templates/task-brief/brief.md) filled with validated
# fields only, so nothing a tower composes reaches the worker's opening turn.
#
# Usage:
#   fleet-task-brief.sh render <spec> <id> [--tower <name>] [--repo-root <dir>]
#       Write `<fleet-home>/tasks/<spec>/<id>/brief.md` and print
#       `brief<TAB><canonical path>`. <spec> is the bare identifier or its
#       `specs/<spec>` alias (scripts/spec-id-lib.sh); <id> is `5` or `3.5`.
#       --tower names the supervising tower's session name, screened here
#       (printable ASCII, no path separator, no leading dash, 1 to 128 bytes,
#       and no backtick, so the name stays inside the brief's code span);
#       with it the brief carries the name and the question rule, without it
#       neither, and the worker has no upward message path. --repo-root names
#       the checkout the unit's worktree is placed in, a linked worktree read
#       as its primary (default: resolve-root.sh repo --primary), recorded
#       beside the brief for retire. A unit whose brief another checkout
#       recorded, and whose worktree there still exists, is refused (exit 4):
#       the fleet home is per machine, keyed by spec and task id alone.
#       The fleet home and every directory below it on the path are created
#       owner-only and must be private to the user and never a symlink; the
#       brief lands owner-only by rename, replacing a file or link at its name
#       (a directory there is refused, exit 4).
#   fleet-task-brief.sh retire [--repo-root <dir>]
#       Remove the brief directory of each of this checkout's task units
#       whose worktree (`<repo>/.claude/worktrees/<spec>-task-<id>`) is gone,
#       printing `retired<TAB><spec>/<id>` each, and of any unit whose recorded
#       checkout no longer exists. A live checkout's other brief, one recording
#       no checkout, and one younger than BRIEF_GRACE_MIN (rendered before its
#       worktree exists) stay. An entry that cannot be read is skipped and
#       named, the rest still retired (exit 4). The checkout record goes last,
#       so a partial removal is retried. A render holding the tasks lock makes
#       retire a silent no-op until the next sweep. No fleet home or tasks
#       directory yet is a clean exit 0 with no output. fleet-sweep.sh's
#       residue pass runs it.
#
# Exit codes: 0 written / retired (or nothing to retire); 2 usage or a field
# failing its grammar (nothing written); 4 the fleet home, a directory on the
# path, or the template refused or unreadable, the unit held by another
# checkout, the tasks lock unobtainable, or a write, read, or removal failed.
#
# Render and retire serialize on `<fleet-home>/tasks/.brief.lock`
# (scripts/lock-lib.sh), so a retire never removes a brief a render is writing.
#
# Portable POSIX sh: no eval, input treated as data only; template values reach
# awk through ENVIRON and are spliced by index, never as a regex replacement.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

prog=fleet-task-brief
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
if [ -f "$script_dir/echo-safety.sh" ] && [ -r "$script_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$script_dir/echo-safety.sh"
else
  sanitize_printable() {
    printf '%s' "$1" | tr -d '\000-\037\177\200-\237'
  }
fi
if [ -r "$script_dir/lock-lib.sh" ]; then
  # shellcheck source=scripts/lock-lib.sh
  . "$script_dir/lock-lib.sh"
else
  printf '%s\n' "$prog: broken install: lock-lib.sh is missing or not readable" >&2
  exit 4
fi
if [ -r "$script_dir/spec-id-lib.sh" ]; then
  # shellcheck source=scripts/spec-id-lib.sh
  . "$script_dir/spec-id-lib.sh"
else
  printf '%s\n' "$prog: broken install: spec-id-lib.sh is missing or not readable" >&2
  exit 4
fi

STATE="$script_dir/fleet-state.sh"
TEMPLATE="$script_dir/../templates/task-brief/brief.md"
LF='
'

# The minutes a brief is kept before retire may take it: the dispatch step
# renders it before the worktree it is keyed on exists.
BRIEF_GRACE_MIN=15

die() {
  printf '%s\n' "$prog: $(sanitize_printable "$2")" >&2
  exit "$1"
}

usage() {
  cat >&2 <<'EOF'
usage: fleet-task-brief.sh render <spec> <id> [--tower <name>] [--repo-root <dir>]
       fleet-task-brief.sh retire [--repo-root <dir>]
EOF
  exit 2
}

# The spec identifier grammar (REQ-A1.8), `flight` reserved.
valid_spec() {
  case $1 in
    '' | *[!a-z0-9-]* | [!a-z0-9]* | flight) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

valid_id() {
  case $1 in
    '' | *[!0-9.]*) return 1 ;;
  esac
  printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?$'
}

# The name screen REQ-D1.7 states, held here so the renderer needs nothing
# from the messaging seam: printable ASCII, no path separator, no leading dash,
# 1 to 128 bytes. A newline fails the printable check, so the name stays one
# line of the brief; a backtick would close the code span the brief quotes it
# in and let the name read as instructions.
valid_name() {
  [ -n "$1" ] && [ "${#1}" -le 128 ] || return 1
  case $1 in
    -* | */* | *\\* | *\`* | *[!\ -~]*) return 1 ;;
  esac
}

# private_dir <dir> — a real directory the invoking user owns that neither
# group nor others can write.
private_dir() {
  [ ! -L "$1" ] && [ -d "$1" ] || return 1
  _pd_uid=$(id -u) || return 1
  [ -n "$(find "$1" -maxdepth 0 -user "$_pd_uid" ! -perm -0020 ! -perm -0002 2>/dev/null)" ]
}

# resolve_repo <dir-or-empty> — set `repo` to the primary checkout's canonical
# path. A linked worktree (the sweep runs from wherever its tower does) maps to
# its primary, the checkout dispatch places unit worktrees in.
resolve_repo() {
  repo=$1
  if [ -n "$repo" ]; then
    _rr_primary=$(cd "$repo" 2>/dev/null && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$script_dir/resolve-root.sh" repo --primary 2>/dev/null </dev/null) \
      && [ -n "$_rr_primary" ] && repo=$_rr_primary
  else
    repo=$(/bin/sh "$script_dir/resolve-root.sh" repo --primary 2>/dev/null </dev/null) \
      || die 2 "cannot resolve the primary checkout (pass --repo-root)"
  fi
  repo=$(cd "$repo" 2>/dev/null && pwd -P) || die 2 "the repo root is not a directory"
  case $repo in
    *"$LF"*) die 2 "refusing a repo root whose path carries a newline" ;;
  esac
}

# resolve_home [--create] — set `home` to the fleet home's canonical path,
# private to the user. Without --create an absent home exits 0.
resolve_home() {
  home=$(/bin/sh "$STATE" root 2>/dev/null </dev/null) && [ -n "$home" ] \
    || die 4 "cannot resolve the fleet home"
  if [ "${1:-}" = --create ]; then
    (umask 077 && mkdir -p "$home") || die 4 "cannot create the fleet home"
  elif [ ! -d "$home" ]; then
    exit 0
  fi
  home=$(cd "$home" 2>/dev/null && pwd -P) || die 4 "cannot resolve the fleet home"
  case $home in
    *[!A-Za-z0-9._/@+-]*)
      die 4 "refusing a fleet home whose canonical path falls outside the brief path charset [A-Za-z0-9._/@+-]; set PLANWRIGHT_FLEET_STATE_DIR to a path within it"
      ;;
  esac
  private_dir "$home" || die 4 "refusing the fleet home: not a directory owned by you that only you can write (chmod go-w it)"
}

# private_child <dir> — create <dir> owner-only if absent, then require it
# private and never a symlink.
private_child() {
  [ ! -L "$1" ] || die 4 "refusing to write a task brief: $1 is a symlink"
  # not-a-lock: a concurrent render creating the same directory is fine
  [ -d "$1" ] || (umask 077 && mkdir "$1") 2>/dev/null || [ -d "$1" ] \
    || die 4 "cannot create $1"
  private_dir "$1" || die 4 "refusing to write a task brief: $1 is not a directory owned by you that only you can write"
}

# land <dir> <name> <text> — write <text> and a newline to <dir>/<name>
# through a temp file and a rename, so a reader never sees it half-written and
# a link planted at the name is replaced, never written through. Never call it
# in a pipeline: its die must end the script, not a subshell.
land() {
  _ld_tmp=$(mktemp "$1/.$2.tmp.XXXXXX") || die 4 "cannot create a temp file in $1"
  if ! printf '%s\n' "$3" >"$_ld_tmp" || ! chmod 600 "$_ld_tmp"; then
    rm -f "$_ld_tmp"
    die 4 "cannot write $1/$2"
  fi
  # mv onto a symlink to a directory would move into that directory.
  [ ! -L "$1/$2" ] || rm -f "$1/$2"
  if [ -d "$1/$2" ] || ! mv -f "$_ld_tmp" "$1/$2"; then
    rm -f "$_ld_tmp"
    die 4 "cannot land $1/$2"
  fi
}

# fill_template — the template on stdout, its placeholders filled and the
# tower block kept (markers dropped) only when a name is given. Trailing blank
# lines are dropped, so the unnamed brief ends at its last line of text. The
# tower name is spliced last, so text it carries is never re-scanned.
fill_template() {
  TB_SPEC=$spec TB_ID=$id TB_TOWER=$tower awk '
    function splice(s, ph, v,    out, i) {
      out = ""
      while ((i = index(s, ph)) > 0) {
        out = out substr(s, 1, i - 1) v
        s = substr(s, i + length(ph))
      }
      return out s
    }
    BEGIN { named = (ENVIRON["TB_TOWER"] != ""); skip = 0; blanks = 0 }
    $0 == "<!-- tower -->" { if (!named) skip = 1; next }
    $0 == "<!-- /tower -->" { skip = 0; next }
    skip { next }
    {
      line = splice($0, "@@SPEC@@", ENVIRON["TB_SPEC"])
      line = splice(line, "@@ID@@", ENVIRON["TB_ID"])
      line = splice(line, "@@TOWER@@", ENVIRON["TB_TOWER"])
      if (line == "") { blanks++; next }
      while (blanks > 0) { print ""; blanks-- }
      print line
    }
  ' <"$TEMPLATE"
}

do_render() {
  spec=''
  id=''
  tower=''
  tower_set=0
  repo_arg=''
  npos=0
  while [ "$#" -gt 0 ]; do
    case $1 in
      --tower)
        [ "$#" -ge 2 ] || usage
        tower=$2
        tower_set=1
        shift 2
        ;;
      --repo-root)
        [ "$#" -ge 2 ] || usage
        repo_arg=$2
        shift 2
        ;;
      --*) usage ;;
      *)
        npos=$((npos + 1))
        case $npos in
          1) spec=$1 ;;
          2) id=$1 ;;
          *) usage ;;
        esac
        shift
        ;;
    esac
  done
  [ "$npos" -eq 2 ] || usage
  spec_id_canon "$spec"
  spec=$SPEC_ID
  valid_spec "$spec" || die 2 "invalid spec identifier: $spec"
  valid_id "$id" || die 2 "invalid task id: $id"
  if [ "$tower_set" -eq 1 ]; then
    valid_name "$tower" || die 2 "refusing a tower name that fails the session-name screen (printable ASCII, no path separator or leading dash, 1 to 128 bytes)"
  fi
  [ -f "$TEMPLATE" ] && [ -r "$TEMPLATE" ] && [ ! -L "$TEMPLATE" ] \
    || die 4 "broken install: the task brief template is missing or not readable"
  resolve_repo "$repo_arg"
  resolve_home --create
  private_child "$home/tasks"
  take_lock 400 || die 4 "the task brief lock stayed held by another render or retire"
  private_child "$home/tasks/$spec"
  unit="$home/tasks/$spec/$id"
  private_child "$unit"
  if [ -f "$unit/checkout" ] && [ ! -L "$unit/checkout" ]; then
    _held=$(cat <"$unit/checkout") || die 4 "cannot read $unit/checkout"
    if [ "$_held" != "$repo" ] && [ -e "$_held/.claude/worktrees/$spec-task-$id" ]; then
      die 4 "refusing to overwrite the task brief of $spec/$id: another checkout's unit holds it ($_held)"
    fi
  fi
  # The template's output ends in exactly one newline, which the substitution
  # strips and land restores.
  body=$(fill_template) || die 4 "cannot render the task brief template"
  # The checkout record lands first: retire keys on it, so a brief never
  # lands without one.
  land "$unit" checkout "$repo"
  land "$unit" brief.md "$body"
  printf 'brief\t%s\n' "$unit/brief.md"
}

# take_lock <tries> — hold the tasks lock until exit; 1 when another holder
# kept it for the whole budget (a <tries> of 0 is one attempt), 2 an error.
take_lock() {
  pw_lock_trap_install
  if [ "$1" -eq 0 ]; then
    pw_lock_try "$home/tasks/.brief.lock"
  else
    pw_lock_acquire "$home/tasks/.brief.lock" "$1"
  fi
}

# retire_unit <dir> — remove one unit's brief directory, its checkout record
# last, so a removal that stops partway leaves what the next retire finds it by.
retire_unit() {
  find "$1" -mindepth 1 -maxdepth 1 ! -name checkout -exec rm -rf {} + 2>/dev/null </dev/null || return 1
  rm -f "$1/checkout" 2>/dev/null && rmdir "$1" 2>/dev/null && [ ! -e "$1" ]
}

do_retire() {
  repo_arg=''
  while [ "$#" -gt 0 ]; do
    case $1 in
      --repo-root)
        [ "$#" -ge 2 ] || usage
        repo_arg=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  resolve_repo "$repo_arg"
  resolve_home
  tasks="$home/tasks"
  [ -e "$tasks" ] || [ -L "$tasks" ] || exit 0
  private_dir "$tasks" || die 4 "refusing to retire: $tasks is not a directory owned by you that only you can write; nothing was removed"
  take_lock 0
  case $? in
    0) ;;
    1) exit 0 ;;
    *) die 4 "cannot take the task brief lock; nothing was removed" ;;
  esac
  failed=0
  # An unreadable spec directory fails the listing but not the rest of it:
  # the entries find could read are still judged, and the failure is named.
  entries=$(find "$tasks" -mindepth 2 -maxdepth 2 2>/dev/null </dev/null) || {
    printf '%s\n' "$prog: part of $tasks could not be listed; what could be read is still retired" >&2
    failed=1
  }
  nl=$(find "$tasks" -mindepth 1 -maxdepth 2 -name "*$LF*" 2>/dev/null </dev/null) || :
  [ -z "$nl" ] || die 4 "refusing to retire: an entry under $tasks has a newline in its name; nothing was removed"
  old_ifs=$IFS
  IFS=$LF
  for dir in $entries; do
    IFS=$old_ifs
    rt_id=${dir##*/}
    rt_spec=${dir%/*}
    rt_spec=${rt_spec##*/}
    if ! valid_spec "$rt_spec" || ! valid_id "$rt_id"; then
      continue
    fi
    [ -d "$dir" ] && [ ! -L "$dir" ] && [ ! -L "$tasks/$rt_spec" ] || continue
    [ -f "$dir/checkout" ] && [ ! -L "$dir/checkout" ] || continue
    rec=$(cat <"$dir/checkout" 2>/dev/null) || {
      printf '%s\n' "$prog: cannot read the checkout record of $rt_spec/$rt_id; skipped" >&2
      failed=1
      continue
    }
    # A brief whose checkout no longer exists has no sweep of its own left.
    if [ "$rec" = "$repo" ]; then
      wt="$repo/.claude/worktrees/$rt_spec-task-$rt_id"
      [ ! -e "$wt" ] && [ ! -L "$wt" ] || continue
    else
      case $rec in
        /*) ;;
        *) continue ;;
      esac
      [ ! -e "$rec" ] && [ ! -L "$rec" ] || continue
    fi
    # A failed age check keeps the brief: "cannot tell" is never "old".
    young=$(find "$dir" -maxdepth 0 -mmin "-$BRIEF_GRACE_MIN" 2>/dev/null </dev/null) || continue
    [ -z "$young" ] || continue
    if retire_unit "$dir"; then
      printf 'retired\t%s/%s\n' "$rt_spec" "$rt_id"
      rmdir "$tasks/$rt_spec" 2>/dev/null || :
    else
      printf '%s\n' "$prog: could not remove the task brief of $rt_spec/$rt_id" >&2
      failed=1
    fi
  done
  IFS=$old_ifs
  [ "$failed" -eq 0 ] || exit 4
}

[ "$#" -ge 1 ] || usage
verb=$1
shift
case $verb in
  render) do_render "$@" ;;
  retire) do_retire "$@" ;;
  *) usage ;;
esac
