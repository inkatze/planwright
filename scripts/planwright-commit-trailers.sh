#!/bin/sh
# planwright-commit-trailers.sh — stamp planwright's footer trailers
# (`Planwright-Task: <spec>/<id>`, and the sign-off pair below) onto a commit
# message (Task 2, REQ-C1.4, D-2).
#
# The trailer is planwright's durable, cross-flow completion anchor: it
# survives branch deletion and solo direct-to-`main` commits. This helper
# emits it in the footer; Task 1's derivation engine reads it by scanning the
# whole commit message for `Planwright-Task:` lines (not git's footer-only
# `%(trailers)`), so the anchor is still recognized when a squash/rebase merge
# relocates it mid-body. This helper is the one shared place that emits it, so
# `/execute-task` and any manual/solo committer produce the identical,
# well-formed trailer.
#
# Usage:
#   planwright-commit-trailers.sh <spec>/<id> [<spec>/<id> ...] < message
#
#   Reads a commit message on stdin and writes it back on stdout with one
#   `Planwright-Task: <spec>/<id>` trailer appended to the footer per ref
#   given as an argument. A bundled commit passes several refs → one trailer
#   each. Compose it straight into the commit:
#
#     printf '%s\n' "$msg" \
#       | scripts/planwright-commit-trailers.sh orchestration-concurrency/2 \
#       | git commit -F -
#
# Behavior:
#   - Trailers land in the footer via `git interpret-trailers`, never the
#     subject line (D-2: discreet by design — footer only). Only planwright's
#     own trailers are added; no Claude/co-author attribution is introduced
#     (the no-attribution rule is unaffected).
#   - `--if-exists addIfDifferent` makes a task-ref or `--reject` re-stamp
#     idempotent: piping an already-trailered message through again does not
#     duplicate it. A `--sign-off` re-stamp is refused (below).
#   - Each ref is grammar-validated before use (REQ-F1.1 discipline): spec
#     `^[a-z0-9][a-z0-9-]*$` (≤64 chars, the D-36 spec-id grammar), id
#     `^[0-9]+(\.[0-9]+)?$`. The id is the *single-task subset* of D-36's
#     branch `<id-or-ids>` grammar: a trailer names one task (D-2 — a bundle
#     carries one trailer line per task), so the bundle-range form (`3-4`) is
#     deliberately not accepted here. A malformed ref, a ref with an embedded
#     newline, or nothing to stamp at all (no ref, `--sign-off`, or
#     `--reject`) is refused (exit 2) and nothing is emitted — the value is
#     never interpolated into the trailer.
#
# Sign-off trailers (doctrine/gate-wiring.md, *The `Planwright-Sign-Off`
# trailer*), stamped alongside or instead of the task refs:
#
#   planwright-commit-trailers.sh [<spec>/<id> ...] --base <base> --sign-off \
#     [--sign-off ...] < message
#   planwright-commit-trailers.sh [<spec>/<id> ...] --reject <id> [--reject <id> ...] < message
#
#   - Each `--sign-off` appends one `Planwright-Sign-Off: PS-<n>`, allocated
#     from the branch's next free id over <base>..HEAD by
#     sign-off-checklist.sh; a shared commit passes one per finding. Run it in
#     the checkout the commit lands in, since HEAD is the allocation range's
#     end, and commit before stamping the next message. The id is written
#     once: a message already carrying a sign-off id is refused, and an
#     unresolvable range refuses (exit 3) rather than restart the sequence.
#   - Each `--reject <id>` appends `Planwright-Sign-Off-Rejected: <id>`, where
#     <id> is `PS-<n>` (at most nine digits) or `PS-legacy-<sha7>`; anything
#     else is refused.
#
# Exit: 0 on success; 2 on a usage error, a malformed ref or id, or a message
# that already carries a sign-off id; 3 when the allocation range does not
# resolve. Every failure emits nothing.
#
# Portable POSIX sh (the bash 3.2 / busybox floor): no bashisms; validation
# uses grep -E, the trailer flag list is built by rotating the positional
# parameters.
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

