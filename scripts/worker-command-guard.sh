#!/usr/bin/env bash
# worker-command-guard.sh — deterministic PreToolUse auto-approve hook for
# dispatched planwright workers (worker-permission-ergonomics Task 1;
# REQ-A1.1..A1.10, REQ-B1.1..B1.7, D-1..D-4). Wired into
# config/worker-settings.json (Task 2), it reads a Claude Code PreToolUse
# payload on stdin and prints a `permissionDecision: allow` decision for an
# ENUMERATED set of known-safe, read-only Bash command shapes — silencing the
# permission-prompt flood on the shapes /execute-task actually issues (plugin
# scripts, `for`/`while` loops, read-only git/coreutil pipelines) — and DEFERS
# everything else to Claude Code's normal permission flow.
#
# Security contract (the whole point):
#   * No LLM in the decision path (REQ-A1.1); purely deterministic shell.
#   * Allow-only: it emits `allow` or nothing. It NEVER emits deny/ask and
#     NEVER exits non-zero — approval is upgrade-only; blocking stays with
#     permissions.deny/ask (REQ-A1.2, REQ-B1.7). A hook `allow` therefore never
#     needs to (and by design never does) auto-approve a deny-listed command:
#     the enumerated allowlist is read-only shapes with zero overlap with the
#     worker deny block, and the adversarial suite pins that (REQ-A1.3,
#     REQ-B1.6). A declared step's line is the exception: it is whatever an
#     operator declared, its trust resting on the declaring layer, not on the
#     deny block (see declared_line_ok).
#   * The extracted command is treated strictly as INERT DATA — never eval-ed,
#     re-expanded, glob-expanded, or used as a pattern/format/unquoted arg — so
#     analyzing a hostile command can never execute it (REQ-B1.1).
#   * One write class, live only when PLANWRIGHT_WORKER_SPEC_ROOT names a
#     marked spec root, which the dispatchers hand in only when it lies outside
#     the work repository (see in_spec_zone): a `>`/`>>` redirect, `tee
#     [-a]`, or `mkdir [-p]` whose every target is a plain literal inside a
#     bundle or reserved directory of that root. With no root handed in, or
#     for any other target, the read-only rule holds.
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
# it uses no construct the analyzer cannot confidently parse — command/process
# substitution, here-docs, subshell or brace grouping, env-assignment prefixes,
# path-prefixed verbs, escaped operators, ANSI-C quoting — all of which defer
# (REQ-A1.9). The expansions
# the analyzer resolves itself are a variable the same command assigned a
# literal, trusted-root path to (`P=/root && $P/scripts/x.sh`; see
# track_assignment and expand_word) and a `for` variable over plain-literal
# head words (see loop_header): the substitution reproduces what the shell
# will do for exactly those value classes and nothing else, and any other
# expansion left in a verb, or in an operand a screen reads, defers (see
# word_unresolved). Repo `scripts/*.sh`
# / `tests/*.sh` and `bats <file>` are trusted repo code but only after their
# path canonicalizes INSIDE the repository, and an INSTALLED planwright root's
# `scripts/*.sh` is trusted after canonicalizing inside a root the hook resolves
# for itself (REQ-A1.10; see is_planwright_script — the reason this needs no
# per-machine, version-pinned allow entry). `fish -c "<inner>"` recurses the same
# analysis on the inner string within a bounded depth.
# A segment none of these shapes approve is still approved when it is exactly
# a command step an operator declared (see declared_line_ok).
#
# Portable bash (3.2 floor / BSD compatible), no dependency on python, fish,
# mise, tmux, or Ansible; the security-critical analysis is pure shell. jq is
# used only to extract the two fields from the JSON payload; when jq is absent
# the hook degrades to deferring everything (REQ-B1.2), never a hand-rolled JSON
# parse and never a false-allow.
set -u
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
# the normal prompt). Because `fish -c "<inner>"` re-enters analyze_command on
# the inner string (each entry independently re-checked against MAX_CMD_LEN),
# the end-to-end worst case is that per-entry cost multiplied by the number of
# levels — up to MAX_DEPTH+1 entries, i.e. ~2 s worst case, not ~0.5 s, plus
# STEPS_DEADLINE when a segment reaches the declared-step fallback. 8 KiB is
# far above any real worker command shape. MAX_DEPTH caps `fish -c` recursion so
# a nested-`fish -c` bomb can never spin.
readonly MAX_CMD_LEN=8192
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

# The fixed reason string. It is NEVER a reflection of the analyzed command
# (REQ-B1.4): untrusted command content is never echoed to a terminal-driving
# stream.
readonly ALLOW_REASON='planwright worker-command-guard: enumerated known-safe read-only command shape (deterministic, no LLM)'

# emit_allow: write the single allow decision (the only thing this hook ever
# prints). Written as one final action after every check has passed, so there
# is never a partially-written allow (REQ-B1.7).
emit_allow() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"'"$ALLOW_REASON"'"}}'
}

# --------------------------------------------------------------------------
# Tokenizer (REQ-A1.4, REQ-A1.9). Scans the command as inert data into a token
# stream held in the caller's (analyze_command's) locals TOK_TYPE / TOK_VAL /
# TOK_N via dynamic scope. Token types: W (word), O (control/grouping operator:
# `;` `;;` `&&` `||` `|` `&` `(` `)`), R (redirect operator, possibly with an
# fd-number prefix). Returns non-zero (DEFER) the instant it meets a construct
# it will not analyze: unbalanced quotes, command/process substitution, backtick
# substitution, ANSI-C `$'…'`, a backslash line-continuation or escaped
# operator/quote. It never executes or expands anything it scans.
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
# (see word_unresolved).
tok_push() {
  TOK_TYPE[TOK_N]=$1
  TOK_VAL[TOK_N]=$2
  TOK_QUOTED[TOK_N]=${3:-0}
  TOK_NOEXP[TOK_N]=${4:-0}
  TOK_QPOS[TOK_N]=${5:--1}
  TOK_DYN[TOK_N]=${6:-0}
  TOK_GLOB[TOK_N]=${7:-0}
  TOK_N=$((TOK_N + 1))
}

