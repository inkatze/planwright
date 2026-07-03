#!/bin/sh
# resolve-dispatch-isolation.sh — resolve the `dispatch_isolation` config knob
# (D-5, REQ-C1.3) into a single validated value on stdout: `per-step` or
# `per-unit`. /execute-task's step sequencing reads this to decide whether each
# step (implementation, then each configured review_sequence skill) runs in its
# own fresh /resume-seeded session (`per-step`, the assigned-decision default)
# or in one session for the whole unit (`per-unit`, today's behavior).
#
# dispatch_isolation is *config*, so it is resolved THROUGH config-get.sh — the
# Task 3 four-layer overlay reader (core < adopter < repo-tracked <
# machine-local, last-layer-wins). This resolver never re-implements layer
# location or merge (REQ-D1.1); it adds only the enum validation and the
# by-layer policy that config-get cannot apply because the enum test is semantic
# (the set of legal values), not the structural test config-get performs.
#
# Bad-value policy (REQ-E1.4 by-layer, mirroring resolve-review-sequence.sh). A
# dispatch_isolation whose value is neither `per-step` nor `per-unit` is
# *malformed*. Handled by the layer that supplied the winning value (config-get
# --explain names it):
#   - repo-tracked: hard-fail, exit 4 — a broken shared value never silently
#     degrades a whole team (mirrors config-get's repo-tracked hard-fail).
#   - adopter / machine-local: warn on stderr and degrade to the CORE DEFAULT
#     (the always-valid base). The degrade target is the core default rather
#     than a strict per-layer cascade because config-get exposes only the merged
#     winning value, not per-layer values; in the dominant case (only core sets
#     the knob) the core default IS the next lower layer, and it is always the
#     safe/behavior-preserving base. A precise multi-overlay semantic cascade
#     would need config-get to expose per-layer reads and is a possible future
#     refinement.
#   - core: a malformed core default is a broken install — exit 5.
#
# A structurally malformed repo-tracked config FILE makes config-get itself
# exit 4 (its own by-layer hard-fail); that exit is propagated unchanged.
#
# Usage: resolve-dispatch-isolation.sh
#   (no arguments; the key is fixed)
#
# Environment: honors every override config-get / resolve-overlay-root honor
# (PLANWRIGHT_CONFIG_DEFAULTS, PLANWRIGHT_ADOPTER_OVERLAY, PLANWRIGHT_REPO_ROOT,
# PLANWRIGHT_LOCAL_CONFIG, CLAUDE_PLUGIN_ROOT/DATA).
#
# Exit: 0 value printed; 2 usage error; 4 malformed repo-tracked overlay
# (hard-fail, propagated or raised here); 5 broken install (the core default is
# itself unresolvable or invalid). Never fails opaquely.
set -u

# The [a-z] ranges below are collation-dependent; pin C so a UTF-8 locale does
# not widen them. Mirrors config-get / resolve-review-sequence.
LC_ALL=C
export LC_ALL
# A CDPATH-resolved cd would echo its destination into the script-dir command
# substitution (house pattern).
unset CDPATH

# The safe, behavior-tie-breaking default: the assigned-decision value the
# shipped core defaults carry. Used only as the broken/partial-install fallback
# (config-get exit 3) so /execute-task still runs; the normal path reads the
# real core default via config-get.
DEFAULT_ISOLATION=per-step

if [ "$#" -ne 0 ]; then
  echo "usage: resolve-dispatch-isolation.sh   (no arguments; resolves the dispatch_isolation knob)" >&2
  exit 2
fi

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
config_get="$script_dir/config-get.sh"
if [ ! -x "$config_get" ]; then
  echo "resolve-dispatch-isolation: config reader '$config_get' is missing or not executable" >&2
  exit 5
fi

# valid_value <value>: 0 when the value is one of the legal enum members after
# trimming surrounding whitespace; 1 otherwise. config-get already strips a
# trailing `# comment` and a surrounding quote pair; the trim here is defensive
# against surrounding whitespace so `  per-unit  ` validates.
valid_value() {
  _v=$(printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  case "$_v" in
    per-step | per-unit) return 0 ;;
    *) return 1 ;;
  esac
}

# emit_trimmed <value>: print the value trimmed of surrounding whitespace, with
# a single trailing newline (the emitter contract every sibling honors).
emit_trimmed() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
  printf '\n'
}

