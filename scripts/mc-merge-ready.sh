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
not a draft, MERGEABLE, with no open thread, no change requested and its
checks SUCCESS. Each is walked by scripts/mc-readiness.sh check, and is
ready only when the walk passes at the snapshot's own head (a head that
moved since is judged at the next snapshot). The verdict is kept in
<runtime>/merge-ready.tsv against the row's head, draft, mergeable, review
decision, open threads, checks and review count, and judged again once that
changes or the verdict is half an hour old, since evidence, labels, the body
and step records can change with no forge field moving. While the forge
holds reads for its rate limit (the snapshot's .hold), a kept verdict
stands and a candidate with none is unknown. The merge command is built
afresh on every read from the row and the repository's default merge method
(gh repo view's viewerDefaultMergeMethod, read once per repository per
judgment):
  gh pr merge <n> --repo <owner/name> --squash|--merge|--rebase --match-head-commit <sha>

Usage:
  mc-merge-ready.sh list --program <p> [--as-status] [--now <epoch>]
      one line per candidate that is ready or could not be judged:
        ready<TAB><owner/name>#<n><TAB><head><TAB><merge command>
        unknown<TAB><owner/name>#<n><TAB><why>
        unknown<TAB>-<TAB><why>          the snapshot itself: none taken
                                         yet, unreadable or stale (past
                                         twice its cadence), or the store
                                         not written
      with --as-status, each line as a scripts/mc-inbox.sh status line:
        decision<TAB>Ready to merge: <owner/name>#<n> at <head:12>, run: <command>
        decision<TAB>Could not tell whether <owner/name>#<n> is ready to merge: <why>
        decision<TAB>Could not tell which pull requests are ready to merge: <why>
      A program with no code-state snapshot source lists nothing.
  mc-merge-ready.sh count --program <p>
      the number of ready verdicts the last judgment kept, with no forge
      read (the panel's count); 0 before any judgment or with no
      code-state source; exit 1, printing nothing, when the last judgment
      left a pull request or the snapshot unknown
  mc-merge-ready.sh watch [--program <p>] [--now <epoch>]
      the readiness-check duty's merge watcher (also what a run with no
      arguments does under the runner): list, then one merge-ready event
      per ready head, subject <owner>:<name>:<n> (pr-<checksum> outside the
      subject grammar), its text the merge command, printing
        announced<TAB>merge-ready<TAB><subject>
      and each unknown on stderr. A head is announced once while the
      snapshot still shows the pull request at it; a stale snapshot, or
      none yet, raises nothing.

Exit codes: 0 done; 1 a failed read, check, store or event, or anything
left unknown; 2 usage; 3 the program is not configured.

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
# Rows: <owner/name>#<n> <key> ready|not-ready|unknown <epoch> <method|-> <why|->.
# A `state` line first says whether the snapshot could be judged at all.
store="$runtime/merge-ready.tsv"
RECHECK_AFTER=1800

if [ "$verb" = count ]; then
  [ -e "$store" ] || {
    printf '0\n'
    exit 0
  }
  awk -F '\t' '
    $1 == "state" && $2 != "ok" { bad = 1 }
    $3 == "unknown" { bad = 1 }
    $3 == "ready" { n++ }
    END { if (bad) exit 4; print n + 0 }' "$store"
  case $? in
    0) exit 0 ;;
    4) mc_fail "the last judgment left a pull request or the snapshot unknown" ;;
    *) mc_fail "the merge-ready store cannot be read" ;;
  esac
fi

# why <file>: the last line a failed command printed, cleaned and capped.
why() { tail -n 1 "$1" 2>/dev/null | mc_clean | tr '\t' ' ' | cut -c1-200; }

# method_of <owner/name>: MO_M, the repository's merge flag word, read once per
# judgment.
METHODS=""
method_of() {
  mo_m=$(printf '%s' "$METHODS" | S=$1 awk -F '\t' '$1 == ENVIRON["S"] { print $2; exit }')
  if [ -z "$mo_m" ]; then
    mo_m=$(gh repo view "$1" --json viewerDefaultMergeMethod --jq .viewerDefaultMergeMethod 2>"$errf")
    case $mo_m in
      SQUASH) mo_m=squash ;;
      MERGE) mo_m=merge ;;
      REBASE) mo_m=rebase ;;
      *) return 1 ;;
    esac
    METHODS="$METHODS$1	$mo_m
"
  fi
  MO_M=$mo_m
}

# scan: the candidates' lines on stdout, the store rewritten. Sets SCAN_RC
# (1 on anything unknown) and SCAN_STATE (ok, none, or why the snapshot
# could not be judged).
scan() {
  SCAN_RC=0
  SCAN_STATE=ok
  mc_code_state "$program"
  case $? in
    0) ;;
    1) SCAN_STATE="the source map of program $program does not resolve" ;;
    2) SCAN_STATE="the code-state snapshot cannot be read" ;;
    3) if [ -n "$MC_CS_SOURCE" ]; then SCAN_STATE="no code-state snapshot has been taken yet"; else SCAN_STATE=none; fi ;;
    *) SCAN_STATE="the code-state snapshot is stale" ;;
  esac
  case $SCAN_STATE in
    ok) ;;
    none)
      rm -f "$store" || SCAN_RC=1
      return 0
      ;;
    *)
      SCAN_RC=1
      printf 'unknown\t-\t%s\n' "$SCAN_STATE"
      printf 'state\tunjudged\n' | mc_write "$store" || printf 'unknown\t-\tthe merge-ready store cannot be written\n'
      return 0
      ;;
  esac
  held=0
  hold=$(cat "$runtime/snapshots/$MC_CS_SOURCE.hold" 2>/dev/null)
  if mc_valid_uint "$hold" && [ "$hold" -gt "$NOW" ]; then held=1; fi
  old=""
  if [ -e "$store" ]; then
    old=$(cat "$store") || old=""
  fi
  kept="state	ok
