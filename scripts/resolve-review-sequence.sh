#!/bin/sh
# resolve-review-sequence.sh — resolve the `review_sequence` config knob (D-6,
# REQ-D1.3) into a validated, ordered list of nestable review-skill names, one
# per line on stdout. /execute-task's convergence phase reads this and runs the
# named review skills in that order, replacing the historical hardcoded
# `/polish --nested` step. The default reproduces today's behavior, so
# out-of-the-box convergence is unchanged (REQ-D1.3, default-preserving).
#
# review_sequence is *config*, so it is resolved THROUGH config-get.sh — the
# Task 3 four-layer overlay reader (core < adopter < repo-tracked <
# machine-local, last-layer-wins). This resolver never re-implements layer
# location or merge (REQ-D1.1); it adds only the list parse, the name
# validation, and the by-layer policy that config-get cannot apply because the
# bad-name test is semantic (it depends on the set of installed skills), not
# structural.
#
# "Nestable review skill" (REQ-D1.3): a skill invocable with --nested. The
# concrete, tool-grounded predicate is that <skills-root>/<name>/SKILL.md exists
# and its `argument-hint:` frontmatter declares --nested. Today that set is
# {polish, self-review}; the predicate self-maintains as skills are added.
#
# Bad-name policy (REQ-D1.3 routes a bad name through the REQ-E1.4 by-layer
# policy). A review_sequence whose value names an unknown skill, a non-nestable
# skill, or is an empty list is *malformed*. Handled by the layer that supplied
# the winning value (config-get --explain names it):
#   - repo-tracked: hard-fail, exit 4 — a broken shared review sequence never silently
#     degrades a whole team (mirrors config-get's repo-tracked hard-fail).
#   - adopter / machine-local: warn on stderr and degrade to the CORE DEFAULT
#     (the always-valid base; the historical single-skill sequence). The degrade
#     target is the core default rather than a strict per-layer cascade because
#     config-get exposes only the merged winning value, not per-layer values; in
#     the dominant case (only core sets the knob) the core default IS the next
#     lower layer, and it is always behavior-preserving. A precise multi-overlay
#     semantic cascade would need config-get to expose per-layer reads and is a
#     possible future refinement.
#   - core: a malformed core default is a broken install — exit 5.
#
# A structurally malformed repo-tracked config FILE makes config-get itself
# exit 4 (its own by-layer hard-fail); that exit is propagated unchanged.
#
# Usage: resolve-review-sequence.sh
#   (no arguments; the key is fixed)
#
# Environment: honors every override config-get / resolve-overlay-root honor
# (PLANWRIGHT_CONFIG_DEFAULTS, PLANWRIGHT_ADOPTER_OVERLAY, PLANWRIGHT_REPO_ROOT,
# PLANWRIGHT_LOCAL_CONFIG, CLAUDE_PLUGIN_ROOT/DATA), plus:
#   PLANWRIGHT_SKILLS_ROOT  explicit skills directory holding <name>/SKILL.md
#                           (else PLANWRIGHT_ROOT/skills, CLAUDE_PLUGIN_ROOT/
#                           skills, or the script-relative ../skills)
#
# Exit: 0 names printed; 2 usage error; 4 malformed repo-tracked overlay
# (hard-fail, propagated or raised here); 5 broken install (the core default is
# itself unresolvable or invalid). Never fails opaquely.
set -u

# The [a-z] ranges below are collation-dependent; pin C so a UTF-8 locale does
# not widen them. Mirrors config-get / resolve-overlay-root.
LC_ALL=C
export LC_ALL
# A CDPATH-resolved cd would echo its destination into the script-dir command
# substitution (house pattern).
unset CDPATH

if [ "$#" -ne 0 ]; then
  echo "usage: resolve-review-sequence.sh   (no arguments; resolves the review_sequence knob)" >&2
  exit 2
fi

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
config_get="$script_dir/config-get.sh"
if [ ! -x "$config_get" ]; then
  echo "resolve-review-sequence: config reader '$config_get' is missing or not executable" >&2
  exit 5
fi

# Resolve the skills root that the nestable predicate checks SKILL.md under.
# First existing wins; an explicit override is honored even if absent (so a test
# or adopter can pin one deliberately).
skills_root=""
if [ -n "${PLANWRIGHT_SKILLS_ROOT:-}" ]; then
  skills_root="$PLANWRIGHT_SKILLS_ROOT"
else
  for root in "${PLANWRIGHT_ROOT:-}" "${CLAUDE_PLUGIN_ROOT:-}" "$script_dir/.."; do
    [ -n "$root" ] || continue
    if [ -d "$root/skills" ]; then
      skills_root="$root/skills"
      break
    fi
  done
fi

# is_nestable_review_skill <name>: 0 when <skills-root>/<name>/SKILL.md exists
# and its argument-hint frontmatter declares --nested; 1 otherwise. The name is
# charset-validated by the caller before it reaches here, so it is path-safe.
# The grep matches the literal "--nested" inside an argument-hint: line (the
# precise "declares the flag" signal — a skill that merely mentions --nested in
# prose, e.g. /execute-task naming "/polish --nested", is correctly excluded).
is_nestable_review_skill() {
  _name="$1"
  [ -n "$skills_root" ] || return 1
  _skill_md="$skills_root/$_name/SKILL.md"
  [ -f "$_skill_md" ] || return 1
  grep -Eq '^argument-hint:.*--nested' "$_skill_md" 2>/dev/null
}

