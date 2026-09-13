#!/bin/sh
# fleet-streamjson.sh — the stream-json-persistent supervisor primitive
# (execution-backends Task 4; D-4, D-5 · REQ-A1.3, REQ-A1.9, REQ-E1.1,
# REQ-E1.2, REQ-E1.3, REQ-E1.4, REQ-E1.5). The close verb and the single-
# initiator elections on `launch` and `recover` come from a later bundle
# (fleet-lifecycle-closure D-3, D-10 · REQ-B1.1–B1.4, REQ-B1.7), whose own
# REQ-A1.3 is a different requirement from the one cited above; qualify the
# bundle when citing either.
#
# WHAT THIS IS (D-5). A supervisor process owns a stream-json worker's stdio:
# it launches the worker (`claude -p --input-format stream-json
# --output-format stream-json --verbose --permission-prompt-tool stdio
# --settings <config/worker-settings.json>`; non-`--bare` pinned per
# D-12/REQ-A1.5, and the worker-settings fragment pinned per fleet-autonomy
# D-19/REQ-E1.4. Pinning means never passing `--bare`, always passing the
# fragment resolved from this script's own location, and REFUSING a
# caller-supplied `--bare` or `--settings`. The fragment is the mode source:
# Claude Code honors a `defaultMode` of auto from the operator's own user
# settings, so a worker launched without a readable fragment inherits the LLM
# approval classifier in place of the human-reviewed allowlist, and the stdio
# prompt tool never fires under it. A missing or unreadable fragment therefore
# refuses the launch instead of degrading.
#
# The supervisor captures every event line, and converts the one verified
# deadlock — a `can_use_tool` control_request pends forever if unanswered — into the
# existing attention-store discipline: every receipt writes a decision-queue
# item (an attention-store `decide` row; the store IS the queue, no new
# surface, per the kickoff resolution of D-5) plus a durable journal record a
# scan-based pending-age alarm reads. AskUserQuestion control_requests map
# 1:1 onto queue items with the same alarm coupling (REQ-E1.2; on the wire an
# AskUserQuestion surfaces as a can_use_tool control_request whose tool_name
# is AskUserQuestion — verified against CLI v2.1.218). NO code path here
# auto-answers a control_request: the only control_response writer is the
# `answer` subcommand, which requires an operator-recorded answer as input
# (D-5's rejected-alternative: no second approval engine in the supervisor).
#
# THE RUNTIME SURFACE. Per-worker state lives OUTSIDE every checkout, under
# the cross-spec fleet home (fleet-state.sh root; PLANWRIGHT_FLEET_STATE_DIR
# is the operator/test override): <home>/streamjson/<worker>/ holding
#   events.jsonl     the event-stream capture (append-only; worker-authored
#                    conversation content — sensitive by default)
#   stderr.log       worker stderr capture
#   session          the persisted session_id (from the system:init event)
#   journal          durable receipt journal, one tab-separated row per
#                    control_request: id kind received-epoch state [epoch]
#                    kind ∈ permission|question; state ∈ pending|answered|
#                    undeliverable (the REQ-E1.5 durable receipt)
#   req-<id>.json    the raw control_request envelope (answer composition)
#   in.fifo/out.fifo the stdio channels the supervisor owns
#   result           the run outcome, one tab-separated row:
#                    result <subtype> <epoch> [is_error] | exit <rc> <epoch>
#                    is_error ∈ true|false, absent on records written before
#                    the field existed (read as false). Newline-terminated:
#                    the terminator is what says the writer finished, so a row
#                    without one is a write in flight, never a completion.
#   supervisor.pid / worker.pid / recover.lock/ / journal.lock/ / launch.lock/
#   scope            the dispatch scope, when the launch supplied one
#   supervisor.log   the detached supervisor's own stderr
#   .init.* / .journal.* / .session.* / .pid.*  mktemp-beside-target staging
#   *.broken.*       a lock directory a stale-break renamed out of the way
# Which of these a close releases is not a property of their order here: the
# release set is `release_classes` and the globs each class names, and the
# entries above are listed by what they hold, not by who removes them.
# Placing the capture under the fleet home is the strongest reading of the
# Task 4 "gitignored location outside committed paths" clause: it sits
# outside every checkout, so it cannot be committed even by force-add. The
# secret-scan surface (mise scan:secrets, committed files only) therefore
# definitionally excludes it; docs/fleet.md names the location and that
# exclusion explicitly (the "named in the secret-scan surface" clause).
#
# CRASH WINDOWS (REQ-E1.5). Receipt state is the on-disk journal, written
# BEFORE the attention upsert, so a supervisor kill loses no receipt. The
# pending-age alarm is scan-based over that journal (`alarm-scan`), so it is
# re-armed after `--resume` by construction — no in-memory timer to lose.
# Duplicate delivery of a request id (same run, or re-issued across the
# resume boundary) deduplicates on request identity: a journaled id is never
# journaled or queued twice. Recovery (`recover`) has a single initiator —
# an atomic mkdir election — and checks the orphaned worker's liveness
# before `--resume`; a failed resume surfaces as a halt of this unit
# (attention item + distinct exit code), never a silent loss. A
# `can_use_tool` arriving in the supervisor-down window is covered after
# recovery: the resumed session re-surfaces the pending ask and the new
# supervisor journals it (same id → dedup keeps the single item).
#
# ANSWER DELIVERY (REQ-E1.4). `answer` delivers the operator's recorded
# answer as the control_response to the pending control_request, serialized
# under the journal lock (one fifo writer at a time). An answer that can no
# longer be delivered — dead supervisor/worker channel, unknown or already-
# settled request — marks the journal row undeliverable and writes a visible
# attention item naming it: never a silent drop, never a silent re-apply to
# a different request.
#
# THE CLOSE (`stop`). The release set is the runtime a worker acquires:
# its process tree, the locks it holds, its scratch temp, and its attention
# record. The tmux-window class is named here rather than left silently absent,
# per the floor's declare-every-class rule: it is not acquired by this rung at
# all — a stream-json worker is a detached supervisor/worker pair with no
# window. The dispatch registry record is written at launch and is NOT released
# here: it is fleet-wide inventory rather than this worker's runtime. Nothing
# reconciles it yet (`scripts/fleet-register.sh` says so where it writes the
# record), so a stopped worker keeps its inventory row until the reconcile this
# bundle plans lands. The worktree, the branch, and the unit's fence are
# never touched: the release set is exactly the reproducible resources, and the
# worktree is the one holding work that cannot be recovered. No audit record is
# written either — the reap path that needs one owns it, so that an autonomous
# close writes exactly one record rather than two.
#
# Process matching keys on the worker's STATE-DIRECTORY path and on the pids
# that directory records, never on a process name or command pattern: an
# operator's own `claude` session shares this worker's command shape exactly,
# so a name match would kill it. The path match is anchored on the supervisor's
# own `_supervise <worker> <dir>` argv, not on a bare search for the directory,
# which would also match a sibling worker whose handle this one prefixes and
# any process merely naming the directory. SIGTERM first, SIGKILL after a
# bounded grace, because children do not reliably die with a parent SIGTERM.
#
# A release that cannot complete is reported as partial with the classes still
# held, never as success, so a tower can tell a closed worker from one that
# left residue. A process class that stays held ends the walk: breaking the
# locks and deleting the stdio fifos of a worker that is demonstrably still
# running would leave it alive with no channel to answer it on. Re-invocation
# is idempotent over the RELEASE SET rather than the invocation: a stop takes
# exactly the classes still held, so a repeat against a fully released worker
# reports `already-closed` and signals nothing, while a repeat after a partial
# close retries only what remains.
#
# COMPLETION / LIVENESS. This backend's completion/liveness source is the
# supervisor plus the event stream (the sibling of Task 3's completion
# signal): `status` reports completed from the captured result event, `ended`
# when that event flagged is_error (the turn completed, the run did not), and
# dead only on positive evidence (fleet-death-evidence.sh `process <pid>`
# verdicts for both recorded pids) — silence is never death.
#
# Launch input hygiene (REQ-A1.9): the prompt is read from a FILE and
# JSON-encoded by awk into the initial stream-json user message written to
# the worker's stdin — data on a pipe, never text interpolated into a shell
# command line. The claude argv is assembled as argv, never spliced.
#
# Usage:
#   fleet-streamjson.sh launch <worker> <scope> --prompt-file <file>
#       [--cwd <dir>] [--foreground] [-- <extra claude args>...]
#       Launch a worker under a supervisor. Detached by default (prints
#       `launched <worker> dir <dir>`); --foreground runs the supervisor
#       loop in this process (fixtures; returns the worker's exit code). A
#       caller-supplied `--bare` (or `-b`) in the extra args is refused
#       (exit 2): the non-bare pin is structural. Single-initiator: a launch
#       already in flight for this worker, or any process this worker's state
#       still records as alive, is refused (exit 3) rather than allowed to
#       orphan the first one. That second arm covers a live worker under a
#       dead supervisor, which wants `recover` rather than a second `launch`.
#   fleet-streamjson.sh answer <worker> <request-id>
#       (--response-file <file> | --allow | --deny [--message <text>])
#       Deliver the recorded answer for a pending request. --allow composes
#       behavior=allow with updatedInput sliced from the stored envelope;
#       --deny composes behavior=deny (optional message); --response-file
#       supplies the full response body (AskUserQuestion answers use this).
#   fleet-streamjson.sh recover <worker> [--foreground] [-- <extra args>...]
#       Single-initiator crash recovery: refuse when a recovery is already
#       in flight (exit 3) or the worker/supervisor is still alive (exit 3),
#       then relaunch with `--resume <session_id>`. A missing session halts
#       with exit 4, a failed resume with exit 5 — both surfaced as
#       attention items (the Awaiting-input halt of the affected unit; the
#       tower and other workers continue).
#   fleet-streamjson.sh alarm-scan [--now <epoch>] [--threshold <secs>]
#       Scan every worker journal for pending items older than the
#       threshold (default 900s; PLANWRIGHT_STREAMJSON_PENDING_AGE
#       overrides, the flag wins) and escalate each to a high-priority
#       attention item + notify push. The outcome is operator escalation on
#       the attention surface — never an auto-answer, never a worker kill.
#       Prints `alarm <worker> <id> <age>` per firing.
#   fleet-streamjson.sh stop <worker> [--grace <secs>]
#       Close the worker: terminate its process tree and release the locks,
#       scratch temp, and attention record it holds. Prints one of
#       `stop <worker> stopped released=<classes>`,
#       `stop <worker> already-closed`, or
#       `stop <worker> partial released=<classes> held=<classes>`, whose
#       released field reads `-` when nothing was released (the other two
#       forms cannot reach that case). <secs> is the SIGTERM-to-SIGKILL grace,
#       a whole number of seconds bounded by `grace_max` and defaulting to
#       `grace_default`; passing an out-of-range value prints both. There is no
#       zero-grace form, since SIGTERM always goes first, and a fixed settling
#       wait follows the SIGKILL.
#       An unknown handle is exit 2, not `already-closed`, so a typo never
#       reads as a successful close, and a close asked for from inside the
#       worker's own process tree is refused with exit 3 rather than attempted.
#   fleet-streamjson.sh status <worker>
#       Print `status <worker> <running|awaiting-input|completed|ended|dead|
#       unknown> <detail>` from the recorded pids, the receipt journal and the
#       captured event stream. `awaiting-input` is a live worker with a pending
#       control_request: the detail carries `pending=<n> oldest=<age>s`, so a
#       worker that cannot proceed never reads as a healthy `running`.
#
# Exit codes: 0 success; 2 usage error, refused hostile input, or a
#   filesystem/lock error (fail closed); 3 a semantic refusal (recovery
#   already in flight / a launch already in flight or over a live supervisor /
#   not orphaned / a close asked for from inside the worker's own process tree /
#   the answer does not apply — the undeliverable-answer arms
#   exit 3 AFTER surfacing the attention item); 4 recovery halt: no usable
#   session to resume; 5 recovery halt: the `--resume` relaunch failed; 6 a
#   partial close: some class of the release set is still held; 7 the
#   worker-settings fragment the launch pins is missing or unreadable; 8 the
#   dispatch-env wrapper the launch goes through is missing or unreadable; 9
#   the launch preflight could not prove the worker's auto-approve hook will
#   approve its opening plugin-script call (see LAUNCH PREFLIGHT).
#
# LAUNCH PREFLIGHT. A dispatched worker's first move is fixed and predictable:
# /execute-task resolves its doctrine by calling scripts under the planwright
# root before any task work. Twice that call fell outside what the dispatch
# plumbing approved and the worker pended on its first tool call with nothing
# to say so (2026-09-12, format-grammar task 7: the guard trusted the root the
# LAUNCHER lives in, the skill called scripts under the root Claude Code
# INSTALLED the plugin at). So before spawning, `launch` runs the wired hook
# (scripts/worker-command-guard.sh, through the same dispatch-env wrapper and
# so with the same environment the worker gets) against a synthetic PreToolUse
# payload for `<root>/scripts/resolve-rule-doc.sh spec-format`, once per root
# the worker could run scripts from: this launcher's own root and every root
# scripts/resolve-installed-roots.sh names. A root the hook does not approve
# refuses the launch with exit 9, naming the root and the command, because the
# worker would otherwise stall on exactly that call. PLANWRIGHT_STREAMJSON_
# GUARD_PREFLIGHT=warn downgrades the refusal to a warning (an operator who
# intends to answer every prompt by hand); =off skips the proof.
#
# ESCALATION TICK. The pending-age alarm used to be scan-only (`alarm-scan`),
# and nothing in the fleet ran the scan, so a worker parked on an unanswerable
# request stayed a `running` worker with one pending journal row for as long as
# nobody looked. The supervisor now runs the same journal scan itself, for its
# own worker, every PLANWRIGHT_STREAMJSON_ALARM_TICK seconds (default 60): a
# receipt pending longer than PLANWRIGHT_STREAMJSON_PENDING_AGE (default 900)
# is escalated to a high-priority queue item and pushed through the notify
# seam once, on the tick that crosses the threshold. Scan-based over the
# durable journal, so it holds the same crash-window properties `alarm-scan`
# has, and still never auto-answers and never kills the worker.
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling): awk,
# mkfifo, mktemp, `date +%s`, a fractional `sleep`, and — for the close —
# `kill` and a `ps -A -o pid=,ppid=,args=` whose output format is load-bearing
# (`-ww` is probed and the narrow form accepted, since BSD ps truncates argv to
# terminal width and busybox ps rejects the flag). No eval, no jq
# (REQ-K1.5); all parsed content — event lines, request ids, prompt text —
# is data, never code. Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

