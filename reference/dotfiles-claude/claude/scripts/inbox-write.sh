#!/usr/bin/env bash
# inbox-write.sh — CRUD on cross-session inbox entries.
#
# Inbox spec: REQ-F1.1, REQ-F1.2, D-22, D-23, D-34 in specs/pair-flow/.
# Files: ~/.claude/inbox/{host}-{session-uuid}.json (one per active session).
#
# Subcommands:
#   hook-event <state> [<summary>]   Driven by a Claude Code hook. Reads the
#                                    hook JSON on stdin to extract session_id
#                                    and cwd. Initializes the entry if absent;
#                                    otherwise updates state + last-heartbeat.
#                                    Fires a macOS notification via the
#                                    existing notify-event.sh on transitions
#                                    into awaiting-input or draft-pr-ready.
#   tick <session-id>                Bump last-heartbeat without changing state.
#                                    Called by inbox-heartbeat.sh on its 30s
#                                    loop. No-op if the entry is gone.
#   drop <session-id>                Remove the entry (clean session exit).
#   summary <session-id> <text>      Set/replace the summary field.
#
# Output: nothing on success; errors to stderr with exit 1.
#
# Compatible with bash 3.2 (macOS default).

set -u

INBOX_DIR="${PAIR_FLOW_INBOX:-$HOME/.claude/inbox}"
mkdir -p "$INBOX_DIR" 2>/dev/null || true
# Best-effort: entries hold worktree paths and branch names. Keep the dir
# private even if it was created before Ansible set mode 0700, or via a
# non-default PAIR_FLOW_INBOX. No hard fail.
chmod 700 "$INBOX_DIR" 2>/dev/null || true

# All read/modify/write paths need jq (some of the write-side calls are not
# 2>/dev/null-guarded). Degrade silently if jq is unavailable, consistent with
# tasks-pr-sync.sh, rather than emitting partial errors and empty-payload dies.
command -v jq >/dev/null 2>&1 || exit 0

die() {
    printf 'inbox-write: %s\n' "$1" >&2
    exit 1
}

# ISO 8601 UTC timestamp (BSD date compatible).
now_iso() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# Resolve host (consistent with what tmux session names look like in the user's
# convention: one tmux session per host).
host_name() {
    if [ -n "${PAIR_FLOW_HOST:-}" ]; then
        printf '%s\n' "$PAIR_FLOW_HOST"
    else
        # `hostname -s` yields the short name without the .local/domain suffix,
        # keeping iCloud-synced filenames clean. The bare-hostname fallback runs
        # only if -s fails (rare on macOS) and may include a suffix; the other
        # inbox scripts derive HOST identically, so it stays consistent per host.
        hostname -s 2>/dev/null || hostname
    fi
}

# Filename for a session entry.
entry_path() {
    printf '%s/%s-%s.json\n' "$INBOX_DIR" "$(host_name)" "$1"
}

# Walk up the process tree looking for a claude CLI ancestor and print its PID.
# Falls back to $PPID (the hook's direct parent) if no match found within 6
# levels. Used so the heartbeat + sweeper can detect dead sessions even when
# Stop never fires (kill -9, terminal closed).
discover_claude_pid() {
    local pid="$PPID"
    local depth=0
    while [ "$pid" != "1" ] && [ "$depth" -lt 6 ]; do
        local comm
        comm=$(ps -p "$pid" -o comm= 2>/dev/null | awk -F/ '{print $NF}')
        case "$comm" in
            claude|claude-code)
                printf '%s\n' "$pid"
                return 0
                ;;
        esac
        pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
        [ -z "$pid" ] && break
        depth=$((depth + 1))
    done
    printf '%s\n' "$PPID"
}

# Capture tmux target if we're in a tmux session (display-message returns
# something like "main:2.1"). Empty otherwise.
tmux_target() {
    [ -z "${TMUX:-}" ] && return 0
    tmux display-message -p '#S:#I.#P' 2>/dev/null || true
}

