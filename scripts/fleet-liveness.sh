#!/bin/sh
# fleet-liveness.sh — push-based worker liveness, the five-state classifier,
# and the crash-loop backoff (fleet-autonomy Task 2: D-1, D-2, D-3;
# REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4).
#
# THREE MECHANISMS, ONE STORE. All three write worker state through
# fleet-attention.sh's existing per-worker state store (never a second
# store), under the same cross-spec fleet home and advisory lock
# (fleet-state.sh), so push, classification, and backoff can never disagree
# about where truth lives. Precedence between the push path and the periodic
# reconcile (REQ-A1.8, a later task) is last-write-wins by COMMIT-TIME
# timestamp — fleet-attention stamps the heartbeat under the lock, so
# whichever writer commits later wins, which is exactly the kickoff risk
# row 5 rule (a reconcile that started before a fresher push cannot commit
# an older stamp after it).
#
# 1. HOOK PUSH (`hook <event>`, D-1/REQ-A1.1). Registered by the plugin's
#    hooks/hooks.json for every session; the DISPATCH-TIME ENV CONTRACT is
#    the identity gate: a dispatched worker session is launched with
#    PLANWRIGHT_WORKER_HANDLE / PLANWRIGHT_WORKER_SCOPE in its environment
#    (hook commands inherit the launched process env — verified against the
#    current hooks reference, kickoff-brief Task 2 research notes), and a
#    session without both is a silent no-op. Event -> transition map:
#      stop                Stop              -> idle   (working -> idle)
#      permission-request  PermissionRequest -> awaiting-input (decide) +
#                          a pending-permission marker
#      post-tool-use       PostToolUse       -> working, ONLY when a pending-
#                          permission marker exists (the documented
#                          awaiting-human -> working INFERENCE, D-1: no
#                          permission-resolution hook exists)
#      session-end         SessionEnd        -> ended  (session termination)
#      stop-failure        StopFailure       -> hung   (turn ended on an API
#                          error resembles a stopped-responding worker —
#                          the kickoff risk row 27 mapping, decided here)
#    THE ESCALATION-PRESERVE GUARD (REQ-A1.3): a downgrade push (stop /
#    session-end / stop-failure) never overwrites an awaiting-input row that
#    has NO pending-permission marker — that row is a queued human decision
#    (a flailing escalation, a crash-loop disable), and hooks must never
#    auto-resolve it. The deny path (kickoff risk row 28): a denied
#    permission whose turn ends with no further tool use clears on the Stop
#    push (marker present -> idle); any residue beyond that heals on the
#    REQ-A1.8 reconcile sweep, which this bundle documents as the
#    correctness backstop for every missed or dropped push.
#    HOOK EXIT DISCIPLINE: a valid event always exits 0 — for the Stop hook
#    an exit 2 would BLOCK the worker's own stop, and any non-zero is noise
#    in someone else's session — so runtime failures warn on stderr and rely
#    on the reconcile backstop (D-1); only a malformed invocation (unknown
#    event: a wiring bug in hooks.json, not a runtime state) exits 2. The
#    hook payload on stdin is drained, never parsed: identity comes from the
#    env contract, so no payload field is ever interpolated anywhere
#    (kickoff risk row 25).
#
# 2. FIVE-STATE CLASSIFIER (`classify`, D-2/REQ-A1.2). Resolves exactly one
#    of working | idle | hung | awaiting-human | flailing from the store row
#    plus caller-supplied observation evidence (all grammar-validated tokens,
#    never raw pane text — kickoff risk row 23; a capture-pane consumer
#    sanitizes before anything reaches this script). Precedence, and the
#    documented boundaries (risk rows 29 and 33):
#      awaiting-input row                  -> awaiting-human
#      idle / pr-ready / merged / done /
#        ended row                         -> idle (no in-flight turn; no
#                                             progress expected; ended is the
#                                             terminal-idle mapping)
#      hung row (a StopFailure push)       -> hung (trust the push; recovery
#                                             overwrites via a later push or
#                                             reconcile heartbeat)
#      working row, or NO row              -> the evidence logic below; a
#                                             missing row with no heartbeat
#                                             evidence is the STARTUP DEFAULT
#                                             `working` (risk 33: dispatch
#                                             implies immediate activity)
#    Evidence logic (heartbeat = the store's commit-time stamp, or the
#    caller's --heartbeat override):
#      heartbeat stopped (age >= fleet_hung_heartbeat_seconds):
#        with an --evidence handle, the POSITIVE-EVIDENCE predicate
#        (fleet-death-evidence.sh, D-5/REQ-A1.7) is consulted: alive (a
#        wedged harness) and dead both confirm hung; UNKNOWN (lost
#        observability) REFUSES the hung classification and stays working
#        with a warning — silence is never death (the 2026-06-12 posture).
#        With no handle available, elapsed time alone is admissible: that is
#        the classifier's own documented timeout-vs-evidence boundary (risk
#        29) — classification is inherently time-based where no
#        authoritative query exists; REQ-A1.7's gate applies wherever one
#        does.
#      heartbeat fresh: no forward progress (the same --progress token, e.g.
#        the worker branch's HEAD sha) across fleet_flailing_threshold
#        consecutive observations -> flailing; else working.
#    A flailing classification ESCALATES AND NOTHING ELSE (REQ-A1.3): it
#    upserts exactly one decision-queue entry (the "this task may be stuck"
#    fork — an upsert, so repeated classification never duplicates it) and
#    records the escalation through the audit trail; there is no restart and
#    no nudge path in this script at all. Routine classification is NOT
#    audited (risk row 31: the trail records actions, not status noise).
#    Observations are kept per worker under <fleet-home>/liveness/, trimmed
#    to the last 50 rows (the risk-18 windowing spirit), written
#    copy-append-rename. The classifier assumes one observer per worker (the
#    tower / reconcile sweep); a raced append self-heals on the next
#    observation (D-1).
#
# 3. CRASH-LOOP BACKOFF (`crash-record` / `crash-check` / `crash-reset`,
#    D-3/REQ-A1.4). A relaunch-supervisor calls crash-record after each
#    worker crash and crash-check before any relaunch. The delay doubles
#    from fleet_crash_backoff_base_seconds and caps at 3600s; at
#    fleet_crash_disable_threshold consecutive failures the worker is
#    DISABLED — no further relaunch is ever authorized — and the disable is
#    escalated as a decision-queue entry (the human decides: investigate,
#    reset, park). The PM2 / supervisord / 3-strike shape D-3 cites.
#    crash-check consults the operator kill-switch (fleet-daemon-gate.sh,
#    D-15) before authorizing: a relaunch is a daemon restart action, so a
#    paused daemon layer short-circuits it (classification and crash
#    BOOKKEEPING are not gated — pausing the record of what happened would
#    hide problems, and surfacing to a human must never be paused: degrade
#    capability, never safety). Counter updates run under the fleet lock
#    (the risk row 6/8 read-modify-write discipline); backoff and disable
#    actions log through the audit trail (REQ-F1.4).
#
# Usage:
#   fleet-liveness.sh hook <stop|permission-request|post-tool-use|session-end|stop-failure>
#       The registered hook handler (identity from the env contract; the
#       payload is drained on the worker path, never parsed). Exits 0 for
#       every valid invocation, including runtime failures and signals;
#       exit 2 only on a malformed invocation (wrong arg count or an
#       unknown event token — a hooks.json wiring bug).
#   fleet-liveness.sh push-capable <backend>
#       Which liveness mechanism the backend gets: prints `push` (exit 0)
#       for tmux (the one backend whose dispatched process inherits the
#       identity env and fires plugin hooks), `observe` (exit 1) for
#       subagent / print / in-session, where the existing observation path
#       (orchestrate-relay.sh observe-command / tower-inline; print is
#       human-run and contract-exempt from liveness) remains the mechanism
#       — the REQ-A1.1 graceful fallback, kickoff risk row 16. Unknown
#       backend: exit 2.
#   fleet-liveness.sh classify <worker> <scope> [--now <epoch>]
#       [--heartbeat <epoch>] [--progress <token>]
#       [--evidence <class> <args...>]
#       Print exactly one of working|idle|hung|awaiting-human|flailing.
#       Exit 4/5: propagated config/install hard-fails from the knob
#       resolver.
#   fleet-liveness.sh crash-record <worker> <scope> [--now <epoch>]
#       Record one crash; prints `<count> <delay>` or `disabled <count>`
#       BEFORE the escalation/audit side effects — the counter is durable
#       once the line prints, so never re-invoke for the same crash on a
#       non-zero exit (a retry double-counts; a lost disable escalation
#       self-heals via crash-check). Exit 4/5: propagated config/install
#       hard-fails.
#   fleet-liveness.sh crash-check <worker> [--now <epoch>]
#       Exit 0 relaunch authorized; 1 backing off or daemon layer paused;
#       3 disabled (never relaunch; reported ahead of the kill-switch so
#       the terminal state is never masked, and the disable escalation is
#       re-upserted if missing); 4/5 propagated config/install hard-fails.
#   fleet-liveness.sh crash-reset <worker>
#       Clear the consecutive-failure streak (a healthy run). Exit 2 when
#       the record could not be removed (the streak did NOT clear).
#
# Exit codes: per subcommand above; 2 usage error, refused hostile input, or
#   a filesystem/lock error (fail closed) on the non-hook subcommands.
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling): `date
# +%s`, awk, a fractional `sleep` (the lock retry, as the sibling fleet
# scripts use). No eval, no jq (REQ-K1.5) — which is also why the hook
# payload is never parsed. All input is data. Pathname expansion is disabled
# (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# The canonical echo-discipline sanitizer (doctrine/security-posture.md),
# sourced as the sibling fleet scripts do; a missing helper is a broken
# install.
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FS="$script_dir/fleet-state.sh"
FA="$script_dir/fleet-attention.sh"
FAU="$script_dir/fleet-audit.sh"
FDE="$script_dir/fleet-death-evidence.sh"
FDG="$script_dir/fleet-daemon-gate.sh"
RCK="$script_dir/resolve-config-knob.sh"
TAB=$(printf '\t')

# The fleet field grammar, byte-identical to fleet-state.sh /
# fleet-attention.sh valid_field: excludes path separators (a `.`/`..`
# dot-run is inert without a slash), whitespace, and any control or shell
# metacharacter; bounded to 128 chars. Worker handles reach liveness file
# paths below, so this runs before any path is built.
valid_field() {
  vf_v=$1
  case $vf_v in
    "" | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#vf_v}" -le 128 ]
}

# A non-negative epoch/seconds integer: no sign, no leading zero (shell
# arithmetic would read it as octal), at most 15 digits (the overflow guard
# the sibling resolvers use).
valid_epoch() {
  ve_v=$1
  case $ve_v in
    "" | *[!0-9]* | 0?*) return 1 ;;
  esac
  [ "${#ve_v}" -le 15 ]
}

