#!/bin/bash
# Tests for scripts/fleet-stuck-detector.sh — the four-state stuck-detector
# and its owner-attribution axis (fleet-lifecycle-closure Task 7: D-4;
# REQ-C1.1–REQ-C1.8, REQ-K1.5).
#
# What is covered:
#   - REQ-C1.1: each of working / waiting-on-a-human / finished-but-unreaped /
#     dead is produced from its own positive signal, and a surface with no
#     signal (nothing pushed, an unchanging pane) classifies NONE of them;
#   - REQ-C1.2: a captured permission-prompt pane classifies
#     waiting-on-a-human while a long-running-tool pane with the same surface
#     stability classifies working; a prompt signature outranks a stale
#     working push; a hook-pushed awaiting-input row is the primary signal;
#   - REQ-C1.3: a worker whose session ended while its process persists is
#     finished-but-unreaped, distinct from working and from dead;
#   - REQ-C1.4: a self-reported completion with an uncommitted tree or with
#     commits absent from the remote-tracking ref never classifies finished,
#     the evidence is local git state only, and no forge is queried;
#   - REQ-C1.5: dead only on a positive predicate verdict; alive, unknown,
#     errored, `none`, and absent handles all classify not-dead;
#   - REQ-C1.6: every state renders with each of the three attributions
#     (twelve cells), resolved from the presence surface, and an unreadable or
#     unreachable surface degrades to dead-or-unknown, never to this-tower;
#   - REQ-C1.7: the stage is derived from the event stream and degrades
#     visibly to `-` when the stream is absent;
#   - REQ-C1.8: the output parses under a pinned tab-separated grammar, a
#     malformed store line degrades to a reported anomaly, and the no-LLM /
#     no-network negative assertion holds over the decision path (REQ-K1.5).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-stuck-detector.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FSD="$here/../scripts/fleet-stuck-detector.sh"
tab=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FSD" ] || fail "scripts/fleet-stuck-detector.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Stub script dir: sibling resolution picks up a counting death-evidence stub
# and a scripted presence stub, so every verdict and attribution is driven by
# a fixture file rather than the host's processes.
stubbin="$tmp/stub-scripts"
mkdir -p "$stubbin"
cp "$here/../scripts/"*.sh "$stubbin/"
cat >"$stubbin/fleet-death-evidence.sh" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/evidence-calls"
verdict=\$(cat "$tmp/evidence-verdict")
printf '%s\n' "\$verdict"
case \$verdict in
  dead) exit 0 ;;
  alive) exit 1 ;;
  refused) exit 2 ;;
  *) exit 3 ;;
esac
STUB
cat >"$stubbin/fleet-presence.sh" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/presence-calls"
case "\$1" in
  identity) cat "$tmp/self-id"; exit 0 ;;
  liveness)
    rc=\$(cat "$tmp/presence-exit")
    [ "\$rc" = 0 ] || exit "\$rc"
    cat "$tmp/presence-answer"
    exit 0
    ;;
esac
exit 2
STUB
chmod +x "$stubbin/fleet-death-evidence.sh" "$stubbin/fleet-presence.sh"
printf 'alive\n' >"$tmp/evidence-verdict"
printf '0\n' >"$tmp/presence-exit"
: >"$tmp/evidence-calls"
: >"$tmp/presence-calls"
self_id="11111111-2222-3333-4444-555555555555"
peer_id="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
printf '%s\n' "$self_id" >"$tmp/self-id"
printf 'tower\t%s\tlive\n' "$peer_id" >"$tmp/presence-answer"

# run <home> <args...> — the detector against a pinned fleet home, plugin and
# tower identity env cleared so nothing leaks in from the host session.
run() {
  r_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID -u PLANWRIGHT_TOWER_PID \
    -u PLANWRIGHT_TOWER_CHECKOUT \
    PLANWRIGHT_FLEET_STATE_DIR="$r_home" \
    /bin/sh "$stubbin/fleet-stuck-detector.sh" "$@"
}
attn() {
  a_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    PLANWRIGHT_FLEET_STATE_DIR="$a_home" \
    /bin/sh "$stubbin/fleet-attention.sh" "$@"
}
reg() {
  g_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    PLANWRIGHT_FLEET_STATE_DIR="$g_home" \
    /bin/sh "$stubbin/fleet-state.sh" register "$@"
}
col() { printf '%s\n' "$1" | awk -F'\t' -v c="$2" '$1 == "worker" { print $c; exit }'; }
state_of() { col "$1" 3; }
owner_of() { col "$1" 4; }
stage_of() { col "$1" 5; }
reason_of() { col "$1" 6; }
ev() { printf '%s\n' "$1" | awk -F'\t' -v s="$2" '$1 == "evidence" && $3 == s { print $4; exit }'; }

w=worker-7
s=demo:7

