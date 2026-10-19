#!/bin/sh
# substrate-attribute.sh — attribute the mined observation set to script tiers
# and defect classes, as the tier-by-class pain matrix.
#
# THE MINED SET. Every `obs:<uid>` the bundle's `## Sources` section (in its
# requirements.md) cites, plus every frozen legacy-log line the legacy index
# lists. A Sources citation must sit in an `- **Observations, <group>:**`
# bullet or its indented continuation lines; one anywhere else in Sources
# fails closed, since it would have no class. A fragment is found by its UID
# under the accumulator's entries/ or archive/ (the `_observations` directory
# beside the bundle), its date being the `YYYY-MM-DD` its file name opens
# with; a legacy line by its index row. Every item must be dated on or before
# --as-of, so a snapshot's date bounds what it counts.
#
# CLASSES. Fixed: lock-concurrency, parser-fragility, echo-sanitization,
# duplicated-primitive, perf-spawn-cost, portability, lint-gap,
# plugin-delivery, test-flakiness, instruction-headroom, auditability
# (`--classes` prints them, in this order). A fragment takes the class of every
# Sources group that cites it: the group label with a trailing ` class` dropped
# is the class, except `lock and concurrency` (lock-concurrency) and
# `auditability and keep-shell evidence` (auditability). A group label naming
# no class fails closed: a missing class is proposed by amendment, never
# minted here. A legacy line takes the classes its index row records.
#
# TIERS. A fragment or line takes the tier of every layer script it names, the
# tier coming from the partition (scripts/substrate-partition.sh's output,
# read from --partition). It names a script by writing `<stem>.sh` (any path
# prefix, not followed by a letter, digit, `_` or `-`), `test-<stem>.sh` (the
# suite for that script), `scripts/<stem>` or `githooks/<hook>` (not inside a
# longer word, and not followed by `/` or by `.` and a name character), or the
# bare stem in backticks; a bare stem outside backticks is prose
# (`ready-flip` is a step as often as a script). A `.sh` name that is no layer
# script is listed as not in the layer and names nothing.
#
# MANUAL FILE. An item naming no layer script is attributed by the manual
# file's row for it (id, tiers, reason), written by a person or worker who
# read it. An item naming none with no row is `needs-manual`; a row for an
# item that names a script is `stale-manual`; a row for an id outside the
# mined set is `orphan-manual`. Any of them fails the run (exit 1, listed on
# stderr) so coverage never shrinks silently.
#
# INPUT FILES (tab-separated, `#` comment lines and blank lines skipped):
#   legacy index   id  classes  match   (id `legacy:<date>:<slug>`; match is
#                  a fixed string found on exactly one `- <date> ` line of
#                  the frozen log, opportunities.md, no two rows on one line)
#   manual file    id  tiers  reason
# Lists are comma-separated and must not be empty. Inside a git work tree,
# an uncommitted, untracked or ignored change to the bundle, the accumulator,
# or either input file fails closed, however the path is spelt: the snapshot
# records the committed tree, not a working copy. The substrate:attribute task
# holds the partition's own inputs to the same rule.
#
# Output (default): the dated pain-matrix snapshot as Markdown. --rows prints
# one TSV row per item instead: id, date, tiers, classes, basis (`script` or
# `manual`), names. --class-map prints id, date, classes and needs neither the
# partition nor the manual file; --obs-dir prints the accumulator directory.
# --out writes the output to a file, replacing it only once the run succeeds.
#
# Usage: substrate-attribute.sh --as-of <YYYY-MM-DD> --partition <tsv>
#          [--rows] [--repo-root <dir>] [--spec <bundle-dir>]
#          [--legacy <tsv>] [--manual <tsv>] [--out <file>]
#        substrate-attribute.sh --as-of <YYYY-MM-DD> --class-map [...]
#        substrate-attribute.sh --classes | --obs-dir [--spec <bundle-dir>]
# `mise run substrate:attribute -- --as-of <date> --out <file>` computes the
# partition and passes it in.
# Defaults: the repo is this script's parent; the bundle is universal-binary
# under the resolved spec root; the legacy and manual files are under
# docs/substrate/.
# Exit codes: 0 written; 1 an item needs a manual row or has a stale or
# orphan one; 2 usage error; 5 fail-closed (a missing or unreadable input; an
# uncommitted input; a UID resolving to no fragment, to two, to a symlink, or
# to a name opening with no date; an item dated after --as-of; a Sources
# citation outside an Observations group or one whose UID is not lowercase
# hex; --out naming a directory; a legacy match on no line or on
# two, or two rows on one line; a malformed, duplicate or empty-listed legacy
# or manual row; a group label, class, or tier outside the fixed sets; a
# partition with no header or two scripts sharing a stem; an empty mined set;
# or a failed step); 128 plus the signal number on HUP, INT or TERM.
#
# POSIX sh on the macOS + Linux support bar. All input is data.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=substrate-attribute
script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
repo_root=$(cd "$script_dir/.." && pwd -P) || exit 2

