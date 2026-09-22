#!/bin/sh
# tower-loop-comms.sh — the operator-comms step of a tower loop (tower-comms
# Task 8; D-6, D-13, D-16, D-18, D-19 · REQ-A1.1, REQ-C1.1, REQ-C1.2, REQ-C1.4,
# REQ-C1.8, REQ-C1.10, REQ-C1.11, REQ-F1.5, REQ-F1.6, REQ-H1.3, REQ-I1.2).
#
# `/orchestrate`'s watch and `--fleet` loops call this once per iteration. It
# owns the ORDER the queue's verbs run in and the shape of what the tower is
# handed; the words the tower says are doctrine/tower-comms.md's, and every
# decision about which item goes next is scripts/tower-queue.sh's. Nothing here
# re-implements either — this is the wiring, which is why it lives in a script
# rather than in a skill body (REQ-I1.2: what a script can enforce is not prose).
#
#   identity --checkout <dir> (--session-id <uuid> | --pid <pid>)
#       Print the tower identity every queue call in the iteration carries,
#       resolved through scripts/fleet-presence.sh with the SAME flags the
#       loop's own presence publish used (D-18: the identity is the lease's
#       owner label, and a lease labelled differently from the presence record
#       is a lease nothing can attribute). A loop that publishes by --pid gets
#       the composite; one that publishes by --session-id gets that uuid's.
#       Exit 3 is the presence surface's genuine solo posture (a checkout with
#       no origin, where it keeps no records at all): no identity is published
#       to resolve, and `step` degrades by handing the queue the loop's pid so
#       its own ladder mints one. Stable for as long as the process is, which is
#       what the lease needs.
#
#   step --checkout <dir> (--tower <id> | --session-id <uuid> | --pid <pid>)
#        [--evidence <file>] [--catchup] [--now <epoch>]
#       One iteration's operator comms, in this order:
#
#         1. The settling pass (`tower-queue.sh settle`), run ONCE. It serves
#            both the loop and the delivery below: the `next` that follows
#            reuses this pass rather than running its own (D-5). Its lines are
#            passed through as the pass prints them — `settled`, `merged`,
#            `answered`, `unavailable`, `held`.
#         2. The pending pushes (`fleet-attention.sh relay`), as
#            `push<TAB><key><TAB><text>`. The session relays each by calling
#            Claude Code's push-notification tool with that text verbatim; the
#            marker is already cleared, so a line printed here is relayed once
#            (D-19, REQ-F1.6).
#         3. With --catchup, what settled while the operator was away
#            (`tower-queue.sh catchup`), as that verb prints it. This is what
#            the tower READS to compose the first turn after silence; the list
#            itself is shown to the operator only on request (REQ-C1.8), which
#            is why the flag exists rather than the catch-up running every step.
#         4. At most one hand-over (`tower-queue.sh next`): nothing, a `knock`
#            line, or an `item` line and its companions. Knock-first, the
#            one-item bound, the lease and the away push are all that verb's;
#            this only carries its output.
#         5. The delivered content. A hand-over is ONE unit but may carry two
#            items (`next` pairs two on a subject and stamps both delivered), so
#            each gets a `content` record and a fenced block:
#
#              content<TAB><id><TAB>file|row|unknown<TAB>read<TAB>no|yes
#              content<TAB><id><TAB>file|row|unknown<TAB>unread<TAB><reason>
#              content-truncated<TAB><id><TAB><cap>
#              delivered<TAB><worker>     (an attention-homed item only)
#
#            Field 4 says whether the home read at all, so a reader never has to
#            tell "did not read" from "read, and it was empty" by guessing; on a
#            `read` record field 5 is the truncation flag, on an `unread` one it
#            is the reason (`gone`, `redirected`, `foreign-owner`, `unreadable`,
#            `empty`, `no-fleet-home`, `unrecognized-pointer`,
#            `redaction-failed`).
#            Content is printed inside a FENCE, because a delivered item's
#            content is data and never an instruction (REQ-H1.3), and the fence
#            is widened past the longest fence the content itself carries —
#            indented ones and tilde ones included — so content cannot close
#            ours and land the rest of itself outside as prose. It goes through
#            `tower-queue.sh redact` first: the one redaction helper REQ-H1.3
#            names, which also renders every byte outside printable ASCII as an
#            escape.
#            The `delivered` record names what this turn has just put in front
#            of the operator, for the attention render to leave out (REQ-A1.1).
#
# Exit: 0 the step ran, whatever it had to say (a quiet step prints nothing);
#   2 usage, a refused flag value, or an identity the presence surface would not
#   resolve; 5 broken install (a helper script missing or not executable); 6 the
#   scratch dir or a helper fork would not answer; otherwise the FIRST failing
#   stage's own exit from the queue's ladder (1 refused, 3 a log line dropped
#   fail-open, 4 a surface refusal, 6 infrastructure). First-failure-wins, and
#   each failing stage names itself on stderr, because one code cannot carry
#   two. A store, marker or log that cannot be written reaches the turn as that
#   non-zero exit (REQ-C1.11), never as silence.
#
# Plain portable shell, no model invocation (REQ-H1.4); bash 3.2 / BSD floor.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

