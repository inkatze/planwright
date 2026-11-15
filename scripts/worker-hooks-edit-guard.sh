#!/bin/bash
# worker-hooks-edit-guard.sh — the worker tier's PreToolUse hook for the file
# tools (Edit, Write, MultiEdit, NotebookEdit): it refuses a path inside a
# directory git runs hooks from, because a hook is code git runs on the
# worker's next commit.
#
# Usage: worker-hooks-edit-guard.sh < <PreToolUse payload>
# Output: a permissionDecision "deny" with its reason, or nothing (defer); exit 0.
#
# The protected directories, resolved from the payload's working directory:
#   - the hooks directory git runs from (core.hooksPath, relative or absolute,
#     or the default one in the common git directory);
#   - the worktree root's `githooks/` and `.githooks/`, and the primary
#     checkout's, since a hook may be wired to run from either by a later
#     config edit. A deeper directory of that name (`test/githooks/`) is not
#     protected: it holds fixtures, not hooks.
# A path is judged by its spelling and by where it resolves (`..`, symlinked
# directories and a symlinked leaf included) and compared case-insensitively,
# since a case-insensitive filesystem reaches a directory under any casing.
#
# Fail closed (REQ-B1.3): a payload that cannot be read, a missing jq or git, a
# working directory git cannot place, a path that cannot be resolved, a signal
# or a crash all refuse the call, so no error path lets a hooks edit through.
# This is the profile's only cover for a `core.hooksPath` directory: a path rule
# cannot name a directory the repository's own config chooses.
set -uf
LC_ALL=C
export LC_ALL
unset CDPATH

emit_deny() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"planwright worker-hooks-edit-guard: '"$1"'"}}'
  exit 0
}

DENY_HOOKS='this path is inside a git hooks directory (core.hooksPath, the default hooks directory, or a githooks/ or .githooks/ directory at the worktree or primary checkout root), and a hook is code git runs on the next commit. Hooks are changed by a person.'
DENY_UNREAD='the guard could not read or place this file-tool call, so it cannot tell whether it writes a hooks directory - refusing (fail closed).'

