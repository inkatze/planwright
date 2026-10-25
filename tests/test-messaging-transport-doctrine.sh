#!/bin/bash
# shellcheck disable=SC2016 # the patterns match literal markdown backticks
# Tests for the messaging-transport doctrine and the doctrine, contract, and
# knob surfaces delivered beside it (fleet-messaging Task 1; REQ-G1.5,
# REQ-G1.6, REQ-G1.7, REQ-A1.6, REQ-F1.2, REQ-F1.6, REQ-E1.1, REQ-E1.2).
#
# Literal-token checks only: the design-level reading of each content is the
# task PR's review, and so are the two diff-shaped clauses (the floor doctrine
# changes in nothing beyond its one row and column, the contract doc gains
# nothing beyond its derivation rule), which a test run after merge could not
# tell apart from history. Sentences are matched over the doc with its line
# breaks folded to spaces, so a rewrap never fails a check.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$REPO_ROOT/doctrine/messaging-transport.md"
FLOOR="$REPO_ROOT/doctrine/fleet-coordination-floor.md"
IOC="$REPO_ROOT/doctrine/inter-orchestrator-coordination.md"
CONTRACT="$REPO_ROOT/doctrine/backend-capability-contract.md"
DEFAULTS="$REPO_ROOT/config/defaults.yml"
OPTIONS="$REPO_ROOT/docs/options-reference.md"
FLEET="$REPO_ROOT/docs/fleet.md"

# A sentence may name files, so `.sh` and `.md` do not end one.
S='([^.]|\.sh|\.md)*'

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

# folded <file> — the file on one line, runs of whitespace collapsed.
folded() { tr '\n' ' ' <"$1" | tr -s ' \t' '  '; }

# has <label> <file> <extended-regex> — the folded file matches.
has() {
  if folded "$2" | grep -Eq -- "$3"; then ok "$1"; else fail "$1"; fi
}

# section <file> <heading-prefix> — the lines under each `## ` heading
# starting with the prefix, up to the next `## ` heading.
section() {
  awk -v want="$2" '
    /^## / { on = (index($0, want) == 1); next }
    on { print }
  ' "$1"
}

# subsection <file> <heading-prefix> — the same for a `### ` heading, ending
# at the next `### ` or `## ` heading.
subsection() {
  awk -v want="$2" '
    /^##+ / { on = (index($0, want) == 1); next }
    on { print }
  ' "$1"
}

# section_has <label> <file> <heading-prefix> <extended-regex>
section_has() {
  if section "$2" "$3" | tr '\n' ' ' | tr -s ' \t' '  ' | grep -Eq -- "$4"; then
    ok "$1"
  else
    fail "$1"
  fi
}

missing=0
for f in "$DOC" "$FLOOR" "$IOC" "$CONTRACT" "$DEFAULTS" "$OPTIONS" "$FLEET"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: ${f#"$REPO_ROOT"/} missing" >&2
    missing=1
  fi
done
[ "$missing" = 0 ] || exit 1

# --- REQ-G1.5: resolves through the rule-doc chain --------------------------
resolve_err=$(mktemp)
resolved=$(PLANWRIGHT_ROOT="$REPO_ROOT" "$REPO_ROOT/scripts/resolve-rule-doc.sh" messaging-transport 2>"$resolve_err")
case "$resolved" in
  */doctrine/messaging-transport.md) ok "the doc resolves through the rule-doc chain" ;;
  *) fail "the doc does not resolve through the rule-doc chain (got '$resolved': $(cat "$resolve_err"))" ;;
esac
rm -f "$resolve_err"

# --- REQ-G1.5: the nine contents --------------------------------------------
section_has "signal-vs-record rule present" "$DOC" "## Signal versus record" \
  "store row${S}record"
section_has "only a turn-ending stop fires a notice" "$DOC" "## Signal versus record" \
  "[Oo]nly a stop that ends the worker's turn fires (an idle |a )?notice"
section_has "a mid-turn suspension is the healing sweep's case" "$DOC" "## Signal versus record" \
  "mid-turn suspension${S}healing sweep"
section_has "fallback obligation present" "$DOC" "## The fallback obligation" \
  'names its (deterministic )?fallback'
section_has "discipline ladder reads script < tiered < open" "$DOC" "## The discipline ladder" \
  '`script` < `tiered` < `open`'
section_has "the ladder names its three directions" "$DOC" "## The discipline ladder" \
  'worker.{1,3}tower.*tower.{1,3}worker.*tower.{1,3}tower'
section_has "send-time pressure demotion stated" "$DOC" "## The discipline ladder" \
  '`reduce-concurrency`[^.]*one value further down'
