#!/usr/bin/env bash
# tower-command-guard.sh — deterministic PreToolUse auto-approve hook for the
# ORCHESTRATING TOWER (fleet-hardening Task 7; REQ-C1.1, REQ-C1.2, REQ-C1.3,
# REQ-E1.3, REQ-E1.4; D-8). Wired into config/tower-settings.json, it reads a
# Claude Code PreToolUse payload on stdin and prints a
# `permissionDecision: allow` decision for an ENUMERATED, TOWER-ORIENTED set of
# known-safe command shapes — the tower's own orchestration surface (tmux
# relay/observe, a `claude --worktree` hand-launch the tower runs at the
# operator's request, planwright scripts by resolved literal path) plus the
# read-only state-observation shapes a tower reads — and DEFERS everything else
# to Claude Code's normal permission flow, fronting the stochastic `auto`-mode classifier with a tested allow layer so
# routine orchestration commands are never non-deterministically blocked.
# The /tower front door runs under the same profile, so the set also carries
# the shapes its sessions run routinely: jq with an inline filter (the worker
# guard's screen, kept identical), bare mktemp, and removal of mktemp-named
# files directly inside TMPDIR, the macOS per-user temp directory, or /tmp.
#
# It reuses the worker-command-guard PATTERN (worker-permission-ergonomics,
# #236/#237) — same tokenizer, same allow-only / fail-closed / no-LLM security
# contract — but fronts a DISTINCT safe set (D-8, REQ-C1.2): it ADDS the
# tower-only shapes (tmux relay/observe, the `claude --worktree` hand-launch,
# bare mktemp, the temp-file rm) the worker guard defers, and it OMITS the
# worker-only shapes (`bats`, `tests/` scripts, `fish -c` recursion) the tower
# does not run. The two guards are
# separate files by design: worker-command-guard.sh is a shipped, consumed
# mechanism this task must not perturb, and a self-contained security script is
# auditable without a cross-file dependency that could break at runtime.
#
# Security contract (identical to the worker guard's — the whole point):
#   * No LLM in the decision path (REQ-E1.3); purely deterministic shell. The
#     analyzed command is inert DATA — never eval-ed, re-expanded, or executed.
#   * Allow-only: it emits `allow` or nothing. It NEVER emits deny/ask and
#     NEVER exits non-zero — approval is upgrade-only; blocking stays with
#     permissions.deny (REQ-C1.2). A hook `allow` therefore never needs to (and
#     by design never does) auto-approve a deny-listed command: the allowlist is
#     tower-safe shapes with zero overlap with the tower deny block, and the
#     adversarial suite pins that OUTCOME (REQ-C1.3, obs:4dda9fe1) rather than
#     leaning on Claude Code's undocumented allow-vs-deny precedence.
#   * Escalation pins (REQ-C1.2): a `claude --worktree` hand-launch is
#     auto-approved only when every arg is on a curated safe-flag ALLOWLIST
#     (see guard_claude); any unrecognized flag DEFERS, so the tower can never
#     auto-approve launching a worker with its permission layer disabled (the
#     tmux rung's own launch, inside scripts/fleet-dispatch-worktree.sh, which
#     this guard allows wholesale, carries the same pin in that script's
#     validate_launch_extra) — this fails closed on the full
#     escalation surface (--dangerously-skip-permissions, the
#     `--allow-dangerously-*` and `--permission-*` variants, --settings /
#     --setting-sources / --mcp-config / --agents / --plugin-dir / --add-dir) and
#     on any future flag, where a denylist would leak. `tmux` is scoped to the
#     relay/observe subcommands, never `send-keys` / `kill-session` / any
#     lifecycle op.
#   * Fail safe on EVERYTHING: jq absent, malformed/empty/non-string input,
#     unknown construct, parser confusion, recursion past the depth bound, or
#     any internal error all DEFER (empty stdout, exit 0). The fallthrough
#     branch of every classifier is defer, so "zero false-allows" is guaranteed
#     by construction, not merely across the test corpus (REQ-C1.3).
#
# Analysis model (inherited from the worker guard): the command string exactly
# as written — Claude Code hands a hook the raw `tool_input.command`, with
# `$VAR` references unexpanded (measured on CLI 2.1.270) — is split —
# quote- and operator-aware — into segments on the control operators `;` `&&`
# `||` `|` `&` and newlines; EVERY segment's simple command must be
# independently known-safe. A command is known-safe only when its verb is on the
# tower allowlist, its flags/args designate no output/target file and enable no
# write or arbitrary execution (the bounded temp-file create and remove of
# guard_mktemp and guard_rm excepted), and it uses no construct the analyzer cannot
# confidently parse (command/process substitution, here-docs, subshell/brace
# grouping, env-assignment prefixes, path-prefixed verbs, escaped operators,
# ANSI-C quoting, shell comments, named-fd redirects) — all of which defer, as
# does any other expansion left in a verb or in an operand a screen reads (a
# `for` variable over plain-literal head words is resolved; see loop_header).
# planwright `scripts/*.sh` are trusted repo/plugin code but only after their
# path canonicalizes INSIDE the repo checkout's or the installed plugin's
# `scripts/` directory.
#
# Portable bash (3.2 floor / BSD compatible), no dependency on python, fish,
# mise, tmux, or Ansible; the security-critical analysis is pure shell. jq is
# used only to extract the two fields from the JSON payload; when jq is absent
# the hook degrades to deferring everything, never a hand-rolled JSON parse and
# never a false-allow.
set -u
unset CDPATH
# Pin the C locale so bracket expressions and character classes below mean
# exactly their ASCII range on every host (mirrors the sibling hooks).
LC_ALL=C
export LC_ALL

