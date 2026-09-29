#!/bin/sh
# tower/skill.sh — the tower routing eval fixture skill. A DETERMINISTIC stand-in
# for the model-backed /tower router: driving the real skill needs a live Claude
# TTY session (nondeterministic, priced), so the assertable invariants of a
# routing run are pinned against this shell model of the routing rule
# (doctrine/flight-rules.md, skills/tower/SKILL.md "The router"). Whether the
# live router's judgment matches the rule on asks the model has never seen is
# what the live run and the operator judge; see the fixtures README.
#
# The signals are matched as whole words over the lowercased ask, which is
# enough for the personas and no more: a keyword model cannot read meaning, so
# an ask worded around its keywords routes wrong here where a live tower would
# not.
#
# It writes the two artifacts of the tower's eval-only seam, which grade.jq reads
# (never a scraped pane):
#
#   decision-log.jsonl  one record per operator line, evidence event, thing
#                       presented, and decision (route, dispatch, refusal, offer,
#                       hold, reconstruction)
#   sign-off.json       the eval run record: eval-only, non-authoritative, and a
#                       sign-off of nothing (the harness's completion marker keeps
#                       the file name)
#
# and one file of its own, evidence.jsonl, standing in for the git and forge
# evidence a restarted session reads (flights dispatched, landings, drafted and
# signed specs, relayed orchestrations). It is not part of the seam.
#
# Input lines are the operator's own words, except lines starting `@event:`,
# which stand for durable evidence the tower reads (a flight landing, a draft
# finishing, a sign-off completing, a spec PR merging, a session restart). An
# event is never the operator's words, so it can never be a go, a yes, or an
# override. The line `that's all` ends the session and writes the run record.
#
# Replay model (as greeter/kickoff): a read at EOF exits 0, so a partial replay
# under the hermetic stub stops before the run record is written; every artifact
# is truncated at start.
#
# Usage: skill.sh <artifacts-dir>
# shellcheck disable=SC2016 # the $-sigils in quoted jq filters are jq bindings, not shell expansions
set -u
LC_ALL=C
export LC_ALL

art="${1:-}"
if [ -z "$art" ]; then
  echo "tower/skill.sh: an artifacts directory argument is required" >&2
  exit 2
fi
mkdir -p -- "$art" 2>/dev/null || {
  echo "tower/skill.sh: cannot create artifacts dir '$art'" >&2
  exit 2
}

die_write() {
  echo "tower/skill.sh: failed to write $1" >&2
  exit 2
}

log="$art/decision-log.jsonl"
run_record="$art/sign-off.json"
evidence="$art/evidence.jsonl"
{ : >"$log"; } 2>/dev/null || die_write "$log"
{ : >"$evidence"; } 2>/dev/null || die_write "$evidence"
rm -f "$run_record" "$run_record.tmp" 2>/dev/null || die_write "$run_record"

# The wording of the no-landing state is pinned by grade.jq and the test.
UNCHECKED="in the air, paused, or dead — not checked"

seq=0
t=0
phase=route

# Conversation-only state, lost on a session restart. A case is answerable in
# the next operator turn only; handle_operator takes and clears it on entry.
case_seq=""
case_ask_seq=""
case_ask=""
case_trigger=""
case_grounds=""
# Evidence-derived state, rebuilt from evidence.jsonl on a restart.
last_pr=""
signed_spec=""
offered_spec=""

# log_entry <kind> <jq-filter> [jq-args...] — append one record, built by a
# single jq so every value is data; sets $seq to its number.
log_entry() {
  _le_kind="$1"
  _le_filter="$2"
  shift 2
  seq=$((seq + 1))
  jq -cn --argjson seq "$seq" --arg phase "$phase" --arg kind "$_le_kind" "$@" \
    "{v: 2, seq: \$seq, phase: \$phase, kind: \$kind} + ($_le_filter)" >>"$log" \
    || die_write "a decision-log record ($_le_kind)"
}

