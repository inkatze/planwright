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
# --output-format stream-json --verbose --permission-prompt-tool stdio`,
# non-`--bare` pinned per D-12/REQ-A1.5 — pinning means never passing
# `--bare`, and this script additionally REFUSES a caller-supplied `--bare`),
# captures every event line, and converts the one verified deadlock — a
# `can_use_tool` control_request pends forever if unanswered — into the
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
#   supervisor.pid / worker.pid / result / recover.lock/ / journal.lock/ /
#   launch.lock/
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
# signal): `status` reports completed from the captured result event, and
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
#       reads as a successful close.
#   fleet-streamjson.sh status <worker>
#       Print `status <worker> <running|completed|dead|unknown> <detail>`
#       from the recorded pids and the captured event stream.
#
# Exit codes: 0 success; 2 usage error, refused hostile input, or a
#   filesystem/lock error (fail closed); 3 a semantic refusal (recovery
#   already in flight / a launch already in flight or over a live supervisor /
#   not orphaned / the answer does not apply — the undeliverable-answer arms
#   exit 3 AFTER surfacing the attention item); 4 recovery halt: no usable
#   session to resume; 5 recovery halt: the `--resume` relaunch failed; 6 a
#   partial close: some class of the release set is still held.
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
    kill -0 "$lt_holder" 2>/dev/null && return 1
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

