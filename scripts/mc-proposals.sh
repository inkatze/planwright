#!/usr/bin/env bash
# mc-proposals.sh — mission control's mechanization proposals: the repeat
# detector over the decisions log's noted repeats, and the proposal record
# mapping a repeat onto the smallest covering row of the knowledge base's
# mechanism inventory, with its accepted, declined and parked outcomes.
#
# `mc-proposals.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-proposals
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

tab=$(printf '\t')
us=$(printf '\037')
STAGED=''
on_exit() {
  mc_kb_unlock
  [ -z "$STAGED" ] || rm -f "$STAGED"
}
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

help_text() {
  cat <<'HELP'
mc-proposals.sh — a program's mechanization proposals, in its knowledge
base's proposals.tsv.

A repeat is a run of noted entries of one shape (scripts/mc-decide.sh note)
inside mission_control_repeat_window reaching
mission_control_repeat_threshold: corrections on one subject, a manual step
on one subject after one event, or one answer to one question; or of one
ask, decisions on one subject that reached the operator by one reason. Subjects
compare by the rule store's subject key. A pattern with a proposal in any
state is never raised again; a declined one stays declined.

A proposal maps the repeat onto one row of the mechanism inventory
(kb/mechanisms.tsv, scripts/mc-kb.sh inventory-refresh), never onto a
mechanism absent from it: of the candidates the caller names, the row of
the smallest kind wins, in the order rule, knob, catalog-step, permission,
hook, routine, any other kind, duty. A bare <kind> candidate names the
kind's only row, and is refused when the kind has several. A correction
with no candidate names the rule row. A row of kind hook or permission, or
whose location is a settings file, is settings-kind: its change is handed
over to the operator ready to apply, and nothing writes it.

proposals.tsv columns: id, opened, pattern, shape, subject (its key),
target (`-` for a correction, the reason for an ask), evidence (entry ids), kind, mechanism,
where, source, change, cadence, intervene, cost, off, state (open,
accepted, declined or parked), trigger, closed.

Usage (every verb takes --program <p> right after it):
  scan
      repeat<TAB><pattern><TAB><shape><TAB><subject key><TAB><target>
      <TAB><count><TAB><entry ids> per repeat no proposal covers yet
  propose --pattern <pattern> [--candidate <kind>[:<mechanism>]]...
      --change <t> --cadence <t> --intervene <t> --cost <t> --off <t>
      record a proposal in the confirmation shape; prints
      proposal<TAB><id><TAB><kind><TAB><mechanism><TAB><where>
  show <id>
      the confirmation: what was noticed and its evidence (each entry's
      quote or act), the mechanism and its change, the cadence, where the
      operator still intervenes, the cost, the off switch, the settings
      handover note where it applies, and the explicit decline
  accept <id>
      a rule-kind proposal is applied as a rule-store entry, its undo entry
      logged (applied<TAB>rule<TAB><rule id>; a retry finds the rule an
      earlier accept added); a settings-kind one is handed to the operator,
      handover-operator<TAB><where><TAB><change>, never applied by mission
      control; any other kind is handed over,
      handover<TAB><where><TAB><change>, for the session to apply where it
      may write; nothing enables itself
  decline <id>
  park <id> --trigger <date:YYYY-MM-DD|event:name>
      "not now": parked, with a follow-up ledger row for the trigger
  reopen <id>
      a parked proposal back to open; reopening or declining a parked
      proposal closes its follow-up
  list
      <id><TAB><state><TAB><kind><TAB><mechanism><TAB><subject>

Exit codes: 0 done; 1 refused (a pattern below the threshold or already
proposed, no covering row, a proposal not in the state the verb needs, a
store with a missing or unknown format, a held lock); 2 usage or an
invalid value; 3 the program is not configured.
HELP
}
usage() {
  mc_usage_fail "usage: mc-proposals.sh scan|propose|show|accept|decline|park|reopen|list --program <p> ... (mc-proposals.sh --help)"
}
kb() { mc_kb "$@"; }

