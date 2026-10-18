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
#       --step <id> [--refire-of <point>] [--backend <name>]
#   step-run.sh [--worktree <dir>] begin --run <id> --point <point>
#       --step <id> --owner <pid> [--refire-of <point>] [--backend <name>]
#       [--session <id>]
#   step-run.sh [--worktree <dir>] end --run <id> --point <point>
#       --step <id> --exit <code> [--timed-out <seconds>] [--output <file>]
#
#   --worktree  the unit's worktree; default the enclosing git top level.
#               Every command runs there.
#   --run       a run id step-record.sh issued.
#
# resolve   run resolve-steps.sh over the points with --explain and the
#           attendance flag, pass its stdout, stderr, and exit through, and
#           keep each point's rows as this run's runner state (a later
#           resolution of the same point in the run replaces them). The
#           command, begin, and refire verbs read a step's row from there.
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
#           pre-ci then pre-pr rows of the run's chain's first run, each
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
#           ends it at its timeout, releases the slot once it has exited,
#           and writes the record. A refused context value fails the step
#           without running it.
# begin     the same up to the run, for a session-hosted (in-session or
#           continue) command step whose slot the unit session's process
#           --owner holds: prints `run<TAB><line>`, the line
#           resolve-steps.sh --line renders (hold mark included when a slot
#           was taken) for the session's shell tool, and keeps the pending
#           state for `end`.
# end       release the slot begin took and write the record from the
#           session's exit code (--timed-out names a timeout the shell tool
#           enforced; --output a file of the line's output, copied into the
#           cache).
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
# record's excerpt names its cause: the exit code, the timeout, the expired
# wait and its holders, or the refused context field.
#
# Runner state lives beside the run's records as `runner-*` files, which
# step-record.sh never reads: runner-rows-<point>, runner-resume, and
# runner-pending-<point>-<step>.
#
# Exit: 0 the step passed or was skipped, or the verb succeeded · 1 the step
# failed (its record written) · 2 usage, a refused argument, or a row that is
# not a resolved command step (nothing recorded) · 4 a record or slot
# operation failed. resolve exits as resolve-steps.sh did.
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

work=''
cleanup() { [ -z "$work" ] || rm -rf "$work"; }
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

# chain_first <run>: the first run of the run's resume chain.
chain_first() {
  local f="$cache/$1/runner-resume" first
  if [ -f "$f" ] && [ ! -L "$f" ]; then
    first=$(head -n 1 "$f" | cut -f 1)
    if is_run "$first" && [ -d "$cache/$first" ]; then
      printf '%s' "$first"
      return
    fi
  fi
  printf '%s' "$1"
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
  local opts=(--explain)
  "$RS" "${points[@]}" ${opts[@]+"${opts[@]}"} "$att" >"$work/rows"
  rc=$?
  cat "$work/rows"
  for p in "${points[@]}"; do
    is_in_run_point "$p" || continue
    awk -F '\t' -v P="$p" '$3 == P' "$work/rows" >"$work/point-rows"
    if [ -s "$work/point-rows" ] || [ "$rc" -eq 0 ]; then
      cp "$work/point-rows" "$dir/runner-rows-$p" || die 4 "cannot keep the resolved rows"
    fi
  done
  exit "$rc"
}

# --- resume -----------------------------------------------------------------
cmd_resume() {
  local run='' from='' frun fpoint dir head first line ref step rhead rend hosting session path
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
  first=$(chain_first "$frun")
  printf '%s\t%s\n' "$first" "$fpoint" >"$dir/runner-resume" || die 4 "cannot keep the resume link"
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

# --- refire -----------------------------------------------------------------
cmd_refire() {
  local run='' first dir
  [ $# -eq 2 ] && [ "$1" = --run ] || usage
  run=$2
  dir=$(run_dir "$run") || exit $?
  sr heads --run "$run" --point post-pr >/dev/null
  case $? in
    0) ;;
    3) return 0 ;;
    *) die 4 "cannot read the run's head moves" ;;
  esac
  first=$(chain_first "$run")
  sr list --run "$run" --point post-pr >"$work/post"
  awk -F '\t' '$1 == "step" { s = $2 } $1 == "refire-of" && $2 != "" { print s }' "$work/post" \
    | sort -u >"$work/done"
  for p in pre-ci pre-pr; do
    [ -f "$cache/$first/runner-rows-$p" ] && cat "$cache/$first/runner-rows-$p"
  done | awk -F '\t' -v TAB="$TAB" -v DONE="$work/done" '
    BEGIN { while ((getline d < DONE) > 0) done[d] = 1 }
    {
      if ($2 in seen) next
      seen[$2] = 1
      if ($1 == "run" && $16 == "post-pr" && $8 == "command" && !($2 in done))
        print "refire" TAB $2 TAB $3 TAB $7
    }'
}

