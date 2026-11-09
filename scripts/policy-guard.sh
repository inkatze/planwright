#!/usr/bin/env bash
# policy-guard.sh — the deny-emitting PreToolUse hook that enforces the
# human-gates policy knobs for the tier a session runs under
# (doctrine/human-gates.md states the list and each rule's kind).
#
# Usage, as the tier profiles wire it:
#   policy-guard.sh <tier> <surface>
# <tier> is `worker`, `tower` or `mission-control`, carried by the settings
# profile the session runs under; any other value, or none, is a session with
# no tier profile, which is outside this guard's jurisdiction, so it defers
# with no read.
# <surface> is `bash`, `mcp` or `file`: which matcher fired, so a payload on
# the MCP matcher that lost its tool_name, or names another tool, still
# denies. `file` (the Edit, Write, MultiEdit and NotebookEdit matcher) is the
# mission-control tier's alone and defers at the others. A payload that
# cannot be read denies at every surface.
#
# THE MISSION-CONTROL TIER is the tower tier with three differences, each
# denying with no read. It runs no git mutation: a git subcommand outside a
# read-only set (the inspection commands and the listing forms of branch, tag,
# stash, worktree, remote and config, an unknown option counting as a write),
# a read flag that writes a file or runs a program (any abbreviation git
# accepts), -c configuration, a GIT_* variable or a moved exec path, an alias
# or external subcommand, a wrapped git text outside the always-read set, a gh
# api branch write, and the gh commands that write a branch on the host or a
# repository locally (pr checkout and update-branch, the repo and release
# writes). It writes no posture file and no repository: a file-tool path that
# names a settings, MCP or planwright configuration file or a shipped profile,
# lies under a .claude hooks, plugins, agents, skills, commands or planwright
# directory, or lies inside a work tree or bare repository denies; in Bash, a
# command naming a posture file passes only as a plain read, and a word or
# redirect target that could expand into one denies (the directories are the
# file surface's alone: an installed planwright script runs from under
# .claude/plugins). Its flip, for a PR of the repository it runs in only,
# follows ready_flip_policy: unit-owner defers to the ready-guard's currency
# check, human asks the operator; the MCP flip stays denied whole, as the
# tower's is.
#
# MODALITY. Like the ready-guard and unlike the allow-only command guards, this
# guard emits deny, so a missed deny defeats it and a false deny blocks work;
# its one ask is the mission-control flip under ready_flip_policy: human.
# Every refusal names its remedy.
#
# ORDER. The intercepted call is classified first, with no knob read: a call
# that performs none of the acts below defers with no read, and a call no
# value or protected set can change (a force or bulk push, the undo, the PR
# merge, the tower's refusals, a `gh api` act, a request the guard cannot
# read) denies before any read. Only then does the guard read what the matched
# act needs (its knob, the protected set) through
# scripts/resolve-policy-knob.sh, always from the primary checkout of the
# repository the act runs in (from git's common dir, so a worker's own
# worktree config governs nothing until it merges; no primary checkout
# denies), each read bounded by
# PLANWRIGHT_POLICY_GUARD_TIMEOUT seconds (default 10) and the upstream
# refresh by PLANWRIGHT_POLICY_GUARD_FETCH_TIMEOUT (default 20), each with a
# two-second kill grace, and all of them by a deadline for the whole call;
# any read failure denies. A reserved act after an earlier segment of the same
# command that changes git configuration, the checked-out branch, or refs (or,
# for a rewrite, that pushes, fetches, or makes a commit) is refused: every
# segment is checked against the state as it stands before the command runs.
# A guard that crashes or is signalled under a tier denies rather than leaving
# the call undecided.
#
# ACTS.
#   flip        `gh pr ready <n>` and the MCP draft->ready transition.
#               tower: deny. worker: ready_flip_policy (unit-owner defers, so
#               the ready-guard's currency check runs next). mission-control:
#               unit-owner defers as a worker's does, and human asks the
#               operator, whose yes is the request to flip, the reason naming
#               the setting that settles it; a flip naming another repository
#               (--repo, a PR URL, GH_REPO, GH_HOST) denies.
#   undo        `gh pr ready --undo` and the MCP ready->draft transition: deny,
#               the corrective helper being the only sanctioned re-draft.
#               Running scripts/request-reviewer.sh performs no act here, so
#               it defers at every tier: its own re-draft runs below this
#               hook, only on a PR it read as a draft before its own request.
#   pr-merge    `gh pr merge`: deny; the merge helper is the only agent path.
#   merge-helper  running scripts/merge-admitted.sh: a command word, or a
#               shell's script argument, whose file name starts with the
#               `merge-ad` stem, matches merge-admitted.sh as a glob, or
#               carries an expansion or brace; or a shell whose script is a
#               bare expansion or stdin in a command naming the stem. tower:
#               deny. worker: merge_policy (policy-class defers; the helper
#               evaluates the class and re-reads the policy itself). Its own gh
#               calls run below this hook, so the invocation is what the guard
#               sees; a wrapper or an unanalyzable command naming the stem
#               denies. A name assembled by a command substitution or ANSI-C
#               quoting outside the stem, a renamed copy, or a link under
#               another name is the accepted residual. Running
#               scripts/ready-flip.sh with `--for-merge` (its flag for the
#               helper's own flip), or with a word that could expand into it
#               (a brace, or an expansion that is not the value of one of its
#               value-taking options), denies at every tier with no read, as
#               does the flag after a script name the guard cannot resolve; a
#               renamed copy of ready-flip.sh, and a flag carried only in an
#               expansion after a script name that is itself an expansion,
#               are the same residual.
#   base-merge  `git merge`, `git pull` in merge mode. tower: deny. worker:
#               worker_base_merge, then the current branch must be the session's
#               unit branch outside the protected set and every source the PR
#               base or the unit branch's own branch on the base remote. When
#               an --ff-only spelling is refused at the tower tier or for
#               running off the unit branch, the reason also names
#               scripts/main-currency.sh ff-primary, the sanctioned way to
#               fast-forward a primary checkout's default branch.
#   rewrite     amend, `--squash`, `--fixup`, rebase, `git pull` in rebase
#               mode. tower: deny. worker: unpushed_rewrite, then the unit
#               branch rule, then the never-pushed check: the upstream tracking
#               ref is refreshed and no remote-tracking ref may contain a
#               rewritten commit. A rebase with -x/--exec denies: its
#               command runs below this hook. A commit with an expansion among
#               its options denies: it could spell an amend.
#   push       a force or bulk push denies; every other push reads the
#               protected set and denies a target inside it.
#   gh api      classified by the act it performs, its names matched in any
#               field: the flip, undo, PR merge, base merge, and forced ref
#               update deny at every tier with no read; a ref, contents,
#               commit, or rename write to a named branch reads only the
#               protected set (a rename checks both names; a contents write
#               naming no branch denies, since it writes the default branch);
#               a request the guard cannot read (a field from a file or stdin,
#               an --input body, a non-literal endpoint, method, or query on a
#               write, a rename with no literal new name, an unknown flag)
#               denies before any read; anything else defers.
#   force-push helper  running scripts/tower-force-push.sh. worker: deny,
#               with no read. tower: defer, so it reaches the permission
#               prompt (the tower's command guard never approves it).
#   ref-surgery tower only: `git filter-branch`, `git filter-repo`, a forced
#               `git branch` (-f, --force, and the -M and -C force shorthands)
#               outside delete mode, and `git update-ref` deny with no read.
#   branch-move tower only, in every checkout including the tower's own:
#               `git checkout`, `git switch`, and `git reset` in every form
#               (--hard, --soft, and path restores included); a `git branch`
#               rename or copy (-m, -c, --move, --copy; -M and -C deny as a
#               forced branch) outside delete mode; a `git symbolic-ref` write
#               (two names, or -d/--delete); a `git fetch` refspec whose
#               destination is a local branch (a bare name, heads/, or
#               refs/heads/) or a glob that can reach one, a non-literal
#               refspec, --stdin, and --refmap with a value; a `git fetch` or
#               `git remote` beside -c, a GIT_* variable, or a config or
#               remote change in the same command; a `git remote add` fetching
#               into a fetch mirror; `gh pr checkout`, `gh pr co`, the
#               top-level `gh co`, and `gh repo sync`; and a gh or `git
#               remote` subcommand given through an expansion. All deny with
#               no read. Residual: a refspec already stored in
#               remote.<r>.fetch is not read, so a plain `git fetch <r>` or
#               `git remote update` follows whatever it maps.
#   stash-write tower only: every `git stash` form except `stash list` and
#               `stash show`, the stack being shared by every worktree of a
#               clone; deny with no read.
#   worktree    tower only: `git worktree add`, `remove`, or `move` with
#               --force, `add` with --detach, and `add -B` on any branch,
#               deny with no read; an `add`
#               whose new branch, or with none its commit-ish or (with
#               neither) its path's last component, names a branch reads the
#               protected set and denies a hit, a ref or remote-tracking form
#               read as the branch it names; that name or path given through an
#               expansion after `--` denies.
#   mcp-write   tower only: the GitHub MCP merge, update, branch-update,
#               create, push-files, create-or-update-file, and delete-file
#               tools deny whatever their arguments.
# At the tower tier a git alias expanding to one of the tower-only
# subcommands denies too, and so does any subcommand that is not a builtin
# where the guard cannot read the alias: in a command it cannot parse, or in
# a repository or directory it cannot follow. An expansion among a tower
# act's options denies, since it could spell the refused option. In a command
# it cannot parse, the guard also refuses git whose subcommand is quoted,
# escaped, or expanded, or whose global options carry a quote or an escape,
# and a fetch or `git remote` beside -c, a GIT_* assignment, or a config or
# remote change. These acts
# cover every
# entry of config/tower-settings.json's deny list, which
# tests/fixtures/tower-deny-acts.tsv maps entry by entry, so the plugin-wired
# floor (scripts/tower-session.sh) holds in a tower launched without that
# profile.
# Every segment of a compound command is classified and the strictest verdict
# wins.
#
# THE UNIT BRANCH. A session owns the checkout at its project directory
# (CLAUDE_PROJECT_DIR, which Claude Code sets for every hook) and the branch it
# holds, when that is a task or flight branch; a session launched at a primary
# checkout holding some other branch (main, say) owns, for a base sync only,
# the linked worktree of that repository its shell is in, as the harness
# reported it (unit_branch_or_deny). Every act must run in the owned checkout
# itself.
# The PR base is the default branch of the unit branch's remote as recorded
# locally (`refs/remotes/<remote>/HEAD`, else `main`): the guard never queries
# the host for it, so a unit whose PR targets another branch syncs through
# scripts/converge-sync-main.sh.
#
# SECURITY. No model in the decision path. The payload is inert data: never
# evaluated, expanded, or executed. Identifiers reach git as argv after a
# grammar check. Untrusted text echoed into a reason is stripped of control
# bytes (scripts/echo-safety.sh) and the decision JSON is built by jq.
#
# Bash 3.2 floor, like the ready-guard: the tokenizer needs word arrays.
set -uf
unset CDPATH
LC_ALL=C
export LC_ALL

readonly MAX_PAYLOAD_BYTES=2000000
readonly MAX_CMD_LEN=16384
readonly MCP_TOOL='mcp__github__update_pull_request'
readonly REASON_PREFIX='planwright policy-guard: '

sanitize_printable() {
  _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237' 2>/dev/null) || _sp=''
  if [ -z "$_sp" ] && [ $# -ge 2 ]; then
    _sp=$2
  fi
  printf '%s' "$_sp"
}
GUARD_DIR=$(cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || GUARD_DIR=''
if [ -n "$GUARD_DIR" ] && [ -r "$GUARD_DIR/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$GUARD_DIR/echo-safety.sh"
fi

NL=$'\n'
TAB=$'\t'

# --------------------------------------------------------------------------
# Emitters. One decision object, written last; every exit is 0.

emit_deny() {
  local reason out
  reason="$REASON_PREFIX$(sanitize_printable "$1" 'refusing a reserved act it could not check')"
  # A reason that stops at the refusal gets the general remedy.
  case $reason in
    *'(fail closed).' | *'refusing.')
      reason="$reason Re-issue it as a plain, literal command from your own worktree, or leave the act to the operator."
      ;;
  esac
  out=$(jq -nc --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null) \
    || out=''
  [ -n "$out" ] || emit_deny_constant
  printf '%s\n' "$out"
  exit 0
}

# emit_ask <reason> — leave the call to the operator's own answer.
emit_ask() {
  local out
  out=$(jq -nc --arg r "$REASON_PREFIX$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}' 2>/dev/null) \
    || out=''
  [ -n "$out" ] || emit_deny_constant
  printf '%s\n' "$out"
  exit 0
}

emit_deny_constant() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"planwright policy-guard: jq is missing or not working, so this call, which looks like a reserved act, could not be checked against the policy - refusing (fail closed). Repair jq and retry."}}'
  exit 0
}

# --------------------------------------------------------------------------
# Raw evidence: used only where the precise parse is unavailable (no jq, an
# over-long command, a construct the tokenizer refuses, a wrapper). Crude and
# over-inclusive in the deny direction on purpose.

RE_GH_API='(^|[^[:alnum:]_.-])gh[^[:alnum:]_.-](.*[^[:alnum:]_-])?api([^[:alnum:]_-]|$)'
RE_GH_PR='(^|[^[:alnum:]_.-])gh[^[:alnum:]_.-](.*[^[:alnum:]_-])?pr[^[:alnum:]_-]+(ready|merge)([^[:alnum:]_-]|$)'
# git, its global options (each with at most one value), then the subcommand.
RE_GIT_HEAD='(^|[^[:alnum:]_.-])git([[:space:]]+-[^[:space:]]*([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+'
RE_GIT_ACT="${RE_GIT_HEAD}(merge|pull|rebase|push)([^[:alnum:]_-]|\$)"
RE_GIT_REWRITE="${RE_GIT_HEAD}commit([[:space:]].*)?[[:space:]]--(am|sq|fix)"
# A substitution after `git commit` could produce --amend at run time.
RE_GIT_COMMIT_SUBST="${RE_GIT_HEAD}"'commit([^[:alnum:]_-].*)?(\$\(|`)'
# The tower-only acts, as crudely: any words may stand between git and the
# act (a quoted option value holding a space defeats RE_GIT_HEAD's
# one-value-per-option reading), any short-option cluster carrying the letter
# counts, and any long option starting with it. No pattern carries a `.*`
# between two anchors: each check slices the text after the first match of
# its anchor (raw_after) and looks for the rest there, since a `.*` retried
# from every occurrence grows with the square of the text.
RE_TOWER_GIT_AT='(^|[^[:alnum:]_.-])git[[:space:]]'
RE_TOWER_SURGERY='[[:space:]](update-ref|filter-branch|filter-repo|reset|checkout|switch|symbolic-ref)([^[:alnum:]_-]|$)'
RE_TOWER_BRANCH_AT='[[:space:]]branch[[:space:]]'
RE_TOWER_BRANCH_OPT='[[:space:]](-[[:alnum:]]*[fMCmc]|--(f(o(r(ce?)?)?)?|m(o(ve?)?)?|c(o(py?)?)?)([^[:alnum:]_-]|$))'
RE_TOWER_WORKTREE='[[:space:]]worktree[[:space:]]+(add|remove|move)([^[:alnum:]_-]|$)'
RE_TOWER_FETCH_AT='[[:space:]]fetch([[:space:]]|:)'
RE_TOWER_FETCH_OPT='(:|[[:space:]]--(st|refm))'
RE_TOWER_REMOTE_AT='[[:space:]]remote[[:space:]]'
RE_TOWER_MIRROR='[[:space:]]--mi'
RE_TOWER_STASH='[[:space:]]stash([^[:alnum:]_-]|$)'
RE_TOWER_FETCHES='[[:space:]](fetch|remote)([^[:alnum:]_-]|$)'
RE_TOWER_CFG_CHANGE='[[:space:]](config[[:space:]]|remote[[:space:]]+(add|set-url|set-branches|rename|remove|rm)([^[:alnum:]_-]|$))'
RE_TOWER_GIT_CONFIG='[[:space:]](-c|--config-env)'
RE_TOWER_STASH_READ='[[:space:]]stash[[:blank:]]+(list|show)([^[:alnum:]_-]|$)'
RE_TOWER_GH='(^|[^[:alnum:]_.-])gh[^[:alnum:]_.-](.*[^[:alnum:]_-])?(pr[^[:alnum:]_-](.*[^[:alnum:]_-])?(checkout|co)|repo[^[:alnum:]_-](.*[^[:alnum:]_-])?sync|co)([^[:alnum:]_-]|$)'

