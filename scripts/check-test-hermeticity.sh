#!/usr/bin/env bash
# check-test-hermeticity.sh — fail the test shapes that pass or fail on the
# running host rather than on the code under test.
#
# Three shapes, each one the external review audit kept finding on branches a
# full lens pass had declared clean:
#
#   mode-bit   a `chmod` that takes read or write away from the owner, with no
#              probe that the access is now denied before the fixture's
#              assertion. Root, or a capability override, reads and writes
#              what the mode forbids, so the refusal the test asserts never
#              happens there and the test fails for a reason unrelated to the
#              guard under test. A probe is a call to
#              hermetic_access_denied (tests/lib/hermetic-env.sh) or a
#              `[ -r ... ]` / `[ -w ... ]` / `test -r|-w` test, anywhere
#              between the chmod and the next chmod of the same target (the
#              restore) or the end of the file.
#   dead-owner a PID captured from `$!`, reaped with `wait`, then used again as
#              though it still named nobody. The host may already have handed
#              that PID to another process. Conforming fixtures draw a PID
#              from tests/lib/dead-owner.sh, or a token the lock library
#              minted for a holder that has exited.
#   unsourced  a suite that reads one of the listed configuration or root
#              variables (tests/lib/hermetic-env.sh owns the list) without
#              sourcing that library, which clears them; its fleet_home
#              helpers carry the pinning, so a suite pinning through them
#              conforms. A read is any `$NAME` or `${NAME...}` in code or in
#              an unquoted heredoc body, which the suite itself expands.
#
# Not code, so never an offense: full-line comments, and heredoc bodies for
# the mode-bit and dead-owner shapes (a chmod written into a stub runs later,
# in the stub). Only owner read and write count for mode-bit: a missing
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
  mode-bit    a chmod removing owner read or write with no access probe
              (hermetic_access_denied, or a [ -r ] / [ -w ] test) before the
              next chmod of the same target or the end of the file
  dead-owner  a $! PID used again after it was reaped with wait; draw one from
              tests/lib/dead-owner.sh or a lock-library token instead
  unsourced   a read of a listed configuration or root variable in a file
              that does not source tests/lib/hermetic-env.sh

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
for n in $names; do
  case "$n" in
    *[!A-Za-z0-9_]* | [0-9]*) fail_closed "the library lists a malformed name: $(sanitize_printable "$n" "(unprintable)")" ;;
  esac
  pattern="${pattern:+$pattern|}$n"
done
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
      if (length(mode) < 3) return 0
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
  # chmod_args(line) sets cm_mode and cm_target from a chmod on the line;
  # returns 0 when there is none.
  # mask(s): <s> with every quoted character replaced, quotes kept, so a
  # command word is found only where the shell would read one.
  function mask(s,   out, i, c, q) {
    out = ""; q = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (q == "" && c == "\\") { out = out "__"; i++; continue }
      if (q == "" && (c == "'"'"'" || c == "\"")) { q = c; out = out c; continue }
      if (q != "" && c == q) { q = ""; out = out c; continue }
      out = out (q == "" ? c : "_")
    }
    return out
  }
  function chmod_args(line,   rest, n, i, t) {
    if (!index(line, "chmod") || !match(mask(line), /(^|[;&|(` \t])chmod[ \t]+/)) return 0
    rest = substr(line, RSTART + RLENGTH)
    n = split(rest, tok, /[ \t]+/)
    cm_mode = ""; cm_target = ""
    for (i = 1; i <= n; i++) {
      t = tok[i]
      if (t == "") continue
      if (cm_mode == "" && t ~ /^-[RfvchHLP]+$/) continue
      if (cm_mode == "") { cm_mode = t; continue }
      cm_target = t
      sub(/[;)]+$/, "", cm_target)
      break
    }
    return (cm_mode != "")
  }
  function scan(path,   line, prev, body, delim, heredoc, heredoc_dash, quoted, n, r, pre, dq, sq, dash, v, k, m, e, sourced, is_lib, re_v) {
    heredoc = ""; heredoc_dash = 0; quoted = 0; n = 0; prev = ""
    sourced = 0; nreads = 0
    split("", readln); split("", readvar)
    insq = 0; qstack = ""
    is_lib = (path == ENVIRON["HTH_LIB"])
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
        prev = line
        continue
      }
      if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) { prev = line; continue }

      if (line ~ /(^|[;&|( \t])(\.|source)[ \t]+[^#]*hermetic-env\.sh/) sourced = 1

      # The quoting state must see every code line, so expanded() runs on
      # each; only a line naming a listed variable is matched against it.
      e = expanded(line, 0)
      if (!is_lib && e ~ namere && !exempt(line, prev)) note_read(e, n)

      # mode-bit: a probe satisfies every open fixture; a chmod of an open
      # target closes it (the restore); a restrictive chmod opens one.
      if (line ~ /hermetic_access_denied|-[rw][ \t]/ && ((m = mask(line)) ~ /hermetic_access_denied[ \t]/ || m ~ /(\[|test)[ \t]+(![ \t]+)?-[rw][ \t]/)) {
        for (k in open_line) probed[k] = 1
      }
      if (chmod_args(line)) {
        if (cm_target in open_line) {
          if (!probed[cm_target]) report(path, open_line[cm_target], "mode-bit", "removes owner access to " cm_target " with no access probe before its next chmod")
          delete open_line[cm_target]; delete probed[cm_target]
        }
        if (cm_target != "" && restrictive(cm_mode) && !exempt(line, prev)) {
          open_line[cm_target] = n; probed[cm_target] = 0
        }
      }

      # dead-owner: a $! capture, its wait, then a later use of the PID.
      if (match(line, /(^|[;&])[ \t]*(local[ \t]+)?[A-Za-z_][A-Za-z0-9_]*=\$!/)) {
        v = substr(line, RSTART, RLENGTH)
        sub(/^[;&]?[ \t]*(local[ \t]+)?/, "", v); sub(/=\$!$/, "", v)
        spawned[v] = 1; reaped[v] = 0
      } else {
        for (v in spawned) {
          if (!index(line, v)) continue
          re_v = "\\$\\{?" v "([^A-Za-z0-9_]|$)"
          if (line !~ re_v) continue
          if (mask(line) ~ /(^|[;&|( \t])wait[ \t]/) { reaped[v] = n; continue }
          if (reaped[v] && line !~ /^[ \t]*(kill|wait)[ \t]/) {
            if (!exempt(line, prev)) report(path, n, "dead-owner", "uses $" v " after line " reaped[v] " reaped it")
            delete spawned[v]; delete reaped[v]
          }
        }
      }

      if (match(line, /<<-?[ \t]*\\?['"'"'"]?[A-Za-z0-9_.+-]+/)) {
        pre = substr(line, 1, RSTART - 1)
        dq = gsub(/"/, "\"", pre)
        sq = gsub(/'"'"'/, "&", pre)
        if (dq % 2 == 0 && sq % 2 == 0) {
          delim = substr(line, RSTART, RLENGTH)
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
    if (!sourced) {
      for (k = 1; k <= nreads; k++) {
        report(path, readln[k], "unsourced", "reads $" readvar[k] " without sourcing tests/lib/hermetic-env.sh")
      }
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
