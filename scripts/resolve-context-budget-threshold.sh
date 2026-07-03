#!/bin/sh
# resolve-context-budget-threshold.sh — resolve the `context_budget_threshold`
# config knob (D-4, REQ-C1.1) into a single validated value on stdout: a
# positive integer (a completed-step budget) or the sentinel `off`.
#
# The value is the number of completed orchestration steps after which a
# long-running tower auto-heals — hands off to a fresh tower via the
# continue-as-new pattern (doctrine/context-budget-autoheal.md) — so it never
# silently degrades from context exhaustion (REQ-C1.1). `off` disables auto-heal
# (the historical single-tower behavior). The signal is a step-count proxy
# because Claude Code exposes no supported live token-usage introspection (Task 5
# research, brief §7): the transcript JSONL is internal/unstable, and there is no
# env var, hook field, or CLI query for remaining budget. The step count is the
# portable, tower-controllable measurement scripts/context-budget-monitor.sh
# compares against this threshold.
#
# context_budget_threshold is *config*, so it is resolved THROUGH config-get.sh —
# the Task 3 four-layer overlay reader (core < adopter < repo-tracked <
# machine-local, last-layer-wins). This resolver never re-implements layer
# location or merge (REQ-D1.1); it adds only the value validation and the
# by-layer policy that config-get cannot apply because the test is semantic (the
# set of legal values), not the structural test config-get performs. It is a
# sibling of resolve-dispatch-isolation.sh and mirrors its structure and policy.
#
# Bad-value policy (REQ-E1.4 by-layer, mirroring resolve-dispatch-isolation.sh).
# A value that is neither a positive integer nor `off` is *malformed*. Handled by
# the layer that supplied the winning value (config-get --explain names it):
#   - repo-tracked: hard-fail, exit 4 — a broken shared value never silently
#     degrades a whole team.
#   - adopter / machine-local: warn on stderr and degrade to the CORE DEFAULT
#     (the always-valid, behavior-preserving base). config-get exposes only the
#     merged winning value, not per-layer values, so the degrade target is the
#     core default rather than a strict per-layer cascade; in the dominant case
#     (only core sets the knob) the core default IS the next lower layer.
#   - core: a malformed core default is a broken install — exit 5.
#
# A structurally malformed repo-tracked config FILE makes config-get itself
# exit 4 (its own by-layer hard-fail); that exit is propagated unchanged.
#
# Usage: resolve-context-budget-threshold.sh
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

# The [0-9] ranges below are collation-dependent; pin C so a UTF-8 locale does
# not widen them. Mirrors config-get / resolve-dispatch-isolation.
LC_ALL=C
export LC_ALL
# A CDPATH-resolved cd would echo its destination into the script-dir command
# substitution (house pattern).
unset CDPATH

# The safe, behavior-tie-breaking default: a conservative completed-step budget.
# Conservative because the continue-as-new handover is cheap and lossless
# (the fresh tower rebuilds from disk), so handing off early is the safe failure
# direction (R5: the unread default must be the safe one). Kept in sync with
# config/defaults.yml. Used only as the broken/partial-install fallback
# (config-get exit 3); the normal path reads the real core default via config-get.
DEFAULT_THRESHOLD=50

if [ "$#" -ne 0 ]; then
  echo "usage: resolve-context-budget-threshold.sh   (no arguments; resolves the context_budget_threshold knob)" >&2
  exit 2
fi

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
config_get="$script_dir/config-get.sh"
if [ ! -x "$config_get" ]; then
  echo "resolve-context-budget-threshold: config reader '$config_get' is missing or not executable" >&2
  exit 5
fi

# valid_value <value>: 0 when the value is a positive integer (no leading zero,
# no sign, no decimal) of at most 15 digits, or the sentinel `off`, after
# trimming surrounding whitespace; 1 otherwise. config-get already strips a
# trailing `# comment` and a surrounding quote pair; the trim here is defensive
# against surrounding whitespace so `  40  ` validates. `0` is rejected: a zero
# step budget means hand off before any work, which is nonsensical and almost
# certainly a mistake. The 15-digit width cap (max ~1e15) keeps the value well
# below the shell signed-integer range (INTMAX ~9.2e18, 19 digits) so the
# downstream `test -ge` comparison in context-budget-monitor.sh never overflows;
# 1e15 already dwarfs any real step budget, so the cap rejects only typos.
valid_value() {
  _v=$(printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  case "$_v" in
    off) return 0 ;;
    '') return 1 ;;       # empty → reject
    0 | 0*) return 1 ;;   # bare or leading-zero → reject
    *[!0-9]*) return 1 ;; # any non-digit (sign, dot, letters) → reject
  esac
  # A positive integer (first digit 1-9). Accept only within the width cap.
  [ "${#_v}" -le 15 ]
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
explain_out=$("$config_get" --explain context_budget_threshold) || rc=$?

