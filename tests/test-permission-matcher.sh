#!/bin/bash
# Fixture-driven permission-matcher test for the worker profile's deny, allow,
# and path rules (guard-coverage Task 1; REQ-A1.1, REQ-A1.2, REQ-H1.3; D-4).
#
# WHAT THIS PINS. config/worker-settings.json's deny block is planwright's
# best-effort glob layer against a worker force-pushing, pushing to main, or
# bypassing the githooks/ backstop, and its path rules keep the file tools
# off the paths the worker guard refuses. A base merge and a never-pushed
# rewrite are policy acts the policy guard decides, so their rows expect the
# glob layer to leave them alone.
# Glob rules are easy to write and easy to silently break: a rule whose `:*`
# lands mid-pattern never fires, a rule anchored at end-of-string is evaded by
# one trailing flag, and a rule can be deleted with a green suite if nothing
# asserts it. This test closes all three by asserting a table of real commands
# and a table of file-tool calls against a DOCUMENTED MODEL of Claude Code's
# matcher (tests/lib/permission-matcher.sh, D-4) plus the real shipped config.
#
# WHAT IT DOES NOT PIN. The model is a re-implementation, not the matcher: this
# test verifies config-vs-model equivalence only. Real-matcher fidelity is the
# manual re-verify recorded as risk row 1 of the kickoff brief. The modeled
# behavior version, sources consulted, modeling boundaries, and the unsettled
# assumption MA-1 are all in docs/permission-matcher-model.md.
#
#   Modeled behavior version: Claude Code CLI 2.1.314 / docs as of 2026-11-01.
#
# The passes:
#   A. Model self-validation — every worked example in Claude Code's own
#      permission docs is replayed against the model. This is the ground-truth
#      differential check: the model must reproduce the documentation's stated
#      match/no-match outcomes, not the author's expectations of them.
#   B. Fixture table — each row is an invocation plus its expected outcome and
#      an explicit class: `load-bearing` (expected-deny regression guard),
#      `legit` (an operation a worker must keep being able to run),
#      `residual` (honest documentation of a current allow the glob layer does
#      not reach; the githooks/ backstop or an accepted residual covers it), or
#      `overblock` (a benign command this deny list denies anyway — an accepted,
#      fail-safe cost), or, for a file-tool path row only, `guard` (a path the
#      profile's rules leave open and a PreToolUse hook refuses instead, the
#      row naming the hook). Class and expectation are cross-checked, so a
#      mislabeled row fails.
#   C. Fail-closed — an empty deny set and an unparseable config must both
#      error, never read as a vacuously green table (REQ-H1.3).
#   D. No dead rules — every deny rule must be exercised by at least one
#      fixture row, so a rule that can never fire cannot ship unnoticed.
#   E. Mutation — for every deny rule that is the SOLE cover for some
#      expected-deny row, removing it flips that row. Rules that are covered
#      redundantly are declared in REDUNDANT_BY_DESIGN with a reason, so
#      redundancy is a reviewed decision rather than silent dead weight.
#   F. No unexercised allow rules — every Bash allow rule is matched by an
#      expected-allow row, so a widening ships with the row showing it.
#   G. The static allow set names no verb REQ-G1.1 excludes.
#   H. Path rules — the Read/Edit deny rules against a path fixture table,
#      every path deny rule exercised, every non-Bash allow entry accounted for.
#
# Runs standalone: ./tests/test-permission-matcher.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SETTINGS="$REPO_ROOT/config/worker-settings.json"
MODEL="$REPO_ROOT/tests/lib/permission-matcher.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required to run this suite" >&2
  exit 1
fi
for f in "$SETTINGS" "$MODEL"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: required file missing: $f" >&2
    exit 1
  fi
done

# shellcheck source=tests/lib/permission-matcher.sh
. "$MODEL"

# ---------------------------------------------------------------------------
# Pass A — model self-validation against Claude Code's documented examples.
#
# Every row below is a match/no-match claim the permission documentation makes
# in prose or in a worked example (see docs/permission-matcher-model.md for the
# source lines). If the model stops reproducing one, the model is wrong — not
# the fixture table.
# ---------------------------------------------------------------------------
expect_match() {
  if pm_matches "$1" "$2"; then
    ok "doc example: Bash($1) matches '$2'"
  else
    fail "doc example: Bash($1) should match '$2'"
  fi
}
expect_no_match() {
  if pm_matches "$1" "$2"; then
    fail "doc example: Bash($1) should NOT match '$2'"
  else
    ok "doc example: Bash($1) does not match '$2'"
  fi
}

# Exact-match patterns (no wildcard) match the whole command and nothing more.
expect_match 'npm run build' 'npm run build'
expect_no_match 'npm run build' 'npm run build --watch'
expect_no_match 'npm run build' 'sudo npm run build'
# Trailing ` *` is the word-boundary form: prefix then a space or end-of-string.
expect_match 'ls *' 'ls -la'
expect_match 'ls *' 'ls'
expect_no_match 'ls *' 'lsof'
# Without the space there is no boundary constraint.
expect_match 'ls*' 'ls -la'
expect_match 'ls*' 'lsof'
# `:*` is an equivalent spelling of a trailing ` *`.
expect_match 'ls:*' 'ls -la'
expect_match 'ls:*' 'ls'
expect_no_match 'ls:*' 'lsof'
# `:*` is recognized ONLY at the end; elsewhere the colon is a literal.
expect_no_match 'git:* push' 'git push'
expect_match 'git:* push' 'git:x push'
# A wildcard matches any sequence including spaces, at any position.
expect_match 'npm run test *' 'npm run test --coverage'
expect_match 'npm *' 'npm install'
expect_match '* install' 'npm install'
expect_match 'git * main' 'git checkout main'
expect_match 'git * main' 'git log --oneline main'
expect_match 'git * main' 'git push origin main'
expect_match 'git * main' 'git merge main'
expect_no_match 'git * main' 'git checkout maintenance'

# Compound commands: a rule must match each subcommand independently, so a
# prefix rule for one subcommand does not carry the whole compound string.
pm_load_rules 'Bash(never-run *)' '' 'Bash(safe-cmd *)' || {
  echo "FAIL: pm_load_rules rejected the compound-command probe set" >&2
  exit 1
}
for compound in \
  'safe-cmd && other-cmd' \
  'safe-cmd ; other-cmd' \
  'safe-cmd | other-cmd' \
  'safe-cmd |& other-cmd' \
  'safe-cmd || other-cmd' \
  'safe-cmd & other-cmd'; do
  if [ "$(pm_decide "$compound")" = "allow" ]; then
    fail "compound: 'Bash(safe-cmd *)' must not allow '$compound'"
  else
    ok "compound: 'Bash(safe-cmd *)' does not allow '$compound'"
  fi
done
if [ "$(pm_decide 'safe-cmd one && safe-cmd two')" = "allow" ]; then
  ok "compound: every subcommand allowed => allow"
else
  fail "compound: 'safe-cmd one && safe-cmd two' should be allowed"
fi
if [ "$(pm_decide 'safe-cmd one && never-run two')" = "deny" ]; then
  ok "compound: one denied subcommand denies the whole call"
else
  fail "compound: a denied subcommand must deny the whole compound call"
fi
# A deny rule matches past any leading environment assignment, in every spelling
# a shell accepts: bare, quoted (double and single), backslash-escaped,
# tab-separated, and several stacked. A naive split on the first space mangles
# the quoted and tab forms and leaves a remainder no deny pattern can match.
tab_ch="$(printf '\t')"
for assigned in \
  'FOO=bar never-run x' \
  'FOO="a b" never-run x' \
  "FOO='a b' never-run x" \
  'FOO=a\ b never-run x' \
  "FOO=bar${tab_ch}never-run x" \
  'A=1 B="x y" C=3 never-run x' \
  'FOO= never-run x'; do
  if [ "$(pm_decide "$assigned")" = "deny" ]; then
    ok "deny matches past a leading assignment: ${assigned%% never-run*} …"
  else
    fail "deny must match past the leading assignment in: $assigned"
  fi