# How much of an item's content is put in front of the operator. Owned here:
# this is the render's bound, not the store's, and the store holds no content
# at all.
Q_CONTENT_CAP=4000

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 6
if [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "tower-loop-comms: scripts/echo-safety.sh is missing — broken install" >&2
  exit 5
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

TQ="$script_dir/tower-queue.sh"
FA="$script_dir/fleet-attention.sh"
FP="$script_dir/fleet-presence.sh"
TAB=$(printf '\t')

usage() {
  cat >&2 <<'EOF'
usage: tower-loop-comms.sh identity --checkout <dir> (--session-id <uuid> | --pid <pid>)
       tower-loop-comms.sh step --checkout <dir> (--tower <id> | --session-id <uuid> | --pid <pid>)
                                [--evidence <file>] [--catchup] [--now <epoch>]
EOF
  exit 2
}

err() {
  printf '%s\n' "tower-loop-comms: $1" >&2
}

need_exec() { # need_exec <path> <name>
  [ -x "$1" ] || {
    err "$2 is missing or not executable — broken install"
    exit 5
  }
}

# Kept in step with tower-queue.sh's own is_tower: a value this refuses would
# be refused there too, and refusing here names the flag that carried it.
is_tower() {
  case "$1" in
    "" | *[!A-Za-z0-9._-]* | .* | -*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

cmd="${1:-}"
[ -n "$cmd" ] || usage
shift || true

checkout=""
session_id=""
pid=""
tower=""
tower_set=0
evidence=""
evidence_set=0
want_catchup=0
now=""
now_set=0

while [ "$#" -gt 0 ]; do
  case $1 in
    --checkout)
      [ "$#" -ge 2 ] || usage
      checkout=$2
      shift 2
      ;;
    --session-id)
      [ "$#" -ge 2 ] || usage
      session_id=$2
      shift 2
      ;;
    --pid)
      [ "$#" -ge 2 ] || usage
      pid=$2
      shift 2
      ;;
    --tower)
      [ "$#" -ge 2 ] || usage
      tower=$2
      tower_set=1
      shift 2
      ;;
    --evidence)
      [ "$#" -ge 2 ] || usage
      evidence=$2
      evidence_set=1
      shift 2
      ;;
    --now)
      [ "$#" -ge 2 ] || usage
      now=$2
      now_set=1
      shift 2
      ;;
    --catchup)
      want_catchup=1
      shift
      ;;
    *)
      err "unknown argument '$(sanitize_printable "$1" "(unprintable argument)")'"
      usage
      ;;
  esac
done

[ -n "$checkout" ] || usage

# Gated on the flag having been GIVEN, not on its value: an explicitly empty
# one is a usage error, never a silent fall-through to the live clock, to no
# evidence, or to the presence surface. The sibling loop writer states the same
# rule (scripts/tower-loop-log.sh) and the seam enforces it for its own keys.
refuse_empty() { # refuse_empty <given> <value> <flag>
  [ "$1" = 1 ] || return 0
  [ -z "$2" ] || return 0
  err "$3 was given an empty value"
  usage
}
refuse_empty "$tower_set" "$tower" --tower
refuse_empty "$evidence_set" "$evidence" --evidence
refuse_empty "$now_set" "$now" --now

