#!/usr/bin/env bash
# resolve-steps.sh — resolve one attachment point's step list into the chain
# the runner executes there, with provenance, the missing-step decision, and
# the by-layer malformed policy applied before anything runs (custom-steps
# Task 2; REQ-A1.3, REQ-A1.4, REQ-B1.1–B1.6, REQ-C1.1–C1.6, REQ-C1.8,
# REQ-D1.8, REQ-D1.9, REQ-G1.1, REQ-H1.3; D-4, D-5, D-6, D-10, D-17, D-19).
# doctrine/custom-steps.md is the normative home of every rule this script
# applies; this header pins what that doc delegates here (the output line
# format, the exit codes, the preamble layout, and the prefix quoting) and
# summarizes the rest for a reader of this file, the doc winning on conflict.
#
# A point's list is config, read THROUGH config-get.sh (last-layer-wins; its
# --layers mode supplies the shadow and stale-key warnings and the core
# default); the step entries are the `steps` data catalog, read THROUGH
# resolve-catalog.sh (append/union, supersede-by-id). This script
# re-implements neither; it adds the entry and list validation, the host
# resolvability check, the missing-step matrix, and the rendering of the
# fixed context.
#
# Usage:
#   resolve-steps.sh <point> [--explain] [--check] --attended|--unattended
#   resolve-steps.sh <point> --preamble
#   resolve-steps.sh <point> --prefix
#
#   <point>       one of the named points of doctrine/custom-steps.md's
#                 vocabulary (the wired points, the two flip points, and the
#                 named-but-unwired points). Any other name is a usage error.
#                 The list key is steps_<point> with hyphens as underscores.
#   --attended / --unattended
#                 the attendance axis of the missing-step matrix, passed by
#                 the hosting skill (--unattended exactly when the unit was
#                 launched headless). Exactly one is required in the
#                 resolution modes; neither, or both, is a usage error. The
#                 render modes take no attendance flag.
#   --explain     append the provenance and execution fields to each line.
#   --check       check mode: pass only when every step of a wired point
#                 resolves to `run`, or to a `skip` from the adopter or
#                 machine-local layer (which passes with its warning).
#                 Refuses --attended (check mode never waits on a human).
#                 Non-zero on any park, on a non-empty list at an unwired
#                 point, and on any malformation at any layer, a degraded
#                 adopter or machine-local one included, whether this script
#                 or a sibling reader degraded it.
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
# <target> and <args> are the declared values as the constrained reader
# parses them (a surrounding pair of double quotes and trailing blanks
# removed); <on-failure> is the effective posture (`halt` when unset);
# <location> is
# the host path a skill or command target resolved to (a prompt prints `-`;
# a relative command path is printed as declared, relative to the working
# directory this script runs in, which the hosting skill makes the unit's
# worktree). An empty or inapplicable field prints `-`. No line carries a
# C0 control byte or DEL: a catalog value carrying one is malformed for its
# layer, and a location built from the environment that carries one does
# not resolve.
# The C1 range is not refused, because those bytes are continuation bytes of
# ordinary UTF-8 text; a consumer rendering a line into a terminal or a PR
# body screens it as untrusted data. A non-empty list at an unwired point
# prints nothing.
#
# Diagnostics go to stderr prefixed `resolve-steps: <point>:`, every
# catalog-derived string in them passed through the house sanitizer
# (scripts/echo-safety.sh). Every warning the point produces is printed on
# every run: the sibling readers' own degrade warnings, the shadow warning
# naming each lower OVERLAY layer that sets the key whatever its value (core
# ships every key, so outranking it is the mechanism working, never a
# shadow), one stale-key warning per layer that sets review_sequence, the
# unwired-point warning, and the skip warnings. A runner that records the
# resolver's warnings therefore records them all; a sibling warning repeated
# by several reads of the same layer is printed once.
#
# The preamble (--preamble; REQ-A1.4, D-14). The runner sets the
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
# The prefix (--prefix; REQ-D1.3, REQ-G1.3). The same fields as POSIX shell
# assignments on one line, in the order above, single-quoted with an
# embedded quote written '\'', separated by one space, for a session-hosted
# command step's declared line: `<prefix> <target> <args>`. This is the exact
# form the worker command guard is specified to strip before matching the
# declared line.
#
# On both channels a value carrying a newline, another C0 control byte, or
# DEL is refused (exit 6), the diagnostic naming the field and never the
# value; so is a unit kind outside task|spec|flight, a task id outside the
# task-id grammar, or a non-numeric PR number.
#
# Exit codes (REQ-H1.3):
#   0  every step is run (a skip counts as run); or the point is unwired
#      (nothing to run); or a context block was rendered
#   1  the point runs nothing: a park or an ask; or, in check mode, a
#      failure the by-layer policy did not already map to 4 or 5
#   2  usage: an unknown point, an attendance flag missing or doubled,
#      --check with --attended, an unknown or conflicting flag
#   4  a malformed repo-tracked list or entry, or a structurally malformed
#      repo-tracked config or catalog (config-get's own 4, resolve-catalog's
#      hard-fail naming the repo-tracked layer)
#   5  broken install: a malformed core list, entry, or catalog, a point key
#      absent from every layer, a missing or duplicated pipeline-entry line,
#      an unusable sibling script
#   6  a refused context value (--preamble / --prefix only)
#   130 / 143  interrupted or terminated by a signal (the shell's own
#      convention), the scratch file removed
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
# The repository root is resolved once (an explicit PLANWRIGHT_REPO_ROOT, else
# the working directory's git toplevel) and exported to every sibling call,
# so the project command and skill directories, the repo-tracked and
# machine-local layers, and a relative command path all follow the directory
# this script runs in. The pipeline-entry list is read from
# <script-dir>/../doctrine/custom-steps.md and from nowhere else: no
# environment arm, never resolve-rule-doc.sh.
#
# Portable bash 3.2 / BSD tooling; jq only for the foreign-plugin registry
# lookup, and its absence is a non-resolving target, never an error.
set -u
# Every word split below is a declared token, never a pattern: pathname
# expansion stays off for the whole run so a `*` in a value is validated as
# itself rather than as the working directory's file names.
set -f

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || {
  echo "resolve-steps: sanitizer '$script_dir/echo-safety.sh' is missing or unreadable (broken install)" >&2
  exit 5
}

