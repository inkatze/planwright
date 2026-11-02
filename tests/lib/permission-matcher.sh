#!/bin/bash
# permission-matcher.sh — a documented re-implementation of Claude Code's Bash
# permission-rule matcher, used as the test oracle for the deny/allow fixture
# table (guard-coverage Task 1, D-4, REQ-A1.1) and, in
# tests/test-merge-currency-matrix.sh, to show the worker profile's allow entry
# admits a ready-flip the ready-guard hook still denies.
#
# THIS IS A MODEL, NOT THE MATCHER. It encodes the semantics Claude Code's
# permission documentation states, so that a deny-list edit that re-opens a known
# evasion fails CI. The modeled behavior version, the sources consulted, the
# modeling boundaries, and the assumptions that are NOT settled by the
# documentation are all recorded in docs/permission-matcher-model.md — read that
# doc before changing anything here. When Claude Code's matcher changes, the doc
# is where the divergence surfaces (D-4).
#
#   Modeled behavior version: Claude Code CLI 2.1.314 / docs as of 2026-11-01.
#
# Sourced, not executed:  . tests/lib/permission-matcher.sh
# Portable bash 3.2 (no associative arrays, no mapfile); no forks in the hot
# path — patterns are compiled to EREs once and matched with [[ =~ ]].
#
# Public interface
#   pm_load_rules <deny-lines> <ask-lines> <allow-lines>
#         Compile three newline-separated rule lists (as they appear in a
#         settings.json permissions array: `Bash(<pattern>)`, `Read(...)`, a
#         bare tool name, ...). Read/Edit path rules and bare file-tool
#         entries (Read, Edit, Write, NotebookEdit; deny, ask, or allow) are
#         filed for pm_decide_path; other non-Bash rules are ignored. Returns
#         2 if the deny list contains no usable Bash rule.
#   pm_decide <command>
#         Print one of: deny | ask | allow | prompt   (prompt = no rule
#         matched, so the call falls through to the permission prompt).
#   pm_subcommands <command> / pm_deny_subjects <command>
#         Print every subcommand allow rules must match, nested ones included
#         (M9); and that list plus the command's atoms, which deny and ask
#         rules are swept over.
#   pm_decide_path <Read|Edit|Write|NotebookEdit> <absolute-path>
#         The same four outcomes for a file-tool call (M10, M11), anchored at
#         PM_CWD, PM_HOME, and PM_SETTINGS_DIR, read when it is called.
#   pm_path_compile
#         Compile the path rules for the current anchors. A caller deciding
#         inside command substitutions runs it first in its own shell.
#   pm_allow_rule_count / pm_allow_rule_at <i>, pm_path_deny_rule_at <i>,
#   pm_path_deny_match_indices <tool> <path>, pm_path_matches <kind> <pat> <path>
#         Enumeration and predicates for the coverage passes.
#   pm_matching_deny_rule <command>
#         Print the first deny rule (as written) that matches, or nothing.
#   pm_matches <pattern> <command>
#         Low-level single-pattern predicate over a single subcommand; exit 0
#         on match. Used by the model's own self-validation tests.
#   pm_deny_rule_count / pm_deny_rule_at <i>
#         Enumerate the compiled deny rules (for the mutation pass).
set -u
PM_TAB="$(printf '\t')"
PM_NL='
'

# --- pattern compilation -----------------------------------------------------

# pm_glob_to_ere <glob> — escape ERE metacharacters, then map `*` to `.*`.
# Pure bash: this runs once per rule, and the fixture/mutation passes reuse the
# compiled result, so no subprocess ever enters the matching loop.
pm_glob_to_ere() {
  local glob="$1" out="" i c
  i=0
  while [ "$i" -lt "${#glob}" ]; do
    c="${glob:$i:1}"
    case "$c" in
      '*') out="$out.*" ;;
      *)
        pm_ere_char "$c"
        out="$out$PM_CHAR"
        ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# pm_ere_char <char> — set PM_CHAR to the character, backslash-escaped when it
# is an ERE metacharacter (no fork).
pm_ere_char() {
  case "$1" in
    '.' | \\ | '+' | '?' | '*' | '(' | ')' | '[' | ']' | '{' | '}' | '^' | '$' | '|') PM_CHAR="\\$1" ;;
    *) PM_CHAR="$1" ;;
  esac
}

# pm_compile_pattern <pattern> — print the anchored ERE for a Bash rule pattern.
#
# Two documented shapes (see the doc's rules M2/M3/M4):
#   * A trailing `:*` is exactly equivalent to a trailing ` *`, and `:*` is
#     recognized ONLY at the end of a pattern — elsewhere the colon is literal.
#   * A trailing ` *` (space then star) is the word-boundary form: the prefix
#     must be followed by a space or end-of-string. Everything else is a plain
#     whole-command glob, anchored at both ends.
pm_compile_pattern() {
  local pattern="$1" prefix
  case "$pattern" in
    *':*') pattern="${pattern%:\*} *" ;;
  esac
  case "$pattern" in
    *' *')
      prefix="${pattern% \*}"
      printf '^%s( .*)?$' "$(pm_glob_to_ere "$prefix")"
      ;;
    *)
      printf '^%s$' "$(pm_glob_to_ere "$pattern")"
      ;;
  esac
}