done
# An unterminated quote is not a strippable assignment: the command is
# unparseable, and an unparseable command falls through to the prompt rather
# than being silently reshaped into something that matches nothing.
if [ "$(pm_decide 'FOO="unterminated never-run x')" = "prompt" ]; then
  ok "an unterminated quoted assignment falls through to the prompt"
else
  fail "an unterminated quoted assignment must not be stripped into a bogus command"
fi
# A bare assignment with no command after it is not a leading assignment.
if [ "$(pm_decide 'FOO=bar')" = "prompt" ]; then
  ok "a bare VAR=value with no command reports prompt"
else
  fail "a bare VAR=value must not be treated as a stripped command"
fi
# A first token that merely contains '=' is not an assignment.
if [ "$(pm_decide './configure --prefix=/usr never-run')" = "prompt" ]; then
  ok "a non-NAME first token containing '=' is not stripped as an assignment"
else
  fail "'./configure --prefix=/usr' must not be stripped as a leading assignment"
fi
# Deny precedes ask ACROSS subcommands, not just within one (doc rule M8: the
# whole rule set is evaluated deny-first; specificity and position never
# reorder it). Unreachable with the shipped config, which ships no ask array,
# but the model claims to implement M8 and an adopter overlay may add one.
pm_load_rules 'Bash(never-run *)' 'Bash(safe-cmd *)' '' || {
  echo "FAIL: pm_load_rules rejected the deny-before-ask probe set" >&2
  exit 1
}
if [ "$(pm_decide 'safe-cmd x && never-run y')" = "deny" ]; then
  ok "deny precedes ask across subcommands (doc rule M8)"
else
  fail "a later subcommand matching deny must outrank an earlier ask match (doc rule M8)"
fi
if [ "$(pm_decide 'safe-cmd x && safe-cmd y')" = "ask" ]; then
  ok "ask still wins when no subcommand matches a deny rule"
else
  fail "an ask match with no deny match must report ask"
fi

# Deny and ask rules reach a command nested in a subshell, a command
# substitution, or a control-flow body (doc rule M9; the documentation's own
# example is an ask rule for `git clean`).
pm_load_rules 'Bash(never-run *)' 'Bash(git clean *)' 'Bash(echo *)' || {
  echo "FAIL: pm_load_rules rejected the nested-command probe set" >&2
  exit 1
}
# shellcheck disable=SC2016 # the nested commands are matched as text, never run
for nested in \
  'cd /tmp && git clean -f' \
  'echo "$(git clean -f)"' \
  '(git clean -f)' \
  'for d in a b; do git clean -f; done'; do
  if [ "$(pm_decide "$nested")" = "ask" ]; then
    ok "doc example: Bash(git clean *) in ask reaches '$nested' (M9)"
  else
    fail "doc example: Bash(git clean *) in ask must reach '$nested' (M9)"
  fi
done
# Lexing the scanner does not reproduce (comments, here-documents, line
# continuations) never reaches allow, and a continuation is joined for deny
# (MB-10).
pm_load_rules 'Bash(never-run *)' '' 'Bash(echo *)' || {
  echo "FAIL: pm_load_rules rejected the unlexed-construct probe set" >&2
  exit 1
}
for unlexed in \
  "echo a # '${PM_NL}other x${PM_NL}echo b # '" \
  "echo \$(cat <<EOF${PM_NL}it's${PM_NL}EOF${PM_NL}other x${PM_NL}echo ')" \
  "echo a \\${PM_NL}b"; do
  if [ "$(pm_decide "$unlexed")" = "prompt" ]; then
    ok "an unlexed construct is never reported allowed (MB-10)"
  else
    fail "an unlexed construct must never be reported allowed (MB-10): $unlexed"
  fi
done
if [ "$(pm_decide "echo a; never-\\${PM_NL}run x")" = "deny" ]; then
  ok "a line continuation is joined before the deny sweep (MB-10)"
else
  fail "a deny-matching command split by a line continuation must be denied (MB-10)"
fi

# Allow still needs every subcommand, nested ones included.
# shellcheck disable=SC2016 # matched as text, never run
if [ "$(pm_decide 'echo "$(never-allowed)"')" = "prompt" ]; then
  ok "an allowed outer command does not carry an unallowed nested one (M9)"
else
  fail "an allowed outer command must not carry an unallowed nested one (M9)"
fi

# A rule that LOOKS like a Bash rule but does not parse must fail closed rather
# than being silently skipped: a deny rule lost to a typo would leave the
# fixture table asserting against a smaller rule set than the config ships.
if pm_load_rules 'Bash(git push --force:*)
Bash(git push origin' '' ''; then
  fail "a malformed Bash(... deny rule must fail closed, not be skipped (REQ-H1.3)"
else
  ok "a malformed Bash(... deny rule fails closed (REQ-H1.3)"
fi
if pm_load_rules 'Bash(git push --force:*)
Bash' '' ''; then
  fail "a bare tool-name Bash deny rule must fail closed rather than be ignored (REQ-H1.3)"
else
  ok "a bare tool-name Bash deny rule fails closed (REQ-H1.3)"
fi
# Non-Bash rules are still ignored silently — they cannot match a command.
if pm_load_rules 'Bash(git push --force:*)
Read(./.env)
Edit' '' ''; then
  ok "non-Bash rules are ignored without failing the load"
else
  fail "non-Bash rules must be ignored, not treated as malformed"
fi

# --- the model doc is tethered to the model ---------------------------------
# The library and this test both cite docs/permission-matcher-model.md as the
# arbiter of the modeled semantics and both restate the modeled Claude Code
# version in their headers. Nothing would otherwise notice the doc being
# renamed, deleted, or version-bumped out from under them.
MODEL_DOC="$REPO_ROOT/docs/permission-matcher-model.md"
if [ -f "$MODEL_DOC" ]; then
  ok "the matcher model doc exists at docs/permission-matcher-model.md (D-4)"
  doc_version="$(sed -n 's/^| Claude Code CLI | \*\*\([0-9.]*\)\*\*.*/\1/p' "$MODEL_DOC" | head -1)"
  if [ -n "$doc_version" ]; then
    ok "the model doc declares a modeled Claude Code version ($doc_version)"
    for f in "$MODEL" "$0"; do
      if grep -Fq "Modeled behavior version: Claude Code CLI $doc_version" "$f"; then
        ok "${f##*/} header restates the doc's modeled version ($doc_version)"
      else
        fail "${f##*/} header does not restate the model doc's modeled version ($doc_version) — bump both together (D-4)"
      fi
    done
  else
    fail "the model doc has no parseable '| Claude Code CLI | **<version>**' row (D-4)"
  fi
else
  fail "docs/permission-matcher-model.md is missing: the model has no documented contract (D-4)"
fi

# ---------------------------------------------------------------------------
# Pass C (part 1) — fail closed before the table is trusted.
# ---------------------------------------------------------------------------
# read_rules <file> <array-name> — print a settings file's permission array,
# one rule per line. Exits non-zero when the file does not parse as JSON, so an
# unparseable config can never be read as "no rules, therefore nothing denied".
read_rules() {
  jq -e -r --arg k "$2" '.permissions[$k] // [] | .[]' "$1" 2>/dev/null
}

# pm_matching_deny_rule backs the unexpected-deny diagnostic in pass B; cover it
# here so the diagnostic itself cannot rot into printing nothing.
pm_load_rules 'Bash(never-run *)' '' '' >/dev/null 2>&1
if [ "$(pm_matching_deny_rule 'safe-cmd x && never-run y')" = 'Bash(never-run *)' ]; then
  ok "pm_matching_deny_rule names the rule that fired"
else
  fail "pm_matching_deny_rule must name the matching deny rule as written"
fi
if pm_matching_deny_rule 'safe-cmd x' >/dev/null; then
  fail "pm_matching_deny_rule must exit non-zero when no deny rule matches"
else
  ok "pm_matching_deny_rule exits non-zero when no deny rule matches"
fi

if pm_load_rules '' '' 'Bash(git status:*)'; then
  fail "an empty deny set must fail closed (REQ-A1.1, REQ-H1.3)"
else
  ok "an empty deny set fails closed (REQ-A1.1, REQ-H1.3)"
fi

tmp="$(mktemp -d)" || {
  echo "FAIL: mktemp failed" >&2
  exit 1
}
trap 'rm -rf "$tmp"' EXIT
printf '{ "permissions": { "deny": [ "Bash(git push --force:*)"\n' >"$tmp/broken.json"
if read_rules "$tmp/broken.json" deny >/dev/null 2>&1; then
  fail "an unparseable config must not yield a rule set (REQ-H1.3)"
else
  ok "an unparseable config yields no rule set and errors (REQ-H1.3)"
fi
printf '{ "permissions": { "deny": [], "allow": [] } }\n' >"$tmp/empty-deny.json"
if pm_load_rules "$(read_rules "$tmp/empty-deny.json" deny)" '' ''; then
  fail "a config with an empty deny array must fail closed (REQ-H1.3)"
else
  ok "a config with an empty deny array fails closed (REQ-H1.3)"
fi

# ---------------------------------------------------------------------------
# Load the REAL shipped rules.
# ---------------------------------------------------------------------------
DENY_RULES="$(read_rules "$SETTINGS" deny)" || {
  echo "FAIL: cannot read .permissions.deny from $SETTINGS" >&2
  exit 1
}
ASK_RULES="$(read_rules "$SETTINGS" ask || true)"
ALLOW_RULES="$(read_rules "$SETTINGS" allow)" || {
  echo "FAIL: cannot read .permissions.allow from $SETTINGS" >&2
  exit 1
}
if pm_load_rules "$DENY_RULES" "$ASK_RULES" "$ALLOW_RULES"; then
  ok "the shipped deny set parses to $(pm_deny_rule_count) Bash rule(s), non-empty (REQ-A1.1)"
else
  echo "FAIL: the shipped deny set parsed to zero Bash rules (REQ-A1.1)" >&2
  exit 1
fi
# A comment opening right after a subshell's close or a redirect operator hides
# the quote the scanner would otherwise pair across lines, and the line between
# is a command (MB-10).
for opener in '(ls)' 'ls >' 'ls <'; do
  hidden="$opener#'${PM_NL}rm -rf build${PM_NL}ls \\'"
  if [ "$(pm_decide "$hidden")" = "prompt" ]; then
    ok "a comment after '$opener' is never reported allowed (MB-10)"
  else
    fail "a comment after '$opener' must not hide a command from the allow check"
  fi
done

# ---------------------------------------------------------------------------
# Pass B — the fixture table.
#
#   expected|class|command|note
#
# expected: deny | allow | prompt   (prompt = no rule matched, so the call
#           falls through to the permission prompt and a headless worker
#           stalls rather than proceeding)
# class:    load-bearing | legit | residual | overblock
#
# Class/expectation consistency is asserted below, so a row cannot be quietly
# relabelled to make a regression look intentional.
# ---------------------------------------------------------------------------
# Rows come from a function rather than a heredoc inside $( ... ): bash 3.2
# reads quotes in that heredoc body as live, so one apostrophe in a row
# stops the whole file from parsing.
fixture_rows() {
  cat <<'ROWS'
deny|load-bearing|git push --force origin HEAD|force flag in the leading position
deny|load-bearing|git push -f origin HEAD|short force flag, leading position
deny|load-bearing|git push origin --force|force flag AFTER the remote
deny|load-bearing|git push origin -f|short force flag after the remote
deny|load-bearing|git push --force-with-lease origin HEAD|lease form, leading position
deny|load-bearing|git push origin --force-with-lease|lease form after the remote
deny|load-bearing|git push --force-with-lease=main:abc123 origin HEAD|=-suffixed lease form; the boundary rules alone miss it
deny|load-bearing|git push --force-if-includes origin HEAD|third force-family flag, caught categorically
deny|load-bearing|git push origin +HEAD:refs/heads/main|+refspec force form onto main
deny|load-bearing|git push origin +feature:feature|+refspec force form onto a feature branch
deny|load-bearing|git push origin main|bare main destination
deny|load-bearing|git push origin HEAD:main|short refspec to main
deny|load-bearing|git push origin HEAD:refs/heads/main|fully-qualified refspec to main
deny|load-bearing|git push origin refs/heads/main|fully-qualified bare destination
deny|load-bearing|git push origin heads/main|abbreviated destination
deny|load-bearing|git push --set-upstream origin main|main destination behind a flag
deny|load-bearing|git push origin main --force-with-lease|flag AFTER main; end-anchored rules alone miss it
deny|load-bearing|git push origin HEAD:main --no-verify|flag after a short main refspec
deny|load-bearing|git push origin HEAD:main --dry-run|BENIGN flag after a short main refspec: only the end-wildcarded main rule can catch this
deny|load-bearing|git push origin main --quiet|BENIGN flag after a bare main destination
deny|load-bearing|git push origin HEAD:refs/heads/main --dry-run|flag after a qualified main refspec
deny|load-bearing|git push origin heads/main --atomic|flag after an abbreviated main refspec
deny|load-bearing|git push origin master|bare master destination
deny|load-bearing|git push origin HEAD:master|short refspec to master
deny|load-bearing|git push origin refs/heads/master|fully-qualified bare master destination
deny|load-bearing|git push origin master --quiet|BENIGN flag after a bare master destination
deny|load-bearing|git push origin HEAD:master --dry-run|BENIGN flag after a short master refspec
deny|load-bearing|git push origin heads/master --atomic|flag after an abbreviated master refspec
deny|load-bearing|git push origin planwright/human-gates/spec|bare spec-branch destination
deny|load-bearing|git push origin HEAD:planwright/human-gates/spec|short refspec to a spec branch
deny|load-bearing|git push origin HEAD:refs/heads/planwright/human-gates/spec|fully-qualified refspec to a spec branch
deny|load-bearing|git push -u origin planwright/human-gates/spec --quiet|BENIGN flag after a bare spec-branch destination
deny|load-bearing|git push origin HEAD:planwright/human-gates/spec --dry-run|BENIGN flag after a short spec-branch refspec
deny|load-bearing|git push origin refs/heads/planwright/human-gates/spec --atomic|flag after a qualified spec-branch refspec
prompt|residual|git pull|a pull is a base merge, which worker_base_merge can grant a worker, so the policy guard refuses it where the value forbids it, never this glob layer
prompt|residual|git pull --rebase origin main|a pull that rebases is a rewrite, which unpushed_rewrite can grant a worker; the policy guard decides it
prompt|residual|git -C . pull origin main|a base merge behind a global option; the policy guard reads -C itself
deny|load-bearing|git push --mirror origin|bulk-ref escape hatch
deny|load-bearing|git push origin --mirror|bulk-ref escape hatch after the remote
deny|load-bearing|git push --all origin|bulk-ref escape hatch
deny|load-bearing|git push origin --all|bulk-ref escape hatch after the remote
allow|residual|git commit --amend|an amend is a never-pushed rewrite, which unpushed_rewrite can grant a worker, so the git commit allow admits it here and the policy guard refuses it where the value or the never-pushed check forbids it
allow|residual|git commit --amend -m "reworded"|--amend -m family; the policy guard decides
allow|residual|git commit --amend -F /tmp/msg|--amend -F family; the policy guard decides
allow|residual|git commit --amend --no-edit|amend with a trailing flag; the policy guard decides
allow|residual|git commit -m "wip" --amend|flag-after-arg amend; the policy guard decides
allow|residual|git commit -a -m "wip" --amend --no-edit|flag-after-arg amend, mid-command; the policy guard decides
allow|residual|git commit --squash HEAD~1|squash, space-separated argument; the policy guard decides
allow|residual|git commit --squash=HEAD~1|squash, =-suffixed argument; the policy guard decides
allow|residual|git commit -m "wip" --squash HEAD~1|flag-after-arg squash; the policy guard decides
allow|residual|git commit --fixup HEAD~1|fixup, space-separated argument; the policy guard decides
allow|residual|git commit --fixup=HEAD~1|fixup, =-suffixed argument; the policy guard decides
allow|residual|git commit --fixup=amend:HEAD~1|--fixup=amend: produces an amend! subject; the policy guard decides
allow|residual|git commit --fixup=reword:HEAD~1|--fixup=reword: produces an amend! subject; the policy guard decides
allow|residual|git commit -m "wip" --fixup=amend:HEAD~1|flag-after-arg =-suffixed fixup; the policy guard decides
deny|load-bearing|git commit --no-verify -m "wip"|hook bypass, leading position
deny|load-bearing|git commit -m "wip" --no-verify|hook bypass after the message
deny|load-bearing|git push --no-verify origin HEAD|pre-push bypass, leading position
deny|load-bearing|git push origin HEAD --no-verify|pre-push bypass after the refspec
deny|load-bearing|git commit -n -m "wip"|-n is the --no-verify short form for git commit
deny|load-bearing|git commit -m "wip" -n|-n after the message
deny|load-bearing|git commit -nm "wip"|bundled short flags smuggling -n
deny|load-bearing|git -c core.hooksPath=/dev/null commit -m "wip"|hooksPath injection via the -c prefix
deny|load-bearing|git -c core.hookspath=/dev/null commit -m "wip"|git config keys are case-insensitive; the all-lowercase spelling
deny|load-bearing|git -c user.name=x -c core.hooksPath=/dev/null commit -m "wip"|hooksPath injection behind another -c
deny|load-bearing|git -c user.name=x -c core.hookspath=/dev/null commit -m "wip"|lowercase hooksPath injection behind another -c
deny|load-bearing|git -c core.hooksPath=/dev/null push origin main|hooksPath injection crossed with push-to-main
deny|load-bearing|git config core.hooksPath /dev/null|persistent hook disable, no intervening flag
deny|load-bearing|git config --local core.hooksPath /dev/null|persistent hook disable, repo scope
deny|load-bearing|git config core.hookspath /dev/null|persistent hook disable, lowercase, no intervening flag
deny|load-bearing|git config --global core.hookspath /dev/null|persistent hook disable, lowercase, user scope
deny|load-bearing|git --config-env=core.hooksPath=HP commit -m "wip"|hooksPath injection via --config-env (a real git 2.55 spelling)
deny|load-bearing|git -c user.name=x --config-env=core.hooksPath=HP commit -m "wip"|--config-env behind another global option
deny|load-bearing|git commit --hooks-path=/dev/null -m "wip"|categorical --hooks-path deny; git 2.55 has no such flag (verified) so this is forward-compat only
deny|load-bearing|git -C . push --force origin feature/topic|GLOBAL-OPTION PREFIX: -C is a real git global option, so the anchored git-push rules never see this force push
deny|load-bearing|git -C . commit --amend --no-edit|global-option prefix in front of an amend
deny|load-bearing|git --git-dir=.git reset --hard origin/main|--git-dir prefix in front of a destructive reset
prompt|residual|git -c a=b merge origin/main|-c prefix in front of a base merge; the policy guard reads -c itself and refuses an alias, include, or autocorrect key
prompt|residual|git -c a=b rebase -i HEAD~2|-c prefix in front of a rebase; the policy guard decides
deny|load-bearing|git -C . filter-branch --tree-filter true HEAD|global-option prefix in front of a history rewrite
deny|load-bearing|git -C . filter-repo --path x|global-option prefix in front of a history rewrite
deny|load-bearing|git -c core.hooksPath=/dev/null status|hooksPath injection in front of a read-only subcommand: the -c rules must catch it on their own
deny|load-bearing|git -c core.hookspath=/dev/null status|lowercase hooksPath injection, read-only subcommand
deny|load-bearing|git -c a=b -c core.hooksPath=/dev/null status|hooksPath behind another -c, read-only subcommand
deny|load-bearing|git -c a=b -c core.hookspath=/dev/null status|lowercase hooksPath behind another -c, read-only subcommand
deny|load-bearing|git --config-env=core.hooksPath=HP status|--config-env injection, read-only subcommand
deny|load-bearing|git -c a=b --config-env=core.hooksPath=HP status|--config-env behind another global option, read-only subcommand
prompt|residual|git rebase --autosquash origin/main|a rebase is a never-pushed rewrite unpushed_rewrite can grant a worker; the policy guard decides
prompt|residual|git rebase -i HEAD~3|interactive rebase; the policy guard decides
prompt|residual|git merge main|a base merge worker_base_merge can grant a worker; the policy guard decides
deny|load-bearing|git reset --hard origin/main|destructive reset
deny|load-bearing|git filter-branch --tree-filter true HEAD|history rewrite
deny|load-bearing|git filter-repo --path x|history rewrite
deny|load-bearing|gh pr merge 123 --squash|merge is reserved to the operator, never a worker
deny|load-bearing|gh pr ready --undo 123|a worker may un-draft a PR, never re-draft one
deny|load-bearing|gh pr ready 123 --undo|flag-after-arg re-draft
deny|load-bearing|git status && git push origin main|a denied subcommand denies the compound call
deny|load-bearing|cd /tmp && git push origin main|deny survives a leading cd subcommand
deny|load-bearing|FOO=bar git push origin main|deny matches past a leading environment assignment
allow|legit|git push origin planwright/guard-coverage/task-1|the ordinary task-branch push
allow|legit|git push -u origin planwright/guard-coverage/task-1|the first push of a task branch, under the same deny floor as git push origin (REQ-G1.6)
deny|load-bearing|git push -u origin main|the first-push spelling still cannot reach main (REQ-G1.6)
deny|load-bearing|git push -u origin --force planwright/guard-coverage/task-1|the first-push spelling still cannot force (REQ-G1.6)
allow|legit|git push origin HEAD:refs/heads/planwright/guard-coverage/task-1|explicit refspec to a task branch
allow|legit|git push origin main-fix|a branch whose name merely starts with main stays pushable
allow|legit|git push origin HEAD:main-fix|refspec to a branch whose name starts with main
allow|legit|git push origin master-fix|a branch whose name merely starts with master stays pushable
allow|legit|git push origin planwright/human-gates/spec-notes|a branch whose name merely extends a spec branch stays pushable
allow|legit|git commit -m "feat(guard): add the matcher fixture table"|the ordinary commit
allow|legit|git commit -a -m "chore: tidy"|commit with -a
allow|legit|git commit -F /tmp/msg|commit from a message file
allow|legit|git commit -s -m "chore: release 0.32.1"|signed-off commit
allow|legit|git add -A && git commit -m "wip"|compound where every subcommand is allowed
allow|legit|gh pr create --draft --title t --body b|draft PR creation
allow|legit|gh pr ready 123|the /spec-kickoff spec-PR exception stays allowed
allow|legit|git status|read-only status
allow|legit|git log --oneline -5|read-only log
allow|legit|mise run check|the full CI gate
allow|residual|git push origin "main"|quoted destination; the glob layer is literal so it misses this — githooks/pre-push rejects the refspec
allow|residual|git push origin "master"|quoted master destination; the glob layer misses it the same way, and githooks/pre-push refuses only main, so no layer backs this one up
allow|residual|git push origin 'planwright/human-gates/spec'|quoted spec-branch destination; missed like the quoted master push, with no githooks backstop either
deny|overblock|git push origin planwright/a/b/spec|the spec-branch globs' * spans /, so a nested name that is not a spec branch is denied too; fail-safe, and the tower queue admits it
prompt|residual|git push|no destination in the text at all; on a branch whose upstream is main this pushes main — githooks/pre-push is the enforcement layer
allow|residual|git push origin HEAD|destination depends on the checked-out branch, which the glob layer cannot see — githooks/pre-push covers it
deny|load-bearing|git -c Core.HooksPath=/dev/null commit -m "wip"|mixed-case config key (git config keys are case-insensitive) evades the case-sensitive hooksPath globs, but the global-option-prefix rule catches it regardless of casing
prompt|residual|git config Core.HooksPath /dev/null|the mixed-case residual that genuinely remains: a PERSISTENT hook disable, missed by the case-sensitive git-config globs and outside the global-option-prefix rules since the command does not start with git -. No glob and no hook reaches it — accepted residual (model doc MA-2)
prompt|residual|GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git commit -m "wip"|config injection through environment variables rather than argv; deny rules match past leading assignments so the hooksPath text is never in the matched string — accepted residual
deny|load-bearing|git status "$(git push origin main)"|command substitution: a deny rule reaches the command nested in $() (model doc M9, REQ-H1.2)
deny|load-bearing|echo "$(git fetch origin && git push origin main)"|a compound inside a command substitution is split like a top-level one (M9)
deny|load-bearing|echo `git push origin main`|backtick command substitution (M9)
deny|load-bearing|echo "$(echo "$(git push --force origin x)")"|a substitution nested inside another substitution (M9)
deny|load-bearing|diff <(git push origin main) x|process substitution (M9)
deny|load-bearing|(git push origin main)|a subshell (M9, REQ-H1.2)
deny|load-bearing|git status && (cd /tmp; git push --force origin x)|a subshell after a top-level separator, separators inside it (M9)
deny|load-bearing|{ git push origin main; }|a brace group (M9)
deny|load-bearing|for b in a c; do git push origin main; done|a for-loop body (M9, REQ-H1.2)
deny|load-bearing|for b in $(git push --force origin x); do echo $b; done|a substitution in a for-loop head (M9)
deny|load-bearing|while true; do git push --force origin x; done|a while-loop body (M9)
deny|load-bearing|until false; do git push origin HEAD:main; done|an until-loop body (M9)
deny|load-bearing|while git push --force origin x; do true; done|a while-loop condition (M9)
deny|load-bearing|until git push origin main; do true; done|an until-loop condition (M9)
deny|load-bearing|if true; then	git push origin main; fi|a body opened by a keyword and a tab (M9)
deny|load-bearing|f() { git push origin main; }; f|a function body (M9)
deny|load-bearing|function f { git reset --hard origin/main; }; f|a function body, function-keyword form (M9)
deny|load-bearing|(git push origin main) 2>/dev/null|a subshell followed by a redirect (M9)
deny|load-bearing|git commit -m "fix (scope"; git push origin main|a lone parenthesis in a quoted argument cannot hold later separators inside a group (MB-3)
deny|load-bearing|git add "x`y" && git reset --hard origin/main|a lone backtick in a quoted argument, the same (MB-3)
deny|load-bearing|echo $((git push origin main); ls)|a substitution opening with a subshell is not arithmetic (M9)
deny|load-bearing|while true; do ls; done < <(git push origin main)|a process substitution after a closing word (M9)
deny|load-bearing|(ls) $(git push origin main)|a substitution after a subshell's close (M9)
deny|load-bearing|echo "(" ; git push origin main ; echo ")"|quoted parentheses that balance hold no separator (MB-3)
deny|load-bearing|git commit -m "(" ; git status $(git log; git push origin main)|a quoted lone parenthesis hides neither the separator after it nor a later substitution (MB-3)
deny|load-bearing|f () { git push origin main; }; f|a function body, POSIX spacing (M9)
deny|load-bearing|f(){ git push origin main; }; f|a function body, no spacing (M9)
allow|legit|git commit -m "chore: a; b && c"|separators inside quotes do not split (MB-3)
deny|load-bearing|case x in a) git push origin main;; esac|a case arm, reached by the atom sweep (MB-7)
prompt|residual|git status $'\'' ; cat x ; git status \'|ANSI-C quoting is not lexed, so the command is never reported allowed (MB-10)
prompt|residual|git status `git status \`cat x\``|an escaped backtick that a backtick substitution unescapes is not lexed (MB-10)
prompt|residual|git status; case x in a) rm -rf build;; esac|a case statement's arms are not read for allow, so nothing in one is reported allowed (MB-7)
allow|legit|git status "$(git rev-parse --show-toplevel)"|a substitution whose every command is allowed (M9)
prompt|residual|ls $((1 + 2))|arithmetic reads as a substitution holding a group, so the model asks for an allow rule it cannot find; conservative (M9)
prompt|residual|ls $(ls $(ls $(ls $(ls $(ls $(ls $(ls $(ls $(ls x))))))))))|nesting past the model's depth bound reports no allow for the uninspected command (M9)
prompt|residual|( (ls) ) >$(rm -rf build)|a substitution after a nested group's close is still read (M9)
prompt|residual|(rm -rf build) && git status|an unallowed command in a subshell beside an allowed one is never reported allowed (M9)
prompt|residual|{ rm -rf build; } && ls|an unallowed command in a brace group, the same (M9)
prompt|residual|git status $(rm -rf build)|an unallowed command in a command substitution, the same (M9)
prompt|residual|git status <(rm -rf build)|an unallowed command in a process substitution, input form (M9)
prompt|residual|git status >(rm -rf build)|an unallowed command in a process substitution, output form (M9)
prompt|residual|for f in a; do rm -rf build; done|an unallowed command in a loop body (M9)
deny|load-bearing|FOO=${x:-a b} git push origin main|an assignment whose ${…} value holds a space is stripped whole (M7)
deny|load-bearing|FOO=${x:-{} git push origin main|a bare { inside ${…} does not nest, so the value still ends at its } (M7)
deny|load-bearing|FOO=${x:-) a} git push origin main|a ) inside ${…} closes nothing (M7)
allow|residual|git push origin main>/dev/null|a redirect glued to the destination; the glob layer is literal (MA-4) — githooks/pre-push rejects the refspec
prompt|residual|git push	origin main|a tab between words; the glob layer is literal (MA-4) — githooks/pre-push rejects the refspec
allow|residual|git push origin x	--force|a tab before the force flag; the glob layer is literal (MA-4) and the policy guard decides
allow|residual|git push -u origin -vf topic|a short force flag bundled with another; the deny globs name -f on its own, and the policy guard reads bundled flags
allow|residual|git push -u origin refs/heads/*:refs/heads/*|a wildcard refspec can reach main; the policy guard refuses it
allow|residual|git push -u origin --prune refs/heads/*:refs/heads/*|--prune with a wildcard refspec deletes remote branches; the policy guard counts it as a bulk push
deny|load-bearing|if git status; then git push origin main; fi|an if-then body (M9)
deny|load-bearing|if false; then true; else git reset --hard origin/main; fi|an else body (M9)
deny|load-bearing|if false; then true; elif git push origin main; then true; fi|an elif condition (M9)
allow|legit|for f in a b; do git add $f; done|a for loop whose body every allow rule covers is allowed (M9)
allow|legit|git rev-parse --abbrev-ref HEAD|read-only rev-parse
allow|legit|git branch --show-current|read-only branch listing
allow|legit|git diff --stat origin/main|diff stat
allow|legit|git show --stat HEAD|show stat
allow|legit|git checkout planwright/guard-coverage/task-1|checkout of a task branch
allow|legit|git switch planwright/guard-coverage/task-1|switch to a task branch
allow|legit|git add scripts/x.sh|staging a file
allow|legit|gh pr view 123 --json state|PR inspection
allow|legit|gh pr list --head planwright/guard-coverage/task-1|PR listing
allow|legit|mise tasks|task listing
prompt|residual|wc --files0-from=/proc/1234/environ README.md|no static rule names wc: --files0-from echoes a file's content in its error output (REQ-G1.1, REQ-E1.6)
allow|legit|ls -la scripts|static read-only set: ls (REQ-G1.1)
allow|legit|stat README.md|static read-only set: stat (REQ-G1.1)
allow|legit|git ls-files scripts|static read-only set: git ls-files (REQ-G1.1)
allow|legit|git merge-base HEAD origin/main|static read-only set: git merge-base (REQ-G1.1)
allow|legit|git ls-tree HEAD scripts|static read-only set: git ls-tree (REQ-G1.1)
allow|legit|git show-ref --heads|static read-only set: git show-ref (REQ-G1.1)
allow|legit|git for-each-ref refs/heads|static read-only set: git for-each-ref (REQ-G1.1)
prompt|residual|cat /proc/1234/environ|no static rule names a content-printing verb (REQ-G1.1, REQ-E1.6); Claude Code also applies the Read deny to the file commands it recognizes, which the model does not (MB-9)
prompt|residual|git rev-list --output=/tmp/x HEAD|git rev-list takes --output, so no static rule names it (REQ-G1.1)
allow|legit|git push origin feature/c++|a branch name containing + stays pushable: the +refspec deny requires a space before the plus (narrowed 2026-07-29 on operator decision). git check-ref-format confirms the ref is valid
allow|residual|git commit -a --amen|git takes any unique prefix of a long option, so --amen is --amend; the policy guard reads the prefixes and decides
allow|residual|git commit --am --no-edit|--am is the shortest prefix git reads as --amend; the policy guard decides
allow|residual|git commit --sq=HEAD~1|--sq is the shortest prefix git reads as --squash; the policy guard decides
allow|residual|git commit -m "wip" --squas HEAD~1|abbreviated squash after the message; the policy guard decides
allow|residual|git commit --fix=HEAD~1|--fix is the shortest prefix git reads as --fixup; the policy guard decides
allow|residual|git commit -m "wip" --fixu HEAD~1|abbreviated fixup after the message; the policy guard decides
deny|load-bearing|git push --mirr origin|abbreviated --mirror, a force-push of every ref
deny|load-bearing|git push origin --mi|shortest --mirror prefix after the remote
deny|load-bearing|git push --al origin|abbreviated --all pushes main with every other branch
deny|load-bearing|git push origin --al|abbreviated --all after the remote
deny|load-bearing|git push origin --branches|--branches is git's alias of --all
deny|load-bearing|git push --b origin|shortest --branches prefix
deny|load-bearing|git push origin :|the matching refspec pushes every branch the remote shares, main included
deny|load-bearing|git push origin : --dry-run|matching refspec with a trailing flag
deny|load-bearing|git push origin "main" --no-veri|abbreviated --no-verify skips the pre-push hook that catches the quoted main destination
deny|load-bearing|git commit --no-veri -m "wip"|abbreviated --no-verify on commit
allow|legit|git push origin :planwright/guard-coverage/task-1|deleting a task branch is not the matching refspec
deny|overblock|git commit -m "docs: describe the -n flag in the guide"|a commit message containing " -n " is denied; fail-safe, rephrase the message
deny|overblock|git commit -m "fix: handle --no-verify in the wrapper"|a commit message naming --no-verify is denied; fail-safe
allow|legit|git commit -m "docs: use --amend carefully"|a commit message naming --amend is a plain commit again now that no amend glob is in the profile
allow|legit|git commit -m "docs: --fix typo"|a message word starting with an abbreviated rewrite flag is a plain commit again
ROWS
}
FIXTURES=$(fixture_rows)

# Row-level assertions, and (in the same pass) the per-row set of matching deny
# rule indices that passes D and E consume.
row_total=0
row_deny_total=0
MATCH_SETS=()
match_n=0

# deny_match_indices <command> — print the indices of every deny rule matching
# any deny subject of the command (the set pm_decide sweeps), space separated.
deny_match_indices() {
  local sub stripped i out=""
  while IFS= read -r sub; do
    [ -n "$sub" ] || continue
    stripped="$(pm_strip_leading_assignments "$sub")"
    i=0
    while [ "$i" -lt "$PM_DENY_N" ]; do
      if [[ $stripped =~ ${PM_DENY_RE[$i]} ]]; then
        case " $out " in
          *" $i "*) ;;
          *) out="$out $i" ;;
        esac
      fi
      i=$((i + 1))
    done
  done <<EOF
$(pm_deny_subjects "$1")
EOF
  printf '%s' "${out# }"
}

# allow_match_indices <command> — the same over the Bash allow rules, which
# match the unstripped subcommand (doc rule M7).
allow_match_indices() {
  local sub i out=""
  while IFS= read -r sub; do
    [ -n "$sub" ] || continue
    i=0
    while [ "$i" -lt "$PM_ALLOW_N" ]; do
      if [[ $sub =~ ${PM_ALLOW_RE[$i]} ]]; then
        case " $out " in
          *" $i "*) ;;
          *) out="$out $i" ;;
        esac
      fi
      i=$((i + 1))
    done
  done <<EOF
$(pm_subcommands "$1")
EOF
  printf '%s' "${out# }"
}
ALLOW_SETS=()
allow_n=0

while IFS='|' read -r expected class command note; do
  [ -n "${expected:-}" ] || continue
  row_total=$((row_total + 1))

  # Class/expectation consistency: a mislabeled row must fail, not pass quietly.
  case "$class" in
    load-bearing | overblock)
      [ "$expected" = "deny" ] \
        || fail "row class '$class' requires expected=deny, got '$expected': $command"
      ;;
    legit)
      [ "$expected" = "allow" ] \
        || fail "row class 'legit' requires expected=allow, got '$expected': $command"
      ;;
    residual)
      case "$expected" in
        allow | prompt) ;;
        *) fail "row class 'residual' requires expected=allow|prompt, got '$expected': $command" ;;
      esac
      ;;
    *) fail "unknown row class '$class': $command" ;;
  esac

  got="$(pm_decide "$command")"
  if [ "$got" = "$expected" ]; then
    ok "[$class] $expected: $command"
  elif [ "$got" = "deny" ]; then
    # The confusing failure to debug is an unexpected deny: name the rule that
    # fired so the reader does not have to bisect 49 globs by hand.
    fail "[$class] expected $expected, got deny (rule: $(pm_matching_deny_rule "$command")): $command  ($note)"
  else
    fail "[$class] expected $expected, got $got: $command  ($note)"
  fi

  if [ "$expected" = "deny" ]; then
    row_deny_total=$((row_deny_total + 1))
    MATCH_SETS[match_n]="$(deny_match_indices "$command")"
    match_n=$((match_n + 1))
  elif [ "$expected" = "allow" ]; then
    ALLOW_SETS[allow_n]="$(allow_match_indices "$command")"
    allow_n=$((allow_n + 1))
  fi
done <<EOF
$FIXTURES
EOF

# Row-count floor, pinned at the current count rather than a round number.
# Passes D and E guard the deny RULES; nothing else would notice a fixture ROW
# being deleted, and a row covering a rule redundantly can be deleted without
# tripping pass D. So the floor is `>=` the exact current count: adding rows is
# always fine, deleting any row fails and has to be argued for. Raise these two
# numbers in the same commit that adds rows (REQ-H1.3).
ROW_FLOOR=208
DENY_ROW_FLOOR=124
if [ "$row_total" -ge "$ROW_FLOOR" ] && [ "$row_deny_total" -ge "$DENY_ROW_FLOOR" ]; then
  ok "the fixture table is non-vacuous: $row_total rows, $row_deny_total load-bearing (REQ-H1.3)"
else
  fail "the fixture table shrank below its floor: $row_total/$ROW_FLOOR rows, $row_deny_total/$DENY_ROW_FLOOR expected-deny (REQ-H1.3)"
fi

# ---------------------------------------------------------------------------
# Pass D — no dead deny rules.
#
# Every deny rule must be matched by at least one fixture row. This is what
# catches a rule that can never fire: a `:*` that landed mid-pattern, a typo in
# a flag name, a path-scoped rule in command-boundary form.
# ---------------------------------------------------------------------------
i=0
while [ "$i" -lt "$PM_DENY_N" ]; do
  exercised=0
  j=0
  while [ "$j" -lt "$match_n" ]; do
    case " ${MATCH_SETS[$j]} " in
      *" $i "*)
        exercised=1
        break
        ;;
    esac
    j=$((j + 1))
  done
  if [ "$exercised" -eq 0 ]; then
    fail "deny rule is never exercised by any fixture row (dead rule or missing row): $(pm_deny_rule_at "$i")"
  fi
  i=$((i + 1))
done
ok "every deny rule is exercised by at least one fixture row (pass D)"

# ---------------------------------------------------------------------------
# Pass E — mutation.
#
# A rule is SOLE COVER for a row when it is the only deny rule matching that
# row; removing it flips the row from deny to allow-or-prompt, so the fixture
# table would fail. Any rule that is never sole cover is redundant: it can be
# deleted with a green suite. That is the exact failure mode this test exists to
# prevent, so redundancy has to be declared here with a reason.
#
# The sole-cover computation is equivalent to re-running the whole table once
# per removed rule, without the re-parse: removing rule i flips row r iff
# r's matching set is exactly {i}.
# ---------------------------------------------------------------------------
# A function for the same bash 3.2 reason as fixture_rows.
redundant_by_design_rows() {
  cat <<'ROWS'
Bash(git push --force:*)|subsumed by Bash(git push --force*); kept as the explicit spelling of the plain force flag
Bash(git push --force-with-lease:*)|subsumed by Bash(git push --force*); kept as the explicit spelling of the lease form
Bash(git push *:main)|subsumed by Bash(git push *:main *); kept as a hedge on the trailing-space word-boundary rule (doc rule M4)
Bash(git push * main)|subsumed by Bash(git push * main *); same M4 hedge
Bash(git push *heads/main)|subsumed by Bash(git push *heads/main *); same M4 hedge
Bash(git push *refs/heads/main)|subsumed by the broader Bash(git push *heads/main) pair; kept as the explicit fully-qualified spelling
Bash(git push *refs/heads/main *)|subsumed by the broader Bash(git push *heads/main *); kept as the explicit fully-qualified spelling
Bash(git push *:master)|subsumed by Bash(git push *:master *); the main family's M4 hedge
Bash(git push * master)|subsumed by Bash(git push * master *); same M4 hedge
Bash(git push *heads/master)|subsumed by Bash(git push *heads/master *); same M4 hedge
Bash(git push *:planwright/*/spec)|subsumed by Bash(git push *:planwright/*/spec *); same M4 hedge
Bash(git push * planwright/*/spec)|subsumed by Bash(git push * planwright/*/spec *); same M4 hedge
Bash(git push *heads/planwright/*/spec)|subsumed by Bash(git push *heads/planwright/*/spec *); same M4 hedge
Bash(git push --mirror:*)|subsumed by Bash(git push --mi*), the shortest prefix git reads as --mirror; kept as the explicit spelling
Bash(git push * --mirror*)|subsumed by Bash(git push * --mi*); kept as the explicit spelling
Bash(git push --all:*)|subsumed by Bash(git push --al*), the shortest prefix git reads as --all; kept as the explicit spelling
Bash(git push * --all*)|subsumed by Bash(git push * --al*); kept as the explicit spelling
Bash(git * --no-verify*)|subsumed by Bash(git * --no-veri*), the shortest prefix git reads as --no-verify; kept as the explicit spelling
ROWS
}
REDUNDANT_BY_DESIGN=$(redundant_by_design_rows)
is_declared_redundant() {
  local rule="$1" line
  while IFS='|' read -r line _; do
    [ -n "${line:-}" ] || continue
    [ "$line" = "$rule" ] && return 0
  done <<EOF
$REDUNDANT_BY_DESIGN
EOF
  return 1
}

i=0
sole_cover_count=0
SOLE_RULES=""
while [ "$i" -lt "$PM_DENY_N" ]; do
  rule="$(pm_deny_rule_at "$i")"
  sole=0
  j=0
  while [ "$j" -lt "$match_n" ]; do
    if [ "${MATCH_SETS[$j]}" = "$i" ]; then
      sole=1
      break
    fi
    j=$((j + 1))
  done
  if [ "$sole" -eq 1 ]; then
    sole_cover_count=$((sole_cover_count + 1))
    SOLE_RULES="$SOLE_RULES
$rule"
  elif is_declared_redundant "$rule"; then
    ok "redundant by design (declared): $rule"
  else
    fail "deny rule is redundant — it can be deleted with a green suite. Add a covering fixture row, or declare it in REDUNDANT_BY_DESIGN with a reason: $rule"
  fi
  i=$((i + 1))
done
ok "$sole_cover_count of $PM_DENY_N deny rules are sole cover for a fixture row; the rest are declared redundant (pass E)"

# A declared-redundant entry that has become sole cover, or that names a rule no
# longer in the deny list, is stale bookkeeping — fail rather than carry it.
while IFS='|' read -r rule reason; do
  [ -n "${rule:-}" ] || continue
  [ -n "${reason:-}" ] || fail "REDUNDANT_BY_DESIGN entry has no reason: $rule"
  found=0
  i=0
  while [ "$i" -lt "$PM_DENY_N" ]; do
    if [ "$(pm_deny_rule_at "$i")" = "$rule" ]; then
      found=1
      break
    fi
    i=$((i + 1))
  done
  [ "$found" -eq 1 ] \
    || fail "REDUNDANT_BY_DESIGN names a rule that is not in the deny list: $rule"
  case "
$SOLE_RULES
" in
    *"
$rule
"*)
      fail "REDUNDANT_BY_DESIGN declares a rule that is in fact sole cover for a fixture row — drop the stale entry: $rule"
      ;;
  esac
done <<EOF
$REDUNDANT_BY_DESIGN
EOF
ok "every REDUNDANT_BY_DESIGN entry names a live, genuinely redundant deny rule and carries a reason"

# ---------------------------------------------------------------------------
# Pass F — no unexercised allow rules (REQ-G1.1), mirroring pass D: every
# Bash allow rule must be matched by at least one expected-allow row, so a
# permissions widening cannot ship without a row showing what it admits.
# ---------------------------------------------------------------------------
# allow_rules_uncovered — print each Bash allow rule no expected-allow row
# matches. A function so the pass can be shown failing on an injected rule.
allow_rules_uncovered() {
  local i j covered
  i=0
  while [ "$i" -lt "$PM_ALLOW_N" ]; do
    covered=0
    j=0
    while [ "$j" -lt "$allow_n" ]; do
      case " ${ALLOW_SETS[$j]} " in
        *" $i "*)
          covered=1
          break
          ;;
      esac
      j=$((j + 1))
    done
    [ "$covered" -eq 1 ] || printf '%s\n' "$(pm_allow_rule_at "$i")"
    i=$((i + 1))
  done
}
uncovered="$(allow_rules_uncovered)"
if [ -z "$uncovered" ]; then
  ok "every Bash allow rule is exercised by an expected-allow fixture row (pass F, REQ-G1.1)"
else
  while IFS= read -r rule; do
    fail "allow rule has no fixture row showing what it admits (pass F, REQ-G1.1): $rule"
  done <<EOF
$uncovered
EOF
fi
# The pass must be able to fail: the same check over the shipped allow list
# plus one rule no row exercises names exactly that rule.
injected="$(
  pm_load_rules "$DENY_RULES" "$ASK_RULES" "$ALLOW_RULES
Bash(zz-no-row-names-this:*)" >/dev/null 2>&1
  allow_rules_uncovered
)"
if [ "$injected" = 'Bash(zz-no-row-names-this:*)' ]; then
  ok "pass F names an allow rule that no fixture row exercises"
else
  fail "pass F did not flag an injected allow rule with no fixture row"
fi

# ---------------------------------------------------------------------------
# Pass G — REQ-G1.1: the static allow set names no verb that prints an
# arbitrary path's content and no verb or git subcommand with a file-writing
# or program-running form. A static rule never reaches the worker guard's
# argument screens, so these stay with the guard.
# ---------------------------------------------------------------------------
FORBIDDEN_VERBS='awk find xargs sed sort uniq cat grep head tail cut diff jq wc'
# Verbs that run their argument as the command, so a rule naming one admits
# whatever follows it.
WRAPPER_VERBS='command builtin env sudo time timeout nice nohup stdbuf noglob exec eval sh bash zsh fish'
# The diff family takes --output, rev-list and the log family write the same
# way, grep takes -O, cat-file takes --textconv.
FORBIDDEN_GIT='diff diff-tree diff-index diff-files log show whatchanged shortlog reflog format-patch range-diff rev-list stash grep cat-file'
# The git subcommands a static rule has been reviewed for; any other needs its
# write and execution forms checked here before it joins the profile.
REVIEWED_GIT='status rev-parse checkout switch add commit push ls-files ls-tree merge-base show-ref for-each-ref'
# Rules that predate the no-write-forms rule and keep their write forms: kept,
# never widened, and no new rule may join them.
GRANDFATHERED='Bash(git diff:*) Bash(git log:*) Bash(git show:*) Bash(git branch:*)'

# forbidden_allow_rules <rule-lines> — print each Bash allow rule that names a
# forbidden or wrapper verb, a verb that is not a plain word (a glob, a path,
# an assignment), or a git subcommand that is forbidden, unreviewed, or hidden
# behind a global option, unless the rule is grandfathered.
forbidden_allow_rules() {
  local rule pat verb rest sub
  while IFS= read -r rule; do
    pat="$(pm_rule_pattern "$rule")" || continue
    case " $GRANDFATHERED " in
      *" $rule "*) continue ;;
    esac
    pat="${pat%:\*}"
    verb="${pat%% *}"
    case "$verb" in
      '' | *[!A-Za-z0-9._-]*)
        printf '%s\n' "$rule"
        continue
        ;;
    esac
    case " $FORBIDDEN_VERBS $WRAPPER_VERBS " in
      *" $verb "*)
        printf '%s\n' "$rule"
        continue
        ;;
    esac
    [ "$verb" = git ] || continue
    rest="${pat#git}"
    rest="${rest# }"
    sub="${rest%% *}"
    case " $FORBIDDEN_GIT " in
      *" $sub "*)
        printf '%s\n' "$rule"
        continue
        ;;
    esac
    case " $REVIEWED_GIT " in
      *" $sub "*) ;;
      *) printf '%s\n' "$rule" ;;
    esac
  done <<EOF
$1
EOF
}
bad="$(forbidden_allow_rules "$ALLOW_RULES")"
if [ -z "$bad" ]; then
  ok "no static allow rule names a content-printing verb or a writing or executing form (pass G, REQ-G1.1, REQ-E1.6)"
else
  while IFS= read -r rule; do
    fail "static allow rule names a verb or git subcommand REQ-G1.1 excludes or nobody reviewed: $rule"
  done <<EOF
$bad
EOF
fi
probe='Bash(cat:*)
Bash(sed -n:*)
Bash(wc:*)
Bash(git grep:*)
Bash(git cat-file:*)
Bash(git diff-tree:*)
Bash(git rev-list:*)
Bash(git archive:*)
Bash(git --no-pager grep:*)
Bash(git*)
Bash(*)
Bash(/bin/cat:*)
Bash(LC_ALL=C sort:*)
Bash(command cat:*)
Bash(git diff:*)
Bash(git ls-files:*)
Bash(stat:*)'
expected_probe='Bash(cat:*) Bash(sed -n:*) Bash(wc:*) Bash(git grep:*) Bash(git cat-file:*) Bash(git diff-tree:*) Bash(git rev-list:*) Bash(git archive:*) Bash(git --no-pager grep:*) Bash(git*) Bash(*) Bash(/bin/cat:*) Bash(LC_ALL=C sort:*) Bash(command cat:*) '
if [ "$(forbidden_allow_rules "$probe" | tr '\n' ' ')" = "$expected_probe" ]; then
  ok "pass G flags each excluded, unreviewed, or disguised spelling and passes the reviewed ones"
else
  fail "pass G misclassified its probe rules: $(forbidden_allow_rules "$probe" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# Pass H — path rules (REQ-F1.6, REQ-G1.8, REQ-E1.6). The Read and Edit rules
# use gitignore patterns (doc rule M10); Write and NotebookEdit path rules
# never match (M11), so Edit rules are what close the Write tool too.
# ---------------------------------------------------------------------------
PM_CWD=/work/repo/.claude/worktrees/w1
PM_HOME=/home/u
PM_SETTINGS_DIR=/opt/planwright/config

expect_path() {
  # expect_path <match|no-match> <deny|allow> <pattern> <path>
  if pm_path_matches "$2" "$3" "$4"; then got=match; else got=no-match; fi
  if [ "$got" = "$1" ]; then
    ok "doc example: $2 path rule ($3) $1 $4"
  else
    fail "doc example: $2 path rule ($3) should $1 $4"
  fi
}
# The permission documentation's worked examples, cwd /work/repo/.claude/worktrees/w1.
expect_path match deny '.env' "$PM_CWD/.env"
expect_path match deny '.env' "$PM_CWD/a/b/.env"
expect_path no-match deny '.env' /work/repo/.env
expect_path match deny '**/.env' "$PM_CWD/a/.env"
expect_path match deny '//**/.env' /etc/x/.env
expect_path match allow 'src/**' "$PM_CWD/src/app.ts"
expect_path no-match allow 'src/**' "$PM_CWD/vendor/pkg/src/lib.js"
expect_path match deny 'src/**' "$PM_CWD/vendor/pkg/src/lib.js"
expect_path match allow '**/src/**' "$PM_CWD/vendor/pkg/src/lib.js"
expect_path no-match deny '/src/**' "$PM_CWD/src/app.ts"
expect_path match deny '/src/**' "$PM_SETTINGS_DIR/src/app.ts"
expect_path match deny '//tmp/scratch.txt' /tmp/scratch.txt
# shellcheck disable=SC2088 # a literal ~ is the rule's home anchor
expect_path match deny '~/.zshrc' /home/u/.zshrc
expect_path no-match deny '*.ts' "$PM_CWD/src/app.js"
expect_path match deny 'src/*.ts' "$PM_CWD/src/app.ts"
expect_path no-match deny 'src/*.ts' "$PM_CWD/src/x/app.ts"

# The hooks-directory probe (worker-permission-ergonomics REQ-F1.7): whether any
# spelling of a path rule matches the worktree root's githooks/ and .githooks/
# and not a deeper directory of that name. PROBE_STAMP is the Claude Code CLI
# version the probe was last read against; it must equal the version the doc
# models and the doc must pin the probe's outcome under it, so a version bump
# forces the probe to be re-read rather than assumed.
PROBE_STAMP=2.1.314
if grep -q "^| Claude Code CLI | \*\*$PROBE_STAMP\*\*" "$MODEL_DOC" \
  && grep -q "Hooks-directory probe (CLI $PROBE_STAMP)" "$MODEL_DOC"; then
  ok "the hooks-directory probe is pinned in the model doc under the modeled CLI version $PROBE_STAMP"
else
  fail "the hooks-directory probe stamp $PROBE_STAMP does not match the modeled CLI version or is not pinned in docs/permission-matcher-model.md"
fi
for dir in githooks .githooks; do
  for spelling in "$dir/**" "./$dir/**" "$dir/**/*" "./$dir/**/*" "$dir/*" "/$dir/**"; do
    root_hit=n
    pm_path_matches deny "$spelling" "$PM_CWD/$dir/x" && root_hit=y
    deep_hit=n
    pm_path_matches deny "$spelling" "$PM_CWD/test/$dir/x" && deep_hit=y
    nested_hit=n
    pm_path_matches deny "$spelling" "$PM_CWD/$dir/sub/x" && nested_hit=y
    case "$spelling" in
      "$dir/**" | "./$dir/**")
        want="y y y"
        ;; # a single directory segment before /** matches at any depth (M10)
      "$dir/**/*" | "./$dir/**/*")
        want="y n y"
        ;; # anchored at the working directory: the shipped spelling
      "$dir/*")
        want="y n n"
        ;;
      *)
        want="n n n"
        ;; # settings-anchored: never the worktree
    esac
    if [ "$root_hit $deep_hit $nested_hit" = "$want" ]; then
      ok "probe: deny $spelling matches (root, deeper-dir, below-root) = $want"
    else
      fail "probe: deny $spelling matched '$root_hit $deep_hit $nested_hit', expected '$want'"
    fi
  done
