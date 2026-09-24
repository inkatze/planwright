#!/bin/bash
# Tests for scripts/resolve-root.sh: the install kind (the core root chain,
# content-checked arms), the repo kind (--primary / --checkout, the
# PLANWRIGHT_REPO_ROOT override, non-repo and bare cases), --explain, and the
# tracked mise.toml PLANWRIGHT_ROOT pin. Plain bash 3.2, inline asserts.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
RESOLVER="$REPO_ROOT/scripts/resolve-root.sh"

failures=0
assert_eq() {
  # assert_eq <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}

assert_contains() {
  # assert_contains <description> <needle> <haystack>
  case $3 in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to contain '$2', got '$3')" >&2
      failures=$((failures + 1))
      ;;
  esac
}

assert_empty() {
  # assert_empty <description> <actual>
  if [ -z "$2" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected nothing, got '$2')" >&2
    failures=$((failures + 1))
  fi
}

if [ ! -f "$RESOLVER" ]; then
  echo "FAIL: resolver script missing at $RESOLVER" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# Every root-affecting variable stripped, HOME pointed at an empty directory
# so the writer-mode arm cannot hit the real ~/.claude/planwright, and git
# discovery fenced at $tmp so a fixture never sees an enclosing repository.
mkdir -p "$tmp/home"
base() {
  env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    -u PLANWRIGHT_REPO_ROOT HOME="$tmp/home" GIT_CEILING_DIRECTORIES="$tmp" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 "$@"
}

run() {
  # run <command...>: capture stdout, stderr, and the exit into out, err, rc.
  "$@" >"$tmp/.out" 2>"$tmp/.err"
  rc=$?
  out=$(cat "$tmp/.out")
  err=$(cat "$tmp/.err")
}

mktree() {
  # mktree <dir>: a content-bearing planwright tree.
  mkdir -p "$1/doctrine" "$1/scripts"
}

# ---------------------------------------------------------------------------
# install kind: the chain, in order
# ---------------------------------------------------------------------------
mktree "$tmp/pw"
mktree "$tmp/plugin"
mktree "$tmp/claudedir/planwright"
mktree "$tmp/home2/.claude/planwright"

run base PLANWRIGHT_ROOT="$tmp/pw" CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  /bin/bash "$RESOLVER" install
assert_eq "install: PLANWRIGHT_ROOT wins over CLAUDE_PLUGIN_ROOT (exit)" 0 "$rc"
assert_eq "install: PLANWRIGHT_ROOT wins over CLAUDE_PLUGIN_ROOT" "$tmp/pw" "$out"
assert_empty "install: a clean resolution warns nothing" "$err"

run base CLAUDE_PLUGIN_ROOT="$tmp/plugin" CLAUDE_DIR="$tmp/claudedir" \
  /bin/bash "$RESOLVER" install
assert_eq "install: CLAUDE_PLUGIN_ROOT is the second arm" "$tmp/plugin" "$out"

run base CLAUDE_DIR="$tmp/claudedir" /bin/bash "$RESOLVER" install
assert_eq "install: writer-mode arm via CLAUDE_DIR" "$tmp/claudedir/planwright" "$out"

run base HOME="$tmp/home2" /bin/bash "$RESOLVER" install
assert_eq "install: writer-mode arm via HOME when CLAUDE_DIR is unset" \
  "$tmp/home2/.claude/planwright" "$out"

run base /bin/bash "$RESOLVER" install
assert_eq "install: self-location when every env arm misses (exit)" 0 "$rc"
assert_eq "install: self-location prints the tree beside the script" "$REPO_ROOT" "$out"
assert_empty "install: an absent writer-mode directory is skipped silently" "$err"

run base HOME= /bin/bash "$RESOLVER" install
assert_eq "install: a HOME-less environment still resolves by self-location" \
  "$REPO_ROOT" "$out"

# A non-canonical arm value is printed canonicalized.
ln -s "$tmp/pw" "$tmp/pw-link"
run base PLANWRIGHT_ROOT="$tmp/pw-link/" /bin/bash "$RESOLVER" install
assert_eq "install: the printed root is canonicalized" "$tmp/pw" "$out"

