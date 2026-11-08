#!/bin/bash
# Tests for scripts/mc-merge-ready.sh — the pull requests ready to merge: a
# non-draft, mergeable, green pull request with no open thread and no review
# outstanding whose readiness walk passes at its head and whose merge
# conditions recommend it, listed with its checked merge command, announced
# once per head and listed again on every read until it merges or changes;
# whatever cannot be judged is said as unknown, never as none.
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
mchome="$tmp/mchome"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_home: $mchome
program_alpha_sources: {code-state: forge:snapshot}
EOF
mkdir -p "$mchome"

# The scripts under test run from a copy whose readiness check is a stub.
# collect writes the evidence at the head in $tmp/head.<n> with the labels
# in $tmp/labels.<n>, or fails when $tmp/verdict.<n> says broken; walk
# answers from $tmp/verdict.<n> (ready, not-ready, or walkfail). Each
# collect is logged.
pw="$tmp/pw"
mkdir -p "$pw"
cp -R "$repo_root/scripts" "$pw/scripts"
cat >"$pw/scripts/mc-readiness.sh" <<EOF
#!/bin/bash
verb=\$1
shift
n="" out="" ev=""
while [ \$# -gt 0 ]; do
  case \$1 in --pr) n=\$2 ;; --out) out=\$2 ;; --evidence) ev=\$2 ;; esac
  shift
done
case \$verb in
  collect)
    printf 'collect --pr %s\n' "\$n" >>"$tmp/check.calls"
    if [ "\$(cat "$tmp/verdict.\$n")" = broken ]; then printf 'gh: not logged in\n' >&2; exit 1; fi
    {
      printf '# format: 1\nhead\t%s\n' "\$(cat "$tmp/head.\$n")"
      cat "$tmp/labels.\$n" 2>/dev/null
      printf 'path\tsrc/app.c\tMODIFIED\nstubpr\t%s\n' "\$n"
    } >"\$out"
    exit 0
    ;;
  walk)
    n=\$(awk -F '\t' '\$1 == "stubpr" { print \$2 }' "\$ev")
    case \$(cat "$tmp/verdict.\$n") in
      ready) printf 'ready\t-\n'; exit 0 ;;
      not-ready) printf 'not-ready\t-\nfail\tcheck\tci is PENDING\n'; exit 4 ;;
    esac
    printf 'walk broke\n' >&2
    exit 1
    ;;
esac
exit 2
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
: >"$tmp/check.calls"
: >"$tmp/gh.calls"

run() { # run <args...>: the copy's mc-merge-ready.sh against the fixture
  OUT=$(PATH="$tmp/bin:$PATH" mc_env /bin/bash "$pw/scripts/mc-merge-ready.sh" "$@" 2>"$tmp/stderr")
  RC=$?
  ERR=$(cat "$tmp/stderr")
}
calls() { awk 'END { print NR + 0 }' "$tmp/check.calls"; }
views() { awk '/^repo view/ { n++ } END { print n + 0 }' "$tmp/gh.calls"; }
checked_since() { [ "$(calls)" -gt "$1" ]; }

H=1111111111111111111111111111111111111111
J=2222222222222222222222222222222222222222
snapdir="$fleet/mission-control/alpha/snapshots"
store="$fleet/mission-control/alpha/merge-ready.tsv"
mkdir -p "$snapdir"
T=$(date +%s)
row() { # row <n> <head> <draft> <mergeable> <threads> <checks> [<decision> [<reviews> [<comments>]]]
  printf 'pr\tacme/web\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tp%s\n' "$1" "$2" "$3" "$4" "${7:-NONE}" "$5" "$6" "${8:-0}" "${9:-0}" "$1"
}
taken() { printf 'format\t1\nsource\tforge\ntaken\t%s\n' "${1:-$T}"; }
only7() { # only7 <head> [<decision> [<reviews> [<comments>]]]: a snapshot of #7 alone, taken at T
  taken
  row 7 "$1" false MERGEABLE 0 SUCCESS "${2:-NONE}" "${3:-0}" "${4:-0}"
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
  row 15 "$H" false MERGEABLE 0 SUCCESS REVIEW_REQUIRED
} >"$snapdir/forge"
for n in 7 8 9 10 11 12 13 14 15; do
  printf '%s\n' "$H" >"$tmp/head.$n"
  printf 'ready\n' >"$tmp/verdict.$n"
