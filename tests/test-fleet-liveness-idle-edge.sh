#!/bin/bash
# Tests for scripts/fleet-liveness.sh's resume edge: the idle exit-edge marker
# (fleet-messaging D-28; REQ-D1.11).
#
# A Stop that moves a worker's row to idle leaves an idle marker under
# liveness/idle/ beside the permission and fork-park markers; the next
# PostToolUse consumes it and writes `working` once under --unless-awaiting, so
# a worker resumed by a message or a typed turn reads working again without
# waiting for the healing sweep, and a queued decision written after the stop
# is never resolved by the edge.
#
# What is covered:
#   - a stop that writes idle leaves the marker; the next post-tool-use writes
#     working and removes it; a second post-tool-use writes nothing;
#   - with the marker present and the row reading awaiting-input (a decision
#     queued after the stop), post-tool-use leaves the row as it was;
#   - a stop that preserves a live fork-park leaves no idle marker;
#   - a post-tool-use with no exit-edge marker present leaves the store as is;
#   - a failed marker write warns on stderr and still exits 0;
#   - the marker lands by rename (a planted symlink is replaced, not followed);
#   - a session-end and a stop-failure each drop a leftover idle marker;
#   - a live permission's resume drops a co-resident idle marker with it;
#   - docs/fleet.md's hook table names the idle marker on Stop and PostToolUse.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FL="$here/../scripts/fleet-liveness.sh"
FA="$here/../scripts/fleet-attention.sh"
DOC="$here/../docs/fleet.md"
tab=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
ok() { echo "ok: $1"; }

[ -x "$FL" ] || fail "scripts/fleet-liveness.sh missing or not executable"
[ -x "$FA" ] || fail "scripts/fleet-attention.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

core_cfg="$tmp/core-defaults.yml"
adopter_root="$tmp/adopter"
mkdir -p "$adopter_root"
cat >"$core_cfg" <<'EOF'
fleet_daemon_pause: false
fleet_flailing_threshold: 3
fleet_hung_heartbeat_seconds: 900
fleet_crash_backoff_base_seconds: 30
fleet_crash_disable_threshold: 3
stale_marker_threshold: 15m
EOF

# fire <home> <handle> <scope> <event> [<payload>] — invoke the hook as a
# worker session's registered hook would: identity from the dispatch env.
fire() {
  f_home=$1 f_handle=$2 f_scope=$3 f_event=$4
  f_payload=${5:-'{"session_id":"s1","hook_event_name":"x"}'}
  printf '%s\n' "$f_payload" \
    | env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME -u PLANWRIGHT_ROOT \
      PLANWRIGHT_WORKER_HANDLE="$f_handle" PLANWRIGHT_WORKER_SCOPE="$f_scope" \
      PLANWRIGHT_FLEET_STATE_DIR="$f_home" PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
      PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" PLANWRIGHT_REPO_ROOT=none \
      PLANWRIGHT_LOCAL_CONFIG="" \
      /bin/sh "$FL" hook "$f_event"
}

attn() {
  a_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$a_home" PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" PLANWRIGHT_REPO_ROOT=none \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/sh "$FA" "$@"
}

state_of() {
  s_home=$1 s_worker=$2
  [ -f "$s_home/attention/state" ] || return 0
  awk -F "$tab" -v w="$s_worker" '($1 "") == (w "") { print $3 }' "$s_home/attention/state"
}

w=w1
s="fleet-messaging:6.5"

# ---------------------------------------------------------------------------
# 1. REQ-D1.11 — a stop that writes idle leaves the marker; the next
#    post-tool-use writes working and consumes it; a second writes nothing.
# ---------------------------------------------------------------------------
h1="$tmp/h1"
fire "$h1" "$w" "$s" stop >/dev/null 2>&1 || fail "1: stop exited non-zero"
[ "$(state_of "$h1" "$w")" = idle ] || fail "1: stop did not write idle"
[ -f "$h1/liveness/idle/$w" ] || fail "1: a stop that wrote idle left no idle marker"
fire "$h1" "$w" "$s" post-tool-use >/dev/null 2>&1 || fail "1: post-tool-use exited non-zero"
[ "$(state_of "$h1" "$w")" = working ] \
  || fail "1: post-tool-use after a stop left state '$(state_of "$h1" "$w")', expected working"
