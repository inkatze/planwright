#!/usr/bin/env bash
# check-duties.sh — validate mission control's duty catalog and program
# configuration against this repository's core and repo-tracked layers.
#
# Fails on:
#   - the merged duties catalog not resolving, or the resolver warning about
#     any layer (a skipped line, a duplicate id without a supersede marker);
#   - a merged entry breaking the grammar config/duties.yaml documents, named
#     as <id>: <field>: <problem> (scripts/mc-duties.sh validate);
#   - the shipped default duty set naming a duty the catalog lacks, or the
#     default state-source map or home root not resolving;
#   - a configured program whose block does not validate
#     (scripts/mc-program.sh validate: repositories, spec root, home, budget,
#     a source map naming an unknown class or mode), or whose enabled list
#     names a duty the catalog lacks.
#
# Only the core and repo-tracked layers are read: the adopter overlay and the
# machine-local config are pointed at an empty scratch directory, and HOME
# with them, so a ~/ value is checked for its shape on any host. The one
# host input left is a gitignored machine-local catalog under
# <repo>/.claude/catalogs.local/, which the catalog reader locates from the
# repo root alone; one there can make a local run differ from CI.
#
# Usage: check-duties.sh [--core <dir>] [--repo <dir>]
#   --core <dir>  the core root holding config/defaults.yml and
#                 config/duties.yaml (default: the checkout holding this
#                 script)
#   --repo <dir>  the git toplevel whose .claude/ holds the repo-tracked
#                 layer (default: the checkout holding this script)
#
# Exit codes: 0 clean; 1 a finding; 2 usage, or an input the guard cannot
# read.
#
# Portable bash 3.2 / BSD tooling.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=check-duties
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
if [ ! -r "$script_dir/echo-safety.sh" ]; then
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

[ -f "$core/config/defaults.yml" ] && [ -r "$core/config/defaults.yml" ] \
  || die "no readable config/defaults.yml under $(sanitize_printable "$core")"
[ -d "$repo" ] || die "no repository at $(sanitize_printable "$repo")"
core=$(cd "$core" && pwd -P) || die "cannot enter $(sanitize_printable "$core")"
repo=$(cd "$repo" && pwd -P) || die "cannot enter $(sanitize_printable "$repo")"
toplevel=$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
  -u GIT_OBJECT_DIRECTORY -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
  git -C "$repo" rev-parse --show-toplevel 2>/dev/null) \
  && toplevel=$(cd "$toplevel" && pwd -P) && [ "$toplevel" = "$repo" ] \
  || die "not a git toplevel: $(sanitize_printable "$repo")"

scratch=$(mktemp -d) || die "mktemp -d failed"
[ -n "$scratch" ] && [ -d "$scratch" ] || die "mktemp -d produced no directory"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/adopter" "$scratch/claude" "$scratch/home" || die "cannot populate the scratch directory"

# run <script> <args...>: a sibling script over the core and repo-tracked
# layers only; stdout to the caller, stderr to $scratch/err.
run() {
  run_script=$1
  shift
  (cd "$repo" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA \
    -u PLANWRIGHT_SKILLS_ROOT -u PLANWRIGHT_CONFIG_DEFAULTS \
    -u PLANWRIGHT_REPO_ROOT_CHECKED -u PLANWRIGHT_CONFIG_STRICT_OVERLAYS \
    PLANWRIGHT_ROOT="$core" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_ADOPTER_OVERLAY="$scratch/adopter" \
    PLANWRIGHT_LOCAL_CONFIG="$scratch/absent.yml" \
    CLAUDE_DIR="$scratch/claude" \
    HOME="$scratch/home" \
    bash "$script_dir/$run_script" "$@" 2>"$scratch/err")
}

findings=0
finding() {
  printf '%s\n' "$prog: $(sanitize_printable "$1")" >&2
  findings=$((findings + 1))
}
# relay: every line the last run wrote to stderr, as findings.
relay() {
  while IFS= read -r line; do
    [ -n "$line" ] && finding "$line"
  done <"$scratch/err"
}

# The merge --explain runs, unlike a plain read of a core-only catalog, warns
# about every layer, the core seed included.
if listing=$(run mc-duties.sh list); then
  [ ! -s "$scratch/err" ] || relay
else
  relay
  finding "the duties catalog does not resolve"
fi
ids=$(printf '%s\n' "$listing" | cut -f1)

run mc-duties.sh validate || relay

# known <label> <ids>: a finding per id (one per line) the catalog lacks.
known() {
  while IFS= read -r kn_id; do
    [ -n "$kn_id" ] || continue
    case "
$ids
" in
      *"
$kn_id
"*) ;;
      *) finding "$1 enables '$kn_id', which the duties catalog lacks" ;;
    esac
  done <<KNOWN
$2
KNOWN
}

if default_duties=$(run mc-program.sh default duties); then
  known "mission_control_default_duties" "$default_duties"
else
  relay
fi
run mc-program.sh default sources >/dev/null || relay
run mc-program.sh default home >/dev/null || relay

if programs=$(run mc-program.sh list); then
  for p in $programs; do
    run mc-program.sh validate "$p" || relay
    if enabled=$(run mc-program.sh get "$p" duties); then
      known "program '$p'" "$enabled"
    fi
  done
else
  relay
fi

if [ "$findings" -ne 0 ]; then
  printf '%s\n' "$prog: $findings finding(s)" >&2
  exit 1
fi
printf '%s\n' "$prog: duties catalog and programs ok"
