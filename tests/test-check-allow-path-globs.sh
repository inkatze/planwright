#!/bin/bash
# Tests for scripts/check-allow-path-globs.sh and the matcher facts it rests on.
#
# Three behaviours under test:
#   1. The bypass premise, against the permission-matcher model: a wildcard in
#      an allow rule's command path admits a `../` walk out of that path, and
#      the safe replacement (an exact script path, no `*` in it) does not.
#   2. The checker flags a path-wildcard allow rule in a settings file, names
#      the safe replacement, passes the legitimate command rules, fails closed
#      on a bad input, and never writes the file it reads.
#   3. The shipped profiles and the repo's documentation carry no such rule.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-allow-path-globs.sh"
CACHE=/home/u/.claude/plugins/cache/planwright/planwright

failures=0
assert() {
  # assert <name> <expected-exit> <actual-exit>
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker script missing at $CHECKER" >&2
  exit 1
fi

# shellcheck disable=SC1091
. "$REPO_ROOT/tests/lib/permission-matcher.sh"

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# --- 1. Matcher premise -----------------------------------------------------

ROOT=/abs/path/to/planwright
pm_load_rules 'Bash(git push --force:*)' '' "Bash($ROOT/scripts/*)
Bash($CACHE/*/scripts/fleet-streamjson.sh answer *)
Bash($CACHE/0.67.0/scripts/fleet-streamjson.sh answer *)"

if [ "$(pm_decide "$ROOT/scripts/../../../bin/anything foo")" = allow ]; then rc=0; else rc=1; fi
assert "scripts/* admits ../../../bin/<x> (premise)" 0 $rc

if [ "$(pm_decide "$CACHE/0.67.0/../../../../../../bin/rm -rf /tmp/victim/scripts/fleet-streamjson.sh answer y")" = allow ]; then rc=0; else rc=1; fi
assert "version glob admits a ../ walk to bin/rm (premise)" 0 $rc

# Rules from the safe form only: the literal version path with a trailing args
# glob. The path cannot be widened, so a traversal in the command path falls
# through to the prompt.
pm_load_rules 'Bash(git push --force:*)' '' "Bash($CACHE/0.67.0/scripts/fleet-streamjson.sh answer *)"

if [ "$(pm_decide "$CACHE/0.67.0/scripts/fleet-streamjson.sh answer y")" = allow ]; then rc=0; else rc=1; fi
assert "exact script path still allows its own command" 0 $rc

if [ "$(pm_decide "$CACHE/0.67.0/../../../../../../bin/rm -rf /tmp/victim")" != allow ]; then rc=0; else rc=1; fi
assert "exact script path does not admit a ../ walk" 0 $rc

# --- 2. Checker -------------------------------------------------------------

write_settings() {
  # write_settings <file> <allow-json-array-body>
  printf '{"permissions":{"allow":[%s],"deny":["Bash(/x/*)"]}}\n' "$2" >"$1"
}

expect_flag() {
  # expect_flag <name> <allow-entry-json>
  local f="$tmp/flag-$RANDOM.json" err="$tmp/err"
  write_settings "$f" "$2"
  bash "$CHECKER" "$f" >/dev/null 2>"$err"
  assert "flags $1" 1 $?
  grep -q "exact script path" "$err" || assert "names the safe replacement for $1" 0 1
}

expect_flag "scripts dir glob" '"Bash(/abs/planwright/scripts/*)"'
expect_flag "version glob with args" "\"Bash($CACHE/*/scripts/fleet-streamjson.sh answer *)\""
expect_flag "relative scripts glob" '"Bash(scripts/*)"'
expect_flag "basename glob" '"Bash(/abs/planwright/scripts/check-*.sh *)"'
expect_flag "literal parent segment" '"Bash(/abs/planwright/../bin/tool *)"'

expect_clean() {
  # expect_clean <name> <allow-entry-json>
  local f="$tmp/clean-$RANDOM.json"
  write_settings "$f" "$2"
  bash "$CHECKER" "$f" >/dev/null 2>&1
  assert "passes $1" 0 $?
}

expect_clean "exact script path with args" '"Bash(/abs/planwright/scripts/fleet-streamjson.sh answer *)"'
expect_clean "command-boundary path rule" '"Bash(/abs/tool:*)"'
expect_clean "plain command glob" '"Bash(git status:*)","Bash(mise run:*)"'
expect_clean "wildcard in arguments only" '"Bash(git push * planwright/*/spec *)"'
expect_clean "non-Bash allow entries" '"Read","Edit"'

f="$tmp/deny-only.json"
printf '{"permissions":{"deny":["Bash(/x/*)"],"allow":["Bash(git status:*)"]}}\n' >"$f"
bash "$CHECKER" "$f" >/dev/null 2>&1
assert "a path glob in deny is not an allow finding" 0 $?

f="$tmp/bad.json"
printf '{"permissions": {' >"$f"
bash "$CHECKER" "$f" >/dev/null 2>&1
assert "invalid JSON fails closed" 2 $?

bash "$CHECKER" "$tmp/does-not-exist.json" >/dev/null 2>&1
assert "missing file fails closed" 2 $?

f="$tmp/readonly.json"
write_settings "$f" '"Bash(/abs/planwright/scripts/*)"'
before=$(cksum <"$f")
bash "$CHECKER" "$f" >/dev/null 2>&1
after=$(cksum <"$f")
if [ "$before" = "$after" ]; then rc=0; else rc=1; fi
assert "the checker never writes the settings it reads" 0 $rc

home="$tmp/home"
mkdir -p "$home/.claude" "$tmp/nogit"
write_settings "$home/.claude/settings.json" '"Bash(/abs/planwright/scripts/*)"'
(cd "$tmp/nogit" && HOME="$home" bash "$CHECKER" >/dev/null 2>&1)
assert "no-argument mode reads user settings and flags" 1 $?

rm -f "$home/.claude/settings.json"
(cd "$tmp/nogit" && HOME="$home" bash "$CHECKER" >/dev/null 2>&1)
assert "no-argument mode with no settings files passes" 0 $?

# --- 2b. Hooks defer the traversal ------------------------------------------
# The version-independent safe form is the planwright PreToolUse hooks, which
# canonicalize the command path. Both must defer a `..` walk and a symlink that
# escapes the repo, and still approve a plain script in the repo.

hook_verdict() {
  # hook_verdict <hook> <cwd> <command> -> allow | defer
  local out
  out=$(jq -n --arg c "$3" --arg w "$2" \
    '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}' \
    | env -u CLAUDE_DIR HOME="$tmp/nohome" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
      PLANWRIGHT_ROOT="$REPO_ROOT" /bin/bash "$1" 2>/dev/null)
  case $out in
    *'"permissionDecision"'*'"allow"'*) echo allow ;;
    *) echo defer ;;
  esac
}