STORE=''
INV=''
stores() {
  mc_require_program "$PROGRAM"
  st_home=$(/bin/bash "$script_dir/mc-program.sh" get "$PROGRAM" home) || mc_fail "the home of program $PROGRAM does not resolve"
  STORE=$st_home/kb/proposals.tsv
  INV=$st_home/kb/mechanisms.tsv
  check_store "$STORE"
}
# check_store <file>: a regular file that opens with this format's field.
check_store() {
  cs_label=kb/${1##*/}
  [ ! -L "$1" ] || mc_fail "store $cs_label is a symlink"
  [ -f "$1" ] || mc_fail "store $cs_label is missing (run mc-kb.sh init --program $PROGRAM)"
  [ "$(head -n 1 "$1")" = "# format: $MC_FORMAT" ] || mc_fail "store $cs_label has a missing or unknown format field"
}
lock_store() { mc_kb_lock "$PROGRAM" proposals.tsv; }
# store_write <content>: the content over the store through a dot-named
# sibling, which no knowledge-base path admits, once its format line checks.
# Called in this shell, never in a pipeline, so a refusal ends the verb; the
# caller holds the lock.
store_write() {
  STAGED=$(mktemp "${STORE%/*}/.proposals.tsv.XXXXXX") || mc_fail "cannot stage kb/proposals.tsv"
  printf '%s\n' "$1" >"$STAGED" || mc_fail "cannot stage kb/proposals.tsv"
  [ "$(head -n 1 "$STAGED")" = "# format: $MC_FORMAT" ] || mc_fail "the staged kb/proposals.tsv lost its format field"
  mv -f "$STAGED" "$STORE" || mc_fail "cannot rewrite kb/proposals.tsv"
  STAGED=''
}
text_arg() { # text_arg <flag> <value>
  [ -n "$2" ] || mc_usage_fail "$1 is required"
  mc_valid_text "$2" || mc_usage_fail "$1 carries a tab, newline or control character"
}
id_arg() {
  case $1 in
    p-[1-9] | p-[1-9]*[0-9]) mc_valid_uint "${1#p-}" || mc_usage_fail "a proposal id is p-<n>" ;;
    *) mc_usage_fail "a proposal id is p-<n>" ;;
  esac
}

# repeats: the repeats at the threshold, every pattern, proposed or not.
repeats() {
  rp_n=$(mc_knob mission_control_repeat_threshold mc_parse_count) || exit 1
  rp_w=$(mc_knob mission_control_repeat_window mc_parse_cadence) || exit 1
  rp_now=$(mc_now)
  rp_all=$(mc_kb_entries "$PROGRAM" decisions) || exit $?
  # shellcheck disable=SC2016 # an awk program, expanded by awk
  printf '%s\n' "$rp_all" | N=$rp_n FROM=$(mc_iso $((rp_now - $(mc_seconds "$rp_w")))) TO=$(mc_iso "$rp_now") \
    awk -F '\t' "$MC_GROUNDS_AWK$MC_SUBJECT_KEY_AWK"'
      !/^#/ && $2 >= ENVIRON["FROM"] && $2 <= ENVIRON["TO"] && grounds($6) {
        if (G_REASON ~ /^(correction|manual|answer)$/)
          p = G_REASON "\037" key($3) "\037" (G_REASON == "correction" ? "-" : key($5))
        else if (asked(G_REASON))
          p = "ask\037" key($3) "\037" G_REASON
        else next
        if (!(p in c)) order[++n] = p
        c[p]++; ids[p] = ids[p] (ids[p] == "" ? "" : ",") $1
      }
      END { for (i = 1; i <= n; i++) if (c[order[i]] >= ENVIRON["N"] + 0) print order[i] "\037" c[order[i]] "\037" ids[order[i]] }' \
    | while IFS="$us" read -r r_shape r_key r_target r_count r_ids; do
      r_sum=$(printf '%s\t%s\t%s' "$r_shape" "$r_key" "$r_target" | mc_sha256) || mc_fail "no SHA-256 tool (sha256sum, shasum or openssl) is on PATH"
      r_sum=$(printf '%s' "$r_sum" | cut -c 1-32)
      printf 'pat-%s\t%s\t%s\t%s\t%s\t%s\n' "$r_sum" "$r_shape" "$r_key" "$r_target" "$r_count" "$r_ids"
    done
}

# row <id>: the proposal's line, or a refusal.
ROW=''
row() {
  ROW=$(I=$1 awk -F '\t' '$1 == ENVIRON["I"] { print; exit }' "$STORE")
  [ -n "$ROW" ] || mc_fail "no proposal $1"
}
col() { printf '%s\n' "$ROW" | cut -f "$1"; }
settings_kind() { # settings_kind <kind> <where>
  case $1 in
    hook | permission) return 0 ;;
  esac
  case $2 in
    */settings.json | */settings.local.json) return 0 ;;
  esac
  return 1
}
# set_state <id> <state> [<trigger>]: rewrite the proposal's state, trigger
# and closing time; the caller holds the lock.
set_state() {
  ss_closed=-
  case $2 in
    accepted | declined) ss_closed=$(mc_iso "$(mc_now)") ;;
  esac
  ss_out=$(I=$1 S=$2 T=${3:--} C=$ss_closed awk -F '\t' 'BEGIN { OFS = "\t" }
    $1 == ENVIRON["I"] { $17 = ENVIRON["S"]; $18 = ENVIRON["T"]; $19 = ENVIRON["C"] }
    { print }' "$STORE") || mc_fail "cannot read kb/proposals.tsv"
  store_write "$ss_out"
}
require_state() { # require_state <id> <state...>
  rs_id=$1
  shift
  rs_have=$(col 17)
  for rs_s in "$@"; do
    [ "$rs_have" != "$rs_s" ] || return 0
  done
  mc_fail "proposal $rs_id is $(sanitize_printable "$rs_have")"
}

