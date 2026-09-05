#!/bin/sh
# allocation-petition.sh — the WORKER PETITION channel: the one signal in the
# allocation path a worker authors, and therefore the one untrusted-input
# surface in it (model-allocation Task 3; D-7, D-8; REQ-C1.3, REQ-C1.6,
# REQ-C1.7).
#
# WHAT IT IS FOR. Events tell the policy that a unit is going badly. Nothing
# tells it the opposite — that the remaining steps are mechanical and the tier
# it was given is more than the work needs. A worker that knows either way
# writes a petition at a pinned path in its OWN worktree; the policy reads it at
# the next launch boundary and weighs it as ONE trigger input among the others.
# It is a HINT, never an authority: allocation-adapt.sh applies it through the
# same ladder step, the same adjustment cap, and the same clamps as any other
# event, so a petition can never buy a tier the budget contracts would refuse.
#
# THE GRAMMAR IS PINNED AND CLOSED (D-7). Exactly five newline-terminated lines,
# in this order, no others:
#
#   direction=escalate | de-escalate
#   unit=<unit identity>
#   step=<step identity, or `-`>
#   attempt=<count>
#   reason=<one line of printable ASCII>
#
# The whole file is capped at 1 KiB and parsed under `LC_ALL=C`, so "printable"
# is a byte range rather than a locale question. Anything else — an unknown key,
# a sixth line, a control byte, an oversize file, a torn write — is out of
# grammar, and out of grammar means CONSUMED AND IGNORED, never acted on.
#
# THE PATH POSTURE (D-7, doctrine/security-posture.md). The pinned path is taken
# only as a CONTAINED REGULAR FILE: the container directory is rejected if it is
# a symlink, the artifact is rejected if it is a symlink or any non-regular file
# (a FIFO is never opened — opening one is how a hostile worker would hang the
# tower), and the read is bounded by the size cap checked first. The reason is
# carried as DATA at every step: it is never interpolated into a command, never
# eval'd, and never echoed without the sanitizer.
#
# THE CLAIM IS THE CONCURRENCY CONTROL (D-7). Consumption starts by atomically
# renaming the artifact OUT of the pinned path — the claim — and only then
# validates it. `rename(2)` gives exactly one of two racing consumers the file
# and fails the other with ENOENT, so two boundaries resolving the same unit
# cannot both weigh one petition. Renaming a symlink moves the LINK, never its
# target, which is why claiming before validating is safe even for a hostile
# artifact.
#
# SINGLE CONSUMPTION (REQ-C1.7). Weighing consumes: the artifact is gone
# afterwards, so one petition moves the tier at most one step, ever, and
# signaling again costs the worker a fresh write. Invalid petitions are consumed
# too — leaving one in place would have it re-parsed and re-audited at every
# later boundary, unbounded ledger spam from a single hostile write.
#
# TWO-PHASE FOR THE ENGINE (`--hold`). A caller that must record a ledger row
# for what it took cannot let the claimed file vanish before the row lands, or a
# crash in between loses the audit. `--hold` leaves the claimed file behind and
# prints its path; the caller discards it once the row is committed, and the
# `reconciled` count on the NEXT boundary is what turns a crash in that window
# into ignored-with-audit rather than silence. Without `--hold` the claim is
# one-shot and cleans up after itself.
#
# THE RESIDUAL RACE, STATED. The container check and the rename it protects are
# two syscalls, and POSIX sh has no `openat`/`O_NOFOLLOW` to fuse them, so a
# writer that swaps `.claude` for a symlink between them redirects this script's
# rename and its claim sweep. That window is accepted rather than closed,
# because the only principal who can take it is the worktree's own owner — the
# worker, which can already write anything it likes there directly, and gains
# nothing by the detour. What the window cannot do is what the checks are
# actually for: nothing is ever read THROUGH a link, no non-regular file is ever
# opened, and the only names touched are the two fixed ones below.
#
# NO WORKTREE, NO CHANNEL. Rungs that run in-session have no worktree to write
# into, so they have no petition channel. That is a documented degradation
# (REQ-C1.7), not an error: `claim` without a worktree is simply never called,
# and the tier moves on events alone.
#
# Usage:
#   allocation-petition.sh path <worktree>
#       Print the pinned artifact path for a worktree.
#   allocation-petition.sh write --worktree <dir> --direction <dir> \
#       --unit <unit> [--step <step>] [--attempt <n>] --reason <text>
#       Write a petition temp-then-rename, so a reader never sees a partial
#       file. Out-of-grammar input is REFUSED here rather than written: a
#       petition the reader will only throw away is worse than none.
#   allocation-petition.sh claim --worktree <dir> --unit <unit> \
#       [--step <step>] [--attempt <n>] [--hold]
#       Reconcile orphaned claims, then claim and screen the artifact. Prints
#       TAB-separated `key<TAB>value` lines:
#         reconciled   orphaned claimed files swept this call (each one owes the
#                      caller an ignored-with-audit ledger row)
#         verdict      valid | invalid | none
#         direction    escalate | de-escalate | -
#         reason       the sanitized single-line reason (valid only)
#         detail       why it was refused (invalid only): symlink, not-regular,
#                      empty, oversize, control-bytes, torn, grammar,
#                      stale-unit, stale-step
#         claimed      the held claimed file's path (`--hold` only)
#
# Exit codes: 0 a petition was claimed (`verdict` says whether it was weighable);
#   1 nothing to claim, including a worktree with no usable channel; 2 usage
#   error or out-of-grammar input to `write`; 5 broken install.
#
# POSIX sh on the macOS + Linux support bar. All input is data (REQ-K1.5).
# Pathname expansion is disabled (set -f) except around the one claim sweep,
# which re-enables it for a single bounded glob.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

