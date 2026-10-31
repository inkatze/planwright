# shellcheck shell=bash
# shell-rule-lib.sh — the shared scanner behind the shell rule checks
# (scripts/check-shell-*.sh), sourced, never executed. config/guard-catalog.yaml
# (the shell-* entries) lists the rules; each rule is its own script and mise task
# so a rule that fires wrongly can be switched off alone.

# A rule script sets SR_RULE (its catalog id), SR_USAGE (its --help text) and
# SR_AWK (awk source defining rule_reset() and rule_check(code, lineno), which
# returns the offense message or ""), then calls `sr_main "$@"`.

# What a rule sees is one logical line at a time, length-preserved: quoted text
# is masked (single-quoted bodies and double-quoted literal text become `x`,
# double-quoted expansions and `$(...)` bodies stay readable), the trailing
# comment and heredoc bodies are gone, a quoted string or a backslash
# continuation spanning lines is joined, and inside a `case` block a pattern
# prefix (`a | b)`) is cut so its alternatives never read as a pipeline.
# The globals rule_check may read: RAW (the same logical line unmasked, aligned
# with code), prev_code (the previous logical line's code) and FILE (the path).

# The escape hatch is `# <rule-id>: <reason>`, trailing the line or on the
# comment line directly above it. One with no reason exempts nothing.

# Scope: every shell file (by shebang or .sh suffix) under scripts/, githooks/
# and tests/lib/. The tests/*.sh suites are outside it: test-vacuity and
# hermeticity are owned by their own guards, and a portability defect in a
# suite fails that suite on the platform it breaks.

# Exit codes: 0 clean, 1 an offense, 2 usage or a scan covering less than it
# claims (an absent root or scope directory, an unreadable file, no files, a
# file ending inside an open quote or heredoc).

unset CDPATH

SR_SCOPE_DIRS="scripts githooks tests/lib"

sr_sanitize_printable() {
  _srp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237' 2>/dev/null) || _srp=''
  [ -n "$_srp" ] || _srp=${2:-}
  printf '%s' "$_srp"
}

sr_fail_closed() {
  printf '%s: %s\n' "check-$SR_RULE" "$1" >&2
  exit 2
}

