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
#   sweep:  see `sweep` below
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

# gc_refs <ref>... — delete each ref from `origin`. Idempotent by
# construction: refs already absent are reported `gc-absent` and never pushed,
# and a ref that vanishes between the read and the push (a peer GC'ing the same
# terminal fence) is success, not an error. Never `--force`: a delete refspec
# needs no force, and forcing is exactly the overwrite this script refuses.
gc_refs() {
  gr_present=$(ls_remote_fences "$NS_ROOT/$spec/*") || return 4
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
  push_out=$(mktemp) || return 4
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

push_out=$(mktemp) || {
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
