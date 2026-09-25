# shellcheck shell=sh
# shellcheck disable=SC2154 # `me` and `release_classes` are set by the rung
# fleet-stop-lib.sh — the close both session-grade rungs share (sourced, never
# executed): `scripts/fleet-streamjson.sh stop` and
# `scripts/fleet-dispatch-headless.sh stop`.
#
# The two rungs differ in what they launch and where they record it, and agree
# on everything a close does with that record: how a process is recognised as
# the worker's, how the tree is signalled, what counts as still held, and how
# the result is reported. The agreement lives here so a close fixed on one rung
# is fixed on both; the difference is handed in by the rung as data.
#
# WHAT THE RUNG SUPPLIES.
#   me                   the name every diagnostic is prefixed with
#   release_classes      the classes the rung acquires, in release order;
#                        `process` first, because a tree that will not close
#                        ends the walk (see stop_walk)
#   stop_held <class> <dir> <worker> <store>
#   stop_release <class> <dir> <worker> <store> <grace>
#                        the per-class probe and release, zero meaning held /
#                        released; the process arms call held_process and
#                        release_processes below
#   stop_process_closed <dir>
#                        what the rung does once its tree is confirmed gone,
#                        with `stop_signalled` set to 1 when this close sent the
#                        signals rather than finding the tree already gone. A
#                        rung whose pid files seed the walk must stop them doing
#                        so here: a recorded pid outlives its process, and a
#                        later close would seed its walk from whatever the host
#                        reissued it to
#
# THE MATCH. A process belongs to the worker when its argv carries the rung's
# own re-exec marker for the worker's state directory (<match>), when a pid file
# in that directory records it (<pidfiles>), or when it descends from either.
# Never a process name or a command pattern: an operator's own `claude` session
# shares a worker's command shape exactly, so a name match would kill it.
#
# Every verb that reads the process table fails closed: a table that cannot be
# read reports the process class held, and a self-hosting check that cannot
# answer refuses the close.

# The settling wait after SIGKILL, in seconds. Not operator-tunable: SIGKILL is
# not refusable, so this bounds how long the kernel takes to reap, not how long
# a process is given to cooperate.
kill_settle=5

# The largest grace a caller may ask for.
grace_max=300

# The SIGTERM-to-SIGKILL grace a caller gets without asking.
grace_default=5

stop_lf='
'

# A positive-integer token: digits only, bare zero refused (kill -0 0 probes
# the whole process group), no leading zero, <=15 digits.
stop_posnum() {
  case "$1" in
    '' | *[!0-9]* | 0*) return 1 ;;
  esac
  [ "${#1}" -le 15 ]
}

# `kill -0` answers "may I signal it", and EPERM means alive; `ps -p` answers
# existence regardless of owner.
stop_pid_live() {
  kill -0 "$1" 2>/dev/null && return 0
  ps -p "$1" >/dev/null 2>&1
}

stop_now() {
  sn_v=$(date +%s)
  case $sn_v in
    '' | *[!0-9]*)
      echo "$me: date +%s produced no epoch" >&2
      return 1
      ;;
  esac
  printf '%s' "$sn_v"
}

# stop_grace_ok <secs> — the grace is bounded as well as shaped: a close that
# waits for a century is indistinguishable from one that has hung.
stop_grace_ok() {
  stop_posnum "$1" && [ "$1" -le "$grace_max" ]
}

stop_grace_refusal() {
  echo "$me: --grace must be a whole number of seconds, 1 to $grace_max (default $grace_default)" >&2
}

# stop_scratch_walk <dir> <probe|release> <patterns> — visit every path under
# <dir> matching one of the rung's space-separated scratch patterns; zero when
# at least one was there. The list is split with globbing off and each pattern
# expanded only under <dir>, so no pattern can match in the caller's cwd.
#
# The probe and the release share one function because they must share one
# pattern list, and because the paths never become text. Handing a caller a
# newline-delimited list would split a filename containing a newline into a
# second, relative path, which the release would then delete from whatever
# directory the operator happened to run the close in; the worker can create
# such a name, and its state directory is a path it knows.
stop_scratch_walk() {
  case $- in
    *f*) sw_restore='set -f' ;;
    *) sw_restore='set +f' ;;
  esac
  sw_found=1
  set -f
  for sw_pat in $3; do
    set +f
    for sw_p in "$1"/$sw_pat; do
      [ -e "$sw_p" ] || continue
      sw_found=0
      [ "$2" = release ] || break 2
      # `rm -rf`, not `rm -f`: a lock a stale-break renamed out of the way is a
      # directory, and `rm -f` cannot remove one. The class would then read held
      # on every later close, with no re-invocation able to make progress.
      rm -rf "$sw_p" 2>/dev/null || :
    done
    set -f
  done
  $sw_restore
  return "$sw_found"
}

