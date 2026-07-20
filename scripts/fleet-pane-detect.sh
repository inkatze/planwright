#!/bin/sh
# fleet-pane-detect.sh — the fallback pane-state detector (fleet-hardening
# Task 3; D-3, REQ-A1.3, REQ-E1.3).
#
# The RECONCILE BACKSTOP to the D-2 attention push. For dispatch backends that
# cannot register hooks — or where a registered hook has not pushed within a
# bounded reconcile interval (the registered-but-non-firing case) — this
# detector classifies a worker's tmux pane. It is NEVER the primary path where a
# fresh hook push exists: that is the deterministic push's job (fleet-autonomy
# D-1's push-first / reconcile-backstop pattern, carried by D-3). Where a fresh
# push is present in the attention store the detector DEFERS.
#
# It codifies, once, the pane discipline every tower otherwise re-derives — and
# each ad-hoc re-derivation regressed:
#   - the 2026-07-19 scrollback false-match (a whole-pane busy matcher matching
#     `esc to interrupt` quoted in the scrollback of an idle session), and
#   - the 2026-07-18 background-agent false-idle (an absence-of-`esc to
#     interrupt` check with no positive discipline reading a main-idle /
#     background-busy pane as idle).
# The three rules that kill both, applied to EVERY classification:
#   (a) read ONLY the bounded footer region, never the full scrollback;
#   (b) require a POSITIVE at-prompt anchor AND the ABSENCE of every busy marker
#       to call idle — a blank / loading / mid-render pane is `indeterminate`,
#       never idle (a starting-up worker is never misread as idle-at-fork);
#   (c) DEBOUNCE across at least two consecutive frames before a classification
#       flips, so a single-frame flap is suppressed.
#
# The decision path is purely deterministic string / arithmetic work over the
# captured pane and the attention store — no model, no API, no network call
# (REQ-E1.3). It is a pure detector: it prints its verdict and never mutates the
# attention store or drives any downstream action (the caller — the reconcile
# sweep or a tower — decides what to do with `idle` / `busy` / `indeterminate`).
#
# Usage:
#   fleet-pane-detect.sh classify --pane <file> --backend <b> --worker <w> \
#       [--scope <s>] [--root <dir>] [--reconcile-ttl <sec>] [--now <epoch>] \
#       [--state-dir <dir>] [--footer-lines <n>]
#
#     --pane <file>          captured pane text to classify (required)
#     --backend <b>          dispatch backend: tmux | subagent | print |
#                            in-session (required). Only a push-capable backend
#                            (tmux) is gated on the store; the others cannot
#                            register a hook, so the detector always runs.
#     --worker <w>           worker handle (required) — keys the store row and
#                            the debounce state.
#     --scope <s>            worker scope (default `-`) — part of the debounce
#                            state key.
#     --root <dir>           fleet-home root holding attention/state; default
#                            resolved via fleet-state.sh root. Only consulted
#                            for a push-capable backend's freshness gate.
#     --reconcile-ttl <sec>  the bounded reconcile interval: a store heartbeat
#                            younger than this counts as a fresh push and the
#                            detector defers (default: the
#                            fleet_reconcile_interval_seconds knob, else 120).
#     --now <epoch>          the reference time for the freshness gate (default:
#                            the wall clock) — a test / determinism hook.
#     --state-dir <dir>      where the two-frame debounce state persists
#                            (default: <root>/liveness/pane-detect).
#     --footer-lines <n>     the bounded footer window height in lines (default
#                            8) — large enough to reach the running-turn spinner
#                            line that sits just above the input box (~5 lines
#                            up), small enough to exclude the scrollback above.
#
#   Prints exactly one token to stdout and exits 0 on a normal classification:
#     defer-to-push  a fresh hook push exists; the detector yields (D-3 backstop
#                    boundary — never the primary path where a push exists).
#     pending        the debounce floor is not yet met (the first frame, or a
#                    flap that has not repeated) — no confirmed verdict yet.
#     idle           positive at-prompt anchor present AND no busy marker.
#     busy           a busy marker present in the footer region.
#     indeterminate  neither a busy marker nor a positive anchor — NOT idle.
#
#   Exit codes: 0 success; 2 usage / environment error.
#
# Runs under /bin/sh (the POSIX / dash floor). No `set -e`: errors are handled
# explicitly with exit codes, the house pattern for these fleet scripts.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FL="$here/fleet-liveness.sh"
FS="$here/fleet-state.sh"
RCK="$here/resolve-config-knob.sh"

