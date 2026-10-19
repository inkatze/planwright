#!/bin/bash
# Tests for scripts/worker-command-guard.sh: argument-independent command
# substitution (REQ-E1.3), and the position fixtures checked against an
# over-broad variant of the guard that each one must catch.
# tests/test-worker-command-guard.sh holds the suite's overview; all its files
# source tests/lib/worker-command-guard-harness.sh, which states the contract.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"

# The substitution fixtures' own checkout. Its script named with a literal
# `$(…)` is what a guard judging the unexpanded text would find and trust.
SUBST_CWD="$SANDBOX/subst"
mkdir -p "$SUBST_CWD/scripts"
: >"$SUBST_CWD/.git"
: >"$SUBST_CWD/scripts/ok.sh"
mkdir -p "$SUBST_CWD/tests"
: >"$SUBST_CWD/tests/ok.bats"
: >"$SUBST_CWD/scripts/\$(echo ok).sh"

# The REQ-E1.3 fixtures that depend on the argument-independence check: each
# defers against the guard and allows against the over-broad variant that
# admits a `$(…)` wherever its inner text passes the read-only analysis.
SUBST_POSITION_FIXTURES=(
  "find . \$(echo -maxdepth 0 -exec id ';')"
  "cat \$(git ls-files)"
  "printf \"\$(cat f)\" x"
  "test \$(echo -v) 'a[\$(id)]'"
  "test -n \$(git status --porcelain)"
  "[ -f \$(echo '*') ]"
  "scripts/\$(echo ok).sh"
  "bash scripts/\$(echo ok).sh"
  "x=\$(git log -1) && find . \$x"
  "x=\$(git ls-files) && cat \$x"
  "y=\$(git ls-files); x=\$y && cat \$x"
  "f=\$(cat f) && printf \"\$f\" x"
  "echo \$(git ls-files) && ls \$_"
  "x=\$(git ls-files) && ls \"\$x\""
  "x=\$(git ls-files) && ls \${x}"
  "x=\$(git ls-files) && ls \$=x"
  "printf -- \"\$(cat f)\" x"
  "x=\$(cat f); echo \$(stat \$x)"
  "echo \$(git ls-files); echo \$(ls \$_)"
  "x=\$(git ls-files); echo \"\$(ls \"\$x\")\""
  "while ls \$_; do echo \$(git ls-files); done"
  "until stat \$_; do echo \$(git ls-files); done"
  "echo \$(cat f) | read -r y; stat \$y"
)

REAL_HOOK=$HOOK
echo "### REQ-E1.3 — argument-independent command substitution"
HOOK_ENV=("PLANWRIGHT_ROOT=$PLUGIN_ROOT")
assert_allow "REQ-E1.3: a plugin script fed a substitution" \
  "$PLUGIN_ROOT/scripts/plug.sh write --head \$(git rev-parse HEAD)" Bash "$PLUGIN_CWD"
