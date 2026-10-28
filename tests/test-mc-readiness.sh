#!/bin/bash
# Tests for scripts/mc-readiness.sh — the readiness walk over primary
# evidence at the current head, the evidence the session records, the
# collector over the forge and the step records, and the watcher
# (mission-control REQ-D1.8, REQ-I1.7; D-25, D-26).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-readiness.sh
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
printf 'ready_flip_policy: unit-owner\n' | write_core_defaults
mchome="$tmp/mchome"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_home: $mchome
program_alpha_sources: {code-state: forge:snapshot}
EOF
mkdir -p "$mchome"
printf '# format: 1\nready\tprogram\t*\tsteps\tpolish\nready\tlabel\tui\tevidence\tscreenshot\nready\tprogram\t*\tbody\t## Summary\n' >"$mchome/gates.tsv"

H=1111111111111111111111111111111111111111
complete() {
  cat <<EOF
# format: 1
head	$H
repo	acme/web
label	ui
path	src/app.c
check	build	SUCCESS
check	lint	NEUTRAL
thread	t1	resolved
finding	cubic-dev-ai[bot]	t2	answered
step	polish	applied	$H
evidence	screenshot	shots/home.png	$H	ok
guard	ready-guard	pass	-
bodyline	## Summary
bodyline	Adds the thing.
EOF
}
walk_with() { # walk_with <label> <sed expression or -> [extra line]
  complete >"$tmp/ev"
  [ "$2" = - ] || sed -i.bak "$2" "$tmp/ev"
  [ -z "${3:-}" ] || printf '%s\n' "$3" >>"$tmp/ev"
  mc_run mc-readiness.sh walk --program alpha --evidence "$tmp/ev"
}

# ---------------------------------------------------------------------------
# REQ-D1.8: a complete fixture passes; each gap is refused, named.
# ---------------------------------------------------------------------------
walk_with complete -
expect_rc "REQ-D1.8: a complete fixture is ready" 0
expect_eq "REQ-D1.8: the verdict names the head" "ready${tab}$H"

walk_with "missing step" '/^step/d'
expect_rc "REQ-D1.8: a missing step is refused" 4
expect_out "REQ-D1.8: named" "fail${tab}step${tab}polish is not recorded passed or applied at 111111111111"
walk_with "step at another head" "s/^step\tpolish\tapplied\t$H/step\tpolish\tapplied\t2222222222222222222222222222222222222222/"
expect_rc "a step recorded at another head is refused" 4
walk_with "failed step" 's/^step\tpolish\tapplied/step\tpolish\tfailed/'
expect_rc "a failed step is refused" 4

walk_with "red check" '-' "check${tab}e2e${tab}FAILURE"
printf 'rollup\tSUCCESS\n' >>"$tmp/ev"
mc_run mc-readiness.sh walk --program alpha --evidence "$tmp/ev"
expect_rc "REQ-D1.8: a red individual check under a green rollup is refused" 4
expect_out "REQ-D1.8: the check named" "fail${tab}check${tab}e2e is FAILURE"
walk_with "pending check" '-' "check${tab}deploy${tab}PENDING"
expect_rc "a pending check is refused" 4
walk_with "no checks" '/^check/d'
expect_rc "no check context at all is refused" 4

walk_with "open thread" '-' "thread${tab}t9${tab}open"
expect_rc "REQ-D1.8: an open thread is refused" 4
expect_out "named" "fail${tab}thread${tab}t9 is open"

walk_with "unanswered finding" 's/answered$/unanswered/'
expect_rc "REQ-D1.8: an unanswered finding is refused" 4
expect_out "named with its reviewer" "fail${tab}finding${tab}cubic-dev-ai[bot] t2 is unanswered"

walk_with "screenshot error" 's/home.png\t\(.*\)\tok$/home.png\t\1\terror/'
expect_rc "REQ-D1.8: a screenshot judged error is refused" 4
expect_out "named" "fail${tab}screenshot${tab}shots/home.png judged error"
walk_with "screenshot missing judgment" 's/home.png\t\(.*\)\tok$/home.png\t\1\tmissing/'
expect_rc "REQ-D1.8: a screenshot whose judgment is missing is refused" 4
walk_with "screenshot extra, no judgment" '-' "evidence${tab}screenshot${tab}shots/other.png${tab}$H"
expect_rc "a screenshot recorded with no judgment field is refused" 4
expect_out "named as missing" "shots/other.png judged missing"
walk_with "no screenshot" '/^evidence/d'
expect_rc "REQ-I1.7: the label's required screenshot is missing" 4
expect_out "named" "fail${tab}evidence${tab}screenshot is not recorded ok"

walk_with "body" '/^bodyline\t## Summary/d'
expect_rc "a required body text missing is refused" 4
expect_out "named" 'the body lacks "## Summary"'
walk_with "guard" 's/^guard.*/guard\tready-guard\tfail\tbehind its base/'
expect_rc "a failed ready-flip guard is refused" 4
expect_out "named" "fail${tab}guard${tab}ready-guard: behind its base"

printf '# format: 1\nreport\tworker says ready\n' >"$tmp/ev"
mc_run mc-readiness.sh walk --program alpha --evidence "$tmp/ev"
expect_rc "REQ-D1.8: a session report alone never passes" 4
expect_out "REQ-D1.8: said so" "a session report alone never passes"

complete | sed '1d' >"$tmp/ev"
mc_run mc-readiness.sh walk --program alpha --evidence "$tmp/ev"
expect_rc "an evidence file with no format line is refused" 4

