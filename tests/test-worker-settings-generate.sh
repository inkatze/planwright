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
  | del(._about)
  | .hooks.PreToolUse |= map(select(.matcher != "Edit|Write|MultiEdit|NotebookEdit"))' "$OUT")
[ "$(jq '[.hooks.PreToolUse[] | select(.matcher == "Edit|Write|MultiEdit|NotebookEdit")] | length' "$OUT")" = 1 ] \
  && ok "the generated profile carries exactly one file-tool guard hook" \
  || fail "the generated profile must carry exactly one file-tool guard hook"
[ "$want" = "$got" ] && ok "allow list, hooks and every other key are the shipped ones" || fail "a non-deny key differs from the shipped profile"
jq -e '.permissions.allow | (index("WebSearch") == null) and (index("WebFetch") == null)' "$OUT" >/dev/null \
  && ok "the generated profile leaves WebSearch and WebFetch to the prompt" \
  || fail "the generated profile must allow neither WebSearch nor WebFetch"
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

# The lefthook config opt-in: --lefthook-edit replaces the two broad lefthook
# denies (lefthook/** and lefthook.*) the same way, and only those.
LH_OUT=$T/out/lefthook.json
if /bin/sh "$GEN" --lefthook-edit "$PROFILE" "$WT" "$LH_OUT" >"$T/stdout" 2>"$T/err"; then
  ok "lefthook: the generator runs with --lefthook-edit"
else
  fail "lefthook: the generator failed: $(cat "$T/err")"
fi
for r in 'Edit(//**/lefthook/**)' 'Edit(//**/lefthook.*)'; do
  jq -e --arg r "$r" '.permissions.deny | index($r) | not' "$LH_OUT" >/dev/null 2>&1 \
    && ok "lefthook: the broad deny $r is removed" || fail "lefthook: the broad deny $r is still present"
done
for a in "$MAIN/.claude/worktrees" "$MAIN/.claude" "$MAIN" "$T" /; do
  base=${a%/}
  for n in 'lefthook/**' 'lefthook.*'; do
    jq -e --arg r "Edit(/$base/$n)" '.permissions.deny | index($r)' "$LH_OUT" >/dev/null 2>&1 \
      && ok "lefthook: ancestor deny present: Edit(/$base/$n)" || fail "lefthook: ancestor deny missing: Edit(/$base/$n)"
  done
done
if jq -e --arg w "Edit(/$WT/" '[.permissions.deny[] | select(startswith($w))] | length == 0' "$LH_OUT" >/dev/null 2>&1; then
  ok "lefthook: no literal deny names the worktree itself"
else
  fail "lefthook: a literal deny names the worktree itself"
fi
# Every other rule is the shipped one: the mise names, the local and dotted
# lefthook variants, the hook directories and the opt-in markers all stay.
for r in 'Edit(//**/mise.toml)' 'Edit(//**/.mise.toml)' 'Edit(//**/mise-tasks/**)' 'Edit(//**/.mise-tasks/**)' \
  'Edit(//**/lefthook-local.*)' 'Edit(//**/.lefthook/**)' 'Edit(//**/.lefthook.*)' 'Edit(//**/.lefthook-local/**)' \
  'Edit(//**/.lefthook-local.*)' 'Edit(//**/githooks/**)' 'Edit(//**/.githooks/**)' 'Edit(//**/.git/**)' \
  'Edit(.claude/**)' 'Edit(//**/streamjson/*/lefthook-edit)' 'Edit(//**/streamjson/*/mise-task-edit)' \
  'Edit(//**/streamjson/*/worker-settings.json)'; do
  jq -e --arg r "$r" '.permissions.deny | index($r)' "$LH_OUT" >/dev/null 2>&1 && ok "lefthook: kept: $r" || fail "lefthook: dropped: $r"
