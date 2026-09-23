#!/bin/bash
# A scripted tower session over a fixture fleet: the RELAY, RENDER and IDENTITY
# half (tower-comms Task 8; D-18, D-19 · REQ-A1.1, REQ-A1.7, REQ-C1.10,
# REQ-C1.11, REQ-F1.6). The hand-over sequence — the knock, the one-item bound,
# the fenced content, capture — is in test-tower-loop-comms.sh; split so each
# file stays inside the per-file wall-clock budget
# (config/test-time-budget.yml), each step costing a full settle + next pass.
#
# Contract under test:
#   identity --checkout <dir> (--session-id <uuid> | --pid <pid>)
#       The tower id every queue call in the iteration carries, resolved with
#       the same flags the loop's presence publish used.
#   step ... the pending pushes it takes and hands the session to relay, and the
#       worker it names for the iteration's own attention render to leave out.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
TLC="$here/../scripts/tower-loop-comms.sh"
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

[ -x "$TLC" ] || fail "scripts/tower-loop-comms.sh missing or not executable"
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
content="$tmp/content"
mkdir -p "$content"
ev="$tmp/evidence"
: >"$ev"
chmod 0600 "$ev"

# The per-step output sizes the Task 8 measurement reads. One line per step:
# a label and the bytes that step put in front of the tower.
sizes="$tmp/step-sizes"
: >"$sizes"

TAB=$(printf '\t')
A=tower-a
B=tower-b

# Every variable the scripts under test read is pinned, including the ones a
# developer running this from inside a live tower session would already have
# set: an ambient ledger path or a backend's attention-surface claim turns this
# file red for a reason that has nothing to do with the code.
env_run() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    PLANWRIGHT_ACTION_LEDGER="" \
    PLANWRIGHT_ATTENTION_SURFACE_PROVIDED="" \
    PLANWRIGHT_TOWER_ID="" \
    PLANWRIGHT_TOWER_SESSION_ID="" \
    PLANWRIGHT_TOWER_PID="" \
    "$@"
}

q() {
  : >"$errf"
  env_run /bin/sh "$TQ" "$@" 2>"$errf"
}

fa() {
  : >"$errf"
  env_run /bin/sh "$FA" "$@" 2>"$errf"
}

step() { # step <label> <args...> — run one loop step and record its size
  _label=$1
  shift
  : >"$errf"
  _out=$(env_run /bin/sh "$TLC" step --checkout "$tmp" "$@" 2>"$errf")
  step_rc=$?
  [ "$step_rc" = 0 ] || {
    printf '%s\n' "$_out"
    return 1
  }
  printf '%s\t%s\n' "$_label" "$(printf '%s' "$_out" | wc -c | tr -d ' ')" >>"$sizes"
  printf '%s\n' "$_out"
}

# step_rc_of <args...> — a step run for its exit status alone. The `|| rc=$?`
# is what keeps `set -e` from killing the run on the failure being asserted;
# without it the substitution would abort and hand back an empty string, which
# every `!= 0` test would pass for the wrong reason.
step_rc_of() {
  : >"$errf"
  _src_rc=0
  env_run /bin/sh "$TLC" step --checkout "$tmp" "$@" >/dev/null 2>"$errf" || _src_rc=$?
  printf '%s\n' "$_src_rc"
}

tlc() { # tlc <args...> — any other subcommand, stdout captured
  : >"$errf"
  env_run /bin/sh "$TLC" "$@" 2>"$errf"
}

reply_at() { # reply_at <tower> <epoch> — what the prompt-submit hook writes
  mkdir -p "$surface/attention"
  chmod 0700 "$surface/attention"
  printf '%s\n' "$2" >"$surface/attention/$1"
  chmod 0600 "$surface/attention/$1"
}

tag() { # tag <output> <tag> — the fields of the first line carrying <tag>
  printf '%s\n' "$1" | awk -F "$TAB" -v t="$2" '$1 == t { print; exit }'
}

count_tag() { # count_tag <output> <tag>
  printf '%s\n' "$1" | awk -F "$TAB" -v t="$2" '$1 == t { n++ } END { print n + 0 }'
}

field() { # field <record> <n> — one tab-separated field of a record
  printf '%s\n' "$1" | awk -F "$TAB" -v n="$2" '{ print $n }'
}