# Bounds (bounded runtime). The tokenizer scans the command with bash substring
# indexing (`${s:i:1}`), O(n) per access and so O(n^2) over the command;
# MAX_CMD_LEN caps that at a fraction of a second per analyze_command entry so
# the hook can never hang the tower's tool call — a longer command simply
# defers. MAX_DEPTH is retained for parity with the worker guard's shared engine
# — there `fish -c "<inner>"` re-enters analyze_command, so the depth cap bounds
# that recursion. This tower guard fronts no recursive shape (`fish -c` defers),
# so analyze_command is only ever entered at depth 0; the depth check is a
# defensive floor here, not an active limiter.
readonly MAX_CMD_LEN=8192
readonly MAX_DEPTH=3
# A `for` loop is verified once per head word: past MAX_LOOP_WORDS head words
# the loop defers, past MAX_LOOP_PASSES body walks the command defers.
readonly MAX_LOOP_WORDS=16
readonly MAX_LOOP_PASSES=64
# Simple commands verified in one hook call, loop passes and `fish -c` inner
# strings included: each may canonicalize a path, so this bounds the runtime
# the loop modelling multiplies. Past it the command defers.
readonly MAX_SIMPLE_CMDS=512

# The fixed reason string. It is NEVER a reflection of the analyzed command:
# untrusted command content is never echoed to a terminal-driving stream.
readonly ALLOW_REASON='planwright tower-command-guard: enumerated known-safe tower orchestration / read-only / bounded temp-file command shape (deterministic, no LLM)'

# emit_allow: write the single allow decision (the only thing this hook ever
# prints). Written as one final action after every check has passed, so there
# is never a partially-written allow.
emit_allow() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"'"$ALLOW_REASON"'"}}'
}

# --------------------------------------------------------------------------
# Tokenizer. Scans the command as inert data into a token stream held in the
# caller's (analyze_command's) locals TOK_TYPE / TOK_VAL / TOK_N via dynamic
# scope. Token types: W (word), O (control/grouping operator), R (redirect
# operator, possibly with an fd-number prefix). Returns non-zero (DEFER) the
# instant it meets a construct it will not analyze: unbalanced quotes,
# command/process substitution, backtick substitution, ANSI-C `$'…'`, a
# backslash line-continuation or escaped operator/quote, a shell comment, or a
# named-fd redirect.
# It never executes or expands anything it scans. A W token also records
# whether it carries a LITERAL `$` (single quotes or a backslash), an
# EXPANDING `$` (1 inside double quotes, 2 unquoted), and an unquoted glob,
# brace expansion, or leading tilde (see word_unresolved). The fifth argument
# is the worker guard's quote-start offset, unused here and kept so the two
# signatures match.
tok_push() {
  TOK_TYPE[TOK_N]=$1
  TOK_VAL[TOK_N]=$2
  TOK_QUOTED[TOK_N]=${3:-0}
  TOK_NOEXP[TOK_N]=${4:-0}
  TOK_DYN[TOK_N]=${6:-0}
  TOK_GLOB[TOK_N]=${7:-0}
  TOK_ZOPT[TOK_N]=${8:-0}
  TOK_N=$((TOK_N + 1))
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
# glob qualifier in that value can run a command during the expansion.
dollar_form_ok() {
  local s=$1 i=$2 j body
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
      while [ "$j" -lt "${#s}" ]; do
        case ${s:j:1} in
          [A-Za-z0-9_]) j=$((j + 1)) ;;
          *) break ;;
        esac
      done
      case ${s:j:1} in
        '' | [[:print:][:cntrl:]]) ;;
        *) return 1 ;;
      esac
      ;;
  esac
  return 0
}

