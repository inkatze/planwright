#!/usr/bin/env bash
# Contract-consistency checker for pair-flow skill files.
# Greps skill files for cross-file invariants that must stay aligned.
# Runs as a lefthook pre-commit job filtered to roles/osx/files/claude/commands/*.md.
set -euo pipefail

CMDS="roles/osx/files/claude/commands"
errors=0

err() { echo "ERROR: $1"; errors=$((errors + 1)); }

# D-32: branch naming pattern (pair-flow/<spec>/task-<ids>)
for f in execute-task.md polish.md panel-pairing.md resume.md orchestrate.md; do
  [ -f "$CMDS/$f" ] && ! grep -q 'pair-flow/.*task-' "$CMDS/$f" \
    && err "$f missing D-32 branch naming pattern"
done

# Four-bucket presentation contract (Finding Categorization)
for f in polish.md panel-pairing.md peer-review.md; do
  [ -f "$CMDS/$f" ] && ! grep -qE 'four.table|four bucket|four:.*Auto-applicable' "$CMDS/$f" \
    && err "$f missing four-bucket presentation reference"
done

# --nested flag bidirectional reference
for f in polish.md execute-task.md; do
  [ -f "$CMDS/$f" ] && ! grep -q '\-\-nested' "$CMDS/$f" \
    && err "$f missing --nested flag reference"
done

# pair-flow-config.sh repo-class in skills that use it
for f in execute-task.md polish.md panel-pairing.md peer-review.md spec-kickoff.md; do
  [ -f "$CMDS/$f" ] && ! grep -q 'pair-flow-config\.sh' "$CMDS/$f" \
    && err "$f missing pair-flow-config.sh reference"
done

# spec-validate.sh in skills that gate on it
for f in orchestrate.md spec-kickoff.md spec-draft.md; do
  [ -f "$CMDS/$f" ] && ! grep -q 'spec-validate\.sh' "$CMDS/$f" \
    && err "$f missing spec-validate.sh reference"
done

# D-21: never-auto-merge / always-draft invariant in execution/orchestration skills
for f in execute-task.md orchestrate.md polish.md; do
  [ -f "$CMDS/$f" ] && ! grep -qiE 'never.*merge|always.*draft|draft PR|--draft' "$CMDS/$f" \
    && err "$f missing D-21 never-auto-merge / always-draft invariant"
done

# D-33: Active-status gate in execution skills
for f in execute-task.md orchestrate.md; do
  [ -f "$CMDS/$f" ] && ! grep -qE 'not.*Active|Status.*Active|Active.*status' "$CMDS/$f" \
    && err "$f missing D-33 Active-status gate"
done

# D-36: kickoff brief gate in execution skills
for f in execute-task.md orchestrate.md; do
  [ -f "$CMDS/$f" ] && ! grep -q 'kickoff.brief' "$CMDS/$f" \
    && err "$f missing D-36 kickoff brief gate reference"
done

if [ "$errors" -gt 0 ]; then
  echo ""
  echo "skill-contracts: $errors invariant(s) broken"
  exit 1
fi
echo "skill-contracts: all invariants hold"