# --- the fixture fleet ----------------------------------------------------------

printf 'Rename the worker window before the next dispatch.\n' >"$content/ask-1"
printf 'Bump the release tag once CI is green.\n' >"$content/ask-2"

i1=$(q add --kind request --root "$content" --pointer ask-1 --origin operator \
  --subject pr:11 --closes 'the operator decides' --now 1000) || fail "add ask-1"
i2=$(q add --kind request --root "$content" --pointer ask-2 --origin operator \
  --subject pr:12 --closes 'the operator decides' --now 1001) || fail "add ask-2"
[ -n "$i1" ] && [ -n "$i2" ] || fail "the fixture items did not register"

# --- the pending push is relayed exactly once and then cleared (REQ-F1.6) --------

push_dir="$home/attention/push"
mkdir -p "$push_dir"
chmod 0700 "$push_dir"
printf 'planwright: a worker has been blocked for 20 minutes. Reply in the tower to pick it up.\n' \
  >"$push_dir/$i1"
chmod 0600 "$push_dir/$i1"

out=$(step relay --tower "$A" --evidence "$ev" --now 4830) \
  || fail "the relay step exited non-zero: $out"
[ "$(count_tag "$out" push)" = 1 ] || fail "the pending push was not relayed"
push_text=$(tag "$out" push | awk -F "$TAB" '{ print $3 }')
[ -n "$push_text" ] || fail "the relayed push carried no line"
[ "${#push_text}" -lt 200 ] || fail "the relayed line is not under 200 characters (${#push_text})"
case $push_text in
  *REQ-* | *D-[0-9]* | *task-*) fail "the relayed line carries a spec identifier: $push_text" ;;
esac
if [ -e "$push_dir/$i1" ]; then
  fail "the marker was not cleared after the relay"
fi

out=$(step relay-again --tower "$A" --evidence "$ev" --now 4840) \
  || fail "the second relay step exited non-zero: $out"
[ "$(count_tag "$out" push)" = 0 ] || fail "the marker was relayed a second time"

# The relayed text is redacted on the way out: it lands on a lock screen, and
# nothing guarantees the marker's writer scrubbed it.
leak=ghp_abcdefghijklmnopqrstuvwxyz0123456789
printf 'planwright: the worker pasted %s into its log.\n' "$leak" >"$push_dir/$i2"
chmod 0600 "$push_dir/$i2"
out=$(step relay-redact --tower "$A" --evidence "$ev" --now 4845) \
  || fail "the redacting relay step exited non-zero: $out"
[ "$(count_tag "$out" push)" = 1 ] || fail "the secret-bearing push was not relayed"
case $out in
  *"$leak"*) fail "a pending push was relayed with a secret-shaped token in it" ;;
esac
tag "$out" push | grep -q 'redacted:github-token' || fail "the relayed push does not show the redaction"

# A marker the relay declines to take is NAMED, never dropped in silence, and
# it makes the step non-zero so the turn says so (REQ-C1.11). Three shapes:
# a name outside the key grammar, an empty marker, and one somebody else can
# write.
printf 'reachable\n' >"$push_dir/not a key"
chmod 0600 "$push_dir/not a key"
rc=$(step_rc_of --tower "$A" --evidence "$ev" --now 4850)
[ "$rc" != 0 ] || fail "a pending-push file outside the key grammar was relayed or ignored silently"
grep -q 'marker key' "$errf" || fail "the refused pending-push name was not named on stderr"
[ -e "$push_dir/not a key" ] || fail "a file the relay refused was deleted anyway"
rm -f "$push_dir/not a key"

: >"$push_dir/$i2"
chmod 0600 "$push_dir/$i2"
rc=$(step_rc_of --tower "$A" --evidence "$ev" --now 4860)
[ "$rc" != 0 ] || fail "an empty pending-push marker was destroyed silently"
grep -q 'held no line to relay' "$errf" || fail "the empty marker's destruction was not surfaced"
if [ -e "$push_dir/$i2" ]; then
  fail "the empty marker was left holding its dedupe key"
fi