tokenize() {
  local s=$1
  local n=${#s}
  local i=0
  local cur='' have=0 curq=0 curx=0 curd=0 curg=0 curz=0 brk=0 brc=0 brs=0
  local c nc j k dc dn fdpfx

  _flush() {
    if [ "$have" = 1 ]; then
      tok_push W "$cur" "$curq" "$curx" -1 "$curd" "$curg" "$curz"
      cur=''
      have=0
      curq=0
      curx=0
      curd=0
      curg=0
      curz=0
      brk=0
      brc=0
      brs=0
    fi
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
        cur="$cur$nc"
        have=1
        curq=1
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
        cur="$cur$k"
        have=1
        curq=1
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
        cur="$cur$k"
        have=1
        curq=1
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
          case $cur in
            '' | *[!0-9]*) tok_push W "$cur" "$curq" "$curx" -1 "$curd" "$curg" "$curz" ;;
            *) [ "$curq" = 1 ] && tok_push W "$cur" "$curq" "$curx" -1 "$curd" "$curg" "$curz" || fdpfx=$cur ;;
          esac
          cur=''
          have=0
          curq=0
          curx=0
          curd=0
          curg=0
          curz=0
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
# file or is a here-doc/here-string. fd-number prefixes are stripped first so
# `2>&1`, `>&2`, `2>&-` read as fd operations, not file writes.
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
# Repo/plugin-root discovery and path containment. repo_root_of walks up from
# the payload cwd looking for a `.git` entry (a dir in a normal checkout, a file
# in a worktree). canon_under canonicalizes a script path (resolving `..` and
# symlinks on its directory) and checks it resolves INSIDE an arbitrary
# already-canonical base root.
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
# (resolved relative to <cwd>) and returns 0 only when it resolves inside <base>
# (an already-canonical root); returns non-zero (DEFER) otherwise — including
# when <base> is empty, the path's directory cannot be resolved, or the final
# component is a symlink (which could point OUT of <base>). Mirrors the worker
# guard's canon_contained, generalized to an arbitrary containment root.
canon_under() {
  local p=$1 cwd=$2 base=$3 d b cd full
  [ -n "$base" ] || return 1
  case $p in
    /*) ;;
    *) p="$cwd/$p" ;;
  esac
  d=$(dirname "$p")
  b=$(basename "$p")
  cd=$(cd "$d" 2>/dev/null && pwd -P) || return 1
  full="$cd/$b"
  # `pwd -P` canonicalizes any symlink in the DIRECTORY path, but the final
  # component can still be a symlink pointing OUT of the base — bash would follow
  # it and run external code. Defer a symlinked target rather than trust its
  # in-base location.
  [ -L "$full" ] && return 1
  case $full in
    "$base"/*)
      printf '%s' "$full"
      return 0
      ;;
    *) return 1 ;;
  esac
}

# is_planwright_script <path> <cwd>: 0 when <path> is a `.sh` under a `scripts/`
# directory that canonicalizes inside EITHER the repo checkout (self-hosting
# dev) OR the installed plugin root (the core root chain's CLAUDE_PLUGIN_ROOT
# arm, hook_plugin_root below — the tower's resolved literal path under a
# marketplace/writer install). The chain's other arms are not trusted: that is
# the tower's own, tighter policy. `tests/` is deliberately NOT
# a trusted script directory for the tower (that is a worker-only shape), so the
# tower set stays distinct from and tighter than the worker set (REQ-C1.2).
is_planwright_script() {
  local p=$1 cwd=$2 root proot full rel
  case $p in
    *.sh) ;;
    *) return 1 ;;
  esac
  # (a) under the repo checkout's scripts/ dir.
  if root=$(repo_root_of "$cwd"); then
    if full=$(canon_under "$p" "$cwd" "$root"); then
      rel=${full#"$root"/}
      case $rel in
        scripts/*) return 0 ;;
      esac
    fi
  fi
  # (b) under the installed plugin's scripts/ dir (resolved literal path).
  cache_plugin_root
  proot=$PLUGIN_ROOT_CACHED
  if [ -n "$proot" ]; then
    if full=$(canon_under "$p" "$cwd" "$proot"); then
      rel=${full#"$proot"/}
      case $rel in
        scripts/*) return 0 ;;
      esac
    fi
  fi
  return 1
}

# --------------------------------------------------------------------------
# Per-verb guards. Each reads the current simple command's words from the
# caller's `cw` array (index 0 = verb) and `cwn` count via dynamic scope, plus
# `HOOK_CWD`. Every guard's default/fallthrough is DEFER.

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
# expression" genuinely ambiguous across dialects (REQ-C1.3 fail-closed).
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
        # sed errors out). Never silently skip it: defer (REQ-C1.3 fail-closed).
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
      -e) expect_e=1 ;;
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

# guard_awk: strict flag allowlist (REQ-C1.2) plus the read-only program check.
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

# guard_tmux: the tower's tmux RELAY/OBSERVE safe set — buffer relay
# (load-buffer / paste-buffer), buffer inspection (show-buffer — dumps a paste
# buffer's contents to stdout, read-only), pane observation (capture-pane), the
# buffer/session/window/pane listings the relay targets by handle, has-session,
# and display-message. Deliberately SCOPED to the relay/observe surface planwright
# actually emits: it does NOT include the config-introspection subcommands
# (show-options, show-environment) — show-environment would surface a worker's
# environment into the tower's context (a mild info-exposure), and neither is a
# relay/observe op — so they fall to the normal permission flow rather than being
# auto-approved. NEVER `send-keys` (the impersonation path the relay contract
# forbids — it defers, it is not auto-approved) nor any session / window / pane
# lifecycle op (kill-*, new-session, split-window, respawn-*, run-shell, if-shell,
# set-*, source-file), which spawn, destroy, or execute. The subcommand allowlist
# is closed: a leading server flag (-L/-S/-f), bare `tmux`, or any unlisted
# subcommand DEFER (REQ-C1.2). It is also NOT sufficient on its own: tmux runs
# the `#(shell-command)` format directive as a shell command, so an otherwise
# read-only observe subcommand carrying a `#(...)` format arg is arbitrary code
# execution — any arg with that form DEFERS, while the inert `#{variable}` form
# stays allowed.
guard_tmux() {
  local i
  [ "$cwn" -ge 2 ] || return 1
  case ${cw[1]} in
    -*) return 1 ;; # a pre-subcommand server flag: defer, conservatively
  esac
  # tmux evaluates the `#(shell-command)` format directive (in a `-F` format or
  # display-message's message) as a SHELL COMMAND — so an observe subcommand
  # carrying a `#(...)` arg is arbitrary code execution, NOT a read-only observe.
  # The subcommand allowlist below is necessary but not sufficient: any arg with
  # the command-substitution form defers. The inert `#{variable}` form (what the
  # relay/observe path actually emits, e.g. `#{pane_pid}`) contains no `#(` and
  # stays allowed.
  for ((i = 1; i < cwn; i++)); do
    case ${cw[i]} in
      *'#('*) return 1 ;;
    esac
  done
  case ${cw[1]} in
    load-buffer | loadb | paste-buffer | pasteb | capture-pane | capturep | \
      list-sessions | ls | list-windows | lsw | list-panes | lsp | \
      list-clients | lsc | list-buffers | lsb | has-session | \
      display-message | display | show-buffer | showb)
      return 0
      ;;
    *) return 1 ;;
  esac
}

# guard_claude: the tower's hand-launch safe set — a `claude --worktree` launch
# the tower runs at the operator's request. The tmux rung does not launch this
# way: its worker starts in a detached session fleet-dispatch-worktree.sh
# creates, which the tower runs as a planwright script by literal path. It
# requires the --worktree flag (the launch shape) and is an ALLOWLIST of
# known-safe launch flags: every arg must be --worktree or one of a
# curated set of benign flags, and ANY unrecognized flag or positional DEFERS
# (fail closed). REQ-C1.2 frames the pin as excluding --dangerously-skip-permissions
# / --permission-mode, but the real Claude Code launch surface carries a WIDER set
# of permission/trust-layer escalations — --allow-dangerously-skip-permissions
# (which a `--dangerously-*` / `--permission-*` denylist misses), --settings /
# --setting-sources (override the worker's settings), --mcp-config / --agents /
# --plugin-dir (inject servers/agents/plugins), --add-dir (widen filesystem) — so
# an allowlist is the only robust pin: it fails closed on every one of those AND
# on any future flag, where a denylist leaks. The usual hand-launch shape
# (`claude --worktree <suffix> [--tmux=classic] [--model <m>] [--effort <e>]`)
# is on the allowlist, so the fail-closed posture never floods a routine
# hand-launch; a non-standard launch simply falls to the normal permission flow.
# `--effort` sits beside `--model` for the same reason: both select capability
# and cost and neither touches the permission or trust layer this pin exists to
# hold. A hand-launch carrying a resolved tier passes it (model-allocation
# D-10), so leaving it off would make every such launch prompt.
guard_claude() {
  local i a saw_worktree=0 expect_value=0
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    if [ "$expect_value" = 1 ]; then
      expect_value=0
      # This token is the value of the preceding safe value-flag (a worktree
      # suffix, a model name) — a real value never starts with `-`. A flag-shaped
      # token here means the guard's "next token is the value" assumption has
      # diverged from claude's own arg parsing (which would treat it as a
      # separate flag, e.g. --worktree swallowing a following
      # --dangerously-skip-permissions), so fail closed rather than let an
      # escalation flag slip through disguised as an inert value.
      case $a in
        -*) return 1 ;;
      esac
      continue
    fi
    case $a in
      --worktree)
        saw_worktree=1
        expect_value=1 # space-form value (the bare worktree suffix) follows
        ;;
      --worktree=*) saw_worktree=1 ;;
      --model | --fallback-model | --effort) expect_value=1 ;; # value-taking safe flags (space form)
      --model=* | --fallback-model=* | --effort=*) ;;          # =form: value attached
      --tmux | --tmux=* | --continue | -c | --resume | -r | --resume=* | -r=*) ;;
      *) return 1 ;; # unrecognized flag or positional: DEFER (fail closed)
    esac
  done
  [ "$expect_value" = 1 ] && return 1 # a dangling value-flag with no value: defer
  [ "$saw_worktree" = 1 ] || return 1
  return 0
}

guard_bashsh() {
  # Only `bash <planwright-script> [args]` / `sh <planwright-script> [args]`;
  # any option (notably -c / -ec) defers. The script must canonicalize inside
  # the repo's or plugin's scripts/ dir.
  [ "$cwn" -ge 2 ] || return 1
  case ${cw[1]} in
    -*) return 1 ;;
  esac
  is_planwright_script "${cw[1]}" "$HOOK_CWD"
}

# gh: read-only gh only. A leading flag, or any non-enumerated group/sub pair,
# defers — notably `gh pr merge` / `gh pr ready` are absent and so defer (the
# deny block denies them regardless; the guard simply never allows them).
guard_gh() {
  case ${cw[1]-} in
    -*) return 1 ;;
  esac
  local g=${cw[1]-} s=${cw[2]-}
  case $g in
    pr)
      case $s in
        view | list | status | diff | checks) return 0 ;;
        *) return 1 ;;
      esac
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
# the home-directory half of guard_jq's screen (see there).
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

# no_input_redirect: 0 when the simple command (verify_simple's ro/rn) carries
# no input redirect. zsh, the shell the Bash tool runs on macOS, reads `<->`
# and `<1-99>` as a numeric glob that expands to digit-named files, where the
# tokenizer sees two redirects; for a writer that turns into operands the
# guard never checked. mktemp and rm read no stdin, so any `<` form defers.
no_input_redirect() {
  local i r
  for ((i = 0; i < rn; i++)); do
    r=${ro[i]}
    while [ -n "$r" ]; do
      case $r in
        [0-9]*) r=${r#?} ;;
        *) break ;;
      esac
    done
    case $r in
      '<'*) return 1 ;;
    esac
  done
  return 0
}

# guard_mktemp: the bare form only, which creates one fresh, empty file in the
# system temp directory (TMPDIR, or on macOS the per-user temp directory) and
# prints its name. A template, -p/--tmpdir or -t chooses where the file goes;
# -d makes a directory guard_rm will not remove; -u only names a path, which is
# the race mktemp exists to avoid. Once a while or until loop has opened in the
# command (verify_tokens' in_unbounded_loop) it defers: those loops have no
# pass cap, so mktemp there would create files without bound. An input
# redirect defers too (no_input_redirect).
guard_mktemp() {
  [ "$cwn" -eq 1 ] && [ "${in_unbounded_loop:-0}" = 0 ] && no_input_redirect
}

# canon_temp_dir <dir>: the physical path of an absolute <dir> on one line, or
# nothing when it is relative (it would resolve against the hook's directory,
# not the command's), unresolvable, or holds a line break the list would split.
canon_temp_dir() {
  local c
  case $1 in
    /*) ;;
    *) return 0 ;;
  esac
  c=$(cd -P -- "$1" 2>/dev/null && pwd -P && printf x) || return 0
  c=${c%x}
  c=${c%"$NL"}
  case $c in
    *"$NL"*) return 0 ;;
  esac
  printf '%s\n' "$c"
}

# raw_temp_dir <dir>: an absolute <dir> as spelled, its trailing slashes
# dropped, on one line; nothing when it is relative, the root, or holds a line
# break.
raw_temp_dir() {
  local r=$1
  case $r in
    /*) ;;
    *) return 0 ;;
  esac
  while :; do
    case $r in
      */) r=${r%/} ;;
      *) break ;;
    esac
  done
  case $r in
    '' | *"$NL"*) return 0 ;;
  esac
  printf '%s\n' "$r"
}

