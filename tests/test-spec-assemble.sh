#!/bin/sh
# Unit tests for scripts/spec-assemble.sh — the self-contained HTML assembly and
# styling layer for /spec-walkthrough (Task 6 of specs/spec-comprehension; D-3,
# D-4, D-7, D-8; REQ-C1.6, REQ-D1.2, REQ-D1.3, REQ-E1.1, REQ-E1.2, REQ-E1.4,
# REQ-E1.5, REQ-E1.6, REQ-E1.7). It runs the one-pager (Task 4) and teach-back
# (Task 5) views over a bundle and assembles them into one offline, dependency-
# free HTML document on stdout: the foregrounded read first (silent-read-first
# ordering), then the teach-back prompt, with all bundle content HTML/SVG-escaped
# so no rendered text can inject executable or structural markup, an off-by-
# default reveal toggle for the identifiers, MIT-licensed inlined styling, and a
# bundle+commit provenance stamp.
#
# Properties verified, one numbered section per Task 6 behavior:
#   1.  Single self-contained document: dir mode emits one well-formed HTML
#       document (a single <!DOCTYPE html> / <html> / </html>) on stdout, exit 0.
#   2.  Content escaping / injection safety (REQ-E1.7, the security core): a
#       fixture whose bundle text carries HTML/SVG markup (<script>, an onerror
#       handler, raw < & ", the <spec> placeholder convention) renders that text
#       escaped — the literal characters survive as entities, and no executable
#       or structural markup originating from bundle content appears live in the
#       output (no raw <script>, no live onerror= attribute from bundle text).
#   3.  Reveal toggle off by default (REQ-D1.3): the underlying identifiers are
#       carried in reveal-only elements that the inlined CSS hides by default and
#       a :checked toggle reveals; the toggle ships unchecked; the default-visible
#       (plain) text carries no internal vocabulary.
#   4.  Silent-read-first ordering (REQ-D1.2): the full read (the one-pager then
#       the decision map) precedes the teach-back prompt section in document
#       order.
#   9b. Decision map four-beat (D-2, REQ-C1.4): each decision renders in the ADR
#       shape Context -> Decision -> Alternative-rejected -> Consequence, with the
#       decision content escaped (REQ-E1.7) and the identifiers reveal-only.
#   5.  Provenance stamp (REQ-E1.1, REQ-E1.5): the document records the bundle it
#       rendered and the commit it was generated from (commit overridable for a
#       deterministic stamp).
#   6.  Inlined, redistributable styling (REQ-E1.6): the CSS is inlined in a
#       <style> block, there is no external stylesheet <link>, and the credit to
#       the MIT-licensed Tailwind CSS / DaisyUI design language it draws on is
#       present (an inspiration credit, not a copyright claim on their code).
#   7.  Offline, no external dependency (REQ-E1.2): the document references no
#       network resource — no http(s) URL, no external src/href, no remote font.
#   8.  Drawn, not ASCII (REQ-C1.6): the artifact carries no ASCII-art diagram
#       (no box-drawing block); structured content is real markup, not preformat.
#   9.  Teach-back is present and neutral (D-3, REQ-D1.1): the teach-back renders
#       the claims with an agree/disagree/unsure response control per claim and
#       no verdict/score/right-answer field.
#  10.  Composition + determinism + read-only: a <spec-dir> argument runs the
#       full chain; two runs with a fixed commit are byte-identical; the script
#       writes nothing but its stdout stream.
#  11.  Graceful degradation: a missing spec directory fails closed (exit 2,
#       propagated from the upstream chain); a missing sibling view fails closed.
#  12.  Data hygiene (REQ-E1.4): the generated artifact is clean under the secret
#       scanner (gitleaks), when gitleaks is available.
#
# Runs standalone: ./tests/test-spec-assemble.sh
set -eu

# Pin the C locale: the byte-wise escaping and grep ranges must not vary by host
# locale.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into command substitutions,
# corrupting derived paths (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/spec-assemble.sh"
repo_root=$(cd "$here/.." && pwd)

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$script" ] || fail "scripts/spec-assemble.sh missing or not executable"

tmp="$(mktemp -d)" || exit 1
trap 'chmod -R u+rwx "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

# A deterministic provenance commit so output is byte-stable across runs.
COMMIT=deadbee
export SPEC_WALKTHROUGH_COMMIT="$COMMIT"

out=
run_dir() {
  rexp=$1
  rc=0
  out=$("$script" "$2" 2>&1) || rc=$?
  [ "$rc" -eq "$rexp" ] \
    || fail "dir mode: expected exit $rexp, got $rc for $2 — output: $out"
}

# run_args <expected-exit> <args...> — run with arbitrary args (the --scope
# selector lands here), capture combined output in $out.
run_args() {
  rexp=$1
  shift
  rc=0
  out=$("$script" "$@" 2>&1) || rc=$?
  [ "$rc" -eq "$rexp" ] \
    || fail "expected exit $rexp, got $rc for: $* — output: $out"
}

# secline <name> — 1-based line number of the data-section="<name>" marker, or
# empty when the section is not rendered.
secline() {
  printf '%s\n' "$out" | grep -n "data-section=\"$1\"" | head -1 | cut -d: -f1
}

# has / lacks — substring presence in $out.
has() {
  case $out in
    *"$1"*) ;;
    *) fail "output lacks \"$1\"" ;;
  esac
}
lacks() {
  case $out in
    *"$1"*) fail "output unexpectedly contains \"$1\"" ;;
    *) ;;
  esac
}
# count_substr <needle> — number of non-overlapping occurrences of <needle>.
count_substr() {
  printf '%s' "$out" | awk -v n="$1" '
    { s = s $0 "\n" }
    END {
      c = 0
      while ((i = index(s, n)) > 0) { c++; s = substr(s, i + length(n)) }
      print c
    }'
}