done
printf 'not-ready\n' >"$tmp/verdict.12"
cmd() { printf 'gh pr merge %s --repo acme/web --%s --match-head-commit %s' "$1" "${3:-squash}" "$2"; }
cmd7=$(cmd 7 "$H")
ready7() { printf 'ready\tacme/web#7\t%s\t%s' "$1" "$(cmd 7 "$1" "${2:-squash}")"; }
inbox() { printf '%s\n' "$OUT" | mc_env /bin/bash "$repo_root/scripts/mc-inbox.sh" status 2>/dev/null; }

# ---------------------------------------------------------------------------
# list: the readiness walk decides, and only a candidate is walked.
# ---------------------------------------------------------------------------
run list --program alpha --now "$T"
expect_rc "list" 0
expect_eq "each candidate whose walk passes is ready, with its checked merge command" \
  "$(ready7 "$H")
ready${tab}acme/web#14${tab}$H${tab}$(cmd 14 "$H")"
checked=$(awk '{ print $NF }' "$tmp/check.calls" | sort -n | tr '\n' ' ')
if [ "$checked" = "7 12 14 " ]; then
  ok "a draft, a conflict, an open thread, red checks and an outstanding review are never walked"
else
  fail "walked: $checked"
fi
if [ "$(views)" = 1 ]; then ok "the merge method is read once per repository"; else fail "repo view ran $(views) times"; fi

before=$(calls)
run list --program alpha --now "$T"
expect_eq "a second read lists both again" "$(ready7 "$H")
ready${tab}acme/web#14${tab}$H${tab}$(cmd 14 "$H")"
if checked_since "$before"; then fail "an unchanged state was walked again"; else ok "an unchanged state is not walked again"; fi
run count --program alpha
expect_eq "count reads the last verdicts, with no forge read" "2${tab}all"

run list --program alpha --now "$T" --as-status
expect_out "as status lines" "decision${tab}Ready to merge: acme/web#7 at $(printf '%s' "$H" | cut -c1-12), run: $cmd7"
case $(inbox) in
  Decisions*"- Ready to merge: acme/web#7"*Landed*) ok "the first-turn status lists it under Decisions" ;;
  *) fail "status form: $(inbox)" ;;
esac

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

# Every verdict is judged again once half an hour old, ready ones too.
printf 'ready\n' >"$tmp/verdict.12"
printf 'not-ready\n' >"$tmp/verdict.14"
T=$((T + 1801))
{
  taken
  row 7 "$H" false MERGEABLE 0 SUCCESS
  row 12 "$H" false MERGEABLE 0 SUCCESS
  row 14 "$H" false MERGEABLE 0 SUCCESS
} >"$snapdir/forge"
run list --program alpha --now "$T"
expect_eq "an aged verdict is judged again, both ways" "$(ready7 "$H")
ready${tab}acme/web#12${tab}$H${tab}$(cmd 12 "$H")"

# A new review is a readiness input, so it is walked again.
only7 "$H" NONE 1 >"$snapdir/forge"
before=$(calls)
run list --program alpha --now "$T"
if checked_since "$before"; then ok "a new review forces a walk"; else fail "a new review forced no walk"; fi

run watch --program alpha --now "$T"
expect_eq "an announced head is not announced again" ""
run list --program alpha --now "$T"
expect_eq "and is still listed for every bring-up" "$(ready7 "$H")"

# A comment changes no readiness input, so it costs no walk.
only7 "$H" NONE 1 3 >"$snapdir/forge"
before=$(calls)
run list --program alpha --now "$T"
if checked_since "$before"; then fail "a new comment forced a walk"; else ok "a new comment forces no walk"; fi

