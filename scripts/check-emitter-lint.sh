#!/bin/sh
# check-emitter-lint.sh — the emitter-output-lint guard
# (doctrine/guard-catalog.md, "Emitter output linting"). A script that emits
# YAML, Markdown or shell declares it in its header, `# Emits: markdown, yaml`,
# and some test under tests/ must lint that output through
# tests/lib/emitter-lint.sh: `lint_emitted <format> <script-name> <file>`.
# Unlinted, a generated artifact's defect surfaces only where it lands.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

me=check-emitter-lint

usage() {
  cat <<'EOF'
check-emitter-lint.sh — hold every declared emitter to a test that lints its output.

Usage:
  check-emitter-lint.sh [<root>]   check <root> (default: this script's repository)
  check-emitter-lint.sh --help

Declared: a `# Emits: <format>[, <format>...]` comment line among the first 40
lines of a scripts/*.sh file, each format one of markdown, yaml, shell.
Linted: a tests/*.sh line calling `lint_emitted <format> <script-name>`.
Fails on a declared format no test lints, on a lint_emitted call naming a
script or format nothing declares, and on an unknown format.
Exit codes: 0 clean, 1 a finding, 2 usage, or a root with no scripts/ or
tests/ directory or no declared emitter (a broken scan, not a clean tree).
EOF
}

fail_closed() {
  printf '%s: %s\n' "$me" "$1" >&2
  exit 2
}

case "${1:-}" in
  --help | -h)
    usage
    exit 0
    ;;
  -*) fail_closed "unknown option (see --help)" ;;
esac
[ "$#" -le 1 ] || fail_closed "too many arguments (expected at most one root)"
root=${1:-$(cd "$(dirname "$0")/.." && pwd -P)}
[ -d "$root/scripts" ] && [ -d "$root/tests" ] \
  || fail_closed "no scripts/ and tests/ directories under the root"

work=$(mktemp -d "${TMPDIR:-/tmp}/check-emitter-lint.XXXXXX") || fail_closed "could not create a temporary directory"
trap 'rm -rf "$work"' EXIT

# Declared pairs, one `<script>\t<format>` per line; an unknown format is a
# finding of its own, written with a leading `!`.
for f in "$root"/scripts/*.sh; do
  [ -f "$f" ] || continue
  [ -r "$f" ] || fail_closed "cannot read scripts/${f##*/}"
  awk -v name="${f##*/}" '
    NR > 40 { exit }
    /^# Emits:/ {
      list = $0
      sub(/^# Emits:[ \t]*/, "", list)
      n = split(list, fmts, /[ \t]*,[ \t]*/)
      for (k = 1; k <= n; k++) {
        if (fmts[k] ~ /^(markdown|yaml|shell)$/) print name "\t" fmts[k]
        else print "!" name "\t" fmts[k]
      }
    }
  ' "$f" >>"$work/declared" || fail_closed "could not read scripts/${f##*/}"
done
[ -s "$work/declared" ] || fail_closed "no script under scripts/ declares an # Emits: format, a broken scan rather than a clean tree"

# Linted pairs from the tests: `lint_emitted <format> <script>` as a call.
for t in "$root"/tests/*.sh; do
  [ -f "$t" ] || continue
  [ -r "$t" ] || fail_closed "cannot read tests/${t##*/}"
  awk '
    /^[ \t]*#/ { next }
    {
      line = $0
      while (match(line, /lint_emitted[ \t]+[a-z]+[ \t]+[A-Za-z0-9_.-]+/)) {
        call = substr(line, RSTART, RLENGTH)
        split(call, w, /[ \t]+/)
        print w[3] "\t" w[2]
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$t" >>"$work/linted" || fail_closed "could not read tests/${t##*/}"
done
: >>"$work/linted"

status=0
tab=$(printf '\t')
while IFS="$tab" read -r script fmt; do
  case $script in
    '!'*)
      printf '%s: scripts/%s declares an unknown format (markdown, yaml or shell)\n' "$me" "${script#!}" >&2
      status=1
      continue
      ;;
  esac
  if ! grep -qxF "$script$tab$fmt" "$work/linted"; then
    printf '%s: scripts/%s emits %s, but no test lints it (lint_emitted %s %s <file>)\n' \
      "$me" "$script" "$fmt" "$fmt" "$script" >&2
    status=1
  fi
done <"$work/declared"
sort -u "$work/linted" >"$work/linted.u"
while IFS="$tab" read -r script fmt; do
  [ -n "$script" ] || continue
  if ! grep -qxF "$script$tab$fmt" "$work/declared"; then
    printf '%s: a test lints %s output of %s, which scripts/%s does not declare\n' \
      "$me" "$fmt" "$script" "$script" >&2
    status=1
  fi
done <"$work/linted.u"
if [ "$status" -eq 0 ]; then
  printf '%s: clean (%s declared emitter formats, each linted)\n' "$me" "$(wc -l <"$work/declared" | tr -d ' ')"
fi
exit "$status"
