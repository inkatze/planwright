#!/bin/sh
# context-budget-monitor.sh — the long-running tower's context-budget monitor
# (D-4, REQ-C1.1). Answers one question each step: given how many orchestration
# steps this tower has completed, is it nearing its context budget and so should
# it auto-heal (hand off to a fresh tower — the continue-as-new pattern in
# doctrine/context-budget-autoheal.md) before it silently degrades from context
# exhaustion?
#
# The signal is a completed-step-count proxy, not a live token measurement:
# Claude Code exposes no supported programmatic introspection of its own
# context-window usage (Task 5 research, brief §7 — no env var, no hook field,
# no CLI query; the transcript JSONL is internal and version-unstable, so
# parsing it is a rejected antipattern). The step count is the portable,
# tower-controllable measurement the tower already has from its own step loop.
# The corroborating native signal — the `PreCompact` (auto) hook — is documented
# in the doctrine doc as a hard-floor a tower may register in its own settings;
# this monitor evaluates the step-count threshold, the primary signal.
#
# The configured threshold is resolved through
# resolve-context-budget-threshold.sh (the four-layer config knob
# `context_budget_threshold`): a positive integer step budget, or `off` to
# disable auto-heal. This monitor does not re-implement config resolution or the
# by-layer malformed policy (REQ-D1.1); it delegates and propagates the
# resolver's hard-fail.
#
# Usage: context-budget-monitor.sh <steps-completed>
#   <steps-completed> is a non-negative integer: how many orchestration steps
#   this tower has run since it started.
#
# stdout: exactly one of (one line):
#   near-limit  steps completed have reached the threshold; hand off now.
#   ok          below the threshold; keep going.
#   disabled    auto-heal is off (threshold `off`); never hand off.
#
# Exit: 0 on a successful evaluation; 2 usage error (including a step count past
# the width cap); 4 propagated from the resolver when a broken repo-tracked
# config value hard-fails (a broken shared config never silently degrades the
# tower); 5 when the resolver is missing/non-executable or reports a broken
# install (propagated). Never fails opaquely.
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

usage() {
  echo "usage: context-budget-monitor.sh <steps-completed>   (a non-negative integer)" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage

steps=$1
# A non-negative integer: one or more digits, no sign, no decimal. A single 0 is
# allowed (a fresh tower). Leading zeros are tolerated here (a count, not a knob)
# but normalized away by the arithmetic comparison below.
case "$steps" in
  '' | *[!0-9]*) usage ;;
esac

script_dir=$(cd "$(dirname "$0")" && pwd) || {
  echo "context-budget-monitor: cannot resolve the script directory" >&2
  exit 2
}
resolver="$script_dir/resolve-context-budget-threshold.sh"
if [ ! -x "$resolver" ]; then
  echo "context-budget-monitor: threshold resolver '$resolver' is missing or not executable" >&2
  exit 5
fi

# Resolve the configured threshold. Propagate the resolver's exit unchanged on
# any non-zero (4 = broken repo-tracked value hard-fail; 5 = broken install);
# the resolver has already explained the failure on stderr.
threshold=""
rc=0
threshold=$("$resolver") || rc=$?
if [ "$rc" -ne 0 ]; then
  exit "$rc"
fi

if [ "$threshold" = off ]; then
  echo disabled
  exit 0
fi

# Integer comparison, POSIX-clean (no `$(( ))` — a leading-zero step count would
# be read as octal there, and base-notation like `10#$n` is a bashism the
# `#!/bin/sh` dialect rejects). Strip any leading zeros from the step count so
# `test -ge` sees a plain decimal; the threshold already has no leading zero
# (the resolver rejects `0*`). An all-zeros count normalizes to 0.
steps_n=$(printf '%s' "$steps" | sed 's/^0\{1,\}//')
[ -n "$steps_n" ] || steps_n=0

# Bound the step count to the same 15-digit width cap the resolver enforces on
# the threshold, so `test -ge` below cannot overflow the shell signed-integer
# range (INTMAX ~9.2e18) and fall through to a wrong answer. A count this large
# from a tower's own step tally is impossible, so this is a fail-closed guard on
# a bug, not a real value — surface it as a usage error rather than an opaque
# arithmetic leak.
[ "${#steps_n}" -le 15 ] || usage

if [ "$steps_n" -ge "$threshold" ]; then
  echo near-limit
else
  echo ok
fi
exit 0
