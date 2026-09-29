#!/bin/sh
# check-spec-literals.sh — flag the literal spec home used as a path.
#
# The spec root has one resolver (scripts/resolve-root.sh). A script that
# composes `specs/` itself keeps the old root silently once the root moves,
# and that pattern re-grows one convenient line at a time, so this guard
# fails on every new occurrence instead of trusting review to spot it.
#
# SCANNED: every file under scripts/ (at any depth) with a .sh suffix or a
# `#!` first line, every file under githooks/, the task `run` and
# `run_windows` values in mise.toml (not their descriptions), lefthook.yml,
# .gitignore, and the workflows under .github/workflows/. Skipped: full-line
# comments, and a trailing comment (the first `#` after whitespace outside
# quotes) everywhere but .gitignore, where a ` #` is part of the pattern. In
# scripts and hooks a heredoc body is text, not code, so nothing in it is
# skipped; messages are scanned too. This is a line scanner, not a shell
# parser: the heredoc and quote tracking cover the forms these files use.
#
# FLAGGED: `specs/` not preceded by a name character (so `--specs/` is an
# option name, not a path); `/specs` ending a path segment (`$root/specs`,
# `*/specs)`), which composes the same root without the trailing slash; and a
# bare `specs` as the operand of cd, pushd, find, ls, -C, or a unary test
# (`-d`, `-e`, `-f` and the rest). Each test also runs on the line with its
# quotes removed, so `"$root"/"specs"` composes the same path it would
# unquoted. A bare `specs` anywhere else is prose.
#
# CLEARED: a flagged line is matched by its file and its whitespace-trimmed
# text (tabs read as spaces), never by line number (which rots) and never by
# file (which exempts the next literal too). One row clears one occurrence:
# a second identical line needs a second row. The rows live in two lists:
#   config/spec-literal-allowlist.tsv — the permanent exemptions, in exactly
#     three classes: `resolver` (the resolver itself, only
#     scripts/resolve-root.sh), `namespace` (a `specs/<id>` that names a spec
#     rather than a directory, such as the Consumed-by writer and an alias
#     mapper), and `static-glob` (a pattern a tool reads statically and cannot
#     resolve, only in lefthook.yml and .gitignore);
#   config/spec-literal-pending.tsv — sites not yet migrated onto the
#     resolver, each tagged with the task that migrates it. Shrink-only: a row
#     absent from the base ref's copy of the list fails, so a migration can
#     delete rows and nothing can add them. The copy read is the one at the
#     merge base of the base ref and HEAD, so a branch cut before a migration
#     is not failed for rows the migration deleted. Where the base ref or its
#     copy of the list does not exist, that comparison is skipped and says so.
# A row that clears nothing is stale and fails, so a migrated site cannot
# leave its exemption behind.
#
# Usage: check-spec-literals.sh [--repo-root <dir>] [--base <ref>]
#   --base  the ref whose pending list bounds this one (default origin/main);
#           given explicitly, a ref that does not resolve is an error rather
#           than a skipped comparison
# Exit: 0 clean · 1 an unlisted literal, a stale row, or an added pending row ·
#   2 usage, or an input that would make the scan vacuous (a missing,
#   unreadable, or symlinked scope file or list, a malformed list row, zero
#   files scanned, a pass that did not complete).
#
# Untrusted input: every scanned file is PR-controllable. Files are read by
# awk as data, never sourced or executed; a symlink is refused rather than
# followed out of the tree; the root reaches awk through the environment, not
# `-v`, so its bytes are never escape-processed; and every reported path and
# line is stripped of control bytes before it reaches the terminal.
#
# POSIX sh on the macOS + Linux support bar.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=check-spec-literals
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
repo_root=$(cd "$script_dir/.." && pwd) || exit 2
base=origin/main
base_given=0

# The house display sanitizer's byte range (scripts/echo-safety.sh), keeping
# TAB and LF so a report stays one record per line.
strip() { tr -d '\000-\010\013-\037\177\200-\237'; }
say() { printf '%s: %s\n' "$me" "$(printf '%s' "$1" | strip)" >&2; }
die() {
  say "$1"
  exit 2
}

