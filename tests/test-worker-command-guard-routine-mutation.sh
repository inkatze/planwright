#!/bin/bash
# Mutation proof for tests/test-worker-command-guard-routine.sh: each mutant is
# a deliberately broken copy of the guard that approves an unsafe case, and the
# routine suite, run against it, must fail. A suite that stays green on a
# mutant does not guard what it claims to.
# shellcheck disable=SC2016 # the sed expressions carry literal dollars
set -u
unset CDPATH
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUITE="$ROOT/tests/test-worker-command-guard-routine.sh"
LC_ALL=C
export LC_ALL

failures=0
passes=0
M=$(mktemp -d "${TMPDIR:-/tmp}/guard-mutants.XXXXXX") || exit 1
trap 'rm -rf "$M"' EXIT

# mutant <name> <sed expression>: a copy of the guard with the expression
# applied, the rest of the tree linked in so the copy finds its sibling
# scripts. A mutant that does not change the guard, or no longer parses, is a
# failure of this proof, not a pass of the suite.
mutant() {
  local name=$1 expr=$2 d="$M/$1" f
  mkdir -p "$d/scripts"
  for f in "$ROOT"/scripts/*; do
    [ "${f##*/}" = worker-command-guard.sh ] || ln -s "$f" "$d/scripts/${f##*/}"
  done
  ln -s "$ROOT/config" "$d/config"
  sed "$expr" "$ROOT/scripts/worker-command-guard.sh" >"$d/scripts/worker-command-guard.sh" || {
    printf 'FAIL: mutant %s: its sed expression is invalid\n' "$name" >&2
    failures=$((failures + 1))
    return
  }
  if cmp -s "$ROOT/scripts/worker-command-guard.sh" "$d/scripts/worker-command-guard.sh"; then
    printf 'FAIL: mutant %s did not change the guard\n' "$name" >&2
    failures=$((failures + 1))
    return
  fi
  if ! bash -n "$d/scripts/worker-command-guard.sh"; then
    printf 'FAIL: mutant %s does not parse\n' "$name" >&2
    failures=$((failures + 1))
    return
  fi
  if WCG_HOOK="$d/scripts/worker-command-guard.sh" bash "$SUITE" >"$d/out" 2>&1; then
    printf 'FAIL: the routine suite passes against mutant %s, so it does not guard that case\n' "$name" >&2
    failures=$((failures + 1))
  else
    printf 'ok: the routine suite fails against mutant %s (%s)\n' "$name" "$(grep -c '^FAIL' "$d/out") failing rows"
    passes=$((passes + 1))
  fi
}

mutant mix-ignores-the-diff 's@^mix_tree_clean() {$@mix_tree_clean() { return 0;@'
mutant mix-treats-code-as-inert 's@^mix_path_inert() {$@mix_path_inert() { return 0;@'
mutant mix-ignores-hidden-flags 's@^  \[ "\${st\[0\]}" = 0 \] \&\& \[ "\${st\[1\]}" = 1 \] || return 1$@  :@'
mutant mix-trusts-a-shadowable-base 's@show-ref --verify -s "refs/remotes/\$base"@rev-parse --verify -q "$base"@'
mutant thread-needs-no-bot 's@^thread_bot_only() {$@thread_bot_only() { return 0;@'
mutant thread-ignores-the-unit-pr 's@\[ -n "\$REC_UNIT" \] \&\& \[ "\$unit_url" = "https://github.com/\$2/pull/\$3" \]$@true@'
mutant thread-lets-a-human-in 's@or (.user.type == "User" and .user.login == \$v)@or true@'
mutant review-state-runs-argv 's@^    register | unregister | sessions) ;;$@    register | unregister | sessions | evidence) ;;@'

printf '\nrouting mutation suite: %s passed, %s failed\n' "$passes" "$failures"
[ "$failures" -eq 0 ]