# The fixed sets every awk program below reads through the environment.
SA_CLASSES="lock-concurrency parser-fragility echo-sanitization duplicated-primitive perf-spawn-cost portability lint-gap plugin-delivery test-flakiness instruction-headroom auditability"
SA_TIERS="hook skill-called library dev-check tests-only"
export SA_CLASSES SA_TIERS

usage() {
  printf '%s\n' "usage: substrate-attribute.sh --as-of <YYYY-MM-DD> (--partition <tsv> [--rows] | --class-map) [--repo-root <dir>] [--spec <bundle-dir>] [--legacy <tsv>] [--manual <tsv>] [--out <file>]; or --classes; or --obs-dir [--spec <bundle-dir>]" >&2
  exit 2
}

as_of="" mode=snapshot spec="" partition="" legacy="" manual="" out=""
while [ "$#" -gt 0 ]; do
  case $1 in
    --rows) mode=rows && shift ;;
    --class-map) mode=class-map && shift ;;
    --classes) mode=classes && shift ;;
    --obs-dir) mode=obs-dir && shift ;;
    --as-of | --repo-root | --spec | --partition | --legacy | --manual | --out)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage
      case $1 in
        --as-of) as_of=$2 ;;
        --repo-root) repo_root=$2 ;;
        --spec) spec=$2 ;;
        --partition) partition=$2 ;;
        --legacy) legacy=$2 ;;
        --manual) manual=$2 ;;
        --out) out=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done

if [ "$mode" = classes ]; then
  # shellcheck disable=SC2086 # the list splits into one class per line
  printf '%s\n' $SA_CLASSES
  exit 0
fi

fail_closed() {
  printf '%s\n' "$me: $1; failing closed rather than writing a matrix" >&2
  exit 5
}

case $repo_root in -*) repo_root=./$repo_root ;; esac
repo_root=$(cd "$repo_root" 2>/dev/null && pwd -P) || fail_closed "the repo root is not a readable directory"
if [ -z "$spec" ]; then
  spec_root=$(cd "$repo_root" && /bin/sh scripts/resolve-root.sh spec) || fail_closed "the spec root does not resolve"
  spec=$spec_root/universal-binary
fi
obs_dir=$(dirname "$spec")/_observations
if [ "$mode" = obs-dir ]; then
  printf '%s\n' "$obs_dir"
  exit 0
fi

# A shape check plus month and day ranges; a newline or a trailing byte in the
# value fails the case pattern, where a line-wise grep would pass it.
case $as_of in
  [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) ;;
  *) usage ;;
esac
case $as_of in
  *-00-* | *-1[3-9]-* | *-00 | *-3[2-9]) usage ;;
esac
case $mode in
  snapshot | rows) [ -n "$partition" ] || usage ;;
esac

[ -n "$legacy" ] || legacy=$repo_root/docs/substrate/legacy-lines.tsv
[ -n "$manual" ] || manual=$repo_root/docs/substrate/manual-attribution.tsv

reqs=$spec/requirements.md
[ -r "$reqs" ] || fail_closed "the bundle's requirements.md is unreadable"
for d in entries archive; do
  [ -d "$obs_dir/$d" ] && [ -r "$obs_dir/$d" ] || fail_closed "the accumulator's $d/ is missing or unreadable"
done
[ -r "$obs_dir/opportunities.md" ] || fail_closed "the frozen log opportunities.md is unreadable"
[ -r "$legacy" ] || fail_closed "the legacy index is unreadable"
if [ "$mode" != class-map ]; then
  [ -r "$manual" ] || fail_closed "the manual attribution file is unreadable"
fi

# canon <path>: the physical absolute path, so a relative or symlinked input
# is still recognised as inside the repo.
canon() {
  if [ -d "$1" ]; then
    (cd -P -- "$1" 2>/dev/null && pwd -P)
  else
    cn_dir=$(cd -P -- "$(dirname -- "$1")" 2>/dev/null && pwd -P) || return 1
    printf '%s/%s\n' "$cn_dir" "$(basename -- "$1")"
  fi
}

