#!/bin/sh
# fleet-stuck-detector.sh — the four-state stuck-detector and its
# owner-attribution axis (fleet-lifecycle-closure Task 7: D-4;
# REQ-C1.1–REQ-C1.8, REQ-K1.5).
#
# WHAT THIS IS (D-4). A pure classifier over the fleet's existing structured
# surfaces that positively enumerates four worker states, each established by
# its OWN signal, and crosses them with who owns the worker. It reads; it
# never writes a store, never terminates anything, never answers a prompt.
# The incident it encodes: a monitor sampling a frozen worker's last pane
# line reported eleven identical healthy heartbeats, because the line was
# stable precisely BECAUSE the worker was stuck (obs:50eac4ac). So absence of
# change is never evidence here — a surface carrying no positive signal
# classifies NONE of the four, and says so.
#
# THE FOUR STATES and the signal that establishes each (REQ-C1.1):
#   dead                    fleet-death-evidence.sh's POSITIVE verdict on the
#                           worker's death handle (REQ-C1.5). alive, unknown,
#                           an errored or refused call, a `none` handle, and
#                           no handle at all are every one of them not-dead.
#   waiting-on-a-human      a hook push — the attention store's awaiting-input
#                           row (PermissionRequest / Notification / a supervisor
#                           decide) — or a pending control_request in the
#                           stream-json journal, or a POSITIVELY MATCHED
#                           permission-prompt signature in a captured pane
#                           (REQ-C1.2, obs:4c25e743). Never elapsed time.
#   finished-but-unreaped   a session-ended signal — the attention store's
#                           `ended` row (SessionEnd), the stream-json `result`
#                           record, the headless `exit` record — while the
#                           worker is not positively dead (REQ-C1.3). A
#                           completion whose work is demonstrably unlanded
#                           (an uncommitted tree, commits absent from the
#                           remote-tracking ref) is NOT finished (REQ-C1.4,
#                           obs:cc13d432): it reports `unclassified` with
#                           reason `completion-unlanded`, so a positive-looking
#                           status can never hide stranded work.
#   working                 a pushed working row, a busy marker in the pane
#                           footer (a running-turn spinner), or a live
#                           stream-json supervisor with no result yet.
# Precedence, highest first: dead, waiting-on-a-human, a completion signal,
# working. Death evidence outranks a stale push; a queued human decision
# outranks a captured result; a captured result outranks a stale working row.
#
# UNCLASSIFIED is the honest fifth word, never a default state: a worker with
# no positive signal (`no-signal`), a turn that ended with nothing further
# pushed (`turn-ended`), a StopFailure push (`stop-failure`), or the unlanded
# completion above. A consumer treats it as "leave alone and surface".
#
# THE UNLANDED CHECK reads LOCAL git state only (REQ-C1.4): `git status` and
# the commit count against the remote-tracking ref. No fetch, no `gh`, no
# per-worker forge query — it is cheap and works offline; whether a unit owes
# a PR is not inferred here. The worktree resolves from --worktree, else the
# registry state dir when that IS a worktree (the tmux rung), else the
# `cwd` of the stream-json init event; unresolvable degrades to
# `unverifiable`, which is not "demonstrably unlanded".
#
# OWNER ATTRIBUTION (REQ-C1.6, D-4). Every state carries one of three words,
# resolved from the dispatch record's owner token and the presence surface:
#   this-tower       the token equals this tower's identity (--tower-id, else
#                    $PLANWRIGHT_TOWER_ID, else fleet-presence.sh identity from
#                    --session-id/--pid + --checkout)
#   live-peer        fleet-presence.sh liveness reports the token live
#   dead-or-unknown  everything else — an absent token, a dead / unknown /
#                    ambiguous / unreadable / unrecorded tower, a surface that
#                    cannot be read, or no identity to ask with. Degradation
#                    always lands here, never on this-tower: the same signal
#                    means opposite things depending on who owns the worker,
#                    and a reaper must never mistake a peer's worker for ours.
#
# STAGE (REQ-C1.7) rides a separate axis from liveness, named `stage` so
# `phase` stays the resource-class sense: derived cheaply from the event
# stream's most recent stage-bearing event — `launched` (init only),
# `implementing` (a tool use), `converging` (a review-skill invocation),
# `handing-off` (a push in a Bash tool use), `completed` (a result event) —
# and `-` with `stage-source absent` where no stream exists.
#
# OUTPUT (REQ-C1.8), tab-separated, one grammar, no LLM needed to read it:
#   worker   <handle> <state> <owner> <stage> <reason>
#   evidence <handle> <signal> <value>
#   anomaly  <handle> <what>
# state ∈ working | waiting-on-a-human | finished-but-unreaped | dead |
# unclassified; owner ∈ this-tower | live-peer | dead-or-unknown; reason is
# the signal that established the state. A malformed store or registry line
# is an `anomaly` line and the worker still classifies from what remains.
# Every printed value is a grammar-validated token or passes through the
# canonical echo-discipline sanitizer, so a hand-corrupted store can never
# drive a terminal or tear a consumer's parse.
#
# STORES. It reads the attention store, the registry, and the stream-json
# runtime dir the fleet already keeps under the cross-spec fleet home
# (fleet-state.sh root) — no second store, no state of its own.
#
# Usage:
#   fleet-stuck-detector.sh classify <worker> [--scope <s>] [--backend <b>]
#       [--state-dir <abs-dir>] [--death-handle <handle>] [--worktree <abs-dir>]
#       [--pane <file>] [--events <file>] [--footer-lines <n>] [--prompt-lines <n>]
#       [--tower-id <token>] [--checkout <dir>] [--session-id <uuid> | --pid <pid>]
#       Classify one worker. Flags override what the registry recorded.
#   fleet-stuck-detector.sh scan [--tower-id <token>] [--checkout <dir>]
#       [--session-id <uuid> | --pid <pid>]
#       Classify every worker the registry or the attention store knows.
#
# Exit codes: 0 classified (unclassified included — it is a valid answer);
#   2 usage error, refused hostile input, or an unreadable named input.
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling). No
# eval, no jq, no model or network call (REQ-K1.5, REQ-A1.2); every parsed
# value is data. Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me='fleet-stuck-detector'

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"
# shellcheck source=scripts/fleet-pane-vocabulary.sh
. "$script_dir/fleet-pane-vocabulary.sh"

