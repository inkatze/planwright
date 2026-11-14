#!/usr/bin/env bash
# mc-draft-stall.sh — the stalled-draft alarm: a draft pull request whose latest
# CI run on its current head ended cancelled, or sat unfinished past a threshold,
# while no hold it states still applies, raises a `draft-stalled` event to the
# mission control that owns it, once per head.
#
# `mc-draft-stall.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-draft-stall
MAX_READS=40
MAX_REFS=5
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh check-runs.jq; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2

usage() {
  mc_usage_fail "usage: mc-draft-stall.sh [watch] [--program <p>] [--now <epoch>]"
}

help_text() {
  cat <<'HELP'
mc-draft-stall.sh — the stalled-draft alarm: a draft pull request of the
program is raised as stalled, to the mission control that owns it, when
  (a) the latest CI run on its current head ended cancelled, or a run on it
      has sat unfinished (queued or running) for
      mission_control_stalled_draft_threshold, and
  (b) no hold the pull request states still applies.
A draft whose hold still applies is not stalled. It changes nothing it reads.

THE CANDIDATES. The program's code-state snapshot names the open drafts; only
a draft whose checks rollup there is FAILURE, ERROR, PENDING or EXPECTED is
read further (at most 40 a pass; the rest are counted). Its checks are read
with the one selection of check runs the flip gates use (check-runs.jq), so a
re-run supersedes the run before it and a base-state check (the release-window
lock) is never the cancelled run. An unfinished run's age runs from its start;
a run with no start time runs from the first pass that saw it at this head.

THE HOLDS a pull request states, none of them guessed:
  a label naming "hold" as a word (hold, on-hold, hold:x; not stakeholder)
                          applies while the label is on it
  a body line opening with hold, held, blocked, waiting, waits or depends on,
    in which
      #<n> or <owner/name>#<n>   applies while that pull request or issue
                                 is open, and is cleared once it is closed
                                 or merged
      "release window" (or "untagged window")
                                 applies while the window-lock check on the
                                 base branch is not green, and is cleared
                                 once it is
    and a hold line naming neither applies, a person having to clear it.
A hold that cannot be read applies: a read that failed never raises.

THE EVENT. Once per head: one `draft-stalled` event (class act, so it wakes
mission control) naming each newly stalled draft and why, recorded as raised
only once the store holds it, so a refused event is retried. A new head
resets it; a draft that is no longer a draft, or is gone, is forgotten.

Usage:
  mc-draft-stall.sh [watch] [--program <p>] [--now <epoch>]
      the watcher (also a run with no arguments under the runner, the
      program from PLANWRIGHT_MC_PROGRAM), printing
        raised<TAB>draft-stalled<TAB><count>
      when it raises. A program with no code-state snapshot, none taken
      yet, or one past twice its cadence raises nothing.

Exit codes: 0 done; 1 a failed read, store, knob or event; 2 usage; 3 the
program is not configured.

Portable bash 3.2 / BSD tooling.
HELP
}

case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
if [ $# -eq 0 ] && [ -n "${PLANWRIGHT_MC_PROGRAM:-}" ]; then
  set -- watch
fi
[ $# -ge 1 ] || usage
verb=$1
shift
[ "$verb" = watch ] || usage
program=""
NOW=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --now)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --now)
          mc_valid_uint "$2" || mc_usage_fail "--now takes an epoch"
          NOW=$2
          ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ -n "$program" ] || program=${PLANWRIGHT_MC_PROGRAM:-}
[ -n "$program" ] || usage
[ -n "$NOW" ] || NOW=$(date +%s)
mc_require_program "$program"

ks=$(mc_knob mission_control_stalled_draft_threshold mc_parse_cadence) || exit 1
THRESHOLD=$(mc_seconds "$ks") || mc_fail "mission_control_stalled_draft_threshold is not a cadence"

mc_code_state "$program" "$NOW"
case $? in
  0) ;;
  1) mc_fail "the source map of program $program does not resolve" ;;
  2) mc_fail "the $MC_CS_SOURCE snapshot cannot be read" ;;
  *) exit 0 ;;
esac
runtime=$(mc_runtime "$program") || mc_fail "cannot resolve the runtime directory"
state="$runtime/draft-stall.tsv"

# Candidates: slug, number, head, rollup of each open draft not clearly green.
cands=$(printf '%s\n' "$MC_CS_ROWS" | awk -F '\t' '$1 == "pr" && $5 == "true" && ($9 == "FAILURE" || $9 == "ERROR" || $9 == "PENDING" || $9 == "EXPECTED") { print $2 "\t" $3 "\t" $4 }')
alldrafts=$(printf '%s\n' "$MC_CS_ROWS" | awk -F '\t' '$1 == "pr" && $5 == "true" { print $2 "#" $3 "\t" $4 }')

prev_raised=""
prev_first=""
if [ -f "$state" ]; then
  prev_raised=$(awk -F '\t' '$1 == "raised" { print $2 "\t" $3 }' "$state")
  prev_first=$(awk -F '\t' '$1 == "first" { print $2 "\t" $3 "\t" $4 }' "$state")
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/mc-draft-stall.XXXXXX") || mc_fail "cannot create a scratch directory"
trap 'rm -rf "$scratch"' EXIT

