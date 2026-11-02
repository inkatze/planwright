#!/bin/bash
# Tests for scripts/substrate-bakeoff.sh run-time behaviour: refusals,
# failure values, timeouts and isolation, each over a copy of the committed
# stub bake-off (universal-binary REQ-C1.4, REQ-C1.6, REQ-G1.3). The report
# and its validator are covered in tests/test-substrate-bakeoff.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-substrate-bakeoff-runs.sh
# shellcheck disable=SC2016 # fixture scripts carry literal expansions
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
SB="$REPO_ROOT/scripts/substrate-bakeoff.sh"
STUB="$REPO_ROOT/tests/fixtures/substrate-bakeoff/stub"

failures=0
ok() { echo "ok: $1"; }
bad() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
check_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi
}
check_has() {
  case "$2" in
    *"$3"*) ok "$1" ;;
    *) bad "$1 (missing [$3] in: $2)" ;;
  esac
}

[ -x "$SB" ] || {
  echo "FAIL: scripts/substrate-bakeoff.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-substrate-bakeoff-runs.XXXXXX") || exit 1
[ -n "$tmp" ] && [ -d "$tmp" ] || exit 1
trap 'rm -rf "$tmp"' EXIT

# get <report> <candidate> <field>
get() {
  awk -F '\t' -v c="$2" -v f="$3" 'NR == 1 { for (i = 1; i <= NF; i++) k[$i] = i; next } $k["candidate"] == c { print $k[f] }' "$1"
}
# set_field <report> <candidate> <field> <value> <out>
set_field() {
  awk -F '\t' -v OFS='\t' -v c="$2" -v f="$3" -v v="$4" 'NR == 1 { for (i = 1; i <= NF; i++) k[$i] = i; print; next } $k["candidate"] == c { $k[f] = v } { print }' "$1" >"$5"
}
# drop_column <report> <field> <out>
drop_column() {
  awk -F '\t' -v OFS='\t' -v f="$2" 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == f) d = i } { s = ""; n = 0; for (i = 1; i <= NF; i++) if (i != d) s = s (n++ ? "\t" : "") $i; print s }' "$1" >"$3"
}
variant() {
  rm -rf "${tmp:?}/$1"
  cp -R "$STUB" "$tmp/$1"
}
run_into() {
  rm -rf "$tmp/out-$1"
  mkdir "$tmp/out-$1"
  out=$("$SB" run --bakeoff "$2" --out-dir "$tmp/out-$1" --run-id "run-$1" --platform test 2>&1)
  rc=$?
}

# --- refusals at run time ---------------------------------------------------

variant omit
mkdir -p "$tmp/omit/fixtures/other/one"
printf '0\n' >"$tmp/omit/fixtures/other/one/expected-status"
: >"$tmp/omit/fixtures/other/one/expected-stdout"
run_into omit "$tmp/omit"
check_eq "a candidate that cannot run a fixture is refused" 1 "$rc"
check_has "the refusal names the missing invocation" "$out" "invoke.other is not set"
if [ -e "$tmp/out-omit/report.tsv" ]; then bad "no report after a refusal"; else ok "no report after a refusal"; fi

variant failing
mkdir -p "$tmp/failing/fixtures/echo-line/wrong"
printf 'in\n' >"$tmp/failing/fixtures/echo-line/wrong/stdin"
printf 'out\n' >"$tmp/failing/fixtures/echo-line/wrong/expected-stdout"
printf '0\n' >"$tmp/failing/fixtures/echo-line/wrong/expected-status"
run_into failing "$tmp/failing"
check_eq "a failing fixture does not refuse the run" 0 "$rc"
check_eq "the failing fixture is recorded per fixture" "echo-line/basic:pass,echo-line/empty:pass,echo-line/wrong:fail" "$(get "$tmp/out-failing/report.tsv" stub-full fixture_results)"
check_eq "the failure counts" "2 1" "$(get "$tmp/out-failing/report.tsv" stub-full tests_passed) $(get "$tmp/out-failing/report.tsv" stub-full tests_failed)"

variant slow
sed 's/^timeout_s=10$/timeout_s=1/' "$STUB/bakeoff.conf" >"$tmp/slow/bakeoff.conf"
mkdir -p "$tmp/slow/fixtures/echo-line/slow"
printf 'sleep\n' >"$tmp/slow/fixtures/echo-line/slow/stdin"
: >"$tmp/slow/fixtures/echo-line/slow/expected-stdout"
printf '0\n' >"$tmp/slow/fixtures/echo-line/slow/expected-status"
cat >"$tmp/slow/candidates/stub-full/bin/echo-line" <<'EOF'
#!/bin/sh
IFS= read -r l || l=
[ "$l" = sleep ] && exec sleep 30
printf '%s\n' "$l"
EOF
start=$(date +%s)
run_into slow "$tmp/slow"
elapsed=$(($(date +%s) - start))
check_eq "a fixture past its timeout does not refuse the run" 0 "$rc"
check_has "the timed-out fixture fails" "$(get "$tmp/out-slow/report.tsv" stub-full fixture_results)" "echo-line/slow:fail"
if [ "$elapsed" -lt 20 ]; then ok "the timeout stops the execution"; else bad "the timeout stops the execution (took ${elapsed}s)"; fi