# ---------------------------------------------------------------------------
# 1. Usage floor: hostile and missing input is refused before any read.
# ---------------------------------------------------------------------------
h1="$tmp/h1"
for args in "" "classify" "classify ../x" "classify a${tab}b" "bogus $w" "classify $w --pane" "classify $w --nope 1"; do
  rc=0
  # shellcheck disable=SC2086
  run "$h1" $args >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage: '$args' exited $rc, expected 2"
done
echo "ok: usage floor refuses missing / hostile input (exit 2)"

# ---------------------------------------------------------------------------
# 2. REQ-C1.1 (negative): no signal at all — no registry record, no store row,
#    no runtime dir — produces NO state; an unchanging pane with no marker
#    presented twice still produces none. Silence is never a signal.
# ---------------------------------------------------------------------------
h2="$tmp/h2"
mkdir -p "$h2"
out=$(run "$h2" classify "$w") || fail "no-signal classify exited non-zero"
[ "$(state_of "$out")" = unclassified ] || fail "no signal: '$(state_of "$out")', expected unclassified"
[ "$(reason_of "$out")" = no-signal ] || fail "no signal: reason '$(reason_of "$out")'"
[ "$(ev "$out" attention)" = absent ] || fail "no signal: attention evidence '$(ev "$out" attention)'"
[ "$(ev "$out" registry)" = absent ] || fail "no signal: registry evidence '$(ev "$out" registry)'"
static_pane="$tmp/static.txt"
cat >"$static_pane" <<'PANE'
● Reading the spec bundle.
  Comparing the requirements against the design.
  Still comparing.
PANE
for _ in 1 2; do
  out=$(run "$h2" classify "$w" --pane "$static_pane") || fail "static pane classify exited non-zero"
  [ "$(state_of "$out")" = unclassified ] || fail "static pane: '$(state_of "$out")', expected unclassified"
  [ "$(ev "$out" pane)" = indeterminate ] || fail "static pane: pane evidence '$(ev "$out" pane)'"
done
echo "ok: absence of change classifies nothing (REQ-C1.1)"

# ---------------------------------------------------------------------------
# 3. REQ-C1.1 / REQ-C1.2: the four states, each from its own signal.
# ---------------------------------------------------------------------------
h3="$tmp/h3"
attn "$h3" heartbeat "$w" "$s" working >/dev/null || fail "setup: working heartbeat"
out=$(run "$h3" classify "$w") || fail "working classify exited non-zero"
[ "$(state_of "$out")" = working ] || fail "working push: '$(state_of "$out")'"
[ "$(reason_of "$out")" = attention-working ] || fail "working push: reason '$(reason_of "$out")'"

attn "$h3" decide "$w" "$s" "Which way?" a "a|b" >/dev/null || fail "setup: decide"
out=$(run "$h3" classify "$w") || fail "awaiting classify exited non-zero"
[ "$(state_of "$out")" = waiting-on-a-human ] || fail "decide push: '$(state_of "$out")'"
[ "$(reason_of "$out")" = hook-push ] || fail "decide push: reason '$(reason_of "$out")'"
attn "$h3" clear "$w" >/dev/null
attn "$h3" park "$w" "$s" "notification:idle_prompt" >/dev/null || fail "setup: park"
out=$(run "$h3" classify "$w") || fail "park classify exited non-zero"
[ "$(state_of "$out")" = waiting-on-a-human ] || fail "park push: '$(state_of "$out")'"
[ "$(ev "$out" attention-reason)" = "notification:idle_prompt" ] || fail "park push: reason evidence '$(ev "$out" attention-reason)'"

attn "$h3" clear "$w" >/dev/null
attn "$h3" heartbeat "$w" "$s" ended >/dev/null || fail "setup: ended heartbeat"
reg "$h3" "$w" "$s" --owner "$self_id" --backend headless-oneshot --death-handle "process 4242" >/dev/null \
  || fail "setup: register"
printf 'alive\n' >"$tmp/evidence-verdict"
out=$(run "$h3" classify "$w") || fail "ended classify exited non-zero"
[ "$(state_of "$out")" = finished-but-unreaped ] || fail "ended + alive: '$(state_of "$out")'"
[ "$(reason_of "$out")" = session-ended ] || fail "ended + alive: reason '$(reason_of "$out")'"
[ "$(ev "$out" death)" = alive ] || fail "ended + alive: death evidence '$(ev "$out" death)'"

printf 'dead\n' >"$tmp/evidence-verdict"
out=$(run "$h3" classify "$w") || fail "dead classify exited non-zero"
[ "$(state_of "$out")" = dead ] || fail "positive death: '$(state_of "$out")'"
[ "$(reason_of "$out")" = death-evidence ] || fail "positive death: reason '$(reason_of "$out")'"
echo "ok: working / waiting-on-a-human / finished-but-unreaped / dead each from its own signal (REQ-C1.1)"

