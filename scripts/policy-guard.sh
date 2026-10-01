#!/usr/bin/env bash
# policy-guard.sh — the deny-emitting PreToolUse hook that enforces the
# human-gates policy knobs for the tier a session runs under (human-gates D-9;
# doctrine/human-gates.md states the list and each rule's kind).
#
# Usage, as the tier profiles wire it:
#   policy-guard.sh <tier> <surface>
# <tier> is `worker` or `tower`, carried by the settings profile the session
# runs under; any other value, or none, is a session with no tier profile,
# which is outside this guard's jurisdiction, so it defers with no read.
# <surface> is `bash` or `mcp`: which matcher fired, so a payload that lost its
# tool_name on the MCP matcher still denies.
#
# MODALITY. Like the ready-guard and unlike the allow-only command guards, this
# guard emits deny, so a missed deny defeats it and a false deny blocks work.
# Every refusal names its remedy.
#
# ORDER. The intercepted call is classified first, with no knob read: a call
# that performs none of the acts below defers at zero cost, and a call whose
# verdict no value can change (the floor, the tower's refusals, a `gh api` act,
# a request the guard cannot read) denies before any read. Only then does the
# guard read the knob the matched act needs, through
# scripts/resolve-policy-knob.sh, bounded by a wall-clock limit; any read
# failure denies.
#
# ACTS.
#   flip        `gh pr ready <n>` and the MCP draft->ready transition.
#               tower: deny. worker: ready_flip_policy (unit-owner defers, so
#               the ready-guard's currency check runs next).
#   undo        `gh pr ready --undo` and the MCP ready->draft transition: deny,
#               the corrective helper being the only sanctioned re-draft.
#   pr-merge    `gh pr merge`: deny; the merge helper is the only agent path.
#   base-merge  `git merge`, `git pull` in merge mode. tower: deny. worker:
#               worker_base_merge, then the current branch must be the session's
#               unit branch outside the protected set and every source the PR
#               base.
#   rewrite     amend, `--squash`, `--fixup`, rebase, `git pull` in rebase
#               mode. tower: deny. worker: unpushed_rewrite, then the unit
#               branch rule, then the never-pushed check: the upstream tracking
#               ref is refreshed and no remote-tracking ref may contain a
#               rewritten commit.
#   push        a force or bulk push denies; every other push reads the
#               protected set and denies a target inside it.
#   gh api      classified by the act it performs (D-9's readable and matching
#               rules): the flip, undo, PR merge, base merge, and forced ref
#               update deny at every tier with no read; a ref, contents, or
#               commit write reads only the protected set; a request the guard
#               cannot read denies before any read; anything else defers.
# Every segment of a compound command is classified and the strictest verdict
# wins.
#
# THE UNIT BRANCH. A session owns the branch checked out at its project
# directory (CLAUDE_PROJECT_DIR, which Claude Code sets for every hook), when
# that branch is a task or flight branch. The PR base is the default branch of
# the unit branch's remote as recorded locally (`refs/remotes/<remote>/HEAD`,
# else `main`): the guard never queries the host for it.
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
  out=$(jq -nc --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null) \
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

raw_evidence_one() {
  local t=$1
  [[ $t =~ $RE_GH_API ]] && return 0
  [[ $t =~ $RE_GH_PR ]] && return 0
  [[ $t =~ $RE_GIT_ACT ]] && return 0
  [[ $t =~ $RE_GIT_REWRITE ]] && return 0
  case $t in *"$MCP_TOOL"*) return 0 ;; esac
  return 1
}

# raw_evidence <text> — the text as written, then with its quote and escape
# characters removed, so `me""rge` reads as `merge`.
raw_evidence() {
  raw_evidence_one "$1" && return 0
  raw_evidence_one "$(printf '%s' "$1" | tr -d "\"'\\\\")"
}

# strip_heredoc_bodies <text> — the text with every here-document body removed,
# so a commit message or PR body handed over a heredoc is not read as commands.
strip_heredoc_bodies() {
  local line out='' delim='' tabs=0 cand re
  re='<<(-?)[[:space:]]*["'"'"'\\]?([A-Za-z_][A-Za-z0-9_]*)'
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "$delim" ]; then
      cand=$line
      [ "$tabs" = 0 ] || cand=${cand#"${cand%%[!"$TAB"]*}"}
      [ "$cand" != "$delim" ] || delim=''
      continue
    fi
    out="$out$line$NL"
    if [[ $line =~ $re ]]; then
      delim=${BASH_REMATCH[2]}
      tabs=0
      [ -z "${BASH_REMATCH[1]}" ] || tabs=1
    fi
  done <<EOF
$1
EOF
  printf '%s' "$out"
}

deny_unanalyzable() {
  emit_deny "$1 and its text names a reserved act (a gh api request, a pull-request flip or merge, or a git merge, pull, rebase, push, or history rewrite) - refusing (fail closed). Issue that command on its own as a plain simple command."
}

