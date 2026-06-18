#!/bin/sh
# spec-scope.sh — the model-stream scope filter for /spec-walkthrough.
#
# Task 9 of specs/spec-comprehension (D-11; REQ-B1.1, REQ-B1.2): the partial-view
# substrate. It reduces the bundle reader model (Task 2, scripts/spec-model.sh)
# to a single requested scope, so the assembler can render only the part the
# reader asked for. The five partial selectors of REQ-B1.2, plus the whole-bundle
# default:
#
#   whole                 the whole bundle (default; a pass-through)
#   file:<name>           one source file (requirements|design|tasks|test-spec)
#   reqs:<GROUP>          one requirement group (e.g. reqs:A)
#   decisions             the decision set
#   tasks                 the task graph
#   decision:<id>         a single decision plus its blast radius — the
#                         requirements and tasks that cite it (the bundle
#                         glossary's reading: what the decision affects). The
#                         id accepts the bare number or a D-/d- prefix.
#
# The BUNDLE and FILE inventory records always survive, in every scope, so the
# downstream framing still resolves the bundle name and status and the file
# inventory (graceful degradation, REQ-A1.5) is never lost to a narrow scope.
#
# The record vocabulary is exactly spec-model.sh's; this filter only drops
# records, never rewrites them, so the reveal seam stays lossless (D-2): a
# scoped stream is a strict subset of the full model.
#
# Usage:
#   spec-scope.sh [--scope <selector>] <spec-dir>   # run the model then filter
#   spec-model.sh <spec-dir> | spec-scope.sh [--scope <selector>]   # filter a stream
#
# With a <spec-dir> argument it runs scripts/spec-model.sh (a sibling) over the
# directory and filters the result; with no argument it reads a model stream on
# stdin (the composable pipe). It is strictly read-only (REQ-A1.3): it writes
# nothing but its stdout stream.
#
# Exit codes:
#   0  the filtered stream was emitted.
#   2  usage or environment error: an unknown/ malformed selector (fail closed —
#      a bad selector is never silently treated as whole), or, in <spec-dir>
#      mode, the model script could not be found or the spec directory is absent
#      or unreadable (propagated from scripts/spec-model.sh).
#
# Portable: /bin/sh + awk as shipped on macOS (bash 3.2, BSD userland) and Linux
# (the REQ-K1.5 envelope). No gawk-only constructs, no eval; input treated as
# data only (the selector reaches awk through -v, never as code).
set -eu

LC_ALL=C
export LC_ALL
unset CDPATH

usage() {
  echo "usage: spec-scope.sh [--scope <selector>] [<spec-dir>]" >&2
  exit 2
}

# sanitize_echo <string> — strip control characters before echoing untrusted
# content (the spec-validate echo discipline, REQ-H1.3: a hostile value must not
# reach the terminal raw, where escape sequences could manipulate it), with a
# placeholder when nothing printable remains. spec-scope.sh is callable directly,
# not always behind the scaffold's charset gate, so the selector is sanitized
# here too (matching the sibling spec-walkthrough.sh / spec-assemble.sh). Display
# only; the classification below still matches on the raw $scope.
sanitize_echo() {
  se=$(printf '%s' "$1" | tr -d '\000-\037\177')
  [ -n "$se" ] || se="(unprintable)"
  printf '%s' "$se"
}

scope=
spec_dir=
while [ $# -gt 0 ]; do
  case $1 in
    --scope)
      [ $# -ge 2 ] || usage
      scope=$2
      shift 2
      ;;
    -)
      shift
      ;;
    -*)
      usage
      ;;
    *)
      [ -z "$spec_dir" ] || usage
      spec_dir=$1
      shift
      ;;
  esac
done

