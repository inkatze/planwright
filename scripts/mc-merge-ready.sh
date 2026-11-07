#!/usr/bin/env bash
# mc-merge-ready.sh — the pull requests ready to merge: each one the
# readiness check passes, with the one checked merge command the operator
# runs, announced once per head and listed on every read until it merges or
# changes. Merging stays the operator's; nothing here merges.
#
# `mc-merge-ready.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-merge-ready
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
mc-merge-ready.sh — the pull requests ready to merge: each one the
readiness check passes, with the one checked merge command the operator
runs, announced once per head and listed on every read until it merges or
changes. Merging stays the operator's; nothing here merges.

A CANDIDATE is a pull request in the program's code-state snapshot that is
not a draft, MERGEABLE, with no open thread and its checks SUCCESS. Each is
walked by scripts/mc-readiness.sh check at its head; the verdict is kept in
<runtime>/merge-ready.tsv against the snapshot row, so an unchanged row is
not checked again (a not-ready verdict is re-checked once half an hour old,
since a step record can land with no forge change). A check that could not
run, or a merge method that could not be read, is kept nowhere and read
again next time. The merge command names the repository's default merge
method (gh repo view's viewerDefaultMergeMethod) and the head it was
checked at:
  gh pr merge <n> --repo <owner/name> --squash|--merge|--rebase --match-head-commit <sha>

Usage:
  mc-merge-ready.sh list --program <p> [--as-status] [--now <epoch>]
      one line per candidate that is ready or could not be judged:
        ready<TAB><owner/name>#<n><TAB><head><TAB><merge command>
        unknown<TAB><owner/name>#<n>|-<TAB><why>
      with --as-status, each ready one as a scripts/mc-inbox.sh status
      line instead:
        decision<TAB>Ready to merge: <owner/name>#<n> at <head:12>, run: <command>
      A stale snapshot (past twice its cadence) or one that cannot be read
      is one unknown line naming it.
  mc-merge-ready.sh count --program <p>
      the number of ready verdicts the last read kept, with no forge read
      (the panel's count)
  mc-merge-ready.sh watch [--program <p>] [--now <epoch>]
      the readiness-check duty's merge watcher (also what a run with no
      arguments does under the runner): list, then one merge-ready event
      per ready head, subject <owner>:<name>:<n> (pr-<checksum> outside the
      subject grammar), its text the merge command, printing
        announced<TAB>merge-ready<TAB><subject>
      announced again once a head clears and returns; a stale snapshot
      raises nothing.

Exit codes: 0 done; 1 a failed read, check, store or event (named on
stderr, or as an unknown line); 2 usage; 3 the program is not configured.

Portable bash 3.2 / BSD tooling; gh's built-in --jq does the JSON.
HELP
}

usage() {
  mc_usage_fail "usage: mc-merge-ready.sh list --program <p> [--as-status] [--now <epoch>] | count --program <p> | watch [--program <p>] [--now <epoch>]"
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
program=""
as_status=0
now_raw=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --now)
      [ $# -ge 2 ] || usage
      mc_valid_text "$2" || mc_usage_fail "$1 takes text with no control byte"
      case $1 in
        --program) program=$2 ;;
        --now) now_raw=$2 ;;
      esac
      shift 2
      ;;
    --as-status)
      as_status=1
      shift
      ;;
    *) usage ;;
  esac
done
case $verb in
  list) ;;
  count) [ "$as_status" -eq 0 ] && [ -z "$now_raw" ] || usage ;;
  watch)
    [ "$as_status" -eq 0 ] || usage
    [ -n "$program" ] || program=${PLANWRIGHT_MC_PROGRAM:-}
    ;;
  *) usage ;;
esac
[ -n "$program" ] || usage
mc_now_arg "$now_raw"
mc_require_program "$program"
runtime=$(mc_runtime "$program") || mc_fail "cannot resolve the runtime directory"
store="$runtime/merge-ready.tsv"

# A not-ready verdict this old is checked again.
RECHECK_AFTER=1800

if [ "$verb" = count ]; then
  if [ -e "$store" ]; then
    [ -r "$store" ] || mc_fail "the merge-ready store cannot be read"
    awk -F '\t' '$3 == "ready" { n++ } END { print n + 0 }' "$store"
  else
    printf '0\n'
  fi
  exit 0
fi