# say <text> [<jq-filter> [jq-args...]] — print a line to the operator and
# mirror it as a present record, extra fields from the optional filter.
say() {
  _sy_text="$1"
  _sy_filter='{}'
  if [ $# -ge 2 ]; then
    _sy_filter="$2"
    shift 2
  else
    shift 1
  fi
  printf 'Tower: %s\n' "$_sy_text"
  log_entry present "{text: \$text} + ($_sy_filter)" --arg text "$_sy_text" "$@"
}

evidence_add() {
  printf '%s\n' "$1" >>"$evidence" 2>/dev/null || die_write "an evidence entry"
}

# sanitize <raw> — the echo-safety floor: C0 and C1 control bytes stripped
# (the set scripts/echo-safety.sh's sanitize_printable strips).
sanitize() { printf '%s' "$1" | tr -d '\000-\037\177\200-\237'; }
# words <text> — lowercased, non-alphanumerics folded to single spaces, padded,
# so a signal matches as whole words: `*" merge it "*`.
words() { printf ' %s ' "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' ' ')" | tr -s ' '; }
trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

valid_spec() {
  case "$1" in
    '' | *[!a-z0-9-]* | -*) return 1 ;;
  esac
  [ "$1" != flight ] && [ "${#1}" -le 64 ]
}

# slug_of <words> <fallback> — a spec-grammar kebab slug from the first four
# words, capped; the fallback when nothing usable remains.
slug_of() {
  _sl="$(printf '%s' "$1" | awk '{ s = ""; for (i = 1; i <= NF && i <= 4; i++) s = s (i > 1 ? "-" : "") $i; print substr(s, 1, 48) }' | sed 's/-*$//')"
  valid_spec "$_sl" || _sl="$2"
  printf '%s' "$_sl"
}

# event_arg <event> <key> — the value of `<key>=<v>` in an event line; the key
# is matched as data, never spliced into a program.
event_arg() {
  printf '%s\n' "$1" | tr ' ' '\n' | awk -v k="$2" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }'
}

# ---- signal classifiers (over `words` output) -------------------------------
reserved_control() {
  case "$1" in
    *" merge it "* | *" merge the "* | *" merge this "* | *" merge that "* | *" merge pr "*) printf 'merge' ;;
    *" mark it ready "* | *" mark ready "* | *" ready for review "*) printf 'ready' ;;
    *" sign it off "* | *" sign off on "*) printf 'sign-off' ;;
    *" force push "* | *" rebase "* | *" squash "* | *" amend "*) printf 'history-rewrite' ;;
  esac
}
mode_request() {
  case "$1" in
    *" from now on "* | *" every ask "* | *" always file "* | *" always fly "*) return 0 ;;
  esac
  return 1
}
has_mutation_verb() {
  case "$1" in
    *" fix "* | *" change "* | *" add "* | *" rename "* | *" delete "* | *" remove "* | *" drop "* | \
      *" rotate "* | *" update "* | *" tighten "* | *" reword "* | *" edit "* | *" move "* | *" create "* | \
      *" make "* | *" set "* | *" bump "* | *" replace "* | *" write "*) return 0 ;;
  esac
  return 1
}
is_read_only() {
  case "$1" in
    " review "* | " audit "* | " find "* | " list "* | " summarize "* | " explain "* | " survey "*)
      has_mutation_verb "$1" && return 1
      return 0
      ;;
  esac
  return 1
}
override_of() {
  case "$1" in
    *" just do it "* | *" fly it visual "*) printf 'visual' ;;
    *" write this one up "* | *" write it up "* | *" file a plan "*) printf 'instrument' ;;
  esac
}
# zone_of — the hard-disqualifier zone the change lands in, or nothing.
zone_of() {
  case "$1" in
    *" auth "* | *" authentication "* | *" authorization "* | *" login "*) printf 'authentication code' ;;
    *" credential "* | *" credentials "* | *" secret "* | *" secrets "*) printf 'a secrets file' ;;
    *" permission "* | *" permissions "*) printf 'the permission checks' ;;
    *" migration "* | *" migrations "*) printf 'a schema migration' ;;
    *" lockfile "*) printf 'a lockfile' ;;
    *" ci config "* | *" ci workflow "*) printf 'the CI configuration' ;;
  esac
}
irreversible_of() {
  case "$1" in
    *" delete "*" data "* | *" remove "*" data "*) printf 'deleting that data' ;;
    *" drop table "* | *" drop the table "*) printf 'dropping it' ;;
    *" public api "* | *" published "*) printf 'a published interface' ;;
    *" send "*" email "* | *" notify customers "* | *" publish "*) printf 'an external side effect' ;;
  esac
}
is_ambiguous() {
  case "$1" in
    *" better somehow "* | *" not sure "* | *" improve things "* | *" whatever you think "*) return 0 ;;
  esac
  return 1
}
# size_of <lowercased-ask> — the size phrase, stated as advisory, or nothing.
size_of() {
  case "$1" in
    *"across all"* | *"every file"* | *hundreds*)
      printf '%s' "$1" | sed -n \
        -e 's/.*\(across all[^,]*\).*/\1/p' \
        -e 's/.*\(every file\).*/\1/p' \
        -e 's/.*\(hundreds[^,]*\).*/\1/p' | head -n 1
      ;;
  esac
}
is_yes() {
  case "$1" in
    " yes " | " yes please " | " yes file it " | " file it " | " go ahead and file it ") return 0 ;;
  esac
  return 1
}
is_no() {
  case "$1" in
    " no " | " no thanks " | " not now " | " drop it " | " park it ") return 0 ;;
  esac
  return 1
}
is_ack() {
  case "$1" in
    " ok " | " okay " | " sure " | " great " | " sounds good " | " thanks ") return 0 ;;
  esac
  return 1
}

