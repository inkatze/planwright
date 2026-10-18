#!/bin/sh
# inception-fanout.sh — the mechanical half of the /inception persona fan-out
# (inception Task 9; REQ-P1.3–P1.9, REQ-B1.3 · D-2, D-3, D-4, D-6, D-7, D-18).
#
# doctrine/persona-fanout.md is the procedure; this script is everything in it
# that must come out the same on every run. The skill holds the gates and
# dispatches the seats; it never assembles a seat brief, a synthesis input, or
# an attributed table by hand.
#
#   frame <venture>             compile exports/frame.md, the normative frame
#   triage <venture>            the stake-scored seat count, three to five
#   roster --run <dir> --backend <b> --seat <spec>... <venture>
#                               fix the seats and print the Gate 1 disclosure;
#                               <spec> is <card-id>[:<pole>][@<model>]
#   brief [--deliver-file] --run <dir> <seat-id> <venture>
#                               one seat's brief: card framing plus the frame
#   check-seat <artifact>...    the typed escalation section ends every artifact
#   anonymize --run <dir>       the blind, order-shuffled synthesis input, and
#                               the orchestrator's label map beside it
#   synthesis-brief [--deliver-file] --run <dir> <venture>
#   challenge-brief [--deliver-file] --run <dir> <venture>
#   amend-brief [--deliver-file] --run <dir> <venture>
#                               the three persona-free prompts; the amendment
#                               is offered once. Each prompt ends by asking for
#                               its document as the final answer, or with
#                               --deliver-file written to the run file the next
#                               step reads (for a rung that hands nothing back)
#   check-synthesis [--run <dir>] <synthesis>
#                               the mandatory table's shape and blindness
#   attribute --run <dir>       re-attach seat attribution into the final table
#   gate2 --run <dir>           the escalations as typed human-power choices
#   record --run <dir> <venture>
#                               copy the run into <venture>/fanout/<date>-<n>/
#   staff [--no-stake <discipline>]... <venture>
#                               auto-file unstaffed disciplines as coverage
#                               risks, collapsed on a zero-seat run
#
# A run directory belongs to the orchestrator (a fresh `mktemp -d`, outside the
# venture). Its files, by the step that writes them: roster.tsv and backend
# (roster), seat-<n>.md (the skill, one per returned seat), synthesis-input.md
# and labels.tsv (anonymize), synthesis.md, challenge.md, and amended.md (the
# skill, from the persona-free sessions), table.md (attribute). Only
# synthesis-input.md ever reaches the synthesis writer, so the writer works
# blind while labels.tsv, the seat-to-label map, stays with the orchestrator.
#
# Output is `key<TAB>value` lines wherever a caller parses it; prompts and
# documents go to stdout or to the named file. Text that came from a seat or a
# bundle is stripped of control characters before it reaches the terminal.
#
# Exit: 0 success · 1 findings (check-seat, check-synthesis, or an input that
#   fails them), an unknown or unusable card, or a second amendment · 2 usage
#   or environment error (a missing frame, run file, or helper; a refused path)
#   · 3 the validator refuses the bundle (passed through) · 5 the file a step
#   writes already exists (never overwritten).
#
# Environment: PLANWRIGHT_INCEPTION_TODAY (YYYY-MM-DD) pins today's date;
#   PLANWRIGHT_FANOUT_SEED (digits) pins the shuffle, for tests.
#
# Portable POSIX sh + awk; bash 3.2 / BSD tooling floor (REQ-K1.5).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

self_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2

# The column-0 fence rule is the meta-spec's grammar, which the inception
# format inherits, so every reader that skips fenced lines takes the shared
# lexer. The three that must carry fenced lines through (card sections, the
# anonymized inputs, the attributed table) and the blind-synthesis check, which
# scans fenced lines for identity too, keep the same toggle inline; see the
# FENCE_EXEMPT note in tests/test-spec-parse-corpus.sh. Sourced, never run.
if [ ! -f "$self_dir/spec-parse.sh" ] || [ ! -r "$self_dir/spec-parse.sh" ]; then
  printf '%s\n' "inception-fanout: required helper $self_dir/spec-parse.sh missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/spec-parse.sh
. "$self_dir/spec-parse.sh" || exit 2

# Planning figures for the Gate 1 cost line, in tokens. They are estimates the
# operator weighs before spawning, not a meter.
SEAT_TOKENS=40000
SYNTH_TOKENS=50000
CHALLENGE_TOKENS=30000
AMEND_TOKENS=55000
MAX_SEATS=5

TABLE_HEADER='| Decision | Tier and reason | Owning role | Evidence needed | Trigger | Powers |'
TABLE_RULE='| --- | --- | --- | --- | --- | --- |'
SYNTH_HEADER='| Kind | Claim | Claim type | Convergence | Outliers | Grounding |'

usage() {
  cat >&2 <<'EOF'
usage: inception-fanout.sh frame <venture-dir>
       inception-fanout.sh triage <venture-dir>
       inception-fanout.sh roster --run <dir> --backend <backend> --seat <card-id>[:<pole>][@<model>]... <venture-dir>
       inception-fanout.sh brief [--deliver-file] --run <dir> <seat-id> <venture-dir>
       inception-fanout.sh check-seat <artifact>...
       inception-fanout.sh anonymize --run <dir>
       inception-fanout.sh synthesis-brief [--deliver-file] --run <dir> <venture-dir>
       inception-fanout.sh challenge-brief [--deliver-file] --run <dir> <venture-dir>
       inception-fanout.sh amend-brief [--deliver-file] --run <dir> <venture-dir>
       inception-fanout.sh check-synthesis [--run <dir>] <synthesis>
       inception-fanout.sh attribute --run <dir>
       inception-fanout.sh gate2 --run <dir>
       inception-fanout.sh record --run <dir> <venture-dir>
       inception-fanout.sh staff [--no-stake <discipline>]... <venture-dir>
EOF
  exit 2
}

die() {
  printf 'inception-fanout: %s\n' "$2" >&2
  exit "$1"
}

tmp_path=
trap '[ -z "$tmp_path" ] || rm -rf "$tmp_path"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

today() {
  t=${PLANWRIGHT_INCEPTION_TODAY:-$(date +%Y-%m-%d)}
  case $t in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) printf '%s' "$t" ;;
    *) die 2 "PLANWRIGHT_INCEPTION_TODAY must be YYYY-MM-DD" ;;
  esac
}

# Seat and bundle text is untrusted: no control character reaches a terminal.
clean() { tr -d '\000-\010\013-\037\177'; }

abs_dir() {
  d=$1
  while [ "$d" != "${d%/}" ]; do d=${d%/}; done
  [ -n "$d" ] || d=/
  [ ! -h "$d" ] || die 2 "refusing a symbolic link: $d"
  [ -d "$d" ] || die 2 "not a directory: $d"
  (cd "$d" && pwd -P) || die 2 "cannot resolve $d"
}

