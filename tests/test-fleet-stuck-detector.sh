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
# Host git config must not reach the fixtures (status.showUntrackedFiles,
# excludes) nor the detector's own reads.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

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
    -u PLANWRIGHT_TOWER_CHECKOUT -u FLEET_PANE_PROMPT_ANCHORS -u FLEET_PANE_PROMPT_SIGNATURES \
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
static_pane_placeholder="$tmp/placeholder-pane"
: >"$static_pane_placeholder"
for args in "" "classify" "classify ../x" "classify a${tab}b" "bogus $w" "classify $w --pane" "classify $w --nope 1" \
  "classify $w --scope x" "classify $w --tower-id ../x" "classify $w --tower-id unknown-owner" \
  "classify $w --session-id nope" "classify $w --pid 007" "classify $w --session-id $self_id --pid 42" \
  "classify $w --checkout relative/dir" "classify $w --worktree /a/../b" "classify $w --state-dir /" \
  "classify $w --death-handle timeout=30" "classify $w --footer-lines 0" "classify $w --prompt-lines x" \
  "classify $w --events $tmp/absent-events" "scan --pane $static_pane_placeholder" "scan $w"; do
  rc=0
  # shellcheck disable=SC2086
  run "$h1" $args >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage: '$args' exited $rc, expected 2"
done
# An empty flag value never reads as "flag not given".
for flag in --pane --events --worktree --state-dir --death-handle --tower-id --checkout --session-id --pid; do
  rc=0
  run "$h1" classify "$w" "$flag" "" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage: empty value for $flag exited $rc, expected 2"
done
echo "ok: usage floor refuses missing / hostile / empty input (exit 2)"

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
[ "$(ev "$out" attention-status)" = absent ] || fail "no signal: attention evidence '$(ev "$out" attention-status)'"
[ "$(ev "$out" attention)" = "-" ] || fail "no signal: attention state '$(ev "$out" attention)'"
[ "$(ev "$out" registry)" = absent ] || fail "no signal: registry evidence '$(ev "$out" registry)'"
static_pane="$tmp/static.txt"
cat >"$static_pane" <<'PANE'
● Reading the spec bundle.
  Comparing the requirements against the design.
  Still comparing.
PANE
for pass in 1 2; do
  [ "$pass" = 2 ] && echo "  Still comparing, slightly further along." >>"$static_pane"
  out=$(run "$h2" classify "$w" --pane "$static_pane") || fail "static pane classify exited non-zero"
  [ "$(state_of "$out")" = unclassified ] || fail "static pane: '$(state_of "$out")', expected unclassified"
  [ "$(ev "$out" pane)" = indeterminate ] || fail "static pane: pane evidence '$(ev "$out" pane)'"
done
# A run with no resolvable fleet home refuses rather than reading as silence.
rc=0
PLANWRIGHT_FLEET_STATE_DIR="" env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_PLUGIN_NAME_OVERRIDE="" /bin/sh "$stubbin/fleet-stuck-detector.sh" classify "$w" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "an unresolvable fleet home must exit 2, got $rc"
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
# A park reason is free text under the store's own grammar (the fence and
# the usage gate write sentences with spaces); it is never read as corruption.
attn "$h3" clear "$w" >/dev/null
attn "$h3" park "$w" "$s" "notification:planwright-fence tentative: the fence for demo/7 is listed by no presence record yet." >/dev/null \
  || fail "setup: free-text park"
out=$(run "$h3" classify "$w") || fail "free-text park classify exited non-zero"
[ "$(state_of "$out")" = waiting-on-a-human ] || fail "free-text park: '$(state_of "$out")'"
printf '%s\n' "$out" | grep -q '^anomaly' && fail "a free-text park reason was reported as an anomaly"
# An answered fork (field 11 stamped) is no longer a queued decision.
attn "$h3" clear "$w" >/dev/null
attn "$h3" fork "$w" "$s" "Which way?" a "a|b" iid-1 >/dev/null || fail "setup: fork"
attn "$h3" claim "$w" iid-1 a >/dev/null || fail "setup: claim"
out=$(run "$h3" classify "$w") || fail "claimed fork classify exited non-zero"
[ "$(state_of "$out")" = unclassified ] || fail "claimed fork: '$(state_of "$out")'"
[ "$(reason_of "$out")" = fork-answered ] || fail "claimed fork: reason '$(reason_of "$out")'"
# The other pushed words: hung is a stop failure, idle a turn end, the
# progress states no signal — none of them any of the four.
for pair in "hung stop-failure" "idle turn-ended" "pr-ready no-signal" "merged no-signal" "done no-signal"; do
  attn "$h3" clear "$w" >/dev/null
  attn "$h3" heartbeat "$w" "$s" "${pair% *}" >/dev/null || fail "setup: ${pair% *} heartbeat"
  out=$(run "$h3" classify "$w") || fail "${pair% *} classify exited non-zero"
  [ "$(state_of "$out")" = unclassified ] || fail "${pair% *} push: '$(state_of "$out")'"
  [ "$(reason_of "$out")" = "${pair#* }" ] || fail "${pair% *} push: reason '$(reason_of "$out")'"
  [ "$(ev "$out" attention)" = "${pair% *}" ] || fail "${pair% *} push: attention evidence '$(ev "$out" attention)'"