# raw_after <text> <ERE> — set RS to the text from the last character of the
# ERE's first match on; 1 when it does not match.
raw_after() {
  local m pre
  [[ $1 =~ $2 ]] || return 1
  m=${BASH_REMATCH[0]}
  pre=${1%%"$m"*}
  RS=${1:$((${#pre} + ${#m} - 1))}
}

# raw_tower_acts <text> — 0 when the text names a tower-only act, or runs a
# fetch or git remote beside configuration that can set its refspec.
raw_tower_acts() {
  local RS RT
  if raw_after "$1" "$RE_TOWER_GIT_AT"; then
    RT=$RS
    if [[ $RT =~ $RE_TOWER_SURGERY ]] || [[ $RT =~ $RE_TOWER_WORKTREE ]] || raw_tower_stash "$RT"; then
      return 0
    fi
    if { raw_after "$RT" "$RE_TOWER_BRANCH_AT" && [[ $RS =~ $RE_TOWER_BRANCH_OPT ]]; } \
      || { raw_after "$RT" "$RE_TOWER_FETCH_AT" && [[ $RS =~ $RE_TOWER_FETCH_OPT ]]; } \
      || { raw_after "$RT" "$RE_TOWER_REMOTE_AT" && [[ $RS =~ $RE_TOWER_MIRROR ]]; }; then
      return 0
    fi
    if [[ $RT =~ $RE_TOWER_FETCHES ]] && { [[ $RT =~ $RE_TOWER_CFG_CHANGE ]] || raw_git_config_beside "$1"; }; then
      return 0
    fi
  fi
  [[ $1 =~ $RE_TOWER_GH ]]
}

# raw_git_config_beside <text> — 0 when the text carries -c configuration
# (its value attached or not) or a GIT_* assignment, either of which can set
# a fetch refspec. -c and -C differ, so this reads case-sensitively whatever
# the caller's nocasematch.
raw_git_config_beside() {
  local nc=0 rc=1
  shopt -q nocasematch && nc=1
  shopt -u nocasematch
  if [[ $1 =~ $RE_TOWER_GIT_CONFIG ]] || [[ $1 =~ $RE_MC_GIT_ENV ]]; then
    rc=0
  fi
  [ "$nc" = 0 ] || shopt -s nocasematch
  return "$rc"
}

# raw_tower_stash <text> — 0 when the text runs a git stash form other than
# `stash list` or `stash show`: each read form is removed first, so a write
# beside a read still counts.
raw_tower_stash() {
  local t=$1 n=0
  while [[ $t =~ $RE_TOWER_STASH_READ ]] && [ "$n" -lt 64 ]; do
    t=${t/"${BASH_REMATCH[0]}"/ }
    n=$((n + 1))
  done
  [ "$n" -lt 64 ] || return 0
  [[ $t =~ $RE_TOWER_STASH ]]
}
# The subcommand is capture group 4: RE_GIT_HEAD holds three groups, and a
# group added there moves it.
RE_GIT_SUB="${RE_GIT_HEAD}([A-Za-z][A-Za-z0-9_-]*)"
# git and its global options as git reads them: only the options that take a
# separate value consume the next word, so a value-less -P cannot swallow an
# alias as its value. The subcommand is capture group 5.
RE_GIT_ALIAS_HEAD='(^|[^[:alnum:]_.-])git([[:space:]]+(-[Cc]|--(git-dir|work-tree|namespace|super-prefix|attr-source|config-env|list-cmds))[[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]*)*[[:space:]]+'
RE_GIT_ALIAS_SUB="${RE_GIT_ALIAS_HEAD}([A-Za-z][A-Za-z0-9_-]*)"
RE_GIT_ALIAS_EXP="${RE_GIT_ALIAS_HEAD}[\"'\$\`\\]"

# raw_tower_alias <text> — 0 when the text runs git with a subcommand that is
# not a builtin (an alias, which the raw fallback cannot expand, could reach
# any tower act), one given through a quote, an escape, or an expansion, or
# one whose global options carry a quote or an escape, which the head cannot
# split reliably. Builtins compare case-sensitively, as git compares them,
# whatever the caller's nocasematch. Bounded, so a long text cannot hold the
# hook.
raw_tower_alias() {
  local t=$1 n=0 m pre sub nc=0 rc=1
  [[ $t =~ $RE_GIT_ALIAS_EXP ]] && return 0
  shopt -q nocasematch && nc=1
  while [[ $t =~ $RE_GIT_ALIAS_SUB ]]; do
    m=${BASH_REMATCH[0]}
    sub=${BASH_REMATCH[5]}
    n=$((n + 1))
    case $m in *[\"\'\\]*) rc=0 ;; esac
    [ "$n" -le 64 ] || rc=0
    shopt -u nocasematch
    case " $GIT_BUILTINS " in *" $sub "*) ;; *) rc=0 ;; esac
    [ "$nc" = 0 ] || shopt -s nocasematch
    [ "$rc" = 1 ] || return 0
    pre=${t%%"$m"*}
    t=${t:$((${#pre} + ${#m}))}
  done
  return 1
}
# Read-form flags that write a file or run a program, any abbreviation git
# accepts included; a wrapped text is not parsed, so these refuse anywhere in
# it beside a git invocation.
RE_MC_GIT_ENV="(^|[[:space:];|&(\"'])GIT_[A-Za-z0-9_]*="
RE_MC_GIT_CONFIG='[[:space:]](-c|--config-env)([[:space:]=]|$)'
RE_MC_GIT_GREP_O='[[:space:]]grep[[:space:]](.*[[:space:]])?-[A-Za-z]*O'
# Prefixes that only these subcommands give an executing meaning: every
# abbreviation of --upload-pack in ls-remote, of --filters in cat-file.
RE_MC_GIT_LSREMOTE_U='[[:space:]]ls-remote[[:space:]](.*[[:space:]])?--u'
RE_MC_GIT_CATFILE_FIL='[[:space:]]cat-file[[:space:]](.*[[:space:]])?--fil'
RE_MC_GIT_EXEC_FLAG='(^|[[:space:]])(--outp[^[:space:]]*|--ext[^[:space:]]*|--textc[^[:space:]]*|--op[^[:space:]]*|--exec[^[:space:]]*)'
RE_MERGE_HELPER='(^|[^[:alnum:]_.-])merge-ad'
RE_FOR_MERGE='(^|[^[:alnum:]_-])--for-merge([^[:alnum:]_-]|$)'

# raw_force_push_call <text> — 0 when the text runs the force-push helper as a
# command: a command's first word, or any word after a wrapper (a shell, sudo,
# env, xargs, an interpreter, ...), where a shell's -c text and eval's text
# start a command of their own. The name anywhere else (a grep pattern, a
# test file's name) runs nothing. Called with nocasematch on: a
# case-insensitive filesystem runs Tower-Force-Push.sh.
raw_force_push_call() {
  local t=$1 w cmd=1 wrapped=0 skip=0
  local -a words
  t=${t//$'\n'/ ; }
  t=${t//;/ ; }
  t=${t//&/ ; }
  t=${t//|/ ; }
  t=${t//(/ ; }
  t=${t//)/ ; }
  t=${t//\`/ ; }
  t=${t//[\"\']/ }
  t=${t//\\/}
  read -r -a words <<<"$t"
  for w in ${words[@]+"${words[@]}"}; do
    if [ "$w" = ';' ]; then
      cmd=1 wrapped=0 skip=0
      continue
    fi
    if [ "$skip" = 1 ]; then
      skip=0
      continue
    fi
    [ "$cmd" = 1 ] || [ "$wrapped" != 0 ] || continue
    [[ ${w##*/} != tower-force-push* ]] || return 0
    case $w in
      '>' | '>>' | '<' | '<<' | [0-9]'>' | [0-9]'>>' | [0-9]'<')
        skip=1
        continue
        ;;
      [0-9]'>'* | '>'* | '<'*) continue ;;
    esac
    if [ "$wrapped" = 2 ] && [[ $w == -*c ]]; then
      cmd=1 wrapped=0
      continue
    fi
    if [[ ${w##*/} == eval ]]; then
      cmd=1 wrapped=0
      continue
    fi
    if [[ ${w##*/} =~ ^(bash|sh|zsh|dash|ksh|mksh|fish|busybox|su|runuser)$ ]]; then
      cmd=0 wrapped=2
    elif [[ ${w##*/} =~ ^(env|sudo|doas|xargs|nohup|nice|ionice|timeout|gtimeout|stdbuf|setsid|chronic|exec|command|builtin|time|watch|flock|unbuffer|caffeinate|strace|ltrace|chroot|unshare|systemd-run|fakeroot|parallel|find|script|ssh|tmux|screen|source|\.|make|python.*|perl|ruby|node|awk|gawk|mawk|nawk|trap|alias)$ ]]; then
      [ "$wrapped" = 2 ] || wrapped=1
      cmd=0
    elif [ "$cmd" = 1 ]; then
      case $w in
        -* | *=* | '{' | '}' | '!' | if | then | elif | else | do | while | until) ;;
        *) cmd=0 ;;
      esac
    fi
  done
  return 1
}

# mc_raw_git_mutation <text> — 0 when an unparsed text runs git with anything
# but an always-read subcommand, with -c configuration, or beside a GIT_*
# assignment. A wrapped text is not parsed, so the listing forms of commands
# that can also write count as writes here.
mc_raw_git_mutation() {
  local t=$1 m sub n=0 rc=1
  [[ $1 =~ $RE_GIT_SUB ]] || return 1
  # The caller holds nocasematch on; -c and -C differ, and so do the flags.
  shopt -u nocasematch
  if [[ $1 =~ $RE_MC_GIT_ENV ]] || [[ $1 =~ $RE_MC_GIT_EXEC_FLAG ]] || [[ $1 =~ $RE_MC_GIT_GREP_O ]] \
    || [[ $1 =~ $RE_MC_GIT_LSREMOTE_U ]] || [[ $1 =~ $RE_MC_GIT_CATFILE_FIL ]]; then
    rc=0
  fi
  shopt -s nocasematch
  [ "$rc" = 1 ] || return 0
  # Bounded, so a long text cannot hold the hook: past the bound it refuses.
  while [[ $t =~ $RE_GIT_SUB ]]; do
    m=${BASH_REMATCH[0]}
    sub=${BASH_REMATCH[4]}
    n=$((n + 1))
    [ "$n" -le 64 ] || return 0
    # Case-blind under the caller's nocasematch.
    case " $MC_GIT_READS " in *" $sub "*) ;; *) return 0 ;; esac
    # git's own options, between git and the subcommand: -c, never -C.
    shopt -u nocasematch
    [[ $m =~ $RE_MC_GIT_CONFIG ]] && rc=0
    shopt -s nocasematch
    [ "$rc" = 1 ] || return 0
    t=${t#*"$m"}
  done
  return 1
}

raw_evidence_one() {
  local t=$1 rc=1
  # Case-insensitive: a case-insensitive filesystem runs `git REBASE`.
  shopt -s nocasematch
  if [[ $t =~ $RE_GH_API ]] || [[ $t =~ $RE_GH_PR ]] || [[ $t =~ $RE_GIT_ACT ]] \
    || [[ $t =~ $RE_GIT_REWRITE ]] || [[ $t =~ $RE_GIT_COMMIT_SUBST ]] || [[ $t =~ $RE_MERGE_HELPER ]] \
    || [[ $t =~ $RE_FOR_MERGE ]]; then
    rc=0
  elif tower_floor && raw_tower_acts "$t"; then
    rc=0
  elif [ "${TIER:-}" = tower ] && raw_tower_alias "$t"; then
    rc=0
  elif [ "${TIER:-}" = mission-control ] && mc_raw_git_mutation "$t"; then
    rc=0
  fi
  # A worker's wrapped or substituted call of the force-push helper.
  [ "$TIER" != worker ] || [[ $t != *tower-force-push* ]] || ! raw_force_push_call "$t" || rc=0
  shopt -u nocasematch
  [ "$rc" = 1 ] || return 0
  case $t in *"$MCP_TOOL"*) return 0 ;; esac
  return 1
}

# raw_evidence <text> — the text as written, then with its quote and escape
# characters removed (so `me""rge` reads as `merge`) and its escaped newlines
# and tabs read as blanks.
raw_evidence() {
  local t=$1
  raw_evidence_one "$t" && return 0
  t=${t//\\n/ }
  t=${t//\\t/ }
  t=${t//[\"\'\\]/}
  raw_evidence_one "$t"
}

# heredoc_substitution_at <text> — 0 when <text> starts with
# `$(cat <<'DELIM' ... DELIM)` whose body expands nothing (a quoted
# delimiter, or an unquoted one over a body with no `$`, backtick, or
# backslash), setting HS_LEN to its length and HS_BODY to its body. That is
# the idiom a commit message or PR body arrives in; the tokenizer reads it,
# where bash would run it as a substitution, as one non-literal word instead
# of refusing the command (the body stays with its segment for the wrapper
# screens), so a gh api query carried this way still reads as unreadable.
# `<<-` is not folded: its delimiter matching differs.
HS_RE='^\$\([[:space:]]*cat[[:space:]]+<<[[:space:]]*(['"'"'"]?)([A-Za-z0-9_.][A-Za-z0-9_.-]*)(['"'"'"]?)[ '"$TAB"']*'"$NL"
heredoc_substitution_at() {
  local s=$1 m delim rest after body
  [[ $s =~ $HS_RE ]] || return 1
  [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[3]}" ] || return 1
  m=${BASH_REMATCH[0]}
  delim=${BASH_REMATCH[2]}
  rest=${s:${#m}}
  if [ "${rest#"$delim$NL"}" != "$rest" ]; then
    after=${rest#"$delim$NL"}
    body=''
  else
    case $rest in
      *"$NL$delim$NL"*)
        after=${rest#*"$NL$delim$NL"}
        body=${rest%%"$NL$delim$NL"*}
        ;;
      *) return 1 ;;
    esac
  fi
  if [ -z "${BASH_REMATCH[1]}" ]; then
    case $body in
      *'$'* | *'`'* | *\\*) return 1 ;;
    esac
  fi
  after=${after#"${after%%[![:space:]]*}"}
  case $after in
    ')'*) ;;
    *) return 1 ;;
  esac
  HS_LEN=$((${#s} - ${#after} + 1))
  HS_BODY=$body
}

deny_unanalyzable() {
  emit_deny "$1 and its text names a reserved act (a gh api request, a pull-request flip or merge, the merge helper, or a git merge, pull, rebase, push, or history rewrite) - refusing (fail closed). Issue that command on its own as a plain simple command."
}

# --------------------------------------------------------------------------
# Tokenizer. Splits the command as written into segments on the unquoted
# control operators, honoring quotes, comments, redirects, and here-documents.
# Per word it records whether the word is literal: free of expansion, an
# escape or `$` outside single quotes, and an unquoted glob or brace (gh's
# `{owner}`, `{repo}`, and `{branch}` placeholders excepted). It refuses
# command and process substitution (bar the data-only heredoc idiom above),
# backticks, ANSI-C quoting, and grouping. An unquoted here-document whose
# body carries a substitution sets HEREDOC_SUBST, since bash runs it.
#
# Results: W[] words, WL[] literal flags, SEG_S[]/SEG_E[] word ranges,
# SEG_TERM[] terminators, SEG_DOC[] here-document bodies per segment.

HEREDOC_SUBST=0
tokenize() {
  local s=$1
  local n=${#s} i=0 c nc ch cur='' have=0 lit=1 uqonly=1 digits_only=1 fold_doc=''
  local pending_delims=() pending_tabs=() pending_seg=() pending_quoted=()
  W=()
  WL=()
  SEG_S=()
  SEG_E=()
  SEG_TERM=()
  SEG_DOC=()
  local seg_start=0

  flush_word() {
    if [ "$have" = 1 ]; then
      if [ "$uqonly" = 1 ] && { [ "$cur" = '{' ] || [ "$cur" = '}' ]; }; then
        return 1
      fi
      # The test brackets are words, not globs.
      case "$uqonly:$cur" in
        '1:[' | '1:[[' | '1:]' | '1:]]') lit=1 ;;
      esac
      W[${#W[@]}]=$cur
      WL[${#WL[@]}]=$lit
    fi
    cur=''
    have=0
    lit=1
    uqonly=1
    digits_only=1
    return 0
  }
  flush_seg() {
    flush_word || return 1
    if [ "${#W[@]}" -gt "$seg_start" ]; then
      SEG_S[${#SEG_S[@]}]=$seg_start
      SEG_E[${#SEG_E[@]}]=${#W[@]}
      SEG_TERM[${#SEG_TERM[@]}]=$1
      SEG_DOC[${#SEG_DOC[@]}]=$fold_doc
    fi
    fold_doc=''
    seg_start=${#W[@]}
    return 0
  }
  # read_heredocs — at a newline, consume the bodies of every pending
  # here-document, attaching each to the segment that opened it.
  read_heredocs() {
    local k line cand body
    for k in "${!pending_delims[@]}"; do
      body=''
      while :; do
        if [ "$i" -ge "$n" ]; then
          break
        fi
        line=${s:i}
        line=${line%%"$NL"*}
        i=$((i + ${#line} + 1))
        cand=$line
        [ "${pending_tabs[$k]}" = 0 ] || cand=${cand#"${cand%%[!"$TAB"]*}"}
        [ "$cand" != "${pending_delims[$k]}" ] || break
        body="$body$line$NL"
      done
      if [ "${pending_quoted[$k]}" = 0 ]; then
        # shellcheck disable=SC2016 # the literal `$(` is the pattern
        case $body in *'$('* | *'`'*) HEREDOC_SUBST=1 ;; esac
      fi
      local si=${pending_seg[$k]}
      if [ "$si" -lt "${#SEG_DOC[@]}" ]; then
        SEG_DOC[si]="${SEG_DOC[si]}$body"
      fi
    done
    pending_delims=()
    pending_tabs=()
    pending_seg=()
    pending_quoted=()
  }

  while [ "$i" -lt "$n" ]; do
    c=${s:i:1}
    case $c in
      "'")
        local j=$((i + 1))
        while [ "$j" -lt "$n" ] && [ "${s:j:1}" != "'" ]; do j=$((j + 1)); done
        [ "$j" -lt "$n" ] || return 1
        cur="$cur${s:i+1:j-i-1}"
        have=1
        uqonly=0
        digits_only=0
        i=$((j + 1))
        ;;
      '"')
        local j=$((i + 1)) ch
        while [ "$j" -lt "$n" ]; do
          ch=${s:j:1}
          [ "$ch" != '"' ] || break
          case $ch in
            "\\")
              lit=0
              case ${s:j+1:1} in
                '"' | "\\" | '$' | '`')
                  cur="$cur${s:j+1:1}"
                  j=$((j + 2))
                  continue
                  ;;
                "$NL")
                  # A line continuation: bash drops both characters here too.
                  j=$((j + 2))
                  continue
                  ;;
              esac
              cur="$cur\\"
              ;;
            '`') return 1 ;;
            '$')
              lit=0
              if [ "${s:j+1:1}" = '(' ]; then
                heredoc_substitution_at "${s:j}" || return 1
                cur="$cur\$__PG_HEREDOC__"
                fold_doc="$fold_doc$HS_BODY$NL"
                j=$((j + HS_LEN))
                continue
              fi
              cur="$cur$ch"
              ;;
            *) cur="$cur$ch" ;;
          esac
          j=$((j + 1))
        done
        [ "$j" -lt "$n" ] || return 1
        have=1
        uqonly=0
        digits_only=0
        i=$((j + 1))
        ;;
      "\\")
        nc=${s:i+1:1}
        [ -n "$nc" ] || return 1
        if [ "$nc" = "$NL" ]; then
          i=$((i + 2))
          continue
        fi
        cur="$cur$nc"
        have=1
        lit=0
        uqonly=0
        digits_only=0
        i=$((i + 2))
        ;;
      '`') return 1 ;;
      '$')
        case ${s:i+1:1} in
          "'") return 1 ;;
          '(')
            heredoc_substitution_at "${s:i}" || return 1
            cur="$cur\$__PG_HEREDOC__"
            fold_doc="$fold_doc$HS_BODY$NL"
            have=1
            lit=0
            digits_only=0
            i=$((i + HS_LEN))
            continue
            ;;
        esac
        cur="$cur$c"
        have=1
        lit=0
        digits_only=0
        i=$((i + 1))
        ;;
      '#')
        if [ "$have" = 0 ]; then
          while [ "$i" -lt "$n" ] && [ "${s:i:1}" != "$NL" ]; do i=$((i + 1)); done
        else
          cur="$cur$c"
          digits_only=0
          i=$((i + 1))
        fi
        ;;
      '<' | '>')
        nc=${s:i+1:1}
        [ "$nc" != '(' ] || return 1
        # An fd designator before the operator (`2>`, or bash's named `{fd}>`)
        # is not an argument, so it is not a word either.
        if [ "$have" = 1 ] && [ "$uqonly" = 1 ] \
          && { [ "$digits_only" = 1 ] || [[ $cur =~ ^\{[A-Za-z_][A-Za-z0-9_]*\}$ ]]; }; then
          cur=''
          have=0
        fi
        flush_word || return 1
        if [ "$c" = '<' ] && [ "$nc" = '<' ] && [ "${s:i+2:1}" != '<' ]; then
          # A here-document: record its delimiter; the body is read at the
          # next newline.
          i=$((i + 2))
          local tabs=0 delim='' quoted=0
          if [ "${s:i:1}" = '-' ]; then
            tabs=1
            i=$((i + 1))
          fi
          while [ "$i" -lt "$n" ] && { [ "${s:i:1}" = ' ' ] || [ "${s:i:1}" = "$TAB" ]; }; do i=$((i + 1)); done
          while [ "$i" -lt "$n" ]; do
            ch=${s:i:1}
            case $ch in
              ' ' | "$TAB" | "$NL" | ';' | '&' | '|' | '<' | '>' | '(' | ')') break ;;
              "'" | '"')
                local q=$ch
                quoted=1
                i=$((i + 1))
                while [ "$i" -lt "$n" ] && [ "${s:i:1}" != "$q" ]; do
                  delim="$delim${s:i:1}"
                  i=$((i + 1))
                done
                [ "$i" -lt "$n" ] || return 1
                ;;
              "\\") quoted=1 ;;
              *) delim="$delim$ch" ;;
            esac
            i=$((i + 1))
          done
          [ -n "$delim" ] || return 1
          pending_delims[${#pending_delims[@]}]=$delim
          pending_quoted[${#pending_quoted[@]}]=$quoted
          pending_tabs[${#pending_tabs[@]}]=$tabs
          pending_seg[${#pending_seg[@]}]=${#SEG_S[@]}
          continue
        fi
        i=$((i + 1))
        case ${s:i:1} in
          '>' | '|' | '&' | '<') i=$((i + 1)) ;;
        esac
        while [ "$i" -lt "$n" ] && { [ "${s:i:1}" = ' ' ] || [ "${s:i:1}" = "$TAB" ]; }; do i=$((i + 1)); done
        while [ "$i" -lt "$n" ]; do
          case ${s:i:1} in
            ' ' | "$TAB" | "$NL" | ';' | '&' | '|' | '<' | '>') break ;;
            '(' | ')' | '`') return 1 ;;
            '$')
              case ${s:i+1:1} in '(' | "'") return 1 ;; esac
              ;;
            "'")
              i=$((i + 1))
              while [ "$i" -lt "$n" ] && [ "${s:i:1}" != "'" ]; do i=$((i + 1)); done
              [ "$i" -lt "$n" ] || return 1
              ;;
            '"')
              i=$((i + 1))
              while [ "$i" -lt "$n" ] && [ "${s:i:1}" != '"' ]; do
                case ${s:i:1} in
                  '`') return 1 ;;
                  '$') [ "${s:i+1:1}" != '(' ] || return 1 ;;
                  "\\") i=$((i + 1)) ;;
                esac
                i=$((i + 1))
              done
              [ "$i" -lt "$n" ] || return 1
              ;;
            "\\") i=$((i + 1)) ;;
          esac
          i=$((i + 1))
        done
        ;;
      ';' | '&' | '|')
        nc=${s:i+1:1}
        if [ "$c" = '&' ] && [ "$nc" = '>' ]; then
          # `&>` and `&>>` redirect both streams; the target is skipped like
          # any other redirect's.
          flush_word || return 1
          i=$((i + 1))
          continue
        fi
        local term=$c
        i=$((i + 1))
        if [ "$nc" = "$c" ] || { [ "$c" = '|' ] && [ "$nc" = '&' ]; }; then
          term="$c$nc"
          i=$((i + 1))
        fi
        flush_seg "$term" || return 1
        ;;
      "$NL")
        flush_seg "$NL" || return 1
        i=$((i + 1))
        [ "${#pending_delims[@]}" = 0 ] || read_heredocs
        ;;
      ' ' | "$TAB")
        flush_word || return 1
        i=$((i + 1))
        ;;
      '(' | ')') return 1 ;;
      '{')
        local rest=${s:i}
        case $rest in
          '{owner}'* | '{repo}'*)
            local ph=${rest%%\}*}
            cur="$cur$ph}"
            i=$((i + ${#ph} + 1))
            ;;
          '{branch}'*)
            cur="$cur{branch}"
            i=$((i + 8))
            ;;
          *)
            cur="$cur$c"
            lit=0
            i=$((i + 1))
            ;;
        esac
        have=1
        digits_only=0
        ;;
      '*' | '?' | '[' | '}')
        cur="$cur$c"
        have=1
        lit=0
        digits_only=0
        i=$((i + 1))
        ;;
      '~')
        [ "$have" = 1 ] || lit=0
        cur="$cur$c"
        have=1
        digits_only=0
        i=$((i + 1))
        ;;
      *)
        cur="$cur$c"
        have=1
        case $c in [0-9]) ;; *) digits_only=0 ;; esac
        i=$((i + 1))
        ;;
    esac
  done
  flush_seg '' || return 1
  [ "${#pending_delims[@]}" = 0 ] || read_heredocs
  return 0
}

# --------------------------------------------------------------------------
# Small helpers.

lower() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'; }

# timeout_bin — the command that bounds a read: timeout or gtimeout, else the
# bundled runner (stock macOS ships neither), else nothing.
timeout_bin() {
  if command -v timeout >/dev/null 2>&1; then
    printf 'timeout'
  elif command -v gtimeout >/dev/null 2>&1; then
    printf 'gtimeout'
  elif [ -n "$GUARD_DIR" ] && [ -r "$GUARD_DIR/bounded-run.sh" ]; then
    printf 'bounded_run'
  fi
}

# Run through sh rather than its own mode bits, which a plugin copy may drop.
# shellcheck disable=SC2329 # called through the name timeout_bin prints
bounded_run() {
  /bin/sh "$GUARD_DIR/bounded-run.sh" "$@"
}

# bound_secs <env-value> <default> — a positive whole number of seconds.
bound_secs() {
  local v=${1:-$2}
  case $v in
    "" | *[!0-9]* | 0 | 0?*) v=$2 ;;
  esac
  [ "${#v}" -le 4 ] || v=$2
  printf '%s' "$v"
}

TB=''
# need_timeout — run before every bounded read: the bound must exist, and the
# call as a whole must still be inside its own deadline, so a compound command
# cannot stack reads past the point where the hook itself would be cut off.
readonly OVERALL_DEADLINE=40
need_timeout() {
  local remain=$((OVERALL_DEADLINE - SECONDS - 3))
  [ "$remain" -gt 0 ] \
    || emit_deny "the guard's reads for this command took over ${OVERALL_DEADLINE}s, so it stops here - refusing (fail closed). Split the command into shorter ones."
  # Each read is bounded by its own limit or the time left, whichever is less.
  KNOB_B=$KNOB_T
  [ "$KNOB_B" -le "$remain" ] || KNOB_B=$remain
  FETCH_B=$FETCH_T
  [ "$FETCH_B" -le "$remain" ] || FETCH_B=$remain
  [ -n "$TB" ] || TB=$(timeout_bin)
  [ -n "$TB" ] \
    || emit_deny 'no timeout (or gtimeout) binary is on PATH and the bundled bounded-run.sh is missing beside this guard, so the guard cannot bound its policy read - refusing (fail closed). Reinstall planwright.'
}

# A git revision as an argument: no leading dash, no shell or ref-breaking
# characters.
valid_rev() {
  case ${1:-} in
    "" | -* | *[!A-Za-z0-9._/~^@{}:+-]* | *..*) return 1 ;;
  esac
  [ "${#1}" -le 255 ]
}

# A branch name as git accepts it, narrowed.
valid_branch() {
  case ${1:-} in
    "" | -* | /* | */ | *//* | *..* | *[!A-Za-z0-9._/+@-]* | *.lock | *.lock/* | *.) return 1 ;;
    HEAD | @ | .* | */.*) return 1 ;;
  esac
  [ "${#1}" -le 255 ]
}

# A flight branch needs no trailing id here, unlike the launchers'
# scripts/flight-id.sh grammar: branches named before ids existed may still
# carry open pull requests, and the id buys uniqueness, not safety (the
# protected set and the ownership checks bound the act).
is_unit_branch() {
  local re_task='^planwright/[a-z0-9][a-z0-9-]*/task-[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$'
  local re_flight='^planwright/flight/[a-z0-9]([a-z0-9-]*[a-z0-9])?$'
  case $1 in planwright/flight/task-*) return 1 ;; esac
  [[ $1 =~ $re_task ]] || [[ $1 =~ $re_flight ]]
}

# gitq <dir> <args...> — a local git read, stdout only. Local reads of refs and
# config take no lock and reach no remote, so they run unbounded; the bound
# is for the policy read and the upstream refresh, which can stall.
gitq() {
  local d=$1
  shift
  GIT_OPTIONAL_LOCKS=0 git -C "$d" "$@" 2>/dev/null </dev/null
}

# --------------------------------------------------------------------------
# Knob reads.

# policy_root <dir> — set POLICY_ROOT to the primary checkout of the
# repository <dir> belongs to (the main worktree, from git's common dir), or
# deny. Policy is read there, never from the command's own worktree, so a
# worker's edit to its own .claude/planwright*.yml governs nothing until it
# merges.
POLICY_ROOT_FOR='' POLICY_ROOT=''
policy_root() {
  local dir=$1 common
  [ "$dir" != "$POLICY_ROOT_FOR" ] || return 0
  common=$(gitq "$dir" rev-parse --path-format=absolute --git-common-dir) || common=''
  case $common in
    /*/.git) POLICY_ROOT=${common%/.git} ;;
    *) POLICY_ROOT='' ;;
  esac
  [ -n "$POLICY_ROOT" ] && [ -d "$POLICY_ROOT" ] \
    || emit_deny "the primary checkout of the repository this act runs in could not be found (a bare repository, or not a repository), and the policy is read only from there - refusing (fail closed). Run the command from a worktree of a non-bare clone."
  POLICY_ROOT_FOR=$dir
}

# read_knob <knob> <dir> <legal...> — the resolved value, or a deny. A knob
# read once for a directory is not read again within the call.
KNOB_CACHE=''
read_knob() {
  local knob=$1 dir=$2 v rc=0 ok=0 legal
  shift 2
  case $KNOB_CACHE in
    *"<$knob|$dir|"*)
      v=${KNOB_CACHE#*"<$knob|$dir|"}
      KNOB_VAL=${v%%>*}
      return 0
      ;;
  esac
  need_timeout
  [ -n "$GUARD_DIR" ] && [ -r "$GUARD_DIR/resolve-policy-knob.sh" ] \
    || emit_deny "the policy resolver is missing beside this guard, so $knob could not be read - refusing (fail closed). Reinstall planwright."
  [ -d "$dir" ] \
    || emit_deny "the directory this act runs in does not exist, so the policy knob $knob cannot be read for it - refusing (fail closed). Run the command from your worktree."
  policy_root "$dir"
  v=$(cd -- "$POLICY_ROOT" 2>/dev/null && PLANWRIGHT_REPO_ROOT=$POLICY_ROOT "$TB" -k 2 "$KNOB_B" /bin/sh "$GUARD_DIR/resolve-policy-knob.sh" "$knob" 2>/dev/null </dev/null) || rc=$?
  if [ "$rc" = 124 ] || [ "$rc" = 143 ]; then
    emit_deny "reading the policy knob $knob did not finish within ${KNOB_B}s - refusing (fail closed). This is a timeout, not a policy decision: retry, and report a resolver that stays slow."
  fi
  [ "$rc" = 0 ] \
    || emit_deny "the policy knob $knob could not be resolved (resolver exit $rc), so the act it governs is refused (fail closed). Repair the malformed value or install, then retry."
  for legal in "$@"; do
    [ "$v" != "$legal" ] || ok=1
  done
  [ "$ok" = 1 ] \
    || emit_deny "the policy knob $knob resolved to a value the guard does not recognize ($(sanitize_printable "$v" 'unprintable')) - refusing (fail closed). Set it to one of: $*."
  KNOB_VAL=$v
  KNOB_CACHE="$KNOB_CACHE<$knob|$dir|$v>"
}

# check_unprotected <dir> <what> <branch...> — deny when any branch is in the
# protected set (the core floor plus protected_branches), or the set cannot be
# read.
check_unprotected() {
  local dir=$1 what=$2 rc=0 err
  shift 2
  [ "$#" -gt 0 ] || return 0
  need_timeout
  [ -n "$GUARD_DIR" ] && [ -r "$GUARD_DIR/protected-branch.sh" ] \
    || emit_deny "the protected-set reader is missing beside this guard - refusing $what (fail closed). Reinstall planwright."
  [ -d "$dir" ] \
    || emit_deny "the directory $what runs in does not exist, so the protected set cannot be read for it - refusing (fail closed). Run the command from your worktree."
  policy_root "$dir"
  err=$(cd -- "$POLICY_ROOT" 2>/dev/null && PLANWRIGHT_REPO_ROOT=$POLICY_ROOT "$TB" -k 2 "$KNOB_B" /bin/sh "$GUARD_DIR/protected-branch.sh" "$@" 2>&1 >/dev/null </dev/null) || rc=$?
  case $rc in
    0) return 0 ;;
    1)
      emit_deny "$what targets a protected branch ($(sanitize_printable "${err#protected-branch: }" 'a protected branch')); main, master, spec branches, and the protected_branches additions are never written by an agent session at any tier. Work on your own unit branch."
      ;;
    2)
      emit_deny "$what names a branch the protected-set reader refuses as a branch name ($(sanitize_printable "${err#protected-branch: }" 'unprintable')) - refusing (fail closed). Name a valid branch."
      ;;
    124 | 143)
      emit_deny "reading the protected set did not finish within ${KNOB_B}s - refusing $what (fail closed). This is a timeout, not a policy decision: retry."
      ;;
    *)
      emit_deny "the protected set could not be read (exit $rc), so $what is refused (fail closed). Repair protected_branches, then retry."
      ;;
  esac
}

# --------------------------------------------------------------------------
# Repository state.

# current_branch <dir> — the checked-out branch name, or empty.
current_branch() {
  gitq "$1" symbolic-ref --quiet --short HEAD || printf ''
}

# checkout_of <dir> — sets CO_TOP, CO_GD and CO_COMMON to the top, the git
# dir and the git common dir of the checkout <dir> lies in, and CO_LINKED to 1
# for a linked worktree, 0 for a primary checkout; returns 1, all four
# cleared, when git cannot read them.
CO_TOP='' CO_GD='' CO_COMMON='' CO_LINKED=0
checkout_of() {
  local out
  CO_TOP='' CO_GD='' CO_COMMON='' CO_LINKED=0
  [ -d "$1" ] || return 1
  out=$(gitq "$1" rev-parse --path-format=absolute --show-toplevel --git-dir --git-common-dir) || return 1
  case $out in *"$NL"*"$NL"*) ;; *) return 1 ;; esac
  CO_TOP=${out%%"$NL"*}
  out=${out#*"$NL"}
  CO_GD=${out%%"$NL"*}
  CO_COMMON=${out#*"$NL"}
  case $CO_COMMON in *"$NL"*) CO_COMMON='' ;; esac
  [ -n "$CO_TOP" ] && [ -n "$CO_GD" ] && [ -n "$CO_COMMON" ] || {
    CO_TOP='' CO_GD='' CO_COMMON=''
    return 1
  }
  [ "$CO_GD" = "$CO_COMMON" ] || CO_LINKED=1
}

# unit_branch_or_deny <what> <act> [<remedy>] — the session's unit branch and
# the checkout holding it, or a deny; <act> is base-sync for a merge or pull of
# the base or the branch's own remote branch, empty otherwise. <remedy>
# follows a refusal for running off the unit branch. A session
# launched into its unit worktree owns that checkout alone. A session
# launched at a repository's primary checkout holding a branch that is not a
# task or flight branch owns, for a base sync only, the linked worktree of
# that repository its shell is in: the payload cwd is the shell's directory as
# the harness reported it, so a `cd` or -C inside the command never moves it,
# and the shell's location is the only ownership evidence such a launch
# leaves.
UNIT_BRANCH='' UNIT_TOP='' UNIT_GD='' UNIT_DIR='' UNIT_VIA=''
# 1 only once the Bash payload itself carried a non-empty cwd; PAYLOAD_CWD
# falls back to the hook's own directory otherwise, which proves nothing.
CWD_REPORTED=0
unit_branch_or_deny() {
  local what=$1 act=$2 rem=${3:-} pdir=${CLAUDE_PROJECT_DIR:-} b common
  local only="$what is allowed only on the session's own unit branch (a planwright/<spec>/task-<id> or planwright/flight/<name> branch)"
  local rewrite="$what is refused: a session launched at the primary checkout never rewrites history; it only syncs the linked worktree its shell is in (a merge or pull of the PR base or its own remote branch). Leave the rewrite to a session launched into its own worktree."
  if [ -z "$UNIT_BRANCH" ]; then
    [ -n "$pdir" ] && [ -d "$pdir" ] \
      || emit_deny "$what needs the session's unit branch, and the hook received no project directory (CLAUDE_PROJECT_DIR) to read it from - refusing (fail closed)."
    b=$(current_branch "$pdir")
    if is_unit_branch "$b"; then
      checkout_of "$pdir" \
        || emit_deny "$what needs the checkout of the session's project directory, which git could not read - refusing (fail closed)."
      UNIT_BRANCH=$b UNIT_TOP=$CO_TOP UNIT_GD=$CO_GD UNIT_DIR=$pdir UNIT_VIA=project
    else
      [ -n "$b" ] \
        || emit_deny "$only, and this session's project directory has no branch checked out (a detached HEAD, or not a repository) - refusing.$rem"
      checkout_of "$pdir" \
        || emit_deny "$what needs the checkout of the session's project directory, which git could not read - refusing (fail closed)."
      [ "$CO_LINKED" = 0 ] \
        || emit_deny "$only, and this session's project directory, a linked worktree, has $(sanitize_printable "$b" 'another branch') checked out - refusing.$rem"
      [ "$act" = base-sync ] || emit_deny "$rewrite"
      common=$CO_COMMON
      [ "$CWD_REPORTED" = 1 ] \
        || emit_deny "$only; this session was launched at the primary checkout ($(sanitize_printable "$b" 'its branch') checked out), so it syncs only the linked worktree its shell is in, and the hook was told no shell directory - refusing (fail closed).$rem"
      checkout_of "$PAYLOAD_CWD" && [ "$CO_LINKED" = 1 ] && [ "$CO_COMMON" = "$common" ] \
        || emit_deny "$only; this session was launched at the primary checkout ($(sanitize_printable "$b" 'its branch') checked out), so it syncs only the linked worktree of this repository its shell is in, and the shell is in none - refusing. If the session works in its own linked worktree, cd into it as a command of its own first.$rem"
      b=$(current_branch "$PAYLOAD_CWD")
      is_unit_branch "$b" \
        || emit_deny "$only, and the worktree this session's shell is in has $(sanitize_printable "${b:-no branch}" 'an unreadable branch') checked out - refusing.$rem"
      UNIT_BRANCH=$b UNIT_TOP=$CO_TOP UNIT_GD=$CO_GD UNIT_DIR=$PAYLOAD_CWD UNIT_VIA=shell
    fi
  fi
  # Not redundant with the refusal above: that one names the rewrite before
  # the shell checks can deny it as something else; this one covers every
  # later act, which skips the resolution once the unit branch is cached.
  [ "$UNIT_VIA" != shell ] || [ "$act" = base-sync ] || emit_deny "$rewrite"
}

# on_unit_branch <dir> <what> [<act>] [<remedy>] — deny unless <dir> lies in
# the session's own checkout (its top and git dir both, so a same-named branch
# in another checkout, or one whose core.worktree points here, is refused) with
# the unit branch checked out, outside the protected set. Checked per act: a
# compound command's later acts get no pass from the first. <act> and <remedy>
# are unit_branch_or_deny's; <remedy> also follows a refusal for running on
# another branch.
on_unit_branch() {
  local dir=$1 what=$2 b
  unit_branch_or_deny "$what" "${3:-}" "${4:-}"
  b=$(current_branch "$dir")
  [ -n "$b" ] \
    || emit_deny "$what runs where no branch is checked out (a detached HEAD or an unreadable repository) - refusing (fail closed)."
  [ "$b" = "$UNIT_BRANCH" ] \
    || emit_deny "$what would run on $(sanitize_printable "$b" 'another branch'), which is not this session's unit branch ($(sanitize_printable "$UNIT_BRANCH" 'unreadable')) - refusing. Run it in your own worktree.${4:-}"
  if [ "$dir" != "$UNIT_DIR" ]; then
    checkout_of "$dir" \
      || emit_deny "$what runs where git could not read the checkout - refusing (fail closed). Run it in your own worktree."
    [ "$CO_TOP" = "$UNIT_TOP" ] \
      || emit_deny "$what targets a checkout other than this session's own ($(sanitize_printable "$UNIT_TOP" 'its worktree')), though it holds a branch of the same name - refusing. Run it in your own worktree, with no cd or -C into another checkout."
    [ "$CO_GD" = "$UNIT_GD" ] \
      || emit_deny "$what runs through another repository's git directory ($(sanitize_printable "$CO_GD" 'unprintable')) whose core.worktree points at this session's worktree - refusing. Run it in your own worktree."
  fi
  check_unprotected "$dir" "$what" "$b"
  CUR_BRANCH=$b
}

# upstream_of <dir> <branch> — sets UP_REMOTE and UP_BRANCH, empty when none.
upstream_of() {
  local m
  UP_REMOTE=$(gitq "$1" config --get "branch.$2.remote") || UP_REMOTE=''
  m=$(gitq "$1" config --get "branch.$2.merge") || m=''
  UP_BRANCH=${m#refs/heads/}
  [ "$UP_BRANCH" != "$m" ] || UP_BRANCH=''
}

# base_of <dir> — sets BASE_REMOTE and BASE_BRANCH: the unit branch's remote
# (origin when unset) and that remote's default branch as recorded locally.
base_of() {
  local head
  BASE_REMOTE=$(gitq "$1" config --get "branch.$CUR_BRANCH.remote") || BASE_REMOTE=''
  case $BASE_REMOTE in "" | .) BASE_REMOTE=origin ;; esac
  head=$(gitq "$1" symbolic-ref --quiet --short "refs/remotes/$BASE_REMOTE/HEAD") || head=''
  BASE_BRANCH=${head#"$BASE_REMOTE"/}
  [ -n "$head" ] && [ "$BASE_BRANCH" != "$head" ] || BASE_BRANCH=main
}

# is_base_ref <dir> <name> — 0 when the merge source is the PR base: by name,
# and by what git resolves the name to (a local branch or tag called
# origin/main would shadow the remote-tracking ref). A local base branch
# counts only while it holds nothing the remote base lacks; FETCH_HEAD only
# when it holds the base branch fetched from the base remote's own URL.
is_base_ref() {
  local d=$1 r=$2 fh line url base_oid oid
  base_oid=$(gitq "$d" rev-parse --verify --quiet "refs/remotes/$BASE_REMOTE/$BASE_BRANCH^{commit}") || return 1
  [ -n "$base_oid" ] || return 1
  case $r in
    "$BASE_REMOTE/$BASE_BRANCH" | "refs/remotes/$BASE_REMOTE/$BASE_BRANCH" | "remotes/$BASE_REMOTE/$BASE_BRANCH")
      oid=$(gitq "$d" rev-parse --verify --quiet --end-of-options "$r^{commit}") || return 1
      [ "$oid" = "$base_oid" ]
      return
      ;;
    "$BASE_BRANCH" | "refs/heads/$BASE_BRANCH" | "heads/$BASE_BRANCH")
      oid=$(gitq "$d" rev-parse --verify --quiet --end-of-options "$r^{commit}") || return 1
      [ "$oid" = "$(gitq "$d" rev-parse --verify --quiet "refs/heads/$BASE_BRANCH^{commit}")" ] || return 1
      gitq "$d" merge-base --is-ancestor "$oid" "$base_oid"
      return
      ;;
    FETCH_HEAD)
      url=$(gitq "$d" config --get "remote.$BASE_REMOTE.url") || return 1
      [ -n "$url" ] || return 1
      # git may write the URL with trailing slashes and `.git` trimmed.
      local short=${url%%/}
      short=${short%.git}
      short=${short%%/}
      fh=$(gitq "$d" rev-parse --git-path FETCH_HEAD) || return 1
      case $fh in /*) ;; *) fh="$d/$fh" ;; esac
      [ -r "$fh" ] || return 1
      local seen=0
      while IFS= read -r line; do
        case $line in
          *"${TAB}not-for-merge${TAB}"*) continue ;;
          *"${TAB}${TAB}branch '$BASE_BRANCH' of $url" | *"${TAB}${TAB}branch '$BASE_BRANCH' of $short") seen=1 ;;
          *) return 1 ;;
        esac
      done <"$fh"
      [ "$seen" = 1 ]
      return
      ;;
  esac
  return 1
}

# is_base_or_own_branch <remote> <branch> — 0 when a remote branch is the PR
# base or the unit branch's own branch on the base remote.
is_base_or_own_branch() {
  [ "$1" = "$BASE_REMOTE" ] || return 1
  [ "$2" = "$BASE_BRANCH" ] || [ "$2" = "$CUR_BRANCH" ]
}

# is_own_remote_ref <dir> <name> — 0 when the merge source is the unit
# branch's own remote-tracking branch on the base remote, by name and by what
# git resolves the name to; 2 when it is spelled as that branch but the ref is
# missing or a local branch or tag of that name points at another commit; 1
# otherwise. A shadow at the same commit is admitted: the merge takes that
# very commit, and the guard refuses a ref change earlier in the command.
is_own_remote_ref() {
  local d=$1 r=$2 want oid
  case $r in
    "$BASE_REMOTE/$CUR_BRANCH" | "refs/remotes/$BASE_REMOTE/$CUR_BRANCH" | "remotes/$BASE_REMOTE/$CUR_BRANCH") ;;
    *) return 1 ;;
  esac
  want=$(gitq "$d" rev-parse --verify --quiet "refs/remotes/$BASE_REMOTE/$CUR_BRANCH^{commit}") || return 2
  oid=$(gitq "$d" rev-parse --verify --quiet --end-of-options "$r^{commit}") || return 2
  [ -n "$want" ] && [ "$oid" = "$want" ] || return 2
}

# refresh_and_check_unpushed <dir> <what> <range> — the never-pushed check:
# refresh the branch's upstream tracking ref, then require that no
# remote-tracking ref contains any commit of the range.
refresh_and_check_unpushed() {
  refresh_upstream "$1" "$2"
  check_unpushed "$@"
}

REFRESHED=''
refresh_upstream() {
  local d=$1 what=$2 rc=0
  upstream_of "$d" "$CUR_BRANCH"
  { [ -n "$UP_REMOTE" ] && [ "$UP_REMOTE" != . ] && [ -n "$UP_BRANCH" ]; } \
    || emit_deny "$what rewrites history, and $(sanitize_printable "$CUR_BRANCH" 'this branch') has no upstream on a remote, so the guard cannot prove the commits were never pushed - refusing. Push the branch with -u once (new commits only), then retry."
  valid_branch "$UP_BRANCH" && [[ $UP_REMOTE =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
    || emit_deny "$what: the branch's upstream is not a shape the guard will fetch - refusing (fail closed). Set a plain remote and branch as the upstream."
  case $REFRESHED in *"<$d|$UP_REMOTE|$UP_BRANCH>"*) return 0 ;; esac
  need_timeout
  # No background maintenance may outlive the hook, and a kill reaches git.
  GIT_TERMINAL_PROMPT=0 "$TB" -k 2 "$FETCH_B" git -C "$d" -c gc.auto=0 -c maintenance.auto=false \
    fetch --quiet --no-tags --no-write-fetch-head \
    --no-recurse-submodules "$UP_REMOTE" "+refs/heads/$UP_BRANCH:refs/remotes/$UP_REMOTE/$UP_BRANCH" \
    </dev/null >/dev/null 2>&1 || rc=$?
  [ "$rc" = 0 ] \
    || emit_deny "$what rewrites history, and refreshing the upstream $(sanitize_printable "$UP_REMOTE/$UP_BRANCH" 'tracking ref') failed (exit $rc), so a commit pushed from another clone could read as never-pushed - refusing (fail closed). Retry when the remote is reachable."
  REFRESHED="$REFRESHED<$d|$UP_REMOTE|$UP_BRANCH>"
}

# check_unpushed <dir> <what> <range> — after refresh_upstream.
check_unpushed() {
  local d=$1 what=$2 range=$3 all mine
  all=$(gitq "$d" rev-list --count "$range") || all=''
  mine=$(gitq "$d" rev-list --count "$range" --not --remotes) || mine=''
  case "$all:$mine" in
    *[!0-9:]* | :* | *:) emit_deny "$what: the commits it would rewrite could not be listed - refusing (fail closed)." ;;
  esac
  [ "$all" = "$mine" ] \
    || emit_deny "$what would rewrite $((all - mine)) commit(s) a remote-tracking ref already contains; pushed history stays append-only - refusing. Add a new commit instead."
}

# --------------------------------------------------------------------------
# Classification. Each segment yields CLS (none, deny, or an act needing
# reads) plus its arguments; deny verdicts land in DENY_NOW.

DENY_NOW=''
PENDING=()

# segment_words <seg> — set SW[] / SWL[] to the segment's words after the
# simple-command prefix (assignments, `command`, `exec`, reserved words).
segment_words() {
  local k=${SEG_S[$1]} e=${SEG_E[$1]} w
  SW=()
  SWL=()
  SW_WRAPPED=0
  SW_GITENV=0
  while [ "$k" -lt "$e" ]; do
    w=${W[$k]}
    case $w in
      '!' | if | then | else | elif | do | while | until | nocorrect | noglob | builtin | coproc)
        k=$((k + 1))
        continue
        ;;
      time)
        k=$((k + 1))
        while [ "$k" -lt "$e" ]; do
          case ${W[$k]} in
            -p | --) k=$((k + 1)) ;;
            *) break ;;
          esac
        done
        continue
        ;;
      command | exec)
        case ${W[$((k + 1))]:-} in
          -*) SW_WRAPPED=1 ;;
        esac
        k=$((k + 1))
        continue
        ;;
      [A-Za-z_]*=*)
        case ${w%%=*} in
          *[!A-Za-z0-9_+]*) ;;
          *)
            case ${w%%=*} in GIT_*) SW_GITENV=1 ;; esac
            k=$((k + 1))
            continue
            ;;
        esac
        ;;
    esac
    break
  done
  while [ "$k" -lt "$e" ]; do
    SW[${#SW[@]}]=${W[$k]}
    SWL[${#SWL[@]}]=${WL[$k]}
    k=$((k + 1))
  done
}

# segment_text <seg> — set SEG_TEXT to the segment's words and its
# here-document body (a variable, not output: this runs per segment).
segment_text() {
  local k=${SEG_S[$1]} e=${SEG_E[$1]}
  SEG_TEXT=''
  while [ "$k" -lt "$e" ]; do
    SEG_TEXT="$SEG_TEXT ${W[$k]}"
    k=$((k + 1))
  done
  SEG_TEXT="$SEG_TEXT$NL${SEG_DOC[$1]}"
}

deny_now() {
  [ -n "$DENY_NOW" ] || DENY_NOW=$1
}

# tower_floor — 0 at a tier that carries the tower's denials.
tower_floor() {
  case ${TIER:-} in
    tower | mission-control) return 0 ;;
  esac
  return 1
}

# Repository state an earlier segment of the same command changes before a
# later one runs; every segment is checked against the state as it is now, so
# a reserved act after such a change cannot be checked and is refused.
ST_CFG=0
ST_REF=0
ST_FETCH=0
ST_FETCHSPEC=0
ST_PUSH=0
ST_HEAD=0
GIT_ENV_SET=0

RESERVED_WORD_RE='^(merge|pull|rebase|push|commit|ready|api|--am.*|--sq.*|--fix.*)$'
# A command word that is one variable naming a directory, then a literal
# path: `"$ROOT/scripts/x.sh"`. Any other expanded command word could be git.
# shellcheck disable=SC2016 # a regex; `$` is literal
RE_ROOTED_SCRIPT='^\$(\{[A-Za-z_][A-Za-z0-9_]*\}|[A-Za-z_][A-Za-z0-9_]*)/[^$`]+$'

# lc <word> — set LC to the word in lower case, forking only when it has an
# upper-case letter (this runs per word on every guarded call).
lc() {
  LC=$1
  case $1 in
    *[A-Z]*) LC=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]') ;;
  esac
}

# runs_force_push_helper <lowercased command name> — 0 when the segment runs
# the tower's force-push helper, directly or as a shell's script operand.
runs_force_push_helper() {
  local w
  [ "$1" = tower-force-push.sh ] && return 0
  case $1 in
    bash | sh | zsh | dash | ksh | mksh | busybox | env | nohup | nice | timeout | gtimeout | exec | command) ;;
    *) return 1 ;;
  esac
  for w in "${SW[@]:1}"; do
    lc "${w##*/}"
    [ "$LC" = tower-force-push.sh ] && return 0
  done
  return 1
}

# tower_wrapped_git_alias — 0 when a wrapped segment's words run git with a
# subcommand that is not a literal builtin. The joined text the raw fallback
# reads has lost the word boundaries, so a quoted global-option value holding
# a space could hide the alias there; the words still carry them.
tower_wrapped_git_alias() {
  local i=1 n=${#SW[@]} k
  while [ "$i" -lt "$n" ]; do
    if [ "${SW[$i]##*/}" = git ]; then
      k=$((i + 1))
      while [ "$k" -lt "$n" ]; do
        case ${SW[$k]} in
          -C | -c | --config-env | --git-dir | --work-tree | --namespace | --super-prefix | --attr-source | --list-cmds)
            k=$((k + 2))
            ;;
          -p | -P | --paginate | --no-pager | --no-replace-objects | --no-lazy-fetch | --no-optional-locks | \
            --no-advice | --literal-pathspecs | --glob-pathspecs | --noglob-pathspecs | --icase-pathspecs | --bare | \
            -C?* | -c?* | --*=*)
            k=$((k + 1))
            ;;
          -*) return 0 ;;
          *) break ;;
        esac
      done
      if [ "$k" -lt "$n" ]; then
        [ "${SWL[$k]}" = 1 ] || return 0
        case " $GIT_BUILTINS " in *" ${SW[$k]} "*) ;; *) return 0 ;; esac
      fi
    fi
    i=$((i + 1))
  done
  return 1
}

tower_wrapped_git_check() {
  [ "$TIER" != tower ] || ! tower_wrapped_git_alias \
    || deny_now "this command runs git through a wrapper where the guard cannot read its subcommand as a literal git builtin (an alias, an expansion, or one behind a global option the guard does not know) - refusing (fail closed). Issue the git command directly."
}

# --------------------------------------------------------------------------
# The kickoff sign-off push. scripts/kickoff-spec-push.sh pushes a spec's own
# sign-off branch, which the protected set otherwise refuses to every agent
# session. Only the worker whose launch scope (PLANWRIGHT_WORKER_SCOPE in the
# hook's environment, which a command's inline assignment cannot change) is
# kickoff-<spec> may run it, and only from that spec branch. Every other
# session is refused the push it would make, with the text a push to that
# branch gets. A run the guard cannot read is refused.

KICK_SEEN=0
KICK_NAME=kickoff-spec-push
KICK_FILE=kickoff-spec-push.sh

# kickoff_named <word> — 0 when the word's basename names the kickoff push.
kickoff_named() {
  lc "${1##*/}"
  case $LC in *"$KICK_NAME"*) return 0 ;; esac
  return 1
}

