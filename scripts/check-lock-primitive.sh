#!/usr/bin/env bash
# check-lock-primitive.sh — the retired-mkdir guard over advisory locking.
#
# `mkdir` is no longer an acquisition primitive in this tree. The single lock
# primitive is `scripts/lock-lib.sh`, whose header carries the full rationale;
# the short version is that the mkdir shape was MEASURED losing mutual
# exclusion on this support bar. Twelve concurrent same-resource writers
# produced 13 interleaved critical sections over ten rounds under `mkdir` +
# `rmdir`, and 0 over the same rounds under an atomic symlink create. A single
# fresh `mkdir` contest IS exclusive on a conforming filesystem, so the loss
# appeared in the release-and-reacquire cycle rather than in `mkdir` itself —
# and the reimplemented coreutils `mkdir` on at least one host inside the
# support bar returns success to several concurrent creators, so the primitive
# is not even reliably exclusive there. The consequence was silent: twenty
# concurrent registrations landed seventeen records while every writer exited 0.
#
# A guard rather than review attention, for the same reason the sibling guards
# exist: the failure leaves no trace. Every writer exits 0, the lock directory
# looks correct afterwards, and the only evidence is the records that are not
# there. Nothing in a local run, a CI run, or a diff read shows it.
#
# WHAT COUNTS AS AN OFFENSE is narrower than "a mkdir": it is a `mkdir` WITHOUT
# `-p` whose EXIT STATUS IS READ. That pair is what makes a mkdir a lock — the
# script is asking the kernel "did I win this path", which is the question
# `pw_lock_try` now answers. Concretely:
#
#   * `if mkdir ...`, `elif`, `if ! mkdir ...`, `while`, `until`, including a
#     condition that starts on the line below its keyword
#   * `mkdir ... && <anything>` or `mkdir ... || <anything>`, including an
#     operator on a backslash-continued line
#   * `mkdir ...; then`
#   * any of those nested in `(...)`, `{...}`, or reached after `;`, `|`,
#     `&&`, `||`
#   * a bare `mkdir ...` whose status the next command reads: any `$?` in the
#     command after a `;` on the same line, or in the first command of the
#     next effective line (`rc=$?`, `export rc=$?`, `[ $? -eq 0 ]`, `case $?`)
#   * the command word in any quoting (`\mkdir`, `"mkdir"`, the dollar-quote
#     form with its escapes) or behind `command`, `exec`, `env` or `sudo`
#
# WHAT DOES NOT COUNT. A `mkdir -p` (or `--parents`) succeeds on a directory
# that already exists, so its status cannot signal exclusion and it is never a
# lock — `if ! mkdir -p "$d"; then` is an ordinary error check, and the tree
# has dozens. A `mkdir` whose status nobody reads is not asking the question at
# all. An occurrence inside a comment, a heredoc body (whatever quoting or
# escape its delimiter carries), or a single-quoted string is prose, not a
# call: every file that documents this rule contains one. And `mkdir` is
# matched only as a COMMAND WORD, so `_mkdir_rc`, `mkdir_failure_kind`,
# `$mkdir_out` and a word in an array's value list are not invocations.
#
# THE ESCAPE HATCH. A site that genuinely consumes mkdir status for something
# other than lock acquisition — a mode-pinned bootstrap where EEXIST is
# success, a best-effort `|| true` creation, a deliberate mkdir-atomicity probe
# in a test — is exempted by an annotation carrying a REASON:
#
#     # not-a-lock: <reason>
#
# either trailing the mkdir line or on the line DIRECTLY above it. A blank line
# between does not carry it, because an annotation that can drift away from its
# site stops being about that site. An annotation with nothing after the colon
# exempts nothing and is reported on its own: a reasonless marker is how an
# escape hatch quietly becomes a blanket.
#
# Scope is every shell file under scripts/, tests/, and githooks/, reached
# either by shebang or by an .sh suffix. Neither test alone is enough: the
# githooks/ hooks are extensionless, and the sourced libraries (echo-safety.sh,
# spec-parse.sh, lock-lib.sh itself) carry a `# shellcheck shell=` line instead
# of a shebang. A sourced library is exactly where a shared lock helper would
# live, so leaving those unscanned would leave the likeliest offender unscanned.
#
# State that outlives a line is carried across it: an open quote, an open
# `${...}`, an array value list, an if or while condition waiting for its
# `then` or `do`, and a backslash continuation, whose lines are read as the one
# command they are.
#
# Known limits, all of them the same shape — the question stops being answerable
# by reading one command:
#   * status consumed through a variable two hops later (`mkdir "$d"; sleep 1;
#     rc=$?`) is not followed: only the next command is examined.
#   * a wrapper other than `command`, `exec`, `env` and `sudo` (`nice`,
#     `timeout`, `xargs`) is not looked through.
#   * `eval "mkdir $d && ..."` is a string, not a command, and is not parsed.
#   * options carried in a variable (`mkdir $opts "$d"`) are not resolved, so
#     a `-p` that only exists at runtime is not seen.
#
# Usage:
#   check-lock-primitive.sh [<root>]   scan the scope directories under <root>
#                                      (default: the parent of this script's
#                                      directory)
#   check-lock-primitive.sh --help | -h
#
# Exit codes: 0 clean, 1 an offending site, 2 usage or a broken enumeration.
# Anything that would make the scan cover less than it claims — an absent root
# or scope directory, an unreadable file, a `find` that fails partway, a scan
# reaching no files at all — is exit 2, never a clean report.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible.
set -u

