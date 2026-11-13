#!/bin/bash
# Tests for scripts/mc-handover.sh's tmux paths: an attended holder inside
# tmux handing over in a pane beside it, and the Remote Control knob a tmux
# successor honours (mission-control REQ-L1.9, D-43). Split from
# tests/test-mc-handover.sh so each file fits the per-file test-time budget.
# The fixture is tests/lib/mc-handover-fixture.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }
tab=$(printf '\t')
suite=test-mc-handover-tmux

# shellcheck source=tests/lib/mc-handover-fixture.sh
. "$here/lib/mc-handover-fixture.sh"
# shellcheck source=tests/lib/emitter-lint.sh
. "$here/lib/emitter-lint.sh"

run mc-rules.sh add alpha --text "Never hand the operator a pane" --subject panes --source "operator, fixture" --date 2026-10-26
[ "$RC" = 0 ] || fail "fixture: the rule was not added: $ERR"
run mc-kb.sh init --program alpha
[ "$RC" = 0 ] || fail "fixture: the knowledge base was not initialised: $ERR"
run mc-rules.sh load alpha
digest=$(printf '%s\n' "$OUT" | sed -n 's/.*, digest \([0-9a-f]*\) -->.*/\1/p' | head -n 1)
[ "${#digest}" = 64 ] || fail "fixture: no rules digest from the load: $OUT"
printf '%s\n' "item q-1" "session mc-worker-1" >"$tmp/picture"
printf '%s\n' "item q-1" >"$tmp/picture-short"
: >"$tmp/empty"
mkdir -p "$fleet/mission-control/alpha/leases"

# ---------------------------------------------------------------------------
# REQ-L1.9, D-43: an attended holder inside tmux hands over itself, in a
# pane beside it; the successor closes exactly the recorded predecessor pane
# once the name has moved, never on a refused or failed take. A fake tmux
# answers for the panes listed in its panes file and logs what it is asked.
# ---------------------------------------------------------------------------
cat >"$tmp/bin/tmux" <<'FAKE'
#!/bin/sh
d=${FAKE_TMUX_DIR:?}
if [ "$1" = -S ]; then
  sock=$2
  shift 2
  printf 'sock %s: ' "$sock" >>"$d/tmux.log"
fi
printf '%s\n' "$*" >>"$d/tmux.log"
mkdir -p "$d/tmuxw"
case $1 in
  display-message)
    t=''
    for a in "$@"; do [ "$prev" = -t ] && t=$a; prev=$a; done
    case $t in
      %*) grep -qx -- "$t" "$d/tmux.panes" && printf '%s\n' "$t" && exit 0 ;;
      @*) if [ -e "$d/tmuxw/$t" ]; then
        case $* in *session_name*) echo stub ;; *) echo "$t" ;; esac
        exit 0
      fi ;;
    esac
    exit 1
    ;;
  new-window)
    n=$(cat "$d/tmuxw/next" 2>/dev/null || echo 1)
    echo $((n + 1)) >"$d/tmuxw/next"
    shift
    printf '%s\n' "$@" >"$d/tmuxw/argv-@$n"
    wname=''
    while [ "$#" -gt 0 ]; do
      [ "$1" = -n ] && wname=$2
      shift
    done
    printf '%s\n' "$wname" >"$d/tmuxw/@$n"
    echo "@$n"
    exit 0
    ;;
  list-windows)
    for w in "$d"/tmuxw/@*; do
      [ -f "$w" ] || continue
      case $* in *window_name*) printf '%s %s\n' "${w##*/}" "$(cat "$w")" ;; *) printf '%s\n' "${w##*/}" ;; esac
    done
    exit 0
    ;;
  kill-window)
    rm -f "$d/tmuxw/$3"
    exit 0
    ;;
  kill-pane)
    id=$3
    grep -vx -- "$id" "$d/tmux.panes" >"$d/tmux.panes.new"
    mv "$d/tmux.panes.new" "$d/tmux.panes"
    exit 0
    ;;
  has-session) exit 1 ;;