# pm_rule_pattern <rule> — print the inner pattern of a `Bash(...)` rule.
#
# Three outcomes, because "not a Bash command rule" and "a broken Bash command
# rule" must not be conflated:
#   0  a well-formed `Bash(<pattern>)` rule; the pattern is printed
#   1  a rule that is not a Bash command rule at all (`Read(...)`, `Edit`, a
#      non-Bash tool name) — it can never match a command, so the caller
#      ignores it
#   3  a rule that names the Bash tool but is not a usable command pattern: a
#      truncated `Bash(...` missing its close paren, or a bare `Bash`
#      tool-name rule whose semantics this model does not implement. Either
#      one, silently skipped, would shrink the rule set the fixture table
#      believes it is asserting against, so the caller fails closed instead.
pm_rule_pattern() {
  local rule="$1" inner
  case "$rule" in
    'Bash('*')')
      inner="${rule#Bash(}"
      printf '%s' "${inner%)}"
      return 0
      ;;
    'Bash' | 'Bash'*) return 3 ;;
  esac
  return 1
}

# --- command decomposition ---------------------------------------------------

# --- the grouping scanner ------------------------------------------------------
#
# The shell's grouping is read with quoting: inside single quotes nothing
# groups; inside double quotes only `$(` and backticks open a nested command,
# and a nested command starts with no quote of its own. PM_Q holds the open
# quote (`s`, `d`, or empty) and PM_STK a stack of two-character frames, each
# the frame's kind (`p` for a parenthesis, `b` for a backtick) and the quote
# it interrupted (`n` for none). pm_scan_step reads the character at an index
# and sets PM_ADV (characters consumed) and PM_EV: `sub` when it opens a
# command or process substitution, `group` when it opens a bare parenthesis,
# `close` when it closes a frame, empty otherwise. No fork.
pm_scan_reset() {
  PM_Q=''
  PM_STK=''
}
pm_scan_push() {
  PM_STK="$PM_STK$1${PM_Q:-n}"
  PM_Q=''
}
pm_scan_pop() {
  PM_Q="${PM_STK:$((${#PM_STK} - 1)):1}"
  [ "$PM_Q" != n ] || PM_Q=''
  PM_STK="${PM_STK%??}"
  PM_EV=close
}
# shellcheck disable=SC2016 # the substitution openers are matched literally
pm_scan_step() {
  local c="${1:$2:1}" two="${1:$2:2}" top=''
  PM_EV=''
  PM_ADV=1
  [ -z "$PM_STK" ] || top="${PM_STK:$((${#PM_STK} - 2)):1}"
  case "$PM_Q" in
    s)
      [ "$c" != "'" ] || PM_Q=''
      return 0
      ;;
    d)
      case "$c" in
        '"') PM_Q='' ;;
        \\) PM_ADV=2 ;;
        '`')
          pm_scan_push b
          PM_EV=sub
          ;;
        '$')
          if [ "$two" = '$(' ]; then
            pm_scan_push p
            PM_EV=sub
            PM_ADV=2
          fi
          ;;
      esac
      return 0
      ;;
  esac
  case "$c" in
    "'") PM_Q=s ;;
    '"') PM_Q=d ;;
    \\) PM_ADV=2 ;;
    '`')
      if [ "$top" = b ]; then
        pm_scan_pop
      else
        pm_scan_push b
        PM_EV=sub
      fi
      ;;
    '$' | '<' | '>')
      case "$two" in
        '$(' | '<(' | '>(')
          pm_scan_push p
          PM_EV=sub
          PM_ADV=2
          ;;
      esac
      ;;
    '(')
      pm_scan_push p
      PM_EV=group
      ;;
    ')') [ "$top" != p ] || pm_scan_pop ;;
  esac
}

# pm_split_command <command> — print each top-level subcommand on its own line.
#
# Claude Code is shell-operator aware: a rule must match each subcommand
# independently. The recognized separators are `&&`, `||`, `;`, `|`, `|&`, `&`,
# and newlines (doc rule M6). Two-character operators are consumed before the
# one-character ones so `&&` is never read as two `&`s. A separator inside
# quotes, parentheses (a subshell, `$(...)`, `<(...)`), or backticks does not
# split at this level: pm_subcommands reaches the nested commands (M9). A
# newline inside one is printed as `;` (as a space inside quotes), so every
# printed subcommand is one line.
#
# A command whose quotes, parentheses, or backticks never close is not read
# for structure at all: its atoms (pm_atoms) are printed, then
# PM_NEST_SENTINEL, which no allow rule matches (doc MB-3).
pm_split_command() {
  local s="$1" out="" cur="" i n two c
  n=${#s}
  i=0
  pm_scan_reset
  while [ "$i" -lt "$n" ]; do
    c="${s:$i:1}"
    if [ -z "$PM_STK" ] && [ -z "$PM_Q" ]; then
      two="${s:$i:2}"
      case "$two" in
        '&&' | '||' | '|&')
          out="$out$cur$PM_NL"
          cur=""
          i=$((i + 2))
          continue
          ;;
      esac
      case "$c" in
        ';' | '|' | '&' | "$PM_NL")
          out="$out$cur$PM_NL"
          cur=""
          i=$((i + 1))
          continue
          ;;
      esac
    fi
    pm_scan_step "$s" "$i"
    c="${s:$i:$PM_ADV}"
    case "$c" in
      *"$PM_NL"*)
        if [ -n "$PM_Q" ]; then c="${c//$PM_NL/ }"; else c="${c//$PM_NL/;}"; fi
        ;;
    esac
    cur="$cur$c"
    i=$((i + PM_ADV))
  done
  if [ -z "$PM_STK" ] && [ -z "$PM_Q" ]; then
    printf '%s%s\n' "$out" "$cur"
  else
    pm_atoms "$s"
    printf '%s\n' "$PM_NEST_SENTINEL"
  fi
}