done

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
attn "$h4" clear "$w" >/dev/null
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
out=$(run "$h4" classify "$w" --pane "$deep_pane" --prompt-lines 100) || fail "--prompt-lines classify exited non-zero"
[ "$(state_of "$out")" = working ] || fail "a busy footer outranks a signature anywhere in the window: '$(state_of "$out")'"
sed '$d' "$deep_pane" >"$tmp/deep-quiet.txt"
out=$(run "$h4" classify "$w" --pane "$tmp/deep-quiet.txt" --prompt-lines 100) || fail "widened window classify exited non-zero"
[ "$(state_of "$out")" = waiting-on-a-human ] || fail "--prompt-lines must widen the signature window: '$(state_of "$out")'"
attn "$h4" clear "$w" >/dev/null
idle_pane="$tmp/idle.txt"
cat >"$idle_pane" <<'PANE'
● Done with that step.

  ❯
  ? for shortcuts · auto mode on
PANE
out=$(run "$h4" classify "$w" --pane "$idle_pane") || fail "idle pane classify exited non-zero"
[ "$(ev "$out" pane)" = idle-prompt ] || fail "idle pane: evidence '$(ev "$out" pane)'"
[ "$(reason_of "$out")" = turn-ended ] || fail "idle pane: reason '$(reason_of "$out")'"
out=$(env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR PLANWRIGHT_FLEET_STATE_DIR="$h4" \
  FLEET_PANE_PROMPT_SIGNATURES="Custom Dialog Text" /bin/sh "$stubbin/fleet-stuck-detector.sh" classify "$w" --pane "$prompt_pane") \
  || fail "override classify exited non-zero"
[ "$(state_of "$out")" = unclassified ] || fail "an overridden signature set must replace the default: '$(state_of "$out")'"
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
# … but never from a path the worker itself authored: an init event naming
# a clean checkout must not launder a dirty worktree (the events cwd is
# not a worktree source), and a state dir merely nested inside a repo is
# not a worktree either.
printf '{"type":"system","subtype":"init","cwd":"%s","session_id":"abc","tools":[]}\n' "$wt" >"$sd6/events.jsonl"
out=$(run "$h6" classify "$w") || fail "events cwd classify exited non-zero"
[ "$(ev "$out" worktree)" = "-" ] || fail "events cwd must not resolve a worktree: '$(ev "$out" worktree)'"
[ "$(ev "$out" tree)" = unverifiable ] || fail "events cwd: tree '$(ev "$out" tree)'"
rm -f "$sd6/events.jsonl"
h6n="$tmp/h6n"
nested="$wt/.fleet/unit"
mkdir -p "$nested"
printf 'result\tsuccess\t1700000000\n' >"$nested/result"
reg "$h6n" "$w" "$s" --owner "$self_id" --backend headless-oneshot --state-dir "$nested" --death-handle "process 4242" >/dev/null
out=$(run "$h6n" classify "$w") || fail "nested state dir classify exited non-zero"
[ "$(ev "$out" worktree)" = "-" ] || fail "a nested state dir is not a worktree: '$(ev "$out" worktree)'"
[ "$(ev "$out" completion)" = "result=success" ] || fail "nested state dir is a runtime dir: '$(ev "$out" completion)'"
rm -rf "$wt/.fleet"
# A worktree that holds a file named `result` is still a worktree, not a
# runtime dir.
printf 'exit\t0\tx\n' >"$wt/result"
attn "$h6b" heartbeat "$w" "$s" working >/dev/null
out=$(run "$h6b" classify "$w") || fail "worktree result file classify exited non-zero"
[ "$(ev "$out" completion)" = absent ] || fail "a worktree's own result file was read as a runtime record: '$(ev "$out" completion)'"
[ "$(state_of "$out")" = working ] || fail "worktree result file: '$(state_of "$out")'"
rm -f "$wt/result"
attn "$h6b" heartbeat "$w" "$s" ended >/dev/null
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
# A session that ended WITHOUT completing — a non-zero exit, a non-success
# result subtype — is never finished: the supervisor renders it ended, and so
# does the detector.
for rec in "exit${tab}1${tab}1700000000" "result${tab}error_max_turns${tab}1700000000"; do
  printf '%s\n' "$rec" >"$sd6/result"
  out=$(run "$h6" classify "$w" --worktree "$wt") || fail "failed completion classify exited non-zero"
  [ "$(state_of "$out")" = unclassified ] || fail "failed completion '$rec': '$(state_of "$out")'"
  case $(reason_of "$out") in
    completion-failed:*) ;;
    *) fail "failed completion '$rec': reason '$(reason_of "$out")'" ;;
  esac