# stop_scratch_release <dir> <patterns> — remove the scratch, succeeding only
# when none is left behind.
stop_scratch_release() {
  stop_scratch_walk "$1" release "$2"
  ! stop_scratch_walk "$1" probe "$2"
}

# stop_ps_rows — one `<pid> <ppid> <args>` row per process on the host.
#
# `-ww` is what keeps a long argv, which carries the state-directory path the
# match keys on, from being truncated to terminal width by BSD ps; a ps that
# rejects the flag degrades to the narrow form rather than to nothing. Each
# candidate is shape-checked rather than trusted by exit status.
stop_ps_rows() {
  pr_out=$(ps -A -ww -o pid=,ppid=,args= 2>/dev/null) || pr_out=''
  if ! stop_ps_rows_shaped "$pr_out"; then
    pr_out=$(ps -A -o pid=,ppid=,args= 2>/dev/null) || pr_out=''
    stop_ps_rows_shaped "$pr_out" || return 1
  fi
  printf '%s\n' "$pr_out"
}

stop_ps_rows_shaped() {
  [ -n "$1" ] || return 1
  prs_first=${1%%"$stop_lf"*}
  while [ "${prs_first# }" != "$prs_first" ]; do
    prs_first=${prs_first# }
  done
  case ${prs_first%% *} in
    '' | *[!0-9]*) return 1 ;;
  esac
}

# stop_seeds <dir> <pidfiles> — the valid pids the worker's pid files record,
# space-separated. Only a regular file is read: the worker can replace one with
# a fifo, and a blocking read would stall the close before it signalled anything.
stop_seeds() {
  ss_out=''
  for ss_f in $2; do
    [ -f "$1/$ss_f" ] || continue
    ss_p=$(cat "$1/$ss_f" 2>/dev/null) || ss_p=''
    if stop_posnum "${ss_p:-}"; then
      ss_out="$ss_out $ss_p"
    fi
  done
  printf '%s' "$ss_out"
}

