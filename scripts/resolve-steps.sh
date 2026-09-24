#!/usr/bin/env bash
# resolve-steps.sh — resolve one attachment point's step list into the chain
# the runner executes there, with provenance, the missing-step decision, and
# the by-layer malformed policy applied before anything runs (custom-steps
# Task 2; REQ-A1.3, REQ-A1.4, REQ-B1.1–B1.6, REQ-C1.1–C1.6, REQ-C1.8,
# REQ-D1.8, REQ-D1.9, REQ-G1.1, REQ-H1.3; D-4, D-5, D-6, D-10, D-17, D-19).
# doctrine/custom-steps.md is the normative home of every rule this script
# applies; this header pins only what that doc delegates here: the output line
# format, the exit codes, the preamble layout, and the prefix quoting.
#
# A point's list is config, read THROUGH config-get.sh (last-layer-wins; the
# --layers mode supplies the shadow and stale-key warnings); the step entries
# are the `steps` data catalog, read THROUGH resolve-catalog.sh (append/union,
# supersede-by-id). This script re-implements neither; it adds the entry and
# list validation, the host resolvability check, the missing-step matrix, and
# the rendering of the fixed context.
#
# Usage:
#   resolve-steps.sh <point> [--explain] [--check] --attended|--unattended
#   resolve-steps.sh <point> --preamble
#   resolve-steps.sh <point> --prefix
#
#   <point>       one of the named points (the rule doc's vocabulary):
#                 pre-implementation pre-ci convergence pre-pr post-pr
#                 pre-ready-flip pre-spec-ready-flip, and the unwired
#                 spec-drafted kickoff-signed-off unit-selected pre-dispatch
#                 post-dispatch unit-halted post-merge orchestrator-idle.
#                 Any other name is a usage error. The list key is
#                 steps_<point> with hyphens as underscores.
#   --attended / --unattended
#                 the attendance axis of the missing-step matrix, passed by
#                 the hosting skill (--unattended exactly when the unit was
#                 launched headless). Exactly one is required in the
#                 resolution modes; neither, or both, is a usage error.
#   --explain     append the provenance and execution fields to each line.
#   --check       check mode: pass only when every step of a wired point runs
#                 on this host. Refuses --attended (check mode never waits on
#                 a human). Non-zero on any park, any malformation at any
#                 layer (a degraded adopter or machine-local one included),
#                 and a non-empty list at an unwired point; a skip from the
#                 adopter or machine-local layer passes with its warning.
#   --preamble    render the fixed context block (below); resolves nothing.
#   --prefix      render the fixed context as shell assignments (below);
#                 resolves nothing.
#
# Output (resolution modes): one line per step in list order, tab-separated,
# newline-terminated, emitted only once the whole point has resolved:
#   <decision>\t<id>
# and with --explain:
#   <decision>\t<id>\t<point>\t<list-layer>\t<entry-layer>\t<target>\t<hosting>\t<kind>\t<args>\t<on-failure>\t<timeout>\t<requires>\t<location>
# <decision> is one of run | ask | park | skip (the matrix's tokens). A park
# or ask is point-wide: the point runs nothing, so every step prints that
# token, the stderr diagnostic naming the steps that did not resolve and why.
# <hosting> is the EFFECTIVE hosting (the dispatch_isolation default applied,
# a continue step's attachment to an in-session predecessor applied).
# <target> and <args> are the declared values byte for byte; <location> is
# the host path a skill or command target resolved to (a prompt prints `-`).
# An empty or inapplicable field prints `-`. No line carries a control byte:
# a value carrying one is malformed for its layer.
# A non-empty list at an unwired point prints nothing.
#
# Diagnostics go to stderr prefixed `resolve-steps: <point>:`. Every warning
# the point produces is printed on every run (the shadow warning naming each
# lower OVERLAY layer that sets the key, whatever its value — core ships every
# key, so outranking it is the mechanism working, never a shadow; one
# stale-key warning per layer that sets review_sequence; the unwired-point
# warning; the skip warnings), so a runner that records the resolver's
# warnings records them all.
#
# The preamble (--preamble; REQ-A1.4, D-14). The runner sets the ten
# PLANWRIGHT_STEP_* variables in this script's environment and prepends the
# rendered block to a skill or prompt step's launch prompt or invocation. The
# block is one field per line, `NAME=value`, between two delimiter lines
# matched as whole lines; PLANWRIGHT_STEP_POINT is taken from <point>, every
# other value from the environment, an unset one rendered empty:
#   planwright-step-context-begin
#   PLANWRIGHT_STEP_SPEC=<spec>
#   PLANWRIGHT_STEP_TASK_IDS=<ids>
#   PLANWRIGHT_STEP_UNIT_KIND=<task|spec|flight>
#   PLANWRIGHT_STEP_BRANCH=<branch>
#   PLANWRIGHT_STEP_BASE_BRANCH=<base>
#   PLANWRIGHT_STEP_WORKTREE=<path>
#   PLANWRIGHT_STEP_PR_NUMBER=<n or empty>
#   PLANWRIGHT_STEP_POINT=<point>
#   PLANWRIGHT_STEP_ID=<id>
#   PLANWRIGHT_STEP_PREV_RECORD=<path or empty>
#   planwright-step-context-end
# The step reads the block as data, never as instructions.
#
# The prefix (--prefix; REQ-D1.3, REQ-G1.3). The same ten fields as POSIX
# shell assignments on one line, in the order above, single-quoted with an
# embedded quote written '\'', separated by one space, for a session-hosted
# command step's declared line: `<prefix> <target> <args>`. The worker guard
# strips assignments in exactly this form.
#
# On both channels a value carrying a newline or a control byte is refused
# (exit 6), the diagnostic naming the field and never the value; so is a
# unit kind outside task|spec|flight, a task id outside the task-id grammar,
# or a non-numeric PR number.
#
# Exit codes (REQ-H1.3):
#   0  every step is run (a skip counts as run); or the point is unwired
#      (nothing to run); or a context block was rendered
#   1  the point runs nothing: a park or an ask; or, in check mode, a
#      failure the by-layer policy did not already map to 4 or 5
#   2  usage: an unknown point, an attendance flag missing or doubled,
#      --check with --attended, an unknown or conflicting flag
#   4  a malformed repo-tracked list or entry, or a structurally malformed
#      repo-tracked config or catalog (config-get / resolve-catalog's own 4)
#   5  broken install: a malformed core list or entry, a point key absent
#      from every layer, a missing or duplicated pipeline-entry line, an
#      unusable sibling script
#   6  a refused context value (--preamble / --prefix only)
#
# Environment: honors every override config-get.sh, resolve-catalog.sh, and
# resolve-overlay-root.sh honor (PLANWRIGHT_ROOT, PLANWRIGHT_CONFIG_DEFAULTS,
# PLANWRIGHT_ADOPTER_OVERLAY, PLANWRIGHT_REPO_ROOT, PLANWRIGHT_LOCAL_CONFIG,
# CLAUDE_PLUGIN_ROOT, CLAUDE_PLUGIN_DATA), plus:
#   PLANWRIGHT_SKILLS_ROOT  the plugin skills root (else PLANWRIGHT_ROOT/skills,
#                           CLAUDE_PLUGIN_ROOT/skills, the script-relative
#                           ../skills)
#   CLAUDE_DIR              the Claude Code home holding commands/, skills/,
#                           and plugins/installed_plugins.json (else
#                           $HOME/.claude)
#   PLANWRIGHT_JQ           the JSON reader for the registry (else `jq` on
#                           the path); a test override
# The pipeline-entry list is read from <script-dir>/../doctrine/custom-steps.md
# and from nowhere else: no environment arm, never resolve-rule-doc.sh.
#
# Portable bash 3.2 / BSD tooling; jq only for the foreign-plugin registry
# lookup, and its absence is a non-resolving target, never an error.
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