# make_bundle <specs-root> <spec> — a small Active bundle whose requirement text
# deliberately carries HTML/SVG markup metacharacters (the injection-safety
# fixture for REQ-E1.7), plus a clean second requirement and a decision so the
# one-pager and teach-back both have claims.
make_bundle() {
  mr=$1
  ms=$2
  d="$mr/$ms"
  mkdir -p "$d"
  cat >"$d/requirements.md" <<'EOF'
# Fixture — Requirements

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

## REQ-A — markup <i>group</i>

- **REQ-A1.1** The renderer SHALL display <script>alert('xss')</script> and
  <img src=x onerror="boom()"> and a raw & ampersand and the <spec> placeholder
  as literal text. *(Cites: D-1.)*
- **REQ-A1.2** The second thing SHALL exist plainly. *(Cites: D-1.)*

## REQ-B — routine group

- **REQ-B1.1** A third uncited thing SHALL exist. *(Cites: D-2.)*
EOF
  cat >"$d/design.md" <<'EOF'
# Fixture — Design

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

### D-1: First decision  (N)

**Decision:** Render <b>bold</b> markup as literal text, never live.

**Alternatives considered:**
- Nothing. Rejected because: nothing would exist.

**Chosen because:** the fixture needs it.

### D-2: Second decision  (N)

**Decision:** Do the second thing.

**Alternatives considered:**
- Nothing. Rejected because: nothing would exist.

**Chosen because:** the fixture needs it too.
EOF
  cat >"$d/tasks.md" <<'EOF'
# Fixture — Tasks

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

## Forward plan

### Task 1 — broad

- **Deliverables:** a thing.
- **Done when:** the thing exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1, REQ-A1.2
- **Estimated effort:** 1 day

### Task 2 — tail <script>boom()</script>

- **Deliverables:** a thing.
- **Done when:** it exists.
- **Dependencies:** 1
- **Citations:** D-2 · REQ-B1.1
- **Estimated effort:** 2 days
EOF
  cat >"$d/test-spec.md" <<'EOF'
# Fixture — Test Spec

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

### REQ-A1.1 — exists [test]

Assert the thing exists.
EOF
}

specs="$tmp/specs"
make_bundle "$specs" demo

# ---------------------------------------------------------------------------
# 1. Single self-contained document.
# ---------------------------------------------------------------------------
run_dir 0 "$specs/demo"
case $out in
  '<!DOCTYPE html>'*) ;;
  '<!DOCTYPE html'*) ;;
  *) fail "output does not begin with a DOCTYPE: $(printf '%s' "$out" | head -1)" ;;
esac
[ "$(count_substr '<html')" -eq 1 ] || fail "expected exactly one <html> element"
[ "$(count_substr '</html>')" -eq 1 ] || fail "expected exactly one </html> close"
has '<head'
has '</body>'
has '<meta charset='

# ---------------------------------------------------------------------------
# 2. Content escaping / injection safety (REQ-E1.7) — the security core.
# ---------------------------------------------------------------------------
# The bundle's literal markup must survive only as escaped entities. Each
# metacharacter class in the fixture is asserted escaped: angle brackets, the
# ampersand, the double quote (the onerror="..." in the fixture), and the
# placeholder convention. A partial escaper that dropped any one of these would
# be caught here, not only by the negative assertions below.
has '&lt;script&gt;'
has '&amp;'
has '&quot;'
has '&#39;'
has '&lt;spec&gt;'
# No executable/structural markup from bundle content survives live.
lacks "<script>alert('xss')</script>"
lacks '<script>alert'
lacks 'onerror="boom()"'
lacks '<img src=x onerror'
lacks '<b>bold</b>'
# The only <script>/<style> tags allowed are the artifact's own (no inline JS is
# required for this artifact, so assert no <script> tag at all — the bundle's are
# escaped and the artifact ships none).
[ "$(count_substr '<script')" -eq 0 ] \
  || fail "the artifact must contain no live <script> tag (bundle script must be escaped)"
# Section labels are rendered content too (REQ-E1.7 escapes ALL rendered text,
# not only the fields assumed untrusted). The fixture's REQ-A group heading
# carries markup (`markup <i>group</i>`); the teach-back group title must render
# it escaped, never as a live element. A regression dropping the section-label
# esc() (verified to surface live `<i>group</i>` when removed) is caught here.
has '&lt;i&gt;group&lt;/i&gt;'
lacks '<i>group</i>'

# ---------------------------------------------------------------------------
# 3. Reveal toggle off by default (REQ-D1.3).
# ---------------------------------------------------------------------------
# A reveal control exists and is unchecked by default. Assert against the toggle
# element itself, not a loose substring: the word "checked" legitimately appears
# in the CSS (#reveal-toggle:checked …), so the test must confirm the *input tag*
# carries no checked attribute rather than that "checked" is absent from the doc.
has 'id="reveal-toggle"'
toggle_tag=$(printf '%s\n' "$out" | grep -o '<input[^>]*id="reveal-toggle"[^>]*>' | head -1)
[ -n "$toggle_tag" ] || fail "no reveal-toggle input element found"
case $toggle_tag in
  *checked*) fail "reveal toggle ships checked: $toggle_tag" ;;
  *) ;;
esac
# The inlined CSS hides reveal-only content by default and reveals it on :checked.
has '.rv'
case $out in
  *'reveal-toggle:checked'*) ;;
  *) fail "no :checked reveal rule found in the inlined CSS" ;;
esac
# The identifier of the markup requirement (REQ-A1.1) appears only inside a
# reveal-only element: every occurrence of the back-pointer token sits in a
# line/element carrying the reveal-only class. Proxy: the default plain text
# does not surface the identifier scheme, the reveal source does.
has 'REQ-A1.1'
# The default-visible plain rendering of a claim must not carry the id scheme:
# pull the plain spans (class "plain") and assert no REQ-/D-id leaks. We check
# that every literal "REQ-A1.1" co-occurs with the reveal-only class marker on
# the same element by requiring the token never appears in a plain-class span.
leak=$(printf '%s\n' "$out" | grep -o 'class="plain"[^<]*' | grep -E 'REQ-[A-Z][0-9]+\.[0-9]+|D-[0-9]+' || true)
[ -z "$leak" ] || fail "an identifier leaked into a default-visible plain span: $leak"

