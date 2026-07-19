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
#     the allowlist is read-only shapes with zero overlap with the worker deny
#     block, and the adversarial suite pins that (REQ-A1.3, REQ-B1.6).
#   * The extracted command is treated strictly as INERT DATA — never eval-ed,
#     re-expanded, glob-expanded, or used as a pattern/format/unquoted arg — so
#     analyzing a hostile command can never execute it (REQ-B1.1).
#   * Fail safe on EVERYTHING: jq absent, malformed/empty/non-string input,
#     unknown construct, parser confusion, recursion past the depth bound, or
#     any internal error all DEFER (empty stdout, exit 0). The fallthrough
#     branch of every classifier is defer, so "zero false-allows" is guaranteed
#     by construction, not merely across the test corpus (REQ-B1.3, REQ-B1.7).
#
# Analysis model: the fully-expanded command (Claude Code expands variables
# before the hook sees it) is split — quote- and operator-aware — into segments
# on the control operators `;` `&&` `||` `|` `&` and newlines; EVERY segment's
# simple command must be independently known-safe (REQ-A1.4). A command is
# known-safe only when (a) its verb is on the enumerated allowlist below, (b)
# its flags/args designate no output/target file and enable no write or
# arbitrary execution (REQ-A1.8), and (c) it uses no construct the analyzer
# cannot confidently parse — command/process substitution, here-docs, subshell
# or brace grouping, env-assignment prefixes, path-prefixed verbs, escaped
# operators, ANSI-C quoting — all of which defer (REQ-A1.9). Repo `scripts/*.sh`
# / `tests/*.sh` and `bats <file>` are trusted repo code but only after their
# path canonicalizes INSIDE the repository (REQ-A1.10). `fish -c "<inner>"`
# recurses the same analysis on the inner string within a bounded depth.
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

# Bounds (REQ-B1.7 bounded runtime): reject an over-long command outright, and
# cap `fish -c` recursion so a nested-`fish -c` bomb can never spin.
readonly MAX_CMD_LEN=65536
readonly MAX_DEPTH=3

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
tok_push() {
  TOK_TYPE[TOK_N]=$1
  TOK_VAL[TOK_N]=$2
  TOK_N=$((TOK_N + 1))
}

tokenize() {
  local s=$1
  local n=${#s}
  local i=0
  local cur='' have=0
  local c nc j k dc dn fdpfx

  while [ "$i" -lt "$n" ]; do
    c=${s:i:1}
    case $c in
      \\)
        nc=${s:i+1:1}
        [ -n "$nc" ] || return 1 # trailing backslash
        case $nc in
          "'" | '"' | ';' | '&' | '|' | '<' | '>' | '(' | ')') return 1 ;; # escaped op/quote
          "$NL") return 1 ;;                                               # line continuation
        esac
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
            k="$k$dn"
            j=$((j + 2))
            continue
          fi
          if [ "$dc" = '$' ]; then
            dn=${s:j+1:1}
            [ "$dn" = '(' ] && return 1 # $( command substitution
            [ "$dn" = "'" ] && return 1 # $' ANSI-C quoting
          fi
          [ "$dc" = '`' ] && return 1 # backtick substitution
          k="$k$dc"
          j=$((j + 1))
        done
        [ "$j" -lt "$n" ] || return 1 # unbalanced double quote
        cur="$cur$k"
        have=1
        i=$((j + 1))
        ;;
      '`') return 1 ;; # backtick substitution
      '$')
        nc=${s:i+1:1}
        [ "$nc" = '(' ] && return 1 # $( command substitution
        [ "$nc" = "'" ] && return 1 # $' ANSI-C quoting
        cur="$cur$c"
        have=1
        i=$((i + 1))
        ;;
      ' ' | "$TAB")
        if [ "$have" = 1 ]; then
          tok_push W "$cur"
          cur=''
          have=0
        fi
        i=$((i + 1))
        ;;
      "$NL")
        if [ "$have" = 1 ]; then
          tok_push W "$cur"
          cur=''
          have=0
        fi
        tok_push O ';'
        i=$((i + 1))
        ;;
      ';')
        if [ "$have" = 1 ]; then
          tok_push W "$cur"
          cur=''
          have=0
        fi
        if [ "${s:i+1:1}" = ';' ]; then
          tok_push O ';;'
          i=$((i + 2))
        else
          tok_push O ';'
          i=$((i + 1))
        fi
        ;;
      '&')
        if [ "$have" = 1 ]; then
          tok_push W "$cur"
          cur=''
          have=0
        fi
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
        if [ "$have" = 1 ]; then
          tok_push W "$cur"
          cur=''
          have=0
        fi
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
          case $cur in
            '' | *[!0-9]*) tok_push W "$cur" ;;
            *) fdpfx=$cur ;;
          esac
          cur=''
          have=0
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
        if [ "$have" = 1 ]; then
          tok_push W "$cur"
          cur=''
          have=0
        fi
        tok_push O '('
        i=$((i + 1))
        ;;
      ')')
        if [ "$have" = 1 ]; then
          tok_push W "$cur"
          cur=''
          have=0
        fi
        tok_push O ')'
        i=$((i + 1))
        ;;
      *)
        cur="$cur$c"
        have=1
        i=$((i + 1))
        ;;
    esac
  done
  [ "$have" = 1 ] && tok_push W "$cur"
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