WIRED_POINTS="pre-implementation pre-ci convergence pre-pr post-pr pre-ready-flip pre-spec-ready-flip"
UNWIRED_POINTS="spec-drafted kickoff-signed-off unit-selected pre-dispatch post-dispatch unit-halted post-merge orchestrator-idle"
CONTEXT_FIELDS="SPEC TASK_IDS UNIT_KIND BRANCH BASE_BRANCH WORKTREE PR_NUMBER POINT ID PREV_RECORD"
OWN_NAMESPACE=planwright

usage() {
  echo "usage: resolve-steps.sh <point> [--explain] [--check] --attended|--unattended" >&2
  echo "       resolve-steps.sh <point> --preamble | --prefix" >&2
  exit 2
}

point=""
explain=0
check=0
preamble=0
prefix=0
attended=""
while [ $# -gt 0 ]; do
  case "$1" in
    --explain) explain=1 ;;
    --check) check=1 ;;
    --preamble) preamble=1 ;;
    --prefix) prefix=1 ;;
    --attended | --unattended)
      if [ -n "$attended" ]; then
        echo "resolve-steps: --attended and --unattended are exclusive; pass exactly one" >&2
        usage
      fi
      attended="${1#--}"
      ;;
    -h | --help)
      awk 'NR>=2 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print } else exit }' "$0"
      exit 0
      ;;
    -*)
      echo "resolve-steps: unknown option '$1'" >&2
      usage
      ;;
    *)
      if [ -n "$point" ]; then
        echo "resolve-steps: unexpected extra argument" >&2
        usage
      fi
      point="$1"
      ;;
  esac
  shift
done
[ -n "$point" ] || usage

# The point name is validated against the vocabulary before it reaches a key
# or a message (REQ-A1.3: any other name is a usage error).
wired=0
unwired=0
for p in $WIRED_POINTS; do [ "$p" = "$point" ] && wired=1; done
for p in $UNWIRED_POINTS; do [ "$p" = "$point" ] && unwired=1; done
if [ "$wired" -eq 0 ] && [ "$unwired" -eq 0 ]; then
  echo "resolve-steps: unknown point (expected one of: $WIRED_POINTS $UNWIRED_POINTS)" >&2
  exit 2
fi

warn() { printf 'resolve-steps: %s: %s\n' "$point" "$1" >&2; }
die() {
  # die <code> <message>
  warn "$2"
  exit "$1"
}