# Repo for an entry — best-effort from `gh` then git remote.
detect_repo() {
    local cwd="$1"
    [ -z "$cwd" ] && cwd="$PWD"
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        local r
        r=$(cd "$cwd" 2>/dev/null && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
        if [ -n "$r" ]; then
            printf '%s\n' "$r"
            return 0
        fi
    fi
    local url
    url=$(cd "$cwd" 2>/dev/null && git remote get-url origin 2>/dev/null || true)
    [ -z "$url" ] && return 0
    url="${url%.git}"
    if [[ "$url" =~ ^[^@]+@[^:]+:(.+)$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    elif [[ "$url" =~ ([^/]+/[^/]+)$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    fi
}

detect_branch() {
    local cwd="$1"
    [ -z "$cwd" ] && cwd="$PWD"
    (cd "$cwd" 2>/dev/null && git branch --show-current 2>/dev/null) | tr -d '\n'
}

# Write an entry atomically. Args: path, json.
#
# Each individual write is atomic (tmp + rename). The read-modify-write across
# subcommands (hook-event reads then rewrites the whole entry; tick reads then
# rewrites last-heartbeat) is NOT serialized: a tick that lands between a
# hook-event's read and write can revert that state change. The window is a few
# milliseconds and the two fire on uncorrelated schedules (ticks every 30s,
# hook-events on state transitions), so a collision is rare and self-heals on
# the next tick or state event well within the 120s stale threshold. Accepted
# as eventual consistency rather than adding a lock (flock is absent on macOS).
atomic_write() {
    local path="$1"
    local json="$2"
    local tmp="${path}.tmp.$$"
    # Refuse to persist an empty payload: every caller passes jq output, so an
    # empty string means jq failed (e.g. a pre-existing malformed entry file).
    # Writing it would blank the entry; die instead so the failure surfaces.
    [ -z "$json" ] && die "refusing to write empty entry to $path"
    printf '%s\n' "$json" > "$tmp" || die "could not write $tmp"
    mv -f "$tmp" "$path" || { rm -f "$tmp"; die "could not rename to $path"; }
}

read_state() {
    local path="$1"
    [ ! -f "$path" ] && return 0
    jq -r '.state // empty' "$path" 2>/dev/null
}

# Fire a macOS notification via the existing notify-event.sh path on a
# transition INTO draft-pr-ready (REQ-F3.1), and only when the previous state
# was different (no spam on idempotent bumps).
#
# awaiting-input is intentionally NOT notified here: the direct
# notify-event.sh permission/idle hooks in settings.json already fire on the
# same permission_prompt/idle_prompt events that set awaiting-input, and they
# carry the actual permission message (richer than a generic "awaiting input").
# inbox-write still records the awaiting-input state above for the dashboard;
# it just does not emit a second, duplicate notification. draft-pr-ready has no
# direct hook, so inbox-write owns that notification.
maybe_notify() {
    local prev="$1"
    local next="$2"
    local cwd="$3"
    local notifier="$HOME/.claude/scripts/notify-event.sh"
    [ ! -x "$notifier" ] && return 0
    # Pass the real cwd: notify-event.sh derives project + branch itself
    # (basename + `git -C "$cwd"`) and prepends that context.
    case "$next" in
        draft-pr-ready)
            [ "$prev" = "draft-pr-ready" ] && return 0
            jq -nc --arg cwd "$cwd" '{cwd: $cwd}' | "$notifier" "done" >/dev/null 2>&1 || true
            ;;
    esac
}

# --- subcommands ----------------------------------------------------------

if [ $# -lt 1 ]; then
    printf 'usage: %s <hook-event <state>|tick <id>|drop <id>|summary <id> <text>>\n' "$(basename "$0")" >&2
    exit 2
fi

cmd="$1"; shift || true

case "$cmd" in
    hook-event)
        [ $# -lt 1 ] && die "usage: hook-event <state> [<summary>]"
        state="$1"; shift || true
        summary="${1:-}"

        # Read hook payload from stdin. Tolerate empty (manual invocation).
        payload=""
        if [ ! -t 0 ]; then
            payload=$(cat)
        fi
        session_id=""
        cwd=""
        if [ -n "$payload" ]; then
            session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
            cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
        fi
        [ -z "$session_id" ] && session_id="${CLAUDE_SESSION_ID:-}"
        [ -z "$cwd" ] && cwd="$PWD"
        [ -z "$session_id" ] && die "hook-event: missing session_id (stdin JSON had no .session_id and CLAUDE_SESSION_ID is unset)"

        path=$(entry_path "$session_id")
        prev_state=$(read_state "$path")
        ts=$(now_iso)
        branch=$(detect_branch "$cwd")

        if [ -f "$path" ]; then
            # Update existing entry.
            new_json=$(jq --arg state "$state" \
                          --arg ts "$ts" \
                          --arg summary "$summary" \
                          --arg cwd "$cwd" \
                          --arg branch "$branch" '
                .state = $state |
                ."last-heartbeat" = $ts |
                .worktree = $cwd |
                (if ($branch != "") then .branch = $branch else . end) |
                if ($summary != "") then .summary = $summary else . end' "$path")
        else
            # Initialize.
            host=$(host_name)
            repo=$(detect_repo "$cwd")
            target=$(tmux_target)
            cpid=$(discover_claude_pid)
            new_json=$(jq -n \
                --arg host "$host" \
                --arg session "$session_id" \
                --arg cwd "$cwd" \
                --arg repo "$repo" \
                --arg branch "$branch" \
                --arg state "$state" \
                --arg first_seen "$ts" \
                --arg heartbeat "$ts" \
                --arg summary "$summary" \
                --arg target "$target" \
                --arg pid "$cpid" '
                {
                    host: $host,
                    session: $session,
                    worktree: $cwd,
                    repo: $repo,
                    branch: $branch,
                    state: $state,
                    "first-seen": $first_seen,
                    "last-heartbeat": $heartbeat,
                    pid: ($pid | tonumber? // null)
                }
                | if ($summary != "") then . + {summary: $summary} else . end
                | if ($target != "") then . + {"tmux-target": $target} else . end')
        fi
        atomic_write "$path" "$new_json"
        maybe_notify "$prev_state" "$state" "$cwd"
        ;;

    tick)
        [ $# -lt 1 ] && die "usage: tick <session-id>"
        session_id="$1"
        path=$(entry_path "$session_id")
        [ ! -f "$path" ] && exit 0
        ts=$(now_iso)
        new_json=$(jq --arg ts "$ts" '."last-heartbeat" = $ts' "$path")
        atomic_write "$path" "$new_json"
        ;;

    drop)
        [ $# -lt 1 ] && die "usage: drop <session-id>"
        session_id="$1"
        path=$(entry_path "$session_id")
        rm -f "$path"
        ;;

    summary)
        [ $# -lt 2 ] && die "usage: summary <session-id> <text>"
        session_id="$1"; shift
        text="$*"
        path=$(entry_path "$session_id")
        [ ! -f "$path" ] && exit 0
        new_json=$(jq --arg text "$text" '.summary = $text' "$path")
        atomic_write "$path" "$new_json"
        ;;

    *)
        printf 'inbox-write: unknown subcommand: %s\n' "$cmd" >&2
        exit 2
        ;;
esac
