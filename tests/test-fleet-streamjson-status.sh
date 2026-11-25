#!/bin/bash
# Tests for scripts/fleet-streamjson.sh: launch election, result frames, the
# launch preflight, the escalation tick, and the status verdicts (REQ-B1.3 and
# REQ-E1.5).
#   - obs:917e384e: `launch` elects a single initiator under real contention.
#   - a result frame claiming success while carrying is_error is read as an
#     error, and an unterminated result snapshot is not read.
#   - `launch` refuses a symlinked state directory; an unreadable receipt
#     journal leaves the attention class held; a live worker this user cannot
#     signal is not treated as an orphan; a supervisor that cannot publish
#     worker.pid closes its worker.
#   - the launch preflight proves the auto-approve hook approves the opening
#     plugin-script call; the escalation tick escalates an overdue receipt and
#     refuses a malformed argv or a foreign supervisor.
#   - the status verdict's shapes, from fabricated state, and a pending request
#     outranking an earlier turn's result while the worker lives.
#   - obs:1eb24a7e: one stuck lock cannot cascade into the other, and a
#     spooled receipt is journaled, deferred, discarded or set aside by the
#     rule that governs it.
#
# Companions: tests/test-fleet-streamjson.sh and
# tests/test-fleet-streamjson-delivery.sh.
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/fleet-streamjson-fixture.sh
. "$here/lib/fleet-streamjson-fixture.sh" || exit 1

# ---------------------------------------------------------------------------
# c25 (obs:917e384e): `launch` elects a single initiator, so two concurrent
#    launches for one worker leave exactly one supervisor and one pid file.
# ---------------------------------------------------------------------------
home="$tmp/h25"
rec="$tmp/r25"
mkdir -p "$rec"
printf 'one initiator\n' >"$tmp/prompt25"
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 -- \
  launch sjw25 execution-backends:4 --prompt-file "$tmp/prompt25" \
  >/dev/null || fail "c25: the first launch exited non-zero"
wdir25="$home/streamjson/sjw25"
poll_until --what 'the supervisor pid' -- test -s "$wdir25/supervisor.pid" || fail "c25: supervisor.pid never appeared"
sup25=$(cat "$wdir25/supervisor.pid")
# (a) a launch arriving while this worker's supervisor is up is refused, so a
#     second supervisor never overwrites the first one's pid file.
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 -- \
  launch sjw25 execution-backends:4 --prompt-file "$tmp/prompt25" >"$tmp/o25a" 2>&1
[ $? -eq 3 ] || fail "c25a: a launch over a live supervisor must be refused (exit 3)"
grep -q "already running" "$tmp/o25a" \
  || fail "c25a: the refusal must be the live-supervisor one, got: $(cat "$tmp/o25a")"
[ "$(cat "$wdir25/supervisor.pid")" = "$sup25" ] \
  || fail "c25a: the refused launch must not have replaced the supervisor pid file"
snap25=$(ps_rows)
n25=$(printf '%s\n' "$snap25" | grep -Fc -- "_supervise sjw25 $wdir25")
[ "$n25" = 1 ] || fail "c25a: exactly one supervisor expected for the worker, found $n25"
senv "$home" "$rec" -- stop sjw25 --grace 2 >/dev/null || fail "c25: stop exited non-zero"
# (b) the election itself, under genuine contention: several launches start at
#     once with no supervisor up, so the primitive's atomic create is what
#     decides. Exactly one may win, and the losers must refuse rather than race
#     into `supervise`.
#
# Asserted unconditionally. This case used to probe the host's `mkdir` first
# and skip itself where several concurrent creators of one path all came back
# happy (uutils coreutils 0.8.0, the /usr/bin/mkdir on some images) — which
# left the election untested on exactly the hosts most likely to break it. The
# lock is one `ln -s` now, and a create-or-fail symlink has no such flavor, so
# there is nothing left to excuse the case from running.
c25b_ran=1
for n in 1 2 3; do
  senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 -- \
    launch sjw25 execution-backends:4 --prompt-file "$tmp/prompt25" \
    >"$tmp/o25b.$n" 2>&1 &
done
wait
won=0
lost=0
for n in 1 2 3; do
  if grep -q "^launched sjw25 " "$tmp/o25b.$n"; then
    won=$((won + 1))
  elif grep -qE "already in flight|already running" "$tmp/o25b.$n"; then
    # How a loser lost is the point: a crash and a single-initiator refusal
    # both leave one winner, and only one of them is the election working.
    lost=$((lost + 1))
  fi
done
if [ "$won" != 1 ] || [ "$lost" != 2 ]; then
  for n in 1 2 3; do
    printf 'c25b launch %s said: %s\n' "$n" "$(cat "$tmp/o25b.$n")" >&2
  done
  fail "c25b: expected one winner and two refusals, got $won and $lost"
fi
snap25=$(ps_rows)
n25=$(printf '%s\n' "$snap25" | grep -Fc -- "_supervise sjw25 $wdir25")
[ "$n25" = 1 ] || fail "c25b: exactly one supervisor expected after the race, found $n25"
# "one supervisor AND one pid file": the criterion is not met if a loser
# overwrote the winner's pid file on its way out.
sup25b=$(cat "$wdir25/supervisor.pid" 2>/dev/null) || sup25b=''
[ -n "$sup25b" ] || fail "c25b: no supervisor pid file survived the race"
printf '%s\n' "$snap25" \
  | awk -v p="$sup25b" -v m="_supervise sjw25 $wdir25" \
    '$1 == p && index($0, m) { f = 1 } END { exit f ? 0 : 1 }' \
  || fail "c25b: supervisor.pid ($sup25b) does not name the surviving supervisor"
senv "$home" "$rec" -- stop sjw25 --grace 2 >/dev/null || fail "c25b: stop exited non-zero"
# (c) a lock whose holder's process is gone is broken, so one hard kill cannot
#     wedge `launch` the way it used to wedge `recover`; a lock whose holder is
#     this very shell is not.
# The path is asserted clear before planting: a lock the preceding launch
# leaked would otherwise be adopted silently and the leg would test nothing.
{ [ ! -L "$wdir25/launch.lock" ] && [ ! -e "$wdir25/launch.lock" ]; } \
  || fail "c25c: the preceding launch leaked its lock"
plant_lock "$wdir25/launch.lock" $$
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 -- \
  launch sjw25 execution-backends:4 --prompt-file "$tmp/prompt25" >/dev/null 2>&1
[ $? -eq 3 ] || fail "c25c: a launch whose holder is alive must refuse the second caller (exit 3)"
plant_lock "$wdir25/launch.lock" "$dead_pid"
senv "$home" "$rec" SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 -- \
  launch sjw25 execution-backends:4 --prompt-file "$tmp/prompt25" >/dev/null \
  || fail "c25c: a lock whose holder is gone must be broken and the launch proceed"
senv "$home" "$rec" -- stop sjw25 --grace 2 >/dev/null || fail "c25c: stop exited non-zero"
# (d) the pid files are published by rename, never by a bare redirect. A
#     redirect creates the file before the write lands, and every reader treats
#     an empty pid file as nothing-recorded — which is what let a second launch
#     call a live worker dead and start a supervisor over it, and would let
#     `recover` resume a session that is still running. The window is too
#     narrow to hit on demand, so the mechanism is what gets pinned.
#     The helper's own body is audited too, not just its call sites: an audit
#     that only checked `supervise` would still pass if `write_pidfile` were
#     reverted to a bare redirect, which is exactly the defect being pinned.
audit=$(awk '/^supervise\(\)/, /^}/' "$SJ")
[ -n "$audit" ] || fail "c25d: the supervisor body was not found for the audit"
for f in supervisor worker; do
  printf '%s\n' "$audit" | grep -qF "write_pidfile \"\$sv_dir/$f.pid\"" \
    || fail "c25d: $f.pid must be published through the atomic helper"