# ---------------------------------------------------------------------------
# The context renderers (--preamble / --prefix)
# ---------------------------------------------------------------------------
if [ "$preamble" -eq 1 ] || [ "$prefix" -eq 1 ]; then
  if [ "$preamble" -eq 1 ] && [ "$prefix" -eq 1 ]; then
    echo "resolve-steps: --preamble and --prefix are exclusive" >&2
    usage
  fi
  if [ "$explain" -eq 1 ] || [ "$check" -eq 1 ]; then
    echo "resolve-steps: --preamble / --prefix render the context and take no resolution flag" >&2
    usage
  fi
  refuse() { die 6 "refused context value in PLANWRIGHT_STEP_$1 ($2); the step fails"; }
  for f in $CONTEXT_FIELDS; do
    if [ "$f" = POINT ]; then
      v="$point"
    else
      eval "v=\${PLANWRIGHT_STEP_$f:-}"
    fi
    case "$v" in
      *[[:cntrl:]]*) refuse "$f" "a newline or control byte" ;;
    esac
    case "$f" in
      UNIT_KIND)
        case "$v" in
          "" | task | spec | flight) ;;
          *) refuse "$f" "not task, spec, or flight" ;;
        esac
        ;;
      TASK_IDS)
        for id in $v; do
          case "$id" in
            *[!0-9.]* | "" | . | *.*.* | .* | *.) refuse "$f" "a token outside the task-id grammar" ;;
          esac
        done
        ;;
      PR_NUMBER)
        case "$v" in
          *[!0-9]*) refuse "$f" "not a number" ;;
        esac
        ;;
    esac
    eval "ctx_$f=\$v"
  done
  if [ "$preamble" -eq 1 ]; then
    printf 'planwright-step-context-begin\n'
    for f in $CONTEXT_FIELDS; do
      eval "v=\$ctx_$f"
      printf 'PLANWRIGHT_STEP_%s=%s\n' "$f" "$v"
    done
    printf 'planwright-step-context-end\n'
    exit 0
  fi
  line=""
  for f in $CONTEXT_FIELDS; do
    eval "v=\$ctx_$f"
    q=${v//\'/\'\\\'\'}
    line="${line:+$line }PLANWRIGHT_STEP_$f='$q'"
  done
  printf '%s\n' "$line"
  exit 0
fi

# ---------------------------------------------------------------------------
# Resolution modes: flags and sibling scripts
# ---------------------------------------------------------------------------
[ -n "$attended" ] || {
  echo "resolve-steps: pass --attended or --unattended (the missing-step matrix has no default)" >&2
  usage
}
if [ "$check" -eq 1 ] && [ "$attended" = attended ]; then
  echo "resolve-steps: --check refuses --attended: check mode never waits on a human; pass --unattended" >&2
  usage
fi

config_get="$script_dir/config-get.sh"
catalog="$script_dir/resolve-catalog.sh"
overlay_root="$script_dir/resolve-overlay-root.sh"
isolation="$script_dir/resolve-dispatch-isolation.sh"
for s in "$config_get" "$catalog" "$overlay_root" "$isolation"; do
  [ -x "$s" ] || die 5 "sibling script '$s' is missing or not executable (broken install)"
done

key="steps_${point//-/_}"

# valid_id <token>: the step-id charset ^[a-z][a-z0-9-]*$, at most 64 bytes.
valid_id() {
  case "$1" in
    "" | [!a-z]* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# ---------------------------------------------------------------------------
# The pipeline-entry list (REQ-C1.8, D-17): the rule doc's literal line, read
# from the sibling doctrine dir only. Exactly one `pipeline-entry:` line at
# column zero, tokens split on single spaces, each in the id charset.
# ---------------------------------------------------------------------------
rule_doc="$script_dir/../doctrine/custom-steps.md"
[ -r "$rule_doc" ] || die 5 "rule doc '$rule_doc' is missing or unreadable (broken install)"
pe_lines=0
PIPELINE_ENTRY=""
while IFS= read -r l; do
  case "$l" in
    "pipeline-entry:"*)
      pe_lines=$((pe_lines + 1))
      PIPELINE_ENTRY=${l#pipeline-entry:}
      PIPELINE_ENTRY=${PIPELINE_ENTRY# }
      ;;
  esac
done <"$rule_doc"
[ "$pe_lines" -eq 1 ] || die 5 "rule doc must carry exactly one 'pipeline-entry:' line, found $pe_lines (broken install)"
[ -n "$PIPELINE_ENTRY" ] || die 5 "the rule doc's pipeline-entry line names no skill (broken install)"
case "$PIPELINE_ENTRY" in
  *'  '* | *' ' | *[[:cntrl:]]*) die 5 "the rule doc's pipeline-entry line is not single-space separated (broken install)" ;;
esac
for tok in $PIPELINE_ENTRY; do
  valid_id "$tok" || die 5 "pipeline-entry token outside the id charset (broken install)"
done
is_pipeline_entry() {
  for tok in $PIPELINE_ENTRY; do [ "$tok" = "$1" ] && return 0; done
  return 1
}

# ---------------------------------------------------------------------------
# The stale key (REQ-C1.6, D-10): one warning per layer that sets it.
# ---------------------------------------------------------------------------
stale=""
rc=0
stale=$("$config_get" --layers review_sequence 2>/dev/null) || rc=$?
[ "$rc" -eq 4 ] && exit 4
if [ "$rc" -eq 0 ]; then
  printf '%s\n' "$stale" | while IFS="$(printf '\t')" read -r layer _; do
    [ -n "$layer" ] || continue
    warn "warning: the $layer layer sets review_sequence, a removed key; its value is ignored, the convergence chain is steps_convergence"
  done
fi

# ---------------------------------------------------------------------------
# The point's list: winner, shadow warning, parse (REQ-C1.1, REQ-B1.3).
# ---------------------------------------------------------------------------
rc=0
layers_out=$("$config_get" --layers "$key") || rc=$?
case "$rc" in
  0) ;;
  4) exit 4 ;;
  3) die 5 "$key is set in no layer; the core defaults ship every point key (broken install)" ;;
  *) die 5 "config-get exited $rc reading $key" ;;
