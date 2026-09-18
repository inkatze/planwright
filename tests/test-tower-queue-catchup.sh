#!/bin/bash
# Tests for scripts/tower-queue.sh's `catchup` verb (REQ-B1.4, REQ-C1.8) — the
# lock-free render of what settled without the operator since their last reply.
# The settling pass that produces those records is in
# test-tower-queue-settle.sh; split from it so each file stays inside the
# per-file wall-clock budget.
#
# Contract under test:
#   catchup [--tower <id>] [--since <epoch>] [--now <epoch>]
#       One `settled` line per item — id, kind, urgency, the origins, the epoch
#       it settled, whether the operator was away, the reason, and the tower
#       that was holding it — most recent first, bounded to
#       `tower_catchup_limit` from the store; then a `remainder` counted from
#       the event log, marked `exact` or `floor` with the reason the log could
#       not cover the window; then the open counts by kind.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
TQ="$here/../scripts/tower-queue.sh"

# The stderr of the last `run`. Kept rather than discarded: a suite that sends
# the system under test to /dev/null reports its own generic message and hides
# the refusal that explains it.
errf=""

fail() {
  echo "FAIL: $1" >&2
  if [ -n "${errf:-}" ] && [ -s "$errf" ]; then
    echo "--- stderr of the last tower-queue run ---" >&2
    cat "$errf" >&2
  fi
  exit 1
}

[ -x "$TQ" ] || fail "scripts/tower-queue.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
errf="$tmp/stderr"

home="$tmp/fleet-home"
mkdir -p "$home"
chmod 0700 "$home"
adopter="$tmp/adopter"
mkdir -p "$adopter"
local_cfg="$tmp/local.yml"
: >"$local_cfg"

surface="$home/tower-comms"
store="$surface/queue"
log_file="$surface/events.log"
content="$tmp/content"
mkdir -p "$content"
ev="$tmp/evidence"

TAB=$(printf '\t')

run() {
  : >"$errf"
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$TQ" "$@" 2>"$errf"
}

# evidence <line>... — the already-derived table the pass consumes. Owner-only,
# the same bar the store is held to: what settles an item settles it without
# the operator ever seeing it.
evidence() {
  : >"$ev"
  chmod 0600 "$ev"
  for l in "$@"; do printf '%s\n' "$l" >>"$ev"; done
}

rec() { grep "^$1$TAB" "$store" || true; }

add_req() { # add_req <name> <subject> <now> [<urgency>]
  printf 'request %s\n' "$1" >"$content/$1"
  run add --kind request --root "$content" --pointer "$1" --origin operator \
    --subject "$2" --urgency "${4:-normal}" --closes 'the operator decides' --now "$3"
}

# --- a small settled history to render ------------------------------------------

A=tower-a

r_pr=$(add_req r-pr pr:42 1000) || fail "add r-pr"
r_br=$(add_req r-br branch:feature-x 1000) || fail "add r-br"
r_open1=$(add_req r-open1 - 1000) || fail "add r-open1"
add_req r-open2 pr:900 1000 >/dev/null || fail "add r-open2"
evidence "stamp${TAB}1010" "pr${TAB}42${TAB}merged" "branch${TAB}feature-x${TAB}commits"
run settle --evidence "$ev" --now 1100 >/dev/null || fail "the pass that settles the away pair"

mkdir -p "$surface/attention"
chmod 0700 "$surface/attention"
printf '1200\n' >"$surface/attention/$A"
chmod 0600 "$surface/attention/$A"
r_here=$(add_req r-here pr:71 1200) || fail "add r-here"
evidence "stamp${TAB}1201" "pr${TAB}71${TAB}merged"
run settle --evidence "$ev" --now 1210 >/dev/null || fail "the pass that settles with the operator present"

