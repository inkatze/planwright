#!/bin/sh
# inception-validate.sh — the inception bundle validator (inception Task 2;
# REQ-A1.9, REQ-C1.7, REQ-C1.8, REQ-G1.1, REQ-G1.5 · D-12).
#
# One validator, every surface (D-12): the /inception skill runs it in-session
# at bundle writes, the scaffolded pre-commit hook runs it on the operator's
# machine, and the scaffolded CI workflow runs it on stakeholder commits
# arriving through the GitHub web UI. doctrine/inception-format.md is the
# normative source for every rule below; this script is its mechanical shadow.
#
# What it enforces, in the order the checks run:
#
#   1. The five authored files are present and lex cleanly, and their
#      `Format-version:` lines parse, agree on a major, and name a supported
#      one. This is the fail-closed gate (REQ-C1.7): on failure nothing else
#      runs, because the rules to apply cannot be known — a bundle from a
#      future plugin is refused, never misparsed.
#   2. Header block: title role token, lifecycle status and its mirrors,
#      `Last reviewed:` as an ISO date.
#   3. ID grammar (`A-`, `DEC-`, `T-`, `KC-` plus a positive integer),
#      uniqueness across live and superseded entries, and supersession
#      pointers that resolve to a same-type id.
#   4. Register integrity: the assumption, decision, and plan-task field sets
#      with their enums and status-gated rules, plus the cross-references
#      between them and the discipline / stakeholder maps.
#   5. brief.md structure: required sections in their relative order, the
#      prompt-vs-structure skip discipline, and the minimum core (REQ-C1.8) —
#      kill criteria set, success metric named, registers parseable.
#   6. Gate-record integrity (REQ-E1.5): heading grammar and sequence, the
#      field set, outcome and verdict enums, decider provenance, and the
#      coverage rules tying a record to the live registers.
#   7. With `--baseline <ref>`: the stakeholder-commit guard (REQ-G1.5) — ids
#      and recorded gate runs are untouchable through the review channel, and
#      a terminal status is not revived. Prose edits pass.
#
# Deliberately NOT enforced, so the boundary is on the record rather than
# inferred from silence:
#   - Field and gate-line ORDER within an entry. The format states a template
#     order; enforcing it would fight the additive-within-major rule, which
#     admits new optional fields. "Rationale last" is enforced indirectly: a
#     gate line after `Rationale:` reads as rationale text, so it lands as a
#     missing field.
#   - plan.md task ORDERING (lowest-confidence highest-blocking first, with
#     the limiting-constraint tie-break). That is a derived-ordering rule the
#     gate move reads, not a structural one.
#   - Whether the enumeration of blocking assumptions and open forks is
#     COMPLETE. The format doc reserves that to the gate decider, aided by the
#     gate completeness check; the validator checks its structural shadow.
#   - Unknown fields and sections within a supported major, which the format
#     rules require a reader to ignore and parse on.
#
# Usage:
#   inception-validate.sh [--baseline <ref>] <venture-dir>
#   inception-validate.sh --version-check <venture-dir>
#   inception-validate.sh --rules
#
# Exit: 0 clean · 1 findings · 2 usage or environment error · 3 fail-closed
#   refusal (missing file, unbalanced code fence, missing/unparseable/
#   unsupported format-version) — the bundle was not validated at all. Callers
#   that must tell "refuse to parse" from "parsed, has findings" key on 3; the
#   renderer and the skill call `--version-check` for exactly that.
#
# Portable POSIX sh + awk; bash 3.2 / BSD tooling floor, no mise dependency
# (REQ-K1.5) — it runs in venture repos, which know nothing about planwright's
# own toolchain.
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# Canonical echo-discipline sanitizer (doctrine/security-posture.md): bundle
# content is repo-controlled input and reaches the terminal only stripped.
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

# The shared spec-parse grammar lib (format-grammar D-3, D-4; REQ-B1.1). An
# inception bundle is a sibling of the four-file spec format rather than a reuse
# of it (inception D-1), but it deliberately INHERITS the meta-spec's header
# conventions — the same bolded `Format-version:` / `Status:` declarations, the
# same mirrored-status discipline, the same column-0 fence rule. Those are the
# same grammar, so they come from the same place: a private copy here would let
# the two formats drift on what a duplicate declaration or an open fence means.
#
# Known bound: `**Last reviewed:**` carries a space, which the lib's header-key
# grammar does not admit, so that one declaration is read below with the lib's
# own block boundary rather than through it (obs:e57b5a39).
#
# Sourced, never executed; fail closed when missing or unreadable (REQ-B1.6a).
spec_parse_sh="$script_dir/spec-parse.sh"
if [ ! -f "$spec_parse_sh" ] || [ ! -r "$spec_parse_sh" ]; then
  printf '%s\n' "inception-validate: required helper $spec_parse_sh missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/spec-parse.sh
. "$spec_parse_sh" || exit 2

SUPPORTED_MAJOR=1
BUNDLE_FILES="brief.md disciplines.md assumptions.md decisions.md plan.md"

usage() {
  echo "usage: inception-validate.sh [--baseline <ref>] <venture-dir>" >&2
  echo "       inception-validate.sh --version-check <venture-dir>" >&2
  echo "       inception-validate.sh --rules" >&2
  exit 2
}

