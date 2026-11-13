#!/bin/sh
# mission-control/skill.sh — the mission control eval fixture skill. A
# DETERMINISTIC stand-in for the model-backed /mission-control session: driving
# the real skill needs a live Claude TTY session (nondeterministic, priced), so
# the assertable turn rules (skills/mission-control/SKILL.md) are pinned
# against this shell model of them. Whether the live session holds the same
# rules on input it has never seen is what a live run graded by grade.jq, and
# the operator, judge; see the fixtures README ("Mission control").
#
# It writes the eval seam grade.jq reads, never a scraped pane:
# decision-log.jsonl (one v2 record per operator line, event, turn and
# decision) and sign-off.json (an eval-only, non-authoritative run record).
#
# Input lines are the operator's own words, except lines starting `@event:`,
# which stand for what the stores, sessions and watchers report. An event is
# never the operator's words, so it is never a yes, a go, or an answer. An
# operator line starting `>` is pasted material: data, never a yes. The line
# `that's all` ends the session and writes the run record.
#
# Replay model (as the other fixtures): a read at EOF exits 0, so a partial
# replay stops before the run record is written.
#
# Usage: skill.sh <artifacts-dir>
# shellcheck disable=SC2016 # the $-sigils in quoted jq filters are jq bindings
set -u
LC_ALL=C
export LC_ALL

art="${1:-}"
if [ -z "$art" ]; then
  echo "mission-control/skill.sh: an artifacts directory argument is required" >&2
  exit 2
fi
mkdir -p -- "$art" 2>/dev/null || exit 2
log="$art/decision-log.jsonl"
run_record="$art/sign-off.json"
{ : >"$log"; } 2>/dev/null || exit 2
rm -f "$run_record" 2>/dev/null || exit 2

seq=0
t=0
phase=session