# Evidence that cannot be collected is unknown, named with its cause, and
# fails the run; the head it had announced is not pushed again once it
# passes.
printf 'broken\n' >"$tmp/verdict.7"
T=$((T + 1801))
only7 "$H" NONE 1 3 >"$snapdir/forge"
run watch --program alpha --now "$T"
expect_rc "evidence that could not be collected fails the watcher run" 1
expect_eq "and announces nothing" ""
expect_err "naming the pull request and the cause" "unknown: acme/web#7: its readiness evidence could not be collected: gh: not logged in"
run count --program alpha
expect_eq "the count is partial, never a smaller number" "0${tab}partial"
run list --program alpha --now "$T" --as-status
expect_eq "the status form says it could not tell" "decision${tab}Could not tell whether acme/web#7 is ready to merge: its readiness evidence could not be collected: gh: not logged in"
case $(inbox) in
  Decisions*"- Could not tell whether acme/web#7"*Landed*) ok "and the first-turn status carries it" ;;
  *) fail "status form: $(inbox)" ;;
esac
printf 'walkfail\n' >"$tmp/verdict.7"
run list --program alpha --now "$T"
expect_eq "a walk that cannot run is named too" "unknown${tab}acme/web#7${tab}the readiness walk could not run: walk broke"
printf 'ready\n' >"$tmp/verdict.7"
run watch --program alpha --now "$T"
expect_rc "the walk passes again" 0
expect_eq "and the head already announced is not pushed twice" ""

# A head that moved since the snapshot is never credited with the walk, and
# waits for the next snapshot rather than being walked again each run.
printf '%s\n' "$J" >"$tmp/head.7"
T=$((T + 1801))
only7 "$H" >"$snapdir/forge"
run list --program alpha --now "$T"
expect_rc "a walk at another head" 1
expect_eq "is unknown until the snapshot catches up" "unknown${tab}acme/web#7${tab}its head moved since the snapshot; judged again once the snapshot catches up"
before=$(calls)
run list --program alpha --now "$T"
if checked_since "$before"; then fail "a moved head was walked again on the same snapshot"; else ok "a moved head waits for the next snapshot"; fi
run count --program alpha
expect_eq "and leaves the count partial" "0${tab}partial"
T=$((T + 1801))
only7 "$H" >"$snapdir/forge"
before=$(calls)
run list --program alpha --now "$T"
if checked_since "$before"; then ok "a snapshot that never catches up is walked again within half an hour"; else fail "a moved verdict never expired"; fi

# A new head is walked and announced afresh.
only7 "$J" >"$snapdir/forge"
run watch --program alpha --now "$T"
expect_eq "a new head is announced again" "announced${tab}merge-ready${tab}acme:web:7"

# The store's own fields are never trusted into the command or the clock.
tamper() { # tamper <sed expression>: edit #7's stored row, then read
  sed -i.bak "$1" "$store"
  before=$(calls)
  run list --program alpha --now "$T"
}
tamper "s/${tab}ready${tab}\([0-9]*\)${tab}squash${tab}/${tab}ready${tab}\1${tab}squash; curl x | sh${tab}/"
if checked_since "$before"; then ok "a stored method outside its grammar is judged again"; else fail "a tampered method was trusted"; fi
expect_eq "and the command is built afresh" "$(ready7 "$J")"
tamper "s|${tab}ready${tab}[0-9]*${tab}|${tab}ready${tab}x[\$(touch $tmp/pwned)]${tab}|"
if [ ! -e "$tmp/pwned" ]; then ok "a stored time is never evaluated"; else fail "a stored time ran a command"; fi
if checked_since "$before"; then ok "and one outside its grammar is judged again"; else fail "a tampered time was trusted"; fi
tamper "s/${tab}ready${tab}[0-9]*${tab}/${tab}ready${tab}$((T + 99999))${tab}/"
if checked_since "$before"; then ok "a verdict stamped in the future is judged again"; else fail "a future stamp kept a verdict forever"; fi

