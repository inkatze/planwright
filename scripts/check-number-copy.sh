#!/bin/sh
# check-number-copy.sh — fail when a spec bundle's prose copies a figure from
# the dated snapshots it is meant to cite.
#
# SNAPSHOTS. Every Markdown file under docs/substrate/ and every
# docs/substrate-*.md (--snapshots names the directory instead, alone).
#
# FIGURES. A run of digits, optionally with a decimal part or with thousands
# commas, compared as a number: `1,234`, `1234` and `01234` are one figure,
# and so are `12.5` and `12.50`. A run is not a figure when the character
# before it is a letter, digit, `_`, `-`, `/`, `#`, `@`, `:`, `.` or `,`, or
# when the one after it is a letter, digit, `_`, `/` or `-`, or a `.`, `:` or
# `,` followed by a digit. So identifiers (`REQ-A1.4`, `D-15`,
# `obs:0087f433`), dates, times and paths are not figures, while a figure
# ending a sentence (`663.`) still is.
#
# PROSE. Every line of the bundle's requirements.md, design.md, tasks.md and
# test-spec.md, except:
#   - the `## Sources` and `## Changelog` sections (dated provenance);
#   - inside a `### D-` decision, a verdict's measurement or cost-benefit
#     line: the paragraph or list item opening with `**Measurement:**`,
#     `**Measurements:**` or `**Cost-benefit:**`, through the line before
#     the next blank line, heading of any level, or list item indented no
#     deeper than it (its own sub-items belong to it);
#   - the metadata field lines whose values are ids or plans, not figures:
#     `**Format-version:**`, and a task's `**Dependencies:**` and
#     `**Estimated effort:**`, at any indent;
#   - a numeral that is a reference, not a quantity: one directly following
#     task, section, step or wave (either case of the first letter), one
#     continuing a plural's list (`Tasks 11 and 12`, `Tasks 5, 9, 10`), and
#     the end of a range (`Tasks 3 through 5`, `Task 3–5`). A singular's
#     comma does not continue it: in `After Task 3, 663 remain` 663 counts.
# A prose figure equal to a snapshot figure is a finding. Only snapshot
# figures count, so a number no snapshot carries never fires.
#
# EXEMPTIONS. scripts/check-number-copy-exempt.tsv (or --exempt): one
# `file<TAB>figure<TAB>reason` row per exempted figure in one bundle file
# (named by base name), a reason required. A row that no longer matches a
# finding fails the run, so the list cannot outlive its cause.
#
# Usage: check-number-copy.sh [--bundle <dir>] [--snapshots <dir>]
#          [--exempt <tsv>]
# Defaults: universal-binary under the resolved spec root; the snapshots
# above.
# Exit codes: 0 clean; 1 a finding or a stale exemption (each printed); 2
# usage error; 5 fail-closed (the spec root not resolving; a bundle file, a
# snapshot, the snapshot directory or the exemption list missing or
# unreadable; no snapshot or no snapshot figure; a malformed exemption row;
# or a failed scan); 128 plus the signal number on HUP, INT or TERM.
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

bundle="" snapshots="" exempt=$script_dir/check-number-copy-exempt.tsv
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

[ -f "$script_dir/spec-parse.sh" ] && [ -r "$script_dir/spec-parse.sh" ] \
  || fail_closed "broken install: spec-parse.sh is missing or not readable"
# shellcheck source=scripts/spec-parse.sh
. "$script_dir/spec-parse.sh"

if [ -z "$bundle" ]; then
  spec_root=$(/bin/sh "$repo_root/scripts/resolve-root.sh" spec) || fail_closed "the spec root does not resolve"
  bundle=$spec_root/universal-binary
fi
for f in requirements.md design.md tasks.md test-spec.md; do
  [ -r "$bundle/$f" ] || fail_closed "the bundle's $f is missing or unreadable"
done
[ -r "$exempt" ] || fail_closed "the exemption list is unreadable"

