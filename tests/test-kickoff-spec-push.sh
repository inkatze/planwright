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
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_NAMESPACE GIT_PREFIX

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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-kickoff-spec-push.XXXXXX") || fail "could not create a scratch directory"
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

long=$(printf 'a%.0s' $(seq 1 65))
for spec in '' 'Demo' '../demo' 'demo/x' '-f' 'de mo' 'demo;x' 'main' 'planwright/demo' flight "$long"; do
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

# --- the spec's own amendment branch -------------------------------------------

g -C "$clone" switch -q -c planwright/demo/amendment-3
g -C "$clone" commit -q --allow-empty -m "amendment sign-off"
amend_head=$(g -C "$clone" rev-parse HEAD)
(cd "$clone" && "$SCRIPT" demo) >/dev/null 2>&1 || fail "the push on the spec's own amendment branch did not succeed"
[ "$(g -C "$origin" rev-parse planwright/demo/amendment-3)" = "$amend_head" ] || fail "the amendment branch on origin is not the local head after the push"
upstream=$(g -C "$clone" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || upstream=''
[ "$upstream" = origin/planwright/demo/amendment-3 ] || fail "the amendment push did not set the upstream (got '$upstream')"
pass "[amendment] the spec's own amendment branch pushes and sets its upstream"

if (cd "$clone" && "$SCRIPT" other) >/dev/null 2>&1; then
  fail "another spec's name pushed from demo's amendment branch"
fi
pass "[amendment] another spec's name refuses from this amendment branch"

for bad in amendment-3b amendment- amendment amendment-3-1 amendment-x; do
  g -C "$clone" switch -q -c "planwright/demo/$bad"
  if (cd "$clone" && "$SCRIPT" demo) >/dev/null 2>&1; then
    fail "a non-digit amendment suffix pushed ($bad)"
  fi
  if g -C "$origin" rev-parse --verify -q "planwright/demo/$bad" >/dev/null; then
    fail "a refused amendment suffix reached origin ($bad)"
  fi
  g -C "$clone" switch -q planwright/demo/amendment-3
done
pass "[amendment] a non-digit or empty amendment suffix refuses and pushes nothing"

g -C "$clone" switch -q -c planwright/other/amendment-1
if (cd "$clone" && "$SCRIPT" demo) >/dev/null 2>&1; then
  fail "another spec's amendment branch pushed under demo"
fi
pass "[amendment] another spec's amendment branch refuses"
refusal=$(cd "$clone" && "$SCRIPT" demo 2>&1) && fail "the wrong-branch run succeeded"
# shellcheck disable=SC2016 # the unexpanded variable is the text under test
case $refusal in
  *'${CLAUDE_PLUGIN_ROOT}/scripts/kickoff-spec-push.sh <spec>'*) ;;
  *) fail "[refusal] the wrong-branch text does not name the accepted form: $refusal" ;;
esac
pass "[refusal] the wrong-branch text names the accepted form"
g -C "$clone" switch -q planwright/demo/amendment-3
mkdir -p "$clone/specs/demo"
printf '# Requirements\n\nStatus: Ready\n' >"$clone/specs/demo/requirements.md"
g -C "$clone" add specs/demo/requirements.md
g -C "$clone" commit -q -m "mark demo Ready"
(cd "$clone" && "$SCRIPT" demo) >/dev/null 2>&1 || fail "[amendment] a Ready spec's amendment branch refused to push"
[ "$(g -C "$origin" rev-parse planwright/demo/amendment-3)" = "$(g -C "$clone" rev-parse HEAD)" ] || fail "[amendment] the Ready spec's amendment push did not reach origin"
pass "[amendment] the push takes no account of spec status: a Ready spec's amendment branch pushes"
g -C "$clone" switch -q planwright/demo/spec

skill="$here/../skills/spec-kickoff/SKILL.md"
grep -qF 'or `planwright/<spec>/amendment-<n>` for an amendment' "$skill" || fail "[doc] /spec-kickoff does not name the amendment branch"
pass "[doc] /spec-kickoff names the amendment branch"

# --- the adopter's pre-push hook runs under the caller's locale ----------------
# The script parses under LC_ALL=C, but the hook is the adopter's: a C locale
# there broke UTF-8 file names (Elixir fell back to latin1).

loc="$tmp/loc"
g clone -q "$origin" "$loc"
g -C "$loc" switch -q -c planwright/loc/spec
hooklog="$tmp/hook-locale"
cat >"$loc/.git/hooks/pre-push" <<HOOK
#!/bin/sh
l=\${LC_ALL:-\${LC_CTYPE:-\${LANG:-C}}}
printf '%s\n' "\$l" >"$hooklog"
case \$l in
  *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*) exit 0 ;;
  *) echo "pre-push: non-UTF-8 locale: \$l" >&2; exit 1 ;;
esac
HOOK
chmod +x "$loc/.git/hooks/pre-push"

loc_push() {
  g -C "$loc" commit -q --allow-empty -m "loc commit"
  rm -f "$hooklog"
  (cd "$loc" && env "$@" "$SCRIPT" loc) >"$tmp/loc.out" 2>&1
}

loc_push -u LC_ALL -u LC_CTYPE LANG=C.UTF-8 \
  || fail "a UTF-8 LANG from the caller did not reach the pre-push hook: $(cat "$tmp/loc.out")"
[ "$(cat "$hooklog")" = C.UTF-8 ] || fail "the hook saw '$(cat "$hooklog")', not the caller's LANG"
pass "a caller with only LANG set gives the pre-push hook its own locale, not C"

loc_push -u LANG -u LC_CTYPE LC_ALL=de_DE.UTF-8 \
  || fail "a UTF-8 LC_ALL from the caller did not reach the pre-push hook: $(cat "$tmp/loc.out")"
[ "$(cat "$hooklog")" = de_DE.UTF-8 ] || fail "the hook saw '$(cat "$hooklog")', not the caller's LC_ALL"
pass "a caller's LC_ALL is what the pre-push hook sees"

loc_push -u LC_ALL -u LANG -u LC_CTYPE \
  || fail "a caller with no locale got a non-UTF-8 pre-push hook: $(cat "$tmp/loc.out")"
[ "$(cat "$hooklog")" = C.UTF-8 ] || fail "the hook saw '$(cat "$hooklog")', not the C.UTF-8 default"
pass "a caller with no locale gives the pre-push hook C.UTF-8"

# Near miss: the script's own parsing stays byte-strict under a non-C caller.
for spec in '' 'Demo' 'démo' '../demo' 'demo/x' '-f' 'de mo' flight; do
  if (cd "$loc" && env LC_ALL=en_US.UTF-8 "$SCRIPT" "$spec") >/dev/null 2>&1; then
    fail "a spec name outside the grammar ran under a UTF-8 caller (\"$spec\")"
  fi
done
if (cd "$clone" && env LC_ALL=en_US.UTF-8 "$SCRIPT" demo) >/dev/null 2>&1; then
  fail "a run from the wrong branch succeeded under a UTF-8 caller"
fi
pass "spec-name and branch checks refuse the same under a non-C caller locale"

# --- the script never names a force --------------------------------------------

if grep -Eq -- '--force|--mirror|--delete|push -[a-zA-Z]*f|[[:space:]]\+[a-zA-Z]|--all|--tags' "$SCRIPT"; then
  fail "scripts/kickoff-spec-push.sh names a force, bulk or delete form"
fi
pass "the script names no force, bulk or delete push"

echo "PASS: test-kickoff-spec-push"
