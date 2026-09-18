#!/bin/bash
# Tests for the standing-decision match and the settle-by-rule route —
# scripts/tower-queue.sh's `match` verb, the settling pass answering a worker
# permission prompt from a written rule through the sanctioned answer channel,
# and what `next` surfaces beside an item without settling it (REQ-B1.2,
# REQ-E1.4, REQ-E1.5, REQ-E1.7, REQ-E1.8, REQ-E1.9, REQ-E1.10, REQ-H1.1,
# REQ-H1.2; D-12).
#
# Contract under test:
#   match --decision <id> --command <text>
#       Prints `match`, `no-match` or `reserved`; exit 0 only on a match.
#   settle (the pass)
#       A permission prompt strictly inside a rule is answered and settled with
#       a reason naming the decision's identifier, plus an `answered` line
#       carrying the rule in the operator's own words and no identifier.
#   next
#       Prints the command being approved and any free-coverage rule on the
#       item's subject, and settles nothing by doing so.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
TQ="$here/../scripts/tower-queue.sh"
FA="$here/../scripts/fleet-attention.sh"

errf=""

fail() {
  echo "FAIL: $1" >&2
  if [ -n "${errf:-}" ] && [ -s "$errf" ]; then
    echo "--- stderr of the last run ---" >&2
    cat "$errf" >&2
  fi
  exit 1
}

[ -x "$TQ" ] || fail "scripts/tower-queue.sh missing or not executable"
[ -x "$FA" ] || fail "scripts/fleet-attention.sh missing or not executable"

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
attn_store="$home/attention/state"

TAB=$(printf '\t')
APPROVE='approve in the worker session'

run() {
  : >"$errf"
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$TQ" "$@" 2>"$errf"
}

fa() {
  : >"$errf"
  PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FA" "$@" 2>"$errf"
}

f() { printf '%s' "$1" | cut -d"$TAB" -f"$2"; }

# line <output> <tag> — the first line of the output carrying that tag.
line() {
  printf '%s\n' "$1" | awk -F "$TAB" -v t="$2" '$1 == t { print; exit }'
}

rec() { awk -F "$TAB" -v i="$1" -v n="$2" '($1 "") == (i "") { print $n; exit }' "$store"; }

fresh() {
  rm -rf "$surface" "$home/attention"
}

# --- the match, in isolation ------------------------------------------------

fresh
rule=$(f "$(run capture --kind standing --text 'always let the workers run read-only git' \
  --covers-command 'git status' --covers-command 'git log' --now 1000)" 2) \
  || fail "capture of the rule failed"

run match --decision "$rule" --command 'git status --short' >"$tmp/o" || fail "a covered command did not match"
[ "$(cat "$tmp/o")" = match ] || fail "a covered command printed '$(cat "$tmp/o")'"
echo "ok: a command inside the rule matches"

# The command IS the prefix.
run match --decision "$rule" --command 'git status' >/dev/null || fail "the bare prefix did not match"
echo "ok: the bare prefix matches"

# One token outside it.
rc=0
run match --decision "$rule" --command 'git fetch --tags' >"$tmp/o" || rc=$?
[ "$rc" = 1 ] && [ "$(cat "$tmp/o")" = no-match ] || fail "a command outside the rule was not refused (exit $rc, '$(cat "$tmp/o")')"
echo "ok: a command outside every prefix does not match"

# Sharing only part of a token with a prefix (`git statuses`) is not a match.
rc=0
run match --decision "$rule" --command 'git statuses' >"$tmp/o" || rc=$?
[ "$rc" = 1 ] && [ "$(cat "$tmp/o")" = no-match ] || fail "a prefix continued inside its own token matched (exit $rc)"
echo "ok: a covered prefix followed by more of the same token does not match"

# The allowlist: anything outside it after the prefix refuses the match.
# shellcheck disable=SC2016 # the whole point is that these stay unexpanded
for bad in 'git status; rm -rf /' 'git status | sh' 'git status && ls' 'git status `id`' \
  'git status $(id)' 'git status \$x' 'git status >out'; do
  rc=0
  run match --decision "$rule" --command "$bad" >"$tmp/o" || rc=$?
  # The TAG matters, not just the exit: `reserved` also exits 1, so a command
  # refused by the wrong branch would pass an exit-only assertion.
  [ "$rc" = 1 ] && [ "$(cat "$tmp/o")" = no-match ] \
    || fail "a shell-operator suffix ('$bad') was not refused by the allowlist (exit $rc, '$(cat "$tmp/o")')"
