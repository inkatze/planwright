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
#   6.  Inlined MIT-licensed styling (REQ-E1.6): the CSS is inlined in a <style>
#       block, there is no external stylesheet <link>, and the MIT notice is
#       present (crediting the styling primitives).
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

## REQ-A — markup group

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
# The bundle's literal markup must survive only as escaped entities.
has '&lt;script&gt;'
has '&amp;'
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

# ---------------------------------------------------------------------------
# 3. Reveal toggle off by default (REQ-D1.3).
# ---------------------------------------------------------------------------
# A reveal control exists and is unchecked by default.
has 'id="reveal-toggle"'
case $out in
  *'id="reveal-toggle"'*'checked'*) fail "reveal toggle must not ship checked" ;;
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
# ---------------------------------------------------------------------------
op_off=$(printf '%s\n' "$out" | grep -n 'data-section="onepager"' | head -1 | cut -d: -f1)
tb_off=$(printf '%s\n' "$out" | grep -n 'data-section="teachback"' | head -1 | cut -d: -f1)
[ -n "$op_off" ] || fail "no one-pager section marker found"
[ -n "$tb_off" ] || fail "no teach-back section marker found"
[ "$op_off" -lt "$tb_off" ] \
  || fail "one-pager (line $op_off) must precede teach-back (line $tb_off)"

# ---------------------------------------------------------------------------
# 5. Provenance stamp (REQ-E1.1, REQ-E1.5): bundle + commit.
# ---------------------------------------------------------------------------
has 'demo'
has "$COMMIT"
# The stamp ties them together in a provenance element.
has 'data-provenance'

# ---------------------------------------------------------------------------
# 6. Inlined MIT-licensed styling (REQ-E1.6).
# ---------------------------------------------------------------------------
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
# An agree/disagree/unsure response control per claim, rendered as radio inputs.
has 'type="radio"'
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
# 11. Graceful degradation: missing dir fails closed; missing sibling fails closed.
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

echo "PASS: test-spec-assemble.sh"
