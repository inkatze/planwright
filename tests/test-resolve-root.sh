#!/bin/bash
# Tests for scripts/resolve-root.sh: the install kind (the core root chain,
# content-checked arms), the repo kind (--primary / --checkout, the
# PLANWRIGHT_REPO_ROOT override, non-repo and bare cases), --explain, and the
# tracked mise.toml PLANWRIGHT_ROOT pin. Plain bash 3.2, inline asserts.
set -u
unset CDPATH
# An inherited repository (a git hook exports these) would redirect the
# fixtures' git commands at the enclosing checkout.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
RESOLVER="$REPO_ROOT/scripts/resolve-root.sh"
# The resolver is POSIX sh and its callers exec it through /bin/sh, which is
# dash on the Linux CI runners; run it there so a bash-ism fails here first.
SH=$(command -v dash || echo /bin/sh)
skips=0

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
  "$SH" "$RESOLVER" install
assert_eq "install: PLANWRIGHT_ROOT wins over CLAUDE_PLUGIN_ROOT (exit)" 0 "$rc"
assert_eq "install: PLANWRIGHT_ROOT wins over CLAUDE_PLUGIN_ROOT" "$tmp/pw" "$out"
assert_empty "install: a clean resolution warns nothing" "$err"

run base CLAUDE_PLUGIN_ROOT="$tmp/plugin" CLAUDE_DIR="$tmp/claudedir" \
  "$SH" "$RESOLVER" install
assert_eq "install: CLAUDE_PLUGIN_ROOT is the second arm" "$tmp/plugin" "$out"

run base CLAUDE_DIR="$tmp/claudedir" "$SH" "$RESOLVER" install
assert_eq "install: writer-mode arm via CLAUDE_DIR" "$tmp/claudedir/planwright" "$out"

run base HOME="$tmp/home2" "$SH" "$RESOLVER" install
assert_eq "install: writer-mode arm via HOME when CLAUDE_DIR is unset" \
  "$tmp/home2/.claude/planwright" "$out"

run base "$SH" "$RESOLVER" install
assert_eq "install: self-location when every env arm misses (exit)" 0 "$rc"
assert_eq "install: self-location prints the tree beside the script" "$REPO_ROOT" "$out"
assert_empty "install: an absent writer-mode directory is skipped silently" "$err"

run base HOME= "$SH" "$RESOLVER" install
assert_eq "install: a HOME-less environment still resolves by self-location" \
  "$REPO_ROOT" "$out"

# A non-canonical arm value is printed canonicalized.
ln -s "$tmp/pw" "$tmp/pw-link"
run base PLANWRIGHT_ROOT="$tmp/pw-link/" "$SH" "$RESOLVER" install
assert_eq "install: the printed root is canonicalized" "$tmp/pw" "$out"

# An empty variable is unset, not an arm.
run base PLANWRIGHT_ROOT= CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  "$SH" "$RESOLVER" install
assert_eq "install: an empty PLANWRIGHT_ROOT falls through" "$tmp/plugin" "$out"
assert_empty "install: an empty variable warns nothing" "$err"

# ---------------------------------------------------------------------------
# install kind: content-checked arms
# ---------------------------------------------------------------------------
mkdir -p "$tmp/empty"
run base PLANWRIGHT_ROOT="$tmp/empty" CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  "$SH" "$RESOLVER" install
assert_eq "install: a content-less arm is skipped for the next arm" "$tmp/plugin" "$out"
assert_contains "install: the skipped content-less arm warns" "WARNING" "$err"
assert_contains "install: the warning names the skipped directory" "$tmp/empty" "$err"
assert_contains "install: the warning names the arm" "PLANWRIGHT_ROOT" "$err"

run base CLAUDE_PLUGIN_ROOT="$tmp/empty" "$SH" "$RESOLVER" install
assert_eq "install: a content-less CLAUDE_PLUGIN_ROOT is never printed" "$REPO_ROOT" "$out"
assert_contains "install: a content-less CLAUDE_PLUGIN_ROOT warns" "CLAUDE_PLUGIN_ROOT" "$err"