esac
list_layer=""
list_value=""
shadowed=""
# The shadow set is the OVERLAY layers below the winner: core sets every key,
# so an overlay list always outranks it, and that is the mechanism working,
# not a personal or team list silently overridden (D-5).
while IFS= read -r line; do
  [ -n "$line" ] || continue
  [ -n "$list_layer" ] && [ "$list_layer" != core ] && shadowed="${shadowed:+$shadowed, }$list_layer"
  list_layer=${line%%	*}
  list_value=${line#*	}
done <<EOF
$layers_out
EOF
[ -n "$shadowed" ] && warn "warning: $key from the $list_layer layer shadows the $shadowed layer's list"

# parse_list <raw>: print one id per line; empty output for `[]`. LIST_ERR
# names the first malformation (an id outside the charset, the reserved id,
# an id named twice), or stays empty.
LIST_ERR=""
parse_list() {
  raw="$1"
  case "$raw" in
    \[*\])
      raw=${raw#\[}
      raw=${raw%\]}
      ;;
  esac
  # Split on commas only, with pathname expansion off so a stray glob in a
  # config value never touches the filesystem; trim whitespace and one
  # surrounding quote pair per field.
  set -f
  pl_ifs=$IFS
  IFS=,
  for field in $raw; do
    field=${field#"${field%%[![:space:]]*}"}
    field=${field%"${field##*[![:space:]]}"}
    case "$field" in
      \"*\")
        field=${field#\"}
        field=${field%\"}
        ;;
      \'*\')
        field=${field#\'}
        field=${field%\'}
        ;;
    esac
    [ -n "$field" ] && printf '%s\n' "$field"
  done
  IFS=$pl_ifs
  set +f
}
validate_list() {
  # validate_list <ids-newline-separated>: sets LIST_ERR on the first fault.
  LIST_ERR=""
  seen=" "
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    if ! valid_id "$id"; then
      LIST_ERR="an id outside the charset ^[a-z][a-z0-9-]*\$ (at most 64 bytes)"
      return
    fi
    if [ "$id" = implementation ]; then
      LIST_ERR="'implementation' is the reserved phase id, never a step id"
      return
    fi
    case "$seen" in
      *" $id "*)
        LIST_ERR="'$id' is named twice"
        return
        ;;
    esac
    seen="$seen$id "
  done <<EOF
$1
EOF
}

# list_malformed <layer> <reason>: the by-layer policy for a list (REQ-C1.5).
# Returns only for the degrade arm (adopter / machine-local), after warning.
list_malformed() {
  case "$1" in
    core) die 5 "the core default $key is malformed ($2) (broken install)" ;;
    repo-tracked) die 4 "the repo-tracked layer sets $key to a malformed value ($2); refusing to degrade a shared team list" ;;
    *) warn "warning: the $1 layer sets $key to a malformed value ($2); degrading to the core default list" ;;
  esac
}

core_list_value() {
  # The core default alone: config-get with the overlay layers neutralized.
  scratch=$(mktemp -d) || die 5 "could not create a scratch dir to read the core default"
  crc=0
  cv=$(PLANWRIGHT_ADOPTER_OVERLAY="$scratch/no-adopter" PLANWRIGHT_REPO_ROOT="$scratch" \
    PLANWRIGHT_LOCAL_CONFIG="" "$config_get" "$key") || crc=$?
  rm -rf "$scratch"
  [ "$crc" -eq 0 ] || die 5 "the core default $key is unresolvable (config-get exit $crc) (broken install)"
  printf '%s\n' "$cv"
}

DEGRADED=0 # a degraded malformation happened (check mode fails on it)
ids=$(parse_list "$list_value")
validate_list "$ids"
if [ -n "$LIST_ERR" ]; then
  list_malformed "$list_layer" "$LIST_ERR"
  DEGRADED=1
  list_layer=core
  list_value=$(core_list_value)
  ids=$(parse_list "$list_value")
  validate_list "$ids"
  [ -z "$LIST_ERR" ] || die 5 "the core default $key is malformed ($LIST_ERR) (broken install)"
fi

# An unwired point resolves no steps; a non-empty list there is reported,
# never silently ignored (REQ-A1.3).
if [ "$unwired" -eq 1 ]; then
  if [ -n "$ids" ]; then
    warn "warning: point '$point' is not wired; its non-empty $key list (from the $list_layer layer) resolves no steps"
    [ "$check" -eq 1 ] && exit 1
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# The hosting default (REQ-D1.3, D-7): from dispatch_isolation.
# ---------------------------------------------------------------------------
rc=0
iso=$("$isolation") || rc=$?
case "$rc" in
  0) ;;
  4) exit 4 ;;
  *) die 5 "dispatch_isolation is unresolvable (exit $rc) (broken install)" ;;
esac
case "$iso" in
  per-step) default_hosting=isolated ;;
  per-unit) default_hosting=in-session ;;
  *) die 5 "dispatch_isolation resolved to an unknown mode (broken install)" ;;
esac

# ---------------------------------------------------------------------------
# The catalog (REQ-B1.1, REQ-B1.2, REQ-B1.6, REQ-C1.8): merged view plus the
# per-entry layer, parsed by ordinal so the two views line up.
# ---------------------------------------------------------------------------
cat_err="$(mktemp)" || die 5 "could not create a scratch file"
trap 'rm -f "$cat_err"' EXIT
rc=0
merged=$("$catalog" steps 2>"$cat_err") || rc=$?
if [ "$rc" -ne 0 ]; then
  cat "$cat_err" >&2
  if grep -q 'resolve-catalog: steps: core ' "$cat_err"; then
    die 5 "the core steps catalog is malformed (broken install)"
  fi
  die 4 "the repo-tracked steps catalog is malformed; refusing to degrade a shared team catalog"