if [ ! -r "$script_dir/echo-safety.sh" ]; then
  echo "allocation-petition: sibling helper '$script_dir/echo-safety.sh' is missing or not readable — broken install" >&2
  exit 5
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

# The artifact's pinned location inside a worktree. `.claude/` is the directory
# a worker's checkout already carries, and the file sits beside the equally
# transient handover brief; both are gitignored, so a petition never dirties the
# tree the worker is about to commit from.
PET_SUBDIR=.claude
PET_NAME=allocation-petition
# The whole-file byte cap (D-7). The reason cap below keeps a well-formed
# petition an order of magnitude under it; this bound is what stops an
# ill-formed one from ever being read.
# The pid-reuse guard for the claim sweep below, in seconds. A live owner pid
# marks a claim as still in flight; pid numbers are reused, so a live pid on a
# claim older than this is reuse rather than an owner.
#
# The age is read from the CLAIM FILENAME, never from the file's mtime. `mv` is
# rename(2) and preserves mtime, so a claimed file carries the time the WORKER
# WROTE the petition — normally one boundary earlier — not the time it was
# claimed. An mtime-based guard therefore treats every ordinary petition as
# pre-expired and sweeps live consumers, which is the whole defect this guard
# exists to prevent. The sibling locks age a mkdir-created directory, where
# mtime does mean "held since"; that invariant does not survive the copy.
PET_CLAIM_ORPHAN_SEC=900
# One claim namespace is 16 slots (see take_claim), so a legitimate sweep never
# exceeds that. Each reconciled claim costs the caller a ledger row, so the
# count is capped: a hostile worker planting claim files must not be able to
# spend an unbounded number of audit writes under the unit lock (D-7's
# anti-spam reasoning, applied to the claim namespace and not only the artifact).
# Anything above the cap is swept by later calls.
PET_CLAIM_MAX_RECONCILE=16
PET_MAX_BYTES=1024
PET_MAX_REASON=200
PET_LINES=5
TAB=$(printf '\t')

