#!/usr/bin/env bash
# check-commit-msgs.sh — conventional-commit lint (Task 2, REQ-G1.7).
#
# Subjects must match `type(scope)!: description`: a known lowercase type,
# an optional lowercase kebab/dotted scope, an optional breaking-change `!`,
# then `: ` and a non-empty description, at most 100 characters total (the
# commitlint conventional defaults; types are that config's set). Merge and
# Revert subjects are skipped — GitHub builds those, and linting them would
# block the normal merge flow.
#
# Usage:
#   check-commit-msgs.sh <git-range>   lint `git log <range>` subjects
#                                      (CI passes the PR's base..head range)
#   check-commit-msgs.sh --stdin       lint one subject per line from stdin
#
# Exit codes: 0 all subjects conform, 1 violation found, 2 usage error
# (including an empty range/input: an empty PR range upstream should be
# visible, not a silent pass).
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
set -u

# Pin the C locale so the character classes below mean exactly their ASCII
# range on every host (defensive; mirrors check-options-reference.sh).
LC_ALL=C
export LC_ALL

unset CDPATH

usage() {
  echo "usage: check-commit-msgs.sh <git-range> | --stdin" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage

if [ "$1" = "--stdin" ]; then
  subjects="$(cat)"
else
  subjects="$(git log --no-merges --format='%s' "$1")" || exit 2
fi

if [ -z "$subjects" ]; then
  echo "check-commit-msgs: no subjects to lint (empty range or input)" >&2
  exit 2
fi

# Held in a variable: bash 3.2 mishandles some literal EREs inside [[ =~ ]].
conventional='^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([a-z0-9.-]+\))?!?: [^ ].*$'

status=0
checked=0

while IFS= read -r subject; do
  [ -z "$subject" ] && continue
  case "$subject" in
    "Merge "* | "Revert "*) continue ;;
  esac
  checked=$((checked + 1))
  if [[ ! "$subject" =~ $conventional ]]; then
    echo "check-commit-msgs: not conventional: $subject" >&2
    status=1
  elif [ "${#subject}" -gt 100 ]; then
    echo "check-commit-msgs: subject exceeds 100 chars: $subject" >&2
    status=1
  fi
done <<EOF
$subjects
EOF

if [ "$status" -eq 0 ]; then
  echo "check-commit-msgs: $checked subject(s) conform"
fi
exit "$status"