# --------------------------------------------------------------------------
# Tokenizer. Splits the command as written into segments on the unquoted
# control operators, honoring quotes, comments, redirects, and here-documents.
# Per word it records whether the word is literal: free of expansion, an
# escape or `$` outside single quotes, and an unquoted glob or brace (gh's
# `{owner}`, `{repo}`, and `{branch}` placeholders excepted). It refuses
# command and process substitution, backticks, ANSI-C quoting, and grouping.
#
# Results: W[] words, WL[] literal flags, SEG_S[]/SEG_E[] word ranges,
# SEG_TERM[] terminators, SEG_DOC[] here-document bodies per segment.

tokenize() {
  local s=$1
  local n=${#s} i=0 c nc ch cur='' have=0 lit=1 uqonly=1 digits_only=1
  local pending_delims=() pending_tabs=() pending_seg=()
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
      SEG_DOC[${#SEG_DOC[@]}]=''
    fi
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
      local si=${pending_seg[$k]}
      if [ "$si" -lt "${#SEG_DOC[@]}" ]; then
        SEG_DOC[si]="${SEG_DOC[si]}$body"
      fi
    done
    pending_delims=()
    pending_tabs=()
    pending_seg=()
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
              esac
              cur="$cur\\"
              ;;
            '`') return 1 ;;
            '$')
              [ "${s:j+1:1}" != '(' ] || return 1
              lit=0
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
          '(' | "'") return 1 ;;
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
        if [ "$have" = 1 ] && [ "$uqonly" = 1 ] && [ "$digits_only" = 1 ]; then
          cur=''
          have=0
        fi
        flush_word || return 1
        if [ "$c" = '<' ] && [ "$nc" = '<' ] && [ "${s:i+2:1}" != '<' ]; then
          # A here-document: record its delimiter; the body is read at the
          # next newline.
          i=$((i + 2))
          local tabs=0 delim=''
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
                i=$((i + 1))
                while [ "$i" -lt "$n" ] && [ "${s:i:1}" != "$q" ]; do
                  delim="$delim${s:i:1}"
                  i=$((i + 1))
                done
                [ "$i" -lt "$n" ] || return 1
                ;;
              "\\") ;;
              *) delim="$delim$ch" ;;
            esac
            i=$((i + 1))
          done
          [ -n "$delim" ] || return 1
          pending_delims[${#pending_delims[@]}]=$delim
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

timeout_bin() {
  if command -v timeout >/dev/null 2>&1; then
    printf 'timeout'
  elif command -v gtimeout >/dev/null 2>&1; then
    printf 'gtimeout'
  fi
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
need_timeout() {
  [ -n "$TB" ] || TB=$(timeout_bin)
  [ -n "$TB" ] \
    || emit_deny 'no timeout (or gtimeout) binary is on PATH, so the guard cannot bound its policy read - refusing (fail closed). Install coreutils.'
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
    "" | -* | /* | */ | *//* | *..* | *[!A-Za-z0-9._/+@-]* | *.lock | *.) return 1 ;;
  esac
  [ "${#1}" -le 255 ]
}

is_unit_branch() {
  local re_task='^planwright/[a-z0-9][a-z0-9-]*/task-[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$'
  local re_flight='^planwright/flight/[a-z0-9][a-z0-9-]*-[0-9a-f]{8}$'
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

# read_knob <knob> <dir> <legal...> — the resolved value, or a deny.
read_knob() {
  local knob=$1 dir=$2 v rc=0 ok=0 legal
  shift 2
  need_timeout
  [ -n "$GUARD_DIR" ] && [ -r "$GUARD_DIR/resolve-policy-knob.sh" ] \
    || emit_deny "the policy resolver is missing beside this guard, so $knob could not be read - refusing (fail closed). Reinstall planwright."
  v=$(cd -- "$dir" 2>/dev/null && "$TB" "$KNOB_T" /bin/sh "$GUARD_DIR/resolve-policy-knob.sh" "$knob" 2>/dev/null </dev/null) || rc=$?
  if [ "$rc" = 124 ]; then
    emit_deny "reading the policy knob $knob did not finish within ${KNOB_T}s - refusing (fail closed). This is a timeout, not a policy decision: retry, and report a resolver that stays slow."
  fi
  [ "$rc" = 0 ] \
    || emit_deny "the policy knob $knob could not be resolved (resolver exit $rc), so the act it governs is refused (fail closed). Repair the malformed value or install, then retry."
  for legal in "$@"; do
    [ "$v" != "$legal" ] || ok=1
  done
  [ "$ok" = 1 ] \
    || emit_deny "the policy knob $knob resolved to a value the guard does not recognize ($(sanitize_printable "$v" 'unprintable')) - refusing (fail closed)."
  KNOB_VAL=$v
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
  err=$(cd -- "$dir" 2>/dev/null && "$TB" "$KNOB_T" /bin/sh "$GUARD_DIR/protected-branch.sh" "$@" 2>&1 >/dev/null </dev/null) || rc=$?
  case $rc in
    0) return 0 ;;
    1)
      emit_deny "$what targets a protected branch ($(sanitize_printable "${err#protected-branch: }" 'a protected branch')); main, master, spec branches, and the protected_branches additions are never written by an agent session at any tier. Work on your own unit branch."
      ;;
    124)
      emit_deny "reading the protected set did not finish within ${KNOB_T}s - refusing $what (fail closed). This is a timeout, not a policy decision: retry."
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

# unit_branch — the session's unit branch (its project directory's branch), or
# a deny.
UNIT_BRANCH=''
unit_branch_or_deny() {
  local what=$1 pdir=${CLAUDE_PROJECT_DIR:-} b
  [ -n "$UNIT_BRANCH" ] && return 0
  [ -n "$pdir" ] && [ -d "$pdir" ] \
    || emit_deny "$what needs the session's unit branch, and the hook received no project directory (CLAUDE_PROJECT_DIR) to read it from - refusing (fail closed)."
  b=$(current_branch "$pdir")
  is_unit_branch "$b" \
    || emit_deny "$what is allowed only on the session's own unit branch (a planwright/<spec>/task-<id> or planwright/flight/<id> branch), and this session's project directory has $(sanitize_printable "${b:-no branch}" 'an unreadable branch') checked out - refusing."
  UNIT_BRANCH=$b
}

# on_unit_branch <dir> <what> — deny unless <dir> has the unit branch checked
# out and that branch is outside the protected set.
on_unit_branch() {
  local dir=$1 what=$2 b
  unit_branch_or_deny "$what"
  b=$(current_branch "$dir")
  [ -n "$b" ] \
    || emit_deny "$what runs where no branch is checked out (a detached HEAD or an unreadable repository) - refusing (fail closed)."
  [ "$b" = "$UNIT_BRANCH" ] \
    || emit_deny "$what would run on $(sanitize_printable "$b" 'another branch'), which is not this session's unit branch ($(sanitize_printable "$UNIT_BRANCH" 'unreadable')) - refusing. Run it in your own worktree."
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

# is_base_ref <dir> <name> — 0 when the merge source names the PR base.
is_base_ref() {
  local d=$1 r=$2 fh line
  case $r in
    "$BASE_REMOTE/$BASE_BRANCH" | "refs/remotes/$BASE_REMOTE/$BASE_BRANCH" | "remotes/$BASE_REMOTE/$BASE_BRANCH") return 0 ;;
    "$BASE_BRANCH" | "refs/heads/$BASE_BRANCH" | "heads/$BASE_BRANCH") return 0 ;;
    FETCH_HEAD)
      fh=$(gitq "$d" rev-parse --git-path FETCH_HEAD) || return 1
      case $fh in /*) ;; *) fh="$d/$fh" ;; esac
      [ -r "$fh" ] || return 1
      local seen=0
      while IFS= read -r line; do
        case $line in
          *"${TAB}not-for-merge${TAB}"*) continue ;;
          *"${TAB}${TAB}branch '$BASE_BRANCH' of "*) seen=1 ;;
          *) return 1 ;;
        esac
      done <"$fh"
      [ "$seen" = 1 ]
      return
      ;;
  esac
  return 1
}

# refresh_and_check_unpushed <dir> <what> <range> — the never-pushed check:
# refresh the branch's upstream tracking ref, then require that no
# remote-tracking ref contains any commit of the range.
refresh_and_check_unpushed() {
  refresh_upstream "$1" "$2"
  check_unpushed "$@"
}

refresh_upstream() {
  local d=$1 what=$2 rc=0
  upstream_of "$d" "$CUR_BRANCH"
  { [ -n "$UP_REMOTE" ] && [ "$UP_REMOTE" != . ] && [ -n "$UP_BRANCH" ]; } \
    || emit_deny "$what rewrites history, and $(sanitize_printable "$CUR_BRANCH" 'this branch') has no upstream on a remote, so the guard cannot prove the commits were never pushed - refusing. Push the branch with -u once (new commits only), then retry."
  valid_branch "$UP_BRANCH" && [[ $UP_REMOTE =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
    || emit_deny "$what: the branch's upstream is not a shape the guard will fetch - refusing (fail closed)."
  GIT_TERMINAL_PROMPT=0 "$TB" "$FETCH_T" git -C "$d" fetch --quiet --no-tags --no-write-fetch-head \
    --no-recurse-submodules "$UP_REMOTE" "+refs/heads/$UP_BRANCH:refs/remotes/$UP_REMOTE/$UP_BRANCH" \
    </dev/null >/dev/null 2>&1 || rc=$?
  [ "$rc" = 0 ] \
    || emit_deny "$what rewrites history, and refreshing the upstream $(sanitize_printable "$UP_REMOTE/$UP_BRANCH" 'tracking ref') failed (exit $rc), so a commit pushed from another clone could read as never-pushed - refusing (fail closed). Retry when the remote is reachable."
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
  while [ "$k" -lt "$e" ]; do
    w=${W[$k]}
    case $w in
      '!' | if | then | else | elif | do | while | until | time | nocorrect | noglob | builtin)
        k=$((k + 1))
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

segment_text() {
  local k=${SEG_S[$1]} e=${SEG_E[$1]} t=''
  while [ "$k" -lt "$e" ]; do
    t="$t ${W[$k]}"
    k=$((k + 1))
  done
  printf '%s%s%s' "$t" "$NL" "${SEG_DOC[$1]}"
}

deny_now() {
  [ -n "$DENY_NOW" ] || DENY_NOW=$1
}

classify_segments() {
  local si=0 eff=$PAYLOAD_CWD eff_ok=1 verb
  while [ "$si" -lt "${#SEG_S[@]}" ]; do
    segment_words "$si"
    if [ "${#SW[@]}" = 0 ]; then
      si=$((si + 1))
      continue
    fi
    verb=${SW[0]}
    if [ "$SW_WRAPPED" = 1 ]; then
      raw_evidence "$(segment_text "$si")" \
        && deny_now "this command runs through a wrapper whose options the guard does not read, and its text names a reserved act - refusing (fail closed). Issue the command directly."
    else
      case $verb in
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
        git | */git) classify_git "$si" "$eff" "$eff_ok" ;;
        gh) classify_gh "$si" "$eff" "$eff_ok" ;;
        */gh)
          case " ${SW[*]} " in
            *" api "*) deny_now "this gh api call names gh by a path, which the guard does not place as the gh verb, so the request cannot be read - refusing (fail closed). Call it as plain gh api with a literal request." ;;
            *) classify_gh "$si" "$eff" "$eff_ok" ;;
          esac
          ;;
        env | sudo | doas | xargs | nohup | nice | ionice | timeout | gtimeout | stdbuf | setsid | \
          chronic | eval | bash | sh | zsh | dash | ksh | mksh | fish | busybox | script | watch | \
          parallel | find | flock | unbuffer | caffeinate | source | . | ssh | tmux | screen)
          raw_evidence "$(segment_text "$si")" \
            && deny_now "this command hands its work to $(sanitize_printable "$verb" 'a wrapper'), whose argument the guard cannot read as a command, and its text names a reserved act - refusing (fail closed). Issue the command directly."
          ;;
      esac
    fi
    si=$((si + 1))
  done
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
        esac
        return 0
        ;;
      *) break ;;
    esac
  done
  [ "$k" -lt "$n" ] || return 0
  case ${SW[$k]} in
    api) classify_gh_api "$si" "$((k + 1))" "$eff" "$eff_ok" ;;
    pr)
      case ${SW[$((k + 1))]:-} in
        ready) classify_gh_ready "$((k + 2))" "$eff" "$eff_ok" ;;
        merge)
          local a
          for a in "${SW[@]:$((k + 2))}"; do
            case $a in --help | -h) return 0 ;; esac
          done
          deny_now 'gh pr merge is denied to every agent session under every merge_policy value; under policy-class the merge helper is the only sanctioned agent path, and otherwise the operator merges (or enables auto-merge).'
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
    deny_now 'gh pr ready --undo is denied: re-drafting a pull request is reserved to the corrective helper that follows a reviewer request. Ask the operator if a PR needs to go back to draft.'
    return 0
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
              true | false | t | f | 1 | 0) ;;
              *)
                ghapi_opaque "the flag --$(sanitize_printable "$name" 'a flag') carries a value the guard does not parse"
                return 0
                ;;
            esac
            [ "$name" != help ] || help=1
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
      deny_now 'this gh api request converts a pull request to draft; re-drafting is reserved to the corrective helper. Ask the operator if a PR needs to go back to draft.'
      return 0
      ;;
    *mergePullRequest* | *enablePullRequestAutoMerge* | *enqueuePullRequest*)
      deny_now 'this gh api request merges a pull request, enables auto-merge, or enqueues it; no agent merges through gh api under any merge_policy value. The operator merges or enables auto-merge (under policy-class, the merge helper is the only agent path).'
      return 0
      ;;
    *mergeBranch* | *updatePullRequestBranch*)
      deny_now 'this gh api request merges into a branch on the host; the gh api spelling of a base merge is never the permitted path. Merge the PR base locally with scripts/converge-sync-main.sh.'
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
      deny_now 'this gh api request updates a pull request branch from its base on the host; merge the PR base locally with scripts/converge-sync-main.sh instead.'
      return 0
      ;;
  esac
  case "$seg_count:${4:-}" in
    4:merges | 4:merge-upstream)
      deny_now 'this gh api request merges into a branch on the host; the gh api spelling of a base merge is never the permitted path. Merge the PR base locally with scripts/converge-sync-main.sh.'
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

