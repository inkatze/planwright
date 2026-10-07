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
#   supervisor.pid / worker.pid / recover.lock / journal.lock / launch.lock
#   scope            the dispatch scope, when the launch supplied one
#   supervisor.log   the detached supervisor's own stderr
#   .init.* / .frame.* / .journal.* / .session.* / .pid.*  mktemp-beside-target
#                    staging
#   deferred-<id>    a receipt the journal lock refused, until it is journaled
#   .deferred.*      its staging temp
#   attention.dirty  the queue row may not match the journal; the tick re-syncs
#   *.lock#*         a lock break's claim, or an aside, a crashed caller left
#   *.broken.*       residue of the retired `mkdir` lock's own stale break
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
# BEFORE the attention upsert, so a supervisor kill loses no receipt; a receipt
# the journal lock refused is on disk as its spool until it is journaled. The
# pending-age alarm is scan-based over that journal (`alarm-scan`), so it is
# re-armed after `--resume` by construction — no in-memory timer to lose.
# Duplicate delivery of a request id (same run, or re-issued across the
# resume boundary) deduplicates on request identity: a journaled id is never
# journaled or queued twice. Recovery (`recover`) has a single initiator —
# an election on the shared lock primitive (scripts/lock-lib.sh), one atomic
# symlink create — and checks the orphaned worker's liveness
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
# a different request. An answer whose frame fails frame_check writes nothing
# and leaves the request pending (exit 2), so a corrected answer can land.
#
# THE CLOSE (`stop`). The release set is the runtime a worker acquires:
# its process tree, the locks it holds, its scratch temp, and its attention
# record. The tmux-window class is named here rather than left silently absent,
# per the floor's declare-every-class rule: it is not acquired by this rung at
# all — a stream-json worker is a detached supervisor/worker pair with no
# window. The dispatch registry record is written at launch and is NOT released
# here: it is fleet-wide inventory rather than this worker's runtime. The
# periodic sweep's registry reconcile retires it, marked closed, once the
# worker has positive death evidence (`scripts/fleet-registry-reconcile.sh`).
# The worktree, the branch, and the unit's fence are never touched: the
# release set is exactly the reproducible resources, and the worktree is the
# one holding work that cannot be recovered. No audit record is
# written either — the reap path that needs one owns it, so that an autonomous
# close writes exactly one record rather than two.
#
# Process matching keys on the worker's STATE-DIRECTORY path and on the pids
# that directory records, never on a process name or command pattern: an
# operator's own `claude` session shares this worker's command shape exactly,
# so a name match would kill it. The path match is anchored on the supervisor's
# own `_supervise <worker> <dir>` argv, not on a bare search for the directory,
# which would also match a sibling worker whose handle this one prefixes and
# any process merely naming the directory (the supervisor's own escalation
# tick, `_tick <worker> <dir> ...`, is one, and is reached only as the
# supervisor's child). SIGTERM first, SIGKILL after a bounded grace, because
# children do not reliably die with a parent SIGTERM.
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
#       supplies the full response body (AskUserQuestion answers use this):
#       one JSON object on one line with no raw control byte (TAB and DEL
#       included, so escape them), 64 KiB at most.
#   fleet-streamjson.sh steer <worker> --message-file <file>
#       Deliver a tower-originated message to a LIVE worker as a user turn on
#       its own stdin: the file's text, under the fixed attribution header
#       `[planwright tower relay -> <worker>]`, JSON-encoded into one user
#       frame on the fifo. This is the steer-in-flight path for this rung
#       (doctrine/inter-orchestrator-coordination.md): a real submit that
#       needs no input box, so it does not depend on a paste landing at an
#       idle prompt, and it leaves a receipt — `<dir>/steers`, one
#       `<epoch>\t<bytes>\t<file>` row per delivery — where a pane paste
#       leaves nothing. It is NOT an answer: it never composes a
#       control_response and never touches the receipt journal, so it cannot
#       settle a pending permission request (the tower may not answer those).
#       The file is data (64 KiB cap, refused whole when over, non-empty); a
#       dead channel is exit 3, never a hang. Prints `steered <worker> <bytes>`.
#       Like every frame written to the fifo (see frame_check), the composed
#       frame is checked before the write; a refused one is exit 2 with
#       nothing written.
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
#   fleet-streamjson.sh stop <worker> [--grace <secs>] [--observe]
#       Close the worker: terminate its process tree and release the locks,
#       scratch temp, and attention record it holds. Prints one of
#       `stop <worker> stopped released=<classes>`,
#       `stop <worker> already-closed`, or
#       `stop <worker> partial released=<classes> held=<classes>`, whose
#       released field reads `-` when nothing was released (the other two
#       forms cannot reach that case). <secs> is the SIGTERM-to-SIGKILL grace,
#       a whole number of seconds bounded by `grace_max` and defaulting to
#       `grace_default` (scripts/fleet-stop-lib.sh, the close this rung shares
#       with the headless one); passing an out-of-range value prints both. There is no
#       zero-grace form, since SIGTERM always goes first, and a fixed settling
#       wait follows the SIGKILL.
#       An unknown handle is exit 2, not `already-closed`, so a typo never
#       reads as a successful close, and a close asked for from inside the
#       worker's own process tree is refused with exit 3 rather than attempted.
#       --observe runs the same checks and probes and releases nothing, printing
#       `stop <worker> would-release=<classes>` for what a close would take now,
#       or `stop <worker> already-closed`; the periodic sweep's observing mode
#       records its would-have close from this.
#   fleet-streamjson.sh status <worker>
#       Print `status <worker> <running|awaiting-input|completed|ended|dead|
#       unknown> <detail>` from the recorded pids, the receipt journal and the
#       captured event stream. `awaiting-input` is a live worker with a pending
#       control_request: the detail carries `pending=<n> oldest=<age>s
#       supervisor=<pid> worker=<pid>` (`oldest=unknown` when no pending row
#       has a readable epoch; a spooled receipt counts as pending), so a worker
#       that cannot proceed never reads as a healthy `running`.
#   fleet-streamjson.sh pending [<worker>...]
#       Read-only view of the journaled requests `status` counts (a spooled
#       receipt is counted there but listed here only once it is journaled,
#       which is also when `answer` can reach it): for every request the
#       journal still reads `pending` (no args: every worker), oldest first,
#       print `== <worker> <request-id> <tool>` (the tool name suffixed
#       `:sanitized` when it had to be altered to fit the header), then the
#       tool input behind a `| ` prefix on every line. A Bash request shows
#       its command decoded, preceded by one `+ {...}` line carrying every
#       other input field but the description when there are any; any other
#       tool shows its input JSON. Input cut at `pending_show_max` bytes gets
#       a `-- truncated ...` line; an envelope that ends early (cut at
#       `pending_read_max` or still being written) gets a
#       `-- request envelope ends early ...` line; every such notice comes
#       before the content, so a piped `head` cannot drop it; a
#       missing, symlinked or malformed envelope prints
#       `-- request envelope unreadable` in place of the input. Request
#       content is untrusted: control bytes are stripped and the prefixes
#       keep it from forging a header. A named worker with no runtime dir, or
#       a journal or worker dir that cannot be read, is exit 2. Never writes,
#       answers, locks, or re-queues anything.
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
# INSTALLED the plugin at). So before spawning, `launch` runs the hook the
# worker will run (scripts/worker-command-guard.sh under the CLAUDE_PLUGIN_ROOT
# the dispatch-env wrapper exports, through that wrapper and so with the
# environment the worker gets) against a synthetic PreToolUse payload for
# `<root>/scripts/resolve-rule-doc.sh spec-format`, once per root the worker
# could run scripts from: this launcher's own root, that plugin root, and every
# root the scripts/resolve-installed-roots.sh beside the hook names, the ones
# its symlink rule refuses included (the hook will not trust those, so a
# worker loading its skills from one would stall). A root the
# hook does not approve refuses the launch with exit 9, naming the root and the
# command, because the worker would otherwise stall on exactly that call; a
# hook that is missing or not executable, or a proof that could not run at
# all, refuses the same way. PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT is `refuse`
# by default; =warn downgrades every refusal to a warning (an operator who
# intends to answer every prompt by hand); =off skips the proof; any other
# value is a usage error (exit 2).
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