done
lh_rest=$(jq -c '[.permissions.deny[] | select(. != "Edit(//**/lefthook/**)" and . != "Edit(//**/lefthook.*)")]' "$PROFILE")
lh_got=$(jq -c '[.permissions.deny[] | select(test("^Edit\\(/[^*]*/(lefthook/\\*\\*|lefthook\\.\\*)\\)$") | not)]' "$LH_OUT")
[ "$lh_rest" = "$lh_got" ] && ok "lefthook: every other deny rule stays, in order, as shipped" || fail "lefthook: the remaining deny rules differ from the shipped ones"
lh_want=$(jq -c 'del(.permissions.deny) | del(._about)' "$PROFILE")
lh_gotall=$(jq -c 'del(.permissions.deny) | del(._about) | .hooks.PreToolUse |= map(select(.matcher != "Edit|Write|MultiEdit|NotebookEdit"))' "$LH_OUT")
[ "$lh_want" = "$lh_gotall" ] && ok "lefthook: allow list, hooks and every other key are the shipped ones" || fail "lefthook: a non-deny key differs from the shipped profile"
# The file-tool hook is wired once, told to judge the lefthook names and not the mise ones.
lh_cmds=$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Edit|Write|MultiEdit|NotebookEdit") | .hooks[].command] | .[]' "$LH_OUT")
case $lh_cmds in
  *"worker-mise-edit-guard.sh '$WT' lefthook") ok "lefthook: the hook is wired for the lefthook names only" ;;
  *) fail "lefthook: the hook command is: $lh_cmds" ;;
esac
[ "$(printf '%s\n' "$lh_cmds" | grep -c .)" = 1 ] && ok "lefthook: exactly one file-tool hook" || fail "lefthook: not exactly one file-tool hook"
mode=$(stat -c %a "$LH_OUT" 2>/dev/null || stat -f %Lp "$LH_OUT")
[ "$mode" = 600 ] && ok "lefthook: the file is owner-only" || fail "lefthook: mode is $mode"

# Both opt-ins: the four mise and the two lefthook broad denies are replaced, and
# the hook judges both name sets.
BOTH_OUT=$T/out/both.json
if /bin/sh "$GEN" --mise-task-edit --lefthook-edit "$PROFILE" "$WT" "$BOTH_OUT" >/dev/null 2>"$T/err"; then
  ok "both: the generator runs with both flags"
else
  fail "both: the generator failed: $(cat "$T/err")"
fi
for r in 'Edit(//**/mise.toml)' 'Edit(//**/.mise.toml)' 'Edit(//**/mise-tasks/**)' 'Edit(//**/.mise-tasks/**)' 'Edit(//**/lefthook/**)' 'Edit(//**/lefthook.*)'; do
  jq -e --arg r "$r" '.permissions.deny | index($r) | not' "$BOTH_OUT" >/dev/null 2>&1 && ok "both: the broad deny $r is removed" || fail "both: the broad deny $r is still present"
done
for n in mise.toml .mise.toml 'mise-tasks/**' '.mise-tasks/**' 'lefthook/**' 'lefthook.*'; do
  jq -e --arg r "Edit(/$MAIN/$n)" '.permissions.deny | index($r)' "$BOTH_OUT" >/dev/null 2>&1 \
    && ok "both: the primary checkout is denied: Edit(/$MAIN/$n)" || fail "both: the primary checkout is not denied: $n"
done
both_cmds=$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Edit|Write|MultiEdit|NotebookEdit") | .hooks[].command] | .[]' "$BOTH_OUT")
case $both_cmds in
  *"worker-mise-edit-guard.sh '$WT' mise lefthook") ok "both: the hook is wired for both name sets" ;;
  *) fail "both: the hook command is: $both_cmds" ;;
esac
# The existing mise-only form is unchanged: no lefthook rule moves.
jq -e '.permissions.deny | (index("Edit(//**/lefthook.*)") != null) and (index("Edit(//**/lefthook/**)") != null)' "$OUT" >/dev/null 2>&1 \
  && ok "the mise-only form leaves the broad lefthook denies in place" || fail "the mise-only form changed the lefthook denies"
