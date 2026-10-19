#!/bin/bash
# Tests for the inception renderer: the dashboard and pitch-narrative exports
# (REQ-G1.1, REQ-G1.2, REQ-G1.3, REQ-C1.7 · D-9).
#
# What is pinned: both modes regenerate deterministically, bundle content is
# escaped everywhere it lands (the dashboard's register detail and the pitch's
# prose alike), mode selection is honored, the dashboard opens with the status
# view REQ-G1.2 names and reflects the fixture registers, and a bundle whose
# format-version this plugin does not support is refused rather than rendered
# (deferring to the validator rather than duplicating the check).
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
# assert_before <label> <first> <second> <haystack> — both present, first
# occurring earlier. Ordering is the property REQ-G1.2 states ("opens with").
assert_before() {
  case "$4" in
    *"$2"*"$3"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected '$2' before '$3')" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_file() {
  if [ -f "$2" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 ($2 was not written)" >&2
    failures=$((failures + 1))
  fi
}
assert_no_file() {
  if [ -e "$2" ]; then
    echo "FAIL: $1 ($2 exists)" >&2
    failures=$((failures + 1))
  else
    echo "ok: $1"
  fi
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
# 1. It renders both exports, to the conventional derived-content paths
#    (REQ-G1.1, REQ-G1.3).
# ---------------------------------------------------------------------------
v="$(fresh)"
out="$("$RENDER" "$v" 2>&1)"
rc=$?
assert_eq "render: exit 0" "0" "$rc"
assert_file "render: writes exports/venture.html" "$v/exports/venture.html"
assert_file "render: writes exports/pitch.html" "$v/exports/pitch.html"
assert_contains "render: reports the dashboard path" "exports/venture.html" "$out"
assert_contains "render: reports the pitch path" "exports/pitch.html" "$out"
html="$(cat "$v/exports/venture.html")"
pitch="$(cat "$v/exports/pitch.html")"

for mode_html in "$html" "$pitch"; do
  assert_contains "render: declares utf-8" 'charset="utf-8"' "$mode_html"
  assert_contains "render: names the venture" "Northwind Signals" "$mode_html"
  assert_contains "render: shows the lifecycle status" "Exploring" "$mode_html"
  # Self-contained: no network fetch, no sidecar asset, no script (REQ-G1.1).
  assert_not_contains "render: no external http reference" "http://" "$mode_html"
  assert_not_contains "render: no external https reference" "https://" "$mode_html"
  assert_not_contains "render: no linked stylesheet" "<link" "$mode_html"
  assert_not_contains "render: no script element" "<script" "$mode_html"
done

# ---------------------------------------------------------------------------
# 2. The dashboard opens with the status view and reflects the registers
#    (REQ-G1.2).
# ---------------------------------------------------------------------------
assert_contains "dashboard: shows the success metric" "ten minutes" "$html"
assert_contains "dashboard: gate readiness" "Gate readiness" "$html"
assert_contains "dashboard: blocking assumptions" "Blocking assumptions" "$html"
assert_contains "dashboard: kill criteria" "Kill criteria" "$html"
assert_contains "dashboard: open forks" "Open forks" "$html"
assert_contains "dashboard: blockers" "Blockers" "$html"
assert_contains "dashboard: lists the blocking assumptions" \
  "A-2</span> the three sinks accept writes from one surface — open, evidence none</li>" "$html"
assert_contains "dashboard: lists the open fork" \
  "DEC-1</span> which handover moment the capture surface owns — open, two-way door</li>" "$html"
assert_contains "dashboard: counts the blocking assumptions" \
  "2 blocking, 2 unresolved" "$html"
# The minimum core is structural (doctrine/inception-format.md, The minimum
# core): enumerated, not resolved. Unresolved blocking assumptions and open
# forks are what stands between the venture and graduation, said separately.
assert_contains "dashboard: the fixture meets the minimum core" \
  "Minimum core is structurally met" "$html"
assert_contains "dashboard: graduation blockers are their own fact" \
  "Graduation is blocked: 2 blocking assumption(s) unresolved." "$html"
assert_contains "dashboard: open forks are counted" "1 open fork(s) still to decide." "$html"
assert_not_contains "dashboard: nothing has tripped at the pinned date" \
  "a kill criterion has tripped" "$html"
assert_contains "dashboard: blockers name the unresolved assumption" \
  "A-1</span> blocking assumption is unresolved" "$html"
assert_contains "dashboard: the approaching criterion is classified" \
  "KC-2</span> — approaching" "$html"
assert_contains "dashboard: the distant criterion is classified" "KC-1</span> — clear" "$html"
assert_contains "dashboard: names the gate decider" "Gate decider: Dana Reyes" "$html"
assert_contains "dashboard: shows the latest gate outcome" \
  "Gate 1 — 2026-08-18 — Recycle" "$html"
assert_before "dashboard: gate readiness leads" "<h2>Gate readiness</h2>" \
  "<h2>Blocking assumptions</h2>" "$html"
assert_before "dashboard: kill criteria precede the open forks" \
  "<h2>Kill criteria</h2>" "<h2>Open forks</h2>" "$html"
assert_before "dashboard: the status view precedes the register detail" \
  "<h2>Blockers</h2>" "<h2>Assumption register</h2>" "$html"

# The register detail below the status view: the whole bundle, live entries.
assert_contains "dashboard detail: assumption statements" \
  "believe ops leads will file once instead of three times" "$html"
assert_contains "dashboard detail: the validation plan" "T-2" "$html"
assert_contains "dashboard detail: the decided decision" "DEC-2" "$html"
assert_contains "dashboard detail: the decision outcome" "reuse the existing relay" "$html"
assert_contains "dashboard detail: decision options as a list" \
  "<li>direct writes to each sink — fewer hops, three integrations to own</li>" "$html"
assert_contains "dashboard detail: the stakeholder map" "integration seam" "$html"
assert_contains "dashboard detail: the staffing table" "Kim Alvarez" "$html"
assert_contains "dashboard detail: a held-out source says so" "held out" "$html"
assert_contains "dashboard detail: code spans render as code" \
  "<code>sources/workflow-audit.md</code>" "$html"
assert_contains "dashboard detail: the gate rationale" \
  "re-scope the plan and return" "$html"
assert_not_contains "dashboard: omits the superseded assumption" "A-3" "$html"
assert_not_contains "dashboard: the decided fork is not listed as open" \
  "existing relay — decided, one-way door" "$html"
assert_not_contains "dashboard: no table separator rows leak" "<td>---</td>" "$html"

# ---------------------------------------------------------------------------
# 3. The pitch narrative (REQ-G1.3): prose order, a status strip first.
# ---------------------------------------------------------------------------
assert_contains "pitch: is labelled as the pitch" "Pitch narrative" "$pitch"
assert_contains "pitch: the problem framing" "re-key the same incident summary" "$pitch"
assert_contains "pitch: who hurts" "closing an incident at end of shift" "$pitch"
assert_contains "pitch: the sketch" "one capture surface that" "$pitch"
assert_contains "pitch: the chain" "handover time drops" "$pitch"
assert_contains "pitch: the success metric" "ten minutes" "$pitch"
assert_contains "pitch: the landscape" "Runbook macros" "$pitch"
assert_contains "pitch: strategy fit" "incident-tooling consolidation" "$pitch"
assert_contains "pitch: a skipped prompt states its reason" \
  "internal tool with no external market" "$pitch"
assert_not_contains "pitch: the skip marker is not shown raw" "_Skipped:" "$pitch"
assert_contains "pitch: what has to be true, from the believe clause" \
  "ops leads will file once instead of three times" "$pitch"
assert_not_contains "pitch: the believe clause stops at verify" \
  "verify with a two-week" "$pitch"
assert_contains "pitch: how we will find out" "two-week shadow run" "$pitch"
assert_contains "pitch: what would stop us" "KC-1" "$pitch"
assert_contains "pitch: open questions" "which handover moment the capture surface owns" "$pitch"
assert_not_contains "pitch: omits the superseded assumption" "chat-first" "$pitch"
assert_contains "pitch: the status strip carries the counts" \
  "Where it stands:</strong> Minimum core is structurally met; the gate decider judges completeness. Graduation is blocked: 2 blocking assumption(s) unresolved. 1 open fork(s) still to decide. Kill criteria: 0 tripped, 1 approaching. Last gate: Gate 1 — 2026-08-18 — Recycle.</p>" "$pitch"
assert_not_contains "pitch: the decided fork is not an open question" "DEC-2" "$pitch"
assert_not_contains "pitch: a non-blocking assumption is not a must-be-true" "A-4" "$pitch"
assert_contains "pitch: non-blocking assumptions are counted" \
  "1 further assumption(s) are tracked without blocking graduation." "$pitch"
assert_before "pitch: the status strip opens the page" "Where it stands" \
  "<h2>The problem</h2>" "$pitch"
assert_before "pitch: the problem precedes what has to be true" \
  "<h2>The problem</h2>" "<h2>What has to be true</h2>" "$pitch"
assert_not_contains "pitch: carries no register detail tables" "<table" "$pitch"

if [ "$html" = "$pitch" ]; then
  echo "FAIL: modes: dashboard and pitch rendered identical pages" >&2
  failures=$((failures + 1))
else
  echo "ok: modes: dashboard and pitch differ"
fi

# ---------------------------------------------------------------------------
# 4. Mode selection is honored (REQ-G1.3).
# ---------------------------------------------------------------------------
both="$(fresh)"
"$RENDER" "$both" >/dev/null 2>&1

v="$(fresh)"
"$RENDER" --mode pitch "$v" >/dev/null 2>&1
rc=$?
assert_eq "mode pitch: exit 0" "0" "$rc"
assert_file "mode pitch: writes the pitch" "$v/exports/pitch.html"
assert_no_file "mode pitch: leaves the dashboard alone" "$v/exports/venture.html"
if cmp -s "$both/exports/pitch.html" "$v/exports/pitch.html"; then
  echo "ok: mode pitch: the same page a both-mode run writes"
else
  echo "FAIL: mode pitch: differs from the both-mode pitch" >&2
  failures=$((failures + 1))
fi

v="$(fresh)"
"$RENDER" --mode dashboard "$v" >/dev/null 2>&1
assert_file "mode dashboard: writes the dashboard" "$v/exports/venture.html"
assert_no_file "mode dashboard: leaves the pitch alone" "$v/exports/pitch.html"
if cmp -s "$both/exports/venture.html" "$v/exports/venture.html"; then
  echo "ok: mode dashboard: the same page a both-mode run writes"
else
  echo "FAIL: mode dashboard: differs from the both-mode dashboard" >&2
  failures=$((failures + 1))
fi

v="$(fresh)"
"$RENDER" --mode pitch --output "$tmp/custom.html" "$v" >/dev/null 2>&1
assert_contains "mode pitch with --output: writes the pitch there" \
  "Pitch narrative" "$(cat "$tmp/custom.html" 2>/dev/null)"
"$RENDER" --mode dashboard --output "$tmp/custom-dash.html" "$v" >/dev/null 2>&1
assert_contains "mode dashboard with --output: writes the dashboard there" \
  "Venture dashboard" "$(cat "$tmp/custom-dash.html" 2>/dev/null)"
assert_no_file "--output: the default paths are left alone" "$v/exports/venture.html"

# A destination that is a directory is refused, never filled with a temp file.
mkdir -p "$tmp/adir"
out="$("$RENDER" --mode pitch --output "$tmp/adir" "$v" 2>&1)"
rc=$?
assert_eq "--output naming a directory: exit 2" "2" "$rc"
leftover="$(find "$tmp/adir" -type f 2>/dev/null)"
assert_eq "--output naming a directory: nothing is written into it" "" "$leftover"
v="$(fresh)"
mkdir -p "$v/exports/pitch.html"
out="$("$RENDER" "$v" 2>&1)"
rc=$?
assert_eq "a directory at a default export path: exit 2" "2" "$rc"
assert_no_file "a directory at a default export path: no page is moved" "$v/exports/venture.html"

out="$("$RENDER" --mode slides "$v" 2>&1)"
rc=$?
assert_eq "unknown mode: exit 2" "2" "$rc"
assert_contains "unknown mode: names the modes" "dashboard" "$out"

# Two pages cannot share one --output path.
out="$("$RENDER" --output "$tmp/both.html" "$v" 2>&1)"
rc=$?
assert_eq "--output without a single mode: exit 2" "2" "$rc"
assert_no_file "--output without a single mode: writes nothing" "$tmp/both.html"

# ---------------------------------------------------------------------------
# 5. Determinism: same bundle, same bytes, in both modes (REQ-G1.1).
# ---------------------------------------------------------------------------
v="$(fresh)"
"$RENDER" "$v" >/dev/null 2>&1
cp "$v/exports/venture.html" "$tmp/first.html"
cp "$v/exports/pitch.html" "$tmp/first-pitch.html"
"$RENDER" "$v" >/dev/null 2>&1
if cmp -s "$tmp/first.html" "$v/exports/venture.html" \
  && cmp -s "$tmp/first-pitch.html" "$v/exports/pitch.html"; then
  echo "ok: render: byte-identical on a repeated run"
else
  echo "FAIL: render: repeated run produced different bytes" >&2
  failures=$((failures + 1))
fi

v="$(fresh tracked)"
"$RENDER" "$v" >/dev/null 2>&1
cp "$v/exports/venture.html" "$tmp/tracked.html"
"$RENDER" "$v" >/dev/null 2>&1
if cmp -s "$tmp/tracked.html" "$v/exports/venture.html"; then
  echo "ok: render: byte-identical on a repeated run (tracked venture)"
else
  echo "FAIL: render: tracked venture rendered different bytes on a repeat" >&2
  failures=$((failures + 1))
fi
assert_contains "tracked venture: lists the declared tracks" \
  "the handover-time measurement pipeline" "$(cat "$v/exports/venture.html")"

# ---------------------------------------------------------------------------
# 6. Escaping: bundle content is data, never markup, in every mode and every
#    place it lands.
# ---------------------------------------------------------------------------
v="$(fresh)"
sed_i "$v/brief.md" 's|^Median incident-handover time drops below ten minutes within one quarter of adoption.$|Cut <script>alert("x")</script> handover \& re-keying time.|'
sed_i "$v/brief.md" 's|^- \*\*Framing:\*\* Ops leads|- **Framing:** <img src=x onerror=alert(1)> Ops leads|'
sed_i "$v/assumptions.md" "s|^- \*\*Risk-if-wrong:\*\* the fan-out saves no time|- **Risk-if-wrong:** it's </td><b>bold</b> the fan-out saves no time|"
sed_i "$v/disciplines.md" 's#^| integration seam | Kim Alvarez |#| <i>integration</i> seam | Kim Alvarez |#'
# shellcheck disable=SC2016 # literal backticks: a markdown code span
sed_i "$v/brief.md" 's|^Runbook macros|`<u>code</u>` and **<s>strong</s>** Runbook macros|'
"$RENDER" "$v" >/dev/null 2>&1
html="$(cat "$v/exports/venture.html")"
pitch="$(cat "$v/exports/pitch.html")"
for mode_html in "$html" "$pitch"; do
  assert_not_contains "escaping: no raw script tag" "<script>" "$mode_html"
  assert_not_contains "escaping: no raw img tag" "<img" "$mode_html"
  assert_contains "escaping: angle brackets escaped" "&lt;script&gt;" "$mode_html"
  assert_contains "escaping: ampersand escaped" "handover &amp; re-keying" "$mode_html"
  assert_contains "escaping: double quote escaped" "&quot;" "$mode_html"
  assert_not_contains "escaping: no raw u tag inside a code span" "<u>" "$mode_html"
  assert_not_contains "escaping: no raw s tag inside a strong span" "<s>" "$mode_html"
done
assert_contains "escaping: the framing is escaped in the pitch" "&lt;img src=x" "$pitch"
assert_contains "escaping: register detail escaped" "&lt;/td&gt;&lt;b&gt;" "$html"
assert_contains "escaping: apostrophe escaped" "it&#39;s" "$html"
assert_not_contains "escaping: no raw b tag from the register" "<b>bold" "$html"
assert_contains "escaping: table cells escaped" "&lt;i&gt;integration&lt;/i&gt;" "$html"
assert_contains "escaping: markup inside a code span is escaped" \
  "<code>&lt;u&gt;code&lt;/u&gt;</code>" "$pitch"

# ---------------------------------------------------------------------------
# 7. Kill-date classification, as a function of the pinned today.
# ---------------------------------------------------------------------------
v="$(fresh)"
PLANWRIGHT_INCEPTION_TODAY=2026-09-20 "$RENDER" "$v" >/dev/null 2>&1
html="$(cat "$v/exports/venture.html")"
assert_contains "kill dates: a past date is tripped" "KC-2</span> — tripped" "$html"
assert_contains "kill dates: a date inside 30 days is approaching" "KC-1</span> — approaching" "$html"
assert_contains "kill dates: a tripped criterion is a blocker" "KC-2</span> kill criterion is tripped" "$html"
assert_contains "kill dates: the pitch says so too" "KC-2</span> — tripped" \
  "$(cat "$v/exports/pitch.html")"

v="$(fresh)"
PLANWRIGHT_INCEPTION_TODAY=2026-01-01 "$RENDER" "$v" >/dev/null 2>&1
html="$(cat "$v/exports/venture.html")"
assert_contains "kill dates: a distant date is clear" "KC-1</span> — clear" "$html"
assert_contains "kill dates: the other distant date is clear" "KC-2</span> — clear" "$html"

# ---------------------------------------------------------------------------
# 8. Version gating: refuse rather than render (REQ-C1.7). The renderer defers
#    to the validator check instead of re-implementing it.
# ---------------------------------------------------------------------------
v="$(fresh)"
"$RENDER" "$v" >/dev/null 2>&1
cp "$v/exports/venture.html" "$tmp/before.html"
cp "$v/exports/pitch.html" "$tmp/before-pitch.html"
for f in brief disciplines assumptions decisions plan; do
  sed_i "$v/$f.md" 's|^\*\*Format-version:\*\* 1\.0$|**Format-version:** 7.0|'
done
out="$("$RENDER" "$v" 2>&1)"
rc=$?
assert_eq "unsupported version: exit 3" "3" "$rc"
assert_contains "unsupported version: plain-language refusal" "unsupported" "$out"
if cmp -s "$tmp/before.html" "$v/exports/venture.html" \
  && cmp -s "$tmp/before-pitch.html" "$v/exports/pitch.html"; then
  echo "ok: unsupported version: the previous exports are left untouched"
else
  echo "FAIL: unsupported version: an export was overwritten anyway" >&2
  failures=$((failures + 1))
fi
out="$("$RENDER" --mode pitch "$v" 2>&1)"
rc=$?
assert_eq "unsupported version, pitch mode: exit 3" "3" "$rc"

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
assert_not_contains "readiness: a met core is not reported as unmet" \
  "Minimum core is not met yet" "$html"
assert_not_contains "readiness: nothing blocks graduation" "Graduation is blocked" "$html"
assert_contains "readiness: zero blocking assumptions counted" "0 blocking, 0 unresolved" "$html"

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

# The exports are what stakeholders read off the forge, so they carry the same
# explicit mode the scaffolded files do rather than whatever the temp file was
# created with.
v="$(fresh)"
"$RENDER" "$v" >/dev/null 2>&1
# `find -perm -044` rather than parsing `ls` or reaching for `stat`, whose flags
# differ between GNU and BSD (REQ-K1.5). The property under test is that the
# export is readable beyond its owner, not its exact octal mode.
readable="$(find "$v/exports" -name '*.html' -perm -044 2>/dev/null | sort | tr '\n' ' ')"
assert_eq "exports: are group- and world-readable" \
  "$v/exports/pitch.html $v/exports/venture.html " "$readable"
leftover="$(find "$v/exports" -name '.*' -type f 2>/dev/null)"
assert_eq "exports: no temp file is left behind" "" "$leftover"

# A missing bundle is an environment error.
out="$("$RENDER" "$tmp/nope" 2>&1)"
rc=$?
assert_eq "missing bundle: exit 2" "2" "$rc"

# A kill date that is well SHAPED but impossible. This renderer runs on bundles
# the validator has not passed (only the version gate precedes it), so it cannot
# defer the calendar to the validator: differencing 2026-02-30 yields a state,
# and "tripped" is the state that tells a venture to kill or re-scope itself.
v="$(fresh)"
sed_i "$v/brief.md" 's|^\(- \*\*KC-1:\*\*.*by \)[0-9-]*$|\12026-02-30|'
PLANWRIGHT_INCEPTION_TODAY=2026-08-26 "$RENDER" "$v" >/dev/null 2>&1
page="$(cat "$v/exports/venture.html")"
assert_contains "impossible date: rendered as unreadable, not classified" \
  "date unreadable" "$page"
assert_not_contains "impossible date: never reported as tripped" \
  "KC-1</span> — tripped" "$page"
assert_contains "impossible date: surfaced as a blocker" \
  "has no readable date" "$page"

# The calendar check must not swallow real dates. A past one still trips, and a
# genuine leap day is a genuine date.
v="$(fresh)"
sed_i "$v/brief.md" 's|^\(- \*\*KC-1:\*\*.*by \)[0-9-]*$|\12026-02-28|'
PLANWRIGHT_INCEPTION_TODAY=2026-08-26 "$RENDER" "$v" >/dev/null 2>&1
assert_contains "real past date: still trips" \
  "KC-1</span> — tripped" "$(cat "$v/exports/venture.html")"

v="$(fresh)"
sed_i "$v/brief.md" 's|^\(- \*\*KC-1:\*\*.*by \)[0-9-]*$|\12028-02-29|'
PLANWRIGHT_INCEPTION_TODAY=2026-08-26 "$RENDER" "$v" >/dev/null 2>&1
assert_not_contains "leap day 2028-02-29: is a real date, not unreadable" \
  "date unreadable" "$(cat "$v/exports/venture.html")"

# ---------------------------------------------------------------------------
# 9. Register edge cases the dashboard and pitch must reflect (REQ-G1.2).
# ---------------------------------------------------------------------------

# A missing kill criterion is a minimum-core gap.
v="$(fresh)"
sed_i "$v/brief.md" '/^- \*\*KC-[12]:\*\*/d'
"$RENDER" "$v" >/dev/null 2>&1
html="$(cat "$v/exports/venture.html")"
assert_contains "core: no kill criterion means the core is unmet" \
  "Minimum core is not met yet" "$html"
assert_contains "core: the missing criterion is a blocker" \
  "no kill criterion is set (minimum core)" "$html"

# A resolved blocking assumption still counts as blocking, not as unresolved.
v="$(fresh)"
sed_i "$v/assumptions.md" 's|^- \*\*Status:\*\* testing$|- **Status:** validated|'
"$RENDER" --mode dashboard "$v" >/dev/null 2>&1
html="$(cat "$v/exports/venture.html")"
assert_contains "resolved blocking: counted once" "2 blocking, 1 unresolved" "$html"
assert_not_contains "resolved blocking: not a blocker" \
  "A-1</span> blocking assumption is unresolved" "$html"

# A deferred decision is still an open fork (un-taken, per the frame).
v="$(fresh)"
sed_i "$v/decisions.md" 's|^- \*\*Status:\*\* open$|- **Status:** deferred|'
"$RENDER" --mode dashboard "$v" >/dev/null 2>&1
assert_contains "deferred fork: still listed as open" \
  "DEC-1</span> which handover moment the capture surface owns — deferred, two-way door" \
  "$(cat "$v/exports/venture.html")"

# The approaching window: due today and 30 days out approach, 31 days out is clear.
for case in "2026-09-15 approaching" "2026-08-16 approaching" "2026-08-15 clear"; do
  d=${case% *}
  want=${case#* }
  v="$(fresh)"
  PLANWRIGHT_INCEPTION_TODAY=$d "$RENDER" --mode dashboard "$v" >/dev/null 2>&1
  assert_contains "kill-date window: KC-2 on $d is $want" "KC-2</span> — $want" \
    "$(cat "$v/exports/venture.html")"
done

# A pitch whose every task is superseded says so rather than listing nothing.
v="$(fresh)"
for st in planned running; do
  sed_i "$v/plan.md" "s|^- \\*\\*Status:\\*\\* $st\$|- **Status:** $st\\
- **Superseded-by:** T-9 (2026-08-20)|"
done
"$RENDER" --mode pitch "$v" >/dev/null 2>&1
assert_contains "pitch: no live task says so" "No validation task is planned yet." \
  "$(cat "$v/exports/pitch.html")"

# A skipped Opportunity field shows its reason on the dashboard, not the marker.
v="$(fresh)"
sed_i "$v/brief.md" 's|^- \*\*Who hurts:\*\* .*$|- **Who hurts:** _Skipped: covered by the portfolio brief._|'
"$RENDER" --mode dashboard "$v" >/dev/null 2>&1
html="$(cat "$v/exports/venture.html")"
assert_contains "dashboard: a skipped field states its reason" "covered by the portfolio brief" "$html"
assert_not_contains "dashboard: the skip marker is not shown raw" "_Skipped:" "$html"

# A continuation indented deeper than two spaces still belongs to its field.
v="$(fresh)"
sed_i "$v/decisions.md" 's|^  - end-of-shift handover only — narrowest surface, clearest metric$|  - end-of-shift handover only — narrowest surface,\
    clearest metric|'
"$RENDER" --mode dashboard "$v" >/dev/null 2>&1
assert_contains "deep continuation: joins its sub-bullet" \
  "<li>end-of-shift handover only — narrowest surface, clearest metric</li>" \
  "$(cat "$v/exports/venture.html")"

# A criterion whose text itself says "— by" keeps all of it.
v="$(fresh)"
sed_i "$v/brief.md" 's|^- \*\*KC-1:\*\* three ops leads|- **KC-1:** sign-off — by the ops team, and three ops leads|'
"$RENDER" --mode dashboard "$v" >/dev/null 2>&1
assert_contains "kill criterion: an inner — by stays in the text" \
  "KC-1</span> — clear — by 2026-10-01 — sign-off — by the ops team, and three ops leads" \
  "$(cat "$v/exports/venture.html")"

# The rationale runs to the end of the block: a later line shaped like a field
# is rationale text, not a replacement for that field.
v="$(fresh)"
sed_i "$v/brief.md" 's|^Rationale: The capture-surface spike has not run yet; re-scope the plan and return.$|Rationale: The capture-surface spike has not run yet;\
Outcome: Kill was argued for and rejected.\
Evidence: re-read at the meeting.|'
"$RENDER" --mode dashboard "$v" >/dev/null 2>&1
html="$(cat "$v/exports/venture.html")"
assert_contains "gate rationale: a field-shaped line stays rationale" \
  "Evidence: re-read at the meeting." "$html"
assert_contains "gate rationale: the real outcome survives" "Gate 1 — 2026-08-18 — Recycle" "$html"
assert_contains "gate rationale: the real evidence survives" "A-1 (stated-intent)" "$html"

# Date: is authoritative over the heading date.
v="$(fresh)"
sed_i "$v/brief.md" 's|^Date: 2026-08-18$|Date: 2026-08-19|'
"$RENDER" --mode dashboard "$v" >/dev/null 2>&1
assert_contains "gate date: the Date: field wins" "Last gate: Gate 1 — 2026-08-19 — Recycle." \
  "$(cat "$v/exports/venture.html")"

# Escaping reaches every place bundle text lands, not only the prose.
v="$(fresh)"
sed_i "$v/brief.md" 's|^# Northwind Signals — Brief$|# North<b1>wind — Brief|'
sed_i "$v/brief.md" 's|^\*\*Gate decider:\*\* Dana Reyes$|**Gate decider:** Dana <b2>|'
sed_i "$v/brief.md" 's|^\(- \*\*KC-1:\*\*\) three ops leads|\1 <b3> three ops leads|'
sed_i "$v/brief.md" 's|re-scope the plan and return|re-scope <b4> and return|'
sed_i "$v/brief.md" 's|^- \*\*workflow audit\*\*|- **workflow <b5> audit**|'
sed_i "$v/decisions.md" 's|^  - every incident close|  - every <b6> incident close|'
sed_i "$v/decisions.md" 's|^### DEC-1 — which handover|### DEC-1 — which <b7> handover|'
"$RENDER" "$v" >/dev/null 2>&1
both_pages="$(cat "$v/exports/venture.html" "$v/exports/pitch.html")"
for n in 1 2 3 4 5 6 7; do
  assert_not_contains "escaping breadth: raw <b$n> never lands" "<b$n>" "$both_pages"
done
assert_contains "escaping breadth: the title is escaped" "North&lt;b1&gt;wind" "$both_pages"
assert_contains "escaping breadth: an entry name is escaped" "which &lt;b7&gt; handover" "$both_pages"

# --- invocation edges ---

# A relative venture path shaped like an awk assignment is still a path.
v="$(fresh)"
mkdir -p "$tmp/rel" && cp "$v"/*.md "$tmp/rel/" && mv "$tmp/rel" "$tmp/v=1"
(cd "$tmp" && "$RENDER" --mode dashboard "v=1") >/dev/null 2>&1
assert_contains "relative path with =: the bundle is read" "Northwind Signals" \
  "$(cat "$tmp/v=1/exports/venture.html" 2>/dev/null)"

# A calendar-impossible today is refused, never differenced.
v="$(fresh)"
out="$(PLANWRIGHT_INCEPTION_TODAY=2026-13-40 "$RENDER" "$v" 2>&1)"
rc=$?
assert_eq "impossible today: exit 2" "2" "$rc"
assert_no_file "impossible today: nothing is written" "$v/exports/venture.html"

# A symlink in the bundle is refused: a pushed link at exports/ would redirect
# the pages outside the repo, and one at a bundle file would pull outside
# content into a page that may be published.
v="$(fresh)"
mkdir -p "$tmp/outside-exports"
ln -s "$tmp/outside-exports" "$v/exports"
out="$("$RENDER" "$v" 2>&1)"
rc=$?
assert_eq "symlinked exports/: exit 2" "2" "$rc"
assert_contains "symlinked exports/: says why" "symbolic link" "$out"
leftover="$(find "$tmp/outside-exports" -type f 2>/dev/null)"
assert_eq "symlinked exports/: nothing is written through it" "" "$leftover"

v="$(fresh)"
printf '| leaked | from | outside |\n' >"$tmp/outside-notes.md"
mv "$v/disciplines.md" "$tmp/real-disciplines.md"
cat "$tmp/real-disciplines.md" "$tmp/outside-notes.md" >"$tmp/linked-disciplines.md"
ln -s "$tmp/linked-disciplines.md" "$v/disciplines.md"
out="$("$RENDER" "$v" 2>&1)"
rc=$?
assert_eq "symlinked bundle file: exit 2" "2" "$rc"
assert_no_file "symlinked bundle file: no page is written" "$v/exports/venture.html"

# A success metric written over two paragraphs shows both on the dashboard.
v="$(fresh)"
sed_i "$v/brief.md" 's|^Median incident-handover time drops below ten minutes within one quarter of adoption.$|&\
\
Measured from the incident-close event to the handover report.|'
"$RENDER" --mode dashboard "$v" >/dev/null 2>&1
assert_contains "dashboard: a second metric paragraph is kept" \
  "Measured from the incident-close event" "$(cat "$v/exports/venture.html")"

# An unknown section is ignored, per the format's additive-within-major rule,
# even one in disciplines.md that carries pipe rows.
v="$(fresh)"
printf '\n## Vendor shortlist\n\n| Vendor | Note |\n| --- | --- |\n| UNKNOWN-SECTION-ROW | x |\n' >>"$v/disciplines.md"
"$RENDER" --mode dashboard "$v" >/dev/null 2>&1
assert_not_contains "unknown section: its table is not rendered" "UNKNOWN-SECTION-ROW" \
  "$(cat "$v/exports/venture.html")"

# A kill criterion counts toward the minimum core only as a state-plus-date
# pair: one whose date is unreadable does not.
v="$(fresh)"
sed_i "$v/brief.md" 's|^\(- \*\*KC-[12]:\*\* .*\) — by .*$|\1|'
"$RENDER" --mode dashboard "$v" >/dev/null 2>&1
assert_contains "undated criteria only: the core is not met" "Minimum core is not met yet" \
  "$(cat "$v/exports/venture.html")"

# ---------------------------------------------------------------------------
# 10. The in-session status view (REQ-J1.4): the dashboard's classification as
#     key<TAB>value lines on stdout, writing no export.
# ---------------------------------------------------------------------------
v="$(fresh)"
out="$("$RENDER" --mode status "$v" 2>/dev/null)"
rc=$?
assert_eq "status: exit 0" "0" "$rc"
assert_no_file "status: writes no dashboard" "$v/exports/venture.html"
assert_no_file "status: writes no pitch" "$v/exports/pitch.html"
assert_contains "status: lifecycle status" "$(printf 'status\tExploring')" "$out"
assert_contains "status: gate readiness (core)" "$(printf 'core\tmet')" "$out"
assert_contains "status: blocking counts" "$(printf 'blocking\t2\t2')" "$out"
assert_contains "status: unresolved blocker A-1" "$(printf 'unresolved\tA-1\ttesting')" "$out"
assert_contains "status: unresolved blocker A-2" "$(printf 'unresolved\tA-2\topen')" "$out"
assert_contains "status: clear kill date" "$(printf 'kill\tKC-1\t2026-10-01\tclear')" "$out"
assert_contains "status: approaching kill date" "$(printf 'kill\tKC-2\t2026-09-15\tapproaching')" "$out"
assert_contains "status: open fork" "$(printf 'fork\tDEC-1\topen\ttwo-way')" "$out"
assert_not_contains "status: a decided fork is not a blocker" "$(printf 'fork\tDEC-2')" "$out"
assert_contains "status: last gate" "$(printf 'gate\t1\t2026-08-18\tRecycle')" "$out"
assert_contains "status: venture start from the changelog" "$(printf 'started\t2026-08-01')" "$out"
assert_contains "status: skipped appetite" "$(printf 'appetite\tskipped')" "$out"

PLANWRIGHT_INCEPTION_TODAY=2026-10-02 out="$("$RENDER" --mode status "$v" 2>/dev/null)"
assert_contains "status: a passed date trips" "$(printf 'kill\tKC-1\t2026-10-01\ttripped')" "$out"

v="$(fresh)"
sed_i "$v/brief.md" 's|^_Skipped: appetite is set at the portfolio level.*$|Six weeks of one engineer, then the gate decides. Budget 6 weeks.|'
out="$("$RENDER" --mode status "$v" 2>/dev/null)"
assert_contains "status: appetite in weeks becomes days" "$(printf 'appetite\t42')" "$out"
sed_i "$v/brief.md" 's|^Six weeks of one engineer.*$|Whatever it takes.|'
out="$("$RENDER" --mode status "$v" 2>/dev/null)"
assert_contains "status: unreadable appetite" "$(printf 'appetite\tunparsed')" "$out"

# Values are bundle content headed for a terminal: no control byte and no tab
# inside a field survives.
v="$(fresh)"
sed_i "$v/brief.md" "s|^Outcome: Recycle\$|Outcome: Recycle$(printf '\033')[31m|"
out="$("$RENDER" --mode status "$v" 2>/dev/null)"
assert_not_contains "status: escape bytes are stripped" "$(printf '\033')" "$out"
assert_contains "status: the stripped value still lands" "$(printf 'gate\t1\t2026-08-18\tRecycle[31m')" "$out"

v="$(fresh)"
assert_eq "status: --output is refused" "2" \
  "$("$RENDER" --mode status --output "$tmp/x" "$v" >/dev/null 2>&1; echo $?)"

if [ "$failures" -ne 0 ]; then
  echo "test-inception-render: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-inception-render: all assertions passed"