# ---- evidence ------------------------------------------------------------------

# evidence_state — one read of evidence.jsonl, summarized as JSON on stdout.
evidence_state() {
  jq -cs '
    [.[] | select(.type == "flight")] as $f
    | [.[] | select(.type == "landing")] as $l
    | [.[] | select(.type == "signed") | .spec] as $signed
    | [$f[] | . as $x | ([$l[] | select(.flight_id == $x.flight_id)] | last) as $land
        | {flight_id: $x.flight_id, state: (if $land then "landed" else "no-landing-yet" end),
           pr: ($land.pr // null)}] as $flights
    | {flights: $flights,
       unlanded: [$flights[] | select(.state == "no-landing-yet") | .flight_id],
       landed: [$flights[] | select(.state == "landed") | .pr],
       last_pr: ([$l[] | .pr] | last // ""),
       signed: ($signed | last // ""),
       drafted: ([.[] | select(.type == "drafted") | .spec | select(. as $x | $signed | index($x) | not)] | last // "")}' \
    "$evidence" 2>/dev/null
}

# ---- actions -------------------------------------------------------------------

# decide_route <ask-seq> <route> <trigger> <grounds> <override> <crossed>
# <reservation> [<size>] — state the route and its grounds, and record it.
decide_route() {
  case "$2" in
    visual) _dr_label="Visual flight" ;;
    instrument) _dr_label="Instrument flight" ;;
    answer) _dr_label="Answered here" ;;
    offload) _dr_label="Read-only look" ;;
  esac
  _dr_statement="$_dr_label: $4"
  [ -n "$7" ] && _dr_statement="$_dr_statement $7"
  say "$_dr_statement"
  log_entry decision '{action: "route", ask_seq: $ask, route: $route, trigger: $trigger, grounds: $grounds,
      override: (if $override == "" then null else $override end),
      crossed: (if $crossed == "" then null else $crossed end),
      reservation: $reservation,
      size_advisory: (if $size == "" then null else $size end),
      statement: $statement}' \
    --argjson ask "$1" --arg route "$2" --arg trigger "$3" --arg grounds "$4" --arg override "$5" \
    --arg crossed "$6" --arg reservation "$7" --arg size "${8:-}" --arg statement "$_dr_statement"
}

# dispatch_flight <ask-seq> <ask-words>
dispatch_flight() {
  _df_fid="fl-$1-$(slug_of "$2" ask)"
  say "Sending it to an isolated worker on its own branch; the record goes in the draft PR body, and I will hand the PR back when it lands."
  log_entry decision '{action: "dispatch", target: "flight", ask_seq: $ask, on_seq: $ask, flight_id: $fid,
      isolated_worktree: true, home: "draft PR body", draft: true}' --argjson ask "$1" --arg fid "$_df_fid"
  evidence_add "$(jq -cn --arg fid "$_df_fid" '{type: "flight", flight_id: $fid}')"
}

# present_case <ask-seq> <raw-ask> <trigger> <why> <automatic-grounds>
present_case() {
  _pc_alt="say \"just do it\" to fly it visual"
  [ -n "$5" ] && _pc_alt="$_pc_alt (my reservation: $5)"
  say "The case for filing a plan. The ask: \"$2\". Why: $4. Filing buys a requirement-level record with a test path for every requirement; it costs a drafting pass and a walkthrough. Alternatives, at equal weight: $_pc_alt, or drop or park the ask. File it?" \
    '{case: true, ask_seq: $ask, quote: $quote}' --argjson ask "$1" --arg quote "$2"
  case_seq="$seq"
  case_ask_seq="$1"
  case_ask="$2"
  case_trigger="$3"
  case_grounds="$5"
}

# refuse <ask-seq> <control> <statement> <handed-back>
refuse() {
  say "$3"
  log_entry decision '{action: "refuse", control: $control, statement: $statement, ask_seq: $ask,
      handed_back: (if $pr == "" then null else $pr end)}' \
    --argjson ask "$1" --arg control "$2" --arg statement "$3" --arg pr "$4"
}

