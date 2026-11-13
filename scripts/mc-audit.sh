#!/usr/bin/env bash
# mc-audit.sh — mission control's self-audit: a mechanical compare of a
# program's decisions and undo logs against its active rule set. It reads
# and reports; it never edits a rule or a log.
#
# `mc-audit.sh --help` prints the contract: findings, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-audit
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
mc-audit.sh — the self-audit over a program's knowledge base and rule store.

Usage:
  mc-audit.sh run --program <p> [--now <epoch>]

An act is a decisions-log entry mission control took (reason `settled` in
scripts/mc-decide.sh's reasons grammar, or grounds outside the grammar) or
an undo-log entry, aside from the rule store's own rule-add,
rule-supersede and rule-withdraw entries and the reverting, reverted and
revert failed entries scripts/mc-kb.sh revert writes; asked decisions,
verdicts and noted repeats are not acts. An act cites the rules its grounds name. Subjects compare by
the rule store's subject key. Findings, one line each:
  finding<TAB>against-rule<TAB><rule id><TAB><entry id><TAB><subject key>
      an act on an active rule's subject, on or after the rule's date,
      that does not cite the rule
  finding<TAB>idle-rule<TAB><rule id><TAB>-<TAB><subject key>
      an active rule dated before the period
      (mission_control_audit_idle_after) with no act on its subject in it
  finding<TAB>shared-subject<TAB><id>,<id>[,...]<TAB>-<TAB><subject key>
      active entries sharing a subject (scripts/mc-rules.sh conflicts);
      whether they conflict is the operator's call
then audit<TAB><n> findings. A log line that is not a whole entry is
skipped with a warning on stderr. A finding is the operator's item or a rule
proposal for the caller to raise; the audit raises and edits nothing.

Exit codes: 0 audited; 1 a store or log that cannot be read; 2 usage or an
invalid value; 3 the program is not configured.
HELP
}
usage() { mc_usage_fail "usage: mc-audit.sh run --program <p> [--now <epoch>] (mc-audit.sh --help)"; }

[ $# -ge 1 ] || usage
case $1 in
  --help | -h | help)
    help_text
    exit 0
    ;;
esac
[ "$1" = run ] || usage
shift
[ $# -ge 2 ] && [ "$1" = --program ] || mc_usage_fail "--program <name> follows the verb"
PROGRAM=$2
shift 2
now_raw=''
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case $1 in
    --now) now_raw=$2 ;;
    *) usage ;;
  esac
  shift 2
done
mc_now_arg "$now_raw"
mc_require_program "$PROGRAM"
idle=$(mc_knob mission_control_audit_idle_after mc_parse_cadence) || exit 1
idle_s=$(mc_seconds "$idle")

rules=$(/bin/bash "$script_dir/mc-rules.sh" active "$PROGRAM") || mc_fail "the rule store cannot be read"
shared=$(/bin/bash "$script_dir/mc-rules.sh" conflicts "$PROGRAM") || mc_fail "the shared-subject report failed"
decisions=$(mc_kb_entries "$PROGRAM" decisions) || exit $?
undo=$(mc_kb_entries "$PROGRAM" undo) || exit $?
# A line short of an entry's fields (a crash's partial append, until the next
# append drops it) is skipped, and said, so a clean audit never hides one.
skipped=$(printf '%s\n%s\n' "$decisions" "$undo" | awk -F '\t' 'NF && NF != 8 { n++ } END { print n + 0 }')
[ "$skipped" -eq 0 ] || printf '%s\n' "$prog: warning: skipped $skipped log line(s) that are not whole entries" >&2

# One stream: R lines (the active rules), A lines (the acts, each with the
# rules it cites), S lines (the shared subjects).
{
  printf '%s\n' "$rules" | awk -F '\t' 'NF >= 5 { printf "R\t%s\t%s\t%s\n", $1, $3, $5 }'
  # shellcheck disable=SC2016 # the awk program after the pipe, expanded by awk
  {
    printf '%s\n' "$decisions" | awk '{ print "decisions\t" $0 }'
    printf '%s\n' "$undo" | awk '{ print "undo\t" $0 }'
  } | awk -F '\t' "$MC_GROUNDS_AWK"'
    NF >= 7 {
      parsed = grounds($7)
      if ($1 == "decisions" && parsed && G_REASON != "settled") next
      if ($1 == "undo" && $5 ~ /^(rule-(add|supersede|withdraw)|reverting|reverted|revert failed)$/) next
      printf "A\t%s\t%s\t%s\t%s\n", $2, $3, $4, (parsed ? G_RULES : "-")
    }'
  printf '%s\n' "$shared" | awk -F '\t' '$1 == "shared" { printf "S\t%s\t%s\n", $2, $3 }'
} | TO=$(mc_iso "$NOW") FROM=$(mc_iso $((NOW - idle_s))) awk -F '\t' "$MC_SUBJECT_KEY_AWK"'
  $1 == "R" { nr++; rid[nr] = $2; rdate[nr] = $3; rkey[nr] = key($4); next }
  $1 == "A" && $3 <= ENVIRON["TO"] {
    na++; aid[na] = $2; ats[na] = $3; acite[na] = "," $5 ","
    k = key($4); bykey[k] = bykey[k] " " na
    next
  }
  $1 == "S" { ns++; skey[ns] = $2; sids[ns] = $3; next }
  END {
    n = 0
    for (r = 1; r <= nr; r++) {
      recent = 0
      m = split(bykey[rkey[r]], hit, " ")
      for (h = 1; h <= m; h++) {
        a = hit[h]
        if (ats[a] >= ENVIRON["FROM"]) recent = 1
        if (substr(ats[a], 1, 10) >= rdate[r] && index(acite[a], "," rid[r] ",") == 0) {
          printf "finding\tagainst-rule\t%s\t%s\t%s\n", rid[r], aid[a], rkey[r]; n++
        }
      }
      if (!recent && rdate[r] < substr(ENVIRON["FROM"], 1, 10)) {
        printf "finding\tidle-rule\t%s\t-\t%s\n", rid[r], rkey[r]; n++
      }
    }
    for (s = 1; s <= ns; s++) { printf "finding\tshared-subject\t%s\t-\t%s\n", sids[s], skey[s]; n++ }
    printf "audit\t%d findings\n", n
  }' | mc_clean_text
