#!/bin/bash
# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
# Tests for scripts/worker-settings-generate.sh: the per-launch worker profile
# an opted-in launch passes with --settings. It is the shipped profile with the
# four task-file deny rules replaced by literal denies for each of those names
# in every ancestor folder of the worktree (and the primary checkout), so the
# worktree's own task files open and nothing else does.
#
# Hermetic: the repository, worktree and output all live under a mktemp folder.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
for v in $(compgen -e); do
  case $v in
    GIT_* | PLANWRIGHT_* | CLAUDE_*) unset "$v" ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
GEN="$REPO_ROOT/scripts/worker-settings-generate.sh"
PROFILE="$REPO_ROOT/config/worker-settings.json"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to run this suite" >&2
  exit 1
}
[ -f "$GEN" ] || {
  echo "FAIL: scripts/worker-settings-generate.sh is missing" >&2
  exit 1
}

T=$(mktemp -d "${TMPDIR:-/tmp}/pw-settings-gen.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
T=$(cd "$T" && pwd -P)
export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
echo "scratch folder: $T"

MAIN=$T/main
WT=$MAIN/.claude/worktrees/w1
git init -q "$MAIN"
git -C "$MAIN" symbolic-ref HEAD refs/heads/main
git -C "$MAIN" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m init
git -C "$MAIN" worktree add -q -b planwright/flight/x-0123abcd "$WT" main

OUT=$T/out/settings.json
mkdir -p "$T/out"

run_gen() {
  /bin/sh "$GEN" "$PROFILE" "$1" "$2" 2>"$T/err"
}

if run_gen "$WT" "$OUT" >"$T/stdout"; then
  ok "the generator runs on a linked worktree"
else
  fail "the generator failed: $(cat "$T/err")"
fi
[ "$(cat "$T/stdout")" = "$OUT" ] && ok "it prints the path it wrote" || fail "stdout was: $(cat "$T/stdout")"
jq -e . "$OUT" >/dev/null 2>&1 && ok "the output is valid JSON" || fail "the output is not JSON"

# The four shipped task-file denies are gone.
for r in 'Edit(//**/mise.toml)' 'Edit(//**/.mise.toml)' 'Edit(//**/mise-tasks/**)' 'Edit(//**/.mise-tasks/**)'; do
  if jq -e --arg r "$r" '.permissions.deny | index($r) | not' "$OUT" >/dev/null; then
    ok "the broad deny $r is removed"
  else
    fail "the broad deny $r is still present"
  fi
done

# Each ancestor of the worktree, the primary checkout and the root included,
# gets a literal deny for each of the four names.
for a in "$MAIN/.claude/worktrees" "$MAIN/.claude" "$MAIN" "$T" /; do
  base=${a%/}
  for n in mise.toml .mise.toml mise-tasks/\*\* .mise-tasks/\*\*; do
    r="Edit(/$base/$n)"
    if jq -e --arg r "$r" '.permissions.deny | index($r)' "$OUT" >/dev/null; then
      ok "ancestor deny present: $r"
    else
      fail "ancestor deny missing: $r"
    fi
  done
done
# The worktree itself gets none.
if jq -e --arg w "Edit(/$WT/" '[.permissions.deny[] | select(startswith($w))] | length == 0' "$OUT" >/dev/null; then
  ok "no literal deny names the worktree itself"
else
  fail "a literal deny names the worktree itself"
fi

# Everything else is exactly the shipped profile: same order, same entries.
want=$(jq -c '
  del(.permissions.deny)
  | del(._about)' "$PROFILE")
got=$(jq -c '
  del(.permissions.deny)
  | del(._about)' "$OUT")
[ "$want" = "$got" ] && ok "allow list, hooks and every other key are the shipped ones" || fail "a non-deny key differs from the shipped profile"
rest=$(jq -c '[.permissions.deny[] | select(
  . != "Edit(//**/mise.toml)" and . != "Edit(//**/.mise.toml)"
  and . != "Edit(//**/mise-tasks/**)" and . != "Edit(//**/.mise-tasks/**)")]' "$PROFILE")
gotrest=$(jq -c '[.permissions.deny[] | select(
  (test("^Edit\\(/[^*]*/(mise\\.toml|\\.mise\\.toml|mise-tasks/\\*\\*|\\.mise-tasks/\\*\\*)\\)$") | not))]' "$OUT")
[ "$rest" = "$gotrest" ] && ok "every other deny rule stays, in order, as shipped" || fail "the remaining deny rules differ from the shipped ones"
for r in 'Edit(//**/mise.*.toml)' 'Edit(//**/.mise.*.toml)' 'Edit(//**/.miserc*.toml)' 'Edit(//**/mise*.lock)' \
  'Edit(//**/mise/conf.d/**)' 'Edit(//**/mise/tasks/**)' 'Edit(//**/.local/state/mise/**)' 'Edit(//**/.cache/mise/**)' \
  'Edit(//**/.local/share/mise/**)' 'Edit(//**/.mise/**)'; do
  jq -e --arg r "$r" '.permissions.deny | index($r)' "$OUT" >/dev/null && ok "kept: $r" || fail "dropped: $r"
done

# Owner-only, written whole.
mode=$(stat -c %a "$OUT" 2>/dev/null || stat -f %Lp "$OUT")
[ "$mode" = 600 ] && ok "the file is owner-only" || fail "mode is $mode"
left=$(find "$T/out" -maxdepth 1 -name '.*' -type f)
[ -z "$left" ] && ok "no temporary file is left" || fail "a temporary file was left beside the output: $left"

# Idempotent: a second run gives the same bytes.
cp "$OUT" "$T/first.json"
run_gen "$WT" "$OUT" >/dev/null
cmp -s "$T/first.json" "$OUT" && ok "a second run writes the same bytes" || fail "a second run changed the output"

# A worktree outside its primary checkout: the primary's names are denied too.
OTHER=$T/elsewhere/w2
git -C "$MAIN" worktree add -q -b planwright/flight/y-0123abcd "$OTHER" main
run_gen "$OTHER" "$T/out/other.json" >/dev/null || fail "the generator failed for an outside worktree: $(cat "$T/err")"
for n in mise.toml .mise.toml 'mise-tasks/**' '.mise-tasks/**'; do
  r="Edit(/$MAIN/$n)"
  jq -e --arg r "$r" '.permissions.deny | index($r)' "$T/out/other.json" >/dev/null \
    && ok "the primary checkout is denied when the worktree is elsewhere: $r" \
    || fail "the primary checkout is not denied: $r"
done

# Refusals: a path glob characters could widen, a missing worktree, a bad profile, usage.
for bad in 'we*ird' 'we?ird' 'we[ird' 'we]ird' 'we\ird' 'we(ird' 'we)ird' "$(printf 'we\tird')" 'weird '; do
  mkdir -p "$T/g/$bad"
  git init -q "$T/g/$bad"
  if /bin/sh "$GEN" "$PROFILE" "$T/g/$bad" "$T/out/g.json" >"$T/stdout" 2>"$T/err"; then
    fail "a worktree path with a pattern character was accepted: $bad"
  elif grep -q 'pattern' "$T/err"; then
    ok "a worktree path with a pattern character is refused for that reason: $bad"
  else
    fail "the refusal for '$bad' did not name the pattern character: $(cat "$T/err")"
  fi
done
# A primary checkout whose git directory is not <checkout>/.git cannot be named,
# so the launch is refused instead of leaving its task files open.
git init -q --separate-git-dir "$T/sepgit" "$T/sepmain"
git -C "$T/sepmain" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m init
git -C "$T/sepmain" worktree add -q -b planwright/flight/z-0123abcd "$T/sepwt"
if /bin/sh "$GEN" "$PROFILE" "$T/sepwt" "$T/out/sep.json" >"$T/stdout" 2>"$T/err"; then
  fail "a worktree of a separate-git-dir checkout was accepted"
elif grep -q 'primary checkout' "$T/err"; then
  ok "a primary checkout that cannot be named refuses the launch"
else
  fail "the separate-git-dir refusal did not name the primary checkout: $(cat "$T/err")"
fi
[ ! -e "$T/out/sep.json" ] && ok "and writes nothing" || fail "a refused separate-git-dir run wrote a file"
if /bin/sh "$GEN" "$PROFILE" "$WT" "$T/no-such-folder/x.json" >/dev/null 2>&1; then
  fail "a missing output folder was accepted"
else
  ok "a missing output folder is refused"
fi
[ ! -e "$T/out/g.json" ] && ok "a refused run writes nothing" || fail "a refused run wrote a file"
/bin/sh "$GEN" "$PROFILE" "$T/nope" "$T/out/n.json" >/dev/null 2>&1 && fail "a missing worktree was accepted" || ok "a missing worktree is refused"
printf '{"permissions":{"deny":[]}}\n' >"$T/thin.json"
/bin/sh "$GEN" "$T/thin.json" "$WT" "$T/out/t.json" >/dev/null 2>&1 && fail "a profile without the task-file denies was accepted" || ok "a profile missing the shipped task-file denies is refused"
printf '{ not json' >"$T/bad.json"
/bin/sh "$GEN" "$T/bad.json" "$WT" "$T/out/b.json" >/dev/null 2>&1 && fail "an unparseable profile was accepted" || ok "an unparseable profile is refused"
/bin/sh "$GEN" "$PROFILE" "$WT" >/dev/null 2>&1
[ $? -eq 2 ] && ok "missing arguments are a usage error (exit 2)" || fail "missing arguments did not exit 2"
/bin/sh "$GEN" "$PROFILE" "$WT" "$WT/inside.json" >/dev/null 2>&1 && fail "an output inside the worktree was accepted" || ok "an output inside the worktree is refused"
[ ! -e "$WT/inside.json" ] && ok "nothing was written inside the worktree" || fail "a file was written inside the worktree"

if [ "$failures" -eq 0 ]; then
  echo "all worker-settings-generate assertions passed"
  exit 0
fi
echo "$failures failure(s)" >&2
exit 1