# fly_overridden <ask-seq> <ask-words> <crossed-trigger> <crossed-grounds>
fly_overridden() {
  _fo_res=""
  [ -n "$3" ] && _fo_res="Reservation: $3 trigger, $4; complying as you asked."
  decide_route "$1" visual override "you asked to fly it visual" visual "$3" "$_fo_res"
  dispatch_flight "$1" "$2"
}

# route_mutation <ask-seq> <raw-ask> <ask-words>
route_mutation() {
  _rm_ov="$(override_of "$3")"
  _rm_zone="$(zone_of "$3")"
  _rm_irr="$(irreversible_of "$3")"
  _rm_trigger=""
  _rm_grounds=""
  if [ -n "$_rm_zone" ]; then
    _rm_trigger=zone
    _rm_grounds="the change lands in $_rm_zone, zone work, so it files automatically"
  elif [ -n "$_rm_irr" ]; then
    _rm_trigger=irreversible
    _rm_grounds="$_rm_irr is not one revert from undone, so it files automatically"
  fi

  if [ "$_rm_ov" = instrument ]; then
    decide_route "$1" instrument override "you asked for it to be written up" instrument "" ""
    present_case "$1" "$2" override "you asked for it" ""
  elif [ "$_rm_ov" = visual ]; then
    fly_overridden "$1" "$3" "$_rm_trigger" "$_rm_grounds"
  elif [ -n "$_rm_trigger" ]; then
    decide_route "$1" instrument "$_rm_trigger" "$_rm_grounds" "" "" ""
    present_case "$1" "$2" "$_rm_trigger" "$_rm_grounds" "$_rm_grounds"
  elif is_ambiguous "$3"; then
    decide_route "$1" instrument ambiguity "I cannot state a done-when you would agree with; that is my judgment, so it files" "" "" ""
    present_case "$1" "$2" ambiguity "I cannot state a done-when you would agree with" ""
  else
    _rm_size="$(size_of "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')")"
    _rm_g="a change one revert from undone, touching no guarded zone"
    [ -n "$_rm_size" ] && _rm_g="$_rm_g; size is advisory: $_rm_size does not file it"
    decide_route "$1" visual reversible "$_rm_g" "" "" "" "$_rm_size"
    dispatch_flight "$1" "$3"
  fi
}