# pm_atoms <command> — split on every separator and every grouping character
# (`(`, `)`, backtick), ignoring quotes, and print the pieces. A command
# nested anywhere in the text, however it is quoted or grouped, surfaces as
# one of them; pm_decide sweeps them for deny and ask rules (M9).
pm_atoms() {
  local s="$1" cur="" i n two c
  n=${#s}
  i=0
  while [ "$i" -lt "$n" ]; do
    two="${s:$i:2}"
    case "$two" in
      '&&' | '||' | '|&')
        printf '%s\n' "$cur"
        cur=""
        i=$((i + 2))
        continue
        ;;
    esac
    c="${s:$i:1}"
    case "$c" in
      ';' | '|' | '&' | "$PM_NL" | '(' | ')' | '`')
        printf '%s\n' "$cur"
        cur=""
        ;;
      *) cur="$cur$c" ;;
    esac
    i=$((i + 1))
  done
  printf '%s\n' "$cur"
}

# pm_substitutions <subcommand> — print the inner text of each outermost
# `$(...)`, `<(...)`, `>(...)`, and backtick substitution, one per line, read
# with quoting (a `$(` inside single quotes opens nothing). `$((` reads as a
# substitution whose inner text is a group, which can only add a subcommand
# to check.
pm_substitutions() {
  local s="$1" i n start=-1 inner
  n=${#s}
  i=0
  pm_scan_reset
  while [ "$i" -lt "$n" ]; do
    pm_scan_step "$s" "$i"
    if [ "$PM_EV" = sub ] && [ "${#PM_STK}" -eq 2 ]; then
      start=$((i + PM_ADV))
    elif [ "$PM_EV" = close ] && [ -z "$PM_STK" ] && [ "$start" -ge 0 ]; then
      inner="${s:$start:$((i - start))}"
      printf '%s\n' "${inner//$PM_NL/;}"
      start=-1
    fi
    i=$((i + PM_ADV))
  done
  if [ "$start" -ge 0 ]; then
    inner="${s:$start}"
    printf '%s\n' "${inner//$PM_NL/;}"
  fi
}

# pm_group_split <subcommand> — for a subcommand opening with `(`, set PM_G_IN
# to the text inside the group and PM_G_REST to whatever follows its close (a
# redirect, a substitution); the rest of the text is PM_G_IN when the group
# never closes.
pm_group_split() {
  local s="$1" i n
  n=${#s}
  i=0
  pm_scan_reset
  while [ "$i" -lt "$n" ]; do
    pm_scan_step "$s" "$i"
    i=$((i + PM_ADV))
    if [ "$PM_EV" = close ] && [ -z "$PM_STK" ]; then
      PM_G_IN="${s:1:$((i - 2))}"
      PM_G_REST="${s:$i}"
      return 0
    fi
  done
  PM_G_IN="${s:1}"
  PM_G_REST=''
}

# pm_first_word <string> — set PM_WORD to the text before the first space or
# tab (no fork).
pm_first_word() {
  PM_WORD="${1%% *}"
  PM_WORD="${PM_WORD%%"$PM_TAB"*}"
}

# pm_strip_keywords <subcommand> — set PM_KW to the command left once the
# control-flow words that open a body or condition (`do`, `then`, `else`,
# `elif`, `if`, `while`, `until`, `!`, `{`) and a function header (`name()`,
# `name ()`, `name(){`, `function name`) are dropped, so the command inside is
# what the rules see (M9). Returns 1 when nothing is left to read; 2 when the
# text runs no command of its own but may hold a substitution (a
# `for`/`select` head, or a closing word, `done`, `fi`, `esac`, `}`, followed
# by a redirect); and 3 for a `case` statement, whose arms the model does not
# read (MB-7).
pm_strip_keywords() {
  local s="$1" rest
  while :; do
    pm_first_word "$s"
    rest="$(pm_trim "${s#"$PM_WORD"}")"
    case "$PM_WORD" in
      'do' | 'then' | 'else' | 'elif' | 'if' | 'while' | 'until' | '!' | '{' | *'()' | *'(){')
        [ -n "$rest" ] || return 1
        s="$rest"
        ;;
      'function')
        [ -n "$rest" ] || return 1
        pm_first_word "$rest"
        s="$(pm_trim "${rest#"$PM_WORD"}")"
        [ -n "$s" ] || return 1
        ;;
      'case') return 3 ;;
      'done' | 'fi' | 'esac' | '}' | 'for' | 'select')
        [ -n "$rest" ] || return 1
        PM_KW="$rest"
        return 2
        ;;
      *)
        case "$rest" in
          '()'*)
            s="$(pm_trim "${rest#()}")"
            [ -n "$s" ] || return 1
            ;;
          *) break ;;
        esac
        ;;
    esac
  done
  case "$s" in
    *' }') s="$(pm_trim "${s% \}}")" ;;
  esac
  PM_KW="$s"
  [ -n "$s" ] || return 1
  return 0
}

