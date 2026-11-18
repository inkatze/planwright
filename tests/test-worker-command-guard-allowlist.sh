#!/bin/bash
# Tests for the worker's read-only allow-list: the read verbs a worker and its
# lens agents run constantly (`ss` beside grep, cat, ls, md5sum, ps, file), the
# routine polish commands (a suite under `umask 022`, a read-only probe script
# in the worker's own scratch directory, the router's kind-flag form, the step
# scripts of the installed root) and the profile's static entries (WebSearch
# allowed; WebFetch and the unclassifiable tools left to the prompt). Each
# allowed shape sits beside the write, chain and redirect variants that must
# keep deferring. tests/test-worker-command-guard.sh holds the suite's
# overview; every file sources tests/lib/worker-command-guard-harness.sh.
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
assert_defer "umask then a bare suite outside the repo" "umask 022 && bash $OUT_DIR/x.sh" Bash "$WT"

echo "### a probe script in the worker's own scratch directory"
mkdir -p "$SC/probe.d" "$OUT_DIR/probe.d"
printf '#!/bin/sh\nset -eu\n# a read-only probe\ngrep -n x f\nls -la\n' >"$SC/probe.d/ok.sh"
printf 'if [ -f f ]; then cat f; fi\nfor n in a b; do ls "$n"; done\n' >"$SC/probe.d/ctl.sh"
printf 'grep -n x f\nrm g\n' >"$SC/probe.d/write.sh"
printf 'grep -n x f > out.txt\n' >"$SC/probe.d/redir.sh"
printf 'grep -n x f | sh\n' >"$SC/probe.d/pipe.sh"
printf 'curl http://example.invalid\n' >"$SC/probe.d/curl.sh"
printf 'echo $(rm g)\n' >"$SC/probe.d/subst.sh"
printf 'cat f && rm g\n' >"$SC/probe.d/chain.sh"
printf 'cat /proc/1/environ\n' >"$SC/probe.d/environ.sh"
printf 'sh %s/probe.d/self.sh\n' "$SC" >"$SC/probe.d/self.sh"
printf 'sh %s/probe.d/write.sh\n' "$SC" >"$SC/probe.d/inner-write.sh"
printf 'sh %s/probe.d/ok.sh\n' "$SC" >"$SC/probe.d/inner-ok.sh"
printf '# only a comment\n' >"$SC/probe.d/empty.sh"
: >"$SC/probe.d/zero.sh"
printf 'grep -n x f\n' >"$SC/probe.d/ok.txt"
printf 'grep -n x f\x00rm g\n' >"$SC/probe.d/nul.sh"
{
  printf 'grep -n x f\n'
  i=0
  while [ "$i" -lt 2000 ]; do
    printf 'ls -la\n'
    i=$((i + 1))
  done
} >"$SC/probe.d/big.sh"
printf 'grep -n x f\n' >"$SC/ok.sh"
printf 'grep -n x f\n' >"$OUT_DIR/probe.d/ok.sh"
ln -sf "$SC/probe.d/ok.sh" "$SC/probe.d/link.sh"
ln -sf "$OUT_DIR/probe.d/ok.sh" "$SC/probe.d/outlink.sh"
ln -f "$OUT_DIR/probe.d/ok.sh" "$SC/probe.d/hard.sh"
mkdir -p "$SC/probe.d/deeper"
printf 'grep -n x f\n' >"$SC/probe.d/deeper/ok.sh"
mkdir -p "$SC/.hidden"
printf 'grep -n x f\n' >"$SC/.hidden/ok.sh"
printf 'grep -n x f\n' >"$SC/probe.d/.dot.sh"
printf 'grep -n x f\n' >"$SC/probe.d/we ird.sh"
printf 'grep -n x f\n' >"$OUT_DIR/ok.sh"
mkdir -p "${SC}-evil/probe.d"
printf 'grep -n x f\n' >"${SC}-evil/probe.d/ok.sh"
# A leading line carrying a control byte that sh counts as part of a word
# (form feed, vertical tab, carriage return), which hides a command from a
# reader that trims it as blank space.
printf '\f# x; rm g\nls\n' >"$SC/probe.d/ff.sh"
printf '\v# x; rm g\nls\n' >"$SC/probe.d/vt.sh"
printf '\r# x; rm g\nls\n' >"$SC/probe.d/cr.sh"
printf '#!/bin/sh\r\nset -eu\r\ngrep -n x f\r\n' >"$SC/probe.d/crlf.sh"
printf 'cat f\rrm g\n' >"$SC/probe.d/midcr.sh"
printf '\t# a tab-indented comment\n\tset -eu\n\n  grep -n x f\n' >"$SC/probe.d/tabs.sh"
printf 'grep -n x f\nset -eu\n' >"$SC/probe.d/midset.sh"
printf 'grep -n x f\n# a comment after the first command\nls\n' >"$SC/probe.d/midcomment.sh"
printf "grep -n x f\\n# it's\\nrm g\\n# '\\n" >"$SC/probe.d/quote.sh"
printf 'cat <<EOF\nx\nEOF\n' >"$SC/probe.d/heredoc.sh"
# The size cap: a file of exactly the cap is read whole, one byte past it is
# refused even when its body, past the comments, is small.
printf '#%8187s\nls\n' '' >"$SC/probe.d/cap.sh"
printf '#%8188s\nls\n' '' >"$SC/probe.d/overcap.sh"
{
  i=0
  while [ "$i" -lt 400 ]; do
    printf '# padding padding\n'
    i=$((i + 1))
  done
  printf 'ls\n'
} >"$SC/probe.d/commented.sh"
{
  i=0
  while [ "$i" -lt 700 ]; do
    printf '# padding padding\n'
    i=$((i + 1))
  done
  printf 'ls\n'
} >"$SC/probe.d/overcommented.sh"

