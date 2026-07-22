#!/bin/sh
# tmux-stub.sh — a faithful `tmux` test double for driving the behavioral-eval
# harness hermetically (operator-dialogue Task 6). It is the SAME double
# test-behavioral-eval.sh embeds inline; extracted here so the Task-6 acceptance
# tests (kickoff + rubric instrument) share one copy rather than a third.
#
# It backs each "session" with a state dir under $BEHAVIORAL_EVAL_TMUX_STATE.
# new-session records the launch and renders the first pane by running the skill
# with zero answers (it prints the turn-1 question + anchor, then EOF-exits).
# send-keys accumulates the driver's answers; each C-m replays ALL accumulated
# answers through the REAL skill, re-rendering the pane and — on the final answer
# — writing the durable artifacts. capture-pane cats the pane;
# has-session/kill-session/list-sessions complete the surface the harness funnels
# through its tmux_* helpers. It is a double for tmux, NEVER for the skill: it
# runs the real fixture skill, so every branch of the harness is exercised
# without a real tmux, a live model, an API key, or spend.
set -u
ST="${BEHAVIORAL_EVAL_TMUX_STATE:?stub needs BEHAVIORAL_EVAL_TMUX_STATE}"
mkdir -p "$ST" 2>/dev/null || true

# strip a leading '=' exact-match prefix from a target
untag() { printf '%s' "${1#=}"; }
# state dir for a session name (name is already grammar-safe)
sdir() { printf '%s/%s' "$ST" "$1"; }
# mark_liveness <state-dir> — model tmux session DEATH: under real tmux the pane
# dies when the launched skill exits. The stub infers death from the render — a
# skill that exited without leaving an at-prompt anchor (`turn=`) AND without a
# sign-off has terminated early (a crash / early-exit), so has-session must then
# report it dead and the harness's invalid-run (exit 3) branch is reachable. A
# completed run (sign-off present) is NOT dead: the harness breaks on the sign-off
# first, matching real tmux where the pane lingers after the skill exits.
mark_liveness() {
  _ml_d="$1"
  if ! grep -q 'turn=' "$_ml_d/pane" 2>/dev/null \
    && [ ! -f "$(cat "$_ml_d/art")/sign-off.json" ]; then
    : >"$_ml_d/dead"
  else
    rm -f "$_ml_d/dead" 2>/dev/null
  fi
}

sub="${1:-}"
[ "$#" -gt 0 ] && shift
case "$sub" in
  new-session)
    name=""
    launch=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -d) shift ;;
        -s)
          name="$2"
          shift 2
          ;;
        -x | -y) shift 2 ;;
        *)
          launch="$1"
          shift
          ;;
      esac
    done
    [ -n "$name" ] || exit 1
    d="$(sdir "$name")"
    mkdir -p "$d/art-link" 2>/dev/null
    printf '%s' "$launch" >"$d/launch"
    : >"$d/answers"
    skill="$(printf '%s' "$launch" | awk '{print $(NF-1)}')"
    art="$(printf '%s' "$launch" | awk '{print $NF}')"
    printf '%s' "$skill" >"$d/skill"
    printf '%s' "$art" >"$d/art"
    printf '%s\t%s\n' "$name" "$launch" >>"$ST/.new-sessions"
    sh "$skill" "$art" </dev/null >"$d/pane" 2>&1
    mark_liveness "$d"
    exit 0
    ;;
  capture-pane)
    name=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -p | -e) shift ;;
        -t)
          name="$(untag "$2")"
          shift 2
          ;;
        -S) shift 2 ;;
        *) shift ;;
      esac
    done
    d="$(sdir "$name")"
    [ -f "$d/pane" ] && cat "$d/pane"
    exit 0
    ;;
  send-keys)
    name=""
    literal=0
    text=""
    enter=0
    while [ $# -gt 0 ]; do
      case "$1" in
        -t)
          name="$(untag "$2")"
          shift 2
          ;;
        -l)
          literal=1
          shift
          ;;
        --)
          shift
          text="${1:-}"
          shift 2>/dev/null || shift $#
          ;;
        C-m)
          enter=1
          shift
          ;;
        *) shift ;;
      esac
    done
    d="$(sdir "$name")"
    [ -d "$d" ] || exit 0
    if [ "$literal" -eq 1 ]; then
      printf '%s' "$text" >"$d/pending"
    fi
    if [ "$enter" -eq 1 ]; then
      pend=""
      [ -f "$d/pending" ] && pend="$(cat "$d/pending")"
      printf '%s\n' "$pend" >>"$d/answers"
      : >"$d/pending"
      skill="$(cat "$d/skill")"
      art="$(cat "$d/art")"
      sh "$skill" "$art" <"$d/answers" >"$d/pane" 2>&1
      mark_liveness "$d"
    fi
    exit 0
    ;;
  has-session)
    name=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -t)
          name="$(untag "$2")"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    d="$(sdir "$name")"
    { [ -d "$d" ] && [ ! -f "$d/dead" ]; } && exit 0
    exit 1
    ;;
  kill-session)
    name=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -t)
          name="$(untag "$2")"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    rm -rf "$(sdir "$name")" 2>/dev/null
    exit 0
    ;;
  list-sessions)
    for d in "$ST"/*/; do
      [ -d "$d" ] || continue
      basename "$d"
    done
    exit 0
    ;;
  *) exit 0 ;;
esac
