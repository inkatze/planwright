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
TOKEN=''
on_exit() {
  [ -z "$TOKEN" ] || /bin/bash "$script_dir/mc-kb.sh" unlock --program "$PROGRAM" proposals.tsv --token "$TOKEN" >/dev/null 2>&1
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
on one subject after one event, or one answer to one question. Subjects
compare by the rule store's subject key. A pattern with a proposal in any
state is never raised again; a declined one stays declined.

A proposal maps the repeat onto one row of the mechanism inventory
(kb/mechanisms.tsv, scripts/mc-kb.sh inventory-refresh), never onto a
mechanism absent from it: of the candidates the caller names, the row of
the smallest kind wins, in the order rule, knob, catalog-step, permission,
hook, routine, any other kind, duty. A correction with no candidate names
the rule row. A row of kind hook or permission, or whose location is a
settings file, is settings-kind: its change is handed over ready to apply
and never written.

proposals.tsv columns: id, opened, pattern, shape, subject (its key),
target (`-` for a correction), evidence (entry ids), kind, mechanism,
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
      a rule-kind proposal is applied as a rule-store entry
      (applied<TAB>rule<TAB><rule id>); any other kind is handed over,
      handover<TAB><where><TAB><change>, for the session or the operator
      to apply; nothing enables itself
  decline <id>
  park <id> --trigger <date:YYYY-MM-DD|event:name>
      "not now": parked, with a follow-up ledger row for the trigger
  reopen <id>
      a parked proposal back to open
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
kb() { /bin/bash "$script_dir/mc-kb.sh" "$@"; }

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
lock_store() {
  TOKEN=$(kb lock --program "$PROGRAM" proposals.tsv --holder $$) || mc_fail "cannot take the lock on kb/proposals.tsv"
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
  rp_n=$(mc_knob mission_control_repeat_threshold mc_parse_uint) || exit 1
  rp_w=$(mc_knob mission_control_repeat_window mc_parse_cadence) || exit 1
  rp_now=$(mc_now)
  rp_all=$(kb entries --program "$PROGRAM" decisions) || mc_fail "the decisions log cannot be read"
  # shellcheck disable=SC2016 # an awk program, expanded by awk
  printf '%s\n' "$rp_all" | N=$rp_n FROM=$(mc_iso $((rp_now - $(mc_seconds "$rp_w")))) TO=$(mc_iso "$rp_now") \
    awk -F '\t' "$MC_GROUNDS_AWK$MC_SUBJECT_KEY_AWK"'
      !/^#/ && $2 >= ENVIRON["FROM"] && $2 <= ENVIRON["TO"] && grounds($6) && G_REASON ~ /^(correction|manual|answer)$/ {
        p = G_REASON "\t" key($3) "\t" (G_REASON == "correction" ? "-" : key($5))
        if (!(p in c)) order[++n] = p
        c[p]++; ids[p] = ids[p] (ids[p] == "" ? "" : ",") $1
      }
      END { for (i = 1; i <= n; i++) if (c[order[i]] >= ENVIRON["N"] + 0) print order[i] "\t" c[order[i]] "\t" ids[order[i]] }' \
    | while IFS="$tab" read -r r_shape r_key r_target r_count r_ids; do
      r_sum=$(printf '%s\t%s\t%s' "$r_shape" "$r_key" "$r_target" | cksum | awk '{ print $1 }')
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
  I=$1 S=$2 T=${3:--} C=$ss_closed awk -F '\t' 'BEGIN { OFS = "\t" }
    $1 == ENVIRON["I"] { $17 = ENVIRON["S"]; $18 = ENVIRON["T"]; $19 = ENVIRON["C"] }
    { print }' "$STORE" | mc_write "$STORE" || mc_fail "cannot rewrite kb/proposals.tsv"
}
require_state() { # require_state <id> <state...>
  rs_id=$1
  shift
  rs_have=$(col 17)
  for rs_s in "$@"; do
    [ "$rs_have" != "$rs_s" ] || return 0
  done
  mc_fail "proposal $rs_id is $rs_have"
}

# --- verbs -------------------------------------------------------------------

v_scan() {
  [ $# -eq 0 ] || usage
  stores
  sc_rep=$(repeats) || exit $?
  printf '%s\n' "$sc_rep" | awk -F '\t' 'NR == FNR { if ($0 !~ /^#/) seen[$3] = 1; next }
    $1 != "" && !($1 in seen) { print "repeat\t" $0 }' "$STORE" - | mc_clean
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
    pat-[0-9]*) mc_valid_uint "${pattern#pat-}" || mc_usage_fail "--pattern takes a pattern id from scan, pat-<n>" ;;
    *) mc_usage_fail "--pattern takes a pattern id from scan, pat-<n>" ;;
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
  IFS="$tab" read -r _ shape subject target _ evidence <<EOF
