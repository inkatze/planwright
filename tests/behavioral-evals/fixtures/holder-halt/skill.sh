#!/bin/sh
# holder-halt/skill.sh — the deterministic stand-in for an execution skill
# halting to Awaiting input with its spec root outside the work repository
# (custom-spec-location REQ-E1.9). It builds a work repository and a store in
# the artifacts directory (a holder repository with its own remote, or a plain
# directory), halts Task 1 through scripts/halt-note.sh exactly as
# /execute-task does in those postures, prints the handoff naming the file, and
# records what the store's git state shows afterwards. The real skill is
# model-backed; this pins the observable contract: the bullet is an
# uncommitted change in the store's primary view, the holder gains no commit,
# branch, or push, and the handoff names the file.
#
# Usage: skill.sh <artifacts-dir>
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

art="${1:-}"
[ -n "$art" ] || {
  echo "holder-halt/skill.sh: an artifacts directory argument is required" >&2
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
  env $inherited_unsets -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    HOME="$art/home" GIT_CEILING_DIRECTORIES="$art" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
    GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
    PLANWRIGHT_ROOT="$repo" "$@"
}

printf 'Execution stand-in: Task 1 is about to halt. Which store holds the spec root (holder or plain)?\n'
emit_ready 1
IFS= read -r posture || exit 0
case $posture in
  holder | plain) ;;
  *) posture=holder ;;
esac
log_turn 1 posture "$posture"

printf 'What is the halt reason?\n'
emit_ready 2
IFS= read -r reason || exit 0
[ -n "$reason" ] || reason="halted"
log_turn 2 reason "$reason"

# The fixture: a work repository whose machine-local spec_root names the store.
w=$art/work
mkdir -p "$art/home"
fx git -c init.defaultBranch=main init -q "$w" >/dev/null 2>&1 || exit 2
printf 'x\n' >"$w/file"
fx git -C "$w" add -A >/dev/null 2>&1 && fx git -C "$w" commit -q -m init >/dev/null 2>&1 || exit 2
if [ "$posture" = holder ]; then
  fx git -c init.defaultBranch=trunk init -q --bare "$art/holder-origin.git" >/dev/null 2>&1 || exit 2
  fx git -c init.defaultBranch=trunk init -q "$art/holder" >/dev/null 2>&1 || exit 2
  root=$art/holder/specs
else
  root=$art/store
fi
mkdir -p "$root/demo" "$w/.claude"
printf 'project: fixture\nlayout: 1\n' >"$root/planwright-spec-root.yml"
cat >"$root/demo/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Ready
**Format-version:** 2

## Tasks

### Task 1 — the unit

- **Deliverables:** a thing
- **Done when:** the thing exists
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
printf 'spec_root: %s\n' "$root" >"$w/.claude/planwright.local.yml"
if [ "$posture" = holder ]; then
  h=$art/holder
  fx git -C "$h" add -A >/dev/null 2>&1 && fx git -C "$h" commit -q -m bundle >/dev/null 2>&1 || exit 2
  fx git -C "$h" remote add origin "$art/holder-origin.git" >/dev/null 2>&1 || exit 2
  fx git -C "$h" push -q origin trunk >/dev/null 2>&1 || exit 2
  head_before=$(fx git -C "$h" rev-parse HEAD)
  refs_before=$(fx git -C "$h" for-each-ref --format='%(refname)' refs/heads)
  remote_before=$(fx git --git-dir="$art/holder-origin.git" for-each-ref --format='%(refname) %(objectname)')
fi

# The halt.
note_file=$(cd "$w" && fx "$repo/scripts/halt-note.sh" demo 1 "$reason" 2>"$art/halt-note.err") || note_file=''
written=false
if [ -n "$note_file" ] && grep -qF -- "- **Task 1** — $reason" "$note_file" 2>/dev/null; then
  written=true
fi
handoff="Halted Task 1 to Awaiting input. The note is an uncommitted change in the spec store: $note_file. Committing it there is yours; nothing was committed, branched, or pushed in the store."
printf '%s\n' "$handoff"
jq -cn --arg t "$handoff" '{kind: "handoff", text: $t}' >>"$log" || exit 2

uncommitted=false new_commit=false new_branch=false pushed=false
if [ "$posture" = holder ]; then
  [ "$(fx git -C "$h" status --porcelain)" = " M specs/demo/tasks.md" ] && uncommitted=true
  [ "$(fx git -C "$h" rev-parse HEAD)" = "$head_before" ] || new_commit=true
  [ "$(fx git -C "$h" for-each-ref --format='%(refname)' refs/heads)" = "$refs_before" ] || new_branch=true
  [ "$(fx git --git-dir="$art/holder-origin.git" for-each-ref --format='%(refname) %(objectname)')" = "$remote_before" ] || pushed=true
fi

jq -n --arg posture "$posture" --arg f "$note_file" --argjson w "$written" \
  --argjson u "$uncommitted" --argjson c "$new_commit" --argjson b "$new_branch" --argjson p "$pushed" \
  '{subject: "Task 1", decision: "halted", posture: $posture, note_file: $f, bullet_written: $w,
    uncommitted: $u, holder_new_commit: $c, holder_new_branch: $b, holder_pushed: $p,
    eval_only: true, authoritative: false, publishing_disabled: true}' >"$signoff.tmp" \
  && mv "$signoff.tmp" "$signoff" || exit 2
printf 'Execution stand-in: done.\n'