mkdir -p "$tmp/claudedir-empty/planwright"
run base CLAUDE_DIR="$tmp/claudedir-empty" "$SH" "$RESOLVER" install
assert_eq "install: a content-less writer-mode directory is skipped" "$REPO_ROOT" "$out"
assert_contains "install: a content-less writer-mode directory warns" "writer-mode" "$err"

run base PLANWRIGHT_ROOT="$tmp/no-such-root" CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  "$SH" "$RESOLVER" install
assert_eq "install: a nonexistent explicit arm is skipped" "$tmp/plugin" "$out"
assert_contains "install: a nonexistent explicit arm warns" "$tmp/no-such-root" "$err"

touch "$tmp/a-file"
run base PLANWRIGHT_ROOT="$tmp/a-file" CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  "$SH" "$RESOLVER" install
assert_eq "install: an arm naming a file is skipped" "$tmp/plugin" "$out"

mkdir -p "$tmp/doctrine-only/doctrine" "$tmp/scripts-only/scripts"
run base PLANWRIGHT_ROOT="$tmp/doctrine-only" "$SH" "$RESOLVER" install
assert_eq "install: doctrine/ alone is content enough" "$tmp/doctrine-only" "$out"
run base PLANWRIGHT_ROOT="$tmp/scripts-only" "$SH" "$RESOLVER" install
assert_eq "install: scripts/ alone is content enough" "$tmp/scripts-only" "$out"

# ---------------------------------------------------------------------------
# install kind: --explain
# ---------------------------------------------------------------------------
tab=$(printf '\t')
run base PLANWRIGHT_ROOT="$tmp/pw" "$SH" "$RESOLVER" install --explain
assert_eq "install --explain: names the PLANWRIGHT_ROOT arm" "PLANWRIGHT_ROOT${tab}$tmp/pw" "$out"
run base CLAUDE_PLUGIN_ROOT="$tmp/plugin" "$SH" "$RESOLVER" --explain install
assert_eq "install --explain: accepted before the kind" "CLAUDE_PLUGIN_ROOT${tab}$tmp/plugin" "$out"
run base CLAUDE_DIR="$tmp/claudedir" "$SH" "$RESOLVER" install --explain
assert_eq "install --explain: names the writer-mode arm" \
  "writer-mode${tab}$tmp/claudedir/planwright" "$out"
run base "$SH" "$RESOLVER" install --explain
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
run in_dir "$tmp/repo" base "$SH" "$RESOLVER" repo --primary
assert_eq "repo --primary: from the primary checkout (exit)" 0 "$rc"
assert_eq "repo --primary: from the primary checkout" "$tmp/repo" "$out"

run in_dir "$tmp/repo/sub/dir" base "$SH" "$RESOLVER" repo --primary
assert_eq "repo --primary: from a subdirectory" "$tmp/repo" "$out"

run in_dir "$tmp/repo-wt" base "$SH" "$RESOLVER" repo --primary
assert_eq "repo --primary: from a linked worktree prints the primary" "$tmp/repo" "$out"

run in_dir "$tmp/repo-wt/deep" base "$SH" "$RESOLVER" repo --primary
assert_eq "repo --primary: from inside a linked worktree" "$tmp/repo" "$out"

run in_dir "$tmp/repo-wt/deep" base "$SH" "$RESOLVER" repo --checkout
assert_eq "repo --checkout: from a worktree prints the worktree" "$tmp/repo-wt" "$out"

run in_dir "$tmp/repo/sub" base "$SH" "$RESOLVER" repo --checkout
assert_eq "repo --checkout: from the primary prints the primary" "$tmp/repo" "$out"

run in_dir "$tmp/bare-wt" base "$SH" "$RESOLVER" repo --checkout
assert_eq "repo --checkout: a worktree of a bare repository has a toplevel" \
  "$tmp/bare-wt" "$out"

# ---------------------------------------------------------------------------
# repo kind: the PLANWRIGHT_REPO_ROOT override
# ---------------------------------------------------------------------------
run in_dir "$tmp/repo-wt" base PLANWRIGHT_REPO_ROOT="$tmp/other" \
  "$SH" "$RESOLVER" repo --primary
