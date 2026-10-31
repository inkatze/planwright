#!/bin/sh
# review-reverify.sh — re-verify every earlier finding's fix by re-running what
# validated it, so a fix that regresses outside the next pass's delta is still
# caught (review-effectiveness REQ-A1.7, REQ-C1.1, D-14).
#
# THE RECORDED-REPRODUCTION FORMAT. A text file whose first line is
# `review-repro 1`; blank lines and `#` comment lines are ignored, and leading
# spaces on any line are. Each record starts at a `finding <id>` line (the id
# is letters, digits, and . _ -, unique in the file) and holds, one per line:
#   kind <reproduction|test|rule>  exactly one; what validated the finding: the real surface
#                                  invoked with the triggering input, the
#                                  targeted test, or the tool rule
#   run <command>                  exactly one; a shell command line, run by sh
#                                  from the copy's root
#   exit <n>                       exactly one; the exit code the fixed behaviour gives
#   output-contains <text>         optional, repeatable: a fixed string the
#                                  combined stdout and stderr must hold
#   output-lacks <text>            optional, repeatable: one it must not hold
# No line may hold a tab. The whole file is validated before anything runs;
# an empty file is malformed (it lacks the first line), never "no records".
#
# THE COPY. Each record runs in its own fresh isolated copy of the committed
# head (or --head): a shared clone in a temporary directory with its remote
# removed, removed on exit. Never the live worktree, whose uncommitted edits
# do not reach the copy. The command starts from an empty environment holding
# only PATH, LC_ALL, TERM, and a home, XDG directories, TMPDIR, fleet home
# (PLANWRIGHT_FLEET_STATE_DIR), plugin-data home (CLAUDE_PLUGIN_DATA), and
# CLAUDE_DIR inside the record's temporary directory, beside the clone (never
# inside it), a fixed git identity, and the default INT and QUIT dispositions
# where env(1) can restore them, with system and global git configuration off,
# both for the command and for setting the copy up, where no hook runs; no
# credential or token variable reaches it. Where setsid(1) exists the command
# runs in its own session, and every process still in that session when it
# returns is killed (found through /proc, else pkill; with neither, only the
# command's own process group); one that leaves the session (setsid, a
# daemon) escapes.
# The copy isolates the repository and the environment, not the host: a
# command naming an absolute path outside it still reaches that path.
#
# Prints `held <id> <kind>` or `regressed <id> <kind> <why>` per record; with
# --log-dir, each record's output is kept there as <id>.log, the evidence an
# isolation or regression claim shows.
#
# Untrusted input: the records file is written by the reviewing loop itself.
# Its run lines are executed, by design, inside the copy; nothing else from it
# is interpreted.
#
# Usage:
#   review-reverify.sh --records <file> [--head <rev>] [--timeout <seconds>]
#       [--log-dir <dir>]
#
#   --timeout  per record, default 600, applied when timeout(1) exists; a
#              timed-out command reports exit 124 (143 under busybox timeout,
#              which reports the TERM it sent), or 137 when it ignored the
#              signal and was killed 10 seconds later
#
# Exit codes: 0 every fix held (or no records); 1 one or more regressed; 2
#   usage or a malformed records file; 4 a copy, a working file, or a log
#   could not be set up or written, or a record's command never started.
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH
# A git hook exports these, and every git command below must act on the
# repository it names, never the one they point at, under no inherited
# configuration.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
  GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
GIT_CONFIG_NOSYSTEM=1
GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL

prog=review-reverify
TAB=$(printf '\t')

usage() {
  cat >&2 <<EOF
usage: $prog --records <file> [--head <rev>] [--timeout <seconds>] [--log-dir <dir>]
EOF
  exit 2
}
# printable — the input without its non-printable bytes, tabs and newlines kept.
printable() { tr -d '\000-\010\013-\037\177\200-\237'; }
die() {
  printf '%s\n' "$prog: $2" | printable >&2
  exit "$1"
}

records=
head_rev=HEAD
timeout_s=600
log_dir=
while [ $# -gt 0 ]; do
  case $1 in
    --records | --head | --timeout | --log-dir)
      [ $# -ge 2 ] || usage
      case $1 in
        --records) records=$2 ;;
        --head) head_rev=$2 ;;
        --timeout) timeout_s=$2 ;;
        --log-dir) log_dir=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ -n "$records" ] || usage
[ -f "$records" ] && [ -r "$records" ] || die 2 "--records is not a readable file: $records"
case $timeout_s in '' | *[!0-9]*) die 2 "--timeout must be a positive whole number of seconds" ;; esac
case $timeout_s in *[!0]*) ;; *) die 2 "--timeout must be a positive whole number of seconds" ;; esac
if [ -n "$log_dir" ]; then
  [ -d "$log_dir" ] && [ -w "$log_dir" ] || die 2 "--log-dir is not a writable directory"
  log_dir=$(cd "$log_dir" && pwd)
