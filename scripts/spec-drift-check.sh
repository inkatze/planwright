#!/bin/bash
# spec-drift-check.sh — list the changed files a spec names as a task
# deliverable while that spec's anchored content did not change.
#
# Usage:
#   spec-drift-check.sh --repo <dir> --base <ref> --head <ref>
#                       --body-file <file> [--spec-root <path>]
#
# A changed file listed (backticked) in a task's Deliverables is flagged unless
# a spec listing it changed its anchored content (merge base against head, so a
# status annotation is no edit), a `Not covered: <path> — <reason>` body line
# names it, or a commit trailer `Planwright-Task: <spec>/<id>` names a task
# listing it. A body with no such line covers nothing.
#
# Output, one line each, tab-separated:
#   flagged<TAB><path><TAB><spec>/<task>[ <spec>/<task>...]
# Exit codes:
#   0  nothing flagged
#   4  at least one file flagged
#   2  the check cannot run (no base, unreadable bundle or body, bad usage);
#      the reason is on stderr and the pull request is refused, never passed
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=spec-drift-check
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

die() {
  printf '%s: %s\n' "$prog" "$1" >&2
  exit 2
}

repo='' base='' head='' body='' root=specs
while [ $# -gt 0 ]; do
  case $1 in
    --repo | --base | --head | --body-file | --spec-root)
      [ $# -ge 2 ] || die "$1 takes a value"
      case $1 in
        --repo) repo=$2 ;;
        --base) base=$2 ;;
        --head) head=$2 ;;
        --body-file) body=$2 ;;
        --spec-root) root=$2 ;;
      esac
      shift 2
      ;;
    *) die "unknown argument $1" ;;
  esac
done
[ -n "$repo" ] && [ -d "$repo" ] || die "--repo takes a repository directory"
[ -n "$base" ] || die "no base given"
[ -n "$head" ] || die "no head given"
[ -n "$body" ] && [ -r "$body" ] || die "--body-file takes a readable file (an empty one for no statement)"
case $root in
  '' | /* | . | .. | ../* | */.. | */../*) die "--spec-root takes a path inside the repository" ;;
esac
root=${root%/}
for f in spec-model.sh spec-anchor.sh untrusted-git-lib.sh; do
  [ -r "$script_dir/$f" ] || die "$f is missing or unreadable (broken install)"
done
# shellcheck source=scripts/untrusted-git-lib.sh
. "$script_dir/untrusted-git-lib.sh"

# The repository is a worker's: its own configuration runs nothing here.
g() { pw_untrusted_git -C "$repo" -c core.quotepath=false "$@"; }

head_sha=$(g rev-parse --verify -q "$head^{commit}" 2>/dev/null) || die "the head $head is not a commit of the repository"
base_sha=$(g rev-parse --verify -q "$base^{commit}" 2>/dev/null) || die "the base $base is not a commit of the repository"
mb=$(g merge-base "$base_sha" "$head_sha" 2>/dev/null) || die "the base and the head share no history"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/spec-drift-check.XXXXXX") || die "cannot create a scratch directory"
trap 'rm -rf "$tmp"' EXIT

g diff --no-renames --name-only "$mb" "$head_sha" >"$tmp/changed" 2>/dev/null || die "cannot list the changed files"
[ -s "$tmp/changed" ] || exit 0

# Tasks the pull request's own commits name.
g log --format='%(trailers:key=Planwright-Task,valueonly,separator=%x0a)' "$mb..$head_sha" 2>/dev/null \
  | awk 'NF { gsub(/^[ \t]+|[ \t\r]+$/, ""); print }' >"$tmp/trailers" || die "cannot read the commit trailers"

# Not covered: <path> — <reason>, a reason being required.
awk '
  { sub(/\r$/, "") }
  {
    line = $0
    if (!match(line, /^[ \t>*-]*Not covered:[ \t]*/)) next
    rest = substr(line, RLENGTH + 1)
    if (substr(rest, 1, 1) == "`") {
      rest = substr(rest, 2); i = index(rest, "`")
      if (!i) next
      p = substr(rest, 1, i - 1); rest = substr(rest, i + 1)
    } else {
      i = match(rest, /[ \t]/)
      if (!i) next
      p = substr(rest, 1, i - 1); rest = substr(rest, i)
    }
    sub(/^[ \t]*(\xe2\x80\x94|--|-|:)?[ \t]*/, "", rest)
    gsub(/\xe2\x80\x93|\xe2\x80\x94/, "", rest)
    gsub(/[[:punct:][:space:]]/, "", rest)
    if (rest != "") { sub(/^\.\//, "", p); print p }
  }' "$body" >"$tmp/notcovered" || die "cannot read the pull request body"

# The bundles at the head: the directories directly under the root, those
# opening with an underscore (the reserved accumulators) aside.
if [ "$(g cat-file -t "$head_sha:$root" 2>/dev/null)" != tree ]; then
  exit 0
fi
# Listing the files first makes a listed file git cannot read an error,
# never an absence that would read as a new, and so edited, bundle.
g ls-tree --full-tree -r --name-only "$head_sha:$root" >"$tmp/head-files" 2>/dev/null || die "cannot read the spec root $root at the head"
base_root=$(g --literal-pathspecs ls-tree --full-tree "$mb" -- "$root" 2>/dev/null) || die "cannot read the merge base"
case $base_root in
  *" tree "*) g ls-tree --full-tree -r --name-only "$mb:$root" >"$tmp/base-files" 2>/dev/null || die "cannot read the spec root $root at the merge base" ;;
  *) : >"$tmp/base-files" ;;