done
helper=$(awk '/^write_pidfile\(\)/, /^}/' "$SJ")
[ -n "$helper" ] || fail "c25d: write_pidfile was not found for the audit"
printf '%s\n' "$helper" | grep -q 'mv ' \
  || fail "c25d: write_pidfile must publish by rename"
# No redirect anywhere on the publication path may name the target itself,
# quoted or bare — both forms are the same defect.
printf '%s\n' "$audit" "$helper" | grep -qE '>[[:space:]]*"?[^ "|&;]*\.pid"?([[:space:]]|$)' \
  && fail "c25d: a pid file must not be published by a bare redirect"
# The helper writes its temp and renames it; if the temp were the target the
# rename would be a no-op and the window would be back.
printf '%s\n' "$helper" | grep -qE "mv[[:space:]]+(--[[:space:]]+)?\"[\$]wp_tmp\"[[:space:]]+\"[\$]1\"" \
  || fail "c25d: write_pidfile must rename its staging temp over the target"
if [ "$c25b_ran" = 1 ]; then
  echo "ok: c25 launch elects a single initiator under contention and breaks a dead holder's lock (obs:917e384e)"
else
  echo "ok: c25 launch refuses a second caller and breaks a dead holder's lock (contention leg skipped) (obs:917e384e)"
fi

# ---------------------------------------------------------------------------
# c26: a result frame may claim success and carry is_error at the same time.
#     An API error (a 529, say) arrives as ordinary assistant TEXT, so the turn
#     succeeds in protocol terms while the RUN failed: the frame reports
#     subtype "success" and is_error true together, on a worker that then exits
#     0 with nothing done. A reader that consults only the subtype calls that a
#     clean completion, frees the slot and moves on. The state must be `ended`,
#     and the detail must show BOTH halves, because the contradiction is the
#     diagnostic, and the cause the error text names.
# ---------------------------------------------------------------------------
home="$tmp/h26"
rec="$tmp/r26"
mkdir -p "$rec"
ev="$tmp/ev26"
line_result_err='{"type":"result","subtype":"success","is_error":true,"result":"API Error: 529 Overloaded","session_id":"'$sid'"}'
printf '%s\n%s\n' "$line_init" "$line_result_err" >"$ev"
printf 'overload me\n' >"$tmp/prompt26"
senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw26 execution-backends:4 --prompt-file "$tmp/prompt26" --foreground \
  >/dev/null 2>&1 || fail "c26: launch exited non-zero"
out=$(senv "$home" "$rec" -- status sjw26) || fail "c26: status exited non-zero"
case $out in
  "status sjw26 ended result=success/is_error=true/cause=api-error-529") : ;;
  *) fail "c26: a success subtype carrying is_error must render 'ended' and name both, got: $out" ;;
esac
# Pin the on-disk record too, not just the rendering. fleet-stuck-detector.sh
# parses this same file from its own suite against a hand-written fixture, so
# nothing else would catch the writer moving the flag or renaming its value —
# the two would simply stop agreeing about a worker, silently.
grep -q "^result${tab}success${tab}[0-9][0-9]*${tab}true${tab}cause=api-error-529$" "$home/streamjson/sjw26/result" \
  || fail "c26: the recorded result row is not <result subtype epoch is_error cause>: $(cat "$home/streamjson/sjw26/result")"
echo "ok: c26 a result frame claiming success while carrying is_error is reported ended, not completed"

# ---------------------------------------------------------------------------
# c27: the result file is truncated and rewritten in place, so a reader can
#      catch a snapshot the writer has not finished — a short write on a full
#      disk leaves one on disk outright. A prefix of an is_error record still
#      starts `result<TAB>` and still parses as subtype success, so a check
#      that stops at the leading field calls a dead run clean: the exact
#      direction this record exists to close. Completeness is the line
#      terminator the writers always emit, not the field count — a
#      newline-terminated two-field record is a shape fleet-status.sh already
#      renders completed, and rejecting it here would change a verdict this
#      block was never asked to touch.
# ---------------------------------------------------------------------------
home="$tmp/h27"
rec="$tmp/r27"
mkdir -p "$rec"

# verdict <case> <record-bytes> <required-verdict-word>
verdict() {
  v_name=$1
  v_bytes=$2
  v_want=$3
  mkdir -p "$home/streamjson/$v_name" || fail "c27/$v_name: cannot plant the dir"
  printf '%s' "$v_bytes" >"$home/streamjson/$v_name/result"
  v_out=$(senv "$home" "$rec" -- status "$v_name") \
    || fail "c27/$v_name: status exited non-zero"
  case $v_out in
    *" $v_want "*) : ;;
    *) fail "c27/$v_name: expected verdict $v_want, got: $v_out" ;;
  esac
}

# Unterminated: the verdict must be the liveness answer for a dir with no pids,
# not a fabricated one in either direction — `ended` would be as invented as
# `completed` here.
verdict sjw27a "result$tab" unknown
verdict sjw27b "result${tab}success$tab" unknown
verdict sjw27c "result${tab}success" unknown
verdict sjw27d "result${tab}success${tab}17887" unknown
verdict sjw27e "exit${tab}0" unknown
# Terminated: every shape a writer actually emits keeps its verdict.
verdict sjw27f "result${tab}success${tab}1700000000
" completed
verdict sjw27g "result${tab}success${tab}1700000000${tab}true
" ended
verdict sjw27h "exit${tab}0${tab}1700000000
" completed
verdict sjw27i "exit${tab}1${tab}1700000000
" ended
# fleet-status.sh consumes this surface and its suite pins a two-field record
# as completed; the terminator, not the field count, is what says the writer
# finished.
verdict sjw27j "result${tab}0
" completed
echo "ok: c27 an unterminated result snapshot is not read as a completion"

# ---------------------------------------------------------------------------
# c28 (REQ-B1.3): `launch` refuses a symlinked state directory. The handle
#     grammar blocks traversal tokens but not a symlink planted under the
#     fleet home, and launch creates fifos and pid files inside whatever it is
#     handed. The close verb already refused one; refusing it here is what
#     stops it being FOLLOWED at all.
# ---------------------------------------------------------------------------
home="$tmp/h28"
mkdir -p "$home/streamjson" "$tmp/outside28"
ln -s "$tmp/outside28" "$home/streamjson/sjw28"
printf 'x\n' >"$tmp/prompt28"
if senv "$home" "$tmp/r28" -- launch sjw28 spec-c28:1 --prompt-file "$tmp/prompt28" >/dev/null 2>&1; then
  fail "c28: launch accepted a symlinked state directory"
fi
[ "$(find "$tmp/outside28" -type f | wc -l | tr -d ' ')" = 0 ] \
  || fail "c28: launch wrote through the symlink into $tmp/outside28"