# ---------------------------------------------------------------------------
# 4. REQ-C1.2: a captured permission prompt vs a long-running tool call. Both
#    panes are equally static; only the positively matched signature separates
#    them. The signature outranks a stale working push (a missed hook), and a
#    busy marker never masks a prompt.
# ---------------------------------------------------------------------------
h4="$tmp/h4"
prompt_pane="$tmp/prompt.txt"
cat >"$prompt_pane" <<'PANE'
● I'll run the test suite now.

  Bash command

    ./tests/test-fleet-liveness.sh
    Run the liveness tests

  Do you want to proceed?
  ❯ 1. Yes
    2. Yes, and don't ask again for ./tests/ commands in this worktree
    3. No, and tell Claude what to do differently (esc)
PANE
busy_pane="$tmp/busy.txt"
cat >"$busy_pane" <<'PANE'
● Running the full suite; this takes a few minutes.

  ⠋ Churning… (2m 41s · esc to interrupt)
PANE
out=$(run "$h4" classify "$w" --pane "$prompt_pane") || fail "prompt pane classify exited non-zero"
[ "$(state_of "$out")" = waiting-on-a-human ] || fail "prompt pane: '$(state_of "$out")'"
[ "$(reason_of "$out")" = prompt-signature ] || fail "prompt pane: reason '$(reason_of "$out")'"
[ "$(ev "$out" pane)" = permission-prompt ] || fail "prompt pane: pane evidence '$(ev "$out" pane)'"
out=$(run "$h4" classify "$w" --pane "$busy_pane") || fail "busy pane classify exited non-zero"
[ "$(state_of "$out")" = working ] || fail "busy pane: '$(state_of "$out")'"
[ "$(reason_of "$out")" = pane-busy ] || fail "busy pane: reason '$(reason_of "$out")'"
attn "$h4" heartbeat "$w" "$s" working >/dev/null
out=$(run "$h4" classify "$w" --pane "$prompt_pane") || fail "prompt + working push exited non-zero"
[ "$(state_of "$out")" = waiting-on-a-human ] || fail "prompt outranks a stale working push: '$(state_of "$out")'"
# A quoted signature deep in the scrollback is not a prompt: the window is bounded.
deep_pane="$tmp/deep.txt"
{
  echo "  earlier the harness asked: Do you want to proceed? and I answered yes"
  i=0
  while [ "$i" -lt 40 ]; do
    echo "  line $i of ordinary output"
    i=$((i + 1))
  done
  echo "  ⠋ Working… (esc to interrupt)"
} >"$deep_pane"
out=$(run "$h4" classify "$w" --pane "$deep_pane") || fail "deep pane classify exited non-zero"
[ "$(state_of "$out")" = working ] || fail "scrollback quote must not match a prompt: '$(state_of "$out")'"
out=$(FLEET_PANE_PROMPT_SIGNATURES="Custom Dialog Text" run "$h4" classify "$w" --pane "$prompt_pane") \
  || fail "override classify exited non-zero"
[ "$(state_of "$out")" = working ] || fail "an overridden signature set must replace the default: '$(state_of "$out")'"
rc=0
run "$h4" classify "$w" --pane "$tmp/absent-pane" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "an unreadable pane file must be refused (exit $rc)"
echo "ok: a permission prompt is detected positively, a long tool call is working (REQ-C1.2)"

# ---------------------------------------------------------------------------
# 5. REQ-C1.5: dead requires the predicate's positive verdict. Every other
#    outcome — alive, unknown, an errored / refused call, a `none` handle, no
#    handle at all — is not-dead, and `none` is never passed to the predicate.
# ---------------------------------------------------------------------------
h5="$tmp/h5"
attn "$h5" heartbeat "$w" "$s" ended >/dev/null
reg "$h5" "$w" "$s" --owner "$self_id" --backend stream-json-persistent --death-handle "process 4242" >/dev/null
for verdict in alive unknown refused garbage; do
  printf '%s\n' "$verdict" >"$tmp/evidence-verdict"
  out=$(run "$h5" classify "$w" 2>/dev/null) || fail "verdict $verdict: classify exited non-zero"
  [ "$(state_of "$out")" != dead ] || fail "verdict $verdict classified dead"
  case $verdict in
    alive) [ "$(ev "$out" death)" = alive ] || fail "verdict alive: evidence '$(ev "$out" death)'" ;;
    *) [ "$(ev "$out" death)" = unknown ] || fail "verdict $verdict: evidence '$(ev "$out" death)', expected unknown" ;;
  esac