assert_eq "repo --primary: an override naming a git toplevel wins (exit)" 0 "$rc"
assert_eq "repo --primary: an override naming a git toplevel wins" "$tmp/other" "$out"

run in_dir "$tmp/repo-wt" base PLANWRIGHT_REPO_ROOT="$tmp/other" \
  "$SH" "$RESOLVER" repo --checkout
assert_eq "repo --checkout: the override never affects it" "$tmp/repo-wt" "$out"

run in_dir "$tmp/plain" base PLANWRIGHT_REPO_ROOT="$tmp/other" \
  "$SH" "$RESOLVER" repo --primary
assert_eq "repo --primary: the override applies outside any repository" "$tmp/other" "$out"

run in_dir "$tmp/repo" base PLANWRIGHT_REPO_ROOT="$tmp/plain" \
  "$SH" "$RESOLVER" repo --primary
assert_eq "repo --primary: an override naming a non-repository is refused (exit)" 4 "$rc"
assert_empty "repo --primary: a refused override prints no path" "$out"
assert_contains "repo --primary: the refusal names the variable" "PLANWRIGHT_REPO_ROOT" "$err"
assert_contains "repo --primary: the refusal names the value" "$tmp/plain" "$err"

run in_dir "$tmp/repo" base PLANWRIGHT_REPO_ROOT="$tmp/repo/sub" \
  "$SH" "$RESOLVER" repo --primary
assert_eq "repo --primary: an override naming a subdirectory, not a toplevel, is refused" \
  4 "$rc"

run in_dir "$tmp/repo" base PLANWRIGHT_REPO_ROOT="$tmp/no-such-dir" \
  "$SH" "$RESOLVER" repo --primary
assert_eq "repo --primary: an override naming a missing directory is refused" 4 "$rc"

run in_dir "$tmp/repo" base PLANWRIGHT_REPO_ROOT="$tmp/bare.git" \
  "$SH" "$RESOLVER" repo --primary
assert_eq "repo --primary: an override naming a bare repository is refused" 4 "$rc"

run in_dir "$tmp/repo-wt" base PLANWRIGHT_REPO_ROOT= \
  "$SH" "$RESOLVER" repo --primary
assert_eq "repo --primary: an empty override is unset" "$tmp/repo" "$out"

ln -s "$tmp/other" "$tmp/other-link"
run in_dir "$tmp/repo" base PLANWRIGHT_REPO_ROOT="$tmp/other-link" \
  "$SH" "$RESOLVER" repo --primary
assert_eq "repo --primary: an override through a symlink prints the canonical toplevel" \
  "$tmp/other" "$out"

# ---------------------------------------------------------------------------
# repo kind: outside a repository, and bare repositories
# ---------------------------------------------------------------------------
for view in --primary --checkout; do
  run in_dir "$tmp/plain/inner" base "$SH" "$RESOLVER" repo $view
  assert_eq "repo $view: a plain directory exits 3" 3 "$rc"
  assert_empty "repo $view: a plain directory prints no path" "$out"
  assert_contains "repo $view: the message names the non-repository case" \
    "not inside a git repository" "$err"

  run in_dir "$tmp/bare.git" base "$SH" "$RESOLVER" repo $view
  assert_eq "repo $view: inside a bare repository exits 3" 3 "$rc"
  assert_empty "repo $view: a bare repository prints no path" "$out"
  assert_contains "repo $view: the message names the bare case" "bare repository" "$err"
done

run in_dir "$tmp/bare-wt" base "$SH" "$RESOLVER" repo --primary
assert_eq "repo --primary: a worktree of a bare repository has no primary (exit)" 3 "$rc"
assert_contains "repo --primary: the bare-worktree message names the case" \
  "no primary working tree" "$err"

# ---------------------------------------------------------------------------
# repo kind: --explain
# ---------------------------------------------------------------------------
run in_dir "$tmp/repo-wt" base "$SH" "$RESOLVER" repo --primary --explain
assert_eq "repo --primary --explain: names the common git directory" \
  "git-common-dir${tab}$tmp/repo" "$out"
