#!/usr/bin/env bash
# check-commit-msgs.sh — conventional-commit lint (Task 2, REQ-G1.7).
#
# Subjects must match `type(scope)!: description`: a known lowercase type,
# an optional lowercase kebab/dotted scope, an optional breaking-change `!`,
# then `: ` and a non-empty description (the commitlint conventional defaults;
# types are that config's set). Merge and Revert subjects are skipped — GitHub
# builds those, and linting them would block the normal merge flow.
#
# Subject LENGTH is enforced only with --max-length N. The framework never
# rewrites history (REQ-J1.4), so a per-commit length rule would make a single
# overlong WIP subject permanently unfixable; CI instead applies --max-length
# to the PR title (the squash-merge subject, which is editable) while the
# per-commit / range path checks conventional format only.
#
# Usage:
#   check-commit-msgs.sh [--max-length N] <git-range>   lint `git log <range>`
#                                      (CI passes the PR's base..head range)
#   check-commit-msgs.sh [--max-length N] --stdin       one subject per line
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
  echo "usage: check-commit-msgs.sh [--max-length N] (<git-range> | --stdin)" >&2
  exit 2
}

max_length=""
source=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --max-length)
      max_length="${2:-}"
      case "$max_length" in
        '' | *[!0-9]*) usage ;; # require a non-empty all-digits value
      esac
      shift 2
      ;;
    *)
      [ -n "$source" ] && usage # at most one source argument
      source="$1"
      shift
      ;;
  esac
done

[ -n "$source" ] || usage

if [ "$source" = "--stdin" ]; then
  subjects="$(cat)"
else
  subjects="$(git log --no-merges --format='%s' "$source")" || exit 2
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
  elif [ -n "$max_length" ] && [ "${#subject}" -gt "$max_length" ]; then
    echo "check-commit-msgs: subject exceeds $max_length chars: $subject" >&2
    status=1
  fi
done <<EOF
$subjects
EOF

if [ "$status" -eq 0 ]; then
  echo "check-commit-msgs: $checked subject(s) conform"
fi
exit "$status"
