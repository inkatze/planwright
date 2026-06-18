#!/bin/sh
# spec-assemble.sh — the self-contained HTML assembly and styling layer for
# /spec-walkthrough.
#
# Task 6 of specs/spec-comprehension (D-3, D-4, D-7, D-8; REQ-C1.6, REQ-D1.2,
# REQ-D1.3, REQ-E1.1, REQ-E1.2, REQ-E1.4, REQ-E1.5, REQ-E1.6, REQ-E1.7): the
# layer that assembles the rendered views into one offline, dependency-free HTML
# artifact. It runs the one-pager view (Task 4, scripts/spec-onepager.sh), the
# decision-map view (Task 8, scripts/spec-decisionmap.sh; D-2, REQ-C1.4), the
# dependency-graph view (Task 7, scripts/spec-graph.sh; D-4, D-5, D-6, REQ-C1.3,
# REQ-C1.6, REQ-E1.3), and the teach-back view (Task 5, scripts/spec-teachback.sh)
# over a bundle and emits a single self-contained HTML document on stdout:
#
#   - the foregrounded read first (the one-pager, then the decision map, then the
#     dependency graph), the teach-back prompt after it (silent-read-first
#     ordering, REQ-D1.2);
#   - every piece of bundle content HTML/SVG-escaped so no rendered text can
#     inject executable or structural markup into the artifact, and so markup in
#     bundle text displays as its literal characters (REQ-E1.7, the security
#     core — escaping is this assembly layer's job, deliberately not the upstream
#     model/translate/view layers', which carry text verbatim so the reveal seam
#     stays lossless, D-2);
#   - an off-by-default reveal toggle that the inlined CSS hides identifiers
#     behind, surfaced only when the reader engages it (REQ-D1.3);
#   - original styling inlined for offline rendering, drawing on the design
#     language of the MIT-licensed Tailwind CSS and DaisyUI projects (their
#     utility/component conventions and color tokens) without bundling any of
#     their code, with that credit carried in the artifact (D-7, REQ-E1.6);
#   - a provenance stamp naming the bundle it rendered and the commit it was
#     generated from, so a reader can tell whether it is stale (D-8, REQ-E1.5).
#
# The document references no external network resource and needs nothing
# installed: it opens offline in any browser (D-4, REQ-E1.2). The whole-bundle
# artifact carries the one-pager, the decision map, the dependency graph, and
# the teach-back; a partial --scope selector (Task 9; REQ-B1.2) renders only the
# sections in its scope, and the framing adapts to the bundle's auto-detected
# status (REQ-B1.3).
#
# This script is strictly read-only (REQ-A1.3): it writes nothing but its stdout
# stream. Persisting the document to the gitignored .claude/walkthroughs/<spec>/
# location (REQ-E1.1) is the command scaffold's (scripts/spec-walkthrough.sh)
# one sanctioned write, layered on top of this stdout stream.
#
# Usage:
#   spec-assemble.sh [--scope <selector>] <spec-dir>   # emit the HTML artifact
#
# <selector> (REQ-B1.2) names which part to render: whole (default), file:<name>,
# reqs:<GROUP>, decisions, tasks, or decision:<id> (the decision plus its blast
# radius). The scaffold validates it; this layer re-classifies and fails closed.
#
# Environment:
#   SPEC_WALKTHROUGH_COMMIT  override the provenance commit (otherwise derived
#                            from the repo HEAD, falling back to "unknown"); set
#                            by the scaffold and used by tests for a stable stamp.
#
# Exit codes:
#   0  the HTML artifact was emitted.
#   2  usage or environment error: no argument, a malformed --scope selector, a
#      sibling view script could not be found, or the upstream chain failed
#      (e.g. an absent/unreadable spec directory — fail closed, propagated from
#      the model/view scripts).
#
# Portable: /bin/sh + awk as shipped on macOS (bash 3.2, BSD userland) and Linux
# (the REQ-K1.5 envelope). No gawk-only constructs, no eval; bundle content is
# treated as data only and escaped before it reaches the document.
set -eu

# Pin the C locale: the byte-wise escaping below relies on C-locale (byte-wise)
# classification, matching the upstream model/translate/view layers. Bytes >= 0x80
# (a multibyte ≤ threshold, an em dash) are passed through escaping untouched.
LC_ALL=C
export LC_ALL
unset CDPATH

usage() {
  echo "usage: spec-assemble.sh [--scope <selector>] <spec-dir>" >&2
  exit 2
}

# sanitize_echo <string> — strip control characters before echoing untrusted
# content (the spec-validate echo discipline, REQ-H1.3: a hostile value must not
# reach the terminal raw, where escape sequences could manipulate it), with a
# placeholder when nothing printable remains. spec-assemble.sh is callable
# directly, bypassing the scaffold's charset gate, so the selector is sanitized
# here too (matching the sibling spec-walkthrough.sh). Display only; the
# classification logic below still matches on the raw $scope.
sanitize_echo() {
  se=$(printf '%s' "$1" | tr -d '\000-\037\177')
  [ -n "$se" ] || se="(unprintable)"
  printf '%s' "$se"
}

# Parse the optional --scope selector (Task 9; REQ-B1.1, REQ-B1.2) and the
# positional spec directory. The whole-bundle default renders every view; a
# partial selector renders only the sections in its scope. The scaffold
# (spec-walkthrough.sh) already charset-validates the selector before it lands
# here; this layer re-classifies it (defense in depth) and fails closed on a
# malformed selector rather than degrading to a silent whole-bundle render.
scope=
spec_dir=
while [ $# -gt 0 ]; do
  case $1 in
    --scope)
      [ $# -ge 2 ] || usage
      scope=$2
      shift 2
      ;;
    - | -*)
      usage
      ;;
    *)
      [ -z "$spec_dir" ] || usage
      spec_dir=$1
      shift
      ;;
  esac
