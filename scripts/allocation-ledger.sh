#!/bin/sh
# allocation-ledger.sh — the PER-UNIT allocation ledger: the authoritative,
# append-only store every tier decision is derived from (model-allocation
# Task 2; D-6, D-8; REQ-C1.1, REQ-F1.1, REQ-F1.3).
#
# WHY PER-UNIT, NOT THE SHARED TRAIL (D-6). fleet-audit.sh's trail carries a
# fixed six-field row with no unit or step identity and no row sequence, prunes
# whole days out from under derived state, and copy-rewrites its whole day file
# per append (the recorded write-amplification observation) — all of which a
# per-launch allocation record would hit hard. So allocation records live in
# their OWN store, partitioned one file per unit: derivation gets a real key and
# a bounded scan, the lock is per-unit so cross-unit work never contends, and
# retention is decoupled from the shared trail. Governance events still MIRROR
# one sparse row each into fleet-audit (allocation-adapt.sh's job), so the
# fleet-wide dashboards keep their single surface.
#
# WHERE. <fleet-home>/allocation/<unit>.tsv, with <fleet-home> resolved by
# scripts/fleet-state.sh (the cross-spec home, D-11) — consumed, never
# re-implemented.
#
# THE PINNED SCHEMA (D-6, REQ-F1.1). One TAB-separated row per record, fifteen
# fields, in this order:
#
#    1 seq        per-unit sequence number, from 1, strictly increasing
#    2 ts         epoch seconds, stamped under the lock (commit time)
#    3 unit       the unit identity this ledger belongs to
#    4 step       the step identity, or `-`
#    5 attempt    the attempt number
#    6 event      the event class (the closed set in allocation-ladder.sh)
#    7 prop_model    \  the PROPOSED tier: what the ladder resolved to before
#    8 prop_effort   /  any clamp was applied
#    9 clamp_model   \  the CLAMPED tier: the proposal after the consumed
#   10 clamp_effort  /  upstream contracts bound it
#   11 res_model     \  the RESOLVED tier: what the launch actually uses
#   12 res_effort    /  (`-` when nothing was resolved, e.g. a withheld unit)
#   13 scope      `unit` (moves the unit's tier) or `step` (this launch only)
#   14 outcome    resolved | applied | withheld | denied | ignored | no-op |
#                 inherit | degraded
#   15 inputs     a bounded `key=value;...` list: trigger, rung, clamps
#                 applied, fallback or inheritance taken
#
# `ts` and `outcome` are additive to D-6's named field list. The timestamp is
# what makes a row readable in time order beside the shared trail; `outcome` is
# what REQ-F1.1's "including ignore, denial, no-op, and inheritance outcomes"
# needs a home for, and giving it a column rather than burying it in the free
# `inputs` text is what lets derivation and the tests read it structurally.
#
# DERIVATION IS MEMORYLESS (REQ-C1.1). `derive` replays the rows against the
# CONFIGURED starting tier passed in by the caller — the tier is never stored as
# a current value. Same rows plus same config yields the same tier, every time;
# change the configured starting tier and the whole replay moves with it. The
# ladder rules themselves live in the sourced scripts/allocation-ladder.sh, so
# this script and allocation-adapt.sh share one implementation of them.
#
# THE PER-UNIT LOCK (D-6). `append` derives the next sequence number and writes
# the row under ONE hold of the unit's own advisory lock (an atomic mkdir with a
# stale break, the same discipline as fleet-state.sh's cross-spec lock, at
# per-unit scope). A caller that needs derive-then-append to be one critical
# section — the engine, deciding a tier from the same rows it is about to extend
# — takes the lock itself and sets PLANWRIGHT_ALLOC_LOCK_HELD to the unit, which
# suppresses the nested acquire this non-reentrant primitive would deadlock on.
# The suppression is scoped to that exact unit: a stale or inherited value for
# some OTHER unit never disables locking here.
#
# The row itself is a single bounded `>>` write (every field grammar-capped, the
# whole row well under PIPE_BUF), so even the lockless read path can never
# observe a half-written row.
#
# DEGRADED MODE (REQ-F1.1). `health` reports whether the store can be trusted:
# an unreadable file, a torn or short row, an out-of-enum field, or a
# non-monotone sequence is UNHEALTHY. `last-tier` stays readable either way, so
# an unhealthy unit can still launch at its last recorded tier with adjustments
# suspended rather than being blocked — the caller's decision, surfaced by
# allocation-adapt.sh.
#
# Usage:
#   allocation-ledger.sh home                     print the allocation store dir
#   allocation-ledger.sh path <unit>              print a unit's ledger path
#   allocation-ledger.sh lock <unit>              acquire the per-unit lock and
#                                                 print its OWNER TOKEN
#   allocation-ledger.sh unlock <unit> [<token>]  release it (idempotent). With
#                                                 the token, the release happens
#                                                 only if the lock is still ours

