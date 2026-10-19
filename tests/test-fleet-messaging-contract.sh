#!/bin/bash
# The messaging platform-contract drift guard (REQ-A1.4): the contract
# scripts/fleet-messaging.sh consumes is frozen in
# tests/fixtures/fleet-messaging/platform-contract.tsv, and this guard proves
# the script's own constants, frame, and record parse still match it. CI binds
# no messaging socket, so it cannot see the platform move; it sees a repo-side
# change break a frozen assumption, and fails naming that assumption. The live
# arm is each platform-touching task's re-verification against the running CLI.
#
# Runs standalone under /bin/bash (bash 3.2).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
FM="$root/scripts/fleet-messaging.sh"
FIXTURE="$here/fixtures/fleet-messaging/platform-contract.tsv"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# value <fixture> <key> — the frozen value, empty when the key is absent.
value() {
  awk -F '\t' -v k="$2" '$1 == k { v = $2 } END { print v }' "$1"
}

# version_ge <a> <b> — numeric per dotted component.
version_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    if (a !~ /^[0-9]+\.[0-9]+\.[0-9]+$/ || b !~ /^[0-9]+\.[0-9]+\.[0-9]+$/) exit 2
    split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
    exit 0
  }'
}

# keys_of <json-object-line> — the top-level keys in order, space-separated
# (a fixture frame or record has no nested key named like a top-level one
# that matters here: nested objects are skipped by depth).
keys_of() {
  printf '%s\n' "$1" | awk '{
    s = $0; n = length(s); d = 0; out = ""
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (c == "\"") {
        j = i + 1; t = ""
        while (j <= n && substr(s, j, 1) != "\"") { if (substr(s, j, 1) == "\\") j++; t = t substr(s, j, 1); j++ }
        k = j + 1
        if (d == 1 && substr(s, k, 1) == ":") out = out (out == "" ? "" : " ") t
        i = j
        continue
      }
      if (c == "{" || c == "[") d++
      if (c == "}" || c == "]") d--
    }
    print out
  }'
}