LC_ALL=C
export LC_ALL

unset CDPATH

SCOPE_DIRS="scripts tests githooks"

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
  printf 'check-lock-primitive: %s\n' "$1" >&2
  exit 2
}

usage() {
  cat <<'EOF'
check-lock-primitive.sh — flag any `mkdir` whose exit status is read as a
lock-acquisition signal.

Usage:
  check-lock-primitive.sh [<root>]   scan the scope directories under <root>
                                     (default: the parent of this script's
                                     directory)
  check-lock-primitive.sh --help | -h

Why: the mkdir shape was measured losing mutual exclusion on this support bar
(twelve concurrent writers, 13 interleaved critical sections over ten rounds;
0 under an atomic symlink create), and it loses it silently — every writer
exits 0 and only the missing records show it. scripts/lock-lib.sh replaces it.

Remedy: take the lock through the library.

  . "$dir/lock-lib.sh"
  pw_lock_trap_install
  pw_lock_acquire "$lock" || exit 1
  ...
  pw_lock_release "$lock"

Flagged: a `mkdir` WITHOUT -p / --parents whose exit status is consumed — in an
if/elif/while/until condition (with or without `!`), by `&&` or `||`, by a
`; then`, or by any `$?` in the command after it (after a `;`, or first on the
next effective line). Nesting in `(...)`, `{...}`, or after `;`, `|`, `&&`,
`||` does not hide it, nor does quoting the command word or running it through
`env` or `sudo`.

Not flagged: any `mkdir -p` / `--parents` (it succeeds on an existing directory,
so its status cannot signal exclusion — `if ! mkdir -p "$d"; then` is an
ordinary error check); a `mkdir` whose status nobody reads; an occurrence in a
comment, a heredoc body, or a single-quoted string; and an identifier that
merely contains the letters, such as `_mkdir_rc` or `$mkdir_out`.

Escape hatch: a site that consumes mkdir status for something other than lock
acquisition — a mode-pinned bootstrap where EEXIST is success, a best-effort
creation, a deliberate mkdir-atomicity probe in a test — is exempted by

    # not-a-lock: <reason>

trailing the mkdir line or on the line directly above it. A blank line between
does not carry it. An annotation with no reason after the colon exempts nothing
and is itself reported.

Exit codes: 0 clean, 1 an offending site, 2 usage or a broken enumeration.
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
work="$(mktemp -d "${TMPDIR:-/tmp}/check-lock-primitive.XXXXXX")" \
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
newline='
'
tab="$(printf '\t')"
while IFS= read -r -d '' file; do
  rel="${file#"$root"/}"
  # Sanitizing forks, so it happens only on the paths that actually reach the
  # terminal, never once per enumerated file.
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
      *) continue ;;
    esac ;;
  esac
  printf '%s\n' "$file" >>"$work/list"
  count=$((count + 1))
