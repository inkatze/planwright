#!/bin/sh
# check-bash32.sh — the bash 3.2 regression guards.
#
# macOS ships bash 3.2 as both /bin/bash and /bin/sh, and its parser misreads
# constructs every later bash accepts, so a script can pass every Linux run and
# still fail to parse on a Mac. Two guards hold that line, sharing one file set:
#
#   parse  runs each covered file through `bash -n`, or `bash --posix -n` for
#          an sh-dialect file, with the bash on PATH (or --bash). CI runs it
#          inside the bash:3.2 image (.github/workflows/ci.yml). A later bash
#          passes everything this guard exists to catch, so a parser whose
#          version does not start with --expect-version (default 3.2) is
#          refused rather than reported clean.
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
#              remedy is to move the `case` out of the substitution. Inside a
#              double-quoted `$( )` even `bash -n` under 3.2 accepts the file
#              and the misparse appears only when it runs, so for that form
#              the lint is the only guard.
#          A heredoc whose delimiter never appears, and a quote that never
#          closes, are findings too: the lint cannot read past either.
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
# every bash:3.2 image reference in a workflow file names Docker's official
# image by an @sha256: digest, and that there is at least one.
#
# Exit codes: 0 clean, 1 a finding, 2 usage or an enumeration that would cover
# less than it claims (no files, an unreadable listed file, a path git had to
# quote, a path outside the root, a symlink, the wrong parser version, a
# parser that fails other than by rejecting a file).
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
       (move such a case out of the substitution: shfmt strips the `(`); also
       a heredoc whose delimiter never appears and a quote that never closes.
list   print `<dialect><TAB><path>` for each covered file.
pin    require Docker's official image by an @sha256: digest on every
       bash:3.2 reference in a workflow file, and at least one reference.

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