esac
exit 1
FAKE
chmod +x "$tmp/bin/tmux"
export FAKE_TMUX_DIR="$tmp"
printf '%s\n' '%7' '%9' '%3' >"$tmp/tmux.panes"
: >"$tmp/tmux.log"

fake_session
self_f=$FAKE
ho resume --program alpha --session op-f --pid "$self_f" --picture "$tmp/picture" --digest "$digest" --durable "$tmp/picture" --window 1s --exit-wait 2s
[ "$RC" = 0 ] || fail "fixture: the attended resume exited $RC: $OUT $ERR"
printf "%s\n" "$(date +%s)" >"$fleet/mission-control/alpha/leases/op-f"

RUN_TMUX_PANE='%7' ho path --program alpha
[ "$OUT" = "path${tab}pane${tab}tmux" ] && ok "an attended holder inside tmux gets the pane path" || fail "path in tmux: $OUT $ERR"
RUN_TMUX_PANE='%99' ho path --program alpha
[ "$(col path 2)" = operator-act ] && ok "a pane tmux does not know still gets the operator's act" || fail "path in an unknown pane: $OUT"
RUN_TMUX_PANE='7;rm' ho path --program alpha
[ "$(col path 2)" = operator-act ] && ok "a pane id outside the grammar gets the operator's act" || fail "path with a malformed pane: $OUT"

ho write --program alpha --session op-f --picture "$tmp/picture" --digest "$digest"
[ "$RC" = 0 ] || fail "fixture: the handover file was not written: $OUT $ERR"
led_f=$(col handover 3)
RUN_TMUX_PANE='%7' ho launch --program alpha --brief "$tmp/brief.md" --handover --backend stream-json
[ "$RC" = 0 ] || fail "fixture: the headless handover launch exited $RC: $OUT $ERR"
ns=$(col successor 2)
wait_done "$ns"
grep -q '^predecessor-pane' "$fleet/mission-control/alpha/successor" && ! grep -q "^predecessor-pane${tab}%" "$fleet/mission-control/alpha/successor" \
  && ok "a headless successor records no pane, so it can never close the operator's" || fail "the headless record: $(cat "$fleet/mission-control/alpha/successor")"
run mission-control-launch.sh retire "$ns"
rm -f "$fleet/mission-control/alpha/successor"

RUN_TMUX_PANE='%7' ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 0 ] && ok "a handover launch over an attended holder inside tmux is admitted, on the tmux rung" || fail "the pane handover launch exited $RC: $OUT $ERR"
nf=$(col successor 2)
grep -qx "predecessor-pane${tab}%7" "$fleet/mission-control/alpha/successor" \
  && grep -qx "predecessor-tmux${tab}$tmp/tmux.sock" "$fleet/mission-control/alpha/successor" \
  && ok "the predecessor's pane id and tmux socket are recorded" || fail "no recorded pane: $(cat "$fleet/mission-control/alpha/successor")"

RUN_TMUX_PANE='%9' ho take --program alpha --session "$nf" --window 1s --exit-wait 1s
[ "$RC" != 0 ] && ! grep -q kill-pane "$tmp/tmux.log" \
  && ok "a take before the self-check closes no pane" || fail "the unverified take: $RC $OUT $ERR $(cat "$tmp/tmux.log")"
RUN_TMUX_PANE='%9' ho take --program alpha --session mc-someone-else --window 1s --exit-wait 1s
[ "$RC" != 0 ] && ! grep -q kill-pane "$tmp/tmux.log" \
  && ok "a refused take (not the pending successor) closes no pane" || fail "the refused take: $RC $OUT $ERR"
holder_is "and the name stays put" op-f

ho verify --program alpha --session "$nf" --picture "$tmp/picture" --digest "$digest" --ledger "$led_f"
[ "$RC" = 0 ] || fail "fixture: the pane successor's verify exited $RC: $OUT $ERR"
grep -qx "predecessor-pane${tab}%7" "$fleet/mission-control/alpha/successor" \
  && ok "the verify keeps the recorded pane" || fail "verify dropped the pane: $(cat "$fleet/mission-control/alpha/successor")"