die_write() {
  printf '%s\n' "mission-control/skill.sh: failed to write $1" >&2
  exit 2
}
log_entry() {
  _le_kind="$1"
  _le_filter="$2"
  shift 2
  seq=$((seq + 1))
  jq -cn --argjson seq "$seq" --arg phase "$phase" --arg kind "$_le_kind" "$@" \
    "{v: 2, seq: \$seq, phase: \$phase, kind: \$kind} + ($_le_filter)" >>"$log" \
    || die_write "a decision-log record ($_le_kind)"
}
# say <text> [<jq-filter> [jq-args...]] — one line to the operator, mirrored.
say() {
  _sy_text="$1"
  _sy_filter='{}'
  if [ $# -ge 2 ]; then
    _sy_filter="$2"
    shift 2
  else
    shift 1
  fi
  printf 'Mission control: %s\n' "$_sy_text"
  log_entry present "{text: \$text} + ($_sy_filter)" --arg text "$_sy_text" "$@"
}
# decide <action> <jq-filter> [jq-args...] — one decision record.
decide() {
  _dc_action="$1"
  _dc_filter="$2"
  shift 2
  log_entry decision "{action: \$action} + ($_dc_filter)" --arg action "$_dc_action" "$@"
}
# item <id> <subject> <link> <does> <asks> <right> <checked> <cluster> — one
# answerable item: the link, what it does, what is asked, whether it is right,
# each option's effect and what was checked (REQ-F1.7).
item() {
  say "$5 ($3)" '{item: {id: $id, subject: $subject, link: $link, does: $does, asks: $asks, right: $right, checked: $checked, cluster: $cluster, options: [{label: "yes", effect: "go ahead as described"}, {label: "not now", effect: "parked until the trigger you name"}, {label: "no", effect: "declined and not raised again"}]}}' \
    --arg id "$1" --arg subject "$2" --arg link "$3" --arg does "$4" --arg asks "$5" \
    --arg right "$6" --arg checked "$7" --arg cluster "$8"
}
human() { printf '%s' "$1" | tr '_-' '  '; }
event_arg() {
  printf '%s\n' "$1" | tr ' ' '\n' | awk -v k="$2" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }'
}
sanitize() { printf '%s' "$1" | tr -d '\000-\037\177\200-\237'; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Session state.
programs=""
selector_subject=""
kickoff_selector=""
draft_person=""
draft_seq=""
proposal_seq=""
proposal_pattern=""
declined=" "
proposed=" "
present_here=1
queue=""
kickoff_mode=relay
inventory=""
fr_step=0
last_rule_seq=""
shadow_after=3
shadow_fires=0
busy=0
held=""
push=on
row_open=""
row_fired=""
repeats=""

# One objective per line, "ask:" or "state:" first: only what the operator can
# answer from their own work is asked; the rest is settled and said.
FIRST_RUN="ask:What is this work, and which repositories does it touch? I'd suggest this repository. One more question after this, then I write it all.
state:The written plans for this work are in this repository; say if they live elsewhere.
state:GitHub sign-in checked: you are signed in, and nothing is stored.
state:Work items, decisions and deadlines come from your written plans, code state from GitHub with its age, designs from what you tell me.
ask:I'd turn on these watches, each with what it saves you. Turn them all on, yes or no? That's the last question.
state:No voice note and no quiet hours yet; tell me either any time."

first_run_next() {
  while [ "$fr_step" -lt 6 ]; do
    fr_step=$((fr_step + 1))
    _ln=$(printf '%s\n' "$FIRST_RUN" | sed -n "${fr_step}p")
    if [ "${_ln%%:*}" = ask ]; then
      _left=$(printf '%s\n' "$FIRST_RUN" | sed -n "$((fr_step + 1)),\$p" | grep -c '^ask:')
      say "${_ln#*:}" '{first_run: {objective: $n, asked: true, left: $l}}' \
        --argjson n "$fr_step" --argjson l "$_left"
      return
    fi
    say "${_ln#*:}" '{first_run: {objective: $n, settled: true}}' --argjson n "$fr_step"
  done
  for w in program-block knowledge-base-skeleton enabled-watches standing-decisions; do
    decide write '{what: $w}' --arg w "$w"
    say "Wrote the $(human "$w")."
  done
  fr_step=0
  programs=new
}
first_run_answer() {
  say "Recorded: $1." '{first_run: {feedback: $n}}' --argjson n "$fr_step"
  first_run_next
}

# deliver — with the operator present, show the top queued item (consequence,
# then age) and every queued item coupled to it; nothing while away.
deliver() {
  [ "$present_here" -eq 1 ] || return 0
  [ -n "$queue" ] || return 0
  _ranked=$(printf '%s\n' "$queue" | sort -t'|' -k2,2nr -k3,3nr)
  _top=$(printf '%s\n' "$_ranked" | head -n 1)
  _tid=${_top%%|*}
  _cl=$(printf '%s' "$_top" | cut -d'|' -f4)
  while IFS='|' read -r qid _qcons _qage qcl qsub; do
    if [ "$qid" = "$_tid" ] || { [ -n "$_cl" ] && [ "$qcl" = "$_cl" ]; }; then
      item "$qid" "$qsub" "https://forge.example/$qid" "changes the $(human "$qsub")" \
        "Shall the $(human "$qsub") change go ahead?" "the checks pass and it matches what you asked" \
        "read the change and its checks" "$qcl"
    fi
  done <<RANKED
$_ranked
RANKED
  queue=$(printf '%s\n' "$queue" | awk -F'|' -v id="$_tid" -v cl="$_cl" '$1 != id && (cl == "" || $4 != cl)')
}

# propose <pattern> <names> <row> <ready_change> — one mechanization proposal
# in the confirmation shape, never twice for a pattern, never after a decline.
propose() {
  case "$declined" in *" $1 "*) return 0 ;; esac
  case "$proposed" in *" $1 "*) return 0 ;; esac
  proposed="$proposed$1 "
  decide proposal '{pattern: $p, names: $n, row: $r, ready_change: ($rc == "yes"), settings_written: false, decline_offered: true}' \
    --arg p "$1" --arg n "$2" --arg r "$3" --arg rc "$4"
  proposal_seq=$seq
  proposal_pattern=$1
  _ready=""
  [ "$4" = yes ] && _ready=" The change is ready for you to apply; I change no settings."
  say "You have done the $(human "$1") by hand twice. Shall I take it on, through the $(human "$3")?$_ready (yes / not now / no)" \
    '{proposal: $s, options: [{label: "yes", effect: "I take it on from now"}, {label: "not now", effect: "parked until you raise it"}, {label: "no", effect: "declined, never raised again"}]}' \
    --argjson s "$proposal_seq"
}