# canon_contained <path> <cwd>: prints the canonical path and returns 0 only
# when it resolves inside the repo root; returns non-zero (DEFER) otherwise —
# including when the repo root or the path's directory cannot be resolved.
canon_contained() {
  local p=$1 cwd=$2 root d b cd
  root=$(repo_root_of "$cwd") || return 1
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
    "$root"/*)
      printf '%s' "$full"
      return 0
      ;;
    *) return 1 ;;
  esac
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

# is_contained_file <path> <cwd>: 0 when <path> canonicalizes inside the repo
# (used for `bats <file>`, which need not sit under scripts/ or tests/).
is_contained_file() {
  canon_contained "$1" "$2" >/dev/null
}

# --------------------------------------------------------------------------
# Per-verb guards. Each reads the current simple command's words from the
# caller's `cw` array (index 0 = verb) and `cwn` count via dynamic scope, plus
# `HOOK_CWD` and `HOOK_DEPTH`. Every guard's default/fallthrough is DEFER.

# sed_script_safe <script>: 0 only when a sed script is provably read-only —
# it contains no write (`w`/`W`), exec (`e`), or arbitrary-file-read (`r`/`R`)
# command, and no `s///` substitution whose flag block carries `w`/`W`/`e`. It
# is a small, inert delimiter-aware scanner (never eval-ed), deferring on ANY
# doubt: a bare/malformed command, the text-region commands `a`/`i`/`c` (their
# multi-line text region is not soundly segmentable here), and anything it
# cannot place. This is the fix for the whitespace-optional flag forms
# (`s/.*/x/e`, `s/a/b/wFILE`) a naive `[wWe][[:space:]]` heuristic misses.
sed_script_safe() {
  local s=$1
  local n=${#s} i=0 c d seen
  # A POSIX bracket expression `[...]` makes the delimiter char literal, so a
  # `/` (or custom delimiter) inside `[...]` would close a `/regex/` or `s///`
  # section EARLY and desync this scanner from real sed — reopening the
  # write/exec smuggling this guard closes. Modeling bracket expressions
  # soundly across sed dialects (leading `]`, `[:class:]`, GNU vs BSD escaping)
  # is error-prone, so any script containing `[` defers wholesale.
  case $s in
    *'['*) return 1 ;;
  esac
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
        i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          case ${s:i:1} in
            \\) i=$((i + 2)) ;;
            '/')
              i=$((i + 1))
              break
              ;;
            *) i=$((i + 1)) ;;
          esac
        done
        continue
        ;;
      \\)
        d=${s:i+1:1}
        [ -n "$d" ] || return 1
        i=$((i + 2))
        while [ "$i" -lt "$n" ]; do
          case ${s:i:1} in
            \\) i=$((i + 2)) ;;
            "$d")
              i=$((i + 1))
              break
              ;;
            *) i=$((i + 1)) ;;
          esac
        done
        continue
        ;;
    esac
    # A command letter.
    case $c in
      w | W | r | R | e) return 1 ;; # write / read-file / exec commands
      a | i | c) return 1 ;;         # text-region commands: defer (unparsed here)
      s | y)
        d=${s:i+1:1}
        [ -n "$d" ] || return 1
        i=$((i + 2))
        seen=0
        while [ "$i" -lt "$n" ] && [ "$seen" -lt 2 ]; do
          case ${s:i:1} in
            \\) i=$((i + 2)) ;;
            "$d")
              seen=$((seen + 1))
              i=$((i + 1))
              ;;
            *) i=$((i + 1)) ;;
          esac
        done
        [ "$seen" -lt 2 ] && return 1 # unterminated s/y command
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