# --- command / begin / end ----------------------------------------------------
# row_of <run> <point> <step>: the step's resolved row into the ROW_* values.
row_of() {
  local f="$cache/$1/runner-rows-$2" row
  [ -f "$f" ] && [ ! -L "$f" ] || die 2 "no resolved rows for $2 in run $1; run the resolve verb first"
  row=$(awk -F '\t' -v S="$3" '$2 == S { print; exit }' "$f")
  [ -n "$row" ] || die 2 "step $3 is not in the resolved $2 list"
  IFS=$TAB read -r ROW_DECISION _ _ _ _ ROW_TARGET ROW_HOSTING ROW_KIND ROW_ARGS _ ROW_TIMEOUT \
    _ ROW_LOCATION ROW_POOL ROW_PATHS _ <<<"$row"
  [ "$ROW_DECISION" = run ] || die 2 "step $3 did not resolve to run"
  [ "$ROW_KIND" = command ] || die 2 "step $3 is not a command step"
  [ "$ROW_ARGS" != - ] || ROW_ARGS=''
  [ "$ROW_TIMEOUT" != - ] || ROW_TIMEOUT=''
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
  CTX_POINT=$POINT
  ROW_RUN=$RUN ROW_POINT=$POINT
  if [ -n "$REFIRE_OF" ]; then
    case $REFIRE_OF in pre-ci | pre-pr) ;; *) die 2 "--refire-of: not pre-ci or pre-pr" ;; esac
    [ "$POINT" = post-pr ] || die 2 "--refire-of: a re-fire runs at post-pr"
    ROW_RUN=$(chain_first "$RUN") ROW_POINT=$REFIRE_OF
  fi
  [ -z "$OWNER" ] || [[ $OWNER =~ ^[1-9][0-9]{0,9}$ ]] || die 2 "--owner: not a process id"
  PENDING="$DIR/runner-pending-$CTX_POINT-$STEP"
}

# context <ctx-point>: export the twelve fields' per-step values.
context() {
  local prev moves
  prev=$(sr list --run "$RUN" --point "$CTX_POINT" | sed -n 's/^record\t\(.*-step-.*\.rec\)$/\1/p' | tail -n 1)
  export PLANWRIGHT_STEP_POINT="$CTX_POINT" PLANWRIGHT_STEP_ID="$STEP"
  export PLANWRIGHT_STEP_PREV_RECORD="${prev:+$worktree/$prev}"
  moves=$(sr heads --run "$RUN" --point "$CTX_POINT" 2>/dev/null) || moves=''
  export PLANWRIGHT_STEP_PREV_HEAD="${moves%%"$TAB"*}" PLANWRIGHT_STEP_NEW_HEAD="${moves#*"$TAB"}"
  [ -n "$moves" ] || PLANWRIGHT_STEP_NEW_HEAD=''
  local v
  for v in SPEC TASK_IDS UNIT_KIND BRANCH BASE_BRANCH WORKTREE PR_NUMBER; do
    export "PLANWRIGHT_STEP_$v=$(printenv "PLANWRIGHT_STEP_$v" || :)"
  done
}

# holders_of <stderr-file>: one --holder argument pair per holder the take's
# wait report named, into HOLDER_ARGS.
holders_of() {
  local hl
  HOLDER_ARGS=()
  hl=$(sed -n -e 's/^step-pool: .* waiting up to [0-9]*s on: //p' \
    -e 's/^step-pool: .* held by: //p' "$1" 2>/dev/null | tail -n 1)
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

# prepare: the reuse check and the take, shared by command and begin. Sets
# STATE (skipped | expired | taken | nested | unpooled | none), and for a
# step that will run START, HEAD0, WAITED, and the pool and fingerprint
# argument lists for its record.
prepare() {
  local hit rc out
  row_of "$ROW_RUN" "$ROW_POINT" "$STEP"
  [ -n "$BACKEND" ] || BACKEND=runner
  FP_ARGS=() POOL_ARGS=() HOLDER_ARGS=() REFIRE_ARGS=()
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
    local line
    line=$(PLANWRIGHT_STEP_POOL_HOLD="${PLANWRIGHT_STEP_POOL_HOLD-}" "$SP" take "$ROW_POOL" "$OWNER" \
      --step "$STEP" --worktree "$worktree" 2>"$work/take.err")
    rc=$?
    cat "$work/take.err" >&2
    holders_of "$work/take.err"
    STATE=$(printf '%s\n' "$line" | awk -F '\t' 'NR == 1 { print $1 }')
    WAITED=$(printf '%s\n' "$line" | awk -F '\t' 'NR == 1 && $3 ~ /^[0-9]+$/ { print $3 }')
    WAITED=${WAITED:-0}
    case $rc:$STATE in
      0:taken | 0:nested | 0:unpooled | 3:expired) ;;
      *) die 4 "the pool helper failed (exit $rc)" ;;
    esac
    POOL_ARGS=(--pool "$ROW_POOL" --wait "$WAITED" ${HOLDER_ARGS[@]+"${HOLDER_ARGS[@]}"})
    [ "$STATE" != unpooled ] || POOL_ARGS+=(--unpooled)
    [ "$STATE" = expired ] || START=$(stamp)
  fi
  HEAD0=$(git rev-parse --verify -q 'HEAD^{commit}') || die 4 "cannot read the worktree's HEAD"
}

