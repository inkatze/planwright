#!/bin/sh
# fleet-pane-vocabulary.sh — the codified Claude Code TUI marker vocabulary
# and the footer classifier over it, SOURCED by every pane consumer
# (fleet-pane-detect.sh, fleet-stuck-detector.sh). This is the SINGLE point a
# tower updates if the TUI footer or dialog text changes — the whole value of
# codifying the pane discipline once (fleet-hardening D-3) instead of every
# consumer re-deriving a fragile heuristic; the platform-rendered surface it
# pins is a known fragility (fleet-lifecycle-closure kickoff risk row 2), so
# the live-CLI rehearsal is what catches a silent divergence, not a fixture.
#
# Busy markers (case-insensitive substring, matched in the footer region only):
#   - `esc to interrupt`  — the running-turn spinner line of the MAIN agent;
#     it always co-occurs with the animated spinner gerund, so matching it
#     subsumes the spinner-word case for the main agent;
#   - `background agent` / `to manage` — the background-agent busy footer
#     (`Waiting for N background agents… (ctrl+b to manage)`), which carries NO
#     `esc to interrupt`, so it must be matched independently (the 2026-07-18
#     false-idle);
#   - the spinner gerunds — belt-and-suspenders for a spinner line whose
#     `esc to interrupt` clause has scrolled or wrapped off the captured frame.
# Positive at-prompt anchors (case-insensitive substring, footer region only):
#   the stable idle-footer tokens of a worker launched in auto / bypass mode.
#   Override the anchor set for a bespoke TUI via FLEET_PANE_PROMPT_ANCHORS
#   (a newline-separated list); unset falls back to the codified default.
# Permission-prompt signatures (case-insensitive substring, bounded window):
#   the text of the harness permission dialog — the question line and the
#   fixed option labels — which is the ONE positive pane signal that a worker
#   is blocked on a human rather than mid-tool-call (fleet-lifecycle-closure
#   REQ-C1.2, obs:4c25e743). Verified against the installed CLI bundle at
#   2.1.260 (`strings` over the binary): the question is `Do you want to
#   proceed?` for every tool dialog, the option labels are `Yes, and don't
#   ask again for …`, `Yes, and always allow …`, `No, and tell Claude what to
#   do differently`; the older per-tool phrasings (`make this edit`, `create
#   <file>`) no longer exist and are deliberately not listed. Override via
#   FLEET_PANE_PROMPT_SIGNATURES, same shape as the anchor override.
#
# Every needle is matched as a plain substring through the sh `case` glob, so
# no regex metacharacter in a needle is ever interpreted; the caller lowercases
# the haystack once and the needle emitters lowercase their overrides, so a
# mixed-case override matches instead of silently never matching.

busy_markers() {
  cat <<'MARKERS'
esc to interrupt
background agent
to manage
MARKERS
}

spinner_words() {
  cat <<'WORDS'
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
WORDS
}

default_prompt_anchors() {
  cat <<'ANCHORS'
? for shortcuts
auto mode on
auto-accept edits
bypass permissions
bypassing permissions
plan mode on
ANCHORS
}

prompt_anchors() {
  if [ -n "${FLEET_PANE_PROMPT_ANCHORS:-}" ]; then
    printf '%s\n' "$FLEET_PANE_PROMPT_ANCHORS" | tr '[:upper:]' '[:lower:]'
  else
    default_prompt_anchors
  fi
}

default_permission_prompt_signatures() {
  cat <<'SIGNATURES'
do you want to proceed
and don't ask again
and always allow
what to do differently
SIGNATURES
}

permission_prompt_signatures() {
  if [ -n "${FLEET_PANE_PROMPT_SIGNATURES:-}" ]; then
    printf '%s\n' "$FLEET_PANE_PROMPT_SIGNATURES" | tr '[:upper:]' '[:lower:]'
  else
    default_permission_prompt_signatures
  fi
}

# contains_any <haystack-lowercased> <needle-list-on-stdin> — 0 iff any
# non-empty needle is a substring of the haystack.
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

# permission_prompt_present <window-text> — 0 iff the bounded window carries a
# permission-prompt signature. A positive match is the only admissible pane
# evidence of a human-blocked worker; its absence is no evidence of anything.
permission_prompt_present() {
  ppp_lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  printf '%s\n' "$(permission_prompt_signatures)" | { contains_any "$ppp_lc"; }
}
