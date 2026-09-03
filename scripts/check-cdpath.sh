#!/usr/bin/env bash
# check-cdpath.sh — CDPATH house-pattern guard.
#
# A shell script that resolves its own location with `dir="$(cd .. && pwd)"` is
# silently wrong for anyone who has CDPATH set: when `cd` finds the directory
# through a CDPATH entry it prints the resolved path, that echo lands inside
# the command substitution, and the variable ends up holding two lines. One
# line at the top of the file, `unset CDPATH`, fixes it.
#
# Two things make the omission worth a guard rather than review attention.
# `spec-walkthrough.sh` shipped through /polish convergence without the unset,
# so vigilance has already failed once. And the harness unsets CDPATH globally,
# which means an offending script passes every local and CI run and breaks only
# on the machine of whoever has it set — the environment hides its own bug.
#
# Scope is every shell file under scripts/, tests/, and githooks/, reached
# either by shebang or by an .sh suffix. Neither test alone is enough: the
# githooks/ hooks are extensionless, and the sourced libraries (echo-safety.sh,
# spec-parse.sh, release-lib.sh) carry a `# shellcheck shell=` line instead of
# a shebang. A sourced library is where a shared path-resolving helper would
# live, so leaving those unscanned would leave the likeliest offender unscanned.
#
# What counts as an offense: `cd` (or `pushd`, which consults CDPATH and echoes
# identically) as the first command inside a command substitution, in the
# `$(...)`, backtick, and `<(...)` forms, whether the `cd` sits on the opening
# line or on the line below it. The multi-line form matters because it is this
# repo's own house style for a long substitution.
#
# What clears a file: a top-level `unset CDPATH` (any spelling that names
# CDPATH, including `unset -v` and multi-name forms) or a top-level `CDPATH=`
# assignment. Heredoc bodies and full-line comments are not code, so an
# `unset CDPATH` inside one clears nothing — otherwise quoting the remedy in a
# usage message would exempt the script quoting it.
#
# Presence is checked, not position. A `cd` substitution that runs before the
# unset is still a bug, and this guard will not catch that one.
#
# Usage:
#   check-cdpath.sh [<root>]   scan the scope directories under <root>
#                              (default: the parent of this script's directory)
#   check-cdpath.sh --help | -h
#
# Exit codes: 0 clean, 1 an offending file, 2 usage or a broken enumeration.
# Anything that would make the scan cover less than it claims — an absent root
# or scope directory, an unreadable file, a `find` that fails partway, a scan
# reaching no files at all — is exit 2, never a clean report.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible.
set -u

LC_ALL=C
export LC_ALL

unset CDPATH

SCOPE_DIRS="scripts tests githooks"

self_dir="$(cd "$(dirname "$0")" && pwd -P)"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

# Display sanitizer for untrusted content headed for the terminal (echo
# discipline, doctrine/security-posture.md). Filenames and the root argument
# both reach stderr, and on a fork PR both are attacker-authored. The inline
# fallback keeps diagnostics safe when the shared helper cannot be sourced.
sanitize_printable() {
  _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237' 2>/dev/null) || _sp=''
  if [ -z "$_sp" ] && [ $# -ge 2 ]; then
    _sp=$2
  fi
  printf '%s' "$_sp"
}
if [ -r "$self_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$self_dir/echo-safety.sh"
fi

fail_closed() {
  echo "check-cdpath: $1" >&2
  exit 2
}

usage() {
  cat <<'EOF'
check-cdpath.sh — flag scripts that resolve paths through a cd command
substitution without a top-level `unset CDPATH`.

Usage:
  check-cdpath.sh [<root>]   scan the scope directories under <root>
                             (default: the parent of this script's directory)
  check-cdpath.sh --help | -h

Scanned: every file under the scope directories reached either by shebang or
by an .sh suffix, so both the extensionless githooks/ hooks and the sourced
shebang-less libraries are covered.

Flagged: `cd` or `pushd` as the first command inside a `$(...)`, backtick, or
`<(...)` substitution, including the form where the `cd` sits on the line below
the opening `$(`.

Cleared by: a top-level `unset CDPATH` (any spelling that names CDPATH) or a
top-level `CDPATH=` assignment. Heredoc bodies and full-line comments do not
count. Presence is checked, not position: an unset written after the
substitution still clears the file here, though it does not fix the bug.

Exit codes: 0 clean, 1 an offending file, 2 usage or a broken enumeration.

Fixing a flagged file: add `unset CDPATH` at column 0, near the top, before
anything resolves a path.

Regression-test convention: a script that resolves paths this way gets one test
that runs it under `CDPATH=.` and asserts the resolved path is still correct —
asserting the path itself, not merely a zero exit, since a corrupted path
usually fails later and for a different-looking reason. Testing under the
ambient environment proves nothing: the harness unsets CDPATH globally, and
that unset masks exactly the bug this guard exists to catch. `CDPATH=.` is the
smallest setting that reproduces it, because `cd` consults CDPATH for a bare
relative name like `foo` or `scripts/..` — though not for one written `./foo`,
`../foo`, or as an absolute path, all of which bypass CDPATH entirely.
EOF
}

case "${1:-}" in
  --help | -h)
    [ "$#" -eq 1 ] || fail_closed "--help takes no other arguments"
    usage
    exit 0
    ;;
  -*)
    fail_closed "unknown option: $(sanitize_printable "$1" "(unprintable)") (see --help)"
    ;;
esac

[ "$#" -le 1 ] || fail_closed "too many arguments (expected at most one root)"

root="${1:-$repo_root}"
safe_root="$(sanitize_printable "$root" "(unprintable path)")"
[ -d "$root" ] || fail_closed "root not found or not a directory: $safe_root"

missing=""
for dir in $SCOPE_DIRS; do
  [ -d "$root/$dir" ] || missing="$missing $dir"
done
[ -z "$missing" ] \
  || fail_closed "scope directories missing under $safe_root:$missing — the scan would cover less than it claims"

work="$(mktemp -d)" || fail_closed "could not create a temporary directory"
trap 'rm -rf "$work"' EXIT
: >"$work/all"

# Enumerate one scope directory at a time so a root containing whitespace or a
# glob character stays a single argument, and so a find that fails partway is
# caught instead of silently contributing nothing. -L follows symlinks: a
# symlinked script still runs, so it still has to be scanned.
for dir in $SCOPE_DIRS; do
  if ! find -L "$root/$dir" -type f -print0 >>"$work/all" 2>"$work/err"; then
    fail_closed "find failed under $safe_root/$dir: $(sanitize_printable "$(cat "$work/err")" "(unprintable)")"
  fi
done

# Select the shell files. The enumeration is NUL-delimited so a filename
# containing a newline survives it intact; such a name is then refused rather
# than skipped, because the file list awk reads is newline-delimited and a
# silently dropped file is the failure this guard exists to prevent.
: >"$work/list"
count=0
newline='
'
while IFS= read -r -d '' file; do
  rel="${file#"$root"/}"
  # Sanitizing is three forks, so it happens only on the paths that actually
  # reach the terminal, never once per enumerated file.
  case "$file" in
    *"$newline"*)
      fail_closed "filename contains a newline, refusing to scan: $(sanitize_printable "$rel" "(unprintable filename)")"
      ;;
  esac
  [ -r "$file" ] \
    || fail_closed "cannot read $(sanitize_printable "$rel" "(unprintable filename)") — the scan would cover less than it claims"
  first=""
  IFS= read -r first <"$file" 2>/dev/null || true
  case "$first" in
    '#!'*) ;;
    *) case "$file" in
      *.sh) ;;
      *) continue ;;
    esac ;;
  esac
  printf '%s\n' "$file" >>"$work/list"
  count=$((count + 1))