TAB=$(printf '\t')
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
point_set=0
explain=0
check=0
preamble=0
prefix=0
attendance=""
while [ $# -gt 0 ]; do
  case "$1" in
    --explain) explain=1 ;;
    --check) check=1 ;;
    --preamble) preamble=1 ;;
    --prefix) prefix=1 ;;
    --attended | --unattended)
      if [ -n "$attendance" ]; then
        echo "resolve-steps: --attended and --unattended are exclusive; pass exactly one" >&2
        usage
      fi
      attendance="${1#--}"
      ;;
    -h | --help)
      awk 'NR>=2 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print } else exit }' "$0"
      exit 0
      ;;
    -*)
      echo "resolve-steps: unknown option" >&2
      usage
      ;;
    *)
      if [ "$point_set" -eq 1 ]; then
        echo "resolve-steps: unexpected extra argument" >&2
        usage
      fi
      point="$1"
      point_set=1
      ;;
  esac
  shift
done
[ -n "$point" ] || usage

# The point name is validated against the vocabulary before it reaches a key
# or a message: any other name is a usage error.
wired=0
unwired=0
for p in $WIRED_POINTS; do [ "$p" = "$point" ] && wired=1; done
for p in $UNWIRED_POINTS; do [ "$p" = "$point" ] && unwired=1; done
if [ "$wired" -eq 0 ] && [ "$unwired" -eq 0 ]; then
  echo "resolve-steps: unknown point (expected one of: $WIRED_POINTS $UNWIRED_POINTS)" >&2
  exit 2
fi

# warn / die: every message passes the house sanitizer, since a catalog or
# registry string can carry a terminal escape.
warn() { printf 'resolve-steps: %s: %s\n' "$point" "$(sanitize_printable "$1")" >&2; }
die() {
  # die <code> <message>
  warn "$2"
  exit "$1"
}
# replay <file>: forward a sibling's captured stderr, each line once per run
# (several reads of one layer repeat its warning), in one pass through the
# house sanitizer's byte set with the newline kept.
replay() {
  [ -s "$1" ] || return 0
  awk 'FILENAME == ARGV[1] { seen[$0] = 1; next } !($0 in seen) { seen[$0] = 1; print }' \
    "$replayed" "$1" | tee -a "$replayed" | tr -d '\000-\011\013-\037\177\200-\237' >&2
}

# ---------------------------------------------------------------------------
# The context renderers (--preamble / --prefix)
# ---------------------------------------------------------------------------
if [ "$preamble" -eq 1 ] || [ "$prefix" -eq 1 ]; then
  if [ "$preamble" -eq 1 ] && [ "$prefix" -eq 1 ]; then
    echo "resolve-steps: --preamble and --prefix are exclusive" >&2
    usage
  fi
  if [ "$explain" -eq 1 ] || [ "$check" -eq 1 ] || [ -n "$attendance" ]; then
    echo "resolve-steps: --preamble / --prefix render the context and take no resolution or attendance flag" >&2
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
        case "$v" in
          " "* | *" " | *"  "*) refuse "$f" "task ids not joined by single spaces" ;;
        esac
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
# Resolution modes: flags, sibling scripts, scratch
# ---------------------------------------------------------------------------
[ -n "$attendance" ] || {
  echo "resolve-steps: pass --attended or --unattended (the missing-step matrix has no default)" >&2
  usage
}
if [ "$check" -eq 1 ] && [ "$attendance" = attended ]; then
  echo "resolve-steps: --check refuses --attended: check mode never waits on a human; pass --unattended" >&2
  usage
fi