# reconstruct — a fresh session rebuilds what is in flight from evidence alone.
reconstruct() {
  case_seq=""
  offered_spec=""
  last_pr=""
  signed_spec=""
  if ! _rc_state="$(evidence_state)" || [ -z "$_rc_state" ]; then
    say "Fresh session. The durable evidence could not be read, so what is in flight is unknown — not checked."
    log_entry decision '{action: "reconstruct", source: "evidence", error: "evidence unreadable", flights: null}'
    return 0
  fi
  last_pr="$(printf '%s' "$_rc_state" | jq -r '.last_pr')"
  signed_spec="$(printf '%s' "$_rc_state" | jq -r '.signed')"
  offered_spec="$(printf '%s' "$_rc_state" | jq -r '.drafted')"
  _rc_msg="$(printf '%s' "$_rc_state" | jq -r --arg u "$UNCHECKED" '
    "Fresh session, rebuilt from durable evidence."
    + (if (.landed | length) > 0 then " Landed: " + (.landed | map("draft PR #" + .) | join(", ")) + "." else "" end)
    + (if (.unlanded | length) > 0 then " \(.unlanded | length) flight(s) with no landing yet: " + $u + "." else "" end)')"
  [ -n "$offered_spec" ] && _rc_msg="$_rc_msg The draft at specs/$offered_spec waits on your kickoff: /spec-kickoff specs/$offered_spec."
  say "$_rc_msg Anything only the last conversation held, such as an unanswered case, is gone and gets re-asked."
  log_entry decision '{action: "reconstruct", source: "evidence", flights: $s.flights}' --argjson s "$_rc_state"
}

reject_event() { # reject_event <name> <reason>
  log_entry event '{source: "evidence", event: $e, rejected: $r}' --arg e "$1" --arg r "$2"
  say "I cannot act on that evidence: $2."
}

handle_event() { # handle_event <line>
  _he_ev="${1#@event:}"
  _he_name="${_he_ev%% *}"
  _he_spec="$(event_arg "$_he_ev" spec)"
  case "$_he_name" in
    draft-complete | signoff-complete | spec-pr-merged)
      valid_spec "$_he_spec" || {
        reject_event "$_he_name" "it names no valid spec"
        return 0
      }
      ;;
  esac
  case "$_he_name" in
    flight-landed)
      _he_pr="$(event_arg "$_he_ev" pr)"
      case "$_he_pr" in
        '' | *[!0-9]*)
          reject_event flight-landed "it names no PR number"
          return 0
          ;;
      esac
      _he_state="$(evidence_state)" || _he_state=""
      _he_fid="$(event_arg "$_he_ev" flight)"
      if [ -z "$_he_fid" ]; then
        _he_fid="$(printf '%s' "$_he_state" | jq -r 'if (.unlanded | length) == 1 then .unlanded[0] else "" end' 2>/dev/null)"
      fi
      if [ -z "$_he_fid" ] || ! printf '%s' "$_he_state" | jq -e --arg f "$_he_fid" '.unlanded | index($f)' >/dev/null 2>&1; then
        reject_event flight-landed "it names no flight still waiting on a landing"
        return 0
      fi
      log_entry event '{source: "evidence", event: "flight-landed", pr: $pr, flight_id: $fid, draft: true}' \
        --arg pr "$_he_pr" --arg fid "$_he_fid"
      evidence_add "$(jq -cn --arg pr "$_he_pr" --arg fid "$_he_fid" '{type: "landing", flight_id: $fid, pr: $pr}')"
      last_pr="$_he_pr"
      say "Landed: draft PR #$_he_pr. The ready flip and the merge stay yours."
      ;;
    session-restart)
      log_entry event '{source: "evidence", event: "session-restart"}'
      reconstruct
      ;;
    draft-complete)
      log_entry event '{source: "evidence", event: "draft-complete", spec: $s}' --arg s "$_he_spec"
      evidence_add "$(jq -cn --arg s "$_he_spec" '{type: "drafted", spec: $s}')"
      offered_spec="$_he_spec"
      say "The draft is at specs/$_he_spec. Walking it and signing it off is yours: run /spec-kickoff specs/$_he_spec when you are ready. I will not start it."
      log_entry decision '{action: "offer", target: "spec-kickoff", spec: $s, started: false}' --arg s "$_he_spec"
      ;;
    signoff-complete)
      log_entry event '{source: "evidence", event: "signoff-complete", spec: $s}' --arg s "$_he_spec"
      evidence_add "$(jq -cn --arg s "$_he_spec" '{type: "signed", spec: $s}')"
      signed_spec="$_he_spec"
      offered_spec=""
      say "$_he_spec is signed off. Nothing starts on its own: say go when you want it orchestrated."
      log_entry decision '{action: "hold", on: "signoff-complete", spec: $s, dispatched: false}' --arg s "$_he_spec"
      ;;
    spec-pr-merged)
      log_entry event '{source: "evidence", event: "spec-pr-merged", spec: $s}' --arg s "$_he_spec"
      say "The $_he_spec spec PR merged. Still nothing starts until you say go."
      log_entry decision '{action: "hold", on: "spec-pr-merged", spec: $s, dispatched: false}' --arg s "$_he_spec"
      ;;
    *)
      reject_event "$_he_name" "it is not evidence I recognize"
      ;;
  esac
}