usage() {
  echo "usage: allocation-petition.sh path <worktree> | write --worktree <dir> --direction <escalate|de-escalate> --unit <unit> [--step <step>] [--attempt <n>] --reason <text> | claim --worktree <dir> --unit <unit> [--step <step>] [--attempt <n>] [--hold]" >&2
}

# valid_identity <value>: the unit/step charset, byte-identical to the ledger's
# `valid_key` (and to allocation-adapt.sh's boundary check). Mirroring it exactly
# is the point — a looser check writes a petition the engine's own argument
# validation would refuse, a tighter one refuses an identity the ledger records.
valid_identity() {
  case $1 in
    "" | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

# valid_count <value>: a bare count. A leading zero is refused because the
# engine keys incidents on the attempt verbatim, and `01` and `1` must not spell
# the same attempt two ways.
valid_count() {
  case $1 in
    "" | *[!0-9]*) return 1 ;;
    0 | [1-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

# printable_line <value>: one line of printable ASCII. `tr -d ' -~'` deletes the
# printable range under the pinned C locale, so anything surviving is a control
# byte, a NUL, an embedded newline, or a high byte — each of which is exactly
# what must not reach a ledger row or a terminal.
printable_line() {
  [ -n "$1" ] || return 1
  pl_left=$(printf '%s' "$1" | tr -d ' -~' | wc -c | tr -d ' ')
  [ "$pl_left" = 0 ]
}

# resolve_container <worktree>: print the artifact's directory, canonicalized.
# Returns 1 when the worktree is not a real directory and 3 when the container
# is a symlink — a path trick, and the one case where there is nothing safe to
# consume, so it degrades to "no channel" rather than to an audited ignore that
# would repeat at every boundary.
resolve_container() {
  rc_wt=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  if [ -L "$rc_wt/$PET_SUBDIR" ]; then
    return 3
  fi
  [ -d "$rc_wt/$PET_SUBDIR" ] || return 1
  printf '%s' "$rc_wt/$PET_SUBDIR"
}

# ---------------------------------------------------------------------------
# path
# ---------------------------------------------------------------------------

cmd_path() {
  [ "$#" -eq 1 ] || {
    usage
    exit 2
  }
  cp_wt=$(cd "$1" 2>/dev/null && pwd -P) || {
    printf '%s\n' "allocation-petition: worktree '$(sanitize_printable "$1" "(unprintable path)")' is not a directory" >&2
    exit 2
  }
  printf '%s/%s/%s\n' "$cp_wt" "$PET_SUBDIR" "$PET_NAME"
}

# ---------------------------------------------------------------------------
# write
# ---------------------------------------------------------------------------

cmd_write() {
  w_wt=""
  w_dir=""
  w_unit=""
  w_step=-
  w_attempt=1
  w_reason=""
  while [ "$#" -gt 0 ]; do
    [ "$#" -ge 2 ] || {
      usage
      exit 2
    }
    case $1 in
      --worktree) w_wt=$2 ;;
      --direction) w_dir=$2 ;;
      --unit) w_unit=$2 ;;
      --step) w_step=$2 ;;
      --attempt) w_attempt=$2 ;;
      --reason) w_reason=$2 ;;
      *)
        printf '%s\n' "allocation-petition: unknown argument '$(sanitize_printable "$1" "(unprintable argument)")'" >&2
        exit 2
        ;;
    esac
    shift 2
  done

  case $w_dir in
    escalate | de-escalate) ;;
    *)
      printf '%s\n' "allocation-petition: direction '$(sanitize_printable "$w_dir" "(unprintable direction)")' is not escalate or de-escalate" >&2
      exit 2
      ;;
  esac
  valid_identity "$w_unit" || {
    printf '%s\n' "allocation-petition: refusing malformed unit '$(sanitize_printable "$w_unit" "(unprintable unit)")'" >&2
    exit 2
  }
  if [ "$w_step" != - ]; then
    valid_identity "$w_step" || {
      printf '%s\n' "allocation-petition: refusing malformed step '$(sanitize_printable "$w_step" "(unprintable step)")'" >&2
      exit 2
    }
  fi
  valid_count "$w_attempt" || {
    printf '%s\n' "allocation-petition: refusing malformed attempt '$(sanitize_printable "$w_attempt" "(unprintable attempt)")'" >&2
    exit 2
  }
  printable_line "$w_reason" || {
    echo "allocation-petition: the reason must be one line of printable text" >&2
    exit 2
  }
  [ "${#w_reason}" -le "$PET_MAX_REASON" ] || {
    echo "allocation-petition: the reason is longer than $PET_MAX_REASON characters" >&2
    exit 2
  }

  w_wtp=$(cd "${w_wt:-.}" 2>/dev/null && pwd -P) || {
    printf '%s\n' "allocation-petition: worktree '$(sanitize_printable "$w_wt" "(unprintable path)")' is not a directory" >&2
    exit 2
  }
  if [ -L "$w_wtp/$PET_SUBDIR" ]; then
    echo "allocation-petition: '$PET_SUBDIR' in the worktree is a symlink — refusing to write through it" >&2
    exit 2
  fi
  mkdir -p "$w_wtp/$PET_SUBDIR" 2>/dev/null || {
    echo "allocation-petition: could not create the petition directory in the worktree" >&2
    exit 2
  }

  # Temp-then-rename, so a boundary that reads mid-write sees either the old
  # artifact or the new one, never a torn one. The temp name is outside the
  # `.claim.` namespace the reconcile sweeps, so an in-flight write is never
  # mistaken for an orphaned claim.
  w_tmp="$w_wtp/$PET_SUBDIR/$PET_NAME.tmp.$$"
  : >"$w_tmp" 2>/dev/null || {
    echo "allocation-petition: could not write into the petition directory" >&2
    exit 2
  }
  printf 'direction=%s\nunit=%s\nstep=%s\nattempt=%s\nreason=%s\n' \
    "$w_dir" "$w_unit" "$w_step" "$w_attempt" "$w_reason" >"$w_tmp" || {
    rm -f "$w_tmp"
    echo "allocation-petition: could not write the petition" >&2
    exit 2
  }
  mv "$w_tmp" "$w_wtp/$PET_SUBDIR/$PET_NAME" || {
    rm -f "$w_tmp"
    echo "allocation-petition: could not publish the petition" >&2
    exit 2
  }
}

