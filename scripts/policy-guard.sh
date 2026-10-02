#!/usr/bin/env bash
# policy-guard.sh — the deny-emitting PreToolUse hook that enforces the
# human-gates policy knobs for the tier a session runs under
# (doctrine/human-gates.md states the list and each rule's kind).
#
# Usage, as the tier profiles wire it:
#   policy-guard.sh <tier> <surface>
# <tier> is `worker` or `tower`, carried by the settings profile the session
# runs under; any other value, or none, is a session with no tier profile,
# which is outside this guard's jurisdiction, so it defers with no read.
# <surface> is `bash` or `mcp`: which matcher fired, so a payload on the MCP
# matcher that lost its tool_name, or names another tool, still denies. A
# payload that cannot be read denies at every surface.
#
# MODALITY. Like the ready-guard and unlike the allow-only command guards, this
# guard emits deny, so a missed deny defeats it and a false deny blocks work.
# Every refusal names its remedy.
#
# ORDER. The intercepted call is classified first, with no knob read: a call
# that performs none of the acts below defers with no read, and a call no
# value or protected set can change (a force or bulk push, the undo, the PR
# merge, the tower's refusals, a `gh api` act, a request the guard cannot
# read) denies before any read. Only then does the guard read what the matched
# act needs (its knob, the protected set) through
# scripts/resolve-policy-knob.sh, each read bounded by
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
# Every segment of a compound command is classified and the strictest verdict
# wins.
#
# THE UNIT BRANCH. A session owns the branch checked out at its project
# directory (CLAUDE_PROJECT_DIR, which Claude Code sets for every hook), when
# that branch is a task or flight branch. The PR base is the default branch of
# the unit branch's remote as recorded locally (`refs/remotes/<remote>/HEAD`,
# else `main`): the guard never queries the host for it, so a unit whose PR
# targets another branch syncs through scripts/converge-sync-main.sh.
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

raw_evidence_one() {
  local t=$1 rc=1
  # Case-insensitive: a case-insensitive filesystem runs `git REBASE`.
  shopt -s nocasematch
  if [[ $t =~ $RE_GH_API ]] || [[ $t =~ $RE_GH_PR ]] || [[ $t =~ $RE_GIT_ACT ]] \
    || [[ $t =~ $RE_GIT_REWRITE ]] || [[ $t =~ $RE_GIT_COMMIT_SUBST ]]; then
    rc=0
  fi
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
  emit_deny "$1 and its text names a reserved act (a gh api request, a pull-request flip or merge, or a git merge, pull, rebase, push, or history rewrite) - refusing (fail closed). Issue that command on its own as a plain simple command."
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
    "" | -* | /* | */ | *//* | *..* | *[!A-Za-z0-9._/+@-]* | *.lock | *.lock/* | *.) return 1 ;;
    HEAD | @ | .* | */.*) return 1 ;;
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
  v=$(cd -- "$dir" 2>/dev/null && "$TB" -k 2 "$KNOB_B" /bin/sh "$GUARD_DIR/resolve-policy-knob.sh" "$knob" 2>/dev/null </dev/null) || rc=$?
  if [ "$rc" = 124 ]; then
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
  err=$(cd -- "$dir" 2>/dev/null && "$TB" -k 2 "$KNOB_B" /bin/sh "$GUARD_DIR/protected-branch.sh" "$@" 2>&1 >/dev/null </dev/null) || rc=$?
  case $rc in
    0) return 0 ;;
    1)
      emit_deny "$what targets a protected branch ($(sanitize_printable "${err#protected-branch: }" 'a protected branch')); main, master, spec branches, and the protected_branches additions are never written by an agent session at any tier. Work on your own unit branch."
      ;;
    2)
      emit_deny "$what names a branch the protected-set reader refuses as a branch name ($(sanitize_printable "${err#protected-branch: }" 'unprintable')) - refusing (fail closed). Name a valid branch."
      ;;
    124)
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

