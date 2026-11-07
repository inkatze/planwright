#!/bin/bash
# Tests for scripts/mc-merge-ready.sh — the pull requests ready to merge: a
# non-draft, mergeable, green pull request with no open thread whose
# readiness check passes at its head, listed with its checked merge command
# in the repository's merge method, announced once per head and listed again
# on every read until it merges or changes.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-merge-ready.sh
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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-merge-ready.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_home: $tmp/mchome
program_alpha_sources: {code-state: forge:snapshot}
EOF
mkdir -p "$tmp/mchome"

# The scripts under test run from a copy whose readiness check is a stub: it
# answers from $tmp/verdict.<n> (ready, not-ready, or anything else for a
# check that could not run) and logs each call.
pw="$tmp/pw"
mkdir -p "$pw"
cp -R "$repo_root/scripts" "$pw/scripts"
cat >"$pw/scripts/mc-readiness.sh" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$tmp/check.calls"
n=""
while [ \$# -gt 0 ]; do [ "\$1" = --pr ] && n=\$2; shift; done
case \$(cat "$tmp/verdict.\$n" 2>/dev/null) in
  ready) printf 'ready\t%s\n' "\$(cat "$tmp/head.\$n")"; exit 0 ;;
  not-ready) printf 'not-ready\t-\nfail\tcheck\tci is PENDING\n'; exit 4 ;;
esac
exit 1
EOF
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/gh.calls"
case "\$1 \$2" in
  "repo view") m=\$(cat "$tmp/method" 2>/dev/null) && [ -n "\$m" ] && printf '%s\n' "\$m" && exit 0 ;;
esac
exit 1
EOF
chmod +x "$tmp/bin/gh"
printf 'SQUASH\n' >"$tmp/method"

run() { # run <args...>: the copy's mc-merge-ready.sh against the fixture
  OUT=$(PATH="$tmp/bin:$PATH" mc_env /bin/bash "$pw/scripts/mc-merge-ready.sh" "$@" 2>"$tmp/stderr")
  RC=$?
  ERR=$(cat "$tmp/stderr")
}
calls() { awk 'END { print NR + 0 }' "$tmp/check.calls" 2>/dev/null || echo 0; }

H=1111111111111111111111111111111111111111
J=2222222222222222222222222222222222222222
snapdir="$fleet/mission-control/alpha/snapshots"
mkdir -p "$snapdir"
now=$(date +%s)
row() { # row <n> <head> <draft> <mergeable> <threads> <checks>
  printf 'pr\tacme/web\t%s\t%s\t%s\t%s\tNONE\t%s\t%s\t0\t0\tp%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$1"
}
snap() { # snap <head of #7>
  printf 'format\t1\nsource\tforge\ntaken\t%s\n' "$now"
  row 7 "$1" false MERGEABLE 0 SUCCESS
  row 8 "$H" true MERGEABLE 0 SUCCESS
  row 9 "$H" false CONFLICTING 0 SUCCESS
  row 10 "$H" false MERGEABLE 2 SUCCESS
  row 11 "$H" false MERGEABLE 0 FAILURE
  row 12 "$H" false MERGEABLE 0 SUCCESS
}
snap "$H" >"$snapdir/forge"
for n in 7 8 9 10 11 12; do printf '%s\n' "$H" >"$tmp/head.$n"; done
printf 'ready\n' >"$tmp/verdict.7"
printf 'not-ready\n' >"$tmp/verdict.12"
cmd7="gh pr merge 7 --repo acme/web --squash --match-head-commit $H"

# ---------------------------------------------------------------------------
# list: the readiness check decides, and only a candidate is checked.
# ---------------------------------------------------------------------------
run list --program alpha
expect_rc "list" 0
expect_eq "only the candidate whose check passes is ready, with its checked merge command" "ready${tab}acme/web#7${tab}$H${tab}$cmd7"
checked=$(cut -d' ' -f1-7 "$tmp/check.calls" | sort | tr '\n' '|')
if [ "$checked" = "check --program alpha --repo acme/web --pr 12|check --program alpha --repo acme/web --pr 7|" ]; then
  ok "a draft, a conflict, an open thread and red checks are never checked"
else
  fail "checked: $checked"
fi

before=$(calls)
run list --program alpha
expect_eq "a second read lists the ready one again" "ready${tab}acme/web#7${tab}$H${tab}$cmd7"
if [ "$(calls)" = "$before" ]; then ok "an unchanged state is not checked again"; else fail "an unchanged state was checked again"; fi

run count --program alpha
expect_eq "count reads the last verdicts, with no forge read" "1"

run list --program alpha --as-status
expect_eq "as status lines" "decision${tab}Ready to merge: acme/web#7 at $(printf '%s' "$H" | cut -c1-12), run: $cmd7"
st=$(printf '%s\n' "$OUT" | mc_env /bin/bash "$repo_root/scripts/mc-inbox.sh" status 2>/dev/null)
case $st in
  Decisions*"- Ready to merge: acme/web#7"*Landed*) ok "the first-turn status lists it under Decisions" ;;
  *) fail "status form: $st" ;;
esac

