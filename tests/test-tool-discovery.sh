#!/bin/bash
# Tests for scripts/tool-discovery.sh — the SessionStart hook that surfaces
# project-shipped quality tooling as additionalContext (Task 6, REQ-K1.3).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
HOOK="$here/../scripts/tool-discovery.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$HOOK" ] || fail "scripts/tool-discovery.sh missing or not executable"
command -v jq >/dev/null 2>&1 || fail "jq required to run this suite"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

make_repo() { # $1 = dir
  mkdir -p "$1"
  git -C "$1" init -q -b main
}

# 1. A repo with detectable tooling emits the SessionStart context payload
#    naming each detected tool.
repo=$tmp/tooled
make_repo "$repo"
printf '[tasks.test]\nrun = "true"\n' >"$repo/mise.toml"
printf 'extends: default\n' >"$repo/.yamllint"
mkdir -p "$repo/.github/workflows"
printf 'name: ci\n' >"$repo/.github/workflows/ci.yml"
out=$(cd "$repo" && CLAUDE_PROJECT_DIR=$repo "$HOOK") || fail "tooled repo: non-zero exit"
[ -n "$out" ] || fail "tooled repo: no output"
printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null \
  || fail "tooled repo: not a SessionStart hookSpecificOutput payload"
ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')
case $ctx in *mise*) ;; *) fail "tooled repo: mise not in summary" ;; esac
case $ctx in *yamllint*) ;; *) fail "tooled repo: yamllint not in summary" ;; esac
case $ctx in *.github/workflows*) ;; *) fail "tooled repo: workflows not in summary" ;; esac
echo "ok: tooled repo emits discovered-tools summary"

# 2. CLAUDE_PROJECT_DIR wins over the cwd (the hook scans the project dir).
out=$(cd "$tmp" && CLAUDE_PROJECT_DIR=$repo "$HOOK") || fail "project-dir env: non-zero exit"
printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -q mise \
  || fail "project-dir env: did not scan CLAUDE_PROJECT_DIR"
echo "ok: CLAUDE_PROJECT_DIR is honored"

# 3. Outside a git work tree: silent no-op (no output, exit 0).
plain=$tmp/plain
mkdir -p "$plain"
printf '[tasks.test]\nrun = "true"\n' >"$plain/mise.toml"
out=$(cd "$plain" && CLAUDE_PROJECT_DIR=$plain "$HOOK") || fail "non-git: non-zero exit"
[ -z "$out" ] || fail "non-git: expected silence, got output"
echo "ok: non-git dir is silent"

# 4. A git repo with no detectable tooling: silent no-op.
bare=$tmp/untooled
make_repo "$bare"
out=$(cd "$bare" && CLAUDE_PROJECT_DIR=$bare "$HOOK") || fail "untooled: non-zero exit"
[ -z "$out" ] || fail "untooled: expected silence, got output"
echo "ok: untooled repo is silent"

# 5. jq unavailable: silent no-op rather than a malformed payload (the hook
#    needs only git from PATH; a stub dir without jq simulates its absence).
nojq=$tmp/nojq-bin
mkdir -p "$nojq"
ln -s "$(command -v git)" "$nojq/git"
out=$(cd "$repo" && CLAUDE_PROJECT_DIR=$repo PATH=$nojq "$HOOK") \
  || fail "no jq: non-zero exit"
[ -z "$out" ] || fail "no jq: expected silence, got output"
echo "ok: missing jq is silent"

echo "PASS: all tool-discovery tests passed"