handle_operator() { # handle_operator <raw>
  _ho_raw="$(trim "$(sanitize "$1")")"
  _ho_w="$(words "$_ho_raw")"
  log_entry answer '{source: "operator", text: $text}' --arg text "$_ho_raw"
  _ho_ask="$seq"
  # A pending case answers in this turn or lapses.
  _ho_case="$case_seq"
  _ho_case_ask_seq="$case_ask_seq"
  _ho_case_ask="$case_ask"
  _ho_case_trigger="$case_trigger"
  _ho_case_grounds="$case_grounds"
  case_seq=""

  _ho_ctl="$(reserved_control "$_ho_w")"
  if [ -n "$_ho_ctl" ]; then
    case "$_ho_ctl" in
      merge)
        if [ -n "$last_pr" ]; then
          refuse "$_ho_ask" merge "Merge is yours, permanently, on both flight rules; I do not merge. Here is the PR back: draft PR #$last_pr." "$last_pr"
        else
          refuse "$_ho_ask" merge "Merge is yours, permanently, on both flight rules; I do not merge, and no landed PR in this conversation needs handing back." ""
        fi
        ;;
      ready) refuse "$_ho_ask" ready "The draft-to-ready flip is yours; I never perform it.${last_pr:+ Draft PR #$last_pr is where you flip it.}" "$last_pr" ;;
      sign-off) refuse "$_ho_ask" sign-off "Sign-off is yours, at the kickoff walkthrough; flights have no sign-off of their own." "" ;;
      history-rewrite) refuse "$_ho_ask" history-rewrite "New commits only, on both flight rules: rewriting pushed history stays yours and I never run it." "" ;;
    esac
    return 0
  fi

  if mode_request "$_ho_w"; then
    refuse "$_ho_ask" mode "Flight rules are not a mode: I choose them per request, and nothing carries to the next ask. Say \"write this one up\" on any ask you want filed." ""
    return 0
  fi

  if [ -n "$_ho_case" ]; then
    if is_yes "$_ho_w"; then
      say "Drafting it in a session you can attach to; it checks for an overlapping spec first."
      log_entry decision '{action: "dispatch", target: "spec-draft", on_seq: $on, case_seq: $c, feature: $f}' \
        --argjson on "$_ho_ask" --argjson c "$_ho_case" --arg f "$(slug_of "$(words "$_ho_case_ask")" "ask-$_ho_case_ask_seq")"
      return 0
    fi
    if is_no "$_ho_w"; then
      say "Dropped; nothing was filed."
      return 0
    fi
    if [ "$(override_of "$_ho_w")" = visual ] && ! has_mutation_verb "$_ho_w"; then
      _ho_ct=""
      case "$_ho_case_trigger" in zone | irreversible) _ho_ct="$_ho_case_trigger" ;; esac
      fly_overridden "$_ho_case_ask_seq" "$(words "$_ho_case_ask")" "$_ho_ct" "$_ho_case_grounds"
      return 0
    fi
  fi

  case "$_ho_w" in
    " go " | " go ahead ")
      if [ -z "$signed_spec" ]; then
        say "Go on what? No signed spec in this conversation to orchestrate."
        return 0
      fi
      jq -e -s --arg s "$signed_spec" 'any(.[]; .type == "orchestrated" and .spec == $s)' "$evidence" >/dev/null 2>&1
      _ho_rc=$?
      if [ "$_ho_rc" -eq 0 ]; then
        say "Orchestration of $signed_spec was already relayed; ask me for its status."
      elif [ "$_ho_rc" -ne 1 ]; then
        say "I cannot read whether $signed_spec was already relayed, so I am not relaying it again — not checked."
      else
        _ho_cmd="/orchestrate specs/$signed_spec --watch"
        say "Relaying your go: $_ho_cmd, on a session you can attach to."
        log_entry decision '{action: "dispatch", target: "orchestrate", on_seq: $on, spec: $s, command: $cmd}' \
          --argjson on "$_ho_ask" --arg cmd "$_ho_cmd" --arg s "$signed_spec"
        evidence_add "$(jq -cn --arg s "$signed_spec" '{type: "orchestrated", spec: $s}')"
      fi
      return 0
      ;;
  esac

  if is_ack "$_ho_w" || is_yes "$_ho_w" || is_no "$_ho_w"; then
    if [ -n "$offered_spec" ]; then
      say "It is yours to start: /spec-kickoff specs/$offered_spec. Nothing starts from here."
    else
      say "Nothing is waiting on that answer. What would you like done?"
    fi
    return 0
  fi

  case "$_ho_raw" in
    *'?')
      if ! has_mutation_verb "$_ho_w"; then
        decide_route "$_ho_ask" answer question "a question, answered in this turn from what I can see" "" "" ""
        if _ho_state="$(evidence_state)" && [ -n "$_ho_state" ]; then
          say "$(printf '%s' "$_ho_state" | jq -r --arg u "$UNCHECKED" '
            (if (.landed | length) > 0 then "Landed: " + (.landed | map("draft PR #" + .) | join(", ")) + ". " else "" end)
            + (if (.unlanded | length) > 0 then "\(.unlanded | length) flight(s) with no landing yet: " + $u + "."
               else "No flight is waiting on a landing." end)')"
        else
          say "The durable evidence could not be read, so what is in flight is unknown — not checked."
        fi
        return 0
      fi
      ;;
  esac
  if is_read_only "$_ho_w"; then
    decide_route "$_ho_ask" offload read-only "it changes nothing, so the look runs read-only and comes back here, with no flight" "" "" ""
    log_entry decision '{action: "dispatch", target: "read-only-offload", ask_seq: $ask, on_seq: $ask, flight_identity: false}' --argjson ask "$_ho_ask"
    return 0
  fi
  # An override alone names no change; what is left once it is removed must.
  _ho_subject="$(printf '%s' "$_ho_w" | sed 's/ write this one up / /; s/ write it up / /; s/ just do it / /; s/ fly it visual / /; s/ file a plan / /')"
  if has_mutation_verb "$_ho_subject" || [ -n "$(zone_of "$_ho_subject")" ] \
    || [ -n "$(irreversible_of "$_ho_subject")" ] || is_ambiguous "$_ho_subject"; then
    route_mutation "$_ho_ask" "$_ho_raw" "$_ho_w"
  else
    say "I cannot tell what you want changed or answered. What would you like done?"
  fi
}