# scan: print ready/unknown lines over the snapshot's candidates and rewrite
# the store with the verdicts still live. Sets SCAN_RC (0, or 1 on any
# unknown) and SCAN_STATE (none, stale or ok).
scan() {
  SCAN_RC=0
  SCAN_STATE=none
  sources=$(/bin/bash "$script_dir/mc-program.sh" get "$program" sources) || mc_fail "the source map of program $program does not resolve"
  source=$(printf '%s\n' "$sources" | awk -F '\t' '$1 == "code-state" && $3 == "snapshot" { print $2 }')
  [ -n "$source" ] || return 0
  snap=$(/bin/bash "$script_dir/mc-snapshot.sh" read --program "$program" "$source")
  case $? in
    0) ;;
    3) return 0 ;;
    *)
      SCAN_STATE=stale
      return 0
      ;;
  esac
  if ! printf '%s\n' "$snap" | head -n 1 | awk -F '\t' '$5 == "age" && $7 == "cadence" { ok = ($6 + 0 <= 2 * ($8 + 0)) } END { exit !ok }'; then
    SCAN_STATE=stale
    return 0
  fi
  SCAN_STATE=ok
  candidates=$(printf '%s\n' "$snap" | awk -F '\t' '$1 == "pr" && $5 == "false" && $6 == "MERGEABLE" && $8 == "0" && $9 == "SUCCESS" {
    k = $4; for (i = 5; i <= 12; i++) k = k "|" $i
    print $2 "\t" $3 "\t" $4 "\t" k }')
  old=""
  if [ -e "$store" ]; then
    old=$(cat "$store") || mc_fail "the merge-ready store cannot be read"
  fi
  kept=""
  while IFS='	' read -r c_slug c_n c_head c_key; do
    [ -n "$c_slug" ] || continue
    c_pr="$c_slug#$c_n"
    if ! mc_valid_slug "$c_slug" || ! mc_valid_uint "$c_n" || ! mc_valid_sha "$c_head"; then
      printf 'unknown\t%s\tthe snapshot row is malformed\n' "$(sanitize_printable "$c_pr")"
      SCAN_RC=1
      continue
    fi
    prior=$(printf '%s\n' "$old" | P=$c_pr K=$c_key awk -F '\t' '$1 == ENVIRON["P"] && $2 == ENVIRON["K"] { print; exit }')
    verdict=$(printf '%s' "$prior" | cut -f3)
    at=$(printf '%s' "$prior" | cut -f4)
    command=$(printf '%s' "$prior" | cut -f5)
    if [ "$verdict" = not-ready ] && mc_valid_uint "$at" && [ $((NOW - at)) -ge "$RECHECK_AFTER" ]; then
      verdict=""
    fi
    case $verdict in
      ready | not-ready) ;;
      *)
        /bin/bash "$script_dir/mc-readiness.sh" check --program "$program" --repo "$c_slug" --pr "$c_n" >/dev/null 2>&1
        c_rc=$?
        case $c_rc in
          0) verdict=ready ;;
          4) verdict=not-ready ;;
          *)
            printf 'unknown\t%s\tthe readiness check could not run (exit %s)\n' "$c_pr" "$c_rc"
            SCAN_RC=1
            continue
            ;;
        esac
        at=$NOW
        command=-
        if [ "$verdict" = ready ]; then
          method=$(gh repo view "$c_slug" --json viewerDefaultMergeMethod --jq .viewerDefaultMergeMethod 2>/dev/null)
          case $method in
            SQUASH) flag=--squash ;;
            MERGE) flag=--merge ;;
            REBASE) flag=--rebase ;;
            *)
              printf 'unknown\t%s\tthe merge method of %s could not be read\n' "$c_pr" "$c_slug"
              SCAN_RC=1
              continue
              ;;
          esac
          command="gh pr merge $c_n --repo $c_slug $flag --match-head-commit $c_head"
        fi
        ;;
    esac
    kept="$kept$c_pr	$c_key	$verdict	$at	$command
"
    [ "$verdict" = ready ] && printf 'ready\t%s\t%s\t%s\n' "$c_pr" "$c_head" "$command"
  done <<EOF
$candidates
EOF
  { printf '%s' "$kept"; } | mc_write "$store" || mc_fail "the merge-ready store cannot be written"
}

# The scan runs in this shell, its lines to a file, so its state survives.
out=$(mktemp "${TMPDIR:-/tmp}/mc-merge-ready.XXXXXX") || mc_fail "cannot create a temporary file"
trap 'rm -f "$out"' EXIT
scan >"$out"

case $verb in
  list)
    if [ "$SCAN_STATE" = stale ]; then
      printf 'unknown\t-\tthe code-state snapshot is stale\n'
      exit 1
    fi
    if [ "$as_status" -eq 1 ]; then
      awk -F '\t' '$1 == "ready" { print "decision\tReady to merge: " $2 " at " substr($3, 1, 12) ", run: " $4 }' "$out"
    else
      cat "$out"
    fi
    exit "$SCAN_RC"
    ;;
  watch)
    # A stale snapshot may show a head long gone; wait for a fresh one.
    [ "$SCAN_STATE" = ok ] || exit 0
    awk -F '\t' '$1 == "unknown" { print "unknown: " $2 ": " $3 }' "$out" >&2
    seen="$runtime/merge-announced"
    rc=$SCAN_RC
    live=""
    while IFS='	' read -r w_kind w_pr w_head w_command; do
      [ "$w_kind" = ready ] || continue
      live="$live$w_pr	$w_head
"
      w_slug=${w_pr%#*}
      w_subject="${w_slug%%/*}:${w_slug#*/}:${w_pr##*#}"
      mc_valid_handle "$w_subject" || w_subject=$(mc_subject pr "$w_pr")
      mc_announce "$program" "$seen" "$w_pr	$w_head" merge-ready "$w_subject" \
        "$w_pr is ready to merge: $w_command" || rc=1
    done <"$out"
    mc_announce_prune "$seen" "$live" || rc=1
    exit "$rc"
    ;;
esac