while [ "$#" -gt 0 ]; do
  case $1 in
    --repo-root | --base)
      [ "$#" -ge 2 ] || die "$1 needs a value"
      case $1 in
        --repo-root) repo_root=$2 ;;
        --base) base=$2 base_given=1 ;;
      esac
      shift 2
      ;;
    -h | --help)
      echo "usage: check-spec-literals.sh [--repo-root <dir>] [--base <ref>]"
      exit 0
      ;;
    *) die "unknown argument (see --help)" ;;
  esac
done

repo_root=$(cd "$repo_root" 2>/dev/null && pwd) || die "repo root is not a readable directory"
case $base in
  '' | -*) die "--base must name a ref" ;;
esac

for f in scripts githooks .github/workflows; do
  [ ! -L "$repo_root/$f" ] || die "$f/ is a symlink; refusing to follow it out of the tree"
  [ -d "$repo_root/$f" ] || die "$f/ is missing; the scan would cover less than it claims"
done
for f in mise.toml lefthook.yml .gitignore config/spec-literal-allowlist.tsv config/spec-literal-pending.tsv; do
  [ ! -L "$repo_root/$f" ] || die "$f is a symlink; refusing to follow it out of the tree"
  [ -r "$repo_root/$f" ] || die "$f is missing or unreadable; the scan would cover less than it claims"
done

work=$(mktemp -d "${TMPDIR:-/tmp}/check-spec-literals.XXXXXX") || die "could not create a temporary directory"
trap 'rm -rf "$work"' EXIT

# The file lists, repo-relative, one per line. A name with a newline or tab
# would split a record below, so it is refused rather than skipped.
: >"$work/plain"
: >"$work/mise"
tab='	'
newline='
'
list_file() {
  case $1 in
    *"$newline"* | *"$tab"*) die "refusing a scanned filename containing a newline or tab" ;;
  esac
  [ ! -L "$repo_root/$1" ] || die "$1 is a symlink; refusing to follow it out of the tree"
  [ -r "$repo_root/$1" ] || die "cannot read $1; the scan would cover less than it claims"
  printf '%s\n' "$1" >>"$work/$2"
}
# Every file at any depth, symlinks included so they can be refused. The walk
# never follows a link.
# A newline in a name would split it across two list lines, so such a name is
# refused before the list is read; a tab is refused by list_file.
bad_names=$(cd "$repo_root" && find scripts githooks .github/workflows -name "*$newline*" -print) \
  || die "could not enumerate the scope directories"
[ -z "$bad_names" ] || die "refusing a scanned filename containing a newline or tab"
(cd "$repo_root" && find scripts githooks .github/workflows \( -type f -o -type l \) -print) >"$work/found.raw" \
  || die "could not enumerate the scope directories"