# A not-ready verdict is checked again once it is old enough.
before=$(calls)
run list --program alpha --now $((now + 1801))
if [ "$(calls)" -gt "$before" ] && grep -q -- '--pr 12' "$tmp/check.calls"; then ok "a not-ready verdict is re-checked after half an hour"; else fail "a stale not-ready verdict was trusted"; fi
printf 'ready\n' >"$tmp/verdict.12"
run list --program alpha --now $((now + 3700))
expect_out "one that became ready without a head move is found" "ready${tab}acme/web#12${tab}$H"
printf 'not-ready\n' >"$tmp/verdict.12"
snap "$H" | awk -F '\t' '!($1 == "pr" && $3 == "12")' >"$snapdir/forge"

# ---------------------------------------------------------------------------
# watch: one merge-ready event per new ready head.
# ---------------------------------------------------------------------------
OUT=$(PATH="$tmp/bin:$PATH" mc_env env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$pw/scripts/mc-merge-ready.sh" 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "the watcher runs with no arguments under the runner" 0
expect_eq "it announces the ready pull request" "announced${tab}merge-ready${tab}acme:web:7"
mc_run mc-event.sh list --program alpha
expect_out "the event carries the merge command" "merge-ready${tab}acme:web:7${tab}acme/web#7 is ready to merge: $cmd7"
run watch --program alpha
expect_eq "an announced head is not announced again" ""
run list --program alpha
expect_eq "and is still listed for every bring-up" "ready${tab}acme/web#7${tab}$H${tab}$cmd7"

# A new head is checked and announced afresh.
snap "$J" | awk -F '\t' '!($1 == "pr" && $3 == "12")' >"$snapdir/forge"
printf '%s\n' "$J" >"$tmp/head.7"
before=$(calls)
run watch --program alpha
if [ "$(calls)" -gt "$before" ]; then ok "a moved head is checked again"; else fail "a moved head was not checked"; fi
expect_eq "and announced again" "announced${tab}merge-ready${tab}acme:web:7"

# The repository's merge method decides the flag.
printf 'REBASE\n' >"$tmp/method"
snap "$H" | awk -F '\t' '!($1 == "pr" && $3 == "12")' >"$snapdir/forge"
printf '%s\n' "$H" >"$tmp/head.7"
run list --program alpha
expect_out "a rebase repository merges by rebase" "gh pr merge 7 --repo acme/web --rebase --match-head-commit $H"

# A merge method that cannot be read leaves the pull request unknown, never
# offered without its method, and read again next time.
: >"$tmp/method"
snap "$J" | awk -F '\t' '!($1 == "pr" && $3 == "12")' >"$snapdir/forge"
printf '%s\n' "$J" >"$tmp/head.7"
run list --program alpha
expect_rc "an unreadable merge method fails the read" 1
expect_eq "named, with no command" "unknown${tab}acme/web#7${tab}the merge method of acme/web could not be read"
printf 'SQUASH\n' >"$tmp/method"
run list --program alpha
expect_eq "read again next time" "ready${tab}acme/web#7${tab}$J${tab}gh pr merge 7 --repo acme/web --squash --match-head-commit $J"

# A check that cannot run is unknown, not cached, and fails the watcher run.
snap "$H" | awk -F '\t' '!($1 == "pr" && $3 == "12")' >"$snapdir/forge"
printf 'broken\n' >"$tmp/verdict.7"
run watch --program alpha
expect_rc "a check that could not run fails the watcher run" 1
expect_eq "and announces nothing" ""
run list --program alpha
expect_eq "it is named unknown" "unknown${tab}acme/web#7${tab}the readiness check could not run (exit 1)"
printf 'ready\n' >"$tmp/verdict.7"
printf '%s\n' "$H" >"$tmp/head.7"
run list --program alpha
expect_eq "and checked again next time" "ready${tab}acme/web#7${tab}$H${tab}$cmd7"

# Merged: gone from the snapshot, gone from the list and the count.
printf 'format\t1\nsource\tforge\ntaken\t%s\n' "$now" >"$snapdir/forge"
run list --program alpha
expect_rc "an empty snapshot" 0
expect_eq "lists nothing" ""
run count --program alpha
expect_eq "and counts none" "0"

# A stale snapshot is named, never read as nothing waiting; the watcher stays
# quiet on it.
{
  printf 'format\t1\nsource\tforge\ntaken\t%s\n' $((now - 86400))
  row 7 "$H" false MERGEABLE 0 SUCCESS
} >"$snapdir/forge"
run list --program alpha
expect_rc "a stale snapshot fails the list" 1
expect_eq "named" "unknown${tab}-${tab}the code-state snapshot is stale"
run watch --program alpha
expect_rc "the watcher waits for a fresh one" 0
expect_eq "quietly" ""

sed -i.bak 's/^program_alpha_sources: .*/program_alpha_sources: {work-items: specs:record}/' "$tracked"
run list --program alpha
expect_rc "a program with no code-state snapshot" 0
expect_eq "has nothing to list" ""

run list
expect_rc "list needs a program" 2
run --help
expect_rc "help" 0

if [ "$failures" -ne 0 ]; then
  echo "test-mc-merge-ready: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-merge-ready: all passed"
