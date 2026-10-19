#!/bin/sh
# check-script-invocation.sh — no skill instruction runs a bash-shebanged
# script through `sh`.
#
# Called by its path, a script gets the interpreter its shebang names. `sh
# <path>` overrides that with whatever /bin/sh is (dash on Debian and Ubuntu,
# bash in POSIX mode on macOS), and a bash-only script fails there on its
# first bashism: a catalog walk degrades, a budget audit fails, with a syntax
# error that names the script rather than the invocation. The rule lives in
# doctrine/plugin-script-invocation.md (*Invoke by the shebang*); this is its
# mechanical half.
#
# THE SHEBANG IS THE DECLARATION. A scripts/*.sh whose first line is a `#!`
# naming bash is bash-only. Sourced libraries carry no shebang and are never
# run, so they are not compared against.
#
# WHAT COUNTS AS AN OFFENSE. In skills/**/*.md and doctrine/*.md, an `sh`
# command word (bare, /bin/sh, /usr/bin/sh, or after `env`) followed, past any
# flags, by an operand whose basename is a bash-shebanged script. `sh -c
# <string>` is not one: the string runs the script by path. Running a script
# by path, or through `bash`, is what the rule asks for.
#
# Untrusted input: the scanned files are PR-controllable. They are read by awk
# as data; nothing from them is executed or interpolated into program text,
# and paths reach output with control bytes stripped.
#
# Usage:
#   check-script-invocation.sh [--repo-root <dir>]   default: this script's parent
#   check-script-invocation.sh --help | -h
#
# Exit codes: 0 clean, 1 an instruction runs a bash script through sh, 2 usage
# or a scan that could not cover what it claims (no scripts/ with a shebanged
# script, no instruction file to scan).
#
# POSIX sh + awk; no fish/mise/tmux.
set -u

LC_ALL=C
export LC_ALL

unset CDPATH

self_dir="$(cd "$(dirname "$0")" && pwd -P)"

fail_closed() {
  printf 'check-script-invocation: %s\n' "$1" | tr -d '\000-\010\013-\037\177' >&2
  exit 2
}

usage() {
  cat <<'EOF'
check-script-invocation.sh — no skill instruction runs a bash-shebanged script
through `sh`.

Usage:
  check-script-invocation.sh [--repo-root <dir>]   default: this script's parent
  check-script-invocation.sh --help | -h

Scans skills/**/*.md and doctrine/*.md for an `sh` invocation whose operand is
a scripts/*.sh whose shebang names bash. Fix a flagged line by calling the
script by its path, or through the interpreter its shebang names.

Exit codes: 0 clean, 1 a flagged instruction, 2 usage or a scan that could not
cover what it claims.
EOF
}

root="$self_dir/.."
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root)
      [ $# -ge 2 ] || {
        usage >&2
        exit 2
      }
      root="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[ -d "$root" ] || fail_closed "root is not a directory: $root"
root="$(cd "$root" && pwd -P)" || fail_closed "cannot resolve the root"
[ -d "$root/scripts" ] || fail_closed "no scripts/ under $root"

work="$(mktemp -d "${TMPDIR:-/tmp}/check-script-invocation.XXXXXX")" \
  || fail_closed "cannot create a temporary directory"
trap 'rm -rf "$work"' EXIT

# Lists go through files rather than pipes so a failing `find` is seen: a pipe
# would hand awk a short list and exit 0.
find "$root/scripts" -type f -name '*.sh' >"$work/scripts" \
  || fail_closed "cannot list $root/scripts"
: >"$work/docs"
if [ -d "$root/skills" ]; then
  find "$root/skills" -type f -name '*.md' >>"$work/docs" \
    || fail_closed "cannot list $root/skills"
fi
if [ -d "$root/doctrine" ]; then
  find "$root/doctrine" -type f -name '*.md' >>"$work/docs" \
    || fail_closed "cannot list $root/doctrine"
fi
sort -o "$work/docs" "$work/docs" || fail_closed "cannot sort the instruction list"

shebanged=0
: >"$work/bash"
while IFS= read -r f; do
  IFS= read -r first <"$f" || first=''
  case "$first" in
    '#!'*) shebanged=$((shebanged + 1)) ;;
    *) continue ;;
  esac
  # A word `bash` in the interpreter line: /bin/bash, /usr/bin/env bash,
  # env -S bash -e. Not bashful-sh or a path merely containing "bash".
  case " ${first#??} " in
    *[/\ ]bash[\ ]*) printf '%s\n' "${f##*/}" >>"$work/bash" ;;
  esac
done <"$work/scripts"
[ "$shebanged" -gt 0 ] || fail_closed "no shebanged scripts/*.sh under $root"
docs=$(grep -c '' "$work/docs") || docs=0
[ "$docs" -gt 0 ] || fail_closed "no skills/**/*.md or doctrine/*.md under $root"

rc=0
awk -v root="$root/" -v bashlist="$work/bash" -v doclist="$work/docs" '
  BEGIN {
    while ((getline name < bashlist) > 0) bash[name] = 1
    close(bashlist)
    # File names come from a list, not the command line, so no word
    # splitting or globbing ever touches them.
    while ((getline name < doclist) > 0) ARGV[ARGC++] = name
    close(doclist)
    # An sh command word: not preceded by a word, path, or dotted character,
    # optionally /bin/ or /usr/bin/, then blanks.
    cmd = "(^|[^A-Za-z0-9_./-])((/usr)?/bin/)?sh[ \t]+"
  }
  FNR == 1 { rel = substr(FILENAME, 1, length(root)) == root ? substr(FILENAME, length(root) + 1) : FILENAME }
  {
    line = $0
    while (match(line, cmd)) {
      rest = substr(line, RSTART + RLENGTH)
      line = rest
      skip = 0
      while (match(rest, /^-[A-Za-z]+[ \t]+/)) {
        if (substr(rest, 2, RLENGTH - 1) ~ /c/) skip = 1
        rest = substr(rest, RLENGTH + 1)
      }
      if (skip) continue
      sub(/^["\047]+/, "", rest)
      if (!match(rest, /^[^ \t"\047`;|&)<>]+/)) continue
      operand = substr(rest, 1, RLENGTH)
      base = operand
      sub(/.*\//, "", base)
      if (base in bash) {
        printf "check-script-invocation: %s:%d: runs scripts/%s through sh, but its shebang names bash; call it by its path or through bash\n", rel, FNR, base
        found++
      }
    }
  }
  END { exit found ? 1 : 0 }
' </dev/null >"$work/out" 2>"$work/err" || rc=$?

tr -d '\000-\010\013-\037\177' <"$work/out" >&2
case "$rc" in
  0) ;;
  1)
    n=$(grep -c '' "$work/out") || n=0
    printf 'check-script-invocation: %s flagged instruction(s)\n' "$n" >&2
    exit 1
    ;;
  *)
    tr -d '\000-\010\013-\037\177' <"$work/err" >&2
    fail_closed "awk failed scanning the instruction files (exit $rc)"
    ;;
esac
printf 'check-script-invocation: clean (%s instruction files, %s bash scripts)\n' \
  "$docs" "$(grep -c '' "$work/bash" || :)"