# dollar_expands <next-char>: 0 when a `$` followed by <next-char> starts an
# expansion. A `$` before anything else (end of word, `/`, a space) is literal.
dollar_expands() {
  case $1 in
    [A-Za-z0-9_@*#?!-] | '{' | '$' | '[' | '"') return 0 ;;
  esac
  return 1
}

# dollar_form_ok <string> <index>: the `$` at <index> opens a form whose value
# the analyzer can reason about: not `$[…]` arithmetic, and a `${…}` only
# around a bare NAME. Any other brace form (`${a[i]}`, `${x:off}`, `${!n}`,
# `${#x}`, a modifier) evaluates text the hook never sees, an array subscript
# or offset arithmetically, so a value read at run time can run a command.
dollar_form_ok() {
  local s=$1 i=$2 j body
  case ${s:i+1:1} in
    '[') return 1 ;;
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
  esac
  return 0
}

tokenize() {
  local s=$1
  local n=${#s}
  local i=0
  local cur='' have=0 curq=0 curx=0 curqp=-1 curd=0 curg=0 brk=0 brc=0 brs=0
  local c nc j k dc dn fdpfx

  # _flush: push the accumulated word (if any) as a W token carrying its
  # quoting-provenance, literal-dollar, quote-start, expansion and glob flags,
  # then reset the accumulator.
  _flush() {
    if [ "$have" = 1 ]; then
      tok_push W "$cur" "$curq" "$curx" "$curqp" "$curd" "$curg"
      cur=''
      have=0
      curq=0
      curx=0
      curqp=-1
      curd=0
      curg=0
      brk=0
      brc=0
      brs=0
    fi
  }
  # _quoting: record where quoting first began in the current word.
  _quoting() {
    [ "$curq" = 1 ] || curqp=${#cur}
    curq=1
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
            k="$k$dn"
            j=$((j + 2))
            continue
          fi
          if [ "$dc" = '$' ]; then
            dn=${s:j+1:1}
            [ "$dn" = '(' ] && return 1 # $( command substitution
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
        [ "$nc" = '(' ] && return 1 # $( command substitution
        [ "$nc" = "'" ] && return 1 # $' ANSI-C quoting
        dollar_form_ok "$s" "$i" || return 1
        dollar_expands "$nc" && curd=2
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
        _flush
        nc=${s:i+1:1}
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
        if [ "$have" = 1 ]; then
          # A quoted digit run is a word (bash only reads an UNQUOTED digit run
          # as this redirect's fd number), so an fd prefix is bare digits only.
          case $cur in
            '' | *[!0-9]*) tok_push W "$cur" "$curq" "$curx" "$curqp" "$curd" "$curg" ;;
            *) [ "$curq" = 1 ] && tok_push W "$cur" "$curq" "$curx" "$curqp" "$curd" "$curg" || fdpfx=$cur ;;
          esac
          cur=''
          have=0
          curq=0
          curx=0
          curqp=-1
          curd=0
          curg=0
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
        case $c in
          '*' | '?') curg=1 ;;
          '[') brk=1 ;;
          ']') [ "$brk" = 1 ] && curg=1 ;;
          '{') brc=1 ;;
          ',') [ "$brc" = 1 ] && brs=1 ;;
          '.') [ "$brc" = 1 ] && [ "${s:i+1:1}" = . ] && brs=1 ;;
          '}') [ "$brs" = 1 ] && curg=1 ;;
          '~') [ "$have" = 0 ] && curg=1 ;;
        esac
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
# in a worktree). canon_contained canonicalizes a script/bats path (resolving
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

# canon_contained <path> <cwd>: canon_under against the repo root — prints the
# canonical path and returns 0 only when it resolves inside the repository;
# non-zero (DEFER) otherwise, including when the repo root cannot be resolved.
canon_contained() {
  local root
  root=$(repo_root_of "$2") || return 1
  canon_under "$1" "$2" "$root"
}

