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
#          parser being the only ground truth; a Linux host's bash passes
#          everything this guard exists to catch, so --expect-version refuses
#          a run under the wrong parser instead of reporting it clean.
#   lint   flags, by pattern, the constructs bash 3.2 is known to misparse,
#          so a Linux-only local run catches their return before a push:
#            - a heredoc inside a `$( )` command substitution whose body
#              holds an unbalanced quote, backtick, or `(`: 3.2 lexes the
#              body as shell and runs off the end of the file (it honors a
#              `#` comment there unless the substitution is double-quoted);
#            - a `case` pattern without its leading `(` inside a `$( )` (3.2
#              reads the pattern's `)` as the substitution's end; the leading
#              `(` form would parse, but shfmt rewrites it back to the bare one).
#          A substitution is tracked from a `$(` that ends its line until a
#          line opening with `)`, plus the forms written on the `$(` line
#          itself; the bash 3.2 parse in CI covers whatever the patterns miss.
#
# Dialect: the shebang's interpreter (sh or dash, bash; directly or through
# env), else a `# shellcheck shell=` directive in the file's leading comment
# block, which is how the shebang-less sourced libraries declare themselves.
# A file naming any other interpreter is out of scope; a .sh file declaring
# neither is an error, so a new library cannot slip past unparsed.
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
# quote, the wrong parser version).
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
       bash on PATH or --bash; --expect-version refuses any other version.
lint   flag, inside a `$( )` command substitution, a heredoc whose body holds
       an unbalanced quote, backtick, or `(`, and a case pattern without its
       leading `(`: constructs bash 3.2 misparses.
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

# pin <workflow>: every bash:3.2 image reference digest-pinned, at least one.
pin_check() {
  [ -r "$1" ] || fail_closed "cannot read workflow file: $(sanitize_printable "$1" "(unprintable path)")"
  # Full-line comments are prose, not references.
  _refs=$(grep -n -E '(^|[^A-Za-z0-9_.-])bash:3\.2([^0-9]|$)' "$1" | grep -v -E '^[0-9]+:[[:space:]]*#') || _refs=''
  [ -n "$_refs" ] || {
    printf 'check-bash32: no bash:3.2 image reference in %s\n' "$(sanitize_printable "$1" "(unprintable path)")" >&2
    exit 1
  }
  _bad=$(printf '%s\n' "$_refs" | grep -v -E 'bash:3\.2[0-9.]*@sha256:[0-9a-f]{64}([^0-9a-f]|$)') || _bad=''
  if [ -n "$_bad" ]; then
    printf 'check-bash32: bash:3.2 image reference without an @sha256: digest: %s\n' "$(sanitize_printable "$_bad" "(unprintable line)")" >&2
    exit 1
  fi
  printf 'check-bash32: pin clean\n'
  exit 0
}

case "${1:-}" in
  --help | -h)
    [ "$#" -eq 1 ] || fail_closed "--help takes no other arguments"
    usage
    exit 0
    ;;
  parse | lint | list) mode=$1 ;;
  pin)
    [ "$#" -eq 2 ] || fail_closed "pin takes exactly one workflow file"
    pin_check "$2"
    ;;
  '') fail_closed "missing mode: parse, lint, list, or pin (see --help)" ;;
  *) fail_closed "unknown mode: $(sanitize_printable "$1" "(unprintable)") (see --help)" ;;
esac
shift

root=$repo_root
files_from=''
bash_bin=bash
expect_version=''
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
  [ "$bash_bin" = bash ] && [ -z "$expect_version" ] \
    || fail_closed "--bash and --expect-version apply to parse only"
fi

safe_root="$(sanitize_printable "$root" "(unprintable path)")"
[ -d "$root" ] || fail_closed "root not found or not a directory: $safe_root"

work="$(mktemp -d "${TMPDIR:-/tmp}/check-bash32.XXXXXX")" \
  || fail_closed "could not create a temporary directory"
trap 'rm -rf "$work"' EXIT

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

