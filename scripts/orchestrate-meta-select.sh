#!/bin/sh
# orchestrate-meta-select.sh — the meta-tower ("tower of towers") selector for
# /orchestrate --meta (orchestration-fleet Task 6, REQ-D1.1, REQ-D1.5, D-6).
#
# Given the spec dirs a meta-tower supervises, pick the next unit to advance
# across the whole fleet, subject to a FLEET-level concurrency bound distinct
# from each spec's per-spec cap. It is the multi-spec analogue of
# orchestrate-select.sh and delegates all per-spec judgement to the single-spec
# primitives it composes — it introduces no new selection logic of its own:
#
#   - Readiness and the per-spec pick come from `orchestrate-select.sh <spec>`
#     (critical-path-first, live-truth). A spec is a candidate iff the selector
#     reports a ready unit (exit 0).
#   - In-flight counts come from the live derivation `orchestrate-state.sh`
#     (git + trailer + marker + gh evidence, D-3, REQ-B1.2) — NOT the committed
#     tasks.md snapshot — so the fleet bound is enforced against reality and
#     rebuilds from disk after any crash (level-triggered, self-healing).
#
# The FLEET bound is the config knob `fleet_max_parallel_units`, resolved through
# the four-layer overlay (config-get.sh) and DISTINCT from the per-spec
# `max_parallel_units`: the sum of in-progress units across all supervised specs
# may not exceed it. At or over the bound, nothing is dispatched this step —
# a ready unit in some spec is HELD, because the cap is fleet-wide (REQ-D1.5).
# The per-spec `max_parallel_units` is also honored: a spec already at its own
# cap is skipped even with fleet headroom, so a saturated spec never starves the
# rest. Both bounds carry the same documented safe default the single tower uses;
# an absent key keeps that default, a malformed value warns and falls back.
#
# Among the dispatchable specs the fewest-in-flight one wins (fair share across
# the fleet), command-line order breaking ties (FIFO) — the multi-spec echo of
# the single selector's FIFO tie-break.
#
# The meta-tower holds no cross-spec state beyond this step (D-6): every call
# recomputes the whole picture from the live derivation, so it is disposable and
# crash-safe exactly like a single-spec tower. The fleet-level advisory lock and
# the atomic same-instant reservation live in fleet-state.sh; this selector is
# the pure, side-effect-free decision the /orchestrate --meta step wraps in that
# lock before it launches a subordinate tower.
#
# IN-FLIGHT SOURCE OF TRUTH. The authoritative fleet in-flight count for THIS
# decision is the live git derivation summed below — level-triggered and
# self-healing, so it never leaks across a tower crash (a dead tower's units stop
# deriving as in-progress). This selector reads ONLY that git truth; it does not
# read or write fleet-state.sh's `bound-incr` counter. That counter is a separate
# same-instant RESERVATION primitive (its fleet-bound accounting is Task 6's, per
# the fleet-state.sh header) meant to close the sub-second window between a meta
# step deciding and a subordinate tower materializing its branch/marker; it is
# deliberately NOT this selector's source of truth. The two can diverge (and the
# counter, unlike the git derivation, is not crash-self-healing); the git
# derivation is what reconciles.
#
# Usage:
#   orchestrate-meta-select.sh <spec-dir> [<spec-dir>...]
#       prints "<spec-dir>\t<id>" for the unit to advance next, on stdout.
#
# Exit: 0 a unit was produced (on stdout); 1 nothing dispatchable this step
# (nothing ready anywhere, the fleet / every candidate spec is at its bound,
# or every ready spec is held on a transient evidence failure — the hold is
# surfaced on stderr per spec, REQ-B1.5);
# 2 a supervised spec dir is missing / taskless / not a git work tree, a spec
# basename fails the identifier grammar, or a required helper is unavailable —
# fail closed, so absent live truth never silently reports "nothing".
#
# Portable POSIX sh (bash 3.2 / BSD tooling): no bash arrays, no gawk-only awk.
# Input is treated as data; the spec basename (which flows downstream into git
# refs and trailers) is grammar-checked before use.
set -u

# Pin the C locale: the [a-z] range glob in the identifier check is
# collation-dependent and would otherwise admit uppercase under UTF-8 locales.
LC_ALL=C
export LC_ALL
# A CDPATH-resolved cd would echo its destination into command substitutions.
unset CDPATH

TAB=$(printf '\t')

# Resolve this script's directory so the sibling primitives are found regardless
# of the caller's working directory.
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

state_engine="$script_dir/orchestrate-state.sh"
selector="$script_dir/orchestrate-select.sh"
config_get="$script_dir/config-get.sh"
echo_safety="$script_dir/echo-safety.sh"
for helper in "$state_engine" "$selector" "$config_get"; do
  if [ ! -x "$helper" ]; then
    echo "orchestrate-meta-select: required helper $helper missing or not executable" >&2
    exit 2
  fi