# An empty variable is unset, not an arm.
run base PLANWRIGHT_ROOT= CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  /bin/bash "$RESOLVER" install
assert_eq "install: an empty PLANWRIGHT_ROOT falls through" "$tmp/plugin" "$out"
assert_empty "install: an empty variable warns nothing" "$err"

# ---------------------------------------------------------------------------
# install kind: content-checked arms
# ---------------------------------------------------------------------------
mkdir -p "$tmp/empty"
run base PLANWRIGHT_ROOT="$tmp/empty" CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  /bin/bash "$RESOLVER" install
assert_eq "install: a content-less arm is skipped for the next arm" "$tmp/plugin" "$out"
assert_contains "install: the skipped content-less arm warns" "WARNING" "$err"
assert_contains "install: the warning names the skipped directory" "$tmp/empty" "$err"
assert_contains "install: the warning names the arm" "PLANWRIGHT_ROOT" "$err"

run base CLAUDE_PLUGIN_ROOT="$tmp/empty" /bin/bash "$RESOLVER" install
assert_eq "install: a content-less CLAUDE_PLUGIN_ROOT is never printed" "$REPO_ROOT" "$out"
assert_contains "install: a content-less CLAUDE_PLUGIN_ROOT warns" "CLAUDE_PLUGIN_ROOT" "$err"

mkdir -p "$tmp/claudedir-empty/planwright"
run base CLAUDE_DIR="$tmp/claudedir-empty" /bin/bash "$RESOLVER" install
assert_eq "install: a content-less writer-mode directory is skipped" "$REPO_ROOT" "$out"
assert_contains "install: a content-less writer-mode directory warns" "writer-mode" "$err"

run base PLANWRIGHT_ROOT="$tmp/no-such-root" CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  /bin/bash "$RESOLVER" install
assert_eq "install: a nonexistent explicit arm is skipped" "$tmp/plugin" "$out"
assert_contains "install: a nonexistent explicit arm warns" "$tmp/no-such-root" "$err"

touch "$tmp/a-file"
run base PLANWRIGHT_ROOT="$tmp/a-file" CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  /bin/bash "$RESOLVER" install
assert_eq "install: an arm naming a file is skipped" "$tmp/plugin" "$out"

mkdir -p "$tmp/doctrine-only/doctrine" "$tmp/scripts-only/scripts"
run base PLANWRIGHT_ROOT="$tmp/doctrine-only" /bin/bash "$RESOLVER" install
assert_eq "install: doctrine/ alone is content enough" "$tmp/doctrine-only" "$out"
run base PLANWRIGHT_ROOT="$tmp/scripts-only" /bin/bash "$RESOLVER" install
assert_eq "install: scripts/ alone is content enough" "$tmp/scripts-only" "$out"

# ---------------------------------------------------------------------------
# install kind: --explain
# ---------------------------------------------------------------------------
tab=$(printf '\t')
run base PLANWRIGHT_ROOT="$tmp/pw" /bin/bash "$RESOLVER" install --explain
assert_eq "install --explain: names the PLANWRIGHT_ROOT arm" "PLANWRIGHT_ROOT${tab}$tmp/pw" "$out"
run base CLAUDE_PLUGIN_ROOT="$tmp/plugin" /bin/bash "$RESOLVER" --explain install
assert_eq "install --explain: accepted before the kind" "CLAUDE_PLUGIN_ROOT${tab}$tmp/plugin" "$out"
run base CLAUDE_DIR="$tmp/claudedir" /bin/bash "$RESOLVER" install --explain
assert_eq "install --explain: names the writer-mode arm" \
  "writer-mode${tab}$tmp/claudedir/planwright" "$out"
run base /bin/bash "$RESOLVER" install --explain
assert_eq "install --explain: names self-location" "self-location${tab}$REPO_ROOT" "$out"

# ---------------------------------------------------------------------------
# repo kind: fixtures
# ---------------------------------------------------------------------------
gitq() { base git "$@" >/dev/null 2>&1; }