[ ! -e "$h1/liveness/idle/$w" ] || fail "1: post-tool-use did not consume the idle marker"
before=$(cat "$h1/attention/state")
sleep 1
fire "$h1" "$w" "$s" post-tool-use >/dev/null 2>&1 || fail "1: second post-tool-use exited non-zero"
[ "$(cat "$h1/attention/state")" = "$before" ] || fail "1: a second post-tool-use rewrote the store"
ok "stop leaves the idle marker; the next post-tool-use writes working once"

# ---------------------------------------------------------------------------
# 2. The escalation-preserve guard: a decision queued after the stop is never
#    resolved by the edge.
# ---------------------------------------------------------------------------
h2="$tmp/h2"
fire "$h2" "$w" "$s" stop >/dev/null 2>&1 || fail "2: stop exited non-zero"
[ -f "$h2/liveness/idle/$w" ] || fail "2: precondition: no idle marker"
attn "$h2" decide "$w" "$s" "no forward progress - task may be stuck" \
  "park for review" "park|relaunch-fresh|redirect" high >/dev/null 2>&1 \
  || fail "2: decide failed"
[ "$(state_of "$h2" "$w")" = awaiting-input ] || fail "2: precondition: decide did not queue"
before=$(cat "$h2/attention/state")
fire "$h2" "$w" "$s" post-tool-use >/dev/null 2>&1 || fail "2: post-tool-use exited non-zero"
[ "$(cat "$h2/attention/state")" = "$before" ] \
  || fail "2: post-tool-use over an awaiting-input row changed it"
ok "the idle edge leaves a decision queued after the stop as it was"

# ---------------------------------------------------------------------------
# 3. A stop that preserves a live fork-park leaves no idle marker.
# ---------------------------------------------------------------------------
h3="$tmp/h3"
fire "$h3" "$w" "$s" notification '{"notification_type":"idle_prompt"}' >/dev/null 2>&1 \
  || fail "3: notification exited non-zero"
[ -e "$h3/liveness/awaiting/$w" ] || fail "3: precondition: no fork-park marker"
fire "$h3" "$w" "$s" stop >/dev/null 2>&1 || fail "3: stop exited non-zero"
[ "$(state_of "$h3" "$w")" = awaiting-input ] || fail "3: precondition: the fork-park was not preserved"
[ ! -e "$h3/liveness/idle/$w" ] || fail "3: a stop preserving a live fork-park left an idle marker"
ok "a stop that preserves a live fork-park leaves no idle marker"

# ---------------------------------------------------------------------------
# 4. The fast path: with no exit-edge marker present, post-tool-use leaves the
#    store untouched.
# ---------------------------------------------------------------------------
h4="$tmp/h4"
fire "$h4" "$w" "$s" stop >/dev/null 2>&1 || fail "4: stop exited non-zero"
rm -f "$h4/liveness/idle/$w"
before=$(ls -la --time-style=full-iso "$h4/attention" 2>/dev/null || ls -la "$h4/attention")
before_state=$(cat "$h4/attention/state")
sleep 1
fire "$h4" "$w" "$s" post-tool-use >/dev/null 2>&1 || fail "4: post-tool-use exited non-zero"
[ "$(cat "$h4/attention/state")" = "$before_state" ] || fail "4: a marker-less post-tool-use rewrote the store"
after=$(ls -la --time-style=full-iso "$h4/attention" 2>/dev/null || ls -la "$h4/attention")
[ "$before" = "$after" ] || fail "4: a marker-less post-tool-use touched the store directory"
ok "post-tool-use with no exit-edge marker leaves the store untouched"

