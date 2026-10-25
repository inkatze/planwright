#!/bin/sh
# check-entry-points.sh — hold every script entry point to the contract its
# recorded fixture froze, so a migration that swaps an implementation behind
# the path cannot change what a caller sees.
#
# ENTRY POINTS. Every script the partition (scripts/substrate-partition.sh)
# reports with a `git`, `githook`, `hook`, or `skill` caller: what a tracked
# git hook, a hook registration, or a skill body names.
#
# FIXTURES. One directory per entry point under tests/fixtures/entry-points/,
# at the entry point's repository path (tests/fixtures/entry-points/scripts/
# x.sh/), holding:
#   args     the arguments, one per line (an empty file passes none)
#   stdin    optional; the bytes fed on stdin (absent: /dev/null)
#   stdout   the exact stdout bytes
#   exit     the exit code
#   stderr   the stderr class: `empty`, or `match <ERE>` that some line of
#            stderr matches
# A directory holding an `exit` file is a fixture.
#
# RUN. Each entry point runs by its path, so its execute bit is part of the
# contract, from the root of a read-only copy of the tree (every top-level
# entry but .git, .claude, and tests), with a clean environment: PATH kept,
# HOME and TMPDIR fresh and empty per run, LC_ALL=C, git confined to the copy,
# and the run bounded by scripts/bounded-run.sh. A fixture is chosen to be
# deterministic and to change nothing: a usage-error or help path, or a hook
# fed a recorded payload. Nothing outside the copy and the sandbox is written.
#
# FINDINGS, each printed and failing the run:
#   - an entry point with no fixture;
#   - a fixture whose entry point is gone from the tree (removed), or is no
#     longer an entry point (the fixture is stale and goes with it);
#   - an entry point that is not executable, or whose run differs from its
#     fixture in exit code, stdout bytes, or stderr class;
#   - a run exiting with the reserved fetch-failure code below, recorded or
#     not: a shim that could not fetch or verify its artifact never meets its
#     stdout contract;
#   - a shim (a layer script carrying a `# planwright-shim-target: <path>`
#     line naming its delegation target by repository path) that the partition
#     flags, or whose target is a layer script the partition flags: no flagged
#     script is migrated.
#
# RECORD. `--record <path> [--stdin <file>] [-- <arg>...]` captures a fixture
# for an entry point from the current implementation: it runs twice, in two
# fresh sandboxes, and refuses a run that differs between them, times out,
# ends on a signal, or exits with the reserved code. The stderr class written
# is the first stderr line, escaped and anchored; review it before committing,
# and loosen it where the line carries text the script does not own.
#
# Usage: check-entry-points.sh [--repo-root <dir>] [--partition <file>]
#        check-entry-points.sh [--repo-root <dir>] [--partition <file>]
#          --record <path> [--stdin <file>] [-- <arg>...]
# --partition reads a partition already computed instead of running it.
# Exit codes: 0 clean (or recorded); 1 a finding (each printed); 2 usage
# error; 5 fail-closed (the partition failing or malformed, a malformed
# fixture, a fixture path outside the layer's name grammar, the sandbox not
# building, or a recording refused); 128 plus the signal number on HUP, INT
# or TERM.
#
# POSIX sh on the macOS + Linux support bar. All input is data.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=check-entry-points
# The one code every D-10 shim exits with when its artifact cannot be fetched
# or verified (REQ-E1.2). The shim library reuses this value; changing it
# changes what callers already distinguish.
reserved_fetch_failure=69
run_bound=60

script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
repo_root=$(cd "$script_dir/.." && pwd -P) || exit 2

usage() {
  printf '%s\n' "usage: check-entry-points.sh [--repo-root <dir>] [--partition <file>] [--record <path> [--stdin <file>] [-- <arg>...]]" >&2
  exit 2
}

