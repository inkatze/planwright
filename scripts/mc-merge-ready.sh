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
not a draft, MERGEABLE, with no open thread, its checks SUCCESS and its
review decision neither CHANGES_REQUESTED nor REVIEW_REQUIRED. Each is
walked as scripts/mc-readiness.sh check walks it (collect, then walk), and
is ready only when the walk passes at the snapshot's own head (a head that
moved since is judged again once the snapshot catches up) and the
program's merge conditions (scripts/mc-gates.sh resolve, for the
repository, labels and paths collected) recommend it: `recommend approved`
waits for an APPROVED review decision. The verdict is kept in <runtime>/merge-ready.tsv against
the row's head, draft, mergeable, review decision, open threads, checks and
review count, and judged again once that changes or the verdict is half an
hour old, since evidence, labels, the body and step records can change with
no forge field moving. While the forge holds reads for its rate limit (the
snapshot's .hold), a kept verdict stands and a candidate with none is
unknown. The merge command is built afresh on every read:
  gh pr merge <n> --repo <owner/name> --squash|--merge|--rebase --match-head-commit <sha>
its method the merge conditions' `method`, else the repository's default
(gh repo view's viewerDefaultMergeMethod, read once per repository per
judgment).

Usage:
  mc-merge-ready.sh list --program <p> [--as-status] [--now <epoch>]
      one line per candidate that is ready or could not be judged:
        ready<TAB><owner/name>#<n><TAB><head><TAB><merge command>
        unknown<TAB><owner/name>#<n><TAB><why>
        unfinished<TAB><owner/name>#<n><TAB><head><TAB><checks>
                                         a pull request already marked ready
                                         (not a draft, its checks not all
                                         SUCCESS) whose head still has a
                                         check queued, pending or in
                                         progress, named; a failed read of
                                         one is skipped, and a check that
                                         finished red is not unfinished
        unknown<TAB>-<TAB><why>          the snapshot or the store: the
                                         source map unresolved, no
                                         snapshot taken yet, one
                                         unreadable or stale (past twice
                                         its cadence), a malformed row,
                                         or the store not written
      with --as-status, each line as a scripts/mc-inbox.sh status line:
        decision<TAB>Ready to merge: <owner/name>#<n> at <head:12>, run: <command>
        decision<TAB>Marked ready with unfinished checks: <owner/name>#<n> at <head:12>: <checks>
        decision<TAB>Could not tell whether <owner/name>#<n> is ready to merge: <why>
        decision<TAB>Could not tell which pull requests are ready to merge: <why>
      A program with no code-state snapshot source lists nothing. --now
      sets the clock for the snapshot's age, the verdicts' and the hold.
  mc-merge-ready.sh count --program <p>
      <n><TAB>all|partial: the ready verdicts the last judgment kept, with
      no forge read (the panel's count); partial when that judgment left a
      pull request or the snapshot unknown, or is over an hour old or
      stamped later than now; `0 all`
      before any judgment or with no code-state source
  mc-merge-ready.sh commands --program <p> [--now <epoch>]
      ready<TAB><owner/name>#<n><TAB><merge command> for each ready verdict the
      last judgment kept, with no forge read (the panel's rows): only while
      that judgment wrote the store as ok less than an hour ago and the
      program has a code-state snapshot source, else nothing. The command is
      the one list prints, built from the head the verdict was judged at.
  mc-merge-ready.sh watch [--program <p>] [--now <epoch>]
      the readiness-check duty's merge watcher (also what a run with no
      arguments does under the runner): list, then one merge-ready event
      per ready head, subject <owner>:<name>:<n> (pr-<checksum> outside the
      subject grammar), its text the merge command, printing
        announced<TAB>merge-ready<TAB><subject>
      and each unknown on stderr. The same event, its text naming this
      program as the judge, goes to every other configured program whose
      repositories include the pull request's (by origin remote) and whose
      duties leave out readiness-check, such as a hub over several
      programs, printing
        forwarded<TAB><program><TAB>merge-ready<TAB><subject>
      A head is announced, and forwarded, once while the
      snapshot still shows the pull request at it. A stale snapshot, or
      none yet, raises nothing and is no failure; any other unknown fails
      the run.

Exit codes: 0 done; 1 a failed read, check, store or event, or anything
left unknown (watch: but a stale snapshot or none yet); 2 usage; 3 the
program is not configured.

Portable bash 3.2 / BSD tooling; gh's built-in --jq does the JSON.
HELP
}

usage() {
  mc_usage_fail "usage: mc-merge-ready.sh list --program <p> [--as-status] [--now <epoch>] | count --program <p> | commands --program <p> [--now <epoch>] | watch [--program <p>] [--now <epoch>]"
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
  commands) [ "$as_status" -eq 0 ] || usage ;;
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
# A `state<TAB><token><TAB><epoch>` line, then one row per candidate:
# <owner/name>#<n> <key> ready|not-ready|moved|unknown <epoch> <method|-> <why|->.
store="$runtime/merge-ready.tsv"
RECHECK_AFTER=1800
COUNT_FRESH=3600
MOVED_WHY="its head moved since the snapshot; judged again once the snapshot catches up"

if [ "$verb" = count ]; then
  cn_map=$(/bin/bash "$script_dir/mc-program.sh" get "$program" sources) || mc_fail "the source map of program $program does not resolve"
  # A store left from before the source was removed counts nothing.
  if ! printf '%s\n' "$cn_map" | awk -F '\t' '$1 == "code-state" && $3 == "snapshot" { f = 1 } END { exit !f }'; then
    printf '0\tall\n'
    exit 0
  fi
  [ -e "$store" ] || {
    printf '0\tall\n'
    exit 0
  }
  [ -f "$store" ] && [ -r "$store" ] || mc_fail "the merge-ready store cannot be read"
  N=$NOW F=$COUNT_FRESH awk -F '\t' '
    $1 == "state" { s = 1; age = ENVIRON["N"] - $3; if ($2 != "ok" || $3 !~ /^[0-9]+$/ || age < 0 || age > ENVIRON["F"] + 0) part = 1 }
    $3 == "unknown" || $3 == "moved" { part = 1 }
    $3 == "ready" { n++ }
    END { if (!s) part = 1; print (n + 0) "\t" (part ? "partial" : "all") }' "$store" \
    || mc_fail "the merge-ready store cannot be read"
  exit 0
fi

if [ "$verb" = commands ]; then
  cm_map=$(/bin/bash "$script_dir/mc-program.sh" get "$program" sources) || mc_fail "the source map of program $program does not resolve"
  printf '%s\n' "$cm_map" | awk -F '\t' '$1 == "code-state" && $3 == "snapshot" { f = 1 } END { exit !f }' || exit 0
  [ -e "$store" ] || exit 0
  [ -f "$store" ] && [ -r "$store" ] && [ ! -L "$store" ] || mc_fail "the merge-ready store cannot be read"
  # <slug> <number> <method> <head> per ready row of a store that is ok and fresh.
  cm_rows=$(N=$NOW F=$COUNT_FRESH awk -F '\t' '
    $1 == "state" { ok = ($2 == "ok" && $3 ~ /^[0-9]+$/ && ENVIRON["N"] - $3 >= 0 && ENVIRON["N"] - $3 <= ENVIRON["F"] + 0) }
    $3 == "ready" && $1 ~ /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+#[0-9]+$/ && $5 ~ /^(squash|merge|rebase)$/ {
      split($2, k, "|")
      if (k[1] !~ /^[0-9a-f]{40}$/) next
      at = index($1, "#")
      rows[++r] = substr($1, 1, at - 1) "\t" substr($1, at + 1) "\t" $5 "\t" k[1]
    }
    END { if (ok) for (i = 1; i <= r; i++) print rows[i] }' "$store") || mc_fail "the merge-ready store cannot be read"
  while IFS='	' read -r c_slug c_n c_method c_head; do
    [ -n "$c_slug" ] || continue
    printf 'ready\t%s#%s\tgh pr merge %s --repo %s --%s --match-head-commit %s\n' "$c_slug" "$c_n" "$c_n" "$c_slug" "$c_method" "$c_head"
  done <<EOF
$cm_rows
EOF
  exit 0
fi

# why <file>: the last line a failed command printed, cleaned and capped.
why() {
  w_line=$(tail -n 1 "$1" 2>/dev/null | mc_clean | tr '\t' ' ' | cut -c1-200)
  printf '%s\n' "${w_line:-no error text}"
}

# method_of <owner/name>: MO_M, the repository's default merge method, read
# once per judgment.
METHODS=""
method_of() {
  MO_M=$(printf '%s' "$METHODS" | S=$1 awk -F '\t' '$1 == ENVIRON["S"] { print $2; exit }')
  [ -z "$MO_M" ] || return 0
  MO_M=$(gh repo view "$1" --json viewerDefaultMergeMethod --jq .viewerDefaultMergeMethod 2>"$errf")
  case $MO_M in
    SQUASH) MO_M=squash ;;
    MERGE) MO_M=merge ;;
    REBASE) MO_M=rebase ;;
    *)
      [ -s "$errf" ] || printf 'gh answered %s\n' "${MO_M:-nothing}" >"$errf"
      return 1
      ;;
  esac
  METHODS="$METHODS$1	$MO_M
