#!/usr/bin/env bash
# check-test-hermeticity.sh — fail the test shapes that pass or fail on the
# running host rather than on the code under test.
#
# Three shapes:
#
#   mode-bit   a `chmod`, or a `mkdir` given a mode, that takes read or write
#              away from the owner, with no probe that the access is now
#              denied. Root, or a capability override, reads and writes what
#              the mode forbids, so the refusal the test asserts never happens
#              there and the test fails for a reason unrelated to the guard
#              under test. A probe is a call to hermetic_access_denied
#              (tests/lib/hermetic-env.sh) or a `[ -r ... ]` / `[ -w ... ]` /
#              `test -r|-w` test whose line names the same target, anywhere
#              between the mode change and the next chmod of that target (the
#              restore) or the end of the file; where it sits relative to the
#              assertion is not checked.
#   dead-owner a PID captured from `$!`, reaped with `wait` (a bare `wait`
#              reaps every capture), then used again, in code or in an
#              unquoted heredoc body, as though it still named nobody. The
#              host may already have handed that PID to another process.
#              Conforming fixtures draw a PID from tests/lib/dead-owner.sh, or
#              a token the lock library minted for a holder that has exited.
#   unsourced  a suite that reads one of the listed configuration or root
#              variables (tests/lib/hermetic-env.sh owns the list) without
#              sourcing that library first, which clears them; its fleet_home
#              helpers carry the pinning, so a suite pinning through them
#              conforms. A read is any `$NAME` or `${NAME...}` in code or in
#              an unquoted heredoc body, which the suite itself expands; a
#              read on a line before the source is still an offense, and a
#              source spelled inside a quoted string is no source.
#
# Not code, so never an offense: full-line comments, and heredoc bodies for
# the mode-bit shape (a chmod written into a stub runs later, in the stub).
# Only owner read and write count for mode-bit: a missing
# execute bit refuses root too, and a directory's search bit cannot be told
# from a file's execute bit by text. Those, and every dependence with no
# textual shape (locale, a symlinked temporary root), are the Tests lens's and
# the perturbed CI run's to catch.
#
# An exclusion is recorded on the offending line, or the line above it, as a
# `# hermetic-exempt: <reason>` comment; a marker with no reason excludes
# nothing.
#
# Usage:
#   check-test-hermeticity.sh [<root>]   scan <root>/tests, outside
#                                        <root>/tests/fixtures, against the
#                                        list in <root>/tests/lib/hermetic-env.sh
#                                        (default root: the parent of this
#                                        script's directory)
#   check-test-hermeticity.sh --help | -h
#
# Exit codes: 0 clean, 1 an offending file, 2 usage or a broken enumeration
# (an absent root, tests directory or library, a library that lists nothing,
# an unreadable file, a find that fails, a scan reaching no files).
#
# Portable bash 3.2 / BSD tooling.
set -u

LC_ALL=C
export LC_ALL

unset CDPATH

self_dir="$(cd "$(dirname "$0")" && pwd -P)"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

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
  printf '%s\n' "check-test-hermeticity: $1" >&2
  exit 2
}

usage() {
  cat <<'EOF'
check-test-hermeticity.sh — fail test fixtures whose outcome depends on the
running host.

Usage:
  check-test-hermeticity.sh [<root>]   scan <root>/tests outside
                                       <root>/tests/fixtures, against the
                                       variable list in
                                       <root>/tests/lib/hermetic-env.sh
                                       (default root: this repository)
  check-test-hermeticity.sh --help | -h

Flagged:
  mode-bit    a chmod, or a mkdir -m, removing owner read or write with no
              access probe naming the target (hermetic_access_denied, or a
              [ -r ] / [ -w ] test) before its next chmod or the end of the file
  dead-owner  a $! PID used again after it was reaped with wait; draw one from
              tests/lib/dead-owner.sh or a lock-library token instead
  unsourced   a read of a listed configuration or root variable in a file
              that does not source tests/lib/hermetic-env.sh before it

Excluded: an offending line carrying, or following, a
`# hermetic-exempt: <reason>` comment.

Exit codes: 0 clean, 1 an offending file, 2 usage or a broken enumeration.
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
[ -d "$root/tests" ] || fail_closed "no tests directory under $safe_root"
lib="$root/tests/lib/hermetic-env.sh"
[ -r "$lib" ] || fail_closed "cannot read the variable list's library under $safe_root (tests/lib/hermetic-env.sh)"

# The list is read by sourcing the library in a child, so the guard reads the
# same names a suite clears and never parses the library's text a second way.
names=$(_hermetic_env_defer=1 /bin/bash -c '. "$1" && hermetic_env_names' _ "$lib" 2>/dev/null) \
  || fail_closed "the library under $safe_root did not yield its variable list"
pattern=""
# No pathname expansion: a name holding a glob character must reach the
# malformed-name check as written, never as the files it matches.
set -f
for n in $names; do
  case "$n" in
    *[!A-Za-z0-9_]* | [0-9]*) fail_closed "the library lists a malformed name: $(sanitize_printable "$n" "(unprintable)")" ;;
  esac
  pattern="${pattern:+$pattern|}$n"
