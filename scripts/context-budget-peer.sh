#!/bin/sh
# context-budget-peer.sh — the peer-pane `/context` context-budget
# CORROBORATION mechanism (fleet-autonomy Task 5: D-9, REQ-C1.1, REQ-C1.2).
#
# The long-running tower's primary context-budget signal is the portable,
# version-stable completed-step-count proxy (context-budget-monitor.sh): Claude
# Code exposes no supported programmatic read of its own context-window usage.
# This mechanism adds a CORROBORATING direct signal ALONGSIDE that proxy — a
# peer pane running `/context`, capture-paned — never a replacement (D-9). The
# step-count proxy remains the fallback in every case; this mechanism only ever
# ADDS a second reading when it can, and otherwise hands the decision straight
# back to the proxy.
#
# Three floors keep it honest:
#   1. CAPABILITY-GATED. A peer observation pane is the backend-capability-
#      contract's `can_observe` capability (a capture-pane scrape of a running
#      session). The gate resolves that boolean through the shared advertisement
#      accessor (orchestrate-backends.sh caps <backend>, field 2) rather than
#      re-deriving the contract table. A backend that does not advertise it —
#      subagent, in-session, print, an unknown pluggable — reports the mechanism
#      ABSENT and the caller uses the step-count proxy (REQ-C1.1).
#   2. IDLE-ONLY. The check is only ATTEMPTED against an idle observed session.
#      A busy session (its render still showing Claude Code's "esc to interrupt"
#      working footer) is SKIPPED — never captured or parsed — so the mechanism
#      neither perturbs a working session nor reads a half-rendered `/context`
#      (REQ-C1.2). By design this fires once per idle transition, not
#      continuously while idle (kickoff risk row 15): the ONE first-class
#      poll-shaped mechanism, distinct from the fallback paths.
#   3. UNSTABLE-UI-TEXT, GRACEFUL DEGRADE. `/context`'s rendering is human-
#      oriented UI text with no cross-release stability guarantee, treated as an
#      unstable contract, never a stable API. A malformed/unexpected rendering
#      DEGRADES to the step-count proxy WITH A WARNING — never an opaque halt
#      (REQ-C1.2). The live parser is re-verified against Claude Code's current
#      `/context` output by the periodic [manual] check test-spec.md pins to
#      REQ-C1.1; this script owns only the decision + parse, not the drift.
#
# This mechanism does NOT nudge, clean up, restart, or throttle any resource, so
# it is not a "daemon action" under REQ-F1.4's enumeration and — like Task 6's
# ghost-text prevention — records nothing through the Task 1 audit trail (that
# trail records actions, not a read-only corroborating measurement; kickoff risk
# row 34).
#
# CAPTURE SEPARATION. The two live captures — the observed pane (for the idle
# classification) and the `/context` rendering (to parse) — are the caller's
# tmux `capture-pane` reads, passed in as files. Keeping the tmux mechanics with
# the caller (the tower already capture-panes for liveness) leaves THIS script a
# pure, portable, fixture-testable decision+parse function: the capability gate,
# the idle gate, and the parse-degrade contract are all exercised without a live
# tmux or a live Claude session (test-context-budget-peer.sh). The gate resolves
# BEFORE any observed-pane argument is required, so an incapable backend costs no
# capture (the "not attempted" guarantee).
#
# ECHO DISCIPLINE. Captured UI text is untrusted: any of it that reaches a
# diagnostic is stripped of C0/DEL/C1 control bytes first (echo-safety.sh, the
# same discipline Task 1's audit trail applies; kickoff risk row 23), so an
# embedded escape sequence in a `/context` render cannot drive the operator's
# terminal at warning time.
#
# Usage:
#   context-budget-peer.sh --backend <name> [--observed-pane <file>] \
#                          [--context-render <file>]
#
#   --backend <name>   the dispatch backend the observed session runs on
#                      (anchored identifier charset; validated before it reaches
#                      the caps accessor). REQUIRED.
#   --observed-pane <file>   a capture-pane read of the observed session's
#                      current render, for the idle/busy classification.
#                      Required once the capability gate passes.
#   --context-render <file>  a capture-pane read of the observed session's
#                      `/context` rendering, to parse. Required once the session
#                      is classified idle.
#
# stdout: exactly one verdict line —
#   corroborated <pct>      a direct signal was parsed; <pct> is context USED
#                           percent (0-100). Offer it alongside the proxy.
#   proxy capability-absent the backend has no peer-observation-pane capability.
#   proxy session-busy      the observed session is busy; not attempted.
#   proxy parse-degraded    the `/context` render was malformed; a warning was
#                           emitted on stderr; use the step-count proxy.
# In every `proxy ...` case the caller falls back to the step-count proxy.
#
# Exit: 0 on every graceful verdict above (this mechanism never halts opaquely,
# mirroring context-budget-monitor.sh); 2 usage error (missing/invalid argument
# or unreadable capture file — fail closed). Never fails opaquely.
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling). All input
# is data; no eval (REQ-K1.5). Pathname expansion is disabled (set -f): a
# backend token or captured line must never expand against the CWD.
set -uf