# The one advisory-lock primitive (universal-binary D-11), required readable
# and fail-closed when absent for the same reason the sanitizer is: every
# election and every journal mutation below runs under it, so a missing
# library is no mutual exclusion at all rather than a degraded kind.
lock_lib="$script_dir/lock-lib.sh"
if [ ! -r "$lock_lib" ]; then
  echo "$me: required helper $lock_lib missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/lock-lib.sh
. "$lock_lib"

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
    echo "       fleet-streamjson.sh steer <worker> --message-file <file>"
    echo "       fleet-streamjson.sh recover <worker> [--foreground] [-- <extra args>...]"
    echo "       fleet-streamjson.sh alarm-scan [--now <epoch>] [--threshold <secs>]"
    echo "       fleet-streamjson.sh stop <worker> [--grace <secs>] [--observe]"
    echo "       fleet-streamjson.sh status <worker>"
    echo "       fleet-streamjson.sh pending [<worker>...]"
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

# --- single-initiator locks -------------------------------------------------

# Every lock this script takes goes through the shared primitive
# (scripts/lock-lib.sh): the lock IS an atomic symlink whose target names its
# holder, and STALE MEANS THE HOLDER'S PROCESS IS ABSENT, never an age. An age
# cannot tell a crash from a `--foreground` launch legitimately holding its lock
# for the whole run, so it would break live locks under load and leave dead
# ones standing for the whole threshold. The holder's process is the evidence
# instead, for every class alike.

# lock_take <lock-path> — take a single-initiator election. 0 taken, non-zero
# refused with the lock untouched.
#
# ONE attempt, never a spin. Both callers are elections whose entire answer to a
# live holder is "someone else is already doing this" (exit 3), so waiting here
# would turn an immediate refusal into a two-minute stall. The journal lock,
# whose callers do want to wait, spins in `journal_lock` instead.
lock_take() {
  pw_lock_try "$1"
}

