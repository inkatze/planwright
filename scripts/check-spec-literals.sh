#!/bin/sh
# check-spec-literals.sh — flag the literal spec home used as a path.
#
# The spec root has one resolver (scripts/resolve-root.sh). A script that
# composes `specs/` itself keeps the old root silently once the root moves,
# and that pattern re-grows one convenient line at a time, so this guard
# fails on every new occurrence instead of trusting review to spot it.
#
# SCANNED: the shell files under scripts/ (by shebang or .sh suffix), every
# file under githooks/, the `run` bodies of the tasks in mise.toml (not their
# descriptions), lefthook.yml, .gitignore, and the workflows under
# .github/workflows/. Full-line comments are skipped everywhere, including
# inside a mise run body; anything else, heredoc bodies and messages included,
# is scanned.
#
# FLAGGED: `specs/` not preceded by a name character (so `--specs/` is an
# option name, not a path) and `/specs` ending a path segment (`$root/specs`,
# `*/specs)`), which composes the same root without the trailing slash.
#
# CLEARED: a flagged line is matched by its file and its whitespace-trimmed
# text, never by line number (which rots) and never by file (which exempts
# the next literal too), against two lists:
#   config/spec-literal-allowlist.tsv — the permanent exemptions, in exactly
#     three classes: `resolver` (the resolver itself, only
#     scripts/resolve-root.sh), `namespace` (a `specs/<id>` that names a spec
#     rather than a directory: the Consumed-by writer, the alias mappers), and
#     `static-glob` (a pattern a tool reads statically and cannot resolve);
#   config/spec-literal-pending.tsv — sites not yet migrated onto the
#     resolver, each tagged with the task that migrates it. This list only
#     shrinks: the migration tasks delete their rows, and none are added.
# An entry in either list that matches no flagged line is stale and fails the
# check, so a migrated site cannot leave its exemption behind.
#
# Usage: check-spec-literals.sh [--repo-root <dir>]
# Exit: 0 clean · 1 an unlisted literal or a stale entry · 2 usage, or an
#   input that would make the scan vacuous (a missing scope file or list, a
#   malformed list row, zero files scanned).
#
# Untrusted input: every scanned file is PR-controllable. Files are read by
# awk as data, never sourced or executed, and every reported line is stripped
# of control bytes before it reaches the terminal.
#
# POSIX sh on the macOS + Linux support bar.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=check-spec-literals
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
repo_root=$(cd "$script_dir/.." && pwd) || exit 2

while [ "$#" -gt 0 ]; do
  case $1 in
    --repo-root)
      [ "$#" -ge 2 ] || {
        echo "$me: --repo-root needs a directory" >&2
        exit 2
      }
      repo_root=$2
      shift 2
      ;;
    -h | --help)
      echo "usage: check-spec-literals.sh [--repo-root <dir>]"
      exit 0
      ;;
    *)
      echo "$me: unknown argument (see --help)" >&2
      exit 2
      ;;
  esac
done

repo_root=$(cd "$repo_root" 2>/dev/null && pwd) || {
  echo "$me: repo root is not a readable directory" >&2
  exit 2
}
allowlist=$repo_root/config/spec-literal-allowlist.tsv
pending=$repo_root/config/spec-literal-pending.tsv

for f in scripts githooks .github/workflows; do
  [ -d "$repo_root/$f" ] || {
    echo "$me: $f/ is missing; the scan would cover less than it claims" >&2
    exit 2
  }
done
for f in mise.toml lefthook.yml .gitignore config/spec-literal-allowlist.tsv config/spec-literal-pending.tsv; do
  [ -r "$repo_root/$f" ] || {
    echo "$me: $f is missing or unreadable; the scan would cover less than it claims" >&2
    exit 2
  }
done

work=$(mktemp -d "${TMPDIR:-/tmp}/check-spec-literals.XXXXXX") || {
  echo "$me: could not create a temporary directory" >&2
  exit 2
}
trap 'rm -rf "$work"' EXIT

