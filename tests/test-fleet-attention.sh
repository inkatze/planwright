#!/bin/bash
# Tests for scripts/fleet-attention.sh — the substrate-agnostic ATTENTION/
# NOTIFICATION capability lifted into core (orchestration-fleet Task 12; D-13,
# REQ-E1.3, REQ-E1.4, REQ-A1.6). It parallels the execution capability: a
# heartbeat/awareness state store, a portable status renderer, the decision
# queue, and a notification seam — all built ON Task 9's cross-spec fleet home
# (scripts/fleet-state.sh: the D-11 home resolution and the advisory-lock
# primitive), depending on no dotfiles-local mechanism so a marketplace-install
# user gets it from core.
#
# Contract under test:
#   - heartbeat/awareness state lives UNDER the Task 9 cross-spec home and works
#     with no dotfiles present (marketplace-install parity);
#   - the renderer lists each worker's scope AND state (REQ-E1.3);
#   - the decision queue orders actionable items across specs as structured
#     choices and its length tracks the `## Awaiting input` count, NOT the
#     worker count — non-actionable signal is suppressed (REQ-E1.3);
#   - the queue is alarm-rationalized: ordered by priority, then oldest-waiting;
#   - a backend advertising provides_attention_surface:true suppresses
#     planwright's own render/queue (backend-capability-contract adaptation);
#   - the notification seam dispatches through the resolved channel (none is a
#     silent no-op; editor-toast drops a sanitized line);
#   - artifact data hygiene (REQ-A1.6): hostile worker/scope/decision fields are
#     refused, and rendered output is stripped of control/escape bytes;
#   - concurrent writes are serialized through the Task 9 lock (no torn/lost
#     rows, upsert keeps one row per worker);
#   - no fleet path writes into the sibling's spec-local .orchestrate/ dir.
#
# Hermetic: every case drives a concrete fleet home via the Task 9
# PLANWRIGHT_FLEET_STATE_DIR override and strips ambient HOME / CLAUDE_* leaks,
# so the suite is reproducible on a dev box and CI alike (the D-11 resolution
# chain itself is covered by test-fleet-state.sh, not re-tested here). Runs
# standalone under /bin/bash (bash 3.2).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FA="$here/../scripts/fleet-attention.sh"
FS="$here/../scripts/fleet-state.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FA" ] || fail "scripts/fleet-attention.sh missing or not executable"
[ -x "$FS" ] || fail "scripts/fleet-state.sh missing or not executable (Task 9 dependency)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tab=$(printf '\t')

# A hermetic invocation against a given home: strip every ambient resolution
# knob, then pin the Task 9 override to the case's home. No HOME / dotfiles are
# present, which is exactly the marketplace-install parity the capability
# promises (heartbeat/registry state under the plugin-data home, no inbox).
aenv() {
  _home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT \
    -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS \
    PLANWRIGHT_FLEET_STATE_DIR="$_home" /bin/sh "$FA" "$@"
}

# ---------------------------------------------------------------------------
# 1. Marketplace-install parity + store home: with only the Task 9 override set
#    (no HOME, no dotfiles, no CLAUDE_*), a heartbeat records state under the
#    cross-spec fleet home, and the store sits under that home (not in a specs/
#    tree, not in a sibling .orchestrate/ dir).
# ---------------------------------------------------------------------------
home="$tmp/fleet-home"
aenv "$home" heartbeat "worker=alpha" "orchestration-fleet:12" working \
  || fail "heartbeat: non-zero exit under marketplace-install parity"
