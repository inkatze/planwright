#!/bin/sh
# fleet-fence.sh — the per-unit `origin` fence: the authoritative
# no-duplicate-dispatch object
# (concurrent-orchestrator-coordination Task 4: D-5, D-7, D-8, D-10, D-11,
# D-12, D-13 · REQ-C1.1–REQ-C1.7, REQ-D1.5).
#
# WHAT THIS IS (D-5, D-8, D-11). At dispatch, BEFORE any worker forks, the
# tower fences the unit by creating `refs/planwright-fence/<spec>/<unit-id>`
# on `origin` through an atomic expect-absent compare-and-swap. `origin` is
# the one substrate every co-located clone already shares, and git serializes
# ref updates on it, so exactly one tower wins a unit and a loser backs off.
# The ref is authoritative because `origin` is natively BOTH cross-clone (every
# clone reads the same ref set) AND death-surviving (the ref outlives the
# tower that pushed it) — the two properties no machine-local surface has
# without faking one. The fence carries NO worker identity and NO death
# handle: it is keyed by unit id and created before the worker exists.
#
# ARCHITECTURE A IS ABSENT BY CONSTRUCTION (D-11). There is no machine-local
# claim object, no per-unit reclaim lock, no under-lock re-read, no
# four-residue GC, and no record quarantine: the correctness object is a git
# ref, which either exists or does not, so the schema-skew, worker-lifecycle,
# and cohesion-keying failure axes dissolve rather than being defended. The
# machine-local presence surface is never on the correctness path — it is read
# only to ATTRIBUTE an orphan fence to its owner (`sweep`), and a missing or
# unreadable surface degrades attribution to `unknown-owner`, never exclusion.
#
# THE CAS, AND WHY THE EXIT CODE IS NOT THE ANSWER (REQ-C1.6). The push is
#   git push --atomic --porcelain \
#       --force-with-lease=<ref>:<all-zeros-oid> origin <origin/main-tip>:<ref>
# where the lease names the fence ref and its must-be-absent expectation as the
# object format's ALL-ZEROS object id (40 hex zeros under SHA-1, 64 under
# SHA-256) — never the bare-empty nothing-after-the-colon form. The pushed
# refspec targets the current `origin/main` tip, an EXISTING commit, so the
# fence adds no commit and no history to `main` (REQ-C1.2, honoring
# `orchestration-concurrency`'s no-dispatch-commit-on-`main` floor).
#
# The win/lose verdict is read from the PER-REF PORCELAIN STATUS, not from the
# exit code. git decides a same-value ref update is `[up to date]` BEFORE it
# evaluates the lease (remote.c sets REF_STATUS_UPTODATE and skips the ref), so
# a second tower pushing the SAME `origin/main` tip at an already-fenced unit
# gets `=` and exit 0 — the case that matters most, since every racing tower
# targets the same tip. The statuses this script acts on:
#   `*`  [new reference]  — THIS push created the fence: the unit is ours.
#   `=`  [up to date]     — the fence already existed at the tip: a peer holds
#                           the unit. Back off (exit 3).
#   `!`  [rejected]       — the server's ref transaction refused the update:
#                           stale info / fetch first / non-fast-forward / the
#                           ref already exists all mean taken (exit 3); any
#                           other rejection is transient (exit 4).
#   no per-ref line       — the push never reached ref negotiation: transient.
# Misclassifying costs at most one wasted pass — the authoritative CAS
# re-adjudicates next pass — but never a double dispatch.
#
# COHESION BUNDLES ARE ALL-OR-NONE (REQ-C1.2). Several unit ids are fenced in
# one `git push --atomic`, so a member the server rejects rolls the whole push
# back. The `[up to date]` status above is NOT a rejection, so `--atomic` does
# not roll it back: a bundle whose member collided that way can leave this
# tower's OWN just-created members behind. The tower therefore verifies every
# member reported `*` and, when the bundle did not fully win, deletes exactly
# the members its own push created (lease-guarded on the value it pushed, so
# it can never delete a peer's fence) before backing off the entire bundle. A
# peer selecting ANY member — lead or non-lead — collides, and no member is
# left fenced by a bundle that backed off.
#
# ORIGIN-REACHABILITY IS CLASSIFIED, NEVER FAILED OPEN (REQ-C1.6, D-10).
# No `origin` configured is the genuine no-remote single-host solo posture:
# there is no peer to collide with, so the tower dispatches WITHOUT a fence
# (exit 5) rather than refusing to work. A transient failure against a
# CONFIGURED `origin` fails closed (exit 4): do not dispatch this unit this
# pass, surface, retry. A rejected CAS backs off the unit (exit 3). A fence
# ref this tower did not create is never `--force`d or overwritten — only the
# expect-absent lease is ever used.
#
# LIFECYCLE (REQ-C1.5, D-7). A fence persists from dispatch until its unit is
# TERMINAL — its PR merged, or the ledger marks it done. An open, unmerged PR
# is NOT terminal, so the fence persists across the whole open-PR window.
# `gc` deletes a terminal unit's fence and is idempotent: an already-absent ref
# is success, so two towers GC'ing the same fence never error. The namespace is
# bounded because every fence is deleted at its unit's terminal transition.
#
# SECURITY (REQ-D1.5). The spec id and every unit id are validated against
# their declared grammar, and the assembled ref name is checked with
# `git check-ref-format` AND a literal `refs/planwright-fence/<spec>/` prefix
# test, BEFORE any push or delete — so a crafted id can never drive a ref
# operation outside the namespace. Untrusted text reaching a terminal passes
# the echo-discipline sanitizer. All input is data; no eval.
#
# Usage:
#   fleet-fence.sh refname --spec <spec> <unit-id>
#   fleet-fence.sh check   --checkout <dir> --spec <spec> <unit-id>
#   fleet-fence.sh fence   --checkout <dir> --spec <spec> <unit-id>...
#   fleet-fence.sh gc      --checkout <dir> --spec <spec> <unit-id>...
#   fleet-fence.sh list    --checkout <dir> [--spec <spec>]
#   fleet-fence.sh sweep   --checkout <dir> --spec <spec>
#       (--session-id <uuid> | --pid <pid>) [--grace <sec>] [--min-interval <sec>]
#
# Output (tab-separated where machine-read):
#   fence:  `fenced <ref>` per won member, or `taken <ref>` / `solo no-origin`
#   check:  `fenced <ref>` | `unfenced <ref>` | `solo no-origin`
#   gc:     `gc <ref>` | `gc-absent <ref>`
#   list:   one ref name per line
#   sweep:  `gc <ref>` / `gc-absent <ref>`      the unit is terminal, fence retired
#           `gc-failed <ref>`                   terminal, but the delete failed
#           `honored <ref> <owner>`             a live owner holds an unfinished unit
#           `strand <ref> <owner> <liveness>`   surfaced to the operator, untouched
#                                               (<liveness>: dead | unknown |
#                                               ambiguous | orphan)
#           `tentative <ref>`                   unattributed, inside its grace window
#           `suppressed <ref>`                  already surfaced, still inside the
#                                               window that runs from its first
#                                               sighting — not re-probed this pass
#           `hold <ref> <reason>`               evidence incomplete: nothing decided
#           `anomaly <ref> <reason>`            a ref this mechanism did not write
#           `summary fences=<n> strands=<n>`
#
# The fence's target commit is `refs/heads/main` on `origin`, overridable with
# `PLANWRIGHT_FENCE_BASE_REF`, falling back to the remote's `HEAD` where that
# ref does not exist — so a repository whose default branch is not `main` still
# fences at an existing commit rather than failing.
#
# Exit codes:
#   0  success (fence won / check found a fence / gc done / list / sweep)
#   1  check only: the unit is NOT fenced
#   2  usage, refused hostile input, or a non-repository checkout (fail closed)
#   3  the unit is already fenced — back off and select another
#   4  transient `origin` failure — fail closed, surfaced, retry next pass
#   5  no `origin` remote — the genuine no-remote single-host solo posture
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling). All
# input is data; no eval. Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

