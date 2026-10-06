#!/bin/sh
# turn-surface.sh — the deterministic stand-in every turn-shape fixture drives
# (operator-dialogue REQ-M1.1, D-19). A fixture's skill.sh execs this with its
# own scenario; the harness then drives it through the TTY like any fixture
# skill, and the turn-shape grader reads the decision log it writes.
#
# A live surface mirrors its own turn-side emissions into the same log; a
# stand-in replays what a surface would emit, including walls planted on
# purpose, in the schema the grader reads (the turn records, schema v2,
# described in tests/behavioral-evals/README.md). Scenarios are
# fixture-authored and trusted like any fixture skill.
#
# A scenario is JSON Lines, one operation per line (blank and `#` lines skip):
#   {"op":"write","name":N,"text":T}      write artifact N (relative, no ..)
#   {"op":"turn", ...}                    print the turn's text to the pane and
#                                         log it as a v2 turn record (every
#                                         field but op is kept)
#   {"op":"ask","phase":P,"text":Q}       prompt, read one answer, log an ask
#                                         and an answer record; with
#                                         "capture":ID the answer confirms or
#                                         declines that proposed capture
#   {"op":"capture","phase":P,"id":ID,"target":G,"ref":R,"text":T}
#                                         if ID was confirmed, write the tracked
#                                         record R and log the capture decision;
#                                         "halt":true records it unconfirmed, the
#                                         way a halt reaches Awaiting input
#
# Replay model (identical to the kickoff fixture): every read is `read ||
# exit 0` and the log is truncated at start, so the stub tmux can replay the
# accumulated answers and only a complete dialogue writes the run record.
#
# Usage: turn-surface.sh <scenario.jsonl> <artifacts-dir>
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

die() {
  printf 'turn-surface: %s\n' "$1" >&2
  exit 2
}

scenario="${1:-}"
art="${2:-}"
[ -n "$scenario" ] && [ -f "$scenario" ] || die "a readable scenario file is required"
[ -n "$art" ] || die "an artifacts directory argument is required"
mkdir -p "$art" 2>/dev/null || die "cannot create the artifacts dir"

log="$art/decision-log.jsonl"
: >"$log"

t=0
seq=0
confirmed=" "

append() {
  printf '%s\n' "$1" >>"$log" 2>/dev/null || die "failed to append a log record"
}

# field <json> <key> — the key's string value, or empty.
field() {
  printf '%s' "$1" | jq -r --arg k "$2" '.[$k] // "" | if type == "string" then . else tojson end'
}

# safe_name <rel> — an artifact name stays inside the artifacts dir.
safe_name() {
  case "$1" in
    '' | /* | *..* | *[!A-Za-z0-9._/-]*) return 1 ;;
    decision-log.jsonl | sign-off.json | sign-off.json.tmp) return 1 ;;
  esac
  return 0
}

put_file() {
  safe_name "$1" || die "unsafe artifact name in the scenario"
  mkdir -p "$(dirname "$art/$1")" 2>/dev/null || die "cannot create a dir for an artifact"
  printf '%s\n' "$2" >"$art/$1" || die "cannot write an artifact"
}

while IFS= read -r line <&3 || [ -n "$line" ]; do
  case "$line" in
    '' | '#'*) continue ;;
  esac
  op="$(field "$line" op)"
  case "$op" in
    write)
      put_file "$(field "$line" name)" "$(field "$line" text)"
      ;;
    turn)
      seq=$((seq + 1))
      rec="$(printf '%s' "$line" | jq -c --argjson seq "$seq" 'del(.op) + {v: 2, seq: $seq, kind: "turn"}')" \
        || die "malformed turn operation"
      append "$rec"
      text="$(field "$line" text)"
      case "$text" in
        *turn=*) die "a turn's text must not carry the driver anchor" ;;
      esac
      printf '%s\n\n' "$text"
      ;;
    ask)
      t=$((t + 1))
      phase="$(field "$line" phase)"
      cap="$(field "$line" capture)"
      case "$(field "$line" text)" in
        *turn=*) die "a prompt must not carry the driver anchor" ;;
      esac
      printf '%s\n' "$(field "$line" text)"
      printf 'EVAL-READY turn=%s\n' "$t"
      IFS= read -r answer || exit 0
      seq=$((seq + 1))
      append "$(jq -cn --argjson seq "$seq" --arg p "$phase" --arg q "$(field "$line" text)" \
        '{v: 2, seq: $seq, phase: $p, kind: "ask", text: $q}')"
      seq=$((seq + 1))
      if [ -n "$cap" ]; then
        case "$answer" in
          confirm* | Confirm* | yes* | Yes*)
            confirmed="$confirmed$cap "
            verdict="confirms"
            ;;
          *) verdict="declines" ;;
        esac
        append "$(jq -cn --argjson seq "$seq" --arg p "$phase" --arg a "$answer" --arg k "$verdict" --arg id "$cap" \
          '{v: 2, seq: $seq, phase: $p, kind: "answer", text: $a} + {($k): $id}')"
      else
        append "$(jq -cn --argjson seq "$seq" --arg p "$phase" --arg a "$answer" \
          '{v: 2, seq: $seq, phase: $p, kind: "answer", text: $a}')"
      fi
      ;;
    capture)
      id="$(field "$line" id)"
      case "$confirmed" in
        *" $id "*) ;;
        *) [ "$(field "$line" halt)" = "true" ] || continue ;;
      esac
      ref="$(field "$line" ref)"
      put_file "$ref" "$(field "$line" text)"
      seq=$((seq + 1))
      append "$(jq -cn --argjson seq "$seq" --arg p "$(field "$line" phase)" --arg id "$id" \
        --arg g "$(field "$line" target)" --arg r "$ref" \
        '{v: 2, seq: $seq, phase: $p, kind: "decision", capture: {id: $id, target: $g, ref: $r}}')"
      ;;
    *) die "unknown scenario operation" ;;
  esac
done 3<"$scenario"

# The run record doubles as the harness's completion sentinel, so it is
# published atomically and marked eval-only like every fixture's.
subject="$(basename "$(dirname "$scenario")")"
if ! jq -n --arg s "$subject" --argjson n "$t" \
  '{subject: $s, eval_only: true, authoritative: false, completed: true, answers: $n}' \
  >"$art/sign-off.json.tmp"; then
  die "cannot build the run record"
fi
mv "$art/sign-off.json.tmp" "$art/sign-off.json" || die "cannot publish the run record"