section_has "the effective-value composition stated" "$DOC" "## The discipline ladder" \
  'max\(script, knob − direction offset − pressure demotion\)'
section_has "probe: the socket variable" "$DOC" "## The per-session probe" \
  'CLAUDE_CODE_MESSAGING_SOCKET'
section_has "probe: the version minimum" "$DOC" "## The per-session probe" \
  '2\.1\.248'
section_has "probe: the inbound-acceptance conjunct" "$DOC" "## The per-session probe" \
  'crossSessionInbound'
section_has "probe: the off switch reads absent" "$DOC" "## The per-session probe" \
  '`off`'
section_has "cross-machine transit note present" "$DOC" "## Cross-machine transit" \
  'third-party infrastructure'
has "the three sweep names distinguished" "$DOC" \
  "healing sweep is \`fleet-attention-watch\\.sh watch\`${S}reconcile sweep is \`/orchestrate\`${S}\`fleet-attention-watch\\.sh reconcile\`"
section_has "glossary: fallback ladder" "$DOC" "## Glossary" '[Ff]allback ladder'
section_has "glossary: discipline ladder" "$DOC" "## Glossary" '[Dd]iscipline ladder'
section_has "glossary: the usage gate's rung ladder" "$DOC" "## Glossary" 'usage gate'
section_has "fleet-runtime version rule present" "$DOC" "## The fleet-runtime version rule" \
  '[Mm]ixed CLI versions'
section_has "REQ-G1.6: no other resource class declared" "$DOC" "## Resource classes" \
  'no (other )?resource class beyond the inbox socket'
section_has "REQ-G1.6: the subscription is tower-side and self-closing" "$DOC" "## Resource classes" \
  "tower-side${S}self-closing"

# --- REQ-G1.1 / D-13: the per-path fallback table ---------------------------
table=$(section "$DOC" "## The per-path fallback table" | grep '^|' | sed '1,2d')
# row <path> — the row whose Path cell (the first) names <path>.
row() {
  printf '%s\n' "$table" | awk -F'|' -v p="$1" 'index(tolower($2), tolower(p)) { print; exit }'
}
# fallback_cell <row> — that row's Fallback cell (the third), trimmed.
fallback_cell() {
  printf '%s\n' "$1" | awk -F'|' '{ c = $4; gsub(/^[ \t]+|[ \t]+$/, "", c); print c }'
}
for path in 'steer' 'decision answer' 'idle notice' "tower's own wake" \
  'healing sweep' 'projection refresh' 'advisory'; do
  r=$(row "$path")
  if [ -z "$r" ]; then
    fail "fallback table row missing: $path"
  elif [ -z "$(fallback_cell "$r")" ]; then
    fail "fallback table row names no fallback: $path"
  else
    ok "fallback table row names a fallback: $path"
  fi
done
case "$(fallback_cell "$(row "tower's own wake")")" in
  *metronome*) ok "the wake row names today's metronome" ;;
  *) fail "the wake row does not name today's metronome" ;;
esac
# per_rung <path> <rung> <outcome-regex> — the row's Fallback cell reads the
# rung's own outcome right after naming it.
per_rung() {
  if fallback_cell "$(row "$1")" | grep -Eq -- "on \`$2\`[^;]*$3"; then
    ok "the $1 row reads per rung: $2"
  else
    fail "the $1 row's fallback does not read $2 as $3"
  fi
}
per_rung steer tmux 'attributed buffer-paste'
per_rung steer stream-json-persistent 'operator handoff'
per_rung steer headless-oneshot 'none'
per_rung 'decision answer' tmux 'attributed buffer-paste'
per_rung 'decision answer' stream-json-persistent 'control response'
per_rung 'decision answer' headless-oneshot 'none'

# --- REQ-G1.6: one row and one column in the floor doctrine ----------------
class_rows=$(awk '
  /^### / { on = ($0 == "### The class contract"); next }
  on && /^\| / { print }
' "$FLOOR" | sed '1,2d')
if [ "$(printf '%s\n' "$class_rows" | grep -c '^| Inbox socket |')" = 1 ]; then
  ok "the class contract table carries one inbox-socket row"
else
  fail "the class contract table does not carry exactly one inbox-socket row"
fi
inbox_row=$(printf '%s\n' "$class_rows" | grep '^| Inbox socket |')
case "$inbox_row" in
  *harness*session*death\ evidence*) ok "the inbox-socket row names its harness open, session close, and death-evidence detector" ;;
  *) fail "the inbox-socket row does not read open/close/detector as REQ-G1.6 states" ;;
