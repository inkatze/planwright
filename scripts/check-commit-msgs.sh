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
# --marker <context> layers the branch-scoped `[pending-sign-off]` placement
# guard (Task 4, REQ-C1.1/C1.3/C1.4) on top of the conventional check, keyed
# to what is being linted:
#   subject  the emit-time --stdin path — a marker, if present, must sit at
#            the very end of the subject (`type(scope): desc [pending-sign-off]`);
#            pre-prefix, mid-subject, and duplicate placements fail.
#   title    a PR title — the marker is rejected outright (the squash-merge
#            subject must be marker-free; titles are editable so this is safe).
# The marker rule is additive: conventional format and --max-length still
# apply. The CI commit-range invocation stays marker-free (a historical
# mid-subject marker must never redden the range lint — REQ-C1.3).
#
# Usage:
#   check-commit-msgs.sh [--max-length N] [--marker subject|title] <git-range>
#                                      lint `git log <range>`
#                                      (CI passes the PR's base..head range)
#   check-commit-msgs.sh [--max-length N] [--marker subject|title] --stdin
#                                      one subject per line
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
  echo "usage: check-commit-msgs.sh [--max-length N] [--marker subject|title] (<git-range> | --stdin)" >&2
  exit 2
}

max_length=""
marker_ctx=""
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
    --marker)
      marker_ctx="${2:-}"
      case "$marker_ctx" in
        subject | title) ;; # the only two check contexts
        *) usage ;;
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

# The pending-sign-off marker, matched literally (its brackets would be a glob
# character class unquoted, so every case pattern below quotes "$marker").
marker='[pending-sign-off]'

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

  # Marker placement guard (--marker), additive to the checks above.
  case "$marker_ctx" in
    subject)
      # A marker, if present, must be the sole one and sit at the very end.
      case "$subject" in
        *"$marker"*)
          canonical=""
          case "$subject" in
            *" $marker")
              prefix="${subject%" $marker"}"
              case "$prefix" in
                *"$marker"*) ;; # a second marker earlier — not canonical
                *) canonical=1 ;;
              esac
              ;;
          esac
          if [ -z "$canonical" ]; then
            echo "check-commit-msgs: marker '$marker' must be at end of subject: $subject" >&2
            status=1
          fi
          ;;
      esac
      ;;
    title)
      # A PR title must be marker-free (it becomes the squash-merge subject).
      case "$subject" in
        *"$marker"*)
          echo "check-commit-msgs: marker '$marker' not allowed in PR title: $subject" >&2
          status=1
          ;;
      esac
      ;;
  esac
done <<EOF
$subjects
EOF

if [ "$status" -eq 0 ]; then
  echo "check-commit-msgs: $checked subject(s) conform"
fi
exit "$status"