# check_contract <fixture> <script> — print each violated assumption, one per
# line; nothing when the contract holds.
check_contract() {
  cf=$1
  cs=$2
  [ -r "$cf" ] || {
    echo "the contract fixture is missing"
    return 0
  }
  pin=$(value "$cf" last_verified_pin)
  docmin=$(value "$cf" documented_minimum)
  pmin=$(value "$cf" probe_minimum)
  if [ -z "$pin" ]; then
    echo "last_verified_pin: absent"
  elif ! version_ge "$pin" "$pmin" 2>/dev/null; then
    echo "last_verified_pin: '$pin' is not a version at or above probe_minimum"
  fi
  version_ge "$pmin" "$docmin" 2>/dev/null || echo "probe_minimum: '$pmin' is not a version at or above documented_minimum '$docmin'"
  smin=$(awk -F= '/^PROBE_MIN_VERSION=/ { print $2; exit }' "$cs")
  [ "$smin" = "$pmin" ] || echo "probe_minimum: the script compares against '$smin', the contract freezes '$pmin'"
  envs=$(value "$cf" env_socket)
  [ -n "$envs" ] && grep -v '^[[:space:]]*#' "$cs" | grep -q "$envs" || echo "env_socket: the script does not read '$envs'"
  envt=$(value "$cf" env_token)
  [ -n "$envt" ] || echo "env_token: absent"
  if [ -n "$envt" ] && grep -v '^[[:space:]]*#' "$cs" | grep -q "$envt"; then
    echo "env_token: the script reads '$envt'; the post carries no auth line"
  fi
  for k in status_frame_type status_frame_action status_frame_keys status_values post_response \
    behavior_notice_gated_by_hold behavior_notice_gated_by_refuse behavior_second_notify_when_idle \
    behavior_name_beside_worktree_tmux behavior_claude_pid_in_session_start_hook \
    behavior_held_released_on_accept behavior_scheduled_wakeup_by_session_type; do
    [ -n "$(value "$cf" "$k")" ] || echo "$k: absent"
  done

  # The post: argv, frame keys, frame type, message keys, reply address.
  home="$tmp/home"
  mkdir -p "$home/.claude/sessions" "$tmp/socks" "$tmp/fleet" "$tmp/repo/.claude"
  printf '{"crossSessionInbound":"accept"}\n' >"$home/.claude/settings.json"
  : >"$tmp/socks/own.sock"
  : >"$tmp/socks/peer.sock"
  printf 'contract probe\n' >"$tmp/msg"
  cat >"$tmp/seam" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"$PLANWRIGHT_MESSAGING_POST_LOG"
cat >>"$PLANWRIGHT_MESSAGING_POST_LOG"
EOF
  chmod +x "$tmp/seam"
  : >"$tmp/post.log"
  post_rc=0
  sent=$(cd "$tmp" && env -u PLANWRIGHT_MESSAGING_INBOUND -u CLAUDE_CONFIG_DIR -u CLAUDE_PLUGIN_ROOT -u PLANWRIGHT_ROOT \
    HOME="$home" PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" CLAUDE_PLUGIN_DATA="$tmp/pd" CLAUDE_DIR="$tmp/cd" \
    PLANWRIGHT_CONFIG_DEFAULTS="$root/config/defaults.yml" PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp/repo" PLANWRIGHT_LOCAL_CONFIG="" PLANWRIGHT_TEST_SEAM=1 \
    PLANWRIGHT_MESSAGING_POST="$tmp/seam" PLANWRIGHT_MESSAGING_POST_LOG="$tmp/post.log" \
    CLAUDE_CODE_MESSAGING_SOCKET="$tmp/socks/own.sock" \
    /bin/sh "$cs" send --to "$tmp/socks/peer.sock" --message-file "$tmp/msg" --cli-version "$pin" --socket-type socket \
    2>/dev/null) || post_rc=$?
  # The seam answers nothing, the response the wire step observed.
  case $(value "$cf" post_response) in
    none)
      [ "$post_rc" = 0 ] && [ -n "$sent" ] \
        || echo "post_response: the frozen response is none, and an empty response with a clean write did not read as accepted (exit $post_rc)"
      ;;
    *) echo "post_response: '$(value "$cf" post_response)' is not a response this guard checks; extend it to the observed line" ;;
  esac
  argv=$(sed -n '1p' "$tmp/post.log")
  frame=$(sed -n '2p' "$tmp/post.log")
  want_argv="$(value "$cf" post_argv) $tmp/socks/peer.sock"
  [ "$argv" = "$want_argv" ] || echo "post_argv: the script posts with '$argv'"
  [ "$(keys_of "$frame")" = "$(value "$cf" frame_keys)" ] || echo "frame_keys: the frame carries '$(keys_of "$frame")'"
  case $frame in
    *'"type":"'"$(value "$cf" frame_type)"'"'*) ;;
    *) echo "frame_type: the frame is not of type '$(value "$cf" frame_type)'" ;;
  esac
  # The message object's keys in the frozen order, each one
  # holding a string.
  msg_re=$(value "$cf" message_keys | awk '{
    r = ""
    for (i = 1; i < NF; i++) r = r "\"" $i "\":\"[^\"]*\","
    print r "\"" $NF "\":\""
  }')
  printf '%s\n' "$frame" | grep -q "\"message\":{$msg_re" \
    || echo "message_keys: the frame's message is not {$(value "$cf" message_keys)}"
  case $frame in
    *'"from":"'"$(value "$cf" reply_address_prefix)$tmp/socks/own.sock"'"'*) ;;
    *) echo "reply_address_prefix: the frame's reply address is not the sender's own socket under '$(value "$cf" reply_address_prefix)'" ;;
  esac

  # The per-session record: a record of the frozen shape parses.
  rec="$home/.claude/sessions/777.json"
  printf '%s\n' "$(value "$cf" session_record_keys)" | awk -v nk="$(value "$cf" session_record_name_key)" \
    -v sk="$(value "$cf" session_record_socket_key)" '{
      printf "{"
      for (i = 1; i <= NF; i++) {
        v = "\"x\""
        if ($i == nk) v = "\"fleet-contract\""
        if ($i == sk) v = "\"/run/user/1/cc-socks/777.sock\""
        if ($i == "peerFeatures") v = "[\"notify_idle\"]"
        printf "%s\"%s\":%s", (i > 1 ? "," : ""), $i, v
      }
      print "}"
    }' >"$rec"
  got=$(env -u CLAUDE_CONFIG_DIR HOME="$home" CLAUDE_PID=777 /bin/sh "$cs" self-name 2>/dev/null) || got=""
  [ "$got" = fleet-contract ] || echo "session_record_keys: self-name cannot read the name from a record of the frozen shape"
  # self-register reads the socket key too; its amend lands on a recorder
  # beside a copy of the script, which reaches its siblings by its own path.
  sr="$tmp/sr"
  rm -rf "$sr"
  mkdir -p "$sr"
  cp "$cs" "$sr/fleet-messaging.sh"
  cp "$root/scripts/echo-safety.sh" "$sr/"
  printf '#!/bin/sh\nprintf "%%s " "$@"\n' >"$sr/fleet-register.sh"
  chmod +x "$sr/fleet-register.sh"
  got=$(env -u CLAUDE_CONFIG_DIR HOME="$home" CLAUDE_PID=777 PLANWRIGHT_WORKER_HANDLE=w1 \
    PLANWRIGHT_WORKER_SCOPE=spec:1 /bin/sh "$sr/fleet-messaging.sh" self-register 2>/dev/null) || got=""
  [ "$got" = "--amend w1 --name fleet-contract --inbox 777.sock " ] \
    || echo "session_record_socket_key: self-register cannot read the socket path from a record of the frozen shape"
  return 0
}