# is_repo_script <path> <cwd>: 0 when <path> is a `.sh` under a scripts/ or
# tests/ directory that canonicalizes inside the repo (REQ-A1.5, REQ-A1.10).
is_repo_script() {
  local p=$1 cwd=$2 full rel root
  case $p in
    *.sh) ;;
    *) return 1 ;;
  esac
  full=$(canon_contained "$p" "$cwd") || return 1
  root=$(repo_root_of "$cwd") || return 1
  rel=${full#"$root"/}
  case $rel in
    scripts/* | tests/* | */scripts/* | */tests/*) return 0 ;;
    *) return 1 ;;
  esac
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
# (REQ-B1.1); they are resolved once at load (INSTALLED_ROOTS below).
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
    printf '%s\n' "${INSTALLED_ROOTS:-}"
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
    rel=${full#"$root"/}
    case $rel in
      scripts/*) return 0 ;;
    esac
  done <<EOF
$PW_ROOTS
EOF
  return 1
}

# is_trusted_dir <canonical-dir> <cwd>: 0 when the directory is, or sits inside,
# the repo checkout or a resolved planwright root. Bounds what a tracked
# assignment may name (see track_assignment); the verb built from it is still
# verified by is_trusted_script afterwards.
is_trusted_dir() {
  local canon=$1 cwd=$2 root
  if root=$(repo_root_of "$cwd"); then
    case $canon in
      "$root" | "$root"/*) return 0 ;;
    esac
  fi
  cache_roots
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    case $canon in
      "$root" | "$root"/*) return 0 ;;
    esac
  done <<EOF
$PW_ROOTS
EOF
  return 1
}

# is_trusted_script <path> <cwd>: the trusted-script union — repo checkout code
# (scripts/ or tests/) or an installed planwright root's scripts/.
is_trusted_script() {
  is_repo_script "$1" "$2" || is_planwright_script "$1" "$2"
}

# is_contained_file <path> <cwd>: 0 when <path> canonicalizes inside the repo
# (used for `bats <file>`, which need not sit under scripts/ or tests/, and which
# stays REPO-scoped — an install ships no test files to run).
is_contained_file() {
  canon_contained "$1" "$2" >/dev/null
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
  [ -n "$SPEC_ZONE" ] || return 1
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

# guard_tee / guard_mkdir: at least one operand, every operand a zone path;
# the only flag `-a` (append) for tee and `-p` for mkdir, so no mode, context,
# or ignore flag changes what lands.
guard_tee() {
  local i a ends=0 operands=0
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
    in_spec_zone "$a" "$HOOK_CWD" || return 1
    operands=$((operands + 1))
  done
  [ "$operands" -ge 1 ]
}

guard_mkdir() {
  local i a ends=0 operands=0
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    if [ "$ends" = 0 ]; then
      case $a in
        -p | --parents) continue ;;
        --)
          ends=1
          continue
          ;;
        -*) return 1 ;;
      esac
    fi
    in_spec_zone "$a" "$HOOK_CWD" || return 1
    operands=$((operands + 1))
  done
  [ "$operands" -ge 1 ]
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
# operand, a `-e` value, or a `--expression=` value) must be read-only.
guard_sed() {
  local i a expect_e=0 script_taken=0
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    if [ "$expect_e" = 1 ]; then
      sed_script_safe "$a" || return 1
      expect_e=0
      script_taken=1
      continue
    fi
    case $a in
      -e) expect_e=1 ;;
      --expression=*)
        sed_script_safe "${a#--expression=}" || return 1
        script_taken=1
        ;;
      -n | -E | -r | -s | -z | -u | --posix | --quiet | --silent | --regexp-extended | --separate | --null-data | --unbuffered | --debug | --sandbox | --help | --version | --) ;;
      -*) return 1 ;; # -i / -f / -l / bundled / unknown: defer
      *)
        if [ "$script_taken" = 0 ]; then
          sed_script_safe "$a" || return 1
          script_taken=1
        fi
        ;;
    esac
  done
  [ "$expect_e" = 1 ] && return 1
  return 0
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
          awk_program_safe "$a" || return 1
          prog_taken=1
        fi
        ;;
    esac
  done
  [ "$expect" = none ] || return 1  # a dangling value-flag with no value: defer
  [ "$prog_taken" = 1 ] || return 1 # no inline program (the -f form): defer
  return 0
}

# jq_program_safe <program>: 0 only when a jq filter is provably free of an
# ENVIRONMENT read. jq's language has no exec and no file-write primitive at
# all, so nothing else in a filter needs screening; what it does have is `env`
# and `$ENV`, either of which hands the whole environment to the filter (and
# from there to the transcript). That is the same call guard_awk makes on
# `ENVIRON`, and for the same reason: the guard can see the read but not what
# the program does with the value.
#
# `$ENV` rejects wherever it appears. `env` rejects only as a WORD — a `.env`
# or `.a.env` is a FIELD ACCESS on the input, not the builtin, and a `$env` is
# someone's own variable, so a preceding `.` or `$` (or an identifier
# character, as in `envelope`) leaves it alone. A mention the rule cannot place
# that way, `"env"` inside a string included, defers; that costs the filter
# shapes nothing.
jq_program_safe() {
  local s=$1
  local n=${#s} i=0 p a
  case $s in
    *\$ENV*) return 1 ;;
  esac
  while [ "$i" -lt "$n" ]; do
    if [ "${s:i:3}" = env ]; then
      p=''
      [ "$i" -gt 0 ] && p=${s:i-1:1}
      a=${s:i+3:1}
      case $p in
        [A-Za-z0-9_.$]) ;; # a field access, a variable, or a longer name
        *)
          case $a in
            [A-Za-z0-9_]) ;; # a longer name: `envelope`, `env_of`
            *) return 1 ;;   # the builtin
          esac
          ;;
      esac
    fi
    i=$((i + 1))
  done
  return 0
}

# guard_jq: strict flag allowlist plus the environment-read check on the
# filter. Only the inline-filter form is verifiable, so `-f`/`--from-file` (a
# filter in a file) and `-L`/`--library-path` (which is where `include` and
# `import` read module text from) defer, as does any unrecognized flag.
#
# Every value-taking flag is enumerated because the filter is identified BY
# POSITION — it is the first non-flag operand — and a value sitting in that
# position would be screened in its place: without this, `jq --indent 4 '$ENV'`
# would screen `4` and hand `$ENV` through as if it were a filename. Operands
# after the filter are input files, or positional arguments under
# `--args`/`--jsonargs`, and jq only ever READS those.
guard_jq() {
  local i a t c expect=0 prog_taken=0 endflags=0
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
      jq_program_safe "$a" || return 1
      prog_taken=1
    fi
  done
  [ "$expect" = 0 ] || return 1     # a dangling value-flag with no value
  [ "$prog_taken" = 1 ] || return 1 # no inline filter (the -f form, or none)
  return 0
}

# guard_env: bare `env` only. With NO operand, env prints the environment and
# runs nothing; with one, it is an EXEC vector (`env VAR=x cmd`, `env -i cmd`,
# `env -S '…'`), and since `-u`/`-C`/`-S` take values, "is this operand a
# command" cannot be decided from the token shape alone. Requiring the bare form
# sidesteps that entirely.
#
# Printing the environment exposes whatever secrets the worker's environment
# carries, but it opens no new class: `echo` is already unguarded on this list,
# so `echo $GH_TOKEN` is already approved. The awk screen's separate `ENVIRON`
# reject is NOT the same call — there the environment read sits inside program
# text whose use of the value the guard cannot see at all.
guard_env() {
  [ "$cwn" -eq 1 ]
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
# yq_expression_safe <expr>: 0 unless the expression reads the environment.
# yq's `env(NAME)` and `strenv(NAME)` are the same capability the awk `ENVIRON`
# reject and jq_program_safe's `env` check exist for — program text whose use
# of the value this guard cannot see — so the third member of that family is
# screened the same way rather than left as the one open door.
yq_expression_safe() {
  local s=$1 n i p a
  case $s in
    *strenv*) return 1 ;;
  esac
  # `env` is a bare operator, not only a call: `env | .PATH` and `.a = env`
  # both read the environment. Walk it as a token so a longer identifier
  # (`.environment`, `envelope`) still passes, mirroring jq_program_safe.
  # Raised by the Copilot pass, 2026-09-15.
  n=${#s}
  i=0
  while [ "$i" -lt "$n" ]; do
    if [ "${s:i:3}" = env ]; then
      p=''
      [ "$i" -gt 0 ] && p=${s:i-1:1}
      a=${s:i+3:1}
      case $p in
        [A-Za-z0-9_.\$]) ;; # a field access, a variable, or a longer name
        *)
          case $a in
            [A-Za-z0-9_]) ;; # a longer name: `environment`, `envelope`
            *) return 1 ;;   # the operator
          esac
          ;;
      esac
    fi
    i=$((i + 1))
  done
  return 0
}

guard_yq() {
  local i a expr_taken=0
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      --) break ;; # end of flags: what follows is an expression or a file
      --inplace | --inplace=* | --in-place | --in-place=* | --split-exp | --split-exp=*) return 1 ;;
      --from-file | --from-file=*) return 1 ;; # an expression this screen cannot read
      --*) ;;
      -?*) short_flag_hit "$a" 'is' '' && return 1 ;;
      *)
        # The first non-flag operand is the expression; later ones are files.
        if [ "$expr_taken" = 0 ]; then
          yq_expression_safe "$a" || return 1
          expr_taken=1
        fi
        ;;
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

guard_mdlint() {
  local i a
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      --fix | -f | --output | --output=* | -o) return 1 ;;
    esac
  done
  return 0
}

guard_bashsh() {
  # Only `bash <trusted-script> [args]` / `sh <trusted-script> [args]` — repo
  # code or an installed planwright root's scripts/; any option (notably -c /
  # -ec) defers (REQ-A1.5, REQ-A1.9).
  [ "$cwn" -ge 2 ] || return 1
  case ${cw[1]} in
    -*) return 1 ;;
  esac
  is_trusted_script "${cw[1]}" "$HOOK_CWD"
}

guard_fish() {
  # Only `fish -c "<inner>"`; recurse the same analysis on the inner string
  # within the depth bound (REQ-A1.5, REQ-B1.3).
  [ "$cwn" -ge 3 ] || return 1
  [ "${cw[1]}" = '-c' ] || return 1
  analyze_command "${cw[2]}" "$((HOOK_DEPTH + 1))"
}

guard_bats() {
  # `bats [safe-flags] <file...>`: each file operand must resolve inside the
  # repo (REQ-A1.10), and ONLY no-value display/selection flags are allowed.
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
      # `run` is an alias of `mise run` (so it can carry the `--shell`
      # interpreter override, REQ-A1.6). Enumerate the read-only leaves, route
      # `run` through the shell-override guard below, and defer edit/add/unknown.
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
        run) i=$j ;; # fall through to the shell-override guard on the run args
        *) return 1 ;;
      esac
      ;;
    run) ;; # fall through to the shell-override guard below
    *) return 1 ;;
  esac
  # `mise run --shell/-s '<cmd>'` overrides the interpreter, turning the trusted
  # repo-task runner into an arbitrary-command runner (REQ-A1.6). Defer any
  # short-flag token carrying `s` (`-s`, `-ns`, …) or the long `--shell` form.
  for (( ; i < cwn; i++)); do
    case ${cw[i]} in
      --shell | --shell=*) return 1 ;;
      -[!-]*s* | -s*) return 1 ;;
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
      --web) return 1 ;;
      --*) ;;
      -?*) short_flag_hit "${cw[i]}" 'w' 'Hqpt' && return 1 ;;
    esac
  done
  return 0
}

guard_gh() {
  # REQ-A1.5: read-only gh only. A leading flag, or any non-enumerated group/sub
  # pair, defers.
  case ${cw[1]-} in
    -*) return 1 ;;
  esac
  local i g=${cw[1]-} s=${cw[2]-}
  case $g in
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
      for ((i = 2; i < cwn; i++)); do
        case ${cw[i]} in
          --) break ;; # end of flags: what follows is the endpoint
          --method | --method=* | --field | --field=* | --raw-field | --raw-field=*) return 1 ;;
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
    auth)
      [ "$s" = status ] && return 0 || return 1
      ;;
    repo)
      [ "$s" = view ] && return 0 || return 1
      ;;
    *) return 1 ;;
  esac
}

# git: read-only subcommands only, no pre-subcommand global option (which can
# inject config/alias-driven execution, REQ-A1.8), and per-subcommand form
# guards on the subcommands with a mutating twin (REQ-A1.5).
guard_git() {
  local i a sub='' subidx=0
  for ((i = 1; i < cwn; i++)); do
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
  case $sub in
    log | show | diff | status | rev-parse | cat-file | ls-files | ls-tree | for-each-ref | describe | blame | shortlog | rev-list | name-rev | whatchanged | grep | merge-base | show-ref | cherry | var)
      # Read-only, but reject a following flag that WRITES a file
      # (`git diff --output=FILE`) or SPAWNS a command: `git grep -O<cmd>` /
      # `--open-files-in-pager=<cmd>` run <cmd> through the shell, and
      # `--ext-diff` / `--textconv` / `--filters` (git cat-file) run a
      # configured driver (external-diff, textconv, or smudge/clean filter).
      for ((i = subidx + 1; i < cwn; i++)); do
        case ${cw[i]} in
          -o | --output | --output=* | --output-directory | --output-directory=*) return 1 ;;
          -O | -O* | --open-files-in-pager | --open-files-in-pager=*) return 1 ;;
          --ext-diff | --textconv | --filters) return 1 ;;
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
      local writes=0 positional=0 read_flag=0
      for ((i = subidx + 1; i < cwn; i++)); do
        a=${cw[i]}
        case $a in
          --get | --get-all | --get-regexp | --get-urlmatch | --list | -l | --get-color | --get-colorbool | --name-only) read_flag=1 ;;
          --add | --unset | --unset-all | --replace-all | --rename-section | --remove-section | -e | --edit | --set) writes=1 ;;
          -*) ;; # scope/format flags (--global/--type/…) are read-safe
          *) positional=$((positional + 1)) ;;
        esac
      done
      [ "$writes" = 1 ] && return 1
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
      # Only the read-only subcommands; bare `git stash` PUSHES, so it defers.
      case ${cw[subidx + 1]-} in
        list | show) return 0 ;;
        *) return 1 ;;
      esac
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
      # `git reflog` / `reflog show` / `reflog exists` READ; `expire`/`delete`
      # destroy recovery data.
      case ${cw[subidx + 1]-} in
        '' | show | exists) return 0 ;;
        *) return 1 ;;
      esac
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
    *) return 1 ;;
  esac
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
# resolves (loop variables are the other; see loop_header).
#
# Claude Code hands the hook the raw command, so `P=<root> && $P/scripts/x.sh`
# — the shape a worker produces when it abbreviates the resolved root the
# doctrine step tells it to call scripts under — reaches the verifier with `$P`
# unexpanded, and a verb carrying `$` can never canonicalize. Rather than defer
# the shape the hook exists to approve, the verifier tracks a standalone
# assignment and substitutes it into later words, under bounds that keep the
# substitution IDENTICAL to what the shell will do:
#   * the value is a bare absolute path of [A-Za-z0-9/._-] only — no `$`, glob
#     character, tilde, whitespace, or quote residue — so expanding it yields
#     exactly that string, with no word splitting and no globbing;
#   * the value canonicalizes to, or inside, a trusted root (the repo checkout
#     or a resolved planwright root), so whatever the variable later names is
#     already code the hook trusts, and the verb built from it still goes
#     through is_trusted_script;
#   * the NAME is a plain identifier, is not present in the hook's own
#     environment (an exported variable reaches every child the command runs:
#     PATH, LD_*, GIT_*, anything the operator exported), and is not a name the
#     shell itself consumes unexported (IFS, CDPATH, the BASH_* family, PS4...);
#   * the name and the `=` are unquoted (a quoted value is fine: quote removal
#     already happened and the charset rule applies to what is left), and the
#     word is the WHOLE simple command — an assignment PREFIX before a verb
#     still defers (REQ-A1.9);
#   * the assignment is unconditional and at the top level of the command:
#     opened by nothing, by `;`, or by `&&` directly after another tracked
#     assignment; closed by `;`, `&&`, `||` or the end. A `|` or `&` on either
#     side runs it in a subshell and a `&&`/`||` after a real command makes it
#     conditional; a loop/if/case body may not run at all. In every one of those
#     the variable can be unset for what follows, so nothing is tracked (the
#     segment itself is still harmless and passes; only the substitution is
#     withheld).
# A word carrying a literal `$` (single quotes, backslash) is never substituted,
# an unknown `$NAME` is left in place (the verb then defers as before), and the
# table is per analyze_command entry, so a `fish -c` inner string starts empty.

# assign_name_ok <name>: the NAME rule above.
assign_name_ok() {
  local name=$1
  case $name in
    '' | *[!A-Za-z0-9_]* | [0-9]*) return 1 ;;
  esac
  case $name in
    IFS | PATH | CDPATH | HOME | ENV | BASH_ENV | SHELL | PWD | OLDPWD | TMPDIR | TMOUT | \
      GLOBIGNORE | EXECIGNORE | FIGNORE | PROMPT_COMMAND | POSIXLY_CORRECT | FUNCNEST | \
      HOSTFILE | INPUTRC | IGNOREEOF | TIMEFORMAT | histchars | auto_resume | \
      OPTIND | OPTARG | OPTERR | LANG | LANGUAGE | _ | \
      BASH* | COMP_* | READLINE_* | HIST* | LC_* | MAIL* | PS[0-9]*) return 1 ;;
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

# assign_value_ok <value> <cwd>: the VALUE rule above.
assign_value_ok() {
  local v=$1 cwd=$2 canon
  bare_abs_path_ok "$v" || return 1
  canon=$(cd "$v" 2>/dev/null && pwd -P) || return 1
  is_trusted_dir "$canon" "$cwd"
}

# track_assignment <word> <quote-start> : 0 when the word is a standalone
# assignment the rules admit, leaving its halves in PENDING_ASSIGN_N / _V for
# verify_tokens to commit once it knows the segment was unconditional.
track_assignment() {
  local w=$1 qpos=$2 name value eqpos v
  case $w in
    [A-Za-z_]*=*) ;;
    *) return 1 ;;
  esac
  name=${w%%=*}
  value=${w#*=}
  eqpos=${#name}
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
  assign_value_ok "$value" "$HOOK_CWD" || return 1
  PENDING_ASSIGN_N=$name
  PENDING_ASSIGN_V=$value
  return 0
}

# expand_word <word>: substitute every `$NAME` / `${NAME}` whose NAME the
# table holds (latest assignment wins, as in the shell); any other `$` — an
# unknown name, a `${NAME:-...}` modifier, a bare `$` — is left in place so the
# word still defers downstream. Leaves the result in EXPANDED (a global, so
# the caller needs no command substitution, which forks once per word).
expand_word() {
  local w=$1
  local out='' i=0 n=${#w} c name j k found v
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
    fi
    found=''
    case $name in
      '' | *[!A-Za-z0-9_]*) ;;
      *)
        for ((v = VAR_C - 1; v >= 0; v--)); do
          if [ "${VAR_N[v]}" = "$name" ]; then
            found=${VAR_V[v]}
            break
          fi
        done
        ;;
    esac
    if [ -n "$found" ]; then
      out="$out$found"
      i=$k
    else
      out="$out$c"
      i=$((i + 1))
    fi
  done
  EXPANDED=$out
}

# --------------------------------------------------------------------------
# Words whose value is not their text. The hook sees the command unexpanded, so
# a word carrying an expansion the analyzer did not resolve (an unknown or
# special `$` parameter, a `${…}` modifier, a glob, a brace expansion, a leading
# tilde) can hold any value at run time: `find . $_` after a printf of
# `-exec id ;` runs id. Such a word may only reach a verb whose approval does
# not read that word (arg_independent_verb); anywhere else, and always in the
# verb position, it defers.

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
# so an opaque operand is equivalent to some literal they already approve.
# printf qualifies past its format only (guard_printf).
arg_independent_verb() {
  case $1 in
    cat | head | tail | wc | cut | comm | cmp | basename | dirname | realpath | pwd | echo | seq | true | false | od | tr | stat | grep | ls | diff) return 0 ;;
    printenv | readlink | nl | paste | column | md5sum | sha1sum | sha256sum | sha512sum | cksum | shellcheck | yamllint) return 0 ;;
  esac
  return 1
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

# guard_printf: `printf -v NAME` assigns a variable (PATH included) and
# evaluates a subscript in NAME the way `test -v` does; bash also takes the
# bundled `-vNAME`. A first word that is any option other than `--` defers.
guard_printf() {
  [ "${cw[1]-}" = -- ] && return 0
  case ${cw[1]-} in
    -*) return 1 ;;
  esac
  return 0
}

# opaque_words_ok: the current simple command (`cw` and its flag arrays, by
# dynamic scope) places every unresolved word where its value cannot change
# the verdict: never the verb, and otherwise only an operand of an
# argument-independent verb, printf past its format, or a test shape
# test_opaque_ok admits.
opaque_words_ok() {
  local i verb=${cw[0]} fmt=1
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
    # checksum family report to stdout with no output-file or filter flag, and
    # `printenv` exposes no more than the already-approved `echo $VAR`. `jq` is
    # NOT here: it passes the same write/exec test — its language has no exec
    # and no file-write primitive, and `-f`, `--rawfile`, `--slurpfile` and
    # `-L` only ever READ — but it carries PROGRAM TEXT, and a jq program can
    # read the environment (`env`, `$ENV`). Leaving it unscreened allowed
    # `jq -n env` while `awk 'BEGIN{print ENVIRON["X"]}'` deferred, which is
    # the same read through a different tool. It is guarded below.
    printenv | readlink | nl | paste | column | md5sum | sha1sum | sha256sum | sha512sum | cksum)
      return 0
      ;;
    # Read-only analyzers (results to stdout only).
    shellcheck | yamllint) return 0 ;;
    # Read-only tools with a specific write/set/output vector: guarded.
    sort) guard_sort ;;
    uniq) guard_uniq ;;
    date) guard_date ;;
    file) guard_file ;;
    find) guard_find ;;
    sed) guard_sed ;;
    awk) guard_awk ;;
    jq) guard_jq ;;
    markdownlint | markdownlint-cli2) guard_mdlint ;;
    env) guard_env ;;
    read) guard_read ;;
    yq) guard_yq ;;
    shfmt) guard_shfmt ;;
    rg) guard_rg ;;
    fd) guard_fd ;;
    # Enumerated read-only subcommand tools.
    git) guard_git ;;
    gh) guard_gh ;;
    mise) guard_mise ;;
    lefthook) guard_lefthook ;;
    # Writers, approved only inside the spec-root write zone.
    tee) guard_tee ;;
    mkdir) guard_mkdir ;;
    # Trusted repo-code runners (path-contained) and the fish recursor.
    bash | sh) guard_bashsh ;;
    fish) guard_fish ;;
    bats) guard_bats ;;
    *) return 1 ;; # fallthrough is DEFER, by construction (REQ-B1.6)
  esac
}

# --------------------------------------------------------------------------
# Declared command steps (custom-steps REQ-G1.2, REQ-G1.3). A segment no rule
# above approved is still approved when its words equal a command step an
# operator declared at a named point: the step's location exactly as
# scripts/resolve-steps.sh prints it on this host, then its args as written,
# after any leading context assignments in the runner's form. The declaration
# carries the trust (its overlay layer is human-owned, and the repo-tracked
# and machine-local layers inherit the trust already given to the repo's
# scripts/), so the match is exact: a segment sharing only the first word, a
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
readonly STEP_CONTEXT_FIELDS='SPEC TASK_IDS UNIT_KIND BRANCH BASE_BRANCH WORKTREE PR_NUMBER POINT ID PREV_RECORD'

# step_context_value_ok <field> <value>: a value the resolver would render,
# refusing what it refuses (a control byte; a unit kind, task ids, or PR number
# outside their grammar; a point outside the wired ones) plus any `$`.
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
# line per declared command step that resolves to `run`, when <location>'s
# file name is cataloged, by one multi-point resolver run from HOOK_CWD. Runs
# once per hook call: a miss defers its segment, which ends the analysis. The
# check and the run share one job in its own process group, bounded by
# STEPS_DEADLINE and killed whole when it overruns or once it ends, so nothing
# it started outlives the call.
resolve_declared() {
  local rs deadline ticks pid killed=0
  local dec target kind args loc key w _
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
  DECL_TMP=$(mktemp -d "${TMPDIR:-/tmp}/planwright-guard.XXXXXX" 2>/dev/null) || {
    DECL_TMP=''
    return 0
  }
  # Job control gives the job its own process group; the resolver's scratch
  # files land under DECL_TMP, which the EXIT trap removes.
  set -m
  (
    cd "$HOOK_CWD" 2>/dev/null || exit 0
    step_name_cataloged "${1##*/}" || exit 0
    # shellcheck disable=SC2086 # the wired points are meant to word-split
    TMPDIR=$DECL_TMP exec /bin/bash "$rs" $STEP_POINTS --explain --unattended
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
  while IFS=$TAB read -r dec _ _ _ _ target _ kind args _ _ _ loc; do
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
    DECL_LINES="$DECL_LINES$key$NL"
  done <"$DECL_TMP/out"
  return 0
}

