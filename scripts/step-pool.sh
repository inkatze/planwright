#!/bin/sh
# step-pool.sh — take, report, and release slots of a per-user step pool.
# doctrine/custom-steps.md (*Expensive checks*) is the normative home of what a
# pool is for and who owns a slot; this header pins the mechanics it delegates
# here. The helper executes nothing: a caller runs its check exactly as it
# would unpooled, between a take and a release, so the helper adds no surface
# a command guard has to reason about.
#
# Usage:
#   step-pool.sh take <pool> <owner-pid> [--step <id>] [--worktree <dir>]
#       [--waited <seconds>] [--for <seconds>]
#   step-pool.sh report <pool>
#   step-pool.sh release <pool> <owner-pid> [--slot <n>]
#
#   <pool>       ^[a-z][a-z0-9-]*$, at most 64 bytes (the step-id charset).
#   <owner-pid>  the process the slot belongs to, a decimal pid with no
#                leading zero. A take requires it running. The slot is held
#                ON ITS BEHALF (lock-lib's pw_lock_acquire_for), never by an
#                open descriptor, so nothing the check spawns inherits it, and
#                once that process is gone the next caller reclaims the slot.
#
# SLOTS. A pool of capacity N is the lock-lib locks slot-1 .. slot-N under
# <root>/<pool>/, <root> being $PLANWRIGHT_STEP_POOL_ROOT, else
# $XDG_STATE_HOME/planwright/step-pools, else
# $HOME/.local/state/planwright/step-pools: one per user on the host, shared by
# every checkout and worktree. Beside each slot, holder-<n> records the
# holder's token, step id, and worktree; it is believed only while its token
# is the slot's current one, so a stale or half-written file reads as an
# unknown holder rather than a wrong one.
#
# CAPACITY is step_pool_capacity_<pool> (hyphens as underscores) when set,
# else step_pool_capacity, else 1. A malformed value falls back to the next in
# that order with one warning naming its layer. Callers configured with
# different capacities each try only their own slot count, so the larger
# setting governs.
#
# take          hold one slot, waiting while none is free. The first round
#               that finds the pool full reports every live holder on stderr
#               (skipped when --waited says an earlier call already began the
#               wait). Admission is unordered: every round tries each slot,
#               reclaiming a dead holder's, so a freed slot goes to whichever
#               waiter tries it first. The wait is bounded by step_pool_wait
#               (a duration, rounded up to whole seconds; malformed, 60m with
#               one warning). --waited carries the seconds earlier calls of
#               the same wait already spent, so the bound covers the whole
#               wait; --for ends this call after that many seconds, for a
#               caller whose shell calls are capped. --step names the
#               holder's step id; without it the holder is recorded as the
#               full-suite run. --worktree defaults to the enclosing git top
#               level. stdout is one line, `<state>\t<slot>\t<waited>`,
#               <waited> the summed seconds:
#                 taken     slot <n> is held for the owner              exit 0
#                 nested    the environment's hold mark (below) names this
#                           pool and a live owner holding a slot of it, so
#                           the caller is already inside that hold: nothing
#                           is taken and nothing is printed on stderr      exit 0
#                 unpooled  the pool cannot be used (its directory or root a
#                           symbolic link, not the user's, not writable, or a
#                           lock-library error): one warning names the cause
#                           and the caller runs its check unpooled         exit 0
#                 expired   the bound passed with no slot free; stderr names
#                           the holders and stdout follows with one holder
#                           line each                                      exit 3
#                 waiting   --for ended this call before the bound         exit 4
# report        one line per live holder of the pool on stdout:
#               `holder\t<slot>\t<pid>\t<step>\t<worktree>`, <step> being
#               `(full-suite)` for the full-suite run and `?` (with <worktree>
#               `?`) when the holder file does not match the slot.
# release       free the owner's slot of the pool: `released\t<n>`. With
#               --slot only that slot is considered. A slot another owner
#               holds is never touched, and an owner holding none prints
#               `none`; an owner holding several must name one. Under a hold
#               mark naming this pool and a live owner holding a slot of it,
#               prints `nested` and frees nothing, so a check that took its
#               own pool again releases nothing of its owner's. An unusable
#               pool prints `unpooled`. Exit 0 in each case.
#
# THE HOLD MARK. A slot's owner passes the check it runs
# PLANWRIGHT_STEP_POOL_HOLD=<pool>:<owner-pid>, so a take or release reaching
# the same pool from inside that check does not wait on its own holder. A mark
# naming another pool or a dead owner, or not matching the pool charset and a
# decimal pid, is ignored. A take by an owner that already holds a slot but
# carries no mark waits like any other caller: only the mark admits nesting.
#
# Exit 2 is a usage error (an unknown verb or option, an extra argument, a
# malformed pool, pid, step, worktree, or count, an owner that is not running)
# or, from release, a slot that could not be freed.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FULL_SUITE='(full-suite)'
DEFAULT_WAIT=60m
TAB=$(printf '\t')
NL='
'

