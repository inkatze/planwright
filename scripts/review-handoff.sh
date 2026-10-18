#!/bin/sh
# review-handoff.sh — build the handoff bundle a review pass reads, so every
# lens, the self-critique agent, and the blind pass get the same context from
# one path instead of each fetching a diff slice of its own
# (review-effectiveness REQ-B1.1, REQ-B1.5, REQ-A1.6, REQ-D1.2, D-3, D-14).
#
# THE BUNDLE is a directory, by default <repo>/.claude/review-handoff
# (gitignored, beside the polish audit file), rebuilt per pass from the
# committed HEAD:
#   MANIFEST          tab-separated key lines, first `review-handoff 1`: head,
#                     base, merge_base, mode (full|delta), previous_head (delta
#                     only), each task, tasks_file, each resolved doctrine
#                     path, the brief path, each tooling file
#   diff.patch        the diff from the merge base of --base and HEAD to HEAD
#   name-status.txt   that diff's name-status, renames detected
#   changed-files.txt every touched path, both sides of a rename
#   files/<path>      every changed file whole, as HEAD holds it
#   callers.tsv       `<symbol> <kind> <path>:<line> <text>` per reference to a
#                     changed symbol, kind `function` or `path`
#   caller-search.txt how the callers were found and what that misses
#   contract.md       the task blocks named by --task, from --tasks-file
#   pr-title.txt, pr-body.md   the would-be PR title and body, when given
#   tooling/<name>    each --tooling file, copied
#   delta.patch, delta-files.txt   --delta only: the change since the previous
#                     pass's head, and the files the fixes since then touched
#
# CHANGED SYMBOLS. Each function enclosing a changed line (the new side read
# in HEAD, the old side in the merge base, so a renamed or deleted function is
# searched by its old name too), and each changed path: its repo path, plus
# its basename for a script. Callers are a whole-word `git grep` over the
# tracked tree at HEAD, a heuristic with no new dependency; caller-search.txt
# records its per-language limits. A definition line is not listed as its own
# caller, nor a file as its own path consumer.
#
# CONTAINMENT. The bundle directory must sit strictly inside <repo>/.claude/,
# judged on the physical path, and must not be a symlink; an existing
# directory there is replaced only when it is a bundle (its MANIFEST says so).
# The bundle is staged beside it and swapped in whole. A changed path that git
# quotes, is absolute, or holds a `..` component is not written and is noted
# in caller-search.txt.
#
# Untrusted input: the diff and file contents are branch-controlled. They are
# copied and searched as data; a symbol reaches git grep only through -F -e
# after matching a fixed character class, and nothing from the tree is
# executed or interpolated into program text.
#
# Usage:
#   review-handoff.sh --base <rev> [--delta <previous-head>]
#       [--tasks-file <tasks.md> --task <id> ...]
#       [--title <text>] [--body-file <file>] [--tooling <file> ...]
#       [--doctrine <path> ...] [--brief <path>] [--out <dir>]
#       [--max-callers <n>]
#
#   --delta        the previous pass's head; must be an ancestor of HEAD
#   --out          default .claude/review-handoff, relative to the repo root
#   --max-callers  references listed per symbol, default 200; the rest are
#                  counted in caller-search.txt
#
# Prints the bundle path. Exit codes: 0 written; 2 usage or a refused input.
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

prog=review-handoff
TAB=$(printf '\t')
NL='
'

usage() {
  cat >&2 <<EOF
usage: $prog --base <rev> [--delta <previous-head>]
         [--tasks-file <tasks.md> --task <id> ...]
         [--title <text>] [--body-file <file>] [--tooling <file> ...]
         [--doctrine <path> ...] [--brief <path>] [--out <dir>]
         [--max-callers <n>]
EOF
  exit 2
}
die() {
  printf '%s\n' "$prog: $2" >&2
  exit "$1"
}

start=$(pwd)
# abs <path> — the path made absolute against the caller's directory.
abs() {
  case $1 in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$start/$1" ;;
  esac
}
# readable <label> <path> — refuse a path that is not a readable file.
readable() {
  [ -f "$2" ] && [ -r "$2" ] || die 2 "$1 is not a readable file: $2"
}
one_line() {
  case $2 in *"$NL"*) die 2 "$1 must not contain a newline" ;; esac
}

