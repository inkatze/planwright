#!/bin/bash
# Fixture-driven permission-matcher test for the worker deny list
# (guard-coverage Task 1; REQ-A1.1, REQ-A1.2, REQ-H1.3; D-4).
#
# WHAT THIS PINS. config/worker-settings.json's deny block is planwright's
# best-effort glob layer against a worker force-pushing, pushing to main,
# amending/squashing/fixing up a commit, or bypassing the githooks/ backstop.
# Glob rules are easy to write and easy to silently break: a rule whose `:*`
# lands mid-pattern never fires, a rule anchored at end-of-string is evaded by
# one trailing flag, and a rule can be deleted with a green suite if nothing
# asserts it. This test closes all three by asserting a fixture table of real
# `git push` / `git commit` invocations against a DOCUMENTED MODEL of Claude
# Code's matcher (tests/lib/permission-matcher.sh, D-4) plus the real shipped
# config.
#
# WHAT IT DOES NOT PIN. The model is a re-implementation, not the matcher: this
# test verifies config-vs-model equivalence only. Real-matcher fidelity is the
# manual re-verify recorded as risk row 1 of the kickoff brief. The modeled
# behavior version, sources consulted, modeling boundaries, and the unsettled
# assumption MA-1 are all in docs/permission-matcher-model.md.
#
#   Modeled behavior version: Claude Code CLI 2.1.220 / docs as of 2026-07-29.
#
# The five passes:
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
#      fail-safe cost). Class and expectation are cross-checked, so a mislabeled
#      row fails.
#   C. Fail-closed — an empty deny set and an unparseable config must both
#      error, never read as a vacuously green table (REQ-H1.3).
#   D. No dead rules — every deny rule must be exercised by at least one
#      fixture row, so a rule that can never fire cannot ship unnoticed.
#   E. Mutation — for every deny rule that is the SOLE cover for some
#      expected-deny row, removing it flips that row. Rules that are covered
#      redundantly are declared in REDUNDANT_BY_DESIGN with a reason, so
#      redundancy is a reviewed decision rather than silent dead weight.
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
# A deny rule matches past any leading environment assignment.
if [ "$(pm_decide 'FOO=bar never-run x')" = "deny" ]; then
  ok "deny matches past a leading environment assignment"