"
}

# covering <owner/name>: CV_PROGRAMS, the other configured programs ($others)
# whose repositories include <owner/name> and whose duties leave out the
# readiness check, one per line: a hub over several programs judges none
# itself, so it hears of each from the program that does. Read once per
# repository per run; one whose duties cannot be read is told too, since a
# second notice costs less than a missed one.
covering() {
  CV_PROGRAMS=$(printf '%s' "$COVER" | S=$1 awk -F '\t' '$1 == ENVIRON["S"] && $2 != "-" { print $2 }')
  if printf '%s' "$COVER" | S=$1 awk -F '\t' '$1 == ENVIRON["S"] { f = 1; exit } END { exit !f }'; then
    return 0
  fi
  cv_rc=0
  COVER="$COVER$1	-
"
  while IFS= read -r cv_q; do
    [ -n "$cv_q" ] || continue
    if cv_duties=$(/bin/bash "$script_dir/mc-program.sh" get "$cv_q" duties </dev/null 2>/dev/null); then
      case "
$cv_duties
" in
        *"
readiness-check
"*) continue ;;
      esac
    fi
    cv_repos=$(mc_slug_repos "$cv_q" "$1" </dev/null) || {
      printf 'unknown: -: the repositories of program %s do not resolve\n' "$cv_q" >&2
      cv_rc=1
      continue
    }
    [ -n "$cv_repos" ] || continue
    COVER="$COVER$1	$cv_q
"
    CV_PROGRAMS="$CV_PROGRAMS$cv_q
"
  done <<EOF
$others
EOF
  return "$cv_rc"
}