esac
rungs=$(awk '
  /^### / { on = ($0 == "### The rungs, crossed with the classes"); next }
  on && /^\|/ { print }
' "$FLOOR")
header=$(printf '%s\n' "$rungs" | head -1)
case "$header" in
  *"| Inbox socket |") ok "the rungs-by-classes table gains the inbox-socket column" ;;
  *) fail "the rungs-by-classes table's last column is not the inbox socket" ;;
esac
want_cols=$(printf '%s\n' "$header" | awk -F'|' '{ print NF }')
# The Inbox socket field's position, read off the header rather than assumed.
inbox_col=$(printf '%s\n' "$header" | awk -F'|' '{ for (i = 1; i <= NF; i++) { c = $i; gsub(/^[ \t]+|[ \t]+$/, "", c); if (c == "Inbox socket") { print i; exit } } }')
rung_rows=$(printf '%s\n' "$rungs" | sed '1,2d')
blank=0
while IFS= read -r r; do
  [ -n "$r" ] || continue
  n=$(printf '%s\n' "$r" | awk -F'|' '{ print NF }')
  cell=$(printf '%s\n' "$r" | awk -F'|' -v k="${inbox_col:-0}" '{ c = (k > 0) ? $k : ""; gsub(/^[ \t]+|[ \t]+$/, "", c); print c }')
  if [ "$n" != "$want_cols" ] || [ -z "$cell" ]; then blank=$((blank + 1)); fi
done <<EOF
$rung_rows
EOF
if [ -z "$rung_rows" ]; then
  fail "the rungs-by-classes table has no rows"
elif [ "$blank" = 0 ]; then ok "every rung fills the inbox-socket cell"; else fail "$blank rung row(s) leave the inbox-socket cell blank or misaligned"; fi
rung_count=$(printf '%s\n' "$rungs" | sed '1,2d' | grep -c '^| `')
if [ "$rung_count" = 6 ]; then ok "the cross still covers all six rungs"; else fail "the cross covers $rung_count rungs, not six"; fi

# --- REQ-G1.7: the inter-orchestrator-coordination amendment --------------
steer_heading=$(grep -E '^### Steer-in-flight' "$IOC" | head -1)
case "$steer_heading" in
  *essag*first*uffer-paste*) ok "the steer-in-flight heading reads messaging first, buffer-paste the fallback" ;;
  *) fail "the steer-in-flight heading does not read messaging first ($steer_heading)" ;;
esac
if subsection "$IOC" "### Steer-in-flight" | tr '\n' ' ' | grep -q 'fleet-messaging\.sh send'; then
  ok "the steer-in-flight body names fleet-messaging.sh first"
else
  fail "the steer-in-flight body does not name fleet-messaging.sh"
fi
has "the one-audited-script sentence names fleet-messaging.sh" "$IOC" \
  "audited script${S}fleet-messaging\\.sh"
has "the relay-command description names fleet-messaging.sh" "$IOC" \
  "\`relay-command\`${S}fleet-messaging\\.sh"
has "the tower-to-tower clause cross-references the advisory rule" "$IOC" \
  "[Tt]ower-to-tower\\*\\*${S}advisor${S}messaging-transport\\.md"
if folded "$IOC" | grep -q 'buffer-paste mechanism serves both'; then
  fail "buffer-paste is still pinned as the tower-to-tower mechanism of record"
else
  ok "buffer-paste is no longer the tower-to-tower mechanism of record"
fi

# --- REQ-A1.6 / D-17: the contract doc's derivation rule -------------------
has "the contract doc derives messaging eligibility from Session-grade" "$CONTRACT" \
  "[Mm]essaging eligibility${S}\`Session-grade\`"
has "the contract doc distinguishes dispatch eligibility" "$CONTRACT" \
  '[Mm]essaging eligibility[^|]*dispatch eligibility'
if folded "$CONTRACT" | grep -q 'CLAUDE_CODE_MESSAGING_SOCKET'; then
  fail "the contract doc carries a probe definition"
else
  ok "the contract doc carries no probe definition"
fi

# --- REQ-F1.2 / REQ-F1.6 / REQ-E1.1: the three knobs on three surfaces -----
check_default() {
  if grep -Eq "^$1: $2\$" "$DEFAULTS"; then ok "defaults: $1 = $2"; else fail "defaults: $1 is not $2"; fi
}
check_default messaging_discipline tiered
check_default messaging_cross_machine false
check_default messaging_heal_cadence_seconds 300