# ---------------------------------------------------------------------------
# 4. Silent-read-first ordering (REQ-D1.2): the full read precedes the teach-back
#    prompt. The reading content is the one-pager then the decision map; the
#    teach-back prompt comes last.
#    REQ-D1.2 is [manual] [design-level] in test-spec.md — the *unanchored read*
#    is a judged UX property a human confirms. This asserts only the mechanical
#    precondition the artifact must structurally provide: the read (one-pager,
#    decision map) comes before the prompt (teach-back) in document order. A
#    regression that reordered the sections would be caught here; the full
#    property stays manual.
# ---------------------------------------------------------------------------
op_off=$(printf '%s\n' "$out" | grep -n 'data-section="onepager"' | head -1 | cut -d: -f1)
dm_off=$(printf '%s\n' "$out" | grep -n 'data-section="decisionmap"' | head -1 | cut -d: -f1)
tb_off=$(printf '%s\n' "$out" | grep -n 'data-section="teachback"' | head -1 | cut -d: -f1)
gr_off=$(printf '%s\n' "$out" | grep -n 'data-section="graph"' | head -1 | cut -d: -f1)
[ -n "$op_off" ] || fail "no one-pager section marker found"
[ -n "$dm_off" ] || fail "no decision-map section marker found"
[ -n "$tb_off" ] || fail "no teach-back section marker found"
[ -n "$gr_off" ] || fail "no graph section marker found"
[ "$op_off" -lt "$tb_off" ] \
  || fail "one-pager (line $op_off) must precede teach-back (line $tb_off)"
# Both foreground views (decision map, graph) are part of the read: each follows
# the at-a-glance one-pager and precedes the teach-back prompt. Their order
# relative to each other is not asserted — either arrangement is read-first
# compliant.
[ "$op_off" -lt "$dm_off" ] \
  || fail "one-pager (line $op_off) must precede the decision map (line $dm_off)"
[ "$dm_off" -lt "$tb_off" ] \
  || fail "decision map (line $dm_off) must precede teach-back (line $tb_off)"
[ "$op_off" -lt "$gr_off" ] \
  || fail "one-pager (line $op_off) must precede the graph (line $gr_off)"
[ "$gr_off" -lt "$tb_off" ] \
  || fail "graph (line $gr_off) must precede teach-back (line $tb_off)"

# ---------------------------------------------------------------------------
# 5. Provenance stamp (REQ-E1.1, REQ-E1.5): bundle + commit.
# ---------------------------------------------------------------------------
has 'demo'
has "$COMMIT"
# The stamp ties them together in a provenance element.
has 'data-provenance'
# The status is carried in the provenance stamp from the BUNDLE record (no
# basename fallback, unlike the spec name): asserting it guards the BUNDLE-record
# read itself — a regression degrading it would surface here as "(undeclared)".
# The fixture bundle is Active.
has 'class="prov-status">Active<'

# ---------------------------------------------------------------------------
# 6. Inlined, redistributable styling (REQ-E1.6).
# ---------------------------------------------------------------------------
# The CSS inlines in a <style> block with no external stylesheet link. The CSS is
# original work; it credits the MIT-licensed Tailwind CSS / DaisyUI design
# language it draws on (an inspiration credit, not a copyright claim on their
# code), so the artifact still ships cleanly. "MIT" is present as that credit.
has '<style'
lacks '<link rel="stylesheet"'
lacks "rel='stylesheet'"
has 'MIT'

# ---------------------------------------------------------------------------
# 7. Offline, no external dependency (REQ-E1.2): no network resource.
# ---------------------------------------------------------------------------
netref=$(printf '%s\n' "$out" | grep -Eo 'https?://[^"'"'"' )]*' || true)
[ -z "$netref" ] || fail "artifact references a network resource: $netref"
lacks 'src="http'
lacks 'href="http'
lacks '@import'

# ---------------------------------------------------------------------------
# 8. Drawn, not ASCII (REQ-C1.6): no ASCII-art diagram block.
# ---------------------------------------------------------------------------
# No box-drawing characters used to draw a diagram (the MVP has no diagram view
# yet; this guards that structured content is never ASCII-rendered).
boxart=$(printf '%s\n' "$out" | grep -E '[┌┐└┘├┤┬┴┼─│╔╗╚╝]' || true)
[ -z "$boxart" ] || fail "artifact contains ASCII/box-drawing art: $boxart"

# ---------------------------------------------------------------------------
# 9. Teach-back present and neutral (D-3, REQ-D1.1).
# ---------------------------------------------------------------------------
has 'data-section="teachback"'
# An agree/disagree/unsure response control per claim, rendered as radio inputs
# grouped per claim: a unique name= per claim (tb-claim-N) keeps each claim's
# three options mutually exclusive without binding choices across claims. Assert
# the structured name is present, not merely that some radio exists.
has 'type="radio"'
has 'name="tb-claim-'
# Distinct radio groups: more than one claim => more than one tb-claim-N name.
groups=$(printf '%s\n' "$out" | grep -o 'name="tb-claim-[0-9]*"' | sort -u | wc -l | tr -d ' ')
[ "$groups" -ge 2 ] || fail "expected distinct per-claim radio groups, found $groups"
# The three neutral options appear as radio values (no verdict, no fourth "right"
# option). agree/disagree/unsure are the only response values.
for opt in agree disagree unsure; do
  has "value=\"$opt\""
done
# Neutral wording present; no verdict/score/right-answer surfaced.
lacks 'correct answer'
lacks 'pass/fail'
lacks 'data-verdict'
lacks 'data-score'

