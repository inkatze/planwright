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
# scripts whose whole job is to contain it. This is reproduced, not theoretical:
# a genuine ESC byte reaches stderr from a PRINTABLE-ONLY argument, which is why
# "the sanitizer already handles this" is the wrong answer.
#
# The class has been reintroduced repeatedly, including by an author whose
# brief warned about it by name. Vigilance has demonstrably failed, which is
# what makes this a guard rather than a review note.
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
# What counts as an offense:
#   - a `sanitize_printable` command substitution appearing anywhere inside an
#     `echo` command's arguments, at any nesting depth (an inner `printf` does
#     not launder it: the outermost command decides whether the escapes come
#     back to life);
#   - a variable whose only assignments come from such a substitution, expanded
#     inside an `echo` — the same defect one alias away.
#
# What is not an offense: a comment, a heredoc body, or a single-quoted string
# mentioning the pattern. Every file that documents this rule contains one, so
# reading them as code would make the guard flag its own explanation.
#
# Known limit: a value that reaches `echo` through a helper function's
# positional parameters (`fail_closed "$(sanitize_printable "$x")"` where
# `fail_closed` echoes "$1") is not detected. Following it needs interprocedural
# dataflow rather than a lexical scan. Presence, not position, is checked for
# the variable form: an `echo` written above the assignment still counts.
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
# stale allowlist entry. Anything that would make the scan cover less than it
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
# before the program). Empty for a file with no shebang. `set --` inside a
# function touches only the function's own positional parameters.
shebang_interp() {
  case "$1" in
    '#!'*) ;;
    *)
      printf ''
      return 0
      ;;
  esac
  _si=${1#'#!'}
  # shellcheck disable=SC2086 # deliberate splitting: a shebang is whitespace-separated
  set -- $_si
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
  printf '%s' "${_prog##*/}"
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

  echo "prefix $(sanitize_printable "$x")" >&2
  printf 'prefix %s\n' "$(sanitize_printable "$x")" >&2

Keep the sanitizer: it is what strips the control bytes. `printf` is what stops
the surviving printable escape TEXT from being re-expanded. Both are needed.
Never interpolate untrusted text into the printf FORMAT operand — a `%` in it
would be read as a conversion; pass it as an argument to `%s`.

Scanned: every sh-interpreted file under scripts/, tests/, and githooks/,
reached either by shebang or by an .sh suffix, so both the extensionless
githooks/ hooks and the sourced shebang-less libraries are covered.

Skipped: files whose shebang names bash, zsh or ksh. Only an interpreter that
expands echo escapes is at risk, and bash does not unless xpg_echo is set, so
those files are safe as written and rewriting them would be churn. A file with
NO shebang is scanned, not skipped: a sourced library runs under whichever
interpreter sourced it, and dash is one of them.

Flagged: a `sanitize_printable` substitution inside an `echo` command's
arguments at any depth (an inner `printf` does not launder an outer `echo`),
and a variable assigned only from such a substitution then expanded inside an
`echo`. Comments, heredoc bodies and single-quoted strings are prose, not
calls, and are never flagged.

Not flagged: a value reaching `echo` through a helper function's positional
parameters. That needs interprocedural dataflow, not a lexical scan.

Allowlist: a short, in-script list of exact repo-relative paths, each present
only because that file is open in another pull request. It shrinks to empty as
those merge, and an entry whose file no longer violates is reported as stale
and fails the guard rather than lingering.

Exit codes: 0 clean, 1 an offending file, 2 usage, a broken enumeration, or a
stale allowlist entry.
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
newline='
'
tab="$(printf '\t')"
while IFS= read -r -d '' file; do
  rel="${file#"$root"/}"
  # Sanitizing is three forks, so it happens only on the paths that actually
  # reach the terminal, never once per enumerated file.
  case "$file" in
    *"$newline"* | *"$tab"*)
      fail_closed "filename contains a newline or tab, refusing to scan: $(sanitize_printable "$rel" "(unprintable filename)")"
      ;;
  esac
  # A symlinked directory has no honest traversal: following it leaves the
  # root, and skipping it covers less than the scan claims. -r would not catch
  # it either, since the directory behind it reads fine.
  if [ -L "$file" ] && [ -d "$file" ]; then
    fail_closed "symlinked directory in the scan scope, refusing to follow: $(sanitize_printable "$rel" "(unprintable filename)")"
  fi
  [ -r "$file" ] \
    || fail_closed "cannot read $(sanitize_printable "$rel" "(unprintable filename)") — the scan would cover less than it claims"
  first=""
  IFS= read -r first <"$file" 2>/dev/null || true
  case "$first" in
    '#!'*) ;;
    *) case "$file" in
      *.sh) ;;
      *) continue ;;
    esac ;;
  esac
  # Only an interpreter that expands echo escapes is at risk. bash, zsh and ksh
  # do not (absent xpg_echo), so their files are safe as written and are counted
  # rather than scanned. Everything else — sh, dash, an unrecognised shebang, or
  # no shebang at all — is scanned, because a sourced library inherits whichever
  # interpreter sourced it and an unknown one has to be assumed hazardous.
  case "$(shebang_interp "$first")" in
    bash | zsh | ksh | ksh93 | mksh | pdksh)
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
    depth++
    savedq[depth] = dq; savesq[depth] = sq; isbt[depth] = bt
    dq = 0; sq = 0; cmd[depth] = ""; atcmd = 1
  }
  function pop_depth() {
    if (depth <= 0) return
    dq = savedq[depth]; sq = savesq[depth]
    depth--; atcmd = 0
  }
  function record_ref(name, ln) {
    if (name == "") return
    if (!is_echo_ancestor(depth)) return
    nref++; refname[nref] = name; refline[nref] = ln
  }
  function word_at_cmd(w, ln) {
    if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
      finish_assign(depth)
      pend_assign = w; sub(/=.*$/, "", pend_assign); pend_san = 0; pend_depth = depth
      return
    }
    if (w in transparent) return
    finish_assign(depth)
    cmd[depth] = w
    atcmd = 0
    if (w == "sanitize_printable") {
      if (pend_assign != "" && depth > pend_depth) pend_san = 1
      if (depth > 0 && is_echo_ancestor(depth - 1)) hits[ln] = "direct"
    }
  }
  function is_wordstart(p) {
    return (p == "" || p == " " || p == "\t" || p == "\n" || p == ";" \
      || p == "&" || p == "|" || p == "(" || p == "{" || p == "}")
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
      while (j <= n && substr(s, j, 1) ~ /[A-Za-z0-9_.+-]/) { delim = delim substr(s, j, 1); j++ }
    }
    if (delim != "") { pend_heredoc = delim; pend_dash = dash }
    return j
  }
  function tokenize(s, ln,   n, i, c, c2, w, name, j, rest) {
    n = length(s); i = 1; prev = "\n"
    if (esc) esc = 0
    while (i <= n) {
      c = substr(s, i, 1)
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
          rest = substr(s, i + 2); j = index(rest, "}")
          name = (j > 0) ? substr(rest, 1, j - 1) : rest
          sub(/^[#!]/, "", name)
          sub(/[^A-Za-z0-9_].*$/, "", name)
          record_ref(name, ln)
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
      if (c == "(") { push_depth(0); prev = c; i++; continue }
      if (c == ")") { pop_depth(); prev = c; i++; continue }
      if (c == "{" && is_wordstart(prev)) {
        finish_assign(depth); cmd[depth] = ""; atcmd = 1; prev = c; i++; continue
      }
      if (c == ";" || c == "&" || c == "|") {
        finish_assign(depth); cmd[depth] = ""; atcmd = 1; prev = c; i++; continue
      }
      if (c == "<" && substr(s, i + 1, 1) == "<" && cmd[depth] != "#arith") {
        i = heredoc_op(s, i); prev = "H"; continue
      }
      if (match(substr(s, i), "^[^ \t;&|()<>{}\"\047$#`\\\\]+")) {
        w = substr(s, i, RLENGTH)
        if (atcmd) word_at_cmd(w, ln)
        i += RLENGTH; prev = "w"; continue
      }
      prev = c; i++
    }
  }
  function scan(path,   line, r, body, ln, maxln, k) {
    sq = 0; dq = 0; esc = 0; depth = 0; atcmd = 1; prev = "\n"
    split("", cmd); split("", savedq); split("", savesq); split("", isbt)
    split("", sanvar); split("", othervar); split("", refname); split("", refline)
    split("", hits)
    cmd[0] = ""; nref = 0
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
        if (body == heredoc) heredoc = ""
        continue
      }
      tokenize(line, maxln)
      if (esc) {
        esc = 0
      } else if (sq || dq) {
        # An unterminated string carries the command onto the next line.
      } else {
        finish_assign(depth); cmd[depth] = ""; atcmd = 1
      }
      if (pend_heredoc != "") {
        heredoc = pend_heredoc; heredoc_dash = pend_dash; pend_heredoc = ""
      }
    }
    close(path)
    if (r < 0) { print "!\t0\tunreadable\t" path; return }
    finish_assign(0)
    # A variable is evidence only when every assignment to it came from the
    # sanitizer. One assignment from anywhere else and the name no longer says
    # anything about what reaches the echo, and guessing there is how a guard
    # starts crying wolf.
    for (k = 1; k <= nref; k++) {
      if ((refname[k] in sanvar) && !(refname[k] in othervar)) {
        if (!(refline[k] in hits)) hits[refline[k]] = "variable"
      }
    }
    for (ln = 1; ln <= maxln; ln++) {
      if (ln in hits) print path "\t" ln "\t" hits[ln]
    }
  }
  BEGIN {
    split("if then else elif fi do done while until for case esac in select " \
      "function time command builtin exec nohup env ! { } [[", tw, " ")
    for (t in tw) transparent[tw[t]] = 1
    while ((lr = (getline path < listfile)) > 0) scan(path)
    # An unreadable list is not an empty one; reporting clean over it would be
    # the same vacuous pass the scan-side check refuses.
    if (lr < 0) print "!\t0\tunreadable\t" listfile
  }