# pm_subcommands <command> — print every simple subcommand the rules are
# matched against, one trimmed line each: the top-level ones, and those
# nested in a subshell, a brace group, a function body, a command or process
# substitution, or a control-flow body, recursively (doc rule M9). A
# subcommand carrying a substitution is printed with it in place, then its
# inner commands follow. Past PM_NEST_MAX levels the unread text is printed as
# PM_NEST_SENTINEL, which no allow rule matches, so an uninspected command can
# never be reported allowed.
PM_NEST_MAX=8
PM_NEST_SENTINEL='#nested-beyond-the-model-depth'
pm_subcommands() { pm_subcommands_at "$1" 0; }
pm_subcommands_at() {
  local s="$1" d="$2" sub inner head rc rest
  if [ "$d" -gt "$PM_NEST_MAX" ]; then
    printf '%s\n' "$PM_NEST_SENTINEL"
    return 0
  fi
  while IFS= read -r sub; do
    sub="$(pm_trim "$sub")"
    [ -n "$sub" ] || continue
    if [ "$sub" = "$PM_NEST_SENTINEL" ]; then
      printf '%s\n' "$sub"
      continue
    fi
    head=0
    # The cheap test for a subcommand pm_strip_keywords could change, so the
    # common plain command skips it; it must cover every word that function
    # acts on.
    pm_first_word "$sub"
    case "$PM_WORD:$sub" in
      'do:'* | 'then:'* | 'else:'* | 'elif:'* | 'if:'* | 'while:'* | 'until:'* | '!:'* | '{:'* | 'function:'* | 'done:'* | 'fi:'* | 'esac:'* | '}:'* | 'for:'* | 'select:'* | 'case:'* | *'()'* | *' }')
        rc=0
        pm_strip_keywords "$sub" || rc=$?
        [ "$rc" -ne 1 ] || continue
        if [ "$rc" -eq 3 ]; then
          printf '%s\n' "$PM_NEST_SENTINEL"
          continue
        fi
        [ "$rc" -ne 2 ] || head=1
        sub="$PM_KW"
        ;;
    esac
    rest="$sub"
    case "$sub" in
      '('*)
        pm_group_split "$sub"
        pm_subcommands_at "$PM_G_IN" $((d + 1))
        rest="$PM_G_REST"
        head=1
        ;;
    esac
    [ "$head" -eq 1 ] || printf '%s\n' "$sub"
    # shellcheck disable=SC2016 # the substitution openers are matched literally
    case "$rest" in
      *'$('* | *'<('* | *'>('* | *'`'*) ;;
      *) continue ;;
    esac
    while IFS= read -r inner; do
      [ -n "$inner" ] || continue
      pm_subcommands_at "$inner" $((d + 1))
    done <<EOF
$(pm_substitutions "$rest")
EOF
  done <<EOF
$(pm_split_command "$s")
EOF
}

# pm_deny_subjects <command> — what the deny and ask sweeps match: every
# subcommand, plus every atom (pm_atoms) with its control-flow words dropped,
# so a command the structured reading missed is still swept.
pm_deny_subjects() {
  local a rc
  pm_subcommands "$1"
  while IFS= read -r a; do
    a="$(pm_trim "$a")"
    [ -n "$a" ] || continue
    rc=0
    pm_strip_keywords "$a" || rc=$?
    [ "$rc" -eq 0 ] || continue
    printf '%s\n' "$PM_KW"
  done <<EOF
$(pm_atoms "$1")
EOF
}

# pm_trim <string> — strip leading and trailing spaces and tabs.
pm_trim() {
  local s="$1" tab
  tab="$PM_TAB"
  while :; do
    case "$s" in
      ' '* | "$tab"*) s="${s#?}" ;;
      *) break ;;
    esac
  done
  while :; do
    case "$s" in
      *' ' | *"$tab") s="${s%?}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$s"
}