usage() {
  cat >&2 <<'EOF'
usage: step-pool.sh take <pool> <owner-pid> [--step <id>] [--worktree <dir>] [--waited <seconds>] [--for <seconds>]
       step-pool.sh report <pool>
       step-pool.sh release <pool> <owner-pid> [--slot <n>]
EOF
}
refuse() {
  printf 'step-pool: %s\n' "$1" >&2
  exit 2
}
warn() {
  printf 'step-pool: warning: %s\n' "$1" >&2
}
shown() {
  sanitize_printable "$1" '(unprintable)'
}

valid_name() {
  [ "${#1}" -le 64 ] || return 1
  case $1 in
    [a-z]*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}
valid_pid() {
  [ "${#1}" -le 10 ] || return 1
  case $1 in
    [1-9]*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!0-9]*) return 1 ;;
  esac
  return 0
}
valid_count() {
  [ "${#1}" -le 9 ] || return 1
  case $1 in
    0) return 0 ;;
    '' | 0* | *[!0-9]*) return 1 ;;
  esac
  return 0
}
# A process owned by another user answers kill -0 with EPERM; it still runs.
pid_running() {
  kill -0 "$1" 2>/dev/null && return 0
  case $(LC_ALL=C kill -0 "$1" 2>&1) in
    *[Pp]ermission* | *[Pp]ermitted*) return 0 ;;
  esac
  ps -p "$1" >/dev/null 2>&1
}

# --- arguments -------------------------------------------------------------------
verb=${1:-}
case $verb in
  take | report | release) shift ;;
  *)
    usage
    exit 2
    ;;
esac
pool=${1:-}
valid_name "$pool" || refuse "pool must match ^[a-z][a-z0-9-]*\$ (at most 64 bytes): '$(shown "$pool")'"
shift
owner=''
if [ "$verb" != report ]; then
  owner=${1:-}
  valid_pid "$owner" || refuse "owner must be a decimal process id: '$(shown "$owner")'"
  shift
