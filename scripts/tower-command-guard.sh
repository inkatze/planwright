#!/usr/bin/env bash
# tower-command-guard.sh — deterministic PreToolUse auto-approve hook for the
# ORCHESTRATING TOWER (fleet-hardening Task 7; REQ-C1.1, REQ-C1.2, REQ-C1.3,
# REQ-E1.3, REQ-E1.4; D-8). Wired into config/tower-settings.json, it reads a
# Claude Code PreToolUse payload on stdin and prints a
# `permissionDecision: allow` decision for an ENUMERATED, TOWER-ORIENTED set of
# known-safe command shapes — the tower's own orchestration surface (tmux
# relay/observe, `claude --worktree` worker launches, planwright scripts by
# resolved literal path) plus the read-only state-observation shapes a tower
# reads — and DEFERS everything else to Claude Code's normal permission flow,
# fronting the stochastic `auto`-mode classifier with a tested allow layer so
# routine orchestration commands are never non-deterministically blocked.
#
# It reuses the worker-command-guard PATTERN (worker-permission-ergonomics,
# #236/#237) — same tokenizer, same allow-only / fail-closed / no-LLM security
# contract — but fronts a DISTINCT safe set (D-8, REQ-C1.2): it ADDS the
# tower-only shapes (tmux relay/observe, `claude --worktree` launches) the
# worker guard defers, and it OMITS the worker-only shapes (`bats`, `tests/`
# scripts, `fish -c` recursion) the tower does not run. The two guards are
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
#   * Escalation pins (REQ-C1.2): a `claude --worktree` launch is auto-approved
#     only when every arg is on a curated safe-flag ALLOWLIST (see guard_claude);
#     any unrecognized flag DEFERS, so the tower can never auto-approve launching
#     a worker with its permission layer disabled — this fails closed on the full
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
# Analysis model (inherited verbatim from the worker guard): the fully-expanded
# command (Claude Code expands variables before the hook sees it) is split —
# quote- and operator-aware — into segments on the control operators `;` `&&`
# `||` `|` `&` and newlines; EVERY segment's simple command must be
# independently known-safe. A command is known-safe only when its verb is on the
# tower allowlist, its flags/args designate no output/target file and enable no
# write or arbitrary execution, and it uses no construct the analyzer cannot
# confidently parse (command/process substitution, here-docs, subshell/brace
# grouping, env-assignment prefixes, path-prefixed verbs, escaped operators,
# ANSI-C quoting) — all of which defer. planwright `scripts/*.sh` are trusted
# repo/plugin code but only after their path canonicalizes INSIDE the repo
# checkout's or the installed plugin's `scripts/` directory.
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

# The fixed reason string. It is NEVER a reflection of the analyzed command:
# untrusted command content is never echoed to a terminal-driving stream.
readonly ALLOW_REASON='planwright tower-command-guard: enumerated known-safe tower orchestration / read-only command shape (deterministic, no LLM)'

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
# backslash line-continuation or escaped operator/quote. It never executes or
# expands anything it scans.
tok_push() {
  TOK_TYPE[TOK_N]=$1
  TOK_VAL[TOK_N]=$2
  TOK_QUOTED[TOK_N]=${3:-0}
  TOK_N=$((TOK_N + 1))
}

tokenize() {
  local s=$1
  local n=${#s}
  local i=0
  local cur='' have=0 curq=0
  local c nc j k dc dn fdpfx

  _flush() {
    if [ "$have" = 1 ]; then
      tok_push W "$cur" "$curq"
      cur=''
      have=0
      curq=0
    fi
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
        curq=1
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
          case $cur in
            '' | *[!0-9]*) tok_push W "$cur" "$curq" ;;
            *) [ "$curq" = 1 ] && tok_push W "$cur" "$curq" || fdpfx=$cur ;;
          esac
          cur=''
          have=0
          curq=0
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
# dev) OR the installed plugin root ($CLAUDE_PLUGIN_ROOT — the tower's resolved
# literal path under a marketplace/writer install). `tests/` is deliberately NOT
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
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && proot=$(cd "$CLAUDE_PLUGIN_ROOT" 2>/dev/null && pwd -P); then
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

# sed_script_safe <script>: 0 only when a sed script is provably read-only —
# no write (`w`/`W`), exec (`e`), or arbitrary-file-read (`r`/`R`) command, and
# no `s///` substitution whose flag block carries `w`/`W`/`e`. Inert, never
# eval-ed, deferring on ANY doubt (bare/malformed command, text-region commands
# `a`/`i`/`c`, or a `[` bracket expression that could desync the delimiter
# scan).
sed_script_safe() {
  local s=$1
  local n=${#s} i=0 c d seen
  case $s in
    *'['*) return 1 ;;
  esac
  while [ "$i" -lt "$n" ]; do
    c=${s:i:1}
    case $c in
      ' ' | "$TAB" | ';' | "$NL" | '{' | '}' | '!')
        i=$((i + 1))
        continue
        ;;
    esac
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
      --output | --output=* | --compress-program | --compress-program=*) return 1 ;;
      --*) ;;           # other long flags are read-only
      -*o*) return 1 ;; # any short-flag token carrying -o (a write target)
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

