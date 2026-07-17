#!/bin/sh
# fleet-cleanup.sh — the deterministic stale-resource cleanup actuator with an
# explicit self-targeting guard (Task 4: D-6, D-5, D-15, D-16; REQ-B1.1).
#
# WHY DETERMINISTIC (D-6). Stale window/pane/worktree cleanup runs as script
# logic, never in-context model judgment. A real postmortem
# (anthropics/claude-code#29787) shows an LLM-driven cleanup non-deterministically
# issuing `tmux kill-session` against its OWN hosting pane, destroying the whole
# session. This actuator closes that exact failure mode two ways: it never lets a
# model decide what to reclaim (the caller passes an explicit target and this
# script gates it), and it REFUSES outright to act on a target that resolves to
# the caller's own hosting session/worktree (the self-targeting guard).
#
# POSITIVE EVIDENCE ONLY (D-5). A resource is reclaimed only on positive,
# deterministic evidence that reclaiming it loses nothing — a tmux window whose
# panes are all dead (`#{pane_dead}` = 1, the worker process exited), or a git
# worktree that is clean AND fully pushed. Silence, a timeout, or a "probably
# stale" guess is never admissible: the same discipline
# scripts/fleet-death-evidence.sh encodes, applied to reclamation. A live pane or
# an unpushed/dirty worktree is refused, never reclaimed.
#
# KILL-SWITCH + AUDIT (D-15, D-16). Every invocation gates through
# scripts/fleet-daemon-gate.sh BEFORE acting (a set `fleet_daemon_pause` pauses
# the whole daemon layer), and every reclaim — and every self-block, a notable
# safety event — is written to the shared audit trail (scripts/fleet-audit.sh).
#
# Usage:
#   fleet-cleanup.sh window <session> <window> <trigger> <reasoning>
#       Reclaim a stale tmux window (kill-window) whose panes are all dead.
#       <window> matches either #{window_id} (@N) or #{window_name}. The self
#       identity is resolved from the caller's own pane ($TMUX_PANE via
#       `tmux display-message`); it is refused if it resolves to that window.
#   fleet-cleanup.sh worktree <path> <trigger> <reasoning>
#       Remove a clean, fully-pushed git worktree (git worktree remove). Refused
#       if <path> is (or contains) the caller's own worktree, or if it carries
#       uncommitted or unpushed work.
#
# <trigger>/<reasoning> are free-text audit fields (the caller's determination of
# WHY the target is stale) under fleet-audit's control-free text grammar.
#
# Exit codes:
#   0  acted (resource reclaimed) or a clean no-op (target already gone)
#   2  usage / refused malformed token
#   3  refused by the self-targeting guard — the target is, or cannot be proven
#      not to be, the caller's own hosting session/worktree (the #29787 block;
#      an unresolvable self-identity fails closed here)
#   4  refused: the fleet_daemon_pause kill-switch is set (or the gate could not
#      resolve its own switch — fail closed, degrade capability never safety)
#   5  refused: no positive evidence the target is reclaimable (a live pane, or a
#      dirty/unpushed worktree — acting would destroy live work), or the reclaim
#      command itself failed
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling). All input
# is data; no eval, no jq (REQ-K1.5). Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# The canonical echo-discipline sanitizer, sourced as the sibling fleet scripts
# do; a missing helper is a broken install.
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

GATE="$script_dir/fleet-daemon-gate.sh"
AUDIT="$script_dir/fleet-audit.sh"
TAB=$(printf '\t')

warn() { printf 'fleet-cleanup: %s\n' "$*" >&2; }

usage() {
  echo "usage: fleet-cleanup.sh window <session> <window> <trigger> <reasoning>" >&2
  echo "       fleet-cleanup.sh worktree <path> <trigger> <reasoning>" >&2
}

# The tmux handle grammar (fleet-death-evidence.sh's conservative single-token
# subset): no path separators, no `:` combined-target separator, no whitespace
# or shell metacharacter, no leading dash (option injection); bounded to 128.
valid_tmux_token() {
  vtt=$1
  case $vtt in
    "" | -*) return 1 ;;
    *[!A-Za-z0-9_@%.-]*) return 1 ;;
  esac
  [ "${#vtt}" -le 128 ]
}

# The control-free text grammar for the audit fields, byte-identical to
# fleet-audit.sh valid_text: non-empty, <=512 bytes, no C0/DEL/C1.
valid_text() {
  vt_v=$1
  [ -n "$vt_v" ] || return 1
  [ "${#vt_v}" -le 512 ] || return 1
  [ "$(sanitize_printable "$vt_v")" = "$vt_v" ]
}

