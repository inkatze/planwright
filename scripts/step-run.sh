#!/usr/bin/env bash
# step-run.sh — host one custom-steps command step for /execute-task's runner:
# the reuse check, the pool slot, the context, the run, and its record; plus
# the per-run state the re-fire pass and resume continuation read.
# doctrine/custom-steps.md is the normative home of every rule applied here
# (*Hosting*, *Expensive checks*, *Resume continuation*, *Records*); this
# header pins the mechanics it delegates. Skill and prompt steps stay with the
# runner session; scripts/step-record.sh owns every record read and write,
# scripts/step-pool.sh every slot, scripts/resolve-steps.sh every resolution
# and context rendering.
#
# Usage:
#   step-run.sh [--worktree <dir>] resolve --run <id> <point>...
#       --attended|--unattended
#   step-run.sh [--worktree <dir>] resume --run <id> --from <run>:<point>
#   step-run.sh [--worktree <dir>] refire --run <id>
#   step-run.sh [--worktree <dir>] command --run <id> --point <point>
#       --step <id> [--refire-of <point>] [--backend <name>] [--session <id>]
#   step-run.sh [--worktree <dir>] begin --run <id> --point <point>
#       --step <id> --owner <pid> [--refire-of <point>] [--backend <name>]
#       [--session <id>]
#   step-run.sh [--worktree <dir>] end --run <id> --point <point>
#       --step <id> --exit <code> [--timed-out <seconds>] [--output <file>]
#       [--session <id>]
#
#   --worktree  the unit's worktree; default the enclosing git top level.
#               Every command runs there.
#   --run       a run id step-record.sh issued.
#   --backend   the record's backend name (default `runner`).
#   --session   the session id the record carries: the unit session's for a
#               session-hosted step, so a later `continue` step can attach.
#   --owner     the slot owner, the unit session's long-lived process (the
#               shell tool's parent, `$PPID`), never a short-lived shell.
#
# resolve   run resolve-steps.sh over the points with --explain and the
#           attendance flag, pass its stdout, stderr, and exit through, and
#           keep each point's rows as this run's runner state (a later
#           resolution of the same point in the run replaces them, and one
#           that fails with no rows removes them). The command, begin, end,
#           and refire verbs read a step's row from there; a re-fire's from
#           the first run of the resume chain.
#           Its own refusals exit 2, a state write that fails 4.
# resume    a resume of the run interrupted at <point>: <run> six digits and
#           <point> an in-run point, both checked before any record is read
#           (exit 2). Records the run's resume link (its chain's first run is
#           the first run of <run>'s chain), then writes one `resume` skip at
#           <point> for each record `step-record.sh lookup resume` prints on
#           the head read once now, copying its heads, target, kind, hosting,
#           backend, session, fingerprint, args digest, and refire-of, and
#           prints `skipped<TAB><step><TAB><record><TAB><hosting><TAB>
#           <session>` per skip, in order: the runner skips that leading
#           prefix of the point's list, then of its re-fire pass.
# refire    the re-fire plan: nothing when no post-pr step record of the run
#           moved the head (step-record.sh heads); otherwise, from the
#           pre-ci then pre-pr rows of the run's chain's first run (a list
#           that run never resolved warns and plans nothing), each
#           distinct step id whose first declaring row reads `run` with
#           refire `post-pr` and that no post-pr record of this run already
#           re-fires, as `refire<TAB><step><TAB><declaring point><TAB>
#           <hosting>`. The runner hosts each at post-pr with --refire-of.
# command   host an isolated command step as the runner subprocess, this
#           process the slot owner: a step declaring paths whose fingerprint
#           matches a passing record (step-record.sh lookup reuse) records a
#           `reuse` skip instead; a pooled step takes its slot (the wait
#           outside the timeout), runs the location and args as argv with
#           the PLANWRIGHT_STEP_* context and the hold mark in its
#           environment, stdin /dev/null, output captured under the cache,
#           in its own process group, and writes the record. At its timeout,
#           or on a HUP, INT, or TERM to this script (forwarded to the group
#           and held), the group is ended (TERM, KILL after ten seconds) and
#           the slot released only once it is gone; a signal then exits
#           128+n after the record. A refused context value, location, or
#           args word (resolve-steps.sh --line's checks) fails the step
#           without running it. A re-fire must name a step whose row
#           declares refire post-pr that this run has not re-fired. In its
#           own group the check has no terminal: one that reads /dev/tty
#           under a controlling terminal stops, as any background job does.
# begin     the same up to the run, for a session-hosted (in-session or
#           continue) command step whose slot the unit session's process
#           --owner holds: prints `run<TAB><line>`, the line
#           resolve-steps.sh --line renders (hold mark included when a slot
#           was taken) for the session's shell tool, and keeps the pending
#           state (slot, re-fire, session) for `end`. A `skipped` or `failed`
#           line instead needs no `end`; a second begin before `end` is
#           refused. Any failure after the take releases the slot.
# end       release the slot begin took (by its slot number) and write the
#           record from the session's exit code (--timed-out names a timeout
#           the shell tool enforced; --output a file of the line's output,
#           appended to the cache copy); the pending state goes only once
#           the record is written, and a retry after a failed write releases
#           nothing again. The re-fire, backend, owner, and pool come from
#           begin; end refuses the flags.
#
# The context: SPEC, TASK_IDS, UNIT_KIND, BRANCH, BASE_BRANCH, WORKTREE, and
# PR_NUMBER of the PLANWRIGHT_STEP_* fields come from the caller's
# environment; POINT (post-pr for a re-fire), ID, PREV_RECORD (the run's last
# step record at that point), and PREV_HEAD and NEW_HEAD (step-record.sh
# heads at that point) are computed here.
#
# Output of command, begin (but `run`), and end: `<outcome><TAB><record>
# <TAB><hosting><TAB><session>`, the record path absolute and, for a reuse
# skip, the hosting and session those of the record it stands on (`-` when
# empty), so a following `continue` step can attach to that session. A failed
# record's excerpt names its cause: the exit code, the timeout, the signal,
# the expired wait and its holders, or the refused field; an unpooled run's
# cause opens its excerpt. The holders are an expired take's holder lines,
# else the wait report's.
#
# Runner state lives beside the run's records as `runner-*` files, which
# step-record.sh never reads: runner-rows-<point>, runner-resume
# (`<first run><TAB><point><TAB><chain runs>`), and
# runner-pending-<point>-<step>, each written through a temporary file and
# refused as a symbolic link. They are untrusted like the records: a row runs
# only after resolve-steps.sh --line accepts its location and args.
#
# Exit: 0 the step passed or was skipped, or the verb succeeded · 1 the step
# failed (its record written) · 2 usage, a refused argument, or a row that is
# not a resolved command step of the verb's hosting (nothing recorded or
# taken) · 4 a record, state, or slot operation failed (a release that fails
# after the record is written included) · 128+n a signal stopped `command`.
# resolve exits as resolve-steps.sh did, save its own 2 and 4.
#
# Portable bash 3.2 / BSD tooling.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
SR="$script_dir/step-record.sh"
SP="$script_dir/step-pool.sh"
RS="$script_dir/resolve-steps.sh"
TAB=$'\t'
NL=$'\n'