# Inputs inside a git work tree must match HEAD, ignored files included, or
# the snapshot would record a working copy nobody can regenerate it from.
if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  set -- "$spec" "$obs_dir" "$legacy"
  [ "$mode" = class-map ] || set -- "$@" "$manual"
  for p in "$@"; do
    p=$(canon "$p") || fail_closed "an input path does not resolve"
    case $p in
      "$repo_root"/*)
        dirty=$(git --literal-pathspecs -C "$repo_root" status --porcelain --untracked-files=all --ignored=matching -- "$p") \
          || fail_closed "git cannot read the state of an input"
        [ -z "$dirty" ] || fail_closed "an input has uncommitted changes (commit it, then regenerate)"
        ;;
    esac
  done
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/substrate-attribute.XXXXXX") || fail_closed "mktemp -d failed"
[ -n "$work" ] && [ -d "$work" ] || fail_closed "mktemp -d produced no directory"
tmp_out=""
trap 'rm -rf "$work"; [ -z "$tmp_out" ] || rm -f "$tmp_out"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Every path an awk program reads or writes travels through the environment:
# `awk -v` would turn a backslash in a path into an escape.
SA_REQS=$reqs SA_LEGACY=$legacy SA_MANUAL=$manual SA_OPP=$obs_dir/opportunities.md
SA_CITES=$work/cites.tsv SA_ITEMS=$work/items.tsv SA_PART=$work/partition.tsv SA_ROWS=$work/rows.tsv
SA_CITES_RAW=$work/cites.raw SA_ITEMS_RAW=$work/items.raw
export SA_REQS SA_LEGACY SA_MANUAL SA_OPP SA_CITES SA_ITEMS SA_PART SA_ROWS SA_CITES_RAW SA_ITEMS_RAW

if [ "$mode" != class-map ]; then
  cp "$partition" "$SA_PART" 2>/dev/null || fail_closed "the partition file is unreadable"
  [ "$(sed -n 1p "$SA_PART" | cut -f1-2)" = "path	tier" ] || fail_closed "the partition has no header row"
fi

# Sources groups: one `obs:<uid><TAB>class` record per citation. A group runs
# from its bullet through the indented lines that continue it.
awk '
  function clean(s) { gsub(/[^[:print:]]/, "", s); return s }
  BEGIN {
    n = split(ENVIRON["SA_CLASSES"], c, " ")
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
      if (grp == "") { print "group label names no class: " clean(lab) > "/dev/stderr"; bad = 1; exit }
    }
  }
  !/^- / && !/^[ \t]+[^ \t]/ { grp = "" }
  {
    t = $0; pos = 0
    while (match(t, /obs:[A-Za-z0-9_]+/)) {
      u = substr(t, RSTART + 4, RLENGTH - 4)
      pre = (pos + RSTART > 1) ? substr($0, pos + RSTART - 1, 1) : ""
      pos += RSTART + RLENGTH - 1; t = substr(t, RSTART + RLENGTH)
      if (pre ~ /[A-Za-z0-9_]/) continue
      if (u !~ /^[0-9a-f]+$/) { print "malformed citation: obs:" clean(u) > "/dev/stderr"; bad = 1; exit }
      if (grp == "") { print "obs:" u " is cited outside an Observations group" > "/dev/stderr"; bad = 1; exit }
      print "obs:" u "\t" grp
    }
  }
  END { exit bad ? 5 : 0 }
' "$SA_REQS" >"$SA_CITES_RAW" || fail_closed "the Sources section has an unclassifiable citation"
sort -u "$SA_CITES_RAW" >"$SA_CITES" || fail_closed "sort failed"
[ -s "$SA_CITES" ] || fail_closed "the Sources section cites no observation"

# Items: `id<TAB>date<TAB>path-or-line-number<TAB>kind`.
cut -f1 "$SA_CITES" | sed 's/^obs://' | sort -u >"$work/uids" || fail_closed "the UID list could not be built"
: >"$SA_ITEMS_RAW"
while IFS= read -r u; do
  set +f
  found=""
  for f in "$obs_dir"/entries/*-"$u".md "$obs_dir"/archive/*-"$u".md; do
    [ -f "$f" ] || [ -h "$f" ] || continue
    [ -z "$found" ] || {
      set -f
      fail_closed "obs:$u resolves to more than one fragment"
    }
    found=$f
  done
  set -f
  [ -n "$found" ] || fail_closed "obs:$u resolves to no fragment"
  [ ! -h "$found" ] || fail_closed "obs:$u's fragment is a symlink"
  [ -r "$found" ] || fail_closed "obs:$u's fragment is unreadable"
  b=${found##*/}
  d=${b%"${b#??????????}"}
  case $d in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) fail_closed "obs:$u's fragment name opens with no date" ;;
  esac
  printf '%s\t%s\t%s\tfragment\n' "obs:$u" "$d" "$found" >>"$SA_ITEMS_RAW" || fail_closed "the item list could not be written"
