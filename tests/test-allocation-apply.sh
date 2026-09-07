#!/bin/bash
# Tests for scripts/allocation-apply.sh — the capability-aware APPLICATION half
# of launch-point selection (model-allocation Task 6; D-4, D-10, D-13;
# REQ-A1.2, REQ-B1.1, REQ-B1.2).
#
# allocation-select.sh chooses and allocation-adapt.sh records; neither decides
# whether the launching backend can actually SET what was chosen. This script
# is that decision, per dimension: it asks the backend capability contract what
# the backend advertises, applies each of model and effort only where the
# backend can set it, and records every inheritance — full, partial, or forced
# by a capability probe that errored — as a ledger row. An un-audited ambient
# launch is the failure mode the whole file exists to make impossible.
#
# What is covered:
#   - defaults-only equivalence (REQ-A1.2, D-13): with an empty config every
#     non-fleet key resolves to the `inherit` sentinel, nothing is applied, and
#     the launch keeps its ambient tier — with the audit row Task 2's engine
#     already writes and NO second row invented on top of it;
#   - the four pinned fixture backends (REQ-B1.2): a fully capable backend
#     (both dimensions flagged), a no-capability backend (full inheritance plus
#     its row), a partially capable backend (model set, effort inherited,
#     partial-inheritance row), and an errored capability probe (treated as
#     no-capability, audited);
#   - per-dimension application (D-10): the model dimension can land while the
#     effort dimension inherits, and the ledger says which was which;
#   - fail-closed identity (REQ-B1.2): a launch with no unit has nowhere to
#     record its inheritance, so it is refused rather than launched unaudited;
#   - hostile key/backend names are refused and sanitized, never interpolated;
#   - determinism and zero outbound client invocations (REQ-A1.1).
#
# The launch-site wiring that consumes this plan (offload's dispatch step, the
# skill-prose launch points) is covered by tests/test-allocation-launch-wiring.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-allocation-apply.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
AP="$REPO_ROOT/scripts/allocation-apply.sh"
LEDGER="$REPO_ROOT/scripts/allocation-ledger.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$AP" ] || fail "$AP missing or not executable"

tmp=$(mktemp -d) || fail "mktemp"
trap 'rm -rf "$tmp"' EXIT

fleet_home="$tmp/fleet"
repo="$tmp/repo"
adopter_root="$tmp/adopter"
core_cfg="$tmp/core.yml"
mkdir -p "$fleet_home" "$repo/.claude" "$adopter_root"
cp "$REPO_ROOT/config/defaults.yml" "$core_cfg" || fail "seeding the core config"

# Stub outbound clients: any invocation would put a model or network call in the
# application path, which the determinism floor forbids (REQ-A1.1). `tmux` is
# stubbed for the same reason a capability probe must never need one.
stubbin="$tmp/stubbin"
mkdir -p "$stubbin"
for c in claude curl wget gh tmux; do
  cat >"$stubbin/$c" <<EOF
#!/bin/sh
echo "$c" >>"$tmp/invocations"
exit 0
EOF
  chmod +x "$stubbin/$c"
done

env_run() {
  PATH="$stubbin:$PATH" \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    PLANWRIGHT_BACKEND_SUBAGENT=1 \
    PLANWRIGHT_BACKEND_TMUX=1 \
    /bin/bash "$@"
}

run() { env_run "$AP" "$@"; }
rows() { env_run "$LEDGER" rows "$1"; }

# field <plan-output> <key>: the value of one `key<TAB>value` plan line.
field() {
  printf '%s\n' "$1" | awk -F "$TAB" -v k="$2" '$1 == k { print $2; found = 1 }
    END { if (!found) exit 3 }'
}

# set_repo_knobs <line>...: write the repo-tracked overlay the run reads.
set_repo_knobs() {
  : >"$repo/.claude/planwright.yml"
  for sk_l in "$@"; do
    printf '%s\n' "$sk_l" >>"$repo/.claude/planwright.yml"
  done
}

clear_repo_knobs() { : >"$repo/.claude/planwright.yml"; }

# row_count <unit>: how many ledger rows the unit carries.
row_count() { rows "$1" | awk 'END { print NR + 0 }'; }

# inputs_of <unit> <seq>: the `inputs` cell (field 15) of one row.
inputs_of() { rows "$1" | awk -F "$TAB" -v s="$2" '$1 == s { print $15 }'; }