# The canonical echo-discipline sanitizer, sourced the way fleet-liveness.sh
# does: caller-controlled values (pane path, backend, handles) are wrapped in
# sanitize_printable before reaching stderr, so a crafted argument cannot inject
# terminal escapes into an operator's display (doctrine/security-posture.md).
# shellcheck source=scripts/echo-safety.sh
. "$here/echo-safety.sh"

usage() {
  echo "usage: fleet-pane-detect.sh classify --pane <file> --backend <b> --worker <w> [--scope <s>] [--root <dir>] [--reconcile-ttl <sec>] [--now <epoch>] [--state-dir <dir>] [--footer-lines <n>]" >&2
  exit 2
}

# valid_field <value> — the fleet field grammar (fleet-liveness.sh valid_field):
# non-empty, not `.`/`..`, only [A-Za-z0-9._=@:-], at most 128 chars. A worker /
# scope carrying a tab, newline, or control char would silently break the
# tab-delimited store lookup and the state-file key; reject it up front.
valid_field() {
  vf_v=$1
  case $vf_v in
    "" | . | .. | *[!A-Za-z0-9._=@:-]*) return 1 ;;
  esac
  [ "${#vf_v}" -le 128 ]
}

# ---------------------------------------------------------------------------
# The codified marker vocabulary. This is the SINGLE point a tower updates if
# the Claude Code TUI footer text changes — the whole value of codifying the
# detector once (D-3) instead of every tower re-deriving a fragile heuristic.
#
# Busy markers (case-insensitive substring, matched in the footer region only):
#   - `esc to interrupt`  — the running-turn spinner line of the MAIN agent;
#     it always co-occurs with the animated spinner gerund, so matching it
#     subsumes the spinner-word case for the main agent;
#   - `background agent` / `to manage` — the background-agent busy footer
#     (`Waiting for N background agents… (ctrl+b to manage)`), which carries NO
#     `esc to interrupt`, so it must be matched independently (the 2026-07-18
#     false-idle);
#   - the spinner gerunds below — belt-and-suspenders for a spinner line whose
#     `esc to interrupt` clause has scrolled or wrapped off the captured frame.
# Positive at-prompt anchors (case-insensitive substring, footer region only):
#   the stable idle-footer tokens of a worker launched in auto / bypass mode.
#   Override the anchor set for a bespoke TUI via FLEET_PANE_PROMPT_ANCHORS
#   (a newline-separated list); unset falls back to the codified default.
# ---------------------------------------------------------------------------
busy_markers() {
  cat <<'EOF'
esc to interrupt
background agent
to manage
EOF
}
spinner_words() {
  cat <<'EOF'
thinking…
cogitating…
simmering…
pondering…
puzzling…
herding…
noodling…
working…
churning…
computing…
EOF
}
default_prompt_anchors() {
  cat <<'EOF'
? for shortcuts
auto mode on
auto-accept edits
bypass permissions
bypassing permissions
plan mode on
EOF
}
# prompt_anchors — emit the anchor needles, always lowercased. raw_classify
# lowercases the haystack, so the needles must be lowercase too; folding here (a
# harmless passthrough for the already-lowercase default) means a mixed-case
# FLEET_PANE_PROMPT_ANCHORS override matches instead of silently never matching.
prompt_anchors() {
  if [ -n "${FLEET_PANE_PROMPT_ANCHORS:-}" ]; then
    printf '%s\n' "$FLEET_PANE_PROMPT_ANCHORS" | tr '[:upper:]' '[:lower:]'
  else
    default_prompt_anchors
  fi
}

