#!/bin/bash
# Tests for the status line's `waiting` field — the queue's native indicator
# on the `statusline` notification channel (tower-comms D-17, REQ-C1.9).
#
# The field is fleet-autonomy REQ-F1.2's render extended in place: the top
# item's kind plus one total, fed by `tower-queue.sh counts`, under the line's
# own planwright label. It is lock-free and best-effort, and it degrades to one
# distinct unreadable marker — never a blank, never a zero — on a store that
# cannot be read, a torn or malformed line, or a kind outside the closed set.
# It renders only under the `statusline` channel and only while a live tower
# presence exists.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SL="$here/../scripts/fleet-statusline.sh"
TQ="$here/../scripts/tower-queue.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SL" ] || fail "scripts/fleet-statusline.sh missing or not executable"
[ -x "$TQ" ] || fail "scripts/tower-queue.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

home="$tmp/fleet"
mkdir -p "$home"
chmod 0700 "$home"
core_cfg="$tmp/core-defaults.yml"
repo="$tmp/repo"
mkdir -p "$repo/.claude"
tracked_cfg="$repo/.claude/planwright.yml"
local_cfg="$tmp/local.yml"
: >"$local_cfg"
printf 'notification_channel: none\n' >"$core_cfg"

surface="$home/tower-comms"
store="$surface/queue"
content="$tmp/content"
mkdir -p "$content"
presence="$home/presence/0123456789abcdef"

STDIN_JSON='{"cwd":"/w","session_id":"abc","model":{"id":"opus"}}'

statusline() {
  printf 'notification_channel: %s\n' "$1" >"$tracked_cfg"
  printf '%s' "$STDIN_JSON" \
    | PLANWRIGHT_FLEET_STATE_DIR="$home" \
      PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
      PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter" \
      PLANWRIGHT_REPO_ROOT="$repo" \
      PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
      /bin/bash "$SL"
}

run() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$TQ" "$@"
}

live_tower() {
  mkdir -p "$presence"
  chmod 0700 "$home/presence" "$presence"
  printf 'pw-presence-v1\t0123456789abcdef\ttower-x\t%s\t-\t-\t1\t2\tprocess 1\tfalse\n' "$repo" \
    >"$presence/tower-x"
  chmod 0600 "$presence/tower-x"
}

waiting_field() { # waiting_field <line> — the `waiting ...` segment, or empty
  printf '%s\n' "$1" | awk -F ' \\| ' '{ for (i = 1; i <= NF; i++) if ($i ~ /^waiting( |$)/) print $i }'
}

add_q() { # add_q <worker> <urgency>
  printf '%s\tspec\tawaiting-input\t1000\t%s\tblocked\t-\tA|B\t-\t-\n' "$1" "$2" >>"$attn_store"
  run add --kind question --worker "$1" --origin "$1" --closes 'the operator answers' --now 1000
}

attn_dir="$home/attention"
mkdir -p "$attn_dir"
chmod 0700 "$attn_dir"
attn_store="$attn_dir/state"
: >"$attn_store"
chmod 0600 "$attn_store"

# --- 1. No live tower presence: the field is absent, the rest of the line is not

q1=$(add_q w1 high)
line=$(statusline statusline) || fail "statusline with no tower presence: exit"
case $line in planwright*) ;; *) fail "the rest of the line did not render: '$line'" ;; esac
[ -z "$(waiting_field "$line")" ] || fail "the field rendered with no live tower presence: '$line'"
echo "ok: with no live tower presence the field is absent and the rest of the line still renders"

# --- 2. A live tower presence: the top kind plus one total ---------------------

live_tower
q2=$(add_q w2 normal)
line=$(statusline statusline) || fail "statusline with a live tower: exit"
[ "$(waiting_field "$line")" = "waiting question 2" ] \
  || fail "the field is not the top kind plus one total: '$(waiting_field "$line")' in '$line'"
[ "$(printf '%s\n' "$line" | grep -c .)" = 1 ] || fail "the line is not a single line"
case $line in *queue*) ;; *) fail "the field displaced the fleet stats' own queue field: '$line'" ;; esac
echo "ok: with a live tower the field renders the top item's kind and one total"

# --- 3. Only under the statusline channel ------------------------------------
# The gate is fleet-statusline.sh's, which renders nothing at all off this
# channel, so what is asserted here is the whole line rather than the field.

for ch in none tmux-popup os-notify editor-toast push; do
  line=$(statusline "$ch") || fail "statusline on the $ch channel: exit"
  [ -z "$line" ] || fail "the $ch channel rendered a status line at all: '$line'"
done
echo "ok: the field renders on no channel but statusline"

# --- 4. Nothing waiting is a genuine zero, said as such, never the marker -----

for id in $q1 $q2; do
  run settle "$id" --reason 'the worker landed it' --now 2000 >/dev/null 2>&1 || fail "settling $id"
done
line=$(statusline statusline) || fail "statusline with an empty queue: exit"
[ "$(waiting_field "$line")" = "waiting none" ] \
  || fail "an empty queue does not read as none: '$(waiting_field "$line")'"