#     Control: the same launch against a real directory gets past this guard,
#     so the refusal above is the symlink and not the fixture.
rm -f "$home/streamjson/sjw28"
mkdir -p "$home/streamjson/sjw28"
senv "$home" "$tmp/r28" -- launch sjw28 spec-c28:1 --prompt-file "$tmp/prompt28" >/dev/null 2>&1
sjw28_rc=$?
[ "$sjw28_rc" != 2 ] \
  || fail "c28 control: a real state directory was refused too — the guard is not symlink-specific"
echo "ok: c28 launch refuses a symlinked state directory (REQ-B1.3)"

# ---------------------------------------------------------------------------
# c29 (REQ-E1.5): an UNREADABLE receipt journal leaves the attention class
#     HELD, so the close reports partial rather than clearing an attention row
#     whose receipts are all still pending. The close tells "no pending rows"
#     from "could not read" by awk's exit code, and busybox awk does not
#     separate those, so readability has to be checked rather than assumed.
# ---------------------------------------------------------------------------
home="$tmp/h29"
rec="$tmp/r29"
mkdir -p "$rec"
ev29="$tmp/ev29"
printf '%s\n%s\n%s\n' "$line_init" "$line_perm" "$line_result" >"$ev29"
printf 'unreadable journal\n' >"$tmp/prompt29"
senv "$home" "$rec" SHIM_EVENTS="$ev29" -- \
  launch sjw29 execution-backends:4 --prompt-file "$tmp/prompt29" --foreground \
  || fail "c29: foreground launch exited non-zero"
wdir29="$home/streamjson/sjw29"
[ -f "$wdir29/journal" ] || fail "c29: no journal to make unreadable"
chmod 000 "$wdir29/journal" || fail "c29: cannot make the journal unreadable"
if hermetic_access_denied r "$wdir29/journal"; then
  #   The hazard is BUSYBOX awk, which exits 1 for an unreadable operand where
  #   gnu/mawk exit 2. On a host with the latter the pre-existing exit-code
  #   arm already covers this, so a test run against the host's own awk passes
  #   whether or not the readability check exists — it proves nothing about
  #   the fix. Shim an awk with busybox's exit code so the case actually
  #   exercises the precondition it is about.
  mkdir -p "$tmp/bin29"
  real_awk=$(command -v awk) || fail "c29: no awk to delegate to"
  cat >"$tmp/bin29/awk" <<AWKSHIM
#!/bin/sh
# busybox-shaped: an unreadable operand exits 1, not 2.
for a in "\$@"; do
  case \$a in -*) continue ;; esac
  if [ -e "\$a" ] && [ ! -r "\$a" ]; then exit 1; fi
done
exec $real_awk "\$@"
AWKSHIM
  chmod +x "$tmp/bin29/awk"
  printf 'x\n' >"$tmp/probe29"
  chmod 000 "$tmp/probe29" # hermetic-exempt: runs only inside the journal's denial probe above, same user and mode
  PATH="$tmp/bin29:$PATH" awk '{ print }' "$tmp/probe29" >/dev/null 2>&1
  [ "$?" = 1 ] || fail "c29: the awk shim does not reproduce busybox's exit 1 — this case would prove nothing"
  chmod 644 "$tmp/probe29"
  out=$(PATH="$tmp/bin29:$PATH" senv "$home" "$rec" -- stop sjw29 --grace 2 2>&1)
  chmod 644 "$wdir29/journal" 2>/dev/null
  case $out in
    *"partial"*"held="*attention*) ;;
    *) fail "c29: an unreadable journal should hold the attention class, got: $out" ;;
  esac
  #   Control: with the journal readable the same close, same shimmed awk,
  #   releases attention — so the hold above is the unreadable journal and not
  #   the shim breaking the close outright.
  out=$(PATH="$tmp/bin29:$PATH" senv "$home" "$rec" -- stop sjw29 --grace 2 2>&1)
  case $out in
    *"held="*attention*) fail "c29 control: attention stayed held with a readable journal: $out" ;;
  esac
  echo "ok: c29 an unreadable receipt journal leaves the attention class held (REQ-E1.5)"
else
  chmod 644 "$wdir29/journal"
  echo "skip: c29 unreadable-journal injection: the running user still reads $wdir29/journal under mode 000"
fi

# ---------------------------------------------------------------------------
# c30 (REQ-E1.5): a live worker this user cannot SIGNAL is still a live
#     worker. `kill -0` answers "may I signal it", not "does it exist": on a
#     pid owned by another uid it fails with EPERM exactly as it does for a
#     pid that is gone. Read as death here, `recover` treats a running worker
#     as orphaned and resumes over it, forking the session its own comment
#     says must never fork.
#
#     pid 1 is the portable EPERM subject: it always exists and a non-root
#     user can never signal it.
# ---------------------------------------------------------------------------
if [ "$(id -u)" = 0 ]; then
  echo "skip: c30 needs a non-root user (root can signal pid 1, so there is no EPERM case)"
elif kill -0 1 2>/dev/null; then
  echo "skip: c30 this host lets us signal pid 1, so it offers no EPERM case"
else
  home="$tmp/h30"
  wdir30="$home/streamjson/sjw30"
  mkdir -p "$wdir30" "$tmp/r30"
  printf '1\n' >"$wdir30/worker.pid"
  printf '1\n' >"$wdir30/supervisor.pid"
  printf 'sess30\n' >"$wdir30/session"
  # Every launch persists its scope; the recovery exports it as the worker's.
  printf 'execution-backends:4\n' >"$wdir30/scope"
  out=$(senv "$home" "$tmp/r30" -- recover sjw30 2>&1)
  rc30=$?
  [ "$rc30" = 3 ] \
    || fail "c30: recover should refuse a live-but-unsignallable worker (exit 3), got $rc30: $out"
  case $out in
    *"still alive"*) ;;
    *) fail "c30: the refusal should say the worker is still alive, got: $out" ;;
  esac
  #   Control: the same call with a pid that is genuinely gone DOES treat the
  #   worker as orphaned, so the refusal above is the EPERM pid and not
  #   recover refusing everything.
  dead30=$(sh -c 'echo $$')
  while kill -0 "$dead30" 2>/dev/null; do dead30=$((dead30 + 1)); done
  printf '%s\n' "$dead30" >"$wdir30/worker.pid"
  printf '%s\n' "$dead30" >"$wdir30/supervisor.pid"
  out=$(senv "$home" "$tmp/r30" -- recover sjw30 2>&1)
  rc30=$?
  case $out in
    *"still alive"*) fail "c30 control: a dead pid was reported still alive: $out" ;;
  esac
  #   That control really resumes: a detached supervisor, its tick, and a shim
  #   blocked reading a stdin nothing will write. Close it here, or it outlives
  #   the suite and anything holding the runner's inherited fds. Only after a
  #   resume that succeeded: a failed one leaves the pid files naming the dead
  #   pid, which `stop` would signal unchecked once the host reuses it.
  [ "$rc30" = 0 ] || fail "c30 control: recover over a dead worker failed ($rc30): $out"
  senv "$home" "$tmp/r30" -- stop sjw30 --grace 2 >/dev/null 2>&1 \
    || fail "c30: closing the resumed control worker failed"
  echo "ok: c30 a live worker this user cannot signal is not treated as orphaned (REQ-E1.5)"
fi