kill "$self_f" 2>/dev/null
RUN_TMUX_PANE='%9' ho take --program alpha --session "$nf" --window 1s --exit-wait 5s
[ "$RC" = 0 ] && [ "$(col pane 2)" = '%7' ] && [ "$(col pane 3)" = closed ] \
  && ok "the successful take reports the predecessor's pane closed" || fail "the pane take: $RC $OUT $ERR"
[ "$(grep -c kill-pane "$tmp/tmux.log")" = 1 ] && grep -qx "sock $tmp/tmux.sock: kill-pane -t %7" "$tmp/tmux.log" \
  && grep -qx '%9' "$tmp/tmux.panes" && grep -qx '%3' "$tmp/tmux.panes" \
  && ok "exactly the recorded pane was killed, no other" || fail "tmux log: $(cat "$tmp/tmux.log")"
holder_is "the name moved to the pane successor" "$nf"

# ---------------------------------------------------------------------------
# Remote Control: a tmux successor starts Remote Control when its predecessor
# was started with --remote-control (named, or bare, which takes the
# successor's own name); a predecessor with none, an unreadable one, or a
# name outside the grammar gives the successor none, and says why on stderr.
# Each predecessor is a process whose argv carries the flags it was given.
# ---------------------------------------------------------------------------
printf '%s\n' 'sleep 900 &' "trap 'kill \$! 2>/dev/null; exit 0' TERM INT" 'wait' >"$tmp/rcclaude"
printf '%s\n' '%11' '%12' '%13' '%14' '%15' '%16' '%17' >>"$tmp/tmux.panes"
rc_predecessor() {
  sh "$tmp/rcclaude" "$@" >/dev/null 2>&1 &
  RC_PID=$!
  fakes="$fakes $RC_PID"
}
rc_window_argv() {
  for w in "$tmp/tmuxw"/@*; do
    [ -f "$w" ] && [ "$(cat "$w")" = "$1" ] || continue
    cat "$tmp/tmuxw/argv-${w##*/}"
    return 0
  done
  return 1
}
rc_absent() { [ -n "$(rc_window_argv "$1")" ] && ! rc_window_argv "$1" | grep -qx -- '--remote-control'; }
rc_has_pair() { awk -v v="$2" 'prev == "--remote-control" && $0 == v { ok = 1 } { prev = $0 } END { exit !ok }' "$1"; }
# rc_cycle <predecessor session> <pane> — the predecessor is made holder by
# resume (RC_PID) or, when it is already the holder, written as is; a tmux
# handover launches its successor (RC_SUCC) and stderr is kept in RC_ERR.
rc_cycle() {
  rc_session=$1 rc_pane=$2
  ho resume --program alpha --session "$rc_session" --pid "$RC_PID" --picture "$tmp/picture" --digest "$digest" --durable "$tmp/picture" --window 1s --exit-wait 1s
  [ "$RC" = 0 ] || fail "fixture: resume as $rc_session exited $RC: $OUT $ERR"
  printf '%s\n' "$(date +%s)" >"$fleet/mission-control/alpha/leases/$rc_session"
  ho write --program alpha --session "$rc_session" --picture "$tmp/picture" --digest "$digest"
  [ "$RC" = 0 ] || fail "fixture: write as $rc_session exited $RC: $OUT $ERR"
  rc_led=$(col handover 3)
  RUN_TMUX_PANE="$rc_pane" ho launch --program alpha --brief "$tmp/brief.md" --handover --backend tmux
  RC_LAUNCH=$RC RC_ERR=$ERR RC_SUCC=$(col successor 2)
}
rc_settle() {
  ho verify --program alpha --session "$RC_SUCC" --picture "$tmp/picture" --digest "$digest" --ledger "$rc_led"
  [ "$RC" = 0 ] || fail "fixture: verify of $RC_SUCC exited $RC: $OUT $ERR"
  kill "$RC_PID" 2>/dev/null
  RUN_TMUX_PANE="$1" ho take --program alpha --session "$RC_SUCC" --window 1s --exit-wait 5s
  [ "$RC" = 0 ] || fail "fixture: take of $RC_SUCC exited $RC: $OUT $ERR"
}