# pin <workflow>: every bash:3.2 image reference names the official image by
# digest, at least one. Comments are prose, so a digest in one pins nothing;
# each reference on a line is checked on its own.
if [ "$mode" = pin ]; then
  [ "$#" -eq 1 ] || fail_closed "pin takes exactly one workflow file"
  safe_wf="$(sanitize_printable "$1" "(unprintable path)")"
  [ -r "$1" ] || fail_closed "cannot read workflow file: $safe_wf"
  sed -e 's/^[[:space:]]*#.*//' -e 's/[[:space:]]#.*//' "$1" >"$work/pin.txt" \
    || fail_closed "could not read workflow file: $safe_wf"
  rc=0
  grep -o -E '[^[:space:]"'\'']*bash:3\.2[^[:space:]"'\'']*' "$work/pin.txt" >"$work/pin.occ" || rc=$?
  [ "$rc" -le 1 ] || fail_closed "could not scan workflow file: $safe_wf"
  sed -e 's/^.*=//' "$work/pin.occ" >"$work/pin.words" \
    || fail_closed "could not scan workflow file: $safe_wf"
  rc=0
  grep -E '(^|/)bash:3\.2([^0-9]|$)' "$work/pin.words" >"$work/pin.refs" || rc=$?
  [ "$rc" -le 1 ] || fail_closed "could not scan workflow file: $safe_wf"
  if [ ! -s "$work/pin.refs" ]; then
    printf 'check-bash32: no bash:3.2 image reference in %s\n' "$safe_wf" >&2
    exit 1
  fi
  rc=0
  grep -v -E '^(docker\.io/library/)?bash:3\.2@sha256:[0-9a-f]{64}$' "$work/pin.refs" >"$work/pin.bad" || rc=$?
  [ "$rc" -le 1 ] || fail_closed "could not scan workflow file: $safe_wf"
  if [ "$rc" -eq 0 ]; then
    while IFS= read -r ref; do
      printf 'check-bash32: bash:3.2 reference not pinned to the official image by an @sha256: digest: %s\n' \
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
    cat >"$work/given" || fail_closed "could not read the file list from stdin"
  else
    [ -r "$files_from" ] \
      || fail_closed "cannot read the file list: $(sanitize_printable "$files_from" "(unprintable path)")"
    cat "$files_from" >"$work/given" || fail_closed "could not read the file list"
  fi
else
  git -C "$root" -c core.quotepath=off ls-files >"$work/given" 2>"$work/err" \
    || fail_closed "git ls-files failed under $safe_root: $(sanitize_printable "$(cat "$work/err")" "(unprintable)")"
fi
# An unmerged path is listed once per stage.
awk '!seen[$0]++' "$work/given" >"$work/all" || fail_closed "could not read the file list"

# Path checks are builtins only, so this loop forks nothing per file; the
# dialect of every candidate is read in one awk pass below.
tab="$(printf '\t')"
checked_dir=''
: >"$work/candidates"
while IFS= read -r rel || [ -n "$rel" ]; do
  [ -n "$rel" ] || continue
  case "$rel" in
    '"'*) fail_closed "git quoted a tracked path, refusing to guess its name: $(sanitize_printable "$rel" "(unprintable filename)")" ;;
    *"$tab"*) fail_closed "path contains a tab, refusing to scan: $(sanitize_printable "$rel" "(unprintable filename)")" ;;
    /* | .. | ../* | */.. | */../*) fail_closed "path leaves the root, refusing to read it: $(sanitize_printable "$rel" "(unprintable filename)")" ;;
    "$EXCLUDE_DIR"*) continue ;;
  esac
  # A symlink anywhere in the path has no honest reading: following it may
  # leave the root, and skipping it covers less than the scan claims. Paths
  # arrive sorted, so each directory is walked once.
  case "$rel" in
    */*) dir=${rel%/*} ;;
    *) dir='' ;;
  esac
  if [ -n "$dir" ] && [ "$dir" != "$checked_dir" ]; then
    walk=$root
    rest=$dir
    while [ -n "$rest" ]; do
      walk=$walk/${rest%%/*}
      [ ! -L "$walk" ] \
        || fail_closed "symlinked directory in the scan, refusing to follow or skip it: $(sanitize_printable "$rel" "(unprintable filename)")"
      case "$rest" in
        */*) rest=${rest#*/} ;;
        *) rest='' ;;
      esac
    done
    checked_dir=$dir
  fi
  file="$root/$rel"
  [ ! -L "$file" ] \
    || fail_closed "symlink in the scan, refusing to follow or skip it: $(sanitize_printable "$rel" "(unprintable filename)")"
  [ -f "$file" ] && [ -r "$file" ] \
    || fail_closed "cannot read $(sanitize_printable "$rel" "(unprintable filename)") — the scan would cover less than it claims"
  printf '%s\n' "$rel" >>"$work/candidates"
done <"$work/all"

# Both awk passes take the root and list through the environment: `-v`
# would expand backslash escapes in them and read a different path than the
# one checked above.
PW_ROOT=$root
export PW_ROOT

# One record per candidate: `sh|bash<TAB>path`, `none<TAB>path` for a .sh file
# declaring no dialect, `!<TAB>path` for a file that could not be read.
# Files are opened by getline rather than through ARGV, so a name containing
# `=` or a leading `-` is read as a path.
PW_LIST="$work/candidates" awk '
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
        # Skip env options, the operand of those that take one, and
        # NAME=value assignments.
        for (i++; i <= n; i++) {
          if (w[i] ~ /^-[uCP]$/ || w[i] ~ /^--(unset|chdir)$/) i++
          else if (w[i] !~ /^-/ && w[i] !~ /=/) break
        }
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
    root = ENVIRON["PW_ROOT"]; listfile = ENVIRON["PW_LIST"]
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
      rc=0
      if [ "$dialect" = sh ]; then
        "$bash_bin" --posix -n "$root/$rel" >"$work/err" 2>&1 || rc=$?
      else
        "$bash_bin" -n "$root/$rel" >"$work/err" 2>&1 || rc=$?
      fi
      [ "$rc" -eq 0 ] && continue
      # bash -n rejects a file with exit 2; anything else is the parser
      # failing, which says nothing about the file.
      [ "$rc" -eq 2 ] \
        || fail_closed "the parser exited $rc on $(sanitize_printable "$rel" "(unprintable filename)") — not a verdict on the file"
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

