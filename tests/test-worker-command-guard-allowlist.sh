#!/bin/bash
# Tests for the worker's read-only allow-list: the read verbs a worker and its
# lens agents run constantly (`ss` beside grep, cat, ls, md5sum, ps, file), the
# routine polish commands (a suite under `umask 022`, the router's kind-flag
# form, the step scripts of the installed root), the scratch arm's TMPDIR
# rule, and the profile's static entries (WebSearch allowed; WebFetch and the
# unclassifiable tools left to the prompt). Each allowed shape sits beside the
# write, chain and redirect variants that must keep deferring.
# tests/test-worker-command-guard.sh holds the suite's overview; every file
# sources tests/lib/worker-command-guard-harness.sh.
# shellcheck disable=SC2016 # the single-quoted rows are literal command text under test
# shellcheck disable=SC2034 # HOOK_ENV is read by the sourced harness
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"
# shellcheck source=tests/lib/worker-guard-corpus.sh
. "$REPO_ROOT/tests/lib/worker-guard-corpus.sh"

PROFILE="$REPO_ROOT/config/worker-settings.json"

corpus_sandbox "$SANDBOX/box" "$REPO_ROOT" || {
  echo "FAIL: could not build the corpus sandbox" >&2
  exit 1
}
WT=$CORPUS_WORKTREE
SC=$CORPUS_SCRATCH
OUT_DIR=$CORPUS_OUTSIDE
STATE=$CORPUS_BOX/state
GIT_ISO=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
# The empty-policy record: the default every adopter has, no arm live.
REC=$STATE/record.1
under() {
  HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=${2-$SC}" "PLANWRIGHT_WORKER_SESSION_RECORD=${1-$REC}")
}

echo "### ss: the read-only socket listing"
under
for c in 'ss -ltn' 'ss -tulpn' 'ss -s' 'ss -4 -tn' 'ss -H -ltn' 'ss -tan state established' \
  'ss -ltn sport = :8080' 'ss --listening --tcp --numeric' 'ss -ltn | grep 80' 'ss -ltn | wc -l' \
  'ss -x' 'ss -tlnpe' 'ss -tm' 'ss -ti'; do
  assert_allow "ss read form: $c" "$c" Bash "$WT"
done
for c in 'ss -K' 'ss -tK' 'ss --kill' 'ss -D out.dump' 'ss --diag=out.dump' 'ss -F filter.txt' \
  'ss --filter=filter.txt' 'ss -N ns1' 'ss --net=ns1' 'ss -r' 'ss --resolve' 'ss -E' 'ss --events' \
  'ss -b' 'ss --bpf' 'ss -ltn > out.txt' 'ss -ltn >> out.txt' 'ss -ltn; rm x' 'ss -ltn && rm x' \
  'ss -ltn | sh' 'ss -ltn $(rm x)' 'ss -ltn `rm x`' 'ss $X' 'ss -ltn dport = $(id)' 'ss -f inet' \
  'ss -A tcp' 'ss -ltn ; touch x' 'ss -tlnpK' 'ss -ltnD' 'ss -ltnF' 'ss -ltnN' 'ss -ltnb' 'ss -ltnr' \
  'ss -ltnE' 'ss -Z' 'ss -ltn --' 'ss -- -K' 'ss --lis' 'ss --listening=1' 'ss -ltn "-K"' 'ss -ltn -K'; do
  assert_defer "ss write or chain form: $c" "$c" Bash "$WT"
done

echo "### the read verbs beside their write, chain and redirect variants"
for c in 'grep -n foo f' 'cat f' 'ls -la' 'md5sum f' 'ps aux' 'file f' 'grep -c x f'; do
  assert_allow "read verb: $c" "$c" Bash "$WT"
done
for c in 'cat f > g' 'cat f >> g' 'ls; rm g' 'ls && rm g' 'grep a f | sh' 'grep a f | bash' \
  'cat f | sh' 'cat $(rm g)' 'cat `rm g`' 'ls -la > out.txt' 'ps aux > ps.txt' 'md5sum f > f.md5' \
  'file -C' 'file --compile' 'file f > out' 'grep -n x f && rm g' 'cat f || rm g' 'cat f; curl x' \
  'cat /proc/1/environ' 'ps eww' 'grep -r x ~' 'ls -R /'; do
  assert_defer "read verb variant that writes or chains: $c" "$c" Bash "$WT"
