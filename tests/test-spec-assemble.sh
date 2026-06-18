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
#   4.  Silent-read-first ordering (REQ-D1.2): the full read (the one-pager
#       section) precedes the teach-back prompt section in document order.
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

tmp=$(mktemp -d)
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
# 4. Silent-read-first ordering (REQ-D1.2): one-pager precedes teach-back.
#    REQ-D1.2 is [manual] [design-level] in test-spec.md — the *unanchored read*
#    is a judged UX property a human confirms. This asserts only the mechanical
#    precondition the artifact must structurally provide: the read (one-pager)
#    comes before the prompt (teach-back) in document order. A regression that
#    reordered the sections would be caught here; the full property stays manual.
# ---------------------------------------------------------------------------
op_off=$(printf '%s\n' "$out" | grep -n 'data-section="onepager"' | head -1 | cut -d: -f1)
tb_off=$(printf '%s\n' "$out" | grep -n 'data-section="teachback"' | head -1 | cut -d: -f1)
gr_off=$(printf '%s\n' "$out" | grep -n 'data-section="graph"' | head -1 | cut -d: -f1)
[ -n "$op_off" ] || fail "no one-pager section marker found"
[ -n "$tb_off" ] || fail "no teach-back section marker found"
[ -n "$gr_off" ] || fail "no graph section marker found"
[ "$op_off" -lt "$tb_off" ] \
  || fail "one-pager (line $op_off) must precede teach-back (line $tb_off)"
# The drawn graph is part of the read (it precedes the teach-back prompt) and
# follows the at-a-glance one-pager: read-first ordering holds with it inline.
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
has 'data-section="teachback"'

# ---------------------------------------------------------------------------
# 12. Composition on a real bundle: full chain renders, escaped, no leak.
# ---------------------------------------------------------------------------
run_dir 0 "$repo_root/specs/spec-comprehension"
has 'spec-comprehension'
has 'data-section="onepager"'
has 'data-section="teachback"'
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

echo "PASS: test-spec-assemble.sh"
