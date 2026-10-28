#!/usr/bin/env bash
# mc-radar.sh — the conflict-radar duty: same-file and same-line overlap
# predicted across a program's branches, merge order from the whole
# dependency graph, and the stack retargets a base merge calls for.
#
# `mc-radar.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-radar
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2

help_text() {
  cat <<'HELP'
mc-radar.sh — the conflict-radar duty: same-file and same-line overlap
predicted across a program's branches, merge order from the whole
dependency graph, and the stack retargets a base merge calls for.

Usage:
  mc-radar.sh overlap --repo <dir> --base <ref> <branch> <branch>...
      each branch's change against its merge base with <ref>, compared
      pairwise in base-side lines (an insertion counts as the line it
      lands at), one line per overlap, pairs in argument order:
        same-file<TAB><a><TAB><b><TAB><path>
        same-line<TAB><a><TAB><b><TAB><path><TAB><first>-<last>
      a path both branches touch gets a same-file line, and a same-line
      line too when their changed line ranges meet
  mc-radar.sh order --graph <file>
      the merge order across every repository in the graph:
        order<TAB><n><TAB><repo><TAB><branch>
      a unit after the unit whose branch is its base and after every
      dependency, ties in file order; a cycle, an unknown dependency or a
      duplicate unit fails, named
  mc-radar.sh retarget --graph <file> --merged <repo>:<branch>
      the units stacked on the merged branch, each to move onto the merged
      unit's own base:
        retarget<TAB><repo><TAB><branch><TAB><old base><TAB><new base>
  mc-radar.sh watch [--program <p>]
      the duty's watcher: in each of the program's repositories, every
      origin branch but the default compared against the default (the
      first 50 by name), one event per same-line overlap not seen before:
        event<TAB>conflict-predicted<TAB><repo>:<a>+<b><TAB><path> lines <first>-<last>
      the program from PLANWRIGHT_MC_PROGRAM when --program is absent

THE GRAPH file opens with "# format: 1"; blank lines and `#` lines are
skipped; every other line is
  unit<TAB><repo><TAB><branch><TAB><base><TAB><dependencies>
<repo> a name the program uses for the repository, <dependencies> `-` or
a comma list of <repo>:<branch> naming other units in any repository.

Exit codes: 0 done; 1 a git read that failed, an invalid graph or an
unknown merged unit; 2 usage; 3 the program is not configured (watch).

Portable bash 3.2 / BSD tooling.
HELP
}

usage() {
  mc_usage_fail "usage: mc-radar.sh overlap --repo <dir> --base <ref> <branch>... | order --graph <file> | retarget --graph <file> --merged <repo>:<branch> | watch [--program <p>]"
}

case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
if [ $# -eq 0 ] && [ -n "${PLANWRIGHT_MC_PROGRAM:-}" ]; then
  set -- watch
fi
[ $# -ge 1 ] || usage
verb=$1
shift
program=""
repo=""
base=""
graph=""
merged=""
branches=()
while [ $# -gt 0 ]; do
  case $1 in
    --program | --repo | --base | --graph | --merged)
      [ $# -ge 2 ] || usage
      mc_valid_text "$2" || mc_usage_fail "$1 takes text with no control byte"
      case $1 in
        --program) program=$2 ;;
        --repo) repo=$2 ;;
        --base) base=$2 ;;
        --graph) graph=$2 ;;
        --merged) merged=$2 ;;
      esac
      shift 2
      ;;
    -*) usage ;;
    *)
      branches+=("$1")
      shift
      ;;
  esac
done

valid_ref() {
  case $1 in
    "" | -* | *..* | *[!A-Za-z0-9._/@-]*) return 1 ;;
  esac
  [ "${#1}" -le 200 ]
}

