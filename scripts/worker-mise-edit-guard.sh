#!/bin/sh
# worker-mise-edit-guard.sh — the PreToolUse hook an opted-in launch's
# generated profile adds for the file tools: it refuses an opted-in name that
# lies outside the worker's own worktree. The names are the mise task files
# (mise.toml, .mise.toml, mise-tasks/, .mise-tasks/ at any depth) and, for a
# launch given --lefthook-edit, the lefthook config (lefthook.<ext>, lefthook/
# at any depth, any letter case). A path rule cannot say "everywhere but
# here", and a deny rule beats every allow, so this is the half of the
# opt-in's boundary the profile's literal ancestor denies leave open.
#
# Usage: worker-mise-edit-guard.sh <worktree> [mise] [lefthook] < <PreToolUse payload>
#   The name sets to judge; none given means mise. A word that is neither
#   judges both.
# Output: a permissionDecision "deny" with its reason, or nothing (defer).
#   A named path is judged by its spelling and by where it resolves (`..`
#   components, symlinked directories and a symlinked leaf included); it is
#   allowed only when both lie inside the worktree. What cannot be read (no
#   jq, a payload that is not JSON, a field holding the payload separator, an
#   unusable worktree argument) refuses the call rather than letting a named
#   path through, and a path that cannot be
#   resolved (a symlink chain past the bound, an unreadable folder) is
#   refused whatever its spelling, since it may resolve to a named file.
# Exit: 0 always. POSIX sh; jq reads the payload.
set -uf
LC_ALL=C
export LC_ALL
unset CDPATH

deny() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"planwright worker-mise-edit-guard: a mise task file or lefthook config this launch may edit (mise.toml, .mise.toml, mise-tasks/, .mise-tasks/, lefthook.<ext>, lefthook/) is editable only inside this worktree; this path lies outside it or resolves outside it."}}'
  exit 0
}

# The name sets to judge: the arguments after the worktree.
want_mise=0
want_lefthook=0
wt_arg=${1:-}
[ "$#" -eq 0 ] || shift
[ "$#" -gt 0 ] || set -- mise
for _w in "$@"; do
  case $_w in
    mise) want_mise=1 ;;
    lefthook) want_lefthook=1 ;;
    *)
      want_mise=1
      want_lefthook=1
      ;;
  esac
done

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
        *)
          # The link's parent may itself be a symlinked directory: a relative
          # target resolves from the parent's real location.
          _par=$(cd -P -- "${_cur%/*}/" 2>/dev/null && pwd -P) || return 1
          _p=$(norm "$_par/$_t$_rest")
          ;;
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

# is_optin_name <normalized path>: some component is a name of a judged set: a mise
# task-file name, or a lefthook config name (`lefthook` or `lefthook.*`, any
# letter case, since a case-insensitive filesystem reads them alike).
is_optin_name() {
  if [ "$want_mise" = 1 ]; then
    case $1 in
      */mise.toml | */.mise.toml | */mise-tasks | */.mise-tasks | */mise.toml/* | */.mise.toml/* | */mise-tasks/* | */.mise-tasks/*) return 0 ;;
    esac
  fi
  if [ "$want_lefthook" = 1 ]; then
    case $1 in
      */[Ll][Ee][Ff][Tt][Hh][Oo][Oo][Kk] | */[Ll][Ee][Ff][Tt][Hh][Oo][Oo][Kk]/* | */[Ll][Ee][Ff][Tt][Hh][Oo][Oo][Kk].*) return 0 ;;
    esac
  fi
  return 1
}

command -v jq >/dev/null 2>&1 || deny
payload=$(cat) || deny
fields=$(printf '%s' "$payload" | jq -r '
  (.tool_input.file_path // .tool_input.notebook_path // "") as $p
  | [(.tool_name // ""), $p, (.cwd // "")]
  | if any(.[]; contains("\u0001")) then error("separator in a field") else join("\u0001") end' 2>/dev/null) || deny
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
  # The file tools may expand a leading ~ to the home folder, a place this
  # hook cannot resolve; a task-named path there is never inside the worktree.
  '~' | '~'/*) is_optin_name "/$path" && deny || exit 0 ;;
  /*) abs=$path ;;
  *) [ -n "$cwd" ] && abs=$cwd/$path || abs=$path ;;
esac
case $abs in
  /*) ;;
  *) is_optin_name "/$abs" && deny || exit 0 ;;
esac
lex=$(norm "$abs")
real=$(phys "$lex") || deny
[ -n "$real" ] || deny
is_optin_name "$lex" || { [ "$real" != "$lex" ] && is_optin_name "$real"; } || exit 0

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