mkdir -p "$tmp/repo/sub/dir"
gitq -C "$tmp/repo" init -q
gitq -C "$tmp/repo" -c user.name=t -c user.email=t@example.invalid \
  commit -q --allow-empty -m init
gitq -C "$tmp/repo" worktree add -q -b wt "$tmp/repo-wt"
mkdir -p "$tmp/repo-wt/deep"

mkdir -p "$tmp/other"
gitq -C "$tmp/other" init -q

mkdir -p "$tmp/plain/inner"

gitq init -q --bare "$tmp/bare.git"
gitq -C "$tmp/repo" push -q "$tmp/bare.git" HEAD:refs/heads/main
gitq -C "$tmp/bare.git" worktree add -q "$tmp/bare-wt" main

in_dir() {
  # in_dir <dir> <command...>
  (cd "$1" && shift && "$@")
}

# ---------------------------------------------------------------------------
# repo kind: --primary and --checkout
# ---------------------------------------------------------------------------
run in_dir "$tmp/repo" base /bin/bash "$RESOLVER" repo --primary
assert_eq "repo --primary: from the primary checkout (exit)" 0 "$rc"
assert_eq "repo --primary: from the primary checkout" "$tmp/repo" "$out"

run in_dir "$tmp/repo/sub/dir" base /bin/bash "$RESOLVER" repo --primary
assert_eq "repo --primary: from a subdirectory" "$tmp/repo" "$out"

run in_dir "$tmp/repo-wt" base /bin/bash "$RESOLVER" repo --primary
assert_eq "repo --primary: from a linked worktree prints the primary" "$tmp/repo" "$out"

run in_dir "$tmp/repo-wt/deep" base /bin/bash "$RESOLVER" repo --primary
assert_eq "repo --primary: from inside a linked worktree" "$tmp/repo" "$out"

run in_dir "$tmp/repo-wt/deep" base /bin/bash "$RESOLVER" repo --checkout
assert_eq "repo --checkout: from a worktree prints the worktree" "$tmp/repo-wt" "$out"

run in_dir "$tmp/repo/sub" base /bin/bash "$RESOLVER" repo --checkout
assert_eq "repo --checkout: from the primary prints the primary" "$tmp/repo" "$out"

run in_dir "$tmp/bare-wt" base /bin/bash "$RESOLVER" repo --checkout
assert_eq "repo --checkout: a worktree of a bare repository has a toplevel" \
  "$tmp/bare-wt" "$out"

# ---------------------------------------------------------------------------
# repo kind: the PLANWRIGHT_REPO_ROOT override
# ---------------------------------------------------------------------------
run in_dir "$tmp/repo-wt" base PLANWRIGHT_REPO_ROOT="$tmp/other" \
  /bin/bash "$RESOLVER" repo --primary
assert_eq "repo --primary: an override naming a git toplevel wins (exit)" 0 "$rc"
assert_eq "repo --primary: an override naming a git toplevel wins" "$tmp/other" "$out"

run in_dir "$tmp/repo-wt" base PLANWRIGHT_REPO_ROOT="$tmp/other" \
  /bin/bash "$RESOLVER" repo --checkout
assert_eq "repo --checkout: the override never affects it" "$tmp/repo-wt" "$out"

run in_dir "$tmp/plain" base PLANWRIGHT_REPO_ROOT="$tmp/other" \
  /bin/bash "$RESOLVER" repo --primary
assert_eq "repo --primary: the override applies outside any repository" "$tmp/other" "$out"

run in_dir "$tmp/repo" base PLANWRIGHT_REPO_ROOT="$tmp/plain" \
  /bin/bash "$RESOLVER" repo --primary
assert_eq "repo --primary: an override naming a non-repository is refused (exit)" 4 "$rc"
assert_empty "repo --primary: a refused override prints no path" "$out"
assert_contains "repo --primary: the refusal names the variable" "PLANWRIGHT_REPO_ROOT" "$err"
assert_contains "repo --primary: the refusal names the value" "$tmp/plain" "$err"