TAB=$(printf '\t')
NS_ROOT=refs/planwright-fence

push_out=""
trap '[ -z "$push_out" ] || rm -f "$push_out"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
  cat >&2 <<'USAGE'
usage: fleet-fence.sh refname --spec <spec> <unit-id>
       fleet-fence.sh check   --checkout <dir> --spec <spec> <unit-id>
       fleet-fence.sh fence   --checkout <dir> --spec <spec> <unit-id>...
       fleet-fence.sh gc      --checkout <dir> --spec <spec> <unit-id>...
       fleet-fence.sh list    --checkout <dir> [--spec <spec>]
       fleet-fence.sh sweep   --checkout <dir> --spec <spec> (--session-id <uuid> | --pid <pid>) [--grace <sec>] [--min-interval <sec>]
USAGE
}

err() {
  echo "fleet-fence: $1" >&2
}

# --- grammars (validated BEFORE any ref or path use, REQ-D1.5) -------------

# The spec-identifier pattern the format pins (doctrine/spec-format.md).
is_spec_id() {
  case "$1" in
    "" | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# The task/unit-id grammar: a single id (`4`, `3.5`) or a bundle range
# (`3-4`, `3.5-4`) — the branch-naming grammar spec-format declares.
is_unit_id() {
  [ "${#1}" -le 32 ] || return 1
  printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$'
}

is_pid() {
  case "$1" in
    "" | *[!0-9]* | 0*) return 1 ;;
  esac
  [ "${#1}" -le 10 ]
}

is_uint() {
  case "$1" in
    "" | *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 12 ]
}