run in_dir "$tmp/repo" base "$SH" "$RESOLVER" repo --primary --explain
assert_eq "repo --primary --explain: from the primary, git names the toplevel" \
  "show-toplevel${tab}$tmp/repo" "$out"
run in_dir "$tmp/repo-wt" base PLANWRIGHT_REPO_ROOT="$tmp/other" \
  "$SH" "$RESOLVER" --explain repo --primary
assert_eq "repo --primary --explain: names the override" \
  "PLANWRIGHT_REPO_ROOT${tab}$tmp/other" "$out"
run in_dir "$tmp/repo-wt" base "$SH" "$RESOLVER" repo --explain --checkout
assert_eq "repo --checkout --explain: names the toplevel" \
  "show-toplevel${tab}$tmp/repo-wt" "$out"

# ---------------------------------------------------------------------------
# hardening: odd inputs and failure modes
# ---------------------------------------------------------------------------
esc=$(printf '\033')

# A control byte in a value never reaches the terminal, and an escape
# sequence spelled with backslashes is not expanded by the shell's echo.
run base PLANWRIGHT_ROOT="$tmp/nope${esc}[31mRED" CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  "$SH" "$RESOLVER" install
assert_eq "hardening: a control-byte arm is still skipped" "$tmp/plugin" "$out"
case $err in
  *"$esc"*)
    echo "FAIL: hardening: a raw ESC byte reached stderr" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: hardening: no raw ESC byte reaches stderr" ;;
esac
run base PLANWRIGHT_ROOT="$tmp"'/nope\033[31m' CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  "$SH" "$RESOLVER" install
case $err in
  *"$esc"*)
    echo "FAIL: hardening: a backslash escape was expanded into an ESC byte" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: hardening: a backslash escape is printed literally, not expanded" ;;
esac
run in_dir "$tmp/repo" base PLANWRIGHT_REPO_ROOT="$tmp/x${esc}[2J" "$SH" "$RESOLVER" repo --primary
case $err in
  *"$esc"*)
    echo "FAIL: hardening: the override refusal echoed a raw ESC byte" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: hardening: the override refusal carries no raw ESC byte" ;;
esac

# A flag-like or relative override is refused, never read as a cd option or
# resolved against whatever directory the caller happens to be in.
run in_dir "$tmp/repo" base HOME="$tmp/other" PLANWRIGHT_REPO_ROOT=-P \
  "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: a flag-like override is refused" 4 "$rc"
run in_dir "$tmp" base PLANWRIGHT_REPO_ROOT=other "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: a relative override is refused" 4 "$rc"
assert_contains "hardening: the relative refusal says why" "absolute" "$err"

# An inherited GIT_DIR (as inside a git hook) does not make an arbitrary
# directory pass as the override's toplevel.
run in_dir "$tmp/repo" base GIT_DIR="$tmp/repo/.git" PLANWRIGHT_REPO_ROOT="$tmp/plain" \
  "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: GIT_DIR does not validate a non-repository override" 4 "$rc"
run in_dir "$tmp/repo" base GIT_DIR="$tmp/repo/.git" GIT_WORK_TREE="$tmp/repo" \
  PLANWRIGHT_REPO_ROOT="$tmp/other" "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: GIT_DIR and GIT_WORK_TREE do not refuse a valid override" \
  "$tmp/other" "$out"

# Config from outside the repository (git -c, as a hook inherits it; the
# GIT_CONFIG_COUNT channel; a global file) cannot name the primary: git itself
# reads core.worktree and core.bare from the repository's own config only.
run in_dir "$tmp/repo" base GIT_CONFIG_PARAMETERS="'core.worktree'='$tmp/other'" \
  "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: git -c core.worktree does not move --primary" "$tmp/repo" "$out"
run in_dir "$tmp/repo" base GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree \
  GIT_CONFIG_VALUE_0="$tmp/other" "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: GIT_CONFIG_COUNT core.worktree does not move --primary" \
  "$tmp/repo" "$out"
