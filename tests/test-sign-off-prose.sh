#!/bin/bash
# The sign-off prose in the gate-wired skills (/polish, /self-review,
# /execute-task): each body carries the approval statement, the
# apply-then-review statement for attended and unattended runs alike, and the
# handoff instruction printing trailered SHAs with the trailer-aware log
# command; no skill body carries the retired subject suffix. The statements are
# fixed strings so the three bodies cannot drift apart.
#
# Verifies human-gates REQ-B1.5, REQ-B1.7, REQ-B1.8 (the CI grep halves).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
root="$here/.."
failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

APPROVAL="the approval act, never the ready flip, signs off pending-sign-off items; reject one before it by its printed recipe"
APPLY="attended or unattended, a needs-sign-off fix is committed on the branch, never asked about first"
# shellcheck disable=SC2016 # literal backticks and format placeholders
HANDOFF='print each trailered commit'"'"'s SHA and `git log --format='"'"'%h %(trailers:key=Planwright-Sign-Off,key=Planwright-Sign-Off-Rejected,separator=%x20) %s'"'"' <base>..HEAD`'

# flat <file>: the file with every run of whitespace collapsed to one space,
# compared lowercased, so a statement matches however the markdown wraps it or
# whether a sentence opens with it.
flat() { tr '\n\t' '  ' <"$1" | tr -s ' '; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

for skill in polish self-review execute-task; do
  f="$root/skills/$skill/SKILL.md"
  [ -f "$f" ] || {
    fail "$skill: SKILL.md missing"
    continue
  }
  body=$(flat "$f")
  lbody=$(lower "$body")
  for pair in "approval statement|$APPROVAL" "apply-then-review statement|$APPLY" "handoff SHA instruction|$HANDOFF"; do
    name=${pair%%|*}
    text=$(lower "${pair#*|}")
    case $lbody in
      *"$text"*) echo "ok: $skill carries the $name" ;;
      *) fail "$skill: the $name is missing" ;;
    esac
  done
done

# The log command the handoff prints really is trailer-aware: over a fixture
# range it shows the sign-off and rejected trailers `--oneline` hides.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null HOME="$tmp"
export GIT_AUTHOR_NAME=T GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=T GIT_COMMITTER_EMAIL=t@example.com
git init -q -b main "$tmp/r"
git -C "$tmp/r" config commit.gpgsign false
git -C "$tmp/r" commit -q --allow-empty -m 'chore: root'
git -C "$tmp/r" checkout -q -b task
printf 'fix: shared\n\nPlanwright-Sign-Off: PS-1\nPlanwright-Sign-Off: PS-2\n' | git -C "$tmp/r" commit -q --allow-empty -F -
printf 'fix: undo part\n\nPlanwright-Sign-Off-Rejected: PS-1\n' | git -C "$tmp/r" commit -q --allow-empty -F -
fmt=${HANDOFF#*--format=\'}
fmt=${fmt%%\'*}
out=$(git -C "$tmp/r" log --format="$fmt" main..HEAD)
case $out in
  *"Planwright-Sign-Off-Rejected: PS-1 fix: undo part"*"Planwright-Sign-Off: PS-1 Planwright-Sign-Off: PS-2 fix: shared"*)
    echo "ok: the handoff log command shows the trailers --oneline hides"
    ;;
  *) fail "the handoff log command does not show the trailers [$out]" ;;
esac

# No skill body carries the retired subject suffix.
hits=$(grep -l -F '[pending-sign-off]' "$root"/skills/*/SKILL.md 2>/dev/null)
if [ -z "$hits" ]; then
  echo "ok: no skill body carries the retired subject suffix"
else
  fail "the retired subject suffix survives in: $hits"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all sign-off prose tests passed"