k_foreign=i00000003
printf 'planwright: somebody else wrote this.\n' >"$push_dir/$k_foreign"
chmod 0644 "$push_dir/$k_foreign"
rc=$(step_rc_of --tower "$A" --evidence "$ev" --now 4870)
[ "$rc" != 0 ] || fail "a pending-push marker that is not owner-only was relayed"
grep -q 'owner-only' "$errf" || fail "the loose marker mode was not named on stderr"
[ -e "$push_dir/$k_foreign" ] || fail "a marker the relay refused was deleted anyway"
rm -f "$push_dir/$k_foreign"

# A fleet home whose path carries a space. Enumerating the pending set is the
# one place this script globs, and a split there makes every marker invisible
# while the directory still lists clean — a dead channel wearing an idle
# channel's face.
spaced="$tmp/fleet home"
mkdir -p "$spaced/attention/push"
chmod 0700 "$spaced" "$spaced/attention" "$spaced/attention/push"
printf 'planwright: pending under a spaced home.\n' >"$spaced/attention/push/i00000009"
chmod 0600 "$spaced/attention/push/i00000009"
: >"$errf"
spaced_out=$(PLANWRIGHT_FLEET_STATE_DIR="$spaced" PLANWRIGHT_REPO_ROOT="$tmp" \
  PLANWRIGHT_LOCAL_CONFIG="$local_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
  /bin/sh "$FA" relay 2>"$errf") || fail "relay refused a fleet home carrying a space"
[ "$(tag "$spaced_out" push | awk -F "$TAB" '{ print $2 }')" = i00000009 ] \
  || fail "a pending push under a spaced fleet home was not relayed"
if [ -e "$spaced/attention/push/i00000009" ]; then
  fail "the relayed marker under a spaced fleet home was not cleared"
fi

# A push directory that cannot be listed is a channel that has stopped working;
# it must not pass for an idle one.
k_pending=i00000004
printf 'planwright: pending.\n' >"$push_dir/$k_pending"
chmod 0600 "$push_dir/$k_pending"
chmod 0000 "$push_dir"
rc=$(step_rc_of --tower "$A" --evidence "$ev" --now 4880)
chmod 0700 "$push_dir"
[ "$rc" != 0 ] || fail "an unlistable pending-push directory read as an idle one"
grep -q 'cannot be listed' "$errf" || fail "the unlistable push directory was not named"
rm -f "$push_dir/$k_pending"

# Nor may a regular file where the push directory should be: `notify` cannot
# queue anything under it, and it lists as readably as an empty directory.
filed="$tmp/filed-home"
mkdir -p "$filed/attention"
chmod 0700 "$filed" "$filed/attention"
: >"$filed/attention/push"
filed_rc=0
: >"$errf"
PLANWRIGHT_FLEET_STATE_DIR="$filed" PLANWRIGHT_REPO_ROOT="$tmp" \
  PLANWRIGHT_LOCAL_CONFIG="$local_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
  /bin/sh "$FA" relay >/dev/null 2>"$errf" || filed_rc=$?
[ "$filed_rc" != 0 ] || fail "a regular file at the push path read as an idle channel"
grep -q 'not a directory' "$errf" || fail "the file at the push path was not named"

# Or an entry in the set that is not a marker: it holds its key against every
# later `notify`, so a set holding only that is a stuck channel, not an idle one.
rm -f "$filed/attention/push"
mkdir -p "$filed/attention/push/i00000005"
chmod 0700 "$filed/attention/push" "$filed/attention/push/i00000005"
filed_rc=0
: >"$errf"
PLANWRIGHT_FLEET_STATE_DIR="$filed" PLANWRIGHT_REPO_ROOT="$tmp" \
  PLANWRIGHT_LOCAL_CONFIG="$local_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
  /bin/sh "$FA" relay >/dev/null 2>"$errf" || filed_rc=$?
[ "$filed_rc" != 0 ] || fail "a pending set holding only a directory read as an idle channel"
grep -q 'not a plain pending-push marker' "$errf" || fail "the directory in the pending set was not named"
[ -d "$filed/attention/push/i00000005" ] || fail "the relay removed an entry it refused"

# --- a question homed on an attention row, and the render that follows it -------