#   allocation-ledger.sh append <unit> <step> <attempt> <event> \
#       <prop-model> <prop-effort> <clamp-model> <clamp-effort> \
#       <res-model> <res-effort> <scope> <outcome> <inputs>
#   allocation-ledger.sh rows <unit>              print the unit's rows
#   allocation-ledger.sh health <unit>            0 healthy, 3 unhealthy
#   allocation-ledger.sh last-tier <unit>         last RESOLVED tier, or empty
#   allocation-ledger.sh derive <unit> <start-model> <start-effort>
#       Print `<model> <effort> <net> <stack-depth> <rows> <escalations>`, TAB
#       separated — the memoryless derivation.
#   allocation-ledger.sh stats [<unit>]           units/rows/bytes/derivation_ms
#
# Exit codes: 0 success; 2 usage error, hostile or out-of-grammar input,
#   unresolvable home, or a filesystem/lock error (fail closed); 3 an unhealthy
#   ledger (`health`); 5 broken install (a sibling helper missing).
#
# POSIX sh on the macOS + Linux support bar. All input is data (REQ-K1.5).
# Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

for dep in echo-safety.sh allocation-ladder.sh; do
  if [ ! -r "$script_dir/$dep" ]; then
    echo "allocation-ledger: sibling helper '$script_dir/$dep' is missing or not readable — broken install" >&2
    exit 5
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"
# shellcheck source=scripts/allocation-ladder.sh
. "$script_dir/allocation-ladder.sh"

FS="$script_dir/fleet-state.sh"

# The per-field grammars (REQ-K1.5, artifact data hygiene). Every one excludes
# TAB, newline, and every control byte, so a hostile field can neither tear a
# row nor drive a terminal at render time.

# valid_key: the identity charset for <unit> and <step>, byte-identical to
# fleet-audit.sh / fleet-attention.sh's field grammar. It excludes path
# separators, so a unit key can never form a traversal path when it becomes a
# filename, and excludes whitespace and shell metacharacters.
valid_key() {
  vk_v=$1
  case $vk_v in
    "" | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#vk_v}" -le 128 ]
}

# valid_step: valid_key widened by the single `-` sentinel for a launch with no
# step identity.
valid_step() {
  [ "$1" = - ] && return 0
  valid_key "$1"
}

valid_count() {
  case $1 in
    "" | *[!0-9]*) return 1 ;;
    0 | [1-9]*) return 0 ;;
  esac
  return 1
}

# valid_inputs: the bounded `key=value;...` list. Capped at 256 bytes so one row
# stays a single small append (the atomicity the lockless read path relies on),
# and restricted to a charset that carries no TAB, no control byte, and no shell
# metacharacter. The `;` is single-quoted INSIDE the bracket expression: an
# unquoted one would end the case item at the tokenizer, before the pattern is
# ever matched. Quoting one member of a bracket set keeps it a literal member.
valid_inputs() {
  vi_v=$1
  case $vi_v in
    "" | *[!A-Za-z0-9._=@:';',/+-]*) return 1 ;;
  esac
  [ "${#vi_v}" -le 256 ]
}