under
assert_allow "sh of a scratch probe" "sh $SC/probe.d/ok.sh" Bash "$WT"
assert_allow "sh of a scratch probe with control structures" "sh $SC/probe.d/ctl.sh" Bash "$WT"
assert_allow "sh of a scratch probe from a directory outside the worktree" "sh $SC/probe.d/ok.sh" Bash "$OUT_DIR"
assert_allow "sh of a probe behind timeout" "timeout 30 sh $SC/probe.d/ok.sh" Bash "$WT"
assert_allow "sh of a probe behind time" "time sh $SC/probe.d/ok.sh" Bash "$WT"
assert_allow "sh of a probe with tab-indented leading lines" "sh $SC/probe.d/tabs.sh" Bash "$WT"
assert_allow "sh of a probe of exactly the size cap" "sh $SC/probe.d/cap.sh" Bash "$WT"
assert_allow "sh of a probe with many leading comment lines under the cap" "sh $SC/probe.d/commented.sh" Bash "$WT"
assert_defer "a probe one byte past the size cap" "sh $SC/probe.d/overcap.sh" Bash "$WT"
assert_defer "a probe over the cap whose body past the comments is small" "sh $SC/probe.d/overcommented.sh" Bash "$WT"
assert_defer "a probe whose first line is form feed then a comment then a command" "sh $SC/probe.d/ff.sh" Bash "$WT"
assert_defer "a probe whose first line is vertical tab then a comment then a command" "sh $SC/probe.d/vt.sh" Bash "$WT"
assert_defer "a probe whose first line is carriage return then a comment then a command" "sh $SC/probe.d/cr.sh" Bash "$WT"
assert_defer "a probe with CRLF line ends" "sh $SC/probe.d/crlf.sh" Bash "$WT"
assert_defer "a probe with a carriage return inside a line" "sh $SC/probe.d/midcr.sh" Bash "$WT"
assert_defer "a probe whose set line is not at the head" "sh $SC/probe.d/midset.sh" Bash "$WT"
assert_defer "a probe with a comment after the first command" "sh $SC/probe.d/midcomment.sh" Bash "$WT"
assert_defer "a probe hiding a command behind comment quotes" "sh $SC/probe.d/quote.sh" Bash "$WT"
assert_defer "a probe with a here-document" "sh $SC/probe.d/heredoc.sh" Bash "$WT"
assert_defer "a probe that runs another read-only probe" "sh $SC/probe.d/inner-ok.sh" Bash "$WT"
assert_defer "a probe typed with a quoted path" "sh \"$SC/probe.d/ok.sh\"" Bash "$WT"
assert_defer "a probe typed through \$TMPDIR" "sh \$TMPDIR/probe.d/ok.sh" Bash "$WT"
assert_defer "a probe typed through \${TMPDIR}" "sh \${TMPDIR}/probe.d/ok.sh" Bash "$WT"
assert_defer "a probe behind nice" "nice -n 5 sh $SC/probe.d/ok.sh" Bash "$WT"
assert_defer "a probe behind timeout and a chain" "timeout 5 sh $SC/probe.d/ok.sh && rm g" Bash "$WT"
assert_defer "a probe in the background" "sh $SC/probe.d/ok.sh &" Bash "$WT"
assert_defer "a probe in a subshell" "(sh $SC/probe.d/ok.sh)" Bash "$WT"
assert_defer "a probe with its stderr redirected" "sh $SC/probe.d/ok.sh 2>&1" Bash "$WT"
assert_defer "a probe fed from a file" "sh $SC/probe.d/ok.sh < f" Bash "$WT"
assert_defer "a probe in a loop" "for n in a b; do sh $SC/probe.d/ok.sh; done" Bash "$WT"
assert_defer "a probe in fish -c" "fish -c 'sh $SC/probe.d/ok.sh'" Bash "$WT"
# Each neighbour here is itself approvable, so only the lone-call rule can
# defer these.
assert_defer "a read before the probe" "ls && sh $SC/probe.d/ok.sh" Bash "$WT"
assert_defer "a read after the probe" "sh $SC/probe.d/ok.sh; ls" Bash "$WT"
assert_defer "the probe piped into a read" "sh $SC/probe.d/ok.sh | grep x" Bash "$WT"
assert_defer "a read and the probe on separate lines" "$(printf 'ls\nsh %s/probe.d/ok.sh' "$SC")" Bash "$WT"
assert_defer "the probe and a read on separate lines" "$(printf 'sh %s/probe.d/ok.sh\nls' "$SC")" Bash "$WT"
assert_defer "a probe under || with a read" "ls || sh $SC/probe.d/ok.sh" Bash "$WT"
# A body that only a policy arm or the spec-root zone could approve defers
# inside a probe, where neither is live.
printf 'touch %s/probe.d/made\n' "$SC" >"$SC/probe.d/arm-touch.sh"
printf 'printf x > %s/probe.d/made\n' "$SC" >"$SC/probe.d/arm-redirect.sh"
printf 'mkdir -p %s/probe.d/sub\n' "$SC" >"$SC/probe.d/arm-mkdir.sh"
printf 'cd %s\nls\n' "$WT" >"$SC/probe.d/arm-cd.sh"
printf 'rm -f %s/probe.d/made\n' "$SC" >"$SC/probe.d/arm-rm.sh"
printf 'echo "$DEPLOY_KEY"1\n' >"$SC/probe.d/secretvar.sh"
printf 'ls "$MY_PAT"x\n' >"$SC/probe.d/secretvar2.sh"
for f in arm-touch arm-redirect arm-mkdir arm-cd arm-rm secretvar secretvar2; do
  assert_defer "a probe body that only a policy arm could approve, or that names a secret variable: $f" "sh $SC/probe.d/$f.sh" Bash "$WT"
