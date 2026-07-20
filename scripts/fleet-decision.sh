#!/bin/sh
# fleet-decision.sh — the structured worker-to-tower DECISION CHANNEL's
# answer + delivery half (fleet-hardening Task 4; D-4, REQ-A1.4, REQ-A1.5,
# REQ-E1.3).
#
# The channel has two halves. The WRITE + atomic-claim half lives in the store
# authority (scripts/fleet-attention.sh `fork` / `claim`), so the record layout
# and the first-answer-wins close stay under the one store lock. THIS script is
# the higher-level channel that COMPOSES them: it answers an answerable fork BY
# LABEL and delivers the answer DOWNWARD to the parked worker through the
# existing attributed buffer-paste / structured-marker path
# (scripts/orchestrate-relay.sh) — NEVER a `send-keys` menu-navigation path
# (REQ-A1.5: no impersonation of the worker's input, immune to menu reordering).
#
# Subcommand:
#   fleet-decision.sh answer <backend> <handle> <worker> <instance-id> <label>
#       Claim the worker's answerable fork by <label> under the store lock
#       (fleet-attention.sh claim: first-answer-wins, stale/invalid-label/
#       permission-park refusals), then — only on a successful claim — write the
#       chosen option as a structured-marker answer artifact and emit the
#       attributed buffer-paste delivery command for <handle> (orchestrate-relay
#       .sh relay-command). Prints the delivery command(s) on stdout for the
#       tower to run. The handle is validated BEFORE the claim, so a bad target
#       never closes a fork it cannot deliver to. Exit codes:
#         0 — the answer was claimed and the delivery command emitted.
#         2 — usage, a malformed handle, or a malformed/unresolvable claim input
#             (propagated from `claim`); nothing was consumed.
#         3 — the claim was REFUSED (stale / bad label / already-claimed /
#             permission-park); nothing was consumed, the fork is untouched.
#         4 — the claim SUCCEEDED (the answer is consumed and the fork closed
#             first-answer-wins) but the downward delivery could not be completed.
#             Two sub-cases, distinguished by the stderr message: (i) the artifact
#             WAS persisted at <fleet-home>/attention/answers/<worker> and only
#             the relay emit failed — the tower recovers by re-emitting from that
#             artifact (never re-claim, the record is closed); (ii) an earlier fs
#             / home-resolution failure closed the fork but persisted NOTHING —
#             the answer is lost, so the operator clears the worker's record to
#             re-ask. Either way the fork is already closed; never re-claim.
#
# What this script NEVER does, by construction (REQ-A1.5, REQ-E1.3): it never
# emits a `send-keys` path (delivery is delegated wholesale to orchestrate-relay
# .sh, which is `send-keys`-free by construction and tested so), never answers a
# worker's harness permission prompt (claim refuses a permission-park record),
# and never invokes a model / network call — the answer is selected by exact
# label match in pure awk, no eval.
#
# Portable POSIX sh (bash 3.2 / BSD compatible): no eval, no bashisms, all input
# is data (REQ-K1.5). Pathname expansion is disabled (set -f): valid_text admits
# glob metacharacters in a label, so this closes any future unquoted-expansion
# surface as a defense-in-depth (matching fleet-attention.sh's `set -uf`).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=fleet-decision

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
echo_safety="$script_dir/echo-safety.sh"
if [ ! -r "$echo_safety" ]; then
  echo "$me: required helper $echo_safety missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$echo_safety"

FA="$script_dir/fleet-attention.sh"
FS="$script_dir/fleet-state.sh"
RELAY="$script_dir/orchestrate-relay.sh"

for _dep in "$FA" "$FS" "$RELAY"; do
  [ -x "$_dep" ] || {
    echo "$me: required sibling '$_dep' is missing or not executable" >&2
    exit 2
  }
done

cmd="${1:-}"
if [ -z "$cmd" ]; then
  echo "usage: $me answer <backend> <handle> <worker> <instance-id> <label>" >&2
  exit 2
fi
shift || true