fix="$tmp/fixture-repo"
mkdir -p "$fix/.git" "$fix/scripts"
printf '#!/bin/sh\necho real\n' >"$fix/scripts/real.sh"
ln -s /bin/true "$fix/scripts/link.sh"

for hook in worker-command-guard.sh tower-command-guard.sh; do
  h="$REPO_ROOT/scripts/$hook"
  if [ "$(hook_verdict "$h" "$fix" "$fix/scripts/real.sh --x")" = allow ]; then rc=0; else rc=1; fi
  assert "$hook approves a plain in-repo script" 0 "$rc"
  if [ "$(hook_verdict "$h" "$fix" "$fix/scripts/../../../bin/rm -rf $tmp/victim")" = defer ]; then rc=0; else rc=1; fi
  assert "$hook defers a ../ walk out of scripts/" 0 "$rc"
  if [ "$(hook_verdict "$h" "$fix" "$fix/scripts/link.sh --x")" = defer ]; then rc=0; else rc=1; fi
  assert "$hook defers a symlink that escapes the repo" 0 "$rc"
done

# --- 3. Shipped profiles and docs ------------------------------------------

(cd "$REPO_ROOT" && bash "$CHECKER" config/worker-settings.json config/tower-settings.json config/mission-control-settings.json >/dev/null 2>&1)
assert "shipped settings profiles carry no path-wildcard allow rule" 0 $?

grep -q 'Bash(/abs/path/to/planwright/scripts/\*)' "$REPO_ROOT/docs/overlays.md"
assert "overlays.md no longer recommends the scripts/* path glob" 1 $?

if [ "$failures" -ne 0 ]; then
  echo "test-check-allow-path-globs: $failures failure(s)" >&2
  exit 1
fi
echo "test-check-allow-path-globs: all passed"
