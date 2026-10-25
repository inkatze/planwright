#!/bin/bash
# Tests for the inception gate and graduation helper (inception Task 11;
# REQ-E1.1–E1.6, REQ-F1.1, REQ-F1.3, REQ-J1.1, REQ-J1.5 · D-14, D-15).
#
# scripts/inception-gate.sh is the mechanical half of the gate move: it
# evaluates the minimum core and the completeness check, surfaces kill
# criteria, writes the structured gate record and the status it implies,
# packages a graduated scope as a /spec-draft seed with its lineage, and
# archives a killed or abandoned venture. The outcome itself is always the
# caller's (the named decider's); nothing here picks one.
#
# REQ-E1.6 and REQ-F1.3 are Gherkin entries in test-spec.md; their scenarios
# run here end to end. REQ-F1.2 (the human picks the destination) and
# REQ-F1.4 (holes routed back) are [manual] dogfood entries.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$REPO_ROOT/scripts/inception-gate.sh"
VALIDATE="$REPO_ROOT/scripts/inception-validate.sh"
REG="$REPO_ROOT/scripts/inception-registry.sh"
RESOLVE_ROOT="$REPO_ROOT/scripts/resolve-root.sh"
SKILL="$REPO_ROOT/skills/inception/SKILL.md"
SPEC_DRAFT="$REPO_ROOT/skills/spec-draft/SKILL.md"
FORMAT_DOC="$REPO_ROOT/doctrine/inception-format.md"

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
      echo "FAIL: $1 (expected to find '$2' in: $3)" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (did not expect '$2' in: $3)" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -x "$GATE" ]; then
  echo "FAIL: $GATE is missing or not executable" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
export PLANWRIGHT_ROOT="$REPO_ROOT"
export PLANWRIGHT_INCEPTION_TODAY=2026-10-18
core_cfg="$tmp/core-defaults.yml"
printf 'ventures_root: ~/ventures\n' >"$core_cfg"
export PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg"
export PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter"
export PLANWRIGHT_REPO_ROOT=none
export PLANWRIGHT_LOCAL_CONFIG=""
unset CLAUDE_PLUGIN_DATA
export PLANWRIGHT_INCEPTION_DATA_DIR="$tmp/data"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

vroot="$HOME/ventures"
mkdir -p "$vroot"

# gate <args...> — run the helper; sets out (stdout+stderr) and rc.
gate() {
  out=$("$GATE" "$@" 2>&1)
  rc=$?
}

# specroot <dir> — the spec root /spec-draft would use in <dir>, the way the
# skill resolves a seed's destination.
specroot() { (unset PLANWRIGHT_REPO_ROOT && cd "$1" && "$RESOLVE_ROOT" spec --primary 2>/dev/null); }

# mkv <name> [tracked] — a fresh fixture venture under the ventures root.
mkv() {
  rm -rf "${vroot:?}/$1"
  inception_fixture_write "$vroot/$1" "${2:-untracked}" || exit 1
  git -C "$vroot/$1" init -q || exit 1
}

# set_field <file> <id> <field> <value> — rewrite one register field bullet.
set_field() {
  awk -v id="$2" -v f="$3" -v v="$4" '
    /^#/ { in_e = ($0 ~ /^### / && $2 == id); skip = 0; print; next }
    in_e && index($0, "- **" f ":**") == 1 { print "- **" f ":** " v; skip = 1; next }
    in_e && skip && /^  / { next }
    { skip = 0; print }
  ' "$1" >"$1.new" && mv "$1.new" "$1"
}

# ready <dir> — resolve both blocking assumptions with real-world evidence.
ready() {
  set_field "$1/assumptions.md" A-1 Status validated
  set_field "$1/assumptions.md" A-1 Evidence "behavior — T-1 findings"
  set_field "$1/assumptions.md" A-2 Status validated
  set_field "$1/assumptions.md" A-2 Threshold "all three sinks accept a canned write"
  set_field "$1/assumptions.md" A-2 Evidence "costly-signal — workflow audit"
}

validates_clean() {
  "$VALIDATE" "$1" >/dev/null 2>&1
  printf '%s' "$?"
}

status_of() { awk '/^\*\*Status:\*\* / { print $2; exit }' "$1/$2"; }

# --- REQ-E1.1 minimum-core evaluation ---------------------------------------

mkv base
gate evaluate "$vroot/base"
assert_eq "E1.1 evaluate exits 0" 0 "$rc"
assert_contains "E1.1 an unresolved blocking assumption is a gap" "gap	blocking-unresolved	A-1	testing" "$out"
assert_contains "E1.1 an open blocking assumption is a gap" "gap	blocking-unresolved	A-2	open" "$out"
assert_contains "E1.1 the core reads unmet" "core	unmet" "$out"
assert_contains "E1.1 Graduate is not admissible" "admissible	Graduate	no" "$out"
assert_contains "E1.1 Recycle stays admissible" "admissible	Recycle	yes" "$out"
assert_contains "E1.1 an open two-way fork is listed for the decider" "fork	DEC-1	open	two-way" "$out"
assert_contains "E1.1 the decider is named" "decider	Dana Reyes" "$out"
assert_contains "E1.1 the next gate number" "next-gate	2" "$out"