# A venture directory, version-gated by the validator (REQ-C1.7) before any
# read, its bundle files and output directories never followed through a link.
venture=
open_venture() {
  [ -n "${1:-}" ] || usage
  venture=$(abs_dir "$1") || exit 2
  for e in exports fanout brief.md disciplines.md assumptions.md decisions.md plan.md; do
    [ ! -h "$venture/$e" ] || die 2 "$e is a symbolic link; refusing to follow it"
  done
  [ -r "$self_dir/inception-validate.sh" ] || die 2 "the validator is missing at $self_dir/inception-validate.sh"
  vrc=0
  /bin/sh "$self_dir/inception-validate.sh" --version-check "$venture" || vrc=$?
  if [ "$vrc" -eq 3 ]; then
    die 3 "the validator refused this bundle above; nothing was read or written"
  elif [ "$vrc" -ne 0 ]; then
    exit 2
  fi
}

run=
open_run() {
  [ -n "${1:-}" ] || usage
  run=$(abs_dir "$1") || exit 2
}

need_run_file() {
  [ ! -h "$run/$1" ] || die 2 "$1 in the run directory is a symbolic link"
  [ -f "$run/$1" ] || die 2 "the run has no $1 yet${2:+; $2}"
}

refuse_existing() {
  if [ -e "$1" ] || [ -h "$1" ]; then
    die 5 "$2 already exists; never overwritten"
  fi
}

# write_atomic <dest>: stdin to <dest> through a temp file beside it.
write_atomic() {
  tmp_path=$(mktemp "$1.XXXXXX") || die 2 "cannot create a temp file beside $1"
  cat >"$tmp_path" || die 2 "cannot write $1"
  mv -f "$tmp_path" "$1" || die 2 "cannot write $1"
  tmp_path=
}