# The engine. Kept in one awk program per run so a file is opened once; files
# are read by getline from a list, never through ARGV, so a name holding `=` or
# a leading `-` stays a path.
# shellcheck disable=SC2016 # literal awk source
SR_ENGINE='
function xs(k,   r) {
  if (XS == "") { XS = "x"; while (length(XS) < 1024) XS = XS XS }
  r = ""
  while (k > 1024) { r = r XS; k -= 1024 }
  return r substr(XS, 1, k)
}
function push(c) { st = st c }
function pop() { if (length(st) > 1) st = substr(st, 1, length(st) - 1) }
function top() { return substr(st, length(st), 1) }
# A quote (or a ${...} inside one) is open, so the logical line continues.
function inquote(   t) { t = top(); return (t == "s" || t == "d" || t == "a" || t == "B") }
# mask(s): one physical line through the quote/substitution state machine,
# carrying st across lines. Sets cmt to the comment text (or "").
function mask(s,   n, i, c, nx, out, t, j, d, q, hit) {
  out = ""; cmt = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    t = top()
    # Copy the run of ordinary characters up to the next one that can change
    # state in one step; per-character concatenation is quadratic in awk.
    q = (t == "s" || t == "d" || t == "a")
    if (t == "s") hit = match(substr(s, i), /\047/)
    else if (t == "a") hit = match(substr(s, i), /[\\\047]/)
    else if (t == "d") hit = match(substr(s, i), /[\\"$`]/)
    else if (t == "B") hit = match(substr(s, i), /[\\"$`}]/)
    else hit = match(substr(s, i), /[\\\047"#$()`]/)
    if (!hit) { out = out (q ? xs(n - i + 1) : substr(s, i)); break }
    if (RSTART > 1) { out = out (q ? xs(RSTART - 1) : substr(s, i, RSTART - 1)); i += RSTART - 1 }
    c = substr(s, i, 1); nx = substr(s, i + 1, 1)
    if (t == "s") {
      if (c == "\047") { pop(); out = out c } else out = out "x"
      continue
    }
    # $'...' (bash ANSI-C quoting): a backslash escapes the next character,
    # a quote included, so it cannot share the plain single-quote state.
    if (t == "a") {
      if (c == "\\" && i < n) { out = out "xx"; i++; continue }
      if (c == "\047") { pop(); out = out c } else out = out "x"
      continue
    }
    # B: a ${...} inside double quotes, kept readable; it may hold quotes of its
    # own and span lines ("${v#*"<newline>$x"}").
    if (t == "B") {
      if (c == "\\" && i < n) { out = out c nx; i++; continue }
      if (c == "}") { pop(); out = out c; continue }
      if (c == "\"") { push("d"); out = out c; continue }
      if (c == "$" && nx == "(") { push("C"); out = out "$("; i++; continue }
      if (c == "$" && nx == "{") { push("B"); out = out "${"; i++; continue }
      if (c == "`") { push("b"); out = out c; continue }
      out = out c; continue
    }
    if (t == "d") {
      if (c == "\\" && i < n) { out = out "xx"; i++; continue }
      if (c == "\"") { pop(); out = out c; continue }
      if (c == "$" && nx == "(") { push("C"); out = out "$("; i++; continue }
      if (c == "`") { push("b"); out = out c; continue }
      if (c == "$" && nx == "{") { push("B"); out = out "${"; i++; continue }
      if (c == "$" && nx ~ /[0-9@*#?!$-]/) { out = out c nx; i++; continue }
      if (c == "$" && nx ~ /[A-Za-z_]/) {
        j = i + 1
        while (j <= n && substr(s, j, 1) ~ /[A-Za-z0-9_]/) j++
        out = out substr(s, i, j - i); i = j - 1; continue
      }
      out = out "x"; continue
    }
    if (c == "\\" && i < n) { out = out c nx; i++; continue }
    if (c == "\047") { push("s"); out = out c; continue }
    if (c == "\"") { push("d"); out = out c; continue }
    if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t;&|(]/)) {
      cmt = substr(s, i)
      while (length(out) < n) out = out " "
      return out
    }
    if (c == "$" && nx == "\047") { push("a"); out = out "$\047"; i++; continue }
    if (c == "$" && nx == "(") { push("C"); out = out "$("; i++; continue }
    if (c == "(") { push("p"); out = out c; continue }
    if (c == ")") { if (t == "C" || t == "p") pop(); out = out c; continue }
    if (c == "`") { if (t == "b") pop(); else push("b"); out = out c; continue }
    out = out c
  }
  return out
}
function annotated(text,   re) {
  re = "#[ \t]*" RULE ":"
  if (text !~ re) return 0
  if (text ~ (re "[ \t]*[^ \t]")) return 1
  return -1
}
function report(lineno, msg) { print FILE "\t" lineno "\t" msg; found = 1 }
function judge(lineno, code, ccmt, rawl,   msg, a, e) {
  RAW = rawl
  # Only where a pattern can start: the line after `case ... in` or after a
  # branch end. A body line opening a subshell keeps its commands.
  if (casedepth > 0 && casepat && match(code, /^[ \t]*\(?[^()]*\)/)) {
    code = sprintf("%" RLENGTH "s", "") substr(code, RLENGTH + 1)
  }
  casepat = (casedepth > 0 && code ~ /;;|;&/)
  # A [[ =~ ]] pattern is a regex, not commands: its | is alternation.
  while ((a = index(code, "=~")) > 0) {
    msg = substr(code, a + 2)
    e = index(msg, "]]")
    if (!e) e = length(msg) + 1
    code = substr(code, 1, a - 1) "  " xs(e - 1) substr(msg, e)
  }
  if (code ~ /(^|[ \t;(])case[ \t]/ && code ~ /[ \t]in([ \t]|$)/) { casedepth++; casepat = 1 }
  if (code ~ /(^|[ \t;])esac([ \t;)]|$)/ && casedepth > 0) casedepth--
  msg = rule_check(code, lineno)
  if (msg != "") {
    a = annotated(ccmt)
    if (a == 0) a = annotated(above)
    if (a == 1) msg = ""
    else if (a == -1) msg = "the " RULE " annotation carries no reason, so it exempts nothing"
  }
  if (msg != "") report(lineno, msg)
  prev_code = code
}
function scan(path,   line, r, code, body, pre, delim, dash, lg, lgc, lgcmt, lstart, fresh) {
  FILE = path; st = "c"; heredoc = ""; above = ""; prev_code = ""; casedepth = 0; casepat = 0
  lg = ""; lgc = ""; lgcmt = ""; lstart = 0; nr = 0
  rule_reset()
  while ((r = (getline line < path)) > 0) {
    nr++
    sub(/\r$/, "", line)
    if (heredoc != "") {
      body = line
      if (heredoc_dash) sub(/^\t+/, "", body)
      if (body == heredoc) heredoc = ""
      continue
    }
    fresh = (lg == "" && st == "c")
    if (fresh && line ~ /^[ \t]*#/) { above = line; continue }
    if (fresh && line ~ /^[ \t]*$/) { above = ""; continue }
    if (lg == "") lstart = nr
    code = mask(line)
    lg = lg (lg == "" ? "" : " ") line
    lgc = lgc (lgc == "" ? "" : " ") code
    if (cmt != "") lgcmt = lgcmt " " cmt
    if (match(code, /<<-?[ \t]*\\?[\047"]?[A-Za-z0-9_.+-]+/) && substr(code, RSTART, 3) != "<<<" && (RSTART == 1 || substr(code, RSTART - 1, 1) != "<")) {
      delim = substr(line, RSTART, RLENGTH)
      dash = (delim ~ /^<<-/)
      sub(/^<<-?[ \t]*/, "", delim)
      # An unquoted number is an arithmetic shift ($((1 << 4))), not a
      # heredoc; reading it as one would swallow the rest of the file.
      if (delim !~ /^[0-9]+$/) {
        sub(/^\\/, "", delim); sub(/^[\047"]/, "", delim)
        heredoc = delim; heredoc_dash = dash
      }
    }
    if (inquote()) continue
    if (code ~ /\\$/ && heredoc == "") { sub(/\\$/, "", lgc); sub(/\\$/, "", lg); continue }
    # A trailing pipe or list operator continues the command on the next line.
    if (heredoc == "" && code ~ /(\||&&)[ \t]*$/) continue
    judge(lstart, lgc, lgcmt, lg)
    above = ""; lg = ""; lgc = ""; lgcmt = ""
  }
  close(path)
  if (r < 0) { print "!\t" path; return }
  # A heredoc or quote still open at end of file means the tail went unjudged.
  if (heredoc != "" || inquote()) { print "?\t" path; return }
  if (lg != "") judge(lstart, lgc, lgcmt, lg)
}
# What may precede a command word: a separator, then the keywords and the
# wrappers that leave the next word as the command run, an assignment prefix,
# and a shell running it as a script (/bin/sh name).
function cw_prefix() {
  return "(^|[;&|({!`]|\\$\\()[ \t]*((if|then|do|else|elif|while|until|time|command|exec|builtin|nohup|env|!|([^ \t;&|()]*/)?(ba)?sh)[ \t]+)*([A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+)*"
}
# Command-word position of name in code (after cw_prefix, with a path prefix
# allowed), or 0.
function cmdword(code, name,   re) {
  # The regex below is the hot spot of every rule; a literal name absent from
  # the line cannot match it.
  if (name !~ /[\\(]/ && !index(code, name)) return 0
  re = cw_prefix() "[\"]?([^ \t;&|()\"]*/)?" name "[\"]?([ \t;)|&]|$)"
  if (!match(code, re)) return 0
  CW_END = RSTART + RLENGTH
  return RSTART
}
# Operand words of the command whose word ended at CW_END: split on blanks up
# to the first ; | & ) at this level, redirections dropped. Fills OPS[1..n].
function operands(code,   rest, n, k, w, words, cnt, skipnext) {
  # The command word ended the command (`mktemp; next`): it has no operands.
  if (substr(code, CW_END - 1, 1) ~ /[;|&)]/) return 0
  rest = substr(code, CW_END - 1)
  sub(/^[\"]?[ \t;)|&]?/, "", rest)
  if (match(rest, /[;|&)]/)) rest = substr(rest, 1, RSTART - 1)
  cnt = split(rest, words, /[ \t]+/); n = 0; skipnext = 0
  for (k = 1; k <= cnt; k++) {
    w = words[k]
    if (w == "") continue
    if (skipnext) { skipnext = 0; continue }
    if (w ~ /^[0-9]*(>>?|<|>&|<&)$/) { skipnext = 1; continue }
    if (w ~ /^[0-9]*(>>?|<|>&|<&)/) continue
    OPS[++n] = w
  }
  return n
}
BEGIN {
  while ((lr = (getline path < listfile)) > 0) scan(path)
  if (lr < 0) print "!\t" listfile
}
'

# sr_main [<root>] | --help — enumerate, scan, report.
sr_main() {
  LC_ALL=C
  export LC_ALL
  case "${1:-}" in
    --help | -h)
      [ "$#" -eq 1 ] || sr_fail_closed "--help takes no other arguments"
      printf '%s\n' "$SR_USAGE"
      exit 0
      ;;
    -*) sr_fail_closed "unknown option: $(sr_sanitize_printable "$1" "(unprintable)") (see --help)" ;;
  esac
  [ "$#" -le 1 ] || sr_fail_closed "too many arguments (expected at most one root)"
  sr_root=${1:-$(cd "$(dirname "$0")/.." && pwd -P)}
  sr_safe_root=$(sr_sanitize_printable "$sr_root" "(unprintable path)")
  [ -d "$sr_root" ] || sr_fail_closed "root not found or not a directory: $sr_safe_root"
  for sr_dir in $SR_SCOPE_DIRS; do
    [ -d "$sr_root/$sr_dir" ] \
      || sr_fail_closed "scope directory $sr_dir missing under $sr_safe_root, so the scan would cover less than it claims"
  done
  sr_work=$(mktemp -d "${TMPDIR:-/tmp}/check-$SR_RULE.XXXXXX") \
    || sr_fail_closed "could not create a temporary directory"
  # shellcheck disable=SC2064 # expand the path now: the trap outlives the scope
  trap "rm -rf '$sr_work'" EXIT
  : >"$sr_work/all"
  for sr_dir in $SR_SCOPE_DIRS; do
    find -P "$sr_root/$sr_dir" \( -type f -o -type l \) -print0 >>"$sr_work/all" 2>"$sr_work/err" \
      || sr_fail_closed "find failed under $sr_safe_root/$sr_dir: $(sr_sanitize_printable "$(head -n 1 "$sr_work/err")" "(no message)")"
  done
  : >"$sr_work/list"
  sr_count=0
  sr_nl='
'
  sr_tab=$(printf '\t')
  while IFS= read -r -d '' sr_file; do
    sr_rel=${sr_file#"$sr_root"/}
    case "$sr_file" in
      *"$sr_nl"* | *"$sr_tab"*)
        sr_fail_closed "filename contains a newline or tab, refusing to scan: $(sr_sanitize_printable "$sr_rel" "(unprintable filename)")"
        ;;
    esac
    if [ -L "$sr_file" ] && [ -d "$sr_file" ]; then
      sr_fail_closed "symlinked directory in the scan scope, refusing to follow: $(sr_sanitize_printable "$sr_rel" "(unprintable filename)")"
    fi
    if [ -L "$sr_file" ] && [ -e "$sr_file" ] && [ ! -f "$sr_file" ]; then
      sr_fail_closed "symlink in the scan scope resolves to neither a file nor a directory, refusing to read it: $(sr_sanitize_printable "$sr_rel" "(unprintable filename)")"
    fi
    [ -r "$sr_file" ] \
      || sr_fail_closed "cannot read $(sr_sanitize_printable "$sr_rel" "(unprintable filename)"), so the scan would cover less than it claims"
    sr_first=''
    IFS= read -r sr_first <"$sr_file" 2>/dev/null || :
    case "$sr_first" in
      '#!'*) ;;
      *) case "$sr_file" in *.sh) ;; *) continue ;; esac ;;
    esac
    printf '%s\n' "$sr_file" >>"$sr_work/list"
    sr_count=$((sr_count + 1))
  done <"$sr_work/all"
  [ "$sr_count" -gt 0 ] \
    || sr_fail_closed "no shell files found under $SR_SCOPE_DIRS in $sr_safe_root, a broken enumeration rather than a clean tree"

  # Values reach awk through ENVIRON: -v would expand backslash escapes in a path.
  RULE=$SR_RULE SR_LIST="$sr_work/list" awk "BEGIN { RULE = ENVIRON[\"RULE\"]; listfile = ENVIRON[\"SR_LIST\"] }
$SR_AWK
$SR_ENGINE" >"$sr_work/offenders" || sr_fail_closed "the scan could not complete"

  sr_status=0
  while IFS="$sr_tab" read -r sr_file sr_line sr_msg; do
    [ -n "$sr_file" ] || continue
    [ "$sr_file" != "!" ] \
      || sr_fail_closed "could not read $(sr_sanitize_printable "${sr_line#"$sr_root"/}" "(unprintable filename)") during the scan"
    [ "$sr_file" != "?" ] \
      || sr_fail_closed "$(sr_sanitize_printable "${sr_line#"$sr_root"/}" "(unprintable filename)") ends inside an open quote or heredoc, so the scan could not judge its tail"
    printf '%s: %s:%s: %s\n' "check-$SR_RULE" \
      "$(sr_sanitize_printable "${sr_file#"$sr_root"/}" "(unprintable filename)")" "$sr_line" \
      "$(sr_sanitize_printable "$sr_msg" "(unprintable message)")" >&2
    sr_status=1
  done <"$sr_work/offenders"
  [ "$sr_status" -ne 0 ] || printf '%s: clean (%s files)\n' "check-$SR_RULE" "$sr_count"
  exit "$sr_status"
}