# temp_dirs: TMPDIR, the macOS per-user temp directory (where bare mktemp
# writes there, whatever TMPDIR says), and /tmp, each as spelled (raw_temp_dir)
# and as resolved (canon_temp_dir), one per line. Read from the hook's own
# environment, never from the analyzed command.
temp_dirs() {
  local u t
  for t in "${TMPDIR:-}" /tmp; do
    raw_temp_dir "$t"
    canon_temp_dir "$t"
  done
  if u=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null); then
    raw_temp_dir "$u"
    canon_temp_dir "$u"
  fi
}

# loop_head_quoted: 0 when an open `for` loop (verify_tokens' LF_QH, by
# dynamic scope) has a quoted head word, whose value the reader may have
# dequoted differently from the shell.
loop_head_quoted() {
  local t
  for ((t = 0; t < lf_n; t++)); do
    [ "${LF_QH[t]-0}" = 1 ] && return 0
  done
  return 1
}

# guard_rm: removing mktemp-named temp files, so a flight petition's ask and
# grounds files can be cleaned up once the dispatch returns. Each operand must
# be an absolute path with no `.` or `..` component, whose name has mktemp's
# default shape (`tmp.` and at least six letters or digits), whose directory
# is one of temp_dirs both as written and as resolved physically (never below
# them, and never through a symlink the list does not name), and that
# is not a symlink, a directory, or any other non-regular file. A name that
# does not exist yet is allowed: without -r rm cannot take a directory that
# appears later, and a symlink that appears later is unlinked, never followed.
# `-f` and `--` are the only flags, and only before the first operand: BSD rm
# reads a later one as a file name. -r/-R/-d (directories), -i/-I/-v and every
# other flag defer, and so does any removal once a while or until loop has
# opened or with an input redirect, as guard_mktemp does. A quoted or
# backslash-escaped operand defers too, as does one taking its value from a
# quoted `for` head word. The guard cannot tell whose file it is: any
# same-user file of that name in those directories qualifies.
guard_rm() {
  local i a d b s w dirs endflags=0 operands=0
  [ "${in_unbounded_loop:-0}" = 0 ] || return 1
  no_input_redirect || return 1
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    # The reader drops quoting the shell keeps (a double-quoted backslash
    # before an ordinary character), so a quoted word, or a loop value taken
    # from a quoted head word, may name another path to rm.
    [ "${cq[i]-0}" = 1 ] && return 1
    if [ "$endflags" = 0 ]; then
      case $a in
        --)
          endflags=1
          continue
          ;;
        -f) continue ;;
        -*) return 1 ;;
      esac
    fi
    endflags=1
    # A newline would let a crafted directory name span lines of the
    # newline-joined directory list below. A dot component would let a logical
    # path walk back out through a symlink rm itself follows.
    case $a in
      *"$NL"* | */./* | */../* | */. | */..) return 1 ;;
      /*) ;;
      *) return 1 ;;
    esac
    b=${a##*/}
    case $b in
      tmp.*) s=${b#tmp.} ;;
      *) return 1 ;;
    esac
    [ "${#s}" -ge 6 ] || return 1
    case $s in
      *[!A-Za-z0-9]*) return 1 ;;
    esac
    [ -L "$a" ] && return 1
    if [ -e "$a" ]; then
      [ -f "$a" ] || return 1
    fi
    # The sentinel keeps a trailing newline in the directory's name, which a
    # bare command substitution would strip into a match.
    d=$(cd -P -- "${a%/*}/" 2>/dev/null && pwd -P && printf x) || return 1
    d=${d%x}
    d=${d%"$NL"}
    case $d in
      *"$NL"*) return 1 ;;
    esac
    cache_temp_dirs
    dirs=$TEMP_DIRS_CACHED
    [ -n "$dirs" ] || return 1
    case $NL$dirs$NL in
      *"$NL$d$NL"*) ;;
      *) return 1 ;;
    esac
    # The directory as written must be one of them too: a symlink in the
    # written path could be re-pointed by its owner after this check.
    w=${a%/*}
    while :; do
      case $w in
        */) w=${w%/} ;;
        *) break ;;
      esac
    done
    case $NL$dirs$NL in
      *"$NL$w$NL"*) ;;
      *) return 1 ;;
    esac
    operands=$((operands + 1))
  done
  [ "$operands" -ge 1 ]
}

