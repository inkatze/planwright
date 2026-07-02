#!/bin/sh
# planwright-commit-trailers.sh — stamp `Planwright-Task: <spec>/<id>` footer
# trailers onto a commit message (Task 2, REQ-C1.4, D-2).
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
#     subject line (D-2: discreet by design — footer only). Only the
#     `Planwright-Task` trailer is added; no Claude/co-author attribution is
#     introduced (the no-attribution rule is unaffected).
#   - `--if-exists addIfDifferent` makes a re-stamp idempotent: piping an
#     already-trailered message through again does not duplicate it.
#   - Each ref is grammar-validated before use (REQ-F1.1 discipline): spec
#     `^[a-z0-9][a-z0-9-]*$` (≤64 chars, the D-36 spec-id grammar), id
#     `^[0-9]+(\.[0-9]+)?$`. The id is the *single-task subset* of D-36's
#     branch `<id-or-ids>` grammar: a trailer names one task (D-2 — a bundle
#     carries one trailer line per task), so the bundle-range form (`3-4`) is
#     deliberately not accepted here. A malformed ref, a ref with an embedded
#     newline, or no ref at all is refused (exit 2) and nothing is emitted —
#     the value is never interpolated into the trailer.
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

# A literal newline, for the embedded-newline guard in valid_ref.
LF='
'

usage() {
  echo "usage: $prog <spec>/<id> [<spec>/<id> ...] < message" >&2
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
    # Never echo the candidate back: a malformed ref can carry terminal escapes
    # or a newline-injected forged log line, so echoing it verbatim is terminal/
    # log injection. The sibling validators (spec-validate.sh, spec-walkthrough.sh)
    # refuse the same spec-id grammar without echoing the candidate, and this
    # helper's own contract (REQ-F1.1) is "hostile input is refused, never
    # interpolated". The grammar hint below is enough to act on the refusal.
    echo "$prog: refusing a malformed task ref (does not match the expected grammar)" >&2
    echo "$prog: expected <spec>/<id>, spec ^[a-z0-9][a-z0-9-]*$ (≤64) id ^[0-9]+(\\.[0-9]+)?$" >&2
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
