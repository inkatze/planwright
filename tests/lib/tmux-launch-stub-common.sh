# shellcheck shell=sh
# shellcheck disable=SC2034 # the STUB_* results are read by the sourcing stub
# tmux-launch-stub-common.sh — helpers shared by the launch fixture harness and
# its stubs (sourced, never executed). Every function reads the stub state
# directory from $STUB_STATE. They set variables rather than print where they
# can: every stub call pays for its forks, and launch fixtures make many.
#
# Exclusive claims are symbolic links, never `mkdir`: `ln -s` either creates
# the path or fails, which is the one primitive scripts/lock-lib.sh trusts
# across the hosts the suite runs on. A recorded pid carries its process's
# start time, so the reaper never signals a pid the system has since handed
# to another process.

# The temp-name suffix of this process's writes. A subshell shares its
# parent's `$$`, so one that writes beside its parent sets its own.
STUB_WRITER=$$
STUB_TAB=$(printf '\t')

# stub_claim_seq <kind> — claim the next free number for <kind> and set
# STUB_SEQ to it, six digits. Claims are never released, so their count is
# where to start looking.
stub_claim_seq() {
  [ -d "$STUB_STATE/seq" ] || return 1
  scs_kind=$1
  set -- "$STUB_STATE/seq/$scs_kind".*
  scs_n=$#
  [ -L "$1" ] || scs_n=0
  scs_n=$((scs_n + 1))
  while [ "$scs_n" -lt 1000000 ]; do
    scs_id=$((1000000 + scs_n))
    scs_id=${scs_id#1}
    if ln -s "$STUB_WRITER" "$STUB_STATE/seq/$scs_kind.$scs_id" 2>/dev/null; then
      STUB_SEQ=$scs_id
      return 0
    fi
    scs_n=$((scs_n + 1))
  done
  return 1
}

# stub_write_file <dest> <content> — <content> to <dest> through a temp name
# private to this writer, then a rename.
stub_write_file() {
  swf_tmp="${1%/*}/.tmp.$STUB_WRITER"
  printf '%s' "$2" >"$swf_tmp" && mv -f "$swf_tmp" "$1"
}

# stub_knob <name> <default> — set STUB_KNOB to the knob's value, or the
# default.
stub_knob() {
  STUB_KNOB=''
  if [ -r "$STUB_STATE/knobs/$1" ]; then
    IFS= read -r STUB_KNOB <"$STUB_STATE/knobs/$1" || true
  fi
  [ -n "$STUB_KNOB" ] || STUB_KNOB=$2
}

# stub_proc_stamp <pid> — the process's start time as ps prints it, empty
# when unknown.
stub_proc_stamp() {
  ps -o lstart= -p "$1" 2>/dev/null
}

stub_record_pid() {
  stub_write_file "$STUB_STATE/pids/$1" "$(stub_proc_stamp "$1")"
}

# stub_pid_ours <pid> — 0 while the process recorded under pids/ still runs
# and is the process that was stamped. A stamp that cannot be read, then or
# now, falls back to the pid alone.
stub_pid_ours() {
  kill -0 "$1" 2>/dev/null || return 1
  spo_want=''
  if [ -r "$STUB_STATE/pids/$1" ]; then
    IFS= read -r spo_want <"$STUB_STATE/pids/$1" || true
  fi
  [ -z "$spo_want" ] && return 0
  spo_now=$(stub_proc_stamp "$1")
  [ -z "$spo_now" ] || [ "$spo_now" = "$spo_want" ]
}

# stub_kill_tree <signal> <pid> — the pid and its descendants, children first,
# from one process-table snapshot.
stub_kill_tree() {
  for skt_p in $(ps -A -o pid= -o ppid= 2>/dev/null | awk -v r="$2" '
    { kids[$2] = kids[$2] " " $1 }
    function walk(p,   n, i, a) { n = split(kids[p], a, " "); for (i = 1; i <= n; i++) walk(a[i]); print p }
    END { walk(r) }'); do
    kill "-$1" "$skt_p" 2>/dev/null
  done
  return 0
}