# fence_refname <spec> <unit-id> — the containment primitive. Both halves are
# grammar-validated, the assembled name is passed through
# `git check-ref-format` (git's own authority on ref-name legality: no `..`,
# no `@{`, no control bytes, no trailing `.lock`), and a literal prefix test
# confirms the result is inside this spec's namespace. Any failure refuses;
# nothing is coerced or sanitized into legality.
fence_refname() {
  fr_spec=$1
  fr_unit=$2
  is_spec_id "$fr_spec" || return 1
  is_unit_id "$fr_unit" || return 1
  fr_ref="$NS_ROOT/$fr_spec/$fr_unit"
  git check-ref-format "$fr_ref" >/dev/null 2>&1 || return 1
  case "$fr_ref" in
    "$NS_ROOT/$fr_spec/"?*) ;;
    *) return 1 ;;
  esac
  printf '%s' "$fr_ref"
}

# --- argument parsing ------------------------------------------------------

cmd="${1:-}"
case "$cmd" in
  refname | check | fence | gc | list | sweep) ;;
  *)
    usage
    exit 2
    ;;
esac
shift

checkout=""
spec=""
pid=""
session_id=""
grace=30
min_interval=30
units=""

# A flag irrelevant to the subcommand is a usage error, never a validated-then-
# ignored no-op (the sibling fleet-presence.sh discipline).
refuse_for() {
  case " $1 " in
    *" $cmd "*) ;;
    *)
      usage
      exit 2
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --checkout)
      refuse_for "check fence gc list sweep"
      checkout="${2:-}"
      shift 2 || {
        usage
        exit 2
      }
      ;;
    --spec)
      spec="${2:-}"
      shift 2 || {
        usage
        exit 2
      }
      ;;
    --pid)
      refuse_for "sweep"
      pid="${2:-}"
      shift 2 || {
        usage
        exit 2
      }
      ;;
    --session-id)
      refuse_for "sweep"
      session_id="${2:-}"
      shift 2 || {
        usage
        exit 2
      }
      ;;
    --grace)
      refuse_for "sweep"
      grace="${2:-}"
      shift 2 || {
        usage
        exit 2
      }
      ;;
    --min-interval)
      refuse_for "sweep"
      min_interval="${2:-}"
      shift 2 || {
        usage
        exit 2
      }
      ;;
    --*)
      usage
      exit 2
      ;;
    *)
      units="$units${units:+ }$1"
      shift
      ;;
  esac
done

# --- input validation ------------------------------------------------------

case "$cmd" in
  list)
    [ -z "$units" ] || {
      usage
      exit 2
    }
    ;;
  refname | check)
    case "$units" in
      "" | *" "*)
        usage
        exit 2
        ;;
    esac
    ;;
  fence | gc)
    [ -n "$units" ] || {
      usage
      exit 2
    }
    ;;
  sweep)
    [ -z "$units" ] || {
      usage
      exit 2
    }
    ;;
esac

if [ "$cmd" != list ] || [ -n "$spec" ]; then
  if ! is_spec_id "$spec"; then
    err "refusing malformed spec id (the ^[a-z0-9][a-z0-9-]*\$ identifier grammar, <=64)"
    exit 2
  fi
fi

# Validate every unit id and assemble its ref name up front: nothing reaches a
# push or a delete before its whole ref name is proven contained.
refs=""
for u in $units; do
  r=$(fence_refname "$spec" "$u") || {
    err "refusing unit id '$(sanitize_printable "$u" "(unprintable)")': it is outside the unit-id grammar or would escape $NS_ROOT/$spec/"
    exit 2
  }
  # A repeated member would put two refspecs for one ref in a single push.
  case " $refs " in
    *" $r "*)
      err "refusing a bundle that names unit '$(sanitize_printable "$u" "(unprintable)")' twice"
      exit 2
      ;;
  esac
  refs="$refs${refs:+ }$r"
done

if [ "$cmd" = refname ]; then
  printf '%s\n' "$refs"
  exit 0
fi

if [ -n "$session_id" ] && [ -n "$pid" ]; then
  usage
  exit 2
fi
if [ -n "$pid" ] && ! is_pid "$pid"; then
  err "refusing malformed pid (a positive integer, no leading zero)"
  exit 2
fi
if ! is_uint "$grace" || ! is_uint "$min_interval"; then
  err "refusing malformed --grace/--min-interval (seconds)"
  exit 2
fi
if [ "$cmd" = sweep ] && [ -z "$session_id" ] && [ -z "$pid" ]; then
  err "sweep needs the tower identity (--session-id or --pid) so its own fences are attributable"
  exit 2
fi