printf '[core]\n\tworktree = %s\n' "$tmp/other" >"$tmp/global-worktree.cfg"
run in_dir "$tmp/repo" base GIT_CONFIG_GLOBAL="$tmp/global-worktree.cfg" \
  "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: a global core.worktree does not move --primary" "$tmp/repo" "$out"
run in_dir "$tmp/repo" base GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.bare \
  GIT_CONFIG_VALUE_0=true "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: an inherited core.bare does not refuse --primary" "$tmp/repo" "$out"

# Inside a git directory there is no working tree; the message says so.
run in_dir "$tmp/repo/.git" base "$SH" "$RESOLVER" repo --checkout
assert_eq "hardening: inside .git, --checkout exits 3" 3 "$rc"
assert_contains "hardening: inside .git, the message names the git directory" \
  "inside a git directory" "$err"

# A submodule's primary is its own working tree, never its git directory.
gitq -C "$tmp/other" -c user.name=t -c user.email=t@example.invalid \
  commit -q --allow-empty -m init
gitq -C "$tmp/repo" -c protocol.file.allow=always submodule add -q "$tmp/other" mod
run in_dir "$tmp/repo/mod" base "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: a submodule's --primary is its working tree (exit)" 0 "$rc"
assert_eq "hardening: a submodule's --primary is its working tree" "$tmp/repo/mod" "$out"

# core.worktree in an ordinary .git directory names the primary.
mkdir -p "$tmp/cw/meta" "$tmp/cw/work"
gitq -C "$tmp/cw/meta" init -q
gitq -C "$tmp/cw/meta" config core.worktree "$tmp/cw/work"
printf 'gitdir: %s\n' "$tmp/cw/meta/.git" >"$tmp/cw/work/.git"
gitq -C "$tmp/cw/work" -c user.name=t -c user.email=t@example.invalid \
  commit -q --allow-empty -m init
gitq -C "$tmp/cw/work" worktree add -q -b cw "$tmp/cw/linked"
run in_dir "$tmp/cw/linked" base "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: core.worktree in a .git directory names the primary" "$tmp/cw/work" "$out"

# With per-worktree config enabled, git reads core.worktree from the
# primary's config.worktree, so the resolver must too.
mkdir -p "$tmp/cwx/meta" "$tmp/cwx/work"
gitq -C "$tmp/cwx/meta" init -q
gitq -C "$tmp/cwx/meta" config extensions.worktreeConfig true
gitq -C "$tmp/cwx/meta" config --worktree core.worktree "$tmp/cwx/work"
printf 'gitdir: %s\n' "$tmp/cwx/meta/.git" >"$tmp/cwx/work/.git"
gitq -C "$tmp/cwx/work" -c user.name=t -c user.email=t@example.invalid \
  commit -q --allow-empty -m init
gitq -C "$tmp/cwx/work" worktree add -q -b cwx "$tmp/cwx/linked"
run in_dir "$tmp/cwx/linked" base "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: core.worktree in config.worktree names the primary" \
  "$tmp/cwx/work" "$out"

# A primary whose core.worktree is gone is reported, not printed.
mv "$tmp/cw/work" "$tmp/cw/work-moved"
run in_dir "$tmp/cw/linked" base "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: an unreachable primary exits 3" 3 "$rc"
assert_empty "hardening: an unreachable primary prints no path" "$out"
assert_contains "hardening: an unreachable primary is named" "no primary working tree" "$err"
mv "$tmp/cw/work-moved" "$tmp/cw/work"

# A .git that is a symlink to the real git directory keeps its primary.
mkdir -p "$tmp/store" "$tmp/symgit"
gitq init -q --bare "$tmp/store/x.git"
gitq --git-dir="$tmp/store/x.git" config core.bare false
ln -s "$tmp/store/x.git" "$tmp/symgit/.git"
gitq -C "$tmp/symgit" -c user.name=t -c user.email=t@example.invalid \
  commit -q --allow-empty -m init
run in_dir "$tmp/symgit" base "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: a symlinked .git keeps its primary" "$tmp/symgit" "$out"