variant nolog
: >"$tmp/nolog/implementation-time.tsv"
run_into nolog "$tmp/nolog"
check_eq "a full candidate without an implementation-time entry is refused" 1 "$rc"
check_has "the refusal names the log" "$out" "implementation-time.tsv has no row"

variant norev
printf 'stub-full\t1\t3\nstub-full\t2\t1\n' >"$tmp/norev/review-findings.tsv"
run_into norev "$tmp/norev"
check_eq "review rows beyond the stated run count are refused" 1 "$rc"
check_has "the refusal names the review log" "$out" "review-findings.tsv needs exactly one row per convergence run"

variant cmpprim
printf 'invoke.echo-line=bin/hello\n' >>"$tmp/cmpprim/candidates/stub-comparison/candidate.conf"
run_into cmpprim "$tmp/cmpprim"
check_eq "a comparison point implementing a primitive is refused" 1 "$rc"
check_has "the refusal says so" "$out" "never implements a primitive"

variant interp
sed 's|^invoke.echo-line=.*|invoke.echo-line=sh bin/echo-line|' "$STUB/candidates/stub-full/candidate.conf" >"$tmp/interp/candidates/stub-full/candidate.conf"
run_into interp "$tmp/interp"
check_eq "an interpreter-prefixed invocation still runs" 0 "$rc"
check_eq "an interpreter-prefixed invocation is not a literal path" no "$(get "$tmp/out-interp/report.tsv" stub-full literal_path)"

variant escape
sed 's|^sources=.*|sources=../stub-comparison/bin/hello|' "$STUB/candidates/stub-full/candidate.conf" >"$tmp/escape/candidates/stub-full/candidate.conf"
run_into escape "$tmp/escape"
check_eq "a path climbing out of the candidate is refused" 1 "$rc"
check_has "the escape refusal says why" "$out" "must be a plain relative path"

variant dup
printf 'tier=hook\n' >>"$tmp/dup/bakeoff.conf"
run_into dup "$tmp/dup"
check_eq "a repeated configuration key fails closed" 5 "$rc"
check_has "the duplicate-key failure says why" "$out" "a repeated key"

# --- failure values the stub never produces --------------------------------

variant failvals
printf '#!/bin/sh\nexit 1\n' >"$tmp/failvals/candidates/stub-full/delivery/writer"
cat >"$tmp/failvals/candidates/stub-full/bin/echo-line" <<'EOF'
#!/bin/sh
printf '%s\n' "${http_proxy:-}" >/dev/null
[ -n "${http_proxy:-}" ] && exec printf 'proxied\n'
exec cat
EOF
printf '#!/bin/sh\nexit 1\n' >"$tmp/failvals/candidates/stub-comparison/build"
chmod 755 "$tmp/failvals/candidates/stub-full/bin/echo-line" "$tmp/failvals/candidates/stub-comparison/build"
printf 'build=build\n' >>"$tmp/failvals/candidates/stub-comparison/candidate.conf"
run_into failvals "$tmp/failvals"
check_eq "a failing delivery check still produces a report" 0 "$rc"
F=$tmp/out-failvals/report.tsv
check_eq "a failing delivery check records fail" fail "$(get "$F" stub-full delivery_writer)"
check_eq "output that changes offline is not replayable" no "$(get "$F" stub-full offline_replay)"
check_eq "a failing build fails the platform" fail "$(get "$F" stub-comparison platform_result)"

variant noexec
sed 's|^invoke.echo-line=.*|invoke.echo-line=bin/missing|' "$STUB/candidates/stub-full/candidate.conf" >"$tmp/noexec/candidates/stub-full/candidate.conf"
run_into noexec "$tmp/noexec"
check_eq "an invocation that cannot launch still produces a report" 0 "$rc"
check_eq "an invocation that cannot launch fails the platform" fail "$(get "$tmp/out-noexec/report.tsv" stub-full platform_result)"
check_eq "every timed run of a failing call site is counted" 3 "$(get "$tmp/out-noexec/report.tsv" stub-full latency_status_mismatches)"

# --- isolation between candidates, repetitions and the caller --------------

