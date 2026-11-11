#!/bin/bash
# Tests for scripts/worker-command-guard.sh: `nice -n <n>` as a transparent
# prefix (REQ-A1.16), and the read-only `gitleaks detect` and `gh release
# view`/`list` shapes (REQ-A1.17). tests/test-worker-command-guard.sh holds the
# suite's overview; all its files source tests/lib/worker-command-guard-harness.sh,
# which states the contract.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"
# shellcheck source=tests/lib/worker-guard-corpus.sh
. "$REPO_ROOT/tests/lib/worker-guard-corpus.sh"

corpus_sandbox "$SANDBOX/box" "$REPO_ROOT" || {
  echo "FAIL: could not build the corpus sandbox" >&2
  exit 1
}
WT=$CORPUS_WORKTREE
SC=$CORPUS_SCRATCH
OUT_DIR=$CORPUS_OUTSIDE
REC=$CORPUS_BOX/state/record.4
GIT_ISO=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=$SC" "PLANWRIGHT_WORKER_SESSION_RECORD=$REC")
: >"$WT/body.md"
: >"$SC/body.md"
: >"$OUT_DIR/body.md"

echo "### REQ-A1.16 — nice -n <0..19> is a transparent prefix"
assert_allow "A1.16: nice -n 10 git status" "nice -n 10 git status" Bash "$WT"
assert_allow "A1.16: nice -n 0 git status" "nice -n 0 git status" Bash "$WT"
assert_allow "A1.16: nice -n 19 a repo test" "nice -n 19 bash tests/ok.sh" Bash "$WT"
assert_allow "A1.16: nice around timeout" "nice -n 10 timeout 30 git status" Bash "$WT"
assert_allow "A1.16: timeout around nice" "timeout 30 nice -n 10 git status" Bash "$WT"
assert_allow "A1.16: time around nice" "time nice -n 10 git status" Bash "$WT"
assert_defer "A1.16: nice -n 20" "nice -n 20 git status" Bash "$WT"
assert_defer "A1.16: nice -n -5" "nice -n -5 git status" Bash "$WT"
assert_defer "A1.16: nice -5" "nice -5 git status" Bash "$WT"
assert_defer "A1.16: nice --adjustment=5" "nice --adjustment=5 git status" Bash "$WT"
assert_defer "A1.16: nice -n with an unresolved value" "nice -n \"\$X\" git status" Bash "$WT"
assert_defer "A1.16: a quoted value" "nice -n \"10\" git status" Bash "$WT"
assert_defer "A1.16: a padded value" "nice -n 010 git status" Bash "$WT"
assert_defer "A1.16: bare nice" "nice" Bash "$WT"
assert_defer "A1.16: nice -n with nothing to run" "nice -n 10" Bash "$WT"
assert_defer "A1.16: nice -n 10 around a writer" "nice -n 10 rm -rf $OUT_DIR/x" Bash "$WT"
assert_defer "A1.16: nice -n 10 around a push" "nice -n 10 git push origin main" Bash "$WT"
assert_defer "A1.16: nice -n 10 around bash -c" "nice -n 10 bash -c x" Bash "$WT"
assert_defer "A1.16: nested nice" "nice -n 10 nice -n 5 git status" Bash "$WT"
assert_defer "A1.16: nice around time" "nice -n 10 time git status" Bash "$WT"
assert_defer "A1.16: nice around cd" "nice -n 10 cd sub" Bash "$WT"