done
echo "ok: a remainder outside the allowlist refuses the match"

# A quoted-string interior is admitted; the quote may not re-open into expansion.
run match --decision "$rule" --command 'git log --grep="fix the thing"' >/dev/null \
  || fail "a quoted-string interior was refused"
rc=0
# shellcheck disable=SC2016
run match --decision "$rule" --command 'git log --grep="`id`"' >/dev/null || rc=$?
[ "$rc" = 1 ] || fail "a backtick inside double quotes matched (exit $rc)"
rc=0
run match --decision "$rule" --command 'git log --grep="unterminated' >/dev/null || rc=$?
[ "$rc" = 1 ] || fail "an unterminated quote matched (exit $rc)"
echo "ok: a quoted interior is admitted but never re-opens into expansion"

# The mechanical reserved-control refusal, whatever the rule covers. The rule
# above covers `git log`, and this command starts with it.
rc=0
run match --decision "$rule" --command 'git log --merge' >"$tmp/o" || rc=$?
[ "$rc" = 1 ] && [ "$(cat "$tmp/o")" = reserved ] || fail "a reserved-control command matched under a covering rule (exit $rc, '$(cat "$tmp/o")')"
echo "ok: a reserved-control command is refused at match time whatever the rule covers"

# The push shapes. The earlier guard spelled the default branch out as ` main`
# and `:main`, so `git push origin +main` — a force-push to main, two reserved
# actions in one command — and `git push origin refs/heads/main` both walked
# through it. These are pinned by shape, not by the wording of the guard.
push_rule=$(f "$(run capture --kind standing --text 'always let the workers push their own branch' \
  --covers-command 'git push ' --now 1010)" 2) || fail "capture of the push rule failed"
for res in 'git push origin +main' 'git push origin refs/heads/main' \
  'git push origin +refs/heads/main' 'git push origin HEAD:refs/heads/main' \
  'git push --force origin main' 'git push origin +master' \
  'git push origin main' 'git push origin HEAD:main' 'git push origin main:main' \
  'git push -qf origin feature' 'git push origin "main"'; do
  rc=0
  run match --decision "$push_rule" --command "$res" >"$tmp/o" || rc=$?
  [ "$rc" = 1 ] && [ "$(cat "$tmp/o")" = reserved ] \
    || fail "'$res' was not refused as a reserved control (exit $rc, '$(cat "$tmp/o")')"
done
echo "ok: every spelling of a force-push or a push to the default branch is refused"

# The quoted spellings. The allowlist admits a quoted interior anywhere in a
# word, and the shell reads each of these as the bare spelling above; the
# guard once stripped one matched pair of quotes, after the prefix test, so
# every one of these walked through it.
for res in 'git push origin "refs/heads/main"' "git push origin 'refs/heads/main'" \
  'git push origin "+main"' "git push origin '+refs/heads/main'" \
  'git push origin "HEAD:refs/heads/main"' 'git push origin HEAD:"refs/heads/main"' \
  "git push origin ''main" 'git push origin ma""in' "git push origin m'ai'n" \
  'git push origin "-f" feature' 'git push "--force" origin feature'; do
  rc=0
  run match --decision "$push_rule" --command "$res" >"$tmp/o" || rc=$?
  [ "$rc" = 1 ] && [ "$(cat "$tmp/o")" = reserved ] \
    || fail "'$res' was not refused as a reserved control (exit $rc, '$(cat "$tmp/o")')"
done
echo "ok: a quoted spelling of a force-push or a push to the default branch is refused"

