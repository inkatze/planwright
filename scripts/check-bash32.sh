#!/bin/sh
# check-bash32.sh — the bash 3.2 regression guards.
#
# macOS ships bash 3.2 as both /bin/bash and /bin/sh, and its parser misreads
# constructs every later bash accepts, so a script can pass every Linux run and
# still fail to parse on a Mac. Two guards hold that line, sharing one file set:
#
#   parse  runs each covered file through `bash -n`, or `bash --posix -n` for
#          an sh-dialect file, with the bash on PATH (or --bash). CI runs it
#          inside the bash:3.2 image (.github/workflows/ci.yml), the real
#          parser being the only ground truth. A later bash passes everything
#          this guard exists to catch, so a parser whose version does not
#          start with --expect-version (default 3.2) is refused rather than
#          reported clean.
#   lint   flags, by pattern, the constructs bash 3.2 is known to misparse,
#          so a Linux-only local run catches their return before a push:
#            - a heredoc inside a `$( )` command substitution whose body
#              holds an unbalanced quote, backtick, or `(` (or, in a bare
#              `$( )`, a stray `)`): 3.2 lexes the body as shell and runs
#              off the end of the file. It honors a `#` comment there unless
#              the substitution is double-quoted.
#            - a `case` pattern without its leading `(` inside a `$( )`: 3.2
#              reads the pattern's `)` as the substitution's end. Adding the
#              `(` parses, but shfmt rewrites it back to the bare form, so the
#              remedy is to move the `case` out of the substitution.
#          A heredoc whose delimiter never appears is a finding too, since
#          the lint cannot read past it.
#
# Dialect: the shebang's interpreter (sh or dash, bash; directly or through
# env), else a `# shellcheck shell=` directive in the file's leading comment
# block, which is how the shebang-less sourced libraries declare themselves.
# A file naming any other interpreter is out of scope; a .sh file declaring
# neither is a finding (exit 1), so a new library cannot slip past unparsed.
#
# The file set is the tracked files under <root> (`git ls-files`), or the
# newline-separated relative paths --files-from names (`-` for stdin), which is
# how the CI step feeds a container with no git in it. tests/fixtures/bash32/
# is excluded: it holds the misparsing fixtures these guards are tested on.
#
# Usage:
#   check-bash32.sh parse [--root <dir>] [--files-from <file>|-]
#                         [--bash <path>] [--expect-version <prefix>]
#   check-bash32.sh lint  [--root <dir>] [--files-from <file>|-]
#   check-bash32.sh list  [--root <dir>] [--files-from <file>|-]
#   check-bash32.sh pin   <workflow-file>
#   check-bash32.sh --help | -h
#
# list prints `<dialect><TAB><path>` for each covered file. pin checks that
# every bash:3.2 image reference in a workflow file carries an @sha256:
# digest, and that there is at least one.
#
# Exit codes: 0 clean, 1 a finding, 2 usage or an enumeration that would cover
# less than it claims (no files, an unreadable listed file, a path git had to
# quote, a path outside the root, a symlink, the wrong parser version).
#
# Portable sh: runs under bash 3.2 and busybox (the bash:3.2 image is Alpine).
set -u

LC_ALL=C
export LC_ALL

unset CDPATH

EXCLUDE_DIR="tests/fixtures/bash32/"

self_dir="$(cd "$(dirname "$0")" && pwd -P)"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

# Filenames and parser output reach the terminal, and on a fork PR both are
# attacker-authored. The inline fallback keeps diagnostics safe when the
# shared helper cannot be sourced.
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
  printf 'check-bash32: %s\n' "$1" >&2
  exit 2
}

usage() {
  cat <<'EOF'
check-bash32.sh — the bash 3.2 regression guards.

Usage:
  check-bash32.sh parse [--root <dir>] [--files-from <file>|-]
                        [--bash <path>] [--expect-version <prefix>]
  check-bash32.sh lint  [--root <dir>] [--files-from <file>|-]
  check-bash32.sh list  [--root <dir>] [--files-from <file>|-]
  check-bash32.sh pin   <workflow-file>
  check-bash32.sh --help | -h

parse  `bash -n` each covered file (`bash --posix -n` for sh dialect) with the
       bash on PATH or --bash; a parser whose version does not start with
       --expect-version (default 3.2; empty accepts any) is refused.
lint   flag, inside a `$( )` command substitution, a heredoc whose body bash
       3.2 would lex unbalanced, and a case pattern without its leading `(`
       (move such a case out of the substitution: shfmt strips the `(`).
list   print `<dialect><TAB><path>` for each covered file.
pin    require an @sha256: digest on every bash:3.2 image reference in a
       workflow file, and at least one such reference.

Covered: tracked files (git ls-files under --root, default this checkout) or
the relative paths --files-from lists, whose dialect is the shebang (sh, dash,
bash; directly or through env), else a `# shellcheck shell=` directive in the
leading comment block. tests/fixtures/bash32/ is excluded. A .sh file
declaring neither is a finding.

Exit codes: 0 clean, 1 a finding, 2 usage or a broken enumeration.
EOF
}