# The record separator for the result file, needed to anchor a field match to a
# real field boundary rather than a name prefix.
TAB=$(printf '\t')
# The record TERMINATOR. The writers below end every record with it, so its
# presence is what distinguishes a record from a snapshot of one being written.
NL=$(printf '\nx')
NL=${NL%x}
me=fleet-streamjson
LF='
'

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
# Absolute path to this script, so the detached-supervisor re-exec survives a
# relative invocation followed by a `--cwd` chdir (a bare `$0` would resolve
# against the new cwd and silently fail to launch).
self="$script_dir/$(basename "$0")"

# The canonical echo-discipline sanitizer (doctrine/security-posture.md),
# required readable and fail-closed when absent: worker-authored strings
# (tool names, result subtypes) are sanitized before any operator-facing
# echo or attention write.
echo_safety="$script_dir/echo-safety.sh"
if [ ! -r "$echo_safety" ]; then
  echo "$me: required helper $echo_safety missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$echo_safety"

FS="$script_dir/fleet-state.sh"
FA="$script_dir/fleet-attention.sh"
FDE="$script_dir/fleet-death-evidence.sh"

# The worker binary. Tests point this at a shim; the default is the
# installed CLI (D-4: the installed `claude` CLI is the only driver, never
# SDK-as-library).
cli=${PLANWRIGHT_STREAMJSON_CLI:-claude}

# --- grammars ---------------------------------------------------------------

# Worker/scope handle grammar, byte-identical to the Task 9 field grammar
# fleet-attention.sh enforces (REQ-A1.6): no path separators, whitespace,
# control bytes, or shell metacharacters; bare dot-runs refused; <=128 chars.
valid_field() {
  case "$1" in
    '' | *[!A-Za-z0-9._=@:-]*) return 1 ;;
    . | ..) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

# Request-id grammar. Request ids arrive on the WORKER's output stream
# (untrusted for path purposes) and become journal keys and `req-<id>.json`
# filenames: alnum/hyphen only, must start alnum, <=64 — a traversal token,
# a dot, or a metacharacter is refused before any path use. The observed CLI
# shape is a UUID; the grammar is deliberately wider so a CLI id-format
# change does not orphan receipts, and strictly narrower than a filename.
valid_reqid() {
  case "$1" in
    '' | [!A-Za-z0-9]*) return 1 ;;
    *[!A-Za-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# A positive-integer token (epochs, thresholds, pids): digits only, bare
# zero refused (kill -0 0 probes the whole process group — a false-alive
# hazard), no leading zero (octal hazard), <=15 digits (the sibling
# overflow guard).
valid_posnum() {
  case "$1" in
    '' | *[!0-9]* | 0*) return 1 ;;
  esac
  [ "${#1}" -le 15 ]
}

usage() {
  {
    echo "usage: fleet-streamjson.sh launch <worker> <scope> --prompt-file <file> [--cwd <dir>] [--foreground] [-- <extra args>...]"
    echo "       fleet-streamjson.sh answer <worker> <request-id> (--response-file <file> | --allow | --deny [--message <text>])"
    echo "       fleet-streamjson.sh recover <worker> [--foreground] [-- <extra args>...]"
    echo "       fleet-streamjson.sh alarm-scan [--now <epoch>] [--threshold <secs>]"
    echo "       fleet-streamjson.sh stop <worker> [--grace <secs>]"
    echo "       fleet-streamjson.sh status <worker>"
  } >&2
  exit 2
}

now_epoch() {
  ne_v=$(date +%s)
  case $ne_v in
    '' | *[!0-9]*)
      echo "$me: date +%s produced no epoch" >&2
      return 1
      ;;
  esac
  printf '%s' "$ne_v"
}

# The per-worker runtime dir under the cross-spec fleet home. The home
# resolution (and its trust chain) is fleet-state.sh's — consumed, never
# re-implemented (the Task 9 discipline).
worker_dir() {
  wd_root=$(/bin/sh "$FS" root) || {
    echo "$me: cannot resolve the fleet home (fleet-state.sh root failed)" >&2
    return 2
  }
  printf '%s/streamjson/%s' "$wd_root" "$1"
}

# stat_mtime <path> — mtime in epoch seconds, portable across GNU/busybox and
# BSD stat. BOTH flavors are tried and each result is validated to be a plain
# integer, because exit status alone does not discriminate between them: on
# GNU/busybox stat `-f` means --file-system, so the BSD form's format string is
# consumed as a FILE operand and the call prints a whole filesystem dump on
# stdout while exiting non-zero. A bare `stat -f … || stat -c …` chain
# therefore CONCATENATES that dump with the fallback's epoch, and the
# `$((now - mtime))` below it is then a FATAL error that kills the shell
# mid-decision (`Illegal number` on Debian/dash, `arithmetic syntax error` on
# Alpine/busybox, `unbound variable` under macOS sh) — a silent Linux-red
# failure the BSD-green floor platform never showed. Shape-validating each
# candidate rather than trusting its exit status makes the probe
# order-independent and immune to that class. Mirrors fleet-pane-detect.sh's
# stat_uid (execution-backends task 3), which fixed the same defect on the
# same reasoning.
# Returns non-zero when neither flavor yields an integer, so callers fail safe
# rather than computing an age from garbage.
stat_mtime() {
  sm_v=$(stat -c '%Y' "$1" 2>/dev/null) || sm_v=''
  case $sm_v in
    '' | *[!0-9]*) sm_v=$(stat -f '%m' "$1" 2>/dev/null) || sm_v='' ;;
  esac
  case $sm_v in
    '' | *[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$sm_v"
}

# --- single-initiator locks -------------------------------------------------

# The ages past which a lock whose holder never recorded itself is a crashed
# holder rather than a live one, each sized against the operation it covers: a
# recovery spans a relaunch and its startup wait; a launch's unrecorded window
# closes as soon as it writes its holder pid.
recover_lock_stale=300
launch_lock_stale=60
journal_lock_stale=60

# lock_take <lock-dir> <max-age> — take an atomic mkdir election, breaking a
# lock whose holder is gone. Non-zero, lock untouched, when a holder is
# genuinely live.
#
# The holder's pid is recorded inside the lock, so a crashed holder is detected
# by evidence rather than by an age that cannot tell a crash from a legitimate
# long hold — a `--foreground` launch holds its lock for the whole run. The age
# is the fallback for a lock whose holder died before recording itself, and an
# unreadable mtime reads as fresh, so an unprobeable lock is refused rather
# than broken.
#
# The break renames before it removes: `rmdir` then `mkdir` is not a
# compare-and-swap, and two callers racing to break one stale lock would both
# win it. Only one rename can find the directory.
lock_take() {
  if mkdir "$1" 2>/dev/null; then
    printf '%s\n' "$$" >"$1/holder" 2>/dev/null || :
    return 0
  fi
  lt_holder=$(cat "$1/holder" 2>/dev/null) || lt_holder=''
  if valid_posnum "${lt_holder:-}"; then
    # Not `kill -0`: an EPERM holder is alive, and breaking its lock would let
    # two callers into the critical section at once.
    pid_live "$lt_holder" && return 1
  else
    lt_now=$(now_epoch) || return 1
    lt_mt=$(stat_mtime "$1") || lt_mt=$lt_now
    [ $((lt_now - lt_mt)) -gt "$2" ] || return 1
  fi
  lt_broken="$1.broken.$$"
  mv "$1" "$lt_broken" 2>/dev/null || return 1
  rm -rf "$lt_broken" 2>/dev/null || :
  mkdir "$1" 2>/dev/null || return 1
  printf '%s\n' "$$" >"$1/holder" 2>/dev/null || :
}

# lock_drop <lock-dir> — release a lock this process still holds. A lock some
# other caller has since taken is left alone: without the ownership check, a
# holder that outlived a break of its own lock would remove its successor's.
lock_drop() {
  [ "$(cat "$1/holder" 2>/dev/null)" = "$$" ] || return 0
  rm -rf "$1" 2>/dev/null || :
}

# write_pidfile <path> <pid> — publish a pid file the way this script publishes
# every other piece of durable state: into a temp beside the target, then
# renamed over it.
#
# A bare redirect creates the file before the write lands, and every reader of
# these files treats an empty one as "no pid recorded". In that window a launch
# reports success over a supervisor that never registered itself, the next
# launch's liveness check calls a live worker dead and starts a second
# supervisor over it, and `recover` resumes a session that is still running.
# A rename has no such window: the file is absent or complete, and absent is
# what every reader already handles.
write_pidfile() {
  wp_tmp=$(mktemp "${1%/*}/.pid.XXXXXX") || return 1
  printf '%s\n' "$2" >"$wp_tmp" && mv "$wp_tmp" "$1" && return 0
  rm -f "$wp_tmp" 2>/dev/null || :
  return 1
}

# pid_live <pid> — true when the pid names a live process, INCLUDING one this
# user may not signal. `kill -0` conflates two answers: "no such process" and
# EPERM, which means the process is alive and owned by someone else. Reading
# the second as death is how a live lock gets broken out from under its holder
# and how a second launch proceeds over a running worker. `ps -p` answers
# existence regardless of ownership and is consulted only after `kill -0` has
# already said no, so the common path stays fork-free.
pid_live() {
  kill -0 "$1" 2>/dev/null && return 0
  ps -p "$1" >/dev/null 2>&1
}

# worker_alive <dir> — true when a pid this worker's own state records is live.
worker_alive() {
  for wa_f in supervisor.pid worker.pid; do
    wa_p=$(cat "$1/$wa_f" 2>/dev/null) || wa_p=''
    if valid_posnum "${wa_p:-}" && pid_live "$wa_p"; then
      return 0
    fi
  done
  return 1
}

# --- journal (the REQ-E1.5 durable receipt state) ---------------------------
# One tab-separated row per request id: id kind received-epoch state [epoch].
# Mutations run under the file's own election lock. That premise used to be
# "journal writes are sub-second, so an older lock is a crashed holder", and it
# stopped holding when this path began publishing the queue projection inside
# the critical section: a hold now spans a shell-out and an old lock is no
# longer evidence of a crash. So age is the fallback, not the test. The
# election reads the holder pid first and refuses to break a live one, which is
# what makes a long legitimate hold safe; the age branch applies only to a lock
# with no usable holder stamp. The cost of refusing is on the other side and is
# real: a wedged holder is not reclaimed at all, only waited out.

journal_lock() {
  # Delegated to the file's own election primitive rather than hand-rolled here.
  # It already answers every hazard this lock met: the break renames before it
  # removes, so two waiters cannot both win one stale lock; the holder's pid is
  # recorded inside, so a live holder is never broken on age alone; and the drop
  # is ownership-checked, so a holder that outlived a break of its own lock
  # leaves its successor's alone. The spin is what this lock adds -- callers
  # here wait for a busy journal rather than failing on the first refusal.
  jl_dir="$1/journal.lock"
  jl_i=0
  until lock_take "$jl_dir" "$journal_lock_stale"; do
    jl_i=$((jl_i + 1))
    if [ "$jl_i" -ge 50 ]; then
      echo "$me: journal lock busy at $jl_dir" >&2
      return 2
    fi
    sleep 0.1
  done
}

journal_unlock() {
  lock_drop "$1/journal.lock"
}

# journal_state <dir> <id> — print the id's state field, empty when the id
# is not journaled.
journal_state() {
  [ -f "$1/journal" ] || return 0
  awk -F'\t' -v id="$2" '$1 == id { print $4; exit }' "$1/journal"
}

# journal_append <dir> <id> <kind> <epoch> — append a pending row (caller
# holds the lock and has established the id is absent). Returns non-zero on a
# write failure so the caller never proceeds to queue a request whose durable
# receipt did not land (REQ-E1.5).
journal_append() {
  printf '%s\t%s\t%s\tpending\n' "$2" "$3" "$4" >>"$1/journal"
}

# journal_set_state <dir> <id> <state> <epoch> — rewrite the id's row
# atomically (temp + rename; caller holds the lock).
journal_set_state() {
  js_tmp=$(mktemp "$1/.journal.XXXXXX") || return 2
  awk -F'\t' -v OFS='\t' -v id="$2" -v st="$3" -v ep="$4" \
    '$1 == id { $4 = st; $5 = ep } { print }' "$1/journal" >"$js_tmp" || {
    rm -f "$js_tmp"
    return 2
  }
  mv "$js_tmp" "$1/journal"
}

# journal_oldest_pending <dir> — print `<id> <kind>` for the oldest pending
# row, empty when none.
journal_oldest_pending() {
  [ -f "$1/journal" ] || return 0
  awk -F'\t' '$4 == "pending" { print $3 "\t" $1 "\t" $2 }' "$1/journal" \
    | sort -n | awk -F'\t' 'NR == 1 { print $2, $3 }'
}

# --- JSON helpers (awk, no jq per REQ-K1.5) ---------------------------------

# json_escape — print stdin as a JSON string body (no surrounding quotes):
# backslash, quote, tab, and CR escaped; newlines between lines become \n;
# remaining C0 control bytes and DEL are stripped (this text is data — a stray
# control byte is dropped, never smuggled, and never emitted raw, which would
# make the frame invalid JSON the worker's parser rejects).
# Bytes >= 0x80 are kept, so raw UTF-8 (accents, em-dash, CJK, emoji) reaches
# the worker intact — JSON strings carry UTF-8 verbatim; the class below is
# chosen over `[^[:print:]]`, which would delete UTF-8 lead/continuation
# bytes. NOTE the strip is GNU-only in practice: BSD awk (macOS) does not
# honour `[\000-\037\177]` as a byte range and strips nothing, so on the
# bash-3.2 floor C0/DEL survive this escaper (tests/test-fleet-streamjson.sh
# c17 documents the same asymmetry). TAB and CR use explicit gsub above and
# are portable everywhere.
# Every string body the supervisor emits goes through this one escaper, so the
# prompt path and the deny-message path cannot drift apart.
json_escape() {
  awk '
    NR > 1 { printf "\\n" }
    {
      s = $0
      gsub(/\\/, "\\\\", s)
      gsub(/"/, "\\\"", s)
      gsub(/\t/, "\\t", s)
      gsub(/\r/, "\\r", s)
      gsub(/[\000-\037\177]/, "", s)
      printf "%s", s
    }
  '
}