state="$home/attention/state"
mkdir -p "$home/attention"
{
  printf 'w-delivered%sspec:task-1%sawaiting-input%s1000%snormal%sMay I force-push the worker branch?%shold it%sforce,hold\n' \
    "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB"
  printf 'w-open%sspec:task-2%sawaiting-input%s1000%snormal%sAnd this?%syes%syes,no\n' \
    "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB"
} >"$state"
chmod 0600 "$state"

qd=$(q add --kind question --worker w-delivered --origin w-delivered \
  --closes 'the operator answers' --now 5000) || fail "add the delivered question"
[ -n "$qd" ] || fail "the delivered question did not register"
reply_at "$A" 5010
out=$(step row-knock --tower "$A" --evidence "$ev" --now 5020) \
  || fail "the knock for the row-homed question exited non-zero: $out"
reply_at "$A" 5030
out=$(step row-handover --tower "$A" --evidence "$ev" --now 5040) \
  || fail "the row-homed hand-over exited non-zero: $out"

# The row's own QUESTION is what makes the item answerable from the one message
# (REQ-C1.1). Reading the row one field to the right would deliver the
# recommendation as the question and never show the ask at all.
row_rec=$(tag "$out" content)
[ "$(field "$row_rec" 3)" = row ] \
  || fail "the content record does not name the attention home: $row_rec"
[ "$(field "$row_rec" 4)" = read ] || fail "the attention row did not read: $row_rec"
printf '%s\n' "$out" | grep -q 'question: May I force-push the worker branch?' \
  || fail "the row's question did not reach the turn"
printf '%s\n' "$out" | grep -q 'recommend: hold it' \
  || fail "the row's recommendation did not reach the turn"
printf '%s\n' "$out" | grep -q 'options: force,hold' \
  || fail "the row's option set did not reach the turn"

# And the step names the worker it just handed over, so the same iteration's
# render can leave that row out (REQ-A1.1).
[ "$(tag "$out" delivered | awk -F "$TAB" '{ print $2 }')" = w-delivered ] \
  || fail "the step did not name the worker it delivered"

render=$(fa queue) || fail "fleet-attention queue exited non-zero"
printf '%s\n' "$render" | grep -q 'spec:task-1' \
  || fail "an unfiltered render dropped a row nobody excepted"
render=$(fa queue --except w-delivered) || fail "queue --except exited non-zero"
printf '%s\n' "$render" | grep -q 'spec:task-2' \
  || fail "the render dropped a row the turn did not deliver"
if printf '%s\n' "$render" | grep -q 'spec:task-1'; then
  fail "the render repeated a row this turn already handed over"
fi
grep -q 'left out' "$errf" || fail "the render shrank without saying so"

# --count is the projection of the awaiting-input entries, which a hand-over
# does not close; it is deliberately not filtered.
[ "$(fa queue --count)" = 2 ] || fail "--except filtered the count"
[ "$(fa queue --except w-delivered --count)" = 2 ] || fail "--except filtered the count"

# The attention store changed AFTER `next` read it and before the row is. `next`
# screens and matches the row itself, so the change has to land between the
# two reads: a tree whose fleet-state.sh runs an armed hook when the loop
# script asks for the root, which it does just before reading the row, is how
# these reach that window.
tree="$tmp/tree"
mkdir -p "$tree"
cp -R "$here/../scripts" "$tree/scripts"
mv "$tree/scripts/fleet-state.sh" "$tree/scripts/fleet-state.real.sh"
hook="$tmp/root-hook"
cat >"$tree/scripts/fleet-state.sh" <<EOF
#!/bin/sh
if [ "\${1:-}" = root ] && [ -f "$hook" ]; then
  case \$(ps -o args= -p "\$PPID" 2>/dev/null) in
    *tower-loop-comms.sh*)
      mv "$hook" "$hook.ran"
      /bin/sh "$hook.ran"
      ;;
  esac
fi
exec /bin/sh "$tree/scripts/fleet-state.real.sh" "\$@"
EOF
chmod 0755 "$tree/scripts/fleet-state.sh"