# stop_candidates <dir> <match> <pidfiles> — every live pid belonging to the
# worker, one per line. Non-zero when the host's process table cannot be read,
# so a caller reports the class held rather than assuming it is free.
#
# Two seeds. The argv seed is the rung's own re-exec marker naming the state
# directory, and the rung builds it so a sibling whose directory this one
# prefixes cannot satisfy it. Searching argv for the bare directory would
# over-match twice over: one handle prefixes another, and any process that
# merely *names* the directory — an operator tailing a capture — would be swept
# in with its whole subtree. The worker, and a re-exec whose argv cannot be
# read, come from the pids the state directory records.
#
# Descendants carry neither the argv nor a pid file, so they are reached by
# walking the parent map down from the seeds. pid 1 is never a root: an
# expansion that reached it would enumerate every orphan on the host.
#
# The caller's own process and its ancestors are excluded: a close invoked from
# inside the tree it is closing must not kill the closer mid-release. That
# exclusion is also why such a close cannot be allowed to proceed at all: the
# re-exec and the worker fall inside it while their other children do not, so
# the walk would signal part of the tree and then report the whole release set
# free. `stop_self_hosted` refuses that case before this runs.
#
# The match text goes through the environment rather than `awk -v`, which
# rewrites backslash escapes in the value it assigns: a state directory is
# taken verbatim from the operator's configuration, and a `\t` in it would
# otherwise make the comparison silently target a path nobody asked for. It is
# scoped to the awk invocation rather than exported, so the path does not end
# up in the environment of every later child of the close.
stop_candidates() {
  sc_snap=$(stop_ps_rows) || return 1
  sc_seed=$(stop_seeds "$1" "$3")
  printf '%s\n' "$sc_snap" | SC_MATCH="$2" awk -v seeds="$sc_seed" -v self_pid="$$" '
    BEGIN {
      sup = ENVIRON["SC_MATCH"]
      # `index(s, "")` is 1, so an empty match string would mark every process
      # on the host. This verb sends signals, so the one input whose emptiness
      # inverts "matches nothing" into "matches everything" is checked rather
      # than reasoned about. Exiting non-zero reports the class held.
      if (sup == "") exit 2
    }
    $1 ~ /^[0-9]+$/ {
      ppid[$1] = $2
      order[++n] = $1
      if (index($0, sup)) want[$1] = 1
    }
    END {
      m = split(seeds, s, " ")
      for (i = 1; i <= m; i++) if (s[i] != "") want[s[i]] = 1
      delete want["0"]
      delete want["1"]
      for (pass = 1; pass <= n; pass++) {
        grew = 0
        for (i = 1; i <= n; i++) {
          p = order[i]
          if (!(p in want) && (p in ppid) && (ppid[p] in want)) {
            want[p] = 1
            grew = 1
          }
        }
        if (!grew) break
      }
      # The closer, everything it descends from, and everything under it. The
      # descendants matter as much as the ancestors: this function runs in a
      # forked subshell, so a close invoked from inside the tree it closes
      # would otherwise enumerate its own scanner on every poll and never see
      # the candidate set empty. pid 0 and pid 1 are filtered from the result
      # rather than seeded here: seeding them would claim every orphan on the
      # host, including the orphaned worker a close most needs to find.
      #
      # Only the closer itself roots the descendant walk. Rooting it at the
      # ancestors as well would claim their other children — and since that
      # chain ends at pid 1, whose descendants are every process on the host,
      # the exclusion set would swallow the very tree the close is looking for
      # and every stop would report the process class released over a live
      # worker.
      p = self_pid
      for (i = 0; i <= n; i++) {
        mine[p] = 1
        if (!(p in ppid) || ppid[p] == "" || ppid[p] == "0") break
        p = ppid[p]
      }
      kin[self_pid] = 1
      for (pass = 1; pass <= n; pass++) {
        grew = 0
        for (i = 1; i <= n; i++) {
          p = order[i]
          if (!(p in kin) && (ppid[p] in kin)) {
            kin[p] = 1
            mine[p] = 1
            grew = 1
          }
        }
        if (!grew) break
      }
      # `p in ppid` is presence in the process table. The recorded pids are
      # seeded without a liveness check of their own, so a worker closed while
      # its pid files survive would otherwise report its process class held
      # forever, on pids that no longer exist.
      for (p in want) {
        if (!(p in ppid) || (p in mine)) continue
        if (p == "0" || p == "1") continue
        print p
      }
    }'
}

# stop_self_hosted <dir> <match> <pidfiles> — zero when this process is running
# inside the very tree it has been asked to close; 1 when it is not; 2 when the
# process table cannot answer.
#
# Such a close cannot work, and it fails in the worst direction. The candidate
# walk excludes the closer and everything it descends from, so the re-exec and
# the worker are invisible to it while their *other* children are not: it
# would SIGTERM and then SIGKILL part of the tree, find nothing left that it can
# see, clear the pid files as though the tree were gone, and report `stopped` —
# leaving the worker alive and half its children dead.
#
# The ancestry is tested against the argv match first, and against the
# recorded pids only when argv cannot be trusted. The two seeds fail in opposite
# directions and neither is safe alone. A pid file outlives the process it
# names, and a recycled pid is very often an ancestor of every shell on the
# host: a leftover state directory whose pid file now names the session
# manager would make every close for that handle look self-hosted and be
# refused, forever — and this verb is the only one that clears those files. The
# argv match cannot be forged that way, and the worker is spawned as a child of
# the process carrying it, so everything genuinely inside the tree is reachable
# through it. But argv is exactly what a narrow `ps` truncates, and there the
# missing match is not evidence of absence; refusing to fall back would let a
# real self-close proceed and kill part of its own tree.
#
# So the fallback is conditioned on which of those two worlds this host is in.
# When argv is readable, a missing match means no live re-exec, and an ancestor
# named by a pid file is a recycled pid to be ignored. When argv is truncated,
# the recorded pids are all there is, and the close fails closed.
stop_self_hosted() {
  # The snapshot and the verdict about its argv fidelity come from one probe.
  # Taken separately they can disagree — a transient fork failure degrades the
  # snapshot to the narrow form while an independent retry of `-ww` succeeds —
  # and the disagreement resolves toward proceeding, which is the direction that
  # kills.
  sfh_wide=1
  sfh_snap=$(ps -A -ww -o pid=,ppid=,args= 2>/dev/null) || sfh_snap=''
  if ! stop_ps_rows_shaped "$sfh_snap"; then
    sfh_wide=0
    sfh_snap=$(ps -A -o pid=,ppid=,args= 2>/dev/null) || sfh_snap=''
    stop_ps_rows_shaped "$sfh_snap" || return 2
  fi
  sfh_seed=''
  [ "$sfh_wide" = 1 ] || sfh_seed=$(stop_seeds "$1" "$3")
  printf '%s\n' "$sfh_snap" | SC_MATCH="$2" awk -v seeds="$sfh_seed" -v self_pid="$$" '
    BEGIN {
      sup = ENVIRON["SC_MATCH"]
      # See stop_candidates: an empty match would mark every process. Exit 2 is
      # the cannot-determine answer, which the caller refuses on.
      if (sup == "") exit 2
    }
    $1 ~ /^[0-9]+$/ {
      ppid[$1] = $2
      n++
      if (index($0, sup)) owner[$1] = 1
    }
    END {
      # The 0/1 filter applies to the seeds only. An argv match at pid 1 is a
      # real re-exec running as container init, and discarding it here would
      # let a self-close from inside that tree proceed.
      m = split(seeds, s, " ")
      for (i = 1; i <= m; i++) {
        if (s[i] != "" && s[i] != "0" && s[i] != "1") owner[s[i]] = 1
      }
      p = self_pid
      for (i = 0; i <= n; i++) {
        if (p in owner) exit 0
        if (!(p in ppid) || ppid[p] == "" || ppid[p] == "0" || p == "1") break
        p = ppid[p]
      }
      exit 1
    }'
}