# A tier column: the model/effort enum, widened by `inherit` (the launch keeps
# its ambient value) and `-` (no tier at this position, e.g. a withheld unit).
valid_model_cell() {
  case $1 in
    inherit | -) return 0 ;;
  esac
  alloc_model_rank "$1" >/dev/null 2>&1
}

valid_effort_cell() {
  case $1 in
    inherit | -) return 0 ;;
  esac
  alloc_effort_rank "$1" >/dev/null 2>&1
}

ALLOC_SCOPES='unit step'
ALLOC_OUTCOMES='resolved applied withheld denied ignored no-op inherit degraded'

in_set() {
  for _is in $2; do
    [ "$1" = "$_is" ] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Store location
# ---------------------------------------------------------------------------

store_dir() {
  if [ ! -x "$FS" ]; then
    echo "allocation-ledger: fleet-state helper '$FS' is missing or not executable — broken install" >&2
    exit 5
  fi
  sd_root=$("$FS" root) || exit 2
  printf '%s/allocation' "${sd_root%/}"
}

ledger_path() {
  lp_dir=$(store_dir) || exit $?
  printf '%s/%s.tsv' "$lp_dir" "$1"
}

lock_path() {
  lk_dir=$(store_dir) || exit $?
  printf '%s/.lock.%s' "$lk_dir" "$1"
}

ensure_store() {
  es_dir=$(store_dir) || exit $?
  if ! mkdir -p "$es_dir" 2>/dev/null; then
    echo "allocation-ledger: cannot create the allocation store $es_dir" >&2
    exit 2
  fi
  printf '%s' "$es_dir"
}

# ---------------------------------------------------------------------------
# The per-unit advisory lock
# ---------------------------------------------------------------------------
#
# An ATOMIC SYMLINK CREATE carrying an OWNER TOKEN, rather than the `mkdir`
# lock the fleet's cross-spec lock uses. The difference is not stylistic: the
# mkdir shape was measured losing mutual exclusion on this support bar. Twelve
# same-unit writers doing acquire / read-modify-write / release produced 13
# interleaved critical sections over ten rounds under `mkdir` + `rmdir`, and 0
# over the same ten rounds under `ln -s` + `rm`; it reproduced from three
# concurrent writers upward, under both dash and bash. Losing exclusion here is
# not cosmetic — two launches would derive a tier from the same ledger state and
# both apply the same escalation — so this lock uses the primitive that held.
# (An observation records the measurement for the lock family's owner; this file
# does not change the sibling's lock, which is another spec's contract.)
#
# THE OWNER TOKEN is the symlink's TARGET, and it is what makes release safe.
# `lock_release` reads the token back and removes the link ONLY when it is still
# ours, so the classic advisory-lock clobber — a holder returning after its lock
# was broken and deleting the CURRENT holder's lock — cannot happen. The stale
# break claims the link by an atomic rename first, so two breakers cannot both
# win. Together these close the window the repo's mkdir lock family documents as
# a known limitation.
#
# The token is `<pid>-<epoch>`: two live processes cannot share a pid, so it is
# unique among concurrent holders, which is all it has to be.
#
# THE SPIN BUDGET MUST STAY WELL UNDER THE STALE THRESHOLD, and that ordering is
# the whole correctness argument for breaking at all. A short threshold looks
# appealing — a hold is one derive-and-append, milliseconds of WORK — but the
# wall clock a waiter burns is not the work: on a loaded machine, same-unit
# launches queue behind each other and the last waits tens of seconds. If the
# threshold sat below that wait, every waiter past it would declare a LIVE holder
# stale. So the threshold is the sibling's shared `stale_lock_threshold` knob
# (15 minutes by default) and the spin budget is ~100 seconds: a waiter exhausts
# its budget and fails closed long before it could break a merely-busy lock.

# alloc_stale_min: the stale threshold in minutes, read from the same
# `stale_lock_threshold` knob fleet-state.sh's lock uses, with PLANWRIGHT_REPO_ROOT
# pinned to the fleet home for the same reason the sibling pins it: this lock is
# reached from many repos, and resolving the cwd-derived layers would let two
# callers on the SAME lock disagree about staleness. An absent or unreadable
# value falls back to 15 minutes.
alloc_stale_min() {
  asm_v=15
  asm_root=$(store_dir) || asm_root=""
  if [ -n "$asm_root" ]; then
    asm_read=$(PLANWRIGHT_REPO_ROOT="$asm_root" "$script_dir/config-get.sh" stale_lock_threshold 2>/dev/null) || asm_read=""
    asm_read=${asm_read%m}
    case $asm_read in
      "" | *[!0-9]*) ;;
      *) asm_v=$asm_read ;;
    esac
  fi
  [ "$asm_v" -ge 1 ] || asm_v=15
  printf '%s' "$asm_v"
}