# guard_claude: the tower's worker-launch safe set — a `claude --worktree`
# dispatch. It requires the --worktree flag (the launch shape) and is an
# ALLOWLIST of known-safe launch flags: every arg must be --worktree or one of a
# curated set of benign flags, and ANY unrecognized flag or positional DEFERS
# (fail closed). REQ-C1.2 frames the pin as excluding --dangerously-skip-permissions
# / --permission-mode, but the real Claude Code launch surface carries a WIDER set
# of permission/trust-layer escalations — --allow-dangerously-skip-permissions
# (which a `--dangerously-*` / `--permission-*` denylist misses), --settings /
# --setting-sources (override the worker's settings), --mcp-config / --agents /
# --plugin-dir (inject servers/agents/plugins), --add-dir (widen filesystem) — so
# an allowlist is the only robust pin: it fails closed on every one of those AND
# on any future flag, where a denylist leaks. The dispatch primitive's own launch
# shape (`claude --worktree <suffix> [--tmux=classic] [--model <m>]`) is on the
# allowlist, so the fail-closed posture never floods a routine launch; a
# non-standard launch simply falls to the normal permission flow.
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
      --model | --fallback-model) expect_value=1 ;; # value-taking safe flags (space form)
      --model=* | --fallback-model=*) ;;            # =form: value attached
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

# classify_verb: the tower's enumerated allowlist. A bare verb (no slash) is
# looked up here; the fallthrough is DEFER. Read-only tools with NO file-write,
# code-exec, or output-to-file capability are approved with any flags; tools with
# a write/set/exec vector carry an explicit guard; the tower orchestration verbs
# (tmux, claude) carry their own tight guards; and the worker-only shapes
# (`fish`, `bats`) are deliberately ABSENT so the tower set is distinct from the
# worker set (REQ-C1.2). Every writer / command-runner / arbitrary-exec verb is
# simply absent here and so defers.
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
    # Tower orchestration surface: relay/observe and worker launches.
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
  for ((i = 0; i < rn; i++)); do
    classify_redirect "${ro[i]}" "${rt[i]}" || return 1
  done
  [ "$cwn" -ge 1 ] || return 0
  verb=${cw[0]}
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
# verified while their header/pattern regions are skipped. Any construct it
# cannot confidently place defers. Returns 0 (every simple command safe) or
# non-zero (DEFER).
verify_tokens() {
  local depth=$1
  local idx=0 typ val
  local mode=normal # normal | skip | casehead | casepat | casebody
  local case_depth=0
  local -a cw=() ro=() rt=()
  local cwn=0 rn=0

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

    if [ "$mode" = skip ]; then
      if [ "$typ" = W ] && [ "$val" = "do" ]; then
        mode=normal
      fi
      idx=$((idx + 1))
      continue
    fi
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
    if [ "$mode" = casepat ]; then
      if [ "$typ" = O ] && [ "$val" = ')' ]; then
        mode=casebody
      elif [ "$typ" = W ] && [ "$val" = "esac" ]; then
        case_depth=$((case_depth - 1))
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

    cw[cwn]=$val
    cwn=$((cwn + 1))
    idx=$((idx + 1))
  done

  [ "$mode" = normal ] || return 1
  [ "$case_depth" -eq 0 ] || return 1
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
  local -a TOK_TYPE=() TOK_VAL=() TOK_QUOTED=()
  local TOK_N=0
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

# Fail safe on any unexpected signal: empty stdout, exit 0. The hook never
# blocks the tower's tool call.
trap 'exit 0' HUP INT TERM PIPE

main
exit 0