sort "$work/found.raw" >"$work/found" || die "could not enumerate the scope directories"
while IFS= read -r rel; do
  f=$repo_root/$rel
  case $rel in
    scripts/*.sh | githooks/* | .github/workflows/*.yml | .github/workflows/*.yaml) ;;
    scripts/*)
      # An unreadable file cannot show its shebang, so it is refused here
      # rather than quietly classed as not a script.
      [ ! -L "$f" ] || die "$rel is a symlink; refusing to follow it out of the tree"
      [ -r "$f" ] || die "cannot read $rel; the scan would cover less than it claims"
      first=''
      IFS= read -r first <"$f" || true
      case $first in '#!'*) ;; *) continue ;; esac
      ;;
    *) continue ;;
  esac
  list_file "$rel" plain
done <"$work/found"
[ -s "$work/plain" ] || die "no files found under scripts/, githooks/, or .github/workflows/; a broken enumeration, not a clean tree"
list_file lefthook.yml plain
list_file .gitignore plain
list_file mise.toml mise

# One pass over every file, printing `<path> TAB <lineno> TAB <text>` for each
# flagged line, then `END` so a pass cut short is told from a clean one.
# mise.toml is read in its own mode: only a task's `run` or `run_windows`
# value counts, single-line, triple-quoted, or an array, under a
# `[tasks.<name>]` table, as a dotted, inline-table, or shorthand
# (`name = "cmd"`) key under `[tasks]`, or as a root-level `tasks.` key.
# shellcheck disable=SC2016 # an awk program, expanded by awk
scan='
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); gsub(/\t/, " ", s); return s }
  # The bracketed [s] keeps this line from matching itself.
  function literal(s) {
    return s ~ /(^|[^A-Za-z0-9_.-])spec[s]\// || s ~ /\/spec[s]([^A-Za-z0-9_.\/-]|$)/ \
      || s ~ /(^|[^A-Za-z0-9_-])(cd|pushd|find|ls|-C|-[a-hkprsuwxGLNOS])[ \t]+["\047]?spec[s]([ \t"\047;)|&]|$)/
  }
  function flagged(s,   u) {
    if (literal(s)) return 1
    u = s; gsub(/["\047]/, "", u)
    return literal(u)
  }
  # The code before a trailing comment: the first `#` after whitespace outside
  # quotes. A backslash outside single quotes escapes the next byte.
  function code(s,   i, c, dq, sq) {
    dq = 0; sq = 0
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (c == "\\" && !sq) { i++; continue }
      if (c == "\"" && !sq) dq = !dq
      else if (c == "\047" && !dq) sq = !sq
      else if (c == "#" && !dq && !sq && i > 1 && substr(s, i - 1, 1) == " ") return substr(s, 1, i - 1)
    }
    return s
  }
  # The heredoc terminator a line opens, or "" when it opens none; sets the
  # global `dash` when it opened with `<<-`, which strips leading tabs from
  # the terminator line.
  function heredoc(s,   pre, d) {
    if (!match(s, /<<-?[ \t]*\\?[\047"]?[A-Za-z0-9_.+-]+/)) return ""
    pre = substr(s, 1, RSTART - 1)
    if (gsub(/"/, "\"", pre) % 2 || gsub(/\047/, "\047", pre) % 2) return ""
    d = substr(s, RSTART, RLENGTH)
    dash = (d ~ /^<<-/)
    sub(/^<<-?[ \t]*\\?[\047"]?/, "", d)
    return d
  }
  # check <path> <n> <text> <whole> <comments> — flag <text> and report the
  # trimmed <whole> line it came from; <comments> says whether comments are
  # skipped here.
  function check(path, n, text, whole, comments,   t) {
    t = trim(text)
    if (t == "") return
    if (comments && t ~ /^#/) return
    if (!flagged(t)) return
    if (comments && strip_trailing && !flagged(code(t))) return
    print path "\t" n "\t" trim(whole)
  }
  function scan_plain(rel, path,   line, n, r, term, dash_term, body) {
    n = 0; term = ""
    strip_trailing = (rel != ".gitignore")
    shell = (rel ~ /^(scripts|githooks)\//)
    while ((r = (getline line < path)) > 0) {
      n++
      if (term != "") {
        body = line
        if (dash_term) sub(/^\t+/, "", body)
        if (body == term) { term = ""; continue }
        check(rel, n, line, line, 0)
        continue
      }
      check(rel, n, line, line, 1)
      if (shell && trim(line) !~ /^#/) {
        term = heredoc(code(trim(line))); dash_term = dash
      }
    }
    close(path)
    if (r < 0) { print "!\t" rel; bad = 1 }
  }
  function scan_mise(rel, path,   line, n, r, t, where, where_now, key, hdr, close_delim, skip_body, rest, q) {
    n = 0; where = ""; close_delim = ""; strip_trailing = 1
    while ((r = (getline line < path)) > 0) {
      n++
      if (close_delim == "]") {
        check(rel, n, line, line, 1)
        if (trim(line) ~ /^\]/ || code(trim(line)) ~ /\][ \t]*$/) close_delim = ""
        continue
      }
      if (close_delim != "") {
        if (index(line, close_delim)) { if (!skip_body) check(rel, n, substr(line, 1, index(line, close_delim) - 1), line, 1); close_delim = ""; continue }
        if (!skip_body) check(rel, n, line, line, 1)
        continue
      }
      t = trim(line)
      if (t ~ /^#/) continue
      if (t ~ /^\[/) {
        hdr = t; gsub(/["\047]/, "", hdr)
        where = (hdr ~ /^\[[ \t]*tasks[ \t]*[.]/) ? "task" : (hdr ~ /^\[[ \t]*tasks[ \t]*\]/) ? "tasks" : "other"
        continue
      }
      # The key with its quotes and the spaces around dots removed, so
      # `"run"` and `lint . run` read as the keys they are. Before any table,
      # a dotted `tasks.` key is a task too.
      key = t; sub(/=.*/, "", key); gsub(/["\047]/, "", key); gsub(/[ \t]*[.][ \t]*/, ".", key); sub(/[ \t]+$/, "", key)
      if (where == "" && key ~ /^tasks[.]/) { where_now = "tasks"; key = substr(key, 7) } else where_now = where
      if (where_now != "task" && where_now != "tasks") continue
      skip_body = 0
      # Under [tasks], an undotted key is a task in shorthand: its value is
      # the run command.
      if (index(t, "=") && (key ~ /(^|[.])run(_windows)?$/ && (where_now == "tasks" || key ~ /^run(_windows)?$/) \
        || where_now == "tasks" && key !~ /[.]/ && t !~ /=[ \t]*\{/)) {
        rest = t; sub(/^[^=]*=[ \t]*/, "", rest)
        q = substr(rest, 1, 3)
        if (q == "\047\047\047" || q == "\"\"\"") {
          rest = substr(rest, 4)
          if (index(rest, q)) check(rel, n, substr(rest, 1, index(rest, q) - 1), line, 1)
          else { check(rel, n, rest, line, 1); close_delim = q }
        } else {
          check(rel, n, rest, line, 1)
          if (substr(rest, 1, 1) == "[" && code(rest) !~ /\][ \t]*$/) close_delim = "]"
        }
      } else if (where_now == "tasks" && t ~ /[{,][ \t]*["\047]?run(_windows)?["\047]?[ \t]*=/) {
        check(rel, n, t, line, 1)
      } else if (index(t, "=")) {
        # Another key whose value opens a multi-line string: its body is not a
        # run value.
        rest = t; sub(/^[^=]*=[ \t]*/, "", rest); q = substr(rest, 1, 3)
        if ((q == "\047\047\047" || q == "\"\"\"") && !index(substr(rest, 4), q)) { close_delim = q; skip_body = 1 }
      }
    }
    close(path)
    if (r < 0) { print "!\t" rel; bad = 1 }
  }
  BEGIN {
    root = ENVIRON["SL_ROOT"]
    while ((r = (getline p < ENVIRON["SL_PLAIN"])) > 0) scan_plain(p, root "/" p)
    if (r < 0) bad = 1
    while ((r = (getline p < ENVIRON["SL_MISE"])) > 0) scan_mise(p, root "/" p)
    if (r < 0) bad = 1
    if (!bad) print "END"
  }
'
SL_ROOT=$repo_root SL_PLAIN=$work/plain SL_MISE=$work/mise awk "$scan" >"$work/hits" \
  || die "the scan could not complete"
if grep -q '^!' "$work/hits" || [ "$(tail -n 1 "$work/hits")" != END ]; then
  die "a scanned file could not be read; the scan would cover less than it claims"
fi

# The pending list's rows at the base ref, when both exist: the bound the
# current list may not exceed.
: >"$work/base-pending"
base_note=''
has_base=0
if git -C "$repo_root" rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1; then
  if merge_base=$(git -C "$repo_root" merge-base "$base" HEAD 2>/dev/null); then
    where_read="the merge base of $base and HEAD"
  else
    merge_base=$base
    where_read="$base (no merge base with HEAD)"
  fi
  # `./` keeps the path relative to the repo root even when that root sits
  # below another repository's toplevel.
  if git -C "$repo_root" cat-file -e "$merge_base:./config/spec-literal-pending.tsv" 2>/dev/null; then
    git -C "$repo_root" show "$merge_base:./config/spec-literal-pending.tsv" >"$work/base-pending" \
      || die "could not read the pending list at $where_read"
    has_base=1
  else
    base_note="; shrink check skipped: $where_read has no pending list"
  fi
else
  [ "$base_given" -eq 0 ] || die "--base $base does not resolve"
  base_note="; shrink check skipped: $base does not resolve"
fi

# Match hits against the lists; print the verdict records:
#   BAD <file:row> <why>             a malformed list row
#   UNLISTED <path> <lineno> <text>  a literal no row clears
#   STALE <list> <row> <path> <text> a row that clears nothing
#   ADDED <row> <path> <text>        a pending row the base ref lacks
#   COUNT <allowlisted> <pending>
# shellcheck disable=SC2016 # an awk program, expanded by awk
verdict='
  function text(from,   s, i) { s = $from; for (i = from + 1; i <= NF; i++) s = s " " $i; sub(/[ \t\r]+$/, "", s); return s }
  function bad(why) { print "BAD\t" name ":" FNR "\t" why }
  BEGIN { FS = "\t"; allow = ENVIRON["SL_ALLOW"]; pend = ENVIRON["SL_PEND"]; basep = ENVIRON["SL_BASE"]; hits = ENVIRON["SL_HITS"] }
  FILENAME == basep {
    if (/^#/ || /^[ \t]*$/ || NF < 3) next
    based[$2 "\t" text(3)]++; next
  }
  FILENAME == allow || FILENAME == pend {
    name = (FILENAME == allow) ? "config/spec-literal-allowlist.tsv" : "config/spec-literal-pending.tsv"
    if (/^#/ || /^[ \t]*$/) next
    if (NF < 3 || $2 == "" || text(3) == "") { bad("expected <tag> TAB <path> TAB <line>"); next }
    if (FILENAME == allow) {
      if ($1 !~ /^(resolver|namespace|static-glob)$/) { bad("class must be resolver, namespace, or static-glob"); next }
      if ($1 == "resolver" && $2 != "scripts/resolve-root.sh") { bad("the resolver class names only scripts/resolve-root.sh"); next }
      if ($1 == "static-glob" && $2 != "lefthook.yml" && $2 != ".gitignore") { bad("the static-glob class names only lefthook.yml and .gitignore"); next }
      list = "allowlist"
    } else {
      if ($1 !~ /^[0-9]+(\.[0-9]+)?$/) { bad("a pending row starts with the task id that migrates it"); next }
      list = "pending"
      key = $2 "\t" text(3)
      if (++pcount[key] > based[key] && has_base) print "ADDED\t" FNR "\t" key
    }
    key = $2 "\t" text(3)
    rows[key]++; rowlist[key, rows[key]] = list; rowno[key, rows[key]] = FNR
    next
  }
  FILENAME == hits {
    if ($0 == "END") next
    key = $1 "\t" text(3)
    if (++seen[key] <= rows[key]) {
      if (rowlist[key, seen[key]] == "pending") np++; else na++
      next
    }
    print "UNLISTED\t" $1 "\t" $2 "\t" text(3)
  }
  END {
    for (k in rows) for (i = seen[k] + 1; i <= rows[k]; i++) print "STALE\t" rowlist[k, i] "\t" rowno[k, i] "\t" k
    print "COUNT\t" na + 0 "\t" np + 0
  }
'
# has_base is set only when the base list was read, so a skipped comparison
# never reports every row as added.
SL_ALLOW=$repo_root/config/spec-literal-allowlist.tsv SL_PEND=$repo_root/config/spec-literal-pending.tsv \
  SL_BASE=$work/base-pending SL_HITS=$work/hits \
  awk -v has_base="$has_base" "$verdict" "$work/base-pending" \
  "$repo_root/config/spec-literal-allowlist.tsv" "$repo_root/config/spec-literal-pending.tsv" \
  "$work/hits" >"$work/verdict" || die "the match could not complete"
grep -q '^COUNT' "$work/verdict" || die "the match could not complete"

if grep -q '^BAD' "$work/verdict"; then
  say "malformed list row(s):"
  grep '^BAD' "$work/verdict" | awk -F '\t' '{ print "  " $2 ": " $3 }' | strip >&2
  exit 2
fi
status=0
if grep -q '^UNLISTED' "$work/verdict"; then
  status=1
  say "the spec home used as a literal path; resolve it with scripts/resolve-root.sh instead:"
  grep '^UNLISTED' "$work/verdict" | awk -F '\t' '{ print "  " $2 ":" $3 ": " $4 }' | strip >&2
fi
if grep -q '^STALE' "$work/verdict"; then
  status=1
  say "list rows that clear no flagged line (the site moved or was migrated; delete the row):"
  grep '^STALE' "$work/verdict" | sort | awk -F '\t' '{ print "  " $2 " row " $3 ": " $4 ": " $5 }' | strip >&2
fi
if grep -q '^ADDED' "$work/verdict"; then
  status=1
  say "pending rows absent from the list at $where_read (the list only shrinks; resolve the path instead):"
  grep '^ADDED' "$work/verdict" | awk -F '\t' '{ print "  row " $2 ": " $3 ": " $4 }' | strip >&2
fi
if [ "$status" -eq 0 ]; then
  IFS="$tab" read -r _ n_allow n_pending <<EOF
$(grep '^COUNT' "$work/verdict")
EOF
  printf '%s: clean (%s allowlisted, %s pending migration%s)\n' "$me" "$n_allow" "$n_pending" "$base_note" | strip
fi
exit "$status"