done
printf 'dead\n' >"$tmp/evidence-verdict"
out=$(run "$h5" classify "$w") || fail "dead: classify exited non-zero"
[ "$(state_of "$out")" = dead ] || fail "dead verdict: '$(state_of "$out")'"
grep -q '^process 4242$' "$tmp/evidence-calls" || fail "the registry death handle never reached the predicate"
: >"$tmp/evidence-calls"
out=$(run "$h5" classify "$w" --death-handle "tmux-window fleet w7") || fail "handle override exited non-zero"
grep -q '^tmux-window fleet w7$' "$tmp/evidence-calls" || fail "--death-handle did not override the registry handle"
: >"$tmp/evidence-calls"
out=$(run "$h5" classify "$w" --death-handle none) || fail "none handle exited non-zero"
[ "$(state_of "$out")" = finished-but-unreaped ] || fail "none handle: '$(state_of "$out")'"
[ "$(ev "$out" death)" = none ] || fail "none handle: evidence '$(ev "$out" death)'"
[ ! -s "$tmp/evidence-calls" ] || fail "a none handle was passed to the predicate"
h5b="$tmp/h5b"
attn "$h5b" heartbeat "$w" "$s" ended >/dev/null
out=$(run "$h5b" classify "$w") || fail "no handle exited non-zero"
[ "$(ev "$out" death)" = absent ] || fail "no handle: evidence '$(ev "$out" death)'"
[ "$(state_of "$out")" = finished-but-unreaped ] || fail "no handle: '$(state_of "$out")'"
rc=0
run "$h5" classify "$w" --death-handle "timeout 30" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a pseudo-evidence handle must be refused (exit $rc)"
echo "ok: dead only on a positive verdict; unknown / errored / none / absent are not-dead (REQ-C1.5)"