FS="$script_dir/fleet-state.sh"
FDE="$script_dir/fleet-death-evidence.sh"
FP="$script_dir/fleet-presence.sh"
TAB=$(printf '\t')

usage() {
  cat >&2 <<'USAGE'
usage: fleet-stuck-detector.sh classify <worker> [--scope <s>] [--backend <b>] [--state-dir <abs-dir>] [--death-handle <handle>] [--worktree <abs-dir>] [--pane <file>] [--events <file>] [--footer-lines <n>] [--prompt-lines <n>] [--tower-id <token>] [--checkout <dir>] [--session-id <uuid> | --pid <pid>]
       fleet-stuck-detector.sh scan [--tower-id <token>] [--checkout <dir>] [--session-id <uuid> | --pid <pid>]
USAGE
  exit 2
}

err() {
  echo "$me: $1" >&2
}

# --- grammars (validated BEFORE any path or command use) --------------------

# The fleet field grammar (fleet-state.sh valid_field) for worker handles.
valid_field() {
  case $1 in
    "" | . | .. | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

# The registry's absolute-directory grammar (fleet-state.sh valid_state_dir).
valid_abs_dir() {
  case $1 in
    / | */../* | */.. | ../*) return 1 ;;
    /*) ;;
    *) return 1 ;;
  esac
  [ "${#1}" -le 4096 ] || return 1
  [ "$(printf '%s' "$1" | tr -d '\000-\037\177')" = "$1" ]
}

# A readable file path: absolute or relative (a pane capture is usually a
# temp file the caller just wrote), control-free, bounded.
valid_file_arg() {
  case $1 in
    "" | -*) return 1 ;;
  esac
  [ "${#1}" -le 4096 ] || return 1
  [ "$(printf '%s' "$1" | tr -d '\000-\037\177')" = "$1" ]
}

valid_backend() {
  case $1 in
    "" | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

valid_tmux_token() {
  case $1 in
    "" | -* | *[!A-Za-z0-9._@%-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

valid_pid() {
  case $1 in
    "" | 0* | *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 10 ]
}

# The registry's death-handle grammar (fleet-state.sh valid_death_handle):
# `none`, `process <pid>`, or `tmux-window <session> <window>`. A
# pseudo-evidence class (`timeout 30`) fails here, so it can never reach the
# predicate — which would refuse it anyway (REQ-A1.7).
valid_death_handle() {
  case $1 in
    none) return 0 ;;
    "process "*) valid_pid "${1#process }" ;;
    "tmux-window "*)
      vdh_rest=${1#tmux-window }
      case $vdh_rest in
        *" "*) ;;
        *) return 1 ;;
      esac
      valid_tmux_token "${vdh_rest%% *}" && valid_tmux_token "${vdh_rest#* }"
      ;;
    *) return 1 ;;
  esac
}

valid_uuid() {
  [ "${#1}" -eq 36 ] || return 1
  case $1 in
    ????????-????-????-????-????????????) ;;
    *) return 1 ;;
  esac
  vu_rest=$(printf '%s' "$1" | tr -d -- '-')
  [ "${#vu_rest}" -eq 32 ] || return 1
  case $vu_rest in
    *[!0-9a-fA-F]*) return 1 ;;
  esac
  return 0
}

# The presence surface's tower-identity grammar (fleet-presence.sh
# is_tower_id): a session UUID or the composite p<pid>.t<hash>.c<hash>.
valid_tower_id() {
  if valid_uuid "$1"; then
    return 0
  fi
  printf '%s' "$1" | grep -Eq '^p[0-9]{1,10}\.t[0-9]+\.c[0-9]+$'
}

# The registry's owner-token grammar (fleet-state.sh valid_owner), which is
# looser than the tower-id grammar on purpose: a token the store accepted
# but the presence surface would not recognize is still displayable, and
# still never live.
valid_owner_token() {
  case $1 in
    "" | . | .. | unknown-owner | -* | *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

valid_posint() {
  case $1 in
    "" | 0* | *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 6 ]
}

# --- argument parsing --------------------------------------------------------

cmd=${1:-}
case $cmd in
  classify | scan) ;;
  *) usage ;;
esac
shift

worker=""
scope=""
backend=""
state_dir=""
death_handle=""
worktree=""
pane=""
events=""
footer_lines=8
prompt_lines=24
tower_id=""
checkout=""
session_id=""
pid=""

if [ "$cmd" = classify ]; then
  worker=${1:-}
  [ -n "$worker" ] || usage
  shift
fi

need_value() {
  [ "$#" -ge 2 ] || usage
}

while [ "$#" -gt 0 ]; do
  case $1 in
    --scope)
      [ "$cmd" = classify ] || usage
      need_value "$@"
      scope=$2
      shift 2
      ;;
    --backend)
      [ "$cmd" = classify ] || usage
      need_value "$@"
      backend=$2
      shift 2
      ;;
    --state-dir)
      [ "$cmd" = classify ] || usage
      need_value "$@"
      state_dir=$2
      shift 2
      ;;
    --death-handle)
      [ "$cmd" = classify ] || usage
      need_value "$@"
      death_handle=$2
      shift 2
      ;;
    --worktree)
      [ "$cmd" = classify ] || usage
      need_value "$@"
      worktree=$2
      shift 2
      ;;
    --pane)
      [ "$cmd" = classify ] || usage
      need_value "$@"
      pane=$2
      shift 2
      ;;
    --events)
      [ "$cmd" = classify ] || usage
      need_value "$@"
      events=$2
      shift 2
      ;;
    --footer-lines)
      [ "$cmd" = classify ] || usage
      need_value "$@"
      footer_lines=$2
      shift 2
      ;;
    --prompt-lines)
      [ "$cmd" = classify ] || usage
      need_value "$@"
      prompt_lines=$2
      shift 2
      ;;
    --tower-id)
      need_value "$@"
      tower_id=$2
      shift 2
      ;;
    --checkout)
      need_value "$@"
      checkout=$2
      shift 2
      ;;
    --session-id)
      need_value "$@"
      session_id=$2
      shift 2
      ;;
    --pid)
      need_value "$@"
      pid=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

if [ "$cmd" = classify ]; then
  if ! valid_field "$worker"; then
    err "refusing malformed worker handle"
    exit 2
  fi
  if [ -n "$scope" ] && ! valid_field "$scope"; then
    err "refusing malformed scope"
    exit 2
  fi
  if [ -n "$backend" ] && ! valid_backend "$backend"; then
    err "refusing malformed backend name"
    exit 2
  fi
  if [ -n "$state_dir" ] && ! valid_abs_dir "$state_dir"; then
    err "refusing malformed --state-dir (an absolute, control-free directory)"
    exit 2
  fi
  if [ -n "$death_handle" ] && ! valid_death_handle "$death_handle"; then
    err "refusing malformed --death-handle (none | process <pid> | tmux-window <session> <window>; a timeout or heartbeat age is not evidence, REQ-A1.7)"
    exit 2
  fi
  if [ -n "$worktree" ] && ! valid_abs_dir "$worktree"; then
    err "refusing malformed --worktree (an absolute, control-free directory)"
    exit 2
  fi
  if [ -n "$pane" ]; then
    if ! valid_file_arg "$pane" || [ ! -f "$pane" ] || [ ! -r "$pane" ]; then
      err "refusing --pane: not a readable file"
      exit 2
    fi
  fi
  if [ -n "$events" ]; then
    if ! valid_file_arg "$events" || [ ! -f "$events" ] || [ ! -r "$events" ]; then
      err "refusing --events: not a readable file"
      exit 2
    fi
  fi
  if ! valid_posint "$footer_lines" || ! valid_posint "$prompt_lines"; then
    err "refusing malformed --footer-lines / --prompt-lines (a positive integer)"
    exit 2
  fi
fi
if [ -n "$tower_id" ] && ! valid_tower_id "$tower_id"; then
  err "refusing malformed --tower-id (a session UUID or p<pid>.t<hash>.c<hash>)"
  exit 2
fi
if [ -n "$session_id" ] && ! valid_uuid "$session_id"; then
  err "refusing malformed --session-id (a UUID)"
  exit 2
fi
if [ -n "$pid" ] && ! valid_pid "$pid"; then
  err "refusing malformed --pid (a positive integer, no leading zero)"
  exit 2
fi
if [ -n "$session_id" ] && [ -n "$pid" ]; then
  err "--session-id and --pid are exclusive"
  exit 2
fi
if [ -n "$checkout" ] && ! valid_abs_dir "$checkout"; then
  err "refusing malformed --checkout (an absolute, control-free directory)"
  exit 2
fi

# --- the fleet home ----------------------------------------------------------

root=""
if [ -x "$FS" ]; then
  root=$("$FS" root 2>/dev/null) || root=""
fi
registry_file=""
store_file=""
if [ -n "$root" ]; then
  registry_file="$root/registry"
  store_file="$root/attention/state"
fi

# --- this tower's identity (the attribution axis's own side) -----------------

# The env-carried inputs mirror fleet-register.sh's resolution order: an
# explicit flag, the already-resolved token, then the identity inputs.
if [ -z "$session_id" ] && [ -z "$pid" ]; then
  if [ -n "${PLANWRIGHT_TOWER_SESSION_ID:-}" ] && valid_uuid "${PLANWRIGHT_TOWER_SESSION_ID:-}"; then
    session_id=$PLANWRIGHT_TOWER_SESSION_ID
  elif [ -n "${PLANWRIGHT_TOWER_PID:-}" ] && valid_pid "${PLANWRIGHT_TOWER_PID:-}"; then
    pid=$PLANWRIGHT_TOWER_PID
  fi
fi
if [ -z "$checkout" ]; then
  if [ -n "${PLANWRIGHT_TOWER_CHECKOUT:-}" ] && valid_abs_dir "${PLANWRIGHT_TOWER_CHECKOUT:-}"; then
    checkout=$PLANWRIGHT_TOWER_CHECKOUT
  else
    checkout=$(git rev-parse --show-toplevel 2>/dev/null) || checkout=""
    if [ -z "$checkout" ]; then
      checkout=$(pwd -P 2>/dev/null) || checkout=""
    fi
    valid_abs_dir "$checkout" || checkout=""
  fi
fi

# presence_identity_args — the identity flag pair the presence surface needs,
# or nothing when no identity input is available. A bare UUID tower id doubles
# as a session id (that is what it is), so a tower that knows only its token
# can still ask the surface.
presence_id_flag=""
presence_id_value=""
if [ -n "$session_id" ]; then
  presence_id_flag=--session-id
  presence_id_value=$session_id
elif [ -n "$pid" ]; then
  presence_id_flag=--pid
  presence_id_value=$pid
fi

self_tower=""
if [ -n "$tower_id" ]; then
  self_tower=$tower_id
elif [ -n "${PLANWRIGHT_TOWER_ID:-}" ] && valid_tower_id "${PLANWRIGHT_TOWER_ID:-}"; then
  self_tower=$PLANWRIGHT_TOWER_ID
elif [ -n "$presence_id_flag" ] && [ -n "$checkout" ] && [ -x "$FP" ]; then
  self_tower=$("$FP" identity --checkout "$checkout" "$presence_id_flag" "$presence_id_value" 2>/dev/null) || self_tower=""
  valid_tower_id "$self_tower" || self_tower=""
fi
if [ -z "$presence_id_flag" ] && [ -n "$self_tower" ] && valid_uuid "$self_tower"; then
  presence_id_flag=--session-id
  presence_id_value=$self_tower
fi

# --- output helpers ----------------------------------------------------------

# Every value crosses the sanitizer: the handle and the enumerated words are
# grammar-validated already, so this is belt-and-suspenders for the one
# loose-charset field (a path) and for any future caller.
emit_evidence() {
  printf 'evidence\t%s\t%s\t%s\n' "$cur_worker" "$1" "$(sanitize_printable "$2" "-")"
}
emit_anomaly() {
  printf 'anomaly\t%s\t%s\n' "$cur_worker" "$1"
}

# git_ro <dir> <args...> — a read-only git query in a directory the detector
# did not choose: the worktree may be named by a worker-authored init event,
# so the target repository's own config is untrusted. No optional index lock
# (someone else's worktree, possibly mid-command) and no fsmonitor, the one
# config-driven command `status` would otherwise execute.
git_ro() {
  gr_dir=$1
  shift
  GIT_OPTIONAL_LOCKS=0 git -C "$gr_dir" -c core.fsmonitor=false "$@"
}

# --- per-worker classification -----------------------------------------------

# classify_one <worker> — runs the whole signal walk for one handle and
# prints its worker row plus evidence. Reads the registry and the store for
# the handle; the classify-only overrides (state dir, death handle, worktree,
# pane, events) are the globals set from argv, empty under `scan`.
classify_one() {
  cur_worker=$1

  # 1. The dispatch record (Task 3): last record for the worker wins. Seven
  #    columns is the current shape; three is the pre-owner shape, still
  #    parseable; anything else is a torn or hand-edited line.
  reg_status=absent
  reg_owner=""
  reg_backend=""
  reg_state_dir=""
  reg_handle=""
  if [ -n "$registry_file" ] && [ -f "$registry_file" ] && [ -r "$registry_file" ]; then
    reg_line=$(awk -F'\t' -v w="$cur_worker" '$2 == w { l = $0 } END { print l }' "$registry_file" 2>/dev/null) || reg_line=""
    if [ -n "$reg_line" ]; then
      reg_nf=$(printf '%s\n' "$reg_line" | awk -F'\t' '{ print NF }')
      case $reg_nf in
        7)
          reg_owner=$(printf '%s\n' "$reg_line" | awk -F'\t' '{ print $4 }')
          reg_backend=$(printf '%s\n' "$reg_line" | awk -F'\t' '{ print $5 }')
          reg_state_dir=$(printf '%s\n' "$reg_line" | awk -F'\t' '{ print $6 }')
          reg_handle=$(printf '%s\n' "$reg_line" | awk -F'\t' '{ print $7 }')
          reg_status=present
          # An unsupplied optional field is `-`; a field that fails its own
          # grammar is corruption, and the record is reported rather than
          # half-trusted (the store refuses such a field at write).
          [ "$reg_owner" = - ] && reg_owner=""
          [ "$reg_backend" = - ] && reg_backend=""
          [ "$reg_state_dir" = - ] && reg_state_dir=""
          [ "$reg_handle" = - ] && reg_handle=""
          if { [ -n "$reg_owner" ] && ! valid_owner_token "$reg_owner"; } \
            || { [ -n "$reg_backend" ] && ! valid_backend "$reg_backend"; } \
            || { [ -n "$reg_state_dir" ] && ! valid_abs_dir "$reg_state_dir"; } \
            || { [ -n "$reg_handle" ] && ! valid_death_handle "$reg_handle"; }; then
            reg_status=malformed
            reg_owner=""
            reg_backend=""
            reg_state_dir=""
            reg_handle=""
          fi
          ;;
        3) reg_status=present ;;
        *) reg_status=malformed ;;
      esac
    fi
  elif [ -n "$registry_file" ] && [ -e "$registry_file" ]; then
    reg_status=unreadable
  fi
  [ "$reg_status" = malformed ] && emit_anomaly registry-malformed

  eff_backend=${backend:-$reg_backend}
  eff_state_dir=${state_dir:-$reg_state_dir}
  eff_handle=${death_handle:-$reg_handle}
  owner_token=$reg_owner

  # 2. The attention store row (the hook-push surface). Eight shipped fields
  #    plus up to three additive ones; the state word and the heartbeat must
  #    parse, and no field may carry a control byte.
  attn_status=absent
  attn_state=""
  attn_reason=""
  if [ -n "$store_file" ] && [ -f "$store_file" ] && [ -r "$store_file" ]; then
    attn_line=$(awk -F'\t' -v w="$cur_worker" '$1 == w { l = $0 } END { print l }' "$store_file" 2>/dev/null) || attn_line=""
    if [ -n "$attn_line" ]; then
      attn_nf=$(printf '%s\n' "$attn_line" | awk -F'\t' '{ print NF }')
      attn_state=$(printf '%s\n' "$attn_line" | awk -F'\t' '{ print $3 }')
      attn_ts=$(printf '%s\n' "$attn_line" | awk -F'\t' '{ print $4 }')
      attn_reason=$(printf '%s\n' "$attn_line" | awk -F'\t' '{ print $9 }')
      attn_clean=$(printf '%s' "$attn_line" | tr -d '\000-\010\013-\037\177')
      if [ "$attn_nf" -lt 8 ] || [ "$attn_nf" -gt 11 ] || [ "$attn_clean" != "$attn_line" ]; then
        attn_status=malformed
      else
        case $attn_state in
          working | idle | hung | ended | awaiting-input | pr-ready | merged | done) ;;
          *) attn_status=malformed ;;
        esac
        case $attn_ts in
          "" | *[!0-9]*) attn_status=malformed ;;
        esac
        if [ "$attn_status" != malformed ] && [ -n "$attn_reason" ] && ! valid_field "$attn_reason"; then
          attn_status=malformed
        fi
        [ "$attn_status" = malformed ] || attn_status=present
      fi
      if [ "$attn_status" = malformed ]; then
        attn_state=""
        attn_reason=""
      fi
    fi
  elif [ -n "$store_file" ] && [ -e "$store_file" ]; then
    attn_status=unreadable
  fi
  [ "$attn_status" = malformed ] && emit_anomaly attention-malformed

  # 3. The runtime dir: the registry's state dir, else the stream-json
  #    supervisor's own layout under the fleet home for a worker that
  #    predates registration.
  runtime_dir=$eff_state_dir
  if [ -z "$runtime_dir" ] && [ -n "$root" ] && [ -d "$root/streamjson/$cur_worker" ]; then
    runtime_dir="$root/streamjson/$cur_worker"
  fi

  # 4. Completion signals, each its own record shape: the stream-json
  #    supervisor's `result` (result <subtype> <epoch> | exit <rc> <epoch>),
  #    the headless runner's `exit` (<rc> <epoch>), the SessionEnd push.
  completion=absent
  if [ -n "$runtime_dir" ] && [ -f "$runtime_dir/result" ] && [ -r "$runtime_dir/result" ]; then
    c_kind=$(awk -F'\t' 'NR == 1 { print $1 }' "$runtime_dir/result" 2>/dev/null)
    c_val=$(awk -F'\t' 'NR == 1 { print $2 }' "$runtime_dir/result" 2>/dev/null)
    case $c_kind in
      result | exit)
        case $c_val in
          "" | *[!A-Za-z0-9_-]*) c_val=unknown ;;
        esac
        completion="$c_kind=$(printf '%s' "$c_val" | cut -c1-32)"
        ;;
      *) emit_anomaly result-record-malformed ;;
    esac
  elif [ -n "$runtime_dir" ] && [ -f "$runtime_dir/exit" ] && [ -r "$runtime_dir/exit" ]; then
    c_val=$(awk 'NR == 1 { print $1 }' "$runtime_dir/exit" 2>/dev/null)
    case $c_val in
      "" | *[!0-9]*) c_val=unknown ;;
    esac
    completion="exit=$c_val"
  elif [ "$attn_state" = ended ]; then
    completion='session-ended'
  fi

  # 5. A pending control_request in the stream-json journal: a positive
  #    receipt of a prompt the supervisor is holding for a human.
  journal_pending=0
  if [ -n "$runtime_dir" ] && [ -f "$runtime_dir/journal" ] && [ -r "$runtime_dir/journal" ]; then
    journal_pending=$(awk -F'\t' '$4 == "pending" { n++ } END { print n + 0 }' "$runtime_dir/journal" 2>/dev/null) || journal_pending=0
    case $journal_pending in
      "" | *[!0-9]*) journal_pending=0 ;;
    esac
  fi

  # 6. Death evidence (REQ-C1.5): the predicate's own verdict word, and only
  #    for a handle it accepts. `none` is a rung that spawned no process; it
  #    is never passed through (the predicate would refuse it, exit 2).
  death=absent
  if [ -n "$eff_handle" ]; then
    if [ "$eff_handle" = none ]; then
      death=none
    else
      # The handle grammar was validated; word-split it into the predicate's
      # argv form.
      # shellcheck disable=SC2086
      set -- $eff_handle
      d_rc=0
      d_out=$("$FDE" "$@" 2>/dev/null) || d_rc=$?
      case "$d_rc:$d_out" in
        0:dead) death=dead ;;
        1:alive) death=alive ;;
        *) death=unknown ;;
      esac
    fi
  fi

  # 7. The event stream (REQ-C1.7): the stage, plus the init event's cwd as a
  #    worktree hint. Bounded read, escape-agnostic substring matching — a
  #    cheap derivation, documented as such; the result is data, never code.
  events_file=$events
  if [ -z "$events_file" ] && [ -n "$runtime_dir" ] && [ -f "$runtime_dir/events.jsonl" ] && [ -r "$runtime_dir/events.jsonl" ]; then
    events_file="$runtime_dir/events.jsonl"
  fi
  stage=-
  stage_source=absent
  events_cwd=""
  if [ -n "$events_file" ]; then
    stage_source=events
    ev_parsed=$(tail -c 1048576 "$events_file" 2>/dev/null | awk '
      /"type":"result"/ { stage = "completed"; next }
      /"type":"tool_use"/ {
        if ($0 ~ /"name":"Skill"/ && ($0 ~ /polish/ || $0 ~ /self-review/)) stage = "converging"
        else if ($0 ~ /"name":"Bash"/ && $0 ~ /git push/) stage = "handing-off"
        else stage = "implementing"
        next
      }
      /"type":"system"/ && /"subtype":"init"/ {
        if (stage == "") stage = "launched"
        if (cwd == "" && match($0, /"cwd":"[^"]*"/)) {
          cwd = substr($0, RSTART + 7, RLENGTH - 8)
        }
      }
      END {
        if (stage == "") stage = "launched"
        print stage "\t" cwd
      }') || ev_parsed=""
    stage=${ev_parsed%%"$TAB"*}
    events_cwd=${ev_parsed#*"$TAB"}
    case $stage in
      launched | implementing | converging | handing-off | completed) ;;
      *)
        stage=-
        stage_source=absent
        ;;
    esac
    # A JSON-escaped path (a backslash) is not trusted as a worktree hint.
    case $events_cwd in
      *\\*) events_cwd="" ;;
    esac
    valid_abs_dir "$events_cwd" || events_cwd=""
  fi

  # 8. The worktree and the unlanded check (REQ-C1.4): local git state only.
  eff_worktree=$worktree
  if [ -z "$eff_worktree" ] && [ -n "$eff_state_dir" ] && [ -d "$eff_state_dir" ] \
    && [ "$(git_ro "$eff_state_dir" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
    eff_worktree=$eff_state_dir
  fi
  if [ -z "$eff_worktree" ] && [ -n "$events_cwd" ] && [ -d "$events_cwd" ] \
    && [ "$(git_ro "$events_cwd" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
    eff_worktree=$events_cwd
  fi
  tree=unverifiable
  unpushed=unverifiable
  commits=unverifiable
  if [ -n "$eff_worktree" ] && [ -d "$eff_worktree" ]; then
    g_status=$(git_ro "$eff_worktree" status --porcelain 2>/dev/null | head -n 1) && g_ok=1 || g_ok=0
    if [ "$g_ok" = 1 ] && git_ro "$eff_worktree" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      if [ -n "$g_status" ]; then
        tree=dirty
      else
        tree=clean
      fi
      # Commits absent from the remote-tracking ref: counted against the
      # upstream when one is set; otherwise against every remote-tracking
      # ref the clone has (a branch never pushed is unpushed in full); a
      # clone with no remote-tracking ref at all cannot verify.
      if git_ro "$eff_worktree" rev-parse --verify --quiet '@{u}' >/dev/null 2>&1; then
        unpushed=$(git_ro "$eff_worktree" rev-list --count '@{u}..HEAD' 2>/dev/null) || unpushed=unverifiable
      elif [ -n "$(git_ro "$eff_worktree" branch -r 2>/dev/null | head -n 1)" ]; then
        unpushed=$(git_ro "$eff_worktree" rev-list --count HEAD --not --remotes 2>/dev/null) || unpushed=unverifiable
      fi
      case $unpushed in
        "" | *[!0-9]*) unpushed=unverifiable ;;
      esac
      # The unit branch's own commits: since it diverged from the default
      # branch, the first of these refs that resolves.
      for base in origin/HEAD origin/main origin/master main master; do
        if git_ro "$eff_worktree" rev-parse --verify --quiet "$base" >/dev/null 2>&1; then
          commits=$(git_ro "$eff_worktree" rev-list --count "$base..HEAD" 2>/dev/null) || commits=unverifiable
          break
        fi
      done
      case $commits in
        "" | *[!0-9]*) commits=unverifiable ;;
      esac
    fi
  fi

  # 9. The captured pane, when the caller has one (the tmux rung): a
  #    permission-prompt signature in a bounded window is the positive
  #    blocked signal; a busy marker in the footer is the positive working
  #    signal; an at-prompt anchor alone is a turn that ended.
  pane_state=absent
  if [ -n "$pane" ]; then
    pane_prompt=$(tail -n "$prompt_lines" "$pane" 2>/dev/null | tr -d '\000-\010\013-\037\177') || pane_prompt=""
    pane_footer=$(tail -n "$footer_lines" "$pane" 2>/dev/null | tr -d '\000-\010\013-\037\177') || pane_footer=""
    if permission_prompt_present "$pane_prompt"; then
      pane_state='permission-prompt'
    else
      case $(raw_classify "$pane_footer") in
        busy) pane_state=busy ;;
        idle) pane_state=idle-prompt ;;
        *) pane_state=indeterminate ;;
      esac
    fi
  fi

  # 10. Owner attribution (REQ-C1.6).
  owner='dead-or-unknown'
  owner_ev=absent
  if [ -n "$owner_token" ]; then
    if [ -n "$self_tower" ] && [ "$owner_token" = "$self_tower" ]; then
      owner='this-tower'
      owner_ev=self
    elif [ -n "$presence_id_flag" ] && [ -n "$checkout" ] && [ -x "$FP" ] && valid_tower_id "$owner_token"; then
      p_rc=0
      p_out=$("$FP" liveness --checkout "$checkout" "$presence_id_flag" "$presence_id_value" "$owner_token" 2>/dev/null) || p_rc=$?
      if [ "$p_rc" != 0 ]; then
        owner_ev='presence-unavailable'
      else
        p_tag=$(printf '%s\n' "$p_out" | awk -F'\t' 'NR == 1 { print $1 }')
        p_verdict=$(printf '%s\n' "$p_out" | awk -F'\t' 'NR == 1 { print $3 }')
        case "$p_tag:$p_verdict" in
          tower:self)
            owner='this-tower'
            owner_ev=self
            ;;
          tower:live)
            owner='live-peer'
            owner_ev=live
            ;;
          tower:dead | tower:unknown | tower:ambiguous) owner_ev=$p_verdict ;;
          no-record:*) owner_ev=no-record ;;
          unreadable:*) owner_ev=unreadable ;;
          *) owner_ev=presence-unavailable ;;
        esac
      fi
    elif ! valid_tower_id "$owner_token"; then
      owner_ev=unrecognized
    else
      owner_ev='no-identity'
    fi
  fi

  # 11. The state, by precedence.
  state=unclassified
  reason='no-signal'
  if [ "$death" = dead ]; then
    state=dead
    reason='death-evidence'
  elif [ "$attn_state" = awaiting-input ]; then
    state='waiting-on-a-human'
    reason='hook-push'
  elif [ "$journal_pending" -gt 0 ]; then
    state='waiting-on-a-human'
    reason='journal-pending'
  elif [ "$pane_state" = permission-prompt ]; then
    state='waiting-on-a-human'
    reason='prompt-signature'
  elif [ "$completion" != absent ]; then
    if [ "$tree" = dirty ] || { [ "$unpushed" != unverifiable ] && [ "$unpushed" -gt 0 ]; }; then
      state=unclassified
      reason='completion-unlanded'
    else
      state='finished-but-unreaped'
      case $completion in
        session-ended) reason=session-ended ;;
        *) reason="completion:$completion" ;;
      esac
    fi
  elif [ "$attn_state" = working ]; then
    state=working
    reason='attention-working'
  elif [ "$pane_state" = busy ]; then
    state=working
    reason='pane-busy'
  elif [ -n "$runtime_dir" ] && [ -f "$runtime_dir/supervisor.pid" ] && [ -f "$runtime_dir/worker.pid" ] && [ "$death" = alive ]; then
    state=working
    reason='runtime-running'
  elif [ "$attn_state" = hung ]; then
    reason='stop-failure'
  elif [ "$attn_state" = idle ] || [ "$pane_state" = idle-prompt ]; then
    reason='turn-ended'
  fi

  printf 'worker\t%s\t%s\t%s\t%s\t%s\n' "$cur_worker" "$state" "$owner" "$stage" "$reason"
  emit_evidence registry "$reg_status"
  emit_evidence backend "${eff_backend:--}"
  emit_evidence owner-token "${owner_token:--}"
  emit_evidence owner "$owner_ev"
  emit_evidence attention "${attn_state:-$attn_status}"
  emit_evidence attention-reason "${attn_reason:--}"
  emit_evidence death "$death"
  emit_evidence completion "$completion"
  emit_evidence journal-pending "$journal_pending"
  emit_evidence worktree "${eff_worktree:--}"
  emit_evidence tree "$tree"
  emit_evidence unpushed "$unpushed"
  emit_evidence commits "$commits"
  emit_evidence pane "$pane_state"
  emit_evidence stage-source "$stage_source"
}

if [ "$cmd" = classify ]; then
  classify_one "$worker"
  exit 0
fi

# scan: the union of registry handles and attention rows, each classified
# once, in a deterministic order. A handle that fails the field grammar is a
# torn line, reported once and skipped — it could not name a store row or a
# runtime dir anyway.
handles=""
if [ -n "$registry_file" ] && [ -f "$registry_file" ] && [ -r "$registry_file" ]; then
  handles=$(awk -F'\t' 'NF >= 2 { print $2 }' "$registry_file" 2>/dev/null)
fi
if [ -n "$store_file" ] && [ -f "$store_file" ] && [ -r "$store_file" ]; then
  handles=$(
    printf '%s\n' "$handles"
    awk -F'\t' 'NF >= 1 { print $1 }' "$store_file" 2>/dev/null
  )
fi
handles=$(printf '%s\n' "$handles" | awk 'NF { print }' | sort -u)
while IFS= read -r h; do
  [ -n "$h" ] || continue
  if ! valid_field "$h"; then
    cur_worker="?"
    emit_anomaly handle-malformed
    continue
  fi
  classify_one "$h"
done <<HANDLES
$handles
HANDLES
exit 0