[ -d "$home" ] || fail "heartbeat did not create the fleet home"
case $home in
  */specs/*) fail "fleet home '$home' sits under a specs/ tree (sibling territory)" ;;
esac
[ ! -e "$home/.orchestrate" ] || fail "attention writes created a sibling .orchestrate dir"
find "$home" -name '.orchestrate' -print 2>/dev/null | grep -q . \
  && fail "an attention path wrote into a .orchestrate dir"
# Read the record back UNDER this home (not just "the dir exists"): prove the
# heartbeat actually persisted here, so a regression that wrote elsewhere while
# still touching the home dir cannot pass.
[ -f "$home/attention/state" ] || fail "no state store under the resolved home"
aenv "$home" render 2>/dev/null | grep -q "worker=alpha" \
  || fail "heartbeat did not persist a retrievable record under this home"
echo "ok: heartbeat records state under the Task 9 cross-spec home with no dotfiles present"

# ---------------------------------------------------------------------------
# 2. The renderer lists each worker's scope AND state (REQ-E1.3).
# ---------------------------------------------------------------------------
home2="$tmp/render-home"
aenv "$home2" heartbeat "worker=a" "spec-one:3" working || fail "render setup: heartbeat a"
aenv "$home2" heartbeat "worker=b" "spec-two:5" pr-ready || fail "render setup: heartbeat b"
aenv "$home2" heartbeat "worker=c" "spec-one:4" merged || fail "render setup: heartbeat c"
out=$(aenv "$home2" render) || fail "render: non-zero exit"
while IFS='|' read -r rw rscope rstate; do
  [ -n "$rw" ] || continue
  line=$(printf '%s\n' "$out" | grep -F "$rw") || fail "render: worker '$rw' not listed"
  # Positional check ([state] scope  worker …), not a bare substring test: a
  # regression that swapped the scope and state columns would still contain both
  # strings somewhere on the line, so assert they sit in their labeled fields.
  case $line in
    "[$rstate] $rscope  $rw  ("*) ;;
    *) fail "render: worker '$rw' line not in '[state] scope  worker' order (got: $line)" ;;
  esac
done <<'EOF'
worker=a|spec-one:3|working
worker=b|spec-two:5|pr-ready
worker=c|spec-one:4|merged
EOF
echo "ok: the renderer lists each worker's scope and state"

# ---------------------------------------------------------------------------
# 3. Upsert: a second heartbeat for the same worker REPLACES its row (one row
#    per worker, last state wins) — the renderer shows current state, not a log.
# ---------------------------------------------------------------------------
aenv "$home2" heartbeat "worker=a" "spec-one:3" "done" || fail "upsert: re-heartbeat a"
out=$(aenv "$home2" render) || fail "render after upsert"
arows=$(printf '%s\n' "$out" | grep -c "worker=a") || true
[ "$arows" = 1 ] || fail "upsert: worker=a has $arows rows, expected exactly 1 (state store, not a log)"
printf '%s\n' "$out" | grep "worker=a" | grep -q "done" \
  || fail "upsert: worker=a did not advance to 'done'"
printf '%s\n' "$out" | grep "worker=a" | grep -q "working" \
  && fail "upsert: worker=a still shows the stale 'working' state"
echo "ok: heartbeat upserts (one row per worker, last state wins)"

# ---------------------------------------------------------------------------
# 4. The decision queue: `decide` records a worker as awaiting-input with a
#    structured choice (scope, question, recommended default, options) and the
#    queue renders it. Non-decision heartbeats do NOT appear in the queue.
# ---------------------------------------------------------------------------
home4="$tmp/queue-home"
aenv "$home4" heartbeat "worker=busy" "spec-x:1" working || fail "queue setup: working"
aenv "$home4" heartbeat "worker=ready" "spec-x:2" pr-ready || fail "queue setup: pr-ready"
# The recommended default (retry-none) is deliberately a token that appears
# NOWHERE in the options list, so its assertion cannot be satisfied by the
# options field — the default column is verified independently.
aenv "$home4" decide "worker=stuck" "spec-y:7" \
  "Retry policy on partial success?" "retry-none" \
  "retry-full|retry-failed-substep|fail-fast" high \
  || fail "decide: non-zero exit"
q=$(aenv "$home4" queue) || fail "queue: non-zero exit"
case $q in *"spec-y:7"*) ;; *) fail "queue: decision scope not rendered (got: $q)" ;; esac
case $q in *"Retry policy on partial success?"*) ;; *) fail "queue: question not rendered" ;; esac
case $q in *"retry-none"*) ;; *) fail "queue: recommended default not rendered independently" ;; esac
case $q in *"retry-full|retry-failed-substep|fail-fast"*) ;; *) fail "queue: options not rendered" ;; esac
# Non-actionable workers are suppressed from the queue.
case $q in *"worker=busy"*) fail "queue: a non-actionable (working) worker leaked into the queue" ;; esac
case $q in *"worker=ready"*) fail "queue: a non-actionable (pr-ready) worker leaked into the queue" ;; esac
echo "ok: the decision queue renders structured choices and suppresses non-actionable signal"

# ---------------------------------------------------------------------------
# 5. Queue LENGTH tracks the awaiting-input count (one awaiting-input record per
#    `## Awaiting input` entry, by the pause-protocol correspondence), NOT the
#    worker count (REQ-E1.3). Here: 5 workers, 2 awaiting-input → queue length 2.
#    The queue's own count is cross-checked against an INDEPENDENT oracle: a
#    direct awk count of awaiting-input rows in the store (a different mechanism
#    than the queue's), so the assertion is causal, not two hand-matched numbers.
# ---------------------------------------------------------------------------
home5="$tmp/count-home"
aenv "$home5" heartbeat "worker=w1" "spec-a:1" working || fail "count: w1"
aenv "$home5" heartbeat "worker=w2" "spec-a:2" pr-ready || fail "count: w2"
aenv "$home5" heartbeat "worker=w3" "spec-b:1" merged || fail "count: w3"
aenv "$home5" decide "worker=w4" "spec-a:3" "Endpoint visibility?" "internal" "public|internal" normal \
  || fail "count: w4 decide"
aenv "$home5" decide "worker=w5" "spec-b:2" "Validation strict or lenient?" "strict" "strict|lenient" normal \
  || fail "count: w5 decide"
count=$(aenv "$home5" queue --count) || fail "queue --count: non-zero exit"
[ "$count" = 2 ] || fail "queue length is $count, expected 2 (must track awaiting-input, not the 5 workers)"
# Independent oracle: count awaiting-input rows straight from the store (field 3
# == awaiting-input) with a mechanism the queue does not share. The queue's
# self-reported length must equal it — this is what makes "length tracks the
# actionable count" a causal check rather than two author-matched constants.
oracle=$(awk -F"$tab" '$3 == "awaiting-input" { c++ } END { print c + 0 }' "$home5/attention/state")
[ "$oracle" = "$count" ] \
  || fail "queue --count ($count) disagrees with an independent awaiting-input row count ($oracle)"
# And it is NOT the worker count (5): the actionable-only property.
total=$(wc -l <"$home5/attention/state" | tr -d ' ')
[ "$total" = 5 ] || fail "count setup: expected 5 worker rows, got $total"
[ "$count" != "$total" ] || fail "queue length equals the worker count — non-actionable signal is not suppressed"
echo "ok: the queue length tracks the awaiting-input count (independent oracle), not the worker count"

# ---------------------------------------------------------------------------
# 6. Alarm rationalization — ordering. Priority first (high before normal before
#    low); within a priority, the oldest-waiting decision first. The age tiebreak
#    is proven deterministically: two normal-priority decisions recorded a clock
#    tick apart, the earlier one must sort first.
# ---------------------------------------------------------------------------
home6="$tmp/order-home"
aenv "$home6" decide "worker=lo" "spec-c:1" "low question" "d" "a|b" low || fail "order: lo"
aenv "$home6" decide "worker=hi" "spec-c:2" "high question" "d" "a|b" high || fail "order: hi"
aenv "$home6" decide "worker=n1" "spec-c:3" "normal first" "d" "a|b" normal || fail "order: n1"
sleep 2 # advance the clock so n2's commit timestamp is strictly later than n1's
aenv "$home6" decide "worker=n2" "spec-c:4" "normal second" "d" "a|b" normal || fail "order: n2"
q6=$(aenv "$home6" queue) || fail "order: queue"
# Extract the order the four workers appear in the queue.
order=$(printf '%s\n' "$q6" | grep -oE 'worker=(hi|n1|n2|lo)' | sed 's/worker=//' | tr '\n' ' ')
[ "$order" = "hi n1 n2 lo " ] \
  || fail "queue order was '$order', expected 'hi n1 n2 lo ' (priority desc, then oldest-first)"
echo "ok: the queue is alarm-rationalized (priority desc, oldest-waiting first within a priority)"

# ---------------------------------------------------------------------------
# 7. provides_attention_surface:true suppression — the backend-capability
#    contract scopes deferral to the DECISION QUEUE only (the actionable
#    surface): `queue` suppresses (empty stdout, a one-line stderr notice, exit
#    0), but the status `render` is NOT suppressed (status stays available).
#    Both the --surface-provided flag and the env signal are honored for queue.
# ---------------------------------------------------------------------------
home7="$tmp/suppress-home"
aenv "$home7" heartbeat "worker=s1" "spec-s:1" working || fail "suppress: heartbeat"
aenv "$home7" decide "worker=s2" "spec-s:2" "q?" "d" "a|b" normal || fail "suppress: decide"
# queue defers: empty stdout + a stderr notice, via the flag AND the env signal.
so=$(aenv "$home7" queue --surface-provided 2>/dev/null) || fail "suppress: queue --surface-provided non-zero exit"
[ -z "$so" ] || fail "suppress: queue --surface-provided still wrote to stdout ('$so')"
se=$(aenv "$home7" queue --surface-provided 2>&1 >/dev/null) || true
[ -n "$se" ] || fail "suppress: queue --surface-provided emitted no deferral notice on stderr"
so=$(env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home7" PLANWRIGHT_ATTENTION_SURFACE_PROVIDED=1 \
  /bin/sh "$FA" queue 2>/dev/null) || fail "suppress: queue env-signal non-zero exit"
[ -z "$so" ] || fail "suppress: queue with the env advertisement still rendered ('$so')"
# render is NOT the actionable surface: it stays available even when a backend
# provides its own attention surface (contract scopes deferral to the queue).
ro=$(aenv "$home7" render --surface-provided 2>/dev/null) || fail "render --surface-provided non-zero exit"
[ -n "$ro" ] || fail "render was suppressed by --surface-provided (contract defers the QUEUE only, not status)"
ro=$(env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home7" PLANWRIGHT_ATTENTION_SURFACE_PROVIDED=1 \
  /bin/sh "$FA" render 2>/dev/null) || fail "render env-signal non-zero exit"
[ -n "$ro" ] || fail "render was suppressed by the env advertisement (status must stay available)"
# Sanity: without any signal, the queue DOES render (so the suppression is real).
[ -n "$(aenv "$home7" queue 2>/dev/null)" ] || fail "suppress control: queue is empty even unsuppressed"
echo "ok: provides_attention_surface suppresses the decision queue only; status render stays available"

# ---------------------------------------------------------------------------
# 8. clear removes a worker's row (idempotent) — cleanup on merged/done teardown.
# ---------------------------------------------------------------------------
home8="$tmp/clear-home"
aenv "$home8" heartbeat "worker=gone" "spec-z:1" "done" || fail "clear: heartbeat"
aenv "$home8" heartbeat "worker=stay" "spec-z:2" working || fail "clear: heartbeat stay"
aenv "$home8" clear "worker=gone" || fail "clear: non-zero exit"
out=$(aenv "$home8" render) || fail "clear: render"
case $out in *"worker=gone"*) fail "clear: worker=gone still present after clear" ;; esac
case $out in *"worker=stay"*) ;; *) fail "clear: removed the wrong worker (stay is gone)" ;; esac
aenv "$home8" clear "worker=gone" || fail "clear: not idempotent on an absent worker"
echo "ok: clear removes a worker's row and is idempotent"

# ---------------------------------------------------------------------------
# 9. Data hygiene (REQ-A1.6): hostile worker/scope identifiers are refused
#    (reusing the Task 9 field grammar), and nothing is written for them.
# ---------------------------------------------------------------------------
home9="$tmp/hostile-home"
rc=0
aenv "$home9" heartbeat "../../etc/passwd" "spec:1" working >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "hostile worker id accepted by heartbeat"
rc=0
aenv "$home9" heartbeat "worker=ok" "$(printf 'sc\tope')" working >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "scope with an embedded tab accepted (would tear the record)"
rc=0
aenv "$home9" decide "worker=ok" "spec:1" "$(printf 'q\twith\ttabs')" "d" "a|b" normal >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "decision question with embedded tabs accepted (would tear the record)"
rc=0
aenv "$home9" decide "worker=ok" "spec:1" "$(printf 'q\nnewline')" "d" "a|b" normal >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "decision question with an embedded newline accepted (would tear the record)"
# "Nothing written" must be asserted directly: all four writes were refused, so
# the store must not exist at all (a refused write must not even create it). A
# regression that stripped a hostile field and then wrote a `worker=ok` row
# would fail this, where the old passwd-only grep (guarded by an existence
# check that is never true) asserted nothing.
[ ! -e "$home9/attention/state" ] \
  || fail "a refused hostile write still created/populated the state store ($(wc -l <"$home9/attention/state") rows)"
echo "ok: hostile worker/scope/decision fields are refused, nothing written"

# ---------------------------------------------------------------------------
# 10. State enum: heartbeat rejects awaiting-input (that needs a structured
#     decision — use `decide`) and any unknown state.
# ---------------------------------------------------------------------------
home10="$tmp/enum-home"
rc=0
aenv "$home10" heartbeat "worker=x" "spec:1" awaiting-input >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "heartbeat accepted awaiting-input without a decision (must route through 'decide')"
rc=0
aenv "$home10" heartbeat "worker=x" "spec:1" bogus-state >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "heartbeat accepted an unknown state"
rc=0
aenv "$home10" decide "worker=x" "spec:1" "q?" "d" "a|b" bogus-priority >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "decide accepted an unknown priority"
echo "ok: heartbeat rejects awaiting-input and unknown states; decide rejects an unknown priority"

# ---------------------------------------------------------------------------
# 11. Echo discipline on render (doctrine/security-posture.md): even a store line
#     corrupted with control/escape bytes (e.g. a hand-edited or pre-grammar
#     record) is stripped before it reaches the terminal — the render path never
#     emits raw C0/DEL bytes. Belt-and-suspenders over the write-time rejection.
# ---------------------------------------------------------------------------
home11="$tmp/inj-home"
mkdir -p "$home11/attention"
# A crafted state line carrying an ESC/OSC/BEL sequence in the scope field.
esc=$(printf 'x\033]0;INJECT\007y')
printf 'worker=inj\t%s\tworking\t1700000000\t\t\t\t\n' "$esc" >"$home11/attention/state"
rout=$(aenv "$home11" render 2>/dev/null) || fail "render: non-zero exit on a crafted store line"
stripped=$(printf '%s' "$rout" | tr -d '\000-\037\177')
[ "$stripped" = "$rout" ] || fail "render leaked control/escape bytes to stdout (terminal injection)"
echo "ok: render strips control/escape bytes from stored fields (no terminal injection)"

# ---------------------------------------------------------------------------
# 12. Concurrency: N concurrent heartbeats for DISTINCT workers are serialized
#     through the Task 9 lock → exactly N rows, none torn, none lost. And N
#     concurrent upserts of the SAME worker collapse to exactly one row.
# ---------------------------------------------------------------------------
home12="$tmp/race-home"
N=20
pids=""
i=0
while [ "$i" -lt "$N" ]; do
  aenv "$home12" heartbeat "worker=r$i" "spec-r:$i" working &
  pids="$pids $!"
  i=$((i + 1))
done
rc=0
for p in $pids; do wait "$p" || rc=1; done
[ "$rc" = 0 ] || fail "heartbeat race: a concurrent heartbeat exited non-zero under contention"
rows=$(wc -l <"$home12/attention/state" | tr -d ' ')
[ "$rows" = "$N" ] || fail "heartbeat race: $rows rows, expected $N (lost or torn writes)"
malformed=$(awk -F"$tab" 'NF != 8 { c++ } END { print c + 0 }' "$home12/attention/state")
[ "$malformed" = 0 ] || fail "heartbeat race: $malformed torn/malformed rows (expected 8 tab-fields each)"
distinct=$(cut -f1 "$home12/attention/state" | sort -u | wc -l | tr -d ' ')
[ "$distinct" = "$N" ] || fail "heartbeat race: $distinct distinct workers, expected $N"

home12b="$tmp/race-same-home"
pids=""
i=0
while [ "$i" -lt "$N" ]; do
  aenv "$home12b" heartbeat "worker=same" "spec-r:$i" working &
  pids="$pids $!"
  i=$((i + 1))
done
rc=0
for p in $pids; do wait "$p" || rc=1; done
[ "$rc" = 0 ] || fail "same-worker race: a concurrent upsert exited non-zero"
rows=$(wc -l <"$home12b/attention/state" | tr -d ' ')
[ "$rows" = 1 ] || fail "same-worker race: $rows rows for one worker, expected exactly 1 (upsert must dedup)"
echo "ok: concurrent heartbeats are serialized (distinct → N rows; same worker → one row)"

# ---------------------------------------------------------------------------
# 13. The notification seam. `none` (the default channel) is a silent no-op —
#     pull-only, nothing pushed, no toast artifact. `editor-toast` drops a
#     sanitized line to the toasts file, stripped of control/escape bytes.
# ---------------------------------------------------------------------------
# 13a. Default channel resolves to `none` from the shipped core defaults (no
#      overlay pins) → notify is a silent no-op and creates no toast file.
home13="$tmp/notify-none-home"
nout=$(aenv "$home13" notify "worker=w spec-a:3 needs a decision" 2>/dev/null) \
  || fail "notify (none): non-zero exit"
[ -z "$nout" ] || fail "notify (none): wrote to stdout ('$nout'), expected a silent no-op"
[ ! -e "$home13/attention/toasts" ] || fail "notify (none): created a toast artifact (should be pull-only)"
echo "ok: the notification seam is a silent no-op on the pull-only default channel"

# 13b. editor-toast (pinned through the machine-local config layer) drops a
#      sanitized line; an embedded escape sequence is stripped before the file.
home13b="$tmp/notify-toast-home"
core_cfg="$tmp/notify-core.yml"
pin_cfg="$tmp/notify-pin.yml"
printf 'notification_channel: none\n' >"$core_cfg"
printf 'notification_channel: editor-toast\n' >"$pin_cfg"
scratch_repo="$tmp/notify-scratch-repo"
mkdir -p "$scratch_repo"
notify_toast() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY \
    PLANWRIGHT_FLEET_STATE_DIR="$home13b" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_REPO_ROOT="$scratch_repo" \
    PLANWRIGHT_LOCAL_CONFIG="$pin_cfg" \
    /bin/sh "$FA" notify "$1"
}
inj_summary=$(printf 'alpha\033]0;X\007 needs input')
notify_toast "$inj_summary" || fail "notify (editor-toast): non-zero exit"
[ -f "$home13b/attention/toasts" ] || fail "notify (editor-toast): no toast file written"
# The line is `<ts>\t<summary>`; check the SUMMARY field for control bytes (the
# tab is the legitimate field separator, not injection). cut -f2- is safe
# because the summary is sanitized to a single control-free field before write.
toast_summary=$(cut -f2- "$home13b/attention/toasts")
case $toast_summary in *"alpha"*) ;; *) fail "notify (editor-toast): summary text not written" ;; esac
stripped=$(printf '%s' "$toast_summary" | tr -d '\000-\037\177')
[ "$stripped" = "$toast_summary" ] || fail "notify (editor-toast): control/escape bytes reached the toast file"
echo "ok: the notification seam drops a sanitized editor-toast line on the editor-toast channel"

# ---------------------------------------------------------------------------
# 14. Empty-state reads are clean: render on an untouched home exits 0 with no
#     rows; queue --count is 0.
# ---------------------------------------------------------------------------
home14="$tmp/empty-home"
aenv "$home14" render >/dev/null 2>&1 || fail "render on an empty home did not exit 0"
c=$(aenv "$home14" queue --count) || fail "queue --count on an empty home non-zero exit"
[ "$c" = 0 ] || fail "queue --count on an empty home is '$c', expected 0"
echo "ok: reads on an empty home are clean (render exits 0, queue count is 0)"

# ---------------------------------------------------------------------------
# 15. Numeric-handle upsert/clear must compare worker keys as STRINGS, not
#     numerically. valid_field admits all-numeric handles; a numeric awk
#     comparison (`$1 != w`) treats `100` == `1e2` and `1` == `01` == `1.0` as
#     equal, so upserting/clearing one worker would silently destroy another's
#     row (data loss). Regression for the awk strnum trap.
# ---------------------------------------------------------------------------
home15="$tmp/numeric-home"
aenv "$home15" heartbeat "1e2" "spec-n:1" working || fail "numeric: heartbeat 1e2"
aenv "$home15" heartbeat "100" "spec-n:2" working || fail "numeric: heartbeat 100 (upsert must not wipe 1e2)"
r15=$(aenv "$home15" render 2>/dev/null) || fail "numeric: render"
printf '%s\n' "$r15" | grep -qE '(^| )1e2( |$)' \
  || fail "numeric upsert of '100' destroyed worker '1e2' (awk numeric-equated them)"
printf '%s\n' "$r15" | grep -qE '(^| )100( |$)' || fail "numeric: worker '100' not recorded"
# clear must also be string-keyed: clearing '1' must not remove '01' or '1.0'.
home15b="$tmp/numeric-clear-home"
aenv "$home15b" heartbeat "1" "spec-n:1" working || fail "numeric-clear: heartbeat 1"
aenv "$home15b" heartbeat "01" "spec-n:2" working || fail "numeric-clear: heartbeat 01"
aenv "$home15b" heartbeat "1.0" "spec-n:3" working || fail "numeric-clear: heartbeat 1.0"
aenv "$home15b" clear "1" || fail "numeric-clear: clear 1"
rows=$(wc -l <"$home15b/attention/state" | tr -d ' ')
[ "$rows" = 2 ] || fail "numeric clear of '1' also removed '01'/'1.0' ($rows rows left, expected 2)"
echo "ok: worker-key comparison is string-based (numeric-looking handles never collide)"

# ---------------------------------------------------------------------------
# 16. The heartbeat timestamp is stamped UNDER the lock (commit time), not at
#     invocation. Deterministic proof, mirroring test-fleet-state.sh: hold the
#     lock, launch a heartbeat that blocks on it, advance the wall clock past a
#     1s boundary, then release. A commit-time stamp is >= the release time; an
#     invocation-time stamp (captured before the block) would predate it.
# ---------------------------------------------------------------------------
home16="$tmp/ts-home"
mkdir -p "$home16"
mkdir "$home16/.fleet.lock" # hold the Task 9 lock so the heartbeat must block
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home16" \
  /bin/sh "$FA" heartbeat "worker=late" "spec-t:1" working &
hb_pid=$!
sleep 2 # advance the clock while the heartbeat is blocked on the held lock
t_release=$(date +%s)
rmdir "$home16/.fleet.lock" # release; the heartbeat now acquires and stamps
wait "$hb_pid" || fail "blocked heartbeat did not complete after lock release"
rec_ts=$(cut -f4 "$home16/attention/state")
case $rec_ts in
  "" | *[!0-9]*) fail "heartbeat timestamp '$rec_ts' is not numeric" ;;
esac
[ "$rec_ts" -ge "$t_release" ] \
  || fail "heartbeat timestamp ($rec_ts) predates lock release ($t_release): stamped at invocation, not under the lock"
echo "ok: the heartbeat timestamp is stamped under the lock (commit time, monotonic)"

# ---------------------------------------------------------------------------
# 17. Notification-adapter injection defenses (the security-relevant channels).
#     Stub the platform tools on PATH so the dispatch is exercised hermetically:
#     tmux-popup must strip '#' (neutralizing tmux #(cmd)/#{...} FORMAT execution)
#     and os-notify must pass the summary as ARGV data (no script-string
#     interpolation). Each stub records exactly the argv it received.
# ---------------------------------------------------------------------------
inj_dir="$tmp/notify-inj"
stub_bin="$inj_dir/bin"
mkdir -p "$stub_bin"
home17="$tmp/notify-inj-home"
core_cfg17="$tmp/notify-inj-core.yml"
scratch_repo17="$tmp/notify-inj-repo"
mkdir -p "$scratch_repo17"
printf 'notification_channel: none\n' >"$core_cfg17"

# A fake `tmux` that appends every arg (one per line) to a capture file.
cat >"$stub_bin/tmux" <<EOF
#!/bin/sh
for a in "\$@"; do printf '%s\n' "\$a" >>"$inj_dir/tmux-args"; done
exit 0
EOF
# A fake `notify-send` doing the same, so os-notify picks the Linux branch
# deterministically (checked before osascript in the adapter).
cat >"$stub_bin/notify-send" <<EOF
#!/bin/sh
for a in "\$@"; do printf '%s\n' "\$a" >>"$inj_dir/notify-args"; done
exit 0
EOF
chmod +x "$stub_bin/tmux" "$stub_bin/notify-send"

notify_inj() { # <channel> <summary>
  _pin="$tmp/notify-inj-pin-$1.yml"
  printf 'notification_channel: %s\n' "$1" >"$_pin"
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY \
    PATH="$stub_bin:$PATH" TMUX="fake-server" \
    PLANWRIGHT_FLEET_STATE_DIR="$home17" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg17" \
    PLANWRIGHT_REPO_ROOT="$scratch_repo17" \
    PLANWRIGHT_LOCAL_CONFIG="$_pin" \
    /bin/sh "$FA" notify "$2"
}

# tmux-popup: a summary that WOULD run a shell command if tmux interpreted its
# format (`#(touch pwned)`). The adapter must strip every '#', so the stub sees
# no '#' and the pwned marker is never created.
notify_inj tmux-popup 'alert #(touch '"$inj_dir"'/pwned) #{q:x}' || fail "notify tmux-popup: non-zero exit"
[ ! -e "$inj_dir/pwned" ] || fail "tmux-popup: '#(cmd)' was not neutralized (format execution)"
[ -f "$inj_dir/tmux-args" ] || fail "tmux-popup: stub tmux was not invoked"
grep -q '#' "$inj_dir/tmux-args" && fail "tmux-popup: a '#' reached tmux (format-injection vector intact)"
grep -q 'alert' "$inj_dir/tmux-args" || fail "tmux-popup: the summary text did not reach tmux"

# os-notify: the summary is passed as a single argv token after `--`, verbatim
# (control bytes already stripped upstream), never interpolated into a script.
notify_inj os-notify 'deploy done; rm -rf /' || fail "notify os-notify: non-zero exit"
[ -f "$inj_dir/notify-args" ] || fail "os-notify: stub notify-send was not invoked"
grep -qx -- '--' "$inj_dir/notify-args" || fail "os-notify: summary not passed after an end-of-options '--'"
grep -qx 'deploy done; rm -rf /' "$inj_dir/notify-args" \
  || fail "os-notify: summary not passed verbatim as a single argv token (injection-safe)"
echo "ok: notify adapters neutralize tmux format injection and pass os-notify summaries as argv data"

echo "ALL PASS: fleet-attention.sh"
