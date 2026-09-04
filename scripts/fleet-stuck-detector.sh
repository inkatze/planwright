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
#                           decide) that no answer has claimed yet — or a
#                           pending control_request in the stream-json journal
#                           of a session that has not ended, or a POSITIVELY
#                           MATCHED permission-prompt signature in a captured
#                           pane (REQ-C1.2, obs:4c25e743). Never elapsed time.
#   finished-but-unreaped   a successful session-ended signal — the attention
#                           store's `ended` row (SessionEnd), a stream-json
#                           `result success` record, a zero `exit` record —
#                           while the worker is not positively dead (REQ-C1.3).
#                           A completion whose work is demonstrably unlanded
#                           (an uncommitted tree, commits absent from the
#                           remote-tracking ref) is NOT finished (REQ-C1.4,
#                           obs:cc13d432): it reports `unclassified` with
#                           reason `completion-unlanded`, so a positive-looking
#                           status can never hide stranded work. A session that
#                           ended WITHOUT completing — a non-zero exit, a
#                           non-success result subtype — is `unclassified`
#                           with reason `completion-failed`, never finished
#                           (the supervisor's own status renders it `ended`,
#                           never `completed`, and this detector agrees).
#   working                 a pushed working row, a busy marker in the pane
#                           footer (a running-turn spinner), or both stream-json
#                           runtime pidfiles present with the supervisor
#                           positively alive and no result yet.
# Precedence, highest first: dead, waiting-on-a-human, a completion signal,
# working. Death evidence outranks a stale push; a queued human decision
# outranks a captured result; a captured result outranks a stale working row.
#
# UNCLASSIFIED is the honest fifth word, never a default state: a worker with
# no positive signal (`no-signal`), a turn that ended with nothing further
# pushed (`turn-ended`), a fork a human answered whose resume has not pushed
# yet (`fork-answered`), a StopFailure push (`stop-failure`), and the two
# completion cases above. A consumer treats it as "leave alone and surface".
#
# THE UNLANDED CHECK reads LOCAL git state only (REQ-C1.4), through the
# plumbing that hashes no file content (`ls-files`, `diff-index --cached`)
# so the target repository's own config can drive no command, and the commit
# count against the remote-tracking ref (the upstream when set, else every
# remote-tracking ref). No fetch, no `gh`, no per-worker forge query — it is
# cheap and works offline; whether a unit owes a PR is not inferred here.
# The worktree comes ONLY from --worktree or from a registry state dir that
# is itself a git toplevel (the tmux rung records the worktree there): a
# path the worker itself authored — the event stream's `cwd` — is never
# used, because a worker could point the check at any clean repository and
# launder its own stranded work. Unresolvable degrades to `unverifiable`,
# which is not "demonstrably unlanded". The check runs only when a completion
# signal is present; otherwise its columns read `-`.
#
# OWNER ATTRIBUTION (REQ-C1.6, D-4). Every state carries one of three words,
# resolved from the dispatch record's owner token and the presence surface:
#   this-tower       the token equals this tower's identity
#   live-peer        fleet-presence.sh liveness reports the token live
#   dead-or-unknown  everything else — an absent token, a dead / unknown /
#                    ambiguous / unreadable / unrecorded tower, a surface that
#                    cannot be read, or no identity to ask with. The word
#                    means "not established live": a consumer that acts on
#                    it still owes positive death evidence of its own
#                    (REQ-D1.4). Degradation always lands here, never on
#                    this-tower: the same signal means opposite things
#                    depending on who owns the worker, and a reaper must never
#                    mistake a peer's worker for ours.
# This tower's identity resolves in the same order fleet-register.sh uses to
# stamp the owner column, so the two agree: --tower-id; else an explicit
# --session-id / --pid resolved through fleet-presence.sh identity; else
# $PLANWRIGHT_TOWER_ID; else $PLANWRIGHT_TOWER_SESSION_ID / $PLANWRIGHT_TOWER_PID
# resolved the same way. The checkout feeding the composite identity is
# --checkout, else $PLANWRIGHT_TOWER_CHECKOUT, else the cwd's git toplevel,
# else the cwd. Tokens are compared under the registry's own owner grammar;
# only a token in the presence surface's identity shape is ever handed to
# the surface.
#
# STAGE (REQ-C1.7) rides a separate axis from liveness, named `stage` so
# `phase` stays the resource-class sense: derived cheaply from the event
# stream's most recent stage-bearing event — `launched` (init only),
# `implementing` (a tool use), `converging` (a review-skill invocation),
# `handing-off` (a push in a Bash tool use), `completed` (a result event) —
# and `-` where no stream exists (`stage-source absent`) or the stream holds
# no such event yet.
#
# OUTPUT (REQ-C1.8), tab-separated, one grammar, no LLM needed to read it:
#   worker   <handle> <state> <owner> <stage> <reason>
#   evidence <handle> <signal> <value>
#   anomaly  <handle> <what>
# state ∈ working | waiting-on-a-human | finished-but-unreaped | dead |
# unclassified; owner ∈ this-tower | live-peer | dead-or-unknown; reason is
# the signal that established the state. The evidence signals, in emission
# order: registry (present|absent|unreadable|malformed), backend, scope,
# owner-token, owner-evidence (self|live|dead|unknown|ambiguous|no-record|
# unreadable|presence-unavailable|unrecognized|no-identity|absent),
# attention (the store's state word, or -), attention-status
# (present|absent|unreadable|malformed), attention-reason, death
# (dead|alive|unknown|none|absent), completion (result=<subtype>|exit=<rc>|
# session-ended|absent), journal-pending, worktree, tree (clean|dirty|
# unverifiable|-), unpushed (<n>|unverifiable|-), commits (<n>|unverifiable),
# pane (permission-prompt|busy|idle-prompt|indeterminate|absent),
# stage-source (events|absent). Anomaly words: registry-malformed,
# attention-malformed, result-record-malformed, result-unreadable,
# exit-unreadable, journal-unreadable, pane-unreadable,
# death-predicate-missing, handle-malformed, registry-unreadable,
# store-unreadable. Anomalies follow the worker's evidence rows. Every printed
# value is a grammar-validated token or passes the canonical echo-discipline
# sanitizer, so a hand-corrupted store can never drive a terminal or tear a
# consumer's parse.
#
# STORES. It reads the attention store, the registry, and the stream-json
# runtime dir the fleet already keeps under the cross-spec fleet home
# (fleet-state.sh root) — no second store, no state of its own. `scan` reads
# each store once and classifies every worker from that one snapshot, and
# asks the presence surface once per distinct owner token.
#
# Usage:
#   fleet-stuck-detector.sh classify <worker> [--backend <b>]
#       [--state-dir <abs-dir>] [--death-handle <handle>] [--worktree <abs-dir>]
#       [--pane <file>] [--events <file>] [--footer-lines <n>] [--prompt-lines <n>]
#       [--tower-id <token>] [--checkout <dir>] [--session-id <uuid> | --pid <pid>]
#       Classify one worker. Flags override what the registry recorded.
#   fleet-stuck-detector.sh scan [--tower-id <token>] [--checkout <dir>]
#       [--session-id <uuid> | --pid <pid>]
#       Classify every worker the registry or the attention store knows. A
#       periodic sweep uses this form (or passes --tower-id / exports
#       PLANWRIGHT_TOWER_ID), so the identity resolution is paid once.
#
# Exit codes: 0 classified (unclassified included — it is a valid answer);
#   2 usage error, refused hostile input, an unreadable named input, or an
#   unresolvable fleet home.
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling). No
# eval, no jq, no model or network call (REQ-K1.5, REQ-A1.2); every parsed
# value is data. Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me='fleet-stuck-detector'