fi
step=''
worktree=''
waited=0
for_secs=''
want_slot=''
while [ "$#" -gt 0 ]; do
  case "$verb:$1" in
    take:--step | take:--worktree | take:--waited | take:--for | release:--slot)
      [ "$#" -ge 2 ] || refuse "$1 needs a value"
      case $1 in
        --step)
          valid_name "$2" || refuse "--step must match ^[a-z][a-z0-9-]*\$ (at most 64 bytes): '$(shown "$2")'"
          step=$2
          ;;
        --worktree)
          case $2 in
            /*) ;;
            *) refuse "--worktree must be an absolute path: '$(shown "$2")'" ;;
          esac
          [ "$(shown "$2")" = "$2" ] || refuse "--worktree must not contain control characters"
          worktree=$2
          ;;
        --waited)
          valid_count "$2" || refuse "--waited must be a whole number of seconds: '$(shown "$2")'"
          waited=$2
          ;;
        --for)
          valid_count "$2" && [ "$2" != 0 ] || refuse "--for must be a positive whole number of seconds: '$(shown "$2")'"
          for_secs=$2
          ;;
        --slot)
          valid_count "$2" && [ "$2" != 0 ] || refuse "--slot must be a slot number: '$(shown "$2")'"
          want_slot=$2
          ;;
      esac
      shift 2
      ;;
    *)
      usage
      refuse "unexpected argument for $verb: '$(shown "$1")' (this helper runs nothing it is given)"
      ;;
  esac
done
if [ "$verb" = take ]; then
  pid_running "$owner" || refuse "owner $owner is not running"
  [ -n "$step" ] || step=$FULL_SUITE
  if [ -z "$worktree" ]; then
    worktree=$(git rev-parse --show-toplevel 2>/dev/null) || worktree=''
    [ -n "$worktree" ] || worktree=$(pwd -P)
    [ "$(shown "$worktree")" = "$worktree" ] || worktree='?'
  fi
fi

# --- the pool directory ------------------------------------------------------------
# screen <dir> <create> — 0 usable; 1 absent (only when not creating); 2
# unusable, cause in screen_cause. Only the directory's own path is checked
# for a link: a home directory reached through one is ordinary.
screen() {
  if [ ! -L "$1" ] && [ ! -e "$1" ]; then
    [ "$2" = yes ] || return 1
    # Owner-only from the first instant, parents included.
    (umask 077 && mkdir -p "$1") 2>/dev/null
  fi
  # The numeric owner is the one field ls prints alike on BSD and GNU.
  # shellcheck disable=SC2012
  _sc_owner=$(ls -ldn "$1" 2>/dev/null | awk '{ print $3 }')
  _sc_me=$(id -u 2>/dev/null)
  if [ -L "$1" ]; then
    screen_cause="$(shown "$1") is a symbolic link"
  elif [ ! -d "$1" ]; then
    screen_cause="$(shown "$1") could not be created as a directory"
  elif [ -z "$_sc_owner" ] || [ -z "$_sc_me" ] || [ "$_sc_owner" != "$_sc_me" ]; then
    screen_cause="$(shown "$1") is not owned by the running user"
  elif [ ! -w "$1" ] || [ ! -x "$1" ]; then
    screen_cause="$(shown "$1") is not writable"
  else
    return 0
  fi
  return 2
}

# locate <create> — set pool_dir, or pool_cause and return 2 (1: absent).
locate() {
  pool_dir=''
  pool_cause=''
  if [ -n "${PLANWRIGHT_STEP_POOL_ROOT:-}" ]; then
    _lc_root=$PLANWRIGHT_STEP_POOL_ROOT
  elif [ -n "${XDG_STATE_HOME:-}" ]; then
    _lc_root=$XDG_STATE_HOME/planwright/step-pools
  elif [ -n "${HOME:-}" ]; then
    _lc_root=$HOME/.local/state/planwright/step-pools
  else
    pool_cause='has no location: neither HOME nor XDG_STATE_HOME is set'
    return 2
  fi
  while :; do
    case $_lc_root in
      ?*/) _lc_root=${_lc_root%/} ;;
      *) break ;;
    esac
  done
  case $_lc_root in
    /*) ;;
    *)
      pool_cause="root must be an absolute path: $(shown "$_lc_root")"
      return 2
      ;;
  esac
  case $_lc_root in
    */. | */.. | *'#'* | *"$NL"*)
      # The link test reads the last component, and lock paths refuse `#`.
      pool_cause="root must not end in '.' or '..' or contain '#' or a newline: $(shown "$_lc_root")"
      return 2
      ;;
  esac
  screen "$_lc_root" "$1"
  _lc_rc=$?
  if [ "$_lc_rc" -eq 0 ]; then
    screen "$_lc_root/$pool" "$1"
    _lc_rc=$?
  fi
  case $_lc_rc in
    1) return 1 ;;
    2)
      pool_cause=$screen_cause
      return 2
      ;;
  esac
  if [ ! -r "$script_dir/lock-lib.sh" ]; then
    pool_cause='lock library is missing'
    return 2
  fi
  # shellcheck source=scripts/lock-lib.sh
  . "$script_dir/lock-lib.sh"
  pool_dir=$_lc_root/$pool
  return 0
}

