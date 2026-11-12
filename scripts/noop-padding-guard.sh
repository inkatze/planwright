#!/usr/bin/env bash
# noop-padding-guard.sh — the PreToolUse hook that refuses a worker's Bash
# command carrying no-op padding: a segment that does nothing, apparently
# written to change how the command is classified, or a shared fixed name
# under /tmp.
#
# Usage: noop-padding-guard.sh < <PreToolUse payload>
# Output: a permissionDecision "deny" with a plain reason naming the shape and
#   the allowed alternative, or nothing (defer).
# Exit: 0 always. Bash 3.2 compatible; jq reads the payload.
#
# Posture: worker-command-guard.sh is allow-only, so this is a separate,
# deny-emitting hook like background-job-guard.sh, wired beside it. Every
# shape here is a pure no-op (or a shared name) with a mechanical alternative,
# so refusing fits better than deferring: a deferred call reaches the
# supervisor, which is exactly the hand-denial this hook replaces. The reason
# is fixed text per shape and never reflects the command.
#
# False refusals are the failure to avoid, so the analysis is conservative: the
# command is split into segments quote- and heredoc-aware, and a construct the
# splitter does not follow (a subshell, a backtick, a substitution inside
# double quotes, an unterminated quote) defers the whole command. Text inside
# quotes, heredoc bodies and substitutions is never read as a command.
# shellcheck disable=SC1003
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

MAX_LEN=8192

# Token stream, filled by tokenize: type W (word), O (control operator), R
# (redirect operator; the next W is its target).
TN=0
TT=()
TV=()
TQ=()
EMPTY_HEREDOC=0
HD_N=0
HD_DELIM=()
HD_TABS=()
CMD=''
REASON=''

tk_add() {
  TT[TN]=$1
  TV[TN]=$2
  TQ[TN]=${3:-0}
  TN=$((TN + 1))
}

# sub_end <i>: the index just past the balanced `)` of the `(` at index i-1,
# skipping quoted runs, in SUB_END; non-zero when unbalanced.
SUB_END=0
sub_end() {
  local i=$1 depth=1 c k rest
  while [ "$i" -lt "${#CMD}" ]; do
    c=${CMD:i:1}
    case $c in
      "'")
        rest=${CMD:i+1}
        case $rest in
          *"'"*)
            k=${rest%%"'"*}
            i=$((i + ${#k} + 2))
            ;;
          *) return 1 ;;
        esac
        continue
        ;;
      '"')
        i=$((i + 1))
        while [ "$i" -lt "${#CMD}" ] && [ "${CMD:i:1}" != '"' ]; do
          [ "${CMD:i:1}" != '\' ] || i=$((i + 1))
          i=$((i + 1))
        done
        [ "$i" -lt "${#CMD}" ] || return 1
        ;;
      '\') i=$((i + 1)) ;;
      '(') depth=$((depth + 1)) ;;
      ')')
        depth=$((depth - 1))
        if [ "$depth" -eq 0 ]; then
          SUB_END=$((i + 1))
          return 0
        fi
        ;;
    esac
    i=$((i + 1))
  done
  return 1
}