now_epoch() {
  ne_v=$(date +%s)
  case $ne_v in
    "" | *[!0-9]*) printf '' ;;
    *) printf '%s' "$ne_v" ;;
  esac
}

# knob <key> <fallback> — one posint knob through the shared resolver
# (D-22/REQ-G1.5). A resolver hard-fail (4 team-shared malformed, 5 broken
# install) propagates: never run under unknown shared configuration. A
# missing/non-executable resolver is itself the broken-install case (exit 5,
# the fleet-daemon-gate discipline), never a raw shell 126/127.
knob() {
  if [ ! -x "$RCK" ]; then
    echo "fleet-liveness: knob resolver '$RCK' is missing or not executable (broken install)" >&2
    return 5
  fi
  k_v=$("$RCK" --key "$1" --type posint --fallback "$2") || return $?
  printf '%s' "$k_v"
}

# --- the fleet advisory lock, consumed through fleet-state.sh's exposed
#     primitive, with the sibling scripts' spin + trap-release discipline so
#     a counter update is never dropped under contention and a signal never
#     leaves the shared lock held.
HOLD_LOCK=0
trap 'release_lock' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
acquire_lock() {
  al_tries=0
  while [ "$al_tries" -lt 1000 ]; do
    "$FS" lock >/dev/null 2>&1
    al_rc=$?
    case $al_rc in
      0)
        HOLD_LOCK=1
        return 0
        ;;
      1) ;; # a live holder has it — retry
      *)
        echo "fleet-liveness: cannot acquire the fleet lock (fleet-state exit $al_rc)" >&2
        return 2
        ;;
    esac
    al_tries=$((al_tries + 1))
    sleep 0.02
  done
  echo "fleet-liveness: gave up acquiring the fleet lock after contention" >&2
  return 2
}
release_lock() {
  if [ "$HOLD_LOCK" = 1 ]; then
    "$FS" unlock >/dev/null 2>&1 || true
    HOLD_LOCK=0
  fi
}

