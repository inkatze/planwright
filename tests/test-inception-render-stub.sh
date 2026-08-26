#!/bin/bash
# Tests for the dashboard-fields-only stub renderer (inception Task 2;
# REQ-G1.1, REQ-C1.7 · D-9, D-12).
#
# Task 2 ships this renderer only so the scaffolded pre-commit
# export-regeneration step has something real to call; Task 12 replaces it with
# the full dashboard + pitch-narrative renderer. The assertions below therefore
# pin the stub contract and nothing beyond it: it regenerates deterministically,
# it escapes bundle content, it refuses a bundle whose format-version this
# plugin does not support (deferring to the validator rather than duplicating
# the check), and it renders the dashboard fields REQ-G1.2 names.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RENDER="$REPO_ROOT/scripts/inception-render.sh"

# shellcheck source=tests/lib/inception-fixture.sh
. "$REPO_ROOT/tests/lib/inception-fixture.sh"

failures=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to find '$2' in output)" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (did not expect '$2' in output)" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -x "$RENDER" ]; then
  echo "FAIL: renderer missing or not executable at $RENDER" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

fresh() {
  d="$(mktemp -d "$tmp/vXXXXXX")" || exit 1
  inception_fixture_write "$d" "${1:-untracked}" || exit 1
  printf '%s' "$d"
}
sed_i() { sed "$2" "$1" >"$1.new" && mv "$1.new" "$1"; }

# Every run pins "today" so the kill-date classification is a fixed function of
# the fixture. Without it a run that straddles midnight renders differently.
export PLANWRIGHT_INCEPTION_TODAY=2026-08-26

# ---------------------------------------------------------------------------
# 1. It renders, to the conventional derived-content path.
# ---------------------------------------------------------------------------
v="$(fresh)"
out="$("$RENDER" "$v" 2>&1)"
rc=$?
assert_eq "render: exit 0" "0" "$rc"
if [ -f "$v/exports/venture.html" ]; then
  echo "ok: render: writes exports/venture.html"
else
  echo "FAIL: render: exports/venture.html was not written" >&2
  failures=$((failures + 1))
fi
html="$(cat "$v/exports/venture.html")"

assert_contains "render: declares utf-8" 'charset="utf-8"' "$html"
assert_contains "render: names the venture" "Northwind Signals" "$html"
assert_contains "render: shows the lifecycle status" "Exploring" "$html"
assert_contains "render: shows the success metric" "ten minutes" "$html"

# REQ-G1.2 dashboard fields.
assert_contains "dashboard: gate readiness" "Gate readiness" "$html"
assert_contains "dashboard: blocking assumptions" "Blocking assumptions" "$html"
assert_contains "dashboard: kill criteria" "Kill criteria" "$html"
assert_contains "dashboard: open forks" "Open forks" "$html"
assert_contains "dashboard: blockers" "Blockers" "$html"
assert_contains "dashboard: lists the blocking assumptions" "A-2" "$html"
assert_contains "dashboard: lists the open fork" "DEC-1" "$html"
assert_not_contains "dashboard: omits the decided fork" "DEC-2" "$html"
assert_not_contains "dashboard: omits the superseded assumption" "A-3" "$html"

# Self-contained: no network fetch, no sidecar asset (REQ-G1.1).
assert_not_contains "render: no external http reference" "http://" "$html"
assert_not_contains "render: no external https reference" "https://" "$html"
assert_not_contains "render: no linked stylesheet" "<link" "$html"

# ---------------------------------------------------------------------------
# 2. Determinism: same bundle, same bytes.
# ---------------------------------------------------------------------------
cp "$v/exports/venture.html" "$tmp/first.html"
"$RENDER" "$v" >/dev/null 2>&1
if cmp -s "$tmp/first.html" "$v/exports/venture.html"; then
  echo "ok: render: byte-identical on a repeated run"
else
  echo "FAIL: render: repeated run produced different bytes" >&2
  failures=$((failures + 1))
fi

# ---------------------------------------------------------------------------
# 3. Escaping: bundle content is data, never markup.
# ---------------------------------------------------------------------------
v="$(fresh)"
sed_i "$v/brief.md" 's|^Median incident-handover time drops below ten minutes within one quarter of adoption.$|Cut <script>alert("x")</script> handover \& re-keying time.|'
"$RENDER" "$v" >/dev/null 2>&1
html="$(cat "$v/exports/venture.html")"
assert_not_contains "escaping: no raw script tag" "<script>" "$html"
assert_contains "escaping: angle brackets escaped" "&lt;script&gt;" "$html"
assert_contains "escaping: ampersand escaped" "&amp;" "$html"
assert_contains "escaping: double quote escaped" "&quot;" "$html"

# ---------------------------------------------------------------------------
# 4. Kill-date classification, as a function of the pinned today.
# ---------------------------------------------------------------------------
v="$(fresh)"
PLANWRIGHT_INCEPTION_TODAY=2026-09-20 "$RENDER" "$v" >/dev/null 2>&1
html="$(cat "$v/exports/venture.html")"
assert_contains "kill dates: a past date is tripped" "KC-2</span> — tripped" "$html"
assert_contains "kill dates: a date inside 30 days is approaching" "KC-1</span> — approaching" "$html"
assert_contains "kill dates: a tripped criterion is a blocker" "KC-2</span> kill criterion is tripped" "$html"