done

# path_fixture_rows: expected|class|tool|path|note, under the cwd above (a
# worker's worktree beneath its primary checkout's .claude/worktrees/).
path_fixture_rows() {
  cat <<'ROWS'
deny|load-bearing|Edit|/work/repo/.claude/worktrees/w1/.git|the worktree's .git entry (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/.git|Edit rules close the Write tool too (M11)
deny|load-bearing|Edit|/work/repo/.git/hooks/pre-push|the default hooks directory, in the common git dir outside the worktree (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.git/config|git's own config, which names the hooks directory (REQ-F1.6)
deny|load-bearing|Edit|/work/repo/.claude/worktrees/w1/githooks/pre-push|a repo-tracked hooks directory (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/.githooks/pre-commit|the dotted hooks-directory convention (REQ-F1.6)
deny|load-bearing|Edit|/work/repo/.claude/worktrees/w1/.claude/settings.json|the worktree's .claude/ (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/.claude/settings.local.json|the worktree's .claude/ through the Write tool (REQ-F1.6)
deny|load-bearing|Edit|/work/repo/.claude/worktrees/w1/mise.toml|mise config runs commands (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/sub/mise.toml|a nested mise config (REQ-F1.6)
deny|load-bearing|Edit|/work/repo/.claude/worktrees/w1/mise.local.toml|machine-local mise config (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/.mise/tasks/check|a mise task directory (REQ-F1.6)
deny|load-bearing|Edit|/work/repo/.claude/worktrees/w1/lefthook.yml|lefthook config runs commands (REQ-F1.6)
deny|load-bearing|Write|/work/repo/mise.local.toml|the primary checkout's mise config, which mise reads from a worktree beneath it (REQ-F1.6)
allow|guard|Edit|/work/repo/githooks/pre-commit|the primary checkout's hooks directory: the anchored rows cover only the worktree root, and scripts/worker-hooks-edit-guard.sh refuses this path (tests/test-worker-hooks-edit-guard.sh asserts it) (REQ-F1.7)
deny|load-bearing|Edit|/work/repo/mise.toml|the primary checkout's mise config (REQ-F1.6)
deny|load-bearing|Edit|/work/repo/.claude/worktrees/w1/.envrc|direnv config runs commands (REQ-F1.6, as the guard names it)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/.tool-versions|tool-version config selects what mise runs (REQ-F1.6, as the guard names it)
deny|load-bearing|Edit|/home/u/.config/direnv/direnvrc|a .config directory, which holds mise and direnv user config (REQ-F1.6, as the guard names it)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/mise/config.toml|mise's directory-config form (REQ-F1.6)
deny|load-bearing|Edit|/work/repo/.claude/worktrees/w1/mise/config.local.toml|the local variant beside mise/config.toml (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/mise/conf.d/10-tools.toml|a conf.d fragment in mise/ (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/mise/conf.d/git-tools/mise.toml|a conf.d folder fragment in mise/ (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/mise/tasks/build|a file task in mise/tasks/ (REQ-F1.6)
deny|load-bearing|Edit|/etc/mise/miserc.toml|the system miserc, which picks the config file names (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/.miserc.toml|a project miserc, which picks the config file names (REQ-F1.6)
deny|load-bearing|Edit|/work/repo/.miserc.local.toml|the primary checkout's local miserc, read from a worktree beneath it (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/mise-tasks/deploy|mise's default file-task directory (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/.mise-tasks/deploy|mise's dotted file-task directory (REQ-F1.6)
deny|load-bearing|Edit|/work/repo/.claude/worktrees/w1/mise.lock|mise's lockfile records download URLs and checksums (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/mise.local.lock|the local lockfile beside mise.local.toml (REQ-F1.6)
deny|load-bearing|Write|/home/u/.local/share/mise/shims/node|mise's data directory holds the tools and shims it runs (REQ-F1.6)
deny|load-bearing|Edit|/home/u/.local/state/mise/trusted-configs/x|mise's state directory records which config it trusts (REQ-F1.6)
deny|load-bearing|Write|/home/u/.cache/mise/remote-git-tasks-cache/r/tasks/x|mise's cache holds remote task clones it reuses (REQ-F1.6)
deny|load-bearing|Write|/Users/u/Library/Caches/mise/remote-git-tasks-cache/r/tasks/x|mise's macOS cache directory (REQ-F1.6)
deny|load-bearing|Write|/usr/local/share/mise/shims/node|mise's system data directory (REQ-F1.6)
deny|load-bearing|Write|/tmp/planwright-1000/0123abcd/mise/x|mise's temporary directory under a worker's TMPDIR (REQ-F1.6)
deny|load-bearing|Write|/var/folders/ab/cd/T/mise/x|mise's temporary directory under the macOS TMPDIR (REQ-F1.6)
deny|load-bearing|Write|/private/tmp/planwright-501/0123abcd/mise/x|a macOS worker's TMPDIR, which the scratch launcher resolves under /private (REQ-F1.6)
deny|load-bearing|Edit|/private/var/folders/ab/cd/T/mise/x|the macOS TMPDIR by its resolved spelling (REQ-F1.6)
deny|overblock|Write|/tmp/planwright-1000/0123abcd/r/mise/files/x|every mise/ under the temporary trees is refused, not only mise's own; fail-safe
deny|load-bearing|Edit|/work/repo/.claude/worktrees/w1/.mise.toml|mise's dotted config name (REQ-F1.6)
deny|load-bearing|Edit|/work/repo/.claude/worktrees/w1/.mise.local.toml|mise's dotted environment config (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/lefthook/pre-commit/check.sh|a lefthook script directory (REQ-F1.6)
deny|load-bearing|Edit|/work/repo/.claude/worktrees/w1/lefthook-local.yml|lefthook's local override, merged on every hook run (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/.lefthook/pre-commit/check.sh|lefthook's dotted script directory (REQ-F1.6)
deny|load-bearing|Edit|/work/repo/.claude/worktrees/w1/.lefthook.yml|lefthook's dotted config name (REQ-F1.6)
deny|load-bearing|Write|/work/repo/.claude/worktrees/w1/.lefthook-local/pre-commit/x.sh|lefthook's dotted local script directory (REQ-F1.6)
deny|load-bearing|Edit|/work/repo/.claude/worktrees/w1/.lefthook-local.yml|lefthook's dotted local override (REQ-F1.6)
deny|load-bearing|Edit|/home/u/.claude/plugins/data/planwright-planwright/fleet/session-records/0123abcd.record|the guard's session record (REQ-G1.8)
deny|load-bearing|Write|/srv/fleet/session-records/0123abcd-89ef0123456789ab.record|a session record under an overridden fleet home (REQ-G1.8)
deny|load-bearing|Write|/home/u/.claude/plugins/data/planwright-planwright/fleet/streamjson/mc-w-1/mise-task-edit|the persisted mise task-file opt-in a recover reads back
deny|load-bearing|Edit|/srv/fleet/streamjson/mc-w-1/worker-settings.json|an opted-in worker's per-launch settings profile
deny|load-bearing|Edit|/work/repo/.claude/planwright.yml|the repo-tracked overlay (REQ-G1.8)
deny|load-bearing|Write|/work/repo/.claude/planwright.local.yml|the machine-local overlay (REQ-G1.8)
deny|load-bearing|Edit|/home/u/.claude/plugins/data/planwright-planwright/overlay/planwright.yml|the adopter overlay (REQ-G1.8)
deny|load-bearing|Read|/proc/1234/environ|another process's environment (REQ-E1.6)
deny|load-bearing|Read|/proc/1234/task/1235/environ|a thread's environment (REQ-E1.6)
deny|load-bearing|Edit|/proc/1234/environ|a Read deny blocks the edit tools on the same path too
allow|legit|Edit|/work/repo/.claude/worktrees/w1/tests/fixtures/entry-points/githooks/pre-push/args|a nested githooks/ fixture directory stays editable: the profile rows anchor at the worktree root (REQ-F1.7)
allow|legit|Write|/work/repo/.claude/worktrees/w1/src/githooks/x|a deeper githooks/ directory is not the hooks directory (REQ-F1.7)
allow|legit|Edit|/work/repo/.claude/worktrees/w1/test/githooks/x|a test fixture directory named githooks (REQ-F1.7)
allow|guard|Write|/work/repo/.claude/worktrees/w1/hookdir/x|a core.hooksPath directory with another name: no path row can name it, so scripts/worker-hooks-edit-guard.sh refuses it (REQ-F1.7)
deny|overblock|Read|/proc/self/environ|the worker's own environment is denied to the Read tool too; env and printenv still print it
allow|legit|Edit|/work/repo/.claude/worktrees/w1/scripts/x.sh|editing a repo script stays allowed (REQ-F1.6 trusted-checkout residual)
allow|legit|Write|/work/repo/.claude/worktrees/w1/tests/test-x.sh|writing a repo test stays allowed
allow|legit|Edit|/work/repo/.claude/worktrees/w1/docs/githooks.md|a file merely named after the hooks directory stays editable
allow|legit|Edit|/work/repo/.claude/worktrees/w1/config/defaults.yml|the repo's own config defaults stay editable
allow|legit|Write|/work/repo/.claude/worktrees/w1/roles/osx/files/mise/offload.toml|a file under mise/ that mise never loads stays writable
allow|legit|Edit|/work/repo/.claude/worktrees/w1/mise/README.md|a mise/ file outside config, miserc, conf.d and tasks stays editable
allow|legit|Read|/work/repo/.claude/worktrees/w1/README.md|ordinary reads
allow|legit|Read|/proc/1234/status|a /proc read that is not an environment
ROWS
}
PATH_FIXTURES=$(path_fixture_rows)
# Compiled here, in this shell, so the per-row command substitutions inherit it.
pm_path_compile
path_rows=0
ALLOW_TOOLS_SEEN=' '
while IFS='|' read -r expected class tool path note; do
  [ -n "${expected:-}" ] || continue
  path_rows=$((path_rows + 1))
  case "$class:$expected" in
    load-bearing:deny | overblock:deny | legit:allow | guard:allow) ;;
    *) fail "path row class '$class' does not fit expected=$expected: $tool $path" ;;
  esac
  got="$(pm_decide_path "$tool" "$path")"
  if [ "$got" = "$expected" ]; then
    ok "[$class] $expected: $tool $path"
  else
    fail "[$class] expected $expected, got $got: $tool $path  ($note)"
  fi
  [ "$expected" = deny ] || ALLOW_TOOLS_SEEN="$ALLOW_TOOLS_SEEN$tool "
done <<EOF
$PATH_FIXTURES
EOF

PATH_ROW_FLOOR=44
if [ "$path_rows" -ge "$PATH_ROW_FLOOR" ]; then
  ok "the path fixture table is non-vacuous: $path_rows rows"
else
  fail "the path fixture table shrank below its floor: $path_rows/$PATH_ROW_FLOOR"
fi

# Every path deny rule must be the only rule blocking at least one row: one
# no row exercises cannot match (a Write(...) rule, a wrong anchor), and one
# that never stands alone can be deleted with a green suite (the path-rule
# counterpart of passes D and E).
# path_rules_uncovered — print `dead <rule>` or `shadowed <rule>` for each
# loaded path deny rule failing that, over the path fixture table's deny rows.
path_rules_uncovered() {
  local expected class tool path note i j exercised sole n=0
  local -a sets=()
  while IFS='|' read -r expected class tool path note; do
    [ "${expected:-}" = deny ] || continue
    sets[n]="$(pm_path_deny_match_indices "$tool" "$path")"
    n=$((n + 1))
  done <<EOF
$PATH_FIXTURES
EOF
  i=0
  while [ "$i" -lt "$PM_PATH_DENY_N" ]; do
    exercised=0
    sole=0
    j=0
    while [ "$j" -lt "$n" ]; do
      case " ${sets[$j]} " in
        *" $i "*) exercised=1 ;;
      esac
      [ "${sets[$j]}" != "$i" ] || sole=1
      j=$((j + 1))
    done
    if [ "$exercised" -eq 0 ]; then
      printf 'dead %s\n' "$(pm_path_deny_rule_at "$i")"
    elif [ "$sole" -eq 0 ]; then
      printf 'shadowed %s\n' "$(pm_path_deny_rule_at "$i")"
    fi
    i=$((i + 1))
  done
}
uncovered="$(path_rules_uncovered)"
if [ -z "$uncovered" ]; then
  ok "every path deny rule is the sole cover for at least one path fixture row"
else
  while IFS=' ' read -r why rule; do
    case "$why" in
      dead) fail "path deny rule is never exercised by any path fixture row (dead rule or missing row): $rule" ;;
      *) fail "path deny rule is the sole cover for no path fixture row, so it can be deleted with a green suite: $rule" ;;
    esac
  done <<EOF
$uncovered
EOF
fi
# The pass must be able to fail: a duplicated rule shadows itself, and a rule
# no row reaches is dead.
injected="$(
  pm_load_rules "$DENY_RULES
Edit(//**/.envrc)
Edit(//nowhere/x)" "$ASK_RULES" "$ALLOW_RULES" >/dev/null 2>&1
  pm_path_compile
  path_rules_uncovered | tr '\n' ' '
)"
case "$injected" in
  *'shadowed Edit(//**/.envrc)'*'dead Edit(//nowhere/x)'*)
    ok "the path coverage pass names a shadowed and a dead path rule"
    ;;
  *) fail "the path coverage pass missed an injected shadowed or dead rule: $injected" ;;
esac
if [ "$PM_PATH_DENY_N" -gt 0 ]; then
  ok "the shipped deny block carries $PM_PATH_DENY_N path rule(s)"
else
  fail "the shipped deny block carries no path rules (REQ-F1.6, REQ-G1.8, REQ-E1.6)"
fi

# The model's path branches the shipped profile does not use, each against a
# synthetic rule set (M10, M11). Each probe loads inside its own substitution,
# so the shipped rules stay loaded here.
path_probe() {
  # path_probe <expected> <label> <deny> <ask> <allow> <tool> <path>
  local got
  got="$(
    pm_load_rules "Bash(never-run *)
$3" "$4" "$5" >/dev/null 2>&1
    pm_decide_path "$6" "$7"
  )"
  if [ "$got" = "$1" ]; then
    ok "path model: $2"
  else
    fail "path model: $2 (expected $1, got $got)"
  fi
}
path_probe prompt 'a Write(path) deny rule never matches (M11)' 'Write(//tmp/x)' '' '' Write /tmp/x
path_probe prompt 'a NotebookEdit(path) deny rule never matches (M11)' 'NotebookEdit(//tmp/x)' '' '' NotebookEdit /tmp/x
path_probe deny 'an Edit deny governs the NotebookEdit tool' 'Edit(//tmp/x)' '' 'NotebookEdit' NotebookEdit /tmp/x
path_probe ask 'an Edit ask rule asks' '' 'Edit(//tmp/x)' 'Edit' Edit /tmp/x
path_probe allow 'an Edit allow rule allows inside its directory' '' '' 'Edit(src/**)' Edit "$PM_CWD/src/a.ts"
path_probe prompt 'an Edit allow rule leaves the rest to the prompt' '' '' 'Edit(src/**)' Edit "$PM_CWD/vendor/src/a.ts"
path_probe prompt 'a Read allow rule does not admit the edit tools' '' '' 'Read(//tmp/**)' Edit /tmp/x
path_probe deny 'a bare Edit deny removes the tool whatever the allow list says' 'Edit' '' 'Edit' Edit /tmp/x
path_probe ask 'a bare Read ask covers the edit tools too' '' 'Read' 'Edit' Edit /tmp/x
path_probe deny 'a single-slash pattern anchors at the settings directory' 'Edit(/mise.toml)' '' 'Edit' Edit "$PM_SETTINGS_DIR/mise.toml"

# Anchors are read when a decision is made: moving the working directory in
# the same shell moves a relative rule with it, and an unset settings
# directory follows the working directory.
anchored="$(
  pm_load_rules 'Bash(never-run *)
Edit(mise.toml)
Edit(/s.toml)' '' 'Edit' >/dev/null 2>&1
  PM_CWD=/a
  unset PM_SETTINGS_DIR
  printf '%s ' "$(pm_decide_path Edit /a/mise.toml)" "$(pm_decide_path Edit /a/s.toml)"
  PM_CWD=/b
  printf '%s ' "$(pm_decide_path Edit /a/mise.toml)" "$(pm_decide_path Edit /b/mise.toml)" "$(pm_decide_path Edit /b/s.toml)"
)"
if [ "$anchored" = 'deny deny allow deny deny ' ]; then
  ok "path model: anchors are read at decision time, the settings directory defaulting to the working directory"
else
  fail "path model: anchors must be read at decision time (got: $anchored)"
fi

# Non-Bash allow entries: a bare file-tool name is exercised by an allow path
# row for that tool; the remaining tool names sit outside the model (MB-6).
OUT_OF_MODEL_ALLOW='Grep Glob'
while IFS= read -r entry; do
  case "$entry" in
    'Bash('*) continue ;;
    Read | Edit | Write)
      case "$ALLOW_TOOLS_SEEN" in
        *" $entry "*) ok "bare allow entry $entry is exercised by a path row" ;;
        *) fail "bare allow entry $entry has no allow path row" ;;
      esac
      ;;
    *)
      case " $OUT_OF_MODEL_ALLOW " in
        *" $entry "*) ok "allow entry $entry is a tool name outside the model (MB-6)" ;;
        *) fail "allow entry has no fixture row and is not declared outside the model: $entry" ;;
      esac
      ;;
  esac