done
printf '0 1700000000\n' >"$sd6c/exit"
printf '137 1700000000\n' >"$sd6c/exit"
out=$(run "$h6c" classify "$w") || fail "headless nonzero exit classify exited non-zero"
[ "$(reason_of "$out")" = "completion-failed:exit=137" ] || fail "headless nonzero exit: reason '$(reason_of "$out")'"
printf '0 1700000000\n' >"$sd6c/exit"
# A malformed result record is an anomaly, after the worker's evidence rows.
printf 'garbage\t1\n' >"$sd6/result"
out=$(run "$h6" classify "$w" --worktree "$wt") || fail "malformed result classify exited non-zero"
printf '%s\n' "$out" | grep -q "^anomaly	$w	result-record-malformed$" || fail "malformed result record not reported"
[ "$(ev "$out" completion)" = absent ] || fail "malformed result: completion '$(ev "$out" completion)'"
[ "$(printf '%s\n' "$out" | awk -F'\t' '$1 == "worker" { print NR }')" = 1 ] || fail "the worker row must come first"
# A pending journal receipt is a queued human decision while the session
# lives, and stale once a completion record exists.
rm -f "$sd6/result"
printf 'req-1\tpermission\t1700000000\tpending\n' >"$sd6/journal"
out=$(run "$h6" classify "$w") || fail "journal pending classify exited non-zero"
[ "$(state_of "$out")" = waiting-on-a-human ] || fail "journal pending: '$(state_of "$out")'"
[ "$(reason_of "$out")" = journal-pending ] || fail "journal pending: reason '$(reason_of "$out")'"
[ "$(ev "$out" journal-pending)" = 1 ] || fail "journal pending: evidence '$(ev "$out" journal-pending)'"
printf 'result\tsuccess\t1700000000\n' >"$sd6/result"
out=$(run "$h6" classify "$w" --worktree "$wt") || fail "journal + result classify exited non-zero"
[ "$(state_of "$out")" = finished-but-unreaped ] || fail "a pending receipt of an ended session is stale: '$(state_of "$out")'"
printf 'req-1\tpermission\t1700000000\tanswered\t1700000001\n' >"$sd6/journal"
# A queued human decision outranks a captured result.
attn "$h6" decide "$w" "$s" "q?" a "a|b" >/dev/null
out=$(run "$h6" classify "$w" --worktree "$wt") || fail "decide + result classify exited non-zero"
[ "$(state_of "$out")" = waiting-on-a-human ] || fail "a queued decision must outrank a result: '$(state_of "$out")'"
attn "$h6" clear "$w" >/dev/null
# Both runtime pidfiles with positive alive evidence and no result is a
# running worker, even when the registry recorded no death handle.
h6r="$tmp/h6r"
sd6r="$tmp/sd6r"
mkdir -p "$sd6r"
printf '4242\n' >"$sd6r/supervisor.pid"
printf '4243\n' >"$sd6r/worker.pid"
reg "$h6r" "$w" "$s" --owner "$self_id" --backend stream-json-persistent --state-dir "$sd6r" >/dev/null
: >"$tmp/evidence-calls"
printf 'alive\n' >"$tmp/evidence-verdict"
out=$(run "$h6r" classify "$w") || fail "runtime running classify exited non-zero"
[ "$(state_of "$out")" = working ] || fail "runtime running: '$(state_of "$out")'"
[ "$(reason_of "$out")" = runtime-running ] || fail "runtime running: reason '$(reason_of "$out")'"
grep -q '^process 4242$' "$tmp/evidence-calls" || fail "the supervisor pidfile was not used as the death handle"
rm -f "$sd6r/worker.pid"
out=$(run "$h6r" classify "$w") || fail "one pidfile classify exited non-zero"
[ "$(state_of "$out")" = unclassified ] || fail "one pidfile is not a running worker: '$(state_of "$out")'"
# A worktree with no remote-tracking ref at all cannot verify pushes.
lone="$tmp/lone"
git_q init -q "$lone"
printf 'x\n' >"$lone/x"
git_q -C "$lone" add x
git_q -C "$lone" commit -q -m x
printf 'result\tsuccess\t1700000000\n' >"$sd6/result"
out=$(run "$h6" classify "$w" --worktree "$lone") || fail "remote-less classify exited non-zero"
[ "$(ev "$out" tree)" = clean ] || fail "remote-less: tree '$(ev "$out" tree)'"
[ "$(ev "$out" unpushed)" = unverifiable ] || fail "remote-less: unpushed '$(ev "$out" unpushed)'"
[ "$(state_of "$out")" = finished-but-unreaped ] || fail "remote-less: '$(state_of "$out")'"
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
for answer in "tower	$peer_id	unknown unknown" "tower	$peer_id	ambiguous ambiguous" "no-record	$peer_id no-record" "unreadable	$peer_id	malformed unreadable"; do
  printf '%s\n' "${answer% *}" >"$tmp/presence-answer"
  out=$(run "$h7" classify "$w" --tower-id "$self_id" --session-id "$self_id" --checkout "$wt") \
    || fail "presence '$answer': exited non-zero"
  [ "$(owner_of "$out")" = dead-or-unknown ] || fail "presence '$answer': owner '$(owner_of "$out")'"
  [ "$(ev "$out" owner-evidence)" = "${answer##* }" ] || fail "presence '$answer': evidence '$(ev "$out" owner-evidence)'"
