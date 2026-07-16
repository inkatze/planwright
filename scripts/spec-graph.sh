#!/bin/sh
# spec-graph.sh — the dependency-graph and critical-path view for /spec-walkthrough.
#
# Task 7 of specs/spec-comprehension (D-4, D-5, D-6; REQ-C1.3, REQ-C1.6,
# REQ-E1.3): the view that turns the bundle's task graph into a drawn (inline
# SVG, never ASCII) diagram with the critical path and the parallelism visible.
# It reads the bundle model (Task 2, scripts/spec-model.sh) for the task nodes
# and dependency edges, computes a layout, and emits a tagged tab-separated
# record stream the assembly layer (Task 6, scripts/spec-assemble.sh) draws as
# inline SVG. Like the sibling views it is strictly read-only (REQ-A1.3): it
# writes nothing but its stdout stream; the artifact write stays the command
# scaffold's one sanctioned write.
#
# The critical path is REUSED, not recomputed (D-6): it is exactly what
# scripts/orchestrate-select.sh --critical-path emits — the effort-weighted
# longest-dependent chain — so the highlighted path cannot disagree with the
# orchestrator's own source of truth (REQ-C1.3).
#
# Layout: a self-contained built-in layered layout is the default and always
# works (column = longest dependency depth, so same-depth tasks share a column
# and parallelism shows). When Graphviz (`dot`) is present it is used for a
# richer layout via `dot -Tplain` — read-only, for node coordinates only;
# planwright always renders its own escaped, styled SVG, so the artifact is
# byte-for-byte self-contained and offline whether or not `dot` was present
# (D-5). A `dot` that is absent, exits non-zero, times out, or emits an
# unparseable layout degrades identically to the built-in path with an
# in-artifact note (REQ-E1.3): `dot` is never on a path that can fail the render.
# Only the numeric task ids are passed to `dot` (never bundle text), and every
# coordinate read back is validated numeric before use, so `dot` is never
# load-bearing and cannot inject anything into the diagram.
#
# Record vocabulary (tag in column 1, tab-separated):
#   GRAPHMETA  <width>  <height>  <layout:builtin|graphviz>  <node-w>  <node-h>
#   GRAPHNOTE  <text>                       (the layout / degradation note)
#   GRAPHCRIT  <space-joined critical-path ids>
#   GRAPHNODE  <id>  <x>  <y>  <crit:0|1>  <title verbatim>
#   GRAPHEDGE  <from-id>  <to-id>  <crit:0|1>    (from = dependency, to = dependent)
#
# Node titles are carried VERBATIM (D-2): HTML/SVG escaping is the assembly
# layer's job (REQ-E1.7), so the reveal seam stays lossless and escaping is not
# duplicated here.
#
# Usage: spec-graph.sh <spec-dir>
#
# Environment:
#   SPEC_WALKTHROUGH_DOT          the Graphviz binary used for the optional
#                                 layout enhancement (default: dot); point it at
#                                 a missing name to force the built-in layout. A
#                                 test/override seam, mirroring
#                                 SPEC_WALKTHROUGH_COMMIT in the assembler.
#   SPEC_WALKTHROUGH_DOT_TIMEOUT  seconds to allow `dot` before a watchdog kills
#                                 it and the layout degrades to built-in
#                                 (default: 5; D-5 / REQ-E1.3 "timeout").
#
# Read-only to the repository (REQ-A1.3): it writes nothing but its stdout
# stream. The optional bounded `dot` run uses two short-lived TMPDIR temp files
# (the DOT input and the layout output), never the tracked tree.
#
# Exit codes:
#   0  the record stream was emitted (a bundle with no task graph still emits a
#      GRAPHMETA + an empty-graph GRAPHNOTE — graceful degradation, REQ-A1.5).
#   2  usage or environment error: no argument, a missing sibling script, or an
#      absent/unreadable spec directory (fail closed, propagated from the model).
#
# Portable: /bin/sh + awk as shipped on macOS (bash 3.2, BSD userland) and Linux
# (the REQ-K1.5 envelope). No gawk-only constructs, no eval; input treated as
# data only.
set -eu