done

echo "### a suite under umask 022"
under
assert_allow "umask 022, then a repo suite" "umask 022 && bash tests/ok.sh" Bash "$WT"
assert_allow "umask 0022, then a repo suite" "umask 0022 && bash tests/ok.sh" Bash "$WT"
assert_allow "a bare umask" "umask" Bash "$WT"
assert_allow "umask -S" "umask -S" Bash "$WT"
assert_allow "umask -p" "umask -p" Bash "$WT"
assert_allow "umask 077" "umask 077 && bash tests/ok.sh" Bash "$WT"
assert_allow "umask 002" "umask 002 && bash tests/ok.sh" Bash "$WT"
for c in 'umask 0' 'umask 000' 'umask 0000' 'umask 2' 'umask 22' 'umask 021' 'umask 020' 'umask 00000'; do
  assert_defer "umask leaving files world-writable or a short form: $c" "$c && bash tests/ok.sh" Bash "$WT"
done
assert_defer "umask then a write" "umask 022 && rm g" Bash "$WT"
assert_defer "umask then a chain into an unallowed command" "umask 022 && bash tests/ok.sh && rm g" Bash "$WT"
assert_defer "umask then bash -c" "umask 022 && bash -c 'rm g'" Bash "$WT"
assert_defer "umask then a pipe into a shell" "umask 022 && cat f | sh" Bash "$WT"
assert_defer "umask with a redirect" "umask 022 > out" Bash "$WT"
assert_defer "umask with a symbolic mode" "umask u=rwx" Bash "$WT"
assert_defer "umask with a non-octal digit" "umask 028" Bash "$WT"
assert_defer "umask with an expansion" "umask \$M" Bash "$WT"
assert_defer "umask with a substitution" "umask \$(id)" Bash "$WT"
assert_defer "umask with a second word" "umask 022 rm" Bash "$WT"
assert_defer "umask -S with an operand" "umask -S 022" Bash "$WT"
assert_defer "umask -p with an operand" "umask -p 022" Bash "$WT"
assert_defer "umask with two flags" "umask -S -p" Bash "$WT"
assert_defer "umask then a bare suite outside the repo" "umask 022 && bash $OUT_DIR/x.sh" Bash "$WT"

echo "### a scratch file is never run"
# tests/test-worker-command-guard-scratch.sh pins the scratch policy; these
# rows add the empty policy and both arms.
mkdir -p "$SC/d"
printf 'ls\n' >"$SC/d/script.sh"
under
assert_defer "sh of a scratch file under the empty policy" "sh $SC/d/script.sh" Bash "$WT"
under "$STATE/record.4"
assert_defer "sh of a scratch file under both arms" "sh $SC/d/script.sh" Bash "$WT"
under

echo "### the scratch arm trusts only an absolute TMPDIR"
# A relative TMPDIR resolves from the hook's directory in the guard and from the
# payload's in the shell, so the root it names could differ; unset must defer,
# never abort the hook (it exits 0 whatever the environment holds).
under "$STATE/record.3" "$SC"
assert_allow "the scratch arm with an absolute TMPDIR" "touch \$TMPDIR/made" Bash "$WT"
under "$STATE/record.3" "$SC/"
assert_allow "the scratch arm with a trailing slash on TMPDIR" "touch \$TMPDIR/made" Bash "$WT"
ORIG_PWD=$PWD
cd "$CORPUS_BOX" || exit 1
under "$STATE/record.3" "scratch"
assert_defer "the scratch arm while TMPDIR is a relative path" "touch \$TMPDIR/x" Bash "$WT"
assert_defer "a literal scratch write while TMPDIR is a relative path" "touch $SC/x" Bash "$WT"
cd "$ORIG_PWD" || exit 1
under "$STATE/record.3" ""
assert_defer "the scratch arm while TMPDIR is empty" "touch \$TMPDIR/x" Bash "$WT"
HOOK_ENV=("${GIT_ISO[@]}" "PLANWRIGHT_WORKER_SESSION_RECORD=$STATE/record.3")
unset TMPDIR
assert_defer "the scratch arm while TMPDIR is unset" "touch \$TMPDIR/x" Bash "$WT"
assert_allow "a plain read while TMPDIR is unset" "ls -la" Bash "$WT"
TMPDIR=/tmp
export TMPDIR
under

