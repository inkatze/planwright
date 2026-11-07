#!/bin/bash
# Tests for scripts/mc-merge-ready.sh — the pull requests ready to merge: a
# non-draft, mergeable, green pull request with no open thread and no change
# requested whose readiness check passes at its head, listed with its checked
# merge command in the repository's merge method, announced once per head and
# listed again on every read until it merges or changes; whatever cannot be
# judged is said as unknown, never as none.
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
# answers from $tmp/verdict.<n> (ready, at the head in $tmp/head.<n>;
# not-ready; or anything else for a check that could not run) and logs each
# call.
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
printf 'gh: not logged in\n' >&2
exit 1
EOF
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/gh.calls"
case "\$1 \$2" in
  "repo view") m=\$(cat "$tmp/method" 2>/dev/null) && [ -n "\$m" ] && printf '%s\n' "\$m" && exit 0 ;;
esac
printf 'HTTP 502\n' >&2
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
views() { grep -c '^repo view' "$tmp/gh.calls" 2>/dev/null || echo 0; }
checked_since() { # checked_since <calls before>: did a check run since?
  [ "$(calls)" -gt "$1" ]
}

H=1111111111111111111111111111111111111111
J=2222222222222222222222222222222222222222
snapdir="$fleet/mission-control/alpha/snapshots"
mkdir -p "$snapdir"
now=$(date +%s)
row() { # row <n> <head> <draft> <mergeable> <threads> <checks> [<decision> [<comments>]]
  printf 'pr\tacme/web\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t0\t%s\tp%s\n' "$1" "$2" "$3" "$4" "${7:-NONE}" "$5" "$6" "${8:-0}" "$1"
}
taken() { printf 'format\t1\nsource\tforge\ntaken\t%s\n' "${1:-$now}"; }
only7() { # only7 <head> [<comments>]: a snapshot holding #7 alone
  taken
  row 7 "$1" false MERGEABLE 0 SUCCESS NONE "${2:-0}"
}
{
  taken
  row 7 "$H" false MERGEABLE 0 SUCCESS
  row 8 "$H" true MERGEABLE 0 SUCCESS
  row 9 "$H" false CONFLICTING 0 SUCCESS
  row 10 "$H" false MERGEABLE 2 SUCCESS
  row 11 "$H" false MERGEABLE 0 FAILURE
  row 12 "$H" false MERGEABLE 0 SUCCESS
  row 13 "$H" false MERGEABLE 0 SUCCESS CHANGES_REQUESTED
  row 14 "$H" false MERGEABLE 0 SUCCESS
} >"$snapdir/forge"
for n in 7 8 9 10 11 12 13 14; do
  printf '%s\n' "$H" >"$tmp/head.$n"
  printf 'ready\n' >"$tmp/verdict.$n"
done
printf 'not-ready\n' >"$tmp/verdict.12"
cmd() { printf 'gh pr merge %s --repo acme/web --%s --match-head-commit %s' "$1" "${3:-squash}" "$2"; }
cmd7=$(cmd 7 "$H")

# ---------------------------------------------------------------------------
# list: the readiness check decides, and only a candidate is checked.
# ---------------------------------------------------------------------------
run list --program alpha
expect_rc "list" 0
expect_eq "each candidate whose check passes is ready, with its checked merge command" \
  "ready${tab}acme/web#7${tab}$H${tab}$cmd7
ready${tab}acme/web#14${tab}$H${tab}$(cmd 14 "$H")"
checked=$(awk '{ print $NF }' "$tmp/check.calls" | sort -n | tr '\n' ' ')
if [ "$checked" = "7 12 14 " ]; then
  ok "a draft, a conflict, an open thread, red checks and a change requested are never checked"
else
  fail "checked: $checked"
fi
if [ "$(views)" = 1 ]; then ok "the merge method is read once per repository"; else fail "repo view ran $(views) times"; fi

before=$(calls)
run list --program alpha
expect_out "a second read lists the ready one again" "ready${tab}acme/web#7${tab}$H${tab}$cmd7"
if checked_since "$before"; then fail "an unchanged state was checked again"; else ok "an unchanged state is not checked again"; fi
run count --program alpha
expect_eq "count reads the last verdicts, with no forge read" "2"

run list --program alpha --as-status
expect_out "as status lines" "decision${tab}Ready to merge: acme/web#7 at $(printf '%s' "$H" | cut -c1-12), run: $cmd7"
st=$(printf '%s\n' "$OUT" | mc_env /bin/bash "$repo_root/scripts/mc-inbox.sh" status 2>/dev/null)
case $st in
  Decisions*"- Ready to merge: acme/web#7"*Landed*) ok "the first-turn status lists it under Decisions" ;;
  *) fail "status form: $st" ;;
esac

# Every verdict is judged again once half an hour old, ready ones too.
printf 'ready\n' >"$tmp/verdict.12"
printf 'not-ready\n' >"$tmp/verdict.14"
run list --program alpha --now $((now + 1801))
expect_eq "an aged verdict is judged again, both ways" \
  "ready${tab}acme/web#7${tab}$H${tab}$cmd7
ready${tab}acme/web#12${tab}$H${tab}$(cmd 12 "$H")"

# ---------------------------------------------------------------------------
# watch: one merge-ready event per ready head.
# ---------------------------------------------------------------------------
only7 "$H" >"$snapdir/forge"
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

# A comment changes no readiness input, so it costs no check.
only7 "$H" 3 >"$snapdir/forge"
before=$(calls)
run list --program alpha
if checked_since "$before"; then fail "a new comment forced a check"; else ok "a new comment forces no check"; fi