# lock_drop <lock-path> — release a lock this process holds. The primitive
# verifies ownership, so a holder that outlived a break of its own lock finds a
# stranger's token at the path and leaves the successor's lock alone.
lock_drop() {
  pw_lock_release "$1"
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
# the second as death is how a second launch proceeds over a running worker.
# `ps -p` answers existence regardless of ownership and is consulted only after
# `kill -0` has already said no, so the common path stays fork-free.
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
# Mutations run under the file's own lock, and the hold is short: no shell-out
# runs inside it, the queue projection included (attention_sync says why). A
# crashed writer's lock is reclaimed on the next attempt, because the primitive
# probes the holder's process, and a live writer's is never taken out from
# under it. A receipt that meets a busy lock anyway is spooled beside the
# journal and journaled once the lock frees (receipt_defer, receipt_drain).

# ~5s of waiting, the bound this lock has always had, expressed in the
# primitive's own 0.02s tick.
journal_lock_tries=250

# journal_lock <dir> [<tries>] — take the journal lock, waiting out a busy one
# for <tries> attempts (default the full budget). 1 when it stays busy for the
# whole budget, 2 when it cannot be taken at all; either is the caller's cue to
# leave the journal alone rather than write a row it cannot vouch for.
journal_lock() {
  # Armed before the acquire, and idempotent: the verbs that reach here have no
  # handler of their own, and the two that do (`launch`, `recover`) armed this
  # same one ahead of their own election.
  pw_lock_trap_install
  jl_dir="$1/journal.lock"
  pw_lock_acquire "$jl_dir" "${2:-$journal_lock_tries}"
  jl_rc=$?
  [ "$jl_rc" -eq 0 ] && return 0
  # A budget exhausted against a live holder is the only outcome this layer has
  # anything to add to; the primitive has already said its piece about the rest.
  # Busy and broken stay apart for the callers that answer them differently
  # (receipt_record); every other caller treats any non-zero as "leave it".
  if [ "$jl_rc" -eq 1 ]; then
    [ "${2:-}" = 1 ] || echo "$me: journal lock busy at $jl_dir" >&2
    return 1
  fi
  return 2
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

# journal_pending_ids <dir> — print the id of every pending row, oldest first.
# Non-zero when the journal exists but cannot be read whole, so a caller can
# tell "nothing pending" from "could not tell".
journal_pending_ids() {
  [ -e "$1/journal" ] || [ -L "$1/journal" ] || return 0
  [ -f "$1/journal" ] || return 2
  jp_rows=$(awk -F'\t' '$4 == "pending" { print $3 "\t" NR "\t" $1 }' "$1/journal") || return 2
  [ -n "$jp_rows" ] || return 0
  jp_rows=$(printf '%s\n' "$jp_rows" | sort -t "$TAB" -k1,1n -k2,2n) || return 2
  printf '%s\n' "$jp_rows" | awk -F'\t' '{ print $3 }'
}

# --- JSON helpers (awk, no jq per REQ-K1.5) ---------------------------------

# json_escape — print stdin as a JSON string body (no surrounding quotes):
# backslash, quote, tab, and CR escaped; newlines between lines become \n;
# remaining C0 control bytes and DEL are stripped (this text is data — a stray
# control byte is dropped, never smuggled, and never emitted raw, which would
# make the frame invalid JSON the worker's parser rejects).
# Bytes >= 0x80 are kept, so raw UTF-8 (accents, em-dash, CJK, emoji) reaches
# the worker intact — JSON strings carry UTF-8 verbatim. The strip is `tr`, not
# an awk class: BSD awk (macOS) does not honour `[\000-\037\177]` as a byte
# range and strips nothing, which left raw C0 bytes in the frame there.
# Every string body the supervisor emits goes through this one escaper, so the
# prompt path and the deny-message path cannot drift apart.
json_escape() {
  tr -d '\000-\010\013\014\016-\037\177' | awk '
    NR > 1 { printf "\\n" }
    {
      s = $0
      gsub(/\\/, "\\\\", s)
      gsub(/"/, "\\\"", s)
      gsub(/\t/, "\\t", s)
      gsub(/\r/, "\\r", s)
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
# braces inside JSON strings do not count). Empty when absent. A raw DEL,
# which JSON allows in a string and the CLI emits unescaped, comes out as
# \u007f: the same character, in the form frame_check accepts.
json_input_object() {
  awk '
    BEGIN { del = sprintf("%c", 127) }
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
        if (c == del) { out = out "\\u007f"; continue }
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

# --- the fifo write discipline ----------------------------------------------

# frame_check <file> — succeed when the file holds exactly one newline-
# terminated line that parses as a JSON object; otherwise print the reason and
# fail. The worker reads its stdin one line at a time, so a frame missing its
# newline runs into whatever the supervisor writes next and the worker dies on
# the merged line; an invalid frame kills it the same way.
#
# Stricter than JSON in one respect: no raw control byte besides the
# terminator, TAB and DEL included. Every string this script composes goes
# through json_escape, which never emits one, and json_input_object escapes
# the DEL a worker's own tool input may carry, so only a caller-supplied body
# (an `--response-file`) can hold one; the byte-range test stays in `tr`, the
# one tool that honours it portably.
#
# The parse is a reduction rather than a character walk, so its cost stays
# linear in the frame instead of in the frame times its string count: each
# string, number, and literal becomes one placeholder byte, which a leftover
# quote or backslash proves was not a well-formed string, then innermost
# arrays and objects collapse to a single value until the top object is one.
# The collapse stops after 512 passes, each taking one array and one object
# level, so nesting past that is refused rather than walked. The cap sits well
# above any tool input an `--allow` splices, since a refusal there leaves the
# worker unable to proceed, and it bounds a pathological 64 KiB body to a few
# seconds (without it, about 24s under mawk).
frame_check() {
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then
    echo "missing or unreadable"
    return 1
  fi
  if [ "$(tail -c 1 <"$1" | wc -l | tr -d ' ')" != 1 ]; then
    echo "unterminated (no trailing newline)"
    return 1
  fi
  if [ "$(wc -l <"$1" | tr -d ' ')" != 1 ]; then
    echo "multi-line (one frame per write)"
    return 1
  fi
  if [ "$(tr -d '\000-\011\013-\037\177' <"$1" | wc -c | tr -d ' ')" != "$(wc -c <"$1" | tr -d ' ')" ]; then
    echo "raw control byte"
    return 1
  fi
  if ! awk '
    BEGIN {
      S = sprintf("%c", 1); N = sprintf("%c", 2); K = sprintf("%c", 3); C = sprintf("%c", 4)
      V = "[" S N K C "]"
      arr = "\\[(" V "(," V ")*)?\\]"
      obj = "\\{(" S ":" V "(," S ":" V ")*)?\\}"
    }
    { s = $0 }
    END {
      if (NR != 1) exit 1
      gsub(/"([^"\\]|\\["\\\/bfnrt]|\\u[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])*"/, S, s)
      if (s ~ /["\\]/) exit 1
      gsub(/-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/, N, s)
      gsub(/true|false|null/, K, s)
      gsub(/ /, "", s)
      if (substr(s, 1, 1) != "{") exit 1
      for (d = 0; d < 512 && s != C; d++)
        if (gsub(arr, C, s) + gsub(obj, C, s) == 0) break
      exit (s == C) ? 0 : 1
    }' <"$1"; then
    echo "invalid JSON"
    return 1
  fi
}

# frame_send <dir> <frame-file> — the one writer into a live worker's stdin,
# for every frame composed after launch (build_initial_msg checks the launch
# frame). The caller holds the journal lock, so two writers never interleave.
# Exit 0 written; 2 the frame is refused, its reason on stdout; 3 the channel
# is dead; 1 the write itself failed. Only 0 and 1 can have written anything.
#
# The frame is judged first so the liveness probe sits next to the open it
# guards: a fifo with no reader blocks its opener forever, so a dead
# supervisor or worker must become a verdict, never a hang. A residual TOCTOU
# is ACCEPTED: a worker that dies between the probe and the blocking open can
# still wedge the open. The window is not closable in portable POSIX sh (a
# non-blocking or timed open needs a helper process), and it is far narrower
# than the already-dead case the probe catches. The `-p` test is also what
# keeps `>>` from creating a regular file where a close just removed the fifo.
frame_send() {
  frame_check "$2" || return 2
  fs_sup=$(cat "$1/supervisor.pid" 2>/dev/null) || fs_sup=''
  fs_wrk=$(cat "$1/worker.pid" 2>/dev/null) || fs_wrk=''
  valid_posnum "$fs_sup" && pid_live "$fs_sup" || return 3
  valid_posnum "$fs_wrk" && pid_live "$fs_wrk" || return 3
  [ -p "$1/in.fifo" ] || return 3
  cat "$2" >>"$1/in.fifo" 2>/dev/null || return 1
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

# attention_publish <worker> <dir> <projection> — write the queue row a
# journal projection names: the `<id> <kind>` of the oldest pending request, or
# nothing, which clears the worker's row.
attention_publish() {
  if [ -n "$3" ]; then
    attention_upsert "$1" "$2" "${3%% *}" "${3#* }"
  else
    /bin/sh "$FA" clear "$1" || :
  fi
}

# attention_sync <worker> <dir> <projection> — publish the projection the
# caller read under the journal lock, then confirm it is still the one the
# journal implies, publishing again until it is. Called WITHOUT the lock.
#
# THE JOURNAL LOCK IS NEVER HELD ACROSS THE ATTENTION STORE. The store takes the
# fleet lock, so a journal lock held across it turns one stuck lock into two:
# every answer, steer and receipt for this worker waits on a fleet lock it has
# nothing to do with, and a receipt that cannot wait is lost. What the hold used
# to buy was that no `answer` could settle a request between the read and the
# publish and have its clear undone by a stale row. Publish-then-confirm buys
# the same without it: every writer that changes the journal publishes after
# its change and confirms after its publish, so whichever publish lands last is
# checked against the journal as it stands by then, and a stale one is replaced
# by the confirmation of the writer that published it. Every publish is
# confirmed, the last one included. A confirmation that cannot happen (the lock
# held past its budget, or a journal still moving after the bounded rounds)
# marks the row for the tick to re-sync rather than trusting it.
attention_sync() {
  sy_proj=$3
  sy_round=0
  while :; do
    attention_publish "$1" "$2" "$sy_proj"
    sy_round=$((sy_round + 1))
    if ! journal_lock "$2" 2>/dev/null; then
      attention_mark_dirty "$2"
      return 0
    fi
    sy_now=$(journal_oldest_pending "$2")
    journal_unlock "$2"
    [ "$sy_now" != "$sy_proj" ] || return 0
    if [ "$sy_round" -ge 4 ]; then
      attention_mark_dirty "$2"
      return 0
    fi
    sy_proj=$sy_now
  done
}

# attention_mark_dirty <dir> — note that the queue row may not match the
# journal, for the tick to put right (attention_resync). Raised when a publish
# could not be confirmed: its lock was held past the budget, or the journal
# kept moving for every round.
attention_mark_dirty() {
  : >"$1/attention.dirty" 2>/dev/null || :
}

# attention_resync <worker> <dir> — the tick's half of attention_mark_dirty:
# one non-waiting attempt to read the projection and publish it, confirmed as
# every publish is. A lock still busy leaves the mark for the next beat.
#
# The mark is taken before the read and put back if the lock is busy, so a mark
# another writer raises meanwhile survives this re-sync rather than being
# cleared by a confirmation that was never about it.
attention_resync() {
  [ -f "$2/attention.dirty" ] || return 0
  rm -f "$2/attention.dirty" 2>/dev/null || return 0
  if ! journal_lock "$2" 1 2>/dev/null; then
    attention_mark_dirty "$2"
    return 0
  fi
  rs_proj=$(journal_oldest_pending "$2")
  journal_unlock "$2"
  attention_sync "$1" "$2" "$rs_proj"
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

# request_kind <line> — the receipt kind a control_request carries.
request_kind() {
  case $(json_field "$1" tool_name) in
    AskUserQuestion) printf 'question' ;;
    *) printf 'permission' ;;
  esac
}

# receipt_record <worker> <dir> <id> <kind> <epoch> <line> [<spool> [<tries>]]
# — journal one control_request and project it into the queue. 0 handled
# (recorded, a duplicate, or a failure already surfaced), 1 the journal lock
# is busy and nothing was written, 2 the journal lock cannot be taken at all.
#
# A <spool> is the deferred copy being drained, removed under the same lock
# hold that records it: a second drainer that read it too finds it gone under
# the lock and records nothing, so a drained receipt is recorded exactly once.
receipt_record() {
  rr_worker=$1
  rr_dir=$2
  rr_id=$3
  rr_kind=$4
  rr_now=$5
  rr_line=$6
  rr_spool=${7:-}
  journal_lock "$rr_dir" "${8:-}" || return $?
  rr_state=$(journal_state "$rr_dir" "$rr_id")
  if [ -n "$rr_spool" ]; then
    # Gone means another drainer recorded it under this same lock already.
    if [ ! -f "$rr_spool" ]; then
      journal_unlock "$rr_dir"
      return 0
    fi
    rm -f "$rr_spool" 2>/dev/null || :
    # Against a settled row, a spool is a resume re-ask only if it was
    # received after the settle; one received before it is a duplicate of the
    # request the operator already answered, spooled while the answer held
    # the lock, and re-opening it would ask a settled question again.
    case $rr_state in
      answered | undeliverable)
        rr_settled=$(awk -F'\t' -v id="$rr_id" '$1 == id { print $5; exit }' "$rr_dir/journal" 2>/dev/null) || rr_settled=''
        if valid_posnum "${rr_settled:-}" && [ "$rr_now" -lt "$rr_settled" ]; then
          journal_unlock "$rr_dir"
          return 0
        fi
        ;;
    esac
  fi
  case $rr_state in
    pending)
      # A still-open request re-delivered: dedup on request identity — no
      # second journal row, no second queue item. This is the within-run
      # duplicate the CLI can emit and the resume-boundary re-delivery of
      # an unanswered request (REQ-E1.1, REQ-E1.2, REQ-E1.5).
      journal_unlock "$rr_dir"
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
      if ! journal_set_state "$rr_dir" "$rr_id" pending "$rr_now"; then
        # Fail closed: with the journal still terminal, an answerable
        # queue item would be a dead end (`answer` refuses on the
        # already-answered/undeliverable row). Surface the failed
        # re-open visibly instead (never silent, never misleading).
        journal_unlock "$rr_dir"
        attention_failure "$rr_worker" "$rr_dir" \
          "could not re-open request $(printf '%s' "$rr_id" | cut -c1-8) on resume for worker $rr_worker - the journal still reads terminal, investigate disk/store"
        return 0
      fi
      ;;
    *)
      # Durable receipt FIRST (a kill after this write loses nothing), then
      # the envelope (answer composition), then the queue item. A failed
      # journal append is surfaced rather than proceeding to queue a request
      # with no durable receipt (REQ-E1.5's receipt-first guarantee).
      if ! journal_append "$rr_dir" "$rr_id" "$rr_kind" "$rr_now"; then
        journal_unlock "$rr_dir"
        attention_failure "$rr_worker" "$rr_dir" \
          "receipt append failed for worker $rr_worker request $(printf '%s' "$rr_id" | cut -c1-8) - the receipt journal is not durable, investigate disk/store"
        return 0
      fi
      ;;
  esac
  printf '%s\n' "$rr_line" >"$rr_dir/req-$rr_id.json"
  # The projection is the OLDEST still-pending request, which the one just
  # recorded is not when an earlier one is still open. Read under the lock and
  # published after it, as attention_sync describes.
  rr_proj=$(journal_oldest_pending "$rr_dir")
  journal_unlock "$rr_dir"
  attention_sync "$rr_worker" "$rr_dir" "$rr_proj"
  return 0
}

# receipt_defer <dir> <id> <epoch> <line> — spool a receipt the journal lock
# refused: its received epoch, then the request line. Staged beside the target
# and renamed, like every other durable write here, so a drain never reads half
# of one.
receipt_defer() {
  # A rename onto a link to a directory files the spool inside it and still
  # succeeds, where no drain would ever find it.
  if [ -L "$1/deferred-$2" ] || { [ -e "$1/deferred-$2" ] && [ ! -f "$1/deferred-$2" ]; }; then
    return 1
  fi
  rf_tmp=$(mktemp "$1/.deferred.XXXXXX") || return 1
  if printf '%s\n%s\n' "$3" "$4" >"$rf_tmp" && mv "$rf_tmp" "$1/deferred-$2"; then
    return 0
  fi
  rm -f "$rf_tmp" 2>/dev/null || :
  return 1
}

# receipt_drain <worker> <dir> [<tries>] — journal every spooled receipt the
# journal lock now admits, under its original received epoch, so the journal's
# oldest-first order is the order the requests arrived in. 0 nothing left
# spooled, otherwise receipt_record's code for the lock that refused (1 busy,
# 2 broken). The supervisor drains on every
# request, waiting out a busy lock; the tick on every beat, with one attempt.
# Both may race for one spool, and the spool is removed under the lock that
# records it, so the loser finds it gone or already journaled.
receipt_drain() {
  set +f
  for dr_f in "$2"/deferred-*; do
    set -f
    [ -f "$dr_f" ] && [ ! -L "$dr_f" ] || continue
    dr_id=${dr_f##*/deferred-}
    valid_reqid "$dr_id" || continue
    dr_epoch=$(head -n 1 "$dr_f" 2>/dev/null) || continue
    case $dr_epoch in
      '' | *[!0-9]*) continue ;;
    esac
    dr_line=$(tail -n +2 "$dr_f" 2>/dev/null) || continue
    dr_rc=0
    receipt_record "$1" "$2" "$dr_id" "$(request_kind "$dr_line")" "$dr_epoch" "$dr_line" \
      "$dr_f" "${3:-}" || dr_rc=$?
    if [ "$dr_rc" -ne 0 ]; then
      set -f
      return "$dr_rc"
    fi
  done
  set -f
  return 0
}

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
      hl_now=$(now_epoch) || hl_now=0
      # Earlier receipts the journal lock refused go first; when it still
      # refuses, this one joins them rather than being dropped.
      hl_rc=0
      receipt_drain "$hl_worker" "$hl_dir" || hl_rc=$?
      if [ "$hl_rc" -eq 0 ]; then
        receipt_record "$hl_worker" "$hl_dir" "$hl_id" "$(request_kind "$hl_line")" "$hl_now" "$hl_line" \
          || hl_rc=$?
        [ "$hl_rc" -ne 0 ] || return 0
      fi
      # The receipt could not be journaled now. It must not pend unobserved
      # (the invariant this script exists for), and it must not be lost
      # either: spooled, it is journaled by the next receipt or the next
      # tick that finds the lock free, with nothing restarted.
      hl_spooled=0
      receipt_defer "$hl_dir" "$hl_id" "$hl_now" "$hl_line" && hl_spooled=1
      if [ "$hl_spooled" = 1 ] && [ "$hl_rc" -ne 2 ]; then
        attention_failure "$hl_worker" "$hl_dir" \
          "receipt for worker $hl_worker request $(printf '%s' "$hl_id" | cut -c1-8) deferred: the journal lock is busy; it is journaled once the lock frees"
      elif [ "$hl_spooled" = 1 ]; then
        attention_failure "$hl_worker" "$hl_dir" \
          "receipt for worker $hl_worker request $(printf '%s' "$hl_id" | cut -c1-8) deferred: the journal lock cannot be taken at all - investigate $hl_dir/journal.lock"
      else
        attention_failure "$hl_worker" "$hl_dir" \
          "receipt journaling failed for worker $hl_worker request $(printf '%s' "$hl_id" | cut -c1-8) - investigate the journal lock"
      fi
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
# The frame is checked here, before any worker exists, rather than in
# supervise: a refusal there would come after the dispatch was registered, and
# the detached launch's startup window would have to cover a second parse.
build_initial_msg() {
  bi_body=$(json_escape_file "$1") || return 2
  printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"%s"}]}}\n' \
    "$bi_body" >"$2" || return 2
  bi_why=$(frame_check "$2") || {
    echo "$me: launch frame refused: $bi_why" >&2
    return 2
  }
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
  # The worker profile leaves the base merge and the never-pushed rewrites to
  # the policy guard, so a hook root without it would leave them unrefused (a
  # hook that fails to run blocks nothing).
  if [ ! -x "$gp_hook_root/scripts/policy-guard.sh" ]; then
    echo "$me: launch preflight: the policy guard $gp_hook_root/scripts/policy-guard.sh is missing or not executable; the worker's merges and history rewrites would go unchecked" >&2
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
    /bin/sh "$gp_hook_root/scripts/resolve-installed-roots.sh" --refused 2>/dev/null || :
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

# The pid files a worker dir records, which seed the process match alongside
# the supervisor's argv.
stop_pidfiles='supervisor.pid worker.pid'

# Scratch is the stdio fifos the supervisor owns, the staging files this
# script's writers create beside their targets, and the residue of a broken
# lock. Everything else in the state directory is the durable record a close
# keeps: the capture, the journal, the session, the stored envelopes, and the
# result.
scratch_patterns='in.fifo out.fifo .init.* .frame.* .journal.* .session.* .pid.* .deferred.* *.lock#* *.broken.*'

# stop_match <worker> <dir> — the argv the supervisor re-execs itself with.
# The handle and the directory together are what keep a sibling whose handle
# this one prefixes (`api` against `api2`) out of the match: the directory alone
# is a prefix of the sibling's, and the triple is not.
stop_match() {
  printf '_supervise %s %s' "$1" "$2"
}

# stop_process_closed <dir> — drop pid files that now record nothing live.
#
# `rm -rf`, for the reason `release_locks` uses it: the held-probe gates on mere
# existence, so anything at those paths that `rm -f` cannot remove — a directory
# the worker created there — would hold the class forever with no re-invocation
# able to make progress. `${1:?}` guards the recursive removal against an empty
# directory argument, and does so by ending the shell rather than the function,
# which is why the trailing `|| :` on that line does not make it non-fatal.
stop_process_closed() {
  for spc_f in $stop_pidfiles; do
    rm -rf "${1:?}/$spc_f" 2>/dev/null || :
  done
}

# `-L` BEFORE `-e`, and both: a held lock is a symlink whose target is a token
# rather than a file, so `-e` follows it and reads FALSE on exactly the shape
# this probe exists to see. `-e` still earns its place for everything else that
# can occupy the path — a regular file, or a directory left by the retired
# `mkdir` shape — because each of those blocks an acquire just as effectively,
# and a probe that missed them would leave the verb they block wedged with
# nothing able to clear it.
held_locks() {
  for hl_l in $lock_classes; do
    if [ -L "$1/$hl_l" ] || [ -e "$1/$hl_l" ]; then
      return 0
    fi
  done
  return 1
}

# clear_legacy_lock_dirs <dir> — clear a lock left as a DIRECTORY by the
# retired `mkdir` shape.
#
# The current primitive never creates one, so a directory at a lock path can
# only be residue of a fleet home that predates the migration. Nothing acquires
# over it: an acquire refuses a path occupied by something that is not a lock
# symlink rather than guessing, so one such directory wedges every verb for
# this worker until something removes it. That is what makes this the in-place
# upgrade path. The library's clear is what makes it safe: it takes a directory
# and only a directory, in one step, so a peer that wins the path in between
# keeps its live lock rather than having it deleted by a recovery.
#
# A failure to clear is surfaced rather than swallowed: the callers are
# `recover` and `launch`, and neither may go on to report contention for a
# condition that will not clear.
clear_legacy_lock_dirs() {
  cl_rc=0
  for cl_l in $lock_classes; do
    pw_lock_clear_legacy "$1/$cl_l" 2>/dev/null
    if [ "$?" -eq 2 ]; then
      printf '%s\n' "$me: cannot clear the legacy lock directory $1/$cl_l (parent unwritable or filesystem error)" >&2
      cl_rc=2
    fi
  done
  return "$cl_rc"
}

# `pw_lock_break_force` rather than a bare `rm`: it is the primitive's own
# unconditional clear, and it takes a lock left as a DIRECTORY by the retired
# `mkdir` shape as readily as a symlink — so the close is the second place a
# fleet home that predates the migration gets unwedged. The names are literals
# from `lock_classes` under a directory the caller has already validated.
release_locks() {
  rl_rc=0
  for rl_l in $lock_classes; do
    if [ ! -L "$1/$rl_l" ] && [ ! -e "$1/$rl_l" ]; then
      continue
    fi
    pw_lock_break_force "${1:?}/$rl_l" >/dev/null 2>&1 || :
    if [ -L "$1/$rl_l" ] || [ -e "$1/$rl_l" ]; then
      rl_rc=1
    fi
  done
  return "$rl_rc"
}

held_scratch() {
  stop_scratch_walk "$1" probe "$scratch_patterns"
}

release_scratch() {
  stop_scratch_release "$1" "$scratch_patterns"
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
  # Spooled receipts were never journaled, and a close makes every receipt
  # undeliverable; left behind, a later supervisor would drain them into a
  # session that never asked. A resumed worker that still wants one asks again.
  set +f
  for jc_f in "$1"/deferred-*; do
    if [ -L "$jc_f" ] || [ -f "$jc_f" ]; then rm -f "$jc_f" 2>/dev/null; fi
  done
  set -f
  rm -f "$1/attention.dirty" 2>/dev/null || :
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
    process) held_process "$2" "$(stop_match "$3" "$2")" "$stop_pidfiles" ;;
    locks) held_locks "$2" ;;
    scratch) held_scratch "$2" ;;
    attention) held_attention "$4" "$3" || held_receipts "$2" ;;
    *)
      echo "$me: no held-probe for release class '$1'" >&2
      return 0
      ;;
  esac
}