# pm_strip_leading_assignments <subcommand> — drop leading `VAR=value ` tokens.
#
# Doc rule M7: a deny or ask rule matches PAST any leading environment
# assignment (`Bash(rm *)` in deny still matches `FOO=bar rm -rf tmp/`). An
# allow rule only strips a known-safe set, which this model does not enumerate,
# so allow matching runs against the unstripped command — the conservative
# direction (the model under-predicts allow, never over-predicts it).
# The value scan is quote- and tab-aware. A naive split on the first space
# mangles both `FOO="a b" git push …` (splitting inside the quoted value) and
# `FOO=bar<TAB>git push …` (swallowing the command name into the assignment
# token), leaving a remainder no deny pattern can match. An assignment whose
# quote never closes is left unstripped: an unparseable command falls through to
# the prompt, which is what the real matcher does with input it cannot parse.
pm_strip_leading_assignments() {
  local s="$1" name value rest i n c q tab
  tab="$PM_TAB"
  while :; do
    # A leading assignment is a bare shell NAME, then `=`, then a value.
    name="${s%%=*}"
    [ "$name" != "$s" ] || break
    case "$name" in
      '' | *[!A-Za-z0-9_]* | [0-9]*) break ;;
    esac
    value="${s#"$name"=}"

    # Consume the value: quoted runs to their closing quote, a backslash escapes
    # the next character, and an unquoted space or tab ends it.
    i=0
    n=${#value}
    q=''
    while [ "$i" -lt "$n" ]; do
      c="${value:$i:1}"
      if [ -n "$q" ]; then
        [ "$c" != "$q" ] || q=''
        i=$((i + 1))
        continue
      fi
      case "$c" in
        '"' | "'")
          q="$c"
          i=$((i + 1))
          ;;
        ' ' | "$tab") break ;;
        \\) i=$((i + 2)) ;;
        *) i=$((i + 1)) ;;
      esac
    done

    # Ran off the end: either a bare `VAR=value` with no command after it, or an
    # unterminated quote. Neither is a leading assignment in front of a command,
    # so leave the string as it stands.
    [ "$i" -lt "$n" ] || break
    rest="$(pm_trim "${value:$i}")"
    [ -n "$rest" ] || break
    s="$rest"
  done
  printf '%s' "$s"
}

# --- single-pattern predicate ------------------------------------------------

# pm_matches <pattern> <subcommand> — exit 0 iff the pattern matches.
# Compiles on every call; used by the model's self-validation tests, never by
# the fixture or mutation loops (those use the precompiled rule arrays).
pm_matches() {
  local re
  re="$(pm_compile_pattern "$1")"
  [[ $2 =~ $re ]]
}

# --- rule sets ---------------------------------------------------------------

PM_DENY_N=0
PM_ASK_N=0
PM_ALLOW_N=0
PM_DENY_RULE=()
PM_DENY_RE=()
PM_ASK_RE=()
PM_ALLOW_RULE=()
PM_ALLOW_RE=()
PM_PATH_DENY_N=0
PM_PATH_ASK_N=0
PM_PATH_ALLOW_N=0
PM_PATH_DENY_RULE=()
PM_PATH_DENY_TOOL=()
PM_PATH_DENY_PAT=()
PM_PATH_DENY_RE=()
PM_PATH_ASK_TOOL=()
PM_PATH_ASK_PAT=()
PM_PATH_ASK_RE=()
PM_PATH_ALLOW_TOOL=()
PM_PATH_ALLOW_PAT=()
PM_PATH_ALLOW_RE=()
PM_TOOL_DENY=' '
PM_TOOL_ASK=' '
PM_TOOL_ALLOW=' '
PM_LOAD_GEN=0
PM_PATH_KEY=''

# pm_load_rules <deny-lines> <ask-lines> <allow-lines> — compile three
# newline-separated rule lists.
#
# Fails closed in two ways, because a rule set quietly smaller than the config
# ships would let the fixture table read every expected-deny row as "allowed":
#   2  the deny list yields no usable Bash rule (a vacuous deny set)
#   3  any list contains a rule that names the Bash tool but is not a usable
#      command pattern (pm_rule_pattern's exit 3)
# Non-Bash rules are still skipped silently: they cannot match a command.
pm_load_rules() {
  local deny="$1" ask="$2" allow="$3" rule pat rc malformed=0

  PM_DENY_N=0
  PM_ASK_N=0
  PM_ALLOW_N=0
  PM_DENY_RULE=()
  PM_DENY_RE=()
  PM_ASK_RE=()
  PM_ALLOW_RULE=()
  PM_ALLOW_RE=()
  PM_PATH_DENY_N=0
  PM_PATH_ASK_N=0
  PM_PATH_ALLOW_N=0
  PM_PATH_DENY_RULE=()
  PM_PATH_DENY_TOOL=()
  PM_PATH_DENY_PAT=()
  PM_PATH_ASK_TOOL=()
  PM_PATH_ASK_PAT=()
  PM_PATH_ALLOW_TOOL=()
  PM_PATH_ALLOW_PAT=()
  PM_TOOL_DENY=' '
  PM_TOOL_ASK=' '
  PM_TOOL_ALLOW=' '
  PM_LOAD_GEN=$((PM_LOAD_GEN + 1))

  while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    pat="$(pm_rule_pattern "$rule")"
    rc=$?
    [ "$rc" -ne 3 ] || {
      malformed=1
      continue
    }
    if [ "$rc" -ne 0 ]; then
      pm_path_record deny "$rule" || malformed=1
      continue
    fi
    PM_DENY_RULE[PM_DENY_N]="$rule"
    PM_DENY_RE[PM_DENY_N]="$(pm_compile_pattern "$pat")"
    PM_DENY_N=$((PM_DENY_N + 1))
  done <<EOF
$deny
EOF

  while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    pat="$(pm_rule_pattern "$rule")"
    rc=$?
    [ "$rc" -ne 3 ] || {
      malformed=1
      continue
    }
    if [ "$rc" -ne 0 ]; then
      pm_path_record ask "$rule" || malformed=1
      continue
    fi
    PM_ASK_RE[PM_ASK_N]="$(pm_compile_pattern "$pat")"
    PM_ASK_N=$((PM_ASK_N + 1))
  done <<EOF
$ask
EOF

  while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    pat="$(pm_rule_pattern "$rule")"
    rc=$?
    [ "$rc" -ne 3 ] || {
      malformed=1
      continue
    }
    if [ "$rc" -ne 0 ]; then
      pm_path_record allow "$rule" || malformed=1
      continue
    fi
    PM_ALLOW_RULE[PM_ALLOW_N]="$rule"
    PM_ALLOW_RE[PM_ALLOW_N]="$(pm_compile_pattern "$pat")"
    PM_ALLOW_N=$((PM_ALLOW_N + 1))
  done <<EOF
$allow
EOF

  [ "$malformed" -eq 0 ] || return 3
  [ "$PM_DENY_N" -gt 0 ] || return 2
  return 0
}