# mise: `mise run <task>` / `mise tasks` (and its read-only leaves) only. Any
# pre-subcommand flag, a `--shell`/`-s` interpreter override, or another
# subcommand defers.
guard_mise() {
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
      leaf=''
      for ((j = i + 1; j < cwn; j++)); do
        case ${cw[j]} in
          -*) ;; # a tasks-level display flag: read-only
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
  for (( ; i < cwn; i++)); do
    case ${cw[i]} in
      --shell | --shell=*) return 1 ;;
      -[!-]*s* | -s*) return 1 ;;
    esac
  done
  return 0
}

# git: read-only subcommands only, no pre-subcommand global option (which can
# inject config/alias-driven execution), and per-subcommand form guards on the
# subcommands with a mutating twin. `update-ref` / `branch -f` are absent from
# the read-only set and so defer (the deny block denies them regardless).
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
      case ${cw[subidx + 1]-} in
        list | show) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    symbolic-ref)
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
      case ${cw[subidx + 1]-} in
        '' | show | exists) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

# --------------------------------------------------------------------------
# Words whose value is not their text, and the one expansion the tower
# resolves: a `for` loop variable, verified once per plain-literal head word
# (loop_header). The engine is the worker guard's; see word_unresolved there
# for the rule and its reasons.

# assign_name_ok <name>: the name a loop may bind. Shell-consumed names
# (PATH, IFS, …) and any name exported in the hook's environment re-point
# what later verbs run, so they defer.
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
  # zsh, the Bash tool's shell on macOS, gives these names a special meaning
  # as variables, as bash gives PATH and CDPATH.
  case $name in
    path | cdpath | NULLCMD | READNULLCMD | module_path | MODULE_PATH | \
      fpath | FPATH | manpath | MANPATH) return 1 ;;
  esac
  case $HOOK_ENV_NAMES in
    *"$NL$name$NL"*) return 1 ;;
  esac
  return 0
}