# Pin C so the [A-Za-z] ranges and the control-byte strip mean their ASCII
# ranges on every host (mirrors the sibling fleet scripts).
LC_ALL=C
export LC_ALL
# A CDPATH-resolved cd would echo its destination into the script-dir command
# substitution (house pattern).
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || {
  echo "context-budget-peer: cannot resolve the script directory" >&2
  exit 2
}

# The canonical echo-discipline sanitizer: captured UI text headed for a
# diagnostic is stripped of control bytes first.
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

usage() {
  echo "usage: context-budget-peer.sh --backend <name> [--observed-pane <file>] [--context-render <file>]" >&2
  exit 2
}

backend=""
observed_pane=""
context_render=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --backend)
      [ "$#" -ge 2 ] || usage
      backend=$2
      shift 2
      ;;
    --observed-pane)
      [ "$#" -ge 2 ] || usage
      observed_pane=$2
      shift 2
      ;;
    --context-render)
      [ "$#" -ge 2 ] || usage
      context_render=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

# --backend is mandatory and must match the anchored identifier charset BEFORE
# it is handed to the caps accessor (defense in depth: the accessor validates
# too, but a hostile token never reaches a subprocess argument unchecked).
[ -n "$backend" ] || usage
case "$backend" in
  '' | [!a-z0-9]* | *[!a-z0-9-]*) usage ;;
esac
[ "${#backend}" -le 64 ] || usage

# ---------------------------------------------------------------------------
# Floor 1 — capability gate. Resolve the backend's advertised can_observe
# (field 2 of the six-field caps string) through the shared accessor. Any
# outcome other than a clean can_observe=true — an incapable shipped backend,
# an unknown/adapterless pluggable (caps exits non-zero), or a caps helper that
# cannot be run — reports the mechanism ABSENT and hands the decision to the
# proxy. This resolves before --observed-pane is required, so an incapable
# backend costs no capture (the "not attempted" guarantee).
# ---------------------------------------------------------------------------
caps_helper="$script_dir/orchestrate-backends.sh"
can_observe=""
if [ -x "$caps_helper" ]; then
  caps_line=$("$caps_helper" caps "$backend" 2>/dev/null) || caps_line=""
  # Field 2 of "interactive can_observe can_steer ... session_grade".
  # shellcheck disable=SC2086
  set -- $caps_line
  can_observe=${2-}
fi
if [ "$can_observe" != true ]; then
  echo "proxy capability-absent"
  # printf, never echo, on any line carrying interpolated (even sanitized)
  # content — the XSI-echo backslash-reinterpretation guard (see the degrade
  # warning below; the orchestrate-backends.sh house pattern).
  printf '%s\n' "context-budget-peer: backend '$(sanitize_printable "$backend" "(unprintable)")' does not advertise a peer observation pane; using the step-count proxy" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# Floor 2 — idle gate. Need the observed pane to classify busy/idle. A busy
