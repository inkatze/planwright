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
#         5. For an item, its content — resolved from the content home the
#            record points at and printed inside a FENCE, because a delivered
#            item's content is data and never an instruction (REQ-H1.3). The
#            fence is widened past the longest backtick run in the content, so
#            content carrying its own fence cannot close ours and land the rest
#            of itself outside as prose. Over `Q_CONTENT_CAP` bytes the block is
#            cut with a `content-truncated` record, since the operator answers
#            from the shortest context that makes the item answerable, not from
#            a file.
#
#       Exit 0 when the step ran, whatever it had to say (a quiet step prints
#       nothing). A store, marker or log that cannot be written is the queue's
#       own error and reaches the turn as its non-zero exit (REQ-C1.11).
#
# Every surfaced byte goes through the canonical echo-discipline sanitizer, and
# the content block additionally has its newlines preserved rather than
# flattened — a fenced block is where multi-line text is safe to show.
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

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 5
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
evidence=""
want_catchup=0
now=""

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
      shift 2
      ;;
    --evidence)
      [ "$#" -ge 2 ] || usage
      evidence=$2
      shift 2
      ;;
    --now)
      [ "$#" -ge 2 ] || usage
      now=$2
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
  need_exec "$FP" "scripts/fleet-presence.sh"
  if [ -n "$session_id" ]; then
    ri_out=$("$FP" identity --checkout "$checkout" --session-id "$session_id" 2>&1) || {
      err "the presence surface could not resolve this loop's identity: $(sanitize_printable "$ri_out" "(no diagnosis)")"
      return 2
    }
  elif [ -n "$pid" ]; then
    ri_out=$("$FP" identity --checkout "$checkout" --pid "$pid" 2>&1) || {
      err "the presence surface could not resolve this loop's identity: $(sanitize_printable "$ri_out" "(no diagnosis)")"
      return 2
    }
  else
    err "needs --tower, --session-id or --pid (the same identity flag the loop's presence publish used)"
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
    [ "$want_catchup" = 0 ] && [ -z "$evidence" ] || usage
    resolve_identity || exit 2
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

tower_id=$(resolve_identity) || exit 2

# q <verb> [args...] — one queue call. `--now` and `--evidence` are the fixture
# and reconcile seams: each is appended only when the caller gave one, so a live
# loop runs the verbs exactly as they run standalone.
q() {
  q_verb=$1
  shift
  if [ -n "$now" ] && [ -n "$evidence" ]; then
    "$TQ" "$q_verb" "$@" --evidence "$evidence" --now "$now"
  elif [ -n "$now" ]; then
    "$TQ" "$q_verb" "$@" --now "$now"
  elif [ -n "$evidence" ]; then
    "$TQ" "$q_verb" "$@" --evidence "$evidence"
  else
    "$TQ" "$q_verb" "$@"
  fi
}

# q_noev <verb> [args...] — the same, for the verbs that take no --evidence.
q_noev() {
  if [ -n "$now" ]; then
    "$TQ" "$@" --now "$now"
  else
    "$TQ" "$@"
  fi
}

step_rc=0

# --- 1. the settling pass, once, serving both the loop and the delivery --------

settle_lines=$(q settle) || step_rc=$?
[ -z "${settle_lines:-}" ] || printf '%s\n' "$settle_lines"

# --- 2. the pending pushes, taken and handed to the session to relay ----------

relay_lines=$("$FA" relay) || err "the pending-push relay reported a problem; see the seam's own diagnosis"
[ -z "${relay_lines:-}" ] || printf '%s\n' "$relay_lines"

# --- 3. the catch-up list, only when the tower asked to read it ----------------

if [ "$want_catchup" = 1 ]; then
  catchup_lines=$(q_noev catchup --tower "$tower_id") || step_rc=$?
  [ -z "${catchup_lines:-}" ] || printf '%s\n' "$catchup_lines"
fi