# RE_KICKOFF_SCRIPT: the planwright script itself, named through the plugin
# root variable. A relative or literal path would run a copy of the script from
# the session's own checkout, which the guard cannot read.
RE_KICKOFF_SCRIPT='^\$\{?CLAUDE_PLUGIN_ROOT\}?/scripts/kickoff-spec-push\.sh$'

# kickoff_script_at <index> — 0 when the command word at <index> is RE_KICKOFF_SCRIPT.
kickoff_script_at() {
  [[ ${SW[$1]} =~ $RE_KICKOFF_SCRIPT ]]
}

# kickoff_segment <dir> — 0 when the segment names the kickoff push, which is
# then decided here; 1 when it does not name it.
kickoff_segment() {
  local dir=$1 n=${#SW[@]} named=0 w spec='' b form=direct
  for w in "${SW[@]}"; do
    kickoff_named "$w" && named=1
  done
  [ "$named" = 1 ] || return 1
  KICK_SEEN=$((KICK_SEEN + 1))
  [ "$GIT_ENV_SET" = 1 ] || [ "$SW_GITENV" = 1 ] \
    && deny_now 'this kickoff push runs with a GIT_ variable set, which could point it at another repository - refusing (fail closed). Run it with no GIT_ variable.' \
    && return 0
  lc "${SW[0]##*/}"
  case $LC in bash | sh | zsh | dash | ksh | mksh) form=shell ;; esac
  if [ "$form" = shell ] && [ "$n" = 3 ] && kickoff_script_at 1; then
    [ "${SWL[2]:-0}" = 1 ] && spec=${SW[2]}
  elif [ "$form" = direct ] && [ "$n" = 2 ] && kickoff_script_at 0; then
    [ "${SWL[1]:-0}" = 1 ] && spec=${SW[1]}
  else
    deny_now 'this command names scripts/kickoff-spec-push.sh in a form the guard cannot check - refusing (fail closed). Run it directly, as scripts/kickoff-spec-push.sh <spec>, with no other arguments.'
    return 0
  fi
  case $spec in
    [a-z0-9]*)
      case $spec in *[!a-z0-9-]*) spec='' ;; esac
      ;;
    *) spec='' ;;
  esac
  [ "${#spec}" -le 64 ] || spec=''
  [ "$spec" != flight ] || spec='' # the reserved flight namespace, not a spec
  [ -n "$spec" ] \
    || deny_now 'this command runs scripts/kickoff-spec-push.sh with an argument the guard cannot read as a spec name - refusing (fail closed). Name the spec in lowercase letters, digits and hyphens.'
  [ -n "$spec" ] || return 0
  if [ "$TIER" = worker ] && [ "${PLANWRIGHT_WORKER_SCOPE:-}" = "kickoff-$spec" ]; then
    b=$(current_branch "$dir")
    [ "$b" = "planwright/$spec/spec" ] \
      || deny_now "the kickoff push runs only from the spec branch of its kickoff (planwright/$spec/spec), and this checkout has ${b:-no branch} checked out - refusing. Check out that branch in your worktree."
    return 0
  fi
  check_unprotected "$dir" 'this git push' "planwright/$spec/spec"
  deny_now "this git push targets a protected branch (planwright/$spec/spec); the spec branch is never written by an agent session at any tier. Work on your own unit branch."
  return 0
}