# json_escape_file <file> — json_escape over a file's content.
json_escape_file() {
  json_escape <"$1"
}

# json_field <line> <key> — print the string value of the FIRST
# `"key":"value"` occurrence in the line (JSON escapes left as-is), empty
# when absent.
json_field() {
  printf '%s\n' "$1" | awk -v k="$2" '
    {
      pat = "\"" k "\":\""
      i = index($0, pat)
      if (i == 0) exit
      rest = substr($0, i + length(pat))
      out = ""
      j = 1
      while (j <= length(rest)) {
        c = substr(rest, j, 1)
        if (c == "\\") { out = out c substr(rest, j + 1, 1); j += 2; continue }
        if (c == "\"") break
        out = out c
        j++
      }
      print out
      exit
    }'
}

# json_input_object <envelope-file> — print the balanced {...} object after
# the first `"input":` in the stored control_request envelope (string-aware:
# braces inside JSON strings do not count). Empty when absent.
json_input_object() {
  awk '
    NR == 1 {
      i = index($0, "\"input\":")
      if (i == 0) exit
      rest = substr($0, i + 8)
      j = 1
      while (j <= length(rest) && substr(rest, j, 1) == " ") j++
      if (substr(rest, j, 1) != "{") exit
      depth = 0; instr = 0; out = ""
      for (; j <= length(rest); j++) {
        c = substr(rest, j, 1)
        out = out c
        if (instr) {
          if (c == "\\") { j++; out = out substr(rest, j, 1); continue }
          if (c == "\"") instr = 0
          continue
        }
        if (c == "\"") { instr = 1; continue }
        if (c == "{") depth++
        if (c == "}") { depth--; if (depth == 0) { print out; exit } }
      }
    }' "$1"
}

# --- attention coupling (D-5: the store IS the decision queue) --------------

# read_scope <dir> — the scope recorded at launch, degraded to a fixed
# placeholder when missing/hostile (the item must still surface).
read_scope() {
  rs_v=$(cat "$1/scope" 2>/dev/null) || rs_v=''
  if valid_field "$rs_v"; then
    printf '%s' "$rs_v"
  else
    printf 'unknown:0'
  fi
}

# attention_upsert <worker> <dir> <id> <kind> [priority] — upsert the
# worker's decision-queue item for a pending request. Question text is
# built from fixed prose plus sanitized, length-bounded fragments only.
attention_upsert() {
  au_worker=$1
  au_dir=$2
  au_id=$3
  au_kind=$4
  au_prio=${5:-normal}
  au_scope=$(read_scope "$au_dir")
  au_tool=''
  if [ -f "$au_dir/req-$au_id.json" ]; then
    au_tool=$(json_field "$(head -c 4096 "$au_dir/req-$au_id.json")" tool_name)
  fi
  au_tool=$(sanitize_printable "$au_tool" tool | cut -c1-64)
  au_short=$(printf '%s' "$au_id" | cut -c1-8)
  if [ "$au_kind" = question ]; then
    au_q="worker question (AskUserQuestion) req $au_short - answer via fleet-streamjson.sh answer"
  else
    au_q="permission request tool $au_tool req $au_short - answer via fleet-streamjson.sh answer"
  fi
  if [ "$au_prio" = high ]; then
    au_q="OVERDUE $au_q"
  fi
  /bin/sh "$FA" decide "$au_worker" "$au_scope" "$au_q" deny "allow|deny" "$au_prio" \
    || echo "$me: attention decide failed for $au_worker req $au_short" >&2
}

# attention_settled <worker> <dir> — after a request settles, re-point the
# queue item at the oldest still-pending request, or clear the row.
attention_settled() {
  as_pending=$(journal_oldest_pending "$2")
  if [ -n "$as_pending" ]; then
    attention_upsert "$1" "$2" "${as_pending%% *}" "${as_pending#* }"
  else
    /bin/sh "$FA" clear "$1" || :
  fi
}

# attention_failure <worker> <dir> <text> — a visible failure item
# (REQ-E1.4, REQ-E1.5: surfaced, never silent). Text is caller-fixed prose
# plus sanitized fragments.
attention_failure() {
  af_scope=$(read_scope "$2")
  /bin/sh "$FA" decide "$1" "$af_scope" "$3" acknowledge "acknowledge|investigate" high \
    || echo "$me: attention failure-item write failed for $1" >&2
  /bin/sh "$FA" notify "$3" >/dev/null 2>&1 || :
}

# --- the supervisor loop ----------------------------------------------------

# handle_line <worker> <dir> <line> — classify one captured event line and
# apply the D-5 coupling. NEVER writes to the worker's stdin (the
# no-auto-answer invariant: the only control_response writer is `answer`).
handle_line() {
  hl_worker=$1
  hl_dir=$2
  hl_line=$3
  case $hl_line in
    *'"type":"control_request"'*)
      hl_id=$(json_field "$hl_line" request_id)
      if ! valid_reqid "$hl_id"; then
        echo "$me: refused a control_request with an out-of-grammar request_id" >&2
        return 0
      fi
      hl_tool=$(json_field "$hl_line" tool_name)
      case $hl_tool in
        AskUserQuestion) hl_kind=question ;;
        *) hl_kind=permission ;;
      esac
      if ! journal_lock "$hl_dir"; then
        # The receipt could not be journaled: surface it rather than letting
        # the request pend unobserved (the invariant this script exists for).
        attention_failure "$hl_worker" "$hl_dir" \
          "receipt journaling failed for worker $hl_worker request $(printf '%s' "$hl_id" | cut -c1-8) - investigate the journal lock"
        return 0
      fi
      hl_state=$(journal_state "$hl_dir" "$hl_id")
      case $hl_state in
        pending)
          # A still-open request re-delivered: dedup on request identity — no
          # second journal row, no second queue item. This is the within-run
          # duplicate the CLI can emit and the resume-boundary re-delivery of
          # an unanswered request (REQ-E1.1, REQ-E1.2, REQ-E1.5).
          journal_unlock "$hl_dir"
          return 0
          ;;
        answered | undeliverable)
          # The same id re-surfaces in a terminal state. That legitimately
          # happens only across a `--resume`: the worker is asking AGAIN, so
          # the prior answer never took (a control_response written into a
          # buffer the killed worker never read, or an undeliverable verdict).
          # Re-OPEN the receipt to pending and re-queue it, so the resumed
          # ask is answerable — never silently swallowed (the no-pend-
          # unobserved invariant, and the "recover the worker and re-ask"
          # remedy this tool prints). The alarm re-arms on the new pending
          # row by construction.
          hl_now=$(now_epoch) || hl_now=0
          if ! journal_set_state "$hl_dir" "$hl_id" pending "$hl_now"; then
            # Fail closed: with the journal still terminal, an answerable
            # queue item would be a dead end (`answer` refuses on the
            # already-answered/undeliverable row). Surface the failed
            # re-open visibly instead (never silent, never misleading).
            journal_unlock "$hl_dir"
            attention_failure "$hl_worker" "$hl_dir" \
              "could not re-open request $(printf '%s' "$hl_id" | cut -c1-8) on resume for worker $hl_worker - the journal still reads terminal, investigate disk/store"
            return 0
          fi
          printf '%s\n' "$hl_line" >"$hl_dir/req-$hl_id.json"
          # Derived under the lock for the reason the sibling site below spells
          # out. Note this surfaces the oldest still-pending request rather
          # than the one just re-opened: when an earlier request is also open,
          # that older one is what the row is supposed to carry.
          attention_settled "$hl_worker" "$hl_dir"
          journal_unlock "$hl_dir"
          return 0
          ;;
      esac
      hl_now=$(now_epoch) || hl_now=0
      # Durable receipt FIRST (a kill after this write loses nothing), then
      # the envelope (answer composition), then the queue item. A failed
      # journal append is surfaced rather than proceeding to queue a request
      # with no durable receipt (REQ-E1.5's receipt-first guarantee).
      if ! journal_append "$hl_dir" "$hl_id" "$hl_kind" "$hl_now"; then
        journal_unlock "$hl_dir"
        attention_failure "$hl_worker" "$hl_dir" \
          "receipt append failed for worker $hl_worker request $(printf '%s' "$hl_id" | cut -c1-8) - the receipt journal is not durable, investigate disk/store"
        return 0
      fi
      printf '%s\n' "$hl_line" >"$hl_dir/req-$hl_id.json"
      # Derived and published INSIDE the journal lock. The queue row is a
      # projection of journal state, so reading that state and writing the row
      # have to be one step: with the publish outside, `answer` lands between
      # them, marks the row answered and clears the queue, and this write then
      # re-posts a decision the operator already made. Deriving instead of
      # publishing the id captured above is the other half -- the row carries
      # the OLDEST still-pending request, which the just-appended id is not
      # when an earlier one is still open. Held across the shell-out
      # deliberately: nothing reachable from here re-takes this lock or takes
      # the attention store's lock ahead of it, so it cannot deadlock. The
      # cost is real and is NOT bounded by the stale break, which is what an
      # earlier revision of this comment claimed: the election refuses to break
      # a lock whose holder is live, on purpose, so a wedged fleet-attention.sh
      # is not reclaimed at journal_lock_stale at all. Other journal writers
      # spin their retry budget, report busy, and stay out until this call
      # returns. An attention-store hang therefore becomes a journal stall for
      # this worker. Bounding that needs a kill-safe shell-out or a recovery
      # path neither this change nor the primitive provides; it is recorded
      # rather than papered over.
      attention_settled "$hl_worker" "$hl_dir"
      journal_unlock "$hl_dir"
      ;;
    *'"type":"system"'*'"subtype":"init"'*)
      hl_sid=$(json_field "$hl_line" session_id)
      if valid_reqid "$hl_sid"; then
        hl_tmp=$(mktemp "$hl_dir/.session.XXXXXX") || return 0
        printf '%s\n' "$hl_sid" >"$hl_tmp" && mv "$hl_tmp" "$hl_dir/session"
      fi
      ;;
    *'"type":"result"'*)
      hl_sub=$(json_field "$hl_line" subtype)
      hl_sub=$(sanitize_printable "$hl_sub" unknown | cut -c1-32)
      hl_now=$(now_epoch) || hl_now=0
      # A frame can claim success and carry is_error at once: an API error
      # reaches us as ordinary assistant text, so the TURN completed the
      # protocol while the RUN died. Recording only the subtype loses the half
      # that says so, and a reader then frees the slot on a worker that did
      # nothing. Matched on the raw line because json_field reads quoted
      # strings and this is a JSON boolean.
      case $hl_line in
        *'"is_error":true'*) hl_err=true ;;
        *) hl_err=false ;;
      esac
      printf 'result\t%s\t%s\t%s\n' "$hl_sub" "$hl_now" "$hl_err" >"$hl_dir/result"
      ;;
  esac
}