# The policy is positive, not a list of bad spellings: a rule may answer a push
# only when its every destination is parsed and safe. A push that spells no
# destination — the current branch, every matching branch, or one moved into
# configuration — reaches the operator, as does any option or word the parse
# has not been reasoned about.
for res in 'git push' 'git push origin' 'git push origin :' 'git push origin :feature' \
  'git push --all origin' 'git push --mirror origin' 'git push origin HEAD' 'git push origin @' \
  'git push origin feature main' 'git push origin feature:' \
  'git -c push.default=matching push origin' 'git -c remote.origin.push=refs/heads/main push origin' \
  'git -C /tmp/x push origin feature' 'git push --tags origin' 'git push --no-verify origin feature' \
  'git push --repo=x origin feature' 'git push -o ci.skip origin feature' \
  'git push git@github.com:x/y.git feature' 'git push https://example/x.git feature' \
  'git push origin feature:refs/tags/v1' 'git push origin feature:refs/for/main' \
  'sudo git push origin feature' 'command git push origin feature' \
  'git push origin feature --' 'git push origin ""'; do
  rc=0
  run match --decision "$push_rule" --command "$res" >"$tmp/o" || rc=$?
  [ "$rc" = 1 ] && [ "$(cat "$tmp/o")" = reserved ] \
    || fail "'$res', a push with no positively parsed safe destination, was not refused (exit $rc, '$(cat "$tmp/o")')"
  grep -q 'positively named' "$errf" || fail "the refusal of '$res' did not say why"
done
echo "ok: a push whose destination cannot be positively named reaches the operator"

# The rule the operator actually wanted still works, in every admitted shape.
for okp in 'git push origin feature/thing' 'git push origin "feature/thing"' 'git push -u origin feature' \
  'git push origin feature -v' 'git push origin main:feature' 'git push origin refs/heads/feature' \
  'git push origin head:feature' 'git push origin feature:refs/heads/feature' 'git push upstream fix-1'; do
  run match --decision "$push_rule" --command "$okp" >"$tmp/o" \
    || fail "an ordinary branch push ('$okp') did not match (exit $?, '$(cat "$tmp/o")')"
  [ "$(cat "$tmp/o")" = match ] || fail "an ordinary branch push ('$okp') printed '$(cat "$tmp/o")'"
done
echo "ok: an ordinary branch push still matches"

# The negative screen is what a rule's COVERAGE is held to: a prefix is not a
# command, so `git push ` is a rule the operator may write, and the positive
# parse is applied to each command it is asked to answer.
[ -n "$push_rule" ] || fail "the push prefix rule was not captured"
echo "ok: a push prefix is capturable and each command under it is parsed on its own"

# A glob in the command is compared as the bytes it is, never expanded against
# whatever the pass's working directory holds. Expanded against a file named
# `feature`, the word would parse as a safe destination and the command would
# then fall to the allowlist as `no-match`; unexpanded it is a word the parse
# refuses, wherever the pass runs.
rc=0
(cd "$tmp" && touch feature && run match --decision "$push_rule" --command 'git push origin feat*' >"$tmp/o") || rc=$?
[ "$rc" = 1 ] && [ "$(cat "$tmp/o")" = reserved ] \
  || fail "a glob in a push was expanded against the working directory (exit $rc, '$(cat "$tmp/o")')"
echo "ok: a glob in a push is never expanded against the working directory"

# A decision the queue does not hold, or that is not a standing decision.
rc=0
run match --decision i00000000 --command 'git status' >/dev/null || rc=$?
[ "$rc" = 2 ] || fail "an unknown decision was not refused (exit $rc)"
req=$(f "$(run capture --kind request --text 'do a thing' --now 1001)" 2)
rc=0
run match --decision "$req" --command 'git status' >/dev/null || rc=$?
[ "$rc" = 2 ] || fail "a non-standing item was accepted as a decision (exit $rc)"
echo "ok: an unknown or non-standing decision is refused"

# A revoked rule answers nothing more.
run settle "$rule" --reason 'the operator revoked it' --now 1002 >/dev/null || fail "revoking the rule failed"
rc=0
run match --decision "$rule" --command 'git status' >/dev/null || rc=$?
[ "$rc" = 2 ] || fail "a revoked rule still matched (exit $rc)"
echo "ok: a revoked rule matches nothing"

# --- the settle-by-rule route ----------------------------------------------

fresh
rule=$(f "$(run capture --kind standing --text 'always let the workers run read-only git' \
  --covers-command 'git status' --now 2000)" 2) || fail "capture of the rule failed"