# kickoff_text_check — every spelling of the kickoff push's name in the command
# must be a run the segments read above; a name in a redirect, a -c string or
# a quoted or spelled-out form is refused.
kickoff_text_check() {
  local s=${P_CMD//[\"\'\\]/} n=0
  while [[ $s == *"$KICK_FILE"* ]]; do
    n=$((n + 1))
    s=${s#*"$KICK_FILE"}
  done
  [ "$n" = "$KICK_SEEN" ] \
    || deny_now 'this command names scripts/kickoff-spec-push.sh in a spelling the guard cannot read as a run of it - refusing (fail closed). Run the script directly, as scripts/kickoff-spec-push.sh <spec>.'
}

classify_segments() {
  local si=0 eff=$PAYLOAD_CWD eff_ok=1 verb base_verb prev_text='' cur_text w
  KICK_SEEN=0
  [ -d "$eff" ] || eff_ok=0
  while [ "$si" -lt "${#SEG_S[@]}" ]; do
    segment_words "$si"
    segment_text "$si"
    cur_text=$SEG_TEXT
    if [ "${#SW[@]}" = 0 ]; then
      # A segment of assignments alone sets them for the rest of the command;
      # the shell runs a prompt or startup hook's value as a command.
      [ "$SW_GITENV" = 0 ] || GIT_ENV_SET=1
      case $cur_text in
        *PROMPT_COMMAND=* | *BASH_ENV=* | *' ENV='*)
          raw_evidence "$cur_text" \
            && deny_now "this command sets a shell hook variable whose value names a reserved act - refusing (fail closed). Run the command directly."
          ;;
      esac
      prev_text=$cur_text
      si=$((si + 1))
      continue
    fi
    verb=${SW[0]}
    # At the mission-control tier a command name that is a variable the command
    # assigned a plain literal is read as that literal.
    if [ "$TIER" = mission-control ] && [ "${SWL[0]}" != 1 ] && mc_resolve_word "$verb"; then
      verb=$MC_RW
      SW[0]=$verb
      SWL[0]=1
    fi
    lc "${verb##*/}"
    base_verb=$LC
    [ "$TIER" != worker ] || ! runs_force_push_helper "$base_verb" \
      || deny_now 'this command runs scripts/tower-force-push.sh; the force-push path is the tower'"'"'s, run on the operator'"'"'s request, never a worker'"'"'s. Name the reword or force-push in your handoff for the operator instead.'
    if kickoff_segment "$eff"; then
      prev_text=$cur_text
      si=$((si + 1))
      continue
    fi
    if [ "${SWL[0]}" != 1 ]; then
      # The command word is an expansion, so what runs cannot be read: only a
      # variable root followed by a literal script path is let through, and
      # even that not when a reserved subcommand follows.
      for_merge_check 0
      ! names_helper "$verb" || queue_merge_helper "$eff" "$eff_ok"
      [[ $verb =~ $RE_ROOTED_SCRIPT ]] \
        || deny_now "this command's name is an expansion the guard cannot read ($(sanitize_printable "$verb" 'unprintable')), so it could be git or gh - refusing (fail closed). Write the command name literally, or as \"\$ROOT/path/to/script\"."
      # A rooted git is git, and only a literal one is classified by subcommand.
      [ "$TIER" != mission-control ] || [ "$base_verb" != git ] \
        || deny_now "mission control runs no git mutation, and this git is named through an expansion whose subcommand the guard does not classify - refusing (fail closed). Call git by its plain name."
      for w in "${SW[@]}"; do
        lc "$w"
        if [[ $LC =~ $RESERVED_WORD_RE ]]; then
          deny_now "this command's name is an expansion the guard cannot read, and it is followed by a reserved subcommand ($(sanitize_printable "$w" 'one')) - refusing (fail closed). Write the command name literally."
          break
        fi
      done
    elif [ "$SW_WRAPPED" = 1 ]; then
      raw_evidence "$cur_text" \
        && deny_now "this command runs through a wrapper whose options the guard does not read, and its text names a reserved act - refusing (fail closed). Issue the command directly."
      tower_wrapped_git_check
    else
      local helper=0 a1 script_at=0 k opt_c=0 opt_s=0
      ! names_helper "$verb" || helper=1
      case $base_verb in
        bash | sh | zsh | dash | ksh | mksh)
          # A shell running the helper as its script, the plain form the
          # plugin-script convention allows. Its own options come first, up
          # to `--` or the first operand: -c hands a command string over (the
          # wrapper screen below reads it), and -s, or no operand, reads the
          # script from stdin, which counts as the helper when the command
          # names its stem; so does an operand that is a bare expansion.
          k=1
          while [ "$k" -lt "${#SW[@]}" ]; do
            case ${SW[$k]} in
              --)
                k=$((k + 1))
                break
                ;;
              -o | +o | -O | +O | --rcfile | --init-file) k=$((k + 2)) ;;
              --*) k=$((k + 1)) ;;
              [-+]*)
                case ${SW[$k]} in *c*) opt_c=1 ;; esac
                case ${SW[$k]} in *s*) opt_s=1 ;; esac
                # A cluster's o or O takes the next word as its value.
                a1=${SW[$k]//[!oO]/}
                k=$((k + 1 + ${#a1}))
                ;;
              *) break ;;
            esac
          done
          a1=${SW[$k]:-}
          if [ "$opt_c" = 0 ]; then
            script_at=$k
            if [ "$opt_s" = 0 ] && [ -n "$a1" ] && names_helper "$a1"; then
              helper=1
            elif [ "$opt_s" = 1 ] || [ -z "$a1" ] || [ "${SWL[$k]}" != 1 ]; then
              # Inferred from the command's text, not this segment's own
              # words, so the flag check below cannot be told apart from it:
              # the flag anywhere in the command refuses.
              lc "$P_CMD"
              if [[ $LC =~ $RE_MERGE_HELPER ]]; then
                helper=1
                [[ ! $LC =~ $RE_FOR_MERGE ]] \
                  || deny_now 'this shell runs a script the guard cannot name, in a command naming the merge helper and the --for-merge flag of scripts/ready-flip.sh - refusing (fail closed). Run the helper by its path on its own.'
              fi
            fi
          fi
          ;;
      esac
      for_merge_check "$script_at"
      if [ "$helper" = 1 ]; then
        queue_merge_helper "$eff" "$eff_ok"
        prev_text=$cur_text
        si=$((si + 1))
        continue
      fi
      case $base_verb in
        export | declare | typeset | readonly | local | let | printf)
          case " ${SW[*]} " in
            *" GIT_"*) GIT_ENV_SET=1 ;;
          esac
          # A value the shell later runs (a startup or prompt hook, an
          # arithmetic subscript) is screened as a command; printf sets one
          # only with -v.
          case "$base_verb: ${SW[*]} " in
            printf:*" -v"*) raw_evidence "$cur_text" && deny_now "this printf -v sets a value naming a reserved act - refusing (fail closed). Run the command directly." ;;
            printf:*) ;;
            *)
              raw_evidence "$cur_text" \
                && deny_now "this command sets or evaluates a value naming a reserved act through $(sanitize_printable "$verb" 'a builtin') - refusing (fail closed). Run the command directly."
              ;;
          esac
          ;;
      esac
      case $base_verb in
        xargs | parallel | find)
          local k=1 n=${#SW[@]}
          while [ "$k" -lt "$n" ]; do
            case $(lower "${SW[$k]##*/}") in
              git | gh)
                if [ "$((k + 1))" -ge "$n" ] || [[ $(lower "${SW[$((k + 1))]}") =~ $RESERVED_WORD_RE ]] \
                  || [[ ${SW[$((k + 1))]} == -* ]]; then
                  deny_now "this command hands git or gh arguments the guard cannot see to $(sanitize_printable "$verb" 'a wrapper') - refusing (fail closed). Run the git or gh command directly."
                fi
                ;;
            esac
            k=$((k + 1))
          done
          ;;
      esac
      case $base_verb in
        bash | sh | zsh | dash | ksh | mksh | fish | busybox | eval | source | . | xargs | parallel)
          # Fed by a pipe, the shell runs whatever the previous segment wrote.
          case ${SEG_TERM[$((si - 1))]:-} in
            '|' | '|&')
              [ "$si" = 0 ] || ! raw_evidence "$prev_text$NL$cur_text" \
                || deny_now "this command pipes text naming a reserved act into $(sanitize_printable "$verb" 'a shell') - refusing (fail closed). Run the command directly."
              ;;
          esac
          ;;
      esac
      case $base_verb in
        cd | pushd | popd)
          local term=${SEG_TERM[$si]}
          if [ "$verb" = cd ] && [ "${#SW[@]}" = 2 ] && [ "${SWL[1]}" = 1 ] \
            && { [ "$term" = '&&' ] || [ "$term" = ';' ] || [ "$term" = "$NL" ]; }; then
            case ${SW[1]} in
              /*) eff=${SW[1]} ;;
              -*) eff_ok=0 ;;
              *) eff="$eff/${SW[1]}" ;;
            esac
            [ -d "$eff" ] || eff_ok=0
          else
            eff_ok=0
          fi
          ;;
        git)
          GIT_ENV=0
          { [ "$SW_GITENV" = 0 ] && [ "$GIT_ENV_SET" = 0 ]; } || GIT_ENV=1
          classify_git "$si" "$eff" "$eff_ok"
          ;;
        gh)
          if [ "$verb" != gh ]; then
            case " ${SW[*]} " in
              *" api "*) deny_now "this gh api call names gh by a path or another spelling, which the guard does not place as the gh verb, so the request cannot be read - refusing (fail closed). Call it as plain gh api with a literal request." ;;
              *) classify_gh "$si" "$eff" "$eff_ok" ;;
            esac
          else
            classify_gh "$si" "$eff" "$eff_ok"
          fi
          ;;
        env | sudo | doas | xargs | nohup | nice | ionice | timeout | gtimeout | stdbuf | setsid | \
          chronic | eval | bash | sh | zsh | dash | ksh | mksh | fish | busybox | script | watch | \
          parallel | find | flock | unbuffer | caffeinate | source | . | ssh | tmux | screen | time | \
          strace | ltrace | chroot | unshare | systemd-run | su | runuser | fakeroot | make | \
          python* | perl | ruby | node | awk | gawk | mawk | nawk | trap | alias | mapfile | readarray | \
          complete | bind)
          raw_evidence "$cur_text" \
            && deny_now "this command hands its work to $(sanitize_printable "$verb" 'a wrapper'), whose argument the guard cannot read as a command, and its text names a reserved act - refusing (fail closed). Issue the command directly."
          tower_wrapped_git_check
          ;;
      esac
    fi
    prev_text=$cur_text
    si=$((si + 1))
  done
  kickoff_text_check
}

# --------------------------------------------------------------------------
# gh.

classify_gh() {
  local si=$1 eff=$2 eff_ok=$3 k=1 n=${#SW[@]}
  while [ "$k" -lt "$n" ]; do
    case ${SW[$k]} in
      -R | --repo) k=$((k + 2)) ;;
      --repo=* | -R?*) k=$((k + 1)) ;;
      -*)
        case " ${SW[*]} " in
          *" api "* | *" pr "*) deny_now "this gh call carries a leading option the guard does not read, so it cannot tell which command runs - refusing (fail closed). Put the subcommand first." ;;
          *" repo "*) [ "$TIER" != tower ] || deny_now "this gh call carries a leading option the guard does not read, so it cannot tell which command runs - refusing (fail closed). Put the subcommand first." ;;
        esac
        return 0
        ;;
      *) break ;;
    esac
  done
  [ "$k" -lt "$n" ] || return 0
  if [ "$TIER" = mission-control ]; then
    local j=$((k + 1))
    while [ "$j" -lt "$n" ]; do
      case ${SW[$j]} in
        -R | --repo) j=$((j + 2)) ;;
        --repo=* | -R?*) j=$((j + 1)) ;;
        *) break ;;
      esac
    done
    case "${SW[$k]} ${SW[$j]:-}" in
      'pr checkout' | 'pr co' | 'pr update-branch' | 'repo sync' | 'repo clone' | 'repo create' | 'repo delete' | \
        'repo set-default' | \
        'repo fork' | 'repo rename' | 'repo edit' | 'repo archive' | 'release create' | 'release delete' | \
        'release edit' | 'release upload' | 'release delete-asset')
        deny_now "mission control writes no branch on the host and edits no repository, and gh $(sanitize_printable "${SW[$k]} ${SW[$j]:-}" 'this command') does one or the other - refusing. Dispatch the change to a session."
        return 0
        ;;
    esac
  fi
  if [ "$TIER" = tower ]; then
    [ "${SWL[$k]}" = 1 ] || {
      deny_now 'this gh command names its top-level command through an expansion the guard cannot read, and it could be pr checkout or repo sync - refusing (fail closed). Write the command literally.'
      return 0
    }
    local j=$((k + 1))
    while [ "$j" -lt "$n" ]; do
      case ${SW[$j]} in
        -R | --repo) j=$((j + 2)) ;;
        --repo=* | -R?*) j=$((j + 1)) ;;
        *) break ;;
      esac
    done
    if [ "${SW[$k]}" = repo ] && [ "${SWL[$j]:-1}" != 1 ]; then
      deny_now 'this gh repo subcommand is an expansion the guard cannot read, and it could be repo sync - refusing (fail closed). Write the subcommand literally.'
      return 0
    fi
    if [ "${SW[$k]}" = co ]; then
      # gh's default configuration aliases co to pr checkout.
      deny_now "gh co is denied to the tower in every checkout, its own included, under every policy value: gh runs it as gh pr checkout, which moves a local branch, and the tower never moves a branch. Read the PR with gh pr view, and leave checkouts to a dispatched session."
      return 0
    fi
    case "${SW[$k]} ${SW[$j]:-}" in
      'pr checkout' | 'pr co' | 'repo sync')
        deny_now "gh $(sanitize_printable "${SW[$k]} ${SW[$j]:-}" 'this command') is denied to the tower in every checkout, its own included, under every policy value: it moves a local branch or a checkout's HEAD, and the tower never moves a branch. Read the PR with gh pr view, and leave checkouts to a dispatched session."
        return 0
        ;;
    esac
  fi
  case ${SW[$k]} in
    api) classify_gh_api "$si" "$((k + 1))" "$eff" "$eff_ok" ;;
    pr)
      # gh reads the --repo pair wherever it sits, so it may come between
      # `pr` and the subcommand too.
      k=$((k + 1))
      while [ "$k" -lt "$n" ]; do
        case ${SW[$k]} in
          -R | --repo) k=$((k + 2)) ;;
          --repo=* | -R?*) k=$((k + 1)) ;;
          *) break ;;
        esac
      done
      [ "${SWL[$k]:-1}" = 1 ] \
        || {
          deny_now 'this gh pr subcommand is an expansion the guard cannot read - refusing (fail closed). Write the subcommand literally.'
          return 0
        }
      case ${SW[$k]:-} in
        ready) classify_gh_ready "$((k + 1))" "$eff" "$eff_ok" ;;
        merge)
          local a
          for a in "${SW[@]:$((k + 1))}"; do
            case $a in --help | -h) return 0 ;; esac
          done
          deny_now 'gh pr merge is denied to every agent session under every merge_policy value; under policy-class the merge helper is the only sanctioned agent path, and otherwise the operator merges (or enables auto-merge). Leave the PR for the operator.'
          ;;
      esac
      ;;
  esac
}

classify_gh_ready() {
  local k=$1 eff=$2 eff_ok=$3 a undo=0 skip=0
  for a in "${SW[@]:$k}"; do
    if [ "$skip" = 1 ]; then
      skip=0
      continue
    fi
    case $a in
      -R | --repo) skip=1 ;;
      --help | -h) return 0 ;;
      --undo) undo=1 ;;
      --undo=*)
        case $(lower "${a#--undo=}") in
          false | f | 0) ;;
          *) undo=1 ;;
        esac
        ;;
    esac
  done
  if [ "$undo" = 1 ]; then
    deny_now 'gh pr ready --undo is denied: re-drafting a pull request is reserved to the corrective helper that follows a reviewer request (scripts/request-reviewer.sh). Ask the operator if a PR needs to go back to draft.'
    return 0
  fi
  # The policy is read from the repository the command runs in, so mission
  # control, which spans repositories, may flip only a PR of that one.
  if [ "$TIER" = mission-control ]; then
    local other=0
    for a in "${SW[@]}"; do
      case $a in -R | --repo | --repo=* | -R?* | *://*) other=1 ;; esac
    done
    case $P_CMD in *GH_REPO* | *GH_HOST*) other=1 ;; esac
    [ -z "${GH_REPO:-}" ] && [ -z "${GH_HOST:-}" ] || other=1
    if [ "$other" = 1 ]; then
      deny_now 'this flip names a repository (--repo, a PR URL, GH_REPO or GH_HOST) other than the one whose ready_flip_policy the guard reads - refusing. Run gh pr ready <number> from that repository'"'"'s own checkout.'
      return 0
    fi
  fi
  queue_flip "$eff" "$eff_ok"
}

queue_flip() {
  if [ "$TIER" = tower ]; then
    deny_now 'the tower never flips a pull request ready, under every ready_flip_policy value; the skill that executed the unit flips its own PR.'
    return 0
  fi
  [ "$2" = 1 ] \
    || {
      deny_now 'this flip runs after a directory change the guard cannot follow, so it cannot read the policy for that repository - refusing (fail closed). Issue gh pr ready on its own.'
      return 0
    }
  PENDING[${#PENDING[@]}]="flip$TAB$1"
}

# names_helper <word> — 0 when the word, as a command or a shell's script,
# could name the merge helper: its file name starts with the stem, matches
# merge-admitted.sh as a glob, or carries an expansion or brace the guard
# cannot resolve (fail closed). A bare expansion with no file name of its own
# is left to the caller.
names_helper() {
  local b
  lc "${1##*/}"
  b=$LC
  case $b in merge-ad*) return 0 ;; esac
  # A bare expansion, with no path of its own, names nothing here.
  case $1 in
    */*) ;;
    \$* | \"\$*) return 1 ;;
  esac
  case $b in
    *'$'* | *'`'* | *'{'*) return 0 ;;
    *'*'* | *'?'* | *'['*)
      # shellcheck disable=SC2053 # the word is the pattern
      [[ merge-admitted.sh == $b ]]
      return
      ;;
  esac
  return 1
}

# for_merge_check <index> — deny an agent's own run of scripts/ready-flip.sh
# with --for-merge, the merge helper's flag: the word at <index> (the command
# word, 0, or a shell's script operand) names ready-flip.sh and a later word
# is the flag, or a word that could expand into it (an unquoted brace, an
# expansion that is not the value of one of its value-taking options).
for_merge_check() {
  local k=$(($1 + 1)) n=${#SW[@]} w script=${SW[$1]:-}
  lc "${script##*/}"
  case $LC in
    *'{'* | *'$'* | *'`'*)
      # A script name the guard cannot resolve could be ready-flip.sh: only
      # the flag itself refuses, so an ordinary run with expansions defers.
      while [ "$k" -lt "$n" ]; do
        lc "${SW[$k]}"
        case $LC in
          *for-merge*)
            deny_now 'this run'"'"'s script name is an expansion or brace the guard cannot resolve, and it carries the --for-merge flag of scripts/ready-flip.sh, the merge helper'"'"'s own flip - refusing (fail closed). Run scripts/merge-admitted.sh by its path, or leave the PR for the operator.'
            return 0
            ;;
        esac
        k=$((k + 1))
      done
      return 0
      ;;
    ready-flip.sh | *'*'* | *'?'* | *'['*)
      # shellcheck disable=SC2053 # the word is the pattern
      [[ ready-flip.sh == $LC ]] || return 0
      ;;
    *) return 0 ;;
  esac
  local prev=''
  while [ "$k" -lt "$n" ]; do
    w=${SW[$k]}
    lc "$w"
    case $LC in
      --for-merge | --for-merge=*) ;;
      *)
        if [ "${SWL[$k]}" = 1 ]; then
          prev=$LC
          k=$((k + 1))
          continue
        fi
        case $LC in *'{'*) prev='' ;; esac
        case $prev in
          --spec | --task | --pr | --worktree | --out | --preconditions | --expect-head | --base | --reason)
            case $LC in
              -*) ;;
              *)
                prev=''
                k=$((k + 1))
                continue
                ;;
            esac
            ;;
        esac
        ;;
    esac
    deny_now 'the --for-merge flag of scripts/ready-flip.sh is the merge helper'"'"'s own flip of a PR its class admitted, and this run carries it or a word that could expand into it; no agent session issues it. Run scripts/merge-admitted.sh under merge_policy: policy-class, write ready-flip.sh'"'"'s options literally, or leave the PR for the operator.'
    return 0
  done
}