# lint. Each file is lexed line by line with its state carried across lines:
# the quote it is inside, and a stack of open groups, each a paren group, an
# arithmetic (( )), or a $( ) opened outside or inside double quotes. So text
# inside quotes or comments never reads as code, and a substitution is
# followed from wherever it opens to the `)` that closes it.
PW_LIST="$work/list" awk '
  BEGIN {
    CASE_MSG = "a case pattern without its leading ( inside a $( ) command substitution (move the case out of it: shfmt strips the ()"
    HEREDOC_MSG = "a heredoc inside a $( ) command substitution with an unbalanced quote, backtick, or parenthesis in its body"
    UNCLOSED_MSG = "a heredoc whose delimiter never appears, so nothing after it was checked"
    QUOTE_MSG = "a quote that never closes, so nothing after it was checked"
    # `case WORD in` at a command position, and `esac` as a word.
    CASE_IN = "(^|[;&|(]|[ \t](then|do|else|!))[ \t]*case[ \t]+[^ \t;]+[ \t]+in([ \t]+|$)"
    CASE_NO_IN = "(^|[;&|(]|[ \t](then|do|else|!))[ \t]*case[ \t]+[^ \t;]+[ \t]*$"
    ESAC = "(^|[ \t;&|])esac([ \t;)]|$)"
    BARE_PATTERN = "^[ \t]*[^ \t()#;][^()]*\\)"
  }
  function report(rel, n, what) { print rel "\t" n "\t" what }

  # The open groups, G[1..gn], carried across a file: "P" a paren group, "A"
  # an arithmetic (( )), "S0" a $( ) opened outside double quotes, "S2" one
  # opened inside them. For each S at index k: NC[k] open case statements in
  # it, WP[k] a case pattern may start next, WI[k] a case awaits its `in`.
  function push(t) { G[++gn] = t; if (t ~ /^S/) { NC[gn] = 0; WP[gn] = 0; WI[gn] = 0 } }
  function top_sub(   k) { for (k = gn; k > 0; k--) if (G[k] ~ /^S/) return k; return 0 }
  function in_arith(   k) {
    for (k = gn; k > 0; k--) { if (G[k] == "A") return 1; if (G[k] ~ /^S/) return 0 }
    return 0
  }

  # lex(s): lexes one line from the carried quote state qs (0 none, 1 single,
  # 2 double, 3 ANSI-C $'"'"'...'"'"') and the carried stack. Sets lx_bare (the
  # line with comments removed, escapes neutralized, and quoted text blanked
  # down to its quote marks), lx_pop (the first group a `)` on the line
  # closed, "" for none), lx_orphan (how many `)` found nothing open), and
  # lx_hd[1..lx_nhd] with lx_hdash[], lx_hsub[],
  # lx_hdq[]: each heredoc delimiter, whether it is `<<-`, whether it opens
  # inside a $( ), and whether that $( ) sits in double quotes.
  function lex(s,   i, c, n, w, j, dash, k, prev) {
    lx_bare = ""; lx_pop = ""; lx_nhd = 0; lx_orphan = 0
    n = length(s); prev = " "
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (qs == 1) { if (c == "'"'"'") { qs = 0; lx_bare = lx_bare c; prev = c }; continue }
      if (qs == 3) {
        if (c == "\\") i++
        else if (c == "'"'"'") { qs = 0; lx_bare = lx_bare c; prev = c }
        continue
      }
      if (qs == 2) {
        if (c == "\\") { i++; continue }
        if (c == "\"") { qs = 0; lx_bare = lx_bare c; prev = c; continue }
        if (c == "$" && substr(s, i + 1, 1) == "(" && substr(s, i + 2, 1) != "(") {
          push("S2"); qs = 0; lx_bare = lx_bare "$("; i++; prev = "("
        }
        continue
      }
      if (c == "\\") { lx_bare = lx_bare "\\x"; i++; prev = "x"; continue }
      if (c == "#" && prev ~ /[ \t;&|(]/) break
      if (c == "'"'"'") { qs = 1; lx_bare = lx_bare c; prev = c; continue }
      if (c == "$" && substr(s, i + 1, 1) == "'"'"'") { qs = 3; lx_bare = lx_bare "$'"'"'"; i++; prev = c; continue }
      if (c == "\"") { qs = 2; lx_bare = lx_bare c; prev = c; continue }
      if (c == "$" && substr(s, i + 1, 2) == "((") { push("A"); lx_bare = lx_bare "$(("; i += 2; prev = "("; continue }
      if (c == "(" && substr(s, i + 1, 1) == "(") { push("A"); lx_bare = lx_bare "(("; i++; prev = "("; continue }
      if (c == "$" && substr(s, i + 1, 1) == "(") { push("S0"); lx_bare = lx_bare "$("; i++; prev = "("; continue }
      if (c == ")" && gn > 0 && G[gn] == "A" && substr(s, i + 1, 1) == ")") {
        gn--; lx_bare = lx_bare "))"; i++; prev = ")"; continue
      }
      if (c == "(") push("P")
      else if (c == ")" && gn == 0) lx_orphan++
      else if (c == ")") {
        if (lx_pop == "") lx_pop = G[gn]
        if (G[gn--] == "S2") { qs = 2; lx_bare = lx_bare c; prev = c; continue }
      }
      if (c == "<" && substr(s, i, 2) == "<<" && substr(s, i + 2, 1) != "<" && prev != "<" && !in_arith()) {
        j = i + 2; dash = 0
        if (substr(s, j, 1) == "-") { dash = 1; j++ }
        while (substr(s, j, 1) ~ /[ \t]/) j++
        w = ""
        while (j <= n && substr(s, j, 1) !~ /[ \t;&|<>()]/) { w = w substr(s, j, 1); j++ }
        gsub(/["'"'"'\\]/, "", w)
        if (w != "") {
          lx_nhd++
          lx_hd[lx_nhd] = w; lx_hdash[lx_nhd] = dash
          k = top_sub()
          lx_hsub[lx_nhd] = (k > 0); lx_hdq[lx_nhd] = (k > 0 && G[k] == "S2")
          lx_bare = lx_bare substr(s, i, j - i)
          i = j - 1; prev = "x"
          continue
        }
      }
      lx_bare = lx_bare c; prev = c
    }
  }

  # Whether bash 3.2 finds a heredoc body unbalanced inside a $( ): it lexes
  # the body as shell, so an unclosed quote, backtick, or ( runs off the end
  # of the file. In a bare $( ) it also honors # comments and rejects a stray
  # ); in a double-quoted one it does neither.
  function unbalanced(s, bare,   i, c, st, bt, p, n) {
    st = 0; bt = 0; p = 0; n = length(s)
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (st == 1) { if (c == "'"'"'") st = 0; continue }
      if (st == 3) { if (c == "\\") i++; else if (c == "'"'"'") st = 0; continue }
      if (c == "\\") { i++; continue }
      if (st == 2) { if (c == "\"") st = 0; else if (c == "`") bt = !bt; continue }
      if (bare && c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t\n]/)) {
        while (i <= n && substr(s, i, 1) != "\n") i++
        continue
      }
      if (c == "$" && substr(s, i + 1, 1) == "'"'"'") { st = 3; i++ }
      else if (c == "'"'"'") st = 1
      else if (c == "\"") st = 2
      else if (c == "`") bt = !bt
      else if (c == "(") p++
      else if (c == ")") { if (p > 0) p--; else if (bare) return 1 }
    }
    return st || bt || p
  }

  # Case-statement state for the substitution at k, from line text t.
  # Returns 1 when t holds a bare pattern there.
  function case_step(k, t,   r, bad) {
    bad = 0
    if (match(t, CASE_IN)) {
      NC[k]++; WI[k] = 0
      r = substr(t, RSTART + RLENGTH)
      if (r != "" && r !~ /^\(/ && r !~ /^#/) bad = 1
      WP[k] = (r == "")
      if (r ~ ESAC) NC[k]--
    } else if (t ~ CASE_NO_IN) WI[k] = 1
    else if (WI[k] && t ~ /^[ \t]*in([ \t]|$)/) {
      WI[k] = 0; NC[k]++
      r = t; sub(/^[ \t]*in[ \t]*/, "", r)
      if (r != "" && r !~ /^\(/) bad = 1
      WP[k] = (r == "")
    } else if (NC[k] > 0) {
      if (WP[k] && t ~ BARE_PATTERN && t !~ /^[ \t]*esac([ \t;)]|$)/) bad = 1
      if (t !~ /^[ \t]*$/) WP[k] = 0
      if (t ~ ESAC) NC[k]--
    }
    if (NC[k] > 0 && t ~ /;;&?[ \t]*$|;&[ \t]*$/) WP[k] = 1
    return bad
  }

  # A line that, outside every group and quote, can change nothing: no quote
  # mark, heredoc, escape, or unmatched paren. Lexing is the cost, so these
  # are skipped.
  function inert(line,   t) {
    if (index(line, "'"'"'") || index(line, "<<") || index(line, "\\")) return 0
    t = line
    if (gsub(/"/, "", t) % 2) return 0
    t = line
    return gsub(/\(/, "", t) == gsub(/\)/, "", line)
  }

  function scan(rel,   path, line, n, r, nq, cur, hq, hdash, hin, gdq, gline, body, t, k, k0, flagged, i, qline) {
    path = ENVIRON["PW_ROOT"] "/" rel
    n = 0; gn = 0; qs = 0; nq = 0; cur = 0; body = ""; qline = 0
    while ((r = (getline line < path)) > 0) {
      n++
      sub(/\r$/, "", line)
      # Heredoc bodies: every body opened on one line is one stream to bash,
      # so their quotes are judged together once the last one closes.
      if (cur > 0) {
        t = line
        if (hdash[cur]) sub(/^\t+/, "", t)
        if (t == hq[cur]) {
          if (cur < nq) cur++
          else {
            if (hin && unbalanced(body, !gdq)) report(rel, gline, HEREDOC_MSG)
            cur = 0; nq = 0; body = ""
          }
        } else body = body line "\n"
        continue
      }
      if (qs == 1 && !index(line, "'"'"'")) continue
      if (qs == 3 && !index(line, "'"'"'")) continue
      if (qs == 2 && !index(line, "\"") && !index(line, "$(")) continue
      if (qs == 0) {
        if (line ~ /^[ \t]*(#.*)?$/) continue
        if (gn == 0 && inert(line)) continue
      }

      k0 = top_sub()
      if (qs == 0) qline = n
      lex(line)
      flagged = 0

      # Case tracking runs in the substitution the line belongs to: the one
      # open when it began, or one the line itself opens (its text after the
      # last $( ).
      k = top_sub(); t = lx_bare
      if (k > k0) { i = t; while (match(i, /\$\(/)) i = substr(i, RSTART + 2); t = i }
      else k = k0
      if (k > 0 && case_step(k, t)) { report(rel, n, CASE_MSG); flagged = 1 }
      if (!flagged && lx_bare ~ /(^|[^\\])\$\([ \t]*case[ \t]+[^ \t;]+[ \t]+in[ \t]+[^( \t]/) {
        report(rel, n, CASE_MSG); flagged = 1
      }
      # The pattern ) closed the substitution in this reading, as it does
      # for bash 3.2; reopen it so the rest of the file reads as written,
      # unless a later ) on the line found nothing open to close.
      if (flagged && lx_pop ~ /^S/ && !lx_orphan) { push(lx_pop); if (qs == 2) qs = 0 }

      if (lx_nhd > 0) {
        hin = 0; gdq = 0
        for (i = 1; i <= lx_nhd; i++) {
          nq++; hq[nq] = lx_hd[i]; hdash[nq] = lx_hdash[i]
          if (lx_hsub[i] && !hin) { hin = 1; gdq = lx_hdq[i] }
        }
        cur = 1; body = ""; gline = n
      }
    }
    close(path)
    if (r < 0) print "!\t" rel
    else if (cur > 0) report(rel, gline, UNCLOSED_MSG)
    else if (qs != 0) report(rel, qline, QUOTE_MSG)
  }
  BEGIN {
    listfile = ENVIRON["PW_LIST"]
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
