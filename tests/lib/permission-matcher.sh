#!/bin/bash
# permission-matcher.sh — a documented re-implementation of Claude Code's Bash
# permission-rule matcher, used as the test oracle for the deny/allow fixture
# table (guard-coverage Task 1, D-4, REQ-A1.1).
#
# THIS IS A MODEL, NOT THE MATCHER. It encodes the semantics Claude Code's
# permission documentation states, so that a deny-list edit that re-opens a known
# evasion fails CI. The modeled behavior version, the sources consulted, the
# modeling boundaries, and the assumptions that are NOT settled by the
# documentation are all recorded in docs/permission-matcher-model.md — read that
# doc before changing anything here. When Claude Code's matcher changes, the doc
# is where the divergence surfaces (D-4).
#
#   Modeled behavior version: Claude Code CLI 2.1.220 / docs as of 2026-07-29.
#
# Sourced, not executed:  . tests/lib/permission-matcher.sh
# Portable bash 3.2 (no associative arrays, no mapfile); no forks in the hot
# path — patterns are compiled to EREs once and matched with [[ =~ ]].
#
# Public interface
#   pm_load_rules <deny-lines> <ask-lines> <allow-lines>
#         Compile three newline-separated rule lists (as they appear in a
#         settings.json permissions array: `Bash(<pattern>)`, `Read(...)`, a
#         bare tool name, ...). Non-Bash rules are ignored for command
#         matching. Returns 2 if the deny list contains no usable Bash rule.
#   pm_decide <command>
#         Print one of: deny | ask | allow | prompt   (prompt = no rule
#         matched, so the call falls through to the permission prompt).
#   pm_matching_deny_rule <command>
#         Print the first deny rule (as written) that matches, or nothing.
#   pm_matches <pattern> <command>
#         Low-level single-pattern predicate over a single subcommand; exit 0
#         on match. Used by the model's own self-validation tests.
#   pm_deny_rule_count / pm_deny_rule_at <i>
#         Enumerate the compiled deny rules (for the mutation pass).
set -u

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
      '.' | \\ | '+' | '?' | '(' | ')' | '[' | ']' | '{' | '}' | '^' | '$' | '|')
        out="$out\\$c"
        ;;
      *) out="$out$c" ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$out"
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

# pm_split_command <command> — print each subcommand on its own line.
#
# Claude Code is shell-operator aware: a rule must match each subcommand
# independently. The recognized separators are `&&`, `||`, `;`, `|`, `|&`, `&`,
# and newlines (doc rule M5). Two-character operators are consumed before the
# one-character ones so `&&` is never read as two `&`s.
#
# BOUNDARY (doc §"Modeling boundaries", MB-3): this split is quoting-unaware. A
# separator inside a quoted argument (`git commit -m "a; b"`) splits here where
# the real matcher would not. No fixture row relies on that shape.
pm_split_command() {
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
      ';' | '|' | '&' | '
')
        printf '%s\n' "$cur"
        cur=""
        i=$((i + 1))
        continue
        ;;
      *)
        cur="$cur$c"
        i=$((i + 1))
        ;;
    esac
  done
  printf '%s\n' "$cur"
}

# pm_trim <string> — strip leading and trailing spaces and tabs.
pm_trim() {
  local s="$1" tab
  tab="$(printf '\t')"
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
  tab="$(printf '\t')"
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
PM_ALLOW_RE=()

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
  PM_ALLOW_RE=()

  while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    pat="$(pm_rule_pattern "$rule")"
    rc=$?
    [ "$rc" -ne 3 ] || {
      malformed=1
      continue
    }
    [ "$rc" -eq 0 ] || continue
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
    [ "$rc" -eq 0 ] || continue
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
    [ "$rc" -eq 0 ] || continue
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
    sub="$(pm_trim "$sub")"
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
$(pm_split_command "$1")
EOF
  return 1
}

# pm_decide <command> — print deny | ask | allow | prompt.
#
# Deny is swept across EVERY subcommand before ask is considered at all. Doing
# both in one per-subcommand pass would let an earlier subcommand's ask match
# outrank a later subcommand's deny match, which inverts M8's global ordering.
pm_decide() {
  local sub stripped i subs matched any
  subs="$(pm_split_command "$1")"

  while IFS= read -r sub; do
    sub="$(pm_trim "$sub")"
    [ -n "$sub" ] || continue
    stripped="$(pm_strip_leading_assignments "$sub")"
    i=0
    while [ "$i" -lt "$PM_DENY_N" ]; do
      if [[ $stripped =~ ${PM_DENY_RE[$i]} ]]; then
        printf 'deny'
        return 0
      fi
      i=$((i + 1))
    done
  done <<EOF
$subs
EOF

  while IFS= read -r sub; do
    sub="$(pm_trim "$sub")"
    [ -n "$sub" ] || continue
    stripped="$(pm_strip_leading_assignments "$sub")"
    i=0
    while [ "$i" -lt "$PM_ASK_N" ]; do
      if [[ $stripped =~ ${PM_ASK_RE[$i]} ]]; then
        printf 'ask'
        return 0
      fi
      i=$((i + 1))
    done
  done <<EOF
$subs
EOF

  any=0
  while IFS= read -r sub; do
    sub="$(pm_trim "$sub")"
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
$subs
EOF

  if [ "$any" -eq 1 ]; then printf 'allow'; else printf 'prompt'; fi
}
