#!/usr/bin/env bash
# check-commit-msgs.sh — conventional-commit lint (Task 2, REQ-G1.7).
#
# Subjects must match `type(scope)!: description`: a known lowercase type,
# an optional lowercase kebab/dotted scope, an optional breaking-change `!`,
# then `: ` and a non-empty description (the commitlint conventional defaults;
# types are that config's set). Merge and Revert subjects are skipped — GitHub
# builds those, and linting them would block the normal merge flow.
#
# WHAT IS ENFORCED WHERE follows one rule: a subject is enforced where it can
# still be corrected, and reported where it cannot.
#
#   --stdin  the PR title, and the commit-msg hook's write-time screen. Both
#            are editable at the moment they are checked, so a violation FAILS.
#            The PR title is the squash-merge subject, and squash is this
#            repo's only merge method, so it is the subject that reaches main.
#   <range>  commits that already exist. The framework never rewrites history
#            (REQ-J1.4), so a violation here has no remedy short of the one
#            thing the framework forbids: it is REPORTED and does not fail.
#
# Subject LENGTH already worked this way. Conventional FORMAT did not, and the
# asymmetry had no reasoning behind it — a single `wip:` subject reddened a
# pull request permanently, with a history rewrite as the only exit. Both
# rules now sit on the same side of the same line.
#
# Nothing is lost by reporting rather than failing on the range: the hook
# screens the subject at write time, where it is one `--amend` away from
# correct, and the PR title carries the only subject that lands on main.
#
# --marker title layers a sign-off guard on top of the conventional check for
# a PR title, which becomes the squash-merge subject: the legacy
# `[pending-sign-off]` bracket and a `Planwright-Sign-Off` or
# `Planwright-Sign-Off-Rejected` trailer line (any case, as git matches trailer
# keys) are rejected anywhere in it, a Merge or Revert title included. Titles
# are editable, so failing is safe. The rule is additive: conventional format
# and --max-length still apply. The CI commit-range invocation stays
# marker-free (a historical mid-subject marker must never redden the range
# lint). The former
# `--marker subject` context is retired: a sign-off rides in a trailer
# (doctrine/gate-wiring.md), so there is no subject placement to check. Only
# the title context remains, for one release.
#
# Usage:
#   check-commit-msgs.sh [--max-length N] <git-range>
#                                      lint `git log <range>`
#                                      (CI passes the PR's base..head range)
#   check-commit-msgs.sh [--max-length N] [--marker title] --stdin
#                                      one subject per line
# --marker is an emit-time guard and requires --stdin: pairing it with a
# <git-range> is a usage error (a range-time marker check would recreate the
# unfixable-red trap REQ-C1.3 forbids).
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
  echo "usage: check-commit-msgs.sh [--max-length N] (<git-range> | [--marker title] --stdin)" >&2
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
        title) ;;
        subject)
          echo "check-commit-msgs: --marker subject is retired; stamp a Planwright-Sign-Off trailer through planwright-commit-trailers.sh instead of a subject marker" >&2
          usage
          ;;
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

# --marker is an emit-time guard, meaningful only against --stdin input. Pairing
# it with a git range is a usage error: a range-time marker check would scan
# history and recreate the unfixable-red trap REQ-C1.3 forbids (design D-3).
if [ -n "$marker_ctx" ] && [ "$source" != "--stdin" ]; then
  usage
fi

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
trailer_line='planwright-sign-off(-rejected)?[[:space:]]*:'

status=0
checked=0
warned=0

while IFS= read -r subject; do
  [ -z "$subject" ] && continue

  # Sign-off guard (--marker title), additive to the checks below. It runs
  # before the Merge/Revert skip: a reverted marked commit's GitHub-built
  # title still becomes the squash subject.
  if [ "$marker_ctx" = title ]; then
    case "$subject" in
      *"$marker"*)
        echo "check-commit-msgs: marker '$marker' not allowed in PR title: $subject" >&2
        status=1
        ;;
    esac
    if printf '%s\n' "$subject" | grep -Eiq "$trailer_line"; then
      echo "check-commit-msgs: a Planwright-Sign-Off trailer line is not allowed in PR title: $subject" >&2
      status=1
    fi
  fi

  case "$subject" in
    "Merge "* | "Revert "*) continue ;;
  esac
  checked=$((checked + 1))
  if [[ ! "$subject" =~ $conventional ]]; then
    # Frozen history reports; an editable subject fails. See the header.
    if [ "$source" = "--stdin" ]; then
      echo "check-commit-msgs: not conventional: $subject" >&2
      status=1
    else
      echo "check-commit-msgs: warning: not conventional (already committed, not rewritable): $subject" >&2
      warned=$((warned + 1))
    fi
  elif [ -n "$max_length" ] && [ "${#subject}" -gt "$max_length" ]; then
    echo "check-commit-msgs: subject exceeds $max_length chars: $subject" >&2
    status=1
  fi
done <<EOF
$subjects
EOF

if [ "$status" -eq 0 ]; then
  if [ "$warned" -gt 0 ]; then
    echo "check-commit-msgs: $checked subject(s) checked, $warned non-conventional (reported, not enforced: already committed)"
  else
    echo "check-commit-msgs: $checked subject(s) conform"
  fi
fi
exit "$status"
