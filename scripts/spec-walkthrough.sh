#!/bin/sh
# spec-walkthrough.sh — the /spec-walkthrough command scaffold.
#
# Task 1 of specs/spec-comprehension: the command surface for the standalone,
# read-only comprehension aid (REQ-A1.1, D-1). This scaffold owns argument and
# flag parsing, the identifier-charset + path-containment safety gate, the
# read-only status-agnostic bundle load, and graceful degradation; it emits a
# load report that the rendering tasks (the bundle model, the plain-language
# translation, the views, the HTML assembly) build on. It renders no artifact
# yet — artifact production lands with the HTML-assembly task.
#
# Usage:
#   spec-walkthrough.sh [--scope <selector>] [--reveal] <spec-path>
#
# <spec-path> is `specs/<spec>` or the bare `<spec>` (the two sanctioned forms,
# the same pair the sibling skills accept), resolved relative to the current
# directory — the repo-root invocation contract, as `mise run check:specs`
# calls the validator. <selector> names which part to render (REQ-B1.2):
#   whole                 the whole bundle (default)
#   file:<name>           one source file (requirements|design|tasks|test-spec)
#   reqs:<GROUP>          one requirement group (e.g. reqs:A)
#   decisions             the decision set
#   tasks                 the task graph
#   decision:<id>         a single decision plus its blast radius (e.g.
#                         decision:1 or decision:D-1)
# --reveal exposes the underlying identifiers; it is off by default (REQ-D1.3).
#
# Read-only (REQ-A1.3): this scaffold writes nothing. The only sanctioned write
# in the whole command is the generated artifact to the gitignored location,
# owned by a later task; Task 1 produces no file.
#
# Status-agnostic (REQ-A1.4, REQ-B1.4): every status renders, including the
# terminal Retired/Superseded, in deliberate contrast with the execution
# skills' non-Active refusal — rendering is read-only, so that refusal's safety
# rationale does not apply.
#
# Exit codes:
#   0  the bundle loaded (full or partial); the load report was emitted.
#   1  graceful degradation, nothing to load: the bundle directory is absent,
#      holds none of the four files, or the requested scope resolves to no part
#      of it. A clear message names what is absent / the available scopes; never
#      an opaque halt (REQ-A1.5).
#   2  clean refusal: a malformed invocation (usage), or a hostile/malformed
#      spec identifier or a path that escapes the specs/ tree. Hostile input is
#      refused before any read, never echoed back, and never becomes a path
#      (REQ-A1.6).
#
# Portable: /bin/sh + awk + sed + grep (incl. grep -o) + tr as shipped on macOS
# (bash 3.2, BSD userland) and Linux (the REQ-K1.5 envelope). No eval; input
# treated as data only.
set -eu

# Pin the C locale: charset checks and awk/grep ranges must not vary by host
# locale collation.
LC_ALL=C
export LC_ALL

# Neutralize a user CDPATH: the path-containment check resolves real paths via
# `$(cd <dir> && pwd -P)`, and with CDPATH set `cd` echoes the resolved
# destination into the command substitution, prepending a stray line that
# breaks the containment comparison and spuriously refuses a valid bundle (the
# house pattern every sibling script follows).
unset CDPATH

usage() {
  echo "usage: spec-walkthrough.sh [--scope <selector>] [--reveal] <spec-path>" >&2
  exit 2
}

# Full-string spec-identifier check (REQ-A1.6, the REQ-A1.8 discipline):
# ^[a-z0-9][a-z0-9-]*$, max 64. The slash that a multi-component or traversal
# path would carry is outside the charset, so this same check rejects them.
check_spec_id() {
  cid=$1
  [ -n "$cid" ] || return 1
  [ "${#cid}" -le 64 ] || return 1
  case $cid in
    [a-z0-9]*) ;;
    *) return 1 ;;
  esac
  case $cid in
    *[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

# first_header <file> <key> — first "**<key>:** value" header line's value,
# with non-printables stripped: extracted values are echoed in the report, and
# hostile file content must not reach the terminal raw (the spec-validate echo
# discipline).
first_header() {
  awk -v key="$2" '
    index($0, "**" key ":**") == 1 {
      sub(/^\*\*[^*]*:\*\*[ \t]*/, "")
      gsub(/[^[:print:]]/, "")
      print
      exit
    }
  ' "$1"
}

# sanitize_echo <string> — strip control characters before echoing untrusted
# content (the spec-validate echo discipline: a hostile value must not reach the
# terminal raw, where escape sequences could manipulate it), with a placeholder
# when nothing printable remains. Display only; logic uses the raw value.
sanitize_echo() {
  se=$(printf '%s' "$1" | tr -d '\000-\037\177')
  [ -n "$se" ] || se="(unprintable)"
  printf '%s' "$se"
}

# join_lines — read a newline list on stdin, print it ", "-joined on one line.
join_lines() {
  awk '{ if (seen) printf ", "; printf "%s", $0; seen = 1 } END { if (seen) printf "\n" }'
}

scope=
reveal=off
specpath=
while [ $# -gt 0 ]; do
  case $1 in
    --scope)
      [ $# -ge 2 ] || usage
      scope=$2
      shift 2
      ;;
    --reveal)
      reveal=on
      shift
      ;;
    -*)
      usage
      ;;
    *)
      [ -z "$specpath" ] || usage
      specpath=$1
      shift
      ;;
  esac