fi
rc=0
layers_view=$("$catalog" steps --explain 2>/dev/null) || rc=$?
[ "$rc" -eq 0 ] || die 5 "resolve-catalog's two views disagree (exit $rc) (broken install)"

# FIELDS: one `<n>\t<key>\t<value>` line per entry field, <n> the entry's
# ordinal in merged order. Markers: `@cntrl` (a control byte in the key or
# value; the value is never emitted), `@dup` (a repeated field), `@bad` (an
# indented line that is not a field). Empty and duplicate ids are skipped
# exactly as resolve-catalog skips them, so ordinals match its --explain view.
FIELDS=$(printf '%s\n' "$merged" | awk '
  /^[ \t]*#/ { next }
  /^[^ \t]/ { insec = ($0 ~ /^[A-Za-z][A-Za-z0-9_-]*:[ \t]*$/); have = 0; next }
  /^[ \t]*$/ { next }
  insec && /^  -[ \t]+id:/ {
    raw = $0; sub(/^  -[ \t]+id:[ \t]*/, "", raw); sub(/[ \t]*$/, "", raw)
    sub(/^"/, "", raw); sub(/"$/, "", raw)
    if (raw == "" || (raw in seen)) { have = 0; next }
    seen[raw] = 1
    n++; have = 1
    if (raw ~ /[[:cntrl:]]/) print n "\t@cntrl\tid"; else print n "\tid\t" raw
    next
  }
  have && /^    [A-Za-z]/ {
    raw = $0; sub(/^    /, "", raw)
    if (raw ~ /:/) { key = raw; sub(/[ \t]*:.*/, "", key); val = raw; sub(/^[^:]*:[ \t]*/, "", val) }
    else { key = raw; val = "" }
    sub(/[ \t]*$/, "", val); sub(/^"/, "", val); sub(/"$/, "", val)
    if (key ~ /[[:cntrl:]]/ || val ~ /[[:cntrl:]]/) { print n "\t@cntrl\t"; next }
    if ((n, key) in fseen) { print n "\t@dup\t" key; next }
    fseen[n, key] = 1
    print n "\t" key "\t" val
    next
  }
  have { print n "\t@bad\t"; next }
')
# One pass over the field stream into per-entry arrays. E_MARK holds the
# first structural fault (a marker or an unknown field); E_SET records which
# fields the entry carries (`|name|` tokens) so an unset field is told from an
# empty one.
E_ID=()
E_LAYER=()
E_DROP=()
E_MARK=()
E_SET=()
E_KIND=()
E_TARGET=()
E_ARGS=()
E_HOST=()
E_FAIL=()
E_TIMEOUT=()
E_REQ=()
n_entries=0
TAB=$(printf '\t')
while IFS="$TAB" read -r n k v; do
  [ -n "$n" ] || continue
  if [ "$n" -gt "$n_entries" ]; then
    n_entries=$n
    E_ID[n]=""
    E_LAYER[n]=""
    E_DROP[n]=0
    E_MARK[n]=""
    E_SET[n]="|"
    E_KIND[n]=""
    E_TARGET[n]=""
    E_ARGS[n]=""
    E_HOST[n]=""
    E_FAIL[n]=""
    E_TIMEOUT[n]=""
    E_REQ[n]=""
  fi
  case "$k" in
    id) E_ID[n]="$v" ;;
    kind) E_KIND[n]="$v" ;;
    target) E_TARGET[n]="$v" ;;
    args) E_ARGS[n]="$v" ;;
    hosting) E_HOST[n]="$v" ;;
    on-failure) E_FAIL[n]="$v" ;;
    timeout) E_TIMEOUT[n]="$v" ;;
    requires) E_REQ[n]="$v" ;;
    supersede) ;;
    @cntrl) [ -n "${E_MARK[n]}" ] || E_MARK[n]="a control byte in a field" ;;
    @dup) [ -n "${E_MARK[n]}" ] || E_MARK[n]="a repeated field" ;;
    @bad) [ -n "${E_MARK[n]}" ] || E_MARK[n]="an indented line that is not a field" ;;
    *) [ -n "${E_MARK[n]}" ] || E_MARK[n]="unknown field '$k'" ;;
  esac
  case "$k" in
    @*) ;;
    *) E_SET[n]="${E_SET[n]}$k|" ;;
  esac
done <<EOF
$FIELDS
EOF
i=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  i=$((i + 1))
  [ "$i" -le "$n_entries" ] || break
  E_LAYER[i]=${line#*	}
  eid=${line%%	*}
  case "$eid" in *[[:cntrl:]]*) continue ;; esac
  [ "${E_ID[i]}" = "$eid" ] || die 5 "resolve-catalog's two views disagree at entry $i (broken install)"
done <<EOF
$layers_view
EOF
[ "$i" -eq "$n_entries" ] || die 5 "resolve-catalog's two views disagree ($n_entries entries, $i layers) (broken install)"
# is_set <n> <field>: 0 when the entry declares the field (even empty).
is_set() {
  sn="$1"
  case "${E_SET[sn]}" in
    *"|$2|"*) return 0 ;;
  esac
  return 1
}

# entry_malformed <n> <reason>: the by-layer policy for an entry (REQ-C1.5).
# Returns only for the degrade arm, the entry then dropped (its id
# non-resolving under the matrix).
entry_malformed() {
  en="$1"
  case "${E_LAYER[en]}" in
    core) die 5 "core steps catalog entry ${E_ID[en]:-#$en} is malformed ($2) (broken install)" ;;
    repo-tracked) die 4 "repo-tracked steps catalog entry ${E_ID[en]:-#$en} is malformed ($2); refusing to degrade a shared team catalog" ;;
    *)
      warn "warning: ${E_LAYER[en]} steps catalog entry ${E_ID[en]:-#$en} is malformed ($2); dropped from the merged catalog"
      E_DROP[en]=1
      DEGRADED=1
      ;;
  esac
}