classify_git() {
  local si=$1 k=1 n=${#SW[@]} w key foreign=0 dir=$2 dir_ok=$3 sub=''
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
        k=$((k + 1))
        key=${SW[$k]:-}
        git_config_key_check "$key" || return 0
        ;;
      -c?* | --config-env=*)
        key=${w#-c}
        key=${key#--config-env=}
        git_config_key_check "$key" || return 0
        ;;
      --git-dir | --work-tree | --namespace | --super-prefix)
        foreign=1
        k=$((k + 1))
        ;;
      --git-dir=* | --work-tree=* | --namespace=* | --super-prefix=* | --bare | --exec-path=*)
        foreign=1
        ;;
      -*) ;;
      *)
        sub=$w
        break
        ;;
    esac
    k=$((k + 1))
  done
  [ -n "$sub" ] || return 0
  [ "${SWL[$k]}" = 1 ] || {
    case $sub in
      *merge* | *pull* | *rebase* | *commit* | *push*)
        deny_now 'this git command names its subcommand through an expansion the guard cannot read - refusing (fail closed). Write the subcommand literally.'
        ;;
    esac
    return 0
  }
  [ -d "$dir" ] || dir_ok=0

  case " $GIT_BUILTINS " in
    *" $sub "*) ;;
    *)
      git_alias_check "$sub" "$dir" "$dir_ok" "$si" "$k"
      return 0
      ;;
  esac

  case $sub in
    merge | pull | rebase | commit | push) ;;
    *) return 0 ;;
  esac
  if [ "$foreign" = 1 ]; then
    deny_now "this git $sub carries --git-dir, --work-tree, --namespace, or --bare, which the guard does not follow to a repository - refusing (fail closed). Use git -C <dir> $sub instead."
    return 0
  fi
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
  local sub=$1 dir=$2 dir_ok=$3 v ac
  case $sub in
    *[!A-Za-z0-9_.-]* | -*) return 0 ;;
  esac
  if [ "$dir_ok" != 1 ]; then
    return 0
  fi
  need_timeout
  v=$(gitq "$dir" config --get "alias.$sub") || v=''
  if [ -n "$v" ]; then
    case $v in
      '!'*)
        raw_evidence "git ${v#!}" || raw_evidence "$v" \
          && deny_now "the git alias $(sanitize_printable "$sub" 'used here') runs a shell command that names a reserved act - refusing (fail closed). Run the commands directly."
        ;;
      *)
        local first=${v%% *}
        case $first in
          merge | pull | rebase | commit | push | -*)
            deny_now "the git alias $(sanitize_printable "$sub" 'used here') expands to git $(sanitize_printable "$first" 'a reserved subcommand'), which the guard reads only by its own name - refusing. Run git $(sanitize_printable "$first" 'that subcommand') directly."
            ;;
        esac
        ;;
    esac
    return 0
  fi
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
# GP_LONG (space-joined long names seen, `name=value` when given), GP_SHORT
# (short flag chars seen). Returns 1 with GP_ERR when a flag cannot be read.
parse_git_opts() {
  local k=$1 vlong=" $2 " vshort=$3 ovshort=$4 n=${#SW[@]} w name endopts=0 b c
  GP_POS=()
  GP_POSL=()
  GP_LONG=' '
  GP_SHORT=''
  GP_VALS=()
  GP_ERR=''
  while [ "$k" -lt "$n" ]; do
    w=${SW[$k]}
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
        GP_LONG="$GP_LONG${name#--}=${w#*=} "
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
            GP_LONG="$GP_LONG$name=${SW[$k]} "
            ;;
          *" $name"*)
            GP_ERR="--$name abbreviates an option that takes a value"
            return 1
            ;;
          *) GP_LONG="$GP_LONG$name " ;;
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