v="$(fresh)"
PLANWRIGHT_INCEPTION_TODAY=2026-01-01 "$RENDER" "$v" >/dev/null 2>&1
html="$(cat "$v/exports/venture.html")"
assert_contains "kill dates: a distant date is clear" "KC-1</span> — clear" "$html"
assert_contains "kill dates: the other distant date is clear" "KC-2</span> — clear" "$html"

# ---------------------------------------------------------------------------
# 5. Version gating: refuse rather than render (REQ-C1.7). The renderer defers
#    to the validator check instead of re-implementing it.
# ---------------------------------------------------------------------------
v="$(fresh)"
"$RENDER" "$v" >/dev/null 2>&1
cp "$v/exports/venture.html" "$tmp/before.html"
for f in brief disciplines assumptions decisions plan; do
  sed_i "$v/$f.md" 's|^\*\*Format-version:\*\* 1\.0$|**Format-version:** 7.0|'
done
out="$("$RENDER" "$v" 2>&1)"
rc=$?
assert_eq "unsupported version: exit 3" "3" "$rc"
assert_contains "unsupported version: plain-language refusal" "unsupported" "$out"
if cmp -s "$tmp/before.html" "$v/exports/venture.html"; then
  echo "ok: unsupported version: the previous export is left untouched"
else
  echo "FAIL: unsupported version: the export was overwritten anyway" >&2
  failures=$((failures + 1))
fi

# Structural completeness and a tripped criterion are different facts, and the
# page says both rather than folding them into one ready/not-ready line: a
# venture can carry every piece a gate needs and still be one the gate kills.
v="$(fresh)"
sed_i "$v/assumptions.md" 's|^- \*\*Blocking:\*\* yes$|- **Blocking:** no|'
sed_i "$v/decisions.md" 's|^- \*\*Status:\*\* open$|- **Status:** decided|'
sed_i "$v/decisions.md" 's|^- \*\*Status:\*\* deferred$|- **Status:** decided|'
PLANWRIGHT_INCEPTION_TODAY=2099-01-01 "$RENDER" "$v" >/dev/null 2>&1
html="$(cat "$v/exports/venture.html")"
assert_contains "readiness: structural completeness is still reported" \
  "Minimum core is structurally met" "$html"
assert_contains "readiness: the trip is named as its own outcome" \
  "a kill criterion has tripped" "$html"
assert_not_contains "readiness: blockers are not equated with incompleteness" \
  "Not ready: see the blockers below" "$html"

# The validator fails closed for three different reasons and the renderer sees
# only one exit code, so it must not name a cause it has not established. A
# missing file is not a version problem, and saying it is sends the operator
# looking for a `Format-version:` line that is fine.
v="$(fresh)"
rm -f "$v/plan.md"
out="$("$RENDER" "$v" 2>&1)"
rc=$?
assert_eq "fail-closed for a missing file: exit 3" "3" "$rc"
assert_not_contains "fail-closed for a missing file: does not blame the version" \
  "inception-render: refusing to render this bundle (see the unsupported format-version" "$out"

# A bundle with ordinary findings still renders: the hook regenerates the export
# on every bundle-changing commit, and only an unparseable version stops it.
v="$(fresh)"
sed_i "$v/plan.md" 's|^- \*\*Kind:\*\* spike$|- **Kind:** vibes|'
"$RENDER" "$v" >/dev/null 2>&1
rc=$?
assert_eq "bundle with findings still renders: exit 0" "0" "$rc"

# ...but "still renders" must not mean "renders anything". The renderer only
# version-checks, so a bundle the validator would reject on KC-FORM reaches it
# intact, and a kill criterion missing its date tail would otherwise feed the
# criterion's own prose to the date arithmetic. That silently classifies it —
# and "tripped" is the state that tells a venture to kill or re-scope itself.
v="$(fresh)"
sed_i "$v/brief.md" 's|^\(- \*\*KC-1:\*\* .*\) — by .*$|\1|'
out="$("$RENDER" "$v" 2>&1)"
rc=$?
assert_eq "unreadable kill date: still renders" "0" "$rc"
html="$(cat "$v/exports/venture.html")"
assert_not_contains "unreadable kill date: is not classified as tripped" "KC-1</span> — tripped" "$html"
assert_contains "unreadable kill date: says the date is unreadable" "KC-1</span> — date unreadable" "$html"
assert_contains "unreadable kill date: is surfaced as a blocker" "KC-1</span> has no readable date" "$html"

# The export is what stakeholders read off the forge, so it carries the same
# explicit mode the scaffolded files do rather than whatever the temp file was
# created with.
v="$(fresh)"
"$RENDER" "$v" >/dev/null 2>&1
# `find -perm -044` rather than parsing `ls` or reaching for `stat`, whose flags
# differ between GNU and BSD (REQ-K1.5). The property under test is that the
# export is readable beyond its owner, not its exact octal mode.
readable="$(find "$v/exports" -name venture.html -perm -044 2>/dev/null)"
assert_eq "export: is group- and world-readable" "$v/exports/venture.html" "$readable"

# A missing bundle is an environment error.
out="$("$RENDER" "$tmp/nope" 2>&1)"
rc=$?
assert_eq "missing bundle: exit 2" "2" "$rc"

if [ "$failures" -ne 0 ]; then
  echo "test-inception-render-stub: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-inception-render-stub: all assertions passed"