done <<EOF
$ALLOW_RULES
EOF

# ---------------------------------------------------------------------------
# Pass I — the per-launch profile an opted-in launch passes (the mise
# task-file opt-in). scripts/worker-settings-generate.sh replaces the four
# task-file denies with literal denies for each of those names in every
# ancestor folder of the worktree, so the worktree's own task files open and
# every other mise path, each ancestor's task files, and the primary
# checkout's stay closed. The rows run the generated rules through the same
# model and path table machinery as pass H, and each literal ancestor deny
# must be the only rule blocking at least one row.
# ---------------------------------------------------------------------------
GEN_SCRIPT="$REPO_ROOT/scripts/worker-settings-generate.sh"
MISE_GUARD="$REPO_ROOT/scripts/worker-mise-edit-guard.sh"
mkdir -p "$tmp/gen"
GBOX=$(cd "$tmp/gen" && pwd -P)
GMAIN="$GBOX/main"
GWT="$GMAIN/.claude/worktrees/w1"
if git init -q "$GMAIN" \
  && git -C "$GMAIN" symbolic-ref HEAD refs/heads/main \
  && git -C "$GMAIN" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m init \
  && git -C "$GMAIN" worktree add -q -b planwright/flight/x-0123abcd "$GWT" main; then
  ok "pass I: built the fixture repository"