# Classify and validate the selector before it reaches awk. The selector is
# never interpolated as code: kind/name/group/target are passed via -v, and each
# component is charset-validated here so a malformed selector fails closed (exit
# 2) rather than degrading to a silent whole-bundle render.
kind=whole
name=
group=
target=
# A control-character-stripped copy of the selector for the error messages below
# (echo discipline); the case still matches on the raw $scope.
scope_safe=$(sanitize_echo "$scope")
case ${scope:-whole} in
  whole | "")
    kind=whole
    ;;
  file:*)
    name=${scope#file:}
    name=${name%.md}
    case $name in
      requirements | design | tasks | test-spec) kind="file" ;;
      *)
        echo "spec-scope: scope '$scope_safe' names no source file (expected file:requirements|design|tasks|test-spec)" >&2
        exit 2
        ;;
    esac
    ;;
  reqs:*)
    group=${scope#reqs:}
    case $group in
      "" | *[!A-Z]*)
        echo "spec-scope: scope '$scope_safe' is not a requirement group (expected reqs:<GROUP>, uppercase letters)" >&2
        exit 2
        ;;
    esac
    kind=reqs
    ;;
  decisions)
    kind=decisions
    ;;
  tasks)
    kind=tasks
    ;;
  decision:*)
    target=${scope#decision:}
    target=${target#D-}
    target=${target#d-}
    case $target in
      "" | *[!0-9]*)
        echo "spec-scope: scope '$scope_safe' is not a decision id (expected decision:<id>)" >&2
        exit 2
        ;;
    esac
    target="D-$target"
    kind=decision
    ;;
  *)
    echo "spec-scope: unknown scope '$scope_safe' (valid: whole, file:<name>, reqs:<GROUP>, decisions, tasks, decision:<id>)" >&2
    exit 2
    ;;
esac

tab=$(printf '\t')

# The filter. Buffers the model stream (small) so the two scopes that need a
# second pass — reqs (collect the group's requirement ids) and decision (collect
# the blast radius from the citation edges) — can resolve their keep-set before
# emitting. Records are emitted in input order; only column 1 (the tag) and the
# two key columns are inspected, so the body bytes pass through untouched.
# shellcheck disable=SC2016 # $1..$3/$0 are awk fields, not shell expansions
filter() {
  awk -F"$tab" -v kind="$kind" -v name="$name" -v group="$group" -v target="$target" '
    { line[NR] = $0; tag[NR] = $1; c2[NR] = $2; c3[NR] = $3 }
    END {
      # Second-pass keep-sets.
      if (kind == "reqs") {
        for (i = 1; i <= NR; i++)
          if (tag[i] == "REQ" && c3[i] == group) keepreq[c2[i]] = 1
      } else if (kind == "file" && name == "test-spec") {
        # The test-spec file pins requirements to verification paths; its content
        # is the set of (requirement, verification) pairs. Keep each tested
        # requirement as the verification subject so the view can label it in
        # plain language (REQ-C1.1) rather than as a bare id.
        for (i = 1; i <= NR; i++)
          if (tag[i] == "TEST") tested[c2[i]] = 1
      } else if (kind == "decision") {
        # Blast radius: every requirement and task whose citation edge points at
        # the target decision (REQCITE/TASKCITE column 3 is the cited id).
        for (i = 1; i <= NR; i++) {
          if (tag[i] == "REQCITE"  && c3[i] == target) blastreq[c2[i]]  = 1
          if (tag[i] == "TASKCITE" && c3[i] == target) blasttask[c2[i]] = 1
        }
      }
      for (i = 1; i <= NR; i++) {
        t = tag[i]
        # The bundle and file inventory always survive (downstream framing reads
        # the BUNDLE status; FILE records carry the degradation inventory).
        if (t == "BUNDLE" || t == "FILE") { print line[i]; continue }
        keep = 0
        if (kind == "whole") {
          keep = 1
        } else if (kind == "file") {
          if (name == "requirements")    keep = (t == "REQ" || t == "REQCITE")
          else if (name == "design")     keep = (t == "DEC" || t == "DECFIELD")
          else if (name == "tasks")      keep = (t == "TASK" || t == "TASKFIELD" || t == "TASKDEP" || t == "TASKCITE")
          else if (name == "test-spec") {
            if (t == "TEST")          keep = 1
            else if (t == "REQ")      keep = (c2[i] in tested)
            else if (t == "REQCITE")  keep = (c2[i] in tested)
          }
        } else if (kind == "decisions") {
          keep = (t == "DEC" || t == "DECFIELD")
        } else if (kind == "tasks") {
          keep = (t == "TASK" || t == "TASKFIELD" || t == "TASKDEP" || t == "TASKCITE")
        } else if (kind == "reqs") {
          if (t == "REQ")          keep = (c3[i] == group)
          else if (t == "REQCITE") keep = (c2[i] in keepreq)
        } else if (kind == "decision") {
          if (t == "DEC" || t == "DECFIELD")           keep = (c2[i] == target)
          else if (t == "REQ" || t == "REQCITE")       keep = (c2[i] in blastreq)
          else if (t == "TASK" || t == "TASKFIELD" || t == "TASKDEP" || t == "TASKCITE") keep = (c2[i] in blasttask)
        }
        if (keep) print line[i]
      }
    }
  '
}

if [ -n "$spec_dir" ]; then
  here=$(cd "$(dirname "$0")" && pwd)
  model_sh="$here/spec-model.sh"
  if [ ! -x "$model_sh" ]; then
    echo "spec-scope: cannot find an executable spec-model.sh at $model_sh" >&2
    exit 2
  fi
  # Capture the model first so its exit status propagates (a pipe would yield
  # awk's status; /bin/sh has no portable pipefail). A failed model (absent or
  # unreadable spec directory) fails closed here, exit 2 propagated.
  model=$("$model_sh" "$spec_dir") || exit $?
  printf '%s\n' "$model" | filter
else
  filter
fi