# check_option_default <knob> <value> — the options reference row exists and
# its Default cell is the backticked value defaults.yml carries.
check_option_default() {
  cell=$(grep "^| \`$1\`" "$OPTIONS" | awk -F'|' '{ c = $3; gsub(/^[ \t]+|[ \t]+$/, "", c); print c }')
  if [ "$cell" = "\`$2\`" ]; then ok "options reference row: $1 defaults to $2"; else fail "options reference row for $1 does not default to $2 (got '$cell')"; fi
}
check_option_default messaging_discipline tiered
check_option_default messaging_cross_machine false
check_option_default messaging_heal_cadence_seconds 300
for knob in messaging_discipline messaging_cross_machine messaging_heal_cadence_seconds; do
  if grep -q "^| \`$knob\`" "$FLEET"; then ok "fleet knobs row: $knob"; else fail "fleet knobs row missing: $knob"; fi
done

# The discipline knob's own comment entry in defaults.yml: from the comment
# line that opens it to the next knob's entry.
disc_comment=$(awk '
  /^# messaging_discipline / { on = 1; print; next }
  on && /^# [a-z_]+ / { exit }
  on && /^#/ { print }
' "$DEFAULTS")
disc_option=$(grep '^| `messaging_discipline`' "$OPTIONS")
disc_fleet=$(grep '^| `messaging_discipline`' "$FLEET")
for surface in defaults options fleet; do
  case "$surface" in
    defaults) text=$disc_comment ;;
    options) text=$disc_option ;;
    fleet) text=$disc_fleet ;;
  esac
  for v in off script tiered open; do
    # Markdown surfaces backtick each value; the yaml comment has no markup,
    # so it is matched as a whole word.
    if [ "$surface" = defaults ]; then
      printf '%s\n' "$text" | grep -qw -- "$v" && listed=1 || listed=0
    else
      case "$text" in *"\`$v\`"*) listed=1 ;; *) listed=0 ;; esac
    fi
    if [ "$listed" = 1 ]; then ok "$surface: messaging_discipline lists $v"; else fail "$surface: messaging_discipline does not list $v"; fi
  done
  case "$text" in
    *"kill switch"*) ok "$surface: off named the kill switch" ;;
    *) fail "$surface: off is not named the kill switch" ;;
  esac
  case "$text" in
    *"outside the ladder"*) ok "$surface: off stated outside the ladder" ;;
    *) fail "$surface: off is not stated outside the ladder" ;;
  esac
done
case "$(grep '^| `messaging_cross_machine`' "$OPTIONS")" in
  *isolatePeerMachines*) ok "the cross-machine row names isolatePeerMachines" ;;
  *) fail "the cross-machine row does not name isolatePeerMachines" ;;
esac

# --- REQ-G1.9: the supervisor duty -----------------------------------------
duty_heading=$(grep -E '^##+ .*supervisor duty' "$IOC" | head -1)
if [ -n "$duty_heading" ]; then
  ok "a supervisor-duty heading is present"
else
  fail "no heading contains 'supervisor duty'"
fi
# duty_text — the supervisor-duty section folded, up to the next heading of
# its level or above.
duty_text() {
  awk -v want="$duty_heading" '
    $0 == want { on = 1; lvl = index($0, " "); next }
    on && /^#+ / && index($0, " ") <= lvl { exit }
    on { print }
  ' "$IOC" | tr '\n' ' ' | tr -s ' \t' '  '
}
for phrase in 'supervising session' 'permission prompt' 'autonomous-safe-decision'; do
  if [ -n "$duty_heading" ] && duty_text | grep -q -- "$phrase"; then
    ok "the supervisor-duty section names: $phrase"
  else
    fail "the supervisor-duty section does not name: $phrase"
  fi
done

# --- REQ-G1.8 / REQ-C1.7: the relay contract and the question row ---------
has "the relay text says the paste never submits it unattended" "$IOC" \
  'never submits it unattended'
has "the relay text names the pending relay" "$IOC" 'pending relay'
busy=$(grep -n 'live, busy worker' "$IOC")
stray=$(printf '%s\n' "$busy" | grep -v 'messag' | grep -v '^$')
if [ -z "$stray" ]; then
  ok "every 'live, busy worker' line names messaging"
else
  fail "'live, busy worker' lines without messaging: $stray"
fi
if [ -n "$(row 'question')" ] && [ -n "$(fallback_cell "$(row 'question')")" ]; then
  ok "the fallback table carries a question row with a fallback"
else
  fail "the fallback table carries no question row with a fallback"
fi
has "the opening turn is not a messaging path" "$DOC" 'not a messaging path'
section_has "the question message is the one model-composed upward path" "$DOC" \
  "## Signal versus record" "question${S}one model-composed"
section_has "the question is recorded first as a fork" "$DOC" \
  "## Signal versus record" "\`fork\`"
section_has "the question is never completion or status" "$DOC" \
  "## Signal versus record" "never${S}completion${S}status"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all messaging-transport doctrine checks passed"
