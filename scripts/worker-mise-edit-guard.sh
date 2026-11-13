#!/bin/sh
# worker-mise-edit-guard.sh — the PreToolUse hook an opted-in launch's
# generated profile adds for the file tools: it refuses a mise task-file path
# (mise.toml, .mise.toml, mise-tasks/, .mise-tasks/ at any depth) that lies
# outside the worker's own worktree. A path rule cannot say "everywhere but
# here", and a deny rule beats every allow, so this is the half of the
# opt-in's boundary the profile's literal ancestor denies leave open.
#
# Usage: worker-mise-edit-guard.sh <worktree> < <PreToolUse payload>
# Output: a permissionDecision "deny" with its reason, or nothing (defer).
#   A task path is judged by its spelling and by where it resolves (`..`
#   components, symlinked directories and a symlinked leaf included); it is
#   allowed only when both lie inside the worktree. What cannot be read (no
#   jq, a payload that is not JSON, an unusable worktree argument) refuses
#   a task path rather than letting it through, and a path that cannot be
#   resolved (a symlink chain past the bound, an unreadable folder) is
#   refused whatever its spelling, since it may resolve to a task file.
# Exit: 0 always. POSIX sh; jq reads the payload.
set -uf
LC_ALL=C
export LC_ALL
unset CDPATH

deny() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"planwright worker-mise-edit-guard: a mise task file (mise.toml, .mise.toml, mise-tasks/, .mise-tasks/) may be edited only inside this worktree; this path lies outside it or resolves outside it."}}'
  exit 0
}

# norm <absolute path>: the path with `.`, `..` and empty components folded.
norm() {
  _out=''
  _old=$IFS
  IFS=/
  # shellcheck disable=SC2086
  set -- $1
  IFS=$_old
  for _c in "$@"; do
    case $_c in
      '' | .) ;;
      ..) _out=${_out%/*} ;;
      *) _out="$_out/$_c" ;;
    esac
  done
  printf '%s\n' "${_out:-/}"
}

# phys <normalized absolute path>: where the path resolves, symlinked
# directories and a symlinked leaf followed; the part that does not exist yet
# is appended as spelled.
phys() {
  _p=$1
  _n=0
  while :; do
    _n=$((_n + 1))
    [ "$_n" -le 40 ] || return 1
    _rest=''
    _cur=$_p
    while [ ! -e "$_cur" ] && [ ! -L "$_cur" ] && [ "$_cur" != / ]; do
      _rest="/${_cur##*/}$_rest"
      _cur=${_cur%/*}
      [ -n "$_cur" ] || _cur=/
    done
    if [ -L "$_cur" ]; then
      _t=$(readlink -- "$_cur") || return 1
      case $_t in
        /*) _p=$(norm "$_t$_rest") ;;
        *) _p=$(norm "${_cur%/*}/$_t$_rest") ;;
      esac
      continue
    fi
    if [ -d "$_cur" ]; then
      _d=$(cd -P -- "$_cur" 2>/dev/null && pwd -P) || return 1
      _base=''
    else
      _d=$(cd -P -- "${_cur%/*}" 2>/dev/null && pwd -P) || return 1
      _base="/${_cur##*/}"
    fi
    case $_d in
      /) _d='' ;;
    esac
    norm "$_d$_base$_rest"
    return 0
  done
}

# is_task <normalized path>: some component is a mise task-file name.
is_task() {
  case $1 in
    */mise.toml | */.mise.toml | */mise-tasks | */.mise-tasks | */mise.toml/* | */.mise.toml/* | */mise-tasks/* | */.mise-tasks/*) return 0 ;;
  esac
  return 1
}

command -v jq >/dev/null 2>&1 || deny
payload=$(cat) || deny
fields=$(printf '%s' "$payload" | jq -r '
  (.tool_input.file_path // .tool_input.notebook_path // "") as $p
  | [(.tool_name // ""), $p, (.cwd // "")] | join("\u0001")' 2>/dev/null) || deny
tool=${fields%%"$(printf '\001')"*}
rest=${fields#*"$(printf '\001')"}
path=${rest%%"$(printf '\001')"*}
cwd=${rest#*"$(printf '\001')"}

case $tool in
  Edit | Write | MultiEdit | NotebookEdit) ;;
  *) exit 0 ;;
esac
[ -n "$path" ] || exit 0

case $path in
  /*) abs=$path ;;
  *) [ -n "$cwd" ] && abs=$cwd/$path || abs=$path ;;
esac
case $abs in
  /*) ;;
  *) is_task "/$abs" && deny || exit 0 ;;
esac
lex=$(norm "$abs")
real=$(phys "$lex") || deny
[ -n "$real" ] || deny
is_task "$lex" || is_task "$real" || exit 0

wt_arg=${1:-}
[ -n "$wt_arg" ] || deny
wt=$(cd -P -- "$wt_arg" 2>/dev/null && pwd -P) || deny

inside() {
  case $1 in
    "$wt"/*) return 0 ;;
  esac
  return 1
}
if inside "$real"; then
  if inside "$lex"; then
    exit 0
  fi
  # The spelling may use another name for the same folder (the working
  # directory resolves to the worktree): accept it only through that.
  if [ -n "$cwd" ]; then
    cwd_real=$(cd -P -- "$cwd" 2>/dev/null && pwd -P) || cwd_real=''
    if [ "$cwd_real" = "$wt" ]; then
      case $lex in
        "$(norm "$cwd")"/*) exit 0 ;;
      esac
    fi
  fi
fi
deny