# declared_line_ok: 0 when the current simple command, as tokenized (`sw` /
# `swq` / `swn` from verify_simple, before any tracked-assignment
# substitution), is a declared step's line. Reads `rn` via dynamic scope.
declared_line_ok() {
  local i=0 i0 f w name key
  [ "$rn" -eq 0 ] || return 1
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
  case $NL$DECL_LINES in
    *"$NL$key$NL"*) return 0 ;;
  esac
  return 1
}

# verify_simple: verify one simple command — known-safe by the rules below, or
# else a declared step's line. Reads the accumulated word array `cw` (0=verb)
# / count `cwn` and the redirect arrays `ro` (ops) / `rt` (targets) / `rn`
# from the caller via dynamic scope. Returns 0 (safe) or non-zero (DEFER).
verify_simple() {
  local i swn=$cwn
  SIMPLE_N=$((SIMPLE_N + 1))
  [ "$SIMPLE_N" -le "$MAX_SIMPLE_CMDS" ] || return 1
  local -a sw=() swq=()
  for ((i = 0; i < cwn; i++)); do
    sw[i]=${cw[i]}
    swq[i]=${cqp[i]}
  done
  verify_known_simple && return 0
  declared_line_ok
}

# verify_known_simple: the enumerated known-safe rules for one simple command.
verify_known_simple() {
  local i verb
  # Redirects first: a write to a real file defers regardless of the verb,
  # unless its target is in the spec-root write zone (covers a leading
  # redirect with no command too, e.g. `> f cat x`).
  for ((i = 0; i < rn; i++)); do
    classify_redirect "${ro[i]}" "${rt[i]}" || spec_zone_redirect "${ro[i]}" "${rt[i]}" || return 1
  done
  # A command with redirects but no words (pure `> file`) already handled;
  # an empty simple command (e.g. a trailing separator) is a no-op.
  [ "$cwn" -ge 1 ] || return 0
  # Resolve the tracked assignments into this command's words first, so a verb
  # or script path written through `$ROOT` is verified as the literal path the
  # shell will run. Words carrying a literal `$` are left alone.
  if [ "$VAR_C" -gt 0 ]; then
    for ((i = 0; i < cwn; i++)); do
      case ${cw[i]} in
        *'$'*) [ "${cx[i]}" = 0 ] && expand_word "${cw[i]}" && cw[i]=$EXPANDED ;;
      esac
    done
  fi
  verb=${cw[0]}
  # A standalone assignment (the whole simple command is one `NAME=value`
  # word) that the tracking rules admit runs nothing and is recorded for the
  # words that follow; whether it is committed is verify_tokens' call.
  if [ "$cwn" -eq 1 ] && track_assignment "$verb" "${cqp[0]}"; then
    return 0
  fi
  opaque_words_ok || return 1
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
      is_trusted_script "$verb" "$HOOK_CWD" && return 0
      return 1
      ;;
  esac
  classify_verb "$verb"
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
  # for a reserved-word boundary): together they decide whether a tracked
  # assignment was unconditional (see track_assignment).
  local ctl_depth=0 seg_open='' prev_commit=0
  # Accumulators for the current simple command (dynamic scope: verify_simple
  # reads these): words, their literal-dollar, quote-start, expansion and glob
  # flags, and the redirects. Reset by fin().
  local -a cw=() cx=() cqp=() cdyn=() cglob=() ro=() rt=()
  local cwn=0 rn=0
  # The open `for` loops, innermost last: the loop variable's VAR slot, its
  # head words in LW, the word being verified, the first body token, and the
  # ctl/case depth inside the body, so the matching `done` is the one the walk
  # itself pairs with this `for`.
  local -a LF_VAR=() LF_START=() LF_COUNT=() LF_POS=() LF_BODY=() LF_DEPTH=() LF_CASE=()
  local lf_n=0

  # fin <closing-op>: finalize the current simple command (verify it), commit a
  # tracked assignment when its segment was unconditional and top-level, and
  # reset. Only called in normal / casebody accumulation modes.
  fin() {
    local close=$1 ok=0
    PENDING_ASSIGN_N=''
    PENDING_ASSIGN_V=''
    verify_simple || return 1
    if [ -n "$PENDING_ASSIGN_N" ] && [ "$ctl_depth" -eq 0 ]; then
      case $seg_open in
        '' | ';') ok=1 ;;
        '&&') [ "$prev_commit" = 1 ] && ok=1 ;;
      esac
      case $close in
        ';' | '&&' | '||' | end) ;;
        *) ok=0 ;;
      esac
    fi
    if [ "$ok" = 1 ]; then
      VAR_N[VAR_C]=$PENDING_ASSIGN_N
      VAR_V[VAR_C]=$PENDING_ASSIGN_V
      VAR_L[VAR_C]=0
      VAR_C=$((VAR_C + 1))
      prev_commit=1
    else
      prev_commit=0
    fi
    seg_open=$close
    cw=()
    cx=()
    cqp=()
    cdyn=()
    cglob=()
    ro=()
    rt=()
    cwn=0
    rn=0
    return 0
  }

  while [ "$idx" -lt "$TOK_N" ]; do
    typ=${TOK_TYPE[idx]}
    val=${TOK_VAL[idx]}

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
      ro[rn]=$val
      rt[rn]=${TOK_VAL[nxt]}
      rn=$((rn + 1))
      idx=$((idx + 2))
      continue
    fi

    # typ = W. A reserved word only in command position (no words accumulated
    # yet) is structural; otherwise it is an ordinary argument.
    if [ "$cwn" -eq 0 ] && is_reserved "$val"; then
      case $val in
        for)
          # Verify the body once per head word, the loop variable substituted
          # (REQ-E1.1); `done` loops the walk back to the body for the next one.
          fin ctl || return 1
          loop_enter || return 1
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
# analyze_command <command> <depth>: tokenize then verify. Returns 0 iff the
# whole command is known-safe. Depth bounds fish -c recursion (REQ-B1.3).
# TOK_* are declared local here so recursion (guard_fish -> analyze_command)
# gets a fresh, shadowing token stream and never corrupts an outer walk.
analyze_command() {
  local cmd=$1 depth=$2
  [ "$depth" -le "$MAX_DEPTH" ] || return 1
  [ "${#cmd}" -le "$MAX_CMD_LEN" ] || return 1
  local -a TOK_TYPE=() TOK_VAL=() TOK_QUOTED=() TOK_NOEXP=() TOK_QPOS=() TOK_DYN=() TOK_GLOB=()
  local TOK_N=0
  local HOOK_DEPTH=$depth
  # The substitution table (tracked assignments and loop variables, VAR_L
  # marking the latter; track_assignment / loop_header / expand_word), fresh
  # per entry so a `fish -c` inner string never inherits the outer shell's,
  # and the loop head words it draws from.
  local -a VAR_N=() VAR_V=() VAR_L=() LW=()
  local VAR_C=0 LW_N=0
  local LH_NAME='' LH_START=0 LH_COUNT=0 LH_NEXT=0
  local PENDING_ASSIGN_N='' PENDING_ASSIGN_V=''
  tokenize "$cmd" || return 1
  verify_tokens "$depth"
}