base=
delta=
tasks_file=
tasks=
title=
title_set=0
body_file=
tooling=
doctrine=
brief=
out=
max_callers=200
while [ $# -gt 0 ]; do
  case $1 in
    --base | --delta | --tasks-file | --task | --title | --body-file | --tooling | --doctrine | --brief | --out | --max-callers)
      [ $# -ge 2 ] || usage
      one_line "$1" "$2"
      case $1 in
        --base) base=$2 ;;
        --delta) delta=$2 ;;
        --tasks-file) tasks_file=$(abs "$2") ;;
        --task) tasks=$tasks$2$NL ;;
        --title)
          title=$2
          title_set=1
          ;;
        --body-file) body_file=$(abs "$2") ;;
        --tooling) tooling=$tooling$(abs "$2")$NL ;;
        --doctrine) doctrine=$doctrine$(abs "$2")$NL ;;
        --brief) brief=$(abs "$2") ;;
        --out) out=$2 ;;
        --max-callers) max_callers=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done

[ -n "$base" ] || usage
case $max_callers in '' | 0 | *[!0-9]*) die 2 "--max-callers must be a positive integer" ;; esac
for id in $tasks; do
  printf '%s\n' "$id" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || die 2 "--task must be a task id like 5 or 3.5"
done
if [ -n "$tasks" ]; then
  [ -n "$tasks_file" ] || die 2 "--task needs --tasks-file"
  readable "--tasks-file" "$tasks_file"
fi
[ -z "$body_file" ] || readable "--body-file" "$body_file"
[ -z "$brief" ] || readable "--brief" "$brief"
printf '%s' "$tooling" | while IFS= read -r f; do readable "--tooling" "$f"; done
printf '%s' "$doctrine" | while IFS= read -r f; do readable "--doctrine" "$f"; done

top=$(git rev-parse --show-toplevel 2>/dev/null) || die 2 "not inside a git work tree"
cd "$top"

# rev <label> <rev> — the commit a revision names, refusing option-like input.
rev() {
  case $2 in -*) die 2 "$1 must be a revision, not an option" ;; esac
  git rev-parse --verify --quiet "$2^{commit}" || die 2 "$1 names no commit: $2"
}
base_sha=$(rev --base "$base")
head=$(git rev-parse --verify "HEAD^{commit}")
mb=$(git merge-base "$base_sha" "$head") || die 2 "--base shares no history with HEAD"
prev=
if [ -n "$delta" ]; then
  prev=$(rev --delta "$delta")
  git merge-base --is-ancestor "$prev" "$head" \
    || die 2 "--delta must be an ancestor of HEAD: a delta from off this branch's history means nothing"
fi

# --- containment -------------------------------------------------------------