# expand_word <word>: substitute every `$NAME` / `${NAME}` the table holds;
# any other `$` is left in place so the word still reads as unresolved. The
# result is left in EXPANDED.
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
      # zsh, the Bash tool's shell on macOS, applies a subscript or a modifier
      # to an unbraced name directly followed by `[` or `:`, quoted or not, so
      # the value is not the name's: leave it unresolved.
      case ${w:k:1} in
        '[' | ':') name='' ;;
      esac
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

word_unresolved() {
  [ "$3" = 1 ] && return 0
  [ "$2" = 0 ] && return 1
  [ "$4" = 1 ] && return 0
  case $1 in
    *'$'*) return 0 ;;
  esac
  return 1
}

arg_independent_verb() {
  case $1 in
    cat | head | tail | wc | cut | comm | cmp | basename | dirname | realpath | pwd | echo | seq | true | false | od | tr | stat | grep | ls | diff) return 0 ;;
    printenv | readlink | nl | paste | column | md5sum | sha1sum | sha256sum | sha512sum | cksum | shellcheck | yamllint) return 0 ;;
  esac
  return 1
}

# guard_test / guard_printf: the `-v` forms evaluate an array subscript, which
# runs any `$(…)` inside it, and `printf -v` assigns a variable.
guard_test() {
  local i
  for ((i = 1; i < cwn; i++)); do
    [ "${cw[i]}" = -v ] && return 1
  done
  return 0
}

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

# classify_verb: the tower's enumerated allowlist. A bare verb (no slash) is
# looked up here; the fallthrough is DEFER. Read-only tools with NO file-write,
# code-exec, or output-to-file capability are approved with any flags; tools with
# a write/set/exec vector carry an explicit guard; the tower orchestration verbs
# (tmux, claude) carry their own tight guards; and the worker-only shapes
# (`fish`, `bats`) are deliberately ABSENT so the tower set is distinct from the
# worker set (REQ-C1.2). Every writer / command-runner / arbitrary-exec verb is
# simply absent here and so defers, with one bounded exception: guard_mktemp and
# guard_rm create and remove mktemp-named temp files and nothing else (whose
# file it is, the guard cannot tell).
classify_verb() {
  local verb=$1
  case $verb in
    # Read-only, no write/exec/output vector: any flags are safe.
    cat | head | tail | wc | cut | comm | cmp | basename | dirname | realpath | pwd | echo | seq | true | false | od | tr | stat | grep | ls | diff)
      return 0
      ;;
    test | '[') guard_test ;;
    printf) guard_printf ;;
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
    # markdownlint / markdownlint-cli2 are deliberately ABSENT from the tower
    # safe set: their --config/-c and -r/--rules flags load an arbitrary file as
    # an executable module (a code-exec vector a denylist leaks), and the tower
    # never invokes them directly — it lints via `mise run lint:md` (guarded by
    # guard_mise). If a direct invocation is ever wanted, re-add as a flag
    # ALLOWLIST (the guard_claude posture), never a patched denylist.
    # Enumerated read-only subcommand tools.
    git) guard_git ;;
    gh) guard_gh ;;
    mise) guard_mise ;;
    # The front door's flight-petition temp files: create, then clean up.
    mktemp) guard_mktemp ;;
    rm) guard_rm ;;
    # Tower orchestration surface: relay/observe and the hand-launch.
    tmux) guard_tmux ;;
    claude) guard_claude ;;
    # Trusted planwright-script runner (path-contained).
    bash | sh) guard_bashsh ;;
    *) return 1 ;; # fallthrough is DEFER, by construction
  esac
}

