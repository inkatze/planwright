#!/bin/bash
# Tests for scripts/tower-placement.sh, the tower placement classifier: it
# prints `<placement><TAB><tower_placement>` for the current checkout, the
# placement being `main`, `linked`, or `none`, and exits 0 for every
# placement.
#
# What is covered:
#   - classification (REQ-B1.1): a main tree and a subdirectory of one, a
#     linked worktree, a separate clone, a bare repository, the inside of a
#     git directory, and a path outside any repository;
#   - only git's directory queries decide: a main tree under a
#     `.claude/worktrees/` path is still `main`, and a linked worktree outside
#     one is still `linked`;
#   - the knob (REQ-A1.3): `warn` by default, the shipped core default, each
#     value at each layer, and a malformed value at each layer per the
#     by-layer policy (adopter and machine-local warn and degrade to the core
#     default, repo-tracked exits 4, core exits 5).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-tower-placement.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
TP="$here/../scripts/tower-placement.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$TP" ] || fail "scripts/tower-placement.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P)

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR PLANWRIGHT_REPO_ROOT
# Discovery never climbs out of the scratch directory, so "outside any
# repository" holds even when the scratch directory sits inside one.
export GIT_CEILING_DIRECTORIES="$tmp"

gitq() {
  git -c user.name=t -c user.email=t@example.invalid "$@" >/dev/null 2>&1
}

core_cfg="$tmp/core-defaults.yml"
adopter_root="$tmp/adopter"
mkdir -p "$adopter_root"
adopter_cfg="$adopter_root/planwright.yml"
printf 'tower_placement: warn\n' >"$core_cfg"

repo="$tmp/repo"
gitq init -q "$repo"
gitq -C "$repo" commit -q --allow-empty -m init
mkdir -p "$repo/sub/dir" "$repo/.claude"
tracked_cfg="$repo/.claude/planwright.yml"
mlocal_cfg="$repo/.claude/planwright.local.yml"

reset_layers() {
  rm -f "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"
}

# run <dir>: the classifier from <dir> against the fixture layers; stdout is
# captured, stderr goes to $tmp/err, the exit status to $rc.
run() {
  rc=0
  out=$(cd "$1" && PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/sh "$TP" 2>"$tmp/err") || rc=$?
}

tab=$(printf '\t')

# expect <dir> <line> <label>
expect() {
  run "$1"
  [ "$rc" = 0 ] || fail "$3: exit $rc, expected 0 (stderr: $(cat "$tmp/err"))"
  [ "$out" = "$2" ] || fail "$3: printed '$out', expected '$2'"
  echo "ok: $3"
}

# --- Classification -------------------------------------------------------

reset_layers
expect "$repo" "main${tab}warn" "a main tree classifies as main"
expect "$repo/sub/dir" "main${tab}warn" "a main tree's subdirectory classifies as main"

linked="$tmp/elsewhere/linked"
mkdir -p "$tmp/elsewhere"
gitq -C "$repo" worktree add -q -b linked-branch "$linked"
mkdir -p "$linked/sub"
expect "$linked" "linked${tab}warn" "a linked worktree outside .claude/worktrees classifies as linked"
expect "$linked/sub" "linked${tab}warn" "a linked worktree's subdirectory classifies as linked"

clone="$tmp/clone"
gitq clone -q "$repo" "$clone"
expect "$clone" "main${tab}warn" "a separate clone classifies as main"

lookalike="$tmp/host/.claude/worktrees/lookalike"
mkdir -p "$lookalike"
gitq init -q "$lookalike"
expect "$lookalike" "main${tab}warn" "a main tree under a .claude/worktrees path classifies as main"

bare="$tmp/bare.git"
gitq init -q --bare "$bare"
expect "$bare" "none${tab}warn" "a bare repository classifies as none"

expect "$repo/.git" "none${tab}warn" "the inside of a git directory classifies as none"

outside="$tmp/outside"
mkdir -p "$outside"
expect "$outside" "none${tab}warn" "a path outside any repository classifies as none"

# --- The knob ---------------------------------------------------------------

# The shipped core default is warn.
rc=0
out=$(cd "$repo" && PLANWRIGHT_CONFIG_DEFAULTS="$here/../config/defaults.yml" \
  PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_LOCAL_CONFIG="" /bin/sh "$TP" 2>"$tmp/err") || rc=$?
[ "$rc" = 0 ] || fail "shipped default: exit $rc (stderr: $(cat "$tmp/err"))"
[ "$out" = "main${tab}warn" ] || fail "shipped default: printed '$out', expected warn"
# A key absent from the core layer would also print warn, through the
# fallback, but with a warning.
[ ! -s "$tmp/err" ] || fail "shipped default: unexpected stderr: $(cat "$tmp/err")"
echo "ok: the shipped core default is warn"

for value in warn refuse allow; do
  reset_layers
  printf 'tower_placement: %s\n' "$value" >"$core_cfg"
  expect "$repo" "main${tab}$value" "core layer value $value"
  printf 'tower_placement: warn\n' >"$core_cfg"

  reset_layers
  printf 'tower_placement: %s\n' "$value" >"$adopter_cfg"
  expect "$repo" "main${tab}$value" "adopter layer value $value"

  reset_layers
  printf 'tower_placement: %s\n' "$value" >"$tracked_cfg"
  expect "$repo" "main${tab}$value" "repo-tracked layer value $value"

  reset_layers
  printf 'tower_placement: %s\n' "$value" >"$mlocal_cfg"
  expect "$repo" "main${tab}$value" "machine-local layer value $value"
done

# A linked worktree reads the primary checkout's layers.
reset_layers
printf 'tower_placement: refuse\n' >"$mlocal_cfg"
expect "$linked" "linked${tab}refuse" "a linked worktree reads the primary's machine-local value"

# Malformed adopter and machine-local values warn and degrade to the core
# default, which is refuse here so the degrade is observable.
printf 'tower_placement: refuse\n' >"$core_cfg"
for layer in adopter machine-local; do
  reset_layers
  case $layer in
    adopter) cfg=$adopter_cfg ;;
    machine-local) cfg=$mlocal_cfg ;;
  esac
  printf 'tower_placement: sometimes\n' >"$cfg"
  expect "$repo" "main${tab}refuse" "a malformed $layer value degrades to the core default"
  grep -q "tower_placement" "$tmp/err" || fail "malformed $layer value: no warning naming the knob"
  echo "ok: a malformed $layer value warns"
done
printf 'tower_placement: warn\n' >"$core_cfg"

# A malformed repo-tracked value hard-fails, printing no classification.
reset_layers
printf 'tower_placement: sometimes\n' >"$tracked_cfg"
run "$repo"
[ "$rc" = 4 ] || fail "malformed repo-tracked value: exit $rc, expected 4"
[ -z "$out" ] || fail "malformed repo-tracked value: printed '$out'"
echo "ok: a malformed repo-tracked value exits 4"

# A malformed core default is a broken install.
reset_layers
printf 'tower_placement: sometimes\n' >"$core_cfg"
run "$repo"
[ "$rc" = 5 ] || fail "malformed core default: exit $rc, expected 5"
[ -z "$out" ] || fail "malformed core default: printed '$out'"
echo "ok: a malformed core default exits 5"
printf 'tower_placement: warn\n' >"$core_cfg"

# Arguments are refused.
rc=0
(cd "$repo" && /bin/sh "$TP" extra >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "an argument: exit $rc, expected 2"
echo "ok: an argument is a usage error"

echo "all tower-placement tests passed"