die() {
  printf 'step-run: %s\n' "$2" >&2
  exit "$1"
}
usage() {
  sed -n '/^# Usage:/,/^#   --run/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//' >&2
  exit 2
}
stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
is_run() { [[ $1 =~ ^[0-9]{6}$ ]]; }
is_step() { [[ $1 =~ ^[a-z][a-z0-9-]*$ ]] && [ "${#1}" -le 64 ]; }
is_in_run_point() {
  case $1 in pre-implementation | pre-ci | convergence | pre-pr | post-pr) return 0 ;; esac
  return 1
}

worktree=''
if [ "${1:-}" = --worktree ]; then
  [ $# -ge 2 ] || usage
  worktree=$2
  shift 2
fi
[ $# -ge 1 ] || usage
verb=$1
shift
if [ -z "$worktree" ]; then
  worktree=$(git rev-parse --show-toplevel 2>/dev/null) || die 2 "not inside a git work tree"
fi
worktree=$(cd -P -- "$worktree" 2>/dev/null && pwd -P) || die 2 "--worktree: not a directory"
cd "$worktree" || die 2 "--worktree: cannot enter it"
cache="$worktree/.claude/steps"

sr() { /bin/sh "$SR" --worktree "$worktree" "$@"; }

# A slot taken for an owner is released on every exit until its record is
# written or, for begin, its pending state hands it to end.
work='' SLOT_HELD='' SLOT='' ROW_POOL='' OWNER=''
# The guard clears only once the helper has freed the slot (or found it free),
# so a failed release is retried on exit; `unpooled` frees nothing.
release_slot() {
  local result
  [ -n "$SLOT_HELD" ] || return 0
  result=$(PLANWRIGHT_STEP_POOL_HOLD='' "$SP" release "$ROW_POOL" "$OWNER" ${SLOT:+--slot "$SLOT"}) || return 1
  case $result in released* | none) SLOT_HELD='' ;; *) return 1 ;; esac
}
cleanup() {
  release_slot || printf 'step-run: warning: the slot of pool %s could not be released\n' "$ROW_POOL" >&2
  [ -z "$work" ] || rm -rf "$work"
}
trap cleanup EXIT
work=$(mktemp -d "${TMPDIR:-/tmp}/step-run.XXXXXX") || die 4 "cannot create a temporary directory"

# field <line> <n>: the line's n-th tab-separated field, empty kept.
field() { printf '%s\n' "$1" | cut -f "$2"; }

# run_dir <id>: the run's directory, refused unless the helper issued it.
run_dir() {
  is_run "$1" || die 2 "--run: not a run id"
  [ -d "$cache/$1" ] && [ ! -L "$cache/$1" ] || die 2 "--run: no such run in the cache"
  printf '%s' "$cache/$1"
}

# put_state <path>: write stdin to a runner-state file through a temporary
# file beside it, refusing a symbolic link at the name.
put_state() {
  local tmp
  [ ! -L "$1" ] || die 4 "runner state ${1##*/} is a symbolic link; refusing it"
  tmp=$(mktemp "$(dirname "$1")/.runner-XXXXXX") || die 4 "cannot write runner state"
  if ! { cat >"$tmp" && mv -f "$tmp" "$1"; }; then
    rm -f "$tmp"
    die 4 "cannot write runner state"
  fi
}