done
ZONE=$SANDBOX/zone/specs
mkdir -p "$ZONE/demo"
printf 'project: fixture\nlayout: 1\n' >"$ZONE/planwright-spec-root.yml"
printf '# Demo\n' >"$ZONE/demo/requirements.md"
printf 'ls > %s/demo/note.md\n' "$ZONE" >"$SC/probe.d/zone.sh"
HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=$SC" "PLANWRIGHT_WORKER_SESSION_RECORD=$REC" "PLANWRIGHT_WORKER_SPEC_ROOT=$ZONE")
assert_allow "the spec-root zone approves a typed redirect (the control for the next row)" "ls > $ZONE/demo/note.md" Bash "$WT"
assert_defer "the spec-root zone does not reach a probe body" "sh $SC/probe.d/zone.sh" Bash "$WT"
under
assert_defer "a probe holding a write" "sh $SC/probe.d/write.sh" Bash "$WT"
assert_defer "a probe holding a redirect" "sh $SC/probe.d/redir.sh" Bash "$WT"
assert_defer "a probe holding a pipe into a shell" "sh $SC/probe.d/pipe.sh" Bash "$WT"
assert_defer "a probe holding curl" "sh $SC/probe.d/curl.sh" Bash "$WT"
assert_defer "a probe holding a writing substitution" "sh $SC/probe.d/subst.sh" Bash "$WT"
assert_defer "a probe holding a chain into a write" "sh $SC/probe.d/chain.sh" Bash "$WT"
assert_defer "a probe reading another process's environment" "sh $SC/probe.d/environ.sh" Bash "$WT"
assert_defer "a probe that runs itself" "sh $SC/probe.d/self.sh" Bash "$WT"
assert_defer "a probe that runs a writing probe" "sh $SC/probe.d/inner-write.sh" Bash "$WT"
assert_defer "a comment-only probe" "sh $SC/probe.d/empty.sh" Bash "$WT"
assert_defer "an empty probe" "sh $SC/probe.d/zero.sh" Bash "$WT"
assert_defer "a probe with a NUL byte" "sh $SC/probe.d/nul.sh" Bash "$WT"
assert_defer "a probe past the size cap" "sh $SC/probe.d/big.sh" Bash "$WT"
assert_defer "a probe not ending in .sh" "sh $SC/probe.d/ok.txt" Bash "$WT"
assert_defer "a probe directly in the scratch root, not in a directory of its own" "sh $SC/ok.sh" Bash "$WT"
assert_defer "a probe two directories down" "sh $SC/probe.d/deeper/ok.sh" Bash "$WT"
assert_defer "a probe in a hidden directory" "sh $SC/.hidden/ok.sh" Bash "$WT"
assert_defer "a hidden probe" "sh $SC/probe.d/.dot.sh" Bash "$WT"
assert_defer "a probe named with a space" "sh '$SC/probe.d/we ird.sh'" Bash "$WT"
assert_defer "a symlinked probe" "sh $SC/probe.d/link.sh" Bash "$WT"
assert_defer "a probe symlinked to outside the root" "sh $SC/probe.d/outlink.sh" Bash "$WT"
assert_defer "a probe hard-linked to a file outside the root" "sh $SC/probe.d/hard.sh" Bash "$WT"
assert_defer "a probe through the symlinked directory that leaves the root" "sh $SC/escape/ok.sh" Bash "$WT"
assert_defer "a probe outside the scratch root" "sh $OUT_DIR/probe.d/ok.sh" Bash "$WT"
assert_defer "a probe in a sibling directory of the same name prefix" "sh ${SC}-evil/probe.d/ok.sh" Bash "$WT"
assert_defer "a probe through a .. component" "sh $SC/probe.d/../probe.d/ok.sh" Bash "$WT"
assert_defer "a probe that does not exist" "sh $SC/probe.d/missing.sh" Bash "$WT"
assert_defer "a probe in the worktree" "sh $WT/f" Bash "$WT"
assert_defer "a relative probe path" "sh probe.d/ok.sh" Bash "$SC"
assert_defer "a probe with an argument" "sh $SC/probe.d/ok.sh arg" Bash "$WT"
assert_defer "a probe with an option" "sh -x $SC/probe.d/ok.sh" Bash "$WT"
assert_defer "a probe under bash" "bash $SC/probe.d/ok.sh" Bash "$WT"
assert_defer "a probe through sh -c" "sh -c 'sh $SC/probe.d/ok.sh'" Bash "$WT"
assert_defer "a probe with a redirect" "sh $SC/probe.d/ok.sh > out.txt" Bash "$WT"
assert_defer "a probe with a chain into a write" "sh $SC/probe.d/ok.sh && rm g" Bash "$WT"
assert_defer "a probe with a leading write" "rm g && sh $SC/probe.d/ok.sh" Bash "$WT"
assert_defer "a probe with a pipe into a shell" "sh $SC/probe.d/ok.sh | sh" Bash "$WT"
assert_defer "a probe with a trailing command after ;" "sh $SC/probe.d/ok.sh; rm g" Bash "$WT"
assert_defer "a probe through a substitution" "sh \$(printf %s $SC/probe.d/ok.sh)" Bash "$WT"
assert_defer "a probe through a variable the shell expands" "P=$SC/probe.d/ok.sh; sh \$P; rm g" Bash "$WT"
assert_defer "a probe run as the verb" "$SC/probe.d/ok.sh" Bash "$WT"
assert_defer "a probe sourced" ". $SC/probe.d/ok.sh" Bash "$WT"
assert_defer "a probe under bats" "bats $SC/probe.d/ok.sh" Bash "$WT"

