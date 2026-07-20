#!/usr/bin/env bash
# check-instructions.sh — the instruction-hygiene size guard and audit tool
# (prompt-hygiene Task 2; D-1, D-2, D-3, D-4, D-5, D-13).
#
# Instruction files (skills/*/SKILL.md bodies the harness injects at invocation,
# doctrine/*.md rule docs skills front-load) grow monotonically and
# instruction-following degrades as that load grows. This guard bounds it. It:
#
#   - counts words (wc -w; wrap-invariant) and lines (informational) for every
#     instruction file, excluding doctrine/README.md (an index, REQ-A1.1);
#   - computes each skill's manifest-derived mandatory-at-start load (SKILL.md
#     body + run-start docs) and reachable closure (+ point-of-use docs),
#     charging a permanently exempt manifest doc at min(actual, its per-file
#     error threshold) so a dependent pays the budgeted size, not the overage
#     (instruction-headroom D-4, REQ-B1.1); --audit prints the honest actual
#     beside the charged total (REQ-B1.2),
#     parsing the doctrine manifest defined by doctrine/instruction-hygiene.md.
#     A skill with no manifest is scored body-only, which is not an error
#     (REQ-A1.2); a malformed manifest entry is a fail-loud error (REQ-B1.8);
#   - runs a deterministic resolution check: every manifest doc name must
#     resolve under the doctrine root (REQ-B1.6);
#   - scans hooks.json-registered hooks that emit additionalContext /
#     hookSpecificOutput and measures their STATIC injected prose, reading the
#     hook script but never executing it, and excluding interpolation lines
#     (REQ-A1.4). This injected-context surface is warn-only: it never fails the
#     check (REQ-B1.7);
#   - enforces per-file / start-load / closure budgets (knobs in
#     config/defaults.yml, overlay-tunable, REQ-B1.2) with boundary-inclusive
#     thresholds (>=, REQ-B1.8), honoring four suppression forms from the
#     tracked suppression list: a permanent per-file-floor exemption, a
#     transitional `pending-diet` allowance (REQ-B1.3), a standing
#     `declared-exception` (instruction-headroom REQ-D1.6), and a `raise`
#     rationale (instruction-headroom REQ-A1.4);
#   - enforces per-surface headroom floors (instruction-headroom D-2, REQ-A1.1,
#     REQ-D1.1): a margin (error threshold − charged words) strictly below a
#     class's floor knob is a named floor-breach warning on every run, and a
#     margin below twice the floor (the restoration target) a named below-target
#     warning; both are warnings, never errors — a permanently exempt doc carries
#     no floor;
#   - enforces the raise-rationale rule (instruction-headroom D-12, REQ-A1.4): an
#     effective instruction_budget_*_warn / *_error value above its shipped core
#     default is a fail-closed error unless a matching `raise|` entry records it;
#   - with --audit, emits a ranked report with per-surface margin-to-warn /
#     margin-to-error columns and an offender shortlist (REQ-A1.3,
#     instruction-headroom REQ-D1.1); each pending-diet allowance's Task field
#     rides both the ranked report and the shortlist (REQ-D1.2, D-8).
#
# All input this guard reads (manifest entries, exemption text, rule-doc names,
# hook scripts) is PR-controllable and treated as untrusted DATA: no content is
# passed to a shell for evaluation, doc-name resolution is confined to the
# doctrine root (a name is charset-validated before any path is formed, so no
# `../` traversal escapes), and hook scripts are read, never executed (REQ-B1.9).
#
# Usage: check-instructions.sh [--audit] [--closeout] [--root <dir>]
#   --audit      also emit the ranked report and offender shortlist on stdout.
#   --closeout   fail if ANY transitional `pending-diet` allowance remains in the
#                suppression list (per-file, start-load, or closure). The Task-8
#                closeout direction (REQ-D1.4): after the diets, only permanent
#                exemptions (REQ-B1.3a) may remain; a lingering allowance means a
#                start-load/closure offender is still hiding behind it. Off by
#                default so the transitional mechanism (REQ-B1.3b) keeps working
#                while a diet is in flight; planwright's own `check:instructions`
#                task passes it because its retrofit is complete.
#   --root <dir> base dir holding skills/, doctrine/, hooks/, config/ (default:
#                the repo root, the script's parent directory). Used by tests.
#
# Exit codes: 0 clean (warnings do not fail), 1 a budget error / malformed
#   input / unresolvable reference, 2 usage error.
#
# Portable bash 3.2 / BSD tooling; POSIX awk, no gawk-only constructs, no eval;
# all input treated as data (REQ-K1.5, REQ-B1.9).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

self_dir="$(cd "$(dirname "$0")" && pwd -P)"

# Echo discipline for the untrusted values this guard newly surfaces to the
# terminal — floor-breach / below-target surface keys and declared-exception
# rationales (instruction-headroom "Echo and data hygiene", security-posture).
# Sourced from the canonical helper; an inline fallback (behavior-identical to
# echo-safety.sh, reformatted for the nested block) keeps the guard
# self-contained if the helper is unavailable.
if [ -r "$self_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$self_dir/echo-safety.sh"
else
  sanitize_printable() {
    _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237')
    if [ -z "$_sp" ] && [ "$#" -ge 2 ]; then _sp=$2; fi
    printf '%s' "$_sp"
  }
fi

audit=0
closeout=0
root=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --audit)
      audit=1
      ;;
    --closeout)
      closeout=1
      ;;
    --root)
      shift
      [ "$#" -gt 0 ] || {
        echo "check-instructions: --root needs a directory argument" >&2
        exit 2
      }
      root="$1"
      ;;
    --root=*)
      root="${1#--root=}"
      ;;
    -h | --help)
      sed -n '2,66p' "$0"
      exit 0
      ;;
    *)
      echo "check-instructions: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
  shift
done

fixture_mode=1
if [ -z "$root" ]; then
  root="$(cd "$self_dir/.." && pwd -P)"
  fixture_mode=0
fi
if [ ! -d "$root" ]; then
  echo "check-instructions: root directory not found: $root" >&2
  exit 2
fi

skills_dir="$root/skills"
doctrine_dir="$root/doctrine"
hooks_json="$root/hooks/hooks.json"
config_defaults="$root/config/defaults.yml"
exemptions_file="$root/config/instruction-budget-exemptions.txt"
config_get="$self_dir/config-get.sh"

status=0
err() {
  echo "check-instructions: ERROR: $1" >&2
  status=1
}
warn() {
  echo "check-instructions: WARN: $1" >&2
}

# Scratch space for the ranked per-file list (sorted at report time).
work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT
perfile_list="$work/perfile"
skill_list="$work/skills"
injected_list="$work/injected"
shortlist="$work/shortlist"
: >"$perfile_list"
: >"$skill_list"
: >"$injected_list"
: >"$shortlist"