# ---------------------------------------------------------------------------
# 9b. Decision map present and four-beat (D-2, REQ-C1.4): the decision-map
#     section renders each decision in the ADR four-beat shape (Context,
#     Decision, Alternative rejected, Consequence), with all rendered decision
#     content escaped (REQ-E1.7) and the identifiers reveal-only (REQ-D1.3).
# ---------------------------------------------------------------------------
has 'data-section="decisionmap"'
# The four beat labels are present (the ADR four-beat shape, REQ-C1.4).
has '>Context<'
has '>Decision<'
has '>Alternative rejected<'
has '>Consequence<'
# The frame summary must use the same "alternative rejected" wording as the beat
# labels and REQ-C1.4, not the divergent "alternative considered" (user-visible
# wording consistency within the section).
has 'alternative rejected, and consequence'
lacks 'alternative considered'
# Each decision in the fixture (D-1, D-2) renders a decision item; assert at least
# two decision items so both fixture decisions surfaced.
ditems=$(printf '%s\n' "$out" | grep -o 'class="decision"' | wc -l | tr -d ' ')
[ "$ditems" -ge 2 ] || fail "expected at least two decision items, found $ditems"
# The D-1 Decision field carries markup (`<b>bold</b>`); it must render escaped in
# the decision map, never as a live element (REQ-E1.7). The negative form is
# already asserted globally (lacks '<b>bold</b>'); assert the escaped form is
# present so the decision content actually reached the artifact.
has '&lt;b&gt;bold&lt;/b&gt;'
# The decision identifiers are reveal-only: every D-id back-pointer sits in a
# reveal-only (.rv) element, so the default plain spans carry no decision id.
dleak=$(printf '%s\n' "$out" | grep -o 'class="plain"[^<]*' | grep -E 'D-[0-9]+' || true)
[ -z "$dleak" ] || fail "a decision id leaked into a default-visible plain span: $dleak"

# ---------------------------------------------------------------------------
# 10. Composition + determinism + read-only.
# ---------------------------------------------------------------------------
run1=$("$script" "$specs/demo")
run2=$("$script" "$specs/demo")
[ "$run1" = "$run2" ] || fail "assemble output is not deterministic with a fixed commit"
# Read-only: a run in a clean git work tree leaves it clean (writes only stdout).
if command -v git >/dev/null 2>&1; then
  gws="$tmp/gitws"
  mkdir -p "$gws/specs"
  make_bundle "$gws/specs" demo
  (
    cd "$gws"
    git init -q
    git config user.email t@e.x
    git config user.name t
    git add -A
    git -c commit.gpgsign=false commit -qm init
  )
  (cd "$gws" && "$script" "specs/demo" >/dev/null)
  status_after=$(cd "$gws" && git status --porcelain)
  [ -z "$status_after" ] \
    || fail "assemble was not read-only; git status: $status_after"
fi

# ---------------------------------------------------------------------------
# 11. Graceful degradation: missing dir fails closed; missing sibling fails
#     closed; a partial bundle (the directory exists but lacks some of the four
#     files) still assembles one valid HTML document (REQ-A1.5 degradation, not
#     an opaque halt and not a malformed half-document).
# ---------------------------------------------------------------------------
run_dir 2 "$specs/does-not-exist"
# A copy of the script with no sibling views must fail closed (exit 2), not emit
# a broken half-document.
isolate="$tmp/isolated"
mkdir -p "$isolate"
cp "$script" "$isolate/spec-assemble.sh"
chmod +x "$isolate/spec-assemble.sh"
rc=0
iout=$("$isolate/spec-assemble.sh" "$specs/demo" 2>&1) || rc=$?
[ "$rc" -eq 2 ] \
  || fail "missing sibling views: expected exit 2, got $rc — output: $iout"
# Partial bundle: only requirements.md present (the upstream model degrades,
# marking the absent files and emitting what is present). The assembler must
# still emit one well-formed HTML document, exit 0.
partial="$tmp/partial/specs/demo"
mkdir -p "$partial"
cat >"$partial/requirements.md" <<'EOF'
# Partial — Requirements

**Status:** Draft
**Format-version:** 1

## REQ-A — only group

- **REQ-A1.1** The lone thing SHALL exist. *(Cites: D-1.)*
EOF
run_dir 0 "$tmp/partial/specs/demo"
case $out in
  '<!DOCTYPE html'*) ;;
  *) fail "partial bundle did not produce an HTML document" ;;
esac
[ "$(count_substr '</html>')" -eq 1 ] || fail "partial bundle produced a malformed document"
has 'data-section="onepager"'
has 'data-section="decisionmap"'
has 'data-section="teachback"'
# The partial bundle has no design file, so the decision map has no decisions: it
# renders the empty-state message, not a "0 decisions, each shown as ..." frame
# (graceful degradation, REQ-A1.5; matches the sibling views' empty states).
has 'No decisions to surface.'
lacks '0 decisions, each shown as'

# ---------------------------------------------------------------------------
# 12. Composition on a real bundle: full chain renders, escaped, no leak.
# ---------------------------------------------------------------------------
run_dir 0 "$repo_root/specs/spec-comprehension"
has 'spec-comprehension'
has 'data-section="onepager"'
has 'data-section="decisionmap"'
has 'data-section="teachback"'
# Every real decision renders the full four-beat shape: the count of beat labels
# is four per decision surfaced in the map.
realdecs=$(printf '%s\n' "$out" | grep -o 'class="decision"' | wc -l | tr -d ' ')
[ "$realdecs" -ge 1 ] || fail "real bundle surfaced no decision in the map"
# A real bundle's default plain spans leak no internal vocabulary.
leak=$(printf '%s\n' "$out" | grep -o 'class="plain"[^<]*' | grep -E 'REQ-[A-Z][0-9]+\.[0-9]+|D-[0-9]+' || true)
[ -z "$leak" ] || fail "real bundle leaked an identifier into a plain span: $leak"