partition="" record="" record_stdin=""
while [ "$#" -gt 0 ]; do
  case $1 in
    --repo-root | --partition | --record | --stdin)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage
      case $1 in
        --repo-root) repo_root=$2 ;;
        --partition) partition=$2 ;;
        --record) record=$2 ;;
        --stdin) record_stdin=$2 ;;
      esac
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *) usage ;;
  esac
done
[ "$#" -eq 0 ] || [ -n "$record" ] || usage
[ -z "$record_stdin" ] || [ -n "$record" ] || usage

fail_closed() {
  printf '%s\n' "$me: $1; failing closed rather than passing" >&2
  exit 5
}

case $repo_root in -*) repo_root=./$repo_root ;; esac
repo_root=$(cd "$repo_root" && pwd -P) || fail_closed "the repository root does not resolve"
fixtures=$repo_root/tests/fixtures/entry-points
bounded=$script_dir/bounded-run.sh
[ -r "$bounded" ] || fail_closed "broken install: bounded-run.sh is missing or not readable"

work=$(mktemp -d "${TMPDIR:-/tmp}/check-entry-points.XXXXXX") || fail_closed "mktemp -d failed"
[ -n "$work" ] && [ -d "$work" ] || fail_closed "mktemp -d produced no directory"
work=$(cd "$work" && pwd -P) || fail_closed "the work directory does not resolve"
# The sandbox trees are read-only, so they need write access back to go.
trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -n "$partition" ]; then
  [ -f "$partition" ] && [ -r "$partition" ] || fail_closed "the partition file is unreadable"
  cp "$partition" "$work/partition" || fail_closed "cannot read the partition file"
else
  /bin/sh "$script_dir/substrate-partition.sh" --repo-root "$repo_root" >"$work/partition"
  rc=$?
  [ "$rc" -gt 128 ] && exit "$rc"
  [ "$rc" -eq 0 ] || fail_closed "the partition exited $rc"
fi
expected_header=$(printf 'path\ttier\tflag\tcallers\tmutation\tprofile\tunresolved')
IFS= read -r header <"$work/partition" || header=""
[ "$header" = "$expected_header" ] || fail_closed "the partition's header is not the one this guard reads"

# A layer path is a relative path of plain name characters; anything else
# could escape the fixture root or the copy.
valid_path() {
  case $1 in
    '' | /* | *//* | */ | *[!A-Za-z0-9._/-]*) return 1 ;;
    . | ./* | */. | */./* | .. | ../* | */.. | */../*) return 1 ;;
  esac
  return 0
}

awk -F '\t' 'NR > 1 && $4 ~ /(^|,)(git|githook|hook|skill)(,|$)/ { print $1 }' \
  "$work/partition" | sort -u >"$work/entry-points" || fail_closed "cannot read the partition"
awk -F '\t' 'NR > 1 && $3 != "-" { print $1 }' "$work/partition" | sort -u >"$work/flagged" \
  || fail_closed "cannot read the partition"
[ -s "$work/entry-points" ] || fail_closed "the partition names no entry point"
while IFS= read -r ep; do
  valid_path "$ep" || fail_closed "the partition names an entry point outside the path grammar"
done <"$work/entry-points"

# make_sandbox <dir>: a read-only copy of the tree in <dir>/tree.
make_sandbox() {
  mkdir "$1" "$1/tree" || return 1
  set +f
  for e in "$repo_root"/* "$repo_root"/.[!.]* "$repo_root"/..?*; do
    [ -e "$e" ] || [ -h "$e" ] || continue
    case ${e##*/} in .git | .claude | tests) continue ;; esac
    cp -RP "$e" "$1/tree/" || {
      set -f
      return 1
    }
  done
  set -f
  chmod -R a-w "$1/tree"
}