guard_sort() {
  local i a
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      -o | --output | --output=*) return 1 ;;
      -o*) # bundled short flags containing o (e.g. -no) -> write target
        case $a in *o*) return 1 ;; esac
        ;;
    esac
    # Any bundled short-flag token that hides -o.
    case $a in
      -[!-]*o*) return 1 ;;
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
  # Only `bash <repo-script> [args]` / `sh <repo-script> [args]`; any option
  # (notably -c / -ec) defers (REQ-A1.5, REQ-A1.9).
  [ "$cwn" -ge 2 ] || return 1
  case ${cw[1]} in
    -*) return 1 ;;
  esac
  is_repo_script "${cw[1]}" "$HOOK_CWD"
}

guard_fish() {
  # Only `fish -c "<inner>"`; recurse the same analysis on the inner string
  # within the depth bound (REQ-A1.5, REQ-B1.3).
  [ "$cwn" -ge 3 ] || return 1
  [ "${cw[1]}" = '-c' ] || return 1
  analyze_command "${cw[2]}" "$((HOOK_DEPTH + 1))"
}

guard_bats() {
  # `bats [flags] <file...>`; every file operand must resolve inside the repo
  # (REQ-A1.10) and no report-output flag may be present.
  local i a saw_file=0
  for ((i = 1; i < cwn; i++)); do
    a=${cw[i]}
    case $a in
      -o | --output | --output=* | -T | --report-formatter) return 1 ;;
      -*) ;; # other bats flags (e.g. --tap, -r, --filter) are safe
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
  # REQ-A1.5: `mise run <task>` / `mise tasks` only (repo-defined tasks, trusted
  # per the kickoff trust boundary). Any pre-subcommand flag or other
  # subcommand defers.
  local sub=''
  local i a
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
    run | tasks) return 0 ;;
    *) return 1 ;;
  esac
}

guard_gh() {
  # REQ-A1.5: read-only gh only. A leading flag, or any non-enumerated group/sub
  # pair, defers.
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
      # `--ext-diff` / `--textconv` run a configured driver.
      for ((i = subidx + 1; i < cwn; i++)); do
        case ${cw[i]} in
          -o | --output | --output=* | --output-directory | --output-directory=*) return 1 ;;
          -O | -O* | --open-files-in-pager | --open-files-in-pager=*) return 1 ;;
          --ext-diff | --textconv) return 1 ;;
        esac
      done
      return 0
      ;;
    branch)
      for ((i = subidx + 1; i < cwn; i++)); do
        a=${cw[i]}
        case $a in
          -a | --all | -r | --remotes | -v | -vv | --verbose | -l | --list | --show-current | --contains | --no-contains | --merged | --no-merged | --points-at | --points-at=* | --format | --format=* | --color | --color=* | --no-color | -q | --quiet | -i | --ignore-case | --sort | --sort=* | --column | --no-column | --abbrev | --abbrev=* | --no-abbrev) ;;
          -*) return 1 ;; # any other flag (mutating or unknown) defers
          *) return 1 ;;  # a positional operand would create/target a branch
        esac
      done
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
classify_verb() {
  local verb=$1
  case $verb in
    # Read-only, no write/exec/output vector: any flags are safe.
    cat | head | tail | wc | cut | comm | cmp | basename | dirname | realpath | pwd | echo | printf | seq | true | false | od | tr | stat | grep | ls | diff | test | '[')
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
    markdownlint | markdownlint-cli2) guard_mdlint ;;
    # Enumerated read-only subcommand tools.
    git) guard_git ;;
    gh) guard_gh ;;
    mise) guard_mise ;;
    # Trusted repo-code runners (path-contained) and the fish recursor.
    bash | sh) guard_bashsh ;;
    fish) guard_fish ;;
    bats) guard_bats ;;
    *) return 1 ;; # fallthrough is DEFER, by construction (REQ-B1.6)
  esac
}