# event_of <unit> <seq>: the event class (field 6) of one row.
event_of() { rows "$1" | awk -F "$TAB" -v s="$2" '$1 == s { print $6 }'; }

# outcome_of <unit> <seq>: the outcome (field 14) of one row.
outcome_of() { rows "$1" | awk -F "$TAB" -v s="$2" '$1 == s { print $14 }'; }

# --------------------------------------------------------------------------
# 1. Defaults only: the sentinel is honored, nothing is applied, and the audit
#    row is the one Task 2's engine already writes (REQ-A1.2, D-13).
# --------------------------------------------------------------------------
clear_repo_knobs
for k in orchestrate_dispatch execute_step offload; do
  out=$(run plan --key "$k" --backend tmux --unit "u-default-$k") \
    || fail "plan at key $k with defaults exited nonzero"
  [ "$(field "$out" model)" = inherit ] \
    || fail "key $k with defaults applied a model: $(field "$out" model)"
  [ "$(field "$out" effort)" = inherit ] \
    || fail "key $k with defaults applied an effort: $(field "$out" effort)"
  [ "$(field "$out" model_source)" = inherit-config ] \
    || fail "key $k with defaults: model_source is $(field "$out" model_source)"
  [ "$(field "$out" effort_source)" = inherit-config ] \
    || fail "key $k with defaults: effort_source is $(field "$out" effort_source)"
  # Exactly one row: the config-level full-inheritance row. A second row here
  # would mean the capability layer invented an inheritance the config already
  # recorded.
  [ "$(row_count "u-default-$k")" = 1 ] \
    || fail "key $k with defaults wrote $(row_count "u-default-$k") ledger rows, expected 1"
  [ "$(event_of "u-default-$k" 1)" = inherit ] \
    || fail "key $k with defaults: row 1 event is $(event_of "u-default-$k" 1)"
  case "$(inputs_of "u-default-$k" 1)" in
    *inherit=full*) ;;
    *) fail "key $k with defaults: row 1 inputs lack inherit=full: $(inputs_of "u-default-$k" 1)" ;;
  esac
done
echo "ok: with defaults only every non-fleet surface plans an ambient launch, audited by exactly one row"

# --------------------------------------------------------------------------
# 2. A fully capable backend applies both dimensions (REQ-B1.2, fixture 1).
# --------------------------------------------------------------------------
set_repo_knobs 'allocation_model_offload: opus' 'allocation_effort_offload: high'
out=$(run plan --key offload --backend tmux --unit u-full) || fail "full-capability plan exited nonzero"
[ "$(field "$out" capability)" = both ] \
  || fail "tmux should advertise both dimensions, got $(field "$out" capability)"
[ "$(field "$out" model)" = opus ] || fail "full-capability model is $(field "$out" model)"
[ "$(field "$out" effort)" = high ] || fail "full-capability effort is $(field "$out" effort)"
[ "$(field "$out" model_source)" = applied ] \
  || fail "full-capability model_source is $(field "$out" model_source)"
[ "$(field "$out" effort_source)" = applied ] \
  || fail "full-capability effort_source is $(field "$out" effort_source)"
# One row, and it is the engine's own resolved launch row — nothing inherited,
# so nothing extra to audit.
[ "$(row_count u-full)" = 1 ] \
  || fail "full capability wrote $(row_count u-full) rows, expected 1"
[ "$(outcome_of u-full 1)" = resolved ] \
  || fail "full-capability row outcome is $(outcome_of u-full 1)"
echo "ok: a fully capable backend applies both dimensions with no inheritance row"

# --------------------------------------------------------------------------
# 3. A no-capability backend inherits both, and says so in the ledger
#    (REQ-B1.2, fixture 2).
# --------------------------------------------------------------------------
set_repo_knobs 'allocation_model_offload: opus' 'allocation_effort_offload: high'
out=$(run plan --key offload --backend in-session --unit u-none) \
  || fail "no-capability plan exited nonzero"
[ "$(field "$out" capability)" = none ] \
  || fail "in-session should advertise no tier control, got $(field "$out" capability)"
[ "$(field "$out" model)" = inherit ] \
  || fail "no-capability backend applied a model: $(field "$out" model)"