# chain_runs <run>: the runs of the run's resume chain, first run first, the
# run itself excluded.
chain_runs() {
  local f="$cache/$1/runner-resume" r
  [ -f "$f" ] && [ ! -L "$f" ] || return 0
  for r in $(head -n 1 "$f" | cut -f 3); do
    is_run "$r" && [ -d "$cache/$r" ] && printf '%s\n' "$r"
  done
}

# rows_run <run>: the run whose resolved lists a re-fire reads, the first run
# of the run's resume chain (the run itself when it resumes nothing).
rows_run() {
  local r
  for r in $(chain_runs "$1") "$1"; do
    printf '%s' "$r"
    return
  done
}

# --- resolve ----------------------------------------------------------------
cmd_resolve() {
  local run='' points=() att='' rc p dir
  while [ $# -gt 0 ]; do
    case $1 in
      --run)
        [ $# -ge 2 ] || usage
        run=$2
        shift 2
        ;;
      --attended | --unattended)
        att=$1
        shift
        ;;
      -*) usage ;;
      *)
        points+=("$1")
        shift
        ;;
    esac
  done
  [ ${#points[@]} -ge 1 ] && [ -n "$att" ] || usage
  dir=$(run_dir "$run") || exit $?
  "$RS" "${points[@]}" --explain "$att" >"$work/rows"
  rc=$?
  cat "$work/rows"
  for p in "${points[@]}"; do
    is_in_run_point "$p" || continue
    awk -F '\t' -v P="$p" '$3 == P' "$work/rows" >"$work/point-rows"
    if [ -s "$work/point-rows" ] || [ "$rc" -eq 0 ]; then
      put_state "$dir/runner-rows-$p" <"$work/point-rows"
    else
      # A failed re-resolution leaves no stale rows to host a step from.
      [ -L "$dir/runner-rows-$p" ] || rm -f "$dir/runner-rows-$p"
    fi
  done
  exit "$rc"
}

# --- resume -----------------------------------------------------------------
cmd_resume() {
  local run='' from='' frun fpoint dir head first chain line ref step rhead rend hosting session path
  while [ $# -gt 0 ]; do
    case $1 in
      --run | --from) [ $# -ge 2 ] || usage ;;
      *) usage ;;
    esac
    case $1 in
      --run) run=$2 ;;
      --from) from=$2 ;;
    esac
    shift 2
  done
  frun=${from%%:*}
  fpoint=${from#*:}
  is_run "$frun" && [ "$from" = "$frun:$fpoint" ] || die 2 "--from: not <run>:<point> with a six-digit run id"
  is_in_run_point "$fpoint" || die 2 "--from: $fpoint is not an in-run point /execute-task wires"
  dir=$(run_dir "$run") || exit $?
  run_dir "$frun" >/dev/null || exit $?
  [ "$frun" != "$run" ] || die 2 "--from: a run cannot resume itself"
  chain=$(chain_runs "$frun" | tr '\n' ' ')
  chain="$chain$frun"
  first=${chain%% *}
  printf '%s\t%s\t%s\n' "$first" "$fpoint" "$chain" >"$work/resume" || die 4 "cannot write runner state"
  put_state "$dir/runner-resume" <"$work/resume"
  head=$(git rev-parse --verify -q 'HEAD^{commit}') || die 4 "cannot read the worktree's HEAD"
  sr lookup resume --run "$frun" --point "$fpoint" --head "$head" >"$work/prefix"
  case $? in
    0 | 3) ;;
    *) die 4 "the resume lookup failed" ;;
  esac
  while IFS= read -r line; do
    # Fields by position: a tab is IFS whitespace, so read would merge an
    # empty session into its neighbours.
    ref=$(field "$line" 2) step=$(field "$line" 3) rhead=$(field "$line" 4)
    rend=$(field "$line" 5) hosting=$(field "$line" 6) session=$(field "$line" 7)
    path=$(field "$line" 8)
    [ -n "$ref" ] || continue
    load_record "$worktree/$path" || die 4 "the record a resume skip stands on cannot be read"
    set -- --run "$run" --point "$fpoint" --step "$step" --kind "$REC_KIND" \
      --target "$REC_TARGET" --hosting "$hosting" --backend "$REC_BACKEND" \
      --head "$rhead" --end-head "$rend" --start "$(stamp)" --outcome skipped \
      --skip-code resume --stands-on "$ref"
    [ -z "$session" ] || set -- "$@" --session "$session"
    if [ -n "$REC_FP" ] && [ -n "$REC_DIGEST" ]; then
      set -- "$@" --fingerprint "$REC_FP" --args-digest "$REC_DIGEST"
      [ -z "$REC_REFIRE" ] || set -- "$@" --refire-of "$REC_REFIRE"
    fi
    line=$(sr write "$@") || die 4 "cannot write the resume skip of $step"
    printf 'skipped\t%s\t%s\t%s\t%s\n' "$step" "$line" "$hosting" "${session:--}"
  done <"$work/prefix"
}