work=$(mktemp -d "${TMPDIR:-/tmp}/check-number-copy.XXXXXX") || fail_closed "mktemp -d failed"
[ -n "$work" ] && [ -d "$work" ] || fail_closed "mktemp -d produced no directory"
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -n "$snapshots" ]; then
  [ -d "$snapshots" ] && [ -r "$snapshots" ] || fail_closed "the snapshot directory is missing or unreadable"
  set +f
  set -- "$snapshots"/*.md
else
  [ -d "$repo_root/docs/substrate" ] && [ -r "$repo_root/docs/substrate" ] \
    || fail_closed "docs/substrate/ is missing or unreadable"
  set +f
  set -- "$repo_root"/docs/substrate/*.md "$repo_root"/docs/substrate-*.md
fi
set -f
: >"$work/snaps"
for f in "$@"; do
  [ -e "$f" ] || [ -h "$f" ] || continue
  [ -f "$f" ] && [ -r "$f" ] || fail_closed "a snapshot is not a readable file"
  printf '%s\n' "$f" >>"$work/snaps"
done
[ -s "$work/snaps" ] || fail_closed "no snapshot file"

# The tokenizer every pass shares; norm() is the comparison form.
cat >"$work/figures.awk" <<'EOF'
function clean(s) { gsub(/[^[:print:]]/, "", s); return s }
function norm(tok) {
  gsub(/,/, "", tok)
  if (tok ~ /\./) { sub(/0+$/, "", tok); sub(/\.$/, "", tok) }
  sub(/^0+/, "", tok)
  if (tok == "" || tok ~ /^\./) tok = "0" tok
  return tok
}
# figures(s, out, keep_refs): fill out[1..n] with the figures line s holds,
# references dropped unless keep_refs; return n.
function figures(s, out, keep_refs,   n, t, pre, post, tok, pos, prefix) {
  n = 0; t = s; pos = 0
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
    if (!keep_refs && prefix ~ /(^|[^A-Za-z])([Tt]ask|[Ss]ection|[Ss]tep|[Ww]ave)[ ]+$/) continue
    if (!keep_refs && prefix ~ /(^|[^A-Za-z])([Tt]asks|[Ss]ections|[Ss]teps|[Ww]aves)[ ]+([0-9.]+(, | and | or | to | through |, and |, or |–|-))*$/) continue
    if (!keep_refs && prefix ~ /(^|[^A-Za-z])([Tt]ask|[Ss]ection|[Ss]tep|[Ww]ave)[ ]+[0-9.]+(–|-| to | through )$/) continue
    out[++n] = norm(tok)
  }
  return n
}
EOF
cat >"$work/values.awk" <<'EOF'
FNR == 1 { name = FILENAME; sub(/^.*\//, "", name) }
{ n = figures($0, f, 1); for (i = 1; i <= n; i++) print f[i] "\t" clean(name) }
EOF
cat >"$work/prose.awk" <<'EOF'
FNR == 1 { name = FILENAME; sub(/^.*\//, "", name); skip = 0; verdict = 0; indec = 0 }
/^## / { skip = ($0 == "## Sources" || $0 == "## Changelog"); verdict = 0; indec = 0 }
/^### / { indec = spec_parse_dec_attempt($0); verdict = 0 }
/^[ \t]*$/ || /^#+([ \t]|$)/ { verdict = 0 }
verdict && /^[ \t]*- / { match($0, /^[ \t]*/); if (RLENGTH <= vindent) verdict = 0 }
indec && /^[ \t]*(- )?\*\*(Measurements?|Cost-benefit):\*\*/ { verdict = 1; match($0, /^[ \t]*/); vindent = RLENGTH }
skip || verdict { next }
/^[ \t]*(- )?\*\*(Format-version|Dependencies|Estimated effort):\*\*/ { next }
{ n = figures($0, f, 0); for (i = 1; i <= n; i++) print name "\t" f[i] "\t" FNR }
EOF
cat >"$work/compare.awk" <<'EOF'
BEGIN {
  FS = "\t"
  f = ENVIRON["CN_VALUES"]
  while ((r = (getline l < f)) > 0) { split(l, p, "\t"); if (!(p[1] in v)) v[p[1]] = p[2] }
  if (r < 0) { print ENVIRON["CN_ME"] ": the snapshot figures could not be read" > "/dev/stderr"; malformed = 1; exit }
  f = ENVIRON["CN_EXEMPT"]
  while ((r = (getline l < f)) > 0) {
    if (l ~ /^#/ || l ~ /^[ \t]*$/) continue
    n = split(l, p, "\t")
    if (n != 3 || p[1] == "" || p[2] !~ /^([0-9]+|[0-9][0-9]?[0-9]?(,[0-9][0-9][0-9])+)(\.[0-9]+)?$/ || p[3] == "") {
      print ENVIRON["CN_ME"] ": malformed exemption row: " clean(p[1]) " " clean(p[2]) > "/dev/stderr"; malformed = 1; exit
    }
    ex[p[1] "\t" norm(p[2])] = 1
  }
  if (r < 0) { print ENVIRON["CN_ME"] ": the exemption list could not be read" > "/dev/stderr"; malformed = 1; exit }
}
($2 in v) {
  if (($1 "\t" $2) in ex) { used[$1 "\t" $2] = 1; next }
  printf "%s:%s: figure %s also appears in snapshot %s; cite the snapshot instead\n", $1, $3, $2, v[$2]
  bad = 1
}
END {
  if (malformed) exit 5
  for (k in ex) if (!(k in used)) { split(k, p, "\t"); stale[++ns] = "stale exemption: " clean(p[1]) " " p[2] " matches no finding"; bad = 1 }
  for (i = 2; i <= ns; i++) { x = stale[i]; for (j = i - 1; j >= 1 && stale[j] > x; j--) stale[j + 1] = stale[j]; stale[j + 1] = x }
  for (i = 1; i <= ns; i++) print stale[i]
  exit bad ? 1 : 0
}
EOF

: >"$work/values.raw"
while IFS= read -r f; do
  awk -f "$work/figures.awk" -f "$work/values.awk" "$f" >>"$work/values.raw" \
    || fail_closed "a snapshot could not be scanned"
done <"$work/snaps"
sort -u -t "$(printf '\t')" -k1,1 "$work/values.raw" >"$work/values" || fail_closed "sort failed"
[ -s "$work/values" ] || fail_closed "the snapshots carry no figure"

printf '%s\n' "$spec_parse_awk_grammar" >"$work/grammar.awk" || fail_closed "the spec grammar could not be staged"
awk -f "$work/grammar.awk" -f "$work/figures.awk" -f "$work/prose.awk" \
  "$bundle/requirements.md" "$bundle/design.md" "$bundle/tasks.md" "$bundle/test-spec.md" >"$work/findings" \
  || fail_closed "the bundle could not be scanned"

CN_VALUES=$work/values CN_EXEMPT=$exempt CN_ME=$me
export CN_VALUES CN_EXEMPT CN_ME
awk -f "$work/figures.awk" -f "$work/compare.awk" "$work/findings"
rc=$?
case $rc in
  0 | 1) exit "$rc" ;;
  *) fail_closed "the comparison failed" ;;
esac