# rc_knob <off|inherit|on|default>: the successor Remote Control knob, in the adopter layer.
rc_knob() {
  {
    touch "$adopter/planwright.yml"
    grep -v "^mission_control_successor_remote_control:" "$adopter/planwright.yml"
    [ "$1" = default ] || printf 'mission_control_successor_remote_control: %s\n' "$1"
  } >"$tmp/adopter.rc" \
    && cat "$tmp/adopter.rc" >"$adopter/planwright.yml"
}

# inherit: what follows reads the predecessor's own launch.
rc_knob inherit

# A predecessor with no readable process carries no Remote Control, and says so.
rc_predecessor
ho write --program alpha --session "$nf" --picture "$tmp/picture" --digest "$digest"
[ "$RC" = 0 ] || fail "fixture: write as the registry holder exited $RC: $OUT $ERR"
rc_led=$(col handover 3)
RUN_TMUX_PANE='%11' ho launch --program alpha --brief "$tmp/brief.md" --handover --backend tmux
[ "$RC" = 0 ] || fail "the unreadable-predecessor handover exited $RC: $OUT $ERR"
rc_u=$(col successor 2)
rc_window_argv "$rc_u" | rc_has_pair /dev/stdin "$rc_u" \
  && ok "a predecessor whose state cannot be read gives a successor Remote Control (it may have had it)" || fail "an unreadable predecessor's successor argv: $(rc_window_argv "$rc_u" | tr '\n' ' ')"
case $ERR in *'may have had'*) ok "and says so on stderr" ;; *) fail "no may-have-had note: $ERR" ;; esac
grep -qF 'may have had Remote Control' "$fleet/mission-control/launch/$rc_u/brief.md" \
  && ok "and the successor's brief says so" || fail "the unreadable-predecessor brief is silent about Remote Control"
RC_SUCC=$rc_u rc_settle '%11'
case $OUT in *'may have had Remote Control'*) ok "and the take line says so" ;; *) fail "the take line is silent about Remote Control: $OUT" ;; esac
RC_PID=''

# A named predecessor: the successor keeps its name.
rc_predecessor --remote-control mc-op-named -- hello
rc_cycle op-named '%12'
[ "$RC_LAUNCH" = 0 ] || fail "the named-predecessor handover exited $RC_LAUNCH: $RC_ERR"
rc_window_argv "$RC_SUCC" | rc_has_pair /dev/stdin mc-op-named \
  && ok "a successor of a named predecessor starts Remote Control under that name" || fail "named successor argv: $(rc_window_argv "$RC_SUCC" | tr '\n' ' ')"
rc_settle '%12'

# A bare predecessor: the successor is named as itself.
rc_predecessor --remote-control -- hello
rc_cycle op-bare '%13'
rc_window_argv "$RC_SUCC" | rc_has_pair /dev/stdin "$RC_SUCC" \
  && ok "a successor of a bare --remote-control predecessor is named as itself" || fail "bare successor argv: $(rc_window_argv "$RC_SUCC" | tr '\n' ' ')"
rc_settle '%13'

# A predecessor started without Remote Control: the successor has none.
rc_predecessor -- hello
rc_cycle op-plain '%14'
if rc_absent "$RC_SUCC"; then ok "a successor of a predecessor with no Remote Control starts none"; else fail "a successor of a predecessor with no Remote Control: $RC_SUCC"; fi
# Remote Control turned on in-session (no argv flag) is invisible to the argv
# read: the successor starts none, and the handover says so, never silently.
case $RC_ERR in *'/remote-control'*) ok "a no-flag predecessor's handover says Remote Control may have been turned on in-session" ;; *) fail "silent about in-session Remote Control: $RC_ERR" ;; esac
grep -qF '/remote-control' "$fleet/mission-control/launch/$RC_SUCC/brief.md" \
  && ok "and the successor's brief says how to turn it on" || fail "the no-flag brief is silent about Remote Control"
rc_settle '%14'
case $OUT in *'/remote-control'*) ok "and the take line says so" ;; *) fail "the no-flag take line is silent: $OUT" ;; esac