config_get_sh="$script_dir/config-get.sh"
catalog_sh="$script_dir/resolve-catalog.sh"
overlay_root_sh="$script_dir/resolve-overlay-root.sh"
isolation_sh="$script_dir/resolve-dispatch-isolation.sh"
for s in "$config_get_sh" "$catalog_sh" "$overlay_root_sh" "$isolation_sh"; do
  [ -x "$s" ] || die 5 "sibling script '$s' is missing or not executable (broken install)"
done

key="steps_${point//-/_}"

# One scratch file holds each sibling's stderr until it is replayed, a second
# the lines already replayed. A signal ends the run with its conventional
# status; the EXIT trap, set first, cleans up.
scratch=""
replayed=""
trap 'rm -f ${scratch:+"$scratch"} ${replayed:+"$replayed"}' EXIT
scratch=$(mktemp) || die 5 "could not create a scratch file"
replayed=$(mktemp) || die 5 "could not create a scratch file"
trap 'exit 130' INT
trap 'exit 143' TERM

# Resolve the repository root once and hand it to every sibling, so they
# skip their own git lookups and every read agrees on the same repository.
if [ -z "${PLANWRIGHT_REPO_ROOT:-}" ]; then
  rc=0
  repo_claude=$("$overlay_root_sh" repo-tracked 2>"$scratch") || rc=$?
  replay "$scratch"
  [ "$rc" -eq 0 ] || die 5 "overlay-root resolution failed for the repo-tracked layer (broken install)"
  if [ -n "$repo_claude" ]; then
    PLANWRIGHT_REPO_ROOT=${repo_claude%/.claude}
    export PLANWRIGHT_REPO_ROOT
  fi
else
  repo_claude="${PLANWRIGHT_REPO_ROOT%/}/.claude"
fi

# DEGRADED: a malformation was degraded with a warning, by this script or by
# a sibling reader; check mode fails on it.
DEGRADED=0

# valid_id <token>: the step-id (and skill-name) charset ^[a-z][a-z0-9-]*$,
# at most 64 bytes.
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
while IFS= read -r l || [ -n "$l" ]; do
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

# read_layers <key>: config-get --layers with its stderr replayed; a warning
# on a successful read is a degraded layer. Sets LAYERS; propagates 4; exit 3
# (absent everywhere) leaves LAYERS empty and returns 3.
read_layers() {
  LAYERS=""
  rl_rc=0
  LAYERS=$("$config_get_sh" --layers "$1" 2>"$scratch") || rl_rc=$?
  replay "$scratch"
  case "$rl_rc" in
    0) [ ! -s "$scratch" ] || DEGRADED=1 ;;
    3) ;;
    4) exit 4 ;;
    *) die 5 "config-get exited $rl_rc reading $1 (broken install)" ;;
  esac
  return "$rl_rc"
}

# ---------------------------------------------------------------------------
# The stale key (REQ-C1.6, D-10): one warning per layer that sets it.
# ---------------------------------------------------------------------------
if read_layers review_sequence; then
  while IFS="$TAB" read -r layer _; do
    [ -n "$layer" ] || continue
    warn "warning: the $layer layer sets review_sequence, the key steps_convergence supersedes; the step resolver ignores its value"
  done <<EOF
$LAYERS
EOF
fi