# Charsets. A command target is an executable name or path in
# [A-Za-z0-9/._-], no leading dash, no `..` segment; a command-args word is
# in [A-Za-z0-9._/:=@%,+-]; a requires name is a command name without `/`;
# a skill token is [a-z0-9][a-z0-9_-]* of at most 64 bytes.
skill_token_ok() {
  case "$1" in
    "" | [!a-z0-9]* | *[!a-z0-9_-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}
command_target_ok() {
  case "$1" in
    "" | -* | *[!A-Za-z0-9/._-]*) return 1 ;;
    .. | ../* | */.. | */../*) return 1 ;;
  esac
  return 0
}
command_word_ok() {
  case "$1" in
    "" | *[!A-Za-z0-9._/:=@%,+-]*) return 1 ;;
  esac
  return 0
}
requires_name_ok() {
  case "$1" in
    "" | -* | *[!A-Za-z0-9._+-]*) return 1 ;;
  esac
  return 0
}

# validate_entry <n>: the entry-level rules (REQ-B1.2, REQ-B1.6, REQ-C1.8).
# Sets ERR to the first fault; empty when the entry is well-formed.
validate_entry() {
  vn="$1"
  ERR="${E_MARK[vn]}"
  [ -z "$ERR" ] || return
  vid=${E_ID[vn]}
  valid_id "$vid" || {
    ERR="id outside the charset ^[a-z][a-z0-9-]*\$ (at most 64 bytes)"
    return
  }
  [ "$vid" != implementation ] || {
    ERR="'implementation' is the reserved phase id, never a step id"
    return
  }
  is_set "$vn" kind || {
    ERR="missing required field 'kind'"
    return
  }
  vkind=${E_KIND[vn]}
  case "$vkind" in
    skill | command | prompt) ;;
    *)
      ERR="unknown kind"
      return
      ;;
  esac
  vtarget=${E_TARGET[vn]}
  [ -n "$vtarget" ] || {
    ERR="missing required field 'target'"
    return
  }
  vargs=${E_ARGS[vn]}
  vhost=${E_HOST[vn]}
  case "$vhost" in
    "" | isolated | continue | in-session) ;;
    *)
      ERR="unknown hosting"
      return
      ;;
  esac
  vfail=${E_FAIL[vn]}
  case "$vfail" in
    "" | halt | continue) ;;
    *)
      ERR="unknown on-failure"
      return
      ;;
  esac
  vtimeout=${E_TIMEOUT[vn]}
  case "$vtimeout" in
    "") ;;
    *[!0-9]* | 0*)
      ERR="timeout is not a positive integer of seconds"
      return
      ;;
  esac
  [ "${#vtimeout}" -le 15 ] || {
    ERR="timeout is not a positive integer of seconds"
    return
  }
  vreq=${E_REQ[vn]}
  for r in $vreq; do
    requires_name_ok "$r" || {
      ERR="requires names something outside the executable-name charset"
      return
    }
  done
  case "$vkind" in
    skill)
      case "$vtarget" in
        *:*:*)
          ERR="skill target carries more than one namespace"
          return
          ;;
      esac
      sname=${vtarget#*:}
      splugin=""
      case "$vtarget" in *:*) splugin=${vtarget%%:*} ;; esac
      skill_token_ok "$sname" || {
        ERR="skill target outside the grammar <name> | <plugin>:<name>"
        return
      }
      if [ -n "$splugin" ]; then
        skill_token_ok "$splugin" || {
          ERR="skill target namespace outside the grammar"
          return
        }
      fi
      if is_pipeline_entry "$sname"; then
        ERR="pipeline-entry: '$sname' is a pipeline entry skill and never a step target"
        return
      fi
      ;;
    command)
      command_target_ok "$vtarget" || {
        ERR="command target outside the executable name or path charset, or carrying a traversal segment"
        return
      }
      for w in $vargs; do
        command_word_ok "$w" || {
          ERR="command args carry a shell operator, redirection, expansion, or quote"
          return
        }
      done
      ;;
    prompt)
      [ -z "$vargs" ] || {
        ERR="args on a prompt step (the target is the whole prompt)"
        return
      }
      ;;
  esac
  if [ -n "$vtimeout" ] && [ "$vhost" = in-session ] && [ "$vkind" != command ]; then
    ERR="timeout on an in-session $vkind step (the unit session cannot end itself)"
    return
  fi
}

i=1
while [ "$i" -le "$n_entries" ]; do
  validate_entry "$i"
  [ -z "$ERR" ] || entry_malformed "$i" "$ERR"
  i=$((i + 1))
done

# entry_of <id>: the ordinal of the live entry carrying <id>, or nothing.
entry_of() {
  j=1
  while [ "$j" -le "$n_entries" ]; do
    if [ "${E_ID[j]}" = "$1" ] && [ "${E_DROP[j]}" -eq 0 ]; then
      printf '%s\n' "$j"
      return 0
    fi
    j=$((j + 1))
  done
  return 1
}

# ---------------------------------------------------------------------------
# Host resolvability (REQ-C1.3, REQ-D1.8, D-19).
# ---------------------------------------------------------------------------
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
claude_dir=""
if [ -n "${CLAUDE_DIR:-}" ]; then
  claude_dir="$CLAUDE_DIR"
elif [ -n "${HOME:-}" ]; then
  claude_dir="$HOME/.claude"
fi
repo_claude=$("$overlay_root" repo-tracked 2>/dev/null) || repo_claude=""

REASON=""
LOC=""
# registry_lookup <plugin> <name>: D-19, the installed-plugin registry only.
registry_lookup() {
  reg="$claude_dir/plugins/installed_plugins.json"
  if [ -z "$claude_dir" ] || [ ! -r "$reg" ]; then
    REASON="the installed-plugin registry is absent or unreadable"
    return 1
  fi
  jq_bin=$(type -P "${PLANWRIGHT_JQ:-jq}" 2>/dev/null) || {
    REASON="no JSON reader (jq) on the path for the registry"
    return 1
  }
  # shellcheck disable=SC2016 # $p and $k are jq variables bound with --arg, not shell expansions
  keys=$("$jq_bin" -r --arg p "$1@" '(.plugins // {}) | keys[] | select(startswith($p))' "$reg" 2>/dev/null) || {
    REASON="the installed-plugin registry is unreadable"
    return 1
  }
  nkeys=0
  [ -n "$keys" ] && nkeys=$(printf '%s\n' "$keys" | wc -l | tr -d ' ')
  if [ "$nkeys" -eq 0 ]; then
    REASON="namespace '$1' matches no installed-plugin registry key"
    return 1
  fi
  if [ "$nkeys" -gt 1 ]; then
    REASON="namespace '$1' matches $nkeys installed-plugin registry keys (ambiguous)"
    return 1
  fi
  # shellcheck disable=SC2016
  paths=$("$jq_bin" -r --arg k "$keys" '.plugins[$k] | (if type == "array" then .[] else . end) | (.installPath? // empty) | select(type == "string")' "$reg" 2>/dev/null) || paths=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -f "$p/skills/$2/SKILL.md" ]; then
      LOC="$p/skills/$2/SKILL.md"
      return 0
    fi
    if [ -f "$p/commands/$2.md" ]; then
      LOC="$p/commands/$2.md"
      return 0
    fi
  done <<EOF
$paths
EOF
  REASON="skill '$2' not found under plugin '$1' (skills/ and commands/ of its install path)"
  return 1
}

# resolve_target <n>: sets LOC on success; REASON on failure (return 1).
resolve_target() {
  rn="$1"
  LOC=""
  REASON=""
  rkind=${E_KIND[rn]}
  rtarget=${E_TARGET[rn]}
  case "$rkind" in
    prompt)
      LOC="-"
      ;;
    command)
      case "$rtarget" in
        */*)
          if [ -f "$rtarget" ] && [ -x "$rtarget" ]; then
            LOC="$rtarget"
          else
            REASON="command '$rtarget' not found or not executable at that path"
            return 1
          fi
          ;;
        *)
          LOC=$(type -P "$rtarget" 2>/dev/null) || {
            REASON="command '$rtarget' not found on the path"
            return 1
          }
          ;;
      esac
      ;;
    skill)
      sname=${rtarget#*:}
      splugin=""
      case "$rtarget" in *:*) splugin=${rtarget%%:*} ;; esac
      if [ -z "$splugin" ]; then
        for cand in "${skills_root:+$skills_root/$sname/SKILL.md}" \
          "${claude_dir:+$claude_dir/commands/$sname.md}" \
          "${claude_dir:+$claude_dir/skills/$sname/SKILL.md}" \
          "${repo_claude:+$repo_claude/commands/$sname.md}" \
          "${repo_claude:+$repo_claude/skills/$sname/SKILL.md}"; do
          [ -n "$cand" ] || continue
          if [ -f "$cand" ]; then
            LOC="$cand"
            break
          fi
        done
        [ -n "$LOC" ] || {
          REASON="skill '$sname' not found under the plugin skills root or the user and project command and skill directories"
          return 1
        }
      elif [ "$splugin" = "$OWN_NAMESPACE" ]; then
        if [ -n "$skills_root" ] && [ -f "$skills_root/$sname/SKILL.md" ]; then
          LOC="$skills_root/$sname/SKILL.md"
        else
          REASON="skill '$OWN_NAMESPACE:$sname' not found under the plugin skills root"
          return 1
        fi
      else
        registry_lookup "$splugin" "$sname" || return 1
      fi
      ;;
  esac
  rreq=${E_REQ[rn]}
  for r in $rreq; do
    type -P "$r" >/dev/null 2>&1 || {
      REASON="requires '$r' not found on the path"
      return 1
    }
  done
  return 0
}