case "${1:-}" in
  --help | -h)
    [ "$#" -eq 1 ] || fail_closed "--help takes no other arguments"
    usage
    exit 0
    ;;
  parse | lint | list | pin) mode=$1 ;;
  '') fail_closed "missing mode: parse, lint, list, or pin (see --help)" ;;
  *) fail_closed "unknown mode: $(sanitize_printable "$1" "(unprintable)") (see --help)" ;;
esac
shift

work="$(mktemp -d "${TMPDIR:-/tmp}/check-bash32.XXXXXX")" \
  || fail_closed "could not create a temporary directory"
trap 'rm -rf "$work"' EXIT

# pin <workflow>: every bash:3.2 image reference digest-pinned, at least one.
# Comments are prose, so a digest in one pins nothing; each reference on a
# line is checked on its own.
if [ "$mode" = pin ]; then
  [ "$#" -eq 1 ] || fail_closed "pin takes exactly one workflow file"
  safe_wf="$(sanitize_printable "$1" "(unprintable path)")"
  [ -r "$1" ] || fail_closed "cannot read workflow file: $safe_wf"
  sed -e 's/^[[:space:]]*#.*//' -e 's/[[:space:]]#.*//' "$1" >"$work/pin.txt" \
    || fail_closed "could not read workflow file: $safe_wf"
  rc=0
  grep -o -E '[^[:space:]"'\'']*bash:3\.2[^[:space:]"'\'']*' "$work/pin.txt" >"$work/pin.occ" || rc=$?
  [ "$rc" -le 1 ] || fail_closed "could not scan workflow file: $safe_wf"
  rc=0
  grep -E '(^|[/=])bash:3\.2([^0-9]|$)' "$work/pin.occ" >"$work/pin.refs" || rc=$?
  [ "$rc" -le 1 ] || fail_closed "could not scan workflow file: $safe_wf"
  if [ ! -s "$work/pin.refs" ]; then
    printf 'check-bash32: no bash:3.2 image reference in %s\n' "$safe_wf" >&2
    exit 1
  fi
  rc=0
  grep -v -E '(^|[/=])bash:3\.2@sha256:[0-9a-f]{64}$' "$work/pin.refs" >"$work/pin.bad" || rc=$?
  [ "$rc" -le 1 ] || fail_closed "could not scan workflow file: $safe_wf"
  if [ "$rc" -eq 0 ]; then
    while IFS= read -r ref; do
      printf 'check-bash32: bash:3.2 image reference without an @sha256: digest: %s\n' \
        "$(sanitize_printable "$ref" "(unprintable reference)")" >&2
    done <"$work/pin.bad"
    exit 1
  fi
  printf 'check-bash32: pin clean\n'
  exit 0
fi

root=$repo_root
files_from=''
bash_bin=bash
expect_version=3.2
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root | --files-from | --bash | --expect-version)
      [ "$#" -ge 2 ] || fail_closed "$1 needs a value"
      case "$1" in
        --root) root=$2 ;;
        --files-from) files_from=$2 ;;
        --bash) bash_bin=$2 ;;
        --expect-version) expect_version=$2 ;;
      esac
      shift 2
      ;;
    *) fail_closed "unknown argument: $(sanitize_printable "$1" "(unprintable)") (see --help)" ;;
  esac
done
if [ "$mode" != parse ]; then
  [ "$bash_bin" = bash ] && [ "$expect_version" = 3.2 ] \
    || fail_closed "--bash and --expect-version apply to parse only"
fi

safe_root="$(sanitize_printable "$root" "(unprintable path)")"
[ -d "$root" ] || fail_closed "root not found or not a directory: $safe_root"

