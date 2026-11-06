#!/bin/bash
# Tests for scripts/kickoff-spec-push.sh, the sanctioned route a kickoff
# session pushes its own spec branch by: a plain push of
# planwright/<spec>/spec from that branch, never forced, nothing else. The
# policy guard decides which session may run it (tests/test-policy-guard.sh);
# these cases pin what the script itself will and will not push.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-kickoff-spec-push.sh
set -euf
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$here/../scripts/kickoff-spec-push.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
pass() {
  echo "ok: $1"
}

[ -x "$SCRIPT" ] || fail "scripts/kickoff-spec-push.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

g() {
  git -c init.defaultBranch=main -c user.name=t -c user.email=t@example.invalid "$@"
}

origin="$tmp/origin.git"
seed="$tmp/seed"
g init -q --bare "$origin"
g init -q "$seed"
g -C "$seed" commit -q --allow-empty -m base
g -C "$seed" remote add origin "$origin"
g -C "$seed" push -q origin main
g -C "$seed" switch -q -c planwright/demo/spec
g -C "$seed" commit -q --allow-empty -m "kickoff sign-off"
g -C "$seed" push -q origin planwright/demo/spec
g -C "$seed" switch -q -c planwright/demo/task-1
g -C "$seed" push -q origin planwright/demo/task-1

clone="$tmp/clone"
g clone -q "$origin" "$clone"
g -C "$clone" switch -q planwright/demo/spec
g -C "$clone" commit -q --allow-empty -m "sign-off record"
local_head=$(g -C "$clone" rev-parse HEAD)
remote_before=$(g -C "$origin" rev-parse planwright/demo/spec)

# --- the one allowed push ----------------------------------------------------

(cd "$clone" && "$SCRIPT" demo) >/dev/null 2>&1 || fail "the kickoff push on its own spec branch did not succeed"
remote_after=$(g -C "$origin" rev-parse planwright/demo/spec)
[ "$remote_after" = "$local_head" ] || fail "the spec branch on origin is not the local head after the push"
[ "$remote_before" != "$remote_after" ] || fail "the push moved nothing"
pass "a plain push of the spec branch lands its local head on origin"
upstream=$(g -C "$clone" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || upstream=''
[ "$upstream" = origin/planwright/demo/spec ] || fail "the push did not set the upstream (got '$upstream')"
pass "the push sets the upstream to origin/planwright/demo/spec"

# --- refusals push nothing ---------------------------------------------------

other="$tmp/other"
g clone -q "$origin" "$other"
g -C "$other" switch -q planwright/demo/spec
g -C "$other" commit -q --allow-empty -m "a diverging sign-off"
g -C "$other" push -q origin planwright/demo/spec
diverged=$(g -C "$origin" rev-parse planwright/demo/spec)
g -C "$clone" commit -q --allow-empty -m "a second local commit"
if (cd "$clone" && "$SCRIPT" demo) >/dev/null 2>&1; then
  fail "a non-fast-forward push succeeded"
fi
[ "$(g -C "$origin" rev-parse planwright/demo/spec)" = "$diverged" ] || fail "a refused push moved origin's spec branch"
pass "a non-fast-forward push is refused and moves nothing"

if (cd "$clone" && "$SCRIPT" demo) >/dev/null 2>&1; then
  fail "a second run succeeded on a branch that is no longer a fast-forward"
fi
pass "a repeated run is refused as the refused push was"

g -C "$clone" switch -q planwright/demo/task-1
task_before=$(g -C "$origin" rev-parse planwright/demo/task-1)
if (cd "$clone" && "$SCRIPT" demo) >/dev/null 2>&1; then
  fail "the script pushed from a branch other than planwright/demo/spec"
fi
[ "$(g -C "$origin" rev-parse planwright/demo/task-1)" = "$task_before" ] || fail "a wrong-branch run moved a task branch"
pass "run from another branch, the script refuses and pushes nothing"
g -C "$clone" switch -q planwright/demo/spec

for spec in '' 'Demo' '../demo' 'demo/x' '-f' 'de mo' 'demo;x' 'main' 'planwright/demo'; do
  if (cd "$clone" && "$SCRIPT" "$spec") >/dev/null 2>&1; then
    fail "a spec name the script does not accept ran (\"$spec\")"
  fi
done
pass "spec names outside the spec-name grammar are refused"

if (cd "$clone" && "$SCRIPT" demo extra) >/dev/null 2>&1; then
  fail "an extra argument was accepted"
fi
if (cd "$clone" && "$SCRIPT") >/dev/null 2>&1; then
  fail "a run with no spec was accepted"
fi
pass "a missing or extra argument is refused"

# --- the script never names a force --------------------------------------------

if grep -Eq -- '--force|--mirror|--delete|push -[a-zA-Z]*f|[[:space:]]\+[a-zA-Z]|--all|--tags' "$SCRIPT"; then
  fail "scripts/kickoff-spec-push.sh names a force, bulk or delete form"
fi
pass "the script names no force, bulk or delete push"

echo "PASS: test-kickoff-spec-push"