# contains_any <haystack-lowercased> <needle-list-on-stdin> — 0 iff any
# non-empty needle is a substring of the haystack. Case folding is the caller's
# job (needles are already lowercase); the sh `case` glob does the substring
# test, so no regex metacharacter in a needle is ever interpreted.
contains_any() {
  ca_hay="$1"
  while IFS= read -r ca_needle; do
    [ -n "$ca_needle" ] || continue
    case "$ca_hay" in
      *"$ca_needle"*) return 0 ;;
    esac
  done
  return 1
}

# raw_classify <footer-region-text> — echo idle | busy | indeterminate from the
# footer region ALONE. Busy takes precedence: a busy marker present is busy
# regardless of any anchor. Idle requires a positive anchor AND no busy marker.
# Anything else (no busy marker, no anchor — a blank / loading / mid-render
# pane) is indeterminate, never idle.
raw_classify() {
  rc_footer_lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s\n' "$(busy_markers)" | { contains_any "$rc_footer_lc"; }; then
    echo busy
    return 0
  fi
  if printf '%s\n' "$(spinner_words)" | { contains_any "$rc_footer_lc"; }; then
    echo busy
    return 0
  fi
  if printf '%s\n' "$(prompt_anchors)" | { contains_any "$rc_footer_lc"; }; then
    echo idle
    return 0
  fi
  echo indeterminate
}

# fresh_push_exists <root> <worker> <now> <ttl> — 0 iff the attention store
# holds a row for <worker> whose heartbeat (the commit-time push timestamp) is
# younger than <ttl> seconds relative to <now>. Empty return / missing store /
# corrupt or leading-zero-octal timestamp / an age at-or-beyond the TTL all mean
# "no fresh push" (return 1) — the detector then runs as the backstop. We fail
# TOWARD running the detector, never toward blindness (a push written before the
# watch was established, or a dead watch, degrades to poll-latency — Task 2's
# liveness contract), so absence of push evidence runs the detector.
fresh_push_exists() {
  fpe_root="$1"
  fpe_store="$fpe_root/attention/state"
  [ -f "$fpe_store" ] && [ -r "$fpe_store" ] || return 1
  # Read the heartbeat field (4) with the same awk idiom fleet-liveness.sh's
  # store_row_field uses — string-forced key comparison (`($1 "") == (w "")`) so
  # a numeric-looking handle is not strnum-matched. The field index is re-stated
  # here (store_row_field is an internal function, not a callable entry point);
  # it must track fleet-liveness.sh FIELD_HEARTBEAT=4 / fleet-attention.sh's row
  # layout (worker·scope·state·heartbeat·…).
  fpe_hb=$(awk -F "$(printf '\t')" -v w="$2" \
    '($1 "") == (w "") { v = $4; found = 1 } END { if (found) print v }' \
    "$fpe_store" 2>/dev/null) || return 1
  case $fpe_hb in
    "" | *[!0-9]* | 0?*) return 1 ;;
  esac
  fpe_age=$(($3 - fpe_hb))
  # Fresh iff the age is in [0, ttl). A NEGATIVE age (a heartbeat later than
  # --now: clock skew or a corrupt future timestamp) is not evidence of a fresh
  # push — treating it as fresh would defer indefinitely until real time catches
  # up, exactly the silent-blindness the backstop exists to prevent. Fail toward
  # running the detector.
  [ "$fpe_age" -ge 0 ] 2>/dev/null || return 1
  [ "$fpe_age" -lt "$4" ] 2>/dev/null || return 1
  return 0
}

# knob <name> <default> — read a positive-integer config knob through the shared
# resolve-config-knob.sh resolver (the fleet-liveness.sh convention), else the
# default. Kept tolerant: a missing / erroring resolver never blocks the
# detector — it falls back to the passed default.
knob() {
  kb_val=""
  if [ -x "$RCK" ]; then
    kb_val=$("$RCK" --key "$1" --type posint --fallback "$2" 2>/dev/null) || kb_val=""
  fi
  case $kb_val in
    "" | *[!0-9]*) printf '%s' "$2" ;;
    *) printf '%s' "$kb_val" ;;
  esac
}

