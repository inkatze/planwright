#!/bin/sh
# fleet-streamjson.sh — the stream-json-persistent supervisor primitive
# (execution-backends Task 4; D-4, D-5 · REQ-A1.3, REQ-A1.9, REQ-E1.1,
# REQ-E1.2, REQ-E1.3, REQ-E1.4, REQ-E1.5).
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
#   supervisor.pid / worker.pid / result / recover.lock/ / journal.lock/
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
#       (exit 2): the non-bare pin is structural.
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
#   fleet-streamjson.sh status <worker>
#       Print `status <worker> <running|completed|dead|unknown> <detail>`
#       from the recorded pids and the captured event stream.
#
# Exit codes: 0 success; 2 usage error, refused hostile input, or a
#   filesystem/lock error (fail closed); 3 a semantic refusal (recovery
#   already in flight / not orphaned / the answer does not apply — the
#   undeliverable-answer arms exit 3 AFTER surfacing the attention item);
#   4 recovery halt: no usable session to resume; 5 recovery halt: the
#   `--resume` relaunch failed.
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling): awk,
# mkfifo, mktemp, `date +%s`, a fractional `sleep`. No eval, no jq
# (REQ-K1.5); all parsed content — event lines, request ids, prompt text —
# is data, never code. Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

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

# Portable mtime-in-epoch (BSD stat, then GNU stat).
stat_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# --- journal (the REQ-E1.5 durable receipt state) ---------------------------
# One tab-separated row per request id: id kind received-epoch state [epoch].
# Mutations run under an mkdir lock, stale-broken past 60s: journal writes
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
      if [ $((jl_now - jl_mt)) -gt 60 ]; then
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

# json_escape_file <file> — print the file's content as a JSON string body
# (no surrounding quotes): backslash, quote, tab, and CR escaped; newlines
# between lines become \n; remaining C0 control bytes and DEL are stripped
# (prompt text is data — a stray control byte is dropped, never smuggled).
# Bytes >= 0x80 are kept, so raw UTF-8 (accents, em-dash, CJK, emoji) reaches
# the worker intact — JSON strings carry UTF-8 verbatim. Under the pinned
# LC_ALL=C the class below is a byte-range strip, so it removes only C0/DEL,
# not the UTF-8 continuation/lead bytes a `[^[:print:]]` strip would delete.
json_escape_file() {
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
  ' "$1"
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
          journal_set_state "$hl_dir" "$hl_id" pending "$hl_now" \
            || echo "$me: could not re-open request $(printf '%s' "$hl_id" | cut -c1-8) on resume" >&2
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
  printf '%s\n' "$$" >"$sv_dir/supervisor.pid"
  "$@" <"$sv_dir/in.fifo" >"$sv_dir/out.fifo" 2>>"$sv_dir/stderr.log" &
  sv_pid=$!
  printf '%s\n' "$sv_pid" >"$sv_dir/worker.pid"
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

  if [ -n "$run_cwd" ]; then
    cd "$run_cwd" || {
      rm -f "$init_msg"
      echo "$me: --cwd not accessible" >&2
      exit 2
    }
  fi

  if [ "$foreground" = 1 ]; then
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
  (sh "$self" _supervise "$worker" "$dir" "$init_msg" "$@" \
    >/dev/null 2>>"$dir/supervisor.log" </dev/null &)
  # Confirm startup by a signal that survives a fast run: supervisor.pid
  # appears while the supervisor is live, and it removes that pid plus writes a
  # `result` on exit — so a run that already finished shows `result` even
  # though supervisor.pid is gone again. Either proves the supervisor came up;
  # a launch that produces neither within the window failed before mkfifo and
  # is surfaced, never reported as an optimistic `launched`.
  li=0
  while [ "$li" -lt 50 ]; do
    if [ -f "$dir/supervisor.pid" ] || [ -f "$dir/result" ]; then
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
  # verdict, never a hang (REQ-E1.4's dead-channel arm).
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
      deny_esc=$(printf '%s' "$deny_msg" | head -c 512 \
        | awk 'NR > 1 { printf "\\n" } { s = $0; gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); printf "%s", s }')
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

  # Single recovery initiator (REQ-E1.5): the atomic mkdir is the election;
  # a concurrent second attempt is refused, never raced.
  if ! mkdir "$dir/recover.lock" 2>/dev/null; then
    echo "$me: recovery already in progress for $worker (refused: single initiator)" >&2
    exit 3
  fi
  trap 'rmdir "$dir/recover.lock" 2>/dev/null' EXIT

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
  if sh "$self" launch "$worker" --resume-session "$sid" ${foreground:+"$foreground"} "$@"; then
    printf 'recovered %s session %s\n' "$worker" "$sid"
  else
    ec=$?
    attention_failure "$worker" "$dir" \
      "resume halt: --resume relaunch for worker $worker failed (exit $ec) - unit halted awaiting operator direction"
    echo "$me: --resume relaunch failed for $worker (exit $ec); halt (REQ-E1.5)" >&2
    exit 5
  fi
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
  status) cmd_status "$@" ;;
  _supervise) supervise "$@" ;;
  *) usage ;;
esac