# ---------------------------------------------------------------------------
# claim
# ---------------------------------------------------------------------------

# sweep_claims <dir>: remove every orphaned claimed file and print how many.
# Each one is a consumer that died between taking a petition and recording it,
# so the caller owes each an ignored-with-audit ledger row — which is what makes
# that crash window visible instead of silent. Clearing them here is what keeps
# one crash from being re-audited at every later boundary.
sweep_claims() {
  sc_n=0
  # A clock we cannot read yields 0, which makes every claim read as ancient and
  # sweepable: the sweep degrades toward reaping, never toward shielding.
  sc_now=$(date +%s 2>/dev/null) || sc_now=0
  case $sc_now in
    "" | *[!0-9]*) sc_now=0 ;;
  esac
  # Globbing is off script-wide (set -f). Enable it for exactly one expansion
  # and turn it straight back off, so no later word in this function can pick up
  # pathname expansion it did not ask for.
  sc_dir=$1
  set +f
  set -- "$sc_dir/$PET_NAME.claim."*
  set -f
  for sc_f in "$@"; do
    # An unmatched glob expands to itself; that literal names no file.
    [ -e "$sc_f" ] || [ -L "$sc_f" ] || continue
    # A claim file names the pid that took it, and a LIVE owner is a sibling
    # consumer mid-flight rather than a crash. Sweeping one destroys the
    # petition that consumer is about to weigh and leaves it screening a file
    # that no longer exists, which it reports as a malformed artifact: the
    # petition is lost and the worker is blamed for it. Only an owner that is
    # gone leaves an orphan, which is the case this sweep exists for.
    sc_rest=${sc_f##*"$PET_NAME.claim."}
    sc_pid=${sc_rest%%.*}
    sc_after=${sc_rest#*.}
    sc_epoch=${sc_after%%.*}
    sc_live=0
    case $sc_pid in
      # `kill -0 0` signals the caller's whole process GROUP and always
      # succeeds, so a claim named `.claim.0.` would shield itself from the
      # sweep forever. Zero is not a pid a claim can legitimately carry.
      "" | 0 | *[!0-9]*) ;;
      *)
        case $sc_epoch in
          "" | *[!0-9]*) ;;
          *)
            if kill -0 "$sc_pid" 2>/dev/null \
              && [ "$((sc_now - sc_epoch))" -le "$PET_CLAIM_ORPHAN_SEC" ]; then
              sc_live=1
            fi
            ;;
        esac
        ;;
    esac
    [ "$sc_live" = 0 ] || continue
    rm -f "$sc_f" 2>/dev/null || continue
    sc_n=$((sc_n + 1))
    # Stop COUNTING past the cap, not sweeping: cleanup stays cheap, while the
    # caller's ledger rows — one per reconciled claim — stay bounded.
    [ "$sc_n" -lt "$PET_CLAIM_MAX_RECONCILE" ] || break
  done
  printf '%s' "$sc_n"
}