echo "### the router's kind-flag form"
SR_WT="$SANDBOX/install/worktree"
mkdir -p "$SR_WT/scripts" "$SR_WT/tests"
: >"$SR_WT/.git"
: >"$SR_WT/tests/ok.sh"
: >"$SR_WT/tests/test-ok.sh"
mkdir -p "$SR_WT/tests/test-a"
: >"$SR_WT/tests/test-a/b.sh"
: >"$SR_WT/scripts/compute-route.sh"
: >"$PLUGIN_ROOT/scripts/compute-route.sh"
CR=$PLUGIN_ROOT/scripts/compute-route.sh
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT")
assert_allow "the bare router form (baseline)" "$CR -- bash tests/ok.sh" Bash "$SR_WT"
assert_allow "the check form" "$CR --check -- mise run check" Bash "$SR_WT"
assert_allow "the check form under a timeout" "timeout 600 $CR --check -- mise run check" Bash "$SR_WT"
assert_allow "the task form" "$CR --task lint -- mise run lint" Bash "$SR_WT"
assert_allow "the test form" "$CR --test tests/test-ok.sh -- bash tests/test-ok.sh" Bash "$SR_WT"
assert_allow "the check form under umask" "umask 022 && $CR --check -- mise run check" Bash "$SR_WT"
assert_defer "a bare router name, looked up on PATH" "compute-route.sh --check -- mise run check" Bash "$PLUGIN_ROOT/scripts"
assert_defer "a quoted kind flag" "$CR '--check' -- mise run check" Bash "$SR_WT"
assert_defer "a quoted task name" "$CR --task 'lint' -- mise run lint" Bash "$SR_WT"
assert_defer "a quoted command word" "$CR --check -- \"mise\" run check" Bash "$SR_WT"
assert_defer "an = spelled kind flag" "$CR --task=lint -- mise run lint" Bash "$SR_WT"
assert_defer "a task name outside the router's grammar" "$CR --task Lint -- mise run Lint" Bash "$SR_WT"
assert_defer "a test path with a directory" "$CR --test tests/test-a/b.sh -- bash tests/test-a/b.sh" Bash "$SR_WT"
assert_defer "the test form with an extra argument" "$CR --test tests/test-ok.sh -- bash tests/test-ok.sh arg" Bash "$SR_WT"
assert_allow "the directory path the pair refuses is approved on its own" "bash tests/test-a/b.sh" Bash "$SR_WT"
assert_defer "the test form under /bin/bash, which the guard never approves as a verb" "$CR --test tests/test-ok.sh -- /bin/bash tests/test-ok.sh" Bash "$SR_WT"
assert_defer "the task form with extra command words" "$CR --task lint -- mise run lint x" Bash "$SR_WT"
assert_defer "an environment prefix before the router" "FOO=1 $CR --check -- mise run check" Bash "$SR_WT"
assert_defer "the check form naming another command" "$CR --check -- bash tests/ok.sh" Bash "$SR_WT"
assert_defer "the check form routing a write" "$CR --check -- rm g" Bash "$SR_WT"
assert_defer "the check form routing mise run of another task" "$CR --check -- mise run lint" Bash "$SR_WT"
assert_defer "the check form with extra command words" "$CR --check -- mise run check extra" Bash "$SR_WT"
assert_defer "the task form naming another task" "$CR --task lint -- mise run check" Bash "$SR_WT"
assert_defer "the task form routing a write" "$CR --task lint -- rm g" Bash "$SR_WT"
assert_defer "the test form naming another file" "$CR --test tests/test-ok.sh -- bash tests/test-other.sh" Bash "$SR_WT"
assert_defer "the test form routing a write" "$CR --test tests/ok.sh -- rm g" Bash "$SR_WT"
assert_defer "the test form with a path outside the tests" "$CR --test ../x.sh -- bash ../x.sh" Bash "$SR_WT"
assert_defer "two kind flags" "$CR --check --task lint -- mise run lint" Bash "$SR_WT"
assert_defer "a kind flag with no --" "$CR --check mise run check" Bash "$SR_WT"
assert_defer "a kind flag with nothing to run" "$CR --check --" Bash "$SR_WT"
assert_defer "a kind flag then a chain" "$CR --check -- mise run check && rm g" Bash "$SR_WT"
assert_defer "a kind flag then a redirect" "$CR --check -- mise run check > out" Bash "$SR_WT"
assert_defer "a kind flag then a pipe into a shell" "$CR --check -- mise run check | sh" Bash "$SR_WT"
assert_defer "a kind flag with no value" "$CR --task -- mise run x" Bash "$SR_WT"
assert_defer "a task kind flag with nothing after it" "$CR --task" Bash "$SR_WT"
assert_defer "a test kind flag with nothing after it" "$CR --test" Bash "$SR_WT"
assert_defer "a quoted router word" "\"$CR\" --check -- mise run check" Bash "$SR_WT"
assert_defer "the task form naming check, which the router maps to --check" "$CR --task check -- mise run check" Bash "$SR_WT"
assert_defer "a router run by the router, bare" "$CR -- $CR -- bash tests/ok.sh" Bash "$SR_WT"
assert_defer "a kind flag whose command is not the one it maps to, a router" "$CR --check -- $CR --check -- mise run check" Bash "$SR_WT"
assert_defer "the checkout's own copy of the router with a kind flag" "scripts/compute-route.sh --check -- mise run check" Bash "$SR_WT"
assert_defer "a kind flag through a variable" "$CR --check -- mise run \$T" Bash "$SR_WT"