case "$checkout" in
  /*) ;;
  *)
    err "refusing checkout: an existing absolute directory is required"
    exit 2
    ;;
esac
if [ ! -d "$checkout" ]; then
  err "refusing checkout: an existing absolute directory is required"
  exit 2
fi
checkout=$(cd "$checkout" && pwd -P) || {
  err "refusing checkout: cannot canonicalize it"
  exit 2
}
if ! git -C "$checkout" rev-parse --git-dir >/dev/null 2>&1; then
  err "refusing checkout: $(sanitize_printable "$checkout" "(unprintable)") is not a git repository"
  exit 2
fi

# --- origin posture (REQ-C1.6, D-10) ---------------------------------------

# A non-repository checkout was already refused above (exit 2): exit 5 is
# reserved for a real repository with no `origin`, so a typo'd path can never
# silently authorize the solo posture.
if ! git -C "$checkout" config --get remote.origin.url >/dev/null 2>&1; then
  printf 'solo\tno-origin\n'
  err "no origin remote on this checkout — the genuine no-remote single-host solo posture: there is no peer to collide with, so dispatch proceeds WITHOUT a fence (REQ-C1.6)"
  exit 5
fi

# zero_oid — the object format's all-zeros object id, the must-be-absent
# expectation the lease names. Explicit and format-correct: the bare-empty
# `<ref>:` form is deliberately never used (D-5).
zero_oid() {
  case "$(git -C "$checkout" rev-parse --show-object-format 2>/dev/null)" in
    sha256) printf '%064d' 0 ;;
    *) printf '%040d' 0 ;;
  esac
}

# ls_remote_fences <pattern> — the LIVE fence-ref read (never a possibly-stale
# checkout-local remote-tracking ref). Prints one ref name per line. A failure
# is transient by construction: `origin` is configured, so an unreachable or
# erroring remote must fail closed rather than read as "no fences".
ls_remote_fences() {
  lrf_out=$(git -C "$checkout" ls-remote origin "$1" 2>/dev/null) || return 1
  printf '%s' "$lrf_out" | awk -F"$TAB" 'NF == 2 && $2 != "" { print $2 }'
}

# origin_main_tip — the fixed sentinel the fence ref is created at: an
# existing commit, so the fence adds no history to `main`. Read live from
# `origin` (which doubles as the reachability probe).
origin_main_tip() {
  omt_ref=${PLANWRIGHT_FENCE_BASE_REF:-refs/heads/main}
  omt_out=$(git -C "$checkout" ls-remote origin "$omt_ref" HEAD 2>/dev/null) || return 1
  omt_tip=$(printf '%s' "$omt_out" \
    | awk -F"$TAB" -v want="$omt_ref" 'NF == 2 && $2 == want { print $1; exit }')
  if [ -z "$omt_tip" ]; then
    omt_tip=$(printf '%s' "$omt_out" \
      | awk -F"$TAB" 'NF == 2 && $2 == "HEAD" { print $1; exit }')
  fi
  [ -n "$omt_tip" ] || return 1
  printf '%s' "$omt_tip"
}

# --- check (the selection guard, REQ-C1.5) ---------------------------------

if [ "$cmd" = check ]; then
  present=$(ls_remote_fences "$refs") || {
    err "transient origin failure reading $refs — failing closed: this unit is NOT dispatched this pass; surfaced, retry next pass (REQ-C1.6)"
    exit 4
  }
  if [ -n "$present" ]; then
    printf 'fenced\t%s\n' "$refs"
    exit 0
  fi
  printf 'unfenced\t%s\n' "$refs"
  exit 1
fi

# --- list ------------------------------------------------------------------

if [ "$cmd" = list ]; then
  if [ -n "$spec" ]; then
    pattern="$NS_ROOT/$spec/*"
  else
    pattern="$NS_ROOT/*"
  fi
  found=$(ls_remote_fences "$pattern") || {
    err "transient origin failure listing $pattern — failing closed"
    exit 4
  }
  [ -z "$found" ] || printf '%s\n' "$found"
  exit 0
fi

# --- gc (idempotent terminal-fence delete, REQ-C1.5) -----------------------

# gc_refs — delete every ref named in the global `refs` from `origin`. It takes
# NO arguments, deliberately: `refs` is the containment-checked ref list built
# once at parse time, and the sweep re-derives it through `fence_refname` before
# each call, so no caller can hand this function a name that skipped the check.
# Idempotent by
# construction: refs already absent are reported `gc-absent` and never pushed,
# and a ref that vanishes between the read and the push (a peer GC'ing the same
# terminal fence) is success, not an error. Never `--force`: a delete refspec
# needs no force, and forcing is exactly the overwrite this script refuses.
gc_refs() {
  gr_present=$(ls_remote_fences "$NS_ROOT/$spec/*") || {
    err "transient origin failure reading the fence namespace before a terminal-fence delete — failing closed: nothing is GC'd this pass; surfaced, retried next pass (REQ-C1.5)"
    return 4
  }
  gr_todo=""
  for gr_r in $refs; do
    case "$(printf '%s\n' "$gr_present" | grep -Fx -- "$gr_r" || true)" in
      "")
        printf 'gc-absent\t%s\n' "$gr_r"
        ;;
      *)
        gr_todo="$gr_todo${gr_todo:+ }$gr_r"
        ;;
    esac
  done
  [ -n "$gr_todo" ] || return 0

  set -- origin
  for gr_r in $gr_todo; do
    set -- "$@" ":$gr_r"
  done
  # Explicit template (the house pattern, cf. scripts/builder-guards.sh): BSD
  # mktemp supplies no default one, and this script's floor is bash 3.2 / BSD.
  push_out=$(mktemp "${TMPDIR:-/tmp}/fleet-fence-gc.XXXXXX") || {
    err "cannot create a temp file for the push transcript — failing closed"
    return 4
  }
  git -C "$checkout" push --porcelain --atomic "$@" >"$push_out" 2>&1
  gr_rc=$?
  if [ "$gr_rc" != 0 ]; then
    # The one benign failure: the ref vanished between the read above and the
    # push (a peer GC'd the same terminal fence). Anything else is transient.
    if grep -q 'remote ref does not exist' "$push_out"; then
      gr_rc=0
    else
      err "transient origin failure deleting a terminal fence — surfaced, retried next pass (REQ-C1.5): $(sanitize_printable "$(tr '\n' ' ' <"$push_out")" "(unprintable)")"
      rm -f "$push_out"
      push_out=""
      return 4
    fi
  fi
  rm -f "$push_out"
  push_out=""
  for gr_r in $gr_todo; do
    printf 'gc\t%s\n' "$gr_r"
  done
  return 0
}

if [ "$cmd" = gc ]; then
  gc_refs
  exit $?
fi

# --- the durable, dedup'd operator sink (REQ-C1.7, D-7) --------------------
#
# "Surfaced" means a durable, deduplicated, operator-facing entry delivered by
# PUSH through `orchestration-fleet`'s attention surface — never a transient
# log line, never poll-only. That surface is consumed as-is (REQ-D1.1); this
# script only supplies the keys and the text.
#
# Deduplication IS the key. Every entry is keyed by a digest of the fence-ref
# name plus the owner identity (record identity for an anomaly), so the same
# strand re-observed on successive passes upserts the same row rather than
# stacking a new one — and the row is only written when it is absent, so its
# timestamp stays pinned to FIRST observation.
#
# That pinned timestamp is also the tower's cross-pass memory. A stateless
# tower keeps no local store, so the one-pass grace re-check an unknown-owner
# orphan needs (REQ-C1.3) lives in the sink: the first sighting writes a
# TENTATIVE entry stamped with its first-seen time, and a later pass promotes
# it to a surfaced strand only once a heartbeat interval has elapsed since
# then. Because the stamp is in the shared sink rather than in the tower, the
# grace window holds cross-tower: a second tower sweeping immediately after
# the first reads the same first-seen time and cannot short-circuit it.
#
# Data hygiene (REQ-D1.4): an entry names the unit and the owner's TOWER
# IDENTITY only. The peer's checkout path and its death handle never reach it
# — `attribute` returns neither.

FA="$script_dir/fleet-attention.sh"
FP="$script_dir/fleet-presence.sh"
OS="$script_dir/orchestrate-state.sh"

sink_cache=""

# key_digest <text> — a bounded, grammar-safe dedup key. The attention
# surface's handle grammar admits no `/`, and a ref name plus a tower identity
# can exceed its length bound, so the key is a digest and the human-readable
# unit rides the scope and question fields.
key_digest() {
  printf '%s' "$1" | git -C "$checkout" hash-object --stdin 2>/dev/null | cut -c1-12
}

sink_load() {
  sink_cache=$("$FA" render 2>/dev/null) || sink_cache=""
}

# sink_age <worker> — seconds since the entry was first written, or empty when
# there is no such entry. `render` prints `[state] scope worker (Ns)`.
sink_age() {
  printf '%s\n' "$sink_cache" | awk -v w="$1" '
    NF >= 2 {
      n = $(NF - 1); age = $NF
      sub(/^\(/, "", age); sub(/s\)$/, "", age)
      if (n == w) { print age; exit }
    }'
}

sink_clear() {
  "$FA" clear "$1" >/dev/null 2>&1 || true
}

# sink_surface <worker> <scope> <question> — raise ONE actionable operator
# item offering the three defined actions, then push it through the configured
# notification channel. Delivery failures are surfaced, never fatal: the entry
# is already durable, and a notification channel is a courtesy on top of it.
#
# Entry text is ASCII. The attention surface's text grammar refuses any value
# that changes under `sanitize_printable`, and that sanitizer strips C1
# (0x80-0x9F) — which are continuation bytes inside every non-ASCII UTF-8
# sequence, so an em dash or a typographic quote is refused as a control byte.
sink_surface() {
  ss_rc=0
  "$FA" fork "$1" "$2" "$3" investigate 'reclaim|investigate|dismiss' "$1" high \
    >/dev/null 2>&1 || ss_rc=$?
  case "$ss_rc" in
    0) ;;
    3)
      # The surface already holds a queued human decision for this key; the
      # operator has it. Do not clobber it, and do not re-notify.
      return 0
      ;;
    *)
      err "could not raise the operator item for $(sanitize_printable "$2" "(unprintable)") — the strand is reported here but not durably surfaced"
      return 1
      ;;
  esac
  "$FA" notify "$3" >/dev/null 2>&1 || err "the strand was recorded but the notification channel did not accept the push"
  return 0
}

# --- sweep (REQ-C1.3, REQ-C1.5, REQ-C1.7) ----------------------------------

if [ "$cmd" = sweep ]; then
  fences=$(ls_remote_fences "$NS_ROOT/$spec/*") || {
    err "transient origin failure listing the fence namespace — failing closed: nothing is classified or GC'd this pass, retry next pass (REQ-C1.3)"
    exit 4
  }
  if [ -z "$fences" ]; then
    printf 'summary\tfences=0\tstrands=0\n'
    exit 0
  fi

  # The identity flags the sweep was invoked with are forwarded verbatim to
  # `attribute`, so the tower's OWN fences attribute to itself instead of
  # reading as orphans.
  set --
  if [ -n "$session_id" ]; then
    set -- --session-id "$session_id"
  else
    set -- --pid "$pid"
  fi

  # Terminality is the derivation engine's answer, not a second reading of the
  # same evidence: `completed` is exactly "PR merged, or the ledger marks it
  # done". An OPEN, unmerged PR derives in-progress, so it is not terminal and
  # the fence rightly persists (REQ-C1.5).
  spec_dir="$checkout/specs/$spec"
  state=""
  evidence_ok=1
  if [ -d "$spec_dir" ]; then
    state=$("$OS" "$spec_dir" 2>/dev/null) || evidence_ok=0
    # A configured-but-failing gh probe leaves the derivation partial. Acting
    # on it could GC the fence of a unit that is not terminal, so the pass
    # fails closed: classify nothing, retry next pass (REQ-C1.3).
    if printf '%s\n' "$state" | grep -q "^degraded${TAB}"; then
      evidence_ok=0
    fi
  else
    evidence_ok=0
  fi

  sink_load
  strands=0
  count=0

  for ref in $fences; do
    count=$((count + 1))
    unit=${ref#"$NS_ROOT/$spec/"}

    # A ref inside the namespace whose tail is off-grammar was not written by
    # this mechanism. It is surfaced as an anomaly and never parsed into a ref
    # operation — the containment rule applies to what we READ, not only to
    # what we write (REQ-D1.5).
    if [ "$unit" = "$ref" ] || ! is_unit_id "$unit"; then
      akey="pwfence-x.$(key_digest "$ref")"
      if [ -z "$(sink_age "$akey")" ]; then
        sink_surface "$akey" "$spec:anomaly" \
          "planwright fence anomaly: the ref $(sanitize_printable "$ref" "(unprintable)") sits in this spec's fence namespace but its unit id is off-grammar, so nothing parsed it and nothing touched it. Choose: reclaim (delete it yourself), investigate, or dismiss." || true
      fi
      printf 'anomaly\t%s\t%s\n' "$ref" "off-grammar-unit-id"
      continue
    fi

    # Attribution, not a correctness read (D-7): it maps the fence to an owner
    # so a strand can be NAMED. A missing or unreadable presence surface
    # degrades to unknown-owner, which is safe precisely because presence is
    # never on the correctness path (D-5, D-11).
    attr=$("$FP" attribute --checkout "$checkout" "$@" "$spec/$unit" 2>/dev/null) || attr=""
    case "$attr" in
      "owner$TAB"*)
        owner=$(printf '%s' "$attr" | awk -F"$TAB" '{print $2}')
        liveness=$(printf '%s' "$attr" | awk -F"$TAB" '{print $3}')
        ;;
      *)
        owner="unknown-owner"
        liveness="unattributed"
        ;;
    esac

    skey="pwfence.$(key_digest "$ref|$owner")"
    tkey="pwfence-t.$(key_digest "$ref")"
    scope="$spec:$unit"

    # An already-surfaced strand is skipped while its sink entry is younger
    # than the cadence window. That window runs from FIRST observation and does
    # not renew: the entry's timestamp is pinned there by design (a strand is a
    # queued operator decision, and `fork` refuses to overwrite one), so once it
    # has elapsed the ref is re-examined on every later pass. Deliberate, and
    # narrower than REQ-C1.3's "not re-checked every sweep" reads on its face —
    # what that requirement is protecting is stated in its own purpose clause,
    # an unbounded per-pass fan-out of `origin`/`gh` reads, and the strand path
    # this skip governs has none to bound: the namespace read and the state
    # derivation are both hoisted ABOVE this loop and cost one `ls-remote` and
    # one derivation per sweep however many strands are queued. (The TERMINAL
    # path below does read `origin` per ref — `gc_refs` re-reads the namespace
    # before each delete — but that fan-out is bounded by the fences that went
    # terminal this pass, and a suppressed strand never reaches it.) What the
    # skip saves is the per-ref attribution subprocess.
    age=$(sink_age "$skey")
    case "$age" in
      "" | *[!0-9]*) ;;
      *)
        if [ "$min_interval" -gt 0 ] && [ "$age" -lt "$min_interval" ]; then
          printf 'suppressed\t%s\n' "$ref"
          continue
        fi
        ;;
    esac

    # TERMINAL FIRST, then liveness: a terminal unit's fence is completed
    # work, GC'd regardless of whether its owner is alive, and its sink entry
    # goes with it so the sink stays bounded (REQ-C1.5, REQ-C1.7).
    #
    # This check runs even on a DEGRADED pass. `completed` outranks the gh
    # probe — it is git ground truth (a merge-reachable branch or the durable
    # completion trailer) — so a positive answer stays positive when gh cannot
    # be reached. What a degraded pass cannot rule out is the reverse: a unit
    # whose ONLY terminal evidence is its merged PR reads as non-terminal, so
    # everything below the terminal check holds rather than surfacing a strand
    # that may be finished work (REQ-C1.3, fail closed: do not act, retry).
    if printf '%s\n' "$state" \
      | awk -F"$TAB" -v u="$unit" '$1 == "task" && $2 == u && $3 == "completed" { f = 1 } END { exit !f }'; then
      # Re-derive the ref through the containment primitive rather than
      # deleting the string read off `origin`: REQ-D1.5 wants BOTH halves —
      # `git check-ref-format` and the literal prefix — before any delete, and
      # the prefix test above is only the second of them.
      refs=$(fence_refname "$spec" "$unit") || {
        printf 'anomaly\t%s\t%s\n' "$ref" "unrepresentable-fence-ref"
        continue
      }
      if gc_refs; then
        sink_clear "$tkey"
        sink_clear "$skey"
        sink_clear "pwfence.$(key_digest "$ref|unknown-owner")"
      else
        printf 'gc-failed\t%s\n' "$ref"
      fi
      continue
    fi

    if [ "$evidence_ok" != 1 ]; then
      printf 'hold\t%s\t%s\n' "$ref" "evidence-degraded"
      continue
    fi

    case "$liveness" in
      live)
        # In flight and alive: the FENCE is honored, untouched. Its sink
        # entries are not — the tentative one from a pass where the owner's
        # heartbeat had not caught up, and any strand already surfaced for it.
        # A strand is keyed by ref plus OWNER (REQ-C1.7), so an orphan promoted
        # before attribution caught up sits under `unknown-owner`, a key no
        # later pass recomputes. Left there it offers the operator `reclaim` on
        # a unit a live tower is demonstrably carrying.
        sink_clear "$tkey"
        sink_clear "$skey"
        sink_clear "pwfence.$(key_digest "$ref|unknown-owner")"
        printf 'honored\t%s\t%s\n' "$ref" "$owner"
        continue
        ;;
      dead | unknown | ambiguous) ;;
      *)
        # No live or dead record lists this fence. That may simply be
        # heartbeat lag between a peer's fence push and its next refresh, so
        # surfacing now would raise a FALSE strand on a unit legitimately in
        # flight. Hold it tentative and let the grace window decide.
        tage=$(sink_age "$tkey")
        case "$tage" in
          "" | *[!0-9]*)
            "$FA" park "$tkey" "$scope" \
              "notification:planwright-fence tentative: the fence for $scope is listed by no presence record yet, which is also what heartbeat lag looks like. Held for one heartbeat interval before it is raised as a strand." \
              >/dev/null 2>&1 || err "could not record the tentative entry for $scope; the grace re-check degrades to re-observing it next pass"
            printf 'tentative\t%s\n' "$ref"
            continue
            ;;
          *)
            if [ "$tage" -lt "$grace" ]; then
              printf 'tentative\t%s\n' "$ref"
              continue
            fi
            ;;
        esac
        liveness=orphan
        ;;
    esac

    # A strand: SURFACED, never auto-reclaimed. Reclaiming a dead owner's
    # in-flight unit is a reserved operator decision (D-7, D-13), so the fence
    # ref is left exactly where it is and the operator gets an actionable item.
    strands=$((strands + 1))
    if [ -z "$(sink_age "$skey")" ]; then
      sink_surface "$skey" "$scope" \
        "planwright strand: unit $scope is fenced by tower $(sanitize_printable "$owner" "(unknown)") ($liveness) and the unit is not terminal, so no live tower will carry it to merge. Nothing was reclaimed. Choose: reclaim (take the unit over yourself), investigate, or dismiss." || true
      sink_clear "$tkey"
    fi
    printf 'strand\t%s\t%s\t%s\n' "$ref" "$owner" "$liveness"
  done

  printf 'summary\tfences=%s\tstrands=%s\n' "$count" "$strands"
  exit 0
fi

# --- fence (the expect-absent CAS, REQ-C1.1, REQ-C1.2, REQ-C1.6) -----------

# push_status <ref> — the per-ref porcelain status flag for <ref>, or empty
# when the push produced no line for it. `git push --porcelain` writes
# `<flag>\t<from>:<to>\t<summary>`; the `To <url>` and `Done` lines carry no
# tabs and are skipped by the field-count test.
push_status() {
  awk -F"$TAB" -v want="$1" '
    NF >= 3 {
      n = index($2, ":")
      if (n > 0 && substr($2, n + 1) == want) { print $1; exit }
    }' "$push_out"
}

push_summary() {
  awk -F"$TAB" -v want="$1" '
    NF >= 3 {
      n = index($2, ":")
      if (n > 0 && substr($2, n + 1) == want) { print $3; exit }
    }' "$push_out"
}

# Pre-flight: a fence already on `origin` means the unit is taken, so the
# bundle backs off before pushing anything. This is the same live read the
# selection guard makes; it is an optimization, not the guarantee — the CAS
# below re-adjudicates whatever lands between this read and the push.
present=$(ls_remote_fences "$NS_ROOT/$spec/*") || {
  err "transient origin failure reading the fence namespace — failing closed: nothing is dispatched this pass; surfaced, retry next pass (REQ-C1.6)"
  exit 4
}
for r in $refs; do
  if printf '%s\n' "$present" | grep -Fxq -- "$r"; then
    printf 'taken\t%s\n' "$r"
    exit 3
  fi
done

tip=$(origin_main_tip) || {
  err "transient origin failure resolving the origin/main tip — failing closed: nothing is dispatched this pass; surfaced, retry next pass (REQ-C1.6)"
  exit 4
}
zero=$(zero_oid)

set --
for r in $refs; do
  set -- "$@" "--force-with-lease=$r:$zero"
done
set -- "$@" origin
for r in $refs; do
  set -- "$@" "$tip:$r"
done

push_out=$(mktemp "${TMPDIR:-/tmp}/fleet-fence-push.XXXXXX") || {
  err "cannot create a temp file for the push transcript — failing closed"
  exit 4
}
git -C "$checkout" push --porcelain --atomic "$@" >"$push_out" 2>&1
push_rc=$?

won=""
taken=""
transient=""
for r in $refs; do
  flag=$(push_status "$r")
  case "$flag" in
    '*') won="$won${won:+ }$r" ;;
    '=')
      # git short-circuits a same-value update to `[up to date]` BEFORE the
      # lease is evaluated, so this — not a rejection — is how a losing tower
      # sees an already-fenced unit. It is the load-bearing case: every racing
      # tower targets the same `origin/main` tip.
      taken="$taken${taken:+ }$r"
      ;;
    '!')
      case "$(push_summary "$r")" in
        *"stale info"* | *"fetch first"* | *"non-fast-forward"* | *"already exists"*)
          taken="$taken${taken:+ }$r"
          ;;
        *) transient="$transient${transient:+ }$r" ;;
      esac
      ;;
    *) transient="$transient${transient:+ }$r" ;;
  esac
done

# The bundle is all-or-none: unless EVERY member reported `*`, this tower
# fenced nothing. `--atomic` rolls back rejections but not `[up to date]`, so
# any member this push actually created is deleted here, lease-guarded on the
# value we pushed — the tower removes only what it created and can never
# delete a peer's fence.
if [ -n "$taken$transient" ]; then
  if [ -n "$won" ]; then
    set --
    for r in $won; do
      set -- "$@" "--force-with-lease=$r:$tip"
    done
    set -- "$@" origin
    for r in $won; do
      set -- "$@" ":$r"
    done
    if ! git -C "$checkout" push --porcelain --atomic "$@" >/dev/null 2>&1; then
      err "backed off the bundle but could not delete the member fence(s) this push created ($(sanitize_printable "$won" "(unprintable)")) — surfaced; the discovery sweep will classify them (REQ-C1.5)"
    fi
  fi
  rm -f "$push_out"
  push_out=""
  if [ -n "$taken" ]; then
    for r in $taken; do
      printf 'taken\t%s\n' "$r"
    done
    exit 3
  fi
  err "transient origin failure fencing $(sanitize_printable "$transient" "(unprintable)") — failing closed: nothing is dispatched this pass; surfaced, retry next pass (REQ-C1.6)"
  exit 4
fi

if [ "$push_rc" != 0 ]; then
  rm -f "$push_out"
  push_out=""
  err "the fence push exited non-zero with every member reported created — failing closed rather than dispatching on an ambiguous result"
  exit 4
fi

rm -f "$push_out"
push_out=""
for r in $refs; do
  printf 'fenced\t%s\n' "$r"
done
exit 0