# take_claim <dir>: atomically rename the artifact out of the pinned path and
# print where it landed. Returns 1 when there is nothing to take — including
# losing the race to another consumer, which is the same outcome from here.
take_claim() {
  tc_src="$1/$PET_NAME"
  [ -e "$tc_src" ] || [ -L "$tc_src" ] || return 1
  # The claim time is carried in the NAME because rename preserves mtime; see
  # PET_CLAIM_ORPHAN_SEC. A clock we cannot read yields 0, which ages the claim
  # out immediately rather than shielding it forever.
  tc_now=$(date +%s 2>/dev/null) || tc_now=0
  case $tc_now in
    "" | *[!0-9]*) tc_now=0 ;;
  esac
  tc_i=0
  while [ "$tc_i" -lt 16 ]; do
    tc_dst="$1/$PET_NAME.claim.$$.$tc_now.$tc_i"
    tc_i=$((tc_i + 1))
    # Never rename over an existing claim: that would destroy a record the
    # reconcile owes an audit row. The sweep above normally leaves none, so this
    # only bites when a live sibling consumer holds one.
    if [ -e "$tc_dst" ] || [ -L "$tc_dst" ]; then
      continue
    fi
    # `mv` here is rename(2) within one directory: atomic, and on a symlink
    # source it moves the LINK rather than following it. The loser of a race
    # gets ENOENT, which is the same "nothing to claim" as an empty path.
    mv "$tc_src" "$tc_dst" 2>/dev/null || return 1
    printf '%s' "$tc_dst"
    return 0
  done
  return 1
}