# A separate git directory records no primary path: from the primary itself
# it answers with the toplevel; from a linked worktree it refuses.
gitq init -q --separate-git-dir="$tmp/sep.git" "$tmp/sep"
gitq -C "$tmp/sep" -c user.name=t -c user.email=t@example.invalid \
  commit -q --allow-empty -m init
gitq -C "$tmp/sep" worktree add -q -b sepwt "$tmp/sep-wt"
run in_dir "$tmp/sep" base "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: a separate git dir answers from its primary" "$tmp/sep" "$out"
run in_dir "$tmp/sep-wt" base "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: a separate git dir's linked worktree exits 3" 3 "$rc"
assert_contains "hardening: the separate-git-dir refusal names the case" \
  "no primary working tree" "$err"

# A separate git dir named .git elsewhere is not mistaken for a sibling tree.
mkdir -p "$tmp/store/proj"
gitq init -q --separate-git-dir="$tmp/store/proj/.git" "$tmp/sepdot"
gitq -C "$tmp/sepdot" -c user.name=t -c user.email=t@example.invalid \
  commit -q --allow-empty -m init
run in_dir "$tmp/sepdot" base "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: a separate .git-named dir answers with its own tree" "$tmp/sepdot" "$out"

# From a subdirectory of a separate git dir's primary.
mkdir -p "$tmp/sep/deeper"
run in_dir "$tmp/sep/deeper" base "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: a separate git dir answers from a subdirectory" "$tmp/sep" "$out"

# From inside the .git directory, --primary still names the tree it serves.
run in_dir "$tmp/repo/.git" base "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: --primary from inside .git (exit)" 0 "$rc"
assert_eq "hardening: --primary from inside .git" "$tmp/repo" "$out"

# A working directory reached through a symlink resolves the real tree.
ln -s "$tmp/repo/sub/dir" "$tmp/dir-link"
run in_dir "$tmp/dir-link" base "$SH" "$RESOLVER" repo --primary
assert_eq "hardening: a symlinked working directory resolves --primary" "$tmp/repo" "$out"
mkdir -p "$tmp/phys/a" "$tmp/phys/doctrine"
ln -s "$tmp/phys/a" "$tmp/logical-a"
run base PLANWRIGHT_ROOT="$tmp/logical-a/.." "$SH" "$RESOLVER" install
assert_eq "hardening: an arm through a symlink prints the directory it checked" "$tmp/phys" "$out"

# git before 2.31 has no --path-format: a shim that echoes the option back,
# as old git does, drives the relative-path fallback.
realgit=$(command -v git)
mkdir -p "$tmp/oldgit"
cat >"$tmp/oldgit/git" <<SHIM
#!/bin/sh
if [ "\$1" = rev-parse ] && [ "\$2" = --path-format=absolute ]; then
  shift 2
  echo --path-format=absolute
  exec "$realgit" rev-parse "\$@"
fi
exec "$realgit" "\$@"
SHIM
chmod +x "$tmp/oldgit/git"
for d in "$tmp/repo/sub/dir" "$tmp/dir-link" "$tmp/repo/.git" "$tmp/repo-wt/deep"; do
  run in_dir "$d" base PATH="$tmp/oldgit:$PATH" "$SH" "$RESOLVER" repo --primary
  assert_eq "hardening: the pre-2.31 fallback resolves --primary from ${d#"$tmp"/}" \
    "$tmp/repo" "$out"
done

# An inherited GIT_DIR does not move --checkout off the working directory's
# own toplevel.
run in_dir "$tmp/repo/sub/dir" base GIT_DIR="$tmp/repo/.git" "$SH" "$RESOLVER" repo --checkout
assert_eq "hardening: GIT_DIR does not move --checkout" "$tmp/repo" "$out"

# Diagnostics keep non-ASCII path bytes intact.
run base PLANWRIGHT_ROOT="$tmp/nope-日ł" CLAUDE_PLUGIN_ROOT="$tmp/plugin" \
  "$SH" "$RESOLVER" install
assert_contains "hardening: a UTF-8 path survives in the warning" "nope-日ł" "$err"