finish() {
  phase=close
  say "Standing by."
  if ! jq -s --arg pub "${PLANWRIGHT_PUBLISH_DISABLED:-}" '
    [.[] | select(.kind == "decision")] as $d
    | {record: "eval-run", subject: "tower-routing", eval_only: true, authoritative: false,
       publishing_disabled: ($pub == "1"),
       routes: [$d[] | select(.action == "route") | {seq, route, trigger}],
       dispatches: [$d[] | select(.action == "dispatch") | .target],
       refusals: [$d[] | select(.action == "refuse") | .control],
       kickoff_started: ([$d[] | select(.action == "kickoff-start")] | length > 0),
       merged: ([$d[] | select(.action == "merge")] | length > 0),
       ready_flipped: ([$d[] | select(.action == "ready-flip")] | length > 0),
       mode_state: null, completed: true}' "$log" >"$run_record.tmp"; then
    die_write "the run record"
  fi
  mv "$run_record.tmp" "$run_record" || die_write "the run record"
  exit 0
}

# ---- the session ----------------------------------------------------------------
phase=bring-up
say "Nothing in flight that this checkout can see. What would you like done?"
phase=route
while :; do
  t=$((t + 1))
  printf 'EVAL-READY turn=%s\n' "$t"
  line=""
  IFS= read -r line || [ -n "$line" ] || exit 0
  line="$(trim "$line")"
  case "$line" in
    @event:*) handle_event "$(sanitize "$line")" ;;
    *)
      case "$(words "$(sanitize "$line")")" in
        " that s all " | " that is all ") finish ;;
        *) handle_operator "$line" ;;
      esac
      ;;
  esac
done