[ "$(field "$out" effort)" = inherit ] \
  || fail "no-capability backend applied an effort: $(field "$out" effort)"
[ "$(field "$out" model_source)" = inherit-capability ] \
  || fail "no-capability model_source is $(field "$out" model_source)"
[ "$(field "$out" effort_source)" = inherit-capability ] \
  || fail "no-capability effort_source is $(field "$out" effort_source)"
# Two rows: the engine's resolved row, then the capability inheritance row.
[ "$(row_count u-none)" = 2 ] \
  || fail "no capability wrote $(row_count u-none) rows, expected 2"
[ "$(event_of u-none 2)" = inherit ] \
  || fail "no-capability audit row event is $(event_of u-none 2)"
[ "$(outcome_of u-none 2)" = inherit ] \
  || fail "no-capability audit row outcome is $(outcome_of u-none 2)"
case "$(inputs_of u-none 2)" in
  *inherit=full*cause=capability* | *cause=capability*inherit=full*) ;;
  *) fail "no-capability audit row inputs are $(inputs_of u-none 2)" ;;
esac
echo "ok: a no-capability backend inherits both dimensions and records a full-inheritance row"

# --------------------------------------------------------------------------
# 4. A partially capable backend sets the model and inherits the effort
#    (REQ-B1.2, fixture 3; D-10's per-dimension clause).
# --------------------------------------------------------------------------
set_repo_knobs 'allocation_model_offload: opus' 'allocation_effort_offload: high'
out=$(run plan --key offload --backend subagent --unit u-partial) \
  || fail "partial-capability plan exited nonzero"
[ "$(field "$out" capability)" = model ] \
  || fail "subagent should advertise model-only tier control, got $(field "$out" capability)"
[ "$(field "$out" model)" = opus ] \
  || fail "partial-capability model is $(field "$out" model)"
[ "$(field "$out" effort)" = inherit ] \
  || fail "partial-capability backend applied an effort: $(field "$out" effort)"
[ "$(field "$out" model_source)" = applied ] \
  || fail "partial-capability model_source is $(field "$out" model_source)"
[ "$(field "$out" effort_source)" = inherit-capability ] \
  || fail "partial-capability effort_source is $(field "$out" effort_source)"
[ "$(row_count u-partial)" = 2 ] \
  || fail "partial capability wrote $(row_count u-partial) rows, expected 2"
case "$(inputs_of u-partial 2)" in
  *inherit=partial*) ;;
  *) fail "partial-capability audit row inputs lack inherit=partial: $(inputs_of u-partial 2)" ;;
esac
case "$(inputs_of u-partial 2)" in
  *dim=effort*) ;;
  *) fail "partial-capability audit row does not name the inherited dimension: $(inputs_of u-partial 2)" ;;
esac
# The resolved cells carry the per-dimension truth: the model that landed
# beside the effort that did not.
led_res=$(rows u-partial | awk -F "$TAB" '$1 == 2 { print $11 "/" $12 }')
[ "$led_res" = "opus/inherit" ] \
  || fail "partial-inheritance row resolved cells are $led_res, expected opus/inherit"
# ...and that half-sentinel pair must never be offered as a launch tier a
# degraded relaunch could adopt: `last-tier` answers only with real tiers.
lt=$(env_run "$LEDGER" last-tier u-partial)
case "$lt" in
  *inherit*) fail "last-tier offered a half-inherited pair as a launch tier: $lt" ;;
esac
echo "ok: a partially capable backend applies the model, inherits the effort, and records a partial row"

# --------------------------------------------------------------------------
# 5. A capability probe that errors is treated as no-capability, audited
#    (REQ-B1.2, fixture 4; D-10).
# --------------------------------------------------------------------------
# A pluggable backend name with no `planwright-backend-<name>` adapter on PATH:
# the probe cannot answer, which the contract treats as no capability.
set_repo_knobs 'allocation_model_offload: opus' 'allocation_effort_offload: high'
out=$(run plan --key offload --backend absent-probe --unit u-probe-error) \
  || fail "errored-probe plan exited nonzero (it must degrade, not fail)"
[ "$(field "$out" capability)" = error ] \
  || fail "an unanswerable probe should report error, got $(field "$out" capability)"
[ "$(field "$out" model)" = inherit ] \
  || fail "errored probe applied a model: $(field "$out" model)"