# --- holders -----------------------------------------------------------------------
# slots — print each slot number present in the pool, ascending.
slots() {
  for _sl in "$pool_dir"/slot-*; do
    _sl=${_sl##*/slot-}
    valid_count "$_sl" && [ "$_sl" != 0 ] && printf '%s\n' "$_sl"
  done | sort -n
}

# holders — print `holder\t<slot>\t<pid>\t<step>\t<worktree>` per live holder.
holders() {
  for _ho_n in $(slots); do
    _ho_tok=$(pw_lock_owner "$pool_dir/slot-$_ho_n")
    [ -n "$_ho_tok" ] || continue
    pw_lock_owner_alive "$_ho_tok" || continue
    _ho_step='?'
    _ho_wt='?'
    if [ -f "$pool_dir/holder-$_ho_n" ] && [ ! -L "$pool_dir/holder-$_ho_n" ]; then
      IFS=$TAB read -r _ho_ftok _ho_fstep _ho_fwt <"$pool_dir/holder-$_ho_n" 2>/dev/null || :
      if [ "${_ho_ftok:-}" = "$_ho_tok" ]; then
        _ho_step=$(shown "${_ho_fstep:-?}")
        _ho_wt=$(shown "${_ho_fwt:-?}")
      fi
    fi
    printf 'holder\t%s\t%s\t%s\t%s\n' "$_ho_n" "${_ho_tok%%-*}" "$_ho_step" "$_ho_wt"
  done
}

# describe <holder lines> — the holders as one human-readable phrase.
describe() {
  _de_out=''
  _de_rest=$1
  while [ -n "$_de_rest" ]; do
    _de_line=${_de_rest%%"$NL"*}
    case $_de_rest in
      *"$NL"*) _de_rest=${_de_rest#*"$NL"} ;;
      *) _de_rest='' ;;
    esac
    [ -n "$_de_line" ] || continue
    IFS=$TAB read -r _ _ _de_pid _de_step _de_wt <<EOF
$_de_line
EOF
    if [ "$_de_step" = "$FULL_SUITE" ]; then
      _de_what='the full-suite run'
    else
      _de_what="step $_de_step"
    fi
    _de_out="${_de_out:+$_de_out; }pid $_de_pid ($_de_what, worktree $_de_wt)"
  done
  printf '%s' "${_de_out:-no live holder found}"
}

# mark_holds — 0 when the hold mark names this pool and a live owner holding a
# slot of it.
mark_holds() {
  _mh=${PLANWRIGHT_STEP_POOL_HOLD:-}
  case $_mh in
    *:*:* | '') return 1 ;;
    *:*) ;;
    *) return 1 ;;
  esac
  [ "${_mh%%:*}" = "$pool" ] || return 1
  _mh_pid=${_mh#*:}
  valid_pid "$_mh_pid" || return 1
  for _mh_n in $(slots); do
    _mh_tok=$(pw_lock_owner "$pool_dir/slot-$_mh_n")
    [ "${_mh_tok%%-*}" = "$_mh_pid" ] || continue
    pw_lock_owner_alive "$_mh_tok" && return 0
  done
  return 1
}