mkdir -p "$top/.claude"
claude=$(cd "$top/.claude" && pwd -P)
[ -n "$out" ] || out=.claude/review-handoff
case $out in /*) ;; *) out=$top/$out ;; esac
out=${out%/}
name=$(basename "$out")
parent=$(dirname "$out")
case $name in '' | . | ..) die 2 "--out must name a directory inside .claude/" ;; esac
[ -d "$parent" ] || die 2 "--out's parent directory does not exist: $parent"
parent=$(cd "$parent" && pwd -P)
case $parent/ in "$claude"/*) ;; *) die 2 "--out must sit inside $claude/" ;; esac
out=$parent/$name
[ ! -L "$out" ] || die 2 "--out is a symlink; refusing to write through it"
if [ -e "$out" ]; then
  [ -d "$out" ] && [ -f "$out/MANIFEST" ] \
    && [ "$(sed -n 1p "$out/MANIFEST")" = "review-handoff${TAB}1" ] \
    || die 2 "--out exists and is not a handoff bundle; refusing to replace it"
fi

stage=$(mktemp -d "$parent/review-handoff.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/files" "$stage/tooling"

# --- the diff and the changed files -------------------------------------------

gitd() { git -c core.quotePath=false diff --no-ext-diff --no-textconv --no-color -M "$@"; }
gitd "$mb" "$head" >"$stage/diff.patch"
gitd --name-status "$mb" "$head" >"$stage/name-status.txt"

notes=
# safe_path <path> — a path the bundle may write and search.
safe_path() {
  case $1 in
    '"'* | /* | .. | ../* | */.. | */../* | -*) return 1 ;;
  esac
}
# script_like <rev> <path> — a file whose basename callers also use.
script_like() {
  case $2 in
    *.sh | *.bash | *.py | *.js | *.mjs | *.cjs | *.ts | *.go | *.rb | *.pl) return 0 ;;
    */*.* | *.*) return 1 ;;
  esac
  git cat-file -p "$1:$2" 2>/dev/null | sed -n '1{/^#!/p;}' | grep -q .
}
# lang <rev> <path> — the definition grammar the symbol scan applies.
lang() {
  case $2 in
    *.sh | *.bash) printf 'sh\n' ;;
    *.py) printf 'py\n' ;;
    *.js | *.mjs | *.cjs | *.ts) printf 'js\n' ;;
    *.go) printf 'go\n' ;;
    */*.* | *.*) printf 'none\n' ;;
    *)
      if git cat-file -p "$1:$2" 2>/dev/null | sed -n 1p | grep -Eq '^#!.*(/|env[[:space:]]+)(ba|da|k|z)?sh([[:space:]]|$)'; then
        printf 'sh\n'
      else
        printf 'none\n'
      fi
      ;;
  esac
}

# Symbols are written as `<symbol> <kind> <own-path>` lines; own-path is the
# file a self-reference to the symbol does not count in, `-` for none.
symbols=$stage/.symbols
: >"$symbols"
# Every definition in a changed file at HEAD, `<path> <name> <line>`: a
# reference sitting on one of these lines is the definition, not a caller.
defs=$stage/.defs
: >"$defs"
: >"$stage/changed-files.txt"

# enclosing <lang> <lines> — read a file on stdin and print the function
# enclosing each listed line number; with lines `defs`, print every
# definition as `<name> <line>` instead.
enclosing() {
  awk -v lang="$1" -v lines="$2" '
    BEGIN { n = split(lines, L, " "); for (i = 1; i <= n; i++) want[L[i]] = 1 }
    {
      name = ""
      s = $0
      if (lang == "sh") {
        if (match(s, /^[ \t]*function[ \t]+[A-Za-z_][A-Za-z0-9_:-]*/)) {
          name = substr(s, RSTART, RLENGTH); sub(/^[ \t]*function[ \t]+/, "", name)
        } else if (match(s, /^[ \t]*[A-Za-z_][A-Za-z0-9_:-]*[ \t]*\(\)/)) {
          name = substr(s, RSTART, RLENGTH); sub(/^[ \t]*/, "", name); sub(/[ \t]*\(\)$/, "", name)
        }
      } else if (lang == "py") {
        if (match(s, /^[ \t]*(async[ \t]+)?(def|class)[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
          name = substr(s, RSTART, RLENGTH); sub(/^.*[ \t]/, "", name)
        } else if (s ~ /^[^ \t#@]/) cur = ""
      } else if (lang == "js") {
        if (match(s, /^[ \t]*(export[ \t]+)?(default[ \t]+)?(async[ \t]+)?(function\*?|class)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*/)) {
          name = substr(s, RSTART, RLENGTH); sub(/^.*[ \t*]/, "", name)
        } else if (match(s, /^[ \t]*(export[ \t]+)?(const|let|var)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*=[ \t]*(async[ \t]*)?(function|\()/)) {
          name = substr(s, RSTART, RLENGTH); sub(/[ \t]*=.*$/, "", name); sub(/^.*[ \t]/, "", name)
        }
      } else if (lang == "go") {
        if (match(s, /^func[ \t]+(\([^)]*\)[ \t]*)?[A-Za-z_][A-Za-z0-9_]*/)) {
          name = substr(s, RSTART, RLENGTH); sub(/^.*[ \t)]/, "", name)
        }
      }
      if (name != "") cur = name
      if (lines == "defs") { if (name != "") print name "\t" NR }
      else if ((NR in want) && cur != "") print cur
      if (lang != "py" && s ~ /^}/) cur = ""
    }'
}
# hunk_lines <side> <mb> <head> <path>... — changed line numbers on one side
# (old or new) of the diff, space-separated.
hunk_lines() {
  side=$1
  shift 3
  gitd -U0 "$mb" "$head" -- "$@" | awk -v side="$side" '
    /^@@ / {
      split($(side == "old" ? 2 : 3), r, ",")
      start = substr(r[1], 2) + 0
      count = (2 in r) ? r[2] + 0 : 1
      for (i = 0; i < count; i++) printf "%d ", start + i
    }'
}
add_functions() {
  # add_functions <rev> <path> <lines> <own-path>
  [ -n "$3" ] || return 0
  l=$(lang "$1" "$2")
  [ "$l" != none ] || return 0
  git cat-file -p "$1:$2" 2>/dev/null | enclosing "$l" "$3" | sort -u | while IFS= read -r fn; do
    printf '%s\tfunction\t%s\n' "$fn" "$4" >>"$symbols"
  done
}
add_path() {
  # add_path <rev> <path> <own-path>
  printf '%s\tpath\t%s\n' "$2" "$3" >>"$symbols"
  if script_like "$1" "$2"; then
    printf '%s\tpath\t%s\n' "${2##*/}" "$3" >>"$symbols"
  fi
}