# The advertised rule set: one `<code> <description>` line per enforced rule.
# The test suite reads this and fails if any code here lacks a seeded-violation
# fixture, or any fixture expects a code that is not here — so the list cannot
# drift away from what the validator actually emits.
print_rules() {
  cat <<'RULES'
FMT-MISSING a file declares no parseable Format-version
FMT-UNSUPPORTED the declared major is not supported by this validator
FMT-MIRROR the five files do not declare the same Format-version
FILE-MISSING an authored bundle file is absent
FENCE-UNBALANCED a column-0 code fence is left open at end of file
HDR-ROLE the title line does not carry the role token of its file
HDR-STATUS the lifecycle status is absent or off the enum
HDR-STATUS-MIRROR a file status does not mirror brief.md
HDR-REVIEWED Last reviewed is absent or not an ISO date
ID-GRAMMAR a register entry id is off the typed-integer grammar
ID-DUPLICATE two entries of a type share a number
ID-SUPERSEDE-TARGET a supersession pointer names no same-type entry
ASM-FIELD-MISSING an assumption is missing a required field
ASM-STATEMENT-SKELETON a statement skips the believe/verify/measure/right-if keywords
ASM-RISK-TAG the risk tag is off the four-risk enum
ASM-GRADE the evidence grade is off the commitment-weighted ladder
ASM-BLOCKING the blocking flag is not yes or no
ASM-STATUS the assumption status is off the enum
ASM-EVIDENCE-REQUIRED a validated or invalidated assumption carries no threshold or evidence
ASM-WAIVED-REASON a waived assumption records no reason
ASM-TASK-REF an assumption links a plan task that does not exist
DEC-FIELD-MISSING a decision is missing a required field
DEC-STATUS the decision status is off the enum
DEC-DOOR the door class is not one-way or two-way
DEC-OPTIONS a decision lists no considered options
DEC-DECIDER-UNKNOWN a decider holds no Decides cell in the stakeholder map
DEC-DISCIPLINE-UNKNOWN the owning discipline is not in the discipline map
PLAN-FIELD-MISSING a plan task is missing a required field
PLAN-KIND the task kind is off the enum
PLAN-STATUS the task status is off the enum
PLAN-TESTS-EMPTY a plan task traces to no assumption or decision
PLAN-TESTS-REF a plan task traces to an id that does not exist
PLAN-TARGET the alignment target is absent, misplaced, or names no decision area
BRIEF-SECTION-MISSING a required brief section or opportunity field is absent
BRIEF-SECTION-ORDER the required brief sections are out of their relative order
BRIEF-SKIP-FORM a prompt is empty without a reason, or a structural section is skipped
BRIEF-METRIC-EMPTY the success metric is absent or skipped
KC-MISSING no kill criterion is set
KC-FORM a kill criterion is not a state-plus-date pair
KC-DECIDER-MISSING the kill-criteria section names no gate decider
KC-DECIDER-UNKNOWN the gate decider holds no Decides cell in the stakeholder map
SRC-FORM a sources-register entry has no bold name lead
DIS-SECTION a required disciplines section is absent or out of order
DIS-STAFFING-TOKEN the staffing token is off the enum
DIS-STAFFING-COVERAGE a mapped discipline has no staffing row
DIS-DECISION-REF the discipline map cites a decision that does not exist
STK-DECIDES-SINGLE a Decides cell does not hold exactly one name
TRK-LABEL a declared track label is off the grammar
TRK-UNDECLARED an entry references a track the brief does not declare
TRK-UNTRACKED an entry carries a track field in an untracked venture
GATE-HEADING a gate-log entry heading is off the grammar
GATE-SEQUENCE gate numbering is not sequential and append-only
GATE-FIELD-MISSING a gate record is missing a required line
GATE-DATE-MISMATCH the gate heading date and the Date line disagree
GATE-OUTCOME the gate outcome is off the four-outcome enum
GATE-DECIDER the record decider is not the venture gate decider
GATE-EVIDENCE-FORM a gate evidence item is off the A-n (grade) form
GATE-THRESHOLD-TOKEN a threshold verdict is off the enum
GATE-THRESHOLD-COVERAGE a live blocking assumption is missing from Thresholds
GATE-KC-TOKEN a kill-criterion state is off the enum
GATE-KC-COVERAGE a live kill criterion is missing from Kill-criteria
GATE-TRACKS-PRESENCE the Tracks line is present in an untracked venture or absent in a tracked one
GATE-TRACKS-COVERAGE a live declared track is missing from Tracks
GATE-GRADUATE-OPEN a Graduate outcome leaves a blocking assumption unevaluated
GATE-GRADUATE-LIVE-TRACK a top-level Graduate leaves a declared track live
GATE-SYNTHETIC-DESIRABILITY synthetic evidence passes a desirability assumption at Graduate
LIFE-STATUS-OUTCOME the venture status disagrees with the latest gate outcome
BASE-ID-VANISHED an id present at the baseline was renumbered or removed
BASE-GATE-MUTATED a recorded gate run was edited or removed
BASE-STATUS-TRANSITION the venture was revived out of a terminal status
RULES
}

mode=validate
baseline=
target=

while [ $# -gt 0 ]; do
  case $1 in
    --rules)
      [ $# -eq 1 ] || usage
      print_rules
      exit 0
      ;;
    --version-check)
      mode=version
      shift
      ;;
    --baseline)
      [ $# -ge 2 ] || usage
      baseline=$2
      shift 2
      ;;
    -*) usage ;;
    *)
      [ -z "$target" ] || usage
      target=$1
      shift
      ;;
  esac
done

[ -n "$target" ] || usage
while [ "$target" != "${target%/}" ]; do target=${target%/}; done
[ -n "$target" ] || target=/
if [ ! -d "$target" ]; then
  printf 'inception-validate: not a directory: %s\n' \
    "$(sanitize_printable "$target" '(unprintable path)')" >&2
  exit 2
fi

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT

err=0
refuse=0
tab=$(printf '\t')

# report <code> <where> <message>
report() {
  printf 'inception-validate: ERROR %s: [%s] %s\n' \
    "$(sanitize_printable "$2" '(unprintable file)')" "$1" \
    "$(sanitize_printable "$3" '(unprintable detail)')"
  err=$((err + 1))
}

# --- 1. Fail-closed gate ----------------------------------------------------

for f in $BUNDLE_FILES; do
  if [ ! -f "$target/$f" ] || [ ! -r "$target/$f" ]; then
    report FILE-MISSING "$f" "authored bundle file is absent or unreadable"
    refuse=1
  fi
done

if [ "$refuse" -eq 0 ]; then
  # An unclosed column-0 fence means the rest of the file lexed as
  # documentation; refuse rather than report findings from half a parse. The
  # probe is the lib's, which also screens for NUL along the way.
  for f in $BUNDLE_FILES; do
    frc=0
    spec_parse_fence_balance "$target/$f" >/dev/null 2>&1 || frc=$?
    case $frc in
      0) ;;
      3)
        report FENCE-UNBALANCED "$f" "a column-0 code fence is left open at end of file"
        refuse=1
        ;;
      *)
        report FILE-MISSING "$f" "the file could not be read (unreadable or NUL-bearing)"
        refuse=1
        ;;
    esac
  done
fi

# Two single-key lib calls per file rather than one batched header_block call:
# a five-file bundle is not the whole-corpus sweep the batching clause is aimed
# at, and pulling two named keys out of a stream in shell would cost more awk
# spawns than it saves.
hdr_value() {
  # hdr_value <file> <key> — prints the declaration value, `!dup` when the
  # header block declares it more than once (unparseable, fail closed), or
  # `!err` when the file could not be read.
  hv=$(spec_parse_header_value "$target/$1" "$2" 2>/dev/null)
  case $? in
    0) printf '%s' "$hv" ;;
    3) printf '!dup' ;;
    *) printf '!err' ;;
  esac
}

