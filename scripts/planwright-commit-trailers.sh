#!/bin/sh
# planwright-commit-trailers.sh — stamp `Planwright-Task: <spec>/<id>` footer
# trailers onto a commit message (Task 2, REQ-C1.4, D-2).
#
# The trailer is planwright's durable, cross-flow completion anchor: it
# survives branch deletion and solo direct-to-`main` commits, and Task 1's
# derivation engine reads it through git's native trailer mechanism
# (`git log --format='%(trailers:key=Planwright-Task)'`). This helper is the
# one shared place that emits it, so `/execute-task` and any manual/solo
# committer produce the identical, well-formed trailer.
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
#     subject line (D-2: discreet by design — footer only). Only the
#     `Planwright-Task` trailer is added; no Claude/co-author attribution is
#     introduced (the no-attribution rule is unaffected).
#   - `--if-exists addIfDifferent` makes a re-stamp idempotent: piping an
#     already-trailered message through again does not duplicate it.
#   - Each ref is grammar-validated before use (REQ-F1.1 discipline, the same
#     grammars /execute-task's pre-flight and bootstrap D-36 enforce):
#     spec `^[a-z0-9][a-z0-9-]*$` (≤64 chars), id `^[0-9]+(\.[0-9]+)?$`. A
#     malformed ref or no ref at all is refused (exit 2) and nothing is
#     emitted — the value is never interpolated into the trailer.
#
# Exit: 0 on success; 2 on a usage error or a malformed ref (fail closed,
# emitting nothing).
#
# Portable POSIX sh (the bash 3.2 / busybox floor): no bashisms; validation
# uses grep -E, the trailer flag list is built by rotating the positional
# parameters.
set -eu
LC_ALL=C
export LC_ALL

prog=${0##*/}

usage() {
  echo "usage: $prog <spec>/<id> [<spec>/<id> ...] < message" >&2
}

# valid_ref <ref> — true when <ref> is `<spec>/<id>` with a grammar-valid
# spec (^[a-z0-9][a-z0-9-]*$, ≤64) and id (^[0-9]+(\.[0-9]+)?$). Exactly one
# slash; no further slash in the id (blocks `../` path escapes).
valid_ref() {
  _ref=$1
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
  printf '%s' "$_id" | grep -qE '^[0-9]+(\.[0-9]+)?$' || return 1
  return 0
}

[ "$#" -ge 1 ] || {
  usage
  exit 2
}

# First pass: validate every ref before emitting anything (fail closed).
for ref in "$@"; do
  if ! valid_ref "$ref"; then
    echo "$prog: refusing malformed task ref '$ref'" >&2
    echo "$prog: expected <spec>/<id>, spec ^[a-z0-9][a-z0-9-]*$ id ^[0-9]+(\\.[0-9]+)?$" >&2
    exit 2
  fi
done

# Second pass: rotate the validated refs (the leading $# positional params)
# into the `--trailer "Planwright-Task: <ref>"` flag list git wants. Each
# iteration consumes the front ref and appends its flag to the back, so after
# $# rotations only the flags remain.
n=$#
i=0
while [ "$i" -lt "$n" ]; do
  ref=$1
  shift
  set -- "$@" --trailer "Planwright-Task: $ref"
  i=$((i + 1))
done

exec git interpret-trailers --if-exists addIfDifferent "$@"