classify_segments() {
  local si=0 eff=$PAYLOAD_CWD eff_ok=1 verb base_verb prev_text='' cur_text w
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
    lc "${verb##*/}"
    base_verb=$LC
    if [ "${SWL[0]}" != 1 ]; then
      # The command word is an expansion, so what runs cannot be read: only a
      # variable root followed by a literal script path is let through, and
      # even that not when a reserved subcommand follows.
      [[ $verb =~ $RE_ROOTED_SCRIPT ]] \
        || deny_now "this command's name is an expansion the guard cannot read ($(sanitize_printable "$verb" 'unprintable')), so it could be git or gh - refusing (fail closed). Write the command name literally, or as \"\$ROOT/path/to/script\"."
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
    else
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
          ;;
      esac
    fi
    prev_text=$cur_text
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

  case " $GIT_BUILTINS " in
    *" $sub "*) ;;
    *)
      if [ "$GIT_ENV" = 1 ] || [ "$ST_CFG" = 1 ]; then
        deny_now "this git $(sanitize_printable "$sub" 'subcommand') runs where git configuration is set in the same command or its environment (a GIT_* variable, git config, or git remote), so the guard cannot tell what it runs - refusing (fail closed). Run the configuration change and the command separately."
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
  local a pos=0 ro=0
  for a in "${SW[@]:$2}"; do
    case $a in
      --get | --get-all | --get-regexp | --get-urlmatch | --list | -l | --show-current | -v | -vv | show | get-url | list) ro=1 ;;
      -*) ;;
      *) pos=$((pos + 1)) ;;
    esac
  done
  case $1 in
    config) [ "$ro" = 1 ] || [ "$pos" -lt 2 ] || ST_CFG=1 ;;
    remote) [ "$ro" = 1 ] || [ "$pos" = 0 ] || ST_CFG=1 ;;
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
        GP_LONG="$GP_LONG${name#--} "
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

# long_prefix_seen <full-name> <min-length> — 0 when GP_LONG carries an
# option git would read as <full-name>: the name itself or a prefix of it at
# least <min-length> long (git takes any unique prefix of a long option).
long_prefix_seen() {
  local t name
  for t in $GP_LONG; do
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
  if long_prefix_seen abort 2 || long_prefix_seen continue 3 || long_prefix_seen quit 2; then
    return 0
  fi
  tower_refuses 'git merge' && return 0
  act_gate 'this git merge' merge || return 0
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
  PENDING[${#PENDING[@]}]="pull$TAB$dir$TAB$mode$TAB${GP_POS[*]-}"
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
      [ -n "$UP_BRANCH" ] || emit_deny 'this rebasing git pull has no upstream to rebase onto - refusing (fail closed). Name the remote and branch, or push the branch with -u first.'
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
    worker | tower) ;;
    *)
      # A session with no tier profile: outside jurisdiction, no read at all.
      return 0
      ;;
  esac
  case $surface in bash | mcp) ;; *) surface=infer ;; esac
  KNOB_T=$(bound_secs "${PLANWRIGHT_POLICY_GUARD_TIMEOUT:-}" 10)
  FETCH_T=$(bound_secs "${PLANWRIGHT_POLICY_GUARD_FETCH_TIMEOUT:-}" 20)

  input=$(head -c "$((MAX_PAYLOAD_BYTES + 1))" 2>/dev/null) || read_ok=0
  [ "$read_ok" = 1 ] \
    || emit_deny 'the PreToolUse payload could not be read - refusing (fail closed). This is a hook-contract violation; report it.'
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
  if [ -z "$tool" ]; then
    [ "$surface" != mcp ] \
      || emit_deny 'this update_pull_request payload could not be parsed, so the guard cannot tell whether it flips or re-drafts a PR - refusing (fail closed). Use gh pr ready <number> for a flip.'
    raw_evidence "$input" \
      && emit_deny 'the PreToolUse payload could not be parsed and its raw content names a reserved act - refusing (fail closed).'
    return 0
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
    to-draft) emit_deny 'this update_pull_request call re-drafts a pull request; re-drafting is reserved to the corrective helper. Ask the operator.' ;;
    to-ready)
      queue_flip "$MCP_DIR_SENTINEL" 1
      [ -z "$DENY_NOW" ] || emit_deny "$DENY_NOW"
      eval_pending
      ;;
    *) emit_deny 'this update_pull_request payload is malformed, so the guard cannot tell whether it flips or re-drafts a PR - refusing (fail closed). Use gh pr ready <number> for a flip.' ;;
  esac
}

handle_bash() {
  local cmd=$P_CMD
  if [ "$P_CMD_OK" != 1 ] || [ -z "$cmd" ]; then
    raw_evidence "$1" && emit_deny 'this Bash payload carries no readable command string and its raw content names a reserved act - refusing (fail closed).'
    return 0
  fi
  # No git and no gh anywhere, even with quotes and escapes removed, and no
  # expansion beside a reserved subcommand: nothing this guard classifies, so
  # no parse and no read.
  local bare=${cmd//[\"\'\\]/} hit=0
  shopt -s nocasematch
  case $bare in
    *git* | *gh*) hit=1 ;;
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
      PAYLOAD_CWD=$P_CWD
      [ -n "$PAYLOAD_CWD" ] || PAYLOAD_CWD=$PWD
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
    worker | tower) emit_deny_internal ;;
  esac
fi
exit 0