long_seen() { # <name> — 0 when GP_LONG carries the option, valued or not
  case $GP_LONG in
    *" $1 "* | *" $1="*) return 0 ;;
  esac
  return 1
}

long_val() { # <name> — the last value given
  local rest=$GP_LONG v=''
  while :; do
    case $rest in
      *" $1="*)
        rest=${rest#*" $1="}
        v=${rest%% *}
        ;;
      *) break ;;
    esac
  done
  printf '%s' "$v"
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

tower_refuses() { # <what>
  if [ "$TIER" = tower ]; then
    deny_now "$1 is denied to the tower under every policy value; the tower never merges into a branch or rewrites history."
    return 0
  fi
  return 1
}

MERGE_VLONG='message file strategy strategy-option into-name cleanup'
classify_git_merge() {
  local k=$1 dir=$2 dir_ok=$3
  parse_git_opts "$k" "$MERGE_VLONG" 'mFsX' 'S' \
    || {
      tower_refuses 'git merge' || deny_now "this git merge carries an option the guard cannot read ($GP_ERR) - refusing (fail closed). Spell its options in full."
      return 0
    }
  if long_seen abort || long_seen continue || long_seen quit; then
    return 0
  fi
  tower_refuses 'git merge' && return 0
  need_dir "$dir_ok" 'this git merge' || return 0
  all_literal || {
    deny_now 'this git merge names its source through an expansion the guard cannot read - refusing (fail closed). Name the PR base literally (origin/main).'
    return 0
  }
  PENDING[${#PENDING[@]}]="merge$TAB$dir$TAB${GP_POS[*]-}"
}

PULL_VLONG='strategy strategy-option depth deepen shallow-since shallow-exclude upload-pack server-option negotiation-tip jobs refmap cleanup'
classify_git_pull() {
  local k=$1 dir=$2 dir_ok=$3 mode=''
  parse_git_opts "$k" "$PULL_VLONG" 'sXoj' 'S' \
    || {
      tower_refuses 'git pull' || deny_now "this git pull carries an option the guard cannot read ($GP_ERR) - refusing (fail closed). Spell its options in full."
      return 0
    }
  tower_refuses 'git pull' && return 0
  need_dir "$dir_ok" 'this git pull' || return 0
  all_literal || {
    deny_now 'this git pull names its source through an expansion the guard cannot read - refusing (fail closed). Name the PR base literally (git pull origin main).'
    return 0
  }
  case $GP_SHORT in *r*) mode=rebase ;; esac
  if long_seen rebase; then
    case $(lower "$(long_val rebase)") in
      false | no | off | 0) mode=merge ;;
      *) mode=rebase ;;
    esac
  fi
  long_seen no-rebase && mode=merge
  PENDING[${#PENDING[@]}]="pull$TAB$dir$TAB$mode$TAB${GP_POS[*]-}"
}

REBASE_VLONG='onto strategy strategy-option exec'
classify_git_rebase() {
  local k=$1 dir=$2 dir_ok=$3
  parse_git_opts "$k" "$REBASE_VLONG" 'sXx' 'SC' \
    || {
      tower_refuses 'git rebase' || deny_now "this git rebase carries an option the guard cannot read ($GP_ERR) - refusing (fail closed). Spell its options in full."
      return 0
    }
  local o
  for o in continue abort skip quit edit-todo show-current-patch; do
    long_seen "$o" && return 0
  done
  tower_refuses 'git rebase' && return 0
  need_dir "$dir_ok" 'this git rebase' || return 0
  all_literal || {
    deny_now 'this git rebase names a revision through an expansion the guard cannot read - refusing (fail closed). Write it literally.'
    return 0
  }
  local root=0 ur=0
  long_seen root && root=1
  long_seen update-refs && ur=1
  long_seen no-update-refs && ur=-1
  PENDING[${#PENDING[@]}]="rebase$TAB$dir$TAB$root$TAB$ur$TAB${GP_POS[*]-}"
}

COMMIT_VLONG=' message file reuse-message reedit-message author date template cleanup trailer pathspec-from-file '
classify_git_commit() {
  local k=$1 dir=$2 dir_ok=$3 n=${#SW[@]} w name v amend=0 targets='' endopts=0 bad=''
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
          esac
        done
        ;;
    esac
    k=$((k + 1))
  done
  [ "$amend" = 1 ] || [ -n "$targets" ] || return 0
  tower_refuses 'amending, squashing, or fixing up a commit' && return 0
  if [ -n "$bad" ]; then
    deny_now "this git commit rewrites history and $bad - refusing (fail closed). Spell its options in full with literal values."
    return 0
  fi
  need_dir "$dir_ok" 'this history rewrite' || return 0
  local t
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
        deny_now 'this git push carries the matching refspec (:), which pushes every branch the remote shares, main included - refusing.'
        return 0
        ;;
    esac
    refs[${#refs[@]}]=$r
    i=$((i + 1))
  done
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
      pull) eval_pull "$rest" ;;
      rebase) eval_rebase "$rest" ;;
      commit) eval_commit "$rest" ;;
      push) eval_push "$rest" ;;
    esac
  done
}

eval_flip() {
  local dir=$1
  [ "$dir" != "$MCP_DIR_SENTINEL" ] || dir=$PAYLOAD_CWD
  [ -d "$dir" ] || dir=/
  read_knob ready_flip_policy "$dir" human unit-owner
  case $KNOB_VAL in
    unit-owner) return 0 ;;
    *) emit_deny 'ready_flip_policy is human, so only a person marks a task pull request ready; leave it a draft and name it in your handoff.' ;;
  esac
}

