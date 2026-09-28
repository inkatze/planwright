#!/bin/sh
# resolve-policy-knob.sh — resolve one human-gates policy knob through the
# shared resolver with its legal values and its strict degrade target, so every
# reader (the policy guard, the ready-flip and merge helpers, the base sync)
# gets the same answer from one table.
#
# Usage: resolve-policy-knob.sh <knob>
#
# A gate knob's shipped default can be its permissive value, so a malformed
# adopter or machine-local value (or overlay file) degrades to the strict
# target named below, never to the core default; a malformed repo-tracked value
# exits 4 and a broken install 5, and a reader treats any non-zero exit as a
# refusal of the act. `ready_flip_ci_wait` is a bound rather than a gate: a
# malformed value degrades to the core default and a malformed file is
# skipped, as for any knob. `protected_branches` degrades nowhere: a
# malformed value in any overlay is a read failure, and on success the output
# is the whole protected set, the core floor first, so no reader can drop the
# floor by forgetting to add it.
#
# Exit: 0 value printed; 2 usage error; 4 malformed value (repo-tracked, or any
# overlay for protected_branches); 5 broken install.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

# The protected floor no layer can remove.
PROTECTED_FLOOR='main master planwright/*/spec'

usage() {
  echo "usage: resolve-policy-knob.sh <knob>" >&2
}

[ "$#" -eq 1 ] || {
  usage
  exit 2
}
knob=$1
rck="$script_dir/resolve-config-knob.sh"
[ -r "$rck" ] || {
  echo "resolve-policy-knob: the shared resolver '$rck' is missing — broken install" >&2
  exit 5
}

case "$knob" in
  ready_flip_policy)
    exec /bin/sh "$rck" --key "$knob" --type enum --values 'human unit-owner' \
      --fallback human --degrade human
    ;;
  ready_flip_ci_wait)
    exec /bin/sh "$rck" --key "$knob" --type duration --fallback 10m
    ;;
  merge_policy)
    exec /bin/sh "$rck" --key "$knob" --type enum --values 'human on-approval policy-class' \
      --fallback human --degrade human
    ;;
  merge_class_max_lines)
    exec /bin/sh "$rck" --key "$knob" --type nonnegint --fallback 0 --degrade 0
    ;;
  merge_class_exclude_paths)
    exec /bin/sh "$rck" --key "$knob" --type globlist --fallback '*' --degrade '*'
    ;;
  merge_class_strategy)
    exec /bin/sh "$rck" --key "$knob" --type enum --values 'sole-allowed squash merge rebase' \
      --fallback sole-allowed --degrade sole-allowed
    ;;
  worker_base_merge | unpushed_rewrite)
    exec /bin/sh "$rck" --key "$knob" --type enum --values 'allow deny' \
      --fallback deny --degrade deny
    ;;
  worker_merge_conflict_policy)
    exec /bin/sh "$rck" --key "$knob" --type enum --values 'halt resolve' \
      --fallback halt --degrade halt
    ;;
  protected_branches)
    additions=$(/bin/sh "$rck" --key "$knob" --type globlist --no-degrade) || exit $?
    # An entry that no branch name can match (git refuses the shape, or `**`,
    # which matches one segment here) is malformed rather than silently inert.
    for entry in $additions; do
      entry=${entry#refs/heads/}
      case "$entry" in
        "" | /* | */ | *//* | *..* | *\*\** | .* | */.* | *.lock | *.lock/* | *. | HEAD)
          printf '%s\n' "resolve-policy-knob: protected_branches entry '$entry' can never match a branch; refusing" >&2
          exit 4
          ;;
      esac
    done
    # Word-split on purpose (set -f is on) to normalize the separators.
    # shellcheck disable=SC2086
    set -- $PROTECTED_FLOOR $additions
    printf '%s\n' "$*"
    ;;
  *)
    printf '%s\n' "resolve-policy-knob: unknown knob '$(sanitize_printable "$knob" "(unprintable knob)")'" >&2
    usage
    exit 2
    ;;
esac
