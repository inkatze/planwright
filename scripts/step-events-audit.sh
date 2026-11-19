#!/bin/sh
# step-events-audit.sh — judge step records against the session that wrote them.
# Usage: step-events-audit.sh --worktree <dir> --records <file> [--run <id>]...
#   --records  `step-record.sh list --effective` output (a start or end corrected
#              by step-record.sh supersede is the one judged); --run restricts
#              the runs.
# A record is hand-written by the session it describes, so its claims are held
# against that session's stream-json events.jsonl: one whose `cwd` is the
# worktree, or one launched elsewhere whose events name its path (it vouches for
# a Skill start and the Agent calls of the session holding that Skill call,
# never the fix-round floor). Faults:
#   - an in-session skill step starts on the second of its Skill tool call;
#   - a polish or self-review recorded passed or applied has an Agent tool
#     call inside its span;
#   - a fix-round step does not start before the first event of the earliest
#     session live at its end (any session when none is), unless it repeats
#     the start of an earlier run's record of the same step;
#   - a polish recorded passed ended on its start head (record alone).
#
# Output:
#   fault<TAB><run>:<point>:<seq><TAB><step><TAB><message>
#   unverified<TAB><run>:<point>:<seq><TAB><step><TAB><why>
# unverified: events unreachable, unreadable or without timestamps, or no
# session launched in the worktree to set a fix-round floor.
# Exit 0 no fault, 1 a fault, 2 usage, 4 the records cannot be read.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

die() {
  printf 'step-events-audit: %s\n' "$2" >&2
  exit "$1"
}

worktree='' records='' runs=''
while [ $# -gt 0 ]; do
  case $1 in
    --worktree | --records | --run) [ $# -ge 2 ] || die 2 "$1: needs a value" ;;
    *) die 2 "usage: step-events-audit.sh --worktree <dir> --records <file> [--run <id>]..." ;;
  esac
  case $1 in
    --worktree) worktree=$2 ;;
    --records) records=$2 ;;
    --run) runs="$runs $2" ;;
  esac
  shift 2
done
[ -n "$worktree" ] && [ -n "$records" ] || die 2 "--worktree and --records are required"
[ -f "$records" ] || die 4 "--records: not a readable file"
worktree=$(cd -P -- "$worktree" && pwd -P) || die 2 "--worktree: not a directory"

work=$(mktemp -d "${TMPDIR:-/tmp}/step-events-audit.XXXXXX") || die 4 "cannot create a temporary directory"
trap 'rm -rf "$work"' EXIT