# run_ep <sandbox> <path> <args-file> <stdin-file> <out-prefix>: run one entry
# point; writes <out-prefix>.out, .err and .rc.
runs=0
run_ep() {
  runs=$((runs + 1))
  (
    sb=$1 ep=$2 argf=$3 inf=$4 o=$5
    rh=$sb/run$runs
    mkdir "$rh" "$rh/home" "$rh/tmp" || exit 5
    set --
    while IFS= read -r a || [ -n "$a" ]; do
      set -- "$@" "$a"
    done <"$argf"
    cd "$sb/tree" || exit 5
    env -i PATH="$PATH" HOME="$rh/home" TMPDIR="$rh/tmp" LC_ALL=C \
      GIT_CEILING_DIRECTORIES="$sb" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
      /bin/sh "$bounded" -k 5 "$run_bound" "./$ep" "$@" <"$inf" >"$o.out" 2>"$o.err"
    printf '%s\n' "$?" >"$o.rc"
  )
}

# stderr_class <err-file>: the class a recording writes.
stderr_class() {
  if [ ! -s "$1" ]; then
    printf '%s\n' empty
    return
  fi
  line=$(sed -n '/./{p;q;}' "$1" | sed 's/[][\\.^$*+?(){}|]/\\&/g')
  printf 'match ^%s$\n' "$line"
}

# class_holds <class-line> <err-file>
class_holds() {
  case $1 in
    empty) [ ! -s "$2" ] ;;
    'match '?*) grep -Eq -- "${1#match }" "$2" ;;
    *) return 2 ;;
  esac
}

if [ -n "$record" ]; then
  valid_path "$record" || fail_closed "the recorded path is outside the path grammar"
  grep -Fqx -- "$record" "$work/entry-points" || {
    printf '%s\n' "$me: $record is not an entry point; only entry points are recorded" >&2
    exit 1
  }
  : >"$work/args"
  for a in "$@"; do
    case $a in *'
'*) fail_closed "an argument holds a newline, which the args file cannot carry" ;; esac
    printf '%s\n' "$a" >>"$work/args"
  done
  if [ -n "$record_stdin" ]; then
    [ -f "$record_stdin" ] && [ -r "$record_stdin" ] || fail_closed "the --stdin file is unreadable"
    cp "$record_stdin" "$work/stdin" || fail_closed "cannot read the --stdin file"
    inf=$work/stdin
  else
    inf=/dev/null
  fi
  for i in 1 2; do
    make_sandbox "$work/sb$i" || fail_closed "the sandbox copy did not build"
    run_ep "$work/sb$i" "$record" "$work/args" "$inf" "$work/r$i"
    rc=$(cat "$work/r$i.rc")
    case $rc in
      124 | 125) fail_closed "the run timed out or its bound failed (exit $rc)" ;;
      "$reserved_fetch_failure") fail_closed "the run exited with the reserved fetch-failure code" ;;
    esac
    [ "$rc" -gt 128 ] && fail_closed "the run ended on a signal (exit $rc)"
    stderr_class "$work/r$i.err" >"$work/r$i.class"
  done
  for x in rc out class; do
    cmp -s "$work/r1.$x" "$work/r2.$x" \
      || fail_closed "two runs differ; the fixture would not be deterministic"
  done
  dest=$fixtures/$record
  mkdir -p "$dest" || fail_closed "cannot create $dest"
  rm -f "$dest/stdin"
  for x in args:args r1.out:stdout r1.rc:exit r1.class:stderr; do
    cp "$work/${x%%:*}" "$dest/${x#*:}" || fail_closed "cannot write the fixture"
  done
  if [ -n "$record_stdin" ]; then
    cp "$work/stdin" "$dest/stdin" || fail_closed "cannot write the fixture"
  fi
  printf '%s\n' "$me: recorded $record (exit $(cat "$work/r1.rc"), stderr $(cat "$work/r1.class"))"
  exit 0
fi

findings=0
finding() {
  printf '%s\n' "$me: $1"
  findings=$((findings + 1))
}