# judge <owner/name> <n> <head> <review decision>: J_VERDICT (ready,
# not-ready, moved or unknown), J_METHOD and J_WHY for one candidate.
judge() {
  J_VERDICT=unknown J_METHOD=- J_WHY=-
  /bin/bash "$script_dir/mc-readiness.sh" collect --program "$program" --repo "$1" --pr "$2" --out "$evf" >/dev/null 2>"$errf" || {
    J_WHY="its readiness evidence could not be collected: $(why "$errf")"
    return 0
  }
  if [ "$(awk -F '\t' '$1 == "head" { print $2; exit }' "$evf")" != "$3" ]; then
    J_VERDICT=moved J_WHY=$MOVED_WHY
    return 0
  fi
  /bin/bash "$script_dir/mc-readiness.sh" walk --program "$program" --evidence "$evf" >/dev/null 2>"$errf"
  case $? in
    0) ;;
    4)
      J_VERDICT=not-ready
      return 0
      ;;
    *)
      J_WHY="the readiness walk could not run: $(why "$errf")"
      return 0
      ;;
  esac
  set -- "$1" "$2" "$3" "$4" --repo "$1"
  while IFS='	' read -r e_kind e_value _; do
    case $e_kind in
      label) set -- "$@" --label "$e_value" ;;
      path) set -- "$@" --path "$e_value" ;;
    esac
  done <"$evf"
  j_gates=$(shift 4 && /bin/bash "$script_dir/mc-gates.sh" resolve --program "$program" "$@" 2>"$errf") || {
    J_WHY="its merge conditions could not be resolved: $(why "$errf")"
    return 0
  }
  j_rec=$(printf '%s\n' "$j_gates" | awk -F '\t' '$1 == "merge" && $2 == "recommend" { print $3; exit }')
  j_method=$(printf '%s\n' "$j_gates" | awk -F '\t' '$1 == "merge" && $2 == "method" { print $3; exit }')
  if [ "$j_rec" = approved ] && [ "$4" != APPROVED ]; then
    J_VERDICT=not-ready
    return 0
  fi
  case $j_method in
    merge | squash | rebase) J_METHOD=$j_method ;;
    *)
      if method_of "$1"; then
        J_METHOD=$MO_M
      else
        J_WHY="the merge method of $1 could not be read: $(why "$errf")"
        return 0
      fi
      ;;
  esac
  J_VERDICT=ready
}

