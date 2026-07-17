#!/bin/sh
# resolve-config-knob.sh — the SHARED config-knob resolver for the
# fleet-autonomy bundle's knobs (Task 1: D-22, REQ-G1.5): resolve one config
# key through the four-layer overlay into a single validated value on stdout,
# with the same malformed-value-by-layer policy `review_sequence` already has
# (REQ-E1.4) — implemented ONCE here instead of copied into a per-knob
# resolver for every knob the bundle introduces (the kill-switch today;
# Task 2's flailing threshold, Task 3/4's sweep cadences, and the rest as they
# land).
#
# A knob is *config*, so it resolves THROUGH config-get.sh — the four-layer
# overlay reader (core < adopter < repo-tracked < machine-local,
# last-layer-wins). This helper never re-implements layer location or merge
# (customization-overlay REQ-D1.1); it adds only the semantic validation that
# config-get cannot apply (the legal-value test is key-specific) and the
# by-layer policy, mirroring resolve-dispatch-isolation.sh /
# resolve-review-sequence.sh:
#   - repo-tracked malformed value (or structurally malformed file, which
#     config-get itself hard-fails): exit 4 — a broken shared value never
#     silently degrades a whole team;
#   - adopter / machine-local malformed value: warn on stderr and degrade to
#     the CORE DEFAULT (re-resolved with the overlay layers neutralized; the
#     documented degrade target, not a strict per-layer cascade, because
#     config-get exposes only the merged winning value);
#   - core default malformed: broken install, exit 5;
#   - key absent in every layer, or absent from core after an overlay
#     degrade: warn and emit the caller's --fallback (the caller-declared safe
#     value), exit 0 — graceful degradation so the calling mechanism still
#     runs (REQ-K1.6).
#
# Usage:
#   resolve-config-knob.sh --key <key> --type enum --values '<v1> <v2> ...' --fallback <value>
#   resolve-config-knob.sh --key <key> --type posint --fallback <value>
#
#   <key>      matches ^[a-z][a-z0-9_]*$ (config-get's queryable charset),
#              validated before it is ever interpolated (REQ-D1.6).
#   enum       the value must equal one of the space-separated --values
#              members literally (each member [A-Za-z0-9._-], <=64 chars).
#   posint     the value must be a positive integer, no leading zero, at most
#              15 digits (the overflow guard resolve-context-budget-threshold
#              uses; a real knob value is orders of magnitude smaller).
#   --fallback is required and must itself validate against the type: it is
#              the safe value emitted when the key cannot be resolved from any
#              layer, so an invalid fallback is a caller bug (exit 2).
#
# Environment: honors every override config-get / resolve-overlay-root honor
# (PLANWRIGHT_CONFIG_DEFAULTS, PLANWRIGHT_ADOPTER_OVERLAY, PLANWRIGHT_REPO_ROOT,
# PLANWRIGHT_LOCAL_CONFIG, CLAUDE_PLUGIN_ROOT/DATA).
#
# Exit: 0 value printed; 2 usage error; 4 malformed repo-tracked overlay
# (hard-fail, propagated or raised here); 5 broken install (the core default
# is itself unresolvable or invalid). Never fails opaquely.
#
# Pathname expansion is disabled (set -f): --values is word-split into
# members, and a stray glob metacharacter must not expand against the CWD
# before the member charset check refuses it.
set -uf

# The [a-z] ranges below are collation-dependent; pin C so a UTF-8 locale does
# not widen them. Mirrors config-get and the per-knob resolver siblings.
LC_ALL=C
export LC_ALL
# A CDPATH-resolved cd would echo its destination into the script-dir command
# substitution (house pattern).
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# The canonical echo-discipline sanitizer (doctrine/security-posture.md):
# refused caller argv and config-file values are stripped of control bytes
# before they reach a diagnostic, so a hostile --values/--fallback/--type or
# an escape-bearing overlay value cannot drive the terminal. The per-knob
# resolver siblings predate this and take no caller argv; this resolver is
# the shared entry point for arbitrary keys and value sets, so it sources
# the sanitizer like the fleet command scripts do.
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