# Pin the C locale: range patterns must not vary by host locale collation.
LC_ALL=C
export LC_ALL
unset CDPATH

# The optional `dot` run uses two TMPDIR temp files; declare them up front so the
# EXIT trap can always reference them (set -u safe) and clean them up on an
# interrupt or error exit too, not only the normal path (the builder-guards.sh /
# spec-validate.sh house pattern). They stay empty unless the Graphviz probe runs.
gv_in=
gv_out=
trap 'rm -f "$gv_in" "$gv_out" 2>/dev/null || :' EXIT

spec_dir="${1:-}"
if [ -z "$spec_dir" ] || [ "$spec_dir" = "-" ]; then
  echo "usage: spec-graph.sh <spec-dir>" >&2
  exit 2
fi
while [ "$spec_dir" != "${spec_dir%/}" ]; do spec_dir=${spec_dir%/}; done

# Resolve the sibling scripts next to this one (the pipeline convention).
here=$(cd "$(dirname "$0")" && pwd)
model_sh="$here/spec-model.sh"
select_sh="$here/orchestrate-select.sh"
for s in "$model_sh" "$select_sh"; do
  if [ ! -x "$s" ]; then
    echo "spec-graph: cannot find an executable $(basename "$s") at $s" >&2
    exit 2
  fi
done

tab=$(printf '\t')

# The model (fail closed on an absent/unreadable spec directory, exit 2
# propagated; a partial bundle with no tasks degrades to an empty graph below).
model=$("$model_sh" "$spec_dir") || exit $?

# Critical path, reused from the orchestrator (D-6). A taskless/absent tasks.md
# — or, since invariant-tasks Task 5, a missing/unparseable Format-version:
# line (REQ-C1.8) — makes the selector exit 2; that is not fatal here (the
# bundle may legitimately have no task graph, and a version-less bundle refuses
# rather than guesses), so the path is simply empty and nothing is highlighted.
# The awk pipeline's exit status is awk's (0), so set -e is satisfied.
crit_path=$(
  "$select_sh" --critical-path "$spec_dir" 2>/dev/null \
    | awk 'NR>1{printf " "} {printf "%s", $0} END{print ""}'
)

# Node ids and dependency edges (dep<tab>dependent) for the optional dot probe.
# Edges are filtered to those whose BOTH endpoints have a TASK node — the same
# dangling-edge guard the GRAPHEDGE emission applies (REQ-A1.5). Otherwise a
# Dependencies line naming a not-yet-written or mistyped id would feed `dot` an
# edge to an undeclared node; `dot` would implicitly create a ghost node for it
# and distort the real nodes' coordinates. Edges are buffered and filtered in
# END so the guard is order-independent (a forward dependency reference is kept
# once every TASK record has been seen).
node_ids=$(printf '%s\n' "$model" | awk -F"$tab" '$1=="TASK"{print $2}')
edges=$(printf '%s\n' "$model" | awk -F"$tab" '
  $1 == "TASK" { seen[$2] = 1; next }
  $1 == "TASKDEP" { ne++; efrom[ne] = $3; eto[ne] = $2; next }
  END {
    for (i = 1; i <= ne; i++)
      if ((efrom[i] in seen) && (eto[i] in seen)) print efrom[i] "\t" eto[i]
  }
')

# Drawn node-box geometry in px — the single source of truth for both the SVG
# the assembler redraws and the box size we ask dot to reserve below. SCALE is
# the px-per-inch used to convert dot's inch coordinates back to px. Defined
# here as shell constants (and passed into the awk emitter via -v, never
# re-stated as awk literals) so the DOT input size, the awk layout, and the
# test all read one definition and cannot silently drift apart. Each constant
# sits alone on its own line so the test can extract it with a `^NAME=NN$` match.
NODEW=180
NODEH=44
COLGAP=54
ROWGAP=22
MARGIN=22
SCALE=72

# --- Optional Graphviz layout (degrades cleanly to built-in) ----------------
layout=builtin
note="Built-in layout (Graphviz not detected; install \`dot\` for a richer graph)."
gvcoords=
gvheight=
dot_bin=${SPEC_WALKTHROUGH_DOT:-dot}
gv_timeout=${SPEC_WALKTHROUGH_DOT_TIMEOUT:-5}
# The timeout is fed straight to the watchdog's `sleep`; a non-integer (or
# negative) value would make that `sleep` error out, and under `set -e` the
# watchdog subshell would then exit before its `kill` — defeating the bound and
# letting a hung `dot` stall the render (REQ-E1.3 "timeout"). Coerce anything
# that is not a plain non-negative integer back to the default.
case $gv_timeout in '' | *[!0-9]*) gv_timeout=5 ;; esac

