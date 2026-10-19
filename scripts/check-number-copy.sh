#!/bin/sh
# check-number-copy.sh — fail when a spec bundle's prose copies a figure from
# the dated snapshots it is meant to cite (universal-binary REQ-A1.4, D-4).
#
# SNAPSHOT VALUES. Every figure in the snapshot directory's Markdown files.
# A figure is a run of digits, optionally with a decimal part or with
# thousands commas (`1,234` and `1234` are the same figure), standing alone:
# not glued to a letter, digit, `_`, `-`, `/`, `#`, `@`, `:` or `.` on either
# side, so identifiers (`REQ-A1.4`, `D-15`, `obs:0087f433`), dates, times,
# versions written as part of a word, and paths are not figures.
#
# PROSE. Every line of the bundle's requirements.md, design.md, tasks.md and
# test-spec.md, except:
#   - the `## Sources` and `## Changelog` sections (dated provenance);
#   - inside a `### D-` decision, a verdict's measurement or cost-benefit
#     line: the paragraph or list item opening with `**Measurement:**`,
#     `**Measurements:**` or `**Cost-benefit:**`, through the line before
#     the next blank line, list item, or heading;
#   - the metadata field lines whose values are ids or plans, not figures:
#     `**Format-version:**`, and a task's `**Dependencies:**` and
#     `**Estimated effort:**`;
#   - a numeral that is a reference, not a quantity: one following `Task`,
#     `Tasks`, `task`, `tasks`, `section`, `sections`, `Section`, `step`,
#     `steps`, `Step`, `wave` or `waves`, or continuing such a list
#     (`Tasks 11 and 12`, `Tasks 5, 9, 10`).
# A prose figure equal to a snapshot value is a finding. Only snapshot values
# count, so a number no snapshot carries never fires.
#
# EXEMPTIONS. scripts/check-number-copy-exempt.tsv (or --exempt): one
# `file<TAB>figure<TAB>reason` row per exempted figure in one bundle file
# (named by base name), a reason required. A row that no longer matches a
# finding fails the run, so the list cannot outlive its cause.
#
# Usage: check-number-copy.sh [--bundle <dir>] [--snapshots <dir>]
#          [--exempt <tsv>]
# Defaults: universal-binary under the resolved spec root; docs/substrate.
# Exit codes: 0 clean; 1 a finding or a stale exemption (each printed); 2
# usage error; 5 fail-closed (a bundle file or the snapshot directory
# missing or unreadable, no snapshot file, or a malformed exemption row).
#
# POSIX sh on the macOS + Linux support bar. All input is data.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=check-number-copy
script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
repo_root=$(cd "$script_dir/.." && pwd -P) || exit 2

usage() {
  printf '%s\n' "usage: check-number-copy.sh [--bundle <dir>] [--snapshots <dir>] [--exempt <tsv>]" >&2
  exit 2
}

bundle="" snapshots=$repo_root/docs/substrate exempt=$script_dir/check-number-copy-exempt.tsv
while [ "$#" -gt 0 ]; do
  case $1 in
    --bundle | --snapshots | --exempt)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage
      case $1 in
        --bundle) bundle=$2 ;;
        --snapshots) snapshots=$2 ;;
        --exempt) exempt=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done

fail_closed() {
  printf '%s\n' "$me: $1; failing closed rather than passing" >&2
  exit 5
}

if [ -z "$bundle" ]; then
  spec_root=$(/bin/sh "$repo_root/scripts/resolve-root.sh" spec) || fail_closed "the spec root does not resolve"
  bundle=$spec_root/universal-binary
fi
for f in requirements.md design.md tasks.md test-spec.md; do
  [ -r "$bundle/$f" ] || fail_closed "the bundle's $f is missing or unreadable"
done
[ -d "$snapshots" ] && [ -r "$snapshots" ] || fail_closed "the snapshot directory is missing or unreadable"
[ -r "$exempt" ] || fail_closed "the exemption list is unreadable"

work=$(mktemp -d "${TMPDIR:-/tmp}/check-number-copy.XXXXXX") || fail_closed "mktemp -d failed"
[ -n "$work" ] && [ -d "$work" ] || fail_closed "mktemp -d produced no directory"
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