echo "### REQ-A1.17 — gitleaks detect, read-only options only"
assert_allow "A1.17: a worktree file" "gitleaks detect --no-git --source $WT/body.md --no-banner" Bash "$WT"
assert_allow "A1.17: a relative worktree file" "gitleaks detect --no-git --source body.md --no-banner" Bash "$WT"
assert_allow "A1.17: a scratch file" "gitleaks detect --no-git --source $SC/body.md --no-banner" Bash "$WT"
assert_allow "A1.17: --source=<path>" "gitleaks detect --no-git --source=$WT/body.md" Bash "$WT"
assert_allow "A1.17: --verbose --redact" "gitleaks detect --no-git --verbose --redact --source $WT/body.md" Bash "$WT"
assert_allow "A1.17: gitleaks detect before a chained command" "gitleaks detect --no-git --source $WT/body.md --no-banner && git status" Bash "$WT"
assert_defer "A1.17: --report-path" "gitleaks detect --report-path f --source $WT/body.md" Bash "$WT"
assert_defer "A1.17: -r" "gitleaks detect -r f --source $WT/body.md" Bash "$WT"
assert_defer "A1.17: --baseline-path" "gitleaks detect --baseline-path f --source $WT/body.md" Bash "$WT"
assert_defer "A1.17: --config" "gitleaks detect --config f --source $WT/body.md" Bash "$WT"
assert_defer "A1.17: --source /etc" "gitleaks detect --source /etc" Bash "$WT"
assert_defer "A1.17: --source ../x" "gitleaks detect --source ../x" Bash "$WT"
assert_defer "A1.17: --source outside both roots" "gitleaks detect --no-git --source $OUT_DIR/body.md" Bash "$WT"
assert_defer "A1.17: --source with an unresolved variable" "gitleaks detect --no-git --source \$X" Bash "$WT"
assert_defer "A1.17: --source with no operand" "gitleaks detect --no-git --source" Bash "$WT"
assert_defer "A1.17: any other option" "gitleaks detect --no-git --log-opts x --source $WT/body.md" Bash "$WT"
assert_defer "A1.17: a clustered short option" "gitleaks detect -vr f --source $WT/body.md" Bash "$WT"
HOOK_ENV=("${GIT_ISO[@]}")
assert_defer "A1.17: no session record, no worktree to hold the source" "gitleaks detect --no-git --source $WT/body.md --no-banner" Bash "$WT"
HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=$SC" "PLANWRIGHT_WORKER_SESSION_RECORD=$REC")
assert_defer "A1.17: another gitleaks verb" "gitleaks protect --source $WT/body.md" Bash "$WT"
assert_defer "A1.17: bare gitleaks" "gitleaks" Bash "$WT"

echo "### REQ-A1.17 — gh release view and list, no web and no repo override"
assert_allow "A1.17: gh release view" "gh release view v1 --json tagName" Bash "$WT"
assert_allow "A1.17: gh release view latest" "gh release view" Bash "$WT"
assert_allow "A1.17: gh release list" "gh release list" Bash "$WT"
assert_allow "A1.17: gh release list --limit" "gh release list --limit 5" Bash "$WT"
assert_defer "A1.17: gh release view --web" "gh release view --web" Bash "$WT"
assert_defer "A1.17: gh release view -w" "gh release view v1 -w" Bash "$WT"
assert_defer "A1.17: gh release view -R" "gh release view -R other/repo" Bash "$WT"
assert_defer "A1.17: gh release view --repo" "gh release view v1 --repo other/repo" Bash "$WT"
assert_defer "A1.17: gh release view --repo=" "gh release view v1 --repo=other/repo" Bash "$WT"
assert_defer "A1.17: gh release view -Rother/repo" "gh release view v1 -Rother/repo" Bash "$WT"
assert_defer "A1.17: gh release list -R" "gh release list -R other/repo" Bash "$WT"
assert_defer "A1.17: gh release create" "gh release create v1" Bash "$WT"
assert_defer "A1.17: gh release delete" "gh release delete v1" Bash "$WT"
assert_defer "A1.17: gh release download" "gh release download v1" Bash "$WT"
assert_defer "A1.17: gh release edit" "gh release edit v1" Bash "$WT"
assert_defer "A1.17: bare gh release" "gh release" Bash "$WT"

finish_suite worker-command-guard-wrappers
