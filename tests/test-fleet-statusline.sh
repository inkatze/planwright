#!/bin/bash
# Tests for scripts/fleet-statusline.sh — the Claude Code statusLine command that
# renders the derived fleet stats natively in the operator's own terminal, gated
# on the `statusline` notification_channel value (fleet-autonomy Task 8: D-14,
# REQ-F1.2).
#
# CONTRACT (Claude Code statusLine, verified against code.claude.com/docs/en/
# statusline.md). Claude Code invokes the configured command, passing a session
# JSON object on stdin; the command's stdout becomes the status line (empty
# stdout or a non-zero exit blanks it). So this command:
#   - reads and ignores the stdin JSON (it needs none of it — the stats derive
#     from the fleet home, not the session);
#   - resolves notification_channel through the overlay layers
#     (scripts/resolve-notification-channel.sh);
#   - when it resolves to `statusline`, prints the compact fleet-stats line
#     (scripts/fleet-stats.sh line) — the rendering function, invoked with the
#     CURRENT derived stats, composing with fleet-attention.sh's queue length;
#   - when it resolves to anything else, prints NOTHING (planwright does not own
#     the operator's statusLine unless they opted this channel in);
#   - ALWAYS exits 0 and is fast (a broken fleet home must never break the
#     operator's status line).
#
# REQ-F1.2 `[test]`: `notification_channel: statusline` resolves through the
# overlay layers and invokes the rendering function with the current stats. (The
# `[manual]` half — the line actually appearing at a real terminal's bottom — is
# an operator visual check, per test-spec.md.)
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-statusline.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SL="$here/../scripts/fleet-statusline.sh"
FA="$here/../scripts/fleet-audit.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SL" ] || fail "scripts/fleet-statusline.sh missing or not executable"
[ -x "$FA" ] || fail "scripts/fleet-audit.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The fleet home (for the stats) and the config overlay layers (for the channel)
# are wired through their respective env overrides, exactly as the sibling tests
# do — hermetic, no $HOME, no git top.
fleet_home="$tmp/fleet"
core_cfg="$tmp/core-defaults.yml"
repo="$tmp/repo"
mkdir -p "$repo/.claude"
tracked_cfg="$repo/.claude/planwright.yml"
printf 'notification_channel: none\n' >"$core_cfg"

# A realistic slice of the session JSON Claude Code pipes in — the command must
# consume and ignore it.
STDIN_JSON='{"cwd":"/w","session_id":"abc","model":{"id":"opus","display_name":"Opus"},"workspace":{"current_dir":"/w"}}'

# statusline <channel-value> — run the command with notification_channel set to
# <channel-value> via the repo-tracked overlay, the fleet home pinned, and the
# session JSON on stdin.
statusline() {
  sl_channel=$1
  printf 'notification_channel: %s\n' "$sl_channel" >"$tracked_cfg"
  printf '%s' "$STDIN_JSON" \
    | PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
      PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
      PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter" \
      PLANWRIGHT_REPO_ROOT="$repo" \
      PLANWRIGHT_LOCAL_CONFIG="" \
      /bin/bash "$SL"
}

audit() { PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$FA" "$@"; }

# --- 1. With the channel set to `statusline`, the command renders the stats line
#        and exits 0.
rc=0
out=$(statusline statusline) || rc=$?
[ "$rc" = 0 ] || fail "statusline channel: expected exit 0, got $rc"
case $out in
  planwright*trips*throttle*queue*) ;;
  *) fail "statusline channel did not render the fleet-stats line (got: '$out')" ;;
esac
# It must be a single line (a statusLine consumes the first line; multi-line
# would be a contract slip).
[ "$(printf '%s' "$out" | wc -l | tr -d ' ')" = 0 ] \
  || fail "statusline output was not a single line"
echo "ok: notification_channel=statusline renders the compact fleet-stats line (exit 0)"

# --- 2. The render reflects the CURRENT stats: a fresh watchdog trip shows up.
audit record tower-watchdog relaunch "tower-dead-ready-work" "cold-started a fresh tower" \
  || fail "recording a watchdog trip failed"
out=$(statusline statusline) || fail "statusline (after trip) failed"
case $out in
  *"trips 1"*) ;;
  *) fail "statusline did not reflect the current watchdog-trip count (got: '$out')" ;;
esac
echo "ok: the statusline render reflects the current derived stats"

# --- 3. With any OTHER channel, the command prints nothing (planwright does not
#        own the statusLine unless opted in) and still exits 0.
for ch in none tmux-popup os-notify editor-toast; do
  rc=0
  out=$(statusline "$ch") || rc=$?
  [ "$rc" = 0 ] || fail "channel '$ch': expected exit 0, got $rc"
  [ -z "$out" ] || fail "channel '$ch' should print nothing, got: '$out'"
done
echo "ok: a non-statusline channel renders nothing and exits 0"

# --- 4. Robustness: a broken/unresolvable fleet home must NOT break the status
#        line — the command still exits 0 (blank or degraded, never a hard fail).
rc=0
printf '%s' "$STDIN_JSON" \
  | PLANWRIGHT_FLEET_STATE_DIR="/nonexistent/should/not/resolve/$$" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$SL" >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "a broken fleet home broke the status line (exit $rc, must be 0)"
echo "ok: a broken fleet home never breaks the status line (exit 0)"

echo "PASS: fleet-statusline.sh"