# resolve_identity — the tower id, from --tower when the caller already has one,
# else from the presence surface under the flags the loop published with. The
# presence script is the single authority for the composite form; deriving one
# here would give the lease a label the presence surface does not know.
resolve_identity() {
  if [ -n "$tower" ]; then
    is_tower "$tower" || {
      err "--tower '$(sanitize_printable "$tower" "(unprintable id)")' is not a tower identity"
      return 2
    }
    printf '%s\n' "$tower"
    return 0
  fi
  # A broken install is exit 5 to the CALLER, not a usage error: this runs in a
  # command substitution, so `exit 5` inside it would be collapsed by the
  # caller's own `|| exit 2` and a missing script would read as bad flags.
  if [ ! -x "$FP" ]; then
    err "scripts/fleet-presence.sh is missing or not executable — broken install"
    return 5
  fi
  if [ -n "$session_id" ] && [ -n "$pid" ]; then
    err "--session-id and --pid name two identities; give the one the loop's presence publish used"
    return 2
  fi
  if [ -n "$session_id" ]; then
    ri_out=$("$FP" identity --checkout "$checkout" --session-id "$session_id" 2>&1)
    ri_rc=$?
  elif [ -n "$pid" ]; then
    ri_out=$("$FP" identity --checkout "$checkout" --pid "$pid" 2>&1)
    ri_rc=$?
  else
    err "needs --tower, --session-id or --pid (the same identity flag the loop's presence publish used)"
    return 2
  fi
  # Exit 5 is the presence surface's genuine SOLO posture — a checkout with no
  # origin, where it deliberately keeps no records. That is not a failure to
  # resolve an identity; it is a tree where no identity is published to resolve.
  # Degrade to the queue's own ladder rather than refusing the step: the queue
  # mints a stable identity from a pid, so the lease stays attributable as long
  # as the loop passes the same pid every call, which is what `step` does.
  if [ "$ri_rc" = 5 ]; then
    err "no presence surface on this checkout (solo posture); the queue mints this loop's identity from its pid"
    return 3
  fi
  if [ "$ri_rc" != 0 ]; then
    err "the presence surface could not resolve this loop's identity: $(sanitize_printable "$ri_out" "(no diagnosis)")"
    return 2
  fi
  ri_id=$(printf '%s\n' "$ri_out" | head -n 1)
  is_tower "$ri_id" || {
    err "the presence surface returned no usable identity"
    return 2
  }
  printf '%s\n' "$ri_id"
}

case $cmd in
  identity)
    # The step's flags are refused here rather than ignored: a caller that
    # passed one meant to run a step, and silently answering a different
    # question is how a loop ends up never delivering anything.
    [ "$want_catchup" = 0 ] || usage
    [ "$evidence_set" = 0 ] || usage
    [ "$now_set" = 0 ] || usage
    id_out=$(resolve_identity)
    id_rc=$?
    [ "$id_rc" = 0 ] || exit "$id_rc"
    printf '%s\n' "$id_out"
    exit 0
    ;;
  step) ;;
  *)
    err "unknown command '$(sanitize_printable "$cmd" "(unprintable command)")' (identity | step)"
    usage
    ;;
esac

need_exec "$TQ" "scripts/tower-queue.sh"
need_exec "$FA" "scripts/fleet-attention.sh"

tower_id=$(resolve_identity)
tower_rc=$?
case $tower_rc in
  0) ;;
  3)
    # The solo posture: no presence surface to name this loop. Hand the queue
    # the loop's pid and let its own ladder mint the identity, which is stable
    # for as long as this process is — so the lease stays attributable.
    tower_id=""
    # Both identity flags, not just --pid: the queue's ladder takes a session
    # uuid directly, and dropping it here leaves the ladder with nothing, so it
    # falls through to a fallback minted from the INVOKING SHELL's pid — a
    # different identity on every iteration, which is a lease no later step of
    # this same loop can claim as its own.
    [ -z "$session_id" ] || PLANWRIGHT_TOWER_SESSION_ID=$session_id
    [ -z "$session_id" ] || export PLANWRIGHT_TOWER_SESSION_ID
    [ -z "$pid" ] || PLANWRIGHT_TOWER_PID=$pid
    [ -z "$pid" ] || export PLANWRIGHT_TOWER_PID
    ;;
  *) exit "$tower_rc" ;;
esac

# tower_flag — `--tower <id>` when one resolved, nothing when the queue is
# minting it. Passed unquoted on purpose; the id is charset-validated above.
tower_flag=""
[ -z "$tower_id" ] || tower_flag="--tower $tower_id"

# q / q_noev <verb> [args...] — one queue call. `--now` is the fixture seam and
# `--evidence` the reconcile's already-derived facts; each is appended only when
# the caller gave one, so a live loop runs the verbs exactly as they run
# standalone. The pair differs only in the `--evidence` append, because `settle`
# and `next` take that flag and `catchup` refuses it.
q() {
  if [ -n "$evidence" ]; then
    q_noev "$@" --evidence "$evidence"
  else
    q_noev "$@"
  fi
}