# stop_live <space-separated pids> — the deduplicated subset still alive,
# space-separated on stdout.
stop_live() {
  sl_out=''
  for sl_p in $1; do
    stop_posnum "$sl_p" || continue
    [ "$sl_p" = 1 ] && continue
    case " $sl_out " in
      *" $sl_p "*) continue ;;
    esac
    # stop_pid_live, not `kill -0`: dropping a live-but-unsignallable pid here
    # would empty the process class and report the tree stopped over a worker
    # still running.
    stop_pid_live "$sl_p" || continue
    sl_out="$sl_out $sl_p"
  done
  printf '%s' "${sl_out# }"
}

# release_processes <dir> <match> <pidfiles> <grace> — SIGTERM the worker's
# process tree, then SIGKILL whatever is still there after <grace> seconds.
# Children do not reliably die with a parent SIGTERM, so the escalation is not
# optional.
#
# The target set accumulates in `stop_tracked` rather than being recomputed
# from scratch each round. A child that ignores SIGTERM is reparented to pid 1
# when its parent dies, which drops it out of the descendant walk entirely — a
# set rebuilt from the walk alone would then find nothing and report the class
# released while that child ran on, which is the exact leak this verb exists to
# close. Candidates discovered during the wait are folded in, so a process the
# worker forks mid-close is signalled too.
#
# The wait is bounded by wall clock rather than by a tick count: a poll costs a
# full process-table scan, so on a busy host a tick is far longer than the
# sleep and a counted grace would silently be several times the seconds the
# operator asked for.
release_processes() {
  rp_found=$(stop_candidates "$1" "$2" "$3") || {
    echo "$me: cannot read the process table; the process class is left held" >&2
    return 1
  }
  stop_tracked=$(stop_live "$stop_tracked $rp_found")
  if [ -z "$stop_tracked" ]; then
    stop_process_closed "$1"
    return
  fi
  # What `stop_process_closed` reads to tell a tree this close terminated from
  # one that was already gone.
  stop_signalled=1
  for rp_sig in TERM KILL; do
    for rp_p in $stop_tracked; do
      kill "-$rp_sig" "$rp_p" 2>/dev/null || :
    done
    case $rp_sig in
      TERM) rp_wait=$4 ;;
      *) rp_wait=$kill_settle ;;
    esac
    rp_now=$(stop_now) || return 1
    rp_until=$((rp_now + rp_wait))
    while :; do
      rp_found=$(stop_candidates "$1" "$2" "$3") || return 1
      stop_tracked=$(stop_live "$stop_tracked $rp_found")
      if [ -z "$stop_tracked" ]; then
        stop_process_closed "$1"
        return
      fi
      rp_now=$(stop_now) || return 1
      # `-le`, so the deadline is a floor: `date +%s` truncates, so a TERM sent
      # at x.999 would otherwise reach a `-lt` deadline a millisecond later and
      # escalate having given the worker no grace at all.
      [ "$rp_now" -le "$rp_until" ] || break
      sleep 0.1
    done
  done
  return 1
}