variant isolate
cat >"$tmp/isolate/candidates/stub-full/bin/echo-line" <<'EOF'
#!/bin/sh
seen=clean
[ -e "$HOME/mark" ] && seen=home
[ -e mark ] && seen=cwd
[ -n "${BAKEOFF_TEST_SECRET:-}" ] && seen=env
: >"$HOME/mark"
: >mark
printf '%s\n' "$seen"
EOF
printf 'clean\n' >"$tmp/isolate/fixtures/echo-line/basic/expected-stdout"
printf 'clean\n' >"$tmp/isolate/fixtures/echo-line/empty/expected-stdout"
cp -R "$tmp/isolate/candidates/stub-full" "$tmp/isolate/candidates/stub-second"
printf 'stub-second\t2026-10-01T09:00:00Z\t2026-10-01T09:30:00Z\n' >>"$tmp/isolate/implementation-time.tsv"
printf 'stub-second\t1\t0\n' >>"$tmp/isolate/review-findings.tsv"
rm -rf "$tmp/out-isolate"
mkdir "$tmp/out-isolate"
mkdir -p "$tmp/fakehome"
printf '#!/bin/sh\n: >"$HOME/delivery-mark"\n' >"$tmp/isolate/candidates/stub-second/delivery/marketplace"
chmod 755 "$tmp/isolate/candidates/stub-second/delivery/marketplace"
HOME="$tmp/fakehome" BAKEOFF_TEST_SECRET=leak "$SB" run --bakeoff "$tmp/isolate" --out-dir "$tmp/out-isolate" --run-id iso --platform test >/dev/null 2>&1
check_eq "the isolation run succeeds" 0 "$?"
check_eq "each fixture sees a fresh directory, a fresh home and no caller environment" "echo-line/basic:pass,echo-line/empty:pass" "$(get "$tmp/out-isolate/report.tsv" stub-second fixture_results)"
check_eq "the offline replay starts from an empty home" yes "$(get "$tmp/out-isolate/report.tsv" stub-second offline_replay)"
check_eq "every timed repetition starts clean" 0 "$(get "$tmp/out-isolate/report.tsv" stub-second latency_status_mismatches)"
if [ -e "$tmp/fakehome/delivery-mark" ]; then bad "a delivery script never writes the caller's home"; else ok "a delivery script never writes the caller's home"; fi

# --- a signal to the harness stops the candidate ----------------------------

variant signal
cat >"$tmp/signal/candidates/stub-full/bin/echo-line" <<EOF
#!/bin/sh
: >"$tmp/signal-started"
sleep 3
: >"$tmp/signal-survived"
EOF
"$SB" run --bakeoff "$tmp/signal" --out-dir "$tmp" --run-id sig --platform test >/dev/null 2>&1 &
harness=$!
i=0
until [ -e "$tmp/signal-started" ] || [ "$i" -ge 100 ]; do
  sleep 0.1
  i=$((i + 1))
done
if [ -e "$tmp/signal-started" ]; then ok "the candidate started before the signal"; else bad "the candidate started before the signal"; fi
kill -s TERM "$harness"
wait "$harness"
check_eq "a terminated harness exits 143" 143 "$?"
sleep 3
if [ -e "$tmp/signal-survived" ]; then bad "a terminated harness takes its candidate with it"; else ok "a terminated harness takes its candidate with it"; fi

# --- refusals for malformed configuration ----------------------------------

variant badsite
sed 's|^call_site=.*|call_site=echo.line/basic|' "$STUB/bakeoff.conf" >"$tmp/badsite/bakeoff.conf"
run_into badsite "$tmp/badsite"
check_eq "a call site matching only as a pattern is refused" 1 "$rc"
check_has "the refusal names the call site" "$out" "names no fixture"

variant zeros
printf '00\n' >"$tmp/zeros/fixtures/echo-line/empty/expected-status"
run_into zeros "$tmp/zeros"
check_eq "an expected status with a leading zero fails closed" 5 "$rc"

variant emptybuild
printf 'build=\n' >>"$tmp/emptybuild/candidates/stub-full/candidate.conf"
run_into emptybuild "$tmp/emptybuild"
check_eq "an empty build is refused" 1 "$rc"
check_has "the refusal names the build key" "$out" "build is empty"

variant blankarg
printf 'a\n\nb\n' >"$tmp/blankarg/fixtures/echo-line/basic/args"
run_into blankarg "$tmp/blankarg"
check_eq "an args file with an empty line fails closed" 5 "$rc"
check_has "the failure names the empty argument" "$out" "args has an empty line"

"$SB" bogus >/dev/null 2>&1
check_eq "an unknown subcommand is a usage error" 2 "$?"

if [ "$failures" -gt 0 ]; then
  echo "test-substrate-bakeoff-runs: $failures failure(s)" >&2
  exit 1
fi
echo "test-substrate-bakeoff-runs: all passed"