# ---------------------------------------------------------------------------
# The point's list: winner, shadow warning, parse (REQ-C1.1, REQ-B1.3).
# ---------------------------------------------------------------------------
core_hint="the core defaults ship every point key; the core root follows PLANWRIGHT_ROOT or CLAUDE_PLUGIN_ROOT when set"
read_layers "$key" || die 5 "$key is set in no layer; $core_hint (broken install)"
list_layer=""
list_value=""
core_value=""
core_set=0
shadowed=""
# The shadow set is the OVERLAY layers below the winner: core sets every key,
# so an overlay list always outranks it, and that is the mechanism working,
# not a personal or team list silently overridden (D-5).
while IFS= read -r line; do
  [ -n "$line" ] || continue
  [ -n "$list_layer" ] && [ "$list_layer" != core ] && shadowed="${shadowed:+$shadowed, }$list_layer"
  list_layer=${line%%"$TAB"*}
  list_value=${line#*"$TAB"}
  if [ "$list_layer" = core ]; then
    core_value="$list_value"
    core_set=1
  fi
done <<EOF
$LAYERS
EOF
[ "$core_set" -eq 1 ] || die 5 "$key has no core default; $core_hint (broken install)"
[ -n "$shadowed" ] && warn "warning: $key from the $list_layer layer shadows the $shadowed layer's list"

# parse_list <raw>: sets IDS to one id per line for a flow list `[a, b]`,
# empty for `[]`. A value that is not a flow list, or carries an empty
# field between commas, sets LIST_ERR instead (the bare scalar the
# review-sequence knob tolerated is not a list of step ids); a trailing
# comma is tolerated as YAML tolerates it.
LIST_ERR=""
IDS=""
parse_list() {
  raw="$1"
  LIST_ERR=""
  IDS=""
  case "$raw" in
    \[*\]) ;;
    *)
      LIST_ERR="not an inline flow list [id, ...]"
      return
      ;;
  esac
  raw=${raw#\[}
  raw=${raw%\]}
  raw=${raw#"${raw%%[![:space:]]*}"}
  raw=${raw%"${raw##*[![:space:]]}"}
  [ -n "$raw" ] || return
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
    if [ -z "$field" ]; then
      LIST_ERR="an empty field between commas"
      IDS=""
      break
    fi
    IDS="$IDS$field
"
  done
  IFS=$pl_ifs
}
# validate_list <ids>: LIST_ERR names the first fault, or stays empty.
validate_list() {
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
# parse_and_validate <raw>: sets IDS and LIST_ERR.
parse_and_validate() {
  parse_list "$1"
  [ -n "$LIST_ERR" ] || validate_list "$IDS"
}

# degrade_list <reason>: the by-layer policy for a malformed list
# (REQ-C1.5). Core is a broken install, repo-tracked hard-fails, an adopter
# or machine-local list warns and gives way to the core default, which is
# then the winning list (the matrix keys on core from here on).
degrade_list() {
  case "$list_layer" in
    core) die 5 "the core default $key is malformed ($1) (broken install)" ;;
    repo-tracked) die 4 "the repo-tracked layer sets $key to a malformed value ($1); refusing to degrade a shared team list" ;;
  esac
  warn "warning: the $list_layer layer sets $key to a malformed value ($1); degrading to the core default list"
  DEGRADED=1
  [ "$core_set" -eq 1 ] || die 5 "$key has no core default to degrade to (broken install)"
  list_layer=core
  list_value="$core_value"
  parse_and_validate "$list_value"
  [ -z "$LIST_ERR" ] || die 5 "the core default $key is malformed ($LIST_ERR) (broken install)"
}

parse_and_validate "$list_value"
[ -z "$LIST_ERR" ] || degrade_list "$LIST_ERR"
ids="$IDS"

# An unwired point resolves no steps; a non-empty list there is reported,
# never silently ignored (REQ-A1.3). Check mode still judges the catalog
# below, so a malformation fails it at every point.
if [ "$unwired" -eq 1 ]; then
  if [ -n "$ids" ]; then
    warn "warning: point '$point' is not wired; its non-empty $key list (from the $list_layer layer) resolves no steps"
    [ "$check" -eq 1 ] && exit 1
  fi
  [ "$check" -eq 1 ] || exit 0
  ids=""
fi

# ---------------------------------------------------------------------------
# The hosting default (REQ-D1.3, D-7): from dispatch_isolation.
# ---------------------------------------------------------------------------
rc=0
iso=$("$isolation_sh" 2>"$scratch") || rc=$?
replay "$scratch"
case "$rc" in
  0) [ ! -s "$scratch" ] || DEGRADED=1 ;;
  4) exit 4 ;;
  *) die 5 "dispatch_isolation is unresolvable (exit $rc) (broken install)" ;;
esac
case "$iso" in
  per-step) default_hosting=isolated ;;
  per-unit) default_hosting=in-session ;;
  *) die 5 "dispatch_isolation resolved to an unknown mode (broken install)" ;;
esac