# The recorded scratch root is the only one trusted, and only while the
# session's own TMPDIR names it.
under "$REC" "$OUT_DIR"
assert_defer "a probe while TMPDIR names another directory" "sh $SC/probe.d/ok.sh" Bash "$WT"
HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=$SC")
assert_defer "a probe with no session record" "sh $SC/probe.d/ok.sh" Bash "$WT"
HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=$SC" "PLANWRIGHT_WORKER_SESSION_RECORD=$STATE/missing.record")
assert_defer "a probe with an unreadable session record" "sh $SC/probe.d/ok.sh" Bash "$WT"
printf 'policy=\nunit_branch=%s\nworktree_root=%s\npr_base=origin/main\nworker_base_merge=allow\n' \
  "$CORPUS_UNIT_BRANCH" "$WT" >"$STATE/noscratch.record"
under "$STATE/noscratch.record"
assert_defer "a probe when the record names no scratch root" "sh $SC/probe.d/ok.sh" Bash "$WT"
ln -s "$SC" "$CORPUS_BOX/scratch.link"
under "$REC" "$CORPUS_BOX/scratch.link"
assert_allow "a probe while TMPDIR reaches the root through a symlink" "sh $SC/probe.d/ok.sh" Bash "$WT"
assert_allow "a probe typed through the TMPDIR spelling of the root" "sh $CORPUS_BOX/scratch.link/probe.d/ok.sh" Bash "$WT"
under "$REC" "$SC"
assert_defer "a probe typed through a symlink that is not the session's TMPDIR" "sh $CORPUS_BOX/scratch.link/probe.d/ok.sh" Bash "$WT"
assert_defer "a probe typed with a .. component through the root" "sh $SC/../scratch/probe.d/ok.sh" Bash "$WT"
# A relative TMPDIR names the root only from the hook's own directory; the
# shell runs the command from the payload's, so it is never trusted.
ORIG_PWD=$PWD
cd "$CORPUS_BOX" || exit 1
under "$REC" "scratch"
assert_defer "a probe while TMPDIR is a relative path" "sh scratch/probe.d/ok.sh" Bash "$WT"
cd "$ORIG_PWD" || exit 1
printf 'policy=\nunit_branch=%s\nworktree_root=%s\npr_base=origin/main\nworker_base_merge=allow\nscratch_root=%s\n' \
  "$CORPUS_UNIT_BRANCH" "$WT" "$SC" >"$STATE/nolog.record"