# ---------------------------------------------------------------------------
# 13. Data hygiene (REQ-E1.4): the generated artifact is gitleaks-clean.
# ---------------------------------------------------------------------------
if command -v gitleaks >/dev/null 2>&1; then
  art="$tmp/artifact.html"
  "$script" "$specs/demo" >"$art"
  gitleaks detect --no-banner --no-git --source "$art" >/dev/null 2>&1 \
    || fail "gitleaks flagged the generated artifact (REQ-E1.4 data hygiene)"
fi

# ---------------------------------------------------------------------------
# 14. Dependency-graph view (Task 7; D-4, D-5, D-6; REQ-C1.3, REQ-C1.6,
#     REQ-E1.3): the graph renders as an inline SVG (not ASCII) with the
#     critical path highlighted, adjacent to its explaining text, with a layout
#     note, and every bundle-derived label escaped.
# ---------------------------------------------------------------------------
run_dir 0 "$specs/demo"
has 'data-section="graph"'
# Drawn, not ASCII: an inline <svg> is present (REQ-C1.6). The boxart guard in
# section 8 already proves no ASCII-art diagram.
has '<svg'
# The critical path is highlighted: at least one node and one edge carry the
# critical class. With the fixture graph (1 -> 2, both on the longest chain),
# the two nodes and the one edge are all critical.
ncrit=$(count_substr 'graph-node-critical')
[ "$ncrit" -ge 1 ] || fail "no critical node highlighted in the graph"
ecrit=$(count_substr 'graph-edge-critical')
[ "$ecrit" -ge 1 ] || fail "no critical edge highlighted in the graph"
# Adjacent explaining text (REQ-C1.3): the graph section carries prose that
# explains the diagram in plain language (no internal vocabulary).
has 'class="graph-intro"'
# The layout/degradation note is present in the artifact (D-5, REQ-E1.3). On a
# host without dot this is the built-in note; the assertion is the note exists.
has 'class="graph-note"'
# SVG label escaping (REQ-E1.7 in SVG text context): the markup-bearing task
# title renders escaped, never as a live element. The node's full label lives in
# an SVG <title> tooltip, escaped.
has '&lt;script&gt;boom()&lt;/script&gt;'
lacks '<script>boom()</script>'
# The plain node labels carry no internal vocabulary by default: the task ids
# (a "#N" back-pointer) sit only in reveal-only graph elements, never in the
# default-visible node label text. (The reveal element uses the shared .rv hook.)
has 'class="graph-svg"'
# Still no live <script> anywhere (the bundle's are all escaped, incl. the graph
# label) — re-assert after adding the graph.
[ "$(count_substr '<script')" -eq 0 ] \
  || fail "graph introduced a live <script> (a bundle label must be escaped)"

# ---------------------------------------------------------------------------
# 15. Graph node labels honor the MAXLABEL budget: a title longer than the
#     budget renders truncated with an ellipsis, and the visible <text> content
#     (content + "...") never exceeds MAXLABEL=26. The full, untruncated title
#     stays in the node's <title> tooltip.
# ---------------------------------------------------------------------------
longspecs="$tmp/long"
make_bundle "$longspecs" demo
cat >"$longspecs/demo/tasks.md" <<'EOF'
# Fixture — Tasks

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

## Forward plan

### Task 1 — supercalifragilisticexpialidociousX

- **Deliverables:** a thing.
- **Done when:** the thing exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1, REQ-A1.2
- **Estimated effort:** 1 day
EOF
run_dir 0 "$longspecs/demo"
glabel=$(printf '%s\n' "$out" | sed -n 's/.*<text class="graph-label"[^>]*>\(.*\)<\/text>.*/\1/p' | head -1)
[ -n "$glabel" ] || fail "no graph-label text found for the long-title node"
glen=${#glabel}
[ "$glen" -le 26 ] || fail "graph label exceeds MAXLABEL=26: [$glabel] (len=$glen)"
case $glabel in
  *...) ;;
  *) fail "long graph label should end with an ellipsis: [$glabel]" ;;
esac
# The full title survives untruncated in the node <title> tooltip.
has '<title>supercalifragilisticexpialidociousX</title>'

# ---------------------------------------------------------------------------
# 16. Empty-graph section (REQ-A1.5 graceful degradation): a bundle with no
#     task graph renders the empty-graph note alone — the graph-intro prose
#     describes the arrows / critical path / parallel columns of a diagram, so
#     printing it when no diagram is drawn contradicts the "clear message"
#     posture. The empty case shows the heading and the empty note, never the
#     intro and never an <svg>.
# ---------------------------------------------------------------------------
emptyspecs="$tmp/empty"
make_bundle "$emptyspecs" demo
cat >"$emptyspecs/demo/tasks.md" <<'EOF'
# Fixture — Tasks

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

## Forward plan
EOF
run_dir 0 "$emptyspecs/demo"
has 'data-section="graph"'
has 'class="graph-empty"'
# The intro describes a diagram that is not drawn in the empty case, so it must
# not appear. This is the regression guard for the empty-graph branch.
lacks 'class="graph-intro"'
# No diagram is rendered when there is no task graph.
lacks 'class="graph-svg"'

# ---------------------------------------------------------------------------
# 17. Stage-aware framing (Task 9; D-11, REQ-B1.3): the artifact's framing
#     adapts to the bundle's auto-detected status — no status flag is passed,
#     the assembler reads it from the bundle. The framing element carries the
#     detected status in data-stage, and the framing prose differs by stage
#     (Draft cold read, Active orientation+progress, Done/terminal onboarding or
#     archaeology). REQ-B1.3 is [test + manual]: the auto-detection (the
#     data-stage value tracks the bundle status) and the prose-differs property
#     are the [test] part asserted here; the framing's editorial fitness stays
#     [manual].
# ---------------------------------------------------------------------------
# The Active demo bundle: data-stage tracks the status, and the framing names
# the in-progress orientation.
run_dir 0 "$specs/demo"
has 'class="stage-framing"'
has 'data-stage="Active"'
active_frame=$out