# finish <outcome> <output-file>: release a taken slot, then write the record
# and print the result line.
finish() {
  local outcome=$1 output=$2 end_head out session_args=()
  if [ "$STATE" = taken ]; then
    PLANWRIGHT_STEP_POOL_HOLD='' "$SP" release "$ROW_POOL" "$OWNER" >/dev/null \
      || printf 'step-run: warning: the slot of pool %s could not be released\n' "$ROW_POOL" >&2
  fi
  end_head=$(git rev-parse --verify -q 'HEAD^{commit}') || die 4 "cannot read the worktree's HEAD"
  [ -z "$SESSION" ] || session_args=(--session "$SESSION")
  out=$(sr write --run "$RUN" --point "$CTX_POINT" --step "$STEP" --kind command \
    --target "$ROW_TARGET" --hosting "$ROW_HOSTING" --backend "$BACKEND" ${session_args[@]+"${session_args[@]}"} \
    --head "$HEAD0" --end-head "$end_head" --start "$START" --outcome "$outcome" \
    --excerpt-file "$output" --output "$output" ${POOL_ARGS[@]+"${POOL_ARGS[@]}"} ${FP_ARGS[@]+"${FP_ARGS[@]}"} \
    ${REFIRE_ARGS[@]+"${REFIRE_ARGS[@]}"}) || die 4 "cannot write the step record"
  printf '%s\t%s\t%s\t%s\n' "$outcome" "$out" "$ROW_HOSTING" "${SESSION:--}"
  [ "$outcome" = passed ] || exit 1
}

new_output() {
  mktemp "$DIR/output-XXXXXX" || die 4 "cannot create the output file"
}

expired_output() {
  local o
  o=$(new_output) || exit $?
  {
    printf 'step-run: the wait for pool %s passed its bound; the step did not run\n' "$ROW_POOL"
    grep '^step-pool: ' "$work/take.err" || :
  } >"$o"
  printf '%s' "$o"
}

# mark_args: resolve-steps.sh's hold-mark flags for a taken slot.
mark_args() {
  MARK_ARGS=()
  [ "$STATE" != taken ] || MARK_ARGS=(--pool "$ROW_POOL" --owner "$OWNER")
}

cmd_command() {
  parse_step_args "$@"
  [ -z "$OWNER" ] || die 2 "--owner: command's slot owner is its own process"
  OWNER=$$
  prepare
  [ "$STATE" != skipped ] || exit 0
  local o rc
  if [ "$STATE" = expired ]; then
    o=$(expired_output) || exit $?
    finish failed "$o"
  fi
  [ "$ROW_HOSTING" = isolated ] || die 2 "step $STEP is hosted $ROW_HOSTING; use begin and end"
  context
  mark_args
  o=$(new_output) || exit $?
  # The resolver validates every context value (exit 6 names the field).
  if ! "$RS" "$CTX_POINT" ${MARK_ARGS[@]+"${MARK_ARGS[@]}"} --prefix >/dev/null 2>"$work/ctx.err"; then
    cat "$work/ctx.err" >"$o"
    cat "$work/ctx.err" >&2
    finish failed "$o"
  fi
  local args=()
  [ -z "$ROW_ARGS" ] || read -r -a args <<<"$ROW_ARGS"
  (
    [ "$STATE" != taken ] || export PLANWRIGHT_STEP_POOL_HOLD="$ROW_POOL:$OWNER"
    exec "$ROW_LOCATION" ${args[@]+"${args[@]}"} </dev/null >"$o" 2>&1
  ) &
  local child=$! timed=''
  if [ -n "$ROW_TIMEOUT" ]; then
    local n=0
    while kill -0 "$child" 2>/dev/null; do
      if [ "$n" -ge "$ROW_TIMEOUT" ]; then
        timed=yes
        kill -TERM "$child" 2>/dev/null
        local k=0
        while kill -0 "$child" 2>/dev/null && [ "$k" -lt 10 ]; do
          sleep 1
          k=$((k + 1))
        done
        kill -KILL "$child" 2>/dev/null
        break
      fi
      sleep 1
      n=$((n + 1))
    done
  fi
  wait "$child"
  rc=$?
  if [ -n "$timed" ]; then
    printf 'step-run: timed out after %ss; ended by the runner\n' "$ROW_TIMEOUT" >>"$o"
    finish failed "$o"
  fi
  [ "$rc" -eq 0 ] || printf 'step-run: exited %s\n' "$rc" >>"$o"
  if [ "$rc" -eq 0 ]; then finish passed "$o"; else finish failed "$o"; fi
}