########################################################################
# Thresholds — read every knob through config-get so overlay layering
# applies; fail loud on a missing or non-numeric knob (REQ-B1.8).
########################################################################
getknob() {
  # getknob <key> -> echoes the integer value, or errors and echoes nothing.
  key="$1"
  if [ ! -x "$config_get" ]; then
    err "config-get.sh missing or not executable at $config_get"
    return 1
  fi
  # config-get resolves core defaults + overlay layers. Root them at $root so a
  # fixture (or the repo) reads its own config; in fixture mode also neutralize
  # ambient plugin/adopter env so the read is hermetic.
  if [ "$fixture_mode" -eq 1 ]; then
    val="$(
      PLANWRIGHT_CONFIG_DEFAULTS="$config_defaults" \
        PLANWRIGHT_REPO_ROOT="$root" \
        CLAUDE_PLUGIN_ROOT="" CLAUDE_PLUGIN_DATA="" \
        PLANWRIGHT_ADOPTER_OVERLAY="$root/.no-adopter-overlay" \
        PLANWRIGHT_LOCAL_CONFIG="" PLANWRIGHT_ROOT="" \
        "$config_get" "$key" 2>/dev/null
    )"
    rc=$?
  else
    val="$(
      PLANWRIGHT_CONFIG_DEFAULTS="$config_defaults" \
        PLANWRIGHT_REPO_ROOT="$root" \
        "$config_get" "$key" 2>/dev/null
    )"
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    # getknob runs in a command substitution, so it cannot set the parent's
    # status; it prints the diagnostic (stderr is shared) and returns non-zero,
    # and the caller records the failure via `|| knob_ok=0`.
    echo "check-instructions: ERROR: threshold knob '$key' is absent (config-get exit $rc); cannot measure fail-loud" >&2
    return 1
  fi
  case "$val" in
    '' | *[!0-9]*)
      echo "check-instructions: ERROR: threshold knob '$key' is not a non-negative integer: '$val'" >&2
      return 1
      ;;
  esac
  printf '%s' "$val"
}

knob_ok=1
t_skill_warn="$(getknob instruction_budget_skill_warn)" || knob_ok=0
t_skill_error="$(getknob instruction_budget_skill_error)" || knob_ok=0
t_doc_warn="$(getknob instruction_budget_doctrine_warn)" || knob_ok=0
t_doc_error="$(getknob instruction_budget_doctrine_error)" || knob_ok=0
t_sl_warn="$(getknob instruction_budget_startload_warn)" || knob_ok=0
t_sl_error="$(getknob instruction_budget_startload_error)" || knob_ok=0
t_cl_warn="$(getknob instruction_budget_closure_warn)" || knob_ok=0
t_cl_error="$(getknob instruction_budget_closure_error)" || knob_ok=0
t_inj_warn="$(getknob instruction_budget_injected_warn)" || knob_ok=0
# Headroom floors (instruction-headroom D-2, REQ-A1.1, REQ-D1.1): one per
# budgeted class, in the class order skill / doctrine / start-load / closure. A
# missing or non-numeric floor knob aborts fail-loud exactly like a budget knob.
t_skill_floor="$(getknob instruction_budget_skill_floor)" || knob_ok=0
t_doc_floor="$(getknob instruction_budget_doctrine_floor)" || knob_ok=0
t_sl_floor="$(getknob instruction_budget_startload_floor)" || knob_ok=0
t_cl_floor="$(getknob instruction_budget_closure_floor)" || knob_ok=0

# A missing/non-numeric knob is fail-loud: without the thresholds no honest
# measurement is possible, so stop here (an input that cannot be measured is
# never counted as under budget, REQ-B1.8).
if [ "$knob_ok" -ne 1 ]; then
  echo "check-instructions: aborting — threshold knobs could not be read" >&2
  exit 1
fi

# Manifest-completeness assertion toggle (REQ-A1.2): a boolean knob, distinct
# from the numeric thresholds above. When on, every skills/*/SKILL.md must
# declare a doctrine manifest (asserted after the skill walk below), so a
# manifest-less skill cannot silently under-report its start-load once manifests
# are the corpus norm — the assertion wired in at Task 3, when the manifests
# land. Absent in every config layer it defaults OFF (an adopter not yet on the
# manifest convention is not forced into it; planwright's own config/defaults.yml
# sets it true). A present but non-boolean value is fail-loud (REQ-B1.8), read
# through config-get like the numeric knobs so overlay layering applies.
# getbool runs in a command substitution, so — like getknob — it cannot set the
# parent's status; it prints the resolved 0/1 on stdout, prints its own fail-loud
# diagnostics to the shared stderr (config-get's own stderr is suppressed by the
# 2>/dev/null on the invocations below), and returns non-zero on a fail-loud
# condition. The caller records the failure via `|| completeness_knob_ok=0`.
getbool() {
  # getbool <key> -> echoes 1 (true) / 0 (false or absent); returns 0 normally,
  # 1 on a fail-loud condition (a present but non-boolean value, or a read
  # failure). Absent in every layer is NOT an error (the caller's default is OFF).
  bk="$1"
  if [ ! -x "$config_get" ]; then
    echo "check-instructions: ERROR: config-get.sh missing or not executable at $config_get" >&2
    echo 0
    return 1
  fi
  if [ "$fixture_mode" -eq 1 ]; then
    bval="$(
      PLANWRIGHT_CONFIG_DEFAULTS="$config_defaults" \
        PLANWRIGHT_REPO_ROOT="$root" \
        CLAUDE_PLUGIN_ROOT="" CLAUDE_PLUGIN_DATA="" \
        PLANWRIGHT_ADOPTER_OVERLAY="$root/.no-adopter-overlay" \
        PLANWRIGHT_LOCAL_CONFIG="" PLANWRIGHT_ROOT="" \
        "$config_get" "$bk" 2>/dev/null
    )"
    brc=$?
  else
    bval="$(
      PLANWRIGHT_CONFIG_DEFAULTS="$config_defaults" \
        PLANWRIGHT_REPO_ROOT="$root" \
        "$config_get" "$bk" 2>/dev/null
    )"
    brc=$?
  fi
  # config-get exit 3 = key absent in every layer (a normal, non-error state for
  # a boolean toggle); any other non-zero is a real read failure surfaced loud.
  if [ "$brc" -eq 3 ]; then
    echo 0
    return 0
  fi
  if [ "$brc" -ne 0 ]; then
    echo "check-instructions: ERROR: boolean knob '$bk' could not be read (config-get exit $brc)" >&2
    echo 0
    return 1
  fi
  case "$bval" in
    true)
      echo 1
      return 0
      ;;
    false)
      echo 0
      return 0
      ;;
    *)
      echo "check-instructions: ERROR: boolean knob '$bk' is not a boolean (true|false): '$bval'" >&2
      echo 0
      return 1
      ;;
  esac
}
completeness_knob_ok=1
manifest_completeness_required="$(getbool instruction_manifest_completeness_required)" \
  || completeness_knob_ok=0
if [ "$completeness_knob_ok" -ne 1 ]; then
  # A present-but-non-boolean toggle is a deterministic malformed input: fail
  # loud rather than silently defaulting the assertion off (REQ-B1.8).
  status=1
fi

