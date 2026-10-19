#!/bin/sh
# substrate-attribute.sh — attribute the mined observation set to script tiers
# and defect classes, as the tier-by-class pain matrix.
#
# THE MINED SET. Every `obs:<uid>` the bundle's `## Sources` section (in its
# requirements.md) cites inside an `- **Observations, <group>:**` bullet, plus
# every frozen legacy-log line the legacy index lists. A fragment is found by
# its UID under the accumulator's entries/ or archive/ (the `_observations`
# directory beside the bundle); a legacy line by its index row.
#
# CLASSES. Fixed: lock-concurrency, parser-fragility, echo-sanitization,
# duplicated-primitive, perf-spawn-cost, portability, lint-gap,
# plugin-delivery, test-flakiness, instruction-headroom, auditability. A
# fragment takes the class of every Sources group that cites it: the group
# label with a trailing ` class` dropped is the class, except `lock and
# concurrency` (lock-concurrency) and `auditability and keep-shell evidence`
# (auditability). A group label naming no class fails closed: a missing class
# is proposed by amendment, never minted here. A legacy line takes the
# classes its index row records.
#
# TIERS. A fragment or line takes the tier of every layer script it names, the
# tier coming from the partition (scripts/substrate-partition.sh). It names a
# script by writing `<stem>.sh` (any path prefix), `test-<stem>.sh` (the
# suite for that script), `scripts/<stem>`, `githooks/<hook>`, or the bare
# stem in backticks; a bare stem outside backticks is prose (`ready-flip` is
# a step as often as a script). A `.sh` name that is no layer script is
# listed as not in the layer and names nothing.
#
# MANUAL FILE. An item naming no layer script is attributed by the manual
# file's row for it (id, tiers, reason), written by a person or worker who
# read it. An item naming none with no row is `needs-manual`; a row for an
# item that names a script is `stale-manual`; either fails the run (exit 1,
# listed on stderr) so coverage never shrinks silently.
#
# INPUT FILES (tab-separated, `#` comment lines and blank lines skipped):
#   legacy index   id  classes  match   (id `legacy:<date>:<slug>`; match is
#                  a fixed string found on exactly one `- <date> ` line of
#                  the frozen log, opportunities.md)
#   manual file    id  tiers  reason
# Lists are comma-separated.
#
# Output (default): the dated pain-matrix snapshot as Markdown. --rows prints
# one TSV row per item instead: id, date, tiers, classes, basis (`script` or
# `manual`), names. --class-map prints id, date, classes, needing neither the
# partition nor the manual file.
#
# Usage: substrate-attribute.sh --as-of <YYYY-MM-DD> [--rows | --class-map]
#          [--repo-root <dir>] [--spec <bundle-dir>] [--partition <tsv>]
#          [--legacy <tsv>] [--manual <tsv>]
# Defaults: the repo is this script's parent; the bundle is universal-binary
# under the resolved spec root; the legacy and manual files are under
# docs/substrate/; the partition is computed.
# Exit codes: 0 written; 1 an item needs a manual row or has a stale one; 2
# usage error; 5 fail-closed (a missing or unreadable input, a UID resolving
# to no fragment or to two, a legacy match on no line or on two, a group
# label or listed class or tier outside the fixed sets, an empty mined set,
# or a partition that fails).
#
# POSIX sh on the macOS + Linux support bar. All input is data.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=substrate-attribute
script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
repo_root=$(cd "$script_dir/.." && pwd -P) || exit 2

usage() {
  printf '%s\n' "usage: substrate-attribute.sh --as-of <YYYY-MM-DD> [--rows | --class-map] [--repo-root <dir>] [--spec <bundle-dir>] [--partition <tsv>] [--legacy <tsv>] [--manual <tsv>]" >&2
  exit 2
}