# verify_simple: verify one simple command. Reads the accumulated word array
# `cw` (0=verb) / count `cwn` and the redirect arrays `ro` / `rt` / `rn` from
# the caller via dynamic scope. Returns 0 (safe) or non-zero (DEFER).
verify_simple() {
  local i verb
  SIMPLE_N=$((SIMPLE_N + 1))
  [ "$SIMPLE_N" -le "$MAX_SIMPLE_CMDS" ] || return 1
  for ((i = 0; i < rn; i++)); do
    classify_redirect "${ro[i]}" "${rt[i]}" || return 1
  done
  [ "$cwn" -ge 1 ] || return 0
  # Substitute the loop variables in scope, then refuse an unresolved word
  # anywhere its value decides the verdict (REQ-E1.1).
  if [ "$VAR_C" -gt 0 ]; then
    for ((i = 0; i < cwn; i++)); do
      case ${cw[i]} in
        *'$'*)
          if [ "${cx[i]}" = 0 ] && expand_word "${cw[i]}"; then
            [ "$EXPANDED" != "${cw[i]}" ] && loop_head_quoted && cq[i]=1
            cw[i]=$EXPANDED
          fi
          ;;
      esac
    done
  fi
  verb=${cw[0]}
  opaque_words_ok || return 1
  # Inline environment-assignment prefix: VAR=value [cmd].
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
  # A verb given as a path containing '/' is only the enumerated planwright-script
  # case; every other path-prefixed verb defers.
  case $verb in
    */*)
      is_planwright_script "$verb" "$HOOK_CWD" && return 0
      return 1
      ;;
  esac
  classify_verb "$verb"
}

# --------------------------------------------------------------------------
# verify_tokens <depth>: walk the token stream (in the caller's TOK_* locals),
# splitting into simple commands on control operators and recognizing the
# for/while/until/if/case control structures so their COMMAND regions are each
# verified while their case pattern regions are skipped. A `for` header is
# modelled (loop_enter); `select`, `for` with no in-list, and an arithmetic
# `for ((…))` defer. Any construct it
# cannot confidently place defers. Returns 0 (every simple command safe) or
# non-zero (DEFER).
verify_tokens() {
  local depth=$1
  local idx=0 typ val fidx k
  local mode=normal # normal | casehead | casepat | casebody
  local case_depth=0 ctl_depth=0 in_unbounded_loop=0
  local -a cw=() cx=() cdyn=() cglob=() cz=() cq=() ro=() rt=()
  local cwn=0 rn=0
  # The open `for` loops, innermost last (see the worker guard's walker).
  local -a LF_VAR=() LF_START=() LF_COUNT=() LF_POS=() LF_BODY=() LF_DEPTH=() LF_CASE=() LF_QH=()
  local lf_n=0

  fin() {
    verify_simple || return 1
    cw=()
    cx=()
    cdyn=()
    cglob=()
    cz=()
    cq=()
    ro=()
    rt=()
    cwn=0
    rn=0
    return 0
  }

  while [ "$idx" -lt "$TOK_N" ]; do
    typ=${TOK_TYPE[idx]}
    val=${TOK_VAL[idx]}

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
    if [ "$mode" = casepat ]; then
      if [ "$typ" = O ] && [ "$val" = ')' ]; then
        mode=casebody
      elif [ "$typ" = W ] && [ "$val" = "esac" ]; then
        case_depth=$((case_depth - 1))
        ctl_depth=$((ctl_depth - 1))
        mode=normal
      fi
      idx=$((idx + 1))
      continue
    fi

    if [ "$typ" = O ]; then
      case $val in
        ';' | '&&' | '||' | '|' | '&')
          fin || return 1
          ;;
        ';;')
          if [ "$mode" = casebody ]; then
            fin || return 1
            mode=casepat
          else
            return 1 # `;;` outside a case is malformed
          fi
          ;;
        '(')
          return 1 # subshell / arithmetic: defer
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
      local nxt=$((idx + 1))
      if [ "$nxt" -ge "$TOK_N" ] || [ "${TOK_TYPE[nxt]}" != W ]; then
        return 1 # dangling redirect operator
      fi
      [ "${TOK_QUOTED[nxt]}" = 1 ] && return 1
      ro[rn]=$val
      rt[rn]=${TOK_VAL[nxt]}
      rn=$((rn + 1))
      idx=$((idx + 2))
      continue
    fi

    if [ "$cwn" -eq 0 ] && is_reserved "$val"; then
      case $val in
        for)
          fin || return 1
          fidx=$idx
          loop_enter || return 1
          # Whether any head word was quoted: guard_rm refuses an operand that
          # takes such a word's value (the reader drops quoting the shell keeps).
          LF_QH[lf_n - 1]=0
          for ((k = fidx + 3; k < fidx + 3 + LH_COUNT; k++)); do
            [ "${TOK_QUOTED[k]}" = 1 ] && LF_QH[lf_n - 1]=1
          done
          continue
          ;;
        select)
          return 1 # its variable takes whatever the user types: not modelled
          ;;
        while | until | if)
          fin || return 1
          ctl_depth=$((ctl_depth + 1))
          [ "$val" = if ] || in_unbounded_loop=1
          ;;
        then | elif | else | do)
          fin || return 1 # boundary; regions on both sides are commands
          ;;
        fi)
          fin || return 1
          ctl_depth=$((ctl_depth - 1))
          [ "$ctl_depth" -ge 0 ] || return 1
          ;;
        done)
          fin || return 1
          ctl_depth=$((ctl_depth - 1))
          [ "$ctl_depth" -ge 0 ] || return 1 # a closer with no opener: defer
          loop_next
          case $? in
            0) continue ;;
            2) return 1 ;;
          esac
          ;;
        'case')
          fin || return 1
          case_depth=$((case_depth + 1))
          ctl_depth=$((ctl_depth + 1))
          [ "$case_depth" -gt 1 ] && return 1 # nested case: defer
          mode=casehead
          ;;
        'esac')
          fin || return 1
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

    cw[cwn]=$val
    cx[cwn]=${TOK_NOEXP[idx]}
    cdyn[cwn]=${TOK_DYN[idx]}
    cglob[cwn]=${TOK_GLOB[idx]}
    cz[cwn]=${TOK_ZOPT[idx]}
    cq[cwn]=${TOK_QUOTED[idx]}
    cwn=$((cwn + 1))
    idx=$((idx + 1))
  done

  [ "$mode" = normal ] || return 1
  [ "$case_depth" -eq 0 ] || return 1
  [ "$ctl_depth" -eq 0 ] || return 1
  fin || return 1
  return 0
}

# --------------------------------------------------------------------------
# analyze_command <command> <depth>: tokenize then verify. Returns 0 iff the
# whole command is known-safe. TOK_* are declared local here so any recursion
# gets a fresh, shadowing token stream.
analyze_command() {
  local cmd=$1 depth=$2
  [ "$depth" -le "$MAX_DEPTH" ] || return 1
  [ "${#cmd}" -le "$MAX_CMD_LEN" ] || return 1
  local -a TOK_TYPE=() TOK_VAL=() TOK_QUOTED=() TOK_NOEXP=() TOK_DYN=() TOK_GLOB=() TOK_ZOPT=()
  local TOK_N=0
  # The loop-variable table expand_word reads and the head words it draws from.
  # VAR_L is written by the shared loop_enter; only the worker guard reads it.
  # shellcheck disable=SC2034
  local -a VAR_N=() VAR_V=() VAR_L=() LW=()
  local VAR_C=0 LW_N=0
  local LH_NAME='' LH_START=0 LH_COUNT=0 LH_NEXT=0
  tokenize "$cmd" || return 1
  verify_tokens "$depth"
}

# --------------------------------------------------------------------------
# main: read the payload, extract the two fields with jq (degrade to defer when
# jq is absent), and auto-approve only a known-safe Bash command. Every exit is
# 0 with either the single allow object or empty stdout.
main() {
  local input tool cmd cwd

  input=$(head -c 2000000 2>/dev/null) || input=''
  [ -n "$input" ] || return 0

  command -v jq >/dev/null 2>&1 || return 0

  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || return 0
  [ "$tool" = Bash ] || return 0 # every non-Bash tool defers

  # A NUL byte defers too: the command substitution drops it, so the guard
  # would screen other text than the shell runs.
  cmd=$(printf '%s' "$input" \
    | jq -r 'if (.tool_input.command | type) == "string" and (.tool_input.command | explode | any(. == 0) | not) then .tool_input.command else empty end' \
      2>/dev/null) || return 0
  [ -n "$cmd" ] || return 0

  # `cwd` gets the same type discipline as `command` (REQ-C1.3): ABSENT (or null)
  # is a supported shape and falls back to $PWD, but a PRESENT non-string value
  # (object, array, number, boolean) means the payload does not match the
  # documented PreToolUse contract, so the whole analysis defers rather than
  # containment-checking against whatever `jq -r` renders such a value as.
  # A NUL byte in cwd defers, as in the command.
  case $(printf '%s' "$input" | jq -r 'if has("cwd") and .cwd != null then (if (.cwd | type) == "string" and (.cwd | explode | any(. == 0)) then "nul" else (.cwd | type) end) else "absent" end' 2>/dev/null) in
    absent) cwd=$PWD ;;
    string)
      cwd=$(printf '%s' "$input" | jq -r '.cwd' 2>/dev/null) || return 0
      [ -n "$cwd" ] || cwd=$PWD
      ;;
    *) return 0 ;; # present but not a string: defer
  esac
  local HOOK_CWD=$cwd
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

# The names the hook's own environment exports, for assign_name_ok. Never
# derived from the analyzed command.
HOOK_ENV_NAMES=$NL$(compgen -e)$NL

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

# hook_plugin_root: the plugin-delivery arm of the core root chain, from the
# resolver shipped beside this hook, never from the analyzed command. Asked
# only when a script path is checked, since the hook runs on every tool call.
HOOK_SCRIPTS=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || HOOK_SCRIPTS=''
hook_plugin_root() {
  [ -n "$HOOK_SCRIPTS" ] && [ -r "$HOOK_SCRIPTS/resolve-root.sh" ] || return 0
  CLAUDE_PLUGIN_ROOT=$(plugin_root_unlinked "$HOOK_SCRIPTS") /bin/sh "$HOOK_SCRIPTS/resolve-root.sh" install --all --explain 2>/dev/null \
    | sed -n "s/^CLAUDE_PLUGIN_ROOT$TAB//p" | head -n 1
}

# cache_plugin_root: hook_plugin_root once per hook call, into
# PLUGIN_ROOT_CACHED; a loop body re-checks its script paths on every pass.
PLUGIN_ROOT_CACHED=''
PLUGIN_ROOT_DONE=0
cache_plugin_root() {
  [ "$PLUGIN_ROOT_DONE" = 1 ] && return 0
  PLUGIN_ROOT_CACHED=$(hook_plugin_root) || PLUGIN_ROOT_CACHED=''
  PLUGIN_ROOT_DONE=1
}

# cache_temp_dirs: temp_dirs costs a getconf exec, so guard_rm builds the list
# once per hook call however many removals the command chains.
TEMP_DIRS_CACHED=''
TEMP_DIRS_DONE=0
cache_temp_dirs() {
  [ "$TEMP_DIRS_DONE" = 1 ] && return 0
  TEMP_DIRS_CACHED=$(temp_dirs) || TEMP_DIRS_CACHED=''
  TEMP_DIRS_DONE=1
}

# Fail safe on any unexpected signal: empty stdout, exit 0. The hook never
# blocks the tower's tool call.
trap 'exit 0' HUP INT TERM PIPE

main
exit 0