: >"$work/recorded"
if [ -d "$fixtures" ]; then
  find "$fixtures" -type f -name exit >"$work/exit-files" || fail_closed "cannot list the fixtures"
  while IFS= read -r f; do
    p=${f#"$fixtures"/}
    p=${p%/exit}
    valid_path "$p" || fail_closed "a fixture directory is outside the path grammar"
    printf '%s\n' "$p" >>"$work/recorded"
  done <"$work/exit-files"
fi
sort -u "$work/recorded" -o "$work/recorded" || fail_closed "cannot sort the fixtures"

while IFS= read -r ep; do
  grep -Fqx -- "$ep" "$work/recorded" \
    || finding "$ep: an entry point with no recorded fixture (record one with --record $ep)"
done <"$work/entry-points"

make_sandbox "$work/sb" || fail_closed "the sandbox copy did not build"
while IFS= read -r p; do
  d=$fixtures/$p
  if [ ! -e "$repo_root/$p" ] && [ ! -h "$repo_root/$p" ]; then
    finding "$p: a recorded entry point is gone from the tree"
    continue
  fi
  if ! grep -Fqx -- "$p" "$work/entry-points"; then
    finding "$p: no longer an entry point, so its fixture is stale; remove tests/fixtures/entry-points/$p"
    continue
  fi
  [ -f "$d/args" ] && [ -f "$d/stdout" ] && [ -f "$d/stderr" ] \
    || fail_closed "$p: the fixture lacks args, stdout, or stderr"
  want_rc=$(cat "$d/exit") || fail_closed "$p: the fixture's exit is unreadable"
  case $want_rc in '' | *[!0-9]*) fail_closed "$p: the fixture's exit is not a number" ;; esac
  [ "$want_rc" -le 255 ] || fail_closed "$p: the fixture's exit is out of range"
  IFS= read -r want_class <"$d/stderr" || [ -n "$want_class" ] || want_class=""
  case $want_class in empty | 'match '?*) ;; *) fail_closed "$p: the fixture's stderr class is malformed" ;; esac
  if [ ! -x "$repo_root/$p" ]; then
    finding "$p: not executable"
    continue
  fi
  inf=/dev/null
  [ -f "$d/stdin" ] && inf=$d/stdin
  run_ep "$work/sb" "$p" "$d/args" "$inf" "$work/run"
  rc=$(cat "$work/run.rc")
  if [ "$rc" = "$reserved_fetch_failure" ]; then
    finding "$p: exited $rc, the reserved fetch-failure code: its artifact was not fetched or verified, so the stdout contract was not met"
    continue
  fi
  [ "$rc" = "$want_rc" ] || finding "$p: exit $rc, recorded $want_rc"
  cmp -s "$work/run.out" "$d/stdout" || finding "$p: stdout differs from the recorded bytes"
  class_holds "$want_class" "$work/run.err"
  case $? in
    0) ;;
    1) finding "$p: stderr is not in the recorded class ($want_class)" ;;
    *) fail_closed "$p: the stderr class does not evaluate" ;;
  esac
done <"$work/recorded"

awk -F '\t' 'NR > 1 { print $1 }' "$work/partition" >"$work/layer"
while IFS= read -r s; do
  valid_path "$s" || fail_closed "the partition names a script outside the path grammar"
  [ -f "$repo_root/$s" ] || continue
  target=$(sed -n 's/^# planwright-shim-target: *\([^ ]*\) *$/\1/p' "$repo_root/$s" | sed -n 1p)
  [ -n "$target" ] || continue
  grep -Fqx -- "$s" "$work/flagged" \
    && finding "$s: a shim the partition flags; a flagged script is removed or given a caller, never migrated"
  grep -Fqx -- "$target" "$work/flagged" \
    && finding "$s: delegates to $target, which the partition flags; a flagged script is never migrated"
done <"$work/layer"

[ "$findings" -eq 0 ] || exit 1
exit 0