run in_dir "$tmp/repo" base PLANWRIGHT_REPO_ROOT="$tmp/repo/sub" \
  /bin/bash "$RESOLVER" repo --primary
assert_eq "repo --primary: an override naming a subdirectory, not a toplevel, is refused" \
  4 "$rc"

run in_dir "$tmp/repo" base PLANWRIGHT_REPO_ROOT="$tmp/no-such-dir" \
  /bin/bash "$RESOLVER" repo --primary
assert_eq "repo --primary: an override naming a missing directory is refused" 4 "$rc"

run in_dir "$tmp/repo" base PLANWRIGHT_REPO_ROOT="$tmp/bare.git" \
  /bin/bash "$RESOLVER" repo --primary
assert_eq "repo --primary: an override naming a bare repository is refused" 4 "$rc"

run in_dir "$tmp/repo-wt" base PLANWRIGHT_REPO_ROOT= \
  /bin/bash "$RESOLVER" repo --primary
assert_eq "repo --primary: an empty override is unset" "$tmp/repo" "$out"

ln -s "$tmp/other" "$tmp/other-link"
run in_dir "$tmp/repo" base PLANWRIGHT_REPO_ROOT="$tmp/other-link" \
  /bin/bash "$RESOLVER" repo --primary
assert_eq "repo --primary: an override through a symlink prints the canonical toplevel" \
  "$tmp/other" "$out"

# ---------------------------------------------------------------------------
# repo kind: outside a repository, and bare repositories
# ---------------------------------------------------------------------------
for view in --primary --checkout; do
  run in_dir "$tmp/plain/inner" base /bin/bash "$RESOLVER" repo $view
  assert_eq "repo $view: a plain directory exits 3" 3 "$rc"
  assert_empty "repo $view: a plain directory prints no path" "$out"
  assert_contains "repo $view: the message names the non-repository case" \
    "not inside a git repository" "$err"

  run in_dir "$tmp/bare.git" base /bin/bash "$RESOLVER" repo $view
  assert_eq "repo $view: inside a bare repository exits 3" 3 "$rc"
  assert_empty "repo $view: a bare repository prints no path" "$out"
  assert_contains "repo $view: the message names the bare case" "bare repository" "$err"
done

run in_dir "$tmp/bare-wt" base /bin/bash "$RESOLVER" repo --primary
assert_eq "repo --primary: a worktree of a bare repository has no primary (exit)" 3 "$rc"
assert_contains "repo --primary: the bare-worktree message names the case" \
  "no primary working tree" "$err"

# ---------------------------------------------------------------------------
# repo kind: --explain
# ---------------------------------------------------------------------------
run in_dir "$tmp/repo-wt" base /bin/bash "$RESOLVER" repo --primary --explain
assert_eq "repo --primary --explain: names the common git directory" \
  "git-common-dir${tab}$tmp/repo" "$out"
run in_dir "$tmp/repo-wt" base PLANWRIGHT_REPO_ROOT="$tmp/other" \
  /bin/bash "$RESOLVER" --explain repo --primary
assert_eq "repo --primary --explain: names the override" \
  "PLANWRIGHT_REPO_ROOT${tab}$tmp/other" "$out"
run in_dir "$tmp/repo-wt" base /bin/bash "$RESOLVER" repo --explain --checkout
assert_eq "repo --checkout --explain: names the toplevel" \
  "show-toplevel${tab}$tmp/repo-wt" "$out"

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
run base /bin/bash "$RESOLVER"
assert_eq "usage: no kind exits 2" 2 "$rc"
run base /bin/bash "$RESOLVER" nope
assert_eq "usage: an unknown kind exits 2" 2 "$rc"
run in_dir "$tmp/repo" base /bin/bash "$RESOLVER" repo
assert_eq "usage: repo without a view exits 2" 2 "$rc"
run in_dir "$tmp/repo" base /bin/bash "$RESOLVER" repo --primary --checkout
assert_eq "usage: repo with both views exits 2" 2 "$rc"
run base /bin/bash "$RESOLVER" install --primary
assert_eq "usage: install takes no view" 2 "$rc"
run base /bin/bash "$RESOLVER" install --bogus
assert_eq "usage: an unknown flag exits 2" 2 "$rc"
assert_contains "usage: the message shows the usage line" "usage:" "$err"