[ "$(field "$out" effort)" = inherit ] \
  || fail "errored probe applied an effort: $(field "$out" effort)"
[ "$(field "$out" model_source)" = inherit-probe-error ] \
  || fail "errored-probe model_source is $(field "$out" model_source)"
[ "$(field "$out" effort_source)" = inherit-probe-error ] \
  || fail "errored-probe effort_source is $(field "$out" effort_source)"
[ "$(row_count u-probe-error)" = 2 ] \
  || fail "errored probe wrote $(row_count u-probe-error) rows, expected 2"
case "$(inputs_of u-probe-error 2)" in
  *cause=probe-error*) ;;
  *) fail "errored-probe audit row inputs are $(inputs_of u-probe-error 2)" ;;
esac
echo "ok: an errored capability probe inherits both dimensions and is audited as a probe error"

# --------------------------------------------------------------------------
# 5b. The mirror of the partial case (REQ-B1.2, D-10's per-dimension clause):
#     a backend that can set the EFFORT but not the model. No shipped rung
#     advertises this, so it comes from a pluggable adapter — without it only
#     one of the two per-dimension directions is ever exercised.
# --------------------------------------------------------------------------
cat >"$stubbin/planwright-backend-effortonly" <<'ADAPTER'
#!/bin/sh
[ "$1" = advertise ] && printf '%s
' "false false false false true no light false effort"
ADAPTER
chmod +x "$stubbin/planwright-backend-effortonly"
set_repo_knobs 'allocation_model_offload: opus' 'allocation_effort_offload: high'
out=$(run plan --key offload --backend effortonly --unit u-effort) || fail "effort-only plan exited nonzero"
[ "$(field "$out" capability)" = effort ] || fail "the effort-only adapter advertised $(field "$out" capability)"
[ "$(field "$out" model)" = inherit ] || fail "an effort-only backend applied a model: $(field "$out" model)"
[ "$(field "$out" effort)" = high ] || fail "an effort-only backend did not apply the effort: $(field "$out" effort)"
[ "$(field "$out" model_source)" = inherit-capability ] || fail "effort-only model_source is $(field "$out" model_source)"
[ "$(field "$out" effort_source)" = applied ] || fail "effort-only effort_source is $(field "$out" effort_source)"
case "$(inputs_of u-effort 2)" in
  *dim=model*) ;;
  *) fail "the effort-only row does not name the inherited dimension: $(inputs_of u-effort 2)" ;;
esac
echo "ok: an effort-capable backend applies the effort and inherits the model"

# --------------------------------------------------------------------------
# 6. No unit, no launch plan: an inheritance with nowhere to be recorded is
#    refused rather than launched unaudited (REQ-B1.2).
# --------------------------------------------------------------------------
set +e
out=$(run plan --key offload --backend in-session 2>"$tmp/err")
rc=$?
set -e
[ "$rc" = 2 ] || fail "a plan with no --unit exited $rc, expected 2"
[ -z "$out" ] || fail "a plan with no --unit printed a plan: $out"
grep -q -- --unit "$tmp/err" || fail "the no-unit refusal does not name --unit"
echo "ok: a launch with no unit identity is refused, never planned unaudited"

# --------------------------------------------------------------------------
# 7. Hostile and unknown names are refused, and the diagnostic is sanitized.
# --------------------------------------------------------------------------
for bad_key in 'offload; rm -rf /' '../../etc/passwd' 'Offload' ''; do
  set +e
  run plan --key "$bad_key" --backend tmux --unit u-hostile >/dev/null 2>"$tmp/err"
  rc=$?
  set -e
  [ "$rc" = 2 ] || fail "hostile key '$bad_key' exited $rc, expected 2"
done
for bad_backend in 'tmux; id' '../evil' 'TMUX' ''; do
  set +e
  run plan --key offload --backend "$bad_backend" --unit u-hostile >/dev/null 2>"$tmp/err"
  rc=$?
  set -e
  [ "$rc" = 2 ] || fail "hostile backend '$bad_backend' exited $rc, expected 2"