done
# echo-safety.sh is sourced (not executed), so require it READABLE and fail closed
# (exit 2) when a broken install omits it — the same fail-closed shape as a
# missing executable helper, rather than a raw dot-source error. It sanitizes
# every untrusted value (spec ids/paths, derivation records) before it reaches
# operator-facing stderr (echo discipline, doctrine/security-posture.md — the same
# posture every sibling in-scope script applies at each such site).
if [ ! -r "$echo_safety" ]; then
  echo "orchestrate-meta-select: required helper $echo_safety missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$echo_safety"

if [ "$#" -lt 1 ]; then
  echo "usage: orchestrate-meta-select.sh <spec-dir> [<spec-dir>...]" >&2
  exit 2
fi

# Validate every supervised spec dir up front (fail closed before any selection):
# the basename becomes the spec id used downstream in branch names and trailers,
# so it must satisfy the anchored identifier grammar (REQ-A1.8) — a hostile id is
# rejected before it reaches any path or git op. A fleet supervises specs in ONE
# checkout: the config overlay (below) is read once from the shared repo root and
# the bounds are only meaningful against a single derivation base, so every spec
# must be inside a git work tree AND share the first spec's toplevel. A spec in no
# git work tree, or in a different checkout, is a caller error and fails closed
# (exit 2) rather than silently resolving bounds from one repo while deriving
# state against another.
repo_root=""
for spec_dir in "$@"; do
  spec_id=$(basename "$spec_dir")
  case "$spec_id" in
    *[!a-z0-9-]* | -* | "")
      echo "orchestrate-meta-select: invalid spec id '$(sanitize_printable "$spec_id" "(unprintable id)")' (must match ^[a-z0-9][a-z0-9-]*\$)" >&2
      exit 2
      ;;
  esac
  if [ "${#spec_id}" -gt 64 ]; then
    echo "orchestrate-meta-select: spec id '$spec_id' exceeds 64 characters" >&2
    exit 2
  fi
  if [ ! -f "$spec_dir/tasks.md" ] || [ ! -r "$spec_dir/tasks.md" ]; then
    echo "orchestrate-meta-select: missing or unreadable $(sanitize_printable "$spec_dir" "(unprintable path)")/tasks.md" >&2
    exit 2
  fi
  spec_top=$(cd "$spec_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || spec_top=""
  if [ -z "$spec_top" ]; then
    echo "orchestrate-meta-select: spec '$(sanitize_printable "$spec_dir" "(unprintable path)")' is not inside a git work tree" >&2
    exit 2
  fi
  if [ -z "$repo_root" ]; then
    repo_root="$spec_top"
  elif [ "$spec_top" != "$repo_root" ]; then
    echo "orchestrate-meta-select: spec '$(sanitize_printable "$spec_dir" "(unprintable path)")' is in a different checkout ('$(sanitize_printable "$spec_top" "(unprintable path)")') than the fleet root ('$(sanitize_printable "$repo_root" "(unprintable path)")'); a fleet supervises specs in one checkout" >&2
    exit 2
  fi
done

# read_bound <key> <fallback> — resolve a concurrency bound through the config
# overlay (defaults + the four layers), with a documented safe fallback. An
# absent key keeps the default; a malformed VALUE (non-numeric, or a leading-zero
# form that arithmetic would treat as octal) warns and falls back; a bound of 0
# is honored (a paused fleet/spec). config-get's own stderr is intentionally NOT
# suppressed (matching scripts/orchestrate-lock.sh and scripts/fleet-state.sh, the
# fleet's own sibling primitives): config-get is silent on a found/absent key, so
# the common paths stay quiet, but a hard-fail on a malformed repo-tracked
# (team-shared) overlay — config-get exit 4, which it raises "loudly regardless of
# the queried key" — reaches the operator instead of being silently degraded to
# the fallback. We still fall back to the safe default on that exit so one broken
# shared config never wedges the fleet, matching the sibling threshold reads.
#
# PLANWRIGHT_REPO_ROOT is pinned to the validated fleet root so config resolution
# is independent of the caller's CWD (matching scripts/fleet-state.sh, which pins
# it for the same cross-spec reason). Without the pin, config-get resolves the
# repo-tracked and adopter overlay layers from the CWD's git toplevel
# (resolve-overlay-root.sh), so invoking this selector from a different repo — or
# outside any repo — would read the wrong repo-tracked overlay and could apply an
# incorrect bound for the fleet the specs actually live in. PLANWRIGHT_LOCAL_CONFIG
# pins the machine-local layer to the same root (it already did); the two together
# tie every overlay layer to repo_root.
read_bound() {
  rb_key=$1
  rb_fallback=$2
  rb_v=$(PLANWRIGHT_REPO_ROOT="$repo_root" \
    PLANWRIGHT_LOCAL_CONFIG="$repo_root/.claude/planwright.local.yml" \
    "$config_get" "$rb_key") || rb_v=""
  case "$rb_v" in
    '')
      printf '%s' "$rb_fallback"
      ;;
    0 | [1-9] | [1-9][0-9]*)
      printf '%s' "$rb_v"
      ;;
    *)
      echo "orchestrate-meta-select: ignoring malformed $rb_key '$(sanitize_printable "$rb_v" "(unprintable value)")'; using $rb_fallback" >&2
      printf '%s' "$rb_fallback"
      ;;
  esac
}

