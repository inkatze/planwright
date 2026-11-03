# shellcheck shell=sh
# proto.sh — the hardened-shell candidate's shared-library seam (sourced).
#
# Prototype scope: it serves this bake-off's two entry points and nothing
# else. It loads the production primitives rather than copying them, so the
# shell candidate is measured on the code the tree already runs: the lock is
# scripts/lock-lib.sh, and the parser is the shared spec grammar in
# scripts/spec-parse.sh, read in one awk pass per file (the batched read)
# rather than a process per line or per key.
#
# The caller sets proto_lib to this file's directory before sourcing it. The
# production libraries are found from there, seven levels up, so a delivery
# copy must keep the same relative layout.
#
# POSIX sh; no external command runs at load time.

proto_scripts=$proto_lib/../../../../../../../scripts
proto_nl='
'

# proto_load <library> — source one production library, failing closed (2)
# when it is missing or unreadable rather than running without it.
proto_load() {
  if [ ! -f "$proto_scripts/$1" ] || [ ! -r "$proto_scripts/$1" ]; then
    printf '%s\n' "proto: $1 is missing or unreadable under $proto_scripts" >&2
    return 2
  fi
  # shellcheck source=/dev/null
  . "$proto_scripts/$1" || return 2
}

proto_lock_usage() {
  printf '%s\n' 'usage: lock try-for <path> <pid> | owner <path> | alive <token> | release <path> <token>' >&2
  return 2
}

# proto_lock <verb> <args>... — the bake-off's lock contract over lock-lib.sh.
#   try-for <path> <pid>     one attempt on <pid>'s behalf; prints a
#                            `broken <token>` line per dead owner it removed,
#                            then `held <owner-field>` read back off the link
#   owner <path>             prints the holder's token; 1 when nobody holds it
#   alive <token>            0 the token's owner is running, 1 it is not
#   release <path> <token>   the ownership-verified cross-process release
# Exit codes are lock-lib's: 0 success, 1 the lock stayed with a holder, 2 a
# real error (usage included).
proto_lock() {
  proto_load lock-lib.sh || return 2
  case ${1:-} in
    try-for)
      [ "$#" -eq 3 ] || {
        proto_lock_usage
        return
      }
      pw_lock_acquire_for "$2" "$3" 1
      proto_rc=$?
      proto_rest=$PW_LOCK_BROKEN
      while [ -n "$proto_rest" ]; do
        case $proto_rest in
          *"$proto_nl"*)
            proto_line=${proto_rest%%"$proto_nl"*}
            proto_rest=${proto_rest#*"$proto_nl"}
            ;;
          *)
            proto_line=$proto_rest
            proto_rest=''
            ;;
        esac
        printf 'broken %s\n' "$proto_line"
      done
      [ "$proto_rc" -eq 0 ] || return "$proto_rc"
      proto_owner=$(pw_lock_owner "$2")
      printf 'held %s\n' "${proto_owner%%-*}"
      ;;
    owner)
      [ "$#" -eq 2 ] || {
        proto_lock_usage
        return
      }
      proto_owner=$(pw_lock_owner "$2")
      [ -n "$proto_owner" ] || return 1
      printf '%s\n' "$proto_owner"
      ;;
    alive)
      [ "$#" -eq 2 ] || {
        proto_lock_usage
        return
      }
      pw_lock_owner_alive "$2"
      ;;
    release)
      [ "$#" -eq 3 ] || {
        proto_lock_usage
        return
      }
      pw_lock_release_token "$2" "$3"
      ;;
    *) proto_lock_usage ;;
  esac
}

# proto_deps <tasks.md> — the bake-off's dependency-line contract over the
# shared grammar: a `TASK<TAB><id>` record per conforming task heading and a
# `TASKDEP<TAB><id><TAB><dep>` record per dependency token, in source order.
# 0 parsed, 2 usage or an unreadable file, 3 the file ends inside an open
# column-0 fence (the records before it are already on stdout).
proto_deps() {
  if [ "$#" -ne 1 ]; then
    printf '%s\n' 'usage: deps <tasks.md>' >&2
    return 2
  fi
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then
    printf '%s\n' "deps: $1 is not a readable file" >&2
    return 2
  fi
  proto_load spec-parse.sh || return 2
  # shellcheck disable=SC2154 # both are defined by spec-parse.sh
  LC_ALL=C awk "$spec_parse_awk_fence$spec_parse_awk_grammar"'
    /^## / { cur = ""; next }
    spec_parse_is_task_heading($0) {
      cur = spec_parse_task_id($0)
      if (cur != "") printf "TASK\t%s\n", cur
      next
    }
    /^### / { cur = ""; next }
    cur != "" && spec_parse_task_field($0) == "dependencies" {
      n = split(spec_parse_dep_ids($0), a, " ")
      for (i = 1; i <= n; i++) printf "TASKDEP\t%s\t%s\n", cur, a[i]
    }
    END { spec_parse__fence_eof() }
  ' <"$1"
}