# hooked_handover <label> <item-id> <tower> <now> — step the hooked tree until
# the item is handed over; its content record is left in $h_rec.
hooked_handover() {
  _hh_t=$4
  _hh_round=0
  h_rec=""
  rm -f "$hook.ran"
  TLC_REAL=$TLC
  TLC="$tree/scripts/tower-loop-comms.sh"
  while [ "$_hh_round" -lt 3 ]; do
    reply_at "$3" "$_hh_t"
    out=$(step "$1-$_hh_round" --tower "$3" --evidence "$ev" --now "$((_hh_t + 1))") || {
      TLC=$TLC_REAL
      fail "the $1 step exited non-zero: $out"
    }
    h_rec=$(printf '%s\n' "$out" | awk -F "$TAB" -v i="$2" '$1 == "content" && $2 == i { print; exit }')
    [ -z "$h_rec" ] || break
    _hh_t=$((_hh_t + 2))
    _hh_round=$((_hh_round + 1))
  done
  TLC=$TLC_REAL
  [ -e "$hook.ran" ] || fail "$1: the fixture hook never ran"
  [ -n "$h_rec" ] || fail "$1: the item never reached a hand-over"
}

# A symlink planted at the store is refused rather than read out: the row is
# rendered as the question.
decoy="$tmp/decoy-state"
sed 's/And this?/PRIVATE decoy question/' "$state" >"$decoy"
chmod 0600 "$decoy"
printf 'mv "%s" "%s.held" && ln -s "%s" "%s"\n' "$state" "$state" "$decoy" "$state" >"$hook"
qs=$(q add --kind question --worker w-open --origin w-open \
  --closes 'the operator answers' --now 5050) || fail "add the swapped-store question"
[ -n "$qs" ] || fail "the swapped-store question did not register"
hooked_handover swapped-store "$qs" tower-s 5060
if [ -L "$state" ]; then
  rm -f "$state"
  mv "$state.held" "$state"
fi
[ "$(field "$h_rec" 4)" = unread ] || fail "a symlinked attention store was read: $h_rec"
[ "$(field "$h_rec" 5)" = gone ] || fail "the symlinked store gave the wrong reason: $h_rec"
if printf '%s\n' "$out" | grep -q PRIVATE; then
  fail "a symlinked attention store was read out to the operator"
fi
q settle "$qs" --reason 'fixture done' --now 5070 >/dev/null || fail "settle the swapped-store question"

# A question is matched on the instance it was queued for. While the worker is
# still on that fork, the row reads.
for w in w-same w-fork; do
  printf '%s%sspec:task-3%sawaiting-input%s1000%snormal%sFirst fork?%sa%sa,b%s%si-one\n' \
    "$w" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" >>"$state"
done
qm=$(q add --kind question --worker w-same --origin w-same \
  --closes 'the operator answers' --now 5072) || fail "add the same-fork question"
[ -n "$qm" ] || fail "the same-fork question did not register"
: >"$hook"
hooked_handover same-fork "$qm" tower-m 5073
[ "$(field "$h_rec" 4)" = read ] || fail "a question's own fork did not read: $h_rec"
printf '%s\n' "$out" | grep -q 'question: First fork?' \
  || fail "the question's own fork did not reach the turn"
q settle "$qm" --reason 'fixture done' --now 5079 >/dev/null || fail "settle the same-fork question"

# A worker that re-forks in the same window holds a different question under
# the same handle. The item was queued for the first one; handing over the
# second would have the operator answer something the item never asked.
qf=$(q add --kind question --worker w-fork --origin w-fork \
  --closes 'the operator answers' --now 5080) || fail "add the re-forked question"
[ -n "$qf" ] || fail "the re-forked question did not register"
cat >"$hook" <<EOF
t=\$(mktemp "$tmp/refork.XXXXXX")
awk -F '$TAB' -v OFS='$TAB' '\$1 == "w-fork" { \$6 = "SECOND fork?"; \$10 = "i-two" } { print }' "$state" >"\$t"
cat "\$t" >"$state"
EOF
hooked_handover reforked "$qf" tower-f 5081
[ "$(field "$h_rec" 4)" = unread ] || fail "a re-forked worker's new question was handed over: $h_rec"
[ "$(field "$h_rec" 5)" = gone ] || fail "the re-forked row gave the wrong reason: $h_rec"
if printf '%s\n' "$out" | grep -q 'SECOND fork'; then
  fail "the re-forked question reached the operator under the first fork's item"