# held_receipts <dir> — a spooled receipt or a re-sync mark is part of the
# attention class: the close settles both, and either one left behind would be
# replayed into a later session by its tick.
held_receipts() {
  [ -e "$1/attention.dirty" ] && return 0
  set +f
  for hr_f in "$1"/deferred-*; do
    if [ -L "$hr_f" ] || [ -f "$hr_f" ]; then
      set -f
      return 0
    fi
  done
  set -f
  return 1
}

stop_release() {
  case $1 in
    process) release_processes "$2" "$(stop_match "$3" "$2")" "$stop_pidfiles" "$5" ;;
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
  # A lock left as a directory by the retired shape refuses every acquire, the
  # journal's included, so a relaunch clears it as `recover` does.
  clear_legacy_lock_dirs "$dir" || exit 2

  # Single launch initiator, on the same election `recover` uses. Two concurrent
  # launches for one worker otherwise both reach `supervise`, and the second
  # overwrites the first's pid files — orphaning a supervisor that nothing
  # records and nothing can close.
  #
  # The release is armed BEFORE the election, not after it: a signal landing in
  # the gap between a successful take and a later `trap` left the lock standing
  # with no holder. It covers the journal lock a `--foreground` launch goes on
  # to take in this same process, too.
  pw_lock_trap_install
  lock_take "$dir/launch.lock"
  lt_rc=$?
  if [ "$lt_rc" -eq 2 ]; then
    # A real error, not contention: something that is not a lock at the path,
    # or a parent this cannot write. The library has already said which.
    # Calling it "already in flight" would send an operator to look for a
    # launch that does not exist.
    echo "$me: cannot take the launch election for $worker (lock error)" >&2
    exit 2
  fi
  if [ "$lt_rc" -ne 0 ]; then
    echo "$me: a launch is already in flight for $worker (refused: single initiator)" >&2
    exit 3
  fi

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
    body=$(head -c 65537 <"$resp_file")
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
  if [ "$mode" = 'file' ]; then
    # The body must be one object on its own, not merely yield a valid frame
    # once spliced in: `{...},"k":{...}` would close the response early and
    # add a key of its own to the envelope. Staged in the worker directory, as
    # scratch a close clears, since the body can carry tool input.
    resp_probe=$(mktemp "$dir/.frame.XXXXXX") || exit 2
    if ! printf '%s\n' "$body" >"$resp_probe"; then
      rm -f "$resp_probe"
      exit 2
    fi
    resp_why=$(frame_check "$resp_probe")
    resp_ok=$?
    rm -f "$resp_probe"
    if [ "$resp_ok" != 0 ]; then
      echo "$me: --response-file refused: $resp_why" >&2
      exit 2
    fi
  fi

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

  # A frame the check refuses writes nothing and leaves the request pending,
  # so a corrected answer can still land. A dead channel or a failed write is
  # a visible undeliverable verdict, never a silent drop.
  frame=$(mktemp "$dir/.frame.XXXXXX") || {
    journal_unlock "$dir"
    exit 2
  }
  if ! printf '{"type":"control_response","response":{"subtype":"success","request_id":"%s","response":%s}}\n' \
    "$req" "$body" >"$frame"; then
    rm -f "$frame"
    journal_unlock "$dir"
    exit 2
  fi
  trap '' PIPE
  why=$(frame_send "$dir" "$frame")
  sent=$?
  rm -f "$frame"
  case $sent in
    2)
      journal_unlock "$dir"
      echo "$me: answer refused, nothing written to worker $worker: $why (request $short stays pending)" >&2
      exit 2
      ;;
    3)
      journal_set_state "$dir" "$req" undeliverable "$now"
      journal_unlock "$dir"
      attention_failure "$worker" "$dir" \
        "undeliverable answer: channel for worker $worker is dead (request $short) - recover the worker and re-ask"
      exit 3
      ;;
  esac
  if [ "$sent" = 0 ]; then
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
    proj=$(journal_oldest_pending "$dir")
    journal_unlock "$dir"
    attention_sync "$worker" "$dir" "$proj"
    printf 'answered %s %s\n' "$worker" "$req"
  else
    journal_set_state "$dir" "$req" undeliverable "$now"
    journal_unlock "$dir"
    attention_failure "$worker" "$dir" \
      "undeliverable answer: write to worker $worker stdin failed (request $short) - recover the worker and re-ask"
    exit 3
  fi
}