# One more, settled while a conversation was holding it: the catch-up is how
# that conversation learns its item closed (REQ-B1.4).
held=$(add_req r-held pr:80 1300 high) || fail "add r-held"
printf '1301\n' >"$surface/attention/$A"
chmod 0600 "$surface/attention/$A"
run next --tower $A --evidence "$ev" --now 1302 >/dev/null || fail "the knock before the held hand-over"
printf '1303\n' >"$surface/attention/$A"
chmod 0600 "$surface/attention/$A"
out=$(run next --tower $A --evidence "$ev" --now 1304) || fail "the held hand-over exited non-zero"
handed=$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "item" { print $2; exit }')
[ "$handed" = "$held" ] || fail "the held item was not the one handed over: '$handed'"
evidence "stamp${TAB}1310" "pr${TAB}80${TAB}merged"
run settle --evidence "$ev" --now 1320 >/dev/null || fail "the pass that settles a held item"
[ "$(rec "$held" | cut -f 24)" = "$A" ] || fail "the item does not record the tower that held it"

# --- catchup: the settled history with reasons, bounded, then the open counts -----

out=$(run catchup --now 3000) || fail "catchup exited non-zero"
printf '%s\n' "$out" | grep -q "^settled${TAB}$r_pr${TAB}request${TAB}" || fail "catchup does not list a settled item"
printf '%s\n' "$out" | awk -F "$TAB" -v i="$r_pr" '$1 == "settled" && $2 == i { print $8 }' | grep -q 'PR #42 is merged' \
  || fail "catchup does not carry the settle reason"
printf '%s\n' "$out" | grep -q "^settled${TAB}$r_open1${TAB}" && fail "catchup listed an open item"
printf '%s\n' "$out" | grep -q "^open${TAB}request${TAB}" || fail "catchup prints no open count per kind"
# Bound to a number the render actually printed: `[ "" -ge 2 ]` is a syntax
# error, not a clean failure, so a missing count would report as noise on
# stderr rather than as the assertion it is.
open_req=$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "open" && $2 == "request" { print $3 }')
case "$open_req" in '' | *[!0-9]*) fail "catchup printed no usable open request count: '$open_req'" ;; esac
[ "$open_req" -ge 2 ] || fail "catchup's open request count is wrong: $open_req"
[ "$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "remainder" { print $2 }')" = 0 ] \
  || fail "catchup reported a remainder with everything shown"
[ "$(printf '%s\n' "$out" | awk -F "$TAB" -v i="$r_br" '$1 == "settled" && $2 == i { print $7 }')" = 1 ] \
  || fail "catchup's away column does not carry a settle made with nobody present"
# Most recent first: the last item settled leads the list.
[ "$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "settled" { print $2; exit }')" = "$held" ] \
  || fail "catchup is not ordered most recent first"

# The window is the operator's own last reply in that conversation: a reply
# after everything settled leaves nothing to catch up on.
printf '2900\n' >"$surface/attention/$A"
chmod 0600 "$surface/attention/$A"
out=$(run catchup --tower $A --now 3000) || fail "catchup --tower exited non-zero"
printf '%s\n' "$out" | grep -q "^settled${TAB}$r_here${TAB}" && fail "catchup showed an item settled before the operator's last reply"
[ "$(printf '%s\n' "$out" | grep -c "^settled${TAB}" || true)" = 0 ] || fail "catchup's since-last-reply window is not applied"
# And the other direction: a reply older than a settle puts it back in the window.
printf '1205\n' >"$surface/attention/$A"
chmod 0600 "$surface/attention/$A"
out=$(run catchup --tower $A --now 3000) || fail "catchup --tower over an older reply exited non-zero"
printf '%s\n' "$out" | grep -q "^settled${TAB}$r_here${TAB}" || fail "catchup dropped an item settled after the operator's last reply"
printf '%s\n' "$out" | grep -q "^settled${TAB}$r_pr${TAB}" && fail "catchup showed an item settled before the window opened"
# The away flag reaches the render the tower actually reads, not just the store.
[ "$(printf '%s\n' "$out" | awk -F "$TAB" -v i="$held" '$1 == "settled" && $2 == i { print $7 }')" = 0 ] \
  || fail "catchup's away column does not match the record"