# screen <file>: judge a claimed artifact. Prints either `!<detail>` or
# `ok<TAB>direction<TAB>unit<TAB>step<TAB>attempt<TAB>reason`. Every check runs
# before the one that would be unsafe without it: link before regular-file,
# regular-file before any open, size before any read, byte range before any
# structural parse.
screen() {
  s_f=$1
  if [ -L "$s_f" ]; then
    printf '!symlink'
    return 0
  fi
  if [ ! -f "$s_f" ]; then
    printf '!not-regular'
    return 0
  fi
  s_bytes=$(wc -c <"$s_f" 2>/dev/null | tr -d ' ') || s_bytes=""
  case $s_bytes in
    "" | *[!0-9]*)
      printf '!not-regular'
      return 0
      ;;
  esac
  if [ "$s_bytes" -eq 0 ]; then
    printf '!empty'
    return 0
  fi
  if [ "$s_bytes" -gt "$PET_MAX_BYTES" ]; then
    printf '!oversize'
    return 0
  fi
  # Everything past here reads the file, and the size cap above is what bounds
  # that read. Byte range first: a control byte, a NUL, or a high byte is a
  # refusal in its own right, and screening it out here is what lets the
  # structural parse below assume plain text.
  s_bad=$(tr -d '\012\040-\176' <"$s_f" | wc -c | tr -d ' ')
  if [ "$s_bad" != 0 ]; then
    printf '!control-bytes'
    return 0
  fi
  # A torn write is a record the writer never terminated. `wc -l` counts
  # NEWLINES and awk counts RECORDS, so they disagree exactly when the last line
  # has no newline — which is what a reader racing a non-atomic write would see.
  s_nl=$(wc -l <"$s_f" | tr -d ' ')
  s_nr=$(awk 'END { print NR }' <"$s_f")
  if [ "$s_nl" != "$s_nr" ]; then
    printf '!torn'
    return 0
  fi
  if [ "$s_nr" != "$PET_LINES" ]; then
    printf '!grammar'
    return 0
  fi
  awk -v maxreason="$PET_MAX_REASON" '
    { line[NR] = $0 }
    function val(i, key,   p) {
      p = key "="
      if (index(line[i], p) != 1) return "\001"
      return substr(line[i], length(p) + 1)
    }
    function ident(v) {
      return (v != "" && length(v) <= 128 && v ~ /^[A-Za-z0-9._=@:-]+$/)
    }
    END {
      d = val(1, "direction"); u = val(2, "unit")
      s = val(3, "step"); a = val(4, "attempt"); r = val(5, "reason")
      if (d == "\001" || u == "\001" || s == "\001" || a == "\001" || r == "\001") {
        print "!grammar"; exit
      }
      if (d != "escalate" && d != "de-escalate") { print "!grammar"; exit }
      if (!ident(u)) { print "!grammar"; exit }
      if (s != "-" && !ident(s)) { print "!grammar"; exit }
      if (a !~ /^(0|[1-9][0-9]*)$/) { print "!grammar"; exit }
      if (r == "" || length(r) > maxreason) { print "!grammar"; exit }
      printf "ok\t%s\t%s\t%s\t%s\t%s", d, u, s, a, r
    }
  ' <"$s_f"
}