usage() {
  echo "usage: resolve-config-knob.sh --key <key> --type <enum|posint> [--values '<v1> <v2> ...'] --fallback <value>" >&2
}

key=""
ktype=""
kvalues=""
fallback=""
fallback_set=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --key)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      key=$2
      shift 2
      ;;
    --type)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      ktype=$2
      shift 2
      ;;
    --values)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      kvalues=$2
      shift 2
      ;;
    --fallback)
      [ "$#" -ge 2 ] || {
        usage
        exit 2
      }
      fallback=$2
      fallback_set=1
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

# Key charset: config-get's own queryable charset, checked here too so a bad
# key is a clean caller-bug refusal before any resolution runs.
case "$key" in
  "")
    usage
    exit 2
    ;;
  [a-z]*) ;;
  *)
    echo "resolve-config-knob: invalid key '$(sanitize_printable "$key" "(unprintable key)")' (must match ^[a-z][a-z0-9_]*\$)" >&2
    exit 2
    ;;
esac
case "$key" in
  *[!a-z0-9_]*)
    echo "resolve-config-knob: invalid key '$(sanitize_printable "$key" "(unprintable key)")' (must match ^[a-z][a-z0-9_]*\$)" >&2
    exit 2
    ;;
esac

case "$ktype" in
  enum)
    if [ -z "$kvalues" ]; then
      echo "resolve-config-knob: --type enum requires --values" >&2
      exit 2
    fi
    # Each enum member is a plain token: matched literally below, but a sane
    # charset keeps diagnostics and overlay files unambiguous.
    for _m in $kvalues; do
      case "$_m" in
        *[!A-Za-z0-9._-]*)
          echo "resolve-config-knob: enum member '$(sanitize_printable "$_m" "(unprintable member)")' has characters outside [A-Za-z0-9._-]" >&2
          exit 2
          ;;
      esac
      [ "${#_m}" -le 64 ] || {
        echo "resolve-config-knob: enum member '$(sanitize_printable "$_m" "(unprintable member)")' is longer than 64 characters" >&2
        exit 2
      }
    done
    ;;
  posint)
    if [ -n "$kvalues" ]; then
      echo "resolve-config-knob: --values only applies to --type enum" >&2
      exit 2
    fi
    ;;
  "")
    usage
    exit 2
    ;;
  *)
    echo "resolve-config-knob: unknown type '$(sanitize_printable "$ktype" "(unprintable type)")' (enum | posint)" >&2
    exit 2
    ;;
esac

if [ "$fallback_set" -ne 1 ]; then
  echo "resolve-config-knob: --fallback is required (the caller's safe value when no layer resolves the key)" >&2
  exit 2
fi

# valid_value <value>: 0 when the trimmed value is legal for the declared
# type — a pure predicate, the sibling resolvers' shape. config-get already
# strips a trailing `# comment` and a surrounding quote pair; the trim here
# is defensive against surrounding whitespace so `  true  ` validates.
valid_value() {
  _vv=$(printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  case "$ktype" in
    enum)
      for _m in $kvalues; do
        [ "$_vv" = "$_m" ] && return 0
      done
      return 1
      ;;
    posint)
      case "$_vv" in
        "" | *[!0-9]* | 0*) return 1 ;;
      esac
      [ "${#_vv}" -le 15 ]
      ;;
  esac
}

# emit_trimmed <value>: print the value trimmed of surrounding whitespace,
# newline-terminated (the emitter contract every sibling honors).
emit_trimmed() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
  printf '\n'
}

if ! valid_value "$fallback"; then
  echo "resolve-config-knob: the --fallback value '$(sanitize_printable "$fallback" "(unprintable fallback)")' is not a legal $ktype value (caller bug)" >&2
  exit 2
fi

config_get="$script_dir/config-get.sh"
if [ ! -x "$config_get" ]; then
  echo "resolve-config-knob: config reader '$config_get' is missing or not executable" >&2
  exit 5
fi

# Read the winning value and its layer. The pinned --explain contract is a
# single "<layer>TAB<value>" line on stdout (config-get B1.6).
explain_out=""
rc=0
explain_out=$("$config_get" --explain "$key") || rc=$?