count_repeat() { printf '%s' "$repeats" | grep -cx "$1"; }
woke() {
  decide wake '{state: "delivered", via: $v}' --arg v "$1"
  say "New just now: a session finished its work."
}

handle_event() {
  ev="$1"
  name=${ev%% *}
  log_entry event '{source: "evidence", event: $e, raw: $r}' --arg e "$name" --arg r "$ev"
  case "$name" in
    bringup)
      decide bringup '{sources_read: ["registry", "git", "forge", "second"], state_file_read: false, contradiction_followed: "forge", cited_contributed: "links"}'
      say "From the stores: $(event_arg "$ev" registry) live sessions, $(event_arg "$ev" git) landed changes; the forge shows $(event_arg "$ev" forge) open (snapshot, 10 minutes old), designs $(event_arg "$ev" second) (snapshot, 1 hour old)."
      say "The forge and the last stored picture disagree; going by the forge."
      say "Tracker: cited, links only; nothing polled."
      ;;
    selector)
      selector_subject=$(event_arg "$ev" subject)
      item sel "$selector_subject" "https://forge.example/pull/7" "ships the $(human "$selector_subject")" \
        "The $(human "$selector_subject") work asks which order to ship. Which one?" \
        "both orders pass the checks" "read the question and both options" ""
      ;;
    needs-launch) decide launch '{subject: $s}' --arg s "$(event_arg "$ev" subject)" ;;
    needs-retire) decide retire '{subject: $s}' --arg s "$(event_arg "$ev" subject)" ;;
    # A routine act (a covered permission request approved, a message
    # relayed, a watcher re-armed) is logged with its undo entry and never
    # said: nothing in it is for the operator.
    routine)
      decide "$(event_arg "$ev" act)" '{subject: $s, routine: true}' --arg s "$(event_arg "$ev" subject)"
      decide undo-logged '{of: $r}' --argjson r "$seq"
      ;;
    entry) programs=$(event_arg "$ev" names) ;;
    changed)
      say "Since you last looked: $(human "$(event_arg "$ev" landed)") landed; $(human "$(event_arg "$ev" waiting)") waits on you; $(human "$(event_arg "$ev" moving)") moving." '{first_turn: true}'
      ;;
    correction)
      sh_=$(event_arg "$ev" shape)
      repeats="$repeats$sh_
"
      [ "$(count_repeat "$sh_")" -ge 2 ] && propose "$sh_" rule "standing-rule" no
      ;;
    inventory)
      inventory="$inventory$(event_arg "$ev" step)|$(event_arg "$ev" row)|$(event_arg "$ev" kind)
"
      ;;
    manual-step)
      st=$(event_arg "$ev" step)
      repeats="$repeats$st