done
# A control byte in a refused name must not survive into the diagnostic.
set +e
run plan --key "$(printf 'off\007load')" --backend tmux --unit u-hostile >/dev/null 2>"$tmp/err"
rc=$?
set -e
[ "$rc" = 2 ] || fail "a control-byte key exited $rc, expected 2"
# A silent refusal would satisfy the strip check vacuously: the diagnostic must
# exist, name the rejected thing, and carry no control byte.
[ -s "$tmp/err" ] || fail "the control-byte refusal carried no diagnostic at all"
grep -q 'selection key' "$tmp/err" || fail "the refusal does not say what it rejected"
if LC_ALL=C grep -q '[[:cntrl:]]' "$tmp/err"; then
  fail "the refusal diagnostic re-emitted a control byte"
fi
echo "ok: hostile keys and backend names are refused with a sanitized diagnostic"

# --------------------------------------------------------------------------
# 8. Determinism, and no outbound client in the application path (REQ-A1.1).
# --------------------------------------------------------------------------
a=$(run plan --key offload --backend subagent --unit u-det)
b=$(run plan --key offload --backend subagent --unit u-det)
[ "$a" = "$b" ] || fail "repeated plans differ:
$a
--
$b"
[ ! -s "$tmp/invocations" ] \
  || fail "the application path invoked an outbound client: $(cat "$tmp/invocations")"
# Positive control: the stubs are reachable, so the assertion above is not vacuous.
PATH="$stubbin:$PATH" claude >/dev/null 2>&1 || true
[ -s "$tmp/invocations" ] || fail "the outbound-client stub is unreachable; case 8 is vacuous"
echo "ok: application is deterministic and reaches no outbound client"

# --------------------------------------------------------------------------
# 9. A WITHHELD admission is not a launch plan (REQ-B1.2, the admission gate).
#    When the usage rung defers, the engine answers `admit withheld` with no
#    tier at all. Applying that as if it were a tier would push work past the
#    gate at every surface this task wired, so the plan is refused.
# --------------------------------------------------------------------------
set_repo_knobs 'allocation_model_offload: opus' 'allocation_effort_offload: high'
env_run "$REPO_ROOT/scripts/fleet-audit.sh" record usage-gate defer-all seed 'seed the rung' >/dev/null 2>&1 \
  || fail "seeding the defer-all rung failed"
set +e
out=$(run plan --key offload --backend tmux --unit u-withheld 2>"$tmp/err")
rc=$?
set -e
[ "$rc" = 3 ] || fail "a withheld admission exited $rc, expected 3"
printf '%s\n' "$out" | grep -q "^admit${TAB}withheld$" \
  || fail "a withheld plan does not carry the admit row: $out"
[ "$(field "$out" model)" = inherit ] \
  || fail "a withheld plan proposed a model: $(field "$out" model)"
# The gate answers before the backend is probed, so the plan reports the
# capability as unprobed rather than claiming the backend cannot set a tier.
# Pinned with the header's enum: the value is part of the contract a consumer
# parses, and the two drifting apart is what makes a plan unreadable.
[ "$(field "$out" capability)" = - ] \
  || fail "a withheld plan reported a probed capability: $(field "$out" capability)"
grep -qi withheld "$tmp/err" || fail "the withheld refusal is not surfaced on stderr"
# The withheld unit must not collect a capability-inheritance row: nothing
# launched, so nothing inherited.
rows u-withheld | awk -F "$TAB" '$6 == "inherit" && $15 ~ /cause=/ { found = 1 }
  END { exit found ? 1 : 0 }' \
  || fail "a withheld unit collected a spurious capability-inheritance row"
# Clear the rung again for the cases below.
env_run "$REPO_ROOT/scripts/fleet-audit.sh" record usage-gate normal seed 'reset the rung' >/dev/null 2>&1 \
  || fail "resetting the rung failed"
echo "ok: a withheld admission is refused rather than applied as a tier"

