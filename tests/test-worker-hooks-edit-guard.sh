#!/bin/bash
# Tests for the worker-tier hooks-directory file-tool guard
# (worker-permission-ergonomics Task 16; REQ-F1.7, REQ-A1.15, REQ-B1.3).
#
# The worker profile used to deny `githooks/` and `.githooks/` at any depth, a
# rule that also refused `test/githooks/x` and left a `core.hooksPath` directory
# with another name open. The guard under test (scripts/worker-hooks-edit-guard.sh)
# refuses the directories git really runs hooks from, wherever they are named,
# and the profile's own rows are anchored at the worktree root.
#
# Every protected path is first shown against the PRE-CHANGE profile rules (the
# any-depth pair, pinned below), then against the shipped profile plus the
# guard. The fixtures are real git repositories under a mktemp folder; no live
# fleet state or config file is read.
#
# Runs standalone: ./tests/test-worker-hooks-edit-guard.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="${WORKER_HOOKS_GUARD:-$REPO_ROOT/scripts/worker-hooks-edit-guard.sh}"
SETTINGS="$REPO_ROOT/config/worker-settings.json"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to run this suite" >&2
  exit 1
}
command -v git >/dev/null 2>&1 || {
  echo "FAIL: git is required to run this suite" >&2
  exit 1
}

T=$(mktemp -d "${TMPDIR:-/tmp}/hooks-edit-guard.XXXXXX") || exit 1
echo "scratch: $T"
cleanup() { rm -rf "$T"; }
trap cleanup EXIT

# Isolate from this machine's git configuration.
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_SYSTEM=/dev/null
: >"$T/gitconfig"
G() { git -c user.email=t@t -c user.name=t "$@"; }

# mkrepo <name> [<core.hooksPath>]: a repo with one commit and a linked worktree
# at $T/<name>-wt, standing in for the worker's worktree.
mkrepo() {
  G init -q -b main "$T/$1" || exit 1
  G -C "$T/$1" commit -q --allow-empty -m init || exit 1
  [ -z "${2:-}" ] || G -C "$T/$1" config core.hooksPath "$2"
  G -C "$T/$1" worktree add -q -b "wt-$1" "$T/$1-wt" || exit 1
  mkdir -p "$T/$1-wt/githooks" "$T/$1-wt/.githooks" "$T/$1-wt/test/githooks" "$T/$1-wt/src/githooks"
}
mkrepo plain
mkrepo rel hookdir
mkdir -p "$T/rel-wt/hookdir"
mkrepo abs "$T/abs-hooks"
mkdir -p "$T/abs-hooks"

payload() { # payload <tool> <path> <cwd>
  case $1 in
    NotebookEdit) jq -nc --arg t "$1" --arg p "$2" --arg c "$3" '{tool_name:$t, tool_input:{notebook_path:$p}, cwd:$c}' ;;
    *) jq -nc --arg t "$1" --arg p "$2" --arg c "$3" '{tool_name:$t, tool_input:{file_path:$p}, cwd:$c}' ;;
  esac
}

# decision <stdin payload> -> denied | deferred (the guard's stdout)
decision() {
  local out
  out=$("$GUARD" 2>&1) || :
  case $out in
    *'"permissionDecision":"deny"'*) echo denied ;;
    '') echo deferred ;;
    *) echo "other:$out" ;;
  esac
}

expect() { # expect <denied|deferred> <label> <payload>
  local got
  got=$(printf '%s' "$3" | decision)
  if [ "$got" = "$1" ]; then ok "$2 is $1"; else fail "$2: expected $1, got $got"; fi
}

[ -x "$GUARD" ] || fail "scripts/worker-hooks-edit-guard.sh is missing or not executable"

# --- the PRE-CHANGE profile, through the matcher model -----------------------
# shellcheck source=tests/lib/permission-matcher.sh
. "$REPO_ROOT/tests/lib/permission-matcher.sh"
PM_CWD="$T/plain-wt"
PM_HOME=/home/u
PM_SETTINGS_DIR=/opt/planwright/config
pre_rules='Bash(git push --force:*)
Edit(//**/githooks/**)
Edit(//**/.githooks/**)'
pm_load_rules "$pre_rules" '' 'Edit
Write' || fail "the pre-change rows did not load into the matcher model"
for p in .githooks/x githooks/x test/githooks/x src/githooks/x; do
  for tool in Edit Write; do
    case $(pm_decide_path "$tool" "$T/plain-wt/$p") in
      deny) ok "pre-change profile: $tool $p is denied" ;;
      *) fail "pre-change profile: $tool $p should be denied" ;;
    esac
  done
done
case $(pm_decide_path Write "$T/rel-wt/hookdir/x") in
  deny) fail "pre-change profile: a core.hooksPath directory named hookdir was denied (it was the open gap)" ;;
  *) ok "pre-change profile: the core.hooksPath directory hookdir/x is NOT denied (the gap the guard closes)" ;;
esac

# --- the shipped profile rows plus the guard ---------------------------------
shipped_deny=$(jq -r '.permissions.deny[]' "$SETTINGS")
shipped_allow=$(jq -r '.permissions.allow[]' "$SETTINGS")
pm_load_rules "$shipped_deny" '' "$shipped_allow" || fail "the shipped profile did not load into the matcher model"
for p in .githooks/x githooks/x; do
  for tool in Edit Write; do
    case $(PM_CWD="$T/plain-wt" pm_decide_path "$tool" "$T/plain-wt/$p") in
      deny) ok "shipped profile: $tool $p is denied by a row" ;;
      *) fail "shipped profile: $tool $p is not denied by a row" ;;
    esac
  done
