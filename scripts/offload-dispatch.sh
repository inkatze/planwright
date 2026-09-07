#!/bin/sh
# offload-dispatch.sh — the /offload dispatch primitive (execution-backends
# Task 6; D-1, REQ-C1.5).
#
# /offload (skills/offload/SKILL.md) selects a rung per the work-placement
# axioms (doctrine/work-placement.md) and dispatches through the backend seam.
# This script is the seam's shell-drivable half: it performs the dispatch for
# the rungs a script can drive and emits the standardized WORKER REPORT — the
# handle plus an observe/attach hint appropriate to the selected backend, per
# its advertised set in the capability contract
# (doctrine/backend-capability-contract.md). A rung with no observe surface
# reports that FACT (act on the completion signal), never an invented hint;
# a failed dispatch produces a visible failure report and a nonzero exit,
# never a silent drop (REQ-C1.5).
#
# Subcommands:
#   dispatch <backend> <prompt-file>
#       Dispatch the petition in <prompt-file> to <backend> and emit the
#       report. Drivable rungs:
#         tmux   — `tmux new-window -d` running an interactive `claude` worker
#                  in the caller's cwd; the window id is the handle. The
#                  petition travels as a FILE READ inside the spawned shell
#                  (`cat` of a fixed argv path), never spliced into the
#                  command line, and no send-keys path exists here (the
#                  never-impersonate discipline, orchestrate-relay.sh).
#         print  — spawn deferred to the human: print the exact launch
#                  command; no process exists until the human runs it.
#       Visibly refused (exit 2, diagnostic on stderr): `subagent` (harness-
#       native — the skill dispatches via its harness Agent tool, then calls
#       `report`), `in-session` (inline work, nothing to dispatch), and the
#       session-grade rows `stream-json-persistent` / `headless-oneshot` —
#       `/offload` drives the tmux and print rungs; the session-grade backends
#       have their own dispatch primitives, driven through `/orchestrate`
#       (fleet-dispatch-headless.sh, fleet-streamjson.sh), not this skill.
#
#   report <backend> <handle>
#       Emit the standardized report for an already-dispatched worker (the
#       harness-native rungs, or a re-report of a known handle). Backends:
#       tmux, subagent.
#
# Report shape: TAB-separated `key<TAB>value` lines —
#   status    dispatched | prepared | reported | failed
#   backend   <name>
#   handle    <handle>  (or the no-process fact for `print`)
#   observe   <read command, or the no-observe-surface fact>
#   attach    <attach hint, or the not-attachable fact>
#   launch    <exact command>            (print only)
#   reason    <failure reason>           (failed only)
# `report` emits `status reported`, never `dispatched`: it validates the
# handle's grammar but verifies no dispatch and no liveness, so its status
# asserts only that a report was produced for a caller-owned handle.
#
# Both launch forms pass `--` before the prompt (end-of-options, verified
# against the running CLI), so petition CONTENT beginning with a dash can
# never be parsed as a `claude` option. The prompt-file path is absolutized
# before dispatch so the later read (the spawned shell's, or the human's for
# `print`) is cwd-independent, and the spawned shell refuses to launch on a
# failed read rather than starting an empty-petition worker. The interactive
# `claude` launches here are not `-p`-family sites, so the non-`--bare`
# launch pin (REQ-A1.5, D-12) does not apply to this script.
#
# Exit codes: 0 success; 1 dispatch failed (failure report emitted); 3 the unit
# is withheld by the admission gate (nothing dispatched); 4 a malformed
# repo-tracked knob and 5 a broken install, the first propagated from the
# launch-tier resolver and the second also raised here when its plan is missing
# a row this reads or carries an out-of-enum tier; 2 usage /
# hostile input / refused backend / missing, empty, unreadable, or unsafe
# prompt file / missing echo-safety helper / internal resolution failure.
#
# Portable POSIX sh + coreutils (bash 3.2 / BSD compatible): no eval, input
# treated as data only (REQ-K1.5). Pathname expansion is disabled (set -f) so
# a token like `*` is taken literally and refused by the grammar, never
# expanded.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=offload-dispatch

