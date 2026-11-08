#!/usr/bin/env bash
# mc-throughput.sh — the throughput duty: measure where the program's time
# goes and raise the single biggest bottleneck to its mission control.
#
# `mc-throughput.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-throughput
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2

help_text() {
  cat <<'HELP'
mc-throughput.sh — the throughput duty: measure where the program's time
goes and raise the single biggest bottleneck to its mission control. Every
measurement is a read; the duty changes nothing it measures.

THE MEASUREMENTS, over the last mission_control_throughput_window (stalls
as they stand now):
  ci         per workflow and job, of the newest
             mission_control_throughput_ci_runs Actions runs (at most 100,
             one forge page) of each program repository's GitHub remote
             (gh api, jq), runs last updated before the window skipped and
             every page of a run's jobs read: the queue time (created to
             started; a job neither completed nor in progress counts to
             now, one that finished unstarted to its finish, never below
             zero) against the run time (started to completed). With more
             than one GitHub repository measured, a key is prefixed with
             its owner/name. A repository with no GitHub remote, or not on
             this machine, is named in the source line, not measured.
  approvals  every permission request in the program's stream-json worker
             journals (<fleet home>/streamjson/<session>/journal, a regular
             file): received to answered, a pending one counted to now
  stalls     every launched session of the program but its mission control
             whose stall sample (scripts/mc-stall.sh, the runtime
             directory's stall/) reads idle, idle-question, open-selector,
             unsubmitted-prompt, turn-ended-background, busy-unchanged or
             dead: the time since its pane last changed. A session with no
             current sample is named in the source line; with none sampled
             the source is unknown.
  steps      every cadence step record (start to end; a skipped step
             aside) in the program repositories' worktrees (a repository
             not on this machine named in the source line) and the program
             home's reclaimed copies, read with `step-record.sh list`, per
             step id, naming the branch of the slowest; a record with the
             same step, branch, run, sequence, point, start and end as one
             already read is a copy
A stream-json session is the program's when its registry row names the
program, or, with no row, when its name is the launcher's readable form
mc-<program>-<kind>-<10 hex>. A source that cannot be read is named
unknown, with the reason, and contributes nothing: an unread source is
never shown as zero.

THE TOP BOTTLENECK: a measurement is a bottleneck when its typical value
(the median CI queue or permission wait, or the median step run; the
longest stall) reaches its threshold in
mission_control_throughput_thresholds. Of those, the top one is the one
that cost the most time in all over the window (ties: the larger typical
value against its threshold, then the key). A total counts only the time
inside the window: a wait, stall or step that began before it adds the
part the window holds.

Usage:
  mc-throughput.sh measure --program <p> [--now <epoch>]
      source<TAB><name><TAB>ok|unknown<TAB><detail>
      ci<TAB>[<owner/name> ]<workflow / job><TAB><jobs><TAB>
        <queue median s><TAB><queue total s><TAB><queue max s><TAB>
        <run median s|->
      approvals<TAB>permission<TAB><requests><TAB><median s><TAB><total s>
        <TAB><max s><TAB><slowest session><TAB><pending><TAB>
        <longest pending s|->
      stall<TAB><session><TAB><state><TAB><seconds>
      step<TAB><step id><TAB><runs><TAB><median s><TAB><total s><TAB>
        <max s><TAB><slowest branch>
  mc-throughput.sh top --program <p> [--now <epoch>]
      the measure lines, then
        top<TAB><key><TAB><total s><TAB><text>   or   top<TAB>none
  mc-throughput.sh curve --program <p> [--now <epoch>]
      cost per model request against context size, from each of the
      program's stream-json sessions' event captures last written inside
      the window, each read whole (jq; a frame that does not parse is
      skipped alone):
        source<TAB>cost<TAB>ok|unknown<TAB><detail>
        request<TAB><session><TAB><n><TAB><percent|-><TAB><context tokens>
          <TAB><window|-><TAB><cost>
        curve<TAB><band>%<TAB><requests><TAB><median context tokens><TAB>
          <mean cost per request>
        curve<TAB>unknown<TAB><requests with no known window>
      a band is 0-9, 10-19 and so on, and 100+ for a request at or past
      its window; context tokens are input plus cache reads and writes; the
      cost is in input-token equivalents at the list-price ratios (cache
      read 0.1, 5-minute write 1.25, 1-hour write 2, output 5; a cache
      write with no 5-minute and 1-hour breakdown is priced as 5-minute),
      not dollars; the window is the capture's own result frame's, else
      the session's format-1 context reading
      (<fleet home>/mission-control/context/<name>, key `window`)
  mc-throughput.sh watch [--program <p>] [--now <epoch>]
      the duty's watcher (also a run with no arguments under the runner):
      measures at most once per mission_control_throughput_interval
      (`skipped<TAB>interval` otherwise), printing the measure lines;
      writes the measurement and the curve to the program home's
      kb/throughput/ under the knowledge-base lock; and emits the top
      bottleneck as a throughput-bottleneck event, its subject the key, or
      throughput-<checksum> for a key outside the subject grammar, its text
      the numbers and each unknown source with its reason, within 500
      bytes (the source named alone when its reason does not fit beside
      the numbers), printing
        raised<TAB><key><TAB><total s>   or   held<TAB><key><TAB><total s>
      A key is raised again only once its total grows by
      mission_control_throughput_worsen percent over the total it was last
      raised at, and forgotten once it is no longer a bottleneck while its
      source reads, so it is raised afresh if it returns. The program from
      PLANWRIGHT_MC_PROGRAM when --program is absent.

Exit codes: 0 done; 1 an invalid knob, an unresolvable fleet home, runtime
directory or program home, a knowledge-base lock not taken, a store that
cannot be read or written, or an event the store refused; 2 usage; 3 the
program is not configured.

Portable bash 3.2 / BSD tooling.
HELP
}