# A hostile name in the predecessor's argv is never passed on.
rc_predecessor --remote-control 'bad;name' -- hello
rc_cycle op-hostile '%15'
if rc_absent "$RC_SUCC"; then ok "a hostile predecessor name is not passed to the successor"; else fail "a successor took a hostile predecessor name"; fi
case $RC_ERR in *'not carried'*) ok "and the handover says why" ;; *) fail "no refusal note for the hostile name: $RC_ERR" ;; esac
rc_settle '%15'
rc_knob default
# The shipped default is off: even a predecessor with Remote Control gives
# its successor none, and nothing is said.
rc_predecessor --remote-control mc-op-default -- hello
rc_cycle op-default '%16'
[ "$RC_LAUNCH" = 0 ] || fail "the default-knob handover exited $RC_LAUNCH: $RC_ERR"
if rc_absent "$RC_SUCC"; then ok "with the knob at its default a successor starts without Remote Control"; else fail "the default knob started Remote Control: $RC_SUCC"; fi
case $RC_ERR in *'not carried'*) fail "the off knob spoke about Remote Control: $RC_ERR" ;; *) ok "and the off knob says nothing" ;; esac
rc_settle '%16'

# on: the successor always gets Remote Control, under its own name, whatever
# its predecessor had.
rc_knob on
rc_predecessor -- hello
rc_cycle op-on '%17'
[ "$RC_LAUNCH" = 0 ] || fail "the on-knob handover exited $RC_LAUNCH: $RC_ERR"
rc_window_argv "$RC_SUCC" | rc_has_pair /dev/stdin "$RC_SUCC" \
  && ok "with the knob on a successor starts Remote Control under its own name" || fail "on-knob successor argv: $(rc_window_argv "$RC_SUCC" | tr '\n' ' ')"
rc_settle '%17'

# A successor that took the name on the tmux rung holds it as a registry
# session, yet it runs in a tmux window: its own handover defaults to the tmux
# rung (so the Remote Control knob applies) and its path is the pane path. The
# holder here is the last settled successor, a registry holder on tmux.
rc_th=$RC_SUCC
holder_is "fixture: the holder is the tmux-rung registry successor" "$rc_th"
case $(col holder 3) in registry) ;; *) fail "fixture: the tmux successor is not a registry holder: $OUT" ;; esac
ho path --program alpha
[ "$OUT" = "path${tab}pane${tab}tmux" ] && ok "a registry holder on the tmux rung gets the pane path" || fail "path for a tmux-rung registry holder: $OUT $ERR"
rc_knob on
ho write --program alpha --session "$rc_th" --picture "$tmp/picture" --digest "$digest"
[ "$RC" = 0 ] || fail "fixture: write as the tmux-rung holder exited $RC: $OUT $ERR"
RUN_TMUX_PANE='%9' ho launch --program alpha --brief "$tmp/brief.md" --handover
th_rc=$RC th_err=$ERR th_succ=$(col successor 2)
[ "$th_rc" = 0 ] || fail "the tmux-rung registry handover exited $th_rc: $OUT $th_err"
rc_window_argv "$th_succ" | rc_has_pair /dev/stdin "$th_succ" \
  && ok "a handover from a tmux-rung registry holder, with no --backend, starts a tmux successor with Remote Control" \
  || fail "no tmux successor with Remote Control: $(rc_window_argv "$th_succ" | tr '\n' ' ') $th_err"
case $th_err in *'--remote-control is for the tmux rung'*) fail "the handover fell to the stream-json rung: $th_err" ;; *) ok "and never warns that Remote Control is for the tmux rung" ;; esac
grep -qx "predecessor-pane${tab}-" "$fleet/mission-control/alpha/successor" \
  && ok "the registry predecessor's pane is not recorded for closing" || fail "a pane was recorded: $(cat "$fleet/mission-control/alpha/successor")"
rm -f "$fleet/mission-control/alpha/successor"
run mission-control-launch.sh retire "$th_succ"

echo
if [ "$failures" -gt 0 ]; then
  echo "test-mc-handover-tmux: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-handover-tmux: all passed"