# Resolve this script's directory so the sibling echo-safety helper is found
# regardless of the caller's working directory.
script_dir=$(cd "$(dirname "$0")" && pwd) || {
  echo "$me: cannot resolve the script's own directory" >&2
  exit 2
}
echo_safety="$script_dir/echo-safety.sh"
if [ ! -r "$echo_safety" ]; then
  echo "$me: required helper $echo_safety missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$echo_safety"

# The launch-tier plan comes from the shared apply layer, never from a local
# copy of the selection rules (model-allocation D-5, REQ-B1.1).
apply_helper="$script_dir/allocation-apply.sh"

# A literal newline, for the prompt-file path safety check below.
nl='
'

# The tmux stderr-capture file (cmd_dispatch), cleaned on any exit — including
# a signal landing inside the tmux call — via the sibling trap idiom
# (obs-record.sh): EXIT does the cleanup, INT/TERM route through it.
tmux_err=
trap '[ -z "$tmux_err" ] || rm -f "$tmux_err"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
  echo "$me: usage: $me <dispatch <backend> <prompt-file> [--unit <id>] | report <backend> <handle>>" >&2
}

# --------------------------------------------------------------------------
# Launch-tier resolution (model-allocation Task 6; D-4, D-10, REQ-B1.1,
# REQ-B1.2). Every dispatch consults the shared resolver before it launches,
# and applies what the selected backend advertises it can set. With the shipped
# `inherit` default nothing is applied and the launch is exactly today's, with
# an audit row saying it inherited (D-13).
#
# Sets TIER_MODEL and TIER_EFFORT to a value to apply, or `inherit` to apply
# nothing. Never builds a command line: the caller splices these in as discrete
# argv elements.
# --------------------------------------------------------------------------
TIER_MODEL=inherit
TIER_EFFORT=inherit

resolve_tier() {
  # $1 backend, $2 unit
  if [ ! -r "$apply_helper" ]; then
    echo "$me: required helper $apply_helper missing or not readable" >&2
    exit 2
  fi
  rt_plan=$(/bin/sh "$apply_helper" plan --key offload --backend "$1" --unit "$2")
  rt_rc=$?
  if [ "$rt_rc" -ne 0 ]; then
    # ONLY an unreachable allocation store degrades, and it says so on its own
    # exit code (6). That is an availability question: refusing to dispatch
    # work because an audit store is missing trades a real capability for a
    # bookkeeping one, so the posture is the ledger's own degraded mode
    # (REQ-F1.1) — launch at the ambient tier, surfaced, never silent.
    #
    # Everything else is FATAL. A rejected argument, a withheld unit, a
    # malformed knob, a broken install and a failed audit write are all
    # different faults, and laundering any of them through the degrade branch
    # would produce exactly the unaudited ambient launch REQ-B1.2 exists to
    # prevent — while blaming a store that was never touched.
    if [ "$rt_rc" -ne 6 ]; then
      case "$rt_rc" in
        3) echo "$me: dispatch: the unit is withheld by the admission gate; not dispatching" >&2 ;;
        *) echo "$me: dispatch: could not resolve a launch tier (allocation-apply exit $rt_rc)" >&2 ;;
      esac
      exit "$rt_rc"
    fi
    echo "$me: dispatch: the allocation store is unreachable; launching at the ambient model and effort with the tier unrecorded (degraded)" >&2
    TIER_MODEL=inherit
    TIER_EFFORT=inherit
    return 0
  fi
  TIER_MODEL=$(printf '%s\n' "$rt_plan" | awk -F '\t' '$1 == "model" { print $2 }')
  TIER_EFFORT=$(printf '%s\n' "$rt_plan" | awk -F '\t' '$1 == "effort" { print $2 }')
  # A plan that exits 0 without the rows this reads is a resolver from another
  # version, not a bad argument. Named before the enum check so the diagnostic
  # says the row is absent rather than calling an empty value out-of-enum.
  if [ -z "$TIER_MODEL" ] || [ -z "$TIER_EFFORT" ]; then
    echo "$me: dispatch: the resolver's plan is missing a model or effort row — broken or outdated install" >&2
    exit 5
  fi
  # Emission-boundary enum check, the same posture as the prompt-file charset
  # check below: these values become argv elements and, for the print rung,
  # words of a command a human runs. A value outside the closed enum means a
  # broken install upstream, and it stops here rather than being emitted — on
  # the install exit code, not the usage one this used to borrow.
  case "$TIER_MODEL" in
    inherit | fable | opus | sonnet | haiku) ;;
    *)
      echo "$me: dispatch: the resolver returned an out-of-enum model — broken or outdated install" >&2
      exit 5
      ;;
  esac
  case "$TIER_EFFORT" in
    inherit | low | medium | high) ;;
    *)
      echo "$me: dispatch: the resolver returned an out-of-enum effort — broken or outdated install" >&2
      exit 5
      ;;
  esac
}