queue_merge_helper() {
  if [ "$TIER" = mission-control ]; then
    deny_now 'mission control never runs the merge helper (scripts/merge-admitted.sh), under every merge_policy value: it never merges.'
    return 0
  fi
  if [ "$TIER" = tower ]; then
    deny_now 'the tower never runs the merge helper (scripts/merge-admitted.sh), under every merge_policy value; the skill that owns the unit branch runs it.'
    return 0
  fi
  [ "$2" = 1 ] \
    || {
      deny_now 'this merge-helper run follows a directory change the guard cannot follow, so it cannot read merge_policy for that repository - refusing (fail closed). Run the helper on its own.'
      return 0
    }
  PENDING[${#PENDING[@]}]="merge-helper$TAB$1"
}

# gh api ------------------------------------------------------------------

ghapi_opaque() {
  deny_now "this gh api request cannot be read ($1), so the guard cannot rule out a reserved act - refusing (fail closed). Re-issue it with the endpoint, the method, and the query written inline as literal text: no variable, command substitution, @file or @- field, or --input body."
}

# norm_endpoint <endpoint> — the REST path with the scheme, host, /api/v3,
# leading slash, query string, and fragment removed.
norm_endpoint() {
  local e=$1
  case $e in
    http://* | https://*)
      e=${e#*://}
      case $e in */*) e=${e#*/} ;; *) e='' ;; esac
      ;;
  esac
  e=${e#/}
  case $e in api/v3/*) e=${e#api/v3/} ;; esac
  e=${e%%\#*}
  e=${e%%\?*}
  printf '%s' "$e"
}

classify_gh_api() {
  local si=$1 k=$2 eff=$3 eff_ok=$4 n=${#SW[@]} w wl name val endopts=0
  local method='' method_lit=1 nfields=0 endpoint='' endpoint_lit=1 npos=0 help=0
  local -a fields=() field_lit=()
  local query_lit=1 query_text=''

  take_value() { # sets VAL / VAL_LIT from the next word
    if [ "$((k + 1))" -ge "$n" ]; then
      return 1
    fi
    k=$((k + 1))
    VAL=${SW[$k]}
    VAL_LIT=${SWL[$k]}
  }
  add_field() { # <kind F|f> <text> <lit>
    local kind=$1 text=$2 l=$3 key=${2%%=*} v=${2#*=}
    fields[${#fields[@]}]=$text
    field_lit[${#field_lit[@]}]=$l
    nfields=$((nfields + 1))
    if [ "$kind" = F ]; then
      case $v in
        @*)
          ghapi_opaque "the field $(sanitize_printable "$key" 'a field') is read from a file or stdin"
          return 1
          ;;
      esac
    fi
    if [ "$key" = query ]; then
      [ "$l" = 1 ] || query_lit=0
      query_text="$query_text$v$NL"
    fi
    return 0
  }
  opt() { # <name> <value-or-empty> <has-value 0|1> <lit>
    local nm=$1 v=$2 hv=$3 l=$4
    case $nm in
      method | X)
        method=$v
        method_lit=$l
        ;;
      field | F) add_field F "$v" "$l" || return 1 ;;
      raw-field | f) add_field f "$v" "$l" || return 1 ;;
      input)
        ghapi_opaque 'it sends an --input body'
        return 1
        ;;
      header | H)
        case $(lower "$v") in
          x-http-method-override*)
            ghapi_opaque 'it overrides the method through a header'
            return 1
            ;;
        esac
        ;;
      cache | hostname | jq | q | preview | p | template | t) ;;
      *) return 2 ;;
    esac
    return 0
  }

  while [ "$k" -lt "$n" ]; do
    w=${SW[$k]}
    wl=${SWL[$k]}
    if [ "$endopts" = 1 ]; then
      npos=$((npos + 1))
      endpoint=$w
      endpoint_lit=$wl
      k=$((k + 1))
      continue
    fi
    case $w in
      --) endopts=1 ;;
      --*=*)
        name=${w%%=*}
        name=${name#--}
        val=${w#*=}
        case $name in
          include | paginate | silent | slurp | verbose | help)
            case $(lower "$val") in
              true | t | 1) [ "$name" != help ] || help=1 ;;
              # --help=false switches help off, so the request runs.
              false | f | 0) [ "$name" != help ] || help=0 ;;
              *)
                ghapi_opaque "the flag --$(sanitize_printable "$name" 'a flag') carries a value the guard does not parse"
                return 0
                ;;
            esac
            ;;
          *)
            opt "$name" "$val" 1 "$wl"
            case $? in
              1) return 0 ;;
              2)
                ghapi_opaque "it carries the flag --$(sanitize_printable "$name" 'an unknown flag'), which gh 2.96.0 does not define"
                return 0
                ;;
            esac
            ;;
        esac
        ;;
      --*)
        name=${w#--}
        case $name in
          include | paginate | silent | slurp | verbose) ;;
          help) help=1 ;;
          method | field | raw-field | input | header | cache | hostname | jq | preview | template)
            if ! take_value; then
              ghapi_opaque "the flag --$name has no value"
              return 0
            fi
            opt "$name" "$VAL" 1 "$VAL_LIT" || return 0
            ;;
          *)
            ghapi_opaque "it carries the flag --$(sanitize_printable "$name" 'an unknown flag'), which gh 2.96.0 does not define"
            return 0
            ;;
        esac
        ;;
      -)
        npos=$((npos + 1))
        endpoint=$w
        endpoint_lit=$wl
        ;;
      -*)
        # pflag bundles short flags; a value-taking one ends the bundle, its
        # value being the rest of the word (one leading `=` dropped) or the
        # next word.
        local b=${w#-} c rest
        while [ -n "$b" ]; do
          c=${b:0:1}
          rest=${b:1}
          case $c in
            i) b=$rest ;;
            h)
              help=1
              b=$rest
              ;;
            F | H | q | X | p | f | t)
              if [ -n "$rest" ]; then
                rest=${rest#=}
                opt "$c" "$rest" 1 "$wl" || return 0
              else
                if ! take_value; then
                  ghapi_opaque "the flag -$c has no value"
                  return 0
                fi
                opt "$c" "$VAL" 1 "$VAL_LIT" || return 0
              fi
              b=''
              ;;
            *)
              ghapi_opaque "it carries the flag -$(sanitize_printable "$c" '?'), which gh 2.96.0 does not define"
              return 0
              ;;
          esac
        done
        ;;
      *)
        npos=$((npos + 1))
        endpoint=$w
        endpoint_lit=$wl
        ;;
    esac
    k=$((k + 1))
  done

  [ "$help" = 0 ] || return 0
  if [ "$npos" != 1 ]; then
    ghapi_opaque "it names $npos endpoints where gh takes exactly one"
    return 0
  fi

  # The act's names, matched in the quote-removed text of every field,
  # whatever the endpoint and whatever the method.
  local all_fields='' f
  for f in ${fields[@]+"${fields[@]}"}; do
    all_fields="$all_fields$f$NL"
  done
  case $all_fields in
    *markPullRequestReadyForReview*)
      deny_now 'this gh api request marks a pull request ready; the gh api spelling is never the permitted path, because the ready-guard cannot check it. Use gh pr ready <number>, which the policy and the ready-guard both read.'
      return 0
      ;;
    *convertPullRequestToDraft*)
      deny_now 'this gh api request converts a pull request to draft; re-drafting is reserved to the corrective helper (scripts/request-reviewer.sh). Ask the operator if a PR needs to go back to draft.'
      return 0
      ;;
    *mergePullRequest* | *enablePullRequestAutoMerge* | *enqueuePullRequest*)
      deny_now 'this gh api request merges a pull request, enables auto-merge, or enqueues it; no agent merges through gh api under any merge_policy value. The operator merges or enables auto-merge (under policy-class, the merge helper is the only agent path).'
      return 0
      ;;
    *mergeBranch* | *updatePullRequestBranch*)
      deny_now 'this gh api request merges into a branch on the host; the gh api spelling of a base merge is never the permitted path. Merge the PR base locally, from a worker session in its own worktree: scripts/converge-sync-main.sh (on a task branch or a flight branch carrying its id), or git merge origin/main.'
      return 0
      ;;
    *updateRefs* | *updateRef* | *deleteRef*)
      deny_now 'this gh api request updates or deletes a ref through GraphQL, whose target and force flag the guard cannot read - refusing (fail closed). Push with git instead.'
      return 0
      ;;
  esac

  # The method: the last one given, else POST when a field is present (gh's
  # implied POST), else GET. graphql is a write whatever the method says
  # short of an explicit GET.
  local um is_write=1 ep
  if [ -n "$method" ]; then
    if [ "$method_lit" != 1 ]; then
      ghapi_opaque 'its method is not literal'
      return 0
    fi
    um=$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')
  elif [ "$nfields" -gt 0 ]; then
    um=POST
  else
    um=GET
  fi
  case $um in GET | HEAD) is_write=0 ;; esac
  [ "$is_write" = 1 ] || return 0

  [ "$endpoint_lit" = 1 ] || {
    ghapi_opaque 'it writes to an endpoint that is not literal'
    return 0
  }
  [ "$query_lit" = 1 ] || {
    ghapi_opaque 'its query field is not literal'
    return 0
  }
  case $query_text in
    *'{branch}'*)
      ghapi_opaque 'its query carries the {branch} placeholder'
      return 0
      ;;
  esac

  ep=$(norm_endpoint "$endpoint")
  case $ep in
    *%* | *..* | *//*)
      ghapi_opaque 'its path carries a percent escape, a dot segment, or an empty segment'
      return 0
      ;;
  esac

  # GraphQL writes that name a branch: the target must be a literal branch
  # name in the query, checked against the protected set.
  case $all_fields in
    *createCommitOnBranch* | *createRef*)
      # A variable or a comment in the query can carry the real target while
      # a literal one decoys the read, so either refuses.
      case $query_text in
        *'$'* | *'#'*)
          ghapi_opaque 'it creates a commit or a ref through a query carrying a variable or a comment, so its target branch cannot be read'
          return 0
          ;;
      esac
      local targets='' re='(branchName|qualifiedName|name)[[:space:]]*:[[:space:]]*"([^"]*)"' t rest=$query_text
      while [[ $rest =~ $re ]]; do
        t=${BASH_REMATCH[2]}
        rest=${rest#*"${BASH_REMATCH[0]}"}
        t=${t#refs/heads/}
        case $t in refs/*) continue ;; esac
        targets="$targets $t"
      done
      case "$targets" in
        '' | *'{branch}'* | *'$'*)
          ghapi_opaque 'it creates a commit or a ref on a branch it does not name literally in the query'
          return 0
          ;;
      esac
      # shellcheck disable=SC2086 # the target list, split on purpose (noglob is on)
      queue_protected "$eff" "$eff_ok" "this gh api commit or ref write" $targets
      return 0
      ;;
  esac

  # REST paths, matched case-insensitively.
  local lp seg_count
  lp=$(lower "$ep")
  local IFS_save=$IFS
  IFS=/
  # shellcheck disable=SC2086 # split on / on purpose (noglob is on)
  set -- $lp
  IFS=$IFS_save
  seg_count=$#
  [ "${1:-}" = repos ] || return 0
  case "$seg_count:${4:-}:${6:-}" in
    6:pulls:merge)
      deny_now 'this gh api request merges a pull request; no agent merges through gh api under any merge_policy value. The operator merges or enables auto-merge.'
      return 0
      ;;
    6:pulls:update-branch)
      deny_now 'this gh api request updates a pull request branch from its base on the host; merge the PR base locally instead, from a worker session in its own worktree: scripts/converge-sync-main.sh (on a task branch or a flight branch carrying its id), or git merge origin/main.'
      return 0
      ;;
  esac
  case "$seg_count:${4:-}" in
    4:merges | 4:merge-upstream)
      deny_now 'this gh api request merges into a branch on the host; the gh api spelling of a base merge is never the permitted path. Merge the PR base locally, from a worker session in its own worktree: scripts/converge-sync-main.sh (on a task branch or a flight branch carrying its id), or git merge origin/main.'
      return 0
      ;;
  esac
  if [ "${4:-}" = git ] && [ "${5:-}" = refs ]; then
    local fv force='' ref_target=''
    local i2=0
    while [ "$i2" -lt "${#fields[@]}" ]; do
      fv=${fields[$i2]}
      case $fv in
        force=*)
          [ "${field_lit[$i2]}" = 1 ] || {
            ghapi_opaque 'its force field is not literal'
            return 0
          }
          force=$(lower "${fv#force=}")
          ;;
        ref=*)
          [ "${field_lit[$i2]}" = 1 ] || {
            ghapi_opaque 'its ref field is not literal'
            return 0
          }
          ref_target=${fv#ref=}
          ;;
      esac
      i2=$((i2 + 1))
    done
    case $force in
      '' | false | 0) ;;
      *)
        deny_now 'this gh api request force-updates a ref; a forced ref update is never permitted to an agent session through gh api. Push new commits with git instead.'
        return 0
        ;;
    esac
    # The target: the path after git/refs/, or the ref field on a create.
    local orig_rest=${lp#*/*/*/git/refs}
    orig_rest=${orig_rest#/}
    [ -n "$orig_rest" ] || orig_rest=$ref_target
    orig_rest=${orig_rest#refs/}
    case $orig_rest in
      '')
        return 0
        ;;
      *'{branch}'*)
        ghapi_opaque 'its ref target carries the {branch} placeholder'
        return 0
        ;;
      heads/*)
        queue_protected "$eff" "$eff_ok" "this gh api ref write" "${orig_rest#heads/}"
        ;;
    esac
    return 0
  fi
  if [ "${4:-}" = branches ] && [ "$seg_count" -ge 6 ] && [ "${!seg_count}" = rename ]; then
    # A rename writes both branches: the one it moves away and the one it creates.
    local renamed=${ep#*/*/*/branches/}
    renamed=${renamed%/rename}
    case $renamed in
      *'{branch}'*)
        ghapi_opaque 'its renamed branch is the {branch} placeholder'
        return 0
        ;;
    esac
    local fv new_name='' i2=0
    while [ "$i2" -lt "${#fields[@]}" ]; do
      fv=${fields[$i2]}
      case $fv in
        new_name=*)
          [ "${field_lit[$i2]}" = 1 ] || {
            ghapi_opaque 'its new_name field is not literal'
            return 0
          }
          new_name=${fv#new_name=}
          ;;
      esac
      i2=$((i2 + 1))
    done
    case $new_name in
      '' | *'{branch}'*)
        ghapi_opaque 'its new_name field is not a literal branch name'
        return 0
        ;;
    esac
    queue_protected "$eff" "$eff_ok" "this gh api branch rename" "$renamed" "$new_name"
    return 0
  fi
  if [ "${4:-}" = contents ] && [ "$seg_count" -ge 5 ]; then
    local fv br='' have_br=0 i2=0
    while [ "$i2" -lt "${#fields[@]}" ]; do
      fv=${fields[$i2]}
      case $fv in
        branch=*)
          [ "${field_lit[$i2]}" = 1 ] || {
            ghapi_opaque 'its branch field is not literal'
            return 0
          }
          br=${fv#branch=}
          have_br=1
          ;;
      esac
      i2=$((i2 + 1))
    done
    if [ "$have_br" = 0 ]; then
      deny_now 'this gh api contents write names no branch, so it writes the repository default branch, which is protected - refusing. Name your own unit branch in a literal branch field.'
      return 0
    fi
    case $br in
      *'{branch}'* | '')
        ghapi_opaque 'its branch field is not a literal branch name'
        return 0
        ;;
    esac
    queue_protected "$eff" "$eff_ok" "this gh api contents write" "${br#refs/heads/}"
  fi
  return 0
}

# queue_protected <eff> <eff_ok> <what> <branch...>
queue_protected() {
  local eff=$1 eff_ok=$2 what=$3 b
  shift 3
  if [ "$TIER" = mission-control ]; then
    deny_now "mission control writes no branch on the host, and $what writes or deletes one; every change goes through a session it dispatches - refusing."
    return 0
  fi
  for b in "$@"; do
    valid_branch "$b" \
      || {
        deny_now "$what targets a ref name the guard will not check ($(sanitize_printable "$b" 'unprintable')) - refusing (fail closed)."
        return 0
      }
  done
  [ "$eff_ok" = 1 ] \
    || {
      deny_now "$what runs after a directory change the guard cannot follow, so it cannot read the protected set for that repository - refusing (fail closed). Issue it on its own."
      return 0
    }
  PENDING[${#PENDING[@]}]="protected$TAB$eff$TAB$what$TAB$*"
}

# --------------------------------------------------------------------------
# git.

GIT_BUILTINS=' add am annotate apply archive backfill bisect blame branch bugreport bundle cat-file check-attr check-ignore check-mailmap check-ref-format checkout checkout-index cherry cherry-pick citool clean clone column commit commit-graph commit-tree config count-objects credential describe diagnose diff diff-files diff-index diff-tree difftool fast-export fast-import fetch fetch-pack filter-branch for-each-ref for-each-repo format-patch fsck gc get-tar-commit-id grep gui hash-object help hook index-pack init instaweb interpret-trailers log ls-files ls-remote ls-tree mailinfo mailsplit maintenance merge merge-base merge-file merge-index merge-tree mergetool mktag mktree multi-pack-index mv name-rev notes pack-objects pack-redundant pack-refs patch-id prune prune-packed pull push range-diff read-tree rebase reflog refs remote repack replace replay repo request-pull rerere reset restore rev-list rev-parse revert rm send-email send-pack shortlog show show-branch show-index show-ref sparse-checkout stash status stripspace submodule switch symbolic-ref tag unpack-file unpack-objects update-index update-ref update-server-info var verify-commit verify-pack verify-tag version whatchanged worktree write-tree '

GIT_ENV=0

# The git subcommands that only read, whatever their arguments, once the
# writing and executing flags below are refused.
MC_GIT_READS=' status log show diff rev-parse ls-files ls-remote ls-tree cat-file for-each-ref merge-base describe blame annotate grep shortlog rev-list name-rev show-ref show-branch whatchanged var count-objects check-ignore check-attr check-mailmap check-ref-format diff-tree diff-files diff-index range-diff cherry version verify-commit verify-tag patch-id '

# mc_git_reads <subcommand> <first-arg-index> — 0 when the git segment in SW[]
# only reads: an inspection command with no flag that writes a file or runs a
# program, or the listing form of a command that can also write, whose read
# verb comes first. An option is skipped only when it is known: one the guard
# cannot place may take the next word as its value, so it counts as a write.
mc_git_reads() {
  local sub=$1 a first=${SW[$2]:-} pos=0 list=0 skip=0 after=0
  for a in "${SW[@]:$2}"; do
    [ "$a" != -- ] || break
    # git takes any unambiguous prefix of a long option, so the prefixes
    # refuse too.
    case $a in
      --outp* | --ext* | --textc*) return 1 ;;
    esac
    case $sub:$a in
      grep:--op* | grep:-O* | grep:-[!-]*O* | ls-remote:--u* | ls-remote:--exec* | cat-file:--fil*) return 1 ;;
    esac
  done
  case " $MC_GIT_READS " in *" $sub "*) return 0 ;; esac
  case $sub in
    stash | notes)
      case $first in list | show) return 0 ;; esac
      return 1
      ;;
    worktree) [ "$first" = list ] && return 0 || return 1 ;;
    reflog)
      case $first in '' | show | exists | -*) ;; *) return 1 ;; esac
      for a in "${SW[@]:$2}"; do
        case $a in expire | delete | drop) return 1 ;; esac
      done
      return 0
      ;;
    remote)
      case $first in show | get-url) return 0 ;; esac
      for a in "${SW[@]:$2}"; do
        case $a in -v | --verbose) ;; *) return 1 ;; esac
      done
      return 0
      ;;
  esac
  for a in "${SW[@]:$2}"; do
    if [ "$skip" = 1 ]; then
      skip=0
      continue
    fi
    if [ "$after" = 1 ]; then
      pos=$((pos + 1))
      continue
    fi
    case $sub:$a in
      *:--) after=1 ;;
      branch:-l | branch:--list | tag:-l | tag:--list) list=1 ;;
      branch:--contains | branch:--no-contains | branch:--merged | branch:--no-merged | branch:--points-at | \
        branch:--sort | branch:--format | tag:--contains | tag:--no-contains | tag:--merged | \
        tag:--no-merged | tag:--points-at | tag:--sort | tag:--format) skip=1 ;;
      branch:-a | branch:--all | branch:-r | branch:--remotes | branch:-v | branch:-vv | branch:--verbose | \
        branch:--show-current | branch:-i | branch:--ignore-case | branch:--omit-empty | \
        branch:--column | branch:--no-column | branch:--color | branch:--no-color | branch:--no-abbrev | \
        tag:-n | tag:-n[0-9]* | tag:-i | tag:--ignore-case | tag:--omit-empty | tag:--column | \
        tag:--no-column | tag:--color | branch:--abbrev=*) ;;
      branch:--contains=* | branch:--no-contains=* | branch:--merged=* | branch:--no-merged=* | \
        branch:--points-at=* | branch:--sort=* | branch:--format=* | branch:--column=* | branch:--color=* | \
        tag:--contains=* | tag:--no-contains=* | tag:--merged=* | tag:--no-merged=* | tag:--points-at=* | \
        tag:--sort=* | tag:--format=* | tag:--column=* | tag:--color=*) ;;
      config:--get | config:--get-all | config:--get-regexp | config:--get-urlmatch | config:--list | \
        config:-l | config:--get-colors | config:--get-color) list=1 ;;
      config:--global | config:--system | config:--local | config:--worktree | config:--show-origin | \
        config:--show-scope | config:--null | config:-z | config:--name-only | config:--includes | \
        config:--no-includes | config:--all | config:--regexp | config:--fixed-value | config:--bool | \
        config:--int | config:--path | config:--type=* | config:--default=* | config:--url=* | \
        config:--value=*) ;;
      symbolic-ref:-q | symbolic-ref:--quiet | symbolic-ref:--short | symbolic-ref:--no-recurse) ;;
      *:-*) return 1 ;;
      *) pos=$((pos + 1)) ;;
    esac
  done
  case $sub in
    branch | tag) [ "$pos" = 0 ] || [ "$list" = 1 ] ;;
    config)
      case $first in get | list) return 0 ;; esac
      [ "$list" = 1 ]
      ;;
    symbolic-ref) [ "$pos" = 1 ] ;;
    *) return 1 ;;
  esac
}

classify_git() {
  local si=$1 k=1 n=${#SW[@]} w key foreign=0 cflag=0 dir=$2 dir_ok=$3 sub='' a
  while [ "$k" -lt "$n" ]; do
    w=${SW[$k]}
    case $w in
      -C)
        k=$((k + 1))
        [ "$k" -lt "$n" ] || return 0
        if [ "${SWL[$k]}" != 1 ]; then
          dir_ok=0
        else
          case ${SW[$k]} in
            /*) dir=${SW[$k]} ;;
            *) dir="$dir/${SW[$k]}" ;;
          esac
        fi
        ;;
      -C?*)
        case ${w#-C} in
          /*) dir=${w#-C} ;;
          *) dir="$dir/${w#-C}" ;;
        esac
        [ "${SWL[$k]}" = 1 ] || dir_ok=0
        ;;
      -c | --config-env)
        cflag=1
        k=$((k + 1))
        key=${SW[$k]:-}
        git_config_key_check "$key" || return 0
        ;;
      -c?* | --config-env=*)
        cflag=1
        key=${w#-c}
        key=${key#--config-env=}
        git_config_key_check "$key" || return 0
        ;;
      --git-dir | --work-tree | --namespace | --super-prefix | --attr-source | --list-cmds)
        foreign=1
        k=$((k + 1))
        ;;
      --git-dir=* | --work-tree=* | --namespace=* | --super-prefix=* | --attr-source=* | --bare | --exec-path=* | --list-cmds=*)
        foreign=1
        ;;
      -p | -P | --paginate | --no-pager | --no-replace-objects | --no-lazy-fetch | --no-optional-locks | \
        --no-advice | --literal-pathspecs | --glob-pathspecs | --noglob-pathspecs | --icase-pathspecs) ;;
      --exec-path | --html-path | --man-path | --info-path | --version | --help | -v | -h) return 0 ;;
      -*)
        # A global option the guard does not know: it cannot tell whether it
        # takes the next word, so it cannot find the subcommand.
        deny_now "this git command carries a global option the guard does not read ($(sanitize_printable "$w" 'unprintable')) - refusing (fail closed). Put the subcommand first."
        return 0
        ;;
      *)
        sub=$w
        break
        ;;
    esac
    k=$((k + 1))
  done
  [ -n "$sub" ] || return 0
  [ "${SWL[$k]}" = 1 ] || {
    deny_now 'this git command names its subcommand through an expansion the guard cannot read - refusing (fail closed). Write the subcommand literally.'
    return 0
  }
  [ -d "$dir" ] || dir_ok=0

  # A case-insensitive filesystem runs `git REBASE` as git-rebase.
  lc "$sub"
  case $LC in
    merge | pull | rebase | commit | push)
      [ "$sub" = "$LC" ] \
        || {
          deny_now "this git subcommand is a reserved one spelled in another case ($(sanitize_printable "$sub" 'unprintable')) - refusing. Spell it in lower case."
          return 0
        }
      ;;
  esac
  # git help is no read (--web and the configured man viewers run a
  # program), but it changes nothing either: the guard leaves it to the
  # operator's prompt.
  if [ "$TIER" = mission-control ] && [ "$LC" = help ]; then
    return 0
  fi
  if [ "$TIER" = mission-control ]; then
    # Configuration, environment and a moved exec path can make any read run
    # a program (an fsmonitor, an external diff, a pager, a remote helper).
    local gw
    for gw in "${SW[@]:1:$((k - 1))}"; do
      case $gw in --exec-path=*) cflag=1 ;; esac
    done
    if [ "$cflag" = 1 ] || [ "$GIT_ENV" = 1 ] || [ "$ST_CFG" = 1 ]; then
      deny_now "mission control runs no git mutation, and this git command carries -c configuration or a GIT_* variable, which can make even a read run a program - refusing (fail closed). Run it without them."
      return 0
    fi
    case " $GIT_BUILTINS " in
      *" $LC "*)
        mc_git_reads "$LC" "$((k + 1))" \
          || deny_now "mission control runs no git mutation (git $(sanitize_printable "$sub" 'this subcommand') in this form can change a repository); every change goes through a session it dispatches - refusing. Read with a listing or inspection form, or dispatch the change."
        ;;
      *) deny_now "mission control runs no git mutation, and git $(sanitize_printable "$sub" 'this subcommand') is an alias or an external command the guard does not follow - refusing (fail closed). Run the git subcommand directly." ;;
    esac
    return 0
  fi
  # git remote fetches too (remote update, remote add -f), from the same
  # configuration; its read forms (none, show, get-url) fetch nothing.
  local rsub=''
  if [ "$LC" = remote ]; then
    for a in "${SW[@]:$((k + 1))}"; do
      case $a in -*) ;; *)
        rsub=$a
        break
        ;;
      esac
    done
  fi
  if [ "$TIER" = tower ] && { [ "$LC" = fetch ] || { [ "$LC" = remote ] && [ -n "$rsub" ] && [ "$rsub" != show ] && [ "$rsub" != get-url ]; }; } \
    && { [ "$cflag" = 1 ] || [ "$GIT_ENV" = 1 ] || [ "$ST_CFG" = 1 ]; }; then
    deny_now "this git $LC runs with -c configuration, a GIT_* variable, or a git config or remote change in the same command, any of which can set a refspec writing a local branch where the guard cannot read it - refusing (fail closed). Run it on its own, without them."
    return 0
  fi
  [ "$TIER" != tower ] || classify_tower_git "$LC" "$k" "$dir" "$dir_ok"

  case " $GIT_BUILTINS " in
    *" $sub "*) ;;
    *)
      if [ "$GIT_ENV" = 1 ] || [ "$ST_CFG" = 1 ]; then
        deny_now "this git $(sanitize_printable "$sub" 'subcommand') runs where git configuration is set in the same command or its environment (a GIT_* variable, git config, or git remote), so the guard cannot tell what it runs - refusing (fail closed). Run the configuration change and the command separately."
        return 0
      fi
      # The alias lookup falls back to the payload's directory, which is not
      # the repository git reads its aliases from here.
      if [ "$TIER" = tower ] && { [ "$foreign" = 1 ] || [ "$dir_ok" = 0 ]; }; then
        deny_now "this git $(sanitize_printable "$sub" 'subcommand') may be an alias of a repository or directory the guard cannot follow (one named by a global option such as --git-dir, or a cd or -C target it cannot read), so the guard cannot read what it expands to - refusing (fail closed). Run the git subcommand directly, or use git -C <literal path>."
        return 0
      fi
      git_alias_check "$sub" "$dir" "$dir_ok"
      return 0
      ;;
  esac

  G_FOREIGN=$foreign
  G_CFLAG=$cflag
  classify_git_act "$sub" "$k" "$dir" "$dir_ok"
  git_state_after "$sub" "$((k + 1))"
}

# act_gate <what> <kind> — refuse a reserved act whose repository, config, or
# state the guard cannot read: a foreign repository option, a GIT_* variable
# or -c setting, or a change an earlier segment of the same command makes.
# <kind> is merge, rewrite, or push. Returns 1 after queuing the refusal.
act_gate() {
  local what=$1 kind=$2
  if [ "$G_FOREIGN" = 1 ]; then
    deny_now "$what carries --git-dir, --work-tree, --namespace, --attr-source, or --bare, which the guard does not follow - refusing (fail closed). Use git -C <dir> instead."
    return 1
  fi
  if [ "$GIT_ENV" = 1 ]; then
    deny_now "$what runs with a GIT_* environment variable set in the same command, which can redirect its repository or configuration where the guard cannot read it - refusing (fail closed). Run it without the variable."
    return 1
  fi
  if [ "$G_CFLAG" = 1 ]; then
    deny_now "$what carries -c configuration, which can change what it does (a pull into a rebase, a push into a mirror) where the guard cannot read it - refusing (fail closed). Run it without -c."
    return 1
  fi
  if [ "$ST_CFG" = 1 ] || [ "$ST_REF" = 1 ]; then
    deny_now "$what follows a git config, remote, branch, checkout, switch, reset, or ref change in the same command; the guard checks the state as it is before the command runs - refusing (fail closed). Run the change first, as its own command."
    return 1
  fi
  if [ "$kind" = rewrite ] && { [ "$ST_PUSH" = 1 ] || [ "$ST_FETCH" = 1 ] || [ "$ST_HEAD" = 1 ]; }; then
    deny_now "$what follows a push, a fetch, or a commit-making command (a merge, pull, commit, cherry-pick, am, revert, or rebase) in the same command, which moves what the rewrite would reach after the guard read it - refusing (fail closed). Run that command first, on its own."
    return 1
  fi
  if [ "$kind" = merge ] && [ "$ST_FETCHSPEC" = 1 ]; then
    deny_now "$what follows a fetch that writes a local ref in the same command - refusing (fail closed). Run the fetch first, as its own command."
    return 1
  fi
  return 0
}

# git_state_after <sub> <first-arg-index> — record what this git segment
# changes for the segments after it.
git_state_after() {
  local a pos=0 ro=0 rsub=''
  for a in "${SW[@]:$2}"; do
    case $a in -*) ;; *) [ -n "$rsub" ] || rsub=$a ;; esac
    case $a in
      --get | --get-all | --get-regexp | --get-urlmatch | --list | -l | --show-current | -v | -vv | show | get-url | list) ro=1 ;;
      -*) ;;
      *) pos=$((pos + 1)) ;;
    esac
  done
  case $1 in
    config) [ "$ro" = 1 ] || [ "$pos" -lt 2 ] || ST_CFG=1 ;;
    # A remote's own name or URL may be a read word, so only the subcommand
    # decides.
    remote)
      case $rsub in '' | show | get-url) ;; *) ST_CFG=1 ;; esac
      ;;
    branch | tag) [ "$ro" = 1 ] || [ "$pos" = 0 ] || ST_REF=1 ;;
    switch | checkout | update-ref | symbolic-ref | reset | worktree | stash | replace | notes) ST_REF=1 ;;
    merge | pull | commit | cherry-pick | am | revert | rebase) ST_HEAD=1 ;;
    push) ST_PUSH=1 ;;
    fetch)
      ST_FETCH=1
      for a in "${SW[@]:$2}"; do
        case $a in -*) ;; *:*) ST_FETCHSPEC=1 ;; esac
      done
      ;;
  esac
}

# classify_git_act <sub> <sub-index> <dir> <dir_ok>
classify_git_act() {
  local sub=$1 k=$2 dir=$3 dir_ok=$4 a
  case $sub in
    merge | pull | rebase | commit | push) ;;
    *) return 0 ;;
  esac
  for a in "${SW[@]:$((k + 1))}"; do
    case $a in
      --) break ;;
      --help | -h) return 0 ;;
    esac
  done
  case $sub in
    merge) classify_git_merge "$((k + 1))" "$dir" "$dir_ok" ;;
    pull) classify_git_pull "$((k + 1))" "$dir" "$dir_ok" ;;
    rebase) classify_git_rebase "$((k + 1))" "$dir" "$dir_ok" ;;
    commit) classify_git_commit "$((k + 1))" "$dir" "$dir_ok" ;;
    push) classify_git_push "$((k + 1))" "$dir" "$dir_ok" ;;
  esac
}

git_config_key_check() {
  local key
  key=$(lower "${1%%=*}")
  case $key in
    alias.* | include.* | includeif.* | help.*)
      deny_now 'this git command sets an alias, an include, or autocorrection on the command line, so the guard cannot tell which subcommand will run - refusing (fail closed). Run the subcommand by its own name.'
      return 1
      ;;
  esac
  return 0
}

# git_alias_check — an unknown subcommand may be a configured alias, or
# autocorrected into a reserved one.
git_alias_check() {
  local sub=$1 dir=$2 dir_ok=$3 v ac first
  case $sub in
    *[!A-Za-z0-9_.-]* | -*) return 0 ;;
  esac
  # Where the directory cannot be followed, the payload's own still shows the
  # global aliases.
  [ "$dir_ok" = 1 ] || dir=$PAYLOAD_CWD
  [ -d "$dir" ] || dir=/
  v=$(gitq "$dir" config --get "alias.$sub") || v=''
  if [ -n "$v" ]; then
    case $v in
      '!'*)
        # A shell alias can reach any act, through another alias or text it
        # builds, so it is refused whatever it names.
        deny_now "the git alias $(sanitize_printable "$sub" 'used here') runs a shell command, which the guard does not read - refusing (fail closed). Run the commands directly."
        ;;
      *)
        first=${v#"${v%%[![:space:]]*}"}
        first=${first%%[[:space:]]*}
        case $first in
          [A-Za-z]*)
            case " $GIT_BUILTINS " in
              *" $first "*)
                case $(lower "$first") in
                  merge | pull | rebase | commit | push)
                    deny_now "the git alias $(sanitize_printable "$sub" 'used here') expands to git $(sanitize_printable "$first" 'a reserved subcommand'), which the guard reads only by its own name - refusing. Run git $(sanitize_printable "$first" 'that subcommand') directly."
                    ;;
                  reset | branch | worktree | update-ref | filter-branch | checkout | switch | symbolic-ref | \
                    fetch | stash | remote)
                    [ "$TIER" != tower ] \
                      || deny_now "the git alias $(sanitize_printable "$sub" 'used here') expands to git $(sanitize_printable "$first" 'a subcommand the tower floor covers'), which the guard reads only by its own name - refusing. Run git $(sanitize_printable "$first" 'that subcommand') directly."
                    ;;
                esac
                ;;
              *)
                deny_now "the git alias $(sanitize_printable "$sub" 'used here') expands to another alias or an unknown command, which the guard does not follow - refusing (fail closed). Run the git subcommand directly."
                ;;
            esac
            ;;
          *)
            deny_now "the git alias $(sanitize_printable "$sub" 'used here') starts with an option or a quote, which the guard does not read - refusing (fail closed). Run the git subcommand directly."
            ;;
        esac
        ;;
    esac
    return 0
  fi
  # An external git-<sub> on PATH runs as itself; only an unknown name can be
  # autocorrected into a reserved one.
  command -v "git-$sub" >/dev/null 2>&1 && return 0
  ac=$(gitq "$dir" config --get help.autocorrect) || ac=''
  case $(lower "$ac") in
    '' | 0 | false | never | show | no | off) ;;
    *)
      deny_now "git is configured to autocorrect an unknown subcommand ($(sanitize_printable "$sub" 'this one')), so the guard cannot tell what will run - refusing (fail closed). Spell the subcommand correctly."
      ;;
  esac
}

# parse_git_opts <start> <value-longs> <value-shorts> <optval-shorts> — walk
# the words from <start>, setting GP_POS[] (positionals with GP_POSL[]),
# GP_LONG (space-joined long option names seen, values dropped), GP_SHORT
# (short flag chars seen), and GP_LITLONG and GP_LITSHORT, the same from
# literal words only. Returns 1 with GP_ERR when a flag cannot be read.
parse_git_opts() {
  local k=$1 vlong=" $2 " vshort=$3 ovshort=$4 n=${#SW[@]} w lit name endopts=0 b c
  GP_POS=()
  GP_POSL=()
  GP_LONG=' '
  GP_SHORT=''
  GP_LITLONG=' '
  GP_LITSHORT=''
  GP_VALS=()
  GP_ERR=''
  while [ "$k" -lt "$n" ]; do
    w=${SW[$k]}
    lit=${SWL[$k]}
    if [ "$endopts" = 1 ]; then
      GP_POS[${#GP_POS[@]}]=$w
      GP_POSL[${#GP_POSL[@]}]=${SWL[$k]}
      k=$((k + 1))
      continue
    fi
    case $w in
      --)
        endopts=1
        ;;
      --*=*)
        name=${w%%=*}
        GP_LONG="$GP_LONG${name#--} "
        [ "$lit" != 1 ] || GP_LITLONG="$GP_LITLONG${name#--} "
        ;;
      --*)
        name=${w#--}
        case $vlong in
          *" $name "*)
            k=$((k + 1))
            [ "$k" -lt "$n" ] || {
              GP_ERR="--$name has no value"
              return 1
            }
            GP_LONG="$GP_LONG$name "
            [ "$lit" != 1 ] || GP_LITLONG="$GP_LITLONG$name "
            ;;
          *" $name"*)
            GP_ERR="--$name abbreviates an option that takes a value"
            return 1
            ;;
          *)
            GP_LONG="$GP_LONG$name "
            [ "$lit" != 1 ] || GP_LITLONG="$GP_LITLONG$name "
            ;;
        esac
        ;;
      -)
        GP_POS[${#GP_POS[@]}]=$w
        GP_POSL[${#GP_POSL[@]}]=${SWL[$k]}
        ;;
      -*)
        b=${w#-}
        while [ -n "$b" ]; do
          c=${b:0:1}
          b=${b:1}
          GP_SHORT="$GP_SHORT$c"
          [ "$lit" != 1 ] || GP_LITSHORT="$GP_LITSHORT$c"
          case $vshort in
            *"$c"*)
              if [ -z "$b" ]; then
                k=$((k + 1))
                [ "$k" -lt "$n" ] || {
                  GP_ERR="-$c has no value"
                  return 1
                }
                GP_VALS[${#GP_VALS[@]}]="$c=${SW[$k]}"
              else
                GP_VALS[${#GP_VALS[@]}]="$c=$b"
              fi
              b=''
              ;;
            *)
              case $ovshort in
                *"$c"*) b='' ;;
              esac
              ;;
          esac
        done
        ;;
      *)
        GP_POS[${#GP_POS[@]}]=$w
        GP_POSL[${#GP_POSL[@]}]=${SWL[$k]}
        ;;
    esac
    k=$((k + 1))
  done
  return 0
}

# long_prefix_seen <full-name> <min-length> [<names>] — 0 when <names>
# (default GP_LONG) carries an option git would read as <full-name>: the name
# itself or a prefix of it at least <min-length> long (git takes any unique
# prefix of a long option).
long_prefix_seen() {
  local t name
  for t in ${3-$GP_LONG}; do
    name=${t%%=*}
    [ "${#name}" -ge "$2" ] || continue
    [ "$name" != "${1:0:${#name}}" ] || return 0
  done
  return 1
}

all_literal() {
  local l
  for l in ${GP_POSL[@]+"${GP_POSL[@]}"}; do
    [ "$l" = 1 ] || return 1
  done
  return 0
}

need_dir() { # <dir_ok> <what>
  [ "$1" = 1 ] \
    || {
      deny_now "$2 runs after a directory change, or with a git -C target, that the guard cannot follow, so it cannot read that repository - refusing (fail closed). Issue it on its own from the worktree, or with git -C <literal path>."
      return 1
    }
}

tower_refuses() { # <what> [<remedy>]
  if [ "$TIER" = tower ]; then
    deny_now "$1 is denied to the tower under every policy value; the tower never merges into a branch or rewrites history.${2:-}"
    return 0
  fi
  return 1
}

# tower_opts_literal <start> <what> — 0 when every word before `--` is
# literal; otherwise queues the refusal, since an expansion could spell the
# option the tower is refused.
tower_opts_literal() {
  local k=$1 n=${#SW[@]}
  while [ "$k" -lt "$n" ] && [ "${SW[$k]}" != -- ]; do
    [ "${SWL[$k]}" = 1 ] \
      || {
        deny_now "$2 carries an expansion the guard cannot read, which could spell an option the tower is refused - refusing (fail closed). Write its options literally, and put expanded names after --."
        return 1
      }
    k=$((k + 1))
  done
  return 0
}

# classify_tower_git <lower-case sub> <sub-index> <dir> <dir_ok> — the acts
# the tower deny list blocks that no other act covers: moving a branch, a
# checkout's HEAD, or a ref, rewriting history by hand, writing the stash,
# and the dangerous git worktree forms.
classify_tower_git() {
  local sub=$1 k=$(($2 + 1)) dir=$3 dir_ok=$4
  case $sub in
    update-ref | filter-branch | filter-repo)
      deny_now "git $sub moves refs or rewrites history by hand; it is denied to the tower under every policy value, since the tower never moves a branch."
      return 0
      ;;
    reset | checkout | switch)
      # Every form, a path restore included, so the guard never has to tell
      # the forms apart.
      deny_now "git $sub is denied to the tower in every form and every checkout, its own included, under every policy value: it can move a branch or a checkout's HEAD, and the tower never moves a branch. Leave the change to a dispatched session in its own worktree."
      ;;
    symbolic-ref)
      tower_opts_literal "$k" 'this git symbolic-ref' || return 0
      parse_git_opts "$k" '' 'm' '' \
        || {
          deny_now "this git symbolic-ref carries an option the guard cannot read ($GP_ERR) - refusing (fail closed). Spell its options in full."
          return 0
        }
      if long_prefix_seen delete 1 || [[ $GP_SHORT == *d* ]] || [ "${#GP_POS[@]}" -ge 2 ]; then
        deny_now 'a git symbolic-ref write (a second name, or -d) is denied to the tower under every policy value: it repoints HEAD or another symbolic ref, and the tower never moves a branch. Read it with one name.'
      fi
      ;;
    fetch) classify_tower_fetch "$k" ;;
    remote) classify_tower_remote "$k" ;;
    stash)
      if [ "$k" -lt "${#SW[@]}" ] && [ "${SWL[$k]}" = 1 ]; then
        case ${SW[$k]} in list | show) return 0 ;; esac
      fi
      deny_now 'this git stash form is denied to the tower under every policy value: the stash stack is shared by every worktree of the clone, so only git stash list and git stash show are the tower'"'"'s.'
      ;;
    branch)
      parse_git_opts "$k" 'set-upstream-to sort format points-at' 'u' '' \
        || {
          deny_now "this git branch carries an option the guard cannot read ($GP_ERR) - refusing (fail closed). Spell its options in full."
          return 0
        }
      # Deletion stays the tower's, and in delete mode a force only deletes an
      # unmerged branch, so a parsed delete flag settles the call: the parse
      # keeps an option's value from reading as one. An expansion could spell
      # --no-delete, which cancels delete mode, so the words must be literal
      # first, and a --no-delete sends the call on to the checks below.
      tower_opts_literal "$k" 'this git branch' || return 0
      if ! long_prefix_seen no-delete 4; then
        case $GP_SHORT in *[dD]*) return 0 ;; esac
        long_prefix_seen delete 1 && return 0
      fi
      # -M and -C are git's --move --force and --copy --force.
      if long_prefix_seen force 1 || [[ $GP_SHORT == *[fMC]* ]]; then
        deny_now 'a forced git branch (-f, --force, -M, -C) is denied to the tower under every policy value: it repoints an existing branch, and the tower never moves a branch.'
      elif long_prefix_seen move 1 || long_prefix_seen copy 1 || [[ $GP_SHORT == *[mc]* ]]; then
        deny_now 'a git branch rename or copy (-m, -c, --move, --copy) is denied to the tower under every policy value: it moves or repoints a branch, and the tower never moves a branch. Create a new branch instead.'
      fi
      ;;
    worktree) classify_tower_worktree "$k" "$dir" "$dir_ok" ;;
  esac
  return 0
}

# classify_tower_fetch <first-arg-index> — a fetch that writes a local branch:
# a refspec destination outside refs/ or under refs/heads/ (git reads a bare
# or heads/ destination as a local branch), a glob destination that can reach
# refs/heads/, or a refspec the guard cannot see:
# any expansion, since an unquoted one can split into a refspec. The first
# positional is the repository, which may be a URL holding a colon.
classify_tower_fetch() {
  local k=$1 j i r dst w
  j=$k
  while [ "$j" -lt "${#SW[@]}" ]; do
    [ "${SWL[$j]}" = 1 ] || {
      deny_now 'this git fetch carries an expansion the guard cannot read, which could spell a refspec writing a local branch - refusing (fail closed). Write the fetch literally.'
      return 0
    }
    j=$((j + 1))
  done
  for w in "${SW[@]:$k}"; do
    [ "$w" != -- ] || break
    case $w in
      --refmap= | --refma= | --refm=) ;;
      --refm*)
        deny_now 'a git fetch with --refmap is denied to the tower under every policy value: the map can write a local branch. Fetch into the remote-tracking refs instead.'
        return 0
        ;;
    esac
  done
  parse_git_opts "$k" 'depth deepen shallow-since shallow-exclude jobs upload-pack refmap server-option negotiation-tip filter' 'jo' '' \
    || {
      deny_now "this git fetch carries an option the guard cannot read ($GP_ERR) - refusing (fail closed). Spell its options in full."
      return 0
    }
  if long_prefix_seen stdin 2; then
    deny_now 'a git fetch reading refspecs from --stdin is denied to the tower under every policy value: the guard cannot see whether one writes a local branch.'
    return 0
  fi
  # --multiple reads every positional as a remote, but a later --no-multiple
  # turns refspecs back on, so the words holding a colon are read either way.
  i=1
  while [ "$i" -lt "${#GP_POS[@]}" ]; do
    r=${GP_POS[$i]}
    i=$((i + 1))
    case $r in *:*) ;; *) continue ;; esac
    # A case-insensitive filesystem stores refs/HEADS/x as refs/heads/x.
    lc "${r#*:}"
    dst=$LC
    # A glob destination writes wherever its pattern reaches: only one whose
    # literal part fixes a namespace other than heads stays clear of them.
    case $dst in
      *'*'*)
        case ${dst%%'*'*} in
          refs/heads/*) ;;
          refs/?*/*) continue ;;
        esac
        deny_now "a git fetch whose glob destination ($(sanitize_printable "$dst" 'its destination')) can reach the local branches is denied to the tower under every policy value, since the tower never moves a branch. Fetch into a namespace the glob fixes, such as refs/remotes/<remote>/*."
        return 0
        ;;
      '') continue ;;
      refs/heads/*) ;;
      refs/*) continue ;;
    esac
    deny_now "a git fetch into a local branch ($(sanitize_printable "$dst" 'its destination')) is denied to the tower under every policy value: it moves that branch, and the tower never moves a branch. Fetch into the remote-tracking refs (git fetch <remote>) instead."
    return 0
  done
}

# classify_tower_remote <first-arg-index> — a git remote add that fetches
# into a fetch mirror, whose refspec maps the remote's refs/ onto the local
# refs/, its branches included. A bare --mirror sets up both directions. The
# subcommand must be literal and follow only git remote's own verbosity
# options, so the add is never missed.
classify_tower_remote() {
  local k=$1 n=${#SW[@]} w name mirror=0 mirror_opt=--mirror v1=--verbose v0=--no-verbose
  while [ "$k" -lt "$n" ]; do
    w=${SW[$k]}
    case $w in
      -v | -vv*) [[ $w =~ ^-v+$ ]] || break ;;
      --*)
        { [ "${#w}" -ge 3 ] && [ "$w" = "${v1:0:${#w}}" ]; } \
          || { [ "${#w}" -ge 6 ] && [ "$w" = "${v0:0:${#w}}" ]; } || break
        ;;
      *) break ;;
    esac
    k=$((k + 1))
  done
  [ "$k" -lt "$n" ] || return 0
  case ${SW[$k]} in
    -*)
      deny_now "this git remote carries an option the guard does not read before its subcommand ($(sanitize_printable "${SW[$k]}" 'unprintable')) - refusing (fail closed). Put the subcommand first."
      return 0
      ;;
  esac
  [ "${SWL[$k]}" = 1 ] || {
    deny_now 'this git remote subcommand is an expansion the guard cannot read, and it could add a fetch mirror writing the local branches - refusing (fail closed). Write the subcommand literally.'
    return 0
  }
  [ "${SW[$k]}" = add ] || return 0
  k=$((k + 1))
  tower_opts_literal "$k" 'this git remote add' || return 0
  parse_git_opts "$k" 'track master' 'tm' '' \
    || {
      deny_now "this git remote add carries an option the guard cannot read ($GP_ERR) - refusing (fail closed). Spell its options in full."
      return 0
    }
  for w in "${SW[@]:$k}"; do
    [ "$w" != -- ] || break
    name=${w%%=*}
    # --m is ambiguous with --master, so --mi is the shortest --mirror.
    [ "${#name}" -ge 4 ] || continue
    [ "$name" = "${mirror_opt:0:${#name}}" ] || continue
    case $w in
      *=push) ;;
      *) mirror=1 ;;
    esac
  done
  if [ "$mirror" = 1 ] && { long_prefix_seen fetch 1 || [[ $GP_SHORT == *f* ]]; }; then
    deny_now 'a git remote add that fetches into a fetch mirror (-f with --mirror or --mirror=fetch) is denied to the tower under every policy value: the mirror writes the local branches, and the tower never moves a branch. Add the remote without --mirror.'
  fi
}

# classify_tower_worktree <verb-index> <dir> <dir_ok>
classify_tower_worktree() {
  local k=$1 dir=$2 dir_ok=$3 verb v x r
  local -a names=() cands=()
  [ "$k" -lt "${#SW[@]}" ] || return 0
  tower_opts_literal "$k" 'this git worktree command' || return 0
  lc "${SW[$k]}"
  verb=$LC
  case $verb in
    add | remove | move) ;;
    *) return 0 ;;
  esac
  parse_git_opts "$((k + 1))" 'reason' 'bB' '' \
    || {
      deny_now "this git worktree $verb carries an option the guard cannot read ($GP_ERR) - refusing (fail closed). Spell its options in full."
      return 0
    }
  if long_prefix_seen force 1 || [[ $GP_SHORT == *f* ]]; then
    deny_now "git worktree $verb --force is denied to the tower under every policy value: it overrides git's own checks on a worktree that may hold work or a checked-out branch."
    return 0
  fi
  [ "$verb" = add ] || return 0
  if long_prefix_seen detach 1 || [[ $GP_SHORT == *d* ]]; then
    deny_now 'a detached worktree add (--detach) is denied to the tower under every policy value: dispatch a worktree through the planwright dispatch script instead.'
    return 0
  fi
  for v in ${GP_VALS[@]+"${GP_VALS[@]}"}; do
    case $v in
      B=*)
        deny_now 'creating a worktree with -B is denied to the tower under every policy value: it force-resets the branch it names when that branch exists, and the tower never moves a branch. Create a new branch with -b instead.'
        return 0
        ;;
      b=*) names[${#names[@]}]=${v#?=} ;;
    esac
  done
  if [ "${#names[@]}" = 0 ]; then
    # A name taken from a positional after `--` may be an expansion.
    if [ -n "${GP_POS[1]:-}" ]; then
      [ "${GP_POSL[1]}" = 1 ] || {
        deny_now "this git worktree $verb names its branch through an expansion the guard cannot read, which could name a protected branch - refusing (fail closed). Name the branch literally."
        return 0
      }
      names[0]=${GP_POS[1]}
    elif [ -n "${GP_POS[0]:-}" ]; then
      [ "${GP_POSL[0]}" = 1 ] || {
        deny_now "this git worktree $verb takes its branch from a path the guard cannot read (an expansion), which could name a protected branch - refusing (fail closed). Name the path or the branch literally."
        return 0
      }
      # With no branch and no commit-ish, git checks out (or creates) the
      # branch named after the path's last component.
      x=${GP_POS[0]%/}
      names[0]=${x##*/}
    fi
  fi
  for x in ${names[@]+"${names[@]}"}; do
    case $x in
      refs/heads/*) x=${x#refs/heads/} ;;
      heads/*) x=${x#heads/} ;;
      refs/remotes/*/* | remotes/*/*)
        x=${x#refs/}
        x=${x#remotes/}
        x=${x#*/}
        ;;
      */*)
        r=${x%%/*}
        case $r in
          *[!A-Za-z0-9._-]* | -* | .*) ;;
          *)
            [ "$dir_ok" != 1 ] || [ -z "$(gitq "$dir" config --get "remote.$r.url")" ] \
              || ! valid_branch "${x#*/}" || cands[${#cands[@]}]=${x#*/}
            ;;
        esac
        ;;
    esac
    ! valid_branch "$x" || cands[${#cands[@]}]=$x
  done
  [ "${#cands[@]}" = 0 ] || queue_protected "$dir" "$dir_ok" "this git worktree $verb" "${cands[@]}"
}

# Appended to a fast-forward-only merge or pull's tier or branch refusal; the
# refusal itself stands.
FF_REMEDY=" To bring a clean primary checkout's default branch up to its origin, run planwright's scripts/main-currency.sh ff-primary --checkout <primary checkout> instead: it fast-forwards only, refuses a dirty tree or any other branch, and records the act."

# ff_only_seen — 0 when the parsed long options leave git in --ff-only mode:
# --ff, --no-ff and --ff-only override each other, the last one winning, and
# git takes any unique prefix (--ff- is --ff-only, --no-f is --no-ff).
ff_only_seen() {
  local t name only=0 ffo=ff-only nff=no-ff
  for t in $GP_LONG; do
    name=${t%%=*}
    if [ "$name" = ff ]; then
      only=0
    elif [ "${#name}" -ge 3 ] && [ "$name" = "${ffo:0:${#name}}" ]; then
      only=1
    elif [ "${#name}" -ge 4 ] && [ "$name" = "${nff:0:${#name}}" ]; then
      only=0
    fi
  done
  [ "$only" = 1 ]
}

MERGE_VLONG='message file strategy strategy-option into-name cleanup'
classify_git_merge() {
  local k=$1 dir=$2 dir_ok=$3 ff=0 remedy=''
  parse_git_opts "$k" "$MERGE_VLONG" 'mFsX' 'S' \
    || {
      tower_refuses 'git merge' || deny_now "this git merge carries an option the guard cannot read ($GP_ERR) - refusing (fail closed). Spell its options in full."
      return 0
    }
  if long_prefix_seen abort 2 || long_prefix_seen continue 3 || long_prefix_seen quit 2; then
    return 0
  fi
  if ff_only_seen; then
    ff=1
    remedy=$FF_REMEDY
  fi
  tower_refuses 'git merge' "$remedy" && return 0
  act_gate 'this git merge' merge || return 0
  need_dir "$dir_ok" 'this git merge' || return 0
  all_literal || {
    deny_now 'this git merge names its source through an expansion the guard cannot read - refusing (fail closed). Name the PR base literally (origin/main).'
    return 0
  }
  PENDING[${#PENDING[@]}]="merge$TAB$dir$TAB$ff$TAB${GP_POS[*]-}"
}

PULL_VLONG='strategy strategy-option depth deepen shallow-since shallow-exclude upload-pack server-option negotiation-tip jobs refmap cleanup'
classify_git_pull() {
  local k=$1 dir=$2 dir_ok=$3 mode='' ff=0 remedy=''
  parse_git_opts "$k" "$PULL_VLONG" 'sXoj' 'S' \
    || {
      tower_refuses 'git pull' || deny_now "this git pull carries an option the guard cannot read ($GP_ERR) - refusing (fail closed). Spell its options in full."
      return 0
    }
  if ff_only_seen; then
    ff=1
    remedy=$FF_REMEDY
  fi
  tower_refuses 'git pull' "$remedy" && return 0
  act_gate 'this git pull' merge || return 0
  need_dir "$dir_ok" 'this git pull' || return 0
  all_literal || {
    deny_now 'this git pull names its source through an expansion the guard cannot read - refusing (fail closed). Name the PR base literally (git pull origin main).'
    return 0
  }
  # The rebase mode, in argument order with the last flag winning, as git
  # reads it; a prefix git would expand counts (--reb is --rebase).
  local w name rb=rebase nrb=no-rebase b c
  while [ "$k" -lt "${#SW[@]}" ]; do
    w=${SW[$k]}
    case $w in
      --) break ;;
      --*)
        name=${w#--}
        name=${name%%=*}
        if [ "${#name}" -ge 3 ] && [ "$name" = "${rb:0:${#name}}" ]; then
          case $w in
            *=*)
              case $(lower "${w#*=}") in
                false | no | off | 0) mode=merge ;;
                *) mode=rebase ;;
              esac
              ;;
            *) mode=rebase ;;
          esac
        elif [ "${#name}" -ge 5 ] && [ "$name" = "${nrb:0:${#name}}" ]; then
          mode=merge
        fi
        ;;
      -?*)
        b=${w#-}
        while [ -n "$b" ]; do
          c=${b:0:1}
          b=${b:1}
          case $c in
            r) mode=rebase ;;
            s | X | o | j | S) b='' ;;
          esac
        done
        ;;
    esac
    k=$((k + 1))
  done
  PENDING[${#PENDING[@]}]="pull$TAB$dir$TAB$mode$TAB$ff$TAB${GP_POS[*]-}"
}

REBASE_VLONG='onto strategy strategy-option exec whitespace empty'
classify_git_rebase() {
  local k=$1 dir=$2 dir_ok=$3
  parse_git_opts "$k" "$REBASE_VLONG" 'sXxC' 'S' \
    || {
      tower_refuses 'git rebase' || deny_now "this git rebase carries an option the guard cannot read ($GP_ERR) - refusing (fail closed). Spell its options in full."
      return 0
    }
  if long_prefix_seen continue 3 || long_prefix_seen abort 2 || long_prefix_seen skip 2 \
    || long_prefix_seen quit 2 || long_prefix_seen edit-todo 2 || long_prefix_seen show-current-patch 2; then
    return 0
  fi
  tower_refuses 'git rebase' && return 0
  # An exec line runs a shell command below this hook, unclassified.
  case $GP_SHORT in
    *x*)
      deny_now 'this git rebase runs a command through -x/--exec, which the guard cannot classify - refusing. Run the rebase without exec and the command on its own.'
      return 0
      ;;
  esac
  if long_prefix_seen exec 2; then
    deny_now 'this git rebase runs a command through -x/--exec, which the guard cannot classify - refusing. Run the rebase without exec and the command on its own.'
    return 0
  fi
  act_gate 'this git rebase' rewrite || return 0
  need_dir "$dir_ok" 'this git rebase' || return 0
  all_literal || {
    deny_now 'this git rebase names a revision through an expansion the guard cannot read - refusing (fail closed). Write it literally.'
    return 0
  }
  local root=0 ur=0 t uref=update-refs nuref=no-update-refs
  long_prefix_seen root 2 && root=1
  # git takes the last of --update-refs and --no-update-refs.
  for t in $GP_LONG; do
    if [ "${#t}" -ge 2 ] && [ "$t" = "${uref:0:${#t}}" ]; then
      ur=1
    elif [ "${#t}" -ge 5 ] && [ "$t" = "${nuref:0:${#t}}" ]; then
      ur=-1
    fi
  done
  PENDING[${#PENDING[@]}]="rebase$TAB$dir$TAB$root$TAB$ur$TAB${GP_POS[*]-}"
}

COMMIT_VLONG=' message file reuse-message reedit-message author date template cleanup trailer pathspec-from-file '
classify_git_commit() {
  local k=$1 dir=$2 dir_ok=$3 n=${#SW[@]} w name v amend=0 targets='' endopts=0 bad='' unread=0
  while [ "$k" -lt "$n" ]; do
    w=${SW[$k]}
    if [ "$endopts" = 1 ]; then
      k=$((k + 1))
      continue
    fi
    case $w in
      --) endopts=1 ;;
      --*)
        name=${w#--}
        v=''
        local hv=0
        case $name in
          *=*)
            v=${name#*=}
            name=${name%%=*}
            hv=1
            ;;
        esac
        # An expansion in the option name could spell --amend, --squash, or --fixup.
        case $name in *[!a-z0-9-]*) [ "${SWL[$k]}" = 1 ] || unread=1 ;; esac
        # git reads any unique prefix of a long option: --am is --amend.
        local am=amend sq=squash fx=fixup
        if [ "${#name}" -ge 2 ] && [ "$name" = "${am:0:${#name}}" ]; then
          amend=1
        elif { [ "${#name}" -ge 2 ] && [ "$name" = "${sq:0:${#name}}" ]; } \
          || { [ "${#name}" -ge 3 ] && [ "$name" = "${fx:0:${#name}}" ]; }; then
          if [ "$hv" = 0 ]; then
            k=$((k + 1))
            [ "$k" -lt "$n" ] || {
              bad="--$name has no value"
              break
            }
            v=${SW[$k]}
            [ "${SWL[$k]}" = 1 ] || bad='its target is not literal'
          else
            [ "${SWL[$k]}" = 1 ] || bad='its target is not literal'
          fi
          case $v in amend:* | reword:*) v=${v#*:} ;; esac
          targets="$targets $v"
        else
          case $COMMIT_VLONG in
            *" $name "*)
              [ "$hv" = 1 ] || k=$((k + 1))
              ;;
            *" $name"*)
              [ "$hv" = 1 ] || bad="--$name abbreviates an option that takes a value"
              ;;
          esac
        fi
        ;;
      -?*)
        local b=${w#-} c
        while [ -n "$b" ]; do
          c=${b:0:1}
          b=${b:1}
          case $c in
            m | F | C | c | t)
              [ -n "$b" ] || k=$((k + 1))
              b=''
              ;;
            S | u) b='' ;;
            [!a-zA-Z0-9]) [ "${SWL[$k]}" = 1 ] || unread=1 ;;
          esac
        done
        ;;
      *) [ "${SWL[$k]}" = 1 ] || unread=1 ;;
    esac
    k=$((k + 1))
  done
  if [ "$unread" = 1 ]; then
    deny_now 'this git commit carries an expansion before -- that could spell --amend, --squash, or --fixup - refusing (fail closed). Write its options literally and put expanded paths after --.'
    return 0
  fi
  [ "$amend" = 1 ] || [ -n "$targets" ] || return 0
  tower_refuses 'amending, squashing, or fixing up a commit' && return 0
  if [ -n "$bad" ]; then
    deny_now "this git commit rewrites history and $bad - refusing (fail closed). Spell its options in full with literal values."
    return 0
  fi
  act_gate 'this history rewrite' rewrite || return 0
  need_dir "$dir_ok" 'this history rewrite' || return 0
  local t
  case "$amend:$targets" in
    0:*[![:space:]]*) ;;
    0:*)
      deny_now 'this git commit names an empty squash or fixup target - refusing (fail closed). Name the commit.'
      return 0
      ;;
  esac
  for t in $targets; do
    valid_rev "$t" \
      || {
        deny_now "this git commit names a target the guard will not read ($(sanitize_printable "$t" 'unprintable')) - refusing (fail closed)."
        return 0
      }
  done
  [ "$amend" = 0 ] || targets="HEAD $targets"
  PENDING[${#PENDING[@]}]="commit$TAB$dir$TAB$targets"
}

classify_git_push() {
  local k=$1 dir=$2 dir_ok=$3 n=${#SW[@]} w name endopts=0 b c force=0 bulk=0 del=0 repo_opt=0
  local -a pos=() posl=()
  while [ "$k" -lt "$n" ]; do
    w=${SW[$k]}
    if [ "$endopts" = 1 ]; then
      pos[${#pos[@]}]=$w
      posl[${#posl[@]}]=${SWL[$k]}
      k=$((k + 1))
      continue
    fi
    case $w in
      --) endopts=1 ;;
      --no-*) ;;
      --*)
        name=${w#--}
        name=${name%%=*}
        local x
        for x in force force-with-lease force-if-includes; do
          case $x in "$name"*) force=1 ;; esac
        done
        for x in mirror all branches prune; do
          case $x in "$name"*) bulk=1 ;; esac
        done
        x=delete
        case $x in "$name"*) del=1 ;; esac
        case $w in
          *=*) [ "$name" != repo ] || repo_opt=1 ;;
          *)
            case $name in
              repo | push-option | receive-pack | exec | recurse-submodules)
                [ "$name" != repo ] || repo_opt=1
                k=$((k + 1))
                ;;
            esac
            ;;
        esac
        ;;
      -)
        pos[${#pos[@]}]=$w
        posl[${#posl[@]}]=${SWL[$k]}
        ;;
      -*)
        b=${w#-}
        while [ -n "$b" ]; do
          c=${b:0:1}
          b=${b:1}
          case $c in
            f) force=1 ;;
            d) del=1 ;;
            o)
              [ -n "$b" ] || k=$((k + 1))
              b=''
              ;;
          esac
        done
        ;;
      *)
        pos[${#pos[@]}]=$w
        posl[${#posl[@]}]=${SWL[$k]}
        ;;
    esac
    k=$((k + 1))
  done
  if [ "$force" = 1 ]; then
    deny_now 'this git push forces; a force-push is never performed by a worker, and by the tower only on an explicit operator request through its own path. Push new commits instead.'
    return 0
  fi
  if [ "$bulk" = 1 ]; then
    deny_now 'this git push sends every branch (--all, --branches, --mirror) or prunes remote branches, which reaches main - refusing. Push your own branch by name.'
    return 0
  fi
  local l
  for l in ${posl[@]+"${posl[@]}"}; do
    [ "$l" = 1 ] \
      || {
        deny_now 'this git push names its remote or refspec through an expansion the guard cannot read, so it cannot check the target against the protected set - refusing (fail closed). Name the branch literally (git push origin <branch>), or push HEAD.'
        return 0
      }
  done
  if [ "$repo_opt" = 1 ] && [ "${#pos[@]}" -gt 0 ]; then
    deny_now 'this git push combines --repo with positional arguments, which the guard does not read - refusing (fail closed). Name the remote as the first argument.'
    return 0
  fi
  local refs=() r i=1
  while [ "$i" -lt "${#pos[@]}" ]; do
    r=${pos[$i]}
    case $r in
      +*)
        deny_now 'this git push carries a +refspec, which forces - refusing. Push new commits instead.'
        return 0
        ;;
      *'*'*)
        deny_now 'this git push carries a wildcard refspec, which can reach main - refusing. Push your own branch by name.'
        return 0
        ;;
      :)
        deny_now 'this git push carries the matching refspec (:), which pushes every branch the remote shares, main included - refusing. Push your own branch by name.'
        return 0
        ;;
    esac
    refs[${#refs[@]}]=$r
    i=$((i + 1))
  done
  act_gate 'this git push' push || return 0
  need_dir "$dir_ok" 'this git push' || return 0
  PENDING[${#PENDING[@]}]="push$TAB$dir$TAB$del$TAB${pos[0]:-}$TAB${refs[*]-}"
}

# --------------------------------------------------------------------------
# Evaluation of the queued acts (phase B: the reads).

eval_pending() {
  local p kind rest dir
  for p in ${PENDING[@]+"${PENDING[@]}"}; do
    kind=${p%%"$TAB"*}
    rest=${p#*"$TAB"}
    case $kind in
      flip) eval_flip "$rest" ;;
      protected)
        dir=${rest%%"$TAB"*}
        rest=${rest#*"$TAB"}
        local what=${rest%%"$TAB"*}
        # shellcheck disable=SC2086 # the branch list, split on purpose
        check_unprotected "$dir" "$what" ${rest#*"$TAB"}
        ;;
      merge) eval_merge "$rest" ;;
      merge-helper) eval_merge_helper "$rest" ;;
      pull) eval_pull "$rest" ;;
      rebase) eval_rebase "$rest" ;;
      commit) eval_commit "$rest" ;;
      push) eval_push "$rest" ;;
    esac
  done
  # Asked only once nothing else in the command was refused.
  [ "$MC_FLIP_ASK" = 0 ] || emit_ask "$MC_FLIP_ASK_REASON"
}