# heredoc_bodies <i>: consume the pending heredoc bodies starting at index i
# (just past a newline), in SUB_END; flags an empty body.
heredoc_bodies() {
  local i=$1 h line rest body found
  h=0
  while [ "$h" -lt "$HD_N" ]; do
    body=0
    found=0
    while [ "$i" -lt "${#CMD}" ]; do
      rest=${CMD:i}
      line=${rest%%$'\n'*}
      i=$((i + ${#line} + 1))
      [ "${HD_TABS[h]}" = 0 ] || line=${line#"${line%%[!$'\t']*}"}
      if [ "$line" = "${HD_DELIM[h]}" ]; then
        found=1
        break
      fi
      case $line in
        *[![:space:]]*) body=1 ;;
      esac
    done
    [ "$found" = 1 ] || { [ "$body" = 0 ] || return 1; }
    [ "$body" = 1 ] || EMPTY_HEREDOC=1
    h=$((h + 1))
  done
  HD_N=0
  SUB_END=$i
  return 0
}

# tokenize: fill the stream from CMD; non-zero defers the whole command.
tokenize() {
  local n=${#CMD} i=0 c nx w='' q=0 st=0 fd op j d dq dtabs t
  flush() {
    [ "$st" = 1 ] || return 0
    tk_add W "$w" "$q"
    w='' q=0 st=0
  }
  while [ "$i" -lt "$n" ]; do
    c=${CMD:i:1}
    case $c in
      "'")
        t=${CMD:i+1}
        case $t in
          *"'"*) ;;
          *) return 1 ;;
        esac
        d=${t%%"'"*}
        w=$w$d
        st=1 q=1
        i=$((i + ${#d} + 2))
        ;;
      '"')
        i=$((i + 1))
        st=1 q=1
        while :; do
          [ "$i" -lt "$n" ] || return 1
          c=${CMD:i:1}
          case $c in
            '"') break ;;
            '`') return 1 ;;
            '$')
              [ "${CMD:i+1:1}" != '(' ] || return 1
              w=$w$c
              ;;
            '\')
              nx=${CMD:i+1:1}
              case $nx in
                '"' | '\' | '$' | '`') w=$w$nx ;;
                *) w=$w$c$nx ;;
              esac
              i=$((i + 1))
              ;;
            *) w=$w$c ;;
          esac
          i=$((i + 1))
        done
        i=$((i + 1))
        ;;
      '\')
        nx=${CMD:i+1:1}
        { [ -n "$nx" ] && [ "$nx" != $'\n' ]; } || return 1
        w=$w$nx
        st=1 q=1
        i=$((i + 2))
        ;;
      ' ' | $'\t')
        flush
        i=$((i + 1))
        ;;
      $'\n')
        flush
        tk_add O NL
        i=$((i + 1))
        if [ "$HD_N" -gt 0 ]; then
          heredoc_bodies "$i" || return 1
          i=$SUB_END
        fi
        ;;
      '#')
        if [ "$st" = 0 ]; then
          t=${CMD:i}
          d=${t%%$'\n'*}
          i=$((i + ${#d}))
        else
          w=$w$c
          i=$((i + 1))
        fi
        ;;
      ';')
        flush
        if [ "${CMD:i+1:1}" = ';' ]; then
          tk_add O ';;'
          i=$((i + 2))
        else
          tk_add O ';'
          i=$((i + 1))
        fi
        ;;
      '|')
        flush
        case ${CMD:i+1:1} in
          '|')
            tk_add O '||'
            i=$((i + 2))
            ;;
          '&') return 1 ;;
          *)
            tk_add O '|'
            i=$((i + 1))
            ;;
        esac
        ;;
      '&')
        case ${CMD:i+1:1} in
          '&')
            flush
            tk_add O '&&'
            i=$((i + 2))
            ;;
          '>')
            flush
            if [ "${CMD:i+2:1}" = '>' ]; then
              tk_add R '&>>'
              i=$((i + 3))
            else
              tk_add R '&>'
              i=$((i + 2))
            fi
            ;;
          *)
            flush
            tk_add O '&'
            i=$((i + 1))
            ;;
        esac
        ;;
      '<' | '>')
        nx=${CMD:i+1:1}
        if [ "$nx" = '(' ]; then
          sub_end $((i + 2)) || return 1
          w=$w${CMD:i:SUB_END-i}
          st=1
          i=$SUB_END
          continue
        fi
        fd=''
        if [ "$st" = 1 ] && [ "$q" = 0 ] && [[ $w =~ ^[0-9]+$ ]]; then
          fd=$w
          w='' st=0
        else
          flush
        fi
        op=$c
        j=$((i + 1))
        if [ "$c" = '>' ]; then
          case $nx in
            '>' | '&' | '|')
              op=$c$nx
              j=$((j + 1))
              ;;
          esac
        else
          case $nx in
            '<')
              if [ "${CMD:i+2:1}" = '<' ]; then
                op='<<<'
                j=$((i + 3))
              elif [ "${CMD:i+2:1}" = '-' ]; then
                op='<<-'
                j=$((i + 3))
              else
                op='<<'
                j=$((i + 2))
              fi
              ;;
            '&' | '>')
              op=$c$nx
              j=$((j + 1))
              ;;
          esac
        fi
        tk_add R "$fd$op"
        i=$j
        if [ "$op" = '<<' ] || [ "$op" = '<<-' ]; then
          dtabs=0
          [ "$op" = '<<' ] || dtabs=1
          while [ "${CMD:i:1}" = ' ' ] || [ "${CMD:i:1}" = $'\t' ]; do
            i=$((i + 1))
          done
          dq=''
          while [ "$i" -lt "$n" ]; do
            c=${CMD:i:1}
            case $c in
              ' ' | $'\t' | $'\n' | ';' | '&' | '|' | '<' | '>' | '(' | ')') break ;;
              "'")
                t=${CMD:i+1}
                case $t in
                  *"'"*) ;;
                  *) return 1 ;;
                esac
                d=${t%%"'"*}
                dq=$dq$d
                i=$((i + ${#d} + 2))
                continue
                ;;
              '"')
                t=${CMD:i+1}
                case $t in
                  *'"'*) ;;
                  *) return 1 ;;
                esac
                d=${t%%'"'*}
                dq=$dq$d
                i=$((i + ${#d} + 2))
                continue
                ;;
              '\')
                dq=$dq${CMD:i+1:1}
                i=$((i + 2))
                continue
                ;;
              *) dq=$dq$c ;;
            esac
            i=$((i + 1))
          done
          [ -n "$dq" ] || return 1
          HD_DELIM[HD_N]=$dq
          HD_TABS[HD_N]=$dtabs
          HD_N=$((HD_N + 1))
          tk_add W "$dq" 1
        fi
        ;;
      '(')
        if [ "$st" = 1 ] && [ "$q" = 0 ] && [ "${CMD:i+1:1}" = ')' ] && [[ $w =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
          w=$w'()'
          i=$((i + 2))
        else
          return 1
        fi
        ;;
      ')') return 1 ;;
      '`') return 1 ;;
      '$')
        if [ "${CMD:i+1:1}" = '(' ]; then
          sub_end $((i + 2)) || return 1
          w=$w${CMD:i:SUB_END-i}
          st=1
          i=$SUB_END
        else
          w=$w$c
          st=1
          i=$((i + 1))
        fi
        ;;
      *)
        w=$w$c
        st=1
        i=$((i + 1))
        ;;
    esac
  done
  flush
  [ "$HD_N" -eq 0 ] || EMPTY_HEREDOC=1
  return 0
}