[ "$(printf '%s\n' "$out" | awk -F "$TAB" -v i="$held" '$1 == "settled" && $2 == i { print $9 }')" = "$A" ] \
  || fail "catchup does not say which conversation was holding the item when it settled"
printf '2900\n' >"$surface/attention/$A"
chmod 0600 "$surface/attention/$A"
echo "ok: catchup lists what settled since the operator's last reply, with reasons, most recent first, beside the open counts"

# --- --since names the window directly, with no conversation to read it from -----

# The three settles are at 1100 (r_pr, r_br), 1210 (r_here) and 1320 (held), so
# each bound below falls in a different gap between them.
out=$(run catchup --since 1250 --now 3000) || fail "catchup --since exited non-zero"
printf '%s\n' "$out" | grep -q "^settled${TAB}$held${TAB}" || fail "catchup --since dropped an item settled inside the window"
printf '%s\n' "$out" | grep -q "^settled${TAB}$r_here${TAB}" && fail "catchup --since showed an item settled before the bound"
printf '%s\n' "$out" | grep -q "^settled${TAB}$r_pr${TAB}" && fail "catchup --since showed an item settled well before the bound"
out=$(run catchup --since 1150 --now 3000) || fail "catchup --since at an earlier bound exited non-zero"
printf '%s\n' "$out" | grep -q "^settled${TAB}$r_here${TAB}" || fail "catchup --since did not widen with an earlier bound"
printf '%s\n' "$out" | grep -q "^settled${TAB}$r_pr${TAB}" && fail "catchup --since at 1150 showed an item settled at 1100"
echo "ok: --since bounds the window itself, without a conversation's last reply to read it from"

# The list is bounded by the knob; the count of everything past it comes from
# the event log, which holds the history the store's horizon has dropped.
logged=$(grep -c '"kind":"settled"\|"kind":"merged"' "$log_file" || true)
[ "$logged" -ge 3 ] || fail "too few settled events to bound: $logged"
printf 'tower_catchup_limit: 2\n' >"$local_cfg"
out=$(run catchup --now 3000) || fail "catchup at a lowered bound exited non-zero"
[ "$(printf '%s\n' "$out" | grep -c "^settled${TAB}" || true)" = 2 ] || fail "catchup did not bound the list to tower_catchup_limit"
[ "$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "remainder" { print $2 }')" = "$((logged - 2))" ] \
  || fail "catchup's remainder is not the event log's count past the list: '$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "remainder" { print $2 }')' against $((logged - 2))"
[ "$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "remainder" { print $3 }')" = exact ] \
  || fail "a complete event log did not give an exact remainder"
: >"$local_cfg"
echo "ok: catchup bounds the list to tower_catchup_limit and counts the rest from the event log"

# A rotated or truncated log can only bound the remainder from below, and says
# so rather than printing a count nobody can stand behind.
cp "$log_file" "$tmp/log.full"
tail -n +3 "$tmp/log.full" >"$log_file"
chmod 0600 "$log_file"
printf 'tower_catchup_limit: 2\n' >"$local_cfg"
out=$(run catchup --now 3000) || fail "catchup over a truncated log exited non-zero"
[ "$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "remainder" { print $3 }')" = floor ] \
  || fail "a truncated log did not render the remainder as a floor"
[ "$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "remainder" { print $4 }')" = log-rotated \
  ] || fail "the floor does not say the log was short: '$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "remainder" { print $4 }')'"

mv "$log_file" "$tmp/log.short"
out=$(run catchup --now 3000) || fail "catchup with no log exited non-zero"
[ "$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "remainder" { print $4 }')" = log-absent \
  ] || fail "a missing log did not say so"
cp "$tmp/log.full" "$log_file"
chmod 0600 "$log_file"
: >"$local_cfg"
echo "ok: a rotated or absent event log makes the remainder a floor, named as one"

echo "PASS: tower-queue catch-up"