MC_FLIP_ASK=0
MC_FLIP_ASK_REASON='ready_flip_policy is human in this repository, so mission control flips this pull request only on your request: a yes to this prompt is your request to mark it ready. To settle it for good, set ready_flip_policy in the repository'"'"'s planwright config (planwright.yml in its project settings directory): unit-owner lets mission control flip its pull requests, and human with a Bash(gh pr ready:*) deny rule in the repository'"'"'s project settings file (settings.json in that directory) keeps mission control hands-off.'

eval_flip() {
  local dir=$1
  [ "$dir" != "$MCP_DIR_SENTINEL" ] || dir=$PAYLOAD_CWD
  read_knob ready_flip_policy "$dir" human unit-owner
  case $KNOB_VAL in
    unit-owner) return 0 ;;
    *)
      # Mission control acts for the operator, who answers the prompt.
      if [ "$TIER" = mission-control ]; then
        MC_FLIP_ASK=1
        return 0
      fi
      emit_deny 'ready_flip_policy is human, so only a person marks a task pull request ready; leave it a draft and name it in your handoff.'
      ;;
  esac
}

eval_merge_helper() {
  read_knob merge_policy "$1" human on-approval policy-class
  [ "$KNOB_VAL" = policy-class ] \
    || emit_deny "merge_policy is $KNOB_VAL, so no agent session runs the merge helper: the operator's approval act merges this PR. Leave it for the operator and name it in your handoff."
}