mkv ready
ready "$vroot/ready"
gate evaluate "$vroot/ready"
assert_contains "E1.1 resolved blocking assumptions meet the core" "core	met" "$out"
assert_contains "E1.1 Graduate is admissible once the core is met" "admissible	Graduate	yes" "$out"
assert_not_contains "E1.1 no gap remains" "gap	" "$out"
assert_contains "E1.1 drafted evidence line" "evidence	A-1 (behavior), A-2 (costly-signal)" "$out"
assert_contains "E1.1 drafted thresholds line" "thresholds	A-1 pass, A-2 pass" "$out"

mkv waived
ready "$vroot/waived"
set_field "$vroot/waived/assumptions.md" A-2 Status "waived — the relay already writes to all three sinks"
set_field "$vroot/waived/assumptions.md" A-2 Evidence none
set_field "$vroot/waived/assumptions.md" A-2 Threshold none
gate evaluate "$vroot/waived"
assert_contains "E1.1 waived-with-reason passes" "admissible	Graduate	yes" "$out"
assert_contains "E1.1 a waived blocking assumption reads waived" "thresholds	A-1 pass, A-2 waived" "$out"

mkv nometric
ready "$vroot/nometric"
awk 'BEGIN { s = 0 } /^## Success metric/ { print; print ""; print "_Pending: not yet elicited._"; print ""; s = 1; next } /^## / { s = 0 } !s { print }' \
  "$vroot/nometric/brief.md" >"$tmp/b" && mv "$tmp/b" "$vroot/nometric/brief.md"
gate evaluate "$vroot/nometric"
assert_contains "E1.1 a missing metric is a gap" "gap	metric-missing" "$out"
assert_contains "E1.1 a missing metric blocks Graduate" "admissible	Graduate	no" "$out"

mkv nokc
ready "$vroot/nokc"
grep -v '^- \*\*KC-' "$vroot/nokc/brief.md" >"$tmp/b" && mv "$tmp/b" "$vroot/nokc/brief.md"
gate evaluate "$vroot/nokc"
assert_contains "E1.1 missing kill criteria are a gap" "gap	kill-criteria-missing" "$out"
assert_contains "E1.1 missing kill criteria block Graduate" "admissible	Graduate	no" "$out"

mkv synth
ready "$vroot/synth"
set_field "$vroot/synth/assumptions.md" A-1 Evidence "synthetic — T-1 findings"
gate evaluate "$vroot/synth"
assert_contains "E1.1 synthetic evidence on a desirability assumption is a gap" "gap	synthetic-desirability	A-1" "$out"
assert_contains "E1.1 synthetic desirability blocks Graduate" "admissible	Graduate	no" "$out"
gate record --outcome Graduate --decider "Dana Reyes" --rationale "ship it" "$vroot/synth"
assert_eq "E1.1 record refuses an inadmissible Graduate" 1 "$rc"
assert_contains "E1.1 the refusal names the gap" "synthetic-desirability" "$out"
assert_eq "E1.1 a refused record writes nothing" Exploring "$(status_of "$vroot/synth" brief.md)"

mkv oneway
ready "$vroot/oneway"
set_field "$vroot/oneway/decisions.md" DEC-1 Door one-way
gate evaluate "$vroot/oneway"
assert_contains "E1.1 an open one-way door is a gap" "gap	fork-open-one-way	DEC-1" "$out"

# --- REQ-E1.2 four outcomes -------------------------------------------------