else
  fail "deny should match past a leading environment assignment"
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
FIXTURES=$(
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
deny|load-bearing|git push --mirror origin|bulk-ref escape hatch
deny|load-bearing|git push origin --mirror|bulk-ref escape hatch after the remote
deny|load-bearing|git push --all origin|bulk-ref escape hatch
deny|load-bearing|git push origin --all|bulk-ref escape hatch after the remote
deny|load-bearing|git commit --amend|bare amend
deny|load-bearing|git commit --amend -m "reworded"|--amend -m family
deny|load-bearing|git commit --amend -F /tmp/msg|--amend -F family
deny|load-bearing|git commit --amend --no-edit|amend with a trailing flag
deny|load-bearing|git commit -m "wip" --amend|flag-after-arg amend
deny|load-bearing|git commit -a -m "wip" --amend --no-edit|flag-after-arg amend, mid-command
deny|load-bearing|git commit --squash HEAD~1|squash, space-separated argument
deny|load-bearing|git commit --squash=HEAD~1|squash, =-suffixed argument
deny|load-bearing|git commit -m "wip" --squash HEAD~1|flag-after-arg squash
deny|load-bearing|git commit --fixup HEAD~1|fixup, space-separated argument
deny|load-bearing|git commit --fixup=HEAD~1|fixup, =-suffixed argument
deny|load-bearing|git commit --fixup=amend:HEAD~1|--fixup=amend: produces an amend! subject
deny|load-bearing|git commit --fixup=reword:HEAD~1|--fixup=reword: produces an amend! subject
deny|load-bearing|git commit -m "wip" --fixup=amend:HEAD~1|flag-after-arg =-suffixed fixup
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
deny|load-bearing|git rebase --autosquash origin/main|rebase is a hard invariant
deny|load-bearing|git rebase -i HEAD~3|interactive rebase
deny|load-bearing|git merge main|merge is a reserved human action
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
prompt|residual|git push -u origin planwright/guard-coverage/task-1|the first push of a task branch is NOT covered by Bash(git push origin:*): -u sits before the remote, so it falls through to the prompt. Recorded, not widened — an allow-list change is a permissions widening that needs sign-off
allow|legit|git push origin HEAD:refs/heads/planwright/guard-coverage/task-1|explicit refspec to a task branch
allow|legit|git push origin main-fix|a branch whose name merely starts with main stays pushable
allow|legit|git push origin HEAD:main-fix|refspec to a branch whose name starts with main
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
prompt|residual|git push|no destination in the text at all; on a branch whose upstream is main this pushes main — githooks/pre-push is the enforcement layer
allow|residual|git push origin HEAD|destination depends on the checked-out branch, which the glob layer cannot see — githooks/pre-push covers it
prompt|residual|git -c Core.HooksPath=/dev/null commit -m "wip"|mixed-case config key: git accepts it, the literal glob does not match, and the hook layer is exactly what it disabled — accepted residual, no backstop
prompt|residual|GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git commit -m "wip"|config injection through environment variables rather than argv; deny rules match past leading assignments so the hooksPath text is never in the matched string — accepted residual
allow|residual|git commit -a --amen|a mistyped flag git itself rejects; recorded so the amend coverage is not read as prefix-based
deny|overblock|git commit -m "docs: describe the -n flag in the guide"|a commit message containing " -n " is denied; fail-safe, rephrase the message
deny|overblock|git commit -m "fix: handle --no-verify in the wrapper"|a commit message naming --no-verify is denied; fail-safe
deny|overblock|git commit -m "docs: use --amend carefully"|a commit message naming --amend is denied; fail-safe
ROWS
)

# Row-level assertions, and (in the same pass) the per-row set of matching deny
# rule indices that passes D and E consume.
row_total=0
row_deny_total=0
MATCH_SETS=()
match_n=0

# deny_match_indices <command> — print the indices of every deny rule matching
# any subcommand of the command, space separated.
deny_match_indices() {
  local sub stripped i out=""
  while IFS= read -r sub; do
    sub="$(pm_trim "$sub")"
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
$(pm_split_command "$1")
EOF
  printf '%s' "${out# }"
}

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
  else
    fail "[$class] expected $expected, got $got: $command  ($note)"
  fi

  if [ "$expected" = "deny" ]; then
    row_deny_total=$((row_deny_total + 1))
    MATCH_SETS[match_n]="$(deny_match_indices "$command")"
    match_n=$((match_n + 1))
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
ROW_FLOOR=95
DENY_ROW_FLOOR=74
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
REDUNDANT_BY_DESIGN=$(
  cat <<'ROWS'
Bash(git push --force:*)|subsumed by Bash(git push --force*); kept as the explicit spelling of the plain force flag
Bash(git push --force-with-lease:*)|subsumed by Bash(git push --force*); kept as the explicit spelling of the lease form
Bash(git push *:main)|subsumed by Bash(git push *:main *); kept as a hedge on the trailing-space word-boundary rule (doc rule M4)
Bash(git push * main)|subsumed by Bash(git push * main *); same M4 hedge
Bash(git push *heads/main)|subsumed by Bash(git push *heads/main *); same M4 hedge
Bash(git push *refs/heads/main)|subsumed by the broader Bash(git push *heads/main) pair; kept as the explicit fully-qualified spelling
Bash(git push *refs/heads/main *)|subsumed by the broader Bash(git push *heads/main *); kept as the explicit fully-qualified spelling
Bash(git commit --squash:*)|subsumed by Bash(git commit --squash*); kept as the explicit space-separated spelling
Bash(git commit --fixup:*)|subsumed by Bash(git commit --fixup*); kept as the explicit space-separated spelling
ROWS
)
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

if [ "$failures" -eq 0 ]; then
  echo "all permission-matcher fixture assertions passed"
  exit 0
fi
echo "$failures failure(s)" >&2
exit 1