if [ "$rc" -eq 4 ]; then
  # config-get already hard-failed a structurally malformed repo-tracked config
  # file and named it on stderr; propagate the team-shared hard-fail unchanged.
  exit 4
fi
if [ "$rc" -eq 3 ]; then
  # context_budget_threshold is absent in every layer. The tracked defaults ship
  # it, so this means a broken/partial install; degrade gracefully to the safe
  # default so the tower still self-manages (REQ-K1.6), warning loudly.
  echo "resolve-context-budget-threshold: warning: context_budget_threshold is unset in every layer (broken/partial install?); falling back to the safe default '$DEFAULT_THRESHOLD'" >&2
  printf '%s\n' "$DEFAULT_THRESHOLD"
  exit 0
fi
if [ "$rc" -ne 0 ]; then
  # Usage/invalid-key (exit 2) cannot occur for a literal key; surface anything
  # unexpected rather than fail opaquely.
  echo "resolve-context-budget-threshold: unexpected config-get exit $rc resolving context_budget_threshold" >&2
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
    echo "resolve-context-budget-threshold: repo-tracked overlay sets context_budget_threshold to a malformed value ('$value' is not a positive integer or 'off'); refusing to silently degrade a shared team value" >&2
    exit 4
    ;;
  adopter | machine-local)
    echo "resolve-context-budget-threshold: warning: the $layer overlay sets context_budget_threshold to a malformed value ('$value' is not a positive integer or 'off'); degrading to the core default" >&2
    # Re-resolve with the overlay layers neutralized so config-get returns the
    # core default. config-get keeps PLANWRIGHT_CONFIG_DEFAULTS; we only blank
    # the three overlay roots. mktemp gives an empty repo root (no
    # .claude/planwright.yml → repo-tracked and derived machine-local both
    # absent); a guaranteed-absent adopter path blanks the adopter layer.
    scratch=$(mktemp -d) || {
      echo "resolve-context-budget-threshold: could not create a scratch dir to read the core default" >&2
      exit 5
    }
    core_value=""
    crc=0
    core_value=$(
      PLANWRIGHT_ADOPTER_OVERLAY="$scratch/no-adopter" \
        PLANWRIGHT_REPO_ROOT="$scratch" \
        PLANWRIGHT_LOCAL_CONFIG="" \
        "$config_get" context_budget_threshold
    ) || crc=$?
    rm -rf "$scratch"
    if [ "$crc" -eq 3 ]; then
      # The core layer itself omits the key (a partial install where only an
      # overlay set it, and that overlay is the malformed one). Fall back to the
      # safe default so the tower still self-manages.
      echo "resolve-context-budget-threshold: warning: the core default context_budget_threshold is also unset; falling back to the safe default '$DEFAULT_THRESHOLD'" >&2
      printf '%s\n' "$DEFAULT_THRESHOLD"
      exit 0
    fi
    if [ "$crc" -ne 0 ]; then
      echo "resolve-context-budget-threshold: the core default context_budget_threshold is itself unresolvable (exit $crc) — broken install" >&2
      exit 5
    fi
    if valid_value "$core_value"; then
      emit_trimmed "$core_value"
      exit 0
    fi
    echo "resolve-context-budget-threshold: the core default context_budget_threshold ('$core_value') is itself malformed — broken install" >&2
    exit 5
    ;;
  core)
    echo "resolve-context-budget-threshold: the core default context_budget_threshold ('$value') is malformed — broken install" >&2
    exit 5
    ;;
  *)
    echo "resolve-context-budget-threshold: config-get named an unrecognized layer '$layer'" >&2
    exit 5
    ;;
esac
