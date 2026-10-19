#!/bin/sh
# check-script-invocation.sh — no skill instruction runs a bash-shebanged
# script through `sh`.
#
# Called by its path, a script gets the interpreter its shebang names. `sh
# <path>` overrides that with whatever /bin/sh is, and where that is dash
# (Debian, Ubuntu) a bash-only script fails on its first bashism: a catalog
# walk degrades, a budget audit fails, with a syntax error that names the
# script rather than the invocation. The rule lives in
# doctrine/plugin-script-invocation.md (*Invoke by the shebang*); this is its
# mechanical half.
#
# THE SHEBANG IS THE DECLARATION. A top-level scripts/*.sh whose first line is
# a `#!` naming bash is bash-only. Sourced libraries carry no shebang and are
# never run, so they are not compared against.
#
# WHAT COUNTS AS AN OFFENSE. In any .md file under skills/ or doctrine/, an
# `sh` command word (bare, or a path ending /sh such as /bin/sh) whose
# operand, past any options, `--`, and a `<` redirect, names
# `scripts/<name>` for a bash-shebanged <name>. The operand may be quoted, a
# variable, or a `<placeholder>` such as `<root>/scripts/<name>`. Not
# offenses: `sh -c <string>` (the string runs the script by path), a call by
# path, a call through `bash`. Not read: a script piped into `sh` on stdin,
# and an invocation split by a backslash-newline.
#
# FAILS CLOSED on anything that would narrow the scan: no scripts/, no
# shebanged script, no instruction file, a file it cannot read, and a symbolic
# link or a name containing a newline under scripts/, skills/, or doctrine/
# (the lists below are newline-separated, so such a name could forge an entry,
# and a link's target would go unscanned).
#
# Untrusted input: the scanned files and their names are PR-controllable.
# awk reads them as data and takes every path through ENVIRON or a list file,
# never its command line; nothing is executed or interpolated into program
# text, and output reaches the terminal with control bytes stripped.
#
# Usage:
#   check-script-invocation.sh [--repo-root <dir>]   default: this script's parent
#   check-script-invocation.sh --help | -h
#
# Exit codes: 0 clean, 1 an instruction runs a bash script through sh, 2 usage
# or a scan that could not cover what it claims.
#
# POSIX sh + awk; no fish/mise/tmux.
set -u

LC_ALL=C
export LC_ALL

unset CDPATH

self_dir="$(cd "$(dirname "$0")" && pwd -P)"

strip_controls() {
  tr -d '\000-\010\013-\037\177\200-\237'
}

fail_closed() {
  printf 'check-script-invocation: %s\n' "$1" | strip_controls >&2
  exit 2
}