# ---------------------------------------------------------------------------
# c31 (REQ-E1.5): a supervisor that cannot publish worker.pid CLOSES the
#     worker rather than running one nothing can find. `recover` decides a
#     worker is orphaned by reading these pid files, so a live worker with no
#     pid file published is invisible to that check and a resume would start a
#     second session over it. Its sibling supervisor.pid write is already
#     fatal; this one was not.
# ---------------------------------------------------------------------------
home="$tmp/h31"
wdir31="$home/streamjson/sjw31"
mkdir -p "$wdir31" "$tmp/r31"
#   Block only the worker.pid publish: a directory the publish cannot rename
#   into. supervisor.pid is written before this and still succeeds, so the
#   case exercises the second write and not a broken state directory.
mkdir -m 500 "$wdir31/worker.pid"
if ! hermetic_access_denied w "$wdir31/worker.pid"; then
  echo "skip: c31: the running user writes into a mode-500 directory"
else
  ev="$tmp/ev31"
  printf '%s\n%s\n' "$line_init" "$line_result" >"$ev"
  mkdir -p "$tmp/c31"
  printf 'p\n' >"$tmp/c31/prompt"
  #   Into a file, not a capture: a worker the failure left running would hold
  #   a capture pipe open and hang the case before the check below could name it.
  senv "$home" "$tmp/r31" SHIM_EVENTS="$ev" -- \
    launch sjw31 execution-backends:4 --prompt-file "$tmp/c31/prompt" --foreground >"$tmp/out31" 2>&1
  rc31=$?
  out=$(cat "$tmp/out31")
  chmod 700 "$wdir31/worker.pid" 2>/dev/null
  [ "$rc31" != 0 ] \
    || fail "c31: a launch that could not publish worker.pid reported success: $out"
  case $out in
    *worker.pid*) ;;
    *) fail "c31: the failure never named the pid file it could not publish: $out" ;;
  esac
  #   And nothing is left running behind that failure. The foreground launch
  #   supervises in-process and spawns no tick before this failure. Its worker
  #   blocks opening the stdin fifo until the supervisor opens the writing end,
  #   which this failure never reaches, so the worker still carries the
  #   launch's argv, naming this case's prompt directory. The shim's directory
  #   covers a worker that does get as far as exec; no earlier case leaves one
  #   running, so any match there is this one.
  for c31d in "$tmp/c31/" "$tmp/bin/"; do
    poll_until --what 'no fixture process left' -- fixture_none "$c31d" || {
      c31left=$(fixture_report "$c31d")
      fixture_reap "$c31d"
      fail "c31: a process survived a failed pid publish: $c31left"
    }
  done
  echo "ok: c31 a worker that cannot be recorded is closed, not left running (REQ-E1.5)"
fi

# ---------------------------------------------------------------------------
# c33: the LAUNCH PREFLIGHT. A worker's first move is a plugin-script call
#    under whichever root its skill resolves to; a launch whose wired hook
#    would not approve that call refuses (exit 9) instead of spawning a worker
#    that pends on it — the 2026-09-12 stall, where the hook trusted the
#    launcher's checkout and the skill called scripts under the marketplace
#    cache. The roots come from scripts/resolve-installed-roots.sh, the same
#    resolver the hook reads, so the proof and the trust cannot diverge.
# ---------------------------------------------------------------------------
home="$tmp/h33"
rec="$tmp/r33"
mkdir -p "$rec"
ev="$tmp/ev33"
printf '%s\n%s\n' "$line_init" "$line_result" >"$ev"
printf 'preflight\n' >"$tmp/prompt33"
cdir="$tmp/cdir33"
# An installed root the resolver names that the hook cannot approve a script
# under: it exists, but carries no scripts/ dir, so containment cannot resolve.
bad_root="$cdir/inst/planwright/0.99.0"
mkdir -p "$bad_root" "$cdir/plugins"
jq -n --arg p "$bad_root" \
  '{plugins: {"planwright@planwright": [{installPath: $p, version: "0.99.0"}]}}' \
  >"$cdir/plugins/installed_plugins.json"
: >"$rec/argv"
senv "$home" "$rec" "CLAUDE_DIR=$cdir" SHIM_EVENTS="$ev" -- \
  launch sjw33 execution-backends:4 --prompt-file "$tmp/prompt33" --foreground \
  >/dev/null 2>"$tmp/pf33.err"
[ $? -eq 9 ] || fail "c33: a root the hook does not approve must refuse the launch (exit 9), stderr: $(cat "$tmp/pf33.err")"
grep -q "$bad_root/scripts/resolve-rule-doc.sh" "$tmp/pf33.err" \
  || fail "c33: the refusal must name the root and the command it could not approve, got: $(cat "$tmp/pf33.err")"
! grep -q "does not approve '$(cd "$here/.." && pwd -P)/scripts/" "$tmp/pf33.err" \
  || fail "c33: only the bad root fails; the launcher's own root must pass the proof"
[ ! -s "$rec/argv" ] || fail "c33: a refused preflight must never spawn the worker"
[ ! -d "$home/streamjson/sjw33" ] || fail "c33: a refused preflight must leave no runtime dir behind"
# warn: the same failure is reported and the launch proceeds.
senv "$home" "$rec" "CLAUDE_DIR=$cdir" SHIM_EVENTS="$ev" \
  PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT=warn -- \
  launch sjw33w execution-backends:4 --prompt-file "$tmp/prompt33" --foreground \
  >/dev/null 2>"$tmp/pf33w.err" \
  || fail "c33: warn mode must launch, stderr: $(cat "$tmp/pf33w.err")"
grep -q "$bad_root/scripts/resolve-rule-doc.sh" "$tmp/pf33w.err" \
  || fail "c33: warn mode must still report the root it could not approve"
grep -q "continuing anyway" "$tmp/pf33w.err" || fail "c33: warn mode must say it is continuing"
[ -s "$rec/argv" ] || fail "c33: warn mode must spawn the worker"
# A well-formed installed root — the marketplace-cache shape a worker's skill
# actually resolves to — passes the proof with no env pointing at it: the hook
# trusts it through the resolver, exactly as the worker's calls will be.
good_root="$cdir/plugins/cache/mkt/planwright/0.98.0"
mkdir -p "$good_root/scripts"
: >"$good_root/scripts/resolve-rule-doc.sh"
jq -n --arg p "$good_root" \
  '{plugins: {"planwright@planwright": [{installPath: $p, version: "0.98.0"}]}}' \
  >"$cdir/plugins/installed_plugins.json"
: >"$rec/argv"
senv "$home" "$rec" "CLAUDE_DIR=$cdir" SHIM_EVENTS="$ev" -- \
  launch sjw33g execution-backends:4 --prompt-file "$tmp/prompt33" --foreground \
  >/dev/null 2>"$tmp/pf33g.err" \
  || fail "c33: an approvable installed root must launch, stderr: $(cat "$tmp/pf33g.err")"
# Silent from the preflight's side; the launch's own registration notes may
# still print (no tower identity in this harness).
! grep -q "launch preflight" "$tmp/pf33g.err" \
  || fail "c33: a passing preflight must be silent, got: $(cat "$tmp/pf33g.err")"
