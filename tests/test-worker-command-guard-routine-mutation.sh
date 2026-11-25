#!/bin/bash
# Mutation proof for tests/test-worker-command-guard-routine.sh: each mutant is
# a deliberately broken copy of the guard that approves an unsafe case, and the
# routine suite, run against it, must fail. A suite that stays green on a
# mutant does not guard what it claims to. The mutants run side by side.
# shellcheck disable=SC2016 # the sed expressions carry literal dollars
set -u
unset CDPATH
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUITE="$ROOT/tests/test-worker-command-guard-routine.sh"
LC_ALL=C
export LC_ALL

M=$(mktemp -d "${TMPDIR:-/tmp}/guard-mutants.XXXXXX") || exit 1
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$M"' EXIT
names=()

# mutant <name> <sed expression>: a copy of the guard with the expression
# applied, the rest of the tree linked in so the copy finds its sibling
# scripts, its verdict left in <dir>/verdict. A mutant that does not change the
# guard, or no longer parses, is a failure of this proof, not a pass of the
# suite.
mutant() {
  local name=$1 expr=$2 d="$M/$1" f
  names+=("$name")
  mkdir -p "$d/scripts"
  for f in "$ROOT"/scripts/*; do
    [ "${f##*/}" = worker-command-guard.sh ] || ln -s "$f" "$d/scripts/${f##*/}"
  done
  ln -s "$ROOT/config" "$d/config"
  sed "$expr" "$ROOT/scripts/worker-command-guard.sh" >"$d/scripts/worker-command-guard.sh" || {
    echo "FAIL: mutant $name: its sed expression is invalid" >"$d/verdict"
    return
  }
  if cmp -s "$ROOT/scripts/worker-command-guard.sh" "$d/scripts/worker-command-guard.sh"; then
    echo "FAIL: mutant $name did not change the guard" >"$d/verdict"
    return
  fi
  if ! bash -n "$d/scripts/worker-command-guard.sh"; then
    echo "FAIL: mutant $name does not parse" >"$d/verdict"
    return
  fi
  (
    if WCG_HOOK="$d/scripts/worker-command-guard.sh" bash "$SUITE" >"$d/out" 2>&1; then
      echo "FAIL: the routine suite passes against mutant $name, so it does not guard that case" >"$d/verdict"
    else
      echo "ok: the routine suite fails against mutant $name ($(grep -c '^FAIL' "$d/out") failing rows)" >"$d/verdict"
    fi
  ) &
}

mutant mix-ignores-the-diff 's@^mix_tree_clean() {$@mix_tree_clean() { return 0;@'
mutant mix-treats-code-as-inert 's@^mix_path_inert() {$@mix_path_inert() { return 0;@'
mutant mix-ignores-hidden-flags 's@^mix_tags_plain() {$@mix_tags_plain() { cat >/dev/null; return 0;@'
mutant mix-trusts-a-shadowable-base 's@show-ref --verify -s "refs/remotes/\$base"@rev-parse --verify -q "$base"@'
mutant mix-ignores-an-earlier-write 's@^  \[ "\$ARM_ACT" = 0 \] [&][&] \[ "\$OB_WROTE" = 0 \].*$@  :@'
mutant mix-ignores-an-assignment '/^mix_run_ok() {$/,/^}$/s@^  \[ "\$VAR_C" -eq 0 \] || return 1$@  :@'
mutant review-state-allows-a-script-in-the-worktree 's@^      \*:"\$REC_WT"/\*) return 1 ;;$@      *:"$REC_WT"/*) ;;@'
mutant mix-trusts-core-worktree 's@ --work-tree="\$REC_WT"@@'
mutant review-state-ignores-an-assignment '/^review_state_call_ok() {$/,/^}$/s@^  \[ "\$VAR_C" -eq 0 \] || return 1$@  :@'
mutant thread-needs-no-bot 's@^thread_bot_only() {$@thread_bot_only() { return 0;@'
mutant thread-ignores-the-unit-pr 's@\[ -n "\$REC_UNIT" \] [&][&] \[ "\$unit_url" = "https://github.com/\$2/pull/\$3" \]$@true@'
mutant thread-lets-a-human-in 's@or (.user.type == "User" and .user.login == \$v)@or true@'
mutant review-state-runs-argv 's@^    register | unregister | sessions) ;;$@    register | unregister | sessions | evidence) ;;@'

wait
failures=0
passes=0
for n in "${names[@]}"; do
  v=$(cat "$M/$n/verdict" 2>/dev/null) || v="FAIL: mutant $n left no verdict"
  case $v in
    ok:*) passes=$((passes + 1)) ;;
    *) failures=$((failures + 1)) ;;
  esac
  printf '%s\n' "$v"
done
printf '\nroutine mutation suite: %s passed, %s failed\n' "$passes" "$failures"
[ "$failures" -eq 0 ]