# load_record <abs-path>: the record's kind, target, backend, fingerprint,
# args digest, and refire-of into the REC_* values, read through
# step-record.sh list.
load_record() {
  local p=$1 run vals
  run=$(basename "$(dirname "$p")")
  sr list --run "$run" >"$work/list" || return 1
  vals=$(awk -F '\t' -v REL="${p#"$worktree"/}" -v TAB="$TAB" '
    $1 == "record" { if (found) exit; found = ($2 == REL); next }
    found && NF >= 1 && !($1 in v) { v[$1] = substr($0, length($1) + 2) }
    END {
      if (!found) exit 1
      print v["kind"] TAB v["target"] TAB v["backend"] TAB v["fingerprint"] TAB v["args-digest"] TAB v["refire-of"] TAB "."
    }' "$work/list") || return 1
  REC_KIND=$(field "$vals" 1) REC_TARGET=$(field "$vals" 2) REC_BACKEND=$(field "$vals" 3)
  REC_FP=$(field "$vals" 4) REC_DIGEST=$(field "$vals" 5) REC_REFIRE=$(field "$vals" 6)
}

# refired <run>: the step ids a post-pr record of the run already re-fires.
refired() {
  sr list --run "$1" --point post-pr >"$work/post" || die 4 "cannot read the run's records"
  awk -F '\t' '$1 == "record" { s = "" } $1 == "step" { s = $2 } $1 == "refire-of" && $2 != "" && s != "" { print s }' \
    "$work/post" | sort -u
}

# --- refire -----------------------------------------------------------------
cmd_refire() {
  local run='' p r
  [ $# -eq 2 ] && [ "$1" = --run ] || usage
  run=$2
  run_dir "$run" >/dev/null || exit $?
  sr heads --run "$run" --point post-pr >/dev/null
  case $? in
    0) ;;
    3) return 0 ;;
    *) die 4 "cannot read the run's head moves" ;;
  esac
  refired "$run" >"$work/done"
  : >"$work/declared"
  for p in pre-ci pre-pr; do
    r=$(rows_run "$run")
    if [ -f "$cache/$r/runner-rows-$p" ]; then
      cat "$cache/$r/runner-rows-$p" >>"$work/declared"
    else
      printf 'step-run: warning: run %s resolved no %s list; its steps are not re-fired\n' "$r" "$p" >&2
    fi
  done
  awk -F '\t' -v TAB="$TAB" -v DONE="$work/done" '
    BEGIN { while ((getline d < DONE) > 0) done[d] = 1 }
    {
      if ($2 in seen) next
      seen[$2] = 1
      if ($1 == "run" && $16 == "post-pr" && $8 == "command" && !($2 in done))
        print "refire" TAB $2 TAB $3 TAB $7
    }' "$work/declared"
}

# --- command / begin / end ----------------------------------------------------
# row_of <run> <point> <step>: the step's resolved row into the ROW_* values.
row_of() {
  local f="$cache/$1/runner-rows-$2" row
  [ -f "$f" ] && [ ! -L "$f" ] || die 2 "no resolved rows for $2 in run $1; run the resolve verb first"
  row=$(awk -F '\t' -v S="$3" '$2 == S { print; exit }' "$f")
  [ -n "$row" ] || die 2 "step $3 is not in the resolved $2 list"
  IFS=$TAB read -r ROW_DECISION _ _ _ _ ROW_TARGET ROW_HOSTING ROW_KIND ROW_ARGS _ ROW_TIMEOUT \
    _ ROW_LOCATION ROW_POOL ROW_PATHS ROW_REFIRE <<<"$row"
  [ "$ROW_DECISION" = run ] || die 2 "step $3 did not resolve to run"
  [ "$ROW_KIND" = command ] || die 2 "step $3 is not a command step"
  [ "$ROW_ARGS" != - ] || ROW_ARGS=''
  [ "$ROW_TIMEOUT" != - ] || ROW_TIMEOUT=''
  [ -z "$ROW_TIMEOUT" ] || [[ $ROW_TIMEOUT =~ ^[1-9][0-9]{0,8}$ ]] || die 2 "step $3's resolved timeout is not whole seconds"
  [ "$ROW_POOL" != - ] || ROW_POOL=''
  [ "$ROW_PATHS" != - ] || ROW_PATHS=''
}

parse_step_args() {
  RUN='' POINT='' STEP='' REFIRE_OF='' BACKEND='' OWNER='' SESSION='' EXIT_CODE='' TIMED_OUT='' OUTPUT=''
  while [ $# -gt 0 ]; do
    case $1 in
      --run | --point | --step | --refire-of | --backend | --owner | --session | --exit | --timed-out | --output)
        [ $# -ge 2 ] || usage
        ;;
      *) usage ;;
    esac
    case $1 in
      --run) RUN=$2 ;;
      --point) POINT=$2 ;;
      --step) STEP=$2 ;;
      --refire-of) REFIRE_OF=$2 ;;
      --backend) BACKEND=$2 ;;
      --owner) OWNER=$2 ;;
      --session) SESSION=$2 ;;
      --exit) EXIT_CODE=$2 ;;
      --timed-out) TIMED_OUT=$2 ;;
      --output) OUTPUT=$2 ;;
    esac
    shift 2
  done
  DIR=$(run_dir "$RUN") || exit $?
  is_in_run_point "$POINT" || die 2 "--point: not an in-run point"
  is_step "$STEP" || die 2 "--step: not a step id"
  [ -z "$BACKEND" ] || { [[ $BACKEND =~ ^[a-z0-9][a-z0-9-]*$ ]] && [ "${#BACKEND}" -le 64 ]; } \
    || die 2 "--backend: not a backend name"
  [ -z "$SESSION" ] || [[ $SESSION =~ ^[A-Za-z0-9._:-]{1,128}$ ]] || die 2 "--session: not a session id"
  [ -z "$OWNER" ] || [[ $OWNER =~ ^[1-9][0-9]{0,9}$ ]] || die 2 "--owner: not a process id"
  CTX_POINT=$POINT
  ROW_RUN=$RUN ROW_POINT=$POINT
  if [ -n "$REFIRE_OF" ]; then
    case $REFIRE_OF in pre-ci | pre-pr) ;; *) die 2 "--refire-of: not pre-ci or pre-pr" ;; esac
    [ "$POINT" = post-pr ] || die 2 "--refire-of: a re-fire runs at post-pr"
    ROW_POINT=$REFIRE_OF
    ROW_RUN=$(rows_run "$RUN")
  fi
  PENDING="$DIR/runner-pending-$CTX_POINT-$STEP"
}