done <"$work/all"

[ "$count" -gt 0 ] \
  || fail_closed "no shell files found under $SCOPE_DIRS in $safe_root — a broken enumeration, not a clean tree"

# One awk pass over the whole list, as a shell tokenizer rather than a line
# regex. Nothing weaker answers the question this guard asks. `mkdir` is an
# invocation only at a command position, so `$mkdir_out` and a `mkdir` inside a
# message string must not count; a `#` opens a comment only at a word boundary
# outside quotes; a heredoc body and a single-quoted string are not code at
# all; and quote state has to survive across lines, because a multi-line
# single-quoted string (this awk program, in this very file) would otherwise be
# read as shell. Files are opened by getline rather than through ARGV, so a
# name containing `=` or a leading `-` is read as a path, never as an awk
# variable assignment or option. SQ carries the single-quote character in,
# which is what keeps this program free of one.
awk -v listfile="$work/list" -v SQ="'" -v BT='`' '
  # tokl carries the SUBSTITUTION NESTING of each token, because a word and its
  # operands are only the same command while they sit at the same level. A
  # lock path is normally built — `mkdir "$d/$(id -u).lock" && ...` — and the
  # `$(` breaks the operand run, so a scan that walks contiguous words alone
  # stops at the substitution and reads it as the end of the command.
  function addtok(t, k) { ntok++; tok[ntok] = t; tokt[ntok] = k; tokl[ntok] = depth }

  # A command substitution opens a fresh QUOTING context; the outer state is
  # restored when it closes, which is what lets a `$(...)` inside a double-
  # quoted string be read as the code it is. Command position is not tracked
  # here — walk() owns that, and clobbering it from the tokenizer would lose
  # the state a continued command carries across a line break. A file with
  # hundreds of unclosed substitutions is not shell anyone wrote, and the
  # per-depth arrays grow with it, so refusing is the fail-closed answer.
  function push_ctx() {
    if (depth >= 200) { toodeep = 1; return }
    depth++
    sdq[depth] = dq; ssq[depth] = sq; saq[depth] = aq; spe[depth] = pe; sarr[depth] = arr
    dq = 0; sq = 0; aq = 0; pe = 0; arr = 0
  }
  function pop_ctx() {
    if (depth <= 0) return
    dq = sdq[depth]; sq = ssq[depth]; aq = saq[depth]; pe = spe[depth]; arr = sarr[depth]
    depth--
  }

  # hexval(c) / the dollar-quote escapes below: just enough of the ANSI-C
  # decoding to read a command word, since `$` + quote + `mk\x64ir` + quote
  # runs mkdir.
  function hexval(c) { return index("0123456789abcdef", tolower(c)) - 1 }

  # unquote(w) — the VALUE of a word, with shell quote removal applied.
  #
  # THE TOKENIZER KEEPS QUOTES ON PURPOSE (the quoting state is what tells a
  # comment from a `#` inside a string), so every place that compares a word to
  # a literal has to ask for the value instead of the spelling. A backslash
  # before a command name is the documented way to bypass a function or alias
  # of that name, and it runs the same binary; a quoted spelling is the same
  # command too. A guard matching the spelling is one escaped character away
  # from being walked past, and it reads a quoted `-p` as something other than
  # `-p`, which reports a site that is not a lock at all.
  # NO APOSTROPHES BELOW: this awk program is a single-quoted shell string.
  function unquote(w,   i, n, c, nc, out, insq, indq, inaq, v, d, k) {
    n = length(w); out = ""; insq = 0; indq = 0; inaq = 0
    for (i = 1; i <= n; i++) {
      c = substr(w, i, 1)
      if (insq) {
        if (c == SQ) insq = 0; else out = out c
        continue
      }
      if (inaq) {
        if (c == SQ) { inaq = 0; continue }
        if (c != "\\") { out = out c; continue }
        nc = substr(w, i + 1, 1); i++
        if (nc == "x") {
          v = 0; k = 0
          while (k < 2 && (d = hexval(substr(w, i + 1, 1))) >= 0) { v = v * 16 + d; i++; k++ }
          out = out (k ? sprintf("%c", v) : "\\x")
        } else if (nc ~ /[0-7]/) {
          v = nc + 0; k = 1
          while (k < 3 && substr(w, i + 1, 1) ~ /[0-7]/) { v = v * 8 + substr(w, i + 1, 1); i++; k++ }
          out = out sprintf("%c", v)
        } else if (nc == "n") out = out "\n"
        else if (nc == "t") out = out "\t"
        else if (nc == "\\" || nc == SQ || nc == "\"" || nc == "?") out = out nc
        else out = out "\\" nc
        continue
      }
      # `$` before a quote is the dollar-quote and locale-quote forms: quoting,
      # not a parameter, so it contributes nothing to the value.
      if (!indq && c == "$" && substr(w, i + 1, 1) == SQ) { inaq = 1; i++; continue }
      if (!indq && c == "$" && substr(w, i + 1, 1) == "\"") { indq = 1; i++; continue }
      if (indq) {
        # Inside double quotes a backslash escapes only these; before anything
        # else it is an ordinary character and stays one.
        nc = substr(w, i + 1, 1)
        if (c == "\\" && (nc == "$" || nc == "\"" || nc == "\\" || nc == BT)) { out = out nc; i++; continue }
        if (c == "\"") { indq = 0; continue }
        out = out c
        continue
      }
      if (c == SQ) { insq = 1; continue }
      if (c == "\"") { indq = 1; continue }
      if (c == "\\") { out = out substr(w, i + 1, 1); i++; continue }
      out = out c
    }
    return out
  }

  # tokenize(line, append) — split one line into words and control operators,
  # setting ntok/tok/tokt, the trailing comment, and whether the line leaves a
  # command open. Quote, expansion, array and substitution state persist across
  # lines by design: none of them ends where a line does. With <append> set the
  # tokens extend the previous line rather than replacing it, which is how a
  # backslash-continued command is read as the one command it is.
  function tokenize(line, append,   i, n, c, nc, pc, c2, w, k, delim, used, hd_dash, j, ch, e, quoted) {
    if (!append) { ntok = 0; comment = ""; hascomment = 0 }
    endsopen = 0; bscont = 0
    w = ""
    i = 1; n = length(line)
    while (i <= n) {
      c = substr(line, i, 1)
      nc = substr(line, i + 1, 1)
      if (sq) {
        if (c == SQ) sq = 0
        w = w c; i++; continue
      }
      if (aq) {
        # The dollar-quote form: single-quoted, except that a backslash escapes,
        # so an escaped quote does not end it.
        if (c == "\\") { w = w c nc; i += 2; continue }
        if (c == SQ) aq = 0
        w = w c; i++; continue
      }
      if (dq) {
        if (c == "\\") { w = w c nc; i += 2; continue }
        if (c == "\"") { dq = 0; w = w c; i++; continue }
        if (c == "$" && nc == "(") {
          if (w != "") { addtok(w, "w"); w = "" }
          addtok("$(", "op"); push_ctx(); i += 2; continue
        }
        w = w c; i++; continue
      }
      if (pe) {
        # Inside ${...}: word text to its closing brace, but quotes inside it
        # still quote, and the brace a quote holds closes nothing. Tracked as
        # state rather than found with index(), because the closing brace may
        # be lines away and a quote opened in between must not be lost.
        if (c == "\\") { w = w c nc; i += 2; continue }
        if (c == SQ) { sq = 1; w = w c; i++; continue }
        if (c == "\"") { dq = 1; w = w c; i++; continue }
        if (c == "$" && nc == "{") { pe++; w = w c nc; i += 2; continue }
        if (c == "}") pe--
        w = w c; i++; continue
      }
      if (c == "\\") {
        # A backslash at end of line joins the next line onto this command.
        if (i == n) { bscont = 1; i++; continue }
        w = w c nc; i += 2; continue
      }
      if (c == "$" && nc == SQ) { aq = 1; w = w c nc; i += 2; continue }
      if (c == SQ) { sq = 1; w = w c; i++; continue }
      if (c == "\"") { dq = 1; w = w c; i++; continue }
      if (c == "#" && w == "") {
        comment = substr(line, i + 1); hascomment = 1
        break
      }
      if (c == " " || c == "\t") { if (w != "") { addtok(w, arr ? "aw" : "w"); w = "" } i++; continue }
      if (arr && c == ")") {
        # The end of an array value list. Nothing in it was a command, so it
        # leaves no operator behind for the walk to read as one.
        if (w != "") { addtok(w, "aw"); w = "" }
        arr = 0; i++; continue
      }
      if (c == "(" && w ~ /=$/ && !arr) {
        # `name=(` opens an array value list: its words are data, so a mkdir
        # named in one is not a command position.
        addtok(w "(", "w"); w = ""; arr = 1; i++; continue
      }
      if (c == "$" && nc == "(") {
        if (w != "") { addtok(w, "w"); w = "" }
        addtok("$(", "op"); push_ctx(); i += 2; continue
      }
      if (c == "$" && nc == "{") {
        # ${...} is word text; letting the brace through as an operator would
        # split a parameter expansion into nonsense.
        pe = 1; w = w c nc; i += 2; continue
      }
      if (c == "`") {
        if (w != "") { addtok(w, "w"); w = "" }
        addtok("`", "op")
        if (bt) { pop_ctx(); bt = 0 } else { push_ctx(); bt = 1 }
        i++; continue
      }
      # A heredoc is recognised here, where the quoting state is known, rather
      # than by a line regex that has to guess whether the operator sits inside
      # a string. Getting it wrong in either direction is fatal: never entering
      # the body lets it clear or trip the scan, and never leaving it swallows
      # the rest of the file.
      if (c == "<" && nc == "<") {
        if (substr(line, i + 2, 1) == "<") { w = w "<<<"; i += 3; continue }
        k = i + 2
        hd_dash = 0
        if (substr(line, k, 1) == "-") { hd_dash = 1; k++ }
        while (substr(line, k, 1) == " " || substr(line, k, 1) == "\t") k++
        # The delimiter is a whole shell WORD and the body ends at a line equal
        # to that word after quote removal, so `E\OF` ends at `EOF` and a quoted
        # `\EOF` ends at `\EOF`. Reading only a run of plain characters gets
        # both wrong: the first never closes and swallows the real code after
        # it, the second is not recognised and its prose is read as code.
        j = k; delim = ""; quoted = 0
        while (j <= n) {
          ch = substr(line, j, 1)
          if (ch == " " || ch == "\t" || ch == ";" || ch == "&" || ch == "|" \
            || ch == "<" || ch == ">" || ch == "(" || ch == ")") break
          if (ch == "\\") { delim = delim substr(line, j + 1, 1); j += 2; quoted = 1; continue }
          if (ch == SQ) {
            e = index(substr(line, j + 1), SQ)
            if (e == 0) { delim = ""; break }
            delim = delim substr(line, j + 1, e - 1); j += e + 1; quoted = 1; continue
          }
          if (ch == "\"") {
            quoted = 1; j++
            while (j <= n && substr(line, j, 1) != "\"") {
              ch = substr(line, j, 1)
              if (ch == "\\" && index("$\"\\" BT, substr(line, j + 1, 1)) > 0) { j++; ch = substr(line, j, 1) }
              delim = delim ch; j++
            }
            j++; continue
          }
          delim = delim ch; j++
        }
        # `<<2` is an arithmetic shift far more often than a heredoc named 2,
        # and reading it as a heredoc would swallow the file from there on. But
        # a shift operand is a NUMBER: `2EOF` is not one, and refusing it reads
        # the heredoc BODY as shell, which reports prose as code. An unquoted
        # word keeps the old plain-character shape, which is what keeps `$x` and
        # other operands of a shift from being read as a delimiter.
        if (delim != "" && (quoted || (delim ~ /^[A-Za-z0-9_.+-]+$/ && delim !~ /^[0-9]+$/))) {
          if (heredoc == "") { heredoc = delim; hdash = hd_dash }
          w = w "<<"
          i = j
          continue
        }
        w = w c; i++; continue
      }
      c2 = substr(line, i, 2)
      if (c2 == "&&" || c2 == "||" || c2 == ";;") {
        if (w != "") { addtok(w, "w"); w = "" }
        addtok(c2, "op"); i += 2; continue
      }
      # `2>&1` and `&>log` are redirections, not the background operator.
      pc = (i > 1) ? substr(line, i - 1, 1) : ""
      if (c == "&" && (pc == ">" || pc == "<" || nc == ">")) { w = w c; i++; continue }
      if (c == ";" || c == "&" || c == "|") {
        if (w != "") { addtok(w, "w"); w = "" }
        addtok(c, "op"); i++; continue
      }
      if (c == "(") {
        if (w != "") { addtok(w, "w"); w = "" }
        addtok("(", "op"); push_ctx(); i++; continue
      }
      if (c == ")") {
        if (w != "") { addtok(w, "w"); w = "" }
        addtok(")", "op"); pop_ctx(); i++; continue
      }
      w = w c; i++
    }
    if (w != "") addtok(w, arr ? "aw" : "w")
    # A line that ends inside a quote or an expansion has not ended its word,
    # let alone its command.
    if (sq || dq || aq || pe) endsopen = 1
    if (ntok > 0 && tokt[ntok] == "op") {
      c = tok[ntok]
      if (c == "&&" || c == "||" || c == "|" || c == "(" || c == "$(") endsopen = 1
    }
  }

  # walk(path, lno) — find the mkdir invocations on the tokenized line and
  # decide, per invocation, whether its exit status is being read.
  # reads_status(from, lvl) — 1 when the command starting at token <from>
  # reads `$?`, the status the command before it left. Any reference counts,
  # not only `rc=$?`: a test, a case, an `export` all read the same answer.
  function reads_status(from, lvl,   j, t, m, ch, insq, indq) {
    for (j = from; j <= ntok; j++) {
      t = tok[j]
      if (tokt[j] == "op") {
        if (tokl[j] <= lvl && (t == ";" || t == "&&" || t == "||" || t == "|" || t == "&" || t == ";;")) return 0
        continue
      }
      insq = 0; indq = 0
      for (m = 1; m <= length(t); m++) {
        ch = substr(t, m, 1)
        if (insq) { if (ch == SQ) insq = 0; continue }
        if (ch == "\\") { m++; continue }
        if (ch == "\"") { indq = !indq; continue }
        if (ch == SQ && !indq) { insq = 1; continue }
        if (ch == "$" && (substr(t, m + 1, 1) == "?" || substr(t, m + 1, 2) == "{?")) return 1
      }
    }
    return 0
  }

  function walk(path, lno, exempt,   i, j, k, t, base, opt, lvl, hasp, inopts, term, nxt, kind, wrap) {
    i = 1
    wrap = ""
    while (i <= ntok) {
      if (tokt[i] == "op") {
        # Every control operator and every substitution boundary opens a
        # command position. A `)` does too: it closes a case pattern, and the
        # word after a closed substitution is a command name in the one shape
        # that matters here, `name() { ... }`.
        atcmd = 1; wrap = ""
        i++; continue
      }
      # A word of an array value list is data wherever it sits.
      if (tokt[i] == "aw") { i++; continue }
      t = tok[i]
      # A brace group opens a command position whatever preceded it, which is
      # how the body of `take() { mkdir ...; }` is reached at all.
      if (t == "{" || t == "}") { atcmd = 1; i++; continue }
      if (!atcmd) { i++; continue }
      if (wrap != "") {
        # The options of a command that runs its operand as a command. Past
        # them, the next word is that command.
        opt = unquote(t)
        if (opt == "--") { wrap = ""; i++; continue }
        if (opt ~ /^-/) {
          if ((wrap == "sudo" && opt ~ /^-[ughprtCDTUR]$/) \
            || (wrap == "env" && opt ~ /^-[uCSPa]$/) \
            || opt == "--user" || opt == "--group" || opt == "--chdir" || opt == "--unset") i++
          i++; continue
        }
        wrap = ""
      }
      # A keyword is a keyword only at a command position, and a case pattern
      # spelled like one (`if)`) is not one.
      if ((t == "if" || t == "elif" || t == "while" || t == "until") && !(i < ntok && tok[i + 1] == ")")) { cond = 1; i++; continue }
      if (t == "then" || t == "do" || t == "else") { cond = 0; i++; continue }
      # Transparent to the command that follows them: the next word is still a
      # command name, so `command mkdir` and `FOO=1 mkdir` are still mkdir.
      if (t == "!" || t == "time" || t == "command" || t == "builtin" || t == "exec" || t == "nohup") { i++; continue }
      if (t ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=/) { i++; continue }
      base = unquote(t)
      sub(/^.*\//, "", base)
      if (base == "env" || base == "sudo") { wrap = base; i++; continue }
      if (base != "mkdir") { atcmd = 0; i++; continue }

      hasp = 0; inopts = 1
      lvl = tokl[i]
      j = i + 1
      # An operand of THIS command is a word at THIS level. Everything deeper
      # belongs to a substitution inside one of its words — including any
      # option-looking word there, which is an option to that command and not
      # to this one — and the opener sits at this level as part of the word it
      # interrupts, so it is stepped over rather than read as a terminator.
      while (j <= ntok) {
        if (tokl[j] > lvl) { j++; continue }
        if (tokt[j] == "op" && (tok[j] == "$(" || tok[j] == BT)) { j++; continue }
        if (tokt[j] != "w") break
        if (inopts) {
          opt = unquote(tok[j])
          if (opt == "--") inopts = 0
          else if (opt == "--parents" || (opt ~ /^-[A-Za-z]+$/ && opt ~ /p/)) hasp = 1
        }
        j++
      }
      # A GROUP DOES NOT SWALLOW THE STATUS. The last command in a subshell or
      # a brace group is the group, so `(mkdir d) && ...` reads the mkdir exit
      # status exactly as `mkdir d && ...` does. Look past the closers — and
      # past the `;` a brace group needs before its `}` — for the operator that
      # actually consumes it.
      k = j
      while (k <= ntok) {
        if (tokt[k] == "op" && tok[k] == ")") { k++; continue }
        if (tok[k] == "}") { k++; continue }
        if (tokt[k] == "op" && tok[k] == ";" \
          && k + 1 <= ntok && tok[k + 1] == "}") { k++; continue }
        break
      }
      term = (k <= ntok) ? tok[k] : "EOL"
      nxt = (k + 1 <= ntok) ? tok[k + 1] : ""
      kind = ""
      # The `; then` reading is the more specific one, so it names the site
      # even where the condition was already known to be open.
      if (term == ";" && (nxt == "then" || nxt == "do")) kind = "then"
      else if (cond) kind = "cond"
      else if (term == "&&" || term == "||") kind = "chain"
      else if (term == ";" && k < ntok && reads_status(k + 1, lvl)) kind = "rcsame"

      if (!hasp && kind != "") {
        if (!exempt) print path "\t" lno "\t" kind
      } else if (!hasp && (term == "EOL" || (term == ";" && k == ntok))) {
        # Nothing on this line reads the status. The next effective line still
        # can, by any reference to `$?` in its first command.
        pend = 1; pend_line = lno; pend_exempt = exempt
      }
      atcmd = 0
      i = j
    }
  }

  function scan(path,   line, r, opened, body, annot_here, exempt, reason, cont, lstart, lexempt) {
    heredoc = ""; hdash = 0
    pend = 0; pend_line = 0; pend_exempt = 0
    prev_annot = 0; atcmd = 1; cond = 0
    dq = 0; sq = 0; aq = 0; pe = 0; arr = 0; depth = 0; bt = 0; toodeep = 0
    opened = 0; cont = 0
    # getline returns -1 when the file cannot be opened or read, which is not
    # end-of-input. Treating the two alike would silently clear a file the scan
    # never saw, reachable as a TOCTOU race against the readability check the
    # selection loop already made.
    while ((r = (getline line < path)) > 0) {
      opened++
      sub(/\r$/, "", line)
      # A heredoc body starts after the whole command line, so a continuation
      # line is still the command even with a heredoc pending.
      if (heredoc != "" && !cont) {
        body = line
        if (hdash) sub(/^\t+/, "", body)
        if (body == heredoc) heredoc = ""
        prev_annot = 0
        continue
      }
      tokenize(line, cont)
      if (toodeep) { close(path); print "!\t" path; return 0 }

      annot_here = 0
      if (hascomment && comment ~ /^[ \t]*not-a-lock:/) {
        reason = comment
        sub(/^[ \t]*not-a-lock:/, "", reason)
        if (reason ~ /[^ \t]/) annot_here = 1
        else print path "\t" opened "\tannot"
      }
      # A backslash-continued command is ONE command: its tokens accumulate and
      # it is walked once, at its first line, when the last line arrives. Read a
      # line at a time, its operands and its `&&` land on lines that no longer
      # know they belong to a mkdir.
      if (!cont) { lstart = opened; lexempt = (annot_here || prev_annot) ? 1 : 0 }
      else if (annot_here) lexempt = 1
      if (bscont) { cont = 1; continue }
      cont = 0
      exempt = lexempt

      if (pend && ntok > 0) {
        if (reads_status(1, tokl[1]) && !pend_exempt) print path "\t" pend_line "\trc"
        pend = 0
      }
      if (ntok > 0) walk(path, lstart, exempt)

      # Only a comment LINE carries forward, and only to the line directly
      # below it. An annotation that can float away from its site stops being
      # about that site.
      prev_annot = (ntok == 0 && annot_here) ? 1 : 0
      # The condition of an if or while does not end with its line: `then` or
      # `do` ends it, wherever it sits. Command position does reset, except on
      # a line left open by an operator or an unfinished word.
      if (!endsopen) atcmd = 1
    }
    close(path)
    if (r < 0) { print "!\t" path; return 0 }
    return opened
  }

  BEGIN {
    while ((lr = (getline path < listfile)) > 0) scan(path)
    # An unreadable list is not an empty one; reporting clean over it would be
    # the same vacuous pass the scan-side check refuses.
    if (lr < 0) print "!\t" listfile
  }
' >"$work/offenders" || fail_closed "the scan could not complete"

status=0
while IFS="$tab" read -r file lineno kind; do
  [ -n "$file" ] || continue
  if [ "$file" = "!" ]; then
    fail_closed "could not read $(sanitize_printable "${lineno#"$root"/}" "(unprintable filename)") during the scan — the scan would cover less than it claims"
  fi
  case "$kind" in
    cond) what="mkdir without -p in an if/while condition — its exit status is read as a lock-acquisition signal" ;;
    chain) what="mkdir without -p whose exit status is consumed by && or || — a lock-acquisition signal" ;;
    then) what="mkdir without -p whose exit status is tested by a following 'then' — a lock-acquisition signal" ;;
    rc) what="mkdir without -p whose exit status is read on the next line as \$? — a lock-acquisition signal" ;;
    rcsame) what="mkdir without -p whose exit status is read as \$? by the command after it on the same line — a lock-acquisition signal" ;;
    annot) what="not-a-lock annotation with no reason — it exempts nothing" ;;
    *) fail_closed "the scan produced an unrecognised record kind" ;;
  esac
  rel="${file#"$root"/}"
  printf 'check-lock-primitive: %s:%s: %s\n' \
    "$(sanitize_printable "$rel" "(unprintable filename)")" "$lineno" "$what" >&2
  status=1
done <"$work/offenders"

if [ "$status" -eq 0 ]; then
  printf 'check-lock-primitive: clean (%s files)\n' "$count"
else
  printf '%s\n' "check-lock-primitive: take the lock through scripts/lock-lib.sh (pw_lock_acquire / pw_lock_try / pw_lock_release); a mkdir whose status is read for something other than lock acquisition is exempted by a '# not-a-lock: <reason>' comment trailing it or on the line directly above" >&2
fi
exit "$status"