q_noev() {
  if [ -n "$now" ]; then
    "$TQ" "$@" --now "$now"
  else
    "$TQ" "$@"
  fi
}

# A scratch dir for the hand-over's own records. The `while read` below cannot
# consume a pipe: the loop body has to set variables the step still reads after
# it, and a piped `while` runs in a subshell in every shell this targets.
TMPDIR_STEP=$(mktemp -d 2>/dev/null) || {
  err "cannot create a scratch directory"
  exit 6
}
trap 'rm -rf "$TMPDIR_STEP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# step_rc — FIRST failure wins, and a later success never clears it. The verbs
# here return distinguishable codes (the queue's ladder: 1 refused, 3 a log line
# dropped fail-open, 4 a surface refusal, 6 infrastructure), so last-wins would
# report a dropped log line where a security refusal happened. Each failing
# stage also says which stage it was on stderr, because one code cannot carry
# two.
step_rc=0
note_rc() { # note_rc <rc> <stage>
  [ "$1" = 0 ] && return 0
  err "the $2 stage failed (exit $1)"
  [ "$step_rc" = 0 ] || return 0
  step_rc=$1
}

# --- 1. the settling pass, once, serving both the loop and the delivery --------

settle_lines=$(q settle)
note_rc "$?" "settling"
[ -z "${settle_lines:-}" ] || printf '%s\n' "$settle_lines"

# --- 2. the pending pushes, taken and handed to the session to relay ----------

relay_lines=$("$FA" relay)
note_rc "$?" "pending-push relay"
[ -z "${relay_lines:-}" ] || printf '%s\n' "$relay_lines"

# --- 3. the catch-up list, only when the tower asked to read it ----------------

if [ "$want_catchup" = 1 ]; then
  # shellcheck disable=SC2086
  catchup_lines=$(q_noev catchup $tower_flag)
  note_rc "$?" "catch-up"
  [ -z "${catchup_lines:-}" ] || printf '%s\n' "$catchup_lines"
fi

# --- 4. at most one hand-over -------------------------------------------------

# shellcheck disable=SC2086
next_lines=$(q next $tower_flag)
note_rc "$?" "hand-over"
[ -z "${next_lines:-}" ] || printf '%s\n' "$next_lines"

# --- 5. the delivered content, fenced as data ---------------------------------

# The readers below write the block to $RAW and set $content_why / $content_
# truncated in THIS shell. Deliberately not `raw=$(reader ...)`: a command
# substitution runs in a subshell, so the reason and the truncation flag set
# inside one would be discarded and every failure would read as an empty file.
RAW="$TMPDIR_STEP/content"
content_why=""
content_truncated=no

# owned_by_me <path> — the file the path finally names is this user's. Called
# on /dev/fd/7 as well as on names, which is why it follows.
owned_by_me() {
  # shellcheck disable=SC2012
  _obown=$(ls -dnL "$1" 2>/dev/null | awk 'NR == 1 { print $3 }')
  _obme=$(id -u 2>/dev/null)
  [ -n "$_obown" ] && [ -n "$_obme" ] && [ "$_obown" = "$_obme" ]
}

# open_screened <path> — open the path on fd 7 and prove the open file is the
# one the name holds now: a regular file of this user's, reached through no
# symlink at the leaf. Opening first and screening after is what closes the
# window between a check and a re-open: a swap before the open leaves the name
# and the descriptor on different files, and a swap after it cannot change what
# fd 7 reads. The caller screens the directory after this returns, for the same
# reason, and closes fd 7 whatever the outcome.
open_screened() {
  { command exec 7<"$1"; } 2>/dev/null || {
    content_why=unreadable
    return 1
  }
  # shellcheck disable=SC2012
  _osfd=$(ls -iLd /dev/fd/7 2>/dev/null | awk 'NR == 1 { print $1 }')
  # shellcheck disable=SC2012
  _osname=$(ls -id "$1" 2>/dev/null | awk 'NR == 1 { print $1 }')
  if [ -L "$1" ] || [ ! -f /dev/fd/7 ] || [ -z "$_osfd" ] || [ "$_osfd" != "$_osname" ]; then
    content_why=redirected
    return 1
  fi
  if ! owned_by_me /dev/fd/7; then
    content_why=foreign-owner
    return 1
  fi
}