# supervise <worker> <dir> <initial-msg-file> <claude-argv...> — run the
# worker owning both stdio ends; capture every stdout line; return the
# worker's exit code. Runs in the process that IS the supervisor (launch
# --foreground, or the re-exec'd detached process, so $$ is honest).
supervise() {
  sv_worker=$1
  sv_dir=$2
  sv_init=$3
  shift 3
  rm -f "$sv_dir/in.fifo" "$sv_dir/out.fifo"
  mkfifo "$sv_dir/in.fifo" "$sv_dir/out.fifo" || return 2
  write_pidfile "$sv_dir/supervisor.pid" "$$" || return 2
  "$@" <"$sv_dir/in.fifo" >"$sv_dir/out.fifo" 2>>"$sv_dir/stderr.log" &
  sv_pid=$!
  if ! write_pidfile "$sv_dir/worker.pid" "$sv_pid"; then
    # Fatal, like its sibling one line above, and for a sharper reason than
    # symmetry. `recover` decides a worker is orphaned by reading these pid
    # files; a worker running with no pid file published is invisible to that
    # check, so a resume would start a second session over a live one. The
    # worker is already spawned, so it is closed here rather than left behind
    # — a supervisor that cannot record its worker must not leave one running
    # that nothing can find.
    # Bounded, TERM then KILL. A plain `wait` here would hang forever on a
    # worker that ignores SIGTERM or is wedged, turning a pid-file failure
    # into a launch that never returns — a worse outcome than the leak this
    # close exists to prevent. KILL cannot be caught or ignored, so the reap
    # is bounded by the kernel rather than by the worker's cooperation — not
    # the same as prompt: a task wedged in uninterruptible I/O stays until
    # that I/O ends, and nothing in userspace shortens it. What this removes
    # is the unbounded wait on a worker that simply chooses not to exit.
    #
    # Reasoned, not measured, and the reason is worth recording: a test cannot
    # reliably make this worker ignore TERM. The signal is sent within a few
    # syscalls of the spawn, so the worker is usually killed before it has run
    # its first line, and the unbounded version therefore returns promptly too.
    # A case built on that race would pass for the wrong reason more often
    # than it caught anything.
    kill "$sv_pid" 2>/dev/null || :
    # pid_live, not `kill -0`: an unsignalable worker reads as dead to the
    # bare probe, which would end the poll early, skip the KILL, and drop
    # straight into the unbounded wait this bound exists to remove — the hang
    # coming back through the check meant to prevent it.
    sv_wait=0
    while pid_live "$sv_pid" && [ "$sv_wait" -lt 20 ]; do
      sv_wait=$((sv_wait + 1))
      sleep 0.1
    done
    if pid_live "$sv_pid"; then
      kill -9 "$sv_pid" 2>/dev/null || :
    fi
    wait "$sv_pid" 2>/dev/null || :
    echo "$me: could not publish worker.pid for $sv_worker; the worker was closed rather than left unrecorded" >&2
    return 2
  fi
  # The ESCALATION TICK (see the header): a background scan of this worker's
  # own journal, so a receipt pending past the threshold surfaces within one
  # tick of crossing it whether or not anything else ever runs `alarm-scan`.
  # Started BEFORE the stdin fifo is opened on fd 3 below: a child holding
  # that fd would keep the worker's stdin open after the supervisor closed it,
  # and the EOF that ends a finished worker would never arrive. Re-exec'd
  # under its own `_tick` verb rather than forked as a subshell: a subshell
  # keeps this process's `_supervise <worker> <dir>` argv, and everything that
  # counts or closes supervisors matches on exactly that.
  /bin/sh "$self" _tick "$sv_worker" "$sv_dir" "$$" "$sv_pid" \
    >/dev/null 2>>"$sv_dir/supervisor.log" </dev/null &
  sv_ticker=$!
  # From here the supervisor writes into the worker's stdin fifo: a worker
  # that exits before reading turns the write into EPIPE, which must end the
  # run cleanly, not kill the supervisor. Set AFTER the spawn so the worker
  # does not inherit an ignored SIGPIPE through exec.
  trap '' PIPE
  # Hold the worker's stdin open for the whole run: `answer` writes
  # control_responses into the same fifo; EOF reaches the worker only when
  # the supervisor ends.
  exec 3>"$sv_dir/in.fifo"
  # Write the initial message in the BACKGROUND, then start the read loop.
  # The worker cannot finish opening its stdout fifo for write (and therefore
  # cannot drain its stdin) until this supervisor opens the read end below;
  # a synchronous init write larger than the pipe buffer would deadlock the
  # two opens against each other. Backgrounding the write lets the read loop
  # open the stdout end immediately, unblocking the worker so it drains the
  # init. The background writer holds its own dup of fd 3; the parent keeps
  # fd 3 open for the whole run, so the worker's stdin never sees a premature
  # EOF. sv_init is removed only after the writer has read it.
  cat "$sv_init" >&3 2>/dev/null &
  sv_init_writer=$!
  while IFS= read -r sv_line; do
    printf '%s\n' "$sv_line" >>"$sv_dir/events.jsonl"
    handle_line "$sv_worker" "$sv_dir" "$sv_line"
  done <"$sv_dir/out.fifo"
  kill "$sv_ticker" 2>/dev/null || :
  wait "$sv_ticker" 2>/dev/null || :
  wait "$sv_init_writer" 2>/dev/null || :
  rm -f "$sv_init"
  exec 3>&-
  wait "$sv_pid"
  sv_ec=$?
  rm -f "$sv_dir/worker.pid" "$sv_dir/supervisor.pid"
  if [ ! -f "$sv_dir/result" ]; then
    # The read loop ended with no `result` event: the worker exited without
    # completing the protocol. This is an END record, not a completion —
    # `cmd_status` renders a nonzero exit as `ended`, never `completed`, so a
    # crash or non-zero exit is not conflated with success.
    sv_now=$(now_epoch) || sv_now=0
    printf 'exit\t%s\t%s\n' "$sv_ec" "$sv_now" >"$sv_dir/result"
  fi
  return "$sv_ec"
}

# build_initial_msg <prompt-file> <out-file> — the REQ-A1.9 data path: the
# prompt text is JSON-encoded from the file into the initial user message.
build_initial_msg() {
  bi_body=$(json_escape_file "$1") || return 2
  printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"%s"}]}}\n' \
    "$bi_body" >"$2"
}

# refuse_bare <arg...> — the D-12 pin is structural: a caller-supplied
# `--bare` (or the `-b` short form) never reaches the launch argv.
refuse_bare() {
  for rb_a in "$@"; do
    case $rb_a in
      --bare | -b)
        echo "$me: refusing '--bare' in the launch argv - the non-bare pin is structural (execution-backends D-12, REQ-A1.5)" >&2
        return 2
        ;;
    esac
  done
}

# refuse_settings <arg...> — the permission posture is structural too: the
# launch pins the reviewed worker-settings fragment, and a caller-supplied
# `--settings` (either spelling) would let a second fragment override it.
refuse_settings() {
  for rs_a in "$@"; do
    case $rs_a in
      --settings | --settings=*)
        echo "$me: refusing '--settings' in the launch argv - the worker-settings pin is structural (fleet-autonomy D-19, REQ-E1.4)" >&2
        return 2
        ;;
    esac
  done
}

# refuse_mode_overrides <arg...> — the settings pin is only structural if the
# caller cannot out-argue it. Each flag below either overrides the fragment's
# defaultMode or removes the allowlist from the approval path entirely, so a
# pinned fragment with `--permission-mode auto` appended after it is not a
# pinned posture at all. Refused for the same reason `--bare` is: the launch
# shape belongs to this script, not to a caller (fleet-autonomy D-19, REQ-E1.4).
refuse_mode_overrides() {
  for rm_a in "$@"; do
    case $rm_a in
      --dangerously-skip-permissions | --permission-mode | --permission-mode=*)
        echo "$me: refusing '$rm_a' in the launch argv - it would override the pinned worker-settings posture (fleet-autonomy D-19, REQ-E1.4)" >&2
        return 2
        ;;
    esac
  done
}

# worker_settings_path — print the reviewed permission fragment the launch
# pins, resolved from this script's own location so a marketplace install
# finds it. Fails closed when it cannot be read: an unverifiable mode source is
# no mode source, and a worker launched without one inherits the operator's
# (see the header).
worker_settings_path() {
  ws_dir=$(cd "$script_dir/../config" 2>/dev/null && pwd -P) || ws_dir="$script_dir/../config"
  ws_path="$ws_dir/worker-settings.json"
  if [ ! -f "$ws_path" ] || [ ! -r "$ws_path" ]; then
    echo "$me: refusing to launch: worker-settings fragment $ws_path missing or unreadable - without it the worker inherits the operator's permission mode (fleet-autonomy D-19, REQ-E1.4)" >&2
    return 7
  fi
  printf '%s\n' "$ws_path"
}

# dispatch_env_path — print the environment-hardening wrapper the worker is
# launched THROUGH. D-10/REQ-D1.1 say every fleet-launched session goes through
# it; this rung used to exec the CLI directly, so its workers got neither the
# ghost-text pin nor a resolvable planwright root — and without the root the
# worker-settings auto-approve hook cannot find its script, so the worker asks
# permission for commands the guard would have approved. Fails closed: a launch
# that cannot apply the pin is not the pinned launch shape.
dispatch_env_path() {
  de_dir=$(cd -- "$script_dir" 2>/dev/null && pwd -P) || de_dir="$script_dir"
  de_path="$de_dir/fleet-dispatch-env.sh"
  # Invoked directly (it heads the launch argv), so the exec bit is what the
  # launch depends on; a readable-but-not-executable wrapper would otherwise
  # surface much later as an opaque worker exit 126.
  if [ ! -x "$de_path" ]; then
    echo "$me: refusing to launch: dispatch-env wrapper $de_path missing or not executable - the worker would run without the ghost-text pin and without a resolvable planwright root (fleet-autonomy D-10, REQ-D1.1)" >&2
    return 8
  fi
  printf '%s\n' "$de_path"
}

# guard_preflight <dispatch-env> <cwd> — the LAUNCH PREFLIGHT (see the
# header): prove the wired hook approves a worker's opening plugin-script call
# under every root it could name, before anything is spawned. Prints nothing
# on success; on a refusal names each root that failed and returns 9 (or 0 with
# the same message when PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT=warn).
guard_preflight() {
  gp_env=$1
  gp_cwd=$2
  gp_mode=${PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT:-refuse}
  case $gp_mode in
    refuse | warn) ;;
    off) return 0 ;;
    *)
      echo "$me: invalid PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT '$gp_mode' (refuse|warn|off)" >&2
      return 2
      ;;
  esac
  gp_dir=$(cd -- "$(dirname "$gp_env")" 2>/dev/null && pwd -P) || gp_dir=$(dirname "$gp_env")
  gp_launcher=$(cd -- "$gp_dir/.." 2>/dev/null && pwd -P) || gp_launcher=''
  # The hook a worker runs is the one under the CLAUDE_PLUGIN_ROOT the wrapper
  # exports (config/worker-settings.json names it through that variable): this
  # launcher's root, unless the launcher itself was started with one already
  # set, in which case another install's copy gates the worker. Prove that
  # file, and read the installed roots through the resolver beside it, so the
  # proof is of what the worker is actually gated by.
  gp_hook_root=$("$gp_env" --print 2>/dev/null | sed -n 's/^CLAUDE_PLUGIN_ROOT=//p' | head -n 1)
  [ -n "$gp_hook_root" ] || gp_hook_root=$gp_launcher
  gp_hook_root=$(cd -- "$gp_hook_root" 2>/dev/null && pwd -P) || gp_hook_root=$gp_launcher
  gp_guard="$gp_hook_root/scripts/worker-command-guard.sh"
  # Executable, not merely readable: the wrapper execs it, and a guard that
  # cannot run would otherwise read as "does not approve" every root below.
  if [ ! -x "$gp_guard" ]; then
    echo "$me: launch preflight: the auto-approve hook $gp_guard is missing or not executable; the worker would prompt on every routine command" >&2
    [ "$gp_mode" = warn ] && return 0
    return 9
  fi
  gp_tmp=$(mktemp) || {
    echo "$me: launch preflight: cannot create a temp file for the proof record (TMPDIR=${TMPDIR:-/tmp})" >&2
    [ "$gp_mode" = warn ] && return 0
    return 2
  }
  gp_nl=$(printf '\nx')
  gp_nl=${gp_nl%x}
  gp_seen=''
  # One line per root proved (`ok` or `failed <root>`), so the record tells
  # "nothing was proved" apart from "everything passed": a proof that could
  # not run must never read as a pass.
  {
    printf '%s\n' "$gp_launcher" "$gp_hook_root"
    /bin/sh "$gp_hook_root/scripts/resolve-installed-roots.sh" 2>/dev/null || :
  } | while IFS= read -r gp_root; do
    [ -n "$gp_root" ] || continue
    gp_root=$(cd -- "$gp_root" 2>/dev/null && pwd -P) || continue
    case "$gp_nl$gp_seen" in *"$gp_nl$gp_root$gp_nl"*) continue ;; esac
    gp_seen="$gp_seen$gp_root$gp_nl"
    gp_cmd="$gp_root/scripts/resolve-rule-doc.sh spec-format"
    gp_payload=$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' \
      "$(printf '%s' "$gp_cmd" | json_escape)" "$(printf '%s' "$gp_cwd" | json_escape)")
    gp_out=$(printf '%s\n' "$gp_payload" | "$gp_env" "$gp_guard" 2>/dev/null) || gp_out=''
    case $gp_out in
      *'"permissionDecision":"allow"'*) printf 'ok\n' ;;
      *) printf 'failed %s\n' "$gp_root" ;;
    esac
  done >"$gp_tmp" || {
    rm -f "$gp_tmp"
    echo "$me: launch preflight: could not record the proof (writing $gp_tmp failed)" >&2
    [ "$gp_mode" = warn ] && return 0
    return 2
  }
  gp_tested=$(awk 'END { print NR }' "$gp_tmp" 2>/dev/null) || gp_tested=0
  gp_failed=$(sed -n 's/^failed //p' "$gp_tmp" 2>/dev/null) || gp_failed=''
  rm -f "$gp_tmp"
  if [ "${gp_tested:-0}" -eq 0 ]; then
    echo "$me: launch preflight: proved nothing - no candidate root resolved (launcher $gp_launcher, hook root $gp_hook_root)" >&2
    [ "$gp_mode" = warn ] && return 0
    return 9
  fi
  [ -n "$gp_failed" ] || return 0
  printf '%s\n' "$gp_failed" | while IFS= read -r gp_root; do
    echo "$me: launch preflight: the auto-approve hook does not approve '$gp_root/scripts/resolve-rule-doc.sh spec-format' - a worker whose skill resolves to that root stalls on its first doctrine call (check jq is installed, and that the hook resolves the root: PLANWRIGHT_ROOT / CLAUDE_PLUGIN_ROOT / scripts/resolve-installed-roots.sh)" >&2
  done
  if [ "$gp_mode" = warn ]; then
    echo "$me: launch preflight: continuing anyway (PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT=warn)" >&2
    return 0
  fi
  echo "$me: refusing to launch: the worker would pend on its opening plugin-script call (exit 9; PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT=warn to launch regardless)" >&2
  return 9
}

# register_dispatch <worker> <scope> <dir> <checkout> [<pid>] — write the
# dispatch record through the one registration seam (fleet-lifecycle-closure
# Task 3; REQ-E1.1, REQ-E1.2).
#
# The SUPERVISOR pid is the death handle: it owns the fifos, the journal, and
# the worker's lifetime, so it is what a close verb acts on, and it is the pid
# this rung's own liveness already reads. The caller passes it directly on the
# foreground path (this process IS the supervisor); on the detached path it is
# read back from the pid file, which `supervise` writes with a plain redirect —
# so the file can EXIST while still empty, and a launcher that polled for its
# existence can read nothing. A short bounded re-read closes that window;
# failing that, the record lands with the column blank rather than with a pid
# that is wrong.
#
# <checkout> is the TOWER's checkout, passed explicitly because `cmd_launch` may
# already have cd'd into the worker's directory: a cwd-derived hash there would
# mint an owner token for a tower that exists nowhere, which is worse than the
# unknown-owner it would otherwise be.
#
# Best-effort by contract (REQ-E1.4): the exit is discarded so a registry
# failure never fails a launch whose supervisor is already up. stderr is left
# alone on purpose — an unregistered worker is the leak this closes. Readable,
# not executable: the call is `/bin/sh <path>`, so a dropped exec bit must not
# silently switch registration off with nothing on stderr.
register_dispatch() {
  rd_reg="$script_dir/fleet-register.sh"
  if [ ! -r "$rd_reg" ]; then
    echo "$me: cannot register $1: $rd_reg is missing or unreadable; this worker will not appear in the fleet inventory" >&2
    return 0
  fi
  rd_scope=$2
  # A resume relaunch carries no scope argument; the launch that created the
  # worker persisted it, so read it back rather than recording the unit as
  # scopeless on every recovery. Still nothing found means absent, which the
  # store spells `-`; inventing a word like `unknown` would read as data.
  [ -n "$rd_scope" ] || rd_scope=$(cat "$3/scope" 2>/dev/null) || rd_scope=''
  [ -n "$rd_scope" ] || rd_scope='-'
  rd_pid=${5:-}
  rd_tries=0
  while [ -z "$rd_pid" ] && [ "$rd_tries" -lt 20 ]; do
    rd_pid=$(cat "$3/supervisor.pid" 2>/dev/null) || rd_pid=''
    case $rd_pid in
      '' | 0* | *[!0-9]*) rd_pid='' ;;
      *) break ;;
    esac
    # The supervisor may also have finished already, in which case there is no
    # pid to wait for and a blank column is the honest record.
    [ -f "$3/result" ] && break
    rd_tries=$((rd_tries + 1))
    sleep 0.05
  done
  set -- --handle "$1" --scope "$rd_scope" \
    --backend stream-json-persistent --state-dir "$3" --checkout "$4"
  case $rd_pid in
    '' | 0* | *[!0-9]*) ;;
    *) set -- "$@" --death-handle "process $rd_pid" ;;
  esac
  /bin/sh "$rd_reg" "$@" >/dev/null </dev/null || true
}