# A check that cannot run is unknown, named with its cause, and fails the
# run; the head it had announced is not pushed again once it passes.
printf 'broken\n' >"$tmp/verdict.7"
run watch --program alpha --now $((now + 3700))
expect_rc "a check that could not run fails the watcher run" 1
expect_eq "and announces nothing" ""
expect_err "naming the pull request and the cause" "unknown: acme/web#7: the readiness check could not run: gh: not logged in"
run count --program alpha
expect_rc "the count is unknown, never a smaller number" 1
expect_eq "printing nothing" ""
printf 'ready\n' >"$tmp/verdict.7"
run watch --program alpha --now $((now + 3700))
expect_rc "the check passes again" 0
expect_eq "and the head already announced is not pushed twice" ""

# A head that moved since the snapshot is never credited with the walk.
only7 "$H" >"$snapdir/forge"
printf '%s\n' "$J" >"$tmp/head.7"
run list --program alpha --now $((now + 7400))
expect_rc "a walk at another head" 1
expect_eq "is unknown until the snapshot catches up" "unknown${tab}acme/web#7${tab}its head moved since the snapshot; judged again at the next one"

# A new head is checked and announced afresh.
only7 "$J" >"$snapdir/forge"
run watch --program alpha
expect_eq "a new head is announced again" "announced${tab}merge-ready${tab}acme:web:7"

# The store's own fields are never trusted into the command.
sed -i.bak "s/${tab}ready${tab}\([0-9]*\)${tab}squash${tab}/${tab}ready${tab}\1${tab}squash; curl x | sh${tab}/" "$fleet/mission-control/alpha/merge-ready.tsv"
before=$(calls)
run list --program alpha
if checked_since "$before"; then ok "a store row outside its grammar is judged again"; else fail "a tampered store row was trusted"; fi
expect_eq "and the command is built afresh" "ready${tab}acme/web#7${tab}$J${tab}$(cmd 7 "$J")"

# The repository's merge method decides the flag; one that cannot be read
# leaves the pull request unknown, never offered without its method.
printf 'REBASE\n' >"$tmp/method"
only7 "$H" >"$snapdir/forge"
printf '%s\n' "$H" >"$tmp/head.7"
run list --program alpha
expect_out "a rebase repository merges by rebase" "$(cmd 7 "$H" rebase)"
: >"$tmp/method"
only7 "$J" >"$snapdir/forge"
printf '%s\n' "$J" >"$tmp/head.7"
run list --program alpha
expect_rc "an unreadable merge method fails the read" 1
expect_eq "named, with its cause and no command" "unknown${tab}acme/web#7${tab}the merge method of acme/web could not be read: HTTP 502"
printf 'SQUASH\n' >"$tmp/method"
run list --program alpha
expect_eq "and read again next time" "ready${tab}acme/web#7${tab}$J${tab}$(cmd 7 "$J")"

# While the forge holds reads, a kept verdict stands and no check runs.
printf '%s\n' $((now + 99999)) >"$snapdir/forge.hold"
before=$(calls)
run list --program alpha --now $((now + 3700))
if checked_since "$before"; then fail "a check ran under the forge's hold"; else ok "no check runs under the forge's hold"; fi
expect_eq "a kept verdict stands" "ready${tab}acme/web#7${tab}$J${tab}$(cmd 7 "$J")"
only7 "$H" >"$snapdir/forge"
run list --program alpha
expect_eq "one never judged is unknown" "unknown${tab}acme/web#7${tab}the forge is holding reads for its rate limit"
rm -f "$snapdir/forge.hold"

# Merged: gone from the snapshot, gone from the list and the count.
taken >"$snapdir/forge"
run list --program alpha
expect_rc "an empty snapshot" 0
expect_eq "lists nothing" ""
run count --program alpha
expect_eq "and counts none" "0"

# ---------------------------------------------------------------------------
# A snapshot that cannot be judged is said so, never read as nothing waiting.
# ---------------------------------------------------------------------------
{
  taken $((now - 86400))
  row 7 "$H" false MERGEABLE 0 SUCCESS
} >"$snapdir/forge"
run list --program alpha
expect_rc "a stale snapshot fails the list" 1
expect_eq "named" "unknown${tab}-${tab}the code-state snapshot is stale"
run list --program alpha --as-status
expect_eq "and said in the status form" "decision${tab}Could not tell which pull requests are ready to merge: the code-state snapshot is stale"
run count --program alpha
expect_rc "the count is unknown too" 1
run watch --program alpha
expect_rc "the watcher waits for a fresh one" 0
expect_eq "quietly" ""

printf 'format\t1\nsource\tforge\ntaken\tsoon\n' >"$snapdir/forge"
run list --program alpha
expect_eq "an unreadable snapshot is named as such" "unknown${tab}-${tab}the code-state snapshot cannot be read"
run watch --program alpha
expect_rc "and fails the watcher run" 1

rm -f "$snapdir/forge"
run list --program alpha
expect_eq "with none taken yet, it says so" "unknown${tab}-${tab}no code-state snapshot has been taken yet"
run watch --program alpha
expect_rc "and the watcher waits" 0

sed -i.bak 's/^program_alpha_sources: .*/program_alpha_sources: {work-items: specs:record}/' "$tracked"
run list --program alpha
expect_rc "a program with no code-state snapshot" 0
expect_eq "has nothing to list" ""
run count --program alpha
expect_eq "and nothing to count" "0"

run list
expect_rc "list needs a program" 2
run --help
expect_rc "help" 0

if [ "$failures" -ne 0 ]; then
  echo "test-mc-merge-ready: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-merge-ready: all passed"