set +f
: >"$work/snaps"
for f in "$snapshots"/*.md; do
  [ -f "$f" ] || continue
  [ -r "$f" ] || {
    set -f
    fail_closed "a snapshot file is unreadable"
  }
  printf '%s\n' "$f" >>"$work/snaps"
done
set -f
[ -s "$work/snaps" ] || fail_closed "the snapshot directory holds no snapshot"

# figures(): one `figure<TAB>line-number` record per figure a line holds that
# is not a reference; the awk library both passes share.
cat >"$work/figures.awk" <<'EOF'
function figures(s, lineno, keep_refs,   out, t, pre, post, tok, pos, prefix) {
  out = ""; t = s; pos = 0
  while (match(t, /[0-9]+(,[0-9][0-9][0-9])*(\.[0-9]+)?/)) {
    tok = substr(t, RSTART, RLENGTH)
    pre = (pos + RSTART > 1) ? substr(s, pos + RSTART - 1, 1) : ""
    post = substr(s, pos + RSTART + RLENGTH, 2)
    prefix = substr(s, 1, pos + RSTART - 1)
    pos += RSTART + RLENGTH - 1
    t = substr(t, RSTART + RLENGTH)
    if (pre ~ /[A-Za-z0-9_\/#@:.,-]/) continue
    if (substr(post, 1, 1) ~ /[A-Za-z0-9_\/-]/) continue
    if (post ~ /^[.:,][0-9]/) continue
    if (!keep_refs && prefix ~ /(^|[^A-Za-z])([Tt]asks?|[Ss]ections?|[Ss]teps?|waves?)[ ]+([0-9.]+(, | and | or | to |, and |, or ))*$/) continue
    gsub(/,/, "", tok)
    out = out tok "\t" lineno "\n"
  }
  return out
}
EOF

while IFS= read -r f; do
  awk -v name="$(basename "$f")" "$(cat "$work/figures.awk")"'
    { r = figures($0, FNR, 1); n = split(r, a, "\n"); for (i = 1; i < n; i++) { split(a[i], p, "\t"); print p[1] "\t" name } }
  ' "$f"
done <"$work/snaps" | sort -u -t "$(printf '\t')" -k1,1 >"$work/values"

: >"$work/findings"
for f in requirements.md design.md tasks.md test-spec.md; do
  awk -v name="$f" "$(cat "$work/figures.awk")"'
    /^## / { skip = ($0 == "## Sources" || $0 == "## Changelog"); verdict = 0; indec = 0 }
    /^### / { indec = ($0 ~ /^### D-/); verdict = 0 }
    /^[ \t]*$/ { verdict = 0 }
    /^[ \t]*- / { verdict = 0 }
    indec && /^[ \t]*(- )?\*\*(Measurements?|Cost-benefit):\*\*/ { verdict = 1 }
    skip || verdict { next }
    /^(- )?\*\*(Format-version|Dependencies|Estimated effort):\*\*/ { next }
    { r = figures($0, FNR, 0); n = split(r, a, "\n"); for (i = 1; i < n; i++) print name "\t" a[i] }
  ' "$bundle/$f" >>"$work/findings"
done

awk -F'\t' -v values="$work/values" -v exempt="$exempt" '
  BEGIN {
    while ((getline l < values) > 0) { split(l, p, "\t"); if (!(p[1] in v)) v[p[1]] = p[2] }
    while ((getline l < exempt) > 0) {
      if (l ~ /^#/ || l ~ /^[ \t]*$/) continue
      n = split(l, p, "\t")
      if (n != 3 || p[3] == "") { print "check-number-copy: malformed exemption row: " p[1] " " p[2] > "/dev/stderr"; malformed = 1; exit }
      ex[p[1] "\t" p[2]] = 1
    }
  }
  ($2 in v) {
    if (($1 "\t" $2) in ex) { used[$1 "\t" $2] = 1; next }
    printf "%s:%s: figure %s also appears in snapshot %s; cite the snapshot instead\n", $1, $3, $2, v[$2]
    bad = 1
  }
  END {
    if (malformed) exit 5
    for (k in ex) if (!(k in used)) { split(k, p, "\t"); printf "stale exemption: %s %s matches no finding\n", p[1], p[2]; bad = 1 }
    exit bad ? 1 : 0
  }
' "$work/findings"