# held_process <dir> <match> <pidfiles> [<residue>] — <residue> names the pid
# files whose mere presence holds the class, and defaults to <pidfiles>.
held_process() {
  hp_found=$(stop_candidates "$1" "$2" "$3") || return 0
  [ -n "$(stop_live "$stop_tracked $hp_found")" ] && return 0
  # A pid file recording nothing live is still this class's residue, and the
  # close has to reach it: a re-exec killed before its own cleanup leaves the
  # file behind, and once the host reuses that pid the rung refuses the handle
  # as already running with nothing able to clear it.
  for hp_f in ${4-$3}; do
    [ -e "$1/$hp_f" ] && return 0
  done
  return 1
}

# held_attention <store> <worker>. The attention store's layout is read
# directly, as the sibling fleet scripts already read it: fleet-attention.sh
# exposes `clear` but no query, and the row's presence is what "held" means
# here. The string coercion is that script's own comparison discipline — a
# bare `$1 == w` equates all-numeric handles (`1`, `01`, `1.0`) and would
# report the wrong worker's row.
#
# A store that exists but cannot be read counts as held: the same fail-closed
# posture the process probe takes, so an unreadable store cannot make a class
# that is still occupied report as released.
held_attention() {
  [ -f "$1" ] || return 1
  [ -r "$1" ] || return 0
  awk -F'\t' -v w="$2" '($1 "") == (w "") { found = 1 } END { exit found ? 0 : 1 }' "$1" 2>/dev/null
  ha_rc=$?
  # Three outcomes from two exit codes plus everything else. The walk reads any
  # non-zero as "not held" and skips the class, so an awk that failed outright
  # — a broken tool, an I/O error mid-read — would silently take the attention
  # class out of the release set and let the close report success it never
  # earned. Only a clean exit 1 means not held; anything the tool could not
  # answer counts as held, and the close reports partial instead.
  case $ha_rc in
    1) return 1 ;;
    *) return 0 ;;
  esac
}

# stop_refuse_self_hosted <dir> <match> <pidfiles> <worker> — end the process
# when the close may not proceed. "Cannot determine" is refused rather than
# treated as "not inside": proceeding on an unreadable table is the direction
# that signals.
stop_refuse_self_hosted() {
  stop_self_hosted "$1" "$2" "$3"
  case $? in
    0)
      echo "$me: refusing to close $4 from inside its own process tree" >&2
      exit 3
      ;;
    1) ;;
    *)
      echo "$me: cannot read the process table; refusing to close $4" >&2
      exit 2
      ;;
  esac
}

# stop_walk <dir> <worker> <store> <grace> — take every class of
# `release_classes` still held, print the one-line result, and return 0 for
# `stopped` / `already-closed` or 6 for `partial`.
#
# Idempotent over the release set rather than the invocation: a class already
# free is skipped, so a repeat against a fully released worker signals nothing
# and reports `already-closed`, while a repeat after a partial close retries
# only what remains.
stop_walk() {
  stop_tracked=''
  # shellcheck disable=SC2034 # read by the rung's stop_process_closed
  stop_signalled=0
  st_released=''
  st_held=''
  for st_class in $release_classes; do
    stop_held "$st_class" "$1" "$2" "$3" || continue
    stop_release "$st_class" "$1" "$2" "$3" "$4" || :
    if stop_held "$st_class" "$1" "$2" "$3"; then
      st_held="$st_held,$st_class"
      # A worker whose tree could not be closed is still running. Releasing the
      # rest of its runtime from under it would take away the channel an
      # operator answers it on and the lock that protects its records, so the
      # walk stops here and reports what is still held.
      [ "$st_class" = process ] && break
    else
      st_released="$st_released,$st_class"
    fi
  done
  st_released=${st_released#,}
  st_held=${st_held#,}

  if [ -n "$st_held" ]; then
    printf 'stop %s partial released=%s held=%s\n' \
      "$2" "${st_released:--}" "$st_held"
    return 6
  fi
  if [ -z "$st_released" ]; then
    printf 'stop %s already-closed\n' "$2"
    return 0
  fi
  printf 'stop %s stopped released=%s\n' "$2" "$st_released"
  return 0
}
