#!/bin/bash
# Tests for scripts/mc-radar.sh — same-file and same-line overlap predicted
# across branches, merge order from the whole graph across repositories,
# stack retargets on a base merge, and the watcher (mission-control
# REQ-M1.5; D-25, D-27).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-radar.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d) || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$tmp/work]
program_alpha_spec_root: $repo
program_alpha_home: $tmp/mchome
EOF

g() { git -C "$tmp/work" -c user.name=t -c user.email=t@example.invalid "$@" >/dev/null 2>&1; }
git init -q -b main "$tmp/work" 2>/dev/null || {
  git init -q "$tmp/work"
  g checkout -b main
}
seq 1 40 >"$tmp/work/app.txt"
printf 'x\n' >"$tmp/work/other.txt"
g add -A
g commit -m base
edit() { # edit <branch> <from> <line> <text>
  g checkout -q -b "$1" "$2"
  sed -i.bak "$3s/.*/$4/" "$tmp/work/app.txt" && rm -f "$tmp/work/app.txt.bak"
  g commit -am "$1"
}
edit feat-a main 10 alpha
edit feat-b main 10 beta
edit feat-c main 30 gamma
edit feat-d feat-a 20 delta
g checkout -q -b feat-e main
printf 'y\n' >"$tmp/work/other.txt"
g commit -am e
# An insertion after line 10, a new file, a deletion, and a binary edit.
g checkout -q -b feat-ins main
sed -i.bak '10a\
inserted' "$tmp/work/app.txt" && rm -f "$tmp/work/app.txt.bak"
g commit -am ins
g checkout -q -b feat-new main
printf 'new\n' >"$tmp/work/new.txt"
g add new.txt
g commit -m new
g checkout -q -b feat-new2 main
printf 'other new\n' >"$tmp/work/new.txt"
g add new.txt
g commit -m new2
g checkout -q -b feat-del main
sed -i.bak '10d' "$tmp/work/app.txt" && rm -f "$tmp/work/app.txt.bak"
g commit -am del
g checkout -q main
printf '\000\001' >"$tmp/work/blob.bin"
g add blob.bin
g commit -m blob
g checkout -q -b bin-a main
printf '\000\002' >"$tmp/work/blob.bin"
g commit -am bin-a
g checkout -q -b bin-b main
printf '\000\003' >"$tmp/work/blob.bin"
g commit -am bin-b
# A deleted line reading like a file header must not be taken for one.
g checkout -q main
printf '%s\n' '-- a/spoofed.sql' 1 2 3 4 5 6 7 >"$tmp/work/s.sql"
g add s.sql
g commit -m sql
g checkout -q -b sql-a main
sed -i.bak '8s/.*/changed/' "$tmp/work/s.sql" && rm -f "$tmp/work/s.sql.bak"
g commit -am sql-a
g checkout -q -b sql-b main
sed -i.bak '1d; 8s/.*/other/' "$tmp/work/s.sql" && rm -f "$tmp/work/s.sql.bak"
g commit -am sql-b
g checkout -q --orphan pages
g rm -rq .
printf 'site\n' >"$tmp/work/index.html"
g add index.html
g commit -m pages
g checkout -q main

# ---------------------------------------------------------------------------
# Same-file and same-line prediction from two fixture branches.
# ---------------------------------------------------------------------------
mc_run mc-radar.sh overlap --checkout "$tmp/work" --base main feat-a feat-b
expect_rc "overlap" 0
expect_out "the radar flags a same-line overlap from two fixture branches" "same-line${tab}feat-a${tab}feat-b${tab}app.txt${tab}10-10"
expect_out "and the same file" "same-file${tab}feat-a${tab}feat-b${tab}app.txt"
mc_run mc-radar.sh overlap --checkout "$tmp/work" --base main feat-a feat-c
expect_out "two branches on one file, far apart, share the file" "same-file${tab}feat-a${tab}feat-c${tab}app.txt"
expect_no_out "and not a line" "same-line"
mc_run mc-radar.sh overlap --checkout "$tmp/work" --base main feat-a feat-e
expect_rc "a disjoint pair" 0
expect_eq "branches on different files do not overlap" ""
mc_run mc-radar.sh overlap --checkout "$tmp/work" --base main feat-ins feat-a
expect_out "an insertion counts as the line it lands at" "same-line${tab}feat-ins${tab}feat-a${tab}app.txt${tab}10-10"
mc_run mc-radar.sh overlap --checkout "$tmp/work" --base main feat-del feat-a
expect_out "a deletion overlaps the edit of its line" "same-line${tab}feat-del${tab}feat-a${tab}app.txt${tab}10-10"
mc_run mc-radar.sh overlap --checkout "$tmp/work" --base main feat-new feat-new2
expect_out "two branches adding the same file share it" "same-file${tab}feat-new${tab}feat-new2${tab}new.txt"
mc_run mc-radar.sh overlap --checkout "$tmp/work" --base main bin-a bin-b
expect_out "a binary file both branches change is a same-file overlap" "same-file${tab}bin-a${tab}bin-b${tab}blob.bin"
mc_run mc-radar.sh overlap --checkout "$tmp/work" --base main sql-a sql-b
expect_out "a deleted line reading like a header is not one" "same-line${tab}sql-a${tab}sql-b${tab}s.sql${tab}8-8"
expect_no_out "and plants no path" "spoofed"
mc_run mc-radar.sh overlap --checkout "$tmp/work" --base main feat-b feat-a pages
expect_rc "a branch with no shared history is skipped, not fatal" 0
expect_err "with a warning" "skipping pages: no merge base"
expect_out "pairs keep the argument order" "same-line${tab}feat-b${tab}feat-a${tab}app.txt"
mc_run mc-radar.sh overlap --checkout "$tmp/work" --base main feat-a no-such
expect_rc "an unknown branch fails" 1
mc_run mc-radar.sh overlap --checkout "$tmp/work" --base main feat-a
expect_rc "one branch is a usage error" 2
mc_run mc-radar.sh overlap --checkout "$tmp/work" --base main feat-a --upload-pack=x
expect_rc "an option-looking branch is refused" 2