base_merge_allowed() { # <dir> <what>
  read_knob worker_base_merge "$1" allow deny
  [ "$KNOB_VAL" = allow ] \
    || emit_deny "worker_base_merge is deny, so $2 is refused; the operator syncs this branch with its base."
  need_timeout
  on_unit_branch "$1" "$2"
  base_of "$1"
}

eval_merge() {
  local dir=${1%%"$TAB"*} srcs=${1#*"$TAB"} s
  base_merge_allowed "$dir" 'this git merge'
  if [ -z "$srcs" ]; then
    upstream_of "$dir" "$CUR_BRANCH"
    [ "$UP_REMOTE" = "$BASE_REMOTE" ] && [ "$UP_BRANCH" = "$BASE_BRANCH" ] \
      || emit_deny "this git merge names no source, so git merges the branch's upstream, which is not the PR base ($(sanitize_printable "$BASE_REMOTE/$BASE_BRANCH" 'the base')) - refusing. Name the base: git merge $(sanitize_printable "$BASE_REMOTE/$BASE_BRANCH" 'origin/main')."
    return 0
  fi
  for s in $srcs; do
    is_base_ref "$dir" "$s" \
      || emit_deny "a worker merges only the PR base ($(sanitize_printable "$BASE_REMOTE/$BASE_BRANCH" 'the base')) into its own branch, and this merge names $(sanitize_printable "$s" 'another source') - refusing. Use scripts/converge-sync-main.sh, or git merge $(sanitize_printable "$BASE_REMOTE/$BASE_BRANCH" 'origin/main')."
  done
}

eval_pull() {
  local dir=${1%%"$TAB"*} rest=${1#*"$TAB"} mode remote='' ref='' a i=0
  mode=${rest%%"$TAB"*}
  rest=${rest#*"$TAB"}
  # shellcheck disable=SC2086 # the positionals, split on purpose
  set -- $rest
  remote=${1:-}
  [ "$#" -le 2 ] \
    || emit_deny 'this git pull names more than one refspec - refusing. Pull the PR base alone: git pull origin main.'
  ref=${2:-}
  need_timeout
  if [ -z "$mode" ]; then
    local cb rb pr
    cb=$(current_branch "$dir")
    rb=$(gitq "$dir" config --get "branch.$cb.rebase") || rb=''
    pr=$(gitq "$dir" config --get pull.rebase) || pr=''
    case $(lower "${rb:-$pr}") in
      '' | false | no | off | 0) mode=merge ;;
      *) mode=rebase ;;
    esac
  fi
  if [ "$mode" = rebase ]; then
    read_knob unpushed_rewrite "$dir" allow deny
    [ "$KNOB_VAL" = allow ] \
      || emit_deny 'unpushed_rewrite is deny, so a rebasing git pull is refused. Pull without --rebase, or run scripts/converge-sync-main.sh.'
    on_unit_branch "$dir" 'this rebasing git pull'
    local upref
    if [ -z "$remote" ]; then
      upstream_of "$dir" "$CUR_BRANCH"
      upref="refs/remotes/$UP_REMOTE/$UP_BRANCH"
      [ -n "$UP_BRANCH" ] || emit_deny 'this rebasing git pull has no upstream to rebase onto - refusing (fail closed).'
    else
      [ -n "$ref" ] || emit_deny 'this rebasing git pull names a remote and no branch, which the guard does not resolve - refusing. Name the branch.'
      upref="refs/remotes/$remote/${ref#refs/heads/}"
    fi
    valid_rev "${upref#refs/}" || emit_deny 'this rebasing git pull names a source the guard will not read - refusing (fail closed).'
    refresh_and_check_unpushed "$dir" 'this rebasing git pull' "$upref..HEAD"
    return 0
  fi
  base_merge_allowed "$dir" 'this git pull'
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
  [ "$remote" = "$BASE_REMOTE" ] && [ "$ref" = "$BASE_BRANCH" ] \
    || emit_deny "a worker pulls only the PR base ($(sanitize_printable "$BASE_REMOTE $BASE_BRANCH" 'the base')) into its own branch, and this pull takes $(sanitize_printable "${remote:-no remote} ${ref:-no branch}" 'another source') - refusing. Use git pull $(sanitize_printable "$BASE_REMOTE $BASE_BRANCH" 'origin main'), or scripts/converge-sync-main.sh."
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
  if [ -z "$up" ]; then
    upstream_of "$dir" "$CUR_BRANCH"
    [ -n "$UP_BRANCH" ] || emit_deny 'this git rebase names no upstream and the branch has none configured - refusing (fail closed).'
    up="refs/remotes/$UP_REMOTE/$UP_BRANCH"
  fi
  valid_rev "$up" || emit_deny "this git rebase names an upstream the guard will not read ($(sanitize_printable "$up" 'unprintable')) - refusing (fail closed)."
  local oid
  oid=$(resolve_commit "$dir" "$up")
  [ -n "$oid" ] || emit_deny "this git rebase names an upstream that does not resolve to a commit ($(sanitize_printable "$up" 'unprintable')) - refusing (fail closed)."
  refresh_and_check_unpushed "$dir" 'this git rebase' "$oid..HEAD"
}

eval_commit() {
  local dir=${1%%"$TAB"*} targets=${1#*"$TAB"} t oid head
  rewrite_allowed "$dir" 'this history rewrite'
  head=$(resolve_commit "$dir" HEAD)
  [ -n "$head" ] || emit_deny 'this history rewrite runs where HEAD does not resolve - refusing (fail closed).'
  local ranges=()
  for t in $targets; do
    oid=$(resolve_commit "$dir" "$t")
    [ -n "$oid" ] || emit_deny "this history rewrite names a commit that does not resolve ($(sanitize_printable "$t" 'unprintable')) - refusing (fail closed)."
    gitq "$dir" merge-base --is-ancestor "$oid" "$head" \
      || emit_deny "this history rewrite names a commit that is not on this branch ($(sanitize_printable "$t" 'unprintable')) - refusing."
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
      *[!A-Za-z0-9._-]*) ;;
      *)
        rp=$(gitq "$dir" config --get-all "remote.$remote.push") || rp=''
        [ -z "$rp" ] \
          || emit_deny 'this git push names no branch and the remote carries a configured push refspec, which the guard does not read - refusing (fail closed). Name the branch.'
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
  local surface=${2:-infer} input read_ok=1 tool
  case $TIER in
    worker | tower) ;;
    *)
      # A session with no tier profile: outside jurisdiction, no read at all.
      return 0
      ;;
  esac
  case $surface in bash | mcp) ;; *) surface=infer ;; esac
  KNOB_T=$(bound_secs "${PLANWRIGHT_POLICY_GUARD_TIMEOUT:-}" 5)
  FETCH_T=$(bound_secs "${PLANWRIGHT_POLICY_GUARD_FETCH_TIMEOUT:-}" 20)

  input=$(head -c "$((MAX_PAYLOAD_BYTES + 1))" 2>/dev/null) || read_ok=0
  [ "$read_ok" = 1 ] || return 0
  if [ "${#input}" -gt "$MAX_PAYLOAD_BYTES" ]; then
    emit_deny 'the PreToolUse payload is larger than this guard reads - refusing (fail closed). Issue the command on its own.'
  fi
  if ! command -v jq >/dev/null 2>&1; then
    { [ "$surface" = mcp ] || raw_evidence "$input"; } && emit_deny_constant
    return 0
  fi
  if [ -z "$input" ]; then
    emit_deny 'the PreToolUse payload was empty - refusing (fail closed). This is a hook-contract violation; report it.'
  fi
  # One jq call for every field the guard reads, NUL-separated: it runs on
  # every Bash call a tier session makes. A NUL inside a value is dropped (no
  # shell argument can carry one).
  tool='' P_CMD_OK=0 P_CMD='' P_CWD_TYPE=absent P_CWD=''
  {
    IFS= read -r -d '' tool
    IFS= read -r -d '' P_CMD_OK
    IFS= read -r -d '' P_CMD
    IFS= read -r -d '' P_CWD_TYPE
    IFS= read -r -d '' P_CWD
  } < <(printf '%s' "$input" | jq -j '
    def clean: if type == "string" then gsub("\u0000"; "") else "" end;
    [ (.tool_name | clean),
      (if (.tool_input.command | type) == "string" then "1" else "0" end),
      (.tool_input.command | clean),
      (if has("cwd") and .cwd != null then (.cwd | type) else "absent" end),
      (.cwd | clean)
    ] | map(. + "\u0000") | add' 2>/dev/null)
  if [ -z "$tool" ]; then
    [ "$surface" != mcp ] \
      || emit_deny 'this update_pull_request payload could not be parsed, so the guard cannot tell whether it flips or re-drafts a PR - refusing (fail closed).'
    raw_evidence "$input" \
      && emit_deny 'the PreToolUse payload could not be parsed and its raw content names a reserved act - refusing (fail closed).'
    return 0
  fi
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
    to-draft) emit_deny 'this update_pull_request call re-drafts a pull request; re-drafting is reserved to the corrective helper. Ask the operator.' ;;
    to-ready)
      queue_flip "$MCP_DIR_SENTINEL" 1
      [ -z "$DENY_NOW" ] || emit_deny "$DENY_NOW"
      eval_pending
      ;;
    *) emit_deny 'this update_pull_request payload is malformed, so the guard cannot tell whether it flips or re-drafts a PR - refusing (fail closed).' ;;
  esac
}