fa permission w1 spec.task-1 'git status --short' || fail "the permission push failed"
item=$(run add --kind question --origin w1 --worker w1 --closes 'the operator answers' --now 2001) || fail "queueing the prompt failed"

out=$(run settle --now 2002) || fail "the settling pass failed"
settled=$(line "$out" settled)
[ -n "$settled" ] || fail "the covered prompt did not settle: $out"
[ "$(f "$settled" 2)" = "$item" ] || fail "the pass settled the wrong item: $settled"
case $(f "$settled" 5) in
  *"$rule"*) ;;
  *) fail "the settling record does not carry the decision's identifier: $settled" ;;
esac
answered=$(line "$out" answered)
[ -n "$answered" ] || fail "the pass spoke no rule for the answer it gave: $out"
[ "$(f "$answered" 3)" = "$rule" ] || fail "the answered line names the wrong decision: $answered"
[ "$(f "$answered" 4)" = 'always let the workers run read-only git' ] || fail "the answered line does not name the rule in the operator's words: $answered"
case $(f "$answered" 4) in
  *"$rule"*) fail "the spoken text carries the decision's identifier: $answered" ;;
esac
[ "$(rec "$item" 12)" = closed ] || fail "the item did not close"
echo "ok: a prompt inside a rule is answered and settled naming the rule"

# The answer went through the sanctioned channel, not into the row by hand.
[ "$(awk -F "$TAB" '$1 == "w1" { print $11 }' "$attn_store")" = "$APPROVE" ] \
  || fail "the answer channel did not stamp the claim"
# The answered row must keep the command it was answered about, or the answer
# cannot be audited against anything afterwards.
[ "$(awk -F "$TAB" '$1 == "w1" { print (NF >= 12 ? $12 : "") }' "$attn_store")" = 'git status --short' ] \
  || fail "the close pass truncated the command off the answered row"
echo "ok: the answer went through the answer channel and kept the command it answered"

# The log line carries the identifier too.
grep -q "\"reason\":\"answered from the standing decision $rule\"" "$surface/events.log" \
  || fail "the event log's settled line does not carry the decision's identifier"
echo "ok: the log line carries the decision's identifier"

# The settling pass has its own guard (rule_covers), reached before the answer
# channel; `match` alone would not prove the path that actually settles items.
fresh
run capture --kind standing --text 'always let the workers push their own branch' \
  --covers-command 'git push ' --now 2100 >/dev/null || fail "capture of the push rule failed"
fa permission wr spec.task-1 'git push origin +main' || fail "the permission push failed"
item=$(run add --kind question --origin wr --worker wr --closes 'the operator answers' --now 2101) \
  || fail "queueing the prompt failed"
out=$(run settle --now 2102) || fail "the settling pass failed"
[ "$(rec "$item" 12)" = open ] || fail "the settling pass answered a reserved-control command: $out"
[ "$(awk -F "$TAB" '$1 == "wr" { print $11 }' "$attn_store")" = - ] \
  || fail "the settling pass claimed a reserved-control prompt"
echo "ok: the settling pass refuses a reserved-control command under a covering rule"

# --- a prompt one token outside the rule -----------------------------------

fresh
rule=$(f "$(run capture --kind standing --text 'always let the workers run read-only git' \
  --covers-command 'git status' --now 3000)" 2) || fail "capture of the rule failed"
fa permission w2 spec.task-1 'git fetch --tags' || fail "the permission push failed"
item=$(run add --kind question --origin w2 --worker w2 --closes 'the operator answers' --now 3001) || fail "queueing the prompt failed"
out=$(run settle --now 3002) || fail "the settling pass failed"
[ -z "$(line "$out" settled)" ] || fail "a prompt outside every rule was settled: $out"
[ "$(rec "$item" 12)" = open ] || fail "a prompt outside every rule did not stay open"
# `-` is the placeholder the permission writer reserves field 11 with; a real
# label there would mean the prompt was answered.
[ "$(awk -F "$TAB" '$1 == "w2" { print $11 }' "$attn_store")" = - ] \
  || fail "a prompt outside every rule was answered anyway"