cmd="${1:-}"
[ "$cmd" = classify ] || usage
shift

pane=""
backend=""
worker=""
scope="-"
root=""
reconcile_ttl=""
now=""
state_dir=""
footer_lines=8

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pane)
      [ "$#" -ge 2 ] || usage
      pane="$2"
      shift 2
      ;;
    --backend)
      [ "$#" -ge 2 ] || usage
      backend="$2"
      shift 2
      ;;
    --worker)
      [ "$#" -ge 2 ] || usage
      worker="$2"
      shift 2
      ;;
    --scope)
      [ "$#" -ge 2 ] || usage
      scope="$2"
      shift 2
      ;;
    --root)
      [ "$#" -ge 2 ] || usage
      root="$2"
      shift 2
      ;;
    --reconcile-ttl)
      [ "$#" -ge 2 ] || usage
      reconcile_ttl="$2"
      shift 2
      ;;
    --now)
      [ "$#" -ge 2 ] || usage
      now="$2"
      shift 2
      ;;
    --state-dir)
      [ "$#" -ge 2 ] || usage
      state_dir="$2"
      shift 2
      ;;
    --footer-lines)
      [ "$#" -ge 2 ] || usage
      footer_lines="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

[ -n "$pane" ] || usage
[ -n "$backend" ] || usage
[ -n "$worker" ] || usage
case $footer_lines in
  "" | *[!0-9]* | 0) footer_lines=8 ;;
esac

# Validate the caller-controlled handles against the fleet field grammar before
# they key a store lookup or a state filename (a tab / newline / control char
# would silently break both). Same discipline as fleet-liveness.sh.
valid_field "$worker" || {
  echo "fleet-pane-detect: refusing malformed worker handle '$(sanitize_printable "$worker" "(unprintable worker)")'" >&2
  exit 2
}
valid_field "$scope" || {
  echo "fleet-pane-detect: refusing malformed scope '$(sanitize_printable "$scope" "(unprintable scope)")'" >&2
  exit 2
}

[ -f "$pane" ] && [ -r "$pane" ] || {
  echo "fleet-pane-detect: pane file not readable: $(sanitize_printable "$pane" "(unprintable path)")" >&2
  exit 2
}

# --- Backstop gate: defer where a fresh hook push exists (D-3 boundary) -----
# Only a push-capable backend can register a hook, so only it is gated. The
# capability is single-sourced from fleet-liveness.sh push-capable (exit 0 =>
# push-capable/tmux; exit 1 => observe-only/hook-less; exit 2 => unknown).
push_capable=1
if [ -x "$FL" ]; then
  "$FL" push-capable "$backend" >/dev/null 2>&1
  push_capable=$?
else
  # No liveness helper to consult — assume hook-capable only for the known
  # push backend, so the freshness gate still applies to a real tmux worker.
  case "$backend" in
    tmux) push_capable=0 ;;
    subagent | print | in-session) push_capable=1 ;;
    *)
      echo "fleet-pane-detect: unknown backend '$(sanitize_printable "$backend" "(unprintable backend)")' (tmux|subagent|print|in-session)" >&2
      exit 2
      ;;
  esac
fi
case $push_capable in
  0) ;; # push-capable — apply the freshness gate below
  1) ;; # hook-less — the detector is the primary path; skip the gate
  *)
    echo "fleet-pane-detect: unknown backend '$(sanitize_printable "$backend" "(unprintable backend)")' (tmux|subagent|print|in-session)" >&2
    exit 2
    ;;
esac

if [ "$push_capable" -eq 0 ]; then
  # Resolve the reference time and the reconcile TTL, then check the store.
  case $now in
    "" | *[!0-9]*) now=$(date +%s 2>/dev/null) || now="" ;;
  esac
  case $reconcile_ttl in
    "" | *[!0-9]*) reconcile_ttl=$(knob fleet_reconcile_interval_seconds 120) ;;
  esac
  # Resolve the fleet root if not given (best-effort; absence => no fresh push).
  if [ -z "$root" ] && [ -x "$FS" ]; then
    root=$("$FS" root 2>/dev/null) || root=""
  fi
  if [ -n "$root" ] && [ -n "$now" ] && fresh_push_exists "$root" "$worker" "$now" "$reconcile_ttl"; then
    echo defer-to-push
    exit 0
  fi