# How many spins between staleness probes. Probing every iteration would fork
# `find` fifty times a second per waiter for a condition that cannot become true
# for minutes.
ALLOC_LOCK_PROBE_EVERY=50
# ~100s of sleep plus syscalls: long enough for a deep same-unit queue on a
# loaded machine, and far short of the stale threshold, so an exhausted waiter
# fails CLOSED instead of breaking a lock that is merely busy.
ALLOC_LOCK_MAX_TRIES=5000

# lock_owner <lockpath>: print the owner token of a held lock, empty if absent.
lock_owner() {
  readlink "$1" 2>/dev/null || printf ''
}

# lock_acquire <lockpath>: acquire and set LOCK_TOKEN to the owner token the
# caller must present to release. Exit 0 held, 2 on a real error or an exhausted
# budget (fail closed).
LOCK_TOKEN=""
lock_acquire() {
  la_lock=$1
  la_ts=$(date +%s 2>/dev/null) || la_ts=0
  la_token="$$-$la_ts"
  la_tries=0
  la_stale_min=""
  while [ "$la_tries" -lt "$ALLOC_LOCK_MAX_TRIES" ]; do
    if ln -s "$la_token" "$la_lock" 2>/dev/null; then
      LOCK_TOKEN=$la_token
      return 0
    fi
    # `ln -s` failed. Only ONE of the reasons it can fail is contention, and the
    # spin budget is patience for that one alone; spent on any other it is a
    # stall that ends in a refusal naming contention that was never there. So
    # separate them here, by what is actually at the lock path.
    #
    # `-L` and not `-e` is what asks the question, because `-e` follows the link
    # and is false for a dangling one: the lock is the LINK, whatever it points
    # at. A link, live or dangling, is a holder, and waiting it out is exactly
    # what the budget is for.
    if [ ! -L "$la_lock" ]; then
      if [ -e "$la_lock" ]; then
        # Something that is not a lock squats the path. The stale break claims
        # a SYMLINK and nothing else, so no amount of waiting clears this.
        echo "allocation-ledger: $la_lock exists and is not a lock symlink — refusing to wait on it" >&2
        return 2
      fi
      # Nothing is there, so nothing was holding it: the create failed on the
      # STORE, not on a peer. One retry separates the two remaining cases — a
      # holder that released in the gap since the attempt (benign, and the
      # retry takes the lock), and a store that cannot be written at all.
      if ln -s "$la_token" "$la_lock" 2>/dev/null; then
        LOCK_TOKEN=$la_token
        return 0
      fi
      if [ ! -L "$la_lock" ]; then
        echo "allocation-ledger: cannot create $la_lock (store unwritable)" >&2
        return 2
      fi
    fi
    la_tries=$((la_tries + 1))
    if [ -L "$la_lock" ] && [ $((la_tries % ALLOC_LOCK_PROBE_EVERY)) -eq 0 ]; then
      [ -n "$la_stale_min" ] || la_stale_min=$(alloc_stale_min)
      if [ -n "$(find "$la_lock" -maxdepth 0 -mmin +"$la_stale_min" 2>/dev/null)" ]; then
        # Claim the stale lock by renaming it aside: two breakers cannot both
        # rename the same path, so only the winner re-creates it. The loser's
        # rename fails because the source is already gone.
        la_aside="$la_lock.stale.$la_token"
        if mv "$la_lock" "$la_aside" 2>/dev/null; then
          rm -f "$la_aside"
        fi
      fi
    fi
    # A fractional sleep: a BSD/GNU extension, deliberate and in scope on the
    # macOS + Linux support bar (the same call fleet-state.sh's spin makes).
    sleep 0.02
  done
  echo "allocation-ledger: gave up acquiring $la_lock after contention" >&2
  return 2
}