# The file list, repo-relative, one per line. A name with a newline or tab
# would split a record below, so it is refused rather than skipped.
: >"$work/plain"
: >"$work/mise"
tab=$(printf '\t')
newline='
'
list_file() {
  case $1 in
    *"$newline"* | *"$tab"*)
      echo "$me: refusing a scanned filename containing a newline or tab" >&2
      exit 2
      ;;
  esac
  [ -r "$repo_root/$1" ] || {
    echo "$me: cannot read $1; the scan would cover less than it claims" >&2
    exit 2
  }
  printf '%s\n' "$1" >>"$work/$2"
}
set +f
for f in "$repo_root"/scripts/* "$repo_root"/githooks/* "$repo_root"/.github/workflows/*; do
  [ -f "$f" ] || continue
  rel=${f#"$repo_root"/}
  case $rel in
    scripts/*.sh | githooks/* | .github/workflows/*.yml | .github/workflows/*.yaml) ;;
    scripts/*)
      first=''
      IFS= read -r first <"$f" 2>/dev/null || true
      case $first in '#!'*) ;; *) continue ;; esac
      ;;
    *) continue ;;
  esac
  list_file "$rel" plain
done
set -f
list_file lefthook.yml plain
list_file .gitignore plain
list_file mise.toml mise

[ "$(wc -l <"$work/plain")" -gt 2 ] || {
  echo "$me: no files found under scripts/, githooks/, or .github/workflows/; a broken enumeration, not a clean tree" >&2
  exit 2
}

# One pass over every file, printing `<path> TAB <lineno> TAB <trimmed line>`
# for each flagged line. mise.toml is read in its own mode: only the `run`
# value of a task counts, single-line, triple-quoted, or an array.
# shellcheck disable=SC2016 # an awk program, expanded by awk
scan='
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
  function flagged(s) {
    # The bracketed [s] keeps this line from matching itself.
    return s ~ /(^|[^A-Za-z0-9_.-])spec[s]\// || s ~ /\/spec[s]([^A-Za-z0-9_.\/-]|$)/
  }
  # The code before a trailing comment: the first `#` after whitespace with
  # an even count of each quote before it, so a `#` inside a string stays.
  function code(s,   i, c, dq, sq) {
    dq = 0; sq = 0
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (c == "\"" && sq % 2 == 0) dq++
      else if (c == "\047" && dq % 2 == 0) sq++
      else if (c == "#" && i > 1 && substr(s, i - 1, 1) ~ /[ \t]/ && dq % 2 == 0 && sq % 2 == 0) return substr(s, 1, i - 1)
    }
    return s
  }
  # check <path> <n> <text> [<whole>] — flag <text>, reporting the trimmed
  # <whole> line when the text is only part of it (a mise run value).
  function check(path, n, line, whole,   t) {
    t = trim(line)
    if (t == "" || t ~ /^#/) return
    if (flagged(strip_trailing ? code(t) : t)) print path "\t" n "\t" (whole != "" ? trim(whole) : t)
  }
  function scan_plain(path,   line, n, r) {
    n = 0
    # gitignore has no trailing comments: a ` #` there is part of the pattern.
    strip_trailing = (path !~ /\/[.]gitignore$/)
    while ((r = (getline line < path)) > 0) { n++; check(path, n, line) }
    close(path)
    if (r < 0) print "!\t" path
  }
  function scan_mise(path,   line, n, r, t, in_tasks, body, delim, rest) {
    n = 0; in_tasks = 0; body = ""; strip_trailing = 1
    while ((r = (getline line < path)) > 0) {
      n++
      if (body != "") {
        if (body == "]") { check(path, n, line); if (line ~ /\]/) body = ""; continue }
        if (index(line, body)) { check(path, n, substr(line, 1, index(line, body) - 1)); body = ""; continue }
        check(path, n, line)
        continue
      }
      t = trim(line)
      if (t ~ /^\[/) { in_tasks = (t ~ /^\[tasks[.]/); continue }
      if (!in_tasks || t !~ /^run[ \t]*=/) continue
      rest = t; sub(/^run[ \t]*=[ \t]*/, "", rest)
      delim = substr(rest, 1, 3)
      if (delim == "\047\047\047" || delim == "\"\"\"") {
        rest = substr(rest, 4)
        if (index(rest, delim)) { check(path, n, substr(rest, 1, index(rest, delim) - 1), line); continue }
        check(path, n, rest, line); body = delim
      } else if (substr(rest, 1, 1) == "[") {
        check(path, n, rest, line)
        if (rest !~ /\]/) body = "]"
      } else {
        check(path, n, rest, line)
      }
    }
    close(path)
    if (r < 0) print "!\t" path
  }
  BEGIN {
    while ((getline p < plain) > 0) scan_plain(root "/" p)
    while ((getline p < mise) > 0) scan_mise(root "/" p)
  }