# ---------------------------------------------------------------------------
# The catalog (REQ-B1.1, REQ-B1.2, REQ-B1.6, REQ-C1.8): the merged view for
# the fields, the --explain view for each entry's layer, matched by id.
# ---------------------------------------------------------------------------
# catalog_failed <rc>: resolve-catalog hard-fails with exit 1 naming the
# layer; anything else from it is an unusable sibling.
catalog_failed() {
  if [ "$1" -eq 1 ] && grep -q '^resolve-catalog: steps: repo-tracked ' "$scratch"; then
    die 4 "the repo-tracked steps catalog is malformed; refusing to degrade a shared team catalog"
  fi
  die 5 "the steps catalog is unusable (resolve-catalog exit $1) (broken install)"
}
rc=0
merged=$("$catalog_sh" steps 2>"$scratch") || rc=$?
replay "$scratch"
[ "$rc" -eq 0 ] || catalog_failed "$rc"
# reader_skips <stderr-file>: the by-layer policy for an entry or line the
# catalog reader skipped with a warning (an empty id, an unmarked
# duplicate, an indented line that is not a field): a core one is a broken
# install, a repo-tracked one hard-fails, any other is degraded. The
# --explain view always runs the merge, so a core-only catalog (which the
# plain view passes through verbatim) reports its skips there; both reads
# are judged and replayed, a line the first read printed shown once.
reader_skips() {
  [ -s "$1" ] || return 0
  if grep -q '^resolve-catalog: steps: core ' "$1"; then
    die 5 "the core steps catalog is malformed (an entry or line the catalog reader skipped) (broken install)"
  fi
  if grep -q '^resolve-catalog: steps: repo-tracked ' "$1"; then
    die 4 "the repo-tracked steps catalog is malformed (an entry or line the catalog reader skipped); refusing to degrade a shared team catalog"
  fi
  DEGRADED=1
}
reader_skips "$scratch"
rc=0
layers_view=$("$catalog_sh" steps --explain 2>"$scratch") || rc=$?
replay "$scratch"
[ "$rc" -eq 0 ] || catalog_failed "$rc"
reader_skips "$scratch"
# An adopter or machine-local entry that lost a line to the reader is
# malformed in itself, not merely degraded: its layer and id, collected
# here, drop it once the entries are known.
LOST_LINE_IDS=$(awk '
  !/" carries an indented line that is not a field; skipping the line$/ { next }
  sub(/^resolve-catalog: steps: adopter entry "/, "") { l = "adopter" }
  sub(/^resolve-catalog: steps: machine-local entry "/, "") { l = "machine-local" }
  l != "" {
    sub(/" carries an indented line that is not a field; skipping the line$/, "")
    print l "\t" $0
    l = ""
  }
' "$scratch")

# FIELDS: one `<n>\t<key>\t<value>` line per entry field, <n> the entry's
# ordinal in merged order. Markers: `@cntrl` (a control byte in the key or
# value; the value is never emitted), `@dup` (a repeated field, the item's
# own id included), `@bad` (an indented line that is not a field, which the
# catalog reader already warns about and drops, so a backstop). Every
# item is kept: a core or repo-tracked entry the catalog reader skipped has
# already ended the run through its warning, and an adopter or machine-local
# one is degraded with its warning and absent from the merged view.
FIELDS=$(printf '%s\n' "$merged" | awk '
  /^[ \t]*#/ { next }
  /^[^ \t]/ { insec = ($0 ~ /^[A-Za-z][A-Za-z0-9_-]*:[ \t]*$/); have = 0; next }
  /^[ \t]*$/ { next }
  insec && /^  -[ \t]+id:/ {
    raw = $0; sub(/^  -[ \t]+id:[ \t]*/, "", raw); sub(/[ \t]*$/, "", raw)
    if (raw ~ /^".*"$/ && length(raw) >= 2) raw = substr(raw, 2, length(raw) - 2)
    n++; have = 1
    fseen[n, "id"] = 1
    print n "\tid\t" raw
    if (raw ~ /[[:cntrl:]]/) print n "\t@cntrl\t"
    next
  }
  have && /^    [A-Za-z]/ {
    raw = $0; sub(/^    /, "", raw)
    if (raw ~ /:/) { key = raw; sub(/:.*/, "", key); val = raw; sub(/^[^:]*:[ \t]*/, "", val) }
    else { key = raw; val = "" }
    sub(/[ \t]*$/, "", val)
    if (val ~ /^".*"$/ && length(val) >= 2) val = substr(val, 2, length(val) - 2)
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
# fields the entry declares (`|name|` tokens) so an unset field is told from
# an empty one; E_DROP marks an entry dropped as malformed in itself and
# E_LIST_DROP one dropped for where the current list places it.
E_ID=()
E_LAYER=()
E_DROP=()
E_LIST_DROP=()
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
while IFS="$TAB" read -r n k v; do
  [ -n "$n" ] || continue
  if [ "$n" -gt "$n_entries" ]; then
    n_entries=$n
    E_ID[n]=""
    E_LAYER[n]=""
    E_DROP[n]=0
    E_LIST_DROP[n]=0
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
[ "$n_entries" -gt 0 ] || die 5 "the steps catalog holds no entry; the core seed always does (broken install)"
# The core seed is judged by its own file: an overlay may supersede every
# seed entry, so the merged layers alone cannot tell a superseded seed from a
# missing one.
rc=0
core_root=$("$overlay_root_sh" core 2>"$scratch") || rc=$?
replay "$scratch"
[ "$rc" -eq 0 ] || die 5 "overlay-root resolution failed for the core layer (broken install)"
core_seed="${core_root:+$core_root/config/steps.yaml}"
{ [ -n "$core_seed" ] && [ -r "$core_seed" ] && grep -q '^[[:space:]]*- id:' "$core_seed"; } \
  || die 5 "the core steps seed contributed no entry (broken install)"
# The --explain view supplies each entry's layer, matched by id: the
# catalog reader skips an id that would not re-parse identically (an edge
# blank or quote), so the merged view carries every id exactly as the reader
# stored it, and ids are unique. With one section the two views list entries in the same order and
# the ordinal must carry the same id; with several, the merged view is
# grouped by section and each view line must match exactly one entry. A
# mismatch (a catalog edited between the two reads, say) is never guessed
# at: the run fails closed. The layer is the last field, so an id carrying a
# tab still splits.
n_sections=$(printf '%s\n' "$merged" | awk '/^[A-Za-z][A-Za-z0-9_-]*:[ \t]*$/ { c++ } END { print c + 0 }')
n_layers=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  n_layers=$((n_layers + 1))
  view_id=${line%"$TAB"*}
  view_layer=${line##*"$TAB"}
  matched=0
  if [ "$n_sections" -le 1 ]; then
    [ "$n_layers" -le "$n_entries" ] || break
    [ "${E_ID[n_layers]}" = "$view_id" ] || die 5 "resolve-catalog's two views disagree at entry $n_layers (broken install)"
    matched=$n_layers
  else
    i=1
    while [ "$i" -le "$n_entries" ]; do
      if [ "${E_ID[i]}" = "$view_id" ]; then
        { [ "$matched" -eq 0 ] && [ -z "${E_LAYER[i]}" ]; } || die 5 "resolve-catalog's two views cannot be aligned: an id is ambiguous (broken install)"
        matched=$i
      fi
      i=$((i + 1))
    done
    [ "$matched" -gt 0 ] || die 5 "resolve-catalog's two views cannot be aligned: an entry matches no id (broken install)"
  fi
  E_LAYER[matched]="$view_layer"
done <<EOF
$layers_view
EOF
[ "$n_layers" -eq "$n_entries" ] || die 5 "resolve-catalog's two views disagree ($n_entries entries, $n_layers layers) (broken install)"
i=1
while [ "$i" -le "$n_entries" ]; do
  [ -n "${E_LAYER[i]}" ] || die 5 "resolve-catalog's two views disagree at entry $i (broken install)"
  i=$((i + 1))
done
# is_set <n> <field>: 0 when the entry declares the field (even empty).
is_set() {
  sn="$1"
  case "${E_SET[sn]}" in
    *"|$2|"*) return 0 ;;
  esac
  return 1
}

# entry_malformed <n> <reason> [list]: the by-layer policy for an entry
# (REQ-C1.5). Returns only for the degrade arm, the entry then dropped (its
# id non-resolving under the matrix): from the merged catalog, or, with
# `list`, only for the current list's order, which the core fallback resets.
entry_malformed() {
  en="$1"
  case "${E_LAYER[en]}" in
    core) die 5 "core steps catalog entry ${E_ID[en]:-#$en} is malformed ($2) (broken install)" ;;
    repo-tracked) die 4 "repo-tracked steps catalog entry ${E_ID[en]:-#$en} is malformed ($2); refusing to degrade a shared team catalog" ;;
    *)
      if [ "${3:-}" = list ]; then
        warn "warning: ${E_LAYER[en]} steps catalog entry ${E_ID[en]:-#$en} is malformed where this list places it ($2); dropped for this list"
        E_LIST_DROP[en]=1
      else
        warn "warning: ${E_LAYER[en]} steps catalog entry ${E_ID[en]:-#$en} is malformed ($2); dropped from the merged catalog"
        E_DROP[en]=1
      fi
      DEGRADED=1
      ;;
  esac
}

# Charsets. A command target is an executable name or path in
# [A-Za-z0-9/._-], no leading dash, no `..` segment; a `requires` name takes
# the same charset; a command-args word is in [A-Za-z0-9._/:=@%,+-]; a skill
# name and namespace take the id charset.
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
# split_skill_target <target>: sets SNAME and SPLUGIN (empty when bare);
# returns 1 when the target is outside the grammar <name> | <plugin>:<name>.
split_skill_target() {
  SNAME=""
  SPLUGIN=""
  case "$1" in
    *:*:*) return 1 ;;
    *:*)
      SPLUGIN=${1%%:*}
      SNAME=${1#*:}
      valid_id "$SPLUGIN" || return 1
      ;;
    *) SNAME="$1" ;;
  esac
  valid_id "$SNAME"
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
  # The constrained reader takes single-line scalars only, so a YAML block
  # indicator (with its chomping or indentation suffix) is a declaration
  # whose body was dropped, never a value.
  for scalar in "$vtarget" "$vargs"; do
    case "$scalar" in
      [\|\>] | [\|\>][0-9+-] | [\|\>][0-9+-][0-9+-])
        ERR="a block scalar (the catalog reader takes single-line scalars only)"
        return
        ;;
    esac
  done
  vhost=${E_HOST[vn]}
  case "$vhost" in
    isolated | continue | in-session) ;;
    "")
      if is_set "$vn" hosting; then
        ERR="empty hosting"
        return
      fi
      ;;
    *)
      ERR="unknown hosting"
      return
      ;;
  esac
  vfail=${E_FAIL[vn]}
  case "$vfail" in
    halt | continue) ;;
    "")
      if is_set "$vn" on-failure; then
        ERR="empty on-failure"
        return
      fi
      ;;
    *)
      ERR="unknown on-failure"
      return
      ;;
  esac
  # A declared-but-empty optional field is refused too: the constrained
  # reader sees a block value (a nested list under `requires:`) as an empty
  # scalar, so accepting one would silently drop the declaration.
  vtimeout=${E_TIMEOUT[vn]}
  bad_timeout=0
  case "$vtimeout" in
    "") is_set "$vn" timeout && bad_timeout=1 ;;
    *[!0-9]* | 0*) bad_timeout=1 ;;
  esac
  # Fifteen digits keeps the value inside the shell arithmetic the runner
  # and its hosting tool apply to it.
  [ "${#vtimeout}" -le 15 ] || bad_timeout=1
  [ "$bad_timeout" -eq 0 ] || {
    ERR="timeout is not a positive integer of seconds"
    return
  }
  vreq=${E_REQ[vn]}
  if [ -z "$vreq" ] && is_set "$vn" requires; then
    ERR="empty requires"
    return
  fi
  if [ -z "$vargs" ] && is_set "$vn" args; then
    ERR="empty args"
    return
  fi
  for r in $vreq; do
    command_target_ok "$r" || {
      ERR="requires names something outside the command-target charset"
      return
    }
  done
  case "$vkind" in
    skill)
      split_skill_target "$vtarget" || {
        ERR="skill target outside the grammar <name> | <plugin>:<name>"
        return
      }
      if is_pipeline_entry "$SNAME"; then
        ERR="pipeline-entry: '$SNAME' is a pipeline entry skill and never a step target"
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
  lost=0
  while IFS="$TAB" read -r ll lid; do
    [ "$ll" = "${E_LAYER[i]}" ] && [ "$lid" = "${E_ID[i]}" ] && lost=1
  done <<EOF