followup_text() { printf 're-raise mechanization proposal %s (mc-proposals.sh reopen)' "$1"; }
# close_followups <id> <evidence>: close the open follow-ups parking left;
# a close that fails ends the verb, naming the follow-up still open.
close_followups() {
  cf_rows=$(kb followup list --program "$PROGRAM") || mc_fail "the proposal moved, but the follow-up ledger cannot be read, so its parking follow-up is still open"
  cf_ids=$(printf '%s\n' "$cf_rows" | T=$(followup_text "$1") awk -F '\t' '$5 == "open" && $6 == ENVIRON["T"] { print $1 }')
  for cf_id in $cf_ids; do
    kb followup close --program "$PROGRAM" "$cf_id" --evidence "$2" >/dev/null \
      || mc_fail "the proposal moved, but its parking follow-up $cf_id could not be closed; close it with mc-kb.sh followup close"
  done
}

# accept_rule <id>: add the proposal's rule and log its undo entry, setting
# RID. A rule an earlier, interrupted accept added is found by its source and
# reused, and its undo entry logged if that accept stopped short of it, so a
# retry never adds the rule twice or leaves it without its reversal.
RID=''
accept_rule() {
  ar_src="mechanization proposal $1, accepted by the operator"
  ar_list=$(/bin/bash "$script_dir/mc-rules.sh" active "$PROGRAM") || mc_fail "the rule store cannot be read"
  RID=$(printf '%s\n' "$ar_list" | S=$ar_src awk -F '\t' '$7 == ENVIRON["S"] { print $1; exit }')
  if [ -z "$RID" ]; then
    ar_out=$(/bin/bash "$script_dir/mc-rules.sh" add "$PROGRAM" --text "$(col 12)" --subject "$(col 5)" \
      --source "$ar_src" --date today) || mc_fail "the rule was not added; proposal $1 stays open"
    RID=$(printf '%s\n' "$ar_out" | sed -n '1s/^rule \(r-[0-9][0-9]*\) .*/\1/p')
    [ -n "$RID" ] || mc_fail "the rule store did not report the rule it added; proposal $1 stays open"
  fi
  ar_logged=$(mc_kb query undo --program "$PROGRAM" --subject "$(col 5)") || mc_fail "the undo log cannot be read"
  printf '%s\n' "$ar_logged" | R=$RID awk -F '\t' '$4 == "rule-add" && $5 == ENVIRON["R"] { f = 1 } END { exit !f }' && return 0
  # The reversal mc-rules.sh prints for an add, as its words.
  mc_kb append undo --program "$PROGRAM" --subject "$(col 5)" --act rule-add --target "$RID" --grounds "$ar_src" \
    -- mc-rules.sh supersede "$PROGRAM" "$RID" --withdraw --source "undo of $RID" --date today >/dev/null \
    || mc_fail "the undo entry for $RID was not logged; accept proposal $1 again to log it"
}

# --- verbs -------------------------------------------------------------------