if [ "$refuse" -eq 0 ]; then
  seen_versions=
  for f in $BUNDLE_FILES; do
    v=$(hdr_value "$f" Format-version)
    case $v in
      '' | '!dup' | '!err')
        report FMT-MISSING "$f" "no single parseable Format-version declaration in the header block"
        refuse=1
        continue
        ;;
    esac
    case $v in
      *[!0-9.]* | *..* | .* | *. | *.*.*)
        report FMT-MISSING "$f" "Format-version is not a <major>.<minor> value"
        refuse=1
        continue
        ;;
    esac
    major=${v%%.*}
    if [ "$major" != "$SUPPORTED_MAJOR" ]; then
      report FMT-UNSUPPORTED "$f" \
        "unsupported format-version $v (this validator supports major $SUPPORTED_MAJOR); refusing to parse the bundle"
      refuse=1
      continue
    fi
    case " $seen_versions " in
      *" $v "*) ;;
      *) seen_versions="$seen_versions $v" ;;
    esac
  done
  if [ "$refuse" -eq 0 ]; then
    nver=0
    for v in $seen_versions; do nver=$((nver + 1)); done
    if [ "$nver" -gt 1 ]; then
      report FMT-MIRROR brief.md \
        "the five files declare different Format-version values ($seen_versions )"
    fi
  fi
fi

if [ "$refuse" -ne 0 ]; then
  printf 'inception-validate: %d error(s); bundle not validated (fail closed)\n' "$err"
  exit 3
fi

if [ "$mode" = version ]; then
  exit 0
fi

# --- 2. Content parse: one awk pass over the five files, checks in END ------

# The status declarations come from the lib and reach awk through the
# environment, not through `-v`: awk expands backslash escapes in a `-v` value,
# and a bundle value is raw content that must survive verbatim into a finding.
i=0
for f in $BUNDLE_FILES; do
  i=$((i + 1))
  eval "INC_ST_$i=\$(hdr_value \"\$f\" Status)"
  eval "export INC_ST_$i"
done

# The lib fence lexer is spliced in AFTER the per-file reset rule below, not at
# the top: its rules `next`, so a file whose first line is a fence would
# otherwise skip the reset entirely.
awk '
function emit(code, file, msg) { printf "%s\t%s\t%s\n", code, file, msg }
function has(a, k) { return (k in a) }
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function id_ok(prefix, id) { return id ~ ("^" prefix "-[1-9][0-9]*$") }

function flush_field(   key) {
  if (cur_kind == "" || cur_field == "") { cur_field = ""; return }
  key = cur_kind SUBSEP cur_id SUBSEP cur_field
  F[key] = cur_val
  FSEEN[key] = 1
  cur_field = ""
}

function start_entry(prefix, head,   id) {
  cur_kind = prefix; cur_field = ""
  id = head; sub(/ —.*$/, "", id); id = trim(id)
  if (!id_ok(prefix, id) || head !~ / — .+$/) {
    emit("ID-GRAMMAR", file, "entry heading \"" head "\" is not " prefix "-<positive integer> — <name>")
    cur_kind = ""; cur_id = ""
    return
  }
  if (has(IDSEEN, prefix SUBSEP id))
    emit("ID-DUPLICATE", file, id " is used by more than one entry; ids are append-only and never reused")
  IDSEEN[prefix SUBSEP id] = 1
  ORDER[prefix, ++COUNT[prefix]] = id
  cur_id = id
}

