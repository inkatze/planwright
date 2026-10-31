#!/usr/bin/env bash
# check-test-vacuity.sh — fail a test whose assertion cannot fail, and a corpus
# harness that passes over zero rows.
#
# Usage: check-test-vacuity.sh [<root>]
#   <root>  the tree whose tests/ is scanned (default: this script's repository)
#   check-test-vacuity.sh --help | -h
# Exit codes: 0 clean; 1 a finding; 2 usage error or a scan that cannot cover
# what it claims. --help states the rules and the annotation that excludes one.
#
# Portable bash 3.2 / BSD tooling. All input is data.
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

me=check-test-vacuity
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)" || exit 2

fail_closed() {
  printf '%s: %s\n' "$me" "$1" >&2
  exit 2
}

usage() {
  cat <<'EOF'
check-test-vacuity.sh: a test assertion must be able to fail.

Usage: check-test-vacuity.sh [<root>]
       check-test-vacuity.sh --help | -h

Scanned: every file under <root>/tests reached by shebang or an .sh suffix,
except the data under tests/fixtures/. Heredoc bodies and comments are not code.

Rules, each reported as file:line: rule:
  no-positive-control  a tests/test-*.sh file asserting only absences (an
                       assert_not_*, assert_no_*, assert_absent*, assert_lacks*,
                       refute* call or a negated grep) and nothing present, so
                       an empty output passes it.
  piped-status         a status read ($? on the next statement, or a chained
                       pass/ok/fail) after a pipeline whose last stage is a
                       filter (tail, head, tee, sed, awk, cut, sort, uniq, tr,
                       cat, wc, fold, column, nl, paste): the filter's status,
                       not the command under test. A file that sets pipefail
                       is exempt.
  masked-status        a status read after a command ending in `|| true` or
                       `|| :`, or an if/elif/while condition ending in one.
  self-comparison      a [ ], [[ ]] or test comparison of an operand to itself.
  zero-row-floor       a while-read loop that asserts inside its body, fed from
                       a corpus (a redirect naming corpus, fixture, cases, .tsv
                       or .csv), with no row counter compared after it to a
                       floor above zero.

Excluding a finding: append `# vacuity-ok: <reason>` to the reported line; the
reason is required.

Exit codes: 0 clean; 1 a finding; 2 usage error, a root without tests/, an
unreadable file, or a scan reaching no shell files.
EOF
}

case "${1:-}" in
  --help | -h)
    [ "$#" -eq 1 ] || fail_closed "--help takes no other arguments"
    usage
    exit 0
    ;;
  -*) fail_closed "unknown option (see --help)" ;;
esac
[ "$#" -le 1 ] || fail_closed "too many arguments (expected at most one root)"

root="${1:-$repo_root}"
[ -d "$root/tests" ] || fail_closed "no tests directory under the root"

work="$(mktemp -d "${TMPDIR:-/tmp}/check-test-vacuity.XXXXXX")" \
  || fail_closed "could not create a temporary directory"
trap 'rm -rf "$work"' EXIT

find -P "$root/tests" -type f -print0 >"$work/all" 2>/dev/null \
  || fail_closed "find failed under the tests directory"