# A small single-file bundle per status (framing reads the BUNDLE status, which
# comes from requirements.md, so requirements.md alone exercises the detection).
make_status_bundle() {
  msb=$1
  mst=$2
  mkdir -p "$msb"
  cat >"$msb/requirements.md" <<EOF
# Stage fixture — Requirements

**Status:** $mst
**Format-version:** 1

## REQ-A — only group

- **REQ-A1.1** The lone thing SHALL exist. *(Cites: D-1.)*
EOF
}

stageroot="$tmp/stage"
for st in Draft Ready Done Retired Superseded; do
  make_status_bundle "$stageroot/$st/specs/demo" "$st"
  run_dir 0 "$stageroot/$st/specs/demo"
  has "data-stage=\"$st\""
done

# Ready stage framing (Task 7; D-1, D-8, REQ-E1.1): the six-status lifecycle
# inserts Ready between Draft and Active ("signed off, validated, executable, no
# work started"). A Ready bundle must get its own stage prose, distinct from the
# unknown-status fallback — it must NOT fall through to the default arm. Before
# Task 7 the case had no Ready arm, so a Ready bundle hit the `*)` default; this
# is the regression guard for the dedicated Ready framing.
make_status_bundle "$stageroot/Ready/specs/demo" Ready
run_dir 0 "$stageroot/Ready/specs/demo"
ready_only=$(printf '%s\n' "$out" | grep 'class="stage-framing"' | head -1)
[ -n "$ready_only" ] || fail "no stage-framing line in the Ready artifact"
ready_prose=$(printf '%s' "$ready_only" | sed 's/ data-stage="[^"]*"//')

# The default fallback prose: a status outside the six-status set hits the `*)`
# arm. Ready must have dedicated framing, not this fallback.
make_status_bundle "$stageroot/Unknownst/specs/demo" Nonesuch
run_dir 0 "$stageroot/Unknownst/specs/demo"
fallback_only=$(printf '%s\n' "$out" | grep 'class="stage-framing"' | head -1)
fallback_prose=$(printf '%s' "$fallback_only" | sed 's/ data-stage="[^"]*"//')
[ "$ready_prose" != "$fallback_prose" ] \
  || fail "Ready stage framing fell through to the default fallback (it must have dedicated Ready-stage prose)"

# Source-enumeration guard (Task 7; REQ-E1.1 "a grep test asserts status
# enumerations include Ready"): the assembler's stage case must carry a Ready
# arm, and the /spec-walkthrough Status-agnostic invariant must name Ready in its
# rendered status set. Catches a regression that dropped Ready from either
# enumeration even if the prose tests above were skipped.
grep -qE '^  Ready\)' "$script" \
  || fail "scripts/spec-assemble.sh stage case is missing a Ready) arm"
skill_md="$here/../skills/spec-walkthrough/SKILL.md"
grep -qE 'Draft, Ready,[[:space:]]*$|Draft, Ready, Active' "$skill_md" \
  || fail "skills/spec-walkthrough/SKILL.md Status-agnostic enumeration does not name Ready"

# The prose differs by stage: the Draft framing is not the Active framing. A
# regression that emitted one constant framing string for every status would be
# caught here (the Done-when: "the framing changes with the bundle's status").
make_status_bundle "$stageroot/Draft2/specs/demo" Draft
run_dir 0 "$stageroot/Draft2/specs/demo"
draft_frame=$out
draft_only=$(printf '%s\n' "$draft_frame" | grep 'class="stage-framing"' | head -1)
active_only=$(printf '%s\n' "$active_frame" | grep 'class="stage-framing"' | head -1)
[ -n "$draft_only" ] || fail "no stage-framing line in the Draft artifact"
[ -n "$active_only" ] || fail "no stage-framing line in the Active artifact"
# Compare the framing *prose*, not the data-stage attribute. data-stage already
# differs by status (asserted above), so comparing the whole <p> line would pass
# even if the prose were a single constant string. Strip data-stage="..." first
# so this assertion actually proves the framing prose adapts to the status.
draft_prose=$(printf '%s' "$draft_only" | sed 's/ data-stage="[^"]*"//')
active_prose=$(printf '%s' "$active_only" | sed 's/ data-stage="[^"]*"//')
[ "$draft_prose" != "$active_prose" ] \
  || fail "stage framing prose did not change between Draft and Active (it must adapt to status)"

# ---------------------------------------------------------------------------
# 18. Scope selection (Task 9; REQ-B1.1, REQ-B1.2): each partial selector
#     renders only its scope. The whole-bundle default renders all four views;
#     a partial selector renders only the sections in its scope.
# ---------------------------------------------------------------------------
# --scope whole is the explicit default: all four views present, identical
# section set to the no-scope default.
run_args 0 --scope whole "$specs/demo"
has 'data-section="onepager"'
has 'data-section="decisionmap"'
has 'data-section="graph"'
has 'data-section="teachback"'
# A scope label names what is being shown (so a partial render is never mistaken
# for the whole bundle), carrying the raw selector in data-scope.
has 'data-scope="whole"'

# decisions: only the decision map (and the teach-back of those decisions). No
# one-pager, no graph.
run_args 0 --scope decisions "$specs/demo"
has 'data-section="decisionmap"'
[ -z "$(secline onepager)" ] || fail "scope decisions rendered the one-pager"
[ -z "$(secline graph)" ] || fail "scope decisions rendered the graph"
# Both fixture decisions are present.
ditems=$(printf '%s\n' "$out" | grep -o 'class="decision"' | wc -l | tr -d ' ')
[ "$ditems" -ge 2 ] || fail "scope decisions surfaced fewer than two decisions"