# The guard over the shipped fixture and script holds.
violations=$(check_contract "$FIXTURE" "$FM")
if [ -n "$violations" ]; then
  printf '%s\n' "$violations" | sed 's/^/drift: /' >&2
  fail "the messaging platform contract no longer holds"
fi
echo "ok: fleet-messaging.sh matches the frozen platform contract"

unrecorded=$(awk -F '\t' '$2 == "unrecorded" { print $1 }' "$FIXTURE")
if [ -n "$unrecorded" ]; then
  printf '%s\n' "$unrecorded" | sed 's/^/note: still unrecorded live: /'
fi

# The guard fails, naming the assumption, when one is violated.
expect_violation() {
  ev_label=$1
  ev_name=$2
  shift 2
  cp "$FIXTURE" "$tmp/f.tsv"
  cp "$FM" "$tmp/s.sh"
  cp "$root/scripts/echo-safety.sh" "$tmp/"
  "$@"
  out=$(check_contract "$tmp/f.tsv" "$tmp/s.sh")
  case $out in
    *"$ev_name"*) ;;
    *) fail "the guard did not catch $ev_label (got: $out)" ;;
  esac
}
drop() { sed -i.bak "/^$1	/d" "$tmp/f.tsv"; }
expect_violation "an absent pin" last_verified_pin drop last_verified_pin
expect_violation "a pin below the minimum" last_verified_pin sed -i.bak 's/^last_verified_pin	.*/last_verified_pin	2.1.200/' "$tmp/f.tsv"
expect_violation "a changed probe minimum" probe_minimum sed -i.bak 's/^PROBE_MIN_VERSION=.*/PROBE_MIN_VERSION=2.1.224/' "$tmp/s.sh"
expect_violation "a changed post argv" post_argv sed -i.bak 's/nc -N -w 5 -U/nc -U/g' "$tmp/s.sh"
expect_violation "a dropped reply address" frame_keys sed -i.bak 's/,\\"from\\":\\"%s\\"//; s/esc(b), esc(from), id/esc(b), id/' "$tmp/s.sh"
expect_violation "a changed record name key" session_record_keys sed -i.bak 's/^session_record_name_key	.*/session_record_name_key	sessionName/' "$tmp/f.tsv"
expect_violation "a renamed record socket key" session_record_socket_key sed -i.bak 's/messagingSocketPath/socketPathRenamed/g' "$tmp/s.sh"
expect_violation "a renamed socket variable" env_socket sed -i.bak '/^[[:space:]]*#/!s/CLAUDE_CODE_MESSAGING_SOCKET/CLAUDE_CODE_MSG_SOCKET/g' "$tmp/s.sh"
expect_violation "a renamed message key" message_keys sed -i.bak 's/\\"content\\"/\\"text\\"/' "$tmp/s.sh"
expect_violation "an empty response no longer accepted" post_response sed -i.bak 's/"" | accepted)/accepted)/' "$tmp/s.sh"
expect_violation "an unchecked response" post_response sed -i.bak 's/^post_response	.*/post_response	ok-line/' "$tmp/f.tsv"
# shellcheck disable=SC2016 # sed text planted in the copy, not expanded here
expect_violation "an auth line" env_token sed -i.bak 's/^MESSAGE_MAX_BYTES=65536$/MESSAGE_MAX_BYTES=65536 # CLAUDE_CODE_MESSAGING_TOKEN/; s/^JSON_MAX_BYTES=1048576$/JSON_MAX_BYTES=1048576; : "$CLAUDE_CODE_MESSAGING_TOKEN"/' "$tmp/s.sh"
expect_violation "a dropped behavior" behavior_held_released_on_accept drop behavior_held_released_on_accept
echo "ok: the guard names the violated assumption for each drift"

echo "PASS: test-fleet-messaging-contract.sh"