# scan: the candidates' lines on stdout, the store rewritten. Sets SCAN_RC
# (1 on anything unknown) and SCAN_STATE (ok, none, nomap, nosnap,
# unreadable or stale).
scan() {
  SCAN_RC=0
  # Only a given --now pins the snapshot's clock: pinned to this run's start,
  # a refresh landing meanwhile would read as taken in the future.
  mc_code_state "$program" "$now_raw"
  case $? in
    0) SCAN_STATE=ok ;;
    1) SCAN_STATE=nomap ;;
    2) SCAN_STATE=unreadable ;;
    3) if [ -n "$MC_CS_SOURCE" ]; then SCAN_STATE=nosnap; else SCAN_STATE=none; fi ;;
    *) SCAN_STATE=stale ;;
  esac
  old=""
  if [ -e "$store" ]; then
    old=$(awk -F '\t' '$1 != "state"' "$store") || old=""
  fi
  case $SCAN_STATE in
    ok) ;;
    none)
      rm -f "$store" || SCAN_RC=1
      return 0
      ;;
    *)
      SCAN_RC=1
      case $SCAN_STATE in
        nomap) printf 'unknown\t-\tthe source map of program %s does not resolve\n' "$program" ;;
        nosnap) printf 'unknown\t-\tno code-state snapshot has been taken yet\n' ;;
        unreadable) printf 'unknown\t-\tthe code-state snapshot cannot be read\n' ;;
        stale) printf 'unknown\t-\tthe code-state snapshot is stale\n' ;;
      esac
      # The verdicts stay for the next fresh snapshot; the state marks them
      # unconfirmed meanwhile.
      {
        printf 'state\t%s\t%s\n' "$SCAN_STATE" "$NOW"
        [ -z "$old" ] || printf '%s\n' "$old"
      } | mc_write "$store" \
        || printf 'unknown\t-\tthe merge-ready store cannot be written\n'
      return 0
      ;;
  esac
  held=0 malformed=0
  hold=$(head -n 1 "$runtime/snapshots/$MC_CS_SOURCE.hold" 2>/dev/null)
  if mc_valid_uint "$hold" && [ "$hold" -gt "$NOW" ]; then held=1; fi
  kept=""
  candidates=$(printf '%s\n' "$MC_CS_ROWS" | awk -F '\t' '$1 == "pr" && $5 == "false" && $6 == "MERGEABLE" && $7 != "CHANGES_REQUESTED" && $7 != "REVIEW_REQUIRED" && $8 == "0" && $9 == "SUCCESS" {
    k = $4; for (i = 5; i <= 10; i++) k = k "|" $i
    print $2 "\t" $3 "\t" $4 "\t" $7 "\t" k }')
  while IFS='	' read -r c_slug c_n c_head c_decision c_key; do
    [ -n "$c_slug" ] || continue
    if ! mc_valid_slug "$c_slug" || ! mc_valid_uint "$c_n" || ! mc_valid_sha "$c_head"; then
      [ "$malformed" -eq 1 ] || printf 'unknown\t-\ta snapshot row is malformed\n'
      malformed=1 SCAN_RC=1
      continue
    fi
    c_pr="$c_slug#$c_n"
    IFS='	' read -r _ _ verdict at method reason <<EOF