# find_own_events: print the events file of every stream-json session whose cwd
# is this worktree, one a line, or nothing.
find_own_events() {
  root=$(/bin/sh "$script_dir/fleet-state.sh" root) || return 0
  for d in "$root"/streamjson/*/; do
    [ -f "${d}cwd" ] && [ -f "${d}events.jsonl" ] && [ ! -L "${d}events.jsonl" ] || continue
    c=''
    read -r c <"${d}cwd" || [ -n "$c" ] || continue
    [ "$c" = "$worktree" ] && printf '%s\n' "${d}events.jsonl"
  done
}

# find_named_events: print the events file of every other stream-json session
# whose events name this worktree's path, one a line, or nothing. Batched greps
# over all sessions (a fork per session costs seconds on a host with many;
# find also skips links and non-files). The path must end where a path ends (a
# separator, a quote, a space or an escape), so a longer path that begins with
# it is not this worktree. step-record.sh's event_files uses the same
# patterns; change both together.
find_named_events() {
  root=$(/bin/sh "$script_dir/fleet-state.sh" root) || return 0
  find "$root/streamjson" -maxdepth 2 -name events.jsonl -type f \
    -exec grep -aFl -e "$worktree/" -e "$worktree\"" -e "$worktree " -e "$worktree\\" -e "$worktree'" -e "$worktree;" -e "$worktree)" -- {} + 2>/dev/null | while IFS= read -r f; do
    c=''
    if [ -f "${f%events.jsonl}cwd" ]; then read -r c <"${f%events.jsonl}cwd" || [ -n "$c" ] || c=''; fi
    [ "$c" = "$worktree" ] || printf '%s\n' "$f"
  done
}

# events_rows <firsts: true|false> <source> [<file>...]: the rows of events read
# from the files or standard input. Line by line, so a live session's
# half-written last line drops only itself; a tool input is written by the
# session under audit, so it loses its tabs and line breaks before it can shape
# a row. `first` rows (when a session opened and closed) come from the
# worktree's own sessions only: the fix-round floor rests on them. Each call
# row carries its source, `own` or the events file of a session that only names
# the worktree.
events_rows() {
  firsts=$1 src=$2
  shift 2
  # shellcheck disable=SC2016 # a jq program
  jq -R -r --argjson firsts "$firsts" --arg src "$src" 'input_filename as $f | (fromjson? // empty) | objects
    | select((.timestamp | type) == "string"
        and (.timestamp | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$")))
    | (.timestamp[0:19] + "Z") as $t
    | (if $firsts then "first\t" + $t + "\t" + $f else empty end),
      ((.message.content? // [])[]? | select(type == "object" and .type == "tool_use")
        | select(.name == "Skill" or .name == "Agent" or .name == "Task")
        | "call\t" + $t + "\t" + .name + "\t"
          + ((.input.skill? // "") | tostring | gsub("[\t\n\r]"; " ")) + "\t" + $src)' "$@"
}

: >"$work/events.tsv"
have_events=0 why='the session events are not reachable' have_first=0
find_own_events >"$work/files"
find_named_events >"$work/named"
if [ -s "$work/files" ] || [ -s "$work/named" ]; then
  if [ -z "$(command -v jq)" ]; then
    why='jq is not installed, so the session events cannot be read'
  else
    ok=1
    if [ -s "$work/files" ]; then
      set --
      while IFS= read -r f; do set -- "$@" "$f"; done <"$work/files"
      events_rows true own "$@" >>"$work/events.tsv" || ok=0
    fi
    # Only the lines that can make a call row are parsed: a long hub session
    # that names the worktree is megabytes of other events. The harness writes
    # compact JSON, which these patterns assume.
    while [ "$ok" -eq 1 ] && IFS= read -r f; do
      grep -aF -e '"name":"Skill"' -e '"name":"Agent"' -e '"name":"Task"' -- "$f" 2>/dev/null \
        | events_rows false "$f" >>"$work/events.tsv" || ok=0
    done <"$work/named"
    if [ "$ok" -eq 0 ]; then
      why='the session events cannot be parsed'
    elif [ -s "$work/events.tsv" ]; then
      have_events=1
    else
      why='the session events carry no timestamps'
    fi
  fi
fi
# The fix-round floor rests on the worktree's own sessions alone.
why_first=$why
if [ "$have_events" -eq 1 ]; then
  if grep -q '^first' "$work/events.tsv"; then
    have_first=1
  elif [ -s "$work/files" ]; then
    why_first='the session events carry no timestamps'
  else
    why_first='no session was launched in the worktree, so the session floor cannot be checked'
  fi
fi

hint='; a misdated start is corrected, not re-recorded, with step-record.sh supersede (cite the session event)'
awk -F '\t' -v RUNS="$runs" -v HAVE="$have_events" -v HAVEF="$have_first" -v WHY="$why" -v WHYF="$why_first" -v HINT="$hint" '
  function days(y, m, d,   era, yoe, doy, doe) {
    if (m <= 2) y--
    era = int(y / 400); yoe = y - era * 400
    doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
    doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
    return era * 146097 + doe - 719468
  }
  function epoch(t) {
    return days(substr(t, 1, 4) + 0, substr(t, 6, 2) + 0, substr(t, 9, 2) + 0) * 86400 \
      + substr(t, 12, 2) * 3600 + substr(t, 15, 2) * 60 + substr(t, 18, 2)
  }
  function absdiff(a, b) { a = epoch(a) - epoch(b); return a < 0 ? -a : a }
  function skill_name(t,   w, n) {
    sub(/^\//, "", t); split(t, w, " "); t = w[1]
    if (t ~ /\/SKILL\.md$/) { n = split(t, w, "/"); t = w[n - 1] }
    sub(/^[^:]*:/, "", t)
    return t
  }
  function fault(msg) { print "fault\t" id "\t" F["step"] "\t" msg; bad = 1 }
  function unverified() { print "unverified\t" id "\t" F["step"] "\t" WHY }
  function judge(   sk, o, near, d, best, i, got, span, s, e, floor) {
    o = F["outcome"]
    sk = F["kind"] == "skill" ? skill_name(F["target"]) : ""
    if (o == "passed" && (sk == "polish" || F["step"] == "polish") && F["head"] != F["end-head"])
      fault("polish recorded passed, but the head moved (head " F["head"] ", end-head " F["end-head"] "); a polish that moved the head is recorded applied")
    if (o == "skipped") return
    s = F["start"]; e = F["end"]
    need1 = F["kind"] == "skill" && F["hosting"] == "in-session"
    need2 = need1 && (sk == "polish" || sk == "self-review") && (o == "passed" || o == "applied")
    need5 = F["step"] ~ /^fix-round/
    if (!(need1 || need5)) return
    if (!HAVE) { unverified(); return }
    if (need5 && !HAVEF) { print "unverified\t" id "\t" F["step"] "\t" WHYF; return }
    if (need1) {
      best = -1; got = 0; split("", from)
      for (i = 1; i <= nsk[sk]; i++) {
        if (skt[sk, i] == s) { got = 1; from[sks[sk, i]] = 1; continue }
        d = absdiff(skt[sk, i], s)
        if (best < 0 || d < best) { best = d; near = skt[sk, i] }
      }
      # With no session launched in the worktree, sessions that merely name it
      # cannot prove a call absent.
      if (!got && !HAVEF) { print "unverified\t" id "\t" F["step"] "\t" WHYF; return }
      if (!got) fault("start " s " is not the second of the " sk " Skill call; the session events show " (nsk[sk] ? "its nearest call at " near : "no such call") HINT)
    }
    if (need2) {
      span = 0
      # A session that only names the worktree vouches for an Agent call only
      # when it is the one whose Skill call vouched for the start (a start that
      # matched no call is already a fault).
      for (i = 1; i <= nag; i++) if (agt[i] >= s && agt[i] <= e && (ags[i] == "own" || !got || (ags[i] in from))) { span = 1; break }
      if (!span) fault("recorded " o ", but the session events show no Agent tool call between " s " and " e)
    }
    if (need5) {
      floor = ""
      for (i in sf) if (sf[i] <= e && sl[i] >= e && (floor == "" || sf[i] < floor)) floor = sf[i]
      if (floor == "") floor = first
      if (floor != "" && s < floor && !(((F["step"] SUBSEP s) in rstart) && rstart[F["step"] SUBSEP s] != curun)) fault("start " s " is before the session first event at " floor HINT)
    }
  }
  # A round repeated in a later run by a fresh records worker keeps the start of
  # the earlier record of that round; only the start of an earlier run counts.
  function note_start(run) {
    if (!((F["step"] SUBSEP F["start"]) in rstart)) rstart[F["step"] SUBSEP F["start"]] = run
  }
  function flush(   n, parts, b) {
    if (!inrec) return
    inrec = 0
    n = split(path, parts, "/"); b = parts[n]
    if (b !~ /^[0-9][0-9][0-9]-step-[a-z][a-z-]*\.rec$/) return
    if (F["type"] != "step") return
    if (RUNS != "" && index(" " RUNS " ", " " parts[n - 1] " ") == 0) { note_start(parts[n - 1]); return }
    id = parts[n - 1] ":" substr(b, 10, length(b) - 13) ":" substr(b, 1, 3)
    curun = parts[n - 1]
    judge()
    note_start(parts[n - 1])
  }
  FILENAME == ARGV[1] {
    if ($1 == "first") {
      if (first == "" || $2 < first) first = $2
      if (!($3 in sf) || $2 < sf[$3]) sf[$3] = $2
      if (!($3 in sl) || $2 > sl[$3]) sl[$3] = $2
    }
    else if ($1 == "call" && $3 == "Skill") { sk = $4; sub(/^[^:]*:/, "", sk); skt[sk, ++nsk[sk]] = $2; sks[sk, nsk[sk]] = $5 }
    else if ($1 == "call") { agt[++nag] = $2; ags[nag] = $5 }
    next
  }
  $1 == "record" { flush(); inrec = 1; path = $2; split("", F); next }
  $0 == "" { flush(); next }
  inrec { k = $1; if (!(k in F)) F[k] = substr($0, length(k) + 2) }
  END { flush(); exit bad ? 1 : 0 }
' "$work/events.tsv" "$records"