as_of="" mode=snapshot spec="" partition="" legacy="" manual=""
while [ "$#" -gt 0 ]; do
  case $1 in
    --rows) mode=rows && shift ;;
    --class-map) mode=classes && shift ;;
    --as-of | --repo-root | --spec | --partition | --legacy | --manual)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage
      case $1 in
        --as-of) as_of=$2 ;;
        --repo-root) repo_root=$2 ;;
        --spec) spec=$2 ;;
        --partition) partition=$2 ;;
        --legacy) legacy=$2 ;;
        --manual) manual=$2 ;;
      esac
      shift 2
      ;;
    -h | --help) usage ;;
    *) usage ;;
  esac
done
printf '%s\n' "$as_of" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || usage

fail_closed() {
  printf '%s\n' "$me: $1; failing closed rather than writing a matrix" >&2
  exit 5
}

case $repo_root in -*) repo_root=./$repo_root ;; esac
repo_root=$(cd "$repo_root" 2>/dev/null && pwd -P) || fail_closed "the repo root is not a readable directory"
if [ -z "$spec" ]; then
  spec_root=$(/bin/sh "$repo_root/scripts/resolve-root.sh" spec) || fail_closed "the spec root does not resolve"
  spec=$spec_root/universal-binary
fi
[ -n "$legacy" ] || legacy=$repo_root/docs/substrate/legacy-lines.tsv
[ -n "$manual" ] || manual=$repo_root/docs/substrate/manual-attribution.tsv

reqs=$spec/requirements.md
obs_dir=$(dirname "$spec")/_observations
[ -r "$reqs" ] || fail_closed "the bundle's requirements.md is unreadable"
for d in entries archive; do
  [ -d "$obs_dir/$d" ] && [ -r "$obs_dir/$d" ] || fail_closed "the accumulator's $d/ is missing or unreadable"
done
[ -r "$obs_dir/opportunities.md" ] || fail_closed "the frozen log opportunities.md is unreadable"
[ -r "$legacy" ] || fail_closed "the legacy index is unreadable"
if [ "$mode" != classes ]; then
  [ -r "$manual" ] || fail_closed "the manual attribution file is unreadable"
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/substrate-attribute.XXXXXX") || fail_closed "mktemp -d failed"
[ -n "$work" ] && [ -d "$work" ] || fail_closed "mktemp -d produced no directory"
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

if [ "$mode" != classes ]; then
  if [ -n "$partition" ]; then
    cp "$partition" "$work/partition.tsv" 2>/dev/null || fail_closed "the partition file is unreadable"
  else
    /bin/sh "$repo_root/scripts/substrate-partition.sh" --repo-root "$repo_root" >"$work/partition.tsv" \
      || fail_closed "the partition failed"
  fi
  [ "$(sed -n 1p "$work/partition.tsv" | cut -f1-2)" = "path	tier" ] || fail_closed "the partition has no header row"
fi

# Sources groups: one `uid<TAB>class` record per citation.
awk '
  BEGIN {
    n = split("lock-concurrency parser-fragility echo-sanitization duplicated-primitive perf-spawn-cost portability lint-gap plugin-delivery test-flakiness instruction-headroom auditability", c, " ")
    for (i = 1; i <= n; i++) cls[c[i]] = 1
    alias["lock and concurrency"] = "lock-concurrency"
    alias["auditability and keep-shell evidence"] = "auditability"
  }
  /^## / { insrc = ($0 == "## Sources"); grp = ""; next }
  !insrc { next }
  /^- / {
    grp = ""
    if ($0 ~ /^- \*\*Observations, [^:*]+:\*\*/) {
      lab = $0; sub(/^- \*\*Observations, /, "", lab); sub(/:\*\*.*/, "", lab)
      g = lab; sub(/ class$/, "", g)
      if (g in alias) grp = alias[g]
      else if (g in cls) grp = g
      if (grp == "") { print "group label names no class: " lab > "/dev/stderr"; bad = 1; exit }
    }
  }
  {
    t = $0
    while (match(t, /obs:[0-9a-f]+/)) {
      u = substr(t, RSTART + 4, RLENGTH - 4); t = substr(t, RSTART + RLENGTH)
      if (grp == "") { print "obs:" u " is cited outside an Observations group" > "/dev/stderr"; bad = 1; exit }
      print "obs:" u "\t" grp
    }
  }
  END { exit bad ? 5 : 0 }