if [ -n "$files_from" ]; then
  if [ "$files_from" = - ]; then
    cat >"$work/all" || fail_closed "could not read the file list from stdin"
  else
    [ -r "$files_from" ] \
      || fail_closed "cannot read the file list: $(sanitize_printable "$files_from" "(unprintable path)")"
    cat "$files_from" >"$work/all" || fail_closed "could not read the file list"
  fi
else
  git -C "$root" -c core.quotepath=off ls-files >"$work/all" 2>"$work/err" \
    || fail_closed "git ls-files failed under $safe_root: $(sanitize_printable "$(cat "$work/err")" "(unprintable)")"
fi

# Path checks are builtins only, so this loop forks nothing per file; the
# dialect of every candidate is read in one awk pass below.
tab="$(printf '\t')"
: >"$work/candidates"
while IFS= read -r rel || [ -n "$rel" ]; do
  [ -n "$rel" ] || continue
  case "$rel" in
    '"'*) fail_closed "git quoted a tracked path, refusing to guess its name: $(sanitize_printable "$rel" "(unprintable filename)")" ;;
    *"$tab"*) fail_closed "path contains a tab, refusing to scan: $(sanitize_printable "$rel" "(unprintable filename)")" ;;
    /* | .. | ../* | */.. | */../*) fail_closed "path leaves the root, refusing to read it: $(sanitize_printable "$rel" "(unprintable filename)")" ;;
    "$EXCLUDE_DIR"*) continue ;;
  esac
  file="$root/$rel"
  # A symlink has no honest reading: following it may leave the root, and
  # skipping it covers less than the scan claims.
  [ ! -L "$file" ] \
    || fail_closed "symlink in the scan, refusing to follow or skip it: $(sanitize_printable "$rel" "(unprintable filename)")"
  [ -f "$file" ] && [ -r "$file" ] \
    || fail_closed "cannot read $(sanitize_printable "$rel" "(unprintable filename)") — the scan would cover less than it claims"
  printf '%s\n' "$rel" >>"$work/candidates"
done <"$work/all"

# One record per candidate: `sh|bash<TAB>path`, `none<TAB>path` for a .sh file
# declaring no dialect, `!<TAB>path` for a file that could not be read.
# Files are opened by getline rather than through ARGV, so a name containing
# `=` or a leading `-` is read as a path.
awk -v listfile="$work/candidates" -v root="$root" '
  function dialect_name(w) {
    sub(/^.*\//, "", w)
    if (w == "sh" || w == "dash") return "sh"
    if (w == "bash") return "bash"
    return "other"
  }
  function classify(path,   line, r, n, w, i, d) {
    r = (getline line < path)
    if (r < 0) return "!"
    if (r == 0) { close(path); return "none" }
    sub(/\r$/, "", line)
    if (line ~ /^#!/) {
      close(path)
      n = split(substr(line, 3), w, /[ \t]+/)
      i = 1
      if (w[i] == "") i++
      if (dialect_name(w[i]) == "other" && w[i] ~ /(^|\/)env$/) {
        for (i++; i <= n && (w[i] ~ /^-/ || w[i] ~ /=/); i++) ;
      }
      return dialect_name(w[i])
    }
    # No shebang: a directive in the leading comment block declares it.
    do {
      sub(/\r$/, "", line)
      if (line ~ /^#.*shellcheck.*shell=/) {
        d = line
        sub(/^.*shell=/, "", d)
        sub(/[^A-Za-z].*$/, "", d)
        close(path)
        return dialect_name(d)
      }
      if (line !~ /^#/ && line !~ /^[ \t]*$/) break
    } while ((r = (getline line < path)) > 0)
    close(path)
    if (r < 0) return "!"
    return "none"
  }
  BEGIN {
    while ((lr = (getline rel < listfile)) > 0) {
      d = classify(root "/" rel)
      if (d == "sh" || d == "bash" || d == "!") print d "\t" rel
      else if (d == "none" && rel ~ /\.sh$/) print "none\t" rel
    }
    if (lr < 0) print "!\t" listfile
  }
' >"$work/classified" || fail_closed "could not read the dialects"

: >"$work/list"
: >"$work/undeclared"
count=0
while IFS="$tab" read -r dialect rel; do
  case "$dialect" in
    '!') fail_closed "cannot read $(sanitize_printable "$rel" "(unprintable filename)") — the scan would cover less than it claims" ;;
    none) printf '%s\n' "$rel" >>"$work/undeclared" ;;
    *)
      printf '%s\t%s\n' "$dialect" "$rel" >>"$work/list"
      count=$((count + 1))
      ;;
  esac
done <"$work/classified"

[ "$count" -gt 0 ] \
  || fail_closed "no shell files found under $safe_root — a broken enumeration, not a clean tree"

status=0
while IFS= read -r rel; do
  # shellcheck disable=SC2016 # the backticks are message text
  printf 'check-bash32: %s: a .sh file declaring no dialect (add a shebang, or a `# shellcheck shell=` line for a sourced library)\n' \
    "$(sanitize_printable "$rel" "(unprintable filename)")" >&2
  status=1
done <"$work/undeclared"

case "$mode" in
  list)
    # The same bytes sanitize_printable drops, keeping the tab and newline
    # that delimit the records.
    tr -d '\000-\010\013-\037\177\200-\237' <"$work/list" \
      || fail_closed "could not print the file list"
    exit "$status"
    ;;
  parse)
    # shellcheck disable=SC2016 # the parser under test expands it, not this shell
    version=$("$bash_bin" -c 'printf "%s" "$BASH_VERSION"' 2>/dev/null) \
      || fail_closed "cannot run the parser: $(sanitize_printable "$bash_bin" "(unprintable path)")"
    version=$(sanitize_printable "$version" "(unprintable)")
    case "$version" in
      "$expect_version"*) ;;
      *) fail_closed "parser is bash $version, not $(sanitize_printable "$expect_version" "(unprintable)") — a clean report would measure nothing" ;;
    esac
    while IFS="$tab" read -r dialect rel; do
      if [ "$dialect" = sh ]; then
        "$bash_bin" --posix -n "$root/$rel" >"$work/err" 2>&1 && continue
      else
        "$bash_bin" -n "$root/$rel" >"$work/err" 2>&1 && continue
      fi
      printf 'check-bash32: %s does not parse as %s under bash %s:\n' \
        "$(sanitize_printable "$rel" "(unprintable filename)")" "$dialect" "$version" >&2
      while IFS= read -r line; do
        printf '  %s\n' "$(sanitize_printable "$line" "(unprintable)")" >&2
      done <"$work/err"
      status=1
    done <"$work/list"
    [ "$status" -eq 0 ] && printf 'check-bash32: parse clean (%s files, bash %s)\n' "$count" "$version"
    exit "$status"
    ;;
esac

# lint. Each line is lexed once: quotes, escapes, comments, `$( )` nesting,
# and heredoc operators, so text inside quotes or comments never reads as
# code. A substitution left open at the end of a line is tracked across lines
# by its paren balance.
awk -v listfile="$work/list" -v root="$root" '
  BEGIN {
    CASE_MSG = "a case pattern without its leading ( inside a $( ) command substitution (move the case out of it: shfmt strips the ()"
    HEREDOC_MSG = "a heredoc inside a $( ) command substitution with an unbalanced quote, backtick, or parenthesis in its body"
    UNCLOSED_MSG = "a heredoc whose delimiter never appears, so nothing after it was checked"
    CASE_IN = "(^|[ \t;&|(])case[ \t]"
    ESAC = "(^|[ \t;&|])esac([ \t;)]|$)"
  }
  function report(rel, n, what) { print rel "\t" n "\t" what }

  # lex(line, insq): lexes line, starting inside a single-quoted string when
  # insq is set. Sets lx_code (comment removed, single-quoted text blanked),
  # lx_bare (double-quoted text blanked too), lx_sq (a single-quoted string
  # left open), lx_open (the line ends inside a `$(` opened on it, 2 when
  # that `$(` sits in double quotes), and lx_hd[1..lx_nhd] with lx_hdash[],
  # lx_hsub[], lx_hdq[]: each heredoc delimiter, whether it is `<<-`, whether
  # it opened inside a `$( )` on this line, and whether that one is quoted.
  function lex(s, insq,   i, c, n, st, sp, stk, ar, w, j, k, q, prev) {
    lx_code = ""; lx_bare = ""; lx_sq = 0; lx_open = 0; lx_nhd = 0
    n = length(s); st = insq ? 1 : 0; sp = 0; ar = 0; prev = " "
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (st == 1) {
        if (c == "'"'"'") { st = 0; lx_code = lx_code c; lx_bare = lx_bare c }
        continue
      }
      if (st == 2) {
        if (c == "\\") { lx_code = lx_code substr(s, i, 2); i++; continue }
        if (c == "\"") { st = 0; lx_code = lx_code c; lx_bare = lx_bare c; prev = c; continue }
        if (c == "$" && substr(s, i + 1, 1) == "(" && substr(s, i + 2, 1) != "(") {
          stk[++sp] = "S2"; st = 0; lx_code = lx_code "$("; lx_bare = lx_bare "$("; i++; prev = "("; continue
        }
        lx_code = lx_code c
        continue
      }
      if (c == "\\") { lx_code = lx_code substr(s, i, 2); lx_bare = lx_bare substr(s, i, 2); i++; prev = "x"; continue }
      if (c == "#" && prev ~ /[ \t;&|(]/) break
      if (c == "'"'"'") { st = 1; lx_code = lx_code c; lx_bare = lx_bare c; prev = c; continue }
      if (c == "\"") { st = 2; lx_code = lx_code c; lx_bare = lx_bare c; prev = c; continue }
      if (substr(s, i, 2) == "((") ar++
      else if (substr(s, i, 2) == "))" && ar > 0) ar--
      if (c == "$" && substr(s, i + 1, 1) == "(" && substr(s, i + 2, 1) != "(") {
        stk[++sp] = "S0"; lx_code = lx_code "$("; lx_bare = lx_bare "$("; i++; prev = "("; continue
      }
      if (c == "(") stk[++sp] = "P"
      if (c == ")" && sp > 0) {
        if (stk[sp] == "S2") { sp--; st = 2; lx_code = lx_code c; lx_bare = lx_bare c; prev = c; continue }
        sp--
      }
      if (c == "<" && substr(s, i, 2) == "<<" && substr(s, i + 2, 1) != "<" && prev != "<" && ar == 0) {
        j = i + 2; q = 0
        if (substr(s, j, 1) == "-") { q = 1; j++ }
        while (substr(s, j, 1) ~ /[ \t]/) j++
        w = ""
        while (j <= n && substr(s, j, 1) !~ /[ \t;&|<>()]/) { w = w substr(s, j, 1); j++ }
        gsub(/["'"'"'\\]/, "", w)
        if (w != "") {
          lx_nhd++
          lx_hd[lx_nhd] = w; lx_hdash[lx_nhd] = q
          lx_hsub[lx_nhd] = 0; lx_hdq[lx_nhd] = 0
          for (k = sp; k > 0; k--) if (stk[k] != "P") { lx_hsub[lx_nhd] = 1; lx_hdq[lx_nhd] = (stk[k] == "S2"); break }
          lx_code = lx_code substr(s, i, j - i); lx_bare = lx_bare substr(s, i, j - i)
          i = j - 1; prev = "x"
          continue
        }
      }
      lx_code = lx_code c; lx_bare = lx_bare c; prev = c
    }
    lx_sq = (st == 1)
    if (sp > 0 && stk[sp] != "P" && lx_code ~ /\$\([ \t]*\\?[ \t]*$/) lx_open = (stk[sp] == "S2") ? 2 : 1
  }

  # Whether bash 3.2 finds a heredoc body unbalanced inside a `$( )`: it
  # lexes the body as shell, so an unclosed quote, backtick, or `(` runs off
  # the end of the file. In a bare `$( )` it also honors `#` comments and
  # rejects a stray `)`; in a double-quoted one it does neither.
  function unbalanced(s, bare,   i, c, st, bt, p, n) {
    st = 0; bt = 0; p = 0; n = length(s)
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (st == 1) { if (c == "'"'"'") st = 0; continue }
      if (c == "\\") { i++; continue }
      if (st == 2) { if (c == "\"") st = 0; else if (c == "`") bt = !bt; continue }
      if (bare && c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t\n]/)) {
        while (i <= n && substr(s, i, 1) != "\n") i++
        continue
      }
      if (c == "'"'"'") st = 1
      else if (c == "\"") st = 2
      else if (c == "`") bt = !bt
      else if (c == "(") p++
      else if (c == ")") { if (p > 0) p--; else if (bare) return 1 }
    }
    return st || bt || p
  }

  function count(s, ch,   t) { t = s; return gsub(ch, "", t) }

  function scan(rel,   path, line, n, r, depth, bal, dqs, cd, ep, pc, insq, nq, hq, hdash, hsub, hdq, hline, body, cur, t, b, net, flagged, i) {
    path = root "/" rel
    n = 0; depth = 0; insq = 0; nq = 0; cur = 0
    while ((r = (getline line < path)) > 0) {
      n++
      sub(/\r$/, "", line)
      if (cur > 0) {
        t = line
        if (hdash[cur]) sub(/^\t+/, "", t)
        if (t == hq[cur]) {
          if (hsub[cur] && unbalanced(body, !hdq[cur])) report(rel, hline, HEREDOC_MSG)
          cur = (cur < nq) ? cur + 1 : 0
          body = ""
          if (cur == 0) nq = 0
        } else body = body line "\n"
        continue
      }
      # A line that opens inside a multi-line single-quoted string (an
      # embedded awk or jq program) is that program text, not shell.
      if (insq) {
        lex(line, 1)
        insq = lx_sq
        continue
      }
      if (line ~ /^[ \t]*(#.*)?$/) continue
      # Outside every substitution, only a quote, a heredoc, or a `$(` can
      # change what follows; lexing is the cost, so skip the rest.
      if (depth == 0 && index(line, "'"'"'") == 0 && index(line, "<<") == 0 && index(line, "$(") == 0) continue
      lex(line, 0)
      flagged = 0

      if (depth > 0) {
        b = lx_bare
        if (b ~ CASE_IN && b ~ /[ \t]in([ \t]|$)/) {
          cd[depth]++
          t = b; sub(/^.*[ \t]in[ \t]*/, "", t)
          if (t ~ /^[^( \t]/) { report(rel, n, CASE_MSG); flagged = 1 }
          ep[depth] = (t == "")
          if (b ~ ESAC) cd[depth]--
        } else if (b ~ CASE_IN) pc[depth] = 1
        else if (pc[depth] && b ~ /^[ \t]*in([ \t]|$)/) { pc[depth] = 0; cd[depth]++; ep[depth] = 1 }
        else if (cd[depth] > 0 && b ~ ESAC) { cd[depth]--; ep[depth] = 0 }
        else if (cd[depth] > 0 && ep[depth]) {
          if (b ~ /^[ \t]*[^ \t()#;][^()]*\)/) { report(rel, n, CASE_MSG); flagged = 1 }
          ep[depth] = 0
        }
        if (cd[depth] > 0 && b ~ /;;&?[ \t]*$|;&[ \t]*$/) ep[depth] = 1

        t = b
        if (lx_open) sub(/\$\([ \t]*\\?[ \t]*$/, "", t)
        net = count(t, "\\(") - count(t, "\\)") + flagged
        bal[depth] += net
        while (depth > 0 && bal[depth] < 0) {
          net = bal[depth] + 1
          depth--
          if (depth > 0) bal[depth] += net
        }
      }
      if (!flagged && lx_bare ~ /(^|[^\\])\$\([ \t]*case[ \t].*[ \t]in[ \t]+[^( \t]/) report(rel, n, CASE_MSG)

      for (i = 1; i <= lx_nhd; i++) {
        nq++
        hq[nq] = lx_hd[i]; hdash[nq] = lx_hdash[i]
        hsub[nq] = lx_hsub[i] || depth > 0
        hdq[nq] = lx_hsub[i] ? lx_hdq[i] : (depth > 0 && dqs[depth])
      }
      if (nq > 0) { cur = 1; body = ""; hline = n }

      if (lx_open) {
        depth++
        bal[depth] = 0; cd[depth] = 0; ep[depth] = 0; pc[depth] = 0
        dqs[depth] = (lx_open == 2)
      }
      if (lx_sq) insq = 1
    }
    close(path)
    if (r < 0) print "!\t" rel
    else if (cur > 0) report(rel, hline, UNCLOSED_MSG)
  }
  BEGIN {
    while ((lr = (getline entry < listfile)) > 0) {
      split(entry, f, "\t")
      scan(f[2])
    }
    if (lr < 0) print "!\t" listfile
  }
' >"$work/findings" || fail_closed "the lint could not complete"

while IFS="$tab" read -r rel lineno what; do
  [ -n "$rel" ] || continue
  if [ "$rel" = "!" ]; then
    fail_closed "could not read $(sanitize_printable "$lineno" "(unprintable filename)") during the lint — it would cover less than it claims"
  fi
  printf 'check-bash32: %s:%s: %s (bash 3.2 misparses it)\n' \
    "$(sanitize_printable "$rel" "(unprintable filename)")" "$lineno" "$what" >&2
  status=1
done <"$work/findings"

[ "$status" -eq 0 ] && printf 'check-bash32: lint clean (%s files)\n' "$count"
exit "$status"