while IFS="$TAB" read -r status p1 p2; do
  [ -n "$status" ] || continue
  old=
  new=
  case $status in
    R* | C*)
      old=$p1
      new=$p2
      ;;
    D*) old=$p1 ;;
    A*) new=$p1 ;;
    *)
      old=$p1
      new=$p1
      ;;
  esac
  case $status in C*) old= ;; esac
  if [ -n "$old" ] && ! safe_path "$old"; then
    notes=$notes"skipped-path${TAB}$old$NL"
    old=
  fi
  if [ -n "$new" ] && ! safe_path "$new"; then
    notes=$notes"skipped-path${TAB}$new$NL"
    new=
  fi
  [ -z "$old" ] || printf '%s\n' "$old" >>"$stage/changed-files.txt"
  [ -z "$new" ] || printf '%s\n' "$new" >>"$stage/changed-files.txt"
  if [ -n "$new" ] && [ "$(git cat-file -t "$head:$new" 2>/dev/null)" = blob ]; then
    mkdir -p "$stage/files/$(dirname "$new")"
    git cat-file -p "$head:$new" >"$stage/files/$new"
  fi
  if [ -n "$new" ]; then
    l=$(lang "$head" "$new")
    [ "$l" = none ] || git cat-file -p "$head:$new" 2>/dev/null | enclosing "$l" defs \
      | awk -v p="$new" '{ print p "\t" $0 }' >>"$defs"
    add_path "$head" "$new" "$new"
    add_functions "$head" "$new" "$(hunk_lines new "$mb" "$head" ${old:+"$old"} "$new")" "$new"
  fi
  if [ -n "$old" ] && [ "$old" != "$new" ]; then
    add_path "$mb" "$old" -
  fi
  if [ -n "$old" ]; then
    add_functions "$mb" "$old" "$(hunk_lines old "$mb" "$head" "$old" ${new:+"$new"})" -
  fi
done <"$stage/name-status.txt"
sort -u -o "$stage/changed-files.txt" "$stage/changed-files.txt"

# --- callers -----------------------------------------------------------------

: >"$stage/callers.tsv"
truncated=
sort -u -t "$TAB" -k1,2 "$symbols" | while IFS="$TAB" read -r sym kind own; do
  case $sym in '' | *[!A-Za-z0-9_.:/@+-]*) continue ;; esac
  git grep -n -I -w -F -e "$sym" "$head" -- . 2>/dev/null | awk -v head="$head:" -v sym="$sym" \
    -v kind="$kind" -v own="$own" -v max="$max_callers" -v defs="$defs" -v report="$stage/.truncated" '
    BEGIN {
      FS = "\t"
      while ((getline d < defs) > 0) { split(d, f, "\t"); if (f[2] == sym) isdef[f[1] SUBSEP f[3]] = 1 }
      FS = " "
    }
    {
      line = substr($0, length(head) + 1)
      if (!match(line, /:[0-9]+:/)) next
      path = substr(line, 1, RSTART - 1)
      num = substr(line, RSTART + 1, RLENGTH - 2)
      text = substr(line, RSTART + RLENGTH)
      if (kind == "path" && path == own) next
      if (kind == "function" && ((path SUBSEP num) in isdef)) next
      gsub(/\r/, "", text)
      total++
      if (total <= max) printf "%s\t%s\t%s:%s\t%s\n", sym, kind, path, num, substr(text, 1, 200)
    }
    END { if (total > max) printf "truncated\t%s\t%d\n", sym, total >> report }' >>"$stage/callers.tsv"
