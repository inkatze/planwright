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
for c in claude curl wget gh; do
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
set -e
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

clear_repo_knobs
echo "ALL PASS: allocation-apply"