for pair in Graduate:Graduated Hold:On-hold Recycle:Exploring Kill:Killed; do
  o=${pair%%:*}
  s=${pair#*:}
  v="out-$(printf '%s' "$o" | tr '[:upper:]' '[:lower:]')"
  mkv "$v"
  ready "$vroot/$v"
  gate record --outcome "$o" --decider "Dana Reyes" --rationale "the $o call, with its reason" "$vroot/$v"
  assert_eq "E1.2 $o records" 0 "$rc"
  assert_contains "E1.2 $o prints the record" "recorded	2	$o" "$out"
  assert_eq "E1.2 $o sets the status" "$s" "$(status_of "$vroot/$v" brief.md)"
  if [ "$s" = Exploring ]; then
    assert_not_contains "E1.2 $o reports no status change" "status	" "$out"
  else
    assert_contains "E1.2 $o reports the status change" "status	Exploring	$s" "$out"
  fi
  assert_eq "E1.2 $o mirrors the status" "$s" "$(status_of "$vroot/$v" plan.md)"
  assert_eq "E1.2 $o leaves a clean bundle" 0 "$(validates_clean "$vroot/$v")"
  assert_eq "E1.2 $o rationale is recorded" 1 "$(grep -c "^Rationale: the $o call, with its reason$" "$vroot/$v/brief.md")"
  assert_eq "E1.2 $o changelog entry" 1 "$(grep -c "^- 2026-10-18 — Gate 2 recorded ($o)\.$" "$vroot/$v/brief.md")"
done

mkv bad
gate record --outcome Pause --decider "Dana Reyes" --rationale "x" "$vroot/bad"
assert_eq "E1.2 an outcome off the four is refused" 2 "$rc"
gate record --outcome Recycle --decider "Kim Alvarez" --rationale "x" "$vroot/bad"
assert_eq "E1.2 a decider other than the gate decider is refused" 1 "$rc"
assert_contains "E1.2 the refusal names the gate decider" "Dana Reyes" "$out"
gate record --outcome Recycle --decider "Dana Reyes" "$vroot/bad"
assert_eq "E1.2 a record without a rationale is refused" 2 "$rc"
assert_eq "E1.2 refused records write nothing" 0 "$(grep -c '^### Gate 2' "$vroot/bad/brief.md")"
gate record --outcome Kill --decider "Dana Reyes" --rationale "no value story" "$vroot/out-kill"
assert_eq "E1.2 a closed venture takes no further gate record" 1 "$rc"

mkv fenced
awk '{ print } /^Rides the incident-tooling consolidation/ { print ""; print "```markdown"; print "## Gate log"; print ""; print "## Changelog"; print "```" }' \
  "$vroot/fenced/brief.md" >"$tmp/b" && mv "$tmp/b" "$vroot/fenced/brief.md"
gate record --outcome Hold --decider "Dana Reyes" --rationale "waiting on budget" "$vroot/fenced"
assert_eq "E1.2 a fenced example heading does not redirect the record" 0 "$rc"
assert_eq "E1.2 the fenced example is left untouched" 0 \
  "$(awk '/^```markdown/ { on = 1; next } /^```/ { on = 0 } on && /Gate 2|Hold/' "$vroot/fenced/brief.md" | wc -l | tr -d ' ')"
assert_eq "E1.2 the record lands in the real gate log" 0 "$(validates_clean "$vroot/fenced")"

# --- REQ-E1.3 kill-criteria checking ----------------------------------------

gate evaluate "$vroot/base"
assert_contains "E1.3 a passed date reads tripped" "kill	KC-1	2026-10-01	tripped" "$out"
assert_contains "E1.3 a tripped criterion surfaces the kill-or-re-scope prompt" "prompt	kill-or-rescope	KC-1" "$out"
mkv trip
gate record --outcome Recycle --decider "Dana Reyes" --rationale "re-scoping the dates" "$vroot/trip"
assert_eq "E1.3 a tripped criterion does not force Kill" 0 "$rc"
assert_eq "E1.3 nothing auto-kills" Exploring "$(status_of "$vroot/trip" brief.md)"
assert_eq "E1.3 the record carries the tripped state" 1 "$(grep -c '^Kill-criteria: KC-1 tripped, KC-2 tripped$' "$vroot/trip/brief.md")"
PLANWRIGHT_INCEPTION_TODAY=2026-09-01 gate evaluate "$vroot/base"
assert_contains "E1.3 a date within thirty days reads approaching" "kill	KC-2	2026-09-15	approaching" "$out"
assert_not_contains "E1.3 an approaching criterion is not a kill prompt" "prompt	kill-or-rescope	KC-2" "$out"

# --- REQ-E1.4 completeness check --------------------------------------------

gate evaluate "$vroot/base"
assert_contains "E1.4 the fixture mapping is complete" "complete	yes" "$out"

mkv unmapped
ready "$vroot/unmapped"
set_field "$vroot/unmapped/assumptions.md" A-2 Tasks none
set_field "$vroot/unmapped/plan.md" T-2 Tests A-1
gate evaluate "$vroot/unmapped"
assert_contains "E1.4 an unmapped blocking assumption fails" "unmapped	A-2" "$out"
assert_contains "E1.4 the check reads incomplete" "complete	no" "$out"
assert_contains "E1.4 incompleteness blocks Graduate" "admissible	Graduate	no" "$out"

mkv dropped
set_field "$vroot/dropped/plan.md" T-2 Status dropped
gate evaluate "$vroot/dropped"
assert_contains "E1.4 a dropped task maps nothing" "unmapped	A-2" "$out"

mkv orphan
cat >>"$vroot/orphan/plan.md" <<'EOF'

### T-4 — chat preference survey

- **Kind:** research
- **Tests:** A-3
- **Done when:** five ops leads have named a preferred capture channel
- **Cap:** one afternoon
- **Status:** planned
EOF
gate evaluate "$vroot/orphan"
assert_contains "E1.4 a task tracing only to a superseded entry is an orphan" "orphan	T-4" "$out"
assert_contains "E1.4 an orphan makes the check incomplete" "complete	no" "$out"

# --- REQ-E1.5 gate records --------------------------------------------------

rec=$(awk '/^### Gate 2/ { on = 1 } on && /^## / { exit } on { print }' "$vroot/out-graduate/brief.md")
assert_contains "E1.5 heading and date" "### Gate 2 — 2026-10-18" "$rec"
assert_contains "E1.5 outcome" "Outcome: Graduate" "$rec"
assert_contains "E1.5 date line" "Date: 2026-10-18" "$rec"
assert_contains "E1.5 decider" "Decider: Dana Reyes" "$rec"
assert_contains "E1.5 evidence cited" "Evidence: A-1 (behavior), A-2 (costly-signal)" "$rec"
assert_contains "E1.5 thresholds evaluated" "Thresholds: A-1 pass, A-2 pass" "$rec"
assert_contains "E1.5 kill-criteria states" "Kill-criteria: KC-1 tripped, KC-2 tripped" "$rec"
mkv broken
ready "$vroot/broken"
"$GATE" record --outcome Hold --decider "Dana Reyes" --rationale "waiting on budget" "$vroot/broken" >/dev/null 2>&1
grep -v '^Thresholds: ' "$vroot/broken/brief.md" >"$tmp/b" && mv "$tmp/b" "$vroot/broken/brief.md"
vout=$("$VALIDATE" "$vroot/broken" 2>&1)
assert_contains "E1.5 a record missing a field is flagged" "GATE-FIELD-MISSING" "$vout"

# --- REQ-E1.6 kill/abandon archival (Gherkin) --------------------------------
# Scenario: Kill outcome -> archive with post-mortem note, registry updated,
# observation recorded.

"$REG" add out-kill "$vroot/out-kill" >/dev/null 2>&1
gate archive --note "the shadow run showed no time saved" "$vroot/out-kill"
assert_eq "E1.6 archive exits 0" 0 "$rc"
assert_contains "E1.6 the archive is reported" "archived	Killed" "$out"
assert_eq "E1.6 the post-mortem lands in the changelog" 1 \
  "$(grep -c '^- 2026-10-18 — post-mortem: the shadow run showed no time saved$' "$vroot/out-kill/brief.md")"
assert_eq "E1.6 the archived bundle validates" 0 "$(validates_clean "$vroot/out-kill")"
assert_contains "E1.6 the registry is refreshed" "registry	refreshed" "$out"
row=$("$REG" get out-kill 2>&1)
assert_contains "E1.6 the registry row reads Killed" "	Killed	" "$row"
assert_contains "E1.6 the observation is recorded" "observation	dropped" "$out"
drop=$("$REG" drop-read 2>&1)
assert_contains "E1.6 the drop carries the post-mortem" "the shadow run showed no time saved" "$drop"
gate archive --note "again" "$vroot/out-kill"
assert_eq "E1.6 a second post-mortem is refused" 1 "$rc"

mkv live
gate archive --note "never mind" "$vroot/live"
assert_eq "E1.6 a live venture is not archived without a declaration" 1 "$rc"
gate archive --abandon --note "the team moved to other work" "$vroot/live"
assert_eq "E1.6 abandon exits 0" 0 "$rc"
assert_eq "E1.6 abandon sets Abandoned" Abandoned "$(status_of "$vroot/live" brief.md)"
assert_eq "E1.6 abandon mirrors the status" Abandoned "$(status_of "$vroot/live" decisions.md)"
assert_eq "E1.6 abandon is a changelog status change" 1 \
  "$(grep -c '^- 2026-10-18 — status Exploring → Abandoned (operator declaration)\.$' "$vroot/live/brief.md")"
assert_eq "E1.6 the abandoned bundle validates" 0 "$(validates_clean "$vroot/live")"
assert_contains "E1.6 the abandoned venture's registry row reads Abandoned" "	Abandoned	" "$("$REG" get live 2>&1)"
mkv nodata
out=$(
  unset PLANWRIGHT_INCEPTION_DATA_DIR
  "$GATE" archive --abandon --note "paused for good" "$vroot/nodata" 2>&1
)
rc=$?
assert_eq "E1.6 an unavailable registry does not undo the archive" 0 "$rc"
assert_contains "E1.6 the registry step degrades with a notice" "degraded	" "$out"
assert_eq "E1.6 the archive stands without the registry" Abandoned "$(status_of "$vroot/nodata" brief.md)"

# --- REQ-F1.1 seed package shape --------------------------------------------

gate seed --dest "$tmp/early-dest" "$vroot/base"
assert_eq "F1.1 an ungraduated venture yields no seed" 1 "$rc"

g="$vroot/out-graduate"
esc=$(printf '\033')
set_field "$g/decisions.md" DEC-2 Consequences "one integration to own ${esc}[31mand relay latency"
gate seed --dest "$(specroot "$g")" "$g"
assert_eq "F1.1 seed exits 0" 0 "$rc"
seedf="$g/specs/_pending/inception-out-graduate.md"
assert_contains "F1.1 the seed path is printed" "seed	$seedf" "$out"
seed=$(cat "$seedf" 2>/dev/null)
assert_contains "F1.1 the lineage key" "**Lineage:** inception:out-graduate" "$seed"
assert_contains "F1.1 brief extract: framing" "Ops leads re-key the same incident summary" "$seed"
assert_contains "F1.1 brief extract: success metric" "Median incident-handover time drops below ten minutes" "$seed"
assert_contains "F1.1 decided fork" "### DEC-2 — fan-out seam" "$seed"
assert_contains "F1.1 decided fork keeps its alternatives" "direct writes to each sink — fewer hops" "$seed"
assert_contains "F1.1 decided fork keeps the chosen option" "reuse the existing relay (2026-08-12)" "$seed"
assert_contains "F1.1 graded evidence" "behavior — T-1 findings" "$seed"
assert_contains "F1.1 validated assumption" "### A-2 — the three sinks accept writes from one surface" "$seed"
assert_contains "F1.1 open question from an open fork" "DEC-1 (open)" "$seed"
assert_contains "F1.1 citations: the sources register" "**workflow audit**" "$seed"
assert_contains "F1.1 citations: held-out material stays held out" "held out: the notes name individuals" "$seed"
assert_not_contains "F1.1 superseded entries are lineage, not seed" "chat-first capture surface" "$seed"
assert_not_contains "F1.1 bundle text loses its control characters" "$esc" "$seed"
assert_contains "F1.1 and keeps the text around them" "one integration to own [31mand relay latency" "$seed"
gate seed --dest "$(specroot "$g")" "$g"
assert_eq "F1.1 a scope is seeded once" 1 "$rc"

# --- REQ-J1.5 bidirectional lineage ------------------------------------------

# shellcheck disable=SC2016 # literal backticks in the expected line, not an expansion
assert_eq "J1.5 the venture side records the seed" 1 \
  "$(grep -c '^- \*\*venture\*\* — Gate 2 — seed: `specs/_pending/inception-out-graduate.md` — spec: pending$' "$g/brief.md")"
assert_eq "J1.5 the bundle with lineage validates" 0 "$(validates_clean "$g")"
gate lineage "$g"
assert_eq "J1.5 a pending spec is not a finding" 0 "$rc"
assert_contains "J1.5 pending is reported" "lineage	venture	pending" "$out"

mkdir -p "$g/specs/capture-surface"
printf '# Capture surface — Requirements\n\n## Sources\n\n- **ops audit** — unrelated\n' >"$g/specs/capture-surface/requirements.md"
gate link --spec "$g/specs/capture-surface" "$g"
assert_eq "J1.5 a spec that does not cite the venture is refused" 1 "$rc"
assert_contains "J1.5 the refusal names the missing direction" "spec-side-missing" "$out"
printf -- '- **Venture out-graduate** — graduated seed (inception:out-graduate, Gate 2)\n' >>"$g/specs/capture-surface/requirements.md"
gate link --spec "$g/specs/capture-surface" "$g"
assert_eq "J1.5 link exits 0 once the spec cites the venture" 0 "$rc"
# shellcheck disable=SC2016 # literal backticks in the expected line, not an expansion
assert_eq "J1.5 the venture side names the spec" 1 "$(grep -c '— spec: `specs/capture-surface`$' "$g/brief.md")"
gate lineage "$g"
assert_contains "J1.5 both directions read linked" "lineage	venture	linked" "$out"
assert_eq "J1.5 linked is clean" 0 "$rc"

grep -v 'inception:out-graduate' "$g/specs/capture-surface/requirements.md" >"$tmp/r" && mv "$tmp/r" "$g/specs/capture-surface/requirements.md"
gate lineage "$g"
assert_eq "J1.5 a spec dropping its citation is a finding" 1 "$rc"
assert_contains "J1.5 the spec side is named" "lineage	venture	spec-side-missing" "$out"

mkv nolin
ready "$vroot/nolin"
"$GATE" record --outcome Graduate --decider "Dana Reyes" --rationale "ready" "$vroot/nolin" >/dev/null 2>&1
gate lineage "$vroot/nolin"
assert_eq "J1.5 a graduated scope with no lineage is a finding" 1 "$rc"
assert_contains "J1.5 the venture side is named" "lineage	venture	venture-side-missing" "$out"

# --- REQ-F1.3 partial graduation (Gherkin) -----------------------------------
# Scenario: one track graduates; sibling tracks and the venture stay live.

mkv tracks tracked
ready "$vroot/tracks"
gate record --outcome Recycle --tracks "capture=Hold" --decider "Dana Reyes" --rationale "x" "$vroot/tracks"
assert_eq "F1.3 a record must cover every live track" 1 "$rc"
gate record --outcome Recycle --decider "Dana Reyes" --rationale "x" "$vroot/tracks"
assert_eq "F1.3 a tracked venture needs the tracks line" 1 "$rc"
gate record --outcome Graduate --tracks "capture=Graduate,measure=Recycle" --decider "Dana Reyes" --rationale "x" "$vroot/tracks"
assert_eq "F1.3 a top-level Graduate leaving a track live is refused" 1 "$rc"
gate record --outcome Recycle --tracks "capture=Graduate,measure=Recycle" --decider "Dana Reyes" \
  --rationale "capture is ready; measure keeps going" "$vroot/tracks"
assert_eq "F1.3 partial graduation records" 0 "$rc"
assert_eq "F1.3 the venture stays live" Exploring "$(status_of "$vroot/tracks" brief.md)"
assert_eq "F1.3 the graduated track is annotated" 1 \
  "$(grep -c '^- \*\*capture\*\* — the single capture surface and its fan-out — graduated 2026-10-18$' "$vroot/tracks/brief.md")"
assert_eq "F1.3 the sibling track stays live" 1 \
  "$(grep -c '^- \*\*measure\*\* — the handover-time measurement pipeline$' "$vroot/tracks/brief.md")"
assert_eq "F1.3 the partial record validates" 0 "$(validates_clean "$vroot/tracks")"
gate seed --track measure --dest "$(specroot "$vroot/tracks")" "$vroot/tracks"
assert_eq "F1.3 a live track yields no seed" 1 "$rc"
gate seed --track capture --dest "$(specroot "$vroot/tracks")" "$vroot/tracks"
assert_eq "F1.3 the graduated track seeds" 0 "$rc"
tseed=$(cat "$vroot/tracks/specs/_pending/inception-tracks.capture.md" 2>/dev/null)
assert_contains "F1.3 the track seed carries the track key" "**Lineage:** inception:tracks/capture" "$tseed"
assert_contains "F1.3 the track seed carries the track's entries" "### A-2 —" "$tseed"
assert_not_contains "F1.3 the track seed leaves the sibling track's entries out" "A-4" "$tseed"
assert_eq "F1.3 the track lineage is recorded" 1 "$(grep -c '^- \*\*capture\*\* — Gate 2 — seed: ' "$vroot/tracks/brief.md")"
gate evaluate --track measure "$vroot/tracks"
assert_contains "F1.3 the sibling track is still evaluable" "scope	track measure" "$out"
gate record --outcome Recycle --tracks "capture=Recycle,measure=Recycle" --decider "Dana Reyes" --rationale "x" "$vroot/tracks"
assert_eq "F1.3 a graduated track is not re-gated" 1 "$rc"

# --- REQ-J1.1 probe: /spec-draft seed gathering finds the seed ---------------
# /spec-draft reads pending notes from <root>/_pending/, where <root> is the
# destination repository's resolved spec root. Graduate into a fresh product
# repository and look where seed gathering looks.

prod="$tmp/product-repo"
mkdir -p "$prod"
git -C "$prod" init -q
proot=$(specroot "$prod")
assert_eq "J1.1 the probe resolves the destination spec root" "$prod/specs" "$proot"
mkv probe
ready "$vroot/probe"
"$GATE" record --outcome Graduate --decider "Dana Reyes" --rationale "ready" "$vroot/probe" >/dev/null 2>&1
gate seed --dest "$proot" "$vroot/probe"
assert_eq "J1.1 a seed into another repository exits 0" 0 "$rc"
found=$(ls "$proot/_pending/" 2>/dev/null)
assert_eq "J1.1 seed gathering's pending directory holds the seed" "inception-probe.md" "$found"
assert_contains "J1.1 /spec-draft reads that directory" '<root>/_pending/' "$(cat "$SPEC_DRAFT")"
# shellcheck disable=SC2016 # literal backticks in the expected line, not an expansion
assert_eq "J1.1 the venture side names the other repository" 1 \
  "$(grep -c '— seed: `product-repo:specs/_pending/inception-probe.md` — spec: pending$' "$vroot/probe/brief.md")"
assert_contains "J1.1 the seed tells the spec what to cite" "inception:probe" "$(cat "$proot/_pending/inception-probe.md")"

cite=$(printf '%s\n' "$out" | sed -n 's/^cite	//p')
assert_contains "J1.1 the printed cite line carries the lineage key" "(inception:probe," "$cite"
mkdir -p "$prod/specs/capture"
printf '# Capture — Requirements\n\n## Sources\n\n%s\n' "$cite" >"$prod/specs/capture/requirements.md"
gate link --spec "$prod/specs/capture" "$vroot/probe"
assert_eq "J1.5 the seed's own cite line satisfies link" 0 "$rc"
# shellcheck disable=SC2016 # literal text for the expected line or a written script, not an expansion
assert_eq "J1.5 a spec in another repository is recorded by repository" 1 \
  "$(grep -c '— spec: `product-repo:specs/capture`$' "$vroot/probe/brief.md")"
gate lineage --spec "$prod/specs/capture" "$vroot/probe"
assert_contains "J1.5 a cross-repository spec reads linked" "lineage	venture	linked" "$out"
gate lineage "$vroot/probe"
assert_eq "J1.5 an unnamed cross-repository spec is not a finding" 0 "$rc"
assert_contains "J1.5 it reads unchecked" "lineage	venture	unchecked" "$out"

# --- convergence fixes -------------------------------------------------------

# A tracked venture closes once every track has graduated or ended.
mkv closing tracked
ready "$vroot/closing"
"$GATE" record --outcome Recycle --tracks "capture=Graduate,measure=Recycle" --decider "Dana Reyes" --rationale a "$vroot/closing" >/dev/null 2>&1
"$GATE" record --outcome Recycle --tracks "measure=Graduate" --decider "Dana Reyes" --rationale b "$vroot/closing" >/dev/null 2>&1
gate record --outcome Graduate --decider "Dana Reyes" --rationale "every track is out" "$vroot/closing"
assert_eq "F1.3 the closing record needs no live track" 0 "$rc"
assert_eq "F1.3 the closing record covers no track" 1 "$(grep -c '^Tracks: none$' "$vroot/closing/brief.md")"
assert_eq "F1.3 the venture closes Graduated" Graduated "$(status_of "$vroot/closing" brief.md)"
assert_eq "F1.3 the closed bundle validates" 0 "$(validates_clean "$vroot/closing")"

mkv killtracks tracked
gate record --outcome Kill --tracks "capture=Hold,measure=Recycle" --decider "Dana Reyes" --rationale x "$vroot/killtracks"
assert_eq "E1.2 a top-level Kill leaving a track live is refused" 1 "$rc"
mkv trackgate tracked
gate record --outcome Recycle --tracks "capture=Graduate,measure=Recycle" --decider "Dana Reyes" --rationale x "$vroot/trackgate"
assert_eq "F1.3 a track with an unresolved blocking assumption cannot graduate" 1 "$rc"
assert_contains "F1.3 the refusal names the gap" "blocking-unresolved	A-1" "$out"

mkv invalid
ready "$vroot/invalid"
set_field "$vroot/invalid/assumptions.md" A-2 Status invalidated
gate evaluate "$vroot/invalid"
assert_contains "E1.1 an invalidated blocking assumption is a gap" "gap	blocking-invalidated	A-2" "$out"
mkv synthfeas
ready "$vroot/synthfeas"
set_field "$vroot/synthfeas/assumptions.md" A-2 Evidence "synthetic — workflow audit"
gate evaluate "$vroot/synthfeas"
assert_contains "E1.1 synthetic evidence on a feasibility assumption is no desirability gap" "admissible	Graduate	yes" "$out"
mkv onedir
ready "$vroot/onedir"
set_field "$vroot/onedir/assumptions.md" A-2 Tasks none
gate evaluate "$vroot/onedir"
assert_contains "E1.4 the task's Tests line alone maps an assumption" "complete	yes" "$out"
gate evaluate "$vroot/out-recycle"
assert_contains "E1.5 a written record reads back" "next-gate	3" "$out"

mkdir -p "$tmp/plain/specs"
mkv nogit
ready "$vroot/nogit"
"$GATE" record --outcome Graduate --decider "Dana Reyes" --rationale ready "$vroot/nogit" >/dev/null 2>&1
gate seed --dest "$tmp/plain/specs" "$vroot/nogit"
assert_eq "F1.1 a destination outside a repository is refused" 1 "$rc"
assert_eq "F1.1 nothing is created in a refused destination" "" "$(ls -A "$tmp/plain/specs")"

mkdir -p "$tmp/dirty-dest"
git -C "$tmp/dirty-dest" init -q
mkv dirty
ready "$vroot/dirty"
"$GATE" record --outcome Graduate --decider "Dana Reyes" --rationale ready "$vroot/dirty" >/dev/null 2>&1
printf '\n### A-9 — x\n' >>"$vroot/dirty/assumptions.md"
gate seed --dest "$tmp/dirty-dest/specs" "$vroot/dirty"
assert_eq "F1.1 a bundle with validator findings yields no seed" 1 "$rc"
assert_eq "F1.1 and leaves the destination untouched" 0 "$(find "$tmp/dirty-dest/specs" 2>/dev/null | wc -l | tr -d ' ')"

mkv forged
ready "$vroot/forged"
"$GATE" record --outcome Graduate --decider "Dana Reyes" --rationale ready "$vroot/forged" >/dev/null 2>&1
awk '{ print } /^Decider: Dana Reyes$/ && !d { print "Decider: ## Injected heading"; d = 1 }' "$vroot/forged/brief.md" >"$tmp/b" \
  && mv "$tmp/b" "$vroot/forged/brief.md"
gate seed --dest "$(specroot "$vroot/forged")" "$vroot/forged"
assert_not_contains "F1.1 a repeated gate field cannot add a seed line" "## Injected heading" \
  "$(cat "$vroot/forged/specs/_pending/inception-forged.md" 2>/dev/null)"

mkdir -p "$g/specs/nospec"
gate link --spec "$g/specs/nospec" "$g"
assert_contains "J1.5 link names a spec without requirements" "lineage	venture	spec-missing" "$out"
printf '# X — Requirements\n\n## Sources\n\n- **near miss** — (inception:out-graduate-x)\n' >"$g/specs/capture-surface/requirements.md"
gate lineage "$g"
assert_contains "J1.5 a longer key does not cite a shorter one" "lineage	venture	spec-side-missing" "$out"

# Failure injection: a validator that crashes on the staged bundle, and an mv
# that fails on one file, must leave the bundle as it was.
cp -R "$REPO_ROOT/scripts" "$tmp/crash-scripts"
mv "$tmp/crash-scripts/inception-validate.sh" "$tmp/crash-scripts/inception-validate.real"
# shellcheck disable=SC2016 # literal text for the expected line or a written script, not an expansion
printf '#!/bin/sh\ncase "$*" in */stage) exit 2 ;; esac\nexec "$(dirname "$0")/inception-validate.real" "$@"\n' >"$tmp/crash-scripts/inception-validate.sh"
chmod +x "$tmp/crash-scripts/inception-validate.sh"
mkv crash
out=$("$tmp/crash-scripts/inception-gate.sh" record --outcome Hold --decider "Dana Reyes" --rationale x "$vroot/crash" 2>&1)
rc=$?
assert_eq "a crashing staged validation is an error" 2 "$rc"
assert_eq "and writes nothing" 0 "$(grep -c '^### Gate 2' "$vroot/crash/brief.md")"

mkdir -p "$tmp/shim"
realmv=$(command -v mv)
# shellcheck disable=SC2016 # literal text for the expected line or a written script, not an expansion
printf '#!/bin/sh\nfor a; do last=$a; done\ncase "$last" in */%s) exit 1 ;; esac\nexec %s "$@"\n' assumptions.md "$realmv" >"$tmp/shim/mv"
chmod +x "$tmp/shim/mv"
mkv torn
out=$(PATH="$tmp/shim:$PATH" "$GATE" record --outcome Hold --decider "Dana Reyes" --rationale x "$vroot/torn" 2>&1)
rc=$?
assert_eq "a failed install is an error" 2 "$rc"
for f in brief disciplines assumptions decisions plan; do
  assert_eq "a failed install restores $f.md" Exploring "$(status_of "$vroot/torn" "$f.md")"
done
assert_eq "a failed install leaves no record" 0 "$(grep -c '^### Gate 2' "$vroot/torn/brief.md")"
assert_eq "a failed install leaves no scratch file" "" "$(find "$vroot/torn" -maxdepth 1 -name '.inception-gate.*')"

# shellcheck disable=SC2016 # literal text for the expected line or a written script, not an expansion
printf '#!/bin/sh\nfor a; do last=$a; done\ncase "$last" in */brief.md) exit 1 ;; esac\nexec %s "$@"\n' "$realmv" >"$tmp/shim/mv"
mkv seedfail
ready "$vroot/seedfail"
"$GATE" record --outcome Graduate --decider "Dana Reyes" --rationale ready "$vroot/seedfail" >/dev/null 2>&1
out=$(PATH="$tmp/shim:$PATH" "$GATE" seed --dest "$(specroot "$vroot/seedfail")" "$vroot/seedfail" 2>&1)
rc=$?
assert_eq "a seed whose lineage cannot be recorded is an error" 2 "$rc"
assert_eq "and the seed is taken back" "" "$(ls -A "$vroot/seedfail/specs/_pending" 2>/dev/null)"
assert_eq "and no scratch file stays in the venture" "" "$(find "$vroot/seedfail" -maxdepth 1 -name '.inception-gate.*')"
gate seed --dest "$(specroot "$vroot/seedfail")" "$vroot/seedfail"
assert_eq "the seed can then be retried" 0 "$rc"

mkv modes
chmod 0644 "$vroot/modes/brief.md"
gate record --outcome Hold --decider "Dana Reyes" --rationale x "$vroot/modes"
assert_eq "an installed file keeps its mode" 1 "$(find "$vroot/modes/brief.md" -perm 0644 | wc -l | tr -d ' ')"
# shellcheck disable=SC2016 # the literal text searched for
assert_eq "no scratch name is derived from the pid" 0 "$(grep -c 'inception-gate\.\$\$' "$GATE")"

# --- refusals ----------------------------------------------------------------

ln -s "$tmp/elsewhere" "$tmp/linkdest"
mkdir -p "$tmp/elsewhere"
mkv linked
ready "$vroot/linked"
"$GATE" record --outcome Graduate --decider "Dana Reyes" --rationale "ready" "$vroot/linked" >/dev/null 2>&1
gate seed --dest "$tmp/linkdest" "$vroot/linked"
assert_eq "seed refuses a symbolic-link destination" 1 "$rc"
gate evaluate "$vroot/../no-such-venture"
assert_eq "an absent venture is a usage error" 2 "$rc"
mkv future
sed 's/^\*\*Format-version:\*\* 1.0$/**Format-version:** 9.0/' "$vroot/future/brief.md" >"$tmp/b" && mv "$tmp/b" "$vroot/future/brief.md"
gate evaluate "$vroot/future"
assert_eq "an unsupported format-version is refused, not parsed" 3 "$rc"

# --- surfaces ----------------------------------------------------------------

assert_contains "the skill routes the gate to the helper" "inception-gate.sh" "$(cat "$SKILL")"
assert_eq "the format defines the lineage section" 1 "$(grep -c '^## Lineage' "$FORMAT_DOC")"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all inception-gate tests passed"