# lock_release <lockpath> [<token>]: release, but only if the lock is still
# OURS. With no token the release is unconditional, which is what the operator-
# facing `unlock` verb falls back to when it is handed no token to check.
lock_release() {
  if [ -n "${2:-}" ] && [ "$(lock_owner "$1")" != "$2" ]; then
    return 0
  fi
  rm -f "$1" 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------
#
# One awk pass over the unit's rows. Unhealthy means derivation cannot be
# trusted: a torn/short row, an out-of-enum field, or a sequence that does not
# strictly increase (which would make replay ORDER undefined, not merely a
# cosmetic defect). An absent file is a zero-history unit and is healthy.
check_health() {
  ch_file=$1
  [ -e "$ch_file" ] || return 0
  if [ ! -r "$ch_file" ]; then
    echo "allocation-ledger: ledger '$ch_file' is not readable" >&2
    return 3
  fi
  # The event and tier columns are checked here for the same reason the scope
  # and outcome columns are, and it is not symmetry: `alloc_replay` SKIPS a row
  # whose event falls outside the closed set, so one corrupted cell moves the
  # derived tier with nothing to show for it. Calling that file healthy is what
  # makes the change silent. The tier columns take the same two widenings the
  # append grammar takes — `inherit` (the launch keeps its ambient value) and
  # `-` (no tier at this position).
  ch_bad=$(awk -F '\t' -v scopes="$ALLOC_SCOPES" -v outcomes="$ALLOC_OUTCOMES" \
    -v events="$ALLOC_EVENTS_UP $ALLOC_EVENTS_DOWN $ALLOC_EVENTS_INERT" \
    -v models="$ALLOC_MODELS inherit -" -v efforts="$ALLOC_EFFORTS inherit -" '
    BEGIN {
      n = split(scopes, a, " "); for (i = 1; i <= n; i++) sc[a[i]] = 1
      n = split(outcomes, b, " "); for (i = 1; i <= n; i++) oc[b[i]] = 1
      n = split(events, c, " "); for (i = 1; i <= n; i++) ev[c[i]] = 1
      n = split(models, d, " "); for (i = 1; i <= n; i++) md[d[i]] = 1
      n = split(efforts, e, " "); for (i = 1; i <= n; i++) ef[e[i]] = 1
      prev = 0
    }
    {
      if (NF != 15) { print "row " NR ": " NF " fields, want 15"; exit }
      if ($1 !~ /^[1-9][0-9]*$/) { print "row " NR ": non-numeric sequence"; exit }
      if ($1 + 0 <= prev) { print "row " NR ": sequence is not strictly increasing"; exit }
      prev = $1 + 0
      if ($2 !~ /^[0-9]+$/) { print "row " NR ": non-numeric timestamp"; exit }
      if ($5 !~ /^[0-9]+$/) { print "row " NR ": non-numeric attempt"; exit }
      if (!($6 in ev)) { print "row " NR ": unknown event class"; exit }
      for (i = 7; i <= 11; i += 2)
        if (!($i in md)) { print "row " NR ": unknown model in field " i; exit }
      for (i = 8; i <= 12; i += 2)
        if (!($i in ef)) { print "row " NR ": unknown effort in field " i; exit }
      if (!($13 in sc)) { print "row " NR ": unknown scope"; exit }
      if (!($14 in oc)) { print "row " NR ": unknown outcome"; exit }
    }
  ' "$ch_file" 2>/dev/null)
  if [ -n "$ch_bad" ]; then
    echo "allocation-ledger: ledger '$ch_file' is unhealthy — $(sanitize_printable "$ch_bad" "(unprintable detail)")" >&2
    return 3
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Timing (REQ-F1.3)
# ---------------------------------------------------------------------------
#
# `date +%s%N` is GNU-only; BSD/macOS `date` renders a literal `N`, so the
# nanosecond arm is taken only when the output is all digits and long enough to
# be a real nanosecond stamp. Elsewhere the reading degrades to whole seconds
# scaled to milliseconds — coarser, never wrong, and never a hard dependency.
now_ms() {
  nm=$(date +%s%N 2>/dev/null) || nm=''
  case $nm in
    '' | *[!0-9]*) ;;
    *)
      if [ "${#nm}" -ge 16 ]; then
        printf '%s' $((nm / 1000000))
        return 0
      fi
      ;;
  esac
  nm=$(date +%s 2>/dev/null) || nm=0
  case $nm in
    '' | *[!0-9]*) nm=0 ;;
  esac
  printf '%s' $((nm * 1000))
}