usage() {
  cat <<'EOF'
check-script-invocation.sh — no skill instruction runs a bash-shebanged script
through `sh`.

Usage:
  check-script-invocation.sh [--repo-root <dir>]   default: this script's parent
  check-script-invocation.sh --help | -h

Scans the .md files under skills/ and doctrine/ for an `sh` invocation whose
operand is a scripts/*.sh whose shebang names bash. Fix a flagged line by
calling the script by its path, or through the interpreter its shebang names.

Exit codes: 0 clean, 1 a flagged invocation, 2 usage or a scan that could not
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
trap 'exit 130' INT
trap 'exit 143' TERM

nl='
'
for d in scripts skills doctrine; do
  [ -e "$root/$d" ] || continue
  find "$root/$d" \( -name "*$nl*" -o -type l \) -print >"$work/odd" \
    || fail_closed "cannot list $root/$d"
  [ ! -s "$work/odd" ] \
    || fail_closed "a symbolic link or a name containing a newline under $d/: $(head -n 1 "$work/odd")"
done

# Lists go through files rather than pipes so a failing `find` is seen: a pipe
# would hand awk a short list and exit 0.
find "$root/scripts/." ! -name . -prune -type f -name '*.sh' >"$work/scripts" \
  || fail_closed "cannot list $root/scripts"
: >"$work/docs"
for d in skills doctrine; do
  [ -d "$root/$d" ] || continue
  find "$root/$d" -type f -name '*.md' >>"$work/docs" \
    || fail_closed "cannot list $root/$d"
done
sort -o "$work/docs" "$work/docs" || fail_closed "cannot sort the instruction list"

: >"$work/err" || fail_closed "cannot write to $work"
rc=0
CSI_ROOT="$root/" CSI_SCRIPTS="$work/scripts" CSI_DOCS="$work/docs" \
  CSI_ERR="$work/err" CSI_SUMMARY="$work/summary" awk '
  function fatal(msg) {
    print "check-script-invocation: " msg > errfile
    failed = 1
    exit
  }
  BEGIN {
    root = ENVIRON["CSI_ROOT"]
    errfile = ENVIRON["CSI_ERR"]
    list = ENVIRON["CSI_SCRIPTS"]
    while ((r = (getline f < list)) > 0) {
      first = ""
      if ((getline first < f) < 0) fatal("cannot read " f)
      close(f)
      sub(/\r$/, "", first)
      if (first !~ /^#!/) continue
      shebanged++
      if (first ~ /^#!(.*[\/ \t])?bash([ \t]|$)/) {
        name = f
        sub(/.*\//, "", name)
        bash[name] = 1
        nbash++
      }
    }
    if (r < 0) fatal("cannot read the script list")
    close(list)
    if (!shebanged) fatal("no shebanged scripts/*.sh under " root)
    list = ENVIRON["CSI_DOCS"]
    while ((r = (getline f < list)) > 0) {
      if (substr(f, 1, length(root)) != root) fatal("listed file outside the root: " f)
      if ((getline probe < f) < 0) fatal("cannot read " f)
      close(f)
      ARGV[ARGC++] = f
      ndocs++
    }
    if (r < 0) fatal("cannot read the instruction list")
    close(list)
    if (!ndocs) fatal("no .md file under skills/ or doctrine/ in " root)
  }
  FNR == 1 { rel = substr(FILENAME, length(root) + 1) }
  /sh/ {
    line = $0
    sub(/\r$/, "", line)
    n = split(line, w, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      # An sh command word: the token ends in sh, preceded by nothing, a
      # path ending in /, or punctuation that opens a command.
      if (w[i] !~ /(^|[^A-Za-z0-9_.\/-])((\/[A-Za-z0-9_.-]+)*\/)?sh$/) continue
      skip = 0
      op = ""
      for (j = i + 1; j <= n; j++) {
        a = w[j]
        if (a == "--" || a == "<") continue
        if (a ~ /^[-+]o$/) { j++; continue }
        if (a ~ /^[-+][A-Za-z]+$/) {
          if (a ~ /^-[A-Za-z]*c/) skip = 1
          if (skip) break
          continue
        }
        op = a
        break
      }
      if (skip || op == "") continue
      if (op !~ /^<[A-Za-z0-9_-]+>/) sub(/^</, "", op)
      gsub(/[\042\047]/, "", op)
      sub(/[`;|&].*$/, "", op)
      sub(/[).,:]+$/, "", op)
      if (op !~ /(^|\/)scripts\/[^\/]+$/) continue
      name = op
      sub(/.*\//, "", name)
      if (name in bash) {
        printf "check-script-invocation: %s:%d: runs scripts/%s through sh, but its shebang names bash; call it by its path or through bash\n", rel, FNR, name
        found++
      }
    }
  }
  END {
    if (failed) exit 2
    print ndocs, nbash > ENVIRON["CSI_SUMMARY"]
    exit found ? 1 : 0
  }
' </dev/null >"$work/out" 2>"$work/awkerr" || rc=$?

strip_controls <"$work/out" >&2
cat "$work/err" "$work/awkerr" | strip_controls >&2
case "$rc" in
  0) ;;
  1)
    n=$(grep -c '' "$work/out") || n=0
    printf 'check-script-invocation: %s flagged invocation(s)\n' "$n" >&2
    exit 1
    ;;
  *) fail_closed "the scan did not complete (awk exit $rc)" ;;
esac
read -r ndocs nbash <"$work/summary" || fail_closed "the scan wrote no summary"
printf 'check-script-invocation: clean (%s instruction files, %s bash scripts)\n' \
  "$ndocs" "$nbash"