# The attention record's field indices this script reads (fleet-attention.sh
# upsert_row is the single authority for the 8-field layout:
# worker/scope/state/heartbeat/priority/question/default/options — named here
# so the positional coupling is explicit and single-sourced in this file).
FIELD_SCOPE=2
FIELD_STATE=3
FIELD_HEARTBEAT=4

# store_row_field <root> <worker> <field-index> — print one field of the
# worker's 8-field attention record, or nothing when no row exists. The ""
# concatenation pins awk to string comparison for numeric-looking handles
# (the fleet-attention upsert discipline).
store_row_field() {
  srf_store="$1/attention/state"
  [ -f "$srf_store" ] || return 0
  awk -F "$TAB" -v w="$2" -v f="$3" '($1 "") == (w "") { print $f }' "$srf_store"
}

# crash_read <root> <worker> — print "count next_allowed disabled" (0 0 0
# when no record). The record is a single space-separated line, written
# atomically (temp + rename), so a lockless read never sees a torn value.
crash_read() {
  cr_file="$1/liveness/crash/$2"
  cr_line=$(cat "$cr_file" 2>/dev/null) || cr_line=""
  # shellcheck disable=SC2086
  set -- $cr_line
  cr_c="${1:-0}"
  cr_n="${2:-0}"
  cr_d="${3:-0}"
  case $cr_c in "" | *[!0-9]*) cr_c=0 ;; esac
  case $cr_n in "" | *[!0-9]*) cr_n=0 ;; esac
  case $cr_d in 0 | 1) ;; *) cr_d=0 ;; esac
  printf '%s %s %s' "$cr_c" "$cr_n" "$cr_d"
}