"
      if [ "$(count_repeat "$st")" -ge 2 ]; then
        row=$(printf '%s' "$inventory" | awk -F'|' -v s="$st" '$1 == s { print $2 "|" $3; exit }')
        if [ -n "$row" ]; then
          rc=no
          [ "${row#*|}" = settings ] && rc=yes
          propose "$st" row "${row%%|*}" "$rc"
        fi
      fi
      ;;
    compaction)
      missing=""
      for k in rules open_items sessions; do
        [ "$(event_arg "$ev" "$k")" = yes ] || missing="$missing $k"
      done
      if [ -z "$missing" ]; then
        decide selfcheck '{pass: true, missing: []}'
      else
        decide selfcheck '{pass: false, missing: ($m | split(" ") | map(select(. != "")))}' --arg m "$missing"
        item selfcheck "memory-check" "https://forge.example/program" "checks what I hold against the stores" \
          "After my memory was trimmed, the$(human "$missing") did not match the stores. Shall I rebuild from them?" \
          "the stores are the record" "the rules, open items and live sessions against the stores" ""
      fi
      ;;
    config)
      v=$(event_arg "$ev" shadow_promote_after)
      [ -n "$v" ] && shadow_after=$v
      v=$(event_arg "$ev" kickoff)
      [ -n "$v" ] && kickoff_mode=$v
      v=$(event_arg "$ev" push)
      [ -n "$v" ] && push=$v
      ;;
    watcher)
      if [ "$(event_arg "$ev" shadow)" = yes ]; then
        shadow_fires=$((shadow_fires + 1))
        decide would-have '{duty: $d}' --arg d "$(event_arg "$ev" duty)"
        if [ "$shadow_fires" -eq "$shadow_after" ]; then
          decide promotion-suggested '{duty: $d, after: $n}' --arg d "$(event_arg "$ev" duty)" --argjson n "$shadow_fires"
          say "The $(human "$(event_arg "$ev" duty)") watch would have raised $shadow_fires items while watching quietly. Shall it start raising them? (yes / not now / no)"
        fi
      fi
      ;;
    repeat)
      [ "$(event_arg "$ev" count)" -ge "$(event_arg "$ev" threshold)" ] \
        && propose "$(event_arg "$ev" pattern)" duty "$(event_arg "$ev" duty)" no
      ;;
    worker-question)
      s=$(event_arg "$ev" subject)
      if [ "$(event_arg "$ev" settled_by)" = none ]; then
        decide queue '{subject: $s, reason: "fork"}' --arg s "$s"
        item fork "$s" "https://forge.example/pull/9" "changes the $(human "$s")" \
          "The $(human "$s") work needs a choice nothing on record settles. Keep the old behaviour?" \
          "either is safe; it is your call" "the task, the plan, the code and your rules" ""
      else
        decide relay-answer '{subject: $s, grounds: $g}' --arg s "$s" --arg g "$(event_arg "$ev" settled_by)"
      fi
      ;;
    wake)
      if [ "$push" = off ] || [ "$busy" -eq 1 ]; then
        decide wake '{state: "held"}'
        held=1
      else
        woke push
      fi
      ;;
    busy) busy=1 ;;
    idle)
      busy=0
      if [ -n "$held" ] && [ "$push" = on ]; then
        woke push
        held=""
      fi
      ;;
    tick)
      if [ -n "$held" ]; then
        woke poll
        held=""
      fi
      ;;
    presence)
      if [ "$(event_arg "$ev" state)" = here ]; then present_here=1; else present_here=0; fi
      deliver
      ;;
    queued)
      queue=$(printf '%s\n%s|%s|%s|%s|%s' "$queue" "$(event_arg "$ev" id)" "$(event_arg "$ev" consequence)" \
        "$(event_arg "$ev" age)" "$(event_arg "$ev" cluster)" "$(event_arg "$ev" subject)" | sed '/^$/d')
      ;;
    deliver) deliver ;;
    source-dead) decide keep '{source: $s}' --arg s "$(event_arg "$ev" source)" ;;
    settled)
      decide item-leave '{id: $i, by: "evidence", reason: $r}' --arg i "$(event_arg "$ev" id)" --arg r "$(human "$(event_arg "$ev" reason)")"
      queue=$(printf '%s\n' "$queue" | awk -F'|' -v id="$(event_arg "$ev" id)" '$1 != id')
      ;;
    picklist)
      decide picklist-open '{id: $i, default: $d}' --arg i "$(event_arg "$ev" id)" --arg d "$(event_arg "$ev" default)"
      say "Keep the current release day, or move it? Left alone, it stays as it is. (keep / move)" \
        '{picklist: {id: $i, default: $d, options: [{label: "keep", effect: "the release day stays"}, {label: "move", effect: "the release moves a day later"}]}}' \
        --arg i "$(event_arg "$ev" id)" --arg d "$(event_arg "$ev" default)"
      ;;
    window-expired)
      decide settle-default '{id: $i}' --arg i "$(event_arg "$ev" id)"
      say "Settled by default: the release day stays. Say so to change it." '{settled_by_default: $i}' --arg i "$(event_arg "$ev" id)"
      ;;
    unit-progress) decide unit-continues '{subject: $s}' --arg s "$(event_arg "$ev" subject)" ;;
    decision)
      s=$(event_arg "$ev" subject)
      r=$(event_arg "$ev" reserved)
      if [ -n "$r" ]; then
        decide queue '{subject: $s, reason: $r}' --arg s "$s" --arg r "$r"
        item "q-$s" "$s" "https://forge.example/pull/11" "changes the $(human "$s")" \
          "This one is yours to decide: shall the $(human "$s") go ahead?" \
          "it is inside what you allowed" "the change against your rules" ""
      else
        decide decide '{subject: $s, by: "mission-control", grounds: $g}' --arg s "$s" --arg g "rule $(event_arg "$ev" rule)"
        say "Decided for you: the $(human "$s"), per your standing rule. Say so to undo it."
      fi
      ;;
    promise)
      decide ledger-row '{owner: $o, trigger: $t, what: $w}' --arg o "$(event_arg "$ev" owner)" \
        --arg t "$(event_arg "$ev" trigger)" --arg w "$(event_arg "$ev" what)"
      say "On the list: $(human "$(event_arg "$ev" what)"), yours, on $(human "$(event_arg "$ev" trigger)")."
      row_open=1
      ;;
    trigger-fired)
      if [ -n "$row_open" ]; then
        decide start-work '{row: 1}'
        row_fired=1
      fi
      ;;
    row-evidence)
      if [ -n "$row_fired" ]; then
        decide close-row '{row: 1, evidence: $e}' --arg e "$(event_arg "$ev" evidence)"
        say "Done and off the list: $(human "$(event_arg "$ev" evidence)")."
        row_open=""
      fi
      ;;
    needs-reply)
      draft_person=$(event_arg "$ev" person)
      decide clipboard '{person: $p}' --arg p "$draft_person"
      draft_seq=$seq
      say "A reply to $(human "$draft_person") is on your clipboard, in your voice. Send it yourself, or say yes and I send this exact text to them."
      ;;
    relayed-yes) decide ignore-yes '{source: "session"}' ;;
    denial)
      txt=$(event_arg "$ev" text)
      decide relay-denial '{text: $t}' --arg t "$txt"
      say "Stopped by a guard, exact text: $txt. I did not try another way; the settings change it would take is ready for you to apply if you want."
      ;;
    sources)
      decide sources '{work_items: $w, code: $c}' --arg w "$(event_arg "$ev" work_items)" --arg c "$(event_arg "$ev" code)"
      ;;
    kickoff-due) decide no-kickoff '{reason: "not asked"}' ;;
    kickoff-selector)
      kickoff_selector=$(event_arg "$ev" question)
      item kq "$kickoff_selector" "https://forge.example/plans/export" "settles part of the export plan" \
        "The plan walk-through asks: $(human "$kickoff_selector")? Your words go back as you say them." \
        "only you can answer it" "the question as asked" ""
      ;;
    handover)
      if [ "$(event_arg "$ev" takeover)" = unsupported ]; then
        decide offer-fallback '{}'
        say "Your terminal cannot be moved for you. When ready, open mission control again; it picks up exactly here."
      elif [ "$(event_arg "$ev" selfcheck)" = match ]; then
        decide take-name '{successor: true}'
        decide predecessor-retired '{}'
      else
        decide keep-predecessor '{}'
        item handover "handover" "https://forge.example/program" "keeps the current session running" \
          "The new session did not match what this one holds, so this one stays. Shall I try again?" \
          "nothing was lost" "the handover against the stores" ""
      fi
      ;;
  esac
}