base_merge_allowed() { # <dir> <what> [<remedy for a branch refusal>]
  read_knob worker_base_merge "$1" allow deny
  [ "$KNOB_VAL" = allow ] \
    || emit_deny "worker_base_merge is deny, so $2 is refused; the operator syncs this branch with its base."
  need_timeout
  on_unit_branch "$1" "$2" base-sync "${3:-}"
  base_of "$1"
}

eval_merge() {
  local dir=${1%%"$TAB"*} rest=${1#*"$TAB"} remedy='' srcs s
  [ "${rest%%"$TAB"*}" != 1 ] || remedy=$FF_REMEDY
  srcs=${rest#*"$TAB"}
  base_merge_allowed "$dir" 'this git merge' "$remedy"
  if [ -z "$srcs" ]; then
    upstream_of "$dir" "$CUR_BRANCH"
    is_base_or_own_branch "$UP_REMOTE" "$UP_BRANCH" \
      || emit_deny "this git merge names no source, so git merges the branch's upstream, which is neither the PR base ($(sanitize_printable "$BASE_REMOTE/$BASE_BRANCH" 'the base')) nor the branch's own remote branch - refusing. Name the base: git merge $(sanitize_printable "$BASE_REMOTE/$BASE_BRANCH" 'origin/main')."
    return 0
  fi
  local rc
  for s in $srcs; do
    is_base_ref "$dir" "$s" && continue
    rc=0
    is_own_remote_ref "$dir" "$s" || rc=$?
    [ "$rc" != 0 ] || continue
    [ "$rc" != 2 ] \
      || emit_deny "this git merge names the branch's own remote branch, but $(sanitize_printable "refs/remotes/$BASE_REMOTE/$CUR_BRANCH" 'its remote-tracking ref') is missing or a local branch or tag of that name points at another commit - refusing (fail closed). Push or fetch the branch first, and remove any local branch or tag of that name."
    emit_deny "a worker merges only the PR base ($(sanitize_printable "$BASE_REMOTE/$BASE_BRANCH" 'the base')) or its own remote branch into its own branch, and this merge names $(sanitize_printable "$s" 'another source') - refusing. Use git merge $(sanitize_printable "$BASE_REMOTE/$BASE_BRANCH" 'origin/main'), or scripts/converge-sync-main.sh (on a task branch or a flight branch carrying its id)."
  done
}

eval_pull() {
  local dir=${1%%"$TAB"*} rest=${1#*"$TAB"} mode ff remote='' ref='' a i=0 rwhat='this rebasing git pull' rhint=' git pull --no-rebase,'
  mode=${rest%%"$TAB"*}
  rest=${rest#*"$TAB"}
  ff=${rest%%"$TAB"*}
  rest=${rest#*"$TAB"}
  # shellcheck disable=SC2086 # the positionals, split on purpose
  set -- $rest
  remote=${1:-}
  [ "$#" -le 2 ] \
    || emit_deny 'this git pull names more than one refspec - refusing. Pull the PR base alone: git pull origin main.'
  ref=${2:-}
  need_timeout
  if [ -z "$mode" ]; then
    # The branch key wins over pull.rebase when present, as in git (a
    # detached HEAD has none), read by git's own bool parser: a key with no
    # value is true, an empty one false (exit 1 means absent). A value it
    # rejects counts as a rebase: merges and interactive rebase, and any
    # other value (alone or among a multi-valued key's) makes git pull fail
    # or is refused here, never a merge the guard did not see.
    local cb rv rc=1
    cb=$(current_branch "$dir")
    if [ -n "$cb" ]; then
      rc=0
      rv=$(gitq "$dir" config --type=bool --get "branch.$cb.rebase") || rc=$?
    fi
    if [ "$rc" = 1 ]; then
      rc=0
      rv=$(gitq "$dir" config --type=bool --get pull.rebase) || rc=$?
    fi
    case $rc:$rv in
      0:false | 1:*) mode=merge ;;
      *)
        mode=rebase rhint=''
        rwhat='this git pull (rebasing under the pull.rebase or branch rebase configuration; git pull --no-rebase merges instead)'
        ;;
    esac
  fi
  if [ "$mode" = rebase ]; then
    read_knob unpushed_rewrite "$dir" allow deny
    [ "$KNOB_VAL" = allow ] \
      || emit_deny "unpushed_rewrite is deny, so $rwhat is refused. Merge the PR base instead:$rhint git merge origin/main, or scripts/converge-sync-main.sh (on a task branch or a flight branch carrying its id)."
    on_unit_branch "$dir" "$rwhat"
    local upref
    if [ -z "$remote" ]; then
      upstream_of "$dir" "$CUR_BRANCH"
      upref="refs/remotes/$UP_REMOTE/$UP_BRANCH"
      [ -n "$UP_BRANCH" ] || emit_deny "$rwhat has no upstream to rebase onto - refusing (fail closed). Name the remote and branch, or push the branch with -u first."
    else
      [ -n "$ref" ] || emit_deny "$rwhat names a remote and no branch, which the guard does not resolve - refusing. Name the branch."
      upref="refs/remotes/$remote/${ref#refs/heads/}"
    fi
    valid_rev "${upref#refs/}" || emit_deny "$rwhat names a source the guard will not read - refusing (fail closed)."
    refresh_and_check_unpushed "$dir" "$rwhat" "$upref..HEAD"
    return 0
  fi
  local remedy=''
  [ "$ff" != 1 ] || remedy=$FF_REMEDY
  base_merge_allowed "$dir" 'this git pull' "$remedy"
  if [ -z "$remote" ]; then
    upstream_of "$dir" "$CUR_BRANCH"
    remote=$UP_REMOTE
    ref=$UP_BRANCH
  elif [ -z "$ref" ]; then
    upstream_of "$dir" "$CUR_BRANCH"
    [ "$remote" = "$UP_REMOTE" ] \
      || emit_deny 'this git pull names a remote and no branch, so git pulls whatever that remote is configured to fetch - refusing. Name the PR base: git pull origin main.'
    ref=$UP_BRANCH
  fi
  case $ref in *:*) emit_deny 'this git pull carries a src:dst refspec, which also writes a local ref - refusing. Pull the PR base alone.' ;; esac
  ref=${ref#refs/heads/}
  is_base_or_own_branch "$remote" "$ref" \
    || emit_deny "a worker pulls only the PR base ($(sanitize_printable "$BASE_REMOTE $BASE_BRANCH" 'the base')) or its own remote branch into its own branch, and this pull takes $(sanitize_printable "${remote:-no remote} ${ref:-no branch}" 'another source') - refusing. Use git pull $(sanitize_printable "$BASE_REMOTE $BASE_BRANCH" 'origin main'), or scripts/converge-sync-main.sh (on a task branch or a flight branch carrying its id)."
}

rewrite_allowed() { # <dir> <what>
  read_knob unpushed_rewrite "$1" allow deny
  [ "$KNOB_VAL" = allow ] \
    || emit_deny "unpushed_rewrite is deny, so $2 is refused; history stays append-only. Add a new commit instead."
  need_timeout
  on_unit_branch "$1" "$2"
}

resolve_commit() { # <dir> <rev> — the full object id, or empty
  gitq "$1" rev-parse --verify --quiet --end-of-options "$2^{commit}" || printf ''
}

eval_rebase() {
  local dir=${1%%"$TAB"*} rest=${1#*"$TAB"} root ur up br
  root=${rest%%"$TAB"*}
  rest=${rest#*"$TAB"}
  ur=${rest%%"$TAB"*}
  rest=${rest#*"$TAB"}
  rewrite_allowed "$dir" 'this git rebase'
  # shellcheck disable=SC2086 # the positionals, split on purpose
  set -- $rest
  up=${1:-}
  br=${2:-}
  [ "$#" -le 2 ] || emit_deny 'this git rebase names more arguments than the guard reads - refusing (fail closed).'
  if [ -n "$br" ] && [ "$br" != "$CUR_BRANCH" ]; then
    emit_deny "this git rebase would rewrite $(sanitize_printable "$br" 'another branch'), not this session's unit branch - refusing."
  fi
  if [ "$ur" = 0 ]; then
    case $(lower "$(gitq "$dir" config --get rebase.updateRefs || printf '')") in
      true | yes | on | 1) ur=1 ;;
    esac
  fi
  [ "$ur" != 1 ] \
    || emit_deny 'this git rebase updates other branches too (--update-refs or rebase.updateRefs) - refusing. Rebase with --no-update-refs.'
  if [ "$root" = 1 ]; then
    refresh_and_check_unpushed "$dir" 'this git rebase --root' HEAD
    return 0
  fi
  # Refresh first, so the upstream resolves to what the rebase will use.
  refresh_upstream "$dir" 'this git rebase'
  if [ -z "$up" ]; then
    up="refs/remotes/$UP_REMOTE/$UP_BRANCH"
  fi
  valid_rev "$up" || emit_deny "this git rebase names an upstream the guard will not read ($(sanitize_printable "$up" 'unprintable')) - refusing (fail closed). Name it as a plain revision."
  local oid
  oid=$(resolve_commit "$dir" "$up")
  [ -n "$oid" ] || emit_deny "this git rebase names an upstream that does not resolve to a commit ($(sanitize_printable "$up" 'unprintable')) - refusing (fail closed). Name an existing commit."
  check_unpushed "$dir" 'this git rebase' "$oid..HEAD"
}

eval_commit() {
  local dir=${1%%"$TAB"*} targets=${1#*"$TAB"} t oid head
  rewrite_allowed "$dir" 'this history rewrite'
  head=$(resolve_commit "$dir" HEAD)
  [ -n "$head" ] || emit_deny 'this history rewrite runs where HEAD does not resolve - refusing (fail closed). Make a first commit instead.'
  local ranges=()
  for t in $targets; do
    oid=$(resolve_commit "$dir" "$t")
    [ -n "$oid" ] || emit_deny "this history rewrite names a commit that does not resolve ($(sanitize_printable "$t" 'unprintable')) - refusing (fail closed)."
    gitq "$dir" merge-base --is-ancestor "$oid" "$head" \
      || emit_deny "this history rewrite names a commit that is not on this branch ($(sanitize_printable "$t" 'unprintable')) - refusing. Name a commit of your own branch."
    # One commit alone: <oid>^! (a root commit has no parent to exclude, so
    # its range is the bare id with a count of one).
    if gitq "$dir" rev-parse --verify --quiet "$oid^" >/dev/null; then
      ranges[${#ranges[@]}]="$oid^!"
    else
      ranges[${#ranges[@]}]="-1 $oid"
    fi
  done
  refresh_upstream "$dir" 'this history rewrite'
  local r
  for r in "${ranges[@]}"; do
    case $r in
      '-1 '*) check_root_unpushed "$dir" "${r#-1 }" ;;
      *) check_unpushed "$dir" 'this history rewrite' "$r" ;;
    esac
  done
}

check_root_unpushed() {
  local hit
  hit=$(gitq "$1" for-each-ref --count=1 --format='%(refname)' --contains "$2" refs/remotes/) || hit='?'
  [ -z "$hit" ] \
    || emit_deny 'this history rewrite names a commit a remote-tracking ref already contains; pushed history stays append-only - refusing. Add a new commit instead.'
}

eval_push() {
  local dir=${1%%"$TAB"*} rest=${1#*"$TAB"} del remote refs r dst targets=() cb
  del=${rest%%"$TAB"*}
  rest=${rest#*"$TAB"}
  remote=${rest%%"$TAB"*}
  refs=${rest#*"$TAB"}
  need_timeout
  cb=$(current_branch "$dir")
  if [ -z "$refs" ]; then
    [ "$del" = 0 ] || emit_deny 'this git push deletes without naming a ref - refusing (fail closed).'
    [ -n "$cb" ] || emit_deny 'this git push names no branch and HEAD is detached, so the guard cannot tell what it pushes - refusing (fail closed). Name the branch.'
    local pd rp
    pd=$(gitq "$dir" config --get push.default) || pd=''
    [ "$(lower "$pd")" != matching ] \
      || emit_deny 'this git push names no branch and push.default is matching, which pushes every branch the remote shares, main included - refusing. Name the branch.'
    [ -n "$remote" ] || remote=$(gitq "$dir" config --get "branch.$cb.pushRemote" || gitq "$dir" config --get remote.pushDefault || gitq "$dir" config --get "branch.$cb.remote" || printf 'origin')
    case $remote in
      *[!A-Za-z0-9._-]*)
        emit_deny 'this git push names no branch and its remote is not a plain remote name the guard can read - refusing (fail closed). Name the remote and the branch.'
        ;;
      *)
        rp=$(gitq "$dir" config --get-all "remote.$remote.push") || rp=''
        [ -z "$rp" ] \
          || emit_deny 'this git push names no branch and the remote carries a configured push refspec, which the guard does not read - refusing (fail closed). Name the branch.'
        case $(lower "$(gitq "$dir" config --get "remote.$remote.mirror" || printf '')") in
          true | yes | on | 1)
            emit_deny 'this git push names no branch and the remote is configured as a mirror, so it pushes every ref, main included - refusing. Name the branch.'
            ;;
        esac
        ;;
    esac
    targets[${#targets[@]}]=$cb
    upstream_of "$dir" "$cb"
    [ -z "$UP_BRANCH" ] || targets[${#targets[@]}]=$UP_BRANCH
  else
    for r in $refs; do
      case $r in
        *:*) dst=${r#*:} ;;
        *) dst=$r ;;
      esac
      [ -n "$dst" ] || emit_deny 'this git push carries a refspec with an empty destination, which the guard does not read - refusing (fail closed).'
      case $dst in
        HEAD | @)
          [ -n "$cb" ] || emit_deny 'this git push pushes HEAD while it is detached - refusing (fail closed). Name the branch.'
          dst=$cb
          ;;
        refs/heads/*) dst=${dst#refs/heads/} ;;
        refs/*) continue ;;
        heads/*) dst=${dst#heads/} ;;
      esac
      valid_branch "$dst" \
        || emit_deny "this git push names a destination the guard will not check ($(sanitize_printable "$dst" 'unprintable')) - refusing (fail closed)."
      targets[${#targets[@]}]=$dst
    done
  fi
  [ "${#targets[@]}" = 0 ] || check_unprotected "$dir" 'this git push' "${targets[@]}"
}

# --------------------------------------------------------------------------
# main

MCP_DIR_SENTINEL='<mcp>'

main() {
  TIER=${1:-}
  # The deadline counts from here, whatever SECONDS the environment carried.
  SECONDS=0
  local surface=${2:-infer} input read_ok=1 tool
  case $TIER in
    worker | tower | mission-control) ;;
    *)
      # A session with no tier profile: outside jurisdiction, no read at all.
      return 0
      ;;
  esac
  case $surface in
    bash | mcp) ;;
    file) [ "$TIER" = mission-control ] || return 0 ;;
    *) surface=infer ;;
  esac
  KNOB_T=$(bound_secs "${PLANWRIGHT_POLICY_GUARD_TIMEOUT:-}" 10)
  FETCH_T=$(bound_secs "${PLANWRIGHT_POLICY_GUARD_FETCH_TIMEOUT:-}" 20)

  input=$(head -c "$((MAX_PAYLOAD_BYTES + 1))" 2>/dev/null) || read_ok=0
  [ "$read_ok" = 1 ] \
    || emit_deny 'the PreToolUse payload could not be read - refusing (fail closed). This is a hook-contract violation; report it.'
  if [ "${#input}" -gt "$MAX_PAYLOAD_BYTES" ]; then
    emit_deny 'the PreToolUse payload is larger than this guard reads - refusing (fail closed). Issue the command on its own.'
  fi
  if ! command -v jq >/dev/null 2>&1; then
    { [ "$surface" = mcp ] || [ "$surface" = file ] || raw_evidence "$input" || mc_settings_named "$input"; } \
      && emit_deny_constant
    return 0
  fi
  if [ -z "$input" ]; then
    emit_deny 'the PreToolUse payload was empty - refusing (fail closed). This is a hook-contract violation; report it.'
  fi
  # The short fields in one jq call, NUL-separated; the command, which can be
  # long, through a command substitution (a NUL-delimited read takes it one
  # byte at a time). A NUL inside a value is dropped: no shell argument can
  # carry one.
  tool='' P_CMD_OK=0 P_CMD='' P_CWD_TYPE=absent P_CWD=''
  {
    IFS= read -r -d '' tool
    IFS= read -r -d '' P_CMD_OK
    IFS= read -r -d '' P_CWD_TYPE
    IFS= read -r -d '' P_CWD
  } < <(printf '%s' "$input" | jq -j '
    def clean: if type == "string" then gsub("\u0000"; "") else "" end;
    [ (.tool_name | clean),
      (if (.tool_input.command | type) == "string" then "1" else "0" end),
      (if has("cwd") and .cwd != null then (.cwd | type) else "absent" end),
      (.cwd | clean)
    ] | map(. + "\u0000") | add' 2>/dev/null)
  if [ "$tool" = Bash ] && [ "$P_CMD_OK" = 1 ]; then
    P_CMD=$(printf '%s' "$input" | jq -j '.tool_input.command | gsub("\u0000"; "")' 2>/dev/null) || P_CMD=''
  fi
  if [ "$surface" = file ]; then
    handle_file "$input"
    return 0
  fi
  if [ -z "$tool" ]; then
    [ "$surface" != mcp ] \
      || emit_deny 'this update_pull_request payload could not be parsed, so the guard cannot tell whether it flips or re-drafts a PR - refusing (fail closed). Use gh pr ready <number> for a flip.'
    raw_evidence "$input" \
      && emit_deny 'the PreToolUse payload could not be parsed and its raw content names a reserved act - refusing (fail closed).'
    mc_settings_named "$input" \
      && emit_deny 'the PreToolUse payload could not be parsed and its raw content names a settings file - refusing (fail closed).'
    return 0
  fi
  if tower_floor; then
    case $tool in
      mcp__github__merge_pull_request | "$MCP_TOOL" | mcp__github__update_pull_request_branch | \
        mcp__github__create_pull_request | mcp__github__push_files | mcp__github__create_or_update_file | \
        mcp__github__delete_file)
        [ "$TIER" = tower ] \
          || emit_deny "$tool is denied to mission control whatever its arguments: it never merges, edits or opens a pull request, updates its branch, or writes a branch through the GitHub MCP server. A flip inside ready_flip_policy is gh pr ready <number>."
        emit_deny "$tool is denied to the tower whatever its arguments: the tower never merges, edits or opens a pull request, updates its branch, or writes a branch through the GitHub MCP server. Read PR state with gh, and leave writes to a flight."
        ;;
    esac
  fi
  [ "$surface" != mcp ] || [ "$tool" = "$MCP_TOOL" ] \
    || emit_deny "the MCP-surface payload names $(sanitize_printable "$tool" 'an unprintable tool'), not $MCP_TOOL, so the guard cannot tell whether it flips or re-drafts a PR - refusing (fail closed). This is a hook-contract violation; report it."
  case $tool in
    Bash) handle_bash "$input" ;;
    "$MCP_TOOL") handle_mcp "$input" ;;
  esac
  return 0
}

handle_mcp() {
  local shape
  shape=$(printf '%s' "$1" | jq -r '
    if (.tool_input | type) != "object" then "malformed"
    elif (.tool_input | has("draft") | not) then "no-draft"
    elif (.tool_input.draft | type) != "boolean" then "malformed"
    elif .tool_input.draft then "to-draft"
    else "to-ready" end' 2>/dev/null) || shape=malformed
  PAYLOAD_CWD=$P_CWD
  [ -n "$PAYLOAD_CWD" ] || PAYLOAD_CWD=$PWD
  case $shape in
    no-draft) return 0 ;;
    to-draft) emit_deny 'this update_pull_request call re-drafts a pull request; re-drafting is reserved to the corrective helper (scripts/request-reviewer.sh). Ask the operator.' ;;
    to-ready)
      queue_flip "$MCP_DIR_SENTINEL" 1
      [ -z "$DENY_NOW" ] || emit_deny "$DENY_NOW"
      eval_pending
      ;;
    *) emit_deny 'this update_pull_request payload is malformed, so the guard cannot tell whether it flips or re-drafts a PR - refusing (fail closed). Use gh pr ready <number> for a flip.' ;;
  esac
}

# --------------------------------------------------------------------------
# The mission-control tier's settings and repository writes.

# A file that sets a session's posture, by name: a settings file
# (settings.json, settings.local.json, managed-settings.json, a shipped
# <kind>-settings.json profile, the user-level .claude.json), an MCP server
# list (.mcp.json), or a planwright configuration layer (planwright.yml,
# planwright.local.yml, where ready_flip_policy lives). The bracketed letter
# keeps the static no-model-client check from reading the name as a client.
RE_MC_POSTURE_NAME='(^|[^[:alnum:]_.])(((managed-)?settings(\.local)?|\.c[l]aude|\.mcp)\.json|planwright(\.local)?\.yml)([^[:alnum:]_-]|$)'
# Directories whose files load as posture, the planwright fleet home among
# them (a recorded launch profile lives there). The file surface alone checks
# them: an installed planwright script runs from under .claude/plugins.
RE_MC_POSTURE_DIR='/\.c[l]aude/(hooks|plugins|agents|skills|commands|planwright)/'
# Posture directories as a relative or absolute path, and the data places an
# expanding write target may still sit in: the harness scratch and task
# directories, and the session's project memory folder.
RE_MC_POSTURE_REL_DIR='(^|/)\.c[l]aude/(hooks|plugins|agents|skills|commands|planwright)(/|$)'
# shellcheck disable=SC2016 # regexes; `$` is literal
RE_MC_DATA_SCRATCH='^(/tmp/claude-[^/]+/|/tmp/planwright-[^/]+/|\$TMPDIR/|\$\{TMPDIR\}/)'
# A variable followed by a plain literal file name; mc_scratch_var vets the variable.
# shellcheck disable=SC2016 # a regex
RE_MC_DATA_SCRATCHVAR='^\$(\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))/[^$`*?[{/][^$`*?[{]*$'
# shellcheck disable=SC2016 # a regex
RE_MC_DATA_MEMORY='^(~|\$HOME|\$\{HOME\}|/[^$`*?[{]*)/\.c[l]aude/(projects/[^/$`*?[{]+/memory|tasks)/'
# A word that runs the text it is handed, so quoted text stays in view.
RE_MC_INTERPRETER='(^|[^[:alnum:]_.-])(sh|bash|zsh|dash|ksh|fish|eval|source|python3?|perl|ruby|node|xargs|ssh)([^[:alnum:]_-]|$)'
# A write verb in unparsed text; sed counts only with an in-place flag.
RE_MC_WRITE_VERB='(^|[^[:alnum:]_.-])(((cp|mv|install|ln|tee|dd|rsync)([^[:alnum:]_-]|$))|(sed[^;&|]*[[:space:]]-([A-Za-z]*i|-in-place)))'
# A construct that can rebind a variable the screen is trusting.
RE_MC_REBIND='(^|[^[:alnum:]_])(eval|printf[[:space:]]+-v|declare|typeset|local|read|mapfile|readarray|unset|source|export[[:space:]]+-n)([^[:alnum:]_]|$)|\$\{!'
MC_SETTINGS_DENY='mission control writes no settings or configuration file, and this command names one, or could through an expansion, in a form that is not a plain read - refusing. Read it with a plain reader such as cat, grep or jq, and hand a settings change to the operator ready to apply.'

# mc_settings_named <text> — 0 at the mission-control tier when the text,
# with its quote and escape characters removed, names a posture file.
mc_settings_named() {
  [ "${TIER:-}" = mission-control ] || return 1
  local t=${1//[\"\'\\]/} rc=1
  shopt -s nocasematch
  [[ $t =~ $RE_MC_POSTURE_NAME ]] && rc=0
  shopt -u nocasematch
  return "$rc"
}

# mc_posture_word <word> — 0 when the word names a posture file or lies under
# a posture directory, or reaches one through a dot-dot component.
mc_posture_word() {
  local t=${1//[\"\'\\]/} rc=1
  shopt -s nocasematch
  if [[ $t =~ $RE_MC_POSTURE_NAME ]] || [[ $t =~ $RE_MC_POSTURE_REL_DIR ]]; then
    rc=0
  elif [[ $t == *.c[l]aude* && ($t == *'/../'* || $t == *'/..') ]]; then
    rc=0
  fi
  shopt -u nocasematch
  return "$rc"
}

# mc_expands <word> — 0 when the word carries a shell expansion, glob or brace.
mc_expands() {
  case $1 in
    *'$'* | *'`'* | *'*'* | *'?'* | *'['* | *'{'*) return 0 ;;
  esac
  return 1
}

# mc_scratch_var <name> — 0 when the command assigns the variable exactly once,
# before any use, from a fresh mktemp -d or a literal scratch path, and
# changes it no other way. What a variable held in an earlier call is out of a
# text screen's sight, so it earns no trust.
mc_scratch_var() {
  local n=$1 t=${MC_CMD//[\"\'\\]/} re_asg re_other re_plus re_use before rest val
  [[ $n =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
  re_asg="(^|[^[:alnum:]_])$n="
  re_other="(read|for|local|declare|typeset|mapfile|readarray|unset|printf[[:space:]]+-v)[^;&|]*[^[:alnum:]_]$n([^[:alnum:]_]|\$)"
  re_plus="(^|[^[:alnum:]_])${n}[+]="
  [[ $t =~ $re_other || $t =~ $RE_MC_REBIND || $t =~ $re_plus ]] && return 1
  [[ $t =~ $re_asg ]] || return 1
  before=${t%%"${BASH_REMATCH[0]}"*}
  rest=${t#*"${BASH_REMATCH[0]}"}
  [[ $rest =~ $re_asg ]] && return 1
  # shellcheck disable=SC2016 # a regex
  re_use='(^|[^[:alnum:]_])\$(\{'$n'\}|'$n'([^[:alnum:]_]|$))'
  [[ $before =~ $re_use ]] && return 1
  # shellcheck disable=SC2016 # literal patterns
  case $rest in
    '$(mktemp -d)'* | '`mktemp -d`'*) return 0 ;;
  esac
  val=${rest%%[[:space:];&|)]*}
  case $val in *..* | *.c[l]aude* | *.mcp*) return 1 ;; esac
  [[ $val =~ ^(/tmp/claude-|/tmp/planwright-)[A-Za-z0-9._/-]*$ || $val =~ ^\$TMPDIR(/[A-Za-z0-9._/-]*)?$ ]]
}

# mc_installed_root_re — the installed root's path prefix, under the user's own
# home only: a look-alike path elsewhere (a scratch directory the session can
# write) is no installed script. Sets MC_ROOT_RE, 1 when HOME is unusable.
mc_installed_root_re() {
  local h=${HOME:-}
  case $h in /?*) ;; *) return 1 ;; esac
  MC_ROOT_RE=${h//[^A-Za-z0-9_\/-]/.}'/\.c[l]aude/plugins/cache/planwright/planwright/[0-9][A-Za-z0-9._+-]*/'
}

# mc_installed_script <path> — 0 when the path is a planwright script at the
# installed root: the session's own tooling, which a read of a configuration
# file may name.
mc_installed_script() {
  mc_installed_root_re || return 1
  [[ $1 =~ ^$MC_ROOT_RE'scripts/'[A-Za-z0-9._-]+\.sh$ ]]
}

# mc_literal_var <name> — 0, with the value in MC_VAR_VAL, when the command
# assigns the variable exactly once, as a plain literal that opens a statement
# of its own (after the start, a semicolon or a newline: never after && or in a
# group, where it may not run) and ends it, before any use, and changes it no
# other way. What a variable held in an earlier call is out of a text
# screen's sight, so it earns no trust.
mc_literal_var() {
  local n=$1 t=${MC_CMD//[\"\'\\]/} re_asg re_other re_plus re_use re_param before rest val tail
  MC_VAR_VAL=''
  [[ $n =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
  re_asg="(^|[^[:alnum:]_])$n="
  re_other="(read|for|local|declare|typeset|mapfile|readarray|unset|printf[[:space:]]+-v)[^;&|]*[^[:alnum:]_]$n([^[:alnum:]_]|\$)"
  re_plus="(^|[^[:alnum:]_])${n}[+]="
  re_param="[\$][{]${n}[:]?[=]"
  [[ $t =~ $re_other || $t =~ $RE_MC_REBIND || $t =~ $re_plus || $t =~ $re_param ]] && return 1
  [[ $t =~ $re_asg ]] || return 1
  before=${t%%"${BASH_REMATCH[0]}"*}
  rest=${t#*"${BASH_REMATCH[0]}"}
  [[ $rest =~ $re_asg ]] && return 1
  # shellcheck disable=SC2016 # a regex
  re_use='(^|[^[:alnum:]_])\$(\{'$n'\}|'$n'([^[:alnum:]_]|$))'
  [[ $before =~ $re_use ]] && return 1
  case $before in
    '' | *';' | *$'\n') ;;
    *)
      # Allow the `export ` form and spaces after a separator.
      before=${before%"${before##*[![:blank:]]}"}
      case $before in '' | *';' | *$'\n' | *'; export' | *$'\n'export) ;; *) return 1 ;; esac
      ;;
  esac
  val=${rest%%[[:space:];&|)]*}
  tail=${rest#"$val"}
  tail=${tail#"${tail%%[![:blank:]]*}"}
  case $tail in ';'* | $'\n'* | '&&'*) ;; *) return 1 ;; esac
  [[ $val =~ ^[A-Za-z0-9_./+:@%,=-]+$ && $val != *..* ]] || return 1
  MC_VAR_VAL=$val
  return 0
}

# mc_resolve_word <word> — rewrites a word that starts with a variable the
# command assigned a plain literal into MC_RW, 0 when it did so. Any other
# word, or an unresolvable variable, leaves MC_RW the word itself, status 1.
mc_resolve_word() {
  MC_RW=$1
  [[ $1 =~ ^\$(\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))(/.*)?$ ]] || return 1
  local name=${BASH_REMATCH[2]}${BASH_REMATCH[3]} rest=${BASH_REMATCH[4]}
  mc_literal_var "$name" || return 1
  MC_RW=$MC_VAR_VAL$rest
  return 0
}

# mc_data_target <word> — 0 when an expanding write target still sits in a
# data place: the harness scratch (never reaching a .claude or .mcp name), or a
# project memory or task folder, with no dot-dot component.
mc_data_target() {
  local t=${1//[\"\'\\]/}
  case $t in *'..'*) return 1 ;; esac
  if [[ $t =~ $RE_MC_DATA_SCRATCH ]]; then
    case ${t#"${BASH_REMATCH[0]}"} in *.c[l]aude* | *.mcp*) return 1 ;; esac
    return 0
  fi
  if [[ $t =~ $RE_MC_DATA_SCRATCHVAR ]]; then
    case $t in *.c[l]aude* | *.mcp*) return 1 ;; esac
    mc_scratch_var "${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
    return
  fi
  [[ $t =~ $RE_MC_DATA_MEMORY ]]
}

# mc_write_word_refused <word> — 0 when a word in a write position names a
# posture file or directory, or could expand into one.
mc_write_word_refused() {
  local w=${1#of=}
  mc_posture_word "$w" && return 0
  # A variable the command assigned a plain literal is that literal.
  if mc_resolve_word "$w"; then
    w=$MC_RW
    mc_posture_word "$w" && return 0
  fi
  mc_expands "$w" || return 1
  mc_data_target "$w" && return 1
  return 0
}

# mc_named_outside_messages — 0 when the tokenized words, apart from the value
# of a message flag, name a posture file.
mc_named_outside_messages() {
  local k=0 skip=0 acc='' w
  while [ "$k" -lt "${#W[@]}" ]; do
    w=${W[$k]}
    k=$((k + 1))
    if [ "$skip" = 1 ]; then
      skip=0
      continue
    fi
    case $w in
      --text | --act | --message | --body | --note | --reason | --title) skip=1 ;;
      --text=* | --act=* | --message=* | --body=* | --note=* | --reason=* | --title=*) ;;
      *) acc="$acc $w" ;;
    esac
  done
  mc_settings_named "$acc"
}

# mc_reader_segment <sed|find|gh> — 0 when the segment (SW) only reads: sed
# printing line ranges with -n, find with no action that runs or writes, and a
# gh view, list, diff or checks subcommand.
mc_reader_segment() {
  local w n=0 script=0 sub
  case $1 in
    sed)
      # The first plain word is the script; the words after it are files read.
      for w in "${SW[@]:1}"; do
        case $w in
          -n) n=1 ;;
          -*) return 1 ;;
          *)
            [ "$script" = 0 ] || continue
            script=1
            case $w in *[!0-9,\$pq]*) return 1 ;; esac
            ;;
        esac
      done
      [ "$n" = 1 ] && [ "$script" = 1 ]
      ;;
    find)
      for w in "${SW[@]:1}"; do
        case $w in
          -exec* | -ok* | -delete | -fprint* | -fls) return 1 ;;
        esac
      done
      ;;
    gh)
      sub=${SW[1]:-}
      case $sub in pr | issue | repo) ;; *) return 1 ;; esac
      for w in "${SW[@]:2}"; do
        case $w in -*) continue ;; esac
        case $w in view | list | diff | checks | status) return 0 ;; *) return 1 ;; esac
      done
      return 1
      ;;
  esac
}

