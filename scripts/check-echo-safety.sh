#!/usr/bin/env bash
# check-echo-safety.sh — the printf-not-echo guard over sanitized output.
#
# `scripts/echo-safety.sh` provides `sanitize_printable`, which strips C0, DEL
# and C1 control BYTES and emits through printf. That helper is correct. The
# defect lives one level up, at the call site:
#
#   echo    "... $(sanitize_printable "$x") ..."   # unsafe
#   printf '%s\n' "... $(sanitize_printable "$x") ..."   # inert
#
# The sanitizer legitimately passes the four printable characters `\` `0` `3`
# `3` through — they are printable, and stripping them would corrupt ordinary
# text. /bin/sh on Linux is dash, whose `echo` expands backslash escapes, so it
# turns that literal text back into a real ESC. Worker-authored content then
# reaches the operator's terminal with live escape sequences, through the
# scripts whose whole job is to contain it. `tests/test-check-echo-safety.sh`
# pins the mechanism; the natural objection, that the sanitizer already handles
# this, is what the failure message answers directly.
#
# Vigilance had already failed on this before the guard existed: the tree
# carried it in a hundred and ten call sites at once, including three files
# whose inline sanitizer under another name hid them from the first version of
# this scan.
#
# THE INTERPRETER IS THE HAZARD, NOT THE DIRECTORY. This is the subtlety most
# likely to be misread. Only a script run by a POSIX sh that expands echo
# escapes — dash, which is /bin/sh on Linux — is at risk. bash's `echo` does not
# expand escapes unless xpg_echo is set, so a `#!/usr/bin/env bash` script under
# scripts/ is NOT vulnerable and is skipped: flagging it would be a false
# positive and would push churn onto files that are already safe. A file with no
# shebang IS scanned, because a sourced library runs under whichever interpreter
# sourced it, and dash is one of them.
#
# What counts as an offense, all four of them sanitized text reaching a
# command that expands escapes:
#   - a sanitizer substitution anywhere inside an `echo` command's arguments,
#     at any nesting depth (an inner `printf` does not launder it: the
#     outermost command decides whether the escapes come back to life);
#   - a variable whose only assignments come from such a substitution, expanded
#     inside an `echo` — the same defect one alias away;
#   - either of those in the printf FORMAT operand, which every shell expands,
#     bash included, so it is worse than the echo it replaced;
#   - either of those passed to a printf `%b`, which expands escapes in the
#     argument.
#
# What is not an offense: a comment, a heredoc body, or a single-quoted string
# mentioning the pattern. Every file that documents this rule contains one, so
# reading them as code would make the guard flag its own explanation.
#
# Known limits, all of them the same shape — the value stops being traceable by
# reading one command:
#   - through a helper function's positional parameters (`err "$(sanitize_
#     printable "$x")"` where `err` echoes "$1"). Following that needs
#     interprocedural dataflow, not a lexical scan, and it is the gap most
#     likely to hide a real one: fix the helper, not each call site.
#   - through a second variable (`a=$(sanitize_printable "$x"); b=$a; echo
#     "$b"`). Only the first hop is followed.
#   - through `eval`, or an `echo` whose command name is itself quoted.
# Presence, not position, is checked for the variable form: an `echo` written
# above the assignment still counts.
#
# Scope is every sh-interpreted shell file under scripts/, tests/, and
# githooks/, reached either by shebang or by an .sh suffix. Neither test alone
# is enough: the githooks/ hooks are extensionless, and the sourced libraries
# carry a `# shellcheck shell=` line instead of a shebang.
#
# Usage:
#   check-echo-safety.sh [<root>]   scan the scope directories under <root>
#                                   (default: the parent of this script's dir)
#   check-echo-safety.sh --help | -h
#
# Exit codes: 0 clean, 1 an offending file, 2 usage, a broken enumeration, or a
# stale allowlist entry with no offender beside it (an offender decides the
# code when both are present; both are always reported). Anything that would make the scan cover less than it
# claims — an absent root or scope directory, an unreadable file, a `find` that
# fails partway, a scan reaching no files at all — is exit 2, never a clean
# report.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible.
set -u

LC_ALL=C
export LC_ALL

unset CDPATH

SCOPE_DIRS="scripts tests githooks"

# The allowlist. Every entry exists for one reason only: the file is open in
# another PR, so converting it here would collide. Each is expected to be fixed
# on its own branch, and this list shrinks to empty as those merge — an entry
# whose file no longer violates is reported as a stale entry and fails the
# guard, so the list cannot outlive the merges it was created for. Nothing else
# belongs here: an allowlist that quietly grows is how this defect class
# survives a guard.
ALLOWLIST="scripts/allocation-adapt.sh
scripts/allocation-ledger.sh
scripts/allocation-select.sh
scripts/fleet-attention.sh
scripts/fleet-liveness.sh
scripts/offload-dispatch.sh"