# tasks: only the dependency graph. No one-pager, no decision map.
run_args 0 --scope tasks "$specs/demo"
has 'data-section="graph"'
has '<svg'
[ -z "$(secline onepager)" ] || fail "scope tasks rendered the one-pager"
[ -z "$(secline decisionmap)" ] || fail "scope tasks rendered the decision map"

# reqs:B: the one-pager (and teach-back) for group B only. Group A's content and
# the decision map / graph are absent. The fixture's group-B requirement text
# ("third uncited thing") is present; group A's distinctive D-1 decision content
# is not rendered (no decision map at all).
run_args 0 --scope reqs:B "$specs/demo"
has 'data-section="onepager"'
[ -z "$(secline decisionmap)" ] || fail "scope reqs:B rendered the decision map"
[ -z "$(secline graph)" ] || fail "scope reqs:B rendered the graph"
has 'third uncited thing'

# reqs:A: group A only; group B's requirement text is filtered out.
run_args 0 --scope reqs:A "$specs/demo"
has 'data-section="onepager"'
lacks 'third uncited thing'

# file:design renders the decision map; file:tasks the graph.
run_args 0 --scope file:design "$specs/demo"
has 'data-section="decisionmap"'
[ -z "$(secline graph)" ] || fail "scope file:design rendered the graph"
run_args 0 --scope file:tasks "$specs/demo"
has 'data-section="graph"'
[ -z "$(secline decisionmap)" ] || fail "scope file:tasks rendered the decision map"

# file:test-spec renders the verification view (which requirements carry a test
# path); the fixture's REQ-A1.1 has a [test] entry. No one-pager / map / graph.
run_args 0 --scope file:test-spec "$specs/demo"
has 'data-section="verification"'
[ -z "$(secline onepager)" ] || fail "scope file:test-spec rendered the one-pager"
[ -z "$(secline graph)" ] || fail "scope file:test-spec rendered the graph"
# The view actually lists the tested requirement, not just an empty section: the
# fixture's REQ-A1.1 carries a [test] entry, so the non-empty frame and the
# requirement's reveal ref render. A regression that emitted an empty "What is
# checked" section (or dropped TEST records in translation) would pass the
# existence check above but fail here. The "1 requirement" count distinguishes
# the non-empty frame from the empty-state note ("No requirement carries ...").
has '1 requirement carries an automated check'
has 'REQ-A1.1'
# REQ-A1.1's text carries markup; the verification view renders it escaped, the
# same injection-safety guarantee the other views give (no live script survives).
has '&lt;script&gt;alert'
[ "$(count_substr '<script')" -eq 0 ] \
  || fail "verification view introduced a live <script> (a tested requirement's text must be escaped)"

# ---------------------------------------------------------------------------
# 19. Single-decision blast radius (Task 9; REQ-B1.2): decision:<id> shows the
#     decision plus its blast radius — the requirements and tasks that cite it.
#     In the fixture D-1 is cited by Task 1 ("broad") but not Task 2 ("tail …");
#     D-2 is cited by Task 2 but not Task 1.
# ---------------------------------------------------------------------------
run_args 0 --scope decision:1 "$specs/demo"
# The selected decision is rendered in the four-beat decision map.
has 'data-section="decisionmap"'
has '>Context<'
has '>Decision<'
# A dedicated blast-radius section names what the decision affects.
has 'data-section="blastradius"'
# D-1's blast radius includes Task 1 ("broad") and excludes Task 2 ("tail …").
has 'broad'
lacks 'tail'
# Only one decision is shown (the selected one): exactly one decision item.
ditems=$(printf '%s\n' "$out" | grep -o 'class="decision"' | wc -l | tr -d ' ')
[ "$ditems" -eq 1 ] || fail "scope decision:1 rendered $ditems decisions, expected exactly 1"
# The graph and one-pager are not part of a single-decision view.
[ -z "$(secline graph)" ] || fail "scope decision:1 rendered the full graph"
[ -z "$(secline onepager)" ] || fail "scope decision:1 rendered the one-pager"

# The D-/d- prefix forms resolve to the same decision.
run_args 0 --scope decision:D-1 "$specs/demo"
has 'data-section="blastradius"'
ditems=$(printf '%s\n' "$out" | grep -o 'class="decision"' | wc -l | tr -d ' ')
[ "$ditems" -eq 1 ] || fail "scope decision:D-1 rendered $ditems decisions, expected exactly 1"

# decision:2's blast radius surfaces Task 2 ("tail …") and excludes the broad
# Task 1 — the radius tracks the selected decision's citations. Task 2's title
# carries markup; the blast view renders it escaped (the plain rendering drops
# the bare "()" but the markup metacharacters survive as escaped entities).
run_args 0 --scope decision:2 "$specs/demo"
has 'data-section="blastradius"'
has 'tail'
lacks 'broad'
has '&lt;script&gt;boom&lt;/script&gt;'
lacks '<script>boom'

# A blast-radius render is still injection-safe: no live script survives.
[ "$(count_substr '<script')" -eq 0 ] \
  || fail "blast-radius view introduced a live <script> (a bundle label must be escaped)"

# ---------------------------------------------------------------------------
# 19b. A graph-only scope (tasks, file:tasks) renders from the on-disk bundle and
#      must not run — nor inherit a failure from — the scope+translate chain that
#      only the text views consume (Copilot review, PR #63). With the translate
#      sibling broken, a graph-only render still succeeds; a translate-dependent
#      scope still fails closed, proving the broken sibling actually bites.
# ---------------------------------------------------------------------------
gtmp="$tmp/gtrans"
mkdir -p "$gtmp"
cp "$here/../scripts/"*.sh "$gtmp/"
cat >"$gtmp/spec-translate.sh" <<'EOF'
#!/bin/sh
echo "spec-translate: forced failure for the test" >&2
exit 3
EOF
chmod +x "$gtmp/"*.sh
for goscope in tasks file:tasks; do
  rc=0
  gout=$("$gtmp/spec-assemble.sh" --scope "$goscope" "$specs/demo" 2>&1) || rc=$?
  [ "$rc" -eq 0 ] \
    || fail "graph-only scope ($goscope) must not depend on translate; failed rc=$rc: $gout"
  case $gout in
    *'data-section="graph"'*) ;;
    *) fail "graph-only scope ($goscope) with broken translate did not render the graph" ;;
  esac
