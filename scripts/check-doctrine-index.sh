#!/usr/bin/env bash
# check-doctrine-index.sh — the doctrine-index drift tether (guard-coverage
# Task 9; REQ-F1.1, REQ-H1.3, D-10).
#
# doctrine/README.md carries an index table: one row per doctrine doc, naming
# what it covers and its primary citations. That index is a restatement of the
# directory listing, so it drifts silently — a doc added without a row is
# invisible to anyone reading the index, and a row left behind by a deleted or
# renamed doc points at nothing. This check asserts the two sets are in
# **bijection**, both directions:
#
#   1. Every doctrine/*.md (excluding README.md itself) has an index row.
#   2. Every index row maps to a doctrine doc that exists, exactly once.
#
# Direction 2 is what a one-way "is it documented" check misses: a rename shows
# up here as both a stale row and an unindexed doc, and both are reported.
#
# Fail-closed posture (REQ-H1.3). Every input degeneracy exits non-zero rather
# than passing vacuously: a missing doctrine directory, a missing README, an
# index table whose header row cannot be found, an index table that parses to
# zero rows, an empty doctrine-doc set, and an index row whose link target is
# not a bare doctrine-doc basename.
#
# Usage: check-doctrine-index.sh [<doctrine-dir>]
#   <doctrine-dir> defaults to the repo's doctrine/ directory (the CI entry
#   point, wired as the `check:doctrine-index` mise task).
#
# Index-table recognition: the table is located by its header row, whose first
# cell is `Doc`; the table ends at the first line that is not a table row. Each
# row's first cell must hold a markdown link whose target is a bare
# `<name>.md`. A table whose header is renamed stops parsing and fails closed,
# so the shape is part of the contract rather than a best-effort guess.
#
# Exit codes: 0 the bijection holds; 1 the bijection is broken (an unindexed
# doc, a stale row, or a duplicate row); 2 usage error or a fail-closed input
# degeneracy.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
set -u

# Pin the C locale so the bracket expressions below mean exactly their ASCII
# range on every host (mirrors the sibling checks).
LC_ALL=C
export LC_ALL

# A user CDPATH would make cd echo into the command substitution below and
# corrupt the repo-root derivation.
unset CDPATH

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

# Display sanitizer for parsed content (echo discipline,
# doctrine/security-posture.md). A byte-identical inline fallback is defined
# first so a diagnostic is never unable to strip control bytes; the canonical
# shared helper overrides it when the sibling resolves.
sanitize_printable() {
  _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237' 2>/dev/null) || _sp=''
  if [ -z "$_sp" ] && [ $# -ge 2 ]; then
    _sp=$2
  fi
  printf '%s' "$_sp"
}
if [ -r "$repo_root/scripts/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$repo_root/scripts/echo-safety.sh"
fi

fail_closed() {
  echo "check-doctrine-index: $1" >&2
  exit 2
}

doctrine_dir="${1:-$repo_root/doctrine}"
safe_dir="$(sanitize_printable "$doctrine_dir" "(unprintable path)")"

[ -d "$doctrine_dir" ] || fail_closed "doctrine directory not found: $safe_dir"

readme="$doctrine_dir/README.md"
[ -f "$readme" ] \
  || fail_closed "index file not found: $safe_dir/README.md is the doctrine index, and its absence must not disable this check"

# ---------------------------------------------------------------------------
# The doctrine-doc set: every *.md in the directory except the index itself.
# Both sets travel as space-separated lists, so each basename is held to the
# REQ-A1.8 identifier grammar first — an unvalidated name carrying a space
# would word-split into entries that exist nowhere, and the resulting failure
# would name files nobody can find.
# ---------------------------------------------------------------------------
docs=""
for path in "$doctrine_dir"/*.md; do
  [ -f "$path" ] || continue
  base="${path##*/}"
  [ "$base" = "README.md" ] && continue
  case "${base%.md}" in
    '' | [!a-z0-9]* | *[!a-z0-9-]*)
      fail_closed "doctrine filename is outside the identifier grammar: $(sanitize_printable "$base" "(unprintable filename)")"
      ;;
  esac
  docs="$docs $base"
done

[ -n "$docs" ] \
  || fail_closed "no doctrine docs found in $safe_dir (a directory that globs to zero *.md files is a broken enumeration, not a clean tree)"

# ---------------------------------------------------------------------------
# The index rows: the body rows of the table whose header's first cell is
# `Doc`. Exit 3 from awk means the header was never found (unparseable table).
# ---------------------------------------------------------------------------
index_rows="$(awk '
  {
    line = $0
    sub(/^[ \t]+/, "", line)
    if (line !~ /^\|/) { intbl = 0; next }
    if (!intbl) {
      if (line ~ /^\|[ \t]*Doc[ \t]*\|/) { intbl = 1; found = 1 }
      next
    }
    if (line ~ /^\|[ \t]*:?-+:?[ \t]*\|/) next
    print line
  }
  END { if (!found) exit 3 }
' "$readme")"
[ "$?" -ne 3 ] \
  || fail_closed "could not parse the index table in $safe_dir/README.md (no header row whose first cell is 'Doc')"

[ -n "$index_rows" ] \
  || fail_closed "the index table in $safe_dir/README.md parsed to zero rows"

# Each row's first cell must be a markdown link whose target is a bare
# `<name>.md`, matching the REQ-A1.8 identifier charset.
indexed=""
while IFS= read -r row; do
  [ -n "$row" ] || continue
  cell="${row#|}"
  cell="${cell%%|*}"
  target="$(printf '%s' "$cell" | sed -n 's/.*\[[^]]*\](\([^)]*\)).*/\1/p')"
  [ -n "$target" ] \
    || fail_closed "index row has no markdown link in its first cell: $(sanitize_printable "$row" "(unprintable row)")"
  case "$target" in
    *.md) stem="${target%.md}" ;;
    *) stem="" ;;
  esac
  case "$stem" in
    '' | [!a-z0-9]* | *[!a-z0-9-]*)
      fail_closed "index row target is not a bare doctrine-doc basename: $(sanitize_printable "$target" "(unprintable target)")"
      ;;
  esac
  indexed="$indexed $target"
done <<EOF
$index_rows
EOF

status=0

# Direction 1: every doc has exactly one row.
for doc in $docs; do
  count=0
  for row_doc in $indexed; do
    [ "$row_doc" = "$doc" ] && count=$((count + 1))
  done
  if [ "$count" -eq 0 ]; then
    echo "check-doctrine-index: doctrine doc '$doc' has no row in README.md" >&2
    status=1
  elif [ "$count" -gt 1 ]; then
    echo "check-doctrine-index: doctrine doc '$doc' has $count rows in README.md (the index is one row per doc)" >&2
    status=1
  fi
done

# Direction 2: every row maps to a doc that exists.
for row_doc in $indexed; do
  found=0
  for doc in $docs; do
    if [ "$row_doc" = "$doc" ]; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "check-doctrine-index: README.md indexes '$row_doc', which is not a doc in $safe_dir (a stale row for a deleted or renamed doc)" >&2
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  doc_count=0
  for doc in $docs; do
    doc_count=$((doc_count + 1))
  done
  echo "check-doctrine-index: $doc_count doctrine docs, each with exactly one index row"
fi
exit "$status"