# verify_simple: verify one simple command. Reads the accumulated word array
# `cw` (0=verb) / count `cwn` and the redirect arrays `ro` (ops) / `rt`
# (targets) / `rn` from the caller via dynamic scope. Returns 0 (safe) or
# non-zero (DEFER).
verify_simple() {
  local i verb
  # Redirects first: a write to a real file defers regardless of the verb
  # (covers a leading redirect with no command too, e.g. `> f cat x`).
  for ((i = 0; i < rn; i++)); do
    classify_redirect "${ro[i]}" "${rt[i]}" || return 1
  done
  # A command with redirects but no words (pure `> file`) already handled;
  # an empty simple command (e.g. a trailing separator) is a no-op.
  [ "$cwn" -ge 1 ] || return 0
  verb=${cw[0]}
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
  # A verb given as a path containing '/' is only the enumerated repo-script
  # case; every other path-prefixed verb defers (REQ-A1.9, REQ-A1.10).
  case $verb in
    */*)
      is_repo_script "$verb" "$HOOK_CWD" && return 0
      return 1
      ;;
  esac
  classify_verb "$verb"
}

# --------------------------------------------------------------------------
# verify_tokens <depth>: walk the token stream (in the caller's TOK_* locals),
# splitting into simple commands on control operators and recognizing the
# for/while/until/if/case control structures so their COMMAND regions are each
# verified while their header/pattern regions are skipped (REQ-A1.5). Any
# construct it cannot confidently place — a stray `)`, a subshell `(`, a brace
# group, a nested `case`, an unbalanced structure — defers. Returns 0 (every
# simple command safe) or non-zero (DEFER).
verify_tokens() {
  local depth=$1
  local idx=0 typ val
  local mode=normal # normal | skip | casehead | casepat | casebody
  local case_depth=0
  # Accumulators for the current simple command (dynamic scope: verify_simple
  # reads these). Reset by fin().
  local -a cw=() ro=() rt=()
  local cwn=0 rn=0

  # fin: finalize the current simple command (verify it) and reset. Only called
  # in normal / casebody accumulation modes.
  fin() {
    verify_simple || return 1
    cw=()
    ro=()
    rt=()
    cwn=0
    rn=0
    return 0
  }

  while [ "$idx" -lt "$TOK_N" ]; do
    typ=${TOK_TYPE[idx]}
    val=${TOK_VAL[idx]}

    # for-loop header: skip everything up to the matching `do`.
    if [ "$mode" = skip ]; then
      if [ "$typ" = W ] && [ "$val" = "do" ]; then
        mode=normal
      fi
      idx=$((idx + 1))
      continue
    fi
    # case head: skip the matched word up to `in`.
    if [ "$mode" = casehead ]; then
      if [ "$typ" = W ] && [ "$val" = "in" ]; then
        mode=casepat
      elif [ "$typ" = W ] && [ "$val" = "esac" ]; then
        case_depth=$((case_depth - 1))
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
        mode=normal
      fi
      # `(` (optional leading pattern paren) and `|` (alternation) are skipped.
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
        for | select)
          fin || return 1
          mode=skip
          ;;
        while | until | if | then | elif | else | fi | do | done)
          fin || return 1 # boundary; regions on both sides are commands
          ;;
        'case')
          fin || return 1
          case_depth=$((case_depth + 1))
          [ "$case_depth" -gt 1 ] && return 1 # nested case: defer
          mode=casehead
          ;;
        'esac')
          fin || return 1
          case_depth=$((case_depth - 1))
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
    cwn=$((cwn + 1))
    idx=$((idx + 1))
  done

  # Finalize the trailing simple command and require a clean end state.
  [ "$mode" = normal ] || return 1
  [ "$case_depth" -eq 0 ] || return 1
  fin || return 1
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
  local -a TOK_TYPE=() TOK_VAL=()
  local TOK_N=0
  local HOOK_DEPTH=$depth
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

  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || cwd=''
  [ -n "$cwd" ] || cwd=$PWD
  local HOOK_CWD=$cwd

  analyze_command "$cmd" 0 || return 0
  emit_allow
  return 0
}

# Newline / tab constants used by the tokenizer (kept out of the case patterns
# themselves, which cannot carry a literal newline portably).
NL=$'\n'
TAB=$'\t'

# Fail safe on any unexpected signal: empty stdout, exit 0 (REQ-B1.7). The hook
# never blocks a worker's tool call.
trap 'exit 0' HUP INT TERM PIPE

main
exit 0