# ---------------------------------------------------------------------------
# 5. A failed marker write warns on stderr and still exits 0.
# ---------------------------------------------------------------------------
h5="$tmp/h5"
mkdir -p "$h5/liveness"
: >"$h5/liveness/idle"
rc=0
err=$(fire "$h5" "$w" "$s" stop 2>&1 >/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "5: a failed marker write exited $rc, expected 0"
[ -n "$err" ] || fail "5: a failed marker write was silent (expected a stderr warning)"
[ "$(state_of "$h5" "$w")" = idle ] || fail "5: the idle push did not land beside the failed marker write"
ok "a failed idle-marker write warns and exits 0"

# ---------------------------------------------------------------------------
# 6. The marker lands by rename: a symlink planted at the target is replaced,
#    never followed.
# ---------------------------------------------------------------------------
h6="$tmp/h6"
mkdir -p "$h6/liveness/idle"
victim="$tmp/victim"
printf 'untouched\n' >"$victim"
ln -s "$victim" "$h6/liveness/idle/$w"
fire "$h6" "$w" "$s" stop >/dev/null 2>&1 || fail "6: stop exited non-zero"
[ "$(cat "$victim")" = untouched ] || fail "6: the marker write followed a planted symlink"
[ -f "$h6/liveness/idle/$w" ] && [ ! -L "$h6/liveness/idle/$w" ] \
  || fail "6: the planted symlink was not replaced by a regular marker file"
ok "the idle marker lands by rename over a planted symlink"

# ---------------------------------------------------------------------------
# 7. A session-end and a stop-failure each drop a leftover idle marker.
# ---------------------------------------------------------------------------
for ev in session-end stop-failure; do
  h7="$tmp/h7-$ev"
  fire "$h7" "$w" "$s" stop >/dev/null 2>&1 || fail "7: stop exited non-zero"
  [ -f "$h7/liveness/idle/$w" ] || fail "7: precondition: no idle marker before $ev"
  fire "$h7" "$w" "$s" "$ev" >/dev/null 2>&1 || fail "7: $ev exited non-zero"
  [ ! -e "$h7/liveness/idle/$w" ] || fail "7: $ev left the idle marker behind"
done
ok "session-end and stop-failure each drop a leftover idle marker"

# ---------------------------------------------------------------------------
# 8. A live permission's resume drops a co-resident idle marker with it, so a
#    later post-tool-use does not fire a stale edge.
# ---------------------------------------------------------------------------
h8="$tmp/h8"
fire "$h8" "$w" "$s" stop >/dev/null 2>&1 || fail "8: stop exited non-zero"
fire "$h8" "$w" "$s" permission-request '{"tool_input":{"command":"ls"}}' >/dev/null 2>&1 \
  || fail "8: permission-request exited non-zero"
[ -f "$h8/liveness/idle/$w" ] || fail "8: precondition: no co-resident idle marker"
fire "$h8" "$w" "$s" post-tool-use >/dev/null 2>&1 || fail "8: post-tool-use exited non-zero"
[ "$(state_of "$h8" "$w")" = working ] || fail "8: the permission resume did not write working"
[ ! -e "$h8/liveness/idle/$w" ] || fail "8: the permission resume left the idle marker behind"
ok "a live permission's resume drops a co-resident idle marker"

# ---------------------------------------------------------------------------
# 9. docs/fleet.md's hook table names the idle marker on both edges.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016 # the backticks are literal markdown, not expansion
grep -q '^| `Stop` |.*idle exit-edge marker' "$DOC" \
  || fail "9: docs/fleet.md's Stop row does not name the idle exit-edge marker"
# shellcheck disable=SC2016 # the backticks are literal markdown, not expansion
grep -q '^| `PostToolUse` |.*idle exit-edge marker' "$DOC" \
  || fail "9: docs/fleet.md's PostToolUse row does not name the idle exit-edge marker"
ok "docs/fleet.md's hook table names the idle exit-edge marker"

echo "ALL PASS: fleet-liveness idle edge"