########################################################################
# Suppression list — permanent exemptions, transitional allowances, standing
# declared exceptions, and raise rationales.
# Grammar (pipe-delimited, one entry per non-blank/non-comment line):
#   exempt|<path>|<reason>
#       permanent per-file-floor exemption ONLY (never start-load/closure).
#   pending-diet|<budget>|<target>|Task <N>|<reason>
#       transitional allowance; <budget> = file | start-load | closure;
#       <target> = a file path (file) or a skill name (start-load/closure).
#   declared-exception|<surface>|<reason>
#       standing exception (instruction-headroom D-11, REQ-D1.6) excusing exactly
#       the warning it names — a below-target warning (whose <surface> is the key
#       the warning prints) or a use-site warning (<surface> = use-site:<skill>/
#       <doc>); never a floor-breach. A stale entry is a cleanup warning, not
#       an error.
#   raise|<knob>|<value>|<reason>
#       the recorded rationale for a budget raise (instruction-headroom D-12,
#       REQ-A1.4): required when an effective instruction_budget_*_warn / *_error
#       knob exceeds its shipped core default; <value> matches the effective
#       value. A raise with no matching entry, an absent/unreadable baseline, or
#       a stale raise| entry is a fail-closed error.
# A reason-less entry of any form is an error; an unparseable line is an error
# (REQ-B1.3, REQ-B1.8). Content is data, never evaluated (REQ-B1.9).
########################################################################
exempt_paths=""                # permanent per-file exemptions (newline-separated paths)
exempt_reasons=""              # "path\treason" records for echoing
pd_file_paths=""               # transitional per-file allowances (paths)
pd_startload=""                # transitional start-load allowances (skill names)
pd_closure=""                  # transitional closure allowances (skill names)
pd_tasks=""                    # "<budget>\t<target>\t<task>" — the allowance's Task field (REQ-D1.2)
declared_exception_surfaces="" # standing below-target/use-site exceptions (keys)
declared_exception_reasons=""  # "surface\treason" records for echoing
declared_exception_used=""     # surface keys whose named warning fired this run
raise_entries=""               # "knob\tvalue\treason" raise rationales

in_list() {
  # in_list <needle> <newline-list> -> 0 if present
  needle="$1"
  list="$2"
  case "
$list
" in
    *"
$needle
"*) return 0 ;;
    *) return 1 ;;
  esac
}

pd_task_for() {
  # pd_task_for <budget> <target> -> prints the pending-diet allowance's Task
  # field (REQ-D1.2, D-8), or nothing if the target has no allowance of that
  # budget class. Data-only: the stored task string is never evaluated.
  _pdb="$1"
  _pdt="$2"
  case "
$pd_tasks
" in
    *"
$_pdb	$_pdt	"*)
      _pdrest="${pd_tasks#*"
$_pdb	$_pdt	"}"
      printf '%s' "${_pdrest%%
*}"
      ;;
  esac
}

if [ -f "$exemptions_file" ]; then
  # Read as data; IFS='|' splits fields, read -r never interprets backslashes,
  # and no field is ever expanded or executed.
  while IFS= read -r raw || [ -n "$raw" ]; do
    case "$raw" in
      '' | '#'*) continue ;;
    esac
    form="${raw%%|*}"
    rest="${raw#*|}"
    case "$form" in
      exempt)
        path="${rest%%|*}"
        reason="${rest#*|}"
        if [ "$path" = "$rest" ] || [ -z "$path" ]; then
          err "malformed exemption entry (expected exempt|<path>|<reason>): $raw"
          continue
        fi
        if [ -z "$reason" ] || [ "$reason" = "$rest" ]; then
          err "exemption for '$path' has no reason (a recorded reason is required)"
          continue
        fi
        exempt_paths="$exempt_paths
$path"
        exempt_reasons="$exempt_reasons
$path	$reason"
        ;;
      pending-diet)
        budget="${rest%%|*}"
        rest2="${rest#*|}"
        target="${rest2%%|*}"
        rest3="${rest2#*|}"
        task="${rest3%%|*}"
        reason="${rest3#*|}"
        if [ "$budget" = "$rest" ] || [ "$target" = "$rest2" ] \
          || [ "$task" = "$rest3" ] || [ -z "$budget" ] || [ -z "$target" ] \
          || [ -z "$task" ]; then
          err "malformed pending-diet entry (expected pending-diet|<budget>|<target>|Task N|<reason>): $raw"
          continue
        fi
        if [ -z "$reason" ] || [ "$reason" = "$rest3" ]; then
          err "pending-diet allowance for '$target' has no reason (a recorded reason is required)"
          continue
        fi
        case "$budget" in
          file) pd_file_paths="$pd_file_paths
$target" ;;
          start-load) pd_startload="$pd_startload
$target" ;;
          closure) pd_closure="$pd_closure
$target" ;;
          *)
            err "unknown pending-diet budget class '$budget' (expected file|start-load|closure): $raw"
            continue
            ;;
        esac
        # Record the allowance's Task field for the audit surface (REQ-D1.2);
        # only reached for a valid budget class (the unknown arm `continue`s).
        pd_tasks="$pd_tasks
$budget	$target	$task"
        ;;
      declared-exception)
        surface="${rest%%|*}"
        reason="${rest#*|}"
        if [ "$surface" = "$rest" ] || [ -z "$surface" ]; then
          err "malformed declared-exception entry (expected declared-exception|<surface>|<reason>): $(sanitize_printable "$raw" "?")"
          continue
        fi
        if [ -z "$reason" ] || [ "$reason" = "$rest" ]; then
          err "declared-exception for '$(sanitize_printable "$surface" "?")' has no reason (a recorded reason is required)"
          continue
        fi
        declared_exception_surfaces="$declared_exception_surfaces
$surface"
        declared_exception_reasons="$declared_exception_reasons
$surface	$reason"
        ;;
      raise)
        knob="${rest%%|*}"
        rest2="${rest#*|}"
        value="${rest2%%|*}"
        reason="${rest2#*|}"
        if [ "$knob" = "$rest" ] || [ "$value" = "$rest2" ] \
          || [ -z "$knob" ] || [ -z "$value" ]; then
          err "malformed raise entry (expected raise|<knob>|<value>|<reason>): $(sanitize_printable "$raw" "?")"
          continue
        fi
        if [ -z "$reason" ] || [ "$reason" = "$rest2" ]; then
          err "raise rationale for '$(sanitize_printable "$knob" "?")' has no reason (a recorded reason is required)"
          continue
        fi
        raise_entries="$raise_entries
$knob	$value	$reason"
        ;;
      *)
        err "unknown suppression form '$(sanitize_printable "$form" "?")' (expected exempt|pending-diet|declared-exception|raise): $(sanitize_printable "$raw" "?")"
        continue
        ;;
    esac
  done <"$exemptions_file"
fi

########################################################################
# Raise-rationale enforcement (instruction-headroom D-12, REQ-A1.4). A budget
# raise — an effective (layered) instruction_budget_*_warn / *_error value above
# its shipped core default — must carry a matching raise|<knob>|<value>|<reason>
# record. A silent raise (no matching entry), an absent or unreadable core
# baseline, or a stale raise| entry (its knob at/below the core default, or
# unknown) is a fail-closed guard error. Floor knobs (*_floor) are protective and
# excluded by suffix. The core baseline is read directly from config/defaults.yml
# (the core layer only, no config-get/overlay resolution — see core_baseline
# below), a fixed set of reads that does not scale with the corpus.
########################################################################
raise_governed_knobs="instruction_budget_skill_warn instruction_budget_skill_error instruction_budget_doctrine_warn instruction_budget_doctrine_error instruction_budget_startload_warn instruction_budget_startload_error instruction_budget_closure_warn instruction_budget_closure_error instruction_budget_injected_warn"

