#!/usr/bin/env bash
# check-steps.sh — resolve every named point of doctrine/custom-steps.md in
# check mode against this repository's own configuration, and fail on the
# retired convergence knob's key.
#
# Two passes:
#   1. Every point the resolver names, wired and unwired, goes through
#      `resolve-steps.sh <point> --check --unattended`. A step that does not
#      resolve, a malformation, or a non-empty list at an unwired point fails
#      the point; the resolver's own diagnostics name the step or the point,
#      and this guard names each failing point and its exit status.
#   2. `review_sequence` fails in the core defaults anywhere, and in the
#      repo-tracked config unless it is the documented transitional line: a
#      key whose directly preceding comment block (no blank line between)
#      carries `Transitional, added YYYY-MM-DD`.
#
# Only the core and repo-tracked layers are read: the adopter overlay and the
# machine-local config are pointed at an empty scratch directory, and the
# Claude dir with them, so the result does not depend on the host running it
# and matches CI. A gitignored machine-local catalog under <repo>/.claude is
# still read, because the catalog reader takes its location from the repo
# root alone.
#
# The point vocabulary is read from the resolver's own WIRED_POINTS and
# UNWIRED_POINTS lines, so a point added there is checked here with no edit.
#
# Usage: check-steps.sh [--core <dir>] [--repo <dir>]
#   --core <dir>  the core root holding config/defaults.yml and skills/
#                 (default: the checkout holding this script)
#   --repo <dir>  the git toplevel whose .claude/ holds the repo-tracked layer
#                 (default: the checkout holding this script)
#
# Exit codes: 0 every point resolves and no stale key; 1 a point failed or a
# stale key was found; 2 usage, or an input the guard cannot read (a missing
# resolver or defaults file, an empty point vocabulary).
#
# Portable bash 3.2 / BSD tooling.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

prog=check-steps
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
if [ ! -f "$script_dir/echo-safety.sh" ] || [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "$prog: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2

die() {
  printf '%s\n' "$prog: $1" >&2
  exit 2
}

core=$(cd "$script_dir/.." && pwd) || exit 2
repo=$core
while [ $# -gt 0 ]; do
  case $1 in
    --core | --repo)
      [ $# -ge 2 ] || die "$1 needs a value"
      case $1 in
        --core) core=$2 ;;
        --repo) repo=$2 ;;
      esac
      shift 2
      ;;
    *) die "unknown argument: $(sanitize_printable "$1")" ;;
  esac
done

resolver="$script_dir/resolve-steps.sh"
[ -x "$resolver" ] || die "resolver missing or not executable: $(sanitize_printable "$resolver")"
defaults="$core/config/defaults.yml"
[ -f "$defaults" ] && [ -r "$defaults" ] || die "no readable config/defaults.yml under $(sanitize_printable "$core")"
[ -d "$repo" ] || die "no repository at $(sanitize_printable "$repo")"
core=$(cd "$core" && pwd) || exit 2
repo=$(cd "$repo" && pwd) || exit 2

wired=$(sed -n 's/^WIRED_POINTS="\(.*\)"$/\1/p' "$resolver")
unwired=$(sed -n 's/^UNWIRED_POINTS="\(.*\)"$/\1/p' "$resolver")
[ -n "$wired" ] && [ -n "$unwired" ] || die "could not read WIRED_POINTS and UNWIRED_POINTS from the resolver"

scratch=$(mktemp -d) || die "mktemp -d failed"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/adopter" "$scratch/claude" || die "cannot populate the scratch directory"

failed=0
checked=""
for point in $wired $unwired; do
  # The resolver joins a relative command target to its working directory,
  # which is the repository for a step this repository declares.
  (cd "$repo" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA \
    -u PLANWRIGHT_SKILLS_ROOT -u PLANWRIGHT_CONFIG_DEFAULTS \
    PLANWRIGHT_ROOT="$core" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_ADOPTER_OVERLAY="$scratch/adopter" \
    PLANWRIGHT_LOCAL_CONFIG="$scratch/absent.yml" \
    CLAUDE_DIR="$scratch/claude" \
    "$resolver" "$point" --check --unattended >/dev/null)
  rc=$?
  checked="$checked $point"
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$prog: point '$point' fails check mode (resolver exit $rc)" >&2
    failed=1
  fi
done

# sweep_stale <file> <label> <allow-transitional>: print one line per
# review_sequence key the file sets outside an allowed transitional line.
sweep_stale() {
  [ -f "$1" ] || return 0
  awk -v allow="$3" -v label="$2" '
    /^[[:space:]]*#/ { block = block "\n" $0; next }
    /^[[:space:]]*review_sequence[[:space:]]*:/ {
      if (allow == "1" && block ~ /Transitional, added [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) {
        printf "note: transitional review_sequence line at %s:%d\n", label, NR
      } else {
        printf "stale: %s:%d sets review_sequence, the key steps_convergence supersedes\n", label, NR
      }
    }
    { block = "" }
  ' "$1"
}

stale_out=$(
  sweep_stale "$defaults" config/defaults.yml 0
  sweep_stale "$repo/.claude/planwright.yml" .claude/planwright.yml 1
) || die "cannot read the configuration files for the stale-key sweep"
if [ -n "$stale_out" ]; then
  while IFS= read -r line; do
    case $line in
      stale:*)
        printf '%s\n' "$prog: ${line#stale: }" >&2
        failed=1
        ;;
      note:*) printf '%s\n' "$prog: ${line#note: }" ;;
    esac
  done <<EOF
$stale_out
EOF
fi

if [ "$failed" -ne 0 ]; then
  printf '%s\n' "$prog: FAILED (see the diagnostics above; doctrine/custom-steps.md owns the rules)" >&2
  exit 1
fi
printf '%s\n' "$prog: every named point resolves in check mode and no stale key is set:$checked"
exit 0