[ -s "$rec/argv" ] || fail "c33: the passing launch must spawn the worker"
# A launcher carrying a session record of its own that names no usable
# worktree: under it the guard trusts no checkout, but the worker never runs
# under it, so the proof runs with no record and an installed root that is a
# git checkout committing the script still passes.
git_root="$cdir/plugins/cache/mkt/planwright/0.97.0"
mkdir -p "$git_root/scripts"
: >"$git_root/scripts/resolve-rule-doc.sh"
if ! { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$git_root" \
  && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$git_root" add scripts \
  && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$git_root" -c user.name=f \
    -c user.email=f@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m root; }; then
  fail "c33: could not build the checkout root"
fi
jq -n --arg p "$git_root" \
  '{plugins: {"planwright@planwright": [{installPath: $p, version: "0.97.0"}]}}' \
  >"$cdir/plugins/installed_plugins.json"
: >"$rec/argv"
senv "$home" "$rec" "CLAUDE_DIR=$cdir" SHIM_EVENTS="$ev" \
  PLANWRIGHT_WORKER_SESSION_RECORD="$tmp/no-such.record" -- \
  launch sjw33r execution-backends:4 --prompt-file "$tmp/prompt33" --foreground \
  >/dev/null 2>"$tmp/pf33r.err" \
  || fail "c33: a launcher's own unusable record must not refuse a committed checkout root, stderr: $(cat "$tmp/pf33r.err")"
[ -s "$rec/argv" ] || fail "c33: the launch under the launcher's own record must spawn the worker"
jq -n --arg p "$good_root" \
  '{plugins: {"planwright@planwright": [{installPath: $p, version: "0.98.0"}]}}' \
  >"$cdir/plugins/installed_plugins.json"
# An unknown mode value is a usage error, never a silent skip.
senv "$home" "$rec" "CLAUDE_DIR=$cdir" SHIM_EVENTS="$ev" \
  PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT=maybe -- \
  launch sjw33m execution-backends:4 --prompt-file "$tmp/prompt33" --foreground \
  >/dev/null 2>&1
[ $? -eq 2 ] || fail "c33: an unknown preflight mode must be refused (exit 2)"
# off: the proof is skipped outright, a root the hook would refuse included.
jq -n --arg p "$bad_root" \
  '{plugins: {"planwright@planwright": [{installPath: $p, version: "0.99.0"}]}}' \
  >"$cdir/plugins/installed_plugins.json"
: >"$rec/argv"
senv "$home" "$rec" "CLAUDE_DIR=$cdir" SHIM_EVENTS="$ev" \
  PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT=off -- \
  launch sjw33o execution-backends:4 --prompt-file "$tmp/prompt33" --foreground \
  >/dev/null 2>"$tmp/pf33o.err" \
  || fail "c33: off mode must launch, stderr: $(cat "$tmp/pf33o.err")"
! grep -q "launch preflight" "$tmp/pf33o.err" || fail "c33: off mode must not run the proof"
[ -s "$rec/argv" ] || fail "c33: off mode must spawn the worker"
# The proof is of the hook the WORKER runs: the wrapper keeps a CLAUDE_PLUGIN_ROOT
# the launcher was started with, and the worker-settings hook resolves through
# that variable, so a launcher carrying another install's root must prove that
# install's guard (here: a root with no guard at all), not this checkout's copy.
preset="$cdir/preset-root"
mkdir -p "$preset"
: >"$rec/argv"
senv "$home" "$rec" "CLAUDE_DIR=$cdir" "CLAUDE_PLUGIN_ROOT=$preset" SHIM_EVENTS="$ev" -- \
  launch sjw33p execution-backends:4 --prompt-file "$tmp/prompt33" --foreground \
  >/dev/null 2>"$tmp/pf33p.err"
[ $? -eq 9 ] || fail "c33: a preset plugin root without the guard must refuse (exit 9), stderr: $(cat "$tmp/pf33p.err")"
grep -q "$preset/scripts/worker-command-guard.sh" "$tmp/pf33p.err" \
  || fail "c33: the refusal must name the guard under the worker's plugin root, got: $(cat "$tmp/pf33p.err")"
[ ! -s "$rec/argv" ] || fail "c33: a missing worker-side guard must never spawn the worker"
grep -q "$preset/scripts/background-job-guard.sh" "$tmp/pf33p.err" \
  || fail "c33: the missing background-job guard must be warned about before any refusal, got: $(cat "$tmp/pf33p.err")"
# A root carrying the command guard but no policy guard refuses too: the worker
# profile leaves merges and rewrites to that guard.
mkdir -p "$preset/scripts" "$preset/config"
cp "$here/../scripts/worker-command-guard.sh" "$preset/scripts/"
# Once it holds scripts/ the root is an arm of the core root chain, so the
# worker profile resolves under it too; give it one so the guard proof is what
# refuses.
cp "$here/../config/worker-settings.json" "$preset/config/"
: >"$rec/argv"
senv "$home" "$rec" "CLAUDE_DIR=$cdir" "CLAUDE_PLUGIN_ROOT=$preset" SHIM_EVENTS="$ev" -- \
  launch sjw33q execution-backends:4 --prompt-file "$tmp/prompt33" --foreground \
  >/dev/null 2>"$tmp/pf33q.err"
[ $? -eq 9 ] || fail "c33: a preset plugin root without the policy guard must refuse (exit 9), stderr: $(cat "$tmp/pf33q.err")"
grep -q "$preset/scripts/policy-guard.sh" "$tmp/pf33q.err" \
  || fail "c33: the refusal must name the policy guard under the worker's plugin root, got: $(cat "$tmp/pf33q.err")"
[ ! -s "$rec/argv" ] || fail "c33: a missing policy guard must never spawn the worker"
# A root without the background-job guard is warned about, whatever the proof
# goes on to decide: its workers stall on a backgrounded command.
cp "$here/../scripts/policy-guard.sh" "$preset/scripts/"
: >"$rec/argv"
senv "$home" "$rec" "CLAUDE_DIR=$cdir" "CLAUDE_PLUGIN_ROOT=$preset" SHIM_EVENTS="$ev" -- \
  launch sjw33b execution-backends:4 --prompt-file "$tmp/prompt33" --foreground \
  >/dev/null 2>"$tmp/pf33b.err"
grep -q "$preset/scripts/background-job-guard.sh" "$tmp/pf33b.err" \
  || fail "c33: a root without the background-job guard must be warned about, got: $(cat "$tmp/pf33b.err")"
# The proof's own failure is a refusal with a cause, never a pass: a record it
# cannot create exits 2 and says why. mktemp is made to fail outright, since
# macOS's falls back to /tmp when TMPDIR names no directory.
: >"$rec/argv"
mkdir -p "$tmp/nomktemp"
printf '#!/bin/sh\nexit 1\n' >"$tmp/nomktemp/mktemp"
chmod +x "$tmp/nomktemp/mktemp"
senv "$home" "$rec" "CLAUDE_DIR=$cdir" "PATH=$tmp/nomktemp:$PATH" SHIM_EVENTS="$ev" -- \
  launch sjw33t execution-backends:4 --prompt-file "$tmp/prompt33" --foreground \
  >/dev/null 2>"$tmp/pf33t.err"
[ $? -eq 2 ] || fail "c33: an unwritable proof record must refuse (exit 2), stderr: $(cat "$tmp/pf33t.err")"
grep -q "cannot create a temp file for the proof record" "$tmp/pf33t.err" \
  || fail "c33: the temp-file failure must be named, got: $(cat "$tmp/pf33t.err")"
[ ! -s "$rec/argv" ] || fail "c33: a proof that could not run must never spawn the worker"
echo "ok: c33 launch preflight proves the hook approves the opening plugin-script call per root, refuses (9) or warns otherwise (fleet-autonomy D-19)"

# ---------------------------------------------------------------------------
# c34: the ESCALATION TICK. A receipt pending past the threshold is escalated
#    by the supervisor itself, within a tick, with nothing else running
#    `alarm-scan` — and still never answered, never killed.
# ---------------------------------------------------------------------------
home="$tmp/h34"
rec="$tmp/r34"
mkdir -p "$rec"
ev="$tmp/ev34"
printf '%s\n%s\n' "$line_init" "$line_perm" >"$ev"
printf 'park me\n' >"$tmp/prompt34"
senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_WAIT_RESPONSE=1 SHIM_RESULT_LINE="$line_result" \
  PLANWRIGHT_STREAMJSON_PENDING_AGE=1 PLANWRIGHT_STREAMJSON_ALARM_TICK=1 -- \
  launch sjw34 execution-backends:4 --prompt-file "$tmp/prompt34" --foreground &
launch34=$!
wdir34="$home/streamjson/sjw34"
poll_until --what 'the journal row' -- grep -q "^$req_perm$tab" "$wdir34/journal" \
  || fail "c34: the pending journal row never appeared"
# The receipt queues its row at normal priority; the tick promotes it to
# high once the age passes the threshold. Bounded wait: 1s threshold + 1s
# tick, plus scheduling slack.
overdue34() { aenv "$home" queue | grep "sjw34" | grep -q '^- \[high\]'; }
poll_until --what 'the escalated receipt' -- overdue34 \
  || fail "c34: the supervisor tick never escalated the overdue receipt, queue: $(aenv "$home" queue)"
grep -q "^$req_perm$tab.*${tab}pending" "$wdir34/journal" \
  || fail "c34: escalation must not settle the request"
grep -q control_response "$rec/stdin" 2>/dev/null \
  && fail "c34: escalation must never auto-answer"
out=$(senv "$home" "$rec" -- status sjw34) || fail "c34: status exited non-zero"
case $out in
  "status sjw34 awaiting-input pending=1 "*) : ;;
  *) fail "c34: an escalated worker is still awaiting-input, got: $out" ;;