done <"$work/uids"

# Legacy rows, loaded in BEGIN so an empty index stays empty; each resolves to
# exactly one frozen-log line, never one another row already took.
awk -F'\t' '
  function clean(s) { gsub(/[^[:print:]]/, "", s); return s }
  BEGIN {
    n = split(ENVIRON["SA_CLASSES"], c, " ")
    for (i = 1; i <= n; i++) cls[c[i]] = 1
    f = ENVIRON["SA_LEGACY"]
    while ((r = (getline l < f)) > 0) {
      if (l ~ /^#/ || l ~ /^[ \t]*$/) continue
      nf = split(l, p, "\t")
      if (nf != 3 || p[1] !~ /^legacy:[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]:[a-z0-9-]+$/ || p[2] == "" || p[3] == "") {
        print "malformed legacy index row: " clean(p[1]) > "/dev/stderr"; bad = 1; exit
      }
      if (p[1] in seen) { print "duplicate legacy id: " clean(p[1]) > "/dev/stderr"; bad = 1; exit }
      seen[p[1]] = 1
      m = split(p[2], cc, ",")
      for (i = 1; i <= m; i++) if (!(cc[i] in cls)) { print "unknown class in " clean(p[1]) ": " clean(cc[i]) > "/dev/stderr"; bad = 1; exit }
      ids[++k] = p[1]; needle[k] = p[3]; dt[k] = substr(p[1], 8, 10); classes_of[k] = p[2]
    }
    if (r < 0) { print "the legacy index could not be read" > "/dev/stderr"; bad = 1; exit }
  }
  {
    for (j = 1; j <= k; j++)
      if (index($0, "- " dt[j] " ") == 1 && index($0, needle[j])) { hit[j]++; line[j] = FNR }
  }
  END {
    if (bad) exit 5
    for (j = 1; j <= k; j++) {
      if (hit[j] != 1) { print clean(ids[j]) " matches " hit[j] + 0 " frozen-log lines, not one" > "/dev/stderr"; exit 5 }
      if (line[j] in taken) { print clean(ids[j]) " resolves to the line " clean(taken[line[j]]) " already took" > "/dev/stderr"; exit 5 }
      taken[line[j]] = ids[j]
      print ids[j] "\t" dt[j] "\t" line[j] "\tlegacy" >> ENVIRON["SA_ITEMS_RAW"]
      m = split(classes_of[j], cc, ",")
      for (i = 1; i <= m; i++) print ids[j] "\t" cc[i] >> ENVIRON["SA_CITES_RAW"]
    }
  }
' "$SA_OPP" || fail_closed "the legacy index does not resolve"
sort -u "$SA_CITES_RAW" >"$SA_CITES" || fail_closed "sort failed"
sort "$SA_ITEMS_RAW" >"$SA_ITEMS" || fail_closed "sort failed"
awk -F'\t' -v asof="$as_of" '$2 > asof { print $1; late = 1 } END { exit late }' "$SA_ITEMS" >"$work/late" \
  || fail_closed "an item is dated after the as-of date ($(sed 's/[^ -~]//g' "$work/late" | head -n 1))"

# write_out <file>: the finished output, to --out (replaced only now) or stdout.
write_out() {
  if [ -z "$out" ]; then
    cat "$1" || exit 5
    return
  fi
  case $out in -*) out=./$out ;; esac
  [ ! -d "$out" ] || fail_closed "--out names a directory"
  tmp_out=$(mktemp "$out.XXXXXX") || fail_closed "cannot create a file beside --out"
  # mktemp creates the file private; the snapshot gets the mode a plain
  # redirect would.
  if ! chmod "$(printf '%o' $((0666 & ~$(umask))))" "$tmp_out" || ! cat "$1" >"$tmp_out" || ! mv -f "$tmp_out" "$out"; then
    fail_closed "cannot write --out"
  fi
  tmp_out=""
}