# ---------------------------------------------------------------------------
# 6. REQ-C1.3 / REQ-C1.4: completion signals from the runtime dir, and the
#    unlanded-work check over LOCAL git state only.
# ---------------------------------------------------------------------------
git_q() { git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
bare="$tmp/origin.git"
git_q init -q --bare "$bare"
wt="$tmp/wt"
git_q init -q "$wt"
git_q -C "$wt" symbolic-ref HEAD refs/heads/main
git_q -C "$wt" remote add origin "$bare"
printf 'base\n' >"$wt/base.txt"
git_q -C "$wt" add base.txt
git_q -C "$wt" commit -q -m base
git_q -C "$wt" push -q -u origin HEAD 2>/dev/null
# The unit branch: what a dispatched worker actually works on.
git_q -C "$wt" checkout -q -b planwright/demo/task-7
h6="$tmp/h6"
sd6="$tmp/sd6"
mkdir -p "$sd6"
printf 'result\tsuccess\t1700000000\n' >"$sd6/result"
reg "$h6" "$w" "$s" --owner "$self_id" --backend stream-json-persistent \
  --state-dir "$sd6" --death-handle "process 4242" >/dev/null
printf 'alive\n' >"$tmp/evidence-verdict"
# (c) landed: clean tree, nothing ahead of the remote-tracking ref.
out=$(run "$h6" classify "$w" --worktree "$wt") || fail "landed classify exited non-zero"
[ "$(state_of "$out")" = finished-but-unreaped ] || fail "landed completion: '$(state_of "$out")'"
[ "$(reason_of "$out")" = "completion:result=success" ] || fail "landed completion: reason '$(reason_of "$out")'"
[ "$(ev "$out" tree)" = clean ] || fail "landed: tree '$(ev "$out" tree)'"
[ "$(ev "$out" unpushed)" = 0 ] || fail "landed: unpushed '$(ev "$out" unpushed)'"
# (a) an uncommitted tree.
printf 'wip\n' >"$wt/wip.txt"
out=$(run "$h6" classify "$w" --worktree "$wt") || fail "dirty classify exited non-zero"
[ "$(state_of "$out")" = unclassified ] || fail "dirty tree classified '$(state_of "$out")'"
[ "$(reason_of "$out")" = completion-unlanded ] || fail "dirty tree: reason '$(reason_of "$out")'"
[ "$(ev "$out" tree)" = dirty ] || fail "dirty tree: evidence '$(ev "$out" tree)'"
rm -f "$wt/wip.txt"
# (b) commits absent from the remote-tracking ref.
printf 'more\n' >"$wt/more.txt"
git_q -C "$wt" add more.txt
git_q -C "$wt" commit -q -m more
out=$(run "$h6" classify "$w" --worktree "$wt") || fail "unpushed classify exited non-zero"
[ "$(state_of "$out")" = unclassified ] || fail "unpushed classified '$(state_of "$out")'"
[ "$(ev "$out" unpushed)" = 1 ] || fail "unpushed: evidence '$(ev "$out" unpushed)'"
[ "$(ev "$out" tree)" = clean ] || fail "unpushed: tree '$(ev "$out" tree)'"
git_q -C "$wt" push -q -u origin HEAD 2>/dev/null
out=$(run "$h6" classify "$w" --worktree "$wt") || fail "re-landed classify exited non-zero"
[ "$(state_of "$out")" = finished-but-unreaped ] || fail "after push: '$(state_of "$out")'"
# The worktree resolves from the registry state dir when that IS a worktree
# (the tmux rung records the worktree as its state dir) …
h6b="$tmp/h6b"
attn "$h6b" heartbeat "$w" "$s" ended >/dev/null
reg "$h6b" "$w" "$s" --owner "$self_id" --backend tmux --state-dir "$wt" --death-handle "tmux-window f w" >/dev/null
printf 'wip\n' >"$wt/wip2.txt"
out=$(run "$h6b" classify "$w") || fail "state-dir worktree classify exited non-zero"
[ "$(state_of "$out")" = unclassified ] || fail "state-dir worktree: '$(state_of "$out")'"
[ "$(ev "$out" tree)" = dirty ] || fail "state-dir worktree: tree '$(ev "$out" tree)'"
rm -f "$wt/wip2.txt"
# … and from the event stream's init cwd on the stream-json rung.
printf '{"type":"system","subtype":"init","cwd":"%s","session_id":"abc","tools":[]}\n' "$wt" >"$sd6/events.jsonl"
printf 'wip\n' >"$wt/wip3.txt"
out=$(run "$h6" classify "$w") || fail "events cwd classify exited non-zero"
[ "$(ev "$out" tree)" = dirty ] || fail "events cwd: tree '$(ev "$out" tree)'"
[ "$(state_of "$out")" = unclassified ] || fail "events cwd: '$(state_of "$out")'"
rm -f "$wt/wip3.txt" "$sd6/events.jsonl"
# No worktree resolvable: not demonstrably unlanded, and visibly unverifiable.
out=$(run "$h6" classify "$w") || fail "no-worktree classify exited non-zero"
[ "$(state_of "$out")" = finished-but-unreaped ] || fail "no worktree: '$(state_of "$out")'"
[ "$(ev "$out" tree)" = unverifiable ] || fail "no worktree: tree '$(ev "$out" tree)'"
# The headless rung's completion signal is its `exit` record.
h6c="$tmp/h6c"
sd6c="$tmp/sd6c"
mkdir -p "$sd6c"
printf '0 1700000000\n' >"$sd6c/exit"
reg "$h6c" "$w" "$s" --owner "$self_id" --backend headless-oneshot --state-dir "$sd6c" --death-handle "process 4242" >/dev/null
out=$(run "$h6c" classify "$w") || fail "headless exit classify exited non-zero"
[ "$(state_of "$out")" = finished-but-unreaped ] || fail "headless exit: '$(state_of "$out")'"
[ "$(ev "$out" completion)" = "exit=0" ] || fail "headless exit: completion '$(ev "$out" completion)'"
# A non-zero stream-json exit record is still an ended session, still not working.
printf 'exit\t1\t1700000000\n' >"$sd6/result"
out=$(run "$h6" classify "$w") || fail "sj exit classify exited non-zero"
[ "$(ev "$out" completion)" = "exit=1" ] || fail "sj nonzero exit: completion '$(ev "$out" completion)'"
[ "$(state_of "$out")" = finished-but-unreaped ] || fail "sj nonzero exit: '$(state_of "$out")'"
# Distinguishable from working and from dead on the same fixture (REQ-C1.3).
attn "$h6" heartbeat "$w" "$s" working >/dev/null
printf 'result\tsuccess\t1700000000\n' >"$sd6/result"
out=$(run "$h6" classify "$w" --worktree "$wt") || fail "completed + working push exited non-zero"
[ "$(state_of "$out")" = finished-but-unreaped ] || fail "a captured result outranks a stale working push: '$(state_of "$out")'"
printf 'dead\n' >"$tmp/evidence-verdict"
out=$(run "$h6" classify "$w" --worktree "$wt") || fail "completed + dead exited non-zero"
[ "$(state_of "$out")" = dead ] || fail "completed + dead: '$(state_of "$out")'"
printf 'alive\n' >"$tmp/evidence-verdict"
# No forge query, asserted at runtime: a `gh` on PATH is never invoked.
fakebin="$tmp/fakebin"
mkdir -p "$fakebin"
printf '#!/bin/sh\necho called >>"%s"\n' "$tmp/gh-calls" >"$fakebin/gh"
chmod +x "$fakebin/gh"
PATH="$fakebin:$PATH" run "$h6" classify "$w" --worktree "$wt" >/dev/null || fail "PATH-shadowed classify exited non-zero"
[ ! -e "$tmp/gh-calls" ] || fail "the detector invoked gh (a per-worker forge query, REQ-C1.4)"
echo "ok: completion is never finished while work is unlanded; git state only, no forge (REQ-C1.3, REQ-C1.4)"

# ---------------------------------------------------------------------------
# 7. REQ-C1.6: twelve cells — each state with each attribution — plus the
#    degradations: an absent token, an unreachable surface, a record the
#    surface does not hold, and no tower identity to compare against.
# ---------------------------------------------------------------------------
attribution_cell() {
  ac_state=$1
  ac_owner_token=$2
  ac_expect_owner=$3
  ac_home="$tmp/h7-$ac_state-$ac_expect_owner"
  ac_handle="process 4242"
  case $ac_state in
    working) attn "$ac_home" heartbeat "$w" "$s" working >/dev/null ;;
    waiting-on-a-human) attn "$ac_home" decide "$w" "$s" "q?" a "a|b" >/dev/null ;;
    finished-but-unreaped) attn "$ac_home" heartbeat "$w" "$s" ended >/dev/null ;;
    dead) attn "$ac_home" heartbeat "$w" "$s" working >/dev/null ;;
  esac
  reg "$ac_home" "$w" "$s" --owner "$ac_owner_token" --backend headless-oneshot --death-handle "$ac_handle" >/dev/null
  if [ "$ac_state" = dead ]; then printf 'dead\n' >"$tmp/evidence-verdict"; else printf 'alive\n' >"$tmp/evidence-verdict"; fi
  ac_out=$(run "$ac_home" classify "$w" --tower-id "$self_id" --session-id "$self_id" --checkout "$wt") \
    || fail "cell $ac_state/$ac_expect_owner: exited non-zero"
  [ "$(state_of "$ac_out")" = "$ac_state" ] || fail "cell $ac_state/$ac_expect_owner: state '$(state_of "$ac_out")'"
  [ "$(owner_of "$ac_out")" = "$ac_expect_owner" ] || fail "cell $ac_state/$ac_expect_owner: owner '$(owner_of "$ac_out")'"
}
printf 'tower\t%s\tlive\n' "$peer_id" >"$tmp/presence-answer"
for st in working waiting-on-a-human finished-but-unreaped dead; do
  attribution_cell "$st" "$self_id" this-tower
  attribution_cell "$st" "$peer_id" live-peer