under "$STATE/nolog.record"
assert_defer "a probe when the record names no audit log home" "sh $SC/probe.d/ok.sh" Bash "$WT"
under

echo "### a probe beside a writer in the same command, under each write policy"
# The hook reads the probe before an earlier segment of the same command could
# rewrite it, so a probe approved beside any other segment would run content
# that was never judged. The scratch arm is what makes those writers approvable.
for col in 3 4; do
  under "$STATE/record.$col"
  assert_allow "policy column $col: the lone probe" "sh $SC/probe.d/ok.sh" Bash "$WT"
  want=$(sha256sum <"$SC/probe.d/ok.sh")
  want=${want%% *}
  if grep -q " probe_sha256=$want\$" "$STATE/audit.$col/record.$col.log"; then
    pass "policy column $col: the audit line carries the digest of the probe's text"
  else
    fail "policy column $col: the audit line must carry the SHA-256 of the probe's text"
  fi
  assert_defer "policy column $col: a redirect rewrites it, then it runs" "printf 'rm g\\n' > $SC/probe.d/ok.sh && sh $SC/probe.d/ok.sh" Bash "$WT"
  assert_defer "policy column $col: the same with ;" "printf 'rm g\\n' > $SC/probe.d/ok.sh; sh $SC/probe.d/ok.sh" Bash "$WT"
  assert_defer "policy column $col: through \$TMPDIR" "printf 'rm g\\n' > \$TMPDIR/probe.d/ok.sh && sh \$TMPDIR/probe.d/ok.sh" Bash "$WT"
  assert_defer "policy column $col: tee rewrites it" "printf 'rm g\\n' | tee $SC/probe.d/ok.sh && sh $SC/probe.d/ok.sh" Bash "$WT"
  assert_defer "policy column $col: cp rewrites it" "cp $SC/probe.d/write.sh $SC/probe.d/ok.sh && sh $SC/probe.d/ok.sh" Bash "$WT"
  assert_defer "policy column $col: mv rewrites it" "mv $SC/probe.d/write.sh $SC/probe.d/ok.sh && sh $SC/probe.d/ok.sh" Bash "$WT"
  assert_defer "policy column $col: a loop rewrites it after the first run" "for n in 1 2; do sh $SC/probe.d/ok.sh; cp $SC/probe.d/write.sh $SC/probe.d/ok.sh; done" Bash "$WT"
  assert_defer "policy column $col: it runs, then a writer follows" "sh $SC/probe.d/ok.sh && printf 'x' > $SC/probe.d/ok.sh" Bash "$WT"
done
under

echo "### the router's kind-flag form"
SR_WT="$SANDBOX/install/worktree"
mkdir -p "$SR_WT/scripts" "$SR_WT/tests"
: >"$SR_WT/.git"
: >"$SR_WT/tests/ok.sh"
: >"$SR_WT/tests/test-ok.sh"
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
assert_defer "the test form under /bin/bash" "$CR --test tests/test-ok.sh -- /bin/bash tests/test-ok.sh" Bash "$SR_WT"
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