usage() {
  mc_usage_fail "usage: mc-throughput.sh measure|top|curve --program <p> [--now <epoch>]; mc-throughput.sh watch [--program <p>] [--now <epoch>]; mc-throughput.sh --help"
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
case $verb in
  measure | top | curve | watch) ;;
  *) usage ;;
esac
program=""
now=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --now)
      [ $# -ge 2 ] || usage
      mc_valid_text "$2" || mc_usage_fail "$1 takes text with no control byte"
      case $1 in
        --program) program=$2 ;;
        --now) now=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ "$verb" != watch ] || [ -n "$program" ] || program=${PLANWRIGHT_MC_PROGRAM:-}
[ -n "$program" ] || usage
mc_now_arg "$now"
mc_require_program "$program"

# parse_thresholds <raw>: the thresholds map as key<TAB>seconds lines, every
# known key once and no other.
parse_thresholds() {
  pt_lines=$(mc_map "$1") || return 1
  pt_out=""
  for pt_k in ci-queue approval-wait stall step; do
    pt_v=$(mc_lookup "$pt_k" "$pt_lines")
    pt_s=$(mc_seconds "$pt_v") || return 1
    pt_out="$pt_out$pt_k	$pt_s
"
  done
  printf '%s\n' "$pt_lines" | awk -F '\t' '$1 !~ /^(ci-queue|approval-wait|stall|step)$/ || ($1 in seen) { exit 1 } { seen[$1] = 1 }' || return 1
  printf '%s' "$pt_out"
}

knob_secs() { # knob_secs <key>
  ks=$(mc_knob "$1" mc_parse_cadence) || exit 1
  mc_seconds "$ks"
}
# load_window: the window, for every verb that reads; load_knobs: it, the
# thresholds and the CI run count, for a verb that measures.
load_window() {
  WINDOW=$(knob_secs mission_control_throughput_window) || exit 1
  SINCE=$((NOW - WINDOW))
}
load_knobs() {
  load_window
  THRESHOLDS=$(mc_knob mission_control_throughput_thresholds parse_thresholds) || exit 1
  CI_RUNS=$(mc_knob mission_control_throughput_ci_runs parse_ci_runs) || exit 1
}
# The Actions runs list is one forge page, which holds at most 100 runs.
parse_ci_runs() {
  mc_parse_count "$1" >/dev/null && [ "$1" -le 100 ] || return 1
  printf '%s\n' "$1"
}
threshold() { mc_lookup "$1" "$THRESHOLDS"; }

FLEET=$(mc_fleet_home) || mc_fail "cannot resolve the fleet home"
RUNTIME=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory of program $program"
KINDS="" KINDS_READ=0

# own_session <name>: 0 when a stream-json session is this program's, 1 when
# it is not, 2 when that cannot be told. Its registry row decides when it has one; otherwise only the launcher's
# readable name, mc-<program>-<kind>-<10 hex>, does (a longer program name
# falls back to a name that carries no program, so it needs the row). A
# name outside the registry's grammar (scripts/mc-stall.sh) never is.
own_session() {
  [ "${#1}" -le 64 ] || return 1
  case $1 in
    *[!a-z0-9-]*) return 1 ;;
  esac
  os_row="$FLEET/mission-control/sessions/$1"
  if [ -f "$os_row" ] && [ ! -L "$os_row" ]; then
    os_p=$(mc_kv "$os_row" program 2>/dev/null) || return 2
    [ "$os_p" = "$program" ]
    return
  fi
  os_rest=${1#"mc-$program-"}
  [ "$os_rest" != "$1" ] || return 1
  if [ "$KINDS_READ" != 1 ]; then
    KINDS=$(/bin/sh "$script_dir/mission-control-launch.sh" kinds 2>/dev/null </dev/null) || return 2
    KINDS=$(printf '%s\n' "$KINDS" | cut -f1)
    KINDS_READ=1
  fi
  for os_k in $KINDS; do
    case ${os_rest#"$os_k-"} in
      "$os_rest") ;;
      [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) return 0 ;;
    esac
  done
  return 1
}

unknown() { # unknown <source> <reason>
  printf 'source\t%s\tunknown\t%s\n' "$1" "$(printf '%s' "$2" | tr '\t\n' '  ' | mc_clean_text)"
}

# The awk helpers every reader shares. iso(s) is a UTC
# YYYY-MM-DDTHH:MM:SSZ timestamp in epoch seconds, -1 for anything else.
# shellcheck disable=SC2016 # an awk program
ISO_AWK='function iso(s,   y, m, d, t) {
  if (s !~ /^[0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-6][0-9](\.[0-9]+)?Z$/) return -1
  y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
  if (m <= 2) { y--; m += 12 }
  t = 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + d - 719469
  return t * 86400 + substr(s, 12, 2) * 3600 + substr(s, 15, 2) * 60 + substr(s, 18, 2)
}'

# aggregate: key<TAB>seconds[<TAB>who[<TAB>inside]] rows on stdin to one
# key<TAB>count<TAB>median<TAB>total<TAB>max<TAB>who-of-max row per key, the
# total summing each row's seconds inside the window where it gives them.
aggregate() {
  sort -t '	' -k1,1 -k2,2n | awk -F '\t' '
    function flush() {
      if (!have) return
      med = (c % 2) ? v[(c + 1) / 2] : int((v[c / 2] + v[c / 2 + 1]) / 2)
      print k "\t" c "\t" med "\t" tot "\t" v[c] "\t" who
    }
    NR == 1 || $1 != k { flush(); have = 1; k = $1; c = 0; tot = 0 }
    { v[++c] = $2; tot += (NF >= 4) ? $4 : $2; who = (NF >= 3) ? $3 : "-" }
    END { flush() }'
}

bounded() { /bin/sh "$script_dir/bounded-run.sh" 30 "$@"; }