# ---------------------------------------------------------------------------
# The tracked mise.toml pin: a worktree of a planwright checkout resolves
# itself even with a content-bearing decoy CLAUDE_PLUGIN_ROOT set.
# ---------------------------------------------------------------------------
pin_line=$(awk '
  /^\[/ { in_env = ($0 == "[env]") ; next }
  in_env && /^PLANWRIGHT_ROOT[ \t]*=/ { print; exit }
' "$REPO_ROOT/mise.toml")
case $pin_line in
  PLANWRIGHT_ROOT*config_root*) echo "ok: mise.toml [env] pins PLANWRIGHT_ROOT as a config-root expansion" ;;
  *)
    echo "FAIL: mise.toml [env] pins PLANWRIGHT_ROOT as a config-root expansion (got '$pin_line')" >&2
    failures=$((failures + 1))
    ;;
esac

mktree "$tmp/decoy"
mktree "$tmp/override"
mktree "$tmp/pwrepo"
printf '[env]\n%s\n' "$pin_line" >"$tmp/pwrepo/mise.toml"
gitq -C "$tmp/pwrepo" init -q
gitq -C "$tmp/pwrepo" add mise.toml
gitq -C "$tmp/pwrepo" -c user.name=t -c user.email=t@example.invalid commit -q -m init
gitq -C "$tmp/pwrepo" worktree add -q -b wt "$tmp/pwrepo-wt"
mktree "$tmp/pwrepo-wt"

# The pin cleared: nothing pins the root, so the decoy wins.
run in_dir "$tmp/pwrepo-wt" base CLAUDE_PLUGIN_ROOT="$tmp/decoy" \
  /bin/bash "$RESOLVER" install
assert_eq "pin cleared: the decoy CLAUDE_PLUGIN_ROOT is what resolves" "$tmp/decoy" "$out"

if command -v mise >/dev/null 2>&1; then
  # Trust the fixture for this call only (nothing lands in the operator's
  # trust store) and blank the global config, whose tools would otherwise be
  # set up under the fixture HOME on every call.
  : >"$tmp/mise-global.toml"
  mise_in() {
    # mise_in <dir> [VAR=value...]: run the resolver under mise from <dir>.
    mi_dir=$1
    shift
    base MISE_TRUSTED_CONFIG_PATHS="$tmp" MISE_GLOBAL_CONFIG_FILE="$tmp/mise-global.toml" \
      MISE_SYSTEM_CONFIG_FILE="$tmp/mise-global.toml" "$@" \
      mise exec -C "$mi_dir" -- /bin/bash "$RESOLVER" install
  }
  run mise_in "$tmp/pwrepo-wt" CLAUDE_PLUGIN_ROOT="$tmp/decoy"
  assert_eq "pin set: a worktree resolves itself over the decoy (exit)" 0 "$rc"
  assert_eq "pin set: a worktree resolves itself over the decoy" "$tmp/pwrepo-wt" "$out"

  run mise_in "$tmp/pwrepo" CLAUDE_PLUGIN_ROOT="$tmp/decoy"
  assert_eq "pin set: the primary checkout resolves itself" "$tmp/pwrepo" "$out"

  run mise_in "$tmp/pwrepo-wt" CLAUDE_PLUGIN_ROOT="$tmp/decoy" \
    PLANWRIGHT_ROOT="$tmp/override"
  assert_eq "pin set: an operator PLANWRIGHT_ROOT in the environment still wins" \
    "$tmp/override" "$out"
elif [ -n "${CI:-}" ]; then
  echo "FAIL: mise is not on PATH in CI; the pin cannot be exercised" >&2
  failures=$((failures + 1))
else
  echo "SKIP: mise not on PATH; the pin's mise-evaluated cases did not run" >&2
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all resolve-root tests passed"