echo "ok: a prompt outside every rule reaches the operator, unanswered"

# A remainder that leaves the allowlist after a covered prefix is never answered.
fresh
run capture --kind standing --text 'always let the workers run read-only git' \
  --covers-command 'git status' --now 3100 >/dev/null || fail "capture of the rule failed"
fa permission w3 spec.task-1 'git status; rm -rf /tmp/x' || fail "the permission push failed"
item=$(run add --kind question --origin w3 --worker w3 --closes 'the operator answers' --now 3101) || fail "queueing the prompt failed"
out=$(run settle --now 3102) || fail "the settling pass failed"
[ "$(rec "$item" 12)" = open ] || fail "a command leaving the allowlist was settled: $out"
echo "ok: a command whose remainder leaves the allowlist is never answered"

# --- a record with no marker, or no command --------------------------------

fresh
run capture --kind standing --text 'always let the workers run read-only git' \
  --covers-command 'git status' --now 3200 >/dev/null || fail "capture of the rule failed"
# A plain `decide` row: awaiting-input, no marker, and prose that mentions the
# command. Nothing here may be matched from that prose (REQ-E1.8).
fa decide w4 spec.task-1 'may I run git status --short' 'yes' 'yes|no' || fail "the decide push failed"
item=$(run add --kind question --origin w4 --worker w4 --closes 'the operator answers' --now 3201) || fail "queueing the decision failed"
out=$(run settle --now 3202) || fail "the settling pass failed"
[ "$(rec "$item" 12)" = open ] || fail "a record with no permission marker was matched: $out"
echo "ok: a record with no permission marker is never matched"

fresh
run capture --kind standing --text 'always let the workers run read-only git' \
  --covers-command 'git status' --now 3300 >/dev/null || fail "capture of the rule failed"
fa permission w5 spec.task-1 || fail "the permission push failed"
item=$(run add --kind question --origin w5 --worker w5 --closes 'the operator answers' --now 3301) || fail "queueing the prompt failed"
out=$(run settle --now 3302) || fail "the settling pass failed"
[ "$(rec "$item" 12)" = open ] || fail "a record with no command field was matched: $out"
echo "ok: a record with the marker but no command is never matched"

# --- a non-command rule beside an item -------------------------------------

fresh
free=$(f "$(run capture --kind standing --text 'always prefer the smaller PR on task 5' \
  --covers 'anything about task 5' --subject worker:w6 --now 4000)" 2) \
  || fail "capture of the non-command rule failed"
fa permission w6 spec.task-1 'gh pr diff 471' || fail "the permission push failed"
item=$(run add --kind question --origin w6 --worker w6 --closes 'the operator answers' --now 4001) || fail "queueing the prompt failed"

# The rule settles nothing mechanically.
out=$(run settle --now 4002) || fail "the settling pass failed"
[ "$(rec "$item" 12)" = open ] || fail "a non-command rule settled an item: $out"
echo "ok: a non-command rule settles nothing mechanically"

# It is surfaced beside the item at the hand-over instead.
run log knocked --tower t1 --now 4003 item="$item" item_kind=question urgency=normal >/dev/null \
  || fail "seeding the knock failed"
out=$(run next --tower t1 --now 4004) || fail "the knocking next failed"
[ -n "$(line "$out" knock)" ] || fail "next did not knock: $out"
mkdir -p "$surface/attention"
chmod 0700 "$surface/attention"
printf '%s\n' 4005 >"$surface/attention/t1"
chmod 0600 "$surface/attention/t1"
out=$(run next --tower t1 --now 4006) || fail "the delivering next failed"
[ -n "$(line "$out" item)" ] || fail "next handed nothing over: $out"
rule_line=$(line "$out" rule)
[ -n "$rule_line" ] || fail "the non-command rule was not surfaced beside the item: $out"
[ "$(f "$rule_line" 2)" = "$free" ] || fail "the rule line names the wrong decision: $rule_line"
[ "$(f "$rule_line" 3)" = 'always prefer the smaller PR on task 5' ] || fail "the rule line does not carry the rule's words: $rule_line"
[ "$(rec "$item" 12)" = open ] || fail "surfacing the rule closed the item"
echo "ok: a non-command rule is surfaced beside the item and settles nothing"