done
printf 'tower\t%s\tlive\n' "$peer_id" >"$tmp/presence-answer"
# An unreadable surface (presence exits 3) degrades to dead-or-unknown, never
# to this-tower, and says so.
printf '3\n' >"$tmp/presence-exit"
out=$(run "$h7" classify "$w" --tower-id "$self_id" --session-id "$self_id" --checkout "$wt" 2>/dev/null) \
  || fail "unreadable surface: exited non-zero"
[ "$(owner_of "$out")" = dead-or-unknown ] || fail "unreadable surface: owner '$(owner_of "$out")'"
[ "$(ev "$out" owner-evidence)" = presence-unavailable ] || fail "unreadable surface: evidence '$(ev "$out" owner-evidence)'"
printf '0\n' >"$tmp/presence-exit"
# The token is compared to this tower's identity before the surface is asked,
# but a non-self token with NO identity to call the surface with is unknown.
out=$(run "$h7" classify "$w") || fail "no identity: exited non-zero"
[ "$(owner_of "$out")" = dead-or-unknown ] || fail "no identity: owner '$(owner_of "$out")'"
[ "$(ev "$out" owner-evidence)" = no-identity ] || fail "no identity: evidence '$(ev "$out" owner-evidence)'"
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
[ "$(ev "$out" owner-evidence)" = absent ] || fail "absent token: evidence '$(ev "$out" owner-evidence)'"
# A store-legal token the presence surface cannot recognize is displayable
# and never live, and the surface is not asked about it.
h7c="$tmp/h7c"
attn "$h7c" heartbeat "$w" "$s" working >/dev/null
reg "$h7c" "$w" "$s" --owner some-orchestrator --backend headless-oneshot --death-handle "process 4242" >/dev/null
: >"$tmp/presence-calls"
out=$(run "$h7c" classify "$w" --tower-id "$self_id" --session-id "$self_id" --checkout "$wt") || fail "unrecognized token: exited non-zero"
[ "$(owner_of "$out")" = dead-or-unknown ] || fail "unrecognized token: owner '$(owner_of "$out")'"
[ "$(ev "$out" owner-evidence)" = unrecognized ] || fail "unrecognized token: evidence '$(ev "$out" owner-evidence)'"
[ ! -s "$tmp/presence-calls" ] || fail "an unrecognized token was handed to the presence surface"
# The same token under the registry's own grammar IS this tower when the
# tower says so (fleet-register.sh stamps PLANWRIGHT_TOWER_ID under that
# grammar, so the two must agree).
out=$(PLANWRIGHT_TOWER_ID=some-orchestrator env PLANWRIGHT_FLEET_STATE_DIR="$h7c" /bin/sh "$stubbin/fleet-stuck-detector.sh" classify "$w") \
  || fail "owner-grammar token: exited non-zero"