esac
# The worker is untouched: answering still completes the run.
senv "$home" "$rec" -- answer sjw34 "$req_perm" --allow >/dev/null \
  || fail "c34: answer after escalation exited non-zero"
wait "$launch34" || fail "c34: the run did not end cleanly after the answer"
[ "$(aenv "$home" queue --count)" = 0 ] \
  || fail "c34: the queue should clear once the escalated request settles"
echo "ok: c34 the supervisor escalates an overdue receipt within a tick; escalation only (REQ-E1.1)"

# ---------------------------------------------------------------------------
# c35: the status verdict's shapes, from fabricated state. A live worker with
#    no pending row is `running`; with a pending row whose epoch is unreadable
#    it is still `awaiting-input` (age unknown), never back to `running`; a
#    dead supervisor with pending rows is neither.
# ---------------------------------------------------------------------------
home="$tmp/h35"
w35="$home/streamjson/sjw35"
mkdir -p "$w35"
printf '%s\n' "$$" >"$w35/supervisor.pid"
printf '%s\n' "$$" >"$w35/worker.pid"
out=$(senv "$home" "$tmp/r35" -- status sjw35) || fail "c35: status exited non-zero"
case $out in
  "status sjw35 running supervisor=$$ worker=$$") : ;;
  *) fail "c35: a live worker with no journal must read running, got: $out" ;;
esac
printf 'req-a\tpermission\t100\tanswered\t200\n' >"$w35/journal"
out=$(senv "$home" "$tmp/r35" -- status sjw35) || fail "c35: status exited non-zero"
case $out in
  "status sjw35 running "*) : ;;
  *) fail "c35: a live worker with only settled rows must read running, got: $out" ;;
esac
printf 'req-b\tpermission\tnot-an-epoch\tpending\t\n' >>"$w35/journal"
out=$(senv "$home" "$tmp/r35" -- status sjw35) || fail "c35: status exited non-zero"
case $out in
  "status sjw35 awaiting-input pending=1 oldest=unknown supervisor=$$ worker=$$") : ;;
  *) fail "c35: a pending row with an unreadable epoch must still read awaiting-input, got: $out" ;;
esac
printf 'req-c\tpermission\t100\tpending\t\n' >>"$w35/journal"
out=$(senv "$home" "$tmp/r35" -- status sjw35) || fail "c35: status exited non-zero"
case $out in
  "status sjw35 awaiting-input pending=2 oldest="[0-9]*"s supervisor=$$ worker=$$") : ;;
  *) fail "c35: the count covers every pending row and the age the readable ones, got: $out" ;;
esac
dead35=$(dead_owner_pid) || fail "c35: no PID is free to stand for a dead supervisor"
printf '%s\n' "$dead35" >"$w35/supervisor.pid"
out=$(senv "$home" "$tmp/r35" -- status sjw35) || :
case $out in
  "status sjw35 awaiting-input"* | "status sjw35 running"*) fail "c35: a dead supervisor must never read live, got: $out" ;;
  "status sjw35 "*) : ;;
  *) fail "c35: unexpected status shape: $out" ;;
esac
echo "ok: c35 status reads running only with no pending row, awaiting-input on any pending row, and never live for a dead supervisor"

# ---------------------------------------------------------------------------
# c36: the escalation tick's own ingress. Internal, but reachable, so a bad
#    argv is a refusal with a cause, and the directory must be the worker's own.
# ---------------------------------------------------------------------------
home="$tmp/h36"
w36="$home/streamjson/sjw36"
mkdir -p "$w36" "$tmp/elsewhere36"
senv "$home" "$tmp/r36" -- _tick sjw36 "$w36" >/dev/null 2>&1
[ $? -eq 2 ] || fail "c36: a short argv must be a usage error (exit 2)"
senv "$home" "$tmp/r36" -- _tick sjw36 "$tmp/elsewhere36" "$$" "$$" >/dev/null 2>"$tmp/tk36.err"
[ $? -eq 2 ] || fail "c36: a directory that is not the worker's own must be refused (exit 2)"
grep -q "is not the state directory of worker sjw36" "$tmp/tk36.err" \
  || fail "c36: the refusal must say which directory was rejected, got: $(cat "$tmp/tk36.err")"
senv "$home" "$tmp/r36" -- _tick sjw36 "$w36" nope "$$" >/dev/null 2>"$tmp/tk36b.err"
[ $? -eq 2 ] || fail "c36: a non-numeric pid must be refused (exit 2)"
grep -q "pids must be positive integers" "$tmp/tk36b.err" \
  || fail "c36: the pid refusal must be named, got: $(cat "$tmp/tk36b.err")"
echo "ok: c36 the tick refuses a malformed argv or a foreign directory, and says so"

# ---------------------------------------------------------------------------
# c38 (obs:1eb24a7e): one stuck lock cannot cascade into the other. A receipt
#    is journaled without the journal lock held across the attention store, so
#    a fleet lock nobody releases cannot turn into a journal outage; and a
#    receipt the journal lock refuses is deferred and journaled once the lock
#    frees, rather than lost until a stop and recover re-send it.
# ---------------------------------------------------------------------------
home="$tmp/h38"
rec="$tmp/r38"
mkdir -p "$rec" "$home"
ev="$tmp/ev38"
printf '%s\n%s\n' "$line_init" "$line_perm" >"$ev"
printf 'cascade\n' >"$tmp/prompt38"
# (a) The fleet lock held by a live process for the whole leg, so every
#     attention write spins on it. The receipt must land, and the journal lock
#     must be free again while that spin is still going.
#     The launch registers through that same lock, so it is planted only once
#     the supervisor is up, and the worker is held on a second stdin line
#     (a steer) so its request arrives after that.
senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_READ_FIRST=2 SHIM_WAIT_RESPONSE=1 \
  SHIM_RESULT_LINE="$line_result" -- \
  launch sjw38 execution-backends:4 --prompt-file "$tmp/prompt38" --foreground &
