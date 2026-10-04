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
    if ln -sn "$STUB_WRITER" "$STUB_STATE/seq/$scs_kind.$scs_id" 2>/dev/null; then
      STUB_SEQ=$scs_id
      return 0
    fi
    # Only a claim someone else holds moves us on; any other failure (a
    # full disk, a state directory already removed) would loop forever.
    [ -L "$STUB_STATE/seq/$scs_kind.$scs_id" ] || return 1
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

# stub_kill_tree <signal> <pid>... — each pid and its descendants. The trees
# are frozen first, parents before children and re-walked until no new
# process appears, so no parent can fork past the walk or have a child
# reparented out of it; then every member gets <signal> and is continued.
# STUB_TREE is set to the members, so a follow-up KILL can reach one whose
# parent has since exited and taken it out of the tree. The calling process
# and its ancestors (a session's command killing its own session) are never
# frozen, or the call would stop itself; its ancestors are still signalled.
stub_kill_tree() {
  skt_sig=$1
  shift
  skt_all=''
  skt_round=0
  while [ "$skt_round" -lt 5 ]; do
    skt_out=$(ps -A -o pid= -o ppid= 2>/dev/null | awk -v roots="$*" -v seen="$skt_all" -v self="$$" '
      { kids[$2] = kids[$2] " " $1; parent[$1] = $2 }
      function walk(p,   m, j, a) {
        if (p != self && !(p in old)) print ((p in anc) ? "a " : "m ") p
        m = split(kids[p], a, " ")
        for (j = 1; j <= m; j++) walk(a[j])
      }
      END {
        for (p = self; p in parent && p > 1; p = parent[p]) anc[parent[p]] = 1
        n = split(seen, s, " "); for (i = 1; i <= n; i++) old[s[i]] = 1
        n = split(roots, r, " "); for (i = 1; i <= n; i++) walk(r[i])
      }')
    [ -n "$skt_out" ] || break
    skt_new=''
    skt_anc=''
    while read -r skt_kind skt_p; do
      case $skt_kind in
        m) skt_new="$skt_new $skt_p" ;;
        a) skt_anc="$skt_anc $skt_p" ;;
      esac
    done <<EOF
$skt_out
EOF
    for skt_p in $skt_new; do kill -STOP "$skt_p" 2>/dev/null; done
    skt_all="$skt_all $skt_new $skt_anc"
    skt_round=$((skt_round + 1))
  done
  for skt_p in $skt_all; do kill "-$skt_sig" "$skt_p" 2>/dev/null; done
  for skt_p in $skt_all; do kill -CONT "$skt_p" 2>/dev/null; done
  STUB_TREE=$skt_all
  return 0
}