base_json=$(/bin/sh "$script_dir/base-state-checks.sh") || base_json='[]'
jq_runs=$(cat -- "$script_dir/check-runs.jq") || mc_fail "check-runs.jq is missing or unreadable (broken install)"
# gh --jq takes no variables, so the list the shared module reads is bound inline.
# shellcheck disable=SC2016 # a jq program
JQ_PROG="${base_json:-[]} as \$base_state | $jq_runs"'
  def clean: tostring | gsub("[\t\r\n]"; " ");
  def epoch: (. // "") | if . == "" or startswith("0001-") then 0 else (try fromdateiso8601 catch 0) end;
  "head\t" + .headRefOid,
  "base\t" + ((.baseRefName // "") | clean),
  (.labels[]? | "label\t" + (.name | clean)),
  ((.statusCheckRollup // []) | latest_check_runs[]
    | if (.status // "COMPLETED") != "COMPLETED" or (.context != null and ((.state // "") == "PENDING" or (.state // "") == "EXPECTED"))
      then "run\tunfinished\t" + ((.startedAt // .createdAt) | epoch | tostring)
      elif (.conclusion // "") == "CANCELLED" then "run\tcancelled\t0"
      else empty end),
  ((.body // "") | split("\n")[] | select(test("^[^A-Za-z0-9]*(hold|held|blocked|waiting|waits|depends on)\\b"; "i")) | "holdline\t" + (gsub("[\t\r]"; " ")))'

# hold_state <slug> <pr file> <own number>: `none` when the pull request states
# no hold, `applies <why>` when one still does, else `cleared <why>`.
hold_state() {
  hs_slug=$1
  hs_file=$2
  hs_self=$3
  hs_base=$(awk -F '\t' '$1 == "base" { print $2; exit }' "$hs_file")
  hs_why=""
  if awk -F '\t' '$1 == "label" && tolower($2) ~ /(^|[^a-z0-9])hold($|[^a-z0-9])/ { f = 1 } END { exit !f }' "$hs_file"; then
    printf 'applies a hold label is on it\n'
    return 0
  fi
  hs_lines=$(awk -F '\t' '$1 == "holdline" { print $2 }' "$hs_file")
  [ -n "$hs_lines" ] || {
    printf 'none\n'
    return 0
  }
  hs_refs=$(printf '%s\n' "$hs_lines" | awk '{
    s = $0
    while (match(s, /[A-Za-z0-9_.-]*\/?[A-Za-z0-9_.-]*#[0-9]+/)) { print substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH) }
  }' | awk '!seen[$0]++' | head -n "$MAX_REFS")
  hs_window=0
  printf '%s\n' "$hs_lines" | grep -qiE 'release window|untagged window' && hs_window=1
  hs_named=0
  while IFS= read -r hs_ref; do
    [ -n "$hs_ref" ] || continue
    hs_n=${hs_ref##*#}
    hs_rs=$hs_slug
    case $hs_ref in
      */*#*) hs_rs=${hs_ref%#*} ;;
    esac
    mc_valid_slug "$hs_rs" || continue
    mc_valid_uint "$hs_n" || continue
    [ "$hs_rs#$hs_n" != "$hs_slug#$hs_self" ] || continue
    hs_named=1
    hs_st=$(gh api "repos/$hs_rs/issues/$hs_n" --jq '.state' 2>"$scratch/err") || hs_st=unreadable
    case $hs_st in
      closed) hs_why="${hs_why}${hs_why:+, }$hs_rs#$hs_n is closed or merged" ;;
      *)
        printf 'applies it waits on %s#%s (%s)\n' "$hs_rs" "$hs_n" "$hs_st"
        return 0
        ;;
    esac
  done <<EOF
$hs_refs
EOF
  if [ "$hs_window" = 1 ]; then
    hs_named=1
    hs_wl=$(gh api "repos/$hs_slug/commits/${hs_base:-main}/check-runs?check_name=window-lock" \
      --jq '[.check_runs[] | .conclusion // "pending"] | if length == 0 then "none" else .[0] end' 2>"$scratch/err") || hs_wl=unreadable
    case $hs_wl in
      none | success | skipped | neutral) hs_why="${hs_why}${hs_why:+, }the release window is closed" ;;
      *)
        printf 'applies it waits on the release window (%s)\n' "$hs_wl"
        return 0
        ;;
    esac
  fi
  if [ "$hs_named" = 0 ]; then
    printf 'applies it states a hold with nothing checkable\n'
    return 0
  fi
  printf 'cleared %s\n' "$hs_why"
}

new_raised=""
new_first=""
events=""
count=0
read_n=0
skipped=0
deferred=0
while IFS='	' read -r c_slug c_n c_head; do
  [ -n "$c_slug" ] || continue
  key="$c_slug#$c_n"
  if printf '%s\n' "$prev_raised" | awk -F '\t' -v k="$key" -v h="$c_head" '$1 == k && $2 == h { f = 1 } END { exit !f }'; then
    new_raised="${new_raised}${key}	${c_head}
"
    continue
  fi
  if [ "$read_n" -ge "$MAX_READS" ]; then
    skipped=$((skipped + 1))
    continue
  fi
  read_n=$((read_n + 1))
  pr="$scratch/pr.$read_n"
  if ! gh pr view "$c_n" --repo "$c_slug" --json headRefOid,baseRefName,labels,body,statusCheckRollup --jq "$JQ_PROG" >"$pr" 2>"$scratch/err"; then
    # A read that failed raises nothing and is retried on the next pass.
    continue
  fi
  head=$(awk -F '\t' '$1 == "head" { print $2; exit }' "$pr")
  mc_valid_sha "$head" || continue
  # The snapshot may be a cadence old: the head the read returns is the one judged.
  if printf '%s\n' "$prev_raised" | awk -F '\t' -v k="$key" -v h="$head" '$1 == k && $2 == h { f = 1 } END { exit !f }'; then
    new_raised="${new_raised}${key}	${head}
"
    continue
  fi
  why=""
  if awk -F '\t' '$1 == "run" && $2 == "cancelled" { f = 1 } END { exit !f }' "$pr"; then
    why="the latest CI run was cancelled"
  else
    started=$(awk -F '\t' '$1 == "run" && $2 == "unfinished" { print $3 + 0 }' "$pr" | sort -n | awk 'NR == 1 { print }')
    if [ -n "$started" ]; then
      if [ "$started" -eq 0 ]; then
        started=$(printf '%s\n' "$prev_first" | awk -F '\t' -v k="$key" -v h="$head" '$1 == k && $2 == h { print $3; exit }')
        mc_valid_uint "$started" && [ "$started" -le "$NOW" ] || started=$NOW
        new_first="${new_first}${key}	${head}	${started}
"
      fi
      if [ $((NOW - started)) -ge "$THRESHOLD" ]; then
        why="a CI run has sat unfinished for $(((NOW - started) / 3600))h$((((NOW - started) % 3600) / 60))m"
      fi
    fi
  fi
  [ -n "$why" ] || continue
  hold=$(hold_state "$c_slug" "$pr" "$c_n")
  case $hold in
    applies*) continue ;;
    cleared*) why="$why, its hold cleared (${hold#cleared })" ;;
  esac
  entry="${key}: ${why}; "
  # The event holds 500 bytes: what does not fit waits for the next pass, unrecorded.
  if [ $((${#events} + ${#entry})) -gt 440 ]; then
    deferred=$((deferred + 1))
    continue
  fi
  events="${events}${entry}"
  count=$((count + 1))
  new_raised="${new_raised}${key}	${head}
"
done <<EOF
$cands
EOF

# Forget a draft that is gone or on a new head: its row survives only while the
# draft it names is still a draft at that head.
keep() { # keep <rows>: rows whose first field names a draft the snapshot still lists
  printf '%s' "$1" | D=$alldrafts awk -F '\t' 'BEGIN { n = split(ENVIRON["D"], d, "\n"); for (i = 1; i <= n; i++) { split(d[i], f, "\t"); cur[f[1]] = 1 } } $1 in cur'
}

# A draft that is no candidate this pass (its checks went green, say) keeps its
# raised row while the snapshot still shows it at that head, so a later failure
# at the same head is not raised twice. A candidate's row is set in the loop.
carried=$(printf '%s\n' "$prev_raised" | K=$cands D=$alldrafts awk -F '\t' '
  BEGIN { n = split(ENVIRON["K"], c, "\n"); for (i = 1; i <= n; i++) { split(c[i], f, "\t"); cand[f[1] "#" f[2]] = 1 }
          n = split(ENVIRON["D"], d, "\n"); for (i = 1; i <= n; i++) { split(d[i], f, "\t"); head[f[1]] = f[2] } }
  NF >= 2 && !($1 in cand) && head[$1] == $2 { print }')
[ -z "$carried" ] || new_raised="${new_raised}${carried}
"

save() {
  {
    keep "$new_raised" | awk -F '\t' 'NF >= 2 { print "raised\t" $1 "\t" $2 }'
    keep "$new_first" | awk -F '\t' 'NF >= 3 { print "first\t" $1 "\t" $2 "\t" $3 }'
  } | mc_write "$state" || mc_fail "cannot write $state"
}

if [ "$count" -eq 0 ]; then
  save
  exit 0
fi

noun=drafts
[ "$count" -ne 1 ] || noun=draft
text="$count stalled $noun: $events"
[ "$skipped" -eq 0 ] || text="${text}+$skipped more unread; "
[ "$deferred" -eq 0 ] || text="${text}+$deferred more next pass; "
text=$(printf '%s' "$text" | sed 's/; $//' | tr '\t\n\r' '   ' | mc_clean_text | cut -c1-500)
# A refused event leaves the drafts unrecorded, so the next pass raises them.
if ! mc_event emit --program "$program" --now "$NOW" -- draft-stalled draft-stalled "$text" >/dev/null; then
  new_raised=$prev_raised
  save
  mc_fail "the draft-stalled event was refused"
fi
save
printf 'raised\tdraft-stalled\t%s\n' "$count"
