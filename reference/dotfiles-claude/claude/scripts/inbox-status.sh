#!/usr/bin/env bash
# inbox-status.sh — tmux status-bar segment for the cross-session inbox.
#
# Prints a triplet like "⚠1 ●3 ◆2":
#   ⚠  awaiting-input count (red category per D-22)
#   ●  working count
#   ◆  draft-pr-ready count
#
# All three are shown even at zero, for at-a-glance liveness (per the user's
# chosen layout on PR #28). Sweeps stale entries first via inbox-sweep.sh so
# crashed sessions do not inflate the counts.
#
# Output is single-line, no trailing newline (tmux status bar convention).
# Errors are silent (the status bar must not break on a transient failure).

set -u

SWEEPER="$HOME/.claude/scripts/inbox-sweep.sh"

if [ ! -x "$SWEEPER" ]; then
    # Fail closed but visibly so the user notices the dependency is missing.
    printf 'inbox?'
    exit 0
fi

awaiting=0
working=0
prready=0

while IFS= read -r path; do
    [ -z "$path" ] && continue
    state=$(jq -r '.state // empty' "$path" 2>/dev/null)
    case "$state" in
        awaiting-input) awaiting=$((awaiting + 1)) ;;
        working)        working=$((working + 1)) ;;
        draft-pr-ready) prready=$((prready + 1)) ;;
    esac
done < <("$SWEEPER" list 2>/dev/null)

printf '⚠%d ●%d ◆%d' "$awaiting" "$working" "$prready"

# Match dracula's polling cadence so dracula's `custom:` slot does not
# re-invoke this script in a tight loop. status-interval defaults to 5s
# in roles/tmux/files/tmux.conf; the gpu-usage.sh sibling follows the
# same pattern.
rate=$(tmux show-option -gqv status-interval 2>/dev/null || true)
sleep "${rate:-5}"