# dialect_of <path>: prints sh, bash, other, or none.
dialect_of() {
  _first=''
  IFS= read -r _first <"$1" || [ -n "$_first" ] || {
    printf 'none'
    return
  }
  case "$_first" in
    '#!'*)
      set -f
      # shellcheck disable=SC2086 # split the shebang line into words
      set -- ${_first#'#!'}
      set +f
      _interp=${1:-}
      if [ "${_interp##*/}" = env ]; then
        shift
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -* | *=*) shift ;;
            *) break ;;
          esac
        done
        _interp=${1:-}
      fi
      case "${_interp##*/}" in
        sh | dash) printf 'sh' ;;
        bash) printf 'bash' ;;
        *) printf 'other' ;;
      esac
      return
      ;;
  esac
  # No shebang: a directive in the leading comment block declares the dialect.
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in
      '#'*shellcheck*shell=*)
        _d=${_line#*shell=}
        _d=${_d%%[!A-Za-z]*}
        case "$_d" in
          sh | dash) printf 'sh' ;;
          bash) printf 'bash' ;;
          *) printf 'other' ;;
        esac
        return
        ;;
      '#'* | '') ;;
      *) break ;;
    esac
    _line=''
  done <"$1"
  printf 'none'
}

newline='
'
tab="$(printf '\t')"
: >"$work/list"
: >"$work/undeclared"
count=0
while IFS= read -r rel || [ -n "$rel" ]; do
  [ -n "$rel" ] || continue
  case "$rel" in
    '"'*) fail_closed "git quoted a tracked path, refusing to guess its name: $(sanitize_printable "$rel" "(unprintable filename)")" ;;
    *"$tab"* | *"$newline"*) fail_closed "path contains a tab, refusing to scan: $(sanitize_printable "$rel" "(unprintable filename)")" ;;
    "$EXCLUDE_DIR"*) continue ;;
  esac
  file="$root/$rel"
  # A tracked symlink is covered through its tracked target.
  [ -L "$file" ] && continue
  [ -f "$file" ] && [ -r "$file" ] \
    || fail_closed "cannot read $(sanitize_printable "$rel" "(unprintable filename)") — the scan would cover less than it claims"
  dialect=$(dialect_of "$file")
  case "$dialect" in
    sh | bash)
      printf '%s\t%s\n' "$dialect" "$rel" >>"$work/list"
      count=$((count + 1))
      ;;
    none)
      case "$rel" in
        *.sh) printf '%s\n' "$rel" >>"$work/undeclared" ;;
      esac
      ;;
  esac
done <"$work/all"

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
    cat "$work/list"
    exit "$status"
    ;;
  parse)
    # shellcheck disable=SC2016 # the parser under test expands it, not this shell
    version=$("$bash_bin" -c 'printf "%s" "$BASH_VERSION"' 2>/dev/null) \
      || fail_closed "cannot run the parser: $(sanitize_printable "$bash_bin" "(unprintable path)")"
    case "$version" in
      "$expect_version"*) ;;
      *) fail_closed "parser is bash $(sanitize_printable "$version" "(unprintable)"), not $(sanitize_printable "$expect_version" "(unprintable)") — a clean report would measure nothing" ;;
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