$LOST_LINE_IDS
EOF
  if [ "$lost" -eq 1 ]; then
    entry_malformed "$i" "an indented line the catalog reader skipped"
  else
    validate_entry "$i"
    [ -z "$ERR" ] || entry_malformed "$i" "$ERR"
  fi
  i=$((i + 1))
done

# entry_of <id>: sets ENTRY to the ordinal of the live entry carrying <id>
# (empty when none) and ENTRY_DROPPED when a dropped one carries it.
entry_of() {
  ENTRY=""
  ENTRY_DROPPED=0
  j=1
  while [ "$j" -le "$n_entries" ]; do
    if [ "${E_ID[j]}" = "$1" ]; then
      if [ "${E_DROP[j]}" -eq 0 ] && [ "${E_LIST_DROP[j]}" -eq 0 ]; then
        ENTRY="$j"
        return 0
      fi
      ENTRY_DROPPED=1
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
  # shellcheck disable=SC2016 # $p is a jq variable bound with --arg, not a shell expansion
  keys=$("$jq_bin" -r --arg p "$1@" '(.plugins // {}) | keys[] | select(startswith($p))' "$reg" 2>/dev/null) || {
    REASON="the installed-plugin registry is unreadable"
    return 1
  }
  nkeys=0
  while IFS= read -r rk; do
    [ -n "$rk" ] && nkeys=$((nkeys + 1))
  done <<EOF
$keys
EOF
  if [ "$nkeys" -eq 0 ]; then
    REASON="namespace '$1' matches no installed-plugin registry key"
    return 1
  fi
  if [ "$nkeys" -gt 1 ]; then
    REASON="namespace '$1' matches $nkeys installed-plugin registry keys (ambiguous)"
    return 1
  fi
  # shellcheck disable=SC2016 # $k is a jq variable bound with --arg, not a shell expansion
  paths=$("$jq_bin" -r --arg k "$keys" '.plugins[$k] | (if type == "array" then .[] else . end) | (.installPath? // empty) | select(type == "string")' "$reg" 2>/dev/null) || {
    REASON="the installed-plugin registry is unreadable"
    return 1
  }
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in /*) ;; *) continue ;; esac
    case "$p" in *[[:cntrl:]]*) continue ;; esac
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
      split_skill_target "$rtarget"
      if [ -z "$SPLUGIN" ]; then
        for cand in "${skills_root:+$skills_root/$SNAME/SKILL.md}" \
          "${claude_dir:+$claude_dir/commands/$SNAME.md}" \
          "${claude_dir:+$claude_dir/skills/$SNAME/SKILL.md}" \
          "${repo_claude:+$repo_claude/commands/$SNAME.md}" \
          "${repo_claude:+$repo_claude/skills/$SNAME/SKILL.md}"; do
          case "$cand" in "" | *[[:cntrl:]]*) continue ;; esac
          if [ -f "$cand" ]; then
            LOC="$cand"
            break
          fi
        done
        [ -n "$LOC" ] || {
          REASON="skill '$SNAME' not found under the plugin skills root or the user and project command and skill directories"
          return 1
        }
      elif [ "$SPLUGIN" = "$OWN_NAMESPACE" ]; then
        if [ -n "$skills_root" ] && [ -f "$skills_root/$SNAME/SKILL.md" ]; then
          LOC="$skills_root/$SNAME/SKILL.md"
        else
          REASON="skill '$OWN_NAMESPACE:$SNAME' not found under the plugin skills root"
          return 1
        fi
      else
        registry_lookup "$SPLUGIN" "$SNAME" || return 1
      fi
      ;;
  esac
  case "$LOC" in
    *[[:cntrl:]]*)
      LOC=""
      REASON="the location the host resolved carries a control byte"
      return 1
      ;;
  esac
  rreq=${E_REQ[rn]}
  for r in $rreq; do
    case "$r" in
      */*)
        { [ -f "$r" ] && [ -x "$r" ]; } || {
          REASON="requires '$r' not found or not executable at that path"
          return 1
        }
        ;;
      *)
        type -P "$r" >/dev/null 2>&1 || {
          REASON="requires '$r' not found on the path"
          return 1
        }
        ;;
    esac
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

