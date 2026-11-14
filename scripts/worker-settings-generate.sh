#!/bin/sh
# worker-settings-generate.sh — write the per-launch worker profile an opted-in
# launch passes with --settings.
#
# Usage: worker-settings-generate.sh <worker-settings.json> <worktree> <out-file>
#
# The four broad mise task-file denies (mise.toml, .mise.toml, mise-tasks/,
# .mise-tasks/ at any depth) are replaced by literal denies of the same names
# in every ancestor folder of the worktree and in the primary checkout, so only
# the worktree's own task files open, and a PreToolUse hook on the file tools
# (worker-mise-edit-guard.sh) refuses every task path outside the worktree,
# which no path rule can express. Every other rule stays as shipped.
# A worktree or primary path holding a pattern character, or a primary checkout
# that cannot be named, is refused. Output: whole by rename, owner-only,
# outside the worktree. What it opens and the residual risk:
# docs/permission-matcher-model.md, "The mise task-file opt-in".
#
# Exit: 0 written (the path is printed); 1 unusable input; 2 usage.
set -uf
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

me=worker-settings-generate.sh
die() {
  printf '%s: %s\n' "$me" "$1" >&2
  exit "${2:-1}"
}

[ "$#" -eq 3 ] || die "usage: $me <worker-settings.json> <worktree> <out-file>" 2
profile=$1
wt_arg=$2
out=$3

command -v jq >/dev/null 2>&1 || die "jq is required"
[ -f "$profile" ] && [ -r "$profile" ] || die "cannot read the profile $profile"
broad='["Edit(//**/mise.toml)","Edit(//**/.mise.toml)","Edit(//**/mise-tasks/**)","Edit(//**/.mise-tasks/**)"]'
jq -e --argjson b "$broad" '(.permissions.deny | type == "array") and ([$b[] as $r | (.permissions.deny | index($r))] | all(. != null))' \
  "$profile" >/dev/null 2>&1 || die "the profile is not JSON, or does not carry the four task-file deny rules to replace"

wt=$(cd -P -- "$wt_arg" 2>/dev/null && pwd -P) || die "not a directory: the worktree"
top=$(GIT_OPTIONAL_LOCKS=0 git -C "$wt" rev-parse --show-toplevel 2>/dev/null </dev/null) || die "not a git worktree"
wt=$(cd -P -- "$top" 2>/dev/null && pwd -P) || die "the worktree top level does not resolve"

nl='
'
unsafe_path() {
  case $1 in
    *'*'* | *'?'* | *'['* | *']'* | *\\* | *'('* | *')'* | *[[:cntrl:]]*) return 0 ;;
    *' '/* | *' ') return 0 ;;
    *"'"*) return 0 ;;
  esac
  return 1
}
unsafe_path "$wt" && die "the worktree path holds a character a path rule would read as a pattern; check the repository out elsewhere"

primary=''
common=$(GIT_OPTIONAL_LOCKS=0 git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null </dev/null) || common=''
case $common in
  /*/.git) primary=${common%/.git} ;;
esac
[ -n "$primary" ] && [ -d "$primary" ] || die "cannot name the primary checkout (its git directory is not <checkout>/.git); its task files would stay open"
primary=$(cd -P -- "$primary" 2>/dev/null && pwd -P) || die "the primary checkout does not resolve"
unsafe_path "$primary" && die "the primary checkout path holds a character a path rule would read as a pattern"

# The folders whose task files stay closed: every ancestor of the worktree,
# the root as `/`, then the primary checkout when it is not one of them.
dirs=''
a=$wt
while :; do
  a=${a%/*}
  if [ -z "$a" ]; then
    dirs="$dirs/$nl"
    break
  fi
  dirs="$dirs$a$nl"
done
if [ "$primary" != "$wt" ]; then
  case "$nl$dirs" in
    *"$nl$primary$nl"*) ;;
    *) dirs="$dirs$primary$nl" ;;
  esac
fi

out_dir=$(cd -P -- "$(dirname -- "$out")" 2>/dev/null && pwd -P) || die "the output folder does not exist"
case $out_dir/ in
  "$wt"/*) die "the output lies inside the worktree, where the worker could rewrite it" ;;
esac
out_name=$(basename -- "$out")
case $out_name in
  '' | . | .. | */*) die "bad output name" ;;
esac

tmp=$(mktemp "$out_dir/.$out_name.XXXXXX") || die "cannot write the output"
chmod 600 "$tmp" 2>/dev/null || {
  rm -f -- "$tmp"
  die "cannot make the output owner-only"
}
if ! jq --argjson b "$broad" --arg dirs "$dirs" --arg wt "$wt" --arg hook "\"\$CLAUDE_PLUGIN_ROOT\"/scripts/worker-mise-edit-guard.sh" '
  ($dirs | split("\n") | map(select(. != "") | if . == "/" then "" else . end)) as $anc
  | .permissions.deny |= (
      map(select(. as $d | ($b | index($d)) == null))
      + [ $anc[] as $a | ("mise.toml", ".mise.toml", "mise-tasks/**", ".mise-tasks/**") as $n
          | "Edit(/" + $a + "/" + $n + ")" ]
    )
  | ({type: "command", command: ($hook + " '"'"'" + $wt + "'"'"'")}) as $h
  | if ([(.hooks.PreToolUse // [])[] | select(.matcher == "Edit|Write|MultiEdit|NotebookEdit")] | length) > 0
    then .hooks.PreToolUse |= map(if .matcher == "Edit|Write|MultiEdit|NotebookEdit" then .hooks += [$h] else . end)
    else .hooks.PreToolUse += [{matcher: "Edit|Write|MultiEdit|NotebookEdit", hooks: [$h]}]
    end' "$profile" >"$tmp" 2>/dev/null; then
  rm -f -- "$tmp"
  die "cannot generate the profile"
fi
mv -f -- "$tmp" "$out" || {
  rm -f -- "$tmp"
  die "cannot write the output"
}
printf '%s\n' "$out"