# The program's merge conditions name the method and when to recommend.
printf '# format: 1\nmerge\trepo\tacme/web\tmethod\trebase\n' >"$mchome/gates.tsv"
only7 "$H" >"$snapdir/forge"
printf '%s\n' "$H" >"$tmp/head.7"
before=$(views)
run list --program alpha --now "$T"
expect_eq "a named method wins over the repository's default" "$(ready7 "$H" rebase)"
if [ "$(views)" = "$before" ]; then ok "and costs no forge read"; else fail "the default method was read anyway"; fi
printf 'merge\tlabel\tui\trecommend\tapproved\n' >>"$mchome/gates.tsv"
printf 'label\tui\n' >"$tmp/labels.7"
only7 "$J" >"$snapdir/forge"
printf '%s\n' "$J" >"$tmp/head.7"
run list --program alpha --now "$T"
expect_rc "a recommendation that waits on an approval" 0
expect_eq "is not offered before it" ""
only7 "$J" APPROVED >"$snapdir/forge"
run list --program alpha --now "$T"
expect_eq "and is once approved" "$(ready7 "$J" rebase)"
printf 'merge\tpath\tsrc/*\tmethod\tmerge\n' >>"$mchome/gates.tsv"
only7 "$J" APPROVED 1 >"$snapdir/forge"
run list --program alpha --now "$T"
expect_eq "a condition on the changed paths applies too" "$(ready7 "$J" merge)"
printf 'merge\tprogram\t*\tmethod\tauto\n' >>"$mchome/gates.tsv"
only7 "$H" APPROVED >"$snapdir/forge"
printf '%s\n' "$H" >"$tmp/head.7"
run list --program alpha --now "$T"
expect_out "a refused conditions file is unknown, never ignored" "unknown${tab}acme/web#7${tab}its merge conditions could not be resolved:"
rm -f "$mchome/gates.tsv" "$tmp/labels.7"

# The repository's default method decides the flag; one that cannot be read
# leaves the pull request unknown, never offered without its method.
printf 'REBASE\n' >"$tmp/method"
only7 "$J" >"$snapdir/forge"
printf '%s\n' "$J" >"$tmp/head.7"
run list --program alpha --now "$T"
expect_eq "a rebase repository merges by rebase" "$(ready7 "$J" rebase)"
: >"$tmp/method"
only7 "$H" >"$snapdir/forge"
printf '%s\n' "$H" >"$tmp/head.7"
run list --program alpha --now "$T"
expect_rc "an unreadable merge method fails the read" 1
expect_eq "named, with its cause and no command" "unknown${tab}acme/web#7${tab}the merge method of acme/web could not be read: HTTP 502"
printf 'SQUASH\n' >"$tmp/method"
run list --program alpha --now "$T"
expect_eq "and read again next time" "$(ready7 "$H")"

# While the forge holds reads, a kept verdict stands and nothing is walked;
# a hold already over holds nothing.
printf '%s\n' $((T + 3600)) >"$snapdir/forge.hold"
T=$((T + 1801))
only7 "$H" >"$snapdir/forge"
before=$(calls)
run list --program alpha --now "$T"
if checked_since "$before"; then fail "a walk ran under the forge's hold"; else ok "nothing is walked under the forge's hold"; fi
expect_eq "a kept verdict stands" "$(ready7 "$H")"
only7 "$J" >"$snapdir/forge"
run list --program alpha --now "$T"
expect_eq "one never judged is unknown" "unknown${tab}acme/web#7${tab}the forge is holding reads for its rate limit"
printf '%s\n' $((T - 1)) >"$snapdir/forge.hold"
printf '%s\n' "$J" >"$tmp/head.7"
run list --program alpha --now "$T"
expect_eq "a hold already over holds nothing" "$(ready7 "$J")"
rm -f "$snapdir/forge.hold"