launch38=$!
wdir38="$home/streamjson/sjw38"
poll_until --what 'the supervisor pid' -- test -s "$wdir38/supervisor.pid" || fail "c38a: the supervisor never came up"
sleep 120 >/dev/null 2>&1 &
fl_holder=$!
ln -s "$fl_holder-$(date +%s)-1" "$home/.fleet.lock" || fail "c38: cannot plant the fleet lock"
printf 'go on\n' >"$tmp/steer38"
senv "$home" "$rec" -- steer sjw38 --message-file "$tmp/steer38" >/dev/null \
  || fail "c38a: the steer that releases the request failed"
poll_until --what 'the journal row' -- grep -q "^$req_perm$tab" "$wdir38/journal" \
  || fail "c38a: the receipt was not journaled while the fleet lock was held"
journal_free38() { [ ! -L "$wdir38/journal.lock" ] && [ ! -e "$wdir38/journal.lock" ]; }
# Shorter than the default on purpose: held across the attention call, the
# lock frees only when fleet-attention's lock spin gives up, which sleeps at
# least 20s (1000 tries of 0.02s) on any host, so the wait must end first.
poll_until --deadline 15 --what 'the journal lock free' -- journal_free38 \
  || fail "c38a: the journal lock is held across the attention call (it stays taken while the fleet lock is busy)"
[ -L "$home/.fleet.lock" ] || fail "c38a: the fleet lock was released early, so the leg proved nothing"
kill "$fl_holder" 2>/dev/null || :
wait "$fl_holder" 2>/dev/null || :
rm -f "$home/.fleet.lock"
senv "$home" "$rec" -- answer sjw38 "$req_perm" --allow >/dev/null \
  || fail "c38a: answer exited non-zero"
wait "$launch38" || fail "c38a: the run did not end cleanly after the answer"
echo "ok: c38 a receipt is journaled with the journal lock free of the attention call (obs:1eb24a7e)"
# (b) The journal lock held by a live process when the request arrives. The
#     receipt cannot be journaled then; it must be once the holder is gone,
#     with nothing restarted.
home="$tmp/h38b"
mkdir -p "$home/streamjson/sjw38b"
wdir38b="$home/streamjson/sjw38b"
sleep 120 >/dev/null 2>&1 &
jl_holder=$!
plant_lock "$wdir38b/journal.lock" "$jl_holder"
senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_WAIT_RESPONSE=1 SHIM_RESULT_LINE="$line_result" -- \
  launch sjw38b execution-backends:4 --prompt-file "$tmp/prompt38" --foreground &
launch38b=$!
# The supervisor waits out its journal-lock budget, then spools the receipt.
# Asserting the spool is what makes this leg exercise the deferral at all; the
# holder is released only after it, so what journals the receipt is the tick's
# drain, not the supervisor's own wait. That budget counts lock attempts, each
# of which forks, so on a loaded host it outlasts the default deadline.
poll_until --deadline 300 --what 'the spool' -- test -f "$wdir38b/deferred-$req_perm" \
  || fail "c38b: a receipt the journal lock refused was not spooled"
grep -q "^$req_perm$tab" "$wdir38b/journal" 2>/dev/null \
  && fail "c38b: the receipt was journaled through a lock a live process holds"
out=$(senv "$home" "$rec" -- status sjw38b) || fail "c38b: status exited non-zero"
case $out in
  "status sjw38b awaiting-input pending=1 "*) : ;;
  *) fail "c38b: a spooled receipt must read as awaiting input, got: $out" ;;
esac
kill "$jl_holder" 2>/dev/null || :
wait "$jl_holder" 2>/dev/null || :
poll_until --what 'the pending journal row' -- grep -q "^$req_perm$tab.*${tab}pending" "$wdir38b/journal" \
  || fail "c38b: a receipt the journal lock refused was lost instead of journaled once the lock freed"
poll_until --what 'the spool drained' -- test ! -e "$wdir38b/deferred-$req_perm" || fail "c38b: the spool outlived the journaled receipt"
senv "$home" "$rec" -- answer sjw38b "$req_perm" --allow >/dev/null \
  || fail "c38b: the deferred receipt is not answerable"
wait "$launch38b" || fail "c38b: the run did not end cleanly after the answer"
echo "ok: c38 a receipt the journal lock refused is deferred and journaled once it frees (obs:1eb24a7e)"
# (c) A close settles spooled receipts and the re-sync mark with the rest of
#     the attention class: left behind, a later session's tick would replay
#     them into a run that never asked.
printf '%s\n%s\n' 1000 "$line_q" >"$wdir38b/deferred-$req_q"
: >"$wdir38b/attention.dirty.999999999"
senv "$home" "$rec" -- stop sjw38b --grace 2 >/dev/null || fail "c38c: stop exited non-zero"
[ ! -e "$wdir38b/deferred-$req_q" ] || fail "c38c: a close left a spooled receipt behind"
[ ! -e "$wdir38b/attention.dirty.999999999" ] || fail "c38c: a close left the re-sync mark behind"
echo "ok: c38 a close discards spooled receipts and the re-sync mark"
# (d) A relaunch clears a journal lock left as a directory by the retired
#     shape once its recorded holder is gone; otherwise every receipt of the
#     new run would be spooled forever. One whose holder still runs is refused
#     and left standing.
home="$tmp/h38d"
mkdir -p "$home/streamjson/sjw38d/journal.lock"
wdir38d="$home/streamjson/sjw38d"
printf '%s\n' $$ >"$wdir38d/journal.lock/holder"
rc38d=0
senv "$home" "$rec" SHIM_EVENTS="$ev" -- \
  launch sjw38d execution-backends:4 --prompt-file "$tmp/prompt38" --foreground >/dev/null 2>&1 || rc38d=$?
[ "$rc38d" -eq 3 ] || fail "c38d: a launch over a legacy journal lock with a live holder must refuse with 3, got $rc38d"
[ -d "$wdir38d/journal.lock" ] || fail "c38d: a legacy journal lock directory with a live holder was removed"
printf '%s\n' "$dead_pid" >"$wdir38d/journal.lock/holder"
senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_WAIT_RESPONSE=1 SHIM_RESULT_LINE="$line_result" -- \
  launch sjw38d execution-backends:4 --prompt-file "$tmp/prompt38" --foreground &
launch38d=$!
poll_until --what 'the journal row' -- grep -q "^$req_perm$tab" "$wdir38d/journal" \
  || fail "c38d: a launch over a legacy journal lock directory never journaled its receipt"
senv "$home" "$rec" -- answer sjw38d "$req_perm" --allow >/dev/null \
  || fail "c38d: answer exited non-zero"
