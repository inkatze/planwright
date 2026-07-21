#!/bin/sh
# fleet-credit-continuation.sh — credit-continuation recovery at the
# rate-limit wall (fleet-autonomy Task 11; D-27, REQ-E1.11, REQ-E1.7,
# REQ-F1.3, REQ-F1.4, REQ-G1.2, REQ-G1.5).
#
# When Claude Code's rate-limit wall offers a CREDIT-CONTINUATION prompt —
# "spend credits / extra usage to continue past the limit" — the fleet's
# DEFAULT response is to decline and wait for the window to reset (the
# REQ-E1.7 reactive backstop already gives "wait for reset" a well-defined
# behavior to fall into, so decline-and-wait costs no new mechanism, D-27).
# Auto-spend is NEVER the shipped default: an irreversible, unattended money
# spend is exactly the class of act planwright reserves for the operator.
# Spending credits to continue requires EXPLICIT operator opt-in through the
# overlay (the fleet_credit_continuation_spend knob). This is a
# spend-AVOIDANCE default, distinct from a dollar-spend accounting ceiling
# (Out of scope): it neither meters nor caps spend, it only refuses to incur
# it without opt-in.
#
# RIDING THE REACTIVE WALL (REQ-E1.7). This helper is invoked on the SAME
# captured wall text the reactive throttle (fleet-throttle.sh observe) reads.
# A credit-continuation prompt is a VARIANT of the wall: it carries an
# explicit spend-to-continue offer that a plain rate-limit wall does not. The
# recognizer keys on that offer. Anything that is NOT a recognized
# credit-continuation offer — a plain wall, a garbled variant, unrelated text
# — is a clean no-op (exit 3), so the caller falls through to the plain
# reactive backstop with no accidental spend. The recognizer is deliberately
# precise: it first demands the SAME rate-limit-wall context the reactive
# throttle detects (a credit offer is a variant of the wall), then a
# spend-offer token (credit / extra usage / ...) AND a continuation token
# (continue / keep going) — the "spend ... to continue" shape. So a plain
# "rate limit reached", a bare "press enter to continue", or informational
# copy about extra usage that is NOT at the wall is never mistaken for a spend
# offer. A miss is the safe direction: it falls through to the reactive
# backstop (decline-and-wait), never a spurious spend.
#
# DETERMINISM FLOOR (REQ-G1.2). The decision is a pure, deterministic reaction
# to the detected prompt: no LLM/API call is ever in the decision path. The
# recognizer is awk over sanitized text; the decision is a config-knob read.
# This helper NEVER launches a session and so cannot engage Claude Code's
# `auto` permission mode (REQ-E1.4) — it makes no dispatch decision at all,
# only the decline/spend policy decision.
#
# DAEMON CONTRACT (REQ-F1.3, REQ-F1.4). Making the decision on a recognized
# prompt is an autonomous daemon action: it checks the operator kill-switch
# (fleet-daemon-gate.sh, D-15) before deciding — a set switch short-circuits
# (exit 1, no decision, no audit row) — and the decision (decline or spend)
# logs through the shared audit trail (fleet-audit.sh, D-16/REQ-F1.4) so "did
# the fleet spend credits" is answerable from a durable record. An
# audit-write failure is surfaced (exit 2), never swallowed. The gate and
# audit run only on a RECOGNIZED prompt; an unrecognized text takes neither
# (exit 3 is a pure read, like fleet-throttle observe's no-signal path).
#
# PARSE DISCIPLINE (the echo discipline; doctrine/security-posture.md).
# Captured pane text is untrusted terminal output: it is bounded (64 KiB) and
# every line is stripped of non-printable bytes BEFORE recognition, and only
# a sanitized excerpt reaches a diagnostic or the audit trail — a traversal
# token, an embedded escape sequence, or a control byte can neither drive the
# terminal nor tear the audit record.
#
# Usage:
#   fleet-credit-continuation.sh decide
#       Read captured wall text on stdin. Not a credit-continuation prompt:
#       exit 3 (clean no-op — the caller falls through to the reactive
#       backstop). Recognized: gate the kill-switch, resolve the opt-in knob,
#       decide, audit, and print `decision<TAB>decline` or
#       `decision<TAB>spend` on stdout; exit 0. Kill-switch set: exit 1.
#
# Exit codes: 0 recognized (decision made and audited); 1 kill-switch
# short-circuit; 2 usage error, unresolvable home, corrupt state, or a
# lock/audit failure; 3 no credit-continuation prompt in the observed text
# (fall through to the reactive backstop); 4/5 propagated from the kill-switch
# gate OR the knob resolver (malformed shared config / broken install — fail
# closed; a malformed repo-tracked fleet_credit_continuation_spend therefore
# halts the decision rather than guessing, by the customization-overlay
# REQ-E1.4 by-layer policy).
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling): awk
# without interval expressions. No eval, no jq (REQ-K1.5). All input is data.
# Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

GATE="$script_dir/fleet-daemon-gate.sh"
AUDIT="$script_dir/fleet-audit.sh"
RESOLVER="$script_dir/resolve-config-knob.sh"

MECHANISM=credit-continuation

usage() {
  echo "usage: fleet-credit-continuation.sh decide" >&2
}

