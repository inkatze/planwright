# shellcheck shell=sh
# untrusted-git-lib.sh — git reads of a checkout the calling session does not
# own (sourced, never executed). Portable POSIX sh; needs git 2.31, the first
# with GIT_CONFIG_COUNT.
#
# A worker writes its checkout's configuration and attributes, so a program it
# plants (fsmonitor, hook, clean or process filter, diff or merge driver,
# textconv, external diff, signature program, remote helper) would run in the
# reader's session. These turn them off for one git, or for every git a shell
# starts:
#
#   pw_untrusted_git [-C <dir>] <args>   one git run, the settings in force
#   pw_untrusted_git_env [<dir>...]      export them; each <dir> is a checkout
#                                        to read (default: the current one)
#
# Both return 128, git's own error status, when a checkout's configuration
# cannot be read: nothing is set and no git runs, and a caller that reads
# status 1 as "no" (check-ignore, diff --quiet) is not misled. An exported
# environment also sets PW_UNTRUSTED_GIT=1, which scripts that scrub git's
# environment on entry honour.

# The settings ride GIT_CONFIG_COUNT, which outranks the repository's own
# configuration. A driver cannot be switched off by wildcard, so the drivers in
# the checkout's local and worktree configuration (the scopes a worker writes)
# are listed with `git config` and each is blanked: an empty clean, smudge or
# process command runs nothing, and `required` is cleared so git does not die
# over the missing filter. A file its filter would have normalised then reads as
# changed: the dirty side, never a false clean. An empty diff command or
# textconv runs nothing but fails the diff, so a diff caller also passes
# --no-ext-diff and --no-textconv, which skip the driver outright. A merge
# driver is set to `false`, a conflict.

# Not covered, and a reader must not assume otherwise:
#   - a driver in the operator's global or system configuration stays on: that
#     is code the operator chose, run on bytes the worker wrote;
#   - the drivers are listed when this runs, so one a worker adds between that
#     and the guarded git is not blanked (pw_untrusted_git lists right before
#     each git; an exported environment lasts as long as its script);
#   - a submodule's own configuration is not listed, and status asks each
#     submodule for its state.

pw_untrusted_git_env() {
  # An inherited repository selector would point git away from the checkout
  # the caller names, and inherited configuration would ride along.
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CONFIG_PARAMETERS GIT_EXTERNAL_DIFF
  # The caller's own GIT_CONFIG_COUNT pairs (a safe.directory, an identity)
  # are kept and ours follow them, so ours win; a count this library set on
  # an earlier call, or one that is not a number, is dropped.
  ug_kept=0
  if [ -z "${PW_UNTRUSTED_GIT:-}" ]; then
    case ${GIT_CONFIG_COUNT:-} in
      '' | *[!0-9]*) ;;
      *) ug_kept=$GIT_CONFIG_COUNT ;;
    esac
  fi
  unset GIT_CONFIG_COUNT
  [ $# -gt 0 ] || set -- .
  ug_list=''
  for ug_dir in "$@"; do
    ug_rc=0
    ug_one=$(git -C "$ug_dir" config --show-scope --name-only --get-regexp \
      '^(filter\..+\.(clean|smudge|process|required)|merge\..+\.driver|diff\.external|diff\..+\.(command|textconv))$' \
      2>/dev/null) || ug_rc=$?
    # 1 is "no such key"; anything else is a checkout git cannot read.
    [ "$ug_rc" -le 1 ] || return 128
    ug_list=$ug_list$ug_one'
'
  done

  ug_n=$ug_kept
  _pw_ug_add core.fsmonitor false
  _pw_ug_add core.hooksPath /dev/null
  _pw_ug_add protocol.allow never
  _pw_ug_add log.showSignature false
  _pw_ug_add gpg.program /dev/null
  _pw_ug_add gpg.openpgp.program /dev/null
  _pw_ug_add gpg.x509.program /dev/null
  _pw_ug_add gpg.ssh.program /dev/null
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
    # The plain diff.external variable and a driver named `external` share a
    # prefix, so the first is told apart.
    case $ug_key in
      diff.external)
        ug_base=diff.external
        ug_tok=variable:diff.external
        ;;
      *)
        ug_base=${ug_key%.*}
        ug_tok=$ug_base
        ;;
    esac
    case $ug_seen in
      *"$ug_nl$ug_tok$ug_nl"*) continue ;;
    esac
    ug_seen=$ug_seen$ug_tok$ug_nl
    case $ug_key in
      filter.*)
        _pw_ug_add "$ug_base.clean" ''
        _pw_ug_add "$ug_base.smudge" ''
        _pw_ug_add "$ug_base.process" ''
        _pw_ug_add "$ug_base.required" false
        ;;
      merge.*) _pw_ug_add "$ug_base.driver" false ;;
      diff.external) _pw_ug_add diff.external '' ;;
      diff.*)
        _pw_ug_add "$ug_base.command" ''
        _pw_ug_add "$ug_base.textconv" ''
        ;;
    esac
  done <<EOF
$ug_list
EOF
  export GIT_CONFIG_COUNT=$ug_n
  GIT_NO_LAZY_FETCH=1
  GIT_PAGER='cat'
  PW_UNTRUSTED_GIT=1
  export GIT_NO_LAZY_FETCH GIT_PAGER PW_UNTRUSTED_GIT
}

# _pw_ug_add <key> <value>: the next GIT_CONFIG_KEY_n / GIT_CONFIG_VALUE_n pair.
_pw_ug_add() {
  export "GIT_CONFIG_KEY_$ug_n=$1" "GIT_CONFIG_VALUE_$ug_n=$2"
  ug_n=$((ug_n + 1))
}

pw_untrusted_git() {
  case ${1:-} in
    -C) (pw_untrusted_git_env "${2:-}" && git "$@") ;;
    *) (pw_untrusted_git_env && git "$@") ;;
  esac
}