# lint. Files are opened by getline rather than through ARGV, so a name
# containing `=` or a leading `-` is read as a path.
awk -v listfile="$work/list" -v root="$root" '
  function report(rel, n, what) { print rel "\t" n "\t" what }
  # A line leaving an odd number of single quotes outside double-quoted
  # strings opens or closes a multi-line single-quoted string: an embedded
  # awk or jq program, whose text is not shell.
  function sq_odd(line,   s) {
    s = line
    gsub(/"[^"]*"/, "", s)
    return gsub(/'"'"'/, "", s) % 2
  }
  # The heredoc delimiter a line of code opens, or "". `<<<` is a here-string
  # and `<<` after `((` an arithmetic shift; `<<` inside an open quote is
  # text.
  function heredoc_of(line,   pre, d) {
    if (!match(line, /<<-?[ \t]*\\?["'"'"']?[A-Za-z0-9_.+-]+/)) return ""
    pre = substr(line, 1, RSTART - 1)
    if (pre ~ /<$/ || substr(line, RSTART + 2, 1) == "<" || pre ~ /\(\(/) return ""
    if (gsub(/"/, "\"", pre) % 2 || gsub(/'"'"'/, "&", pre) % 2) return ""
    d = substr(line, RSTART, RLENGTH)
    hd_dash = (d ~ /^<<-/)
    sub(/^<<-?[ \t]*/, "", d); sub(/^\\/, "", d); sub(/^["'"'"']/, "", d)
    return d
  }
  # Whether bash 3.2 would find a heredoc body unbalanced: inside a `$( )`
  # it lexes the body as shell, so an unclosed quote, backtick, or `(` runs
  # it off the end of the file. A stray `)` it tolerates. It skips a `#`
  # comment in the body unless the substitution sits inside double quotes.
  function unbalanced(s, comments,   i, c, st, bt, p) {
    st = 0; bt = 0; p = 0
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (st == 1) { if (c == "'"'"'") st = 0; continue }
      if (c == "\\") { i++; continue }
      if (st == 2) { if (c == "\"") st = 0; else if (c == "`") bt = !bt; continue }
      if (comments && c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t\n]/)) {
        while (i <= length(s) && substr(s, i, 1) != "\n") i++
        continue
      }
      if (c == "'"'"'") st = 1
      else if (c == "\"") st = 2
      else if (c == "`") bt = !bt
      else if (c == "(") p++
      else if (c == ")" && p > 0) p--
    }
    return st || bt || p
  }
  # Whether the last `$(` in s sits inside double quotes.
  function dq_before(s,   pre) {
    pre = s
    sub(/\$\([^$]*$/, "", pre)
    return gsub(/"/, "\"", pre) % 2
  }
  function scan(rel,   path, line, code, tail, n, r, depth, dqs, incase, heredoc, dash, insub, indq, body, hd_line, insq, d) {
    path = root "/" rel
    n = 0; depth = 0; incase = 0; heredoc = ""; insq = 0
    while ((r = (getline line < path)) > 0) {
      n++
      sub(/\r$/, "", line)
      if (heredoc != "") {
        tail = line
        if (dash) sub(/^\t+/, "", tail)
        if (tail == heredoc) {
          heredoc = ""
          if (insub && unbalanced(body, !indq))
            report(rel, hd_line, "a heredoc inside a $( ) command substitution with an unbalanced quote, backtick, or ( in its body")
        } else if (insub) body = body line "\n"
        continue
      }
      if (insq) {
        if (sq_odd(line)) insq = 0
        continue
      }
      if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) continue
      if (sq_odd(line)) insq = 1
      # Single-quoted text on the line is literal, never code.
      code = line
      gsub(/'"'"'[^'"'"']*'"'"'/, "'"'"''"'"'", code)

      if (depth > 0) {
        if (code ~ /^[ \t]*\)/) { depth--; incase = 0; continue }
        if (code ~ /(^|[ \t;&|(])case[ \t].*[ \t]in([ \t]|$)/) {
          incase = (code !~ /(^|[ \t;&|])esac([ \t;)]|$)/)
          if (code ~ /(^|[ \t;&|(])case[ \t].*[ \t]in[ \t]+[^( \t#]/)
            report(rel, n, "a case pattern without its leading ( inside a $( ) command substitution")
        } else if (code ~ /(^|[ \t;&|])esac([ \t;)]|$)/) incase = 0
        else if (incase && code ~ /^[ \t]*[^ \t()#;][^()]*\)/)
          report(rel, n, "a case pattern without its leading ( inside a $( ) command substitution")
      }
      # The same-line form: `$(case x in a) ...`.
      if (code ~ /\$\([ \t]*case[ \t].*[ \t]in[ \t]+[^( \t#]/)
        report(rel, n, "a case pattern without its leading ( inside a $( ) command substitution")

      d = heredoc_of(line)
      if (d != "") {
        heredoc = d; dash = hd_dash; body = ""; hd_line = n
        if (match(code, /\$\([^)]*<</)) {
          insub = 1; indq = dq_before(substr(code, 1, RSTART + 1))
        } else {
          insub = (depth > 0); indq = (depth > 0 && dqs[depth])
        }
      }

      tail = code
      sub(/[ \t]+$/, "", tail)
      if (tail ~ /\$\([ \t]*\\?[ \t]*(#.*)?$/) dqs[++depth] = dq_before(tail)
    }
    close(path)
    if (r < 0) print "!\t" rel
  }
  BEGIN {
    FS = "\t"
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
