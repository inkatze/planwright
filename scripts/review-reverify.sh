#!/bin/sh
# review-reverify.sh — re-verify every earlier finding's fix by re-running what
# validated it, so a fix that regresses outside the next pass's delta is still
# caught (review-effectiveness REQ-A1.7, REQ-C1.1, D-14).
#
# THE RECORDED-REPRODUCTION FORMAT. A text file whose first line is
# `review-repro 1`; blank lines and `#` comment lines are ignored. Each record
# starts at a `finding <id>` line (the id is letters, digits, and . _ -, unique
# in the file) and holds, one per line:
#   kind <reproduction|test|rule>  what validated the finding: the real surface
#                                  invoked with the triggering input, the
#                                  targeted test, or the tool rule
#   run <command>                  exactly one; a shell command line, run by sh
#                                  from the copy's root
#   exit <n>                       the exit code the fixed behaviour gives
#   output-contains <text>         optional, repeatable: a fixed string the
#                                  combined stdout and stderr must hold
#   output-lacks <text>            optional, repeatable: one it must not hold
# No line may hold a tab. The whole file is validated before anything runs.
#
# THE COPY. Each record runs in its own fresh isolated copy of the committed
# head (or --head): a shared clone in a temporary directory with its remote
# removed, the command's home, XDG directories, and machine-local state home
# (CLAUDE_PLUGIN_DATA) redirected into it, removed on exit. Never the live
# worktree, whose uncommitted edits do not reach the copy. The copy isolates
# the repository, not the host: a command naming an absolute path outside it
# still reaches that path. The reviewing session's own home and credentials
# are untouched, and none are copied in.
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
#              timed-out command reports its exit code (124)
#
# Exit codes: 0 every fix held (or no records); 1 one or more regressed; 2
#   usage or a malformed records file; 4 a copy could not be set up.
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

prog=review-reverify
TAB=$(printf '\t')

usage() {
  cat >&2 <<EOF
usage: $prog --records <file> [--head <rev>] [--timeout <seconds>] [--log-dir <dir>]
EOF
  exit 2
}
die() {
  printf '%s\n' "$prog: $2" >&2
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
case $timeout_s in '' | 0 | *[!0-9]*) die 2 "--timeout must be a positive whole number of seconds" ;; esac
if [ -n "$log_dir" ]; then
  [ -d "$log_dir" ] && [ -w "$log_dir" ] || die 2 "--log-dir is not a writable directory"
  log_dir=$(cd "$log_dir" && pwd)
fi

# --- validate and normalize ---------------------------------------------------
# Each record becomes `R <id> <kind> <exit> <run>`, then `C <id> <text>` and
# `L <id> <text>` per expected and forbidden output.

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
  /^[ ]*$/ || /^#/ { next }
  {
    field = $1
    value = $0
    sub(/^[^ ]+ ?/, "", value)
    if (field == "finding") {
      close_rec()
      if (value !~ /^[A-Za-z0-9._-]+$/ || value ~ /^\.+$/) bad("finding ids are letters, digits, and . _ -")
      if (value in seen) bad("finding " value " is repeated")
      seen[value] = 1
      id = value; kind = ""; runs = 0; run = ""; code = ""; expect = ""
      next
    }
    if (id == "") bad("a " field " line before any finding line")
    if (field == "kind") {
      if (value !~ /^(reproduction|test|rule)$/) bad("kind must be reproduction, test, or rule")
      kind = value
    } else if (field == "run") {
      if (value == "") bad("an empty run line")
      runs++; run = value
    } else if (field == "exit") {
      if (value !~ /^[0-9]+$/ || value + 0 > 255) bad("exit must be a code from 0 to 255")
      code = value + 0
    } else if (field == "output-contains" || field == "output-lacks") {
      if (value == "") bad("an empty " field " line")
      expect = expect (field == "output-contains" ? "C" : "L") "\t" id "\t" value "\n"
    } else bad("unknown field: " field)
  }
  END { if (!failed) close_rec() }' "$records" 2>&1) || die 2 "malformed records file: $parsed"

if ! printf '%s\n' "$parsed" | grep -q '^R'; then
  printf 'no records to re-verify\n'
  exit 0
fi

top=$(git rev-parse --show-toplevel 2>/dev/null) || die 2 "not inside a git work tree"
case $head_rev in -*) die 2 "--head must be a revision, not an option" ;; esac
head=$(git rev-parse --verify --quiet "$head_rev^{commit}") || die 2 "--head names no commit: $head_rev"

runner=
if command -v timeout >/dev/null 2>&1; then runner="timeout $timeout_s"; fi

work=$(mktemp -d "${TMPDIR:-/tmp}/review-reverify.XXXXXX")
trap 'rm -rf "$work"' EXIT

status=0
printf '%s\n' "$parsed" | grep '^R' >"$work/runs"
printf '%s\n' "$parsed" | grep -v '^R' >"$work/expect" || true
while IFS="$TAB" read -r _ id kind code run; do
  c=$work/$id
  mkdir -p "$c/home" "$c/state"
  {
    git clone -q --shared --no-checkout "$top" "$c/copy" \
      && git -C "$c/copy" checkout -q --detach "$head" \
      && git -C "$c/copy" remote remove origin
  } >/dev/null 2>&1 </dev/null || die 4 "could not set up an isolated copy of $head for finding $id"
  rc=0
  (
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
    cd "$c/copy"
    HOME=$c/home XDG_CONFIG_HOME=$c/home/.config XDG_STATE_HOME=$c/home/.local/state \
      XDG_CACHE_HOME=$c/home/.cache XDG_DATA_HOME=$c/home/.local/share CLAUDE_PLUGIN_DATA=$c/state \
      $runner sh -c "$run"
  ) >"$c/out" 2>&1 </dev/null || rc=$?
  why=
  [ "$rc" -eq "$code" ] || why="exit $rc, expected $code"
  while IFS="$TAB" read -r op eid text; do
    [ "$eid" = "$id" ] || continue
    if grep -F -q -e "$text" "$c/out"; then
      [ "$op" = C ] || why=${why:+$why; }"output holds '$text'"
    else
      [ "$op" = L ] || why=${why:+$why; }"output lacks '$text'"
    fi
  done <"$work/expect"
  [ -z "$log_dir" ] || cp "$c/out" "$log_dir/$id.log"
  if [ -z "$why" ]; then
    printf 'held\t%s\t%s\n' "$id" "$kind"
  else
    printf 'regressed\t%s\t%s\t%s\n' "$id" "$kind" "$why"
    status=1
  fi
  rm -rf "$c"
done <"$work/runs"
exit "$status"