HOOK_ENV=()
assert_allow "REQ-E1.3: a quoted substitution as a test operand in a wait" \
  "until [ -z \"\$(git status --porcelain)\" ]; do sleep 5; done" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: a repo script fed a substitution" "scripts/ok.sh --head \$(git rev-parse HEAD)" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: bash <script> fed a substitution" "bash scripts/ok.sh \$(git rev-parse HEAD)" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: echo of a quoted substitution" "echo \"head=\$(git rev-parse HEAD)\"" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: printf past a literal format" "printf '%s\\n' \"\$(git log -1 --format=%h)\"" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: a substitution assigned, then echoed" "h=\$(git rev-parse HEAD) && echo \"\$h\"" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: a substitution assigned, then handed to a script" \
  "h=\$(git rev-parse HEAD); scripts/ok.sh --head \"\$h\"" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: a read-only pipeline inside" "echo \"\$(git log --oneline | head -1)\"" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: quotes inside the substitution" "echo \$(git log --format='%h %s' -1)" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: double quotes nested in a quoted substitution" \
  "echo \"\$(git log --format=\"%h\" -1)\"" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: two quoted substitutions around a binary test" \
  "[ \"\$(git rev-parse HEAD)\" = \"\$(git rev-parse origin/main)\" ] && echo same" Bash "$SUBST_CWD"
for c in "${SUBST_POSITION_FIXTURES[@]}"; do
  assert_defer "REQ-E1.3: output reaching a position that reads it: $c" "$c" Bash "$SUBST_CWD"
done
assert_defer "REQ-E1.3: the -v operand form" "test -v \"\$(cat f)\"" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a -v operand through a variable" "v=\$(cat f) && test -v \"\$v\"" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an escaped -exec terminator inside" "find . \$(echo -maxdepth 0 -exec id \\;)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a substitution in the verb position" "\$(echo ls) f" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a substitution as the script path" "bash \$(echo scripts/ok.sh)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an environment prefix from a substitution" "x=\$(git log -1) git status" Bash "$SUBST_CWD"
# An assignment holding a substitution exits with the inner command's
# status, so an assignment after its `&&` may never run.
assert_defer "REQ-E1.3: a re-assignment after && may not run" \
  "x=\$(cat f g) && x=README.md; cat \$x" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an assignment after a substitution's && is not modelled" \
  "x=\$(git rev-parse HEAD) && y=-name; find . \$y a.sh" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: a substitution assignment carries across ;" \
  "x=\$(git rev-parse HEAD); y=a; echo \"\$x\" \$y" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner command that is not read-only" "echo \$(rm -rf build)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner write redirect" "echo \$(cat f > g)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner list, not a pipeline" "echo \$(git status; git log -1)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner && list" "echo \$(git status && git log -1)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner newline" "echo \"\$(git status
git log -1)\"" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner background job" "echo \$(git status & git log -1)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner reserved word in command position" "echo \$(then cat f)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner do in command position" "echo \$(do cat f)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner trailing pipe" "echo \$(cat f |)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner empty pipeline segment" "echo \$(cat f | | cat)" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: an inner read redirect alone" "echo \$(<f)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner reserved word after a redirect" "echo \$(<f then cat f)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner do after a redirect" "echo \$(<f do cat f)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner reserved word after an fd redirect" "echo \$(2>/dev/null then cat f)" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: an inner command after a redirect" "echo \$(<f cat)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner assignment" "echo \$(x=1)" Bash "$SUBST_CWD"
# Trusted repo code may write, so it is approvable on its own but never as a
# substitution's read-only command.
assert_defer "REQ-E1.3: an inner repo script" "echo \$(scripts/ok.sh)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner ./ repo script" "echo \$(./scripts/ok.sh)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner bash <script>" "echo \$(bash scripts/ok.sh)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner mise run" "echo \$(mise run check)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner lefthook run" "echo \$(lefthook run pre-commit)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner bats run" "echo \$(bats tests/ok.bats)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner fish -c running a script" "echo \$(fish -c 'scripts/ok.sh')" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: the same script runs on its own" "scripts/ok.sh" Bash "$SUBST_CWD"
# A name only inferred to carry output (an outer name inside a substitution,
# `$_`, an untracked name) gains no position a plain opaque value lacks.
assert_defer "REQ-E1.3: an outer name inside a substitution reaching a script" "echo \$(scripts/ok.sh \$HOME)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: \$_ after a substitution reaching a script" "echo \$(git log -1); scripts/ok.sh \$_" Bash "$SUBST_CWD"
# The opaque-word rules already defer this one; it pins that the inference
# never upgrades an untracked name to known output.
assert_defer "REQ-E1.3: an untracked name beside a substitution is never known output" \
  "scripts/ok.sh \"\$HOME\" \$(git log -1)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an untracked name beside a substitution reaching ls" \
  "ls \"\$HOME\" \$(git log -1)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a name assigned from \$_ reaching ls" "echo \$(git log -1); y=\$_; ls \$y" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a name assigned from an untracked name reaching ls" \
  "echo \$(git log -1); y=\$HOME; ls \$y" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: a name assigned from \$_ echoed" "echo \$(git log -1); y=\$_; echo \"\$y\"" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a name assigned from \$_ reaching a script" \
  "echo \$(git log -1); y=\$_; scripts/ok.sh \$y" Bash "$SUBST_CWD"
assert_allow "REQ-E1.3: an untracked name echoed beside a substitution" "echo \"\$HOME\" \"\$(git log -1)\"" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: substitution output in a numeric printf conversion" "printf %d \"\$(cat f)\"" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: substitution output in a * printf width" "printf -- '%*s' \"\$(cat f)\" x" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a tainted variable in a numeric printf conversion" "x=\$(cat f); printf %u \"\$x\"" Bash "$SUBST_CWD"
# A word joining known output to an inferred name is only as trusted as the
# inferred part.
assert_defer "REQ-E1.3: a substitution joined to an untracked name reaching a script" \
  "scripts/ok.sh \"\$(git log -1)\$HOME\"" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a tainted variable joined to an untracked name reaching a script" \
  "x=\$(git log -1); scripts/ok.sh \$HOME\$x" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: \$_ joined to a substitution reaching a script" \
  "echo \$(git log -1); scripts/ok.sh \$_\$(git log -1)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a mixed value assigned, then handed to a script" \
  "x=\$(git log -1); y=\$HOME\$x; scripts/ok.sh \$y" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a quoted mixed value assigned, then handed to a script" \
  "y=\"\$(git log -1)\$HOME\"; scripts/ok.sh \$y" Bash "$SUBST_CWD"