err() {
  echo "$me: $1" >&2
}

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

for helper in echo-safety.sh fleet-pane-vocabulary.sh; do
  if [ ! -r "$script_dir/$helper" ]; then
    err "required helper $script_dir/$helper missing or not readable"
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"
# shellcheck source=scripts/fleet-pane-vocabulary.sh
. "$script_dir/fleet-pane-vocabulary.sh"

FS="$script_dir/fleet-state.sh"
FDE="$script_dir/fleet-death-evidence.sh"
FP="$script_dir/fleet-presence.sh"
TAB=$(printf '\t')
NL='
'

usage() {
  cat >&2 <<'USAGE'
usage: fleet-stuck-detector.sh classify <worker> [--backend <b>] [--state-dir <abs-dir>] [--death-handle <handle>] [--worktree <abs-dir>] [--pane <file>] [--events <file>] [--footer-lines <n>] [--prompt-lines <n>] [--tower-id <token>] [--checkout <dir>] [--session-id <uuid> | --pid <pid>]
       fleet-stuck-detector.sh scan [--tower-id <token>] [--checkout <dir>] [--session-id <uuid> | --pid <pid>]
USAGE
  exit 2
}

# --- grammars (validated BEFORE any path or command use) --------------------

# The fleet field grammar (fleet-state.sh valid_field) for worker handles.
valid_field() {
  case $1 in
    "" | . | .. | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

# Control-free: no C0 byte and no DEL, under the pinned C locale.
control_free() {
  case $1 in
    *[[:cntrl:]]*) return 1 ;;
  esac
  return 0
}