self_dir="$(cd "$(dirname "$0")" && pwd -P)"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

# Display sanitizer for untrusted content headed for the terminal (echo
# discipline, doctrine/security-posture.md). Filenames and the root argument
# both reach stderr, and on a fork PR both are attacker-authored. The inline
# fallback keeps diagnostics safe when the shared helper cannot be sourced.
sanitize_printable() {
  _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237' 2>/dev/null) || _sp=''
  if [ -z "$_sp" ] && [ $# -ge 2 ]; then
    _sp=$2
  fi
  printf '%s' "$_sp"
}
if [ -r "$self_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$self_dir/echo-safety.sh"
fi

fail_closed() {
  printf 'check-echo-safety: %s\n' "$1" >&2
  exit 2
}

# The interpreter a shebang actually selects, as a bare program name, resolving
# the `#!/usr/bin/env <prog>` form (and any env options or VAR=value operands
# before the program). Sets `interp`, empty for a file with no shebang: the
# answer is wanted once per enumerated file, and returning it through a command
# substitution would fork for every one of them. `set --` inside a function
# touches only the function's own positional parameters.
shebang_interp() {
  interp=""
  case "$1" in
    '#!'*) ;;
    *) return 0 ;;
  esac
  _si=${1#'#!'}
  # Splitting is wanted here; GLOBBING is not. A shebang is file content, so on
  # a fork PR it is attacker-authored, and `#!*/bash` would otherwise expand
  # against the working directory and could name this file bash — skipping a
  # file that dash actually runs. `set -f` makes the split word-only.
  set -f
  # shellcheck disable=SC2086 # deliberate splitting: a shebang is whitespace-separated
  set -- $_si
  set +f
  _prog=${1:-}
  if [ "${_prog##*/}" = "env" ]; then
    shift
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -* | *=*) shift ;;
        *) break ;;
      esac
    done
    _prog=${1:-}
  fi
  interp=${_prog##*/}
}