# --- the close (the release set) --------------------------------------------

# The classes a stop walks, in release order. Processes go first because a
# release that cannot complete aborts the walk: breaking the locks and deleting
# the stdio fifos of a worker still running would leave it alive with no
# channel to answer it on and no receipt lock to protect its journal.
release_classes='process locks scratch attention'

# The locks this rung's worker dir can hold.
lock_classes='journal.lock recover.lock launch.lock'

# scratch_walk <dir> <probe|release> — visit every scratch path present under
# <dir>; zero when at least one was there. Scratch is the stdio fifos the
# supervisor owns, the staging files this script's writers create beside their
# targets, and the residue of a broken lock. Everything else in the state
# directory is the durable record a close keeps: the capture, the journal, the
# session, the stored envelopes, and the result.
#
# The probe and the release share one function because they must share one glob
# list, and because the paths never become text. Handing a caller a
# newline-delimited list would split a filename containing a newline into a
# second, relative path, which the release would then delete from whatever
# directory the operator happened to run the close in; the worker can create
# such a name, and its state directory is a path it knows.
scratch_walk() {
  case $- in
    *f*) sw_restore='set -f' ;;
    *) sw_restore='set +f' ;;
  esac
  set +f
  sw_found=1
  for sw_p in "$1/in.fifo" "$1/out.fifo" \
    "$1"/.init.* "$1"/.journal.* "$1"/.session.* "$1"/.pid.* "$1"/*.broken.*; do
    [ -e "$sw_p" ] || continue
    sw_found=0
    [ "$2" = release ] || break
    # `rm -rf`, not `rm -f`: a lock a stale-break renamed out of the way is a
    # directory, and `rm -f` cannot remove one. The class would then read held
    # on every later close, with no re-invocation able to make progress.
    rm -rf "$sw_p" 2>/dev/null || :
  done
  $sw_restore
  return "$sw_found"
}

# ps_rows — one `<pid> <ppid> <args>` row per process on the host.
#
# `-ww` is what keeps the supervisor's long argv, which carries the
# state-directory path the match keys on, from being truncated to terminal
# width by BSD ps; a ps that rejects the flag degrades to the narrow form
# rather than to nothing. Each candidate is shape-checked rather than trusted
# by exit status, the discipline stat_mtime applies to its own two flavors.
ps_rows() {
  pr_out=$(ps -A -ww -o pid=,ppid=,args= 2>/dev/null) || pr_out=''
  if ! ps_rows_shaped "$pr_out"; then
    pr_out=$(ps -A -o pid=,ppid=,args= 2>/dev/null) || pr_out=''
    ps_rows_shaped "$pr_out" || return 1
  fi
  printf '%s\n' "$pr_out"
}

ps_rows_shaped() {
  [ -n "$1" ] || return 1
  prs_first=${1%%"$LF"*}
  while [ "${prs_first# }" != "$prs_first" ]; do
    prs_first=${prs_first# }
  done
  case ${prs_first%% *} in
    '' | *[!0-9]*) return 1 ;;
  esac
}

# stop_candidates <dir> <worker> — every live pid belonging to the worker whose
# runtime state lives at <dir>, one per line. Non-zero when the host's process
# table cannot be read, so a caller reports the class held rather than assuming
# it is free.
#
# Two seeds. The supervisor is matched on the exact `_supervise <worker> <dir>`
# triple this script re-execs itself with. Searching argv for the bare
# directory would over-match twice over: one handle prefixes another (`api`
# against `api2`'s state directory), and any process that merely *names* the
# directory — an operator tailing the event capture — would be swept in with
# its whole subtree. The worker, and a supervisor whose argv cannot be read,
# come from the pids the state directory records. Neither seed is a process
# name or a command pattern.
#
# The worker's own children carry neither the argv nor a pid file, so they are
# reached by walking the parent map down from the seeds. pid 1 is never a root:
# an expansion that reached it would enumerate every orphan on the host.
#
# The caller's own process and its ancestors are excluded: a close invoked from
# inside the tree it is closing must not kill the closer mid-release. That
# exclusion is also why such a close cannot be allowed to proceed at all: the
# supervisor and the worker fall inside it while their other children do not, so
# the walk would signal part of the tree and then report the whole release set
# free. `stop_self_hosted` refuses that case before this runs.
#
# The match text goes through the environment rather than `awk -v`, which
# rewrites backslash escapes in the value it assigns: the fleet home is taken
# verbatim from the operator's configuration, and a `\t` in it would otherwise
# make the comparison silently target a path nobody asked for. It is scoped to
# the awk invocation rather than exported, so the worker's state-directory path
# does not end up in the environment of every later child of the close.
stop_candidates() {
  sc_dir=$1
  sc_snap=$(ps_rows) || return 1
  sc_seed=''
  for sc_f in supervisor.pid worker.pid; do
    sc_p=$(cat "$sc_dir/$sc_f" 2>/dev/null) || sc_p=''
    if valid_posnum "${sc_p:-}"; then
      sc_seed="$sc_seed $sc_p"
    fi
  done
  printf '%s\n' "$sc_snap" | SC_MATCH="_supervise $2 $sc_dir" awk -v seeds="$sc_seed" -v self_pid="$$" '
    BEGIN {
      sup = ENVIRON["SC_MATCH"]
      # `index(s, "")` is 1, so an empty match string would mark every process
      # on the host. It cannot be empty as written — the value has a literal
      # prefix — but this verb sends signals, so the one input whose emptiness
      # inverts "matches nothing" into "matches everything" is checked rather
      # than reasoned about. Exiting non-zero reports the class held.
      if (sup == "") exit 2
    }
    $1 ~ /^[0-9]+$/ {
      ppid[$1] = $2
      order[++n] = $1
      if (index($0, sup)) want[$1] = 1
    }
    END {
      m = split(seeds, s, " ")
      for (i = 1; i <= m; i++) if (s[i] != "") want[s[i]] = 1
      delete want["0"]
      delete want["1"]
      for (pass = 1; pass <= n; pass++) {
        grew = 0
        for (i = 1; i <= n; i++) {
          p = order[i]
          if (!(p in want) && (p in ppid) && (ppid[p] in want)) {
            want[p] = 1
            grew = 1
          }
        }
        if (!grew) break
      }
      # The closer, everything it descends from, and everything under it. The
      # descendants matter as much as the ancestors: this function runs in a
      # forked subshell, so a close invoked from inside the tree it closes
      # would otherwise enumerate its own scanner on every poll and never see
      # the candidate set empty. pid 0 and pid 1 are filtered from the result
      # rather than seeded here: seeding them would claim every orphan on the
      # host, including the orphaned worker a close most needs to find.
      #
      # Only the closer itself roots the descendant walk. Rooting it at the
      # ancestors as well would claim their other children — and since that
      # chain ends at pid 1, whose descendants are every process on the host,
      # the exclusion set would swallow the very tree the close is looking for
      # and every stop would report the process class released over a live
      # worker.
      p = self_pid
      for (i = 0; i <= n; i++) {
        mine[p] = 1
        if (!(p in ppid) || ppid[p] == "" || ppid[p] == "0") break
        p = ppid[p]
      }
      kin[self_pid] = 1
      for (pass = 1; pass <= n; pass++) {
        grew = 0
        for (i = 1; i <= n; i++) {
          p = order[i]
          if (!(p in kin) && (ppid[p] in kin)) {
            kin[p] = 1
            mine[p] = 1
            grew = 1
          }
        }
        if (!grew) break
      }
      # `p in ppid` is presence in the process table. The recorded pids are
      # seeded without a liveness check of their own, so a worker closed while
      # its pid files survive would otherwise report its process class held
      # forever, on two pids that no longer exist.
      for (p in want) {
        if (!(p in ppid) || (p in mine)) continue
        if (p == "0" || p == "1") continue
        print p
      }
    }'
}

# stop_self_hosted <dir> <worker> — zero when this process is running inside the
# very tree it has been asked to close.
#
# Such a close cannot work, and it fails in the worst direction. The candidate
# walk excludes the closer and everything it descends from, so the supervisor
# and the worker are invisible to it while their *other* children are not: it
# would SIGTERM and then SIGKILL part of the tree, find nothing left that it can
# see, clear the pid files as though the tree were gone, and report `stopped` —
# leaving the worker alive, half its children dead, its stdio fifos deleted, and
# nothing recorded for `launch` to refuse a second supervisor on.
#
# The ancestry is tested against the supervisor's argv first, and against the
# recorded pids only when argv cannot be trusted. The two seeds fail in opposite
# directions and neither is safe alone. A pid file outlives the process it
# names, and a recycled pid is very often an ancestor of every shell on the
# host: a leftover state directory whose `supervisor.pid` now names the session
# manager would make every close for that handle look self-hosted and be
# refused, forever — and this verb is the only one that clears those files, so
# `launch` and `recover` would refuse the handle too. The argv match cannot be
# forged that way, and the worker is spawned as a child of the process carrying
# it, so everything genuinely inside the tree is reachable through it. But argv
# is exactly what a narrow `ps` truncates, and there the missing match is not
# evidence of absence; refusing to fall back would let a real self-close proceed
# and kill part of its own tree.
#
# So the fallback is conditioned on which of those two worlds this host is in.
# When argv is readable, a missing match means no live supervisor, and an
# ancestor named by a pid file is a recycled pid to be ignored. When argv is
# truncated, the recorded pids are all there is, and the close fails closed.
stop_self_hosted() {
  # The snapshot and the verdict about its argv fidelity come from one probe.
  # Taken separately they can disagree — a transient fork failure degrades the
  # snapshot to the narrow form while an independent retry of `-ww` succeeds —
  # and the disagreement resolves toward proceeding, which is the direction that
  # kills.
  ssh_wide=1
  ssh_snap=$(ps -A -ww -o pid=,ppid=,args= 2>/dev/null) || ssh_snap=''
  if ! ps_rows_shaped "$ssh_snap"; then
    ssh_wide=0
    ssh_snap=$(ps -A -o pid=,ppid=,args= 2>/dev/null) || ssh_snap=''
    ps_rows_shaped "$ssh_snap" || return 2
  fi
  ssh_seed=''
  if [ "$ssh_wide" = 0 ]; then
    for ssh_f in supervisor.pid worker.pid; do
      ssh_p=$(cat "$1/$ssh_f" 2>/dev/null) || ssh_p=''
      if valid_posnum "${ssh_p:-}"; then
        ssh_seed="$ssh_seed $ssh_p"
      fi
    done
  fi
  printf '%s\n' "$ssh_snap" | SC_MATCH="_supervise $2 $1" awk -v seeds="$ssh_seed" -v self_pid="$$" '
    BEGIN {
      sup = ENVIRON["SC_MATCH"]
      # `index(s, "")` is 1, so an empty match string would mark every process
      # on the host. It cannot be empty as written — the value has a literal
      # prefix — but this verb sends signals, so the one input whose emptiness
      # inverts "matches nothing" into "matches everything" is checked rather
      # than reasoned about. Exit 2 is the cannot-determine answer, which the
      # caller refuses on.
      if (sup == "") exit 2
    }
    $1 ~ /^[0-9]+$/ {
      ppid[$1] = $2
      n++
      if (index($0, sup)) owner[$1] = 1
    }
    END {
      # The 0/1 filter applies to the seeds only. An argv match at pid 1 is a
      # real supervisor running as container init, and discarding it here would
      # let a self-close from inside that tree proceed.
      m = split(seeds, s, " ")
      for (i = 1; i <= m; i++) {
        if (s[i] != "" && s[i] != "0" && s[i] != "1") owner[s[i]] = 1
      }
      p = self_pid
      for (i = 0; i <= n; i++) {
        if (p in owner) exit 0
        if (!(p in ppid) || ppid[p] == "" || ppid[p] == "0" || p == "1") break
        p = ppid[p]
      }
      exit 1
    }'
}

# stop_live <space-separated pids> — the deduplicated subset still signallable,
# space-separated on stdout.
stop_live() {
  sl_out=''
  for sl_p in $1; do
    valid_posnum "$sl_p" || continue
    [ "$sl_p" = 1 ] && continue
    case " $sl_out " in
      *" $sl_p "*) continue ;;
    esac
    # pid_live, not `kill -0`: dropping a live-but-unsignallable pid here
    # would empty the process class and report the tree stopped over a worker
    # still running.
    pid_live "$sl_p" || continue
    sl_out="$sl_out $sl_p"
  done
  printf '%s' "${sl_out# }"
}

# The settling wait after SIGKILL, in seconds. Not operator-tunable: SIGKILL is
# not refusable, so this bounds how long the kernel takes to reap, not how long
# a process is given to cooperate.
kill_settle=5

# The largest grace a caller may ask for.
grace_max=300

# The SIGTERM-to-SIGKILL grace a caller gets without asking.
grace_default=5

# release_processes <dir> <worker> <grace> — SIGTERM the worker's process tree,
# then SIGKILL whatever is still there after <grace> seconds. Children do not
# reliably die with a parent SIGTERM, so the escalation is not optional.
#
# The target set accumulates in `stop_tracked` rather than being recomputed
# from scratch each round. A child that ignores SIGTERM is reparented to pid 1
# when its parent dies, which drops it out of the descendant walk entirely — a
# set rebuilt from the walk alone would then find nothing and report the class
# released while that child ran on, which is the exact leak this verb exists to
# close. Candidates discovered during the wait are folded in, so a process the
# worker forks mid-close is signalled too.
#
# The wait is bounded by wall clock rather than by a tick count: a poll costs a
# full process-table scan, so on a busy host a tick is far longer than the
# sleep and a counted grace would silently be several times the seconds the
# operator asked for.
release_processes() {
  rp_dir=$1
  rp_worker=$2
  rp_grace=$3
  rp_found=$(stop_candidates "$rp_dir" "$rp_worker") || {
    echo "$me: cannot read the process table; the process class is left held" >&2
    return 1
  }
  stop_tracked=$(stop_live "$stop_tracked $rp_found")
  if [ -z "$stop_tracked" ]; then
    clear_pidfiles "$rp_dir"
    return 0
  fi
  for rp_sig in TERM KILL; do
    for rp_p in $stop_tracked; do
      kill "-$rp_sig" "$rp_p" 2>/dev/null || :
    done
    case $rp_sig in
      TERM) rp_wait=$rp_grace ;;
      *) rp_wait=$kill_settle ;;
    esac
    rp_now=$(now_epoch) || return 1
    rp_until=$((rp_now + rp_wait))
    while :; do
      rp_found=$(stop_candidates "$rp_dir" "$rp_worker") || return 1
      stop_tracked=$(stop_live "$stop_tracked $rp_found")
      if [ -z "$stop_tracked" ]; then
        clear_pidfiles "$rp_dir"
        return 0
      fi
      rp_now=$(now_epoch) || return 1
      # `-le`, so the deadline is a floor: `date +%s` truncates, so a TERM sent
      # at x.999 would otherwise reach a `-lt` deadline a millisecond later and
      # escalate having given the worker no grace at all.
      [ "$rp_now" -le "$rp_until" ] || break
      sleep 0.1
    done
  done
  return 1
}

# clear_pidfiles <dir> — drop pid files that now record nothing live.
#
# `rm -rf`, for the reason `release_locks` uses it: the held-probe gates on mere
# existence, so anything at those paths that `rm -f` cannot remove — a directory
# the worker created there — would hold the class forever with no re-invocation
# able to make progress. `${1:?}` guards the recursive removal against an empty
# directory argument, and does so by ending the shell rather than the function,
# which is why the trailing `|| :` on that line does not make it non-fatal.
clear_pidfiles() {
  rm -rf "${1:?}/supervisor.pid" "${1:?}/worker.pid" 2>/dev/null || :
}

held_process() {
  hp_found=$(stop_candidates "$1" "$2") || return 0
  [ -n "$(stop_live "$stop_tracked $hp_found")" ] && return 0
  # A pid file recording nothing live is still this class's residue, and the
  # close has to reach it: a supervisor killed before its own cleanup leaves the
  # file behind, and once the host reuses that pid `launch` refuses the handle
  # as already running with nothing able to clear it. A worker that ended
  # cleanly removed its own files, so this does not disturb `already-closed`.
  [ -e "$1/supervisor.pid" ] || [ -e "$1/worker.pid" ]
}

# `-e` rather than `-d`: a lock path that exists as a regular file blocks the
# `mkdir` election just as effectively as a directory does, and gating on `-d`
# would leave the verb it blocks wedged with nothing able to clear it.
held_locks() {
  for hl_l in $lock_classes; do
    [ -e "$1/$hl_l" ] && return 0
  done
  return 1
}

# `rm -rf` rather than `rmdir`: an election lock carries its holder's pid
# inside it, so it is not an empty directory. The names are literals from
# `lock_classes` under a directory the caller has already validated.
release_locks() {
  rl_rc=0
  for rl_l in $lock_classes; do
    [ -e "$1/$rl_l" ] || continue
    rm -rf "${1:?}/$rl_l" 2>/dev/null || :
    [ -e "$1/$rl_l" ] && rl_rc=1
  done
  return "$rl_rc"
}

held_scratch() {
  scratch_walk "$1" probe
}

release_scratch() {
  scratch_walk "$1" release
  ! scratch_walk "$1" probe
}

# The attention store's layout is read directly, as the sibling fleet scripts
# already read it: fleet-attention.sh exposes `clear` but no query, and the
# row's presence is what "held" means here. The string coercion is that
# script's own comparison discipline — a bare `$1 == w` equates all-numeric
# handles (`1`, `01`, `1.0`) and would report the wrong worker's row.
#
# A store that exists but cannot be read counts as held: the same fail-closed
# posture the process probe takes, so an unreadable store cannot make a class
# that is still occupied report as released.
held_attention() {
  [ -f "$1" ] || return 1
  [ -r "$1" ] || return 0
  awk -F'\t' -v w="$2" '($1 "") == (w "") { found = 1 } END { exit found ? 0 : 1 }' "$1" 2>/dev/null
  ha_rc=$?
  # Three outcomes from two exit codes plus everything else. The caller reads
  # any non-zero as "not held" and skips the class, so an awk that failed
  # outright — a broken tool, an I/O error mid-read — would silently take the
  # attention class out of the release set and let the close report success it
  # never earned. Only a clean exit 1 means not held; anything the tool could
  # not answer counts as held, and the close reports partial instead.
  case $ha_rc in
    1) return 1 ;;
    *) return 0 ;;
  esac
}

# Clearing the row is half the release. The other half is the journal: a
# receipt left `pending` is what `alarm-scan` re-queues a decision item from,
# so a closed worker would keep re-arming the class this call just released,
# and an operator answering that item would write into a fifo the same close
# deleted. A close makes those receipts undeliverable by definition, and a
# later `--resume` re-opens any the resumed worker asks again.
release_attention() {
  journal_close "$2" || return 1
  /bin/sh "$FA" clear "$1" >/dev/null
}

journal_close() {
  [ -f "$1/journal" ] || return 0
  # Readable, not merely present. The exit-code reading below leans on awk
  # separating "no pending rows" (1) from "could not read" (something else),
  # and busybox awk does not make that separation — an unreadable journal
  # exits 1 there and would clear the attention row with every receipt still
  # pending. Checking first makes the distinction independent of which awk
  # this host ships.
  [ -r "$1/journal" ] || {
    echo "$me: the receipt journal is unreadable; the attention class is left held" >&2
    return 1
  }
  # Three outcomes, not two: awk exits 1 for "no pending rows" and something
  # else entirely when it could not read the journal. Folding the second into
  # the first would clear the attention row while every receipt stayed pending,
  # which is the re-arming this function exists to stop.
  awk -F'\t' '$4 == "pending" { found = 1 } END { exit found ? 0 : 1 }' "$1/journal"
  case $? in
    0) ;;
    1) return 0 ;;
    *)
      echo "$me: cannot read the receipt journal; the attention class is left held" >&2
      return 1
      ;;
  esac
  journal_lock "$1" || return 1
  jc_now=$(now_epoch) || jc_now=0
  jc_tmp=$(mktemp "$1/.journal.XXXXXX") || {
    journal_unlock "$1"
    return 1
  }
  jc_rc=0
  awk -F'\t' -v OFS='\t' -v ep="$jc_now" \
    '$4 == "pending" { $4 = "undeliverable"; $5 = ep } { print }' "$1/journal" >"$jc_tmp" \
    && mv "$jc_tmp" "$1/journal" || jc_rc=1
  [ "$jc_rc" = 0 ] || rm -f "$jc_tmp" 2>/dev/null
  journal_unlock "$1"
  return "$jc_rc"
}

# stop_held / stop_release <class> <dir> <worker> <attention-store> <grace>.
# The unknown-class arms are not defensive filler: a class added to
# `release_classes` without both arms would otherwise report itself
# permanently held, or silently released, with nothing on stderr.
stop_held() {
  case $1 in
    process) held_process "$2" "$3" ;;
    locks) held_locks "$2" ;;
    scratch) held_scratch "$2" ;;
    attention) held_attention "$4" "$3" ;;
    *)
      echo "$me: no held-probe for release class '$1'" >&2
      return 0
      ;;
  esac
}

stop_release() {
  case $1 in
    process) release_processes "$2" "$3" "$5" ;;
    locks) release_locks "$2" ;;
    scratch) release_scratch "$2" ;;
    attention) release_attention "$3" "$2" ;;
    *)
      echo "$me: no release for class '$1'" >&2
      return 1
      ;;
  esac
}

# --- subcommands ------------------------------------------------------------

cmd_launch() {
  worker=''
  scope=''
  prompt_file=''
  run_cwd=''
  foreground=0
  resume_sid=''
  while [ $# -gt 0 ]; do
    case $1 in
      --prompt-file)
        [ $# -ge 2 ] || usage
        prompt_file=$2
        shift 2
        ;;
      --cwd)
        [ $# -ge 2 ] || usage
        run_cwd=$2
        shift 2
        ;;
      --foreground)
        foreground=1
        shift
        ;;
      --resume-session)
        # Internal: recover's relaunch arm.
        [ $# -ge 2 ] || usage
        resume_sid=$2
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        usage
        ;;
      *)
        if [ -z "$worker" ]; then
          worker=$1
        elif [ -z "$scope" ]; then
          scope=$1
        else
          usage
        fi
        shift
        ;;
    esac
  done
  valid_field "${worker:-}" || {
    echo "$me: invalid worker handle" >&2
    exit 2
  }
  # The internal --resume-session seam gets the same ingress grammar as every
  # other input: cmd_recover validates the persisted sid before passing it,
  # but a direct invocation must not ride an out-of-grammar id into the argv.
  if [ -n "$resume_sid" ] && ! valid_reqid "$resume_sid"; then
    echo "$me: invalid --resume-session id" >&2
    exit 2
  fi
  if [ -z "$resume_sid" ]; then
    valid_field "${scope:-}" || {
      echo "$me: invalid scope" >&2
      exit 2
    }
    if [ -z "$prompt_file" ] || [ ! -r "$prompt_file" ]; then
      echo "$me: --prompt-file missing or unreadable" >&2
      exit 2
    fi
  fi
  refuse_bare "$@" || exit 2
  refuse_settings "$@" || exit 2
  refuse_mode_overrides "$@" || exit 2
  worker_settings=$(worker_settings_path) || exit 7
  dispatch_env=$(dispatch_env_path) || exit 8
  guard_preflight "$dispatch_env" "${run_cwd:-$PWD}"
  gp_rc=$?
  [ "$gp_rc" -eq 0 ] || exit "$gp_rc"

  dir=$(worker_dir "$worker") || exit 2
  # The handle grammar blocks traversal tokens but not a symlink planted under
  # the fleet home, and this verb creates fifos and pid files inside whatever
  # it is handed. The close verb already refuses a symlinked state directory;
  # refusing it here too is what stops one being FOLLOWED in the first place,
  # which is the earlier and more useful of the two checks.
  [ ! -L "$dir" ] || {
    echo "$me: refusing to launch $worker: its state directory is a symlink" >&2
    exit 2
  }
  mkdir -p "$dir" || exit 2
  chmod 700 "$dir" 2>/dev/null || :

  # Single launch initiator, on the atomic-mkdir election `recover` already
  # uses. Two concurrent launches for one worker otherwise both reach
  # `supervise`, and the second overwrites the first's pid files — orphaning a
  # supervisor that nothing records and nothing can close.
  #
  if ! lock_take "$dir/launch.lock" "$launch_lock_stale"; then
    echo "$me: a launch is already in flight for $worker (refused: single initiator)" >&2
    exit 3
  fi
  trap 'lock_drop "$dir/launch.lock"' EXIT

  # The election ends when the first launch releases its lock, so a launch
  # arriving after that against a supervisor already up needs its own refusal:
  # it reaches the same double-supervisor outcome by the later route.
  if worker_alive "$dir"; then
    echo "$me: worker $worker is already running; launch refused" >&2
    exit 3
  fi

  if [ -n "$scope" ]; then
    printf '%s\n' "$scope" >"$dir/scope"
  fi

  init_msg=$(mktemp "$dir/.init.XXXXXX") || exit 2
  if [ -n "$resume_sid" ]; then
    # Resume relaunch: no new prompt — the recovered session carries its
    # context; steering arrives later through the fifo.
    : >"$init_msg"
  else
    build_initial_msg "$prompt_file" "$init_msg" || {
      rm -f "$init_msg"
      exit 2
    }
  fi

  # The pinned launch shape (REQ-A1.3, D-12; fleet-autonomy D-10, D-19): the
  # environment-hardening wrapper in front (it execs the rest, so the fifos
  # below still attach to the CLI), then -p with stream-json both ways,
  # --verbose (required with -p stream-json output), the stdio permission
  # prompt tool (the receipt channel), the reviewed worker-settings fragment
  # (the mode source), and NEVER --bare.
  set -- "$dispatch_env" "$cli" -p --input-format stream-json --output-format stream-json \
    --verbose --permission-prompt-tool stdio --settings "$worker_settings" "$@"
  if [ -n "$resume_sid" ]; then
    set -- "$@" --resume "$resume_sid"
  fi

  # Capture the TOWER's checkout before any cd: past this point the cwd is the
  # worker's, and an owner token hashed over that names a tower nobody
  # published (fleet-register.sh, "The CHECKOUT feeds the composite identity").
  tower_checkout=$(git rev-parse --show-toplevel 2>/dev/null) || tower_checkout=''
  [ -n "$tower_checkout" ] || tower_checkout=$(pwd)

  if [ -n "$run_cwd" ]; then
    cd "$run_cwd" || {
      rm -f "$init_msg"
      echo "$me: --cwd not accessible" >&2
      exit 2
    }
  fi

  if [ "$foreground" = 1 ]; then
    # This process becomes the supervisor, so it is its own death handle; the
    # record has to land before supervise blocks.
    register_dispatch "$worker" "$scope" "$dir" "$tower_checkout" "$$"
    supervise "$worker" "$dir" "$init_msg" "$@"
    return $?
  fi
  # Detached: re-exec so the supervisor process records its OWN pid ($$ in a
  # backgrounded subshell would report this parent instead). Two visibility
  # guarantees the naive `>/dev/null 2>&1 &` form broke:
  #   1. The supervisor's stderr goes to a per-worker log, not /dev/null, so a
  #      startup failure (mkfifo, worker exec) is inspectable.
  #   2. `$self` (absolute) is used, not `$0`, so a relative invocation plus
  #      --cwd cannot silently fail to find the script.
  # Then confirm the supervisor actually came up before reporting success:
  # supervise writes supervisor.pid right after mkfifo, so its (re)appearance
  # is the "did the supervisor start" signal. A launch that never produces it
  # is surfaced as a failure with a non-zero exit, never an optimistic
  # `launched` over a dead supervisor.
  rm -f "$dir/supervisor.pid" "$dir/worker.pid" "$dir/result"
  (/bin/sh "$self" _supervise "$worker" "$dir" "$init_msg" "$@" \
    >/dev/null 2>>"$dir/supervisor.log" </dev/null &)
  # Confirm startup by a signal that survives a fast run: supervisor.pid
  # appears while the supervisor is live, and it removes that pid plus writes a
  # `result` on exit — so a run that already finished shows `result` even
  # though supervisor.pid is gone again. Either proves the supervisor came up;
  # a launch that produces neither within the window failed before mkfifo and
  # is surfaced, never reported as an optimistic `launched`.
  li=0
  while [ "$li" -lt 50 ]; do
    if [ -s "$dir/supervisor.pid" ] || [ -f "$dir/result" ]; then
      register_dispatch "$worker" "$scope" "$dir" "$tower_checkout"
      printf 'launched %s dir %s\n' "$worker" "$dir"
      return 0
    fi
    sleep 0.1
    li=$((li + 1))
  done
  echo "$me: detached supervisor for $worker did not start within 5s; see $dir/supervisor.log" >&2
  return 2
}

cmd_answer() {
  [ $# -ge 2 ] || usage
  worker=$1
  req=$2
  shift 2
  valid_field "$worker" || {
    echo "$me: invalid worker handle" >&2
    exit 2
  }
  valid_reqid "$req" || {
    echo "$me: invalid request id" >&2
    exit 2
  }
  mode=''
  resp_file=''
  deny_msg=''
  while [ $# -gt 0 ]; do
    case $1 in
      --response-file)
        [ $# -ge 2 ] || usage
        mode='file'
        resp_file=$2
        shift 2
        ;;
      --allow)
        mode=allow
        shift
        ;;
      --deny)
        mode=deny
        shift
        ;;
      --message)
        [ $# -ge 2 ] || usage
        deny_msg=$2
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done
  [ -n "$mode" ] || usage
  if [ "$mode" = 'file' ]; then
    if [ ! -r "$resp_file" ]; then
      echo "$me: --response-file missing or unreadable" >&2
      exit 2
    fi
    # Read one byte past the 64 KiB cap so an oversize body is REFUSED whole,
    # never silently truncated into a partial (invalid) JSON frame. (The
    # command substitution strips a trailing newline, so a cap-sized payload
    # plus its final newline still fits.)
    body=$(head -c 65537 "$resp_file")
    if [ "$(printf '%s' "$body" | wc -c | tr -d ' ')" -gt 65536 ]; then
      echo "$me: --response-file exceeds the 64 KiB cap (refused, not truncated)" >&2
      exit 2
    fi
    # An empty body would emit '"response":' with no value — an invalid
    # frame on the worker's stdin. Refused fail-closed.
    if [ -z "$body" ]; then
      echo "$me: --response-file is empty" >&2
      exit 2
    fi
    # The response rides ONE line of the worker's stdin stream: an embedded
    # newline would inject extra frames into the protocol, so it is refused
    # (fail closed), never silently collapsed. (The command substitution
    # already stripped the trailing newline, so any count above zero is an
    # embedded one.)
    if [ "$(printf '%s' "$body" | wc -l | tr -d ' ')" != 0 ]; then
      echo "$me: --response-file must be single-line JSON (embedded newline refused)" >&2
      exit 2
    fi
  fi
  dir=$(worker_dir "$worker") || exit 2
  [ -d "$dir" ] || {
    echo "$me: unknown worker $worker" >&2
    exit 2
  }

  journal_lock "$dir" || exit 2
  state=$(journal_state "$dir" "$req")
  short=$(printf '%s' "$req" | cut -c1-8)
  now=$(now_epoch) || now=0
  case $state in
    '')
      journal_unlock "$dir"
      attention_failure "$worker" "$dir" \
        "undeliverable answer: request $short is not journaled for worker $worker (gone or never received) - answer NOT applied"
      exit 3
      ;;
    answered)
      journal_unlock "$dir"
      attention_failure "$worker" "$dir" \
        "undeliverable answer: request $short already answered for worker $worker - second answer NOT applied"
      exit 3
      ;;
    undeliverable)
      journal_unlock "$dir"
      attention_failure "$worker" "$dir" \
        "undeliverable answer: request $short already marked undeliverable for worker $worker"
      exit 3
      ;;
  esac

  # Channel liveness BEFORE the fifo open: a fifo with no reader blocks its
  # opener forever, so a dead supervisor/worker must become an undeliverable
  # verdict, never a hang (REQ-E1.4's dead-channel arm). A residual TOCTOU is
  # ACCEPTED here: a worker that dies in the few-syscall window between this
  # kill -0 check and the blocking open below can still wedge the open (no
  # reader). The window is not closable in portable POSIX sh — a non-blocking /
  # timed open is not expressible without a helper process — and it is far
  # narrower than the already-dead case this check catches, so the common
  # dead-channel arm is guarded and the race is left documented, not fixed.
  sup_pid=$(cat "$dir/supervisor.pid" 2>/dev/null) || sup_pid=''
  wrk_pid=$(cat "$dir/worker.pid" 2>/dev/null) || wrk_pid=''
  channel_ok=1
  valid_posnum "${sup_pid:-}" && pid_live "$sup_pid" || channel_ok=0
  valid_posnum "${wrk_pid:-}" && pid_live "$wrk_pid" || channel_ok=0
  [ -p "$dir/in.fifo" ] || channel_ok=0
  if [ "$channel_ok" = 0 ]; then
    journal_set_state "$dir" "$req" undeliverable "$now"
    journal_unlock "$dir"
    attention_failure "$worker" "$dir" \
      "undeliverable answer: channel for worker $worker is dead (request $short) - recover the worker and re-ask"
    exit 3
  fi

  case $mode in
    file)
      # $body was read and single-line-validated before the lock was taken.
      ;;
    allow)
      input_obj=$(json_input_object "$dir/req-$req.json" 2>/dev/null) || input_obj=''
      if [ -n "$input_obj" ]; then
        body=$(printf '{"behavior":"allow","updatedInput":%s}' "$input_obj")
      else
        body='{"behavior":"allow"}'
      fi
      ;;
    deny)
      deny_esc=$(printf '%s' "$deny_msg" | head -c 512 | json_escape)
      body=$(printf '{"behavior":"deny","message":"%s"}' "$deny_esc")
      ;;
  esac

  # Deliver: one line into the worker's stdin fifo, under the journal lock
  # (one writer at a time). A racing worker death turns the write into a
  # visible undeliverable verdict via write-failure, never a silent drop.
  trap '' PIPE
  if printf '{"type":"control_response","response":{"subtype":"success","request_id":"%s","response":%s}}\n' \
    "$req" "$body" >>"$dir/in.fifo" 2>/dev/null; then
    # The answer reached the worker's stdin. If the state flip fails (disk
    # full, journal replaced), the row stays `pending` — which would let
    # alarm-scan fire a spurious escalation and a second `answer` re-deliver a
    # duplicate frame. Surface it rather than reporting a clean `answered`.
    if ! journal_set_state "$dir" "$req" answered "$now"; then
      journal_unlock "$dir"
      attention_failure "$worker" "$dir" \
        "answer for worker $worker request $short was delivered but the receipt could not be marked answered - the journal is stale, do not re-answer, investigate disk/store"
      exit 2
    fi
    attention_settled "$worker" "$dir"
    journal_unlock "$dir"
    printf 'answered %s %s\n' "$worker" "$req"
  else
    journal_set_state "$dir" "$req" undeliverable "$now"
    journal_unlock "$dir"
    attention_failure "$worker" "$dir" \
      "undeliverable answer: write to worker $worker stdin failed (request $short) - recover the worker and re-ask"
    exit 3
  fi
}

cmd_recover() {
  [ $# -ge 1 ] || usage
  worker=$1
  shift
  valid_field "$worker" || {
    echo "$me: invalid worker handle" >&2
    exit 2
  }
  foreground=''
  while [ $# -gt 0 ]; do
    case $1 in
      --foreground)
        foreground=--foreground
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        usage
        ;;
    esac
  done
  dir=$(worker_dir "$worker") || exit 2
  [ -d "$dir" ] || {
    echo "$me: unknown worker $worker" >&2
    exit 2
  }

  # Single recovery initiator (REQ-E1.5): the election refuses a concurrent
  # second attempt rather than racing it, and breaks a lock whose holder is
  # gone — without that break, one SIGKILL between the election and the trap
  # that releases it wedges `recover` for this worker permanently.
  if ! lock_take "$dir/recover.lock" "$recover_lock_stale"; then
    echo "$me: recovery already in progress for $worker (refused: single initiator)" >&2
    exit 3
  fi
  trap 'lock_drop "$dir/recover.lock"' EXIT

  # Orphan liveness BEFORE --resume (REQ-E1.5): a still-alive worker or
  # supervisor is not orphaned; resuming over it would fork the session.
  for pidfile in worker.pid supervisor.pid; do
    pid=$(cat "$dir/$pidfile" 2>/dev/null) || pid=''
    if valid_posnum "${pid:-}" && pid_live "$pid"; then
      echo "$me: $pidfile ($pid) still alive for $worker - not orphaned, recovery refused" >&2
      exit 3
    fi
  done

  sid=$(cat "$dir/session" 2>/dev/null) || sid=''
  if ! valid_reqid "${sid:-}"; then
    attention_failure "$worker" "$dir" \
      "resume halt: worker $worker has no usable persisted session_id - unit halted awaiting operator direction"
    echo "$me: no usable session_id for $worker; halt (REQ-E1.5)" >&2
    exit 4
  fi

  rm -f "$dir/result"
  if [ $# -gt 0 ]; then
    set -- -- "$@"
  fi
  # `$self` (absolute), not `$0`. In detached mode `launch` now blocks until
  # the resumed supervisor writes supervisor.pid (or reports failure), so this
  # recover holds recover.lock until the new supervisor is actually up: a
  # second recover cannot slip into the old release-before-startup window and
  # fork the session, and a silently-failed detached resume now returns
  # non-zero here instead of a false `recovered`.
  if /bin/sh "$self" launch "$worker" --resume-session "$sid" ${foreground:+"$foreground"} "$@"; then
    printf 'recovered %s session %s\n' "$worker" "$sid"
  else
    ec=$?
    # The relaunch's own refusal (a launch already in flight, or a supervisor
    # that came up under someone else) is not a resume failure: halting the
    # unit on it would tell the operator to intervene while a perfectly good
    # launch is running. Pass the refusal through instead.
    if [ "$ec" = 3 ]; then
      echo "$me: relaunch for $worker refused; another launch holds this worker" >&2
      exit 3
    fi
    attention_failure "$worker" "$dir" \
      "resume halt: --resume relaunch for worker $worker failed (exit $ec) - unit halted awaiting operator direction"
    echo "$me: --resume relaunch failed for $worker (exit $ec); halt (REQ-E1.5)" >&2
    exit 5
  fi
}

cmd_stop() {
  [ $# -ge 1 ] || usage
  worker=$1
  shift
  valid_field "$worker" || {
    echo "$me: invalid worker handle" >&2
    exit 2
  }
  grace=$grace_default
  while [ $# -gt 0 ]; do
    case $1 in
      --grace)
        [ $# -ge 2 ] || usage
        grace=$2
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done
  # The grace is bounded as well as shaped: `valid_posnum` admits fifteen
  # digits, and a close that waits for a century is indistinguishable from one
  # that has hung.
  if ! valid_posnum "$grace" || [ "$grace" -gt "$grace_max" ]; then
    echo "$me: --grace must be a whole number of seconds, 1 to $grace_max (default $grace_default)" >&2
    exit 2
  fi
  dir=$(worker_dir "$worker") || exit 2
  # A close never removes the state directory, so its absence means this handle
  # names no worker — reported as such rather than as `already-closed`, which
  # would read a typo as a successful close.
  [ -d "$dir" ] || {
    echo "$me: unknown worker $worker" >&2
    exit 2
  }
  # The handle grammar blocks traversal tokens but not a symlink planted under
  # the fleet home, and this verb deletes inside whatever it is handed.
  [ ! -L "$dir" ] || {
    echo "$me: refusing to close $worker: its state directory is a symlink" >&2
    exit 2
  }
  # Three answers, not two. "Cannot determine" is refused rather than treated as
  # "not inside": the whole file's posture on the process class is fail-closed,
  # and proceeding on an unreadable table is the direction that signals.
  stop_self_hosted "$dir" "$worker"
  case $? in
    0)
      echo "$me: refusing to close $worker from inside its own process tree" >&2
      exit 3
      ;;
    1) ;;
    *)
      echo "$me: cannot read the process table; refusing to close $worker" >&2
      exit 2
      ;;
  esac
  st_root=$(/bin/sh "$FS" root) || exit 2
  st_store="$st_root/attention/state"

  stop_tracked=''
  st_released=''
  st_held=''
  for st_class in $release_classes; do
    stop_held "$st_class" "$dir" "$worker" "$st_store" || continue
    stop_release "$st_class" "$dir" "$worker" "$st_store" "$grace" || :
    if stop_held "$st_class" "$dir" "$worker" "$st_store"; then
      st_held="$st_held,$st_class"
      # A worker whose tree could not be closed is still running. Releasing the
      # rest of its runtime from under it would take away the channel an
      # operator answers it on and the lock that protects its journal, so the
      # walk stops here and reports what is still held.
      [ "$st_class" = process ] && break
    else
      st_released="$st_released,$st_class"
    fi
  done
  st_released=${st_released#,}
  st_held=${st_held#,}

  if [ -n "$st_held" ]; then
    printf 'stop %s partial released=%s held=%s\n' \
      "$worker" "${st_released:--}" "$st_held"
    return 6
  fi
  if [ -z "$st_released" ]; then
    printf 'stop %s already-closed\n' "$worker"
    return 0
  fi
  printf 'stop %s stopped released=%s\n' "$worker" "$st_released"
  return 0
}

# cmd__tick <worker> <dir> <supervisor-pid> <worker-pid> — the escalation
# tick's own process (internal; spawned by supervise). Sleeps in one-second
# steps, leaving the instant either pid is gone so a closed worker never keeps
# a ticker behind, and runs this worker's pending-age scan every
# PLANWRIGHT_STREAMJSON_ALARM_TICK seconds (default 60) against
# PLANWRIGHT_STREAMJSON_PENDING_AGE (default 900).
cmd__tick() {
  [ $# -eq 4 ] || usage
  tk_worker=$1
  tk_dir=$2
  tk_sup=$3
  tk_wrk=$4
  valid_field "$tk_worker" || exit 2
  valid_posnum "$tk_sup" || exit 2
  valid_posnum "$tk_wrk" || exit 2
  [ -d "$tk_dir" ] || exit 2
  tk_tick=${PLANWRIGHT_STREAMJSON_ALARM_TICK:-60}
  valid_posnum "$tk_tick" || tk_tick=60
  tk_thr=${PLANWRIGHT_STREAMJSON_PENDING_AGE:-900}
  valid_posnum "$tk_thr" || tk_thr=900
  tk_i=0
  while :; do
    sleep 1
    pid_live "$tk_sup" || exit 0
    pid_live "$tk_wrk" || exit 0
    tk_i=$((tk_i + 1))
    [ "$tk_i" -ge "$tk_tick" ] || continue
    tk_i=0
    [ -f "$tk_dir/journal" ] || continue
    alarm_scan_worker "$tk_worker" "$tk_dir" '' "$tk_thr" "$tk_tick" >/dev/null || :
  done
}

cmd_alarm_scan() {
  now=''
  threshold=${PLANWRIGHT_STREAMJSON_PENDING_AGE:-900}
  while [ $# -gt 0 ]; do
    case $1 in
      --now)
        [ $# -ge 2 ] || usage
        now=$2
        shift 2
        ;;
      --threshold)
        [ $# -ge 2 ] || usage
        threshold=$2
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done
  valid_posnum "$threshold" || {
    echo "$me: invalid threshold" >&2
    exit 2
  }
  if [ -z "$now" ]; then
    now=$(now_epoch) || exit 2
  fi
  valid_posnum "$now" || {
    echo "$me: invalid --now" >&2
    exit 2
  }
  as_root=$(/bin/sh "$FS" root) || exit 2
  [ -d "$as_root/streamjson" ] || return 0
  # The one intentional glob in this script: enumerate worker dirs (pathname
  # expansion is otherwise disabled by set -f).
  set +f
  for as_dir in "$as_root/streamjson"/*; do
    [ -d "$as_dir" ] || continue
    [ -f "$as_dir/journal" ] || continue
    as_worker=${as_dir##*/}
    valid_field "$as_worker" || continue
    alarm_scan_worker "$as_worker" "$as_dir" "$now" "$threshold" ''
  done
  set -f
}