# tmp_fixed_name <word>: succeeds when the word names a fixed, shared path
# directly under /tmp (not a mktemp template or result, a variable, the
# session's own TMPDIR, or the harness's own task directory).
tmp_fixed_name() {
  local p=$1 name base
  case $p in
    /tmp/?*) ;;
    *) return 1 ;;
  esac
  name=${p#/tmp/}
  name=${name%%/*}
  case $name in
    claude-* | '$'*) return 1 ;;
  esac
  [[ $name =~ ^tmp\.[A-Za-z0-9]{6,}$ ]] && return 1
  [[ $name =~ X{3,}$ ]] && return 1
  base=${TMPDIR:-}
  if [ -n "$base" ]; then
    base=${base%/}
    case $p in
      "$base" | "$base"/*) return 1 ;;
    esac
  fi
  return 0
}

DEVNULL_REASON='a redirect to, or read of, /dev/null does nothing for the command. Send output you do not need to a file in your own mktemp -d scratch directory, or drop the redirect'
TMP_REASON='a fixed or shared name under /tmp is raced and clobbered by other sessions. Use a file inside your own scratch directory from mktemp -d, and use full paths'
MKTEMP_REASON='mktemp -u only names a shared path without creating it. Use mktemp -d for your own scratch directory, and write files inside it'
HEAD_REASON='head with a count of zero prints nothing. Remove it'

# check_segment <prev-op> <next-op>: sets REASON and returns 0 on a shape.
SW=()
SQ=()
SN=0
RO=()
RT=()
RN=0
PREV_VERB=''
PREV_ARGS=''
check_segment() {
  local prev=$1 next=$2 k=0 verb='' res='' i w a pa has_out has_in
  local -a AW=() AQ=()
  local an=0
  # Leading assignments, then reserved words and prefixes, then the verb.
  while [ "$k" -lt "$SN" ] && [[ ${SW[k]} =~ ^[A-Za-z_][A-Za-z0-9_]*\+?= ]] && [ "${SQ[k]}" = 0 ]; do
    k=$((k + 1))
  done
  while [ "$k" -lt "$SN" ]; do
    case ${SW[k]} in
      if | then | elif | else | do | while | until | '!' | '{')
        res=${SW[k]}
        k=$((k + 1))
        ;;
      time) k=$((k + 1)) ;;
      *) break ;;
    esac
  done
  if [ "$k" -lt "$SN" ]; then
    verb=${SW[k]}
    k=$((k + 1))
  fi
  while [ "$k" -lt "$SN" ]; do
    AW[an]=${SW[k]}
    AQ[an]=${SQ[k]}
    an=$((an + 1))
    k=$((k + 1))
  done

  has_out=0
  has_in=0
  i=0
  while [ "$i" -lt "$RN" ]; do
    case ${RO[i]} in
      *'<' | *'<<-' | *'<&') has_in=1 ;;
      *) has_out=1 ;;
    esac
    case ${RO[i]} in
      *'<<' | *'<<-') ;;
      *)
        if [ "${RT[i]:-}" = /dev/null ]; then
          REASON=$DEVNULL_REASON
          return 0
        fi
        ;;
    esac
    i=$((i + 1))
  done

  # An unquoted /dev/null argument: a read of, or write to, nothing.
  case $verb in
    git | cp | mv | install | ln | ls | stat | file | test | '[' | '[[' | readlink | realpath | echo | printf | '') ;;
    *)
      i=0
      while [ "$i" -lt "$an" ]; do
        if [ "${AW[i]}" = /dev/null ] && [ "${AQ[i]}" = 0 ]; then
          REASON=$DEVNULL_REASON
          return 0
        fi
        i=$((i + 1))
      done
      ;;
  esac

  # Fixed or shared names directly under /tmp, and a mktemp that only names.
  i=0
  while [ "$i" -lt "$SN" ]; do
    w=${SW[i]}
    if tmp_fixed_name "$w" || { [[ $w == *=* ]] && tmp_fixed_name "${w#*=}"; }; then
      REASON=$TMP_REASON
      return 0
    fi
    if [ "${SQ[i]}" = 0 ] && [[ $w =~ mktemp[[:space:]]+(-[A-Za-z]*u|--dry-run) ]]; then
      REASON=$MKTEMP_REASON
      return 0
    fi
    i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "$RN" ]; do
    if tmp_fixed_name "${RT[i]:-}"; then
      REASON=$TMP_REASON
      return 0
    fi
    i=$((i + 1))
  done
  if [ "$verb" = mktemp ]; then
    for ((i = 0; i < an; i++)); do
      case ${AW[i]} in
        --dry-run | -*u*)
          REASON=$MKTEMP_REASON
          return 0
          ;;
      esac
    done
  fi

  [ -n "$verb" ] || return 1

  case $verb in
    true | :)
      if [ -z "$res" ] && [ "$an" -eq 0 ] && [ "$RN" -eq 0 ]; then
        REASON='true or : as a step (including || true) does nothing. Remove it; handle a failing command by reading its exit status'
        return 0
      fi
      ;;
    echo)
      if [ "$RN" -eq 0 ] && [ "$next" != '|' ]; then
        if [ "$an" -eq 0 ]; then
          REASON='a bare echo prints a blank line and nothing else. Remove it'
          return 0
        fi
        if [ "$an" -eq 1 ]; then
          case ${AW[0]} in
            ok | OK | done | DONE | skip | SKIP)
              REASON='echo ok, done or skip is filler. Remove it; the command output and exit status already say so'
              return 0
              ;;
          esac
        fi
      fi
      ;;
  esac
  case $verb in
    echo | printf)
      if [ "$an" -eq 1 ] && [ "$has_out" = 1 ]; then
        case ${AW[0]} in
          placeholder | dummy)
            REASON='writing placeholder text to a file does nothing useful. Write the real content, or do not create the file'
            return 0
            ;;
        esac
      fi
      ;;
    cat)
      if [ "$an" -eq 0 ] && [ "$has_in" = 0 ] && [ "$prev" != '|' ] && [ "$has_out" = 1 ]; then
        REASON='cat with no input reads the terminal and writes nothing. Give it the file to read, or use the Write tool'
        return 0
      fi
      if [ "$an" -eq 0 ] && [ "$RN" -eq 0 ] && [ "$prev" = '|' ]; then
        REASON='a pass-through | cat stage changes nothing. Remove it'
        return 0
      fi
      if [ "$an" -eq 1 ] && [ "$RN" -eq 0 ] && [ "$next" = '|' ] && [ "$prev" != '|' ]; then
        case ${AW[0]} in
          -*) ;;
          *)
            REASON='cat file | cmd is a pass-through stage. Give the file to the command itself, or redirect it with <file'
            return 0
            ;;
        esac
      fi
      ;;
    cd)
      if [ "$an" -eq 1 ]; then
        case ${AW[0]} in
          . | ./)
            REASON='cd . stays where it is. Remove it, and use full paths instead of cd'
            return 0
            ;;
          -)
            if [ "$PREV_VERB" = cd ] && [ "$prev" != '|' ]; then
              REASON='cd X followed straight by cd - does nothing. Remove both, and use full paths instead of cd'
              return 0
            fi
            ;;
        esac
        if [ "$PREV_VERB" = cd ] && [ "$prev" = '||' ] && [ "$PREV_ARGS" = "${AW[0]}" ]; then
          REASON='cd X || cd X repeats itself. Remove the second cd, and use full paths instead of cd'
          return 0
        fi
      fi
      ;;
    head)
      pa=''
      for ((i = 0; i < an; i++)); do
        a=${AW[i]}
        if [[ $a =~ ^-[nc]?0+$ ]] || { [ -n "$pa" ] && [[ $a =~ ^0+$ ]]; }; then
          REASON=$HEAD_REASON
          return 0
        fi
        case $a in
          -n | -c) pa=$a ;;
          *) pa='' ;;
        esac
      done
      ;;
    sed)
      for ((i = 0; i < an; i++)); do
        if [[ ${AW[i]} =~ ^[0-9]*,0p$ ]]; then
          REASON='this sed range selects nothing. Remove it, or give a real range'
          return 0
        fi
      done
      ;;
    python | python3)
      if [ "$an" -eq 2 ] && [ "${AW[0]}" = -c ]; then
        case ${AW[1]} in
          1 | 0 | pass | None | True | False | '')
            REASON='python -c with a constant does nothing. Remove it'
            return 0
            ;;
        esac
      fi
      ;;
  esac
  return 1
}

# analyze: walk the stream segment by segment; REASON is set on a shape.
analyze() {
  local t=0 prev=START sn_prev
  SN=0
  RN=0
  local pend=0
  while [ "$t" -le "$TN" ]; do
    if [ "$t" -lt "$TN" ] && [ "${TT[t]}" != O ]; then
      if [ "${TT[t]}" = R ]; then
        RO[RN]=${TV[t]}
        RT[RN]=''
        RN=$((RN + 1))
        pend=1
      elif [ "$pend" = 1 ]; then
        RT[RN - 1]=${TV[t]}
        pend=0
      else
        SW[SN]=${TV[t]}
        SQ[SN]=${TQ[t]}
        SN=$((SN + 1))
      fi
    else
      sn_prev=${TV[t]:-END}
      if [ "$SN" -gt 0 ] || [ "$RN" -gt 0 ]; then
        if check_segment "$prev" "$sn_prev"; then
          return 0
        fi
        PREV_VERB=''
        PREV_ARGS=''
        if [ "$SN" -gt 0 ]; then
          PREV_VERB=${SW[0]}
          PREV_ARGS=${SW[1]:-}
        fi
      fi
      SN=0
      RN=0
      pend=0
      prev=$sn_prev
    fi
    t=$((t + 1))
  done
  # An empty function: name() { :; } or name() { true; }.
  local i=0 j
  while [ "$i" -lt "$TN" ]; do
    if [ "${TT[i]}" = W ] && [[ ${TV[i]} == *'()' ]] && [ "${TT[i + 1]:-}" = W ] && [ "${TV[i + 1]:-}" = '{' ]; then
      j=$((i + 2))
      while [ "${TT[j]:-}" = O ] && { [ "${TV[j]}" = ';' ] || [ "${TV[j]}" = NL ]; }; do j=$((j + 1)); done
      if [ "${TT[j]:-}" = W ] && { [ "${TV[j]}" = : ] || [ "${TV[j]}" = true ]; }; then
        j=$((j + 1))
        while [ "${TT[j]:-}" = O ] && { [ "${TV[j]}" = ';' ] || [ "${TV[j]}" = NL ]; }; do j=$((j + 1)); done
      fi
      if [ "${TT[j]:-}" = W ] && [ "${TV[j]}" = '}' ]; then
        REASON='an empty function does nothing. Remove it'
        return 0
      fi
    fi
    i=$((i + 1))
  done
  return 1
}

emit_deny() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"planwright noop-padding-guard: '"$1"'."}}'
}

main() {
  local input tool
  command -v jq >/dev/null 2>&1 || return 0
  input=$(head -c 2000000 2>/dev/null) || input=''
  [ -n "$input" ] || return 0
  {
    IFS= read -r -d '' tool && IFS= read -r -d '' CMD
  } < <(printf '%s' "$input" | jq -j -s '
    if length == 1 then .[0] else empty end
    | select((.tool_input.command | type) == "string" and (.tool_input.command | explode | any(. == 0) | not))
    | (.tool_name // "" | if type == "string" then . else "" end) as $t
    | $t, "\u0000", .tool_input.command, "\u0000"
  ' 2>/dev/null) || return 0
  [ "$tool" = Bash ] || return 0
  [ -n "$CMD" ] || return 0
  [ "${#CMD}" -le "$MAX_LEN" ] || return 0
  tokenize || return 0
  [ "$EMPTY_HEREDOC" = 0 ] || {
    emit_deny 'an empty heredoc writes nothing. Give it a body, or use the Write tool'
    return 0
  }
  if analyze; then
    emit_deny "$REASON"
  fi
  return 0
}

main
exit 0