if [ "$mode" = class-map ]; then
  awk -F'\t' '
    FNR == NR { v = ($1 in c) ? c[$1] "," $2 : $2; c[$1] = v; next }
    { print $1 "\t" $2 "\t" c[$1] }
  ' "$SA_CITES" "$SA_ITEMS" >"$work/out" || fail_closed "the class map could not be written"
  write_out "$work/out"
  exit 0
fi

# Attribute each item: the named layer scripts and their tiers, or the manual
# row. The classes arrive through the item list's cites.
awk -F'\t' '
  function clean(s) { gsub(/[^[:print:]]/, "", s); return s }
  function stem(p) { sub(/^.*\//, "", p); sub(/\.sh$/, "", p); return p }
  function add(list, x,   n, a, i) {
    n = split(list, a, ",")
    for (i = 1; i <= n; i++) if (a[i] == x) return list
    return list == "" ? x : list "," x
  }
  # note_script(w): when w is a layer script, record its path and tier.
  function note_script(w) {
    if (!(w in tier)) return 0
    named = add(named, path[w]); tset = add(tset, tier[w])
    return 1
  }
  BEGIN {
    nt = split(ENVIRON["SA_TIERS"], tl, " "); for (i = 1; i <= nt; i++) tierok[tl[i]] = 1
    part = ENVIRON["SA_PART"]; man = ENVIRON["SA_MANUAL"]; cites = ENVIRON["SA_CITES"]
    getline hdr < part
    while ((r = (getline l < part)) > 0) {
      split(l, p, "\t"); s = stem(p[1])
      if (!(p[2] in tierok)) { print "partition tier outside the fixed set: " clean(p[1]) > "/dev/stderr"; bad = 1; exit }
      if (s in tier) { print "two layer scripts share the stem " clean(s) > "/dev/stderr"; bad = 1; exit }
      tier[s] = p[2]; path[s] = p[1]
    }
    if (r < 0) { print "the partition could not be read" > "/dev/stderr"; bad = 1; exit }
    while ((r = (getline l < cites)) > 0) {
      split(l, p, "\t"); v = (p[1] in cl) ? cl[p[1]] "," p[2] : p[2]; cl[p[1]] = v
    }
    if (r < 0) { bad = 1; exit }
    while ((r = (getline l < man)) > 0) {
      if (l ~ /^#/ || l ~ /^[ \t]*$/) continue
      nf = split(l, p, "\t")
      if (nf != 3 || p[2] == "" || p[3] == "" || p[1] !~ /^(obs:[0-9a-f]+|legacy:[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]:[a-z0-9-]+)$/) {
        print "malformed manual row: " clean(p[1]) > "/dev/stderr"; bad = 1; exit
      }
      if (p[1] in mt) { print "duplicate manual row: " clean(p[1]) > "/dev/stderr"; bad = 1; exit }
      m = split(p[2], tt, ","); v = ""
      for (i = 1; i <= m; i++) {
        if (!(tt[i] in tierok)) { print "unknown tier in " clean(p[1]) ": " clean(tt[i]) > "/dev/stderr"; bad = 1; exit }
        v = add(v, tt[i])
      }
      mt[p[1]] = v
    }
    if (r < 0) { print "the manual file could not be read" > "/dev/stderr"; bad = 1; exit }
    opp = ENVIRON["SA_OPP"]; ln = 0
    while ((r = (getline l < opp)) > 0) oppline[++ln] = l
    if (r < 0) { bad = 1; exit }
    rowsout = ENVIRON["SA_ROWS"]
  }
  {
    id = $1; txt = ""
    if ($4 == "legacy") txt = oppline[$3]
    else {
      while ((r = (getline l < $3)) > 0) txt = txt " " l
      if (r < 0) { print "a fragment could not be read: " clean(id) > "/dev/stderr"; bad = 1; exit }
      close($3)
    }
    named = ""; tset = ""; stray = ""; t = txt
    while (match(t, /[A-Za-z0-9_.\/-]*[A-Za-z0-9_-]\.sh/)) {
      w = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
      if (substr(t, 1, 1) ~ /[A-Za-z0-9_-]/) continue
      w = stem(w)
      if (note_script(w)) continue
      if (w ~ /^test-/ && note_script(substr(w, 6))) continue
      stray = add(stray, w ".sh")
    }
    t = txt; pos = 0
    while (match(t, /(scripts|githooks)\/[A-Za-z0-9_-]+/)) {
      w = substr(t, RSTART, RLENGTH)
      pre = (pos + RSTART > 1) ? substr(txt, pos + RSTART - 1, 1) : ""
      pos += RSTART + RLENGTH - 1; t = substr(t, RSTART + RLENGTH)
      if (pre ~ /[A-Za-z0-9_.-]/) continue
      if (substr(t, 1, 1) == "/" || substr(t, 1, 2) ~ /^[.][A-Za-z0-9_]/) continue
      note_script(stem(w))
    }
    t = txt
    while (match(t, /`[A-Za-z0-9_-]+`/)) {
      w = substr(t, RSTART + 1, RLENGTH - 2); t = substr(t, RSTART + RLENGTH)
      note_script(w)
    }
    if (named != "") {
      basis = "script"
      if (id in mt) { print "stale-manual\t" clean(id) > "/dev/stderr"; fails = 1 }
    } else if (id in mt) {
      basis = "manual"; tset = mt[id]
    } else {
      print "needs-manual\t" clean(id) > "/dev/stderr"; fails = 1; next
    }
    used[id] = 1
    if (stray != "") named = named (named == "" ? "" : ",") "not-in-layer:" clean(stray)
    print id "\t" $2 "\t" tset "\t" cl[id] "\t" basis "\t" (named == "" ? "-" : named) > rowsout
  }
  END {
    if (bad) exit 5
    for (id in mt) if (!(id in used)) print "orphan-manual\t" clean(id) > (ENVIRON["SA_ROWS"] ".orphans")
    if (fails) exit 1
  }
' "$SA_ITEMS"
rc=$?
if [ -s "$SA_ROWS.orphans" ]; then
  sort "$SA_ROWS.orphans" >&2
  [ "$rc" -ne 0 ] || rc=1
fi
case $rc in
  0) ;;
  1)
    printf '%s\n' "$me: attribution incomplete; see the needs-manual, stale-manual and orphan-manual lines above" >&2
    exit 1
    ;;
  *) fail_closed "an input is malformed or the attribution pass failed" ;;