[ "$#" -ge 1 ] || {
  usage
  exit 2
}
cmd=$1
shift

case "$cmd" in
  decide)
    [ "$#" -eq 0 ] || {
      usage
      exit 2
    }

    # Recognize the credit-continuation offer over the untrusted captured
    # text. Bound the stream first (an unbounded accumulator is a memory
    # hazard on hostile input), strip non-printable bytes per line (the awk
    # [[:print:]] form of the echo discipline), join, lowercase, then demand
    # BOTH a spend-offer token AND a continuation token — the "spend ... to
    # continue" shape. Output protocol: line 1 = `credit` | `none`; line 2
    # (when `credit`) = a <=200-char sanitized excerpt for the audit trigger.
    parse=$(head -c 65536 | awk '
      { gsub(/[^[:print:]]/, ""); text = text " " $0 }
      END {
        lt = tolower(text)
        # A credit-continuation offer is a VARIANT OF THE WALL: recognition
        # first demands the same rate-limit-wall context the reactive throttle
        # detects (fleet-throttle.sh observe), so informational copy that
        # merely mentions "extra usage" and "continue" off the wall is never
        # mistaken for an actionable spend prompt. Then it demands both a
        # spend-offer token and a continuation token — the "spend ... to
        # continue" shape. A miss here is the safe direction: it falls through
        # to the reactive backstop (decline-and-wait), never a spurious spend.
        wall  = (lt ~ /rate.?limit|usage limit|limit reached|too many requests/)
        offer = (lt ~ /credit|extra usage|extra paid usage|additional usage|pay.as.you.go/)
        cont  = (lt ~ /continue|keep going|keep working/)
        if (wall && offer && cont) { print "credit"; print substr(text, 2, 200); exit }
        print "none"
      }') || {
      echo "fleet-credit-continuation: recognizer failed" >&2
      exit 2
    }
    kind=$(printf '%s\n' "$parse" | head -n 1)
    excerpt=$(printf '%s\n' "$parse" | sed -n '2p')
    [ -n "$excerpt" ] || excerpt="credit-continuation prompt (no excerpt)"

    case "$kind" in
      none)
        # Not a credit-continuation offer: a clean no-op, so the caller falls
        # through to the plain reactive backstop (fleet-throttle observe) with
        # no accidental spend. No gate, no audit — nothing was decided.
        exit 3
        ;;
      credit) ;;
      *)
        echo "fleet-credit-continuation: internal recognizer protocol error" >&2
        exit 2
        ;;
    esac

    # A recognized offer means we are about to take a daemon action (decide +
    # audit). Gate the operator kill-switch first (D-15): only exit 0
    # authorizes proceeding; 1 is the set switch (short-circuit, no decision,
    # no audit row); 4/5 are resolver hard-fails — all propagate. A missing
    # gate helper is a broken install (exit 5), matching the sibling scripts'
    # posture rather than an undocumented 127.
    if [ ! -x "$GATE" ]; then
      echo "fleet-credit-continuation: daemon gate '$GATE' is missing or not executable — broken install" >&2
      exit 5
    fi
    "$GATE" "$MECHANISM"
    gate_rc=$?
    if [ "$gate_rc" -ne 0 ]; then
      exit "$gate_rc"
    fi

    # Resolve the opt-in knob. --fallback false is the fail-safe direction: a
    # knob absent from every layer (broken/partial install) lands on decline,
    # never an unattended spend. A malformed team-shared value is a hard-fail
    # (exit 4), a broken install exit 5 — both propagate (never spend under
    # unknown configuration).
    if [ ! -x "$RESOLVER" ]; then
      echo "fleet-credit-continuation: knob resolver '$RESOLVER' is missing or not executable — broken install" >&2
      exit 5
    fi
    spend=""
    rc=0
    spend=$("$RESOLVER" --key fleet_credit_continuation_spend --type enum --values 'true false' --fallback false) || rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "fleet-credit-continuation: could not resolve fleet_credit_continuation_spend (exit $rc) — declining to spend under unknown configuration (fail closed)" >&2
      exit "$rc"
    fi

    if [ "$spend" = true ]; then
      action=spend
      reasoning="credit-continuation offer detected; permitted credit spend to continue (operator opt-in fleet_credit_continuation_spend=true)"
    else
      action=decline
      reasoning="credit-continuation offer detected; declined by default (spend-avoidance); waiting for the rate-limit window to reset via the reactive backstop (REQ-E1.7)"
    fi

    # Audit the decision (REQ-F1.4). A refused record is surfaced (exit 2),
    # never swallowed — an unrecorded spend/decline decision is exactly what
    # the trail exists to prevent.
    if [ ! -x "$AUDIT" ]; then
      echo "fleet-credit-continuation: audit helper '$AUDIT' is missing or not executable — broken install" >&2
      exit 5
    fi
    "$AUDIT" record "$MECHANISM" "$action" "$excerpt" "$reasoning" || {
      echo "fleet-credit-continuation: the audit trail refused the $action record — surfacing, not swallowing" >&2
      exit 2
    }

    printf 'decision\t%s\n' "$action"
    ;;

  *)
    usage
    exit 2
    ;;
esac
