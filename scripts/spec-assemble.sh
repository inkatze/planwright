#!/bin/sh
# spec-assemble.sh — the self-contained HTML assembly and styling layer for
# /spec-walkthrough.
#
# Task 6 of specs/spec-comprehension (D-3, D-4, D-7, D-8; REQ-C1.6, REQ-D1.2,
# REQ-D1.3, REQ-E1.1, REQ-E1.2, REQ-E1.4, REQ-E1.5, REQ-E1.6, REQ-E1.7): the
# layer that assembles the rendered views into one offline, dependency-free HTML
# artifact. It runs the one-pager view (Task 4, scripts/spec-onepager.sh) and the
# teach-back view (Task 5, scripts/spec-teachback.sh) over a bundle and emits a
# single self-contained HTML document on stdout:
#
#   - the foregrounded read first, the teach-back prompt after it
#     (silent-read-first ordering, REQ-D1.2);
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
# installed: it opens offline in any browser (D-4, REQ-E1.2). The diagram views
# (the dependency graph, the decision map) and partial-scope rendering land in
# later tasks and extend this same assembly; the MVP artifact is the one-pager
# plus the teach-back.
#
# This script is strictly read-only (REQ-A1.3): it writes nothing but its stdout
# stream. Persisting the document to the gitignored .claude/walkthroughs/<spec>/
# location (REQ-E1.1) is the command scaffold's (scripts/spec-walkthrough.sh)
# one sanctioned write, layered on top of this stdout stream.
#
# Usage:
#   spec-assemble.sh <spec-dir>     # run the chain and emit the HTML artifact
#
# Environment:
#   SPEC_WALKTHROUGH_COMMIT  override the provenance commit (otherwise derived
#                            from the repo HEAD, falling back to "unknown"); set
#                            by the scaffold and used by tests for a stable stamp.
#
# Exit codes:
#   0  the HTML artifact was emitted.
#   2  usage or environment error: no argument, a sibling view script could not
#      be found, or the upstream chain failed (e.g. an absent/unreadable spec
#      directory — fail closed, propagated from the view scripts).
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

spec_dir="${1:-}"
if [ -z "$spec_dir" ] || [ "$spec_dir" = "-" ]; then
  echo "usage: spec-assemble.sh <spec-dir>" >&2
  exit 2
fi

# Resolve the sibling view scripts next to this one (the sibling-script
# convention the whole pipeline follows).
here=$(cd "$(dirname "$0")" && pwd)
onepager_sh="$here/spec-onepager.sh"
teachback_sh="$here/spec-teachback.sh"
graph_sh="$here/spec-graph.sh"
for s in "$onepager_sh" "$teachback_sh" "$graph_sh"; do
  if [ ! -x "$s" ]; then
    echo "spec-assemble: cannot find an executable $(basename "$s") at $s" >&2
    exit 2
  fi
done

# Run the two views in <spec-dir> mode; capture each first so its exit code
# propagates (fail closed on an absent/unreadable spec directory; /bin/sh has no
# portable pipefail). The teach-back is run in dir mode so its section labels are
# the bundle's plain requirement-group headings.
onepager_stream=$("$onepager_sh" "$spec_dir") || exit $?
teachback_stream=$("$teachback_sh" "$spec_dir") || exit $?
graph_stream=$("$graph_sh" "$spec_dir") || exit $?

tab=$(printf '\t')

# Bundle name + status from the BUNDLE pass-through record (the model floors at a
# BUNDLE record for any existing directory); fall back to the directory name.
spec=$(printf '%s\n' "$onepager_stream" | awk -F"$tab" '$1=="BUNDLE"{print $2; exit}')
status=$(printf '%s\n' "$onepager_stream" | awk -F"$tab" '$1=="BUNDLE"{print $3; exit}')
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
    print "<p class=\"graph-intro\">Each box is a piece of work. An arrow runs from a piece to the work that depends on it, so the diagram flows left to right from the earliest work to the last. The highlighted chain is the longest path through the plan &mdash; the run of work that paces the whole effort. Boxes sharing a column have no dependency between them and can move ahead in parallel.</p>"
    if (nn == 0) {
      # The empty-graph GRAPHNOTE carries this same sentence, so it is the single
      # source for the message and is not also echoed as a graph-note (printing
      # both rendered the identical line twice).
      print "<p class=\"graph-empty\">" esc(note) "</p>"
      print "</section>"
      exit
    }
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

onepager_html=$(printf '%s\n' "$onepager_stream" | awk "$onepager_prog")
teachback_html=$(printf '%s\n' "$teachback_stream" | awk "$teachback_prog")
graph_html=$(printf '%s\n' "$graph_stream" | awk "$graph_prog")

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

# Emit the document. Each dynamic value is passed as a printf %s argument (never
# as a format string) so bundle-derived content is never interpreted; the head
# values are pre-escaped, and the body fragments were escaped in awk. The styling
# credit is plain text (no URL) so the artifact references no network resource.
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
  printf '%s\n' '<label for="reveal-toggle" class="reveal-label">Reveal identifiers</label>'
  printf '%s\n' '<p class="read-hint">Read the whole walkthrough first; the teach-back prompt follows it.</p>'
  printf '%s\n' '</header>'
  printf '%s\n' "$onepager_html"
  printf '%s\n' "$graph_html"
  printf '%s\n' "$teachback_html"
  printf '%s\n' '<footer class="card foot">'
  printf '%s\n' '<p class="license">Styling: original CSS, inlined for offline use, drawing on the design language of Tailwind CSS and DaisyUI.</p>'
  printf '%s\n' '<p class="license-text">This stylesheet is original work and bundles no third-party code. It draws on the design conventions and color tokens of Tailwind CSS and DaisyUI, both of which are distributed under the MIT License; this is a credit of inspiration, not a claim on their copyright.</p>'
  printf '%s\n' '</footer>'
  printf '%s\n' '</main>'
  printf '%s\n' '</body>'
  printf '%s\n' '</html>'
}