'
awk -v root="$repo_root" -v plain="$work/plain" -v mise="$work/mise" "$scan" >"$work/raw" || {
  echo "$me: the scan could not complete" >&2
  exit 2
}
if grep -q '^!' "$work/raw"; then
  echo "$me: a scanned file could not be read; the scan would cover less than it claims" >&2
  exit 2
fi
# Repo-relative paths, the prefix stripped literally: a root containing a
# regex byte must not turn into a pattern.
awk -F '\t' -v OFS='\t' -v pre="$repo_root/" '{ if (index($1, pre) == 1) $1 = substr($1, length(pre) + 1); print }' "$work/raw" >"$work/hits"

# Both lists, normalized to `<list> TAB <path> TAB <line> TAB <row>`. A
# malformed row is a usage error: a list that cannot be read is not a list
# that exempts nothing.
awk -F '\t' -v OFS='\t' '
  FNR == 1 { which = (FILENAME ~ /pending/) ? "pending" : "allowlist" }
  /^#/ || /^[ \t]*$/ { next }
  which == "allowlist" {
    if (NF < 3 || $1 !~ /^(resolver|namespace|static-glob)$/) { print "!\t" FILENAME ":" FNR; next }
    if ($1 == "resolver" && $2 != "scripts/resolve-root.sh") { print "!\t" FILENAME ":" FNR; next }
    line = $3; for (i = 4; i <= NF; i++) line = line "\t" $i
    if (($2 "\t" line) in seen) { print "!\t" FILENAME ":" FNR " (listed more than once)"; next }
    seen[$2 "\t" line] = 1
    print "allowlist", $2, line, FNR; next
  }
  {
    if (NF < 3 || $1 !~ /^[0-9]+(\.[0-9]+)?$/) { print "!\t" FILENAME ":" FNR; next }
    line = $3; for (i = 4; i <= NF; i++) line = line "\t" $i
    if (($2 "\t" line) in seen) { print "!\t" FILENAME ":" FNR " (listed more than once)"; next }
    seen[$2 "\t" line] = 1
    print "pending", $2, line, FNR
  }
' "$allowlist" "$pending" >"$work/entries"
if grep -q '^!' "$work/entries"; then
  echo "$me: malformed list row(s) (expected <class> TAB <path> TAB <line>, class resolver|namespace|static-glob, resolver only for scripts/resolve-root.sh; pending rows <task> TAB <path> TAB <line>):" >&2
  grep '^!' "$work/entries" | cut -f2 | sed "s#^$repo_root/##; s/^/  /" >&2
  exit 2
fi

# Match hits against the lists; print the verdict records:
#   UNLISTED <path> <lineno> <line>   a literal no list clears
#   STALE <list> <row> <path> <line>  an entry matching no flagged line
#   COUNT <allowlisted> <pending>
awk -F '\t' '
  FILENAME == ARGV[1] { key = $2 "\t" $3; list[key] = $1; row[key] = $4; next }
  {
    key = $1 "\t" $3
    if (key in list) { used[key] = 1; if (list[key] == "pending") np++; else na++; next }
    print "UNLISTED\t" $1 "\t" $2 "\t" $3
  }
  END {
    for (k in list) if (!(k in used)) { split(k, kp, "\t"); print "STALE\t" list[k] "\t" row[k] "\t" k }
    print "COUNT\t" na + 0 "\t" np + 0
  }
' "$work/entries" "$work/hits" >"$work/verdict"

strip() { tr -d '\000-\010\013-\037\177\200-\237'; }
status=0
if grep -q '^UNLISTED' "$work/verdict"; then
  status=1
  echo "$me: the spec home used as a literal path; resolve it with scripts/resolve-root.sh instead:" >&2
  grep '^UNLISTED' "$work/verdict" | awk -F '\t' '{ print "  " $2 ":" $3 ": " $4 }' | strip >&2
fi
if grep -q '^STALE' "$work/verdict"; then
  status=1
  echo "$me: list entries that match no flagged line (the site moved or was migrated; delete the row):" >&2
  grep '^STALE' "$work/verdict" | sort | awk -F '\t' '{ print "  " $2 " row " $3 ": " $4 ": " $5 }' | strip >&2
fi
if [ "$status" -eq 0 ]; then
  IFS="$tab" read -r _ n_allow n_pending <<EOF
$(grep '^COUNT' "$work/verdict")
EOF
  echo "$me: clean ($n_allow allowlisted, $n_pending pending migration)"
fi
exit "$status"