fi

# --- Footer-region extraction (bounded; scrollback excluded) ----------------
# stdin redirection (not `tail … -- "$pane"`) reads the bounded footer without
# relying on `--` end-of-options support and with no option-injection surface;
# $pane was already confirmed readable above.
footer=$(tail -n "$footer_lines" <"$pane" 2>/dev/null) || footer=""

raw=$(raw_classify "$footer")

# --- Two-frame debounce -----------------------------------------------------
# State persists the previous frame's raw class and the last CONFIRMED class.
# A class becomes confirmed only when it equals the immediately previous frame's
# raw class (two consecutive agreeing frames). A frame that disagrees with the
# previous frame keeps the last confirmed class (flap suppressed) and prints it;
# with no confirmed class yet the output is `pending`.
if [ -z "$state_dir" ]; then
  if [ -n "$root" ]; then
    state_dir="$root/liveness/pane-detect"
  else
    state_dir="${TMPDIR:-/tmp}/fleet-pane-detect"
  fi
fi
mkdir -p "$state_dir" 2>/dev/null || {
  echo "fleet-pane-detect: cannot create the debounce state dir $(sanitize_printable "$state_dir" "(unprintable dir)")" >&2
  exit 2
}
# Key the state file by scope+worker. A readable sanitized prefix aids
# debugging, but sanitizing alone collides (slash-style handles like
# `spec/task-3` fold `/` to `_`, and a literal `__` in either component is
# ambiguous), so a cksum of the raw, newline-delimited pair disambiguates every
# distinct (scope,worker) — the newline can never appear in either component, so
# the hashed input is unambiguous.
key_prefix=$(printf '%s' "$worker" | tr -c 'A-Za-z0-9._-' '_')
key_hash=$(printf '%s\n%s\n' "$scope" "$worker" | cksum | cut -d' ' -f1)
key="$key_prefix-$key_hash"
state_file="$state_dir/$key"

prev_raw=""
confirmed=""
if [ -f "$state_file" ] && [ -r "$state_file" ]; then
  # One read of the two-line state file (line 1: previous raw class; line 2:
  # last confirmed class), no per-line fork.
  {
    IFS= read -r prev_raw || prev_raw=""
    IFS= read -r confirmed || confirmed=""
  } <"$state_file" 2>/dev/null || {
    prev_raw=""
    confirmed=""
  }
fi
# Shape-guard both values read from disk: only the known raw classes (and empty)
# are legal. A torn or externally tampered state file must never let an
# arbitrary string reach stdout as a verdict — coerce anything else to empty,
# which the debounce treats as "no prior state" (a `pending` frame, self-heals).
case $prev_raw in idle | busy | indeterminate | "") ;; *) prev_raw="" ;; esac
case $confirmed in idle | busy | indeterminate | "") ;; *) confirmed="" ;; esac

if [ "$raw" = "$prev_raw" ] && [ -n "$prev_raw" ]; then
  confirmed="$raw"
fi

# Persist the new state atomically (same-dir temp + rename).
state_tmp=$(mktemp "$state_dir/.tmp.XXXXXX" 2>/dev/null) || {
  echo "fleet-pane-detect: cannot create a temp file under $(sanitize_printable "$state_dir" "(unprintable dir)")" >&2
  exit 2
}
if ! printf '%s\n%s\n' "$raw" "$confirmed" >"$state_tmp"; then
  rm -f "$state_tmp" 2>/dev/null
  echo "fleet-pane-detect: failed to write the debounce state" >&2
  exit 2
fi
if ! mv -f "$state_tmp" "$state_file"; then
  rm -f "$state_tmp" 2>/dev/null
  echo "fleet-pane-detect: failed to commit the debounce state" >&2
  exit 2
fi

if [ -n "$confirmed" ]; then
  printf '%s\n' "$confirmed"
else
  printf 'pending\n'
fi
exit 0