usage() {
  cat <<'EOF'
check-echo-safety.sh — flag call sites that pass `sanitize_printable` output
through `echo` instead of `printf`.

Usage:
  check-echo-safety.sh [<root>]   scan the scope directories under <root>
                                  (default: the parent of this script's dir)
  check-echo-safety.sh --help | -h

Why: `sanitize_printable` strips control BYTES, and it correctly leaves the
printable characters `\` `0` `3` `3` alone. /bin/sh on Linux is dash, whose
`echo` expands backslash escapes and turns that literal text back into a real
ESC, so untrusted content drives the operator's terminal after all. `printf`
does not expand its operands, so it is inert.

Remedy: rewrite the call site.

  echo "prefix $(sanitize_printable "$x")" >&2          # wrong
  printf 'prefix %s\n' "$(sanitize_printable "$x")" >&2  # right

Keep the sanitizer: it is what strips the control bytes. `printf` is what stops
the surviving printable escape TEXT from being re-expanded. Both are needed.
Never interpolate untrusted text into the printf FORMAT operand — a `%` in it
would be read as a conversion; pass it as an argument to `%s`.

Scanned: every sh-interpreted file under scripts/, tests/, and githooks/,
reached either by shebang or by an .sh suffix, so both the extensionless
githooks/ hooks and the sourced shebang-less libraries are covered.

Skipped: files whose shebang names bash, and nothing else. bash is the only
shell here whose `echo` leaves escapes alone (absent xpg_echo), so those files
are safe as written and rewriting them would be churn. zsh and the ksh family
are NOT skipped: their `echo` follows System V and expands escapes. A file with
NO shebang is scanned too: a sourced library runs under whichever interpreter
sourced it, and dash is one of them.

Flagged: sanitized text reaching a command that expands escapes — inside an
`echo` command's arguments at any depth (an inner `printf` does not launder an
outer `echo`), through a variable assigned only from a sanitizer then expanded
inside an `echo`, in the printf FORMAT operand, or passed to a printf `%b`.
Detection keys on the sanitizer family, so an inline copy under another name
counts. Comments, heredoc bodies and single-quoted strings are prose, not
calls, and are never flagged.

Not flagged: a value reaching `echo` through a helper function's positional
parameters. That needs interprocedural dataflow, not a lexical scan.

Allowlist: a short, in-script list of exact repo-relative paths, each present
only because that file is open in another pull request. It shrinks to empty as
those merge, and an entry whose file no longer violates is reported as stale
and fails the guard rather than lingering. An entry whose file is absent under
the scanned root is simply not applicable and is skipped.

Exit codes: 0 clean, 1 an offending file, 2 usage, a broken enumeration, or a
stale allowlist entry with no offender beside it. Both are always reported;
when both are present the offender decides the code.
EOF
}

case "${1:-}" in
  --help | -h)
    [ "$#" -eq 1 ] || fail_closed "--help takes no other arguments"
    usage
    exit 0
    ;;
  -*)
    fail_closed "unknown option: $(sanitize_printable "$1" "(unprintable)") (see --help)"
    ;;
esac

[ "$#" -le 1 ] || fail_closed "too many arguments (expected at most one root)"

root="${1:-$repo_root}"
safe_root="$(sanitize_printable "$root" "(unprintable path)")"
[ -d "$root" ] || fail_closed "root not found or not a directory: $safe_root"

missing=""
for dir in $SCOPE_DIRS; do
  [ -d "$root/$dir" ] || missing="$missing $dir"
done
[ -z "$missing" ] \
  || fail_closed "scope directories missing under $safe_root:$missing — the scan would cover less than it claims"

# Explicit template (the house pattern, see scripts/check-hook-contracts.sh): a
# bare `mktemp -d` relies on a default template BSD mktemp does not supply, so
# it fails outright on the macOS half of the support bar this script claims.
work="$(mktemp -d "${TMPDIR:-/tmp}/check-echo-safety.XXXXXX")" \
  || fail_closed "could not create a temporary directory"
trap 'rm -rf "$work"' EXIT
: >"$work/all"

# Enumerate one scope directory at a time so a root containing whitespace or a
# glob character stays a single argument, and so a find that fails partway is
# caught instead of silently contributing nothing. The walk is physical and
# takes symlinks as leaves rather than following them: a symlinked script still
# runs, so it still has to be scanned, but descending through a symlinked
# directory would walk a tree outside the root and report its files as if they
# lived here. Those are refused below instead.
for dir in $SCOPE_DIRS; do
  if ! find -P "$root/$dir" \( -type f -o -type l \) -print0 >>"$work/all" 2>"$work/err"; then
    fail_closed "find failed under $safe_root/$dir: $(sanitize_printable "$(cat "$work/err")" "(unprintable)")"
  fi
done

# Select the shell files. The enumeration is NUL-delimited so a filename
# containing a newline survives it intact; such a name is then refused rather
# than skipped, because the file list awk reads is newline-delimited and a
# silently dropped file is the failure this guard exists to prevent.
: >"$work/list"
count=0
skipped=0
dropped=0
newline='
'
tab="$(printf '\t')"
while IFS= read -r -d '' file; do
  rel="${file#"$root"/}"
  # Sanitizing forks, so it happens only on the paths that actually reach the
  # terminal, never once per enumerated file.
  # A newline or a tab in a filename would be swallowed by the newline-
  # delimited file list or by the tab-delimited offender records below.
  # Refusing is the fail-closed answer; silently skipping is not.
  case "$file" in
    *"$newline"* | *"$tab"*)
      fail_closed "filename contains a newline or tab, refusing to scan: $(sanitize_printable "$rel" "(unprintable filename)")"
      ;;
  esac
  # A symlink is followed only to a regular file. A symlinked directory has no
  # honest traversal (following it leaves the root; skipping it covers less
  # than the scan claims), and a symlink to a FIFO or a character device is
  # worse than either: reading it blocks forever with no writer, or never ends
  # on /dev/zero, so the guard hangs instead of answering. -r rules out none of
  # these — the thing behind the link reads fine.
  if [ -L "$file" ] && [ ! -f "$file" ]; then
    fail_closed "symlink in the scan scope does not resolve to a regular file, refusing to follow: $(sanitize_printable "$rel" "(unprintable filename)")"
  fi
  [ -r "$file" ] \
    || fail_closed "cannot read $(sanitize_printable "$rel" "(unprintable filename)") — the scan would cover less than it claims"
  first=""
  IFS= read -r first <"$file" 2>/dev/null || true
  case "$first" in
    '#!'*) ;;
    *) case "$file" in
      *.sh) ;;
      *)
        dropped=$((dropped + 1))
        continue
        ;;
    esac ;;
  esac
  # bash is the ONLY interpreter here whose `echo` leaves backslash escapes
  # alone (absent xpg_echo), so a bash file is safe as written and is counted
  # rather than scanned. zsh and the ksh family are deliberately not exempt:
  # their `echo` follows System V and expands escapes, so they are as exposed
  # as dash. Everything else — sh, dash, an unrecognised shebang, or no shebang
  # at all — is scanned too, because a sourced library inherits whichever
  # interpreter sourced it and an unknown one must be assumed hazardous.
  shebang_interp "$first"
  case "$interp" in
    bash)
      skipped=$((skipped + 1))
      continue
      ;;
  esac
  printf '%s\n' "$file" >>"$work/list"
  count=$((count + 1))
done <"$work/all"

[ "$count" -gt 0 ] \
  || fail_closed "no sh-interpreted shell files found under $SCOPE_DIRS in $safe_root — a broken enumeration, not a clean tree"

# One awk pass over the whole list, as a shell tokenizer rather than a line
# regex. Nothing weaker distinguishes the four shapes that matter: an `echo` is
# only an `echo` at a command position (`true | echo`, `then echo`, `command
# echo`), a `$(` inside a double-quoted string opens a fresh unquoted context,
# a `#` is a comment only at a word boundary outside quotes, and a heredoc body
# is not code at all. Every one of those is a false positive or a miss for a
# grep. Files are opened by getline rather than through ARGV, so a name
# containing `=` or a leading `-` is read as a path, never as an awk variable
# assignment or option.
awk -v listfile="$work/list" '
  function is_echo_ancestor(d,   j) {
    for (j = 0; j <= d; j++) if (cmd[j] == "echo") return 1
    return 0
  }
  # printf expands escapes in its FORMAT operand in every shell, so the
  # remedy this guard prescribes has an unsafe spelling of its own:
  # `printf "$(sanitize_printable "$x")\n"` is worse than the echo it replaced.
  # Untrusted text belongs in a %s argument, never in the format.
  function is_fmt_ancestor(d,   j) {
    for (j = 0; j <= d; j++) if (cmd[j] == "printf" && argn[j] == 1) return 1
    return 0
  }
  # `%b` is the other unsafe printf spelling: it expands escapes in the
  # ARGUMENT, so `printf %b "$safe"` revives exactly what %s leaves inert.
  function is_pctb_ancestor(d,   j) {
    for (j = 0; j <= d; j++) if (cmd[j] == "printf" && fmtb[j] && argn[j] > 1) return 1
    return 0
  }
  # An assignment is only over when something terminates it at ITS OWN depth. A
  # command word inside its right-hand side — which is exactly where the
  # sanitizer call sits in `safe="$(sanitize_printable "$x")"` — must not close
  # it, or the assignment is filed as untainted before the call is seen.
  function finish_assign(d) {
    if (pend_assign != "" && d <= pend_depth) {
      if (pend_san) sanvar[pend_assign] = 1; else othervar[pend_assign] = 1
      pend_assign = ""; pend_san = 0; pend_depth = 0
    }
  }
  function push_depth(bt) {
    # A file with hundreds of unclosed `$(` is not shell anyone wrote, and the
    # per-depth arrays grow with it. Refusing is the fail-closed answer.
    if (depth >= 400) { toodeep = 1; return }
    depth++
    savedq[depth] = dq; savesq[depth] = sq; isbt[depth] = bt
    dq = 0; sq = 0; cmd[depth] = ""; atcmd = 1; argn[depth] = 0; inarg[depth] = 0; fmtb[depth] = 0; redirpend[depth] = 0
  }
  function pop_depth() {
    if (depth <= 0) return
    dq = savedq[depth]; sq = savesq[depth]
    depth--; atcmd = 0
  }
  function record_ref(name, ln) {
    if (name == "") return
    if (is_echo_ancestor(depth)) { nref++; refname[nref] = name; refline[nref] = ln; refkind[nref] = "variable"; return }
    if (is_fmt_ancestor(depth)) { nref++; refname[nref] = name; refline[nref] = ln; refkind[nref] = "format"; return }
    if (is_pctb_ancestor(depth)) { nref++; refname[nref] = name; refline[nref] = ln; refkind[nref] = "percentb" }
  }
  function word_at_cmd(w, ln) {
    if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
      finish_assign(depth)
      pend_assign = w; sub(/=.*$/, "", pend_assign); pend_san = 0; pend_depth = depth
      return
    }
    # `case` and `esac` are transparent keywords, but the pattern list between
    # them changes what a `)` means, so the construct is tracked before the
    # keyword is waved through.
    if (w == "case") { ncase++; casedep[ncase] = depth; return }
    if (w == "esac") { if (ncase > 0) ncase--; return }
    if (w in transparent) return
    if (cmd[depth] == "" && w ~ /^-/) return
    finish_assign(depth)
    cmd[depth] = w
    atcmd = 0; argn[depth] = 0; inarg[depth] = 1; fmtb[depth] = 0
    redirpend[depth] = 0; pctesc[depth] = 0
    # Keyed on the sanitizer FAMILY, not one spelling. spec-scope.sh and
    # spec-assemble.sh carry inline copies named sanitize_echo, and a guard
    # that matched only the canonical name reported both files clean over
    # eight live call sites.
    if (w ~ /^sanitize_/) {
      if (pend_assign != "" && depth > pend_depth) pend_san = 1
      if (depth > 0 && is_echo_ancestor(depth - 1)) hits[ln] = "direct"
      else if (depth > 0 && is_fmt_ancestor(depth - 1)) hits[ln] = "format"
      else if (depth > 0 && is_pctb_ancestor(depth - 1)) hits[ln] = "percentb"
    }
  }
  function is_wordstart(p) {
    return (p == "" || p == " " || p == "\t" || p == "\n" || p == ";" \
      || p == "&" || p == "|" || p == "(" || p == ")" || p == "{" || p == "}")
  }
  # Consumes a heredoc operator and returns the index just past it, recording
  # the delimiter so the body can be skipped. Getting the delimiter charset
  # wrong is not a near miss: too narrow and `<<EOF-1` never sees its
  # terminator and swallows the rest of the file; too eager and `<<<` (a
  # herestring, no body) swallows it instead.
  function heredoc_op(s, i,   j, c, dash, delim, q, n) {
    n = length(s); j = i + 2
    if (substr(s, j, 1) == "<") return j + 1
    dash = 0
    if (substr(s, j, 1) == "-") { dash = 1; j++ }
    while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
    delim = ""; c = substr(s, j, 1)
    if (c == "\\") { j++; c = substr(s, j, 1) }
    if (c == "\"" || c == "\047") {
      q = c; j++
      while (j <= n && substr(s, j, 1) != q) { delim = delim substr(s, j, 1); j++ }
      j++
    } else {
      # A delimiter is an ordinary word. Restricting it to a word-character
      # charset refuses real shell: `<<!EOF!` and `<<EOF:1` both ship in
      # scripts on a stock system, and refusing them fails a clean tree.
      while (j <= n && index(" \t<>&|;()\"\047`", substr(s, j, 1)) == 0) {
        delim = delim substr(s, j, 1); j++
      }
    }
    # A `<<` whose delimiter matches nothing leaves the body extent unknown,
    # so the body would be read as code. Refusing beats guessing.
    if (delim == "") { baddelim = 1; return j }
    pend_heredoc = delim; pend_dash = dash
    return j
  }
  function tokenize(s, ln,   n, i, c, c2, w, name, j, rest) {
    n = length(s); i = 1; prev = "\n"
    if (esc) esc = 0
    while (i <= n) {
      c = substr(s, i, 1)
      # Track which argument of the current command we are inside, so the
      # format operand (argument 1) can be told from the %s operands after it.
      if (!sq && !dq && !esc) {
        if (c == " " || c == "\t") inarg[depth] = 0
        else if (cmd[depth] != "" && !inarg[depth]) {
          inarg[depth] = 1
          # A redirection target is not an argument. Counting it shifts every
          # later operand by one, and `printf >&2 "..."` — house style here —
          # then hides its format operand from the format check entirely.
          if (redirpend[depth]) redirpend[depth] = 0
          else argn[depth]++
        }
        if (c == ">" || c == "<") {
          if (inarg[depth]) { argn[depth]--; inarg[depth] = 0 }
          redirpend[depth] = 1
        }
      }
      # Checked regardless of quote state: the format operand is normally a
      # quoted literal, which the branches below skip over wholesale.
      if (cmd[depth] == "printf" && argn[depth] == 1 && c == "%") {
        if (pctesc[depth]) {
          pctesc[depth] = 0            # the second `%` of a literal `%%`
        } else {
          pctesc[depth] = 1
          k = i + 1
          while (k <= n && index("-+ #0123456789.*\047", substr(s, k, 1)) > 0) k++
          if (substr(s, k, 1) == "b") fmtb[depth] = 1
        }
      } else if (c != "%") {
        pctesc[depth] = 0
      }
      if (esc) { esc = 0; prev = c; i++; continue }
      if (c == "\\") {
        if (sq) { prev = c; i++; continue }
        esc = 1; i++; continue
      }
      if (sq) { if (c == "\047") sq = 0; prev = c; i++; continue }
      if (c == "\047" && !dq) { sq = 1; prev = c; i++; continue }
      if (c == "\"") { dq = !dq; prev = c; i++; continue }
      # Expansions stay live inside double quotes, which is exactly why the
      # defect hides there.
      if (c == "$") {
        c2 = substr(s, i + 1, 1)
        if (c2 == "(") {
          if (substr(s, i + 2, 1) == "(") {
            push_depth(0); push_depth(0)
            cmd[depth] = "#arith"; cmd[depth - 1] = "#arith"; atcmd = 0
            prev = "("; i += 3; continue
          }
          push_depth(0); prev = "("; i += 2; continue
        }
        if (c2 == "{") {
          # The FIRST `}` is the wrong one for a nested expansion: the POSIX
          # trim idiom `${x#"${x%%[! ]*}"}` closes an inner brace there, and
          # resuming after it re-reads the tail as code, where a stray quote
          # flips the string state for the rest of the file — a silent miss,
          # or a bogus unterminated-string refusal.
          bdepth = 1; j = 0
          for (k = i + 2; k <= n; k++) {
            ch = substr(s, k, 1)
            if (ch == "{") bdepth++
            else if (ch == "}") { bdepth--; if (bdepth == 0) { j = k - i - 1; break } }
          }
          rest = substr(s, i + 2)
          name = (j > 0) ? substr(rest, 1, j - 1) : rest
          # `${#v}` expands to a LENGTH and `${!v}` to a NAME. Neither carries
          # the sanitized value, so neither is content reaching the command.
          if (name ~ /^[#!]/) name = ""
          sub(/[^A-Za-z0-9_].*$/, "", name)
          record_ref(name, ln)
          # `${x:-$(sanitize_printable "$y")}` is a live substitution. Skipping
          # the word whole would step straight over it, so when the body holds
          # one, resume scanning just past the name instead.
          body = (j > 0) ? substr(rest, 1, j - 1) : rest
          if (index(body, "$(") > 0 || index(body, "`") > 0) {
            i += 2 + length(name); prev = "x"; continue
          }
          i += (j > 0) ? (2 + j) : (n + 1)
          prev = "}"; continue
        }
        if (c2 ~ /[A-Za-z_]/) {
          name = substr(s, i + 1)
          sub(/[^A-Za-z0-9_].*$/, "", name)
          record_ref(name, ln)
          i += 1 + length(name); prev = "x"; continue
        }
        prev = c; i++; continue
      }
      if (c == "`") {
        if (depth > 0 && isbt[depth]) pop_depth(); else push_depth(1)
        prev = "`"; i++; continue
      }
      if (dq) { prev = c; i++; continue }
      if (c == "#" && is_wordstart(prev)) break
      if (c == "(") {
        if (atcmd && substr(s, i + 1, 1) == "(") {
          push_depth(0); push_depth(0)
          cmd[depth] = "#arith"; cmd[depth - 1] = "#arith"; atcmd = 0
          prev = "("; i += 2; continue
        }
        # The optional open paren of a case pattern — `(a) cmd ...` — opens no
        # subshell. Pushing a depth for it desynchronises the stack and the
        # command in that arm is then read as an argument.
        if (ncase > 0 && depth == casedep[ncase] && atcmd) { prev = c; i++; continue }
        push_depth(0); prev = c; i++; continue
      }
      # In `a) echo ...`, the `)` ends a case PATTERN and opens a command
      # position; it closes nothing. Reading it as a paren close leaves the
      # echo inside that arm parsed as an argument, and every case arm goes
      # unchecked — which is exactly what it did before this was tracked.
      if (c == ")") {
        if (ncase > 0 && depth == casedep[ncase]) {
          finish_assign(depth); cmd[depth] = ""; atcmd = 1; redirpend[depth] = 0
        } else if (depth > 0) {
          pop_depth()
        } else {
          finish_assign(depth); cmd[depth] = ""; atcmd = 1; redirpend[depth] = 0
        }
        prev = c; i++; continue
      }
      if (c == "{" && is_wordstart(prev)) {
        finish_assign(depth); cmd[depth] = ""; atcmd = 1; redirpend[depth] = 0; prev = c; i++; continue
      }
      # `>&2` and `2>&1`: the `&` is part of the redirection, not a control
      # operator. Resetting on it makes `echo >&2 "..."` parse `2` as the
      # command word, and the echo is never seen — a spelling this repo uses.
      if (c == "&" && (prev == ">" || prev == "<")) { prev = c; i++; continue }
      if (c == ";" || c == "&" || c == "|") {
        finish_assign(depth); cmd[depth] = ""; atcmd = 1; redirpend[depth] = 0; prev = c; i++; continue
      }
      if (c == "<" && substr(s, i + 1, 1) == "<" && cmd[depth] != "#arith") {
        # The delimiter is the operator operand and is consumed here, so the
        # redirect is complete; leaving it pending would eat the next word.
        i = heredoc_op(s, i); redirpend[depth] = 0; prev = "H"; continue
      }
      # Scanned forward rather than matched against substr(s, i): that copies
      # the whole line remainder once per word token, which is quadratic in the
      # line length and reachable from a file a fork PR authors.
      j = i
      while (j <= n && index(STOP, substr(s, j, 1)) == 0) j++
      if (j > i) {
        w = substr(s, i, j - i)
        if (w == "--" && argn[depth] == 1) argn[depth]--
        if (atcmd) word_at_cmd(w, ln)
        i = j; prev = "w"; continue
      }
      prev = c; i++
    }
  }
  function scan(path,   line, r, body, ln, maxln, k) {
    sq = 0; dq = 0; esc = 0; depth = 0; atcmd = 1; prev = "\n"
    split("", cmd); split("", savedq); split("", savesq); split("", isbt)
    split("", sanvar); split("", othervar); split("", refname); split("", refline)
    split("", hits)
    cmd[0] = ""; nref = 0; ncase = 0; split("", casedep); split("", argn); split("", inarg); split("", refkind); split("", fmtb); split("", redirpend); split("", pctesc)
    toodeep = 0; baddelim = 0
    pend_assign = ""; pend_san = 0; pend_depth = 0
    heredoc = ""; heredoc_dash = 0; pend_heredoc = ""; pend_dash = 0
    maxln = 0
    # getline returns -1 when the file cannot be opened or read, which is not
    # end-of-input. Treating the two alike would silently clear a file the scan
    # never saw, reachable as a TOCTOU race against the readability check the
    # selection loop already made.
    while ((r = (getline line < path)) > 0) {
      maxln++
      sub(/\r$/, "", line)
      if (heredoc != "") {
        body = line
        if (heredoc_dash) sub(/^\t+/, "", body)
        # `V=`cat <<EOF ... EOF`` closes the substitution on the terminator
        # line. The terminator is still the terminator; only the closer that
        # follows it belongs to the enclosing command.
        term = body
        sub(/[`)]+[ \t]*$/, "", term)
        if (body == heredoc || term == heredoc) heredoc = ""
        continue
      }
      tokenize(line, maxln)
      if (esc) {
        esc = 0
      } else if (sq || dq) {
        # An unterminated string carries the command onto the next line.
      } else {
        finish_assign(depth); cmd[depth] = ""; atcmd = 1; redirpend[depth] = 0
      }
      if (pend_heredoc != "") {
        heredoc = pend_heredoc; heredoc_dash = pend_dash; pend_heredoc = ""
      }
    }
    close(path)
    if (r < 0) { print "!\t0\tunreadable\t" path; return }
    if (toodeep) { print "!\t0\ttoodeep\t" path; return }
    # Reaching EOF inside a heredoc body or an unterminated string means the
    # rest of the file was never read as code. Reporting clean over it is the
    # silent-undercoverage failure the contract here rules out.
    if (baddelim) { print "!\t0\tbaddelim\t" path; return }
    if (heredoc != "" || sq || dq) { print "!\t0\tunterminated\t" path; return }
    finish_assign(0)
    # A variable is evidence only when every assignment to it came from the
    # sanitizer. One assignment from anywhere else and the name no longer says
    # anything about what reaches the echo, and guessing there is how a guard
    # starts crying wolf.
    for (k = 1; k <= nref; k++) {
      if ((refname[k] in sanvar) && !(refname[k] in othervar)) {
        if (!(refline[k] in hits)) hits[refline[k]] = refkind[k]
      }
    }
    for (ln = 1; ln <= maxln; ln++) {
      if (ln in hits) print path "\t" ln "\t" hits[ln]
    }
  }
  BEGIN {
    split("if then else elif fi do done while until for case esac in select " \
      "function time command builtin exec nohup env ! { } [[ " \
      "local export readonly typeset declare", tw, " ")
    for (t in tw) transparent[tw[t]] = 1
    # The characters that end a bare word. Held as a string so the scan can ask
    # index() per character instead of running a regex over the line remainder.
    STOP = " \t;&|()<>{}\"\047$#`\\"
    while ((lr = (getline path < listfile)) > 0) scan(path)
    # An unreadable list is not an empty one; reporting clean over it would be
    # the same vacuous pass the scan-side check refuses.
    if (lr < 0) print "!\t0\tunreadable\t" listfile
  }
' >"$work/offenders" 2>"$work/awkerr" \
  || fail_closed "the scan could not complete: $(sanitize_printable "$(cat "$work/awkerr")" "(unprintable diagnostic)")"
# awk names the offending path in its own diagnostics, and a filename is
# attacker-authored on a fork PR. Every other print path here is sanitized;
# this one would not be if it went straight to the terminal.
if [ -s "$work/awkerr" ]; then
  fail_closed "the scan reported a diagnostic: $(sanitize_printable "$(cat "$work/awkerr")" "(unprintable diagnostic)")"
fi

: >"$work/allowed-hit"
# An unquoted heredoc body would run command substitution on the allowlist. It
# holds plain paths today, but it is explicitly meant to be edited, and an
# entry carrying a backtick must not be executed by the guard reading it.
printf '%s\n' "$ALLOWLIST" >"$work/allowlist"
status=0
while IFS="$(printf '\t')" read -r file lineno kind extra; do
  [ -n "$file" ] || continue
  if [ "$file" = "!" ]; then
    case "$kind" in
      unterminated)
        fail_closed "$(sanitize_printable "${extra#"$root"/}" "(unprintable filename)") ends inside a heredoc or an unterminated string — the scan did not read all of it as code, so it cannot report it clean"
        ;;
      baddelim)
        fail_closed "$(sanitize_printable "${extra#"$root"/}" "(unprintable filename)") opens a heredoc whose delimiter the scan cannot parse — the body's extent is unknown, so it cannot report it clean"
        ;;
    esac
    if [ "$kind" = "toodeep" ]; then
      fail_closed "nesting depth in $(sanitize_printable "${extra#"$root"/}" "(unprintable filename)") exceeds what the scan will follow — refusing rather than reporting a file it did not finish reading"
    fi
    fail_closed "could not read $(sanitize_printable "${extra#"$root"/}" "(unprintable filename)") during the scan — the scan would cover less than it claims"
  fi
  rel="${file#"$root"/}"
  case "$newline$ALLOWLIST$newline" in
    *"$newline$rel$newline"*)
      printf '%s\n' "$rel" >>"$work/allowed-hit"
      continue
      ;;
  esac
  safe_rel="$(sanitize_printable "$rel" "(unprintable filename)")"
  case "$kind" in
    format)
      printf 'check-echo-safety: %s:%s puts sanitized output in the printf FORMAT operand; pass it as a %s argument instead\n' \
        "$safe_rel" "$lineno" "'%s'" >&2
      ;;
    percentb)
      printf 'check-echo-safety: %s:%s passes sanitized output to a printf %s conversion, which expands escapes in the argument; use %s\n' \
        "$safe_rel" "$lineno" "'%b'" "'%s'" >&2
      ;;
    variable)
      printf 'check-echo-safety: %s:%s echoes a variable holding sanitized output; print it with printf instead\n' \
        "$safe_rel" "$lineno" >&2
      ;;
    *)
      printf 'check-echo-safety: %s:%s passes sanitized output through echo; print it with printf instead\n' \
        "$safe_rel" "$lineno" >&2
      ;;
  esac
  status=1
done <"$work/offenders"

# The allowlist's own fail-closed rule. An entry whose file is present and no
# longer violates has done its job, and leaving it in place is how a temporary
# exemption becomes a permanent one. An entry whose file is absent under this
# root is simply not applicable (a fixture tree, or a deleted script) and is
# skipped without comment.
allowed=0
stale=""
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  [ -e "$root/$entry" ] || continue
  if grep -qxF -- "$entry" "$work/allowed-hit"; then
    allowed=$((allowed + 1))
  else
    stale="$stale $entry"
  fi
done <"$work/allowlist"

# A stale entry is a bookkeeping error and a real offender is a security
# defect, so when both are present the offender decides the exit code. Reported
# either way: reporting only the bookkeeping would bury the defect under it.
if [ -n "$stale" ]; then
  printf 'check-echo-safety: allowlist entries no longer violate and must be removed —%s (each exists only while its file is open in another pull request; the allowlist shrinks to empty)\n' \
    "$(sanitize_printable "$stale" " (unprintable)")" >&2
  [ "$status" -ne 0 ] || exit 2
fi

if [ "$status" -ne 0 ]; then
  printf 'check-echo-safety: the sanitizer strips control BYTES but keeps backslashes, so a PRINTABLE-ONLY argument still reaches the terminal as a live ESC under dash. See --help for the remedy.\n' >&2
fi

if [ "$status" -eq 0 ]; then
  printf 'check-echo-safety: clean (%s files scanned, of which %s allowlisted; %s bash-interpreter files not at risk, %s not shell)\n' \
    "$count" "$allowed" "$skipped" "$dropped"
fi
exit "$status"
