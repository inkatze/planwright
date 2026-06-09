#!/usr/bin/env bash
# inbox-dashboard.sh — render the cross-session inbox as a tmux popup table.
#
# Layout: compact table (the user's chosen option on PR #28). Display-only;
# rows are not navigational in v1 (REQ-F2.1 baseline).
#
# Rendering:
#   * one row per worktree+branch (D-34: aggregates concurrent sessions in the
#     same worktree as a single row annotated "(N sessions)"). The aggregation
#     key is host|worktree|branch; a git worktree pins a single branch, so this
#     is effectively per-worktree.
#   * color and sort per D-22. D-22's table reserves weight 1 (red,
#     strikethrough) for "stale lock", an orchestrator concept; a session
#     dashboard has no lock state (stale heartbeats are swept before display
#     per D-23), so weight 1 is used here for error/blocked sessions, which
#     share the same red-strikethrough urgency styling.
#       red    → awaiting-input    (sort weight 0)
#       red×   → error / blocked   (sort weight 1, strikethrough)
#       orange → working >2h       (sort weight 2)
#       blue   → draft-pr-ready    (sort weight 3)
#       yellow → working >30min    (sort weight 4)
#       green  → working fresh     (sort weight 5)
#       grey   → idle / exited     (sort weight 6)
#
# Stale entries (heartbeat older than 2 min) are removed by the sweeper before
# rendering so the popup never shows ghost sessions.
#
# Designed to run inside `tmux display-popup -E`. The popup closes when the
# script exits; the simple read loop at the end blocks until the user presses
# any key, so the rendered table stays on screen.

set -u

SWEEPER="$HOME/.claude/scripts/inbox-sweep.sh"
INBOX_DIR="${PAIR_FLOW_INBOX:-$HOME/.claude/inbox}"
# Honor PAIR_FLOW_HOST exactly as inbox-write.sh's host_name() does, so local
# entries are not mislabeled "[remote: ...]" when the host name is overridden.
HOST="${PAIR_FLOW_HOST:-$(hostname -s 2>/dev/null || hostname)}"

# ANSI color codes (256-color palette so dracula's red/yellow/green stay
# coherent with the rest of the user's theme).
RED=$'\033[38;5;203m'
ORANGE=$'\033[38;5;215m'
BLUE=$'\033[38;5;111m'
YELLOW=$'\033[38;5;221m'
GREEN=$'\033[38;5;120m'
GREY=$'\033[38;5;245m'
STRIKE=$'\033[9m'
RESET=$'\033[0m'
BOLD=$'\033[1m'

if [ ! -x "$SWEEPER" ]; then
    printf '%s\n' "inbox-dashboard: missing $SWEEPER" >&2
    sleep 2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' "inbox-dashboard: jq not found" >&2
    sleep 2
    exit 1
fi

# BSD date epoch parsing.
iso_to_epoch() {
    [ -z "$1" ] && return 1
    date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null
}

now_epoch=$(date -u +%s)

# Format a duration in seconds as a short string (90 → 1m30s, 5400 → 1h30m).
fmt_duration() {
    local s="$1"
    if [ "$s" -lt 60 ]; then
        printf '%ds' "$s"
    elif [ "$s" -lt 3600 ]; then
        printf '%dm' "$((s / 60))"
    elif [ "$s" -lt 86400 ]; then
        printf '%dh%02dm' "$((s / 3600))" "$(((s % 3600) / 60))"
    else
        printf '%dd' "$((s / 86400))"
    fi
}

# --- pass 1: scan entries, compute per-worktree rows --------------------

# Per-worktree aggregation: key = host\tworktree.
# Values: pipe-separated list of (state, first-seen-epoch, heartbeat-epoch).
# bash 3.2 has no associative arrays, so use parallel arrays.
worktree_keys=()
worktree_blobs=()

while IFS= read -r path; do
    [ -z "$path" ] && continue
    entry_host=$(jq -r '.host // empty' "$path" 2>/dev/null)
    worktree=$(jq -r '.worktree // empty' "$path" 2>/dev/null)
    branch=$(jq -r '.branch // empty' "$path" 2>/dev/null)
    state=$(jq -r '.state // "idle"' "$path" 2>/dev/null)
    first_seen=$(jq -r '."first-seen" // empty' "$path" 2>/dev/null)
    heartbeat=$(jq -r '."last-heartbeat" // empty' "$path" 2>/dev/null)
    fs_epoch=$(iso_to_epoch "$first_seen" 2>/dev/null || echo 0)
    hb_epoch=$(iso_to_epoch "$heartbeat" 2>/dev/null || echo 0)

    key="${entry_host}|${worktree}|${branch}"
    blob="${state}^${fs_epoch}^${hb_epoch}"

    # Look up in parallel arrays.
    found=-1
    i=0
    for k in "${worktree_keys[@]:-}"; do
        if [ "$k" = "$key" ]; then
            found=$i
            break
        fi
        i=$((i + 1))
    done
    if [ "$found" -ge 0 ]; then
        worktree_blobs[found]="${worktree_blobs[found]};${blob}"
    else
        worktree_keys+=("$key")
        worktree_blobs+=("$blob")
    fi