# A `cd` is approvable only in a real repository at its canonical path, so the
# inner-cd fixtures run in one; a carried inner cd would move the directory
# the later script path is checked against.
SUBST_REPO="$(cd "$SANDBOX" && pwd -P)/substrepo"
mkdir -p "$SUBST_REPO/scripts"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$SUBST_REPO"
: >"$SUBST_REPO/scripts/ok.sh"
write_record "$SANDBOX/substrepo.record" "$SUBST_REPO"
HOOK_ENV=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1" "PLANWRIGHT_WORKER_SESSION_RECORD=$SANDBOX/substrepo.record")
assert_allow "REQ-E1.3: the inner-cd repository approves a plain cd" "cd scripts && ls" Bash "$SUBST_REPO"
assert_defer "REQ-E1.3: an inner cd" "echo \$(cd scripts)" Bash "$SUBST_REPO"
assert_defer "REQ-E1.3: an inner cd never carries past &&" "echo \$(cd scripts) && bash ok.sh" Bash "$SUBST_REPO"
assert_defer "REQ-E1.3: an inner cd never carries past ;" "echo \$(cd scripts); bash ok.sh" Bash "$SUBST_REPO"
assert_defer "REQ-E1.3: an inner loop" "echo \$(for f in a; do echo \$f; done)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an unclosed substitution" "echo \$(git status" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a substitution in a case head" "case \$(git rev-parse HEAD) in a) echo x ;; esac" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a substitution in a case pattern" "case a in \$(git log -1)) echo x ;; esac" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a substitution in a loop head" "for f in \$(git ls-files); do echo \$f; done" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a substitution inside fish -c" "fish -c 'echo \$(git status)'" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a substitution reaching fish -c" "fish -c \"echo \$(git status)\"" Bash "$SUBST_CWD"
# Regression-only: these defer by the scan or the redirect rules, not the
# argument-independence check.
assert_defer "REQ-E1.3: a substitution as a read redirect source" "cat < \$(echo f)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a substitution as a write redirect target" "echo x > \$(echo f)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a nested substitution" "echo \$(echo \$(id))" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a backtick inside a substitution" "echo \$(echo \`id\`)" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a backtick" "echo \`id\`" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: a closing parenthesis inside a quote" "echo \"\$(grep ')' f)\"" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an opening parenthesis inside a quote" "echo \"\$(grep '(' f)\"" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an escaped closing parenthesis" "echo \$(echo a\\))" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: arithmetic expansion" "echo \$((1 + 2))" Bash "$SUBST_CWD"
assert_defer "REQ-E1.3: an inner subshell" "echo \$( (id) )" Bash "$SUBST_CWD"

echo "### REQ-E1.3 — the position fixtures discriminate against an over-broad variant"
# The variant admits a substitution wherever its inner text passes the
# read-only analysis, so every position fixture must allow there: one that
# deferred anyway would not be testing the argument-independence check.
# The variant reads the deny block beside it, as the guard does.
mkdir -p "$SANDBOX/overbroad/scripts" "$SANDBOX/overbroad/config"
cp "$REPO_ROOT/config/worker-settings.json" "$SANDBOX/overbroad/config/"
awk '/^subst_reach_ok\(\) \{$/ { print "subst_reach_ok() { return 0; }"; skip = 1; next }
  skip && /^}$/ { skip = 0; next }
  !skip' "$REAL_HOOK" >"$SANDBOX/overbroad/scripts/worker-command-guard.sh"
if grep -q '^subst_reach_ok() { return 0; }$' "$SANDBOX/overbroad/scripts/worker-command-guard.sh"; then
  pass "the over-broad variant replaced the position check"
else
  fail "the over-broad variant found no position check to replace"
fi
HOOK="$SANDBOX/overbroad/scripts/worker-command-guard.sh"
for c in "${SUBST_POSITION_FIXTURES[@]}"; do
  assert_allow "REQ-E1.3 over-broad variant admits: $c" "$c" Bash "$SUBST_CWD"
done
HOOK=$REAL_HOOK

finish_suite worker-command-guard-subst