fi

# --- validate and normalize ---------------------------------------------------
# Each record becomes `R <id> <kind> <exit> <run>`, then `C <id> <text>` and
# `L <id> <text>` per expected and forbidden output.

parse_err=$(mktemp "${TMPDIR:-/tmp}/review-reverify-parse.XXXXXX") || die 4 "could not create a working file"
trap 'rm -f "$parse_err"' EXIT
parsed=$(awk '
  function bad(msg) { printf "line %d: %s\n", NR, msg > "/dev/stderr"; failed = 1; exit 2 }
  function close_rec() {
    if (id == "") return
    if (kind == "") bad("finding " id " has no kind line")
    if (runs != 1) bad("finding " id " needs exactly one run line")
    if (code == "") bad("finding " id " has no exit line")
    printf "R\t%s\t%s\t%s\t%s\n", id, kind, code, run
    printf "%s", expect
  }
  NR == 1 { if ($0 != "review-repro 1") bad("the first line must be: review-repro 1"); next }
  /\t/ { bad("a line holds a tab") }
  { sub(/^ +/, "") }
  /^$/ || /^#/ { next }
  {
    field = $1
    value = $0
    sub(/^[^ ]+ ?/, "", value)
    if (field == "finding") {
      close_rec()
      if (value !~ /^[A-Za-z0-9._-]+$/ || value ~ /^\.+$/) bad("finding ids are letters, digits, and . _ -")
      if (value in seen) bad("finding " value " is repeated")
      seen[value] = 1
      id = value; kind = ""; runs = 0; run = ""; code = ""; expect = ""; kinds = 0; codes = 0
      next
    }
    if (id == "") bad("a " field " line before any finding line")
    if (field == "kind") {
      if (value !~ /^(reproduction|test|rule)$/) bad("kind must be reproduction, test, or rule")
      if (++kinds > 1) bad("finding " id " has more than one kind line")
      kind = value
    } else if (field == "run") {
      if (value == "") bad("an empty run line")
      runs++; run = value
    } else if (field == "exit") {
      if (value !~ /^[0-9]+$/ || value + 0 > 255) bad("exit must be a code from 0 to 255")
      if (++codes > 1) bad("finding " id " has more than one exit line")
      code = value + 0
    } else if (field == "output-contains" || field == "output-lacks") {
      if (value == "") bad("an empty " field " line")
      expect = expect (field == "output-contains" ? "C" : "L") "\t" id "\t" value "\n"
    } else bad("unknown field: " field)
  }
  END {
    if (failed) exit 2
    if (NR == 0) bad("an empty file: the first line must be: review-repro 1")
    close_rec()
  }' "$records" 2>"$parse_err") || die 2 "malformed records file: $(cat "$parse_err")"
rm -f "$parse_err"

if ! printf '%s\n' "$parsed" | grep -q '^R'; then
  printf 'no records to re-verify\n'
  exit 0
fi

top=$(git rev-parse --show-toplevel 2>/dev/null) || die 2 "not inside a git work tree"
case $head_rev in -*) die 2 "--head must be a revision, not an option" ;; esac
head=$(git rev-parse --verify --quiet "$head_rev^{commit}") || die 2 "--head names no commit: $head_rev"

runner=
if command -v timeout >/dev/null 2>&1; then runner="timeout -k 10 $timeout_s"; fi
session=
if command -v setsid >/dev/null 2>&1; then session=setsid; fi
signals=
if env --default-signal=INT,QUIT true 2>/dev/null; then signals=--default-signal=INT,QUIT; fi