: >"$work/list"
newline='
'
while IFS= read -r -d '' file; do
  rel="${file#"$root"/}"
  case "$rel" in tests/fixtures/*) continue ;; esac
  case "$file" in *"$newline"*) fail_closed "a filename contains a newline, refusing to scan" ;; esac
  [ -r "$file" ] || fail_closed "a test file is unreadable"
  first=""
  IFS= read -r first <"$file" 2>/dev/null || true
  case "$first" in
    '#!'*sh*) ;;
    *) case "$file" in *.sh) ;; *) continue ;; esac ;;
  esac
  printf '%s\n' "$rel" >>"$work/list"
done <"$work/all"

[ -s "$work/list" ] || fail_closed "no shell files found under tests/, a broken enumeration rather than a clean tree"

TV_ROOT=$root TV_LIST=$work/list TV_ME=$me
export TV_ROOT TV_LIST TV_ME
awk '
  function clean(s) { gsub(/[\001-\037\177]/, "", s); return s }
  function report(line, rule, why) {
    printf "%s: %s:%d: %s: %s\n", ENVIRON["TV_ME"], clean(file), line, rule, why
    bad = 1
  }
  # Quoted text is data: a quoted string becomes one word, its operator and
  # blank characters replaced, and a comment goes.
  function strip(s,   o, i, c, st, prev) {
    if (s !~ /['"'"'"#\\]/) return s
    o = ""; st = ""; prev = " "
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (st == "s") { if (c == "'"'"'") st = ""; else o = o (c ~ /[|;&#<>()$` \t]/ ? "_" : c); prev = c; continue }
      if (c == "\\" && st != "s") { o = o c substr(s, i + 1, 1); i++; prev = "x"; continue }
      if (st == "d") {
        if (c == "\"") st = ""
        else if (c !~ /[|;&#<>() \t]/) o = o c
        else o = o "_"
        prev = c; continue
      }
      if (c == "'"'"'") { st = "s"; o = o "Q"; continue }
      if (c == "\"") { st = "d"; o = o "\""; prev = c; continue }
      if (c == "#" && prev ~ /[ \t;&|(]/) break
      o = o c; prev = c
    }
    return o
  }
  function annotated(i) { return R[i] ~ /#[ \t]*vacuity-ok:[ \t]*[^ \t]/ }
  function filter_stage(p,   n, parts, w) {
    n = split(p, parts, /[^|]\|[^|]/)
    if (n < 2) return 0
    w = parts[n]
    sub(/^[ \t({!]+/, "", w)
    while (w ~ /^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]/) sub(/^[^ \t]+[ \t]+/, "", w)
    if (w ~ /^(awk|[^ \t]*\/awk)[ \t]/ && w ~ /exit/) return 0
    if (w ~ /^(sort|[^ \t]*\/sort)[ \t].*[ \t]-[A-Za-z]*[cC]/) return 0
    sub(/[ \t;)&|].*/, "", w)
    sub(/.*\//, "", w)
    return w ~ /^(tail|head|tee|sed|awk|cut|sort|uniq|tr|cat|wc|fold|column|nl|paste)$/
  }
  # The status of a command substitution is the status of its assignment only.
  function outer(s) { while (gsub(/\$\([^()]*\)/, "V", s)) ; return s }
  function stage_of(s) { return s ~ /^[ \t]*[A-Za-z_][A-Za-z0-9_]*=\$\(/ ? s : outer(s) }
  function reads_status(s) { return s ~ /^[ \t]*[^;|&$]*\$\?/ && s !~ /^[ \t]*[^$]*\$\(/ }
  function is_neg(w) { return w ~ /^(assert_not_|assert_no_|assert_absent|assert_lacks|refute)/ }
  function words_at_command(s, out,   n, parts, i, w, k) {
    n = split(s, parts, /&&|\|\||[|;]/)
    k = 0
    for (i = 1; i <= n; i++) {
      w = parts[i]
      sub(/^[ \t({]+/, "", w)
      while (w ~ /^(if|then|else|elif|do|while|until)[ \t]/) sub(/^[a-z]+[ \t]+/, "", w)
      out[++k] = w
    }
    return k
  }
  function classify(s, line,   n, cw, i, w, first) {
    n = words_at_command(s, cw)
    for (i = 1; i <= n; i++) {
      w = cw[i]; first = w; sub(/[ \t].*/, "", first)
      if (w ~ /^![ \t]+grep[ \t]/) { if (!negline) negline = line; continue }
      if (is_neg(first)) { if (!negline) negline = line; continue }
      if (first ~ /^(assert|expect)[A-Za-z_]*$/ || first == "pass" || first == "ok") pos = 1
      if (first == "grep" && w ~ /[ \t]-[A-Za-z]*q/) pos = 1
    }
    if (s ~ /(\[|test)[ \t].*\|\|[ \t]*fail/) pos = 1
  }
  function self_compare(s, line,   n, t, i) {
    n = split(s, t, /[ \t]+/)
    for (i = 1; i + 3 <= n; i++)
      if ((t[i] == "[" || t[i] == "[[" || t[i] == "test") && t[i + 2] ~ /^(=|==|!=|-eq|-ne|-le|-ge|-lt|-gt)$/ \
        && t[i + 1] == t[i + 3] && t[i + 1] !~ /\$\(|`/) {
        if (!annotated(line)) report(line, "self-comparison", "an operand compared to itself cannot fail")
        return
      }
  }
  function counter_of(s,   name, rest) {
    if (match(s, /[A-Za-z_][A-Za-z0-9_]*=\$\(\([ \t]*\$?[A-Za-z_][A-Za-z0-9_]*[ \t]*\+/)) {
      name = substr(s, RSTART, RLENGTH); sub(/=.*/, "", name)
      rest = substr(s, RSTART, RLENGTH); sub(/^[^=]*=\$\(\([ \t]*\$?/, "", rest); sub(/[ \t]*\+$/, "", rest)
      if (rest == name) return name
    }
    if (match(s, /\(\([ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*(\+\+|\+=)/)) { name = substr(s, RSTART, RLENGTH); sub(/^\(\([ \t]*/, "", name); sub(/[ \t+=]+$/, "", name); return name }
    if (match(s, /^[ \t]*[A-Za-z_][A-Za-z0-9_]*(\+=\(|\[[^]]*\]=)/)) { name = substr(s, RSTART, RLENGTH); sub(/^[ \t]*/, "", name); sub(/[+[].*/, "", name); return name }
    return ""
  }
  # A floor compares the counter to a literal or a min/floor variable; one that
  # admits zero rows (-ge 0, -gt -1, -lt 0, -le -1) is no floor.
  function bound(op, val,   v) {
    if (val ~ /^"?[$][{]?[A-Za-z_]*([Mm][Ii][Nn]|[Ff][Ll][Oo][Oo][Rr])/) return 1
    if (val !~ /^"?-?[0-9]+("|[^0-9]|$)/) return 0
    v = val; gsub(/"/, "", v); v = v + 0
    if ((op == "-ge" || op == ">=" || op == "-lt" || op == "<") && v <= 0) return 0
    if ((op == "-gt" || op == ">" || op == "-le" || op == "<=") && v < 0) return 0
    return 1
  }
  function floor_after(names, from,   i, k, nn, nm, fwd, ar, rest, o) {
    nn = split(names, nm, " ")
    for (k = 1; k <= nn; k++) {
      if (nm[k] == "" || nm[k] ~ /^(fail|err)/) continue
      fwd = "[$][{]?#?" nm[k] "([[][@*][]])?[}]?[\"]?[ \t]+-(gt|ge|lt|le|eq|ne)[ \t]+"
      ar = "[(][(][ \t]*" nm[k] "[ \t]*(<=|>=|==|!=|<|>)[ \t]*"
      for (i = 1; i <= ns; i++) {
        if (SL[i] <= from) continue
        if (match(S[i], fwd) || match(S[i], ar)) {
          rest = substr(S[i], RSTART + RLENGTH)
          o = substr(S[i], RSTART, RLENGTH)
          sub(/[ \t]+$/, "", o); sub(/.*[ \t(]/, "", o); sub(/.*[^-<>=!a-z]/, "", o)
          if (bound(o, rest)) return 1
        }
      }
    }
    return 0
  }
  function statement(s, line,   segs, n, i, prev, seg, tgt) {
    n = split(s, segs, /;/)
    for (i = 1; i <= n; i++) {
      seg = segs[i]
      if (seg ~ /^[ \t]*$/) continue
      S[++ns] = seg; SL[ns] = line
      if (ns > 1 && SL[ns - 1] >= line - 3 && reads_status(seg)) {
        prev = S[ns - 1]
        if (!pipefail && filter_stage(stage_of(prev)) && !annotated(line))
          report(line, "piped-status", "the status read is a filter stage'"'"'s, not the command under test'"'"'s")
        if (prev ~ /\|\|[ \t]*(true|:)[ \t]*\)?[ \t]*$/ && !annotated(line))
          report(line, "masked-status", "the status read follows an always-true alternative")
      }
      if (seg ~ /^[ \t]*(if|elif|while)[ \t].*\|\|[ \t]*(true|:)[ \t]*$/ && !annotated(line))
        report(line, "masked-status", "the condition ends in an always-true alternative")
      if (match(seg, /(&&[ \t]*(pass|ok)|\|\|[ \t]*fail)([ \t]|$)/) && filter_stage(outer(substr(seg, 1, RSTART - 1))) && !pipefail && !annotated(line))
        report(line, "piped-status", "the chained assertion reads a filter stage'"'"'s status")
      self_compare(seg, line)
      classify(seg, line)
      if (seg ~ /^[ \t]*(while|until|for)[ \t]/) { sp++; LA[sp] = 0; LC[sp] = ""; LS[sp] = line }
      if (sp && (seg ~ /(^|[ \t])(fail|pass|ok)([ \t]|$)/ || seg ~ /(^|[ \t])(assert|expect)[A-Za-z_]*[ \t]/)) LA[sp] = 1
      tgt = counter_of(seg)
      if (sp && tgt != "") LC[sp] = LC[sp] " " tgt
      if (sp && seg ~ /(^|[ \t])done([ \t<]|$)/) {
        tgt = ""
        if (match(seg, /done[ \t]*<[^<(][^ \t]*/)) tgt = tolower(substr(seg, RSTART, RLENGTH))
        if (LA[sp] && tgt ~ /corpus|fixture|cases|\.tsv|\.csv/) { np++; PL[np] = line; PC[np] = LC[sp] }
        if (sp > 1) { LA[sp - 1] = LA[sp - 1] || LA[sp]; LC[sp - 1] = LC[sp - 1] " " LC[sp] }
        sp--
      }
    }
  }
  function scan(path,   r, line, raw, s, cur, start, heredoc, hd, body, pre, dq, sq, delim, i) {
    heredoc = ""; cur = ""; ns = 0; np = 0; sp = 0; pipefail = 0; negline = 0; pos = 0; nl = 0
    while ((r = (getline raw < path)) > 0) {
      nl++; sub(/\r$/, "", raw); R[nl] = raw
      if (heredoc != "") {
        body = raw
        if (hd) sub(/^\t+/, "", body)
        if (body == heredoc) heredoc = ""
        continue
      }
      if (raw ~ /^[ \t]*#/ || raw ~ /^[ \t]*$/) continue
      s = strip(raw)
      if (cur == "") start = nl
      if (s ~ /\\$/) { sub(/\\$/, "", s); cur = cur " " s; continue }
      cur = cur " " s
      if (s ~ /(\||&&)[ \t]*$/) continue
      if (cur ~ /set[ \t].*pipefail/) pipefail = 1
      statement(cur, start)
      cur = ""
      if (match(raw, /<<-?[ \t]*\\?['"'"'"]?[A-Za-z0-9_.+-]+/) && substr(raw, RSTART, 3) != "<<<") {
        pre = substr(raw, 1, RSTART - 1)
        dq = gsub(/"/, "\"", pre); sq = gsub(/'"'"'/, "&", pre)
        if (dq % 2 == 0 && sq % 2 == 0) {
          delim = substr(raw, RSTART, RLENGTH)
          hd = (delim ~ /^<<-/)
          sub(/^<<-?[ \t]*/, "", delim); sub(/^\\/, "", delim); sub(/^['"'"'"]/, "", delim)
          heredoc = delim
        }
      }
    }
    close(path)
    if (r < 0) { unreadable = 1; return }
    if (cur != "") statement(cur, start)
    for (i = 1; i <= np; i++)
      if (!floor_after(PC[i], PL[i]) && !annotated(PL[i]))
        report(PL[i], "zero-row-floor", "the corpus loop has no row count compared to a floor above zero")
    base = file; sub(/.*\//, "", base)
    if (base ~ /^test-.*\.sh$/ && negline && !pos && !annotated(negline))
      report(negline, "no-positive-control", "the file asserts only absences, which an empty output satisfies")
  }
  BEGIN {
    lf = ENVIRON["TV_LIST"]
    while ((lr = (getline file < lf)) > 0) { scan(ENVIRON["TV_ROOT"] "/" file); if (unreadable) break }
    if (lr < 0) unreadable = 1
    if (unreadable) { print ENVIRON["TV_ME"] ": a file could not be read during the scan" > "/dev/stderr"; exit 2 }
    exit bad ? 1 : 0
  }
' >"$work/out"
rc=$?
cat "$work/out"
case $rc in
  0) printf '%s: clean (%s files)\n' "$me" "$(wc -l <"$work/list" | tr -d ' ')" ;;
  1) ;;
  *) exit 2 ;;
esac
exit "$rc"