# The command the operator is being asked to approve goes over with it.
cmd_line=$(line "$out" command)
[ -n "$cmd_line" ] || fail "the command being approved was not shown: $out"
[ "$(f "$cmd_line" 3)" = 'gh pr diff 471' ] || fail "the command line carries the wrong text: $cmd_line"
echo "ok: the command being approved is shown with the item"

# Command text the operator could misread is shown as escapes, with a warning.
fresh
fa permission w7 spec.task-1 "$(printf 'gh pr diff \303\251')" || fail "the permission push failed"
item=$(run add --kind question --origin w7 --worker w7 --closes 'the operator answers' --now 4100) \
  || fail "queueing the prompt failed"
run log knocked --tower t1 --now 4101 item="$item" item_kind=question urgency=normal >/dev/null \
  || fail "seeding the knock failed"
run next --tower t1 --now 4102 >/dev/null || fail "the knocking next failed"
mkdir -p "$surface/attention"
chmod 0700 "$surface/attention"
printf '%s\n' 4103 >"$surface/attention/t1"
chmod 0600 "$surface/attention/t1"
out=$(run next --tower t1 --now 4104) || fail "the delivering next failed"
cmd_line=$(line "$out" command)
[ "$(f "$cmd_line" 3)" = 'gh pr diff \xc3\xa9' ] || fail "non-ASCII command text was not escaped: $cmd_line"
grep -q 'outside printable ASCII' "$errf" || fail "the escaped command came with no warning"
echo "ok: non-ASCII command text is shown escaped beside a warning"

# --- the answer channel's own check on a named rule -------------------------

fresh
rule=$(f "$(run capture --kind standing --text 'always let the workers run read-only git' \
  --covers-command 'git status' --now 5000)" 2) || fail "capture of the rule failed"
fa permission w8 spec.task-1 'git push --tags' || fail "the permission push failed"
rc=0
fa claim w8 - "$APPROVE" --standing "$rule" || rc=$?
[ "$rc" = 3 ] || fail "the channel accepted an answer whose rule does not cover the command (exit $rc)"
[ "$(awk -F "$TAB" '$1 == "w8" { print $11 }' "$attn_store")" = - ] \
  || fail "the refused answer stamped a claim anyway"
echo "ok: an answer whose named rule does not cover the parked command is refused"

# And the channel's own re-match is what decides, not the caller: a request is
# not a standing decision, however it is named.
req=$(f "$(run capture --kind request --text 'do a thing' --now 5001)" 2) || fail "capture failed"
rc=0
fa claim w8 - "$APPROVE" --standing "$req" || rc=$?
[ "$rc" = 3 ] || fail "the channel accepted an answer naming a non-standing item (exit $rc)"
echo "ok: an answer naming an item that is not a standing decision is refused"

# --- a non-zero exit from the answer channel --------------------------------

fresh
rule=$(f "$(run capture --kind standing --text 'always let the workers run read-only git' \
  --covers-command 'git status' --now 6000)" 2) || fail "capture of the rule failed"
fa permission w9 spec.task-1 'git status --short' || fail "the permission push failed"
item=$(run add --kind question --origin w9 --worker w9 --closes 'the operator answers' --now 6001) \
  || fail "queueing the prompt failed"
# The channel cannot write its close: the store is there and matches, but the
# directory it must rename through is read-only, so the claim fails AFTER the
# match. Nothing may settle on that.
chmod 0500 "$home/attention"
out=$(run settle --now 6002) || fail "the settling pass failed"
chmod 0700 "$home/attention"
[ "$(rec "$item" 12)" = open ] || fail "an item settled on a failed answer: $out"
[ -z "$(line "$out" answered)" ] || fail "the pass spoke a rule for an answer that failed: $out"
grep -q '"verb":"settle-by-rule"' "$surface/events.log" \
  || fail "the failed attempt was not logged"
grep -q "\"decision\":\"$rule\"" "$surface/events.log" \
  || fail "the logged attempt does not name the decision"
echo "ok: a non-zero exit from the answer channel leaves the item open with the attempt logged"

echo "PASS: $(basename "$0")"