done

[ -n "$specpath" ] || usage

# Derive the spec identifier from the path before it is ever used as a path
# (REQ-A1.6). Strip a trailing slash and an optional single leading `specs/`;
# what remains must be a bare identifier. A charset failure here is a clean
# refusal that never names the candidate back.
spec=$specpath
while [ "$spec" != "${spec%/}" ]; do spec=${spec%/}; done
case $spec in
  specs/*) spec=${spec#specs/} ;;
esac
if ! check_spec_id "$spec"; then
  echo "spec-walkthrough: invalid spec identifier (must match ^[a-z0-9][a-z0-9-]*\$, max length 64); refused before any read" >&2
  exit 2
fi

bundle_dir="specs/$spec"

# Path containment (REQ-A1.6): when the bundle directory exists, its real path
# must sit inside the real specs/ tree. A symlink whose target escapes specs/ is
# refused before any file is read; the resolved path is never echoed. The gate
# fails closed: if either real path cannot be resolved, the containment decision
# cannot be made, so we refuse before any read rather than fall through to the
# file load with the check silently skipped.
if [ -d "$bundle_dir" ]; then
  specs_real=$(cd specs 2>/dev/null && pwd -P) || specs_real=
  bundle_real=$(cd "$bundle_dir" 2>/dev/null && pwd -P) || bundle_real=
  if [ -z "$specs_real" ] || [ -z "$bundle_real" ]; then
    echo "spec-walkthrough: could not resolve the bundle's real path for the containment check; refused before any read" >&2
    exit 2
  fi
  case "$bundle_real/" in
    "$specs_real/"*) ;;
    *)
      echo "spec-walkthrough: resolved bundle path escapes the specs/ tree; refused before any read" >&2
      exit 2
      ;;
  esac
fi

# Missing bundle: a clear, non-opaque degradation naming the expected location
# and the four files it would hold (REQ-A1.5).
if [ ! -d "$bundle_dir" ]; then
  echo "spec-walkthrough: no bundle at specs/$spec — the directory is absent (expected requirements.md, design.md, tasks.md, test-spec.md)" >&2
  exit 1
fi

# Inventory the four files. read-only: nothing is written.
present=
missing=
for f in requirements.md design.md tasks.md test-spec.md; do
  if [ -f "$bundle_dir/$f" ]; then
    if [ -z "$present" ]; then present=$f; else present="$present, $f"; fi
  else
    if [ -z "$missing" ]; then missing=$f; else missing="$missing, $f"; fi
  fi
done

# An empty bundle (directory present, none of the four files): degrade rather
# than render an empty artifact (REQ-A1.5).
if [ -z "$present" ]; then
  echo "spec-walkthrough: bundle at specs/$spec holds none of the four spec files (expected requirements.md, design.md, tasks.md, test-spec.md)" >&2
  exit 1
fi

# Status (auto-detected; status-agnostic, never a refusal). Authoritative home
# is requirements.md; only when it is absent does a sibling mirror stand in.
status=
if [ -f "$bundle_dir/requirements.md" ]; then
  # requirements.md is the authoritative Status home; an empty value there is
  # reported as undeclared rather than masked by a sibling mirror.
  status=$(first_header "$bundle_dir/requirements.md" Status)
else
  # Authoritative home absent: derive from the first sibling that declares one.
  for f in design.md tasks.md test-spec.md; do
    [ -f "$bundle_dir/$f" ] || continue
    status=$(first_header "$bundle_dir/$f" Status)
    [ -n "$status" ] && break
  done
fi
[ -n "$status" ] || status="(undeclared)"

# Resolve the requested scope against what the bundle actually holds. The scope
# selector never becomes a path; an unresolvable but charset-valid selector is
# a content-level degradation (exit 1) naming the available scopes, not the
# path-level refusal (exit 2). Each interpolated component is charset-validated
# before it reaches grep, so a selector cannot inject a pattern.
req_groups() {
  [ -f "$bundle_dir/requirements.md" ] || return 0
  grep -oE '^## REQ-[A-Z]+' "$bundle_dir/requirements.md" 2>/dev/null \
    | sed 's/^## REQ-//' | join_lines
}
decision_ids() {
  [ -f "$bundle_dir/design.md" ] || return 0
  # Only the spec-conforming `### D-<n>:` form (doctrine/spec-format.md; the
  # colon is required and the validator flags a colon-less `### D-` as
  # malformed). This is the same form the decision:<id> resolver matches, so a
  # listed decision is always one the resolver can resolve. Strip the trailing
  # colon before joining.
  grep -oE '^### D-[0-9]+:' "$bundle_dir/design.md" 2>/dev/null \
    | sed 's/^### //; s/:$//' | join_lines
}

scope_label=
# The raw selector is echoed back in degradation messages; sanitize the display
# copy so a hostile --scope value cannot reach the terminal raw. Logic below
# still matches on the raw $scope.
scope_safe=$(sanitize_echo "$scope")
case ${scope:-whole} in
  whole | "")
    scope_label="whole bundle"
    ;;
  file:*)
    name=${scope#file:}
    name=${name%.md}
    case $name in
      requirements | design | tasks | test-spec)
        if [ -f "$bundle_dir/$name.md" ]; then
          scope_label="file $name.md"
        else
          echo "spec-walkthrough: scope '$scope_safe' names a file absent from specs/$spec; available files: $present" >&2
          exit 1
        fi
        ;;
      *)
        echo "spec-walkthrough: scope '$scope_safe' names no source file; available files: $present" >&2
        exit 1
        ;;
    esac
    ;;
  reqs:*)
    group=${scope#reqs:}
    case $group in
      "" | *[!A-Z]*)
        echo "spec-walkthrough: scope '$scope_safe' is not a requirement group (expected reqs:<GROUP>); available groups: $(req_groups)" >&2
        exit 1
        ;;
    esac
    if [ ! -f "$bundle_dir/requirements.md" ]; then
      echo "spec-walkthrough: scope '$scope_safe' names a requirement group, but requirements.md is absent from specs/$spec" >&2
      exit 1
    fi
    if grep -qE "^## REQ-$group( |\$)" "$bundle_dir/requirements.md" 2>/dev/null; then
      scope_label="requirement group $group"
    else
      echo "spec-walkthrough: scope '$scope_safe' resolves to no requirement group in specs/$spec; available groups: $(req_groups)" >&2
      exit 1
    fi
    ;;
  decisions)
    if [ -f "$bundle_dir/design.md" ] && grep -qE '^### D-[0-9]+:' "$bundle_dir/design.md" 2>/dev/null; then
      scope_label="decision set"
    else
      echo "spec-walkthrough: scope 'decisions' resolves to no decision set in specs/$spec; design.md is absent or holds no decisions" >&2
      exit 1
    fi
    ;;
  tasks)
    if [ -f "$bundle_dir/tasks.md" ]; then
      scope_label="task graph"
    else
      echo "spec-walkthrough: scope 'tasks' resolves to no task graph in specs/$spec; tasks.md is absent" >&2
      exit 1
    fi
    ;;
  decision:*)
    did=${scope#decision:}
    did=${did#D-}
    did=${did#d-}
    case $did in
      "" | *[!0-9]*)
        echo "spec-walkthrough: scope '$scope_safe' is not a decision id (expected decision:<id>); available decisions: $(decision_ids)" >&2
        exit 1
        ;;
    esac
    if [ ! -f "$bundle_dir/design.md" ]; then
      echo "spec-walkthrough: scope '$scope_safe' names a decision, but design.md is absent from specs/$spec" >&2
      exit 1
    fi
    if grep -qE "^### D-$did:" "$bundle_dir/design.md" 2>/dev/null; then
      scope_label="decision D-$did"
    else
      echo "spec-walkthrough: scope '$scope_safe' resolves to no decision in specs/$spec; available decisions: $(decision_ids)" >&2
      exit 1
    fi
    ;;
  *)
    echo "spec-walkthrough: unknown scope '$scope_safe'; valid scopes: whole, file:<name>, reqs:<group>, decisions, tasks, decision:<id>" >&2
    exit 1
    ;;
esac

# Load report (read-only). The rendering tasks consume this surface; for now it
# is the observable proof the bundle loaded, in any status, writing nothing.
if [ -z "$missing" ]; then
  printf "spec-walkthrough: loaded bundle '%s' (status: %s)\n" "$spec" "$status"
  printf '  files present: %s\n' "$present"
else
  printf "spec-walkthrough: loaded bundle '%s' (status: %s, partial)\n" "$spec" "$status"
  printf '  files present: %s\n' "$present"
  printf '  files missing: %s\n' "$missing"
fi
printf '  scope: %s\n' "$scope_label"
printf '  reveal: %s\n' "$reveal"