# A row outside the snapshot's grammar is named without its text.
{
  taken
  printf 'pr\tacme/web; run: rm\t7\t%s\tfalse\tMERGEABLE\tNONE\t0\tSUCCESS\t0\t0\tp\n' "$H"
  printf 'pr\tacme/web\t8\tnot-a-sha\tfalse\tMERGEABLE\tNONE\t0\tSUCCESS\t0\t0\tp\n'
} >"$snapdir/forge"
run list --program alpha --now "$T"
expect_eq "malformed rows are one fixed line" "unknown${tab}-${tab}a snapshot row is malformed"
{
  taken "$(date +%s)"
  printf 'pr\tacme/web\t8\tnot-a-sha\tfalse\tMERGEABLE\tNONE\t0\tSUCCESS\t0\t0\tp\n'
} >"$snapdir/forge"
run list --program alpha
run count --program alpha
expect_eq "and leave the count partial (judged on the real clock)" "0${tab}partial"

# Merged: gone from the snapshot, gone from the list and the count (judged
# on the real clock, since a count stamped later than now is partial).
taken "$(date +%s)" >"$snapdir/forge"
run list --program alpha
expect_rc "an empty snapshot" 0
expect_eq "lists nothing" ""
run count --program alpha
expect_eq "and counts none" "0${tab}all"

# A count is only as good as its judgment's age.
real=$(date +%s)
row7="acme/web#7${tab}k${tab}ready${tab}$real${tab}squash${tab}-"
printf 'state\tok\t%s\n%s\n' $((real - 4000)) "$row7" >"$store"
run count --program alpha
expect_eq "a judgment over an hour old is a floor" "1${tab}partial"
printf 'state\tok\t%s\n%s\n' $((real + 4000)) "$row7" >"$store"
run count --program alpha
expect_eq "so is one stamped later than now" "1${tab}partial"
printf '%s\n' "$row7" >"$store"
run count --program alpha
expect_eq "and one with no state line" "1${tab}partial"
printf 'state\tok\t%s\n%s\n' "$real" "$row7" >"$store"
run count --program alpha
expect_eq "a fresh one is whole" "1${tab}all"

# ---------------------------------------------------------------------------
# Every program on the host hears of it: another program whose repositories
# include this one and that runs no readiness check of its own (a hub over
# several programs) gets the same event; one that judges for itself, or
# covers other repositories only, does not.
# ---------------------------------------------------------------------------
git -C "$repo" remote add origin https://github.com/acme/web.git
other="$tmp/other"
git init -q "$other"
git -C "$other" remote add origin git@github.com:acme/api.git
sed -i.bak 's/^mission_control_programs: .*/mission_control_programs: [alpha, hub, beta, gamma]/' "$tracked"
mkdir -p "$tmp/hubhome" "$tmp/betahome" "$tmp/gammahome"
cat >>"$tracked" <<EOF
program_hub_repositories: [$other, $repo]
program_hub_home: $tmp/hubhome
program_hub_duties: [inbox, prepared-moments]
program_beta_repositories: [$repo]
program_beta_home: $tmp/betahome
program_beta_duties: [readiness-check]
program_gamma_repositories: [$other]
program_gamma_home: $tmp/gammahome
program_gamma_duties: [inbox]
EOF
printf '%s\n' "$H" >"$tmp/head.20"
printf 'ready\n' >"$tmp/verdict.20"
{
  taken
  row 20 "$H" false MERGEABLE 0 SUCCESS
} >"$snapdir/forge"
run watch --program alpha --now "$T"
expect_rc "a ready head another program covers" 0
expect_eq "is announced here and forwarded to the covering hub" "announced${tab}merge-ready${tab}acme:web:20
forwarded${tab}hub${tab}merge-ready${tab}acme:web:20"
mc_run mc-event.sh list --program hub
expect_out "the hub's event carries the command and the judging program" \
  "merge-ready${tab}acme:web:20${tab}acme/web#20 is ready to merge: $(cmd 20 "$H") (judged by program alpha)"
mc_run mc-event.sh list --program beta
expect_eq "a program running its own readiness check gets none" ""
mc_run mc-event.sh list --program gamma
expect_eq "nor does one over other repositories" ""
run watch --program alpha --now "$T"
expect_eq "a forwarded head is not forwarded twice" ""
taken >"$snapdir/forge"
run watch --program alpha --now "$T"
{
  taken
  row 20 "$J" false MERGEABLE 0 SUCCESS
} >"$snapdir/forge"
printf '%s\n' "$J" >"$tmp/head.20"
run watch --program alpha --now "$T"
expect_eq "a new head is forwarded afresh" "announced${tab}merge-ready${tab}acme:web:20
forwarded${tab}hub${tab}merge-ready${tab}acme:web:20"