# hunks <repo> <base> <branch>: <branch><TAB><path><TAB><first><TAB><last>
# per changed base-side range.
hunks() {
  hk_mb=$(git -C "$1" merge-base "$2" "$3" 2>/dev/null) || {
    printf '%s\n' "$prog: no merge base of $(sanitize_printable "$3") and $(sanitize_printable "$2")" >&2
    return 1
  }
  git -C "$1" -c core.quotePath=false diff -U0 --no-color --no-ext-diff --no-renames --no-textconv "$hk_mb" "$3" -- 2>/dev/null \
    | B=$3 awk '
      /^--- / { p = substr($0, 5); if (p ~ /^a\//) p = substr(p, 3); next }
      /^\+\+\+ / { q = substr($0, 5); if (q ~ /^b\//) q = substr(q, 3); if (p == "/dev/null") p = q; next }
      /^@@ / {
        split($2, o, ","); a = substr(o[1], 2) + 0; n = (2 in o) ? o[2] + 0 : 1
        if (n == 0) { lo = a; hi = a } else { lo = a; hi = a + n - 1 }
        if (lo < 1) lo = 1
        if (hi < lo) hi = lo
        print ENVIRON["B"] "\t" p "\t" lo "\t" hi
      }'
}

# overlap <repo> <base> <branch>...
overlap() {
  ov_repo=$1
  ov_base=$2
  shift 2
  ov_all=""
  for ov_b in "$@"; do
    ov_h=$(hunks "$ov_repo" "$ov_base" "$ov_b") || return 1
    [ -z "$ov_h" ] || ov_all="$ov_all$ov_h
"
  done
  printf '%s' "$ov_all" | awk -F '\t' '
    { if (!($1 in rank)) { rank[$1] = ++nb; name[nb] = $1 }
      n++; B[n] = $1; P[n] = $2; L[n] = $3 + 0; H[n] = $4 + 0
      if (!(($1, $2) in has)) { has[$1, $2] = 1; files[$2] = files[$2] "\n" $1 } }
    END {
      for (i = 1; i <= nb; i++) for (j = i + 1; j <= nb; j++) {
        a = name[i]; b = name[j]
        for (f in files) if (((a, f) in has) && ((b, f) in has)) {
          print "same-file\t" a "\t" b "\t" f
          lo = 0; hi = 0
          for (x = 1; x <= n; x++) if (B[x] == a && P[x] == f)
            for (y = 1; y <= n; y++) if (B[y] == b && P[y] == f && L[x] <= H[y] && L[y] <= H[x]) {
              l = (L[x] > L[y]) ? L[x] : L[y]; h = (H[x] < H[y]) ? H[x] : H[y]
              if (!lo || l < lo) lo = l
              if (h > hi) hi = h
            }
          if (lo) print "same-line\t" a "\t" b "\t" f "\t" lo "-" hi
        }
      }
    }' | sort -t '	' -k1,1r -k2,2 -k3,3 -k4,4
}

# load_graph <file>: the graph's unit lines, checked.
load_graph() {
  [ -r "$1" ] || mc_fail "the graph is unreadable: $(sanitize_printable "$1")"
  awk -F '\t' '
    function bad(why) { printf "mc-radar: %s:%d: %s\n", FILENAME, FNR, why > "/dev/stderr"; err = 1 }
    NR == 1 { if ($0 != "# format: 1") { bad("unknown format (want \"# format: 1\")"); exit } ; next }
    /^[ ]*$/ || /^#/ { next }
    {
      if ($1 != "unit" || NF != 5) { bad("want unit<TAB><repo><TAB><branch><TAB><base><TAB><dependencies>"); next }
      k = $2 ":" $3
      if (k in seen) { bad("duplicate unit " k); next }
      seen[k] = 1; print $2 "\t" $3 "\t" $4 "\t" $5
    }
    END { if (NR == 0) { printf "mc-radar: %s: empty, with no format line\n", FILENAME > "/dev/stderr"; exit 1 } ; exit err }' "$1"
}

case $verb in
  overlap)
    [ -n "$repo" ] && [ -n "$base" ] && [ "${#branches[@]}" -ge 2 ] || usage
    [ -d "$repo" ] || mc_fail "no repository at $(sanitize_printable "$repo")"
    valid_ref "$base" || mc_usage_fail "invalid base ref"
    for b in "${branches[@]}"; do valid_ref "$b" || mc_usage_fail "invalid branch '$(sanitize_printable "$b")'"; done
    overlap "$repo" "$base" "${branches[@]}"
    ;;
  order | retarget)
    [ -n "$graph" ] && [ "${#branches[@]}" -eq 0 ] || usage
    units=$(load_graph "$graph") || exit 1
    if [ "$verb" = retarget ]; then
      case $merged in
        *:?*) ;;
        *) mc_usage_fail "--merged takes <repo>:<branch>" ;;
      esac
      printf '%s\n' "$units" | M=$merged awk -F '\t' '
        { u[NR] = $0 }
        $1 ":" $2 == ENVIRON["M"] { found = 1; mrepo = $1; mbranch = $2; mbase = $3 }
        END {
          if (!found) { print "mc-radar: the merged unit " ENVIRON["M"] " is not in the graph" > "/dev/stderr"; exit 1 }
          for (i = 1; i <= NR; i++) { split(u[i], f, "\t"); if (f[1] == mrepo && f[3] == mbranch) print "retarget\t" f[1] "\t" f[2] "\t" mbranch "\t" mbase }
        }'
      exit $?
    fi
    printf '%s\n' "$units" | awk -F '\t' '
      { n++; R[n] = $1; Bn[n] = $2; Ba[n] = $3; D[n] = $4; id[$1 ":" $2] = n }
      END {
        for (i = 1; i <= n; i++) {
          k = 0
          if ((R[i] ":" Ba[i]) in id) pre[i, ++k] = id[R[i] ":" Ba[i]]
          if (D[i] != "-") {
            m = split(D[i], d, ",")
            for (j = 1; j <= m; j++) {
              if (!(d[j] in id)) { print "mc-radar: unit " R[i] ":" Bn[i] " depends on unknown unit " d[j] > "/dev/stderr"; exit 1 }
              pre[i, ++k] = id[d[j]]
            }
          }
          np[i] = k
        }
        for (placed = 0; placed < n; ) {
          moved = 0
          for (i = 1; i <= n; i++) {
            if (done[i]) continue
            ok = 1
            for (j = 1; j <= np[i]; j++) if (!done[pre[i, j]]) ok = 0
            if (ok) { done[i] = 1; placed++; moved = 1; print "order\t" placed "\t" R[i] "\t" Bn[i]; break }
          }
          if (!moved) {
            left = ""
            for (i = 1; i <= n; i++) if (!done[i]) left = left " " R[i] ":" Bn[i]
            print "mc-radar: a cycle among" left > "/dev/stderr"; exit 1
          }
        }
      }'
    ;;
  watch)
    [ "${#branches[@]}" -eq 0 ] || usage
    [ -n "$program" ] || program=${PLANWRIGHT_MC_PROGRAM:-}
    [ -n "$program" ] || usage
    mc_require_program "$program"
    runtime=$(mc_runtime "$program") || mc_fail "cannot resolve the runtime directory"
    seen="$runtime/radar-announced"
    [ -f "$seen" ] || : >"$seen"
    repos=$(/bin/bash "$script_dir/mc-program.sh" get "$program" repositories) || mc_fail "the repositories of program $program do not resolve"
    found=""
    rc=0
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      def=$(git -C "$r" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) || continue
      def=${def#refs/remotes/}
      list=$(git -C "$r" for-each-ref --format='%(refname:short)' refs/remotes/origin/ 2>/dev/null | awk -v d="$def" '$0 != d && $0 != "origin/HEAD" && $0 != "origin"' | sort | head -n 50)
      set --
      while IFS= read -r b; do
        valid_ref "$b" && set -- "$@" "$b"
      done <<EOF
$list
EOF
      [ $# -ge 2 ] || continue
      lines=$(overlap "$r" "$def" "$@") || {
        rc=1
        continue
      }
      name=${r%/}
      name=${name##*/}
      found="$found$(printf '%s\n' "$lines" | N=$name awk -F '\t' '$1 == "same-line" { print ENVIRON["N"] ":" $2 "+" $3 "\t" $4 " lines " $5 }')
"
    done <<EOF
$repos
EOF
    new=$(printf '%s' "$found" | awk 'NF' | awk 'FILENAME == ARGV[1] { s[$0] = 1; next } !($0 in s)' "$seen" -)
    if [ -n "$new" ]; then
      printf '%s\n' "$new" | awk -F '\t' '{ print "event\tconflict-predicted\t" $1 "\t" $2 }'
      { cat "$seen" && printf '%s\n' "$new"; } | tail -n 500 | mc_write "$seen" || mc_fail "cannot record the announced overlaps"
    fi
    exit "$rc"
    ;;
  *) usage ;;
esac