# The program's repositories and home, read once (REPOS_OK, HOME_OK 1 when
# they resolved); call it outside a command substitution.
load_program() {
  REPOS_OK=0
  HOME_OK=0
  if REPOS=$(/bin/bash "$script_dir/mc-program.sh" get "$program" repositories 2>/dev/null); then REPOS_OK=1; fi
  if PHOME=$(/bin/bash "$script_dir/mc-program.sh" get "$program" home 2>/dev/null) && [ -n "$PHOME" ]; then HOME_OK=1; fi
}

# slug_of <repository>: owner/name of its origin remote on GitHub; 1 when
# it has no origin or one off GitHub, 2 when git cannot read it.
slug_of() {
  so_url=$(mc_untrusted_git -C "$1" remote get-url origin 2>/dev/null)
  case $? in
    0) ;;
    2) return 1 ;;
    *) return 2 ;;
  esac
  so_slug=$(printf '%s\n' "$so_url" | sed -n -e 's#^[a-z+]*://\([^@/]*@\)\{0,1\}github\.com\(:[0-9]*\)\{0,1\}/##p' -e 's#^[^@/:]*@github\.com:##p' | sed -e 's#/$##' -e 's#\.git$##')
  mc_valid_slug "$so_slug" || return 1
  printf '%s\n' "$so_slug"
}

# The jq definition every forge read shares: a name with its control bytes
# (C0, DEL, C1) dropped, so forge text never reaches a terminal or a store raw.
# Fields are joined with a tab rather than @tsv, which would double a
# backslash that `read` then keeps; clean leaves no tab or newline to join.
# shellcheck disable=SC2016 # a jq program
JQ_CLEAN='def clean: tostring | explode | map(select(. >= 32 and . != 127 and (. < 128 or . > 159))) | implode;'