# fleet-state.sh valid_state_dir, generalized to the three directory flags
# (--state-dir, --worktree, --checkout): absolute, no `..` segment, bounded,
# control-free.
valid_abs_dir() {
  case $1 in
    / | */../* | */.. | ../*) return 1 ;;
    /*) ;;
    *) return 1 ;;
  esac
  [ "${#1}" -le 4096 ] || return 1
  control_free "$1"
}

# A readable file path: absolute or relative (a pane capture is usually a
# temp file the caller just wrote), control-free, bounded.
valid_file_arg() {
  case $1 in
    "" | -*) return 1 ;;
  esac
  [ "${#1}" -le 4096 ] || return 1
  control_free "$1"
}

# The attention store's free-text grammar (fleet-attention.sh valid_text) for
# the additive park reason: printable, at most 512 bytes.
valid_text() {
  [ -n "$1" ] || return 1
  [ "${#1}" -le 512 ] || return 1
  control_free "$1"
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
  case $1 in
    *[!0-9a-fA-F-]*) return 1 ;;
  esac
  return 0
}

# The presence surface's tower-identity grammar (fleet-presence.sh
# is_tower_id): a session UUID or the composite p<pid>.t<hash>.c<hash>.
valid_tower_id() {
  if valid_uuid "$1"; then
    return 0
  fi
  case $1 in
    p*.t*.c*) ;;
    *) return 1 ;;
  esac
  vti_p=${1#p}
  vti_p=${vti_p%%.*}
  vti_rest=${1#p*.t}
  vti_t=${vti_rest%%.*}
  vti_c=${vti_rest#*.c}
  valid_pid "$vti_p" || return 1
  case $vti_t in
    "" | *[!0-9]*) return 1 ;;
  esac
  case $vti_c in
    "" | *[!0-9]*) return 1 ;;
  esac
  return 0
}

# The registry's owner-token grammar (fleet-state.sh valid_owner): a charset,
# deliberately looser than the tower-id shape, so a token the store accepted
# is comparable for equality even when the surface would not recognize it.
valid_owner() {
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

# need_value <argv...> — a flag takes exactly one NON-EMPTY value: an empty
# value would silently read as "flag not given" and, for --tower-id, fall
# through to the ambient token — the one direction attribution must never
# degrade in.
need_value() {
  [ "$#" -ge 2 ] || usage
  [ -n "$2" ] || usage
}

classify_only() {
  [ "$cmd" = classify ] || usage
}

while [ "$#" -gt 0 ]; do
  case $1 in
    --backend)
      classify_only
      need_value "$@"
      backend=$2
      shift 2
      ;;
    --state-dir)
      classify_only
      need_value "$@"
      state_dir=$2
      shift 2
      ;;
    --death-handle)
      classify_only
      need_value "$@"
      death_handle=$2
      shift 2
      ;;
    --worktree)
      classify_only
      need_value "$@"
      worktree=$2
      shift 2
      ;;
    --pane)
      classify_only
      need_value "$@"
      pane=$2
      shift 2
      ;;
    --events)
      classify_only
      need_value "$@"
      events=$2
      shift 2
      ;;
    --footer-lines)
      classify_only
      need_value "$@"
      footer_lines=$2
      shift 2
      ;;
    --prompt-lines)
      classify_only
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
if [ -n "$tower_id" ] && ! valid_owner "$tower_id"; then
  err "refusing malformed --tower-id (the registry's owner-token grammar)"
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

# --- the fleet home, read once -----------------------------------------------

if [ ! -x "$FS" ]; then
  err "cannot resolve the fleet home: $FS missing or not executable"
  exit 2
fi
root=$("$FS" root 2>/dev/null) || {
  err "cannot resolve the fleet home (fleet-state.sh root failed)"
  exit 2
}
registry_file="$root/registry"
store_file="$root/attention/state"

# One snapshot per run: every worker is classified from the same bytes, so a
# scan never mixes store versions across workers. Readers are lock-free by
# design (the writers rename atomically).
registry_status=absent
registry_data=""
if [ -f "$registry_file" ]; then
  if registry_data=$(cat "$registry_file" 2>/dev/null); then
    registry_status=present
  else
    registry_status=unreadable
  fi
elif [ -e "$registry_file" ]; then
  registry_status=unreadable
fi
store_status=absent
store_data=""
if [ -f "$store_file" ]; then
  if store_data=$(cat "$store_file" 2>/dev/null); then
    store_status=present
  else
    store_status=unreadable
  fi
elif [ -e "$store_file" ]; then
  store_status=unreadable
fi

# --- this tower's identity (the attribution axis's own side) -----------------

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

# presence_id_flag / presence_id_value — the identity flag pair the presence
# surface needs, or nothing when no identity input is available. A bare UUID
# tower id doubles as a session id (that is what it is), so a tower that
# knows only its token can still ask the surface.
presence_id_flag=""
presence_id_value=""
explicit_identity=0
if [ -n "$session_id" ]; then
  presence_id_flag=--session-id
  presence_id_value=$session_id
  explicit_identity=1
elif [ -n "$pid" ]; then
  presence_id_flag=--pid
  presence_id_value=$pid
  explicit_identity=1
elif [ -n "${PLANWRIGHT_TOWER_SESSION_ID:-}" ] && valid_uuid "${PLANWRIGHT_TOWER_SESSION_ID:-}"; then
  presence_id_flag=--session-id
  presence_id_value=$PLANWRIGHT_TOWER_SESSION_ID
elif [ -n "${PLANWRIGHT_TOWER_PID:-}" ] && valid_pid "${PLANWRIGHT_TOWER_PID:-}"; then
  presence_id_flag=--pid
  presence_id_value=$PLANWRIGHT_TOWER_PID
fi

presence_identity() {
  [ -n "$presence_id_flag" ] && [ -n "$checkout" ] && [ -x "$FP" ] || return 1
  pi_v=$("$FP" identity --checkout "$checkout" "$presence_id_flag" "$presence_id_value" 2>/dev/null) || return 1
  valid_tower_id "$pi_v" || return 1
  printf '%s\n' "$pi_v"
}

self_tower=""
if [ -n "$tower_id" ]; then
  self_tower=$tower_id
elif [ "$explicit_identity" = 1 ]; then
  self_tower=$(presence_identity) || self_tower=""
fi
if [ -z "$self_tower" ] && [ -n "${PLANWRIGHT_TOWER_ID:-}" ] && valid_owner "${PLANWRIGHT_TOWER_ID:-}"; then
  self_tower=$PLANWRIGHT_TOWER_ID
fi
if [ -z "$self_tower" ] && [ "$explicit_identity" = 0 ]; then
  self_tower=$(presence_identity) || self_tower=""
fi
if [ -z "$presence_id_flag" ] && [ -n "$self_tower" ] && valid_uuid "$self_tower"; then
  presence_id_flag=--session-id
  presence_id_value=$self_tower
fi

# --- helpers -----------------------------------------------------------------

# last_record <data> <column> <handle> — the last line of <data> whose tab
# column <column> equals <handle>, compared as STRINGS: awk compares two
# numeric-looking operands numerically, and the handle grammar admits
# all-numeric handles, so `100` would otherwise match `1e2` (the
# fleet-attention.sh discipline). Printed one FIELD per line (an empty field
# is an empty line), because a tab is IFS whitespace to `read` and empty
# fields would otherwise collapse and shift every column after them; the
# first line is the field count.
last_record() {
  printf '%s\n' "$1" | awk -F'\t' -v c="$2" -v w="$3" '
    ($c "") == (w "") { l = $0; n = NF }
    END {
      if (n == 0) exit
      print n
      split(l, f, "\t")
      for (i = 1; i <= n; i++) print f[i]
    }'
}

# git_ro <dir> <args...> — a read-only git query in a worktree the detector
# did not create: the repository's own config is untrusted, so no optional
# index lock (someone else's worktree, possibly mid-command) and no
# fsmonitor; the callers use only plumbing that hashes no file content, so
# no clean filter can run either.
git_ro() {
  gr_dir=$1
  shift
  GIT_OPTIONAL_LOCKS=0 git -C "$gr_dir" -c core.fsmonitor=false "$@"
}

# is_git_toplevel <dir> — 0 iff <dir> is the top of a git working tree (not
# merely a directory nested inside one, which `--is-inside-work-tree` would
# also accept for a fleet home that happens to live inside a checkout).
is_git_toplevel() {
  igt_top=$(git_ro "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  igt_dir=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  [ "$igt_top" = "$igt_dir" ]
}

# The per-run presence memo: one `liveness` question per distinct owner
# token, however many workers share it.
presence_memo=""

# owner_liveness <token> — prints the presence surface's answer word for the
# token: self | live | dead | unknown | ambiguous | no-record | unreadable |
# presence-unavailable.
owner_liveness() {
  ol_hit=$(printf '%s\n' "$presence_memo" | awk -F'\t' -v t="$1" '($1 "") == (t "") { print $2; exit }')
  if [ -n "$ol_hit" ]; then
    printf '%s\n' "$ol_hit"
    return 0
  fi
  ol_rc=0
  ol_out=$("$FP" liveness --checkout "$checkout" "$presence_id_flag" "$presence_id_value" "$1" 2>/dev/null) || ol_rc=$?
  ol_word='presence-unavailable'
  if [ "$ol_rc" = 0 ]; then
    ol_tag=${ol_out%%"$TAB"*}
    case $ol_tag in
      tower)
        ol_v=${ol_out##*"$TAB"}
        case $ol_v in
          self | live | dead | unknown | ambiguous) ol_word=$ol_v ;;
        esac
        ;;
      no-record) ol_word=no-record ;;
      unreadable) ol_word=unreadable ;;
    esac
  fi
  presence_memo="$presence_memo$1$TAB$ol_word$NL"
  printf '%s\n' "$ol_word"
}

anomalies=""
note_anomaly() {
  anomalies="$anomalies$1$NL"
}

# --- per-worker classification -----------------------------------------------

# read_registry <worker> — sets reg_status, reg_scope, reg_owner, reg_backend,
# reg_state_dir, reg_handle from the snapshot. Seven columns is the current
# shape; three is the pre-owner shape, still parseable; anything else is a
# torn or hand-edited line.
read_registry() {
  reg_status=$registry_status
  reg_scope=""
  reg_owner=""
  reg_backend=""
  reg_state_dir=""
  reg_handle=""
  [ "$registry_status" = present ] || return 0
  rr_fields=$(last_record "$registry_data" 2 "$1")
  if [ -z "$rr_fields" ]; then
    reg_status=absent
    return 0
  fi
  rr_nf=${rr_fields%%"$NL"*}
  case $rr_nf in
    7)
      {
        IFS= read -r _
        IFS= read -r _
        IFS= read -r _
        IFS= read -r reg_scope
        IFS= read -r reg_owner
        IFS= read -r reg_backend
        IFS= read -r reg_state_dir
        IFS= read -r reg_handle
      } <<REC
$rr_fields
REC
      [ "$reg_owner" = - ] && reg_owner=""
      [ "$reg_backend" = - ] && reg_backend=""
      [ "$reg_state_dir" = - ] && reg_state_dir=""
      [ "$reg_handle" = - ] && reg_handle=""
      # An unsupplied optional field is `-`; a field that fails its own
      # grammar is corruption, and the record is reported rather than
      # half-trusted (the store refuses such a field at write).
      if { [ -n "$reg_owner" ] && ! valid_owner "$reg_owner"; } \
        || { [ -n "$reg_backend" ] && ! valid_backend "$reg_backend"; } \
        || { [ -n "$reg_state_dir" ] && ! valid_abs_dir "$reg_state_dir"; } \
        || { [ -n "$reg_handle" ] && ! valid_death_handle "$reg_handle"; } \
        || ! valid_field "$reg_scope"; then
        reg_status=malformed
      fi
      ;;
    3)
      {
        IFS= read -r _
        IFS= read -r _
        IFS= read -r _
        IFS= read -r reg_scope
      } <<REC
$rr_fields
REC
      valid_field "$reg_scope" || reg_status=malformed
      ;;
    *) reg_status=malformed ;;
  esac
  if [ "$reg_status" = malformed ]; then
    reg_scope=""
    reg_owner=""
    reg_backend=""
    reg_state_dir=""
    reg_handle=""
    note_anomaly registry-malformed
  fi
}

# read_attention <worker> — sets attn_status, attn_state, attn_scope,
# attn_reason, attn_claimed from the snapshot. Eight shipped fields plus up
# to three additive ones (fleet-attention.sh upsert_row); the state word and
# the heartbeat must parse, no field may carry a control byte, and the park
# reason is the store's own free-text grammar.
read_attention() {
  attn_status=$store_status
  attn_state=""
  attn_scope=""
  attn_reason=""
  attn_claimed=""
  [ "$store_status" = present ] || return 0
  ra_fields=$(last_record "$store_data" 1 "$1")
  if [ -z "$ra_fields" ]; then
    attn_status=absent
    return 0
  fi
  ra_nf=${ra_fields%%"$NL"*}
  ra_ts=""
  if [ "$ra_nf" -ge 8 ] && [ "$ra_nf" -le 11 ]; then
    {
      IFS= read -r _
      IFS= read -r _
      IFS= read -r attn_scope
      IFS= read -r attn_state
      IFS= read -r ra_ts
      IFS= read -r _
      IFS= read -r _
      IFS= read -r _
      IFS= read -r _
      IFS= read -r attn_reason
      IFS= read -r _
      IFS= read -r attn_claimed
    } <<REC
$ra_fields
REC
    ra_flat=$(printf '%s' "$ra_fields" | tr -d '\n')
    control_free "$ra_flat" || attn_status=malformed
    case $attn_state in
      working | idle | hung | ended | awaiting-input | pr-ready | merged | done) ;;
      *) attn_status=malformed ;;
    esac
    case $ra_ts in
      "" | *[!0-9]*) attn_status=malformed ;;
    esac
    if [ -n "$attn_reason" ] && ! valid_text "$attn_reason"; then
      attn_status=malformed
    fi
  else
    attn_status=malformed
  fi
  if [ "$attn_status" = malformed ]; then
    attn_state=""
    attn_scope=""
    attn_reason=""
    attn_claimed=""
    note_anomaly attention-malformed
  fi
}

# read_completion <runtime-dir> — sets completion (absent | result=<subtype>
# | exit=<rc>) and completion_ok (1 for a success, 0 otherwise) from the
# stream-json supervisor's `result` record (result <subtype> <epoch> | exit
# <rc> <epoch>) or the headless runner's `exit` record (<rc> <epoch>). One
# bounded read per record.
read_completion() {
  completion=absent
  completion_ok=0
  rc_dir=$1
  [ -n "$rc_dir" ] || return 0
  if [ -e "$rc_dir/result" ]; then
    if [ ! -f "$rc_dir/result" ] || [ ! -r "$rc_dir/result" ]; then
      note_anomaly result-unreadable
      return 0
    fi
    rc_line=$(head -c 4096 "$rc_dir/result" 2>/dev/null | head -n 1) || rc_line=""
    rc_kind=${rc_line%%"$TAB"*}
    rc_rest=${rc_line#*"$TAB"}
    rc_val=${rc_rest%%"$TAB"*}
    case $rc_kind in
      result | exit) ;;
      *)
        note_anomaly result-record-malformed
        return 0
        ;;
    esac
    case $rc_val in
      "" | *[!A-Za-z0-9_-]*) rc_val=unknown ;;
    esac
    [ "${#rc_val}" -le 32 ] || rc_val=unknown
    # Field 4 (result records only) carries the frame's is_error flag. A frame
    # can report subtype success and is_error true at once, because an API
    # error arrives as assistant text: the turn completed, the run did not.
    # Reading the subtype alone calls that finished and frees the slot on a
    # worker that did nothing. Records predating the field have three fields
    # and keep their previous meaning.
    rc_err=""
    case $rc_rest in
      *"$TAB"*"$TAB"*)
        rc_after=${rc_rest#*"$TAB"}
        rc_err=${rc_after#*"$TAB"}
        rc_err=${rc_err%%"$TAB"*}
        ;;
    esac
    completion="$rc_kind=$rc_val"
    case $completion in
      result=success | exit=0) completion_ok=1 ;;
    esac
    if [ "$rc_err" = true ]; then
      completion="$completion/is_error=true"
      completion_ok=0
    fi
    return 0
  fi
  if [ -e "$rc_dir/exit" ]; then
    if [ ! -f "$rc_dir/exit" ] || [ ! -r "$rc_dir/exit" ]; then
      note_anomaly exit-unreadable
      return 0
    fi
    rc_line=$(head -c 4096 "$rc_dir/exit" 2>/dev/null | head -n 1) || rc_line=""
    rc_val=${rc_line%% *}
    case $rc_val in
      "" | *[!0-9]*) rc_val=unknown ;;
    esac
    [ "${#rc_val}" -le 32 ] || rc_val=unknown
    completion="exit=$rc_val"
    [ "$rc_val" = 0 ] && completion_ok=1
  fi
}

# read_journal <runtime-dir> — sets journal_pending, the count of pending
# control_request receipts (fleet-streamjson.sh journal: id kind epoch state).
read_journal() {
  journal_pending=0
  [ -n "$1" ] && [ -e "$1/journal" ] || return 0
  if [ ! -f "$1/journal" ] || [ ! -r "$1/journal" ]; then
    note_anomaly journal-unreadable
    return 0
  fi
  journal_pending=$(head -c 1048576 "$1/journal" 2>/dev/null | awk -F'\t' '$4 == "pending" { n++ } END { print n + 0 }') || journal_pending=0
  case $journal_pending in
    "" | *[!0-9]*) journal_pending=0 ;;
  esac
}

# read_events <file> — sets stage and stage_source from the most recent
# stage-bearing event in a bounded tail of the stream. Only complete lines
# (ending in `}`) count, so a line the supervisor is mid-append cannot set a
# stage; the needles are anchored to their JSON keys, and the push needle
# matches only at a command position (the start of the command, or after a
# separator and an optional then/do/else), so a tool call that merely
# mentions or quotes a marker is not read as the marker. The residue is a
# separator followed by the words inside one quoted string.
read_events() {
  stage=-
  stage_source=absent
  [ -n "$1" ] || return 0
  stage_source=events
  re_stage=$(tail -c 262144 "$1" 2>/dev/null | awk '
    !/}[ \t\r]*$/ { next }
    /"type":"result"/ { stage = "completed"; next }
    /"type":"tool_use"/ {
      if ($0 ~ /"name":"Skill"/ && $0 ~ /"skill":"[^"]*(polish|self-review)/) stage = "converging"
      else if ($0 ~ /"name":"Bash"/ && $0 ~ /"command":"( *git push|([^"\\]|\\.)*([;&|({]|\\\\n)( *(then|do|else))? *git push)/) stage = "handing-off"
      else stage = "implementing"
      next
    }
    /"type":"system"/ && /"subtype":"init"/ { if (stage == "") stage = "launched" }
    END { print stage }') || re_stage=""
  case $re_stage in
    launched | implementing | converging | handing-off | completed) stage=$re_stage ;;
    *) stage=- ;;
  esac
}

# check_worktree <dir> — sets tree (clean | dirty | unverifiable), unpushed
# (<n> | unverifiable) from local git state, through plumbing that hashes no
# content: a touched-but-identical file reads dirty (the fail-closed side).
check_worktree() {
  tree=unverifiable
  unpushed=unverifiable
  cw_dir=$1
  cw_changes=$(git_ro "$cw_dir" ls-files -m -d -o --exclude-standard 2>/dev/null) || return 0
  cw_staged=0
  git_ro "$cw_dir" diff-index --cached --quiet HEAD 2>/dev/null || cw_staged=$?
  case $cw_staged in
    0 | 1) ;;
    *) return 0 ;;
  esac
  if [ -n "$cw_changes" ] || [ "$cw_staged" = 1 ]; then
    tree=dirty
  else
    tree=clean
  fi
  if git_ro "$cw_dir" rev-parse --verify --quiet '@{u}' >/dev/null 2>&1; then
    cw_n=$(git_ro "$cw_dir" rev-list --count '@{u}..HEAD' 2>/dev/null) || cw_n=""
  elif [ -n "$(git_ro "$cw_dir" for-each-ref --count=1 refs/remotes 2>/dev/null)" ]; then
    cw_n=$(git_ro "$cw_dir" rev-list --count HEAD --not --remotes 2>/dev/null) || cw_n=""
  else
    cw_n=""
  fi
  case $cw_n in
    "" | *[!0-9]*) unpushed=unverifiable ;;
    *) unpushed=$cw_n ;;
  esac
}

# count_commits <dir> — sets commits: the unit branch's own commits since it
# diverged from the default branch, the first of these refs that resolves.
count_commits() {
  commits=unverifiable
  for cc_base in origin/HEAD origin/main origin/master main master; do
    if git_ro "$1" rev-parse --verify --quiet "$cc_base" >/dev/null 2>&1; then
      cc_n=$(git_ro "$1" rev-list --count "$cc_base..HEAD" 2>/dev/null) || cc_n=""
      case $cc_n in
        "" | *[!0-9]*) ;;
        *) commits=$cc_n ;;
      esac
      return 0
    fi
  done
}

# read_pane <file> — sets pane_state from one bounded read of the capture:
# a busy marker in the footer is a running turn and outranks a signature
# higher in the window (an answered dialog still in the scrollback); a
# signature in the bounded window with no busy footer is the blocked signal;
# an at-prompt anchor alone is a turn that ended.
read_pane() {
  pane_state=absent
  [ -n "$1" ] || return 0
  rp_rc=0
  rp_window=$(tail -c 65536 "$1" 2>/dev/null | tail -n "$prompt_lines" | tr -d '\000-\010\013-\037\177') || rp_rc=$?
  if [ "$rp_rc" != 0 ] || [ ! -r "$1" ]; then
    note_anomaly pane-unreadable
    return 0
  fi
  rp_footer=$(printf '%s\n' "$rp_window" | tail -n "$footer_lines")
  case $(raw_classify "$rp_footer") in
    busy) pane_state=busy ;;
    idle)
      if permission_prompt_present "$rp_window"; then
        pane_state='permission-prompt'
      else
        pane_state='idle-prompt'
      fi
      ;;
    *)
      if permission_prompt_present "$rp_window"; then
        pane_state='permission-prompt'
      else
        pane_state=indeterminate
      fi
      ;;
  esac
}

# classify_one <worker> — the whole signal walk for one handle: prints its
# worker row, evidence, and anomalies. The classify-only overrides (state
# dir, death handle, worktree, pane, events) are the globals set from argv,
# empty under `scan`.
classify_one() {
  cur_worker=$1
  anomalies=""

  read_registry "$cur_worker"
  read_attention "$cur_worker"

  eff_backend=${backend:-$reg_backend}
  eff_state_dir=${state_dir:-$reg_state_dir}
  eff_handle=${death_handle:-$reg_handle}
  eff_scope=${reg_scope:-$attn_scope}
  owner_token=$reg_owner

  # The state dir is one of two layouts: the unit worktree (the tmux rung)
  # or a runtime dir (the two session-grade rungs). A git toplevel is the
  # former; only the latter carries the runtime records, so a worktree that
  # happens to hold a file named `result` is never read as one.
  runtime_dir=""
  eff_worktree=$worktree
  if [ -n "$eff_state_dir" ] && [ -d "$eff_state_dir" ]; then
    if is_git_toplevel "$eff_state_dir"; then
      [ -n "$eff_worktree" ] || eff_worktree=$eff_state_dir
    else
      runtime_dir=$eff_state_dir
    fi
  fi
  if [ -z "$runtime_dir" ] && [ -d "$root/streamjson/$cur_worker" ]; then
    runtime_dir="$root/streamjson/$cur_worker"
  fi

  read_completion "$runtime_dir"
  read_journal "$runtime_dir"
  # The SessionEnd push is the third session-ended record.
  if [ "$completion" = absent ] && [ "$attn_state" = ended ]; then
    completion='session-ended'
    completion_ok=1
  fi

  # A stream-json dispatch may have registered no death handle (the
  # supervisor pid can land after the registrar's bounded wait); the
  # runtime dir's own pidfile is the same evidence class.
  runtime_pids=0
  if [ -n "$runtime_dir" ] && [ -f "$runtime_dir/supervisor.pid" ] && [ -f "$runtime_dir/worker.pid" ]; then
    runtime_pids=1
    if [ -z "$eff_handle" ]; then
      rp_pid=$(head -c 16 "$runtime_dir/supervisor.pid" 2>/dev/null | head -n 1) || rp_pid=""
      valid_pid "$rp_pid" && eff_handle="process $rp_pid"
    fi
  fi

  # Death evidence (REQ-C1.5): the predicate's own verdict word, and only
  # for a handle it accepts. `none` is a rung that spawned no process; it
  # is never passed through (the predicate would refuse it, exit 2). The
  # predicate's stderr flows through, so a lost-observability reason stays
  # visible.
  death=absent
  if [ -n "$eff_handle" ]; then
    if [ "$eff_handle" = none ]; then
      death=none
    elif [ ! -x "$FDE" ]; then
      death=unknown
      note_anomaly death-predicate-missing
    else
      # shellcheck disable=SC2086
      set -- $eff_handle
      d_rc=0
      d_out=$("$FDE" "$@") || d_rc=$?
      case "$d_rc:$d_out" in
        0:dead) death=dead ;;
        1:alive) death=alive ;;
        *) death=unknown ;;
      esac
    fi
  fi

  events_file=$events
  if [ -z "$events_file" ] && [ -n "$runtime_dir" ] && [ -f "$runtime_dir/events.jsonl" ] && [ -r "$runtime_dir/events.jsonl" ]; then
    events_file="$runtime_dir/events.jsonl"
  fi
  read_events "$events_file"

  tree=-
  unpushed=-
  commits=unverifiable
  if [ -n "$eff_worktree" ] && [ -d "$eff_worktree" ] && is_git_toplevel "$eff_worktree"; then
    count_commits "$eff_worktree"
    if [ "$completion" != absent ]; then
      check_worktree "$eff_worktree"
    fi
  elif [ "$completion" != absent ]; then
    tree=unverifiable
    unpushed=unverifiable
  fi

  read_pane "$pane"

  # Owner attribution (REQ-C1.6).
  owner='dead-or-unknown'
  owner_ev=absent
  if [ -n "$owner_token" ]; then
    if [ -n "$self_tower" ] && [ "$owner_token" = "$self_tower" ]; then
      owner='this-tower'
      owner_ev=self
    elif ! valid_tower_id "$owner_token"; then
      owner_ev=unrecognized
    elif [ -z "$presence_id_flag" ]; then
      owner_ev='no-identity'
    elif [ -z "$checkout" ] || [ ! -x "$FP" ]; then
      owner_ev='presence-unavailable'
    else
      owner_ev=$(owner_liveness "$owner_token")
      case $owner_ev in
        self) owner=this-tower ;;
        live) owner=live-peer ;;
      esac
    fi
  fi

  # The state, by precedence.
  state=unclassified
  reason='no-signal'
  if [ "$death" = dead ]; then
    state=dead
    reason='death-evidence'
  elif [ "$attn_state" = awaiting-input ] && [ -z "$attn_claimed" ]; then
    state='waiting-on-a-human'
    reason='hook-push'
  elif [ "$journal_pending" -gt 0 ] && [ "$completion" = absent ]; then
    state='waiting-on-a-human'
    reason='journal-pending'
  elif [ "$pane_state" = permission-prompt ]; then
    state='waiting-on-a-human'
    reason='prompt-signature'
  elif [ "$completion" != absent ]; then
    if [ "$completion_ok" != 1 ]; then
      state=unclassified
      reason="completion-failed:$completion"
    elif [ "$tree" = dirty ] || { [ "$unpushed" != unverifiable ] && [ "$unpushed" != - ] && [ "$unpushed" -gt 0 ]; }; then
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
  elif [ "$runtime_pids" = 1 ] && [ "$death" = alive ]; then
    state=working
    reason='runtime-running'
  elif [ "$attn_state" = hung ]; then
    state=unclassified
    reason='stop-failure'
  elif [ "$attn_state" = awaiting-input ]; then
    state=unclassified
    reason='fork-answered'
  elif [ "$attn_state" = idle ] || [ "$pane_state" = idle-prompt ]; then
    state=unclassified
    reason='turn-ended'
  fi

  printf 'worker\t%s\t%s\t%s\t%s\t%s\n' "$cur_worker" "$state" "$owner" "$stage" "$reason"
  # Enumerated words and grammar-validated tokens print as they are; the
  # loose-charset fields (a path, the park reason) cross the sanitizer.
  ev() { printf 'evidence\t%s\t%s\t%s\n' "$cur_worker" "$1" "$2"; }
  ev registry "$reg_status"
  ev backend "${eff_backend:--}"
  ev scope "${eff_scope:--}"
  ev owner-token "${owner_token:--}"
  ev owner-evidence "$owner_ev"
  ev attention "${attn_state:--}"
  ev attention-status "$attn_status"
  ev attention-reason "$(sanitize_printable "${attn_reason:--}" "-")"
  ev death "$death"
  ev completion "$completion"
  ev journal-pending "$journal_pending"
  ev worktree "$(sanitize_printable "${eff_worktree:--}" "-")"
  ev tree "$tree"
  ev unpushed "$unpushed"
  ev commits "$commits"
  ev pane "$pane_state"
  ev stage-source "$stage_source"
  printf '%s' "$anomalies" | while IFS= read -r an; do
    [ -n "$an" ] && printf 'anomaly\t%s\t%s\n' "$cur_worker" "$an"
  done
}

if [ "$cmd" = classify ]; then
  classify_one "$worker"
  exit 0
fi

# scan: the union of registry handles and attention rows, each classified
# once, in a deterministic order. A surface that exists but cannot be read is
# reported, never mistaken for an empty fleet; a handle that fails the field
# grammar is a torn line, reported once and skipped.
[ "$registry_status" = unreadable ] && printf 'anomaly\t-\tregistry-unreadable\n'
[ "$store_status" = unreadable ] && printf 'anomaly\t-\tstore-unreadable\n'
handles=$(
  printf '%s\n' "$registry_data" | awk -F'\t' 'NF >= 2 { print $2 }'
  printf '%s\n' "$store_data" | awk -F'\t' 'NF >= 1 { print $1 }'
)
handles=$(printf '%s\n' "$handles" | awk 'NF { print }' | sort -u)
while IFS= read -r h; do
  [ -n "$h" ] || continue
  if ! valid_field "$h"; then
    printf 'anomaly\t%s\thandle-malformed\n' "$(sanitize_printable "$h" "?")"
    continue
  fi
  classify_one "$h"
done <<HANDLES
$handles
HANDLES
exit 0