if [ "$rc" -eq 4 ]; then
  # config-get already hard-failed a structurally malformed repo-tracked
  # config file and named it on stderr; propagate the team-shared hard-fail.
  exit 4
fi
if [ "$rc" -eq 3 ]; then
  # The key is absent in every layer. Emit the caller's declared safe value so
  # the calling mechanism still runs (REQ-K1.6), warning loudly.
  echo "resolve-config-knob: warning: '$key' is unset in every layer (broken/partial install, or a knob core does not ship); falling back to '$fallback'" >&2
  emit_trimmed "$fallback"
  exit 0
fi
if [ "$rc" -ne 0 ]; then
  echo "resolve-config-knob: unexpected config-get exit $rc resolving '$key'" >&2
  exit "$rc"
fi

# The pinned --explain contract is "<layer>TAB<value>". A line with no tab
# would make both expansions below yield the whole line — and a
# coincidentally-valid value would then resolve with its layer provenance
# lost, silently bypassing the by-layer policy. Refuse it instead. (The tab
# is matched through a variable: an unquoted literal tab in a case pattern
# is token-separating whitespace, not a pattern character.)
TAB=$(printf '\t')
case "$explain_out" in
  *"$TAB"*) ;;
  *)
    echo "resolve-config-knob: config-get --explain output is malformed (no layer/value separator) — broken install" >&2
    exit 5
    ;;
esac
layer=${explain_out%%	*}
value=${explain_out#*	}

if valid_value "$value"; then
  emit_trimmed "$value"
  exit 0
fi

# The winning value is malformed. Apply the REQ-E1.4 by-layer policy.
case "$layer" in
  repo-tracked)
    echo "resolve-config-knob: repo-tracked overlay sets '$key' to a malformed value ('$(sanitize_printable "$value" "(unprintable value)")' is not a legal $ktype value); refusing to silently degrade a shared team value" >&2
    exit 4
    ;;
  adopter | machine-local)
    echo "resolve-config-knob: warning: the $layer overlay sets '$key' to a malformed value ('$(sanitize_printable "$value" "(unprintable value)")' is not a legal $ktype value); degrading to the core default" >&2
    # Re-resolve with the overlay layers neutralized so config-get returns the
    # core default. mktemp gives an empty repo root (no .claude/planwright.yml
    # -> repo-tracked and derived machine-local both absent); a
    # guaranteed-absent adopter path blanks the adopter layer.
    scratch=$(mktemp -d) || {
      echo "resolve-config-knob: could not create a scratch dir to read the core default" >&2
      exit 5
    }
    core_value=""
    crc=0
    core_value=$(
      PLANWRIGHT_ADOPTER_OVERLAY="$scratch/no-adopter" \
        PLANWRIGHT_REPO_ROOT="$scratch" \
        PLANWRIGHT_LOCAL_CONFIG="" \
        "$config_get" "$key"
    ) || crc=$?
    rm -rf "$scratch"
    if [ "$crc" -eq 3 ]; then
      # The core layer itself omits the key (only the malformed overlay set
      # it). Fall back to the caller's safe value so the mechanism still runs.
      echo "resolve-config-knob: warning: the core default for '$key' is also unset; falling back to '$fallback'" >&2
      emit_trimmed "$fallback"
      exit 0
    fi
    if [ "$crc" -ne 0 ]; then
      echo "resolve-config-knob: the core default for '$key' is itself unresolvable (exit $crc) — broken install" >&2
      exit 5
    fi
    if valid_value "$core_value"; then
      emit_trimmed "$core_value"
      exit 0
    fi
    echo "resolve-config-knob: the core default for '$key' ('$(sanitize_printable "$core_value" "(unprintable value)")') is itself malformed — broken install" >&2
    exit 5
    ;;
  core)
    echo "resolve-config-knob: the core default for '$key' ('$(sanitize_printable "$value" "(unprintable value)")') is malformed — broken install" >&2
    exit 5
    ;;
  *)
    echo "resolve-config-knob: config-get named an unrecognized layer '$(sanitize_printable "$layer" "(unprintable layer)")'" >&2
    exit 5
    ;;
esac