# ---------------------------------------------------------------------------
# REQ-M1.5: merge order across two repositories from the whole graph, and a
# retarget for a stacked branch on its base's merge.
# ---------------------------------------------------------------------------
cat >"$tmp/graph" <<'EOF'
# format: 1
unit	web	feat-d	feat-a	-
unit	web	feat-a	main	api:feat-x
unit	api	feat-x	main	-
unit	api	feat-y	main	-
EOF
mc_run mc-radar.sh order --graph "$tmp/graph"
expect_rc "order" 0
expect_eq "REQ-M1.5: the order spans both repositories, dependencies and stack bases first" \
  "order${tab}1${tab}api${tab}feat-x
order${tab}2${tab}web${tab}feat-a
order${tab}3${tab}web${tab}feat-d
order${tab}4${tab}api${tab}feat-y"
mc_run mc-radar.sh retarget --graph "$tmp/graph" --merged web:feat-a
expect_rc "retarget" 0
expect_eq "REQ-M1.5: the stacked branch moves onto its base's own base" "retarget${tab}web${tab}feat-d${tab}feat-a${tab}main"
mc_run mc-radar.sh retarget --graph "$tmp/graph" --merged api:feat-x
expect_eq "a merge with nothing stacked on it retargets nothing" ""
mc_run mc-radar.sh retarget --graph "$tmp/graph" --merged web:nope
expect_rc "an unknown merged unit fails" 1
printf 'unit\tapi\tfeat-y\tmain\tapi:feat-z\nunit\tapi\tfeat-z\tmain\tapi:feat-y\n' >>"$tmp/graph"
sed -i.bak '/feat-y\tmain\t-$/d' "$tmp/graph"
mc_run mc-radar.sh order --graph "$tmp/graph"
expect_rc "a cycle fails" 1
expect_err "named" "a cycle among"
printf '# format: 1\nunit\tapi\tfeat-y\tmain\tapi:gone\n' >"$tmp/graph"
mc_run mc-radar.sh order --graph "$tmp/graph"
expect_rc "an unknown dependency fails" 1
printf 'unit\tapi\tfeat-y\tmain\t-\n' >"$tmp/graph"
mc_run mc-radar.sh order --graph "$tmp/graph"
expect_rc "a graph with no format line fails" 1
printf '# format: 1\nunit\tapi\tfeat-y\tmain\t-\nunit\tapi\tfeat-y\tdev\t-\n' >"$tmp/graph"
mc_run mc-radar.sh order --graph "$tmp/graph"
expect_rc "a duplicate unit fails" 1
expect_err "named" "duplicate unit api:feat-y"

# ---------------------------------------------------------------------------
# watch: one event per same-line overlap across the origin branches.
# ---------------------------------------------------------------------------
git clone -q "$tmp/work" "$tmp/clone" 2>/dev/null
sed -i.bak "s|^program_alpha_repositories: .*|program_alpha_repositories: [$tmp/clone]|" "$tracked"
OUT=$(mc_env env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-radar.sh" 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "the watcher runs with no arguments under the runner" 0
expect_out "an overlap is announced" "announced${tab}conflict-predicted${tab}conflict-"
expect_err "the orphan branch skipped, not fatal" "skipping origin/pages"
mc_run mc-event.sh list --program alpha
expect_rc "the event store reads" 0
case $OUT in
  *"clone:origin/feat-a+origin/feat-b app.txt lines 10-10"* | *"clone:origin/feat-b+origin/feat-a app.txt lines 10-10"*)
    ok "the overlap lands in the event store, its pair and lines in the text"
    ;;
  *) fail "no stored conflict-predicted event for feat-a and feat-b: $OUT" ;;
esac
expect_no_out "no event for branches that only share the file" "feat-c"
mc_run mc-radar.sh watch --program alpha
expect_rc "a second pass" 0
expect_eq "an announced overlap is not announced again" ""

if [ "$failures" -ne 0 ]; then
  echo "test-mc-radar: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-radar: all passed"