# load_row <hosting-test>: the row, refused before anything is recorded or
# taken when it is not the verb's hosting or, for a re-fire, not a step that
# declares one or one this run already re-fired.
load_row() {
  row_of "$ROW_RUN" "$ROW_POINT" "$STEP"
  case $1:$ROW_HOSTING in
    isolated:isolated | session:in-session | session:continue) ;;
    isolated:*) die 2 "step $STEP is hosted $ROW_HOSTING; use begin and end" ;;
    *) die 2 "step $STEP is hosted isolated; use command" ;;
  esac
  if [ -n "$REFIRE_OF" ]; then
    [ "$ROW_REFIRE" = post-pr ] || die 2 "step $STEP declares no refire: post-pr"
    refired "$RUN" >"$work/refired"
    ! grep -Fxq -- "$STEP" "$work/refired" || die 2 "step $STEP was already re-fired in run $RUN"
  fi
}

# context: export the twelve fields' per-step values.
context() {
  local prev moves rc
  sr list --run "$RUN" --point "$CTX_POINT" >"$work/ctx-list" || die 4 "cannot read the run's records"
  prev=$(awk -F '\t' '$1 == "record" && $2 ~ /-step-[a-z-]*\.rec$/ { p = $2 } END { print p }' "$work/ctx-list")
  export PLANWRIGHT_STEP_POINT="$CTX_POINT" PLANWRIGHT_STEP_ID="$STEP"
  export PLANWRIGHT_STEP_PREV_RECORD="${prev:+$worktree/$prev}"
  moves=$(sr heads --run "$RUN" --point "$CTX_POINT")
  rc=$?
  case $rc in
    0 | 3) ;;
    *) die 4 "cannot read the run's head moves" ;;
  esac
  export PLANWRIGHT_STEP_PREV_HEAD="${moves%%"$TAB"*}" PLANWRIGHT_STEP_NEW_HEAD="${moves#*"$TAB"}"
  local v
  for v in SPEC TASK_IDS UNIT_KIND BRANCH BASE_BRANCH WORKTREE PR_NUMBER; do
    export "PLANWRIGHT_STEP_$v=$(printenv "PLANWRIGHT_STEP_$v" || :)"
  done
}

# holders_of <take-stdout> <take-stderr>: one --holder pair per holder into
# HOLDER_ARGS, from an expired take's holder lines, else from the wait report.
holders_of() {
  local hl pid st wt
  HOLDER_ARGS=()
  if grep -q "^holder$TAB" "$1"; then
    while IFS=$TAB read -r _ _ pid st wt; do
      [ "$st" != '(full-suite)' ] || st='the full-suite run'
      case $st in 'the full-suite run') ;; *) st="step $st" ;; esac
      HOLDER_ARGS+=(--holder "pid $pid ($st, worktree $wt)")
    done < <(grep "^holder$TAB" "$1")
    return
  fi
  hl=$(sed -n -e 's/^step-pool: .* waiting up to [0-9]*s on: //p' "$2" 2>/dev/null | tail -n 1)
  [ "$hl" != 'no live holder found' ] || hl=''
  while [ -n "$hl" ]; do
    case $hl in
      *'; pid '*)
        HOLDER_ARGS+=(--holder "${hl%%; pid *}")
        hl="pid ${hl#*; pid }"
        ;;
      *)
        HOLDER_ARGS+=(--holder "$hl")
        hl=''
        ;;
    esac
  done
}