$line
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
    NR == FNR { if ($0 !~ /^#/ && NF == 4) { nr++; rk[nr] = $1; rm[nr] = $2; row[nr] = $0 } next }
    {
      c = $2; p = index(c, ":")
      k = p ? substr(c, 1, p - 1) : c; m = p ? substr(c, p + 1) : ""
      for (i = 1; i <= nr; i++) {
        if (rk[i] != k || (p && rm[i] != m)) continue
        if (best == "" || rank(k) < brank) { best = row[i]; brank = rank(k) }
        break
      }
    }
    END { if (best != "") print best }' "$INV" -)
  [ -n "$pick" ] || mc_fail "no row of the mechanism inventory covers pattern $pattern; no proposal is raised"
  IFS="$tab" read -r kind mech where source <<EOF
$pick
EOF
  n=$(awk -F '\t' '!/^#/ && NF { n++ } END { print n + 0 }' "$STORE")
  id=p-$((n + 1))
  {
    cat "$STORE"
    printf '%s\t' "$id" "$(mc_iso "$(mc_now)")" "$pattern" "$shape" "$subject" "$target" "$evidence" "$kind" "$mech" \
      "$where" "$source" "$change" "$cadence" "$intervene" "$cost" "$off" open -
    printf '%s\n' -
  } | mc_write "$STORE" || mc_fail "cannot write kb/proposals.tsv"
  printf 'proposal\t%s\t%s\t%s\t%s\n' "$id" "$kind" "$mech" "$where" | mc_clean
}

v_show() {
  [ $# -eq 1 ] || usage
  id_arg "$1"
  stores
  row "$1"
  all=$(kb entries --program "$PROGRAM" decisions) || mc_fail "the decisions log cannot be read"
  {
    printf 'proposal\t%s\t%s\n' "$1" "$(col 17)"
    ev=$(col 7)
    count=$(printf '%s\n' "$ev" | awk -F ',' '{ print NF }')
    case $(col 4) in
      correction) printf 'noticed\tcorrection repeated %s times: %s\n' "$count" "$(col 5)" ;;
      manual) printf 'noticed\tmanual step repeated %s times: %s, after %s\n' "$count" "$(col 5)" "$(col 6)" ;;
      *) printf 'noticed\tanswer repeated %s times: %s, answered %s\n' "$count" "$(col 5)" "$(col 6)" ;;
    esac
    printf '%s\n' "$all" | E=,$ev, awk -F '\t' 'index(ENVIRON["E"], "," $1 ",") { printf "evidence\t%s\t%s\n", $1, $4 }'
    printf 'mechanism\t%s\t%s\t%s\t%s\n' "$(col 8)" "$(col 9)" "$(col 10)" "$(col 11)"
    printf 'change\t%s\ncadence\t%s\nintervene\t%s\ncost\t%s\noff\t%s\n' "$(col 12)" "$(col 13)" "$(col 14)" "$(col 15)" "$(col 16)"
    if settings_kind "$(col 8)" "$(col 10)"; then
      printf 'settings\tready to apply, never written: %s\n' "$(col 10)"
    fi
    printf 'decline\tsay no and this pattern is not proposed again; "not now" parks it until a trigger\n'
  } | mc_clean
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
        added=$(/bin/bash "$script_dir/mc-rules.sh" add "$PROGRAM" --text "$(col 12)" --subject "$(col 5)" \
          --source "mechanization proposal $id, accepted by the operator" --date today) || mc_fail "the rule was not added; proposal $id stays open"
        rid=$(printf '%s\n' "$added" | sed -n '1s/^rule \(r-[0-9]*\) .*/\1/p')
        set_state "$id" accepted
        printf 'applied\trule\t%s\n' "$rid"
      else
        set_state "$id" accepted
        printf 'handover\t%s\t%s\n' "$(col 10)" "$(col 12)" | mc_clean
      fi
      ;;
    decline)
      require_state "$id" open parked
      set_state "$id" declined
      printf 'declined\t%s\n' "$id"
      ;;
    park)
      require_state "$id" open
      kb followup add --program "$PROGRAM" --owner mission-control --trigger "$trigger" \
        --text "re-raise mechanization proposal $id (mc-proposals.sh reopen)" >/dev/null || mc_fail "the follow-up was not written; proposal $id stays open"
      set_state "$id" parked "$trigger"
      printf 'parked\t%s\t%s\n' "$id" "$trigger"
      ;;
    reopen)
      require_state "$id" parked
      set_state "$id" open
      printf 'open\t%s\n' "$id"
      ;;
  esac
}

v_list() {
  [ $# -eq 0 ] || usage
  stores
  awk -F '\t' '!/^#/ && NF >= 17 { printf "%s\t%s\t%s\t%s\t%s\n", $1, $17, $8, $9, $5 }' "$STORE" | mc_clean
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
