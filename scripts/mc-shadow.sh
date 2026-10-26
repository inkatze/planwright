#!/usr/bin/env bash
# mc-shadow.sh — the shadow lifecycle of a mission-control duty: the one
# path a duty's operator item takes, raised when the duty is live and
# written as a would-have entry when it is in shadow, and the promotion
# suggestion once the operator has agreed with enough of those entries.
#
# `mc-shadow.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-shadow
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
mc-shadow.sh — a duty's lifecycle (off, shadow, live; config/duties.yaml)
applied to what it raises.

Usage:
  mc-shadow.sh raise --program <p> --duty <id> -- <kind> <subject> [<text>]
      an operator item of a kind the duty declares. A live duty's item is
      emitted to the attention store (scripts/mc-event.sh) and prints
      raised<TAB><event id>; a shadow duty's is written to the
      knowledge base's would-have log, act `<kind>: <text>`, and prints
      would-have<TAB><entry id>, raising nothing. <subject> takes the
      event grammar in both, so promotion changes nothing else.
  mc-shadow.sh agree --program <p> <would-have entry id>
      the operator agrees with what the duty would have done, logged as an
      `agreed` would-have entry naming it; each entry is agreed once
  mc-shadow.sh promotion --program <p>
      per armed shadow duty, promote<TAB><id><TAB><agreed><TAB><needed>
      once the agreed entries reach mission_control_shadow_promote_after,
      else shadow<TAB><id><TAB><agreed><TAB><needed>. A suggestion only:
      promotion is the operator's edit of the duty's lifecycle.

Exit codes: 0 done; 1 refused (a duty not armed, an entry not found or
already agreed, a store refusal); 2 usage or an invalid value; 3 the
program is not configured.
HELP
}
usage() {
  mc_usage_fail "usage: mc-shadow.sh raise --program <p> --duty <id> -- <kind> <subject> [<text>] | agree --program <p> <id> | promotion --program <p> (mc-shadow.sh --help)"
}
kb() { /bin/bash "$script_dir/mc-kb.sh" "$@"; }
duties() { /bin/bash "$script_dir/mc-duties.sh" "$@"; }

# armed: the program's armed duties, <id><TAB><dir> lines.
armed() {
  duties files --program "$PROGRAM" || mc_fail "the duties of program $PROGRAM do not resolve"
}
# would_have: every would-have entry, oldest first.
would_have() {
  kb entries --program "$PROGRAM" would-have || mc_fail "the would-have log cannot be read"
}

v_raise() {
  duty=''
  while [ $# -gt 0 ]; do
    case $1 in
      --duty)
        [ $# -ge 2 ] || usage
        duty=$2
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *) usage ;;
    esac
  done
  [ $# -ge 2 ] && [ $# -le 3 ] || usage
  kind=$1 subject=$2 text=${3:-}
  mc_valid_kebab "$duty" || mc_usage_fail "--duty takes a duty id"
  mc_valid_kebab "$kind" && [ "${#kind}" -le 64 ] || mc_usage_fail "the kind is kebab, at most 64 characters"
  mc_valid_handle "$subject" || mc_usage_fail "the subject takes the event grammar (letters, digits, . _ = @ : -)"
  mc_valid_text "$text" || mc_usage_fail "the text carries a control character"
  mc_require_program "$PROGRAM"
  a=$(armed) || exit $?
  printf '%s\n' "$a" | D=$duty awk -F '\t' '$1 == ENVIRON["D"] { f = 1 } END { exit !f }' \
    || mc_fail "duty $duty is not armed in program $PROGRAM (not enabled, or off); it raises nothing"
  kinds=$(duties get "$duty" kinds) || mc_fail "the kinds of duty $duty do not resolve"
  K=$kind L=$kinds awk 'BEGIN {
    l = ENVIRON["L"]; gsub(/^[[ ]+|[] ]+$/, "", l)
    n = split(l, k, ",")
    for (i = 1; i <= n; i++) { gsub(/^ +| +$/, "", k[i]); if (k[i] == ENVIRON["K"]) exit 0 }
    exit 1
  }' || mc_usage_fail "duty $duty declares no item kind $kind (its kinds: $kinds)"
  lifecycle=$(duties get "$duty" lifecycle) || mc_fail "the lifecycle of duty $duty does not resolve"
  case $lifecycle in
    live)
      id=$(mc_event emit --program "$PROGRAM" -- "$kind" "$subject" "$text") || mc_fail "the item was not raised"
      printf 'raised\t%s\n' "$id"
      ;;
    shadow)
      id=$(kb append would-have --program "$PROGRAM" --subject "$subject" --act "$kind: ${text:-$kind}" --duty "$duty") \
        || mc_fail "the would-have entry was not written"
      printf 'would-have\t%s\n' "$id"
      ;;
    *) mc_fail "duty $duty has lifecycle $lifecycle; it raises nothing" ;;
  esac
}

v_agree() {
  [ $# -eq 1 ] || usage
  case $1 in
    would-have-[0-9]*-[0-9]*) ;;
    *) mc_usage_fail "a would-have entry id is would-have-<YYYYMM>-<n>" ;;
  esac
  mc_require_program "$PROGRAM"
  all=$(would_have) || exit $?
  line=$(printf '%s\n' "$all" | I=$1 awk -F '\t' '$1 == ENVIRON["I"] && $4 != "agreed" { print; exit }')
  [ -n "$line" ] || mc_fail "no would-have entry $1"
  if printf '%s\n' "$all" | I=$1 awk -F '\t' '$4 == "agreed" && $5 == ENVIRON["I"] { f = 1 } END { exit !f }'; then
    mc_fail "would-have entry $1 is already agreed"
  fi
  subject=$(printf '%s\n' "$line" | cut -f 3)
  duty=$(printf '%s\n' "$line" | cut -f 8)
  id=$(kb append would-have --program "$PROGRAM" --subject "$subject" --act agreed --target "$1" \
    --grounds "the operator agrees" --duty "$duty") || mc_fail "the agreement was not written"
  printf 'agreed\t%s\t%s\n' "$1" "$id"
}

v_promotion() {
  [ $# -eq 0 ] || usage
  mc_require_program "$PROGRAM"
  need=$(mc_knob mission_control_shadow_promote_after mc_parse_uint) || exit 1
  a=$(armed) || exit $?
  all=$(would_have) || exit $?
  while IFS="$(printf '\t')" read -r d _; do
    [ -n "$d" ] || continue
    [ "$(duties get "$d" lifecycle)" = shadow ] || continue
    n=$(printf '%s\n' "$all" | D=$d awk -F '\t' '$4 == "agreed" && $8 == ENVIRON["D"] { n++ } END { print n + 0 }')
    if [ "$n" -ge "$need" ]; then
      printf 'promote\t%s\t%s\t%s\n' "$d" "$n" "$need"
    else
      printf 'shadow\t%s\t%s\t%s\n' "$d" "$n" "$need"
    fi
  done <<EOF
$a
EOF
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
[ $# -ge 2 ] && [ "$1" = --program ] || mc_usage_fail "--program <name> follows the verb"
PROGRAM=$2
shift 2
case $verb in
  raise) v_raise "$@" ;;
  agree) v_agree "$@" ;;
  promotion) v_promotion "$@" ;;
  *) usage ;;
esac