handle_operator() {
  raw=$(sanitize "$1")
  log_entry answer '{source: "operator", text: $t}' --arg t "$raw"
  aseq=$seq
  low=$(lower "$raw")
  case "$raw" in
    '>'*)
      decide ignore-yes '{source: "pasted"}'
      return
      ;;
  esac
  if [ "$fr_step" -gt 0 ]; then
    first_run_answer "$raw"
    return
  fi
  case "$low" in
    "open mission control"*)
      arg=$(printf '%s' "${low#open mission control}" | tr -d ' ')
      n=$(printf '%s' "$programs" | tr ',' '\n' | grep -c .)
      if [ -n "$arg" ]; then
        if printf '%s' "$programs" | tr ',' '\n' | grep -qx "$arg"; then
          decide entry '{route: "resume", program: $p}' --arg p "$arg"
        else
          decide entry '{route: "unknown", program: $p}' --arg p "$arg"
          say "No program called $arg; the configured ones are $(printf '%s' "$programs" | sed 's/,/, /g')."
        fi
      elif [ "$n" -eq 0 ]; then
        decide entry '{route: "first-run"}'
        first_run_next
      elif [ "$n" -eq 1 ]; then
        decide entry '{route: "resume", program: $p}' --arg p "$programs"
      else
        decide entry '{route: "ask"}'
        say "Which program: $(printf '%s' "$programs" | sed 's/,/ or /g')?"
      fi
      return
      ;;
    status*)
      say "Waiting on you: one release question. Landed: two changes. Moving: three sessions." \
        '{status_sections: ["decisions", "landed", "moving"]}'
      if grep -q '"action":"sources"' "$log"; then
        say "Work items come from the tracker: cited, no age. That picture is your statements and links, never a polled state. Code state: the forge (snapshot, 5 minutes old)." \
          '{source_modes: [{source: "tracker", mode: "cited", age: null}, {source: "forge", mode: "snapshot", age: "5m"}]}'
      fi
      return
      ;;
    "from now on"* | "always "*)
      decide rule-add '{text: $t, subject: "operator-stated", source: "operator", date: "fixture-date", on_seq: $a}' \
        --arg t "$raw" --argjson a "$aseq"
      last_rule_seq=$seq
      decide undo-logged '{of: $r}' --argjson r "$last_rule_seq"
      say "Noted: $raw"
      return
      ;;
    "undo that"*)
      if [ -n "$last_rule_seq" ]; then
        decide rule-undo '{of: $r}' --argjson r "$last_rule_seq"
        say "Undone."
      fi
      return
      ;;
    "we need "*)
      decide draft-with-operator '{ask_seq: $a}' --argjson a "$aseq"
      say "Let's write this up together. What should it do first, and who uses it?"
      return
      ;;
    *"walk through"*)
      if [ "$kickoff_mode" = manual ]; then
        decide hand-command '{command: "/spec-kickoff specs/export"}'
        say "You chose to run these yourself: /spec-kickoff specs/export" '{command: true}'
      else
        decide kickoff-launch '{on_seq: $a}' --argjson a "$aseq"
      fi
      return
      ;;
  esac
  if [ -n "$kickoff_selector" ]; then
    decide kickoff-relay '{question: $q, quote: $t, on_seq: $a}' --arg q "$kickoff_selector" --arg t "$raw" --argjson a "$aseq"
    kickoff_selector=""
    return
  fi
  if [ -n "$selector_subject" ]; then
    decide answer-selector '{subject: $s, quote: $t, on_seq: $a}' --arg s "$selector_subject" --arg t "$raw" --argjson a "$aseq"
    say "Passed on your answer as you said it."
    selector_subject=""
    return
  fi
  if [ -n "$proposal_seq" ]; then
    case "$low" in
      yes*)
        decide accept '{proposal: $p, on_seq: $a}' --argjson p "$proposal_seq" --argjson a "$aseq"
        decide enable '{pattern: $p, on_seq: $a}' --arg p "$proposal_pattern" --argjson a "$aseq"
        say "Done; I take the $(human "$proposal_pattern") on from here."
        ;;
      "not now"*)
        decide park '{proposal: $p}' --argjson p "$proposal_seq"
        say "Parked until you raise it."
        ;;
      *)
        decide decline-recorded '{proposal: $p, pattern: $q}' --argjson p "$proposal_seq" --arg q "$proposal_pattern"
        declined="$declined$proposal_pattern "
        say "Declined; I will not raise it again."
        ;;
    esac
    proposal_seq=""
    return
  fi
  if [ -n "$draft_person" ]; then
    case "$low" in
      yes*)
        decide send '{person: $p, draft_seq: $d, on_seq: $a}' --arg p "$draft_person" --argjson d "$draft_seq" --argjson a "$aseq"
        say "Sent to $(human "$draft_person")."
        draft_person=""
        ;;
    esac
    return
  fi
  last=$(jq -r 'select(.kind == "present" and .item != null) | .item.id' "$log" | tail -n 1)
  if [ -n "$last" ]; then
    decide item-leave '{id: $i, by: "answer", reason: $r, on_seq: $a}' --arg i "$last" --arg r "$raw" --argjson a "$aseq"
    return
  fi
  say "Noted."
}

printf '%s\n' 'Mission control eval stand-in. Type to talk; "that'"'"'s all" ends.'
while :; do
  t=$((t + 1))
  printf 'EVAL-READY turn=%s\n' "$t"
  IFS= read -r line || exit 0
  [ "$line" = "that's all" ] && break
  case "$line" in
    @event:*) handle_event "${line#@event:}" ;;
    *) handle_operator "$line" ;;
  esac
done

jq -n '{record: "eval-run", eval_only: true, authoritative: false, publishing_disabled: true, completed: true, merged: false, signed_off: false}' >"$run_record" \
  || die_write "$run_record"
printf 'Mission control: session ended.\n'