prog=${0##*/}

# A literal newline, for the embedded-newline guard in valid_ref.
LF='
'

usage() {
  echo "usage: $prog [<spec>/<id> ...] [--base <base> --sign-off ...] [--reject <id> ...] < message" >&2
}

# valid_ref <ref> — true when <ref> is `<spec>/<id>` with a grammar-valid spec
# (^[a-z0-9][a-z0-9-]*$, ≤64) and id (^[0-9]+(\.[0-9]+)?$, the single-task
# subset of D-36's branch grammar — no bundle range). Exactly one slash; no
# further slash in the id (blocks `../` path escapes); no embedded newline
# (the grep below is `^…$`-anchored and matches line-by-line, so without this
# a ref whose first line is valid would slip a second line through into the
# trailer — REQ-F1.1: hostile input is refused, never interpolated).
valid_ref() {
  _ref=$1
  case "$_ref" in
    *"$LF"*) return 1 ;;
  esac
  case "$_ref" in
    */*) ;;
    *) return 1 ;;
  esac
  _spec=${_ref%%/*}
  _id=${_ref#*/}
  case "$_id" in
    */*) return 1 ;;
  esac
  printf '%s' "$_spec" | grep -qE '^[a-z0-9][a-z0-9-]{0,63}$' || return 1
  # `flight` is the reserved flight branch segment (tower-front-door D-11),
  # never a spec a task trailer can anchor to.
  [ "$_spec" != flight ] || return 1
  printf '%s' "$_id" | grep -qE '^[0-9]+(\.[0-9]+)?$' || return 1
  return 0
}

# valid_rejected_id <id> — `PS-<n>` or `PS-legacy-<sha7>`, one line.
valid_rejected_id() {
  case "$1" in
    *"$LF"*) return 1 ;;
  esac
  printf '%s' "$1" | grep -qE '^PS-([1-9][0-9]{0,8}|legacy-[0-9a-f]{7})$'
}

# First pass: validate every argument before emitting anything (fail closed).
base=""
signoffs=0
rejects=""
nrefs=0
want=""
for arg in "$@"; do
  case "$want" in
    base)
      base=$arg
      want=""
      continue
      ;;
    reject)
      if ! valid_rejected_id "$arg"; then
        echo "$prog: refusing a malformed rejected id (expected PS-<n> or PS-legacy-<sha7>)" >&2
        exit 2
      fi
      # Validated ids carry no whitespace or glob characters, so the list
      # splits safely on spaces below.
      rejects="$rejects $arg"
      want=""
      continue
      ;;
  esac
  case "$arg" in
    --base) want=base ;;
    --reject) want=reject ;;
    --sign-off) signoffs=$((signoffs + 1)) ;;
    *)
      if ! valid_ref "$arg"; then
        # Never echo the candidate back: a malformed ref can carry terminal escapes
        # or a newline-injected forged log line, so echoing it verbatim is terminal/
        # log injection. The sibling validators (spec-validate.sh, spec-walkthrough.sh)
        # refuse the same spec-id grammar without echoing the candidate, and this
        # helper's own contract (REQ-F1.1) is "hostile input is refused, never
        # interpolated". The grammar hint below is enough to act on the refusal.
        echo "$prog: refusing a malformed task ref (does not match the expected grammar)" >&2
        echo "$prog: expected <spec>/<id>, spec ^[a-z0-9][a-z0-9-]*$ (≤64, not flight) id ^[0-9]+(\\.[0-9]+)?$" >&2
        exit 2
      fi
      nrefs=$((nrefs + 1))
      ;;
  esac
done

# A dangling option, --base without --sign-off (or the reverse), or nothing to
# stamp at all is a usage error.
if [ -n "$want" ] \
  || { [ -n "$base" ] && [ "$signoffs" -eq 0 ]; } \
  || { [ -z "$base" ] && [ "$signoffs" -gt 0 ]; } \
  || { [ "$nrefs" -eq 0 ] && [ "$signoffs" -eq 0 ] && [ -z "$rejects" ]; }; then
  usage
  exit 2
fi

msg=$(cat)

next=0
if [ "$signoffs" -gt 0 ]; then
  parsed=$(printf '%s\n' "$msg" | git interpret-trailers --parse) || exit 2
  if printf '%s\n' "$parsed" | grep -qi '^Planwright-Sign-Off:'; then
    echo "$prog: the message already carries a sign-off id; an id is written once" >&2
    exit 2
  fi
  script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
  # A failed allocation has already named its error on stderr; its exit code
  # (3 for an unresolvable range) passes through and nothing is emitted.
  alloc=$("$script_dir/sign-off-checklist.sh" next "$base") || exit $?
  if ! printf '%s' "$alloc" | grep -qE '^PS-[1-9][0-9]{0,8}$'; then
    echo "$prog: the allocator returned no usable id; nothing stamped" >&2
    exit 2
  fi
  next=${alloc#PS-}
fi

# Second pass: rotate the arguments (the leading $# positional params) into the
# `--trailer` flag list git wants, task refs first. Each iteration consumes
# the front argument and appends a flag to the back, so after $# rotations
# only the flags remain. Options and their arguments are dropped here; the
# sign-off and rejected trailers are appended after the loop.
n=$#
i=0
while [ "$i" -lt "$n" ]; do
  arg=$1
  shift
  i=$((i + 1))
  case "$arg" in
    --base | --reject)
      shift
      i=$((i + 1))
      ;;
    --sign-off) ;;
    *) set -- "$@" --trailer "Planwright-Task: $arg" ;;
  esac
done
i=0
while [ "$i" -lt "$signoffs" ]; do
  set -- "$@" --trailer "Planwright-Sign-Off: PS-$((next + i))"
  i=$((i + 1))
done
for id in $rejects; do
  set -- "$@" --trailer "Planwright-Sign-Off-Rejected: $id"
done

printf '%s\n' "$msg" | git interpret-trailers --if-exists addIfDifferent "$@"