else
  fail "pass I: could not build the fixture repository"
fi
if mkdir -p "$GMAIN/.claude/worktrees/w2" "$GBOX/other/mise-tasks" "$GWT/sub2" \
  && ln -s "$GBOX/other/mise-tasks" "$GWT/sub2/mise-tasks" \
  && : >"$GBOX/other/mise.toml" && ln -s "$GBOX/other/mise.toml" "$GWT/sub2/link.toml" \
  && mkdir -p "$GBOX/other/dir" && ln -s "$GBOX/other/dir" "$GWT/dirlink" && ln -s ../mise.toml "$GBOX/other/dir/rel" \
  && mkdir -p "$GWT/chain" && ln -s "$GBOX/other/mise.toml" "$GWT/chain/l1" \
  && : >"$GWT/chain/target.txt" && ln -s "$GWT/chain/target.txt" "$GWT/chain/s1" \
  && gi=2 && while [ "$gi" -le 41 ]; do
  ln -s "$GWT/chain/l$((gi - 1))" "$GWT/chain/l$gi" || break
  gi=$((gi + 1))
done && [ "$gi" -eq 42 ] \
  && gi=2 && while [ "$gi" -le 3 ]; do
  ln -s "$GWT/chain/s$((gi - 1))" "$GWT/chain/s$gi" || break
  gi=$((gi + 1))