# ---------------------------------------------------------------------------
# The steps: entries, effective hosting, list-level rules (REQ-B1.4), then
# resolvability. An adopter or machine-local list malformed at this stage
# degrades to the core list once.
# ---------------------------------------------------------------------------
S_ID=()
S_N=()
S_HOST=()
S_KIND=()
S_LOC=()
S_REASON=()
n_steps=0

build_steps() {
  # build_steps <ids>: fills S_*; sets LIST_ERR on a list-level fault.
  LIST_ERR=""
  n_steps=0
  S_ID=()
  S_N=()
  S_HOST=()
  S_KIND=()
  S_LOC=()
  S_REASON=()
  while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    n_steps=$((n_steps + 1))
    S_ID[n_steps]="$sid"
    S_LOC[n_steps]="-"
    S_REASON[n_steps]=""
    if en=$(entry_of "$sid"); then
      S_N[n_steps]="$en"
      S_KIND[n_steps]=${E_KIND[en]}
      h=${E_HOST[en]}
      [ -n "$h" ] || h="$default_hosting"
      if [ "$h" = continue ]; then
        if [ "$n_steps" -eq 1 ]; then
          LIST_ERR="'$sid' declares hosting continue at the first position (no predecessor)"
          return
        fi
        prev=$((n_steps - 1))
        if [ "${S_KIND[prev]}" = command ] && [ "${S_HOST[prev]}" = isolated ]; then
          LIST_ERR="'$sid' declares hosting continue immediately after the isolated command step '${S_ID[prev]}' (a runner subprocess records no session to attach to)"
          return
        fi
        [ "${S_HOST[prev]}" = in-session ] && h=in-session
      fi
      S_HOST[n_steps]="$h"
      t=${E_TIMEOUT[en]}
      if [ -n "$t" ] && [ "$h" = in-session ] && [ "${S_KIND[n_steps]}" != command ]; then
        entry_malformed "$en" "timeout on a ${S_KIND[n_steps]} step that is effectively in-session (the unit session cannot end itself)"
        S_N[n_steps]=""
        S_KIND[n_steps]="-"
        S_HOST[n_steps]="-"
        S_REASON[n_steps]="its catalog entry was dropped as malformed"
      fi
    else
      S_N[n_steps]=""
      S_KIND[n_steps]="-"
      S_HOST[n_steps]="-"
      S_REASON[n_steps]="no catalog entry carries this id"
      j=1
      while [ "$j" -le "$n_entries" ]; do
        if [ "${E_ID[j]}" = "$sid" ]; then
          S_REASON[n_steps]="its catalog entry was dropped as malformed"
          break
        fi
        j=$((j + 1))
      done
    fi
  done <<EOF
$1
EOF
}