pm_deny_rule_count() { printf '%s' "$PM_DENY_N"; }
pm_deny_rule_at() { printf '%s' "${PM_DENY_RULE[$1]}"; }
pm_allow_rule_count() { printf '%s' "$PM_ALLOW_N"; }
pm_allow_rule_at() { printf '%s' "${PM_ALLOW_RULE[$1]}"; }

# --- path rules (doc rules M10, M11) -----------------------------------------
#
# `Read(<pattern>)` and `Edit(<pattern>)` rules guard file paths with gitignore
# patterns. Edit rules apply to every built-in tool that edits files, the
# Write tool included; a `Write(...)` or `NotebookEdit(...)` path rule is
# accepted but never matches (M11). A Read deny also blocks the edit tools on
# the same path. A bare `Read`, `Edit`, or `Write` entry governs that tool on
# every path: in deny it removes the tool, in allow it admits every call. The
# anchors a pattern resolves against are PM_CWD (the session's working
# directory, default $PWD), PM_HOME (default $HOME), and PM_SETTINGS_DIR (the
# directory of the file passed with --settings, which anchors a single-slash
# pattern; default PM_CWD), each read when a decision is made.

# pm_anchors — set PM_A_CWD, PM_A_HOME, and PM_A_SETTINGS to the anchors'
# current values (no fork).
pm_anchors() {
  PM_A_CWD="${PM_CWD:-$PWD}"
  PM_A_HOME="${PM_HOME:-${HOME:-}}"
  PM_A_SETTINGS="${PM_SETTINGS_DIR:-$PM_A_CWD}"
}

# pm_path_record <deny|ask|allow> <rule> — file a non-Bash rule. Returns 1 for
# a path rule missing its closing paren (fail closed, as for Bash rules);
# any other non-Bash rule (an MCP name, Grep, Glob) is ignored.
pm_path_record() {
  local kind="$1" rule="$2" tool pat
  case "$rule" in
    Read | Edit | Write | NotebookEdit)
      case "$kind" in
        deny) PM_TOOL_DENY="$PM_TOOL_DENY$rule " ;;
        ask) PM_TOOL_ASK="$PM_TOOL_ASK$rule " ;;
        allow) PM_TOOL_ALLOW="$PM_TOOL_ALLOW$rule " ;;
      esac
      return 0
      ;;
    'Read('*')' | 'Edit('*')' | 'Write('*')' | 'NotebookEdit('*')')
      tool="${rule%%(*}"
      pat="${rule#*(}"
      pat="${pat%)}"
      ;;
    'Read('* | 'Edit('* | 'Write('* | 'NotebookEdit('*) return 1 ;;
    *) return 0 ;;
  esac
  case "$kind" in
    deny)
      PM_PATH_DENY_RULE[PM_PATH_DENY_N]="$rule"
      PM_PATH_DENY_TOOL[PM_PATH_DENY_N]="$tool"
      PM_PATH_DENY_PAT[PM_PATH_DENY_N]="$pat"
      PM_PATH_DENY_N=$((PM_PATH_DENY_N + 1))
      ;;
    ask)
      PM_PATH_ASK_TOOL[PM_PATH_ASK_N]="$tool"
      PM_PATH_ASK_PAT[PM_PATH_ASK_N]="$pat"
      PM_PATH_ASK_N=$((PM_PATH_ASK_N + 1))
      ;;
    allow)
      PM_PATH_ALLOW_TOOL[PM_PATH_ALLOW_N]="$tool"
      PM_PATH_ALLOW_PAT[PM_PATH_ALLOW_N]="$pat"
      PM_PATH_ALLOW_N=$((PM_PATH_ALLOW_N + 1))
      ;;
  esac
}

pm_path_deny_rule_at() { printf '%s' "${PM_PATH_DENY_RULE[$1]}"; }

# pm_ere_escape <text> — escape ERE metacharacters, globs included.
pm_ere_escape() {
  local s="$1" out="" i
  i=0
  while [ "$i" -lt "${#s}" ]; do
    pm_ere_char "${s:$i:1}"
    out="$out$PM_CHAR"
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# pm_path_glob_ere <glob> — gitignore glob to ERE: `**/` spans zero or more
# directories, a trailing `/**` everything below, `*` and `?` stay inside one
# segment.
pm_path_glob_ere() {
  local g="$1" out="" i n c
  n=${#g}
  i=0
  while [ "$i" -lt "$n" ]; do
    c="${g:$i:1}"
    if [ "${g:$i:3}" = '**/' ]; then
      out="$out(.*/)?"
      i=$((i + 3))
      continue
    fi
    if [ "${g:$i:2}" = '**' ]; then
      out="$out.*"
      i=$((i + 2))
      continue
    fi
    case "$c" in
      '*') out="${out}[^/]*" ;;
      '?') out="${out}[^/]" ;;
      *)
        pm_ere_char "$c"
        out="$out$PM_CHAR"
        ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# pm_path_pattern_ere <deny|ask|allow> <pattern> — the anchored ERE a path