fi
q settle "$qf" --reason 'fixture done' --now 5090 >/dev/null || fail "settle the re-forked question"

# --- a second tower on the host carries its own identity ------------------------
# A's confirmed attention is not B's, and the question A is holding is leased to
# A (D-18, REQ-A1.7, REQ-C1.10). If `--tower` were dropped anywhere in the step,
# B would inherit A's conversation and hand over the item A already has.

printf 'A fourth ask.\n' >"$content/ask-5"
i5=$(q add --kind request --root "$content" --pointer ask-5 --origin operator \
  --subject pr:15 --closes 'the operator decides' --now 5100) || fail "add ask-5"
[ -n "$i5" ] || fail "the second-tower fixture item did not register"

out=$(step other-tower-quiet --tower "$B" --evidence "$ev" --now 5110) \
  || fail "the second tower's first step exited non-zero: $out"
[ "$(count_tag "$out" item)" = 0 ] \
  || fail "a second tower delivered content on another tower's attention"

reply_at "$B" 5120
out=$(step other-tower-handover --tower "$B" --evidence "$ev" --now 5130) \
  || fail "the second tower's hand-over step exited non-zero: $out"
b_id=$(tag "$out" item | awk -F "$TAB" '{ print $2 }')
[ -n "$b_id" ] || fail "the second tower's own reply released nothing"
[ "$b_id" != "$qd" ] || fail "the second tower was handed the item the first one holds"

# --- the identity verb, the one the loop resolves its tower id through ----------
# Every step above passes --tower; this is the path the skill tells the loop to
# take, and nothing else in the suite exercises it.

# The presence surface refuses a checkout that is not a repository, and keeps
# no records at all on one with no origin, so the identity path needs both a
# repository and a remote.
repo="$tmp/repo"
mkdir -p "$repo"
(cd "$repo" && git init -q . && git remote add origin "$tmp/upstream.git") \
  || fail "could not init the fixture checkout"

# The solo posture first: a checkout with no origin publishes no identity, and
# that is a named degrade (exit 3), not a refusal — a loop there still has to
# be able to talk to its operator.
solo="$tmp/solo"
mkdir -p "$solo"
(cd "$solo" && git init -q .) || fail "could not init the solo checkout"
solo_rc=0
: >"$errf"
env_run /bin/sh "$TLC" identity --checkout "$solo" --pid "$$" >/dev/null 2>"$errf" || solo_rc=$?
[ "$solo_rc" = 3 ] || fail "the solo posture reported $solo_rc, not the documented degrade"
grep -q 'solo posture' "$errf" || fail "the solo posture was not named"
solo_step=0
: >"$errf"
env_run /bin/sh "$TLC" step --checkout "$solo" --pid "$$" --evidence "$ev" --now 5400 \
  >/dev/null 2>"$errf" || solo_step=$?
[ "$solo_step" = 0 ] || fail "a step in the solo posture refused to run (exit $solo_step)"

# The same degrade under --session-id. The identity a step leases with has to
# be the SAME one on the next step, or the loop cannot claim back the item it
# is holding: a per-invocation fallback minted from the invoking shell's pid
# would make every iteration a different tower.
solo_uuid=11111111-2222-3333-4444-555555555555
for solo_now in 5410 5420; do
  solo_step=0
  : >"$errf"
  env_run /bin/sh "$TLC" step --checkout "$solo" --session-id "$solo_uuid" \
    --evidence "$ev" --now "$solo_now" >/dev/null 2>"$errf" || solo_step=$?
  [ "$solo_step" = 0 ] \
    || fail "a --session-id step in the solo posture refused to run (exit $solo_step)"
  if grep -q 'fallback\.p' "$errf"; then
    fail "the solo degrade dropped the session id and leased under a per-invocation fallback"
  fi
done

# The flag the step was given outranks whatever identity the shell exported:
# the queue's ladder reads PLANWRIGHT_TOWER_ID before the session id and the
# session id before the pid, so a degrade that only adds the flag's own
# variable leases under the ambient one instead.
solo_ambient() { # solo_ambient <VAR=value> <identity flags and step args...>
  _sa_env=$1
  shift
  : >"$errf"
  env_run env "$_sa_env" /bin/sh "$TLC" step --checkout "$solo" --evidence "$ev" "$@" 2>"$errf"
}
printf 'A solo ask.\n' >"$content/ask-solo"
q add --kind request --root "$content" --pointer ask-solo --origin operator \
  --subject pr:16 --closes 'the operator decides' --now 5430 >/dev/null || fail "add ask-solo"