# prepare: the reuse check and the take, shared by command and begin, after
# load_row. Sets STATE (skipped | expired | taken | nested | unpooled | none),
# and for a step that will run START, HEAD0, WAITED, and the pool and
# fingerprint argument lists for its record.
prepare() {
  local hit rc out
  [ -n "$BACKEND" ] || BACKEND=runner
  FP_ARGS=() POOL_ARGS=() HOLDER_ARGS=() REFIRE_ARGS=()
  : >"$work/take.err"
  [ -z "$REFIRE_OF" ] || REFIRE_ARGS=(--refire-of "$REFIRE_OF")
  if [ -n "$ROW_PATHS" ]; then
    local fp digest
    fp=$(sr fingerprint --paths "$ROW_PATHS") || die 4 "cannot fingerprint the declared paths"
    digest=$(/bin/sh "$SR" args-digest "$ROW_ARGS") || die 4 "cannot digest the args"
    FP_ARGS=(--fingerprint "$fp" --args-digest "$digest")
    hit=$(sr lookup reuse --step "$STEP" --target "$ROW_TARGET" --args-digest "$digest" --fingerprint "$fp")
    rc=$?
    if [ "$rc" -eq 0 ]; then
      local ref h0 hosting session
      hit=${hit%%"$NL"*}
      ref=$(field "$hit" 2) hosting=$(field "$hit" 6) session=$(field "$hit" 7)
      h0=$(git rev-parse --verify -q 'HEAD^{commit}') || die 4 "cannot read the worktree's HEAD"
      out=$(sr write --run "$RUN" --point "$CTX_POINT" --step "$STEP" --kind command \
        --target "$ROW_TARGET" --hosting "$ROW_HOSTING" --backend "$BACKEND" --head "$h0" \
        --end-head "$h0" --start "$(stamp)" --outcome skipped --skip-code reuse \
        --stands-on "$ref" ${FP_ARGS[@]+"${FP_ARGS[@]}"} ${REFIRE_ARGS[@]+"${REFIRE_ARGS[@]}"}) || die 4 "cannot write the reuse skip"
      printf 'skipped\t%s\t%s\t%s\n' "$out" "$hosting" "${session:--}"
      STATE=skipped
      return
    fi
    [ "$rc" -eq 3 ] || die 4 "the reuse lookup failed"
  fi
  STATE=none WAITED=0 START=$(stamp)
  if [ -n "$ROW_POOL" ]; then
    # The wait report reaches stderr as it is made, not after the wait.
    mkfifo "$work/take.fifo" || die 4 "cannot create a FIFO for the wait report"
    tee "$work/take.err" <"$work/take.fifo" >&2 &
    local teep=$!
    "$SP" take "$ROW_POOL" "$OWNER" --step "$STEP" --worktree "$worktree" \
      >"$work/take.out" 2>"$work/take.fifo"
    rc=$?
    wait "$teep"
    STATE=$(awk -F '\t' 'NR == 1 { print $1 }' "$work/take.out")
    SLOT=$(awk -F '\t' 'NR == 1 && $2 ~ /^[0-9]+$/ { print $2 }' "$work/take.out")
    WAITED=$(awk -F '\t' 'NR == 1 && $3 ~ /^[0-9]+$/ { print $3 }' "$work/take.out")
    WAITED=${WAITED:-0}
    case $rc:$STATE in
      0:taken) SLOT_HELD=yes ;;
      0:nested | 0:unpooled | 3:expired) ;;
      *) die 4 "the pool helper failed (exit $rc)" ;;
    esac
    holders_of "$work/take.out" "$work/take.err"
    POOL_ARGS=(--pool "$ROW_POOL" --wait "$WAITED" ${HOLDER_ARGS[@]+"${HOLDER_ARGS[@]}"})
    [ "$STATE" != unpooled ] || POOL_ARGS+=(--unpooled)
    [ "$STATE" = expired ] || START=$(stamp)
  fi
  HEAD0=$(git rev-parse --verify -q 'HEAD^{commit}') || die 4 "cannot read the worktree's HEAD"
}

# finish <outcome> <output-file> [<exit>]: release a taken slot, then write
# the record and print the result line; exit 1 unless passed (or <exit>).
finish() {
  local outcome=$1 output=$2 end_head out session_args=() released=0 was_held=$SLOT_HELD
  release_slot || released=1
  if [ -n "$was_held" ] && [ "$released" -eq 0 ] && [ -f "$PENDING" ] && [ ! -L "$PENDING" ]; then
    sed 's/^state\ttaken$/state\treleased/' "$PENDING" >"$work/pending-released" \
      && put_state "$PENDING" <"$work/pending-released"
  fi
  end_head=$(git rev-parse --verify -q 'HEAD^{commit}') || die 4 "cannot read the worktree's HEAD"
  [ -z "$SESSION" ] || session_args=(--session "$SESSION")
  out=$(sr write --run "$RUN" --point "$CTX_POINT" --step "$STEP" --kind command \
    --target "$ROW_TARGET" --hosting "$ROW_HOSTING" --backend "$BACKEND" ${session_args[@]+"${session_args[@]}"} \
    --head "$HEAD0" --end-head "$end_head" --start "$START" --outcome "$outcome" \
    --excerpt-file "$output" --output "$output" ${POOL_ARGS[@]+"${POOL_ARGS[@]}"} ${FP_ARGS[@]+"${FP_ARGS[@]}"} \
    ${REFIRE_ARGS[@]+"${REFIRE_ARGS[@]}"}) || die 4 "cannot write the step record"
  [ ! -f "$PENDING" ] || rm -f "$PENDING"
  printf '%s\t%s\t%s\t%s\n' "$outcome" "$out" "$ROW_HOSTING" "${SESSION:--}"
  if [ "$released" -ne 0 ]; then
    die 4 "the slot of pool $ROW_POOL could not be released for pid $OWNER"
  fi
  [ -z "${3:-}" ] || exit "$3"
  [ "$outcome" = passed ] || exit 1
}

# new_output: a fresh output file under the run, opening with any warning the
# take printed (an unpooled run's cause among them).
new_output() {
  local o
  o=$(mktemp "$DIR/output-XXXXXX") || die 4 "cannot create the output file"
  grep '^step-pool: warning: ' "$work/take.err" >"$o" 2>/dev/null || :
  printf '%s' "$o"
}