esac

if [ "$mode" = rows ]; then
  write_out "$SA_ROWS"
  exit 0
fi

awk -F'\t' -v asof="$as_of" '
  BEGIN {
    nc = split(ENVIRON["SA_CLASSES"], c, " ")
    nt = split(ENVIRON["SA_TIERS"], tl, " ")
  }
  {
    rows[++nr] = $0; nitems++
    if ($5 == "manual") nmanual++
    nrow_tiers = split($3, ts, ","); nk = split($4, ks, ",")
    for (i = 1; i <= nrow_tiers; i++) {
      tieritems[ts[i]]++
      for (j = 1; j <= nk; j++) cell[ts[i], ks[j]]++
    }
    for (j = 1; j <= nk; j++) classitems[ks[j]]++
  }
  END {
    print "# Substrate pain matrix, as of " asof
    print ""
    print "Generated by `scripts/substrate-attribute.sh`; do not edit by hand. Regenerate on an"
    print "unchanged tree with:"
    print ""
    print "```sh"
    print "mise run substrate:attribute -- --as-of " asof " --out docs/substrate/pain-matrix-" asof ".md"
    print "```"
    print ""
    print "The mined set is every observation the universal-binary bundle cites under its"
    print "Sources (fragment UIDs) plus the frozen legacy-log lines listed in"
    print "`docs/substrate/legacy-lines.tsv`. Each item counts once in every cell of its"
    print "tiers crossed with its classes, so a row or column does not sum to the item"
    print "count. Tiers come from the partition (the `substrate:partition` task) through"
    print "the scripts an item names; an item naming none is attributed by"
    print "`docs/substrate/manual-attribution.tsv`. The script header defines both rules."
    print ""
    print "## Summary"
    print ""
    print "| measure | value |"
    print "| --- | --- |"
    print "| items attributed | " nitems " |"
    print "| attributed through a named script | " nitems - nmanual " |"
    print "| attributed by the manual file | " nmanual + 0 " |"
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
      print r " " (tieritems[tl[i]] + 0) " |"
    }
    r = "| any tier |"
    for (j = 1; j <= nc; j++) r = r " " (classitems[c[j]] + 0) " |"
    print r " " nitems " |"
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
' "$SA_ROWS" >"$work/out" || fail_closed "the snapshot could not be rendered"
write_out "$work/out"