"
  candidates=$(printf '%s\n' "$MC_CS_ROWS" | awk -F '\t' '$1 == "pr" && $5 == "false" && $6 == "MERGEABLE" && $7 != "CHANGES_REQUESTED" && $8 == "0" && $9 == "SUCCESS" {
    k = $4; for (i = 5; i <= 10; i++) k = k "|" $i
    print $2 "\t" $3 "\t" $4 "\t" k }')
  while IFS='	' read -r c_slug c_n c_head c_key; do
    [ -n "$c_slug" ] || continue
    if ! mc_valid_slug "$c_slug" || ! mc_valid_uint "$c_n" || ! mc_valid_sha "$c_head"; then
      printf 'unknown\t%s\tthe snapshot row is malformed\n' "$(sanitize_printable "$c_slug#$c_n")"
      SCAN_RC=1
      continue
    fi
    c_pr="$c_slug#$c_n"
    verdict="" at="" method="" reason=""
    IFS='	' read -r _ _ verdict at method reason <<EOF
$(printf '%s\n' "$old" | P=$c_pr K=$c_key awk -F '\t' '$1 == ENVIRON["P"] && $2 == ENVIRON["K"] { print; exit }')
EOF
    case $verdict in
      ready | not-ready) mc_valid_uint "$at" || verdict="" ;;
      *) verdict="" ;;
    esac
    case $verdict:$method in
      ready:squash | ready:merge | ready:rebase | not-ready:*) ;;
      *) verdict="" ;;
    esac
    if [ -n "$verdict" ] && [ "$held" -eq 0 ] && [ $((NOW - at)) -ge "$RECHECK_AFTER" ]; then
      verdict=""
    fi
    if [ -z "$verdict" ]; then
      at=$NOW method=- reason=-
      if [ "$held" -eq 1 ]; then
        verdict=unknown reason="the forge is holding reads for its rate limit"
      else
        c_out=$(/bin/bash "$script_dir/mc-readiness.sh" check --program "$program" --repo "$c_slug" --pr "$c_n" 2>"$errf")
        case $? in
          0)
            c_walked=$(printf '%s\n' "$c_out" | awk -F '\t' 'NR == 1 && $1 == "ready" { print $2 }')
            if [ "$c_walked" != "$c_head" ]; then
              verdict=unknown reason="its head moved since the snapshot; judged again at the next one"
            elif method_of "$c_slug"; then
              method=$MO_M
              verdict=ready
            else
              verdict=unknown method=- reason="the merge method of $c_slug could not be read: $(why "$errf")"
            fi
            ;;
          4) verdict=not-ready ;;
          *) verdict=unknown reason="the readiness check could not run: $(why "$errf")" ;;
        esac
      fi
    fi
    kept="$kept$c_pr	$c_key	$verdict	$at	$method	$reason
"
    case $verdict in
      ready) printf 'ready\t%s\t%s\tgh pr merge %s --repo %s --%s --match-head-commit %s\n' "$c_pr" "$c_head" "$c_n" "$c_slug" "$method" "$c_head" ;;
      unknown)
        printf 'unknown\t%s\t%s\n' "$c_pr" "$reason"
        SCAN_RC=1
        ;;
    esac
  done <<EOF
$candidates
EOF
  if ! printf '%s' "$kept" | mc_write "$store"; then
    printf 'unknown\t-\tthe merge-ready store cannot be written\n'
    SCAN_RC=1
  fi
}

# The scan runs in this shell, its lines to a file, so its state survives.
out=$(mktemp "${TMPDIR:-/tmp}/mc-merge-ready.XXXXXX") || mc_fail "cannot create a temporary file"
errf=$(mktemp "${TMPDIR:-/tmp}/mc-merge-ready.XXXXXX") || {
  rm -f "$out"
  mc_fail "cannot create a temporary file"
}
trap 'rm -f "$out" "$errf"' EXIT
scan >"$out"

case $verb in
  list)
    if [ "$as_status" -eq 1 ]; then
      awk -F '\t' '
        $1 == "ready" { print "decision\tReady to merge: " $2 " at " substr($3, 1, 12) ", run: " $4 }
        $1 == "unknown" && $2 == "-" { print "decision\tCould not tell which pull requests are ready to merge: " $3 }
        $1 == "unknown" && $2 != "-" { print "decision\tCould not tell whether " $2 " is ready to merge: " $3 }' "$out"
    else
      cat "$out"
    fi
    exit "$SCAN_RC"
    ;;
  watch)
    awk -F '\t' '$1 == "unknown" { print "unknown: " $2 ": " $3 }' "$out" >&2
    case $SCAN_STATE in
      "the code-state snapshot is stale" | "no code-state snapshot has been taken yet" | none) exit 0 ;;
      ok) ;;
      *) exit 1 ;;
    esac
    seen="$runtime/merge-announced"
    rc=$SCAN_RC
    while IFS='	' read -r w_kind w_pr w_head w_command; do
      [ "$w_kind" = ready ] || continue
      mc_announce "$program" "$seen" "$w_pr	$w_head" merge-ready "$(mc_pr_subject "${w_pr%#*}" "${w_pr##*#}")" \
        "$w_pr is ready to merge: $w_command" || rc=1
    done <"$out"
    # A head stays announced while the snapshot shows the pull request at
    # it, so a failed check or a mergeability blip never pushes it twice.
    live=$(printf '%s\n' "$MC_CS_ROWS" | awk -F '\t' '$1 == "pr" { print $2 "#" $3 "\t" $4 }')
    mc_announce_prune "$seen" "$live" || rc=1
    exit "$rc"
    ;;
esac