# session (Claude Code's "esc to interrupt" working footer present) is skipped,
# NOT attempted — the /context render is never read.
# ---------------------------------------------------------------------------
[ -n "$observed_pane" ] && [ -r "$observed_pane" ] || usage
pane_text=$(cat "$observed_pane") || usage
# Match the busy footer case-insensitively. tr lowercases; the sh `case` glob
# does the substring test. This is a UI-text heuristic (unstable, same class as
# the /context contract): its only failure mode is a mis-idle that then degrades
# at the parse step, never an opaque halt.
pane_lc=$(printf '%s' "$pane_text" | tr '[:upper:]' '[:lower:]')
case "$pane_lc" in
  *"esc to interrupt"*)
    echo "proxy session-busy"
    echo "context-budget-peer: observed session is busy; the /context corroboration is only attempted while idle; using the step-count proxy" >&2
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# Floor 3 — parse the /context render. Idle: the render is required. Extract the
# context USED percent; a malformed/unexpected rendering degrades to the proxy
# with a warning, never an opaque halt.
# ---------------------------------------------------------------------------
[ -n "$context_render" ] && [ -r "$context_render" ] || usage

# parse_context_used <render-file> — echo the context USED percent (an integer
# 0-100) on a recognized rendering, or return 1 when nothing parses. UI-text
# contract, re-verified by the [manual] check; two accepted forms:
#   - token-total form:  a line naming `token` with a parenthesized/bare `NN%`
#     — NN is the USED fraction (e.g. "120k/200k tokens (60%)" -> 60);
#   - auto-compact form: a line naming `auto-compact` with `NN%` — NN is
#     REMAINING until auto-compact, so used = 100 - NN.
#   A line phrased as remaining ("left"/"remaining"/"until") is normalized the
#   same way. First recognized line (top-to-bottom) wins.
# Every line is control-stripped before matching so a control byte can neither
# break the match nor survive into a later diagnostic.
parse_context_used() {
  _pc_used=""
  while IFS= read -r _pc_line || [ -n "$_pc_line" ]; do
    _pc_clean=$(printf '%s' "$_pc_line" | tr -d '\000-\037\177\200-\237')
    _pc_lc=$(printf '%s' "$_pc_clean" | tr '[:upper:]' '[:lower:]')
    # An anchor line must name a context-usage concept.
    case "$_pc_lc" in
      *token* | *auto-compact*) ;;
      *) continue ;;
    esac
    # First `NN%` on the line (grep -o keeps it POSIX-portable; head picks one).
    _pc_pct=$(printf '%s' "$_pc_lc" | grep -Eo '[0-9]+%' | head -n 1) || _pc_pct=""
    [ -n "$_pc_pct" ] || continue
    _pc_num=${_pc_pct%\%}
    # Strip leading zeros so the arithmetic below is decimal, never octal
    # (the context-budget-monitor.sh discipline); all-zeros -> 0.
    _pc_num=$(printf '%s' "$_pc_num" | sed 's/^0\{1,\}//')
    [ -n "$_pc_num" ] || _pc_num=0
    # A percent is 0-100; a bogus larger number is not a usable signal.
    [ "${#_pc_num}" -le 3 ] || continue
    [ "$_pc_num" -le 100 ] || continue
    case "$_pc_lc" in
      *left* | *remaining* | *until*) _pc_used=$((100 - _pc_num)) ;;
      *) _pc_used=$_pc_num ;;
    esac
    printf '%s\n' "$_pc_used"
    return 0
  done <"$1"
  return 1
}

if used=$(parse_context_used "$context_render"); then
  echo "corroborated $used"
  exit 0
fi

# Malformed/unexpected rendering. Degrade to the proxy WITH A WARNING (never an
# opaque halt). A short, sanitized snippet aids the [manual] format re-check
# without letting captured control bytes reach the terminal.
snippet=$(head -n 1 "$context_render" 2>/dev/null | cut -c1-80)
echo "proxy parse-degraded"
# printf, never echo: `sanitize_printable` strips control BYTES but not a
# literal backslash, and an XSI `echo` (/bin/sh = dash on Linux) would then
# re-interpret a captured `\033`/`\007` byte-sequence into a live escape,
# reopening the row-23 hole. `printf '%s\n'` emits the sanitized snippet
# verbatim on every host (the orchestrate-backends.sh house pattern).
printf '%s\n' "context-budget-peer: WARNING: could not parse the /context rendering (unstable UI-text contract); degrading to the step-count proxy. First line: $(sanitize_printable "$snippet" "(no printable content)")" >&2
exit 0