# Without the label, no screenshot is required.
walk_with "no label" '/^label/d; /^evidence/d'
expect_rc "REQ-I1.7: an unlabelled pull request needs no screenshot" 0

# ---------------------------------------------------------------------------
# record: evidence the session opened and judged.
# ---------------------------------------------------------------------------
mc_run mc-readiness.sh record --program alpha --repo acme/web --pr 7 --head "$H" --kind screenshot --ref shots/home.png --judgment ok
expect_rc "a judgment is recorded" 0
expect_out "echoed" "recorded${tab}acme/web#7${tab}screenshot${tab}ok"
if [ "$(head -n 1 "$mchome/kb/readiness-check/evidence.tsv")" = "# format: 1" ]; then ok "the store carries its format"; else fail "the store lacks its format line"; fi
mc_run mc-readiness.sh record --program alpha --repo acme/web --pr 7 --head "$H" --kind screenshot --ref x --judgment fine
expect_rc "an unknown judgment is a usage error" 2
mc_run mc-readiness.sh record --program alpha --repo acme/web --pr 7 --head abc --kind smoke --ref x --judgment ok
expect_rc "a short head is a usage error" 2

# ---------------------------------------------------------------------------
# collect: the forge read, the step records and the guard, at the head.
# ---------------------------------------------------------------------------
git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m one
head=$(git -C "$repo" rev-parse HEAD)
mc_run mc-readiness.sh record --program alpha --repo acme/web --pr 7 --head "$head" --kind screenshot --ref shots/home.png --judgment ok
(cd "$repo" && PLANWRIGHT_ROOT="$core" /bin/bash "$repo_root/scripts/step-record.sh" new-run >/dev/null \
  && /bin/bash "$repo_root/scripts/step-record.sh" write --run 000001 --point convergence --step polish --kind skill \
    --target polish --hosting isolated --backend none --head "$head" --end-head "$head" \
    --start 2026-10-28T00:00:00Z --end 2026-10-28T00:01:00Z --outcome applied >/dev/null) || fail "the fixture step record"
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/gh.calls"
case "\$1 \$2" in
  "pr view")
    case "\$*" in
      *statusCheckRollup*) printf 'head\t%s\nlabel\tui\npath\tsrc/app.c\ncheck\tbuild\tSUCCESS\nbodyline\t## Summary\n' "$head" ;;
      *) exit 1 ;;
    esac
    ;;
  "api graphql") printf 'thread\tt1\tresolved\nfinding\tcubic-dev-ai[bot]\tt1\tanswered\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --worktree "$repo" --out "$tmp/collected"
expect_rc "collect" 0
c=$(cat "$tmp/collected" 2>/dev/null)
case $c in "# format: 1"*) ok "the evidence carries its format" ;; *) fail "the collected evidence lacks its format line" ;; esac
case $c in *"head${tab}$head"*) ok "REQ-D1.8: the head is the forge's" ;; *) fail "no head collected" ;; esac
case $c in *"step${tab}polish${tab}applied${tab}$head"*) ok "REQ-D1.8: the recorded cadence step is collected" ;; *) fail "no step collected: $c" ;; esac
case $c in *"evidence${tab}screenshot${tab}shots/home.png${tab}$head${tab}ok"*) ok "the recorded screenshot judgment at the head is collected" ;; *) fail "no screenshot collected" ;; esac
case $c in *"guard${tab}ready-guard${tab}"*) ok "D-25: the ready-flip guard is composed" ;; *) fail "no guard verdict collected" ;; esac
case $c in *"finding${tab}cubic-dev-ai[bot]"*) ok "the automated reviewer's finding is collected" ;; *) fail "no finding collected" ;; esac
case $c in *"repo${tab}acme/web"*) ok "the repository is named for the conditions" ;; *) fail "no repo line" ;; esac
if grep -q 'pr ready' "$tmp/gh.calls" 2>/dev/null; then fail "a flip was attempted"; else ok "nothing flips a pull request"; fi
# The stub cannot satisfy the guard's own reads, so it fails closed, and the
# walk over the collection refuses on it.
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh check --program alpha --repo acme/web --pr 7 --worktree "$repo"
expect_rc "check refuses while the guard does" 4
expect_out "the guard named" "fail${tab}guard${tab}ready-guard"

# ---------------------------------------------------------------------------
# watch: one readiness-due event per new head of a green draft.
# ---------------------------------------------------------------------------
snapdir="$fleet/mission-control/alpha/snapshots"
mkdir -p "$snapdir"
now=$(date +%s)
printf 'format\t1\nsource\tforge\ntaken\t%s\npr\tacme/web\t7\t%s\ttrue\tMERGEABLE\tNONE\t0\tSUCCESS\t0\t0\tp1\npr\tacme/web\t8\t%s\ttrue\tMERGEABLE\tNONE\t2\tSUCCESS\t0\t0\tp2\npr\tacme/web\t9\t%s\tfalse\tMERGEABLE\tNONE\t0\tSUCCESS\t0\t0\tp3\n' \
  "$now" "$H" "$H" "$H" >"$snapdir/forge"
OUT=$(mc_env env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-readiness.sh" 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "the watcher runs with no arguments under the runner" 0
expect_eq "only the green draft with no open thread is due" "event${tab}readiness-due${tab}acme/web#7${tab}head 111111111111"
mc_run mc-readiness.sh watch --program alpha
expect_eq "an announced head is not announced again" ""

if [ "$failures" -ne 0 ]; then
  echo "test-mc-readiness: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-readiness: all passed"