wait "$launch38d" || fail "c38d: the run did not end cleanly"
echo "ok: c38 a launch clears a retired-shape journal lock directory"
# (e) A spooled receipt for a request the journal already settled is the
#     resume re-ask, and draining it re-opens the request rather than dropping
#     it. The worker stays up after its answer so its tick does the drain.
home="$tmp/h38e"
wdir38e="$home/streamjson/sjw38e"
senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_WAIT_RESPONSE=1 SHIM_SLEEP=300 -- \
  launch sjw38e execution-backends:4 --prompt-file "$tmp/prompt38" &
poll_until --what 'the journal row' -- grep -q "^$req_perm$tab" "$wdir38e/journal" \
  || fail "c38e: the receipt was never journaled"
senv "$home" "$rec" -- answer sjw38e "$req_perm" --allow >/dev/null \
  || fail "c38e: answer exited non-zero"
grep -q "^$req_perm$tab.*${tab}answered" "$wdir38e/journal" || fail "c38e: the answer was not recorded"
# A duplicate received BEFORE the answer, spooled while the answer held the
# lock, is not a re-ask: drained, it is dropped and the request stays settled.
printf '%s\n%s\n' 1000 "$line_perm" >"$wdir38e/deferred-$req_perm"
poll_until --what 'the spool drained' -- test ! -e "$wdir38e/deferred-$req_perm" \
  || fail "c38e: the tick never drained the stale spool"
grep -q "^$req_perm$tab.*${tab}answered" "$wdir38e/journal" \
  || fail "c38e: a duplicate received before the answer re-opened the settled request"
sleep 1
printf '%s\n%s\n' "$(date +%s)" "$line_perm" >"$wdir38e/deferred-$req_perm"
poll_until --what 'the pending journal row' -- grep -q "^$req_perm$tab.*${tab}pending" "$wdir38e/journal" \
  || fail "c38e: a spooled re-ask of a settled request was dropped instead of re-opened"
# The spool goes only after the journal write it backs, so it is waited for.
poll_until --what 'the spool drained' -- test ! -e "$wdir38e/deferred-$req_perm" || fail "c38e: the drained spool was left behind"
senv "$home" "$rec" -- stop sjw38e --grace 2 >/dev/null || fail "c38e: stop exited non-zero"
echo "ok: c38 a spooled re-ask of a settled request is re-opened, not dropped"
# (f) A spool whose journal write fails is set aside once, not retried and
#     re-reported every beat; status still counts it, and a close removes it.
#     A read-only journal makes the append fail; root writes through that, so
#     the leg is skipped there.
home="$tmp/h38f"
wdir38f="$home/streamjson/sjw38f"
senv "$home" "$rec" SHIM_EVENTS="$ev" SHIM_WAIT_RESPONSE=1 SHIM_SLEEP=300 -- \
  launch sjw38f execution-backends:4 --prompt-file "$tmp/prompt38" &
poll_until --what 'the journal row' -- grep -q "^$req_perm$tab" "$wdir38f/journal" \
  || fail "c38f: the receipt was never journaled"
senv "$home" "$rec" -- answer sjw38f "$req_perm" --allow >/dev/null \
  || fail "c38f: answer exited non-zero"
chmod 444 "$wdir38f/journal"
if hermetic_access_denied w "$wdir38f/journal"; then
  printf '%s\n%s\n' "$(date +%s)" "$line_q" >"$wdir38f/deferred-$req_q"
  poll_until --what 'the set-aside spool' -- test -f "$wdir38f/undrained-$req_q" \
    || fail "c38f: a spool whose journal write failed was not set aside"
  [ ! -e "$wdir38f/deferred-$req_q" ] || fail "c38f: the failed spool was left where the drain retries it"
  out=$(senv "$home" "$rec" -- status sjw38f) || fail "c38f: status exited non-zero"
  case $out in
    "status sjw38f awaiting-input pending=1 "*) : ;;
    *) fail "c38f: a set-aside receipt must still read as awaiting input, got: $out" ;;
  esac
  chmod 644 "$wdir38f/journal"
  # Once the journal takes the same request, the set-aside copy is answered.
  printf '%s\n%s\n' "$(date +%s)" "$line_q" >"$wdir38f/deferred-$req_q"
  poll_until --what 'the pending journal row' -- grep -q "^$req_q$tab.*${tab}pending" "$wdir38f/journal" \
    || fail "c38f: the re-spooled receipt was not journaled once the journal was writable"
  # The drain removes the set-aside copy after the journal row lands, inside
  # the lock hold this lock-free read does not take, so it is waited for.
  poll_until --what 'the set-aside spool removed' -- test ! -e "$wdir38f/undrained-$req_q" \
    || fail "c38f: a set-aside receipt outlived its journaled request"
  : >"$wdir38f/undrained-$req_q"
  senv "$home" "$rec" -- stop sjw38f --grace 2 >/dev/null || fail "c38f: stop exited non-zero"
  [ ! -e "$wdir38f/undrained-$req_q" ] || fail "c38f: a close left the set-aside receipt behind"
  echo "ok: c38 a spool that cannot land is set aside once, counted, and removed by a close"
else
  chmod 644 "$wdir38f/journal"
  senv "$home" "$rec" -- stop sjw38f --grace 2 >/dev/null || fail "c38f: stop exited non-zero"
  echo "skip: c38f set-aside spool: the running user still writes $wdir38f/journal under mode 444"
fi
# ---------------------------------------------------------------------------
# c39: a turn result does not hide a later request. A persistent worker writes
#     `result` at the end of every turn and stays up; steered into a new turn
#     that raises a permission request, it is waiting on a human, so status
#     reads awaiting-input with the oldest request's age, not the earlier
#     turn's `completed`. Once the session is gone the result stands again.
# ---------------------------------------------------------------------------
home="$tmp/h39"
w39="$home/streamjson/sjw39"
mkdir -p "$w39"
printf '%s\n' "$$" >"$w39/supervisor.pid"
printf '%s\n' "$$" >"$w39/worker.pid"
now39=$(date +%s)
printf 'result\tsuccess\t%s\tfalse\n' "$((now39 - 600))" >"$w39/result"
out=$(senv "$home" "$tmp/r39" -- status sjw39) || fail "c39: status exited non-zero"
case $out in
  "status sjw39 completed result=success") : ;;
  *) fail "c39: a live worker idle after its turn with nothing pending reads completed, got: $out" ;;
esac
printf 'req-a\tpermission\t%s\tpending\t\n' "$((now39 - 120))" >"$w39/journal"
out=$(senv "$home" "$tmp/r39" -- status sjw39) || fail "c39: status exited non-zero"
case $out in
  "status sjw39 awaiting-input pending=1 oldest="*"s supervisor=$$ worker=$$") : ;;
  *) fail "c39: a request raised after the earlier turn's result must read awaiting-input, got: $out" ;;
esac
age39=${out#*oldest=}
age39=${age39%%s *}
[ "$age39" -ge 120 ] || fail "c39: oldest must be the request's age, got: $out"
dead39=$(dead_owner_pid) || fail "c39: no PID is free to stand for a dead supervisor"
printf '%s\n' "$dead39" >"$w39/supervisor.pid"
out=$(senv "$home" "$tmp/r39" -- status sjw39) || fail "c39: status exited non-zero"
case $out in
  "status sjw39 completed result=success") : ;;
  *) fail "c39: with the supervisor gone the recorded result stands, got: $out" ;;
esac
echo "ok: c39 a pending request outranks an earlier turn's result while the worker lives"

assert_nothing_left_running
echo "ok: c37 no supervisor, tick, or shim from this run outlives the suite"

echo "all fleet-streamjson status tests passed"