# --- configuration -------------------------------------------------------------------
# refused <key> <wanted> <fallback> — the one warning for a value the resolver
# would not accept: the layer and value when config-get can name them, else
# the resolver's own cause from the scratch file.
refused() {
  _rf=$("$script_dir/config-get.sh" --explain "$1" 2>/dev/null) || _rf=''
  if [ -n "$_rf" ]; then
    warn "the ${_rf%%"$TAB"*} layer sets $1 to '$(sanitize_printable "${_rf#*"$TAB"}")', not $2; falling back to $3"
    return 0
  fi
  _rf=$(tr '\n' ' ' <"$errf" 2>/dev/null) || _rf=''
  _rf=$(shown "${_rf% }")
  warn "$1 could not be read${_rf:+ ($_rf)}; falling back to $3"
}

# capacity — the pool's slot count, falling back key by key.
capacity() {
  _ca_key=step_pool_capacity_$(printf '%s' "$pool" | tr '-' '_')
  _ca_v=$("$script_dir/resolve-config-knob.sh" --key "$_ca_key" --type posint --no-degrade 2>/dev/null)
  _ca_rc=$?
  if [ "$_ca_rc" -eq 4 ]; then
    # --no-degrade also exits 4 for a malformed file in any layer, set key or
    # not, so the key's own winning value decides. The shared read below
    # reports a malformed file.
    _ca_x=$("$script_dir/config-get.sh" --explain "$_ca_key" 2>/dev/null) || _ca_x=''
    if [ -z "$_ca_x" ]; then
      _ca_rc=5
    elif valid_count "${_ca_x#*"$TAB"}" && [ "${_ca_x#*"$TAB"}" != 0 ]; then
      _ca_v=${_ca_x#*"$TAB"}
      _ca_rc=0
    fi
  fi
  case $_ca_rc in
    0)
      printf '%s' "$_ca_v"
      return 0
      ;;
    5) ;; # no layer sets the per-pool key
    *) refused "$_ca_key" 'a positive integer' step_pool_capacity ;;
  esac
  # The resolver's own warning already names a degraded overlay layer.
  if _ca_v=$("$script_dir/resolve-config-knob.sh" --key step_pool_capacity --type posint --fallback 1 2>"$errf"); then
    cat "$errf" >&2
    printf '%s' "$_ca_v"
    return 0
  fi
  refused step_pool_capacity 'a positive integer' 'the core default 1'
  printf 1
}

# wait_bound — step_pool_wait in whole seconds, rounded up.
wait_bound() {
  if _wb_v=$("$script_dir/resolve-config-knob.sh" --key step_pool_wait --type duration --fallback "$DEFAULT_WAIT" 2>"$errf"); then
    cat "$errf" >&2
  else
    refused step_pool_wait 'a duration' "the core default $DEFAULT_WAIT"
    _wb_v=$DEFAULT_WAIT
  fi
  printf '%s\n' "$_wb_v" | awk '{
    v = $0; m = 1
    if (v ~ /ms$/) { m = 0.001; sub(/ms$/, "", v) }
    else if (v ~ /s$/) { sub(/s$/, "", v) }
    else if (v ~ /m$/) { m = 60; sub(/m$/, "", v) }
    else if (v ~ /h$/) { m = 3600; sub(/h$/, "", v) }
    else if (v ~ /d$/) { m = 86400; sub(/d$/, "", v) }
    # The slack absorbs float error in the product, so 1.1h is 3960, not
    # 3961; the cap keeps the result inside shell arithmetic.
    s = v * m; if (s > 9007199254740992) s = 9007199254740992
    c = int(s); if (s - c > 2e-15 * (s > 1 ? s : 1)) c++; if (c < 1) c = 1
    printf "%d", c
  }'
}

# --- verbs -----------------------------------------------------------------------------
errf=''
# A slot taken for a long-lived owner but never reported to it would stay held
# until that owner exits, so an interrupted take gives it back. dash runs no
# EXIT trap on a fatal signal, hence the signal traps.
unreported=''
finish() {
  [ -z "$unreported" ] || pw_lock_release_token "$unreported" "$tok" 2>/dev/null
  [ -z "$errf" ] || rm -f "$errf"
}
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 141' PIPE
trap 'exit 143' TERM

if [ "$verb" = report ]; then
  locate no
  case $? in
    1) exit 0 ;;
    2)
      warn "pool $pool $pool_cause"
      exit 0
      ;;
  esac
  holders
  exit 0
fi

if [ "$verb" = release ]; then
  locate no
  case $? in
    1)
      echo none
      exit 0
      ;;
    2)
      warn "pool $pool $pool_cause; nothing released"
      echo unpooled
      exit 0
      ;;
  esac
  if mark_holds; then
    echo nested
    exit 0
  fi
  mine=''
  for n in $(slots); do
    [ -z "$want_slot" ] || [ "$n" = "$want_slot" ] || continue
    tok=$(pw_lock_owner "$pool_dir/slot-$n")
    [ -n "$tok" ] && [ "${tok%%-*}" = "$owner" ] && mine="$mine $n:$tok"
  done
  case $mine in
    '')
      echo none
      exit 0
      ;;
    ' '*' '*) refuse "owner $owner holds several slots of $pool; name one with --slot" ;;
  esac
  n=${mine# }
  tok=${n#*:}
  n=${n%%:*}
  pw_lock_release_token "$pool_dir/slot-$n" "$tok"
  case $? in
    0) printf 'released\t%s\n' "$n" ;;
    1) echo none ;;
    *) refuse "slot $n of $pool could not be released" ;;
  esac
  exit 0
