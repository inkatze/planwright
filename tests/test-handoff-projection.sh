#!/bin/bash
# Tests for the review-loop handoff family's turn/artifact split
# (operator-dialogue Task 9; D-15, D-16; REQ-J1.1, REQ-J1.2, REQ-J1.5).
#
# The handoff family is `doctrine/gate-wiring.md`'s loop-end rule plus the
# per-skill instantiations in `/self-review`, `/polish`, `/execute-task` and
# `/builder`. Its contract: the full audit record is artifact-side, and the
# turn carries a projection of it (counts plus the residue, itself projected).
#
# This is a PROSE TETHER, in the shape tests/test-allocation-docs.sh uses. The
# rule lives in instructions an agent reads, so nothing else can hold it: the
# failure it guards against is a repaired surface losing its declared side in a
# later edit, silently, and every surface below has already been through that
# once. The behavioral assertions that drive real runs are on-demand
# (test-spec REQ-J1.2, the behavioral lane) and never in CI, so the artifacts
# the rule mandates — the gitignore entry, the cache-file path, the declared
# side at each emit mandate — are what CI can honestly hold.
#
# What is covered here:
#   - gate-wiring's loop-end handoff declares both sides and names the residue
#     as the pending sign-offs and open forks;
#   - /polish's worktree-local cache artifact exists as a rule: the path is
#     named in the skill, and `.gitignore` actually ignores it (checked through
#     `git check-ignore`, not a substring, so a reworded comment cannot pass);
#   - each REPAIRED surface names its own turn-side projection rather than
#     inheriting the shared doc silently. `/execute-task` is deliberately
#     absent from that list: its repair does not fit the instruction budget
#     (its SKILL.md sits exactly at the margin its declared exception was
#     granted at, so one added word fails check:instructions), and it is
#     escalated rather than done. Add its assertion with its repair.
#     The surfaces mark the declared side
#     as `**turn**` / `**artifact-side**`, and the assertions below hold them
#     to that markup: it is what makes a side visible to a reader skimming the
#     instructions, and an unmarked mention is what the repair replaced.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-handoff-projection.sh
#
# `set -u` without `-e`: this suite accumulates failures and reports them all.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd) || {
  echo "FAIL: cannot resolve the script directory" >&2
  exit 1
}
root="$here/.."

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1" >&2
  fails=$((fails + 1))
}

# Assert that a file's contents match an extended regular expression. The file
# is unwrapped to one line first, for the reason the section extraction below
# records: a phrase the rule mandates straddles the 79-column wrap often
# enough that a per-line match would tether nothing.
# $1 label, $2 path, $3 ERE
doc_matches() {
  if [ ! -r "$2" ]; then
    fail "$1: $2 is not readable"
    return
  fi
  if tr '\n' ' ' <"$2" | tr -s ' ' | grep -Eqi "$3"; then
    pass "$1"
  else
    fail "$1: $2 does not match /$3/"
  fi
}

# Extract gate-wiring's "Loop-end handoff" section so the assertions below
# cannot be satisfied by wording elsewhere in the doc.
GW="$root/doctrine/gate-wiring.md"
# Unwrapped to one line first: the source wraps at column 79, so a two-word
# term the rule names can straddle a line break and defeat a literal match.
section=$(awk '/^## Loop-end handoff/{f=1;next} /^## /{f=0} f' "$GW" 2>/dev/null \
  | tr '\n' ' ' | tr -s ' ')
if [ -z "$section" ]; then
  fail "gate-wiring: the Loop-end handoff section is absent or empty"
else
  case "$section" in
    *artifact-side*) pass "gate-wiring: the full record is declared artifact-side" ;;
    *) fail "gate-wiring: the loop-end handoff does not declare the artifact side" ;;
  esac
  case "$section" in
    *turn*projection*) pass "gate-wiring: the turn gets a declared projection" ;;
    *) fail "gate-wiring: the loop-end handoff does not declare the turn side" ;;
  esac
  case "$section" in
    *"pending sign-off"*) pass "gate-wiring: the projected residue names the pending sign-offs" ;;
    *) fail "gate-wiring: the projected residue does not name pending sign-offs" ;;
  esac
  case "$section" in
    *fork*) pass "gate-wiring: the projected residue names the open forks" ;;
    *) fail "gate-wiring: the projected residue does not name the open forks" ;;
  esac
fi

# /polish's cache artifact (D-16). The path is a rule in the skill, and the
# repo's denylist .gitignore must actually ignore it — asserted through git so
# a stale or misplaced pattern fails here rather than at the first polish run.
doc_matches "polish: the audit record's path is named" \
  "$root/skills/polish/SKILL.md" '\.claude/polish-audit\.md'

if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$root" check-ignore -q .claude/polish-audit.md; then
    pass "gitignore: .claude/polish-audit.md is ignored"
  else
    fail "gitignore: .claude/polish-audit.md is not ignored by the repo's denylist"
  fi
else
  printf 'skip %s\n' "gitignore: not a git checkout"
fi

# Per-skill instantiation: each repaired surface states its own turn side
# rather than leaving the shared doc to carry it.
doc_matches "self-review: states its own turn-side projection" \
  "$root/skills/self-review/SKILL.md" '\*\*turn\*\*.*projection'
doc_matches "polish: states its own turn-side projection" \
  "$root/skills/polish/SKILL.md" '\*\*turn\*\*.*projection|projection.*\*\*turn\*\*'
doc_matches "builder: states its own turn-side projection" \
  "$root/skills/builder/SKILL.md" '\*\*turn\*\*.*projection|projection.*\*\*turn\*\*'

if [ "$fails" -eq 0 ]; then
  printf '\nPASS: handoff projection tethers hold\n'
  exit 0
fi
printf '\nFAIL: %d handoff projection tether(s) failed\n' "$fails" >&2
exit 1