done < <("$SWEEPER" list 2>/dev/null)

# --- pass 2: render rows with color + sort weight ------------------------

# Each rendered row: "<sort-weight>\t<plain-text-for-sort>\t<ansi-text>".
rows_file=$(mktemp -t inbox-dash.XXXXXX)
trap 'rm -f "$rows_file"' EXIT

idx=0
awaiting=0
working=0
prready=0
total_rows=${#worktree_keys[@]}

for key in "${worktree_keys[@]:-}"; do
    [ -z "$key" ] && continue
    blob="${worktree_blobs[$idx]}"
    idx=$((idx + 1))

    entry_host="${key%%|*}"
    rest="${key#*|}"
    worktree="${rest%%|*}"
    branch="${rest##*|}"

    # Pick the most urgent session for this worktree (lowest sort weight).
    # Also collect session count for the "(N sessions)" annotation.
    best_weight=99
    best_state="idle"
    best_age=0
    sessions=0
    IFS=';' read -r -a parts <<< "$blob"
    for part in "${parts[@]}"; do
        s_state="${part%%^*}"
        rem="${part#*^}"
        s_fs="${rem%%^*}"
        # Skip malformed parts with no (or unparseable) first-seen timestamp;
        # otherwise the arithmetic below would treat the field as 0 and report
        # a bogus age measured from the epoch, dominating the sort order.
        [ -n "$s_fs" ] && [ "$s_fs" != "0" ] || continue
        s_age=$((now_epoch - s_fs))
        case "$s_state" in
            awaiting-input) w=0 ;;
            draft-pr-ready) w=3 ;;
            working)
                if   [ "$s_age" -gt 7200 ]; then w=2
                elif [ "$s_age" -gt 1800 ]; then w=4
                else                              w=5
                fi
                ;;
            error|blocked)  w=1 ;;
            idle|*)         w=6 ;;
        esac
        if [ "$w" -lt "$best_weight" ]; then
            best_weight="$w"
            best_state="$s_state"
            best_age="$s_age"
        fi
        sessions=$((sessions + 1))
    done

    case "$best_weight" in
        0) color="$RED";    awaiting=$((awaiting + 1)) ;;
        1) color="${RED}${STRIKE}" ;;
        2) color="$ORANGE" ;;
        3) color="$BLUE";   prready=$((prready + 1)) ;;
        4) color="$YELLOW"; working=$((working + 1)) ;;
        5) color="$GREEN";  working=$((working + 1)) ;;
        *) color="$GREY" ;;
    esac

    # Truncate worktree to its basename, then clip to the column width so
    # long names like `dotfiles--claude-worktrees-spec-pair-flow` do not
    # push the right-hand columns off the popup.
    wt_name="${worktree##*/}"
    [ -z "$wt_name" ] && wt_name="(unknown)"
    if [ ${#wt_name} -gt 22 ]; then
        wt_name="${wt_name:0:19}..."
    fi
    [ -z "$branch" ] && branch="(no branch)"
    if [ ${#branch} -gt 26 ]; then
        branch="${branch:0:23}..."
    fi

    age_str=$(fmt_duration "$best_age")
    host_tag=""
    if [ "$entry_host" != "$HOST" ]; then
        host_tag=" [remote: $entry_host]"
    fi
    multi=""
    [ "$sessions" -gt 1 ] && multi=" ($sessions sessions)"

    plain=$(printf '%s  %-22s  %-26s  %-15s  %5s%s%s' \
        "$best_weight" "$wt_name" "$branch" "$best_state" "$age_str" "$host_tag" "$multi")
    ansi=$(printf '%s%-22s  %-26s  %-15s  %5s%s%s%s' \
        "$color" "$wt_name" "$branch" "$best_state" "$age_str" "$host_tag" "$multi" "$RESET")

    printf '%d\t%s\t%s\n' "$best_weight" "$plain" "$ansi" >> "$rows_file"
done

# --- pass 3: render the popup -------------------------------------------

clear

now_fmt=$(date '+%H:%M')
printf '%sINBOX%s (%d worktrees · %d awaiting · %d working · %d pr-ready)        %s\n\n' \
    "$BOLD" "$RESET" "$total_rows" "$awaiting" "$working" "$prready" "$now_fmt"

if [ "$total_rows" -eq 0 ]; then
    printf '%s  no active Claude sessions across hosts%s\n\n' "$GREY" "$RESET"
else
    printf '  %-22s  %-26s  %-15s  %5s\n' 'WORKTREE' 'BRANCH' 'STATE' 'AGE'
    printf '  %-22s  %-26s  %-15s  %5s\n' \
        '----------------------' '--------------------------' '---------------' '-----'
    # Stable sort by weight, then by worktree name.
    sort -t $'\t' -k1,1n -k2,2 "$rows_file" | while IFS=$'\t' read -r _ _ ansi; do
        printf '  %s\n' "$ansi"
    done
    printf '\n'
fi

printf '  press any key to close · entry files at %s\n' "$INBOX_DIR"

# Block so the popup stays open until the user dismisses it.
read -r -s -n1 _ || true
