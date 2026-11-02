#!/bin/sh
# check-verdict-figures.sh — fail when a figure in a verdict decision's
# rationale names no field of the bake-off report the verdict cites, or
# differs from that field's value.
#
# A verdict is a `### D-` decision in the bundle's design.md carrying a
# **Report:**, **Measurement:** or **Cost-benefit:** line; its rationale is
# the **Chosen because:** and **Measurement(s):** spans; a figure cites a
# field as `<figure> (`<candidate>.<field>`)`. The full form, and what is a
# figure rather than a reference, is in docs/substrate-bakeoff-report.md
# ("Citing a report in a verdict"); scripts/verdict-scan.sh reads it.
#
# Usage: check-verdict-figures.sh [--bundle <dir>] [--root <dir>]
# Defaults: universal-binary under the resolved spec root; report paths
# resolve against the repository root.
# Exit codes: 0 clean (a bundle with no verdict passes); 1 a finding (each
# printed); 2 usage error; 5 fail-closed (the spec root not resolving, the
# design.md or a shared library unreadable, or a failed scan); 128 plus the
# signal number on HUP, INT or TERM.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=check-verdict-figures
script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
repo_root=$(cd "$script_dir/.." && pwd -P) || exit 2

usage() {
  printf '%s\n' "usage: check-verdict-figures.sh [--bundle <dir>] [--root <dir>]" >&2
  exit 2
}

bundle="" root=$repo_root
while [ "$#" -gt 0 ]; do
  case $1 in
    --bundle | --root)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage
      case $1 in
        --bundle) bundle=$2 ;;
        --root) root=$2 ;;
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

for lib in spec-parse.sh verdict-scan.sh; do
  [ -f "$script_dir/$lib" ] && [ -r "$script_dir/$lib" ] || fail_closed "broken install: $lib is missing or not readable"
done
# shellcheck source=scripts/spec-parse.sh
. "$script_dir/spec-parse.sh"
# shellcheck source=scripts/verdict-scan.sh
. "$script_dir/verdict-scan.sh"

if [ -z "$bundle" ]; then
  spec_root=$(/bin/sh "$repo_root/scripts/resolve-root.sh" spec) || fail_closed "the spec root does not resolve"
  bundle=$spec_root/universal-binary
fi
[ -f "$bundle/design.md" ] && [ -r "$bundle/design.md" ] || fail_closed "the bundle's design.md is missing or unreadable"
[ -d "$root" ] || fail_closed "the report root is not a directory"

work=$(mktemp -d "${TMPDIR:-/tmp}/check-verdict-figures.XXXXXX") || fail_closed "mktemp -d failed"
[ -n "$work" ] && [ -d "$work" ] || fail_closed "mktemp -d produced no directory"
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s\n' "$spec_parse_awk_grammar" >"$work/grammar.awk" || fail_closed "the spec grammar could not be staged"
printf '%s\n' "$verdict_scan_awk" >"$work/scan.awk" || fail_closed "the verdict scanner could not be staged"
printf '%s\n' "$verdict_cite_awk" >"$work/cite.awk" || fail_closed "the citation reader could not be staged"
awk -f "$work/grammar.awk" -f "$work/scan.awk" "$bundle/design.md" >"$work/records" \
  || fail_closed "design.md could not be scanned"

VS_ROOT=$root VS_ME=$me
export VS_ROOT VS_ME
cat >"$work/figures.awk" <<'EOF' || fail_closed "the figure check could not be staged"
{ vs_record() }
END {
  for (s = 1; s <= vs_ns; s++) {
    d = vs_s_dec[s]
    if (vs_s_kind[s] != "rationale" || !(d in vs_verdict)) continue
    where = "design.md:" vs_s_line[s] ": "
    n = cites(vs_s_text[s], fig, ref, cref)
    for (i = 1; i <= n; i++) {
      if (ref[i] == "") { printf "%sfigure %s in %s's rationale names no report field; cite it as <figure> (`<candidate>.<field>`)\n", where, fig[i], d; bad = 1; continue }
      if (!vs_np[d]) { if (!(d in noreport)) printf "%s%s cites figures but carries no **Report:** line\n", where, d; noreport[d] = 1; bad = 1; continue }
      cand = ref[i]; sub(/\..*/, "", cand); fld = ref[i]; sub(/^[^.]*\./, "", fld)
      found = report_find(d, cand)
      if (found == "!") { if (!(vc_err in said)) printf "%s%s\n", where, vc_err; said[vc_err] = 1; bad = 1; continue }
      if (found == "") { printf "%s%s names no candidate row of the reports %s cites\n", where, ref[i], d; bad = 1; continue }
      if (!((found, fld) in vc_hasf)) { printf "%s%s names no field of %s\n", where, ref[i], found; bad = 1; continue }
      v = vc_val[found, cand, fld]
      if (v !~ /^[0-9]+(\.[0-9]+)?$/) { printf "%s%s carries no value in %s\n", where, ref[i], found; bad = 1; continue }
      if (vc_norm(fig[i]) != vc_norm(v)) { printf "%sfigure %s cites %s, whose value is %s in %s\n", where, fig[i], ref[i], v, found; bad = 1 }
    }
  }
  exit bad ? 1 : 0
}
EOF
awk -F '\t' -f "$work/cite.awk" -f "$work/figures.awk" "$work/records"
rc=$?
case $rc in
  0 | 1) exit "$rc" ;;
  *) fail_closed "the comparison failed" ;;
esac