# section <file> <heading>: the body of an H2 section, code fences respected.
section() {
  awk -v want="$2" '
    /^```/ { fence = !fence }
    !fence && /^## / { on = (substr($0, 4) == want); next }
    !fence && /^# / { on = 0; next }
    on { print }
  ' "$1" | awk '
    NF { while (blank > 0) { print ""; blank-- } print; seen = 1; next }
    seen { blank++ }
  '
}

# field <name>: a `- **<name>:** value` bullet from stdin, continuation lines
# joined with single spaces.
field() {
  awk -v want="- **$1:** " '
    index($0, want) == 1 { on = 1; v = substr($0, length(want) + 1); next }
    on && /^[ \t]+[^ \t]/ && $0 !~ /^[ \t]*- \*\*/ { s = $0; sub(/^[ \t]+/, "", s); v = v " " s; next }
    on { on = 0 }
    END { print v }
  '
}

card_header() {
  awk -v want="**$2:** " 'index($0, want) == 1 { print substr($0, length(want) + 1); exit }' "$1"
}

display_name() {
  /bin/bash "$self_dir/resolve-catalog.sh" discipline-cards 2>/dev/null | awk -v want="$1" '
    /^[ ]*- id:/ { id = $0; sub(/^[ ]*- id:[ ]*/, "", id); gsub(/"/, "", id); next }
    /^[ ]+discipline:/ && id == want {
      d = $0; sub(/^[ ]+discipline:[ ]*/, "", d); gsub(/^"|"$/, "", d); print d; exit
    }
  '
}

valid_card_id() {
  case $1 in
    "" | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

valid_seat_id() {
  case $1 in
    seat-[1-9]) return 0 ;;
  esac
  return 1
}

# The awk date helpers, the same calendar the renderer classifies kill
# criteria with (scripts/inception-render.sh).
# shellcheck disable=SC2016 # awk source
AWK_DATES='
function date_ok(d,   y, m, dd, dim) {
  if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
  y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
  if (m < 1 || m > 12 || dd < 1) return 0
  dim = 31
  if (m == 4 || m == 6 || m == 9 || m == 11) dim = 30
  else if (m == 2) dim = ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) ? 29 : 28
  return (dd <= dim)
}
function days(d,   y, m, dd, era, yoe, doy, doe) {
  y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
  y -= (m <= 2)
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + dd - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}
'

# --------------------------------------------------------------------------
# frame
# --------------------------------------------------------------------------
cmd_frame() {
  [ $# -eq 1 ] || usage
  open_venture "$1"
  t=$(today) || exit 2
  title=$(awk 'NR == 1 { sub(/^# /, ""); sub(/ — Brief$/, ""); print; exit }' "$venture/brief.md" | clean)
  opp=$(section "$venture/brief.md" Opportunity)
  framing=$(printf '%s\n' "$opp" | field Framing)
  hurts=$(printf '%s\n' "$opp" | field 'Who hurts')
  nogos=$(printf '%s\n' "$opp" | field 'No-gos & sketch')
  appetite=$(section "$venture/brief.md" Appetite | tr '\n' ' ' | sed 's/ *$//')
  fit=$(section "$venture/brief.md" 'Strategy fit' | tr '\n' ' ' | sed 's/ *$//')
  metric=$(section "$venture/brief.md" 'Success metric' | tr '\n' ' ' | sed 's/ *$//')
  sources=$(section "$venture/brief.md" Sources)
  staffing=$(section "$venture/disciplines.md" 'Staffing table')
  decisions=$(awk "$spec_parse_awk_fence"'
    /^### DEC-[0-9]+ — / { flush(); id = $2; t = $0; sub(/^### DEC-[0-9]+ — /, "", t); st = ""; door = ""; sup = 0; next }
    /^#/ { flush(); id = ""; next }
    id != "" && /^- \*\*Status:\*\* / { st = substr($0, 15) }
    id != "" && /^- \*\*Door:\*\* / { door = substr($0, 13) }
    id != "" && /^- \*\*Superseded-by:\*\*/ { sup = 1 }
    function flush() {
      if (id != "" && !sup && (st == "open" || st == "deferred")) {
        print "- **" id "** (" door ", " st ") — " t; n++
      }
      id = ""
    }
    END { flush(); if (!n) print "none" }
  ' "$venture/decisions.md")
  kcs=$(section "$venture/brief.md" 'Kill criteria' | awk -v today="$t" "$AWK_DATES"'
    /^- \*\*KC-[0-9]+:\*\* / {
      if (index($0, "**Superseded-by:**")) next
      d = $0; sub(/^.* — by /, "", d); sub(/[^0-9-].*$/, "", d)
      if (!date_ok(d)) s = "date unreadable"
      else { delta = days(d) - days(today); s = (delta < 0) ? "tripped" : (delta <= 30) ? "approaching" : "clear" }
      print $0 " — " s; n++
    }
    END { if (!n) print "none" }
  ')
  [ -n "$sources" ] || sources=none
  [ -n "$staffing" ] || staffing=none

  # not-a-lock: creates the derived-output directory on first use
  [ -d "$venture/exports" ] || mkdir "$venture/exports" || die 2 "cannot create exports/"
  {
    printf '# %s — Frame\n\n' "$title"
    printf 'Derived from the bundle by inception-fanout.sh at fan-out time; regenerate it, never edit it.\n\n'
    printf '## Problem statement\n\n- **Framing:** %s\n- **Who hurts:** %s\n\n' "$framing" "$hurts"
    printf '## Evidence pointers\n\n%s\n\n' "$sources"
    printf '## Constraints\n\n- **Appetite:** %s\n- **No-gos & sketch:** %s\n- **Inherited constraints:** %s\n\n' \
      "${appetite:-none}" "${nogos:-none}" "${fit:-none}"
    printf '## Door-classified decisions\n\n%s\n\n' "$decisions"
    printf '## Discipline staffing table\n\n%s\n\n' "$staffing"
    printf '## Success metric and kill criteria\n\n- **Success metric:** %s\n%s\n' "${metric:-none}" "$kcs"
  } | write_atomic "$venture/exports/frame.md"
  printf 'frame\t%s\n' "exports/frame.md"
}

# --------------------------------------------------------------------------
# triage: open one-way doors plus weakly evidenced, unresolved blocking
# assumptions. The band is the requirement's; the cut points are a cheap
# signal, and the operator confirms the count at Gate 1.
# --------------------------------------------------------------------------
cmd_triage() {
  [ $# -eq 1 ] || usage
  open_venture "$1"
  doors=$(awk "$spec_parse_awk_fence"'
    /^### DEC-/ { flush(); on = 1; st = ""; door = ""; sup = 0; next }
    /^#/ { flush(); on = 0; next }
    on && /^- \*\*Status:\*\* / { st = substr($0, 15) }
    on && /^- \*\*Door:\*\* / { door = substr($0, 13) }
    on && /^- \*\*Superseded-by:\*\*/ { sup = 1 }
    function flush() { if (on && !sup && door == "one-way" && (st == "open" || st == "deferred")) n++; on = 0 }
    END { flush(); print n + 0 }
  ' "$venture/decisions.md")
  weak=$(awk "$spec_parse_awk_fence"'
    /^### A-/ { flush(); on = 1; st = ""; ev = ""; bl = ""; sup = 0; next }
    /^#/ { flush(); on = 0; next }
    on && /^- \*\*Status:\*\* / { st = substr($0, 15); sub(/ .*$/, "", st) }
    on && /^- \*\*Evidence:\*\* / { ev = substr($0, 17); sub(/ .*$/, "", ev) }
    on && /^- \*\*Blocking:\*\* / { bl = substr($0, 17) }
    on && /^- \*\*Superseded-by:\*\*/ { sup = 1 }
    function flush() {
      if (on && !sup && bl == "yes" && (st == "open" || st == "testing") &&
          (ev == "none" || ev == "synthetic" || ev == "opinion")) n++
      on = 0
    }
    END { flush(); print n + 0 }
  ' "$venture/assumptions.md")
  signal=$((doors + weak))
  if [ "$signal" -ge 6 ]; then
    seats=5
  elif [ "$signal" -ge 3 ]; then
    seats=4
  else
    seats=3
  fi
  printf 'seats\t%s\nsignal\t%s\none-way-doors\t%s\nweak-blocking\t%s\n' "$seats" "$signal" "$doors" "$weak"
}

# --------------------------------------------------------------------------
# roster: the seats, fixed before Gate 1, and the disclosure Gate 1 shows.
# --------------------------------------------------------------------------
cmd_roster() {
  backend=
  specs=
  nspec=0
  rdir=
  while [ $# -gt 1 ]; do
    case $1 in
      --run)
        rdir=$2
        shift 2
        ;;
      --backend)
        backend=$2
        shift 2
        ;;
      --seat)
        nspec=$((nspec + 1))
        specs="$specs$2
"
        shift 2
        ;;
      *) break ;;
    esac
  done
  [ $# -eq 1 ] && [ -n "$rdir" ] && [ -n "$backend" ] || usage
  open_run "$rdir"
  open_venture "$1"
  [ -f "$venture/exports/frame.md" ] || die 2 "no frame yet; run \`inception-fanout.sh frame\` and confirm it at Gate 1 first"
  [ "$nspec" -ge 1 ] || die 2 "a fan-out needs at least one seat; a zero-seat run files its coverage risk with \`staff\` instead"
  [ "$nspec" -le "$MAX_SEATS" ] || die 2 "$nspec seats is over the cap of $MAX_SEATS"
  case $backend in "" | -* | *[!a-z0-9-]*) die 2 "invalid backend name" ;; esac
  caps=$(/bin/sh "$self_dir/orchestrate-backends.sh" caps "$backend" 2>/dev/null) \
    || die 2 "the backend contract does not know '$backend'"
  overhead=$(printf '%s\n' "$caps" | awk '{ print $7 }')
  tier=$(printf '%s\n' "$caps" | awk '{ print $9 }')
  refuse_existing "$run/roster.tsv" "the run's roster"

  rows=
  n=0
  old_ifs=$IFS
  IFS='
'
  for spec in $specs; do
    IFS=$old_ifs
    n=$((n + 1))
    model=inherit
    case $spec in *@*)
      model=${spec#*@}
      spec=${spec%%@*}
      ;;
    esac
    pole=none
    case $spec in *:*)
      pole=${spec#*:}
      spec=${spec%%:*}
      ;;
    esac
    card=$spec
    valid_card_id "$card" || die 2 "invalid card id in seat $n"
    case $model in
      "" | -* | *[!a-z0-9./-]*) die 2 "invalid model token in seat $n" ;;
    esac
    path=$(/bin/sh "$self_dir/resolve-card.sh" "$card" 2>/dev/null) || die 1 "no usable card for '$card' (seat $n)"
    /bin/sh "$self_dir/card-lint.sh" "$path" >/dev/null 2>&1 || die 1 "the '$card' card does not lint clean; fix it before staffing a seat with it"
    axis=$(card_header "$path" Stance-axis)
    if [ "$pole" != none ]; then
      case $pole in "" | *[!a-z]*) die 2 "invalid pole in seat $n" ;; esac
      case $axis in
        "$pole"-* | *-"$pole") ;;
        *) die 2 "the '$card' card's stance axis (${axis:-none}) has no '$pole' pole" ;;
      esac
    fi
    if [ "$model" = inherit ]; then
      override=$(card_header "$path" Model-override)
      case $override in "" | none | *[!a-z0-9./-]*) ;; *) model=$override ;; esac
    fi
    disc=$(display_name "$card" | clean)
    [ -n "$disc" ] || disc=$card
    rows="${rows}seat-$n	$card	$disc	$pole	$model
"
    IFS='
'
  done
  IFS=$old_ifs

  printf '%s' "$rows" | write_atomic "$run/roster.tsv"
  printf '%s\n' "$backend" | write_atomic "$run/backend"

  printf 'backend\t%s\n' "$backend"
  printf '%s' "$rows" | awk -F '\t' '{ print "seat\t" $0 }'
  sessions=$((n + 3))
  tokens=$((n * SEAT_TOKENS + SYNTH_TOKENS + CHALLENGE_TOKENS + AMEND_TOKENS))
  printf 'sessions\t%s\n' "$sessions"
  printf 'overhead\t%s per session\n' "$overhead"
  printf 'cost\tabout %sk tokens (planning estimate: %sk per seat, plus the synthesis, challenge, and amendment)\n' \
    "$((tokens / 1000))" "$((SEAT_TOKENS / 1000))"
  section "$venture/disciplines.md" 'Staffing table' | awk -F '|' '
    NR > 2 && NF >= 4 {
      d = $2; s = $3; gsub(/^[ \t]+|[ \t]+$/, "", d); gsub(/^[ \t]+|[ \t]+$/, "", s)
      if (s == "unstaffed") print "unstaffed\t" d
    }
  ' | clean
  requested=$(printf '%s' "$rows" | awk -F '\t' '$5 != "inherit" { n++ } END { print n + 0 }')
  distinct=$(printf '%s' "$rows" | cut -f5 | sort -u | awk 'END { print NR }')
  # A per-seat model needs a launch that takes one per seat. The harness Agent
  # launch does, where tier_control covers the model; offload-dispatch.sh's
  # tmux and print launches apply the one configured offload tier to every
  # launch, so on those rungs the seats cannot differ even though the backend
  # itself could carry a model.
  per_seat=no
  case $backend:$tier in subagent:both | subagent:model) per_seat=yes ;; esac
  if [ "$per_seat" = yes ]; then
    if [ "$n" -gt 1 ] && [ "$distinct" -lt 2 ]; then
      printf 'degraded\tevery seat runs on the same model, so the seats lose model-family decorrelation\n'
    fi
  elif [ "$n" -gt 1 ] || [ "$requested" -gt 0 ]; then
    printf 'degraded\tthe %s seat launch cannot set a per-seat model; every seat runs on one model, so the seats lose model-family decorrelation\n' "$backend"
  fi
  printf 'per-seat-model\t%s\n' "$per_seat"
}

# roster_row <seat-id>: the seat's roster line, or nothing.
roster_row() {
  awk -F '\t' -v want="$1" '$1 == want { print; exit }' "$run/roster.tsv"
}

# --------------------------------------------------------------------------
# brief
# --------------------------------------------------------------------------
cmd_brief() {
  take_deliver "$@"
  shift "$shifted"
  [ $# -eq 4 ] && [ "$1" = --run ] || usage
  open_run "$2"
  valid_seat_id "$3" || die 2 "invalid seat id"
  seat=$3
  open_venture "$4"
  need_run_file roster.tsv "run \`roster\` first"
  [ -f "$venture/exports/frame.md" ] || die 2 "no frame yet; run \`inception-fanout.sh frame\` first"
  row=$(roster_row "$seat")
  [ -n "$row" ] || die 2 "the roster has no $seat"
  card=$(printf '%s\n' "$row" | cut -f2)
  pole=$(printf '%s\n' "$row" | cut -f4)
  valid_card_id "$card" || die 2 "the roster names an invalid card id"
  path=$(/bin/sh "$self_dir/resolve-card.sh" "$card" 2>/dev/null) || die 1 "no usable card for '$card'"
  axis=$(card_header "$path" Stance-axis)
  tier=$(card_header "$path" Default-tier)

  cat <<EOF
# Seat brief

One independent seat of a persona fan-out over a venture. Work from this brief,
the frame at its end, and the files the input subscription names, and nothing
else. Those files are the venture's bundle, in \`$venture\`.

## Rules

- Work read-only: propose register entries in the artifact; never edit a file.
- Work alone: no other seat's output is visible here, and nothing goes to any
  other seat.
- Do not stop to ask questions, and never ask the human anything. A call that
  needs a human goes into the final section.
- Contact no one outside this session: no messages, forms, or sign-ups.
- Do not name the discipline, the card, the stance, or this seat in the
  artifact; the synthesis reads every artifact unlabeled.
- State confidence only as cited evidence: a sources-register name, a register
  ID, or a named external source per claim. Never state your own certainty or a
  probability.
- Write output that is not a recommendation (the card's default tier is
  ${tier:-structure-only}) in hypothesis grammar: if this holds, then that
  follows, and this evidence would show it. Write a call reserved to a human in
  briefing grammar: the options, the evidence, and the stakes.

## Task framing

EOF
  section "$path" Role
  for s in Mandate Frameworks Grounding 'Input subscription' 'Capability boundary' \
    'Escalation contract' 'Register rules' Independence; do
    printf '\n### %s\n\n' "$s"
    section "$path" "$s"
  done
  if [ "$pole" != none ]; then
    printf '\n## Stance\n\nArgue from the %s pole of the %s axis: weigh the evidence as that pole would, and say where the evidence does not support it.\n' "$pole" "$axis"
  fi
  printf '\n## Artifact template\n\n'
  section "$path" 'Artifact template' | awk -v h="$TABLE_HEADER" -v r="$TABLE_RULE" '
    $0 == "| Decision | Tier and reason | Owning role | Evidence needed |" { print h; swap = 1; next }
    swap && $0 == "| --- | --- | --- | --- |" { print r; swap = 0; next }
    { print }
  '
  cat <<EOF

## The final section

The artifact ends with \`## Decisions I cannot make\` as its last section, its
table carrying exactly this header:

$TABLE_HEADER
$TABLE_RULE

One row per call this seat cannot make. **Tier and reason** opens with the tier
(agent-senior, structure-only, or human-authority). **Trigger** is one of
irreversibility, missing-domain-authority, confidence-floor, or
contract-policy-change, as the escalation contract above words them. **Powers**
lists, comma-separated, the human's powers over the item from disregard,
override, reverse, and halt. With no such call, keep the header and write
\`none\` on its own line below it.

## The frame

EOF
  cat "$venture/exports/frame.md"
  delivery "$run/$seat.md" artifact
}

# --------------------------------------------------------------------------
# check-seat
# --------------------------------------------------------------------------
# shellcheck disable=SC2016 # awk source
AWK_SEAT='
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function bad(msg) { gsub(/[\001-\037\177]/, "", msg); print "finding\t" cur "\t" msg; nbad++ }
FNR == 1 { if (NR > 1) finish(); cur = FILENAME; last = ""; insec = 0; hdr = 0; rows = 0; nonel = 0 }
{
  low = tolower($0)
  if (low ~ /(^|[^a-z])(i am|i.m|we are|we.re) (very |highly |fairly |quite |reasonably |extremely )?(confident|certain|sure)([^a-z]|$)/ ||
      low ~ /confidence (level|score|rating)|confidence:/ ||
      low ~ /[0-9]+ ?% ?(confident|certain|certainty|confidence|likely|probability|chance)/ ||
      low ~ /(probability|likelihood|chance) (of|is) [0-9]/)
    bad("verbalized self-confidence or a stated probability (confidence is cited evidence only): " trim($0))
}
/^## / { last = substr($0, 4); insec = (last == "Decisions I cannot make"); hdr = 0; next }
insec && trim($0) == "none" { nonel = 1; next }
insec && /^\|/ {
  line = trim($0)
  if (!hdr) { if (line == HEADER) hdr = 1; else { bad("the Decisions I cannot make table needs the header " HEADER); hdr = -1 } ; next }
  if (hdr < 0) next
  if (line ~ /^\|[ |:-]*$/) next
  n = split(line, c, "|")
  if (n != 8) { bad("a Decisions I cannot make row needs six cells: " line); next }
  rows++
  if (trim(c[2]) == "") bad("a Decisions I cannot make row names no decision")
  t = trim(c[3]); sub(/[^a-z-].*$/, "", t)
  if (t != "agent-senior" && t != "structure-only" && t != "human-authority")
    bad("Tier and reason must open with a tier token: " trim(c[3]))
  if (trim(c[4]) == "") bad("a Decisions I cannot make row names no owning role")
  tr = trim(c[6])
  if (tr != "irreversibility" && tr != "missing-domain-authority" && tr != "confidence-floor" && tr != "contract-policy-change")
    bad("untyped escalation trigger: " tr)
  np = split(trim(c[7]), p, ",")
  if (np == 0) bad("an escalation names no human power")
  for (i = 1; i <= np; i++) {
    pw = trim(p[i])
    if (pw != "disregard" && pw != "override" && pw != "reverse" && pw != "halt") bad("not one of the four human powers: " pw)
  }
}
function finish() {
  if (last != "Decisions I cannot make") { bad("the artifact must end with the Decisions I cannot make section"); return }
  if (hdr == 0) bad("the Decisions I cannot make table needs the header " HEADER)
  else if (hdr > 0 && rows == 0 && !nonel) bad("an empty Decisions I cannot make table must say none")
}
END { if (NR > 0) finish(); exit (nbad > 0) }
'

check_seats() {
  for f in "$@"; do
    [ ! -h "$f" ] || die 2 "refusing a symbolic link: $f"
    [ -f "$f" ] && [ -r "$f" ] || die 2 "cannot read $f"
    [ -s "$f" ] || {
      printf 'finding\t%s\tthe artifact is empty\n' "$f"
      return 1
    }
  done
  awk -v HEADER="$TABLE_HEADER" 'FNR == 1 { spec_parse__fence = 0 }'"$spec_parse_awk_fence$AWK_SEAT" "$@"
}

cmd_check_seat() {
  [ $# -ge 1 ] || usage
  check_seats "$@"
}

# identity_terms: every seat's card id, display name, pole, model, and seat id,
# one per line, longest first so a longer term is redacted before a shorter one
# inside it.
identity_terms() {
  awk -F '\t' '{
    print $1; print $2; print $3
    if ($4 != "none") print $4
    if ($5 != "inherit") print $5
  }' "$run/roster.tsv" | awk 'length($0) > 0' | sort -u | awk '{ print length($0) "\t" $0 }' \
    | sort -rn | cut -f2-
}

# --------------------------------------------------------------------------
# anonymize
# --------------------------------------------------------------------------
cmd_anonymize() {
  [ $# -eq 2 ] && [ "$1" = --run ] || usage
  open_run "$2"
  need_run_file roster.tsv "run \`roster\` first"
  refuse_existing "$run/synthesis-input.md" "the run's synthesis input"
  refuse_existing "$run/labels.tsv" "the run's label map"
  seats=$(cut -f1 "$run/roster.tsv")
  set --
  for s in $seats; do
    valid_seat_id "$s" || die 2 "the roster names an invalid seat id"
    need_run_file "$s.md" "save each returned seat artifact as <seat-id>.md"
    set -- "$@" "$run/$s.md"
  done
  check_seats "$@" >&2 || die 1 "a seat artifact fails the check above; re-run that seat rather than synthesizing over it"
  seed=${PLANWRIGHT_FANOUT_SEED:-}
  case $seed in
    "") seed=$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' ') ;;
    *[!0-9]*) die 2 "PLANWRIGHT_FANOUT_SEED must be digits" ;;
  esac
  [ -n "$seed" ] || die 2 "no randomness source for the shuffle"
  order=$(cut -f1 "$run/roster.tsv" | awk -v seed="$seed" 'BEGIN { srand(seed) } { print rand() "\t" $0 }' \
    | sort -n | cut -f2)
  terms=$(identity_terms)
  labels=ABCDEFGHI
  i=0
  map=
  tmp_path=$(mktemp "$run/synthesis-input.md.XXXXXX") || die 2 "cannot create a temp file in the run"
  {
    total=$(awk 'END { print NR }' "$run/roster.tsv")
    printf '# Synthesis input\n\n%s independent inputs over one frame, unlabeled and in shuffled order.\n' "$total"
    for s in $order; do
      i=$((i + 1))
      l=$(printf '%s' "$labels" | cut -c"$i")
      map="$map$l	$s
"
      printf '\n## Input %s\n\n' "$l"
      TERMS=$terms awk '
        BEGIN { n = split(ENVIRON["TERMS"], T, "\n"); for (k = 1; k <= n; k++) L[k] = tolower(T[k]) }
        function alnum(ch) { return ch ~ /[a-z0-9]/ }
        function redact(s,   k, low, out, at, pre, post) {
          for (k = 1; k <= n; k++) {
            if (L[k] == "") continue
            low = tolower(s); out = ""
            while ((at = index(low, L[k])) > 0) {
              pre = (at > 1) ? substr(low, at - 1, 1) : ""
              post = substr(low, at + length(L[k]), 1)
              if (alnum(pre) || alnum(post)) {
                out = out substr(s, 1, at + length(L[k]) - 1)
              } else {
                out = out substr(s, 1, at - 1) "[redacted]"
              }
              s = substr(s, at + length(L[k])); low = substr(low, at + length(L[k]))
            }
            s = out s
          }
          return s
        }
        /^```/ { fence = !fence; print redact($0); next }
        !fence && /^# / { next }
        !fence && /^#/ { print "#" redact($0); next }
        { print redact($0) }
      ' "$run/$s.md" | clean
    done
  } >"$tmp_path" || die 2 "cannot write the synthesis input"
  mv -f "$tmp_path" "$run/synthesis-input.md" || die 2 "cannot write the synthesis input"
  tmp_path=
  printf '%s' "$map" | write_atomic "$run/labels.tsv"
  printf 'inputs\t%s\nsynthesis-input\t%s\n' "$i" "$run/synthesis-input.md"
}