cmd_begin() {
  parse_step_args "$@"
  [ -n "$OWNER" ] || die 2 "--owner: required, the unit session's process"
  prepare
  [ "$STATE" != skipped ] || exit 0
  local o
  if [ "$STATE" = expired ]; then
    o=$(expired_output) || exit $?
    finish failed "$o"
  fi
  [ "$ROW_HOSTING" != isolated ] || die 2 "step $STEP is hosted isolated; use command"
  context
  mark_args
  local args=() line
  [ -z "$ROW_ARGS" ] || read -r -a args <<<"$ROW_ARGS"
  if ! line=$("$RS" "$CTX_POINT" ${MARK_ARGS[@]+"${MARK_ARGS[@]}"} --line "$ROW_LOCATION" ${args[@]+"${args[@]}"} 2>"$work/ctx.err"); then
    o=$(new_output) || exit $?
    cat "$work/ctx.err" >"$o"
    cat "$work/ctx.err" >&2
    finish failed "$o"
  fi
  {
    printf 'state\t%s\nowner\t%s\nstart\t%s\nhead\t%s\nwaited\t%s\nbackend\t%s\nsession\t%s\n' \
      "$STATE" "$OWNER" "$START" "$HEAD0" "$WAITED" "$BACKEND" "$SESSION"
    [ ${#FP_ARGS[@]} -eq 0 ] || printf 'fingerprint\t%s\ndigest\t%s\n' "${FP_ARGS[1]}" "${FP_ARGS[3]}"
    local i
    for ((i = 1; i < ${#HOLDER_ARGS[@]}; i += 2)); do printf 'holder\t%s\n' "${HOLDER_ARGS[$i]}"; done
  } >"$PENDING" || die 4 "cannot keep the pending state"
  printf 'run\t%s\n' "$line"
}

cmd_end() {
  parse_step_args "$@"
  [[ $EXIT_CODE =~ ^[0-9]{1,3}$ ]] || die 2 "--exit: not an exit code"
  [ -z "$TIMED_OUT" ] || [[ $TIMED_OUT =~ ^[1-9][0-9]{0,8}$ ]] || die 2 "--timed-out: not whole seconds"
  [ -f "$PENDING" ] && [ ! -L "$PENDING" ] || die 2 "no pending begin for $STEP at $CTX_POINT in run $RUN"
  row_of "$ROW_RUN" "$ROW_POINT" "$STEP"
  local k v fp='' digest=''
  HOLDER_ARGS=()
  while IFS=$TAB read -r k v; do
    case $k in
      state) STATE=$v ;;
      owner) OWNER=$v ;;
      start) START=$v ;;
      head) HEAD0=$v ;;
      waited) WAITED=$v ;;
      backend) BACKEND=$v ;;
      session) [ -n "$SESSION" ] || SESSION=$v ;;
      holder) HOLDER_ARGS+=(--holder "$v") ;;
      fingerprint) fp=$v ;;
      digest) digest=$v ;;
    esac
  done <"$PENDING"
  rm -f "$PENDING"
  FP_ARGS=() POOL_ARGS=() REFIRE_ARGS=()
  [ -z "$REFIRE_OF" ] || REFIRE_ARGS=(--refire-of "$REFIRE_OF")
  # The fingerprint the step ran over, as begin took it.
  [ -z "$fp" ] || FP_ARGS=(--fingerprint "$fp" --args-digest "$digest")
  if [ -n "$ROW_POOL" ] && [ "$STATE" != none ]; then
    POOL_ARGS=(--pool "$ROW_POOL" --wait "$WAITED" ${HOLDER_ARGS[@]+"${HOLDER_ARGS[@]}"})
    [ "$STATE" != unpooled ] || POOL_ARGS+=(--unpooled)
  fi
  local o
  o=$(new_output) || exit $?
  if [ -n "$OUTPUT" ]; then
    cat -- "$OUTPUT" >"$o" 2>/dev/null || printf 'step-run: the output file could not be read\n' >"$o"
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