v_scan() {
  [ $# -eq 0 ] || usage
  stores
  sc_rep=$(repeats) || exit $?
  printf '%s\n' "$sc_rep" | awk -F '\t' 'NR == FNR { if ($0 !~ /^#/) seen[$3] = 1; next }
    $1 != "" && !($1 in seen) { print "repeat\t" $0 }' "$STORE" - | mc_clean_text
}

v_propose() {
  pattern='' change='' cadence='' intervene='' cost='' off=''
  cands=()
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || usage
    case $1 in
      --pattern) pattern=$2 ;;
      --candidate)
        text_arg --candidate "$2"
        cands[${#cands[@]}]=$2
        ;;
      --change) change=$2 ;;
      --cadence) cadence=$2 ;;
      --intervene) intervene=$2 ;;
      --cost) cost=$2 ;;
      --off) off=$2 ;;
      *) usage ;;
    esac
    shift 2
  done
  case $pattern in
    pat-[0-9a-f]*)
      case ${pattern#pat-} in
        *[!0-9a-f]*) mc_usage_fail "--pattern takes a pattern id from scan, pat-<hex>" ;;
      esac
      [ "${#pattern}" -eq 36 ] || mc_usage_fail "--pattern takes a pattern id from scan, pat-<hex>"
      ;;
    *) mc_usage_fail "--pattern takes a pattern id from scan, pat-<hex>" ;;
  esac
  text_arg --change "$change"
  text_arg --cadence "$cadence"
  text_arg --intervene "$intervene"
  text_arg --cost "$cost"
  text_arg --off "$off"
  stores
  check_store "$INV"
  lock_store
  prior=$(P=$pattern awk -F '\t' '$3 == ENVIRON["P"] { print $1 "\t" $17; exit }' "$STORE")
  if [ -n "$prior" ]; then
    case ${prior#*"$tab"} in
      declined) mc_fail "pattern $pattern was declined (${prior%%"$tab"*}); it is not proposed again" ;;
      *) mc_fail "pattern $pattern is already proposed (${prior%%"$tab"*}, ${prior#*"$tab"})" ;;
    esac
  fi
  rep=$(repeats) || exit $?
  line=$(printf '%s\n' "$rep" | P=$pattern awk -F '\t' '$1 == ENVIRON["P"] { print; exit }')
  [ -n "$line" ] || mc_fail "pattern $pattern is not a repeat at the threshold inside the window"
  IFS="$us" read -r _ shape subject target _ evidence <<EOF
$(printf '%s' "$line" | tr '\t' '\037')
EOF
  if [ "${#cands[@]}" -eq 0 ]; then
    [ "$shape" = correction ] || mc_usage_fail "a $shape repeat names its candidate mechanisms (--candidate <kind>[:<mechanism>])"
    cands=(rule)
  fi
  pick=$(for c in "${cands[@]}"; do printf 'C\t%s\n' "$c"; done | awk -F '\t' '
    function rank(k) {
      if (k == "rule") return 1; if (k == "knob") return 2; if (k == "catalog-step") return 3
      if (k == "permission") return 4; if (k == "hook") return 5; if (k == "routine") return 6
      if (k == "duty") return 8; return 7
    }
    NR == FNR { if ($0 !~ /^#/ && NF == 4) { nr++; rk[nr] = $1; rm[nr] = $2; row[nr] = $0; nk[$1]++ } next }
    {
      c = $2; p = index(c, ":")
      k = p ? substr(c, 1, p - 1) : c; m = p ? substr(c, p + 1) : ""
      if (!p && nk[k] > 1) { print "AMBIGUOUS\t" k; exit }
      for (i = 1; i <= nr; i++) {
        if (rk[i] != k || (p && rm[i] != m)) continue
        if (best == "" || rank(k) < brank) { best = row[i]; brank = rank(k) }
        break
      }
    }
    END { if (best != "") print best }' "$INV" -)
  case $pick in
    AMBIGUOUS"$tab"*) mc_usage_fail "the inventory has several ${pick#*"$tab"} rows; name one as --candidate ${pick#*"$tab"}:<mechanism>" ;;
  esac
  [ -n "$pick" ] || mc_fail "no row of the mechanism inventory covers pattern $pattern; no proposal is raised"
  IFS="$us" read -r kind mech where source <<EOF
$(printf '%s' "$pick" | tr '\t' '\037')
EOF
  n=$(awk -F '\t' '!/^#/ && NF { n++ } END { print n + 0 }' "$STORE")
  id=p-$((n + 1))
  old=$(cat "$STORE") || mc_fail "cannot read kb/proposals.tsv"
  new=$(printf '%s\t' "$id" "$(mc_iso "$(mc_now)")" "$pattern" "$shape" "$subject" "$target" "$evidence" "$kind" "$mech" \
    "$where" "$source" "$change" "$cadence" "$intervene" "$cost" "$off" open -)
  store_write "$old
$new-"
  printf 'proposal\t%s\t%s\t%s\t%s\n' "$id" "$kind" "$mech" "$where" | mc_clean_text
}

v_show() {
  [ $# -eq 1 ] || usage
  id_arg "$1"
  stores
  row "$1"
  all=$(mc_kb_entries "$PROGRAM" decisions) || exit $?
  {
    printf 'proposal\t%s\t%s\n' "$1" "$(col 17)"
    ev=$(col 7)
    count=$(printf '%s\n' "$ev" | awk -F ',' '{ print NF }')
    case $(col 4) in
      correction) printf 'noticed\tcorrection repeated %s times: %s\n' "$count" "$(col 5)" ;;
      manual) printf 'noticed\tmanual step repeated %s times: %s, after %s\n' "$count" "$(col 5)" "$(col 6)" ;;
      ask) printf 'noticed\task repeated %s times: %s, by %s\n' "$count" "$(col 5)" "$(col 6)" ;;
      *) printf 'noticed\tanswer repeated %s times: %s, answered %s\n' "$count" "$(col 5)" "$(col 6)" ;;
    esac
    printf '%s\n' "$all" | E=,$ev, awk -F '\t' 'index(ENVIRON["E"], "," $1 ",") { printf "evidence\t%s\t%s\n", $1, $4 }'
    printf 'mechanism\t%s\t%s\t%s\t%s\n' "$(col 8)" "$(col 9)" "$(col 10)" "$(col 11)"
    printf 'change\t%s\ncadence\t%s\nintervene\t%s\ncost\t%s\noff\t%s\n' "$(col 12)" "$(col 13)" "$(col 14)" "$(col 15)" "$(col 16)"
    if settings_kind "$(col 8)" "$(col 10)"; then
      printf 'settings\tready to apply, never written: %s\n' "$(col 10)"
    fi
    printf 'decline\tsay no and this pattern is not proposed again; "not now" parks it until a trigger\n'
  } | mc_clean_text
}

