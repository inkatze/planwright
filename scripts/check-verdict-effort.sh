#!/bin/sh
# check-verdict-effort.sh — fail when a verdict decision's migration effort
# neither cites the porting rate its bake-off logged nor carries the explicit
# absence token of a verdict the screen settled.
#
# A verdict is a `### D-` decision in the bundle's design.md carrying a
# **Report:**, **Measurement:** or **Cost-benefit:** line; its effort is the
# **Migration effort:** span. The span passes when it carries
# `porting-rate: absent`, or cites `<candidate>.porting_rate_min_per_kib` of a
# full candidate in a report its **Report:** line names (its own bake-off or
# the inherited one), any figure before the citation equal to the logged
# rate. The full form is in docs/substrate-bakeoff-report.md ("Citing a
# report in a verdict"); scripts/verdict-scan.sh reads it.
#
# Usage: check-verdict-effort.sh [--bundle <dir>] [--root <dir>]
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

me=check-verdict-effort
script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
repo_root=$(cd "$script_dir/.." && pwd -P) || exit 2

usage() {
  printf '%s\n' "usage: check-verdict-effort.sh [--bundle <dir>] [--root <dir>]" >&2
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

for lib in spec-parse.sh verdict-scan.sh substrate-bakeoff.sh; do
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

work=$(mktemp -d "${TMPDIR:-/tmp}/check-verdict-effort.XXXXXX") || fail_closed "mktemp -d failed"
[ -n "$work" ] && [ -d "$work" ] || fail_closed "mktemp -d produced no directory"
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s\n' "$spec_parse_awk_fence" >"$work/fence.awk" || fail_closed "the fence lexer could not be staged"
printf '%s\n' "$spec_parse_awk_grammar" >"$work/grammar.awk" || fail_closed "the spec grammar could not be staged"
printf '%s\n' "$verdict_scan_awk" >"$work/scan.awk" || fail_closed "the verdict scanner could not be staged"
printf '%s\n' "$verdict_cite_awk" >"$work/cite.awk" || fail_closed "the citation reader could not be staged"
awk -f "$work/fence.awk" -f "$work/grammar.awk" -f "$work/scan.awk" "$bundle/design.md" >"$work/records" \
  || fail_closed "design.md could not be scanned"

VS_ROOT=$root VS_ME=$me VS_BAKEOFF=$script_dir/substrate-bakeoff.sh
export VS_ROOT VS_ME VS_BAKEOFF
cat >"$work/effort.awk" <<'EOF' || fail_closed "the effort check could not be staged"
{ vs_record() }
END {
  for (s = 1; s <= vs_ns; s++) if (vs_s_kind[s] == "effort") has[vs_s_dec[s]] = 1
  for (d in vs_verdict) if (!(d in has)) { miss[++nm] = "design.md:" vs_verdict[d] ": " d " is a verdict without a **Migration effort:** statement; extrapolate it from the logged porting rate, or state `porting-rate: absent` for a verdict settled by screen"; bad = 1 }
  for (i = 2; i <= nm; i++) { x = miss[i]; for (j = i - 1; j >= 1 && miss[j] > x; j--) miss[j + 1] = miss[j]; miss[j + 1] = x }
  for (i = 1; i <= nm; i++) print miss[i]
  for (s = 1; s <= vs_ns; s++) {
    d = vs_s_dec[s]
    if (vs_s_kind[s] != "effort" || !(d in vs_verdict)) continue
    where = "design.md:" vs_s_line[s] ": "
    if (index(vs_s_text[s], "`porting-rate: absent`")) continue
    n = cites(vs_s_text[s], fig, ref, cref)
    rate = 0
    for (k = 1; k <= vc_nref; k++) {
      if (cref[k] !~ /\.porting_rate_min_per_kib$/) continue
      rate++
      cand = cref[k]; sub(/\..*/, "", cand)
      if (!vs_np[d]) { printf "%s%s cites a porting rate but carries no **Report:** line\n", where, d; bad = 1; continue }
      found = report_find(d, cand)
      if (found == "!") { printf "%s%s\n", where, vc_err; bad = 1; continue }
      if (found == "") { printf "%s%s names no full candidate of the reports %s cites\n", where, cref[k], d; bad = 1; continue }
      v = vc_val[found, cand, "porting_rate_min_per_kib"]
      if (vc_val[found, cand, "class"] != "full" || v !~ /^[0-9]+(\.[0-9]+)?$/) { printf "%s%s carries no logged rate in %s (only a full candidate logs one)\n", where, cref[k], found; bad = 1; continue }
      for (i = 1; i <= n; i++) if (ref[i] == cref[k] && vc_norm(fig[i]) != vc_norm(v)) { printf "%sfigure %s cites %s, whose logged value is %s in %s\n", where, fig[i], cref[k], v, found; bad = 1 }
    }
    if (!rate) { printf "%s%s's migration effort neither cites a logged porting rate (`<candidate>.porting_rate_min_per_kib`) nor carries `porting-rate: absent`\n", where, d; bad = 1 }
  }
  exit bad ? 1 : 0
}
EOF
awk -F '\t' -f "$work/cite.awk" -f "$work/effort.awk" "$work/records"
rc=$?
case $rc in
  0 | 1) exit "$rc" ;;
  *) fail_closed "the comparison failed" ;;
esac