# steer <worker> --message-file <file> — see the header. Delivered through
# frame_send under the journal lock, as `answer` is, but the frame is a USER
# turn, and the only state it writes is its own receipt row.
cmd_steer() {
  [ $# -ge 1 ] || usage
  worker=$1
  shift
  valid_field "$worker" || {
    echo "$me: invalid worker handle" >&2
    exit 2
  }
  st_file=''
  while [ $# -gt 0 ]; do
    case $1 in
      --message-file)
        [ $# -ge 2 ] || usage
        st_file=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  [ -n "$st_file" ] || usage
  if [ ! -f "$st_file" ] || [ ! -r "$st_file" ]; then
    echo "$me: --message-file missing or unreadable" >&2
    exit 2
  fi
  # One byte past the cap, so an oversize message is refused whole rather
  # than truncated into a message the worker reads as complete.
  st_bytes=$(head -c 65537 <"$st_file" | wc -c | tr -d ' ')
  if [ "$st_bytes" -gt 65536 ]; then
    echo "$me: --message-file exceeds the 64 KiB cap (refused, not truncated)" >&2
    exit 2
  fi
  if [ "$(tr -d '[:space:]' <"$st_file" | wc -c | tr -d ' ')" = 0 ]; then
    echo "$me: --message-file is empty" >&2
    exit 2
  fi
  dir=$(worker_dir "$worker") || exit 2
  [ -d "$dir" ] || {
    echo "$me: unknown worker $worker" >&2
    exit 2
  }
  # The receipt row carries the path as given; a tab or newline in it would
  # split the row, so such a path is refused rather than recorded mangled.
  case $st_file in
    *"$TAB"* | *"$NL"*)
      echo "$me: --message-file path may not contain a tab or newline" >&2
      exit 2
      ;;
  esac

  journal_lock "$dir" || exit 2
  now=$(now_epoch) || now=0
  st_body=$(json_escape_file "$st_file") || {
    journal_unlock "$dir"
    exit 2
  }
  st_frame=$(mktemp "$dir/.frame.XXXXXX") || {
    journal_unlock "$dir"
    exit 2
  }
  # The header is the buffer-paste relay's (scripts/orchestrate-relay.sh), so a
  # worker reads a tower message the same way on every rung.
  if ! printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[planwright tower relay -> %s]\\n%s"}]}}\n' \
    "$worker" "$st_body" >"$st_frame"; then
    rm -f "$st_frame"
    journal_unlock "$dir"
    exit 2
  fi
  trap '' PIPE
  st_why=$(frame_send "$dir" "$st_frame")
  st_sent=$?
  rm -f "$st_frame"
  case $st_sent in
    2)
      journal_unlock "$dir"
      echo "$me: steer refused, nothing written to worker $worker: $st_why" >&2
      exit 2
      ;;
    3)
      journal_unlock "$dir"
      echo "$me: steer not delivered: channel for worker $worker is dead (recover the worker first)" >&2
      exit 3
      ;;
  esac
  if [ "$st_sent" = 0 ]; then
    printf '%s\t%s\t%s\n' "$now" "$st_bytes" "$st_file" >>"$dir/steers" || :
    journal_unlock "$dir"
    printf 'steered %s %s\n' "$worker" "$st_bytes"
  else
    journal_unlock "$dir"
    echo "$me: steer not delivered: write to worker $worker stdin failed (recover the worker first)" >&2
    exit 3
  fi
}

