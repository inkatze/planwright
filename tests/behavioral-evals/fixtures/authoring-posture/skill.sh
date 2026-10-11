#!/bin/sh
# authoring-posture/skill.sh — the deterministic stand-in for /spec-draft
# completing a bundle with its spec root outside the work repository
# (custom-spec-location REQ-E1.2, REQ-E1.3). It builds a work repository and a
# store in the artifacts directory (a holder repository with its own remote,
# or a plain directory), classifies the posture through the real resolver,
# follows docs/spec-location.md's authoring table for that posture (the holder
# worktree through scripts/spec-store-worktree.sh, the draft commit there; or
# the files alone, every git step skipped), prints the handoff, and records
# what each repository's git state shows afterwards. The real skill is
# model-backed; this pins the observable contract.
#
# Usage: skill.sh <artifacts-dir>
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

art="${1:-}"
[ -n "$art" ] || {
  echo "authoring-posture/skill.sh: an artifacts directory argument is required" >&2
  exit 2
}
mkdir -p "$art" 2>/dev/null || exit 2
art=$(cd "$art" && pwd -P) || exit 2
here=$(cd "$(dirname "$0")" && pwd -P) || exit 2
repo=$(cd "$here/../../../.." && pwd -P) || exit 2
log="$art/decision-log.jsonl"
signoff="$art/sign-off.json"
: >"$log"

emit_ready() { printf 'EVAL-READY turn=%s\n' "$1"; }
log_turn() {
  jq -cn --argjson turn "$1" --arg q "$2" --arg a "$3" '{turn: $turn, question: $q, answer: $a}' >>"$log" || exit 2
}
# fx <command...> — the fixture's git and scripts, fenced at the artifacts
# directory and pinned to this checkout, with no inherited planwright setting.
inherited_unsets=$(env | sed -n 's/^\(PLANWRIGHT_[A-Za-z0-9_]*\)=.*/-u \1/p')
fx() {
  # shellcheck disable=SC2086 # one `-u NAME` pair per word
  env $inherited_unsets -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
    HOME="$art/home" GIT_CEILING_DIRECTORIES="$art" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
    GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
    PLANWRIGHT_ROOT="$repo" "$@"
}
refs() { fx git -C "$1" for-each-ref --format='%(refname) %(objectname)'; }

printf 'Authoring stand-in: /spec-draft is about to write. Which store holds the spec root (holder or plain)?\n'
emit_ready 1
IFS= read -r posture_answer || exit 0
case $posture_answer in
  holder | plain) ;;
  *) posture_answer=holder ;;
esac
log_turn 1 posture "$posture_answer"

printf 'Which spec identifier?\n'
emit_ready 2
IFS= read -r id || exit 0
case $id in
  '' | *[!a-z0-9-]* | [!a-z0-9]*) id=demo ;;
esac
log_turn 2 spec "$id"

# The fixture: a work repository whose machine-local spec_root names the store.
w=$art/work
mkdir -p "$art/home"
fx git -c init.defaultBranch=main init -q "$w" >/dev/null 2>&1 || exit 2
printf 'x\n' >"$w/file"
fx git -C "$w" add -A >/dev/null 2>&1 && fx git -C "$w" commit -q -m init >/dev/null 2>&1 || exit 2
if [ "$posture_answer" = holder ]; then
  h=$art/holder
  fx git -c init.defaultBranch=trunk init -q --bare "$art/holder-origin.git" >/dev/null 2>&1 || exit 2
  fx git -c init.defaultBranch=trunk init -q "$h" >/dev/null 2>&1 || exit 2
  root=$h/projects/work
else
  root=$art/store
fi
mkdir -p "$root" "$w/.claude"
printf 'project: fixture\nlayout: 1\n' >"$root/planwright-spec-root.yml"
printf 'spec_root: %s\n' "$root" >"$w/.claude/planwright.local.yml"
if [ "$posture_answer" = holder ]; then
  printf '.claude/worktrees/\n' >"$h/.gitignore"
  fx git -C "$h" add -A >/dev/null 2>&1 && fx git -C "$h" commit -q -m root >/dev/null 2>&1 || exit 2
  fx git -C "$h" remote add origin "$art/holder-origin.git" >/dev/null 2>&1 || exit 2
  fx git -C "$h" push -q -u origin trunk >/dev/null 2>&1 || exit 2
  fx git -C "$h" remote set-head origin --auto >/dev/null 2>&1 || exit 2
  remote_before=$(fx git --git-dir="$art/holder-origin.git" for-each-ref --format='%(refname) %(objectname)')
fi
work_refs_before=$(refs "$w")