# norm <absolute path>: the path with `.`, `..` and empty components folded.
norm() {
  local out='' c old=$IFS
  IFS=/
  # shellcheck disable=SC2086
  set -- $1
  IFS=$old
  for c in "$@"; do
    case $c in
      '' | .) ;;
      ..) out=${out%/*} ;;
      *) out="$out/$c" ;;
    esac
  done
  printf '%s\n' "${out:-/}"
}

# phys <absolute path>: where the path resolves, symlinked directories and a
# symlinked leaf followed; the part that does not exist yet is appended as
# spelled. A `..` is resolved by the kernel after the symlinks before it, so
# it is never folded lexically here: the existing prefix goes through cd -P.
# Non-zero past the symlink bound, an unreadable folder, or a `.` or `..`
# component in the part that does not exist.
phys() {
  local p=$1 n=0 rest cur t d base comp
  while :; do
    n=$((n + 1))
    [ "$n" -le 40 ] || return 1
    rest=''
    cur=$p
    while [ ! -e "$cur" ] && [ ! -L "$cur" ] && [ "$cur" != / ]; do
      comp=${cur##*/}
      case $comp in
        . | ..) return 1 ;;
      esac
      rest="/$comp$rest"
      cur=${cur%/*}
      [ -n "$cur" ] || cur=/
    done
    if [ -L "$cur" ]; then
      t=$(readlink -- "$cur") || return 1
      case $t in
        /*) p=$t$rest ;;
        *) p=${cur%/*}/$t$rest ;;
      esac
      continue
    fi
    if [ -d "$cur" ]; then
      d=$(cd -P -- "$cur" 2>/dev/null && pwd -P) || return 1
      base=''
    else
      d=$(cd -P -- "${cur%/*}/" 2>/dev/null && pwd -P) || return 1
      base="/${cur##*/}"
    fi
    [ "$d" != / ] || d=''
    norm "$d$base$rest"
    return 0
  done
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# under <lowercased path> <lowercased directory>
under() {
  case $1/ in
    "$2"/*) return 0 ;;
  esac
  return 1
}

main() {
  local payload fields tool path cwd abs lex real top raw line c
  local SEP
  SEP=$(printf '\001')
  command -v jq >/dev/null 2>&1 || emit_deny "$DENY_UNREAD"
  command -v git >/dev/null 2>&1 || emit_deny "$DENY_UNREAD"
  payload=$(cat) || emit_deny "$DENY_UNREAD"
  fields=$(printf '%s' "$payload" | jq -r '
    (.tool_input.file_path // .tool_input.notebook_path // "") as $p
    | [(.tool_name // ""), $p, (.cwd // "")] | join("\u0001")' 2>/dev/null) || emit_deny "$DENY_UNREAD"
  tool=${fields%%"$SEP"*}
  fields=${fields#*"$SEP"}
  path=${fields%%"$SEP"*}
  cwd=${fields#*"$SEP"}
  case $tool in
    Edit | Write | MultiEdit | NotebookEdit) ;;
    '') emit_deny "$DENY_UNREAD" ;;
    *) return 0 ;;
  esac
  [ -n "$path" ] || emit_deny "$DENY_UNREAD"
  [ -n "$cwd" ] || cwd=$PWD

  case $path in
    '~' | '~'/*)
      [ -n "${HOME:-}" ] || emit_deny "$DENY_UNREAD"
      path=$HOME${path#\~}
      ;;
  esac
  case $path in
    /*) abs=$path ;;
    *) abs=$cwd/$path ;;
  esac
  case $abs in
    /*) ;;
    *) emit_deny "$DENY_UNREAD" ;;
  esac
  lex=$(norm "$abs")
  real=$(phys "$abs") || emit_deny "$DENY_UNREAD"
  [ -n "$real" ] || emit_deny "$DENY_UNREAD"

  [ -d "$cwd" ] || emit_deny "$DENY_UNREAD"
  top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || emit_deny "$DENY_UNREAD"
  [ -n "$top" ] || emit_deny "$DENY_UNREAD"
  raw=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir --git-path hooks 2>/dev/null) || emit_deny "$DENY_UNREAD"
  local -a dirs=()
  local common='' hooks='' i=0
  while IFS= read -r line; do
    case $line in
      /*) ;;
      *) emit_deny "$DENY_UNREAD" ;;
    esac
    if [ "$i" = 0 ]; then common=$line; else hooks=$line; fi
    i=$((i + 1))
  done <<EOF
$raw
EOF
  [ -n "$common" ] && [ -n "$hooks" ] || emit_deny "$DENY_UNREAD"
  dirs+=("$hooks" "$top/githooks" "$top/.githooks")
  case ${common##*/} in
    .git) dirs+=("${common%/*}/githooks" "${common%/*}/.githooks") ;;
  esac
  local lexl reall
  lexl=$(lower "$lex") || emit_deny "$DENY_UNREAD"
  reall=$(lower "$real") || emit_deny "$DENY_UNREAD"
  [ -n "$lexl" ] && [ -n "$reall" ] || emit_deny "$DENY_UNREAD"
  for c in "${dirs[@]}"; do
    d=$(phys "$(norm "$c")") || emit_deny "$DENY_UNREAD"
    d=$(lower "$d") || emit_deny "$DENY_UNREAD"
    cl=$(lower "$(norm "$c")") || emit_deny "$DENY_UNREAD"
    [ -n "$d" ] && [ -n "$cl" ] || emit_deny "$DENY_UNREAD"
    if under "$reall" "$d" || under "$lexl" "$d" || under "$reall" "$cl" || under "$lexl" "$cl"; then
      emit_deny "$DENY_HOOKS"
    fi
  done
  return 0
}

emit_deny_internal() {
  emit_deny 'the guard stopped before it reached a decision (an internal error or a signal), so this call could not be checked - refusing (fail closed).'
}
trap 'emit_deny_internal' HUP INT TERM
trap 'exit 0' PIPE

OUT=$(main "$@")
RC=$?
if [ -n "$OUT" ]; then
  printf '%s\n' "$OUT"
elif [ "$RC" != 0 ]; then
  emit_deny_internal
fi
exit 0