# _frame-check <file> — internal: the fifo write discipline's verdict on a
# frame file, printed as `frame ok` or `frame refused: <reason>`, for fixtures
# that need the check without a live channel.
cmd__frame_check() {
  [ $# -eq 1 ] || usage
  if fc_why=$(frame_check "$1"); then
    echo "frame ok"
  else
    echo "frame refused: $fc_why"
    exit 2
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

  # `recover` is the verb an operator reaches for when a worker is stuck, so it
  # is where a fleet home predating the symlink primitive gets its in-place
  # upgrade: one lock left as a directory by the retired shape refuses every
  # acquire for this worker, including the election below. A clear that fails
  # is fatal here rather than swallowed: the election would otherwise report
  # contention for a condition that will not clear.
  clear_legacy_lock_dirs "$dir" || exit 2

  # Single recovery initiator (REQ-E1.5): the election refuses a concurrent
  # second attempt rather than racing it, and breaks a lock whose holder's
  # process is gone — without that break, one SIGKILL between the election and
  # the release wedges `recover` for this worker permanently. The release is
  # armed before the take for the same reason: a signal landing in the gap
  # would leave the lock standing with no holder.
  pw_lock_trap_install
  lock_take "$dir/recover.lock"
  lt_rc=$?
  if [ "$lt_rc" -eq 2 ]; then
    echo "$me: cannot take the recovery election for $worker (lock error)" >&2
    exit 2
  fi
  if [ "$lt_rc" -ne 0 ]; then
    echo "$me: recovery already in progress for $worker (refused: single initiator)" >&2
    exit 3
  fi

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
  # The close this rung shares with the headless one, loaded here so a missing
  # library costs `stop` and no other verb. Required rather than degraded:
  # without it the close has no process match at all.
  if [ ! -r "$script_dir/fleet-stop-lib.sh" ]; then
    echo "$me: required helper $script_dir/fleet-stop-lib.sh missing or not readable" >&2
    exit 2
  fi
  # shellcheck source=scripts/fleet-stop-lib.sh
  . "$script_dir/fleet-stop-lib.sh"
  worker=$1
  shift
  valid_field "$worker" || {
    echo "$me: invalid worker handle" >&2
    exit 2
  }
  grace=$grace_default
  observe=0
  while [ $# -gt 0 ]; do
    case $1 in
      --grace)
        [ $# -ge 2 ] || usage
        grace=$2
        shift 2
        ;;
      --observe)
        observe=1
        shift
        ;;
      *)
        usage
        ;;
    esac
  done
  stop_grace_ok "$grace" || {
    stop_grace_refusal
    exit 2
  }
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
  stop_refuse_self_hosted "$dir" "$(stop_match "$worker" "$dir")" \
    "$stop_pidfiles" "$worker"
  st_root=$(/bin/sh "$FS" root) || exit 2
  if [ "$observe" = 1 ]; then
    stop_observe "$dir" "$worker" "$st_root/attention/state"
    return
  fi
  stop_walk "$dir" "$worker" "$st_root/attention/state" "$grace"
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
  # Its stderr is the supervisor's log, the one place a ticker that never
  # started can be seen, so every refusal says what it refused.
  valid_field "$tk_worker" || {
    echo "$me: tick: invalid worker handle" >&2
    exit 2
  }
  if ! valid_posnum "$tk_sup" || ! valid_posnum "$tk_wrk"; then
    echo "$me: tick: supervisor and worker pids must be positive integers" >&2
    exit 2
  fi
  # The directory must be this worker's own state directory, resolved the way
  # every other verb resolves it, not a caller-chosen path to scan.
  tk_expect=$(worker_dir "$tk_worker") || exit 2
  if [ "$tk_dir" != "$tk_expect" ] || [ ! -d "$tk_dir" ]; then
    echo "$me: tick: $tk_dir is not the state directory of worker $tk_worker" >&2
    exit 2
  fi
  tk_tick=${PLANWRIGHT_STREAMJSON_ALARM_TICK:-60}
  valid_posnum "$tk_tick" || {
    echo "$me: tick: invalid PLANWRIGHT_STREAMJSON_ALARM_TICK '$tk_tick'; using 60" >&2
    tk_tick=60
  }
  tk_thr=${PLANWRIGHT_STREAMJSON_PENDING_AGE:-900}
  valid_posnum "$tk_thr" || {
    echo "$me: tick: invalid PLANWRIGHT_STREAMJSON_PENDING_AGE '$tk_thr'; using 900" >&2
    tk_thr=900
  }
  tk_i=0
  while :; do
    sleep 1
    pid_live "$tk_sup" || exit 0
    pid_live "$tk_wrk" || exit 0
    # Every beat, not every tick: a receipt the journal lock refused is the
    # one thing here that someone is waiting on.
    receipt_drain "$tk_worker" "$tk_dir" 1 || :
    attention_resync "$tk_worker" "$tk_dir"
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
  # An intentional glob, like cmd_pending's: enumerate worker dirs (pathname
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
  aw_worker=$1
  aw_dir=$2
  aw_now=$3
  aw_thr=$4
  aw_tick=$5
  if [ -z "$aw_now" ]; then
    aw_now=$(now_epoch) || return 2
  fi
  # Candidate ids only. Everything the escalation acts on -- kind, received
  # epoch, state -- is re-read under the lock below, because this read is
  # unlocked and its values can be stale by the time the lock is taken.
  # Carrying them forward from here is what let a re-opened request be
  # escalated against the age this scan measured.
  # Read into a variable and looped in this shell, not piped: a pipeline runs
  # the loop in a subshell whose locks carry this shell's pid, held by a
  # process that can outlive or predecease the one the token names.
  aw_ids=$(awk -F'\t' -v now="$aw_now" -v thr="$aw_thr" \
    '$4 == "pending" && (now - $3) > thr { print $1 }' \
    "$aw_dir/journal") || aw_ids=''
  while read -r a_id; do
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
    # The DECISION is made under one lock, from one read. The publish is not:
    # the attention store takes the fleet lock, and holding the journal across
    # it is how one stuck lock becomes two. So the publish is confirmed
    # afterwards instead, the way attention_sync confirms every other one: if
    # an answer settled the request while the row was being written, the
    # confirmation finds it no longer pending and republishes what the journal
    # implies now. Every skip path below unlocks before it leaves.
    if ! journal_lock "$aw_dir"; then
      break
    fi
    aw_row=$(awk -F'\t' -v id="$a_id" '$1 == id { print $2 "\t" $3 "\t" $4; exit }' \
      "$aw_dir/journal" 2>/dev/null) || aw_row=''
    aw_now_kind=${aw_row%%"$TAB"*}
    aw_rest=${aw_row#*"$TAB"}
    aw_recv=${aw_rest%%"$TAB"*}
    aw_state=${aw_rest#*"$TAB"}
    aw_fired=0
    if [ "$aw_state" = pending ] && valid_posnum "${aw_recv:-}"; then
      aw_age=$((aw_now - aw_recv))
      if [ "$aw_age" -gt "$aw_thr" ]; then
        aw_fired=1
      fi
    fi
    journal_unlock "$aw_dir"
    [ "$aw_fired" = 1 ] || continue
    attention_upsert "$aw_worker" "$aw_dir" "$a_id" "$aw_now_kind" high
    if journal_lock "$aw_dir" 2>/dev/null; then
      aw_still=$(journal_state "$aw_dir" "$a_id")
      aw_proj=$(journal_oldest_pending "$aw_dir")
      journal_unlock "$aw_dir"
      [ "$aw_still" = pending ] || attention_sync "$aw_worker" "$aw_dir" "$aw_proj"
    fi
    if [ -z "$aw_tick" ] || [ "$aw_age" -le $((aw_thr + aw_tick)) ]; then
      /bin/sh "$FA" notify \
        "stream-json worker $aw_worker: request $(printf '%s' "$a_id" | cut -c1-8) pending ${aw_age}s past threshold" \
        >/dev/null 2>&1 || :
    fi
    printf 'alarm %s %s %s\n' "$aw_worker" "$a_id" "$aw_age"
  done <<AWIDS
$aw_ids
AWIDS
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
    # count and the oldest age, rather than a `running` that reads as healthy.
    # One read of the journal for both figures, so the count and the age come
    # from the same generation of a file that is replaced by rename; a pending
    # row whose epoch is unreadable still counts, with the age reported as
    # unknown rather than the row dropped back to `running`.
    st_pend=0
    st_oldest=''
    if [ -f "$dir/journal" ]; then
      st_row=$(awk -F'\t' '$4 == "pending" { n++; if ($3 ~ /^[0-9]+$/ && (o == "" || $3 + 0 < o + 0)) o = $3 } END { print n + 0 "\t" o }' \
        "$dir/journal" 2>/dev/null) || st_row=''
      st_pend=${st_row%%"$TAB"*}
      st_oldest=${st_row#*"$TAB"}
      [ "$st_oldest" != "$st_row" ] || st_oldest=''
    fi
    # A receipt spooled because the journal lock was busy is waiting on an
    # answer just the same.
    set +f
    for st_f in "$dir"/deferred-*; do
      [ -f "$st_f" ] && [ ! -L "$st_f" ] || continue
      st_pend=$((${st_pend:-0} + 1))
      st_e=$(head -n 1 "$st_f" 2>/dev/null) || st_e=''
      if valid_posnum "${st_e:-}" && { [ -z "$st_oldest" ] || [ "$st_e" -lt "$st_oldest" ]; }; then
        st_oldest=$st_e
      fi
    done
    set -f
    if valid_posnum "${st_pend:-}"; then
      st_age=unknown
      if valid_posnum "${st_oldest:-}" && st_now=$(now_epoch); then
        st_age=$((st_now - st_oldest))
        [ "$st_age" -ge 0 ] || st_age=0
        st_age="${st_age}s"
      fi
      printf 'status %s awaiting-input pending=%s oldest=%s supervisor=%s worker=%s\n' \
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

# The display bound for one request's tool input, and the most of an envelope
# the renderer reads at all. A Write's content can be megabytes; the tower needs
# enough to recognise the request, not the whole payload. The read bound is also
# a time bound: busybox awk's substr costs grow with the offset, so a walk over
# 300 KiB there takes seconds where 64 KiB takes a fraction of one. An envelope
# cut by it still shows the start of its input, marked as ending early.
pending_show_max=4096
pending_read_max=65536

# pending_render — read a stored control_request envelope on stdin and print
# four things, one per line but the last: a header-safe tool-name token, a
# flag (`bad` for an envelope with no readable input or malformed JSON;
# otherwise 0 or 1 for a display-bound cut, led by `a` when `answer --allow`
# would splice another input and `e` when the envelope ends early), the Bash request's other input fields as one line of raw
# JSON members (empty otherwise), then the content. The content is the decoded
# top-level `command` of a request whose tool is named exactly Bash, otherwise
# the input object's JSON text. The walk follows the JSON structure rather than
# searching for a key name, so a string that merely contains `"input":` or
# `"command":` cannot pass for the real field, and a repeated key resolves to
# its last occurrence, the one the CLI itself acts on. Unicode escapes for
# printable ASCII, TAB and LF are decoded so the command reads as it will run;
# every other escape stays as visible escape text. Raw control bytes are the
# caller's to strip.
pending_render() {
  awk -v cap="$pending_show_max" '
    # A walk that runs off the end met an envelope cut short (the read bound,
    # or a read racing the write), which is shown marked as such; any other
    # failure is malformed JSON, which is not shown at all.
    function fail() {
      err = 1
      if (pos > n) eof = 1
    }
    function ws() {
      while (pos <= n && index(" \t\r\n", substr(s, pos, 1)) > 0) pos++
    }
    function pstr(   st, c) {
      st = ++pos
      while (pos <= n) {
        c = substr(s, pos, 1)
        if (c == "\\") { pos += 2; continue }
        if (c == "\"") { pos++; return substr(s, st, pos - 1 - st) }
        pos++
      }
      fail()
      return substr(s, st)
    }
    function hexv(h,   i, v, d) {
      v = 0
      for (i = 1; i <= 4; i++) {
        d = index("0123456789abcdef", tolower(substr(h, i, 1))) - 1
        if (d < 0) return -1
        v = v * 16 + d
      }
      return v
    }
    function dec(raw, lim,   out, i, m, c, e, v) {
      out = ""
      m = length(raw)
      for (i = 1; i <= m; i++) {
        if (lim && length(out) > lim) { trunc = 1; return substr(out, 1, lim) }
        c = substr(raw, i, 1)
        if (c != "\\") { out = out c; continue }
        e = substr(raw, ++i, 1)
        if (e == "n") out = out "\n"
        else if (e == "t") out = out "\t"
        else if (e == "\"" || e == "\\" || e == "/") out = out e
        else if (e == "u") {
          v = hexv(substr(raw, i + 1, 4))
          if (v == 9) out = out "\t"
          else if (v == 10) out = out "\n"
          else if (v >= 32 && v <= 126) out = out sprintf("%c", v)
          else out = out "\\u" substr(raw, i + 1, 4)
          i += 4
        } else out = out "\\" e
      }
      if (lim && length(out) > lim) { trunc = 1; return substr(out, 1, lim) }
      return out
    }
    function val(path, d,   c, k, str, kst) {
      if (d > 64) { fail(); return }
      ws()
      if (pos > n) { fail(); return }
      if (path == "/request") { tool = ""; ins = 0; ine = 0; hc = 0 }
      if (path == "/request/input") { ins = pos; ine = 0; hc = 0; extra = ""; xcut = 0 }
      if (path == "/request/input/command") hc = 0
      c = substr(s, pos, 1)
      if (c == "{" || c == "[") {
        pos++
        ws()
        if (substr(s, pos, 1) == (c == "{" ? "}" : "]")) pos++
        else while (1) {
          if (c == "{") {
            ws()
            if (substr(s, pos, 1) != "\"") { fail(); return }
            kst = pos
            # Bounded: decoding appends a byte at a time, quadratic in the key,
            # and no key the walk matches is anywhere near this long.
            k = dec(pstr(), 16)
            if (err) return
            ws()
            if (substr(s, pos, 1) != ":") { fail(); return }
            pos++
            # The path joins keys with a slash, so a slash inside one key would
            # let `"input/command"` spell a nested path it is not.
            gsub(/\//, "\001", k)
            val(path "/" k, d + 1)
            # What the command view would otherwise hide: every input field
            # but the command itself and the model-written description.
            if (!err && path == "/request/input" && k != "command" && k != "description" && !xcut) {
              extra = extra (extra == "" ? "" : ",") substr(s, kst, pos - kst)
              if (length(extra) > cap) { extra = substr(extra, 1, cap); xcut = 1 }
            }
          } else val(path "/[]", d + 1)
          if (err) return
          ws()
          if (pos > n) { fail(); return }
          k = substr(s, pos, 1)
          pos++
          if (k == ",") continue
          if (k == (c == "{" ? "}" : "]")) break
          fail()
          return
        }
      } else if (c == "\"") {
        str = pstr()
        if (path == "/request/tool_name") tool = str
        if (path == "/request/input/command") { cmd = str; hc = 1 }
        if (err) return
      } else {
        k = pos
        while (pos <= n && index(",]} \t\r\n", substr(s, pos, 1)) == 0) pos++
        if (pos == k || pos > n) { fail(); return }
        if (substr(s, k, pos - k) !~ /^(true|false|null|-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?)$/) { fail(); return }
      }
      if (path == "/request/input") ine = pos
    }
    NR == 1 {
      s = $0
      n = length(s)
      pos = 1
      val("", 0)
      if (!err) {
        ws()
        if (pos <= n) fail()
      }
    }
    END {
      trunc = 0
      name = dec(tool, 64)
      t = name
      gsub(/[^A-Za-z0-9_.:-]/, "", t)
      if (t == "") t = "unknown"
      else if (t != name || trunc) t = t ":sanitized"
      trunc = 0
      if (ins == 0 || (err && !eof)) { print t; print "bad"; exit }
      if (name == "Bash" && hc) {
        out = dec(cmd, cap)
        if (extra != "") extra = xcut extra
      } else {
        extra = ""
        out = ine ? substr(s, ins, ine - ins) : substr(s, ins)
        if (length(out) > cap) { out = substr(out, 1, cap); trunc = 1 }
      }
      # `answer --allow` splices the object json_input_object finds, the one
      # after the first literal `"input":`. Unless that is the object shown
      # here, the tower would approve something other than what it read.
      j = index(s, "\"input\":")
      if (j) { j += 8; while (substr(s, j, 1) == " ") j++ }
      print t
      print (j == ins ? "" : "a") (eof ? "e" : "") trunc
      print extra
      print out
    }'
}

# pending_show <worker> <dir> <id> — print one request: the header, then its
# `-- ` notices (unreadable, ambiguous, ends early, fields cut, content cut)
# and a Bash request's other fields on one `+ ` line, then every content line
# behind a `| ` prefix.
# Every notice precedes the content so a piped `head` cannot drop one. The prefix is what keeps the framing unforgeable: no content line
# can begin with `== `, `+ ` or `-- `, whatever the request carries, and the
# fields line is one line because the envelope it is sliced from is.
pending_show() {
  ps_env="$2/req-$3.json"
  if [ -L "$ps_env" ] || [ ! -f "$ps_env" ]; then
    ps_env=/dev/null
  fi
  ps_out=$(
    head -c "$pending_read_max" "$ps_env" 2>/dev/null | pending_render
    printf x
  )
  ps_out=${ps_out%x}
  ps_tool=${ps_out%%"$NL"*}
  ps_out=${ps_out#*"$NL"}
  ps_flag=${ps_out%%"$NL"*}
  ps_out=${ps_out#*"$NL"}
  ps_extra=${ps_out%%"$NL"*}
  ps_out=${ps_out#*"$NL"}
  printf '== %s %s %s\n' "$1" "$3" "${ps_tool:-unknown}"
  if [ "$ps_flag" = bad ] || [ -z "$ps_flag" ]; then
    echo '-- request envelope unreadable'
    return 0
  fi
  case $ps_flag in
    a*)
      echo '-- request envelope ambiguous: an answer --allow would not apply the input shown'
      ps_flag=${ps_flag#a}
      ;;
  esac
  # `answer --allow` splices from the whole file, so a field past the cut (a
  # later command, a sandbox bypass) would still apply.
  case $ps_flag in
    e*)
      printf -- '-- request envelope ends early (read bound %s bytes, or still being written): fields after the cut are not shown and an answer --allow may apply them\n' "$pending_read_max"
      ps_flag=${ps_flag#e}
      ;;
  esac
  # The fields line leads with its own cut flag, so a cut is marked on the line
  # it hides fields from rather than on the command's trailer.
  case $ps_extra in
    0*) printf '+ {%s}\n' "${ps_extra#0}" | tr -d '\000-\010\013-\037\177\200-\237' ;;
    1*)
      printf '+ {%s\n' "${ps_extra#1}" | tr -d '\000-\010\013-\037\177\200-\237'
      printf -- '-- fields truncated at %s bytes\n' "$pending_show_max"
      ;;
  esac
  if [ "$ps_flag" = 1 ]; then
    printf -- '-- truncated at %s bytes: the content below is cut short\n' "$pending_show_max"
  fi
  printf '%s' "${ps_out%"$NL"}" | tr -d '\000-\010\013-\037\177\200-\237' | awk '{ print "| " $0 } END { if (NR == 0) print "| " }'
}

# pending_worker <worker> <dir> — every request of one worker the journal still
# reads pending, driven by the journal rather than the envelope files, so a row
# whose envelope never landed is still listed. Read-only: no lock is taken,
# since the journal is replaced by rename and an unlocked read sees one whole
# generation of it.
pending_worker() {
  if [ ! -r "$2" ] || [ ! -x "$2" ] || { [ -e "$2/journal" ] && [ ! -r "$2/journal" ]; }; then
    echo "$me: cannot read the receipt journal of worker $1" >&2
    return 2
  fi
  pw_ids=$(journal_pending_ids "$2") || {
    echo "$me: cannot read the receipt journal of worker $1" >&2
    return 2
  }
  [ -n "$pw_ids" ] || return 0
  printf '%s\n' "$pw_ids" | while IFS= read -r pw_id; do
    valid_reqid "$pw_id" || continue
    pending_show "$1" "$2" "$pw_id"
  done
}

cmd_pending() {
  for pd_w in "$@"; do
    valid_field "$pd_w" || {
      echo "$me: invalid worker handle" >&2
      exit 2
    }
  done
  pd_root=$(/bin/sh "$FS" root) || exit 2
  # An unreadable worker fails the call, but only after the others are listed:
  # one broken dir must not hide every other worker's pending decisions.
  pd_rc=0
  if [ $# -eq 0 ]; then
    [ -d "$pd_root/streamjson" ] || return 0
    [ -r "$pd_root/streamjson" ] && [ -x "$pd_root/streamjson" ] || {
      echo "$me: cannot list the stream-json workers under $pd_root" >&2
      exit 2
    }
    set +f
    for pd_dir in "$pd_root/streamjson"/*; do
      [ -d "$pd_dir" ] || continue
      pd_w=${pd_dir##*/}
      valid_field "$pd_w" || continue
      pending_worker "$pd_w" "$pd_dir" || pd_rc=2
    done
    set -f
    exit "$pd_rc"
  fi
  for pd_w in "$@"; do
    [ -d "$pd_root/streamjson/$pd_w" ] || {
      echo "$me: no stream-json worker $pd_w" >&2
      exit 2
    }
  done
  for pd_w in "$@"; do
    pending_worker "$pd_w" "$pd_root/streamjson/$pd_w" || pd_rc=2
  done
  exit "$pd_rc"
}

# --- dispatch ---------------------------------------------------------------

[ $# -ge 1 ] || usage
cmd=$1
shift
case $cmd in
  launch) cmd_launch "$@" ;;
  answer) cmd_answer "$@" ;;
  steer) cmd_steer "$@" ;;
  recover) cmd_recover "$@" ;;
  alarm-scan) cmd_alarm_scan "$@" ;;
  _tick) cmd__tick "$@" ;;
  stop) cmd_stop "$@" ;;
  status) cmd_status "$@" ;;
  pending) cmd_pending "$@" ;;
  _supervise) supervise "$@" ;;
  _frame-check) cmd__frame_check "$@" ;;
  *) usage ;;
esac