# --------------------------------------------------------------------------
# 10. A version-skewed capability accessor is a BROKEN INSTALL, not a probe
#     error. An accessor still emitting the legacy eight-field set would
#     otherwise read as "this backend cannot set a tier" and inherit silently,
#     which is the same fail-open dressed as a capability gap.
# --------------------------------------------------------------------------
# A skewed INSTALL: the script resolves its siblings beside itself, so the
# faithful way to stage version skew is a directory holding this script next to
# a stale accessor.
skew="$tmp/skew-install"
mkdir -p "$skew"
cp "$AP" "$REPO_ROOT/scripts/echo-safety.sh" "$REPO_ROOT/scripts/allocation-adapt.sh" \
  "$REPO_ROOT/scripts/allocation-ledger.sh" "$REPO_ROOT/scripts/allocation-ladder.sh" \
  "$REPO_ROOT/scripts/allocation-select.sh" "$REPO_ROOT/scripts/fleet-resource-select.sh" \
  "$REPO_ROOT/scripts/resolve-config-knob.sh" "$REPO_ROOT/scripts/config-get.sh" \
  "$REPO_ROOT/scripts/fleet-state.sh" "$REPO_ROOT/scripts/fleet-usage-gate.sh" \
  "$REPO_ROOT/scripts/fleet-daemon-gate.sh" "$REPO_ROOT/scripts/fleet-audit.sh" \
  "$REPO_ROOT/scripts/fleet-allocate.sh" "$REPO_ROOT/scripts/resolve-overlay-root.sh" \
  "$skew/" 2>/dev/null || true
cat >"$skew/orchestrate-backends.sh" <<'SKEW'
#!/bin/sh
# A stale sibling: the pre-extension eight-field answer.
[ "$1" = caps ] || exit 2
printf '%s\n' "true true true false true yes full-session true"
SKEW
chmod +x "$skew/orchestrate-backends.sh"
set +e
out=$(env_run "$skew/allocation-apply.sh" plan --key offload \
  --backend tmux --unit u-skew 2>"$tmp/err")
rc=$?
set -e
[ "$rc" = 5 ] || fail "a version-skewed accessor exited $rc, expected 5 (broken install)"
grep -qi "version-skewed\|field" "$tmp/err" \
  || fail "the skew diagnostic does not name the arity problem"
echo "ok: a version-skewed capability accessor is a broken install, not a silent inherit"

# --------------------------------------------------------------------------
# 10b. An engine that answers NO admit row is a broken install too, and it must
#      fail CLOSED. The admission gate is the one direction that must never
#      default open: reading a missing row as `yes` would launch precisely the
#      units the usage gate withheld, at every surface this task wired. The
#      missing model and effort rows two checks above already exit 5; admit is
#      answered by the same engine on the same call, so its absence is the same
#      version skew and takes the same code.
# --------------------------------------------------------------------------
noadmit="$tmp/noadmit-install"
mkdir -p "$noadmit"
cp "$AP" "$REPO_ROOT/scripts/echo-safety.sh" "$REPO_ROOT/scripts/allocation-ledger.sh" \
  "$REPO_ROOT/scripts/orchestrate-backends.sh" "$REPO_ROOT/scripts/allocation-ladder.sh" \
  "$REPO_ROOT/scripts/allocation-select.sh" "$REPO_ROOT/scripts/fleet-resource-select.sh" \
  "$REPO_ROOT/scripts/resolve-config-knob.sh" "$REPO_ROOT/scripts/config-get.sh" \
  "$REPO_ROOT/scripts/fleet-state.sh" "$REPO_ROOT/scripts/fleet-usage-gate.sh" \
  "$REPO_ROOT/scripts/fleet-daemon-gate.sh" "$REPO_ROOT/scripts/fleet-audit.sh" \
  "$REPO_ROOT/scripts/fleet-allocate.sh" "$REPO_ROOT/scripts/resolve-overlay-root.sh" \
  "$noadmit/" 2>/dev/null || true
# A pre-admission-gate engine: it resolves a tier, and never answers `admit`.
cat >"$noadmit/allocation-adapt.sh" <<'NOADMIT'
#!/bin/sh
# A stale sibling: resolves a tier but predates the admission gate.
[ "$1" = resolve ] || exit 2
printf 'model\topus\n'
printf 'effort\thigh\n'
printf 'proposed_model\topus\n'
printf 'proposed_effort\thigh\n'
NOADMIT
chmod +x "$noadmit/allocation-adapt.sh"
set +e
out=$(env_run "$noadmit/allocation-apply.sh" plan --key offload \
  --backend tmux --unit u-noadmit 2>"$tmp/err")
rc=$?
set -e
[ "$rc" = 5 ] \
  || fail "an engine answering no admit row exited $rc, expected 5 (broken install); plan was: $out"
# The specific fail-open this guards: not merely a nonzero exit, but never a
# printed plan that a caller could read as an admitted launch.
printf '%s\n' "$out" | grep -q "^admit${TAB}yes$" \
  && fail "a missing admit row was defaulted to admitted: $out"