# worker_alive <dir> — true when a pid this worker's own state records is live.
worker_alive() {
  for wa_f in supervisor.pid worker.pid; do
    wa_p=$(cat "$1/$wa_f" 2>/dev/null) || wa_p=''
    if valid_posnum "${wa_p:-}" && kill -0 "$wa_p" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# --- journal (the REQ-E1.5 durable receipt state) ---------------------------
# One tab-separated row per request id: id kind received-epoch state [epoch].
# Mutations run under an mkdir lock, stale-broken past its age: journal writes
# are sub-second, so an older lock is a crashed holder, and breaking it can
# at worst duplicate an attention upsert — never lose a receipt.

journal_lock() {
  jl_dir="$1/journal.lock"
  jl_i=0
  while ! mkdir "$jl_dir" 2>/dev/null; do
    jl_i=$((jl_i + 1))
    if [ "$jl_i" -ge 50 ]; then
      jl_now=$(now_epoch) || return 2
      jl_mt=$(stat_mtime "$jl_dir") || jl_mt=$jl_now
      if [ $((jl_now - jl_mt)) -gt "$journal_lock_stale" ]; then
        rmdir "$jl_dir" 2>/dev/null
        jl_i=0
        continue
      fi
      echo "$me: journal lock busy at $jl_dir" >&2
      return 2
    fi
    sleep 0.1
  done
}

journal_unlock() {
  rmdir "$1/journal.lock" 2>/dev/null
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
          journal_unlock "$hl_dir"
          attention_upsert "$hl_worker" "$hl_dir" "$hl_id" "$hl_kind"
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
      journal_unlock "$hl_dir"
      attention_upsert "$hl_worker" "$hl_dir" "$hl_id" "$hl_kind"
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
      printf 'result\t%s\t%s\n' "$hl_sub" "$hl_now" >"$hl_dir/result"
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
  write_pidfile "$sv_dir/worker.pid" "$sv_pid" || :
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
# exclusion is also why such a close cannot be allowed to proceed at all —
# `stop_self_hosted` refuses it before the walk starts, because a walk that
# cannot see the supervisor would report the whole release set free.
#
# The match text goes through the environment rather than `awk -v`, which
# rewrites backslash escapes in the value it assigns: the fleet home is taken
# verbatim from the operator's configuration, and a `\t` in it would otherwise
# make the comparison silently target a path nobody asked for.
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
  SC_MATCH="_supervise $2 $sc_dir"
  export SC_MATCH
  printf '%s\n' "$sc_snap" | awk -v seeds="$sc_seed" -v self_pid="$$" '
    BEGIN { sup = ENVIRON["SC_MATCH"] }
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
# Such a close cannot work, and the failure is silent in the worst direction:
# the candidate walk excludes the closer and everything it descends from, so the
# supervisor it should be signalling is exactly what it cannot see. It would
# find nothing to kill, clear the pid files as though the tree were gone, and
# then release the locks and delete the stdio fifos of a worker that is still
# running — reporting `stopped` while leaving it alive with no channel, and with
# nothing recorded for `launch` to refuse a second supervisor on. Refusing is
# the only honest answer; the close has to come from outside.
stop_self_hosted() {
  ssh_snap=$(ps_rows) || return 1
  ssh_seed=''
  for ssh_f in supervisor.pid worker.pid; do
    ssh_p=$(cat "$1/$ssh_f" 2>/dev/null) || ssh_p=''
    if valid_posnum "${ssh_p:-}"; then
      ssh_seed="$ssh_seed $ssh_p"
    fi
  done
  SC_MATCH="_supervise $2 $1"
  export SC_MATCH
  printf '%s\n' "$ssh_snap" | awk -v seeds="$ssh_seed" -v self_pid="$$" '
    BEGIN { sup = ENVIRON["SC_MATCH"] }
    $1 ~ /^[0-9]+$/ {
      ppid[$1] = $2
      n++
      if (index($0, sup)) owner[$1] = 1
    }
    END {
      m = split(seeds, s, " ")
      for (i = 1; i <= m; i++) if (s[i] != "") owner[s[i]] = 1
      delete owner["0"]
      delete owner["1"]
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
    kill -0 "$sl_p" 2>/dev/null || continue
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
# able to make progress.
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

  dir=$(worker_dir "$worker") || exit 2
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

  # The pinned launch shape (REQ-A1.3, D-12): -p with stream-json both ways,
  # --verbose (required with -p stream-json output), the stdio permission
  # prompt tool (the receipt channel), and NEVER --bare.
  set -- "$cli" -p --input-format stream-json --output-format stream-json \
    --verbose --permission-prompt-tool stdio "$@"
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
  valid_posnum "${sup_pid:-}" && kill -0 "$sup_pid" 2>/dev/null || channel_ok=0
  valid_posnum "${wrk_pid:-}" && kill -0 "$wrk_pid" 2>/dev/null || channel_ok=0
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
    journal_unlock "$dir"
    attention_settled "$worker" "$dir"
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
    if valid_posnum "${pid:-}" && kill -0 "$pid" 2>/dev/null; then
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
  if stop_self_hosted "$dir" "$worker"; then
    echo "$me: refusing to close $worker from inside its own process tree" >&2
    exit 3
  fi
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
    awk -F'\t' -v now="$now" -v thr="$threshold" \
      '$4 == "pending" && (now - $3) > thr { print $1 "\t" $2 "\t" now - $3 }' \
      "$as_dir/journal" | while IFS="$(printf '\t')" read -r a_id a_kind a_age; do
      valid_reqid "$a_id" || continue
      # Escalation only (the kickoff-pinned alarm outcome): the queue item
      # is re-upserted at high priority and the notify seam is pushed —
      # never an auto-answer, never a worker kill.
      attention_upsert "$as_worker" "$as_dir" "$a_id" "$a_kind" high
      /bin/sh "$FA" notify \
        "stream-json worker $as_worker: request $(printf '%s' "$a_id" | cut -c1-8) pending ${a_age}s past threshold" \
        >/dev/null 2>&1 || :
      printf 'alarm %s %s %s\n' "$as_worker" "$a_id" "$a_age"
    done
  done
  set -f
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
  if [ -f "$dir/result" ]; then
    st_kind=$(awk -F'\t' 'NR == 1 { print $1 }' "$dir/result")
    detail=$(awk -F'\t' 'NR == 1 { print $1 "=" $2 }' "$dir/result")
    detail=$(sanitize_printable "$detail" unknown | cut -c1-64)
    # A `result` event is a completion; an `exit` fallback record with a
    # non-zero code is a worker that ended without completing the protocol —
    # rendered `ended`, never conflated with `completed` (a `result` event or
    # an exit=0 fallback is completion).
    st_ec=$(awk -F'\t' 'NR == 1 { print $2 }' "$dir/result")
    if [ "$st_kind" = exit ] && [ "$st_ec" != 0 ]; then
      printf 'status %s ended %s\n' "$worker" "$detail"
    else
      printf 'status %s completed %s\n' "$worker" "$detail"
    fi
    return 0
  fi
  sup_pid=$(cat "$dir/supervisor.pid" 2>/dev/null) || sup_pid=''
  wrk_pid=$(cat "$dir/worker.pid" 2>/dev/null) || wrk_pid=''
  if valid_posnum "${sup_pid:-}" && kill -0 "$sup_pid" 2>/dev/null \
    && valid_posnum "${wrk_pid:-}" && kill -0 "$wrk_pid" 2>/dev/null; then
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
  stop) cmd_stop "$@" ;;
  status) cmd_status "$@" ;;
  _supervise) supervise "$@" ;;
  *) usage ;;
esac