echo "### the step scripts of the installed root"
SREC=$PLUGIN_ROOT/scripts/step-record.sh
SRUN=$PLUGIN_ROOT/scripts/step-run.sh
: >"$SREC"
: >"$SRUN"
assert_allow "step-record heads" "$SREC heads" Bash "$SR_WT"
assert_allow "step-record render" "$SREC render --run r-1" Bash "$SR_WT"
assert_allow "step-run audit" "$SRUN audit --through pre-pr" Bash "$SR_WT"
assert_allow "step-run audit to post-pr" "$SRUN audit --through post-pr --base origin/main" Bash "$SR_WT"
assert_defer "step-record with a redirect" "$SREC heads > out" Bash "$SR_WT"
assert_defer "step-record then a write" "$SREC heads; rm g" Bash "$SR_WT"
assert_defer "step-record into a shell" "$SREC render --run r-1 | sh" Bash "$SR_WT"
assert_defer "step-run then a chain into a write" "$SRUN audit --through pre-pr && rm g" Bash "$SR_WT"
assert_defer "step-run with a substitution that writes" "$SRUN audit --through \$(rm g)" Bash "$SR_WT"
assert_defer "a step script of a root the guard does not trust" "$SANDBOX/install/planwright-evil/scripts/step-record.sh heads" Bash "$SR_WT"
assert_defer "a step script of a decoy sibling root" "$PLUGIN_DECOY/scripts/step-record.sh heads" Bash "$SR_WT"

under
echo "### the profile's static entries"
if jq -e '.permissions.allow | index("WebSearch") != null' "$PROFILE" >/dev/null 2>&1; then
  pass "WebSearch is allowed without a prompt"
else
  fail "WebSearch must be in the profile's allow list"
fi
if jq -e '[.permissions.allow[] | select(startswith("WebFetch"))] | length == 0' "$PROFILE" >/dev/null 2>&1; then
  pass "WebFetch keeps its prompt: a URL can carry data out"
else
  fail "WebFetch must have no static allow entry"
fi
# Any Bash allow entry naming one of these verbs, in any spelling: the first
# word of the rule's pattern, past an optional leading wildcard or paren.
# ls and stat are deliberately absent: the profile allows them statically.
for t in psql redis-cli curl sed cat grep md5sum file ss ps umask sh bash; do
  if jq -e --arg t "$t" '[.permissions.allow[] | select(test("^Bash\\((.*[ /])?" + $t + "([ :*)]|$)"))] | length == 0' "$PROFILE" >/dev/null 2>&1; then
    pass "$t has no static allow entry: the hook screens its arguments"
  else
    fail "$t must have no static allow entry: a static rule never reaches the hook's argument screens"
  fi
done
for t in psql redis-cli curl; do
  assert_defer "$t has no read-only form the hook approves" "$t -c x" Bash "$WT"
done

finish_suite "worker allow-list"