# build_steps <ids>: fills S_*; sets LIST_ERR when the list must degrade.
# A `continue` with no session to attach to is a fault of the list and the
# entry together, so a personal layer's part never breaks a shared one: an
# adopter or machine-local list degrades; otherwise an adopter or
# machine-local entry is dropped for this list; otherwise a repo-tracked
# list or entry hard-fails and an all-core pairing is a broken install. A
# timeout on a step that lands in-session is the declaring entry's, judged
# only once the list is known not to degrade, so the order of a list never
# decides between the two.
build_steps() {
  LIST_ERR=""
  n_steps=0
  n_placed=0
  P_N=()
  P_FAULT=()
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
    if entry_of "$sid"; then
      en="$ENTRY"
      S_N[n_steps]="$en"
      S_KIND[n_steps]=${E_KIND[en]}
      h=${E_HOST[en]}
      [ -n "$h" ] || h="$default_hosting"
      fault=""
      if [ "$h" = continue ]; then
        prev=$((n_steps - 1))
        if [ "$n_steps" -eq 1 ]; then
          fault="hosting continue at the first position (no predecessor)"
        elif [ "${S_KIND[prev]}" = command ] && [ "${S_HOST[prev]}" = isolated ]; then
          fault="hosting continue immediately after the isolated command step '${S_ID[prev]}' (a runner subprocess records no session to attach to)"
        elif [ "${S_HOST[prev]}" = in-session ]; then
          h=in-session
        fi
      fi
      if [ -n "$fault" ]; then
        case "$list_layer/${E_LAYER[en]}" in
          adopter/* | machine-local/*)
            LIST_ERR="'$sid' declares $fault"
            return
            ;;
          */adopter | */machine-local) ;;
          repo-tracked/* | */repo-tracked) die 4 "the repo-tracked layer's list or entry places '$sid' malformed ($fault); refusing to degrade shared team config" ;;
          *) die 5 "the core default $key places '$sid' malformed ($fault) (broken install)" ;;
        esac
      fi
      S_HOST[n_steps]="$h"
      t=${E_TIMEOUT[en]}
      if [ -z "$fault" ] && [ -n "$t" ] && [ "$h" = in-session ] && [ "${S_KIND[n_steps]}" != command ]; then
        fault="timeout on a ${S_KIND[n_steps]} step that is effectively in-session (the unit session cannot end itself)"
      fi
      if [ -n "$fault" ]; then
        n_placed=$((n_placed + 1))
        P_N[n_placed]="$en"
        P_FAULT[n_placed]="$fault"
        E_LIST_DROP[en]=1
        S_N[n_steps]=""
        S_KIND[n_steps]="-"
        S_HOST[n_steps]="-"
        S_REASON[n_steps]="its catalog entry was dropped as malformed"
      fi
    else
      S_N[n_steps]=""
      S_KIND[n_steps]="-"
      S_HOST[n_steps]="-"
      if [ "$ENTRY_DROPPED" -eq 1 ]; then
        S_REASON[n_steps]="its catalog entry was dropped as malformed"
      else
        S_REASON[n_steps]="no catalog entry carries this id"
      fi
    fi
  done <<EOF