# --------------------------------------------------------------------------
# main: read the payload, extract the two fields with jq (degrade to defer when
# jq is absent), and auto-approve only a known-safe Bash command. Every exit is
# 0 with either the single allow object or empty stdout.
main() {
  local input tool cmd cwd

  # Bounded, defensive stdin read: cap the payload so a giant blob can never
  # make the hook spin (REQ-B1.7). Command substitution strips trailing
  # newlines, which JSON does not care about.
  input=$(head -c 2000000 2>/dev/null) || input=''
  [ -n "$input" ] || return 0

  # jq absent -> auto-approve nothing (REQ-B1.2). Never a hand-rolled parse.
  command -v jq >/dev/null 2>&1 || return 0

  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || return 0
  [ "$tool" = Bash ] || return 0 # every non-Bash tool defers (REQ-A1.7)

  # The command must be a JSON string; a present-but-empty or non-string value
  # defers (REQ-B1.7).
  cmd=$(printf '%s' "$input" \
    | jq -r 'if (.tool_input.command | type) == "string" then .tool_input.command else empty end' \
      2>/dev/null) || return 0
  [ -n "$cmd" ] || return 0

  # `cwd` gets the same type discipline as `command` (REQ-B1.7): ABSENT (or null)
  # is a supported shape and falls back to $PWD, but a PRESENT non-string value
  # (object, array, number, boolean) means the payload does not match the
  # documented PreToolUse contract, so the whole analysis defers rather than
  # containment-checking against whatever `jq -r` renders such a value as.
  case $(printf '%s' "$input" | jq -r 'if has("cwd") and .cwd != null then (.cwd | type) else "absent" end' 2>/dev/null) in
    absent) cwd=$PWD ;;
    string)
      cwd=$(printf '%s' "$input" | jq -r '.cwd' 2>/dev/null) || return 0
      [ -n "$cwd" ] || cwd=$PWD
      ;;
    *) return 0 ;; # present but not a string: defer
  esac
  local HOOK_CWD=$cwd
  # Shared across `fish -c` recursion so nesting cannot multiply the bound.
  LOOP_PASSES=0
  SIMPLE_N=0

  analyze_command "$cmd" 0 || return 0
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
# Arm 3 of the same chain: the roots Claude Code itself installed the plugin
# at, resolved once at load from its own record and cache (never from the
# analyzed command). Empty when neither exists.
INSTALLED_ROOTS=$(installed_planwright_roots) || INSTALLED_ROOTS=''

# Fail safe on any unexpected signal: empty stdout, exit 0 (REQ-B1.7). The hook
# never blocks a worker's tool call.
trap 'exit 0' HUP INT TERM PIPE
trap '[ -z "$DECL_PGID" ] || kill -KILL -- "-$DECL_PGID" 2>/dev/null; [ -z "$DECL_TMP" ] || rm -rf "$DECL_TMP"' EXIT

main
exit 0