# The single tower's documented safe default (config/defaults.yml) is 3 for both
# knobs; the fallbacks here match it so a missing key behaves identically.
fleet_bound=$(read_bound fleet_max_parallel_units 3)
spec_bound=$(read_bound max_parallel_units 3)

# Walk the supervised specs: sum fleet-wide in-flight from the live derivation,
# and collect the dispatchable candidates (a ready unit AND per-spec headroom).
fleet_inflight=0
# Each candidate is one line "<inflight>\t<index>\t<spec-dir>\t<id>"; the two
# leading numeric keys drive the fewest-in-flight-then-FIFO ordering below.
candidates=""
index=0
for spec_dir in "$@"; do
  index=$((index + 1))

  # In-flight count from the live derivation. A non-zero exit is a hard failure
  # (no git work tree, taskless) → fail the whole fleet closed.
  if ! state_out=$("$state_engine" "$spec_dir"); then
    echo "orchestrate-meta-select: live derivation failed for $(sanitize_printable "$spec_dir" "(unprintable path)") (fail closed)" >&2
    exit 2
  fi
  # The derivation's evidence-quality records (degraded / contradiction) are
  # emitted on its STDOUT as tagged TSV (orchestrate-state.sh output contract),
  # so they are captured into $state_out, not the engine's stderr. The awk below
  # keeps only task rows, which would silently drop them; surface each to the
  # operator's stderr (tagged with the spec) so a gh-degraded or git-vs-PR
  # contradiction stays visible during meta selection. This is the one place they
  # reach the operator: the per-spec selector re-derives the same state with its
  # stderr suppressed, so it cannot surface them either.
  printf '%s\n' "$state_out" \
    | awk -F"$TAB" '$1 == "degraded" || $1 == "contradiction"' \
    | while IFS= read -r meta_rec; do
      [ -n "$meta_rec" ] && echo "orchestrate-meta-select: [$(sanitize_printable "$spec_dir" "(unprintable path)")] $(sanitize_printable "$meta_rec" "(unprintable record)")" >&2
    done
  inflight=$(printf '%s\n' "$state_out" \
    | awk -F"$TAB" '$1 == "task" && $3 == "in-progress" { n++ } END { print n + 0 }')
  fleet_inflight=$((fleet_inflight + inflight))

  # The per-spec ready pick, from the single-spec selector (critical-path-first,
  # live-truth). Its stderr is suppressed here: it re-derives the same state whose
  # evidence records we already surfaced above, so letting it through would double
  # every degraded/contradiction diagnostic.
  sel_rc=0
  ready_id=$("$selector" "$spec_dir" 2>/dev/null) || sel_rc=$?
  if [ "$sel_rc" = 2 ]; then
    echo "orchestrate-meta-select: selection failed for $(sanitize_printable "$spec_dir" "(unprintable path)") (fail closed)" >&2
    exit 2
  fi
  # Selector exit 3 (REQ-B1.5, v2 bundles): a transient evidence failure — the
  # spec is held this step (not a candidate, nothing dispatched), and the
  # reason is re-stated here because the selector's stderr is suppressed
  # above. Without this, "cannot know" would be indistinguishable from
  # exit 1's "nothing ready" at the fleet tier.
  if [ "$sel_rc" = 3 ]; then
    echo "orchestrate-meta-select: transient evidence failure for $(sanitize_printable "$spec_dir" "(unprintable path)"); holding this spec this step (REQ-B1.5)" >&2
  fi

  # A candidate iff the spec has a ready unit AND is below its per-spec cap.
  if [ "$sel_rc" = 0 ] && [ -n "$ready_id" ] && [ "$inflight" -lt "$spec_bound" ]; then
    candidates="$candidates$inflight$TAB$index$TAB$spec_dir$TAB$ready_id
"
  fi
done

# The fleet bound caps TOTAL concurrency across specs: at or over it, hold this
# step even if a spec is ready. Surface the reason (distinct from nothing-ready)
# so an operator watching an unattended fleet sees why it paused.
if [ "$fleet_inflight" -ge "$fleet_bound" ]; then
  echo "orchestrate-meta-select: fleet at bound ($fleet_inflight/$fleet_bound in progress); holding this step" >&2
  exit 1
fi

# Nothing ready (or every ready spec is at its per-spec cap): nothing to dispatch.
if [ -z "$candidates" ]; then
  exit 1
fi

# Fair pick: fewest in-flight first (numeric), command-line order breaking ties.
pick=$(printf '%s' "$candidates" | sort -t"$TAB" -k1,1n -k2,2n | head -n 1)
sel_dir=$(printf '%s' "$pick" | cut -f3)
sel_id=$(printf '%s' "$pick" | cut -f4)
printf '%s%s%s\n' "$sel_dir" "$TAB" "$sel_id"
exit 0