function start_gate(head,   num, d) {
  cur_kind = "GATE"; cur_field = ""
  if (head !~ /^Gate [1-9][0-9]* — [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
    emit("GATE-HEADING", "brief.md", "gate-log heading \"" head "\" is not `Gate <n> — <YYYY-MM-DD>`")
    cur_kind = ""; cur_id = ""
    return
  }
  num = head; sub(/^Gate /, "", num); sub(/ —.*$/, "", num)
  d = head; sub(/^.* — /, "", d)
  cur_id = num
  GATEN[++gaten] = num
  GATEDATE[num] = d
}

function srcbad(line) {
  emit("SRC-FORM", "brief.md", "sources entry \"" substr(trim(line), 1, 60) "\" does not open with a bold name lead")
}

function kc_bullet(line,   id, rest, sup) {
  id = line; sub(/^- \*\*/, "", id); sub(/:\*\*.*$/, "", id)
  if (!id_ok("KC", id)) {
    emit("ID-GRAMMAR", "brief.md", "kill-criterion id \"" id "\" is not KC-<positive integer>")
    return
  }
  if (has(IDSEEN, "KC" SUBSEP id))
    emit("ID-DUPLICATE", "brief.md", id " is used by more than one kill criterion")
  IDSEEN["KC" SUBSEP id] = 1
  ORDER["KC", ++COUNT["KC"]] = id
  rest = line; sub(/^- \*\*KC-[^:*]*:\*\*[ \t]*/, "", rest)
  if (rest ~ / — \*\*Superseded-by:\*\* /) {
    sup = rest; sub(/^.* — \*\*Superseded-by:\*\*[ \t]*/, "", sup); sub(/[ \t].*$/, "", sup)
    SUPTGT["KC" SUBSEP id] = sup
    sub(/ — \*\*Superseded-by:\*\*.*$/, "", rest)
  }
  if (rest !~ / — by [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/)
    emit("KC-FORM", "brief.md", id " is not a state-plus-date pair (`<state> — by <YYYY-MM-DD>`)")
}

function track_bullet(line,   label) {
  label = line; sub(/^- \*\*/, "", label); sub(/\*\*.*$/, "", label)
  TRACKN++
  if (label !~ /^[a-z0-9][a-z0-9-]*$/ || length(label) > 32) {
    emit("TRK-LABEL", "brief.md", "track label \"" label "\" must match ^[a-z0-9][a-z0-9-]*$ (max 32)")
    return
  }
  TRACK[label] = 1
  if (line ~ / — graduated [0-9]/ || line ~ / — ended [0-9]/) TRACKDONE[label] = 1
}

function check_track(f, kind, id,   lb) {
  if (!has(FSEEN, kind SUBSEP id SUBSEP "Track")) return
  lb = F[kind SUBSEP id SUBSEP "Track"]
  if (!tracked)
    emit("TRK-UNTRACKED", f, id " carries a Track field but the brief declares no tracks")
  else if (!(lb in TRACK))
    emit("TRK-UNDECLARED", f, id " references track \"" lb "\", which the brief does not declare")
}

BEGIN {
  split("Exploring On-hold Graduated Killed Abandoned", t, " "); for (i in t) STATUS[t[i]] = 1
  split("value usability feasibility viability", t, " "); for (i in t) RISKTAG[t[i]] = 1
  split("synthetic opinion stated-intent costly-signal behavior", t, " "); for (i in t) GRADE[t[i]] = 1
  split("open testing validated invalidated waived", t, " "); for (i in t) ASTATUS[t[i]] = 1
  split("open decided deferred", t, " "); for (i in t) DSTATUS[t[i]] = 1
  split("spike research analysis demand-signal alignment", t, " "); for (i in t) KIND[t[i]] = 1
  split("planned running delivered accepted dropped", t, " "); for (i in t) TSTATUS[t[i]] = 1
  split("Graduate Hold Recycle Kill", t, " "); for (i in t) OUTCOME[t[i]] = 1
  split("pass fail waived open", t, " "); for (i in t) VERDICT[t[i]] = 1
  split("clear approaching tripped", t, " "); for (i in t) KCSTATE[t[i]] = 1
  split("agent-persona named-human unstaffed", t, " "); for (i in t) STAFF[t[i]] = 1

  ROLE["brief.md"] = "Brief"; ROLE["disciplines.md"] = "Disciplines"
  ROLE["assumptions.md"] = "Assumptions"; ROLE["decisions.md"] = "Decisions"
  ROLE["plan.md"] = "Plan"

  # brief.md required sections in relative order; Tracks is conditional on the
  # venture declaring tracks and is handled inside the walk.
  nreq = split("Opportunity|Success metric|Appetite|Kill criteria|Tracks|Existing alternatives|Business viability|Strategy fit|Sources|Gate log|Changelog", REQSEC, "|")
  split("Appetite|Existing alternatives|Business viability|Strategy fit", t, "|"); for (i in t) PROMPT[t[i]] = 1
  nopp = split("Framing|Who hurts|No-gos & sketch|Chain", OPPF, "|")

  nasm = split("Statement|Risk-if-wrong|Risk-tag|Threshold|Evidence|Blocking|Tasks|Status", ASMF, "|")
  ndec = split("Status|Door|Discipline|Deciders|Options|Outcome|Consequences|Feed-forward", DECF, "|")
  nplan = split("Kind|Tests|Done when|Cap|Status", PLANF, "|")
  ngate = split("Outcome|Date|Decider|Evidence|Thresholds|Kill-criteria|Rationale", GATEF, "|")

  DATE = "^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$"

  # The status declarations, read through the lib and handed over as raw
  # environment values. `!dup` means the header block declared it more than
  # once, which has no honest positional winner and is reported as absent.
  nfiles = split("brief.md disciplines.md assumptions.md decisions.md plan.md", FL, " ")
  for (i = 1; i <= nfiles; i++) ST[FL[i]] = ENVIRON["INC_ST_" i]
}

FNR == 1 {
  flush_field()   # the previous file may have ended mid-entry
  n = split(FILENAME, p, "/"); file = p[n]
  past = 0; sect = ""; cur_kind = ""; cur_id = ""; cur_field = ""
  seen_title = 0
}
'"$spec_parse_awk_fence"'

# The leading header region, delimited exactly as the lib delimits it, so this
# pass and the lib cannot disagree about where a header block ends. Only
# `Last reviewed:` is read here; the lib owns the other two declarations.
!past {
  if ($0 ~ /^[ \t]*$/ || $0 ~ /^# / || $0 ~ /^\*\*[^*]+:\*\*/) {
    if (!seen_title && $0 ~ /^# /) {
      seen_title = 1
      ttl = $0; sub(/^# /, "", ttl); sub(/[ \t]+$/, "", ttl)
      if (ttl !~ ("— " ROLE[file] "$"))
        emit("HDR-ROLE", file, "title line must end with the file role token \"" ROLE[file] "\"")
    } else if ($0 ~ /^\*\*Last reviewed:\*\*/) {
      v = $0; sub(/^\*\*Last reviewed:\*\*[ \t]*/, "", v); v = trim(v)
      if (!has(RV, file)) RV[file] = v
    }
    next
  }
  past = 1
}

/^## / {
  flush_field(); cur_kind = ""
  sect = $0; sub(/^## /, "", sect); sect = trim(sect)
  if (file == "brief.md") { if (!has(BSECPOS, sect)) BSECPOS[sect] = ++bsecidx }
  else if (file == "disciplines.md") DSEC[sect] = ++dsecidx
  next
}

/^### / {
  flush_field()
  head = $0; sub(/^### /, "", head); head = trim(head)
  if (file == "assumptions.md") start_entry("A", head)
  else if (file == "decisions.md") start_entry("DEC", head)
  else if (file == "plan.md") start_entry("T", head)
  else if (file == "brief.md" && sect == "Gate log") start_gate(head)
  else cur_kind = ""
  next
}

# Sources and Tracks bullets carry a bold NAME, not a bold FIELD, so they are
# routed before the field-bullet rule below.
file == "brief.md" && sect == "Sources" && /^[ \t]*- / {
  if ($0 ~ /^- \*\*[^*]+\*\* — /) SRCN++
  else srcbad($0)
  next
}
file == "brief.md" && sect == "Tracks" && /^- / { track_bullet($0); next }
file == "brief.md" && sect == "Kill criteria" && /^- / {
  if ($0 ~ /^- \*\*KC-[^:*]*:\*\* /) kc_bullet($0)
  else emit("KC-FORM", "brief.md", "kill criterion \"" substr(trim($0), 1, 60) "\" is not `- **KC-<n>:** <state> — by <date>`")
  next
}

/^- \*\*[^*]+:\*\*/ {
  flush_field()
  name = $0; sub(/^- \*\*/, "", name); sub(/:\*\*.*$/, "", name)
  val = $0; sub(/^- \*\*[^*]+:\*\*[ \t]?/, "", val)
  if (cur_kind != "") { cur_field = name; cur_val = trim(val) }
  else if (file == "brief.md" && sect == "Opportunity") {
    OPPV[name] = trim(val); OPPSEEN[name] = 1
  }
  next
}

/^  - / {
  if (cur_kind != "" && cur_field != "") SUBCNT[cur_kind, cur_id, cur_field]++
  next
}
/^  [^ ]/ {
  if (cur_kind != "" && cur_field != "") cur_val = cur_val " " trim($0)
  next
}

file == "brief.md" && sect == "Kill criteria" && /^\*\*Gate decider:\*\* / {
  v = $0; sub(/^\*\*Gate decider:\*\*[ \t]*/, "", v); GATEDECIDER = trim(v); next
}

file == "brief.md" && sect == "Gate log" && cur_kind == "GATE" && /^[A-Z][A-Za-z-]*: / {
  if (has(GFIELD, cur_id SUBSEP "Rationale")) next   # Rationale runs to block end
  k = $0; sub(/:.*$/, "", k)
  v = $0; sub(/^[A-Z][A-Za-z-]*:[ \t]?/, "", v)
  if (!has(GFIELD, cur_id SUBSEP k)) GFIELD[cur_id SUBSEP k] = trim(v)
  next
}

file == "disciplines.md" && /^\|/ {
  if ($0 ~ /^\|[ -]+\|/ && $0 ~ /---/) next
  nc = split($0, c, /[ \t]*\|[ \t]*/)
  for (i = 1; i <= nc; i++) c[i] = trim(c[i])
  if (sect == "Discipline map") {
    if (c[2] == "Discipline" || nc < 5) next
    DISC[c[2]] = 1; DISCDEC[c[2]] = c[4]
  } else if (sect == "Staffing table") {
    if (c[2] == "Discipline" || nc < 5) next
    STAFFED[c[2]] = 1
    if (!(c[3] in STAFF))
      emit("DIS-STAFFING-TOKEN", "disciplines.md", "staffing token \"" c[3] "\" for " c[2] " is not agent-persona, named-human, or unstaffed")
  } else if (sect == "Stakeholder map") {
    if (c[2] == "Decision area" || nc < 6) next
    AREA[c[2]] = 1
    if (c[3] == "" || c[3] == "none" || index(c[3], ",") > 0)
      emit("STK-DECIDES-SINGLE", "disciplines.md", "the Decides cell for \"" c[2] "\" must hold exactly one name")
    else DECIDES[c[3]] = 1
  }
  next
}

file == "brief.md" && sect != "" {
  if ($0 ~ /^_Skipped: .+\._$/) BSKIP[sect] = 1
  else if (trim($0) != "") BBODY[sect] = 1
}

END {
  flush_field()

  brief_status = ST["brief.md"]
  if (brief_status == "!dup" || brief_status == "!err") brief_status = ""
  for (i = 1; i <= nfiles; i++) {
    f = FL[i]
    st = ST[f]
    if (st == "" || st == "!dup" || st == "!err")
      emit("HDR-STATUS", f, "no single Status declaration in the header block")
    else if (!(st in STATUS))
      emit("HDR-STATUS", f, "status \"" st "\" is not one of Exploring, On-hold, Graduated, Killed, Abandoned")
    else if (f != "brief.md" && brief_status != "" && st != brief_status)
      emit("HDR-STATUS-MIRROR", f, "status \"" st "\" does not mirror brief.md (\"" brief_status "\")")
    rv = RV[f]
    if (rv !~ DATE)
      emit("HDR-REVIEWED", f, "Last reviewed must be a YYYY-MM-DD date (found \"" rv "\")")
  }

  FILEOF["A"] = "assumptions.md"; FILEOF["DEC"] = "decisions.md"
  FILEOF["T"] = "plan.md"; FILEOF["KC"] = "brief.md"
  np = split("A DEC T KC", PF, " ")
  for (pi = 1; pi <= np; pi++) {
    pfx = PF[pi]
    for (i = 1; i <= COUNT[pfx]; i++) {
      id = ORDER[pfx, i]
      tgt = (pfx == "KC") ? SUPTGT[pfx SUBSEP id] : F[pfx SUBSEP id SUBSEP "Superseded-by"]
      if (tgt == "") continue
      sub(/[ \t].*$/, "", tgt)
      SUPERSEDED[pfx SUBSEP id] = 1
      if (!id_ok(pfx, tgt) || !has(IDSEEN, pfx SUBSEP tgt))
        emit("ID-SUPERSEDE-TARGET", FILEOF[pfx], id " is superseded by \"" tgt "\", which is not an existing " pfx "-<n> entry")
    }
  }

  tracked = (TRACKN > 0)

  for (i = 1; i <= COUNT["A"]; i++) {
    id = ORDER["A", i]
    for (j = 1; j <= nasm; j++)
      if (!has(FSEEN, "A" SUBSEP id SUBSEP ASMF[j]))
        emit("ASM-FIELD-MISSING", "assumptions.md", id " is missing the " ASMF[j] " field")
    if (has(FSEEN, "A" SUBSEP id SUBSEP "Statement"))
      if (F["A" SUBSEP id SUBSEP "Statement"] !~ /believe .*; *verify .*; *measure .*; *right if /)
        emit("ASM-STATEMENT-SKELETON", "assumptions.md", id " must read `believe <claim>; verify <test>; measure <observable>; right if <condition>.`")
    tag = F["A" SUBSEP id SUBSEP "Risk-tag"]
    if (has(FSEEN, "A" SUBSEP id SUBSEP "Risk-tag") && !(tag in RISKTAG))
      emit("ASM-RISK-TAG", "assumptions.md", id " risk tag \"" tag "\" is not value, usability, feasibility, or viability")
    RTAG[id] = tag
    blk = F["A" SUBSEP id SUBSEP "Blocking"]
    if (has(FSEEN, "A" SUBSEP id SUBSEP "Blocking") && blk != "yes" && blk != "no")
      emit("ASM-BLOCKING", "assumptions.md", id " blocking flag \"" blk "\" is not yes or no")
    ABLOCK[id] = blk
    ev = F["A" SUBSEP id SUBSEP "Evidence"]
    grade = ev; sub(/ —.*$/, "", grade); grade = trim(grade)
    if (has(FSEEN, "A" SUBSEP id SUBSEP "Evidence") && ev != "none" && !(grade in GRADE))
      emit("ASM-GRADE", "assumptions.md", id " evidence grade \"" grade "\" is not on the ladder (synthetic, opinion, stated-intent, costly-signal, behavior)")
    AGRADE[id] = (ev == "none") ? "none" : grade
    st = F["A" SUBSEP id SUBSEP "Status"]
    stw = st; sub(/ —.*$/, "", stw); stw = trim(stw)
    if (has(FSEEN, "A" SUBSEP id SUBSEP "Status")) {
      if (!(stw in ASTATUS))
        emit("ASM-STATUS", "assumptions.md", id " status \"" stw "\" is not open, testing, validated, invalidated, or waived")
      else if (stw == "waived" && st !~ /^waived — .+/)
        emit("ASM-WAIVED-REASON", "assumptions.md", id " is waived and must record its reason as `waived — <reason>`")
      else if ((stw == "validated" || stw == "invalidated") \
        && (F["A" SUBSEP id SUBSEP "Threshold"] == "none" || ev == "none"))
        emit("ASM-EVIDENCE-REQUIRED", "assumptions.md", id " is " stw " and must carry a real threshold and cited, graded evidence")
    }
    if (!has(SUPERSEDED, "A" SUBSEP id)) ALIVE[id] = 1
    tk = F["A" SUBSEP id SUBSEP "Tasks"]
    if (tk != "" && tk != "none") {
      m = split(tk, refs, /[,;] */)
      for (r = 1; r <= m; r++) {
        ref = trim(refs[r]); if (ref == "") continue
        if (!id_ok("T", ref) || !has(IDSEEN, "T" SUBSEP ref))
          emit("ASM-TASK-REF", "assumptions.md", id " links task \"" ref "\", which is not a plan task")
      }
    }
    check_track("assumptions.md", "A", id)
  }

  for (i = 1; i <= COUNT["DEC"]; i++) {
    id = ORDER["DEC", i]
    for (j = 1; j <= ndec; j++)
      if (!has(FSEEN, "DEC" SUBSEP id SUBSEP DECF[j]))
        emit("DEC-FIELD-MISSING", "decisions.md", id " is missing the " DECF[j] " field")
    st = F["DEC" SUBSEP id SUBSEP "Status"]
    if (has(FSEEN, "DEC" SUBSEP id SUBSEP "Status") && !(st in DSTATUS))
      emit("DEC-STATUS", "decisions.md", id " status \"" st "\" is not open, decided, or deferred")
    dr = F["DEC" SUBSEP id SUBSEP "Door"]
    if (has(FSEEN, "DEC" SUBSEP id SUBSEP "Door") && dr != "one-way" && dr != "two-way")
      emit("DEC-DOOR", "decisions.md", id " door class \"" dr "\" is not one-way or two-way")
    if (has(FSEEN, "DEC" SUBSEP id SUBSEP "Options") && SUBCNT["DEC", id, "Options"] < 1)
      emit("DEC-OPTIONS", "decisions.md", id " lists no considered options")
    dsc = F["DEC" SUBSEP id SUBSEP "Discipline"]
    if (has(FSEEN, "DEC" SUBSEP id SUBSEP "Discipline") && !(dsc in DISC))
      emit("DEC-DISCIPLINE-UNKNOWN", "decisions.md", id " owning discipline \"" dsc "\" is not in the discipline map")
    dd = F["DEC" SUBSEP id SUBSEP "Deciders"]
    if (dd != "" && dd != "none") {
      m = split(dd, names, /, */)
      for (r = 1; r <= m; r++) {
        nm = trim(names[r])
        if (nm != "" && !(nm in DECIDES))
          emit("DEC-DECIDER-UNKNOWN", "decisions.md", id " names decider \"" nm "\", who holds no Decides cell in the stakeholder map")
      }
    }
    check_track("decisions.md", "DEC", id)
  }

  for (i = 1; i <= COUNT["T"]; i++) {
    id = ORDER["T", i]
    for (j = 1; j <= nplan; j++)
      if (!has(FSEEN, "T" SUBSEP id SUBSEP PLANF[j]))
        emit("PLAN-FIELD-MISSING", "plan.md", id " is missing the " PLANF[j] " field")
    kd = F["T" SUBSEP id SUBSEP "Kind"]
    if (has(FSEEN, "T" SUBSEP id SUBSEP "Kind") && !(kd in KIND))
      emit("PLAN-KIND", "plan.md", id " kind \"" kd "\" is not spike, research, analysis, demand-signal, or alignment")
    st = F["T" SUBSEP id SUBSEP "Status"]
    if (has(FSEEN, "T" SUBSEP id SUBSEP "Status") && !(st in TSTATUS))
      emit("PLAN-STATUS", "plan.md", id " status \"" st "\" is not planned, running, delivered, accepted, or dropped")
    tt = F["T" SUBSEP id SUBSEP "Tests"]
    if (!has(FSEEN, "T" SUBSEP id SUBSEP "Tests")) { }   # already a missing-field finding
    else if (tt == "" || tt == "none")
      emit("PLAN-TESTS-EMPTY", "plan.md", id " traces to no assumption or decision")
    else {
      m = split(tt, refs, /[,;] */)
      for (r = 1; r <= m; r++) {
        ref = trim(refs[r]); if (ref == "") continue
        ok = (id_ok("A", ref) && has(IDSEEN, "A" SUBSEP ref)) || (id_ok("DEC", ref) && has(IDSEEN, "DEC" SUBSEP ref))
        if (!ok)
          emit("PLAN-TESTS-REF", "plan.md", id " traces to \"" ref "\", which is not an A-<n> or DEC-<n> entry")
      }
    }
    tg = F["T" SUBSEP id SUBSEP "Target"]
    hastg = has(FSEEN, "T" SUBSEP id SUBSEP "Target")
    if (kd == "alignment" && !hastg)
      emit("PLAN-TARGET", "plan.md", id " is an alignment task and must name a stakeholder-map decision area")
    else if (kd != "alignment" && hastg)
      emit("PLAN-TARGET", "plan.md", id " carries a Target but is not an alignment task")
    else if (hastg && !(tg in AREA))
      emit("PLAN-TARGET", "plan.md", id " target \"" tg "\" is not a decision area in the stakeholder map")
    check_track("plan.md", "T", id)
  }

  ndis = split("Discipline map|Staffing table|Stakeholder map", DSECL, "|")
  last = 0
  for (i = 1; i <= ndis; i++) {
    if (!(DSECL[i] in DSEC)) { emit("DIS-SECTION", "disciplines.md", "the `## " DSECL[i] "` section is absent"); continue }
    if (DSEC[DSECL[i]] < last)
      emit("DIS-SECTION", "disciplines.md", "`## " DSECL[i] "` appears out of its required order")
    last = DSEC[DSECL[i]]
  }
  for (d in DISC) {
    if (!(d in STAFFED))
      emit("DIS-STAFFING-COVERAGE", "disciplines.md", "discipline \"" d "\" has no staffing row")
    cell = DISCDEC[d]
    if (cell != "" && cell != "none") {
      m = split(cell, refs, /, */)
      for (r = 1; r <= m; r++) {
        ref = trim(refs[r]); if (ref == "") continue
        if (!id_ok("DEC", ref) || !has(IDSEEN, "DEC" SUBSEP ref))
          emit("DIS-DECISION-REF", "disciplines.md", "discipline \"" d "\" cites \"" ref "\", which is not a DEC-<n> entry")
      }
    }
  }

  last = 0
  for (i = 1; i <= nreq; i++) {
    s = REQSEC[i]
    if (s == "Tracks") {
      if (tracked && !(s in BSECPOS))
        emit("BRIEF-SECTION-MISSING", "brief.md", "the `## Tracks` section is absent")
    } else if (!(s in BSECPOS)) {
      emit("BRIEF-SECTION-MISSING", "brief.md", "the `## " s "` section is absent")
      continue
    }
    if (!(s in BSECPOS)) continue
    if (BSECPOS[s] < last)
      emit("BRIEF-SECTION-ORDER", "brief.md", "`## " s "` appears out of its required order")
    last = BSECPOS[s]
  }
  for (s in BSECPOS) {
    if (s in PROMPT) {
      if (!(s in BBODY) && !(s in BSKIP))
        emit("BRIEF-SKIP-FORM", "brief.md", "prompt section `## " s "` is empty; a skipped prompt states `_Skipped: <reason>._`")
    } else if (s in BSKIP)
      emit("BRIEF-SKIP-FORM", "brief.md", "`## " s "` is structural, not a prompt; it cannot be skipped")
  }
  for (i = 1; i <= nopp; i++)
    if (!(OPPF[i] in OPPSEEN))
      emit("BRIEF-SECTION-MISSING", "brief.md", "the Opportunity field `" OPPF[i] "` is absent")
  if (("Success metric" in BSECPOS) && (!("Success metric" in BBODY) || ("Success metric" in BSKIP)))
    emit("BRIEF-METRIC-EMPTY", "brief.md", "the success metric is part of the minimum core and cannot be skipped or left empty")
  if (COUNT["KC"] == 0)
    emit("KC-MISSING", "brief.md", "the minimum core requires at least one kill criterion as a state-plus-date pair")
  if (GATEDECIDER == "")
    emit("KC-DECIDER-MISSING", "brief.md", "the `## Kill criteria` section must open with `**Gate decider:** <name>`")
  else if (!(GATEDECIDER in DECIDES))
    emit("KC-DECIDER-UNKNOWN", "brief.md", "gate decider \"" GATEDECIDER "\" holds no Decides cell in the stakeholder map")
  for (l in TRACK) if (!(l in TRACKDONE)) TRACKLIVE[l] = 1

  for (i = 1; i <= gaten; i++) {
    num = GATEN[i]
    if (num + 0 != i)
      emit("GATE-SEQUENCE", "brief.md", "gate records must be numbered sequentially from 1 (found Gate " num " in position " i ")")
    for (j = 1; j <= ngate; j++) {
      if (GATEF[j] == "Tracks") continue
      if (!has(GFIELD, num SUBSEP GATEF[j]))
        emit("GATE-FIELD-MISSING", "brief.md", "Gate " num " is missing the `" GATEF[j] ":` line")
    }
    if (has(GFIELD, num SUBSEP "Date") && GFIELD[num SUBSEP "Date"] != GATEDATE[num])
      emit("GATE-DATE-MISMATCH", "brief.md", "Gate " num " heading date " GATEDATE[num] " and `Date: " GFIELD[num SUBSEP "Date"] "` disagree")
    oc = GFIELD[num SUBSEP "Outcome"]
    if (has(GFIELD, num SUBSEP "Outcome") && !(oc in OUTCOME))
      emit("GATE-OUTCOME", "brief.md", "Gate " num " outcome \"" oc "\" is not Graduate, Hold, Recycle, or Kill")
    dc = GFIELD[num SUBSEP "Decider"]
    if (has(GFIELD, num SUBSEP "Decider") && GATEDECIDER != "" && dc != GATEDECIDER)
      emit("GATE-DECIDER", "brief.md", "Gate " num " decider \"" dc "\" is not the venture gate decider (\"" GATEDECIDER "\")")

    ev = GFIELD[num SUBSEP "Evidence"]
    if (ev != "" && ev != "none") {
      m = split(ev, items, /, */)
      for (r = 1; r <= m; r++) {
        it = trim(items[r]); if (it == "") continue
        aid = it; sub(/[ \t].*$/, "", aid)
        g = it; sub(/^[^(]*\(/, "", g); sub(/\).*$/, "", g)
        if (it !~ /^[A-Z]+-[1-9][0-9]* \(.+\)$/ || !has(IDSEEN, "A" SUBSEP aid) || !(g in GRADE))
          emit("GATE-EVIDENCE-FORM", "brief.md", "Gate " num " evidence item \"" it "\" is not `A-<n> (<grade>)` naming an existing assumption and a ladder grade")
      }
    }

    split("", TSEEN, " ")
    th = GFIELD[num SUBSEP "Thresholds"]
    if (th != "" && th != "none") {
      m = split(th, items, /, */)
      for (r = 1; r <= m; r++) {
        it = trim(items[r]); if (it == "") continue
        aid = it; sub(/[ \t].*$/, "", aid)
        vd = it; sub(/^[^ \t]*[ \t]*/, "", vd)
        if (!(vd in VERDICT))
          emit("GATE-THRESHOLD-TOKEN", "brief.md", "Gate " num " threshold \"" it "\" must read `A-<n> pass|fail|waived|open`")
        TSEEN[aid] = vd
      }
    }
    for (a in ALIVE) {
      if (ABLOCK[a] != "yes") continue
      if (!(a in TSEEN))
        emit("GATE-THRESHOLD-COVERAGE", "brief.md", "Gate " num " Thresholds must cover live blocking assumption " a)
      else if (oc == "Graduate" && TSEEN[a] == "open")
        emit("GATE-GRADUATE-OPEN", "brief.md", "Gate " num " records Graduate while blocking assumption " a " is unevaluated")
    }
    if (oc == "Graduate")
      for (a in TSEEN)
        if (TSEEN[a] == "pass" && AGRADE[a] == "synthetic" && (RTAG[a] == "value" || RTAG[a] == "usability"))
          emit("GATE-SYNTHETIC-DESIRABILITY", "brief.md", "Gate " num " passes desirability assumption " a " on synthetic evidence, which cannot satisfy a Graduate threshold")

    split("", KSEEN, " ")
    kcl = GFIELD[num SUBSEP "Kill-criteria"]
    if (kcl != "" && kcl != "none") {
      m = split(kcl, items, /, */)
      for (r = 1; r <= m; r++) {
        it = trim(items[r]); if (it == "") continue
        kid = it; sub(/[ \t].*$/, "", kid)
        stt = it; sub(/^[^ \t]*[ \t]*/, "", stt)
        if (!(stt in KCSTATE))
          emit("GATE-KC-TOKEN", "brief.md", "Gate " num " kill-criterion state \"" it "\" must read `KC-<n> clear|approaching|tripped`")
        KSEEN[kid] = 1
      }
    }
    for (k = 1; k <= COUNT["KC"]; k++) {
      kid = ORDER["KC", k]
      if (has(SUPERSEDED, "KC" SUBSEP kid)) continue
      if (!(kid in KSEEN))
        emit("GATE-KC-COVERAGE", "brief.md", "Gate " num " Kill-criteria must cover live criterion " kid)
    }

    hastr = has(GFIELD, num SUBSEP "Tracks")
    if (tracked && !hastr)
      emit("GATE-TRACKS-PRESENCE", "brief.md", "Gate " num " must carry a `Tracks:` line in a tracked venture")
    else if (!tracked && hastr)
      emit("GATE-TRACKS-PRESENCE", "brief.md", "Gate " num " carries a `Tracks:` line but the venture declares no tracks")
    if (tracked && hastr) {
      split("", TRSEEN, " ")
      m = split(GFIELD[num SUBSEP "Tracks"], items, /, */)
      for (r = 1; r <= m; r++) {
        it = trim(items[r]); if (it == "") continue
        lb = it; sub(/=.*$/, "", lb)
        TRSEEN[lb] = 1
      }
      for (l in TRACKLIVE)
        if (!(l in TRSEEN))
          emit("GATE-TRACKS-COVERAGE", "brief.md", "Gate " num " Tracks must cover live track \"" l "\"")
    }
    if (oc == "Graduate" && tracked && i == gaten)
      for (l in TRACKLIVE)
        emit("GATE-GRADUATE-LIVE-TRACK", "brief.md", "Gate " num " records a top-level Graduate while track \"" l "\" is still live")
    if (i == gaten) LASTOUT = oc
  }

  # Only the closing outcomes bind: Hold and Recycle leave the venture live,
  # and an On-hold venture resumes to Exploring by operator act, so neither
  # direction of that pair is checkable.
  if (LASTOUT != "" && brief_status != "") {
    if (LASTOUT == "Kill" && brief_status != "Killed")
      emit("LIFE-STATUS-OUTCOME", "brief.md", "the latest gate outcome is Kill but the venture status is \"" brief_status "\"")
    else if (LASTOUT == "Graduate" && brief_status != "Graduated")
      emit("LIFE-STATUS-OUTCOME", "brief.md", "the latest gate outcome is Graduate but the venture status is \"" brief_status "\"")
    else if (brief_status == "Killed" && LASTOUT != "Kill")
      emit("LIFE-STATUS-OUTCOME", "brief.md", "the venture status is Killed but the latest gate outcome is \"" LASTOUT "\"")
    else if (brief_status == "Graduated" && LASTOUT != "Graduate")
      emit("LIFE-STATUS-OUTCOME", "brief.md", "the venture status is Graduated but the latest gate outcome is \"" LASTOUT "\"")
  }
}
' "$target/brief.md" "$target/disciplines.md" "$target/assumptions.md" \
  "$target/decisions.md" "$target/plan.md" >"$work/findings" || exit 2

while IFS="$tab" read -r code fname msg; do
  [ -n "$code" ] || continue
  report "$code" "$fname" "$msg"
done <"$work/findings"

# --- 3. Baseline mode: the stakeholder-commit guard (REQ-G1.5) --------------

if [ -n "$baseline" ]; then
  if ! top=$(git -C "$target" rev-parse --show-toplevel 2>/dev/null); then
    echo "inception-validate: --baseline needs a git work tree; the bundle directory is not inside one" >&2
    exit 2
  fi
  if ! git -C "$target" rev-parse --verify --quiet "$baseline^{commit}" >/dev/null 2>&1; then
    echo "inception-validate: --baseline ref does not resolve to a commit" >&2
    exit 2
  fi
  prefix=$(git -C "$target" rev-parse --show-prefix 2>/dev/null) || exit 2

  mkdir -p "$work/base" || exit 2
  missing_base=0
  for f in $BUNDLE_FILES; do
    if ! git -C "$top" show "$baseline:${prefix}$f" >"$work/base/$f" 2>/dev/null; then
      missing_base=1
    fi
  done

  # Ids and gate-record bodies, extracted identically from both sides so the
  # comparison is of content and not of formatting noise. The venture status
  # comes from the lib on each side rather than from this sweep.
  extract() {
    awk "$spec_parse_awk_fence"'
      FNR == 1 { n = split(FILENAME, p, "/"); f = p[n]; sect = ""; ingate = 0; cur = "" }
      /^## / { sect = $0; sub(/^## /, "", sect); sub(/[ \t]+$/, "", sect); ingate = (sect == "Gate log"); cur = ""; next }
      /^### / {
        h = $0; sub(/^### /, "", h); sub(/[ \t]+$/, "", h)
        if (ingate) { cur = h; sub(/ —.*$/, "", cur); sub(/^Gate /, "", cur); print "gate\t" cur "\t" h; next }
        id = h; sub(/ —.*$/, "", id); sub(/[ \t]+$/, "", id)
        cur = ""; print "id\t" f "\t" id; next
      }
      /^- \*\*KC-[^:*]*:\*\* / { id = $0; sub(/^- \*\*/, "", id); sub(/:\*\*.*$/, "", id); print "id\t" f "\t" id; next }
      ingate && cur != "" && NF { print "gate\t" cur "\t" $0 }
    ' "$1/brief.md" "$1/disciplines.md" "$1/assumptions.md" "$1/decisions.md" "$1/plan.md"
  }

  if [ "$missing_base" -ne 0 ]; then
    # A bundle that did not exist at the baseline has nothing to be compared
    # against — the first PR of a new venture. Say so rather than reporting a
    # silent clean pass on checks that never ran (REQ-K1.7).
    echo "inception-validate: the bundle is absent or partial at the baseline ref; the stakeholder-commit comparison was skipped" >&2
  else
    extract "$work/base" >"$work/base.txt"
    extract "$target" >"$work/head.txt"

    awk -F"$tab" '$1 == "id"' "$work/base.txt" | sort -u >"$work/ids.base"
    awk -F"$tab" '$1 == "id"' "$work/head.txt" | sort -u >"$work/ids.head"
    comm -23 "$work/ids.base" "$work/ids.head" >"$work/ids.gone"
    while IFS="$tab" read -r _ vfile vid; do
      [ -n "${vid:-}" ] || continue
      report BASE-ID-VANISHED "$vfile" \
        "$vid was present at the baseline and is gone from the working tree; ids are stable forever"
    done <"$work/ids.gone"

    awk -F"$tab" '$1 == "gate" { print $2 }' "$work/base.txt" | sort -u >"$work/gates.base"
    while read -r g; do
      [ -n "$g" ] || continue
      bb=$(awk -F"$tab" -v g="$g" '$1 == "gate" && $2 == g { print $3 }' "$work/base.txt")
      hh=$(awk -F"$tab" -v g="$g" '$1 == "gate" && $2 == g { print $3 }' "$work/head.txt")
      if [ "$bb" != "$hh" ]; then
        report BASE-GATE-MUTATED brief.md \
          "Gate $g was edited or removed; recorded gate runs are append-only"
      fi
    done <"$work/gates.base"

    bstatus=$(spec_parse_header_value "$work/base/brief.md" Status 2>/dev/null) || bstatus=
    hstatus=$(spec_parse_header_value "$target/brief.md" Status 2>/dev/null) || hstatus=
    case $bstatus in
      Graduated | Killed | Abandoned)
        if [ "$bstatus" != "$hstatus" ]; then
          report BASE-STATUS-TRANSITION brief.md \
            "the venture was $bstatus at the baseline; there is no transition out of a terminal status"
        fi
        ;;
    esac
  fi
fi

printf 'inception-validate: %d error(s)\n' "$err"
[ "$err" -eq 0 ]