esac
awk -F / 'NF > 1 && !seen[$1]++ { print $1 }' "$tmp/head-files" >"$tmp/entries"

: >"$tmp/listing"
: >"$tmp/edited"
files='requirements.md design.md tasks.md test-spec.md'
# export_bundle <commit> <bundle> <dir> <file list>: 0 all four files, 1 none, 2 some
export_bundle() {
  local c=$1 b=$2 d=$3 f n=0
  mkdir -p "$d" || die "cannot create a scratch directory"
  for f in $files; do
    grep -qxF -- "$b/$f" "$4" || continue
    g cat-file blob "$c:$root/$b/$f" >"$d/$f" 2>/dev/null || die "cannot read $root/$b/$f at $c"
    n=$((n + 1))
  done
  case $n in 4) return 0 ;; 0) return 1 ;; *) return 2 ;; esac
}
while IFS= read -r b; do
  case $b in _*) continue ;; esac
  [[ $b =~ ^[a-z0-9][a-z0-9-]*$ ]] || continue
  # A bundle whose tasks.md holds no changed path as text lists none of them,
  # so it is skipped before the costly model and anchor reads.
  grep -qxF -- "$b/tasks.md" "$tmp/head-files" || continue
  g cat-file blob "$head_sha:$root/$b/tasks.md" >"$tmp/tasks" 2>/dev/null || die "cannot read $root/$b/tasks.md at the head"
  rc=0
  awk 'FILENAME == ARGV[1] { if ($0 != "") c[++n] = $0; next }
    { for (i = 1; i <= n; i++) if (index($0, c[i])) { hit = 1; exit } }
    END { exit hit ? 0 : 1 }' "$tmp/changed" "$tmp/tasks" || rc=$?
  case $rc in
    0) ;;
    1) continue ;;
    *) die "cannot read $root/$b/tasks.md at the head" ;;
  esac
  rc=0
  export_bundle "$head_sha" "$b" "$tmp/head/$b" "$tmp/head-files" || rc=$?
  case $rc in
    1) continue ;;
    2) die "the bundle $b is unreadable at the head (a spec file is missing)" ;;
  esac
  /bin/sh "$script_dir/spec-model.sh" "$tmp/head/$b" >"$tmp/model" 2>/dev/null || die "the bundle $b cannot be read"
  awk -F '\t' -v B="$b" '
    $1 == "TASKFIELD" && $3 == "deliverables" {
      text = $0; sub(/^TASKFIELD\t[^\t]*\tdeliverables\t/, "", text)
      while ((n = index(text, "`")) > 0) {
        text = substr(text, n + 1); m = index(text, "`")
        if (!m) break
        tok = substr(text, 1, m - 1); text = substr(text, m + 1)
        if (tok ~ /^[^ \t]+$/) { sub(/^\.\//, "", tok); print tok "\t" B "\t" $2 }
      }
    }' "$tmp/model" >>"$tmp/listing" || die "the bundle $b cannot be read"
  # An untouched bundle is the same at both ends, so its anchor is unchanged.
  P="$root/$b/" awk 'index($0, ENVIRON["P"]) == 1 { hit = 1; exit } END { exit hit ? 0 : 1 }' "$tmp/changed" || continue
  hanchor=$(/bin/sh "$script_dir/spec-anchor.sh" "$tmp/head/$b" 2>/dev/null) || die "the anchor of $b cannot be computed at the head"
  rc=0
  export_bundle "$mb" "$b" "$tmp/base/$b" "$tmp/base-files" || rc=$?
  if [ "$rc" = 0 ]; then
    banchor=$(/bin/sh "$script_dir/spec-anchor.sh" "$tmp/base/$b" 2>/dev/null) || die "the anchor of $b cannot be computed at the base"
  else
    banchor=''
  fi
  [ "$hanchor" = "$banchor" ] || printf '%s\n' "$b" >>"$tmp/edited"
done <"$tmp/entries"

# A changed path is flagged when a spec lists it and nothing excuses it.
awk -F '\t' '
  FILENAME == ARGV[1] { chg[$0] = 1; next }
  FILENAME == ARGV[2] { nc[$0] = 1; next }
  FILENAME == ARGV[3] { tr[$0] = 1; next }
  FILENAME == ARGV[4] { ed[$0] = 1; next }
  {
    p = $1; if (!(p in chg)) next
    if (!(p in order)) { order[p] = ++n; names[n] = p }
    who[p] = who[p] (who[p] == "" ? "" : " ") $2 "/" $3
    if (($2 "/" $3) in tr) excused[p] = 1
    if ($2 in ed) excused[p] = 1
    if (p in nc) excused[p] = 1
  }
  END {
    for (i = 1; i <= n; i++) { p = names[i]; if (!(p in excused)) { print "flagged\t" p "\t" who[p]; bad = 1 } }
    exit bad ? 4 : 0
  }' "$tmp/changed" "$tmp/notcovered" "$tmp/trailers" "$tmp/edited" "$tmp/listing"