# Read the winning value and its layer. The pinned --explain contract is a
# single "<layer>TAB<value>" line on stdout (config-get B1.6).
explain_out=""
rc=0
explain_out=$("$config_get" --explain dispatch_isolation) || rc=$?

if [ "$rc" -eq 4 ]; then
  # config-get already hard-failed a structurally malformed repo-tracked config
  # file and named it on stderr; propagate the team-shared hard-fail unchanged.
  exit 4
fi
if [ "$rc" -eq 3 ]; then
  # dispatch_isolation is absent in every layer. The tracked defaults ship it,
  # so this means a broken/partial install; degrade gracefully to the safe
  # default so /execute-task still runs (REQ-K1.6), warning loudly.
  echo "resolve-dispatch-isolation: warning: dispatch_isolation is unset in every layer (broken/partial install?); falling back to the safe default '$DEFAULT_ISOLATION'" >&2
  printf '%s\n' "$DEFAULT_ISOLATION"
  exit 0
fi
if [ "$rc" -ne 0 ]; then
  # Usage/invalid-key (exit 2) cannot occur for a literal key; surface anything
  # unexpected rather than fail opaquely.
  echo "resolve-dispatch-isolation: unexpected config-get exit $rc resolving dispatch_isolation" >&2
  exit "$rc"
fi

layer=${explain_out%%	*}
value=${explain_out#*	}

if valid_value "$value"; then
  emit_trimmed "$value"
  exit 0
fi

# The winning value is malformed. Apply the REQ-E1.4 by-layer policy.
case "$layer" in
  repo-tracked)
    echo "resolve-dispatch-isolation: repo-tracked overlay sets dispatch_isolation to a malformed value ('$value' is not 'per-step' or 'per-unit'); refusing to silently degrade a shared team value" >&2
    exit 4
    ;;
  adopter | machine-local)
    echo "resolve-dispatch-isolation: warning: the $layer overlay sets dispatch_isolation to a malformed value ('$value' is not 'per-step' or 'per-unit'); degrading to the core default" >&2
    # Re-resolve with the overlay layers neutralized so config-get returns the
    # core default. config-get keeps PLANWRIGHT_CONFIG_DEFAULTS; we only blank
    # the three overlay roots. mktemp gives an empty repo root (no
    # .claude/planwright.yml → repo-tracked and derived machine-local both
    # absent); a guaranteed-absent adopter path blanks the adopter layer.
    scratch=$(mktemp -d) || {
      echo "resolve-dispatch-isolation: could not create a scratch dir to read the core default" >&2
      exit 5
    }
    core_value=""
    crc=0
    core_value=$(
      PLANWRIGHT_ADOPTER_OVERLAY="$scratch/no-adopter" \
        PLANWRIGHT_REPO_ROOT="$scratch" \
        PLANWRIGHT_LOCAL_CONFIG="" \
        "$config_get" dispatch_isolation
    ) || crc=$?
    rm -rf "$scratch"
    if [ "$crc" -eq 3 ]; then
      # The core layer itself omits the key (a partial install where only an
      # overlay set it, and that overlay is the malformed one). Fall back to the
      # safe default so /execute-task still runs.
      echo "resolve-dispatch-isolation: warning: the core default dispatch_isolation is also unset; falling back to the safe default '$DEFAULT_ISOLATION'" >&2
      printf '%s\n' "$DEFAULT_ISOLATION"
      exit 0
    fi
    if [ "$crc" -ne 0 ]; then
      echo "resolve-dispatch-isolation: the core default dispatch_isolation is itself unresolvable (exit $crc) — broken install" >&2
      exit 5
    fi
    if valid_value "$core_value"; then
      emit_trimmed "$core_value"
      exit 0
    fi
    echo "resolve-dispatch-isolation: the core default dispatch_isolation ('$core_value') is itself malformed — broken install" >&2
    exit 5
    ;;
  core)
    echo "resolve-dispatch-isolation: the core default dispatch_isolation ('$value') is malformed — broken install" >&2
    exit 5
    ;;
  *)
    echo "resolve-dispatch-isolation: config-get named an unrecognized layer '$layer'" >&2
    exit 5
    ;;
esac