# The skill: resolve the root and its posture, then follow the guide's table.
posture=$(cd "$w" && fx "$repo/scripts/resolve-root.sh" spec --posture 2>"$art/resolve.err") || posture=''
case $posture in
  separate-repo) posture=holder ;;
esac
worktree='' bundle=''
if [ "$posture" = holder ]; then
  out=$(cd "$w" && fx "$repo/scripts/spec-store-worktree.sh" "$id" 2>"$art/store-worktree.err") || out=''
  worktree=$(printf '%s\n' "$out" | sed -n 's/^worktree	//p')
  bundle=$(printf '%s\n' "$out" | sed -n 's/^bundle	//p')
elif [ "$posture" = plain ]; then
  bundle=$(cd "$w" && fx "$repo/scripts/resolve-root.sh" spec 2>>"$art/resolve.err")/$id || bundle=''
fi
files=0
if [ -n "$bundle" ]; then
  mkdir -p "$bundle" || exit 2
  for f in requirements design tasks test-spec; do
    printf '# Demo — %s\n\n**Status:** Draft\n**Format-version:** 2\n' "$f" >"$bundle/$f.md" && files=$((files + 1))
  done
fi
if [ "$posture" = holder ] && [ -n "$worktree" ]; then
  fx git -C "$worktree" add -A >/dev/null 2>&1 \
    && fx git -C "$worktree" commit -q -m "feat(spec): draft specs/$id bundle" >/dev/null 2>&1 || exit 2
  handoff="Drafted $id at $bundle, committed on planwright/$id/spec in the holder (worktree $worktree). Next: /spec-kickoff $id, which pushes and opens the spec PR in the holder."
else
  handoff="Drafted $id at $bundle. The spec root is a plain directory, so these steps were skipped: spec branch, spec worktree, commit, push, spec PR, ready flip; and no spec guard runs on a plain store, since CI and commit hooks never see it."
fi
printf '%s\n' "$handoff"
jq -cn --arg t "$handoff" '{kind: "handoff", text: $t}' >>"$log" || exit 2

# What the repositories show afterwards.
work_new_commit=false work_new_branch=false work_new_worktree=false
[ "$(fx git -C "$w" rev-parse HEAD)" = "$(printf '%s\n' "$work_refs_before" | sed -n 's#^refs/heads/main ##p')" ] \
  || work_new_commit=true
[ "$(refs "$w")" = "$work_refs_before" ] || work_new_branch=true
[ "$(fx git -C "$w" worktree list --porcelain | grep -c '^worktree ')" -eq 1 ] || work_new_worktree=true
branch_has_bundle=false holder_clean=false holder_pushed=false spec_branch_anywhere=false store_has_git=false
expected_worktree=''
if [ "$posture_answer" = holder ]; then
  expected_worktree=$h/.claude/worktrees/$id-spec
  rel=${bundle#"$worktree"/}
  [ "$(fx git -C "$h" ls-tree --name-only "planwright/$id/spec" -- "$rel/" 2>/dev/null | wc -l | tr -d ' ')" -eq 4 ] \
    && branch_has_bundle=true
  [ -z "$(fx git -C "$h" status --porcelain)" ] && [ -z "$(fx git -C "$worktree" status --porcelain)" ] && holder_clean=true
  [ "$(fx git --git-dir="$art/holder-origin.git" for-each-ref --format='%(refname) %(objectname)')" = "$remote_before" ] \
    || holder_pushed=true
else
  [ -e "$root/.git" ] && store_has_git=true
  fx git -C "$w" show-ref --verify --quiet "refs/heads/planwright/$id/spec" && spec_branch_anywhere=true
fi

jq -n --arg posture "$posture" --argjson files "$files" --arg wt "$worktree" --arg ewt "$expected_worktree" \
  --argjson wc "$work_new_commit" --argjson wb "$work_new_branch" --argjson ww "$work_new_worktree" \
  --argjson bb "$branch_has_bundle" --argjson hc "$holder_clean" --argjson hp "$holder_pushed" \
  --argjson sb "$spec_branch_anywhere" --argjson sg "$store_has_git" \
  '{subject: "spec draft", decision: "drafted", posture: $posture, files_written: $files,
    worktree: $wt, expected_worktree: $ewt, work_new_commit: $wc, work_new_branch: $wb,
    work_new_worktree: $ww, branch_has_bundle: $bb, holder_clean: $hc, holder_pushed: $hp,
    spec_branch_anywhere: $sb, store_has_git: $sg,
    eval_only: true, authoritative: false, publishing_disabled: true}' >"$signoff.tmp" \
  && mv "$signoff.tmp" "$signoff" || exit 2
printf 'Authoring stand-in: done.\n'
