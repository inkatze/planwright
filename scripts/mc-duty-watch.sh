#!/usr/bin/env bash
# mc-duty-watch.sh — the watcher of the undo-ledger, self-audit and proposals
# duties: one read-only pass over what the duty's script already reports,
# raising an event only when the report changed since the last pass.
#
# `mc-duty-watch.sh --help` prints the contract.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-duty-watch
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

STAGED=''
trap '[ -z "$STAGED" ] || rm -f "$STAGED"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

help_text() {
  cat <<'HELP'
mc-duty-watch.sh — the watcher of the undo-ledger, self-audit and proposals
duties.

Usage:
  mc-duty-watch.sh watch [--program <p>] [--duty <id>]
      The program from PLANWRIGHT_MC_PROGRAM and the duty from
      PLANWRIGHT_MC_DUTY when the options are absent (a run with no
      arguments under the runner). It reads and edits nothing of the
      program's records, and prints
        checked<TAB><duty><TAB><n>
      with n the findings of the pass, then, only when the findings differ
      from the last pass's, one event line the runner turns into an event:
        event<TAB>self-audit-finding<TAB>self-audit<TAB><text>
            scripts/mc-audit.sh run: its findings
        event<TAB>proposal-repeat<TAB>proposals<TAB><text>
            scripts/mc-proposals.sh scan: the repeats no proposal covers
        event<TAB>undo-revert-stuck<TAB>undo-ledger<TAB><text>
            an undo entry whose revert logged `reverting` and no outcome,
            which scripts/mc-kb.sh revert never runs again unasked
      A pass whose findings went to none after a raise prints
        cleared<TAB><duty>
      and forgets them, so a return raises afresh. What the last pass saw is
      one line in the duty's own directory of the knowledge base
      (kb/<files>/watch.last).

Exit codes: 0 done; 1 the duty's script or the records it reads failed, or
the state could not be written; 2 usage, or a duty this watcher does not
serve; 3 the program is not configured.

Portable bash 3.2 / BSD tooling.
HELP
}

usage() {
  mc_usage_fail "usage: mc-duty-watch.sh watch [--program <p>] [--duty <id>] (mc-duty-watch.sh --help)"
}

case ${1:-} in
  --help | -h | help)
    help_text
    exit 0
    ;;
esac
[ "${1:-}" = watch ] || usage
shift
PROGRAM=${PLANWRIGHT_MC_PROGRAM:-}
DUTY=${PLANWRIGHT_MC_DUTY:-}
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case $1 in
    --program) PROGRAM=$2 ;;
    --duty) DUTY=$2 ;;
    *) usage ;;
  esac
  shift 2
done
[ -n "$PROGRAM" ] || mc_usage_fail "no program: pass --program or set PLANWRIGHT_MC_PROGRAM"
[ -n "$DUTY" ] || mc_usage_fail "no duty: pass --duty or set PLANWRIGHT_MC_DUTY"
mc_require_program "$PROGRAM"

# findings: the duty's findings, one line each, on stdout.
case $DUTY in
  self-audit)
    kind=self-audit-finding
    subject=self-audit
    out=$(/bin/bash "$script_dir/mc-audit.sh" run --program "$PROGRAM") || mc_fail "the self-audit failed"
    findings=$(printf '%s\n' "$out" | awk -F '\t' '$1 == "finding"')
    hint="run scripts/mc-audit.sh run --program $PROGRAM"
    ;;
  proposals)
    kind=proposal-repeat
    subject=proposals
    out=$(/bin/bash "$script_dir/mc-proposals.sh" scan --program "$PROGRAM") || mc_fail "the repeat scan failed"
    findings=$(printf '%s\n' "$out" | awk -F '\t' '$1 == "repeat"')
    hint="run scripts/mc-proposals.sh scan --program $PROGRAM"
    ;;
  undo-ledger)
    kind=undo-revert-stuck
    subject=undo-ledger
    out=$(mc_kb_entries "$PROGRAM" undo) || exit $?
    # An entry is <id> <time> <subject> <act> <target> ...: a revert's own
    # entries name the undo entry they act on as their target.
    findings=$(printf '%s\n' "$out" | awk -F '\t' '
      NF >= 5 && ($4 == "reverting" || $4 == "reverted" || $4 == "revert failed") { last[$5] = $4 }
      END { for (t in last) if (last[t] == "reverting") print t }
    ' | sort)
    hint="settle each with scripts/mc-kb.sh revert <id> --outcome reverted|failed --grounds <what you found>"
    ;;
  *)
    mc_usage_fail "the watcher does not serve duty '$(sanitize_printable "$DUTY")' (undo-ledger, self-audit, proposals)"
    ;;
esac

home=$(mc_program_home "$PROGRAM") || exit 1
files=$(/bin/bash "$script_dir/mc-duties.sh" get "$DUTY" files) || mc_fail "the directory of duty $DUTY does not resolve"
mc_valid_kebab "$files" || mc_fail "the directory of duty $DUTY is not a kebab name"
dir=$home/kb/$files
last=$dir/watch.last

n=0
sum=none
if [ -n "$findings" ]; then
  n=$(printf '%s\n' "$findings" | awk 'END { print NR }')
  sum=$(printf '%s\n' "$findings" | cksum | awk '{ print $1 "-" $2 }')
fi
printf 'checked\t%s\t%s\n' "$DUTY" "$n"

seen=none
[ ! -f "$last" ] || seen=$(head -n 1 "$last")
[ "$seen" != "$sum" ] || exit 0

if [ "$sum" = none ]; then
  printf 'cleared\t%s\n' "$DUTY"
else
  printf 'event\t%s\t%s\t%s\n' "$kind" "$subject" "$(printf '%s finding(s); %s' "$n" "$hint" | mc_clean_text | cut -c 1-400)"
fi
mkdir -p "$dir" || mc_fail "cannot create $dir"
STAGED=$(mktemp "$dir/.watch.last.XXXXXX") || mc_fail "cannot stage $last"
printf '%s\n' "$sum" >"$STAGED" || mc_fail "cannot stage $last"
mv -f "$STAGED" "$last" || mc_fail "cannot write $last"
STAGED=''