# ---------------------------------------------------------------------------
# Command dispatch
# ---------------------------------------------------------------------------

usage() {
  echo "usage: allocation-ledger.sh home | path <unit> | lock <unit> | unlock <unit> | append <unit> <step> <attempt> <event> <pm> <pe> <cm> <ce> <rm> <re> <scope> <outcome> <inputs> | rows <unit> | health <unit> | last-tier <unit> | derive <unit> <start-model> <start-effort> | stats [<unit>]" >&2
}

require_unit() {
  if ! valid_key "$1"; then
    echo "allocation-ledger: refusing malformed unit key '$(sanitize_printable "$1" "(unprintable unit)")'" >&2
    exit 2
  fi
}

[ "$#" -ge 1 ] || {
  usage
  exit 2
}
cmd=$1
shift

case "$cmd" in
  home)
    [ "$#" -eq 0 ] || {
      usage
      exit 2
    }
    store_dir
    printf '\n'
    ;;

  path)
    [ "$#" -eq 1 ] || {
      usage
      exit 2
    }
    require_unit "$1"
    ledger_path "$1"
    printf '\n'
    ;;

  lock)
    [ "$#" -eq 1 ] || {
      usage
      exit 2
    }
    require_unit "$1"
    ensure_store >/dev/null
    lock_acquire "$(lock_path "$1")" || exit 2
    # The token goes back to the caller so its `unlock` can prove ownership.
    printf '%s\n' "$LOCK_TOKEN"
    ;;

  unlock)
    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
      usage
      exit 2
    fi
    require_unit "$1"
    lock_release "$(lock_path "$1")" "${2:-}"
    ;;

  append)
    if [ "$#" -ne 13 ]; then
      usage
      exit 2
    fi
    a_unit=$1
    a_step=$2
    a_attempt=$3
    a_event=$4
    a_pm=$5
    a_pe=$6
    a_cm=$7
    a_ce=$8
    a_rm=$9
    shift 9
    a_re=$1
    a_scope=$2
    a_outcome=$3
    a_inputs=$4

    require_unit "$a_unit"
    valid_step "$a_step" || {
      echo "allocation-ledger: refusing malformed step '$(sanitize_printable "$a_step" "(unprintable step)")'" >&2
      exit 2
    }
    valid_count "$a_attempt" || {
      echo "allocation-ledger: refusing non-numeric attempt '$(sanitize_printable "$a_attempt" "(unprintable attempt)")'" >&2
      exit 2
    }
    alloc_event_dir "$a_event" >/dev/null || {
      echo "allocation-ledger: refusing unknown event class '$(sanitize_printable "$a_event" "(unprintable event)")'" >&2
      exit 2
    }
    for a_cell in "$a_pm" "$a_cm" "$a_rm"; do
      valid_model_cell "$a_cell" || {
        echo "allocation-ledger: refusing unknown model '$(sanitize_printable "$a_cell" "(unprintable model)")'" >&2
        exit 2
      }
    done
    for a_cell in "$a_pe" "$a_ce" "$a_re"; do
      valid_effort_cell "$a_cell" || {
        echo "allocation-ledger: refusing unknown effort '$(sanitize_printable "$a_cell" "(unprintable effort)")'" >&2
        exit 2
      }
    done
    in_set "$a_scope" "$ALLOC_SCOPES" || {
      echo "allocation-ledger: refusing unknown scope '$(sanitize_printable "$a_scope" "(unprintable scope)")'" >&2
      exit 2
    }
    in_set "$a_outcome" "$ALLOC_OUTCOMES" || {
      echo "allocation-ledger: refusing unknown outcome '$(sanitize_printable "$a_outcome" "(unprintable outcome)")'" >&2
      exit 2
    }
    valid_inputs "$a_inputs" || {
      echo "allocation-ledger: refusing inputs field (non-empty, <=256 bytes, charset [A-Za-z0-9._=@:;,/+-])" >&2
      exit 2
    }

    ensure_store >/dev/null
    a_file=$(ledger_path "$a_unit")
    a_lock=$(lock_path "$a_unit")
    a_held=0
    if [ "${PLANWRIGHT_ALLOC_LOCK_HELD:-}" = "$a_unit" ]; then
      a_held=1
    fi
    a_token=""
    if [ "$a_held" -eq 0 ]; then
      lock_acquire "$a_lock" || exit 2
      a_token=$LOCK_TOKEN
    fi
    # The sequence is derived from the file under the lock, so two racing
    # appends can neither collide on a number nor lose a row.
    a_seq=1
    if [ -r "$a_file" ]; then
      a_last=$(awk -F '\t' 'NF == 15 && $1 ~ /^[1-9][0-9]*$/ { s = $1 + 0 } END { print s + 0 }' "$a_file")
      a_seq=$((a_last + 1))
    fi
    a_ts=$(date +%s 2>/dev/null) || a_ts=0
    case $a_ts in
      '' | *[!0-9]*) a_ts=0 ;;
    esac
    # Re-verify ownership between deriving the sequence number and writing it:
    # the only way to lose the lock mid-section is a stale break, which cannot
    # fire for minutes, so this is a cheap assertion rather than a retry loop —
    # but a lost lock means the sequence we derived is already stale, and
    # writing it anyway is the one outcome the ledger must not produce.
    if [ -n "$a_token" ] && [ "$(lock_owner "$a_lock")" != "$a_token" ]; then
      echo "allocation-ledger: lost the per-unit lock for '$(sanitize_printable "$a_unit" "(unprintable unit)")' mid-append — refusing to write a stale sequence number" >&2
      exit 2
    fi
    if ! printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$a_seq" "$a_ts" "$a_unit" "$a_step" "$a_attempt" "$a_event" \
      "$a_pm" "$a_pe" "$a_cm" "$a_ce" "$a_rm" "$a_re" \
      "$a_scope" "$a_outcome" "$a_inputs" >>"$a_file"; then
      [ "$a_held" -eq 0 ] && lock_release "$a_lock" "$a_token"
      echo "allocation-ledger: failed to append to $a_file" >&2
      exit 2
    fi
    [ "$a_held" -eq 0 ] && lock_release "$a_lock" "$a_token"
    printf '%s\n' "$a_seq"
    ;;

  rows)
    [ "$#" -eq 1 ] || {
      usage
      exit 2
    }
    require_unit "$1"
    r_file=$(ledger_path "$1")
    [ -r "$r_file" ] || exit 0
    cat "$r_file"
    ;;

  health)
    [ "$#" -eq 1 ] || {
      usage
      exit 2
    }
    require_unit "$1"
    check_health "$(ledger_path "$1")" || exit 3
    ;;

  last-tier)
    [ "$#" -eq 1 ] || {
      usage
      exit 2
    }
    require_unit "$1"
    lt_file=$(ledger_path "$1")
    [ -r "$lt_file" ] || exit 0
    # The last row carrying a REAL resolved tier — a withheld or inherit row
    # records no tier, and a torn row is skipped rather than trusted.
    awk -F '\t' '
      NF == 15 && $11 != "-" && $11 != "inherit" { m = $11; e = $12 }
      END { if (m != "") printf "%s\t%s\n", m, e }
    ' "$lt_file"
    ;;

  derive)
    [ "$#" -eq 3 ] || {
      usage
      exit 2
    }
    require_unit "$1"
    if ! alloc_valid_tier "$2" "$3"; then
      echo "allocation-ledger: refusing invalid starting tier '$(sanitize_printable "$2" "?")'/'$(sanitize_printable "$3" "?")'" >&2
      exit 2
    fi
    d_file=$(ledger_path "$1")
    alloc_replay "$d_file" "$2" "$3" || exit 2
    # The stack is a space-separated token list and `set -f` is on, so word
    # splitting counts it exactly, with no fork and no glob expansion.
    # shellcheck disable=SC2086 # deliberate word splitting: that is the count
    set -- $ALLOC_STACK
    d_depth=$#
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$ALLOC_MODEL" "$ALLOC_EFFORT" "$ALLOC_NET" "$d_depth" "$ALLOC_ROWS" "$ALLOC_ESCALATIONS"
    ;;

  stats)
    if [ "$#" -gt 1 ]; then
      usage
      exit 2
    fi
    st_dir=$(store_dir) || exit $?
    st_unit=${1:-}
    if [ -n "$st_unit" ]; then
      require_unit "$st_unit"
      st_files=$(ledger_path "$st_unit")
      [ -r "$st_files" ] || st_files=''
    else
      # `set -f` is on, so the glob does not expand here; `find` enumerates the
      # store instead, which also keeps an empty store from yielding a literal
      # pattern as a filename.
      st_files=$(find "$st_dir" -maxdepth 1 -type f -name '*.tsv' 2>/dev/null | sort)
    fi
    st_units=0
    st_rows=0
    st_bytes=0
    st_biggest=''
    st_biggest_rows=0
    # Field splitting on newlines only: a ledger filename can contain no
    # whitespace (the unit grammar forbids it), so this stays exact.
    st_oldifs=$IFS
    IFS='