$1
EOF
  pi=1
  while [ "$pi" -le "$n_placed" ]; do
    entry_malformed "${P_N[pi]}" "${P_FAULT[pi]}" list
    pi=$((pi + 1))
  done
}

build_steps "$ids"
if [ -n "$LIST_ERR" ]; then
  degrade_list "$LIST_ERR"
  ids="$IDS"
  i=1
  while [ "$i" -le "$n_entries" ]; do
    E_LIST_DROP[i]=0
    i=$((i + 1))
  done
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
case "$list_layer/$attendance" in
  core/*) missing_token=park ;;
  repo-tracked/attended | adopter/attended | machine-local/attended) missing_token=ask ;;
  repo-tracked/unattended) missing_token=park ;;
  adopter/unattended | machine-local/unattended) missing_token=skip ;;
  *) die 5 "config-get named an unrecognized layer '$list_layer' (broken install)" ;;
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
      warn "${missing_token}: step '${S_ID[i]}' does not resolve on this host: ${S_REASON[i]}; the point $verb (the $list_layer layer's list, $attendance)"
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
  line="$dec$TAB${S_ID[i]}"
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
    line="$line$TAB$point$TAB$list_layer$TAB$elayer$TAB$etarget$TAB${S_HOST[i]}$TAB${S_KIND[i]}$TAB${eargs:--}$TAB$efail$TAB${etimeout:--}$TAB${ereq:--}$TAB${S_LOC[i]}"
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