case $cmd in
  answer)
    backend="${1:-}"
    handle="${2:-}"
    worker="${3:-}"
    instance="${4:-}"
    label="${5:-}"
    if [ -z "$backend" ] || [ -z "$handle" ] || [ -z "$worker" ] \
      || [ -z "$instance" ] || [ -z "$label" ]; then
      echo "usage: $me answer <backend> <handle> <worker> <instance-id> <label>" >&2
      exit 2
    fi
    # Validate the delivery target BEFORE the claim (a read-only check, no store
    # mutation): a claim closes the fork first-answer-wins, so a target we cannot
    # deliver to must be refused before we consume the answer. orchestrate-relay
    # owns the per-backend handle grammar; reuse it rather than re-deriving.
    if ! "$RELAY" validate-handle "$backend" "$handle" >/dev/null 2>&1; then
      echo "$me: refusing an invalid $(sanitize_printable "$backend" "(backend)") handle '$(sanitize_printable "$handle" "(handle)")' before answering" >&2
      exit 2
    fi
    # Atomic claim by label under the store lock (first-answer-wins). Its stderr
    # already diagnoses the refusal class; PROPAGATE its exit code faithfully — 2
    # for a malformed input / lock error (nothing consumed), 3 for a semantic
    # refusal (nothing consumed) — rather than flattening both to 3. matched is
    # the canonical option label the record carries. Everything BELOW this point
    # runs after the fork is already closed, so its failures are exit 4 (consumed
    # -but-undelivered), never a claim-refusal 3.
    matched=$("$FA" claim "$worker" "$instance" "$label")
    claim_rc=$?
    if [ "$claim_rc" -ne 0 ]; then
      exit "$claim_rc"
    fi
    # The claim succeeded, so worker is a validated handle (no path separator,
    # control byte, or whitespace) safe to use as a per-worker artifact basename.
    # These pre-commit failures leave the fork CLOSED but NO artifact persisted
    # (the mv below is the commit point), so the answer is lost — the operator
    # clears the worker's record to re-ask, NOT "recover from a persisted answer".
    root=$("$FS" root) || {
      echo "$me: could not resolve the fleet home (fork already closed, answer NOT persisted — clear the worker's record to re-ask)" >&2
      exit 4
    }
    answers_dir="$root/attention/answers"
    if ! mkdir -p "$answers_dir" 2>/dev/null; then
      echo "$me: cannot create the answers dir $(sanitize_printable "$answers_dir" "(dir)") (fork already closed, answer NOT persisted — clear the record to re-ask)" >&2
      exit 4
    fi
    answer_file="$answers_dir/$worker"
    # The structured-marker answer artifact: a fixed marker naming the instance
    # id and the chosen option LABEL (not a menu position). The tower's paste
    # command reads this file as DATA, so the marker is delivered verbatim,
    # attributed by orchestrate-relay's header. Temp + rename so a reader never
    # sees a half-written artifact (the atomic-write discipline).
    tmp_ans=$(mktemp "$answers_dir/.answer.XXXXXX") || {
      echo "$me: could not stage the answer artifact (fork already closed, answer NOT persisted — clear the record to re-ask)" >&2
      exit 4
    }
    if ! printf 'planwright-decision-answer instance=%s option=%s\n' "$instance" "$matched" >"$tmp_ans"; then
      rm -f "$tmp_ans" 2>/dev/null
      echo "$me: could not write the answer artifact (fork already closed, answer NOT persisted — clear the record to re-ask)" >&2
      exit 4
    fi
    if ! mv -f "$tmp_ans" "$answer_file"; then
      rm -f "$tmp_ans" 2>/dev/null
      echo "$me: could not commit the answer artifact (fork already closed, answer NOT persisted — clear the record to re-ask)" >&2
      exit 4
    fi
    # Emit the attributed buffer-paste delivery for the tower to run. NEVER
    # send-keys — orchestrate-relay guarantees the buffer-paste / structured
    # -marker path by construction. Its stdout is the command(s) to deliver the
    # answer artifact to the parked worker. On failure the answer is already
    # persisted at $answer_file, so the tower re-emits the delivery from it (exit
    # 4, consumed-but-undelivered) — it must NOT re-claim the closed fork.
    if ! "$RELAY" relay-command "$backend" "$handle" "$answer_file"; then
      echo "$me: the answer was claimed and persisted at $(sanitize_printable "$answer_file" "(file)") but the delivery command could not be emitted; re-emit from that artifact (do not re-claim)" >&2
      exit 4
    fi
    exit 0
    ;;

  *)
    echo "$me: unknown command '$(sanitize_printable "$cmd" "(unprintable command)")' (answer)" >&2
    exit 2
    ;;
esac