# Validate a Graphviz `-Tplain` coordinate as a conventional non-negative decimal
# (digits, with at most one interior dot: no bare ".", no leading/trailing dot,
# no "1..2"). A `*[!0-9.]*` character-class guard alone passes those malformed
# forms, which awk/shell then coerce to 0 or a partial number; this keeps the
# "every coordinate read back is validated numeric" claim honest so untrusted
# `dot` output can never inject a misleading position.
is_decimal() {
  case $1 in
    '' | *[!0-9.]*) return 1 ;;
    *.*.* | .* | *.) return 1 ;;
  esac
  return 0
}

if [ -n "$node_ids" ] && command -v "$dot_bin" >/dev/null 2>&1; then
  # `dot` is present (command -v found it). If any step below rejects its layout
  # (non-zero exit, timeout, or unparseable output) we keep the built-in layout,
  # but the in-artifact note must not then claim Graphviz was "not detected" — it
  # was, it just did not return a usable layout. The success branch overwrites
  # this; every failure mode degrades identically (REQ-E1.3) while the note stays
  # accurate about which mode occurred.
  note="Built-in layout (Graphviz did not return a usable layout; using the built-in graph)."
  # Build a DOT graph from numeric ids only — no bundle text reaches dot, so no
  # title can inject DOT syntax.
  #
  # Declare the node size dot should reserve so its column spacing matches the
  # fixed-size boxes we actually draw downstream. Without this dot sizes each
  # node to its tiny numeric-id label (~0.75in) and packs the LR ranks closer
  # than NODEW, so adjacent columns overlap once each is redrawn NODEW wide.
  # The reserved size is DERIVED from NODEW/NODEH at SCALE (the single source of
  # truth above), rounded UP to the hundredth-inch so the reserved box is never
  # smaller than the drawn box: NODEW/SCALE = 180/72 = 2.5 exactly; NODEH/SCALE =
  # 44/72 ≈ 0.611 -> 0.62 (a bare 0.61 would reserve 43.92px < NODEH and re-pack
  # same-rank rows too tight). ranksep/nodesep add modest gutters.
  dot_dims=$(awk -v w="$NODEW" -v h="$NODEH" -v s="$SCALE" 'BEGIN {
    printf "%s %s", fmt(ceilh(w / s)), fmt(ceilh(h / s))
  }
  function ceilh(x,   n) { n = int(x * 100); if (x * 100 > n) n++; return n / 100 }
  function fmt(x,   t) { t = sprintf("%.2f", x); sub(/0+$/, "", t); sub(/\.$/, "", t); return t }')
  dot_w=${dot_dims%% *}
  dot_h=${dot_dims##* }
  dot_src=$(
    printf 'digraph G {\n  rankdir=LR;\n  graph [ranksep=0.55, nodesep=0.3];\n  node [shape=box, fixedsize=true, width=%s, height=%s];\n' "$dot_w" "$dot_h"
    printf '%s\n' "$node_ids" | while IFS= read -r nid; do
      [ -n "$nid" ] && printf '  "%s";\n' "$nid"
    done
    # Guard the empty case: with every edge filtered out (e.g. all dependencies
    # dangling), `printf '%s\n' ""` would emit a blank line whose `[ -n "$ef" ]`
    # short-circuits to a non-zero status, and under `set -e` that aborts this
    # `$(...)` subshell before the closing brace is printed.
    if [ -n "$edges" ]; then
      printf '%s\n' "$edges" | while IFS="$tab" read -r ef et; do
        [ -n "$ef" ] && printf '  "%s" -> "%s";\n' "$ef" "$et"
      done
    fi
    printf '}\n'
  )
  # Run dot under a wall-clock watchdog so a hung or pathologically slow
  # invocation degrades to the built-in layout instead of stalling the render
  # (D-5 / REQ-E1.3 "timeout"). dot reads the DOT source from a temp file (not a
  # pipe) so $! is unambiguously dot's pid for the watchdog to kill; both temps
  # live under TMPDIR, never the tracked tree, so the view stays repo-read-only.
  plain=
  # Explicit templates: a bare `mktemp` default template is not portable to BSD
  # mktemp (the house pattern, see scripts/builder-guards.sh).
  gv_in=$(mktemp "${TMPDIR:-/tmp}/spec-graph.XXXXXX" 2>/dev/null) || gv_in=
  gv_out=$(mktemp "${TMPDIR:-/tmp}/spec-graph.XXXXXX" 2>/dev/null) || gv_out=
  if [ -n "$gv_in" ] && [ -n "$gv_out" ]; then
    printf '%s\n' "$dot_src" >"$gv_in"
    "$dot_bin" -Tplain "$gv_in" >"$gv_out" 2>/dev/null &
    gv_pid=$!
    (
      sleep "$gv_timeout"
      kill "$gv_pid" 2>/dev/null
    ) >/dev/null 2>&1 &
    gv_watch=$!
    if wait "$gv_pid" 2>/dev/null; then
      plain=$(cat "$gv_out")
    fi
    kill "$gv_watch" 2>/dev/null || :
    wait "$gv_watch" 2>/dev/null || :
  fi
  # Prompt cleanup on the normal path (keeps the temps' lifetime to the probe);
  # the EXIT trap above is the backstop for an interrupt or error exit.
  rm -f "$gv_in" "$gv_out" 2>/dev/null || :
  # Accept the layout only if it carries the `graph <scale> <w> <h>` header and a
  # numeric x,y for every node id; any gap means degrade to built-in.
  if printf '%s\n' "$plain" | head -1 | grep -q '^graph '; then
    gvheight=$(printf '%s\n' "$plain" | awk '$1=="graph"{print $4; exit}')
    parsed=$(printf '%s\n' "$plain" | awk '$1=="node"{print $2, $3, $4}')
    ok=1
    coords=
    for nid in $node_ids; do
      cline=$(printf '%s\n' "$parsed" | awk -v i="$nid" '$1==i{print $2, $3; exit}')
      cx=${cline%% *}
      cy=${cline##* }
      is_decimal "$cx" || ok=0
      is_decimal "$cy" || ok=0
      [ "$ok" = 1 ] || break
      coords="$coords$nid $cx $cy;"
    done
    is_decimal "$gvheight" || ok=0
    if [ "$ok" = 1 ]; then
      layout=graphviz
      gvcoords=$coords
      note="Graphviz (\`dot\`) layout."
    fi
  fi
fi

# --- Emit the record stream -------------------------------------------------
printf '%s\n' "$model" | awk \
  -v crit="$crit_path" -v layout="$layout" -v gvcoords="$gvcoords" \
  -v gvheight="$gvheight" -v note="$note" \
  -v NODEW="$NODEW" -v NODEH="$NODEH" -v COLGAP="$COLGAP" \
  -v ROWGAP="$ROWGAP" -v MARGIN="$MARGIN" -v SCALE="$SCALE" '
  BEGIN {
    FS = "\t"; OFS = "\t"
    nnodes = 0; ne = 0
    ncp = split(crit, cp, " ")
    for (i = 1; i <= ncp; i++)
      if (cp[i] != "") critpos[cp[i]] = i
  }
  $1 == "TASK" {
    id = $2
    if (id in seen) next
    seen[id] = 1
    nnodes++
    idx[nnodes] = id
    title[id] = $4
    next
  }
  $1 == "TASKDEP" {
    # $2 (dependent) depends on $3 (dependency); the drawn edge runs dep -> task.
    ne++
    efrom[ne] = $3
    eto[ne] = $2
    deps[$2] = deps[$2] $3 " "
    next
  }
  # rankof(t): longest dependency depth (sources are rank 0). Memoized; the
  # pre-set 0 also guards a malformed cyclic graph from looping.
  function rankof(t,   best, n, a, i, r) {
    if (t in rmemo) return rmemo[t]
    rmemo[t] = 0
    best = 0
    n = split(deps[t], a, " ")
    for (i = 1; i <= n; i++) {
      if (a[i] == "" || !(a[i] in seen)) continue
      r = rankof(a[i]) + 1
      if (r > best) best = r
    }
    rmemo[t] = best
    return best
  }
  END {
    if (nnodes == 0) {
      print "GRAPHMETA", 0, 0, layout, NODEW, NODEH
      print "GRAPHNOTE", "This bundle has no task graph to draw."
      print "GRAPHCRIT", ""
      exit 0
    }
    if (layout == "graphviz") {
      # Inches (center, bottom-left origin) -> px top-left on a top-left-origin
      # canvas, normalized so the minimum corner sits at MARGIN.
      m = split(gvcoords, items, ";")
      minx = 1e18; miny = 1e18
      for (k = 1; k <= m; k++) {
        if (items[k] == "") continue
        split(items[k], f, " ")
        gid = f[1]
        cxp = f[2] * SCALE - NODEW / 2
        cyp = (gvheight - f[3]) * SCALE - NODEH / 2
        gx[gid] = cxp; gy[gid] = cyp
        if (cxp < minx) minx = cxp
        if (cyp < miny) miny = cyp
      }
      maxx = 0; maxy = 0
      for (i = 1; i <= nnodes; i++) {
        id = idx[i]
        nx[id] = int(gx[id] - minx + MARGIN + 0.5)
        ny[id] = int(gy[id] - miny + MARGIN + 0.5)
        if (nx[id] + NODEW > maxx) maxx = nx[id] + NODEW
        if (ny[id] + NODEH > maxy) maxy = ny[id] + NODEH
      }
      W = maxx + MARGIN; H = maxy + MARGIN
    } else {
      maxrank = 0; maxrows = 0
      for (i = 1; i <= nnodes; i++) {
        id = idx[i]
        r = rankof(id)
        rank[id] = r
        row[id] = rowcount[r]++
        if (r > maxrank) maxrank = r
        if (rowcount[r] > maxrows) maxrows = rowcount[r]
      }
      for (i = 1; i <= nnodes; i++) {
        id = idx[i]
        nx[id] = MARGIN + rank[id] * (NODEW + COLGAP)
        ny[id] = MARGIN + row[id] * (NODEH + ROWGAP)
      }
      W = MARGIN + (maxrank + 1) * (NODEW + COLGAP) - COLGAP + MARGIN
      H = MARGIN + maxrows * (NODEH + ROWGAP) - ROWGAP + MARGIN
    }
    print "GRAPHMETA", W, H, layout, NODEW, NODEH
    print "GRAPHNOTE", note
    cpline = ""
    for (i = 1; i <= ncp; i++)
      if (cp[i] != "") cpline = cpline (cpline == "" ? "" : " ") cp[i]
    print "GRAPHCRIT", cpline
    for (i = 1; i <= nnodes; i++) {
      id = idx[i]
      print "GRAPHNODE", id, nx[id], ny[id], (id in critpos ? 1 : 0), title[id]
    }
    for (j = 1; j <= ne; j++) {
      d = efrom[j]; t = eto[j]
      # Skip a dangling edge whose dependency (or, defensively, dependent) names
      # a task with no node — a Dependencies line pointing at a not-yet-written
      # or mistyped id in a Draft/partial bundle. The built-in rank layout
      # already ignores such a dep; emitting the edge anyway would make the
      # assembler draw a line to a node that does not exist (REQ-A1.5).
      if (!(d in seen) || !(t in seen)) continue
      ec = (d in critpos && t in critpos && critpos[t] == critpos[d] + 1) ? 1 : 0
      print "GRAPHEDGE", d, t, ec
    }
  }
'