$(printf '%s\n' "$old" | P=$c_pr K=$c_key awk -F '\t' '$1 == ENVIRON["P"] && $2 == ENVIRON["K"] { print; exit }')
EOF
    case $verdict:$method in
      ready:squash | ready:merge | ready:rebase | not-ready:- | moved:-) ;;
      *) verdict="" ;;
    esac
    if [ -n "$verdict" ]; then
      if ! mc_valid_uint "$at" || [ "$at" -gt "$NOW" ]; then
        verdict=""
      elif [ "$held" -eq 0 ] && [ $((NOW - at)) -ge "$RECHECK_AFTER" ]; then
        verdict=""
      fi
    fi
    if [ -z "$verdict" ]; then
      at=$NOW
      if [ "$held" -eq 1 ]; then
        verdict=unknown method=- reason="the forge is holding reads for its rate limit"
      else
        judge "$c_slug" "$c_n" "$c_head" "$c_decision"
        verdict=$J_VERDICT method=$J_METHOD reason=$J_WHY
      fi
    fi
    [ "$verdict" != moved ] || reason=$MOVED_WHY
    kept="$kept$c_pr	$c_key	$verdict	$at	$method	$reason
"
    case $verdict in
      ready) printf 'ready\t%s\t%s\tgh pr merge %s --repo %s --%s --match-head-commit %s\n' "$c_pr" "$c_head" "$c_n" "$c_slug" "$method" "$c_head" ;;
      unknown | moved)
        printf 'unknown\t%s\t%s\n' "$c_pr" "$reason"
        SCAN_RC=1
        ;;
    esac
  done <<EOF
$candidates
EOF
  # A pull request already marked ready whose head still has a check queued,
  # pending or running slipped through a flip that waits for every check to
  # finish; say so each read, with the checks. Advisory: a read that fails
  # here is skipped, never a failure of the scan.
  if [ "$held" -eq 0 ]; then
    unfinished_rows=$(printf '%s\n' "$MC_CS_ROWS" | awk -F '\t' '$1 == "pr" && $5 == "false" && $9 != "SUCCESS" { print $2 "\t" $3 "\t" $4 }')
    while IFS='	' read -r u_slug u_n u_head; do
      [ -n "$u_slug" ] || continue
      if ! { mc_valid_slug "$u_slug" && mc_valid_uint "$u_n" && mc_valid_sha "$u_head"; }; then continue; fi
      /bin/bash "$script_dir/mc-readiness.sh" collect --program "$program" --repo "$u_slug" --pr "$u_n" --out "$uevf" >/dev/null 2>"$errf" || continue
      [ "$(awk -F '\t' '$1 == "head" { print $2; exit }' "$uevf")" = "$u_head" ] || continue
      u_out=$(/bin/bash "$script_dir/mc-readiness.sh" unfinished --evidence "$uevf" 2>"$errf") && continue
      u_names=$(printf '%s\n' "$u_out" | awk -F '\t' '$1 == "fail" && $2 == "check" { printf "%s%s", (n++ ? ", " : ""), $3 }')
      [ -z "$u_names" ] || printf 'unfinished\t%s#%s\t%s\t%s\n' "$u_slug" "$u_n" "$u_head" "$u_names"
    done <<EOF
$unfinished_rows
EOF
  fi
  # A malformed row has no verdict to keep, so the state marks the count partial.
  state=ok
  [ "$malformed" -eq 0 ] || state=malformed
  if ! printf 'state\t%s\t%s\n%s' "$state" "$NOW" "$kept" | mc_write "$store"; then
    printf 'unknown\t-\tthe merge-ready store cannot be written\n'
    SCAN_RC=1
  fi
}