echo "ok: an empty queue reads as none, not as the unreadable marker"

# --- 5. A torn line degrades to the unreadable marker, never a zero ----------

cp "$store" "$tmp/store.bak"
printf 'itorn0001\tquestion\tnormal\top\t1\tpath\tx\t-\n' >>"$store"
line=$(statusline statusline) || fail "statusline over a torn store: exit"
[ "$(waiting_field "$line")" = "waiting ?" ] \
  || fail "a torn store line did not degrade to the marker: '$(waiting_field "$line")'"
case $line in *planwright*queue*) ;; *) fail "a torn store broke the rest of the line: '$line'" ;; esac
cp "$tmp/store.bak" "$store"
echo "ok: a torn store line degrades to the unreadable marker and leaves the rest of the line"

# --- 6. A store that cannot be read degrades the same way --------------------

# chmod 0000 does not make a file unreadable to root, so under a root CI
# container this case would exercise nothing and fail green. Skipped there,
# loudly, rather than asserted on a measurement that was not taken.
if [ "$(id -u)" = 0 ]; then
  echo "skip: the unreadable-store case needs a non-root uid (chmod 0000 does not bind root)"
else
  chmod 0000 "$store"
  line=$(statusline statusline) || fail "statusline over an unreadable store: exit"
  [ "$(waiting_field "$line")" = "waiting ?" ] \
    || fail "an unreadable store did not degrade to the marker: '$(waiting_field "$line")'"
  case $line in *planwright*queue*) ;; *) fail "an unreadable store broke the rest of the line: '$line'" ;; esac
  chmod 0600 "$store"
fi

rm -f "$store"
line=$(statusline statusline) || fail "statusline over an absent store: exit"
[ "$(waiting_field "$line")" = "waiting ?" ] \
  || fail "an absent store did not degrade to the marker: '$(waiting_field "$line")'"
case $line in *planwright*queue*) ;; *) fail "an absent store broke the rest of the line: '$line'" ;; esac
cp "$tmp/store.bak" "$store"
chmod 0600 "$store"
echo "ok: an unreadable and an absent store both degrade to the unreadable marker"

# --- 7. A kind outside the closed set degrades the same way ------------------
# The top kind is what the field names, so a store whose top record carries a
# kind the grammar does not know must not reach the operator as that word.

# The renderer locates its sibling beside itself and takes no environment
# override for it — that path runs unattended on Claude Code's own schedule,
# and a variable naming an executable there would be a subprocess the operator
# never chose. So the stand-in is a copy of the renderer with a stub sibling,
# which is the same seam the real install uses.
stub="$tmp/stub"
mkdir -p "$stub"
cp "$here/../scripts/fleet-stats.sh" "$here/../scripts/echo-safety.sh" "$stub/"
cat >"$stub/tower-queue.sh" <<'EOF'
#!/bin/sh
# The presence row first, as the real verb prints it: it is emitted before the
# store is read so a failed read still carries it.
printf 'presence\tlive\nquestion\t1\napproval\t0\nrequest\t0\nnews\t0\nstanding\t0\ntotal\t1\ntop\tgremlin\nmalformed\t0\nstore\tpresent\n'
EOF
chmod +x "$stub/tower-queue.sh"
out=$(PLANWRIGHT_FLEET_STATE_DIR="$home" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
  PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter" \
  PLANWRIGHT_REPO_ROOT="$repo" \
  PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
  /bin/sh "$stub/fleet-stats.sh" line) || fail "fleet-stats line with an unknown kind: exit"
[ "$(waiting_field "$out")" = "waiting ?" ] \
  || fail "a kind outside the closed set reached the operator: '$(waiting_field "$out")'"
case $out in *gremlin*) fail "the unknown kind was rendered: '$out'" ;; esac
echo "ok: a kind outside the closed set degrades to the unreadable marker"

# --- 8. The render completes inside its stated ceiling over a full store ------
# Ceiling: 2 seconds for the whole line over a store at the retention cap. The
# read is lock-free, so this measures the scan, not a contended lock.

i=0
while [ "$i" -lt 500 ]; do
  i=$((i + 1))
  printf 'i%08x\tquestion\tnormal\tw%s\t1000\tpath\tf%s\t-\t%s\t-\tthe operator answers\topen\t0\t0\t0\t0\t0\t-\t-\t0\t-\t0\t-\t-\t0\n' \
    "$i" "$i" "$i" "$content" >>"$store"
done
t0=$(date +%s)
line=$(statusline statusline) || fail "statusline over a full store: exit"
t1=$(date +%s)
[ $((t1 - t0)) -le 2 ] || fail "the render took $((t1 - t0))s, past the stated 2s ceiling"
[ "$(waiting_field "$line")" = "waiting question 500" ] \
  || fail "the full-store render is wrong: '$(waiting_field "$line")'"
echo "ok: the render completes inside its stated 2s ceiling over a full-sized store"

echo "PASS: the status line's waiting field"