done
if [ -z "$spec_dir" ]; then
  usage
fi

# Classify the selector into a scope kind plus the section flags that decide
# which views render. Each view is on (1) or off (0) per scope; the read-first
# ordering (one-pager, decision map, graph, blast radius, verification, then the
# teach-back prompt) is preserved among whichever sections are on.
scope_label=
dec_label=
show_op=0
show_dm=0
show_gr=0
show_tb=0
show_blast=0
show_verify=0
# A control-character-stripped copy of the selector for the error messages below
# (echo discipline); the case still matches on the raw $scope.
scope_safe=$(sanitize_echo "$scope")
case ${scope:-whole} in
  whole | "")
    scope=whole
    scope_label="the whole bundle"
    show_op=1
    show_dm=1
    show_gr=1
    show_tb=1
    ;;
  file:*)
    fname=${scope#file:}
    fname=${fname%.md}
    case $fname in
      requirements)
        scope_label="the requirements file"
        show_op=1
        show_tb=1
        ;;
      design)
        scope_label="the design file"
        show_dm=1
        show_tb=1
        ;;
      tasks)
        scope_label="the tasks file"
        show_gr=1
        ;;
      test-spec)
        scope_label="the test-spec file"
        show_verify=1
        ;;
      *)
        echo "spec-assemble: scope '$scope_safe' names no source file" >&2
        exit 2
        ;;
    esac
    ;;
  reqs:*)
    rgroup=${scope#reqs:}
    case $rgroup in
      "" | *[!A-Z]*)
        echo "spec-assemble: scope '$scope_safe' is not a requirement group" >&2
        exit 2
        ;;
    esac
    scope_label="requirement group $rgroup"
    show_op=1
    show_tb=1
    ;;
  decisions)
    scope_label="the decision set"
    show_dm=1
    show_tb=1
    ;;
  tasks)
    scope_label="the task graph"
    show_gr=1
    ;;
  decision:*)
    dnum=${scope#decision:}
    dnum=${dnum#D-}
    dnum=${dnum#d-}
    case $dnum in
      "" | *[!0-9]*)
        echo "spec-assemble: scope '$scope_safe' is not a decision id" >&2
        exit 2
        ;;
    esac
    dec_label="D-$dnum"
    scope_label="decision $dec_label and its blast radius"
    show_dm=1
    show_blast=1
    ;;
  *)
    echo "spec-assemble: unknown scope '$scope_safe'" >&2
    exit 2
    ;;
esac

# Resolve the sibling view scripts next to this one (the sibling-script
# convention the whole pipeline follows).
here=$(cd "$(dirname "$0")" && pwd)
onepager_sh="$here/spec-onepager.sh"
decisionmap_sh="$here/spec-decisionmap.sh"
teachback_sh="$here/spec-teachback.sh"
graph_sh="$here/spec-graph.sh"
model_sh="$here/spec-model.sh"
scope_sh="$here/spec-scope.sh"
translate_sh="$here/spec-translate.sh"
for s in "$onepager_sh" "$decisionmap_sh" "$teachback_sh" "$graph_sh" \
  "$model_sh" "$scope_sh" "$translate_sh"; do
  if [ ! -x "$s" ]; then
    echo "spec-assemble: cannot find an executable $(basename "$s") at $s" >&2
    exit 2
  fi
done

tab=$(printf '\t')

# The bundle model, run only for the scopes that consume it. A partial scope
# feeds it through the scope filter below, and every non-whole scope reads its
# spec/status from the BUNDLE record here (a graph-only scope renders no one-pager,
# so it has no other source). The whole-bundle scope runs its views in <spec-dir>
# mode and reads spec/status from the one-pager pass-through BUNDLE record after
# the views run (the established pre-task path), so it needs no separate model
# parse — avoiding a redundant 1 + N model read in the common whole-bundle case.
# Captured with `|| exit $?` so an absent/unreadable spec dir fails closed (no
# portable pipefail in /bin/sh); for the whole scope that fail-closed comes from
# the view scripts, which run the same model in <spec-dir> mode.
model=
spec=
status=
if [ "$scope" != whole ]; then
  model=$("$model_sh" "$spec_dir") || exit $?
  spec=$(printf '%s\n' "$model" | awk -F"$tab" '$1=="BUNDLE"{print $2; exit}')
  status=$(printf '%s\n' "$model" | awk -F"$tab" '$1=="BUNDLE"{print $3; exit}')
fi

# The view record streams. The whole-bundle scope runs each view in <spec-dir>
# mode (the established path, byte-identical to before this task). A partial
# scope filters the model through scripts/spec-scope.sh, translates the scoped
# substream, and feeds the text views that scoped translate stream on stdin (the
# composable pipe) so each renders only its scope (REQ-B1.2). The graph reuses
# the orchestrator's critical-path computation, which is bound to the on-disk
# bundle, so it always renders the whole graph — and is only shown for the
# scopes whose scope *is* the whole task graph (whole, tasks, file:tasks).
onepager_stream=
decisionmap_stream=
teachback_stream=
graph_stream=
scoped_translate=
if [ "$scope" = whole ]; then
  [ "$show_op" -eq 1 ] && onepager_stream=$("$onepager_sh" "$spec_dir")
  [ "$show_dm" -eq 1 ] && decisionmap_stream=$("$decisionmap_sh" "$spec_dir")
  [ "$show_tb" -eq 1 ] && teachback_stream=$("$teachback_sh" "$spec_dir")
elif [ "$show_op" -eq 1 ] || [ "$show_dm" -eq 1 ] || [ "$show_tb" -eq 1 ] \
  || [ "$show_blast" -eq 1 ] || [ "$show_verify" -eq 1 ]; then
  # Filter then translate once; the text views share the scoped translate stream.
  # Only run the scope + translate chain when a view actually consumes it: a
  # graph-only scope (tasks, file:tasks) renders from the on-disk bundle below
  # and needs neither, so it must not do the work nor inherit a failure from a
  # stream it never reads (the blast and verification views at the awk step below
  # also read scoped_translate, hence their flags here).
  # Capture the filter and the translate as separate command substitutions so a
  # mid-pipeline failure fails closed: a single `model | scope | translate`
  # substitution yields only translate's exit status (/bin/sh has no portable
  # pipefail), so a failing scope filter would be masked by a successful
  # translate of its empty output, and the assembler would emit a silently empty
  # document at exit 0. Splitting the captures with `|| exit $?` restores the
  # file's fail-closed discipline (matching the model and graph captures above).
  scoped_model=$(printf '%s\n' "$model" | "$scope_sh" --scope "$scope") || exit $?
  scoped_translate=$(printf '%s\n' "$scoped_model" | "$translate_sh") || exit $?
  [ "$show_op" -eq 1 ] && onepager_stream=$(printf '%s\n' "$scoped_translate" | "$onepager_sh")
  [ "$show_dm" -eq 1 ] && decisionmap_stream=$(printf '%s\n' "$scoped_translate" | "$decisionmap_sh")
  [ "$show_tb" -eq 1 ] && teachback_stream=$(printf '%s\n' "$scoped_translate" | "$teachback_sh")
fi
if [ "$show_gr" -eq 1 ]; then
  graph_stream=$("$graph_sh" "$spec_dir") || exit $?
fi

# The whole-bundle scope reads spec/status from the one-pager's pass-through
# BUNDLE record (the pre-task path), avoiding the separate model parse above. The
# fallbacks then apply to every scope: an empty spec degrades to the directory
# name, an empty status to "(undeclared)".
if [ "$scope" = whole ]; then
  spec=$(printf '%s\n' "$onepager_stream" | awk -F"$tab" '$1=="BUNDLE"{print $2; exit}')
  status=$(printf '%s\n' "$onepager_stream" | awk -F"$tab" '$1=="BUNDLE"{print $3; exit}')
fi
if [ -z "$spec" ]; then
  spec=$(basename "$spec_dir")
fi
[ -n "$status" ] || status="(undeclared)"

# Provenance commit: env override (a stable stamp for the scaffold and tests),
# else the repo HEAD, else "unknown". git is read-only here.
commit=${SPEC_WALKTHROUGH_COMMIT:-}
if [ -z "$commit" ]; then
  commit=$(git -C "$spec_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)
fi

# esc_val <string> — HTML-escape a single-line shell value (spec, status,
# commit) for safe interpolation into the document head and provenance stamp.
# The ampersand is escaped first so the entities it introduces are not
# re-escaped. \047 is the apostrophe (kept out of the single-quoted awk source).
esc_val() {
  printf '%s' "$1" | awk '
    {
      gsub(/&/, "\\&amp;")
      gsub(/</, "\\&lt;")
      gsub(/>/, "\\&gt;")
      gsub(/"/, "\\&quot;")
      gsub(/\047/, "\\&#39;")
      printf "%s", $0
    }'
}

spec_e=$(esc_val "$spec")
status_e=$(esc_val "$status")
commit_e=$(esc_val "$commit")

# The one-pager section fragment. The same esc() guards every bundle field; the
# plain rendering is default-visible, the back-pointer and verbatim source live
# in reveal-only (.rv) elements the CSS hides until the toggle is engaged
# (REQ-D1.3). Killer items carry a visible badge (the foregrounding, REQ-C1.2).
# shellcheck disable=SC2016 # $1..$7/$0 are awk fields, not shell expansions
onepager_prog='
  function esc(s) {
    gsub(/&/, "\\&amp;", s)
    gsub(/</, "\\&lt;", s)
    gsub(/>/, "\\&gt;", s)
    gsub(/"/, "\\&quot;", s)
    gsub(/\047/, "\\&#39;", s)
    return s
  }
  BEGIN {
    FS = "\t"
    print "<section data-section=\"onepager\" class=\"card section\">"
    print "<h2 class=\"section-title\">At a glance</h2>"
    open = 0; haveframe = 0
  }
  $1 == "ONEPAGERFRAME" {
    printf "<p class=\"frame\">Showing %d of %d load-bearing claims.</p>\n", $7, $8
    haveframe = 1
    next
  }
  $1 == "ONEPAGER" {
    if (!open) { print "<ol class=\"claims\">"; open = 1 }
    cls = ($3 == "killer") ? "claim claim-killer" : "claim claim-routine"
    printf "<li class=\"%s\">", cls
    if ($3 == "killer") printf "<span class=\"badge badge-killer\">key</span> "
    printf "<span class=\"plain\">%s</span>", esc($6)
    printf "<span class=\"rv ref\"> [%s]</span>", esc($4)
    printf "<span class=\"rv source\"> &mdash; %s</span>", esc($7)
    print "</li>"
    next
  }
  END {
    if (open) print "</ol>"
    else if (!haveframe) print "<p class=\"frame empty\">No live claims to surface.</p>"
    print "</section>"
  }
'

# The decision-map section fragment (Task 8, REQ-C1.4). Each decision renders in
# the ADR four-beat shape — Context, Decision, Alternative rejected, Consequence —
# as a definition list (label/body pairs), the rejected alternative and its cost
# surfaced alongside the chosen path. The plain rendering is default-visible; the
# back-pointer and verbatim source live in reveal-only (.rv) elements (REQ-D1.3).
# A beat the bundle does not state renders a muted "(not stated)" placeholder so
# the four-beat shape stays visible rather than collapsing (graceful degradation,
# REQ-A1.5). The same esc() guards every bundle field (REQ-E1.7).
# shellcheck disable=SC2016 # $1..$6/$0 are awk fields, not shell expansions
decisionmap_prog='
  function esc(s) {
    gsub(/&/, "\\&amp;", s)
    gsub(/</, "\\&lt;", s)
    gsub(/>/, "\\&gt;", s)
    gsub(/"/, "\\&quot;", s)
    gsub(/\047/, "\\&#39;", s)
    return s
  }
  function beatlabel(b) {
    if (b == "context")     return "Context"
    if (b == "decision")    return "Decision"
    if (b == "alternative") return "Alternative rejected"
    if (b == "consequence") return "Consequence"
    return b
  }
  BEGIN {
    FS = "\t"
    print "<section data-section=\"decisionmap\" class=\"card section\">"
    print "<h2 class=\"section-title\">Decisions</h2>"
    curref = ""; haveframe = 0; open = 0
  }
  $1 == "DECMAPFRAME" {
    # A bundle with no decisions (e.g. a partial bundle missing the design file)
    # falls through to the END empty-state message rather than a "0 decisions,
    # each shown as ..." frame, matching the one-pager/teach-back empty-state
    # convention and the graceful-degradation posture (REQ-A1.5).
    if ($4 + 0 == 0) next
    printf "<p class=\"frame\">%d decisions, each shown as context, decision, alternative rejected, and consequence.</p>\n", $4
    haveframe = 1
    next
  }
  $1 == "DECMAP" {
    if (!open) { print "<ol class=\"decisions\">"; open = 1 }
    # A new decision id opens a fresh decision item (closing the previous one).
    if ($3 != curref) {
      if (curref != "") { print "</dl>"; print "</li>" }
      curref = $3
      print "<li class=\"decision\">"
      printf "<span class=\"rv ref\">[%s]</span>\n", esc($3)
      print "<dl class=\"beats\">"
    }
    printf "<dt class=\"beat-label\">%s</dt>\n", esc(beatlabel($4))
    printf "<dd class=\"beat beat-%s\">", esc($4)
    if ($5 == "" && $6 == "") {
      printf "<span class=\"beat-empty\">(not stated)</span>"
    } else {
      printf "<span class=\"plain\">%s</span>", esc($5)
      printf "<span class=\"rv source\"> &mdash; %s</span>", esc($6)
    }
    print "</dd>"
    next
  }
  END {
    if (open) {
      if (curref != "") { print "</dl>"; print "</li>" }
      print "</ol>"
    } else if (!haveframe) {
      print "<p class=\"frame empty\">No decisions to surface.</p>"
    }
    print "</section>"
  }
'

# The teach-back section fragment. Buffered then emitted section by section
# (REQ-C1.5): the neutral agree/disagree/unsure response model becomes one radio
# group per claim, with no column for a verdict or score — the independence
# firewall is structural (REQ-D1.1). The same esc() guards every field.
# shellcheck disable=SC2016 # $1..$6/$0 are awk fields, not shell expansions
teachback_prog='
  function esc(s) {
    gsub(/&/, "\\&amp;", s)
    gsub(/</, "\\&lt;", s)
    gsub(/>/, "\\&gt;", s)
    gsub(/"/, "\\&quot;", s)
    gsub(/\047/, "\\&#39;", s)
    return s
  }
  function cap(s) { return toupper(substr(s, 1, 1)) substr(s, 2) }
  BEGIN { FS = "\t"; nresp = 0; nsec = 0; ncl = 0 }
  $1 == "RESPONSE" { resp[++nresp] = $2; next }
  $1 == "SECTION"  { secorder[++nsec] = $2; seclabel[$2] = $4; next }
  $1 == "CLAIM"    { ncl++; cref[ncl] = $2; csec[ncl] = $3; cplain[ncl] = $5; csrc[ncl] = $6; next }
  END {
    print "<section data-section=\"teachback\" class=\"card section\">"
    print "<h2 class=\"section-title\">Teach-back</h2>"
    print "<p class=\"tb-intro\">Restate each claim in your own words, then mark your understanding. This records your own read &mdash; it supplies no answer and no score.</p>"
    if (ncl == 0) { print "<p class=\"tb-empty\">No claims to teach back.</p>"; print "</section>"; exit }
    cc = 0
    for (o = 1; o <= nsec; o++) {
      sid = secorder[o]
      print "<section class=\"tb-group\">"
      printf "<h3 class=\"tb-group-title\">%s</h3>\n", esc(seclabel[sid])
      print "<ol class=\"tb-claims\">"
      for (i = 1; i <= ncl; i++) {
        if (csec[i] != sid) continue
        cc++
        print "<li class=\"tb-claim\">"
        printf "<p class=\"plain\">%s</p>", esc(cplain[i])
        printf "<span class=\"rv ref\">[%s]</span>", esc(cref[i])
        printf "<span class=\"rv source\">%s</span>\n", esc(csrc[i])
        print "<fieldset class=\"responses\">"
        print "<legend class=\"sr-only\">Your understanding</legend>"
        for (r = 1; r <= nresp; r++) {
          # Escape the label text as well as the value attribute: this assembly
          # layer escapes ALL rendered content (REQ-E1.7), not only the fields it
          # assumes are untrusted. The response options are the hardcoded
          # agree/disagree/unsure upstream today, but the escaping contract here
          # must not depend on that, so the cap() output is escaped before output.
          printf "<label class=\"resp\"><input type=\"radio\" name=\"tb-claim-%d\" value=\"%s\"> %s</label>\n", cc, esc(resp[r]), esc(cap(resp[r]))
        }
        print "</fieldset>"
        print "</li>"
      }
      print "</ol>"
      print "</section>"
    }
    print "</section>"
  }
'

# The dependency-graph section fragment (Task 7; D-4, D-5, D-6; REQ-C1.3,
# REQ-C1.6, REQ-E1.3). The graph view (scripts/spec-graph.sh) emits a record
# stream of nodes (with computed coordinates), edges, the reused critical path,
# and a layout note; this draws it as an inline SVG (never ASCII) adjacent to its
# explaining text. Bundle-derived labels are escaped here (the same esc(), now in
# SVG text context — the dedicated SVG pass the Task 6 scoping note anticipated);
# coordinates are numeric (the view validated them) and coerced with +0. The
# critical path and its edges carry a -critical class for the highlight; the
# back-pointer id sits in a reveal-only (.rv) SVG element, hidden by default
# (REQ-D1.3). No xmlns is emitted: the HTML5 parser places inline SVG in the SVG
# namespace automatically, so an explicit xmlns identifier is redundant here.
# shellcheck disable=SC2016 # $1..$6/$0 are awk fields, not shell expansions
graph_prog='
  function esc(s) {
    gsub(/&/, "\\&amp;", s)
    gsub(/</, "\\&lt;", s)
    gsub(/>/, "\\&gt;", s)
    gsub(/"/, "\\&quot;", s)
    gsub(/\047/, "\\&#39;", s)
    return s
  }
  function trunc(s,   t) {
    if (length(s) <= MAXLABEL) return s
    # Reserve three characters for the ellipsis so the rendered label (content +
    # "...") never exceeds MAXLABEL.
    t = substr(s, 1, MAXLABEL - 3)
    sub(/ +$/, "", t)
    return t "..."
  }
  BEGIN { FS = "\t"; nn = 0; nedg = 0; MAXLABEL = 26; W = 0; H = 0; NODEW = 180; NODEH = 44; layout = "builtin"; note = "" }
  $1 == "GRAPHMETA" { W = $2 + 0; H = $3 + 0; layout = $4; NODEW = $5 + 0; NODEH = $6 + 0; next }
  $1 == "GRAPHNOTE" { note = $2; next }
  $1 == "GRAPHCRIT" { next }
  $1 == "GRAPHNODE" {
    nn++
    gid[nn] = $2; gx[nn] = $3 + 0; gy[nn] = $4 + 0; gc[nn] = ($5 == "1"); glab[nn] = $6
    ix[$2] = $3 + 0; iy[$2] = $4 + 0
    next
  }
  $1 == "GRAPHEDGE" {
    nedg++
    ef[nedg] = $2; et[nedg] = $3; ec[nedg] = ($4 == "1")
    next
  }
  END {
    print "<section data-section=\"graph\" class=\"card section\">"
    print "<h2 class=\"section-title\">How the work fits together</h2>"
    if (nn == 0) {
      # The empty-graph GRAPHNOTE carries this same sentence, so it is the single
      # source for the message and is not also echoed as a graph-note (printing
      # both rendered the identical line twice). The graph-intro prose is emitted
      # only below, once we know there is at least one node: it describes the
      # arrows, critical path, and parallel columns of a drawn diagram, so
      # printing it here would explain a diagram that is never rendered.
      print "<p class=\"graph-empty\">" esc(note) "</p>"
      print "</section>"
      exit
    }
    print "<p class=\"graph-intro\">Each box is a piece of work. An arrow runs from a piece to the work that depends on it, so the diagram flows left to right from the earliest work to the last. The highlighted chain is the longest path through the plan &mdash; the run of work that paces the whole effort. Boxes sharing a column have no dependency between them and can move ahead in parallel.</p>"
    print "<svg class=\"graph-svg\" viewBox=\"0 0 " W " " H "\" role=\"img\" aria-label=\"Task dependency graph; the highlighted chain is the critical path\">"
    print "<defs>"
    print "<marker id=\"gv-arrow\" markerWidth=\"9\" markerHeight=\"9\" refX=\"8\" refY=\"3\" orient=\"auto\"><path d=\"M0,0 L7,3 L0,6 Z\"/></marker>"
    print "<marker id=\"gv-arrow-crit\" markerWidth=\"9\" markerHeight=\"9\" refX=\"8\" refY=\"3\" orient=\"auto\"><path d=\"M0,0 L7,3 L0,6 Z\"/></marker>"
    print "</defs>"
    for (j = 1; j <= nedg; j++) {
      x1 = ix[ef[j]] + NODEW; y1 = iy[ef[j]] + NODEH / 2
      x2 = ix[et[j]];         y2 = iy[et[j]] + NODEH / 2
      cls = ec[j] ? "graph-edge graph-edge-critical" : "graph-edge"
      mk = ec[j] ? "gv-arrow-crit" : "gv-arrow"
      printf "<line class=\"%s\" x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\" marker-end=\"url(#%s)\"/>\n", cls, x1, y1, x2, y2, mk
    }
    for (i = 1; i <= nn; i++) {
      ncls = gc[i] ? "graph-node graph-node-critical" : "graph-node"
      print "<g class=\"" ncls "\">"
      printf "<rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" rx=\"8\"/>\n", gx[i], gy[i], NODEW, NODEH
      printf "<text class=\"graph-label\" x=\"%d\" y=\"%d\">%s</text>\n", gx[i] + 12, gy[i] + NODEH / 2 + 1, esc(trunc(glab[i]))
      printf "<text class=\"rv graph-node-id\" x=\"%d\" y=\"%d\" text-anchor=\"end\">#%s</text>\n", gx[i] + NODEW - 8, gy[i] + NODEH - 8, esc(gid[i])
      printf "<title>%s</title>\n", esc(glab[i])
      print "</g>"
    }
    print "</svg>"
    print "<p class=\"graph-note\">" esc(note) "</p>"
    print "</section>"
  }
'

# The blast-radius section fragment (Task 9; REQ-B1.2). For a single-decision
# scope (decision:<id>) the scope filter keeps the selected decision plus the
# requirements and tasks that cite it — its blast radius, what the decision
# affects. The decision itself renders in the decision map above; this section
# lists, in plain language, the affected requirements and tasks read from the
# scoped translate stream (TEXT requirement and task-title records). The
# identifiers stay reveal-only (REQ-D1.3); the same esc() guards every field
# (REQ-E1.7). An empty radius (nothing cites the decision) renders a clear note
# rather than an empty list (REQ-A1.5).
# shellcheck disable=SC2016 # $1..$5/$0 are awk fields, not shell expansions
blast_prog='
  function esc(s) {
    gsub(/&/, "\\&amp;", s)
    gsub(/</, "\\&lt;", s)
    gsub(/>/, "\\&gt;", s)
    gsub(/"/, "\\&quot;", s)
    gsub(/\047/, "\\&#39;", s)
    return s
  }
  BEGIN { FS = "\t"; nr = 0; nt = 0 }
  $1 == "TEXT" && $3 == "requirement" { nr++; rref[nr] = $2; rplain[nr] = $4; next }
  $1 == "TEXT" && $3 == "task-title"  { nt++; tref[nt] = $2; tplain[nt] = $4; next }
  END {
    print "<section data-section=\"blastradius\" class=\"card section\">"
    print "<h2 class=\"section-title\">What this decision affects</h2>"
    if (nr == 0 && nt == 0) {
      print "<p class=\"frame empty\">Nothing else in the bundle points back to this decision.</p>"
      print "</section>"
      exit
    }
    print "<p class=\"frame\">The parts of the bundle that rest on this decision &mdash; change it and these are what feel it.</p>"
    if (nr > 0) {
      print "<h3 class=\"blast-group-title\">Requirements</h3>"
      print "<ol class=\"claims\">"
      for (i = 1; i <= nr; i++) {
        print "<li class=\"claim claim-routine\">"
        printf "<span class=\"plain\">%s</span>", esc(rplain[i])
        printf "<span class=\"rv ref\"> [%s]</span>", esc(rref[i])
        print "</li>"
      }
      print "</ol>"
    }
    if (nt > 0) {
      print "<h3 class=\"blast-group-title\">Tasks</h3>"
      print "<ol class=\"claims\">"
      for (i = 1; i <= nt; i++) {
        # The task back-pointer ref is "task-<id>"; strip the prefix so the
        # reveal shows the bundle-facing task id (#<id>), matching the graph.
        tid = tref[i]; sub(/^task-/, "", tid)
        print "<li class=\"claim claim-routine\">"
        printf "<span class=\"plain\">%s</span>", esc(tplain[i])
        printf "<span class=\"rv ref\"> [#%s]</span>", esc(tid)
        print "</li>"
      }
      print "</ol>"
    }
    print "</section>"
  }
'

# The verification section fragment (Task 9; REQ-B1.2, file:test-spec scope).
# The test-spec file pins requirements to verification paths; this view lists,
# in plain language, the requirements that carry an automated check (the TEST
# records joined to the kept requirement TEXT). Identifiers stay reveal-only;
# the same esc() guards every field. No tested requirement renders a clear note.
# shellcheck disable=SC2016 # $1..$5/$0 are awk fields, not shell expansions
verify_prog='
  function esc(s) {
    gsub(/&/, "\\&amp;", s)
    gsub(/</, "\\&lt;", s)
    gsub(/>/, "\\&gt;", s)
    gsub(/"/, "\\&quot;", s)
    gsub(/\047/, "\\&#39;", s)
    return s
  }
  BEGIN { FS = "\t" }
  $1 == "TEST" { tested[$2] = 1; next }
  $1 == "TEXT" && $3 == "requirement" { plain[$2] = $4; ord[++norder] = $2; next }
  END {
    print "<section data-section=\"verification\" class=\"card section\">"
    print "<h2 class=\"section-title\">What is checked</h2>"
    n = 0
    for (i = 1; i <= norder; i++) if (ord[i] in tested) n++
    if (n == 0) {
      print "<p class=\"frame empty\">No requirement carries an automated check.</p>"
      print "</section>"
      exit
    }
    printf "<p class=\"frame\">%d requirement%s carr%s an automated check.</p>\n", n, (n == 1 ? "" : "s"), (n == 1 ? "ies" : "y")
    print "<ol class=\"claims\">"
    for (i = 1; i <= norder; i++) {
      ref = ord[i]
      if (!(ref in tested)) continue
      print "<li class=\"claim claim-routine\">"
      printf "<span class=\"plain\">%s</span>", esc(plain[ref])
      printf "<span class=\"rv ref\"> [%s]</span>", esc(ref)
      print "</li>"
    }
    print "</ol>"
    print "</section>"
  }
'

onepager_html=
decisionmap_html=
teachback_html=
graph_html=
blast_html=
verify_html=
[ "$show_op" -eq 1 ] && onepager_html=$(printf '%s\n' "$onepager_stream" | awk "$onepager_prog")
[ "$show_dm" -eq 1 ] && decisionmap_html=$(printf '%s\n' "$decisionmap_stream" | awk "$decisionmap_prog")
[ "$show_tb" -eq 1 ] && teachback_html=$(printf '%s\n' "$teachback_stream" | awk "$teachback_prog")
[ "$show_gr" -eq 1 ] && graph_html=$(printf '%s\n' "$graph_stream" | awk "$graph_prog")
[ "$show_blast" -eq 1 ] && blast_html=$(printf '%s\n' "$scoped_translate" | awk "$blast_prog")
[ "$show_verify" -eq 1 ] && verify_html=$(printf '%s\n' "$scoped_translate" | awk "$verify_prog")

# The inlined stylesheet (D-7, REQ-E1.6): original CSS authored at ship time,
# drawing on the design language of Tailwind CSS and DaisyUI (their utility /
# component conventions and color tokens) without bundling any of their code, so
# it inlines cleanly and the artifact stays offline and self-contained (no
# external stylesheet, no web font, no network resource). The
# default view hides the reveal-only (.rv) identifier elements; the off-by-default
# #reveal-toggle checkbox reveals them with a pure-CSS sibling rule (no script —
# the artifact ships no executable JavaScript). Quoted heredoc: static content,
# no shell expansion.
css=$(
  cat <<'CSS'
/*
 * Original CSS for planwright, inlined for offline self-containment. It draws on
 * the design language of Tailwind CSS and DaisyUI (both MIT-licensed): their
 * utility/component conventions and color tokens. It bundles none of their code;
 * the credit is carried in the artifact footer.
 */
:root {
  --bg: #f8fafc; --surface: #ffffff; --ink: #1e293b; --muted: #64748b;
  --line: #e2e8f0; --accent: #4f46e5; --accent-ink: #ffffff; --key: #b45309;
  --key-bg: #fef3c7; --radius: 0.75rem;
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--bg); color: var(--ink);
  font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
  line-height: 1.6; padding: 2rem 1rem;
}
.container { max-width: 56rem; margin: 0 auto; display: flex; flex-direction: column; gap: 1.5rem; }
.card {
  background: var(--surface); border: 1px solid var(--line);
  border-radius: var(--radius); padding: 1.5rem 1.75rem;
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04);
}
.hero-title { margin: 0 0 0.25rem; font-size: 1.6rem; font-weight: 700; }
.provenance { margin: 0.25rem 0 0.75rem; color: var(--muted); font-size: 0.9rem; }
.prov-spec, .prov-commit { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
.read-hint { margin: 0.75rem 0 0; color: var(--muted); font-size: 0.9rem; font-style: italic; }
/* Stage-aware framing (REQ-B1.3): a status-adapted orientation line; the scope
 * label names what slice is shown so a partial render is never mistaken for the
 * whole bundle. */
.stage-framing { margin: 0.75rem 0 0; font-size: 0.95rem; }
.scope-label { margin: 0.35rem 0 0; color: var(--muted); font-size: 0.85rem; }
.blast-group-title { font-size: 1rem; font-weight: 700; margin: 1rem 0 0.5rem; }
.section-title { margin: 0 0 0.75rem; font-size: 1.25rem; font-weight: 700; }
.frame { color: var(--muted); font-size: 0.9rem; margin: 0 0 1rem; }
.claims, .tb-claims { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 0.75rem; }
.claim { padding: 0.85rem 1rem; border: 1px solid var(--line); border-radius: 0.5rem; background: #fcfcfd; }
.claim-killer { border-color: var(--key); background: var(--key-bg); }
.badge {
  display: inline-block; font-size: 0.7rem; font-weight: 700; text-transform: uppercase;
  letter-spacing: 0.04em; padding: 0.1rem 0.5rem; border-radius: 999px; margin-right: 0.4rem;
}
.badge-killer { background: var(--key); color: var(--accent-ink); }
.plain { display: block; }
/* The decision map: each decision is a card-like list item holding a four-beat
 * definition list (Context, Decision, Alternative rejected, Consequence). */
.decisions { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 0.75rem; }
.decision { padding: 0.85rem 1rem; border: 1px solid var(--line); border-radius: 0.5rem; background: #fcfcfd; }
.beats { margin: 0; }
.beat-label {
  font-size: 0.72rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em;
  color: var(--accent); margin-top: 0.6rem;
}
.beat-label:first-child { margin-top: 0; }
.beat { margin: 0.15rem 0 0; }
.beat-empty { color: var(--muted); font-style: italic; }
.tb-group { margin-top: 1.25rem; }
.tb-group-title { font-size: 1rem; font-weight: 700; margin: 0 0 0.5rem; }
.tb-claim { padding: 0.85rem 1rem; border: 1px solid var(--line); border-radius: 0.5rem; background: #fcfcfd; }
.responses { border: 0; margin: 0.5rem 0 0; padding: 0; display: flex; gap: 1rem; flex-wrap: wrap; }
.resp { font-size: 0.9rem; color: var(--muted); }
/* The reveal control: a visually-hidden checkbox driven by the labelled button. */
.reveal-checkbox { position: absolute; width: 1px; height: 1px; opacity: 0; pointer-events: none; }
.reveal-label {
  display: inline-block; margin-top: 0.25rem; cursor: pointer;
  background: var(--accent); color: var(--accent-ink); border-radius: 0.5rem;
  padding: 0.4rem 0.9rem; font-size: 0.85rem; font-weight: 600; user-select: none;
}
/* Identifiers and verbatim source are reveal-only: hidden by default (REQ-D1.3). */
.rv { display: none; }
.ref { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--accent); }
.source { color: var(--muted); }
/* Engaging the toggle reveals every .rv element inside the page. Pure CSS: the
 * checkbox precedes the container, so the general-sibling combinator reaches it. */
#reveal-toggle:checked ~ .container .rv { display: inline; }
#reveal-toggle:checked ~ .container .reveal-label { background: var(--muted); }
.foot { color: var(--muted); font-size: 0.8rem; }
.license { margin: 0 0 0.5rem; }
.license-text { margin: 0; white-space: normal; }
.sr-only {
  position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
  overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0;
}
/* The dependency-graph view (Task 7). The diagram is a drawn inline SVG (never
 * ASCII); the critical path and its arrows are highlighted in the key color, the
 * same accent the one-pager uses for load-bearing items. The back-pointer id is
 * a reveal-only (.rv) element, hidden until the toggle is engaged. */
.graph-intro { margin: 0 0 0.75rem; }
.graph-svg { display: block; max-width: 100%; height: auto; margin: 0.25rem 0 0.5rem; }
.graph-note { margin: 0.25rem 0 0; color: var(--muted); font-size: 0.85rem; font-style: italic; }
.graph-empty { margin: 0.25rem 0; color: var(--muted); }
.graph-node rect { fill: #fcfcfd; stroke: var(--line); stroke-width: 1.5; }
.graph-node-critical rect { fill: var(--key-bg); stroke: var(--key); stroke-width: 2.5; }
.graph-label { font-size: 13px; fill: var(--ink); dominant-baseline: middle;
  font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif; }
.graph-node-id { font-size: 10px; fill: var(--muted);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
.graph-edge { stroke: var(--muted); stroke-width: 1.5; fill: none; }
.graph-edge-critical { stroke: var(--key); stroke-width: 2.5; fill: none; }
#gv-arrow path { fill: var(--muted); }
#gv-arrow-crit path { fill: var(--key); }
CSS
)

# Stage-aware framing (Task 9; D-11, REQ-B1.3). The framing adapts to the
# bundle's auto-detected status — the reader never specifies it. A pre-sign-off
# cold read for Draft, orientation plus progress for Active, onboarding or
# archaeology for Done and the terminal statuses. The text is plain and
# audience-neutral (REQ-C1.1): no internal vocabulary, no verdict (the
# independence firewall, REQ-D1.1). data-stage carries the detected status so
# the auto-detection is observable.
case $status in
  Draft)
    stage_text="This is still a draft and has not been signed off. Read it as a proposal and judge it for yourself before it is approved."
    ;;
  Active)
    stage_text="This is approved and the work is underway. Use it to get oriented and to see where things stand."
    ;;
  Done)
    stage_text="This work is finished. Use it to get onboarded, or to trace why the work was shaped the way it was."
    ;;
  Retired)
    stage_text="This work was retired without a replacement. Read it as a record of what was once proposed."
    ;;
  Superseded)
    stage_text="This work was replaced by a newer version. Read it as a record; the current version lives elsewhere."
    ;;
  *)
    stage_text="Read the whole walkthrough and judge the work for yourself."
    ;;
esac
stage_text_e=$(esc_val "$stage_text")
scope_e=$(esc_val "$scope")
scope_label_e=$(esc_val "$scope_label")

# Emit the document. Each dynamic value is passed as a printf %s argument (never
# as a format string) so bundle-derived content is never interpreted; the head
# values are pre-escaped, and the body fragments were escaped in awk. The styling
# credit is plain text (no URL) so the artifact references no network resource.
# Only the sections in scope are emitted, in read-first order (one-pager,
# decision map, graph, blast radius, verification), with the teach-back prompt
# last (silent-read-first, REQ-D1.2).
{
  printf '%s\n' '<!DOCTYPE html>'
  printf '%s\n' '<html lang="en">'
  printf '%s\n' '<head>'
  printf '%s\n' '<meta charset="utf-8">'
  printf '%s\n' '<meta name="viewport" content="width=device-width, initial-scale=1">'
  printf '<title>Spec walkthrough &mdash; %s</title>\n' "$spec_e"
  printf '%s\n' '<style>'
  printf '%s\n' "$css"
  printf '%s\n' '</style>'
  printf '%s\n' '</head>'
  printf '%s\n' '<body>'
  printf '%s\n' '<input type="checkbox" id="reveal-toggle" class="reveal-checkbox">'
  printf '%s\n' '<main class="container">'
  printf '%s\n' '<header class="card hero">'
  printf '%s\n' '<h1 class="hero-title">Spec walkthrough</h1>'
  printf '<p class="provenance" data-provenance="1">Bundle <span class="prov-spec">%s</span> &middot; status <span class="prov-status">%s</span> &middot; generated from commit <span class="prov-commit">%s</span></p>\n' "$spec_e" "$status_e" "$commit_e"
  printf '<p class="stage-framing" data-stage="%s">%s</p>\n' "$status_e" "$stage_text_e"
  printf '<p class="scope-label" data-scope="%s">Showing: %s.</p>\n' "$scope_e" "$scope_label_e"
  printf '%s\n' '<label for="reveal-toggle" class="reveal-label">Reveal identifiers</label>'
  # The read-first hint only promises a teach-back when one is actually rendered
  # (a partial scope may carry no teach-back); otherwise it just frames the read.
  if [ "$show_tb" -eq 1 ]; then
    printf '%s\n' '<p class="read-hint">Read the whole walkthrough first; the teach-back prompt follows it.</p>'
  else
    printf '%s\n' '<p class="read-hint">Read the whole walkthrough first.</p>'
  fi
  printf '%s\n' '</header>'
  [ -n "$onepager_html" ] && printf '%s\n' "$onepager_html"
  [ -n "$decisionmap_html" ] && printf '%s\n' "$decisionmap_html"
  [ -n "$graph_html" ] && printf '%s\n' "$graph_html"
  [ -n "$blast_html" ] && printf '%s\n' "$blast_html"
  [ -n "$verify_html" ] && printf '%s\n' "$verify_html"
  [ -n "$teachback_html" ] && printf '%s\n' "$teachback_html"
  printf '%s\n' '<footer class="card foot">'
  printf '%s\n' '<p class="license">Styling: original CSS, inlined for offline use, drawing on the design language of Tailwind CSS and DaisyUI.</p>'
  printf '%s\n' '<p class="license-text">This stylesheet is original work and bundles no third-party code. It draws on the design conventions and color tokens of Tailwind CSS and DaisyUI, both of which are distributed under the MIT License; this is a credit of inspiration, not a claim on their copyright.</p>'
  printf '%s\n' '</footer>'
  printf '%s\n' '</main>'
  printf '%s\n' '</body>'
  printf '%s\n' '</html>'
}