# The scan runs in this shell, its lines to a file, so its state survives.
out=$(mktemp "${TMPDIR:-/tmp}/mc-merge-ready.XXXXXX") || mc_fail "cannot create a temporary file"
errf=$(mktemp "${TMPDIR:-/tmp}/mc-merge-ready.XXXXXX") || errf=""
evf=$(mktemp "${TMPDIR:-/tmp}/mc-merge-ready.XXXXXX") || evf=""
uevd=$(mktemp -d "${TMPDIR:-/tmp}/mc-merge-ready.XXXXXX") || uevd=""
uevf="$uevd/evidence.unf"
trap 'rm -f "$out" "$errf" "$evf"; [ -z "$uevd" ] || rm -rf "$uevd"' EXIT
[ -n "$errf" ] && [ -n "$evf" ] && [ -n "$uevd" ] || mc_fail "cannot create a temporary file"
scan >"$out"

case $verb in
  list)
    if [ "$as_status" -eq 1 ]; then
      awk -F '\t' '
        $1 == "ready" { print "decision\tReady to merge: " $2 " at " substr($3, 1, 12) ", run: " $4 }
        $1 == "unfinished" { print "decision\tMarked ready with unfinished checks: " $2 " at " substr($3, 1, 12) ": " $4 }
        $1 == "unknown" && $2 == "-" { print "decision\tCould not tell which pull requests are ready to merge: " $3 }
        $1 == "unknown" && $2 != "-" { print "decision\tCould not tell whether " $2 " is ready to merge: " $3 }' "$out"
    else
      cat "$out"
    fi
    exit "$SCAN_RC"
    ;;
  watch)
    case $SCAN_STATE in
      none | nosnap | stale) exit 0 ;;
    esac
    awk -F '\t' '$1 == "unknown" { print "unknown: " $2 ": " $3 }' "$out" >&2
    [ "$SCAN_STATE" = ok ] || exit 1
    seen="$runtime/merge-announced"
    forwarded="$runtime/merge-forwarded"
    rc=$SCAN_RC
    listed=1
    if others=$(/bin/bash "$script_dir/mc-program.sh" list 2>/dev/null); then
      others=$(printf '%s\n' "$others" | P=$program awk '$0 != "" && $0 != ENVIRON["P"]')
    else
      printf 'unknown: -: the other configured programs cannot be listed\n' >&2
      others="" rc=1 listed=0
    fi
    COVER=""
    while IFS='	' read -r w_kind w_pr w_head w_command; do
      [ "$w_kind" = ready ] || continue
      w_subject=$(mc_pr_subject "${w_pr%#*}" "${w_pr##*#}")
      mc_announce "$program" "$seen" "$w_pr	$w_head" merge-ready "$w_subject" \
        "$w_pr is ready to merge: $w_command" || rc=1
      covering "${w_pr%#*}" || rc=1
      while IFS= read -r w_q; do
        [ -n "$w_q" ] || continue
        if w_fw=$(mc_announce "$w_q" "$forwarded" "$w_q	$w_pr	$w_head" merge-ready "$w_subject" \
          "$w_pr is ready to merge: $w_command (judged by program $program)"); then
          [ -z "$w_fw" ] || printf 'forwarded\t%s\t%s\n' "$w_q" "${w_fw#announced	}"
        else
          printf 'unknown: %s: the merge-ready event for program %s could not be raised\n' "$w_pr" "$w_q" >&2
          rc=1
        fi
      done <<EOF
$CV_PROGRAMS
EOF
    done <"$out"
    # A head stays announced while the snapshot shows the pull request at
    # it, so a failed check or a mergeability blip never pushes it twice.
    live=$(printf '%s\n' "$MC_CS_ROWS" | awk -F '\t' '$1 == "pr" { print $2 "#" $3 "\t" $4 }')
    mc_announce_prune "$seen" "$live" || rc=1
    # Unlisted programs would prune every forward, so each is sent again.
    if [ "$listed" -eq 1 ]; then
      live_fw=$(printf '%s\n' "$live" | O=$others awk 'BEGIN { n = split(ENVIRON["O"], o, "\n") }
        $0 != "" { for (i = 1; i <= n; i++) if (o[i] != "") print o[i] "\t" $0 }')
      mc_announce_prune "$forwarded" "$live_fw" || rc=1
    fi
    exit "$rc"
    ;;
esac