# rule's pattern compiles to (M10). `//p` is absolute, `~/p` home-relative,
# `/p` settings-relative, and `p` or `./p` relative to PM_CWD. A relative
# pattern with no slash (a bare name) matches at any depth under its anchor,
# and so, in deny and ask rules only, does a single directory segment
# followed by `/**`.
pm_path_pattern_ere() {
  local kind="$1" p="$2" base rel any=0 seg
  pm_anchors
  # shellcheck disable=SC2088 # a literal ~ is the rule's home anchor
  case "$p" in
    '//'*)
      base=''
      rel="${p#//}"
      ;;
    '~/'*)
      base="$PM_A_HOME"
      rel="${p#\~/}"
      ;;
    '/'*)
      base="$PM_A_SETTINGS"
      rel="${p#/}"
      ;;
    *)
      base="$PM_A_CWD"
      rel="${p#./}"
      case "$rel" in
        */*)
          seg="${rel%/\*\*}"
          if [ "$kind" != allow ] && [ "$seg" != "$rel" ]; then
            case "$seg" in
              */* | *'*'*) ;;
              *) any=1 ;;
            esac
          fi
          ;;
        *) any=1 ;;
      esac
      ;;
  esac
  base="${base%/}"
  if [ "$any" -eq 1 ]; then
    printf '^%s/(.*/)?%s$' "$(pm_ere_escape "$base")" "$(pm_path_glob_ere "$rel")"
  else
    printf '^%s/%s$' "$(pm_ere_escape "$base")" "$(pm_path_glob_ere "$rel")"
  fi
}

# pm_path_matches <deny|ask|allow> <pattern> <absolute-path> — exit 0 on match.
# Compiles on every call; used by the model's self-validation tests, never by
# the decision loops (those use pm_path_compile's arrays).
pm_path_matches() {
  local re
  re="$(pm_path_pattern_ere "$1" "$2")"
  [[ $3 =~ $re ]]
}

# pm_path_rule_applies <rule-tool> <tool> <deny|ask|allow> — whether a path
# rule of <rule-tool> governs a call of <tool>: Edit rules govern the edit
# tools, Read rules govern Read and, as deny or ask, the edit tools too.
pm_path_rule_applies() {
  case "$1:$2" in
    Edit:Edit | Edit:Write | Edit:NotebookEdit | Read:Read) return 0 ;;
    Read:Edit | Read:Write | Read:NotebookEdit) [ "$3" != allow ] ;;
    *) return 1 ;;
  esac
}

# pm_tool_in <list> <tool> — whether a bare tool-name entry covers <tool>. An
# Edit entry also covers Write and NotebookEdit, and a Read entry in deny or ask
# covers all three edit tools, as the matching path rules do.
pm_tool_in() {
  case "$1" in
    *" $2 "*) return 0 ;;
  esac
  case "$2" in
    Write | NotebookEdit)
      case "$1" in
        *' Edit '* | *' Read '*) return 0 ;;
      esac
      ;;
    Edit)
      case "$1" in
        *' Read '*) return 0 ;;
      esac
      ;;
  esac
  return 1
}

# pm_path_deny_match_indices <tool> <path> — the indices of every path deny
# rule that blocks the call, space separated.
pm_path_deny_match_indices() {
  local i out=""
  pm_path_compile
  i=0
  while [ "$i" -lt "$PM_PATH_DENY_N" ]; do
    if pm_path_rule_applies "${PM_PATH_DENY_TOOL[$i]}" "$1" deny \
      && [[ $2 =~ ${PM_PATH_DENY_RE[$i]} ]]; then
      out="$out $i"
    fi
    i=$((i + 1))
  done
  printf '%s' "${out# }"
}

# pm_path_compile — compile every path rule's ERE against the current anchors,
# once per pm_load_rules call and anchor triple, so the decision loops never
# fork. A caller deciding inside command substitutions runs it once in its own
# shell first, after setting the anchors, so each substitution inherits the
# compiled set rather than rebuilding it. Editing the rule arrays in place,
# rather than through pm_load_rules, is unsupported.
pm_path_compile() {
  local key i
  pm_anchors
  key="$PM_LOAD_GEN$PM_NL$PM_A_CWD$PM_NL$PM_A_HOME$PM_NL$PM_A_SETTINGS"
  [ "$key" != "$PM_PATH_KEY" ] || return 0
  PM_PATH_DENY_RE=()
  PM_PATH_ASK_RE=()
  PM_PATH_ALLOW_RE=()
  i=0
  while [ "$i" -lt "$PM_PATH_DENY_N" ]; do
    PM_PATH_DENY_RE[i]="$(pm_path_pattern_ere deny "${PM_PATH_DENY_PAT[$i]}")"
    i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "$PM_PATH_ASK_N" ]; do
    PM_PATH_ASK_RE[i]="$(pm_path_pattern_ere ask "${PM_PATH_ASK_PAT[$i]}")"
    i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "$PM_PATH_ALLOW_N" ]; do
    PM_PATH_ALLOW_RE[i]="$(pm_path_pattern_ere allow "${PM_PATH_ALLOW_PAT[$i]}")"
    i=$((i + 1))
  done
  PM_PATH_KEY="$key"
}