# valid_name <name>: 0 when the name matches the skill-name charset
# (^[a-z][a-z0-9-]*$) AND is a nestable review skill. Charset first so a hostile
# value never reaches the filesystem predicate.
valid_name() {
  _n="$1"
  case "$_n" in
    "" | [!a-z]*) return 1 ;;
    *[!a-z0-9-]*) return 1 ;;
  esac
  is_nestable_review_skill "$_n"
}

# parse_list <raw>: print one element per line. Accepts an inline flow list
# `[a, b, c]` (surrounding brackets stripped, comma-separated) or a bare scalar
# (one element). Per element: trim surrounding whitespace and a surrounding
# quote pair. Empty elements are dropped here; an all-empty result (e.g. `[]`)
# yields no lines, which the caller treats as malformed.
parse_list() {
  _raw="$1"
  # Strip one surrounding [ ... ] pair if present (a flow list); otherwise the
  # value is a bare scalar and passes through as a single field.
  case "$_raw" in
    \[*\]) _raw=$(printf '%s' "$_raw" | sed -e 's/^\[//' -e 's/\]$//') ;;
  esac
  # Split on commas, trimming whitespace and a surrounding quote pair per field.
  # The trailing newline matters: without it `read` drops the final field (it
  # returns non-zero at EOF on an unterminated line, skipping the loop body).
  printf '%s\n' "$_raw" | tr ',' '\n' | while IFS= read -r _field; do
    _field=$(printf '%s' "$_field" \
      | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/")
    [ -n "$_field" ] && printf '%s\n' "$_field"
  done
}

# validate_sequence <raw>: print the validated names (one per line) on success
# and return 0; return 1 if the raw value is malformed (unknown/non-nestable
# name, or empty). Accumulates output and only emits it on full success, so a
# bad trailing name never leaks a partial sequence.
validate_sequence() {
  _raw="$1"
  _acc=""
  _count=0
  while IFS= read -r _name; do
    [ -n "$_name" ] || continue
    _count=$((_count + 1))
    if ! valid_name "$_name"; then
      return 1
    fi
    _acc="$_acc$_name
"
  done <<EOF
$(parse_list "$_raw")
EOF
  [ "$_count" -gt 0 ] || return 1 # an empty list is malformed
  printf '%s' "$_acc"
  return 0
}

# Read the winning value and its layer. The pinned --explain contract is a
# single "<layer>TAB<value>" line on stdout (config-get B1.6).
explain_out=""
rc=0
explain_out=$("$config_get" --explain review_sequence) || rc=$?

if [ "$rc" -eq 4 ]; then
  # config-get already hard-failed a structurally malformed repo-tracked config
  # file and named it on stderr; propagate the team-shared hard-fail unchanged.
  exit 4
fi
if [ "$rc" -eq 3 ]; then
  # review_sequence is absent in every layer. The tracked defaults ship it, so
  # this means a broken/partial install; degrade gracefully to the historical
  # single-skill sequence so convergence still runs (REQ-K1.6), warning loudly.
  echo "resolve-review-sequence: warning: review_sequence is unset in every layer (broken/partial install?); falling back to the default single 'polish' sequence" >&2
  printf 'polish\n'
  exit 0
fi
if [ "$rc" -ne 0 ]; then
  # Usage/invalid-key (exit 2) cannot occur for a literal key; surface anything
  # unexpected rather than fail opaquely.
  echo "resolve-review-sequence: unexpected config-get exit $rc resolving review_sequence" >&2
  exit "$rc"
fi

layer=${explain_out%%	*}
value=${explain_out#*	}

if validated=$(validate_sequence "$value"); then
  printf '%s\n' "$validated"
  exit 0
fi

# The winning value is malformed. Apply the REQ-E1.4 by-layer policy.
case "$layer" in
  repo-tracked)
    echo "resolve-review-sequence: repo-tracked overlay sets review_sequence to a malformed value ('$value' names an unknown or non-nestable review skill, or is empty); refusing to silently degrade a shared team review sequence" >&2
    exit 4
    ;;
  adopter | machine-local)
    echo "resolve-review-sequence: warning: the $layer overlay sets review_sequence to a malformed value ('$value' names an unknown or non-nestable review skill, or is empty); degrading to the core default sequence" >&2
    # Re-resolve with the overlay layers neutralized so config-get returns the
    # core default. config-get keeps PLANWRIGHT_CONFIG_DEFAULTS; we only blank
    # the three overlay roots. mktemp gives an empty repo root (no
    # .claude/planwright.yml → repo-tracked and derived machine-local both
    # absent); a guaranteed-absent adopter path blanks the adopter layer.
    scratch=$(mktemp -d) || {
      echo "resolve-review-sequence: could not create a scratch dir to read the core default" >&2
      exit 5
    }
    core_value=""
    crc=0
    core_value=$(
      PLANWRIGHT_ADOPTER_OVERLAY="$scratch/no-adopter" \
        PLANWRIGHT_REPO_ROOT="$scratch" \
        PLANWRIGHT_LOCAL_CONFIG="" \
        "$config_get" review_sequence
    ) || crc=$?
    rm -rf "$scratch"
    if [ "$crc" -ne 0 ]; then
      echo "resolve-review-sequence: the core default review_sequence is itself unresolvable (exit $crc) — broken install" >&2
      exit 5
    fi
    if validated=$(validate_sequence "$core_value"); then
      printf '%s\n' "$validated"
      exit 0
    fi
    echo "resolve-review-sequence: the core default review_sequence ('$core_value') is itself malformed — broken install" >&2
    exit 5
    ;;
  core)
    echo "resolve-review-sequence: the core default review_sequence ('$value') is malformed — broken install" >&2
    exit 5
    ;;
  *)
    echo "resolve-review-sequence: config-get named an unrecognized layer '$layer'" >&2
    exit 5
    ;;
esac
