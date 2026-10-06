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
#   fixture_procs <dir/>     one `<pid> <args>` row per matched process, the
#                            suite's own shell excluded; exit 2 when the
#                            process table cannot be read, so a guard never
#                            passes on a snapshot it did not get
#   fixture_none <dir/>      succeeds only on a readable table with no match
#   fixture_reap <dir/>      SIGTERM the matches, SIGKILL whatever is left
#                            after a short grace; names survivors on stderr and
#                            returns 1 if any outlive the KILL, or, signalling
#                            nothing, when fixture_procs refuses (exit 2)
#   fixture_is_owner         succeeds only in the suite's own process: bash
#                            runs the EXIT trap in a backgrounded child
#                            signalled before it reaches exec, and that child
#                            must not tear the suite down under itself
#
# <dir/> must be an existing directory strictly inside the temporary directory
# `mktemp -d` uses, written with its trailing slash: an empty `mktemp -d`
# result would otherwise make the needle `/`, and a broad one such as `$HOME/`
# matches the processes the suite runs under and all their descendants.
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

_fp_needle_ok() {
  local base=${TMPDIR:-/tmp}
  base=${base%/}
  case $1 in
    "$base"/?*/) [ -d "$1" ] ;;
    *) return 1 ;;
  esac
}

# Every row leads with a numeric pid and ppid, or this is not a process table.
_fp_table_ok() {
  printf '%s\n' "$1" | awk 'NF { n++; if ($1 !~ /^[0-9]+$/ || $2 !~ /^[0-9]+$/) bad = 1 } END { exit (n && !bad) ? 0 : 1 }'
}

fixture_procs() {
  local needle=$1 snap
  _fp_needle_ok "$needle" || {
    echo "fixture_procs: refusing needle '$needle': not an existing directory inside ${TMPDIR:-/tmp}" >&2
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

fixture_reap() {
  local needle=$1 sig rows p t
  for sig in TERM KILL; do
    rows=$(fixture_procs "$needle") || return 1
    [ -n "$rows" ] || return 0
    while read -r p _; do
      kill -s "$sig" "$p" 2>/dev/null
    done <<EOF
$rows
EOF
    t=0
    while [ "$t" -lt 20 ] && ! fixture_none "$needle"; do
      sleep 0.1
      t=$((t + 1))
    done
  done
  rows=$(fixture_procs "$needle") || return 1
  [ -z "$rows" ] && return 0
  echo "fixture_reap: process(es) survived SIGKILL: $(printf '%s\n' "$rows" | tr '\n' ';')" >&2
  return 1
}