' >"$work/offenders" || fail_closed "the scan could not complete"

: >"$work/allowed-hit"
status=0
while IFS="$(printf '\t')" read -r file lineno kind extra; do
  [ -n "$file" ] || continue
  if [ "$file" = "!" ]; then
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
  if [ "$kind" = "variable" ]; then
    printf 'check-echo-safety: %s:%s echoes a variable holding sanitize_printable output; use printf '"'"'%%s\\n'"'"' instead — the sanitizer strips control BYTES but keeps backslashes, so a PRINTABLE-ONLY argument still reaches the terminal as a live ESC under dash\n' \
      "$safe_rel" "$lineno" >&2
  else
    printf 'check-echo-safety: %s:%s passes sanitize_printable output through echo; use printf '"'"'%%s\\n'"'"' instead — the sanitizer strips control BYTES but keeps backslashes, so a PRINTABLE-ONLY argument still reaches the terminal as a live ESC under dash\n' \
      "$safe_rel" "$lineno" >&2
  fi
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
  if grep -qxF -- "$entry" "$work/allowed-hit" 2>/dev/null; then
    allowed=$((allowed + 1))
  else
    stale="$stale $entry"
  fi
done <<EOF
$ALLOWLIST
EOF

[ -z "$stale" ] \
  || fail_closed "allowlist entries no longer violate and must be removed —$(sanitize_printable "$stale" " (unprintable)") (each exists only while its file is open in another pull request; the allowlist shrinks to empty)"

if [ "$status" -eq 0 ]; then
  printf 'check-echo-safety: clean (%s files, %s allowlisted; %s bash-interpreter files not at risk)\n' \
    "$count" "$allowed" "$skipped"
fi
exit "$status"
