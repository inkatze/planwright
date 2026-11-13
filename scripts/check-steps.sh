#!/usr/bin/env bash
# check-steps.sh — resolve every named point of doctrine/custom-steps.md in
# check mode against this repository's own configuration, and fail on the
# retired convergence knob's key.
#
# Two passes:
#   1. Every point the resolver names goes through `resolve-steps.sh
#      --check --unattended`, the wired points in one run and each unwired
#      point in its own (the resolver's rule). A step that does not
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
# Claude dir with them. The one host input left is a gitignored machine-local
# catalog under <repo>/.claude/catalogs.local/, which the catalog reader
# locates from the repo root alone; one there can make a local run differ
# from CI.
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
# resolver or defaults file, a --repo that is not a git toplevel, an empty
# point vocabulary); 130 / 143 the resolver was interrupted.
#
# Portable bash 3.2 / BSD tooling.
set -u
# The point lists are word-split below; their words are names, never patterns.
set -f
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
    --core)
      [ $# -ge 2 ] || die "--core needs a value"
      core=$2
      shift 2
      ;;
    --repo)
      [ $# -ge 2 ] || die "--repo needs a value"
      repo=$2
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
core=$(cd "$core" && pwd -P) || die "cannot enter $(sanitize_printable "$core")"
repo=$(cd "$repo" && pwd -P) || die "cannot enter $(sanitize_printable "$repo")"
# The overlay resolver refuses a repo root that is not a git toplevel, which
# would otherwise surface as every point failing check mode. A git hook
# exports repository selectors, cleared here as scripts/resolve-root.sh clears
# them, so the check asks about <repo> itself.
toplevel=$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
  -u GIT_OBJECT_DIRECTORY -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
  git -C "$repo" rev-parse --show-toplevel 2>/dev/null) \
  && toplevel=$(cd "$toplevel" && pwd -P) && [ "$toplevel" = "$repo" ] \
  || die "not a git toplevel: $(sanitize_printable "$repo")"

wired=$(sed -n 's/^WIRED_POINTS="\(.*\)"$/\1/p' "$resolver")
unwired=$(sed -n 's/^UNWIRED_POINTS="\(.*\)"$/\1/p' "$resolver")
[ -n "$wired" ] && [ -n "$unwired" ] || die "could not read WIRED_POINTS and UNWIRED_POINTS from the resolver"

scratch=$(mktemp -d "${TMPDIR:-/tmp}/check-steps.XXXXXX") || die "mktemp -d failed"
[ -n "$scratch" ] && [ -d "$scratch" ] || die "mktemp -d produced no directory"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/adopter" "$scratch/claude" || die "cannot populate the scratch directory"

# resolve <args...>: the resolver over the core and repo-tracked layers only,
# every inherited variable that could select another layer or relax a read
# cleared. Run in the repository, because the resolver joins a relative
# command target to its working directory.
resolve() {
  (cd "$repo" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA \
    -u PLANWRIGHT_SKILLS_ROOT -u PLANWRIGHT_CONFIG_DEFAULTS \
    -u PLANWRIGHT_REPO_ROOT_CHECKED -u PLANWRIGHT_CONFIG_STRICT_OVERLAYS \
    PLANWRIGHT_ROOT="$core" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_ADOPTER_OVERLAY="$scratch/adopter" \
    PLANWRIGHT_LOCAL_CONFIG="$scratch/absent.yml" \
    CLAUDE_DIR="$scratch/claude" \
    "$resolver" "$@" >/dev/null)
}

failed=0
# point_failed <point> <rc>: record a failing point; an interrupted resolver
# ends the run with its signal status rather than reading as a config fault.
point_failed() {
  case $2 in 130 | 143) exit "$2" ;; esac
  printf '%s\n' "$prog: point '$1' fails check mode (resolver exit $2)" >&2
  failed=1
}

# The wired points share one resolution, as the runner resolves them; only a
# failure re-resolves them one by one, its diagnostics already printed, to
# name the failing points.
# shellcheck disable=SC2086 # the point lists are meant to word-split
resolve $wired --explain --check --unattended
batch_rc=$?
if [ "$batch_rc" -ne 0 ]; then
  case $batch_rc in 130 | 143) exit "$batch_rc" ;; esac
  for point in $wired; do
    resolve "$point" --check --unattended 2>/dev/null
    rc=$?
    [ "$rc" -eq 0 ] || point_failed "$point" "$rc"
  done
  # A shared read can fail the batch while every single run passes.
  [ "$failed" -ne 0 ] || point_failed "$(printf '%s' "$wired" | tr ' ' ',')" "$batch_rc"
fi
# An unwired point resolves only on its own.
for point in $unwired; do
  resolve "$point" --check --unattended
  rc=$?
  [ "$rc" -eq 0 ] || point_failed "$point" "$rc"
done

# sweep_stale <file> <label> <allow-transitional>: print one line per
# review_sequence key the file sets, marking the allowed transitional line.
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

stale_out=$(sweep_stale "$defaults" config/defaults.yml 0) \
  || die "cannot read config/defaults.yml for the stale-key sweep"
tracked_out=$(sweep_stale "$repo/.claude/planwright.yml" .claude/planwright.yml 1) \
  || die "cannot read .claude/planwright.yml for the stale-key sweep"
stale_out=$(printf '%s\n%s' "$stale_out" "$tracked_out")
transitional=""
while IFS= read -r line; do
  case $line in
    stale:*)
      printf '%s\n' "$prog: ${line#stale: }" >&2
      failed=1
      ;;
    note:*)
      printf '%s\n' "$prog: ${line#note: }"
      transitional=" outside a transitional line"
      ;;
  esac
done <<EOF
$stale_out
EOF

if [ "$failed" -ne 0 ]; then
  printf '%s\n' "$prog: FAILED (see the diagnostics above; doctrine/custom-steps.md owns the rules)" >&2
  exit 1
fi
printf '%s\n' "$prog: every named point resolves in check mode and no stale key is set$transitional: $wired $unwired"
exit 0