# pm_decide_path <tool> <absolute-path> — print deny | ask | allow | prompt
# for a Read, Edit, or Write tool call (M8 order).
pm_decide_path() {
  local tool="$1" path="$2" i
  pm_path_compile
  if pm_tool_in "$PM_TOOL_DENY" "$tool"; then
    printf 'deny'
    return 0
  fi
  i=0
  while [ "$i" -lt "$PM_PATH_DENY_N" ]; do
    if pm_path_rule_applies "${PM_PATH_DENY_TOOL[$i]}" "$tool" deny \
      && [[ $path =~ ${PM_PATH_DENY_RE[$i]} ]]; then
      printf 'deny'
      return 0
    fi
    i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "$PM_PATH_ASK_N" ]; do
    if pm_path_rule_applies "${PM_PATH_ASK_TOOL[$i]}" "$tool" ask \
      && [[ $path =~ ${PM_PATH_ASK_RE[$i]} ]]; then
      printf 'ask'
      return 0
    fi
    i=$((i + 1))
  done
  if pm_tool_in "$PM_TOOL_ASK" "$tool"; then
    printf 'ask'
    return 0
  fi
  case "$PM_TOOL_ALLOW" in
    *" $tool "*)
      printf 'allow'
      return 0
      ;;
  esac
  i=0
  while [ "$i" -lt "$PM_PATH_ALLOW_N" ]; do
    if pm_path_rule_applies "${PM_PATH_ALLOW_TOOL[$i]}" "$tool" allow \
      && [[ $path =~ ${PM_PATH_ALLOW_RE[$i]} ]]; then
      printf 'allow'
      return 0
    fi
    i=$((i + 1))
  done
  printf 'prompt'
}

# --- decision ----------------------------------------------------------------
#
# Doc rule M8: rules are evaluated deny, then ask, then allow; the first match
# in that order wins and specificity never reorders it. A compound command is
# denied when ANY subcommand matches a deny rule, and allowed only when EVERY
# subcommand matches an allow rule.

# pm_matching_deny_rule <command> — print the first matching deny rule as
# written, or nothing (exit 1).
pm_matching_deny_rule() {
  local sub stripped i
  while IFS= read -r sub; do
    [ -n "$sub" ] || continue
    stripped="$(pm_strip_leading_assignments "$sub")"
    i=0
    while [ "$i" -lt "$PM_DENY_N" ]; do
      if [[ $stripped =~ ${PM_DENY_RE[$i]} ]]; then
        printf '%s' "${PM_DENY_RULE[$i]}"
        return 0
      fi
      i=$((i + 1))
    done
  done <<EOF
$(pm_deny_subjects "$1")
EOF
  return 1
}

# pm_decide <command> — print deny | ask | allow | prompt.
#
# Deny is swept across EVERY deny subject before ask is considered at all.
# Doing both in one per-subcommand pass would let an earlier subcommand's ask
# match outrank a later subcommand's deny match, which inverts M8's global
# ordering. The deny and ask sweeps read pm_deny_subjects; allow reads the
# structured subcommands, every one of which must match.
pm_decide() {
  local sub stripped i matched any stripped_all=""

  while IFS= read -r sub; do
    [ -n "$sub" ] || continue
    stripped="$(pm_strip_leading_assignments "$sub")"
    stripped_all="$stripped_all$stripped$PM_NL"
    i=0
    while [ "$i" -lt "$PM_DENY_N" ]; do
      if [[ $stripped =~ ${PM_DENY_RE[$i]} ]]; then
        printf 'deny'
        return 0
      fi
      i=$((i + 1))
    done
  done <<EOF
$(pm_deny_subjects "$1")
EOF

  if [ "$PM_ASK_N" -gt 0 ]; then
    while IFS= read -r stripped; do
      [ -n "$stripped" ] || continue
      i=0
      while [ "$i" -lt "$PM_ASK_N" ]; do
        if [[ $stripped =~ ${PM_ASK_RE[$i]} ]]; then
          printf 'ask'
          return 0
        fi
        i=$((i + 1))
      done
    done <<EOF
$stripped_all
EOF
  fi

  any=0
  while IFS= read -r sub; do
    [ -n "$sub" ] || continue
    any=1
    matched=0
    i=0
    while [ "$i" -lt "$PM_ALLOW_N" ]; do
      if [[ $sub =~ ${PM_ALLOW_RE[$i]} ]]; then
        matched=1
        break
      fi
      i=$((i + 1))
    done
    if [ "$matched" -eq 0 ]; then
      printf 'prompt'
      return 0
    fi
  done <<EOF
$(pm_subcommands "$1")
EOF

  if [ "$any" -eq 1 ]; then printf 'allow'; else printf 'prompt'; fi
}