'
    for st_f in $st_files; do
      IFS=$st_oldifs
      [ -r "$st_f" ] || {
        IFS='
'
        continue
      }
      st_units=$((st_units + 1))
      st_n=$(awk 'END { print NR + 0 }' "$st_f")
      st_rows=$((st_rows + st_n))
      st_b=$(awk 'BEGIN { t = 0 } { t += length($0) + 1 } END { print t + 0 }' "$st_f")
      st_bytes=$((st_bytes + st_b))
      if [ "$st_n" -ge "$st_biggest_rows" ]; then
        st_biggest_rows=$st_n
        st_biggest=$st_f
      fi
      IFS='
'
    done
    IFS=$st_oldifs
    # Derivation latency, measured over the LARGEST ledger — the growth signal
    # the risk register asks for is about the worst unit, not the average one.
    st_ms=0
    if [ -n "$st_biggest" ]; then
      st_t0=$(now_ms)
      alloc_replay "$st_biggest" haiku low >/dev/null 2>&1 || true
      st_t1=$(now_ms)
      st_ms=$((st_t1 - st_t0))
      [ "$st_ms" -ge 0 ] || st_ms=0
    fi
    printf 'units\t%s\n' "$st_units"
    printf 'rows\t%s\n' "$st_rows"
    printf 'bytes\t%s\n' "$st_bytes"
    printf 'derivation_ms\t%s\n' "$st_ms"
    ;;

  *)
    usage
    exit 2
    ;;
esac
