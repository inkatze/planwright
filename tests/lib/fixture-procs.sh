# shellcheck shell=bash
# fixture-procs.sh — find, reap, and refuse to leave behind the processes a
# suite's fixtures start (sourced, never executed). Every process such a suite
# starts carries its scratch directory in its argv (the shim path, the fleet
# home), so that path is the match: no pid file is trusted to name a process a
# failed case never recorded, and no name pattern can reach a sibling suite's
# fixture or a real worker.
#
#   fixture_procs <needle>   one `<pid> <args>` row per live process whose argv
#                            contains <needle>, the calling shell excluded
#   fixture_reap <needle>    SIGTERM those, SIGKILL whatever is left after a
#                            short grace; returns 1 if any survive the KILL
#   fixture_owner            succeeds only in the suite's own process: bash runs
#                            the EXIT trap in a backgrounded child signalled
#                            before it reaches exec, and that child must not
#                            tear the suite down under itself
#
# Matched in-shell over a captured `ps` snapshot: a `grep` or `pgrep` for the
# path would find its own argv.

_fp_owner=$(exec sh -c 'echo "$PPID"')

fixture_owner() {
  [ "$(exec sh -c 'echo "$PPID"')" = "$_fp_owner" ]
}

fixture_procs() {
  local needle=$1 snap p a
  [ -n "$needle" ] || return 0
  snap=$(ps -A -ww -o pid=,args= 2>/dev/null) || snap=''
  case ${snap%%"
"*} in
    *[0-9]*) ;;
    *) snap=$(ps -A -o pid=,args= 2>/dev/null) || snap='' ;;
  esac
  while read -r p a; do
    [ -n "$p" ] || continue
    [ "$p" = "$_fp_owner" ] && continue
    case $a in
      *"$needle"*) printf '%s %s\n' "$p" "$a" ;;
    esac
  done <<EOF
$snap
EOF
}

fixture_reap() {
  local needle=$1 sig rows p t
  for sig in TERM KILL; do
    rows=$(fixture_procs "$needle")
    [ -n "$rows" ] || return 0
    while read -r p _; do
      kill -s "$sig" "$p" 2>/dev/null
    done <<EOF
$rows
EOF
    t=0
    while [ "$t" -lt 20 ] && [ -n "$(fixture_procs "$needle")" ]; do
      sleep 0.1
      t=$((t + 1))
    done
  done
  [ -z "$(fixture_procs "$needle")" ]
}