# --------------------------------------------------------------------------
# check-synthesis
# --------------------------------------------------------------------------
check_synthesis() {
  # $1 file; the run (optional) supplies the input count, labels, and the
  # identity terms a blind synthesis must not carry.
  f=$1
  [ ! -h "$f" ] || die 2 "refusing a symbolic link: $f"
  [ -f "$f" ] && [ -r "$f" ] || die 2 "cannot read $f"
  ninputs=
  labelset=
  terms=
  if [ -n "$run" ]; then
    need_run_file labels.tsv "run \`anonymize\` first"
    ninputs=$(awk 'END { print NR }' "$run/labels.tsv")
    labelset=$(cut -f1 "$run/labels.tsv" | tr '\n' ' ')
    terms=$(identity_terms)
  fi
  TERMS=$terms LABELS=$labelset awk -v HEADER="$SYNTH_HEADER" -v NIN="$ninputs" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function bad(msg) { gsub(/[\001-\037\177]/, "", msg); print "finding\t" FILENAME "\t" msg; nbad++ }
    BEGIN {
      nt = split(ENVIRON["TERMS"], T, "\n")
      nl = split(ENVIRON["LABELS"], LB, " "); for (k = 1; k <= nl; k++) OK["Input " LB[k]] = 1
    }
    {
      low = tolower($0)
      for (k = 1; k <= nt; k++) {
        if (T[k] == "") continue
        at = index(low, tolower(T[k]))
        if (at == 0) continue
        pre = (at > 1) ? substr(low, at - 1, 1) : ""; post = substr(low, at + length(T[k]), 1)
        if (pre !~ /[a-z0-9]/ && post !~ /[a-z0-9]/) bad("seat identity in a blind synthesis: " T[k])
      }
    }
    /^```/ { fence = !fence; next }
    fence { next }
    /^## / { insec = (substr($0, 4) == "Synthesis table"); if (insec) seen = 1; hdr = 0; next }
    insec && /^\|/ {
      line = trim($0)
      if (!hdr) { if (line != HEADER) bad("the synthesis table needs the header " HEADER); hdr = 1; next }
      if (line ~ /^\|[ |:-]*$/) next
      n = split(line, c, "|")
      if (n != 8) { bad("a synthesis row needs six cells: " line); next }
      rows++
      kind = trim(c[2]); ct = trim(c[4]); cv = trim(c[5]); ol = trim(c[6])
      if (kind != "agreement" && kind != "tension" && kind != "open-question") bad("unknown kind: " kind)
      if (trim(c[3]) == "") bad("a synthesis row states no claim")
      if (ct != "extractive" && ct != "interpretive") bad("claim type must be extractive or interpretive: " ct)
      if (cv !~ /^[0-9]+ of [0-9]+$/) { bad("convergence is a count, <k> of <n>, never a percentage or probability: " cv); next }
      split(cv, kn, " of "); k = kn[1] + 0; tot = kn[2] + 0
      if (k > tot) bad("more converging inputs than inputs: " cv)
      if (NIN != "" && tot != NIN + 0) bad("convergence counts over " tot " inputs; the run has " NIN ": " cv)
      if (ol == "none") { if (k < tot) bad("a claim with " cv " convergence must name its outlier inputs") }
      else {
        np = split(ol, p, ",")
        for (i = 1; i <= np; i++) {
          q = trim(p[i])
          if (q !~ /^Input [A-I]$/ || (nl > 0 && !(q in OK))) bad("outlier is not an input label: " q)
        }
      }
      if (trim(c[7]) == "") bad("a synthesis row needs a grounding cell (citations, or none)")
    }
    END {
      if (!seen) bad("the synthesis needs a ## Synthesis table section")
      else if (rows == 0) bad("the synthesis table has no rows")
      exit (nbad > 0)
    }
  ' "$f"
}

cmd_check_synthesis() {
  if [ "${1:-}" = --run ]; then
    [ $# -eq 3 ] || usage
    open_run "$2"
    shift 2
  fi
  [ $# -eq 1 ] || usage
  check_synthesis "$1"
}

persona_free_rules() {
  cat <<'EOF'
Work only from the material in this prompt: read no file, run no command beyond
the delivery at the end, and contact no one. The inputs are unlabeled on
purpose; do not guess where any of them came from, and name no discipline,
card, or seat.
EOF
}

# take_deliver: an optional leading --deliver-file, for a rung whose session
# hands nothing back (tmux, print). It sets $deliver and how many arguments
# it consumed in $shifted.
deliver=
shifted=0
take_deliver() {
  shifted=0
  if [ "${1:-}" = --deliver-file ]; then
    deliver=yes
    shifted=1
  fi
}

# delivery <target> <noun>: the closing instruction. The target is always the
# run file the step reads next, never a caller-chosen path.
delivery() {
  printf '\n## Delivery\n\n'
  if [ -n "$deliver" ]; then
    # shellcheck disable=SC2016 # the backticks are literal markdown
    printf 'Write the finished %s, and nothing else, to the file `%s`, creating it. Write no other file, then stop.\n' "$2" "$1"
  else
    printf 'Return the finished %s, and nothing else, as the final answer.\n' "$2"
  fi
}

table_rules() {
  cat <<EOF
The document has a short \`## Synthesis\` section of prose, then a
\`## Synthesis table\` section holding one table with exactly this header:

$SYNTH_HEADER
| --- | --- | --- | --- | --- | --- |

- **Kind:** agreement, tension, or open-question.
- **Claim:** one claim, keyed to the inputs by their labels (Input A, Input B).
- **Claim type:** extractive (restates a fact or a cited source) or
  interpretive (a judgment or an evaluation).
- **Convergence:** \`<k> of <n>\`, where n is the number of inputs and k the
  inputs that support the claim. Never a percentage, a probability, or a
  confidence word: agreement among inputs that share a frame is a weak signal.
- **Outliers:** the labels of the inputs that dissent or are silent, comma
  separated, or none when every input supports the claim. Name them; never
  average them away.
- **Grounding:** the checkable citations behind the claim (sources-register
  names, register IDs, named sources), or none. Grounding outranks the count.
EOF
}

cmd_synthesis_brief() {
  take_deliver "$@"
  shift "$shifted"
  [ $# -eq 3 ] && [ "$1" = --run ] || usage
  open_run "$2"
  open_venture "$3"
  need_run_file synthesis-input.md "run \`anonymize\` first"
  [ -f "$venture/exports/frame.md" ] || die 2 "no frame yet"
  cat <<EOF
# Synthesis task

Merge the independent inputs below, each one reading of the same frame, into a
single synthesis. Record where the inputs agree, where they are in tension, and
what they leave open.

EOF
  persona_free_rules
  printf '\n'
  table_rules
  printf '\n## The frame\n\n'
  cat "$venture/exports/frame.md"
  printf '\n## The inputs\n\n'
  cat "$run/synthesis-input.md"
  delivery "$run/synthesis.md" "synthesis document"
}

cmd_challenge_brief() {
  take_deliver "$@"
  shift "$shifted"
  [ $# -eq 3 ] && [ "$1" = --run ] || usage
  open_run "$2"
  open_venture "$3"
  need_run_file synthesis.md "save the synthesis writer's answer as synthesis.md"
  check_synthesis "$run/synthesis.md" >&2 || die 1 "the synthesis fails the check above; send it back to its writer before the challenge"
  cat <<'EOF'
# Challenge task

Run one challenge pass over the synthesis below, against the frame it was
written from. It has two parts:

1. **A premortem.** Suppose the venture went ahead on this synthesis and has
   failed a year from now. List the most plausible causes, most likely first,
   each tied to a claim in the synthesis or a gap in it.
2. **A key-assumptions check.** List the assumptions the synthesis rests on,
   stated or not. For each, say what supports it in the synthesis or the
   frame, how strong that support is, and what would show it wrong.

Do not rewrite the synthesis and do not argue for a side; the synthesis writer
answers this pass once. The document holds `## Premortem` and
`## Key-assumptions check`.

EOF
  persona_free_rules
  printf '\n## The frame\n\n'
  cat "$venture/exports/frame.md"
  printf '\n## The synthesis\n\n'
  cat "$run/synthesis.md"
  delivery "$run/challenge.md" "challenge document"
}