# The unit a dispatch records its allocation against. The caller names it with
# `--unit`; absent that, it is derived from the petition file so a dispatch
# still lands in a ledger of its own rather than a shared bucket.
derive_unit() {
  du_v="offload:$(basename -- "$1")"
  case $du_v in
    *[!A-Za-z0-9._=@:-]*) du_v='' ;;
  esac
  if [ -z "$du_v" ] || [ "${#du_v}" -gt 128 ]; then
    du_v="offload:petition"
  fi
  printf '%s' "$du_v"
}

# Per-backend handle grammar, mirroring orchestrate-relay.sh: input is DATA —
# a case-glob whitelist, never evaluated. Empty, leading-dash (option
# injection), and over-length tokens are refused first; then the per-backend
# charset, which excludes whitespace, quotes, `$`, backtick, `;` `|` `&`,
# parentheses, redirects, glob metacharacters, and the newline.
valid_handle() {
  case "$2" in
    '') return 1 ;;
    -*) return 1 ;;
  esac
  [ "${#2}" -le 128 ] || return 1
  case "$1" in
    tmux)
      case "$2" in
        *[!A-Za-z0-9_@%:./-]*) return 1 ;;
      esac
      ;;
    subagent)
      case "$2" in
        *[!A-Za-z0-9_.-]*) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
  return 0
}

# A prompt file must be a readable, non-empty regular file whose path is safe
# to place inside a single-quoted shell literal in an emitted command (no
# single quote, no newline, no control byte) — mirroring orchestrate-relay's
# message-file check. The skill writes the petition to a temp file it
# controls; this guards the emission boundary regardless.
valid_promptfile() {
  [ -f "$1" ] || return 1
  [ -r "$1" ] || return 1
  [ -s "$1" ] || return 1
  case "$1" in
    *"'"*) return 1 ;;
    *"$nl"*) return 1 ;;
  esac
  [ "$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237')" = "$1" ] || return 1
  return 0
}

reject_handle() {
  echo "$me: refusing invalid $1 handle (validated before use, never interpolated)" >&2
  exit 2
}

# register_dispatch <handle> <backend> [<death-handle>] — write the dispatch
# record through the one registration seam (fleet-lifecycle-closure Task 3;
# REQ-E1.1, REQ-E1.4). Best-effort BY CONTRACT: the exit is discarded so a
# registry that cannot be written never fails a dispatch that already
# succeeded, while stderr is deliberately NOT discarded — a dispatch the fleet
# has no record of is exactly the leak this bundle exists to close, and the
# operator has to be able to see it happen.
#
# Readable, not executable: the call is `/bin/sh <path>`, so the exec bit is
# not what it depends on, and gating on `-x` would let a checkout with
# core.fileMode=false silently switch registration off with nothing on stderr.
register_dispatch() {
  rd_reg="$script_dir/fleet-register.sh"
  if [ ! -r "$rd_reg" ]; then
    printf '%s\n' "$me: cannot register $1: $rd_reg is missing or unreadable; this worker will not appear in the fleet inventory" >&2
    return 0
  fi
  rd_death=${3:-}
  set -- --handle "$1" --scope offload --backend "$2"
  [ -n "$rd_death" ] && set -- "$@" --death-handle "$rd_death"
  /bin/sh "$rd_reg" "$@" >/dev/null </dev/null || true
}