done
printf 'tower\t%s\tdead\n' "$peer_id" >"$tmp/presence-answer"
for st in working waiting-on-a-human finished-but-unreaped dead; do
  attribution_cell "$st" "$peer_id" dead-or-unknown
done
printf 'alive\n' >"$tmp/evidence-verdict"
h7="$tmp/h7"
attn "$h7" heartbeat "$w" "$s" working >/dev/null
reg "$h7" "$w" "$s" --owner "$peer_id" --backend headless-oneshot --death-handle "process 4242" >/dev/null
for answer in "tower	$peer_id	unknown" "tower	$peer_id	ambiguous" "no-record	$peer_id" "unreadable	$peer_id	malformed"; do
  printf '%s\n' "$answer" >"$tmp/presence-answer"
  out=$(run "$h7" classify "$w" --tower-id "$self_id" --session-id "$self_id" --checkout "$wt") \
    || fail "presence '$answer': exited non-zero"
  [ "$(owner_of "$out")" = dead-or-unknown ] || fail "presence '$answer': owner '$(owner_of "$out")'"
done
printf 'tower\t%s\tlive\n' "$peer_id" >"$tmp/presence-answer"
# An unreadable surface (presence exits 3) degrades to dead-or-unknown, never
# to this-tower, and says so.
printf '3\n' >"$tmp/presence-exit"
out=$(run "$h7" classify "$w" --tower-id "$self_id" --session-id "$self_id" --checkout "$wt" 2>/dev/null) \
  || fail "unreadable surface: exited non-zero"
[ "$(owner_of "$out")" = dead-or-unknown ] || fail "unreadable surface: owner '$(owner_of "$out")'"
[ "$(ev "$out" owner)" = presence-unavailable ] || fail "unreadable surface: evidence '$(ev "$out" owner)'"
printf '0\n' >"$tmp/presence-exit"
# The token is compared to this tower's identity before the surface is asked,
# but a non-self token with NO identity to call the surface with is unknown.
out=$(run "$h7" classify "$w") || fail "no identity: exited non-zero"
[ "$(owner_of "$out")" = dead-or-unknown ] || fail "no identity: owner '$(owner_of "$out")'"
[ "$(ev "$out" owner)" = no-identity ] || fail "no identity: evidence '$(ev "$out" owner)'"
# The env-carried token attributes without a presence call (the ordinary
# tower path), and an absent token is unknown-owner.
: >"$tmp/presence-calls"
out=$(PLANWRIGHT_TOWER_ID="$peer_id" env PLANWRIGHT_FLEET_STATE_DIR="$h7" /bin/sh "$stubbin/fleet-stuck-detector.sh" classify "$w") \
  || fail "env token: exited non-zero"
[ "$(owner_of "$out")" = this-tower ] || fail "env token: owner '$(owner_of "$out")'"
[ ! -s "$tmp/presence-calls" ] || fail "a self-token match still called the presence surface"
h7b="$tmp/h7b"
attn "$h7b" heartbeat "$w" "$s" working >/dev/null
reg "$h7b" "$w" "$s" --backend headless-oneshot --death-handle "process 4242" >/dev/null
out=$(run "$h7b" classify "$w" --tower-id "$self_id") || fail "absent token: exited non-zero"
[ "$(owner_of "$out")" = dead-or-unknown ] || fail "absent token: owner '$(owner_of "$out")'"
[ "$(ev "$out" owner)" = absent ] || fail "absent token: evidence '$(ev "$out" owner)'"
echo "ok: every state renders with each attribution; degradations never read as this-tower (REQ-C1.6)"