# read_path_content <path> — the content of a `path:` home. The write
# paths checked this pointer when the item was added; that says nothing about
# the file being read now, so the screen is re-derived here (the rule
# scripts/tower-queue.sh states for its own ledger read). A symlink at the leaf,
# a symlink anywhere above it, and a file owned by somebody else are each
# refused, and the bytes rendered are read from the same open file the screen
# passed: an item's content is rendered to the operator, so a redirect planted
# after `add`, or between the screen and the read, would be reading an
# arbitrary file out loud. A hardlink to another file of this same owner is the
# residual neither this nor the ledger read can see.
read_path_content() {
  _rpok=0
  read_path_screened "$@" || _rpok=1
  exec 7<&-
  return "$_rpok"
}

read_path_screened() {
  _rp=$1
  if [ -L "$_rp" ] || [ ! -f "$_rp" ]; then
    content_why=gone
    return 1
  fi
  open_screened "$_rp" || return 1
  _rpdir=$(cd "$(dirname "$_rp")" 2>/dev/null && pwd -P) || _rpdir=""
  if [ -z "$_rpdir" ] || [ "$_rpdir/$(basename "$_rp")" != "$_rp" ]; then
    content_why=redirected
    return 1
  fi
  _rpfull="$TMPDIR_STEP/content.full"
  head -c "$((Q_CONTENT_CAP + 1))" <&7 >"$_rpfull" 2>/dev/null || {
    content_why=unreadable
    return 1
  }
  head -c "$Q_CONTENT_CAP" "$_rpfull" >"$RAW" 2>/dev/null || {
    content_why=unreadable
    return 1
  }
  # One byte past the cap decides the flag, so a block that exactly fills it is
  # not reported as cut and one that overruns it is. Measured on the FILE, not
  # on a shell variable: a variable has already lost its trailing newlines to
  # the substitution that made it, which is what a length taken there gets
  # wrong in both directions.
  _rpbytes=$(wc -c <"$_rpfull" | tr -d ' ')
  case $_rpbytes in
    "" | *[!0-9]*) ;;
    *) [ "$_rpbytes" -le "$Q_CONTENT_CAP" ] || content_truncated=yes ;;
  esac
  [ -s "$RAW" ] || {
    content_why=empty
    return 1
  }
}

# read_row_content <pointer> — the attention row's question, recommendation,
# option set and (for a permission record) the command the operator is being
# asked to approve: what makes the item answerable from the one message
# (REQ-C1.1). Field order is scripts/fleet-attention.sh's upsert_row: 1 handle,
# 6 question, 7 default, 8 options, 10 instance, 12 command.
read_row_content() {
  _rrok=0
  read_row_screened "$@" || _rrok=1
  exec 7<&-
  return "$_rrok"
}

read_row_screened() {
  _rrh=$1
  _rrroot=$("$script_dir/fleet-state.sh" root 2>/dev/null) || _rrroot=""
  if [ -z "$_rrroot" ]; then
    content_why=no-fleet-home
    return 1
  fi
  _rrstore="$_rrroot/attention/state"
  # The row is rendered to the operator as the question, so it gets the screen
  # the path home above gets and tower-queue.sh's check_owned gives this same
  # store. `next` screened it a moment ago; that says nothing about the file
  # read now. Only the store and its directory, not every component above: the
  # fleet home is not canonicalized, and a home under a symlinked prefix is not
  # a redirect.
  if [ -L "$_rrstore" ] || [ ! -f "$_rrstore" ]; then
    content_why=gone
    return 1
  fi
  open_screened "$_rrstore" || return 1
  if [ -L "${_rrstore%/*}" ]; then
    content_why=redirected
    return 1
  fi
  if ! owned_by_me "${_rrstore%/*}"; then
    content_why=foreign-owner
    return 1
  fi
  # The pointer is `<handle>` or `<handle>@<instance>`, and `@` is legal in
  # both, so it is matched whole rather than split. A question's pointer
  # carries the instance it was queued for: a worker that has re-forked since
  # holds a different question, and handing that over would have the operator
  # answer something the item never asked. `($1 "") == (h "")` forces a string
  # compare: awk would otherwise treat a numeric-looking handle as a number, so
  # `0100` and `1e2` would both match a row keyed `100`. The same guard is in
  # scripts/fleet-attention.sh for the same reason.
  awk -F "$TAB" -v h="$_rrh" '
    ($1 "") == (h "") || ($1 "@" $10) == (h "") {
      if ($6 != "") print "question: " $6
      if ($7 != "") print "recommend: " $7
      if ($8 != "") print "options: " $8
      if ($12 != "") print "command: " $12
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  ' <&7 >"$RAW" 2>/dev/null || {
    content_why=gone
    return 1
  }
  [ -s "$RAW" ] || {
    content_why=empty
    return 1
  }
}