# mc_settings_screen <command> — refuse a command that writes a posture file:
# one that names such a file in a form that is not a plain read (apart from
# the text of a message flag), redirects to a posture path or to a target the
# shell expands, or hands a posture path or an expanding word to cp, mv,
# install, ln, tee, dd, rsync or sed -i. An expansion in a read position, or
# under a data place, is no write. A relative name after a cd into a posture
# directory is out of a text screen's sight.
mc_settings_screen() {
  local t=$1 r si=0 k named=0 w m verb sedscript inplace
  MC_CMD=$t
  mc_settings_named "$t" && named=1
  # shellcheck disable=SC2016 # literal patterns
  case $t in
    *'>'* | *'$('* | *'`'* | *cp* | *mv* | *install* | *ln* | *tee* | *dd* | *rsync* | *sed*) ;;
    *) [ "$named" = 1 ] || return 0 ;;
  esac
  [ "${#t}" -le "$MAX_CMD_LEN" ] || emit_deny "$MC_SETTINGS_DENY"
  r=${t//&>\/dev\/null/}
  r=${r//[0-9]>\/dev\/null/}
  r=${r//>\/dev\/null/}
  r=${r//[0-9]>&[0-9]/}
  [ "$named" = 0 ] || case $r in *'>'*) emit_deny "$MC_SETTINGS_DENY" ;; esac
  # Quoted text is no redirect unless a shell is handed it to run or the quote
  # is itself the redirect's target.
  # A backslash can desync the quote pairing, so such text is scanned whole.
  if ! [[ $r =~ $RE_MC_INTERPRETER || $r == *\\* ]]; then
    local q=$r out=''
    while [[ $q =~ (\>[[:space:]]*)?(\"[^\"]*\"|\'[^\']*\') ]]; do
      m=${BASH_REMATCH[0]}
      out="$out${q%%"$m"*}"
      if [ -n "${BASH_REMATCH[1]}" ]; then out="$out$m"; else out="${out}Q"; fi
      q=${q#*"$m"}
    done
    r=$out$q
  fi
  while [[ $r =~ \>+[[:space:]]*([^[:space:]\;\|\&\<\>]+) ]]; do
    m=${BASH_REMATCH[0]}
    w=${BASH_REMATCH[1]}
    ! mc_write_word_refused "$w" || emit_deny "$MC_SETTINGS_DENY"
    r=${r#*"$m"}
  done
  if ! tokenize "$t"; then
    # Unparsed text (a command substitution, say) fails closed where it could
    # name a posture path or hand a write verb a target the screen cannot read;
    # its redirects were already vetted above.
    # The installed root sits under ~/.claude/plugins, and a run of planwright's
    # own scripts from it names no posture file by that prefix alone.
    local nr=$t
    if mc_installed_root_re; then
      while [[ $nr =~ $MC_ROOT_RE ]]; do nr=${nr/"${BASH_REMATCH[0]}"/}; done
    fi
    case $nr in
      *.c[l]aude* | *.mcp* | *settings* | *planwright.*) emit_deny "$MC_SETTINGS_DENY" ;;
    esac
    [[ ${t//[\"\'\\]/} =~ $RE_MC_WRITE_VERB ]] && emit_deny "$MC_SETTINGS_DENY"
    return 0
  fi
  if [ "$named" = 1 ]; then
    # A heredoc body can be run, so its text keeps the whole-text verdict.
    if [ "${#SEG_DOC[@]}" -gt 0 ] && [ -n "${SEG_DOC[*]}" ]; then :; else
      mc_named_outside_messages || named=0
    fi
  fi
  # A write verb inside a substitution runs, though no segment names it.
  for k in "${!W[@]}"; do
    [ "${WL[$k]}" != 1 ] || continue
    # shellcheck disable=SC2016 # literal patterns
    case ${W[$k]} in
      *'$('* | *'`'*) [[ ${W[$k]//[\"\'\\]/} =~ $RE_MC_WRITE_VERB ]] && emit_deny "$MC_SETTINGS_DENY" ;;
    esac
  done
  while [ "$si" -lt "${#SEG_S[@]}" ]; do
    segment_words "$si"
    si=$((si + 1))
    [ "${#SW[@]}" -gt 0 ] || continue
    if [ "$named" = 1 ]; then
      # A loop or condition keyword opens a segment; the command after it is
      # the segment's own, and a loop's word list must hold no substitution,
      # which would run.
      case ${SW[0]} in
        for | done | fi | 'esac')
          for w in "${SW[@]}"; do
            # shellcheck disable=SC2016 # literal patterns
            case $w in *'$('* | *'`'*) emit_deny "$MC_SETTINGS_DENY" ;; esac
          done
          continue
          ;;
        do | then | else | elif | if | while | until | '!')
          SW=("${SW[@]:1}")
          SWL=("${SWL[@]:1}")
          [ "${#SW[@]}" -gt 0 ] || continue
          ;;
      esac
      if [ "${SWL[0]}" != 1 ]; then
        mc_resolve_word "${SW[0]}" || emit_deny "$MC_SETTINGS_DENY"
        SW[0]=$MC_RW
      fi
      # One of planwright's own scripts at the installed root reads what it is
      # handed, apart from the two that write configuration.
      if mc_installed_script "${SW[0]}"; then
        case ${SW[0]##*/} in install.sh | mc-config.sh) emit_deny "$MC_SETTINGS_DENY" ;; esac
        continue
      fi
      case ${SW[0]} in
        */*)
          case ${SW[0]} in
            /bin/[!/]* | /usr/bin/[!/]*) ;;
            *) emit_deny "$MC_SETTINGS_DENY" ;;
          esac
          ;;
      esac
      lc "${SW[0]##*/}"
      case $LC in
        cat | head | tail | jq | grep | egrep | fgrep | wc | ls | stat | diff | cmp | cut | tr | nl | tac | rev | column) ;;
        sed | find | gh) mc_reader_segment "$LC" || emit_deny "$MC_SETTINGS_DENY" ;;
        *) emit_deny "$MC_SETTINGS_DENY" ;;
      esac
      continue
    fi
    lc "${SW[0]##*/}"
    verb=$LC
    inplace=0
    case $verb in
      cp | mv | install | ln | tee | dd | rsync) ;;
      sed)
        for w in "${SW[@]:1}"; do
          case $w in -i* | -[!-]*i* | --in-place*) inplace=1 ;; esac
        done
        [ "$inplace" = 1 ] || continue
        ;;
      *) continue ;;
    esac
    # sed's first plain word is its script, which is no path.
    sedscript=0
    if [ "$verb" = sed ]; then
      sedscript=1
      for w in "${SW[@]:1}"; do
        case $w in -e | -f | --expression | --file) sedscript=0 ;; esac
      done
    fi
    for w in "${SW[@]:1}"; do
      case $w in
        -e | -f | --expression | --file)
          sedscript=1
          continue
          ;;
        -*) continue ;;
      esac
      if [ "$sedscript" = 1 ]; then
        sedscript=0
        continue
      fi
      ! mc_write_word_refused "$w" || emit_deny "$MC_SETTINGS_DENY"
    done
  done
  return 0
}

# mc_repo_walk <dir> <how> — refuse when <dir> or an ancestor is a git work
# tree (it holds a .git entry) or a bare repository (HEAD, objects and refs).
mc_repo_walk() {
  local d=$1
  while :; do
    if [ -e "$d/.git" ] || { [ -f "$d/HEAD" ] && [ -d "$d/objects" ] && [ -d "$d/refs" ]; }; then
      emit_deny "mission control edits no repository, and this path $2 inside one; every change goes through a session it dispatches."
    fi
    [ "$d" != / ] || return 0
    d=${d%/*}
    [ -n "$d" ] || d=/
  done
}

# mc_posture_path <path> <verb> — refuse a path naming a posture file or
# lying under a posture directory; <verb> completes the refusal's "this path
# <verb> one".
mc_posture_path() {
  local rc=1
  shopt -s nocasematch
  [[ $1 =~ $RE_MC_POSTURE_DIR ]] && rc=0
  shopt -u nocasematch
  if [ "$rc" = 0 ] || mc_settings_named "${1##*/}"; then
    emit_deny "mission control never writes a settings or configuration file, nor widens its own posture; this path $2 one. A settings change is handed to the operator ready to apply."
  fi
}

# mc_file_path <path> — one file-tool path: refuse a posture file, a path
# inside a repository (read lexically and, from its deepest existing
# directory, physically with the missing remainder kept), a symbolic link,
# and any path the guard cannot read.
mc_file_path() {
  local path=$1 d phys rest
  case $path in
    /*) ;;
    *) emit_deny 'this file-tool path is not absolute, so the guard cannot place it - refusing (fail closed). Name the file by its absolute path.' ;;
  esac
  while :; do
    case $path in
      *//*) path=${path//\/\//\/} ;;
      *) break ;;
    esac
  done
  case "$path/" in
    */./* | */../*) emit_deny 'this file-tool path carries a . or .. component, which the guard does not resolve - refusing (fail closed). Name the file by its plain absolute path.' ;;
  esac
  mc_posture_path "$path" is
  [ ! -L "$path" ] \
    || emit_deny 'this file-tool path is a symbolic link, which could reach a repository or a settings file - refusing (fail closed).'
  d=${path%/*}
  [ -n "$d" ] || d=/
  mc_repo_walk "$d" lies
  while [ ! -d "$d" ]; do
    d=${d%/*}
    [ -n "$d" ] || d=/
  done
  phys=$(cd -P -- "$d" 2>/dev/null && pwd) \
    || emit_deny 'the guard cannot resolve this file-tool path - refusing (fail closed).'
  [ "$phys" = "$d" ] && return 0
  rest=${path#"$d"}
  mc_repo_walk "$phys" resolves
  mc_posture_path "${phys%/}$rest" "resolves to"
}

# handle_file <payload> — an Edit, Write, MultiEdit or NotebookEdit call at the
# mission-control tier: every path field it carries passes mc_file_path.
handle_file() {
  local paths p n=0
  paths=$(printf '%s' "$1" | jq -r '.tool_input
    | if type == "object" then [.file_path, .notebook_path] else [] end
    | .[] | select(. != null)
    | if type == "string" and (test("[\u0000\n]") | not) then . else "unreadable" end' 2>/dev/null) || paths=''
  # A value that is not a plain one-line string comes through as a relative
  # word, which mc_file_path refuses.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n=$((n + 1))
    mc_file_path "$p"
  done <<EOF
$paths
EOF
  [ "$n" -gt 0 ] \
    || emit_deny 'this file-tool payload names no file path the guard can read, so it cannot tell whether it writes a repository or a settings file - refusing (fail closed).'
  return 0
}

# mc_unparsed_command_names <command> — refuses, in text the guard cannot
# parse, a statement whose command name is a bare variable that is not a plain
# literal the command assigned: it could be git or gh.
mc_unparsed_command_names() {
  # shellcheck disable=SC2016 # a regex; `$` is literal
  local rest=$1 word re='(^|[;&|]|'$'\n'')[[:space:]]*(\$([{][A-Za-z_][A-Za-z0-9_]*[}]|[A-Za-z_][A-Za-z0-9_]*))([[:space:];&|]|$)'
  MC_CMD=$1
  while [[ $rest =~ $re ]]; do
    word=${BASH_REMATCH[2]}
    rest=${rest#*"${BASH_REMATCH[0]}"}
    mc_resolve_word "$word" \
      || emit_deny "this command's name is an expansion the guard cannot read ($(sanitize_printable "$word" 'unprintable')), in text it cannot parse, so it could be git or gh - refusing (fail closed). Write the command name literally."
  done
  return 0
}

handle_bash() {
  local cmd=$P_CMD
  if [ "$P_CMD_OK" != 1 ] || [ -z "$cmd" ]; then
    raw_evidence "$1" && emit_deny 'this Bash payload carries no readable command string and its raw content names a reserved act - refusing (fail closed).'
    mc_settings_named "$1" && emit_deny "$MC_SETTINGS_DENY"
    return 0
  fi
  [ "$TIER" != mission-control ] || mc_settings_screen "$cmd"
  # No git, no gh, no merge-helper, force-push-helper, or glob spelling
  # anywhere, even with quotes and escapes removed, and no expansion beside
  # a reserved subcommand: nothing this guard classifies, so no parse and no
  # read.
  local bare=${cmd//[\"\'\\]/} hit=0
  shopt -s nocasematch
  case $bare in
    *git* | *gh* | *merge-ad* | *--for-merge* | *tower-force-push* | *kickoff-spec*) hit=1 ;;
    # A glob or brace word could still name the merge helper.
    *admitted* | *'*'* | *'?'* | *'['* | *'{'*) hit=1 ;;
    *'$'* | *'`'*)
      case $bare in
        *merge* | *pull* | *rebase* | *push* | *commit* | *ready* | *api*) hit=1 ;;
      esac
      ;;
  esac
  shopt -u nocasematch
  # Any expansion can assemble a command word, so its command is parsed.
  case $cmd in *'$'* | *'`'*) hit=1 ;; esac
  [ "$hit" = 1 ] || return 0
  case $P_CWD_TYPE in
    absent) PAYLOAD_CWD=$PWD ;;
    string)
      if [ -n "$P_CWD" ]; then
        PAYLOAD_CWD=$P_CWD CWD_REPORTED=1
      else
        PAYLOAD_CWD=$PWD
      fi
      ;;
    *)
      raw_evidence "$cmd" && emit_deny 'this Bash payload carries a malformed cwd and its command names a reserved act - refusing (fail closed).'
      return 0
      ;;
  esac
  # Where the parse is unavailable the whole text is screened, here-document
  # bodies included: only the parse can tell a body bash runs from one it
  # hands to a command as data.
  if [ "${#cmd}" -gt "$MAX_CMD_LEN" ]; then
    raw_evidence "$cmd" && deny_unanalyzable 'this command is too long for the guard to analyze'
    return 0
  fi
  if ! tokenize "$cmd"; then
    [ "$TIER" != mission-control ] || mc_unparsed_command_names "$cmd"
    raw_evidence "$cmd" \
      && deny_unanalyzable 'this command uses a construct the guard will not analyze (command or process substitution, backticks, ANSI-C quoting, or grouping)'
    return 0
  fi
  if [ "$HEREDOC_SUBST" = 1 ]; then
    raw_evidence "$cmd" \
      && deny_unanalyzable 'this command carries an unquoted here-document whose body runs a substitution'
  fi
  # A word that carries substitution text is inert as a word, but an
  # arithmetic context (let, declare -i, a [[ ]] numeric test) evaluates it
  # again and runs it.
  local w subst=0 arith=0
  for w in "${W[@]}"; do
    # shellcheck disable=SC2016 # the literal `$(` is the pattern
    case $w in
      *'$('* | *'`'*) subst=1 ;;
    esac
    case $w in
      let | '[[' | -eq | -ne | -lt | -le | -gt | -ge | -i | -[!-]*i*) arith=1 ;;
    esac
  done
  if [ "$subst" = 1 ] && [ "$arith" = 1 ]; then
    raw_evidence "$cmd" \
      && deny_unanalyzable 'this command evaluates text carrying a substitution in an arithmetic context'
  fi
  classify_segments
  [ -z "$DENY_NOW" ] || emit_deny "$DENY_NOW"
  [ "${#PENDING[@]}" = 0 ] && return 0
  need_timeout
  eval_pending
}

emit_deny_internal() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"planwright policy-guard: the guard stopped before it reached a decision (an internal error or a signal), so this call could not be checked against the policy - refusing (fail closed). Retry; report a guard that keeps failing on the same command."}}'
  exit 0
}

# A signal mid-evaluation, or a crash (a non-zero exit with no decision),
# refuses rather than leaving the call undecided, which Claude Code would let
# through. main runs in a subshell so a crash returns here.
trap 'emit_deny_internal' HUP INT TERM
trap 'exit 0' PIPE

PG_OUT=$(main "$@")
PG_RC=$?
if [ -n "$PG_OUT" ]; then
  printf '%s\n' "$PG_OUT"
elif [ "$PG_RC" != 0 ]; then
  case ${1:-} in
    worker | tower | mission-control) emit_deny_internal ;;
  esac
fi
exit 0