done
for p in test/githooks/x src/githooks/x; do
  for tool in Edit Write; do
    case $(PM_CWD="$T/plain-wt" pm_decide_path "$tool" "$T/plain-wt/$p") in
      deny) fail "shipped profile: $tool $p is still denied by a row" ;;
      *) ok "shipped profile: $tool $p is not denied by a row" ;;
    esac
  done
done

# --- the guard: protected directories are refused ----------------------------
for tool in Edit Write MultiEdit; do
  expect denied "$tool .githooks/x" "$(payload "$tool" "$T/plain-wt/.githooks/x" "$T/plain-wt")"
  expect denied "$tool githooks/x" "$(payload "$tool" "$T/plain-wt/githooks/x" "$T/plain-wt")"
  expect denied "$tool core.hooksPath (relative) hookdir/x" "$(payload "$tool" "$T/rel-wt/hookdir/x" "$T/rel-wt")"
  expect denied "$tool core.hooksPath (absolute) abs-hooks/x" "$(payload "$tool" "$T/abs-hooks/x" "$T/abs-wt")"
done
expect denied "NotebookEdit .githooks/x.ipynb" "$(payload NotebookEdit "$T/plain-wt/.githooks/x.ipynb" "$T/plain-wt")"
expect denied "Write to the default hooks dir of the common git directory" "$(payload Write "$T/plain/.git/hooks/pre-commit" "$T/plain-wt")"
expect denied "Write githooks/x on a relative path from a subdirectory cwd" "$(payload Write ../githooks/x "$T/plain-wt/src")"
expect denied "Write through a dot-dot spelling" "$(payload Write "$T/plain-wt/src/../githooks/x" "$T/plain-wt")"
ln -s "$T/plain-wt/githooks" "$T/plain-wt/hooklink"
expect denied "Write through a symlink to githooks" "$(payload Write "$T/plain-wt/hooklink/x" "$T/plain-wt")"
mkdir -p "$T/plain-wt/githooks/sub"
ln -s "$T/plain-wt/githooks/sub" "$T/plain-wt/src/lnk2"
expect denied "Write through symlink-then-dot-dot (the kernel resolves .. after the link)" "$(payload Write "$T/plain-wt/src/lnk2/../pre-commit" "$T/plain-wt")"
expect denied "Write through a relative symlink-then-dot-dot spelling" "$(payload Write src/lnk2/../pre-commit "$T/plain-wt")"
expect deferred "a harmless dot-dot spelling to a new file" "$(payload Write "$T/plain-wt/src/../README.md" "$T/plain-wt")"
expect denied "the primary checkout's githooks/x""$(payload Write "$T/plain/githooks/x" "$T/plain-wt")"
expect denied "Edit of the primary checkout's githooks/pre-commit" "$(payload Edit "$T/plain/githooks/pre-commit" "$T/plain-wt")"

# --- the guard: other paths pass ---------------------------------------------
for tool in Edit Write; do
  expect deferred "$tool test/githooks/x" "$(payload "$tool" "$T/plain-wt/test/githooks/x" "$T/plain-wt")"
  expect deferred "$tool src/githooks/x" "$(payload "$tool" "$T/plain-wt/src/githooks/x" "$T/plain-wt")"
  expect deferred "$tool README.md" "$(payload "$tool" "$T/plain-wt/README.md" "$T/plain-wt")"
done
expect deferred "Write docs/githooks.md" "$(payload Write "$T/plain-wt/docs/githooks.md" "$T/plain-wt")"
expect deferred "Write a core.hooksPath-named dir in a repo that does not set it" "$(payload Write "$T/plain-wt/hookdir/x" "$T/plain-wt")"
expect deferred "a tool the guard does not govern" "$(payload Bash "$T/plain-wt/githooks/x" "$T/plain-wt")"

# --- fail closed (REQ-B1.3) --------------------------------------------------
good=$(payload Write "$T/plain-wt/githooks/x" "$T/plain-wt")
expect denied "an unparsable payload" "not json at all"
expect denied "an empty payload" ""
expect denied "a payload that names no file path" '{"tool_name":"Write","tool_input":{},"cwd":"/x"}'

# A hook that crashes: stub tools that fail, found first on PATH.
stub="$T/stub"
for tool in git jq tr readlink cat; do
  mkdir -p "$stub/$tool-dead"
  printf '#!/bin/sh\nexit 3\n' >"$stub/$tool-dead/$tool"
  chmod +x "$stub/$tool-dead/$tool"
  got=$(printf '%s' "$good" | PATH="$stub/$tool-dead:$PATH" "$GUARD" 2>&1) || :
  case $got in
    *'"permissionDecision":"deny"'*) ok "a crashing $tool still refuses the protected directory" ;;
    *) fail "a crashing $tool let githooks/x through: $got" ;;
  esac
done
# A working directory that is no repository: the hooks directory cannot be named.
mkdir -p "$T/norepo"
expect denied "a cwd outside any repository" "$(payload Write "$T/norepo/githooks/x" "$T/norepo")"
# The guard exits 0 on every path above, whatever it decided.
printf '%s' "$good" | "$GUARD" >/dev/null 2>&1
rc=$?
if [ "$rc" = 0 ]; then ok "the guard exits 0 with a decision"; else fail "the guard exited $rc"; fi

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "all checks passed"