# ---------------------------------------------------------------------------
# 8. REQ-C1.6 against the REAL presence surface (no stub): a peer that
#    published is live-peer, our own token is this-tower, an unpublished
#    token is dead-or-unknown.
# ---------------------------------------------------------------------------
realbin="$tmp/real-scripts"
mkdir -p "$realbin"
cp "$here/../scripts/"*.sh "$realbin/"
h8="$tmp/h8"
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR PLANWRIGHT_FLEET_STATE_DIR="$h8" \
  /bin/sh "$realbin/fleet-presence.sh" publish --checkout "$wt" --session-id "$peer_id" --pid $$ >/dev/null \
  || fail "real presence publish failed"
run_real() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID -u PLANWRIGHT_TOWER_PID \
    PLANWRIGHT_FLEET_STATE_DIR="$h8" /bin/sh "$realbin/fleet-stuck-detector.sh" "$@"
}
for pair in "$peer_id live-peer" "$self_id this-tower" "cccccccc-cccc-cccc-cccc-cccccccccccc dead-or-unknown"; do
  tok=${pair% *}
  want=${pair#* }
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR PLANWRIGHT_FLEET_STATE_DIR="$h8" \
    /bin/sh "$realbin/fleet-attention.sh" heartbeat "$w" "$s" working >/dev/null
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR PLANWRIGHT_FLEET_STATE_DIR="$h8" \
    /bin/sh "$realbin/fleet-state.sh" register "$w" "$s" --owner "$tok" --backend headless-oneshot --death-handle "process $$" >/dev/null
  out=$(run_real classify "$w" --session-id "$self_id" --checkout "$wt") || fail "real presence ($want): exited non-zero"
  [ "$(owner_of "$out")" = "$want" ] || fail "real presence: token $tok -> '$(owner_of "$out")', expected $want"
  [ "$(state_of "$out")" = working ] || fail "real presence: state '$(state_of "$out")'"
done
echo "ok: attribution resolves through the real presence surface (REQ-C1.6)"

# ---------------------------------------------------------------------------
# 9. REQ-C1.7: the stage from the event stream, degrading visibly.
# ---------------------------------------------------------------------------
h9="$tmp/h9"
sd9="$tmp/sd9"
mkdir -p "$sd9"
attn "$h9" heartbeat "$w" "$s" working >/dev/null
reg "$h9" "$w" "$s" --owner "$self_id" --backend stream-json-persistent --state-dir "$sd9" --death-handle "process 4242" >/dev/null
out=$(run "$h9" classify "$w") || fail "stage absent: exited non-zero"
[ "$(stage_of "$out")" = "-" ] || fail "no event stream: stage '$(stage_of "$out")'"
[ "$(ev "$out" stage-source)" = absent ] || fail "no event stream: source '$(ev "$out" stage-source)'"
ev9="$sd9/events.jsonl"
printf '{"type":"system","subtype":"init","cwd":"%s","session_id":"abc","tools":[]}\n' "$wt" >"$ev9"
out=$(run "$h9" classify "$w") || fail "stage launched: exited non-zero"
[ "$(stage_of "$out")" = launched ] || fail "init only: stage '$(stage_of "$out")'"
[ "$(ev "$out" stage-source)" = events ] || fail "init only: source '$(ev "$out" stage-source)'"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"./tests/test-x.sh"}}]}}\n' >>"$ev9"
out=$(run "$h9" classify "$w") || fail "stage implementing: exited non-zero"
[ "$(stage_of "$out")" = implementing ] || fail "tool use: stage '$(stage_of "$out")'"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"planwright:polish","args":"--nested"}}]}}\n' >>"$ev9"
out=$(run "$h9" classify "$w") || fail "stage converging: exited non-zero"
[ "$(stage_of "$out")" = converging ] || fail "polish skill: stage '$(stage_of "$out")'"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t3","name":"Bash","input":{"command":"git push origin planwright/x/task-1"}}]}}\n' >>"$ev9"
out=$(run "$h9" classify "$w") || fail "stage handing-off: exited non-zero"
[ "$(stage_of "$out")" = handing-off ] || fail "git push: stage '$(stage_of "$out")'"
printf '{"type":"result","subtype":"success","result":"done","session_id":"abc"}\n' >>"$ev9"
out=$(run "$h9" classify "$w") || fail "stage completed: exited non-zero"
[ "$(stage_of "$out")" = completed ] || fail "result event: stage '$(stage_of "$out")'"
[ "$(ev "$out" commits)" = 1 ] || fail "commit count on the unit branch: '$(ev "$out" commits)'"
alt9="$tmp/alt-events.jsonl"
printf '{"type":"system","subtype":"init","cwd":"/nowhere","session_id":"x","tools":[]}\n' >"$alt9"
out=$(run "$h9" classify "$w" --events "$alt9") || fail "--events override: exited non-zero"
[ "$(stage_of "$out")" = launched ] || fail "--events override: stage '$(stage_of "$out")'"
echo "ok: the stage is derived from the event stream and degrades visibly (REQ-C1.7)"