v_outcome() { # v_outcome <accept|decline|park|reopen> <id> [--trigger <t>]
  outcome=$1
  shift
  [ $# -ge 1 ] || usage
  id=$1
  shift
  trigger=''
  if [ "$outcome" = park ]; then
    [ $# -eq 2 ] && [ "$1" = --trigger ] || usage
    trigger=$2
    case $trigger in
      date:[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
      event:?*) mc_valid_kebab "${trigger#event:}" || mc_usage_fail "a trigger is date:<YYYY-MM-DD> or event:<name>" ;;
      *) mc_usage_fail "a trigger is date:<YYYY-MM-DD> or event:<name>" ;;
    esac
  else
    [ $# -eq 0 ] || usage
  fi
  id_arg "$id"
  stores
  lock_store
  row "$id"
  case $outcome in
    accept)
      require_state "$id" open
      if [ "$(col 8)" = rule ]; then
        accept_rule "$id"
        set_state "$id" accepted
        printf 'applied\trule\t%s\n' "$RID"
      elif settings_kind "$(col 8)" "$(col 10)"; then
        set_state "$id" accepted
        printf 'handover-operator\t%s\t%s\n' "$(col 10)" "$(col 12)" | mc_clean_text
      else
        set_state "$id" accepted
        printf 'handover\t%s\t%s\n' "$(col 10)" "$(col 12)" | mc_clean_text
      fi
      ;;
    decline)
      require_state "$id" open parked
      was=$(col 17)
      set_state "$id" declined
      [ "$was" != parked ] || close_followups "$id" "proposal $id declined"
      printf 'declined\t%s\n' "$id"
      ;;
    park)
      require_state "$id" open
      set_state "$id" parked "$trigger"
      if ! kb followup add --program "$PROGRAM" --owner mission-control --trigger "$trigger" \
        --text "$(followup_text "$id")" >/dev/null; then
        set_state "$id" open
        mc_fail "the follow-up was not written; proposal $id stays open"
      fi
      printf 'parked\t%s\t%s\n' "$id" "$trigger"
      ;;
    reopen)
      require_state "$id" parked
      set_state "$id" open
      close_followups "$id" "proposal $id reopened"
      printf 'open\t%s\n' "$id"
      ;;
  esac
}

v_list() {
  [ $# -eq 0 ] || usage
  stores
  awk -F '\t' '!/^#/ && NF >= 17 { printf "%s\t%s\t%s\t%s\t%s\n", $1, $17, $8, $9, $5 }' "$STORE" | mc_clean_text
}

[ $# -ge 1 ] || usage
case $1 in
  --help | -h | help)
    help_text
    exit 0
    ;;
esac
verb=$1
shift
PROGRAM=''
[ $# -ge 2 ] && [ "$1" = --program ] || mc_usage_fail "--program <name> follows the verb"
PROGRAM=$2
shift 2
case $verb in
  scan) v_scan "$@" ;;
  propose) v_propose "$@" ;;
  show) v_show "$@" ;;
  accept | decline | park | reopen) v_outcome "$verb" "$@" ;;
  list) v_list "$@" ;;
  *) usage ;;
esac