done
[ ! -f "$stage/.truncated" ] || truncated=$(cat "$stage/.truncated")
rm -f "$symbols" "$defs" "$stage/.truncated"

cat >"$stage/caller-search.txt" <<EOF
caller search: a whole-word git grep -F over the tracked tree at $head, a heuristic
symbols: each function enclosing a changed line (both sides of the diff), and each changed path
paths: a changed path's repo path, plus its basename for a script; a longer name ending in that basename after a non-word character also matches
shell: name() and function name definitions; a function ends at a column-0 }
python: def and class at any indent; a definition runs to the next definition or column-0 statement
javascript/typescript: function, class, and const/let/var name = function or arrow; methods are not definitions
go: func and method definitions; a function ends at a column-0 }
other languages: path references only
a whole-word match is not a call: comments, strings, and same-named symbols elsewhere are listed too; dynamic dispatch, aliases, and constructed names are missed
max callers per symbol: $max_callers
EOF
printf '%s' "$truncated$notes" >>"$stage/caller-search.txt"

# --- contract, PR text, tooling ----------------------------------------------

if [ -n "$tasks" ]; then
  : >"$stage/contract.md"
  for id in $tasks; do
    awk -v id="$id" '
      BEGIN { gsub(/\./, "[.]", id) }
      $0 ~ "^### Task " id "( |$)" { on = 1; found = 1; print; next }
      on && /^#{1,3} / { on = 0 }
      on { print }
      END { exit !found }' "$tasks_file" >>"$stage/contract.md" \
      || die 2 "--tasks-file holds no block for Task $id"
  done
fi
[ "$title_set" -eq 0 ] || printf '%s\n' "$title" >"$stage/pr-title.txt"
[ -z "$body_file" ] || cp "$body_file" "$stage/pr-body.md"
tooling_names=
n=0
printf '%s' "$tooling" >"$stage/.tooling"
while IFS= read -r f; do
  n=$((n + 1))
  t=$(basename "$f")
  [ ! -e "$stage/tooling/$t" ] || t=$n-$t
  cp "$f" "$stage/tooling/$t"
  tooling_names=$tooling_names"tooling${TAB}$t$NL"
done <"$stage/.tooling"
rm -f "$stage/.tooling"

# --- delta -------------------------------------------------------------------

if [ -n "$prev" ]; then
  gitd "$prev" "$head" >"$stage/delta.patch"
  gitd --name-status "$prev" "$head" | awk -F '\t' 'NF >= 2 { for (i = 2; i <= NF; i++) print $i }' \
    | sort -u >"$stage/delta-files.txt"
fi

# --- manifest, written last ---------------------------------------------------

{
  printf 'review-handoff\t1\n'
  printf 'head\t%s\n' "$head"
  printf 'base\t%s\n' "$base_sha"
  printf 'merge_base\t%s\n' "$mb"
  if [ -n "$prev" ]; then
    printf 'mode\tdelta\n'
    printf 'previous_head\t%s\n' "$prev"
  else
    printf 'mode\tfull\n'
  fi
  for id in $tasks; do printf 'task\t%s\n' "$id"; done
  [ -z "$tasks" ] || printf 'tasks_file\t%s\n' "$tasks_file"
  printf '%s' "$doctrine" | while IFS= read -r f; do printf 'doctrine\t%s\n' "$f"; done
  [ -z "$brief" ] || printf 'brief\t%s\n' "$brief"
  printf '%s' "$tooling_names"
} >"$stage/MANIFEST"

[ ! -e "$out" ] || rm -rf "$out"
mv "$stage" "$out"
printf '%s\n' "$out"