# offload_handle <prefix> — a handle unique over TIME, not just within this
# process. A bare `$$` recycles within hours on a busy host, and the registry is
# last-record-wins per handle: a later dispatch drawing the same pid would
# silently mask an earlier record, which for the print rung is the only evidence
# that unit exists at all (REQ-D1.8).
offload_handle() {
  oh_now=$(date +%s 2>/dev/null) || oh_now=0
  case $oh_now in
    '' | *[!0-9]*) oh_now=0 ;;
  esac
  printf '%s-%s-%s\n' "$1" "$oh_now" "$$"
}

# Emit the observe/attach hint pair for a backend, per its advertised set in
# the capability contract: tmux advertises can_observe=true and
# interactive=true; subagent advertises neither, so its report carries the
# facts, not invented hints.
emit_hints() {
  case "$1" in
    tmux)
      printf "observe\ttmux capture-pane -p -t '%s'\n" "$2"
      printf "attach\ttmux select-window -t '%s'  (from outside tmux: tmux attach)\n" "$2"
      ;;
    subagent)
      printf 'observe\tnone: no observe surface on this rung; act on the completion signal\n'
      printf 'attach\tnone: in-harness worker, not human-attachable\n'
      ;;
    *)
      # Defensive: both callers whitelist first, so this arm is unreachable
      # today — it exists so a future backend addition fails loudly rather
      # than silently emitting a report missing its observe/attach lines.
      echo "$me: internal error: no hint arm for backend '$1'" >&2
      exit 2
      ;;
  esac
}

cmd_report() {
  backend=$1
  handle=$2
  case "$backend" in
    tmux | subagent) ;;
    *)
      echo "$me: report: unknown backend '$(sanitize_printable "$backend" "(unprintable)")'" >&2
      exit 2
      ;;
  esac
  valid_handle "$backend" "$handle" || reject_handle "$backend"
  # The subagent rung's ONLY seam (fleet-lifecycle-closure Task 3; REQ-E1.1).
  # Its spawn is harness-native — the skill dispatches through the harness Agent
  # tool and then calls `report` — so this is the single point at which a
  # subagent worker can enter the fleet's inventory, and leaving it out would
  # make "every dispatch seam registers" false for a rung that really does
  # produce a live worker. Its death handle is `none`: the subagent has no
  # separate OS process, it dies with the tower, and the capability contract
  # marks the whole process-tree class trivial for this rung.
  #
  # A `report` for a tmux handle is a RE-report of a worker `dispatch` already
  # registered, so it registers nothing: this subcommand verifies no dispatch
  # and no liveness, and a re-report is not evidence of a new one.
  [ "$backend" = subagent ] && register_dispatch "$handle" subagent none
  # `reported`, never `dispatched`: this subcommand verified no dispatch and
  # no liveness — only the handle's grammar (see the header contract).
  printf 'status\treported\n'
  printf 'backend\t%s\n' "$backend"
  printf 'handle\t%s\n' "$handle"
  emit_hints "$backend" "$handle"
}