done <"$work/all"

[ "$count" -gt 0 ] \
  || fail_closed "no shell files found under $SCOPE_DIRS in $safe_root — a broken enumeration, not a clean tree"

# One awk pass over the whole list. A per-file state machine is what the
# multi-line substitution and the heredoc exclusion both need, and neither is
# expressible line-at-a-time. Files are opened by getline rather than through
# ARGV, so a name containing `=` or a leading `-` is read as a path and never
# as an awk variable assignment or option.
awk -v listfile="$work/list" '
  function scan(path,   line, tail, body, delim, heredoc, pending, badline, cleared, opened) {
    heredoc = ""; pending = 0; badline = 0; cleared = 0; opened = 0
    while ((getline line < path) > 0) {
      opened++
      sub(/\r$/, "", line)

      # Inside a heredoc body nothing is code: not an offense, not a remedy.
      if (heredoc != "") {
        body = line
        sub(/^[ \t]+/, "", body)
        if (body == heredoc) heredoc = ""
        continue
      }
      if (line ~ /^[ \t]*#/) continue
      if (line ~ /^[ \t]*$/) { pending = 0; continue }

      if (line ~ /^unset([ \t]+-[A-Za-z]+)*([ \t]+[A-Za-z_][A-Za-z0-9_]*)*[ \t]+CDPATH([ \t;&|)]|$)/) cleared = 1
      if (line ~ /^(export[ \t]+)?CDPATH=/) cleared = 1

      # cd opening a substitution on this line ...
      if (!badline && line ~ /(\$\(|`|<\()[ \t]*\\?(command[ \t]+|builtin[ \t]+)?(cd|pushd)([ \t]|$)/) badline = opened
      # ... or on the line after a substitution opened with nothing following it.
      if (!badline && pending && line ~ /^[ \t]*\\?(command[ \t]+|builtin[ \t]+)?(cd|pushd)([ \t]|$)/) badline = opened

      tail = line
      sub(/[ \t]+$/, "", tail)
      pending = (tail ~ /\$\($/) ? 1 : 0

      if (match(line, /<<-?[ \t]*['"'"'"]?[A-Za-z_][A-Za-z0-9_]*/)) {
        delim = substr(line, RSTART, RLENGTH)
        sub(/^<<-?[ \t]*/, "", delim)
        sub(/^['"'"'"]/, "", delim)
        heredoc = delim
      }
    }
    close(path)
    if (badline && !cleared) print path "\t" badline
    return opened
  }
  BEGIN {
    while ((getline path < listfile) > 0) scan(path)
  }
' >"$work/offenders" || fail_closed "the scan could not complete"

status=0
while IFS="$(printf '\t')" read -r file lineno; do
  [ -n "$file" ] || continue
  rel="${file#"$root"/}"
  echo "check-cdpath: $(sanitize_printable "$rel" "(unprintable filename)"):$lineno resolves a path through a cd command substitution but has no top-level 'unset CDPATH'" >&2
  status=1
done <"$work/offenders"

if [ "$status" -eq 0 ]; then
  echo "check-cdpath: clean ($count files)"
fi
exit "$status"