# ---------------------------------------------------------------------------
# 10. REQ-C1.8: the pinned grammar parses with awk alone; a malformed store or
#     registry line is an anomaly, never a torn parse; `scan` renders every
#     registered worker.
# ---------------------------------------------------------------------------
h10="$tmp/h10"
attn "$h10" heartbeat "$w" "$s" working >/dev/null
attn "$h10" heartbeat other-1 "$s" ended >/dev/null
reg "$h10" "$w" "$s" --owner "$self_id" --backend headless-oneshot --death-handle "process 4242" >/dev/null
reg "$h10" other-1 "$s" --owner "$peer_id" --backend tmux --death-handle "tmux-window f w" >/dev/null
out=$(run "$h10" classify "$w" --tower-id "$self_id") || fail "grammar classify exited non-zero"
printf '%s\n' "$out" | awk -F'\t' '
  $1 == "worker" { if (NF != 6) bad = 1; w++ }
  $1 == "evidence" { if (NF != 4) bad = 1 }
  $1 == "anomaly" { if (NF != 3) bad = 1 }
  $1 != "worker" && $1 != "evidence" && $1 != "anomaly" { bad = 1 }
  END { exit (bad || w != 1) }' || fail "output violates the pinned grammar:
$out"
printf '%s\n' "$out" | grep -q "^worker	$w	working	this-tower	-	attention-working$" \
  || fail "worker row shape: $(printf '%s\n' "$out" | grep '^worker')"
# A malformed attention row for this worker: reported, and the worker still classifies.
printf 'bad-row\tonly-two\n' >>"$h10/attention/state"
out=$(run "$h10" classify bad-row 2>/dev/null) || fail "malformed store row: exited non-zero"
printf '%s\n' "$out" | grep -q "^anomaly	bad-row	attention-malformed$" || fail "malformed store row not reported as an anomaly"
[ "$(state_of "$out")" = unclassified ] || fail "malformed store row: state '$(state_of "$out")'"
printf 'bad-ctl\tscope\twork\x1bing\t1700000000\tnormal\t-\t-\t-\n' >>"$h10/attention/state"
out=$(run "$h10" classify bad-ctl 2>/dev/null) || fail "control-byte row: exited non-zero"
printf '%s\n' "$out" | grep -q "^anomaly	bad-ctl	attention-malformed$" || fail "control-byte store row not reported"
printf '%s\n' "$out" | grep -q "$(printf '\033')" && fail "a control byte reached the output"
printf '1700000000\treg-bad\tscope\tx\ty\n' >>"$h10/registry"
out=$(run "$h10" classify reg-bad 2>/dev/null) || fail "malformed registry: exited non-zero"
printf '%s\n' "$out" | grep -q "^anomaly	reg-bad	registry-malformed$" || fail "malformed registry record not reported"
out=$(run "$h10" scan --tower-id "$self_id") || fail "scan exited non-zero"
[ "$(printf '%s\n' "$out" | grep -c '^worker	')" = 5 ] || fail "scan rendered $(printf '%s\n' "$out" | grep -c '^worker	') workers, expected 5"
printf '%s\n' "$out" | grep -q "^worker	other-1	finished-but-unreaped	live-peer	" || fail "scan: other-1 row missing or wrong"
printf '%s\n' "$out" | grep -q "^worker	$w	working	this-tower	" || fail "scan: $w row missing or wrong"
echo "ok: the output grammar is pinned and script-parseable; anomalies are reported (REQ-C1.8)"

# ---------------------------------------------------------------------------
# 11. REQ-K1.5 / REQ-A1.2 / REQ-C1.4 negative assertions over the source: no
#     model, API, network, forge, or pane-capture call in the decision path,
#     and no jq.
# ---------------------------------------------------------------------------
code_only() { grep -vE '^[[:space:]]*#' "$1"; }
for f in "$FSD" "$here/../scripts/fleet-pane-vocabulary.sh"; do
  code_only "$f" | grep -qE 'capture-pane' && fail "$(basename "$f") references capture-pane (REQ-A1.2)"
  code_only "$f" | grep -qE '(^|[^A-Za-z_.])jq([^A-Za-z_]|$)' && fail "$(basename "$f") invokes jq (REQ-K1.5)"
  code_only "$f" | grep -qiE '(^|[^A-Za-z_.])(claude|anthropic|curl|wget|gh)([^A-Za-z_-]|$)' \
    && fail "$(basename "$f") references a model / network / forge call (REQ-K1.5, REQ-C1.4)"
  # A git INVOCATION of a remote-reaching verb (a `git`, optionally `-C <dir>`,
  # at a command position followed by the verb); the awk needle that reads a
  # worker's own `git push` tool use as a stage marker is data, not a call.
  code_only "$f" | grep -qE '(^|[;&|(` \t])git([ \t]+-C[ \t]+[^ \t]+)?[ \t]+(fetch|ls-remote|pull|push)([ \t]|$)' \
    && fail "$(basename "$f") reaches the remote (REQ-C1.4: local git state only)"
done
echo "ok: no model / network / forge call in the decision path (REQ-K1.5, REQ-C1.4)"

echo "PASS: fleet-stuck-detector"