cmd_amend_brief() {
  take_deliver "$@"
  shift "$shifted"
  [ $# -eq 3 ] && [ "$1" = --run ] || usage
  open_run "$2"
  open_venture "$3"
  need_run_file synthesis.md
  need_run_file synthesis-input.md
  need_run_file challenge.md "run the challenge pass first"
  if [ -e "$run/amended.md" ] || [ -h "$run/amended.md" ]; then
    die 1 "the synthesis has already been amended once; there is no second round"
  fi
  cat <<'EOF'
# Amendment task

A challenge pass has read the synthesis below. Amend the synthesis once in its
light: change a claim, a count, or an outlier where the challenge shows it is
wrong, add what it shows is missing, and leave the rest. This is the only
amendment; there is no further round.

EOF
  persona_free_rules
  printf '\n'
  table_rules
  printf '\n## The frame\n\n'
  cat "$venture/exports/frame.md"
  printf '\n## The inputs\n\n'
  cat "$run/synthesis-input.md"
  printf '\n## The synthesis\n\n'
  cat "$run/synthesis.md"
  printf '\n## The challenge\n\n'
  cat "$run/challenge.md"
  delivery "$run/amended.md" "amended synthesis document"
}

# --------------------------------------------------------------------------
# attribute
# --------------------------------------------------------------------------
cmd_attribute() {
  [ $# -eq 2 ] && [ "$1" = --run ] || usage
  open_run "$2"
  need_run_file labels.tsv "run \`anonymize\` first"
  need_run_file roster.tsv
  src=synthesis.md
  [ -f "$run/amended.md" ] && src=amended.md
  need_run_file "$src"
  refuse_existing "$run/table.md" "the run's final table"
  check_synthesis "$run/$src" >&2 || die 1 "the $src fails the check above"
  names=$(awk -F '\t' 'NR == FNR { s[$1] = $0; next } {
    split(s[$2], r, "\t")
    a = r[3]; if (r[4] != "none") a = a ", " r[4] " pole"; if (r[5] != "inherit") a = a ", " r[5]
    print $1 "\t" a
  }' "$run/roster.tsv" "$run/labels.tsv")
  NAMES=$names awk '
    BEGIN { n = split(ENVIRON["NAMES"], R, "\n"); for (k = 1; k <= n; k++) { split(R[k], f, "\t"); A["Input " f[1]] = f[2] } }
    /^```/ { fence = !fence }
    !fence && /^## / { insec = (substr($0, 4) == "Synthesis table") }
    insec && /^\|/ {
      out = ""; s = $0
      while (match(s, /Input [A-I]/)) {
        lab = substr(s, RSTART, RLENGTH)
        nxt = substr(s, RSTART + RLENGTH, 1)
        out = out substr(s, 1, RSTART - 1) lab
        if ((lab in A) && nxt !~ /[A-Za-z0-9(]/) out = out " (" A[lab] ")"
        s = substr(s, RSTART + RLENGTH)
      }
      print out s; next
    }
    { print }
  ' "$run/$src" | clean | write_atomic "$run/table.md"
  printf 'table\t%s\n' "$run/table.md"
}

# --------------------------------------------------------------------------
# gate2
# --------------------------------------------------------------------------
cmd_gate2() {
  [ $# -eq 2 ] && [ "$1" = --run ] || usage
  open_run "$2"
  need_run_file roster.tsv
  set --
  # shellcheck disable=SC2013 # seat ids are single words, each validated below
  for s in $(cut -f1 "$run/roster.tsv"); do
    valid_seat_id "$s" || die 2 "the roster names an invalid seat id"
    need_run_file "$s.md"
    set -- "$@" "$run/$s.md"
  done
  check_seats "$@" >&2 || die 1 "a seat artifact fails the check above"
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    FNR == 1 { seat = FILENAME; sub(/^.*\//, "", seat); sub(/\.md$/, "", seat); insec = 0; hdr = 0; spec_parse__fence = 0 }
'"$spec_parse_awk_fence"'
    /^## / { insec = (substr($0, 4) == "Decisions I cannot make"); hdr = 0; next }
    insec && /^\|/ {
      if (!hdr) { hdr = 1; next }
      if ($0 ~ /^\|[ |:-]*$/) next
      split($0, c, "|")
      t = trim(c[3]); sub(/[^a-z-].*$/, "", t)
      print "choice\t" ++n "\t" seat "\t" trim(c[2]) "\t" t "\t" trim(c[4]) "\t" trim(c[6]) "\t" trim(c[7])
    }
  ' "$@" | clean
  printf 'outcomes\tproceed park kill re-run-seat pull-bench\n'
}

# --------------------------------------------------------------------------
# record
# --------------------------------------------------------------------------
cmd_record() {
  [ $# -eq 3 ] && [ "$1" = --run ] || usage
  open_run "$2"
  open_venture "$3"
  need_run_file table.md "run \`attribute\` first"
  need_run_file roster.tsv
  t=$(today) || exit 2
  # not-a-lock: creates the run-record directory on first use
  [ -d "$venture/fanout" ] || mkdir "$venture/fanout" || die 2 "cannot create fanout/"
  n=1
  # not-a-lock: claims the first unused run number; a lost race takes the next
  until mkdir "$venture/fanout/$t-$n" 2>/dev/null; do
    n=$((n + 1))
    [ "$n" -le 999 ] || die 2 "cannot create a run directory under fanout/"
  done
  dest="$venture/fanout/$t-$n"
  cp "$run/table.md" "$run/roster.tsv" "$dest/" || die 2 "cannot copy the run into $dest"
  [ ! -f "$run/challenge.md" ] || cp "$run/challenge.md" "$dest/" || die 2 "cannot copy the challenge"
  # shellcheck disable=SC2013 # seat ids are single words, each validated below
  for s in $(cut -f1 "$run/roster.tsv"); do
    valid_seat_id "$s" || continue
    [ ! -f "$run/$s.md" ] || cp "$run/$s.md" "$dest/" || die 2 "cannot copy $s.md"
  done
  printf 'recorded\t%s\n' "fanout/$t-$n"
}

# --------------------------------------------------------------------------
# staff: coverage honesty (REQ-P1.8). Every unstaffed discipline is filed
# unless the operator judged it stake-free (--no-stake); an agent-persona row
# whose card does not resolve counts as unstaffed.
# --------------------------------------------------------------------------
cmd_staff() {
  nostake=
  while [ $# -gt 1 ]; do
    case $1 in
      --no-stake)
        nostake="$nostake$2
"
        shift 2
        ;;
      *) break ;;
    esac
  done
  [ $# -eq 1 ] || usage
  open_venture "$1"
  staffing=$(section "$venture/disciplines.md" 'Staffing table' | awk -F '|' '
    NR > 2 && NF >= 5 {
      d = $2; s = $3; c = $4
      gsub(/^[ \t]+|[ \t]+$/, "", d); gsub(/^[ \t]+|[ \t]+$/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", c)
      print d "\t" s "\t" c
    }
  ')
  persona_rows=0
  unstaffed=
  old_ifs=$IFS
  IFS='
'
  for row in $staffing; do
    IFS=$old_ifs
    d=$(printf '%s\n' "$row" | cut -f1)
    s=$(printf '%s\n' "$row" | cut -f2)
    c=$(printf '%s\n' "$row" | cut -f3)
    why=
    if [ "$s" = agent-persona ]; then
      persona_rows=$((persona_rows + 1))
      if ! valid_card_id "$c" || ! /bin/sh "$self_dir/resolve-card.sh" "$c" >/dev/null 2>&1; then
        why="no card"
      fi
    elif [ "$s" = unstaffed ]; then
      why=unstaffed
    fi
    if [ -n "$why" ]; then
      if printf '%s' "$nostake" | grep -Fqx -- "$d"; then
        printf 'skipped\t%s\tjudged stake-free\n' "$d" | clean
      else
        unstaffed="$unstaffed$d	$why
"
      fi
    fi
    IFS='
'
  done
  IFS=$old_ifs

  am="$venture/assumptions.md"
  next=$(awk '/^### A-[0-9]+ — / { n = substr($2, 3) + 0; if (n > max) max = n } END { print max + 1 }' "$am")
  count=$(printf '%s' "$unstaffed" | awk 'END { print NR }')
  [ "$count" -gt 0 ] || {
    printf 'filed\tnone\n'
    return 0
  }

  # Only a deliberate zero-seat run collapses: a persona row whose card is
  # missing is a staffing gap, filed on its own.
  if [ "$persona_rows" -eq 0 ]; then
    existing=$(awk '/^### A-[0-9]+ — personas waived \(zero-seat\); / { print $2; exit }' "$am")
    if [ -n "$existing" ]; then
      printf 'exists\t%s\tpersonas waived\n' "$existing"
      return 0
    fi
    word=disciplines
    [ "$count" -eq 1 ] && word=discipline
    list=$(printf '%s' "$unstaffed" | cut -f1 | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')
    {
      cat "$am"
      cat <<EOF

### A-$next — personas waived (zero-seat); $count $word unstaffed

- **Statement:** believe this venture can reach its gate with no persona seat and
  these disciplines unstaffed ($list); verify by naming who covers each before the
  gate; measure how many of them the staffing table names a person or a card for;
  right if each is staffed or shown to carry no stake before the gate.
- **Risk-if-wrong:** calls in an unstaffed discipline are made with nobody accountable
  for the discipline
- **Risk-tag:** viability
- **Threshold:** none
- **Evidence:** none
- **Blocking:** no
- **Tasks:** none
- **Status:** open
EOF
    } | write_atomic "$am"
    printf 'collapsed\tA-%s\t%s\n' "$next" "$count"
    return 0
  fi

  out=$(cat "$am")
  first=$next
  report=
  IFS='
'
  for row in $unstaffed; do
    IFS=$old_ifs
    d=$(printf '%s\n' "$row" | cut -f1)
    why=$(printf '%s\n' "$row" | cut -f2)
    existing=$(awk -v want="— coverage risk: $d unstaffed" '
      /^### A-[0-9]+ — / { h = $0; sub(/^### A-[0-9]+ /, "", h); if (h == want) { print $2; exit } }
    ' "$am")
    if [ -n "$existing" ]; then
      report="${report}exists	$existing	$d
"
    else
      out="$out

### A-$next — coverage risk: $d unstaffed

- **Statement:** believe this venture's $d calls can be made well with no seat or
  named person staffing the discipline; verify by naming who covers $d before the
  gate; measure whether the staffing table names a person or a card for it; right if
  $d is staffed before the gate or its calls are shown to carry no stake.
- **Risk-if-wrong:** $d calls are made with nobody accountable for the discipline
- **Risk-tag:** viability
- **Threshold:** none
- **Evidence:** none
- **Blocking:** no
- **Tasks:** none
- **Status:** open"
      report="${report}filed	A-$next	$d	$why
"
      next=$((next + 1))
    fi
    IFS='
'
  done
  IFS=$old_ifs
  if [ "$next" -gt "$first" ]; then
    printf '%s\n' "$out" | write_atomic "$am"
  fi
  printf '%s' "$report" | clean
}

[ $# -ge 1 ] || usage
cmd=$1
shift
case $cmd in
  frame) cmd_frame "$@" ;;
  triage) cmd_triage "$@" ;;
  roster) cmd_roster "$@" ;;
  brief) cmd_brief "$@" ;;
  check-seat) cmd_check_seat "$@" ;;
  anonymize) cmd_anonymize "$@" ;;
  synthesis-brief) cmd_synthesis_brief "$@" ;;
  challenge-brief) cmd_challenge_brief "$@" ;;
  amend-brief) cmd_amend_brief "$@" ;;
  check-synthesis) cmd_check_synthesis "$@" ;;
  attribute) cmd_attribute "$@" ;;
  gate2) cmd_gate2 "$@" ;;
  record) cmd_record "$@" ;;
  staff) cmd_staff "$@" ;;
  *) usage ;;
esac