expired_output() {
  local o
  o=$(new_output) || exit $?
  {
    printf 'step-run: the wait for pool %s passed its bound; the step did not run\n' "$ROW_POOL"
    grep '^step-pool: ' "$work/take.err" || :
  } >>"$o"
  printf '%s' "$o"
}

# mark_args: resolve-steps.sh's hold-mark flags for a taken slot.
mark_args() {
  MARK_ARGS=()
  [ "$STATE" != taken ] || MARK_ARGS=(--pool "$ROW_POOL" --owner "$OWNER")
}

# render_line <output>: the resolver's --line for the step into LINE, which
# validates every context value, the location, and the args; a refusal fails
# the step.
render_line() {
  local args=()
  [ -z "$ROW_ARGS" ] || read -r -a args <<<"$ROW_ARGS"
  ARGV=("$ROW_LOCATION" ${args[@]+"${args[@]}"})
  if ! LINE=$("$RS" "$CTX_POINT" ${MARK_ARGS[@]+"${MARK_ARGS[@]}"} --line "${ARGV[@]}" 2>"$work/ctx.err"); then
    cat "$work/ctx.err" >>"$1"
    cat "$work/ctx.err" >&2
    finish failed "$1"
  fi
}

# group_gone <pgid>: no process of the group is left.
group_gone() { ! kill -0 -- "-$1" 2>/dev/null; }

# end_group <pgid>: TERM the group, then KILL what is left after ten seconds,
# returning once the group is gone.
end_group() {
  local k=0
  kill -TERM -- "-$1" 2>/dev/null
  while ! group_gone "$1" && [ "$k" -lt 10 ]; do
    sleep 1
    k=$((k + 1))
  done
  kill -KILL -- "-$1" 2>/dev/null
  while ! group_gone "$1"; do sleep 1; done
}

caught='' child='' escalator=''
# on_signal <128+n>: forward TERM to the check's group and KILL it ten
# seconds later if it is still there.
on_signal() {
  caught=$1
  stop_group
}
stop_group() {
  [ -n "$child" ] && [ -z "$escalator" ] || return 0
  kill -TERM -- "-$child" 2>/dev/null
  set -m
  (
    sleep 10
    kill -KILL -- "-$child" 2>/dev/null
  ) &
  escalator=$!
  set +m
}

cmd_command() {
  parse_step_args "$@"
  [ -z "$OWNER" ] || die 2 "--owner: command's slot owner is its own process"
  [ -z "$EXIT_CODE$TIMED_OUT$OUTPUT" ] || usage
  OWNER=$$
  load_row isolated
  prepare
  [ "$STATE" != skipped ] || exit 0
  local o rc killer=''
  if [ "$STATE" = expired ]; then
    o=$(expired_output) || exit $?
    finish failed "$o"
  fi
  context
  mark_args
  o=$(new_output) || exit $?
  render_line "$o"
  # The check runs in its own process group, so a timeout or a signal ends
  # everything it started before the slot is released. A signal reaching this
  # script is forwarded to the group and held until the group is gone.
  trap 'on_signal 129' HUP
  trap 'on_signal 130' INT
  trap 'on_signal 143' TERM
  set -m
  (
    [ "$STATE" != taken ] || export PLANWRIGHT_STEP_POOL_HOLD="$ROW_POOL:$OWNER"
    exec "${ARGV[@]}" </dev/null >>"$o" 2>&1
  ) &
  child=$!
  if [ -n "$ROW_TIMEOUT" ]; then
    (
      sleep "$ROW_TIMEOUT"
      : >"$work/timed-out"
      kill -TERM -- "-$child" 2>/dev/null
      sleep 10
      kill -KILL -- "-$child" 2>/dev/null
    ) &
    killer=$!
  fi
  set +m
  [ -z "$caught" ] || stop_group
  while :; do
    wait "$child"
    rc=$?
    kill -0 "$child" 2>/dev/null || break
  done
  [ -z "$killer" ] || kill -TERM -- "-$killer" 2>/dev/null
  [ -z "$escalator" ] || kill -TERM -- "-$escalator" 2>/dev/null
  if [ -n "$caught" ] || [ -e "$work/timed-out" ]; then
    end_group "$child"
  fi
  if [ -n "$caught" ]; then
    printf 'step-run: stopped by signal %s; ended by the runner\n' "$((caught - 128))" >>"$o"
    finish failed "$o" "$caught"
  fi
  if [ -e "$work/timed-out" ]; then
    printf 'step-run: timed out after %ss; ended by the runner\n' "$ROW_TIMEOUT" >>"$o"
    finish failed "$o"
  fi
  [ "$rc" -eq 0 ] || printf 'step-run: exited %s\n' "$rc" >>"$o"
  if [ "$rc" -eq 0 ]; then finish passed "$o"; else finish failed "$o"; fi
}

