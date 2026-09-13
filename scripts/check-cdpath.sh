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
# CDPATH, including `unset -v` and multi-name forms) or a top-level assignment
# of an EMPTY CDPATH. `CDPATH=.:/var` is the bug rather than the remedy, so it
# clears nothing. Heredoc bodies and full-line comments are not code either, so
# an `unset CDPATH` inside one clears nothing — otherwise quoting the remedy in
# a usage message would exempt the script quoting it.
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
top-level assignment of an empty CDPATH. A non-empty `CDPATH=...` is the bug,
not the remedy. Heredoc bodies and full-line comments do not count. Presence is
checked, not position: an unset written after the substitution still clears the
file here, though it does not fix the bug.

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

# Explicit template (the house pattern, see scripts/check-hook-contracts.sh): a
# bare `mktemp -d` relies on a default template BSD mktemp does not supply, so
# it fails outright on the macOS half of the support bar this script claims.
work="$(mktemp -d "${TMPDIR:-/tmp}/check-cdpath.XXXXXX")" \
  || fail_closed "could not create a temporary directory"
trap 'rm -rf "$work"' EXIT
: >"$work/all"

# Enumerate one scope directory at a time so a root containing whitespace or a
# glob character stays a single argument, and so a find that fails partway is
# caught instead of silently contributing nothing. The walk is physical and
# takes symlinks as leaves rather than following them: a symlinked script still
# runs, so it still has to be scanned, but descending through a symlinked
# directory would walk a tree outside the root and report its files as if they
# lived here. Those are refused below instead.
for dir in $SCOPE_DIRS; do
  if ! find -P "$root/$dir" \( -type f -o -type l \) -print0 >>"$work/all" 2>"$work/err"; then
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
tab="$(printf '\t')"
while IFS= read -r -d '' file; do
  rel="${file#"$root"/}"
  # Sanitizing is three forks, so it happens only on the paths that actually
  # reach the terminal, never once per enumerated file.
  # A newline or a tab in a filename would be swallowed by the newline-
  # delimited file list or by the tab-delimited offender records below.
  # Refusing is the fail-closed answer; silently skipping is not.
  case "$file" in
    *"$newline"* | *"$tab"*)
      fail_closed "filename contains a newline or tab, refusing to scan: $(sanitize_printable "$rel" "(unprintable filename)")"
      ;;
  esac
  # A symlinked directory has no honest traversal: following it leaves the
  # root, and skipping it covers less than the scan claims. -r would not catch
  # it either, since the directory behind it reads fine.
  if [ -L "$file" ] && [ -d "$file" ]; then
    fail_closed "symlinked directory in the scan scope, refusing to follow: $(sanitize_printable "$rel" "(unprintable filename)")"
  fi
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
  function scan(path,   line, tail, body, delim, heredoc, heredoc_dash, pending, badline, cleared, opened, r, pre, dq, sq, dash) {
    heredoc = ""; heredoc_dash = 0; pending = 0; badline = 0; cleared = 0; opened = 0
    # getline returns -1 when the file cannot be opened or read, which is not
    # end-of-input. Treating the two alike would silently clear a file the scan
    # never saw, reachable as a TOCTOU race against the readability check the
    # selection loop already made.
    while ((r = (getline line < path)) > 0) {
      opened++
      sub(/\r$/, "", line)

      # Inside a heredoc body nothing is code: not an offense, not a remedy.
      # `<<-` strips leading tabs from the terminator; plain `<<` requires an
      # exact match. Stripping spaces for both would close the body early.
      if (heredoc != "") {
        body = line
        if (heredoc_dash) sub(/^\t+/, "", body)
        if (body == heredoc) heredoc = ""
        continue
      }
      # Neither a comment nor a blank line closes an open substitution, so
      # neither clears `pending`: `root=$(` followed by an empty line and then
      # `cd ..` is one substitution, and resetting here would let the blank
      # line hide it.
      if (line ~ /^[ \t]*#/) continue
      if (line ~ /^[ \t]*$/) continue

      if (line ~ /^unset([ \t]+-[A-Za-z]+)*([ \t]+[A-Za-z_][A-Za-z0-9_]*)*[ \t]+CDPATH([ \t;&|)]|$)/) cleared = 1
      # Only an EMPTY assignment counts. `CDPATH=.:/var` is the bug, not a
      # remedy, and must never read as one.
      if (line ~ /^(export[ \t]+)?CDPATH=[ \t]*(;|$)/) cleared = 1

      # cd opening a substitution on this line ...
      if (!badline && line ~ /(\$\(|`|<\()[ \t]*[({]?[ \t]*\\?(command[ \t]+|builtin[ \t]+)?(cd|pushd)([ \t]|$)/) badline = opened
      # ... or on the line after a substitution opened with nothing following it.
      if (!badline && pending && line ~ /^[ \t]*[({]?[ \t]*\\?(command[ \t]+|builtin[ \t]+)?(cd|pushd)([ \t]|$)/) badline = opened

      # An opening `$(` still counts as opening when a line continuation or a
      # trailing comment follows it, both of which are ordinary in a long
      # substitution.
      tail = line
      sub(/[ \t]+$/, "", tail)
      pending = (tail ~ /\$\([ \t]*\\?[ \t]*(#.*)?$/) ? 1 : 0

      # The delimiter charset has to cover what bash accepts, not just word
      # characters: `<<EOF-1` truncated to `EOF` would never see its terminator
      # and would swallow the rest of the file, and `<<\DOC` would not register
      # as a heredoc at all, letting its body clear the file.
      if (match(line, /<<-?[ \t]*\\?['"'"'"]?[A-Za-z0-9_.+-]+/)) {
        # `echo "<<EOF"` is a string, not a heredoc, and believing otherwise
        # would swallow the rest of the file. Odd quote parity before the
        # operator means it sits inside a string.
        pre = substr(line, 1, RSTART - 1)
        dq = gsub(/"/, "\"", pre)
        sq = gsub(/'"'"'/, "&", pre)
        if (dq % 2 == 0 && sq % 2 == 0) {
          delim = substr(line, RSTART, RLENGTH)
          dash = (delim ~ /^<<-/)
          sub(/^<<-?[ \t]*/, "", delim)
          sub(/^\\/, "", delim)
          sub(/^['"'"'"]/, "", delim)
          heredoc = delim
          heredoc_dash = dash
        }
      }
    }
    close(path)
    if (r < 0) { print "!\t" path; return 0 }
    if (badline && !cleared) print path "\t" badline
    return opened
  }
  BEGIN {
    while ((lr = (getline path < listfile)) > 0) scan(path)
    # An unreadable list is not an empty one; reporting clean over it would be
    # the same vacuous pass the scan-side check refuses.
    if (lr < 0) print "!\t" listfile
  }
' >"$work/offenders" || fail_closed "the scan could not complete"

status=0
while IFS="$(printf '\t')" read -r file lineno; do
  [ -n "$file" ] || continue
  if [ "$file" = "!" ]; then
    fail_closed "could not read $(sanitize_printable "${lineno#"$root"/}" "(unprintable filename)") during the scan — the scan would cover less than it claims"
  fi
  rel="${file#"$root"/}"
  echo "check-cdpath: $(sanitize_printable "$rel" "(unprintable filename)"):$lineno resolves a path through a cd command substitution but has no top-level 'unset CDPATH'" >&2
  status=1
done <"$work/offenders"

if [ "$status" -eq 0 ]; then
  echo "check-cdpath: clean ($count files)"
fi
exit "$status"