# effective_knob <knob> -> echo the effective (layered) value already read above;
# returns 1 for a knob outside the governed set.
effective_knob() {
  case "$1" in
    instruction_budget_skill_warn) printf '%s' "$t_skill_warn" ;;
    instruction_budget_skill_error) printf '%s' "$t_skill_error" ;;
    instruction_budget_doctrine_warn) printf '%s' "$t_doc_warn" ;;
    instruction_budget_doctrine_error) printf '%s' "$t_doc_error" ;;
    instruction_budget_startload_warn) printf '%s' "$t_sl_warn" ;;
    instruction_budget_startload_error) printf '%s' "$t_sl_error" ;;
    instruction_budget_closure_warn) printf '%s' "$t_cl_warn" ;;
    instruction_budget_closure_error) printf '%s' "$t_cl_error" ;;
    instruction_budget_injected_warn) printf '%s' "$t_inj_warn" ;;
    *) return 1 ;;
  esac
}

# core_baseline <knob> -> echo the shipped core-default integer, read directly
# from config/defaults.yml (the core layer only — the "shipped core default" is
# defined as the value in that file, D-12, so no overlay resolution is wanted; a
# direct read also avoids a per-run config-get fork chain, keeping the
# guard-performance invariant). Returns 1 on an absent/unreadable file or key or
# a non-integer value (a fail-closed condition the caller surfaces). The flat-YAML
# extraction mirrors config-get's get_value. <knob> is charset-guarded before it
# reaches the grep/sed pattern (data is not code, REQ-B1.9); callers only pass the
# governed knob names, but the guard is kept for defense in depth.
core_baseline() {
  case "$1" in
    [a-z]*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[!a-z0-9_]*) return 1 ;;
  esac
  [ -r "$config_defaults" ] || return 1
  grep -q "^$1:" "$config_defaults" 2>/dev/null || return 1
  _cbv="$(sed -n "s/^$1:[[:space:]]*//p" "$config_defaults" \
    | head -n 1 \
    | sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' \
      -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/")"
  case "$_cbv" in
    '' | *[!0-9]*) return 1 ;;
  esac
  printf '%s' "$_cbv"
}

# Per-knob: an effective value over the core default needs a matching raise entry.
for rk in $raise_governed_knobs; do
  reff="$(effective_knob "$rk")"
  if rbase="$(core_baseline "$rk")"; then
    if [ "$reff" -gt "$rbase" ]; then
      rfound=0
      while IFS="$(printf '\t')" read -r rek rev _rer; do
        [ -n "$rek" ] || continue
        if [ "$rek" = "$rk" ] && [ "$rev" = "$reff" ]; then rfound=1; fi
      done <<EOF
$raise_entries
EOF
      if [ "$rfound" -ne 1 ]; then
        err "raise-rationale: '$rk' effective value $reff exceeds its core default $rbase with no matching 'raise|$rk|$reff|<reason>' entry (a silent raise)"
      fi
    fi
  else
    err "raise-rationale: core-default baseline for '$rk' is absent or unreadable — a raise cannot be validated fail-closed"
  fi
done

# Per-entry: a raise entry whose knob is unknown, or is not raised above its core
# default, is stale (REQ-A1.4).
while IFS="$(printf '\t')" read -r rek rev _rer; do
  [ -n "$rek" ] || continue
  case " $raise_governed_knobs " in
    *" $rek "*) ;;
    *)
      err "raise-rationale: stale raise| entry names an unknown knob '$(sanitize_printable "$rek" "?")' (only instruction_budget_*_warn / *_error knobs are raisable; floor knobs are protective)"
      continue
      ;;
  esac
  rbase="$(core_baseline "$rek")" || continue # the per-knob loop already surfaced this
  reff="$(effective_knob "$rek")"
  if [ "$reff" -le "$rbase" ]; then
    err "raise-rationale: stale raise| entry for '$rek' — its effective value $reff is at or below the core default $rbase; remove the entry that un-raised it"
  fi
done <<EOF
$raise_entries
EOF

########################################################################
# Closeout direction (REQ-D1.4, Task 8). With --closeout, any surviving
# transitional `pending-diet` allowance is a hard error: after the diets, the
# suppression list must carry only permanent exemptions (REQ-B1.3a). Because a
# start-load or reachable-closure offender can be carried ONLY by such an
# allowance (REQ-B1.3b), this catches a lingering start-load/closure offender,
# not just a per-file one. Off by default so the transitional mechanism keeps a
# diet's CI green while it is in flight; planwright's `check:instructions` passes
# --closeout because its own retrofit is complete.
########################################################################
closeout_err() {
  # closeout_err <newline-list> <budget-label>. Iterate the parsed allowance
  # targets line by line (never word-split or glob-expand the data, REQ-B1.9),
  # in the current shell so err's status=1 propagates (a here-doc redirect adds
  # no subshell). An empty list yields a single empty line, skipped below.
  _list="$1"
  _label="$2"
  while IFS= read -r _target; do
    [ -n "$_target" ] || continue
    err "closeout (REQ-D1.4): $_label pending-diet allowance still present for '$_target' — a diet must remove its own allowance; only permanent exemptions may remain at closeout"
  done <<EOF
$_list
EOF
}
if [ "$closeout" -eq 1 ]; then
  closeout_err "$pd_file_paths" "per-file"
  closeout_err "$pd_startload" "start-load (skill)"
  closeout_err "$pd_closure" "closure (skill)"
fi

########################################################################
# Per-file walk + per-skill start-load / closure, in a single pass per file so
# each file's word/line count is taken exactly once (guard-performance risk R10:
# memoized counts, no O(skills*docs) re-reads). Skills use the skill thresholds
# and additionally get their manifest-derived start-load/closure; doctrine files
# use the doctrine thresholds. doctrine/README.md is excluded (REQ-A1.1).
########################################################################
# Measure EVERY instruction file in ONE awk pass (guard-performance risk R10: no
# per-file fork chain), caching the word/line counts in parallel arrays keyed by
# repo-relative path. Every later lookup — per-file floors, a skill's body, a
# manifest doc's contribution to start-load/closure — is a fork-free array scan.
mpaths=()
mwords=()
mlines=()
files_to_measure=()
if [ -d "$skills_dir" ]; then
  for skill_md in "$skills_dir"/*/SKILL.md; do
    [ -f "$skill_md" ] && files_to_measure+=("$skill_md")
  done
fi
if [ -d "$doctrine_dir" ]; then
  for doc in "$doctrine_dir"/*.md; do
    [ -f "$doc" ] || continue
    [ "${doc##*/}" = "README.md" ] && continue
    files_to_measure+=("$doc")
  done
fi
if [ "${#files_to_measure[@]}" -gt 0 ]; then
  measured="$(awk '
    FNR == 1 { if (f != "") print f "\t" w "\t" l; f = FILENAME; w = 0; l = 0 }
    { w += NF; l++ }
    END { if (f != "") print f "\t" w "\t" l }
  ' "${files_to_measure[@]}")"
  awk_rc=$?
  # Fail loud if the measure pass could not read an instruction file: awk skips
  # an unopenable file (printing to stderr) and exits non-zero, so `measured`
  # would hold only partial results and the missing file would fall through the
  # cache to a 0-word score — silently under budget. An input that cannot be
  # measured is never counted as under budget (REQ-B1.8), symmetric with the
  # knob fail-loud abort above.
  if [ "$awk_rc" -ne 0 ]; then
    echo "check-instructions: ERROR: one or more instruction files could not be measured (awk exit $awk_rc); an unmeasurable file is never scored as under budget (REQ-B1.8)" >&2
    exit 1
  fi
  while IFS="$(printf '\t')" read -r mp mw ml; do
    [ -n "$mp" ] || continue
    mpaths+=("$mp")
    mwords+=("$mw")
    mlines+=("$ml")
  done <<EOF