grep -qi "admit" "$tmp/err" || fail "the missing-admit diagnostic does not name the admit row"
echo "ok: a missing admit row fails closed rather than defaulting to admitted"

# --------------------------------------------------------------------------
# 10c. A GARBLED admit answer fails closed too. `admit` is a closed enum
#      (`yes | withheld`), and testing only for `withheld` would treat every
#      other token — a version-skewed spelling, a truncated read, a torn row —
#      as admitted. That is the same fail-open as the missing row above,
#      arriving through a value rather than an absence.
# --------------------------------------------------------------------------
cat >"$noadmit/allocation-adapt.sh" <<'GARBLED'
#!/bin/sh
# A sibling answering an admit token outside the enum.
[ "$1" = resolve ] || exit 2
printf 'admit\tmaybe\n'
printf 'model\topus\n'
printf 'effort\thigh\n'
printf 'proposed_model\topus\n'
printf 'proposed_effort\thigh\n'
GARBLED
chmod +x "$noadmit/allocation-adapt.sh"
set +e
out=$(env_run "$noadmit/allocation-apply.sh" plan --key offload \
  --backend tmux --unit u-garbled 2>"$tmp/err")
rc=$?
set -e
[ "$rc" = 5 ] \
  || fail "an out-of-enum admit exited $rc, expected 5 (broken install); plan was: $out"
printf '%s\n' "$out" | grep -q "^admit${TAB}yes$" \
  && fail "an out-of-enum admit was laundered into an admitted plan: $out"
echo "ok: an out-of-enum admit fails closed rather than reading as admitted"

# --------------------------------------------------------------------------
# 11. An unreachable allocation store gets its OWN exit code, so a caller can
#     degrade on it without also degrading on a rejected argument.
# --------------------------------------------------------------------------
set +e
out=$(PLANWRIGHT_FLEET_STATE_DIR="" CLAUDE_PLUGIN_DATA="" CLAUDE_DIR="$tmp/no-such-dir" \
  PATH="$stubbin:$PATH" PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
  PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" PLANWRIGHT_REPO_ROOT="$repo" \
  PLANWRIGHT_LOCAL_CONFIG="" /bin/bash "$AP" plan --key offload --backend tmux \
  --unit u-nostore 2>"$tmp/err")
rc=$?
set -e
[ "$rc" = 6 ] || fail "an unreachable allocation store exited $rc, expected 6"
[ -z "$out" ] || fail "an unreachable store still printed a plan: $out"
echo "ok: an unreachable allocation store has its own exit code"

# --------------------------------------------------------------------------
# 12. The attempt grammar matches the engine's: a leading zero is refused here
#     rather than two helpers deep, where it would surface as a store fault.
# --------------------------------------------------------------------------
set +e
run plan --key offload --backend tmux --unit u-att --attempt 01 >/dev/null 2>"$tmp/err"
rc=$?
set -e
[ "$rc" = 2 ] || fail "a leading-zero attempt exited $rc, expected 2"
grep -qi attempt "$tmp/err" || fail "the leading-zero refusal does not name the attempt"
# The two refusals the grammar carries are not the same fact, and the engine
# spells them apart (allocation-adapt.sh). Calling `01` non-numeric sends a
# reader looking for a character that is not there.
grep -qi 'leading zero' "$tmp/err" \
  || fail "the leading-zero refusal does not name the leading zero: $(cat "$tmp/err")"
grep -qi 'non-numeric' "$tmp/err" \
  && fail "the leading-zero refusal calls a numeric attempt non-numeric: $(cat "$tmp/err")"
echo "ok: the attempt grammar matches the engine's, refused locally"

# 12b. A genuinely non-numeric attempt keeps the non-numeric wording, so
#      splitting the diagnostic above did not simply rename both arms.
set +e
run plan --key offload --backend tmux --unit u-att --attempt abc >/dev/null 2>"$tmp/err"
rc=$?
set -e
[ "$rc" = 2 ] || fail "a non-numeric attempt exited $rc, expected 2"
grep -qi 'non-numeric' "$tmp/err" \
  || fail "the non-numeric refusal lost its wording: $(cat "$tmp/err")"
echo "ok: a non-numeric attempt is refused as non-numeric"

clear_repo_knobs
echo "ALL PASS: allocation-apply"