fi

# take
# The clock starts before the config reads, which can take seconds on a busy
# host, so --for and the summed wait cover the whole call.
start=$(date +%s)
if ! locate yes; then
  warn "pool $pool $pool_cause; running unpooled"
  printf 'unpooled\t-\t%s\n' "$waited"
  exit 0
fi
if mark_holds; then
  printf 'nested\t-\t%s\n' "$waited"
  exit 0
fi
if ! errf=$(mktemp "${TMPDIR:-/tmp}/step-pool.XXXXXX" 2>/dev/null); then
  errf=''
  warn "pool $pool cannot be waited on: no scratch file could be created in $(shown "${TMPDIR:-/tmp}"); running unpooled"
  printf 'unpooled\t-\t%s\n' "$waited"
  exit 0
fi
cap=$(capacity)
bound=$(wait_bound)
nap=0.1
round=0
reported=''
rechecked=''
while :; do
  [ "$round" -eq 0 ] || pid_running "$owner" || refuse "owner $owner is not running"
  i=1
  while [ "$i" -le "$cap" ]; do
    pw_lock_acquire_for "$pool_dir/slot-$i" "$owner" 1 2>"$errf"
    case $? in
      0)
        tok=$PW_LOCK_TOKEN
        unreported=$pool_dir/slot-$i
        pid_running "$owner" || refuse "owner $owner is not running"
        part="$pool_dir/.holder-$i.$$"
        if (set -C && printf '%s\t%s\t%s\n' "$tok" "$step" "$worktree" >"$part") 2>/dev/null; then
          mv -f "$part" "$pool_dir/holder-$i" 2>/dev/null || rm -f "$part"
        else
          rm -f "$part"
        fi
        # A take in the first round waited for nothing, whatever second the
        # clock ticked over in meanwhile.
        [ "$round" -eq 0 ] || waited=$((waited + $(date +%s) - start))
        printf 'taken\t%s\t%s\n' "$i" "$waited" && unreported=''
        exit 0
        ;;
      1) ;;
      *)
        cause=$(shown "$(tr '\n' ' ' <"$errf")")
        warn "pool $pool lock error: ${cause:-lock-lib failed on slot $i}; running unpooled"
        [ "$round" -eq 0 ] || waited=$((waited + $(date +%s) - start))
        printf 'unpooled\t-\t%s\n' "$waited"
        exit 0
        ;;
    esac
    i=$((i + 1))
  done
  elapsed=$(($(date +%s) - start))
  total=$((waited + elapsed))
  if [ "$waited" -eq 0 ] && [ -z "$reported" ]; then
    reported=yes
    printf 'step-pool: pool %s is full (capacity %s); waiting up to %ss on: %s\n' \
      "$pool" "$cap" "$bound" "$(describe "$(holders)")" >&2
  fi
  if [ "$total" -ge "$bound" ]; then
    held=$(holders)
    if [ -z "$held" ] && [ -z "$rechecked" ]; then
      # Every holder left after this round's tries, so one more round can take
      # the freed slot rather than expire on a pool with a slot free.
      rechecked=yes
      round=$((round + 1))
      continue
    fi
    printf 'step-pool: the wait for pool %s passed its %ss bound; held by: %s\n' \
      "$pool" "$bound" "$(describe "$held")" >&2
    printf 'expired\t-\t%s\n' "$total"
    [ -z "$held" ] || printf '%s\n' "$held"
    exit 3
  fi
  if [ -n "$for_secs" ] && [ "$elapsed" -ge "$for_secs" ]; then
    printf 'waiting\t-\t%s\n' "$total"
    exit 4
  fi
  sleep "$nap" 2>/dev/null || sleep 1
  round=$((round + 1))
  case $nap in
    0.1) nap=0.25 ;;
    0.25) nap=0.5 ;;
    *) nap=1 ;;
  esac
done