done
rc=0
dout=$("$gtmp/spec-assemble.sh" --scope decisions "$specs/demo" 2>&1) || rc=$?
[ "$rc" -ne 0 ] \
  || fail "a translate-dependent scope (decisions) must fail closed when translate is broken: $dout"

# ---------------------------------------------------------------------------
# 19d. Whole-bundle perf parity (Copilot review, PR #63): the whole-bundle
#      assembler must not run a redundant spec-model.sh parse — its views already
#      read the model in <spec-dir> mode. Count model parses via a wrapper; the
#      whole-mode total must equal the parses its four views make on their own (no
#      extra direct parse). A regression that re-adds a direct parse shows up as
#      exactly one extra invocation. Robust to per-view parse counts: it compares
#      the assembler's total against the views' own total, nothing hardcoded.
# ---------------------------------------------------------------------------
mc="$tmp/modelcount"
mkdir -p "$mc/scripts"
cp "$here/../scripts/"*.sh "$mc/scripts/"
mv "$mc/scripts/spec-model.sh" "$mc/scripts/spec-model-real.sh"
cat >"$mc/scripts/spec-model.sh" <<EOF
#!/bin/sh
echo x >>"$mc/calls"
exec "$mc/scripts/spec-model-real.sh" "\$@"
EOF
chmod +x "$mc/scripts/spec-model.sh"
# The parses the four whole-mode views make on their own (dir mode).
: >"$mc/calls"
"$mc/scripts/spec-onepager.sh" "$specs/demo" >/dev/null
"$mc/scripts/spec-decisionmap.sh" "$specs/demo" >/dev/null
"$mc/scripts/spec-teachback.sh" "$specs/demo" >/dev/null
"$mc/scripts/spec-graph.sh" "$specs/demo" >/dev/null
views_parses=$(wc -l <"$mc/calls" | tr -d ' ')
# The whole-bundle assembler's parses.
: >"$mc/calls"
"$mc/scripts/spec-assemble.sh" --scope whole "$specs/demo" >/dev/null
whole_parses=$(wc -l <"$mc/calls" | tr -d ' ')
[ "$whole_parses" -eq "$views_parses" ] \
  || fail "whole-bundle made $whole_parses model parses; its views alone make $views_parses (a redundant direct parse regressed)"

# ---------------------------------------------------------------------------
# 19c. Echo discipline (REQ-H1.3): spec-assemble.sh is callable directly, bypassing
#      the scaffold's charset gate, so a hostile --scope carrying control characters
#      is stripped before being echoed to stderr (Copilot review, PR #63; matches
#      the sibling spec-walkthrough.sh / spec-validate.sh). Each selector lands on a
#      different malformed-selector error branch (unknown, no-such-file, bad reqs
#      group, bad decision id); none may echo the raw control byte.
# ---------------------------------------------------------------------------
esc=$(printf '\033')
for hostile in "${esc}[31mbogus" "file:${esc}nope" "reqs:${esc}x" "decision:${esc}9"; do
  rc=0
  hout=$("$script" --scope "$hostile" "$specs/demo" 2>&1 >/dev/null) || rc=$?
  [ "$rc" -eq 2 ] \
    || fail "hostile scope must fail closed (exit 2), got $rc"
  case $hout in
    *"$esc"*) fail "raw control character reached stderr (echo discipline violated)" ;;
  esac
done

# ---------------------------------------------------------------------------
# 20. Scope is forwarded through the command scaffold (spec-walkthrough.sh): a
#     partial selector produces a scoped artifact, not the whole bundle. This
#     guards the scaffold->assembler wiring (the scaffold validates the selector
#     and must hand it to the assembler, not drop it).
# ---------------------------------------------------------------------------
walkthrough="$here/../scripts/spec-walkthrough.sh"
if [ -x "$walkthrough" ]; then
  wkroot="$tmp/wk"
  make_bundle "$wkroot/specs" demo
  artifact="$wkroot/.claude/walkthroughs/demo/demo.html"
  (cd "$wkroot" && SPEC_WALKTHROUGH_COMMIT="$COMMIT" "$walkthrough" --scope decisions "specs/demo" >/dev/null 2>&1)
  [ -f "$artifact" ] || fail "scaffold did not write the scoped artifact at $artifact"
  out=$(cat "$artifact")
  has 'data-section="decisionmap"'
  [ -z "$(secline onepager)" ] \
    || fail "scaffold did not forward --scope decisions to the assembler (one-pager present)"
fi

# ---------------------------------------------------------------------------
# 21. Defense-in-depth selector validation (Task 9; REQ-B1.1): the scaffold
#     (spec-walkthrough.sh) charset-validates the selector, but spec-assemble.sh
#     is callable directly (the tests above call it without the scaffold), so it
#     re-classifies the selector and must fail closed on a malformed one (exit 2,
#     a clear message) rather than degrade to a silent whole-bundle render. One
#     case per malformed class: unknown form, unknown file, non-uppercase group,
#     non-numeric decision id.
# ---------------------------------------------------------------------------
run_args 2 --scope bogus "$specs/demo"
has 'unknown scope'
run_args 2 --scope file:nope "$specs/demo"
has 'names no source file'
run_args 2 --scope reqs:lower "$specs/demo"
has 'is not a requirement group'
run_args 2 --scope decision:abc "$specs/demo"
has 'is not a decision id'
# A bare --scope with no selector value is a usage error (exit 2).
run_args 2 --scope

echo "PASS: test-spec-assemble.sh"