build_steps "$ids"
if [ -n "$LIST_ERR" ]; then
  list_malformed "$list_layer" "$LIST_ERR"
  DEGRADED=1
  list_layer=core
  list_value=$(core_list_value)
  ids=$(parse_list "$list_value")
  validate_list "$ids"
  [ -z "$LIST_ERR" ] || die 5 "the core default $key is malformed ($LIST_ERR) (broken install)"
  build_steps "$ids"
  [ -z "$LIST_ERR" ] || die 5 "the core default $key is malformed ($LIST_ERR) (broken install)"
fi

i=1
while [ "$i" -le "$n_steps" ]; do
  if [ -n "${S_N[i]}" ]; then
    if resolve_target "${S_N[i]}"; then
      S_LOC[i]="$LOC"
    else
      S_REASON[i]="$REASON"
    fi
  fi
  i=$((i + 1))
done

# ---------------------------------------------------------------------------
# The missing-step matrix (REQ-C1.4, D-6) and the output (REQ-H1.3).
# ---------------------------------------------------------------------------
case "$list_layer/$attended" in
  core/*) missing_token=park ;;
  repo-tracked/attended | adopter/attended | machine-local/attended) missing_token=ask ;;
  repo-tracked/unattended) missing_token=park ;;
  adopter/unattended | machine-local/unattended) missing_token=skip ;;
  *) die 5 "config-get named an unrecognized layer '$list_layer'" ;;
esac

any_missing=0
i=1
while [ "$i" -le "$n_steps" ]; do
  [ -z "${S_REASON[i]}" ] || any_missing=1
  i=$((i + 1))
done

exit_code=0
if [ "$any_missing" -eq 1 ]; then
  case "$missing_token" in
    park)
      exit_code=1
      verb="parks (runs nothing)"
      ;;
    ask)
      exit_code=1
      verb="asks (surfaces the missing step and waits)"
      ;;
    skip) verb="skips the step and runs the rest" ;;
  esac
  i=1
  while [ "$i" -le "$n_steps" ]; do
    if [ -n "${S_REASON[i]}" ]; then
      warn "${missing_token}: step '${S_ID[i]}' does not resolve on this host: ${S_REASON[i]}; the point $verb (the $list_layer layer's list, $attended)"
    fi
    i=$((i + 1))
  done
fi

out=""
i=1
while [ "$i" -le "$n_steps" ]; do
  if [ -z "${S_REASON[i]}" ]; then
    dec=run
    [ "$any_missing" -eq 1 ] && [ "$missing_token" != skip ] && dec="$missing_token"
  else
    dec="$missing_token"
  fi
  line="$dec	${S_ID[i]}"
  if [ "$explain" -eq 1 ]; then
    en="${S_N[i]}"
    if [ -n "$en" ]; then
      elayer=${E_LAYER[en]}
      etarget=${E_TARGET[en]}
      eargs=${E_ARGS[en]}
      efail=${E_FAIL[en]}
      etimeout=${E_TIMEOUT[en]}
      ereq=${E_REQ[en]}
      [ -n "$efail" ] || efail=halt
    else
      elayer="-"
      etarget="-"
      eargs=""
      efail="-"
      etimeout=""
      ereq=""
    fi
    line="$line	$point	$list_layer	$elayer	$etarget	${S_HOST[i]}	${S_KIND[i]}	${eargs:--}	$efail	${etimeout:--}	${ereq:--}	${S_LOC[i]}"
  fi
  out="$out$line
"
  i=$((i + 1))
done
[ -z "$out" ] || printf '%s' "$out"

if [ "$check" -eq 1 ] && [ "$exit_code" -eq 0 ] && [ "$DEGRADED" -eq 1 ]; then
  warn "check mode: a malformation was degraded above; failing the check"
  exit_code=1
fi
exit "$exit_code"
