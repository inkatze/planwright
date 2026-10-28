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
g checkout -q main

# ---------------------------------------------------------------------------
# Same-file and same-line prediction from two fixture branches.
# ---------------------------------------------------------------------------
mc_run mc-radar.sh overlap --repo "$tmp/work" --base main feat-a feat-b
expect_rc "overlap" 0
expect_out "the radar flags a same-line overlap from two fixture branches" "same-line${tab}feat-a${tab}feat-b${tab}app.txt${tab}10-10"
expect_out "and the same file" "same-file${tab}feat-a${tab}feat-b${tab}app.txt"
mc_run mc-radar.sh overlap --repo "$tmp/work" --base main feat-a feat-c
expect_out "two branches on one file, far apart, share the file" "same-file${tab}feat-a${tab}feat-c${tab}app.txt"
expect_no_out "and not a line" "same-line"
mc_run mc-radar.sh overlap --repo "$tmp/work" --base main feat-a feat-e
expect_eq "branches on different files do not overlap" ""
mc_run mc-radar.sh overlap --repo "$tmp/work" --base main feat-a no-such
expect_rc "an unknown branch fails" 1
mc_run mc-radar.sh overlap --repo "$tmp/work" --base main feat-a
expect_rc "one branch is a usage error" 2
mc_run mc-radar.sh overlap --repo "$tmp/work" --base main feat-a --upload-pack=x
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

# ---------------------------------------------------------------------------
# watch: one event per same-line overlap across the origin branches.
# ---------------------------------------------------------------------------
git clone -q "$tmp/work" "$tmp/clone" 2>/dev/null
sed -i.bak "s|^program_alpha_repositories: .*|program_alpha_repositories: [$tmp/clone]|" "$tracked"
OUT=$(mc_env env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-radar.sh" 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "the watcher runs with no arguments under the runner" 0
expect_out "the overlap is an event" "event${tab}conflict-predicted${tab}clone:origin/feat-a+origin/feat-b${tab}app.txt lines 10-10"
expect_no_out "no event for branches that only share the file" "feat-c"
mc_run mc-radar.sh watch --program alpha
expect_eq "an announced overlap is not announced again" ""

if [ "$failures" -ne 0 ]; then
  echo "test-mc-radar: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-radar: all passed"