# emit_content <item-id> <pointer> — resolve one delivered item's content home
# and put it in front of the tower, fenced.
emit_content() {
  _ec_id=$1
  _ec_ptr=$2
  content_why=""
  content_truncated=no
  : >"$RAW"
  case $_ec_ptr in
    path:*)
      _ec_home="file"
      read_path_content "${_ec_ptr#path:}" || :
      ;;
    attention:*)
      _ec_home="row"
      read_row_content "${_ec_ptr#attention:}" || :
      ;;
    *)
      _ec_home="unknown"
      content_why=unrecognized-pointer
      ;;
  esac

  if [ -n "$content_why" ]; then
    # Never silently (REQ-C1.11). The reason is its own field so a reader never
    # has to tell "did not read" from "read, and it was empty" by guessing, and
    # the record's arity matches the success line's.
    printf 'content\t%s\t%s\t%s\t%s\n' "$_ec_id" "$_ec_home" unread "$content_why"
    if [ "$content_why" = empty ]; then
      err "the content home for $_ec_id is empty; the item is handed over without content"
    else
      err "the content home for $_ec_id did not read ($content_why); the item is handed over without it"
    fi
    return 0
  fi

  # The one redaction helper, reached where REQ-H1.3 says it must be: the queue
  # script owns it, this asks for it rather than growing a second copy. It also
  # renders every byte outside printable ASCII as an escape, so nothing in the
  # block can drive the terminal or display as something it is not.
  "$TQ" redact <"$RAW" >"$TMPDIR_STEP/safe" || {
    printf 'content\t%s\t%s\t%s\t%s\n' "$_ec_id" "$_ec_home" unread redaction-failed
    err "the content for $_ec_id could not be redacted; it is NOT rendered"
    note_rc 6 "content redaction"
    return 0
  }

  # The fence must outlast the longest fence the content itself carries, or the
  # content closes ours and the rest of it lands outside the block as prose —
  # which is the whole of the REQ-H1.3 escape. Markdown lets a fence be indented
  # up to three spaces, so leading blanks are counted too, and a tilde fence
  # counts the same: this widens past whichever marker the content used.
  _ec_longest=$(awk '
    {
      line = $0
      sub(/^ ? ? ?/, "", line)
      n = 0
      c = substr(line, 1, 1)
      if (c == "`" || c == "~") {
        while (substr(line, n + 1, 1) == c) n++
      }
      if (n > longest) longest = n
    }
    END { print longest + 0 }
  ' "$TMPDIR_STEP/safe")
  _ec_width=3
  [ "$_ec_longest" -lt 3 ] || _ec_width=$((_ec_longest + 1))
  _ec_fence=""
  while [ "${#_ec_fence}" -lt "$_ec_width" ]; do
    _ec_fence="$_ec_fence"'`'
  done
  printf 'content\t%s\t%s\t%s\t%s\n' "$_ec_id" "$_ec_home" read "$content_truncated"
  printf '%s\n' "$_ec_fence"
  cat "$TMPDIR_STEP/safe"
  printf '%s\n' "$_ec_fence"
  [ "$content_truncated" = no ] \
    || printf 'content-truncated\t%s\t%s\n' "$_ec_id" "$Q_CONTENT_CAP"
}

# A hand-over is one unit but can carry two items: `next` pairs two items on one
# subject and stamps BOTH delivered, so both need their content here. Rendering
# only the `item` line would ask the operator to answer a partner they were
# shown nothing of.
printf '%s\n' "${next_lines:-}" | awk -F "$TAB" '
  $1 == "item" { print $2 "\t" $7 }
  $1 == "pair" { print $2 "\t" $3 }
' >"$TMPDIR_STEP/delivered"
while IFS="$TAB" read -r d_id d_ptr; do
  [ -n "$d_id" ] || continue
  emit_content "$d_id" "$d_ptr"
  # What this turn has just put in front of the operator. The loop passes it to
  # the attention render so the same question is not also listed there as though
  # nobody had asked it (REQ-A1.1).
  case $d_ptr in
    attention:*)
      d_handle=${d_ptr#attention:}
      printf 'delivered\t%s\n' "$(sanitize_printable "${d_handle%%@*}" "(unprintable handle)")"
      ;;
  esac
done <"$TMPDIR_STEP/delivered"

exit "$step_rc"