mise_cmd=$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Edit|Write|MultiEdit|NotebookEdit") | .hooks[].command] | .[0]' "$OUT")
[ "$mise_cmd" = "\"\$CLAUDE_PLUGIN_ROOT\"/scripts/worker-mise-edit-guard.sh '$WT'" ] \
  && ok "the mise-only hook command is unchanged" || fail "the mise-only hook command changed: $mise_cmd"
# --mise-task-edit alone is the legacy form.
/bin/sh "$GEN" --mise-task-edit "$PROFILE" "$WT" "$T/out/m.json" >/dev/null 2>&1 && cmp -s "$T/out/m.json" "$OUT" \
  && ok "--mise-task-edit alone writes the same bytes as the flagless form" || fail "--mise-task-edit alone differs from the flagless form"
# A generator without its hook script beside it is refused rather than leaving
# every opted-in name outside the ancestors editable.
mkdir -p "$T/lone"
cp "$GEN" "$T/lone/worker-settings-generate.sh"
/bin/sh "$T/lone/worker-settings-generate.sh" --lefthook-edit "$PROFILE" "$WT" "$T/out/lone.json" >/dev/null 2>"$T/err" \
  && fail "a generator with no hook script beside it was accepted" \
  || { grep -q 'hook' "$T/err" && ok "a generator with no hook script beside it is refused for that reason" || fail "the missing-hook refusal did not name the hook: $(cat "$T/err")"; }
[ ! -e "$T/out/lone.json" ] && ok "and writes nothing" || fail "a refused no-hook run wrote a file"
# The generator checks only the copy beside it: the launch preflight proves the
# one under the worker's own root, so an exported plugin root does not move it.
mkdir -p "$T/otherroot/scripts"
CLAUDE_PLUGIN_ROOT=$T/otherroot /bin/sh "$GEN" --lefthook-edit "$PROFILE" "$WT" "$T/out/otherroot.json" >/dev/null 2>"$T/err" \
  && ok "an exported plugin root without the hook does not move the generator's own check" \
  || fail "the generator read the exported plugin root for its hook check: $(cat "$T/err")"
CLAUDE_PLUGIN_ROOT=$T/otherroot /bin/sh "$T/lone/worker-settings-generate.sh" --lefthook-edit "$PROFILE" "$WT" "$T/out/lone2.json" >/dev/null 2>"$T/err" \
  && fail "a generator with no hook beside it was accepted under an exported plugin root" \
  || ok "a generator with no hook beside it is refused whatever plugin root is exported"
# A profile that lacks the lefthook denies cannot be opened up; a repeated flag is usage.
jq 'del(.permissions.deny[] | select(. == "Edit(//**/lefthook.*)"))' "$PROFILE" >"$T/nolh.json"
/bin/sh "$GEN" --lefthook-edit "$T/nolh.json" "$WT" "$T/out/nolh.out.json" >/dev/null 2>&1 \
  && fail "a profile without the lefthook denies was accepted for --lefthook-edit" || ok "a profile missing a shipped lefthook deny is refused for --lefthook-edit"
[ ! -e "$T/out/nolh.out.json" ] && ok "and writes nothing" || fail "a refused lefthook run wrote a file"
/bin/sh "$GEN" --lefthook-edit --lefthook-edit "$PROFILE" "$WT" "$T/out/dup.json" >/dev/null 2>&1
[ $? -eq 2 ] && ok "a repeated --lefthook-edit is a usage error (exit 2)" || fail "a repeated --lefthook-edit did not exit 2"
/bin/sh "$GEN" --lefthook-edit "$PROFILE" "$WT" "$WT/inside.json" >/dev/null 2>&1 && fail "a lefthook output inside the worktree was accepted" || ok "a lefthook output inside the worktree is refused"

if [ "$failures" -eq 0 ]; then
  echo "all worker-settings-generate assertions passed"
  exit 0
fi
echo "$failures failure(s)" >&2
exit 1