# A program list that fails after the program check is named, fails the run,
# and keeps what was forwarded, so nothing is sent twice once it reads again.
mv "$pw/scripts/mc-program.sh" "$pw/scripts/mc-program.real.sh"
cat >"$pw/scripts/mc-program.sh" <<EOF
#!/bin/bash
if [ "\$1" = list ] && [ -e "$tmp/list.calls" ]; then
  printf 'config read failed\n' >&2
  exit 1
fi
[ "\$1" != list ] || : >"$tmp/list.calls"
exec /bin/bash "$pw/scripts/mc-program.real.sh" "\$@"
EOF
rm -f "$tmp/list.calls"
run watch --program alpha --now "$T"
expect_rc "an unreadable program list fails the run" 1
expect_err "naming it" "unknown: -: the other configured programs cannot be listed"
mv "$pw/scripts/mc-program.real.sh" "$pw/scripts/mc-program.sh"
run watch --program alpha --now "$T"
expect_eq "and nothing is forwarded twice once it reads again" ""

# ---------------------------------------------------------------------------
# A snapshot that cannot be judged is said so, never read as nothing waiting,
# and the verdicts it cannot confirm stay for the next fresh one.
# ---------------------------------------------------------------------------
only7 "$J" >"$snapdir/forge"
run list --program alpha --now "$T"
expect_eq "a fresh snapshot" "$(ready7 "$J")"
{
  taken $((T - 86400))
  row 7 "$J" false MERGEABLE 0 SUCCESS
} >"$snapdir/forge"
run list --program alpha --now "$T"
expect_rc "a stale snapshot fails the list" 1
expect_eq "named" "unknown${tab}-${tab}the code-state snapshot is stale"
run list --program alpha --now "$T" --as-status
expect_eq "and said in the status form" "decision${tab}Could not tell which pull requests are ready to merge: the code-state snapshot is stale"
run count --program alpha
expect_eq "the count it kept is a floor meanwhile" "1${tab}partial"
run watch --program alpha --now "$T"
expect_rc "the watcher waits for a fresh one" 0
expect_eq "quietly" ""
if [ -z "$ERR" ]; then ok "with nothing on stderr"; else fail "a stale snapshot wrote to stderr: $ERR"; fi
only7 "$J" >"$snapdir/forge"
before=$(calls)
run list --program alpha --now "$T"
expect_eq "a fresh snapshot again" "$(ready7 "$J")"
if checked_since "$before"; then fail "a stale spell threw the verdicts away"; else ok "and the kept verdict stands, unwalked"; fi

printf 'format\t1\nsource\tforge\ntaken\tsoon\n' >"$snapdir/forge"
run list --program alpha --now "$T"
expect_eq "an unreadable snapshot is named as such" "unknown${tab}-${tab}the code-state snapshot cannot be read"
run watch --program alpha --now "$T"
expect_rc "and fails the watcher run" 1

rm -f "$snapdir/forge"
run list --program alpha --now "$T"
expect_eq "with none taken yet, it says so" "unknown${tab}-${tab}no code-state snapshot has been taken yet"
run watch --program alpha --now "$T"
expect_rc "and the watcher waits" 0

sed -i.bak 's/^program_alpha_sources: .*/program_alpha_sources: {work-items: specs:record}/' "$tracked"
run list --program alpha --now "$T"
expect_rc "a program with no code-state snapshot" 0
expect_eq "has nothing to list" ""
run count --program alpha
expect_eq "and nothing to count" "0${tab}all"

run list
expect_rc "list needs a program" 2
run --help
expect_rc "help" 0

if [ "$failures" -ne 0 ]; then
  echo "test-mc-merge-ready: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-merge-ready: all passed"