$measured
EOF
fi

# mget <abs-path> -> sets MW and ML from the cache; returns 1 if not measured.
mget() {
  _i=0
  _n="${#mpaths[@]}"
  while [ "$_i" -lt "$_n" ]; do
    if [ "${mpaths[$_i]}" = "$1" ]; then
      MW="${mwords[$_i]}"
      ML="${mlines[$_i]}"
      return 0
    fi
    _i=$((_i + 1))
  done
  return 1
}

# classify <words> <warn> <error> -> sets _STATE to ok|WARN|ERROR (boundary >=).
# A global write, not an echo, to avoid a subshell fork per file.
classify() {
  if [ "$1" -ge "$3" ]; then
    _STATE=ERROR
  elif [ "$1" -ge "$2" ]; then
    _STATE=WARN
  else
    _STATE=ok
  fi
}

# headroom_check <words> <error-threshold> <floor> <surface-key> — emit the
# floor-breach or below-target warning for a floored surface (D-2, D-11,
# REQ-D1.1, REQ-D1.6). margin = error - words. A margin strictly below the floor
# is an unsuppressible floor-breach warning; a margin at or above the floor but
# below twice it (the restoration target) is a below-target warning, which a
# matching declared-exception excuses (the entry is then marked used so a stale
# one is reported later). Never called for a permanently exempt surface — an
# exempt doc carries no headroom floor (REQ-D1.1) — nor an unmeasured skill. Both
# warnings are warnings only: they never touch the exit code. The surface key is
# sanitized before it reaches the terminal (echo discipline).
headroom_check() {
  _hcm=$(($2 - $1))
  if [ "$_hcm" -lt "$3" ]; then
    warn "floor-breach: $(sanitize_printable "$4" "?") margin=$_hcm below headroom floor $3 (error threshold $2, words $1)"
  elif [ "$_hcm" -lt $(($3 * 2)) ]; then
    if in_list "$4" "$declared_exception_surfaces"; then
      declared_exception_used="$declared_exception_used
$4"
    else
      warn "below-target: $(sanitize_printable "$4" "?") margin=$_hcm below restoration target $(($3 * 2)) (headroom floor $3, error threshold $2, words $1)"
    fi
  fi
}

record_perfile() {
  # record_perfile <relpath> <words> <lines> <warn> <error> <kind> <floor>
  rel="$1"
  words="$2"
  lines="$3"
  wt="$4"
  et="$5"
  floor="$7"
  classify "$words" "$wt" "$et"
  state="$_STATE"
  suppress=""
  if in_list "$rel" "$exempt_paths"; then
    suppress="exempt"
  elif in_list "$rel" "$pd_file_paths"; then
    suppress="pending-diet"
  fi
  # Per-file headroom (D-2, REQ-D1.1): a permanently exempt doc carries no floor;
  # every other floored file gets the floor-breach / below-target check.
  if [ "$suppress" != exempt ]; then
    headroom_check "$words" "$et" "$floor" "$rel"
  fi
  # The pending-diet allowance's Task field rides the audit surface (REQ-D1.2,
  # D-8); a non-allowance file carries the literal `none`. A tab is IFS
  # whitespace, so an empty interior field would collapse under the audit
  # reader's `read` — the `none` sentinel keeps every column aligned.
  pd_task=none
  if [ "$suppress" = pending-diet ]; then
    pd_task="$(pd_task_for file "$rel")"
    [ -n "$pd_task" ] || pd_task=none
  fi
  # Write the suppression field as a literal `none` when empty for the same
  # IFS-collapse reason.
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$words" "$rel" "$lines" "$state" "${suppress:-none}" "$6" "$pd_task" >>"$perfile_list"

  if [ "$state" = ERROR ]; then
    # Every over-floor file is an offender and goes on the shortlist (it needs a
    # diet plan, REQ-A1.3), whether or not a suppression currently keeps CI
    # green; suppression governs only the exit code, not offender status.
    printf 'per-file\t%s\t%s\t%s\t%s\t%s\n' "$rel" "$words" "$et" "${suppress:-unsuppressed}" "$pd_task" >>"$shortlist"
    if [ "$suppress" = exempt ]; then
      # echo the standing rationale so a reviewer sees why the floor is waived.
      ereason=""
      case "
$exempt_reasons
" in
        *"
$rel	"*)
          ereason="${exempt_reasons#*"
$rel	"}"
          ereason="${ereason%%
*}"
          ;;
      esac
      warn "per-file floor over budget but permanently exempt: $rel ($words words) [floor $et] — reason: $ereason"
    elif [ "$suppress" = pending-diet ]; then
      warn "per-file floor over budget, pending-diet allowance in place: $rel ($words words) [floor $et]"
    else
      err "per-file floor over budget: $rel ($words words >= $et)"
    fi
  elif [ "$state" = WARN ]; then
    warn "per-file floor warn: $rel ($words words >= $wt)"
  fi
}

# resolve_doc: charset-validate the name BEFORE any path is formed (REQ-B1.9),
# then confine resolution to the doctrine root by looking the doc up in the
# measured-file cache (every doctrine/*.md was measured above). On success sets
# DOC_W to the doc's word count and returns 0; returns 1 unresolvable; returns 2
# invalid name (traversal-safe — the name never reaches a path unless it matched
# the strict kebab-case identifier charset).
resolve_doc() {
  name="$1"
  case "$name" in
    [a-z0-9]*) ;;
    *) return 2 ;;
  esac
  case "$name" in
    *[!a-z0-9-]*) return 2 ;;
  esac
  if mget "$doctrine_dir/$name.md"; then
    DOC_W="$MW"
    return 0
  fi
  # An empty (zero-line) doc exists but is absent from the measure cache; it
  # resolves and contributes zero words.
  if [ -f "$doctrine_dir/$name.md" ]; then
    DOC_W=0
    return 0
  fi
  return 1
}