done
set +f
[ -n "$pattern" ] || fail_closed "the library under $safe_root lists no variables"

work="$(mktemp -d "${TMPDIR:-/tmp}/check-test-hermeticity.XXXXXX")" \
  || fail_closed "could not create a temporary directory"
trap 'rm -rf "$work"' EXIT
: >"$work/all"

if ! find -P "$root/tests" -path "$root/tests/fixtures" -prune -o \( -type f -o -type l \) -print0 >>"$work/all" 2>"$work/err"; then
  fail_closed "find failed under $safe_root/tests: $(sanitize_printable "$(cat "$work/err")" "(unprintable)")"
fi

: >"$work/list"
count=0
newline='
'
tab="$(printf '\t')"
while IFS= read -r -d '' file; do
  rel="${file#"$root"/}"
  case "$file" in
    *"$newline"* | *"$tab"*)
      fail_closed "filename contains a newline or tab, refusing to scan: $(sanitize_printable "$rel" "(unprintable filename)")"
      ;;
  esac
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
  printf '%s\n' "$file" >>"$work/list"
  count=$((count + 1))
done <"$work/all"

[ "$count" -gt 0 ] \
  || fail_closed "no shell files found under $safe_root/tests — a broken enumeration, not a clean tree"

# The variable pattern and the library path reach awk through ENVIRON: a -v
# assignment would have its backslashes reinterpreted. The program quotes a
# single quote as '"'"', which shellcheck reads as an escape attempt.
# shellcheck disable=SC1003
HTH_PATTERN="$pattern" HTH_LIB="$lib" awk -v listfile="$work/list" '
  function exempt(line, prev) {
    return (line ~ /#[ \t]*hermetic-exempt:[ \t]*[^ \t]/ || prev ~ /^[ \t]*#[ \t]*hermetic-exempt:[ \t]*[^ \t]/)
  }
  # The text of <s> the shell would expand: escaped dollars dropped, and, in
  # code, single-quoted spans and a trailing comment. The quoting state (an
  # open single quote, a stack of double quotes and command substitutions)
  # carries from line to line, since a quoted string may span several; inside
  # double quotes a single quote is literal until a $( opens a fresh context.
  # A heredoc body has no quoting, only escapes.
  function expanded(s, body,   out, k, c, top, re) {
    if (body) { gsub(/\\./, "", s); return s }
    if (!insq && s !~ /[\\'"'"'"()#$]/) return s
    out = ""
    while (s != "") {
      if (insq) {
        if (!(k = index(s, "'"'"'"))) return out
        s = substr(s, k + 1); insq = 0
        continue
      }
      top = substr(qstack, length(qstack), 1)
      if (top == "d") k = match(s, /[\\"$]/)
      else k = match(s, /[\\'"'"'"()#$]/)
      if (!k) { out = out s; break }
      out = out substr(s, 1, RSTART - 1)
      c = substr(s, RSTART, 1)
      s = substr(s, RSTART + 1)
      if (c == "\\") { s = substr(s, 2); continue }
      if (c == "$") {
        if (substr(s, 1, 1) == "(") { qstack = qstack "c"; out = out "$("; s = substr(s, 2) }
        else out = out c
        continue
      }
      if (top == "d") { qstack = substr(qstack, 1, length(qstack) - 1); out = out c; continue }
      if (c == "'"'"'") { insq = 1; continue }
      if (c == "\"") { qstack = qstack "d"; out = out c; continue }
      if (c == "(") { qstack = qstack "c"; out = out c; continue }
      if (c == ")") {
        if (top == "c") qstack = substr(qstack, 1, length(qstack) - 1)
        out = out c
        continue
      }
      if (out == "" || out ~ /[ \t;&|(]$/) break
      out = out c
    }
    return out
  }
  function note_read(s, n,   v) {
    if (!match(s, varre)) return
    v = substr(s, RSTART, RLENGTH)
    sub(/^\$\{?/, "", v); sub(/[^A-Za-z0-9_]$/, "", v)
    nreads++; readln[nreads] = n; readvar[nreads] = v
  }
  function report(path, n, shape, msg) {
    print path "\t" n "\t" shape "\t" msg
    found++
  }
  # Restrictive for the owner: read or write taken away. A numeric mode is
  # judged by its owner digit; a symbolic one clause by clause.
  function restrictive(mode,   n, i, c, who, op, perms, k) {
    if (mode ~ /^[0-7]+$/) {
      # chmod pads a short mode with leading zeros: `chmod 0` is mode 000.
      while (length(mode) < 3) mode = "0" mode
      c = substr(mode, length(mode) - 2, 1) + 0
      return (c < 6)
    }
    n = split(mode, cl, ",")
    for (i = 1; i <= n; i++) {
      if (!match(cl[i], /[-+=]/)) continue
      who = substr(cl[i], 1, RSTART - 1)
      op = substr(cl[i], RSTART, 1)
      perms = substr(cl[i], RSTART + 1)
      if (who != "" && who !~ /[ua]/) continue
      if (op == "-" && perms ~ /[rw]/) return 1
      if (op == "=" && (perms !~ /r/ || perms !~ /w/)) return 1
    }
    return 0
  }
  # mask(s): <s> with every quoted or escaped character replaced, quotes
  # kept and length preserved, so a command word or an operator is found only
  # where the shell would read one.
  function mask(s,   out, i, c, q) {
    out = ""; q = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (q != "'"'"'" && c == "\\") { out = out "__"; i++; continue }
      if (q == "" && (c == "'"'"'" || c == "\"")) { q = c; out = out c; continue }
      if (q != "" && c == q) { q = ""; out = out c; continue }
      out = out (q == "" ? c : "_")
    }
    return out
  }
  # chmod_args(line) sets cm_mode and cm_target from a chmod, or a mkdir
  # given a mode, on the line; returns 0 when there is neither. cm_restore is
  # 1 for a chmod, which can close an open fixture, and 0 for a mkdir.
  function chmod_args(line,   rest, n, i, t, mk) {
    cm_mode = ""; cm_target = ""; cm_restore = 1
    if (index(line, "chmod") && match(mask(line), /(^|[;&|(` \t])chmod[ \t]+/)) mk = 0
    else if (index(line, "mkdir") && index(line, "-") && match(mask(line), /(^|[;&|(` \t])mkdir[ \t]+/)) { mk = 1; cm_restore = 0 }
    else return 0
    rest = substr(line, RSTART + RLENGTH)
    n = split(rest, tok, /[ \t]+/)
    for (i = 1; i <= n; i++) {
      t = tok[i]
      if (t == "") continue
      if (mk) {
        if (t == "-m" || t ~ /^-p+m$/) { cm_mode = tok[++i]; continue }
        if (t ~ /^-p*m./) { sub(/^-p*m/, "", t); cm_mode = t; continue }
        if (t ~ /^--mode=/) { cm_mode = substr(t, 8); continue }
        if (t ~ /^-/) continue
        if (cm_mode == "") return 0
      } else {
        if (cm_mode == "" && t ~ /^-[RfvchHLP]+$/) continue
        if (cm_mode == "") { cm_mode = t; continue }
      }
      cm_target = t
      sub(/[;)]+$/, "", cm_target)
      break
    }
    return (cm_mode != "")
  }
  # unquoted(s): <s> without its quote characters, so a probe and a chmod
  # spelling one path with different quoting still match.
  function unquoted(s) {
    gsub(/["'"'"']/, "", s)
    return s
  }
  function scan(path,   line, prev, body, delim, heredoc, heredoc_dash, quoted, n, r, pre, dash, v, k, m, e, sourced, is_lib, re_v, instr, s, off, u, len) {
    heredoc = ""; heredoc_dash = 0; quoted = 0; n = 0; prev = ""
    sourced = 0; nreads = 0
    split("", readln); split("", readvar)
    insq = 0; qstack = ""
    is_lib = (path == ENVIRON["HTH_LIB"])
    path_now = path
    split("", open_line); split("", probed)
    split("", spawned); split("", reaped)
    while ((r = (getline line < path)) > 0) {
      n++
      sub(/\r$/, "", line)

      if (heredoc != "") {
        body = line
        if (heredoc_dash) sub(/^\t+/, "", body)
        if (body == heredoc) { heredoc = ""; prev = line; continue }
        # The suite expands an unquoted body itself, so a listed name there
        # is a read; a quoted body is text handed to something else.
        if (!quoted && !is_lib && line ~ namere && !exempt(line, prev)) note_read(expanded(line, 1), n)
        # An unquoted body also expands a reaped PID into what it writes.
        if (!quoted) dead_use(line, n, prev)
        prev = line
        continue
      }
      if (line ~ /^[ \t]*$/) { prev = line; continue }
      # A line opening with # is a comment only outside a quoted string; inside
      # one it is string text, whose closing quote the quoting state must see.
      if (line ~ /^[ \t]*#/) {
        if (insq || index(qstack, "d")) {
          e = expanded(line, 0)
          if (!is_lib && e ~ namere && !exempt(line, prev)) note_read(e, n)
        }
        prev = line
        continue
      }
      instr = (insq || index(qstack, "d"))
      m = mask(line)

      # Only a source the shell runs counts: the dot or `source` word must
      # sit outside quotes, on a line that does not open inside a string.
      if (!sourced && !instr && index(line, "hermetic-env.sh")) {
        s = line; off = 0
        while (match(s, /(^|[;&|( \t])(\.|source)[ \t]+[^#]*hermetic-env\.sh/)) {
          k = off + RSTART
          if (substr(line, k, 1) !~ /[.s]/) k++
          if (substr(m, k, 1) == substr(line, k, 1)) { sourced = n; break }
          off += RSTART; s = substr(s, RSTART + 1)
        }
      }

      # The quoting state must see every code line, so expanded() runs on
      # each; only a line naming a listed variable is matched against it.
      e = expanded(line, 0)
      if (!is_lib && e ~ namere && !exempt(line, prev)) note_read(e, n)

      # mode-bit: a probe naming an open target satisfies it; a chmod of an
      # open target closes it (the restore); a restrictive chmod, or a mkdir
      # given a restrictive mode, opens one.
      if (line ~ /hermetic_access_denied|-[rw][ \t]/ && (m ~ /hermetic_access_denied[ \t]/ || m ~ /(\[|test)[ \t]+(![ \t]+)?-[rw][ \t]/)) {
        u = unquoted(line)
        for (k in open_line) if (index(u, unquoted(k))) probed[k] = 1
      }
      if (chmod_args(line)) {
        if (cm_restore && (cm_target in open_line)) {
          if (!probed[cm_target]) report(path, open_line[cm_target], "mode-bit", "removes owner access to " cm_target " with no access probe before its next chmod")
          delete open_line[cm_target]; delete probed[cm_target]
        }
        if (cm_target != "" && restrictive(cm_mode) && !exempt(line, prev)) {
          open_line[cm_target] = n; probed[cm_target] = 0
        }
      }

      # dead-owner: a $! capture, its wait (a bare wait reaps every capture),
      # then a later use of the PID.
      if (match(line, /(^|[;&{]|then|do|else)[ \t]*((local|declare|readonly|export|typeset)[ \t]+(-[A-Za-z]+[ \t]+)?)?[A-Za-z_][A-Za-z0-9_]*="?\$!/)) {
        v = substr(line, RSTART, RLENGTH)
        sub(/^([;&{]|then|do|else)?[ \t]*((local|declare|readonly|export|typeset)[ \t]+(-[A-Za-z]+[ \t]+)?)?/, "", v); sub(/="?\$!$/, "", v)
        spawned[v] = 1; reaped[v] = 0
      } else {
        if (m ~ /(^|[;&|( \t])wait[ \t]*($|[;&|)])/) {
          for (v in spawned) if (!reaped[v]) reaped[v] = n
        }
        for (v in spawned) {
          if (!index(line, v)) continue
          re_v = "\\$\\{?" v "([^A-Za-z0-9_]|$)"
          if (line !~ re_v) continue
          if (m ~ /(^|[;&|( \t])wait[ \t]/) { reaped[v] = n; continue }
        }
        dead_use(line, n, prev)
      }

      # A heredoc opens only at a << the shell reads as one: not a here-string
      # (<<<), not a shift inside arithmetic, not inside quotes.
      if (!instr && index(line, "<<") && match(m, /(^|[^<])<<-?[ \t]*\\?['"'"'"]?[A-Za-z0-9_.+-]+/)) {
        k = RSTART; len = RLENGTH
        if (substr(m, k, 1) != "<") { k++; len-- }
        pre = substr(m, 1, k - 1)
        if (gsub(/\(\(/, "&", pre) <= gsub(/\)\)/, "&", pre)) {
          delim = substr(line, k, len)
          dash = (delim ~ /^<<-/)
          sub(/^<<-?[ \t]*/, "", delim)
          quoted = (delim ~ /^[\\'"'"'"]/)
          sub(/^\\/, "", delim)
          sub(/^['"'"'"]/, "", delim)
          heredoc = delim
          heredoc_dash = dash
        }
      }
      prev = line
    }
    close(path)
    if (r < 0) { print "!\t" path; return }
    for (k in open_line) {
      if (!probed[k]) report(path, open_line[k], "mode-bit", "removes owner access to " k " with no access probe after it")
    }
    for (k = 1; k <= nreads; k++) {
      if (!sourced) report(path, readln[k], "unsourced", "reads $" readvar[k] " without sourcing tests/lib/hermetic-env.sh")
      else if (readln[k] < sourced) report(path, readln[k], "unsourced", "reads $" readvar[k] " before line " sourced " sources tests/lib/hermetic-env.sh")
    }
  }
  # dead_use(line, n, prev): report a use of a captured PID after its wait.
  function dead_use(line, n, prev,   v, re_v) {
    for (v in spawned) {
      if (!reaped[v] || !index(line, v)) continue
      re_v = "\\$\\{?" v "([^A-Za-z0-9_]|$)"
      if (line !~ re_v || line ~ /^[ \t]*(kill|wait)[ \t]/) continue
      if (mask(line) ~ /(^|[;&|( \t])wait[ \t]/) continue
      if (!exempt(line, prev)) report(path_now, n, "dead-owner", "uses $" v " after line " reaped[v] " reaped it")
      delete spawned[v]; delete reaped[v]
    }
  }
  BEGIN {
    varre = "\\$\\{?(" ENVIRON["HTH_PATTERN"] ")([^A-Za-z0-9_]|$)"
    namere = "(" ENVIRON["HTH_PATTERN"] ")"
    found = 0
    while ((lr = (getline path < listfile)) > 0) scan(path)
    if (lr < 0) print "!\t" listfile
  }
' >"$work/offenders" || fail_closed "the scan could not complete"

status=0
while IFS="$tab" read -r file lineno shape msg; do
  [ -n "$file" ] || continue
  if [ "$file" = "!" ]; then
    fail_closed "could not read $(sanitize_printable "${lineno#"$root"/}" "(unprintable filename)") during the scan — the scan would cover less than it claims"
  fi
  rel="${file#"$root"/}"
  printf '%s\n' "check-test-hermeticity: $(sanitize_printable "$rel" "(unprintable filename)"):$lineno: $shape: $(sanitize_printable "$msg" "(unprintable)")" >&2
  status=1
done <"$work/offenders"

if [ "$status" -eq 0 ]; then
  printf '%s\n' "check-test-hermeticity: clean ($count files)"
fi
exit "$status"
