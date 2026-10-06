# shellcheck shell=bash
# fixture-procs.sh — find, reap, and refuse to leave behind the processes a
# suite's fixtures start (sourced, never executed). A fixture's supervisor,
# tick, and shim carry the suite's scratch directory in their argv (the shim
# path, the fleet home), so that path seeds the match and each seed's live
# descendants join it: a shim's bare `sleep` names no path but dies with the
# reap. No pid file is trusted to name a process a failed case never recorded.
# What the path match cannot tell apart is a process that merely names the
# directory, such as an operator tailing a capture while the suite runs, and
# with it that process's descendants.
#
#   fixture_scratch          make the suite's scratch directory and print its
#                            path; only a directory inside one is a needle
#   fixture_procs <dir/>     one `<pid> <args>` row per matched process, the
#                            suite's own shell excluded; exit 2 when the
#                            process table cannot be read, so a guard never
#                            passes on a snapshot it did not get
#   fixture_none <dir/>      succeeds only on a readable table with no match
#   fixture_reap <dir/>      SIGTERM the matches, SIGKILL whatever is left
#                            after about two seconds; names survivors on
#                            stderr and returns 1 if any outlive the KILL, or
#                            when a snapshot is refused, before any signal for
#                            a bad needle and possibly after the TERM pass for
#                            a table that stops reading
#   fixture_report <dir/>    the matched rows on one line, or the refusal, for
#                            a failure message
#   fixture_is_owner         succeeds only in the suite's own process: bash
#                            runs the EXIT trap in a backgrounded child
#                            signalled before it reaches exec, and that child
#                            must not tear the suite down under itself
#
# <dir/> must be an existing directory at or under one fixture_scratch made,
# written with its trailing slash. The proof is a `fixture.*` directory, not a
# symlink and owned by this user, holding the marker it leaves, so a marker
# someone else planted, or a link pointing at one of ours, is not trusted. An empty
# `mktemp -d` result would otherwise make the needle `/`, and a broad one such
# as `$HOME/` matches the processes the suite runs under and all their
# descendants. Reading the marker rather than comparing against $TMPDIR keeps
# the rule independent of where mktemp chose to put the directory.
# Only `ps -ww` is read: a narrower table can cut the path out of an argv, and a
# guard reading it would pass on processes it never saw.
# Matched in-shell over a captured `ps` snapshot: a `grep` or `pgrep` for the
# path would find its own argv.

_fp_owner=$(exec sh -c 'echo "$PPID"')

fixture_is_owner() {
  local me
  me=$(exec sh -c 'echo "$PPID"')
  # A probe whose fork failed answers nothing; treating that as "not the
  # owner" would skip the whole teardown in the one process that owns it.
  [ -z "$me" ] || [ -z "$_fp_owner" ] || [ "$me" = "$_fp_owner" ]
}

fixture_scratch() {
  local d
  d=$(mktemp -d "${TMPDIR:-/tmp}/fixture.XXXXXX") || return 1
  : >"$d/.fixture-procs" || {
    rmdir "$d"
    return 1
  }
  # A relative TMPDIR gives a relative path, which no needle may be.
  case $d in
    /*) ;;
    *) d=$(cd "$d" && pwd) || return 1 ;;
  esac
  printf '%s\n' "$d"
}

_fp_needle_ok() {
  local d
  case $1 in
    /?*/) [ -d "$1" ] || return 1 ;;
    *) return 1 ;;
  esac
  d=${1%/}
  while [ -n "$d" ]; do
    case ${d##*/} in
      fixture.?*) [ ! -L "$d" ] && [ -O "$d" ] && [ -f "$d/.fixture-procs" ] && return 0 ;;
    esac
    d=${d%/*}
  done
  return 1
}

# Every row leads with a numeric pid and ppid, or this is not a process table.
_fp_table_ok() {
  printf '%s\n' "$1" | awk 'NF { n++; if ($1 !~ /^[0-9]+$/ || $2 !~ /^[0-9]+$/) bad = 1 } END { exit (n && !bad) ? 0 : 1 }'
}

fixture_procs() {
  local needle=$1 snap
  _fp_needle_ok "$needle" || {
    echo "fixture_procs: refusing needle '$needle': not an existing directory under a fixture_scratch directory" >&2
    return 2
  }
  snap=$(ps -A -ww -o pid=,ppid=,args= 2>/dev/null) || snap=''
  _fp_table_ok "$snap" || {
    echo "fixture_procs: no usable process table on this host" >&2
    return 2
  }
  printf '%s\n' "$snap" | FP_NEEDLE=$needle FP_SELF=$_fp_owner awk '
    NF {
      pid[NR] = $1; ppid[NR] = $2
      args = $0
      sub(/^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]*/, "", args)
      line[NR] = args
      if (index(args, ENVIRON["FP_NEEDLE"]) && $1 != ENVIRON["FP_SELF"]) hit[$1] = 1
    }
    END {
      do {
        grew = 0
        for (i = 1; i <= NR; i++)
          if ((ppid[i] in hit) && !(pid[i] in hit) && pid[i] != ENVIRON["FP_SELF"]) { hit[pid[i]] = 1; grew = 1 }
      } while (grew)
      for (i = 1; i <= NR; i++) if (pid[i] in hit) print pid[i], line[i]
    }'
}

fixture_none() {
  local rows
  rows=$(fixture_procs "$1") || return 1
  [ -z "$rows" ]
}

fixture_report() {
  fixture_procs "$1" 2>&1 | tr '\n' ';'
}

# _fp_alive <pid...> — the given pids that are still running, zombies excluded.
_fp_alive() {
  local p st
  for p in "$@"; do
    st=$(ps -p "$p" -o stat= 2>/dev/null) || continue
    case $st in '' | Z*) ;; *) printf '%s\n' "$p" ;; esac
  done
}

fixture_reap() {
  local needle=$1 sig rows p end seen='' left
  for sig in TERM KILL; do
    rows=$(fixture_procs "$needle") || return 1
    # A descendant matched only through its parent leaves the match once that
    # parent dies and it is reparented, so every pid seen stays a target until
    # it is gone. The window in which one could be reused is this grace.
    seen="$seen $(printf '%s\n' "$rows" | awk 'NF { print $1 }')"
    # shellcheck disable=SC2086 # one pid per word
    left=$(_fp_alive $seen)
    [ -n "$left" ] || return 0
    for p in $left; do
      kill -s "$sig" "$p" 2>/dev/null
    done
    # Bounded by the clock, not a poll count: each poll takes a full `ps`
    # snapshot, which on a loaded host costs more than the sleep between them.
    end=$((SECONDS + 3))
    # shellcheck disable=SC2086
    while [ "$SECONDS" -lt "$end" ] && { ! fixture_none "$needle" || [ -n "$(_fp_alive $seen)" ]; }; do
      sleep 0.1
    done
  done
  rows=$(fixture_procs "$needle") || return 1
  # shellcheck disable=SC2086
  left=$(_fp_alive $seen)
  [ -z "$rows" ] && [ -z "$left" ] && return 0
  echo "fixture_reap: process(es) survived SIGKILL: $(printf '%s\n' "$rows" "$left" | tr '\n' ';')" >&2
  return 1
}