cmd_dispatch() {
  backend=$1
  promptfile=$2
  unit=${3:-}
  case "$backend" in
    tmux | print) ;;
    subagent)
      echo "$me: dispatch: subagent is harness-native — dispatch via the harness Agent tool, then run: $me report subagent <handle>" >&2
      exit 2
      ;;
    in-session)
      echo "$me: dispatch: in-session is inline work in the caller's own session — nothing to dispatch" >&2
      exit 2
      ;;
    stream-json-persistent | headless-oneshot)
      echo "$me: dispatch: '$backend' is a session-grade rung /offload does not drive (it dispatches the tmux and print rungs); the session-grade backends are dispatched through /orchestrate's own primitives" >&2
      exit 2
      ;;
    *)
      echo "$me: dispatch: unknown backend '$(sanitize_printable "$backend" "(unprintable)")'" >&2
      exit 2
      ;;
  esac
  # Absolutize the prompt-file path BEFORE validation so (a) the emission-
  # boundary charset check covers the exact string that is emitted or passed,
  # and (b) the later read — the spawned shell's, or the human's for `print`,
  # both of which happen in an arbitrary cwd — is cwd-independent.
  case "$promptfile" in
    /*) : ;;
    *)
      pf_dir=$(cd -- "$(dirname -- "$promptfile")" 2>/dev/null && pwd) || {
        echo "$me: dispatch: cannot resolve the prompt file's directory: '$(sanitize_printable "$promptfile" "(unprintable)")'" >&2
        exit 2
      }
      promptfile="$pf_dir/$(basename -- "$promptfile")"
      ;;
  esac
  if ! valid_promptfile "$promptfile"; then
    echo "$me: dispatch: prompt file missing, empty, unreadable, or unsafe: '$(sanitize_printable "$promptfile" "(unprintable)")'" >&2
    exit 2
  fi

  [ -n "$unit" ] || unit=$(derive_unit "$promptfile")
  resolve_tier "$backend" "$unit"

  case "$backend" in
    print)
      # A print-rung unit spawns nothing until a human runs the command, so its
      # dispatch record is the ONLY evidence it exists (REQ-D1.8) — which is
      # precisely why it is registered, with `none` as its death handle: this
      # rung has no process to attribute or terminate, and saying so is not the
      # same as leaving the column blank.
      register_dispatch "$(offload_handle print)" print none
      printf 'status\tprepared\n'
      printf 'backend\tprint\n'
      printf 'handle\tnone: no process exists until the human runs the launch command\n'
      # The printed command line IS this rung's launch, so a resolved tier has
      # to travel in it as its own words — that is what `print` advertising
      # tier_control means. The values are enum-checked at resolve_tier, so
      # nothing outside the closed model/effort sets can reach this line.
      pf_tier=''
      [ "$TIER_MODEL" = inherit ] || pf_tier="$pf_tier --model $TIER_MODEL"
      [ "$TIER_EFFORT" = inherit ] || pf_tier="$pf_tier --effort $TIER_EFFORT"
      printf "launch\tclaude%s -- \"\$(cat -- '%s')\"\n" "$pf_tier" "$promptfile"
      printf 'observe\tnone: spawn deferred to the human\n'
      printf 'attach\trun the launch command in your own terminal\n'
      return 0
      ;;
  esac

  # tmux: spawn a detached window running an interactive claude worker in the
  # caller's cwd. The petition is read from the prompt file INSIDE the spawned
  # shell via a fixed argv path — the content never appears on this command
  # line — with `--` pinning it as the prompt (never an option), and a failed
  # read refuses to launch rather than starting an empty-petition worker. The
  # printed window id is the stable handle. tmux's stderr is captured
  # SEPARATELY from the id: folding the streams together would turn a
  # successful spawn with stderr chatter into a false failure report over a
  # live, unreported worker.
  cwd=$(pwd) || {
    echo "$me: dispatch: cannot resolve the current directory" >&2
    exit 2
  }
  tmux_err=$(mktemp "${TMPDIR:-/tmp}/offload-dispatch-err.XXXXXX") || {
    echo "$me: dispatch: cannot create the stderr capture file" >&2
    exit 2
  }
  # A resolved tier reaches the worker as DISCRETE argv elements appended after
  # the prompt path, consumed by the spawned shell's `"$@"` — never spliced
  # into the `sh -c` script text, which is what the argv-discipline clause of
  # REQ-B1.2 is about. Built with `set --` so each flag and its value stay
  # separate words with no re-splitting anywhere in the path.
  set -- offload-worker "$promptfile"
  [ "$TIER_MODEL" = inherit ] || set -- "$@" --model "$TIER_MODEL"
  [ "$TIER_EFFORT" = inherit ] || set -- "$@" --effort "$TIER_EFFORT"
  # shellcheck disable=SC2016 # single quotes are deliberate: $1/$@ expand in
  # the SPAWNED shell (argv-passed prompt path and tier flags), never here — no
  # content splicing.
  handle=$(tmux new-window -d -P -F '#{window_id}' -n "offload-$$" -c "$cwd" \
    /bin/sh -c 'p=$(cat -- "$1") || exit 1; shift; exec claude "$@" -- "$p"' \
    "$@" 2>"$tmux_err")
  rc=$?
  err_text=$(cat "$tmux_err" 2>/dev/null)
  rm -f "$tmux_err"
  if [ "$rc" -ne 0 ]; then
    [ -n "$err_text" ] || err_text="(no output)"
    printf 'status\tfailed\n'
    printf 'backend\ttmux\n'
    printf 'reason\ttmux new-window exited %s: %s\n' "$rc" "$(sanitize_printable "$err_text" "(unprintable)")"
    echo "$me: dispatch failed: tmux new-window exited $rc" >&2
    exit 1
  fi
  if ! valid_handle tmux "$handle"; then
    printf 'status\tfailed\n'
    printf 'backend\ttmux\n'
    printf 'reason\ttmux returned an unusable window id\n'
    echo "$me: dispatch failed: tmux returned an unusable window id: '$(sanitize_printable "$handle" "(unprintable)")'" >&2
    exit 1
  fi
  # The death handle needs the window's SESSION as well as its id, asked of the
  # already-validated window id rather than reconstructed from a listing. A
  # session name outside the death-evidence token charset (it may carry a `:`
  # or `/`, which that predicate refuses) is left out rather than allowed to
  # sink the whole record: an inventory entry with one blank column beats no
  # entry at all.
  death=''
  sess=$(tmux display-message -p -t "$handle" '#{session_name}' 2>/dev/null) || sess=''
  # BOTH halves are checked against the death-evidence token charset, not just
  # the session: `valid_handle tmux` above admits `:` and `/`, which that
  # predicate refuses, so an unchecked window id would build a death handle the
  # store rejects — and a rejected field costs the WHOLE record rather than the
  # one column. An inventory entry with a blank column beats no entry at all.
  for tok in "$sess" "$handle"; do
    case $tok in
      '' | -* | *[!A-Za-z0-9._@%-]*)
        sess=''
        break
        ;;
    esac
    [ "${#tok}" -le 128 ] || {
      sess=''
      break
    }
  done
  [ -n "$sess" ] && death="tmux-window $sess $handle"
  register_dispatch "$handle" tmux "$death"
  printf 'status\tdispatched\n'
  printf 'backend\ttmux\n'
  printf 'handle\t%s\n' "$handle"
  emit_hints tmux "$handle"
}

[ "$#" -ge 1 ] || {
  usage
  exit 2
}
sub=$1
shift
case "$sub" in
  dispatch)
    [ "$#" -ge 2 ] || {
      usage
      exit 2
    }
    d_backend=$1
    d_promptfile=$2
    shift 2
    d_unit=''
    while [ "$#" -gt 0 ]; do
      case $1 in
        --unit)
          [ "$#" -ge 2 ] || {
            usage
            exit 2
          }
          d_unit=$2
          shift 2
          ;;
        *)
          usage
          exit 2
          ;;
      esac
    done
    if [ -n "$d_unit" ]; then
      case $d_unit in
        *[!A-Za-z0-9._=@:-]*)
          echo "$me: dispatch: refusing malformed --unit '$(sanitize_printable "$d_unit" "(unprintable)")'" >&2
          exit 2
          ;;
      esac
      if [ "${#d_unit}" -gt 128 ]; then
        echo "$me: dispatch: --unit exceeds 128 bytes" >&2
        exit 2
      fi
    fi
    cmd_dispatch "$d_backend" "$d_promptfile" "$d_unit"
    ;;
  report)
    [ "$#" -eq 2 ] || {
      usage
      exit 2
    }
    cmd_report "$1" "$2"
    ;;
  *)
    usage
    exit 2
    ;;
esac