# Missing git is named as such, not reported as "not a repository".
mkdir -p "$tmp/nogit"
for tool in tr cat; do ln -s "$(command -v $tool)" "$tmp/nogit/$tool"; done
run in_dir "$tmp/repo" base PATH="$tmp/nogit" "$SH" "$RESOLVER" repo --checkout
assert_eq "hardening: missing git exits 3" 3 "$rc"
assert_contains "hardening: missing git is named" "git is not installed" "$err"

# A dangling writer-mode symlink is a broken install worth a warning.
mkdir -p "$tmp/claudedir-dangling"
ln -s "$tmp/nowhere" "$tmp/claudedir-dangling/planwright"
run base CLAUDE_DIR="$tmp/claudedir-dangling" "$SH" "$RESOLVER" install
assert_eq "hardening: a dangling writer-mode link is skipped" "$REPO_ROOT" "$out"
assert_contains "hardening: a dangling writer-mode link warns" "writer-mode" "$err"

# CLAUDE_DIR, once set, owns the writer-mode arm: HOME is not consulted.
run base CLAUDE_DIR="$tmp/claudedir-missing" HOME="$tmp/home2" "$SH" "$RESOLVER" install
assert_eq "hardening: a set CLAUDE_DIR is not backfilled from HOME" "$REPO_ROOT" "$out"

# --explain prints the canonical path for a non-canonical value.
run base PLANWRIGHT_ROOT="$tmp/pw-link/" "$SH" "$RESOLVER" install --explain
assert_eq "hardening: --explain canonicalizes" "PLANWRIGHT_ROOT${tab}$tmp/pw" "$out"

# A copy with nothing beside it and every arm unset has no install root.
mkdir -p "$tmp/lonely/bin"
cp "$RESOLVER" "$tmp/lonely/bin/resolve-root.sh"
run base "$SH" "$tmp/lonely/bin/resolve-root.sh" install
assert_eq "hardening: no content-bearing arm exits 1" 1 "$rc"
assert_empty "hardening: no content-bearing arm prints no path" "$out"
assert_contains "hardening: the skipped self-location arm warns" "self-location" "$err"

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
run base "$SH" "$RESOLVER"
assert_eq "usage: no kind exits 2" 2 "$rc"
run base "$SH" "$RESOLVER" nope
assert_eq "usage: an unknown kind exits 2" 2 "$rc"
run in_dir "$tmp/repo" base "$SH" "$RESOLVER" repo
assert_eq "usage: repo without a view exits 2" 2 "$rc"
run in_dir "$tmp/repo" base "$SH" "$RESOLVER" repo --primary --checkout
assert_eq "usage: repo with both views exits 2" 2 "$rc"
run base "$SH" "$RESOLVER" install --primary
assert_eq "usage: install takes no view" 2 "$rc"
run base "$SH" "$RESOLVER" "" install
assert_eq "usage: an empty argument exits 2" 2 "$rc"
run base "$SH" "$RESOLVER" install --bogus
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
  PLANWRIGHT_ROOT*get_env*PLANWRIGHT_ROOT*config_root*)
    echo "ok: mise.toml [env] pins PLANWRIGHT_ROOT as a config-root expansion an environment value overrides"
    ;;
  *)
    echo "FAIL: mise.toml [env] pins PLANWRIGHT_ROOT as a config-root expansion an environment value overrides (got '$pin_line')" >&2
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
  "$SH" "$RESOLVER" install
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
    base env -u MISE_ENV -u MISE_CONFIG_DIR -u MISE_STATE_DIR -u MISE_DATA_DIR \
      -u MISE_CACHE_DIR -u __MISE_DIFF -u __MISE_SESSION MISE_CEILING_PATHS="$tmp" \
      MISE_TRUSTED_CONFIG_PATHS="$tmp" MISE_GLOBAL_CONFIG_FILE="$tmp/mise-global.toml" \
      MISE_SYSTEM_CONFIG_FILE="$tmp/mise-global.toml" "$@" \
      mise exec -C "$mi_dir" -- "$SH" "$RESOLVER" install
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
  skips=$((skips + 3))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
if [ "$skips" -gt 0 ]; then
  echo "all resolve-root tests passed ($skips skipped)"
else
  echo "all resolve-root tests passed"
fi