handle_bash() {
  local cmd=$P_CMD stripped
  if [ "$P_CMD_OK" != 1 ] || [ -z "$cmd" ]; then
    raw_evidence "$1" && emit_deny 'this Bash payload carries no readable command string and its raw content names a reserved act - refusing (fail closed).'
    return 0
  fi
  # No git and no gh anywhere: nothing this guard classifies, so no parse and
  # no read.
  case $cmd in
    *git* | *gh*) ;;
    *) return 0 ;;
  esac
  case $P_CWD_TYPE in
    absent) PAYLOAD_CWD=$PWD ;;
    string)
      PAYLOAD_CWD=$P_CWD
      [ -n "$PAYLOAD_CWD" ] || PAYLOAD_CWD=$PWD
      ;;
    *)
      raw_evidence "$cmd" && emit_deny 'this Bash payload carries a malformed cwd and its command names a reserved act - refusing (fail closed).'
      return 0
      ;;
  esac
  if [ "${#cmd}" -gt "$MAX_CMD_LEN" ]; then
    stripped=$(strip_heredoc_bodies "$cmd")
    raw_evidence "$stripped" && deny_unanalyzable 'this command is too long for the guard to analyze'
    return 0
  fi
  if ! tokenize "$cmd"; then
    stripped=$(strip_heredoc_bodies "$cmd")
    raw_evidence "$stripped" \
      && deny_unanalyzable 'this command uses a construct the guard will not analyze (command or process substitution, backticks, ANSI-C quoting, or grouping)'
    return 0
  fi
  classify_segments
  [ -z "$DENY_NOW" ] || emit_deny "$DENY_NOW"
  [ "${#PENDING[@]}" = 0 ] && return 0
  need_timeout
  eval_pending
}

trap 'exit 0' HUP INT TERM PIPE

main "$@"
exit 0