# ci_runs <slug> <count>: <run id><TAB><workflow> per newest run updated
# inside the window (an older run holds no job the window keeps).
ci_runs() {
  cr_json=$(bounded gh api "repos/$1/actions/runs?per_page=$2" 2>/dev/null) || return 1
  printf '%s\n' "$cr_json" | SINCE=$SINCE jq -r "$JQ_CLEAN"' .workflow_runs[]
    | select(((.updated_at // "") | try fromdateiso8601 catch (env.SINCE | tonumber)) >= (env.SINCE | tonumber))
    | [(.id | clean), (.name | clean)] | join("\t")' 2>/dev/null
}

# ci_jobs <slug> <run id> <workflow>: <slug><TAB><workflow / job><TAB>
# <status><TAB><created><TAB><started|-><TAB><completed|-> per job that
# was not skipped, every page of them.
ci_jobs() {
  cj_json=$(bounded gh api --paginate "repos/$1/actions/runs/$2/jobs?per_page=100" 2>/dev/null) || return 1
  printf '%s\n' "$cj_json" | W=$3 S=$1 jq -r "$JQ_CLEAN"' .jobs[] | select(.conclusion != "skipped")
    | [env.S, env.W + " / " + (.name | clean), (.status | clean), (.created_at | clean),
      (.started_at // "-" | clean), (.completed_at // "-" | clean)] | join("\t")' 2>/dev/null
}

measure_ci() {
  command -v gh >/dev/null 2>&1 || {
    unknown ci "gh is not on PATH"
    return 0
  }
  command -v jq >/dev/null 2>&1 || {
    unknown ci "jq is not on PATH"
    return 0
  }
  [ "$REPOS_OK" = 1 ] || {
    unknown ci "the program's repositories do not resolve"
    return 0
  }
  ci_all=""
  ci_n=0
  ci_off=""
  ci_absent=""
  while IFS= read -r ci_repo; do
    [ -n "$ci_repo" ] || continue
    # A repository not cloned here, or with no GitHub remote, has no Actions
    # to measure: named, never a reason to leave the others unmeasured.
    if [ ! -d "$ci_repo" ]; then
      ci_absent="$ci_absent${ci_absent:+, }$ci_repo"
      continue
    fi
    ci_slug=$(slug_of "$ci_repo")
    case $? in
      0) ;;
      1)
        ci_off="$ci_off${ci_off:+, }$ci_repo"
        continue
        ;;
      *)
        unknown ci "cannot read the origin remote of $ci_repo"
        return 0
        ;;
    esac
    ci_n=$((ci_n + 1))
    ci_list=$(ci_runs "$ci_slug" "$CI_RUNS") || {
      unknown ci "the Actions runs of $ci_slug cannot be read"
      return 0
    }
    while IFS='	' read -r ci_id ci_wf; do
      [ -n "$ci_id" ] || continue
      mc_valid_uint "$ci_id" || {
        unknown ci "an Actions run id of $ci_slug is malformed"
        return 0
      }
      ci_j=$(ci_jobs "$ci_slug" "$ci_id" "$ci_wf") || {
        unknown ci "the jobs of $ci_slug run $ci_id cannot be read"
        return 0
      }
      [ -z "$ci_j" ] || ci_all="$ci_all$ci_j
"
    done <<EOF
$ci_list
EOF
  done <<EOF
$REPOS
EOF
  ci_skip="${ci_off:+; no GitHub remote: $ci_off}${ci_absent:+; not on this machine: $ci_absent}"
  if [ "$ci_n" = 0 ] && [ -n "$ci_skip" ]; then
    unknown ci "no repository measured$ci_skip"
    return 0
  fi
  printf 'source\tci\tok\t%s repositories%s\n' "$ci_n" "$ci_skip"
  [ -n "$ci_all" ] || return 0
  # A job not yet running (queued, waiting, pending or requested, whatever
  # start time the forge gives it) counts its wait to now; one in progress
  # has no run time yet; one that finished unstarted waited until it finished. A clock
  # behind the forge's never makes a wait negative.
  ci_rows=$(printf '%s' "$ci_all" | MULTI=$ci_n SINCE=$SINCE NOW=$NOW awk -F '\t' "$ISO_AWK"'
    function w(x) { return (x < 0) ? 0 : x }
    {
      c = iso($4); if (c < 0 || c < ENVIRON["SINCE"] + 0) next
      k = (ENVIRON["MULTI"] + 0 > 1) ? $1 " " $2 : $2
      s = iso($5); e = iso($6)
      if ($3 == "completed" && s < 0) { if (e >= 0) print k "\tq\t" w(e - c); next }
      if (($3 != "completed" && $3 != "in_progress") || s < 0) { print k "\tq\t" w(ENVIRON["NOW"] - c); next }
      print k "\tq\t" w(s - c)
      if ($3 == "completed" && e >= s) print k "\tr\t" (e - s)
    }')
  q=$(printf '%s\n' "$ci_rows" | awk -F '\t' '$2 == "q" { print $1 "\t" $3 }' | aggregate)
  r=$(printf '%s\n' "$ci_rows" | awk -F '\t' '$2 == "r" { print $1 "\t" $3 }' | aggregate)
  [ -n "$q" ] || return 0
  printf '%s\n' "$q" | RUNS=$r awk -F '\t' '
    BEGIN { n = split(ENVIRON["RUNS"], l, "\n"); for (i = 1; i <= n; i++) { split(l[i], f, "\t"); if (f[1] != "") rm[f[1]] = f[3] } }
    { print "ci\t" $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" (($1 in rm) ? rm[$1] : "-") }'
}

measure_approvals() {
  ma_root="$FLEET/streamjson"
  if [ ! -d "$ma_root" ]; then
    printf 'source\tapprovals\tok\t0 journals\n'
    return 0
  fi
  [ -r "$ma_root" ] && [ -x "$ma_root" ] || {
    unknown approvals "cannot read $ma_root"
    return 0
  }
  ma_rows=""
  ma_n=0
  set +f
  for ma_d in "$ma_root"/mc-*/; do
    ma_d=${ma_d%/}
    own_session "${ma_d##*/}"
    case $? in
      0) ;;
      1) continue ;;
      *)
        set -f
        unknown approvals "cannot tell whether ${ma_d##*/} is the program's"
        return 0
        ;;
    esac
    [ -x "$ma_d" ] || {
      set -f
      unknown approvals "cannot read the folder of ${ma_d##*/}"
      return 0
    }
    # A link (to another session's journal, say) is not read, so no journal
    # counts twice.
    [ ! -L "$ma_d" ] && [ -f "$ma_d/journal" ] && [ ! -L "$ma_d/journal" ] || continue
    if ! ma_out=$(W=${ma_d##*/} SINCE=$SINCE NOW=$NOW awk -F '\t' '
        # An epoch second has at most 12 digits; a longer one would print
        # as an exponent no shell arithmetic reads.
        $2 == "permission" && $3 ~ /^[0-9]+$/ && length($3) <= 12 {
          if ($4 == "pending") e = ENVIRON["NOW"] + 0
          else if ($4 ~ /^(answered|undeliverable)$/ && $5 ~ /^[0-9]+$/ && length($5) <= 12) e = $5 + 0
          else next
          if (e < ENVIRON["SINCE"] + 0 || e < $3 + 0) next
          print "permission\t" (e - $3) "\t" ENVIRON["W"] "\t" (e - ($3 + 0 > ENVIRON["SINCE"] + 0 ? $3 : ENVIRON["SINCE"])) "\t" ($4 == "pending")
        }' "$ma_d/journal" 2>/dev/null); then
      set -f
      unknown approvals "cannot read the journal of ${ma_d##*/}"
      return 0
    fi
    ma_n=$((ma_n + 1))
    [ -z "$ma_out" ] || ma_rows="$ma_rows$ma_out
"
  done
  set -f
  printf 'source\tapprovals\tok\t%s journals\n' "$ma_n"
  [ -n "$ma_rows" ] || return 0
  ma_pending=$(printf '%s' "$ma_rows" | awk -F '\t' '$5 == 1 { if (!p++ || $2 + 0 > m) m = $2 + 0 } END { print (p + 0) "\t" (p ? m : "-") }')
  printf '%s' "$ma_rows" | cut -f1-4 | aggregate | P=$ma_pending awk -F '\t' '{ print "approvals\t" $0 "\t" ENVIRON["P"] }'
}

measure_stalls() {
  ms_reg="$FLEET/mission-control/sessions"
  if [ ! -d "$ms_reg" ]; then
    printf 'source\tstalls\tok\t0 sessions\n'
    return 0
  fi
  [ -r "$ms_reg" ] && [ -x "$ms_reg" ] || {
    unknown stalls "cannot read the session registry"
    return 0
  }
  ms_out=""
  ms_count=0
  ms_unsampled=""
  ms_sampled=0
  set +f
  for ms_row in "$ms_reg"/mc-*; do
    [ -f "$ms_row" ] && [ ! -L "$ms_row" ] || continue
    case ${ms_row##*/} in *.tmp.* | *[!a-z0-9-]*) continue ;; esac
    # The row is judged and its launch key cleaned as scripts/mc-stall.sh
    # cleans it when it writes the sample, in one read: empty when the row
    # is not one of this program's launched sessions.
    ms_key=$(P=$program awk -F '\t' '
      $1 ~ /^(format|program|state|kind|launched|token)$/ && !($1 in s) { s[$1] = 1; x = substr($0, length($1) + 2); gsub(/[^[:print:]]/, "", x); v[$1] = x }
      END {
        if (v["format"] != "1" || v["program"] != ENVIRON["P"] || v["state"] != "launched" || v["kind"] == "mission-control") exit
        k = (v["launched"] == "" ? "-" : v["launched"]) ":" (v["token"] == "" ? "-" : v["token"])
        print (k ~ /[^A-Za-z0-9:.-]/) ? "-" : k
      }' "$ms_row" 2>/dev/null) || {
      # A row removed since it was listed is a session retired mid-pass.
      [ -e "$ms_row" ] || continue
      set -f
      unknown stalls "cannot read the registry row ${ms_row##*/}"
      return 0
    }
    [ -n "$ms_key" ] || continue
    ms_count=$((ms_count + 1))
    ms_sample="$RUNTIME/stall/${ms_row##*/}"
    # scripts/mc-stall.sh refuses a linked sample; so does this reader.
    if [ -f "$ms_sample" ] && [ ! -L "$ms_sample" ]; then
      ms_line=$(head -n 1 "$ms_sample" 2>/dev/null) && [ -r "$ms_sample" ] || {
        if [ -e "$ms_sample" ]; then
          set -f
          unknown stalls "cannot read the stall sample of ${ms_row##*/}"
          return 0
        fi
        ms_line=""
      }
    else
      ms_line=""
    fi
    s_launch='' s_since='' s_state=''
    [ -z "$ms_line" ] || IFS='	' read -r s_launch _ s_since s_state <<EOF
$ms_line
EOF
    # No sample, one from an earlier launch under the same name, or one from
    # the future leaves the session unmeasured, which is said, not zero.
    if [ "$s_launch" != "$ms_key" ] || ! mc_valid_uint "$s_since" || [ "$s_since" -gt "$NOW" ]; then
      ms_unsampled="$ms_unsampled${ms_unsampled:+, }${ms_row##*/}"
      continue
    fi
    ms_sampled=$((ms_sampled + 1))
    case $s_state in
      idle | idle-question | open-selector | unsubmitted-prompt | turn-ended-background | busy-unchanged | dead) ;;
      *) continue ;;
    esac
    ms_out="${ms_out}stall	${ms_row##*/}	$s_state	$((NOW - s_since))
"
  done
  set -f
  if [ "$ms_count" -gt 0 ] && [ "$ms_sampled" = 0 ]; then
    unknown stalls "no current stall sample for any of the $ms_count sessions (scripts/mc-stall.sh samples them)"
    return 0
  fi
  printf 'source\tstalls\tok\t%s sessions%s\n' "$ms_count" "${ms_unsampled:+; no current stall sample: $ms_unsampled}"
  [ -z "$ms_out" ] || printf '%s' "$ms_out"
}

# step_rows <worktree> <branch>: <step><TAB><seconds><TAB><branch><TAB>
# <seconds inside the window><TAB><record identity> per step record of <worktree>'s cache that ended inside
# the window, read through scripts/step-record.sh, the cache's one reader.
step_rows() {
  sr_list=$(/bin/sh "$script_dir/step-record.sh" --worktree "$1" list 2>/dev/null </dev/null) || return 1
  printf '%s\n' "$sr_list" | B=$2 SINCE=$SINCE awk -F '\t' "$ISO_AWK"'
    # A branch name may carry C1 control bytes git allows; they never reach
    # a terminal or the store.
    BEGIN { b = ENVIRON["B"]; gsub(/[\001-\037\177]/, "", b); gsub(/\302[\200-\237]/, "", b) }
    function flush() {
      if (v["type"] == "step" && v["outcome"] != "skipped" && v["step"] ~ /^[A-Za-z0-9._-]+$/) {
        s = iso(v["start"]); e = iso(v["end"])
        if (s >= 0 && e >= s && e >= ENVIRON["SINCE"] + 0)
          print v["step"] "\t" (e - s) "\t" b "\t" (e - (s > ENVIRON["SINCE"] + 0 ? s : ENVIRON["SINCE"])) "\t" v["run"] ":" v["seq"] ":" v["point"] ":" v["start"] ":" v["end"]
      }
      delete v
    }
    $1 == "record" || $0 == "" { flush() }
    $0 != "" && !($1 in v) { v[$1] = substr($0, length($1) + 2) }
    END { flush() }'
}

# fresh <steps folder>: whether it holds a record written since the window
# began. A record that ended inside the window was written inside it, so a
# folder with none is passed over unread; a find that fails reads it. The
# age is reckoned from the real clock, so a --now pass sees the same cut.
fresh() {
  fr_min=$(((REAL_NOW - SINCE) / 60 + 1))
  [ "$fr_min" -ge 1 ] || fr_min=1
  fr_new=$(find "$1" -name '*.rec' -mmin "-$fr_min" 2>/dev/null </dev/null) || return 0
  [ -n "$fr_new" ]
}

measure_steps() {
  REAL_NOW=$(date +%s)
  st_repos=$REPOS
  [ "$REPOS_OK" = 1 ] || {
    unknown steps "the program's repositories do not resolve"
    return 0
  }
  st_rows=""
  st_n=0
  st_absent=""
  while IFS= read -r st_repo; do
    [ -n "$st_repo" ] || continue
    if [ ! -d "$st_repo" ]; then
      st_absent="$st_absent${st_absent:+, }$st_repo"
      continue
    fi
    # NUL-separated fields become lines, and a newline inside a path a
    # \001, so a worktree whose path holds a newline or a tab is passed
    # over rather than misread.
    st_pairs=$({ mc_untrusted_git -C "$st_repo" worktree list --porcelain -z 2>/dev/null || printf '\0failed\0'; } \
      | tr '\n\000' '\001\n' | awk '
        function emit() { if (w != "" && w !~ /[\001\t]/) print w "\t" b }
        $0 == "failed" { bad = 1 }
        /^worktree / { emit(); w = substr($0, 10); b = "-" }
        /^branch refs\/heads\// { b = substr($0, 19) }
        END { if (bad) exit 1; emit() }') || {
      unknown steps "cannot list the worktrees of $st_repo"
      return 0
    }
    while IFS='	' read -r st_wt st_branch; do
      [ -n "$st_wt" ] || continue
      # A worktree that cannot be searched is unread, not empty; one gone
      # since it was listed (a prunable entry, or removed mid-pass) holds
      # nothing to read.
      for st_p in "$st_wt" "$st_wt/.claude"; do
        if [ -d "$st_p" ] && [ ! -x "$st_p" ]; then
          unknown steps "cannot read the worktree $st_wt"
          return 0
        fi
      done
      [ -d "$st_wt/.claude/steps" ] || continue
      if ! fresh "$st_wt/.claude/steps"; then
        st_n=$((st_n + 1))
        continue
      fi
      st_out=$(step_rows "$st_wt" "$st_branch") || {
        [ -d "$st_wt/.claude/steps" ] || continue
        unknown steps "cannot read the step records of $st_wt"
        return 0
      }
      st_n=$((st_n + 1))
      [ -z "$st_out" ] || st_rows="$st_rows$st_out
"
    done <<EOF
$st_pairs
EOF
  done <<EOF
$st_repos
EOF
  st_home=$PHOME
  [ "$HOME_OK" = 1 ] || {
    unknown steps "the program home does not resolve"
    return 0
  }
  if [ -d "$st_home/reclaimed" ]; then
    # <home>/reclaimed/<repository>/<branch>/.claude/steps/...: the branch
    # is the path between the repository and .claude.
    st_dirs=$(find "$st_home/reclaimed" -type d -path '*/.claude/steps' -prune 2>/dev/null) || {
      unknown steps "cannot read the reclaimed folder"
      return 0
    }
    while IFS= read -r st_d; do
      [ -n "$st_d" ] || continue
      st_rel=${st_d#"$st_home/reclaimed/"}
      st_rel=${st_rel%/.claude/steps}
      st_branch=${st_rel#*/}
      if ! fresh "$st_d"; then
        st_n=$((st_n + 1))
        continue
      fi
      st_out=$(step_rows "${st_d%/.claude/steps}" "$st_branch") || {
        [ -d "$st_d" ] || continue
        unknown steps "cannot read the step records of $st_d"
        return 0
      }
      st_n=$((st_n + 1))
      [ -z "$st_out" ] || st_rows="$st_rows$st_out
"
    done <<EOF
$st_dirs
EOF
  fi
  printf 'source\tsteps\tok\t%s record folders%s\n' "$st_n" "${st_absent:+; not on this machine: $st_absent}"
  [ -n "$st_rows" ] || return 0
  # A reclaimed copy of a worktree still on disk holds the same records;
  # another cache of the same branch reuses run ids for other records.
  printf '%s' "$st_rows" | awk -F '\t' '!(($1, $3, $5) in seen) { seen[$1, $3, $5] = 1; print $1 "\t" $2 "\t" $3 "\t" $4 }' \
    | aggregate | awk '{ print "step\t" $0 }'
}

measure() {
  measure_ci
  measure_approvals
  measure_stalls
  measure_steps
}

# candidates <measure lines>: <key><TAB><typical><TAB><total><TAB>
# <threshold><TAB><text> per measurement at or over its threshold.
candidates() {
  printf '%s\n' "$1" | TCI=$(threshold ci-queue) TAP=$(threshold approval-wait) TST=$(threshold stall) TSP=$(threshold step) \
  W=$WINDOW awk -F '\t' '
    function d(s,   h, m) {
      s = int(s); if (s < 60) return s "s"
      if (s < 3600) return int(s / 60) "m"
      h = int(s / 3600); m = int((s % 3600) / 60)
      return (m ? h "h" m "m" : h "h")
    }
    function out(k, typ, tot, th, txt) { if (typ + 0 >= th + 0) print k "\t" typ "\t" tot "\t" th "\t" txt }
    $1 == "ci" { out("ci:" $2, $4, $5, ENVIRON["TCI"], "CI runner queue, " $2 ": median wait " d($4) " over " $3 " jobs, " d($5) " queued in all, longest " d($6) "; median run " ($7 == "-" ? "unknown" : d($7)) " (threshold " d(ENVIRON["TCI"]) ")") }
    $1 == "approvals" { out("approvals", $4, $5, ENVIRON["TAP"], "Permission approvals: median wait " d($4) " over " $3 " requests, " d($5) " waiting in all, longest " d($6) " on " $7 ", " $8 " pending now (threshold " d(ENVIRON["TAP"]) ")") }
    $1 == "stall" && $4 + 0 >= ENVIRON["TST"] + 0 { sn++; st += ($4 + 0 < ENVIRON["W"] + 0) ? $4 : ENVIRON["W"]; if ($4 + 0 > sl) { sl = $4 + 0; sw = $2 " " $3 } }
    $1 == "step" { out("step:" $2, $4, $5, ENVIRON["TSP"], "Slow cadence step " $2 ": median " d($4) " over " $3 " runs, " d($5) " in all, slowest " d($6) " on " $7 " (threshold " d(ENVIRON["TSP"]) ")") }
    END {
      if (sn) out("stalls", sl, st, ENVIRON["TST"], "Stalled or idle sessions: " sn " past " d(ENVIRON["TST"]) ", " d(st) " in all, longest " d(sl) " (" sw ")")
    }'
}

# pick <candidates>: the top candidate's line.
pick() {
  [ -n "$1" ] || return 0
  printf '%s\n' "$1" | awk -F '\t' '{ printf "%012d\t%012d\t%s\n", $3, int($2 * 1000 / ($4 > 0 ? $4 : 1)), $0 }' \
    | sort -t '	' -k1,1r -k2,2r -k3,3 | head -n 1 | cut -f3-
}

# top_line <measure lines> <candidates>: sets TOP (the top candidate's line
# or empty), its text in two parts, TOP_HEAD (the bottleneck) and TOP_NOTE
# (each unknown source with its reason, else empty), TOP_NAMES (those
# sources by name alone), and TOP_TEXT, the head and the note together.
top_line() {
  TOP=$(pick "$2")
  TOP_HEAD="" TOP_NOTE="" TOP_NAMES="" TOP_TEXT=""
  [ -n "$TOP" ] || return 0
  tl_unknown=$(printf '%s\n' "$1" | awk -F '\t' '$1 == "source" && $3 == "unknown" { printf "%s%s (%s)", (n++ ? "; " : ""), $2, $4 }')
  tl_names=$(printf '%s\n' "$1" | awk -F '\t' '$1 == "source" && $3 == "unknown" { printf "%s%s", (n++ ? ", " : ""), $2 }')
  TOP_HEAD="Top bottleneck over the last $(printf '%s' "$WINDOW" | awk '{ s = $1; if (s % 86400 == 0) print s / 86400 "d"; else if (s % 3600 == 0) print s / 3600 "h"; else print int(s / 60) "m" }'): $(printf '%s\n' "$TOP" | cut -f5)"
  [ -z "$tl_unknown" ] || TOP_NOTE=". Not measured: $tl_unknown"
  [ -z "$tl_names" ] || TOP_NAMES=". Not measured: $tl_names"
  TOP_TEXT="$TOP_HEAD$TOP_NOTE"
}

curve() {
  command -v jq >/dev/null 2>&1 || {
    unknown cost "jq is not on PATH"
    return 0
  }
  cv_root="$FLEET/streamjson"
  [ -d "$cv_root" ] || {
    printf 'source\tcost\tok\t0 captures\n'
    return 0
  }
  [ -r "$cv_root" ] && [ -x "$cv_root" ] || {
    unknown cost "cannot read $cv_root"
    return 0
  }
  cv_rows=""
  cv_n=0
  set +f
  for cv_d in "$cv_root"/mc-*/; do
    cv_d=${cv_d%/}
    own_session "${cv_d##*/}"
    case $? in
      0) ;;
      1) continue ;;
      *)
        set -f
        unknown cost "cannot tell whether ${cv_d##*/} is the program's"
        return 0
        ;;
    esac
    [ -x "$cv_d" ] || {
      set -f
      unknown cost "cannot read the folder of ${cv_d##*/}"
      return 0
    }
    cv_e="$cv_d/events.jsonl"
    [ ! -L "$cv_d" ] && [ -f "$cv_e" ] && [ ! -L "$cv_e" ] || continue
    # Inside the window: written since its start.
    # shell-gnu-only-flag: BSD stat -f is the fallback when GNU stat -c fails
    cv_m=$(stat -c %Y "$cv_e" 2>/dev/null || stat -f %m "$cv_e" 2>/dev/null) || {
      set -f
      unknown cost "cannot stat the capture of ${cv_d##*/}"
      return 0
    }
    [ "$cv_m" -ge "$SINCE" ] 2>/dev/null || continue
    # Every frame is judged alone and a malformed one yields nothing, since
    # jq's exit status reflects only its last input. A usage with no
    # cache_creation breakdown reports its cache writes as 5-minute ones.
    cv_out=$(jq -R -r 'fromjson? | try (
      if .type == "assistant" and (.message.usage | type) == "object" then
        .message.usage as $u
        | (if ($u.cache_creation | type) == "object"
          then [($u.cache_creation.ephemeral_5m_input_tokens // 0), ($u.cache_creation.ephemeral_1h_input_tokens // 0)]
          else [($u.cache_creation_input_tokens // 0), 0] end) as $w
        | ["m", (.message.id // "-"), ($u.input_tokens // 0), ($u.cache_read_input_tokens // 0), $w[0], $w[1],
          ($u.output_tokens // 0)] | @tsv
      elif .type == "result" and (.modelUsage | type) == "object" then
        ["w", ([.modelUsage[] | .contextWindow // 0] | max // 0)] | @tsv
      else empty end) catch empty' "$cv_e" 2>/dev/null) || {
      set -f
      unknown cost "cannot read the capture of ${cv_d##*/}"
      return 0
    }
    cv_n=$((cv_n + 1))
    cv_ctx="$FLEET/mission-control/context/${cv_d##*/}"
    cv_fw=-
    if [ -f "$cv_ctx" ] && [ "$(mc_kv "$cv_ctx" format 2>/dev/null)" = 1 ]; then
      cv_fw=$(mc_kv "$cv_ctx" window 2>/dev/null) || cv_fw=-
    fi
    [ -n "$cv_out" ] || continue
    cv_req=$(printf '%s\n' "$cv_out" | S=${cv_d##*/} FW=$cv_fw awk -F '\t' '
      $1 == "w" && $2 + 0 > win { win = $2 + 0 }
      # A message streams as several frames under one id: the last one holds
      # its final usage.
      $1 == "m" { if (!($2 in at)) ord[++n] = $2; at[$2] = $0 }
      END {
        if (!win && ENVIRON["FW"] ~ /^[1-9][0-9]*$/) win = ENVIRON["FW"] + 0
        for (i = 1; i <= n; i++) {
          split(at[ord[i]], f, "\t")
          ctx = f[3] + f[4] + f[5] + f[6]
          cost = f[3] + 0.1 * f[4] + 1.25 * f[5] + 2 * f[6] + 5 * f[7]
          print "request\t" ENVIRON["S"] "\t" i "\t" (win ? int(ctx * 100 / win) : "-") "\t" ctx "\t" (win ? win : "-") "\t" int(cost + 0.5)
        }
      }')
    [ -z "$cv_req" ] || cv_rows="$cv_rows$cv_req
"
  done
  set -f
  printf 'source\tcost\tok\t%s captures\n' "$cv_n"
  [ -n "$cv_rows" ] || return 0
  printf '%s' "$cv_rows"
  printf '%s' "$cv_rows" | awk -F '\t' '$4 == "-" { u++ } END { if (u) print "curve\tunknown\t" u }'
  printf '%s' "$cv_rows" | awk -F '\t' '$4 != "-" { b = int($4 / 10) * 10; if (b > 100) b = 100; print sprintf("%03d", b) "\t" $5 "\t" $7 }' \
    | sort -t '	' -k1,1 -k2,2n | awk -F '\t' '
      function flush() { if (!have) return; med = (c % 2) ? v[(c + 1) / 2] : int((v[c / 2] + v[c / 2 + 1]) / 2); print "curve\t" (k + 0 >= 100 ? "100+" : (k + 0) "-" (k + 9)) "%\t" c "\t" med "\t" int(cost / c + 0.5) }
      NR == 1 || $1 != k { flush(); have = 1; k = $1; c = 0; cost = 0 }
      { v[++c] = $2; cost += $3 }
      END { flush() }'
}

case $verb in
  measure)
    load_knobs
    load_program
    measure
    ;;
  top)
    load_knobs
    load_program
    m=$(measure)
    printf '%s\n' "$m"
    top_line "$m" "$(candidates "$m")"
    if [ -n "$TOP" ]; then
      printf 'top\t%s\t%s\t%s\n' "$(printf '%s\n' "$TOP" | cut -f1)" "$(printf '%s\n' "$TOP" | cut -f3)" "$TOP_TEXT"
    else
      printf 'top\tnone\n'
    fi
    ;;
  curve)
    load_window
    curve
    ;;
  watch)
    interval=$(knob_secs mission_control_throughput_interval) || exit 1
    last="$RUNTIME/throughput-last"
    if [ -f "$last" ]; then
      l=$(head -n 1 "$last" 2>/dev/null)
      if mc_valid_uint "$l" && [ "$l" -le "$NOW" ] && [ $((NOW - l)) -lt "$interval" ]; then
        printf 'skipped\tinterval\n'
        exit 0
      fi
    fi
    worsen=$(mc_knob mission_control_throughput_worsen mc_parse_count) || exit 1
    load_knobs
    load_program
    [ "$HOME_OK" = 1 ] || mc_fail "the home of program $program does not resolve"
    # The pass is stamped before it measures, so one that fails partway (a
    # store, the lock, the event or the memory) is not repeated, forge reads
    # and any event it emitted included, on every run inside the interval.
    printf '%s\n' "$NOW" | mc_write "$last" || mc_fail "cannot write $last"
    kb="$PHOME/kb/throughput"
    m=$(measure)
    printf '%s\n' "$m"
    c=$(candidates "$m")
    top_line "$m" "$c"
    mkdir -p "$kb" || mc_fail "cannot create $kb"
    cv=$(curve)
    trap mc_kb_unlock EXIT
    mc_kb_lock "$program" throughput/measure.tsv
    {
      printf '# format: 1\n'
      printf 'measured\t%s\n' "$NOW"
      printf '%s\n' "$m"
    } | mc_write "$kb/measure.tsv" || mc_fail "cannot write $kb/measure.tsv"
    {
      printf '# format: 1\n'
      printf 'measured\t%s\n' "$NOW"
      printf '%s\n' "$cv" | awk -F '\t' '$1 != "request"'
    } | mc_write "$kb/cost-curve.tsv" || mc_fail "cannot write $kb/cost-curve.tsv"
    mc_kb_unlock
    raised="$RUNTIME/throughput-raised"
    prev=""
    if [ -f "$raised" ]; then
      prev=$(cat "$raised") || mc_fail "cannot read $raised"
    fi
    # What is still a bottleneck stays remembered, and so does what this
    # run could not see, so a source's recovery raises nothing it already
    # raised.
    live=$(printf '%s\n' "$c" | cut -f1)
    blind=$(printf '%s\n' "$m" | awk -F '\t' '$1 == "source" && $3 == "unknown" { print $2 }')
    kept=$(printf '%s\n' "$prev" | LIVE=$live BLIND=$blind awk -F '\t' '
      function src(k) { if (k ~ /^ci:/) return "ci"; if (k ~ /^step:/) return "steps"; return k }
      BEGIN {
        n = split(ENVIRON["LIVE"], l, "\n"); for (i = 1; i <= n; i++) if (l[i] != "") k[l[i]] = 1
        n = split(ENVIRON["BLIND"], l, "\n"); for (i = 1; i <= n; i++) if (l[i] != "") b[l[i]] = 1
      }
      NF >= 2 && (($1 in k) || (src($1) in b))')
    if [ -n "$TOP" ]; then
      key=$(printf '%s\n' "$TOP" | cut -f1)
      total=$(printf '%s\n' "$TOP" | cut -f3)
      was=$(mc_lookup "$key" "$kept")
      if [ -n "$was" ] && mc_valid_uint "$was" && [ $((total * 100)) -lt $((was * (100 + worsen))) ]; then
        printf 'held\t%s\t%s\n' "$key" "$total"
      else
        subject=$key
        mc_valid_handle "$subject" || subject=$(mc_subject throughput "$key")
        # Every unmeasured source is named. When their reasons do not fit
        # beside the whole bottleneck (whose key a checksum subject does not
        # carry), the sources are named alone, the reasons left to
        # kb/throughput/measure.tsv; the bottleneck gives way only after that.
        ev_head=$(printf '%s' "$TOP_HEAD" | tr '\t\n\r' '   ' | mc_clean_text)
        note=$(printf '%s' "$TOP_NOTE" | tr '\t\n\r' '   ' | mc_clean_text)
        [ $((${#ev_head} + ${#note})) -le 500 ] || note=$(printf '%s' "$TOP_NAMES" | tr '\t\n\r' '   ' | mc_clean_text)
        note=$(printf '%s' "$note" | cut -c1-500)
        text=""
        [ "${#note}" -ge 500 ] || text=$(printf '%s' "$ev_head" | cut -c1-$((500 - ${#note})))
        mc_event emit --program "$program" --now "$NOW" -- throughput-bottleneck "$subject" "$text$note" >/dev/null || mc_fail "the throughput-bottleneck event was refused"
        kept=$(printf '%s\n' "$kept" | K=$key awk -F '\t' 'NF && $1 != ENVIRON["K"]')
        kept="${kept:+$kept
}$key	$total"
        printf 'raised\t%s\t%s\n' "$key" "$total"
      fi
    fi
    { [ -z "$kept" ] || printf '%s\n' "$kept"; } | mc_write "$raised" || mc_fail "cannot write $raised"
    ;;
esac