[ "$(owner_of "$out")" = this-tower ] || fail "owner-grammar env token: owner '$(owner_of "$out")'"
# The env-carried identity inputs resolve through the surface like the flags.
: >"$tmp/presence-calls"
out=$(PLANWRIGHT_TOWER_SESSION_ID="$self_id" PLANWRIGHT_TOWER_CHECKOUT="$wt" env PLANWRIGHT_FLEET_STATE_DIR="$h7" /bin/sh "$stubbin/fleet-stuck-detector.sh" classify "$w") \
  || fail "env identity: exited non-zero"
[ "$(owner_of "$out")" = live-peer ] || fail "env identity: owner '$(owner_of "$out")'"
grep -q "^identity --checkout $wt --session-id $self_id$" "$tmp/presence-calls" || fail "env identity did not resolve through the surface"
# An explicit --session-id outranks an ambient token, as it does for the registrar.
out=$(PLANWRIGHT_TOWER_ID="$peer_id" env PLANWRIGHT_FLEET_STATE_DIR="$h7" /bin/sh "$stubbin/fleet-stuck-detector.sh" classify "$w" --session-id "$self_id" --checkout "$wt") \
  || fail "explicit over ambient: exited non-zero"
[ "$(owner_of "$out")" = live-peer ] || fail "explicit --session-id must outrank the ambient token: '$(owner_of "$out")'"
# The surface's own `self` answer attributes to this tower.
printf 'tower\t%s\tself\n' "$peer_id" >"$tmp/presence-answer"
out=$(run "$h7" classify "$w" --session-id "$self_id" --checkout "$wt") || fail "surface self: exited non-zero"
[ "$(owner_of "$out")" = this-tower ] || fail "surface self answer: owner '$(owner_of "$out")'"
printf 'tower\t%s\tlive\n' "$peer_id" >"$tmp/presence-answer"
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
: >"$ev9"
out=$(run "$h9" classify "$w") || fail "empty stream: exited non-zero"
[ "$(stage_of "$out")" = "-" ] || fail "an empty stream is no positive stage: '$(stage_of "$out")'"
[ "$(ev "$out" stage-source)" = events ] || fail "empty stream: source '$(ev "$out" stage-source)'"
printf '{"type":"system","subtype":"init","cwd":"%s","session_id":"abc","tools":[]}\n' "$wt" >"$ev9"
out=$(run "$h9" classify "$w") || fail "stage launched: exited non-zero"
[ "$(stage_of "$out")" = launched ] || fail "init only: stage '$(stage_of "$out")'"
[ "$(ev "$out" stage-source)" = events ] || fail "init only: source '$(ev "$out" stage-source)'"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"./tests/test-x.sh"}}]}}\n' >>"$ev9"
out=$(run "$h9" classify "$w") || fail "stage implementing: exited non-zero"
[ "$(stage_of "$out")" = implementing ] || fail "tool use: stage '$(stage_of "$out")'"
# A tool call that merely MENTIONS a marker is not the marker.
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1b","name":"Bash","input":{"command":"grep -n \\"git push\\" scripts/x.sh"}}]}}\n' >>"$ev9"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1c","name":"Skill","input":{"skill":"planwright:execute-task","args":"then polish"}}]}}\n' >>"$ev9"
out=$(run "$h9" classify "$w") || fail "stage mention: exited non-zero"
[ "$(stage_of "$out")" = implementing ] || fail "a mention must not set a stage: '$(stage_of "$out")'"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"planwright:self-review","args":"--nested"}}]}}\n' >>"$ev9"
out=$(run "$h9" classify "$w") || fail "stage converging: exited non-zero"
[ "$(stage_of "$out")" = converging ] || fail "self-review skill: stage '$(stage_of "$out")'"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"planwright:polish","args":"--nested"}}]}}\n' >>"$ev9"
out=$(run "$h9" classify "$w") || fail "stage converging: exited non-zero"
[ "$(stage_of "$out")" = converging ] || fail "polish skill: stage '$(stage_of "$out")'"
# A line the supervisor is still appending never sets a stage.
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2b","name":"Bash","input":{"command":"git push origin x' >>"$ev9"
out=$(run "$h9" classify "$w") || fail "partial line: exited non-zero"
[ "$(stage_of "$out")" = converging ] || fail "a partial last line must not set a stage: '$(stage_of "$out")'"
printf '"}}]}}\n' >>"$ev9"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t3","name":"Bash","input":{"command":"git push origin planwright/x/task-1"}}]}}\n' >>"$ev9"
out=$(run "$h9" classify "$w") || fail "stage handing-off: exited non-zero"
[ "$(stage_of "$out")" = handing-off ] || fail "git push: stage '$(stage_of "$out")'"
printf '{"type":"result","subtype":"success","result":"done","session_id":"abc"}\n' >>"$ev9"
out=$(run "$h9" classify "$w" --worktree "$wt") || fail "stage completed: exited non-zero"
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
inventory=$(printf '%s\n' "$out" | awk -F'\t' '$1 == "evidence" { print $3 }' | tr '\n' ' ')
[ "$inventory" = "registry backend scope owner-token owner-evidence attention attention-status attention-reason death completion journal-pending worktree tree unpushed commits pane stage-source " ] \
  || fail "evidence inventory drifted: $inventory"