# atomic_write_file <file> <content> — same-dir temp + rename.
atomic_write_file() {
  awf_file=$1
  awf_val=$2
  awf_dir=$(dirname "$awf_file")
  awf_tmp=$(mktemp "$awf_dir/.tmp.XXXXXX") || return 1
  if ! printf '%s\n' "$awf_val" >"$awf_tmp"; then
    rm -f "$awf_tmp"
    return 1
  fi
  if ! mv -f "$awf_tmp" "$awf_file"; then
    rm -f "$awf_tmp"
    return 1
  fi
  return 0
}

if [ "$#" -lt 1 ]; then
  echo "usage: fleet-liveness.sh hook|push-capable|classify|crash-record|crash-check|crash-reset [args]" >&2
  exit 2
fi
cmd=$1
shift

case "$cmd" in
  hook)
    # Signals must not turn a valid hook invocation into a non-zero exit
    # (the always-exit-0 discipline): an INT/TERM delivered to the worker's
    # process group mid-hook would otherwise ride the file-level 130/143
    # traps out as a non-zero hook exit. No lock is ever held in this arm,
    # so exiting 0 on a signal abandons nothing.
    trap 'exit 0' INT TERM
    if [ "$#" -ne 1 ]; then
      echo "usage: fleet-liveness.sh hook <stop|permission-request|post-tool-use|session-end|stop-failure>" >&2
      exit 2
    fi
    event=$1
    case "$event" in
      stop | permission-request | post-tool-use | session-end | stop-failure) ;;
      *)
        # A malformed invocation (unknown event, wrong arg count above) is a
        # hooks.json wiring bug, not a runtime state: the hook-path exit 2.
        echo "fleet-liveness: unknown hook event '$(sanitize_printable "$event" "(unprintable event)")'" >&2
        exit 2
        ;;
    esac
    handle="${PLANWRIGHT_WORKER_HANDLE:-}"
    scope="${PLANWRIGHT_WORKER_SCOPE:-}"
    # The identity gate, BEFORE the stdin drain: not a dispatched worker
    # session — a clean, silent no-op with no further process spawned. The
    # plugin registers these hooks for EVERY session; only dispatched
    # workers may write, and nobody else's session may be slowed or
    # disturbed (exiting without reading the payload is the norm for hook
    # commands that ignore stdin).
    if [ -z "$handle" ] && [ -z "$scope" ]; then
      exit 0
    fi
    # The payload is deliberately unparsed (risk 25): identity comes from
    # the env contract. Drain it only on the worker path, where the handler
    # does real work anyway.
    cat >/dev/null 2>&1 || true
    # A hostile or half-set identity is refused with NO write — but still
    # exit 0: a hook exit must never block the hosting session.
    if ! valid_field "$handle" || ! valid_field "$scope"; then
      echo "fleet-liveness: refusing malformed worker identity env (PLANWRIGHT_WORKER_HANDLE/PLANWRIGHT_WORKER_SCOPE); no state written" >&2
      exit 0
    fi
    root=$("$FS" root) || {
      echo "fleet-liveness: cannot resolve the fleet home; state push dropped (the reconcile sweep self-heals, D-1)" >&2
      exit 0
    }
    marker="$root/liveness/pending/$handle"
    case "$event" in
      permission-request)
        # Decide BEFORE the marker: a PostToolUse racing this handler (a
        # parallel tool call in the same session) that saw the marker before
        # the decide committed would clear the marker and strand the
        # awaiting-input row as a phantom escalation. Decide-first narrows
        # the phantom window to a marker-WRITE failure (rare, warned below,
        # healed by the reconcile), instead of an any-concurrent-tool race.
        "$FA" decide "$handle" "$scope" \
          "Worker is awaiting a permission decision in its session" \
          "answer in the worker session" \
          "approve in the worker session|deny in the worker session" \
          normal >/dev/null 2>&1 || {
          echo "fleet-liveness: state push (awaiting-input) failed; reconcile self-heals (D-1)" >&2
          exit 0
        }
        # Temp + rename (never a truncating `>` redirect): the redirect
        # would follow a symlink planted at the marker path, while mv
        # replaces the link itself (the atomic_write_file discipline).
        if ! mkdir -p "$root/liveness/pending" 2>/dev/null \
          || ! atomic_write_file "$marker" "" 2>/dev/null; then
          echo "fleet-liveness: pending-permission marker write failed; the awaiting-input row clears on the next stop/reconcile" >&2
        fi
        exit 0
        ;;
      post-tool-use)
        # Only the documented inference acts: the next tool use AFTER a
        # pending permission means the human allowed it — awaiting-human ->
        # working. Every other tool use is a fast no-op (push fires on the
        # REQ-A1.1 transitions, never per tool call). Known inference
        # limitation (D-1 documents the transition as inference, not a
        # direct signal): a parallel unrelated tool's PostToolUse can clear
        # a still-pending permission's marker; the ground-truth reconcile
        # (REQ-A1.8) re-derives the awaiting state next sweep.
        [ -e "$marker" ] || exit 0
        rm -f "$marker" 2>/dev/null || true
        "$FA" heartbeat "$handle" "$scope" working >/dev/null 2>&1 \
          || echo "fleet-liveness: state push (working) failed; reconcile self-heals (D-1)" >&2
        exit 0
        ;;
      stop | session-end | stop-failure)
        case "$event" in
          stop) target=idle ;;
          session-end) target=ended ;;
          stop-failure) target=hung ;;
        esac
        # The escalation-preserve guard (REQ-A1.3): an awaiting-input row
        # with NO pending-permission marker is a queued human decision — a
        # downgrade push never auto-resolves it. The guard is enforced
        # ATOMICALLY inside the store's critical section
        # (heartbeat --unless-awaiting), so a decide committing between a
        # read here and the write cannot be clobbered. With the marker
        # present this is the permission flow ending (risk 28's deny path):
        # clear to the downgrade state unconditionally.
        if [ -e "$marker" ]; then
          rm -f "$marker" 2>/dev/null || true
          "$FA" heartbeat "$handle" "$scope" "$target" >/dev/null 2>&1 \
            || echo "fleet-liveness: state push ($target) failed; reconcile self-heals (D-1)" >&2
        else
          "$FA" heartbeat "$handle" "$scope" "$target" --unless-awaiting >/dev/null 2>&1 \
            || echo "fleet-liveness: state push ($target) failed; reconcile self-heals (D-1)" >&2
        fi
        exit 0
        ;;
    esac
    exit 0
    ;;

  push-capable)
    if [ "$#" -ne 1 ]; then
      echo "usage: fleet-liveness.sh push-capable <backend>" >&2
      exit 2
    fi
    backend=$1
    # The risk-16 boundary, keyed to the backend capability contract
    # (doctrine/backend-capability-contract.md): only tmux launches a
    # dispatch-controlled Claude Code process that inherits the identity env
    # and fires plugin hooks, so only tmux pushes. subagent runs in-process
    # (per-worker session hooks do not exist), in-session shares the tower's
    # own session, and print spawns NO process at all — the human runs the
    # printed command by hand, so the dispatch env is never injected and
    # print-backend units are contract-exempt from the liveness predicate.
    # All three keep the EXISTING observation path — the fleet degrades to
    # pre-spec observation for that slice, never to a broken mechanism.
    case "$backend" in
      tmux)
        printf 'push\n'
        exit 0
        ;;
      subagent | print | in-session)
        printf 'observe\n'
        exit 1
        ;;
      *)
        echo "fleet-liveness: unknown backend '$(sanitize_printable "$backend" "(unprintable backend)")' (tmux|subagent|print|in-session)" >&2
        exit 2
        ;;
    esac
    ;;

  classify)
    if [ "$#" -lt 2 ]; then
      echo "usage: fleet-liveness.sh classify <worker> <scope> [--now <epoch>] [--heartbeat <epoch>] [--progress <token>] [--evidence <class> <args...>]" >&2
      exit 2
    fi
    worker=$1
    scope=$2
    shift 2
    if ! valid_field "$worker"; then
      echo "fleet-liveness: refusing malformed worker handle" >&2
      exit 2
    fi
    if ! valid_field "$scope"; then
      echo "fleet-liveness: refusing malformed scope" >&2
      exit 2
    fi
    now=""
    hb_arg=""
    progress=""
    ev_class=""
    ev_a1=""
    ev_a2=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --now)
          if [ "$#" -lt 2 ] || ! valid_epoch "$2"; then
            echo "fleet-liveness: --now needs a non-negative epoch (no leading zero, <=15 digits)" >&2
            exit 2
          fi
          now=$2
          shift 2
          ;;
        --heartbeat)
          if [ "$#" -lt 2 ] || ! valid_epoch "$2"; then
            echo "fleet-liveness: --heartbeat needs a non-negative epoch (no leading zero, <=15 digits)" >&2
            exit 2
          fi
          hb_arg=$2
          shift 2
          ;;
        --progress)
          if [ "$#" -lt 2 ] || ! valid_field "$2"; then
            echo "fleet-liveness: --progress needs a token matching the fleet field grammar" >&2
            exit 2
          fi
          progress=$2
          shift 2
          ;;
        --evidence)
          # Two classes, arity-checked here; the predicate re-validates its
          # own tokens (and refuses pseudo-evidence classes) — this check
          # only keeps a malformed invocation from reaching it at all.
          [ "$#" -ge 2 ] || {
            echo "fleet-liveness: --evidence needs a class (process <pid> | tmux-window <session> <window>)" >&2
            exit 2
          }
          ev_class=$2
          case "$ev_class" in
            process)
              [ "$#" -ge 3 ] || {
                echo "fleet-liveness: --evidence process needs <pid>" >&2
                exit 2
              }
              ev_a1=$3
              shift 3
              ;;
            tmux-window)
              [ "$#" -ge 4 ] || {
                echo "fleet-liveness: --evidence tmux-window needs <session> <window>" >&2
                exit 2
              }
              ev_a1=$3
              ev_a2=$4
              shift 4
              ;;
            *)
              echo "fleet-liveness: unknown evidence class '$(sanitize_printable "$ev_class" "(unprintable class)")' (process|tmux-window)" >&2
              exit 2
              ;;
          esac
          ;;
        *)
          echo "fleet-liveness: unknown classify option '$(sanitize_printable "$1" "(unprintable option)")'" >&2
          exit 2
          ;;
      esac
    done
    if [ -z "$now" ]; then
      now=$(now_epoch)
      if [ -z "$now" ]; then
        echo "fleet-liveness: could not read a numeric timestamp" >&2
        exit 2
      fi
    fi
    flail_n=$(knob fleet_flailing_threshold 3) || exit $?
    hung_s=$(knob fleet_hung_heartbeat_seconds 900) || exit $?
    root=$("$FS" root) || exit 2
    row_state=$(store_row_field "$root" "$worker" "$FIELD_STATE")
    hb="$hb_arg"
    [ -n "$hb" ] || hb=$(store_row_field "$root" "$worker" "$FIELD_HEARTBEAT")
    case $hb in *[!0-9]* | 0?*) hb="" ;; esac

    # Record the observation (bounded history, copy-append-rename so a
    # concurrent reader never sees a torn file).
    obs_dir="$root/liveness/observations"
    obs="$obs_dir/$worker.tsv"
    if ! mkdir -p "$obs_dir" 2>/dev/null; then
      echo "fleet-liveness: cannot create the observations dir $obs_dir" >&2
      exit 2
    fi
    obs_tmp=$(mktemp "$obs_dir/.obs.XXXXXX") || {
      echo "fleet-liveness: cannot create a temp file under $obs_dir" >&2
      exit 2
    }
    # The history window must hold at least fleet_flailing_threshold rows or
    # a threshold above the window silently caps the streak and flailing can
    # never fire; 50 is the floor (the risk-18 windowing spirit), a larger
    # threshold widens the window to match.
    keep_n=49
    [ "$flail_n" -le 50 ] || keep_n=$((flail_n - 1))
    ob_rc=0
    if [ -f "$obs" ]; then
      tail -n "$keep_n" "$obs" >"$obs_tmp" 2>/dev/null || ob_rc=2
    fi
    if [ "$ob_rc" = 0 ]; then
      printf '%s\t%s\t%s\t%s\n' "$now" "${hb:--}" "$progress" "$row_state" >>"$obs_tmp" || ob_rc=2
    fi
    if [ "$ob_rc" = 0 ]; then
      mv -f "$obs_tmp" "$obs" || ob_rc=2
    fi
    if [ "$ob_rc" != 0 ]; then
      rm -f "$obs_tmp" 2>/dev/null
      echo "fleet-liveness: failed to record the observation" >&2
      exit 2
    fi

    cls=""
    case "$row_state" in
      awaiting-input) cls=awaiting-human ;;
      idle | pr-ready | merged | done | ended) cls=idle ;;
      hung) cls=hung ;;
    esac
    if [ -z "$cls" ]; then
      # working row, or no row yet (the startup default, risk 33).
      if [ -z "$hb" ]; then
        cls=working
      elif [ $((now - hb)) -ge "$hung_s" ]; then
        if [ -n "$ev_class" ]; then
          ev_rc=0
          if [ "$ev_class" = process ]; then
            "$FDE" process "$ev_a1" >/dev/null 2>&1 || ev_rc=$?
          else
            "$FDE" tmux-window "$ev_a1" "$ev_a2" >/dev/null 2>&1 || ev_rc=$?
          fi
          case $ev_rc in
            0 | 1) cls=hung ;; # dead, or alive-but-silent (a wedged harness)
            3)
              echo "fleet-liveness: lost observability (death-evidence: unknown) — refusing the hung classification (REQ-A1.7: silence is not evidence)" >&2
              cls=working
              ;;
            *)
              echo "fleet-liveness: the death-evidence predicate refused the evidence handle (exit $ev_rc)" >&2
              exit 2
              ;;
          esac
        else
          # No authoritative query available: the documented elapsed-time
          # boundary (risk 29).
          cls=hung
        fi
      elif [ -n "$progress" ]; then
        # Trailing consecutive observations sharing this progress token
        # (the row just appended included).
        streak=$(awk -F "$TAB" -v t="$progress" '
          { if (($3 "") == (t "")) n++; else n = 0 }
          END { print n + 0 }' "$obs")
        if [ "$streak" -ge "$flail_n" ]; then
          cls=flailing
        else
          cls=working
        fi
      else
        cls=working
      fi
    fi

    if [ "$cls" = flailing ]; then
      # Escalate, and nothing else (REQ-A1.3): one queued human decision
      # (an upsert — repeated classification never duplicates it), one
      # audit row for the escalation ACTION (routine classification is
      # never audited, risk 31). No restart, no nudge — no such path
      # exists here. Audit BEFORE decide: on a decide failure the caller
      # retries and the streak re-fires (a duplicate audit row records the
      # retry, benign), whereas decide-before-audit could queue the fork
      # with the escalate action permanently missing from the trail — the
      # row state flips to awaiting-input, so a retry never re-audits.
      "$FAU" record liveness-classifier escalate \
        "no-forward-progress-x$flail_n" \
        "worker $worker heartbeating with an unchanged progress token across $flail_n observations; queued the stuck-task fork (no automatic restart or nudge, REQ-A1.3)" \
        >/dev/null || {
        echo "fleet-liveness: failed to audit the flailing escalation" >&2
        exit 2
      }
      "$FA" decide "$worker" "$scope" \
        "No forward progress across $flail_n heartbeats - this task may be stuck" \
        "park for human review" \
        "park for review|relaunch fresh|redirect with guidance" \
        high >/dev/null || {
        echo "fleet-liveness: failed to queue the flailing escalation" >&2
        exit 2
      }
    fi
    printf '%s\n' "$cls"
    exit 0
    ;;

  crash-record)
    if [ "$#" -lt 2 ]; then
      echo "usage: fleet-liveness.sh crash-record <worker> <scope> [--now <epoch>]" >&2
      exit 2
    fi
    worker=$1
    scope=$2
    shift 2
    if ! valid_field "$worker" || ! valid_field "$scope"; then
      echo "fleet-liveness: refusing malformed worker/scope token" >&2
      exit 2
    fi
    now=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --now)
          if [ "$#" -lt 2 ] || ! valid_epoch "$2"; then
            echo "fleet-liveness: --now needs a non-negative epoch (no leading zero, <=15 digits)" >&2
            exit 2
          fi
          now=$2
          shift 2
          ;;
        *)
          echo "fleet-liveness: unknown crash-record option" >&2
          exit 2
          ;;
      esac
    done
    if [ -z "$now" ]; then
      now=$(now_epoch)
      if [ -z "$now" ]; then
        echo "fleet-liveness: could not read a numeric timestamp" >&2
        exit 2
      fi
    fi
    base=$(knob fleet_crash_backoff_base_seconds 30) || exit $?
    thresh=$(knob fleet_crash_disable_threshold 3) || exit $?
    root=$("$FS" root) || exit 2
    crash_dir="$root/liveness/crash"
    if ! mkdir -p "$crash_dir" 2>/dev/null; then
      echo "fleet-liveness: cannot create the crash dir $crash_dir" >&2
      exit 2
    fi
    # The read-modify-write runs under the fleet lock (risk rows 6/8): two
    # supervisors recording the same crash burst can neither lose an
    # increment (delayed disable) nor double-count one crash (premature
    # disable) through a torn update.
    acquire_lock || exit 2
    # shellcheck disable=SC2046
    set -- $(crash_read "$root" "$worker")
    count=$1
    prev_disabled=$3
    count=$((count + 1))
    delay=$base
    i=1
    while [ "$i" -lt "$count" ] && [ "$delay" -lt 3600 ]; do
      delay=$((delay * 2))
      i=$((i + 1))
    done
    [ "$delay" -le 3600 ] || delay=3600
    disabled=0
    [ "$count" -lt "$thresh" ] || disabled=1
    # Disabled is STICKY: once set, only a human crash-reset clears it. A
    # threshold raised after the fact must not silently re-authorize a
    # worker a human never re-enabled.
    [ "$prev_disabled" != 1 ] || disabled=1
    if ! atomic_write_file "$crash_dir/$worker" "$count $((now + delay)) $disabled"; then
      release_lock
      echo "fleet-liveness: failed to write the crash record" >&2
      exit 2
    fi
    release_lock
    # The result line prints BEFORE the escalation/audit side effects: the
    # counter is already durable at this point, so the caller must not
    # re-invoke crash-record for the same crash even on a non-zero exit (a
    # retry would double-count). A side-effect failure below exits 2 with
    # the stdout line already carrying the committed record; the missing
    # disable escalation self-heals on the next crash-check (which
    # re-upserts the queue entry for a disabled worker). Side effects run
    # AFTER the lock is released: decide and the audit trail serialize
    # through the same fleet lock themselves.
    if [ "$disabled" = 1 ]; then
      printf 'disabled %s\n' "$count"
      "$FA" decide "$worker" "$scope" \
        "Worker crash-looping: disabled after $count consecutive failures" \
        "investigate before any relaunch" \
        "investigate|reset the streak and relaunch|park the unit" \
        high >/dev/null || {
        echo "fleet-liveness: failed to queue the disable escalation (crash-check re-queues it)" >&2
        exit 2
      }
      "$FAU" record liveness-backoff disable \
        "consecutive-failure-$count" \
        "worker $worker reached the disable threshold ($thresh); no further relaunch will be authorized until a human resets the streak (REQ-A1.4)" \
        >/dev/null || {
        echo "fleet-liveness: failed to audit the disable" >&2
        exit 2
      }
      exit 0
    fi
    printf '%s %s\n' "$count" "$delay"
    "$FAU" record liveness-backoff backoff \
      "consecutive-failure-$count" \
      "worker $worker crashed; relaunch backed off ${delay}s on the escalating schedule (base ${base}s, doubling, cap 3600s)" \
      >/dev/null || {
      echo "fleet-liveness: failed to audit the backoff" >&2
      exit 2
    }
    exit 0
    ;;

  crash-check)
    if [ "$#" -lt 1 ]; then
      echo "usage: fleet-liveness.sh crash-check <worker> [--now <epoch>]" >&2
      exit 2
    fi
    worker=$1
    shift
    if ! valid_field "$worker"; then
      echo "fleet-liveness: refusing malformed worker handle" >&2
      exit 2
    fi
    now=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --now)
          if [ "$#" -lt 2 ] || ! valid_epoch "$2"; then
            echo "fleet-liveness: --now needs a non-negative epoch (no leading zero, <=15 digits)" >&2
            exit 2
          fi
          now=$2
          shift 2
          ;;
        *)
          echo "fleet-liveness: unknown crash-check option" >&2
          exit 2
          ;;
      esac
    done
    if [ -z "$now" ]; then
      now=$(now_epoch)
      if [ -z "$now" ]; then
        echo "fleet-liveness: could not read a numeric timestamp" >&2
        exit 2
      fi
    fi
    root=$("$FS" root) || exit 2
    # shellcheck disable=SC2046
    set -- $(crash_read "$root" "$worker")
    count=$1
    next_allowed=$2
    disabled=$3
    # The terminal state is reported FIRST: a disabled worker is exit 3 even
    # while the kill-switch is set — pausing the daemon layer must not mask
    # "never relaunch, needs a human" behind the transient "paused" signal.
    # The disable escalation is re-upserted here (idempotent — one row per
    # worker), self-healing the window where crash-record persisted
    # disabled=1 but died before its decide committed; surfacing to a human
    # is never gated (degrade capability, never safety).
    if [ "$disabled" = 1 ]; then
      # Heal only when no queued entry exists for the worker (an
      # awaiting-input row IS the queue entry) so an intact escalation's
      # scope and text are never clobbered; the row's own scope is reused,
      # with a placeholder only when no row survives at all.
      d_state=$(store_row_field "$root" "$worker" "$FIELD_STATE")
      if [ "$d_state" != awaiting-input ]; then
        d_scope=$(store_row_field "$root" "$worker" "$FIELD_SCOPE")
        valid_field "$d_scope" || d_scope=unknown
        "$FA" decide "$worker" "$d_scope" \
          "Worker crash-looping: disabled after $count consecutive failures" \
          "investigate before any relaunch" \
          "investigate|reset the streak and relaunch|park the unit" \
          high >/dev/null 2>&1 \
          || echo "fleet-liveness: could not re-upsert the disable escalation" >&2
      fi
      printf 'disabled\n'
      exit 3
    fi
    # A relaunch is a daemon restart action: the operator kill-switch gates
    # it (D-15). Exit 1 paused; 4/5 propagate (never act under unknown
    # switch state). Bookkeeping (crash-record) is deliberately NOT gated.
    gate_rc=0
    "$FDG" liveness-backoff || gate_rc=$?
    case $gate_rc in
      0) ;;
      1)
        printf 'paused\n'
        exit 1
        ;;
      *)
        exit "$gate_rc"
        ;;
    esac
    if [ "$count" -gt 0 ] && [ "$now" -lt "$next_allowed" ]; then
      printf 'backoff %s\n' "$((next_allowed - now))"
      exit 1
    fi
    printf 'ok\n'
    exit 0
    ;;

  crash-reset)
    if [ "$#" -ne 1 ]; then
      echo "usage: fleet-liveness.sh crash-reset <worker>" >&2
      exit 2
    fi
    worker=$1
    if ! valid_field "$worker"; then
      echo "fleet-liveness: refusing malformed worker handle" >&2
      exit 2
    fi
    root=$("$FS" root) || exit 2
    acquire_lock || exit 2
    reset_rc=0
    if [ -e "$root/liveness/crash/$worker" ]; then
      # Surface a failed removal (fail closed): reporting "streak cleared"
      # while the disabled record survives would leave the worker parked
      # with the human believing it re-enabled.
      rm -f "$root/liveness/crash/$worker" 2>/dev/null || reset_rc=2
      if [ "$reset_rc" != 0 ] || [ -e "$root/liveness/crash/$worker" ]; then
        reset_rc=2
        echo "fleet-liveness: failed to remove the crash record (streak NOT cleared)" >&2
      fi
    fi
    release_lock
    exit "$reset_rc"
    ;;

  *)
    echo "fleet-liveness: unknown command '$(sanitize_printable "$cmd" "(unprintable command)")' (hook|push-capable|classify|crash-record|crash-check|crash-reset)" >&2
    exit 2
    ;;
esac