# --- 4. at most one hand-over -------------------------------------------------

next_lines=$(q next --tower "$tower_id") || step_rc=$?
[ -z "${next_lines:-}" ] || printf '%s\n' "$next_lines"

# --- 5. the item's content, fenced as data ------------------------------------

item_line=$(printf '%s\n' "${next_lines:-}" | awk -F "$TAB" '$1 == "item" { print; exit }')
if [ -n "$item_line" ]; then
  item_id=$(printf '%s\n' "$item_line" | awk -F "$TAB" '{ print $2 }')
  pointer=$(printf '%s\n' "$item_line" | awk -F "$TAB" '{ print $7 }')
  raw=""
  source_note=""
  case $pointer in
    path:*)
      cpath=${pointer#path:}
      if [ -f "$cpath" ] && [ ! -L "$cpath" ]; then
        raw=$(head -c "$Q_CONTENT_CAP" "$cpath" 2>/dev/null) || raw=""
        source_note="file"
      else
        source_note=gone
      fi
      ;;
    attention:*)
      handle=${pointer#attention:}
      handle=${handle%%@*}
      # The row's own question, recommendation and option set: what makes the
      # item answerable from the one message (REQ-C1.1). The `queue` render
      # above is the status surface; this is the hand-over.
      root=$("$script_dir/fleet-state.sh" root 2>/dev/null) || root=""
      state_store="$root/attention/state"
      if [ -n "$root" ] && [ -f "$state_store" ]; then
        raw=$(awk -F "$TAB" -v h="$handle" '
          $1 == h {
            if ($7 != "") print "question: " $7
            if ($8 != "") print "recommend: " $8
            if ($9 != "") print "options: " $9
            if ($12 != "") print "command: " $12
            found = 1
          }
          END { if (!found) exit 1 }
        ' "$state_store" 2>/dev/null) || raw=""
        source_note=row
      else
        source_note=gone
      fi
      ;;
    *)
      source_note=gone
      ;;
  esac

  if [ "$source_note" = gone ] || [ -z "$raw" ]; then
    # Never silently: an item whose content home will not read is the turn's to
    # say, and the record stays open for the settling pass to close on evidence.
    printf 'content\t%s\t%s\t%s\n' "$item_id" "$source_note" \
      "$(sanitize_printable "$pointer" "(unprintable pointer)")"
    err "the content home for $item_id did not read; the item is handed over without it"
  else
    truncated=no
    rawbytes=$(printf '%s' "$raw" | wc -c | tr -d ' ')
    [ "$rawbytes" -lt "$Q_CONTENT_CAP" ] || truncated=yes
    # Strip the control bytes line by line: sanitize_printable is per-value and
    # drops the newlines a fenced block is exactly the place to keep.
    safe=$(printf '%s\n' "$raw" | tr -d '\000-\010\013\014\016-\037\177\200-\237')
    # The fence has to outlast the longest column-0 backtick run in the content,
    # or the content's own fence closes ours and the rest of it lands outside as
    # prose (REQ-H1.3). Markdown's own rule, applied mechanically.
    longest=$(printf '%s\n' "$safe" | awk '
      /^`+/ {
        n = 0
        while (substr($0, n + 1, 1) == "`") n++
        if (n > longest) longest = n
      }
      END { print longest + 0 }
    ')
    width=3
    [ "$longest" -lt 3 ] || width=$((longest + 1))
    fence=$(awk -v w="$width" 'BEGIN { s = ""; while (length(s) < w) s = s "`"; print s }')
    printf 'content\t%s\t%s\t%s\n' "$item_id" "$source_note" "$truncated"
    printf '%s\n' "$fence"
    printf '%s\n' "$safe"
    printf '%s\n' "$fence"
    [ "$truncated" = no ] || printf 'content-truncated\t%s\t%s\n' "$item_id" "$Q_CONTENT_CAP"
  fi
fi

exit "$step_rc"