# alarm_scan_worker <worker> <dir> <now> <threshold> <tick> — one worker's
# pending-age scan, shared by `alarm-scan` (every worker, on demand) and the
# supervisor's escalation tick (its own worker, on a cadence). <now> empty
# means the clock. <tick> empty means every overdue receipt is pushed through
# the notify seam on every call, the on-demand contract; a tick width means
# the push happens once, on the call whose window contains the crossing, while
# the high-priority queue row is re-upserted on every call (idempotent, and the
# row is what an attention watch reacts to). Prints `alarm <worker> <id> <age>`
# per firing.
alarm_scan_worker() {
  as_worker=$1
  as_dir=$2
  as_now=$3
  as_thr=$4
  as_tick=$5
  if [ -z "$as_now" ]; then
    as_now=$(now_epoch) || return 2
  fi
  # Candidate ids only. Everything the escalation acts on -- kind, received
  # epoch, state -- is re-read under the lock below, because this read is
  # unlocked and its values can be stale by the time the lock is taken.
  # Carrying them forward from here is what let a re-opened request be
  # escalated against the age this scan measured.
  awk -F'\t' -v now="$as_now" -v thr="$as_thr" \
    '$4 == "pending" && (now - $3) > thr { print $1 }' \
    "$as_dir/journal" | while read -r a_id; do
    valid_reqid "$a_id" || continue
    # Escalation only (the kickoff-pinned alarm outcome): the queue item
    # is re-upserted at high priority and the notify seam is pushed —
    # never an auto-answer, never a worker kill.
    #
    # Re-read under the lock before publishing, for the reason handle_line
    # and answer do. The awk above read this journal unlocked, so an answer
    # landing between that scan and this upsert would be undone by it,
    # re-posting a decision the operator just made — the same stale queue row
    # this projection prevents, arriving through the sweep.
    #
    # The whole ROW is re-read, not just the state. A request can be answered
    # and then re-opened by handle_line with a fresh received epoch while this
    # waits for the lock; a state-only check sees `pending` again and escalates
    # against the age the first scan measured, marking a request overdue that
    # has not yet had its threshold. The kind can change with it, so that is
    # taken from the same read.
    #
    # A lock this scan cannot take ends the worker, not the request: `continue`
    # would send every remaining row of a busy worker through the same retry
    # budget, turning one skip into seconds of spinning. The next pass retries
    # the whole worker.
    # ONE lock, held from the re-read through the publish. An earlier revision
    # of this took the lock twice -- read, unlock, decide, relock, publish --
    # which put the whole decision outside any lock and let an answer settle
    # the request in the gap, so the publish overwrote it. That is the very
    # row this change exists to prevent, reintroduced by the fix for the age
    # predicate. Every skip path below unlocks before it leaves.
    if ! journal_lock "$as_dir"; then
      break
    fi
    as_row=$(awk -F'\t' -v id="$a_id" '$1 == id { print $2 "\t" $3 "\t" $4; exit }' \
      "$as_dir/journal" 2>/dev/null) || as_row=''
    as_now_kind=${as_row%%"$TAB"*}
    as_rest=${as_row#*"$TAB"}
    as_recv=${as_rest%%"$TAB"*}
    as_state=${as_rest#*"$TAB"}
    as_fired=0
    if [ "$as_state" = pending ] && valid_posnum "${as_recv:-}"; then
      as_age=$((as_now - as_recv))
      if [ "$as_age" -gt "$as_thr" ]; then
        attention_upsert "$as_worker" "$as_dir" "$a_id" "$as_now_kind" high
        as_fired=1
      fi
    fi
    journal_unlock "$as_dir"
    [ "$as_fired" = 1 ] || continue
    if [ -z "$as_tick" ] || [ "$as_age" -le $((as_thr + as_tick)) ]; then
      /bin/sh "$FA" notify \
        "stream-json worker $as_worker: request $(printf '%s' "$a_id" | cut -c1-8) pending ${as_age}s past threshold" \
        >/dev/null 2>&1 || :
    fi
    printf 'alarm %s %s %s\n' "$as_worker" "$a_id" "$as_age"
  done
}

cmd_status() {
  [ $# -eq 1 ] || usage
  worker=$1
  valid_field "$worker" || {
    echo "$me: invalid worker handle" >&2
    exit 2
  }
  dir=$(worker_dir "$worker") || exit 2
  if [ ! -d "$dir" ]; then
    printf 'status %s unknown no-runtime-dir\n' "$worker"
    return 0
  fi
  # ONE read, with every field parsed from that single snapshot. The writer
  # truncates and rewrites this file in place, so separate reads can straddle
  # the empty window and disagree with each other: four independent reads
  # returned `completed` 156 times in 400 against a file whose writer only ever
  # wrote an is_error record. That direction of failure is the one this record
  # exists to prevent, so the verdict must not be assembled from fields taken at
  # different instants. read_completion in fleet-stuck-detector.sh already takes
  # its snapshot in one read; this is the sibling catching up. It enforces the
  # same terminator rule below, so the two agree on a torn snapshot as well —
  # it reports the record malformed where this one falls through to liveness.
  #
  # A torn or empty snapshot is NOT evidence of completion. It falls through to
  # the liveness check below, which is the honest answer while a write is in
  # flight.
  # Completeness is the TERMINATOR, not the leading field: the writers emit a
  # record in one newline-ended printf, so an unterminated snapshot is one they
  # have not finished (a short write on a full disk leaves one on disk for
  # good). A prefix of an is_error record still opens `result<TAB>` and still
  # parses as subtype success, so stopping at the kind word calls a dead run
  # clean. Not the field count: a terminated two-field record is a shape
  # fleet-status.sh already renders completed.
  st_raw=$(
    head -c 4096 "$dir/result" 2>/dev/null
    printf x
  )
  st_raw=${st_raw%x}
  st_seen=0
  case $st_raw in
    result"$TAB"*"$NL"* | exit"$TAB"*"$NL"*) st_seen=1 ;;
  esac
  st_line=${st_raw%%"$NL"*}
  if [ "$st_seen" = 1 ]; then
    st_kind=$(printf '%s\n' "$st_line" | awk -F'\t' 'NR == 1 { print $1 }')
    detail=$(printf '%s\n' "$st_line" | awk -F'\t' 'NR == 1 { print $1 "=" $2 }')
    # A `result` event is a completion unless the frame flagged is_error — the
    # turn completed the protocol while the run died — and an `exit` fallback
    # with a non-zero code is a worker that ended without completing it. Both
    # render `ended`, never conflated with `completed`.
    st_ec=$(printf '%s\n' "$st_line" | awk -F'\t' 'NR == 1 { print $2 }')
    st_err=$(printf '%s\n' "$st_line" | awk -F'\t' 'NR == 1 { print $4 }')
    if [ "$st_err" = true ]; then
      # Name both halves: the contradiction is the diagnostic, so collapsing it
      # to either one alone hides why the run is being called ended.
      detail="$detail/is_error=true"
    fi
    # Composed first, bounded once: truncating before the suffix is appended
    # can cut the suffix back off, leaving `ended` with nothing saying why.
    detail=$(sanitize_printable "$detail" unknown | cut -c1-64)
    if { [ "$st_kind" = exit ] && [ "$st_ec" != 0 ]; } || [ "$st_err" = true ]; then
      printf 'status %s ended %s\n' "$worker" "$detail"
    else
      printf 'status %s completed %s\n' "$worker" "$detail"
    fi
    return 0
  fi
  sup_pid=$(cat "$dir/supervisor.pid" 2>/dev/null) || sup_pid=''
  wrk_pid=$(cat "$dir/worker.pid" 2>/dev/null) || wrk_pid=''
  if valid_posnum "${sup_pid:-}" && pid_live "$sup_pid" \
    && valid_posnum "${wrk_pid:-}" && pid_live "$wrk_pid"; then
    # A live worker with a pending receipt is not making progress: it is
    # waiting on an answer nobody may be about to give. Say so, with the
    # count and the oldest age, rather than the `running` that read as
    # healthy for the twenty minutes a stalled worker sat on its first call.
    st_pend=0
    st_oldest=''
    if [ -f "$dir/journal" ]; then
      st_pend=$(awk -F'\t' '$4 == "pending" { n++ } END { print n + 0 }' \
        "$dir/journal" 2>/dev/null) || st_pend=0
      st_oldest=$(awk -F'\t' '$4 == "pending" && $3 ~ /^[0-9]+$/ { if (o == "" || $3 < o) o = $3 } END { print o }' \
        "$dir/journal" 2>/dev/null) || st_oldest=''
    fi
    if valid_posnum "${st_pend:-}" && valid_posnum "${st_oldest:-}"; then
      st_now=$(now_epoch) || st_now=$st_oldest
      st_age=$((st_now - st_oldest))
      [ "$st_age" -ge 0 ] || st_age=0
      printf 'status %s awaiting-input pending=%s oldest=%ss supervisor=%s worker=%s\n' \
        "$worker" "$st_pend" "$st_age" "$sup_pid" "$wrk_pid"
      return 0
    fi
    printf 'status %s running supervisor=%s worker=%s\n' "$worker" "$sup_pid" "$wrk_pid"
    return 0
  fi
  # Death is POSITIVE evidence only (the fleet discipline): every recorded
  # handle must yield a dead verdict from fleet-death-evidence.sh; anything
  # less is unknown, never dead-by-silence.
  dead=0
  checked=0
  for pid in "$sup_pid" "$wrk_pid"; do
    valid_posnum "${pid:-}" || continue
    checked=$((checked + 1))
    if /bin/sh "$FDE" process "$pid" >/dev/null 2>&1; then
      dead=$((dead + 1))
    fi
  done
  if [ "$checked" -gt 0 ] && [ "$dead" -eq "$checked" ]; then
    printf 'status %s dead supervisor+worker\n' "$worker"
  else
    printf 'status %s unknown insufficient-evidence\n' "$worker"
  fi
}

# --- dispatch ---------------------------------------------------------------

[ $# -ge 1 ] || usage
cmd=$1
shift
case $cmd in
  launch) cmd_launch "$@" ;;
  answer) cmd_answer "$@" ;;
  recover) cmd_recover "$@" ;;
  alarm-scan) cmd_alarm_scan "$@" ;;
  _tick) cmd__tick "$@" ;;
  stop) cmd_stop "$@" ;;
  status) cmd_status "$@" ;;
  _supervise) supervise "$@" ;;
  *) usage ;;
esac