done && [ "$gi" -eq 4 ]; then
  ok "pass I: built the sibling, other-repository and symlink fixtures"
else
  fail "pass I: could not build the sibling, other-repository and symlink fixtures"
fi
GEN_OUT="$GBOX/generated.json"
if [ -f "$GEN_SCRIPT" ] && /bin/sh "$GEN_SCRIPT" "$SETTINGS" "$GWT" "$GEN_OUT" >/dev/null 2>"$tmp/gen.err"; then
  ok "pass I: the generator wrote a per-launch profile"
else
  fail "pass I: the generator failed ($(cat "$tmp/gen.err" 2>/dev/null))"
fi

gen_path_rows() {
  cat <<ROWS
allow|legit|Edit|$GWT/mise.toml|the opted-in worker edits its own worktree mise.toml
allow|legit|Write|$GWT/.mise.toml|its own dotted mise.toml
allow|legit|Write|$GWT/mise-tasks/deploy|its own default file-task directory
allow|legit|Edit|$GWT/.mise-tasks/deploy|its own dotted file-task directory
allow|legit|Write|$GWT/sub/mise.toml|a nested mise.toml inside its own worktree
allow|legit|Write|$GWT/sub/mise-tasks/x|a nested task directory inside its own worktree
deny|load-bearing|Edit|/work/unrelated/mise.toml|an unrelated repository's mise.toml stays closed: only the worker's own worktree opens
deny|load-bearing|Write|$GMAIN/.claude/worktrees/w2/mise.toml|a sibling worktree's mise.toml stays closed
deny|load-bearing|Edit|$GMAIN/.claude/worktrees/w2/mise-tasks/x|a sibling worktree's mise-tasks stays closed
deny|load-bearing|Write|$GBOX/other/mise-tasks/x|another repository's mise-tasks stays closed
deny|load-bearing|Write|$GBOX/other/.mise.toml|another repository's dotted mise.toml stays closed
deny|load-bearing|Edit|$GWT/../w2/mise.toml|a .. escape into a sibling worktree stays closed
deny|load-bearing|Write|$GWT/sub/../../../../../other/mise-tasks/x|a .. escape into another repository stays closed
deny|load-bearing|Write|$GWT/sub2/mise-tasks/x|a task directory that is a symlink pointing out of the worktree stays closed
deny|load-bearing|Edit|$GWT/sub2/link.toml|a file symlink pointing at another repository's mise.toml stays closed
deny|load-bearing|Write|~/other/mise.toml|a home-relative task path the file tools may expand stays closed
allow|legit|Edit|$GWT/scripts/x.sh|ordinary edits stay allowed
deny|load-bearing|Edit|$GWT/dirlink/rel|a relative symlink inside a symlinked directory is resolved from the directory's real location, so a ../mise.toml landing outside the worktree stays closed
deny|load-bearing|Edit|$GWT/chain/l41|a chain of 41 symlinks (longer than the resolver follows) ending at another repository's mise.toml is refused, not deferred
allow|legit|Edit|$GWT/chain/s3|a short symlink chain ending at an ordinary file inside the worktree still defers
deny|load-bearing|Edit|$GWT/mise.local.toml|machine-local mise config stays closed
deny|load-bearing|Write|$GWT/.mise.local.toml|dotted machine-local mise config stays closed
deny|load-bearing|Edit|$GWT/mise.test.toml|an environment-specific mise config stays closed
deny|load-bearing|Write|$GWT/.miserc.toml|a project miserc stays closed
deny|load-bearing|Write|$GWT/mise/conf.d/10.toml|conf.d fragments stay closed
deny|load-bearing|Write|$GWT/mise/config.toml|mise/config.toml stays closed
deny|load-bearing|Write|$GWT/mise/tasks/build|mise/tasks stays closed
deny|load-bearing|Write|$GWT/.mise/tasks/build|.mise/ stays closed
deny|load-bearing|Edit|$GWT/mise.lock|the lockfile stays closed
deny|load-bearing|Edit|$GWT/mise.local.lock|the local lockfile stays closed
deny|load-bearing|Write|/home/u/.local/state/mise/trusted-configs/x|trust state stays closed
deny|load-bearing|Write|/home/u/.local/share/mise/shims/node|the data folder stays closed
deny|load-bearing|Write|/home/u/.cache/mise/remote-git-tasks-cache/r/x|the cache folder stays closed
deny|load-bearing|Write|/tmp/planwright-1000/0123abcd/mise/x|mise temporary folders stay closed
deny|load-bearing|Edit|$GWT/.git|git entries stay closed
deny|load-bearing|Edit|$GWT/lefthook.yml|lefthook config stays closed
ROWS
  # Every ancestor of the worktree, the primary checkout included, keeps all
  # four names closed: the mise files a worktree picks up from above.
  local a
  a=$GWT
  while [ "$a" != / ] && [ -n "$a" ]; do
    a=${a%/*}
    [ -n "$a" ] || a=/
    printf 'deny|load-bearing|Edit|%s/mise.toml|the ancestor %s keeps mise.toml closed\n' "${a%/}" "$a"
    printf 'deny|load-bearing|Write|%s/.mise.toml|the ancestor %s keeps .mise.toml closed\n' "${a%/}" "$a"
    printf 'deny|load-bearing|Edit|%s/mise-tasks/x|the ancestor %s keeps mise-tasks/ closed\n' "${a%/}" "$a"
    printf 'deny|load-bearing|Write|%s/.mise-tasks/x|the ancestor %s keeps .mise-tasks/ closed\n' "${a%/}" "$a"
    printf 'deny|load-bearing|Write|%s/mise-tasks/sub/x|the ancestor %s keeps a nested task file closed\n' "${a%/}" "$a"
  done
}
GEN_FIXTURES=$(gen_path_rows)
GEN_DENY=$(read_rules "$GEN_OUT" deny 2>/dev/null) || GEN_DENY=''
GEN_ALLOW=$(read_rules "$GEN_OUT" allow 2>/dev/null) || GEN_ALLOW=''
if [ -n "$GEN_DENY" ] && pm_load_rules "$GEN_DENY" "" "$GEN_ALLOW"; then
  pm_path_compile
  PM_CWD=$GWT
  gen_rows=0
  while IFS='|' read -r expected class tool path note; do
    [ -n "${expected:-}" ] || continue
    gen_rows=$((gen_rows + 1))
    got="$(pm_decide_path "$tool" "$path")"
    # The generated profile's hook refuses what no path rule can: a task path
    # outside the worktree. An absent hook leaves the rule verdict.
    if [ "$got" = allow ] && [ -x "$MISE_GUARD" ]; then
      case $(printf '{"tool_name":"%s","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$tool" "$path" "$GWT" | "$MISE_GUARD" "$GWT") in
        *'"permissionDecision":"deny"'*) got=deny ;;
      esac
    fi
    if [ "$got" = "$expected" ]; then
      ok "pass I [$class] $expected: $tool $path"
    else
      fail "pass I [$class] expected $expected, got $got: $tool $path  ($note)"
    fi
  done <<EOF
$GEN_FIXTURES
EOF
  if [ "$gen_rows" -ge 40 ]; then
    ok "pass I: the generated-profile table is non-vacuous: $gen_rows rows"
  else
    fail "pass I: the generated-profile table shrank: $gen_rows rows"
  fi
  # Each literal ancestor deny is the only rule blocking at least one row, so
  # none can be dropped with a green suite.
  PATH_FIXTURES=$GEN_FIXTURES
  gen_uncovered=$(path_rules_uncovered | grep -E '^(dead|shadowed) Edit\(/[^*]*/?(mise\.toml|\.mise\.toml|mise-tasks/\*\*|\.mise-tasks/\*\*)\)$')
  if [ -z "$gen_uncovered" ]; then
    ok "pass I: every literal ancestor deny is the sole cover for a row"
  else
    fail "pass I: literal ancestor denies without sole cover: $gen_uncovered"
  fi
  # The hook that closes every task path outside the worktree is wired in.
  if [ -x "$MISE_GUARD" ] && jq -e --arg wt "$GWT" '[.hooks.PreToolUse[] | select(.matcher | test("Edit")) | .hooks[].command] | any(contains("worker-mise-edit-guard.sh '"'"'" + $wt + "'"'"'"))' "$GEN_OUT" >/dev/null 2>&1; then
    ok "pass I: the generated profile wires the outside-the-worktree hook for the file tools"
  else
    fail "pass I: the generated profile does not wire the outside-the-worktree hook"
  fi
  # The shipped broad rules are gone from the generated deny list.
  case "$GEN_DENY" in
    *'Edit(//**/mise.toml)'* | *'Edit(//**/mise-tasks/**)'*) fail "pass I: a broad task-file deny survived in the generated profile" ;;
    *) ok "pass I: no broad task-file deny survives in the generated profile" ;;
  esac
else
  fail "pass I: the generated rules did not load into the model"
fi
# The shipped profile is untouched by any of this: the worktree's own task
# files stay closed under it.
pm_load_rules "$DENY_RULES" "$ASK_RULES" "$ALLOW_RULES" >/dev/null 2>&1
pm_path_compile
PM_CWD=$GWT
for t in "$GWT/mise.toml" "$GWT/.mise.toml" "$GWT/mise-tasks/deploy" "$GWT/.mise-tasks/deploy"; do
  if [ "$(pm_decide_path Edit "$t")" = deny ]; then
    ok "pass I: the shipped profile still denies $t"
  else
    fail "pass I: the shipped profile admits $t"
  fi
done

if [ "$failures" -eq 0 ]; then
  echo "all permission-matcher fixture assertions passed"
  exit 0
fi
echo "$failures failure(s)" >&2
exit 1