# A record may leave read-only files in its copy (a module cache, a chmod);
# removal makes them writable first, and a cleanup failure is never a verdict.
scrub() {
  chmod -R -- u+w "$1" 2>/dev/null || true
  rm -rf -- "$1" 2>/dev/null || true
}
# reap <pid> — end what a record left running in its session, whose id is the
# pid of the record's session leader: the session's members read from /proc
# where it exists, else through pkill -s, else only the leader's group.
grp=
reap() {
  [ -n "$1" ] && [ -n "$session" ] || return 0
  kill -9 "-$1" 2>/dev/null || true
  if [ -r /proc/self/stat ]; then
    sid_want=$1
    # A stat file is `<pid> (<comm>) <state> <ppid> <pgrp> <session> ...`; the
    # command name may hold spaces, parentheses and newlines, so each file is
    # read whole with builtins (no fork per process), fields count from its
    # last `)`, and the pid comes from the file's path, never its contents.
    for st in /proc/[0-9]*/stat; do
      line=
      {
        while IFS= read -r l || [ -n "$l" ]; do line=$line$l; done <"$st"
      } 2>/dev/null || continue
      # shellcheck disable=SC2086 # split into fields on purpose
      set -- ${line##*) }
      [ "${4:-}" = "$sid_want" ] || continue
      pid=${st#/proc/}
      kill -9 "${pid%/stat}" 2>/dev/null || true
    done
  elif command -v pkill >/dev/null 2>&1; then
    pkill -9 -s "$1" 2>/dev/null || true
  fi
}
work=$(mktemp -d "${TMPDIR:-/tmp}/review-reverify.XXXXXX") || die 4 "could not create a working directory"
trap 'reap "$grp"; scrub "$work"' EXIT
work=$(cd "$work" && pwd) || die 4 "could not create a working directory"
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$work/r" || die 4 "could not create a working directory"

status=0
printf '%s\n' "$parsed" | grep '^R' >"$work/runs"
printf '%s\n' "$parsed" | grep -v '^R' >"$work/expect" || true
while IFS="$TAB" read -r _ id kind code run; do
  c=$work/r/$id
  mkdir -p "$c/home" "$c/state" "$c/tmp" || die 4 "could not set up an isolated copy for finding $id"
  {
    git -c core.hooksPath=/dev/null -c core.fsmonitor=false clone -q --shared --no-checkout "$top" "$c/copy" \
      && git -C "$c/copy" -c core.hooksPath=/dev/null -c core.fsmonitor=false checkout -q --detach "$head" \
      && git -C "$c/copy" -c core.hooksPath=/dev/null remote remove origin
  } >/dev/null 2>&1 </dev/null || die 4 "could not set up an isolated copy of $head for finding $id"
  rc=0
  # With job control off, a background child is not a group leader, so setsid
  # runs the command in place and its pid names the new session's group. The
  # record's shell marks that it started, then runs the line with no
  # positional parameters, as sh -c would.
  # shellcheck disable=SC2086,SC2016 # $signals, $session and $runner are command words or empty; the inner script expands in the record's shell
  (cd "$c/copy" && exec env -i $signals PATH="$PATH" LC_ALL=C ${TERM:+TERM="$TERM"} \
    HOME="$c/home" XDG_CONFIG_HOME="$c/home/.config" XDG_STATE_HOME="$c/home/.local/state" \
    XDG_CACHE_HOME="$c/home/.cache" XDG_DATA_HOME="$c/home/.local/share" TMPDIR="$c/tmp" \
    CLAUDE_PLUGIN_DATA="$c/state" PLANWRIGHT_FLEET_STATE_DIR="$c/state/fleet" \
    CLAUDE_DIR="$c/home/.claude" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    GIT_AUTHOR_NAME=review-reverify GIT_AUTHOR_EMAIL=review-reverify@localhost \
    GIT_COMMITTER_NAME=review-reverify GIT_COMMITTER_EMAIL=review-reverify@localhost \
    $session $runner sh -c ': >"$1" || exit 125; eval "set --; $2"' sh "$c/started" "$run") \
    >"$c/out" 2>&1 </dev/null &
  grp=$!
  wait "$grp" || rc=$?
  reap "$grp"
  grp=
  [ -e "$c/started" ] || die 4 "the command for finding $id never started"
  why=
  [ "$rc" -eq "$code" ] || why="exit $rc, expected $code"
  # The command can reach its own output file; output that cannot be read
  # proves nothing either way, so it is a regression, never a pass.
  while IFS="$TAB" read -r op eid text; do
    [ "$eid" = "$id" ] || continue
    grc=0
    grep -F -q -e "$text" "$c/out" 2>/dev/null || grc=$?
    case $grc in
      0) [ "$op" = C ] || why=${why:+$why; }"output holds '$text'" ;;
      1) [ "$op" = L ] || why=${why:+$why; }"output lacks '$text'" ;;
      *) why=${why:+$why; }"cannot read the output to check '$text'" ;;
    esac
  done <"$work/expect"
  [ -z "$log_dir" ] || cp "$c/out" "$log_dir/$id.log" 2>/dev/null \
    || die 4 "could not write the log for finding $id into --log-dir"
  if [ -z "$why" ]; then
    printf 'held\t%s\t%s\n' "$id" "$kind"
  else
    printf 'regressed\t%s\t%s\t%s\n' "$id" "$kind" "$why"
    status=1
  fi
  scrub "$c"
done <"$work/runs"
exit "$status"