cmd_claim() {
  c_wt=""
  c_unit=""
  c_step=-
  c_hold=no
  while [ "$#" -gt 0 ]; do
    case $1 in
      --hold)
        c_hold=yes
        shift
        continue
        ;;
    esac
    [ "$#" -ge 2 ] || {
      usage
      exit 2
    }
    case $1 in
      --worktree) c_wt=$2 ;;
      --unit) c_unit=$2 ;;
      --step) c_step=$2 ;;
      # Accepted so the launch boundary can pass one identity to every
      # allocation helper, and deliberately not stored: the attempt does not
      # bind the petition (see the staleness check). Discarding it here rather
      # than keeping an unread variable keeps that fact visible.
      --attempt) : ;;
      *)
        printf '%s\n' "allocation-petition: unknown argument '$(sanitize_printable "$1" "(unprintable argument)")'" >&2
        exit 2
        ;;
    esac
    shift 2
  done
  valid_identity "$c_unit" || {
    printf '%s\n' "allocation-petition: refusing malformed unit '$(sanitize_printable "$c_unit" "(unprintable unit)")'" >&2
    exit 2
  }
  [ -n "$c_wt" ] || {
    usage
    exit 2
  }

  c_rc=0
  c_dir=$(resolve_container "$c_wt") || c_rc=$?
  if [ "$c_rc" != 0 ]; then
    if [ "$c_rc" = 3 ]; then
      printf '%s\n' "allocation-petition: '$PET_SUBDIR' in worktree '$(sanitize_printable "$c_wt" "(unprintable path)")' is a symlink — no petition channel" >&2
    fi
    printf 'reconciled\t0\nverdict\tnone\ndirection\t-\n'
    return 1
  fi

  c_reconciled=$(sweep_claims "$c_dir")
  printf 'reconciled\t%s\n' "$c_reconciled"

  c_file=$(take_claim "$c_dir") || {
    printf 'verdict\tnone\ndirection\t-\n'
    return 1
  }

  c_verdict=$(screen "$c_file")
  case $c_verdict in
    "ok$TAB"*)
      # Field order matches screen()'s printf. The reason is last, so a value
      # carrying its own separators could not shift the fields even if the byte
      # screen above had let a TAB through.
      c_rest=${c_verdict#ok"$TAB"}
      c_pdir=${c_rest%%"$TAB"*}
      c_rest=${c_rest#*"$TAB"}
      c_punit=${c_rest%%"$TAB"*}
      c_rest=${c_rest#*"$TAB"}
      c_pstep=${c_rest%%"$TAB"*}
      c_rest=${c_rest#*"$TAB"}
      # Field 4 is the attempt. The grammar still carries it — it is part of
      # what the worker recorded, and the screen validates its shape — but it
      # does not bind the petition, so it is stepped over rather than read.
      c_preason=${c_rest#*"$TAB"}
      # The binding: a petition speaks for ONE unit at ONE step. Anything else
      # is stale — a leftover from a previous step, or a file planted for a unit
      # that never wrote it — and is ignored with a row rather than weighed for
      # whoever happens to read it next.
      #
      # ATTEMPT IS DELIBERATELY NOT PART OF THIS. D-7 defines staleness as
      # "wrong unit or step" and REQ-C1.6 pins the binding as "unit and step
      # identity"; neither makes the attempt count part of it. Requiring it to
      # match would also break the channel in the flow it exists for: a worker
      # petitions at the end of attempt N, and the boundary that reads it is the
      # relaunch at attempt N+1, so an attempt-strict check goes stale on every
      # retry — the main escalate path. The attempt still binds ELSEWHERE, as
      # part of the event idempotency key in allocation-adapt.sh, which is a
      # different mechanism with a different job.
      if [ "$c_punit" != "$c_unit" ]; then
        c_detail=stale-unit
      elif [ "$c_pstep" != "$c_step" ]; then
        c_detail=stale-step
      else
        c_detail=""
      fi
      if [ -n "$c_detail" ]; then
        printf 'verdict\tinvalid\ndirection\t-\ndetail\t%s\n' "$c_detail"
      else
        # The reason is worker-authored text on its way to a terminal and a
        # ledger row: it passes the sanitizer even though the byte screen
        # already bounded it, because defense here costs nothing and the screen
        # is the only thing standing between the two.
        printf 'verdict\tvalid\ndirection\t%s\nreason\t%s\n' \
          "$c_pdir" "$(sanitize_printable "$c_preason" "(unprintable reason)")"
      fi
      ;;
    "!"*)
      printf 'verdict\tinvalid\ndirection\t-\ndetail\t%s\n' "${c_verdict#!}"
      ;;
    *)
      # An awk that produced neither shape is itself the anomaly; fail closed.
      printf 'verdict\tinvalid\ndirection\t-\ndetail\tgrammar\n'
      ;;
  esac

  if [ "$c_hold" = yes ]; then
    printf 'claimed\t%s\n' "$c_file"
  else
    rm -f "$c_file" 2>/dev/null || true
  fi
  return 0
}

[ "$#" -ge 1 ] || {
  usage
  exit 2
}
cmd=$1
shift
case "$cmd" in
  path) cmd_path "$@" ;;
  write) cmd_write "$@" ;;
  claim) cmd_claim "$@" ;;
  *)
    usage
    exit 2
    ;;
esac