[ "$(ev "$out" scope)" = "$s" ] || fail "scope evidence '$(ev "$out" scope)'"
# A legacy three-column record still parses, owner absent.
printf '1700000000\tlegacy-1\t%s\n' "$s" >>"$h10/registry"
out=$(run "$h10" classify legacy-1) || fail "legacy record classify exited non-zero"
[ "$(ev "$out" registry)" = present ] || fail "legacy record: registry '$(ev "$out" registry)'"
[ "$(ev "$out" owner-token)" = "-" ] || fail "legacy record: owner-token '$(ev "$out" owner-token)'"
# A seven-column record with one corrupt field is reported and never half-trusted.
printf '1700000000\tcorrupt-1\t%s\t%s\theadless-oneshot\trelative/dir\tprocess 4242\n' "$s" "$self_id" >>"$h10/registry"
out=$(run "$h10" classify corrupt-1 2>/dev/null) || fail "corrupt record classify exited non-zero"
printf '%s\n' "$out" | grep -q "^anomaly	corrupt-1	registry-malformed$" || fail "corrupt registry field not reported"
[ "$(ev "$out" owner-token)" = "-" ] || fail "corrupt record: owner-token was trusted: '$(ev "$out" owner-token)'"
[ "$(ev "$out" backend)" = "-" ] || fail "corrupt record: backend was trusted"
# Numeric-looking handles are compared as strings.
attn "$h10" heartbeat 100 "$s" ended >/dev/null
attn "$h10" heartbeat 1e2 "$s" working >/dev/null
out=$(run "$h10" classify 100) || fail "numeric handle classify exited non-zero"
[ "$(ev "$out" attention)" = ended ] || fail "handle 100 read another worker's row: '$(ev "$out" attention)'"
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
printf '1700000000\tbad handle\tscope\n' >>"$h10/registry"
: >"$tmp/presence-calls"
out=$(run "$h10" scan --tower-id "$self_id" --session-id "$self_id" --checkout "$wt") || fail "scan exited non-zero"
[ "$(printf '%s\n' "$out" | grep -c '^worker	')" = 9 ] || fail "scan rendered $(printf '%s\n' "$out" | grep -c '^worker	') workers, expected 9"
printf '%s\n' "$out" | grep -q "^worker	other-1	finished-but-unreaped	live-peer	" || fail "scan: other-1 row missing or wrong"
printf '%s\n' "$out" | grep -q "^worker	$w	working	this-tower	" || fail "scan: $w row missing or wrong"
[ "$(printf '%s\n' "$out" | grep -c '^anomaly	bad handle	handle-malformed$')" = 1 ] || fail "scan: torn handle not reported once"
[ "$(grep -c '^liveness' "$tmp/presence-calls")" = 1 ] || fail "scan asked the presence surface $(grep -c '^liveness' "$tmp/presence-calls") times for one distinct token"
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$h10/attention/state"
  out=$(run "$h10" scan --tower-id "$self_id" 2>/dev/null) || fail "unreadable store scan exited non-zero"
  printf '%s\n' "$out" | grep -q '^anomaly	-	store-unreadable$' || fail "an unreadable store must be reported, not read as empty"
  out=$(run "$h10" classify "$w" --tower-id "$self_id" 2>/dev/null) || fail "unreadable store classify exited non-zero"
  [ "$(ev "$out" attention-status)" = unreadable ] || fail "unreadable store: '$(ev "$out" attention-status)'"
  chmod 600 "$h10/attention/state"
fi
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