' "$reqs" >"$work/cites.tsv" || fail_closed "the Sources section has an unclassifiable citation"
sort -u "$work/cites.tsv" -o "$work/cites.tsv"
[ -s "$work/cites.tsv" ] || fail_closed "the Sources section cites no observation"

# Items: `id<TAB>date<TAB>path-or-line-number<TAB>kind`.
: >"$work/items.tsv"
cut -f1 "$work/cites.tsv" | sed 's/^obs://' | sort -u >"$work/uids"
while IFS= read -r u; do
  set +f
  found=""
  for f in "$obs_dir"/entries/*-"$u".md "$obs_dir"/archive/*-"$u".md; do
    [ -f "$f" ] || continue
    [ -z "$found" ] || {
      set -f
      fail_closed "obs:$u resolves to more than one fragment"
    }
    found=$f
  done
  set -f
  [ -n "$found" ] || fail_closed "obs:$u resolves to no fragment"
  [ -r "$found" ] || fail_closed "obs:$u's fragment is unreadable"
  d=$(basename "$found" | cut -c1-10)
  printf '%s\t%s\t%s\tfragment\n' "obs:$u" "$d" "$found" >>"$work/items.tsv"
done <"$work/uids"

awk -F'\t' -v out="$work/items.tsv" -v cites="$work/cites.tsv" '
  BEGIN {
    n = split("lock-concurrency parser-fragility echo-sanitization duplicated-primitive perf-spawn-cost portability lint-gap plugin-delivery test-flakiness instruction-headroom auditability", c, " ")
    for (i = 1; i <= n; i++) cls[c[i]] = 1
  }
  FNR == NR {
    if ($0 ~ /^#/ || $0 ~ /^[ \t]*$/) next
    if (NF != 3 || $1 !~ /^legacy:[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]:[a-z0-9-]+$/ || $3 == "") {
      print "malformed legacy index row: " $1 > "/dev/stderr"; bad = 1; exit
    }
    if ($1 in seen) { print "duplicate legacy id: " $1 > "/dev/stderr"; bad = 1; exit }
    seen[$1] = 1
    m = split($2, cc, ",")
    for (i = 1; i <= m; i++) if (!(cc[i] in cls)) { print "unknown class in " $1 ": " cc[i] > "/dev/stderr"; bad = 1; exit }
    ids[++k] = $1; match_[k] = $3; dt[k] = substr($1, 8, 10); klass[k] = $2
    next
  }
  {
    for (j = 1; j <= k; j++)
      if (index($0, "- " dt[j] " ") == 1 && index($0, match_[j])) { hit[j]++; line[j] = FNR }
  }
  END {
    if (bad) exit 5
    for (j = 1; j <= k; j++) {
      if (hit[j] != 1) { print ids[j] " matches " hit[j] + 0 " frozen-log lines, not one" > "/dev/stderr"; exit 5 }
      print ids[j] "\t" dt[j] "\t" line[j] "\tlegacy" >> out
      m = split(klass[j], cc, ",")
      for (i = 1; i <= m; i++) print ids[j] "\t" cc[i] >> cites
    }
  }
' "$legacy" "$obs_dir/opportunities.md" || fail_closed "the legacy index does not resolve"
sort -u "$work/cites.tsv" -o "$work/cites.tsv"
sort "$work/items.tsv" -o "$work/items.tsv"

if [ "$mode" = classes ]; then
  awk -F'\t' '
    FNR == NR { v = ($1 in c) ? c[$1] "," $2 : $2; c[$1] = v; next }
    { print $1 "\t" $2 "\t" c[$1] }
  ' "$work/cites.tsv" "$work/items.tsv"
  exit 0
fi

# Attribute each item: named layer scripts, their tiers, or the manual row.
OPP=$obs_dir/opportunities.md
export OPP
awk -F'\t' -v part="$work/partition.tsv" -v man="$manual" -v cites="$work/cites.tsv" -v rowsout="$work/rows.tsv" '
  BEGIN {
    tiers = "hook skill-called library dev-check tests-only"
    split(tiers, tl, " "); for (i in tl) tierok[tl[i]] = 1
    getline hdr < part
    while ((getline l < part) > 0) {
      split(l, p, "\t"); s = p[1]; sub(/^.*\//, "", s); sub(/\.sh$/, "", s)
      tier[s] = p[2]; path[s] = p[1]
    }
    while ((getline l < cites) > 0) {
      split(l, p, "\t"); v = (p[1] in cl) ? cl[p[1]] "," p[2] : p[2]; cl[p[1]] = v
    }
    while ((getline l < man) > 0) {
      if (l ~ /^#/ || l ~ /^[ \t]*$/) continue
      nf = split(l, p, "\t")
      if (nf != 3 || p[3] == "") { print "malformed manual row: " p[1] > "/dev/stderr"; bad = 5; exit }
      if (p[1] in mt) { print "duplicate manual row: " p[1] > "/dev/stderr"; bad = 5; exit }
      m = split(p[2], tt, ",")
      for (i = 1; i <= m; i++) if (!(tt[i] in tierok)) { print "unknown tier in " p[1] ": " tt[i] > "/dev/stderr"; bad = 5; exit }
      mt[p[1]] = p[2]
    }
    opp = ENVIRON["OPP"]; ln = 0
    while ((getline l < opp) > 0) oppline[++ln] = l
  }
  function add(list, x,   n, a, i) {
    n = split(list, a, ",")
    for (i = 1; i <= n; i++) if (a[i] == x) return list
    return list == "" ? x : list "," x
  }
  function name(w) {
    if (w in tier) { named = add(named, path[w]); return 1 }
    return 0
  }
  {
    if (bad) exit bad
    id = $1; txt = ""
    if ($4 == "legacy") txt = oppline[$3]
    else { while ((getline l < $3) > 0) txt = txt " " l; close($3) }
    named = ""; stray = ""; t = txt
    while (match(t, /[A-Za-z0-9_.\/-]*[A-Za-z0-9_-]\.sh/)) {
      w = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
      sub(/^.*\//, "", w); sub(/\.sh$/, "", w)
      if (name(w)) continue
      if (w ~ /^test-/ && name(substr(w, 6))) continue
      stray = add(stray, w ".sh")
    }
    t = txt
    while (match(t, /(scripts|githooks)\/[A-Za-z0-9_-]+/)) {
      w = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
      if (substr(t, 1, 3) == ".sh") continue
      sub(/^.*\//, "", w); name(w)
    }
    t = txt
    while (match(t, /`[A-Za-z0-9_-]+`/)) {
      w = substr(t, RSTART + 1, RLENGTH - 2); t = substr(t, RSTART + RLENGTH)
      name(w)
    }
    tset = ""
    n = split(named, a, ",")
    for (i = 1; i <= n; i++) { s = a[i]; sub(/^.*\//, "", s); sub(/\.sh$/, "", s); tset = add(tset, tier[s]) }
    if (named != "") {
      basis = "script"
      if (id in mt) { print "stale-manual\t" id > "/dev/stderr"; fails = 1 }
    } else if (id in mt) {
      basis = "manual"; tset = mt[id]
    } else {
      print "needs-manual\t" id > "/dev/stderr"; fails = 1; next
    }
    used[id] = 1
    if (stray != "") named = named (named == "" ? "" : ",") "not-in-layer:" stray
    print id "\t" $2 "\t" tset "\t" cl[id] "\t" basis "\t" (named == "" ? "-" : named) > rowsout
  }
  END {
    if (bad) exit bad
    for (id in mt) if (!(id in used)) { print "orphan-manual\t" id > "/dev/stderr"; fails = 1 }
    exit fails ? 1 : 0
  }
' "$work/items.tsv"
rc=$?
[ "$rc" -eq 5 ] && fail_closed "an input file is malformed"
[ "$rc" -eq 0 ] || {
  printf '%s\n' "$me: attribution incomplete; see the needs-manual, stale-manual and orphan-manual lines above" >&2
  exit 1
}

if [ "$mode" = rows ]; then
  cat "$work/rows.tsv"
  exit 0
fi

awk -F'\t' -v asof="$as_of" '
  BEGIN {
    nc = split("lock-concurrency parser-fragility echo-sanitization duplicated-primitive perf-spawn-cost portability lint-gap plugin-delivery test-flakiness instruction-headroom auditability", c, " ")
    nt = split("hook skill-called library dev-check tests-only", tl, " ")
  }
  {
    rows[++nr] = $0; nobs++
    if ($5 == "manual") nman++
    nt_ = split($3, ts, ","); nk = split($4, ks, ",")
    for (i = 1; i <= nt_; i++) {
      tierobs[ts[i]]++
      for (j = 1; j <= nk; j++) cell[ts[i], ks[j]]++
    }
    for (j = 1; j <= nk; j++) classobs[ks[j]]++
  }
  END {
    print "# Substrate pain matrix, as of " asof
    print ""
    print "Generated by `scripts/substrate-attribute.sh`; do not edit by hand. Regenerate on an"
    print "unchanged tree with:"
    print ""
    print "```sh"
    print "/bin/sh scripts/substrate-attribute.sh --as-of " asof " >docs/substrate/pain-matrix-" asof ".md"
    print "```"
    print ""
    print "The mined set is every observation the universal-binary bundle cites under its"
    print "Sources (fragment UIDs) plus the frozen legacy-log lines listed in"
    print "`docs/substrate/legacy-lines.tsv`. Each item counts once in every cell of its"
    print "tiers crossed with its classes, so a row or column does not sum to the item"
    print "count. Tiers come from the partition (`scripts/substrate-partition.sh`) through"
    print "the scripts an item names; an item naming none is attributed by"
    print "`docs/substrate/manual-attribution.tsv`. The script header defines both rules."
    print ""
    print "## Summary"
    print ""
    print "| measure | value |"
    print "| --- | --- |"
    print "| items attributed | " nobs " |"
    print "| attributed through a named script | " nobs - nman " |"
    print "| attributed by the manual file | " nman + 0 " |"
    print "| unattributed | 0 |"
    print ""
    print "## Matrix"
    print ""
    h = "| tier |"; s = "| --- |"
    for (j = 1; j <= nc; j++) { h = h " " c[j] " |"; s = s " ---: |" }
    print h " items |"
    print s " ---: |"
    for (i = 1; i <= nt; i++) {
      r = "| " tl[i] " |"
      for (j = 1; j <= nc; j++) r = r " " (cell[tl[i], c[j]] + 0) " |"
      print r " " (tierobs[tl[i]] + 0) " |"
    }
    r = "| any tier |"
    for (j = 1; j <= nc; j++) r = r " " (classobs[c[j]] + 0) " |"
    print r " " nobs " |"
    print ""
    print "## Attribution"
    print ""
    print "| item | date | tiers | classes | basis | names |"
    print "| --- | --- | --- | --- | --- | --- |"
    for (i = 1; i <= nr; i++) {
      split(rows[i], f, "\t")
      nm = f[6]; gsub(/,/, ", ", nm)
      print "| " f[1] " | " f[2] " | " f[3] " | " f[4] " | " f[5] " | " nm " |"
    }
  }
' "$work/rows.tsv"