# gate <mechanism> — fail-closed kill-switch check. Returns 0 to proceed; prints
# a note and returns 4 on any non-zero gate result (paused, or a resolver
# hard-fail: never act under an unresolved/paused switch).
gate() {
  "$GATE" "$1" 2>/dev/null && return 0
  warn "daemon layer paused or kill-switch unresolvable — refusing '$1' (unset fleet_daemon_pause to resume)"
  return 4
}

# audit <mechanism> <action> <trigger> <reasoning> — best-effort trail write.
# A reclaim's audit failure is surfaced loudly by the caller (an unrecorded
# action is what the trail exists to prevent); a self-block's is a warn only.
audit() {
  "$AUDIT" record "$1" "$2" "$3" "$4"
}

cmd=${1:-}
case "$cmd" in
  window | worktree) shift ;;
  "")
    usage
    exit 2
    ;;
  *)
    usage
    exit 2
    ;;
esac

case "$cmd" in
  window)
    if [ "$#" -ne 4 ]; then
      usage
      exit 2
    fi
    session=$1
    window=$2
    trigger=$3
    reasoning=$4
    if ! valid_tmux_token "$session" || ! valid_tmux_token "$window"; then
      warn "refusing malformed tmux token"
      exit 2
    fi
    if ! valid_text "$trigger" || ! valid_text "$reasoning"; then
      warn "refusing an audit field with a control byte, an embedded tab/newline, or over-length text"
      exit 2
    fi

    gate window-cleanup || exit 4

    # Resolve self-identity from the caller's own pane. A cleanup that cannot
    # prove the target is NOT its own window fails closed (refuse): the whole
    # point of the guard is that we would rather leave a stale window than risk
    # the #29787 self-kill.
    if [ -z "${TMUX:-}" ] || ! command -v tmux >/dev/null 2>&1; then
      warn "not inside a resolvable tmux (no \$TMUX or no tmux binary) — cannot prove non-self-target, refusing (fail closed)"
      exit 3
    fi
    self=$(tmux display-message -p -t "${TMUX_PANE:-}" \
      "#{session_name}${TAB}#{window_id}${TAB}#{window_name}" 2>/dev/null) || self=""
    if [ -z "$self" ]; then
      warn "could not resolve the caller's own tmux window — cannot prove non-self-target, refusing (fail closed)"
      exit 3
    fi
    self_session=${self%%"$TAB"*}
    self_rest=${self#*"$TAB"}
    self_wid=${self_rest%%"$TAB"*}
    self_wname=${self_rest#*"$TAB"}

    if [ "$session" = "$self_session" ] \
      && { [ "$window" = "$self_wid" ] || [ "$window" = "$self_wname" ]; }; then
      warn "REFUSING self-target: '$session:$window' is the caller's own hosting window (the #29787 block)"
      audit window-cleanup refuse-self "$trigger" "$reasoning" \
        || warn "could not record the self-block in the audit trail"
      exit 3
    fi

    # Positive evidence: the target's panes must all be dead. A list-panes
    # failure means the window is already gone (a clean no-op); a live pane
    # (pane_dead 0) or an empty/ambiguous listing means not reclaimable.
    target="=$session:$window"
    panes=$(tmux list-panes -t "$target" -F '#{pane_dead}' 2>/dev/null) || {
      # Window absent from the authoritative listing: nothing to reclaim.
      exit 0
    }
    if [ -z "$panes" ]; then
      warn "no pane state for '$session:$window' — no positive evidence it is reclaimable, refusing"
      exit 5
    fi
    old_ifs=$IFS
    IFS='
'
    for pd in $panes; do
      if [ "$pd" != 1 ]; then
        IFS=$old_ifs
        warn "'$session:$window' has a live pane (pane_dead='$pd') — refusing to kill a live worker"
        exit 5
      fi
    done
    IFS=$old_ifs

    if ! tmux kill-window -t "$target" 2>/dev/null; then
      warn "kill-window '$session:$window' failed — not reclaimed"
      exit 5
    fi
    if ! audit window-cleanup cleanup "$trigger" "$reasoning"; then
      warn "reclaimed window '$session:$window' but FAILED to record it in the audit trail"
      exit 2
    fi
    exit 0
    ;;

  worktree)
    if [ "$#" -ne 3 ]; then
      usage
      exit 2
    fi
    path=$1
    trigger=$2
    reasoning=$3
    case $path in
      "" | -*)
        warn "refusing malformed worktree path (empty or leading dash)"
        exit 2
        ;;
      /*) ;;
      *)
        warn "refusing a non-absolute worktree path"
        exit 2
        ;;
    esac
    if [ "$path" != "$(sanitize_printable "$path")" ]; then
      warn "refusing a worktree path with a control byte"
      exit 2
    fi
    if ! valid_text "$trigger" || ! valid_text "$reasoning"; then
      warn "refusing an audit field with a control byte, an embedded tab/newline, or over-length text"
      exit 2
    fi

    gate worktree-cleanup || exit 4

    command -v git >/dev/null 2>&1 || {
      warn "no git binary on PATH — cannot verify a worktree is reclaimable, refusing (fail closed)"
      exit 3
    }

    # Resolve the caller's own worktree root; fail closed if it cannot be
    # determined (we cannot prove the target is not ourselves).
    self_wt=$(git rev-parse --show-toplevel 2>/dev/null) || self_wt=""
    if [ -z "$self_wt" ]; then
      warn "caller is not inside a resolvable git worktree — cannot prove non-self-target, refusing (fail closed)"
      exit 3
    fi
    self_wt=$(cd "$self_wt" 2>/dev/null && pwd -P) || self_wt=""
    [ -n "$self_wt" ] || {
      warn "could not normalize the caller's own worktree — refusing (fail closed)"
      exit 3
    }

    # Target already gone: a clean no-op.
    if [ ! -e "$path" ]; then
      exit 0
    fi
    target_wt=$(cd "$path" 2>/dev/null && pwd -P) || {
      warn "target worktree path '$path' is not a traversable directory — refusing"
      exit 5
    }

    # Self-targeting guard: the target is the caller's own worktree, or an
    # ancestor of it (removing it would pull the ground out from under us).
    if [ "$target_wt" = "$self_wt" ]; then
      warn "REFUSING self-target: '$path' is the caller's own worktree"
      audit worktree-cleanup refuse-self "$trigger" "$reasoning" \
        || warn "could not record the self-block in the audit trail"
      exit 3
    fi
    case "$self_wt/" in
      "$target_wt"/*)
        warn "REFUSING self-target: '$path' contains the caller's own worktree"
        audit worktree-cleanup refuse-self "$trigger" "$reasoning" \
          || warn "could not record the self-block in the audit trail"
        exit 3
        ;;
    esac

    # Positive evidence the worktree is reclaimable: a git worktree whose root
    # is exactly this path, clean (no uncommitted changes), and fully pushed (no
    # commits ahead of a configured upstream). Any missing piece is refused —
    # reclaiming would lose work.
    top=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null) || top=""
    if [ -z "$top" ]; then
      warn "'$path' is not a git worktree — refusing to remove an unknown directory"
      exit 5
    fi
    top=$(cd "$top" 2>/dev/null && pwd -P) || top=""
    if [ "$top" != "$target_wt" ]; then
      warn "'$path' is not a worktree root (its toplevel is '$top') — refusing"
      exit 5
    fi
    if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
      warn "'$path' has uncommitted changes — refusing to remove (would lose work)"
      exit 5
    fi
    upstream=$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || upstream=""
    if [ -z "$upstream" ]; then
      warn "'$path' has no upstream configured — cannot prove it is pushed, refusing"
      exit 5
    fi
    ahead=$(git -C "$path" rev-list --count '@{upstream}..HEAD' 2>/dev/null) || ahead=""
    case $ahead in
      "" | *[!0-9]*)
        warn "'$path' unpushed-commit count is unreadable — refusing (fail closed)"
        exit 5
        ;;
    esac
    if [ "$ahead" != 0 ]; then
      warn "'$path' has $ahead unpushed commit(s) — refusing to remove (would lose work)"
      exit 5
    fi

    # Reclaim, running the removal from the caller's own worktree (a sibling in
    # the same repo), never from inside the target.
    if ! git -C "$self_wt" worktree remove "$path" 2>/dev/null; then
      warn "git worktree remove '$path' failed — not reclaimed"
      exit 5
    fi
    if ! audit worktree-cleanup cleanup "$trigger" "$reasoning"; then
      warn "removed worktree '$path' but FAILED to record it in the audit trail"
      exit 2
    fi
    exit 0
    ;;
esac