# The manifest parser: emit one record per column-zero Doctrine: line outside a
# fenced block. Class and name are validated here so a malformed entry is caught
# fail-loud (REQ-B1.8) and a bad name never reaches a path (REQ-B1.9). Output:
#   OK <class> <name>
#   BAD <verbatim line>
# shellcheck disable=SC2016 # a single-quoted awk program; $0/$fields are awk's
parse_manifest='
  BEGIN { fence = 0; fence_char = "" }
  {
    line = $0
    # fenced-code tracking: a ``` or ~~~ marker at column zero opens a block, and
    # only a marker of the SAME fence character closes it. Treating ``` and ~~~ as
    # one interchangeable toggle would let a different-type fence shown as content
    # (the idiomatic way to display a fence example, e.g. a ```-block inside a ~~~
    # wrapper) close the block early and expose the enclosed Doctrine: example
    # lines as live entries — a false manifest error or a start-load inflation on
    # documentation.
    if (fence == 0) {
      if (line ~ /^```/) { fence = 1; fence_char = "`"; next }
      if (line ~ /^~~~/) { fence = 1; fence_char = "~"; next }
    } else {
      if (fence_char == "`" && line ~ /^```/) { fence = 0; fence_char = "" }
      else if (fence_char == "~" && line ~ /^~~~/) { fence = 0; fence_char = "" }
      next
    }
    # only column-zero lines are entries; indented/quoted lines never are.
    if (line ~ /^[ \t]/) next
    if (line ~ /^Doctrine:/) {
      rest = line
      sub(/^Doctrine:/, "", rest)
      # class
      n = split(rest, tok, /[ \t]+/)
      # tok[1] is empty (leading space); class is first non-empty token.
      ci = 1
      while (ci <= n && tok[ci] == "") ci++
      cls = (ci <= n) ? tok[ci] : ""
      ni = ci + 1
      while (ni <= n && tok[ni] == "") ni++
      nm = (ni <= n) ? tok[ni] : ""
      # after the name, only an optional (parenthesized note) may follow.
      # rebuild the tail after the name token.
      tail = ""
      for (k = ni + 1; k <= n; k++) if (tok[k] != "") tail = tail " " tok[k]
      gsub(/^[ \t]+|[ \t]+$/, "", tail)
      okclass = (cls == "run-start" || cls == "point-of-use")
      okname = (nm ~ /^[a-z0-9][a-z0-9-]*$/)
      oktail = (tail == "" || tail ~ /^\(.*\)$/)
      if (okclass && okname && oktail) {
        print "OK " cls " " nm
      } else {
        print "BAD " line
      }
      next
    }
    # a column-zero case-variant near-miss (doctrine:, DOCTRINE:) is malformed,
    # never silently dropped (it would under-report the start-load).
    if (tolower(line) ~ /^doctrine:/) { print "BAD " line }
  }
'

# manifest-completeness assertion (REQ-A1.2): collect the skills that declare no
# doctrine manifest (zero entry lines); asserted after the walk if the knob is on.
manifestless_skills=""
if [ -d "$skills_dir" ]; then
  for skill_md in "$skills_dir"/*/SKILL.md; do
    [ -f "$skill_md" ] || continue
    sname="${skill_md%/SKILL.md}"
    sname="${sname##*/}"
    # A zero-line (empty) file never reaches the measure awk's FNR==1 flush, so
    # it is absent from the cache; score it 0/0 rather than reuse a stale value.
    MW=0
    ML=0
    mget "$skill_md" || true
    body_words="$MW"
    record_perfile "skills/$sname/SKILL.md" "$MW" "$ML" \
      "$t_skill_warn" "$t_skill_error" skill "$t_skill_floor"
    startload="$body_words"
    closure="$body_words"
    # Uncapped ("actual") twins of the two aggregates. When a permanently exempt
    # doc is capped (D-4, below) the charged aggregate diverges from the honest
    # sum; --audit prints the actual beside the charged so the full load stays
    # visible (REQ-B1.2). With no cap in play they stay equal.
    startload_actual="$body_words"
    closure_actual="$body_words"
    seen_docs=""
    malformed=0
    unresolved=0
    mani_entries=0

    while IFS= read -r rec; do
      [ -n "$rec" ] || continue
      # every parsed Doctrine: line (OK or BAD) means the skill declared a
      # manifest — a malformed entry is still a declaration, so a garbled-only
      # manifest is not additionally flagged manifest-less (its BAD error stands).
      mani_entries=$((mani_entries + 1))
      tag="${rec%% *}"
      if [ "$tag" = BAD ]; then
        err "malformed doctrine manifest entry in skills/$sname/SKILL.md: ${rec#BAD }"
        malformed=1
        continue
      fi
      # rec = "OK <class> <name>"
      body="${rec#OK }"
      cls="${body%% *}"
      name="${body#* }"
      if in_list "$name" "$seen_docs"; then
        err "duplicate doctrine manifest doc '$name' in skills/$sname/SKILL.md"
        malformed=1
        continue
      fi
      seen_docs="$seen_docs
$name"
      resolve_doc "$name"
      rc=$?
      if [ "$rc" -eq 2 ]; then
        err "invalid doctrine manifest doc name in skills/$sname/SKILL.md: '$name'"
        malformed=1
        continue
      fi
      if [ "$rc" -eq 1 ]; then
        err "unresolvable doctrine reference '$name' in skills/$sname/SKILL.md (no doctrine/$name.md)"
        unresolved=1
        continue
      fi
      dw="$DOC_W"
      # Capped charge for permanently exempt docs (D-4, REQ-B1.1, REQ-B1.2): a
      # doc carrying a standing per-file exemption is charged into the aggregates
      # at min(actual, its per-file error threshold), so a dependent pays the
      # budgeted size, not the overage (spec-format.md charges the doctrine
      # error threshold, not its larger actual). Manifest docs are always
      # doctrine/*.md, so the per-file error threshold is t_doc_error. We reach
      # here only on a resolve_doc success, so the D-4 "resolves and measures"
      # precondition holds; a missing/unresolvable doc took the unresolved path
      # above, and a malformed or reason-less `exempt|` entry never entered
      # exempt_paths (the parser dropped it), so its full charge still cascades —
      # doubly fail-closed. The actual words feed the *_actual twins for the audit.
      charged="$dw"
      if in_list "doctrine/$name.md" "$exempt_paths" && [ "$dw" -gt "$t_doc_error" ]; then
        charged="$t_doc_error"
      fi
      if [ "$cls" = run-start ]; then
        startload=$((startload + charged))
        closure=$((closure + charged))
        startload_actual=$((startload_actual + dw))
        closure_actual=$((closure_actual + dw))
      else
        closure=$((closure + charged))
        closure_actual=$((closure_actual + dw))
      fi
    done <<EOF
$(awk "$parse_manifest" "$skill_md")
EOF

    # A here-doc-fed while loop runs in the current shell, so mani_entries
    # survives it: zero parsed entries means this skill declares no manifest.
    if [ "$mani_entries" -eq 0 ]; then
      manifestless_skills="$manifestless_skills
$sname"
    fi

    if [ "$malformed" -eq 1 ] || [ "$unresolved" -eq 1 ]; then
      # A skill whose manifest cannot be trusted is not scored under budget.
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$sname" "$startload" "$closure" \
        "unmeasured" "unmeasured" "$startload_actual" "$closure_actual" >>"$skill_list"
      continue
    fi

    classify "$startload" "$t_sl_warn" "$t_sl_error"
    sl_state="$_STATE"
    classify "$closure" "$t_cl_warn" "$t_cl_error"
    cl_state="$_STATE"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$sname" "$startload" "$closure" \
      "$sl_state" "$cl_state" "$startload_actual" "$closure_actual" >>"$skill_list"

    if [ "$sl_state" = ERROR ]; then
      if in_list "$sname" "$pd_startload"; then
        sl_task="$(pd_task_for start-load "$sname")"
        [ -n "$sl_task" ] || sl_task=none
        printf 'start-load\t%s\t%s\t%s\t%s\t%s\n' "$sname" "$startload" "$t_sl_error" "pending-diet" "$sl_task" >>"$shortlist"
        warn "start-load over budget, pending-diet allowance in place: $sname ($startload >= $t_sl_error)"
      else
        printf 'start-load\t%s\t%s\t%s\t%s\t%s\n' "$sname" "$startload" "$t_sl_error" "unsuppressed" "none" >>"$shortlist"
        err "start-load over budget: $sname ($startload words >= $t_sl_error)"
      fi
    elif [ "$sl_state" = WARN ]; then
      warn "start-load warn: $sname ($startload words >= $t_sl_warn)"
    fi

    if [ "$cl_state" = ERROR ]; then
      if in_list "$sname" "$pd_closure"; then
        cl_task="$(pd_task_for closure "$sname")"
        [ -n "$cl_task" ] || cl_task=none
        printf 'closure\t%s\t%s\t%s\t%s\t%s\n' "$sname" "$closure" "$t_cl_error" "pending-diet" "$cl_task" >>"$shortlist"
        warn "closure over budget, pending-diet allowance in place: $sname ($closure >= $t_cl_error)"
      else
        printf 'closure\t%s\t%s\t%s\t%s\t%s\n' "$sname" "$closure" "$t_cl_error" "unsuppressed" "none" >>"$shortlist"
        err "closure over budget: $sname ($closure words >= $t_cl_error)"
      fi
    elif [ "$cl_state" = WARN ]; then
      warn "closure warn: $sname ($closure words >= $t_cl_warn)"
    fi

    # Aggregate headroom (D-2, REQ-D1.1): floor-breach / below-target for the
    # start-load and reachable-closure surfaces of a measured skill.
    headroom_check "$startload" "$t_sl_error" "$t_sl_floor" "start-load:$sname"
    headroom_check "$closure" "$t_cl_error" "$t_cl_floor" "closure:$sname"
  done

  # Manifest-completeness assertion (REQ-A1.2): once the manifest convention is
  # the corpus norm, a skill declaring no manifest silently under-reports its
  # start-load (its run-start docs go uncounted). When the toggle is on, that is
  # an error, distinct from the malformed-manifest error (REQ-B1.8) and from the
  # scoring rule that a manifest-less skill is still scored body-only.
  if [ "$manifest_completeness_required" -eq 1 ]; then
    for ml in $manifestless_skills; do
      [ -n "$ml" ] || continue
      err "manifest-completeness assertion: skills/$ml/SKILL.md declares no doctrine manifest (every skill must declare one; set instruction_manifest_completeness_required=false to disable)"
    done
  fi
fi

# Doctrine rule docs: per-file floor only (they carry no manifest of their own;
# their contribution to a skill's start-load/closure is counted above via that
# skill's manifest). doctrine/README.md is excluded (REQ-A1.1).
if [ -d "$doctrine_dir" ]; then
  for doc in "$doctrine_dir"/*.md; do
    [ -f "$doc" ] || continue
    base="${doc##*/}"
    [ "$base" = "README.md" ] && continue
    # A zero-line (empty) doc is absent from the measure cache; report it as a
    # 0-word row rather than dropping it ("every instruction file", REQ-A1.1),
    # symmetric with the skill walk's empty-file handling.
    MW=0
    ML=0
    mget "$doc" || true
    record_perfile "doctrine/$base" "$MW" "$ML" \
      "$t_doc_warn" "$t_doc_error" doctrine "$t_doc_floor"
  done
fi

########################################################################
# Injected-context hooks (REQ-A1.4, REQ-B1.7). Discovery is over hooks.json
# registered commands; a hook is injected-context iff its script emits
# additionalContext / hookSpecificOutput. Static prose is extracted from
# heredoc bodies and multi-line quoted-string assignments, excluding
# interpolation lines. The script is read, never executed. This surface never
# fails the check: over-floor -> warning; unextractable -> parse-failure
# warning.
########################################################################
# Extract static injected prose. Emits two lines: "WORDS <n>" and "BLOCK <0|1>"
# (BLOCK 1 iff at least one heredoc/multi-line-quote body was found). An
# interpolation line ($(...), ${...}, or a $name reference) is noted, not
# counted.
# shellcheck disable=SC2016 # a single-quoted awk program; the $-forms are awk's
extract_injected='
  # interpolation forms: $(...), ${...}, a $name reference, and the shell
  # special/positional parameters ($?, $@, $*, $#, $-, $0-$9). A line carrying
  # any of these is runtime-expanded, so it is excluded from the static count
  # (REQ-A1.4). ($$ and $! are not covered — an accepted imprecision on this
  # warn-only surface; over/under-counting here can only shift a warning.)
  function is_interp(s) { return (s ~ /\$\(/ || s ~ /\$\{/ || s ~ /\$[A-Za-z_@*#?0-9-]/) }
  function count_words(s,   m, a) {
    gsub(/^[ \t]+|[ \t]+$/, "", s)
    if (s == "") return 0
    m = split(s, a, /[ \t]+/)
    return m
  }
  BEGIN { mode = 0; total = 0; block = 0; delim = ""; qchar = "" }
  {
    line = $0
    if (mode == 1) {                       # in heredoc
      t = line
      gsub(/^[ \t]+/, "", t)               # <<- strips leading tabs on term
      if (t == delim || line == delim) { mode = 0; next }
      if (!is_interp(line)) total += count_words(line)
      next
    }
    if (mode == 2) {                       # in multi-line quoted string
      idx = index(line, qchar)
      if (idx > 0) {
        prose = substr(line, 1, idx - 1)
        if (!is_interp(prose)) total += count_words(prose)
        mode = 0
        next
      }
      if (!is_interp(line)) total += count_words(line)
      next
    }
    # NORMAL: heredoc opener wins over quoted-assignment detection.
    if (match(line, /<<-?[ \t]*[\047"]?[A-Za-z_][A-Za-z0-9_]*/)) {
      d = substr(line, RSTART, RLENGTH)
      sub(/^<<-?[ \t]*[\047"]?/, "", d)
      delim = d
      mode = 1
      block = 1
      next
    }
    # multi-line double- or single-quoted assignment at column zero:
    # name="...    (no closing quote on this line)
    if (line ~ /^[A-Za-z_][A-Za-z0-9_]*="[^"]*$/) {
      qchar = "\""
      prose = line
      sub(/^[A-Za-z_][A-Za-z0-9_]*="/, "", prose)
      if (!is_interp(prose)) total += count_words(prose)
      mode = 2
      block = 1
      next
    }
    if (line ~ /^[A-Za-z_][A-Za-z0-9_]*=\047[^\047]*$/) {
      qchar = "\047"
      prose = line
      sub(/^[A-Za-z_][A-Za-z0-9_]*=\047/, "", prose)
      if (!is_interp(prose)) total += count_words(prose)
      mode = 2
      block = 1
      next
    }
  }
  END { print "WORDS " total; print "BLOCK " block }
'

scan_injected() {
  [ -f "$hooks_json" ] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq unavailable; injected-context scan skipped (surface is warn-only)"
    return 0
  fi
  cmds="$(jq -r '.hooks // {} | to_entries[]? | .value[]? | .hooks[]? | select(.type=="command") | .command' "$hooks_json" 2>/dev/null)" || {
    warn "hooks.json could not be parsed; injected-context scan skipped (warn-only surface)"
    return 0
  }
  [ -n "$cmds" ] || return 0
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    # Map the command to a script path under $root. Strip quotes, then take the
    # tail after the last brace-close of a ${...} plugin-root reference. Pure
    # string surgery on data — the command is never executed (REQ-B1.9).
    c="${cmd//\"/}"
    c="${c//\'/}"
    case "$c" in
      *'}'*) rel="${c##*\}}" ;;
      *) rel="$c" ;;
    esac
    rel="${rel#/}"
    # Drop any CLI arguments: a registered command may pass flags to the hook
    # (e.g. `<root>/hooks/x.sh --session-start`); the first token is the script
    # path. Without this the hook would resolve to a non-existent path and be
    # silently omitted rather than reported as a row (REQ-A1.4).
    rel="${rel%% *}"
    case "$rel" in
      *..*)
        warn "hook path contains '..' traversal; skipped: $cmd"
        continue
        ;;
    esac
    hook_path="$root/$rel"
    [ -f "$hook_path" ] || continue
    [ -r "$hook_path" ] || continue
    # injected-context iff the script emits additionalContext/hookSpecificOutput.
    grep -Eq 'additionalContext|hookSpecificOutput' "$hook_path" 2>/dev/null || continue

    ex="$(awk "$extract_injected" "$hook_path")"
    iwords="$(printf '%s\n' "$ex" | sed -n 's/^WORDS //p')"
    iblock="$(printf '%s\n' "$ex" | sed -n 's/^BLOCK //p')"
    [ -n "$iwords" ] || iwords=0

    if [ "$iblock" = 0 ]; then
      printf '%s\t%s\t%s\n' "$rel" "$iwords" "parse-failure" >>"$injected_list"
      warn "injected-context hook static prose could not be extracted (parse-failure, warn-only): $rel"
      continue
    fi
    istate=ok
    if [ "$iwords" -ge "$t_inj_warn" ]; then
      istate=WARN
      warn "injected-context static prose over floor: $rel (static=$iwords >= $t_inj_warn)"
    fi
    printf '%s\t%s\t%s\n' "$rel" "$iwords" "$istate" >>"$injected_list"
  done <<EOF
$cmds
EOF
}
scan_injected

########################################################################
# Declared-exception staleness (REQ-D1.6). An entry whose named warning did not
# fire this run is stale — a named cleanup WARNING, never an error: staleness in
# the protective direction nudges, never blocks. Runs after every floor/target
# check has had its chance to mark an entry used. Surface and reason are
# sanitized before echoing (echo discipline).
########################################################################
while IFS= read -r de_surface; do
  [ -n "$de_surface" ] || continue
  if in_list "$de_surface" "$declared_exception_used"; then
    continue
  fi
  de_reason=""
  case "
$declared_exception_reasons
" in
    *"
$de_surface	"*)
      de_reason="${declared_exception_reasons#*"
$de_surface	"}"
      de_reason="${de_reason%%
*}"
      ;;
  esac
  warn "declared-exception cleanup: no live below-target or use-site warning names '$(sanitize_printable "$de_surface" "?")' (reason: $(sanitize_printable "$de_reason" "?")) — remove the stale entry"
done <<EOF
$declared_exception_surfaces
EOF

########################################################################
# --audit report.
########################################################################
if [ "$audit" -eq 1 ]; then
  echo "== Instruction hygiene audit =="
  echo
  echo "Per-file (ranked by words):"
  sort -rn "$perfile_list" | while IFS="$(printf '\t')" read -r w rel l st sup kind tk; do
    tag=""
    [ "$sup" != none ] && tag=" [$sup]"
    # A pending-diet allowance's Task field rides its ranked-report row (REQ-D1.2,
    # D-8), so a Task retag is visible in the audit surface. The field is raw,
    # PR-controllable exemptions-file text, so it is sanitized on echo like every
    # other surfaced untrusted value (REQ-B1.9, echo discipline).
    [ "$tk" != none ] && tag="$tag [$(sanitize_printable "$tk" "?")]"
    # Margin-to-warn / margin-to-error for the floored per-file classes (D-8,
    # REQ-D1.1). A permanently exempt file carries no headroom floor, so it
    # shows no margin columns (its exempt notice stands).
    margins=""
    charged=""
    if [ "$sup" = exempt ]; then
      # Charged-vs-actual (D-4, REQ-B1.2): an exempt doctrine doc over its
      # per-file error threshold is charged min(actual, threshold) into every
      # dependent aggregate; print that charged value beside the actual words=
      # so the honest count and the budgeted charge are both visible on the
      # capped doc's own line. Only doctrine docs feed manifests, so only they
      # are cap-relevant; an exempt file at or under the threshold charges its
      # actual and shows no charged= (min() is a no-op).
      if [ "$kind" = doctrine ] && [ "$w" -gt "$t_doc_error" ]; then
        charged=" charged=$t_doc_error"
      fi
    else
      case "$kind" in
        skill) margins=" margin-to-warn=$((t_skill_warn - w)) margin-to-error=$((t_skill_error - w))" ;;
        doctrine) margins=" margin-to-warn=$((t_doc_warn - w)) margin-to-error=$((t_doc_error - w))" ;;
      esac
    fi
    printf '  words=%s lines=%s %s %s%s%s%s\n' "$w" "$l" "$rel" "$st" "$margins" "$charged" "$tag"
  done
  echo
  echo "Per-skill load:"
  while IFS="$(printf '\t')" read -r name sl cl sls cls sla cla; do
    # Margin-to-warn / margin-to-error for the two floored aggregate classes
    # (D-8, REQ-D1.1); an unmeasured skill (untrusted manifest) shows none.
    slm=""
    clm=""
    # Charged-vs-actual (D-4, REQ-B1.2): when a capped exempt doc made the
    # charged aggregate diverge from the honest sum, print the actual beside it
    # so the aggregate line distinguishes its charged total from the raw load.
    slc=""
    clc=""
    if [ "$sls" != unmeasured ]; then
      slm=" margin-to-warn=$((t_sl_warn - sl)) margin-to-error=$((t_sl_error - sl))"
      [ -n "$sla" ] && [ "$sla" != "$sl" ] && slc=" (actual $sla)"
    fi
    if [ "$cls" != unmeasured ]; then
      clm=" margin-to-warn=$((t_cl_warn - cl)) margin-to-error=$((t_cl_error - cl))"
      [ -n "$cla" ] && [ "$cla" != "$cl" ] && clc=" (actual $cla)"
    fi
    printf '  %s start-load=%s (%s)%s%s closure=%s (%s)%s%s\n' \
      "$name" "$sl" "$sls" "$slc" "$slm" "$cl" "$cls" "$clc" "$clm"
  done <"$skill_list"
  echo
  echo "Injected-context hooks:"
  if [ -s "$injected_list" ]; then
    while IFS="$(printf '\t')" read -r rel iw ist; do
      printf '  %s static=%s %s\n' "$rel" "$iw" "$ist"
    done <"$injected_list"
  else
    echo "  none"
  fi
  echo
  echo "Offender shortlist:"
  if [ -s "$shortlist" ]; then
    while IFS="$(printf '\t')" read -r cls tgt w th sup tk; do
      # A pending-diet allowance's Task field rides its shortlist row (REQ-D1.2,
      # D-8); a non-allowance offender carries the `none` sentinel and no tag.
      # The field is raw, PR-controllable exemptions-file text, sanitized on echo
      # like every other surfaced untrusted value (REQ-B1.9, echo discipline).
      tasktag=""
      [ "$tk" != none ] && tasktag=" [$(sanitize_printable "$tk" "?")]"
      printf '  %s %s (%s words >= %s %s budget) [%s]%s\n' \
        "$cls" "$tgt" "$w" "$th" "$cls" "$sup" "$tasktag"
    done <"$shortlist"
  else
    echo "  none"
  fi
fi

exit "$status"
