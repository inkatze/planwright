# shellcheck shell=sh
# untrusted-git-lib.sh — git reads of a checkout the calling session does not
# own (sourced, never executed). Portable POSIX sh.
#
# A worker writes its checkout's configuration and attributes, so a program it
# plants (fsmonitor, hook, clean or process filter, diff driver, textconv,
# external diff, signature program, remote helper) would run in the reader's
# session. These turn them off for one git, or for every git a shell starts:
#
#   pw_untrusted_git [-C <dir>] <args>   one git run, the settings in force
#   pw_untrusted_git_env [<dir>...]      export them; each <dir> is a checkout
#                                        to read (default: the current one)

# The settings ride GIT_CONFIG_COUNT, which outranks the repository's own
# configuration. A driver cannot be switched off by wildcard, so the drivers in
# the checkout's local and worktree configuration (the scopes a worker writes)
# are listed with `git config` and each is blanked: an empty clean, smudge or
# process command runs nothing, and `required` is cleared so git does not die
# over the missing filter. A file its filter would have normalised then reads as
# changed: the dirty side, never a false clean. An empty diff command or
# textconv runs nothing but fails the diff, so a diff caller also passes
# --no-ext-diff and --no-textconv, which skip the driver outright.

# Not covered, and a reader must not assume otherwise:
#   - a driver in the operator's global or system configuration stays on: that
#     is code the operator chose, run on bytes the worker wrote;
#   - the drivers are listed when this runs, so one a worker adds between that
#     and the guarded git is not blanked (pw_untrusted_git lists right before
#     each git; an exported environment lasts as long as its script);
#   - a submodule's own configuration is not listed, and status asks each
#     submodule for its state.
# A configuration git cannot read returns 1 and sets nothing, so a `&&` chain
# does not go on to run git unguarded.

pw_untrusted_git_env() {
  # An inherited repository selector would point git away from the checkout
  # the caller names, and inherited configuration would ride along.
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CONFIG_PARAMETERS GIT_EXTERNAL_DIFF
  [ $# -gt 0 ] || set -- .
  ug_list=''
  for ug_dir in "$@"; do
    ug_rc=0
    ug_one=$(git -C "$ug_dir" config --show-scope --name-only --get-regexp \
      '^(filter\..+\.(clean|smudge|process|required)|diff\.external|diff\..+\.(command|textconv))$' \
      2>/dev/null) || ug_rc=$?
    # 1 is "no such key"; anything else is a checkout git cannot read.
    [ "$ug_rc" -le 1 ] || return 1
    ug_list=$ug_list$ug_one'
'
  done

  ug_n=0
  ug_add core.fsmonitor false
  ug_add core.hooksPath /dev/null
  ug_add protocol.allow never
  ug_add log.showSignature false
  ug_add gpg.program /dev/null
  ug_add gpg.openpgp.program /dev/null
  ug_add gpg.x509.program /dev/null
  ug_add gpg.ssh.program /dev/null
  ug_nl='
'
  ug_tab='	'
  ug_seen=$ug_nl
  while IFS= read -r ug_line; do
    [ -n "$ug_line" ] || continue
    case ${ug_line%%"$ug_tab"*} in
      local | worktree) ;;
      *) continue ;;
    esac
    ug_key=${ug_line#*"$ug_tab"}
    case $ug_key in
      diff.external) ug_base=diff.external ;;
      *) ug_base=${ug_key%.*} ;;
    esac
    case $ug_seen in
      *"$ug_nl$ug_base$ug_nl"*) continue ;;
    esac
    ug_seen=$ug_seen$ug_base$ug_nl
    case $ug_key in
      filter.*)
        ug_add "$ug_base.clean" ''
        ug_add "$ug_base.smudge" ''
        ug_add "$ug_base.process" ''
        ug_add "$ug_base.required" false
        ;;
      diff.external) ug_add diff.external '' ;;
      diff.*)
        ug_add "$ug_base.command" ''
        ug_add "$ug_base.textconv" ''
        ;;
    esac
  done <<EOF
$ug_list
EOF
  export GIT_CONFIG_COUNT=$ug_n
  GIT_NO_LAZY_FETCH=1
  GIT_PAGER='cat'
  export GIT_NO_LAZY_FETCH GIT_PAGER
  PW_UNTRUSTED_GIT=1
  export PW_UNTRUSTED_GIT
}

# ug_add <key> <value>: the next GIT_CONFIG_KEY_n / GIT_CONFIG_VALUE_n pair.
ug_add() {
  export "GIT_CONFIG_KEY_$ug_n=$1" "GIT_CONFIG_VALUE_$ug_n=$2"
  ug_n=$((ug_n + 1))
}

pw_untrusted_git() {
  case ${1:-} in
    -C) (pw_untrusted_git_env "${2:-}" && git "$@") ;;
    *) (pw_untrusted_git_env && git "$@") ;;
  esac
}
