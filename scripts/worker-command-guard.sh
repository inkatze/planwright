#!/usr/bin/env bash
# worker-command-guard.sh — deterministic PreToolUse auto-approve hook for
# dispatched planwright workers (worker-permission-ergonomics Task 1;
# REQ-A1.1..A1.10, REQ-B1.1..B1.7, D-1..D-4). Wired into
# config/worker-settings.json (Task 2), it reads a Claude Code PreToolUse
# payload on stdin and prints a `permissionDecision: allow` decision for an
# ENUMERATED set of known-safe Bash command shapes (read-only shapes, trusted
# repo code, and the spec-root write zone) — silencing the
# permission-prompt flood on the shapes /execute-task actually issues (plugin
# scripts, `for`/`while` loops, read-only git/coreutil pipelines) — and DEFERS
# everything else to Claude Code's normal permission flow.
#
# Security contract (the whole point):
#   * No LLM in the decision path (REQ-A1.1); purely deterministic shell.
#   * Allow-only: it emits `allow` or nothing. It NEVER emits deny/ask and
#     NEVER exits non-zero — approval is upgrade-only; blocking stays with
#     permissions.deny/ask (REQ-A1.2, REQ-B1.7).
#   * The floor first: before any approval is weighed,
#     a simple command that a `Bash(…)` rule of the worker profile's deny
#     block matches, or that is a reserved act (a push, rebase, reset, amend,
#     hook skip, squash, or `gh` write), defers, declared check commands and
#     steps' lines included, save two own-unit acts (see own_unit_act): a push of the
#     recorded unit branch to origin and a body edit of its own open pull
#     request. The guard reads the deny block itself rather than trusting
#     Claude Code's evaluation order, and approves nothing when it cannot.
#   * The self-approval policy: the read-only arm (read-only
#     shapes, trusted repo code, declared check commands and steps, the
#     spec-root write zone) is
#     always in force; the own-branch arm, which approves writes confined to
#     the unit branch and its worktree, and the scratch arm, which approves
#     writes confined to the worker's scratch root, each only when the session
#     record names it. The record is the launcher's (see session_record_load):
#     the policy, the unit branch, the worktree, the scratch root, and the
#     audit-log home are never read from live config, the checkout, or the
#     environment. Each allow first appends a hashed line to the session's
#     audit log (audit_append); a record naming no usable log home turns both
#     write arms off.
#   * The extracted command is treated strictly as INERT DATA — never eval-ed,
#     re-expanded, glob-expanded, or used as a pattern/format/unquoted arg — so
#     analyzing a hostile command can never execute it (REQ-B1.1).
#   * Two write classes. The spec-root write zone, live only when
#     PLANWRIGHT_WORKER_SPEC_ROOT names a marked spec root, which the
#     dispatchers hand in only when it lies outside the work repository (see
#     in_spec_zone): a `>`/`>>` redirect, `tee [-a]`, or `mkdir [-p]` whose
#     every target is a plain literal inside a bundle or reserved directory of
#     that root. And the policy arms (see ob_path, ob_git), whose targets lie
#     inside the recorded worktree and outside the paths a tool runs or trusts
#     unprompted, or inside the recorded scratch root. Any other write defers.
#   * Fail safe on EVERYTHING: jq absent, malformed/empty/non-string input,
#     unknown construct, parser confusion, recursion past the depth bound, or
#     any internal error all DEFER (empty stdout, exit 0). The fallthrough
#     branch of every classifier is defer, so "zero false-allows" is guaranteed
#     by construction, not merely across the test corpus (REQ-B1.3, REQ-B1.7).
#
# Analysis model: the command string EXACTLY as the model wrote it — Claude Code
# hands a hook the raw `tool_input.command`, with `$VAR` references and
# assignments unexpanded (measured on CLI 2.1.270 against a `--settings` hook;
# the earlier claim here that variables arrive expanded was never true, and
# every shape built on it deferred). It is split — quote- and operator-aware —
# into segments on the control operators `;` `&&` `||` `|` `&` and newlines;
# EVERY segment's simple command must be independently known-safe, or a
# declared step's line (REQ-A1.4). A
# command is known-safe only when (a) its verb is on the enumerated allowlist
# below, (b) its flags/args designate no output/target file and enable no write
# or arbitrary execution (REQ-A1.8), the spec-root write zone excepted, and (c)
# it uses no construct the analyzer cannot confidently parse — process
# substitution, a command substitution outside the narrow form
# verify_known_simple and subst_words_ok admit, here-docs, subshell or brace
# grouping, env-assignment prefixes, path-prefixed verbs, escaped operators,
# ANSI-C quoting, shell comments, named-fd redirects — all of which defer
# (REQ-A1.9). The segments are read in run order, so the state one sets applies to those after it: a `cd` into the
# session's own worktree moves the working directory later segments are
# checked against (see cd_target_ok; a read line led by `cd <dir>;` is held to
# the scoped read mode instead, see scoped_read_ok), and the time/timeout prefixes are looked
# through to the command they wrap (see strip_prefixes); fin decides where
# state may carry. The expansions the analyzer resolves itself are a variable
# the same command assigned a plain literal (`f=a.md && grep x $f`; see
# track_assignment and expand_words), a `for` variable over plain-literal
# head words (see loop_header), and under the scratch arm `$TMPDIR`, the
# recorded scratch root: the substitution reproduces what the shell
# will do for exactly those value classes and nothing else, and any other
# expansion left in a verb, or in an operand a screen reads, defers (see
# word_unresolved). Repo `scripts/*.sh`
# / `tests/*.sh` and `bats <file>` are trusted repo code but only after their
# path canonicalizes INSIDE the repository and HEAD commits the file unchanged
# (committed_blob; a `bats` directory defers), and an INSTALLED planwright root's
# `scripts/*.sh` is trusted after canonicalizing inside a root the hook resolves
# for itself, held to that root's HEAD the same way when the root is a git
# checkout (REQ-A1.10; see is_planwright_script — the reason this needs no
# per-machine, version-pinned allow entry). `fish -c "<inner>"` recurses the same
# analysis on the inner string within a bounded depth.
# A segment none of these shapes approve is still approved when it matches a
# check command the repository declares (see check_command_ok), or is exactly
# a command step an operator declared (see declared_line_ok).
#
# Portable bash (3.2 floor / BSD compatible), no dependency on python, fish,
# mise, tmux, or Ansible; the security-critical analysis is pure shell. jq is
# used only to extract the two fields from the JSON payload; when jq is absent
# the hook degrades to deferring everything (REQ-B1.2), never a hand-rolled JSON
# parse and never a false-allow.
set -u
# The shared engine's own-environment switch: never on for a worker, and set
# here rather than inherited.
GUARD_OWN_ENVIRON=0
# Whether the environment the hook inherited sets a CDPATH, read before the
# unset below: a `cd` the shell could resolve through it is never approved.
HOOK_CDPATH_SET=0
[ -z "${CDPATH:-}" ] || HOOK_CDPATH_SET=1
unset CDPATH
# Pin the C locale so bracket expressions and character classes below mean
# exactly their ASCII range on every host (mirrors the sibling hooks).
LC_ALL=C
export LC_ALL

# Bounds (REQ-B1.7 bounded runtime). The tokenizer scans the command with
# bash substring indexing (`${s:i:1}`), which is O(n) per access and so O(n^2)
# over the command — a ~40 KiB command takes ~8 s. MAX_CMD_LEN caps that at a
# fraction of a second (~0.5 s) PER analyze_command entry so the hook can never
# hang a worker's tool call; a longer command simply defers (never worse than
# the normal prompt). Two routes re-enter analyze_command on text inside the
# command, a `fish -c "<inner>"` string and a command substitution's inner
# text, and a loop body is walked once per head word, each walk costing in
# proportion to its words' length. So MAX_SCANNED caps the text one hook call
# may tokenize and walk together, every entry and loop pass counted: past it
# the command defers, which keeps the end-to-end cost near that of a few
# full-length entries, plus STEPS_DEADLINE when a segment reaches the
# declared-step fallback. A substitution's verdict is kept for the working
# directory it last passed in, so a loop pass there does not analyse it again. 8 KiB is far above any
# real worker command shape. MAX_DEPTH caps `fish -c` recursion so a
# nested-`fish -c` bomb can never spin.
readonly MAX_CMD_LEN=8192
readonly MAX_SCANNED=$((MAX_CMD_LEN * 4))
readonly DOLLAR_COST=8
readonly MAX_DEPTH=3
# A `for` loop is verified once per head word (loop_header), so its cost
# multiplies the body's: past MAX_LOOP_WORDS head words the whole loop
# defers, and past MAX_LOOP_PASSES body walks in one command (nested loops
# multiply) the command defers.
readonly MAX_LOOP_WORDS=16
readonly MAX_LOOP_PASSES=64
# Simple commands verified in one hook call, loop passes and `fish -c` inner
# strings included: each may canonicalize a path, so this bounds the runtime
# the loop modelling multiplies. Past it the command defers.
readonly MAX_SIMPLE_CMDS=512
# Assignments tracked in one command: expand_word scans the table once per
# `$`, so past this the command defers rather than outrun the hook timeout.
readonly MAX_TRACKED_VARS=32

# The fixed reason string. It is NEVER a reflection of the analyzed command
# (REQ-B1.4): untrusted command content is never echoed to a terminal-driving
# stream.
readonly ALLOW_REASON='planwright worker-command-guard: enumerated known-safe command shape under the session self-approval policy (deterministic, no LLM)'

# emit_allow: write the single allow decision (the only thing this hook ever
# prints). Written as one final action after every check has passed, so there
# is never a partially-written allow (REQ-B1.7).
emit_allow() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"'"$ALLOW_REASON"'"}}'
}

# The policy arms whose checks admitted part of the command being approved:
# set by ob_path, ob_git_ready, guard_mktemp, and expand_word's `$TMPDIR`,
# reset per hook call; AUDIT_OU, by own_unit_act. Read-only is whatever
# approval set none of them.
AUDIT_OB=0
AUDIT_SC=0
AUDIT_OU=0
# 1 once the own-branch arm approved an act that can change a worktree file
# (a file write, or a git act other than add and commit); main reads it beside
# COMMITTED_USED.
OB_TOUCH=0
OU_EXPORTED=0
OU_EXP_NAMES=''
OU_SEG=0
# 1 once the own-branch or scratch arm or the spec-root zone approved a write
# or a git act other than add and commit, a plain fetch was approved, or a
# plugin script other than an installed step script ran (main reads it).
ARM_ACT=0
# 1 while the segment being verified is an own-unit partner: git add or
# commit through the own-branch arm, or a gate task (fin reads it).
OU_PARTNER=0

# audit_append <command> <session-id>: append the approval's line to the
# session's audit log, before the decision is written. The command, its
# trailing newlines already removed, is recorded only as its SHA-256, never
# as text, since commands carry what workers type. One append write, so
# concurrent hook calls interleave whole lines; a write that fails is dropped and the approval stands. The log is
# checked again here because a FIFO in its place would hang the hook.
audit_append() {
  local f=$REC_AUDIT_LOG arm='' t h sid=$2
  [ -n "$f" ] || return 0
  [ "$AUDIT_OB" = 0 ] || arm=own-branch
  [ "$AUDIT_SC" = 0 ] || arm=${arm:+$arm,}scratch
  [ "$AUDIT_OU" = 0 ] || arm=${arm:+$arm,}own-unit
  [ -n "$arm" ] || arm=read-only
  [[ $sid =~ ^[A-Za-z0-9_-]{1,128}$ ]] || sid=-
  t=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || t=-
  if command -v sha256sum >/dev/null 2>&1; then
    h=$(printf '%s' "$1" | sha256sum 2>/dev/null) || h=-
  else
    h=$(printf '%s' "$1" | shasum -a 256 2>/dev/null) || h=-
  fi
  h=${h%% *}
  [[ $h =~ ^[0-9a-f]{64}$ ]] || h=-
  if [ -e "$f" ] || [ -L "$f" ]; then
    [ -f "$f" ] && [ ! -L "$f" ] || return 0
  fi
  (
    umask 077
    printf '%s\n' "time=$t session=$sid arm=$arm cmd_sha256=$h" >>"$f"
  ) 2>/dev/null || :
}

# --------------------------------------------------------------------------
# Tokenizer (REQ-A1.4, REQ-A1.9). Scans the command as inert data into a token
# stream held in the caller's (analyze_command's) locals TOK_TYPE / TOK_VAL /
# TOK_N via dynamic scope. Token types: W (word), O (control/grouping operator:
# `;` `;;` `&&` `||` `|` `&` `(` `)`), R (redirect operator, possibly with an
# fd-number prefix). Returns non-zero (DEFER) the instant it meets a construct
# it will not analyze: unbalanced quotes, process substitution, a command
# substitution subst_scan refuses, backtick substitution, ANSI-C `$'…'`, a
# backslash line-continuation or escaped operator/quote, a shell comment, or a
# named-fd redirect. It never executes or expands anything it scans.
# tok_push <type> <value> [quoted]: the optional third arg records whether a W
# token was built from any quoting or backslash-escaping (1) or is a bare,
# unquoted literal (0, the default for operators and plain words). classify of a
# redirect operand uses it: a quoted operand is never a bare fd-number or bare
# /dev/null, so it must not read as a safe fd-dup / null-write (REQ-A1.4).
# The optional fourth arg records whether the word carries a LITERAL `$` — one
# produced by single quotes or a backslash — that the shell will NOT expand.
# expand_word refuses to substitute into such a word, since it cannot tell a
# literal `$` from an expanding one once the quotes are gone. The optional fifth
# arg is the offset within the word at which quoting FIRST began (-1 when the
# word is bare): track_assignment needs the name and the `=` of an assignment
# to be unquoted, which the whole-word flag cannot tell from a quoted value.
# The sixth arg records an EXPANDING `$` (one the shell will expand: 1 inside
# double quotes only, 2 unquoted), the seventh an unquoted glob, brace
# expansion, or leading tilde: either way the word's value is not its text
# (see word_unresolved). The eighth is the zsh-option flag (see
# zsh_opt_word_ok). The ninth records that the quoting is mixed: a second
# quoted run, or an unquoted character after quoting began, so a value quoted
# from its first character is wholly quoted only when this is 0. The tenth
# lists, space-separated, the SUBST_TXT indexes of the `$(…)` substitutions the
# word holds (see subst_scan).
tok_push() {
  TOK_TYPE[TOK_N]=$1
  TOK_VAL[TOK_N]=$2
  TOK_QUOTED[TOK_N]=${3:-0}
  TOK_NOEXP[TOK_N]=${4:-0}
  TOK_QPOS[TOK_N]=${5:--1}
  TOK_DYN[TOK_N]=${6:-0}
  TOK_GLOB[TOK_N]=${7:-0}
  TOK_ZOPT[TOK_N]=${8:-0}
  TOK_QMIX[TOK_N]=${9:-0}
  TOK_SUBS[TOK_N]=${10:-}
  TOK_N=$((TOK_N + 1))
}

# dollar_count <text>: sets DOLLAR_N to the number of `$` in <text>, by
# splitting on them, which stays linear. `${text//[!\$]/}` is quadratic in
# bash 3.2, macOS's /bin/bash, and costs seconds on a command near
# MAX_CMD_LEN, so the budget charge would outrun the work it bounds.
dollar_count() {
  local IFS='$' noglob=0
  local -a dc_parts
  DOLLAR_N=0
  case $1 in *'$'*) ;; *) return 0 ;; esac
  case $- in *f*) noglob=1 ;; esac
  set -f
  # shellcheck disable=SC2206 # split on `$` alone; the `.` keeps a trailing one
  dc_parts=($1.)
  [ "$noglob" = 1 ] || set +f
  DOLLAR_N=$((${#dc_parts[@]} - 1))
}

# dollar_expands <next-char>: 0 when a `$` followed by <next-char> starts an
# expansion. A `$` before anything else (end of word, `/`, a space) is literal.
# zsh, the Bash tool's shell on macOS, also expands `$~NAME`, `$=NAME`,
# `$^NAME` and `$+NAME`, which bash leaves as text.
dollar_expands() {
  case $1 in
    [A-Za-z0-9_@*#?!~=^+-] | '{' | '$' | '[' | '"') return 0 ;;
  esac
  return 1
}

# dollar_form_ok <string> <index>: the `$` at <index> opens a form whose value
# the analyzer can reason about: not `$[…]` arithmetic, and a `${…}` only
# around a bare NAME. Any other brace form (`${a[i]}`, `${x:off}`, `${!n}`,
# `${#x}`, a modifier) evaluates text the hook never sees, an array subscript
# or offset arithmetically, so a value read at run time can run a command.
# A non-ASCII byte right after the `$`, or right after the NAME it opens,
# defers: zsh in a UTF-8 locale reads a non-ASCII letter as part of a name,
# so the shell expands one longer name where this C-locale scan ends the
# name before that byte and keeps the byte as literal text. zsh's `$~NAME`
# defers wherever it appears: it reads the value as a glob pattern, and a
# glob qualifier in that value can run a command during the expansion. So
# does a NAME or a one-character special parameter (`$*`, `$@`, `$?`)
# directly followed by `[`, quoted or not: zsh reads that as a
# subscript and evaluates it as arithmetic, which can assign a variable.
dollar_form_ok() {
  local s=$1 i=$2 j k body
  case ${s:i+1:1} in
    '[' | '~') return 1 ;;
    '{')
      j=$((i + 2))
      body=''
      while [ "$j" -lt "${#s}" ] && [ "${s:j:1}" != '}' ]; do
        body="$body${s:j:1}"
        j=$((j + 1))
      done
      [ "$j" -lt "${#s}" ] || return 1
      case $body in
        '' | [!A-Za-z_]* | *[!A-Za-z0-9_]*) return 1 ;;
      esac
      ;;
    *)
      j=$((i + 1))
      case ${s:j:1} in [=^+#]) j=$((j + 1)) ;; esac
      k=$j
      while [ "$j" -lt "${#s}" ]; do
        case ${s:j:1} in
          [A-Za-z0-9_]) j=$((j + 1)) ;;
          *) break ;;
        esac
      done
      case ${s:j:1} in
        '[') return 1 ;;
        '*' | '@' | '?' | '!' | '-' | '$' | '#') [ "$j" -ne "$k" ] || [ "${s:j+1:1}" != '[' ] || return 1 ;;
        '' | [[:print:][:cntrl:]]) ;;
        *) return 1 ;;
      esac
      ;;
  esac
  return 0
}

# subst_scan <string> <index>: the `$(` at <index> opens a command
# substitution the narrow rule can judge (REQ-E1.3): its text runs to the
# first `)` and holds no `(` and no backtick, so it nests nothing, and a `)`
# the shell would read as quoted or escaped cuts the text inside that quote
# or escape, which then fails to tokenize when verify_known_simple analyses
# it. Records the inner text in SUBST_TXT, its index in SUBST_IDX, and the
# index past the `)` in SUBST_END. `$((` arithmetic, and any substitution
# inside a `fish -c` string (fish splits its output on newlines alone),
# defer.
subst_scan() {
  local s=$1 p=$(($2 + 2))
  [ "$HOOK_DEPTH" -eq 0 ] || return 1
  [ "${s:p:1}" != '(' ] || return 1
  while [ "$p" -lt "${#s}" ]; do
    case ${s:p:1} in
      ')') break ;;
      '(' | '`') return 1 ;;
    esac
    p=$((p + 1))
  done
  [ "$p" -lt "${#s}" ] || return 1
  SUBST_TXT[SUBST_N]=${s:$2+2:p-$2-2}
  SUBST_IDX=$SUBST_N
  SUBST_N=$((SUBST_N + 1))
  SUBST_END=$((p + 1))
}

tokenize() {
  local s=$1
  local n=${#s}
  local i=0
  local cur='' have=0 curq=0 curx=0 curqp=-1 curd=0 curg=0 curz=0 curqm=0 brk=0 brc=0 brs=0 cursub=''
  local c nc j k dc dn fdpfx

  # _flush: push the accumulated word (if any) as a W token carrying its
  # quoting-provenance, literal-dollar, quote-start, expansion and glob flags,
  # then reset the accumulator.
  _flush() {
    if [ "$have" = 1 ]; then
      tok_push W "$cur" "$curq" "$curx" "$curqp" "$curd" "$curg" "$curz" "$curqm" "$cursub"
      cur=''
      cursub=''
      have=0
      curq=0
      curx=0
      curqp=-1
      curd=0
      curg=0
      curz=0
      curqm=0
      brk=0
      brc=0
      brs=0
    fi
  }
  # _quoting: record where quoting first began in the current word.
  _quoting() {
    [ "$curq" = 1 ] && curqm=1
    [ "$curq" = 1 ] || curqp=${#cur}
    curq=1
  }

  # named_fd_word: 0 when the word built up to a redirect is a `{name}`
  # brace word, which bash and zsh read as a named-fd redirect that assigns
  # that shell variable, not as an operand.
  named_fd_word() {
    [ "$have" = 1 ] || return 1
    case $cur in
      '{'*'}') return 0 ;;
    esac
    return 1
  }

  while [ "$i" -lt "$n" ]; do
    c=${s:i:1}
    case $c in
      \\)
        nc=${s:i+1:1}
        [ -n "$nc" ] || return 1 # trailing backslash
        case $nc in
          "'" | '"' | ';' | '&' | '|' | '<' | '>' | '(' | ')') return 1 ;; # escaped op/quote
          "$NL") return 1 ;;                                               # line continuation
          '$') curx=1 ;;                                                   # literal dollar
        esac
        _quoting
        cur="$cur$nc"
        have=1
        i=$((i + 2))
        ;;
      "'")
        j=$((i + 1))
        k=''
        while [ "$j" -lt "$n" ] && [ "${s:j:1}" != "'" ]; do
          k="$k${s:j:1}"
          j=$((j + 1))
        done
        [ "$j" -lt "$n" ] || return 1 # unbalanced single quote
        case $k in *'$'*) curx=1 ;; esac
        _quoting
        cur="$cur$k"
        have=1
        i=$((j + 1))
        ;;
      '"')
        j=$((i + 1))
        k=''
        while [ "$j" -lt "$n" ] && [ "${s:j:1}" != '"' ]; do
          dc=${s:j:1}
          if [ "$dc" = "\\" ]; then
            dn=${s:j+1:1}
            [ -n "$dn" ] || return 1
            [ "$dn" = '$' ] && curx=1 # \$ inside double quotes is literal
            # bash keeps the backslash before any other character, and
            # guard_fish must see it.
            case $dn in
              '$' | '`' | '"' | "\\") k="$k$dn" ;;
              # bash drops a backslash-newline whole, joining the word's halves.
              "$NL") return 1 ;;
              *) k="$k\\$dn" ;;
            esac
            j=$((j + 2))
            continue
          fi
          if [ "$dc" = '$' ]; then
            dn=${s:j+1:1}
            # Its text opens a fresh quoting context, so a `"` in it does
            # not end this one.
            if [ "$dn" = '(' ]; then
              subst_scan "$s" "$j" || return 1
              cursub="$cursub $SUBST_IDX"
              [ "$curd" = 2 ] || curd=1
              k="$k${s:j:SUBST_END-j}"
              j=$SUBST_END
              continue
            fi
            [ "$dn" = "'" ] && return 1 # $' ANSI-C quoting
            dollar_form_ok "$s" "$j" || return 1
            [ "$dn" != '"' ] && dollar_expands "$dn" && { [ "$curd" = 2 ] || curd=1; }
            [ "$dn" = '@' ] && curd=2 # "$@" splits into words even quoted
          fi
          [ "$dc" = '`' ] && return 1 # backtick substitution
          k="$k$dc"
          j=$((j + 1))
        done
        [ "$j" -lt "$n" ] || return 1 # unbalanced double quote
        _quoting
        cur="$cur$k"
        have=1
        i=$((j + 1))
        ;;
      '`') return 1 ;; # backtick substitution
      '$')
        nc=${s:i+1:1}
        if [ "$nc" = '(' ]; then
          subst_scan "$s" "$i" || return 1
          cursub="$cursub $SUBST_IDX"
          curd=2
          [ "$curq" = 1 ] && curqm=1
          cur="$cur${s:i:SUBST_END-i}"
          have=1
          i=$SUBST_END
          continue
        fi
        [ "$nc" = "'" ] && return 1 # $' ANSI-C quoting
        dollar_form_ok "$s" "$i" || return 1
        dollar_expands "$nc" && curd=2
        [ "$curq" = 1 ] && curqm=1
        cur="$cur$c"
        have=1
        i=$((i + 1))
        ;;
      ' ' | "$TAB")
        _flush
        i=$((i + 1))
        ;;
      "$NL")
        _flush
        tok_push O ';'
        i=$((i + 1))
        ;;
      ';')
        _flush
        if [ "${s:i+1:1}" = ';' ]; then
          tok_push O ';;'
          i=$((i + 2))
        else
          tok_push O ';'
          i=$((i + 1))
        fi
        ;;
      '&')
        nc=${s:i+1:1}
        [ "$nc" = '>' ] && named_fd_word && return 1
        _flush
        if [ "$nc" = '&' ]; then
          tok_push O '&&'
          i=$((i + 2))
        elif [ "$nc" = '>' ]; then
          if [ "${s:i+2:1}" = '>' ]; then
            tok_push R '&>>'
            i=$((i + 3))
          else
            tok_push R '&>'
            i=$((i + 2))
          fi
        else
          tok_push O '&'
          i=$((i + 1))
        fi
        ;;
      '|')
        _flush
        nc=${s:i+1:1}
        if [ "$nc" = '|' ]; then
          tok_push O '||'
          i=$((i + 2))
        elif [ "$nc" = '&' ]; then
          tok_push O '|' # |& (pipe stdout+stderr) is still a pipe boundary
          i=$((i + 2))
        else
          tok_push O '|'
          i=$((i + 1))
        fi
        ;;
      '<' | '>')
        # A pure-digit run built up to here with no intervening space is the
        # fd number of this redirect (e.g. the 2 in 2>&1), not a word.
        fdpfx=''
        named_fd_word && return 1
        if [ "$have" = 1 ]; then
          # A quoted digit run is a word (bash only reads an UNQUOTED digit run
          # as this redirect's fd number), so an fd prefix is bare digits only.
          case $cur in
            '' | *[!0-9]*) tok_push W "$cur" "$curq" "$curx" "$curqp" "$curd" "$curg" "$curz" "$curqm" "$cursub" ;;
            *) [ "$curq" = 1 ] && tok_push W "$cur" "$curq" "$curx" "$curqp" "$curd" "$curg" "$curz" "$curqm" "$cursub" || fdpfx=$cur ;;
          esac
          cur=''
          cursub=''
          have=0
          curq=0
          curx=0
          curqp=-1
          curd=0
          curg=0
          curz=0
          curqm=0
          brk=0
          brc=0
          brs=0
        fi
        if [ "$c" = '<' ]; then
          nc=${s:i+1:1}
          if [ "$nc" = '<' ]; then
            if [ "${s:i+2:1}" = '<' ]; then
              tok_push R "${fdpfx}<<<"
              i=$((i + 3))
            elif [ "${s:i+2:1}" = '-' ]; then
              tok_push R "${fdpfx}<<-"
              i=$((i + 3))
            else
              tok_push R "${fdpfx}<<"
              i=$((i + 2))
            fi
          elif [ "$nc" = '&' ]; then
            tok_push R "${fdpfx}<&"
            i=$((i + 2))
          elif [ "$nc" = '(' ]; then
            return 1 # <( process substitution
          else
            tok_push R "${fdpfx}<"
            i=$((i + 1))
          fi
        else
          nc=${s:i+1:1}
          if [ "$nc" = '>' ]; then
            tok_push R "${fdpfx}>>"
            i=$((i + 2))
          elif [ "$nc" = '|' ]; then
            tok_push R "${fdpfx}>|"
            i=$((i + 2))
          elif [ "$nc" = '&' ]; then
            tok_push R "${fdpfx}>&"
            i=$((i + 2))
          elif [ "$nc" = '(' ]; then
            return 1 # >( process substitution
          else
            tok_push R "${fdpfx}>"
            i=$((i + 1))
          fi
        fi
        ;;
      '(')
        _flush
        tok_push O '('
        i=$((i + 1))
        ;;
      ')')
        _flush
        tok_push O ')'
        i=$((i + 1))
        ;;
      *)
        # Unquoted pattern characters: a glob (`*`, `?`, a closed `[…]`), a
        # brace expansion (`{` then `,` or `..` then `}`), or a leading `~`.
        # A word-initial `#` opens a shell comment, which this scan does not
        # model, so the command defers.
        case $c in
          '*' | '?') curg=1 ;;
          '[') brk=1 ;;
          ']') [ "$brk" = 1 ] && curg=1 ;;
          '{')
            brc=1
            curz=1
            ;;
          ',') [ "$brc" = 1 ] && brs=1 ;;
          '.') [ "$brc" = 1 ] && [ "${s:i+1:1}" = . ] && brs=1 ;;
          '}')
            [ "$brs" = 1 ] && curg=1
            curz=1
            ;;
          '~') if [ "$have" = 0 ]; then curg=1; else curz=1; fi ;;
          '#') if [ "$have" = 0 ]; then return 1; else curz=1; fi ;;
          '^') curz=1 ;;
        esac
        [ "$curq" = 1 ] && curqm=1
        cur="$cur$c"
        have=1
        i=$((i + 1))
        ;;
    esac
  done
  _flush
  return 0
}

# --------------------------------------------------------------------------
# is_reserved <word>: shell reserved words the verifier recognizes structurally.
is_reserved() {
  case $1 in
    for | select | while | until | if | then | elif | else | fi | do | done | 'case' | 'esac' | 'in') return 0 ;;
    *) return 1 ;;
  esac
}

# --------------------------------------------------------------------------
# classify_redirect <op> <operand>: 0 if this redirect is safe (a read, an
# fd-dup/close, or a write to /dev/null), non-zero (DEFER) if it writes a real
# file or is a here-doc/here-string (REQ-A1.4). fd-number prefixes are stripped
# first so `2>&1`, `>&2`, `2>&-` read as fd operations, not file writes.
classify_redirect() {
  local operand=$2 bare=$1
  while [ -n "$bare" ]; do
    case $bare in
      [0-9]*) bare=${bare#?} ;;
      *) break ;;
    esac
  done
  case $bare in
    '<' | '<&') return 0 ;;           # input read / input fd-dup
    '<<' | '<<-' | '<<<') return 1 ;; # here-doc / here-string
    '>' | '>>' | '>|')
      [ "$operand" = /dev/null ] && return 0 || return 1
      ;;
    '>&')
      case $operand in
        /dev/null | '-') return 0 ;; # write to null / fd-close
        '' | *[!0-9]*) return 1 ;;   # a filename target -> write
        *) return 0 ;;               # pure digits -> fd-dup
      esac
      ;;
    '&>' | '&>>')
      [ "$operand" = /dev/null ] && return 0 || return 1
      ;;
    *) return 1 ;;
  esac
}

# --------------------------------------------------------------------------
# Repo-root discovery and path containment (REQ-A1.10). repo_root walks up from
# the payload cwd looking for a `.git` entry (a dir in a normal checkout, a file
# in a worktree). canon_under canonicalizes a script/bats path (resolving
# `..` and symlinks on its directory) and checks it resolves INSIDE the repo.
repo_root_of() {
  local d=$1
  d=$(cd "$d" 2>/dev/null && pwd -P) || return 1
  while [ -n "$d" ] && [ "$d" != / ]; do
    if [ -e "$d/.git" ]; then
      printf '%s' "$d"
      return 0
    fi
    d=$(dirname "$d")
  done
  return 1
}

# canon_under <path> <cwd> <base>: prints the canonical absolute path of <path>
# (resolved relative to <cwd>) and returns 0 only when it resolves inside <base>,
# an ALREADY-CANONICAL root; returns non-zero (DEFER) otherwise — including when
# <base> is empty or the path's directory cannot be resolved. Both sides of the
# containment compare are canonical, so a `..` segment cannot escape and a
# sibling directory that merely shares the root's name PREFIX
# (`/x/planwright-evil` against `/x/planwright`) does not match.
canon_under() {
  local p=$1 cwd=$2 base=$3 d b cd
  [ -n "$base" ] || return 1
  case $p in
    /*) ;;
    *) p="$cwd/$p" ;;
  esac
  d=$(dirname "$p")
  b=$(basename "$p")
  cd=$(cd "$d" 2>/dev/null && pwd -P) || return 1
  local full="$cd/$b"
  # `pwd -P` above canonicalizes any symlink in the DIRECTORY path, but the
  # final component can still be a symlink pointing OUT of the repo — bash/bats
  # would follow it and run external code. REQ-A1.10 requires the path to
  # RESOLVE inside the repo, so defer a symlinked target rather than trust its
  # in-repo location (a symlinked script travels through a normal git checkout).
  [ -L "$full" ] && return 1
  case $full in
    "$base"/*)
      printf '%s' "$full"
      return 0
      ;;
    *) return 1 ;;
  esac
}

# committed_blob <root> <rel> <full>: 0 when <full> (the canonical path of
# <rel> under the work tree <root>) is a regular file whose bytes are exactly
# the blob HEAD records for <rel>, as a plain or executable file. Where a file
# sits proves nothing about who wrote it, since a worker may Write it, so a
# file the guard trusts by its content is trusted only as a commit holds it.
# Plumbing only, so no index refresh (no write, no index.lock race with a
# concurrent commit) and no filter or textconv driver runs. A verdict is kept
# per path for the rest of the hook call, since a loop re-checks its body.
#
# COMMITTED_USED records that the approval leans on such a check, which holds
# only for the file as it is before the command runs: main refuses a command
# that also makes an own-branch act that can change a worktree file
# (OB_TOUCH), since that act could land on the file before the shell reaches
# it. Staging and committing change no worktree file, so they do not count.
COMMITTED_OK=''
COMMITTED_USED=0
committed_blob() {
  local root=$1 rel=$2 full=$3 key line meta path want have
  key=$'\n'"$full"$'\n'
  case $COMMITTED_OK in
    *"$key"*)
      committed_used "$full"
      return 0
      ;;
  esac
  [ -f "$full" ] && [ ! -L "$full" ] || return 1
  line=$(git_plain -C "$root" -c core.quotePath=false ls-tree --full-tree HEAD -- "$rel" 2>/dev/null) || return 1
  case $line in
    *$'\n'*) return 1 ;;
  esac
  meta=${line%%$'\t'*}
  path=${line#*$'\t'}
  [ "$path" = "$rel" ] || return 1
  case $meta in
    '100644 blob '* | '100755 blob '*) want=${meta##* } ;;
    *) return 1 ;;
  esac
  have=$(git_plain -C "$root" hash-object --no-filters -- "$full" 2>/dev/null) || return 1
  [ -n "$want" ] && [ "$want" = "$have" ] || return 1
  COMMITTED_OK=$COMMITTED_OK$key
  committed_used "$full"
  return 0
}

# committed_used <full>: note a committed check the approval leans on, when the
# file lies in the recorded worktree, the only place an own-branch write lands.
committed_used() {
  case $1 in
    "$REC_WT"/*) [ -z "$REC_WT" ] || COMMITTED_USED=1 ;;
  esac
}

# git_plain <args>: git answering about the repository its -C names, never one
# a GIT_DIR, GIT_WORK_TREE or index variable inherited from a git hook points at.
git_plain() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY git "$@"
}

# committed_in_checkout <full>: 0 when <full>, a canonical path, is a file the
# git checkout holding it commits unchanged (committed_blob). The checkout must
# answer for itself: a `.git` that is no repository of its own would let git
# answer from the one around it.
committed_in_checkout() {
  local root
  root=$(repo_root_of "$(dirname -- "$1")") || return 1
  [ "$(git_plain -C "$root" rev-parse --show-toplevel 2>/dev/null)" = "$root" ] || return 1
  committed_blob "$root" "${1#"$root"/}" "$1"
}

# is_repo_script <path> <cwd>: 0 when <path> is a `.sh` under a scripts/ or
# tests/ directory that canonicalizes inside the repo (REQ-A1.5, REQ-A1.10)
# and matches what HEAD commits there (committed_blob).
is_repo_script() {
  local p=$1 cwd=$2 full rel root
  case $p in
    *.sh) ;;
    *) return 1 ;;
  esac
  root=$(repo_root_of "$cwd") || return 1
  full=$(canon_under "$p" "$cwd" "$root") || return 1
  # The force-push helper under another name (a hardlink) is still the tower's.
  [ ! "$full" -ef "$root/scripts/tower-force-push.sh" ] || return 1
  rel=${full#"$root"/}
  case $rel in
    scripts/* | tests/* | */scripts/* | */tests/*) ;;
    *) return 1 ;;
  esac
  committed_blob "$root" "$rel" "$full"
}

# planwright_roots: print, one per line and canonicalized, every planwright
# installation root this hook trusts its `scripts/*.sh` under: every arm of
# the core root chain, as `resolve-root.sh install --all` reports it
# (chain_roots below), plus this guard's own policy arms:
#
#   1. the core root chain         every content-bearing arm, highest first
#   2. $HOOK_SELF_ROOT             this hook's own sibling root (`dirname $0`/..),
#                                  kept apart from the chain's self-location arm
#                                  so it holds even if the resolver cannot run
#   3. every installed root        what Claude Code records in
#                                  <claude-dir>/plugins/installed_plugins.json
#                                  for a planwright plugin, plus every version
#                                  directory under the marketplace cache
#                                  (<claude-dir>/plugins/cache/*/planwright/*)
#
# Arm 2 is what makes this allowance need NO per-machine, version-pinned settings
# entry: the guard ships at <root>/scripts/worker-command-guard.sh, so it can
# always locate its own root. Arm 3 exists because arms 1 and 2 both resolve
# to the root the LAUNCHER lives in (the dispatch-env wrapper exports its own
# root as the chain's PLANWRIGHT_ROOT and CLAUDE_PLUGIN_ROOT arms), while the
# skill text a worker executes is loaded from wherever Claude Code installed
# the plugin, and `${CLAUDE_PLUGIN_ROOT}` in that text substitutes to THAT
# root. A tower driving a checkout's scripts/ therefore
# launched workers whose every plugin-script call — the first thing
# /execute-task does — named a root the hook did not trust, and deferred
# (2026-09-12, format-grammar task 7). The installed roots are Claude Code's own
# record and its own cache layout, never a value taken from the analyzed command
# (REQ-B1.1); like the chain's other arms they are resolved only when a script
# path is checked, at most once per hook call (cache_roots), since most
# commands never need them and the hook runs on every tool call.
#
# Each root is canonicalized (`cd … && pwd -P`, resolving `..` segments and
# symlinked components) and skipped when it does not resolve; containment then
# goes through canon_under, so a `..` segment in the path, a symlinked leaf, or
# a sibling directory that merely shares the root's name PREFIX never passes.
planwright_roots() {
  local r root
  {
    chain_roots
    printf '%s\n' "${HOOK_SELF_ROOT:-}"
    installed_planwright_roots
  } | while IFS= read -r r; do
    [ -n "$r" ] || continue
    root=$(cd "$r" 2>/dev/null && pwd -P) || continue
    printf '%s\n' "$root"
  done
}

# cache_roots: compute planwright_roots once per hook call into PW_ROOTS. A
# loop body re-verifies its script paths on every pass, and each computation
# runs the root resolver.
PW_ROOTS=''
PW_ROOTS_DONE=0
cache_roots() {
  [ "$PW_ROOTS_DONE" = 1 ] && return 0
  PW_ROOTS=$(planwright_roots)
  PW_ROOTS_DONE=1
}

# installed_planwright_roots: arm 5's raw (uncanonicalized) candidates, from the
# sibling resolver the stream-json launch preflight reads too — one computation
# of "which roots does a worker run scripts from", so the launcher's proof and
# this hook's trust can never disagree again. Its jq read is the same dependency
# the payload read already has; absent the resolver or jq it yields nothing,
# never a guess.
installed_planwright_roots() {
  [ -n "${HOOK_SELF_ROOT:-}" ] || return 0
  [ -r "$HOOK_SELF_ROOT/scripts/resolve-installed-roots.sh" ] || return 0
  /bin/sh "$HOOK_SELF_ROOT/scripts/resolve-installed-roots.sh" 2>/dev/null || :
}

# is_planwright_script <path> <cwd>: 0 when <path> is a `.sh` under the
# `scripts/` directory of a resolved planwright installation root (REQ-A1.5,
# REQ-A1.10). This is the installed-plugin twin of is_repo_script: a dispatched
# worker runs planwright's OWN scripts from wherever the plugin is installed,
# which is outside the repo checkout and so can never satisfy repo containment.
# `tests/` is deliberately NOT trusted here (an install ships no tests/), keeping
# this addition strictly narrower than the repo case.
is_planwright_script() {
  local p=$1 cwd=$2 root full rel
  case $p in
    *.sh) ;;
    *) return 1 ;;
  esac
  cache_roots
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    full=$(canon_under "$p" "$cwd" "$root") || continue
    [ ! "$full" -ef "$root/scripts/tower-force-push.sh" ] || return 1
    rel=${full#"$root"/}
    case $rel in
      scripts/*)
        # A root that is a git checkout (a tower or mission control run from
        # one) lies outside the worktree, where the file tools still write,
        # so it is held to what its HEAD commits, as the repository is. A
        # root that is no checkout of its own is an install copy.
        [ -e "$root/.git" ] || return 0
        [ "$(git_plain -C "$root" rev-parse --show-toplevel 2>/dev/null)" = "$root" ] || return 1
        committed_blob "$root" "$rel" "$full"
        return
        ;;
    esac
  done <<EOF
$PW_ROOTS
EOF
  return 1
}

# is_trusted_script <path> <cwd>: the trusted-script union — repo checkout code
# (scripts/ or tests/) or an installed planwright root's scripts/.
is_trusted_script() {
  # The force-push path is the tower's (doctrine/human-gates.md): never
  # approved for a worker, under any casing a case-insensitive filesystem runs.
  case ${1##*/} in
    [Tt][Oo][Ww][Ee][Rr]-[Ff][Oo][Rr][Cc][Ee]-[Pp][Uu][Ss][Hh].[Ss][Hh]) return 1 ;;
    # The router runs whatever follows its `--`: only strip_compute_route
    # approves it, and only for a command the guard approves on its own.
    [Cc][Oo][Mm][Pp][Uu][Tt][Ee]-[Rr][Oo][Uu][Tt][Ee].[Ss][Hh]) return 1 ;;
  esac
  # A hardlink of the helper is refused by each arm, against the root the path
  # resolves under.
  is_repo_script "$1" "$2" || is_planwright_script "$1" "$2"
}

# --------------------------------------------------------------------------
# The step scripts (REQ-F1.12). A record whose times a worker sets by hand
# can make a step that never ran read as run, so the guard approves only the
# calls that leave the times to the scripts, on the session's own step cache.
# A call is read as the script path, at most one two-word `--worktree <dir>`,
# then the verb; every word must be the literal the script will see.

# step_script_kind <path>: 0 when the trusted script <path> is a step script,
# its kind left in STEP_KIND (`record` or `run`): by name under any casing a
# case-insensitive filesystem runs, or as a link of a trusted root's copy.
step_script_kind() {
  local p=$1 root
  lower "${p##*/}"
  case $LOWER in
    step-record.sh)
      STEP_KIND=record
      return 0
      ;;
    step-run.sh)
      STEP_KIND=run
      return 0
      ;;
  esac
  case $p in
    /*) ;;
    *) p=$HOOK_CWD/$p ;;
  esac
  cache_roots
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    if [ "$p" -ef "$root/scripts/step-record.sh" ]; then
      STEP_KIND=record
      return 0
    fi
    if [ "$p" -ef "$root/scripts/step-run.sh" ]; then
      STEP_KIND=run
      return 0
    fi
  done <<EOF
$PW_ROOTS
EOF
  return 1
}

# step_call_ok <index>: the step-script call whose script path is word
# <index> of the current simple command, STEP_KIND set, is one REQ-F1.12
# passes.
step_call_ok() {
  local i=$1 j wt='' given=0 verb
  for ((j = i; j < cwn; j++)); do
    [ -z "${csub[j]-}" ] || return 1
    word_unresolved "${cw[j]}" "${cdyn[j]}" "${cglob[j]}" "${cx[j]}" && return 1
  done
  j=$((i + 1))
  if [ "${cw[j]-}" = --worktree ]; then
    [ $((j + 1)) -lt "$cwn" ] || return 1
    wt=${cw[j + 1]}
    given=1
    j=$((j + 2))
  fi
  [ "$j" -lt "$cwn" ] || return 1
  verb=${cw[j]}
  # It reads no worktree or file, so no cache to keep it to.
  [ "$STEP_KIND:$verb" != record:args-digest ] || return 0
  step_own_cache_ok "$given" "$wt" || return 1
  case $STEP_KIND:$verb in
    record:write) step_write_ok $((j + 1)) ;;
    # The script checks the source against the session's own events.
    record:supersede) step_has_word $((j + 1)) --source ;;
    record:render | record:list | record:lookup | record:heads | record:untrue | record:fingerprint) ;;
    record:new-run | record:regenerate | record:status) ;;
    record:excerpt) [ $((j + 2)) -eq "$cwn" ] && step_excerpt_ok "${cw[j + 1]}" ;;
    # Their records are timed by the script itself.
    run:resolve | run:audit | run:command | run:begin | run:end | run:resume | run:refire) ;;
    *) return 1 ;;
  esac
}

# step_own_cache_ok <given> <dir>: the call works on the recorded worktree's
# cache: a given `--worktree` is a plain absolute path canonically that
# worktree; an absent one leaves the script to find the git top level from
# the session's directory, which must then lie in the worktree's own
# repository. A step-context WORKTREE is held to the same worktree where
# step_context_value_ok reads it.
step_own_cache_ok() {
  local here
  [ -n "$REC_WT" ] || return 1
  if [ "$1" = 1 ]; then
    bare_abs_path_ok "$2" || return 1
    case $2/ in
      */./* | */../* | *//*/*) return 1 ;;
    esac
    [ "$(cd -- "$2" 2>/dev/null && pwd -P)" = "$REC_WT" ]
    return
  fi
  here=$(cd "$HOOK_CWD" 2>/dev/null && pwd -P) || return 1
  case $here/ in
    "$REC_WT"/*) ;;
    *) return 1 ;;
  esac
  own_unit_same_repo "$here"
}

# step_write_ok <index>: the write from word <index> on is a --completion
# write setting no time: a step, re-fire or full-suite write gives --start.
step_write_ok() {
  local j c=0
  for ((j = $1; j < cwn; j++)); do
    case ${cw[j]} in
      --completion) c=1 ;;
      --start | --end | --start=* | --end=*) return 1 ;;
    esac
  done
  [ "$c" = 1 ]
}

# step_has_word <index> <word>: <word> is one of the words from <index> on.
step_has_word() {
  local j
  for ((j = $1; j < cwn; j++)); do
    [ "${cw[j]}" != "$2" ] || return 0
  done
  return 1
}

# step_excerpt_ok <file>: <file> canonicalizes inside the recorded worktree
# or scratch root, never through a symlinked leaf.
step_excerpt_ok() {
  local f=$1 d b full root
  case $f in
    /*) ;;
    *) f=$HOOK_CWD/$f ;;
  esac
  b=${f##*/}
  case $b in
    '' | . | ..) return 1 ;;
  esac
  d=$(cd "${f%/*}/" 2>/dev/null && pwd -P) || return 1
  full=${d%/}/$b
  [ ! -L "$full" ] || return 1
  for root in "$REC_WT" "$REC_SCRATCH"; do
    [ -n "$root" ] || continue
    case $full in
      "$root"/*) return 0 ;;
    esac
  done
  return 1
}

# is_contained_file <path> <cwd>: 0 when <path> canonicalizes inside the repo
# and is a file HEAD commits there unchanged (used for `bats <file>`, which need
# not sit under scripts/ or tests/, and which stays REPO-scoped — an install
# ships no test files to run). A directory operand fails, since bats would run
# whatever files it holds.
is_contained_file() {
  local root full
  root=$(repo_root_of "$2") || return 1
  full=$(canon_under "$1" "$2" "$root") || return 1
  committed_blob "$root" "${full#"$root"/}" "$full"
}

# --------------------------------------------------------------------------
# The spec-root write zone (custom-spec-location D-15, REQ-E1.7). A dispatcher
# whose spec root lies in another repository than the work repository, or in
# none, computes that root once and hands it to the worker's environment as
# PLANWRIGHT_WORKER_SPEC_ROOT (scripts/worker-spec-root.sh); the guard reads it
# once at load (SPEC_ZONE below) and never resolves config per call. Inside
# it, and nowhere else, the guard approves the few write shapes a halting
# worker's store write takes: a `>`/`>>` redirect of an otherwise approved
# command (or of none, as a bare `> f`), `tee [-a]`, and `mkdir [-p]`. A write
# anywhere else, the work repository included, still defers as before.
#
# in_spec_zone <path> <cwd>: 0 when <path> is a plain literal (no expansion,
# glob, or quoting can hide in the charset) that canonicalizes inside a
# directory under the zone: a bundle (one holding requirements.md) or a
# reserved underscore directory, never the root's own top level, and never
# through a dot-led component (.git, .claude, a lock or marker directory). An
# existing leaf must be a regular file with one link, or a directory, so a
# write cannot travel through a symlink or a hard link to a file outside.
in_spec_zone() {
  local p=$1 cwd=$2 full rel top
  [ -n "$SPEC_ZONE" ] && [ "$IN_SUBST" = 0 ] || return 1
  case $p in
    '' | -* | *[!A-Za-z0-9._/@+-]*) return 1 ;;
  esac
  full=$(canon_under "$p" "$cwd" "$SPEC_ZONE") || return 1
  rel=${full#"$SPEC_ZONE"/}
  case /$rel/ in
    */.*) return 1 ;;
  esac
  case $rel in
    */*) top=${rel%%/*} ;;
    *) return 1 ;;
  esac
  case $top in
    _[a-z0-9]*) ;;
    [a-z0-9]*) [ -f "$SPEC_ZONE/$top/requirements.md" ] || return 1 ;;
    *) return 1 ;;
  esac
  case $top in
    *[!a-z0-9_-]*) return 1 ;;
  esac
  if [ -e "$full" ]; then
    if [ -f "$full" ]; then
      [ "$(find "$full" -maxdepth 0 -links 1 2>/dev/null)" = "$full" ] || return 1
    elif [ ! -d "$full" ]; then
      return 1
    fi
  fi
  ARM_ACT=1
  return 0
}

# spec_zone_redirect <op> <operand>: 0 for a file-writing `>`/`>>` (an fd
# number before it allowed) whose target is in the zone.
spec_zone_redirect() {
  local bare=$1
  while :; do
    case $bare in
      [0-9]*) bare=${bare#?} ;;
      *) break ;;
    esac
  done
  case $bare in
    '>' | '>>') in_spec_zone "$2" "$HOOK_CWD" ;;
    *) return 1 ;;
  esac
}

# guard_tee / guard_mkdir: at least one operand, every operand a zone path
# or one a policy arm admits (ob_path); the only flag `-a` (append) for
# tee and `-p` for mkdir, so no mode, context, or ignore flag changes what
# lands.
guard_tee() {
  local i a ends=0 operands=0 ob=0
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    if [ "$ends" = 0 ]; then
      case $a in
        -a | --append) continue ;;
        --)
          ends=1
          continue
          ;;
        -*) return 1 ;;
      esac
    fi
    if ! in_spec_zone "$a" "$HOOK_CWD"; then
      wr_live && ob_path "$a" leaf write || return 1
      ob=1
    fi
    operands=$((operands + 1))
  done
  [ "$operands" -ge 1 ] || return 1
  [ "$ob" = 0 ] || ob_mark write
}

guard_mkdir() {
  local i a ends=0 operands=0 ob=0 mode=leaf
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    if [ "$ends" = 0 ]; then
      case $a in
        -p | --parents)
          mode=parents
          continue
          ;;
        --)
          ends=1
          continue
          ;;
        -*) return 1 ;;
      esac
    fi
    if ! in_spec_zone "$a" "$HOOK_CWD"; then
      wr_live && ob_path "$a" "$mode" write || return 1
      ob=1
    fi
    operands=$((operands + 1))
  done
  [ "$operands" -ge 1 ] || return 1
  [ "$ob" = 0 ] || ob_mark write
}

# --------------------------------------------------------------------------
# The session record. The launcher resolves the
# self-approval policy, the unit branch, the worktree root, the PR base, the
# base-merge gate, and the scratch root once, writes them to a record outside
# the worktree
# (scripts/worker-session-record.sh), and hands its path in as
# PLANWRIGHT_WORKER_SESSION_RECORD. The guard reads them from there and never
# from live config or the checkout, so neither a Write to an overlay nor a
# `git switch` changes what it approves. A field that is missing, repeated, or
# outside its grammar is dropped, disabling whatever reads it: the
# policy reads as the empty list, and without the worktree root and unit
# branch neither the own-branch arm nor a `cd` approves anything, and without
# the scratch root the scratch arm approves nothing. The scratch root must be
# this user's own canonical directory, apart from the worktree in both
# directions. A record that is unreadable, not this user's own regular file,
# or inside the worktree or the scratch root it describes is no record.
#
# The audit-log home must be this user's own writable canonical directory,
# apart from the worktree and the scratch root in both directions, and the
# session's log there (audit_append) a regular file or absent. Without one,
# the policy drops both write arms, so neither approves a write with no log.
REC_POLICY=''
REC_UNIT=''
REC_WT=''
REC_BASE=''
REC_BASE_MERGE=''
REC_SCRATCH=''
REC_AUDIT_LOG=''
# The launch's opt-ins to editing the worktree's own trusted names, as the
# letters ob_excluded_name and ob_tree_clean read: m (the record's mise_task_edit=1, the mise
# task files), l (lefthook_edit=1, the lefthook config).
REC_OPEN=''
# The repository's declared check commands, `;` separated, as the launcher
# resolved worker_check_commands; see check_command_ok. The length bound is
# scripts/worker-session-record.sh's (they change together), which keeps the
# record under the size every record reader accepts.
REC_CHECKS=''
readonly MAX_CHECKS_LEN=2048

# rec_unit_branch_ok <name>: a task or flight branch, in policy-guard.sh's
# grammar (is_unit_branch) narrowed to flight names carrying the id every
# launcher mints; a protected branch never matches it.
rec_unit_branch_ok() {
  local re_task='^planwright/[a-z0-9][a-z0-9-]*/task-[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$'
  local re_flight='^planwright/flight/[a-z0-9][a-z0-9-]*-[0-9a-f]{8}$'
  case $1 in
    planwright/flight/task-*) return 1 ;;
  esac
  [[ $1 =~ $re_task ]] || [[ $1 =~ $re_flight ]]
}

# rec_policy_norm <value>: the policy's members, or the empty list when any
# member is unknown.
rec_policy_norm() {
  local m out=''
  local -a members=()
  IFS=' ' read -r -a members <<<"$1"
  for m in ${members[@]+"${members[@]}"}; do
    case $m in
      own-branch | scratch) out="$out $m" ;;
      *) return 0 ;;
    esac
  done
  printf '%s' "${out# }"
}

session_record_load() {
  local p=${PLANWRIGHT_WORKER_SESSION_RECORD:-} line k v seen=' ' dup=' ' size dir
  local policy='' unit='' wt='' base='' bm='' sr='' ah='' log='' mt='' lh='' cc=''
  case $p in
    /?*) ;;
    *) return 0 ;;
  esac
  [ -f "$p" ] && [ ! -L "$p" ] && [ -r "$p" ] && [ -O "$p" ] || return 0
  size=$(wc -c <"$p" 2>/dev/null) || return 0
  [ "${size// /}" -le 4096 ] 2>/dev/null || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      *=*) ;;
      *) continue ;;
    esac
    k=${line%%=*}
    v=${line#*=}
    case $seen in
      *" $k "*) dup="$dup$k " ;;
    esac
    seen="$seen$k "
    case $k in
      policy) policy=$v ;;
      unit_branch) unit=$v ;;
      worktree_root) wt=$v ;;
      pr_base) base=$v ;;
      worker_base_merge) bm=$v ;;
      scratch_root) sr=$v ;;
      audit_log_home) ah=$v ;;
      mise_task_edit) mt=$v ;;
      lefthook_edit) lh=$v ;;
      check_commands) cc=$v ;;
    esac
  done <"$p"
  case $dup in *" policy "*) policy='' ;; esac
  case $dup in *" unit_branch "*) unit='' ;; esac
  case $dup in *" worktree_root "*) wt='' ;; esac
  case $dup in *" pr_base "*) base='' ;; esac
  case $dup in *" worker_base_merge "*) bm='' ;; esac
  case $dup in *" scratch_root "*) sr='' ;; esac
  case $dup in *" audit_log_home "*) ah='' ;; esac
  case $dup in *" mise_task_edit "*) mt='' ;; esac
  case $dup in *" lefthook_edit "*) lh='' ;; esac
  case $dup in *" check_commands "*) cc='' ;; esac
  case $cc in
    *[[:cntrl:]]*) cc='' ;;
  esac
  [ "${#cc}" -le "$MAX_CHECKS_LEN" ] || cc=''
  rec_unit_branch_ok "$unit" || unit=''
  case $wt in
    /?*) ;;
    *) wt='' ;;
  esac
  case $wt in
    *[[:cntrl:]]*) wt='' ;;
  esac
  if [ -n "$wt" ]; then
    [ -d "$wt" ] && [ -e "$wt/.git" ] && [ "$(cd "$wt" 2>/dev/null && pwd -P)" = "$wt" ] || wt=''
  fi
  case $base in
    [A-Za-z0-9]*/?*) ;;
    *) base='' ;;
  esac
  case $base in
    *[!A-Za-z0-9._/+@-]* | *..* | *//* | */ | *.lock | *.lock/* | */.* | *.) base='' ;;
  esac
  case ${base%%/*} in
    *[!A-Za-z0-9._-]*) base='' ;;
  esac
  case $bm in
    allow | deny) ;;
    *) bm='' ;;
  esac
  case $sr in
    /?*) ;;
    *) sr='' ;;
  esac
  case $sr in
    *[[:cntrl:]]*) sr='' ;;
  esac
  if [ -n "$sr" ]; then
    [ -d "$sr" ] && [ -O "$sr" ] && [ "$(cd "$sr" 2>/dev/null && pwd -P)" = "$sr" ] || sr=''
  fi
  if [ -n "$sr" ] && [ -n "$wt" ]; then
    case $sr/ in
      "$wt"/*) sr='' ;;
    esac
    case $wt/ in
      "$sr"/*) sr='' ;;
    esac
  fi
  # A record inside the worktree or the scratch root it describes is one the
  # worker can rewrite.
  dir=$(cd "$(dirname "$p")" 2>/dev/null && pwd -P) || return 0
  if [ -n "$wt" ]; then
    case $dir/ in
      "$wt"/*) return 0 ;;
    esac
  fi
  if [ -n "$sr" ]; then
    case $dir/ in
      "$sr"/*) return 0 ;;
    esac
  fi
  case $ah in
    /?*) ;;
    *) ah='' ;;
  esac
  case $ah in
    *[[:cntrl:]]*) ah='' ;;
  esac
  if [ -n "$ah" ]; then
    [ -d "$ah" ] && [ -O "$ah" ] && [ -w "$ah" ] && [ "$(cd "$ah" 2>/dev/null && pwd -P)" = "$ah" ] || ah=''
  fi
  for k in "$wt" "$sr"; do
    [ -n "$ah" ] && [ -n "$k" ] || continue
    case $ah/ in
      "$k"/*) ah='' ;;
    esac
    case $k/ in
      "$ah"/*) ah='' ;;
    esac
  done
  # One log per record: the launch's own name for it.
  k=${p##*/}
  k=${k%.record}
  case $k in
    '' | .* | *[!A-Za-z0-9._-]*) ah='' ;;
  esac
  if [ -n "$ah" ]; then
    log=$ah/$k.log
    if [ -e "$log" ] || [ -L "$log" ]; then
      [ -f "$log" ] && [ ! -L "$log" ] && [ -O "$log" ] || log=''
    fi
  fi
  REC_AUDIT_LOG=$log
  REC_POLICY=''
  [ -z "$log" ] || REC_POLICY=$(rec_policy_norm "$policy")
  REC_UNIT=$unit
  REC_WT=$wt
  REC_BASE=$base
  REC_BASE_MERGE=$bm
  REC_SCRATCH=$sr
  REC_OPEN=''
  [ "$mt" != 1 ] || REC_OPEN=${REC_OPEN}m
  [ "$lh" != 1 ] || REC_OPEN=${REC_OPEN}l
  REC_CHECKS=''
  [ -z "$wt" ] || REC_CHECKS=$cc
}

# --------------------------------------------------------------------------
# The floor, checked for every simple command
# before any arm or declared step is considered: whatever a `Bash(…)` rule of
# the worker profile's deny block matches, and the reserved acts (any push, a
# rebase or branch reset, an amend, fixup, squash, or hook skip on a commit, a
# squash merge, and every `gh` act but the read-only ones the guard
# enumerates), are never approved, whatever the policy, the own-unit acts
# excepted (own_unit_act, below the floor). The arms below carry
# the rest of the floor themselves: a write target outside the worktree or
# inside an excluded path never passes ob_path.
#
# The deny rules come from the profile beside this guard
# (<root>/config/worker-settings.json, the file the launchers pass as
# --settings), compiled once per hook call with the documented matcher model
# (tests/lib/permission-matcher.sh, docs/permission-matcher-model.md): a
# trailing `:*` or ` *` matches at a word boundary, any other `*` anywhere.
# The subject is the command's words joined by single spaces, as written and
# again after substitution and the transparent prefixes, so the guard reads a
# match wherever Claude Code's matcher would and in more places. A profile
# that cannot be read, holds no Bash rule, or holds a malformed one leaves the
# guard approving nothing.
#
# This runs on every hook call, so the rules are escaped in one pass and a
# subject is tested against a rule's regex only when it starts with the
# rule's literal prefix (the glob before its first `*`), which every match
# must: bash recompiles a regex on each `=~`.
DENY_N=-1
DENY_RE=()
DENY_PRE=()

# deny_glob_ere <globs>: the globs as EREs in DENY_ERE, their metacharacters
# escaped and each `*` read as `.*`. The escape is per character, so a
# newline-separated block of globs escapes in one pass.
deny_glob_ere() {
  local g=$1 c
  for c in "\\" '.' '+' '?' '(' ')' '[' ']' '{' '}' '^' '$' '|'; do
    g=${g//"$c"/\\$c}
  done
  DENY_ERE=${g//\*/.*}
}

# deny_load: compile the rules main's payload read took from the profile
# (DENY_SRC `ok`, DENY_RULES one per line); `none` (no readable profile) and
# `err` (no deny array) leave nothing compiled.
DENY_SRC=none
DENY_RULES=''
deny_load() {
  local rule pat globs='' tails='' n=0 i
  local -a eres=()
  DENY_N=0
  DENY_RE=()
  DENY_PRE=()
  [ "$DENY_SRC" = ok ] || return 1
  while IFS= read -r rule; do
    case $rule in
      'Bash('*')') ;;
      Bash*) return 1 ;;
      *) continue ;;
    esac
    pat=${rule#Bash(}
    pat=${pat%)}
    case $pat in
      *':*') pat="${pat%:\*} *" ;;
    esac
    case $pat in
      *' *')
        pat=${pat% \*}
        tails+=w
        ;;
      *) tails+=x ;;
    esac
    globs+=$pat$'\n'
    DENY_PRE[n]=${pat%%\**}
    n=$((n + 1))
  done <<EOF
$DENY_RULES
EOF
  [ "$n" -gt 0 ] || return 0
  deny_glob_ere "$globs"
  # A read loop, not mapfile: bash 3.2 (the macOS /bin/bash) has no mapfile.
  while IFS= read -r rule; do
    eres+=("$rule")
  done <<<"${DENY_ERE%$'\n'}"
  [ "${#eres[@]}" -eq "$n" ] || return 1
  for ((i = 0; i < n; i++)); do
    if [ "${tails:i:1}" = w ]; then
      DENY_RE[i]="^${eres[i]}( .*)?\$"
    else
      DENY_RE[i]="^${eres[i]}\$"
    fi
  done
  DENY_N=$n
}

# deny_hit <word>...: 0 when the words, joined by single spaces, match a deny
# rule, or when the rules could not be read.
deny_hit() {
  local IFS=' ' subject i
  subject="$*"
  [ "$DENY_N" -ge 0 ] || deny_load
  [ "$DENY_N" -gt 0 ] || return 0
  for ((i = 0; i < DENY_N; i++)); do
    [[ $subject == "${DENY_PRE[i]}"* ]] || continue
    [[ $subject =~ ${DENY_RE[i]} ]] && return 0
  done
  return 1
}

# floor_act: 0 when the current simple command (`cw`) is a reserved act. The
# program is matched by its last path component, since a declared step names
# it by absolute path.
floor_act() {
  local i a sub=''
  [ "$cwn" -ne 2 ] || [ "${cw[1]}" != --version ] || return 1
  case ${cw[0]##*/} in
    git)
      # A leading `-C <dir>` is read past: guard_git admits it for a read,
      # and every verb after it is weighed as it would be without it.
      i=1
      [ "${cw[1]-}" != -C ] || [ "$cwn" -lt 4 ] || i=3
      for (( ; i < cwn; i++)); do
        case ${cw[i]} in
          -*) return 0 ;; # any other global option: never approved, so never weighed
        esac
        sub=${cw[i]}
        break
      done
      case $sub in
        push | rebase | reset | filter-branch | filter-repo) return 0 ;;
      esac
      for ((i = i + 1; i < cwn; i++)); do
        a=${cw[i]}
        case $sub:$a in
          *:--) break ;;
          commit:--amend | commit:--fixup* | commit:--squash* | commit:--no-verify | commit:--no-veri* | merge:--squash) return 0 ;;
          commit:--*) ;;
          commit:-?*) short_flag_hit "$a" 'n' 'mFcCtuS' && return 0 ;;
        esac
      done
      ;;
    gh) guard_gh || return 0 ;;
  esac
  return 1
}

# floor_act_words <word>...: floor_act over the given words, for a line read
# before substitution (a declared step's).
floor_act_words() {
  local -a cw=("$@")
  local cwn=$#
  floor_act
}

# --------------------------------------------------------------------------
# The own-unit acts: three a session may run on its own unit that no other
# arm approves (the push and the edit being floor acts), approved whatever
# the record's policy, but only under a record carrying the unit branch, the
# worktree root and a usable audit log, with the session's directory in that
# worktree's own repository, for the session's own command at the top level
# (never inside a substitution, a `fish -c` string, a loop, an if or case
# body, a pipeline or a background job, the whole and-or list a later `&`
# backgrounds included, nor after `||`), with no redirect,
# prefix or leading assignment, and no later re-assignment of a name an
# approved export set:
#   export PLANWRIGHT_STEP_<field>=<literal>...   the step context, its
#       values held to strip_step_context's rules and its worktree, when
#       given, canonically the recorded one;
#   gh pr edit <n> --body-file <file>   <n> the open, same-repository pull
#       request whose head is the unit branch, as one bounded `gh pr view`
#       read from the session's directory says, and <file> a regular file
#       canonically inside the recorded scratch root;
#   git push origin <unit> | git push origin <unit>:<unit>   nothing else.
# Every word but the body file is a bare literal as written. Anything else
# is left to the floor, which reserves it as before.

# own_unit_candidate: the unsubstituted words (`sw`) open one of the
# reserved own-unit acts, so verify_simple defers its floor to
# verify_known_simple's exact check.
own_unit_candidate() {
  [ "${sw[0]-}" = git ] && [ "${sw[1]-}" = push ] && return 0
  [ "${sw[0]-}" = gh ] && [ "${sw[1]-}" = pr ] && [ "${sw[2]-}" = edit ]
}

# own_unit_words_bare <from> <to>: words <from>..<to>-1 are bare literals,
# unchanged by any expansion.
own_unit_words_bare() {
  local i
  for ((i = $1; i < $2; i++)); do
    [ "${swq[i]}" -lt 0 ] && [ "${cw[i]}" = "${sw[i]}" ] || return 1
    word_unresolved "${cw[i]}" "${cdyn[i]}" "${cglob[i]}" "${cx[i]}" && return 1
  done
  return 0
}

# own_unit_act: 0 when the current simple command, after the tracked
# assignments are resolved, is exactly one own-unit act.
own_unit_act() {
  local i here
  case ${cw[0]-} in
    export | git | gh) ;;
    *) return 1 ;;
  esac
  [ "$HOOK_DEPTH" -eq 0 ] && [ "$IN_SUBST" = 0 ] && [ "$SCOPED_RD" = 0 ] && [ "$OUTSIDE_CD" = 0 ] || return 1
  # Top level and unconditional: no loop, if or case body, no pipeline, no
  # background job, and not run only on an earlier failure. `seg_open`,
  # `close` and `ctl_depth` are verify_tokens' and fin's walk state.
  [ "${ctl_depth:-1}" -eq 0 ] && [ "${ou_or:-1}" = 0 ] && [ "${ou_pipe:-1}" = 0 ] || return 1
  case ${seg_open-x}:${close-x} in
    :* | ';':* | '&&':*) ;;
    *) return 1 ;;
  esac
  case ${close-x} in
    ';' | '&&' | '||' | end) ;;
    *) return 1 ;;
  esac
  [ "$rn" -eq 0 ] && [ "$cwn" -eq "$swn" ] && [ "$cwn" -ge 2 ] || return 1
  [ -n "$REC_UNIT" ] && [ -n "$REC_WT" ] && [ -n "$REC_AUDIT_LOG" ] || return 1
  for ((i = 0; i < cwn; i++)); do
    [ -z "${csub[i]-}" ] || return 1
  done
  here=$(cd "$HOOK_CWD" 2>/dev/null && pwd -P) || return 1
  case $here/ in
    "$REC_WT"/*) ;;
    *) return 1 ;;
  esac
  deny_hit "${cw[@]}" && return 1
  case ${cw[0]} in
    export)
      own_step_export_ok && own_unit_same_repo "$here" || return 1
      OU_EXPORTED=1
      for ((i = 1; i < cwn; i++)); do
        OU_EXP_NAMES="$OU_EXP_NAMES ${cw[i]%%=*}"
      done
      ;;
    git) own_push_ok && own_unit_same_repo "$here" ;;
    gh) own_unit_same_repo "$here" && own_pr_edit_ok "$here" ;;
    *) return 1 ;;
  esac
}

# own_unit_same_repo <canonical dir>: under the worktree path is not enough,
# since a nested repository or a .git pointing elsewhere is another
# repository with its own origin. Decided from the path alone, with no git
# run there, whose config a nested repository's author controls: no .git
# entry of any kind between <dir> and the worktree root.
own_unit_same_repo() {
  local d=$1
  while [ "$d" != "$REC_WT" ]; do
    [ ! -e "$d/.git" ] && [ ! -L "$d/.git" ] || return 1
    d=${d%/*}
    case $d/ in
      "$REC_WT"/*) ;;
      *) return 1 ;;
    esac
  done
}

own_step_export_ok() {
  local i w f v
  own_unit_words_bare 0 "$cwn" || return 1
  # A step name the command assigned earlier, exported or not, could reach
  # the step call around the checks below.
  for ((i = 0; i < VAR_C; i++)); do
    case ${VAR_N[i]} in
      PLANWRIGHT_STEP_*) return 1 ;;
    esac
  done
  for ((i = 1; i < cwn; i++)); do
    w=${cw[i]}
    case $w in
      PLANWRIGHT_STEP_?*=*) ;;
      *) return 1 ;;
    esac
    f=${w%%=*}
    # Exporting a name an earlier own-unit export set is a re-assignment.
    case "$OU_EXP_NAMES " in
      *" $f "*) return 1 ;;
    esac
    f=${f#PLANWRIGHT_STEP_}
    case " $STEP_CONTEXT_FIELDS " in
      *" $f "*) ;;
      *) return 1 ;;
    esac
    v=${w#*=}
    case $v in
      *[!A-Za-z0-9._/:@%,+-]*) return 1 ;;
    esac
    step_context_value_ok "$f" "$v" || return 1
  done
  return 0
}

own_push_ok() {
  [ "$cwn" -eq 4 ] && own_unit_words_bare 0 4 || return 1
  [ "${cw[1]}" = push ] && [ "${cw[2]}" = origin ] || return 1
  case ${cw[3]} in
    "$REC_UNIT" | "$REC_UNIT:$REC_UNIT") return 0 ;;
  esac
  return 1
}

# own_pr_edit_ok <canonical cwd>
own_pr_edit_ok() {
  local n f d out
  [ "$cwn" -eq 6 ] && own_unit_words_bare 0 5 || return 1
  [ "${cw[1]}" = pr ] && [ "${cw[2]}" = edit ] && [ "${cw[4]}" = --body-file ] || return 1
  n=${cw[3]}
  [[ $n =~ ^[1-9][0-9]{0,8}$ ]] || return 1
  [ -n "$REC_SCRATCH" ] && [ "${swq[5]}" -lt 0 ] || return 1
  f=${cw[5]}
  # The recorded `$TMPDIR` names the scratch root under every policy here,
  # as the launcher exported it; the scratch arm already resolved it when
  # in force.
  if [ "$HOOK_TMPDIR_IS_SCRATCH" = 1 ]; then
    # shellcheck disable=SC2016 # the unexpanded spelling is what is matched
    case $f in
      '$TMPDIR/'*) f=$REC_SCRATCH/${f#'$TMPDIR/'} ;;
      '${TMPDIR}/'*) f=$REC_SCRATCH/${f#'${TMPDIR}/'} ;;
    esac
  fi
  case $f in
    /*) ;;
    *) return 1 ;;
  esac
  case $f in
    *[!A-Za-z0-9._/@%,+:=-]* | */./* | */../* | */.. | */.) return 1 ;;
  esac
  [ -f "$f" ] && [ ! -L "$f" ] && [ -r "$f" ] || return 1
  d=$(cd "${f%/*}" 2>/dev/null && pwd -P) || return 1
  case $d/ in
    "$REC_SCRATCH"/*) ;;
    *) return 1 ;;
  esac
  # The read is bounded by the runner beside this guard, so a hung forge
  # defers instead of outlasting the hook's timeout.
  [ -n "$HOOK_SELF_ROOT" ] && [ -r "$HOOK_SELF_ROOT/scripts/bounded-run.sh" ] || return 1
  out=$(cd -- "$1" && /bin/sh "$HOOK_SELF_ROOT/scripts/bounded-run.sh" 15 \
    env GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 GH_PAGER=cat \
    gh pr view "$n" --json headRefName,isCrossRepository,state 2>/dev/null </dev/null) || return 1
  [ "${#out}" -le 4096 ] || return 1
  printf '%s' "$out" | jq -e --arg b "$REC_UNIT" \
    'type == "object" and .headRefName == $b and .isCrossRepository == false and .state == "OPEN"' >/dev/null 2>&1
}

# --------------------------------------------------------------------------
# The own-branch arm: live only when the
# record's policy names it and the record carries the unit branch and the
# worktree root, the payload directory lies inside that root, and the command
# is the session's own (never inside a substitution or a `fish -c` string).
# It approves file writes whose every target canonicalizes inside the worktree
# and outside the excluded paths (ob_path), and the git acts that keep to the
# unit branch (ob_git). A write never travels through a symlink, a `..`, or an
# existing file with a second hard link. A segment that can leave a symlink
# behind (a recursive copy, a move, a checkout, restore, or merge) is the only
# writer its command may hold: the targets are checked before the command
# runs, so a write after it could follow a link it created (ob_mark).
#
# The scratch arm: live when the record's policy names it, the record carries
# a usable scratch root, and the TMPDIR the hook inherited names that root
# (HOOK_TMPDIR_IS_SCRATCH), for the session's own command wherever its
# payload directory lies. It approves the same file writers under the same
# flag, symlink, `..`, hard-link, and link-creation rules, plus `mktemp`,
# whose every target canonicalizes strictly inside the scratch root and
# outside the trusted names ob_excluded_name lists, and resolves a literal
# `$TMPDIR` to that root (analyze_command). The root comes from the record;
# the inherited TMPDIR only has to agree with it. Nothing there is ever
# trusted to run: the script runners admit only repository and
# installed-plugin code.
OB_ON=0
SC_ON=0
OB_WROTE=0
OB_LINKY=0
OB_EXCL_STATE=0
OB_EXCL_DIRS=''

ob_live() {
  [ "$OB_ON" = 1 ] && [ "$IN_SUBST" = 0 ] && [ "$HOOK_DEPTH" -eq 0 ]
}

sc_live() {
  [ "$SC_ON" = 1 ] && [ "$IN_SUBST" = 0 ] && [ "$HOOK_DEPTH" -eq 0 ]
}

# wr_live: a policy arm that approves file writes is live.
wr_live() {
  ob_live || sc_live
}

# ob_mark <write|link>: record an approved write, or a link-capable segment
# (itself a write); 1 when the command already holds what that conflicts with.
ob_mark() {
  [ "$OB_LINKY" = 0 ] || return 1
  case $1 in
    write) OB_WROTE=1 ;;
    link)
      [ "$OB_WROTE" = 0 ] || return 1
      OB_LINKY=1
      ;;
  esac
}

# lower <text>: the text with A-Z lowercased into LOWER, as `tr` does under
# the C locale, without a fork: a fork that failed would leave an empty
# string, which matches no excluded name and so would admit the path.
lower() {
  local s=$1 out='' c k i u=ABCDEFGHIJKLMNOPQRSTUVWXYZ l=abcdefghijklmnopqrstuvwxyz
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      [A-Z])
        # Under nocasematch the pattern also takes a lowercase letter, which
        # the prefix strip then finds nowhere.
        k=${u%%"$c"*}
        [ "${#k}" -ge 26 ] || c=${l:${#k}:1}
        ;;
    esac
    out=$out$c
  done
  LOWER=$out
}

# canon_loose <abs>: the canonical form of an absolute path whose trailing
# components may not exist yet.
canon_loose() {
  local p=$1 tail='' c
  while [ ! -d "$p" ]; do
    [ "$p" != / ] && [ -n "$p" ] || return 1
    tail=/${p##*/}$tail
    p=${p%/*}
    [ -n "$p" ] || p=/
  done
  c=$(cd "$p" 2>/dev/null && pwd -P) || return 1
  printf '%s' "${c%/}$tail"
}

# ob_excl_load: the git directory, the common directory, and the hooks
# directory git runs from (core.hooksPath or the default), canonical and
# lowercased (a case-insensitive filesystem reaches them under any casing),
# into OB_EXCL_DIRS. Non-zero when git cannot name them, which refuses every
# own-branch write.
ob_excl_load() {
  local raw line c out=''
  case $OB_EXCL_STATE in
    1) return 0 ;;
    2) return 1 ;;
  esac
  OB_EXCL_STATE=2
  raw=$(git -C "$REC_WT" rev-parse --path-format=absolute --git-dir --git-common-dir --git-path hooks 2>/dev/null) || return 1
  while IFS= read -r line; do
    case $line in
      /*) ;;
      *) return 1 ;;
    esac
    c=$(canon_loose "$line") || return 1
    out="$out$c$NL"
  done <<EOF
$raw
EOF
  [ -n "$out" ] || return 1
  lower "$out"
  OB_EXCL_DIRS=$LOWER
  OB_EXCL_STATE=1
}

# ob_excluded_name <component> [<open>]: the names a tool runs or trusts
# without a further prompt, matched case-insensitively at any depth, since
# mise reads a config from whatever directory it starts in. <open> is REC_OPEN
# or a subset of it: with `m`, the four task-file names (mise.toml, .mise.toml,
# mise-tasks, .mise-tasks) are let through; with `l`, the lefthook config
# names (lefthook, lefthook.*; lefthook-local.* and the dotted variants stay
# excluded). Only the worktree zone of an opted-in session asks for either.
ob_excluded_name() {
  local low
  lower "$1"
  low=$LOWER
  case ${2:-} in
    *m*)
      case $low in
        mise.toml | .mise.toml | mise-tasks | .mise-tasks) return 1 ;;
      esac
      ;;
  esac
  case ${2:-} in
    *l*)
      case $low in
        lefthook | lefthook.*) return 1 ;;
      esac
      ;;
  esac
  case $low in
    .git | .claude | .envrc | .tool-versions | .config | .mise | mise.toml | .mise.toml | mise.*.toml | .mise.*.toml | .miserc*.toml | mise-tasks | .mise-tasks | mise*.lock | lefthook | lefthook.* | lefthook-local.* | .lefthook | .lefthook.* | .lefthook-local | .lefthook-local.*) return 0 ;;
  esac
  return 1
}

# ob_excluded_mise_child <component>: the entries of a `mise/` directory mise
# loads, matched case-insensitively. Anything else there is never read.
ob_excluded_mise_child() {
  local low
  lower "$1"
  low=$LOWER
  case $low in
    config*.toml | miserc*.toml | conf.d | tasks) return 0 ;;
  esac
  return 1
}

# ob_excluded_rel <relative-path> <root> [<open>]: 0 when a component of the path
# under <root> is an excluded name, a `mise/` entry mise loads (the root's own
# name counting as its parent), or the last component is `mise` itself:
# moving a directory onto that name would turn its config.toml or conf.d into
# loaded config without any name inside it matching.
ob_excluded_rel() {
  local comp prev last=''
  local -a comps=()
  lower "${2##*/}"
  prev=$LOWER
  IFS=/ read -r -a comps <<<"$1"
  for comp in ${comps[@]+"${comps[@]}"}; do
    case $comp in
      '' | .) continue ;;
    esac
    ob_excluded_name "$comp" "${3:-}" && return 0
    if [ "$prev" = mise ] && ob_excluded_mise_child "$comp"; then
      return 0
    fi
    lower "$comp"
    prev=$LOWER
    last=$prev
  done
  [ "$last" = mise ]
}

# ob_excluded <canonical-path>: 0 when the path is, or lies under, an excluded
# path.
ob_excluded() {
  local full=$1 low d
  ob_excl_load || return 0
  lower "$full"
  low=$LOWER
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    case $low/ in
      "$d"/*) return 0 ;;
    esac
  done <<EOF
$OB_EXCL_DIRS
EOF
  ob_excluded_rel "${full#"$REC_WT"/}" "$REC_WT" "$REC_OPEN"
}

# ob_tree_clean <canonical-dir> [<open>]: 0 when nothing under the directory is
# an excluded path, for a recursive act on it. <open> is ob_excluded_name's:
# the opt-in names let through, given only where the act lands in the worktree.
ob_tree_clean() {
  local dir=$1 low d hit
  lower "$dir"
  low=$LOWER
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    case $d/ in
      "$low"/*) return 1 ;;
    esac
  done <<EOF
$OB_EXCL_DIRS
EOF
  # The same names ob_excluded_name lists (keep the two in step), as find
  # primaries, less the ones an opt-in lets through.
  local -a names=(-iname .git -o -iname .claude -o -iname .envrc -o -iname .tool-versions
    -o -iname .config -o -iname .mise
    -o -iname 'mise.*.toml' -o -iname '.mise.*.toml' -o -iname '.miserc*.toml'
    -o -iname 'mise*.lock' -o -ipath '*/mise/config*.toml'
    -o -ipath '*/mise/miserc*.toml' -o -ipath '*/mise/conf.d' -o -ipath '*/mise/tasks'
    -o -iname 'lefthook-local.*' -o -iname '.lefthook' -o -iname '.lefthook.*'
    -o -iname '.lefthook-local' -o -iname '.lefthook-local.*')
  case ${2:-} in
    *m*) ;;
    *) names+=(-o -iname mise.toml -o -iname .mise.toml -o -iname mise-tasks -o -iname .mise-tasks) ;;
  esac
  case ${2:-} in
    *l*) ;;
    *) names+=(-o -iname lefthook -o -iname 'lefthook.*') ;;
  esac
  hit=$(find "$dir" \( "${names[@]}" \) -print -quit 2>/dev/null) || return 1
  [ -z "$hit" ]
}

# ob_path <word> <mode> [<zones>]: 0 when <word> names a write target the
# arm admits, its canonical path left in OB_PATH and its zone (`wt` or `sc`)
# in OB_ZONE. The word must be a plain literal (no expansion, glob, tilde, or
# `..` can hide in the charset), absolute only when written under a zone's
# canonical root. <mode>: `leaf` (only the last component may be missing),
# `parents` (any trailing components may be, for `mkdir -p`), or `exists`.
# <zones>: `wt` (the default: the worktree), `write` (the zone of each live
# write arm), `read` (a copy's source: the worktree, and the scratch root
# under the scratch arm), or `sc` (the scratch root). No component may be a
# symlink; the target lies strictly inside a zone, outside every excluded path
# of the worktree, and, when it exists, is a directory or a regular file with
# one link.
ob_path() {
  local w=$1 mode=$2 zones=${3-wt} acc comp missing=0 wt_ok=0 sc_ok=0
  local -a comps=()
  OB_PATH=''
  OB_ZONE=''
  case $zones in
    wt | read) [ -z "$REC_WT" ] || wt_ok=1 ;;
    write) ! ob_live || wt_ok=1 ;;
  esac
  case $zones in
    read | write | sc) ! sc_live || sc_ok=1 ;;
  esac
  [ "$wt_ok$sc_ok" != 00 ] || return 1
  case $w in
    '' | -* | *[!A-Za-z0-9._/@+%,:-]*) return 1 ;;
  esac
  case /$w/ in
    */../*) return 1 ;;
  esac
  case $w in
    /*)
      if [ "$wt_ok" = 1 ] && [ "${w#"$REC_WT"/}" != "$w" ]; then
        acc=$REC_WT
      elif [ "$sc_ok" = 1 ] && [ "${w#"$REC_SCRATCH"/}" != "$w" ]; then
        acc=$REC_SCRATCH
      else
        return 1
      fi
      w=${w#"$acc"/}
      ;;
    *) acc=$(cd "$HOOK_CWD" 2>/dev/null && pwd -P) || return 1 ;;
  esac
  IFS=/ read -r -a comps <<<"$w"
  for comp in ${comps[@]+"${comps[@]}"}; do
    case $comp in
      '' | .) continue ;;
    esac
    if [ "$missing" = 1 ]; then
      [ "$mode" = parents ] || return 1
      acc=$acc/$comp
      continue
    fi
    acc=$acc/$comp
    [ -L "$acc" ] && return 1
    [ -e "$acc" ] || missing=1
  done
  [ "$missing" = 0 ] || [ "$mode" != exists ] || return 1
  if [ "$wt_ok" = 1 ] && [ "${acc#"$REC_WT"/}" != "$acc" ]; then
    ob_excluded "$acc" && return 1
    OB_ZONE=wt
  elif [ "$sc_ok" = 1 ] && [ "${acc#"$REC_SCRATCH"/}" != "$acc" ]; then
    # The trusted names stay closed here too: a tool started there would
    # read them as its own configuration. The root is the worker's TMPDIR,
    # so its mise/ is mise's own temporary directory.
    ob_excluded_rel "${acc#"$REC_SCRATCH"/}" "$REC_SCRATCH" && return 1
    lower "${acc#"$REC_SCRATCH"/}"
    case $LOWER in
      mise | mise/*) return 1 ;;
    esac
    OB_ZONE=sc
  else
    return 1
  fi
  if [ -e "$acc" ]; then
    if [ -f "$acc" ]; then
      [ "$(find "$acc" -maxdepth 0 -links 1 2>/dev/null)" = "$acc" ] || return 1
    elif [ ! -d "$acc" ]; then
      return 1
    fi
  fi
  OB_PATH=$acc
  case $OB_ZONE in
    wt) ! ob_live || { AUDIT_OB=1 && ARM_ACT=1 && OB_TOUCH=1; } ;;
    sc) AUDIT_SC=1 ARM_ACT=1 ;;
  esac
}

# ob_target <word> <mode> <recursive> [<zones>]: ob_path, and for a recursive
# act on a worktree directory, nothing excluded beneath it.
ob_target() {
  ob_path "$1" "$2" "${4-wt}" || return 1
  [ "$3" = 1 ] && [ "$OB_ZONE" = wt ] && [ -d "$OB_PATH" ] && ! ob_tree_clean "$OB_PATH" "$REC_OPEN" && return 1
  return 0
}

# ob_redirect <op> <target>: a file-writing redirect whose target the arm
# admits.
ob_redirect() {
  local bare=$1
  while :; do
    case $bare in
      [0-9]*) bare=${bare#?} ;;
      *) break ;;
    esac
  done
  case $bare in
    '>' | '>>' | '>|' | '&>' | '&>>') ;;
    *) return 1 ;;
  esac
  wr_live && ob_path "$2" leaf write && ob_mark write
}

# guard_rm: `rm` with the removal flags only (no `-i`, no
# `--no-preserve-root`); a recursive removal is checked below its target.
guard_rm() {
  local i a ends=0 rec=0 n=0
  wr_live || return 1
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    if [ "$ends" = 0 ]; then
      case $a in
        --)
          ends=1
          continue
          ;;
        --recursive)
          rec=1
          continue
          ;;
        --force | --verbose | --dir) continue ;;
        --*) return 1 ;;
        -?*)
          case ${a#-} in
            *[!rRfvd]*) return 1 ;;
          esac
          case $a in
            *[rR]*) rec=1 ;;
          esac
          continue
          ;;
      esac
    fi
    ob_target "$a" leaf "$rec" write || return 1
    n=$((n + 1))
  done
  [ "$n" -ge 1 ] && ob_mark write
}

guard_touch() {
  local i a ends=0 n=0
  wr_live || return 1
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    if [ "$ends" = 0 ]; then
      case $a in
        --)
          ends=1
          continue
          ;;
        --no-create) continue ;;
        --*) return 1 ;;
        -?*)
          case ${a#-} in
            *[!amc]*) return 1 ;;
          esac
          continue
          ;;
      esac
    fi
    ob_path "$a" leaf write || return 1
    n=$((n + 1))
  done
  [ "$n" -ge 1 ] && ob_mark write
}

# ob_copy_move <cp|mv> <recursive> <wt|write> <operand>...: the operand rule
# `cp` and `mv` share, over the worktree alone or the live write arms' zones.
# Every source exists inside a zone (a moved one is a target, so in a write
# zone; a copied one is read, so the worktree or, under the scratch arm, the
# scratch root); the destination is a new path, or an existing directory
# whose entry for each source is checked as the target. A directory copied
# or moved holds no excluded path, in either zone, an opt-in's names excepted
# when the destination is the worktree. A recursive copy lands only
# where nothing exists yet, so it never writes through an existing file.
ob_copy_move() {
  local verb=$1 rec=$2 zones=$3 n dst s b final src src_dir
  shift 3
  n=$#
  [ "$n" -ge 2 ] || return 1
  src=$zones
  [ "$zones" = wt ] || [ "$verb" = mv ] || src='read'
  dst=${!n}
  ob_path "$dst" leaf "$zones" || return 1
  local dst_dir=0
  [ -d "$OB_PATH" ] && dst_dir=1
  [ "$dst_dir" = 1 ] || [ "$n" -eq 2 ] || return 1
  while [ "$#" -gt 1 ]; do
    s=$1
    shift
    ob_path "$s" exists "$src" || return 1
    src_dir=''
    if [ -d "$OB_PATH" ]; then
      [ "$verb" = mv ] || [ "$rec" = 1 ] || return 1
      src_dir=$OB_PATH
    fi
    if [ "$dst_dir" = 1 ]; then
      b=${s%/}
      b=${b##*/}
      final=$dst/$b
    else
      final=$dst
    fi
    ob_path "$final" leaf "$zones" || return 1
    if [ "$rec" = 1 ] && [ -e "$OB_PATH" ]; then
      return 1
    fi
    if [ -n "$src_dir" ]; then
      # An opt-in's names move only within the worktree, never into scratch.
      if [ "$OB_ZONE" = wt ]; then
        ob_tree_clean "$src_dir" "$REC_OPEN" || return 1
      else
        ob_tree_clean "$src_dir" || return 1
      fi
    fi
  done
  return 0
}

# guard_cp / guard_mv: no flag that links, preserves links, or picks the
# target directory (`-l`, `-s`, `-a`, `-P`, `-d`, `-t`, `--parents`...). A
# recursive copy and every move can leave a symlink behind (ob_mark).
guard_cp() {
  local i a ends=0 rec=0 n=0
  local -a ops=()
  wr_live || return 1
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    if [ "$ends" = 0 ]; then
      case $a in
        --)
          ends=1
          continue
          ;;
        --recursive)
          rec=1
          continue
          ;;
        --force | --verbose | --no-clobber) continue ;;
        --*) return 1 ;;
        -?*)
          case ${a#-} in
            *[!fvnprR]*) return 1 ;;
          esac
          case $a in
            *[rR]*) rec=1 ;;
          esac
          continue
          ;;
      esac
    fi
    ops[n]=$a
    n=$((n + 1))
  done
  ob_copy_move cp "$rec" write ${ops[@]+"${ops[@]}"} || return 1
  if [ "$rec" = 1 ]; then
    ob_mark link
  else
    ob_mark write
  fi
}

guard_mv() {
  local i a ends=0 n=0
  local -a ops=()
  wr_live || return 1
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    if [ "$ends" = 0 ]; then
      case $a in
        --)
          ends=1
          continue
          ;;
        --force | --verbose | --no-clobber) continue ;;
        --*) return 1 ;;
        -?*)
          case ${a#-} in
            *[!fvn]*) return 1 ;;
          esac
          continue
          ;;
      esac
    fi
    ops[n]=$a
    n=$((n + 1))
  done
  ob_copy_move mv 0 write ${ops[@]+"${ops[@]}"} && ob_mark link
}

# guard_mktemp: the scratch arm's own writer. With no template it creates
# under TMPDIR, which the launcher set to the scratch root; a template must
# lie in the scratch root, since without `-p` or `-t` a relative one names
# the working directory. Only `-d` and `-q`: `-p`, `-t`, and `--tmpdir` pick
# another directory, and `-u` is not a write.
guard_mktemp() {
  local i a ends=0 n=0
  sc_live || return 1
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    if [ "$ends" = 0 ]; then
      case $a in
        --)
          ends=1
          continue
          ;;
        --directory | --quiet) continue ;;
        --*) return 1 ;;
        -?*)
          case ${a#-} in
            *[!dq]*) return 1 ;;
          esac
          continue
          ;;
      esac
    fi
    n=$((n + 1))
    [ "$n" -eq 1 ] || return 1
    ob_path "$a" leaf sc || return 1
  done
  AUDIT_SC=1
  ARM_ACT=1
  ob_mark write
}

# ob_git_ready: the git acts run in the worktree the record names, with its
# unit branch checked out (a session that switched away gets nothing).
ob_git_ready() {
  local top head
  ob_live || return 1
  top=$(git -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ "$(cd "$top" 2>/dev/null && pwd -P)" = "$REC_WT" ] || return 1
  head=$(git -C "$REC_WT" symbolic-ref -q HEAD 2>/dev/null) || return 1
  [ "$head" = "refs/heads/$REC_UNIT" ] || return 1
  AUDIT_OB=1
  OB_TOUCH=1
}

# ob_pathspec <word> <recursive>: a git pathspec naming a write target: no
# magic (`:`), then ob_target.
ob_pathspec() {
  case $1 in
    :*) return 1 ;;
  esac
  ob_target "$1" leaf "$2"
}

# ob_read_ok <word>: a file git reads a message from, inside the worktree.
ob_read_ok() {
  ob_path "$1" exists && [ -f "$OB_PATH" ]
}

# ob_ref_name <word>: a plain ref or revision name.
ob_ref_name() {
  case $1 in
    '' | -* | *[!A-Za-z0-9._/-]* | *..* | *//* | */ | *.lock) return 1 ;;
  esac
  return 0
}

# git_fetch_ok <first-arg-index> <any|origin>: 0 only for a fetch of a
# configured remote whose URL a built-in transport serves, with at most plain
# branch names after it: no refspec (so nothing lands outside the remote's own
# remote-tracking refs), no option that names a program or a config value. The
# `origin` form is the policy-free one: the remote must be named origin, and
# only the quiet and no-tags flags pass; `any` (the own-branch arm) also takes
# other configured remotes, --prune and --tags.
git_fetch_ok() {
  local i=$1 mode=$2 a remote=''
  for (( ; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      -q | --quiet | -v | --verbose | --no-tags) continue ;;
      -p | --prune | --tags)
        [ "$mode" = any ] || return 1
        continue
        ;;
      -*) return 1 ;;
    esac
    if [ -z "$remote" ]; then
      remote=$a
    else
      ob_ref_name "$a" && [ "$a" != tag ] || return 1
    fi
  done
  case $remote in
    '' | [!A-Za-z0-9]* | *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "$mode" = any ] || [ "$remote" = origin ] || return 1
  [ -e "$HOOK_CWD/$remote" ] || [ -e "$HOOK_CWD/$remote.git" ] && return 1
  git -C "$HOOK_CWD" config --get "remote.$remote.url" >/dev/null 2>&1 || return 1
  ls_remote_url_ok "$remote"
}

# ob_git <sub> <subidx>: the own-branch git acts. Git's own writes to its
# object store and index are not write targets; the worktree
# files a `rm`, `mv`, `restore`, or `checkout --` writes are.
ob_git() {
  local sub=$1 i=$(($2 + 1)) a ends=0 n=0 rec=0 expect='' worktree=1 staged=0 c rest remote='' src='' ot=$OB_TOUCH
  ob_git_ready || return 1
  # Staging, committing and fetching write only git's own store, never a
  # worktree file, so they leave a script HEAD already holds as it was
  # (OB_TOUCH); a commit's -F read is a read.
  case $sub in
    add | commit | fetch) OB_TOUCH=$ot ;;
  esac
  case $sub in
    add)
      for (( ; i < cwn; i++)); do
        a=${cw[i]}
        [ "$ends" = 0 ] || continue
        case $a in
          --) ends=1 ;;
          --all | --update | --verbose | --force | --intent-to-add | --no-all | --ignore-removal | --no-ignore-removal | --dry-run | --ignore-errors | --ignore-missing) ;;
          --*) return 1 ;;
          -?*)
            case ${a#-} in
              *[!AuvfNn]*) return 1 ;;
            esac
            ;;
        esac
      done
      return 0
      ;;
    commit)
      for (( ; i < cwn; i++)); do
        a=${cw[i]}
        if [ -n "$expect" ]; then
          [ "$expect" != F ] || ob_read_ok "$a" || return 1
          expect=''
          continue
        fi
        [ "$ends" = 0 ] || continue
        case $a in
          --) ends=1 ;;
          -m | --message | --trailer) expect=m ;;
          -F | --file) expect=F ;;
          --message=* | --trailer=* | --cleanup=* | --gpg-sign=*) ;;
          --file=*) ob_read_ok "${a#--file=}" || return 1 ;;
          --quiet | --signoff | --all | --allow-empty | --allow-empty-message | --gpg-sign | --no-gpg-sign | --verbose | --status | --no-status) ;;
          --*) return 1 ;;
          -?*)
            rest=${a#-}
            while [ -n "$rest" ]; do
              c=${rest:0:1}
              rest=${rest:1}
              case $c in
                a | q | s | v) ;;
                m | S)
                  [ -n "$rest" ] || [ "$c" = S ] || expect=m
                  break
                  ;;
                F)
                  if [ -n "$rest" ]; then
                    ob_read_ok "$rest" || return 1
                  else
                    expect=F
                  fi
                  break
                  ;;
                *) return 1 ;;
              esac
            done
            ;;
        esac
      done
      OB_TOUCH=$ot
      [ -z "$expect" ]
      return
      ;;
    rm)
      local -a paths=()
      for (( ; i < cwn; i++)); do
        a=${cw[i]}
        if [ "$ends" = 0 ]; then
          case $a in
            --)
              ends=1
              continue
              ;;
            --cached | --force | --quiet | --dry-run | --ignore-unmatch) continue ;;
            --*) return 1 ;;
            -?*)
              case ${a#-} in
                *[!rfqn]*) return 1 ;;
              esac
              case $a in
                *r*) rec=1 ;;
              esac
              continue
              ;;
          esac
        fi
        paths[n]=$a
        n=$((n + 1))
      done
      [ "$n" -ge 1 ] || return 1
      for a in "${paths[@]}"; do
        ob_pathspec "$a" "$rec" || return 1
      done
      ob_mark write
      return
      ;;
    mv)
      local -a ops=()
      for (( ; i < cwn; i++)); do
        a=${cw[i]}
        if [ "$ends" = 0 ]; then
          case $a in
            --)
              ends=1
              continue
              ;;
            --force | --verbose | --dry-run) continue ;;
            --*) return 1 ;;
            -?*)
              case ${a#-} in
                *[!fkvn]*) return 1 ;;
              esac
              continue
              ;;
          esac
        fi
        case $a in
          :*) return 1 ;;
        esac
        ops[n]=$a
        n=$((n + 1))
      done
      ob_copy_move mv 0 wt ${ops[@]+"${ops[@]}"} && ob_mark link
      return
      ;;
    restore | checkout)
      local -a paths=()
      for (( ; i < cwn; i++)); do
        a=${cw[i]}
        if [ -n "$expect" ]; then
          ob_ref_name "$a" || return 1
          expect=''
          continue
        fi
        if [ "$ends" = 0 ]; then
          case $a in
            --)
              ends=1
              continue
              ;;
            -q | --quiet) continue ;;
          esac
          # `git checkout <tree> -- <paths>` and the branch forms switch, or
          # change where the paths come from: only the `--` form is the arm's.
          [ "$sub" = restore ] || return 1
          case $a in
            -S | --staged)
              staged=1
              continue
              ;;
            -W | --worktree)
              worktree=2
              continue
              ;;
            -s)
              expect=s
              continue
              ;;
            --source=*)
              ob_ref_name "${a#--source=}" || return 1
              continue
              ;;
            -*) return 1 ;;
          esac
        fi
        paths[n]=$a
        n=$((n + 1))
      done
      [ -z "$expect" ] && [ "$n" -ge 1 ] || return 1
      [ "$sub" = restore ] || [ "$ends" = 1 ] || return 1
      for a in "${paths[@]}"; do
        ob_pathspec "$a" 1 || return 1
      done
      # `--staged` alone writes only the index.
      [ "$staged" = 1 ] && [ "$worktree" = 1 ] && return 0
      ob_mark link
      return
      ;;
    fetch)
      git_fetch_ok "$i" any
      return
      ;;
    merge)
      [ "$REC_BASE_MERGE" = allow ] && [ -n "$REC_BASE" ] || return 1
      for (( ; i < cwn; i++)); do
        a=${cw[i]}
        if [ -n "$expect" ]; then
          expect=''
          continue
        fi
        case $a in
          -m | --message) expect=m ;;
          --message=* | --no-edit | -q | --quiet | --no-ff | --ff | --ff-only | --stat | --no-stat | --log | --no-log | --progress | --no-progress | --signoff | --no-signoff) ;;
          -*) return 1 ;;
          *)
            [ -z "$src" ] || return 1
            src=$a
            ;;
        esac
      done
      [ -z "$expect" ] && [ "$src" = "$REC_BASE" ] || return 1
      # A local branch or tag of the same name would shadow the remote ref.
      a=$(git -C "$REC_WT" rev-parse --verify -q "$src^{commit}" 2>/dev/null) || return 1
      [ -n "$a" ] && [ "$a" = "$(git -C "$REC_WT" rev-parse --verify -q "refs/remotes/$src^{commit}" 2>/dev/null)" ] || return 1
      ob_mark link
      return
      ;;
  esac
  return 1
}

# --------------------------------------------------------------------------
# Per-verb guards. Each reads the current simple command's words from the
# caller's `cw` array (index 0 = verb) and `cwn` count via dynamic scope, plus
# `HOOK_CWD` and `HOOK_DEPTH`. Every guard's default/fallthrough is DEFER.

# sed_bracket_end / sed_scan_regex / sed_scan_literal: the delimiter-aware
# region scanners sed_script_safe walks its script with. All three read and
# advance the caller's `s` (script), `n` (length), `i` (cursor) and `d`
# (delimiter) via dynamic scope, and every one of them returns non-zero (DEFER)
# rather than guess when a region's extent is not identical across sed dialects.
#
# Why they exist: a POSIX bracket expression `[...]` makes the delimiter char
# LITERAL, so a `/` inside `[...]` does NOT close a `/regex/` or an `s///`
# pattern. A scanner blind to brackets desyncs from real sed on `/[/]/w f` and
# lets a write/exec command hide behind the desync; a scanner that instead bails
# on every `[` cannot approve the read-only bracket forms that dominate real
# usage (`s/^[0-9-]{11}//`). These scan brackets explicitly and defer only on the
# constructs whose extent genuinely differs between dialects.
#
# sed_bracket_end: `i` points at the opening `[`; advance past the matching `]`.
sed_bracket_end() {
  local j=$((i + 1)) c nc k cn
  [ "${s:j:1}" = '^' ] && j=$((j + 1)) # negation, then …
  [ "${s:j:1}" = ']' ] && j=$((j + 1)) # … a LEADING `]` is a literal member
  while [ "$j" -lt "$n" ]; do
    c=${s:j:1}
    case $c in
      # GNU sed honors backslash escapes INSIDE a bracket expression (`[\]]`,
      # `[\n]`); POSIX and BSD sed treat the backslash as an ordinary member, so
      # the bracket ENDS at a different offset under the two dialects. That is
      # exactly the desync this scanner must not guess at: defer.
      \\) return 1 ;;
      '[')
        nc=${s:j+1:1}
        case $nc in
          ':')
            # `[:class:]`: a sub-bracket whose `]` does not close the enclosing
            # expression. The class name is the closed POSIX set (case-sensitive:
            # real sed rejects `[[:Alpha:]]`), so an unknown or malformed name is
            # not a bracket expression at all and DEFERS rather than being
            # skipped as if it were one.
            k=$((j + 2))
            cn=''
            while [ "$k" -lt "$n" ]; do
              case ${s:k:1} in
                [a-z])
                  cn="$cn${s:k:1}"
                  k=$((k + 1))
                  ;;
                *) break ;;
              esac
            done
            [ "${s:k:1}" = ':' ] && [ "${s:k+1:1}" = ']' ] || return 1
            case $cn in
              alnum | alpha | blank | cntrl | digit | graph | lower | print | punct | space | upper | xdigit) ;;
              *) return 1 ;; # not a POSIX character class
            esac
            j=$((k + 2))
            ;;
          '.' | '=')
            # `[.coll.]` / `[=equiv=]`: SINGLE-character content only. A
            # multi-character collating-element or equivalence-class name is
            # locale-dependent (and rejected outright in the C locale), so its
            # validity — and therefore its extent — is not something this scanner
            # can place: defer.
            [ -n "${s:j+2:1}" ] || return 1
            [ "${s:j+3:1}" = "$nc" ] && [ "${s:j+4:1}" = ']' ] || return 1
            j=$((j + 5))
            ;;
          *) j=$((j + 1)) ;; # a plain `[` member
        esac
        ;;
      ']')
        i=$((j + 1))
        return 0
        ;;
      *) j=$((j + 1)) ;;
    esac
  done
  return 1 # unterminated bracket expression (real sed errors out)
}

# sed_scan_regex: `i` sits just past a region's opening delimiter `d`; advance
# past its closing delimiter, treating the region as a REGULAR EXPRESSION (so
# `[...]` hides the delimiter). Used for addresses and an `s` command's pattern.
sed_scan_regex() {
  local c
  while [ "$i" -lt "$n" ]; do
    c=${s:i:1}
    # The delimiter is tested FIRST: a script may choose any delimiter, and a
    # delimiter that also opens a bracket is rejected by the caller.
    if [ "$c" = "$d" ]; then
      i=$((i + 1))
      return 0
    fi
    case $c in
      \\) i=$((i + 2)) ;; # an escaped char (including an escaped delimiter)
      '[') sed_bracket_end || return 1 ;;
      *) i=$((i + 1)) ;;
    esac
  done
  return 1 # unterminated region
}

# sed_scan_literal: same, for a region that is NOT a regular expression — an `s`
# command's REPLACEMENT and both halves of `y`. Brackets carry no meaning there
# (`s/a/[/w f` writes a file), so treating them as bracket expressions would
# over-consume and skip the flag block: scan delimiters and escapes only.
sed_scan_literal() {
  local c
  while [ "$i" -lt "$n" ]; do
    c=${s:i:1}
    if [ "$c" = "$d" ]; then
      i=$((i + 1))
      return 0
    fi
    case $c in
      \\) i=$((i + 2)) ;;
      *) i=$((i + 1)) ;;
    esac
  done
  return 1 # unterminated region
}

# sed_delim_ok <char>: 0 only for a delimiter this scanner can place. sed forbids
# a backslash or newline delimiter outright; `[` and `]` are rejected here
# because a bracket-opening delimiter makes "is this `[` a delimiter or a bracket
# expression" genuinely ambiguous across dialects (REQ-B1.3 fail-closed).
sed_delim_ok() {
  case $1 in
    '' | \\ | '[' | ']' | "$NL") return 1 ;;
  esac
  return 0
}

# sed_script_safe <script>: 0 only when a sed script is provably read-only —
# it contains no write (`w`/`W`), exec (`e`), or arbitrary-file-read (`r`/`R`)
# command, and no `s///` substitution whose flag block carries `w`/`W`/`e`. It
# is a small, inert delimiter-aware scanner (never eval-ed), deferring on ANY
# doubt: a bare/malformed command, the text-region commands `a`/`i`/`c` (their
# multi-line text region is not soundly segmentable here), and anything it
# cannot place — an unplaceable delimiter (sed_delim_ok), an unterminated region,
# a dialect-divergent bracket expression (sed_bracket_end), or a `[` at command
# position. This is the fix for the whitespace-optional flag forms (`s/.*/x/e`,
# `s/a/b/wFILE`) a naive `[wWe][[:space:]]` heuristic misses. It screens what
# makes a sed script dangerous — the `w`/`W` (write), `r`/`R` (read-file) and `e`
# (exec) commands, and the `w`/`W`/`e` substitution flags — NOT the mere presence
# of a bracket expression, which is read-only however it parses.
sed_script_safe() {
  local s=$1
  local n=${#s} i=0 c d
  while [ "$i" -lt "$n" ]; do
    c=${s:i:1}
    # Command separators / block braces reset to command position.
    case $c in
      ' ' | "$TAB" | ';' | "$NL" | '{' | '}' | '!')
        i=$((i + 1))
        continue
        ;;
    esac
    # Addresses at command position are skipped as inert.
    case $c in
      [0-9])
        while [ "$i" -lt "$n" ]; do
          case ${s:i:1} in
            [0-9]) i=$((i + 1)) ;;
            *) break ;;
          esac
        done
        continue
        ;;
      '$' | ',' | '~' | '+')
        i=$((i + 1))
        continue
        ;;
      '/')
        d='/'
        i=$((i + 1))
        sed_scan_regex || return 1
        continue
        ;;
      \\)
        # `\cREc`: a custom-delimiter address regex.
        d=${s:i+1:1}
        sed_delim_ok "$d" || return 1
        i=$((i + 2))
        sed_scan_regex || return 1
        continue
        ;;
      '[')
        # A `[` at COMMAND position is not a sed address or command at all (real
        # sed errors out). Never silently skip it: defer (REQ-B1.3 fail-closed).
        return 1
        ;;
    esac
    # A command letter.
    case $c in
      w | W | r | R | e) return 1 ;; # write / read-file / exec commands
      a | i | c) return 1 ;;         # text-region commands: defer (unparsed here)
      s | y)
        d=${s:i+1:1}
        sed_delim_ok "$d" || return 1
        i=$((i + 2))
        # `s` takes a REGEX then a literal replacement; `y` takes two literal
        # character lists (no bracket expression in either half).
        if [ "$c" = s ]; then
          sed_scan_regex || return 1
        else
          sed_scan_literal || return 1
        fi
        sed_scan_literal || return 1
        if [ "$c" = s ]; then
          # Flag block: reject a w/W/e substitution flag (write/exec).
          while [ "$i" -lt "$n" ]; do
            case ${s:i:1} in
              w | W | e) return 1 ;;
              ' ' | "$TAB" | ';' | "$NL" | '}') break ;;
              *) i=$((i + 1)) ;;
            esac
          done
        fi
        ;;
      *) i=$((i + 1)) ;; # p/d/n/N/g/G/h/H/x/q/Q/=/l/z/b/t/T/: … : read-only
    esac
  done
  return 0
}

# guard_sed: strict flag allowlist (REQ-A1.8) plus the read-only script check.
# `-i`/`--in-place`, `-f`/`--file` (an unverifiable external script file), any
# bundled short-flag token, and any unrecognized flag all defer; only the
# enumerated safe standalone flags pass, and every inline script (a bare
# operand, or a `-e`, `--expression` or `--expression=` value) must be
# read-only.
guard_sed() {
  local i a expect_e=0 script_taken=0
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    if [ "$expect_e" = 1 ]; then
      zsh_opt_word_ok "$i" && sed_script_safe "$a" || return 1
      expect_e=0
      script_taken=1
      continue
    fi
    case $a in
      -e | --expression) expect_e=1 ;;
      --expression=*)
        zsh_opt_word_ok "$i" && sed_script_safe "${a#--expression=}" || return 1
        script_taken=1
        ;;
      -n | -E | -r | -s | -z | -u | --posix | --quiet | --silent | --regexp-extended | --separate | --null-data | --unbuffered | --debug | --sandbox | --help | --version | --) ;;
      -*) return 1 ;; # -i / -f / -l / bundled / unknown: defer
      *)
        if [ "$script_taken" = 0 ]; then
          zsh_opt_word_ok "$i" && sed_script_safe "$a" || return 1
          script_taken=1
        fi
        ;;
    esac
  done
  [ "$expect_e" = 1 ] && return 1
  return 0
}

# guard_sed_inplace: a bare `-i` / `--in-place` (no backup suffix), which
# edits files, only under the own-branch arm, with every option ahead of
# every operand. Without the `-i` word the
# command must pass guard_sed, the read-only screen the tower guard shares;
# every file must then be an existing regular file ob_path admits, and must
# also read as a read-only script, since BSD sed takes the word after `-i` as
# its suffix and so the first file as the script.
guard_sed_inplace() {
  local i a inplace=0 expect_e=0 script_taken=0 nfiles=0 nn=0 operand=0 ddash=0
  local -a words=() files=() nx=() nq=() nd=() ng=() nz=() nm=() ns=()
  ob_live || return 1
  for ((i = 0; i < cwn; i++)); do
    a=${cw[i]}
    if [ "$i" -gt 0 ] && [ "$expect_e" = 0 ]; then
      # Every option must precede every operand and `--`: GNU sed reads an
      # `-e` anywhere but takes every word after `--` as a file, so a bare
      # word ahead of an `-e` would be a file this loop took for the script.
      case $a in
        --)
          [ "$ddash$nfiles" = 00 ] || return 1
          ddash=1
          operand=1
          ;;
        -*) [ "$operand" = 0 ] || return 1 ;;
        *) operand=1 ;;
      esac
      case $a in
        -i | --in-place)
          inplace=1
          continue
          ;;
      esac
    fi
    # Every per-word flag array drops the `-i` word with `cw`, so a screen
    # guard_sed runs by index reads the word it names, not its neighbour.
    words[nn]=$a
    nx[nn]=${cx[i]}
    nq[nn]=${cqp[i]}
    nd[nn]=${cdyn[i]}
    ng[nn]=${cglob[i]}
    nz[nn]=${cz[i]-0}
    nm[nn]=${cqm[i]}
    ns[nn]=${csub[i]-}
    nn=$((nn + 1))
    [ "$i" -gt 0 ] || continue
    if [ "$expect_e" = 1 ]; then
      expect_e=0
      script_taken=1
      continue
    fi
    case $a in
      -e) expect_e=1 ;;
      --expression=*) script_taken=1 ;;
      # guard_sed accepts this form; the in-place arm defers it rather than
      # count its value as a file.
      --expression) return 1 ;;
      -*) ;;
      *)
        if [ "$script_taken" = 0 ]; then
          script_taken=1
        else
          files[nfiles]=$a
          nfiles=$((nfiles + 1))
        fi
        ;;
    esac
  done
  [ "$inplace" = 1 ] && [ "$nfiles" -ge 1 ] || return 1
  local -a cw=("${words[@]}") cx=("${nx[@]}") cqp=("${nq[@]}") cdyn=("${nd[@]}")
  local -a cglob=("${ng[@]}") cz=("${nz[@]}") cqm=("${nm[@]}") csub=("${ns[@]}")
  local cwn=$nn
  guard_sed || return 1
  for a in "${files[@]}"; do
    # Only a BSD sed reads the first word after a bare `-i` as its suffix, so
    # the first file as the script; GNU sed takes the suffix attached and the
    # next word as the script, so a file name is never read as one.
    case $OSTYPE in
      linux*) ;;
      *) sed_script_safe "$a" || return 1 ;;
    esac
    ob_path "$a" exists && [ -f "$OB_PATH" ] || return 1
  done
  ob_mark write
}

# perl_subst_safe <program>: a lone `s/RE/REPL/FLAGS` whose text no perl
# feature can turn into code: delimiter `/`, `|` or `#` that never recurs
# inside the parts, no escaped delimiter, no braces (code blocks, `\x{..}`,
# `@{[..]}`), no `(?`, no `@`, no backtick, `$` only before a digit in the
# replacement or ending the pattern, flags from [gimsx] only (never `e`).
perl_subst_safe() {
  local p=$1 d re repl flags rest
  case $p in
    s/*) d=/ ;;
    's|'*) d='|' ;;
    's#'*) d='#' ;;
    *) return 1 ;;
  esac
  rest=${p#s?}
  re=${rest%%"$d"*}
  [ "$re" != "$rest" ] || return 1
  rest=${rest#*"$d"}
  repl=${rest%%"$d"*}
  [ "$repl" != "$rest" ] || return 1
  flags=${rest#*"$d"}
  case $flags in
    *[!gimsx]*) return 1 ;;
  esac
  case $re$repl in
    *[{}@\`]* | *'(?'* | *$'\n'*) return 1 ;;
  esac
  case $re$repl in
    *\\) return 1 ;;
  esac
  case $re in
    *\\"$d"* | *\\) return 1 ;;
    *'$'*) [[ $re == *'$' && ${re%\$} != *'$'* ]] || return 1 ;;
  esac
  case $repl in
    *\\"$d"* | *\\) return 1 ;;
  esac
  local t=$repl
  while [ "${t#*'$'}" != "$t" ]; do
    t=${t#*'$'}
    case $t in
      [0-9]*) ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# guard_perl_inplace: `perl -pi -e <s///> <file>...` (or `-i -pe`), only under
# the own-branch arm, a bare `-i` (a suffix would back up beside the file),
# one substitution from perl_subst_safe, and every file an existing regular
# file ob_path admits.
guard_perl_inplace() {
  local i prog n=$cwn
  ob_live || return 1
  case "${cw[1]-} ${cw[2]-}" in
    '-pi -e' | '-i -pe') ;;
    *) return 1 ;;
  esac
  [ "$n" -ge 5 ] || return 1
  prog=${cw[3]}
  [ "${cdyn[3]}" = 0 ] && [ "${cglob[3]}" = 0 ] || return 1
  perl_subst_safe "$prog" || return 1
  for ((i = 4; i < n; i++)); do
    ob_path "${cw[i]}" exists && [ -f "$OB_PATH" ] || return 1
  done
  ob_mark write
}

# awk_program_safe <program>: 0 only when an awk program text is provably
# read-only. awk's dangerous surface is (a) EXEC — `system(…)`, either direction
# of a command pipe (`print | "cmd"`, `"cmd" | getline`), gawk's `|&` coprocess
# and its `@load` / `@include` / indirect `@fn` calls — and (b) OUTPUT — a
# `print`/`printf` redirected with `>` / `>>` to a file.
#
# The screen is a blanket reject plus ONE narrow, positively-blessed exception,
# in that order:
#
#   1. Any `>`, `@`, `|&`, `system`, `close`, `ENVIRON` or `getline` anywhere in
#      the text rejects. `>` goes in whole — no file-write class survives at all
#      — so a relational `$1 > 5` is rejected with it: telling a redirecting `>`
#      from a relational one needs a real awk parser, and this screen has none.
#   2. That leaves `|`, and only in the programs that contain one. Every `|`
#      must be POSITIVELY blessed as `||` (logical OR) or as a character inside
#      a positively-identified regex literal; anything else rejects. A program
#      with no `|` left after step 1 has no reachable exec or write vector at
#      all, whatever it parses to, so it is approved without a walk.
#   3. A regex literal is positively identified only where awk CANNOT mean
#      division: a `/` whose immediately preceding non-whitespace character is
#      one of `{ ; ( , & ! ~ |`, or a newline that is not a line continuation,
#      or the start of the program. It closes at the next `/` not preceded by a
#      backslash, and may hold no `"`, no `[` and no newline. Rejecting `[`
#      sidesteps the mawk/nawk/busybox disagreement over `/[/]/` entirely, at
#      the cost of deferring `/[0-9]+|[a-z]+/`; that over-defer is accepted.
#   4. A `/` ANYWHERE ELSE rejects. There is deliberately NO "not a regex, so
#      scan on as division" fallback. The screen this replaced had one, and four
#      working bypasses came through it in under an hour: a `/` misread as
#      division scanned the span as CODE, and a `#` or an unbalanced `"` inside
#      that span then swallowed the real `| "sh"` behind it. An unplaceable `/`
#      is a defer. That absence is the entire point — do not add a branch here,
#      and do not reach for a tokenizer to buy back the over-defers it costs.
#
# Two spans are walked, and only because the rule above is unsound without
# them. A string literal, because a `{`, `;` or `&` INSIDE one would otherwise
# bless the `/` that follows it (`{x = "&" /2; print s | c; y = 1/2}` reaches
# the shell if it does). And `\`-newline, because it is a LINE CONTINUATION:
# awk is still mid-expression across it, so that newline is not a statement
# boundary and must not bless either (`{x = 1 \` + newline + `/ 2; print s | c;
# y = 1/3}` reaches the shell if it does). Both were live exec bypasses of this
# screen when it was first written; the fixtures for them are load-bearing.
#
# A `|` inside a string rejects like any other, so `{print "a|b"}` defers — the
# accepted price of not modelling what awk does with the value. Comments are not
# skipped for the same reason: everything a `#` would hide rejects rather than
# being read as inert.
awk_program_safe() {
  local s=$1
  # A backslash-newline inside program text can split a dangerous token so the
  # blanket substring checks below never see it: `syste\<newline>m("id")` holds
  # no literal `system`. Under mawk that parses as an undefined function rather
  # than executing, so the splice itself is unreproduced here, but no other awk
  # was available to test and the construct has no place in a program this
  # screen is willing to vouch for. Reject it outright (fail-closed) instead of
  # betting on one dialect's tokenizer. Raised by the Copilot pass, 2026-09-15.
  case $s in
    *\\$'\n'*) return 1 ;;
  esac
  local n=${#s} i=0 c prev=''
  case $s in
    *'>'* | *'@'* | *'|&'* | *system* | *close* | *ENVIRON* | *getline*) return 1 ;;
  esac
  case $s in
    *'|'*) ;;
    *) return 0 ;;
  esac
  while [ "$i" -lt "$n" ]; do
    c=${s:i:1}
    case $c in
      '"')
        i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          case ${s:i:1} in
            \\) i=$((i + 2)) ;;
            '|') return 1 ;; # a `|` a string hides is never blessed
            '"') break ;;
            *) i=$((i + 1)) ;;
          esac
        done
        [ "$i" -lt "$n" ] || return 1 # unterminated string literal
        i=$((i + 1))
        prev='"'
        continue
        ;;
      \\)
        # Outside a string or a regex, a `\` is only ever a LINE CONTINUATION;
        # awk errors on every other use of one. Consume `\`+newline as a single
        # unit with `prev` UNTOUCHED — the continuation does not end the
        # statement, so that newline must not bless a following `/` — and
        # reject any other `\X`, so nothing can hide inside the skip.
        [ "${s:i+1:1}" = "$NL" ] || return 1
        i=$((i + 2))
        continue
        ;;
      '/')
        case $prev in
          '' | '{' | ';' | '(' | ',' | '&' | '!' | '~' | '|' | "$NL") ;;
          *) return 1 ;; # an unplaceable `/`: never scanned on (4 above)
        esac
        i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          case ${s:i:1} in
            \\) i=$((i + 2)) ;;
            '"' | '[' | "$NL") return 1 ;;
            '/') break ;;
            *) i=$((i + 1)) ;;
          esac
        done
        [ "$i" -lt "$n" ] || return 1 # unterminated regex literal
        i=$((i + 1))
        prev='/'
        continue
        ;;
      '|')
        [ "${s:i+1:1}" = '|' ] || return 1 # a lone `|` is a command pipe
        i=$((i + 2))
        prev='|'
        continue
        ;;
    esac
    case $c in
      ' ' | "$TAB") ;; # blanks never change what a following `/` may mean
      *) prev=$c ;;
    esac
    i=$((i + 1))
  done
  return 0
}

# awk_assignment_ok <text>: 0 only when <text> is a placeable `name=value`
# variable assignment (a valid awk identifier left of the first `=`). A `-v`
# operand this cannot place means the guard's arg model has diverged from awk's,
# so the caller defers rather than assume the token is inert data.
awk_assignment_ok() {
  case $1 in
    [A-Za-z_]*=*) ;;
    *) return 1 ;;
  esac
  case ${1%%=*} in
    *[!A-Za-z0-9_]*) return 1 ;;
  esac
  return 0
}

# guard_awk: strict flag allowlist (REQ-A1.8) plus the read-only program check.
# Only the inline-program form is verifiable, so `-f`/--file` (an external
# program file), gawk's file-writing/loading flags (`-p`/--profile`, `-o`,
# `-d`/--dump-variables`, `-l`/--load`, `-i`/--include`, `-E`, `--source`), any
# bundled short-flag token, and any unrecognized flag all defer. The first
# non-flag operand is the program (screened); later operands are input files and
# `var=value` assignments, which awk only ever READS.
guard_awk() {
  local i a expect=none prog_taken=0
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $expect in
      fs) # the value of a space-form -F: an inert field-separator regex
        expect=none
        continue
        ;;
      assign)
        awk_assignment_ok "$a" || return 1
        expect=none
        continue
        ;;
    esac
    case $a in
      -F | --field-separator) expect=fs ;;
      -F?* | --field-separator=*) ;; # attached value: inert
      -v | --assign) expect=assign ;;
      -v?*) awk_assignment_ok "${a#-v}" || return 1 ;;
      --assign=*) awk_assignment_ok "${a#--assign=}" || return 1 ;;
      --posix | --traditional | -c | --compat | -b | --characters-as-bytes | --re-interval | -S | --sandbox | --help | --usage | --version | -V | --) ;;
      -*) return 1 ;; # -f / -p / -o / -d / -l / -i / -E / bundled / unknown: defer
      *)
        if [ "$prog_taken" = 0 ]; then
          zsh_opt_word_ok "$i" && awk_program_safe "$a" || return 1
          prog_taken=1
        fi
        ;;
    esac
  done
  [ "$expect" = none ] || return 1  # a dangling value-flag with no value: defer
  [ "$prog_taken" = 1 ] || return 1 # no inline program (the -f form): defer
  return 0
}

# zsh_opt_word_ok <index>: 0 unless word <index> of the current simple command
# (cz, by dynamic scope) holds an unquoted character that a zsh option off by
# default would expand (extended globbing's `^`, `~` and `#`, brace character
# classes). The program-text screens read that word as literal text, so they
# refuse it; the same characters in any other word keep their verdicts.
zsh_opt_word_ok() {
  [ "${cz[$1]-0}" = 0 ]
}

# jq_program_safe <program>: 0 only when a jq filter is provably free of an
# ENVIRONMENT read and loads no module text. jq's language has no exec and no
# file-write primitive at all; what it does have is `env` and `$ENV`, either
# of which hands the whole environment to the filter (and from there to the
# transcript), `include` / `import`, which pull in module text the guard
# never sees, from a search path the filter itself can name, and `modulemeta`,
# which reads that text back. That is the same
# call guard_awk makes on `ENVIRON`, and for the same reason: the guard can see
# the read but not what the program does with the value.
#
# Each of those names rejects only as a WORD: a preceding `.` makes it a FIELD
# ACCESS on the input (`.env`, `.a.include`), an identifier character after it
# a longer name (`envelope`, `ENVIRONMENT`), and a preceding `$` someone's own
# variable (`$env`, `$import`). `ENV` takes no `$` exemption, since jq 1.6 and
# older read `$ ENV`, with a space or a comment between the two, as `$ENV`. A
# mention the rule cannot place that way, `"env"` inside a string included,
# defers; that costs the filter shapes nothing.
jq_program_safe() {
  local s=$1
  local n=${#s} i=0 p a w words
  case $s in
    *\$ENV*) return 1 ;;
    *env* | *ENV* | *include* | *import* | *modulemeta*) ;;
    *) return 0 ;; # names none of the screened words
  esac
  while [ "$i" -lt "$n" ]; do
    case ${s:i:1} in
      e) words='env' ;;
      E) words='ENV' ;;
      i) words='include import' ;;
      m) words='modulemeta' ;;
      *) words='' ;;
    esac
    for w in $words; do
      [ "${s:i:${#w}}" = "$w" ] || continue
      a=${s:i+${#w}:1}
      case $a in
        [A-Za-z0-9_]) continue ;; # a longer name
      esac
      p=''
      [ "$i" -gt 0 ] && p=${s:i-1:1}
      case $w:$p in
        ENV:[A-Za-z0-9_.]) ;; # a field access or a longer name
        ENV:*) return 1 ;;
        *:[A-Za-z0-9_.$]) ;; # a field access, a variable, or a longer name
        *) return 1 ;;
      esac
    done
    i=$((i + 1))
  done
  return 0
}

# jq_home_safe: 0 only when HOME is an absolute path and no `~/.jq` exists,
# the home-directory half of guard_jq's screen (see there), shared with
# guard_yq for the jq-wrapping yq.
jq_home_safe() {
  case ${HOME:-} in
    /*) ;;
    *) return 1 ;;
  esac
  if [ -e "$HOME/.jq" ] || [ -L "$HOME/.jq" ]; then
    return 1
  fi
  return 0
}

# guard_jq: strict flag allowlist plus the environment-read and module checks
# on the filter. Only the inline-filter form is verifiable, so `-f`/`--from-file`
# (a filter in a file) and `-L`/`--library-path` (which is where `include` and
# `import` read module text from) defer, as does any unrecognized flag, and so
# does every run while `~/.jq` exists: jq reads a `~/.jq` file into every
# filter, and a `~/.jq` directory is on its module search path. A HOME that is
# not an absolute path defers too, since the guard cannot then tell where jq
# looks (jq 1.6 falls back to the password entry's home when HOME is unset).
#
# Every value-taking flag is enumerated because the filter is identified BY
# POSITION — it is the first non-flag operand — and a value sitting in that
# position would be screened in its place: without this, `jq --indent 4 '$ENV'`
# would screen `4` and hand `$ENV` through as if it were a filename. Operands
# after the filter are input files, or positional arguments under
# `--args`/`--jsonargs`, and jq only ever READS those.
guard_jq() {
  local i a t c expect=0 prog_taken=0 endflags=0
  jq_home_safe || return 1
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    if [ "$expect" -gt 0 ]; then # a flag's value, never the filter
      expect=$((expect - 1))
      continue
    fi
    if [ "$endflags" = 0 ]; then
      case $a in
        --)
          endflags=1
          continue
          ;;
        --indent)
          expect=1
          continue
          ;;
        --arg | --argjson | --slurpfile | --rawfile)
          expect=2
          continue
          ;;
        --null-input | --raw-input | --slurp | --compact-output | --raw-output | \
          --raw-output0 | --join-output | --ascii-output | --sort-keys | \
          --color-output | --monochrome-output | --tab | --unbuffered | --stream | \
          --stream-errors | --seq | --args | --jsonargs | --exit-status | \
          --version | --build-configuration | --help)
          continue
          ;;
        --*) return 1 ;; # --from-file / --library-path / unknown
        -?*)
          # jq combines short flags (`-rn`), so every character in the token is
          # its own flag. `f` and `L` carry unscreenable program text and any
          # other unknown character is an arg model the guard does not have.
          t=${a#-}
          while [ -n "$t" ]; do
            c=${t:0:1}
            case $c in
              [acCehjMnrsSRV]) ;;
              *) return 1 ;;
            esac
            t=${t:1}
          done
          continue
          ;;
      esac
    fi
    if [ "$prog_taken" = 0 ]; then
      zsh_opt_word_ok "$i" && jq_program_safe "$a" || return 1
      prog_taken=1
    fi
  done
  [ "$expect" = 0 ] || return 1     # a dangling value-flag with no value
  [ "$prog_taken" = 1 ] || return 1 # no inline filter (the -f form, or none)
  return 0
}

# guard_env: `env` never auto-approves. Bare, it prints the whole environment,
# whatever credentials the worker's session carries; with an operand it is an
# EXEC vector (`env VAR=x cmd`, `env -i cmd`, `env -S '…'`). `env --version`
# is approved earlier, as a version probe.
guard_env() {
  return 1
}

# guard_printenv: `printenv NAME…` with names only, none credential-named:
# the same read as `echo $VAR`. Bare, or with a flag, it prints every variable.
guard_printenv() {
  local i
  [ "$cwn" -ge 2 ] || return 1
  for ((i = 1; i < cwn; i++)); do
    case ${cw[i]} in
      # An operand the tracker could not resolve may name any variable.
      -* | '' | *[\$\`]*) return 1 ;;
    esac
    ! secret_var_name "${cw[i]}" || return 1
  done
  return 0
}

# guard_sleep: `sleep <duration>…`, numeric durations only, within the cap.
guard_sleep() {
  local i total=0
  [ "$cwn" -ge 2 ] || return 1
  for ((i = 1; i < cwn; i++)); do
    is_duration "${cw[i]}" || return 1
    total=$((total + DURATION_SECONDS))
  done
  # sleep waits for the sum of its operands.
  [ "$total" -le "$MAX_WAIT_SECONDS" ]
}

# guard_ps: ps writes no file and runs nothing, but its option grammar
# differs by platform, so only the enumerated flags pass: the selection and
# format flags (a value-taking one, alone or ending a bundle, consumes the
# next word), BSD-style letter words, and pid operands. Whatever prints
# process environments, which carry secrets, defers: `-e` (which does on
# macOS and the BSDs), the BSD `e` modifier, and a format naming an
# environment field (ps_format_ok).
guard_ps() {
  local i a body
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      --format=*) ps_format_ok "${a#--format=}" || return 1 ;;
      --no-headers | --no-heading | --headers | --forest | --cumulative | --sort=* | --pid=* | --ppid=* | --cols=* | --columns=* | --width=*) ;;
      --format)
        i=$((i + 1))
        [ "$i" -lt "$cwn" ] && ps_format_ok "${cw[i]}" || return 1
        ;;
      --sort | --pid | --ppid | --cols | --columns | --width)
        i=$((i + 1))
        [ "$i" -lt "$cwn" ] || return 1
        ;;
      -?*)
        body=${a#-}
        case $body in
          *[!AadfFHjlLMmTwxyZoOpqtuUgGCs]*) return 1 ;;
          *[oOpqtuUgGCs]?*) return 1 ;; # a value-taking flag must end its bundle
          *[oO])
            i=$((i + 1))
            [ "$i" -lt "$cwn" ] && ps_format_ok "${cw[i]}" || return 1
            ;;
          *[pqtuUgGCs])
            i=$((i + 1))
            [ "$i" -lt "$cwn" ] || return 1
            ;;
        esac
        ;;
      '' | *[!0-9,]*)
        case $a in
          '' | *[!auxwfjlT]*) return 1 ;;
        esac
        ;;
    esac
  done
  return 0
}

# ps_format_ok <format>: 0 unless the format names an environment field
# (`env`, `environ`, in any case).
ps_format_ok() {
  case $1 in
    *[eE][nN][vV]*) return 1 ;;
  esac
  return 0
}

# guard_uptime: bare, or one of the report-format flags.
guard_uptime() {
  case $cwn in
    1) return 0 ;;
    2)
      case ${cw[1]} in
        -p | --pretty | -s | --since) return 0 ;;
      esac
      ;;
  esac
  return 1
}

# guard_which: names to look up, with `-a` / `-s` only.
guard_which() {
  local i
  [ "$cwn" -ge 2 ] || return 1
  for ((i = 1; i < cwn; i++)); do
    case ${cw[i]} in
      -a | -s) ;;
      -* | '') return 1 ;;
    esac
  done
  return 0
}

# guard_command: only the lookup forms `command -v` / `command -V NAME…`;
# every other form runs its operand as a command.
guard_command() {
  local i
  case ${cw[1]-} in
    -v | -V) ;;
    *) return 1 ;;
  esac
  [ "$cwn" -ge 3 ] || return 1
  for ((i = 2; i < cwn; i++)); do
    case ${cw[i]} in
      -* | '') return 1 ;;
    esac
  done
  return 0
}

# guard_read: `read [-r] [NAME…]`. read runs nothing and writes no file, but it
# ASSIGNS shell variables, and a name like PATH or IFS would re-point every
# later command in the same shell — the exact hazard assign_name_ok exists for,
# so each name goes through it. Only `-r` is allowed: every other read flag
# takes a value (`-d`, `-n`, `-a`, `-u`, `-p`, `-t`, `-i`), and a value operand
# would otherwise be name-checked as if it were a variable. A name the
# analyzer is substituting (a tracked assignment or a loop variable) would
# keep its modelled value after read replaced it, so it defers too.
guard_read() {
  local i a v
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      -r | --) ;;
      -*) return 1 ;;
      *)
        assign_name_ok "$a" || return 1
        # As track_assignment refuses: a read into a name an own-unit export
        # set would replace the value the export was checked against.
        if [ "$OU_EXPORTED" = 1 ]; then
          case $a in
            PLANWRIGHT_STEP_*) return 1 ;;
          esac
        fi
        for ((v = 0; v < VAR_C; v++)); do
          [ "${VAR_N[v]}" = "$a" ] && return 1
        done
        ;;
    esac
  done
  return 0
}

# flag_name_in <token> <name>…: 0 when <token>'s flag NAME — what follows its
# leading dashes, up to an `=` — is one of <name>…. For the tools that do NOT
# bundle short flags: shfmt's `-sr` is ONE flag named `sr`, not `-s -r`, and
# `-filename=x` is one flag named `filename`, so matching the whole name is
# exact and an attached value can never be read as a flag. Long and short
# spellings collapse to the same test (`-w` and `--write`).
flag_name_in() {
  local tok=${1#-} name
  shift
  tok=${tok#-}
  tok=${tok%%=*}
  for name in "$@"; do
    [ "$tok" = "$name" ] && return 0
  done
  return 1
}

# guard_yq: yq EDITS IN PLACE. Both the Go (mikefarah) and the jq-wrapping
# Python spelling write the input file back with `-i`/`--inplace`/`--in-place`,
# and the Go one also writes one file per match with `-s`/`--split-exp`. Reject
# both in every spelling, bundled short forms included; `-I` (indent) is a
# different, read-only flag and the case-sensitive patterns leave it alone.
#
# No short flag is declared value-taking here, so only the `-o=json` form of an
# attached value is placed (every parser in play starts a value at `=`), and
# `-ojson` still defers. That is deliberate: two unrelated programs answer to
# `yq` with different short-flag tables, and a value-taking claim that is wrong
# for the one actually installed would read a dangerous flag as inert.
# The jq-wrapping spelling also reads `~/.jq`, so guard_yq takes jq's
# home-directory check too.
# yq_expression_safe <expr>: 0 unless the expression reads the environment
# or, read as a jq filter, fails jq_program_safe.
# yq's `env(NAME)` and `strenv(NAME)` are the same capability the awk `ENVIRON`
# reject and jq_program_safe's `env` check exist for — program text whose use
# of the value this guard cannot see — so the third member of that family is
# screened the same way rather than left as the one open door.
yq_expression_safe() {
  local s=$1 n i p a w
  case $s in
    *strenv* | *envsubst*) return 1 ;;
  esac
  # The jq-wrapping Python spelling runs the expression as a jq filter.
  jq_program_safe "$s" || return 1
  # `env` is a bare operator, not only a call: `env | .PATH` and `.a = env`
  # both read the environment. Walk it as a token so a longer identifier
  # (`.environment`, `envelope`) still passes, mirroring jq_program_safe.
  # Raised by the Copilot pass, 2026-09-15.
  # The second word runs text this screen never sees, so it rejects the same
  # way, except as the whole operand, where it names a subcommand.
  case $s in
    eval | eval-all) return 0 ;;
  esac
  n=${#s}
  i=0
  while [ "$i" -lt "$n" ]; do
    # The load family (`load`, `load_str`, `load_xml`, …) reads any path
    # named in the expression, /proc/<pid>/environ included.
    if [ "${s:i:4}" = load ]; then
      p=''
      [ "$i" -gt 0 ] && p=${s:i-1:1}
      case $p in
        [A-Za-z0-9_.\$]) ;;
        *) return 1 ;;
      esac
    fi
    for w in env eval; do
      [ "${s:i:${#w}}" = "$w" ] || continue
      p=''
      [ "$i" -gt 0 ] && p=${s:i-1:1}
      a=${s:i+${#w}:1}
      case $p in
        [A-Za-z0-9_.\$]) ;; # a field access, a variable, or a longer name
        *)
          case $a in
            [A-Za-z0-9_]) ;; # a longer name: `environment`, `envelope`
            *) return 1 ;;   # the operator
          esac
          ;;
      esac
    done
    i=$((i + 1))
  done
  return 0
}

guard_yq() {
  local i a endflags=0
  jq_home_safe || return 1
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    # Every operand is screened as the expression: which one yq reads it from
    # is not always the first operand this loop sees.
    if [ "$endflags" = 1 ]; then
      zsh_opt_word_ok "$i" && yq_expression_safe "$a" || return 1
      continue
    fi
    case $a in
      --) endflags=1 ;; # end of flags: what follows is an expression or a file
      # Every long flag defers: the Go spelling's long-only flags include
      # ones that write files, run programs, or carry the expression, and the
      # two spellings share no long-flag table this screen could vouch for.
      --*) return 1 ;;
      -?*) short_flag_hit "$a" 'is' '' && return 1 ;;
      *) zsh_opt_word_ok "$i" && yq_expression_safe "$a" || return 1 ;;
    esac
  done
  return 0
}

# guard_shfmt: shfmt's only write vector is `-w`/`--write` (format in place);
# `-d`/`-l`/`--to-json` report to stdout. shfmt does not bundle short flags —
# `-lw` is one undefined flag named `lw`, not `-l -w`, and shfmt exits 2 without
# touching the file (measured against 3.13.1) — so the whole flag NAME decides,
# and an attached value can never be read as a flag: `-filename=workflow.sh`
# names `filename`, not a `w` write. The names are an ALLOWLIST of the
# report-only flags rather than a reject list for `w`, so a flag this screen has
# never heard of defers instead of passing on the strength of its spelling.
guard_shfmt() {
  local i a
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      --) break ;;
      -?*)
        flag_name_in "$a" l list d diff f find s simplify p posix i indent ln \
          language-dialect bn binary-next-line ci case-indent sr space-redirects \
          kp keep-padding fn func-next-line mn minify filename apply-ignore \
          to-json from-json version h help || return 1
        ;;
    esac
  done
  return 0
}

# guard_rg: ripgrep writes no file, but `--pre <cmd>` runs an arbitrary program
# over every searched file and `--hostname-bin <cmd>` runs one to resolve the
# hostname. `-z`/`--search-zip` also spawns decompressors picked off PATH, so it
# goes too — the search shapes a worker writes never need it.
guard_rg() {
  local i a
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      --) break ;; # end of flags: what follows is the pattern and paths
      --pre | --pre=* | --pre-glob | --pre-glob=* | --hostname-bin | --hostname-bin=* | --search-zip) return 1 ;;
      --*) ;;
      -?*) short_flag_hit "$a" 'z' 'ABCEMTdefgjmrt' && return 1 ;;
    esac
  done
  return 0
}

# guard_fd: fd writes no file, but `-x`/`--exec` and `-X`/`--exec-batch` run an
# arbitrary command per result (or per batch).
guard_fd() {
  local i a
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      --) break ;;
      --exec | --exec=* | --exec-batch | --exec-batch=*) return 1 ;;
      --*) ;;
      -?*) short_flag_hit "$a" 'xX' 'EScdejot' && return 1 ;;
    esac
  done
  return 0
}

# guard_lefthook: `lefthook run <job>` only — the same trust boundary `mise run`
# sits on, and for the same reason: what it runs is the repo's own tracked
# lefthook.yml, which the kickoff trust boundary already covers. That makes it a
# TRUSTED-REPO-CODE allowance, not a read-only one (a pre-commit job may well
# format files). `-c`/`--config` is what breaks the boundary — it points
# lefthook at an arbitrary config, i.e. arbitrary commands — so it defers in
# every position, as does any pre-subcommand flag and any other subcommand.
# lefthook spells its long flags with one dash as readily as two and does not
# bundle short ones, so the flag NAME is what is matched: `-command lint` keeps
# its own name and is left alone.
guard_lefthook() {
  local i a sub=''
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      -*) return 1 ;; # a pre-subcommand flag
      *)
        sub=$a
        break
        ;;
    esac
  done
  [ "$sub" = run ] || return 1
  for ((i = i + 1; i < cwn; i++)); do
    case ${cw[i]} in
      --) break ;;
      # `-c` takes an attached value too: `-c/tmp/evil.yml` selects an
      # arbitrary config, and a config is arbitrary commands. flag_name_in
      # only placed the separated and long forms. Copilot pass, 2026-09-15.
      -c* | --config | --config=*) return 1 ;;
      -?*) flag_name_in "${cw[i]}" c config && return 1 ;;
    esac
  done
  return 0
}

guard_find() {
  local i a
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      -delete | -exec | -execdir | -ok | -okdir | -fprint | -fprint0 | -fprintf | -fls) return 1 ;;
    esac
  done
  return 0
}

# short_flag_hit <token> <danger> <valued>: 0 when <token> is a short-flag
# cluster whose FLAG positions include one of the <danger> characters. The scan
# mirrors how these tools' own parsers read a cluster: characters are flags left
# to right until one that TAKES A VALUE, after which the REST of the token is
# that value, and an `=` starts one the same way. `rg -tzsh` is `-t zsh`, not
# `-t -z -s -h`, and `sort -to` is `-t o`, so the trailing characters are not
# flag positions and must not be screened as if they were — each such misread
# is a worker stall. A character in NEITHER set is an unknown boolean flag and
# the scan continues past it: unknown-means-keep-looking is the fail-closed
# direction, since reading a value as flags can only add defers, never drop a
# reject. Callers pass only tokens that begin with a single `-`; long flags are
# matched by name before this is reached.
short_flag_hit() {
  local rest=${1#-} danger=$2 valued=$3 c
  while [ -n "$rest" ]; do
    c=${rest:0:1}
    [ "$c" = '=' ] && return 1
    case $danger in
      *"$c"*) return 0 ;;
    esac
    case $valued in
      *"$c"*) return 1 ;;
    esac
    rest=${rest:1}
  done
  return 1
}

# guard_sort: sort's exec/write vectors are -o/--output, which writes a file,
# and --compress-program=<prog>, which execs an arbitrary program on every
# external-merge temp-file spill. Reject both; every other sort flag is
# read-only. -k/-S/-t/-T take values, so the characters after them in a cluster
# are data, not flags.
guard_sort() {
  local i a
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      --) break ;; # end of flags: what follows are input files
      --output | --output=* | --compress-program | --compress-program=*) return 1 ;;
      --*) ;;
      -?*) short_flag_hit "$a" 'o' 'kStT' && return 1 ;;
    esac
  done
  return 0
}

guard_uniq() {
  local i a operands=0
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      -*) ;;                           # a flag (none of uniq's flags write)
      *) operands=$((operands + 1)) ;; # positional: 2nd operand is the OUTPUT file
    esac
  done
  [ "$operands" -ge 2 ] && return 1
  return 0
}

guard_date() {
  local i a
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      -s | -s* | --set | --set=*) return 1 ;;
      # `-f FILE` echoes every line it cannot parse; short options bundle and
      # long ones abbreviate.
      -I*) ;;
      -[fs]* | -[a-zA-Z]*[fs]* | --f*) return 1 ;;
    esac
  done
  return 0
}

guard_file() {
  local i a
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      --compile) return 1 ;;
      -[!-]*C* | -C) return 1 ;; # -C compiles/writes the magic cache
    esac
  done
  return 0
}

# guard_ss: ss reads the kernel's socket tables and writes nothing by default,
# but a few options write, kill, switch namespace, run a filter program or
# resolve names off the machine: `-K`/`--kill` closes sockets, `-D`/`--diag`
# dumps raw data to a file, `-F`/`--filter` reads one, `-N`/`--net` enters a
# namespace, `-b`/`--bpf` loads a program, `-r`/`--resolve` queries DNS, and
# `-E`/`--events` never returns. Only the enumerated display and selection
# flags pass, and a filter expression only as plain words, so nothing is read
# from a variable, a substitution or a glob.
guard_ss() {
  local i a body
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      --listening | --all | --tcp | --udp | --raw | --unix | --sctp | --dccp | --packet | --numeric | --processes | --summary | --extended | --info | --options | --memory | --ipv4 | --ipv6 | --no-header | --oneline) ;;
      -- | --*) return 1 ;;
      -?*)
        body=${a#-}
        case $body in
          *[!ntulaxwdSsiempoH460O]*) return 1 ;;
        esac
        ;;
      '' | *[!A-Za-z0-9_.:=!\<\>/@%,-]*) return 1 ;;
    esac
  done
  return 0
}

# guard_umask: the mask of the shell the command runs in, which only changes
# the mode of files made after it: bare, `-S`, `-p`, or an octal literal that
# keeps the other-write bit masked, so a later step never makes a
# world-writable file.
guard_umask() {
  local re='^0?[0-7]{2}[2367]$'
  case $cwn in
    1) return 0 ;;
    2)
      case ${cw[1]} in
        -S | -p) return 0 ;;
      esac
      [[ ${cw[1]} =~ $re ]]
      return
      ;;
  esac
  return 1
}

# guard_mdlint <verb>: markdownlint-cli2 and markdownlint load their config
# from the folder of each file they lint, the working directory and the folders
# above, and a config can run code: a .cjs or .mjs one is a module, and an
# options file can name custom-rule, plugin and formatter modules. A worker can
# Write any of those, so a run is approved only on named files inside the
# repository, since a glob or a folder reaches folders this does not check,
# and only when mdlint_configs_ok clears every folder. An option defers (it
# can name a config, a rule module or an output file, or fix files), but for
# `--no-globs` and markdownlint's `-q`.
guard_mdlint() {
  local verb=$1 i a p full root ends=0 nog=0 dirs=()
  root=$(repo_root_of "$HOOK_CWD") || return 1
  [ "$(git_plain -C "$root" rev-parse --show-toplevel 2>/dev/null)" = "$root" ] || return 1
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    if [ "$ends" = 0 ]; then
      case $verb:$a in
        *:--)
          ends=1
          continue
          ;;
        markdownlint-cli2:--no-globs)
          nog=1
          continue
          ;;
        markdownlint:-q | markdownlint:--quiet) continue ;;
        *:-*) return 1 ;;
      esac
    fi
    p=$a
    # markdownlint-cli2 reads a leading `:` as "a literal path".
    [ "$verb" != markdownlint-cli2 ] || p=${p#:}
    # Glob and extended-glob syntax, and a newline, which no folder walk below
    # could follow.
    case $p in
      '' | -* | '#'* | '!'* | '~'* | *[][*?{}\(\)\|\\]* | *$'\n'*) return 1 ;;
    esac
    case /$p/ in
      */../*) return 1 ;;
    esac
    mdlint_unlinked "$p" || return 1
    full=$(canon_under "$p" "$HOOK_CWD" "$root") || return 1
    [ -f "$full" ] || return 1
    dirs+=("${full%/*}")
  done
  [ "${#dirs[@]}" -ge 1 ] || return 1
  mdlint_configs_ok "$verb" "$nog" "${dirs[@]}"
}

# mdlint_unlinked <operand>: 0 unless a folder the operand names on its way to
# the file is a symbolic link. The linters look for config along the path as
# written, so a linked folder's own config would lie off the canonical walk.
mdlint_unlinked() {
  local d
  case $1 in
    */*) d=${1%/*} ;;
    *) return 0 ;;
  esac
  while [ -n "$d" ]; do
    case $d in
      /*) [ ! -L "$d" ] || return 1 ;;
      *) [ ! -L "$HOOK_CWD/$d" ] || return 1 ;;
    esac
    case $d in
      */*) d=${d%/*} ;;
      *) d='' ;;
    esac
  done
  return 0
}

# The files markdownlint-cli2 and markdownlint read from a folder, by what
# they can do: a module runs whatever it imports, an options file can name
# modules to import and, in the working directory, add globs, and a config
# file holds rule settings only (its `extends` reads another such file).
MDLINT_MODULES=(.markdownlint-cli2.cjs .markdownlint-cli2.mjs .markdownlint.cjs .markdownlint.mjs)
MDLINT_OPTIONS=(.markdownlint-cli2.jsonc .markdownlint-cli2.yaml .markdownlint-cli2.yml package.json)
MDLINT_SETTINGS=(.markdownlint.jsonc .markdownlint.json .markdownlint.yaml .markdownlint.yml .markdownlintrc)

# mdlint_configs_ok <verb> <no-globs> <dir>...: 0 when the working directory,
# each <dir> and every folder above them hold no module config, and every
# options and settings file there is one a git checkout commits unchanged.
# A committed module may still import a file the worker wrote, so it defers
# too, and so does an options file naming a module key or holding a
# backslash, through which an escape could spell one. Without --no-globs, an
# options file in the working directory may add globs reaching folders this
# does not walk, so one there defers. The verdict holds only for the folders as
# they are before the command runs, so the approval leans on a committed check
# (COMMITTED_USED) and main refuses it beside an own-branch act that can change
# a worktree file (OB_TOUCH).
mdlint_configs_ok() {
  local verb=$1 nog=$2 d f seen=$'\n' cwdp
  shift 2
  cwdp=$(cd "$HOOK_CWD" 2>/dev/null && pwd -P) || return 1
  # A newline in a folder name would forge an entry of the walk's seen list.
  case $cwdp in
    *$'\n'*) return 1 ;;
  esac
  if [ "$verb" = markdownlint-cli2 ] && [ "$nog" = 0 ]; then
    for f in "${MDLINT_OPTIONS[@]}"; do
      [ ! -e "$cwdp/$f" ] && [ ! -L "$cwdp/$f" ] || return 1
    done
  fi
  for d in "$cwdp" "$@"; do
    while :; do
      case $seen in
        *$'\n'"$d"$'\n'*) break ;;
      esac
      seen=$seen$d$'\n'
      for f in "${MDLINT_MODULES[@]}"; do
        [ ! -e "$d/$f" ] && [ ! -L "$d/$f" ] || return 1
      done
      for f in "${MDLINT_OPTIONS[@]}" "${MDLINT_SETTINGS[@]}"; do
        [ -e "$d/$f" ] || [ -L "$d/$f" ] || continue
        committed_in_checkout "${d%/}/$f" || return 1
      done
      for f in "${MDLINT_OPTIONS[@]}"; do
        [ -f "$d/$f" ] || continue
        # grep exits 1 only on a file read whole with no match.
        LC_ALL=C grep -a -q -E 'customRules|markdownItPlugins|outputFormatters|modulePaths|[\]' -- "$d/$f"
        [ $? -eq 1 ] || return 1
      done
      [ "$d" != / ] || break
      d=${d%/*}
      [ -n "$d" ] || d=/
    done
  done
  COMMITTED_USED=1
  return 0
}

guard_bashsh() {
  # Only `bash <trusted-script> [args]` / `sh <trusted-script> [args]` — repo
  # code HEAD commits unchanged or an installed planwright root's scripts/
  # (is_trusted_script); any option (notably -c /
  # -ec) defers (REQ-A1.5, REQ-A1.9).
  [ "$cwn" -ge 2 ] || return 1
  case ${cw[1]} in
    -*) return 1 ;;
  esac
  is_trusted_script "${cw[1]}" "$HOOK_CWD" || return 1
  step_script_kind "${cw[1]}" || return 0
  STEP_CALL=1
  step_call_ok 1
}

guard_fish() {
  # Only `fish -c "<inner>"`; recurse the same analysis on the inner string
  # within the depth bound (REQ-A1.5, REQ-B1.3).
  # fish keeps reading its own options after the string, and a second `-c`
  # or `--init-command` runs too.
  [ "$cwn" -eq 3 ] || return 1
  [ "${cw[1]}" = '-c' ] || return 1
  # The inner string is read with bash's quoting, but fish decodes escapes
  # bash does not (`--he\x6cp` is `--help` to fish), and expands `{a, b}`
  # across the space into two words, so either defers.
  case ${cw[2]} in
    *\\* | *'{'*','*) return 1 ;;
  esac
  # fish's read updates a variable where it already lives, a universal one
  # included, and fish saves those to disk, so no read runs inside.
  local FISH_INNER=1
  analyze_command "${cw[2]}" "$((HOOK_DEPTH + 1))"
}

guard_bats() {
  # `bats [safe-flags] <file...>`: each file operand must resolve inside the
  # repo (REQ-A1.10) to a file HEAD commits unchanged (a directory defers), and
  # ONLY no-value display/selection flags are allowed.
  # Any value-taking or unrecognized flag defers — a `--formatter`/`--output`/
  # `--report-formatter`/`--setup-suite-file` flag (and its `=<path>` form) can
  # carry a path bats would execute or write OUTSIDE the containment check, so
  # allowlisting the safe flags (rather than denylisting the dangerous ones)
  # closes that whole class.
  local i a saw_file=0
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      --tap | -t | --pretty | -p | --timing | -T | --recursive | -r | --count | -c | --trace | -x | --no-tempdir-cleanup | --print-output-on-failure | --show-output-of-passing-tests | --verbose-run | --no-parallelize-across-files | --no-parallelize-within-files | --) ;;
      -*) return 1 ;; # value-taking / path-carrying / unknown flag: defer
      *)
        is_contained_file "$a" "$HOOK_CWD" || return 1
        saw_file=1
        ;;
    esac
  done
  [ "$saw_file" = 1 ] || return 1
  return 0
}

guard_mise() {
  # REQ-A1.5: `mise run <task>` / `mise tasks` (and its read-only leaves) only
  # (repo-defined tasks, trusted per the kickoff trust boundary). Any
  # pre-subcommand flag or other subcommand defers.
  local sub=''
  local i a j leaf
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      -*) return 1 ;; # a pre-subcommand flag
      *)
        sub=$a
        break
        ;;
    esac
  done
  case $sub in
    tasks)
      # `mise tasks` is a subcommand TREE, not a read-only leaf. Bare
      # `mise tasks` and the display leaves (`ls`/`info`/`deps`) list tasks, but
      # `edit` launches $EDITOR (arbitrary exec), `add` writes a task file, and
      # `run` is an alias of `mise run` (so it can carry the options that
      # change what a task runs). Enumerate the read-only leaves, route
      # `run` through the run-option screen below, and defer edit/add/unknown.
      leaf=''
      for ((j = i + 1; j < cwn; j++)); do
        case ${cw[j]} in
          -*) ;; # a tasks-level display flag (-g/-l/-J/--json/…): read-only
          *)
            leaf=${cw[j]}
            break
            ;;
        esac
      done
      case $leaf in
        '' | ls | info | deps) return 0 ;;
        run) ;; # screened below from the words after `tasks`, a global option before `run` included
        *) return 1 ;;
      esac
      ;;
    run) ;; # fall through to the run-option screen below
    *) return 1 ;;
  esac
  mise_run_args_ok "$((i + 1))"
}

# mise_run_args_ok <from>: 0 unless a word from index <from> on is an option
# that changes what a task runs, turning the trusted repo-task runner into an
# arbitrary-command runner: --shell runs the task through any
# command, --cd takes it from another directory's config, --env loads a
# mise.<env>.toml beside the config, and --tool puts a tool on its PATH. mise
# reads no abbreviation of a long option, but a short-flag cluster can carry
# any of the letters (`-nC`), so a cluster holding one defers.
mise_run_args_ok() {
  local i
  for ((i = $1; i < cwn; i++)); do
    case ${cw[i]} in
      --shell | --shell=* | --cd | --cd=* | --env | --env=* | --tool | --tool=*) return 1 ;;
      -[sCEt]* | -[!-]*[sCEt]*) return 1 ;;
    esac
  done
  return 0
}

# gh_jq_ok: 0 unless a jq filter or Go template (`--jq`, `-q`, `--template`,
# `-t`) mentions `env`: gojq's `env` and `$ENV` print the worker's
# environment, tokens included, through any read verb that takes the flag. A
# short word holding q or t is screened whole, since an attached value can
# itself end in q or t (`-qenv|test`); one ending in q or t may also hand its
# value to the next word, so that word is screened too.
gh_jq_ok() {
  local i jqv=0
  for ((i = 2; i < cwn; i++)); do
    if [ "$jqv" = 1 ]; then
      ci_has "${cw[i]}" '*env*' && return 1
      jqv=0
    fi
    case ${cw[i]} in
      --jq | --template) jqv=1 ;;
      --jq=* | --template=*) ci_has "${cw[i]}" '*env*' && return 1 ;;
      -[qt]* | -[!-]*[qt]*)
        ci_has "${cw[i]}" '*env*' && return 1
        case ${cw[i]} in
          *[qt]) jqv=1 ;;
        esac
        ;;
    esac
  done
  return 0
}

# gh_no_web: 0 unless a `--web`/`-w` flag is present. These read verbs print
# to stdout, but `--web` instead launches $BROWSER — an inherited BROWSER is an
# arbitrary program, and a headless opener stalls the worker. Raised by the
# Copilot pass, 2026-09-15.
gh_no_web() {
  local i
  for ((i = 2; i < cwn; i++)); do
    case ${cw[i]} in
      --) break ;;
      --web | --web=*) return 1 ;;
      --*) ;;
      -?*) short_flag_hit "${cw[i]}" 'w' 'Hqpt' && return 1 ;;
    esac
  done
  return 0
}

# gh_no_token: 0 unless `gh auth status` carries `--show-token` or its `-t`,
# alone or in a short bundle, which prints the token. A `t` read as part of
# another flag's value only over-refuses.
gh_no_token() {
  local i
  for ((i = 3; i < cwn; i++)); do
    case ${cw[i]} in
      --show* | -t* | -[!-]*t*) return 1 ;;
    esac
  done
  return 0
}

# gh_release_ok: `gh release view|list` with no `--web`/`-w` (it launches
# $BROWSER) and no `--repo`/`-R` override (REQ-A1.17). `-R` and `-w` can ride
# in a short cluster, and the value-taking short flags end one.
gh_release_ok() {
  local i a
  for ((i = 3; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      --) break ;;
      --web | --web=* | --repo | --repo=*) return 1 ;;
      --*) ;;
      -?*) short_flag_hit "$a" 'wR' 'JqtLO' && return 1 ;;
    esac
  done
  return 0
}

# guard_gitleaks: `gitleaks detect` with only the read-and-report options
# (REQ-A1.17): any report, baseline, or config option defers, and `--source`
# names one plain literal path inside the worktree or the scratch root. The
# path is read through ob_path, whose audit marks a write arm: a read is no
# arm's act, so the marks are put back.
guard_gitleaks() {
  local i a src='' have=0 ao=$AUDIT_OB as=$AUDIT_SC ot=$OB_TOUCH
  [ "${cw[1]-}" = detect ] || return 1
  for ((i = 2; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      --no-git | --no-banner | --verbose | --redact) ;;
      --source)
        [ "$have" = 0 ] && [ "$((i + 1))" -lt "$cwn" ] || return 1
        have=1
        i=$((i + 1))
        src=${cw[i]}
        [ "${cqp[i]}" -lt 0 ] && ! word_unresolved "$src" "${cdyn[i]}" "${cglob[i]}" "${cx[i]}" || return 1
        ;;
      --source=?*)
        [ "$have" = 0 ] || return 1
        have=1
        src=${a#--source=}
        [ "${cqp[i]}" -lt 0 ] && ! word_unresolved "$a" "${cdyn[i]}" "${cglob[i]}" "${cx[i]}" || return 1
        ;;
      *) return 1 ;;
    esac
  done
  [ "$have" = 1 ] || return 1
  ob_path "$src" exists read || return 1
  AUDIT_OB=$ao
  AUDIT_SC=$as
  OB_TOUCH=$ot
  return 0
}

guard_gh() {
  # REQ-A1.5: read-only gh only. A leading flag, or any non-enumerated group/sub
  # pair, defers.
  case ${cw[1]-} in
    -*) return 1 ;;
  esac
  local i g=${cw[1]-} s=${cw[2]-}
  gh_jq_ok || return 1
  case $g in
    release)
      case $s in
        view | list) gh_release_ok || return 1 ;;
        *) return 1 ;;
      esac
      return 0
      ;;
    pr | issue)
      case $s in
        view | list | status | diff | checks) gh_no_web || return 1 ;;
        *) return 1 ;;
      esac
      return 0
      ;;
    run)
      case $s in
        view | list) gh_no_web || return 1 ;;
        *) return 1 ;; # download / rerun / cancel / delete / watch
      esac
      return 0
      ;;
    api)
      # `gh api <endpoint>` is a GET, and a GET through gh is read-only. The
      # flags that change that are the ones to reject: an explicit
      # `-X`/`--method`, `--input` (a request body), and any field flag — gh
      # switches the request to POST as soon as one `-f`/`-F`/`--field`/
      # `--raw-field` is present, so a field flag is a write in disguise even
      # with no `-X`.
      # A method-override header makes the server treat the GET as a write,
      # and `--hostname` sends the request, token included, to another host:
      # both defer, and so does a header value the guard cannot read.
      # A full URL may name another host.
      local hdr=0
      for ((i = 2; i < cwn; i++)); do
        ci_has "${cw[i]}" '*method-override*' '*x-http-method*' '*x-method*' '*://*' && return 1
        if [ "$hdr" = 1 ]; then
          case ${cw[i]} in
            *'$'*) return 1 ;;
          esac
          hdr=0
        fi
        case ${cw[i]} in
          --header=*'$'* | -H*'$'*) return 1 ;;
          --header | -*H) hdr=1 ;;
        esac
        case ${cw[i]} in
          --) break ;; # end of flags: what follows is the endpoint
          --hostname | --hostname=*) return 1 ;;
          # An explicit GET is the default spelled out. The value must be the
          # next literal word, so a `-X`/`--method` with anything else (or
          # nothing) stays a write.
          --method=GET | -XGET) continue ;;
          -X | --method)
            [ "$((i + 1))" -lt "$cwn" ] && [ "${cw[i + 1]}" = GET ] && [ "${cqp[i + 1]}" -lt 0 ] || return 1
            i=$((i + 1))
            continue
            ;;
          --method=* | --field | --field=* | --raw-field | --raw-field=*) return 1 ;;
          --input | --input=*) return 1 ;;
          --*) ;;
          # gh uses pflag, which bundles short flags, so a write flag can ride
          # behind a boolean one: `-iX POST` is `-i` plus `-X POST`, and an
          # anchored `-X*` match never sees it. The value-taking flags end the
          # cluster because everything after them is their value, not flags —
          # in `-qFkey=val` the `F` is part of the jq expression `-q` consumes.
          -?*) short_flag_hit "${cw[i]}" 'XFf' 'Hqpt' && return 1 ;;
        esac
      done
      return 0
      ;;
    search)
      case $s in
        code | issues | prs) gh_no_web || return 1 ;;
        *) return 1 ;;
      esac
      return 0
      ;;
    auth)
      [ "$s" = status ] || return 1
      gh_no_token || return 1
      return 0
      ;;
    repo)
      [ "$s" = view ] || return 1
      gh_no_web || return 1
      return 0
      ;;
    *) return 1 ;;
  esac
}

# git_driver_opt <verb> <word>: whether git can read <word> as an option that
# runs a configured driver (`--ext-diff`, `--textconv`, `--filters`). git takes
# any unambiguous prefix of a long option and the `--opt=value` spelling, so any
# prefix of one matches, failing closed. `--text` and `--filter` name other
# options exactly, except on cat-file: it has no `--text`, and git before its
# own `--filter` reads that word as `--filters`.
git_driver_opt() {
  local n=${2%%=*}
  case $n in
    --?*) n=${n#--} ;;
    *) return 1 ;;
  esac
  case $n in
    text | filter) [ "$1" = cat-file ] || return 1 ;;
  esac
  [[ ext-diff == "$n"* || textconv == "$n"* || filters == "$n"* ]]
}

# git_config_write_opt <word>: whether git config can read <word> as an option
# that writes config or opens an editor on it. git takes any unambiguous prefix
# of a long option (`--remove-sec`), so any prefix of one matches, the
# ambiguous ones git refuses (`--u`, `--re`, `--e`) included; a short cluster
# carrying `e` is `-e` (`-ze`), a `-t` value holding an e included. `--comment`
# applies only to a write, and its value can be a read flag: `git config
# --comment --list a.b v` sets a.b.
git_config_write_opt() {
  local n o
  case $1 in
    --?*)
      n=${1%%=*}
      n=${n#--}
      ;;
    -*e*) return 0 ;;
    *) return 1 ;;
  esac
  for o in add unset unset-all replace-all rename-section remove-section edit comment; do
    [[ $o == "$n"* ]] && return 0
  done
  return 1
}

# git_help_req <verb>: whether the git line in cw asks for help, which opens the
# man page through a pager or a browser, and a pager runs commands (`!cmd` in
# less). git opens it for the `help` verb and an exact `--help` right after
# the verb, but any word git could read as --help or --help-all, wherever it
# sits and abbreviated or not, counts, failing closed.
git_help_req() {
  local i n
  [ "$1" = help ] && return 0
  for ((i = 1; i < cwn; i++)); do
    n=${cw[i]%%=*}
    case $n in
      --?*) [[ help-all == "${n#--}"* ]] && return 0 ;;
    esac
  done
  return 1
}

# git: read-only subcommands only, no pre-subcommand global option (which can
# inject config/alias-driven execution, REQ-A1.8), and per-subcommand form
# guards on the subcommands with a mutating twin (REQ-A1.5).
guard_git() {
  local i a sub='' subidx=0 start=1 viac=0
  # `git -C <dir>` for a read: the one global option admitted, and only when
  # <dir> is the session's own worktree or a directory of it (own_dir_ok).
  if [ "${cw[1]-}" = -C ] && [ "$cwn" -ge 4 ]; then
    own_dir_ok 2 || return 1
    start=3
    viac=1
  fi
  for ((i = start; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      -*) return 1 ;; # a pre-subcommand global option: defer
      *)
        sub=$a
        subidx=$i
        break
        ;;
    esac
  done
  [ -n "$sub" ] || return 1
  git_help_req "$sub" && return 1
  if [ "$viac" = 1 ]; then
    case $sub in
      status | diff | log | show) ;;
      *) return 1 ;;
    esac
  fi
  # `stash list`, `stash show` and `reflog show` hand their options to git log
  # or git diff, --output among them, so the read verbs' screen applies to the
  # words after the subcommand.
  case $sub:${cw[subidx + 1]-} in
    stash:list | stash:show | reflog:show)
      sub=log
      subidx=$((subidx + 1))
      ;;
  esac
  case $sub in
    log | show | diff | status | rev-parse | cat-file | ls-files | ls-tree | for-each-ref | describe | blame | shortlog | rev-list | name-rev | whatchanged | grep | merge-base | show-ref | cherry | var)
      # Read-only, but reject a following flag that WRITES a file
      # (`git diff --output=FILE`) or SPAWNS a command: `git grep -O<cmd>` /
      # `--open-files-in-pager=<cmd>` run <cmd> through the shell, and
      # `--ext-diff` / `--textconv` / `--filters` (git cat-file) run a
      # configured driver (external-diff, textconv, or smudge/clean filter).
      for ((i = subidx + 1; i < cwn; i++)); do
        case ${cw[i]} in
          # git takes any unambiguous prefix of a long option (`--out=`).
          -o | --ou* | -O | -O* | --op*) return 1 ;;
          # `-nO<cmd>` is -n then -O with <cmd> as its value. Any O in a short
          # cluster defers, a value holding one (`log -SOops`) included.
          -[!-]*O*) return 1 ;;
          # Content from outside the repository: any file (`diff --no-index`,
          # `blame --contents`), and a list read from a named file
          # (`--orderfile`, `ls-files -X`).
          --no-i* | --or* | --exclude-f* | --exclude-p*) return 1 ;;
        esac
        git_driver_opt "$sub" "${cw[i]}" && return 1
        case $sub in
          ls-files)
            case ${cw[i]} in
              -X* | -[!-]*X*) return 1 ;;
            esac
            ;;
          blame)
            case ${cw[i]} in
              --con* | --ignore-revs* | -S* | -[!-]*S*) return 1 ;;
            esac
            ;;
          # Patterns read from a file: `-f`, alone or in a cluster.
          grep)
            case ${cw[i]} in
              -f* | -[!-]*f*) return 1 ;;
            esac
            ;;
          # Two paths, one outside the work tree, are an implicit --no-index.
          diff)
            case ${cw[i]} in
              /* | \~* | .. | ../* | */../* | */..) return 1 ;;
            esac
            ;;
        esac
      done
      return 0
      ;;
    branch)
      # A listing-filter flag puts branch in read-only list mode, where a
      # positional is a filter arg / pattern (never a branch to create); without
      # one, a positional creates a branch and defers. Mirrors the tag guard.
      local listing=0 positional=0
      for ((i = subidx + 1; i < cwn; i++)); do
        a=${cw[i]}
        case $a in
          -l | --list | --contains | --contains=* | --no-contains | --no-contains=* | --merged | --merged=* | --no-merged | --no-merged=* | --points-at | --points-at=*) listing=1 ;;
          -a | --all | -r | --remotes | -v | -vv | --verbose | --show-current | --format | --format=* | --color | --color=* | --no-color | -q | --quiet | -i | --ignore-case | --sort | --sort=* | --column | --no-column | --abbrev | --abbrev=* | --no-abbrev) ;;
          -*) return 1 ;; # any other flag (mutating -m/-d/-D/-f/-c/-u… or unknown) defers
          *) positional=$((positional + 1)) ;;
        esac
      done
      [ "$positional" -ge 1 ] && [ "$listing" = 0 ] && return 1
      return 0
      ;;
    config)
      local positional=0 read_flag=0 operands=0 first=$((subidx + 1))
      # git reads a subcommand only as the word right after `config`; `list`
      # takes its own options after it.
      case ${cw[first]-} in
        set | unset | rename-section | remove-section | edit) return 1 ;;
        list) first=$((first + 1)) ;;
      esac
      for ((i = first; i < cwn; i++)); do
        a=${cw[i]}
        git_config_write_opt "$a" && return 1
        # git stops reading options at the first operand, `--` or
        # `--end-of-options`, so a dashed word after it is an operand:
        # `git config core.hooksPath -x` sets it.
        if [ "$operands" = 1 ]; then
          positional=$((positional + 1))
          continue
        fi
        case $a in
          # Actions only: a display option such as --name-only is negatable
          # (`--name-only --no-name-only a.b v` sets a.b).
          --get | --get-all | --get-regexp | --get-urlmatch | --list | -l | --get-color | --get-colorbool) read_flag=1 ;;
          # Another file parsed as config prints its `key = value` lines.
          -f* | -[!-]*f* | --fil* | --bl*) return 1 ;;
          -- | --end-of-options) operands=1 ;;
          -?*) ;; # scope/format flags (--global/--type/…) are read-safe
          *)
            operands=1
            positional=$((positional + 1))
            ;;
        esac
      done
      [ "$read_flag" = 1 ] && return 0
      [ "$positional" -ge 2 ] && return 1 # `git config key value` sets
      return 0
      ;;
    remote)
      local nxt=${cw[subidx + 1]-}
      case $nxt in
        '' | -v | --verbose) return 0 ;; # bare / verbose list
        show | get-url) return 0 ;;
        *) return 1 ;; # add/remove/set-url/rename/prune/… mutate
      esac
      ;;
    tag)
      local listing=0 positional=0 mutating=0
      for ((i = subidx + 1; i < cwn; i++)); do
        a=${cw[i]}
        case $a in
          -l | --list | -n | -n* | --contains | --no-contains | --points-at | --merged | --no-merged | --sort | --sort=* | --format | --format=* | --color | --no-color | -i | --ignore-case) listing=1 ;;
          -d | --delete | -a | --annotate | -s | --sign | -u | --local-user | -m | --message | -F | --file | -f | --force | -e) mutating=1 ;;
          -*) return 1 ;;
          *) positional=$((positional + 1)) ;;
        esac
      done
      [ "$mutating" = 1 ] && return 1
      [ "$listing" = 1 ] && return 0
      [ "$positional" -ge 1 ] && return 1 # `git tag <name>` creates
      return 0
      ;;
    stash)
      # `stash list` and `stash show` arrive above as `log`; bare `git stash`
      # PUSHES, and every other subcommand writes, so it defers.
      return 1
      ;;
    symbolic-ref)
      # `git symbolic-ref <name>` READS a ref, but `git symbolic-ref HEAD <ref>`
      # SETS it and `-d` deletes it — both silent local mutations.
      local positional=0
      for ((i = subidx + 1; i < cwn; i++)); do
        case ${cw[i]} in
          -d | --delete) return 1 ;;
          --short | -q | --quiet) ;;
          -*) return 1 ;;
          *) positional=$((positional + 1)) ;;
        esac
      done
      [ "$positional" -ge 2 ] && return 1 # a second operand sets the ref
      return 0
      ;;
    reflog)
      # `git reflog` and `reflog exists` READ (`reflog show` arrives above as
      # `log`); `expire`/`delete` destroy recovery data.
      case ${cw[subidx + 1]-} in
        '' | exists) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    check-ignore)
      local ddash=0
      for ((i = subidx + 1; i < cwn; i++)); do
        [ "$ddash" = 1 ] && continue
        case ${cw[i]} in
          --) ddash=1 ;;
          -q | --quiet | -v | --verbose | -n | --non-matching | --no-index | --stdin | -z) ;;
          -*) return 1 ;;
        esac
      done
      return 0
      ;;
    ls-remote)
      # Only a remote NAME: a URL, a path, or an scp-style address would make
      # git open whatever repository it names (a local one through its own
      # upload-pack), and `--upload-pack` / `-u` choose the program run. A
      # name that is also an existing path, as itself or as git's `.git`
      # variants, could be read as that path, so it defers too.
      local remote='' positional=0
      for ((i = subidx + 1; i < cwn; i++)); do
        a=${cw[i]}
        case $a in
          -h | --heads | -b | --branches | -t | --tags | --refs | -q | --quiet | --exit-code | --get-url | --symref | --sort=*) ;;
          -*) return 1 ;;
          *)
            positional=$((positional + 1))
            [ "$positional" -eq 1 ] && remote=$a
            ;;
        esac
      done
      case $remote in
        '' | [!A-Za-z0-9]* | *[!A-Za-z0-9._-]*) return 1 ;;
      esac
      [ -e "$HOOK_CWD/$remote" ] || [ -e "$HOOK_CWD/$remote.git" ] && return 1
      # A name no remote is configured as is read as a path or URL instead.
      git -C "$HOOK_CWD" config --get "remote.$remote.url" >/dev/null 2>&1 || return 1
      ls_remote_url_ok "$remote"
      ;;
    worktree)
      # Only `git worktree list`. Bare `git worktree` is a usage error, and
      # every other leaf (add/remove/move/prune/repair/lock/unlock) mutates the
      # worktree set — including the one this worker is running in.
      case ${cw[subidx + 1]-} in
        list) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    fetch)
      # Without the own-branch arm: `git fetch origin [<branch>]` from the
      # session's own repository, which writes only remote-tracking refs and
      # objects. Not through -C.
      if [ "$viac" = 0 ] && [ "$IN_SUBST" = 0 ] && [ "$HOOK_DEPTH" -eq 0 ] && [ -n "$REC_WT" ] && [ -n "$REC_UNIT" ]; then
        HOOK_WT_ROOT=$REC_WT
        # It writes remote-tracking refs: no own-unit partner, whichever arm
        # approves it.
        cd_same_repo "$HOOK_CWD" && git_fetch_ok "$((subidx + 1))" origin && ARM_ACT=1 && return 0
      fi
      ob_git "$sub" "$subidx" && ARM_ACT=1
      ;;
    add | commit) ob_git_partner "$sub" "$subidx" ;;
    rm | mv | restore | checkout | merge) ob_git "$sub" "$subidx" && ARM_ACT=1 ;;
    *) return 1 ;;
  esac
}

# ob_git_partner <sub> <index>: ob_git for the own-branch arm's `git add` and
# `git commit`, the two git acts that may come before an own-unit act in its
# chain (OU_PARTNER): a read their checks make (a `commit -F` file) is no
# write, so it leaves ARM_ACT as it was.
ob_git_partner() {
  local arm=$ARM_ACT
  ob_git "$1" "$2" || return 1
  ARM_ACT=$arm
  OU_PARTNER=1
}

# ls_remote_url_ok <remote>: 0 only when `git ls-remote <remote>` would use a
# built-in transport: the URL git resolves (insteadOf rewrites applied, which
# is why the configured value alone is not read) is https://, ssh://, git://,
# file://, an absolute path, or scp-style `[user@]host:path`. Any other URL,
# `<transport>::<address>` above all, makes git run a git-remote-<transport>
# helper, as does a remote's `vcs` setting, and a remote's own `uploadpack`
# names the program git runs. A host starting with `-` would be read as an ssh
# option. Asking git for the URL contacts no remote and runs no helper.
ls_remote_url_ok() {
  local url
  git -C "$HOOK_CWD" config --get "remote.$1.vcs" >/dev/null 2>&1 && return 1
  git -C "$HOOK_CWD" config --get "remote.$1.uploadpack" >/dev/null 2>&1 && return 1
  url=$(git -C "$HOOK_CWD" ls-remote --get-url "$1" 2>/dev/null) || return 1
  case $url in
    '' | *::* | *[[:cntrl:]]* | -* | *://-* | *@-*) return 1 ;;
    https://?* | ssh://?* | git://?* | file://?* | /?*) return 0 ;;
    [A-Za-z0-9._-]*:?*)
      # scp-style: no `/` before the first colon, or git reads it as a path.
      case ${url%%:*} in
        */*) return 1 ;;
      esac
      return 0
      ;;
  esac
  return 1
}

# classify_verb: the enumerated allowlist. A bare verb (no slash) is looked up
# here; the fallthrough is DEFER (REQ-A1.6). Read-only tools with NO
# file-write, code-exec, or output-to-file capability are approved with any
# flags — no flag can turn `cat`/`grep`/`ls`/`diff`/… into a writer; the tools
# that DO have a write/set/exec vector carry an explicit guard above, and every
# writer / command-runner / arbitrary-exec verb is simply absent here and so
# defers (REQ-A1.8 recognized-safe-invocation rule).
# --------------------------------------------------------------------------
# Same-command variable tracking: the assignment expansion the analyzer
# resolves (loop variables and the scratch arm's `$TMPDIR` are the others; see
# loop_header and analyze_command).
#
# Claude Code hands the hook the raw command, so `f=notes.md && grep -n x $f`
# or `P=<root> && $P/scripts/x.sh` reaches the verifier with the `$` unexpanded.
# Rather than defer those shapes, the verifier tracks a standalone assignment
# and substitutes its value into later words exactly as the shell will, so
# every screen then judges the value the command will really carry (a
# resolved `-delete` still meets find's screen, a resolved script path still
# canonicalizes):
#   * the NAME is a plain identifier, is not present in the hook's own
#     environment (an exported variable reaches every child the command runs:
#     PATH, LD_*, GIT_*, anything the operator exported), and is not a name the
#     shell itself consumes, evaluates as arithmetic, or rewrites on its own
#     (IFS, CDPATH, the BASH_* family, PS4, RANDOM, REPLY, UID...);
#   * the name and the `=` are unquoted, and the word is the WHOLE simple
#     command: an assignment PREFIX before a verb still defers (REQ-A1.9);
#   * the VALUE is any literal of a plain character set (see
#     assign_value_literal), bare or quoted as a whole from its first
#     character; one carrying an expansion, any other character, a quote
#     that starts mid-value, or a bare `=` zsh expands (leading the value,
#     or after a `:`) is assigned all the same, but leaves the variable
#     OPAQUE: a later `$NAME` stays unresolved,
#     so it may only reach a position whose approval does not read it;
#   * the assignment is unconditional and at the top level of the command:
#     opened by nothing, by `;`, or by `&&` directly after another segment
#     that carried state (an assignment or a `cd`); closed by `;`, `&&`, `||`
#     or the end. Anywhere else (a pipeline, the background, after a real
#     command's `&&` or `||`, a loop/if/case body) the shell may not set it for
#     what follows, so the whole command defers;
#   * a later top-level `&` that backgrounds the and-or list holding it
#     (`D=x && true & …`) drops it again: the list ran in a subshell, so
#     what follows sees the value from before that list, or none.
# A value holding a space is substituted only inside double quotes, where it
# stays one word in every shell; unquoted, bash splits it and zsh (the Bash
# tool's shell on macOS) does not, so there it stays unresolved. An empty
# value removes an unquoted word in both. A word carrying a literal `$`
# (single quotes, backslash) is never substituted, an unknown `$NAME` is left in
# place, and the table is per analyze_command entry, seeded only with the
# scratch arm's TMPDIR at the top level, so a `fish -c` inner
# string starts empty.

# assign_name_ok <name>: the NAME rule above.
assign_name_ok() {
  local name=$1
  case $name in
    '' | *[!A-Za-z0-9_]* | [0-9]*) return 1 ;;
  esac
  # Beside the names the shell consumes, this refuses the ones bash evaluates
  # as arithmetic on assignment (a subscript in the value runs a command),
  # keeps readonly, or rewrites by itself (`read` with no NAME sets REPLY), so
  # a modelled value would lie.
  case $name in
    IFS | PATH | CDPATH | HOME | ENV | BASH_ENV | SHELL | PWD | OLDPWD | TMPDIR | TMOUT | \
      RANDOM | SRANDOM | HISTCMD | SECONDS | LINENO | EPOCHSECONDS | EPOCHREALTIME | UID | EUID | \
      PPID | GROUPS | FUNCNAME | DIRSTACK | SHELLOPTS | REPLY | MAPFILE | COPROC | \
      GLOBIGNORE | EXECIGNORE | FIGNORE | PROMPT_COMMAND | POSIXLY_CORRECT | FUNCNEST | \
      HOSTFILE | INPUTRC | IGNOREEOF | TIMEFORMAT | histchars | auto_resume | \
      OPTIND | OPTARG | OPTERR | LANG | LANGUAGE | _ | \
      BASH* | COMP_* | READLINE_* | HIST* | LC_* | MAIL* | PS[0-9]*) return 1 ;;
  esac
  # zsh, the Bash tool's shell on macOS, gives these names a special meaning
  # as variables, as bash gives PATH and CDPATH, or types, freezes, or sets
  # them itself, refused on the same grounds as the bash names above.
  case $name in
    path | cdpath | NULLCMD | READNULLCMD | module_path | MODULE_PATH | \
      fpath | FPATH | manpath | MANPATH | \
      ARGC | GID | EGID | ERRNO | HISTSIZE | SAVEHIST | KEYTIMEOUT | LISTMAX | LOGCHECK | PERIOD | \
      SHLVL | TTYIDLE | TRY_BLOCK_ERROR | TRY_BLOCK_INTERRUPT | COLUMNS | LINES | BAUD | \
      DIRSTACKSIZE | USERNAME | STTY | ZDOTDIR | TMPPREFIX | status | pipestatus | \
      ZSH_* | funcstack | funcfiletrace | functrace | zsh_eval_context | MBEGIN | MEND | \
      options | commands | functions | aliases | parameters | argv | match | MATCH | mbegin | \
      mend | reply) return 1 ;;
  esac
  # The rest of zsh's own tables, read from its source rather than a list:
  # the special parameters it types or ties (params.c's special_params), the
  # names it sets at startup, and every parameter a module defines, read-only
  # or autoloaded on first use (zsh/parameter's, the other modules'
  # autofeatures, and zsh/system's sysparams).
  case $name in
    TERM | TERMINFO | TERMINFO_DIRS | WORDCHARS | KEYBOARD_HACK | ZLE_RPROMPT_INDENT | POSTEDIT | \
      RPS1 | RPS2 | RPROMPT | RPROMPT2 | SPROMPT | prompt | PROMPT | PROMPT2 | PROMPT3 | PROMPT4 | \
      PSVAR | psvar | fignore | mailpath | TIMEFMT | HOST | LOGNAME | CPUTYPE | MACHTYPE | OSTYPE | \
      TTY | VENDOR | signals | \
      dis_functions | functions_source | dis_functions_source | funcsourcetrace | builtins | \
      dis_builtins | reswords | dis_reswords | patchars | dis_patchars | modules | dirstack | \
      history | historywords | jobtexts | jobdirs | jobstates | nameddirs | userdirs | usergroups | \
      dis_aliases | galiases | dis_galiases | saliases | dis_saliases | \
      epochtime | zgdbm_tied | langinfo | mapfile | errnos | sysparams | termcap | terminfo | \
      WATCH | watch | widgets | keymaps | zsh_scheduled_events) return 1 ;;
  esac
  # Membership in the hook's own ENVIRONMENT, snapshotted at startup: an
  # exported name the command re-points reaches every child it runs. The
  # snapshot is what is tested, NOT `${!name+x}` — an indirect read also sees
  # every shell variable in scope, so the guard's own locals answered for the
  # name under test and `read i`, `read a` and `read name` (the helper's own
  # parameter) all deferred, which is the exact shape guard_read exists for.
  case $HOOK_ENV_NAMES in
    *"$NL$name$NL"*) return 1 ;;
  esac
  return 0
}

# bare_abs_path_ok <word>: 0 when the word is an absolute path of
# [A-Za-z0-9/._-] only, so it carries no `$`, glob, quote, or space.
bare_abs_path_ok() {
  case $1 in
    /*) ;;
    *) return 1 ;;
  esac
  case $1 in
    *[!A-Za-z0-9/._-]*) return 1 ;;
  esac
  return 0
}

# assign_value_literal <value> <value-quote-start> <mixed> <expands> <globs>
# <literal-dollar>: 0 when the value is the plain literal the VALUE rule above
# substitutes; non-zero leaves the variable opaque. The quote start is
# relative to the value (0: quoted from its first character, -1: bare).
assign_value_literal() {
  [ "$4" = 0 ] && [ "$5" = 0 ] && [ "$6" = 0 ] || return 1
  case $2 in
    -1) ;;
    0) [ "$3" = 0 ] || return 1 ;;
    *) return 1 ;;
  esac
  # An allowlist, not a list of known pattern characters: bash globs an
  # unquoted expansion with every pattern syntax a shell option can turn on
  # (extglob's `@(…)`, a lone backslash in bash 5.0), and the snapshot a
  # Bash tool shell replays can turn them on.
  case $1 in
    *[!A-Za-z0-9._/:=@%,+\ -]*) return 1 ;;
  esac
  # zsh expands a bare `=` leading an assignment value, or following a `:`,
  # as `=cmd` (the command's path); bash keeps it literal.
  if [ "$2" = -1 ]; then
    case $1 in
      =* | *:=*) return 1 ;;
    esac
  fi
  return 0
}

# track_assignment: 0 when the current one-word simple command (`cw` and its
# flag arrays, by dynamic scope, before any substitution) is a standalone
# assignment the rules admit, leaving its halves in PENDING_ASSIGN_N / _V and
# PENDING_ASSIGN_O (1: opaque) and PENDING_ASSIGN_S (the VAR_S value, see
# word_tainted) for verify_tokens to commit once it knows the segment's placement.
track_assignment() {
  local w=${cw[0]} qpos=${cqp[0]} name value eqpos v vq
  # fish has no `NAME=value` statement, so inside `fish -c` the word is not one.
  # Inside a substitution it would set a subshell's variable, never modelled.
  [ "$HOOK_DEPTH" -eq 0 ] && [ "$IN_SUBST" = 0 ] || return 1
  case $w in
    [A-Za-z_]*=*) ;;
    *) return 1 ;;
  esac
  name=${w%%=*}
  value=${w#*=}
  eqpos=${#name}
  # Once an own-unit export has run, the step names are exported: assigning
  # one again would change what later step calls read around its checks.
  if [ "$OU_EXPORTED" = 1 ]; then
    case $name in
      PLANWRIGHT_STEP_*) return 1 ;;
    esac
  fi
  # The name and the `=` must be bare: a word quoted from its start is a
  # command whose name merely contains `=`, not an assignment.
  if [ "$qpos" -ge 0 ] && [ "$qpos" -le "$eqpos" ]; then
    return 1
  fi
  assign_name_ok "$name" || return 1
  # A loop variable keeps its modelled value for the whole body pass, so the
  # body may not re-point it.
  for ((v = 0; v < VAR_C; v++)); do
    [ "${VAR_N[v]}" = "$name" ] && [ "${VAR_L[v]}" = 1 ] && return 1
  done
  vq=-1
  [ "$qpos" -lt 0 ] || vq=$((qpos - eqpos - 1))
  PENDING_ASSIGN_O=0
  assign_value_literal "$value" "$vq" "${cqm[0]}" "${cdyn[0]}" "${cglob[0]}" "${cx[0]}" \
    || PENDING_ASSIGN_O=1
  PENDING_ASSIGN_S=0
  if [ "$SUBST_N" -gt 0 ] && word_tainted 0; then
    PENDING_ASSIGN_S=$((TAINT_WEAK + 1))
  fi
  PENDING_ASSIGN_N=$name
  PENDING_ASSIGN_V=$value
  return 0
}

# expand_word <word> <mode>: substitute every `$NAME` / `${NAME}` the table
# resolves (latest assignment wins, as in the shell); any other `$` — an
# unknown or opaque name, a `${NAME:-...}` modifier, a bare `$` — is left in
# place so the word still reads as unresolved. <mode> is `split` (every
# expansion unquoted), `whole` (every expansion inside double quotes), or
# `mixed`; outside `whole`, a value holding a space is left in place too
# (see the splitting rule above). Leaves
# the result in EXPANDED (a global, so the caller needs no command
# substitution, which forks once per word).
expand_word() {
  local w=$1 mode=$2
  local out='' i=0 n=${#w} c name j k found v hit
  while [ "$i" -lt "$n" ]; do
    c=${w:i:1}
    if [ "$c" != '$' ]; then
      out="$out$c"
      i=$((i + 1))
      continue
    fi
    name=''
    if [ "${w:i+1:1}" = '{' ]; then
      j=$((i + 2))
      while [ "$j" -lt "$n" ] && [ "${w:j:1}" != '}' ]; do
        name="$name${w:j:1}"
        j=$((j + 1))
      done
      if [ "$j" -ge "$n" ]; then
        out="$out$c"
        i=$((i + 1))
        continue
      fi
      k=$((j + 1))
    else
      j=$((i + 1))
      while [ "$j" -lt "$n" ]; do
        case ${w:j:1} in
          [A-Za-z0-9_]) name="$name${w:j:1}" ;;
          *) break ;;
        esac
        j=$((j + 1))
      done
      k=$j
      # zsh, the Bash tool's shell on macOS, applies a subscript or a modifier
      # to an unbraced name directly followed by `[` or `:`, quoted or not, so
      # the value is not the name's: leave it unresolved.
      case ${w:k:1} in
        '[' | ':') name='' ;;
      esac
    fi
    hit=0
    found=''
    case $name in
      '' | *[!A-Za-z0-9_]*) ;;
      *)
        for ((v = VAR_C - 1; v >= 0; v--)); do
          if [ "${VAR_N[v]}" = "$name" ]; then
            [ "${VAR_O[v]}" = 1 ] || hit=1
            found=${VAR_V[v]}
            break
          fi
        done
        ;;
    esac
    if [ "$hit" = 1 ] && [ "$mode" != whole ]; then
      case $found in
        *' '*) hit=0 ;;
      esac
    fi
    if [ "$hit" = 1 ]; then
      [ "$name" != TMPDIR ] || [ "$SC_ON" = 0 ] || AUDIT_SC=1
      out="$out$found"
      i=$k
    else
      out="$out$c"
      i=$((i + 1))
    fi
  done
  EXPANDED=$out
}

# expand_words: rewrite the current simple command (`cw` and its flag arrays,
# by dynamic scope) with the tracked values substituted; a bare word whose
# expansions all came out empty is removed, as both shells remove it.
expand_words() {
  local i mode
  local -a nw=() nx=() nq=() nd=() ng=() nz=() nm=() ns=()
  local nn=0
  for ((i = 0; i < cwn; i++)); do
    case ${cw[i]} in
      *'$'*)
        if [ "${cx[i]}" = 0 ]; then
          if [ "${cqp[i]}" -lt 0 ]; then
            mode='split'
          elif [ "${cdyn[i]}" = 1 ]; then
            mode=whole
          else
            mode=mixed
          fi
          expand_word "${cw[i]}" "$mode"
          # A bare word that expanded to nothing is removed.
          [ "$mode" = split ] && [ -z "$EXPANDED" ] && continue
          nw[nn]=$EXPANDED
        else
          nw[nn]=${cw[i]}
        fi
        ;;
      *) nw[nn]=${cw[i]} ;;
    esac
    nx[nn]=${cx[i]}
    nq[nn]=${cqp[i]}
    nd[nn]=${cdyn[i]}
    ng[nn]=${cglob[i]}
    nz[nn]=${cz[i]-0}
    nm[nn]=${cqm[i]}
    ns[nn]=${csub[i]-}
    nn=$((nn + 1))
  done
  cw=(${nw[@]+"${nw[@]}"})
  cx=(${nx[@]+"${nx[@]}"})
  cqp=(${nq[@]+"${nq[@]}"})
  cdyn=(${nd[@]+"${nd[@]}"})
  cglob=(${ng[@]+"${ng[@]}"})
  cz=(${nz[@]+"${nz[@]}"})
  cqm=(${nm[@]+"${nm[@]}"})
  csub=(${ns[@]+"${ns[@]}"})
  cwn=$nn
}

# shift_words <n>: drop the first <n> words of the current simple command.
shift_words() {
  local i n=$1
  local -a nw=() nx=() nq=() nd=() ng=() nz=() nm=() ns=()
  for ((i = n; i < cwn; i++)); do
    nw[i - n]=${cw[i]}
    nx[i - n]=${cx[i]}
    nq[i - n]=${cqp[i]}
    nd[i - n]=${cdyn[i]}
    ng[i - n]=${cglob[i]}
    nz[i - n]=${cz[i]-0}
    nm[i - n]=${cqm[i]}
    ns[i - n]=${csub[i]-}
  done
  cw=(${nw[@]+"${nw[@]}"})
  cx=(${nx[@]+"${nx[@]}"})
  cqp=(${nq[@]+"${nq[@]}"})
  cdyn=(${nd[@]+"${nd[@]}"})
  cglob=(${ng[@]+"${ng[@]}"})
  cz=(${nz[@]+"${nz[@]}"})
  cqm=(${nm[@]+"${nm[@]}"})
  csub=(${ns[@]+"${ns[@]}"})
  cwn=$((cwn > n ? cwn - n : 0))
}

# --------------------------------------------------------------------------
# Words whose value is not their text. The hook sees the command unexpanded, so
# a word carrying an expansion the analyzer did not resolve (an unknown or
# special `$` parameter, a `${…}` modifier, a glob, a brace expansion, a leading
# tilde) can hold any value at run time: `find . $_` after a printf of
# `-exec id ;` runs id. Such a word may only reach a verb whose approval does
# not read that word (arg_independent_verb); anywhere else, and always in the
# verb position, it defers. One exception: a verb that opens its operands
# (opens_operands) could be pointed at another process's environment, so an
# unknown `$` value there defers too (opener_word_risky).

# word_unresolved <word> <expands> <globs> <literal-dollar>: 0 when the word,
# after tracked substitution, still carries an expansion the analyzer did not
# resolve. A word mixing a literal and an expanding `$` is never substituted.
word_unresolved() {
  [ "$3" = 1 ] && return 0
  [ "$2" = 0 ] && return 1
  [ "$4" = 1 ] && return 0
  case $1 in
    *'$'*) return 0 ;;
  esac
  return 1
}

# arg_independent_verb <verb>: the verbs whose approval reads no operand value,
# so an opaque operand is equivalent to some literal they already approve,
# short of the environ rule (opens_operands). printf qualifies past its
# format only (guard_printf).
arg_independent_verb() {
  case $1 in
    cat | head | tail | wc | cut | comm | cmp | basename | dirname | realpath | pwd | echo | seq | true | false | od | tr | stat | grep | ls | diff) return 0 ;;
    printenv | readlink | nl | paste | column | md5sum | sha1sum | sha256sum | sha512sum | cksum | shellcheck | yamllint) return 0 ;;
  esac
  return 1
}

# opens_operands <verb>: the verbs that open a file operand and print what
# it holds, part of it, or a digest of it. Only their words and the
# redirects meet the environ test below, so `grep environ f` and
# `git log --grep environ` stay approvable. An unresolved word reaching one
# of them that is also argument-independent could name another process's
# environment, `$_` after an `echo` of that path included, so it defers.
opens_operands() {
  case $1 in
    cat | head | tail | wc | cut | comm | cmp | od | grep | diff | nl | paste | column) return 0 ;;
    md5sum | sha1sum | sha256sum | sha512sum | cksum | shellcheck | yamllint) return 0 ;;
    sort | uniq | file | sed | awk | jq | yq | rg | shfmt | markdownlint | markdownlint-cli2) return 0 ;;
  esac
  return 1
}

# opener_word_risky <word> <literal-dollar> <globs>: 0 when an operand of
# an opens_operands verb, still unresolved after substitution, could name
# another process's environ file. A `$` with no tracked literal behind it
# could be any path. A tracked value kept unresolved only for its spaces is
# known, so each word bash or zsh could make of it is checked instead, as
# the glob the word's own pattern characters make it.
opener_word_risky() {
  local piece
  local -a pieces
  case $1 in
    *'$'*) ;;
    *) return 1 ;;
  esac
  [ "$2" = 0 ] || return 0
  expand_word "$1" whole
  case $EXPANDED in
    *'$'*) return 0 ;;
  esac
  environ_word_risky "$EXPANDED" "$3" && return 0
  IFS=' ' read -r -a pieces <<<"$EXPANDED"
  for piece in ${pieces[@]+"${pieces[@]}"}; do
    environ_word_risky "$piece" "$3" && return 0
  done
  return 1
}

# Other processes' environments. /proc/<pid>/environ holds another
# process's environment (credentials included), and /proc/<pid>/mem its
# memory; the reading process's own environ is the worker's environment
# and defers with them. A redirect source, or a word of a verb
# that opens its operands, whose last component is `environ` or `mem`
# defers, since a `..`, /dev/fd, or a symlink can reach /proc from any
# directory. So does a glob whose last component could match either, unless
# its directory exists and canonicalizes outside /proc.

# environ_word_risky <word> <globs>: 0 when the word could name a secret
# (secret_word_risky), or any process's environ or mem file.
environ_word_risky() {
  local w=$1 last dir canon
  # `//proc` names /proc to the kernel, and bash's `cd -P` keeps the two
  # slashes, so neither test below would see /proc in it.
  while [ "${w#*//}" != "$w" ]; do
    w=${w//\/\//\/}
  done
  # The tower still reads its own environment; a worker defers.
  if [ "$2" = 0 ] && [ "$GUARD_OWN_ENVIRON" = 1 ]; then
    case $w in
      /proc/self/environ | /proc/thread-self/environ) return 1 ;;
    esac
  fi
  secret_word_risky "$w" "$2" && return 0
  last=${w##*/}
  # `mem` holds the whole process's memory, its environment included.
  case $last in
    environ | mem) return 0 ;;
  esac
  [ "$2" = 1 ] || return 1
  # Pattern syntax beyond `*`, `?`, and `[…]` (braces, zsh's extended
  # characters, a backslash) is not matched here, only assumed to match.
  case $last in
    *[{}\\~^#\<\>\|]*) ;;
    *)
      # shellcheck disable=SC2053 # the operand is the pattern under test
      [[ environ == $last || mem == $last ]] || return 1
      ;;
  esac
  # fish's `**` descends into subdirectories, through symlinks too, so no
  # directory test can bound where it matches.
  case $last in
    *'**'*) return 0 ;;
  esac
  case $w in
    */*)
      dir=${w%/*}
      [ -n "$dir" ] || dir=/
      ;;
    *) dir=. ;;
  esac
  # A process directory can appear between this check and the run, so a
  # path through any `proc` component (`/./proc`, `../../proc`) defers
  # whether or not it exists now.
  case $dir in
    *[*?[{}~\$]* | proc | proc/* | */proc | */proc/*) return 0 ;;
  esac
  case $dir in
    /*) ;;
    *) dir=$HOOK_CWD/$dir ;;
  esac
  # The guard resolves the directory in its own process, so one it cannot
  # enter may still resolve for the command (`/dev/fd/0` with a /proc
  # directory on the command's stdin), and defers.
  canon_dir_cached "$dir"
  canon=$CANON
  [ -n "$canon" ] || return 0
  case $canon in
    /proc | /proc/*) return 0 ;;
  esac
  return 1
}

# Secret-bearing locations. Credentials live in a handful of home-directory
# dotfiles and system files, and a file descriptor or process memory can hand
# the reader whatever the worker's own process holds, so a reader meeting any
# of them defers in every spelling: absolute, relative to the tracked cwd,
# `~`, `$HOME`, repeated slashes, `..`, a symlinked directory or final
# component, and a glob that could match one. Home-directory names are matched
# as path components, so they hold for any account's home.

# secret_lexical <path>: 0 when the path, read as written, names a secret.
secret_lexical() {
  local s=$1 had=1 hit=1
  case $s in
    /*) ;;
    *) s=/$s ;;
  esac
  s=$s/
  # A case-insensitive volume (macOS's default) opens `~/.SSH` as `~/.ssh`.
  shopt -q nocasematch && had=0
  shopt -s nocasematch
  case $s in
    */.ssh/* | */.gnupg/* | */.aws/* | */.netrc/* | */.npmrc/* | */.pypirc/* | */.git-credentials/* | \
      */.kube/* | */.azure/* | */.password-store/* | */.docker/* | */.dockercfg/* | \
      */.pgpass/* | */.my.cnf/* | */.s3cfg/* | */.boto/* | */.oci/* | */.m2/settings*.xml/* | \
      */.composer/auth.json/* | */.config/composer/auth.json/* | */.config/containers/auth.json/* | \
      */.local/share/keyrings/* | */Library/Keychains/* | \
      */.config/gh/* | */.config/hub/* | */.config/op/* | */.config/gcloud/* | */.config/git/credentials/* | \
      */.config/rclone/* | */.config/doctl/* | */.config/glab-cli/* | */.config/github-copilot/* | \
      */.cargo/credentials* | */.gem/credentials/* | \
      */.terraform.d/credentials* | */.vault-token/* | \
      */.claude/.credentials* | */.claude.json/*) hit=0 ;;
  esac
  [ "$had" -eq 0 ] || shopt -u nocasematch
  [ "$hit" -ne 0 ] || return 0
  case $s in
    /etc/letsencrypt/* | /etc/NetworkManager/system-connections/* | /etc/wireguard/* | /etc/pki/tls/private/* | \
      /etc/master.passwd/* | /private/etc/master.passwd/* | *.keytab/*) return 0 ;;
    /etc/shadow/* | /etc/gshadow/* | /etc/shadow-/* | /etc/gshadow-/* | /etc/ssh/ssh_host_*_key/* | /etc/sudoers/* | /etc/sudoers.d/* | /etc/ssl/private/*) return 0 ;;
    # macOS keeps /etc under /private, which a resolved path reports.
    /private/etc/shadow/* | /private/etc/gshadow/* | /private/etc/ssh/ssh_host_*_key/* | /private/etc/sudoers/* | /private/etc/sudoers.d/* | /private/etc/ssl/private/*) return 0 ;;
    /proc/*/?* | /dev/fd/* | /dev/stdin/*) return 0 ;;
    # Container and service secrets, and Debian's shadow backups.
    /run/secrets/* | /var/run/secrets/* | /private/var/run/secrets/* | /run/credentials/* | /var/backups/*shadow* | /run/user/*/containers/auth.json/*) return 0 ;;
  esac
  return 1
}

# secret_glob <absolute-word>: 0 when a word with pattern characters could
# match a secret: a literal sample of each system file, or a component that
# starts with a dot and could match a secret directory name. Braces and zsh's
# pattern operators defer when the word names a system directory or a dotted
# component, since they are not matched here.
secret_glob() {
  secret_glob_word "$1" && return 0
  # The word as written misses the samples when it has `.`, `..` or repeated
  # slashes, so its lexical form is tested too.
  lexical_path "$1"
  [ "$LEX" != "$1" ] || return 1
  secret_glob_word "$LEX"
}

# lexical_path <absolute-path>: the path with `.`, `..` and repeated slashes
# resolved as text, `..` clamped at the root, left in LEX. Split by parameter
# expansion, not `IFS=/ read`: macOS's bash 3.2 mis-splits that one-shot form
# while a caller has IFS empty.
lexical_path() {
  local rest=$1/ comp
  LEX=''
  while [ -n "$rest" ]; do
    comp=${rest%%/*}
    rest=${rest#*/}
    case $comp in
      '' | .) ;;
      ..) LEX=${LEX%/*} ;;
      *) LEX=$LEX/$comp ;;
    esac
  done
  [ -n "$LEX" ] || LEX=/
}

secret_glob_word() {
  local w=$1 s c n IFS=/
  local -a parts
  case $w in
    *[\{^#~]*)
      case $w in
        /etc* | /proc* | /dev* | */.* | *[\{,]\.*) return 0 ;;
      esac
      ;;
  esac
  case $w in
    /proc/*/?*) return 0 ;;
  esac
  # A pattern in the top directory's name (`/pro[c]`, `/e?c`) could be any
  # system root.
  c=${w#/}
  c=${c%%/*}
  case $c in
    *[*?[]*)
      for n in proc etc dev run var root home Users private; do
        # shellcheck disable=SC2053
        [[ $n == $c ]] && return 0
      done
      ;;
  esac
  for s in /etc/shadow /etc/gshadow /etc/shadow- /etc/gshadow- /etc/sudoers /etc/ssl/private/k.pem /proc/1/mem /dev/fd/0 /dev/stdin \
    /etc/ssh/ssh_host_rsa_key /etc/ssh/ssh_host_ed25519_key \
    /run/secrets/x /var/run/secrets/x /run/credentials/x /var/backups/shadow.bak /var/backups/gshadow.bak /run/user/0/containers/auth.json; do
    # shellcheck disable=SC2053 # the operand is the pattern under test
    [[ $s == $w ]] && return 0
  done
  read -r -a parts <<<"$w"
  for c in ${parts[@]+"${parts[@]}"}; do
    case $c in
      .*[*?[]*)
        for n in .ssh .gnupg .aws .netrc .npmrc .pypirc .git-credentials .kube .azure .password-store .claude.json \
          .docker .dockercfg .pgpass .my.cnf .s3cfg .boto .oci .vault-token; do
          # shellcheck disable=SC2053
          [[ $n == $c ]] && return 0
        done
        ;;
    esac
  done
  return 1
}

# secret_home_glob <home-relative-pattern>: 0 when a pattern read from some
# account's home (`~name/…`, `~+/…`, `~-/…`, whose home this guard cannot
# expand) could match a well-known credential file, ignoring case as
# secret_lexical does.
secret_home_glob() {
  local s had=1 hit=1
  shopt -q nocasematch && had=0
  shopt -s nocasematch
  for s in /.ssh/id_rsa /.gnupg/pubring.kbx /.aws/credentials /.netrc /.npmrc /.git-credentials /.kube/config /.docker/config.json \
    /.config/gh/hosts.yml /.config/gcloud/credentials.db /.config/op/config /.config/rclone/rclone.conf /.config/containers/auth.json \
    /.config/git/credentials /.local/share/keyrings/login.keyring /.cargo/credentials.toml /.claude/.credentials.json \
    /.pypirc /.azure/accessTokens.json /.password-store/x.gpg /.dockercfg /.pgpass /.my.cnf /.s3cfg /.boto /.oci/config \
    /.m2/settings.xml /.composer/auth.json /.config/composer/auth.json /Library/Keychains/login.keychain-db /.config/hub/config \
    /.config/doctl/config.yaml /.config/glab-cli/config.yml /.config/github-copilot/hosts.json /.gem/credentials \
    /.terraform.d/credentials.tfrc.json /.vault-token /.claude.json; do
    # shellcheck disable=SC2053 # the operand is the pattern under test
    if [[ $s == $1 ]]; then
      hit=0
      break
    fi
  done
  [ "$had" -eq 0 ] || shopt -u nocasematch
  return "$hit"
}

# secret_word_risky <word> <globs>: 0 when the word, or the value an
# `--option=value` word carries, could name a secret. The word has its
# repeated slashes collapsed already.
secret_word_risky() {
  local w=$1
  secret_path_risky "$w" "$2" && return 0
  case $w in
    -*=*) secret_path_risky "${w#*=}" "$2" && return 0 ;;
    # A short option's attached operand (`-f/etc/shadow`, `-nf~/.ssh/k`).
    -[!-]*[/~]*)
      secret_path_risky "${w:2}" "$2" && return 0
      case $w in
        */*) secret_path_risky "/${w#*/}" "$2" && return 0 ;;
      esac
      case $w in
        *\~*) secret_path_risky "~${w#*\~}" "$2" && return 0 ;;
      esac
      ;;
  esac
  return 1
}

# secret_path_risky <path> <globs>: the path as written, then resolved from
# the tracked cwd through its directory's canonical form and, for a symlink,
# its target.
secret_path_risky() {
  local p=$1 abs dir last tgt link hop=0
  case $p in
    '~'*)
      case $p in
        */*) p=/${p#*/} ;;
        *) return 1 ;;
      esac
      ;;
    "\$HOME"/* | "\${HOME}"/*) p=/${p#*/} ;;
  esac
  secret_lexical "$p" && return 0
  case $p in
    /*) abs=$p ;;
    *) abs=$HOOK_CWD/$p ;;
  esac
  while [ "${abs%/}" != "$abs" ] && [ "$abs" != / ]; do
    abs=${abs%/}
  done
  if [ "$2" = 1 ]; then
    # Braces and zsh operators are not expanded here: one that can leave the
    # tracked cwd (an absolute word, a `..`) is not followed.
    case $p in
      *[\{^#~]*)
        case $p in
          /* | *..*) return 0 ;;
        esac
        ;;
    esac
    secret_glob "$abs" && return 0
    case $1 in
      '~'/*) ;;
      # Another account's home, or `~+`/`~-`: no home to expand it against.
      '~'?*/*)
        case $p in
          *..*) return 0 ;;
        esac
        secret_home_glob "$p" && return 0
        ;;
    esac
    # The lexical tests read a home-relative word from `/`; its matches come
    # from the home itself.
    case $1 in
      '~'/* | "\$HOME"/* | "\${HOME}"/*)
        [ -n "$HOME" ] || return 0
        glob_any_risky secret "$HOME$p"
        return
        ;;
    esac
    glob_any_risky secret "$abs"
    return
  fi
  secret_lexical "$abs" && return 0
  last=${abs##*/}
  dir=${abs%/*}
  [ -n "$dir" ] || dir=/
  canon_dir_cached "$dir"
  [ -n "$CANON" ] || return 1
  case $CANON in
    /) tgt=/$last ;;
    *) tgt=$CANON/$last ;;
  esac
  secret_lexical "$tgt" && return 0
  # A symlink chain followed link by link (`readlink -f` is GNU-only); one
  # that loops or cannot be read defers.
  while [ -L "$tgt" ]; do
    hop=$((hop + 1))
    [ "$hop" -le 16 ] || return 0
    link=$(readlink -- "$tgt") || return 0
    case $link in
      /*) ;;
      *) link=${tgt%/*}/$link ;;
    esac
    secret_lexical "$link" && return 0
    dir=${link%/*}
    [ -n "$dir" ] || dir=/
    canon_dir_cached "$dir"
    [ -n "$CANON" ] || return 1
    tgt=${CANON%/}/${link##*/}
    secret_lexical "$tgt" && return 0
  done
  return 1
}

# glob_any_risky <secret|broad> <absolute-pattern>: expands the pattern as the
# shell would and screens every match as a plain path, so a pattern that
# reaches a secret through `..`, a symlink or a glob in a system directory's
# name (`/pro[c]`) is caught. More matches than are screened defer.
glob_any_risky() {
  local kind=$1 pat=$2 m n=0 IFS='' had_null=0 noglob=0
  local -a ms
  shopt -q nullglob && had_null=1
  case $- in *f*) noglob=1 ;; esac
  set +f
  shopt -s nullglob
  # shellcheck disable=SC2206 # the expansion is the point; IFS is empty
  ms=($pat)
  [ "$had_null" = 1 ] || shopt -u nullglob
  [ "$noglob" = 0 ] || set -f
  # The screens below assume the default IFS.
  IFS=$' \t\n'
  for m in ${ms[@]+"${ms[@]}"}; do
    n=$((n + 1))
    [ "$n" -le 2048 ] || return 0
    case $kind in
      secret) secret_path_risky "$m" 0 && return 0 ;;
      *) broad_path_risky "$m" && return 0 ;;
    esac
  done
  return 1
}

# lists_operands <verb>: the verbs that print the names inside a directory
# operand. A listing of a secret-bearing directory names the key files, so
# they meet the secret screen too, though not the environ one. `date` joins
# them: `-r FILE` and `--reference=FILE` report a file's modification time.
lists_operands() {
  case $1 in
    ls | find | fd | date) return 0 ;;
  esac
  return 1
}

# secret_words_ok: no word of the current simple command could name a secret.
secret_words_ok() {
  local i g w
  for ((i = 0; i < cwn; i++)); do
    g=${cglob[i]}
    [ "${cz[i]-0}" = 0 ] || g=1
    w=${cw[i]}
    while [ "${w#*//}" != "$w" ]; do
      w=${w//\/\//\/}
    done
    secret_word_risky "$w" "$g" && return 1
  done
  return 0
}

# recursive_reader: the current simple command reads, or lists, everything
# under its directory operands: `find`, `fd`, `tree` and `rg` always, `grep`
# and `diff` with a recursive flag, `ls -R`.
recursive_reader() {
  local i w
  case ${cw[0]} in
    find | fd | tree | rg) return 0 ;;
    grep | egrep | fgrep | diff | ls | file)
      for ((i = 1; i < cwn; i++)); do
        w=${cw[i]}
        case $w in
          # grep abbreviates a long option to any unambiguous prefix.
          --rec* | --der* | --dir*=rec* | --dir | --dire | --direc | --direct | --directo | --director | --directories) return 0 ;;
          --*) ;;
          -d) return 0 ;;
          -*[rRd]*) return 0 ;;
        esac
      done
      ;;
  esac
  return 1
}

# broad_dir <absolute-dir>: a directory that holds secret-bearing locations
# below it, so a recursive read of it reaches them: the filesystem and system
# roots, every home directory, the account's own home, the parents of the
# credential directories, and a secret location itself.
broad_dir() {
  local x=$1 had=1 hit=1
  # Matched ignoring case, as secret_lexical is (`~/.CONFIG` on macOS).
  shopt -q nocasematch && had=0
  shopt -s nocasematch
  case $x in
    / | /etc | /etc/ssh | /etc/ssl | /etc/sudoers.d | /root | /home | /Users | /private | /private/etc | /proc | /proc/* | /dev | /dev/*) hit=0 ;;
    # Runtime secrets, backups, and mounted volumes (another system's homes).
    # Only a volume's root: a worktree may live further down one.
    /run | /run/user | /run/user/* | /var | /var/run | /var/lib | /var/lib/* | /var/backups | /private/var | /private/var/run | /mnt | /media | /srv | /Volumes) hit=0 ;;
    /mnt/*/* | /media/*/* | /Volumes/*/*) ;;
    /mnt/* | /media/* | /Volumes/*) hit=0 ;;
    /root/.claude | /root/.config | /home/*/.claude | /home/*/.config | /Users/*/.claude | /Users/*/.config) hit=0 ;;
    /home/*/* | /Users/*/*) ;;
    /home/* | /Users/*) hit=0 ;;
  esac
  if [ "$hit" -ne 0 ] && [ -n "$HOME" ]; then
    case $x in
      "$HOME" | "$HOME/.claude" | "$HOME/.config") hit=0 ;;
    esac
  fi
  [ "$had" -eq 0 ] || shopt -u nocasematch
  [ "$hit" -ne 0 ] || return 0
  secret_lexical "$x"
}

# broad_canon <canonical-dir>: broad_dir, or the account's own home as its
# canonical path (macOS's /tmp is /private/tmp).
broad_canon() {
  broad_dir "$1" && return 0
  canon_dir_cached "$HOME"
  if [ -n "$CANON" ]; then
    case $1 in
      "$CANON" | "$CANON/.claude" | "$CANON/.config") return 0 ;;
    esac
  fi
  return 1
}

# broad_path_risky <word>: the operand names a directory broad_dir flags,
# written as is, through `~` or `$HOME`, with dot components, or through a
# symlink.
broad_path_risky() {
  local p=$1 abs out root
  while [ "${p#*//}" != "$p" ]; do
    p=${p//\/\//\/}
  done
  case $p in
    \~ | \~/*)
      [ -n "$HOME" ] || return 0
      p=$HOME${p#\~}
      ;;
    \$HOME | \$HOME/*)
      [ -n "$HOME" ] || return 0
      p=$HOME${p#\$HOME}
      ;;
    \$\{HOME\} | \$\{HOME\}/*)
      [ -n "$HOME" ] || return 0
      p=$HOME${p#\$\{HOME\}}
      ;;
    \~*) return 0 ;;
  esac
  case $p in
    /*) abs=$p ;;
    *) abs=$HOOK_CWD/$p ;;
  esac
  # A `..` after a symlink climbs from the link's target, not from the link.
  case $abs in
    */.. | */../*)
      canon_dir_cached "$abs"
      if [ -n "$CANON" ]; then
        broad_path_risky "$CANON" && return 0
      fi
      ;;
  esac
  lexical_path "$abs"
  out=$LEX
  broad_dir "$out" && return 0
  canon_dir_cached "$out"
  out=$CANON
  [ -n "$out" ] || return 1
  broad_canon "$out" && return 0
  # A parent of the worktree holds its siblings and, further up, the home.
  # The payload's cwd names the worktree while HOOK_CWD follows a cd out of it.
  root=$(repo_root_of "${HOOK_PAYLOAD_CWD:-$HOOK_CWD}") || return 0
  [ "$out" != "$root" ] || return 1
  case $root/ in
    "$out"/*) return 0 ;;
  esac
  return 1
}

# broad_glob_risky <word>: a recursive operand with a pattern or brace: the
# directory before the first pattern character is what is checked, and any
# alternative that could leave it (`~`, `$`, `..`, an absolute path) defers.
broad_glob_risky() {
  local w=$1 lit dir
  while [ "${w#*//}" != "$w" ]; do
    w=${w//\/\//\/}
  done
  case $w in
    *..* | *\$* | *\~* | *,/* | *\{/*) return 0 ;;
  esac
  lit=${w%%[\*\?\[\{]*}
  case $lit in
    */*) dir=${lit%/*} ;;
    *) dir=. ;;
  esac
  [ -n "$dir" ] || dir=/
  broad_path_risky "$dir" && return 0
  case $w in
    *[\{^#]*) return 1 ;;
    /*) glob_any_risky broad "$w" ;;
    *) glob_any_risky broad "$HOOK_CWD/$w" ;;
  esac
}

# broad_words_ok: no operand of the current recursive reader names a broad
# directory.
broad_words_ok() {
  local i
  for ((i = 1; i < cwn; i++)); do
    case ${cw[i]} in
      # An option's attached directory (`--search-path=`, `--from-file=`).
      -*=?*)
        broad_path_risky "${cw[i]#*=}" && return 1
        continue
        ;;
      -*) continue ;;
    esac
    # A variable the tracker could not resolve may name any directory; a
    # word carrying substitution output is subst_reach_ok's to judge.
    case ${cw[i]} in
      *[\$\`]*)
        if word_unresolved "${cw[i]}" "${cdyn[i]}" 0 "${cx[i]}"; then
          word_tainted "$i" && [ "${TAINT_WEAK:-0}" = 0 ] || return 1
        fi
        ;;
    esac
    if [ "${cglob[i]}" != 0 ] || [ "${cz[i]-0}" != 0 ]; then
      broad_glob_risky "${cw[i]}" && return 1
    fi
    broad_path_risky "${cw[i]}" && return 1
  done
  return 0
}

# link_follower: the current simple command follows a symbolic link it meets
# inside a tree it reads recursively: `grep -R`, `rg -L`/`--follow`, and
# `diff -r` (grep and ripgrep follow only a command-line link otherwise).
link_follower() {
  local i w
  for ((i = 1; i < cwn; i++)); do
    w=${cw[i]}
    case ${cw[0]} in
      grep | egrep | fgrep)
        case $w in
          --der*) return 0 ;;
          --*) ;;
          -*R*) return 0 ;;
        esac
        ;;
      rg)
        case $w in
          --fo*) return 0 ;;
          --*) ;;
          -*L*) return 0 ;;
        esac
        ;;
      # A directory pair compares same-named files through links, recursive or not.
      diff) return 0 ;;
    esac
  done
  return 1
}

# follow_links_ok: no symbolic link inside a directory operand of a
# link_follower leads to a secret or a broad directory. Links met under a
# linked directory are followed too, up to a few directories. diff reads a
# linked file only against the same name in its other tree, so only a link
# with a counterpart there counts. A glob operand, or more links than are
# screened, defers; with no directory operand the reader scans the cwd.
follow_links_ok() {
  local i w d other rel l n=0 qi=0 k canon diff=0 rec=0 miss=0
  local -a dirs=() queue=()
  [ "${cw[0]}" != diff ] || diff=1
  for ((i = 1; i < cwn; i++)); do
    w=${cw[i]}
    case $w in
      --rec*) rec=1 ;;
      # An absent file read as empty prints the other side's link target, and
      # a --from-file or --to-file tree is paired with every other operand.
      --new* | --unid*) miss=1 ;;
      --from-file=* | --to-file=*)
        miss=1
        w=${w#*=}
        ;;
      --from-file | --to-file) miss=1 ;;
      --*) ;;
      -*)
        case $w in *r*) rec=1 ;; esac
        case $w in *[NP]*) miss=1 ;; esac
        ;;
    esac
    case $w in -*) continue ;; esac
    [ "${cglob[i]}" = 0 ] && [ "${cz[i]-0}" = 0 ] || return 1
    case $w in
      /*) d=$w ;;
      *) d=$HOOK_CWD/$w ;;
    esac
    if [ -d "$d" ]; then
      dirs[${#dirs[@]}]=$d
    fi
  done
  # A plain diff reads no link unless a directory operand holds one.
  [ "$diff" = 0 ] || [ "$rec" = 1 ] || [ "${#dirs[@]}" -gt 0 ] || return 0
  [ "${#dirs[@]}" -gt 0 ] || dirs[0]=$HOOK_CWD
  # Names are paired only for exactly two trees and no flag that reads a
  # missing counterpart as empty; otherwise every link counts.
  { [ "${#dirs[@]}" -eq 2 ] && [ "$miss" = 0 ]; } || diff=0
  queue=("${dirs[@]}")
  while [ "$qi" -lt "${#queue[@]}" ]; do
    d=${queue[qi]}
    other=''
    # A tree reached through a link has no counterpart to pair against.
    if [ "$diff" = 1 ] && [ "$qi" -lt 2 ]; then
      [ "$qi" -ne 0 ] && other=${dirs[0]} || other=${dirs[1]}
    fi
    qi=$((qi + 1))
    while IFS= read -r -d '' l; do
      n=$((n + 1))
      [ "$n" -le 512 ] || return 1
      if [ -n "$other" ]; then
        rel=${l#"${d%/}"/}
        [ -e "$other/$rel" ] || [ -L "$other/$rel" ] || continue
      fi
      secret_path_risky "$l" 0 && return 1
      broad_path_risky "$l" && return 1
      if [ -d "$l" ]; then
        canon_dir_cached "$l"
        [ -n "$CANON" ] || continue
        canon=$CANON
        for ((k = 0; k < ${#queue[@]}; k++)); do
          [ "${queue[k]}" != "$canon" ] || continue 2
        done
        [ "${#queue[@]}" -lt 16 ] || return 1
        queue[${#queue[@]}]=$canon
      fi
    done < <(find -H "$d" -type l -print0 2>/dev/null)
  done
  return 0
}

# ci_has <word> <glob>...: whether the word matches any glob, ignoring case.
# nocasematch rather than ${w,,}, which bash 3.2 (the macOS /bin/bash) lacks.
ci_has() {
  local w=$1 p hit=1 had=1
  shift
  shopt -q nocasematch && had=0
  shopt -s nocasematch
  for p in "$@"; do
    # shellcheck disable=SC2254  # the glob is the argument, deliberately unquoted
    case $w in $p) hit=0 ;; esac
  done
  [ "$had" -eq 0 ] || shopt -u nocasematch
  return "$hit"
}

# secret_var_name <name>: whether a variable name looks like a credential.
secret_var_name() {
  ci_has "$1" '*TOKEN*' '*SECRET*' '*PASSWORD*' '*PASSWD*' '*PASSPHRASE*' '*CREDENTIAL*' '*APIKEY*' '*API_KEY*' \
    '*ACCESS_KEY*' '*_KEY' '*_PAT' '*BEARER*' 'AUTH' '*_AUTH' '*AUTHORIZATION*' '*_PASS' '*_PWD' '*COOKIE*' \
    '*_DSN' 'DSN' '*DATABASE_URL*' 'JWT' '*_JWT' 'JWT_*'
}

# secret_var_ref <word>: whether a word expands a credential-named variable
# (any `$NAME`, `${NAME…}`, `${#NAME}`, zsh's `$=NAME`/`$^NAME`, or an
# indirect `${!…}`). A quoted single-quote form cannot be told apart here, so
# it defers too. The word is unquoted already, so a name that ended at a
# quote or escape (`"$DEPLOY_KEY"1`) is looked for in the raw command.
secret_var_ref() {
  local w=$1 rest name k p
  case $w in
    *\$\{!*) return 0 ;;
  esac
  while [ "${w#*\$}" != "$w" ]; do
    rest=${w#*\$}
    w=$rest
    rest=${rest#\{}
    rest=${rest#[\#=^~+]}
    name=${rest%%[!A-Za-z0-9_]*}
    [ -n "$name" ] || continue
    secret_var_name "$name" && return 0
    for ((k = ${#name} - 1; k >= 2; k--)); do
      p=${name:0:k}
      case ${HOOK_RAW_CMD-} in
        *"\$$p\""* | *"\$$p'"* | *"\$$p\\"*) secret_var_name "$p" && return 0 ;;
      esac
    done
  done
  return 1
}

# secret_vars_ok: no word of the current simple command expands a credential
# variable, and no printenv operand names one.
secret_vars_ok() {
  local i
  for ((i = 0; i < cwn; i++)); do
    secret_var_ref "${cw[i]}" && return 1
    if [ "${cw[0]}" = printenv ] && [ "$i" -ge 1 ]; then
      secret_var_name "${cw[i]}" && return 1
    fi
  done
  return 0
}

# canon_dir_cached <absolute-dir>: the directory's canonical path in CANON,
# empty when it cannot be entered. Each lookup forks, and a loop re-walks
# its body once per head word, so results are kept for the hook's run.
canon_dir_cached() {
  local k n=${CANON_N:-0}
  for ((k = 0; k < n; k++)); do
    if [ "${CANON_D[k]}" = "$1" ]; then
      CANON=${CANON_P[k]}
      return 0
    fi
  done
  CANON=$(cd -P -- "$1" 2>/dev/null && pwd) || CANON=''
  if [ "$n" -lt 64 ]; then
    CANON_D[n]=$1
    CANON_P[n]=$CANON
    CANON_N=$((n + 1))
  fi
  return 0
}

# environ_words_ok: no word of the current simple command could name
# another process's environ file. grep and rg read their first operand as
# the pattern unless a flag anywhere supplies one (GNU grep permutes its
# arguments); any short cluster holding `e` or `f` is taken to, so the
# pattern is skipped only when it surely is one.
environ_words_ok() {
  local i pi=0 opts=1 given=0 g
  case ${cw[0]} in
    grep | rg)
      for ((i = 1; i < cwn; i++)); do
        if [ "$opts" = 1 ]; then
          case ${cw[i]} in
            --)
              opts=0
              continue
              ;;
            # GNU grep takes any unambiguous prefix (`--reg=`, `--fil`).
            --reg* | --fil | --file | --file=*)
              given=1
              continue
              ;;
            --*) continue ;;
            -?*)
              case ${cw[i]} in
                -*[ef]*) given=1 ;;
              esac
              continue
              ;;
          esac
        fi
        [ "$pi" -gt 0 ] || pi=$i
      done
      [ "$given" = 0 ] || pi=0
      # A pattern that can expand into several words (a glob, a brace, an
      # expansion) hands grep its later words as files, so it is checked.
      if [ "$pi" -gt 0 ]; then
        [ "${cglob[pi]}" = 0 ] && [ "${cdyn[pi]}" = 0 ] && [ "${cz[pi]-0}" = 0 ] || pi=0
      fi
      ;;
  esac
  for ((i = 0; i < cwn; i++)); do
    [ "$i" -eq "$pi" ] && [ "$pi" -gt 0 ] && continue
    # A character zsh's EXTENDED_GLOB makes an operator (`#`, `^`, a
    # mid-word `~`) is flagged apart from globs, but matches like one.
    g=${cglob[i]}
    [ "${cz[i]-0}" = 0 ] || g=1
    environ_word_risky "${cw[i]}" "$g" && return 1
  done
  return 0
}

# environ_redirect_ok <operand>: the same tests (secrets and environ files)
# for a redirect operand, which
# the guard never expands, so any `$` in it could name anything. Any other
# path under /proc defers too: a process directory on stdin lets a later
# `/dev/fd/0/…` reach into it, out of the guard's sight.
environ_redirect_ok() {
  local g=0 w=$1
  case $w in
    *'$'*) return 1 ;;
    *[*?[\{~#^]*) g=1 ;;
  esac
  while [ "${w#*//}" != "$w" ]; do
    w=${w//\/\//\/}
  done
  if [ "$g" = 0 ] && [ "$GUARD_OWN_ENVIRON" = 1 ]; then
    case $w in
      /proc/self/environ | /proc/thread-self/environ) return 0 ;;
    esac
  fi
  case $w in
    proc | proc/* | */proc | */proc/*) return 1 ;;
  esac
  environ_word_risky "$w" "$g" && return 1
  return 0
}

# guard_test: `test`/`[` evaluate a `-v` operand as an array subscript, which
# runs any `$(…)` inside it even when the word was single-quoted.
guard_test() {
  local i
  for ((i = 1; i < cwn; i++)); do
    [ "${cw[i]}" = -v ] && return 1
  done
  return 0
}

# printf_format_inert <format>: 0 when every conversion in the literal
# format reads its operand as text (`%s`, `%b`, `%q`, `%c`, or `%%`) and none
# takes a `*` width or precision. zsh evaluates an operand a numeric
# conversion or a `*` consumes as arithmetic, which can assign a variable.
printf_format_inert() {
  local f=$1
  while :; do
    case $f in
      *%*) f=${f#*%} ;;
      *) return 0 ;;
    esac
    while :; do
      case ${f:0:1} in
        - | + | ' ' | '#' | "'" | . | [0-9]) f=${f#?} ;;
        '*') return 1 ;;
        *) break ;;
      esac
    done
    case ${f:0:1} in
      s | b | q | c | %) f=${f#?} ;;
      *) return 1 ;;
    esac
  done
}

# guard_printf: `printf -v NAME` assigns a variable (PATH included) and
# evaluates a subscript in NAME the way `test -v` does; bash also takes the
# bundled `-vNAME`. A first word that is any option other than `--` defers.
# After a format with a non-text conversion, every operand must be a plain
# number, since zsh evaluates such an operand, a literal one too, as
# arithmetic.
guard_printf() {
  local fmt=1 i re='^[-+]?[0-9]+(\.[0-9]+)?$'
  case ${cw[1]-} in
    --) fmt=2 ;;
    -*) return 1 ;;
  esac
  printf_format_inert "${cw[fmt]-}" && return 0
  for ((i = fmt + 1; i < cwn; i++)); do
    word_unresolved "${cw[i]}" "${cdyn[i]}" "${cglob[i]}" "${cx[i]}" && return 1
    [[ ${cw[i]} =~ $re ]] || return 1
  done
  return 0
}

# Command substitution (REQ-E1.3, D-11). A `$(…)` whose inner text passes the
# read-only analysis on its own (subst_inner_ok) still prints text the hook
# never sees, so its output, directly or through a variable assigned from it,
# may reach only a position whose verdict no value can change: then the
# unknown text is equivalent to some literal the guard already approves. That
# set is narrower than arg_independent_verb's: a verb that opens its operands
# could be handed another process's environ path, and the rest are left out
# rather than argued one by one. In the comments of this section, a bare
# "substitution" is a command substitution, never the table of tracked
# variables (VAR_*).

# word_tainted <i>: 0 when word <i> of the current simple command carries
# substitution output, with TAINT_WEAK saying how the guard knows. Known
# (TAINT_WEAK=0): the word holds a `$(…)` or names a variable the table marks
# as assigned from one (VAR_S 1). Inferred (TAINT_WEAK=1): the name may hold
# output the table cannot see. Callers ask only about a command holding a
# substitution, where any name the table does not track may: `$_` is the
# previous command's last argument (and a loop's head reads it again after
# the body's substitution), a zsh pipeline's last `read` sets a name in the
# current shell, and the inner text of a substitution starts with an empty
# table while its subshell inherits every outer variable (VAR_S 2 marks a
# variable assigned from such a word). A word mixing both is inferred: its
# known part says nothing about the rest. Every `$` spelling is read, a
# literal one too, which can only narrow a verdict.
word_tainted() {
  local w=${cw[$1]} name v found weak=0 known=0
  TAINT_WEAK=0
  [ -z "${csub[$1]-}" ] || known=1
  # Each `$` below copies the rest of the word, so a word holding more than
  # a handful is taken as inferred rather than read name by name.
  dollar_count "$w"
  if [ "$DOLLAR_N" -gt 64 ]; then
    TAINT_WEAK=1
    return 0
  fi
  while :; do
    case $w in
      *'$'*) w=${w#*'$'} ;;
      *) break ;;
    esac
    w=${w#'{'}
    case $w in [=^+#]*) w=${w#?} ;; esac
    name=${w%%[!A-Za-z0-9_]*}
    [ -n "$name" ] || continue
    if [ "$IN_SUBST" = 1 ]; then
      weak=1
      break
    fi
    found=0
    for ((v = VAR_C - 1; v >= 0; v--)); do
      if [ "${VAR_N[v]}" = "$name" ]; then
        found=1
        # A loop variable's slot never carries a VAR_S of its own.
        if [ "${VAR_L[v]}" = 0 ]; then
          case ${VAR_S[v]-0} in
            1) known=1 ;;
            2) weak=1 ;;
          esac
        fi
        break
      fi
    done
    [ "$found" = 1 ] || weak=1
  done
  if [ "$weak" = 1 ]; then
    TAINT_WEAK=1
    return 0
  fi
  [ "$known" = 1 ]
}

# subst_reach_ok <i>: whether word <i>, which carries substitution output,
# sits in an argument-independent position: an operand of echo, an operand
# of printf after its format, an operand after a script path (whether the
# script is trusted is the verb rules' call), or a test operand. 0 admits the
# word; 2 leaves it to test_opaque_ok as an opaque word, since test reads
# its operands as operators by position and `-v` runs a subscript; 1 defers.
subst_reach_ok() {
  local i=$1 fmt=1
  [ "$i" -gt 0 ] || return 1
  case ${cw[0]} in
    echo) return 0 ;;
    printf)
      [ "${cw[1]-}" = -- ] && fmt=2
      [ "$i" -gt "$fmt" ] && return 0
      ;;
    test | '[') return 2 ;;
    bash | sh) [ "$i" -ge 2 ] && return 0 ;;
    */*) return 0 ;;
  esac
  return 1
}

# subst_inner_ok <text>: the inner text of a `$(…)` is one simple command or
# pipeline that passes the read-only analysis alone, in a subshell: no
# assignment or `cd` is modelled there, and neither trusted repo code, a
# declared step, nor a spec-root write counts as read-only.
subst_inner_ok() {
  local saved=$IN_SUBST rc
  IN_SUBST=1
  analyze_command "$1" "$HOOK_DEPTH" pipeline
  rc=$?
  IN_SUBST=$saved
  return "$rc"
}

# subst_words_ok: the current simple command's words carrying substitution
# output each sit where subst_reach_ok admits them, and then every other
# unresolved word passes opaque_words_ok, which sees each admitted word known
# to carry output as a plain literal. A word only inferred to carry it is
# left as it is, so it must pass both checks and a name that may be an
# ordinary opaque value gains no position it lacked. The neutral copy is
# local, so the screens after this one still read the words as written.
subst_words_ok() {
  local i rc
  # Without a substitution in this command, or around it, nothing is tainted.
  if [ "$SUBST_N" -eq 0 ] && [ "$IN_SUBST" = 0 ]; then
    opaque_words_ok
    return
  fi
  local -a cw=(${cw[@]+"${cw[@]}"}) cdyn=(${cdyn[@]+"${cdyn[@]}"}) cglob=(${cglob[@]+"${cglob[@]}"})
  local -a cx=(${cx[@]+"${cx[@]}"}) cz=(${cz[@]+"${cz[@]}"})
  for ((i = 0; i < cwn; i++)); do
    word_tainted "$i" || continue
    subst_reach_ok "$i"
    rc=$?
    [ "$rc" = 0 ] && [ "$TAINT_WEAK" = 1 ] && rc=2
    case $rc in
      0)
        cw[i]=x
        cdyn[i]=0
        cglob[i]=0
        cx[i]=0
        cz[i]=0
        ;;
      2) ;;
      *) return 1 ;;
    esac
  done
  opaque_words_ok
}

# opaque_words_ok: the current simple command (`cw` and its flag arrays, by
# dynamic scope) places every unresolved word where its value cannot change
# the verdict: never the verb, and otherwise only an operand of an
# argument-independent verb (one that opens its operands only when
# opener_word_risky clears the word), printf past its format, or a test
# shape test_opaque_ok admits.
opaque_words_ok() {
  local i verb=${cw[0]} fmt=1 g
  word_unresolved "$verb" "${cdyn[0]}" "${cglob[0]}" "${cx[0]}" && return 1
  case $verb in
    test | '[')
      test_opaque_ok
      return
      ;;
  esac
  [ "${cw[1]-}" = -- ] && fmt=2
  for ((i = 1; i < cwn; i++)); do
    word_unresolved "${cw[i]}" "${cdyn[i]}" "${cglob[i]}" "${cx[i]}" || continue
    [ "$verb" = printf ] && [ "$i" -gt "$fmt" ] && continue
    arg_independent_verb "$verb" || return 1
    if opens_operands "$verb" && [ "${cdyn[i]}" != 0 ]; then
      g=${cglob[i]}
      [ "${cz[i]-0}" = 0 ] || g=1
      opener_word_risky "${cw[i]}" "${cx[i]}" "$g" && return 1
    fi
  done
  return 0
}

# test_opaque_ok: `test`/`[` read their operands as operators by position,
# and a `-v` operand runs a subscript, so an opaque word is admitted only
# where bash cannot read it as an operator: it must expand inside double
# quotes alone (one word, never split or globbed), and the expression must
# be one operand, a literal unary operator and its operand, or two operands
# around a literal binary operator. guard_test still refuses a literal `-v`.
test_opaque_ok() {
  local i n=$cwn opaque=0
  [ "${cw[0]}" = '[' ] && [ "${cw[cwn - 1]}" = ']' ] && n=$((cwn - 1))
  for ((i = 1; i < cwn; i++)); do
    word_unresolved "${cw[i]}" "${cdyn[i]}" "${cglob[i]}" "${cx[i]}" || continue
    [ "$i" -lt "$n" ] && [ "${cdyn[i]}" = 1 ] && [ "${cglob[i]}" = 0 ] || return 1
    opaque=1
  done
  [ "$opaque" = 1 ] || return 0
  case $((n - 1)) in
    1) return 0 ;;
    2)
      word_unresolved "${cw[1]}" "${cdyn[1]}" "${cglob[1]}" "${cx[1]}" && return 1
      return 0
      ;;
    3)
      word_unresolved "${cw[2]}" "${cdyn[2]}" "${cglob[2]}" "${cx[2]}" && return 1
      case ${cw[2]} in
        = | == | != | '<' | '>' | -eq | -ne | -lt | -le | -gt | -ge | -nt | -ot | -ef | -a | -o) return 0 ;;
      esac
      return 1
      ;;
  esac
  return 1
}

# loop_header <idx>: model the `for NAME in WORD…; do` header whose `for` sits
# at TOK index <idx>. Succeeds only when NAME passes assign_name_ok and is not
# already in the substitution table (its old value would come back after the
# loop), and every head word is a plain literal (no
# expansion, glob, or character outside the guard's path charset, so it reads
# the same quoted or not and splits into nothing), at most MAX_LOOP_WORDS of
# them. Appends the words to LW and sets LH_NAME, LH_START, LH_COUNT, and
# LH_NEXT (the first body token). Any other header shape defers the command.
loop_header() {
  local j=$(($1 + 1)) w cnt=0 v
  [ "$j" -lt "$TOK_N" ] && [ "${TOK_TYPE[j]}" = W ] && [ "${TOK_QUOTED[j]}" = 0 ] || return 1
  LH_NAME=${TOK_VAL[j]}
  assign_name_ok "$LH_NAME" || return 1
  for ((v = 0; v < VAR_C; v++)); do
    [ "${VAR_N[v]}" = "$LH_NAME" ] && return 1
  done
  j=$((j + 1))
  [ "$j" -lt "$TOK_N" ] && [ "${TOK_TYPE[j]}" = W ] && [ "${TOK_VAL[j]}" = in ] && [ "${TOK_QUOTED[j]}" = 0 ] || return 1
  j=$((j + 1))
  LH_START=$LW_N
  while [ "$j" -lt "$TOK_N" ] && [ "${TOK_TYPE[j]}" = W ]; do
    w=${TOK_VAL[j]}
    [ "${TOK_DYN[j]}" = 0 ] && [ "${TOK_GLOB[j]}" = 0 ] || return 1
    case $w in
      '' | *[!A-Za-z0-9._/:=@%,+-]*) return 1 ;;
    esac
    cnt=$((cnt + 1))
    [ "$cnt" -le "$MAX_LOOP_WORDS" ] || return 1
    LW[LW_N]=$w
    LW_N=$((LW_N + 1))
    j=$((j + 1))
  done
  [ "$cnt" -ge 1 ] || return 1
  [ "$j" -lt "$TOK_N" ] && [ "${TOK_TYPE[j]}" = O ] && [ "${TOK_VAL[j]}" = ';' ] || return 1
  j=$((j + 1))
  [ "$j" -lt "$TOK_N" ] && [ "${TOK_TYPE[j]}" = W ] && [ "${TOK_VAL[j]}" = 'do' ] && [ "${TOK_QUOTED[j]}" = 0 ] || return 1
  LH_NEXT=$((j + 1))
  LH_COUNT=$cnt
  return 0
}

# loop_fits — whether every pass of the loop loop_enter just opened can fit
# the scan budget, charged up front from the body's text: one pass's words,
# each `$` at DOLLAR_COST as verify_simple charges them, times the head words.
# A loop that cannot fit then defers at its `for` instead of after its first
# passes have been walked. The body runs to its matching `done`, counting the
# do/done pairs nested inside it; a `done` that is only an argument ends it
# early, which can only under-charge, and the per-pass charge still holds.
loop_fits() {
  local j=$LH_NEXT nest=1 cost=0
  while [ "$j" -lt "$TOK_N" ]; do
    if [ "${TOK_TYPE[j]}" = W ] && [ "${TOK_QUOTED[j]}" = 0 ]; then
      case ${TOK_VAL[j]} in
        do) nest=$((nest + 1)) ;;
        done)
          nest=$((nest - 1))
          [ "$nest" -gt 0 ] || break
          ;;
      esac
    fi
    dollar_count "${TOK_VAL[j]}"
    cost=$((cost + ${#TOK_VAL[j]} + DOLLAR_N * DOLLAR_COST))
    j=$((j + 1))
  done
  [ $((SCANNED + cost * LH_COUNT)) -le "$MAX_SCANNED" ]
}

# loop_enter / loop_next: the `for` modelling inside verify_tokens, reading and
# writing its walk state (idx, ctl_depth, case_depth, the LF_* frames) by
# dynamic scope. loop_enter opens a loop at the `for` token: its variable takes
# the first head word and the walk moves to the body. loop_next runs at a
# `done`, after the depth drop: 0 sends the walk back to the body with the
# next head word, 1 lets it go on past the `done` (the loop is closed, its
# variable dropped from the table, so a later use is opaque), 2 defers.
loop_enter() {
  loop_header "$idx" || return 1
  LOOP_PASSES=$((LOOP_PASSES + 1))
  [ "$LOOP_PASSES" -le "$MAX_LOOP_PASSES" ] || return 1
  ctl_depth=$((ctl_depth + 1))
  LF_VAR[lf_n]=$VAR_C
  LF_START[lf_n]=$LH_START
  LF_COUNT[lf_n]=$LH_COUNT
  LF_POS[lf_n]=0
  LF_BODY[lf_n]=$LH_NEXT
  LF_DEPTH[lf_n]=$ctl_depth
  LF_CASE[lf_n]=$case_depth
  lf_n=$((lf_n + 1))
  VAR_N[VAR_C]=$LH_NAME
  VAR_V[VAR_C]=${LW[LH_START]}
  VAR_L[VAR_C]=1
  VAR_O[VAR_C]=0
  VAR_C=$((VAR_C + 1))
  idx=$LH_NEXT
  return 0
}

loop_next() {
  local t p
  [ "$lf_n" -gt 0 ] && [ "$ctl_depth" -eq $((LF_DEPTH[lf_n - 1] - 1)) ] || return 1
  t=$((lf_n - 1))
  [ "$case_depth" -eq "${LF_CASE[t]}" ] || return 2
  p=$((LF_POS[t] + 1))
  if [ "$p" -lt "${LF_COUNT[t]}" ]; then
    LOOP_PASSES=$((LOOP_PASSES + 1))
    [ "$LOOP_PASSES" -le "$MAX_LOOP_PASSES" ] || return 2
    LF_POS[t]=$p
    VAR_V[LF_VAR[t]]=${LW[LF_START[t] + p]}
    ctl_depth=$((ctl_depth + 1))
    idx=${LF_BODY[t]}
    return 0
  fi
  VAR_C=${LF_VAR[t]}
  LW_N=${LF_START[t]}
  lf_n=$t
  return 1
}

classify_verb() {
  local verb=$1
  case $verb in
    # Read-only, no write/exec/output vector: any flags are safe.
    cat | head | tail | wc | cut | comm | cmp | basename | dirname | realpath | pwd | echo | seq | true | false | od | tr | stat | grep | ls | diff)
      return 0
      ;;
    test | '[') guard_test ;;
    printf) guard_printf ;;
    # Same class, added 2026-09-14 from the shapes real dispatched workers
    # stalled on. Each was checked for a write/exec vector across its whole
    # flag surface and has none: `readlink`/`nl`/`paste`/`column` and the
    # checksum family report to stdout with no output-file or filter flag.
    # `printenv` is guarded below: bare, it prints every variable. `jq` is
    # NOT here: it passes the same write/exec test — its language has no exec
    # and no file-write primitive, and `-f`, `--rawfile`, `--slurpfile` and
    # `-L` only ever READ — but it carries PROGRAM TEXT, and a jq program can
    # read the environment (`env`, `$ENV`). Leaving it unscreened allowed
    # `jq -n env` while `awk 'BEGIN{print ENVIRON["X"]}'` deferred, which is
    # the same read through a different tool. It is guarded below.
    readlink | nl | paste | column | md5sum | sha1sum | sha256sum | sha512sum | cksum)
      return 0
      ;;
    # Read-only analyzers (results to stdout only).
    shellcheck | yamllint) return 0 ;;
    # Waits and process / lookup inspection (REQ-E1.5).
    sleep) guard_sleep ;;
    ps) guard_ps ;;
    uptime) guard_uptime ;;
    which) guard_which ;;
    command) guard_command ;;
    # Read-only tools with a specific write/set/output vector: guarded.
    sort) guard_sort ;;
    uniq) guard_uniq ;;
    date) guard_date ;;
    file) guard_file ;;
    ss) guard_ss ;;
    umask) guard_umask ;;
    find) guard_find ;;
    sed) guard_sed || guard_sed_inplace ;;
    perl) guard_perl_inplace ;;
    awk) guard_awk ;;
    jq) guard_jq ;;
    markdownlint | markdownlint-cli2) guard_mdlint "$verb" ;;
    env) guard_env ;;
    printenv) guard_printenv ;;
    read) [ -z "${FISH_INNER-}" ] && guard_read ;;
    yq) guard_yq ;;
    shfmt) guard_shfmt ;;
    rg) guard_rg ;;
    fd) guard_fd ;;
    # Enumerated read-only subcommand tools.
    git) guard_git ;;
    gh) guard_gh ;;
    gitleaks) guard_gitleaks ;;
    mise) guard_mise ;;
    lefthook) guard_lefthook ;;
    # Writers, approved inside the spec-root write zone or under a policy
    # arm.
    tee) guard_tee ;;
    mkdir) guard_mkdir ;;
    rm) guard_rm ;;
    touch) guard_touch ;;
    cp) guard_cp ;;
    mv) guard_mv ;;
    mktemp) guard_mktemp ;;
    # Trusted repo-code runners (path-contained) and the fish recursor.
    bash | sh) guard_bashsh ;;
    fish) guard_fish ;;
    bats) guard_bats ;;
    *) return 1 ;; # fallthrough is DEFER, by construction (REQ-B1.6)
  esac
}

# --------------------------------------------------------------------------
# Declared check commands (worker_check_commands). A segment no rule above
# approved is still approved when its words match a check command the
# repository declares, so its own test and check runners need no mise task.
# A declaration is a word sequence: literal words, matched exactly (a flag is
# admitted only where it is spelled out), and the placeholders `<word>` (a
# token with no `/`), `<int>` and `<path>` (worktree-relative, resolved from
# the working directory, inside the worktree and outside every path the
# own-branch arm excludes, so naming no hooks, git or tool configuration
# path), the last of them optionally suffixed `...` to match one or more
# words. No placeholder matches a leading dash, a shell metacharacter or an
# expansion, and the working directory is held to the `<path>` rules. A runner prefix (`mise exec --`) is literal words like any other,
# so it admits its own sequence and never the runner in general. A
# declaration holding anything else is malformed and dropped alone. The
# declarations come from the session record, read by the launcher at the
# primary checkout, never from a file the worker can write; the floor is read
# before them (verify_simple). Running one runs repository code: a script its
# literal words name is held to HEAD as the repository's scripts/ are
# (check_literals_committed), and whatever a `<path>` names runs as declared.
# That trust stops at a config loader: a declared markdownlint or mise run
# still passes the screen the undeclared command does (check_loader_ok).

readonly MAX_CHECK_WORDS=32
readonly MAX_CHECK_ARG=512
# The `<path>` words one hook call may check: each walks and canonicalizes a
# path, a cost the command-length bounds do not cap.
readonly MAX_CHECK_PATHS=64
CHECK_PATHS_N=0
# The well-formed declarations, parsed once per hook call (check_decls_load),
# with their first words; the working directory last checked, and its verdict.
CHECK_STATE=0
CHECK_DECLS=()
CHECK_FIRST=()
CHECK_CWD_FOR=''
CHECK_CWD=''
HAZARD_NAME=''

# check_word_ok <word>: the `<word>` placeholder. A leading `=` is refused
# because zsh expands `=name` to a command's absolute path.
check_word_ok() {
  case $1 in
    '' | -* | =* | *[!A-Za-z0-9._:@%,+=-]* | . | ..) return 1 ;;
  esac
  [ "${#1}" -le "$MAX_CHECK_ARG" ]
}

# check_int_ok <word>: the `<int>` placeholder.
check_int_ok() {
  case $1 in
    '' | *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 18 ]
}

# check_dir_open <canonical-path>: 0 when the path is the worktree root or
# lies inside it, outside every path the own-branch arm excludes.
check_dir_open() {
  local c=$1 d
  [ "$c" = "$REC_WT" ] && return 0
  case $c/ in
    "$REC_WT"/*) ;;
    *) return 1 ;;
  esac
  ob_excl_load || return 1
  lower "$c"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    case $LOWER/ in
      "$d"/*) return 1 ;;
    esac
  done <<EOF
$OB_EXCL_DIRS
EOF
  ! ob_excluded_rel "${c#"$REC_WT"/}" "$REC_WT" ''
}

# check_path_in <relative-path> <canonical-cwd>: 0 when no existing component
# of the path is a symlink and it resolves inside the worktree, outside every
# excluded path.
check_path_in() {
  local rest=$1 acc=$2 comp c
  case /$rest/ in
    */../*) return 1 ;;
  esac
  while [ -n "$rest" ]; do
    comp=${rest%%/*}
    case $rest in
      */*) rest=${rest#*/} ;;
      *) rest='' ;;
    esac
    case $comp in
      '' | .) continue ;;
    esac
    acc=$acc/$comp
    [ ! -L "$acc" ] || return 1
    [ -e "$acc" ] || break
  done
  c=$(canon_loose "$2/${1%/}") || return 1
  check_dir_open "$c"
}

# check_path_ok <word> <canonical-cwd>: the `<path>` placeholder. A runner may
# read `<file>:<line>`, so the part before the first `:` is held to the same
# rules as the whole word.
check_path_ok() {
  local p=$1
  case $p in
    '' | -* | /* | *[!A-Za-z0-9._/:+-]*) return 1 ;;
  esac
  [ "${#p}" -le "$MAX_CHECK_ARG" ] || return 1
  CHECK_PATHS_N=$((CHECK_PATHS_N + 1))
  [ "$CHECK_PATHS_N" -le "$MAX_CHECK_PATHS" ] || return 1
  [ -n "${p%%:*}" ] || return 1
  case $p in
    *:*/*) return 1 ;;
  esac
  check_path_in "$p" "$2" || return 1
  [ "${p%%:*}" = "$p" ] || check_path_in "${p%%:*}" "$2"
}

# check_decl_ok <word>...: 0 when the words form a well-formed declaration.
check_decl_ok() {
  local n=$# j=0 d
  [ "$n" -ge 1 ] && [ "$n" -le "$MAX_CHECK_WORDS" ] || return 1
  for d in "$@"; do
    case $d in
      '<word>' | '<int>' | '<path>')
        [ "$j" -gt 0 ] || return 1
        ;;
      '<word>...' | '<int>...' | '<path>...')
        [ "$j" -gt 0 ] && [ "$j" -eq $((n - 1)) ] || return 1
        ;;
      *[!A-Za-z0-9._/:=@%,+-]*) return 1 ;;
      *=*) [ "$j" -gt 0 ] || return 1 ;;
    esac
    j=$((j + 1))
  done
}

# check_decls_load: parse REC_CHECKS into CHECK_DECLS and CHECK_FIRST, once per
# hook call, dropping each malformed declaration alone, so a malformed one
# never matches on a prefix.
check_decls_load() {
  local decl w key
  local -a all=() dw=()
  CHECK_STATE=1
  IFS=';' read -r -a all <<<"$REC_CHECKS"
  for decl in ${all[@]+"${all[@]}"}; do
    dw=()
    IFS=' ' read -r -a dw <<<"$decl"
    [ "${#dw[@]}" -ge 1 ] || continue
    check_decl_ok "${dw[@]}" || continue
    key=''
    for w in "${dw[@]}"; do
      key="${key:+$key }$w"
    done
    CHECK_DECLS[${#CHECK_DECLS[@]}]=$key
    CHECK_FIRST[${#CHECK_FIRST[@]}]=${dw[0]}
  done
}

# check_decl_match <declaration> <canonical-cwd>: 0 when the current simple
# command's words (`sw` / `swn`, via dynamic scope) match the well-formed
# declaration.
check_decl_match() {
  local -a dw=()
  local n j i=0 d ph last
  IFS=' ' read -r -a dw <<<"$1"
  n=${#dw[@]}
  for ((j = 0; j < n; j++)); do
    d=${dw[j]}
    case $d in
      '<'*)
        ph=${d%...}
        last=$i
        [ "$d" = "$ph" ] || last=$((swn - 1))
        [ "$i" -le "$last" ] || return 1
        while [ "$i" -le "$last" ]; do
          [ "$i" -lt "$swn" ] || return 1
          case $ph in
            '<word>') check_word_ok "${sw[i]}" || return 1 ;;
            '<int>') check_int_ok "${sw[i]}" || return 1 ;;
            '<path>') check_path_ok "${sw[i]}" "$2" || return 1 ;;
          esac
          i=$((i + 1))
        done
        ;;
      *)
        [ "$i" -lt "$swn" ] && [ "${sw[i]}" = "$d" ] || return 1
        i=$((i + 1))
        ;;
    esac
  done
  [ "$i" -eq "$swn" ]
}

# check_command_ok: 0 when the current simple command (`sw` / `swn`, the
# redirect arrays `ro` / `rt` / `rn`, via dynamic scope) matches a declared
# check command, run from inside the recorded worktree with no redirect but
# a read, an fd duplication or one to /dev/null.
check_command_ok() {
  local i k c
  [ -n "$REC_CHECKS" ] && [ -n "$REC_WT" ] && [ "$swn" -gt 0 ] || return 1
  [ "$swn" -le $((MAX_CHECK_WORDS + MAX_CHECK_PATHS)) ] || return 1
  for ((i = 0; i < rn; i++)); do
    case ${rt[i]} in
      *'$'*) return 1 ;;
    esac
    classify_redirect "${ro[i]}" "${rt[i]}" || return 1
  done
  # The working directory is held to the `<path>` rules: a declared command
  # never runs from inside a hooks, git or tool-configuration directory.
  if [ "$CHECK_CWD_FOR" != "$HOOK_CWD" ]; then
    CHECK_CWD_FOR=$HOOK_CWD
    CHECK_CWD=''
    if c=$(cd "$HOOK_CWD" 2>/dev/null && pwd -P) && check_dir_open "$c"; then
      CHECK_CWD=$c
    fi
  fi
  [ -n "$CHECK_CWD" ] || return 1
  [ "$CHECK_STATE" = 1 ] || check_decls_load
  for ((k = 0; k < ${#CHECK_DECLS[@]}; k++)); do
    [ "${CHECK_FIRST[k]}" = "${sw[0]}" ] || continue
    check_decl_match "${CHECK_DECLS[k]}" "$CHECK_CWD" || continue
    check_literals_committed "${CHECK_DECLS[k]}" "$CHECK_CWD" || continue
    # The loader verdict reads only the words, so no other declaration
    # could turn it.
    check_loader_ok
    return
  done
  return 1
}

# check_literals_committed <declaration> <canonical-cwd>: every literal word
# of the declaration that names an existing file, from the working directory
# or by its absolute path, is held to what HEAD commits, as a declared step's
# location is (declared_location_ok): the declaration names the file, not its
# content, and the worker can Write it. A bare first word is looked up on PATH,
# never in the working directory, and a `<path>` placeholder is the declarer's
# choice of what the runner is given; both stay as declared.
check_literals_committed() {
  local -a dw=()
  local w full j=0
  IFS=' ' read -r -a dw <<<"$1"
  for w in "${dw[@]}"; do
    j=$((j + 1))
    case $w in
      '<'*) continue ;;
      /*) full=$w ;;
      */*) full=$2/$w ;;
      *)
        [ "$j" -gt 1 ] || continue
        full=$2/$w
        ;;
    esac
    [ -e "$full" ] || [ -L "$full" ] || continue
    [ -d "$full" ] && [ ! -L "$full" ] && continue
    declared_location_ok "$full" || return 1
  done
  return 0
}

# check_may_partner: 0 when the matched check command (`sw` / `swn`) may be a
# chain partner of an own-unit act: no word is one check_hazard_word refuses,
# and no `run` follows a `go`. Every word is read, a placeholder's included,
# so a runner prefix or a wrapper cannot carry one past the check; only a
# leading `mise exec` is skipped. A repository task runner (`mix`, `npm`,
# `make`) names none and partners.
check_may_partner() {
  local i=0 go=0
  [ "${sw[0]}" != mise ] || [ "${sw[1]-}" != exec ] || i=2
  for (( ; i < swn; i++)); do
    ! check_hazard_word "${sw[i]}" || return 1
    case $HAZARD_NAME in
      go) go=1 ;;
      run) [ "$go" = 0 ] || return 1 ;;
    esac
  done
  return 0
}

# check_hazard_word <word>: 0 when the word names a program check_hazard_name
# lists, read lowercased (a case-insensitive filesystem runs `GIT` as git), by
# its last path component, whole or after its last `=` (`--cmd=rm`,
# `SHELL=bash`). The whole word's lowercased last component is left in
# HAZARD_NAME.
check_hazard_word() {
  local w=$1
  case $w in
    *[A-Z]*)
      lower "$w"
      w=$LOWER
      ;;
  esac
  HAZARD_NAME=${w##*/}
  check_hazard_name "$HAZARD_NAME" && return 0
  case $w in
    *=*)
      w=${w##*=}
      check_hazard_name "${w##*/}"
      return
      ;;
  esac
  return 1
}

# check_hazard_name <lowercase name>: 0 for a program that writes files, acts
# on git, runs another program, or interprets code, its GNU `g`-prefixed name
# (`gsed`, `gtouch`) included. Subcommand words that fetch and run a package
# (`npm exec`, `pnpm dlx`, `npm x`) are listed too. The list fails open for a
# program it does not name.
check_hazard_name() {
  case $1 in
    # git and gh, and the programs the guard approves only as a write or
    # screens for a write or exec vector.
    git | gh | mise | tee | mkdir | rm | touch | cp | mv | mktemp | sed | awk | find | sort | uniq | date | file | yq | shfmt | rg | fd | jq | gitleaks | markdownlint | markdownlint-cli2 | lefthook | bats) return 0 ;;
    # Other writers, archivers and editors.
    mawk | nawk | ln | link | chmod | chown | chgrp | dd | install | truncate | shred | unlink | rmdir | rename | mkfifo | mknod | xxd | ditto | rsync | scp | sftp | curl | wget | tar | bsdtar | unzip | zip | gzip | bzip2 | xz | zstd | lz4 | 7z | 7za | cpio | sponge | split | patch | ed | ex | vi | vim | nvim | nano | emacs | sqlite3 | psql | crontab) return 0 ;;
    # Shells and programs that run another program.
    bash | sh | fish | zsh | dash | ksh | ash | csh | tcsh | mksh | rbash | env | command | builtin | exec | x | eval | xargs | sudo | doas | su | ssh | nc | socat | docker | podman | tmux | screen | script | at | systemd-run | chroot | unshare | nsenter | xvfb-run | nohup | setsid | timeout | nice | ionice | time | stdbuf | flock | watch | parallel | strace | busybox) return 0 ;;
    # Interpreters, compilers and fetch-and-run launchers.
    perl | perl[0-9]* | python | python[0-9]* | node | nodejs | ruby | ruby[0-9]* | irb | php | php[0-9]* | deno | bun | bunx | npx | pnpx | uvx | pipx | dlx | osascript | lua | lua[0-9]* | luajit | r | rscript | tclsh | pwsh | powershell | elixir | iex | erl | escript | java | javac | jshell | julia | groovy | cc | gcc | clang | rustc) return 0 ;;
  esac
  case $1 in
    g?*) check_hazard_name "${1#g}" ;;
    *) return 1 ;;
  esac
}

# check_loader_ok: 0 unless the current simple command (`sw` / `swn`) runs a
# loader the guard screens by its words, as its first word or the word after a
# runner prefix's `--`, and that loader's own screen defers it. A declaration
# vouches for the words it spells, never for the config the loader reads from
# folders a worker can Write, so a declared loader is approved only where the
# undeclared command would be: markdownlint by guard_mdlint, and mise before an
# option, `run`, `tasks` or their aliases by guard_mise, which knows no alias
# and so defers one. Any other markdownlint name (the `-fix` and `-config`
# binaries older releases ship) defers, as the undeclared one does. The
# subcommand list must stay a superset of what guard_mise screens, or a new
# spelling passes on the declaration alone. The name is matched
# case-insensitively, since a case-insensitive filesystem runs a recased one.
check_loader_ok() {
  local k
  for ((k = 0; k < swn; k++)); do
    [ "$k" -eq 0 ] || [ "${sw[k - 1]}" = -- ] || continue
    lower "${sw[k]##*/}"
    case $LOWER in
      markdownlint | markdownlint-cli2) check_loader_screen "$k" guard_mdlint "$LOWER" || return 1 ;;
      markdownlint*) return 1 ;;
      mise)
        case ${sw[k + 1]-} in
          -* | run | r | tasks | task | t) check_loader_screen "$k" guard_mise || return 1 ;;
        esac
        ;;
    esac
  done
  return 0
}

# check_loader_screen <from> <screen> [<arg>]: run <screen> on the words from
# index <from> on, as `cw` / `cwn`. The parallel per-word arrays are not
# sliced, so a screen run here must read only those two.
check_loader_screen() {
  local from=$1
  shift
  local -a cw=("${sw[@]:from}")
  local cwn=${#cw[@]}
  "$@"
}

# --------------------------------------------------------------------------
# Declared command steps (custom-steps REQ-G1.2, REQ-G1.3). A segment no rule
# above approved is still approved when its words equal a command step an
# operator declared at a named point: the step's location exactly as
# scripts/resolve-steps.sh prints it on this host, then its args as written,
# after any leading context assignments in the runner's form. The declaration
# carries the trust (its overlay layer is human-owned, and the repo-tracked
# and machine-local layers inherit the trust already given to the repo's
# scripts/, which holds a location inside the repository to what HEAD commits
# there: declared_location_ok), so the match is exact: a segment sharing only the first word, a
# bare target, or an extra arg defers. The declarations are resolved at most
# once per hook call, by one resolver run over every wired point, only when a
# segment reaches this fallback with a declared line's shape and the file name
# of its location word (the first after any context assignments) is the last
# path component of a target some layer's steps catalog declares, and under
# STEPS_DEADLINE. A run that fails before printing (a shared read or a usage
# failure) or overruns contributes nothing; a point failing alone drops only
# its own rows.

# The wired points of resolve-steps.sh's WIRED_POINTS; the lists change
# together. The unwired points run nothing, so they declare nothing. Every
# name must be a distinct wired point: they go to one multi-point run, which
# refuses the whole run otherwise.
readonly STEP_POINTS='pre-implementation pre-ci convergence pre-pr post-pr pre-ready-flip pre-spec-ready-flip'
# Seconds the catalog check and the resolution may take together in one hook
# call. The PLANWRIGHT_GUARD_STEPS_DEADLINE override (1..60) changes only how
# long they may run: it never widens the set of lines a segment can match,
# though a resolution that finishes in time can approve where a shorter
# deadline would have deferred.
readonly STEPS_DEADLINE=2
DECL_RESOLVED=0
DECL_LINES=''
DECL_TMP=''
# The process group of a running resolution job, killed on any exit.
DECL_PGID=''

# The context names in the order resolve-steps.sh's CONTEXT_FIELDS renders
# them in --prefix; the lists change together.
readonly STEP_CONTEXT_FIELDS='SPEC TASK_IDS UNIT_KIND BRANCH BASE_BRANCH WORKTREE PR_NUMBER POINT ID PREV_RECORD PREV_HEAD NEW_HEAD'

# step_context_value_ok <field> <value>: a value the resolver would render,
# refusing what it refuses (a control byte; a unit kind, task ids, PR number,
# or head outside their grammar; a point outside the wired ones) plus any `$`.
step_context_value_ok() {
  local f=$1 v=$2 id
  case $v in
    *[[:cntrl:]]* | *'$'*) return 1 ;;
  esac
  case $f in
    UNIT_KIND)
      case $v in
        '' | task | spec | flight) ;;
        *) return 1 ;;
      esac
      ;;
    TASK_IDS)
      # The charset first: the unquoted split below would glob-expand a `*`.
      case $v in
        *[!0-9.\ ]* | ' '* | *' ' | *'  '*) return 1 ;;
      esac
      for id in $v; do
        case $id in
          *[!0-9.]* | . | *.*.* | .* | *.) return 1 ;;
        esac
      done
      ;;
    PR_NUMBER)
      case $v in
        *[!0-9]*) return 1 ;;
      esac
      ;;
    WORKTREE)
      # Under a record, the step context names the session's own worktree
      # alone, however it is spelled.
      if [ -n "$REC_WT" ]; then
        case $v in
          /*) ;;
          *) return 1 ;;
        esac
        case $v/ in
          */./* | */../*) return 1 ;;
        esac
        [ "$(cd "$v" 2>/dev/null && pwd -P)" = "$REC_WT" ] || return 1
      fi
      ;;
    PREV_HEAD | NEW_HEAD)
      case $v in
        *[!0-9a-f]*) return 1 ;;
      esac
      case ${#v} in
        0 | 40 | 64) ;;
        *) return 1 ;;
      esac
      ;;
    POINT)
      case $v in
        *' '*) return 1 ;;
      esac
      case " $STEP_POINTS " in
        *" $v "*) ;;
        *) return 1 ;;
      esac
      ;;
  esac
  return 0
}

# step_pool_hold_ok <value>: the resolver's hold mark, `<pool>:<pid>`, the pool
# in the step-id charset (at most 64 bytes) and the pid decimal with no
# leading zero (at most ten digits), as scripts/step-pool.sh reads it.
step_pool_hold_ok() {
  local pool=${1%%:*} pid=${1#*:}
  case $1 in
    *:*) ;;
    *) return 1 ;;
  esac
  case $pool in
    '' | [!a-z]* | *[!a-z0-9-]*) return 1 ;;
  esac
  case $pid in
    '' | [!1-9]* | *[!0-9]*) return 1 ;;
  esac
  [ "${#pool}" -le 64 ] && [ "${#pid}" -le 10 ]
}

# step_arg_ok <word>: the resolver's args charset.
step_arg_ok() {
  case $1 in
    '' | *[!A-Za-z0-9._/:=@%,+-]*) return 1 ;;
  esac
  return 0
}

# step_location_ok <location> <target>: the location is absolute and in the
# guard's path charset; for a path target (one naming a directory) it also
# carries no `.`, `..`, or empty segment and canonicalizes to an executable
# file. A bare target's location is whatever the host's PATH lookup found.
step_location_ok() {
  local loc=$1 target=$2 d
  bare_abs_path_ok "$loc" || return 1
  case $target in
    */*)
      case $loc in
        */./* | */../* | */. | */.. | *//*) return 1 ;;
      esac
      d=$(cd "$(dirname "$loc")" 2>/dev/null && pwd -P) || return 1
      [ -f "$d/$(basename "$loc")" ] && [ -x "$d/$(basename "$loc")" ] || return 1
      ;;
  esac
  return 0
}

# step_name_cataloged <name>: 0 when some layer's steps catalog file declares a
# target whose last path component is <name>, each layer root found through
# resolve-overlay-root.sh at the per-layer locations resolve-catalog.sh reads
# (the locations change together). A declared step's location always ends in
# its target's file name, so a miss means nothing can match; a hit only
# admits the resolution.
step_name_cataloged() {
  local ors=$HOOK_SELF_ROOT/scripts/resolve-overlay-root.sh l r f re
  local -a files=()
  [ -x "$ors" ] || return 1
  for l in core adopter repo-tracked; do
    "$ors" "$l" </dev/null >"$DECL_TMP/root-$l" 2>/dev/null &
  done
  wait
  r=''
  IFS= read -r r <"$DECL_TMP/root-core"
  [ -z "$r" ] || files[${#files[@]}]=$r/config/steps.yaml
  r=''
  IFS= read -r r <"$DECL_TMP/root-adopter"
  [ -z "$r" ] || files[${#files[@]}]=$r/catalogs/steps.yaml
  r=''
  IFS= read -r r <"$DECL_TMP/root-repo-tracked"
  # The machine-local catalog sits under the repo-tracked root, which
  # resolve-overlay-root.sh gives both repo-side layers.
  if [ -n "$r" ]; then
    files[${#files[@]}]=$r/catalogs/steps.yaml
    files[${#files[@]}]=$r/catalogs.local/steps.yaml
  fi
  # The name is in the location charset, where only `.` is a regex operator.
  re=${1//./\\.}
  for f in ${files[@]+"${files[@]}"}; do
    [ -f "$f" ] && grep -Eq -e "^[[:space:]]*target:[[:space:]]*\"?([^\"]*/)?$re\"?[[:space:]]*\$" -- "$f" 2>/dev/null && return 0
  done
  return 1
}

# resolve_declared <location>: fill DECL_LINES with one `<location> <arg>...`
# line, then a tab and the step's declared pool (`-` for none), per declared
# command step that resolves to `run`, when <location>'s
# file name is cataloged, by one multi-point resolver run from HOOK_CWD. Runs
# once per hook call: a miss defers its segment, which ends the analysis. The
# check and the run share one job in its own process group, bounded by
# STEPS_DEADLINE and killed whole when it overruns or once it ends, so nothing
# it started outlives the call.
resolve_declared() {
  local rs deadline ticks pid killed=0
  local dec target kind args loc pool key w _
  DECL_RESOLVED=1
  [ -n "${HOOK_SELF_ROOT:-}" ] || return 0
  rs="$HOOK_SELF_ROOT/scripts/resolve-steps.sh"
  [ -r "$rs" ] || return 0
  deadline=${PLANWRIGHT_GUARD_STEPS_DEADLINE:-}
  case $deadline in
    '' | *[!0-9]*) deadline=$STEPS_DEADLINE ;;
  esac
  # Arithmetic reads a leading zero as octal, so strip it first.
  deadline=${deadline#"${deadline%%[!0]*}"}
  { [ "$deadline" -ge 1 ] && [ "$deadline" -le 60 ]; } 2>/dev/null || deadline=$STEPS_DEADLINE
  DECL_TMP=$(mktemp -d "$HOOK_TMP_BASE/planwright-guard.XXXXXX" 2>/dev/null) || {
    DECL_TMP=''
    return 0
  }
  # Job control gives the job its own process group; the resolver's scratch
  # files land under DECL_TMP, which the EXIT trap removes.
  set -m
  (
    cd "$HOOK_CWD" 2>/dev/null || exit 0
    # The core layer is this guard's own root, never one the environment
    # names: a flight's launch pins the brief's root there, and letting it
    # choose the catalog the guard trusts would widen what a worker gets.
    PLANWRIGHT_ROOT=$HOOK_SELF_ROOT CLAUDE_PLUGIN_ROOT=$HOOK_SELF_ROOT \
      step_name_cataloged "${1##*/}" || exit 0
    # shellcheck disable=SC2086 # the wired points are meant to word-split
    PLANWRIGHT_ROOT=$HOOK_SELF_ROOT CLAUDE_PLUGIN_ROOT=$HOOK_SELF_ROOT TMPDIR=$DECL_TMP \
      exec /bin/bash "$rs" $STEP_POINTS --explain --unattended
  ) </dev/null >"$DECL_TMP/out" 2>/dev/null &
  DECL_PGID=$!
  set +m
  pid=$DECL_PGID
  ticks=$((deadline * 10))
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$ticks" -le 0 ]; then
      killed=1
      break
    fi
    sleep 0.1
    ticks=$((ticks - 1))
  done
  # The group goes either way: an overrun leaves the run itself, a finished
  # run can leave a sibling read it started. The pid is killed too in case
  # the job never got a group of its own.
  kill -KILL -- "-$pid" 2>/dev/null
  [ "$killed" = 0 ] || kill -KILL "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  DECL_PGID=''
  [ "$killed" = 0 ] || return 0
  # Only `run` rows count, so the exit status needs no reading: a point that
  # parks or asks prints those tokens (a refused step its own `refuse`), one
  # that fails prints nothing, and
  # either leaves the other points' rows as their own runs print them.
  # The --explain columns resolve-steps.sh documents; it prints `-` for an
  # empty field, which a tab IFS would otherwise collapse.
  while IFS=$TAB read -r dec _ _ _ _ target _ kind args _ _ _ loc pool _; do
    [ "$dec" = run ] && [ "$kind" = command ] || continue
    step_location_ok "$loc" "$target" || continue
    key=$loc
    if [ "$args" != - ]; then
      # Checked before the unquoted split, which would otherwise glob-expand
      # a `*` or `?` in the args against the working directory.
      case $args in
        *[!A-Za-z0-9._/:=@%,+\ -]*) continue ;;
      esac
      for w in $args; do
        key="$key $w"
      done
    fi
    DECL_LINES="$DECL_LINES$key$TAB${pool:--}$NL"
  done <"$DECL_TMP/out"
  return 0
}

# declared_line_ok: 0 when the current simple command, as tokenized (`sw` /
# `swq` / `swn` from verify_simple, before any tracked-assignment
# substitution), is a declared step's line. Reads `rn` via dynamic scope.
declared_line_ok() {
  local i=0 i0 f w name key mark_pool=''
  [ "$rn" -eq 0 ] || return 1
  # The declarations resolve from the payload cwd: after a `cd`, a declared
  # line's relative args would name other files than the declared ones.
  [ "$HOOK_CWD" = "$HOOK_PAYLOAD_CWD" ] || return 1
  case ${sw[0]} in
    PLANWRIGHT_STEP_*)
      for f in $STEP_CONTEXT_FIELDS; do
        [ "$i" -lt "$swn" ] || return 1
        w=${sw[i]}
        name=PLANWRIGHT_STEP_$f
        case $w in
          "$name="*) ;;
          *) return 1 ;;
        esac
        # A quote before the `=` makes the word a command name, not an assignment.
        if [ "${swq[i]}" -ge 0 ] && [ "${swq[i]}" -le "${#name}" ]; then
          return 1
        fi
        step_context_value_ok "$f" "${w#*=}" || return 1
        i=$((i + 1))
      done
      # A pooled step's hold mark, the one optional assignment after the
      # context fields.
      name=PLANWRIGHT_STEP_POOL_HOLD
      case ${sw[i]-} in
        "$name="*)
          if [ "${swq[i]}" -ge 0 ] && [ "${swq[i]}" -le "${#name}" ]; then
            return 1
          fi
          step_pool_hold_ok "${sw[i]#*=}" || return 1
          mark_pool=${sw[i]#*=}
          mark_pool=${mark_pool%%:*}
          i=$((i + 1))
          ;;
      esac
      ;;
  esac
  [ "$i" -lt "$swn" ] || return 1
  i0=$i
  key=${sw[i]}
  bare_abs_path_ok "$key" || return 1
  i=$((i + 1))
  while [ "$i" -lt "$swn" ]; do
    step_arg_ok "${sw[i]}" || return 1
    key="$key ${sw[i]}"
    i=$((i + 1))
  done
  [ "$DECL_RESOLVED" = 1 ] || resolve_declared "${sw[i0]}" 2>/dev/null
  # A mark is approved only on a step that declares the pool it names, so a
  # line can never claim a pool hold its step was not given.
  if [ -n "$mark_pool" ]; then
    case $NL$DECL_LINES in
      *"$NL$key$TAB$mark_pool$NL"*) declared_location_ok "${sw[i0]}" && return 0 ;;
    esac
    return 1
  fi
  case $NL$DECL_LINES in
    *"$NL$key$TAB"*) declared_location_ok "${sw[i0]}" && return 0 ;;
  esac
  return 1
}

# declared_location_ok <abs-path>: a declared step's location in a git checkout
# (the session's repository, or another such as the primary) is held to what
# that checkout's HEAD commits, as a script run by its path is: the declaration
# names the file, not its content, and the worker can Write the file. A
# location spelled inside the session's repository counts as in it even when a
# symlinked folder resolves it elsewhere, and so defers. A location in no
# checkout keeps the declaration's trust.
declared_location_ok() {
  local root d full
  d=$(cd -- "$(dirname -- "$1")" 2>/dev/null && pwd -P) || return 1
  if root=$(repo_root_of "$HOOK_PAYLOAD_CWD"); then
    case $1 in
      "$root"/*) d=$root ;;
    esac
  fi
  root=$(repo_root_of "$d") || return 0
  full=$(canon_under "$1" / "$root") || return 1
  committed_blob "$root" "${full#"$root"/}" "$full"
}

# verify_simple: verify one simple command — known-safe by the rules below, or
# else a declared step's line. Reads the accumulated word array `cw` (0=verb)
# / count `cwn` and the redirect arrays `ro` (ops) / `rt` (targets) / `rn`
# from the caller via dynamic scope. Returns 0 (safe) or non-zero (DEFER).
verify_simple() {
  local i swn=$cwn
  SIMPLE_N=$((SIMPLE_N + 1))
  [ "$SIMPLE_N" -le "$MAX_SIMPLE_CMDS" ] || return 1
  # Each `$` costs a pass over the rest of its word (expand_word,
  # word_tainted), so it is charged DOLLAR_COST on top of the word's length.
  for ((i = 0; i < cwn; i++)); do
    dollar_count "${cw[i]}"
    SCANNED=$((SCANNED + ${#cw[i]} + DOLLAR_N * DOLLAR_COST))
  done
  [ "$SCANNED" -le "$MAX_SCANNED" ] || return 1
  local -a sw=() swq=()
  for ((i = 0; i < cwn; i++)); do
    sw[i]=${cw[i]}
    swq[i]=${cqp[i]}
  done
  # The floor comes before every arm and the declared steps. An own-unit act
  # it reserves is weighed exactly by verify_known_simple, and nothing else
  # may approve it.
  local own_cand=0 STEP_CALL=0
  [ "$cwn" -eq 0 ] || ! deny_hit "${sw[@]}" || return 1
  if [ "$cwn" -gt 0 ] && floor_act_words "${sw[@]}"; then
    own_unit_candidate || return 1
    own_cand=1
  fi
  verify_known_simple && return 0
  # A step-script call step_call_ok refused is never a declared line's.
  [ "$own_cand" = 0 ] && [ "$STEP_CALL" = 0 ] || return 1
  # A declared check command or step is an operator's line, never one around
  # a substitution, and is not read-only inside one. Nor is one judged in the
  # scoped read mode, whose directory is one of two.
  [ "$IN_SUBST" = 0 ] && [ "$SCOPED_RD" = 0 ] || return 1
  for ((i = 0; i < cwn; i++)); do
    [ -z "${csub[i]-}" ] || return 1
  done
  # A declared check command or command step is a trusted repository task:
  # a chain partner before an own-unit act. A check command check_may_partner
  # refuses, unless a step declares the same line, is approved alone but keeps
  # every own-unit act in its command from being approved.
  if check_command_ok; then
    check_may_partner || declared_line_ok || {
      ARM_ACT=1
      return 0
    }
  else
    declared_line_ok || return 1
  fi
  OU_PARTNER=1
}

# An approved wait or time limit is at most two hours, which covers the
# longest real wait (a full gate run) while a typo such as `sleep 365d` still
# reaches the prompt instead of parking the worker for good.
readonly MAX_WAIT_SECONDS=7200

# is_duration <word>: the `sleep` / `timeout` duration form, its length (a
# fraction rounded up to a whole unit, which errs short of the cap) left in
# DURATION_SECONDS; at most MAX_WAIT_SECONDS.
is_duration() {
  local re='^([0-9]{1,9})(\.([0-9]+))?([smhd]?)$' whole mult
  [[ $1 =~ $re ]] || return 1
  whole=$((10#${BASH_REMATCH[1]}))
  case ${BASH_REMATCH[4]} in
    m) mult=60 ;;
    h) mult=3600 ;;
    d) mult=86400 ;;
    *) mult=1 ;;
  esac
  DURATION_SECONDS=$((whole * mult))
  case ${BASH_REMATCH[3]} in
    *[1-9]*) DURATION_SECONDS=$((DURATION_SECONDS + mult)) ;;
  esac
  [ "$DURATION_SECONDS" -le "$MAX_WAIT_SECONDS" ]
}

# strip_step_context: drop a leading step-context prefix from the current
# simple command, so the installed step script it feeds is verified as the bare
# call is. The prefix is an optional bare `env` followed only by, or plain
# leading, `PLANWRIGHT_STEP_<field>=<literal>` words, every field one of
# STEP_CONTEXT_FIELDS, every value bare (no quote, expansion, glob or
# substitution), inside the charset of a branch, path or number, and valid for
# its field. The word after them must be step-run.sh or step-record.sh under an
# installed planwright root; anything else leaves the words untouched, and the
# `env` operands or the assignment prefix then defer as before. The pool hold
# mark stays with declared_line_ok: it claims a pool a declaration must back.
strip_step_context() {
  local i=0 first f w name
  [ "$HOOK_DEPTH" -eq 0 ] && [ "$IN_SUBST" = 0 ] || return 0
  # An expansion that changed the word count is not the words as written.
  [ "$cwn" -eq "$swn" ] || return 0
  if [ "${sw[0]}" = env ] && [ "${swq[0]}" -lt 0 ] && [ "${cw[0]}" = env ]; then
    i=1
  fi
  first=$i
  while [ "$i" -lt "$swn" ]; do
    w=${sw[i]}
    case $w in
      PLANWRIGHT_STEP_*=*) ;;
      *) break ;;
    esac
    name=${w%%=*}
    f=${name#PLANWRIGHT_STEP_}
    case " $STEP_CONTEXT_FIELDS " in
      *" $f "*) ;;
      *) return 0 ;;
    esac
    [ "${swq[i]}" -lt 0 ] && [ "${cw[i]}" = "$w" ] && [ -z "${csub[i]-}" ] || return 0
    word_unresolved "$w" "${cdyn[i]}" "${cglob[i]}" "${cx[i]}" && return 0
    # The charset leaves out `=`: zsh expands `=cmd` and `:=` forms in an
    # assignment (assign_value_literal refuses the same).
    case ${w#*=} in
      *[!A-Za-z0-9._/:@%,+-]*) return 0 ;;
    esac
    step_context_value_ok "$f" "${w#*=}" || return 0
    i=$((i + 1))
  done
  [ "$i" -gt "$first" ] && [ "$i" -lt "$swn" ] || return 0
  [ "${swq[i]}" -lt 0 ] && [ "${cw[i]}" = "${sw[i]}" ] || return 0
  word_unresolved "${cw[i]}" "${cdyn[i]}" "${cglob[i]}" "${cx[i]}" && return 0
  case ${cw[i]} in
    */step-run.sh | */step-record.sh) ;;
    *) return 0 ;;
  esac
  is_planwright_script "${cw[i]}" "$HOOK_CWD" || return 0
  shift_words "$i"
}

# strip_prefixes: drop the transparent `time [-p]`, `timeout <duration>` and
# `nice -n <0..19>` prefixes (REQ-A1.13, REQ-A1.16) from the current simple
# command, setting PREFIXED, so the command they wrap is verified as if it
# stood alone. Non-zero defers: a prefix with nothing to run, a `cd` under a
# prefix (its directory would not carry), or a `time`, `timeout` or `nice`
# left after the prefixes, which would be the program or a nested wrapper
# rather than a keyword. A leading compute-route.sh `--` is dropped last (see
# strip_compute_route), so a wrapper may precede it but never follow. A `timeout`
# whose next word is not a duration is left as the verb, and classify_verb
# defers it.
strip_prefixes() {
  PREFIXED=0
  # `time` is a keyword only when written as a bare word, and `-p` its option
  # only when written bare too (a quoted `"-p"` is the command it runs), so
  # both are read from the unsubstituted words (`sw` / `swq`, verify_simple's
  # copy): a `$T` that expands to `time` runs the program. The timeout
  # duration is held to a bare word the same way.
  if [ "${sw[0]-}" = time ] && [ "${swq[0]-}" -lt 0 ]; then
    if [ "${sw[1]-}" = -p ] && [ "${swq[1]-}" -lt 0 ] && [ "${cw[1]-}" = -p ]; then
      shift_words 2
    else
      shift_words 1
    fi
    PREFIXED=1
    [ "$cwn" -ge 1 ] || return 1
  fi
  # `nice -n <0..19>` and `timeout <duration>` wrap each other in either
  # order, each at most once (a second one is left as the verb and defers).
  local niced=0 before=$cwn
  strip_nice
  [ "$cwn" -lt "$before" ] && niced=1
  if [ "${cw[0]}" = timeout ] && [ "$cwn" -ge 2 ] && [ "${cqp[1]}" -lt 0 ] \
    && ! word_unresolved "${cw[1]}" "${cdyn[1]}" "${cglob[1]}" "${cx[1]}" \
    && is_duration "${cw[1]}"; then
    shift_words 2
    PREFIXED=1
    [ "$cwn" -ge 1 ] || return 1
    [ "$niced" = 0 ] && strip_nice
  fi
  strip_compute_route || return 1
  if [ "$PREFIXED" = 1 ]; then
    case ${cw[0]} in
      time | timeout | nice | cd) return 1 ;;
    esac
  fi
  return 0
}

# strip_compute_route: drop a leading `<installed root>/scripts/compute-route.sh
# [<kind>] --`, setting PREFIXED, so the command it routes is verified as if it
# stood alone: the router only chooses where an approved command runs. A copy in
# the checkout is a worker-authored script, so only the installed one counts. A
# kind flag names to the host the command it runs there, so it is transparent
# only beside the one command the router itself maps to that kind, which is
# what the bare form would have run: `--check -- mise run check`,
# `--task <name> -- mise run <name>`, `--test tests/test-<name>.sh -- bash
# tests/test-<name>.sh` (the router's own grammar). Defer: any other pairing,
# two kinds, a router with nothing to run, a bare router name (the shell looks
# it up on PATH), and another router as the command.
# is_trusted_script refuses the script as a verb, so no other spelling reaches
# the router.
strip_compute_route() {
  local n=1 kind='' val='' i end re_task='^[a-z][a-z0-9:_-]*$' re_test='^tests/test-[A-Za-z0-9._-]+\.sh$'
  case ${cw[0]} in
    compute-route.sh | */compute-route.sh) ;;
    *) return 0 ;;
  esac
  # A bare name is looked up on PATH by the shell, not beside this hook's root.
  case ${cw[0]} in
    */*) ;;
    *) return 1 ;;
  esac
  case ${cw[1]-} in
    --check)
      kind=check
      n=2
      ;;
    --task | --test)
      kind=${cw[1]#--}
      val=${cw[2]-}
      n=3
      ;;
  esac
  [ "$cwn" -ge $((n + 2)) ] && [ "${cw[n]}" = -- ] || return 1
  for ((i = 0; i <= n; i++)); do
    [ "${cqp[i]}" -lt 0 ] && ! word_unresolved "${cw[i]}" "${cdyn[i]}" "${cglob[i]}" "${cx[i]}" || return 1
  done
  is_planwright_script "${cw[0]}" "$HOOK_CWD" || return 1
  case $kind in
    check)
      end=$((n + 4))
      [ "$cwn" -eq "$end" ] && [ "${cw[n + 1]}" = mise ] && [ "${cw[n + 2]}" = run ] && [ "${cw[n + 3]}" = check ] || return 1
      ;;
    task)
      end=$((n + 4))
      [[ $val =~ $re_task ]] && [ "$val" != check ] && [ "$cwn" -eq "$end" ] && [ "${cw[n + 1]}" = mise ] && [ "${cw[n + 2]}" = run ] && [ "${cw[n + 3]}" = "$val" ] || return 1
      ;;
    test)
      end=$((n + 3))
      [[ $val =~ $re_test ]] && [ "$cwn" -eq "$end" ] && [ "${cw[n + 1]}" = bash ] && [ "${cw[n + 2]}" = "$val" ] || return 1
      ;;
  esac
  if [ -n "$kind" ]; then
    for ((i = n + 1; i < cwn; i++)); do
      [ "${cqp[i]}" -lt 0 ] && ! word_unresolved "${cw[i]}" "${cdyn[i]}" "${cglob[i]}" "${cx[i]}" || return 1
    done
  fi
  shift_words $((n + 1))
  PREFIXED=1
  # The router is a plugin script other than a step script: whatever it
  # routes, it keeps an own-unit act out of its command.
  ARM_ACT=1
  case ${cw[0]} in
    compute-route.sh | */compute-route.sh) return 1 ;;
  esac
  return 0
}

# strip_nice: drop a leading `nice -n <0..19>` (REQ-A1.16) when the adjustment
# is a bare plain decimal literal, setting PREFIXED. Any other spelling is left
# as the verb, which classify_verb defers: a negative adjustment is privileged
# and a non-literal value is unreadable here.
strip_nice() {
  local re='^([0-9]|1[0-9])$'
  [ "${cw[0]}" = nice ] && [ "$cwn" -ge 4 ] && [ "${cw[1]}" = -n ] \
    && [ "${cqp[1]}" -lt 0 ] && [ "${cqp[2]}" -lt 0 ] \
    && ! word_unresolved "${cw[2]}" "${cdyn[2]}" "${cglob[2]}" "${cx[2]}" \
    && [[ ${cw[2]} =~ $re ]] || return 0
  shift_words 3
  PREFIXED=1
}

# cd_target_ok: the current simple command is `cd <dir>` naming an existing
# directory inside the session's own worktree (REQ-E1.4); leaves its
# canonical path in PENDING_CD for verify_tokens to carry once it knows the
# segment's placement. The operand is resolved by this hook against the
# modelled working directory, never through CDPATH, and only where bash's
# logical `cd` lands on the same directory as the physical path checked
# here: no `..` component, no symlinked component, and an absolute operand
# written in its canonical form. A `fish -c` inner string defers, its `cd`
# being fish's.
cd_target_ok() {
  [ "$cwn" -eq 2 ] || return 1
  if [ "$OUTSIDE_CD" = 0 ] && own_dir_ok 1; then
    PENDING_CD=$OWN_DIR
    return 0
  fi
  cd_outside_ok 1 || return 1
  PENDING_OUT=1
  PENDING_OUT_DIR=$OUT_DIR
  return 0
}

# cd_outside_ok <word-index>: a `cd` to an existing directory outside the
# worktree, for the read lines that start `cd /tmp; ...`. The guard does not
# model the directory it lands in, so every later segment of the command is
# held to the pure-read verbs (outside_cwd_verb) and to no file redirect: a
# relative path in a write, a trusted script or a git command would otherwise
# be judged against a directory the command is no longer in. Top level only,
# an absolute canonical operand, never under /proc, /sys or /dev, and never a
# secret or broad directory, since any read there may reach a key. The
# directory is left in OUT_DIR.
cd_outside_ok() {
  local n=$1 t=${cw[$1]-} canon
  [ "$HOOK_DEPTH" -eq 0 ] && [ "$IN_SUBST" = 0 ] && [ "$HOOK_CDPATH_SET" = 0 ] && [ "${ctl_depth:-1}" -eq 0 ] || return 1
  word_unresolved "$t" "${cdyn[n]}" "${cglob[n]}" "${cx[n]}" && return 1
  [ "${cz[n]-0}" = 0 ] || return 1
  case $t in
    /*) ;;
    *) return 1 ;;
  esac
  case $t in
    *[!A-Za-z0-9._/@%,:+-]*) return 1 ;;
  esac
  case /$t/ in
    */../*) return 1 ;;
  esac
  canon=$(cd "$t" 2>/dev/null && pwd -P) || return 1
  [ "$canon" = "$t" ] || [ "$canon/" = "$t" ] || return 1
  case $canon in
    /proc | /proc/* | /sys | /sys/* | /dev | /dev/*) return 1 ;;
  esac
  secret_path_risky "$canon" 0 && return 1
  broad_canon "$canon" && return 1
  OUT_DIR=$canon
  return 0
}

# outside_cwd_verb <verb>: the verbs a segment may run after a `cd` outside
# the worktree: readers whose operands never run or write anything.
outside_cwd_verb() {
  case $1 in
    cat | head | tail | wc | cut | comm | cmp | basename | dirname | realpath | pwd | echo | seq | true | false | od | tr | stat | grep | ls | diff) classify_verb "$1" ;;
    printenv | readlink | nl | paste | column | md5sum | sha1sum | sha256sum | sha512sum | cksum) classify_verb "$1" ;;
    sort | uniq | jq | gh | rg | sleep | test | '[' | printf) classify_verb "$1" ;;
    sed) guard_sed ;;
    *) return 1 ;;
  esac
}

# The scoped read mode: the line a review subagent writes as `cd <own dir>;
# <reads>`, or `cd <own dir> && <reads>` with a later `;` or `||`. Past that
# point the directory is the cd's target or, had the cd failed, the one
# before it, so both must lie in the session's own worktree and repository
# (scoped_alt_ok), and every later segment is held to scoped_read_ok: a read
# verb with no redirect and no substitution, each operand a path inside the
# worktree, the session's own scratch root (the record's, and only while the
# TMPDIR the hook inherited names it), or an installed planwright root, from
# both directories. A sibling session's scratch root is in none of them.
# The mode is stricter than the plain read rules: a segment it does not admit
# defers the whole line rather than falling back to them.

# is_abs <word>: the word is an absolute path.
is_abs() {
  case $1 in
    /*) return 0 ;;
  esac
  return 1
}

# scoped_alt_ok <dir>: the directory is inside the worktree and its
# repository; its canonical form is left in SCOPED_ALT.
scoped_alt_ok() {
  local c
  [ -n "$REC_WT" ] && [ -n "$HOOK_WT_ROOT" ] || return 1
  canon_dir_cached "$1"
  c=$CANON
  [ -n "$c" ] || return 1
  case $c/ in
    "$REC_WT"/*) ;;
    *) return 1 ;;
  esac
  [ "$c" = "$HOOK_WT_ROOT" ] || cd_same_repo "$c" || return 1
  SCOPED_ALT=$c
}

# scoped_root_has <canonical-path>: the path is one of the roots or under one.
scoped_root_has() {
  local root
  [ -n "$REC_WT" ] || return 1
  case $1/ in
    "$REC_WT"/*) return 0 ;;
  esac
  if [ "$HOOK_TMPDIR_IS_SCRATCH" = 1 ] && [ -n "$REC_SCRATCH" ]; then
    case $1/ in
      "$REC_SCRATCH"/*) return 0 ;;
    esac
  fi
  cache_roots
  while IFS= read -r root; do
    [ -n "$root" ] && [ "$root" != / ] || continue
    case $1/ in
      "$root"/*) return 0 ;;
    esac
  done <<EOF
$PW_ROOTS
EOF
  return 1
}

# scoped_under <absolute-path>: the path, its directory canonicalized and its
# last component no symlink, lies in a root. canon_under's check against
# several roots, through the per-call directory cache.
scoped_under() {
  local d=${1%/*} b=${1##*/} full
  [ -n "$d" ] || d=/
  canon_dir_cached "$d"
  [ -n "$CANON" ] || return 1
  case $b in
    '' | .) full=$CANON ;;
    *) full=${CANON%/}/$b ;;
  esac
  [ -L "$full" ] && return 1
  scoped_root_has "$full"
}

# scoped_word_plain <index> [glob]: the word's value is its text: nothing
# left unresolved, no zsh pattern character, no leading `=` zsh would expand
# to a command's path, and no glob unless `glob` is given, then only an
# unquoted `*` or `?` (never a brace, a bracket, a tilde, or a backslash).
scoped_word_plain() {
  local i=$1 w=${cw[$1]}
  [ "${cz[i]-0}" = 0 ] || return 1
  word_unresolved "$w" "${cdyn[i]}" 0 "${cx[i]}" && return 1
  case $w in
    =*) [ "${cqp[i]}" = 0 ] || return 1 ;;
  esac
  [ "${cglob[i]}" = 0 ] && return 0
  [ "${2-}" = glob ] && [ "${cqp[i]}" -lt 0 ] || return 1
  case $w in
    *[{}~\[\\]*) return 1 ;;
  esac
  return 0
}

# scoped_opt_word_ok <index>: an option word; a glob may only follow its `=`
# (`--include=*.sh`), so whatever it matches is still that option.
scoped_opt_word_ok() {
  local i=$1 w=${cw[$1]}
  if [ "${cglob[i]}" = 0 ]; then
    scoped_word_plain "$i"
    return
  fi
  scoped_word_plain "$i" glob || return 1
  case ${w%%[*?]*} in
    --*=*) return 0 ;;
  esac
  return 1
}

# scoped_path_ok <index>: the operand names a path inside a root from every
# directory the line may run in. A glob only in the last component, never
# dot-led, in a directory holding no symlink a match could follow and no
# name a match would turn into an option.
scoped_path_ok() {
  local i=$1 w=${cw[$1]} p rest e
  scoped_word_plain "$i" glob || return 1
  case /$w/ in
    */../*) return 1 ;;
  esac
  p=$w
  if [ "${cglob[i]}" = 1 ]; then
    rest=${w##*/}
    case $rest in
      .*) return 1 ;;
    esac
    case ${w%"$rest"} in
      *[*?]*) return 1 ;;
    esac
    p=${w%"$rest"}
    [ -n "$p" ] || p=.
  fi
  if is_abs "$p"; then
    set -- "$p"
  else
    set -- "$HOOK_CWD/$p"
    [ -z "$SCOPED_ALT" ] || [ "$SCOPED_ALT" = "$HOOK_CWD" ] || set -- "$1" "$SCOPED_ALT/$p"
  fi
  for e in "$@"; do
    scoped_under "$e" || return 1
  done
  [ "${cglob[i]}" = 1 ] || return 0
  for p in "$@"; do
    for e in "$p"/* "$p"/.[!.]* "$p"/..?*; do
      [ -L "$e" ] && return 1
      case ${e##*/} in
        -*) return 1 ;;
      esac
    done
  done
  return 0
}

# scoped_git_ok: `git show`, `git diff` or `git log`, the only global option
# an absolute `-C` into the worktree, every word plain, no `--no-index` or
# orderfile, an absolute word only on an allowed path and no `..` component
# (git diff reads two paths outside the repository as `--no-index`), and
# guard_git's own screen on top.
scoped_git_ok() {
  local i s=1
  if [ "${cw[1]-}" = -C ]; then
    is_abs "${cw[2]-}" || return 1
    s=3
  fi
  case ${cw[s]-} in
    show | diff | log) ;;
    *) return 1 ;;
  esac
  for ((i = 1; i < cwn; i++)); do
    scoped_word_plain "$i" || return 1
    case ${cw[i]} in
      --no-index | --orderfile | --orderfile=*) return 1 ;;
      /*) scoped_path_ok "$i" || return 1 ;;
    esac
    case /${cw[i]}/ in
      */../*) return 1 ;;
    esac
  done
  guard_git
}

# scoped_grep_opt <index>: one grep option word, from an allowlist (GNU grep
# takes any unique prefix of a long option, so only whole names pass). Sets
# SC_TAKE to `pat` or `num` when the next word is that option's value. `-f`,
# `-R`, `-d` and `-D` are refused: a pattern file is a path read out of
# sight, and the others follow links or devices.
scoped_grep_opt() {
  local w=${cw[$1]} c rest
  case $w in
    --regexp)
      SC_TAKE=pat
      return 0
      ;;
    --max-count | --context | --after-context | --before-context)
      SC_TAKE=num
      return 0
      ;;
    --regexp=* | --max-count=* | --context=* | --after-context=* | --before-context=* | --include=* | --exclude=* | --exclude-dir=* | --binary-files=* | --color=* | --colour=*) return 0 ;;
    --line-number | --recursive | --ignore-case | --no-ignore-case | --count | --files-with-matches | --files-without-match | --only-matching | --no-filename | --with-filename | --word-regexp | --line-regexp | --invert-match | --extended-regexp | --fixed-strings | --perl-regexp | --basic-regexp | --quiet | --silent | --null | --null-data | --text | --byte-offset | --initial-tab | --no-messages | --color | --colour) return 0 ;;
    --*) return 1 ;;
  esac
  rest=${w#-}
  while [ -n "$rest" ]; do
    c=${rest%"${rest#?}"}
    rest=${rest#?}
    case $c in
      e)
        [ -n "$rest" ] || SC_TAKE=pat
        return 0
        ;;
      [ABCm])
        if [ -n "$rest" ]; then
          case $rest in
            *[!0-9]*) return 1 ;;
          esac
        else
          SC_TAKE=num
        fi
        return 0
        ;;
      [abcEFGhHiIlLnoqrsTUvwxyzZ0-9]) ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# scoped_read_ok: the current simple command is one of the scoped read
# verbs with every operand on an allowed path (see scoped_path_ok); the
# caller has already refused its redirects and substitutions. grep's
# pattern and sed's script are no path: the first operand unless an option
# supplies one (both permute their arguments, so any option anywhere
# counts). sed must run with `-n`; tail may not follow, which never ends.
scoped_read_ok() {
  local verb=${cw[0]} i w opts=1 first=1 quiet=0 given=0
  local SC_TAKE=''
  case $verb in
    cat | head | tail | wc | ls | grep) ;;
    sed) guard_sed || return 1 ;;
    git)
      scoped_git_ok
      return
      ;;
    *) return 1 ;;
  esac
  for ((i = 1; i < cwn; i++)); do
    w=${cw[i]}
    [ "$w" = -- ] && break
    case $verb:$w in
      grep:--regexp | grep:--regexp=* | sed:-e | sed:--expression | sed:--expression=*) given=1 ;;
      grep:--*) ;;
      grep:-*e*) given=1 ;;
    esac
  done
  [ "$given" = 0 ] || first=0
  [ "$verb" = grep ] || [ "$verb" = sed ] || first=0
  for ((i = 1; i < cwn; i++)); do
    w=${cw[i]}
    case $SC_TAKE in
      pat)
        scoped_word_plain "$i" || return 1
        SC_TAKE=''
        continue
        ;;
      num)
        case $w in
          '' | *[!0-9]*) return 1 ;;
        esac
        SC_TAKE=''
        continue
        ;;
    esac
    if [ "$opts" = 1 ]; then
      case $w in
        --)
          opts=0
          continue
          ;;
        -?*)
          scoped_opt_word_ok "$i" || return 1
          case $verb:$w in
            grep:*) scoped_grep_opt "$i" || return 1 ;;
            sed:-n | sed:--quiet | sed:--silent) quiet=1 ;;
            sed:-e | sed:--expression) SC_TAKE=pat ;;
            wc:--lines | wc:--words | wc:--bytes | wc:--chars | wc:--max-line-length | wc:--total=*) ;;
            wc:--* | wc:-*[!lwcmL]*) return 1 ;;
            ls:--de* | tail:--f* | tail:--r*) return 1 ;;
            ls:--* | tail:--*) ;;
            ls:-*L* | tail:-*[fF]*) return 1 ;;
          esac
          continue
          ;;
      esac
    fi
    if [ "$first" = 1 ]; then
      first=0
      scoped_word_plain "$i" || return 1
      continue
    fi
    scoped_path_ok "$i" || return 1
  done
  [ -z "$SC_TAKE" ] || return 1
  [ "$verb" != sed ] || [ "$quiet" = 1 ] || return 1
  if opens_operands "$verb"; then
    environ_words_ok || return 1
  fi
  return 0
}

# own_dir_ok <word-index>: the word is an operand naming an existing directory
# inside the session's own worktree and repository, in a form bash, zsh and
# git all read the same way; leaves its canonical path in OWN_DIR. Shared by
# `cd <dir>` (above) and `git -C <dir>` (guard_git).
own_dir_ok() {
  local n=$1 t=${cw[$1]-} base acc comp canon
  local -a comps=()
  OWN_DIR=''
  [ "$HOOK_DEPTH" -eq 0 ] && [ "$IN_SUBST" = 0 ] && [ "$HOOK_CDPATH_SET" = 0 ] || return 1
  # The worktree comes from the session record, never the checkout.
  [ -n "$REC_WT" ] && [ -n "$REC_UNIT" ] || return 1
  HOOK_WT_ROOT=$REC_WT
  word_unresolved "$t" "${cdyn[n]}" "${cglob[n]}" "${cx[n]}" && return 1
  # A plain operand only: bash tilde-expands after `=`, zsh reads `+N` / `-N`
  # as the directory stack and `=cmd` as a command path, and zsh glob options
  # a shell snapshot can carry turn `^`, `#`, `~` and braces into patterns.
  [ "${cz[n]-0}" = 0 ] || return 1
  case $t in
    '' | [-+]* | *[!A-Za-z0-9._/@%,:+-]*) return 1 ;;
  esac
  case /$t/ in
    */../*) return 1 ;;
  esac
  case $t in
    /*)
      canon=$(cd "$t" 2>/dev/null && pwd -P) || return 1
      [ "$canon" = "$t" ] || [ "$canon/" = "$t" ] || return 1
      ;;
    *)
      base=$(cd "$HOOK_CWD" 2>/dev/null && pwd -P) || return 1
      acc=$base
      IFS=/ read -r -a comps <<<"$t"
      for comp in ${comps[@]+"${comps[@]}"}; do
        case $comp in
          '' | .) continue ;;
        esac
        acc=$acc/$comp
        [ -L "$acc" ] && return 1
        [ -d "$acc" ] || return 1
      done
      canon=$(cd "$acc" 2>/dev/null && pwd -P) || return 1
      [ "$canon" = "$acc" ] || return 1
      ;;
  esac
  case $canon in
    "$HOOK_WT_ROOT" | "$HOOK_WT_ROOT"/*) ;;
    *) return 1 ;;
  esac
  cd_same_repo "$canon" || return 1
  OWN_DIR=$canon
  return 0
}

# cd_same_repo <canonical-dir>: 0 only when git places <dir> in the session's
# own repository: the same top level and the same common directory as the
# worktree root. A nested repository, a submodule, another worktree, or the
# git directory itself would hand every later `git` that repository's own
# config (its fsmonitor, hooks, aliases, pager), which is why `git -C <dir>`
# and a `cd` there defer; rev-parse reads config but runs
# none of it.
cd_same_repo() {
  local here
  if [ -z "${HOOK_WT_GIT:-}" ]; then
    HOOK_WT_GIT=$(git -C "$HOOK_WT_ROOT" rev-parse --path-format=absolute --show-toplevel --git-common-dir 2>/dev/null) \
      || return 1
  fi
  here=$(git -C "$1" rev-parse --path-format=absolute --show-toplevel --git-common-dir 2>/dev/null) || return 1
  [ -n "$here" ] && [ "$here" = "$HOOK_WT_GIT" ]
}

# version_tool <verb>: the allowlisted tools whose bare `--version` form
# (REQ-E1.5) only prints a version.
version_tool() {
  case $1 in
    git | gh | jq | yq | rg | fd | sed | awk | find | grep | sort | uniq | date | file | \
      bash | sh | fish | bats | mise | lefthook | shellcheck | shfmt | yamllint | \
      markdownlint | markdownlint-cli2 | cat | head | tail | wc | ls | diff | stat | od | tr | \
      seq | cut | comm | cmp | basename | dirname | realpath | readlink | nl | paste | column | \
      md5sum | sha1sum | sha256sum | sha512sum | cksum | env | printenv | sleep | ps | uptime | which) return 0 ;;
  esac
  return 1
}

# read_screens_ok: the current simple command's operands, read from HOOK_CWD,
# reach no environ file, secret or broad directory.
read_screens_ok() {
  if opens_operands "${cw[0]}"; then
    environ_words_ok || return 1
  elif lists_operands "${cw[0]}"; then
    secret_words_ok || return 1
  fi
  if recursive_reader; then
    broad_words_ok || return 1
  fi
  if link_follower; then
    follow_links_ok || return 1
  fi
  return 0
}

# verify_known_simple: the enumerated known-safe rules for one simple command.
verify_known_simple() {
  local i verb si sc_ok=0 here rc=0
  # The scoped read mode takes no substitution and no redirect at all; a
  # lead cd's chain still in the running notes whether this segment would
  # pass it.
  if [ "$SCOPED_RD" = 1 ] || [ "$SCOPED_CHAIN" = 1 ]; then
    sc_ok=1
    [ "$rn" -eq 0 ] || sc_ok=0
    for ((i = 0; i < cwn; i++)); do
      [ -z "${csub[i]-}" ] || sc_ok=0
    done
    [ "$SCOPED_RD" = 0 ] || [ "$sc_ok" = 1 ] || return 1
  fi
  # Each substitution's own command runs whatever the words around it are,
  # so it must pass first, against the working directory it will run in.
  if [ "$SUBST_N" -gt 0 ]; then
    for ((i = 0; i < cwn; i++)); do
      for si in ${csub[i]-}; do
        [ "${SUBST_OKD[si]-}" = "d:$HOOK_CWD" ] && continue
        subst_inner_ok "${SUBST_TXT[si]}" || return 1
        SUBST_OKD[si]=d:$HOOK_CWD
      done
    done
  fi
  # Redirects first: a write to a real file defers regardless of the verb,
  # unless its target is in the spec-root write zone (covers a leading
  # redirect with no command too, e.g. `> f cat x`). A bare target takes the
  # tracked values as a split word does, which leaves a value holding a space
  # unresolved; a tracked value holds no pattern character to glob.
  # On a bare assignment (`X=a >$X`) the shell assigns first and expands the
  # target with the new value, so a target naming that variable stays
  # unresolved (any name it prefixes, too, which only defers more).
  local rtw rexp rname=''
  if [ "$cwn" -eq 1 ]; then
    case ${cw[0]} in
      [A-Za-z_]*=*) rname=${cw[0]%%=*} ;;
    esac
  fi
  for ((i = 0; i < rn; i++)); do
    rtw=${rt[i]}
    rexp=1
    if [ -n "$rname" ]; then
      case $rtw in
        *"\$$rname"* | *"\${$rname"*) rexp=0 ;;
      esac
    fi
    if [ "$rexp" = 1 ] && [ "$VAR_C" -gt 0 ] && [ "${rtx[i]}" = 00 ]; then
      case $rtw in
        *'$'*)
          expand_word "$rtw" split
          rtw=$EXPANDED
          ;;
      esac
    fi
    # The spec-root zone keeps its plain-literal rule: only the policy arms
    # read the expanded target.
    classify_redirect "${ro[i]}" "${rt[i]}" \
      || { [ "$OUTSIDE_CD" = 0 ] && { spec_zone_redirect "${ro[i]}" "${rt[i]}" || ob_redirect "${ro[i]}" "$rtw"; }; } \
      || return 1
    environ_redirect_ok "$rtw" || return 1
  done
  # A command with redirects but no words (pure `> file`) already handled;
  # an empty simple command (e.g. a trailing separator) is a no-op.
  [ "$cwn" -ge 1 ] || return 0
  # A standalone assignment (the whole simple command is one `NAME=value`
  # word) that the tracking rules admit runs nothing and is recorded for the
  # words that follow; whether it is committed is verify_tokens' call. It is
  # read before substitution: a word that only becomes `NAME=value` through
  # an expansion is a command name, not an assignment.
  secret_vars_ok || return 1
  if [ "$cwn" -eq 1 ] && track_assignment; then
    return 0
  fi
  # Resolve the tracked assignments into this command's words, so a verb,
  # script path, or screened operand written through `$NAME` is verified as
  # the words the shell will run. Words carrying a literal `$` are left alone.
  [ "$VAR_C" -eq 0 ] || expand_words
  [ "$cwn" -ge 1 ] || return 0
  if own_unit_act; then
    AUDIT_OU=1
    OU_SEG=1
    return 0
  fi
  strip_step_context
  strip_prefixes || return 1
  # The floor again, on the words the shell will run.
  deny_hit "${cw[@]}" && return 1
  floor_act && return 1
  verb=${cw[0]}
  # A substitution's command must be read-only, and trusted repo code (a
  # script, `bash`/`sh` running one, `mise`, `lefthook`, `bats`) may write.
  if [ "$IN_SUBST" = 1 ]; then
    case $verb in
      */* | bash | sh | mise | lefthook | bats) return 1 ;;
    esac
  fi
  if [ "$verb" = cd ]; then
    [ "$SCOPED_RD" = 0 ] || return 1
    cd_target_ok
    return
  fi
  if [ "$SCOPED_RD" = 1 ]; then
    scoped_read_ok || return 1
    SEG_SCOPED=1
    return 0
  fi
  if [ "$sc_ok" = 1 ] && scoped_read_ok; then
    SEG_SCOPED=1
  fi
  if [ "$OUTSIDE_CD" = 1 ]; then
    [ "$cwn" -ge 1 ] && outside_cwd_verb "$verb" || return 1
    [ -n "$OUTSIDE_DIR" ] || return 1
    # Relative operands name paths under the directory the cd landed in.
    here=$HOOK_CWD
    HOOK_CWD=$OUTSIDE_DIR
    read_screens_ok || rc=1
    HOOK_CWD=$here
    [ "$rc" = 0 ] || return 1
    subst_words_ok || return 1
    return 0
  fi
  read_screens_ok || return 1
  subst_words_ok || return 1
  # Inline environment-assignment prefix (REQ-A1.9): VAR=value [cmd].
  case $verb in
    [A-Za-z_]*=*)
      case $verb in
        *=*)
          case ${verb%%=*} in
            *[!A-Za-z0-9_]*) ;; # not a valid identifier: fall through to verb lookup
            *) return 1 ;;      # env-assignment prefix -> defer
          esac
          ;;
      esac
      ;;
  esac
  # A verb given as a path containing '/' is only the enumerated trusted-script
  # case (repo code, or an installed planwright root's scripts/); every other
  # path-prefixed verb defers (REQ-A1.9, REQ-A1.10).
  case $verb in
    */*)
      is_trusted_script "$verb" "$HOOK_CWD" || return 1
      if step_script_kind "$verb"; then
        STEP_CALL=1
        step_call_ok 0 || return 1
      fi
      ou_script_kind "$verb"
      return 0
      ;;
  esac
  if [ "$cwn" -eq 2 ] && [ "${cw[1]}" = --version ] && version_tool "$verb"; then
    return 0
  fi
  classify_verb "$verb" || return 1
  case $verb in
    mise | lefthook | bats) OU_PARTNER=1 ;;
    bash | sh) ou_script_kind "${cw[1]}" ;;
  esac
  return 0
}

# ou_script_kind <trusted script>: what the script is to an own-unit act in
# the same command. A repository script is a chain partner (a gate task); an
# installed step script is neither; any other plugin script keeps the act
# from being approved, since it may write.
ou_script_kind() {
  if is_repo_script "$1" "$HOOK_CWD"; then
    OU_PARTNER=1
    return 0
  fi
  case $1 in
    */step-run.sh | */step-record.sh) return 0 ;;
  esac
  ARM_ACT=1
}

# --------------------------------------------------------------------------
# verify_tokens <depth>: walk the token stream (in the caller's TOK_* locals),
# splitting into simple commands on control operators and recognizing the
# for/while/until/if/case control structures so their COMMAND regions are each
# verified while their case pattern regions are skipped (REQ-A1.5). A `for`
# header is modelled (loop_enter: the body is verified once per head word);
# `select`, `for` with no in-list, and an arithmetic `for ((…))` defer. Any
# construct it cannot confidently place — a stray `)`, a subshell `(`, a brace
# group, a nested `case`, an unbalanced structure — defers. Returns 0 (every
# simple command safe) or non-zero (DEFER).
verify_tokens() {
  local depth=$1
  local idx=0 typ val
  local mode=normal # normal | casehead | casepat | casebody
  local case_depth=0
  # Nesting depth of for/while/until/if/case bodies, and the operator that
  # opened the current segment ('' at the start, a control operator, or `ctl`
  # for a reserved-word boundary), whether the previous segment carried state,
  # and whether a `cd` has: together they decide where state may carry (fin).
  local ctl_depth=0 seg_open='' prev_commit=0 cd_live=0
  # 1 while the top-level and-or list since the last `;` or line break holds
  # an own-unit act: a trailing `&` would background the whole list.
  local ou_list=0
  # 1 once that list has passed a top-level `||`: an act after it is after `||`.
  local ou_or=0
  # 1 while the segment about to be read is piped: the last close was `|`,
  # with only line breaks (empty `;` segments) since.
  local ou_pipe=0
  # The VAR table's size when the current top-level and-or list began, so a
  # trailing `&` can drop what that list assigned, and whether the last `;`
  # was a newline continuing that list (fin).
  local list_var=$VAR_C list_cont=0
  # An own-unit act's chain partners (OU_PARTNER: a git add or commit the
  # policy approves, a trusted repository task) come before it, joined only
  # by `&&`. ou_chain: a partner was seen and its chain is still open;
  # ou_bad: one was seen anywhere else, or after an act (ou_seen), so no act
  # in this command is approved.
  local ou_chain=0 ou_bad=0 ou_seen=0
  # A lead `cd <own dir> &&` keeps SCOPED_CHAIN while each segment of its
  # chain passes the scoped read check (SEG_SCOPED), with the directory it
  # left in cd_pre: a later `;` or `||` then enters the scoped read mode.
  local SCOPED_CHAIN=0 SEG_SCOPED=0 cd_pre=''
  # Accumulators for the current simple command (dynamic scope: verify_simple
  # reads these): words, their literal-dollar, quote-start, expansion, glob,
  # zsh-option and mixed-quoting flags, substitution indexes, and the
  # redirects. Reset by fin().
  local -a cw=() cx=() cqp=() cdyn=() cglob=() cz=() cqm=() csub=() ro=() rt=() rtx=()
  local cwn=0 rn=0
  # The open `for` loops, innermost last: the loop variable's VAR slot, its
  # head words in LW, the word being verified, the first body token, and the
  # ctl/case depth inside the body, so the matching `done` is the one the walk
  # itself pairs with this `for`.
  local -a LF_VAR=() LF_START=() LF_COUNT=() LF_POS=() LF_BODY=() LF_DEPTH=() LF_CASE=()
  local lf_n=0

  # fin <closing-op>: finalize the current simple command (verify it), carry
  # the state it sets (a tracked assignment, a `cd`) when its placement allows,
  # and reset. Only called in normal / casebody accumulation modes. State
  # carries from a segment at the top level opened by nothing, `;`, or `&&`
  # straight after another state-carrying segment: anywhere else the segment
  # may run in a subshell or not at all, so the command defers. An assignment
  # always takes effect, so it may also close with `;` or `||`; a `cd` can fail,
  # so it must close with `&&` or end the command, and once one is carried,
  # every later top-level operator must keep the walk inside its `&&` chain
  # (`&&`, or `|`, which binds tighter), since after `;`, `||`, or `&` the
  # directory is no longer known. The one exception is the scoped read mode
  # (see scoped_read_ok): a first-segment `cd` to an absolute directory of the
  # worktree closed by `;`, or such a cd's `&&` chain of scoped reads closed
  # by `;` or `||`, enters it, and every later segment is checked from both
  # directories the line may then be in.
  fin() {
    local close=$1 placed=0 empty=0
    [ "$cwn" -gt 0 ] || [ "$rn" -gt 0 ] || empty=1
    PENDING_ASSIGN_N=''
    PENDING_ASSIGN_V=''
    PENDING_ASSIGN_O=0
    PENDING_ASSIGN_S=0
    PENDING_CD=''
    PENDING_OUT=0
    PENDING_OUT_DIR=''
    SEG_SCOPED=0
    OU_SEG=0
    OU_PARTNER=0
    verify_simple || return 1
    if [ "$close" = '|' ]; then
      ou_pipe=1
    elif [ "$empty" = 0 ] || [ "$close" != ';' ]; then
      ou_pipe=0
    fi
    [ "$OU_SEG" = 0 ] || ou_list=1
    if [ "$OU_PARTNER" = 1 ]; then
      if [ "$ctl_depth" -ne 0 ] || [ "$close" != '&&' ] || [ "$ou_seen" = 1 ] || [ "$ou_or" = 1 ]; then
        ou_bad=1
      fi
      case $seg_open in
        '' | ';' | '&&') ;;
        *) ou_bad=1 ;;
      esac
      ou_chain=1
    elif [ "$OU_SEG" = 0 ] && [ "$ou_chain" = 1 ] && [ "$ou_seen" = 0 ] && [ "$ctl_depth" -eq 0 ]; then
      # A segment between a partner and the act keeps the chain only by `&&`,
      # with no line break either.
      [ "$close" = '&&' ] && [ "$empty" = 0 ] || ou_bad=1
    fi
    if [ "$OU_SEG" = 1 ]; then
      ou_seen=1
      [ "$ou_bad" = 0 ] || return 1
    fi
    [ "$ou_seen" = 0 ] || [ "$ou_bad" = 0 ] || return 1
    if [ "$ctl_depth" -eq 0 ]; then
      [ "$close" != '&' ] || [ "$ou_list" = 0 ] || return 1
      # The tokenizer reads every line break as `;`, but one right after
      # `&&`, `||` or `|` (an empty segment) continues the list.
      case $close in
        end) ou_list=0 ou_or=0 ;;
        ';') [ "$empty" = 1 ] || ou_list=0 ou_or=0 ;;
        '||') ou_or=1 ;;
      esac
    fi
    [ "$SEG_SCOPED" = 1 ] || SCOPED_CHAIN=0
    # A `cd` outside the worktree is approved only as a top-level `cd X;`
    # step: the `&&` chain and every other placement keep deferring.
    if [ "$PENDING_OUT" = 1 ]; then
      [ "$ctl_depth" -eq 0 ] || return 1
      case $seg_open:$close in
        ':;' | ';:;')
          OUTSIDE_CD=1
          OUTSIDE_DIR=$PENDING_OUT_DIR
          ;;
        *) return 1 ;;
      esac
    fi
    if [ "$cd_live" = 1 ] && [ "$ctl_depth" -eq 0 ]; then
      case $close in
        '&&' | '|' | ctl | end) ;;
        ';' | '||')
          [ "$SCOPED_CHAIN" = 1 ] && scoped_alt_ok "$cd_pre" || return 1
          SCOPED_RD=1
          SCOPED_CHAIN=0
          cd_live=0
          ;;
        *) return 1 ;;
      esac
    fi
    # The scoped read mode's own entry. A relative cd keeps the `&&`-only
    # rule, and the cd itself may carry no redirect.
    if [ -n "$PENDING_CD" ] && [ "$ctl_depth" -eq 0 ] && [ -z "$seg_open" ] && [ "$close" = ';' ] \
      && [ "$rn" -eq 0 ] && is_abs "${cw[1]-}"; then
      scoped_alt_ok "$HOOK_CWD" || return 1
      SCOPED_RD=1
      HOOK_CWD=$PENDING_CD
      PENDING_CD=''
    fi
    if [ -n "$PENDING_ASSIGN_N" ] || [ -n "$PENDING_CD" ]; then
      if [ "$ctl_depth" -eq 0 ]; then
        case $seg_open in
          '' | ';') placed=1 ;;
          '&&') [ "$prev_commit" = 1 ] && placed=1 ;;
        esac
      fi
      if [ -n "$PENDING_CD" ]; then
        case $close in
          '&&' | end) ;;
          *) placed=0 ;;
        esac
      else
        case $close in
          ';' | '&&' | '||' | end) ;;
          *) placed=0 ;;
        esac
      fi
      [ "$placed" = 1 ] || return 1
      if [ -n "$PENDING_CD" ]; then
        if [ -z "$seg_open" ] && [ "$SCOPED_RD" = 0 ] && [ "$rn" -eq 0 ] && is_abs "${cw[1]-}"; then
          SCOPED_CHAIN=1
          cd_pre=$HOOK_CWD
        fi
        HOOK_CWD=$PENDING_CD
        cd_live=1
      else
        [ "$VAR_C" -lt "$MAX_TRACKED_VARS" ] || return 1
        VAR_N[VAR_C]=$PENDING_ASSIGN_N
        VAR_V[VAR_C]=$PENDING_ASSIGN_V
        VAR_L[VAR_C]=0
        VAR_O[VAR_C]=$PENDING_ASSIGN_O
        VAR_S[VAR_C]=$PENDING_ASSIGN_S
        VAR_C=$((VAR_C + 1))
      fi
      prev_commit=1
      # An assignment holding a substitution exits with its command's
      # status, so what follows its `&&` may not run.
      [ -z "${csub[0]-}" ] || prev_commit=0
    else
      prev_commit=0
    fi
    # A top-level `&` runs the whole and-or list since the last top-level `;`,
    # newline or `&` in a background subshell, not just its last command, so
    # nothing that list assigned reaches the commands after it. The tokenizer
    # reads a newline as `;`, and newlines straight after `&&`, `||` or `|`
    # continue the list instead of ending it.
    if [ "$ctl_depth" -eq 0 ]; then
      local cont=0
      if [ "$close" = ';' ] && [ "$empty" = 1 ]; then
        case $list_cont:$seg_open in
          1:';' | *:'&&' | *:'||' | *:'|') cont=1 ;;
        esac
      fi
      case $close in
        '&') VAR_C=$list_var ;;
        ';') [ "$cont" = 1 ] || list_var=$VAR_C ;;
      esac
      list_cont=$cont
    fi
    seg_open=$close
    cw=()
    cx=()
    cqp=()
    cdyn=()
    cglob=()
    cz=()
    cqm=()
    csub=()
    ro=()
    rt=()
    rtx=()
    cwn=0
    rn=0
    return 0
  }

  while [ "$idx" -lt "$TOK_N" ]; do
    typ=${TOK_TYPE[idx]}
    val=${TOK_VAL[idx]}

    # The case head and pattern words below are skipped unverified, so a
    # substitution there would run unanalysed.
    # Nor may they match on a credential, which leaks it a guess at a time.
    if [ "$mode" = casehead ] || [ "$mode" = casepat ]; then
      [ -z "${TOK_SUBS[idx]}" ] || return 1
      ! secret_var_ref "$val" || return 1
    fi
    # case head: skip the matched word up to `in`.
    if [ "$mode" = casehead ]; then
      if [ "$typ" = W ] && [ "$val" = "in" ]; then
        mode=casepat
      elif [ "$typ" = W ] && [ "$val" = "esac" ]; then
        case_depth=$((case_depth - 1))
        ctl_depth=$((ctl_depth - 1))
        mode=normal
      fi
      idx=$((idx + 1))
      continue
    fi
    # case pattern: skip pattern tokens up to the `)` that opens the body.
    if [ "$mode" = casepat ]; then
      if [ "$typ" = O ] && [ "$val" = ')' ]; then
        mode=casebody
      elif [ "$typ" = W ] && [ "$val" = "esac" ]; then
        case_depth=$((case_depth - 1))
        ctl_depth=$((ctl_depth - 1))
        mode=normal
      fi
      # `(` (optional leading pattern paren) and `|` (alternation) are skipped.
      idx=$((idx + 1))
      continue
    fi

    if [ "$typ" = O ]; then
      case $val in
        ';' | '&&' | '||' | '|' | '&')
          fin "$val" || return 1
          ;;
        ';;')
          if [ "$mode" = casebody ]; then
            fin ctl || return 1
            mode=casepat
          else
            return 1 # `;;` outside a case is malformed
          fi
          ;;
        '(')
          return 1 # subshell / fish bare-paren / arithmetic: defer (REQ-A1.9)
          ;;
        ')')
          return 1 # a `)` outside a case pattern is unbalanced: defer
          ;;
        *) return 1 ;;
      esac
      idx=$((idx + 1))
      continue
    fi

    if [ "$typ" = R ]; then
      # The operand is the next token and must be a word.
      local nxt=$((idx + 1))
      if [ "$nxt" -ge "$TOK_N" ] || [ "${TOK_TYPE[nxt]}" != W ]; then
        return 1 # dangling redirect operator
      fi
      # A quoted/escaped operand is never a bare fd-number or bare /dev/null, so
      # bash treats it as a real file target (`>&"1\2"` writes a file). Defer
      # rather than let classify_redirect mistake it for a safe fd-dup/null-write.
      [ "${TOK_QUOTED[nxt]}" = 1 ] && return 1
      [ -z "${TOK_SUBS[nxt]}" ] || return 1
      ro[rn]=$val
      rt[rn]=${TOK_VAL[nxt]}
      rtx[rn]=${TOK_NOEXP[nxt]}${TOK_GLOB[nxt]}
      rn=$((rn + 1))
      idx=$((idx + 2))
      continue
    fi

    # typ = W. A reserved word only in command position (no words accumulated
    # yet) is structural; otherwise it is an ordinary argument.
    if [ "$cwn" -eq 0 ] && is_reserved "$val"; then
      [ "$SCOPED_RD" = 0 ] || return 1
      case $val in
        for)
          # Verify the body once per head word, the loop variable substituted
          # (REQ-E1.1); `done` loops the walk back to the body for the next one.
          fin ctl || return 1
          loop_enter || return 1
          # A loop over a name an own-unit export set re-assigns it, as
          # track_assignment refuses for a plain assignment.
          if [ "$OU_EXPORTED" = 1 ]; then
            case $LH_NAME in
              PLANWRIGHT_STEP_*) return 1 ;;
            esac
          fi
          loop_fits || return 1
          continue
          ;;
        select)
          return 1 # its variable takes whatever the user types: not modelled
          ;;
        while | until | if)
          fin ctl || return 1
          ctl_depth=$((ctl_depth + 1))
          ;;
        then | elif | else | do)
          fin ctl || return 1 # boundary; regions on both sides are commands
          ;;
        fi)
          fin ctl || return 1
          ctl_depth=$((ctl_depth - 1))
          [ "$ctl_depth" -ge 0 ] || return 1 # a closer with no opener: defer
          ;;
        done)
          fin ctl || return 1
          ctl_depth=$((ctl_depth - 1))
          [ "$ctl_depth" -ge 0 ] || return 1 # a closer with no opener: defer
          loop_next
          case $? in
            0) continue ;;
            2) return 1 ;;
          esac
          ;;
        'case')
          fin ctl || return 1
          case_depth=$((case_depth + 1))
          ctl_depth=$((ctl_depth + 1))
          [ "$case_depth" -gt 1 ] && return 1 # nested case: defer
          mode=casehead
          ;;
        'esac')
          fin ctl || return 1
          case_depth=$((case_depth - 1))
          ctl_depth=$((ctl_depth - 1))
          [ "$ctl_depth" -ge 0 ] || return 1
          mode=normal
          ;;
        'in')
          return 1 # `in` with no enclosing for/case header: malformed
          ;;
      esac
      idx=$((idx + 1))
      continue
    fi

    # Ordinary word: append to the current simple command.
    cw[cwn]=$val
    cx[cwn]=${TOK_NOEXP[idx]}
    cqp[cwn]=${TOK_QPOS[idx]}
    cdyn[cwn]=${TOK_DYN[idx]}
    cglob[cwn]=${TOK_GLOB[idx]}
    cz[cwn]=${TOK_ZOPT[idx]}
    cqm[cwn]=${TOK_QMIX[idx]}
    csub[cwn]=${TOK_SUBS[idx]}
    cwn=$((cwn + 1))
    idx=$((idx + 1))
  done

  # Finalize the trailing simple command and require a clean end state.
  [ "$mode" = normal ] || return 1
  [ "$case_depth" -eq 0 ] || return 1
  [ "$ctl_depth" -eq 0 ] || return 1
  fin end || return 1
  return 0
}

# --------------------------------------------------------------------------
# analyze_command <command> <depth> [pipeline]: tokenize then verify. Returns
# 0 iff the whole command is known-safe. Depth bounds fish -c recursion
# (REQ-B1.3); `pipeline` admits only one simple command or pipeline (a
# substitution's inner text). TOK_* are declared local here so recursion
# (guard_fish or subst_inner_ok -> analyze_command) gets a fresh, shadowing
# token stream and never corrupts an outer walk.
analyze_command() {
  local cmd=$1 depth=$2 t seg lead
  [ "$depth" -le "$MAX_DEPTH" ] || return 1
  [ "${#cmd}" -le "$MAX_CMD_LEN" ] || return 1
  # The tokenizer screens each `$` against the rest of the command, so the
  # `$` are charged before it runs, not only when the words are walked.
  dollar_count "$cmd"
  SCANNED=$((SCANNED + ${#cmd} + DOLLAR_N * DOLLAR_COST))
  [ "$SCANNED" -le "$MAX_SCANNED" ] || return 1
  local -a TOK_TYPE=() TOK_VAL=() TOK_QUOTED=() TOK_NOEXP=() TOK_QPOS=() TOK_DYN=() TOK_GLOB=() TOK_ZOPT=() TOK_QMIX=() TOK_SUBS=()
  local TOK_N=0
  # The command substitutions' inner texts and the working directory each
  # last passed in (SUBST_OKD, `d:`-prefixed; a cd cannot move inside a loop
  # today, so no loop re-checks one in another directory yet);
  # subst_scan returns its results in SUBST_IDX / SUBST_END.
  local -a SUBST_TXT=() SUBST_OKD=()
  local SUBST_N=0 SUBST_IDX=0 SUBST_END=0
  local HOOK_DEPTH=$depth
  # The substitution table (tracked assignments and loop variables, VAR_L
  # marking the latter and VAR_O an opaque value; track_assignment /
  # loop_header / expand_word), fresh
  # per entry so a `fish -c` inner string never inherits the outer shell's,
  # and the loop head words it draws from.
  local -a VAR_N=() VAR_V=() VAR_L=() VAR_O=() VAR_S=() LW=()
  local VAR_C=0 LW_N=0
  local LH_NAME='' LH_START=0 LH_COUNT=0 LH_NEXT=0
  local PENDING_ASSIGN_N='' PENDING_ASSIGN_V='' PENDING_ASSIGN_O=0 PENDING_ASSIGN_S=0 PENDING_CD='' PREFIXED=0
  local OUTSIDE_CD=${OUTSIDE_CD:-0} PENDING_OUT=0 PENDING_OUT_DIR='' OUT_DIR=''
  local OUTSIDE_DIR=${OUTSIDE_DIR-}
  local SCOPED_RD=${SCOPED_RD:-0} SCOPED_ALT=${SCOPED_ALT:-}
  # Under the scratch arm, `$TMPDIR` is the recorded scratch root: the
  # launcher exported it, and assign_name_ok refuses re-pointing it. A
  # `fish -c` string is left to fish's own rules.
  if [ "$SC_ON" = 1 ] && [ "$depth" -eq 0 ]; then
    VAR_N[0]=TMPDIR
    VAR_V[0]=$REC_SCRATCH
    VAR_L[0]=0
    VAR_O[0]=0
    VAR_S[0]=0
    VAR_C=1
  fi
  tokenize "$cmd" || return 1
  # Each `|`-separated segment holds a command or a redirect, and its first
  # word is no reserved word: anything else is not a pipeline.
  if [ "${3-}" = pipeline ]; then
    seg=0 lead=1
    for ((t = 0; t < TOK_N; t++)); do
      case ${TOK_TYPE[t]} in
        O)
          [ "${TOK_VAL[t]}" = '|' ] && [ "$seg" = 1 ] || return 1
          seg=0 lead=1
          ;;
        R)
          seg=1
          t=$((t + 1))
          ;;
        *)
          [ "$lead" = 0 ] || ! is_reserved "${TOK_VAL[t]}" || return 1
          seg=1 lead=0
          ;;
      esac
    done
    [ "$seg" = 1 ] || return 1
  fi
  verify_tokens "$depth"
}

# --------------------------------------------------------------------------
# main: read the payload, extract the two fields with jq (degrade to defer when
# jq is absent), and auto-approve only a known-safe Bash command. Every exit is
# 0 with either the single allow object or empty stdout.
main() {
  local input tool cmd cwd sid

  # Bounded, defensive stdin read: cap the payload so a giant blob can never
  # make the hook spin (REQ-B1.7). Command substitution strips trailing
  # newlines, which JSON does not care about.
  input=$(head -c 2000000 2>/dev/null) || input=''
  [ -n "$input" ] || return 0

  # jq absent -> auto-approve nothing (REQ-B1.2). Never a hand-rolled parse.
  command -v jq >/dev/null 2>&1 || return 0

  # One jq read for every field, since the hook runs on every tool call: the
  # tool name, the command, the cwd's kind and value, and the deny block's
  # state and rules (deny_load), each NUL-terminated, or nothing, which
  # defers. Exactly one JSON document is read; anything else defers. Each
  # string field then gets the trailing-newline strip a command substitution
  # gives it, and the tool name and rules lose their NULs as they would.
  # Every non-Bash tool defers (REQ-A1.7).
  # The command must be a JSON string; a present-but-empty or non-string value
  # defers (REQ-B1.7).
  # A NUL byte defers too: the command substitution drops it, so the guard
  # would screen other text than the shell runs.
  # `cwd` gets the same type discipline as `command` (REQ-B1.7): ABSENT (or null)
  # is a supported shape and falls back to $PWD, but a PRESENT non-string value
  # (object, array, number, boolean) means the payload does not match the
  # documented PreToolUse contract, so the whole analysis defers rather than
  # containment-checking against whatever `jq -r` renders such a value as.
  # A NUL byte in cwd defers, as in the command.
  local cwdkind f
  local -a denyarg=()
  if [ -n "${HOOK_SELF_ROOT:-}" ]; then
    f=$HOOK_SELF_ROOT/config/worker-settings.json
    [ -f "$f" ] && [ -r "$f" ] && denyarg=(--slurpfile deny "$f")
  fi
  {
    IFS= read -r -d '' tool && IFS= read -r -d '' cmd \
      && IFS= read -r -d '' cwdkind && IFS= read -r -d '' cwd \
      && IFS= read -r -d '' DENY_SRC && IFS= read -r -d '' DENY_RULES \
      && IFS= read -r -d '' sid
  } < <(printf '%s' "$input" | jq -j -s ${denyarg[@]+"${denyarg[@]}"} '
    if length == 1 then .[0] else empty end
    | (.tool_name // "" | if type == "string" then explode | map(select(. != 0)) | implode else "" end) as $t
    | select((.tool_input.command | type) == "string" and (.tool_input.command | explode | any(. == 0) | not))
    | (if has("cwd") and .cwd != null then (if (.cwd | type) == "string" and (.cwd | explode | any(. == 0)) then "nul" else (.cwd | type) end) else "absent" end) as $k
    | ($ARGS.named.deny // null) as $d
    | (if $d == null then ["none", ""] else
        try ["ok", ([$d[] | .permissions.deny | if type == "array" then .[] | select(type == "string") else error("no deny array") end]
          | join("\n") | explode | map(select(. != 0)) | implode)]
        catch ["err", ""] end) as $r
    | $t, "\u0000", .tool_input.command, "\u0000", $k, "\u0000", (if $k == "string" then .cwd else "" end), "\u0000",
      $r[0], "\u0000", $r[1], "\u0000",
      (.session_id | if type == "string" and (explode | any(. == 0) | not) then . else "" end), "\u0000"
  ' 2>/dev/null) || return 0
  tool=${tool%"${tool##*[!$'\n']}"}
  [ "$tool" = Bash ] || return 0
  cmd=${cmd%"${cmd##*[!$'\n']}"}
  [ -n "$cmd" ] || return 0
  case $cwdkind in
    absent) cwd=$PWD ;;
    string)
      cwd=${cwd%"${cwd##*[!$'\n']}"}
      [ -n "$cwd" ] || cwd=$PWD
      ;;
    *) return 0 ;; # present but not a string: defer
  esac
  local HOOK_CWD=$cwd HOOK_PAYLOAD_CWD=$cwd HOOK_RAW_CMD=$cmd
  # The session's own worktree, which a `cd` may not leave: the record's
  # (cd_target_ok).
  local HOOK_WT_ROOT='' HOOK_WT_GIT=''
  local pcwd
  # The own-branch arm, when the record names it and the payload directory
  # lies inside the recorded worktree.
  OB_ON=0
  case " $REC_POLICY " in
    *" own-branch "*)
      if [ -n "$REC_UNIT" ] && [ -n "$REC_WT" ] && pcwd=$(cd "$cwd" 2>/dev/null && pwd -P); then
        case $pcwd/ in
          "$REC_WT"/*) OB_ON=1 ;;
        esac
      fi
      ;;
  esac
  SC_ON=0
  case " $REC_POLICY " in
    *" scratch "*) [ "$HOOK_TMPDIR_IS_SCRATCH" = 0 ] || SC_ON=1 ;;
  esac
  # Shared across `fish -c` recursion so nesting cannot multiply the bound.
  LOOP_PASSES=0
  SIMPLE_N=0
  # 1 while subst_inner_ok analyses a substitution's inner text.
  IN_SUBST=0
  AUDIT_OB=0
  AUDIT_SC=0
  COMMITTED_USED=0
  OB_TOUCH=0
  AUDIT_OU=0
  OU_EXPORTED=0
  OU_EXP_NAMES=''
  ARM_ACT=0
  SCANNED=0

  analyze_command "$cmd" 0 || return 0
  [ "$COMMITTED_USED" = 0 ] || [ "$OB_TOUCH" = 0 ] || return 0
  # An own-unit act shares its command only with a cd into the worktree,
  # read-only segments, a step-context export, an installed step script, and
  # the partners verify_tokens places before it (git add or commit, a gate
  # task): never with a file write, another git act or a spec-root write.
  [ "$AUDIT_OU" = 0 ] || [ "$ARM_ACT" = 0 ] || return 0
  audit_append "$cmd" "$sid"
  emit_allow
  return 0
}

# Newline / tab constants used by the tokenizer (kept out of the case patterns
# themselves, which cannot carry a literal newline portably).
NL=$'\n'
TAB=$'\t'

# The names the hook's OWN environment carries, captured once at load as
# `\nNAME\n…` for assign_name_ok's shadowing rule (see there). Exported names
# only: the hook's shell variables are its own implementation detail and say
# nothing about what the analyzed command would shadow. Never derived from the
# analyzed command.
HOOK_ENV_NAMES=$NL$(compgen -e)$NL

# The hook's own sibling root — the final, delivery-mode-agnostic arm of
# is_planwright_script's root chain (see there). Resolved ONCE at load, before
# any payload is read, and left empty when it cannot be resolved (in which case
# that arm simply never fires). Never derived from the analyzed command.
HOOK_SELF_ROOT=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P) || HOOK_SELF_ROOT=''
# The spec-root write zone (see in_spec_zone), read once at load from the
# dispatcher's hand-off: an absolute directory that canonicalizes and carries
# the root marker as a regular file, or else no zone. Never derived from the
# analyzed command.
spec_zone_load() {
  local v=${PLANWRIGHT_WORKER_SPEC_ROOT:-} c
  case $v in
    /?*) ;;
    *) return 0 ;;
  esac
  c=$(cd -P -- "$v" 2>/dev/null && pwd -P) || return 0
  [ "$c" != / ] || return 0
  [ -f "$c/planwright-spec-root.yml" ] && [ ! -L "$c/planwright-spec-root.yml" ] || return 0
  printf '%s' "$c"
}
SPEC_ZONE=$(spec_zone_load) || SPEC_ZONE=''
session_record_load
# The scratch arm resolves `$TMPDIR` to the recorded root, so it is live only
# while the TMPDIR this hook inherited, which is the session's, names that
# root: a sandbox, a settings env, or another launch's record would otherwise
# point the shell elsewhere. A relative TMPDIR resolves here from the hook's
# directory and there from the payload's, so only an absolute one counts. Nor
# do the guard's own temp files belong in a directory the worker may write to.
HOOK_TMPDIR_IS_SCRATCH=0
HOOK_TMP_BASE=/tmp
case ${TMPDIR:-} in
  /*)
    HOOK_TMP_BASE=$TMPDIR
    if [ -n "$REC_SCRATCH" ] && [ "$(cd -P -- "$TMPDIR" 2>/dev/null && pwd -P)" = "$REC_SCRATCH" ]; then
      HOOK_TMPDIR_IS_SCRATCH=1
      HOOK_TMP_BASE=/tmp
    fi
    ;;
esac
# plugin_root_unlinked <scripts-dir>: $CLAUDE_PLUGIN_ROOT, or nothing when
# resolve-installed-roots.sh's symlink rule refuses it (or cannot be run). The
# chain canonicalizes an arm, so a plugin cache root reached through a symlink
# would make wherever it points trusted.
plugin_root_unlinked() {
  local r=${CLAUDE_PLUGIN_ROOT:-}
  [ -n "$r" ] && [ -r "$1/resolve-installed-roots.sh" ] || return 0
  /bin/sh "$1/resolve-installed-roots.sh" --unlinked "$r" 2>/dev/null && printf '%s' "$r"
  return 0
}
# Arm 1: the core root chain, from the resolver shipped beside this hook. It
# runs only when a script path is actually checked, since most commands never
# need it and the hook runs on every tool call. Its warnings are dropped: a
# hook's stderr is not a channel anyone reads, and a skipped arm is simply not
# trusted.
chain_roots() {
  [ -n "$HOOK_SELF_ROOT" ] && [ -r "$HOOK_SELF_ROOT/scripts/resolve-root.sh" ] || return 0
  CLAUDE_PLUGIN_ROOT=$(plugin_root_unlinked "$HOOK_SELF_ROOT/scripts") /bin/sh "$HOOK_SELF_ROOT/scripts/resolve-root.sh" install --all 2>/dev/null || :
}

# Fail safe on any unexpected signal: empty stdout, exit 0 (REQ-B1.7). The hook
# never blocks a worker's tool call.
trap 'exit 0' HUP INT TERM PIPE
trap '[ -z "$DECL_PGID" ] || kill -KILL -- "-$DECL_PGID" 2>/dev/null; [ -z "$DECL_TMP" ] || rm -rf "$DECL_TMP"' EXIT

main
exit 0