cmd_begin() {
  parse_step_args "$@"
  [ -n "$OWNER" ] || die 2 "--owner: required, the unit session's process"
  [ -z "$EXIT_CODE$TIMED_OUT$OUTPUT" ] || usage
  [ ! -e "$PENDING" ] && [ ! -L "$PENDING" ] || die 2 "step $STEP at $CTX_POINT in run $RUN already has a pending begin; run end first"
  load_row session
  prepare
  [ "$STATE" != skipped ] || exit 0
  local o
  if [ "$STATE" = expired ]; then
    o=$(expired_output) || exit $?
    finish failed "$o"
  fi
  context
  mark_args
  o=$(new_output) || exit $?
  render_line "$o"
  {
    printf 'state\t%s\nowner\t%s\nslot\t%s\nstart\t%s\nhead\t%s\nwaited\t%s\nbackend\t%s\nsession\t%s\nrefire-of\t%s\noutput\t%s\npool\t%s\n' \
      "$STATE" "$OWNER" "$SLOT" "$START" "$HEAD0" "$WAITED" "$BACKEND" "$SESSION" "$REFIRE_OF" "$o" "$ROW_POOL"
    [ ${#FP_ARGS[@]} -eq 0 ] || printf 'fingerprint\t%s\ndigest\t%s\n' "${FP_ARGS[1]}" "${FP_ARGS[3]}"
    local i
    for ((i = 1; i < ${#HOLDER_ARGS[@]}; i += 2)); do printf 'holder\t%s\n' "${HOLDER_ARGS[$i]}"; done
  } >"$work/pending" || die 4 "cannot write runner state"
  put_state "$PENDING" <"$work/pending"
  # The pending state now carries the slot to end.
  SLOT_HELD=''
  printf 'run\t%s\n' "$LINE"
}

cmd_end() {
  parse_step_args "$@"
  [[ $EXIT_CODE =~ ^[0-9]{1,3}$ ]] || die 2 "--exit: not an exit code"
  [ -z "$TIMED_OUT" ] || [[ $TIMED_OUT =~ ^[1-9][0-9]{0,8}$ ]] || die 2 "--timed-out: not whole seconds"
  [ -z "$REFIRE_OF$BACKEND$OWNER" ] || die 2 "end takes the re-fire, backend, and owner from begin"
  [ -f "$PENDING" ] && [ ! -L "$PENDING" ] || die 2 "no pending begin for $STEP at $CTX_POINT in run $RUN"
  local k v fp='' digest='' o='' pool=''
  HOLDER_ARGS=()
  while IFS=$TAB read -r k v; do
    case $k in
      state) STATE=$v ;;
      owner) OWNER=$v ;;
      slot) SLOT=$v ;;
      start) START=$v ;;
      head) HEAD0=$v ;;
      waited) WAITED=$v ;;
      backend) BACKEND=$v ;;
      session) [ -n "$SESSION" ] || SESSION=$v ;;
      refire-of) REFIRE_OF=$v ;;
      output) o=$v ;;
      pool) pool=$v ;;
      holder) HOLDER_ARGS+=(--holder "$v") ;;
      fingerprint) fp=$v ;;
      digest) digest=$v ;;
    esac
  done <"$PENDING"
  if [ -n "$REFIRE_OF" ]; then
    ROW_POINT=$REFIRE_OF
    ROW_RUN=$(rows_run "$RUN")
  fi
  # The slot is released from the pool begin took, whatever the row says now
  # (or if it is gone); `released` is a retry after an earlier end freed it.
  ROW_POOL=$pool
  case $STATE in
    taken) SLOT_HELD=yes ;;
    released) STATE=taken ;;
  esac
  row_of "$ROW_RUN" "$ROW_POINT" "$STEP"
  ROW_POOL=$pool
  FP_ARGS=() POOL_ARGS=() REFIRE_ARGS=()
  [ -z "$REFIRE_OF" ] || REFIRE_ARGS=(--refire-of "$REFIRE_OF")
  # The fingerprint the step ran over, as begin took it.
  [ -z "$fp" ] || FP_ARGS=(--fingerprint "$fp" --args-digest "$digest")
  if [ -n "$ROW_POOL" ] && [ "$STATE" != none ]; then
    POOL_ARGS=(--pool "$ROW_POOL" --wait "$WAITED" ${HOLDER_ARGS[@]+"${HOLDER_ARGS[@]}"})
    [ "$STATE" != unpooled ] || POOL_ARGS+=(--unpooled)
  fi
  case $o in "$DIR"/output-*) ;; *) o='' ;; esac
  case ${o#"$DIR"/output-} in */* | '') o='' ;; esac
  [ -z "$o" ] || { [ -f "$o" ] && [ ! -L "$o" ]; } || o=''
  [ -n "$o" ] || o=$(new_output) || exit $?
  if [ -n "$OUTPUT" ]; then
    cat -- "$OUTPUT" >>"$o" 2>/dev/null || printf 'step-run: the output file could not be read\n' >>"$o"
  fi
  if [ -n "$TIMED_OUT" ]; then
    printf "step-run: timed out after %ss; ended by the session's shell tool\n" "$TIMED_OUT" >>"$o"
    finish failed "$o"
  fi
  [ "$EXIT_CODE" -eq 0 ] || printf 'step-run: exited %s\n' "$EXIT_CODE" >>"$o"
  if [ "$EXIT_CODE" -eq 0 ]; then finish passed "$o"; else finish failed "$o"; fi
}

case $verb in
  resolve) cmd_resolve "$@" ;;
  resume) cmd_resume "$@" ;;
  refire) cmd_refire "$@" ;;
  command) cmd_command "$@" ;;
  begin) cmd_begin "$@" ;;
  end) cmd_end "$@" ;;
  *) usage ;;
esac