solo_ambient PLANWRIGHT_TOWER_ID=tower-ambient --session-id "$solo_uuid" --now 5440 >/dev/null \
  || fail "the ambient-identity knock step exited non-zero"
reply_at "$solo_uuid" 5450
out=$(solo_ambient PLANWRIGHT_TOWER_ID=tower-ambient --session-id "$solo_uuid" --now 5460) \
  || fail "the ambient-identity hand-over step exited non-zero: $out"
[ "$(count_tag "$out" item)" = 1 ] \
  || fail "a solo --session-id step leased under an ambient PLANWRIGHT_TOWER_ID"

ambient_uuid=66666666-7777-8888-9999-000000000000
printf 'Another solo ask.\n' >"$content/ask-solo-2"
q add --kind request --root "$content" --pointer ask-solo-2 --origin operator \
  --subject pr:17 --closes 'the operator decides' --now 5470 >/dev/null || fail "add ask-solo-2"
solo_ambient PLANWRIGHT_TOWER_SESSION_ID="$ambient_uuid" --pid "$$" --now 5480 >/dev/null \
  || fail "the ambient-session knock step exited non-zero"
reply_at "$ambient_uuid" 5490
out=$(solo_ambient PLANWRIGHT_TOWER_SESSION_ID="$ambient_uuid" --pid "$$" --now 5495) \
  || fail "the ambient-session hand-over step exited non-zero: $out"
[ "$(count_tag "$out" item)" = 0 ] \
  || fail "a solo --pid step leased under an ambient PLANWRIGHT_TOWER_SESSION_ID"

id_out=$(tlc identity --checkout "$repo" --pid "$$") \
  || fail "identity could not resolve this process's composite: $(cat "$errf")"
[ -n "$id_out" ] || fail "identity printed nothing"
[ "$(printf '%s\n' "$id_out" | grep -c .)" = 1 ] || fail "identity printed more than one id"

if env_run /bin/sh "$TLC" identity --checkout "$repo" --pid "$$" --catchup >/dev/null 2>"$errf"; then
  fail "identity accepted a step-only flag"
fi
if env_run /bin/sh "$TLC" identity --checkout "$repo" >/dev/null 2>"$errf"; then
  fail "identity resolved an id with no identity flag"
fi
# A step given the same flags resolves the SAME id: the lease's owner label and
# the presence record have to agree, or nothing can attribute a held item.
id_again=$(tlc identity --checkout "$repo" --pid "$$") || fail "identity is not stable"
[ "$id_again" = "$id_out" ] || fail "identity resolved two different ids for one process"
if env_run /bin/sh "$TLC" step --checkout "$tmp" --tower '' >/dev/null 2>"$errf"; then
  fail "an empty --tower was accepted"
fi
grep -q 'empty value' "$errf" || fail "an empty flag value was not named"
# Without an evidence table the delivery cannot reuse the step's settling pass
# and runs a second one, so the flag is required rather than defaulted.
noev_rc=0
: >"$errf"
env_run /bin/sh "$TLC" step --checkout "$tmp" --tower "$A" --now 5500 >/dev/null 2>"$errf" || noev_rc=$?
[ "$noev_rc" = 2 ] || fail "a step with no --evidence ran (exit $noev_rc) rather than being refused"
grep -q -- '--evidence' "$errf" || fail "the missing --evidence was not named"

# --- the per-step measurement the PR body reports -------------------------------

[ "$(grep -c . "$sizes")" -ge 4 ] || fail "the per-step sizes were not recorded"
echo "--- per-step bytes put in front of the tower ---"
cat "$sizes"
awk -F "$TAB" '
  { s += $2; n++; if ($2 > m) m = $2 }
  END { printf "steps\t%d\tmean\t%d\tmax-step\t%d\n", n, s / n, m }
' "$sizes"

echo "PASS: $(basename "$0")"
